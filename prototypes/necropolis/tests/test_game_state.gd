extends RefCounted
## GameState: golden parity with the pre-extraction Game autoload, substep
## accounting, determinism, events and the debug commands. Headless, no autoloads.


func _mk(seed_val := 1) -> GameState:
	var s := GameState.new()
	s.setup(TestUtil.configs())
	s.cmd_new_game(seed_val)
	return s


func _precondition(s: GameState) -> void:
	s.assignments["gather"] = 2
	s.assignments["slab"] = 1
	s.assignments["jobs"] = 1
	s.assignments["trade"] = 1
	s.res["bodies"] = 20


func _rel(t: TestUtil, got: float, want: float, msg: String) -> void:
	t.ok(absf(got - want) <= 1e-6 * maxf(1.0, absf(want)), "%s (%s vs %s)" % [msg, str(got), str(want)])


func _check_golden(t: TestUtil, s: GameState, tag: String) -> void:
	var v: Dictionary = s.realm.vei
	var l := 0.0
	var d := 0.0
	var u := 0.0
	for f in s.realm.forts:
		l += f["living"]
		d += f["dead"]
		u += f["undead"]
	var fs := [0.0, 0.0, 0.0]
	for x in s.field.green:
		fs[0] += x
	for x in s.field.orange:
		fs[1] += x
	for x in s.field.entrench:
		fs[2] += x
	_rel(t, v["undead_queue"], 0.0, tag + " undead_queue")
	_rel(t, v["dead_queue"], 0.0, tag + " dead_queue")
	_rel(t, v["living_pool"], 599.9570080097985, tag + " living_pool")
	_rel(t, l, 2868.0327421751444, tag + " forts living")
	_rel(t, d, 151.31843753977864, tag + " forts dead")
	_rel(t, u, 91.09017048540989, tag + " forts undead")
	_rel(t, s.res["gold"], 243.36510000000152, tag + " gold")
	_rel(t, s.res["materials"], 30.000000000000682, tag + " materials")
	_rel(t, s.res["bodies"], 280.71001190347215, tag + " bodies")
	_rel(t, s.res["townsfolk"], 16.87600000000026, tag + " townsfolk")
	t.ok(s.green_towns == 1, tag + " green_towns")
	t.ok(s.gather["phase"] == "out", tag + " gather phase")
	_rel(t, fs[0], 283.3603042630535, tag + " field green sum")
	_rel(t, fs[1], 1010.8601058052695, tag + " field orange sum")
	_rel(t, fs[2], -4763.510489614215, tag + " field entrench sum")


func run() -> int:
	var t := TestUtil.new()
	t.suite("game-state")

	# --- golden parity (numbers captured from the old Game._tick(0.5) x 1200) ---
	var a := _mk()
	_precondition(a)
	for i in 1200:
		a.tick(0.5)
	_check_golden(t, a, "stepped")
	var b := _mk()
	_precondition(b)
	t.ok(b.tick(600.0) == 1200, "tick(600) uncapped runs 1200 substeps")
	_check_golden(t, b, "bulk")
	t.ok(a.res["gold"] == b.res["gold"] and a.realm.vei["living_pool"] == b.realm.vei["living_pool"],
		"stepped and bulk ticking agree exactly")

	# --- substep accounting ---
	var s := _mk()
	var rev0 := s.rev
	t.ok(s.tick(1.25) == 2, "tick(1.25) runs 2 substeps")
	t.ok(s.rev == rev0 + 2, "rev counts substeps")
	t.near(s._acc, 0.25, 1e-9, "0.25 s left over")
	t.ok(s.tick(0.25) == 1, "tick(0.25) completes a third substep")
	t.ok(s.tick(100.0, 16) == 16, "cap of 16 substeps honoured")
	t.near(s._acc, 0.0, 1e-12, "remainder dropped after the cap")
	t.ok(s.tick(0.1) == 0, "a sub-step dt runs nothing")

	# --- determinism ---
	var x := _mk(7)
	var y := _mk(7)
	t.ok(x.rng_seed is String and x.rng_seed == "7", "rng_seed is a String")
	for st in [x, y]:
		_precondition(st)
		st.tick(120.0)
	t.ok(x.realm.vei["undead_queue"] == y.realm.vei["undead_queue"], "same seed: undead_queue identical")
	t.ok(x.res["gold"] == y.res["gold"], "same seed: gold identical")
	x.auto_resolve_boss()
	y.auto_resolve_boss()
	t.ok(x.won == y.won, "same seed: same boss outcome")
	t.ok(x._events == y._events, "same seed: same events")

	# --- events ---
	var e := _mk()
	e.apply_boss_result({"won": true})
	var evs := e.drain_events()
	t.ok(evs.size() == 1 and evs[0]["type"] == "vei_result" and evs[0]["won"] == true, "boss win queues vei_result")
	t.ok(evs[0].has("t"), "event carries sim time")
	t.ok(e.drain_events().is_empty(), "drain empties the queue")
	e.apply_raid_result({"fort_id": e.realm.forts[0]["id"], "relish_died": true})
	evs = e.drain_events()
	t.ok(evs.size() == 2 and evs[0]["type"] == "relish_died" and evs[0]["outcome"] == "unmade"
		and evs[0]["in_place"] == false and evs[0]["at"] == "covington" and evs[0]["run_id"] == -1
		and evs[0]["respawn_s"] == 0.0, "relish death queues relish_died (unmade)")
	t.ok(evs[1]["type"] == "relish_respawned" and evs[1]["with_clone"] == false and evs[1]["at"] == "covington",
		"then relish_respawned without a clone")
	e.town["vats"] = 1
	e.apply_raid_result({"fort_id": e.realm.forts[0]["id"], "relish_died": true})
	evs = e.drain_events()
	t.ok(evs.size() == 2 and evs[0]["outcome"] == "clone" and evs[1]["with_clone"] == true, "legacy vat gives a clone respawn")
	t.ok(e.relish["state"] == "home" and e.town["vats"] == 0, "she respawns home at once, the vat is spent")

	# --- debug commands ---
	var g := _mk()
	var r := g.cmd_debug_grant({"gold": 5})
	t.ok(r["ok"] == false and r["reason"] == "not_debug", "refused with not_debug when debug_enabled is false")
	g.debug_enabled = true
	var gold0: float = g.res["gold"]
	var rv := g.rev
	r = g.cmd_debug_grant({"gold": 10, "bogus": 1})
	t.ok(r["reason"] == "unknown_key" and r["key"] == "bogus" and g.res["gold"] == gold0 and g.rev == rv,
		"unknown key refuses atomically")
	r = g.cmd_debug_grant({"time_scale": 5})
	t.ok(r["reason"] == "unknown_key" and g.time_scale == 1.0, "time_scale refused by grant")
	r = g.cmd_debug_set_state({"time_scale": 10})
	t.ok(r["ok"] and r["key"] == "" and g.time_scale == 10.0 and g.rev == rv + 1, "set_state accepts time_scale, bumps rev")
	r = g.cmd_debug_set_state({"time_scale": 0})
	t.ok(r["reason"] == "bad_value" and g.time_scale == 10.0, "non-positive time_scale refused")
	r = g.cmd_debug_grant({"workers": 7.9})
	t.ok(g.idle_undead == 13 and g.idle_undead is int and r["applied"]["workers"] == 7, "workers grant adds, ints truncated")
	g.cmd_debug_grant({"gold": -9999})
	t.ok(g.res["gold"] == 0.0, "clamped at 0")
	r = g.cmd_debug_grant({"gold": 5.5})
	t.near(g.res["gold"], 5.5, 1e-9, "grant adds")
	t.near(r["applied"]["gold"], 5.5, 1e-9, "applied reports the delta")

	return t.failures
