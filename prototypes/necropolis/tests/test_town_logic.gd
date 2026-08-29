extends RefCounted
## Covington visit logic: affordability, builds, stepper clamps, simulacrum
## gating, and the result-dict contract. Pure TownLogic — no UI, no autoloads.


func _base_seed() -> Dictionary:
	return {
		"town": {"slabs": 1, "vats": 0, "sim_stations": 0, "forge_level": 0, "trade_level": 0},
		"assignments": {"trade": 0, "forge": 0, "jobs": 0, "gather": 0, "slab": 0},
		"res": {"gold": 30.0, "materials": 12.0, "bodies": 0.0, "townsfolk": 10.0},
		"army": {"soldier": 0, "elite": 0},
		"idle_undead": 6, "quality": 1.2, "green_towns": 0,
		"gather": {"target": "", "phase": "idle", "eta": 0.0, "load": 0.0},
		"fort_ids": ["ashgate", "vespers", "whitecross"],
		"simulacra": [],
	}


func _mk(seed_over := {}, cfg_over := {}) -> TownLogic:
	var cfg := TestUtil.load_json("res://configs/town.json")
	if not cfg_over.has("spend_grace"):
		cfg_over["spend_grace"] = 0.0  # strict by default; grace tested explicitly
	for k in cfg_over:
		cfg[k] = cfg_over[k]
	var seed_data := _base_seed()
	for k in seed_over:
		seed_data[k] = seed_over[k]
	var l := TownLogic.new()
	l.setup(seed_data, cfg)
	return l


func run() -> int:
	var t := TestUtil.new()
	t.suite("town-logic")

	# --- config file itself ---------------------------------------------------
	var cfg := TestUtil.load_json("res://configs/town.json")
	t.ok(not cfg.is_empty(), "configs/town.json parses")
	t.ok((cfg.get("costs", {}) as Dictionary).has("slab_gold_per_current"), "config carries the costs block")

	# --- affordability + builds ----------------------------------------------
	var l := _mk()
	t.near(l.slab_cost(), 25.0, 0.001, "first slab costs 25 x 1 current slab")
	t.ok(l.can_afford(l.slab_cost(), 0.0), "30 gold affords the first slab")
	t.ok(l.buy_slab(), "slab purchase succeeds")
	t.ok(int(l.town["slabs"]) == 2, "slab count incremented")
	t.near(float(l.spent["gold"]), 25.0, 0.001, "spend records the slab cost as a delta")
	t.near(l.slab_cost(), 50.0, 0.001, "next slab costs 25 x 2")
	t.ok(not l.buy_slab(), "second slab (50g) blocked at 5g remaining")
	t.ok(int(l.town["slabs"]) == 2 and absf(float(l.spent["gold"]) - 25.0) < 0.001,
		"failed purchase changes nothing")

	var lv := _mk()
	t.ok(lv.buy_vat(), "vat affordable from base seed (30g, 8m)")
	t.ok(int(lv.town["vats"]) == 1, "vat count incremented")
	t.near(float(lv.spent["gold"]), 30.0, 0.001, "vat gold spent")
	t.near(float(lv.spent["materials"]), 8.0, 0.001, "vat materials spent")

	# --- overspend can never exceed the seed's res (+grace) -------------------
	var lo := _mk()
	for i in 50:
		lo.buy_slab()
		lo.buy_vat()
		lo.buy_forge()
		lo.craft_simulacrum("ashgate")
	t.ok(float(lo.spent["gold"]) <= 30.0 + 0.001, "gold spend capped at seed gold (spree)")
	t.ok(float(lo.spent["materials"]) <= 12.0 + 0.001, "materials spend capped at seed materials (spree)")

	var lg := _mk({"res": {"gold": 45.0, "materials": 0.0, "bodies": 0.0, "townsfolk": 0.0},
		"town": {"slabs": 2, "vats": 0, "sim_stations": 0, "forge_level": 0, "trade_level": 0}},
		{"spend_grace": 5.0})
	t.ok(lg.buy_slab(), "grace lets a 50g slab through at 45g (live totals only grow)")
	t.ok(float(lg.spent["gold"]) <= 45.0 + 5.0 + 0.001, "spend stays within seed + grace")
	t.ok(not lg.buy_slab(), "grace does not stack into a second overspend")

	# --- steppers clamp at the idle pool and at zero --------------------------
	var ls := _mk()
	var total := ls.total_undead()
	var assigned := 0
	for i in 7:
		if ls.assign("trade"):
			assigned += 1
	t.ok(assigned == 6, "assign drains exactly the idle pool (6)")
	t.ok(ls.idle_undead == 0, "idle pool empties, never negative")
	t.ok(not ls.assign("jobs"), "assign refused at idle 0")
	t.ok(ls.unassign("trade"), "unassign returns a worker")
	t.ok(ls.idle_undead == 1 and int(ls.assignments["trade"]) == 5, "counts move together")
	t.ok(not ls.unassign("forge"), "unassign refused at task count 0")
	t.ok(ls.total_undead() == total, "total assigned + idle constant through churn")

	# --- simulacrum requires the station --------------------------------------
	var rich := {"res": {"gold": 200.0, "materials": 200.0, "bodies": 0.0, "townsfolk": 10.0}}
	var lc := _mk(rich)
	t.ok(not lc.craft_simulacrum("whitecross"), "craft refused without a station")
	t.ok(lc.deploys.is_empty(), "no deployment recorded on refusal")
	t.ok(lc.buy_station(), "station purchase succeeds when funded")
	t.ok(lc.station_built(), "station registers as built")
	t.ok(not lc.buy_station(), "station is once-only")
	t.ok(lc.craft_simulacrum("whitecross"), "craft succeeds with station")
	t.ok(not lc.craft_simulacrum(""), "craft refused with no fort chosen")
	t.ok(lc.deploys.size() == 1, "one deployment recorded")
	var dep: Dictionary = lc.deploys[0]
	t.ok(str(dep["fort_id"]) == "whitecross", "deployment targets the chosen fort")
	var scfg: Dictionary = TestUtil.load_json("res://configs/town.json").get("simulacrum", {})
	t.near(float(dep["charges"]), float(scfg.get("charges", 300.0)), 0.001, "charges come from config")
	t.near(float(dep["rate"]), float(scfg.get("rate", 3.0)), 0.001, "rate comes from config")

	# --- forge + quality ------------------------------------------------------
	var lf := _mk(rich)
	t.near(lf.forge_cost(), 12.0, 0.001, "forge L1 costs 12 x 1")
	t.ok(lf.buy_forge(), "forge upgrade succeeds")
	t.near(lf.forge_cost(), 24.0, 0.001, "forge L2 costs 12 x 2")
	t.near(lf.quality(), 1.2 + 0.25, 0.001, "quality readout rises by the config bonus")

	# --- result contract ------------------------------------------------------
	var lr := _mk(rich)
	lr.buy_slab()
	lr.assign("gather")
	lr.gather_target = "vespers"
	lr.buy_station()
	lr.craft_simulacrum("ashgate")
	var r := lr.result()
	for key in ["town", "assignments", "idle_undead", "spend", "gather_target",
			"deploy_simulacra", "teleport_to"]:
		t.ok(r.has(key), "result has key '%s'" % key)
	t.ok(str(r["teleport_to"]) == "", "teleport_to is empty for now")
	t.ok(int(r["idle_undead"]) >= 0, "result idle_undead never negative")
	t.ok(str(r["gather_target"]) == "vespers", "gather target carried into result")
	t.ok((r["deploy_simulacra"] as Array).size() == 1, "new deployments carried into result")
	var spend: Dictionary = r["spend"]
	t.ok(float(spend["gold"]) <= 200.0 + 0.001 and float(spend["materials"]) <= 200.0 + 0.001,
		"spend never exceeds seed funds")
	var back := int(r["idle_undead"])
	for task in (r["assignments"] as Dictionary):
		back += int(r["assignments"][task])
	t.ok(back == 6, "result conserves the workforce (assigned + idle)")

	return t.failures
