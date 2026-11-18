extends RefCounted
## Phase I raid wiring (dungeon-i): the ending beats checkpoint their exit (a crash in the death or victory beat
## resumes as that ending), raid_populate reads the spawn floor from realm.json, and the minor list (slam_damage's
## explicit lever, a horn-cancelled toll, the edge warning's reach, the Huntsman's typed Callable).
## Scripts naming autoloads cannot load headless, so the scene wiring is checked by source text.


func run() -> int:
	var t := TestUtil.new()
	_checkpoint_mapping_tests(t)
	_checkpoint_roundtrip_tests(t)
	_checkpoint_wiring_tests(t)
	_populate_tests(t)
	_minor_tests(t)
	return t.failures


func _src(path: String) -> String:
	return FileAccess.get_file_as_string(path)


func _func_src(src: String, head: String) -> String:
	var i := src.find(head)
	if i < 0:
		return ""
	var j := src.find("\nfunc ", i + 10)
	return src.substr(i, (j if j >= 0 else src.length()) - i)


func _code(src: String) -> String:
	var out := PackedStringArray()
	for line in src.split("\n"):
		var in_q := false
		var cut := -1
		for i in line.length():
			var ch := line[i]
			if ch == "\"" and (i == 0 or line[i - 1] != "\\"):
				in_q = not in_q
			elif ch == "#" and not in_q:
				cut = i
				break
		out.append(line if cut < 0 else line.substr(0, cut))
	return "\n".join(out)


func _checkpoint_mapping_tests(t: TestUtil) -> void:
	t.suite("raid_beat_checkpoint")
	t.ok(RaidLogic.checkpoint_outcome("relish_died") == "relish_died", "a death beat checkpoints relish_died")
	t.ok(RaidLogic.checkpoint_outcome("warden_beaten") == "warden_beaten", "a victory beat checkpoints warden_beaten")
	t.ok(RaidLogic.checkpoint_outcome("") == "retreated", "no beat: retreated")
	t.ok(RaidLogic.checkpoint_outcome("chest_opened") == "retreated" and RaidLogic.checkpoint_outcome("won") == "retreated",
		"an unknown string reads as a retreat")
	t.ok(RaidLogic.checkpoint_outcome(RaidLogic.pending_on("relish_died")) == "relish_died"
		and RaidLogic.checkpoint_outcome(RaidLogic.pending_on("chest_opened")) == "warden_beaten"
		and RaidLogic.checkpoint_outcome(RaidLogic.pending_on("nothing")) == "retreated", "pending_on's output maps through")


## The state side: the outcome a checkpoint carries is what a load ends the run with.
func _checkpoint_roundtrip_tests(t: TestUtil) -> void:
	var loot := {"relics": 1, "blueprints": [], "husks": [], "remnants": [], "essence": 2}
	for case in [["relish_died", "dead"], ["retreated", "at_fort"], ["warden_beaten", "at_fort"]]:
		var s := GameState.new(TestUtil.configs())
		s.cmd_new_game(1)
		s.debug_enabled = true
		s.cmd_debug_set_state({"relish_at": "old-sluice"})
		var b := s.cmd_begin_dungeon("old-sluice")
		var id := int(b["run_id"])
		var cp := s.cmd_run_checkpoint(id, loot, case[0])
		var d: Dictionary = JSON.parse_string(JSON.stringify(s.to_dict()))
		var n := GameState.new(TestUtil.configs())
		n.cmd_new_game(2)
		var ld := n.from_dict(d)
		t.ok(cp["ok"] and ld["ok"] and str((d.get("pending_retreat", {}) as Dictionary).get("outcome", "")) == case[0],
			"%s: the save's pending_retreat carries the outcome" % case[0])
		t.ok(n.run.is_empty() and n.relish["state"] == case[1],
			"%s: the load ends the run, Relish %s (got %s)" % [case[0], case[1], str(n.relish["state"])])
	# a death resumes as a death: not at the fort, with the death's respawn clock set
	var s2 := GameState.new(TestUtil.configs())
	s2.cmd_new_game(1)
	s2.debug_enabled = true
	s2.cmd_debug_set_state({"relish_at": "old-sluice"})
	var id2 := int(s2.cmd_begin_dungeon("old-sluice")["run_id"])
	s2.cmd_run_checkpoint(id2, loot, "relish_died")
	var n2 := GameState.new(TestUtil.configs())
	n2.cmd_new_game(2)
	n2.from_dict(JSON.parse_string(JSON.stringify(s2.to_dict())))
	t.ok(n2.relish["state"] != "at_fort" and float(n2.relish.get("dead_s_left", 0.0)) > 0.0, "the death writeback sets a respawn clock (a retreat would not)")


func _checkpoint_wiring_tests(t: TestUtil) -> void:
	var re := _src("res://scripts/raid/raid_endings.gd")
	var rc := _code(re)
	var sc := _code(_func_src(re, "func _send_checkpoint("))
	t.ok(sc.contains("RaidLogic.checkpoint_outcome(pending_exit)") and not sc.contains("\"retreated\""),
		"_send_checkpoint derives its outcome from pending_exit (sticky: no later call writes retreated back)")
	t.ok(sc.contains("_raid._from_run") and not sc.contains("has_method"), "_send_checkpoint is guarded by _from_run only (the API exists)")
	t.ok(not re.contains("TODO(api-request #4)") and not rc.contains("has_method(\"cmd_run_checkpoint\")"), "no stale api-request #4 wording or guard")
	var ce := _code(_func_src(re, "func checkpoint_ending("))
	t.ok(ce.contains("_raid._from_run") and ce.contains("_send_checkpoint(") and ce.contains("has_method(\"autosave\")") and ce.contains("Game.autosave()")
		and ce.find("_send_checkpoint(") < ce.find("Game.autosave()"), "checkpoint_ending sends the checkpoint, then autosaves (guarded)")
	var dead := _code(_func_src(re, "func on_relish_died("))
	t.ok(dead.find("pending_exit =") >= 0 and dead.find("checkpoint_ending()") > dead.find("pending_exit ="),
		"on_relish_died checkpoints the death after pending_exit is set")
	t.ok(dead.find("checkpoint_ending()") < dead.find("create_timer"), "the death checkpoint lands before the beat's timer and card")
	var ww := _src("res://scripts/raid/raid_warden_run.gd")
	var body := _code(_func_src(ww, "func on_chest_opened("))
	var ck := body.find("e.checkpoint_ending(")
	t.ok(ck > body.find("e.pending_exit =") and ck > body.find("merge_loot(") and ck < body.find("RaidAutopilot.enabled()"),
		"on_chest_opened checkpoints the win after the loot merge and pending_exit, before the bot/card branch")
	t.ok(body.contains("e.checkpoint_ending(RaidLogic.result_loot(\"warden_beaten\", false, _raid.found_loot, _raid.carried_count(), e.banked))"),
		"the win checkpoint carries the loot the win result pays")
	t.ok(_code(_func_src(re, "func build_result(")).contains("RaidLogic.result_loot(exit, closing, _raid.found_loot, _raid.carried_count(), banked)"),
		"build_result pays through the same result_loot")


func _populate_tests(t: TestUtil) -> void:
	t.suite("raid_populate_floor")
	var realm := TestUtil.load_json("res://configs/realm.json")
	var fl := float((realm.get("hold", {}) as Dictionary).get("clear_min_living", -1.0))
	t.ok(fl > 0.0, "realm.json hold.clear_min_living is set (%s)" % str(fl))
	var pop := _code(_src("res://scripts/raid/raid_populate.gd"))
	t.ok(pop.contains("ConfigDb.data[\"realm\"][\"hold\"][\"clear_min_living\"]") and pop.contains("living > floor_living"),
		"the spawn floor is read from realm.json hold.clear_min_living")
	t.ok(not pop.contains("living > 0.05") and not pop.contains("0.05"), "no literal 0.05 floor left in raid_populate")


func _minor_tests(t: TestUtil) -> void:
	t.suite("raid_minor_list")
	var wl := _src("res://scripts/raid/warden_logic.gd")
	t.ok(_code(wl).contains("muffled: bool, lever: bool) -> float:") and not _code(wl).contains("lever := true"), "slam_damage has no default lever")
	var bell := _code(_src("res://scripts/raid/warden_bellringer.gd"))
	var passes := true
	var calls := 0
	for line in bell.split("\n"):
		for part in line.split("WardenLogic.slam_damage(").slice(1):
			calls += 1
			passes = passes and (part.contains(", true)") or part.contains(", lev)"))
	t.ok(calls == 4 and passes, "the bellringer passes the lever to every slam_damage (%d calls)" % calls)
	# the edge warning reaches as far as the slam's ring
	var cfg := TestUtil.load_json("res://configs/raid.json")
	var spec := WardenLogic.spec({"id": "old-sluice", "tier": 2}, cfg)
	var at: Dictionary = spec["attack"]
	t.near(WardenLogic.slam_edge_px(spec), float(at["radius_px"]) + float(at["band_px"]) * 0.5, 0.0001, "the slam's edge is radius_px plus half the band")
	t.ok(WardenLogic.slam_edge_px(spec) > float(at["radius_px"]), "the ring reaches past radius_px (the 260-278 px gap the warning missed)")
	var step := _code(_func_src(_src("res://scripts/raid/warden_bellringer.gd"), "func _step("))
	var w := step.find("raid.danger_targeted()")
	var cond := step.substr(maxi(0, w - 420), 420)
	t.ok(cond.contains("<= WardenLogic.slam_edge_px(spec)") and not cond.contains("at.get(\"radius_px\""), "the edge warning checks the slam's edge, not the bare radius")
	t.ok(step.contains("var slam_reach := WardenLogic.slam_edge_px(spec)"), "the toll's reach test reads the same edge")
	# a horn-cancelled toll is not booked
	var horn := step.substr(0, step.find("muffled = WardenLogic.is_muffled"))
	t.ok(horn.contains("toll_beats = maxi(0, toll_beats - 1)") and horn.contains("toll_marks.erase("), "a horn over a toll's tell un-books it")
	t.ok(_code(_src("res://scripts/raid/warden_huntsman.gd")).contains("var resolve: Callable = raid.resolve_walls"), "the Huntsman's wall callable is typed")
