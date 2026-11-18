extends RefCounted
## The scene router's stale-result rule (RouterLogic) against a real GameState, the catching_up wait line,
## and source checks on main.gd / world_map.gd (they name autoloads and can't compile headless). No autoloads.


func run() -> int:
	var t := TestUtil.new()
	t.suite("map_router")
	MapLogic.configure(TestUtil.load_json("res://configs/map_view.json"))
	_stale(t)
	_wait_line(t)
	_catchup(t)
	_sources(t)
	return t.failures


func _catchup(t: TestUtil) -> void:
	t.suite("map_router-catchup")
	Palette.configure(TestUtil.load_json("res://configs/palette.json"))
	var c := RouterLogic.catchup_cfg()
	for k in ["layer", "plate_alpha", "fade_s", "title", "line_fmt", "line_px", "bar_w_px", "bar_h_px", "gap_px", "track_alpha", "fill_key", "demo_total_s", "demo_done_s"]:
		t.ok(c.has(k), "catchup.%s exists" % k)
	t.ok(int(c["layer"]) > int(TransitionLogic.cfg()["layer"]), "the screen's layer is above the transition's")
	t.ok(RouterLogic.catchup_fraction({"done_s": 5.0, "total_s": 20.0}) == 0.25, "fraction is done over total")
	t.ok(RouterLogic.catchup_fraction({"done_s": 0.0, "total_s": 0.0}) == 0.0, "a total of 0 reads 0")
	t.ok(RouterLogic.catchup_fraction({}) == 0.0, "an empty view reads 0")
	t.ok(RouterLogic.catchup_fraction({"done_s": 50.0, "total_s": 20.0}) == 1.0 and RouterLogic.catchup_fraction({"done_s": -5.0, "total_s": 20.0}) == 0.0, "the fraction clamps to 0..1")
	var line := RouterLogic.catchup_line({"done_s": 12000.0, "total_s": 32700.0})
	t.ok(line == "3h 20m of 9h 05m", "12000 s of 32700 s reads '%s'" % line)
	t.ok(RouterLogic.catchup_swallows(true) and not RouterLogic.catchup_swallows(false), "input is swallowed exactly while active")
	var fade := float(c["fade_s"])
	t.ok(RouterLogic.catchup_alpha(0.0, true, 0.016, fade, false) == 1.0, "active: full alpha at once")
	var a := RouterLogic.catchup_alpha(1.0, false, fade * 0.5, fade, false)
	t.ok(is_equal_approx(a, 0.5) and RouterLogic.catchup_shown(a), "inactive: the fade steps down and the plate is still shown")
	t.ok(not RouterLogic.catchup_shown(RouterLogic.catchup_alpha(a, false, fade, fade, false)), "inactive: hidden once the fade has run")
	t.ok(not RouterLogic.catchup_shown(RouterLogic.catchup_alpha(1.0, false, 0.0, fade, true)), "reduced motion: hidden at once")
	var words := [str(c["title"]), str(c["line_fmt"])]
	for w in words:
		t.ok(not w.to_lower().contains("the run") and not w.contains("_"), "'%s' has no 'the run'" % w)
	t.ok(str(c["title"]).contains("time away"), "the title says 'time away'")
	# the real overlay (it names no autoload): plate stops the mouse; inactive hides it
	var cu := MapCatchup.new()
	t.ok(not cu.visible, "the screen starts hidden")
	cu.update({"active": true, "done_s": 12000.0, "total_s": 32700.0}, 0.016, false)
	t.ok(cu.visible and cu.swallowing() and cu.plate_stops_mouse(), "active: shown, swallowing, the plate stops clicks")
	cu.update({"active": false, "done_s": 32700.0, "total_s": 32700.0}, 0.016, false)
	t.ok(cu.visible and not cu.swallowing(), "just ended: fading, no longer swallowing")
	t.ok(cu.visible and not cu.plate_stops_mouse(), "fading: still visible, the plate no longer stops clicks")
	cu.update({"active": true, "done_s": 1.0, "total_s": 2.0}, 0.016, false)
	t.ok(cu.visible and cu.swallowing() and cu.plate_stops_mouse(), "active again: the plate stops clicks")
	cu.update({"active": true, "done_s": 1.0, "total_s": 2.0}, 0.016, true)
	cu.update({"active": false, "done_s": 2.0, "total_s": 2.0}, 0.016, true)
	t.ok(not cu.visible, "reduced motion: hidden the frame it ends")
	cu.free()


func _at_fort_with_run() -> Dictionary:
	var s := GameState.new(TestUtil.configs())
	s.debug_enabled = true
	s.cmd_debug_load_fixture("day1")
	s.cmd_move_relish("old-sluice")
	for i in 40:
		s.tick(0.5)
		if str(s.view_relish()["state"]) == "at_fort":
			break
	var b := s.cmd_begin_dungeon("old-sluice")
	return {"s": s, "begun": b}


func _stale(t: TestUtil) -> void:
	t.suite("map_router-stale")
	var p := _at_fort_with_run()
	var s: GameState = p["s"]
	t.ok(p["begun"]["ok"], "a raid run is open at old-sluice (%s)" % str(p["begun"].get("reason", "")))
	var rid := int(p["begun"]["run_id"])
	t.ok(int(s.view_relish()["run_id"]) == rid and not RouterLogic.result_stale("raid", s.view_relish()), "(i) the run is open: a raid result is not stale")
	t.ok(not RouterLogic.result_stale("boss", s.view_relish()), "(iii) a boss result is never stale by this rule (open run)")
	# a VALID raid result for the open run, built before the gap (a bare stand-in fails Results.validate first)
	var valid := StateRuns.end_result(s.run, StateRuns.empty_loot(), "retreated")
	t.ok(Results.validate("raid", valid).is_empty(), "the stand-in built before the gap passes Results.validate")
	# a gap above idle.gap_s ends the run inside its frame (IDLE I5)
	var gap := float(TestUtil.configs()["economy"]["idle"]["gap_s"]) * 4.0
	s.tick(gap, s.max_substeps_per_frame())
	t.ok(s.catching_up(), "the gap's catch-up is under way")
	var rv := s.view_relish()
	t.ok(int(rv["run_id"]) == -1 and s.run.is_empty(), "catching_up with the run already ended: run_id is -1, so _apply can't abort an open run on it")
	t.ok(RouterLogic.result_stale("raid", rv), "(ii) after the gap the raid's result is stale")
	t.ok(not RouterLogic.result_stale("boss", rv), "(iii) a boss result is not stale by this rule even with no run")
	t.ok(RouterLogic.result_stale("raid", {}), "no run_id at all reads as -1: stale")
	var refused := s.apply_result("raid", {"v": 2, "run_id": rid})
	t.ok(not refused["ok"], "a raid result for the ended run is refused by apply_result (%s; the result here is a bare stand-in), so the router must not call it" % str(refused.get("reason", "")))
	var refused_valid := s.apply_result("raid", valid)
	t.ok(not refused_valid["ok"] and ["wrong_run", "duplicate_run"].has(str(refused_valid.get("reason", ""))), "a VALID raid result for the ended run is refused as wrong_run or duplicate_run (%s)" % str(refused_valid.get("reason", "")))
	var frames := 0
	while s.catching_up() and frames < 5000:
		s.tick(1.0 / 60.0, s.max_substeps_per_frame())
		frames += 1
	t.ok(not s.catching_up() and RouterLogic.result_stale("raid", s.view_relish()), "once the catch-up is done the run is still gone")


func _wait_line(t: TestUtil) -> void:
	t.suite("map_router-wait")
	var line := RelishLogic.reason_text("catching_up")
	var ctl: Dictionary = MapLogic.cfg()["controls"]
	t.ok(line == str(ctl["reasons"]["catching_up"]) and line != str(ctl["reason_fallback"]) % "catching_up", "catching_up has its own line (%s)" % line)
	t.ok(line.length() <= 60 and line.contains("catching up") and line.contains("Try again"), "it is short and says to try again")
	t.ok(not line.contains("_"), "no raw reason code")
	# every refusal path emits a plain toast (one neutral label): no caller styles a refusal
	for f in ["map_sidebar", "map_relish_chip", "map_valve", "map_tithe_explain"]:
		var src := FileAccess.get_file_as_string("res://scripts/map/%s.gd" % f)
		var bad := false
		for ln in src.split("\n"):
			if ln.contains("reason_text") and (ln.contains("danger") or ln.contains("modulate") or ln.contains("font_color") or ln.contains("Palette.c(")):
				bad = true
		t.ok(src.contains("RelishLogic.reason_text(") and not bad, "%s shows a refusal through toast.emit(reason_text), unstyled" % f)
	var hud := FileAccess.get_file_as_string("res://scripts/map/map_hud.gd")
	var show := _body(hud, "func show_toast(")
	t.ok(show != "" and not show.contains("danger") and not show.contains("font_color") and not show.contains("add_theme_color"), "show_toast has one neutral style (no error colour)")


func _body(src: String, sig: String) -> String:
	var i := src.find(sig)
	if i < 0:
		return ""
	var j := src.find("\nfunc ", i + 1)
	return src.substr(i, (j if j >= 0 else src.length()) - i)


func _sources(t: TestUtil) -> void:
	t.suite("map_router-source")
	var src := FileAccess.get_file_as_string("res://scripts/main.gd")
	var ap := _body(src, "func _apply(")
	t.ok(ap.contains("RouterLogic.result_stale(kind, s.view_relish())"), "_apply asks RouterLogic.result_stale")
	t.ok(ap.find("result_stale(") >= 0 and ap.find("result_stale(") < ap.find("apply_result("), "the stale check comes before apply_result")
	var stale_branch := ap.substr(ap.find("result_stale("), ap.find("apply_result(") - ap.find("result_stale("))
	t.ok(stale_branch.contains("_open_map(arrive_from)") and stale_branch.contains("return") and not stale_branch.contains("push_warning") and not stale_branch.contains("cmd_abort_dungeon"), "a stale result opens the map and returns: no warning, no abort")
	var after := ap.substr(ap.find("apply_result("))
	t.ok(after.contains("push_warning") and after.contains("cmd_abort_dungeon") and after.count("push_warning") == 1 and after.count("cmd_abort_dungeon") == 1, "push_warning and cmd_abort_dungeon remain only for a non-stale refusal")
	var tp := _body(src, "func _teleport(")
	t.ok(tp.count("RelishLogic.reason_text(str(r[\"reason\"]))") == 2 and not tp.contains("_open_map()"), "_teleport shows the reason on both refusals (boss, dungeon): no silent reopen")
	t.ok(_body(src, "func _open_map(").contains("args[\"toast\"]"), "_open_map passes the line to the map")
	t.ok(src.contains("Game.state.view_catchup()") and src.contains("_catchup.update(view, dt, Pulse.reduced_motion)"), "main.gd feeds the catch-up screen view_catchup() and reduced motion")
	t.ok(src.contains("--catchup=demo") and src.contains("Game.state.debug_enabled"), "--catchup=demo is debug-gated")
	t.ok(_body(src, "func _mount(").contains("move_child(_catchup, -1)"), "_mount keeps the screen last so its _input hears events first")
	var cus := FileAccess.get_file_as_string("res://scripts/map/map_catchup.gd")
	t.ok(cus.contains("_plate.mouse_filter = Control.MOUSE_FILTER_STOP") and _body(cus, "func _input(").contains("set_input_as_handled()"), "the plate stops the mouse and _input swallows the rest while active")
	var wm := FileAccess.get_file_as_string("res://scripts/map/world_map.gd")
	t.ok(wm.contains("args.get(\"toast\"") and wm.contains("hud.show_toast(_arrive_toast)"), "the map shows it on the HUD's existing toast")
