extends RefCounted
## The catch-up runner (IDLE §4, E2b-2 T3.3b; scripts/sim/catchup.gd): every load catches up the real time
## since its save, and a long gap in the open game does too, through GameState's own core step in adaptive,
## event-clipped steps, in chunks that never change the result.
## - A load with the clock (GameState.clock_override) N s on: t advances by N exactly, the ledger balances,
##   the catch-up's events are collected in time order inside its window and the scenes' queue gets none;
##   a negative elapsed time is 0 (the identity), one above idle.catchup_max_s is capped and flagged, a 0 s
##   load is the identity. A step never straddles a clip event (the runner's trace), Relish's arrival and
##   the tithe's moments are step boundaries, and a construction finishing and the queue's head starting on
##   funds land at their own time, against a 0.5 s live run. next_event_s's clauses one by one, and the dt
##   rule. F1: at a full store the head's time is affordable_in_s's (BuildRules.queue_net), not the clipped net.
## - The load flash: from a load until the first substep's train verdict, no frame shows a held fort safe
##   where the first settled read is thin; view_realm and the held forts' view_fort read the same just
##   before a save and just after its 0 s load.
## - Chunks: synchronous and in chunks of 1, 7 and the default give the same to_dict() and RNG; a chunked
##   catch-up's frames refresh no build-benefit row and run no train probe; the frame path sends a frame
##   above idle.gap_s of real time through catch-up (the same state as that time caught up on load), keeps a
##   20 s frame live and debug fast-forward live; a gap under idle.report_min_s queues its events (a retake
##   inside a 300 s gap reaches the queue), a longer one collects them; paused time is no time off.
## - Accuracy (IDLE §4): 2 h caught up against 2 h live at 0.5 s from midgame_2flips, within
##   idle.catchup_tol; seven held forts with WAR at 0, 20 min caught up at 10 s against live: 3 or more
##   retakes, each within the outcomes' time bound; a threshold-free start matches to 1e-9; I1, a scripted
##   session left 30 min, closed against open through the frame path; the same save and time away give the
##   same to_dict() twice.
## Saves go under user://test_catchup_<pid>, removed at the end. The field is shrunk (8 × 6) and its
## pre-warm off, as tests/slow/convergence.gd's harness does, so the runs are cheap; the field step wiring
## is the same at any size.

var t := TestUtil.new()
var _dir := "user://test_catchup_%d" % OS.get_process_id()
const CLOCK := 1_800_000_000  # a "now" for the saves (unix seconds)


func run() -> int:
	t.suite("catchup")
	DirAccess.make_dir_recursive_absolute(_dir)
	_away_basic()
	_away_edges()
	_dt_rule()
	_dt_schedule()
	_next_event_units()
	_no_straddle()
	_construction_on_time()
	_build_start_on_time()
	_build_start_at_cap()
	_lanes_and_field()
	_load_flash()
	_load_identity_views()
	_config_check()
	_chunks_equal()
	_frame_work_excluded()
	_gap_frame()
	_gap_cap()
	_live_frames()
	_gap_events()
	_accuracy_2h()
	_retakes_bound()
	_retakes_relish()
	_threshold_free()
	_i1()
	_i1_field()
	_determinism()
	_cleanup()
	return t.failures


# ------------------------------------------------------------------------------ helpers ----
## The shipped configs with the field shrunk and its pre-warm off (convergence.gd's harness), then
## `over` ({"file.section.key": value}).
static func cfgs(over := {}) -> Dictionary:
	var c := TestUtil.configs()
	var fld: Dictionary = c["realm"]["field"]
	fld["w"] = 8
	fld["h"] = 6
	c["economy"]["sim"]["prewarm_ticks"] = 0
	for path in over:
		var keys: PackedStringArray = str(path).split(".")
		var d: Dictionary = c
		for i in keys.size() - 1:
			d = d[keys[i]]
		d[keys[-1]] = over[path]
	return c


func _mk(c: Dictionary) -> GameState:
	var s := GameState.new(c)
	s.debug_enabled = true
	s.save_dir = _dir
	return s


## A start: a fixture loaded, or "day1" as cmd_new_game(1) a few substeps in (its rates set).
func _start(c: Dictionary, name: String) -> GameState:
	var s := _mk(c)
	if name == "new":
		s.cmd_new_game(1)
		s.tick(2.0)
	else:
		t.ok(s.cmd_debug_load_fixture(name)["ok"], "(setup) %s loads" % name)
	return s


## Saves `s` to `slot` at CLOCK; a fresh state loads it with the clock `away` s on. Returns the loaded
## state (its load's result in `meta.load`).
func _away(c: Dictionary, s: GameState, slot: String, away: int, chunked := false) -> GameState:
	s.clock_override = CLOCK
	t.ok(s.cmd_save(slot)["ok"], "(setup) %s saved" % slot)
	var n := _mk(c)
	n.clock_override = CLOCK + away
	var r := n.cmd_load(slot, chunked)
	n.set_meta("load", r)
	n.set_meta("saved", s.to_dict())  # what the save holds, as to_dict gives it (ints as ints)
	return n


func _ledger_err(s: GameState) -> float:
	return GameState.Ledger.error(s.ledger())


func _cleanup() -> void:
	var d := DirAccess.open(_dir)
	if d == null:
		return
	for f in d.get_files():
		d.remove(f)
	DirAccess.remove_absolute(_dir)


# --------------------------------------------------------------------------- the load ----
## midgame_2flips saved, then loaded 50 min later: the sim runs exactly those 3 000 s, the ledger balances,
## and the catch-up's events are collected (in time order, inside its window) instead of queued.
func _away_basic() -> void:
	var c := cfgs()
	var s := _start(c, "midgame_2flips")
	var t0 := s.t
	var n := _away(c, s, "basic", 3000)
	var r: Dictionary = n.get_meta("load")
	t.ok(r["ok"] and r["away_s"] == 3000.0 and r["capped"] == false, "the load catches up 3000 s: %s" % str(r))
	t.ok(n.t == t0 + 3000.0, "t advances by exactly the time away (%.6f → %.6f)" % [t0, n.t])
	t.ok(_ledger_err(n) < 1e-9, "the ledger balances after the catch-up (%s)" % String.num_scientific(_ledger_err(n)))
	var evs := n.catchup_events()
	var ordered := not evs.is_empty()
	var inside := true
	var last := -INF
	for e in evs:
		ordered = ordered and float(e["t"]) >= last
		last = float(e["t"])
		inside = inside and float(e["t"]) >= t0 - 1e-9 and float(e["t"]) <= t0 + 3000.0 + 1e-9
	t.ok(ordered and inside, "its %d events are in time order, inside [%.0f, %.0f]" % [evs.size(), t0, t0 + 3000.0])
	var kinds := {}
	for e in evs:
		kinds[e["type"]] = true
	t.ok(kinds.has("tithe_wave") and kinds.has("tithe_warning"), "the waves of the 50 min are among them: %s" % str(kinds.keys()))
	# (T3.3c: the scenes' queue gets the away report's away_report, which a report replaces them with)
	t.ok(n.drain_events().map(func(e): return e["type"]) == ["away_report"], "the scenes' queue gets none of them: only the report's away_report")
	var cu := n.view_catchup()
	t.ok(not cu["active"] and cu["done_s"] == 3000.0 and cu["total_s"] == 3000.0, "view_catchup: done, 3000 of 3000 s: %s" % str(cu))
	t.ok(n._catchup.steps > 0 and n._catchup.field_calls == n._catchup.field_n and n._catchup.field_n == int(c["economy"]["idle"]["field_steps"]),
		"%d core steps, %d field steps (of %d planned: idle.field_steps)" % [n._catchup.steps, n._catchup.field_calls, n._catchup.field_n])


## A clock behind the save is no time away (the identity); one more than idle.catchup_max_s on is capped
## there and flagged; a file without saved_at catches up nothing.
func _away_edges() -> void:
	var c := cfgs({"economy.idle.catchup_max_s": 600.0})
	var s := _start(c, "midgame_2flips")
	var t0 := s.t
	var back := _away(c, s, "edges", -500)
	var saved: Dictionary = back.get_meta("saved")
	var rb: Dictionary = back.get_meta("load")
	t.ok(rb["ok"] and rb["away_s"] == 0.0 and not rb["capped"] and back.t == t0 and back.to_dict() == saved,
		"the clock 500 s behind the save: nothing to catch up, the state is the save: %s" % str(rb))
	var far := _away(c, s, "edges", 1000)
	var rf: Dictionary = far.get_meta("load")
	t.ok(rf["ok"] and rf["away_s"] == 600.0 and rf["capped"] and far.t == t0 + 600.0,
		"1000 s away with the cap at 600 s: 600 s caught up, capped (%s, t +%.1f)" % [str(rf), far.t - t0])
	SaveIO.write_atomic(_dir + "/bare.json", JSON.stringify(saved))
	var nb := _mk(c)
	nb.clock_override = CLOCK + 900
	var rn := nb.cmd_load("bare")
	t.ok(rn["ok"] and rn["away_s"] == 0.0 and nb.t == t0, "a file without saved_at catches up nothing: %s" % str(rn))
	var zero := _away(c, s, "edges", 0)
	var rz: Dictionary = zero.get_meta("load")
	t.ok(rz["away_s"] == 0.0 and zero.to_dict() == saved and zero._catchup.steps == 0 and zero.rev == 1,
		"a load with 0 s away is the identity: no step, the state is the save (rev %d)" % zero.rev)


## dt = clamp(elapsed / idle.catchup_max_steps, sim.substep_s, idle.catchup_dt_max_s): 31 s steps at 0.5 s,
## 2 h at 2 h / 4320, 12 h and 7 d at 10 s; and a 2 h catch-up's longest step is that.
func _dt_rule() -> void:
	var c := cfgs()
	var s := _mk(c)
	s.cmd_new_game(1)
	var n := float(c["economy"]["idle"]["catchup_max_steps"])
	var mx := float(c["economy"]["idle"]["catchup_dt_max_s"])
	var cases := [[31.0, 0.5], [7200.0, 7200.0 / n], [43200.0, mx], [604800.0, mx]]
	for cs in cases:
		t.near(Catchup.base_dt(s, cs[0]), cs[1], 1e-12, "a catch-up of %.0f s steps at %.4f s" % [cs[0], cs[1]])
	var st := _start(c, "midgame_2flips")
	st.clock_override = CLOCK
	st.cmd_save("dt")
	var l := _mk(c)
	l.from_dict(SaveIO.read_file(_dir + "/dt.json"))
	l._catchup.begin(l, 7200.0, true)
	l._catchup.trace = []
	l._catchup.run(l)
	var longest := 0.0
	for e in l._catchup.trace:
		longest = maxf(longest, float(e[1]))
	t.near(longest, 7200.0 / n, 1e-9, "a 2 h catch-up's longest step is 2 h / %d" % int(n))


## The step past the first 12 h (the budget's lever 2, IDLE §4): up to idle.catchup_dt_max_s for the first
## idle.catchup_dt_long_after_s of a catch-up, up to idle.catchup_dt_long_s after. Scaled here
## (catchup_max_steps 100 and the switch at 600 s): a 3 600 s catch-up from midgame_2flips takes 10 s steps
## to 600 s and idle.catchup_dt_long_s steps after (15 s); a 7 d one's base steps are 10 s and that at the
## shipped configs.
func _dt_schedule() -> void:
	var c := cfgs({"economy.idle.catchup_max_steps": 100, "economy.idle.catchup_dt_long_after_s": 600.0})
	var long_s := float(c["economy"]["idle"]["catchup_dt_long_s"])
	var s := _start(c, "midgame_2flips")
	s.clock_override = CLOCK
	s.cmd_save("sched")
	var l := _mk(c)
	l.from_dict(SaveIO.read_file(_dir + "/sched.json"))
	var t0 := l.t
	l._catchup.begin(l, 3600.0, true)
	l._catchup.trace = []
	l._catchup.run(l)
	var before := 0.0
	var after := 0.0
	for e in l._catchup.trace:
		if float(e[0]) - t0 < 600.0 - 1e-9:
			before = maxf(before, float(e[1]))
		else:
			after = maxf(after, float(e[1]))
	t.ok(before == 10.0 and after == long_s and long_s > 10.0 and l.t == t0 + 3600.0, "steps up to %.1f s before 600 s, up to %.1f s after" % [before, after])
	var w := _mk(cfgs())
	w.cmd_new_game(1)
	w._catchup.begin(w, 604800.0, true)
	t.ok(w._catchup.dt == 10.0 and w._catchup.dt_long == long_s and w._catchup.long_after_s == 43200.0,
		"a week: %.0f s steps, %.0f s past %.0f s" % [w._catchup.dt, w._catchup.dt_long, w._catchup.long_after_s])


## next_event_s's clauses, each alone on a new game (Relish home, no tithe, nothing building or queued,
## gold and bone not falling): it is INF there, then each event's own projection.
func _next_event_units() -> void:
	var c := cfgs()
	var base := func() -> GameState:
		var s := _mk(c)
		s.cmd_new_game(1)
		s.town_sim.rates = TownSim._zero_rates()
		return s
	var s: GameState = base.call()
	t.ok(Catchup.next_event_s(s) == INF, "a new game: nothing pending (INF)")
	# Relish's arrival
	s.cmd_move_relish("old-sluice")
	var want := (s._dist_to("old-sluice") - GameState.ARRIVE_EPS) / s.travel_speed()
	t.near(Catchup.next_event_s(s), want, 1e-9, "Relish travelling: her arrival, %.3f s" % want)
	# an unpaid building's hold
	s = base.call()
	s.town_sim.buildings["lot-04"]["state"] = "unpaid"
	s.town_sim.buildings["lot-04"]["unpaid_s"] = 12.5
	t.near(Catchup.next_event_s(s), 12.5, 1e-12, "an unpaid building: its hold's end, 12.5 s")
	# a construction finishing
	s = base.call()
	t.ok(s.cmd_build("house", "lot-05")["ok"], "(setup) a house goes up")
	s.town_sim.restaff()
	var eta := float(s.town_sim.construction_left("lot-05")["eta_s"])
	t.ok(eta > 0.0, "(setup) it has builders (eta %.1f s)" % eta)
	s.town_sim.rates = TownSim._zero_rates()
	t.near(Catchup.next_event_s(s), eta, 1e-9, "a construction: its finish, %.2f s" % eta)
	# gold and bone reaching their floor
	for k in ["gold", "bone"]:
		s = base.call()
		s.town_sim.gold = 100.0
		s.town_sim.bone = 100.0
		s.town_sim.rates[k] = {"in": 0.5, "out": 2.5}
		t.near(Catchup.next_event_s(s), 50.0, 1e-12, "%s falling 2 /s from 100: its floor at 50 s" % k)
	# the queue's head starting on funds: the later of the currencies it lacks
	s = base.call()
	s.town_sim.gold = 10.0
	s.town_sim.bone = 4.0
	t.ok(s.cmd_queue_build("house", "lot-05")["ok"] and s.build_queue[0]["waited_on"] == "no_gold", "(setup) a house waits on gold")
	s.town_sim.rates["gold"] = {"in": 0.5, "out": 0.2}
	s.town_sim.rates["bone"] = {"in": 0.2, "out": 0.0}
	t.near(Catchup.next_event_s(s), maxf(30.0 / 0.3, 6.0 / 0.2), 1e-9, "a house short 30 gold at 0.3 /s and 6 bone at 0.2 /s: 100 s")
	s.town_sim.rates["bone"] = {"in": 0.0, "out": 0.1}
	t.near(Catchup.next_event_s(s), 40.0, 1e-9, "and with its bone falling it can't start on funds (bone's floor alone: 40 s)")
	# the tithe: the warning, a wave starting, a wave ending
	s = base.call()
	s.realm.start_tithe()
	var warn := float(c["realm"]["tithe"]["warning_s"])
	s.realm.tithe["next_s"] = warn + 33.0
	s.realm.tithe["warning"] = {}
	t.near(Catchup.next_event_s(s), 33.0, 1e-9, "the tithe: its warning 33 s on")
	s.realm.tithe["warning"] = {"wave_id": 1, "fort_id": "ashgate", "eta_s": 70.0, "surge": 1.0}
	s.realm.tithe["next_s"] = 70.0
	t.near(Catchup.next_event_s(s), 70.0, 1e-9, "warned: the wave's start 70 s on")
	s.realm.tithe["next_s"] = 400.0
	s.realm.tithe["warning"] = {}
	s.realm.tithe["wave"] = {"wave_id": 1, "fort_id": "ashgate", "s_left": 17.0, "duration_s": 40.0, "mult": 1.0, "delivered": 0.0}
	t.near(Catchup.next_event_s(s), 17.0, 1e-9, "a wave running: its end 17 s on")


## No step straddles a clip event: each step of a 1 h catch-up at 10 s steps (idle.catchup_max_steps 360)
## from midgame_2flips is at most the next event's time (the runner's trace), Relish's arrival at Greywall
## and every tithe warning and wave in it are step boundaries.
func _no_straddle() -> void:
	var c := cfgs({"economy.idle.catchup_max_steps": 360})
	var s := _start(c, "midgame_2flips")
	var arrive := s.t + (s._dist_to("greywall") - GameState.ARRIVE_EPS) / s.travel_speed()
	s.clock_override = CLOCK
	s.cmd_save("straddle")
	var l := _mk(c)
	l.from_dict(SaveIO.read_file(_dir + "/straddle.json"))
	l._catchup.begin(l, 3600.0, true)
	l._catchup.trace = []
	l._catchup.run(l)
	var ok := true
	var bounds := {}
	var bad := ""
	for e in l._catchup.trace:
		bounds[snappedf(float(e[0]), 1e-6)] = true
		bounds[snappedf(float(e[0]) + float(e[1]), 1e-6)] = true
		if float(e[2]) > Catchup.CLIP_MIN_S and float(e[1]) > float(e[2]) + 1e-9:
			ok = false
			bad = str(e)
	t.ok(ok and l._catchup.trace.size() > 360, "no step of %d is longer than the time to its next event%s" % [l._catchup.trace.size(),
		"" if ok else ": " + bad])
	t.ok(bounds.has(snappedf(arrive, 1e-6)), "Relish's arrival at Greywall (%.4f s) is a step boundary" % arrive)
	var tithe := 0
	var on := true
	for e in l.catchup_events():
		if e["type"] == "tithe_warning" or e["type"] == "tithe_wave":
			tithe += 1
			on = on and bounds.has(snappedf(float(e["t"]), 1e-6))
	t.ok(tithe > 4 and on, "every tithe warning and wave (%d) is at a step boundary" % tithe)


## A construction finishing inside a catch-up's 10 s step finishes at its own moment (the work left over
## its builders' rate, here 25.2 s in), not at the step's end, and within a substep of a 0.5 s live run's.
func _construction_on_time() -> void:
	var c := cfgs({"economy.idle.catchup_max_steps": 60})
	var s := _start(c, "new")
	t.ok(s.cmd_build("house", "lot-05")["ok"], "(setup) a house goes up")
	s.tick(0.5)
	s.town_sim.buildings["lot-05"]["progress"] = 0.37
	var eta := float(s.town_sim.construction_left("lot-05")["eta_s"])
	var at := s.t + eta
	t.ok(fmod(eta, 10.0) > 1.0 and fmod(eta, 10.0) < 9.0, "(setup) it finishes mid-step: %.2f s in" % eta)
	var live := _mk(c)
	live.from_dict(s.to_dict())
	live.drain_events()
	live.tick(ceilf(eta) + 1.0)
	var live_t := _event_t(live.drain_events(), "building_done", "lot-05")
	var n := _away(c, s, "build", 600)
	var cu_t := _event_t(n.catchup_events(), "building_done", "lot-05")
	t.near(cu_t, at, 1e-6, "in the catch-up the house is done at %.4f s, its own moment (%.4f)" % [cu_t, at])
	t.ok(live_t >= at - 1e-9 and live_t - at <= 0.5 + 1e-9, "the live 0.5 s run's at %.2f s, the substep after it" % live_t)


## The queue's head waiting on gold starts at the moment its shortfall is earned: in a 10 s-step catch-up
## within a substep of a 0.5 s live run's start, not at a step's end.
func _build_start_on_time() -> void:
	var c := cfgs({"economy.idle.catchup_max_steps": 60})
	var s := _start(c, "new")
	s.cmd_debug_grant({"gold": 11.0 - s.town_sim.gold})
	t.ok(s.cmd_queue_build("house", "lot-05")["ok"] and s.build_queue[0]["waited_on"] == "no_gold", "(setup) a house waits on gold")
	var live := _mk(c)
	live.from_dict(s.to_dict())
	live.drain_events()
	live.tick(600.0)
	var live_t := _event_t(live.drain_events(), "queue_started", "lot-05")
	var n := _away(c, s, "queue", 600)
	var cu_t := _event_t(n.catchup_events(), "queue_started", "lot-05")
	t.ok(live_t > s.t and fmod(live_t - s.t, 10.0) > 1.0 and fmod(live_t - s.t, 10.0) < 9.0,
		"(setup) it starts mid-step: live at +%.2f s" % (live_t - s.t))
	t.ok(cu_t > 0.0 and absf(cu_t - live_t) <= 0.5 + 1e-6,
		"the catch-up starts it at +%.3f s, within the live run's substep (+%.2f s)" % [cu_t - s.t, live_t - s.t])


## F1: at a full store the queue's head is timed with the net affordable_in_s uses (BuildRules.queue_net: the income
## before the cap's clip, less the upkeep), not the HUD's in − out, which the clip holds at 0 there. A config with a
## 100-gold cap (the Market adding none): day1 full, then a House, a Bakery and a Well queued, and one substep. Its
## TownSim step ends at the cap (the gold income clipped down to the upkeep), then the House and the Bakery start
## and spend the store, so the Well is the head on no_gold with the income back. build_start_s reads (30 − gold) /
## (trade − out), the Well's own affordable_in_s exactly; the clipped form's net is 0, so it read INF: no clip.
func _build_start_at_cap() -> void:
	var c := cfgs({"economy.gold.cap": 100.0, "buildings.market.effects.gold_cap": 0.0})
	var s := _mk(c)
	t.ok(s.cmd_debug_load_fixture("day1")["ok"], "(setup) day1 loads")
	s.town_sim.gold = 100.0
	s.tick(s.substep_s())
	for p in [["house", "lot-05"], ["bakery", "lot-06"], ["well", "lot-07"]]:
		t.ok(s.cmd_queue_build(p[0], p[1])["ok"], "(setup) %s queued on %s" % p)
	s.tick(s.substep_s())
	var g: Dictionary = s.town_sim.rates["gold"]
	var clipped := float(g["in"]) - float(g["out"])
	var net := float(g["trade"]) - float(g["out"])
	var rows: Array = s.view_town()["queue"]
	t.ok(rows.size() == 1 and rows[0]["building_id"] == "well" and s.build_queue[0]["waited_on"] == "no_gold" and float(g["overflow"]) > 0.0
		and absf(clipped) < 1e-12 and net > 0.0 and s.town_sim.gold < 30.0,
		"(setup) the House and the Bakery started from the full store: the Well waits on gold (%.3f), the step's income clipped (in − out %s/s; %.4f/s before the clip)" % [
		s.town_sim.gold, String.num_scientific(clipped), net])
	var want := (30.0 - s.town_sim.gold) / net
	var got := Catchup.build_start_s(s)
	t.ok(absf(got - want) <= 1e-9 * want and got == float(rows[0]["affordable_in_s"]),
		"build_start_s at a full store: %.3f s, (30 − %.3f) / %.4f, the Well's affordable_in_s (%.3f s) exactly; the HUD's clipped net would give %s" % [
		got, s.town_sim.gold, net, float(rows[0]["affordable_in_s"]), "INF" if not (clipped > 0.0) else String.num_scientific((30.0 - s.town_sim.gold) / clipped) + " s"])
	t.ok(Catchup.next_event_s(s) <= got, "next_event_s clips at it or sooner: %.3f s" % Catchup.next_event_s(s))


func _event_t(evs: Array, type: String, lot: String) -> float:
	for e in evs:
		if e["type"] == type and str(e.get("lot_id", "")) == lot:
			return float(e["t"])
	return -1.0


## The presentation step's parts at the catch-up's end: the lanes' baseline is the state now (the net
## change's callouts, once), the field accumulator is reset, and the field steps' count follows
## idle.field_step_min_s for a short catch-up.
func _lanes_and_field() -> void:
	var c := cfgs()
	var n := _away(c, _start(c, "midgame_2flips"), "lanes", 0)
	n._field_acc = 0.13
	var was: Dictionary = n._lane_prev.duplicate(true)
	n._catchup.begin(n, 120.0, true)
	n._catchup.run(n)
	t.ok(n._lane_prev == n._lane_state() and n._lane_prev != was, "the lanes' baseline is current after the catch-up (it moved: %s)" % str(n._lane_prev))
	t.ok(n._field_acc == 0.0, "the field accumulator is reset")
	t.ok(n._catchup.field_n == 60 and n._catchup.field_calls == 60, "120 s: 60 field steps of 2 s (idle.field_step_min_s), %d made" % n._catchup.field_calls)
	t.ok(not n.view_lanes()["lanes"].is_empty(), "the lanes read")


# ------------------------------------------------------------------------- the load flash ----
## From a load until the first substep's train verdict is in, on every frame of the frame path, no held
## fort's view_fort().margin reads safe where the first settled read (view_projection at the valve's
## target, with `settled`, and the train after the first substep) reads thin. midgame_2flips as loaded
## (Relish on her way to Greywall: her tide there thins Old Sluice), and a 0 s load of a real save of it
## a substep in.
func _load_flash() -> void:
	var c := cfgs()
	var fx := _start(c, "midgame_2flips")
	_flash_frames(fx, "midgame_2flips as loaded")
	var a := _start(c, "midgame_2flips")
	a.tick(a.substep_s())
	t.ok(a.relish["state"] == "travelling", "(setup) a substep in she is still on her way")
	var b := _away(c, a, "flash", 0)
	_flash_frames(b, "a 0 s load of a save a substep in")


func _flash_frames(s: GameState, what: String) -> void:
	var held: Array = []
	for f in s.realm.forts:
		if RealmSim.is_held(f):
			held.append(str(f["id"]))
	var settled: Dictionary = s.view_projection(s.valve_target, true)["margins"]
	var bad: Array = []
	var frames := 0
	var after_substep := false
	var thin := 0
	for id in held:
		if settled[id]["margin"] != "safe":
			thin += 1
	while frames < 200:
		for id in held:
			var m: String = s.view_fort(id)["margin"]
			if m == "safe" and settled[id]["margin"] != "safe":
				bad.append("frame %d %s safe (settled %s)" % [frames, id, settled[id]["margin"]])
		if after_substep:
			break
		frames += 1
		after_substep = s.tick(1.0 / 60.0, s.max_substeps_per_frame()) > 0
	var first: Dictionary = {}
	for id in held:
		first[id] = s.view_fort(id)["margin"]
		if first[id] == "safe" and settled[id]["margin"] != "safe":
			bad.append("after the first substep %s safe" % id)
	t.ok(thin > 0, "%s: (setup) a held fort reads thin in the first settled read: %s" % [what, str(settled)])
	t.ok(bad.is_empty() and frames > 1, "%s: over %d frames to the first substep no held fort reads safe where the settled read is thin%s" % [
		what, frames, "" if bad.is_empty() else ": " + ", ".join(PackedStringArray(bad))])


## view_realm() and every held fort's view_fort() just before cmd_save equal those right after its 0 s
## cmd_load, with no substep between (floats to the save's 15 digits): midgame_2flips as loaded, and a
## substep in (a real save, the last substep's dispatch rebuilt at the load).
func _load_identity_views() -> void:
	var c := cfgs()
	for k in [0, 1]:
		var s := _start(c, "midgame_2flips")
		if k == 1:
			s.tick(s.substep_s())
		var before := _flash_views(s)
		var n := _away(c, s, "views%d" % k, 0)
		var after := _flash_views(n)
		var why: Array = []
		_diff(before, after, 1e-9, "views", why)
		t.ok(why.is_empty(), "%s: view_realm and the held forts' view_fort read the same after the 0 s load%s" % [
			["as loaded", "a substep in"][k], "" if why.is_empty() else ": " + ", ".join(PackedStringArray(why.slice(0, 6)))])


func _flash_views(s: GameState) -> Dictionary:
	var out := {"realm": s.view_realm()}
	out["realm"].erase("rev")
	for f in s.realm.forts:
		if RealmSim.is_held(f):
			var v := s.view_fort(str(f["id"]))
			v.erase("rev")
			out[str(f["id"])] = v
	return out


## Every difference between `a` and `b` beyond `rel` (relative, for floats) into `why`.
static func _diff(a: Variant, b: Variant, rel: float, path: String, why: Array) -> void:
	if a is Dictionary and b is Dictionary:
		for k in a:
			if not b.has(k):
				why.append(path + "." + str(k) + " missing")
			else:
				_diff(a[k], b[k], rel, path + "." + str(k), why)
		for k in b:
			if not a.has(k):
				why.append(path + "." + str(k) + " extra")
	elif a is Array and b is Array:
		if a.size() != b.size():
			why.append("%s: size %d vs %d" % [path, a.size(), b.size()])
		else:
			for i in a.size():
				_diff(a[i], b[i], rel, "%s[%d]" % [path, i], why)
	elif (a is float or a is int) and (b is float or b is int):
		if absf(float(a) - float(b)) > rel * maxf(1.0, maxf(absf(float(a)), absf(float(b)))):
			why.append("%s: %s vs %s" % [path, str(a), str(b)])
	elif a != b:
		why.append("%s: %s vs %s" % [path, str(a), str(b)])


# ------------------------------------------------------------------------------- chunks ----
## The step sequence depends only on the save, the time away and the configs: the same save caught up
## synchronously and in chunks of 1, 7 and idle.catchup_steps_per_chunk (the views read between chunks,
## as a progress screen's would) gives the same to_dict() and RNG state, to the bit.
func _chunks_equal() -> void:
	var c := cfgs({"economy.idle.catchup_max_steps": 360})
	var s := _start(c, "midgame_2flips")
	var sync := _away(c, s, "chunks", 1800)
	var want := sync.to_dict()
	var per := int(c["economy"]["idle"]["catchup_steps_per_chunk"])
	for k in [1, 7, per]:
		var n := _away(c, s, "chunks", 1800, true)
		t.ok(n.get_meta("load")["ok"] and n.catching_up() and n.t == s.t, "chunked: the load returns with the catch-up pending (%d per chunk)" % k)
		var chunks := 0
		while n.catching_up():
			n._catchup.run(n, k)
			chunks += 1
			if chunks % 25 == 1:
				n.view_realm()
				n.view_fort("ashgate")
				n.view_town()
				n.view_hud()
				n.view_catalog()
				n.view_projection(n.valve_target, true)
		var got := n.to_dict()
		t.ok(got == want and n.rng.state == sync.rng.state and n.catchup_events() == sync.catchup_events(),
			"in %d chunks of %d: the same to_dict(), RNG state and events as synchronously" % [chunks, k])


## A chunked catch-up's frames do no frame work: no build-benefit row is refreshed and no train probe runs
## on them (StateViews.projection_frame and GameState._train_frame), with the catalog being read and a
## view reading the train between frames, late in the substep interval (where both would run). One core
## step per chunk (idle.catchup_steps_per_chunk 1), a 40 s gap of 0.5 s steps. The views' own reads may
## probe; the frames mustn't. Also: a view read after a chunk re-probes the train (its state moved).
func _frame_work_excluded() -> void:
	var c := cfgs({"economy.idle.catchup_steps_per_chunk": 1})
	var s := _start(c, "midgame_2flips")
	var cap := s.max_substeps_per_frame()
	s.tick(s.substep_s(), cap)
	s.view_catalog()
	s.view_fort("ashgate")
	t.ok(s.tick(40.0, cap) == 0 and s.catching_up(), "(setup) a 40 s frame starts a catch-up")
	var frames := 0
	var rows := 0
	var probes := 0
	var reprobe := true
	while s.catching_up() and frames < 200:
		s.view_catalog()
		var p0 := int(s._train_cache.get("computed", 0))
		s.view_fort("ashgate")
		reprobe = reprobe and int(s._train_cache.get("computed", 0)) == p0 + 1
		s._acc = 0.45  # late in the interval: where the frame refreshes run
		var r0 := int(s._proj_cache.get("rows_computed", 0))
		var c0 := int(s._train_cache.get("computed", 0))
		s.tick(1.0 / 60.0, cap)
		if s.catching_up():
			frames += 1
			rows += int(s._proj_cache.get("rows_computed", 0)) - r0
			probes += int(s._train_cache.get("computed", 0)) - c0
	t.ok(frames > 50 and rows == 0, "%d frames of the catch-up refresh no build-benefit row (%d)" % [frames, rows])
	t.ok(probes == 0, "and run no train probe (%d)" % probes)
	t.ok(reprobe, "a view read after each chunk re-probes the train")


## The frame path: a frame of 3 600 s of real time goes through catch-up and gives the same state as the
## same 3 600 s caught up on load: in one chunk, and in the default chunks over frames, whose own time
## then runs as live time (none of it dropped). Its fraction of a second stays in the accumulator.
func _gap_frame() -> void:
	var big := cfgs({"economy.idle.catchup_steps_per_chunk": 1_000_000})
	var s := _start(big, "midgame_2flips")
	var on_load := _away(big, s, "gap", 3600)
	var framed := _away(big, s, "gap", 0)
	var cap := framed.max_substeps_per_frame()
	t.ok(framed.tick(3600.0, cap) == 0 and not framed.catching_up(), "a 3600 s frame is caught up (in one chunk here)")
	# (T3.3c: each queues its report's away_report, and nothing else)
	var fq := framed.drain_events()
	var lq := on_load.drain_events()
	t.ok(framed.to_dict() == on_load.to_dict() and framed.catchup_events() == on_load.catchup_events()
		and fq.map(func(e): return e["type"]) == ["away_report"] and fq == lq and framed.view_away() == on_load.view_away().merged({"rev": framed.rev}, true),
		"the same state, events and report as 3600 s caught up on load")
	var c := cfgs()
	var a := _away(c, s, "gap2", 3600)
	var b := _away(c, s, "gap2", 0)
	t.ok(b.tick(3600.0, cap) == 0 and b.catching_up(), "with the default chunks it is still running after the frame")
	var frame_s := 0.0
	var frames := 0
	while b.catching_up() and frames < 1000:
		b.tick(1.0 / 60.0, cap)
		frame_s += 1.0 / 60.0
		frames += 1
	t.ok(not b.catching_up() and frames > 2, "(setup) done after %d more frames" % frames)
	a.tick(frame_s, 60)  # the frames' time, as one live frame (cap at idle.gap_s of substeps)
	var why: Array = []
	_diff(a.to_dict(), b.to_dict(), 0.0, "d", why)
	t.ok(why.is_empty() and a.t == b.t, "the frames' own %.2f s then ran live: the same state as the load's catch-up and %.2f s live%s" % [
		frame_s, frame_s, "" if why.is_empty() else ": " + ", ".join(PackedStringArray(why.slice(0, 4)))])
	var f := _away(c, s, "gap3", 0)
	var acc0 := f._acc
	f.tick(40.75, cap)
	t.ok(f._catchup.total_s == 40.0 and absf(f._acc - (acc0 + 0.75)) < 1e-12, "a 40.75 s frame catches up 40 s and keeps 0.75 s in the accumulator (%.3f → %.3f)" % [acc0, f._acc])


## A gap in the open game is capped at idle.catchup_max_s as a load is (IDLE §4): with the cap at 900 s
## and report_min_s 600, a frame of 900 + 3 600.5 s catches up exactly 900 s, drops the excess and its
## 0.5 s fraction (the accumulator is as it was), and its report says capped with away_s 900. A gap under
## the cap keeps its fraction and isn't capped.
func _gap_cap() -> void:
	var c := cfgs({"economy.idle.catchup_max_s": 900.0, "economy.idle.report_min_s": 600.0, "economy.idle.catchup_steps_per_chunk": 1_000_000})
	var s := _start(c, "midgame_2flips")
	var cap := s.max_substeps_per_frame()
	var f := _away(c, s, "gapcap", 0)
	var t0 := f.t
	var acc0 := f._acc
	f.tick(900.0 + 3600.5, cap)
	while f.catching_up():
		f.tick(1.0 / 60.0, cap)
	var a := f.view_away()
	t.ok(absf(f._catchup.total_s - 900.0) < 1e-9 and absf((f.t - t0) - 900.0) < 1e-6,
		"a 4 500.5 s frame with the cap at 900 s: game time advanced by exactly the cap (%.6f s)" % (f.t - t0))
	t.ok(a["shown"] and a["capped"] == true and a["away_s"] == 900.0, "its report says capped, away_s 900: %s" % str([a["shown"], a["capped"], a["away_s"]]))
	t.ok(absf(f._acc - acc0) < 1e-12, "no fraction of the dropped excess in the accumulator (%.6f → %.6f)" % [acc0, f._acc])
	var g := _away(c, s, "gapcap2", 0)
	var acc1 := g._acc
	var t1 := g.t
	g.tick(800.75, cap)
	while g.catching_up():
		g.tick(1.0 / 60.0, cap)
	var b := g.view_away()
	t.ok(b["shown"] and b["capped"] == false and b["away_s"] == 800.0 and absf((g.t - t1) - 800.0) < 1e-6 and absf(g._acc - (acc1 + 0.75)) < 1e-12,
		"control, an 800.75 s gap under the cap: 800 s, not capped, the 0.75 s fraction kept (%.3f → %.3f)" % [acc1, g._acc])


## What stays live: a 20 s frame (under idle.gap_s) runs its capped substeps and drops the rest, as
## before; debug fast-forward at ×60 (60 s of sim in a 1 s frame) is live play; an uncapped tick (tests,
## cmd_debug_skip_time) never routes a gap; a paused sim counts no time off.
func _live_frames() -> void:
	var c := cfgs()
	var s := _start(c, "midgame_2flips")
	var cap := s.max_substeps_per_frame()
	var t0 := s.t
	s._acc = 0.0
	t.ok(s.tick(20.0, cap) == cap and not s.catching_up() and s._acc == 0.0 and s.t == t0 + cap * s.substep_s(),
		"a 20 s frame: %d live substeps, the rest dropped" % cap)
	t.ok(s.cmd_debug_set_state({"time_scale": 60.0})["ok"], "(setup) ×60")
	t0 = s.t
	t.ok(s.tick(60.0, cap) == cap and not s.catching_up() and s.t == t0 + cap * s.substep_s(), "×60, a 1 s frame (60 s of sim): live, %d substeps" % cap)
	s.time_scale = 1.0
	t0 = s.t
	var n := s.tick(100.0)
	t.ok(n == 200 and not s.catching_up() and s.t == t0 + 100.0, "an uncapped tick of 100 s: 200 live substeps (%d)" % n)
	t.ok(s.cmd_pause(true)["ok"], "(setup) paused")
	t0 = s.t
	t.ok(s.tick(3600.0, cap) == 0 and not s.catching_up() and s.t == t0, "paused: a 3600 s frame is no time off")


## The events of a gap under idle.report_min_s go to the scenes' queue as live (no report replaces them):
## midgame_2flips 180 s before the 30 s window its first retake falls in (found live), so a fort is retaken
## within 300 s, and that fort_retaken reaches drain_events() from a 300 s frame. A 900 s frame collects it for
## the report instead, and queues none. (Before B1 (ii) the start was a fixed 20 min, when Old Sluice sat at 0
## under the most-undead rule; the lowest-margin rule moves which fort falls and when, so the setup finds it.)
func _gap_events() -> void:
	var c := cfgs()
	var s := _start(c, "midgame_2flips")
	var scan := _mk(c)
	scan.from_dict(s.to_dict())
	scan.drain_events()
	var first := -1.0
	while first < 0.0 and scan.t - s.t < 10800.0:
		scan.tick(30.0)
		if scan.drain_events().any(func(e): return e["type"] == "fort_retaken"):
			first = scan.t - s.t
	t.ok(first > 0.0, "(setup) live, midgame_2flips loses its first fort %.0f s in" % first)
	s.tick(maxf(0.0, first - 180.0))
	s.drain_events()
	var cap := s.max_substeps_per_frame()
	var live := _mk(c)
	live.from_dict(s.to_dict())
	live.drain_events()
	live.tick(300.0)
	var live_rt := live.drain_events().filter(func(e): return e["type"] == "fort_retaken")
	t.ok(live_rt.size() == 1, "(setup) live, a fort is retaken within 300 s: %s" % str(live_rt))
	for gap in [300.0, 900.0]:
		var n := _mk(c)
		n.from_dict(s.to_dict())
		n.drain_events()
		n.tick(gap, cap)
		var q: Array = []
		while n.catching_up():
			q.append_array(n.drain_events())
			n.tick(1.0 / 60.0, cap)
		q.append_array(n.drain_events())
		var rt_q := q.filter(func(e): return e["type"] == "fort_retaken")
		var rt_c := n.catchup_events().filter(func(e): return e["type"] == "fort_retaken")
		if gap < 600.0:
			t.ok(rt_q.size() == 1 and rt_c.is_empty() and q.size() > 1, "a %.0f s gap: its %d events reach the queue, the retake among them" % [gap, q.size()])
		else:
			t.ok(rt_q.is_empty() and rt_c.size() == 1 and n.catchup_events().size() > 1,
				"a %.0f s gap: its %d events are collected for the report (the retake among them), none queued (%d)" % [gap, n.catchup_events().size(), q.size()])


# ---------------------------------------------------------------------- accuracy and I1 ----
## IDLE §4's accuracy test, one start: a catch-up of `seconds` (a load with the clock that far on)
## against a live 0.5 s run of the same seconds with no input (tick, the presentation step included),
## both from the same save. Returns {ok, lines, ledger: [catch-up, live], stocks: {id: rel}, rates: {id:
## rel}, held: [catch-up, live], town_same, outcomes: [the lists that differ]}. Shared with the slow
## suite (12 h) and the I1 helper.
## With `window_s` > 0 (the slow suite's 12 h starts; E4, the A1 I1 fix's measurement correction) the rates the
## feed drives (WINDOWED: the mint reads the last step's burned / wanted, and its split and the workers' inflow
## follow it) are judged on their means over the next `window_s` live at 0.5 s in both runs, and their endpoint
## values are printed, not asserted. The feed saws with the convoy's loads (fresh's mint 9.4 to 12.8 a cycle), so
## one instant compares two phases: fresh at 12 h read 36.2% apart on a minted total 0.0015% apart and 600 s means
## 0.05% apart, and before the claim it passed at 12 h on its phase (0.84%) and read 36% apart 600 s later.
static func accuracy(c: Dictionary, js: String, seconds: float, tol: float, window_s := 0.0) -> Dictionary:
	var dir := "user://test_catchup_acc_%d" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(dir)
	var src := GameState.new(c)
	src.debug_enabled = true
	src.from_dict(JSON.parse_string(js))
	src.save_dir = dir
	src.clock_override = CLOCK
	src.cmd_save("acc")
	var cu := GameState.new(c)
	cu.debug_enabled = true
	cu.save_dir = dir
	cu.clock_override = CLOCK + int(seconds)
	cu.cmd_load("acc")
	var live := GameState.new(c)
	live.debug_enabled = true
	live.save_dir = dir
	live.clock_override = CLOCK
	live.cmd_load("acc")
	live.drain_events()
	live.tick(seconds)
	var cu_evs := cu.catchup_events()
	var live_evs := live.drain_events()
	var out := compare(cu, cu_evs, live, live_evs, tol, WINDOWED if window_s > 0.0 else [])
	out["grow_started"] = [grow_starts(cu_evs), grow_starts(live_evs)]  # (Phase I P3) caught up, live
	out["t0"] = src.t
	out["grow_bound_s"] = grow_bound_s(cu)
	if window_s > 0.0:
		var conv = load("res://tests/slow/convergence.gd")
		var ma := _window_means(cu, window_s)
		var mb := _window_means(live, window_s)
		var rfl := 0.01 * maxf(1.0, float(mb["mint"]))
		var w := 0.0
		var wparts: Array = []
		for k in WINDOWED:
			var e := absf(float(ma[k]) - float(mb[k])) / maxf(absf(float(mb[k])), rfl)
			w = maxf(w, e)
			wparts.append("%s %s" % [k, conv._pct(e)])
		out["window"] = {"s": window_s, "worst": w, "cycle_s": float(mb["_cycle_s"]), "swing": float(mb["_swing"]),
			"cycle_s_cu": float(ma["_cycle_s"])}
		out["worst"] = maxf(float(out["worst"]), w)
		out["ok"] = bool(out["ok"]) and w <= tol
		out["lines"] = str(out["lines"]) + "; %s over the next %.0f s live (asserted; the endpoint's are printed above): %s; the live mint's saw %s over the window, a cycle of %.1f s (caught up %.1f s)" % [
			"/".join(PackedStringArray(WINDOWED)), window_s, ", ".join(PackedStringArray(wparts)), conv._pct(float(mb["_swing"])),
			float(mb["_cycle_s"]), float(ma["_cycle_s"])]
	DirAccess.remove_absolute(dir + "/acc.json")
	DirAccess.remove_absolute(dir)
	return out


## The rates the pits' feed drives (accuracy()'s window).
const WINDOWED := ["mint", "war", "flood", "worker_in"]


## Phase I P3 (the run's manager's ruling 1 on handoff 4: Grow acts during catch-up, so the accuracy, I1, away and
## determinism checks run a Grow-on case): the Grow stance's starts in `evs`, in order, as [building_id, lot_id, level, t].
static func grow_starts(evs: Array) -> Array:
	var out: Array = []
	for e in evs:
		if e["type"] == "grow_started":
			out.append([str(e["building_id"]), str(e["lot_id"]), int(e["level"]), float(e["t"])])
	return out


## "" when `a`'s Grow starts (grow_starts; the caught-up or closed run's) are `b`'s (the live run's) upgrades in the same
## order, each started within max(`step_bound_s`, `tol` × its wait in `b`) of `b`'s, the wait counted from `b`'s previous
## start (from `t0`, the runs' start, for the first); else what differs. From the same stocks, catch-up starts one within
## a substep of live play (its clip at grow_start_s; test_grow's _catchup_on_time, with its revert proof). Over a long
## run two things move it: Grow arms at a stance beat, which catch-up reads at its step as every stance (IDLE §4: hold_s
## at least the longest step), so `step_bound_s` is compare()'s outcomes' bound (grow_bound_s; the I1 case's Market L2
## here: 8.5 s at 10 s steps); and the two runs' stocks drift apart within idle.catchup_tol, so the moment they cover a
## price drifts with them, by up to `tol` of the wait (pre_vei's pit L2 here: 4.7 s on a 2 434 s wait, its steps 1.7 s).
static func grow_same(a: Array, b: Array, tol: float, t0: float, step_bound_s: float) -> String:
	if a.size() != b.size():
		return "%d starts against %d" % [a.size(), b.size()]
	var prev := t0
	for i in a.size():
		if a[i].slice(0, 3) != b[i].slice(0, 3):
			return "start %d: %s against %s" % [i, str(a[i]), str(b[i])]
		var bound := maxf(step_bound_s, tol * (float(b[i][3]) - prev))
		if absf(float(a[i][3]) - float(b[i][3])) > bound:
			return "start %d (%s %s L%d) at %.3f against %.3f s, over %.2f s apart" % [i, a[i][0], a[i][1], a[i][2], a[i][3], b[i][3], bound]
		prev = float(b[i][3])
	return ""


## compare()'s outcomes' time bound for the caught-up run `cu`: convergence.gd's TIME_BOUND_STEPS × its longest step
## (its dt or dt_long).
static func grow_bound_s(cu: GameState) -> float:
	var conv = load("res://tests/slow/convergence.gd")
	return float(conv.TIME_BOUND_STEPS) * maxf(cu._catchup.dt, cu._catchup.dt_long)


## The worst |Δt| of two runs' matched Grow starts (grow_starts), for the report.
static func grow_worst_dt(a: Array, b: Array) -> float:
	var w := 0.0
	for i in mini(a.size(), b.size()):
		w = maxf(w, absf(float(a[i][3]) - float(b[i][3])))
	return w


## A save JSON (convergence.start_json's) with the Grow stance turned on: a fixture's save predates v14, so it loads with
## Grow off (§9.1), and a Grow-on case turns it on as a player would.
static func grow_on_json(js: String) -> String:
	var d: Dictionary = JSON.parse_string(js)
	if not (d["stances"]["on"] as Array).has("grow"):
		(d["stances"]["on"] as Array).append("grow")
	return JSON.stringify(d)


## pre_vei's gold net is negative (0.60 g/s of income against a 1.07 g/s bill: its one Market at L2 against City-tier
## upkeep, a fixture artifact), so Grow's upkeep test (the run's manager's ruling 1 on handoff 5; BuildRules.grow_target)
## passes over every pick there and Grow starts nothing until the town sheds. The pre_vei Grow-on cases run `c` with
## economy.json market.price doubled: 1.20 g/s of income, a net of +0.13 g/s, so Grow spends the stock on the living's
## levels as it did before the test. A copy; `c` is unchanged.
static func grow_price(c: Dictionary) -> Dictionary:
	var g: Dictionary = c.duplicate(true)
	g["economy"]["market"]["price"] = float(g["economy"]["market"]["price"]) * 2.0
	return g


## The Grow-on I1 script: the default I1's valve and House (whose finish arms Grow), the bone store filled to its cap
## so Grow has picks: the Market's L2 at once, then the House's levels on gold waits, on a smooth income. (A Bone Mill
## first, the shipped path, has picks too, but its convoy-fed mill saws bone_net 37.5% and the mint 16.8% at a 30 min
## endpoint, which the I1 compare reads unwindowed.)
static func grow_script(s: GameState) -> void:
	s.cmd_set_valve(0.5, 0.35, 0.15)
	s.cmd_build("house", "lot-05")
	s.cmd_debug_grant({"bone": s.town_sim.bone_cap() - s.town_sim.bone})


## Each WINDOWED rate's mean over `window_s` more of live play at 0.5 s.
static func _window_means(s: GameState, window_s: float) -> Dictionary:
	var sum := {}
	for k in WINDOWED:
		sum[k] = 0.0
	var n := maxi(1, int(round(window_s / 0.5)))
	var mint: Array[float] = []
	for i in n:
		s.tick(0.5)
		var r := _rates(s)
		mint.append(float(r["mint"]))
		for k in WINDOWED:
			sum[k] = float(sum[k]) + float(r[k])
	for k in WINDOWED:
		sum[k] = float(sum[k]) / n
	# the mint's saw over the window (E4 review item 4): `_cycle_s` the window over its upward crossings of the window's
	# mean (a crossing counts once it has been under the mean by a quarter of the swing, so substep jitter doesn't),
	# INF with none; `_swing` (max − min) ÷ the mean. A mean over the window is off by at most about swing × cycle ÷
	# window of the mean, so the window must hold many cycles
	var mu := float(sum["mint"])
	var lo := INF
	var hi := -INF
	for v in mint:
		lo = minf(lo, v)
		hi = maxf(hi, v)
	var band := 0.25 * (hi - lo)
	var ups := 0
	var armed := false
	for v in mint:
		if v < mu - band:
			armed = true
		elif armed and v >= mu:
			ups += 1
			armed = false
	sum["_cycle_s"] = window_s / ups if ups > 0 else INF
	sum["_swing"] = (hi - lo) / maxf(absf(mu), 1e-9)
	return sum


## Two runs of the same span compared (accuracy(), the I1 helper; also returns `late`, the time-bound misses,
## and `retaken`, each run's retake count): the ledger in each, Vei's and
## Covington's stocks (convergence.gd's KEY, each against max(|live|, its floor): 1% of the live value's
## scale, the body cap for bodies, Vei's pool cap for her pool), the key rates (the mint and its split,
## TownSim's worker inflow and the gold, bone and living nets, Vei's sustained differential: each against
## max(|live|, 1% of the mint)), the held forts (±1), Covington's buildings (id, level, state per lot) and
## the outcomes in order (convergence.gd's outcome lists), each flip and retake within the outcomes' time
## bound (convergence.gd's TIME_BOUND_STEPS) × `a`'s catch-up step at that moment: its `dt` for the first
## idle.catchup_dt_long_after_s, `dt_long` past it. `a` is the caught-up run. The rates in `printed_only` are
## reported but left out of `worst` and `ok` (accuracy()'s window judges them instead).
static func compare(a: GameState, a_evs: Array, b: GameState, b_evs: Array, tol: float, printed_only: Array = []) -> Dictionary:
	var conv = load("res://tests/slow/convergence.gd")
	var sa: Dictionary = conv.sample(a)
	var sb: Dictionary = conv.sample(b)
	var stocks := {}
	var worst := 0.0
	for m in conv.KEY:
		var fl := maxf(1.0, 0.01 * absf(float(sb[m])))
		if m == "vei_pool":
			fl = float(b._pool_cap())
		var e := absf(float(sa[m]) - float(sb[m])) / maxf(absf(float(sb[m])), fl)
		stocks[m] = e
		worst = maxf(worst, e)
	var ra := _rates(a)
	var rb := _rates(b)
	var rates := {}
	var rfl := 0.01 * maxf(1.0, float(rb["mint"]))
	for k in rb:
		var e := absf(float(ra[k]) - float(rb[k])) / maxf(absf(float(rb[k])), rfl)
		rates[k] = e
		if not printed_only.has(k):
			worst = maxf(worst, e)
	var held := [0, 0]
	for i in 2:
		for f in [a, b][i].realm.forts:
			if RealmSim.is_held(f):
				held[i] += 1
	var town_same := _town_of(a) == _town_of(b)
	var oa: Dictionary = conv._outcome()
	var ob: Dictionary = conv._outcome()
	conv._note(a_evs, oa, 0.0)
	conv._note(b_evs, ob, 0.0)
	for pair in [[a, oa], [b, ob]]:
		for f in pair[0].realm.forts:
			if RealmSim.is_held(f):
				pair[1]["held"].append(str(f["id"]))
			if float(f["living"]) > 1.0:
				pair[1]["garrisoned"].append(str(f["id"]))
		pair[1]["tier"] = pair[0].town_tier
	var cs: Catchup = a._catchup
	var step_at := func(t: float) -> float: return cs.dt_long if t - cs.t0 >= cs.long_after_s else cs.dt
	var differ: Array = conv.outcomes_differ(oa, ob, step_at)
	var la := GameState.Ledger.error(a.ledger())
	var lb := GameState.Ledger.error(b.ledger())
	var ok := worst <= tol and absi(held[0] - held[1]) <= 1 and town_same and differ.is_empty() and la < 1e-9 and lb < 1e-9
	var parts: Array = []
	for m in stocks:
		parts.append("%s %s" % [conv.SHORT[m], conv._pct(float(stocks[m]))])
	var rparts: Array = []
	for k in rates:
		rparts.append("%s %s" % [k, conv._pct(float(rates[k]))])
	var tparts: Array = []  # each flip's and retake's Δ against its bound, for the report
	for k in ["flips", "retaken"]:
		for i in mini((oa[k] as Array).size(), (ob[k] as Array).size()):
			if oa[k][i][0] == ob[k][i][0]:
				var ta := float(oa[k][i][1])
				tparts.append("%s %.1f s (bound %s × %s s)" % [oa[k][i][0], absf(ta - float(ob[k][i][1])), str(conv.TIME_BOUND_STEPS),
					str(maxf(float(step_at.call(ta)), float(step_at.call(float(ob[k][i][1])))))])
	var lines := "stocks: %s; rates: %s; held %d vs %d; Covington %s; outcomes %s (%d flips, %d waves, %d builds, %d retakes; flip and retake Δ: %s); ledger %s, %s" % [
		", ".join(PackedStringArray(parts)), ", ".join(PackedStringArray(rparts)), held[0], held[1],
		"identical" if town_same else "differs", "equal" if differ.is_empty() else "differ: " + ", ".join(PackedStringArray(differ)),
		(ob["flips"] as Array).size(), (ob["waves"] as Array).size(), (ob["builds"] as Array).size(), (ob["retaken"] as Array).size(),
		"none" if tparts.is_empty() else ", ".join(PackedStringArray(tparts)), String.num_scientific(la), String.num_scientific(lb)]
	return {"ok": ok, "lines": lines, "worst": worst, "stocks": stocks, "rates": rates, "held": held, "town_same": town_same,
		"outcomes": differ, "late": conv.outcome_times(oa, ob, step_at), "retaken": [(oa["retaken"] as Array).size(), (ob["retaken"] as Array).size()],
		"retaken_at": [oa["retaken"], ob["retaken"]]}


static func _rates(s: GameState) -> Dictionary:
	var r: Dictionary = s.town_sim.rates
	return {"mint": float(s._split["mint"]), "war": float(s._split["war"]), "flood": float(s._split["flood"]),
		"worker_in": float(r["workers"]["in"]) * s.worker_mass(),
		"gold_net": float(r["gold"]["in"]) - float(r["gold"]["out"]), "bone_net": float(r["bone"]["in"]) - float(r["bone"]["out"]),
		"living_net": float(r["living"]["in"]) - float(r["living"]["out"]), "diff_ema": float(s._readout["diff_ema"])}


static func _town_of(s: GameState) -> Dictionary:
	var out := {}
	for lot in s.town_sim.buildings:
		var b: Dictionary = s.town_sim.buildings[lot]
		out[lot] = [str(b["building_id"]), int(b["level"]), str(b["state"])]
	return out


## A catch-up of 2 h against a live 0.5 s run of it, from midgame_2flips (held forts, its waves and a
## retake in the window), at the shrunk field: about 8 s, most of it the live run's 14 400 substeps. The
## other starts are the slow suite's (tests/slow/catchup_accuracy.gd, 12 h): fresh needs 10 min of live
## play on the shipped field to build (another 12 s here), and pre_vei's gold reaches its floor about
## 2.14 h in, a threshold in reach of this window (T3.3a's attribution).
func _accuracy_2h() -> void:
	var c := cfgs()
	var conv = load("res://tests/slow/convergence.gd").new()
	var tol := float(c["economy"]["idle"]["catchup_tol"])
	for st in ["midgame_2flips"]:
		var js: String = conv.start_json(st)
		var r := accuracy(c, js, 7200.0, tol)
		print("  [catchup] %s, 2 h caught up vs live: %s" % [st, r["lines"]])
		t.ok(r["ok"], "%s: 2 h caught up against 2 h live at 0.5 s: within %s, held forts ±1, Covington identical, the same outcomes, both ledgers balanced: %s" % [
			st, conv._pct(tol), r["lines"]])
	# Phase I P3 (the run's manager's ruling 1 on handoff 4): a Grow-on case. pre_vei with Grow turned on (its save loads
	# with it off): 17 Grow starts at this tree (the mill's and the charnel's L2 at once, then the living's
	# levels and the Inn's and the pit's on waits), so the catch-up's clip at each pick's time (grow_start_s) is exercised;
	# each start within the outcomes' bound or tol of its wait (grow_same). pre_vei's feed saws (catchup_accuracy: 36.6% on an
	# 8.5 s cycle), so its mint and split are judged on their 600 s means, as there: unwindowed, its 2 h endpoint passed on its
	# phase and read the mint 44.9% apart with the Grow clip reverted, while every Grow start stayed within 1.3 s. The clip's
	# revert proof is the I1 case below (and test_grow's). At market.price ×2 (grow_price: pre_vei's own net is negative,
	# so Grow's upkeep test would hold every pick), over 7 000 s, not 2 h: with the doubled price Grow's last levels wait
	# on bone, and at 7 200 s the window ends 28 s after the second pit's L2 spent the bone store (305), where the stock,
	# 4 bone, reads that start's 1.3 s drift × 0.40 bone/s as 8% (0.32 bone). At 7 000 s the store is about 236 bone.
	var rg := accuracy(grow_price(c), grow_on_json(conv.start_json("pre_vei")), 7000.0, tol, 600.0)
	var gs2: Array = rg["grow_started"]
	var gd := grow_same(gs2[0], gs2[1], tol, float(rg["t0"]), float(rg["grow_bound_s"]))
	print("  [catchup] pre_vei with Grow on, 7 000 s caught up vs live: %s; Grow started %d caught up, %d live, the worst %.3f s apart" % [rg["lines"],
		(gs2[0] as Array).size(), (gs2[1] as Array).size(), grow_worst_dt(gs2[0], gs2[1])])
	t.ok(rg["ok"] and (gs2[1] as Array).size() >= 10 and gd == "",
		"pre_vei with Grow on: 7 000 s caught up against live within %s, the same outcomes, and the same %d Grow starts in order, each within the outcomes' bound or %s of its wait (%s): %s" % [
		conv._pct(tol), (gs2[1] as Array).size(), conv._pct(tol), gd if gd != "" else "the worst %.3f s" % grow_worst_dt(gs2[0], gs2[1]), rg["lines"]])


## The outcomes' time bound on several retakes (the run's manager: the slow suites only ever met Old Sluice's):
## midgame_2flips with five more forts held from now (no grace) on garrisons of 10 to 150 mass and the valve's
## WAR at 0, so Vei's reship takes them back one by one. 20 min caught up at 10 s steps (catchup_max_steps 120,
## the longest step) against live at 0.5 s: at least 3 retakes in both, the same in the same order, each within
## TIME_BOUND_STEPS × 10 s of live's, and the rest of compare() as the 2 h test has it. About 2 s.
func _retakes_bound() -> void:
	var c := cfgs({"economy.idle.catchup_max_steps": 120})
	var conv = load("res://tests/slow/convergence.gd").new()
	var s := _seven_held(c)
	# E4 step 5 (ruling A1): the muster joins the FLOOD now, so the WAR really is 0, and Relish (travelling to Greywall
	# in the fixture) would raise its corpses while its garrison drains: a catch-up step spreads her corpse-limited raise
	# over the step (Catchup.simulacrum_out_s's note), so caught up Greywall broke 32.5 s late (3.25 steps of 10 s; IDLE
	# §8). This test is Vei's reship's retakes, so she waits at home; with her there all 7 match within 0.24 s
	s._place_relish("covington")
	s._ledger.reset(GameState.Ledger.total(s._held()))  # the garrisons were set by hand
	var r := accuracy(c, JSON.stringify(s.to_dict()), 1200.0, float(c["economy"]["idle"]["catchup_tol"]))
	print("  [catchup] seven held forts, WAR 0, 20 min caught up at 10 s vs live: %s" % r["lines"])
	t.ok(int(r["retaken"][1]) >= 3 and r["retaken"][0] == r["retaken"][1] and (r["late"] as Array).is_empty() and r["ok"],
		"%d retakes live, %d caught up, each within %s × 10 s of live's (misses %s); the rest of compare() holds: %s" % [
		int(r["retaken"][1]), int(r["retaken"][0]), str(conv.TIME_BOUND_STEPS), str(r["late"]), r["lines"]])


## The seven-retakes start (_retakes_bound, _retakes_relish): midgame_2flips with five more forts held on hand-set
## garrisons and no living, every one past its grace, and the valve's WAR at 0, slewed.
func _seven_held(c: Dictionary) -> GameState:
	var conv = load("res://tests/slow/convergence.gd").new()
	var s := _mk(c)
	t.ok(s.from_dict(JSON.parse_string(conv.start_json("midgame_2flips")))["ok"], "(setup) midgame_2flips loads")
	var g := {"greywall": 10.0, "vespers": 20.0, "chime-fort": 60.0, "lantern-keep": 100.0, "hollow-redoubt": 150.0}
	for id in g:
		s.realm.hold(id, 0.0)
		s.realm.fort_by_id(id)["undead"] = g[id]
		s.realm.fort_by_id(id)["living"] = 0.0
	t.ok(s.cmd_set_valve(0.85, 0.0, 0.15)["ok"], "(setup) the valve's WAR at 0")
	s.valve = s.valve_target.duplicate()
	return s


## E4 review item 3: the open/closed gap _retakes_bound steps around (IDLE §8), kept under test. Relish is left as the
## fixture has her, travelling to Greywall, so she raises its corpses while its garrison drains. Live play raises each
## corpse at once; a 10 s catch-up step spreads her corpse-limited raise over the step (Catchup.simulacrum_out_s's
## note), so the caught-up Greywall breaks late. Asserted as the known bound: the same forts retaken, Greywall later
## than the 2-step bound but within 4 steps (3.25 recorded: 3 831.2 s against 3 798.7 s), every other fort within the
## bound. If the spread is ever fixed, the first half trips, and IDLE §8's record changes with it.
func _retakes_relish() -> void:
	var c := cfgs({"economy.idle.catchup_max_steps": 120})
	var s := _seven_held(c)
	t.ok(str(s.relish["target"]) == "greywall", "(setup) Relish is bound for Greywall: %s" % str(s.relish["target"]))
	s._ledger.reset(GameState.Ledger.total(s._held()))
	var r := accuracy(c, JSON.stringify(s.to_dict()), 1200.0, float(c["economy"]["idle"]["catchup_tol"]))
	print("  [catchup] seven held forts, WAR 0, Relish raising at Greywall, 20 min caught up at 10 s vs live: %s" % r["lines"])
	var at: Array = [{}, {}]  # each run's first retake per fort id (the list's "<id> (<cause>)"): caught up, live
	for k in 2:
		for e in r["retaken_at"][k]:
			var id := str(e[0]).get_slice(" ", 0)
			if not (at[k] as Dictionary).has(id):
				at[k][id] = float(e[1])
	var ids: Array = (at[1] as Dictionary).keys()
	ids.sort()
	var ids_cu: Array = (at[0] as Dictionary).keys()
	ids_cu.sort()
	var bound := 2.0 * 10.0  # convergence.TIME_BOUND_STEPS × the catch-up's 10 s step
	var gd := float(at[0].get("greywall", INF)) - float(at[1].get("greywall", -INF))
	var others: Array = []
	for id in ids:
		if id != "greywall" and at[0].has(id) and absf(float(at[0][id]) - float(at[1][id])) > bound:
			others.append("%s Δ %.1f s" % [id, float(at[0][id]) - float(at[1][id])])
	t.ok(ids.size() >= 3 and ids == ids_cu, "the same %d forts retaken both ways: %s against %s" % [ids.size(), str(ids_cu), str(ids)])
	t.ok(gd > bound and gd <= 2.0 * bound, "the known bound: caught-up Greywall breaks %.1f s late (over the %.0f s bound, within %.0f s)" % [
		gd, bound, 2.0 * bound])
	t.ok(others.is_empty(), "every other fort within %.0f s of live's (misses: %s)" % [bound, str(others)])


## A threshold-free start, where every step is in one smooth regime, so a catch-up's 10 s step equals
## twenty 0.5 s substeps: a new game with no workers (no staffing, no jobs, no rot, no convoy), the valve
## all FLOOD (no WAR: no fort fights), Vei's pool at its cap (she converts nothing, so her queue only
## grows), the living at their housing cap and gold well above upkeep and under its cap. The backlog grows
## by FLOOD, gold falls by the upkeep, the differential's EMA relaxes exactly, the field settles the same
## sources; no stock meets a floor or cap and no event happens. Caught up at 10 s steps against live:
## every number in to_dict() within 1e-9 relative, the village owners aside. Those are the field's
## (the presentation step's, MECHANICS §1.3), and catch-up's field steps don't replay the live field's
## cadence (live it ticks at most field.max_ticks_per_step a substep, so it runs behind 5 Hz); here they
## decide nothing (the living sit at their cap, so migrants change nothing). They are counted, not judged.
## 30 min (180 steps of 10 s against 3 600 substeps), for the default suite's time.
func _threshold_free() -> void:
	var c := cfgs({"economy.idle.catchup_max_steps": 180})
	var s := _mk(c)
	s.cmd_new_game(1)
	s.cmd_set_valve(0.0, 0.0, 1.0)
	s.valve = s.valve_target.duplicate()
	s.town_sim.workers = 0.0
	s.town_sim.living = s.town_sim.living_cap()
	s.town_sim.gold = 3000.0
	s.realm.vei["living_pool"] = s._pool_cap()
	s.town_sim.restaff()
	s._ledger.reset(GameState.Ledger.total(s._held()))
	s.tick(1.0)  # its rates set
	var js := JSON.stringify(s.to_dict())
	var a := _mk(c)
	a.from_dict(JSON.parse_string(js))
	a.clock_override = CLOCK
	a.cmd_save("free")
	var cu := _mk(c)
	cu.clock_override = CLOCK + 1800
	cu.cmd_load("free")
	var live := _mk(c)
	live.clock_override = CLOCK
	live.cmd_load("free")
	live.tick(1800.0)
	t.ok(cu._catchup.dt == 10.0, "(setup) the catch-up steps at 10 s")
	var da := cu.to_dict()
	var db := live.to_dict()
	var owners := 0
	for i in (db["villages"] as Array).size():
		owners += int(da["villages"][i]["owner"] != db["villages"][i]["owner"])
	da.erase("villages")
	db.erase("villages")
	var why: Array = []
	_diff(da, db, 1e-9, "d", why)
	t.ok(why.is_empty(), "a threshold-free start: 30 min caught up at 10 s equals 30 min live at 0.5 s within 1e-9 (backlog +%.1f, gold %.2f; %d of %d village owners differ, the field's)%s" % [
		float(db["realm"]["vei"]["undead_queue"]) - float(JSON.parse_string(js)["realm"]["vei"]["undead_queue"]), float(db["town"]["gold"]),
		owners, (live.to_dict()["villages"] as Array).size(), "" if why.is_empty() else ": " + ", ".join(PackedStringArray(why.slice(0, 8)))])


## I1 (IDLE §2): closed equals open. A scripted session's opening commands (`script`, called on a new game
## or a fixture), then the game left: open, ticked live through the frame path (frames of `frame_dt` s,
## the shell's substep cap) for `seconds`; closed, saved there and loaded `seconds` later. Returns
## compare()'s result. E3's autoplayer profiles extend this (their scripts and spans).
static func i1(c: Dictionary, start: String, script: Callable, seconds: float, frame_dt: float, tol: float) -> Dictionary:
	var dir := "user://test_catchup_i1_%d" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(dir)
	var s := GameState.new(c)
	s.debug_enabled = true
	s.save_dir = dir
	if start == "new":
		s.cmd_new_game(1)
	else:
		s.cmd_debug_load_fixture(start)
	script.call(s)
	s.clock_override = CLOCK
	s.cmd_save("i1")
	var closed := GameState.new(c)
	closed.debug_enabled = true
	closed.save_dir = dir
	closed.clock_override = CLOCK + int(seconds)
	closed.cmd_load("i1")
	var open := GameState.new(c)
	open.debug_enabled = true
	open.save_dir = dir
	open.clock_override = CLOCK
	open.cmd_load("i1")
	open.drain_events()
	var evs: Array = []
	var cap := open.max_substeps_per_frame()
	var n := int(round(seconds / frame_dt))
	for i in n:
		open.tick(frame_dt, cap)
		evs.append_array(open.drain_events())
	var out := compare(closed, closed.catchup_events(), open, evs, tol)
	out["grow_started"] = [grow_starts(closed.catchup_events()), grow_starts(evs)]  # (Phase I P3) closed, open
	out["t0"] = s.t
	out["grow_bound_s"] = grow_bound_s(closed)
	out["open_t"] = open.t
	out["closed_t"] = closed.t
	out["owners"] = [{}, {}]  # each run's village owners by id (closed, open)
	for i in 2:
		for v in [closed, open][i].to_dict()["villages"]:
			out["owners"][i][str(v["id"])] = str(v["owner"])
	DirAccess.remove_absolute(dir + "/i1.json")
	DirAccess.remove_absolute(dir)
	return out


## I1 in the default suite: a new game; the valve to 0.5 / 0.35 / 0.15, a House built and a Well queued
## (waiting on gold), then left 30 min; open through the frame path at 0.25 s frames against closed and
## loaded 30 min later. A 30 min catch-up would step at the live 0.5 s (under 36 min the step is
## sim.substep_s), so here it steps at 10 s (idle.catchup_max_steps 180), its longest; the slow suite runs
## the shipped schedule over 12 h.
func _i1() -> void:
	var c := cfgs({"economy.idle.catchup_max_steps": 180})
	var tol := float(c["economy"]["idle"]["catchup_tol"])
	var script := func(s: GameState) -> void:
		s.cmd_set_valve(0.5, 0.35, 0.15)
		s.cmd_build("house", "lot-05")
		s.cmd_queue_build("well", "lot-06")
	var r := i1(c, "new", script, 1800.0, 0.25, tol)
	print("  [catchup] I1, a new game's session left 30 min, closed vs open: %s" % r["lines"])
	t.ok(r["ok"] and float(r["open_t"]) == float(r["closed_t"]), "I1: closed for 30 min equals open for 30 min within %.0f%%, the same outcomes: %s" % [
		tol * 100.0, r["lines"]])
	# Phase I P3 (the run's manager's ruling 1 on handoff 4): a new game with Grow on by default (grow_script: the House's
	# finish arms it, the bone store full), left 30 min at 10 s steps: Grow's starts on gold waits inside it, each within
	# the outcomes' bound or tol of its wait (grow_same). Revert proof: Catchup.next_event_s without its grow_start_s clip,
	# 1 FAIL here (the House's L3 started 23 s after live's, at a step's end, over the 20 s bound)
	var cg := cfgs({"economy.idle.catchup_max_steps": 180, "economy.stance.grow.default_on": true})
	var rg := i1(cg, "new", grow_script, 1800.0, 0.25, tol)
	var gs2: Array = rg["grow_started"]
	var gd := grow_same(gs2[0], gs2[1], tol, float(rg["t0"]), float(rg["grow_bound_s"]))
	print("  [catchup] I1 with Grow on, 30 min closed vs open: %s; Grow started %s closed, %s open" % [rg["lines"], str(gs2[0]), str(gs2[1])])
	t.ok(rg["ok"] and float(rg["open_t"]) == float(rg["closed_t"]) and (gs2[1] as Array).size() >= 2 and gd == "",
		"I1 with Grow on: closed for 30 min equals open within %.0f%%, and the same %d Grow starts, each within the outcomes' bound or %s of its wait (%s): %s" % [
		tol * 100.0, (gs2[1] as Array).size(), "%.0f%%" % (tol * 100.0), gd if gd != "" else "the worst %.3f s" % grow_worst_dt(gs2[0], gs2[1]), rg["lines"]])


## I1's field (E4): a catch-up's village owners read the field as live play does, the step's in-flight
## injects on top (InfluenceField.overlay_in_flight). In this shrunk field Bellwether shares Covington's
## cell with an orange inject, so the contest wipes the step's bare result there: without the overlay a
## caught-up Bellwether read none for its first 80 s here (and, under A1's thinner WAR, the whole half-hour),
## while open play's read green from its first second (the I1 test's 61.5% town living under A1, Bellwether's
## migrants). A new game left 60 s, closed (30 field steps of 2 s) against open.
func _i1_field() -> void:
	var r := i1(cfgs(), "new", func(_s: GameState) -> void: pass, 60.0, 0.25, 1.0)
	var o: Array = r["owners"]
	t.ok(o[0] == o[1] and str(o[1].get("bellwether", "")) == "player",
		"I1's field: 60 s closed reads the village owners open play does, Bellwether (Covington's cell) held in both: closed %s, open %s" % [
		str(o[0]), str(o[1])])


## Determinism: the same save and time away give the identical to_dict() twice (and the same events).
## 1 h at 10 s steps.
func _determinism() -> void:
	var c := cfgs({"economy.idle.catchup_max_steps": 360})
	var s := _start(c, "midgame_2flips")
	var a := _away(c, s, "det", 3600)
	var b := _away(c, s, "det", 3600)
	t.ok(a.to_dict() == b.to_dict() and a.catchup_events() == b.catchup_events() and a.rng.state == b.rng.state,
		"the same save and 3600 s away: the same to_dict(), events and RNG twice")
	# Phase I P3 (the run's manager's ruling 1 on handoff 4): with Grow on, pre_vei (Grow turned on before the save), whose
	# hour away holds over a dozen Grow starts (at market.price ×2: grow_price)
	var cp := grow_price(c)
	var sg := _start(cp, "pre_vei")
	sg.cmd_set_stance("grow", true)
	var ga := _away(cp, sg, "detg", 3600)
	var gb := _away(cp, sg, "detg", 3600)
	var ng := grow_starts(ga.catchup_events()).size()
	t.ok(ga.to_dict() == gb.to_dict() and ga.catchup_events() == gb.catchup_events() and ga.rng.state == gb.rng.state and ng >= 5,
		"with Grow on: the same save and 3600 s away, %d Grow starts in it: the same to_dict(), events and RNG twice" % ng)


## IDLE §4: stance.hold_s must be at least catch-up's longest step in config, the larger of
## idle.catchup_dt_max_s and idle.catchup_dt_long_s (15 s shipped: the long step). E3-1 ships the key at 20 s,
## above the longest step, and it holds; at or above the longest step it holds; under it (BALANCE's
## old planned 10 s against the long step), setup() reports the problem as an error naming both keys. Both ways round
## (E2b-2 T3.3b2): with idle.catchup_dt_max_s overridden above idle.catchup_dt_long_s the check follows it, so
## it reads the config, not a fixed 15 s.
func _config_check() -> void:
	var c := TestUtil.configs()
	var idle: Dictionary = c["economy"]["idle"]
	var longest := maxf(float(idle["catchup_dt_max_s"]), float(idle["catchup_dt_long_s"]))
	t.ok(float(c["economy"]["stance"]["hold_s"]) >= longest and GameState.catchup_config_problem(c) == "",
		"the shipped configs: stance.hold_s %.0f s (E3-1) is at least the %.0f s longest step: it holds" % [float(c["economy"]["stance"]["hold_s"]), longest])
	c["economy"]["stance"]["hold_s"] = longest
	t.ok(GameState.catchup_config_problem(c) == "", "stance.hold_s %.0f s against a %.0f s longest step: it holds" % [longest, longest])
	c["economy"]["stance"]["hold_s"] = 10.0
	var p := GameState.catchup_config_problem(c)
	t.ok(p.find("stance.hold_s") >= 0 and p.find("catchup_dt_max_s") >= 0 and p.find("catchup_dt_long_s") >= 0,
		"stance.hold_s 10 s under a %.0f s step is a problem naming both step keys: %s" % [longest, p])
	# the other way round: idle.catchup_dt_max_s 20 s above idle.catchup_dt_long_s 15 s, so 20 s is the longest
	var o := TestUtil.configs()
	o["economy"]["idle"]["catchup_dt_max_s"] = 20.0
	o["economy"]["idle"]["catchup_dt_long_s"] = 15.0
	o["economy"]["stance"]["hold_s"] = 16.0
	var q := GameState.catchup_config_problem(o)
	t.ok(q.find("stance.hold_s") >= 0 and q.find("20") >= 0 and q.find("catchup_dt_max_s") >= 0 and q.find("catchup_dt_long_s") >= 0,
		"idle.catchup_dt_max_s 20 s over idle.catchup_dt_long_s 15 s: stance.hold_s 16 s is under the longest step: %s" % q)
	o["economy"]["stance"]["hold_s"] = 20.0
	t.ok(GameState.catchup_config_problem(o) == "", "... and stance.hold_s 20 s holds")
