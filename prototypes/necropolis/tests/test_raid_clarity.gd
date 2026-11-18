extends RefCounted
## Phase I raid clarity (dungeon-i): the retreat panel (item 8: Space never confirms a retreat) and the
## retreat lines (item 6). Pure logic and the real RaidRetreatPanel class; no scene tree, no autoloads.


func run() -> int:
	var t := TestUtil.new()
	Palette.configure(TestUtil.load_json("res://configs/palette.json"))
	_retreat_panel_tests(t)
	_retreat_line_tests(t)
	_warden_presence_tests(t)
	_legend_tests(t)
	_hint_cue_tests(t)
	_goal_tests(t)
	_clear_card_tests(t)
	return t.failures


## T5: the clear card's words (RaidLogic) and the warden run's wiring (source text: raid_warden_run.gd names RaidAutopilot).
func _clear_card_tests(t: TestUtil) -> void:
	t.suite("raid_clear_card")
	t.ok(RaidLogic.clear_card_title("Old Sluice") == "OLD SLUICE IS YOURS", "title upper-cases the fort name")
	var found := {"relics": 2, "husks": [{"kind": "skeleton"}], "essence": 3}
	var won := RaidLogic.loot_counts(RaidLogic.result_loot("warden_beaten", false, found, 4, {}))
	t.ok(int(won["relics"]) == 2 and int(won["husks"]) == 1 and int(won["essence"]) == 4, "the win pays everything found plus the carried essence")
	var ca := _func_src(FileAccess.get_file_as_string("res://scripts/raid/raid.gd"), "func carry_add(")
	t.ok(ca.contains("not endings.win_result.is_empty()") and ca.find("win_result") < ca.find("carried.append("),
		"no mote joins the slots once the win is frozen at the chest (the ring shows what the card pays)")
	var rows := RaidLogic.clear_card_rows("The Bellringer", won)
	var labels: Array = []
	var no_contradiction := true
	for r in rows:
		labels.append(r["label"])
		var tx := str(r["text"])
		if tx.contains("banked") and tx.contains("lost"):
			no_contradiction = false
	t.ok(labels == ["BROKEN", "TAKEN", "LOOT", "NEXT"], "the four rows in order")
	t.ok(rows[0]["text"] == "The Bellringer" and rows[0]["key"] == "vei", "BROKEN names the warden")
	t.ok(rows[2]["text"] == RaidLogic.loot_line(won) and str(rows[2]["text"]).contains("relics 2"), "LOOT reads the counts")
	t.ok(RaidLogic.clear_card_rows("X", RaidLogic.loot_counts(RaidLogic.empty_loot()))[2]["text"] == "nothing this time", "empty loot reads 'nothing this time'")
	t.ok(no_contradiction, "no row says banked next to lost")
	var src := FileAccess.get_file_as_string("res://scripts/raid/raid_warden_run.gd")
	var i := src.find("func on_chest_opened")
	var body := src.substr(i, src.find("\nfunc ", i + 10) - i if src.find("\nfunc ", i + 10) > 0 else -1)
	var bot := body.find("RaidAutopilot.enabled()")
	var card_at := body.find("RaidClearCard.new()")
	t.ok(bot > 0 and card_at > bot, "the bot check comes before the card is built")
	var bot_branch := body.substr(bot, card_at - bot)
	t.ok(bot_branch.contains("victory_s") and bot_branch.contains("show_banner(\"THE WARDEN IS BEATEN"), "the bot branch keeps victory_s and its banner")
	var rest := body.substr(card_at)
	t.ok(rest.contains("hud.add_child(card)") and rest.contains("card.dismissed.connect(finish_win)"), "the card is added to the HUD and its dismissal finishes the run")
	t.ok(rest.contains("\"card_s\"") and rest.contains("create_timer") and not rest.contains("show_banner"), "a card_s timer backs it up, no banner")
	t.ok(body.contains("else e.build_result(\"warden_beaten\"))") and body.contains("e.pending_exit = RaidLogic.pending_on(\"chest_opened\")"), "the result is still build_result(warden_beaten), pending_exit set first")
	# the win is frozen at chest open: built once before the card, finished with that dict on every path
	var wr := body.find("e.win_result = e.build_result(\"warden_beaten\")")
	t.ok(wr > bot and wr < card_at, "the non-bot path builds the result once, before the card")
	var code_body := _code(body)   # comments stripped: a note naming build_result( cannot flip these counts
	var code_rest := _code(rest)
	t.ok(code_rest.count("build_result(") == 0 and code_body.count("build_result(") == 2, "the card path never rebuilds it (only the bot's fallback does)")
	t.ok(body.contains("e.finish(e.win_result if not e.win_result.is_empty() else e.build_result(\"warden_beaten\"))")
		and rest.contains("card.dismissed.connect(finish_win)") and rest.contains("timeout.connect(finish_win)"), "the dismissal and the timer both finish with the stored dict")
	t.ok(body.contains("loot_counts(e.win_result[\"loot\"])") and body.contains("hud.on_clear(won)") and rest.contains("clear_card_rows(warden_name, won)"), "the card and the HUD read the win's own loot")
	var es := FileAccess.get_file_as_string("res://scripts/raid/raid_endings.gd")
	var cr := es.find("func close_request")
	var cbody := es.substr(cr, es.find("\n# ---", cr) - cr)
	t.ok(es.contains("var win_result := {}") and cbody.contains("win_result.is_empty()") and cbody.contains("finish(win_result)"), "close_request emits the stored win when it exists")
	var hs := FileAccess.get_file_as_string("res://scripts/raid/raid_hud.gd")
	var hcode := _code(hs)
	t.ok(_func_src(hcode, "func on_clear(").contains("_clearing = true") and _func_src(hcode, "func show_banner(").contains("_clearing")
		and _func_src(hcode, "func refresh(").contains("_clearing") and _func_src(hcode, "func _update_push(").contains("not _clearing"),
		"the HUD's on_clear path, read by refresh, the banner and the push line")
	var ub0 := RaidLogic.loot_counts(RaidLogic.empty_loot())
	t.ok(not RaidLogic.push_line(2, "W", 1, won, false, 1, 3, false).contains("risk") and RaidLogic.push_line(2, "W", 1, won, false, 1, 3).contains("at risk"),
		"the push line drops its at-risk clause once the win is banked")
	t.ok(int(ub0["total"]) == 0, "nothing unbanked after the win")
	var cc: Dictionary =TestUtil.load_json("res://configs/raid.json").get("clear", {})
	for k in ["card_s", "skip_after_s", "fade_s"]:
		t.ok(cc.get(k, 0) is float or cc.get(k, 0) is int, "clear.%s is a number" % k)
		t.ok(float(cc.get(k, 0)) > 0.0, "clear.%s > 0" % k)
	var card_src := FileAccess.get_file_as_string("res://scripts/raid/raid_clear_card.gd")
	var death_src := FileAccess.get_file_as_string("res://scripts/raid/raid_death_card.gd")
	t.ok(card_src.contains("click or press Space to return to the realm") and not card_src.contains("\"click to return"), "the clear card's footer names click and Space")
	t.ok(_func_src(card_src, "func _input(").contains("RaidLogic.card_skips(ev, _t, _skip_after)")
		and _func_src(death_src, "func _input(").contains("RaidLogic.card_skips(ev, _t, _skip_after)"), "both cards skip through the one shared rule")
	_card_skip_tests(t)


## T4: the goal line, the route line, how the warden breaks (break / takes / counter lines from the spec the game
## builds) and the no-army row. Words live in RaidLogic / WardenLogic; the HUD's wiring is checked by source text.
func _goal_tests(t: TestUtil) -> void:
	t.suite("raid_goal")
	t.ok(RaidLogic.goal_line("Old Sluice", "The Bellringer", false) == "GOAL · break THE BELLRINGER to take OLD SLUICE", "goal line, a dungeon")
	t.ok(RaidLogic.goal_line("Old Sluice", "The Bellringer", true) == "YOUR FORT · clear its counter-garrison for loot", "goal line, a held fort")
	t.ok(RaidLogic.route_line(3, 2, "NE") == "room 1 of 3 · the warden is 2 rooms on · next door NE", "route: room 1 of 3, 2 rooms on, next door NE")
	t.ok(RaidLogic.route_line(3, 1, "E") == "room 2 of 3 · the warden is 1 room on · next door E", "route: room 2 of 3, 1 room on, next door E")
	t.ok(RaidLogic.route_line(3, 0, "") == "you are in the warden's room", "route: in the warden's room")
	t.ok(RaidLogic.route_line(3, 0, "N") == "you are in the warden's room", "route: in the warden's room names no door")
	t.ok(RaidLogic.route_line(3, 5, "S").begins_with("room 1 of 3 · the warden is 5 rooms on · next door S"), "route: off the route (more hops left than the route) clamps to room 1")
	t.ok(RaidLogic.route_line(0, 2, "NE") == "the warden is 2 rooms on · next door NE" and RaidLogic.route_line(0, 1, "") == "the warden is 1 room on",
		"route: an unreachable spawn room (route_len 0) drops 'room n of m', never 'of 0'")
	t.ok(RaidLogic.route_line(3, 2, "") == "room 1 of 3 · the warden is 2 rooms on", "route: no compass word drops the next-door clause")
	_goal_rows_tests(t)
	t.ok(RaidLogic.no_army(0, 0, 0, 0), "no army: all four zero")
	t.ok(not RaidLogic.no_army(1, 0, 0, 0) and not RaidLogic.no_army(0, 1, 0, 0) and not RaidLogic.no_army(0, 0, 1, 0) and not RaidLogic.no_army(0, 0, 0, 1),
		"no army: any one of undead, loose motes, carried or piles left says no")
	t.ok(RaidLogic.NO_ARMY_LINE == "NO UNDEAD WITH YOU AND NOTHING TO RAISE · retreat, then send WAR here or bring big undead", "the no-army line, word for word")
	var cfg: Dictionary = TestUtil.load_json("res://configs/raid.json")
	var pips := int(cfg["wardens"]["meter_pips"])
	var verbs := {"bellringer": "muffles its slams", "huntsman": "intercepts its lunge", "shieldwall": "flanks it from behind", "pyre_priest": "snuffs an acolyte in one blow"}
	for tier in [1, 3]:
		for a in ["bellringer", "huntsman", "shieldwall", "pyre_priest"]:
			var sp := RaidLogic.warden_spec({"id": "x", "tier": tier, "archetype": a}, cfg)
			var ac: Dictionary = cfg["wardens"]["archetypes"][a]
			var tag := "%s t%d" % [a, tier]
			# the pips the player sees: the warden node's meter_n (warden.gd: bands x pips per band; the Pyre-priest's own meter)
			var bands := WardenLogic.meter_bands(sp)
			var shown := WardenLogic.meter_per_band(bands, pips) * (bands.size() - 1)
			if a == "pyre_priest":
				shown = int(WardenLogic.pyre_meter(sp, pips, int(cfg["wardens"]["pyre_pips_per_acolyte"]))["n"])
			t.ok(WardenLogic.break_line(sp, shown).contains("%d pips" % shown), "%s: the break line holds the meter the player sees (%d; config meter_pips %d)" % [tag, shown, pips])
			var tk := WardenLogic.takes_line(sp)
			var want: Array = []
			match a:
				"huntsman":
					want.append(WardenLogic._num(float(ac["weak_point"]["stun_dmg_mult"])))
				"shieldwall":
					want.append(WardenLogic._num(float(ac["attack"]["front_mult"])))
					want.append(WardenLogic._num(float(ac["attack"]["back_mult"])))
				"pyre_priest":
					want.append(WardenLogic._num(float(ac["attack"]["ward_mult"])))
			var has_pack := sp.has("pack")
			t.ok(has_pack == (tier >= int(ac["pack"]["min_tier"]) and int(ac["pack"]["size_by_tier"][str(tier)]) > 0), "%s: the spec has a pack only from its min_tier" % tag)
			var pk_part := "×%s while its %s stand" % [WardenLogic._num(float(ac["pack"]["ward_mult"])), str(ac["pack"]["name"])]
			t.ok(tk.contains(pk_part) == has_pack, "%s: the takes line names the pack only where the spec has one" % tag)
			var all_in := true
			for m in want:
				all_in = all_in and tk.contains("×" + str(m))
			t.ok(all_in and (want.is_empty() and not has_pack) == (tk == ""), "%s: the takes line holds the config's multipliers %s: '%s'" % [tag, str(want), tk])
			t.ok(tk == "" or tk.begins_with("TAKES "), "%s: the takes line starts TAKES" % tag)
			var wp: Dictionary = ac["weak_point"]
			var thr := int(wp["threshold"])
			var base := "COUNTER · a big undead with %s %d+ %s" % [str(wp["stat"]), thr, verbs[a]]
			t.ok(WardenLogic.counter_line(sp, []) == base + " · you have none: raise more undead", "%s: the counter line, no bigs" % tag)
			t.ok(WardenLogic.counter_line(sp, [thr - 1, 0]) == base + " · none in your party", "%s: the counter line, none meets it" % tag)
			t.ok(WardenLogic.counter_line(sp, [thr, thr + 3, thr - 1]) == base + " · 2 in your party", "%s: the counter line, 2 of 3 meet it" % tag)
	var hud_src := FileAccess.get_file_as_string("res://scripts/raid/raid_hud.gd")
	var build_src := _func_src(hud_src, "func build(")
	t.ok(RegEx.create_from_string("if not boss_mode:\\s*_warden_block = WardenBlock\\.new\\(\\)").search(build_src) != null
		and build_src.contains("RaidGoalBlock.new()") and build_src.find("RaidGoalBlock.new()") > build_src.find("_warden_block = WardenBlock.new()")
		and build_src.find("RaidGoalBlock.new()") < build_src.find("if not boss_mode:   # there is no retreat"),
		"the HUD builds the RaidGoalBlock only inside the not-boss branch that builds the WardenBlock")
	for call in ["RaidLogic.goal_rows(", "RaidLogic.route_line(", "WardenLogic.break_line(", "WardenLogic.takes_line(", "WardenLogic.counter_line(", "RaidLogic.no_army("]:
		t.ok(hud_src.contains(call), "the HUD takes its words from %s" % call)
	var logic_src := FileAccess.get_file_as_string("res://scripts/raid/raid_logic.gd")
	t.ok(_func_src(logic_src, "static func goal_rows(").contains("goal_line(") and _func_src(logic_src, "static func goal_rows(").contains("NO_ARMY_LINE"), "goal_rows words its rows with goal_line and NO_ARMY_LINE")
	t.ok(hud_src.contains("RaidHud.break_rows(raid, w.spec, int(w.meter_n))") and hud_src.contains("break_rows(raid, sp, int(w.meter_n))"),
		"the WardenBlock and the GoalBlock take their break rows with the warden node's meter_n")
	t.ok(hud_src.contains("\"WARDEN\")") and hud_src.contains("_edge(_wp, view, Palette.c(\"vei\"), \"WARDEN\")"), "the Pointers class draws a WARDEN edge chevron")
	var gb := FileAccess.get_file_as_string("res://scripts/raid/raid_goal_block.gd")
	t.ok(gb.contains("class_name RaidGoalBlock") and not gb.contains("ConfigDb") and not gb.contains("Game."), "the goal block names no autoload")
	var gcfg: Dictionary = cfg.get("hud", {}).get("goal", {})
	var gok := gcfg.has("_doc")
	for k in ["goal_px", "route_px", "row_px", "plate_alpha"]:
		gok = gok and (gcfg.get(k) is float or gcfg.get(k) is int) and float(gcfg[k]) > 0.0
	t.ok(gok, "hud.goal is documented, with goal_px, route_px, row_px, plate_alpha all > 0")


## T2: the hint line's words, the two onboarding cues and the ESSENCE row's meaning. Words and rules live in
## RaidLogic; raid.gd / raid_hud.gd name Game/ConfigDb, so their wiring is checked by source text.
func _hint_cue_tests(t: TestUtil) -> void:
	t.suite("raid_hints")
	t.ok(RaidLogic.hint_text(true, false) == "DRAG A LOOP AROUND ESSENCE · each mote inside becomes one undead", "trance: the loop instruction")
	t.ok(RaidLogic.hint_text(false, true) == "AT EXIT · RETREAT banks your loot", "at the exit: the retreat line, word for word")
	t.ok(RaidLogic.hint_text(false, false) == "HOLD SPACE · circle essence to RAISE undead", "idle: hold Space to raise")
	t.ok(RaidLogic.hint_text(true, true) == RaidLogic.hint_text(true, false), "the trance case wins over the exit case")
	var words: Array = [RaidLogic.hint_text(true, false), RaidLogic.hint_text(false, true), RaidLogic.hint_text(false, false),
		RaidLogic.CUE_FIRST_MOTE, RaidLogic.CUE_UNDEAD, RaidLogic.ESSENCE_MEANING]
	for i in 4:
		words.append(RaidLogic.last_chance_banner(i))
	var gather := false
	for w in words:
		gather = gather or str(w).to_lower().contains("gather")
	t.ok(not gather, "no hint, cue, essence meaning or last-chance banner says 'gather'")
	t.ok(RaidLogic.CUE_FIRST_MOTE.contains("RAISE") and RaidLogic.CUE_FIRST_MOTE.contains("BANK")
		and RaidLogic.ESSENCE_MEANING.contains("RAISE") and RaidLogic.ESSENCE_MEANING.contains("BANK"), "the first-mote cue and the essence meaning name RAISE and BANK")
	var longest := 0
	for cue in [RaidLogic.CUE_FIRST_MOTE, RaidLogic.CUE_UNDEAD]:
		for seg in str(cue).split(" · "):
			longest = maxi(longest, seg.length())
	t.ok(longest <= 36, "every cue line (split at ' · ') is short, so the cue's plate stays narrow over the world (longest %d chars)" % longest)
	t.ok(RaidLogic.last_chance_banner(0) == "LAST CHANCE · a free trance" and RaidLogic.last_chance_banner(3).ends_with("3 loose essence here: walk close and it drifts to you"), "last chance: bare at 0, the drift line with a count")
	t.ok(not RaidLogic.undead_cue_due(true, 3, 99.0, 5.0, 4), "the undead cue never repeats")
	t.ok(not RaidLogic.undead_cue_due(false, 3, 99.0, 5.0, 0), "none without an undead standing")
	t.ok(RaidLogic.undead_cue_due(false, 1, 0.0, 5.0, 1), "a kill makes it due")
	t.ok(RaidLogic.undead_cue_due(false, 0, 5.0, 5.0, 1), "scene_s == delay_s makes it due with no kill")
	t.ok(not RaidLogic.undead_cue_due(false, 0, 4.9, 5.0, 1), "not before the delay with no kill")
	var cues: Dictionary = TestUtil.load_json("res://configs/raid.json").get("hud", {}).get("cues", {})
	var ok := cues.has("_doc")
	for k in ["max_wait_s", "first_mote_s", "undead_s", "undead_delay_s"]:
		ok = ok and (cues.get(k) is float or cues.get(k) is int) and float(cues[k]) > 0.0
	t.ok(ok, "hud.cues is documented, with max_wait_s, first_mote_s, undead_s, undead_delay_s all > 0")
	var raid_src := FileAccess.get_file_as_string("res://scripts/raid/raid.gd")
	t.ok(RegEx.create_from_string("if not is_boss\\(\\) and hud != null:\\s*hud\\.on_first_carry\\(\\)").search(raid_src) != null,
		"carry_add calls the HUD's first-carry path under a not-boss guard")
	var died := _func_src(raid_src, "func on_unit_died(")
	var enemy_branch := died.substr(0, died.find("\telse:"))
	t.ok(enemy_branch.contains("kills += 1") and enemy_branch.contains("faction == \"enemy\""), "on_unit_died counts the kill in the enemy branch")
	var hud_src := FileAccess.get_file_as_string("res://scripts/raid/raid_hud.gd")
	t.ok(hud_src.contains("RaidLogic.hint_text(") and hud_src.contains("RaidLogic.undead_cue_due(") and hud_src.contains("RaidLogic.ESSENCE_MEANING"),
		"the HUD takes its hint, undead cue and essence meaning from RaidLogic")
	var cue_src := _func_src(hud_src, "func show_cue(")
	t.ok(RegEx.create_from_string("if _banner_t < 0\\.0:\\s*show_banner\\(").search(cue_src) != null and cue_src.count("show_banner(") == 1
		and cue_src.find("_cue_queue.append") > cue_src.find("show_banner("), "show_cue calls show_banner only when no banner is showing; otherwise it queues")


## A function's source text: from its `func` line to the next top-level func (or the file's end).
func _func_src(src: String, head: String) -> String:
	var i := src.find(head)
	if i < 0:
		return ""
	var j := src.find("\nfunc ", i + 10)
	return src.substr(i, (j if j >= 0 else src.length()) - i)


## T1: the control legend. Open until a fort is taken, then a chip; only a left press on its header or
## chip toggles it; keys never do. The HUD names Game/ConfigDb, so it is checked by source text.
func _legend_tests(t: TestUtil) -> void:
	t.suite("raid_legend")
	t.ok(RaidLogic.legend_open_at_start(0) and not RaidLogic.legend_open_at_start(1) and not RaidLogic.legend_open_at_start(3),
		"open at 0 forts taken, collapsed after one or more")
	var cfg: Dictionary = TestUtil.load_json("res://configs/raid.json").get("hud", {}).get("legend", {})
	t.ok(cfg.has("_doc") and float(cfg.get("chip_h", 0)) >= 44.0 and float(cfg.get("key_px", 0)) >= 12.0 and float(cfg.get("row_px", 0)) >= 12.0,
		"hud.legend is documented, with a 44 px chip and text of at least 12 px")
	var l := RaidLegend.new()
	l.setup(cfg, true)
	t.ok(l.focus_mode == Control.FOCUS_NONE and l.mouse_filter == Control.MOUSE_FILTER_PASS, "no focus; the mouse passes through")
	t.ok(l.get_child_count() == 0, "no child controls")
	var open_h := l.size.y
	var open_w := l.size.x
	l.position = Vector2(18.0, 300.0)
	var bottom := l.position.y + l.size.y
	# row 2's centre from the legend's own layout: the header band (at least 44), half a gap, row 1 (key+10), gap, half of row 2
	var kp := float(cfg.get("key_px", 13))
	var gp := float(cfg.get("gap_px", 8))
	var hband := maxf(44.0, float(cfg.get("pad_px", 10)) + kp + 4.0 + gp * 0.5)
	var row2_y := hband + gp * 0.5 + kp + 10.0 + gp + (kp + 10.0) * 0.5
	var on_row2 := Vector2(open_w * 0.5, row2_y)
	t.ok(not l.classify(_mouse(MOUSE_BUTTON_LEFT, on_row2)), "a left press on the rows does not toggle")
	t.ok(l.classify(_mouse(MOUSE_BUTTON_LEFT, Vector2(open_w - 20.0, 14.0))), "a left press on the header toggles")
	t.ok(hband >= 44.0 and l.classify(_mouse(MOUSE_BUTTON_LEFT, Vector2(open_w * 0.5, 43.5))) and l.classify(_mouse(MOUSE_BUTTON_LEFT, Vector2(8.0, 0.5))),
		"the header's hit band is at least 44 px tall (the touch floor), top to bottom")
	t.ok(not l.classify(_mouse(MOUSE_BUTTON_LEFT, Vector2(open_w * 0.5, hband + gp * 0.5 + 2.0))), "a press just under the header, on the first row, does not toggle")
	l.toggle()
	t.ok(not l.is_open and l.size.y >= 44.0 and l.size.y < open_h, "collapsed: a chip at least 44 px tall, shorter than the plate")
	t.ok(is_equal_approx(l.position.y + l.size.y, bottom), "the bottom edge stays put when it collapses")
	var on_chip := l.size * 0.5
	var accept := InputEventAction.new()
	accept.action = &"ui_accept"
	accept.pressed = true
	var none := not l.classify(_mouse(MOUSE_BUTTON_RIGHT, on_chip)) and not l.classify(_mouse(MOUSE_BUTTON_LEFT, on_chip, false))
	for ev in [_key(KEY_SPACE), _key(KEY_ENTER), _key(KEY_ESCAPE), accept]:
		none = none and not l.classify(ev)
	t.ok(none, "a right press, a left release and Space, Enter, Esc, ui_accept never toggle")
	t.ok(l.classify(_mouse(MOUSE_BUTTON_LEFT, on_chip)), "a left press on the chip opens it")
	l.toggle()
	t.ok(l.is_open and is_equal_approx(l.size.y, open_h) and is_equal_approx(l.position.y + l.size.y, bottom), "reopened to the same plate, bottom edge fixed")
	l.free()
	var leg_src := FileAccess.get_file_as_string("res://scripts/raid/raid_legend.gd")
	var gi := leg_src.find("func _gui_input")
	var gbody := leg_src.substr(gi, leg_src.find("\nfunc ", gi + 10) - gi) if gi >= 0 else ""
	t.ok(gi >= 0 and RegEx.create_from_string("if classify\\(ev\\):\\s*accept_event\\(\\)").search(gbody) != null
		and gbody.count("accept_event()") == 1, "_gui_input accepts an event only inside `if classify(ev):`")
	var hud_src := FileAccess.get_file_as_string("res://scripts/raid/raid_hud.gd")
	t.ok(hud_src.contains("Game.state.view_hud().get(\"highest_tier_flipped\", 0)"), "the HUD reads highest_tier_flipped from view_hud()")
	var i := hud_src.find("RaidLegend.new()")
	t.ok(i > 0 and hud_src.substr(maxi(0, i - 400), 400).contains("if not boss_mode:"), "RaidLegend is built only when not boss_mode")
	t.ok(RegEx.create_from_string("_legend\\.visible = not raid\\._ended").search(hud_src) != null, "the legend hides once the run has ended")


## T3: a sleeping warden reads as a boss. Knobs in configs/raid.json; warden.gd needs Pulse/ConfigDb so
## it is checked by source text.
func _warden_presence_tests(t: TestUtil) -> void:
	t.suite("warden_presence")
	var w: Dictionary = TestUtil.load_json("res://configs/raid.json").get("wardens", {})
	var pc: Dictionary = w.get("presence", {})
	for k in ["ring_mult", "ring_alpha", "dash_gap_px", "tick_px", "plinth_y", "plinth_rx", "plinth_ry",
			"plinth_alpha", "name_px", "label_px", "plate_alpha", "plate_gap_px"]:
		t.ok(pc.has(k) and (pc[k] is float or pc[k] is int), "presence." + k + " is a number")
	t.ok(float(pc.get("ring_mult", 0.0)) > 1.5, "the boss ring stands well outside the body")
	for k in ["ring_alpha", "plinth_alpha", "plate_alpha"]:
		t.ok(float(pc.get(k, 0.0)) > 0.0 and float(pc.get(k, 0.0)) <= 1.0, k + " in (0, 1]")
	t.ok(float(pc.get("name_px", 0)) >= 12.0 and float(pc.get("label_px", 0)) >= 12.0, "plate text at least 12 px")
	# the name plate never sits under the HUD's top blocks (Ashgate's warden room is at the arena's top-left)
	var stats := Rect2(18, 14, 420, 290)
	var goal := Rect2(460, 10, 680, 140)
	t.ok(RaidLogic.plate_hidden(Rect2(420, 60, 160, 40), [stats, goal]), "a plate under the goal block is hidden")
	t.ok(RaidLogic.plate_hidden(Rect2(300, 200, 160, 40), [stats, Rect2()]), "a plate under the fort's StatBlock is hidden")
	t.ok(not RaidLogic.plate_hidden(Rect2(1060, 200, 170, 40), [stats, goal]), "a plate in the open is not")
	t.ok(not RaidLogic.plate_hidden(Rect2(420, 60, 160, 40), [Rect2()]), "an empty rect (no block showing) hides nothing")
	t.ok(is_equal_approx(RaidLogic.plate_nudge_x(Rect2(420, 265, 160, 60), [stats, goal], 8.0), 438.0 + 8.0 - 420.0),
		"a plate under the StatBlock's right edge slides right past it")
	t.ok(is_equal_approx(RaidLogic.plate_nudge_x(Rect2(1100, 60, 160, 40), [goal], 8.0), 1140.0 + 8.0 - 1100.0),
		"a plate over a block's right edge slides right past it")
	t.ok(is_equal_approx(RaidLogic.plate_nudge_x(Rect2(400, 60, 120, 40), [goal], 8.0), -(520.0 - 460.0 + 8.0)),
		"a plate over a block's left edge slides left past it")
	t.ok(RaidLogic.plate_nudge_x(Rect2(1060, 200, 170, 40), [stats, goal], 8.0) == 0.0, "a clear plate stays put")
	var wsrc := FileAccess.get_file_as_string("res://scripts/raid/warden.gd")
	var dp := _func_src(wsrc, "func _draw_presence(")
	t.ok(dp.contains("occluder_rects()") and dp.contains("RaidLogic.plate_hidden(") and dp.contains("_pres[\"both\"]") and dp.contains("RaidLogic.plate_nudge_x("),
		"the sleeping warden checks its name plate against the HUD's rects each draw, moves it below the ring and slides it clear")
	t.ok(float(w.get("dormant_alpha", 0.0)) >= 0.6, "the sleeping glyph is not faint")
	var src := FileAccess.get_file_as_string("res://scripts/raid/warden.gd")
	t.ok(RegEx.create_from_string("if not awake:\\s*_draw_presence\\(\\)").search(src) != null, "_draw calls _draw_presence only while asleep")
	var draw_body := _func_src(src, "func _draw_presence()")
	var body := _func_src(src, "func _build_presence(")   # the geometry, built once per zoom and cached
	t.ok(body.contains("wcfg().get(\"presence\""), "_build_presence reads presence from wcfg()")
	t.ok(body.contains("\"WARDEN\"") and body.contains("break it to take this fort"), "the plates say WARDEN and what breaking it does")
	t.ok(draw_body.contains("zoom()") and body.contains("/ z"), "sizes are held in screen px by the zoom")
	t.ok(draw_body.contains("_build_presence(z)") and not draw_body.contains("to_upper") and not draw_body.contains("get_string_size")
		and not draw_body.contains("PackedVector2Array()"), "the sleeping picture is cached: the per-frame draw builds no arrays and measures no text")
	t.ok(float(w.get("acolyte_dormant_alpha", 1.0)) <= 0.4 and float(w.get("acolyte_dormant_alpha", 1.0)) < float(w.get("dormant_alpha", 0.0)),
		"a sleeping acolyte is faint (its alpha is its only dormant cue)")
	var acolyte := FileAccess.get_file_as_string("res://scripts/raid/warden_acolyte.gd")
	t.ok(acolyte.contains("\"acolyte_dormant_alpha\"") and not acolyte.contains("get(\"dormant_alpha\""), "the acolyte reads acolyte_dormant_alpha, not the warden's")


## `src` without its `#` comments (a `#` inside a double-quoted string stays): source guards count code, not notes.
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


## The GoalBlock's row choice, the banner's step-down, the edge chevrons' clearance of the top-centre block, and
## the HUD's wiring to them (source text: raid_hud.gd names autoloads).
func _goal_rows_tests(t: TestUtil) -> void:
	t.suite("raid_goal_rows")
	var base := {"fort_name": "Old Sluice", "warden_name": "The Bellringer", "goal_px": 17, "route_px": 14, "row_px": 13}
	var held := base.duplicate()
	held["held"] = true
	held["warden_alive"] = true
	held["chest"] = true
	var r := RaidLogic.goal_rows(held)
	t.ok(r.size() == 1 and r[0]["text"] == RaidLogic.goal_line("Old Sluice", "", true) and r[0]["key"] == "vei" and r[0]["px"] == 17, "held: only the goal row, whatever else is true")
	var alive := base.duplicate()
	alive["warden_alive"] = true
	alive["route_text"] = "room 1 of 3 · the warden is 2 rooms on"
	alive["break_rows"] = ["BREAK x", "COUNTER y"]
	r = RaidLogic.goal_rows(alive)
	t.ok(r.size() == 4 and r[0]["text"] == RaidLogic.goal_line("Old Sluice", "The Bellringer", false) and r[1]["text"] == alive["route_text"] and r[1]["key"] == "text" and r[1]["px"] == 14,
		"warden alive: the goal, then the route")
	t.ok(r[2]["text"] == "BREAK x" and r[3]["text"] == "COUNTER y" and r[2]["key"] == "text_dim" and r[3]["px"] == 13, "then each break row, dim, at the row size")
	var chest := base.duplicate()
	chest["chest"] = true
	r = RaidLogic.goal_rows(chest)
	t.ok(r.size() == 2 and r[1]["text"] == RaidLogic.CHEST_ROW and r[1]["text"] == "open the chest to take the fort" and r[1]["px"] == 14, "warden down, chest standing: the goal and the chest row")
	t.ok(RaidLogic.goal_rows(base).is_empty(), "no warden, no chest, not held: no rows")
	var noarmy := alive.duplicate()
	noarmy["no_army"] = true
	r = RaidLogic.goal_rows(noarmy)
	t.ok(r.size() == 5 and r[4]["text"] == RaidLogic.NO_ARMY_LINE and r[4]["key"] == "danger", "the no-army row comes last")
	var empty_na := base.duplicate()
	empty_na["no_army"] = true
	t.ok(RaidLogic.goal_rows(empty_na).is_empty(), "the no-army row alone never shows")
	var held_na := held.duplicate()
	held_na["no_army"] = true
	t.ok(RaidLogic.goal_rows(held_na).size() == 2, "a held raid with no army: goal and the no-army row")
	# the banner steps down under the block that shows
	t.ok(RaidLogic.banner_top(116.0, false, 200.0) == 116.0, "no block: the banner stays at its base")
	t.ok(RaidLogic.banner_top(116.0, true, 62.0) == 130.0, "a base-height block: 14 px down")
	t.ok(RaidLogic.banner_top(116.0, true, 100.0) == 168.0, "a taller block: 14 px plus the extra height")
	t.ok(RaidLogic.banner_top(116.0, true, 40.0) == 130.0, "a block shorter than the base never lifts it")
	# edge chevrons clear of the top-centre block
	var view := Vector2(1280.0, 720.0)
	var blk := Rect2(300.0, 10.0, 680.0, 62.0)
	var lab := Rect2(Vector2(600.0, 60.0), Vector2(40.0, 16.0))
	var p := Vector2(640.0, 34.0)
	var q := RaidLogic.edge_clear_of(p, lab, blk, view)
	t.ok(is_equal_approx(q.x, 640.0) and q.y >= blk.end.y + 12.0, "a straight-up chevron under the block drops below its bottom edge, same x")
	t.ok(RaidLogic.edge_clear_of(Vector2(100.0, 34.0), Rect2(Vector2(80.0, 60.0), Vector2(40.0, 16.0)), blk, view) == Vector2(100.0, 34.0), "a chevron beside the block stays")
	t.ok(RaidLogic.edge_clear_of(Vector2(640.0, 34.0), lab, Rect2(), view) == Vector2(640.0, 34.0), "no block: nothing moves")
	t.ok(RaidLogic.edge_clear_of(Vector2(1000.0, 640.0), Rect2(Vector2(980.0, 666.0), Vector2(40.0, 16.0)), blk, view) == Vector2(1000.0, 640.0), "a chevron on the bottom edge stays")
	var lab_in := Rect2(Vector2(700.0, 70.0), Vector2(40.0, 16.0))   # the block ends at y 72: the label's top 2 px are under it
	var q2 := RaidLogic.edge_clear_of(Vector2(720.0, 100.0), lab_in, blk, view)
	t.ok(q2 == Vector2(720.0, blk.end.y + RaidLogic.EDGE_BELOW), "a label that reaches into the block moves the chevron just below it")
	var edge_l := RaidLogic.edge_clear_of(Vector2(10.0, 20.0), Rect2(Vector2(0.0, 40.0), Vector2(40.0, 16.0)), Rect2(0.0, 0.0, 400.0, 62.0), view)
	t.ok(edge_l.x >= RaidLogic.EDGE_INSET and edge_l.y >= 62.0, "the moved chevron is clamped into the view's inset")
	var tall := RaidLogic.edge_clear_of(Vector2(640.0, 34.0), lab, Rect2(300.0, 0.0, 680.0, 900.0), view)
	t.ok(tall.y <= view.y - RaidLogic.EDGE_INSET, "a block taller than the view never pushes it off screen")
	# the HUD's wiring
	var hs := FileAccess.get_file_as_string("res://scripts/raid/raid_hud.gd")
	var hcode := _code(hs)
	t.ok(_func_src(hcode, "func _update_goal(").contains("RaidLogic.goal_rows(") and not hcode.contains("open the chest to take the fort"), "the GoalBlock's rows come from RaidLogic.goal_rows; the chest row is RaidLogic.CHEST_ROW")
	t.ok(hcode.contains("RaidLogic.banner_top(") and hcode.contains("func top_block_rect() -> Rect2"), "the banner steps down by RaidLogic.banner_top under top_block_rect()")
	var edge_i := hcode.find("func _edge(")
	var edge_src := hcode.substr(edge_i, hcode.find("\n\tfunc ", edge_i + 10) - edge_i)
	t.ok(edge_src.contains("RaidLogic.edge_clear_of(") and hcode.contains("hud.top_block_rect()"), "the edge chevrons clear the top-centre block")
	var tick := _func_src(hcode, "func _tick_goal(")
	t.ok(tick.find("_goal_block.visible = false") >= 0 and tick.find("return") >= 0 and tick.find("return") < tick.find("_update_goal()"), "the goal rows are not rebuilt while the block is hidden")
	t.ok(_func_src(hcode, "func refresh(").contains("_retreat.refresh_lines(_retreat_lines())"), "the open retreat panel's lines refresh from the HUD")


## The cards' shared skip rule: any mouse press, a non-echo Space, Enter or keypad Enter, and only past the gate.
func _card_skip_tests(t: TestUtil) -> void:
	t.suite("raid_card_skips")
	var gate := 0.8
	for code in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER]:
		t.ok(RaidLogic.card_skips(_key(code), gate, gate), "key %d skips at the gate" % code)
		t.ok(not RaidLogic.card_skips(_key(code), gate - 0.01, gate), "key %d never skips before the gate" % code)
		var echo := _key(code)
		echo.echo = true
		t.ok(not RaidLogic.card_skips(echo, 5.0, gate), "an echo of key %d never skips" % code)
		t.ok(not RaidLogic.card_skips(_key(code, false), 5.0, gate), "a release of key %d never skips" % code)
	for b in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
		t.ok(RaidLogic.card_skips(_mouse(b, Vector2.ZERO), 1.0, gate), "mouse button %d skips" % b)
		t.ok(not RaidLogic.card_skips(_mouse(b, Vector2.ZERO), 0.1, gate), "mouse button %d never skips before the gate" % b)
		t.ok(not RaidLogic.card_skips(_mouse(b, Vector2.ZERO, false), 1.0, gate), "a release of mouse button %d never skips" % b)
	t.ok(not RaidLogic.card_skips(_key(KEY_A), 5.0, gate) and not RaidLogic.card_skips(_key(KEY_ESCAPE), 5.0, gate), "other keys never skip")
	t.ok(not RaidLogic.card_skips(InputEventMouseMotion.new(), 5.0, gate), "mouse motion never skips")


func _key(code: Key, pressed := true) -> InputEventKey:
	var k := InputEventKey.new()
	k.keycode = code
	k.physical_keycode = code
	k.pressed = pressed
	return k


func _mouse(button: MouseButton, pos: Vector2, pressed := true) -> InputEventMouseButton:
	var m := InputEventMouseButton.new()
	m.button_index = button
	m.position = pos
	m.global_position = pos
	m.pressed = pressed
	return m


## Item 8: the cac5a17 ConfirmationDialog focused its OK button, and Space (the trance key) is also
## ui_accept, so one Space press confirmed a retreat. The panel takes no focus and only a left click on
## RETREAT confirms.
func _retreat_panel_tests(t: TestUtil) -> void:
	t.suite("raid_retreat_panel")
	var p := RaidRetreatPanel.new()
	p.open(PackedStringArray(["a", "b", "c"]))
	var got := []
	p.chosen.connect(func(go: bool) -> void: got.append(go))
	t.ok(p.focus_mode == Control.FOCUS_NONE, "the panel never takes focus")
	t.ok(p.mouse_filter == Control.MOUSE_FILTER_PASS, "the panel passes the mouse on: only its left-button events are accepted")
	t.ok(p.get_child_count() == 0, "no child controls (no Button to focus and press with ui_accept)")
	t.ok(p.is_open() and p.retreat_rect().size.y >= 44.0 and p.stay_rect().size.y >= 44.0, "open, with 44 px buttons")
	var on_retreat := p.retreat_rect().get_center()
	var accept := InputEventAction.new()
	accept.action = &"ui_accept"
	accept.pressed = true
	var keys := [_key(KEY_SPACE), _key(KEY_ENTER), _key(KEY_KP_ENTER), _key(KEY_ESCAPE), accept]
	var none := true
	for ev in keys:
		none = none and p.classify(ev) == ""
	t.ok(none, "no key confirms: Space, Enter, keypad Enter, Esc and the ui_accept action all classify as nothing")
	for ev in keys:
		p.apply(p.classify(ev))
	t.ok(got.is_empty() and p.is_open(), "applied, the keys neither retreat nor close it")
	t.ok(p.classify(_mouse(MOUSE_BUTTON_RIGHT, on_retreat)) == "", "a right click on RETREAT does nothing (right mouse is the trance)")
	t.ok(p.classify(_mouse(MOUSE_BUTTON_LEFT, on_retreat, false)) == "", "a left release on RETREAT does nothing")
	t.ok(p.classify(_mouse(MOUSE_BUTTON_LEFT, Vector2(2, 2))) == "", "a left click on the plate, off the buttons, does nothing")
	t.ok(p.classify(_mouse(MOUSE_BUTTON_LEFT, p.stay_rect().get_center())) == "stay", "a left click on STAY stays")
	p.apply(p.classify(_mouse(MOUSE_BUTTON_LEFT, p.stay_rect().get_center())))
	t.ok(got == [false] and not p.is_open(), "STAY closes the panel and says stay")
	p.open(PackedStringArray(["a"]))
	p.apply(p.classify(_mouse(MOUSE_BUTTON_LEFT, p.retreat_rect().get_center())))
	t.ok(got == [false, true] and not p.is_open(), "a left click on RETREAT is the one way to retreat")
	p.apply("retreat")
	t.ok(got.size() == 2, "a closed panel ignores a late choice")
	t.ok(RaidRetreatPanel.is_stay_key(_key(KEY_SPACE)) and RaidRetreatPanel.is_stay_key(_key(KEY_ESCAPE))
		and RaidRetreatPanel.is_stay_key(_mouse(MOUSE_BUTTON_RIGHT, Vector2.ZERO)), "Space, Esc and right mouse are stay keys")
	t.ok(not RaidRetreatPanel.is_stay_key(_key(KEY_SPACE, false)) and not RaidRetreatPanel.is_stay_key(_mouse(MOUSE_BUTTON_LEFT, Vector2.ZERO)),
		"a release, or a left click, is not a stay key")
	# the plate fits its lines each time it opens: a 3-line open after a 4-line one is shorter
	p.open(PackedStringArray(["a", "b", "c", "d"]))
	var h4 := p.size.y
	p.open(PackedStringArray(["a", "b", "c"]))
	t.ok(p.size.y < h4 and is_equal_approx(h4 - p.size.y, RaidRetreatPanel.LINE_H), "open with 4 lines then 3: the plate shrinks by a line (%.0f -> %.0f)" % [h4, p.size.y])
	t.ok(p.retreat_rect().end.y <= p.size.y and p.stay_rect().end.y <= p.size.y, "the buttons stay inside the shrunk plate")
	# its lines follow a pickup while it shows (the HUD calls this 4 times a second), and only when they change
	p.refresh_lines(PackedStringArray(["a", "b", "c", "d"]))
	t.ok(is_equal_approx(p.size.y, h4), "refreshed with a 4th line: the plate grows to fit")
	var same_rect := p.retreat_rect()
	p.refresh_lines(PackedStringArray(["a", "b", "c", "d"]))
	t.ok(p.retreat_rect() == same_rect and p.lines.size() == 4, "the same lines change nothing")
	p.close()
	p.refresh_lines(PackedStringArray(["x"]))
	t.ok(p.lines.size() == 4, "a closed panel ignores a refresh")
	# hover clears when the mouse leaves the plate
	p.open(PackedStringArray(["a"]))
	var mv := InputEventMouseMotion.new()
	mv.position = p.stay_rect().get_center()
	p._gui_input(mv)
	t.ok(p._hover == "stay", "hovering STAY marks it")
	p.notification(Control.NOTIFICATION_MOUSE_EXIT)
	t.ok(p._hover == "", "the mouse leaving the plate clears the hover")
	p.free()
	# a right press and motion are not accepted by the panel or the RETREAT button, so they reach the raid
	var panel_src := FileAccess.get_file_as_string("res://scripts/raid/raid_retreat_panel.gd")
	var pgi := _func_src(panel_src, "func _gui_input(")
	t.ok(RegEx.create_from_string("if ev is InputEventMouseButton and [^\\n]*MOUSE_BUTTON_LEFT and ev\\.pressed:\\s*(#[^\\n]*)?\\s*accept_event\\(\\)").search(pgi) != null
		and _code(pgi).count("accept_event()") == 1 and panel_src.contains("mouse_filter = Control.MOUSE_FILTER_PASS") and not _code(panel_src).contains("MOUSE_FILTER_STOP"),
		"the panel is MOUSE_FILTER_PASS and accepts only a left press (a loop released over it still ends)")
	var hud_code := _code(FileAccess.get_file_as_string("res://scripts/raid/raid_hud.gd"))
	var exit_src := hud_code.substr(hud_code.find("class ExitButton:"))
	exit_src = exit_src.substr(0, exit_src.find("\nclass ", 10))
	var egi := _func_src(exit_src, "func _gui_input(")
	t.ok(_func_src(exit_src, "func _init(").contains("mouse_filter = Control.MOUSE_FILTER_PASS") and not exit_src.contains("MOUSE_FILTER_STOP")
		and egi.contains("MOUSE_BUTTON_LEFT and ev.pressed") and egi.count("accept_event()") == 1,
		"the RETREAT button is MOUSE_FILTER_PASS and accepts only its own left press")
	# source guards: no dialog anywhere in the raid that a key could confirm; the raid closes the panel on a stay key
	var dialogs := []
	var made := RegEx.create_from_string("(ConfirmationDialog|AcceptDialog)\\.new\\(|:\\s*(ConfirmationDialog|AcceptDialog)\\b|extends\\s+(ConfirmationDialog|AcceptDialog)")
	var dir := DirAccess.open("res://scripts/raid")
	for f in dir.get_files():
		if f.ends_with(".gd") and made.search(FileAccess.get_file_as_string("res://scripts/raid/" + f)) != null:
			dialogs.append(f)
	t.ok(dialogs.is_empty(), "no ConfirmationDialog or AcceptDialog in scripts/raid (found: %s)" % str(dialogs))
	var raid_src := FileAccess.get_file_as_string("res://scripts/raid/raid.gd")
	t.ok(RegEx.create_from_string("retreat_open\\(\\) and RaidRetreatPanel\\.is_stay_key\\(ev\\):\\s*hud\\.close_retreat\\(\\)").search(raid_src) != null,
		"the raid closes the panel on a stay key before the trance reads it")
	var hud_src := FileAccess.get_file_as_string("res://scripts/raid/raid_hud.gd")
	t.ok(hud_src.contains("raid.endings.try_retreat(\"click\")"), "the panel's RETREAT is labelled a click for the capture")
	var cap_src := FileAccess.get_file_as_string("res://scripts/raid/raid_capture.gd")
	t.ok(cap_src.contains("\"retreat_by\": _raid.endings.retreat_by"), "the capture row carries the retreat trigger")


## Item 6: the panel says what a retreat keeps (as counts) and what stays, in the glossary's words.
func _retreat_line_tests(t: TestUtil) -> void:
	t.suite("raid_retreat_lines")
	var keep := RaidLogic.loot_counts(RaidLogic.loot_snapshot({"relics": 2, "husks": [{"kind": "skeleton"}]}, 5))
	var l := RaidLogic.retreat_lines(false, keep, "")
	t.ok(l[0] == "You keep everything you found and all carried essence.", "first: what you keep")
	t.ok(l[1].contains("relics 2") and l[1].contains("husks 1") and l[1].contains("essence 5"), "then the counts a retreat pays")
	t.ok(l[2].begins_with("The fort stays Vei's") and l.size() == 3, "then what stays: the fort stays Vei's")
	var e := RaidLogic.retreat_lines(true, RaidLogic.loot_counts(RaidLogic.empty_loot()), "\nBone Knight is on the plate · lost if you retreat.")
	t.ok(e[1].contains("nothing yet"), "nothing found: 'nothing yet'")
	t.ok(e[2] == "The fort stays yours.", "a held fort stays yours")
	t.ok(e.size() == 4 and e[3] == "Bone Knight is on the plate · lost if you retreat.", "the held door's line, without its newline")
	var paid := RaidLogic.loot_counts(RaidLogic.result_loot("retreated", false, {"relics": 2, "husks": [{"kind": "skeleton"}]}, 5, {}))
	t.ok(paid["relics"] == keep["relics"] and paid["husks"] == keep["husks"] and paid["essence"] == keep["essence"],
		"the counts shown are what result_loot pays a retreat")
