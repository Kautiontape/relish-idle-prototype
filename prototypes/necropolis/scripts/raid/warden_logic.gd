class_name WardenLogic
extends RefCounted
## Pure warden logic (MECHANICS 5.3, GAMEPLAY 3c): the spec built from raid.json `wardens`, beat
## maths, phase gates, slam ring and lunge hit helpers. No scene-tree or autoload dependencies.
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


## True while the telegraph shows: attack_beat - tell_beats <= beat < attack_beat.
static func is_tell(beat: float, attack_beat: float, tell_beats: float) -> bool:
	return beat >= attack_beat - tell_beats and beat < attack_beat


# ------------------------------------------------------------------ phases ---
## Bellringer phase index: the first phase whose until_hp_frac is below hp_frac, else the last.
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
