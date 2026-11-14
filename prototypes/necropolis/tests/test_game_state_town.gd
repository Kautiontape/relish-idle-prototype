extends RefCounted
## GameState with TownSim wired in (MECHANICS §1.3 step 2, §3.2, §4; STATE-API §2.2, §4.1, §5, §9):
## WORK in the same substep, the mint from pits and last step's feed, muster into WAR, haul pickups off the forts,
## the views read from TownSim, the legacy getters, the BALANCE §0 new game, v1 → v2 saves and the
## fixtures. The influence field is shrunk in memory (a copy of the configs), so substeps stay cheap.

var t := TestUtil.new()
var _base := {}


func _cfgs() -> Dictionary:
	if _base.is_empty():
		_base = TestUtil.configs()
		var fld: Dictionary = _base["realm"]["field"]
		fld["tick_hz"] = 0.01
		fld["w"] = 8
		fld["h"] = 6
	return _base.duplicate(true)


func _mk() -> GameState:
	var s := GameState.new(_cfgs())
	s.debug_enabled = true
	s.cmd_new_game(1)
	return s


func _bld(s: GameState, lot_id: String) -> Dictionary:
	for b in s.view_town()["buildings"]:
		if b["lot_id"] == lot_id:
			return b
	return {}


func _lane(s: GameState, id: String) -> Dictionary:
	for l in s.view_lanes()["lanes"]:
		if l["id"] == id:
			return l
	return {}


func _schema_ok(v: Dictionary, name: String) -> Array:
	var spec: Dictionary = (ApiSchema.VIEWS[name] as Dictionary).duplicate()
	spec["rev"] = TYPE_INT
	var errs: Array = []
	ApiSchema.check(v, spec, name, errs)
	ApiSchema.non_finite(v, name, errs)
	return errs


func run() -> int:
	t.suite("game_state_town")
	_new_game()
	_work()
	_mint()
	_muster()
	_haul()
	_views()
	_events()
	_legacy()
	_migrate()
	_fixtures()
	_vat_hands()
	return t.failures


# ------------------------------------------------------------- BALANCE §0 ----
func _new_game() -> void:
	var s := _mk()
	var open: Dictionary = TestUtil.configs()["economy"]["opening"]
	var ts := s.town_sim
	var lots := {}
	for lot in ts.buildings:
		lots[lot] = [ts.buildings[lot]["building_id"], ts.buildings[lot]["level"], ts.buildings[lot]["state"]]
	t.ok(lots == {"lot-01": ["crypt", 1, "active"], "lot-02": ["raising_pit", 1, "active"], "lot-03": ["charnel_house", 1, "active"],
		"lot-04": ["market", 1, "active"]}, "the start buildings on their lots, working: %s" % str(lots))
	t.ok(open["buildings"] == {"lot-01": "crypt", "lot-02": "raising_pit", "lot-03": "charnel_house", "lot-04": "market"},
		"economy.json opening.buildings is BALANCE §0's Crypt, Raising Pit, Charnel House and Market")
	t.ok([ts.gold, ts.bone, ts.bodies, ts.workers, ts.living, ts.living_cap()] == [80.0, 30.0, 40.0, 12.0, 10.0, 16.0],
		"gold/bone/bodies 80/30/40, 12 workers, 10 living of 16")
	t.ok(_bld(s, "lot-04")["slots"] == 2, "a small market: 2 stalls")
	t.ok(s.valve == {"work": 0.40, "war": 0.45, "flood": 0.15} and s.valve_target == s.valve, "valve 0.40/0.45/0.15")
	var vr := s.view_relish()
	t.ok(vr["state"] == "home" and vr["phylactery_charges"] == 0 and vr["clones_ready"] == 0 and s.view_backups()["vats"] == [],
		"Relish home, no phylactery, no clones or vats")
	t.ok(s.view_fort("old-sluice")["first_dungeon"] and s.view_party()["starter_units"] == 0, "Old Sluice is flagged first")
	t.ok(s.town_tier == "hamlet" and s.haul_target == "auto" and ts.forge["level"] == 0 and ts.ladder == open.get("", ts.ladder)
		and ts.ladder == TestUtil.configs()["economy"]["job"]["default_ladder"], "hamlet, haul auto, forge 0, the default ladder")
	t.ok(ts.morale == 0.6 and ts.shock == 0.0 and ts.haul["convoys"].is_empty() and s.work_pending == 0.0, "morale at its base, no shock, no convoy, no WORK yet")
	# a new game resets the town in place
	var obj := ts.get_instance_id()
	s.cmd_debug_grant({"gold": 500.0, "workers": 9.0})
	ts.place_building("lot-05", "house", 1)
	s.cmd_set_staff_cap("lot-03", 0)
	s.cmd_set_job_priority(["tend", "forge", "mill", "stall", "pit", "haul", "build"])
	s.tick(5.0)
	s.cmd_new_game(2)
	t.ok(s.town_sim.get_instance_id() == obj and s.town_sim.gold == 80.0 and s.town_sim.workers == 12.0
		and not s.town_sim.buildings.has("lot-05") and s.town_sim.buildings["lot-03"]["staff_cap"] == -1
		and s.town_sim.ladder == TestUtil.configs()["economy"]["job"]["default_ladder"] and s.work_pending == 0.0,
		"cmd_new_game resets the one TownSim in place")


# ------------------------------------------ WORK in the same substep, the feed lagged ----
func _work() -> void:
	var s := _mk()
	var dt := s.substep_s()
	var mass := float(TestUtil.configs()["economy"]["worker"]["mass"])
	s.tick(dt)
	t.near(float(s.town_sim.rates["workers"]["in"]) * mass, s._split["work"], 1e-12, "the first substep's TownSim gets that substep's WORK")
	t.ok(s.work_pending == 0.0, "nothing waits in work_pending")
	var ok := true
	var never := true
	for i in 40:
		s.tick(dt)
		ok = ok and absf(float(s.town_sim.rates["workers"]["in"]) * mass - s._split["work"]) <= 1e-12 * maxf(1.0, s._split["work"])
		never = never and s.work_pending == 0.0
	t.ok(ok, "each substep TownSim takes exactly that substep's WORK (rate × dt)")
	t.ok(never, "work_pending stays 0 at every step boundary")
	t.ok(s.town_sim.workers > 12.0, "and the workforce grows from it (%.3f)" % s.town_sim.workers)
	# a save from before the lag (E2a) can hold WORK in flight: it arrives with the next step's, once.
	# The save is E2a-shaped: 3 mass in town.work_pending and a ledger block without `opening` (E2a
	# predates the ledger), so the load counts the pending mass in what the save holds
	var d: Dictionary = JSON.parse_string(JSON.stringify(_mk().to_dict()))
	d["town"]["work_pending"] = 3.0
	d["ledger"] = {"sources": {}, "sinks": {"dungeon": 0.0}}
	var e := GameState.new(_cfgs())
	e.debug_enabled = true
	var r := e.from_dict(d)
	t.ok(r["ok"] and e.work_pending == 3.0, "an E2a save with 3 mass of WORK in flight loads (%s)" % str(r.get("reason", "")))
	t.ok(GameState.Ledger.error(e.ledger()) < 1e-12, "the ledger balances before the first step (%s)" % String.num_scientific(GameState.Ledger.error(e.ledger())))
	e.tick(dt)
	t.near(float(e.town_sim.rates["workers"]["in"]) * mass * dt, e._split["work"] * dt + 3.0, 1e-12, "step 1: TownSim's WORK is the pending 3 plus this step's")
	t.ok(e.work_pending == 0.0 and GameState.Ledger.error(e.ledger()) < 1e-12, "then work_pending is 0, and the ledger balances (%s)" % String.num_scientific(GameState.Ledger.error(e.ledger())))
	e.tick(dt)
	t.near(float(e.town_sim.rates["workers"]["in"]) * mass * dt, e._split["work"] * dt, 1e-12, "step 2: this step's WORK only (delivered once)")
	t.ok(GameState.Ledger.error(e.ledger()) < 1e-12, "and the ledger still balances (%s)" % String.num_scientific(GameState.Ledger.error(e.ledger())))


# ------------------------------------------------------------ pits and feed ----
## The mint reads the working pits now and the feed of the step before (MECHANICS §3.2).
func _mint() -> void:
	var cfg: Dictionary = TestUtil.configs()["realm"]
	var bonus := float(TestUtil.configs()["economy"]["pit"]["bonus"])
	var s := _mk()
	s.tick(s.substep_s())
	t.near(s._split["mint"], 2.0 + 6.0 * 1.0, 1e-12, "the first substep: no step has burned yet (feed 0): 2 + 6 · 1 = 8")
	s.tick(s.substep_s())
	t.near(s._split["mint"], (2.0 + 6.0 * 1.0) * (1.0 + 0.6 * 1.0), 1e-12, "the next: (2 + 6 · 1) · (1 + 0.6 · feed 1) = 12.8")
	t.ok(float(cfg["P_base"]) == 2.0 and float(cfg["P_per_pit"]) == 6.0 and bonus == 0.6 and not cfg.has("P_per_slab"),
		"realm.json P_base 2, P_per_pit 6 (was P_per_slab); economy.json pit.bonus 0.6")
	t.near(s.view_hud()["rates"][0]["rate"], 12.8, 1e-12, "view_hud's mint rate")
	# the pit unstaffed: no burn, no feed bonus, but still a working pit
	var u := _mk()
	u.cmd_set_staff_cap("lot-02", 0)
	u.tick(u.substep_s())
	u.tick(u.substep_s())
	t.ok(u.town_sim.rates["feed"] == 0.0 and u._split["mint"] == 8.0, "an unstaffed pit: feed 0, mint P_base + P_per_pit = 8")
	# a starved pit: feed is burned / wanted, proportional
	var h := _mk()
	h.cmd_set_staff_cap("lot-03", 0)  # no hauling
	h.cmd_debug_grant({"bodies": -40.0})
	h.tick(h.substep_s())
	var feed := float(h.town_sim.rates["feed"])
	h.tick(h.substep_s())
	t.ok(feed > 0.0 and feed < 1.0, "bodies short: a partial feed (rot return only: %.4f)" % feed)
	t.near(h._split["mint"], 8.0 * (1.0 + bonus * feed), 1e-12, "the mint follows the feed smoothly, a step behind")
	# a second pit
	var p := _mk()
	p.town_sim.place_building("lot-05", "raising_pit", 1)
	p.tick(p.substep_s())
	p.tick(p.substep_s())
	t.ok(p.town_sim.pits() == 2, "two working pits")
	t.near(p._split["mint"], (2.0 + 6.0 * 2.0) * 1.6, 1e-12, "both fed: (2 + 6 · 2) · 1.6")
	t.ok(p.view_town()["buildings"][4]["output"]["mint"] == 6.0, "each pit's output shows its P_per_pit")


# ------------------------------------------------------------ muster to WAR ----
func _muster() -> void:
	var s := _mk()
	var mass := float(TestUtil.configs()["economy"]["worker"]["mass"])
	s.tick(s.substep_s())
	t.ok(s._split["muster"] == 0.0, "12 workers under 7 slots + idle_cap 10: no muster")
	s.cmd_debug_grant({"workers": 20.0})  # 32: 15 above 7 slots + 10 idle
	s.tick(s.substep_s())
	var sp: Dictionary = s._split
	t.ok(sp["muster"] >= 15.0 * mass / s.substep_s() - 1e-9, "the 15 above the cap muster at once: %.1f mass/s" % sp["muster"])
	t.near(sp["muster"], float(s.town_sim.rates["workers"]["muster"]) * mass, 1e-9, "muster mass/s = TownSim's muster × worker.mass")
	t.near(sp["war"], sp["mint"] * s.valve["war"] + sp["muster"], 1e-9, "WAR = mint · valve.war + muster")
	t.ok(s._realm_inputs["war"] == sp["war"], "RealmSim gets WAR with the muster in it")
	t.near(s.view_rates()["rates"]["war"]["in"], sp["war"], 0.0, "view_rates.war.in includes it")
	t.ok(s.town_sim.workers <= 17.0 + 1e-9, "the workforce ends the step at slots + idle_cap")


# ------------------------------------------------------------------- haul ----
## A twin pair: the same game, one with its haulers capped to 0. Until the convoy lands they match.
func _haul() -> void:
	var a := _mk()
	var b := _mk()
	b.cmd_set_staff_cap("lot-03", 0)
	for s in [a, b]:
		s.cmd_debug_set_state({"forts": {"ashgate": {"dead": 30.0}}})
		s.cmd_set_haul_target("ashgate")
	var picked := -1.0
	var gap := 0.0
	for i in 20:
		var phase: String = a.town_sim.haul["convoys"][0]["phase"] if not a.town_sim.haul["convoys"].is_empty() else ""
		a.tick(a.substep_s())
		b.tick(b.substep_s())
		var now: String = a.town_sim.haul["convoys"][0]["phase"] if not a.town_sim.haul["convoys"].is_empty() else ""
		if phase == "out" and now == "back":
			picked = a.town_sim.haul["convoys"][0]["load"]
			gap = b.realm.fort_by_id("ashgate")["dead"] - a.realm.fort_by_id("ashgate")["dead"]
			break
	t.ok(picked > 0.0, "the convoy picked up at Ashgate (%.3f mass)" % picked)
	t.ok(absf(gap - picked) <= 0.01 * picked, "the pickup came off Ashgate's dead: %.4f vs %.4f (k_clear on the rest aside)" % [gap, picked])
	t.ok(b.town_sim.haul["convoys"].is_empty(), "the twin with no haulers sent none")
	# the clamp: a pickup larger than the fort's dead now takes only what is there
	var c := _mk()
	c.cmd_debug_set_state({"forts": {"ashgate": {"dead": 10.0}, "vespers": {"dead": 5.0}}})
	c._apply_pickups([{"fort_id": "ashgate", "mass": 50.0}, {"fort_id": "vespers", "mass": 2.0}, {"fort_id": "nowhere", "mass": 9.0}])
	t.ok(c.realm.fort_by_id("ashgate")["dead"] == 0.0 and c.realm.fort_by_id("vespers")["dead"] == 3.0,
		"pickups are clamped to the fort's live dead (never negative); unknown forts are ignored")
	# the convoy in the views and the lane
	var v := _mk()
	v.cmd_debug_set_state({"forts": {"ashgate": {"dead": 60.0}}})
	v.cmd_set_haul_target("ashgate")
	for i in 30:  # until the first trip has landed and the next is out
		v.tick(v.substep_s())
		if v.town_sim.rates["haul_trip"] > 0.0 and not v.town_sim.haul["convoys"].is_empty():
			break
	var hv: Dictionary = v.view_town()["haul"]
	t.ok(hv["target"] == "ashgate" and hv["current"] == "ashgate" and hv["convoys"].size() == 1, "view_town.haul: the target and the convoy")
	var c0: Dictionary = v.town_sim.haul["convoys"][0]
	var want: Dictionary = {"from": "covington", "to": "ashgate"} if c0["phase"] == "out" else {"from": "ashgate", "to": "covington"}
	t.ok(hv["convoys"][0]["from"] == want["from"] and hv["convoys"][0]["to"] == want["to"] and hv["convoys"][0]["t"] == c0["t"]
		and hv["convoys"][0]["load"] == c0["load"] and not hv["convoys"][0].has("trip_s"), "TownSim's convoy mapped to {from, to, phase, t, load}")
	var trip: float = v.town_sim.rates["haul_trip"]
	t.ok(trip > 0.0 and _lane(v, "haul:ashgate:covington")["rate"] == trip, "the haul lane: Ashgate → Covington at the trip-averaged rate (%.3f)" % trip)
	var rb: Dictionary = v.view_rates()["rates"]["bodies"]
	t.near(rb["in"], float(v.town_sim.rates["bodies"]["rot"]) + trip, 1e-12, "view_rates.bodies.in: rot return + the trip-averaged haul")
	t.ok(_bld(v, "lot-03")["output"] == {"bodies": trip}, "the Charnel House's output is the haul")


# ------------------------------------------------------------------ views ----
func _views() -> void:
	var s := _mk()
	s.town_sim.place_building("lot-05", "well", 1)
	s.cmd_debug_set_state({"forts": {"vespers": {"dead": 40.0}}})
	s.tick(20.0)
	var ts := s.town_sim
	var r: Dictionary = ts.rates
	var v := s.view_town()
	t.ok(_schema_ok(v, "view_town").is_empty(), "view_town fits the contract: %s" % str(_schema_ok(v, "view_town")))
	t.ok(v["gold"] == ts.gold and v["bone"] == ts.bone and v["bodies"] == ts.bodies and v["bodies_cap"] == ts.body_cap()
		and v["living"] == ts.living and v["living_cap"] == 18.0 and v["trade_rate"] == r["trade_rate"], "stocks, caps (the well's +2 living cap) and trade")
	var w: Dictionary = v["workers"]
	t.ok(w["total"] == ts.workers and w["idle"] == ts.staffing["idle"] and w["in"] == r["workers"]["in"] and w["rot"] == r["workers"]["rot"]
		and w["muster"] == r["workers"]["muster"], "workers: TownSim's count, idle and flows")
	t.near(w["steady"], float(r["workers"]["in"]) * ts.lifetime_s(true), 1e-12, "steady = inflow × lifetime (Relish home)")
	t.ok(s.view_hud()["workers_steady"] == w["steady"] and w["steady"] > 30.0, "view_hud.workers_steady agrees (%.1f)" % w["steady"])
	t.ok(v["morale"]["value"] == ts.morale and v["morale"]["target"] == ts.morale_target()
		and v["morale"]["factors"] == [{"id": "base", "delta": 0.6}, {"id": "amenity:well", "delta": 0.03}], "morale and its factors: %s" % str(v["morale"]))
	t.ok(v["migrants"] == r["living"]["in"] and v["departures"] == r["living"]["out"], "migrants and departures")
	var jobs := {}
	for j in v["jobs"]:
		jobs[j["id"]] = [j["slots"], j["staffed"]]
	t.ok(jobs.keys() == ["haul", "pit", "stall"] and jobs["pit"] == [2, 2.0], "jobs with slots, in ladder order: %s" % str(jobs))
	t.ok(_bld(s, "lot-05")["slots"] == 0 and _bld(s, "lot-05")["output"] == {} and _bld(s, "lot-05")["state"] == "active", "the well: no slots, no output")
	# view_hud and view_rates
	var hud: Array = s.view_hud()["rates"]
	var rates: Dictionary = s.view_rates()["rates"]
	var flows := {"workers": r["workers"], "gold": r["gold"], "bone": r["bone"], "living": r["living"]}
	var ok := true
	for i in GameState.HUD_RATE_IDS.size():
		var id: String = GameState.HUD_RATE_IDS[i]
		if flows.has(id):
			var net := float(flows[id]["in"]) - float(flows[id]["out"])
			ok = ok and hud[i]["rate"] == net and rates[id]["net"] == net and rates[id]["in"] == flows[id]["in"] and rates[id]["out"] == flows[id]["out"]
	t.ok(ok, "view_hud's and view_rates' workers, gold, bone and living are TownSim's flows")
	t.ok(hud[2]["rate"] == rates["bodies"]["net"] and rates["bodies"]["out"] == r["bodies"]["out"], "bodies: out is pit burn + mill")
	t.ok(hud[2]["cap"] == ts.body_cap() and hud[5]["cap"] == ts.living_cap() and hud[1]["stock"] == ts.workers, "caps and stocks")
	for id in ["mint", "work", "war", "flood"]:
		t.ok(rates[id]["in"] == s._split[id] and rates[id]["out"] == rates[id]["in"] and rates[id]["net"] == 0.0, "view_rates.%s: the valve stream, a pass-through" % id)
	t.ok(rates["backlog"]["net"] == s.view_vei()["diff"], "backlog is live (test_game_state_rates checks every id)")
	t.ok(_lane(s, "work:covington:covington")["rate"] == s._split["work"] and _lane(s, "work:covington:covington")["kind"] == "work",
		"the work lane: Covington → Covington at the valve's WORK")
	# the commands drive TownSim
	var order := ["stall", "pit", "haul", "build", "mill", "forge", "tend"]
	s.cmd_set_job_priority(order)
	t.ok(ts.ladder == order and s.view_town()["ladder"] == order and s.view_town()["jobs"][0]["id"] == "stall", "cmd_set_job_priority sets TownSim's ladder")
	s.cmd_set_staff_cap("lot-04", 1)
	t.ok(ts.buildings["lot-04"]["staff_cap"] == 1 and _bld(s, "lot-04")["staffed"] == 1.0, "cmd_set_staff_cap is TownSim's cap")
	t.ok(s.cmd_set_staff_cap("lot-05", 1)["reason"] == "no_jobs" and s.cmd_set_staff_cap("lot-06", 1)["reason"] == "empty_lot", "no_jobs, empty_lot")
	# q reads TownSim's forge level
	var q0 := s.digest_q()
	ts.forge = {"level": 2, "progress": 0.0}
	t.near(s.digest_q() - q0, 0.2, 1e-12, "q_forge × TownSim's forge level")
	# relics the forge spends come off the stock
	var f := _mk()
	f.town_sim.place_building("lot-13", "forge", 1)
	f.cmd_debug_grant({"relics": 2, "workers": 4.0})
	f.town_sim.forge["progress"] = 119.9
	f.tick(f.substep_s())
	t.ok(f.town_sim.forge["level"] == 1 and f.relics == 1, "a forge level completed with a relic, taken off the stock (%d)" % f.relics)


# ----------------------------------------------------------------- events ----
func _events() -> void:
	var s := _mk()
	s.cmd_debug_grant({"workers": 6.0})
	t.ok(s.town_sim.start_construction("lot-05", "house", 1)["ok"], "a house starts on lot-05")
	s.tick(s.substep_s())
	var evs := s.drain_events().filter(func(e): return str(e["type"]).begins_with("building"))
	t.ok(evs == [{"type": "building_started", "lot_id": "lot-05", "building_id": "house", "level": 1, "upgrade": false, "t": s.t}],
		"building_started comes out of the next substep, stamped, with upgrade: %s" % str(evs))
	t.ok(_bld(s, "lot-05")["state"] == "constructing" and _bld(s, "lot-05")["level"] == 0 and _bld(s, "lot-05")["slots"] == 3,
		"view_town: constructing, level 0, 3 build slots")
	var done := {}
	for i in 400:
		s.tick(s.substep_s())
		for e in s.drain_events():
			if e["type"] == "building_done":
				done = e
		if not done.is_empty():
			break
	t.ok(done.get("lot_id", "") == "lot-05" and done.get("level", 0) == 1 and done.get("t", -1.0) == s.t, "building_done, stamped: %s" % str(done))
	s.town_sim.start_construction("lot-05", "house", 2)
	s.tick(s.substep_s())
	evs = s.drain_events().filter(func(e): return e["type"] == "building_started")
	t.ok(evs.size() == 1 and evs[0]["upgrade"] == true and evs[0]["level"] == 2, "an upgrade's building_started has upgrade: true")
	var errs: Array = []
	ApiSchema.check(evs[0], ApiSchema.EVENTS["building_started"], "event", errs)
	t.ok(errs.is_empty(), "and fits §6: %s" % str(errs))


# ------------------------------------------- the compatibility members (§2.2) ----
func _legacy() -> void:
	var s := _mk()
	var l := s.legacy_stores()
	t.ok(l["res"] == {"gold": 80.0, "materials": 30.0, "bodies": 40.0, "townsfolk": 10.0}, "res: gold, materials = bone, bodies, townsfolk = living")
	t.ok(l["army"] == {"soldier": 0, "elite": 0}, "army: empty")
	t.ok(l["town"] == {"slabs": 1, "vats": 0, "forge_level": 0, "sim_stations": 0, "trade_level": 0}, "town: slabs = working pits, vats = clones")
	t.ok(l["assignments"] == {"trade": 2, "forge": 0, "jobs": 0, "gather": 3, "slab": 2} and l["idle_undead"] == 5,
		"assignments: staffed stall, forge, build, haul, pit; idle_undead: idle workers")
	t.ok(l["gather"] == {"target": "", "phase": "idle", "eta": 0.0, "load": 0.0}, "gather: idle, no target")
	var ints := true
	for k in l["town"]:
		ints = ints and typeof(l["town"][k]) == TYPE_INT
	for k in l["assignments"]:
		ints = ints and typeof(l["assignments"][k]) == TYPE_INT
	t.ok(ints and typeof(l["idle_undead"]) == TYPE_INT and typeof(l["army"]["soldier"]) == TYPE_INT, "every count is an int (world_map prints %d)")
	l["res"]["gold"] = 1.0e6
	l["army"]["soldier"] = 40
	t.ok(s.town_sim.gold == 80.0 and s.legacy_stores()["army"]["soldier"] == 0, "writes to them change nothing")
	s.clones_ready = 2
	s.cmd_debug_set_state({"forge_level": 3})
	s.cmd_set_haul_target("vespers")
	t.ok(s.legacy_stores()["town"]["vats"] == 2 and s.legacy_stores()["town"]["forge_level"] == 3
		and s.legacy_stores()["gather"]["target"] == "vespers", "vats, forge level and the set target follow the new state")
	s.tick(s.substep_s())
	var g: Dictionary = s.legacy_stores()["gather"]
	var c: Dictionary = s.town_sim.haul["convoys"][0]
	t.ok(g["target"] == "vespers" and g["phase"] == "out" and absf(g["eta"] - (1.0 - c["t"]) * c["trip_s"]) < 1e-9 and g["load"] == 0.0,
		"gather: the convoy out, eta = (1 − t) · trip_s")
	t.ok(s.quality() == s.digest_q(), "quality() is q")
	var rs := s.raid_seed("ashgate")
	var f := s.realm.fort_by_id("ashgate")
	t.ok(rs.keys() == ["fort_id", "name", "tier", "cap", "living", "undead", "dead", "boss", "quality"] and rs["living"] == f["living"]
		and rs["quality"] == s.digest_q() and not rs["boss"] and s.raid_seed("nope") == {}, "raid_seed: the pre-E1 keys from the live fort")
	var bs := s.boss_seed()
	t.ok(bs["boss"] and bs["army"] == {"soldier": 0, "elite": 0} and bs["backlog"] == s.realm.vei["undead_queue"] and bs["odds"] == s.realm.odds()
		and bs["quality"] == s.digest_q(), "boss_seed: the pre-E1 keys, an empty army")
	t.ok(s.town_snapshot() == {}, "town_snapshot: {}")
	var before := s.to_dict()
	var rv := s.rev
	s.apply_town_result({"town": {"slabs": 9}, "spend": {"gold": 50.0}, "assignments": {"trade": 5}, "deploy_simulacra": [{"fort_id": "ashgate", "charges": 5.0, "rate": 1.0}]})
	t.ok(s.to_dict() == before and s.rev == rv and s.realm.simulacra.is_empty(), "apply_town_result: a no-op")


# ------------------------------------------------------------ v1 → v2 saves ----
func _migrate() -> void:
	var v1 := TestUtil.load_json("res://tests/fixtures/v1_day1.json")
	t.ok(v1.get("v") == 1.0 and v1.has("legacy"), "v1_day1.json is an E1 save (v 1, a legacy block)")
	var m := GameState.migrate(v1)
	var tn: Dictionary = m.get("town", {})
	t.ok(m.get("v") == 2 and not m.has("legacy") and m.has("town"), "migrate: v 2, the legacy block gone")
	t.ok([tn["gold"], tn["bone"], tn["bodies"], tn["living"], tn["workers"]] == [30.0, 12.0, 0.0, 10.0, 6.0],
		"legacy res and workers move into the town: 30 gold, 12 bone (materials), 0 bodies, 10 living (townsfolk), 6 workers")
	t.ok(tn["buildings"].map(func(b): return [b["lot_id"], b["building_id"], b["level"], b["state"], b["staff_cap"]]) == [
		["lot-01", "crypt", 1, "active", -1], ["lot-02", "raising_pit", 1, "active", -1],
		["lot-03", "charnel_house", 1, "active", -1], ["lot-04", "market", 1, "active", -1]], "v1's lots become the working start buildings")
	t.ok(tn["forge"] == {"level": 0, "progress": 0.0} and tn["haul"] == {"target": "auto", "current": "", "convoys": []} and tn["tier"] == "hamlet"
		and m["backups"]["clones_ready"] == 0 and not tn.has("morale"), "forge, haul, tier and clones; morale left to the load")
	var s := GameState.new(_cfgs())
	t.ok(s.from_dict(v1) == {"ok": true, "reason": ""}, "a v1 save loads")
	t.ok(s.town_sim.gold == 30.0 and s.town_sim.workers == 6.0 and s.town_sim.morale == 0.6 and s.view_town()["buildings"].size() == 4,
		"into TownSim, morale at its base")
	s.tick(60.0)
	t.ok(s.town_sim.workers > 6.0 and s.town_sim.gold > 30.0 and s._split["mint"] > 0.0, "and plays (60 s: workers %.2f, gold %.2f)" % [s.town_sim.workers, s.town_sim.gold])
	var d := s.to_dict()
	var s2 := GameState.new(_cfgs())
	t.ok(s2.from_dict(JSON.parse_string(JSON.stringify(d)))["ok"] and s2.to_dict() == d, "and saves as a v2 that round-trips")
	# the richer E1 midgame: stocks, a forge level, a set haul target, the legacy convoy dropped
	var mid := TestUtil.load_json("res://tests/fixtures/v1_midgame_2flips.json")
	var lg: Dictionary = mid["legacy"]
	var mm := GameState.migrate(mid)
	t.ok(mm["town"]["gold"] == lg["res"]["gold"] and mm["town"]["workers"] == float(lg["idle_undead"]) + 1.0
		and mm["town"]["forge"]["level"] == 1 and mm["town"]["tier"] == "village" and mm["town"]["haul"]["target"] == "greywall"
		and mm["town"]["haul"]["convoys"] == [], "midgame: gold, idle + assigned workers, forge 1, the village, the target; no convoy")
	var sm := GameState.new(_cfgs())
	t.ok(sm.from_dict(mid)["ok"] and sm.digest_q() > 1.2 and sm.view_relish()["state"] == "travelling", "it loads: forge 1 in q, Relish on her way")
	sm.tick(sm.substep_s())
	t.ok(sm.town_sim.haul["convoys"].size() == 1 and sm.town_sim.haul["convoys"][0]["fort"] == "greywall" and sm.town_sim.living <= sm.town_sim.living_cap(),
		"its first substep sends a convoy to the set target; the living fit the cap")
	# broken v1 saves are corrupt, not crashes
	var bad := v1.duplicate(true)
	bad.erase("legacy")
	t.ok(GameState.new(_cfgs()).from_dict(bad) == {"ok": false, "reason": "corrupt"}, "a v1 save without its legacy block is corrupt")
	bad = v1.duplicate(true)
	bad["legacy"]["res"]["gold"] = "lots"
	t.ok(GameState.new(_cfgs()).from_dict(bad) == {"ok": false, "reason": "corrupt"}, "a v1 save with a bad legacy store is corrupt")


# --------------------------------------------------------------- fixtures ----
func _fixtures() -> void:
	for name in GameState.FIXTURES:
		var s := GameState.new(_cfgs())
		s.debug_enabled = true
		t.ok(s.cmd_debug_load_fixture(name)["ok"], "%s loads" % name)
		var errs: Array = []
		ApiSchema.check(s.to_dict(), ApiSchema.SAVE, "to_dict", errs)
		for view in ["view_town", "view_hud", "view_rates", "view_lanes", "view_backups"]:
			errs.append_array(_schema_ok(s.call(view), view))
		t.ok(errs.is_empty(), "%s: the save and the town views fit the contract %s" % [name, str(errs)])
		var town: Dictionary = s.to_dict()["town"]
		t.ok(town["buildings"].size() == s.view_town()["buildings"].size() and town["workers"] == s.view_town()["workers"]["total"], "%s: view_town is its TownSim" % name)
		s.tick(10.0)
		var ts := s.town_sim
		t.ok(ts.gold >= 0.0 and ts.bone >= 0.0 and ts.bodies >= 0.0 and ts.workers >= 0.0 and ts.living >= 0.0 and s._split["mint"] > 0.0,
			"%s: 10 s on, it runs (mint %.2f)" % [name, s._split["mint"]])


# ------------------------------------------------------------ the vat rule ----
func _tend_of(s: GameState) -> Dictionary:
	for j in s.view_town()["jobs"]:
		if j["id"] == "tend":
			return j
	return {"id": "tend", "slots": 0, "staffed": 0.0}


## MECHANICS §7 (E2b-2): a staffed vat takes a hand. cmd_staff_vat opens its tend slot at once and
## the ladder fills it; unstaffing gives the hand back. A save keeps the vats and a load reopens
## their slots; a new game clears them.
func _vat_hands() -> void:
	t.suite("game_state_town-vats")
	var s := GameState.new(TestUtil.configs())
	s.debug_enabled = true
	t.ok(s.cmd_debug_load_fixture("pre_vei")["ok"], "pre_vei loads")
	t.ok(int(_tend_of(s)["slots"]) == 0 and float(_tend_of(s)["staffed"]) == 0.0 and s.view_backups()["vats"].size() == 2,
		"pre_vei: a Chapel with two unstaffed vats offers no tend slot")
	s.cmd_set_job_priority(["tend", "stall", "pit", "haul", "build", "mill", "forge"])
	t.ok(s.cmd_debug_grant({"workers": 3.0 - s.town_sim.workers})["ok"], "three workers")
	var stall0 := _staffed_job(s, "stall")
	var rv := s.rev
	t.ok(s.cmd_staff_vat(0, true)["ok"] and s.rev == rv + 1, "staff vat 0")
	t.ok(int(_tend_of(s)["slots"]) == 1 and float(_tend_of(s)["staffed"]) == 1.0 and _staffed_job(s, "stall") == stall0 - 1.0,
		"its tend slot opens at once and takes the hand the stall below it had (stall %.1f -> %.1f)" % [stall0, _staffed_job(s, "stall")])
	var d := s.to_dict()
	var n := GameState.new(TestUtil.configs())
	n.debug_enabled = true
	t.ok(n.from_dict(d)["ok"] and float(_tend_of(n)["staffed"]) == 1.0 and n.view_backups()["vats"][0]["staffed"],
		"a save keeps the vat and a load reopens its slot")
	t.ok(s.cmd_staff_vat(0, false)["ok"] and int(_tend_of(s)["slots"]) == 0 and _staffed_job(s, "stall") == stall0,
		"unstaffing it closes the slot and gives the hand back")
	s.cmd_staff_vat(1, true)
	s.cmd_new_game(3)
	t.ok(s.town_sim.vats_on() == [] and s.vats_staffed == [], "a new game clears the vats in TownSim too")


func _staffed_job(s: GameState, job: String) -> float:
	for j in s.view_town()["jobs"]:
		if j["id"] == job:
			return float(j["staffed"])
	return 0.0
