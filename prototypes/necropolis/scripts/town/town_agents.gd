class_name TownAgents
extends RefCounted
## Covington's agents (VISUAL-LANGUAGE §2b "Agents"), pure: no autoloads, no Engine, no Nodes.
## Time and the beat come in through step(); the renderer reads the public arrays.
##
##   var ag := TownAgents.new(town_view_cfg, buildings_cfg, economy_cfg, tempo_s)
##   ag.sync(model, views)                                   # every fetch, after model.update()
##   ag.step(dt, Pulse.phase(), Pulse.reduced_motion)         # every frame
##   for a in ag.undead: a.pos, a.dir, a.carry, a.tilt, a.flash, a.hidden ...
##
## - **Counts follow the stream.** Undead per job = the job's `staffed` (view_town().jobs), idle =
##   `workers.idle`, living = `living`. Both kinds share one budget, view.max_agents strokes, and
##   the undead (the product) come first: they keep one stroke per worker up to the budget less
##   what the living's floor reserves (min(living, view.min_living_agents)); the living take what
##   is left, never less than that floor, and never more than max(min_living_agents,
##   floor(view.living_ratio_max x undead strokes)), so the undead stay the visible majority. A
##   kind over its share is sampled by k = ceil(total / share) (`undead_scale`, `living_scale`:
##   1 stroke = k), so the living are thinned first; legend() says so on screen.
## - **Entry, then growth.** The first sync (and any relayout) places the current population along
##   its loops at once: the town already exists when you walk in. After that every change in
##   counts is gradual: at most view.spawn_per_s agents a second per kind are added or removed,
##   undead at the crypt and the living at the gate (they walk there to despawn). Moving an agent
##   from one job to another is free: it walks to its new task.
## - **Lockstep gait.** The undead move only in the first view.step_duty of each of the
##   view.steps_per_beat sub-beats of Pulse's beat, view.step_px per step, and freeze in between,
##   all at once. Every undead clock (dwells, the stall shuffle, the hammer, the forge flash) counts
##   in those steps, so the whole workforce ticks together like a factory. The living walk smoothly
##   at their own pace with a sway per stride, and dwell at each stop.
## - **Reduced motion.** Nothing moves (no steps, no sway, no beat actions); counts still follow
##   the stream (new agents appear in place on their loops, removed ones vanish), arcs still fire.
## All tuning lives in configs/town.json `view`; every px value scales with model.scale.

## One walker. Undead have a job ("idle" included); the living have none.
class Agent:
	extends RefCounted
	var id := 0
	var undead := true
	var job := ""
	## The job building's lot id ("" for idle and the living).
	var site := ""
	## The cycle's stop keys ("lot:<id>", "gate", "away", "market"...); `stop` is the one walked to.
	var stops: Array = []
	var stop := 0
	## Walking to the crypt (undead) or the gate (living) to despawn; no longer counted.
	var leaving := false
	var gone := false
	## Arrived at a hold post (stall, forge, tend, build).
	var holding := false
	## Set by sync() when a held agent's post or cycle changed; step() re-assigns it.
	var reroute := false
	## Out of town (a hauler past the gate).
	var hidden := false
	## Carrying a dead pip (a pit worker on its way from the charnel house).
	var carry := false
	var pos := Vector2.ZERO
	## Heading (unit). A held agent faces its building.
	var dir := Vector2.RIGHT
	## Beat actions, 0 unless on the beat: a builder's hammer tilt (radians), a forge flash (0..1).
	var tilt := 0.0
	var flash := 0.0
	## Hold post, and the unit along the building front (the stall shuffle's axis).
	var base := Vector2.ZERO
	var side := Vector2.ZERO
	## -1..1: where along a building front this agent stands.
	var spread := 0.0
	var lane := Vector2.ZERO
	var path := PackedVector2Array()
	## Per path point: the street node id, or "" off the street graph.
	var nodes := PackedStringArray()
	## Per path segment: the street index (TownModel.streets), or -1.
	var edges := PackedInt32Array()
	var cum := PackedFloat32Array()
	var d := 0.0
	var seg := 0
	## Undead: the gait (in steps) before which it stays put. Living: the clock (s).
	var wait := 0.0
	## The living: px/s, and a sway phase.
	var speed := 0.0
	var phase := 0.0


const HOLD_JOBS := ["stall", "forge", "tend", "build"]
## Loop jobs and their cycle; "src" is the charnel house, "site" the job's building.
const LOOPS := {"haul": ["src", "away"], "pit": ["src", "site"], "mill": ["src", "site"]}

var undead: Array[Agent] = []
var living: Array[Agent] = []
## Live trade arcs: {buyer: Agent, seller: Agent, age: float (s)}.
var arcs: Array = []
## Carts on the in-town leg: {pos, dir, pips: int, lit: bool}.
var carts: Array = []
## Foremen (big undead at a building): {lot_id, pos, strokes: int}.
var foremen: Array = []
var undead_scale := 1
var living_scale := 1
## Target agents per job ("idle" included) and for the living, after sampling.
var targets: Dictionary = {}
var living_target := 0
## Stall sales per second driving the arcs, and whether it is the E2 stand-in.
var trade_rate := 0.0
var trade_standin := false
var trades_fired := 0
## Relish at the slab (home, and the town has a crypt), where, and her light per lot.
var relish_home := false
var relish_pos := Vector2.ZERO
## Per model lot (same order): the brighten factor her light adds to its building's glow.
var lot_brighten := PackedFloat32Array()
## Per model street (same index): undead agents per second walking it, smoothed. The number is
## the agents on the street times their mean walking speed over its length (each agent standing
## for undead_scale workers), so it reads the live stream even when the gait is frozen.
var edge_rates := PackedFloat32Array()
var scale := 1.0

var _v: Dictionary
var _bcfg: Dictionary
var _econ: Dictionary
var _slab: Dictionary
var _tempo_s := 0.0
var _rng := RandomNumberGenerator.new()
var _model: TownModel
var _rect := Rect2()
var _seeded := false
var _next_id := 1
var _job_of_building: Dictionary = {}  # building id -> Array of job ids
var _sites: Dictionary = {}  # job -> Array of lot ids
var _fronts: Dictionary = {}  # lot id -> {c, n, t, half, node}
var _charnel := ""
var _crypt := ""
var _homes: Array = []
var _markets: Array = []
var _inns: Array = []
var _cart_targets: Array = []
var _street_len := PackedFloat32Array()
var _beats := -1.0  # Pulse beats since the first step (absolute, so steps align with the beat)
var _gait := 0.0  # steps since the first step
var _clock := 0.0
var _bud_u := 0.0
var _bud_l := 0.0
var _trade_acc := 0.0
var _rates_warm := false
var _was_reduced := false


func _init(view_cfg: Dictionary = {}, buildings_cfg: Dictionary = {}, economy_cfg: Dictionary = {},
		tempo_s := 0.0, seed := 1, slab_cfg := {}) -> void:
	_slab = slab_cfg
	_v = view_cfg
	_bcfg = buildings_cfg
	_econ = economy_cfg
	_tempo_s = tempo_s
	_rng.seed = seed
	for bid in _bcfg:
		_job_of_building[bid] = (_bcfg[bid].get("jobs", {}) as Dictionary).keys()


# ------------------------------------------------------------------- queries ----
## Undead counted toward `job` ("idle" for the idle), leaving ones excluded.
func count(job: String) -> int:
	var n := 0
	for a in undead:
		if a.job == job and not a.leaving:
			n += 1
	return n


func living_count() -> int:
	var n := 0
	for a in living:
		if not a.leaving:
			n += 1
	return n


## True where Relish's light falls (she is home and `p` is within view.relish_light_r).
func lit(p: Vector2) -> bool:
	return relish_home and p.distance_to(relish_pos) <= _num("relish_light_r") * scale


## The visible agent nearest `p` within `radius` px (never less than 22: a 44 px target), undead
## or living; null if none. Hidden (out of town) and gone agents can't be picked.
func agent_at(p: Vector2, radius: float) -> Agent:
	var r := maxf(radius, 22.0)
	var best: Agent = null
	var best_d := r
	for arr in [undead, living]:
		for a in arr:
			if a.hidden or a.gone:
				continue
			var d: float = a.pos.distance_to(p)
			if d <= best_d:
				best_d = d
				best = a
	return best


## The scale legend for the town view's corner: "1 green stroke = k undead" and "1 orange stroke =
## k living", each only while its k > 1 (view.legend).
static func legend_lines(u_scale: int, l_scale: int, vcfg: Dictionary) -> Array:
	var lc: Dictionary = vcfg.get("legend", {})
	var out: Array = []
	if u_scale > 1:
		out.append(BuildSort.fmt(String(lc.get("undead", "")), {"k": u_scale}))
	if l_scale > 1:
		out.append(BuildSort.fmt(String(lc.get("living", "")), {"k": l_scale}))
	return out


## legend_lines() at the current scales.
func legend() -> Array:
	return legend_lines(undead_scale, living_scale, _v)


## A trade arc's control point: the quadratic from buyer `a` to seller `b` bows to the side by
## `bulge` x their distance, but never so little that its hop (the curve's height over the chord,
## half the control's offset) is under `min_h` px, so a buyer at the stall still reads as a toss.
## It bows up the screen (the side whose normal points up).
static func arc_ctrl(a: Vector2, b: Vector2, bulge: float, min_h: float) -> Vector2:
	var d := b - a
	var n := Vector2(-d.y, d.x).normalized() if d.length() > 1e-6 else Vector2.UP
	if n.y > 0.0:
		n = -n
	return (a + b) * 0.5 + n * maxf(bulge * d.length(), 2.0 * min_h)


## The point at `u` (0 buyer .. 1 seller) along the quadratic a -> ctrl -> b.
static func arc_point(a: Vector2, ctrl: Vector2, b: Vector2, u: float) -> Vector2:
	return a.lerp(ctrl, u).lerp(ctrl.lerp(b, u), u)


## Where an arc's mote is (0 buyer .. 1 seller): it runs the arc's life; reduced motion holds it at
## the midpoint.
static func mote_u(age: float, life: float, reduced: bool) -> float:
	if reduced:
		return 0.5
	return clampf(age / maxf(life, 1e-3), 0.0, 1.0)


## Whether `a` is still walking in town (one of this population, not gone).
func alive(a: Agent) -> bool:
	return a != null and not a.gone and (undead.has(a) or living.has(a))


## What agent `a` is doing, in words (templates: view.agent_status): "hauler: carrying bodies to
## the Charnel House", "idle at the crypt", "buyer: going to the Market", "buyer: at the Market".
## The undead by job and the stop they walk to; the living by the stop of their round (home,
## market, inn: resident, buyer, guest), "at" while they dwell there.
func describe(a: Agent) -> String:
	var s: Dictionary = _v.get("agent_status", {})
	if not a.undead:
		if a.leaving:
			return String(s.get("leaving_living", ""))
		var n := a.stops.size()
		if n == 0:
			return ""
		var roles: Array = s.get("living_roles", [])
		var dwelling := _clock < a.wait
		var i := (a.stop - 1 + n) % n if dwelling else a.stop % n
		var role := String(roles[i]) if i < roles.size() else ""
		var vars := {"role": role, "place": _place_name(String(a.stops[i]))}
		if dwelling:
			return BuildSort.fmt(String(s.get("at", "")), vars)
		return BuildSort.fmt(String(s.get("home" if i == 0 else "going", "")), vars)
	if a.job == "idle":
		return String(s.get("idle", ""))
	var role := String((s.get("roles", {}) as Dictionary).get(a.job, a.job))
	if a.leaving:
		return BuildSort.fmt(String(s.get("leaving", "")), {"role": role})
	if a.hidden:
		return BuildSort.fmt(String(s.get("out", "")), {"role": role})
	if a.stops.is_empty():
		return String(s.get("idle", ""))  # no building for its job: it idles at the crypt
	var key := String(a.stops[a.stop % a.stops.size()])
	var vars := {"role": role, "place": _place_name(key)}
	if a.holding:
		return BuildSort.fmt(String(s.get("working", "")), vars)
	if key == "away":
		return BuildSort.fmt(String(s.get("heading_out", "")), vars)
	if LOOPS.has(a.job) and a.stops.size() > 1:
		# a hauler walking back to the charnel house, or a pit or mill worker walking from it, carries
		var to_src := key == "lot:" + _charnel
		if to_src == (a.job == "haul"):
			vars["what"] = String((s.get("carry", {}) as Dictionary).get(a.job, ""))
			return BuildSort.fmt(String(s.get("carrying", "")), vars)
	return BuildSort.fmt(String(s.get("going", "")), vars)


## A stop key as a place name: a lot's building label, or view.agent_status.places.
func _place_name(key: String) -> String:
	if key.begins_with("lot:"):
		var l := _model.lot(key.trim_prefix("lot:")) if _model != null else {}
		if not l.is_empty() and not (l["building"] as Dictionary).is_empty():
			return String(l["building"]["label"])
	return String((_v.get("agent_status", {}).get("places", {}) as Dictionary).get(key, key))


## The gait position (in steps) at `beats` Pulse beats: whole steps, plus the share of the
## current step's duty window walked. Flat outside the duty windows.
static func gait_at(beats: float, steps_per_beat: int, duty: float) -> float:
	var whole := floorf(beats)
	var x := (beats - whole) * float(steps_per_beat)
	var n := floorf(x)
	return whole * float(steps_per_beat) + n + minf((x - n) / maxf(duty, 1e-6), 1.0)


## The street index agent `a` is walking, or -1 (held, hidden, dwelling off-street).
static func edge_of(a: Agent) -> int:
	if a.holding or a.hidden or a.gone or a.seg >= a.edges.size():
		return -1
	return a.edges[a.seg]


# ---------------------------------------------------------------------- sync ----
## New targets from the shell's views. `model` must already be updated from the same views.
func sync(model: TownModel, views: Dictionary) -> void:
	_model = model
	scale = model.scale
	if model.rect != _rect:
		_rect = model.rect
		undead.clear()
		living.clear()
		arcs.clear()
		_seeded = false
		_street_len = PackedFloat32Array()
		for s in model.streets:
			_street_len.append(maxf(float(s["length"]), 1.0))
		edge_rates = PackedFloat32Array()
		edge_rates.resize(model.streets.size())
		_rates_warm = false
	var town: Dictionary = views.get("town", {})
	_read_sites(model)
	_read_targets(town)
	_read_trade(model, town)
	_read_carts(town)
	_read_foremen(model, views)
	_read_relish(model, town)
	for a in undead:
		var old_site := a.site
		_refresh_stops(a)
		# a held agent whose post or cycle changed under it must walk again (step() re-routes it)
		if a.holding and not a.leaving and (a.site != old_site or not _holds(a)):
			a.reroute = true
	for a in living:
		_refresh_stops(a)
	if not _seeded and views.has("town"):  # an empty first fetch must not spend the entry seed
		_seeded = true
		_seed()


func _read_sites(model: TownModel) -> void:
	_sites = {}
	_fronts = {}
	_charnel = ""
	_crypt = ""
	_homes = []
	_markets = []
	_inns = []
	for l in model.lots:
		var b: Dictionary = l["building"]
		if b.is_empty():
			continue
		var id := String(l["id"])
		var bid := String(b["building_id"])
		_fronts[id] = _front(l)
		var built := String(b["state"]) != "constructing"
		if bid == "crypt":
			_crypt = id
		if not built:
			if not _sites.has("build"):
				_sites["build"] = []
			_sites["build"].append(id)
			continue
		match bid:
			"charnel_house":
				if _charnel == "":
					_charnel = id
			"house", "inn":
				_homes.append(id)
			"market":
				_markets.append(id)
		if bid == "inn":
			_inns.append(id)
		for j in _job_of_building.get(bid, []):
			if j == "build":
				continue
			if not _sites.has(j):
				_sites[j] = []
			_sites[j].append(id)


func _read_targets(town: Dictionary) -> void:
	var staffed := {}
	var total := 0.0
	for j in town.get("jobs", []):
		var s := maxf(float(j.get("staffed", 0.0)), 0.0)
		staffed[String(j.get("id", ""))] = float(staffed.get(String(j.get("id", "")), 0.0)) + s
		total += s
	var idle := maxf(float(town.get("workers", {}).get("idle", 0.0)), 0.0)
	total += idle
	var people := maxf(float(town.get("living", 0.0)), 0.0)
	var budget := _num("max_agents")
	var floor_l := minf(_num("min_living_agents"), ceilf(people - 1e-9))  # only what the living need
	undead_scale = _scale_for(total, maxf(budget - floor_l, 1.0))
	targets = {}
	var orphan := 0.0
	var used := 0
	for j in staffed:
		if (_sites.get(j, []) as Array).is_empty():
			orphan += staffed[j]  # no building for the job: its workers idle at the crypt
		else:
			targets[j] = roundi(staffed[j] / float(undead_scale))
			used += int(targets[j])
	targets["idle"] = roundi((idle + orphan) / float(undead_scale))
	used += int(targets["idle"])
	var ratio := maxf(_num("min_living_agents"), floorf(_num("living_ratio_max") * float(used)))
	living_scale = _scale_for(people, minf(maxf(budget - float(used), floor_l), ratio))
	living_target = roundi(people / float(living_scale))


static func _scale_for(total: float, cap: float) -> int:
	if cap <= 0.0 or total <= cap:
		return 1
	return maxi(ceili(total / cap - 1e-9), 1)


func _read_trade(model: TownModel, town: Dictionary) -> void:
	trade_standin = model.staffing_standin
	if trade_standin:
		trade_rate = TownStandins.trade_rate(town, _v)  # STANDIN(E2): off once outputs arrive
	else:
		trade_rate = maxf(float(town.get("trade_rate", 0.0)), 0.0)


## Convoys on the in-town leg become carts between the gate and the charnel house: `back` with
## t >= 1 - f walks in as t -> 1; `out` with t <= f walks out as t grows (f = view.cart_town_frac).
func _read_carts(town: Dictionary) -> void:
	_cart_targets = []
	var f := _num("cart_town_frac")
	if _charnel == "" or f <= 0.0 or not _model.nodes.has("gate"):
		carts.clear()
		return
	var road := _leg_points("gate", _place("lot:" + _charnel, 0.0))
	var length := _poly_len(road)
	var mass := _num("cart_pip_mass")
	for c in town.get("haul", {}).get("convoys", []):
		var t := float(c.get("t", 0.0))
		var s := -1.0  # share of the road from the gate in
		var inward := true
		match String(c.get("phase", "")):
			"back":
				if t >= 1.0 - f:
					s = clampf((t - (1.0 - f)) / f, 0.0, 1.0)
			"out":
				if t <= f:
					s = clampf(1.0 - t / f, 0.0, 1.0)
					inward = false
		if s < 0.0:
			continue
		var at := _point_at(road, s * length)
		var dir: Vector2 = at[1] if inward else -at[1]
		var load := maxf(float(c.get("load", 0.0)), 0.0)
		var pips := ceili(load / mass - 1e-9) if mass > 0.0 else 0
		_cart_targets.append({"pos": at[0], "dir": dir, "pips": maxi(pips, 0)})
	carts.resize(_cart_targets.size())
	for i in _cart_targets.size():
		var tg: Dictionary = _cart_targets[i]
		if not carts[i] is Dictionary:
			carts[i] = {"pos": tg["pos"], "dir": tg["dir"], "pips": 0, "lit": false}
		carts[i]["pips"] = tg["pips"]


func _read_foremen(model: TownModel, views: Dictionary) -> void:
	foremen = []
	var by_uid := {}
	for e in views.get("big_undead", {}).get("big_undead", []):
		by_uid[String(e.get("uid", ""))] = e
	var big := _agent_px("big_px")
	for l in model.lots:
		var b: Dictionary = l["building"]
		if b.is_empty() or String(b.get("foreman", "")) == "":
			continue
		var fr: Dictionary = _fronts.get(String(l["id"]), {})
		if fr.is_empty():
			continue
		var p: Vector2 = fr["c"] + fr["n"] * big * 1.5
		foremen.append({"lot_id": String(l["id"]), "pos": p,
			"strokes": TownStandins.foreman_strokes(by_uid.get(String(b["foreman"]), {}), _v, _slab)})


func _read_relish(model: TownModel, town: Dictionary) -> void:
	relish_home = bool(town.get("relish_home", false)) and _crypt != ""
	relish_pos = Vector2.ZERO
	if _crypt != "":
		relish_pos = (model.lot(_crypt)["building"]["rect"] as Rect2).get_center()
	var r := _num("relish_light_r") * scale
	var k := _num("relish_brighten")
	lot_brighten = PackedFloat32Array()
	lot_brighten.resize(model.lots.size())
	for i in model.lots.size():
		var l: Dictionary = model.lots[i]
		var near := (l["rect"] as Rect2).get_center().distance_to(relish_pos) <= r
		lot_brighten[i] = k if relish_home and near and not (l["building"] as Dictionary).is_empty() else 0.0


## The front a building's agents gather at: the footprint edge facing its door, pushed out by
## view.front_gap_px. {c: centre, n: outward normal, t: along the edge, half: half its length,
## node: the door's street node}.
func _front(l: Dictionary) -> Dictionary:
	var b: Dictionary = l["building"]
	var r: Rect2 = b["rect"] if not b.is_empty() else l["rect"]
	var c := r.get_center()
	var hs := r.size * 0.5
	var dl: Vector2 = l["door_pos"] - c
	var n := Vector2(0.0, 1.0 if dl.y >= 0.0 else -1.0)
	if absf(dl.x) * hs.y > absf(dl.y) * hs.x:
		n = Vector2(1.0 if dl.x >= 0.0 else -1.0, 0.0)
	var half := hs.x if n.x == 0.0 else hs.y
	var edge := c + n * (hs.y if n.x == 0.0 else hs.x)
	return {"c": edge + n * _px("front_gap_px"), "n": n, "t": Vector2(absf(n.y), absf(n.x)), "half": half,
		"node": String(l["door"])}


# ---------------------------------------------------------------- places ----
## A stop key resolved for agent `a`: {node, pos, hidden, direct, face, side}.
func _place(key: String, spread: float) -> Dictionary:
	if key.begins_with("lot:"):
		var fr: Dictionary = _fronts.get(key.trim_prefix("lot:"), {})
		if not fr.is_empty():
			var off: float = spread * float(fr["half"]) * _num("post_spread")
			return {"node": fr["node"], "pos": fr["c"] + fr["t"] * off, "face": -fr["n"], "side": fr["t"]}
		key = "crypt"
	match key:
		"gate", "away":
			var g: Vector2 = _model.nodes.get("gate", _rect.get_center())
			return {"node": "gate" if _model.nodes.has("gate") else "", "pos": g, "hidden": key == "away"}
		"crypt":
			if _crypt != "" and _fronts.has(_crypt):
				return _place("lot:" + _crypt, 0.0)
		"loiter":
			return {"node": "", "pos": _loiter_spot(), "direct": true}
	var p: Vector2 = _model.nodes.get("plaza", _rect.get_center())
	return {"node": "plaza" if _model.nodes.has("plaza") else "", "pos": p}


## A random idle spot in the ring around the crypt (view.idle_ring_px outside its footprint), on
## the half facing its door, outside every lot.
func _loiter_spot() -> Vector2:
	var ring: Array = _v.get("idle_ring_px", [0.0, 0.0])
	var cr := Rect2(_model.nodes.get("plaza", _rect.get_center()), Vector2.ZERO)
	var n := Vector2(0.0, 1.0)
	if _crypt != "" and _fronts.has(_crypt):
		cr = _model.lot(_crypt)["building"]["rect"]
		n = _fronts[_crypt]["n"]
	var c := cr.get_center()
	var p := c
	for i in 8:
		var g := cr.grow(_rng.randf_range(float(ring[0]), float(ring[1])) * scale)
		var u := Vector2.from_angle(n.angle() + _rng.randf_range(-PI * 0.5, PI * 0.5))
		var hx := g.size.x * 0.5 / absf(u.x) if absf(u.x) > 1e-6 else INF
		var hy := g.size.y * 0.5 / absf(u.y) if absf(u.y) > 1e-6 else INF
		p = c + u * minf(hx, hy)
		var clear := true
		for l in _model.lots:
			if (l["rect"] as Rect2).has_point(p):
				clear = false
				break
		if clear:
			break
	return p


## Resolve an agent's cycle into stop keys (re-run on every sync, so new buildings take effect).
func _refresh_stops(a: Agent) -> void:
	if not a.undead:
		var home := "gate"
		if not _homes.is_empty():
			home = "lot:" + String(_homes[a.id % _homes.size()])
		var market := "lot:" + String(_markets[a.id % _markets.size()]) if not _markets.is_empty() else "plaza"
		var inn := "lot:" + String(_inns[a.id % _inns.size()]) if not _inns.is_empty() else market
		a.stops = [home, market, inn]
		return
	if a.job != "idle" and not (_sites.get(a.job, []) as Array).has(a.site):
		a.site = _pick_site(a.job)
	a.stops = []
	if LOOPS.has(a.job):
		if _charnel == "" or (a.job == "haul" and a.site == ""):
			a.stops = ["lot:" + a.site] if a.site != "" else []
		else:
			for k in LOOPS[a.job]:
				a.stops.append("lot:" + _charnel if k == "src" else ("away" if k == "away" else "lot:" + a.site))
	elif a.job in HOLD_JOBS and a.site != "":
		a.stops = ["lot:" + a.site]


func _pick_site(job: String) -> String:
	var sites: Array = _sites.get(job, [])
	if sites.is_empty():
		return ""
	var best := String(sites[0])
	var best_n := 1 << 30
	for s in sites:
		var n := 0
		for a in undead:
			if a.job == job and a.site == s and not a.leaving:
				n += 1
		if n < best_n:
			best_n = n
			best = String(s)
	return best


# ------------------------------------------------------------------ paths ----
## The polyline from street node `from_node` (or straight, for a direct place) to place `to`.
func _leg_points(from_node: String, to: Dictionary, lane := Vector2.ZERO) -> PackedVector2Array:
	var out := PackedVector2Array()
	if from_node != "" and not bool(to.get("direct", false)):
		for id in _model.route(from_node, String(to["node"])):
			out.append(_model.nodes[id] + lane)
	out.append(to["pos"])
	return out


## Point `a` along a fresh path from where it stands to place `to`, via street node `from_node`
## ("" = straight there).
func _set_path(a: Agent, from_node: String, to: Dictionary) -> void:
	var pts := PackedVector2Array([a.pos])
	var ids := PackedStringArray([""])
	if from_node != "" and not bool(to.get("direct", false)):
		for id in _model.route(from_node, String(to["node"])):
			pts.append(_model.nodes[id] + a.lane)
			ids.append(id)
	pts.append(to["pos"])
	ids.append("")
	a.path = pts
	a.nodes = ids
	a.edges = PackedInt32Array()
	a.cum = PackedFloat32Array([0.0])
	for i in range(1, pts.size()):
		a.edges.append(_model.edge_index(ids[i - 1], ids[i]) if ids[i - 1] != "" and ids[i] != "" else -1)
		a.cum.append(a.cum[i - 1] + pts[i - 1].distance_to(pts[i]))
	a.d = 0.0
	a.seg = 0


## The street node an agent heads through to go anywhere new: the next node on its path, else
## the last one it passed, else the nearest.
func _anchor(a: Agent) -> String:
	for i in range(a.seg + 1, a.nodes.size()):
		if a.nodes[i] != "":
			return a.nodes[i]
	for i in range(mini(a.seg, a.nodes.size() - 1), -1, -1):
		if a.nodes[i] != "":
			return a.nodes[i]
	var best := ""
	var best_d := INF
	for id in _model.nodes:
		var dd: float = _model.nodes[id].distance_squared_to(a.pos)
		if dd < best_d:
			best_d = dd
			best = id
	return best


func _poly_len(p: PackedVector2Array) -> float:
	var l := 0.0
	for i in range(1, p.size()):
		l += p[i - 1].distance_to(p[i])
	return l


## [point, unit direction] at distance `s` along `p`.
func _point_at(p: PackedVector2Array, s: float) -> Array:
	var left := maxf(s, 0.0)
	for i in range(1, p.size()):
		var l := p[i - 1].distance_to(p[i])
		if left <= l or i == p.size() - 1:
			var dir := (p[i] - p[i - 1]) / l if l > 0.0 else Vector2.RIGHT
			return [p[i - 1] + dir * minf(left, l), dir]
		left -= l
	return [p[0] if not p.is_empty() else Vector2.ZERO, Vector2.RIGHT]


## Move `a` `dist` px along its path. Returns the distance left over past the end (>= 0) if it
## arrived, else -1.
func _advance(a: Agent, dist: float) -> float:
	var total: float = a.cum[a.cum.size() - 1]
	a.d += dist
	var over := -1.0
	if a.d >= total:
		over = a.d - total
		a.d = total
	while a.seg < a.path.size() - 2 and a.d > a.cum[a.seg + 1]:
		a.seg += 1
	var i := a.seg
	if a.path.size() >= 2:
		var l: float = a.cum[i + 1] - a.cum[i]
		var u := (a.d - a.cum[i]) / l if l > 0.0 else 1.0
		a.pos = a.path[i].lerp(a.path[i + 1], u)
		if l > 0.0:
			a.dir = (a.path[i + 1] - a.path[i]) / l
	return over


# ----------------------------------------------------------------- agents ----
func _new_agent(is_undead: bool) -> Agent:
	var a := Agent.new()
	a.id = _next_id
	_next_id += 1
	a.undead = is_undead
	var lane := _px("lane_px")
	a.lane = Vector2(_rng.randf_range(-lane, lane), _rng.randf_range(-lane, lane))
	a.spread = _rng.randf_range(-1.0, 1.0)
	a.phase = _rng.randf_range(0.0, TAU)
	if not is_undead:
		var sp: Array = _v.get("living_speed_px", [0.0, 0.0])
		a.speed = _rng.randf_range(float(sp[0]), float(sp[1])) * scale
	return a


## Give `a` a job and send it there from where it stands (or, `in_place`, put it straight on its
## loop: the entry seed and reduced motion).
func _assign(a: Agent, job: String, in_place: bool) -> void:
	a.job = job
	a.site = ""
	a.holding = false
	a.hidden = false
	a.carry = false
	a.tilt = 0.0
	a.flash = 0.0
	_refresh_stops(a)
	if in_place:
		_warm(a)
		return
	a.stop = 0
	a.wait = _gait
	if job == "idle" or a.stops.is_empty():
		# back along the streets to the crypt, then out to a spot in its ring
		var spot := _place("loiter", 0.0)
		spot["direct"] = false
		spot["node"] = _place("crypt", 0.0)["node"]
		_set_path(a, _entry_node(a), spot)
		return
	_set_path(a, _entry_node(a), _place(String(a.stops[0]), a.spread))


## Where an agent enters the street graph to go somewhere new: its anchor, or for a fresh agent
## (no path yet) the crypt's door (undead) or the gate (living).
func _entry_node(a: Agent) -> String:
	if not a.path.is_empty():
		return _anchor(a)
	var c := _place("crypt", 0.0) if a.undead else _place("gate", 0.0)
	return String(c["node"]) if String(c["node"]) != "" else _anchor(a)


## Agents that stand at their building: the hold jobs, and a loop with only one stop (a pit or
## mill when the town has no charnel house).
func _holds(a: Agent) -> bool:
	return a.undead and (a.job in HOLD_JOBS or a.stops.size() == 1)


## Put `a` straight onto its cycle at a random point: a hold post, an idle spot, or a random
## leg of its loop at a random distance along it.
func _warm(a: Agent) -> void:
	a.hidden = false
	a.carry = false
	if a.undead and (a.job == "idle" or a.stops.is_empty()):
		a.pos = _loiter_spot()
		a.path = PackedVector2Array()
		a.nodes = PackedStringArray()
		_idle_next(a, _gait)
		return
	if _holds(a):
		_hold_at(a, _place(String(a.stops[0]), a.spread))
		return
	var n := a.stops.size()
	var i := _rng.randi_range(0, n - 1)
	var from := _place(String(a.stops[i]), a.spread)
	var to := _place(String(a.stops[(i + 1) % n]), a.spread)
	a.pos = from["pos"]
	a.path = PackedVector2Array()
	_set_path(a, String(from["node"]), to)
	a.stop = (i + 1) % n
	a.carry = _carries(a)
	a.wait = _gait if a.undead else _clock
	_advance(a, _rng.randf() * a.cum[a.cum.size() - 1])


func _hold_at(a: Agent, p: Dictionary) -> void:
	a.holding = true
	a.carry = false
	a.pos = p["pos"]
	a.base = a.pos
	a.dir = p.get("face", Vector2.UP)
	a.side = p.get("side", Vector2.RIGHT)
	a.path = PackedVector2Array([a.pos])
	a.nodes = PackedStringArray([String(p["node"])])
	a.edges = PackedInt32Array()
	a.cum = PackedFloat32Array([0.0])
	a.seg = 0
	a.d = 0.0


## A pit worker carries a body on its way from the charnel house to the pit.
func _carries(a: Agent) -> bool:
	return a.undead and a.job == "pit" and a.stops.size() == 2 and a.stop == 1


func _idle_next(a: Agent, g: float) -> void:
	var dw: Array = _v.get("idle_dwell_steps", [1, 1])
	a.wait = ceilf(g) + float(_rng.randi_range(int(dw[0]), int(dw[1])))
	_set_path(a, "", _place("loiter", 0.0))


func _leave(a: Agent, in_place: bool) -> void:
	a.leaving = true
	a.holding = false
	if in_place:
		a.gone = true
		return
	a.wait = _gait if a.undead else _clock
	_set_path(a, _entry_node(a), _place("crypt", 0.0) if a.undead else _place("gate", 0.0))


## Arrival at the end of a path at gait `g` (undead) or now (living).
func _arrive(a: Agent, g: float) -> void:
	if a.leaving:
		a.gone = true
		return
	if not a.undead:
		var dw: Array = _v.get("living_dwell_s", [0.0, 0.0])
		a.wait = _clock + _rng.randf_range(float(dw[0]), float(dw[1]))
		var here := _place(String(a.stops[a.stop % a.stops.size()]), a.spread)
		a.stop = (a.stop + 1) % a.stops.size()
		a.spread = _rng.randf_range(-1.0, 1.0)
		_set_path(a, String(here["node"]), _place(String(a.stops[a.stop]), a.spread))
		return
	if a.job == "idle" or a.stops.is_empty():
		_idle_next(a, g)
		return
	if _holds(a):
		_hold_at(a, _place(String(a.stops[0]), a.spread))
		return
	var key := String(a.stops[a.stop % a.stops.size()])
	var here := _place(key, a.spread)
	a.hidden = bool(here.get("hidden", false))
	a.stop = (a.stop + 1) % a.stops.size()
	a.carry = _carries(a)
	var steps := _num("haul_away_steps") if key == "away" else _num("undead_dwell_steps")
	a.wait = ceilf(g) + steps
	_set_path(a, String(here["node"]), _place(String(a.stops[a.stop]), a.spread))


# ------------------------------------------------------------- population ----
func _seed() -> void:
	for j in _job_order():
		for i in int(targets[j]):
			var a := _new_agent(true)
			undead.append(a)
			_assign(a, j, true)
	for i in living_target:
		var a := _new_agent(false)
		living.append(a)
		_refresh_stops(a)
		_warm(a)


## Jobs in a stable order, idle last (so freed workers are re-tasked before they are sent home).
func _job_order() -> Array:
	var out: Array = targets.keys()
	out.erase("idle")
	out.sort()
	out.append("idle")
	return out


## Bring the counts toward the targets: re-task surplus agents first (free), then spawn or send
## home, within the kind's budget (view.spawn_per_s, at most one banked).
func _reconcile(dt: float, in_place: bool) -> void:
	var rate := _num("spawn_per_s")
	_bud_u = minf(_bud_u + dt * rate, 1.0)
	_bud_l = minf(_bud_l + dt * rate, 1.0)
	var groups := {}
	for a in undead:
		if not a.leaving:
			if not groups.has(a.job):
				groups[a.job] = []
			groups[a.job].append(a)
	var pool: Array = []
	for j in groups:
		var extra: int = groups[j].size() - int(targets.get(j, 0))
		for i in extra:
			pool.append(groups[j][groups[j].size() - 1 - i])
	# re-task idle surplus first: put it at the back, where pop_back takes from
	pool.sort_custom(func(x: Agent, y: Agent) -> bool: return x.job != "idle" and y.job == "idle")
	for j in _job_order():
		var need: int = int(targets[j]) - (groups.get(j, []) as Array).size()
		while need > 0 and not pool.is_empty():
			_assign(pool.pop_back(), j, in_place)
			need -= 1
		while need > 0 and _bud_u >= 1.0:
			var a := _new_agent(true)
			a.pos = _place("crypt", 0.0)["pos"]
			undead.append(a)
			_assign(a, j, in_place)
			_bud_u -= 1.0
			need -= 1
	for a in pool:
		if _bud_u < 1.0:
			break
		_bud_u -= 1.0
		_leave(a, in_place)
	var have := living_count()
	while have < living_target and _bud_l >= 1.0:
		var a := _new_agent(false)
		a.pos = _place("gate", 0.0)["pos"]
		living.append(a)
		_refresh_stops(a)
		if in_place:
			_warm(a)
		else:  # a newcomer walks in from the gate to its home first
			a.stop = 0
			a.wait = _clock
			_set_path(a, _entry_node(a), _place(String(a.stops[0]), a.spread))
		_bud_l -= 1.0
		have += 1
	var i := living.size() - 1
	while have > living_target and _bud_l >= 1.0 and i >= 0:
		if not living[i].leaving:
			_leave(living[i], in_place)
			_bud_l -= 1.0
			have -= 1
		i -= 1


# ---------------------------------------------------------------------- step ----
## Advance everything by `dt` seconds. `beat_phase` is Pulse.phase() (0..1 into the beat).
func step(dt: float, beat_phase: float, reduced_motion: bool) -> void:
	if _model == null:
		return
	var spb := maxi(int(_num("steps_per_beat")), 1)
	var duty := _num("step_duty")
	var g0 := _gait
	if reduced_motion:
		_was_reduced = true
	else:
		var first := _beats < 0.0
		_beats = beat_phase if first else _beats + fposmod(beat_phase - fposmod(_beats, 1.0), 1.0)
		_gait = gait_at(_beats, spb, duty)
		if first or _was_reduced:
			g0 = _gait  # (re)joining the beat: no catch-up stride
		_was_reduced = false
	var g1 := _gait
	_clock += dt
	for a in undead:
		if a.reroute:
			a.reroute = false
			_assign(a, a.job, reduced_motion)
	_reconcile(dt, reduced_motion)
	if not reduced_motion:
		var step := _px("step_px")
		for a in undead:
			_step_undead(a, g0, g1, step, spb)
		for a in living:
			_step_living(a, dt)
	else:
		for a in undead:
			a.tilt = 0.0
			a.flash = 0.0
	_trade(dt)
	for c in carts.size():
		if reduced_motion or g1 > g0:
			var tg: Dictionary = _cart_targets[c]
			carts[c]["pos"] = tg["pos"]
			carts[c]["dir"] = tg["dir"]
		carts[c]["lit"] = lit(carts[c]["pos"])
	_rates(dt)
	_sweep()


func _step_undead(a: Agent, g0: float, g1: float, step: float, spb: int) -> void:
	if a.holding:
		_hold_beat(a, g1, spb)
		return
	var from := maxf(g0, a.wait)
	if g1 <= from or a.path.size() < 2:
		return
	a.hidden = false
	var over := _advance(a, (g1 - from) * step)
	if over >= 0.0:
		_arrive(a, g1 - over / maxf(step, 1e-6))


## A held agent's beat: the stall shuffles one step side to side, the builder's stroke tilts like
## a hammer, the forge flashes on the first step of each beat. All inside the duty window only.
func _hold_beat(a: Agent, g: float, spb: int) -> void:
	var m := floorf(g)
	var q := g - m
	a.tilt = 0.0
	a.flash = 0.0
	match a.job:
		"stall":
			var s0 := -1.0 if int(m) % 2 == 0 else 1.0
			a.pos = a.base + a.side * _px("stall_shuffle_px") * lerpf(s0, -s0, q)
		"build":
			a.tilt = deg_to_rad(_num("hammer_deg")) * sin(PI * q)
		"forge":
			if q > 0.0 and int(m) % spb == 0:
				a.flash = 1.0 - q


func _step_living(a: Agent, dt: float) -> void:
	if _clock < a.wait or a.path.size() < 2:
		return
	var over := _advance(a, a.speed * dt)
	if over >= 0.0:
		_arrive(a, 0.0)
		return
	var stride := _px("living_sway_stride_px")
	if stride > 0.0:
		a.pos += Vector2(-a.dir.y, a.dir.x) * _px("living_sway_px") * sin(a.d / stride * TAU + a.phase)


## Sales accumulate at trade_rate; each whole one is an arc from the living agent nearest a
## holding stall worker (within view.trade_reach_px) to that worker, for view.trade_arc_s. At most
## view.max_trade_arcs live at once; a sale with no buyer in reach or over the cap draws nothing.
func _trade(dt: float) -> void:
	var life := _num("trade_arc_s")
	var i := arcs.size() - 1
	while i >= 0:
		arcs[i]["age"] += dt
		if arcs[i]["age"] >= life:
			arcs.remove_at(i)
		i -= 1
	_trade_acc += trade_rate * dt
	while _trade_acc >= 1.0:
		_trade_acc -= 1.0
		if arcs.size() >= int(_num("max_trade_arcs")):
			continue
		var sellers: Array = []
		for a in undead:
			if a.job == "stall" and a.holding and not a.leaving:
				sellers.append(a)
		if sellers.is_empty():
			continue
		var seller: Agent = sellers[_rng.randi_range(0, sellers.size() - 1)]
		var reach := _num("trade_reach_px") * scale
		var buyer: Agent = null
		var best := reach
		for b in living:
			if b.leaving or b.gone:
				continue
			var dd := b.pos.distance_to(seller.pos)
			if dd <= best:
				best = dd
				buyer = b
		if buyer == null:
			continue
		arcs.append({"buyer": buyer, "seller": seller, "age": 0.0})
		trades_fired += 1


func _rates(dt: float) -> void:
	var n := edge_rates.size()
	if n == 0:
		return
	var tgt := PackedFloat32Array()
	tgt.resize(n)
	var v := _px("step_px") * _num("steps_per_beat") / _tempo_s if _tempo_s > 0.0 else 0.0
	for a in undead:
		var e := edge_of(a)
		if e >= 0 and e < n:
			tgt[e] += v / _street_len[e] * float(undead_scale)
	var tau := _num("flow_smooth_s")
	var k := 1.0 if not _rates_warm or tau <= 0.0 else 1.0 - exp(-dt / tau)
	_rates_warm = true
	for i in n:
		edge_rates[i] += (tgt[i] - edge_rates[i]) * k


func _sweep() -> void:
	for arr in [undead, living]:
		var i: int = arr.size() - 1
		while i >= 0:
			if arr[i].gone:
				arr.remove_at(i)
			i -= 1


# ------------------------------------------------------------------ config ----
func _num(key: String) -> float:
	return float(_v.get(key, 0.0))


## A px value from view, at the view's scale.
func _px(key: String) -> float:
	return float(_v.get(key, 0.0)) * scale


func _agent_px(key: String) -> float:
	return float(_v.get("agent", {}).get(key, 0.0)) * scale
