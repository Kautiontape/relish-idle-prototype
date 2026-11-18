extends RefCounted
## The I1 bone-gap hour, live against closed (the E4 final review's item 3, handoff 23 ruling 3; IDLE §8). The state:
## the sessions policy's first session, replayed in an open game (sessions_open) and run open to 3 000 s, inside its
## first away, after the House; no build starts in the next hour in any run. From it, one hour open (live frames)
## against the same hour caught up at 5 s and 10 s steps (idle.catchup_max_steps 720 and 360, a load 3 600 s on).
## The bone made (the store's rise; nothing in the hour spends bone) reads, at 3137462 (sim-identical to 4384a17's fix
## for this run): open +122.99, 5 s +138.12, 10 s +151.34 (7 s +131.89, not run here), the residual IDLE §8 records
## and leaves unchased. TownSim._haul_wait_s fixed the departure mark (test_town_sim _haul_wait: the departures and loads
## match live at 5 s and 10 s), so what is left is not the departure; IDLE's reading (the convoy's corpse projection
## holds the last realm step's dead_rate over a step) stays unconfirmed. This pins the bound: a closed run more than
## BOUND[dt] off the open hour fails, so a regression past the recorded residual shows. Wall time is printed.

var t := TestUtil.new()
const CLOCK := 1_800_000_000
const T0 := 3000.0
const SPAN := 3600.0
## |closed − open| bone made allowed, per catch-up step (s): the recorded residual (+15.13 and +28.35) plus a margin.
const BOUND := {5.0: 16.0, 10.0: 29.5}
var _dir := "user://test_haul_hour_%d" % OS.get_process_id()


func run() -> int:
	t.suite("haul_hour")
	var u0 := Time.get_ticks_msec()
	var cfg: Dictionary = Autoplayer.cfgs()
	var lead := Autoplayer._bot("sessions", cfg, {"print_rows": false})
	lead.record = true
	lead.new_game()
	lead.play_sessions(1)
	var t_leave := float(lead.closes[0]["t"])
	var first: Array = lead.cmd_log.filter(func(e): return float(e["t"]) <= t_leave)
	var fol := Autoplayer._bot("sessions_open", cfg)
	fol.new_game()
	fol.replay(first, 0)
	fol.open_rows = false
	fol._open_to(T0)
	var s: GameState = fol.s
	t.ok(t_leave < T0 and absf(s.t - T0) < 1e-6, "(setup) the first session closes at %.0f s; the open game is at %.2f s" % [t_leave, s.t])
	DirAccess.make_dir_recursive_absolute(_dir)
	s.save_dir = _dir
	s.clock_override = CLOCK
	t.ok(s.cmd_save("hour")["ok"], "(setup) saved at %.0f s" % T0)
	var b0 := s.town_sim.bone
	var q0 := s.build_queue.size()
	while s.t < T0 + SPAN - 1e-6:
		fol._frames(1)
	var open := s.town_sim.bone - b0
	t.ok(open > 100.0 and s.town_sim.bone < s.town_sim.bone_cap() and s.build_queue.size() == q0,
		"(setup) open, the hour makes %.3f bone, under the cap, the queue as saved (%d)" % [open, s.build_queue.size()])
	for dt in BOUND:
		var c: Dictionary = cfg.duplicate(true)
		c["economy"]["idle"]["catchup_max_steps"] = SPAN / float(dt)
		var n := GameState.new(c)
		n.debug_enabled = true
		n.save_dir = _dir
		n.clock_override = CLOCK + int(SPAN)
		var r := n.cmd_load("hour", true)
		var nb0 := n.town_sim.bone
		while n._catchup.active:
			n._catchup.run(n, 1)
		var made := n.town_sim.bone - nb0
		t.ok(r["ok"] and absf(float(n._catchup.dt) - float(dt)) < 1e-9 and absf(n.t - (T0 + SPAN)) < 1e-6 and n.build_queue.size() == q0,
			"(setup) caught up at %.1f s steps to %.2f s, the queue as saved (%d)" % [float(n._catchup.dt), n.t, n.build_queue.size()])
		t.ok(absf(made - open) <= float(BOUND[dt]), "caught up at %.0f s the hour makes %.3f bone against %.3f open (%+.3f; bound ±%.1f, IDLE §8)" % [
			float(dt), made, open, made - open, float(BOUND[dt])])
	DirAccess.remove_absolute(_dir + "/hour.json")
	DirAccess.remove_absolute(_dir)
	print("  [haul_hour] %.1f s wall" % ((Time.get_ticks_msec() - u0) / 1000.0))
	return t.failures
