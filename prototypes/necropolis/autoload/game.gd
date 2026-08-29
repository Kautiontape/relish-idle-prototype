extends Node
## Global game state hub. Owns the realm sim, influence field, town economy,
## army, and Relish's mortality. Ticks regardless of which scene is active —
## this is an idle game; the realm never sleeps.

signal realm_ticked
signal relish_respawned(with_vat: bool)
signal victory
signal defeat_boss

var realm: RealmSim
var field: InfluenceField
var time_scale := 1.0

# --- Relish's holdings ---
var army := {"soldier": 0, "elite": 0}
var res := {"gold": 30.0, "materials": 12.0, "bodies": 0.0, "townsfolk": 10.0}
var town := {"slabs": 1, "vats": 0, "sim_stations": 0, "forge_level": 0, "trade_level": 0}
var assignments := {"trade": 0, "forge": 0, "jobs": 0, "gather": 0, "slab": 0}
var idle_undead := 6  # unassigned workers in Covington
var gather := {"target": "", "phase": "idle", "eta": 0.0, "load": 0.0}
var towns: Array = []
var green_towns := 0
var won := false
var stats := {"raised_total": 0.0, "raids": 0, "deaths": 0, "sims_built": 0}

var _field_acc := 0.0
var _raiding_fort := ""


func raiding_fort_id() -> String:
	return _raiding_fort


func _ready() -> void:
	randomize()
	new_game()


func new_game() -> void:
	var cfg: Dictionary = ConfigDb.data.get("realm", {})
	var world: Dictionary = ConfigDb.data.get("world", {})
	realm = RealmSim.new()
	realm.setup(world, cfg)
	realm.send_relish("covington")
	field = InfluenceField.new()
	field.setup(cfg.get("field", {}), RealmSim._vec(world.get("size", [2048, 1440])))
	towns = []
	for tw in world.get("towns", []):
		towns.append({
			"id": tw.get("id", ""), "name": tw.get("name", "?"),
			"pos": RealmSim._vec(tw.get("pos", [0, 0])),
			"pop": float(tw.get("pop", 30)), "control": "none",
		})
	# pre-warm the field so the map doesn't start blank
	for i in 90:
		_inject_sources(0.2)
		field.tick(0.2)


func quality() -> float:
	var cfg: Dictionary = ConfigDb.data.get("realm", {})
	var q: float = float(cfg.get("q", 1.2)) \
		+ float(cfg.get("q_per_forge", 0.25)) * town["forge_level"] \
		+ float(cfg.get("q_per_elite", 0.01)) * army["elite"]
	return clampf(q, 1.0, float(cfg.get("q_max", 4.0)))


func _process(delta: float) -> void:
	var dt := delta * time_scale
	while dt > 0.0001:
		var step := minf(dt, 0.5)
		_tick(step)
		dt -= step


func _tick(dt: float) -> void:
	var cfg: Dictionary = ConfigDb.data.get("realm", {})
	realm.t["q"] = quality()
	var mint: float = float(cfg.get("P_base", 2.0)) + float(cfg.get("P_per_slab", 2.0)) * town["slabs"]
	if res["bodies"] > 0.5 and assignments["slab"] > 0:
		var burn: float = minf(res["bodies"], float(cfg.get("slab_bodies_per_s", 0.12)) * town["slabs"] * dt)
		res["bodies"] -= burn
		mint *= float(cfg.get("slab_mint_bonus", 1.6))
	realm.t["P_base"] = mint
	realm.step(dt)
	_tick_town(dt, cfg)
	_tick_gather(dt, cfg)
	_field_acc += dt
	var period: float = 1.0 / float(cfg.get("field", {}).get("tick_hz", 5.0))
	# Cap field work per tick: at high time_scale the field may lag behind the
	# realm (it is territory visualisation + town control; exactness not needed).
	var field_ticks := 0
	while _field_acc >= period and field_ticks < 2:
		_field_acc -= period
		_inject_sources(period)
		field.tick(period)
		field_ticks += 1
	if field_ticks > 0:
		_update_towns(cfg)
	_field_acc = minf(_field_acc, period * 4.0)
	realm_ticked.emit()


func _tick_town(dt: float, cfg: Dictionary) -> void:
	res["gold"] += (float(cfg.get("gold_per_townsfolk", 0.02)) * res["townsfolk"] \
		+ float(cfg.get("gold_per_job_worker", 0.06)) * assignments["jobs"] \
		+ float(cfg.get("gold_per_trade_worker", 0.03)) * assignments["trade"]) * dt
	res["materials"] += float(cfg.get("materials_per_trade_worker", 0.03)) * assignments["trade"] * dt
	res["townsfolk"] += float(cfg.get("migrant_rate_per_town", 0.012)) * green_towns * dt


func _tick_gather(dt: float, cfg: Dictionary) -> void:
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


func _inject_sources(dt: float) -> void:
	var fcfg: Dictionary = ConfigDb.data.get("realm", {}).get("field", {})
	var src_main: float = float(fcfg.get("src_main", 3.0))
	var src_fort: float = float(fcfg.get("src_fort", 1.1))
	field.inject(realm.cov_pos, true, src_main * (1.0 + 0.15 * town["slabs"]) * dt, 2)
	var vei_str: float = 1.0 + realm.vei["living_pool"] / maxf(1.0, float(ConfigDb.data.get("realm", {}).get("vei_pool_cap", 600.0)))
	field.inject(realm.vei_pos, false, src_main * vei_str * dt, 3)
	for f in realm.forts:
		var cap: float = f["cap"]
		if f["undead"] > 0.5:
			field.inject(f["pos"], true, src_fort * (f["undead"] / cap) * dt, 1)
		if f["living"] > 0.5:
			field.inject(f["pos"], false, src_fort * (f["living"] / cap) * dt, 1)


func _update_towns(cfg: Dictionary) -> void:
	var thresh: float = float(cfg.get("field", {}).get("town_threshold", 0.18))
	green_towns = 0
	for tw in towns:
		var dom: float = field.dominance_at(tw["pos"])
		tw["control"] = "green" if dom > thresh else ("orange" if dom < -thresh else "none")
		if tw["control"] == "green":
			green_towns += 1


# ------------------------------------------------------------------ raids ----
func raid_seed(fort_id: String) -> Dictionary:
	var f := realm.fort_by_id(fort_id)
	if f.is_empty():
		return {}
	return {
		"fort_id": fort_id, "name": f["name"], "tier": f["tier"], "cap": f["cap"],
		"living": f["living"], "undead": f["undead"], "dead": f["dead"],
		"boss": false, "quality": quality(),
	}


func begin_raid(fort_id: String) -> void:
	_raiding_fort = fort_id
	realm.raiding = true


func end_raid() -> void:
	_raiding_fort = ""
	realm.raiding = false


func apply_raid_result(r: Dictionary) -> void:
	var f := realm.fort_by_id(str(r.get("fort_id", "")))
	if f.is_empty():
		return
	stats["raids"] += 1
	var killed: float = minf(f["living"], float(r.get("killed_living_mass", 0.0)))
	f["living"] -= killed
	f["dead"] += killed
	var chaff: float = minf(f["dead"], float(r.get("raised_chaff_mass", 0.0)))
	f["dead"] -= chaff
	realm.vei["undead_queue"] += chaff  # worthless undead are thrown at Vei
	var good_mass: float = minf(f["dead"], float(r.get("good_mass", 0.0)))
	f["dead"] -= good_mass
	army["soldier"] += int(r.get("raised_soldiers", 0))
	army["elite"] += int(r.get("raised_elites", 0))
	var garrison: float = minf(f["dead"], float(r.get("garrison_mass", 0.0)))
	f["dead"] -= garrison
	f["undead"] += garrison
	stats["raised_total"] += chaff + good_mass + garrison
	if bool(r.get("relish_died", false)):
		_relish_dies()


func auto_resolve_raid(fort_id: String) -> void:
	# Fallback when the raid scene is unavailable: a decent but unspectacular raid.
	var f := realm.fort_by_id(fort_id)
	if f.is_empty():
		return
	apply_raid_result({
		"fort_id": fort_id,
		"killed_living_mass": f["living"] * 0.3,
		"raised_chaff_mass": (f["dead"] + f["living"] * 0.3) * 0.5,
		"raised_soldiers": 1 + int(f["tier"]),
		"raised_elites": 0,
		"good_mass": 4.0,
		"garrison_mass": (f["dead"] + f["living"] * 0.3) * 0.2,
		"relish_died": false,
	})


func _relish_dies() -> void:
	stats["deaths"] += 1
	if town["vats"] > 0:
		town["vats"] -= 1
		relish_respawned.emit(true)
	else:
		# no clone vat: the realm carries on without her for a while and the army scatters
		army["soldier"] = int(army["soldier"] * 0.6)
		army["elite"] = int(army["elite"] * 0.7)
		relish_respawned.emit(false)


# ------------------------------------------------------------------ town -----
func town_snapshot() -> Dictionary:
	return {
		"town": town.duplicate(true), "assignments": assignments.duplicate(true),
		"res": res.duplicate(true), "army": army.duplicate(true),
		"idle_undead": idle_undead, "quality": quality(),
		"green_towns": green_towns, "gather": gather.duplicate(true),
		"fort_ids": realm.forts.map(func(f): return f["id"]),
		"simulacra": realm.simulacra.duplicate(true),
	}


func apply_town_result(r: Dictionary) -> void:
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
	for s in r.get("deploy_simulacra", []):
		realm.simulacra.append(s)
		stats["sims_built"] += 1


# ------------------------------------------------------------------ boss -----
func boss_seed() -> Dictionary:
	return {
		"fort_id": "vei", "name": "Vei's Domain", "tier": 5, "cap": 800.0,
		"living": 500.0, "undead": 0.0, "dead": 60.0, "boss": true,
		"quality": quality(), "backlog": realm.vei["undead_queue"],
		"army": army.duplicate(true), "vei_capacity": float(ConfigDb.v("realm", "R_vei", 50.0)),
		"odds": realm.readout()["odds"],
	}


func apply_boss_result(r: Dictionary) -> void:
	if bool(r.get("won", false)):
		won = true
		victory.emit()
		return
	realm.vei["undead_queue"] *= 0.35  # she digests a chunk of the massed horde
	army["soldier"] = int(army["soldier"] * 0.3)
	army["elite"] = int(army["elite"] * 0.4)
	if bool(r.get("relish_died", true)):
		_relish_dies()
	defeat_boss.emit()


func auto_resolve_boss() -> void:
	var odds: float = realm.readout()["odds"]
	apply_boss_result({"won": randf() < odds, "relish_died": true})
