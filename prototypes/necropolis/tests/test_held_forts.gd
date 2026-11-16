extends RefCounted
## Held forts through GameState (IDLE §3, MECHANICS §3.4; E2b-2 T3.1): the contest's events at catch-up
## steps, and what a retake does to the fort's siege. RealmSim's own rules (grace, reship, the zero
## clock, the hold rule) are test_realm_sim's.
##
## The convergence check runs midgame_2flips with its WAR cut (valve 0.5 / 0 / 0.5): both held forts
## end their 374.5 s of grace with too little support (TownSim's muster is all the WAR), her reship
## lands, the garrisons go to 0 and both are
## broken inside the hour. Core steps only, field frozen (tests/slow/convergence.gd's harness), at 0.5
## and 10 s:
## - the grace ends at its time at 10 s as at 0.5 s: the reship each fort has had by 380 s (the first
##   10 s boundary after it) agrees within GRACE_TOL (measured 3.4e-4: her odds, which scale the
##   reship, are read at each part's start); landing at a step's boundary would give 0 or 1.8× it;
## - both forts are retaken (cause broken) at both dt, in the same order, and each retake at 10 s is
##   within max(one 10 s step, RETAKE_K × the time from its grace's end) of 0.5 s's. Measured at
##   T3.1: Ashgate 980.06 and 980.32 s (0.26 s apart, 0.04% of its 605.6 s fall), Old Sluice 1299.63
##   and 1299.82 s (0.19 s, 0.02% of 925.1 s), so the 10 s step is the binding gate.

## E3-3 (the siege live): that run moves u9, midgame's siege at Ashgate, to the crypt first, so it keeps testing "a WAR
## cut breaks both forts". The same cut with u9 sieging Ashgate (SIEGE_RUN_S, at both dt) holds Ashgate about 635 s
## longer, its waves blunted: retaken at 1614.85 s at 0.5 s and 1614.36 s at 10 s against 980.06 and 980.33 s, Old
## Sluice's unchanged (_siege_holds); IDLE I6's siege return at its retake is checked on that run (_retake_effects).
const GRACE_TOL := 1e-3
const RETAKE_K := 0.005
const RUN_S := 1500.0
const SIEGE_RUN_S := 1700.0

var t := TestUtil.new()


func run() -> int:
	t.suite("held_forts")
	var c = load("res://tests/slow/convergence.gd").new()
	c.t = t
	var js: String = c.start_json("midgame_2flips")
	var res := {}
	for dt in [0.5, 10.0]:
		res[dt] = _run(c, js, dt, false, RUN_S)
	_convergence(res)
	var sg := {}
	for dt in [0.5, 10.0]:
		sg[dt] = _run(c, js, dt, true, SIEGE_RUN_S)
	_siege_holds(res, sg)
	_retake_effects(sg[10.0])
	_retaken_mid_run()
	return t.failures


## One run of midgame_2flips with no WAR at core steps of `dt` for `run_s`, u9 sieging Ashgate with `siege` (else
## moved to the crypt first, E3-3): {shipped_380: {fort: mass}, retaken: [[fort, s from the start, cause]], events,
## grace_end, s (the state at the end)}.
func _run(c, js: String, dt: float, siege: bool, run_s: float) -> Dictionary:
	var s: GameState = c.load_state(js)
	if not siege:
		s.cmd_place_big_undead("u9", "crypt")
	s.cmd_debug_set_state({"valve": {"work": 0.5, "war": 0.0, "flood": 0.5}})
	s.drain_events()
	var t0 := s.t
	var grace := float(s.realm.fort_by_id("ashgate")["grace_s"])
	var shipped := {"ashgate": 0.0, "old-sluice": 0.0}
	var at_380 := {}
	var retaken: Array = []
	var evs: Array = []
	var el := 0.0
	while el < run_s - 1e-9:
		s._core_step(dt)
		el += dt
		for id in shipped:
			shipped[id] += float(s.realm.fort_by_id(id)["r_shipped"]) * dt
		if absf(el - 380.0) < 1e-9:
			at_380 = shipped.duplicate()
		for e in s.drain_events():
			var ev: Dictionary = e.duplicate()
			ev["t"] = float(e["t"]) - t0
			evs.append(ev)
			if e["type"] == "fort_retaken":
				retaken.append([str(e["fort_id"]), float(ev["t"]), str(e["cause"])])
	print("  [held_forts] dt %.1f%s: reship by 380 s %s; retaken %s" % [dt, ", u9 sieging Ashgate" if siege else "", str(at_380), str(retaken)])
	return {"shipped_380": at_380, "retaken": retaken, "events": evs, "grace_end": grace, "s": s}


func _convergence(res: Dictionary) -> void:
	var a: Dictionary = res[0.5]
	var b: Dictionary = res[10.0]
	t.near(float(a["grace_end"]), 374.5, 1e-9, "midgame_2flips: both forts start with 374.5 s of grace (setup)")
	for id in ["ashgate", "old-sluice"]:
		var x := float(a["shipped_380"][id])
		var y := float(b["shipped_380"][id])
		t.ok(x > 0.0 and absf(y - x) <= GRACE_TOL * x,
			"%s: by 380 s its reship is %.6f at 10 s and %.6f at 0.5 s (within %.1f%%): the grace ends at its time inside the step" % [
			id, y, x, GRACE_TOL * 100.0])
	var ra: Array = a["retaken"]
	var rb: Array = b["retaken"]
	t.ok(ra.size() == 2 and rb.size() == 2 and ra[0][0] == rb[0][0] and ra[1][0] == rb[1][0],
		"both forts are retaken at both dt, in the same order: %s; %s" % [str(ra), str(rb)])
	for i in mini(ra.size(), rb.size()):
		var fall := float(ra[i][1]) - float(a["grace_end"])
		var gate := maxf(10.0, RETAKE_K * fall)
		var gap := absf(float(rb[i][1]) - float(ra[i][1]))
		t.ok(ra[i][2] == "broken" and rb[i][2] == "broken" and gap <= gate,
			"%s: retaken (broken) at %.2f s at 10 s and %.2f s at 0.5 s, %.2f s apart (%.3f%% of its %.1f s fall; gate %.1f s)" % [
			ra[i][0], float(rb[i][1]), float(ra[i][1]), gap, 100.0 * gap / fall, fall, gate])


## E3-3: the same WAR cut with u9 sieging Ashgate holds Ashgate longer than without it, at both dt (its waves blunted by
## tithe.siege_block; measured: 1614.85 s at 0.5 s and 1614.36 s at 10 s against 980.06 and 980.33 s), and Old Sluice
## (no siege) falls as it does without it, within 1 s (her pool moves a little with the blunted waves).
func _siege_holds(res: Dictionary, sg: Dictionary) -> void:
	for dt in [0.5, 10.0]:
		var at := {}
		var at_sg := {}
		for r in res[dt]["retaken"]:
			at[r[0]] = float(r[1])
		for r in sg[dt]["retaken"]:
			at_sg[r[0]] = float(r[1])
		t.ok(at.has("ashgate") and at_sg.has("ashgate") and float(at_sg["ashgate"]) > float(at["ashgate"]) + 300.0
			and at_sg.has("old-sluice") and absf(float(at_sg["old-sluice"]) - float(at.get("old-sluice", -1.0))) <= 1.0,
			"dt %.1f, the WAR cut with u9 sieging Ashgate: Ashgate retaken at %.2f s against %.2f s without it; Old Sluice at %.2f s (within 1 s of it)" % [
			dt, float(at_sg.get("ashgate", -1.0)), float(at.get("ashgate", -1.0)), float(at_sg.get("old-sluice", -1.0))])


## IDLE I6 at the retake: midgame_2flips' siege big undead at Ashgate (u9) goes back to the crypt, with
## big_undead_returned right after the fort_retaken and at its t; the retake is stamped at its moment
## inside its 10 s step, and t never decreases.
func _retake_effects(r: Dictionary) -> void:
	var s: GameState = r["s"]
	var evs: Array = r["events"]
	var k := -1
	for i in evs.size():
		if evs[i]["type"] == "fort_retaken" and evs[i]["fort_id"] == "ashgate":
			k = i
	t.ok(k >= 0 and k + 1 < evs.size() and evs[k + 1] == {"type": "big_undead_returned", "uid": "u9", "fort_id": "ashgate", "t": evs[k]["t"]},
		"Ashgate's retake: big_undead_returned {uid: u9, fort_id: ashgate} right after it, at its t: %s" % (str(evs.slice(k, k + 2)) if k >= 0 else "none"))
	t.ok(k >= 0 and absf(fmod(float(evs[k]["t"]), 10.0)) > 1e-6, "the retake is stamped inside its 10 s step (%.3f s from the start)" % (float(evs[k]["t"]) if k >= 0 else -1.0))
	var b := s._find_uid(s.big_undead, "u9")
	t.ok(b["place"] == "crypt" and s.view_fort("ashgate")["siege"] == [], "u9 is in the crypt; Ashgate has no siege")
	var mono := true
	for i in range(1, evs.size()):
		mono = mono and float(evs[i]["t"]) >= float(evs[i - 1]["t"])
	t.ok(mono and evs.size() > 4, "event t never decreases over the run (%d events)" % evs.size())
	for e in evs:
		var errs: Array = []
		ApiSchema.check(e, ApiSchema.EVENTS.get(e["type"], {}), "event", errs)
		if e["type"] in ["fort_retaken", "big_undead_returned"]:
			t.ok(errs.is_empty() and ApiSchema.EVENTS.has(e["type"]), "%s matches the contract%s" % [e["type"], "" if errs.is_empty() else ": " + str(errs)])


# ------------------------- a fort retaken during its own raid pays no counter-garrison clear ----
## A retreat result for the open run's seed that kills all of its living and brings 2 relics.
func _clear_res(sd: Dictionary) -> Dictionary:
	return {
		"v": 2, "run_id": sd["run_id"], "seed_rev": sd["seed_rev"], "fort_id": sd["fort"]["id"],
		"warden_beaten": false, "retreated": true, "relish_died": false, "revived_in_place": 0,
		"killed_living_mass": sd["living"], "raised": [], "chaff_mass": 0.0, "garrison_mass": sd["garrison_in_mass"],
		"party_lost": [], "loot": {"relics": 2, "blueprints": [], "husks": [], "remnants": [], "essence": 0},
	}


## A new game with Greywall held (living 52, undead 20) and a raid open on it; `retake` retakes it
## mid-run. Used: RealmSim._retaken(f, "broken", 0.0) called directly (the realm's own zero clock
## needs a hold.break_s-long contest), its events dropped (no siege big undead, Relish is in_dungeon).
## Returns {s, cleared, loot_banked, relics, yield_c, held}: the clear event count, the loot_banked
## count, the relics gained and the fort's yield_c / held after a valid retreat that kills all its living.
func _mid_run(retake: bool) -> Dictionary:
	var s := GameState.new(TestUtil.configs())
	s.cmd_new_game(1)
	s.debug_enabled = true
	s.realm.hold("greywall", 0.0)
	s.cmd_debug_set_state({"relish_at": "greywall", "forts": {"greywall": {"living": 52.0, "undead": 20.0}}})
	var sd: Dictionary = s.cmd_begin_dungeon("greywall")["seed"]
	var f: Dictionary = s.realm.fort_by_id("greywall")
	if retake:
		s.realm._retaken(f, "broken", 0.0)
		s.realm.events.clear()
	s.drain_events()
	var relics0 := s.relics
	var ok: bool = s.apply_result("raid", _clear_res(sd))["ok"]
	var evs := s.drain_events()
	return {"ok": ok, "cleared": evs.filter(func(e): return e["type"] == "counter_garrison_cleared").size(),
		"banked": evs.filter(func(e): return e["type"] == "loot_banked").size(), "relics": s.relics - relics0,
		"yield_c": float(f["yield_c"]), "held": bool(f["held"])}


func _retaken_mid_run() -> void:
	t.suite("held-forts-retaken-mid-raid")
	var decay: float = float(TestUtil.configs()["loot"]["reclear_decay"])
	var c := _mid_run(false)
	t.ok(c["ok"] and c["cleared"] == 1 and c["banked"] == 1 and c["relics"] == 2
		and absf(c["yield_c"] - decay) < 1e-12,
		"control, still held: the clear event is raised, the yield spends to %.2f, the loot is banked: %s" % [decay, str(c)])
	var r := _mid_run(true)
	t.ok(r["ok"] and not r["held"], "retaken mid-run: the result still applies, the fort is Vei's: %s" % str(r))
	t.ok(r["cleared"] == 0, "retaken mid-run: no counter_garrison_cleared for a fort Vei owns (%d)" % r["cleared"])
	t.ok(r["yield_c"] == 1.0, "retaken mid-run: yield_c stays at the retake's 1 (%.3f), not halved" % r["yield_c"])
	t.ok(r["banked"] == 1 and r["relics"] == 2, "retaken mid-run: the retreat banks its loot as usual (%d event, %d relics)" % [r["banked"], r["relics"]])
