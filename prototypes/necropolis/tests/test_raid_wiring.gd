extends RefCounted
## Phase I raid wiring (dungeon-i): the ending beats checkpoint their exit (a crash in the death or victory beat
## resumes as that ending), raid_populate reads the spawn floor from realm.json, and the minor list (slam_damage's
## explicit lever, a horn-cancelled toll, the edge warning's reach, the Huntsman's typed Callable).
## Scripts naming autoloads cannot load headless, so the scene wiring is checked by source text.


func run() -> int:
	var t := TestUtil.new()
	_checkpoint_mapping_tests(t)
	_checkpoint_payload_tests(t)
	_checkpoint_roundtrip_tests(t)
	_checkpoint_effect_tests(t)
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


## What _send_checkpoint sends (RaidLogic.checkpoint_payload): sticky in the loot as in the outcome.
func _checkpoint_payload_tests(t: TestUtil) -> void:
	t.suite("raid_checkpoint_payload")
	var banked := {"relics": 1, "blueprints": [], "husks": [], "remnants": [], "essence": 2}
	var win := {"relics": 3, "blueprints": [], "husks": [], "remnants": [], "essence": 7}
	var death := {"relics": 1, "blueprints": [], "husks": [], "remnants": [], "essence": 2}
	var before := RaidLogic.checkpoint_payload("", {}, banked)
	t.ok(before["outcome"] == "retreated" and before["loot"] == banked, "before an ending: the banked loot, retreated")
	var won := RaidLogic.checkpoint_payload("warden_beaten", win, banked)
	t.ok(won["outcome"] == "warden_beaten" and won["loot"] == win, "after a win begins: the win's loot, not the pre-chest banked snapshot")
	var won_later := RaidLogic.checkpoint_payload("warden_beaten", win, {"relics": 0, "blueprints": [], "husks": [], "remnants": [], "essence": 0})
	t.ok(won_later["loot"] == win, "a later call (take_checkpoint, clamp_banked) cannot write a different loot over the win's")
	var died := RaidLogic.checkpoint_payload("relish_died", death, banked)
	t.ok(died["outcome"] == "relish_died" and died["loot"] == death, "after a death: the death's loot with relish_died")
	var none := RaidLogic.checkpoint_payload("relish_died", RaidLogic.empty_loot(), {})
	t.ok(none["loot"] == RaidLogic.empty_loot(), "a death with nothing banked sends the empty loot shape")
	t.ok(RaidLogic.checkpoint_payload("", {}, {})["loot"] == RaidLogic.empty_loot(), "an empty banked is the empty loot shape, never {}")
	var d := RaidLogic.checkpoint_payload("warden_beaten", win, banked)
	(d["loot"] as Dictionary)["relics"] = 99
	t.ok(int(win["relics"]) == 3, "the payload's loot is a copy")


## The state side of the endings: a win flips the fort and banks the chest loot, a death is counted.
func _checkpoint_effect_tests(t: TestUtil) -> void:
	t.suite("raid_checkpoint_effect")
	var loot := {"relics": 2, "blueprints": [], "husks": [], "remnants": [], "essence": 3}
	for outcome in ["warden_beaten", "relish_died"]:
		var s := GameState.new(TestUtil.configs())
		s.cmd_new_game(1)
		s.debug_enabled = true
		s.cmd_debug_set_state({"relish_at": "old-sluice"})
		var id := int(s.cmd_begin_dungeon("old-sluice")["run_id"])
		var relics0 := s.relics
		var ess0 := s.essence
		var cp := s.cmd_run_checkpoint(id, loot, outcome)
		var n := GameState.new(TestUtil.configs())
		n.cmd_new_game(2)
		var ld := n.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
		t.ok(cp["ok"] and ld["ok"] and n.run.is_empty(), "%s: checkpoint saved and loaded, the run ended" % outcome)
		var f := n.view_fort("old-sluice")
		if outcome == "warden_beaten":
			t.ok(bool(f["held"]) and int(f["flipped_count"]) == 1 and not bool(f["first_clear"]), "a win checkpoint flips the fort (held, flipped once, cleared)")
			t.ok(n.relics - relics0 == 2 and n.essence - ess0 == 3, "the win's relics and essence land (got +%d, +%d)" % [n.relics - relics0, n.essence - ess0])
			t.ok(int(n.stats["deaths"]) == 0 and n.relish["state"] == "at_fort", "a win is no death")
		else:
			t.ok(int(n.stats["deaths"]) == 1, "a death checkpoint counts the death (stats.deaths %s)" % str(n.stats["deaths"]))
			t.ok(not bool(f["held"]) and int(f["flipped_count"]) == 0, "a death flips nothing")


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
	t.ok(sc.contains("RaidLogic.checkpoint_payload(pending_exit, _ending_loot, banked)") and not sc.contains("\"retreated\""),
		"_send_checkpoint takes outcome and loot from checkpoint_payload (sticky: no later call writes retreated or the pre-ending loot back)")
	t.ok(_code(_func_src(re, "func take_checkpoint(")).contains("if ended:") and _code(_func_src(re, "func clamp_banked(")).contains("if ended:"),
		"take_checkpoint and clamp_banked do nothing once the raid has ended")
	var loot_callers := 0
	var with_arg := 0
	for line in rc.split("\n"):
		if line.contains("_send_checkpoint(") and not line.contains("func _send_checkpoint("):
			loot_callers += 1
			if not line.contains("_send_checkpoint()"):
				with_arg += 1
	var ce_body := _code(_func_src(re, "func checkpoint_ending("))
	t.ok(loot_callers == 3 and with_arg == 1 and ce_body.contains("_send_checkpoint(RaidLogic.empty_loot() if l.is_empty() else l)"),
		"checkpoint_ending is the only caller passing a loot argument to _send_checkpoint (%d callers, %d with an argument)" % [loot_callers, with_arg])
	t.ok(not _code(_src("res://scripts/raid/raid_warden_run.gd")).contains("_send_checkpoint("), "nothing outside raid_endings sends a checkpoint")
	t.ok(sc.contains("_raid._from_run") and not sc.contains("has_method"), "_send_checkpoint is guarded by _from_run only (the API exists)")
	t.ok(not re.contains("TODO(api-request #4)") and not rc.contains("has_method(\"cmd_run_checkpoint\")"), "no stale api-request #4 wording or guard")
	var ce := _code(_func_src(re, "func checkpoint_ending("))
	t.ok(ce.contains("_raid._from_run") and ce.contains("_send_checkpoint(") and not ce.contains("has_method") and ce.contains("Game.autosave()")
		and ce.find("_send_checkpoint(") < ce.find("Game.autosave()"), "checkpoint_ending sends the checkpoint, then autosaves (Game always has autosave: no guard)")
	t.ok(sc.contains("_ending_loot = loot") and ce.contains("RaidLogic.empty_loot()"), "checkpoint_ending's loot is stored, and an empty banked becomes the empty loot shape")
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
	t.ok(horn.contains("if _toll_beat_booked:") and horn.contains("toll_beats = maxi(0, toll_beats - 1)") and horn.contains("toll_marks.erase(")
		and not horn.contains("toll_at != Vector2.INF"), "a horn over a booked beat's tell un-books it, whether or not its toll was placed")
	t.ok(step.contains("_toll_beat_booked = true") and step.contains("toll_exit_px_max"), "the booked flag is set where the beat is counted; the px max is the placed-toll worst case")
	t.ok(_code(_src("res://scripts/raid/warden_huntsman.gd")).contains("var resolve: Callable = raid.resolve_walls"), "the Huntsman's wall callable is typed")
