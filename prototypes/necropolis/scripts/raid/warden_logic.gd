class_name WardenLogic
extends RefCounted
## Pure warden logic (MECHANICS 5.3, GAMEPLAY 3c): the spec built from raid.json `wardens`, beat
## maths, phase gates, slam ring, lunge hit and shield arc helpers. No scene-tree or autoload
## dependencies.
## Beats run on SCENE time (it slows with the trance's time scale), so callers pass elapsed scene
## seconds and the tempo length (pulse.json tempo_ms / 1000); nothing here reads the wall clock.

const DEFAULT_ARCHETYPE := "bellringer"


## Warden spec for a fort {id, tier, archetype?, first_dungeon?}: tier-scaled hp and, in the
## first dungeon, slower periods, softer damage and less hp. A deep copy; deterministic.
static func spec(fort: Dictionary, cfg: Dictionary) -> Dictionary:
	var w: Dictionary = cfg.get("wardens", {})
	var arche := str(fort.get("archetype", ""))
	if arche == "":
		arche = str((w.get("by_fort", {}) as Dictionary).get(str(fort.get("id", "")), DEFAULT_ARCHETYPE))
	var archs: Dictionary = w.get("archetypes", {})
	if not archs.has(arche):
		arche = DEFAULT_ARCHETYPE
	var a: Dictionary = (archs.get(arche, {}) as Dictionary).duplicate(true)
	var tier := maxi(1, int(fort.get("tier", 1)))
	var first := bool(fort.get("first_dungeon", false))
	var fd: Dictionary = w.get("first_dungeon", {})
	var hp := float(a.get("hp_base", 100.0)) + float(a.get("hp_per_tier", 0.0)) * tier
	var period_mult := 1.0
	var dmg_mult := 1.0
	if first:
		hp *= float(fd.get("hp_mult", 1.0))
		period_mult = float(fd.get("period_mult", 1.0))
		dmg_mult = float(fd.get("dmg_mult", 1.0))
	var phases: Array = a.get("phases", [])
	for ph in phases:
		ph["period_beats"] = float(ph.get("period_beats", 4.0)) * period_mult
	var attack: Dictionary = a.get("attack", {})
	for k in attack.keys():
		if str(k).begins_with("dmg_"):
			attack[k] = float(attack[k]) * dmg_mult
	return {"archetype": arche, "name": str(a.get("name", arche)), "tier": tier, "hp": hp,
		"radius": float(a.get("radius", 30.0)), "tells": a.get("tells", []).duplicate(),
		"weak_point": a.get("weak_point", {}), "phases": phases, "attack": attack,
		"first_dungeon": first}


# ------------------------------------------------------------------- beats ---
## Beats since the warden woke, from elapsed scene seconds.
static func beat_of(t_s: float, tempo_s: float) -> float:
	return t_s / maxf(tempo_s, 0.001)


## Where in the Pulse beat `now_ms` falls (0..1), for the sim: the wake aligns the warden's beat
## clock to it. Not Pulse.phase(), which reduced motion pins to a steady value (that would make the
## boss fight differ with the accessibility setting).
static func wake_phase(now_ms: float, tempo_ms: float) -> float:
	return fposmod(now_ms / maxf(tempo_ms, 1.0), 1.0)


## True while the telegraph shows: attack_beat - tell_beats <= beat < attack_beat.
static func is_tell(beat: float, attack_beat: float, tell_beats: float) -> bool:
	return beat >= attack_beat - tell_beats and beat < attack_beat


# ------------------------------------------------------------------ phases ---
## Phase index of an hp-phased warden (the Bellringer, the Shieldwall): the first phase whose
## until_hp_frac is below hp_frac, else the last.
static func bellringer_phase(sp: Dictionary, hp_frac: float) -> int:
	var phases: Array = sp.get("phases", [])
	for i in phases.size():
		if hp_frac > float(phases[i].get("until_hp_frac", 0.0)):
			return i
	return maxi(0, phases.size() - 1)


## Huntsman phase index from how many times Relish was caught; until_catches -1 is open-ended.
static func huntsman_phase(sp: Dictionary, catches: int) -> int:
	var phases: Array = sp.get("phases", [])
	for i in phases.size():
		var u := int(phases[i].get("until_catches", -1))
		if u < 0 or catches < u:
			return i
	return maxi(0, phases.size() - 1)


## Beats between attacks in a phase (index clamped).
static func period_beats(sp: Dictionary, phase: int) -> float:
	var phases: Array = sp.get("phases", [])
	if phases.is_empty():
		return 4.0
	return float(phases[clampi(phase, 0, phases.size() - 1)].get("period_beats", 4.0))


# ---------------------------------------------------------- bellringer ring ---
## The ring's radius `beats_since_slam` after the slam: linear to radius_px over ring_beats, then
## -1 (done). Negative time is 0.
static func slam_radius(sp: Dictionary, beats_since_slam: float) -> float:
	var at: Dictionary = sp.get("attack", {})
	var ring := maxf(float(at.get("ring_beats", 0.6)), 0.001)
	if beats_since_slam >= ring:
		return -1.0
	return float(at.get("radius_px", 360.0)) * maxf(beats_since_slam, 0.0) / ring


## The expanding band reached `dist` this frame: its leading edge (r + band/2) crossed it, so each
## target is hit once per slam over contiguous frames. On the first frame (r_prev <= 0) the whole
## band, including what already lies inside it, counts.
static func slam_crosses(dist: float, r_prev: float, r_now: float, band_px: float) -> bool:
	if r_now <= r_prev:
		return false
	var lo := -1.0 if r_prev <= 0.0 else r_prev + band_px * 0.5
	return dist > lo and dist <= r_now + band_px * 0.5


## Slam damage to "unit", "big" or "relish". Big undead are soaked by beef; muffled slams are
## scaled by the weak point's dmg_mult.
static func slam_damage(sp: Dictionary, target: String, beef: float, muffled: bool) -> float:
	var at: Dictionary = sp.get("attack", {})
	var d := float(at.get("dmg_relish", 0.0)) if target == "relish" else float(at.get("dmg_unit", 0.0))
	if target == "big":
		d *= maxf(float(at.get("min_soak", 0.3)), 1.0 - beef * float(at.get("soak_per_beef", 0.0)))
	if muffled:
		d *= float((sp.get("weak_point", {}) as Dictionary).get("dmg_mult", 1.0))
	return d


## Contacts are [{beef}]: big undead touching the bell. Muffled when any has beef >= threshold.
static func is_muffled(sp: Dictionary, contacts: Array) -> bool:
	var th := float((sp.get("weak_point", {}) as Dictionary).get("threshold", 1.0e9))
	for c in contacts:
		if float(c.get("beef", 0.0)) >= th:
			return true
	return false


# ------------------------------------------------------------ huntsman lunge ---
## Candidates are [{pos: Vector2, speed}]. The index of the candidate with speed >= the threshold
## within intercept_px of the from->to segment, nearest `from` along it; -1 if none.
static func lunge_interceptor(sp: Dictionary, from: Vector2, to: Vector2, candidates: Array) -> int:
	var wp: Dictionary = sp.get("weak_point", {})
	var th := float(wp.get("threshold", 1.0e9))
	var reach := float(wp.get("intercept_px", 0.0))
	var seg := to - from
	var len2 := seg.length_squared()
	var best := -1
	var best_t := INF
	for i in candidates.size():
		var c: Dictionary = candidates[i]
		if float(c.get("speed", 0.0)) < th:
			continue
		var p: Vector2 = c["pos"]
		var t := 0.0 if len2 <= 0.0 else clampf((p - from).dot(seg) / len2, 0.0, 1.0)
		if p.distance_to(from + seg * t) <= reach and t < best_t:
			best_t = t
			best = i
	return best


## Segment-circle test: the lunge from->to touches a circle at target_pos.
static func lunge_hits(from: Vector2, to: Vector2, target_pos: Vector2, hit_radius: float) -> bool:
	var seg := to - from
	var len2 := seg.length_squared()
	var t := 0.0 if len2 <= 0.0 else clampf((target_pos - from).dot(seg) / len2, 0.0, 1.0)
	return target_pos.distance_to(from + seg * t) <= hit_radius


## Where the Huntsman wants to be: on Relish while she is inside its room, else the room's centre.
static func leash_target(room: Rect2, relish_pos: Vector2) -> Vector2:
	return relish_pos if room.has_point(relish_pos) else room.get_center()


## A position clamped inside the room, `margin` px in from every edge (a room smaller than the
## margin collapses to its centre).
static func leash_clamp(room: Rect2, pos: Vector2, margin: float) -> Vector2:
	var inner := room.grow(-margin)
	if inner.size.x <= 0.0 or inner.size.y <= 0.0:
		return room.get_center()
	return Vector2(clampf(pos.x, inner.position.x, inner.end.x), clampf(pos.y, inner.position.y, inner.end.y))


## The locked lunge point: `aim` clipped to `range_px` along the line from `from`.
static func lunge_target(from: Vector2, aim: Vector2, range_px: float) -> Vector2:
	var d := aim - from
	if d.length() <= range_px:
		return aim
	return from + d.normalized() * range_px


## Where an intercepted lunge ends: the point of from->to nearest the interceptor.
static func lunge_stop(from: Vector2, to: Vector2, interceptor_pos: Vector2) -> Vector2:
	var seg := to - from
	var len2 := seg.length_squared()
	var t := 0.0 if len2 <= 0.0 else clampf((interceptor_pos - from).dot(seg) / len2, 0.0, 1.0)
	return from + seg * t


## Damage the Huntsman takes: the weak point's stun_dmg_mult while it is stunned.
static func stun_damage(sp: Dictionary, amount: float, stunned: bool) -> float:
	if not stunned:
		return amount
	return amount * float((sp.get("weak_point", {}) as Dictionary).get("stun_dmg_mult", 1.0))


## The bodyguard's post: `guard_px` from Relish toward the threat, guard `index` of `count` spread
## sideways across the line by `spread_px` steps (centred on the line).
static func guard_point(relish_pos: Vector2, threat_pos: Vector2, guard_px: float, index: int, count: int, spread_px: float) -> Vector2:
	var d := threat_pos - relish_pos
	var dir := d.normalized() if d.length() > 0.001 else Vector2.RIGHT
	var side := (float(index) - float(count - 1) * 0.5) * 2.0 * spread_px if count > 1 else 0.0
	return relish_pos + dir * guard_px + dir.orthogonal() * side


# ------------------------------------------------------------ hunting undead ---
## Who the Huntsman hunts: Relish while she stands in its room, else (hiding costs units) the undead
## nearest to `from` inside the room grown by `margin` (so one entering through a doorway counts).
## `units` are Vector2 positions. Returns {kind: "relish" | "undead" | "none", index, pos}; index is
## into `units` (-1 for Relish or none).
static func hunt_target(room: Rect2, relish_pos: Vector2, relish_alive: bool, units: Array, from: Vector2,
		margin: float) -> Dictionary:
	if relish_alive and room.has_point(relish_pos):
		return {"kind": "relish", "index": -1, "pos": relish_pos}
	var reach := room.grow(margin)
	var best := -1
	var bd := INF
	for i in units.size():
		var p: Vector2 = units[i]
		if not reach.has_point(p):
			continue
		var d := from.distance_to(p)
		if d < bd:
			bd = d
			best = i
	if best < 0:
		return {"kind": "none", "index": -1, "pos": Vector2.ZERO}
	return {"kind": "undead", "index": best, "pos": units[best]}


# -------------------------------------------------------------- shieldwall ---
## The Shieldwall's per-phase knobs (index clamped): {period_beats, turn_deg_s, front_half_deg}.
static func shield_phase(sp: Dictionary, phase: int) -> Dictionary:
	var phases: Array = sp.get("phases", [])
	var ph: Dictionary = {} if phases.is_empty() else phases[clampi(phase, 0, phases.size() - 1)]
	return {"period_beats": float(ph.get("period_beats", 4.0)), "turn_deg_s": float(ph.get("turn_deg_s", 45.0)),
		"front_half_deg": float(ph.get("front_half_deg", 70.0))}


## The signed smallest turn from angle `a` to angle `b`, in radians, in [-PI, PI).
static func angle_diff(a: float, b: float) -> float:
	return wrapf(b - a, -PI, PI)


## True when `at` stands inside the front arc of a wall at `from` facing `facing` (radians): within
## `half_deg` of the facing as seen from the wall's centre. A point on the centre counts as front.
static func in_front(facing: float, from: Vector2, at: Vector2, half_deg: float) -> bool:
	var d := at - from
	if d.length_squared() < 0.0001:
		return true
	return absf(angle_diff(facing, d.angle())) <= deg_to_rad(half_deg) + 0.000001


## One turn step: from `facing` toward `goal` by at most rate_deg_s x delta, never past it, wrapped
## to [-PI, PI).
static func turn_step(facing: float, goal: float, rate_deg_s: float, delta: float) -> float:
	var diff := angle_diff(facing, goal)
	var mx := deg_to_rad(maxf(0.0, rate_deg_s)) * maxf(0.0, delta)
	return wrapf(facing + clampf(diff, -mx, mx), -PI, PI)


## Where a strike from `at` lands on a wall at `from` facing `facing`: "front" inside the front arc
## (±front_half_deg: the shield), "back" inside the back arc (±back_half_deg round facing + PI: the
## open back), else "side". The front wins where the two would overlap.
static func shield_zone(facing: float, from: Vector2, at: Vector2, front_half_deg: float, back_half_deg: float) -> String:
	if in_front(facing, from, at, front_half_deg):
		return "front"
	return "back" if in_front(facing + PI, from, at, back_half_deg) else "side"


## A hit's damage multiplier by zone: the shield glances (attack.front_mult), the side lands in full,
## the open back takes the bonus (attack.back_mult).
static func shield_mult(sp: Dictionary, zone: String) -> float:
	var at: Dictionary = sp.get("attack", {})
	match zone:
		"front":
			return float(at.get("front_mult", 0.1))
		"back":
			return float(at.get("back_mult", 1.0))
	return 1.0


## Where the Shieldwall turns: the densest crowd of undead within `reach_px` of `from`. For each
## undead's bearing, count the undead within `half_deg` of it; the most wins, a tie goes to the
## bearing nearest the current `facing` (then the lower index), so an even ring holds still. The
## goal is the mean bearing of that sector's undead. `units` are Vector2 positions (the caller leaves
## the flank-role undead out: they keep to its back). {ok: false} when none is in reach.
static func shield_goal(from: Vector2, units: Array, reach_px: float, half_deg: float, facing: float) -> Dictionary:
	var angs: Array[float] = []
	var dirs: Array[Vector2] = []
	for p in units:
		var d: Vector2 = (p as Vector2) - from
		if d.length() <= reach_px and d.length_squared() > 0.0001:
			angs.append(d.angle())
			dirs.append(d.normalized())
	if angs.is_empty():
		return {"ok": false, "angle": facing, "count": 0}
	var half := deg_to_rad(half_deg) + 0.000001
	var best := -1
	var best_n := -1
	var best_off := INF
	for i in angs.size():
		var n := 0
		for j in angs.size():
			if absf(angle_diff(angs[i], angs[j])) <= half:
				n += 1
		var off := absf(angle_diff(facing, angs[i]))
		if n > best_n or (n == best_n and off < best_off - 0.000001):
			best = i
			best_n = n
			best_off = off
	var sum := Vector2.ZERO
	for j in angs.size():
		if absf(angle_diff(angs[best], angs[j])) <= half:
			sum += dirs[j]
	var ang := sum.angle() if sum.length() > 0.001 else angs[best]
	return {"ok": true, "angle": ang, "count": best_n}


## The bash reaches a target of radius `r` at `at`: inside the front arc and within reach_px (+ r)
## of the wall's centre.
static func bash_hits(facing: float, from: Vector2, at: Vector2, half_deg: float, reach_px: float, r: float) -> bool:
	return at.distance_to(from) <= reach_px + r and in_front(facing, from, at, half_deg)


## Where a bashed target lands: `at` pushed shove_px straight away from the wall (along the facing
## when it stands on the centre).
static func shove_point(facing: float, from: Vector2, at: Vector2, shove_px: float) -> Vector2:
	var d := at - from
	var dir := d.normalized() if d.length() > 0.001 else Vector2.RIGHT.rotated(facing)
	return at + dir * shove_px


## A big undead takes the flank role when its wits meet the weak point's threshold.
static func is_flanker(sp: Dictionary, wits: float) -> bool:
	var wp: Dictionary = sp.get("weak_point", {})
	return str(wp.get("effect", "")) == "flank" and wits >= float(wp.get("threshold", 1.0e9))


## The bearing of flanker `index` of `count`'s post: straight behind the wall (facing + PI), the
## flankers spread by `spread_deg` steps centred on it.
static func flank_angle(facing: float, index: int, count: int, spread_deg: float) -> float:
	var side := (float(index) - float(count - 1) * 0.5) * deg_to_rad(spread_deg) if count > 1 else 0.0
	return wrapf(facing + PI + side, -PI, PI)


## Where a flanker at `pos` walks next toward its post at bearing `post_angle` on the circle of
## `orbit_px` round the wall at `from`: the post itself once its own bearing is within `step_deg`,
## else the orbit point `step_deg` round from its bearing the shorter way (so it walks round the
## wall, never through it).
static func flank_step(from: Vector2, pos: Vector2, post_angle: float, orbit_px: float, step_deg: float) -> Vector2:
	var d := pos - from
	var cur := d.angle() if d.length_squared() > 0.0001 else post_angle
	var diff := angle_diff(cur, post_angle)
	var stp := deg_to_rad(maxf(1.0, step_deg))
	var ang := post_angle if absf(diff) <= stp else cur + signf(diff) * stp
	return from + Vector2(orbit_px, 0).rotated(ang)


## The HUD's shield line for a phase, from the spec: "front ±80° glances ×0.1 · back ×2.5 · turns
## 40°/s · bash every 4 beats" (arc, turn rate and period per phase; the multipliers from the attack).
static func shield_label(sp: Dictionary, phase: int) -> String:
	var ph := shield_phase(sp, phase)
	var at: Dictionary = sp.get("attack", {})
	return "front ±%d° glances ×%s · back ×%s · turns %d°/s · bash every %s beats" % [roundi(ph["front_half_deg"]),
		_num(float(at.get("front_mult", 0.1))), _num(float(at.get("back_mult", 1.0))), roundi(ph["turn_deg_s"]), _num(ph["period_beats"])]


static func _num(v: float) -> String:
	return str(int(v)) if is_equal_approx(v, roundf(v)) else str(snappedf(v, 0.01))


# ---------------------------------------------------------- slam window (bot) ---
## True when a player can stay inside the Bellringer's slam reach and still be out before the next
## tell: the beats until the tell starts (negative while a slam is in flight), less the walk out
## (`exit_px` at `speed_px_s`, in beats), must exceed `safe_beats`.
static func slam_window_open(beats_to_tell: float, exit_px: float, speed_px_s: float, tempo_s: float,
		safe_beats: float) -> bool:
	var exit_beats := maxf(0.0, exit_px) / maxf(1.0, speed_px_s) / maxf(0.001, tempo_s)
	return beats_to_tell - exit_beats > safe_beats


# ------------------------------------------------------------ break meter ---
## The break meter is pips, never a percent (VISUAL-LANGUAGE law 9): the warden's remaining
## strength. An hp-phased warden (every phase has until_hp_frac: the Bellringer) gets one segment
## per phase, and each segment's pips count down through that phase's hp band, so a notch is
## crossed on exactly the hit that changes bellringer_phase. A warden phased by anything else (the
## Huntsman: catches) gets one flat segment and no notches on its strength.
## The hp band edges, highest first: [1.0, 0.66, 0.33, 0.0] for the Bellringer, [1.0, 0.0] else.
static func meter_bands(sp: Dictionary) -> Array[float]:
	var out: Array[float] = [1.0]
	var phases: Array = sp.get("phases", [])
	var hp_phased := phases.size() > 1
	for ph in phases:
		hp_phased = hp_phased and (ph as Dictionary).has("until_hp_frac")
	if hp_phased:
		for i in phases.size() - 1:
			out.append(clampf(float(phases[i]["until_hp_frac"]), 0.0, 1.0))
	out.append(0.0)
	return out


## Pips per segment: `total` shared evenly over the bands (at least 1).
static func meter_per_band(bands: Array, total: int) -> int:
	return maxi(1, roundi(float(total) / float(maxi(1, bands.size() - 1))))


## Lit pips (the strength left) at `hp_frac`: a band hp is above is full, one it is below is
## empty, and the band it is in shows the ceiling of its share left. 0 only at hp_frac <= 0.
static func meter_lit(bands: Array, per_band: int, hp_frac: float) -> int:
	var lit := 0
	for j in bands.size() - 1:
		var hi := float(bands[j])
		var lo := float(bands[j + 1])
		if hp_frac >= hi:
			lit += per_band
		elif hp_frac > lo:
			lit += clampi(ceili((hp_frac - lo) / maxf(0.000001, hi - lo) * per_band - 0.000001), 1, per_band)
	return lit


## Phase notches on the strength meter, as pip counts from the empty end ([4, 8] at 4 a band).
static func meter_notches(bands: Array, per_band: int) -> Array[int]:
	var out: Array[int] = []
	for j in range(1, bands.size() - 1):
		out.append(per_band * j)
	return out


## The Huntsman's phases are its catches: the until_catches of each bounded phase, ascending
## ([2, 4]); [] for a warden not phased by catches.
static func catch_notches(sp: Dictionary) -> Array[int]:
	var out: Array[int] = []
	for ph in sp.get("phases", []):
		var u := int((ph as Dictionary).get("until_catches", -1))
		if u > 0:
			out.append(u)
	out.sort()
	return out


## What a Huntsman catch costs and where it bites, for the CAUGHT track's label: Relish loses
## `dmg_relish` hp per catch (spec.attack, already scaled for the first dungeon; a lethal catch is
## taken by an ally in her place) and the phases turn faster at each notch. "" for a warden with no
## catch notches.
static func catch_label(sp: Dictionary) -> String:
	var n := catch_notches(sp)
	if n.is_empty():
		return ""
	var dmg := roundi(float((sp.get("attack", {}) as Dictionary).get("dmg_relish", 0.0)))
	var at := ""
	for i in n.size():
		at += ("" if i == 0 else (" and " if i == n.size() - 1 else ", ")) + str(n[i])
	return "each catch costs Relish %d hp (an ally takes a killing one) · it hunts faster at %s catches" % [dmg, at]


## Slots on the CAUGHT track: the last notch plus two, so the open-ended last phase shows too.
static func catch_slots(sp: Dictionary) -> int:
	var n := catch_notches(sp)
	return 0 if n.is_empty() else int(n[n.size() - 1]) + 2
