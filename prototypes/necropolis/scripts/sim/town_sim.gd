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
##   pits: int              working pits (the mint's P_per_pit term reads pit_weight(): them weighted by their
##                          foremen, E3-3)
##   feed: float 0..1       burned / wanted (the mint's feed bonus; wanted counts pit_weight's pits)
##   muster_mass: float     mass to add to WAR
##   pickups: Array         [{fort_id, mass}] corpses taken from forts this substep, each total ≤
##                          that fort's `dead` (GameState takes them off the forts)
##   relics_spent: int      relics the forge used (GameState takes them off the stock)
##   rot_overflow: float    rot return lost to the body cap (mass; a ledger sink)
##   haul_overflow: float   haul deliveries lost to the body cap (mass; a ledger sink)
##   rot_loss: float        rotted mass that never returns as bodies, (1 − body_return) (a ledger sink)
##   burned, milled: float  bodies the pits burned and the mills milled (mass; ledger sinks)
##   gold_overflow, bone_overflow: float  income the gold and bone caps clipped (IDLE §6; not mass:
##                          GameState tallies them in the ledger's `stores`)
##   vat_hands: Array       each vat's tend hands this step × its Chapel's foreman multiplier (vat_work, E3-3):
##                          what GameState grows the vats on
##   events: Array          {type, ...} without `t` (GameState stamps it): building_started,
##                          building_done, building_unpaid
##   rates: Dictionary      this substep's flows per second (a copy of `rates`)

const JOBS := ["haul", "mill", "stall", "forge", "pit", "tend", "build"]
## The capacity effects (caps and slots): they count for every built level, unpaid or mid-upgrade too
## (_sum_built), so an unpaid spell never lowers a cap or destroys stock (R1, the run's manager). Every
## other effect is a working one and needs the building working (_sum_working, _lists). `craft_slots` is
## read by cmd_craft's gate from E3-4 (needs_building under 1).
const CAPACITY_EFFECTS := ["body_cap", "gold_cap", "bone_cap", "relic_cap", "essence_cap", "living_cap", "vat_slots",
	"stance_slots", "craft_slots"]
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
	"economy.gold.cap", "economy.bone.cap",
	"economy.morale.base", "economy.morale.ease_per_s", "economy.morale.dread_ratio", "economy.morale.dread_k",
	"economy.morale.leave_below", "economy.morale.shock_s",
	"economy.job.default_ladder", "economy.job.haul.speed", "economy.job.haul.carry", "economy.job.haul.auto_min_dead",
	"economy.job.mill.mass_per_s", "economy.job.mill.rate", "economy.job.forge.rate",
	"economy.job.build.rate", "economy.job.build.slots",
	"economy.stall.rate", "economy.market.shop_rate", "economy.market.price", "economy.pit.burn_per_s",
	"economy.upkeep.unpaid_hold_s", "economy.upkeep.shed_order", "economy.forge.level_work", "economy.forge.level_relics",
	"economy.town.migrant_rate", "economy.town.leave_rate",
	"realm.relish.home_rot_mult", "realm.flip.haul_mult", "town.lots", "buildings",
	# E3-1: Thrift's reach (MECHANICS §4.5; thrift_pick)
	"economy.stance.thrift_upkeep", "economy.stance.thrift_spares_from",
	# E3-3: the foreman (MECHANICS §4.2; _fm, E4 placeholders)
	"economy.foreman.mult", "economy.foreman.speed_k", "economy.foreman.presence_k",
]

# ---- tunables, read once in setup() from REQUIRED (no numbers here) ----
var _lots: Array[String] = []  # town.json lot ids, in order
## building id -> {jobs: {job: int}, effects: {}, upkeep_gold, upkeep_bone, build_work, max_level, has_jobs,
## shed_rank: its `shed_class`'s place in economy.json upkeep.shed_order (_upkeep sheds the lowest first)}
var _defs := {}
var _start := {}  # economy.json opening: workers, bodies, gold, bone, living (floats), buildings {lot_id: id}
var _default_ladder: Array[String] = []
var _mass := 0.0
var _lifetime := 0.0
var _body_return := 0.0
var _idle_rot := 0.0
var _idle_cap := 0.0
var _home_rot := 0.0
var _body_cap := 0.0
var _gold_cap := 0.0
var _bone_cap := 0.0
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
var _thrift_over := 0.0  # economy.json stance.thrift_upkeep: Thrift idles only buildings whose gold upkeep is above it
## economy.json stance.thrift_spares_from's place in upkeep.shed_order: Thrift idles only the classes ranked before
## it (the decorations, the passive and the job buildings; never the WAR chain)
var _thrift_rank := 0
var _f_mult := 0.0  # economy.json foreman.mult: a working foreman's multiplier before its speed
var _f_speed_k := 0.0  # foreman.speed_k: the multiplier per point of the foreman's speed
var _f_presence_k := 0.0  # foreman.presence_k: the morale per point of a working foreman's presence

# ---- state (to_dict / from_dict) ----
var workers := 0.0  # workers
var bodies := 0.0  # mass, ≤ body_cap()
var gold := 0.0  # ≤ gold_cap(), except an excess kept from before the cap dropped
var bone := 0.0  # ≤ bone_cap(), likewise
var living := 0.0  # people, ≤ living_cap()
var morale := 0.0  # 0..1
var shock := 0.0  # the decaying death shock, subtracted from the morale target
## lot_id -> {building_id, level, state, progress, staff_cap, unpaid_s, build_level}. `state` is
## constructing | active | idle (working, but nobody staffed) | unpaid | thrift (idled by the Thrift stance,
## E3-1: like unpaid it offers no slots, gives no output and pays no upkeep, and keeps its capacity effects and
## its tier count; it never resumes by itself, only when Thrift stops acting: thrift_resume; view_town shows it
## "idle"). `level` is 0 during a first build; `build_level` is the level a construction completes to.
## `progress` is 0..1 while constructing, else 1. `staff_cap` -1 = none. `unpaid_s` is the unpaid hold left.
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

# ---- the stances' effects (E3-1, MECHANICS §4.5): GameState sets them from the stances acting (never saved; a
# load re-applies them from the stance state) ----
## The jobs the acting ladder stances lift to the top, in economy.json stance.priority order (effective_ladder).
## Set through set_top_jobs, which marks the rooms.
var top_jobs: Array = []
## Muster acts: the idle cap reads 0 (idle_cap), so every idle worker musters to WAR at once.
var muster_all := false

# ---- the foremen (E3-3, MECHANICS §4.2): GameState sets them from the big undead placed `town:<lot_id>`
# (set_foremen; never saved: a load derives them from the save's big undead). State, not a step input, so clone()
# carries them and every projection (stance_flows, lot_output, the build benefit's and the forecasts' clones, the
# stances' and the queue's readings of the last step's rates) sees them ----
## lot_id -> {speed: float, presence: float}, the foreman's stats. A foreman works (_fm_works) only at a building with
## job slots that is working and staffed; there it multiplies the building's job output by foreman.mult + speed ·
## foreman.speed_k (_fm) and lifts the morale target by foreman.presence_k · presence (morale_factors).
var foremen := {}

# ---- derived (not saved; rebuilt by _staff()) ----
## {jobs: {job: {slots: int, staffed: float}} in ladder order, lots: {lot_id: staffed},
## idle: float, slots: float (staffable after staff caps)}
var staffing := {}
## Why the staffed mills milled less than their hands want in the last step (never saved; "" before a
## first step, after a new game and after a load): "" when they got all they want or none are staffed;
## "pits_first" when the pits took bodies and the supply fell short of both; "no_bodies" when the
## pits took none either (nothing in the store or landing, or no staffed pit). STATE-API §5.9.
var mill_starved := ""
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
## What step() reads of the buildings, cached like the sums (E2b-2 T3.3b2, catch-up's budget): it reads only
## their states and levels, so _mark_rooms() clears it and _lists() rebuilds it at its next read. {pits:
## [[lot_id, pits, pit slots]] the working pits in lot order; attract: the working buildings' `attract` in lot
## order; amen: the morale amenities, building id -> Σ `morale` (morale_factors' order); work: [[lot_id, upkeep
## gold, upkeep bone]] the working buildings in lot order; unpaid: the unpaid lots in lot order; building: the
## lots under construction in lot order; upkeep: lot_id -> [upkeep gold, upkeep bone] for every building; thrift:
## the lots the Thrift stance idles, in lot order; bill_g: the gold upkeep of the working buildings and of those}.
var _lists_c := {}
## The vats staffed, per vat slot (GameState's vats_staffed, which it saves; set_vats), trailing
## falses dropped. A vat slot's tend room is open only while its vat is staffed (MECHANICS §7).
var _vats: Array[bool] = []
var _n_rooms := 0  # staff_rooms() builds, for tests (not saved)
## +1 whenever the rooms may have changed (_mark_rooms: a building's arrival or removal, state, level or
## staff cap, the ladder, the vats). The build benefit's cache keys on it (StateViews.projections). Not saved.
var structure_rev := 0
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
	_gold_cap = _num(cfgs, "economy.gold.cap")
	_bone_cap = _num(cfgs, "economy.bone.cap")
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
	_thrift_over = _num(cfgs, "economy.stance.thrift_upkeep")
	_thrift_rank = _arr(_at(cfgs, "economy.upkeep.shed_order")).find(str(_at(cfgs, "economy.stance.thrift_spares_from")))
	if _thrift_rank < 0:
		push_error("TownSim: economy.stance.thrift_spares_from is not a class in economy.upkeep.shed_order")
		_thrift_rank = 0  # Thrift idles nothing rather than everything
	_f_mult = _num(cfgs, "economy.foreman.mult")
	_f_speed_k = _num(cfgs, "economy.foreman.speed_k")
	_f_presence_k = _num(cfgs, "economy.foreman.presence_k")
	_default_ladder = []
	for j in _arr(_at(cfgs, "economy.job.default_ladder")):
		_default_ladder.append(str(j))
	_lots = []
	for l in _arr(_at(cfgs, "town.lots")):
		_lots.append(str(_d(l).get("id", "")))
	_defs = {}
	var shed_order := _arr(_at(cfgs, "economy.upkeep.shed_order"))
	var bcfg := _d(_at(cfgs, "buildings"))
	for id in bcfg:
		var b := _d(bcfg[id])
		var up := _d(b.get("upkeep"))
		var jobs := _d(b.get("jobs"))
		var has_jobs := false
		for j in jobs:
			has_jobs = has_jobs or int(jobs[j]) > 0
		var rank := shed_order.find(str(b.get("shed_class", "")))
		if rank < 0:
			push_error("TownSim: buildings.json %s's shed_class %s is not in economy.upkeep.shed_order" % [id, str(b.get("shed_class", ""))])
			rank = 0  # shed with the first class: never protected by a missing key
		_defs[str(id)] = {
			"jobs": jobs, "effects": _d(b.get("effects")),
			"upkeep_gold": float(up.get("gold", 0.0)), "upkeep_bone": float(up.get("bone", 0.0)),
			"build_work": float(b.get("build_work", 0.0)), "max_level": int(b.get("max_level", 0)),
			"has_jobs": has_jobs, "shed_rank": rank,
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
	mill_starved = ""
	workers = float(_start["workers"])
	bodies = float(_start["bodies"])
	gold = float(_start["gold"])
	bone = float(_start["bone"])
	living = float(_start["living"])
	shock = 0.0
	buildings = {}
	_vats = []
	top_jobs = []
	muster_all = false
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


## A copy for a hypothetical (view_catalog's `projected`, view_town's `upgrade_projected`; STATE-API
## §5.10): setup()'s tunables shared (no step changes them; `_lots` too, unless the caller swaps in its own
## list), the state deep-copied, nothing pending, the caches dirty. Stepping it never touches this one.
func clone() -> TownSim:
	var c := TownSim.new()
	c._lots = _lots
	c._defs = _defs
	c._start = _start
	c._default_ladder = _default_ladder
	c._mass = _mass
	c._lifetime = _lifetime
	c._body_return = _body_return
	c._idle_rot = _idle_rot
	c._idle_cap = _idle_cap
	c._home_rot = _home_rot
	c._body_cap = _body_cap
	c._gold_cap = _gold_cap
	c._bone_cap = _bone_cap
	c._living_cap = _living_cap
	c._haul_speed = _haul_speed
	c._carry = _carry
	c._auto_min = _auto_min
	c._haul_mult = _haul_mult
	c._mill_mass = _mill_mass
	c._mill_rate = _mill_rate
	c._forge_rate = _forge_rate
	c._build_rate = _build_rate
	c._build_slots = _build_slots
	c._stall_rate = _stall_rate
	c._shop_rate = _shop_rate
	c._price = _price
	c._burn = _burn
	c._hold_s = _hold_s
	c._forge_work = _forge_work
	c._forge_relics = _forge_relics
	c._migrant_rate = _migrant_rate
	c._leave_rate = _leave_rate
	c._morale_base = _morale_base
	c._ease = _ease
	c._dread_ratio = _dread_ratio
	c._dread_k = _dread_k
	c._leave_below = _leave_below
	c._shock_s = _shock_s
	c._thrift_over = _thrift_over
	c._thrift_rank = _thrift_rank
	c._f_mult = _f_mult
	c._f_speed_k = _f_speed_k
	c._f_presence_k = _f_presence_k
	c.foremen = foremen.duplicate(true)
	c.top_jobs = top_jobs.duplicate()
	c.muster_all = muster_all
	c.workers = workers
	c.bodies = bodies
	c.gold = gold
	c.bone = bone
	c.living = living
	c.morale = morale
	c.shock = shock
	c.buildings = buildings.duplicate(true)
	c.ladder = ladder.duplicate()
	c.haul = haul.duplicate(true)
	c.forge = forge.duplicate()
	c.rates = rates.duplicate(true)
	c._vats = _vats.duplicate()
	# the staffing as it stands (E3-3): a foreman's multiplier reads its building's hands (_fm_works), and a
	# projection reads pit_weight() before its first step's restaff refills it (StateViews._proj_step's mint)
	c.staffing = staffing.duplicate(true)
	c._by_lot = _by_lot.duplicate(true)
	c._mark_rooms()
	return c


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
		"rot_overflow": 0.0, "haul_overflow": 0.0, "rot_loss": 0.0, "burned": 0.0, "milled": 0.0,
		"gold_overflow": 0.0, "bone_overflow": 0.0, "vat_hands": [], "events": events}
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
	var wf := workforce(w0, r, dt, life, _idle_rot, used_slots, idle_cap())
	workers = wf["w"]
	var rotted: float = float(wf["rot"]) * _mass
	var rot_mass: float = rotted * _body_return
	out["rot_loss"] = rotted - rot_mass
	out["muster_mass"] = float(wf["muster"]) * _mass

	# 2. what the pits and the mills want this step (the pits have first call on the bodies, step 4). A Pit foreman
	# (E3-3) multiplies its pit's burn and its weight in the pits' `wanted` (pit_weight), so the pit draws bodies m
	# times as fast and the mint (GameState._mint, on pit_weight) raises m times its share: the raise follows the burn
	var pits := 0
	var pit_w := 0.0  # the working pits weighted by their foremen: float(pits) while none works
	var pit_can := 0.0  # mass/s the staffed pits can burn
	for e in _lists()["pits"]:  # [lot_id, pits, slots], the working pits in lot order
		var p: int = e[1]
		var slots: int = e[2]
		pits += p
		var m := _fm_lot(e[0])
		pit_w += p * m
		var frac := 1.0 if slots <= 0 else float(_by_lot.get(e[0], {}).get("pit", 0.0)) / slots
		pit_can += _burn * p * frac * m
	var want_pit := pit_can * dt
	var want_mill := _mill_mass * _job("mill") * dt
	var want := want_pit + want_mill

	# 3. haul (§4.2): the convoy, as many legs as the step holds. Its departures and pickups see the
	# store's projected level (rot in, pits and mills out, the loads landed so far); loads land whole
	var b0 := bodies
	var g0 := gold  # the gold and bone stores before the step (step 9's cap clip)
	var bn0 := bone
	# (the crew: the haulers × their Charnel House's foreman multiplier, _job_w: a foreman multiplies the carry per
	# hauler, and the fort's dead and the store's headroom still clamp the load after it)
	var haul_in := _haul(dt, inp, _job_w("haul"), cap, out, b0, (rot_mass - want) / dt)

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
	# the mill's reason (view_town.jobs[].starved): short of its want by more than float noise
	mill_starved = ""
	if want_mill > 0.0 and milled < want_mill * (1.0 - 1e-9):
		mill_starved = "pits_first" if burned > 0.0 else "no_bodies"
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
	var bone_in := milled * _mill_rate * _job_f("mill")  # a Bone Mill foreman multiplies the bone, not the bodies milled
	bone += bone_in
	var wanted := _burn * pit_w * dt
	out["pits"] = pits
	out["feed"] = clampf(burned / wanted, 0.0, 1.0) if wanted > 0.0 else 0.0

	# 4. stalls: gold = min(staffed · stall.rate, living · shop_rate) · price, × a Market foreman's multiplier after
	# that cap (E3-3; trade_rate stays the sales)
	var sales := minf(_job("stall") * _stall_rate, living * _shop_rate)
	var gold_in := sales * _price * _job_f("stall") * dt
	gold += gold_in

	# 5. the forge: work toward the next q level; a level completes only with its relics
	var forge_work := 0.0
	var relics_left := int(inp.get("relics_available", 0))
	var spent := 0
	if int(forge["level"]) < _forge_work.size():
		forge_work = _forge_rate * _job_w("forge") * dt  # a Forge foreman's smiths work m times as fast (E3-3)
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
	for lot_id in _lists()["building"]:  # the lots under construction, in lot order (a finish marks the rooms)
		var b: Dictionary = buildings[lot_id]
		var w := build_speed(lot_id) * dt
		build_work += w
		var need := construction_work(b["building_id"], int(b["build_level"]))
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
	for a in _lists()["attract"]:  # every working building's attract, in lot order
		mig += a
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
	# the gold and bone caps (IDLE §6): only what came in is clipped (store_overflow), exactly for
	# constant rates inside the step: one 10 s step ends with the stock and the overflow of twenty 0.5 s
	# steps, from under the cap or over it. A store already over its cap (a demolished cap building, an
	# old save) keeps its excess, earns nothing until it is back under, and upkeep (and spending) draw it
	# down. Gold's floor of 0 and upkeep are unchanged.
	var g_over := store_overflow(g0, gold, gold_in, float(paid["gold"]), gold_cap())
	var b_over := store_overflow(bn0, bone, bone_in, float(paid["bone"]), bone_cap())
	gold -= g_over
	bone -= b_over
	out["gold_overflow"] = g_over
	out["bone_overflow"] = b_over

	# 10. rates for the views; the staffing and the states at the step's end (views and saves read
	# them; the next step's _restaff() finds them current and has nothing to redo). The vats' hands are
	# this step's tend staffing, as the forge's work is its own (GameState grows the vats on them, E3-2)
	var tend := _job("tend")
	out["vat_hands"] = vat_work()  # each vat's tend hands × its Chapel's foreman multiplier: what it grows on (E3-3)
	_restaff()
	rates = {
		"workers": {"in": r, "out": (float(wf["rot"]) + float(wf["muster"])) / dt, "rot": float(wf["rot"]) / dt,
			"muster": float(wf["muster"]) / dt, "steady": r * life, "lifetime_s": life, "slots": used_slots},
		"bodies": {"in": (rot_in + haul_in) / dt, "out": (burned + milled) / dt, "rot": rot_in / dt, "haul": haul_in / dt,
			"pit": burned / dt, "mill": milled / dt, "overflow": (float(out["rot_overflow"]) + float(out["haul_overflow"])) / dt},
		"gold": {"in": (gold_in - g_over) / dt, "out": float(paid["gold"]) / dt, "overflow": g_over / dt,
			"trade": gold_in / dt},
		"bone": {"in": (bone_in - b_over) / dt, "out": float(paid["bone"]) / dt, "overflow": b_over / dt,
			"mill": bone_in / dt},
		"living": {"in": living_in / dt, "out": living_out / dt},
		"trade_rate": sales, "haul_trip": float(rates.get("haul_trip", 0.0)) if _haul_trip < 0.0 else _haul_trip,
		"forge": forge_work / dt, "build": build_work / dt, "tend": tend, "feed": float(out["feed"]),
	}
	out["rates"] = rates.duplicate(true)
	return out


## What a capped store (gold, bone) loses to its cap over a step (IDLE §6, MECHANICS §4.3): `s0` before
## the step, `end` after its `income` and the upkeep `out` it paid. Only what came in is clipped, exactly
## for constant rates inside the step. While the store is above its cap every coin in overflows and the
## upkeep draws it down; when the upkeep outruns the income it reaches the cap (s0 − cap) / out of the
## way through the step and runs on uncapped below it, so the overflow is income × min(1, that share).
## Otherwise it is what ends above max(cap, s0 − out), the body store's rule (step 4). Returns the
## overflow, ≥ 0 and never more than the income.
static func store_overflow(s0: float, end: float, income: float, out: float, cap: float) -> float:
	if s0 > cap and out > income:
		return income * minf(1.0, (s0 - cap) / out)
	return maxf(0.0, end - maxf(cap, s0 - out))


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


## workforce_steady() at the live inputs: this substep's inflow, the lifetime now, the staffable slots, the idle
## cap now (0 while Muster acts).
func steady_kept(relish_home: bool) -> Dictionary:
	return workforce_steady(float(rates["workers"]["in"]), lifetime_s(relish_home), _idle_rot,
			float(staffing.get("slots", 0.0)), idle_cap())


## The idle cap the workforce is pinned at (MECHANICS §4.1): economy.json worker.idle_cap, or 0 while the Muster
## stance acts (E3-1: every idle worker musters to WAR at once).
func idle_cap() -> float:
	return 0.0 if muster_all else _idle_cap


## The convoy. A leg takes distance / (job.haul.speed · stables) seconds. It leaves when haulers
## are staffed, the store is under the cap and there is a target (auto: the fort with the most
## dead above job.haul.auto_min_dead). The crew is fixed at departure. At arrival it picks up
## carry · crew (× flip.haul_mult at a held fort), clamped to the fort's dead and to the store's
## headroom; on the way back the load lands (step() nets it into the store).
## The store's level at a leg's moment is projected from `b0`: `net` mass/s (rot return less what
## the pits and mills want) and each landed load, held within [0, cap].
## The forts' dead are read at each leg's own moment s into the step (E2b-2 T3.3a), for the pick and
## the pickup: RealmSim.dead_at(dead, dead_rate, s) from the snapshot's `dead` and `dead_rate` (a
## snapshot without `dead_rate` reads 0: its dead as they stand), less what this step's legs took
## there. A pickup is also held to the snapshot's dead less those legs: GameState takes it off the
## fort before the realm step, which owns the corpses made inside it, so a long step's later legs
## can't take those (MECHANICS §4.2: a lag of up to a step where corpses grow inside it). Before, both
## read the snapshot: at 10 s from midgame_2flips the convoy found the corpses Relish's raises at
## Greywall would have taken inside the step (at 9b5fc99, 115.7 mass over 12 h against 0.001 at 0.5 s).
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
			var fid := _haul_pick(forts, target, taken, dt - left)
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
			var d0 := maxf(0.0, float(f.get("dead", 0.0)))
			var now := RealmSim.dead_at(d0, float(f.get("dead_rate", 0.0)), dt - left)
			var avail := maxf(0.0, minf(now, d0) - float(taken.get(c["fort"], 0.0)))
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


## The convoy's target at a departure `at` seconds into the step: the set one, or (auto) the fort with
## the most dead then (RealmSim.dead_at, less what this step's legs took there) above
## job.haul.auto_min_dead; ties go to the first in order.
func _haul_pick(forts: Array, target: String, taken: Dictionary, at: float) -> String:
	if target != "auto":
		for f in forts:
			if str(f.get("id", "")) == target:
				return target
		return ""
	var best := ""
	var most := _auto_min
	for f in forts:
		var id := str(f.get("id", ""))
		var dead := RealmSim.dead_at(float(f.get("dead", 0.0)), float(f.get("dead_rate", 0.0)), at) - float(taken.get(id, 0.0))
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
## can't cover the step's upkeep, one paying building goes unpaid at a time: the first class in
## economy.json upkeep.shed_order (its buildings.json `shed_class`: decorations, then the passive
## no-job buildings, then the job buildings, then the WAR chain last, the mill, the charnel houses and
## the raising pits), and within it the cheapest by its upkeep in that stock (ties in lot order),
## except a building that earns that stock (stalls for gold, mills for bone): idling it could never
## pay the bill back. What is still owed is paid down to 0; there is no debt. R1 (the E2b-2 vision
## review): cheapest-first alone idled the raising pits (0.03 gold/s) before the Statue, the
## Reliquary and the Walls, so pre_vei's gold floor took its WAR from 41.9 to 0.95 mass/s, then a
## 16.4 plateau. E2b T4.C: resumes used to be checked at the step's end, in lot order, on the stocks
## before the step's upkeep: a 10 s step from pre_vei resumed its raising pit (lot-02) at 7 804 s,
## ahead of the house (lot-05) whose lower threshold the gold crossed first, and about 45 s before
## the gold, net of upkeep, reached either (7 847 s, 7 853 s).
func _upkeep(dt: float, events: Array, gold_in: float, bone_in: float) -> Dictionary:
	var due_g := 0.0
	var due_b := 0.0
	var secs := {}  # lot_id -> the seconds of this step its upkeep is paid for
	var cands: Array = []  # [lot_id, seconds into the step its hold is over], in lot order
	var lists := _lists()
	var upk: Dictionary = lists["upkeep"]
	for e in lists["work"]:  # [lot_id, upkeep gold, upkeep bone], the working buildings in lot order
		due_g += float(e[1])
		due_b += float(e[2])
		secs[e[0]] = dt
	for lot_id in lists["unpaid"]:
		var b: Dictionary = buildings[lot_id]
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
		var u: Array = upk[lot_id]
		owe_g += float(u[0]) * float(secs[lot_id])
		owe_b += float(u[1]) * float(secs[lot_id])
	while gold < owe_g - EPS or bone < owe_b - EPS:
		var short := "gold" if gold < owe_g - EPS else "bone"
		var key := "upkeep_" + short
		var earner := "stall" if short == "gold" else "mill"
		var pick := ""
		var first := 1 << 30  # the shed class's rank (upkeep.shed_order), then
		var cheapest := INF  # the cheapest within it, then lot order (strict <)
		for lot_id in _lots:
			var b: Dictionary = buildings.get(lot_id, {})
			if b.is_empty() or not WORKING.has(b["state"]):
				continue
			var d: Dictionary = _defs[b["building_id"]]
			var u := float(d[key])
			if u <= 0.0 or int(d["jobs"].get(earner, 0)) > 0:
				continue
			var rank := int(d["shed_rank"])
			if rank < first or (rank == first and u < cheapest):
				first = rank
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
## The order the workers fill the jobs in: `order` after stances (MECHANICS §4.5): the jobs the acting ladder
## stances lift (`top_jobs`, in stance.priority order) on top, then the rest of `order` in its order. With no
## stance acting it is `order` itself. `_staff()`, view_town's `ladder_effective` and the staffing
## projection (STATE-API §5.16) all read it, so they apply the stances the same way.
## The room cache (`_mark_rooms`) is keyed on `ladder`, not on this, while `_staff()` fills from the
## effective ladder. So the stances change `top_jobs` only through set_top_jobs, which calls `_mark_rooms()`, or
## the cache would serve the old rooms.
func effective_ladder(order: Array) -> Array:
	return lifted(order, top_jobs)


## `order` with `top` (jobs) lifted to the top in `top`'s order, the rest after in `order`'s; a job of `top` that
## isn't in `order` is skipped. `order` itself (a copy) when `top` is empty.
static func lifted(order: Array, top: Array) -> Array:
	if top.is_empty():
		return order.duplicate()
	var out: Array = []
	for j in top:
		if order.has(j) and not out.has(j):
			out.append(j)
	for j in order:
		if not out.has(j):
			out.append(j)
	return out


## The jobs the acting ladder stances lift (GameState._apply_stances, E3-1). A change marks the rooms, since they
## are keyed on `ladder` (effective_ladder above), then restaffs; `on_load` refills without marking the
## buildings' states (a load restores them as saved, as set_vats does). Nothing happens when they are the same.
func set_top_jobs(jobs: Array, on_load := false) -> void:
	if jobs == top_jobs:
		return
	top_jobs = jobs.duplicate()
	_mark_rooms()
	if on_load:
		_staff()
	else:
		_restaff()


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


## The hands on each vat now (E3-2, MECHANICS §7), by vat slot (tend_open's numbering, view_backups'): tend
## workers are staffed per Chapel, not per vat, so a Chapel's tend staffing fills its staffed vats in slot order,
## one hand each, the lowest slot first, as the ladder fills its rooms top-down. With s hands on a Chapel's k
## staffed vats, the first floor(s) have 1, the next s − floor(s), the rest 0; an unstaffed vat has 0, and so does
## every vat of a Chapel that offers no tend slot (unpaid, idled by Thrift). [] while no vat is staffed. step()
## reports it for the step's own staffing (`vat_hands`), before its end restaff.
func vat_hands() -> Array:
	if _vats.is_empty():
		return []
	var out: Array = []
	var at := 0
	for lot_id in _lots:
		var b: Dictionary = buildings.get(lot_id, {})
		if b.is_empty():
			continue
		var n := int(_eff(b, "vat_slots"))
		if n <= 0:
			continue
		var left := float(_by_lot.get(lot_id, {}).get("tend", 0.0))
		for i in range(at, at + n):
			var h := 0.0
			if i < _vats.size() and _vats[i]:
				h = clampf(left, 0.0, 1.0)
				left -= h
			out.append(h)
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
	structure_rev += 1
	_rooms_dirty = true
	_staffed_w = NAN
	_sums_w.clear()
	_sums_b.clear()
	_lists_c = {}


## The cached lists step() reads (_lists_c), rebuilt from the buildings when the rooms were last marked.
func _lists() -> Dictionary:
	if not _lists_c.is_empty():
		return _lists_c
	var pit_lots: Array = []
	var attract := PackedFloat64Array()
	var amen := {}
	var work: Array = []
	var unpaid: Array = []
	var thrift: Array = []
	var building: Array = []
	var upkeep := {}
	var bill := 0.0
	for lot_id in _lots:
		var b: Dictionary = buildings.get(lot_id, {})
		if b.is_empty():
			continue
		var d: Dictionary = _defs[b["building_id"]]
		var ug := float(d["upkeep_gold"])
		var ub := float(d["upkeep_bone"])
		upkeep[lot_id] = [ug, ub]
		if b["state"] == "constructing":
			building.append(lot_id)
		if _works(b):
			var pn := int(_eff(b, "pits"))
			if pn > 0:
				pit_lots.append([lot_id, pn, _slots(b, "pit")])
			attract.append(_eff(b, "attract"))
			var v := _eff(b, "morale")
			if v != 0.0:
				amen[b["building_id"]] = float(amen.get(b["building_id"], 0.0)) + v
			work.append([lot_id, ug, ub])
			bill += ug
		elif b["state"] == "unpaid":
			unpaid.append(lot_id)
		elif b["state"] == "thrift":
			thrift.append(lot_id)
			bill += ug
	# thrift: the lots Thrift idles, in lot order; bill_g: the gold upkeep of the working buildings and of those (what
	# the town owes with Thrift's idled buildings paying: Thrift's condition, gold_bill)
	_lists_c = {"pits": pit_lots, "attract": attract, "amen": amen, "work": work, "unpaid": unpaid, "building": building,
		"upkeep": upkeep, "thrift": thrift, "bill_g": bill}
	return _lists_c


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


# ------------------------------------------------------- the stances' effects ----
## Thrift's income (MECHANICS §4.5, E3-1): the stalls' sales at today's staffing and living, × market.price, per
## second (step 4's formula, before the gold cap's clip). Read from the state, not the last step's rates, so it
## holds after a new game or a load with no step run yet.
func trade_income() -> float:
	return minf(_job("stall") * _stall_rate, living * _shop_rate) * _price * _job_f("stall")  # × a Market foreman's m (E3-3)


## Thrift's upkeep (E3-1): the gold upkeep per second of the working buildings and of the ones Thrift idles, what
## the town would owe if Thrift let them go. Unpaid buildings owe nothing.
func gold_bill() -> float:
	return float(_lists()["bill_g"])


## The lots Thrift idles when it starts acting (MECHANICS §4.5, the run's manager's ruling E3-1): none unless the
## income (trade_income) is under the upkeep (gold_bill). Then the eligible working buildings, one at a time, until
## the income covers the upkeep still paid or none is left: a building whose gold upkeep is above
## economy.json stance.thrift_upkeep, whose shed_class ranks before stance.thrift_spares_from in upkeep.shed_order
## (the decorations, the passive and the job buildings: never the WAR chain, at any level) and that earns no store
## (no stall or mill jobs: never the Market). In shed order (the decorations first), the dearest first within a
## class, ties in lot order. A building mid-upgrade isn't working-idle (constructing) and isn't picked. The
## income is today's: a job building idled frees hands the stalls may take, which isn't counted.
func thrift_pick() -> Array:
	var income := trade_income()
	var owed := gold_bill()
	if income >= owed:
		return []
	var cands: Array = []  # [shed rank, upkeep gold, lot index, lot_id]
	for i in _lots.size():
		var b: Dictionary = buildings.get(_lots[i], {})
		if b.is_empty() or not WORKING.has(b["state"]):
			continue
		var d: Dictionary = _defs[b["building_id"]]
		var u := float(d["upkeep_gold"])
		if u <= _thrift_over or int(d["shed_rank"]) >= _thrift_rank:
			continue
		if int(d["jobs"].get("stall", 0)) > 0 or int(d["jobs"].get("mill", 0)) > 0:
			continue
		cands.append([int(d["shed_rank"]), u, i, _lots[i]])
	cands.sort_custom(func(x: Array, y: Array) -> bool:
		if x[0] != y[0]:
			return x[0] < y[0]
		if x[1] != y[1]:
			return x[1] > y[1]
		return x[2] < y[2])
	var out: Array = []
	for c in cands:
		if income >= owed:
			break
		out.append(c[3])
		owed -= float(c[1])
	return out


## Thrift idles `lots` (thrift_pick's): each working one takes state "thrift" (no slots, no output, no upkeep;
## its capacity effects and tier count stay), then the rooms are marked and restaffed. Returns the lots idled.
func thrift_idle(lots: Array) -> Array:
	var out: Array = []
	for lot_id in lots:
		var b: Dictionary = buildings.get(lot_id, {})
		if not b.is_empty() and WORKING.has(b["state"]):
			b["state"] = "thrift"
			out.append(lot_id)
	if not out.is_empty():
		_mark_rooms()
		_restaff()
	return out


## Thrift stops acting: every building it idled goes back to work (state "active", then the restaff marks it
## active or idle) and pays its upkeep from this step on. Returns the lots resumed, in lot order ([] at once when
## none is idled).
func thrift_resume() -> Array:
	var back: Array = (_lists()["thrift"] as Array).duplicate()
	if back.is_empty():
		return back
	for lot_id in back:
		buildings[lot_id]["state"] = "active"
	_mark_rooms()
	_restaff()
	return back


## The flows per second the town would run at today's state with the stances' effects replaced (E3-1:
## view_stances' `projected`, STATE-API §5.11): `top` the jobs lifted, `muster` the idle cap at 0, `thrift` the lots
## Thrift idles ({lot_id: true}; every other lot Thrift idles now back at work). The staffing is the one allocation
## (staff_allocate, as project_staffing runs it) on `ladder` with `top` lifted, today's workforce, buildings (with
## those states), staff caps and vats. The flows are what step() runs on that staffing, per second, now:
## - workers: the last step's inflow less the rot (staffed / lifetime, idle × worker.idle_rot_mult / lifetime) and
##   the muster (what the inflow brings beyond that rot while the workforce sits pinned at slots + idle cap; the
##   lump a lowered cap sends at once, the idle hands above it, is no rate);
## - bodies: the rot return plus the haul (the trip-averaged rate now, scaled by the haulers and by the convoy's
##   speed; 0 while no convoy is out) less the pits' burn and the mills' draw (each its want while the store holds
##   bodies; with the store empty the pits first from what comes in, the mills the rest);
## - gold: the stalls' sales × market.price less the gold upkeep; bone: the bodies milled × job.mill.rate less the
##   bone upkeep; living: the migrants (`held_villages`, the working inns' attract) less the departures (morale as
##   it stands);
## each net clipped to 0 at its store's cap while it would rise. Also the working pits and their feed (burned /
## wanted), for the next step's mint (GameState._mint). `home`: Relish home (the lifetime). Pure: changes nothing.
## The foremen (E3-3) count as in step(), on this staffing: a working foreman's building's gold, bone, crew (the
## haul's scale) and pit (its burn and its weight in `pits`, a float like pit_weight) × its multiplier.
## Returns {workers, bodies, gold, bone, living, muster (workers/s), haul (mass/s), pits, feed}.
func stance_flows(top: Array, muster: bool, thrift: Dictionary, home: bool, held_villages: int) -> Dictionary:
	var bin := buildings.duplicate()  # shallow: a lot whose state changes gets its own copy
	for lot_id in buildings:
		var b: Dictionary = buildings[lot_id]
		var want := "thrift" if thrift.has(lot_id) else ("active" if b["state"] == "thrift" else str(b["state"]))
		if want != b["state"]:
			var c := b.duplicate()
			c["state"] = want
			bin[lot_id] = c
	var a := staff_allocate(lifted(ladder, top), _lots, bin, _defs, _build_slots, workers, _vats)
	var st: Dictionary = a["staffing"]
	var by_lot: Dictionary = a["by_lot"]
	var jobs: Dictionary = st["jobs"]
	var bonus := 0.0
	var speed := 0.0
	var attract := 0.0
	var pits := 0.0  # the working pits weighted by their foremen, as pit_weight (E3-3)
	var want_pit := 0.0
	var up_g := 0.0
	var up_b := 0.0
	for lot_id in _lots:
		var b: Dictionary = bin.get(lot_id, {})
		if b.is_empty() or not _works_b(b):
			continue
		var d: Dictionary = _defs[b["building_id"]]
		up_g += float(d["upkeep_gold"])
		up_b += float(d["upkeep_bone"])
		bonus += _eff_b(b, "lifetime_bonus", _defs)
		speed += _eff_b(b, "haul_speed_mult", _defs)
		attract += _eff_b(b, "attract", _defs)
		var p := int(_eff_b(b, "pits", _defs))
		if p > 0:
			var m := _fm(lot_id, b, by_lot.get(lot_id, {})) if not foremen.is_empty() else 1.0  # its foreman (E3-3)
			pits += p * m
			var slots := _slots_b(b, "pit", _defs, _build_slots)
			want_pit += _burn * p * (1.0 if slots <= 0 else float(by_lot.get(lot_id, {}).get("pit", 0.0)) / slots) * m
	var life := _lifetime * (1.0 + bonus) / (_home_rot if home else 1.0)
	# the workforce, instantaneous: staffed and idle as the allocation leaves them, the idle above the cap mustered
	var staffed := maxf(0.0, workers - float(st["idle"]))
	var top_w := float(st["slots"]) + (0.0 if muster else _idle_cap)
	var w := minf(workers, top_w)
	var idle := maxf(0.0, w - staffed)
	var r := float(rates["workers"]["in"])
	var rot := (staffed + _idle_rot * idle) / maxf(EPS, life)
	var must := r - rot if w >= top_w - EPS and r > rot else 0.0
	# the body store
	var rot_in := rot * _mass * _body_return
	var crew0 := _job_w("haul")  # the crews as the carry counts them, foremen's multipliers in (E3-3)
	var haul_rate := 0.0
	if crew0 > 0.0 and not (haul["convoys"] as Array).is_empty():
		var crew := _job_w_of("haul", float(jobs.get("haul", {}).get("staffed", 0.0)), by_lot, bin)
		haul_rate = float(rates.get("haul_trip", 0.0)) * (crew / crew0) \
			* ((1.0 + speed) / (1.0 + _sum_working("haul_speed_mult")))
	var stalls := float(jobs.get("stall", {}).get("staffed", 0.0))
	var mills := float(jobs.get("mill", {}).get("staffed", 0.0))
	var want_mill := _mill_mass * mills
	var burned := want_pit
	var milled := want_mill
	if bodies <= EPS:
		var supply := rot_in + haul_rate
		burned = minf(want_pit, supply)
		milled = clampf(supply - burned, 0.0, want_mill)
	var out := {
		"workers": r - rot - must, "muster": must, "haul": haul_rate, "pits": pits,
		"feed": clampf(burned / (_burn * pits), 0.0, 1.0) if pits > 0.0 and _burn > 0.0 else 0.0,
		"bodies": rot_in + haul_rate - burned - milled,
		"gold": minf(stalls * _stall_rate, living * _shop_rate) * _price * _job_f_of("stall", stalls, by_lot, bin) - up_g,
		"bone": milled * _mill_rate * _job_f_of("mill", mills, by_lot, bin) - up_b,
		"living": float(held_villages) * _migrant_rate + attract - (living * _leave_rate if morale < _leave_below else 0.0),
	}
	for pair in [["bodies", bodies, body_cap()], ["gold", gold, gold_cap()], ["bone", bone, bone_cap()], ["living", living, living_cap()]]:
		if float(pair[1]) >= float(pair[2]) - EPS and float(out[pair[0]]) > 0.0:
			out[pair[0]] = 0.0
	return out


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


# ------------------------------------------------------------ the foremen ----
## GameState's foremen (E3-3): lot_id -> {speed, presence} for every big undead placed `town:<lot_id>`
## (GameState._sync_foremen). A change moves structure_rev, so the caches keyed on it (the build benefit's, the
## stances' projections) are computed again; the rooms don't depend on the foremen.
func set_foremen(map: Dictionary) -> void:
	if map == foremen:
		return
	foremen = map.duplicate(true)
	structure_rev += 1


## Whether a foreman on `lot_id` works (E3-3, the run's manager's ruling; MECHANICS §4.2): one stands there and the
## building `b` has job slots in buildings.json (a passive building has no work to lead), is working (TownSim's state
## active or idle: built, paid, not mid-upgrade, not idled by Thrift) and has hands staffed (`st`, its staffing by
## job; with them the restaff marks it `active`). Anywhere else a foreman is allowed and gives nothing.
func _fm_works(lot_id: String, b: Dictionary, st: Dictionary) -> bool:
	if not foremen.has(lot_id) or b.is_empty() or not WORKING.has(b["state"]) or not bool(_defs[b["building_id"]]["has_jobs"]):
		return false
	for j in st:
		if float(st[j]) > 0.0:
			return true
	return false


## The multiplier the building `b` on `lot_id` gets on its job output: foreman.mult + speed · foreman.speed_k while
## its foreman works (_fm_works, on the staffing `st`), else 1.0.
func _fm(lot_id: String, b: Dictionary, st: Dictionary) -> float:
	if not _fm_works(lot_id, b, st):
		return 1.0
	return _f_mult + float(foremen[lot_id]["speed"]) * _f_speed_k


## _fm for the building on `lot_id` now, on the staffing the last restaff left.
func _fm_lot(lot_id: String) -> float:
	if foremen.is_empty() or not foremen.has(lot_id):
		return 1.0
	return _fm(lot_id, buildings.get(lot_id, {}), _by_lot.get(lot_id, {}))


## `job`'s hands as its output counts them: `plain` (the job's hands, staffing's total) plus, for each lot whose
## foreman works, its hands there × (m − 1), on the staffing `by_lot` and the buildings `bin` (today's, or a
## projection's). So Σ hands × m over the lots, and `plain` exactly while no foreman works.
func _job_w_of(job: String, plain: float, by_lot: Dictionary, bin: Dictionary) -> float:
	if foremen.is_empty():
		return plain
	var w := plain
	for lot_id in foremen:
		var st: Dictionary = by_lot.get(lot_id, {})
		var h := float(st.get(job, 0.0))
		if h > 0.0:
			w += h * (_fm(lot_id, bin.get(lot_id, {}), st) - 1.0)
	return w


## _job_w_of's hands over the plain ones: the factor a job's output gets from its foremen (1.0 while none works there,
## or with no hands).
func _job_f_of(job: String, plain: float, by_lot: Dictionary, bin: Dictionary) -> float:
	if foremen.is_empty() or not (plain > 0.0):
		return 1.0
	return _job_w_of(job, plain, by_lot, bin) / plain


## _job_w_of today: the haulers' crew and the smiths' work (step 3, step 5).
func _job_w(job: String) -> float:
	return _job_w_of(job, _job(job), _by_lot, buildings)


## _job_f_of today: the stalls' gold and the mills' bone (step 4).
func _job_f(job: String) -> float:
	return _job_f_of(job, _job(job), _by_lot, buildings)


## view_town's `foreman_mult` (E3-3, STATE-API §5.9): the multiplier the building on `lot_id` gets from its foreman
## now; 1.0 with none, and where one gives nothing (_fm_works: a passive, unpaid, Thrift-idled, mid-upgrade or
## unstaffed building).
func foreman_mult(lot_id: String) -> float:
	return _fm_lot(lot_id)


## The working pits weighted by their foremen (E3-3): Σ pits × _fm over the working pits. The mint counts it
## (GameState._mint's pit term) and so do the pits' `wanted` (step 2), so a Pit foreman's pit raises m times its
## share while it burns m times as much: the raise follows the burn. float(pits()) while no foreman works.
func pit_weight() -> float:
	if foremen.is_empty():
		return float(pits())
	var n := 0.0
	for e in _lists()["pits"]:
		n += int(e[1]) * _fm_lot(e[0])
	return n


## vat_hands() as the vats grow on them (E3-3): each vat's tend hands × its Chapel's foreman multiplier, the factor
## GameState._grow_vats grows a vat by (step()'s `vat_hands`). vat_hands() itself while no foreman works.
func vat_work() -> Array:
	var hands := vat_hands()
	if foremen.is_empty() or hands.is_empty():
		return hands
	var at := 0
	for lot_id in _lots:
		var b: Dictionary = buildings.get(lot_id, {})
		if b.is_empty():
			continue
		var n := int(_eff(b, "vat_slots"))
		if n <= 0:
			continue
		var m := _fm_lot(lot_id)
		for i in range(at, mini(at + n, hands.size())):
			hands[i] = float(hands[i]) * m
		at += n
	return hands


## The working foremen's presence (E3-3): Σ foreman.presence_k · presence over the foremen that work (_fm_works),
## the morale target's `foreman` term. 0 while none works.
func _foreman_presence() -> float:
	if foremen.is_empty():
		return 0.0
	var s := 0.0
	for lot_id in foremen:
		if _fm_works(lot_id, buildings.get(lot_id, {}), _by_lot.get(lot_id, {})):
			s += _f_presence_k * float(foremen[lot_id]["presence"])
	return s


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


## economy.json gold.cap plus the buildings' `gold_cap` effects (the Market, per level; IDLE §6). A
## capacity effect: unpaid or mid-upgrade levels count.
func gold_cap() -> float:
	return _gold_cap + _sum_built("gold_cap")


## economy.json bone.cap plus the buildings' `bone_cap` effects (the Bone Mill, per level).
func bone_cap() -> float:
	return _bone_cap + _sum_built("bone_cap")


## The build work a construction of `building_id` heading to `level` needs in all (step 6: build_work ·
## target level); 0 for an unknown building. The queue's `work` (STATE-API §5.9) reads it.
func construction_work(building_id: String, level: int) -> float:
	return float(_defs.get(building_id, {}).get("build_work", 0.0)) * level


## A building's numeric effect `key` at `level` (_eff_b's rule: a number per level, an Array a per-level
## table; 0 at level 0). The queue's cap_level reads the cap effects through it.
func effect_at(building_id: String, key: String, level: int) -> float:
	if not _defs.has(building_id):
		return 0.0
	return _eff_b({"building_id": building_id, "level": level}, key, _defs)


## The work per second the builders staffed on a lot do now: job.build.rate × its build staffing as the
## last restaff left it (step 6 advances a construction by this × dt). 0 with no builders.
func build_speed(lot_id: String) -> float:
	return _build_rate * float(_by_lot.get(lot_id, {}).get("build", 0.0))


## A construction's work as view_town shows it (STATE-API §5.9, api-request #17): {left, eta_s}. `left` is
## the build work still to do, construction_work · (1 − progress), the numbers step 6 uses; `eta_s` is
## left / build_speed, −1.0 with no builders. {0.0, −1.0} on a lot that isn't constructing.
func construction_left(lot_id: String) -> Dictionary:
	var b: Dictionary = buildings.get(lot_id, {})
	if b.is_empty() or b["state"] != "constructing":
		return {"left": 0.0, "eta_s": -1.0}
	var left := maxf(0.0, construction_work(b["building_id"], int(b["build_level"])) * (1.0 - float(b["progress"])))
	var speed := build_speed(lot_id)
	return {"left": left, "eta_s": left / speed if speed > 0.0 else -1.0}


## Working pits now: the mint's `pits` before a step has run (step() reports the same count).
func pits() -> int:
	return int(_sum_working("pits"))


## The mill slots a lot's building offers (0 with no building).
func lot_mill_slots(lot_id: String) -> int:
	var b: Dictionary = buildings.get(lot_id, {})
	return _slots(b, "mill") if not b.is_empty() else 0


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
## A working foreman's building (E3-3) shows its outputs × its multiplier (_fm_lot); its haulers' share is of
## the crew as the carry counts it (_job_w).
func lot_output(lot_id: String, mint_per_pit: float, haul_rate: float) -> Dictionary:
	var b: Dictionary = buildings.get(lot_id, {})
	var out := {}
	if b.is_empty() or not _works(b):
		return out
	var st: Dictionary = _by_lot.get(lot_id, {})
	var m := _fm_lot(lot_id)  # its foreman's multiplier (E3-3): 1.0 with none working there
	var p := _eff(b, "pits")
	if p > 0.0:
		var slots := _slots(b, "pit")
		var frac := 1.0 if slots <= 0 else float(st.get("pit", 0.0)) / slots
		out["mint"] = mint_per_pit * p * m
		out["burn"] = _burn * p * frac * m
	var stall := float(st.get("stall", 0.0))
	if stall > 0.0:
		out["gold"] = minf(_job("stall") * _stall_rate, living * _shop_rate) * _price * (stall / _job("stall")) * m
	var mill := float(st.get("mill", 0.0))
	if mill > 0.0:
		out["bone"] = mill * _mill_mass * _mill_rate * m
	var haul_n := float(st.get("haul", 0.0))
	if haul_n > 0.0:
		out["bodies"] = haul_rate * (haul_n * m / _job_w("haul"))  # its share of the convoy's crew, as the carry counts it
	var smiths := float(st.get("forge", 0.0))
	if smiths > 0.0 and int(forge["level"]) < _forge_work.size():
		out["forge"] = smiths * _forge_rate * m
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
## `morale`, summed per building id in lot order), foreman (E3-3: the working foremen's presence ×
## foreman.presence_k, _foreman_presence), dread and shock (each of the last three only when non-zero).
func morale_factors() -> Array:
	var out: Array = [{"id": "base", "delta": _morale_base}]
	var amen: Dictionary = _lists()["amen"]
	for id in amen:
		out.append({"id": "amenity:" + str(id), "delta": amen[id]})
	var fp := _foreman_presence()  # E3-3: the working foremen's presence
	if fp != 0.0:
		out.append({"id": "foreman", "delta": fp})
	var dread := maxf(0.0, workers / maxf(living, 1.0) - _dread_ratio) * _dread_k
	if dread > 0.0:
		out.append({"id": "dread", "delta": -dread})
	if shock > 0.0:
		out.append({"id": "shock", "delta": -shock})
	return out


## Σ morale_factors()' deltas in their order, clamped to 0..1 (summed here without building the rows: the
## step reads it every step).
func morale_target() -> float:
	var s := 0.0
	s += _morale_base
	var amen: Dictionary = _lists()["amen"]
	for id in amen:
		s += float(amen[id])
	var fp := _foreman_presence()
	if fp != 0.0:
		s += fp
	var dread := maxf(0.0, workers / maxf(living, 1.0) - _dread_ratio) * _dread_k
	if dread > 0.0:
		s += -dread
	if shock > 0.0:
		s += -shock
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
	mill_starved = ""
	workers = float(d.get("workers", 0.0))
	bodies = float(d.get("bodies", 0.0))
	gold = float(d.get("gold", 0.0))
	bone = float(d.get("bone", 0.0))
	living = float(d.get("living", 0.0))
	morale = float(d.get("morale", _morale_base))
	shock = float(d.get("shock", 0.0))
	buildings = {}
	_vats = []  # GameState sets the loaded vats right after (set_vats(..., true))
	top_jobs = []  # and the stances' effects (GameState._apply_stances(true))
	muster_all = false
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
		"gold": {"in": 0.0, "out": 0.0},  # a step adds overflow and trade (mill for bone); read them with get()
		"bone": {"in": 0.0, "out": 0.0},
		"living": {"in": 0.0, "out": 0.0},
		"trade_rate": 0.0, "haul_trip": 0.0, "forge": 0.0, "build": 0.0, "tend": 0.0, "feed": 0.0,
	}


static func _xy(a: Variant) -> Vector2:
	if a is Array and a.size() >= 2:
		return Vector2(float(a[0]), float(a[1]))
	return Vector2.ZERO
