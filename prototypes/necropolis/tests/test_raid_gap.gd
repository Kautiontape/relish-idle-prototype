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
	_boss_won_tests(t)
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
	# gap_plan: the raid keeps a running ending beat (leave); the Vei fight never does, and cuts whatever end is up
	var gp := RaidLogic.gap_plan(true, "relish_died", false)
	t.ok(gp["leave"] and not gp["cut_end"], "gap_plan raid, death beat running: leave it, cut nothing")
	gp = RaidLogic.gap_plan(true, "warden_beaten", false)
	t.ok(gp["leave"] and not gp["cut_end"], "gap_plan raid, victory beat running: leave it")
	gp = RaidLogic.gap_plan(false, "", false)
	t.ok(not gp["leave"] and not gp["cut_end"], "gap_plan raid, nothing ended: the stop runs, nothing to cut")
	gp = RaidLogic.gap_plan(true, "", false)
	t.ok(not gp["leave"] and not gp["cut_end"], "gap_plan raid, retreat beat (ended, no pending_exit): the stop runs, no card to cut")
	gp = RaidLogic.gap_plan(false, "", true)
	t.ok(not gp["leave"] and not gp["cut_end"], "gap_plan boss, mid-fight: the stop runs, no end to cut")
	gp = RaidLogic.gap_plan(true, "", true)
	t.ok(not gp["leave"] and gp["cut_end"], "gap_plan boss, unravel or card up (ended, no pending_exit): cut the card and the set piece, then the banner")
	gp = RaidLogic.gap_plan(true, "relish_died", true)
	t.ok(not gp["leave"] and gp["cut_end"], "gap_plan boss without a recorded win never leaves a beat: the state forfeits the fight")
	gp = RaidLogic.gap_plan(true, "", true, true)
	t.ok(gp["leave"] and not gp["cut_end"], "gap_plan boss, unravel or win card up with the win the state holds (#22): leave it, cut nothing")
	gp = RaidLogic.gap_plan(false, "", true, true)
	t.ok(not gp["leave"] and not gp["cut_end"], "gap_plan boss_won mid-fight (can't happen: the win is recorded once the fight is over): the stop runs")
	t.ok(RaidLogic.gap_outcome({"type": "run_ended", "kind": "boss", "outcome": "won", "cause": "gap"}) == "won",
		"a boss run whose recorded win the gap applied: the outcome is won")
	t.ok(RaidLogic.gap_outcome({"type": "run_ended", "kind": "boss", "outcome": "retreated", "cause": "gap"}) == "retreated"
		and RaidLogic.gap_outcome({"type": "away_report"}, "") == "retreated", "a forfeited boss run and the backstop still read retreated")
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
	# Source pins, on purpose: raid.gd, raid_endings.gd and raid_hud.gd name autoloads, so the headless suite cannot
	# build a raid, emit run_ended and run to the finish. The decisions are RaidLogic's statics (tested above); these
	# pin each call WITH its arguments inside the function it must live in, so a rename or a wrong argument fails.
	# The end-to-end check (one result, a checkpoint-less beat) is the --raid-run-ended=60 boot, which reads "retreated".
	var raid := _src("res://scripts/raid/raid.gd")
	var end := _src("res://scripts/raid/raid_endings.gd")
	var dev := _src("res://scripts/raid/raid_dev.gd")
	t.ok(raid.contains("Game.game_event.connect(") and raid.contains("Game.game_event.disconnect("), "the raid connects Game.game_event and disconnects it")
	var ev := _func_src(raid, "func _on_game_event(")
	t.ok(ev.contains("if RaidLogic.gap_ends_run(ev, run_id, open_id):\n\t\tendings.gap_end(RaidLogic.gap_outcome(ev, endings.pending_exit))")
		and ev.contains("int(Game.state.view_relish().get(\"run_id\", -1)) if str(ev.get(\"type\", \"\")) == \"away_report\" else -1"),
		"the handler asks the pure rule with the run id and the open run id (from view_relish), then ends the run with the recorded outcome and pending_exit")
	t.ok(ev.contains("RaidLogic.reread_seed(") or raid.contains("RaidLogic.reread_seed("), "an away_report with the run still open re-reads the seed's phylactery fields")
	var ge := _func_src(end, "func gap_end(")
	t.ok(ge.contains("ended = true") and ge.contains("trance.force_end()") and ge.contains("close_retreat()") and ge.contains("_pending_cp = {}"),
		"gap_end stops the raid like an ending, closes the retreat panel and drops a pending checkpoint")
	t.ok(ge.contains("if not ended:\n\t\tretreat_by = \"gap\"") and ge.contains("_raid.hud.show_banner(RaidLogic.gap_banner(gcfg, _raid.is_boss()), float(gcfg.get(\"banner_s\", 4.0)), \"danger\")")
		and ge.contains("create_timer(float(_raid.rcfg().get(\"gap_end\", {}).get(\"beat_s\", 2.5))).timeout.connect(_finish_gap.bind(outcome))"),
		"it sets retreat_by (unless an ending ran), shows the banner (the boss's words for the Vei fight) and holds the beat from raid.json, then finishes with the recorded outcome")
	t.ok(not ge.contains("RaidDeathCard") and not ge.contains("RaidClearCard") and not ge.contains("_card"), "gap_end frees no raid card itself (none can be open: both exist only once pending_exit is set; the boss's own card goes through gap_plan)")
	t.ok(not FileAccess.get_file_as_string("res://scripts/raid/raid_logic.gd").contains("the raid ended at its last checkpoint"), "the banner's words are not in the code")
	var fg := _func_src(end, "func _finish_gap(")
	t.ok(fg.contains("\tfinish(_raid.close_result())") and fg.contains("\t\tfinish(win_result)")
		and fg.contains("finish(_raid._death_result() if plan[\"exit\"] == \"relish_died\" else build_result(plan[\"exit\"], plan[\"closing\"]))"), "the beat's end finishes (the one emit) with the result the state recorded: boss, win, death or retreat")
	t.ok(ge.contains("if finished or _gap:\n\t\treturn\n\t_gap = true"), "it runs once: a second call, or one after the finish, returns before it sets _gap")
	var lb := ge.find("RaidLogic.gap_plan(ended, pending_exit, _raid.is_boss(), outcome == \"won\" or win_recorded)")
	t.ok(lb >= 0 and ge.substr(lb, 200).contains("return") and lb < ge.find("show_banner(") and lb < ge.find("create_timer("),
		"gap_end returns early on a running ending, before the banner and timer")
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


## P3b (api-request #22), the scene's half (the state's is economy's test_boss_won): as Vei breaks the boss scene freezes
## its win's result and records it with the open run (VeiBoss._record_win: cmd_boss_won, then a save), so a gap applies
## it as the win. VeiBoss can't load headless, so its call site is pinned by source text, and the flow it drives runs
## on a GameState: the result VeiBoss builds (BossLogic.result_of on a fight state, won) is accepted; a 100 s gap ends
## the run with run_ended "won", which the scene's rules read as the win (gap_outcome, then gap_plan: the card stays);
## the card's later press of the same dict reads duplicate_run, which the router takes as done (RouterLogic.result_done).
## Without a record the gap still forfeits, and the card is cut (the control).
func _boss_won_tests(t: TestUtil) -> void:
	t.suite("raid_gap_boss_won")
	var s := _boss_state(t)
	var sd := s.view_boss_seed()
	var rid := int(sd.get("run_id", -1))
	var won := BossLogic.result_of({"seed": sd, "p1": {}, "fronts_cleared": [], "phase1_s": 40.0, "deaths": 0,
		"spent": {"phylactery": 0, "clones": 0}, "party_lost": [], "horde0": 100.0, "horde": 0.0}, true)
	var rec := s.cmd_boss_won(rid, won)
	t.ok(bool(rec.get("ok", false)), "the scene's result, won, is recorded: %s %s" % [str(rec.get("reason", "")), str(rec.get("errors", []))])
	s.drain_events()
	s.tick(100.0, s.max_substeps_per_frame())
	var q := s.drain_events()
	var ended := q.filter(func(e): return e["type"] == "run_ended")
	t.ok(ended.size() == 1 and RaidLogic.gap_ends_run(ended[0], rid, -1) and RaidLogic.gap_outcome(ended[0]) == "won" and s.won,
		"a 100 s gap: one run_ended for our run, read as won, and the game is won (%s)" % str(ended))
	var plan := RaidLogic.gap_plan(true, "", true, RaidLogic.gap_outcome(ended[0]) == "won" if not ended.is_empty() else false)
	t.ok(plan["leave"] and not plan["cut_end"], "the scene leaves the unravel or the win card up: no AWAY TOO LONG, no cut")
	var away := q.filter(func(e): return e["type"] == "away_report")
	t.ok(away.is_empty() or (RaidLogic.gap_ends_run(away[0], rid, int(s.view_relish().get("run_id", -1)))
		and RaidLogic.gap_outcome(away[0], "") == "retreated" and RaidLogic.gap_plan(true, "", true, true)["leave"]),
		"the backstop away_report says no outcome; the scene's own record (win_recorded) keeps the card")
	var press := s.apply_result("boss", won)
	t.ok(not bool(press.get("ok", true)) and str(press.get("reason", "")) == "duplicate_run" and RouterLogic.result_done(press),
		"the card's press of the same dict after the gap: duplicate_run, which the router takes as done (%s)" % str(press.get("reason", "")))
	t.ok(RouterLogic.result_done({"ok": true, "reason": ""}) and not RouterLogic.result_done({"ok": false, "reason": "wrong_run"})
		and not RouterLogic.result_done({}), "result_done: ok or duplicate_run only; a forfeited run's wrong_run is still a refusal")
	t.ok(not RouterLogic.result_stale("boss", s.view_relish()), "a boss result is still never stale (the stale toast names a raid)")
	# the control: no record, so the gap forfeits the fight and the card is cut
	var f := _boss_state(t)
	var fid := int(f.view_boss_seed().get("run_id", -1))
	f.drain_events()
	f.tick(100.0, f.max_substeps_per_frame())
	var fe := f.drain_events().filter(func(e): return e["type"] == "run_ended")
	var fo := RaidLogic.gap_outcome(fe[0]) if not fe.is_empty() else ""
	var fp := RaidLogic.gap_plan(true, "", true, fo == "won")
	t.ok(fo == "retreated" and not f.won and not fp["leave"] and fp["cut_end"] and str(f.apply_result("boss", BossLogic.result_of({"seed": f.view_boss_seed(),
		"p1": {}, "fronts_cleared": [], "phase1_s": 40.0, "deaths": 0, "spent": {"phylactery": 0, "clones": 0}, "party_lost": [], "horde0": 100.0,
		"horde": 0.0}, true)).get("reason", "")) != "duplicate_run", "without a record: the gap forfeits (run %d, %s), the card is cut, and a press is not taken as done" % [fid, fo])
	# the call site (VeiBoss can't load headless)
	var vb := _src("res://scripts/raid/vei_boss.gd")
	var win := _func_src(vb, "func _win(")
	var rw := _func_src(vb, "func _record_win(")
	t.ok(win.find("_end_common()") >= 0 and win.find("_end_common()") < win.find("_record_win()") and win.find("_record_win()") < win.find("_seq_kind = \"win\""),
		"Vei breaks: the fight ends, then the win is recorded, before the unravel starts")
	t.ok(rw.contains("_win_r = _result(true)") and rw.contains("Game.state.cmd_boss_won(int(seed_data.get(\"run_id\", 0)), _win_r)")
		and rw.contains("endings.win_recorded = bool(r.get(\"ok\", false))") and rw.contains("Game.autosave()")
		and rw.find("_win_r = _result(true)") < rw.find("if not _from_run:") and rw.find("if not _from_run:") < rw.find("cmd_boss_won(")
		and rw.find("cmd_boss_won(") < rw.find("Game.autosave()"), "_record_win freezes the result, records it for a real run only, keeps the answer and saves")
	t.ok(_func_src(vb, "func _emit(").contains("var r := _win_r if won and not _win_r.is_empty() else _result(won)")
		and _func_src(vb, "func close_result(").contains("var r := _win_r if bool(f[\"won\"]) and not _win_r.is_empty() else _result(bool(f[\"won\"]))"),
		"the press, its self-press and a window close send the recorded dict")
	t.ok(not vb.contains("TODO(api-request #22)") and _func_src(vb, "func _win_card(").contains("win_card_auto_s"), "the #22 TODO is gone; the card still presses itself")
	t.ok(_func_src(_src("res://scripts/main.gd"), "func _apply(").contains("if not RouterLogic.result_done(out):"), "the router asks result_done before it warns and forfeits")
	var gdoc := str(TestUtil.load_json("res://configs/raid.json").get("gap_end", {}).get("_doc", ""))
	t.ok(gdoc.contains("the moment Vei breaks") and not gdoc.contains("Only the press keeps the win"), "gap_end._doc says the win is kept from the break")


func _boss_state(t: TestUtil) -> GameState:
	var s := GameState.new(TestUtil.configs())
	s.debug_enabled = true
	s.save_dir = "user://test_raid_gap_%d" % OS.get_process_id()
	t.ok(bool(s.cmd_debug_load_fixture("pre_vei").get("ok", false)) and bool(s.cmd_begin_boss().get("ok", false)), "(setup) pre_vei, a boss run open")
	return s
