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
##   rot_loss: float        rotted mass that never returns as bodies, (1 − body_return) (a ledger sink)
##   burned, milled: float  bodies the pits burned and the mills milled (mass; ledger sinks)
##   events: Array          {type, ...} without `t` (GameState stamps it): building_started,
##                          building_done, building_unpaid
##   rates: Dictionary      this substep's flows per second (a copy of `rates`)

const JOBS := ["haul", "mill", "stall", "forge", "pit", "tend", "build"]
const WORKING := ["active", "idle"]  # built, paid and not under construction (_works() adds a building mid-upgrade)
const EPS := 1e-9
const MAX_LEGS := 256  # convoy legs one step may run (a long catch-up step makes many trips)
const MIN_TRIP_S := 0.01

## Every config value TownSim reads, as "file.section.key" paths. setup() reads only these, and
## tests/test_game_state_configs.gd asserts each one is present in res://configs, so the numbers
## live in the configs alone. (Per-building keys are covered by the buildings.json shape test.)
const REQUIRED := [
	"economy.opening.workers", "economy.opening.bodies", "economy.opening.gold", "economy.opening.bone",
	"economy.opening.living", "economy.opening.living_cap", "economy.opening.buildings",
	"economy.worker.mass", "economy.worker.lifetime_s", "economy.worker.body_return",
	"economy.worker.idle_rot_mult", "economy.worker.idle_cap", "economy.body_store.cap",
	"economy.morale.base", "economy.morale.ease_per_s", "economy.morale.dread_ratio", "economy.morale.dread_k",
	"economy.morale.leave_below", "economy.morale.shock_s",
	"economy.job.default_ladder", "economy.job.haul.speed", "economy.job.haul.carry", "economy.job.haul.auto_min_dead",
	"economy.job.mill.mass_per_s", "economy.job.mill.rate", "economy.job.forge.rate",
	"economy.job.build.rate", "economy.job.build.slots",
	"economy.stall.rate", "economy.market.shop_rate", "economy.market.price", "economy.pit.burn_per_s",
	"economy.upkeep.unpaid_hold_s", "economy.forge.level_work", "economy.forge.level_relics",
	"economy.town.migrant_rate", "economy.town.leave_rate",
	"realm.relish.home_rot_mult", "realm.flip.haul_mult", "town.lots", "buildings",
]

# ---- tunables, read once in setup() from REQUIRED (no numbers here) ----
var _lots: Array[String] = []  # town.json lot ids, in order
var _defs := {}  # building id -> {jobs: {job: int}, effects: {}, upkeep_gold, upkeep_bone, build_work, max_level}
var _start := {}  # economy.json opening: workers, bodies, gold, bone, living (floats), buildings {lot_id: id}
var _default_ladder: Array[String] = []
var _mass := 0.0
var _lifetime := 0.0
var _body_return := 0.0
var _idle_rot := 0.0
var _idle_cap := 0.0
var _home_rot := 0.0
var _body_cap := 0.0
var _living_cap := 0.0
var _haul_speed := 0.0
var _carry := 0.0
var _auto_min := 0.0
var _haul_mult := 0.0
var _mill_mass := 0.0
var _mill_rate := 0.0
var _forge_rate := 0.0
var _build_rate := 0.0
var _build_slots := 0
var _stall_rate := 0.0
var _shop_rate := 0.0
var _price := 0.0
var _burn := 0.0
var _hold_s := 0.0
var _forge_work: Array[float] = []
var _forge_relics: Array[int] = []
var _migrant_rate := 0.0
var _leave_rate := 0.0
var _morale_base := 0.0
var _ease := 0.0
var _dread_ratio := 0.0
var _dread_k := 0.0
var _leave_below := 0.0
var _shock_s := 0.0

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
## The job order, top first. Assigning it marks the rooms dirty (_mark_rooms).
var ladder: Array = []:
	set(v):
		ladder = v
		_mark_rooms()
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
## The allocation's rooms (staff_rooms), cached: they change only when the ladder, a building (its
## arrival or removal, state, level or staff cap) or the vats do, and every place that changes one
## calls _mark_rooms(). Filling them with the workers each step is cheap (E2b T4.P).
var _rooms := {}
var _rooms_dirty := true
## The workforce the last _restaff() filled and marked the states with; NAN once anything since may
## differ. _restaff() with clean rooms and this workforce has nothing to redo.
var _staffed_w := NAN
## _sum_working() and _sum_built() per effect key, cached like the rooms: they read only the
## buildings' states and levels, so _mark_rooms() clears them.
var _sums_w := {}
var _sums_b := {}
## The vats staffed, per vat slot (GameState's vats_staffed, which it saves; set_vats), trailing
## falses dropped. A vat slot's tend room is open only while its vat is staffed (MECHANICS §7).
var _vats: Array[bool] = []
var _n_rooms := 0  # staff_rooms() builds, for tests (not saved)
var _n_fills := 0  # staff_fill() runs from _staff(), for tests (not saved)
var _pending: Array = []  # events from commands, returned by the next step()
var _haul_trip := -1.0  # this step's landed trip, load / round trip (mass/s); -1 when none landed


func setup(cfgs: Dictionary) -> void:
	for k in ["workers", "bodies", "gold", "bone", "living"]:
		_start[k] = _num(cfgs, "economy.opening." + k)
	_start["buildings"] = _d(_at(cfgs, "economy.opening.buildings")).duplicate(true)
	_living_cap = _num(cfgs, "economy.opening.living_cap")
	_mass = maxf(EPS, _num(cfgs, "economy.worker.mass"))
	_lifetime = maxf(EPS, _num(cfgs, "economy.worker.lifetime_s"))
	_body_return = _num(cfgs, "economy.worker.body_return")
	_idle_rot = maxf(0.0, _num(cfgs, "economy.worker.idle_rot_mult"))
	_idle_cap = maxf(0.0, _num(cfgs, "economy.worker.idle_cap"))
	_home_rot = maxf(EPS, _num(cfgs, "realm.relish.home_rot_mult"))
	_haul_mult = _num(cfgs, "realm.flip.haul_mult")
	_body_cap = _num(cfgs, "economy.body_store.cap")
	_haul_speed = _num(cfgs, "economy.job.haul.speed")
	_carry = _num(cfgs, "economy.job.haul.carry")
	_auto_min = _num(cfgs, "economy.job.haul.auto_min_dead")
	_mill_mass = _num(cfgs, "economy.job.mill.mass_per_s")
	_mill_rate = _num(cfgs, "economy.job.mill.rate")
	_forge_rate = _num(cfgs, "economy.job.forge.rate")
	_build_rate = _num(cfgs, "economy.job.build.rate")
	_build_slots = int(_num(cfgs, "economy.job.build.slots"))
	_stall_rate = _num(cfgs, "economy.stall.rate")
	_shop_rate = _num(cfgs, "economy.market.shop_rate")
	_price = _num(cfgs, "economy.market.price")
	_burn = _num(cfgs, "economy.pit.burn_per_s")
	_hold_s = _num(cfgs, "economy.upkeep.unpaid_hold_s")
	_forge_work = []
	_forge_relics = []
	for w in _arr(_at(cfgs, "economy.forge.level_work")):
		_forge_work.append(float(w))
	for r in _arr(_at(cfgs, "economy.forge.level_relics")):
		_forge_relics.append(int(r))
	while _forge_relics.size() < _forge_work.size():
		_forge_relics.append(0)
	_migrant_rate = _num(cfgs, "economy.town.migrant_rate")
	_leave_rate = _num(cfgs, "economy.town.leave_rate")
	_morale_base = _num(cfgs, "economy.morale.base")
	_ease = _num(cfgs, "economy.morale.ease_per_s")
	_dread_ratio = _num(cfgs, "economy.morale.dread_ratio")
	_dread_k = _num(cfgs, "economy.morale.dread_k")
	_leave_below = _num(cfgs, "economy.morale.leave_below")
	_shock_s = _num(cfgs, "economy.morale.shock_s")
	_default_ladder = []
	for j in _arr(_at(cfgs, "economy.job.default_ladder")):
		_default_ladder.append(str(j))
	_lots = []
	for l in _arr(_at(cfgs, "town.lots")):
		_lots.append(str(_d(l).get("id", "")))
	_defs = {}
	var bcfg := _d(_at(cfgs, "buildings"))
	for id in bcfg:
		var b := _d(bcfg[id])
		var up := _d(b.get("upkeep"))
		var jobs := _d(b.get("jobs"))
		var has_jobs := false
		for j in jobs:
			has_jobs = has_jobs or int(jobs[j]) > 0
		_defs[str(id)] = {
			"jobs": jobs, "effects": _d(b.get("effects")),
			"upkeep_gold": float(up.get("gold", 0.0)), "upkeep_bone": float(up.get("bone", 0.0)),
			"build_work": float(b.get("build_work", 0.0)), "max_level": int(b.get("max_level", 0)),
			"has_jobs": has_jobs,
		}
	_mark_rooms()


## The config value at a REQUIRED path. A missing one is reported loudly and reads as null.
static func _at(cfgs: Dictionary, path: String) -> Variant:
	assert(REQUIRED.has(path), "TownSim reads %s; add it to REQUIRED" % path)
	var v: Variant = cfgs
	for k in path.split("."):
		if not (v is Dictionary and (v as Dictionary).has(k)):
			push_error("TownSim: config %s is missing" % path)
			return null
		v = v[k]
	return v


static func _num(cfgs: Dictionary, path: String) -> float:
	var v: Variant = _at(cfgs, path)
	return float(v) if v is float or v is int else 0.0


static func _arr(v: Variant) -> Array:
	return v if v is Array else []


static func _d(v: Variant) -> Dictionary:
	return v if v is Dictionary else {}


## BALANCE §0: the start buildings on their lots, the opening stocks and the default ladder.
func new_game() -> void:
	workers = float(_start["workers"])
	bodies = float(_start["bodies"])
	gold = float(_start["gold"])
	bone = float(_start["bone"])
	living = float(_start["living"])
	shock = 0.0
	buildings = {}
	_vats = []
	_mark_rooms()
	var start: Dictionary = _start["buildings"]
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
	_mark_rooms()
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
	_mark_rooms()
	_restaff()
	return {"ok": true, "reason": ""}


## Cancels the construction under way on a lot (costs and refunds are the caller's). A first build
## frees the lot; an upgrade goes back to its old level, working as before. The `building_started`
## it queued, if no step() has returned it yet, is dropped. Reasons: unknown_lot, not_building.
## `level` is the level the construction was heading to.
func cancel_construction(lot_id: String) -> Dictionary:
	if not _lots.has(lot_id):
		return {"ok": false, "reason": "unknown_lot", "building_id": "", "level": 0, "upgrade": false}
	var b: Dictionary = buildings.get(lot_id, {})
	if b.is_empty() or b["state"] != "constructing":
		return {"ok": false, "reason": "not_building", "building_id": "", "level": 0, "upgrade": false}
	var out := {"ok": true, "reason": "", "building_id": b["building_id"], "level": int(b["build_level"]), "upgrade": int(b["level"]) >= 1}
	if out["upgrade"]:
		b["state"] = "active"
		b["progress"] = 1.0
		b["build_level"] = int(b["level"])
	else:
		buildings.erase(lot_id)
	_drop_pending(lot_id)
	_mark_rooms()
	_restaff()
	return out


## Removes a finished building (no refund; GameState's rules). Reasons: unknown_lot, empty_lot,
## constructing (cancel_construction first). Its staff cap goes with it.
func demolish(lot_id: String) -> Dictionary:
	if not _lots.has(lot_id):
		return {"ok": false, "reason": "unknown_lot"}
	var b: Dictionary = buildings.get(lot_id, {})
	if b.is_empty():
		return {"ok": false, "reason": "empty_lot"}
	if b["state"] == "constructing":
		return {"ok": false, "reason": "constructing"}
	buildings.erase(lot_id)
	_drop_pending(lot_id)
	_mark_rooms()
	_restaff()
	return {"ok": true, "reason": ""}


func _drop_pending(lot_id: String) -> void:
	_pending = _pending.filter(func(e): return not (e.get("type", "") == "building_started" and e.get("lot_id", "") == lot_id))


## The sum of a building effect over every built building (a level counts once its build is done,
## unpaid or mid-upgrade too): caps and slots, as GameState reads them.
func built_effect(key: String) -> float:
	return _sum_built(key)


## The player's job order, top first (a permutation of JOBS; GameState checks it), then a restaff.
func set_ladder(order: Array) -> void:
	var o: Array = []
	for j in order:
		o.append(str(j))
	ladder = o  # marks the rooms dirty
	_restaff()


## A lot's staff cap (-1 = none), then a restaff. False (nothing changes) for a lot with no building.
func set_staff_cap(lot_id: String, cap: int) -> bool:
	if not buildings.has(lot_id):
		return false
	buildings[lot_id]["staff_cap"] = cap
	_mark_rooms()
	_restaff()
	return true


## Which vats are staffed (bool per vat slot; GameState's vats_staffed): each staffed vat opens its
## Chapel's tend slot (MECHANICS §7). A change marks the rooms dirty and restaffs at once; `on_load`
## refills without marking the states (a load restores them as saved). Nothing changes when the
## staffed set is the same.
func set_vats(staffed: Array, on_load := false) -> void:
	var v := _vat_list(staffed)
	if v == _vats:
		return
	_vats = v
	_mark_rooms()
	if on_load:
		_staff()
	else:
		_restaff()


## `staffed` as a vat list: bool per slot, trailing falses dropped (so [true] and [true, false] agree).
static func _vat_list(staffed: Array) -> Array[bool]:
	var v: Array[bool] = []
	for x in staffed:
		v.append(bool(x))
	while not v.is_empty() and not v[v.size() - 1]:
		v.pop_back()
	return v


## The vats as set_vats() keeps them, for the allocation and tests.
func vats_on() -> Array[bool]:
	return _vats.duplicate()


## Refills the job slots from scratch after a stock or a building was changed directly (a debug
## grant of workers; tests that edit `buildings`): the rooms are rebuilt too.
func restaff() -> void:
	_mark_rooms()
	_restaff()


## A death shock (E3 calls it). Each working building with `death_shock_mult` (the Statue)
## multiplies it by that, per level.
func add_shock(x: float) -> void:
	var k := 1.0
	for lot_id in _lots:
		var b: Dictionary = buildings.get(lot_id, {})
		if not b.is_empty() and _works(b) and _defs[b["building_id"]]["effects"].has("death_shock_mult"):
			k *= pow(float(_defs[b["building_id"]]["effects"]["death_shock_mult"]), int(b["level"]))
	shock = maxf(0.0, shock + x * k)


# ------------------------------------------------------------------ step ----
func step(dt: float, inp: Dictionary) -> Dictionary:
	var events: Array = _pending
	_pending = []
	var out := {"pits": 0, "feed": 0.0, "muster_mass": 0.0, "pickups": [], "relics_spent": 0,
		"rot_overflow": 0.0, "haul_overflow": 0.0, "rot_loss": 0.0, "burned": 0.0, "milled": 0.0, "events": events}
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
	var rotted: float = float(wf["rot"]) * _mass
	var rot_mass: float = rotted * _body_return
	out["rot_loss"] = rotted - rot_mass
	out["muster_mass"] = float(wf["muster"]) * _mass

	# 2. what the pits and the mills want this step (the pits have first call on the bodies, step 4)
	var pits := 0
	var pit_can := 0.0  # mass/s the staffed pits can burn
	for lot_id in _lots:
		var b: Dictionary = buildings.get(lot_id, {})
		if b.is_empty() or not _works(b):
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

	# 3. haul (§4.2): the convoy, as many legs as the step holds. Its departures and pickups see the
	# store's projected level (rot in, pits and mills out, the loads landed so far); loads land whole
	var b0 := bodies
	var haul_in := _haul(dt, inp, _job("haul"), cap, out, b0, (rot_mass - want) / dt)

	# 4. the store over the step: rot return and landings in, the pits and mills out, netted before
	# the cap clips (MECHANICS §4.1), so a long step near the cap books no phantom overflow. What
	# overflows is split between rot and haul by their shares of the inflow.
	# The pits have first call on the bodies and the mills take only the surplus (E2b-2). While the
	# store holds bodies both draw their full want; the step's shortfall falls on the time it stands
	# empty, tau = shortfall / (want − rot return) per second, when only the rot return comes in
	# (a landing refills it at once), and that goes to the pits first. So the split doesn't depend
	# on dt: one 10 s step splits as twenty 0.5 s steps do. Pits-first on the whole step's supply,
	# min(want_pit, B0 + in), did (pre_vei's bone 44.8% off at 15 s over 1 h, a load landing inside
	# a long step fed the pits only). The total taken is min(want, B0 + in) as before, so the
	# store's path and _haul's projection of it are unchanged.
	var inflow := rot_mass + haul_in
	var taken := minf(want, b0 + inflow)
	var end := b0 + inflow - taken
	var burned := want_pit
	var shortfall := want - taken
	if shortfall > 0.0:
		var r_in := rot_mass / dt  # mass/s while the store stands empty
		var w := want / dt
		var tau := minf(dt, shortfall / (w - r_in)) if w > r_in else dt
		var wp := want_pit / dt
		burned = wp * (dt - tau) + minf(wp, r_in) * tau
	burned = clampf(burned, 0.0, taken)
	var milled := taken - burned
	# only what comes in is clipped: an excess the store held before the step (a demolished house
	# dropped the cap) persists and the pits draw it down; inflow fills to the cap, or to wherever
	# the pits have drawn the stock this step, whichever is higher
	var over := maxf(0.0, end - maxf(cap, b0 - taken))
	bodies = maxf(0.0, end - over)
	var rot_over := minf(over, over * rot_mass / inflow) if inflow > 0.0 else 0.0
	var haul_over := maxf(0.0, over - rot_over)
	out["rot_overflow"] = rot_over
	out["haul_overflow"] = haul_over
	var rot_in := rot_mass - rot_over
	haul_in -= haul_over
	out["burned"] = burned
	out["milled"] = milled
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
			_mark_rooms()
			events.append({"type": "building_done", "lot_id": lot_id, "building_id": b["building_id"], "level": int(b["level"])})

	# 7. the living (§4.3): exact first-order update, then the housing cap
	var lcap := living_cap()
	var mig := float(inp.get("held_villages", 0)) * _migrant_rate
	for lot_id in _lots:
		var b: Dictionary = buildings.get(lot_id, {})
		if not b.is_empty() and _works(b):
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

	# 9. upkeep: resume after the hold when the stocks cover it (on their paths over the step), idle
	# the cheapest when short
	var paid := _upkeep(dt, events, gold_in, bone_in)

	# 10. rates for the views; the staffing and the states at the step's end (views and saves read
	# them; the next step's _restaff() finds them current and has nothing to redo)
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


## Where `workforce()` settles at a constant inflow `r` workers/s (lifetime `life`, idle rot multiplier
## `m`, `slots` staffable, `idle_cap`), with exactly its regimes. Returns {kept, muster}: the settled
## workforce, and the workers/s mustered to WAR there (0 unless the idle pool is pinned at its cap).
static func workforce_steady(r: float, life: float, m: float, slots: float, idle_cap: float) -> Dictionary:
	var s := maxf(0.0, slots)
	var c := maxf(0.0, idle_cap)
	var L := maxf(EPS, life)
	var rl := r * L
	if rl <= s:
		return {"kept": rl, "muster": 0.0}
	if m > 0.0:
		var ss_b := s + (rl - s) / m
		if ss_b <= s + c:
			return {"kept": ss_b, "muster": 0.0}
		return {"kept": s + c, "muster": maxf(0.0, r - (s + m * c) / L)}
	return {"kept": s + c, "muster": maxf(0.0, r - s / L)}


## workforce_steady() at the live inputs: this substep's inflow, the lifetime now, the staffable slots.
func steady_kept(relish_home: bool) -> Dictionary:
	return workforce_steady(float(rates["workers"]["in"]), lifetime_s(relish_home), _idle_rot,
			float(staffing.get("slots", 0.0)), _idle_cap)


## The convoy. A leg takes distance / (job.haul.speed · stables) seconds. It leaves when haulers
## are staffed, the store is under the cap and there is a target (auto: the fort with the most
## dead above job.haul.auto_min_dead). The crew is fixed at departure. At arrival it picks up
## carry · crew (× flip.haul_mult at a held fort), clamped to the fort's dead left in the snapshot
## and to the store's headroom; on the way back the load lands (step() nets it into the store).
## The store's level at a leg's moment is projected from `b0`: `net` mass/s (rot return less what
## the pits and mills want) and each landed load, held within [0, cap]. Pickups read the forts'
## dead as the snapshot had them, so a long step's later legs see no corpses made inside it.
## Returns the mass landed.
func _haul(dt: float, inp: Dictionary, crew_now: float, cap: float, out: Dictionary, b0: float, net: float) -> float:
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
	var hi := maxf(cap, b0)  # an over-cap store keeps its excess (step 4); it is the projection's ceiling
	var lvl := clampf(b0, 0.0, hi)  # the projected store at `at_lvl` seconds into the step
	var at_lvl := 0.0
	for _i in MAX_LEGS:
		if left <= 0.0:
			break
		if convoys.is_empty():
			if crew_now <= EPS or clampf(lvl + net * (dt - left - at_lvl), 0.0, hi) >= cap - EPS or speed <= 0.0:
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
			var level := clampf(lvl + net * (dt - left - at_lvl), 0.0, hi)
			var load := minf(minf(avail, _carry * float(c["crew"]) * mult), maxf(0.0, cap - level))
			taken[c["fort"]] = float(taken.get(c["fort"], 0.0)) + load
			c["load"] = load
			c["phase"] = "back"
			c["t"] = 0.0
		else:
			delivered += float(c["load"])
			lvl = minf(hi, clampf(lvl + net * (dt - left - at_lvl), 0.0, hi) + float(c["load"]))
			at_lvl = dt - left
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


## Upkeep (§4.3), on the stocks' paths over the step: each starts at what it held before this
## step's income (`gold_in`, `bone_in`), which comes in at a constant rate, and pays the working
## buildings' upkeep as it goes. An unpaid building whose hold is over resumes at the first moment
## its stocks cover the paying upkeep plus its own for max(unpaid_hold_s, dt). The moments are
## solved on those paths; buildings resume in their order (ties in lot order), each raising the
## upkeep the next must cover, and a resumed building pays from its moment on. Then, while a stock
## can't cover the step's upkeep, the cheapest paying building by its upkeep in that stock (ties in
## lot order) goes unpaid, except a building that earns that stock (stalls for gold, mills for
## bone): idling it could never pay the bill back. What is still owed is paid down to 0; there is
## no debt. E2b T4.C: resumes used to be checked at the step's end, in lot order, on the stocks
## before the step's upkeep: a 10 s step from pre_vei resumed its raising pit (lot-02) at 7 804 s,
## ahead of the house (lot-05) whose lower threshold the gold crossed first, and about 45 s before
## the gold, net of upkeep, reached either (7 847 s, 7 853 s).
func _upkeep(dt: float, events: Array, gold_in: float, bone_in: float) -> Dictionary:
	var due_g := 0.0
	var due_b := 0.0
	var secs := {}  # lot_id -> the seconds of this step its upkeep is paid for
	var cands: Array = []  # [lot_id, seconds into the step its hold is over], in lot order
	for lot_id in _lots:
		var b: Dictionary = buildings.get(lot_id, {})
		if b.is_empty():
			continue
		if _works(b):
			due_g += float(_defs[b["building_id"]]["upkeep_gold"])
			due_b += float(_defs[b["building_id"]]["upkeep_bone"])
			secs[lot_id] = dt
		elif b["state"] == "unpaid":
			var left := float(b["unpaid_s"])
			b["unpaid_s"] = maxf(0.0, left - dt)
			if float(b["unpaid_s"]) <= 0.0:
				cands.append([lot_id, maxf(0.0, left)])
	var span := maxf(_hold_s, dt)
	var at := 0.0  # how far into the step the paths are solved
	var g := gold - gold_in  # the stocks at `at`
	var bn := bone - bone_in
	var in_g := gold_in / dt
	var in_b := bone_in / dt
	while not cands.is_empty():
		var pick := -1
		var when := INF
		for k in cands.size():
			var d: Dictionary = _defs[buildings[cands[k][0]]["building_id"]]
			var tg := _covers(g, in_g - due_g, (due_g + float(d["upkeep_gold"])) * span, at)
			var tb := _covers(bn, in_b - due_b, (due_b + float(d["upkeep_bone"])) * span, at)
			var lo := maxf(maxf(at, float(cands[k][1])), maxf(float(tg[0]), float(tb[0])))
			if lo <= minf(dt, minf(float(tg[1]), float(tb[1]))) + EPS and lo < when:
				when = lo
				pick = k
		if pick < 0:
			break
		var lot_id: String = cands[pick][0]
		var bd: Dictionary = buildings[lot_id]
		var ug := float(_defs[bd["building_id"]]["upkeep_gold"])
		var ub := float(_defs[bd["building_id"]]["upkeep_bone"])
		g += (in_g - due_g) * (when - at)
		bn += (in_b - due_b) * (when - at)
		at = when
		bd["state"] = "active"
		_mark_rooms()
		due_g += ug
		due_b += ub
		secs[lot_id] = maxf(0.0, dt - when)
		cands.remove_at(pick)
		events.append({"type": "building_unpaid", "lot_id": lot_id, "building_id": bd["building_id"], "unpaid": false})
	var owe_g := 0.0
	var owe_b := 0.0
	for lot_id in secs:
		owe_g += float(_defs[buildings[lot_id]["building_id"]]["upkeep_gold"]) * float(secs[lot_id])
		owe_b += float(_defs[buildings[lot_id]["building_id"]]["upkeep_bone"]) * float(secs[lot_id])
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
		_mark_rooms()
		var paid_s := float(secs.get(pick, dt))
		owe_g -= float(_defs[pb["building_id"]]["upkeep_gold"]) * paid_s
		owe_b -= float(_defs[pb["building_id"]]["upkeep_bone"]) * paid_s
		secs.erase(pick)
		events.append({"type": "building_unpaid", "lot_id": pick, "building_id": pb["building_id"], "unpaid": true})
	var pg := clampf(owe_g, 0.0, gold)
	var pbn := clampf(owe_b, 0.0, bone)
	gold -= pg
	bone -= pbn
	return {"gold": pg, "bone": pbn}


## When a stock at `v` (`at` seconds into the step), changing at `rate`, is at least `need`:
## [from, until] in seconds into the step, either end ±INF; from > until when never.
static func _covers(v: float, rate: float, need: float, at: float) -> Array:
	if v >= need:
		return [-INF, at + (v - need) / -rate] if rate < 0.0 else [-INF, INF]
	if rate > 0.0:
		return [at + (need - v) / rate, INF]
	return [INF, -INF]


# --------------------------------------------------------- the job ladder ----
## The order the workers fill the jobs in: `order` after stances (MECHANICS §4.5). Stances are E3;
## until then it is `order` itself. `_staff()`, view_town's `ladder_effective` and the staffing
## projection (STATE-API §5.16) all read it, so they apply the stances the same way.
func effective_ladder(order: Array) -> Array:
	return order.duplicate()


## The staffing allocation (MECHANICS §4.5), pure on its inputs: staff_rooms() then staff_fill().
## `_staff()` and the projection (project_staffing) both run it; nothing else fills rooms.
static func staff_allocate(order: Array, lots: Array, buildings_in: Dictionary, defs: Dictionary, build_slots: int,
		w: float, vats: Array) -> Dictionary:
	return staff_fill(staff_rooms(order, lots, buildings_in, defs, build_slots, vats), w)


## The allocation's rooms, which don't depend on the workforce. Jobs in `order` (the effective
## ladder; an id outside JOBS or one already seen is skipped), lots in `lots` order: each lot offers
## a job its slots (_slots_b), cut to what its staff cap leaves after the jobs above it.
## `buildings_in` is lot_id -> {building_id, state, level, staff_cap}, `defs` the building defs,
## `build_slots` job.build.slots. `vats` (staffed, per vat slot) opens the tend slots: one per vat,
## open only while that vat is staffed (MECHANICS §7, tend_open). Returns {rooms: [[lot_id, job,
## room]] in fill order, jobs: {job: slots} in order, slots: Σ room (the staffable workers),
## tend: {lot_id: open tend slots}}.
static func staff_rooms(order: Array, lots: Array, buildings_in: Dictionary, defs: Dictionary, build_slots: int,
		vats: Array) -> Dictionary:
	var tend := tend_open(lots, buildings_in, defs, vats)
	var used := {}
	var rooms: Array = []  # [lot_id, job, room] in fill order
	var jobs := {}
	var total := 0.0
	for job in order:
		if not JOBS.has(job) or jobs.has(job):
			continue
		var n := 0
		for lot_id in lots:
			var b: Dictionary = buildings_in.get(lot_id, {})
			if b.is_empty():
				continue
			var k := _slots_b(b, job, defs, build_slots)
			if job == "tend":
				k = mini(k, int(tend.get(lot_id, 0)))
			if k <= 0:
				continue
			n += k
			var room := float(k)
			if int(b["staff_cap"]) >= 0:
				room = clampf(float(b["staff_cap"]) - float(used.get(lot_id, 0.0)), 0.0, room)
			used[lot_id] = float(used.get(lot_id, 0.0)) + room
			rooms.append([lot_id, job, room])
			total += room
		jobs[job] = n
	return {"rooms": rooms, "jobs": jobs, "slots": total, "tend": tend}


## The vat rule (MECHANICS §7; the run's manager, E2b-2): a Chapel of Vats offers one tend slot per
## vat (jobs.tend × level = vat_slots × level), open only while that vat is staffed. Vats are numbered
## as view_backups numbers them: every built building's `vat_slots` at its level (unpaid and
## mid-upgrade too, so an unpaid Chapel keeps its numbers), in lot order, then by vat within the lot.
## Returns {lot_id: staffed vats there}, which caps the lot's tend slots (an unpaid Chapel, or a first
## build, still offers none).
static func tend_open(lots: Array, buildings_in: Dictionary, defs: Dictionary, vats: Array) -> Dictionary:
	var out := {}
	var at := 0
	for lot_id in lots:
		var b: Dictionary = buildings_in.get(lot_id, {})
		if b.is_empty():
			continue
		var n := int(_eff_b(b, "vat_slots", defs))
		if n <= 0:
			continue
		var on := 0
		for i in range(at, at + n):
			if i < vats.size() and bool(vats[i]):
				on += 1
		out[lot_id] = on
		at += n
	return out


## Fills staff_rooms()' rooms top-down with `w` workers. Returns {staffing, by_lot}: what `staffing`
## ({jobs: {job: {slots, staffed}} in order, lots: {lot_id: staffed}, idle, slots}) and `_by_lot`
## (lot_id -> {job: staffed}) hold.
static func staff_fill(r: Dictionary, w: float) -> Dictionary:
	var jobs := {}
	var slots: Dictionary = r["jobs"]
	for job in slots:
		jobs[job] = {"slots": slots[job], "staffed": 0.0}
	var left := maxf(0.0, w)
	var lots := {}
	var by_lot := {}
	for e in r["rooms"]:
		var take := minf(float(e[2]), left)
		left -= take
		jobs[e[1]]["staffed"] = float(jobs[e[1]]["staffed"]) + take
		lots[e[0]] = float(lots.get(e[0], 0.0)) + take
		if not by_lot.has(e[0]):
			by_lot[e[0]] = {}
		by_lot[e[0]][e[1]] = float(by_lot[e[0]].get(e[1], 0.0)) + take
	return {"staffing": {"jobs": jobs, "lots": lots, "idle": left, "slots": r["slots"]}, "by_lot": by_lot}


## Workers fill job slots top-down in ladder order (effective_ladder), buildings in lot order, each lot up to its
## staff cap. A working building offers jobs × level slots (one mid-upgrade too, at its old level); a constructing lot offers
## job.build.slots build slots; unpaid buildings offer none. Rebuilds `staffing` and `_by_lot` only.
func _staff() -> void:
	if _rooms_dirty:
		_rooms = staff_rooms(effective_ladder(ladder), _lots, buildings, _defs, _build_slots, _vats)
		_rooms_dirty = false
		_n_rooms += 1
	var a := staff_fill(_rooms, workers)
	_n_fills += 1
	staffing = a["staffing"]
	_by_lot = a["by_lot"]
	_staffed_w = NAN


## The rooms changed (or may have): the next _staff() rebuilds them and the next _restaff() refills.
func _mark_rooms() -> void:
	_rooms_dirty = true
	_staffed_w = NAN
	_sums_w.clear()
	_sums_b.clear()


## The staffing `_staff()` would give now with the job order replaced by `order` (stances applied by
## effective_ladder, as `_staff()` applies them) on today's workforce, buildings and staff caps. Pure:
## changes nothing. `vat_override` ({slot: bool}, int slots) stands in for the staffed vats at the
## slots it lists, opening and closing their tend slots as cmd_staff_vat would; a slot that isn't a
## whole number from 0 to the vats there are is ignored. Returns staff_fill()'s {staffing, by_lot}.
func project_staffing(order: Array, vat_override: Dictionary) -> Dictionary:
	var o: Array = []
	for j in order:
		o.append(str(j))
	var v: Array = _vats.duplicate()
	var n := int(_sum_built("vat_slots"))
	for k in vat_override:
		if not (k is int or (k is float and is_finite(k) and float(k) == floorf(k))):
			continue
		var slot := int(k)
		if slot < 0 or slot >= n:
			continue
		while v.size() <= slot:
			v.append(false)
		v[slot] = bool(vat_override[k])
	return staff_allocate(effective_ladder(o), _lots, buildings, _defs, _build_slots, workers, v)


## `_staff()`, then marks working buildings that have job slots `active` (someone staffed) or
## `idle` (nobody). A load never calls this, so a saved state comes back as it was saved. With the
## rooms clean and the workforce the last call filled, the staffing and the states are already what
## this would give (a fill is pure in the two), so it returns at once: a step's first call after the
## last step's closing one (E2b T4.P; the step used to fill twice).
func _restaff() -> void:
	if not _rooms_dirty and workers == _staffed_w:
		return
	_staff()
	var lots: Dictionary = staffing["lots"]
	for lot_id in buildings:
		var b: Dictionary = buildings[lot_id]
		if not WORKING.has(b["state"]):
			continue
		b["state"] = "active" if not bool(_defs[b["building_id"]]["has_jobs"]) or float(lots.get(lot_id, 0.0)) > 0.0 else "idle"
	_staffed_w = workers


## A building at work: built and paid, or built and mid-upgrade (it keeps working at its old level
## until the upgrade completes; a first build, level 0, never works).
func _works(b: Dictionary) -> bool:
	return _works_b(b)


static func _works_b(b: Dictionary) -> bool:
	return WORKING.has(b["state"]) or (b["state"] == "constructing" and int(b["level"]) >= 1)


func _slots(b: Dictionary, job: String) -> int:
	return _slots_b(b, job, _defs, _build_slots)


## The slots a building offers a job (MECHANICS §4.2): its def's jobs × level while it works,
## job.build.slots build slots while it is constructing, none while unpaid.
static func _slots_b(b: Dictionary, job: String, defs: Dictionary, build_slots: int) -> int:
	if job == "build":
		return build_slots if b["state"] == "constructing" else 0
	if not _works_b(b):
		return 0
	return int(defs[b["building_id"]]["jobs"].get(job, 0)) * int(b["level"])


func _job(job: String) -> float:
	return float(staffing.get("jobs", {}).get(job, {}).get("staffed", 0.0))


# ------------------------------------------------------- effects and caps ----
## A building's numeric effect at its level: a number is per level (× level); an Array is a
## per-level table (index level − 1). 0 before the first build completes.
func _eff(b: Dictionary, key: String) -> float:
	return _eff_b(b, key, _defs)


static func _eff_b(b: Dictionary, key: String, defs: Dictionary) -> float:
	var lv := int(b["level"])
	var v: Variant = defs[b["building_id"]]["effects"].get(key, null)
	if v == null or lv <= 0:
		return 0.0
	if v is Array:
		return float(v[mini(lv, v.size()) - 1]) if not v.is_empty() else 0.0
	return float(v) * lv


func _sum_working(key: String) -> float:
	if _sums_w.has(key):
		return _sums_w[key]
	var s := 0.0
	for lot_id in _lots:
		var b: Dictionary = buildings.get(lot_id, {})
		if not b.is_empty() and _works(b):
			s += _eff(b, key)
	_sums_w[key] = s
	return s


## Capacity effects count for every built level, unpaid or mid-upgrade too, so an unpaid spell
## never destroys stock.
func _sum_built(key: String) -> float:
	if _sums_b.has(key):
		return _sums_b[key]
	var s := 0.0
	for lot_id in _lots:
		if buildings.has(lot_id):
			s += _eff(buildings[lot_id], key)
	_sums_b[key] = s
	return s


func body_cap() -> float:
	return _body_cap + _sum_built("body_cap")


## Working pits now: the mint's `pits` before a step has run (step() reports the same count).
func pits() -> int:
	return int(_sum_working("pits"))


## The job slots a lot offers now (build slots while constructing, none while unpaid, a Chapel's tend
## slots only for its staffed vats); 0 when empty.
func lot_slots(lot_id: String) -> int:
	var b: Dictionary = buildings.get(lot_id, {})
	var n := 0
	if not b.is_empty():
		var tend := tend_open(_lots, buildings, _defs, _vats)
		for job in JOBS:
			var k := _slots(b, job)
			n += mini(k, int(tend.get(lot_id, 0))) if job == "tend" else k
	return n


## view_town's `output` for a lot (STATE-API §5.9): per second, at the current staffing. A pit gives
## {mint: mint_per_pit · pits, burn: pit.burn_per_s · pits · its staffed share}; stalls {gold}, their
## share of the town's sales; millers {bone}; haulers {bodies}, their share of `haul_rate` (the
## trip-averaged haul, which GameState passes in with the realm's P_per_pit); smiths {forge} (work/s,
## while a forge level is left); an inn {living} (its migrants). {} during a first build or while unpaid.
func lot_output(lot_id: String, mint_per_pit: float, haul_rate: float) -> Dictionary:
	var b: Dictionary = buildings.get(lot_id, {})
	var out := {}
	if b.is_empty() or not _works(b):
		return out
	var st: Dictionary = _by_lot.get(lot_id, {})
	var p := _eff(b, "pits")
	if p > 0.0:
		var slots := _slots(b, "pit")
		var frac := 1.0 if slots <= 0 else float(st.get("pit", 0.0)) / slots
		out["mint"] = mint_per_pit * p
		out["burn"] = _burn * p * frac
	var stall := float(st.get("stall", 0.0))
	if stall > 0.0:
		out["gold"] = minf(_job("stall") * _stall_rate, living * _shop_rate) * _price * (stall / _job("stall"))
	var mill := float(st.get("mill", 0.0))
	if mill > 0.0:
		out["bone"] = mill * _mill_mass * _mill_rate
	var haul_n := float(st.get("haul", 0.0))
	if haul_n > 0.0:
		out["bodies"] = haul_rate * (haul_n / _job("haul"))
	var smiths := float(st.get("forge", 0.0))
	if smiths > 0.0 and int(forge["level"]) < _forge_work.size():
		out["forge"] = smiths * _forge_rate
	var attract := _eff(b, "attract")
	if attract > 0.0:
		out["living"] = attract
	return out


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
		if b.is_empty() or not _works(b):
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
## JSON-safe, floats canonical (SaveIO.canon), buildings in lot order. `pending` holds the events
## a command queued that no step() has returned yet (a building_started before a save).
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
		"pending": _pending.duplicate(true),
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
	_vats = []  # GameState sets the loaded vats right after (set_vats(..., true))
	_mark_rooms()
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
			"trip_s": float(c.get("trip_s", MIN_TRIP_S)), "load": float(c.get("load", 0.0)), "crew": float(c.get("crew", 0.0))})
	var fg := _d(d.get("forge"))
	forge = {"level": int(fg.get("level", 0)), "progress": float(fg.get("progress", 0.0))}
	rates = _zero_rates()
	var rd := _d(d.get("rates"))
	for k in rates:
		if rd.has(k):
			rates[k] = rd[k].duplicate(true) if rd[k] is Dictionary else float(rd[k])
	_pending = []
	for e in d.get("pending", []):
		if e is Dictionary:
			var ev: Dictionary = e.duplicate(true)
			if ev.has("level"):
				ev["level"] = int(ev["level"])
			_pending.append(ev)
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
