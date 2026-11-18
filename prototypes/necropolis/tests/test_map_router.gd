extends RefCounted
## The scene router's stale-result rule (RouterLogic) against a real GameState, the catching_up wait line,
## and source checks on main.gd / world_map.gd (they name autoloads and can't compile headless). No autoloads.


func run() -> int:
	var t := TestUtil.new()
	t.suite("map_router")
	MapLogic.configure(TestUtil.load_json("res://configs/map_view.json"))
	_stale(t)
	_wait_line(t)
	_sources(t)
	return t.failures


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
	var wm := FileAccess.get_file_as_string("res://scripts/map/world_map.gd")
	t.ok(wm.contains("args.get(\"toast\"") and wm.contains("hud.show_toast(_arrive_toast)"), "the map shows it on the HUD's existing toast")
