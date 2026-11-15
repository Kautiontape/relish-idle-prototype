class_name WardenLogic
extends RefCounted
## Pure warden logic (MECHANICS 5.3, GAMEPLAY 3c): the spec built from raid.json `wardens`, beat
## maths, phase gates, slam ring, lunge hit, shield arc and pyre (acolytes, ward, burn areas)
## helpers. No scene-tree or autoload dependencies.
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
	# D-d/E Step 4, the risk lever candidates (wardens.lever_min_tier up, never the first dungeon):
	# attack_dmg_mult on all of its attack's damage (to her undead and to Relish), relish_dmg_mult on its
	# damage to Relish only. 1.0 each leaves every spec as it was.
	var lever := lever_on(tier, first, w)
	var all_m := float(w.get("attack_dmg_mult", 1.0)) if lever else 1.0
	var rel_m := float(w.get("relish_dmg_mult", 1.0)) if lever else 1.0
	for k in attack.keys():
		if str(k).begins_with("dmg_"):
			attack[k] = float(attack[k]) * dmg_mult
			if lever:
				attack[k] = float(attack[k]) * all_m * (rel_m if str(k) == "dmg_relish" else 1.0)
	var out := {"archetype": arche, "name": str(a.get("name", arche)), "tier": tier, "hp": hp,
		"radius": float(a.get("radius", 30.0)), "tells": a.get("tells", []).duplicate(),
		"weak_point": a.get("weak_point", {}), "phases": phases, "attack": attack,
		"first_dungeon": first}
	var pk := pack_spec(a.get("pack", {}), tier, first)
	if not pk.is_empty():
		pk["weak"] = {"stat": str((a.get("weak_point", {}) as Dictionary).get("stat", "")),
			"threshold": float((a.get("weak_point", {}) as Dictionary).get("threshold", 0.0))}
		out["pack"] = pk   # no key at all below its tier or in the first dungeon: those specs stay as they were
	return out


# -------------------------------------------------------------------- pack ---
## D-d/E Step 3, a warden's pack (`archetypes.<id>.pack`, the Huntsman's hounds): from `min_tier` up and
## never in the first dungeon, at each hp gate in `at_hp_frac` it sounds a horn (`horn_beats` ahead, on
## the beat) and calls `size_by_tier` of its own living (`kind`) into its room's far side from Relish.
## While any of them stands it takes `ward_mult` of every hit and holds its own attack (one threat at a
## time). Its pack drops nothing: no mass, no motes, no dings (like the acolytes; a pack that fed the
## raises would shorten the fight it is there to lengthen). {} when it has none here.
static func pack_spec(pk: Dictionary, tier: int, first: bool) -> Dictionary:
	if pk.is_empty() or first or tier < int(pk.get("min_tier", 99)):
		return {}
	var out := pk.duplicate(true)
	out.erase("_doc")
	out["size"] = int((pk.get("size_by_tier", {}) as Dictionary).get(str(clampi(tier, 1, 4)), 0))
	return out


## True when the hp gate after the `horns` already sounded is reached (hp_frac at or below it).
static func pack_due(pk: Dictionary, hp_frac: float, horns: int) -> bool:
	var gates: Array = pk.get("at_hp_frac", [])
	return int(pk.get("size", 0)) > 0 and horns < gates.size() and hp_frac <= float(gates[horns])


## The share of a hit the warden takes while `alive` of its pack stand (1.0 with none, or no pack).
static func pack_ward(pk: Dictionary, alive: int) -> float:
	return float(pk.get("ward_mult", 1.0)) if alive > 0 and not pk.is_empty() else 1.0


## Where the pack comes in: `n` points on the far side of `room` from `away` (Relish), split between
## the two inset corners farthest from her, each corner's run `spread` px apart toward the room's centre. No rng.
static func pack_spots(room: Rect2, away: Vector2, n: int, inset: float, spread: float) -> Array[Vector2]:
	var out: Array[Vector2] = []
	if n <= 0:
		return out
	var r := room.grow(-minf(inset, minf(room.size.x, room.size.y) * 0.4))
	var cs: Array[Vector2] = [r.position, Vector2(r.end.x, r.position.y), Vector2(r.position.x, r.end.y), r.end]
	cs.sort_custom(func(p: Vector2, q: Vector2) -> bool:
		var dp := p.distance_to(away)
		var dq := q.distance_to(away)
		if absf(dp - dq) > 0.001:
			return dp > dq
		return p.x < q.x or (p.x == q.x and p.y < q.y))
	for i in n:
		var c: Vector2 = cs[i % 2]
		var k := i / 2
		var p := c + (r.get_center() - c).normalized() * spread * float(k)
		out.append(Vector2(clampf(p.x, r.position.x, r.end.x), clampf(p.y, r.position.y, r.end.y)))
	return out


## D-d/E 3c: a pack never turns on Relish. With no undead standing, a pack that stands or is being called
## (its horn sounding) breaks: it leaves the fight and the ward drops.
static func pack_breaks(standing: int, horn_up: bool, undead_standing: bool) -> bool:
	return (standing > 0 or horn_up) and not undead_standing


## The pack's counter (D-d/E Step 3b): a big undead whose stat meets the warden's own weak point (beef,
## speed, wits or power, `weak_point.stat` >= `threshold`) kills a pack unit in one blow, and while a pack
## stands it goes for the nearest of them. False with no pack.
static func pack_breaker(sp: Dictionary, stat_value: float) -> bool:
	if not sp.has("pack"):
		return false
	return stat_value >= float((sp.get("weak_point", {}) as Dictionary).get("threshold", 1.0e9))


## The verb a pack unit's one-blow death shows, the warden's own weak point's: MUFFLED, INTERCEPTED,
## FLANKED or SNUFFED.
static func pack_verb(sp: Dictionary) -> String:
	match str((sp.get("weak_point", {}) as Dictionary).get("effect", "")):
		"muffle":
			return "MUFFLED"
		"intercept":
			return "INTERCEPTED"
		"flank":
			return "FLANKED"
		"snuff":
			return "SNUFFED"
	return "BROKEN"


## The HUD's pack row before and between packs, from the spec: "at 2/3 and 1/3 of its strength it calls
## 5 hounds · it is warded while they run" ("" with no pack).
static func pack_teach(pk: Dictionary) -> String:
	if pk.is_empty():
		return ""
	var gates: PackedStringArray = []
	for g in pk.get("at_hp_frac", []):
		gates.append(_frac_word(float(g)))
	var wp: Dictionary = sp_weak(pk)
	var tail := "" if wp.is_empty() else " · %s %s kills one in a blow" % [str(wp.get("stat", "")), str(snappedf(float(wp.get("threshold", 0.0)), 0.1))]
	return "at %s of its strength it calls %d %s · it is warded while they run%s" % [" and ".join(gates), int(pk.get("size", 0)), str(pk.get("name", "pack")), tail]


## The weak point a pack spec carries for its teach row (WardenLogic.spec copies it in as `weak`).
static func sp_weak(pk: Dictionary) -> Dictionary:
	return pk.get("weak", {})


static func _frac_word(f: float) -> String:
	for q in [[2, 3], [1, 3], [1, 2], [3, 4], [1, 4]]:
		if absf(f - float(q[0]) / float(q[1])) < 0.02:
			return "%d/%d" % q
	return "%d%%" % roundi(f * 100.0)


## The HUD's pack row: "HOUNDS 3 of 5 · it takes ×0.25" while they run, "" otherwise.
static func pack_label(pk: Dictionary, alive: int, n: int) -> String:
	if pk.is_empty() or alive <= 0:
		return ""
	return "%s %d of %d · it takes ×%s" % [str(pk.get("name", "PACK")).to_upper(), alive, n, str(snappedf(float(pk.get("ward_mult", 1.0)), 0.01))]


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


## Whether the Shieldwall may turn at `beat`: not through its tell, and not on the bash frame itself
## (beat >= attack_beat), so the bash lands where the lit arc showed.
static func shield_turns(beat: float, attack_beat: float, tell_beats: float) -> bool:
	return beat < attack_beat and not is_tell(beat, attack_beat, tell_beats)


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
## scaled by the weak point's dmg_mult for the undead, and do not reach Relish at all (D-d/E Step 4b:
## the counter is the soak; the chain no longer soaks a slam).
static func slam_damage(sp: Dictionary, target: String, beef: float, muffled: bool) -> float:
	if target == "relish" and muffled:
		return 0.0
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


## D-d/E Step 4.1, the rush's reach: the bash's `base` plus `rush_px`, but never beyond `frac` of the
## warden room's half-size (`room_half`, its shorter side), so a small room keeps a ring she can stand in
## (pale-bastion's room is 543 px across: a 260 px rush covered nearly all of it). Never below the bash's
## own reach; `frac` 0 means no cap.
static func rush_reach(base: float, rush_px: float, room_half: float, frac: float) -> float:
	var r := base + rush_px
	if frac > 0.0:
		r = minf(r, room_half * frac)
	return maxf(base, r)


## D-d/E Step 4b, the Bellringer's toll: as a slam's tell begins it marks a ring of `toll_r` where Relish
## stands (`toll_at`); on the slam it strikes her if she is still in it, unless the bell is muffled (the counter
## spares her) or she stands where the slam's own ring will reach her anyway (`in_ring`: no second blow).
static func toll_strikes(rel_pos: Vector2, toll_at: Vector2, toll_r: float, rel_r: float, muffled: bool, in_ring: bool) -> bool:
	if muffled or in_ring or toll_at == Vector2.INF or toll_r <= 0.0:
		return false
	return rel_pos.distance_to(toll_at) <= toll_r + rel_r


## D-d/E Step 4b, where a toll may land: from her spot `pos`, the way away from the bell (`bell`) must have
## floor inside the room for her to step out of the ring (toll_r + her radius) and the toll radius more
## beyond it (the corner case: a toll she could not step out of). Measured along the ray to the room's edge.
static func toll_room_ok(room: Rect2, pos: Vector2, bell: Vector2, toll_r: float, rel_r: float) -> bool:
	var dir := pos - bell
	if dir.length() < 1.0:
		return false
	dir = dir.normalized()
	var t := INF
	if dir.x > 1e-6:
		t = minf(t, (room.end.x - pos.x) / dir.x)
	elif dir.x < -1e-6:
		t = minf(t, (room.position.x - pos.x) / dir.x)
	if dir.y > 1e-6:
		t = minf(t, (room.end.y - pos.y) / dir.y)
	elif dir.y < -1e-6:
		t = minf(t, (room.position.y - pos.y) / dir.y)
	return t - rel_r >= 2.0 * toll_r + rel_r


## D-d/E Step 4b, the Shieldwall's aimed rush: its lane reaches to the warden room's farthest corner from
## the wall (anywhere she can stand in its room).
static func lane_reach(room: Rect2, from: Vector2) -> float:
	var r := 0.0
	for c in [room.position, Vector2(room.end.x, room.position.y), Vector2(room.position.x, room.end.y), room.end]:
		r = maxf(r, from.distance_to(c))
	return r


## D-d/E Step 4 / 4b, the risk gate: the lever and the tell-attacks' bypass of the sacrifice chain apply from
## `wardens.lever_min_tier` up and never in the first dungeon (`w` is raid.json `wardens`).
static func lever_on(tier: int, first: bool, w: Dictionary) -> bool:
	return not first and tier >= int(w.get("lever_min_tier", 2))


## D-d/E Step 4b: a bash whose lit arc covers her strikes Relish (the chain does not soak it). A wits
## flanker's pin is the counter to the rush only: it stops the rush, and the plain bash it leaves still
## strikes her in its arc (round 3: the manager's ruling named the pin as the rush's counter, no more).
static func bash_strikes_relish(in_arc: bool) -> bool:
	return in_arc


## A big undead takes the flank role when its wits meet the weak point's threshold.
## D-d/E 3b, the Shieldwall's rush: a wits flanker pins it when it stands within `max_d` of the wall and
## off the shield's front (outside ±`half_deg` of the facing). `pts` are the wits big undead's positions.
static func shield_pinned(facing: float, wp: Vector2, half_deg: float, pts: Array, max_d: float) -> bool:
	for p in pts:
		if (p as Vector2).distance_to(wp) <= max_d and not in_front(facing, wp, p, half_deg):
			return true
	return false


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


# ------------------------------------------------------------- pyre-priest ---
## The Pyre-priest's acolytes at its tier: attack.acolytes_base + acolytes_per_tier x tier, never
## below 0.
static func acolyte_count(sp: Dictionary) -> int:
	var at: Dictionary = sp.get("attack", {})
	return maxi(0, roundi(float(at.get("acolytes_base", 0.0)) + float(at.get("acolytes_per_tier", 1.0)) * float(sp.get("tier", 1))))


## Where the acolytes stand: `n` posts `ring_px` from the priest at `center`, on the side away from
## `entry` (where the swarm comes in), spread evenly over `arc_deg` centred on that bearing (one post
## sits straight behind). The caller keeps them inside the room.
static func acolyte_posts(center: Vector2, entry: Vector2, n: int, ring_px: float, arc_deg: float) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var away := center - entry
	var base := away.angle() if away.length_squared() > 0.0001 else -PI * 0.5
	for i in n:
		var off := 0.0 if n <= 1 else (float(i) / float(n - 1) - 0.5) * deg_to_rad(arc_deg)
		out.append(center + Vector2(ring_px, 0).rotated(base + off))
	return out


## Damage multiplier on the priest: attack.ward_mult while any acolyte lives (it is warded), else 1.
static func ward_mult(sp: Dictionary, living: int) -> float:
	return float((sp.get("attack", {}) as Dictionary).get("ward_mult", 1.0)) if living > 0 else 1.0


## A big undead snuffs an acolyte in one blow (and takes the acolyte-hunting role) when its power
## meets the weak point's threshold.
static func is_snuffer(sp: Dictionary, power: float) -> bool:
	var wp: Dictionary = sp.get("weak_point", {})
	return str(wp.get("effect", "")) == "snuff" and power >= float(wp.get("threshold", 1.0e9))


## The index of the point nearest `from` (a tie goes to the lower index); -1 for none.
static func nearest_index(from: Vector2, pts: Array) -> int:
	var best := -1
	var bd := INF
	for i in pts.size():
		var d := from.distance_to(pts[i] as Vector2)
		if d < bd - 0.000001:
			bd = d
			best = i
	return best


## The Pyre-priest's phase: 0 while any acolyte lives (whatever its hp); once the last falls, the
## first later phase whose until_hp_frac is below hp_frac, else the last. A priest whose hp crossed a
## later gate while still warded steps straight to that phase when it is exposed.
static func pyre_phase(sp: Dictionary, living: int, hp_frac: float) -> int:
	var phases: Array = sp.get("phases", [])
	if living > 0 or phases.size() <= 1:
		return 0
	for i in range(1, phases.size()):
		if hp_frac > float(phases[i].get("until_hp_frac", 0.0)):
			return i
	return phases.size() - 1


## The phase's knobs (index clamped): {period_beats, burn_radius_px, areas}.
static func pyre_phase_knobs(sp: Dictionary, phase: int) -> Dictionary:
	var phases: Array = sp.get("phases", [])
	var ph: Dictionary = {} if phases.is_empty() else phases[clampi(phase, 0, phases.size() - 1)]
	return {"period_beats": float(ph.get("period_beats", 4.0)), "burn_radius_px": float(ph.get("burn_radius_px", 80.0)),
		"areas": int(ph.get("areas", 1))}


## Burn areas per beat: the phase's own (`areas`) plus attack.areas_per_acolyte for each living
## acolyte beyond the first, so each acolyte that falls takes a fire away.
static func burn_count(sp: Dictionary, phase: int, living: int) -> int:
	var per := int((sp.get("attack", {}) as Dictionary).get("areas_per_acolyte", 1))
	return maxi(0, int(pyre_phase_knobs(sp, phase)["areas"]) + per * maxi(0, living - 1))


## How many of a beat's areas the acolytes aim at Relish (while she is in reach): the areas they
## add (burn_count less the phase's own), at most attack.relish_areas_max.
static func burn_aim_relish(sp: Dictionary, phase: int, living: int) -> int:
	var extra := burn_count(sp, phase, living) - int(pyre_phase_knobs(sp, phase)["areas"])
	return clampi(extra, 0, maxi(0, int((sp.get("attack", {}) as Dictionary).get("relish_areas_max", 99))))


## Greedy burn centres: up to `n` picks from `cands` (Vector2) weighted by `weights`. Each pick is
## the candidate whose circle of `radius` covers the most weight not yet covered (a tie goes to the
## candidate nearest `from`, then the lower index); what it covers is then spent. Stops early when
## nothing is left to cover. Deterministic for a given order.
static func burn_pick(cands: Array, weights: Array, radius: float, from: Vector2, n: int) -> Array[Vector2]:
	var w: Array[float] = []
	for x in weights:
		w.append(float(x))
	var out: Array[Vector2] = []
	var r2 := radius * radius + 0.0001
	for k in n:
		var best := -1
		var best_s := 0.0
		var best_d := INF
		for i in cands.size():
			var ci: Vector2 = cands[i]
			var s := 0.0
			for j in cands.size():
				if w[j] > 0.0 and ci.distance_squared_to(cands[j] as Vector2) <= r2:
					s += w[j]
			if s <= 0.0:
				continue
			var d := from.distance_to(ci)
			if s > best_s + 0.000001 or (absf(s - best_s) <= 0.000001 and d < best_d - 0.000001):
				best = i
				best_s = s
				best_d = d
		if best < 0:
			break
		var c: Vector2 = cands[best]
		out.append(c)
		for j in cands.size():
			if c.distance_squared_to(cands[j] as Vector2) <= r2:
				w[j] = 0.0
	return out


## Where the acolytes' `n` areas land on Relish at `rel`: the first on her, each other one
## `spread_px` from her, spaced evenly round her starting from the bearing away from the priest at
## `from`. Stepping off means leaving all of them.
static func relish_spots(rel: Vector2, from: Vector2, n: int, spread_px: float) -> Array[Vector2]:
	var out: Array[Vector2] = []
	if n <= 0:
		return out
	out.append(rel)
	var away := rel - from
	var dir := away.normalized() if away.length_squared() > 0.0001 else Vector2.RIGHT
	for k in range(1, n):
		out.append(rel + dir.rotated(TAU * float(k - 1) / float(n - 1)) * spread_px)
	return out


## One burn beat's area centres, deterministic. `field`: {motes: Array (Vector2: loose essence on the
## floor), piles: Array (Vector2: unstirred corpse piles), relish: Vector2 (Vector2.INF when she is
## out of reach), aim: bool (this beat one fire goes on her even with no acolyte left)}, each already
## filtered to the priest's room and reach. The acolytes' areas
## (burn_aim_relish) go on Relish while she is in reach; every other area goes on the densest essence
## or corpses (a pile weighs attack.pile_weight motes). Fewer areas when nothing is left to burn.
static func burn_plan(sp: Dictionary, phase: int, living: int, from: Vector2, field: Dictionary) -> Array[Vector2]:
	var at: Dictionary = sp.get("attack", {})
	var n := burn_count(sp, phase, living)
	var r := float(pyre_phase_knobs(sp, phase)["burn_radius_px"])
	var rel: Vector2 = field.get("relish", Vector2.INF)
	var n_rel := burn_aim_relish(sp, phase, living) if rel != Vector2.INF else 0
	if bool(field.get("aim", false)) and rel != Vector2.INF and n_rel < 1:
		n_rel = 1   # D-d/E Step 4b: on an aimed beat one of its own fires goes on her (attack.relish_area_every)
		n = maxi(n, 1)
	var cands: Array = []
	var weights: Array = []
	for m in field.get("motes", []):
		cands.append(m)
		weights.append(1.0)
	for p in field.get("piles", []):
		cands.append(p)
		weights.append(float(at.get("pile_weight", 2.0)))
	var out := burn_pick(cands, weights, r, from, n - n_rel)
	out.append_array(relish_spots(rel, from, n_rel, float(at.get("relish_spread_px", 60.0))))
	return out


## True when a target of radius `r` at `p` touches any burn area (centres `areas`, radius `burn_r`).
static func in_burn(p: Vector2, areas: Array, burn_r: float, r: float) -> bool:
	for c in areas:
		if p.distance_to(c as Vector2) <= burn_r + r:
			return true
	return false


## A corpse pile's mass after a burn: it loses `frac` of it, and burns away (0) below `min_mass`.
static func pile_after_burn(mass: float, frac: float, min_mass: float) -> float:
	var m := maxf(0.0, mass) * (1.0 - clampf(frac, 0.0, 1.0))
	return 0.0 if m < min_mass else m


## The Pyre-priest's break meter: `total` pips, `per` for each acolyte (the right-hand band: the
## first to go, one band per acolyte), the rest for its hp split at the last phase's gate (phases[1]
## until_hp_frac). {hp_bands, hp_per, hp_pips, aco, per, n, notches}: notches between the two hp
## bands and between the hp and the acolytes' pips.
static func pyre_meter(sp: Dictionary, total: int, per: int) -> Dictionary:
	var aco := acolyte_count(sp)
	var p := maxi(1, per)
	var phases: Array = sp.get("phases", [])
	var bands: Array[float] = [1.0]
	if phases.size() >= 3:
		bands.append(clampf(float(phases[1].get("until_hp_frac", 0.0)), 0.0, 1.0))
	bands.append(0.0)
	var hp_bands := bands.size() - 1
	var hp_per := maxi(1, floori(float(maxi(hp_bands, total - aco * p)) / float(hp_bands)))
	var hp_pips := hp_per * hp_bands
	var notches: Array[int] = []
	for j in range(1, hp_bands):
		notches.append(hp_per * j)
	if aco > 0:
		notches.append(hp_pips)
	return {"hp_bands": bands, "hp_per": hp_per, "hp_pips": hp_pips, "aco": aco, "per": p, "n": hp_pips + aco * p, "notches": notches}


## Lit pips on the Pyre-priest's meter: its hp's share (meter_lit over the hp bands) plus `per` for
## each living acolyte.
static func pyre_meter_lit(m: Dictionary, living: int, hp_frac: float) -> int:
	return meter_lit(m["hp_bands"], int(m["hp_per"]), hp_frac) + clampi(living, 0, int(m["aco"])) * int(m["per"])


## Whether pip `i` of the Pyre-priest's meter is lit. The hp pips `[0, hp_pips)` light as a prefix
## of its hp share; the acolytes' pips `[hp_pips, n)` as a prefix of `living` bands of `per`. So hp
## lost through the ward never darkens an acolyte's pip.
static func pyre_pip_lit(m: Dictionary, i: int, living: int, hp_frac: float) -> bool:
	var hp_pips := int(m["hp_pips"])
	if i < hp_pips:
		return i < meter_lit(m["hp_bands"], int(m["hp_per"]), hp_frac)
	return i - hp_pips < clampi(living, 0, int(m["aco"])) * int(m["per"])


## The pips a snuff takes: acolytes' pips `[lo, hi)` going from `before` living to `after`
## (the right-hand bands, past the hp pips).
static func pyre_snuff_pips(m: Dictionary, before: int, after: int) -> Vector2i:
	var hp_pips := int(m["hp_pips"])
	var per := int(m["per"])
	var aco := int(m["aco"])
	return Vector2i(hp_pips + clampi(after, 0, aco) * per, hp_pips + clampi(before, 0, aco) * per)


## The HUD's pyre line from the spec: "warded ×0.2 · 3 fires every 4 beats, 2 at Relish" while
## acolytes live, "exposed · 1 fire every 3 beats" once they are gone.
static func pyre_label(sp: Dictionary, phase: int, living: int) -> String:
	var k := pyre_phase_knobs(sp, phase)
	var n := burn_count(sp, phase, living)
	var fires := "%d fire%s every %s beats" % [n, "" if n == 1 else "s", _num(float(k["period_beats"]))]
	if living <= 0:
		return "exposed · " + fires
	var at_rel := burn_aim_relish(sp, phase, living)
	return "warded ×%s · %s%s" % [_num(ward_mult(sp, living)), fires, "" if at_rel <= 0 else ", %d at Relish" % at_rel]


## Where Relish steps to leave the lit burn areas: the nearest point that is `clear` px (her radius
## and a margin) outside every area and inside `room` grown in by `margin`. Tried: straight out from
## the centre of each area that covers her, and 16 headings round her at one and two areas' width.
## `pos` itself when no area covers her; when no candidate is clear, the one inside the fewest
## areas (then the nearest).
static func burn_exit(pos: Vector2, areas: Array, burn_r: float, clear: float, room: Rect2, margin: float) -> Vector2:
	if not in_burn(pos, areas, burn_r, clear):
		return pos
	var inner := room.grow(-margin) if room.size != Vector2.ZERO else Rect2()
	var cands: Array[Vector2] = []
	for c in areas:
		var d: Vector2 = pos - (c as Vector2)
		var dir := d.normalized() if d.length_squared() > 0.0001 else Vector2.RIGHT
		cands.append((c as Vector2) + dir * (burn_r + clear + 1.0))
	for s in [1.0, 2.0]:
		for k in 16:
			cands.append(pos + Vector2((burn_r + clear) * s, 0).rotated(TAU * float(k) / 16.0))
	var best := pos
	var best_in := 1 << 30
	var best_d := INF
	for p in cands:
		var q := p
		if inner.size.x > 0.0 and inner.size.y > 0.0:
			q = Vector2(clampf(p.x, inner.position.x, inner.end.x), clampf(p.y, inner.position.y, inner.end.y))
		var n_in := 0
		for c in areas:
			if q.distance_to(c as Vector2) <= burn_r + clear:
				n_in += 1
		var d2 := pos.distance_to(q)
		if n_in < best_in or (n_in == best_in and d2 < best_d - 0.000001):
			best = q
			best_in = n_in
			best_d = d2
	return best


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
	elif sp.has("pack"):
		# a warden phased otherwise (the Huntsman, by catches) is notched where its horn sounds
		for g in (sp["pack"] as Dictionary).get("at_hp_frac", []):
			out.append(clampf(float(g), 0.0, 1.0))
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
