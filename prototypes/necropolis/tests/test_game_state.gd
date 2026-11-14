extends RefCounted
## GameState: stepped and bulk ticking, substep accounting, determinism, events and the debug
## commands. Headless, no autoloads.


func _mk(seed_val := 1) -> GameState:
	var s := GameState.new()
	s.setup(TestUtil.configs())
	s.cmd_new_game(seed_val)
	return s


## Puts her at a node with the debug command, which these suites' release-mode states refuse.
func _place(s: GameState, node: String) -> void:
	var was := s.debug_enabled
	s.debug_enabled = true
	s.cmd_debug_set_state({"relish_at": node})
	s.debug_enabled = was


## Drives a boss run through the run API: Relish to Vei, begin, a v1 result converted, applied.
func _run_boss(s: GameState, v1: Dictionary) -> void:
	_place(s, "vei")
	var b := s.cmd_begin_boss()
	s.apply_result("boss", Results.from_v1("boss", v1, b["seed"]))


## Same for a raid at old-sluice; returns the run id.
func _run_raid(s: GameState, v1: Dictionary) -> int:
	_place(s, "old-sluice")
	var b := s.cmd_begin_dungeon("old-sluice")
	var d := v1.duplicate()
	d["fort_id"] = "old-sluice"
	s.apply_result("raid", Results.from_v1("raid", d, b["seed"]))
	return b["run_id"]


## More workers and bodies than the opening, and a named haul target, so every TownSim job runs.
func _precondition(s: GameState) -> void:
	s.debug_enabled = true
	s.cmd_debug_grant({"workers": 6.0, "bodies": 20.0})
	s.cmd_set_haul_target("ashgate")
	s.debug_enabled = false


func _rel(t: TestUtil, got: float, want: float, msg: String) -> void:
	t.ok(absf(got - want) <= 1e-6 * maxf(1.0, absf(want)), "%s (%s vs %s)" % [msg, str(got), str(want)])


func run() -> int:
	var t := TestUtil.new()
	t.suite("game-state")

	# --- stepped and bulk ticking agree ---
	var a := _mk()
	_precondition(a)
	for i in 1200:
		a.tick(0.5)
	var b := _mk()
	_precondition(b)
	t.ok(b.tick(600.0) == 1200, "tick(600) uncapped runs 1200 substeps")
	t.ok(a.town_sim.to_dict() == b.town_sim.to_dict() and a.realm.vei["living_pool"] == b.realm.vei["living_pool"]
		and a.town_sim.gold > 80.0, "stepped and bulk ticking agree exactly (the town and the realm)")

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
	t.ok(x.town_sim.to_dict() == y.town_sim.to_dict(), "same seed: the town identical")
	_run_boss(x, {"won": false, "relish_died": true})
	_run_boss(y, {"won": false, "relish_died": true})
	t.ok(x.won == y.won, "same seed: same boss outcome")
	t.ok(x._events == y._events, "same seed: same events")

	# --- events ---
	var e := _mk()
	_run_boss(e, {"won": true})
	var evs := e.drain_events()
	t.ok(evs.size() == 1 and evs[0]["type"] == "vei_result" and evs[0]["won"] == true, "boss win queues vei_result")
	t.ok(evs[0].has("t"), "event carries sim time")
	t.ok(e.drain_events().is_empty(), "drain empties the queue")
	var run_id := _run_raid(e, {"relish_died": true})
	evs = e.drain_events().filter(func(ev): return ev["type"] != "loot_banked")
	t.ok(evs.size() == 2 and evs[0]["type"] == "relish_died" and evs[0]["outcome"] == "unmade"
		and evs[0]["in_place"] == false and evs[0]["at"] == "old-sluice" and evs[0]["run_id"] == run_id
		and evs[0]["respawn_s"] == 0.0, "relish death queues relish_died (unmade)")
	t.ok(evs[1]["type"] == "relish_respawned" and evs[1]["with_clone"] == false and evs[1]["at"] == "covington",
		"then relish_respawned without a clone")
	var shock := float(TestUtil.configs()["economy"]["morale"]["death_shock"])
	t.near(e.town_sim.shock, shock, 1e-12, "unmade: the town takes morale.death_shock")
	e.clones_ready = 1
	_run_raid(e, {"relish_died": true})
	evs = e.drain_events().filter(func(ev): return ev["type"] != "loot_banked")
	t.ok(evs.size() == 2 and evs[0]["outcome"] == "clone" and evs[1]["with_clone"] == true, "a ready clone gives a clone respawn")
	t.ok(e.relish["state"] == "home" and e.clones_ready == 0 and e.town_sim.shock == shock,
		"she respawns home at once, the clone is spent, no new shock")

	# --- debug commands ---
	var g := _mk()
	var r := g.cmd_debug_grant({"gold": 5})
	t.ok(r["ok"] == false and r["reason"] == "not_debug", "refused with not_debug when debug_enabled is false")
	g.debug_enabled = true
	var gold0: float = g.town_sim.gold
	var rv := g.rev
	r = g.cmd_debug_grant({"gold": 10, "bogus": 1})
	t.ok(r["reason"] == "unknown_key" and r["key"] == "bogus" and g.town_sim.gold == gold0 and g.rev == rv,
		"unknown key refuses atomically")
	r = g.cmd_debug_grant({"time_scale": 5})
	t.ok(r["reason"] == "unknown_key" and g.time_scale == 1.0, "time_scale refused by grant")
	r = g.cmd_debug_set_state({"time_scale": 10})
	t.ok(r["ok"] and r["key"] == "" and g.time_scale == 10.0 and g.rev == rv + 1, "set_state accepts time_scale, bumps rev")
	r = g.cmd_debug_set_state({"time_scale": 0})
	t.ok(r["reason"] == "bad_value" and g.time_scale == 10.0, "non-positive time_scale refused")
	r = g.cmd_debug_grant({"workers": 7.9})
	t.ok(g.town_sim.workers == 12.0 + 7.9 and absf(r["applied"]["workers"] - 7.9) < 1e-12, "workers grant adds (workers are a float)")
	g.cmd_debug_grant({"gold": -9999})
	t.ok(g.town_sim.gold == 0.0, "clamped at 0")
	r = g.cmd_debug_grant({"gold": 5.5})
	t.near(g.town_sim.gold, 5.5, 1e-9, "grant adds")
	t.near(r["applied"]["gold"], 5.5, 1e-9, "applied reports the delta")

	return t.failures
