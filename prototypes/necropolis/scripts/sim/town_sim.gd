class_name TownSim
extends RefCounted
## Covington's economy (MECHANICS §4.1–§4.3): the workforce, the job ladder, the jobs (haul, mill,
## stall, forge, pit, tend, build), the living and morale, upkeep and the buildings' effects.
## Headless and pure on its inputs: GameState feeds `step()` once per substep (order step 2,
## MECHANICS §1.3) and applies the outputs. No autoload, no Engine.
##
## Units: workers are counted in workers of `worker.mass` mass; bodies, rot return, WORK, muster
## and pickups are mass.
##
## step(dt, inp) inputs (all optional):
##   work_mass: float       mass of WORK delivered this substep (the previous substep's WORK)
##   relish_home: bool      Relish is home: the rot rate × relish.home_rot_mult
##   held_villages: int     villages following held forts (migrants)
##   forts: Array           [{id, pos: [x, y], dead, held}], a read-only snapshot taken before this
##                          substep's realm step
##   cov_pos: [x, y]        Covington (haul trip lengths)
##   haul_target: String    "auto" or a fort id
##   relics_available: int  relics the forge may spend this substep
## step outputs:
##   pits: int              working pits (the mint's P_per_pit term)
##   feed: float 0..1       burned / wanted (the mint's feed bonus)
##   muster_mass: float     mass to add to WAR
##   pickups: Array         [{fort_id, mass}] corpses taken from forts this substep, each total ≤
##                          that fort's `dead` (GameState takes them off the forts)
##   relics_spent: int      relics the forge used (GameState takes them off the stock)
##   rot_overflow: float    rot return lost to the body cap (mass; a ledger sink)
##   haul_overflow: float   haul deliveries lost to the body cap (mass; a ledger sink)
##   events: Array          {type, ...} without `t` (GameState stamps it): building_started,
##                          building_done, building_unpaid
##   rates: Dictionary      this substep's flows per second (a copy of `rates`)

const JOBS := ["haul", "mill", "stall", "forge", "pit", "tend", "build"]
const WORKING := ["active", "idle"]  # built, paid and not under construction
const EPS := 1e-9
const MAX_LEGS := 256  # convoy legs one step may run (a long catch-up step makes many trips)
const MIN_TRIP_S := 0.01

# ---- tunables, read once in setup() ----
var _lots: Array[String] = []  # town.json lot ids, in order
var _defs := {}  # building id -> {jobs: {job: int}, effects: {}, upkeep_gold, upkeep_bone, build_work, max_level}
var _open := {}
var _default_ladder: Array[String] = []
var _mass := 40.0
var _lifetime := 480.0
var _body_return := 0.25
var _idle_rot := 0.5
var _idle_cap := 10.0
var _home_rot := 0.7
var _body_cap := 200.0
var _living_cap := 16.0
var _haul_speed := 140.0
var _carry := 14.0
var _auto_min := 4.0
var _haul_mult := 1.5
var _mill_mass := 0.2
var _mill_rate := 0.5
var _forge_rate := 0.5
var _build_rate := 0.5
var _build_slots := 3
var _stall_rate := 0.15
var _shop_rate := 0.03
var _price := 1.0
var _burn := 0.6
var _hold_s := 30.0
var _forge_work: Array[float] = []
var _forge_relics: Array[int] = []
var _migrant_rate := 0.012
var _leave_rate := 0.004
var _morale_base := 0.6
var _ease := 0.005
var _dread_ratio := 4.0
var _dread_k := 0.05
var _leave_below := 0.35
var _shock_s := 600.0

# ---- state (to_dict / from_dict) ----
var workers := 0.0  # workers
var bodies := 0.0  # mass, ≤ body_cap()
var gold := 0.0
var bone := 0.0
var living := 0.0  # people, ≤ living_cap()
var morale := 0.0  # 0..1
var shock := 0.0  # the decaying death shock, subtracted from the morale target
## lot_id -> {building_id, level, state, progress, staff_cap, unpaid_s, build_level}. `state` is
## constructing | active | idle (working, but nobody staffed) | unpaid. `level` is 0 during a
## first build; `build_level` is the level a construction completes to. `progress` is 0..1 while
## constructing, else 1. `staff_cap` -1 = none. `unpaid_s` is the unpaid hold left.
var buildings := {}
var ladder: Array = []  # job order, top first
## The convoy: `current` is the fort it works ("" when home); at most one entry in `convoys`,
## {fort, phase: out|back, t: 0..1 leg progress, trip_s: one leg, load: mass, crew: haulers}.
var haul := {"current": "", "convoys": []}
var forge := {"level": 0, "progress": 0.0}  # the q forge level (not the Forge building's level), work units
var rates := {}  # the last substep's flows per second (views); see _zero_rates()

# ---- derived (not saved; rebuilt by _staff()) ----
## {jobs: {job: {slots: int, staffed: float}} in ladder order, lots: {lot_id: staffed},
## idle: float, slots: float (staffable after staff caps)}
var staffing := {}
var _by_lot := {}  # lot_id -> {job: staffed}
var _pending: Array = []  # events from commands, returned by the next step()
var _haul_trip := -1.0  # this step's landed trip, load / round trip (mass/s); -1 when none landed


func setup(cfgs: Dictionary) -> void:
	var eco := _d(cfgs.get("economy"))
	var realm := _d(cfgs.get("realm"))
	var worker := _d(eco.get("worker"))
	var job := _d(eco.get("job"))
	var hl := _d(job.get("haul"))
	var ml := _d(job.get("mill"))
	var morale_c := _d(eco.get("morale"))
	var town := _d(eco.get("town"))
	_open = _d(eco.get("opening")).duplicate(true)
	_mass = maxf(EPS, float(worker.get("mass", 40.0)))
	_lifetime = maxf(EPS, float(worker.get("lifetime_s", 480.0)))
	_body_return = float(worker.get("body_return", 0.25))
	_idle_rot = maxf(0.0, float(worker.get("idle_rot_mult", 0.5)))
	_idle_cap = maxf(0.0, float(worker.get("idle_cap", 10.0)))
	_home_rot = maxf(EPS, float(_d(realm.get("relish")).get("home_rot_mult", 0.7)))
	_haul_mult = float(_d(realm.get("flip")).get("haul_mult", 1.5))
	_body_cap = float(_d(eco.get("body_store")).get("cap", 200.0))
	_living_cap = float(_open.get("living_cap", 16.0))
	_haul_speed = float(hl.get("speed", 140.0))
	_carry = float(hl.get("carry", 14.0))
	_auto_min = float(hl.get("auto_min_dead", 4.0))
	_mill_mass = float(ml.get("mass_per_s", 0.2))
	_mill_rate = float(ml.get("rate", 0.5))
	_forge_rate = float(_d(job.get("forge")).get("rate", 0.5))
	_build_rate = float(_d(job.get("build")).get("rate", 0.5))
	_build_slots = int(_d(job.get("build")).get("slots", 3))
	_stall_rate = float(_d(eco.get("stall")).get("rate", 0.15))
	_shop_rate = float(_d(eco.get("market")).get("shop_rate", 0.03))
	_price = float(_d(eco.get("market")).get("price", 1.0))
	_burn = float(_d(eco.get("pit")).get("burn_per_s", 0.6))
	_hold_s = float(_d(eco.get("upkeep")).get("unpaid_hold_s", 30.0))
	_forge_work = []
	_forge_relics = []
	var fc := _d(eco.get("forge"))
	for w in fc.get("level_work", []):
		_forge_work.append(float(w))
	for r in fc.get("level_relics", []):
		_forge_relics.append(int(r))
	while _forge_relics.size() < _forge_work.size():
		_forge_relics.append(0)
	_migrant_rate = float(town.get("migrant_rate", 0.012))
	_leave_rate = float(town.get("leave_rate", 0.004))
	_morale_base = float(morale_c.get("base", 0.6))
	_ease = float(morale_c.get("ease_per_s", 0.005))
	_dread_ratio = float(morale_c.get("dread_ratio", 4.0))
	_dread_k = float(morale_c.get("dread_k", 0.05))
	_leave_below = float(morale_c.get("leave_below", 0.35))
	_shock_s = float(morale_c.get("shock_s", 600.0))
	_default_ladder = []
	for j in job.get("default_ladder", JOBS):
		_default_ladder.append(str(j))
	_lots = []
	for l in cfgs.get("town", {}).get("lots", []):
		_lots.append(str(l.get("id", "")))
	_defs = {}
	var bcfg := _d(cfgs.get("buildings"))
	for id in bcfg:
		var b := _d(bcfg[id])
		var up := _d(b.get("upkeep"))
		_defs[str(id)] = {
			"jobs": _d(b.get("jobs")), "effects": _d(b.get("effects")),
			"upkeep_gold": float(up.get("gold", 0.0)), "upkeep_bone": float(up.get("bone", 0.0)),
			"build_work": float(b.get("build_work", 0.0)), "max_level": int(b.get("max_level", 1)),
		}


static func _d(v: Variant) -> Dictionary:
	return v if v is Dictionary else {}


## BALANCE §0: the start buildings on their lots, the opening stocks and the default ladder.
func new_game() -> void:
	workers = float(_open.get("workers", 12.0))
	bodies = float(_open.get("bodies", 40.0))
	gold = float(_open.get("gold", 80.0))
	bone = float(_open.get("bone", 30.0))
	living = float(_open.get("living", 10.0))
	shock = 0.0
	buildings = {}
	var start := _d(_open.get("buildings"))
	for lot_id in start:
		place_building(str(lot_id), str(start[lot_id]), 1)
	ladder = _default_ladder.duplicate()
	haul = {"current": "", "convoys": []}
	forge = {"level": 0, "progress": 0.0}
	rates = _zero_rates()
	_pending = []
	_restaff()
	morale = morale_target()


## Puts a finished building on a lot at once (the opening, fixtures, debug, tests). No cost, no
## event. False for an unknown lot or building, or a level outside 1..max_level.
func place_building(lot_id: String, building_id: String, level: int) -> bool:
	if not _lots.has(lot_id) or not _defs.has(building_id) or level < 1 or level > int(_defs[building_id]["max_level"]):
		return false
	var cap := int(buildings.get(lot_id, {}).get("staff_cap", -1))
	buildings[lot_id] = {"building_id": building_id, "level": level, "state": "active", "progress": 1.0,
		"staff_cap": cap, "unpaid_s": 0.0, "build_level": level}
	_restaff()
	return true


## Starts a build (level 1 on an empty lot) or an upgrade (the next level of the building already
## there). Costs and gates are the caller's (T2.4); this only checks the lot and the level. The
## lot offers `job.build.slots` build slots and nothing else until it completes.
## `building_started` comes out of the next step(). Reasons: unknown_lot, unknown_building,
## occupied, busy (already constructing), unpaid (an unpaid building can't upgrade), bad_level.
func start_construction(lot_id: String, building_id: String, level: int) -> Dictionary:
	if not _lots.has(lot_id):
		return {"ok": false, "reason": "unknown_lot"}
	if not _defs.has(building_id):
		return {"ok": false, "reason": "unknown_building"}
	if not buildings.has(lot_id):
		if level != 1:
			return {"ok": false, "reason": "bad_level"}
		buildings[lot_id] = {"building_id": building_id, "level": 0, "state": "constructing", "progress": 0.0,
			"staff_cap": -1, "unpaid_s": 0.0, "build_level": 1}
	else:
		var b: Dictionary = buildings[lot_id]
		if b["building_id"] != building_id:
			return {"ok": false, "reason": "occupied"}
		if b["state"] == "constructing":
			return {"ok": false, "reason": "busy"}
		if b["state"] == "unpaid":
			return {"ok": false, "reason": "unpaid"}
		if level != int(b["level"]) + 1 or level > int(_defs[building_id]["max_level"]):
			return {"ok": false, "reason": "bad_level"}
		b["state"] = "constructing"
		b["progress"] = 0.0
		b["unpaid_s"] = 0.0
		b["build_level"] = level
	_pending.append({"type": "building_started", "lot_id": lot_id, "building_id": building_id, "level": level})
	_restaff()
	return {"ok": true, "reason": ""}


## A death shock (E3 calls it). Each working building with `death_shock_mult` (the Statue)
## multiplies it by that, per level.
func add_shock(x: float) -> void:
	var k := 1.0
	for lot_id in _lots:
		var b: Dictionary = buildings.get(lot_id, {})
		if not b.is_empty() and WORKING.has(b["state"]) and _defs[b["building_id"]]["effects"].has("death_shock_mult"):
			k *= pow(float(_defs[b["building_id"]]["effects"]["death_shock_mult"]), int(b["level"]))
	shock = maxf(0.0, shock + x * k)


# ------------------------------------------------------------------ step ----
func step(dt: float, inp: Dictionary) -> Dictionary:
	var events: Array = _pending
	_pending = []
	var out := {"pits": 0, "feed": 0.0, "muster_mass": 0.0, "pickups": [], "relics_spent": 0,
		"rot_overflow": 0.0, "haul_overflow": 0.0, "events": events}
	if not is_finite(dt) or dt <= 0.0:
		out["rates"] = rates.duplicate(true)
		return out
	var home := bool(inp.get("relish_home", false))
	_restaff()
	var used_slots: float = staffing["slots"]
	var cap := body_cap()

	# 1. the workforce (§4.1): exact over the step, then rot to bodies and muster to WAR
	var r := maxf(0.0, float(inp.get("work_mass", 0.0))) / _mass / dt
	var life := lifetime_s(home)
	var w0 := workers
	var wf := workforce(w0, r, dt, life, _idle_rot, used_slots, _idle_cap)
	workers = wf["w"]
	var rot_mass: float = float(wf["rot"]) * _mass * _body_return
	var rot_in := clampf(cap - bodies, 0.0, rot_mass)
	bodies += rot_in
	out["rot_overflow"] = rot_mass - rot_in
	out["muster_mass"] = float(wf["muster"]) * _mass

	# 2. haul (§4.2): the convoy, as many legs as the step holds
	var haul_in := _haul(dt, inp, _job("haul"), cap, out)

	# 3. pits and mills share the bodies in proportion to what they want
	var pits := 0
	var pit_can := 0.0  # mass/s the staffed pits can burn
	for lot_id in _lots:
		var b: Dictionary = buildings.get(lot_id, {})
		if b.is_empty() or not WORKING.has(b["state"]):
			continue
		var p := int(_eff(b, "pits"))
		if p <= 0:
			continue
		pits += p
		var slots := _slots(b, "pit")
		var frac := 1.0 if slots <= 0 else float(_by_lot.get(lot_id, {}).get("pit", 0.0)) / slots
		pit_can += _burn * p * frac
	var want_pit := pit_can * dt
	var want_mill := _mill_mass * _job("mill") * dt
	var want := want_pit + want_mill
	var share := 1.0 if want <= bodies else (bodies / want if want > 0.0 else 0.0)
	var burned := want_pit * share
	var milled := want_mill * share
	bodies = maxf(0.0, bodies - burned - milled)
	var bone_in := milled * _mill_rate
	bone += bone_in
	var wanted := _burn * pits * dt
	out["pits"] = pits
	out["feed"] = clampf(burned / wanted, 0.0, 1.0) if wanted > 0.0 else 0.0

	# 4. stalls: gold = min(staffed · stall.rate, living · shop_rate) · price
	var sales := minf(_job("stall") * _stall_rate, living * _shop_rate)
	var gold_in := sales * _price * dt
	gold += gold_in

	# 5. the forge: work toward the next q level; a level completes only with its relics
	var forge_work := 0.0
	var relics_left := int(inp.get("relics_available", 0))
	var spent := 0
	if int(forge["level"]) < _forge_work.size():
		forge_work = _forge_rate * _job("forge") * dt
		forge["progress"] = float(forge["progress"]) + forge_work
		while int(forge["level"]) < _forge_work.size():
			var lvl := int(forge["level"])
			var need: float = _forge_work[lvl]
			if float(forge["progress"]) < need:
				break
			if relics_left < _forge_relics[lvl]:
				forge["progress"] = need
				break
			relics_left -= _forge_relics[lvl]
			spent += _forge_relics[lvl]
			forge["progress"] = float(forge["progress"]) - need
			forge["level"] = lvl + 1
		if int(forge["level"]) >= _forge_work.size():
			forge["progress"] = 0.0
	out["relics_spent"] = spent

	# 6. construction: build_work · target level, at job.build.rate per staffed builder
	var build_work := 0.0
	for lot_id in _lots:
		var b: Dictionary = buildings.get(lot_id, {})
		if b.is_empty() or b["state"] != "constructing":
			continue
		var w := _build_rate * float(_by_lot.get(lot_id, {}).get("build", 0.0)) * dt
		build_work += w
		var need := float(_defs[b["building_id"]]["build_work"]) * int(b["build_level"])
		b["progress"] = 1.0 if need <= 0.0 else float(b["progress"]) + w / need
		if float(b["progress"]) >= 1.0 - EPS:
			b["level"] = int(b["build_level"])
			b["state"] = "active"
			b["progress"] = 1.0
			events.append({"type": "building_done", "lot_id": lot_id, "building_id": b["building_id"], "level": int(b["level"])})

	# 7. the living (§4.3): exact first-order update, then the housing cap
	var lcap := living_cap()
	var mig := float(inp.get("held_villages", 0)) * _migrant_rate
	for lot_id in _lots:
		var b: Dictionary = buildings.get(lot_id, {})
		if not b.is_empty() and WORKING.has(b["state"]):
			mig += _eff(b, "attract")
	var k := _leave_rate if morale < _leave_below else 0.0
	var l0 := living
	var l1 := l0 + mig * dt
	if k > 0.0:
		var ss := mig / k
		l1 = ss + (l0 - ss) * exp(-k * dt)
	var dep := maxf(0.0, mig * dt - (l1 - l0))
	living = clampf(l1, 0.0, maxf(0.0, lcap))
	var net_l := living - l0
	var living_in := maxf(0.0, net_l + dep)
	var living_out := living_in - net_l

	# 8. morale eases toward its target; the shock decays
	shock = shock * exp(-dt / _shock_s) if _shock_s > 0.0 else 0.0
	morale = clampf(move_toward(morale, morale_target(), _ease * dt), 0.0, 1.0)

	# 9. upkeep: resume after the hold when the stock covers it, idle the cheapest when short
	var paid := _upkeep(dt, events)

	# 10. rates for the views
	var tend := _job("tend")
	_restaff()
	rates = {
		"workers": {"in": r, "out": (float(wf["rot"]) + float(wf["muster"])) / dt, "rot": float(wf["rot"]) / dt,
			"muster": float(wf["muster"]) / dt, "steady": r * life, "lifetime_s": life, "slots": used_slots},
		"bodies": {"in": (rot_in + haul_in) / dt, "out": (burned + milled) / dt, "rot": rot_in / dt, "haul": haul_in / dt,
			"pit": burned / dt, "mill": milled / dt, "overflow": (float(out["rot_overflow"]) + float(out["haul_overflow"])) / dt},
		"gold": {"in": gold_in / dt, "out": float(paid["gold"]) / dt},
		"bone": {"in": bone_in / dt, "out": float(paid["bone"]) / dt},
		"living": {"in": living_in / dt, "out": living_out / dt},
		"trade_rate": sales, "haul_trip": float(rates.get("haul_trip", 0.0)) if _haul_trip < 0.0 else _haul_trip,
		"forge": forge_work / dt, "build": build_work / dt, "tend": tend, "feed": float(out["feed"]),
	}
	out["rates"] = rates.duplicate(true)
	return out


## The workforce's exact update over `dt` (MECHANICS §4.1, IDLE §4), in workers.
## Inflow `r` workers/s, lifetime `life` s, idle rot multiplier `m`, `slots` staffable workers,
## `idle_cap`. The ODE is linear in three regimes, so each piece uses the exact
## w(t) = w_ss + (w − w_ss)e^(−t/τ) and the boundary crossings are timed exactly:
## - all staffed (w ≤ S): w' = r − w/L (τ = L, w_ss = rL);
## - some idle (S < w < S + C): w' = r − S/L − m(w − S)/L (τ = L/m, w_ss = S + (rL − S)/m);
## - pinned at S + C: the surplus r − (S + mC)/L is mustered.
## Workers above S + C at the start are mustered at once. Returns {w, rot, muster} in workers;
## rot = r·dt − Δw − muster, so the three always balance.
static func workforce(w0: float, r: float, dt: float, life: float, m: float, slots: float, idle_cap: float) -> Dictionary:
	var s := maxf(0.0, slots)
	var top := s + maxf(0.0, idle_cap)
	var L := maxf(EPS, life)
	var w := maxf(0.0, w0)
	var start := w
	var muster := 0.0
	if w > top:
		muster = w - top
		w = top
	var ss_b := s + (r * L - s) / m if m > 0.0 else 0.0
	var rises_to_cap := ss_b > top if m > 0.0 else r - s / L > 0.0
	var left := dt
	for _i in 8:
		if left <= 0.0:
			break
		if w >= top and rises_to_cap:
			muster += (m * (ss_b - top) / L if m > 0.0 else r - s / L) * left
			left = 0.0
		elif w < s or (w <= s and r * L <= s):
			var ss := r * L
			if ss > s:
				var tc := L * log((ss - w) / (ss - s))
				if tc < left:
					w = s
					left -= tc
					continue
			w = ss + (w - ss) * exp(-left / L)
			left = 0.0
		elif m > 0.0:
			var tau := L / m
			if ss_b > top:
				var tc := tau * log((ss_b - w) / (ss_b - top))
				if tc < left:
					w = top
					left -= tc
					continue
			elif ss_b < s:
				var tc := tau * log((w - ss_b) / (s - ss_b))
				if tc < left:
					w = s
					left -= tc
					continue
			w = ss_b + (w - ss_b) * exp(-left / tau)
			left = 0.0
		else:
			var slope := r - s / L
			if slope > 0.0 and (top - w) / slope < left:
				left -= (top - w) / slope
				w = top
				continue
			if slope < 0.0 and (w - s) / -slope < left:
				left -= (w - s) / -slope
				w = s
				continue
			w += slope * left
			left = 0.0
	w = clampf(w, 0.0, top)
	return {"w": w, "rot": maxf(0.0, r * dt - (w - start) - muster), "muster": muster}


## The convoy. A leg takes distance / (job.haul.speed · stables) seconds. It leaves when haulers
## are staffed, the store is under the cap and there is a target (auto: the fort with the most
## dead above job.haul.auto_min_dead). The crew is fixed at departure. At arrival it picks up
## carry · crew (× flip.haul_mult at a held fort), clamped to the fort's dead left in the snapshot
## and to the store's headroom; on the way back the load lands in bodies.
func _haul(dt: float, inp: Dictionary, crew_now: float, cap: float, out: Dictionary) -> float:
	_haul_trip = -1.0
	var forts: Array = inp.get("forts", [])
	var by_id := {}
	for f in forts:
		by_id[str(f.get("id", ""))] = f
	var cov := _xy(inp.get("cov_pos", [0.0, 0.0]))
	var target := str(inp.get("haul_target", "auto"))
	var speed := _haul_speed * (1.0 + _sum_working("haul_speed_mult"))
	var convoys: Array = haul["convoys"]
	var taken := {}
	var delivered := 0.0
	var left := dt
	for _i in MAX_LEGS:
		if left <= 0.0:
			break
		if convoys.is_empty():
			if crew_now <= EPS or bodies >= cap - EPS or speed <= 0.0:
				break
			var fid := _haul_pick(forts, target, taken)
			if fid == "":
				break
			var trip := maxf(MIN_TRIP_S, cov.distance_to(_xy(by_id[fid].get("pos", [0.0, 0.0]))) / speed)
			convoys.append({"fort": fid, "phase": "out", "t": 0.0, "trip_s": trip, "load": 0.0, "crew": crew_now})
			haul["current"] = fid
		var c: Dictionary = convoys[0]
		var need: float = (1.0 - float(c["t"])) * float(c["trip_s"])
		if need > left:
			c["t"] = float(c["t"]) + left / float(c["trip_s"])
			left = 0.0
			break
		left -= need
		if c["phase"] == "out":
			var f: Dictionary = by_id.get(c["fort"], {})
			var avail := maxf(0.0, float(f.get("dead", 0.0)) - float(taken.get(c["fort"], 0.0)))
			var mult := _haul_mult if bool(f.get("held", false)) else 1.0
			var load := minf(minf(avail, _carry * float(c["crew"]) * mult), maxf(0.0, cap - bodies))
			taken[c["fort"]] = float(taken.get(c["fort"], 0.0)) + load
			c["load"] = load
			c["phase"] = "back"
			c["t"] = 0.0
		else:
			var add := clampf(cap - bodies, 0.0, float(c["load"]))
			bodies += add
			delivered += add
			out["haul_overflow"] = float(out["haul_overflow"]) + float(c["load"]) - add
			_haul_trip = float(c["load"]) / (2.0 * float(c["trip_s"]))
			convoys.clear()
			haul["current"] = ""
	var picks: Array = []
	for f in forts:
		var id := str(f.get("id", ""))
		if float(taken.get(id, 0.0)) > 0.0:
			picks.append({"fort_id": id, "mass": float(taken[id])})
	out["pickups"] = picks
	return delivered


func _haul_pick(forts: Array, target: String, taken: Dictionary) -> String:
	if target != "auto":
		for f in forts:
			if str(f.get("id", "")) == target:
				return target
		return ""
	var best := ""
	var most := _auto_min
	for f in forts:
		var id := str(f.get("id", ""))
		var dead := float(f.get("dead", 0.0)) - float(taken.get(id, 0.0))
		if dead > most:
			most = dead
			best = id
	return best


## Upkeep (§4.3). Unpaid buildings whose hold is over resume (lot order) when the stock covers
## the paying upkeep plus theirs for max(unpaid_hold_s, dt). Then, while a stock can't cover this
## step's upkeep, the cheapest paying building by its upkeep in that stock (ties in lot order)
## goes unpaid, except a building that earns that stock (stalls for gold, mills for bone): idling
## it could never pay the bill back. What is still owed is paid down to 0; there is no debt.
func _upkeep(dt: float, events: Array) -> Dictionary:
	var due_g := 0.0
	var due_b := 0.0
	for lot_id in _lots:
		var b: Dictionary = buildings.get(lot_id, {})
		if b.is_empty():
			continue
		if WORKING.has(b["state"]):
			due_g += float(_defs[b["building_id"]]["upkeep_gold"])
			due_b += float(_defs[b["building_id"]]["upkeep_bone"])
		elif b["state"] == "unpaid":
			b["unpaid_s"] = maxf(0.0, float(b["unpaid_s"]) - dt)
	var span := maxf(_hold_s, dt)
	for lot_id in _lots:
		var b: Dictionary = buildings.get(lot_id, {})
		if b.is_empty() or b["state"] != "unpaid" or float(b["unpaid_s"]) > 0.0:
			continue
		var ug := float(_defs[b["building_id"]]["upkeep_gold"])
		var ub := float(_defs[b["building_id"]]["upkeep_bone"])
		if gold >= (due_g + ug) * span and bone >= (due_b + ub) * span:
			b["state"] = "active"
			due_g += ug
			due_b += ub
			events.append({"type": "building_unpaid", "lot_id": lot_id, "building_id": b["building_id"], "unpaid": false})
	var owe_g := due_g * dt
	var owe_b := due_b * dt
	while gold < owe_g - EPS or bone < owe_b - EPS:
		var short := "gold" if gold < owe_g - EPS else "bone"
		var key := "upkeep_" + short
		var earner := "stall" if short == "gold" else "mill"
		var pick := ""
		var cheapest := INF
		for lot_id in _lots:
			var b: Dictionary = buildings.get(lot_id, {})
			if b.is_empty() or not WORKING.has(b["state"]):
				continue
			var d: Dictionary = _defs[b["building_id"]]
			var u := float(d[key])
			if u > 0.0 and u < cheapest and int(d["jobs"].get(earner, 0)) <= 0:
				cheapest = u
				pick = lot_id
		if pick == "":
			break
		var pb: Dictionary = buildings[pick]
		pb["state"] = "unpaid"
		pb["unpaid_s"] = _hold_s
		owe_g -= float(_defs[pb["building_id"]]["upkeep_gold"]) * dt
		owe_b -= float(_defs[pb["building_id"]]["upkeep_bone"]) * dt
		events.append({"type": "building_unpaid", "lot_id": pick, "building_id": pb["building_id"], "unpaid": true})
	var pg := clampf(owe_g, 0.0, gold)
	var pbn := clampf(owe_b, 0.0, bone)
	gold -= pg
	bone -= pbn
	return {"gold": pg, "bone": pbn}


# --------------------------------------------------------- the job ladder ----
## Workers fill job slots top-down in ladder order, buildings in lot order, each lot up to its
## staff cap. A working building offers jobs × level slots; a constructing lot offers
## job.build.slots build slots; unpaid buildings offer none. Rebuilds `staffing` only.
func _staff() -> void:
	var used := {}
	var rooms: Array = []  # [lot_id, job, room] in fill order
	var jobs := {}
	var total := 0.0
	for job in ladder:
		if not JOBS.has(job) or jobs.has(job):
			continue
		var n := 0
		for lot_id in _lots:
			var b: Dictionary = buildings.get(lot_id, {})
			if b.is_empty():
				continue
			var k := _slots(b, job)
			if k <= 0:
				continue
			n += k
			var room := float(k)
			if int(b["staff_cap"]) >= 0:
				room = clampf(float(b["staff_cap"]) - float(used.get(lot_id, 0.0)), 0.0, room)
			used[lot_id] = float(used.get(lot_id, 0.0)) + room
			rooms.append([lot_id, job, room])
			total += room
		jobs[job] = {"slots": n, "staffed": 0.0}
	var left := maxf(0.0, workers)
	var lots := {}
	_by_lot = {}
	for e in rooms:
		var take := minf(float(e[2]), left)
		left -= take
		jobs[e[1]]["staffed"] = float(jobs[e[1]]["staffed"]) + take
		lots[e[0]] = float(lots.get(e[0], 0.0)) + take
		if not _by_lot.has(e[0]):
			_by_lot[e[0]] = {}
		_by_lot[e[0]][e[1]] = float(_by_lot[e[0]].get(e[1], 0.0)) + take
	staffing = {"jobs": jobs, "lots": lots, "idle": left, "slots": total}


## `_staff()`, then marks working buildings that have job slots `active` (someone staffed) or
## `idle` (nobody). A load never calls this, so a saved state comes back as it was saved.
func _restaff() -> void:
	_staff()
	var lots: Dictionary = staffing["lots"]
	for lot_id in buildings:
		var b: Dictionary = buildings[lot_id]
		if not WORKING.has(b["state"]):
			continue
		var has_jobs := false
		for j in _defs[b["building_id"]]["jobs"]:
			has_jobs = has_jobs or int(_defs[b["building_id"]]["jobs"][j]) > 0
		b["state"] = "active" if not has_jobs or float(lots.get(lot_id, 0.0)) > 0.0 else "idle"


func _slots(b: Dictionary, job: String) -> int:
	if job == "build":
		return _build_slots if b["state"] == "constructing" else 0
	if not WORKING.has(b["state"]):
		return 0
	return int(_defs[b["building_id"]]["jobs"].get(job, 0)) * int(b["level"])


func _job(job: String) -> float:
	return float(staffing.get("jobs", {}).get(job, {}).get("staffed", 0.0))


# ------------------------------------------------------- effects and caps ----
## A building's numeric effect at its level: a number is per level (× level); an Array is a
## per-level table (index level − 1). 0 before the first build completes.
func _eff(b: Dictionary, key: String) -> float:
	var lv := int(b["level"])
	var v: Variant = _defs[b["building_id"]]["effects"].get(key, null)
	if v == null or lv <= 0:
		return 0.0
	if v is Array:
		return float(v[mini(lv, v.size()) - 1]) if not v.is_empty() else 0.0
	return float(v) * lv


func _sum_working(key: String) -> float:
	var s := 0.0
	for lot_id in _lots:
		var b: Dictionary = buildings.get(lot_id, {})
		if not b.is_empty() and WORKING.has(b["state"]):
			s += _eff(b, key)
	return s


## Capacity effects count for every built level, unpaid or mid-upgrade too, so an unpaid spell
## never destroys stock.
func _sum_built(key: String) -> float:
	var s := 0.0
	for lot_id in _lots:
		if buildings.has(lot_id):
			s += _eff(buildings[lot_id], key)
	return s


func body_cap() -> float:
	return _body_cap + _sum_built("body_cap")


## opening.living_cap (the crypt district's huts) plus housing.
func living_cap() -> float:
	return _living_cap + _sum_built("living_cap")


## worker.lifetime_s · (1 + Σ lifetime_bonus) / home_rot_mult while Relish is home.
func lifetime_s(relish_home: bool) -> float:
	return _lifetime * (1.0 + _sum_working("lifetime_bonus")) / (_home_rot if relish_home else 1.0)


## The morale target's terms for view_town: base, amenity:<building_id> (working buildings'
## `morale`, summed per building id in lot order), dread and shock (each only when non-zero).
func morale_factors() -> Array:
	var out: Array = [{"id": "base", "delta": _morale_base}]
	var amen := {}
	for lot_id in _lots:
		var b: Dictionary = buildings.get(lot_id, {})
		if b.is_empty() or not WORKING.has(b["state"]):
			continue
		var v := _eff(b, "morale")
		if v != 0.0:
			amen[b["building_id"]] = float(amen.get(b["building_id"], 0.0)) + v
	for id in amen:
		out.append({"id": "amenity:" + str(id), "delta": amen[id]})
	var dread := maxf(0.0, workers / maxf(living, 1.0) - _dread_ratio) * _dread_k
	if dread > 0.0:
		out.append({"id": "dread", "delta": -dread})
	if shock > 0.0:
		out.append({"id": "shock", "delta": -shock})
	return out


func morale_target() -> float:
	var s := 0.0
	for f in morale_factors():
		s += float(f["delta"])
	return clampf(s, 0.0, 1.0)


# ---------------------------------------------------------- persistence ----
## JSON-safe, floats canonical (SaveIO.canon), buildings in lot order.
func to_dict() -> Dictionary:
	var bl: Array = []
	for lot_id in _lots:
		if buildings.has(lot_id):
			var b: Dictionary = buildings[lot_id]
			bl.append({"lot_id": lot_id, "building_id": b["building_id"], "level": int(b["level"]), "state": b["state"],
				"progress": float(b["progress"]), "staff_cap": int(b["staff_cap"]), "unpaid_s": float(b["unpaid_s"]),
				"build_level": int(b["build_level"])})
	var cv: Array = []
	for c in haul["convoys"]:
		cv.append({"fort": str(c["fort"]), "phase": str(c["phase"]), "t": float(c["t"]), "trip_s": float(c["trip_s"]),
			"load": float(c["load"]), "crew": float(c["crew"])})
	var d := {
		"workers": workers, "bodies": bodies, "gold": gold, "bone": bone, "living": living, "morale": morale, "shock": shock,
		"buildings": bl, "ladder": ladder.duplicate(), "haul": {"current": str(haul["current"]), "convoys": cv},
		"forge": {"level": int(forge["level"]), "progress": float(forge["progress"])}, "rates": rates.duplicate(true),
	}
	return SaveIO.canon(d)


func from_dict(d: Dictionary) -> void:
	workers = float(d.get("workers", 0.0))
	bodies = float(d.get("bodies", 0.0))
	gold = float(d.get("gold", 0.0))
	bone = float(d.get("bone", 0.0))
	living = float(d.get("living", 0.0))
	morale = float(d.get("morale", _morale_base))
	shock = float(d.get("shock", 0.0))
	buildings = {}
	for e in d.get("buildings", []):
		var lot_id := str(e.get("lot_id", ""))
		var bid := str(e.get("building_id", ""))
		if not _lots.has(lot_id) or not _defs.has(bid):
			continue
		buildings[lot_id] = {"building_id": bid, "level": int(e.get("level", 1)), "state": str(e.get("state", "active")),
			"progress": float(e.get("progress", 1.0)), "staff_cap": int(e.get("staff_cap", -1)),
			"unpaid_s": float(e.get("unpaid_s", 0.0)), "build_level": int(e.get("build_level", e.get("level", 1)))}
	ladder = []
	for j in d.get("ladder", _default_ladder):
		ladder.append(str(j))
	var h := _d(d.get("haul"))
	haul = {"current": str(h.get("current", "")), "convoys": []}
	for c in h.get("convoys", []):
		haul["convoys"].append({"fort": str(c.get("fort", "")), "phase": str(c.get("phase", "out")), "t": float(c.get("t", 0.0)),
			"trip_s": float(c.get("trip_s", 1.0)), "load": float(c.get("load", 0.0)), "crew": float(c.get("crew", 0.0))})
	var fg := _d(d.get("forge"))
	forge = {"level": int(fg.get("level", 0)), "progress": float(fg.get("progress", 0.0))}
	rates = _zero_rates()
	var rd := _d(d.get("rates"))
	for k in rates:
		if rd.has(k):
			rates[k] = rd[k].duplicate(true) if rd[k] is Dictionary else float(rd[k])
	_pending = []
	_staff()


static func _zero_rates() -> Dictionary:
	return {
		"workers": {"in": 0.0, "out": 0.0, "rot": 0.0, "muster": 0.0, "steady": 0.0, "lifetime_s": 0.0, "slots": 0.0},
		"bodies": {"in": 0.0, "out": 0.0, "rot": 0.0, "haul": 0.0, "pit": 0.0, "mill": 0.0, "overflow": 0.0},
		"gold": {"in": 0.0, "out": 0.0},
		"bone": {"in": 0.0, "out": 0.0},
		"living": {"in": 0.0, "out": 0.0},
		"trade_rate": 0.0, "haul_trip": 0.0, "forge": 0.0, "build": 0.0, "tend": 0.0, "feed": 0.0,
	}


static func _xy(a: Variant) -> Vector2:
	if a is Array and a.size() >= 2:
		return Vector2(float(a[0]), float(a[1]))
	return Vector2.ZERO
