class_name LegacyEconomy
extends RefCounted
## E1 legacy economy. E2a retires this file.
## Everything of the pre-extraction town lives here: the stores (res, army, town, assignments,
## idle_undead, gather), the mint and slab burn, the town and gather ticks, the quality, the
## legacy seeds and town snapshot, the death scatter, the raid and boss army parity, the stock
## readers the views use, the targets of the debug grants and the save's `legacy` block.
## GameState forwards every public legacy name to the one instance it owns (`GameState.legacy`).
## It needs the RealmSim and the configs only; GameState hands them in.

const _I := TYPE_INT
const _F := TYPE_FLOAT
const _S := TYPE_STRING
## The save's `legacy` block (SaveIO's table embeds it).
const SAVE_SPEC := {
	"res": {"gold": _F, "materials": _F, "bodies": _F, "townsfolk": _F},
	"army": {"soldier": _I, "elite": _I},
	"town": {"slabs": _I, "vats": _I, "sim_stations": _I, "forge_level": _I, "trade_level": _I},
	"assignments": {"trade": _I, "forge": _I, "jobs": _I, "gather": _I, "slab": _I},
	"idle_undead": _I, "gather": {"target": _S, "phase": _S, "eta": _F, "load": _F},
}

var realm: RealmSim
var cfgs := {}  # the configs dict GameState holds, shared by reference

var army := {"soldier": 0, "elite": 0}
var res := {"gold": 30.0, "materials": 12.0, "bodies": 0.0, "townsfolk": 10.0}
var town := {"slabs": 1, "vats": 0, "sim_stations": 0, "forge_level": 0, "trade_level": 0}
var assignments := {"trade": 0, "forge": 0, "jobs": 0, "gather": 0, "slab": 0}
var idle_undead := 6  # unassigned workers in Covington
var gather := {"target": "", "phase": "idle", "eta": 0.0, "load": 0.0}


func _cfg() -> Dictionary:
	return cfgs.get("realm", {})


func _sec(file: String, section: String) -> Dictionary:
	var d: Variant = cfgs.get(file, {}).get(section, {})
	return d if d is Dictionary else {}


## The legacy stores back to the start state (the object is reset in place).
func reset() -> void:
	army = {"soldier": 0, "elite": 0}
	res = {"gold": 30.0, "materials": 12.0, "bodies": 0.0, "townsfolk": 10.0}
	town = {"slabs": 1, "vats": 0, "sim_stations": 0, "forge_level": 0, "trade_level": 0}
	assignments = {"trade": 0, "forge": 0, "jobs": 0, "gather": 0, "slab": 0}
	idle_undead = 6
	gather = {"target": "", "phase": "idle", "eta": 0.0, "load": 0.0}


func quality() -> float:
	var cfg: Dictionary = _cfg()
	var q: float = float(cfg.get("q", 1.2)) \
		+ float(cfg.get("q_per_forge", 0.25)) * town["forge_level"] \
		+ float(cfg.get("q_per_elite", 0.01)) * army["elite"]
	return clampf(q, 1.0, float(cfg.get("q_max", 4.0)))


# ------------------------------------------------------------------- tick ----
## Substep step 1: the Covington mint (P_base for the realm), burning slab bodies on the way.
func mint_step(dt: float) -> float:
	var cfg: Dictionary = _cfg()
	var mint: float = float(cfg.get("P_base", 2.0)) + float(cfg.get("P_per_slab", 2.0)) * town["slabs"]
	if res["bodies"] > 0.5 and assignments["slab"] > 0:
		var burn: float = minf(res["bodies"], float(cfg.get("slab_bodies_per_s", 0.12)) * town["slabs"] * dt)
		res["bodies"] -= burn
		mint *= float(cfg.get("slab_mint_bonus", 1.6))
	return mint


func tick_town(dt: float, green_towns: int) -> void:
	var cfg: Dictionary = _cfg()
	res["gold"] += (float(cfg.get("gold_per_townsfolk", 0.02)) * res["townsfolk"] \
		+ float(cfg.get("gold_per_job_worker", 0.06)) * assignments["jobs"] \
		+ float(cfg.get("gold_per_trade_worker", 0.03)) * assignments["trade"]) * dt
	res["materials"] += float(cfg.get("materials_per_trade_worker", 0.03)) * assignments["trade"] * dt
	res["townsfolk"] += float(cfg.get("migrant_rate_per_town", 0.012)) * green_towns * dt


func tick_gather(dt: float) -> void:
	var cfg: Dictionary = _cfg()
	if assignments["gather"] <= 0:
		gather["phase"] = "idle"
		return
	var speed: float = float(cfg.get("gather_speed", 140.0))
	match gather["phase"]:
		"idle":
			var best := ""
			var best_dead := 4.0
			for f in realm.forts:
				if f["dead"] > best_dead:
					best_dead = f["dead"]
					best = f["id"]
			if gather["target"] != "" and not realm.fort_by_id(gather["target"]).is_empty():
				best = gather["target"]
			if best != "":
				gather["phase"] = "out"
				gather["target"] = best
				gather["eta"] = realm.cov_pos.distance_to(realm.node_pos(best)) / speed
		"out":
			gather["eta"] -= dt
			if gather["eta"] <= 0.0:
				var f := realm.fort_by_id(gather["target"])
				if not f.is_empty():
					var carry: float = float(cfg.get("gather_carry", 14.0)) * assignments["gather"]
					gather["load"] = minf(f["dead"], carry)
					f["dead"] -= gather["load"]
				gather["phase"] = "back"
				gather["eta"] = realm.cov_pos.distance_to(realm.node_pos(gather["target"])) / speed
		"back":
			gather["eta"] -= dt
			if gather["eta"] <= 0.0:
				res["bodies"] += gather["load"]
				gather["load"] = 0.0
				gather["phase"] = "idle"


# ------------------------------------------------------- runs and seeds ----
## Clones ready at E1: the legacy vats.
func vats() -> int:
	return maxi(0, int(town["vats"]))


## The legacy death scatter (E1 rule, §8.3 step 10): a legacy vat gives a clone, otherwise the
## army scatters. True if it was a clone.
func death_scatter() -> bool:
	var clone: bool = town["vats"] > 0
	if clone:
		town["vats"] -= 1
	else:
		army["soldier"] = int(army["soldier"] * 0.6)
		army["elite"] = int(army["elite"] * 0.7)
	return clone


## Raid step 12, E1 parity: soldiers and elites into the legacy army.
func add_raised(raised: Array) -> void:
	for e in raised:
		var score := int(e["score"])
		if score >= 90:
			army["elite"] += int(e["count"])
		elif score >= 60:
			army["soldier"] += int(e["count"])


## A lost boss run scatters the army (E1 parity).
func boss_loss_scatter() -> void:
	army["soldier"] = int(army["soldier"] * 0.3)
	army["elite"] = int(army["elite"] * 0.4)


## A boss run spends `clones` of the legacy vats (they are the clones at E1).
func spend_clones(clones: int) -> void:
	town["vats"] = maxi(0, int(town["vats"]) - clones)


func raid_seed(fort_id: String) -> Dictionary:
	var f := realm.fort_by_id(fort_id)
	if f.is_empty():
		return {}
	return {
		"fort_id": fort_id, "name": f["name"], "tier": f["tier"], "cap": f["cap"],
		"living": f["living"], "undead": f["undead"], "dead": f["dead"],
		"boss": false, "quality": quality(),
	}


func boss_seed() -> Dictionary:
	return {
		"fort_id": "vei", "name": "Vei's Domain", "tier": 5, "cap": 800.0,
		"living": 500.0, "undead": 0.0, "dead": 60.0, "boss": true,
		"quality": quality(), "backlog": realm.vei["undead_queue"],
		"army": army.duplicate(true), "vei_capacity": float(_cfg().get("R_vei", 50.0)),
		"odds": realm.readout()["odds"],
	}


func town_snapshot(green_towns: int) -> Dictionary:
	return {
		"town": town.duplicate(true), "assignments": assignments.duplicate(true),
		"res": res.duplicate(true), "army": army.duplicate(true),
		"idle_undead": idle_undead, "quality": quality(),
		"green_towns": green_towns, "gather": gather.duplicate(true),
		"fort_ids": realm.forts.map(func(f): return f["id"]),
		"simulacra": realm.simulacra.duplicate(true),
	}


## Applies a town-logic result. Returns the simulacra it deployed (the caller counts them).
func apply_town_result(r: Dictionary) -> int:
	if r.has("town"):
		town = r["town"]
	if r.has("assignments"):
		assignments = r["assignments"]
	if r.has("idle_undead"):
		idle_undead = int(r["idle_undead"])
	var spend: Dictionary = r.get("spend", {})
	res["gold"] = maxf(0.0, res["gold"] - float(spend.get("gold", 0.0)))
	res["materials"] = maxf(0.0, res["materials"] - float(spend.get("materials", 0.0)))
	if r.has("gather_target"):
		gather["target"] = str(r["gather_target"])
	var built := 0
	for s in r.get("deploy_simulacra", []):
		realm.simulacra.append(s)
		built += 1
	return built


# ------------------------------------------------------ stocks for the views ----
## The legacy workforce: idle plus assigned.
func workers() -> float:
	var n := idle_undead
	for k in assignments:
		n += int(assignments[k])
	return float(n)


## The town's stocks at E1: the live legacy stores, the same ones view_hud shows (§5.1), so
## fixtures and debug grants show up in every view. `living_cap` is the economy.json
## `opening` constant.
func town_stock(key: String) -> float:
	match key:
		"gold":
			return float(res["gold"])
		"bone":
			return float(res["materials"])
		"bodies":
			return float(res["bodies"])
		"living":
			return float(res["townsfolk"])
		"workers":
			return workers()
	return float(_sec("economy", "opening").get(key, 0.0))


func haul_current() -> String:
	return gather["target"] if gather["phase"] != "idle" else ""


## The legacy convoy as a §5.9 convoy: out is Covington -> fort, back is fort -> Covington.
func convoys() -> Array:
	var phase: String = gather["phase"]
	var fid: String = gather["target"]
	if (phase != "out" and phase != "back") or realm.fort_by_id(fid).is_empty():
		return []
	var trip: float = realm.cov_pos.distance_to(realm.node_pos(fid)) / float(_cfg().get("gather_speed", 140.0))
	var prog := clampf(1.0 - float(gather["eta"]) / trip, 0.0, 1.0) if trip > 0.0 else 1.0
	if phase == "out":
		return [{"from": "covington", "to": fid, "phase": "out", "t": prog, "load": 0.0}]
	return [{"from": fid, "to": "covington", "phase": "back", "t": prog, "load": float(gather["load"])}]


# ------------------------------------------------------------ debug targets ----
## cmd_debug_grant's legacy keys (gold, bodies, living, bone, workers). Returns the amount applied.
func grant(key: String, v: float) -> float:
	match key:
		"gold", "bodies", "living":
			var store: String = "townsfolk" if key == "living" else key
			var old: float = res[store]
			var hi := INF
			if key == "living":
				hi = float(_sec("economy", "opening").get("living_cap", INF))
			# a grant never pulls an over-cap store down
			res[store] = clampf(old + v, 0.0, maxf(hi, old))
			return res[store] - old
		"bone":
			var old: float = res["materials"]
			res["materials"] = maxf(0.0, old + v)
			return res["materials"] - old
		"workers":
			var old := idle_undead
			idle_undead = maxi(0, int(old + v))
			return float(idle_undead - old)
	return 0.0


## cmd_set_haul_target: "" clears the convoy's own pick.
func set_gather_target(target: String) -> void:
	gather["target"] = target


func set_forge_level(level: int) -> void:
	town["forge_level"] = level


# ------------------------------------------------------------------- save ----
func to_dict() -> Dictionary:
	return {
		"res": res.duplicate(), "army": army.duplicate(), "town": town.duplicate(),
		"assignments": assignments.duplicate(), "idle_undead": idle_undead, "gather": gather.duplicate(),
	}


## "" if the save's legacy block `lg` is sound (it already fits SAVE_SPEC), else why not.
static func save_problem(lg: Dictionary, fort_ids: Dictionary) -> String:
	if not ["idle", "out", "back"].has(lg["gather"]["phase"]):
		return "gather phase"
	var gt: String = lg["gather"]["target"]
	if gt != "" and not fort_ids.has(gt):
		return "gather target"
	return ""


## Restores a checked legacy block. Types are restored here: ints from floats.
func from_dict(lg: Dictionary) -> void:
	res = {}
	for k in lg["res"]:
		res[k] = float(lg["res"][k])
	army = {"soldier": int(lg["army"]["soldier"]), "elite": int(lg["army"]["elite"])}
	town = {}
	for k in lg["town"]:
		town[k] = int(lg["town"][k])
	assignments = {}
	for k in lg["assignments"]:
		assignments[k] = int(lg["assignments"][k])
	idle_undead = int(lg["idle_undead"])
	gather = {"target": str(lg["gather"]["target"]), "phase": str(lg["gather"]["phase"]),
		"eta": float(lg["gather"]["eta"]), "load": float(lg["gather"]["load"])}
