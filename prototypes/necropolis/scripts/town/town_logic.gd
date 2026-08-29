class_name TownLogic
extends RefCounted
## Pure logic for a Covington visit — UI-free so the test suite can drive it
## headlessly. The scene is PRESENTATIONAL: the real economy ticks in the Game
## autoload while this is open. We therefore work on a frozen local view of the
## seed's resources, only ever subtracting our own purchases, and report those
## purchases back as spend DELTAS (never balances).
##
## Invariants enforced here (and tested):
##   - spend never exceeds the seed's res + spend_grace (per resource)
##   - idle_undead never goes negative
##   - total assigned + idle stays constant (nothing raises or kills here)
##   - crafting a simulacrum requires the station

const TASKS := ["trade", "forge", "jobs", "gather", "slab"]

var cfg := {}
var town := {}
var assignments := {}
var idle_undead := 0
var funds := {"gold": 0.0, "materials": 0.0}   # seed res minus our spends
var spent := {"gold": 0.0, "materials": 0.0}   # deltas reported in result()
var deploys: Array = []                        # new simulacra made this visit
var gather_target := ""                        # "" = auto (richest corpse fort)
var fort_ids: Array = []
var seed_quality := 1.2
var seed_forge_level := 0


func setup(seed_data: Dictionary, cfg_: Dictionary) -> void:
	cfg = cfg_
	town = (seed_data.get("town", {}) as Dictionary).duplicate(true)
	for k in ["slabs", "vats", "sim_stations", "forge_level", "trade_level"]:
		if not town.has(k):
			town[k] = 0
	var seed_assign: Dictionary = seed_data.get("assignments", {})
	assignments = {}
	for t in TASKS:
		assignments[t] = maxi(0, int(seed_assign.get(t, 0)))
	idle_undead = maxi(0, int(seed_data.get("idle_undead", 0)))
	var res: Dictionary = seed_data.get("res", {})
	funds = {"gold": float(res.get("gold", 0.0)), "materials": float(res.get("materials", 0.0))}
	spent = {"gold": 0.0, "materials": 0.0}
	deploys = []
	gather_target = str((seed_data.get("gather", {}) as Dictionary).get("target", ""))
	fort_ids = (seed_data.get("fort_ids", []) as Array).duplicate()
	seed_quality = float(seed_data.get("quality", 1.2))
	seed_forge_level = int(town.get("forge_level", 0))


# ------------------------------------------------------------------ money ----
func grace() -> float:
	return float(cfg.get("spend_grace", 0.0))


func can_afford(gold_c: float, mat_c: float) -> bool:
	# Small grace over the seed snapshot: the live totals only ever grow while
	# the scene is open, so being a hair over the stale snapshot is fine.
	return float(funds["gold"]) + grace() >= gold_c - 0.0001 \
		and float(funds["materials"]) + grace() >= mat_c - 0.0001


func _pay(gold_c: float, mat_c: float) -> void:
	funds["gold"] = float(funds["gold"]) - gold_c
	funds["materials"] = float(funds["materials"]) - mat_c
	spent["gold"] = float(spent["gold"]) + gold_c
	spent["materials"] = float(spent["materials"]) + mat_c


func display_funds(key: String) -> float:
	return maxf(0.0, float(funds.get(key, 0.0)))


func _cost(key: String, def: float) -> float:
	return float((cfg.get("costs", {}) as Dictionary).get(key, def))


# ------------------------------------------------------------------ builds ---
func slab_cost() -> float:
	return _cost("slab_gold_per_current", 25.0) * maxf(1.0, float(int(town["slabs"])))


func buy_slab() -> bool:
	var c := slab_cost()
	if not can_afford(c, 0.0):
		return false
	_pay(c, 0.0)
	town["slabs"] = int(town["slabs"]) + 1
	return true


func vat_cost() -> Dictionary:
	return {"gold": _cost("vat_gold", 30.0), "materials": _cost("vat_materials", 8.0)}


func buy_vat() -> bool:
	var c := vat_cost()
	if not can_afford(float(c["gold"]), float(c["materials"])):
		return false
	_pay(float(c["gold"]), float(c["materials"]))
	town["vats"] = int(town["vats"]) + 1
	return true


func station_built() -> bool:
	return int(town["sim_stations"]) >= 1


func station_cost() -> Dictionary:
	return {"gold": _cost("sim_station_gold", 80.0), "materials": _cost("sim_station_materials", 40.0)}


func buy_station() -> bool:
	if station_built():
		return false
	var c := station_cost()
	if not can_afford(float(c["gold"]), float(c["materials"])):
		return false
	_pay(float(c["gold"]), float(c["materials"]))
	town["sim_stations"] = 1
	return true


func forge_cost() -> float:
	return _cost("forge_materials_per_next_level", 12.0) * float(int(town["forge_level"]) + 1)


func buy_forge() -> bool:
	var c := forge_cost()
	if not can_afford(0.0, c):
		return false
	_pay(0.0, c)
	town["forge_level"] = int(town["forge_level"]) + 1
	return true


func sim_cost() -> float:
	return _cost("simulacrum_materials", 30.0)


func can_craft_sim() -> bool:
	return station_built() and can_afford(0.0, sim_cost())


func craft_simulacrum(fort_id: String) -> bool:
	if fort_id == "" or not station_built():
		return false
	if not can_afford(0.0, sim_cost()):
		return false
	_pay(0.0, sim_cost())
	var s: Dictionary = cfg.get("simulacrum", {})
	deploys.append({
		"fort_id": fort_id,
		"charges": float(s.get("charges", 300.0)),
		"rate": float(s.get("rate", 3.0)),
	})
	return true


# ------------------------------------------------------------------ workers --
func assign(task: String) -> bool:
	if not assignments.has(task) or idle_undead <= 0:
		return false
	idle_undead -= 1
	assignments[task] = int(assignments[task]) + 1
	return true


func unassign(task: String) -> bool:
	if int(assignments.get(task, 0)) <= 0:
		return false
	assignments[task] = int(assignments[task]) - 1
	idle_undead += 1
	return true


func total_undead() -> int:
	var n := idle_undead
	for t in TASKS:
		n += int(assignments[t])
	return n


# ------------------------------------------------------------------ readouts -
func quality() -> float:
	# Seed quality already includes the seed's forge levels; only add the delta
	# bought during this visit.
	var bonus := float(cfg.get("forge_quality_bonus", 0.25))
	return seed_quality + bonus * float(int(town["forge_level"]) - seed_forge_level)


# ------------------------------------------------------------------ result ---
func result() -> Dictionary:
	return {
		"town": town.duplicate(true),
		"assignments": assignments.duplicate(true),
		"idle_undead": maxi(0, idle_undead),
		"spend": {"gold": float(spent["gold"]), "materials": float(spent["materials"])},
		"gather_target": gather_target,
		"deploy_simulacra": deploys.duplicate(true),
		"teleport_to": "",
	}
