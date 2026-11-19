extends RefCounted
## Ruling B4 (the run's manager, 2026-11-19; economy's Phase I close-out, flag (c)): the player's reads of the queue's
## times hold the Bone Mill's bone over its last live minute (BuildRules.shown_net, economy.json queue.shown_window_s)
## instead of its last 0.5 s step. A convoy-fed mill mills nothing in a step whose store stands empty between landings
## (the pits take bodies first), so the last step alone read "can't be afforded at today's bone income ... raise WAR"
## for a build a median hour off, in 662 of 1 200 live minutes of the batch's sessions profile (BALANCE §5, B4). "Never"
## now shows only when that mean, less the upkeep, is at or below 0. The core (head_dry and the hold), the catch-up's
## build_start_s (F1), Grow's pick and the bots keep the last step (queue_net, view_town().queue[].affordable_in_s_step),
## so the bots, the batch and the sim are bit-identical; moving those is Phase II. The manager's option (a) (2026-11-19):
## the catch-up's own steps feed the window too, so the away report reads the away's last minute. Headless, no
## autoloads. Economy's suite. Revert proofs (each alone): shown_net returning queue_net(gs); _tick not calling
## _note_mill; Catchup.run not calling it; from_dict not emptying the window; the walk's never_row line removed;
## shown_net without its producer_idle check; the away report's waiting line at queue_net (the counts are in BALANCE
## §5, ruling B4).

var t: TestUtil
var vcfg: Dictionary


func run() -> int:
	t = TestUtil.new()
	vcfg = TestUtil.configs()["town"]["view"]
	_gap()
	_window_rule()
	_never_row()
	_away_report()
	_producer_idle()
	_fallback()
	_reads()
	return t.failures


func _mk() -> GameState:
	var s := GameState.new(TestUtil.configs())
	s.cmd_new_game(1)
	s.debug_enabled = true
	return s


func _mill_staffed(s: GameState) -> bool:
	return float((s.town_sim.staffing["jobs"].get("mill", {}) as Dictionary).get("staffed", 0.0)) > 0.0


## A new game with a Raising Pit queued ahead of a Bone Mill (test_build_queue's _never_head start), ticked live until
## the Mill stands staffed and the Pit is the head waiting on bone: the convoy-fed mill the ruling is about.
func _waiting_pit() -> GameState:
	var s := _mk()
	s.tick(s.substep_s())
	s.town_sim.gold = 100.0
	s.town_sim.bone = 30.0
	t.ok(s.cmd_queue_build("raising_pit", "lot-05")["ok"] and s.cmd_queue_build("bone_mill", "lot-06")["ok"],
		"(setup) a Raising Pit (bone), then a Bone Mill")
	var ok := false
	for i in 2400:
		s.tick(s.substep_s())
		if _mill_staffed(s) and s.build_queue.size() == 1 and str(s.view_town()["queue"][0]["status"]) == "waiting_funds":
			ok = true
			break
	t.ok(ok, "(setup) the Mill stands staffed and the Pit waits on funds at t %.1f" % s.t)
	return s


## The head's time at a net, as _afford_at reads a lone head at clock 0: the longest (cost − stock) / net over the
## stores it is short of; −1.0 when a short store's net is ≤ NET_EPS.
func _time_at(s: GameState, row: Dictionary, net: Dictionary) -> float:
	var dt := 0.0
	for k in ["gold", "bone"]:
		var short := float(row["cost"][k]) - (s.town_sim.gold if k == "gold" else s.town_sim.bone)
		if short <= 0.0:
			continue
		if float(net[k]) <= BuildRules.NET_EPS:
			return -1.0
		dt = maxf(dt, short / float(net[k]))
	return dt


## Live play with the Pit waiting on bone: at every step the head's affordable_in_s is its time at shown_net and its
## affordable_in_s_step its time at queue_net, the last step's; in the convoy gaps (the step's bone net 0, the minute's
## above 0) the player's reads give a time where the step reads −1.0: no never text on the town row, no stall line on
## the map, no starved reason. "Never" shows only at a minute's net at or below 0.
func _gap() -> void:
	t.suite("shown_net-gap")
	var s := _waiting_pit()
	var steps := 0
	var gaps := 0  # the step reads never, the minute a time
	var never_shown := 0  # the minute's net <= 0: the player's read is never too
	var bad: Array = []
	for i in 2400:
		s.tick(s.substep_s())
		if s.build_queue.size() != 1 or not _mill_staffed(s):
			break
		var row: Dictionary = s.view_town()["queue"][0]
		if str(row["status"]) != "waiting_funds":
			break
		steps += 1
		var a := float(row["affordable_in_s"])
		var a_step := float(row["affordable_in_s_step"])
		var want := _time_at(s, row, BuildRules.shown_net(s))
		var want_step := _time_at(s, row, BuildRules.queue_net(s))
		if absf(a - want) > 1e-9 * maxf(1.0, absf(want)) or absf(a_step - want_step) > 1e-9 * maxf(1.0, absf(want_step)):
			bad.append([snappedf(s.t, 0.1), a, want, a_step, want_step])
		if a_step < 0.0 and a >= 0.0:
			gaps += 1
			var line: String = BuildSort.queue_etas([row], {"gold": s.town_sim.gold, "bone": s.town_sim.bone, "rates": {}}, {}, {}, -1.0, vcfg)[0]
			if str(row["starved"]) != "" or not HudLogic.stalled_head(row).is_empty() or line.begins_with("can't be afforded"):
				bad.append([snappedf(s.t, 0.1), "gap row reads never", row["starved"], line])
		if a < 0.0:
			never_shown += 1
			if float(BuildRules.shown_net(s)["bone"]) > BuildRules.NET_EPS:
				bad.append([snappedf(s.t, 0.1), "never at a minute's net above 0"])
	t.ok(steps > 100 and bad.is_empty(),
		"every step (%d) the head reads its time at the minute's net (affordable_in_s) and at the last step's (affordable_in_s_step)%s" % [
		steps, "" if bad.is_empty() else ": " + str(bad.slice(0, 4))])
	t.ok(gaps > 0,
		"the convoy gaps happen and read a time: %d steps whose last step reads never while the minute's net is above 0 (%d steps read never at the minute's net too)" % [
		gaps, never_shown])
	var m := s.mill_mean()
	var w := s._req_f("economy.queue.shown_window_s")
	t.ok(float(m["span"]) <= w + 1e-9 and float(m["span"]) >= w - s.substep_s() - 1e-9,
		"the window holds the newest %.0f s of live time (%.2f s)" % [w, float(m["span"])])


## The rule on a set window, at one state: a minute that milled nothing reads never with the town row's never text;
## one that milled 0.5 bone/s reads (short) / (0.5 − upkeep); the step's time is the same whatever the window holds.
func _window_rule() -> void:
	t.suite("shown_net-window")
	var s := _waiting_pit()
	s._mill_win = []
	var step0 := float(s.view_town()["queue"][0]["affordable_in_s_step"])
	var empty := float(s.view_town()["queue"][0]["affordable_in_s"])
	t.ok(empty == step0, "an empty window reads the last step: %.3f, %.3f" % [empty, step0])
	var w := s._req_f("economy.queue.shown_window_s")
	s._mill_win = [[w, 0.0]]
	var row: Dictionary = s.view_town()["queue"][0]
	var line: String = BuildSort.queue_etas([row], {"gold": s.town_sim.gold, "bone": s.town_sim.bone, "rates": {}}, {}, {}, -1.0, vcfg)[0]
	t.ok(float(row["affordable_in_s"]) == -1.0 and line.begins_with("can't be afforded at today's bone income")
		and float(row["affordable_in_s_step"]) == step0,
		"a minute that milled nothing: never, '%s'; the step's time unchanged (%.3f)" % [line, float(row["affordable_in_s_step"])])
	s._mill_win = [[w, 0.5 * w]]
	row = s.view_town()["queue"][0]
	var up := float(s.town_sim.rates["bone"]["out"])
	var short := float(row["cost"]["bone"]) - s.town_sim.bone
	var gshort := float(row["cost"]["gold"]) - s.town_sim.gold
	var want := short / (0.5 - up)
	t.ok(short > 0.0 and gshort <= 0.0 and absf(float(row["affordable_in_s"]) - want) <= 1e-9 * want and str(row["starved"]) == ""
		and float(row["affordable_in_s_step"]) == step0,
		"0.5 bone/s over the minute: %.3f s, (%.2f short) / (0.5 − %.2f upkeep), no starved reason; the step's time unchanged" % [
		float(row["affordable_in_s"]), short, up])


## A head the core skipped as never (head_never on the last step: here its hold run out with the mill staffed) reads
## never in the player's read too, whatever the minute milled: the queue has passed it, and its line is the never form.
func _never_row() -> void:
	t.suite("shown_net-never-row")
	var s := _waiting_pit()
	var dry := false
	for i in 2400:
		if float(BuildRules.queue_net(s)["bone"]) <= BuildRules.NET_EPS and _mill_staffed(s):
			dry = true
			break
		s.tick(s.substep_s())
	t.ok(dry, "(setup) a step whose bone net reads 0 with the mill staffed (t %.1f)" % s.t)
	var w := s._req_f("economy.queue.shown_window_s")
	var hold := s._req_f("economy.queue.never_hold_s")
	# (fixture) the clock a hold on, so the Pit's count can have started at a game time (held_out reads a negative
	# never_since as a count not started), then the count a second past the hold: the core's skip at this state
	s.t += hold + 1.0
	s.build_queue[0]["never_since"] = s.t - hold - 1.0
	s._mill_win = [[w, w]]  # 1 bone/s over the minute
	var row: Dictionary = s.view_town()["queue"][0]
	t.ok(BuildRules.never_row(row) and float(row["affordable_in_s"]) == -1.0 and float(row["affordable_in_s_step"]) == -1.0
		and float(BuildRules.shown_net(s)["bone"]) > 0.0,
		"held out: skipped on %s, −1.0 in both reads (%.1f, %.1f) though the minute milled 1 bone/s" % [
		str(row["reason"]), float(row["affordable_in_s"]), float(row["affordable_in_s_step"])])


## Option (a): the away report, built at a reporting catch-up's end, reads the window (the away's last minute, which
## the catch-up's steps fed): at a step that milled nothing, a minute at 0.5 bone/s gives the head's waiting line with a
## time, and an empty window (a load with no catch-up) the last step's never line.
func _away_report() -> void:
	t.suite("shown_net-away-report")
	var s := _waiting_pit()
	var dry := false
	for i in 2400:
		if float(BuildRules.queue_net(s)["bone"]) <= BuildRules.NET_EPS and _mill_staffed(s):
			dry = true
			break
		s.tick(s.substep_s())
	t.ok(dry and str(s.view_town()["queue"][0]["status"]) == "waiting_funds",
		"(setup) a step whose bone net reads 0 with the mill staffed and the Pit waiting (t %.1f)" % s.t)
	var w := s._req_f("economy.queue.shown_window_s")
	var b := StateViews.away_before(s)
	s._mill_win = [[w, 0.5 * w]]
	var lines := _queue_lines(StateViews.away_report(s, b, [], 700.0, false))
	t.ok(lines.size() == 1 and lines[0].contains(" is waiting on bone: affordable in ") and not lines[0].contains("can't be afforded"),
		"the away's last minute at 0.5 bone/s: the waiting line with a time (%s)" % str(lines))
	s._mill_win = []
	lines = _queue_lines(StateViews.away_report(s, b, [], 700.0, false))
	t.ok(lines.size() == 1 and lines[0].contains("can't be afforded"),
		"an empty window: the last step's never line (%s)" % str(lines))


func _queue_lines(rep: Dictionary) -> Array:
	var out: Array = []
	for ln in rep["ready"]:
		if str(ln["kind"]) == "queue":
			out.append(str(ln["text"]))
	return out


## With no staffed mill the minute's bone is the hands' that left: shown_net reads the last step's net.
func _producer_idle() -> void:
	t.suite("shown_net-producer-idle")
	var s := _mk()
	s.tick(s.substep_s())
	var w := s._req_f("economy.queue.shown_window_s")
	s._mill_win = [[w, w]]
	t.ok(BuildRules.producer_idle(s, "bone") and BuildRules.shown_net(s) == BuildRules.queue_net(s),
		"no staffed mill: shown_net is queue_net (bone %.3f/s) though the window holds 1 bone/s" % float(BuildRules.shown_net(s)["bone"]))


## The window is live time only and never saved: a load (from_dict) and a catch-up's begin (a gap) empty it, so the
## first read after either is the last step's; it isn't in the save.
func _fallback() -> void:
	t.suite("shown_net-fallback")
	var s := _waiting_pit()
	for i in 240:
		s.tick(s.substep_s())
	t.ok(float(s.mill_mean()["span"]) > 0.0, "(setup) live ticks fill the window (%.1f s)" % float(s.mill_mean()["span"]))
	var d := s.to_dict()
	t.ok(not JSON.stringify(d).contains("mill_win"), "the save has no window")
	t.ok(bool(s.from_dict(d)["ok"]) and float(s.mill_mean()["span"]) == 0.0, "a load empties it")
	var rows: Array = s.view_town()["queue"]
	var same := true
	for r in rows:
		same = same and float(r["affordable_in_s"]) == float(r["affordable_in_s_step"])
	t.ok(same and not rows.is_empty(), "after the load every row's two reads agree (%d rows)" % rows.size())
	for i in 240:
		s.tick(s.substep_s())
	t.ok(float(s.mill_mean()["span"]) > 0.0, "(setup) live ticks fill it again")
	# option (a) (the run's manager, 2026-11-19): a catch-up's own steps feed it, so the away report reads the away's
	# last minute. A marker no mill makes (100 bone/s) before the gap must be gone after it
	var w := s._req_f("economy.queue.shown_window_s")
	s._mill_win = [[w, 100.0 * w]]
	var gap := s._req_f("economy.idle.gap_s") * 4.0 + 60.0
	s.tick(gap, s.max_substeps_per_frame())
	var guard := 0
	while s.catching_up() and guard < 10000:
		s.tick(s.substep_s(), s.max_substeps_per_frame())
		guard += 1
	var m := s.mill_mean()
	t.ok(not s.catching_up() and float(m["span"]) >= w - 1e-9 and float(m["span"]) <= w + s.substep_s() + 1e-9
		and float(m["mill"]) < 100.0,
		"a gap (%.0f s) runs a catch-up whose own steps fill the window: after it %.1f s of it at %.3f bone/s (the marker's 100/s gone)" % [
		gap, float(m["span"]), float(m["mill"])])


## The reads that keep the last step, pinned by source: every bot read of a queue time is affordable_in_s_step; Grow's
## pick and head_dry (the core's hold) read queue_net; the catch-up never reads shown_net; the away report's waiting
## line reads it.
func _reads() -> void:
	t.suite("shown_net-reads")
	var bot := FileAccess.get_file_as_string("res://tests/autoplay/autoplayer.gd")
	t.ok(bot.count("[\"affordable_in_s\"]") == 0 and bot.count("[\"affordable_in_s_step\"]") >= 8,
		"the bots read only affordable_in_s_step (%d reads, %d of affordable_in_s)" % [bot.count("[\"affordable_in_s_step\"]"), bot.count("[\"affordable_in_s\"]")])
	var br := FileAccess.get_file_as_string("res://scripts/sim/build_rules.gd")
	for f in ["grow_target", "head_dry"]:
		var body := _body(br, "static func %s(" % f)
		t.ok(body.contains("queue_net(gs)") and not body.contains("shown_net"), "%s reads queue_net, the last step" % f)
	var cu := FileAccess.get_file_as_string("res://scripts/sim/catchup.gd")
	t.ok(not cu.contains("shown_net(") and cu.contains("BuildRules.queue_net(gs)"), "the catch-up reads queue_net only")
	var sv := FileAccess.get_file_as_string("res://scripts/sim/state_views.gd")
	t.ok(sv.contains("str(w[\"waits\"][i]), BuildRules.shown_net(gs), _move_down_helps(gs, i))"),
		"the away report's waiting line reads shown_net")


## A function's text: from `head` to the next top-level `func` or `static func`.
func _body(src: String, head: String) -> String:
	var a := src.find(head)
	if a < 0:
		return ""
	var b := len(src)
	for k in ["\nstatic func ", "\nfunc "]:
		var j := src.find(k, a + len(head))
		if j >= 0:
			b = mini(b, j)
	return src.substr(a, b - a)
