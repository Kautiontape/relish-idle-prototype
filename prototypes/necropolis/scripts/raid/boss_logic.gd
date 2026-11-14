class_name BossLogic
extends RefCounted
## Vei's final test, the boss scene's pure maths (no autoloads, no Engine, no scene tree): lane
## geometry, stream and guard-line sizes, anchor placement, beat bookkeeping, guard and mote
## accrual, weave geometry, the seed's fronts and the demo seed. The rules of the fight are
## VeiFronts'; this file only places, counts and steps. Every function is static, takes its numbers
## from `cfg` (configs/vei.json, passed in) and never mutates its arguments.
##
## lanes(size, wall_t, court, cfg) -> Array[{id, a, b}]   one per front (FRONT_IDS order, west to
##   east): a = the south start, b = the end at Vei's court (court_r_px from her).
## point_at(lane, s), lane_len(lane), lane_dir(lane)        s in 0..1 from a to b.
## contact_s(progress, cfg)        where the stream meets the guard line (guard_s0 -> guard_s1).
## stream_count(have, cfg), guard_rows(need, cfg)    the stream's glyphs and the guard line's rows.
## stream_s(count, s_end, len_px, march_px)    lane fractions of `count` evenly spaced glyphs on
##   0..s_end, shifted forward by march_px (wrapping), so a moving offset marches them.
## seg_dist(p, a, b), seg_t(p, a, b), nearest_lane(p, lanes)    the lane a raise feeds.
## anchors(lanes, cfg) -> Array[Vector2]    phase-2 anchors between the lanes at lane_s.
## beat_of(t, tempo_s), beats_crossed(b0, b1), align_t(pulse_phase, tempo_s)    the beat clock:
##   align_t is the clock start that puts beat 0 on the next tempo boundary.
## ferry_per_beat(ferry, tempo_s, cfg)    F * tempo_s * ferry_beat_scale (the break's comparison).
## horde_step(h, ferry, dt), backlog_spent(h0, h)    the horde pool; spent is never negative.
## accrue(acc, rate, dt) -> {acc, n}    whole events from a rate.
## guard_spawn(acc, dt, uncleared, alive, cfg) -> {acc, n}    guards to spawn now (cap-bounded).
## anchor_mote_rate(ferry, cfg)    motes/s at the anchors: the faster she ferries, the more essence.
## ray_to_bounds(origin, through, size, wall_t)    a weave's far end: the ray from `origin` through
##   `through`, clipped to the arena's inner rect.
## weave_hits(a, b, p, reach), is_tell(beat, at, tell_beats)
## seed_fronts_empty(seed)    the seed's fronts are economy's pre-E3 zeros.
## party_lanes(seed, cfg) -> {uid: lane index}    the front each party member is counted on.
## force_fronts(fronts, n, cfg)    the demo's --boss-fronts=n override.
## demo_seed(cfg) -> Dictionary    vei.json demo.seed, deep-copied.
## backups_left(spent, charges, clones), rng_int(rng_seed)
## close_fields(end_reason, spent_total) -> {won, relish_deaths}    a window close mid-fight (IDLE
##   I5): the win once she broke ("broken"), else lost; deaths = the backups spent, plus one when
##   the final-death beat was playing ("relish_unmade"). Always consistent with STATE-API 8.2.

const FRONT_IDS := ["giants", "swarm", "carvers", "raw"]


static func _f(d: Variant, key: String, def: float) -> float:
	if typeof(d) == TYPE_DICTIONARY and d.has(key) and (typeof(d[key]) == TYPE_INT or typeof(d[key]) == TYPE_FLOAT):
		return float(d[key])
	return def


static func _sec(cfg: Dictionary, key: String) -> Dictionary:
	var v: Variant = cfg.get(key, {})
	return v if typeof(v) == TYPE_DICTIONARY else {}


# ------------------------------------------------------------------------ lanes ----
static func lanes(size: Vector2, wall_t: float, court: Vector2, cfg: Dictionary) -> Array:
	var lc := _sec(cfg, "lanes")
	var xs: Variant = lc.get("x_frac", [])
	var y0 := size.y - wall_t - _f(lc, "south_margin_px", 120.0)
	var r := _f(lc, "court_r_px", 230.0)
	var arc := deg_to_rad(_f(lc, "court_arc_deg", 104.0))
	var n := FRONT_IDS.size()
	var out: Array = []
	for i in n:
		var k := float(i) / float(n - 1)
		var xf := 0.17 + 0.66 * k
		if typeof(xs) == TYPE_ARRAY and i < xs.size():
			xf = float(xs[i])
		var ang := lerpf(arc * 0.5, -arc * 0.5, k)   # west lane ends on her west side
		out.append({"id": FRONT_IDS[i], "a": Vector2(size.x * xf, y0), "b": court + Vector2(0.0, r).rotated(ang)})
	return out


static func point_at(lane: Dictionary, s: float) -> Vector2:
	return (lane["a"] as Vector2).lerp(lane["b"], s)


static func lane_len(lane: Dictionary) -> float:
	return (lane["a"] as Vector2).distance_to(lane["b"])


static func lane_dir(lane: Dictionary) -> Vector2:
	return ((lane["b"] as Vector2) - (lane["a"] as Vector2)).normalized()


static func contact_s(progress: float, cfg: Dictionary) -> float:
	var lc := _sec(cfg, "lanes")
	return lerpf(_f(lc, "guard_s0", 0.5), _f(lc, "guard_s1", 0.93), clampf(progress, 0.0, 1.0))


static func stream_count(have: float, cfg: Dictionary) -> int:
	if have <= 0.0:
		return 0
	var lc := _sec(cfg, "lanes")
	return clampi(roundi(have * _f(lc, "glyphs_per_have", 1.1)), int(_f(lc, "glyphs_min", 3.0)),
		int(_f(lc, "glyphs_max", 44.0)))


static func guard_rows(need: float, cfg: Dictionary) -> int:
	var lc := _sec(cfg, "lanes")
	return clampi(ceili(maxf(need, 0.0) * _f(lc, "rows_per_need", 0.11)), 1, int(_f(lc, "rows_max", 6.0)))


static func stream_s(count: int, s_end: float, len_px: float, march_px: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	if count <= 0 or s_end <= 0.0 or len_px <= 0.0:
		return out
	var span := s_end * len_px
	var step := span / float(count)
	var off := fposmod(march_px, step)
	for k in count:
		out.append((off + step * k) / len_px)
	return out


static func seg_t(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var l2 := ab.length_squared()
	if l2 <= 0.000001:
		return 0.0
	return clampf((p - a).dot(ab) / l2, 0.0, 1.0)


static func seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	return p.distance_to(a.lerp(b, seg_t(p, a, b)))


## The lane whose segment lies nearest `p` (ties: the westmost). -1 with no lanes.
static func nearest_lane(p: Vector2, lanes_a: Array) -> int:
	var best := -1
	var bd := INF
	for i in lanes_a.size():
		var d := seg_dist(p, lanes_a[i]["a"], lanes_a[i]["b"])
		if d < bd:
			bd = d
			best = i
	return best


## `count` anchors spread evenly (by fraction (i + 0.5) / count) along the polyline through every
## lane's point at lane_s: with four lanes and three anchors, one sits between each pair.
static func anchors(lanes_a: Array, cfg: Dictionary) -> Array:
	var ac := _sec(cfg, "anchors")
	var n := int(_f(ac, "count", 3.0))
	var s := _f(ac, "lane_s", 0.42)
	var out: Array = []
	if lanes_a.is_empty() or n <= 0:
		return out
	var pts: Array[Vector2] = []
	for l in lanes_a:
		pts.append(point_at(l, s))
	if pts.size() == 1:
		for i in n:
			out.append(pts[0])
		return out
	var total := 0.0
	for i in range(1, pts.size()):
		total += pts[i].distance_to(pts[i - 1])
	for i in n:
		var want := total * (float(i) + 0.5) / float(n)
		var acc := 0.0
		for j in range(1, pts.size()):
			var seg := pts[j].distance_to(pts[j - 1])
			if acc + seg >= want or j == pts.size() - 1:
				out.append(pts[j - 1].lerp(pts[j], clampf((want - acc) / maxf(seg, 0.0001), 0.0, 1.0)))
				break
			acc += seg
	return out


# ------------------------------------------------------------------------ beats ----
static func beat_of(t_s: float, tempo_s: float) -> float:
	return t_s / maxf(tempo_s, 0.001)


## Whole beats passed going from beat b0 to b1 (0 when b1 <= b0).
static func beats_crossed(b0: float, b1: float) -> int:
	return maxi(0, floori(b1) - floori(b0))


## The clock start (negative, scene seconds) so beat 0 lands on the next tempo boundary.
static func align_t(pulse_phase: float, tempo_s: float) -> float:
	return -(1.0 - clampf(pulse_phase, 0.0, 1.0)) * tempo_s


static func ferry_per_beat(ferry: float, tempo_s: float, cfg: Dictionary) -> float:
	return maxf(ferry, 0.0) * tempo_s * _f(cfg, "ferry_beat_scale", 0.12)


# ------------------------------------------------------------- horde, accruals ----
static func horde_step(h: float, ferry: float, dt: float) -> float:
	return maxf(0.0, h - maxf(ferry, 0.0) * dt)


static func backlog_spent(h0: float, h: float) -> float:
	return maxf(0.0, h0 - h)


static func accrue(acc: float, rate: float, dt: float) -> Dictionary:
	var a := acc + maxf(rate, 0.0) * dt
	var n := floori(a)
	return {"acc": a - n, "n": n}


static func guard_spawn(acc: float, dt: float, uncleared: int, alive: int, cfg: Dictionary) -> Dictionary:
	var gc := _sec(cfg, "guards")
	var room := maxi(0, int(_f(gc, "cap", 12.0)) - alive)
	var a := acc + _f(gc, "rate_per_uncleared", 0.3) * maxf(float(uncleared), 0.0) * dt
	var n := mini(floori(a), room)
	a -= n
	if n >= room:
		a = minf(a, 1.0)   # at the cap the lanes wait; they don't bank a flood
	return {"acc": a, "n": n}


static func anchor_mote_rate(ferry: float, cfg: Dictionary) -> float:
	return maxf(ferry, 0.0) * _f(_sec(cfg, "anchors"), "motes_per_ferry", 0.5)


# ------------------------------------------------------------------------ weaves ----
static func ray_to_bounds(origin: Vector2, through: Vector2, size: Vector2, wall_t: float) -> Vector2:
	var d := through - origin
	if d.length() < 0.001:
		d = Vector2(0.0, 1.0)
	d = d.normalized()
	var lo := Vector2(wall_t, wall_t)
	var hi := size - Vector2(wall_t, wall_t)
	var tmax := INF
	if d.x > 0.0:
		tmax = minf(tmax, (hi.x - origin.x) / d.x)
	elif d.x < 0.0:
		tmax = minf(tmax, (lo.x - origin.x) / d.x)
	if d.y > 0.0:
		tmax = minf(tmax, (hi.y - origin.y) / d.y)
	elif d.y < 0.0:
		tmax = minf(tmax, (lo.y - origin.y) / d.y)
	if not is_finite(tmax) or tmax < 0.0:
		tmax = 0.0
	return origin + d * tmax


static func weave_hits(a: Vector2, b: Vector2, p: Vector2, reach: float) -> bool:
	return seg_dist(p, a, b) <= reach


static func is_tell(beat: float, at: float, tell_beats: float) -> bool:
	return beat >= at - tell_beats and beat < at


# ------------------------------------------------------------- fronts, the seed ----
static func seed_fronts_empty(seed: Dictionary) -> bool:
	var fs: Variant = seed.get("fronts", [])
	if typeof(fs) != TYPE_ARRAY or fs.is_empty():
		return true
	for f in fs:
		if typeof(f) == TYPE_DICTIONARY and (_f(f, "need", 0.0) > 0.0 or _f(f, "have", 0.0) > 0.0):
			return false
	return true


static func party_lanes(seed: Dictionary, cfg: Dictionary) -> Dictionary:
	var out := {}
	var fr := VeiFronts.have_need(VeiFronts.info_from_boss_seed(seed), cfg)
	for i in fr.size():
		for uid in fr[i]["assigned"]:
			out[String(uid)] = i
	return out


static func force_fronts(fronts: Array, n: int, cfg: Dictionary) -> Array:
	var dc := _sec(cfg, "demo")
	var met := _f(dc, "force_met_frac", 1.15)
	var short := _f(dc, "force_unmet_frac", 0.3)
	var out: Array = []
	for i in fronts.size():
		var g: Dictionary = (fronts[i] as Dictionary).duplicate(true)
		var need := float(g.get("need", 0.0))
		var have := float(g.get("have", 0.0))
		g["have"] = maxf(have, need * met) if i < n else minf(have, need * short)
		g["cleared"] = float(g["have"]) >= need
		out.append(g)
	return out


static func demo_seed(cfg: Dictionary) -> Dictionary:
	var d: Variant = _sec(cfg, "demo").get("seed", {})
	return (d as Dictionary).duplicate(true) if typeof(d) == TYPE_DICTIONARY else {}


static func backups_left(spent: Dictionary, charges: int, clones: int) -> int:
	return maxi(0, charges - int(spent.get("phylactery", 0))) + maxi(0, clones - int(spent.get("clones", 0)))


static func close_fields(end_reason: String, spent_total: int) -> Dictionary:
	var s := maxi(0, spent_total)
	return {"won": end_reason == "broken", "relish_deaths": s + 1 if end_reason == "relish_unmade" else s}


## A seed's rng_seed string as an int (a non-numeric string hashes).
static func rng_int(rng_seed: String) -> int:
	return rng_seed.to_int() if rng_seed.is_valid_int() else hash(rng_seed)
