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

const GRACE_TOL := 1e-3
const RETAKE_K := 0.005
const RUN_S := 1500.0

var t := TestUtil.new()


func run() -> int:
	t.suite("held_forts")
	var c = load("res://tests/slow/convergence.gd").new()
	c.t = t
	var js: String = c.start_json("midgame_2flips")
	var res := {}
	for dt in [0.5, 10.0]:
		res[dt] = _run(c, js, dt)
	_convergence(res)
	_retake_effects(res[10.0])
	return t.failures


## One run of midgame_2flips with no WAR at core steps of `dt`: {shipped_380: {fort: mass}, retaken:
## [[fort, s from the start, cause]], events, grace_end, s (the state at the end)}.
func _run(c, js: String, dt: float) -> Dictionary:
	var s: GameState = c.load_state(js)
	s.cmd_debug_set_state({"valve": {"work": 0.5, "war": 0.0, "flood": 0.5}})
	s.drain_events()
	var t0 := s.t
	var grace := float(s.realm.fort_by_id("ashgate")["grace_s"])
	var shipped := {"ashgate": 0.0, "old-sluice": 0.0}
	var at_380 := {}
	var retaken: Array = []
	var evs: Array = []
	var el := 0.0
	while el < RUN_S - 1e-9:
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
	print("  [held_forts] dt %.1f: reship by 380 s %s; retaken %s" % [dt, str(at_380), str(retaken)])
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
