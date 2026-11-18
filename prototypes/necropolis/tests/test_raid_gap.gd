extends RefCounted
## The raid survives the game ending its run underneath it (milestone 2 H-a, C-c): a gap above idle.gap_s ends the open
## run in the state (run_ended, cause gap; then an away_report), a checkpoint refused with catching_up is kept and
## resent, and the two small follow-ups from the clarity review. The decisions are RaidLogic's statics; the scene
## wiring (raid.gd, raid_endings.gd, raid_dev.gd) cannot load headless, so it is checked by source text.


func run() -> int:
	var t := TestUtil.new()
	_end_tests(t)
	_retry_tests(t)
	_reread_tests(t)
	_wrap_tests(t)
	_wiring_tests(t)
	return t.failures


func _src(path: String) -> String:
	return FileAccess.get_file_as_string(path)


func _func_src(src: String, head: String) -> String:
	var i := src.find(head)
	if i < 0:
		return ""
	var j := src.find("\nfunc ", i + 10)
	return src.substr(i, (j if j >= 0 else src.length()) - i)


func _end_tests(t: TestUtil) -> void:
	t.suite("raid_gap_end")
	var ended := {"type": "run_ended", "run_id": 7, "kind": "raid", "outcome": "retreated", "cause": "gap"}
	t.ok(RaidLogic.gap_ends_run(ended, 7, 7), "a run_ended with our run id ends the raid")
	t.ok(not RaidLogic.gap_ends_run(ended, 8, 8), "a run_ended for another run does not")
	t.ok(not RaidLogic.gap_ends_run({"type": "run_ended", "kind": "raid"}, 0, 0), "a run_ended with no id never matches (-1)")
	var away := {"type": "away_report", "away_s": 3600.0, "capped": false}
	t.ok(RaidLogic.gap_ends_run(away, 7, -1), "an away_report with no run open ends the raid (the backstop)")
	t.ok(RaidLogic.gap_ends_run(away, 7, 9), "an away_report with another run open ends it too")
	t.ok(not RaidLogic.gap_ends_run(away, 7, 7), "an away_report with our run still open does not")
	t.ok(not RaidLogic.gap_ends_run({"type": "loot_banked", "run_id": 7}, 7, 7), "other events never end it")
	t.ok(not RaidLogic.gap_ends_run({}, 7, -1), "an empty event never ends it")
	t.ok(RaidLogic.gap_outcome(ended) == "retreated", "the outcome is the event's")
	t.ok(RaidLogic.gap_outcome({"type": "run_ended", "outcome": "relish_died"}) == "relish_died", "a death the state recorded stays a death")
	t.ok(RaidLogic.gap_outcome({"type": "run_ended", "outcome": "warden_beaten"}) == "warden_beaten", "a win the state recorded stays a win")
	t.ok(RaidLogic.gap_outcome(away) == "retreated" and RaidLogic.gap_outcome({"type": "run_ended", "outcome": "junk"}) == "retreated",
		"no outcome, or an unknown one, reads as a retreat")
	t.ok(RaidLogic.close_plan(true, "relish_died")["exit"] == "relish_died" and RaidLogic.close_plan(true, "retreated")["closing"],
		"the gap's result plan is close_plan's: a retreat pays the last checkpoint, an ending stands")
	t.ok(RaidLogic.gap_outcome(away, "relish_died") == "relish_died" and RaidLogic.gap_outcome(away, "warden_beaten") == "warden_beaten"
		and RaidLogic.gap_outcome(away, "") == "retreated", "an away_report's outcome follows the checkpoint rule (pending_exit)")
	t.ok(RaidLogic.gap_outcome(ended, "relish_died") == "retreated", "a run_ended keeps the event's own outcome")
	t.ok(RaidLogic.gap_leaves_beat(true, "relish_died") and RaidLogic.gap_leaves_beat(true, "warden_beaten"),
		"a gap in a running death or victory beat leaves the beat alone")
	t.ok(not RaidLogic.gap_leaves_beat(false, "") and not RaidLogic.gap_leaves_beat(true, "") and not RaidLogic.gap_leaves_beat(false, "relish_died"),
		"no beat under way: the AWAY TOO LONG stop runs")
	var gcfg: Dictionary = TestUtil.load_json("res://configs/raid.json").get("gap_end", {})
	var b := RaidLogic.gap_banner(gcfg)
	t.ok(b.begins_with("AWAY TOO LONG") and b.contains("last checkpoint"), "the raid's banner (raid.json gap_end.banner_text) says it in the glossary's words: " + b)
	var bb := RaidLogic.gap_banner(gcfg, true)
	t.ok(bb.begins_with("AWAY TOO LONG") and bb.contains("Vei") and not bb.to_lower().contains("raid") and not bb.to_lower().contains("checkpoint"),
		"the Vei fight's banner (gap_end.banner_text_boss) names the fight, not a raid or a checkpoint: " + bb)
	t.ok(RaidLogic.gap_banner({}) == "" and RaidLogic.gap_banner({"banner_text": "x"}, true) == "", "no words in the block, no banner (the words live in raid.json)")


func _retry_tests(t: TestUtil) -> void:
	t.suite("raid_gap_checkpoint_retry")
	var p1 := {"run_id": 3, "loot": RaidLogic.empty_loot(), "outcome": "retreated"}
	var p2 := {"run_id": 3, "loot": RaidLogic.empty_loot(), "outcome": "warden_beaten"}
	var refused := {"ok": false, "reason": "catching_up"}
	t.ok(RaidLogic.checkpoint_pending_after(p1, refused) == p1, "a catching_up refusal keeps the payload pending")
	t.ok(RaidLogic.checkpoint_pending_after(p1, {"ok": true}).is_empty(), "an ok clears it")
	t.ok(RaidLogic.checkpoint_pending_after(p1, {"ok": false, "reason": "no_run"}).is_empty(), "any other refusal drops it (it would never pass)")
	t.ok(RaidLogic.checkpoint_pending_after(p1, {}).is_empty(), "no result is not a refusal")
	# a newer payload replaces a pending one, whether it is refused again or accepted
	var pending := RaidLogic.checkpoint_pending_after(p1, refused)
	pending = RaidLogic.checkpoint_pending_after(p2, refused)
	t.ok(pending == p2, "a newer refused payload replaces the pending one")
	pending = RaidLogic.checkpoint_pending_after(p1, {"ok": true})
	t.ok(pending.is_empty(), "a newer accepted payload leaves nothing to resend")
	t.ok(not RaidLogic.checkpoint_resend_due(p1, true), "no resend while the catch-up runs")
	t.ok(RaidLogic.checkpoint_resend_due(p1, false), "resend once it is over")
	t.ok(not RaidLogic.checkpoint_resend_due({}, false), "nothing pending, nothing to send")


func _reread_tests(t: TestUtil) -> void:
	t.suite("raid_gap_reread")
	var seed := {"phylactery_charges": 1, "phylactery_max_per_dungeon": 1, "run_id": 4, "party": []}
	var fresh := {"phylactery_charges": 2, "phylactery_max_per_dungeon": 1, "run_id": 4}
	var out := RaidLogic.reread_seed(seed, fresh)
	t.ok(int(out["phylactery_charges"]) == 2 and int(out["party"].size()) == 0 and int(seed["phylactery_charges"]) == 1,
		"the phylactery charges are re-read; the rest of the seed and the input are untouched")
	t.ok(RaidLogic.reread_seed(seed, {}) == seed, "no fresh seed (the run is gone) changes nothing")
	t.ok(RaidLogic.reread_seed(seed, {"run_id": 4}) == seed, "a fresh seed missing the keys changes nothing")


func _wrap_tests(t: TestUtil) -> void:
	t.suite("raid_gap_wrap_floor")
	t.near(RaidLogic.break_wrap_width(0.0, 12.0, 120.0), 120.0, 0.0001, "a zero-width block wraps at the floor, not one word per line")
	t.near(RaidLogic.break_wrap_width(300.0, 12.0, 120.0), 276.0, 0.0001, "a real width is the inner width")
	t.near(RaidLogic.break_wrap_width(130.0, 12.0, 120.0), 120.0, 0.0001, "a narrow one is floored too")
	var cfg := TestUtil.load_json("res://configs/raid.json")
	t.ok(float(cfg.get("hud", {}).get("break_wrap_min_px", 0.0)) >= 60.0, "raid.json carries the floor")
	var hud := _src("res://scripts/raid/raid_hud.gd")
	var i := hud.find("class WardenBlock:")
	var j := hud.find("\nclass ", i + 10)
	var blk := hud.substr(i, (j if j >= 0 else hud.length()) - i)
	var proc := _func_src(blk, "\tfunc _process(")
	var draw := blk.substr(blk.find("for line in break_lines"))
	t.ok(proc.contains("RaidLogic.wrap_break_rows(") and proc.contains("break_lines.size()") and not proc.contains("break_rows.size()"),
		"WardenBlock._process counts the wrapped break_lines (not the raw rows) in its height")
	t.ok(blk.contains("for line in break_lines:") and not blk.contains("for line in break_rows"),
		"WardenBlock draws break_lines, never the raw rows")
	t.ok(draw.contains("_text(x0, ry, str(line)"), "the draw loop prints each wrapped line")
	t.ok(proc.contains("RaidLogic.break_wrap_width("), "the wrap width goes through the floor")


func _wiring_tests(t: TestUtil) -> void:
	t.suite("raid_gap_wiring")
	var raid := _src("res://scripts/raid/raid.gd")
	var end := _src("res://scripts/raid/raid_endings.gd")
	var dev := _src("res://scripts/raid/raid_dev.gd")
	t.ok(raid.contains("Game.game_event.connect(") and raid.contains("Game.game_event.disconnect("), "the raid connects Game.game_event and disconnects it")
	var ev := _func_src(raid, "func _on_game_event(")
	t.ok(ev.contains("RaidLogic.gap_ends_run(") and ev.contains("view_relish()") and ev.contains("gap_end("),
		"the handler asks the pure rule, reading the open run id from view_relish")
	t.ok(ev.contains("RaidLogic.reread_seed(") or raid.contains("RaidLogic.reread_seed("), "an away_report with the run still open re-reads the seed's phylactery fields")
	var ge := _func_src(end, "func gap_end(")
	t.ok(ge.contains("ended = true") and ge.contains("trance.force_end()") and ge.contains("close_retreat()") and ge.contains("_pending_cp = {}"),
		"gap_end stops the raid like an ending, closes the retreat panel and drops a pending checkpoint")
	t.ok(ge.contains("retreat_by = \"gap\"") and ge.contains("RaidLogic.gap_banner(gcfg, _raid.is_boss())") and ge.contains("gap_end\", {}).get(\"beat_s\""),
		"it sets retreat_by, shows the banner (the boss's words for the Vei fight) and holds the beat from raid.json")
	t.ok(not ge.contains("RaidDeathCard") and not ge.contains("RaidClearCard") and not ge.contains("_card"), "gap_end frees no card (none can be open: both exist only once pending_exit is set)")
	t.ok(not FileAccess.get_file_as_string("res://scripts/raid/raid_logic.gd").contains("the raid ended at its last checkpoint"), "the banner's words are not in the code")
	t.ok(_func_src(end, "func _finish_gap(").contains("finish("), "the beat's end finishes (the one emit)")
	t.ok(ge.contains("if finished or _gap"), "it runs once")
	var lb := ge.find("RaidLogic.gap_leaves_beat(ended, pending_exit)")
	t.ok(lb >= 0 and ge.substr(lb, 200).contains("return") and lb < ge.find("show_banner(") and lb < ge.find("create_timer("),
		"gap_end returns early on a running ending, before the banner and timer")
	t.ok(raid.contains("RaidLogic.gap_outcome(ev, endings.pending_exit)"), "the handler passes pending_exit")
	t.ok(_func_src(end, "func _send_checkpoint(").contains("_post_checkpoint(") and _func_src(end, "func _post_checkpoint(").contains("checkpoint_pending_after("),
		"a refused checkpoint is kept")
	t.ok(_func_src(end, "func tick(").contains("checkpoint_resend_due(") and _func_src(raid, "func _process(").contains("endings.tick()"),
		"the raid's process tick resends it once the catch-up is over")
	t.ok(_func_src(end, "func finish(").contains("_pending_cp = {}"), "finish drops a pending checkpoint")
	t.ok(dev.contains("--raid-run-ended=") and dev.contains("run_ended") and dev.contains("Game.game_event.emit("), "the dev flag emits a synthetic run_ended")
	var cap := _src("res://scripts/raid/raid_capture.gd")
	# a gap's result is a plain retreat (build_result("retreated", true)), so the capture's retreat_by rule needs no
	# gap case: it records endings.retreat_by ("gap") whenever the exit is "retreated"
	var gp := RaidLogic.close_plan(true, RaidLogic.gap_outcome({"type": "away_report"}, ""))
	t.ok(gp["exit"] == "retreated" and RaidLogic.capture_exit(false, false, true) == "retreated"
		and cap.contains("\"retreat_by\": _raid.endings.retreat_by if exit == \"retreated\"") and not cap.contains("retreat_by == \"gap\""),
		"a gap's result is exit retreated, so the capture row carries retreat_by gap through the ordinary retreat rule")
	t.ok(cap.contains("\"assist\": RaidLogic.assist_on"), "the capture row records whether LONGER WARNINGS was on")
	var cfg := TestUtil.load_json("res://configs/raid.json")
	t.ok(float(cfg.get("gap_end", {}).get("beat_s", 0.0)) > 0.0 and str(cfg.get("gap_end", {}).get("_doc", "")) != "", "raid.json gap_end.beat_s with a _doc")
