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
	_round2_tests(t)
	_contrast_tests(t)
	_goal_compact_tests(t)
	return t.failures


## A stand-in for a RaidUnit (the fields the counter filter reads).
class FakeUnit:
	extends RefCounted
	var alive := true
	var kind := "big"
	var role := "party"
	var beef := 0.0
	var speed_stat := 0.0
	var wits := 0.0
	var power := 0.0


func _fake(kind := "big", role := "party", beef := 0.0, alive := true) -> FakeUnit:
	var u := FakeUnit.new()
	u.kind = kind
	u.role = role
	u.beef = beef
	u.alive = alive
	return u


## Clarity round 2, task A: the counter advice, the retreat panel's two columns, the undead hint, the uses line,
## the PHYLACT. explanation.
func _round2_tests(t: TestUtil) -> void:
	t.suite("raid_clarity_r2")
	# A1: the counter line sends a player with no big to the Crypt slab, never to "raise more undead"
	var sp := {"weak_point": {"stat": "beef", "threshold": 6.0, "effect": "muffle"}}
	t.ok(WardenLogic.counter_line(sp, []).ends_with(" · you have none: make one at the Crypt slab"), "no bigs: make one at the Crypt slab")
	t.ok(WardenLogic.counter_line(sp, [5.0]).ends_with(" · none in your party: make one at the Crypt slab"), "bigs but none meets it: make one at the Crypt slab")
	t.ok(WardenLogic.counter_line(sp, [6.0, 2.0]).ends_with(" · 1 in your party") and not WardenLogic.counter_line(sp, [6.0]).contains("Crypt"), "k meet it: the count, no advice")
	t.ok(not WardenLogic.counter_line(sp, []).contains("raise more undead"), "the counter line never says raise more undead")
	var holder := _fake("big", "party", 9.0)
	var pool := [_fake("big", "party", 7.0), _fake("chaff", "party", 99.0), _fake("big", "raised", 99.0), _fake("big", "party", 8.0, false), holder, _fake("big", "party", 3.0)]
	var vals := RaidLogic.counter_party_values(pool, "beef", holder)
	t.ok(vals == [7.0, 3.0], "counter pool: living party bigs only, not a non-big, a raised big, a dead one or the door's holder (%s)" % str(vals))
	t.ok(RaidLogic.counter_party_values(pool, "beef", null).size() == 3, "no holder: the holder counts")
	var hsrc := FileAccess.get_file_as_string("res://scripts/raid/raid_hud.gd")
	t.ok(_func_src(hsrc, "static func break_rows(").contains("RaidLogic.counter_party_values("), "break_rows reads the counter pool helper")
	# A2: the retreat panel's two columns
	var keep := RaidLogic.loot_counts({"relics": 2, "husks": [{}], "essence": 5})
	var left := RaidLogic.retreat_keep_lines(false, keep, "")
	t.ok(left[0]["text"] == "You keep everything you found and all carried essence." and left[1]["text"].contains("relics 2") and left[1]["text"].contains("essence 5"), "left: what you keep, as counts")
	t.ok(left[left.size() - 1]["text"] == "The fort stays Vei's · you can come back and break its warden.", "left: the fort stays Vei's")
	var empty := RaidLogic.retreat_keep_lines(true, RaidLogic.loot_counts(RaidLogic.empty_loot()), "\nBone Knight is on the plate · lost if you retreat.")
	t.ok(empty.size() == 4 and empty[1]["text"].contains("nothing found yet") and not empty[1]["text"].contains("now:"), "nothing found: plain words, no uses line")
	t.ok(empty[2]["text"] == "The fort stays yours." and empty[3]["text"].begins_with("Bone Knight is on the plate"), "a held raid: the fort stays yours, then the door line")
	t.ok(left[2]["text"] == RaidLogic.loot_uses_line(keep) and left[2]["key"] == "text_dim", "the uses line sits under the counts, dim")
	var ub := {"relics": 1, "essence": 4}
	var next_unmade := RaidLogic.death_next_row({"death_ends": {"outcome": "unmade", "respawn_s": 600.0}})
	var fall := RaidLogic.retreat_fall_lines(0, ub, 2, next_unmade)
	var card := RaidLogic.death_card_rows("x", {}, ub, 2, "", next_unmade)
	t.ok(fall.size() == 2 and fall[0]["text"].ends_with(card[card.size() - 2]["text"]) and fall[1]["text"].ends_with(card[card.size() - 1]["text"]) and fall[1]["text"].contains("unmade · reforms in 10:00"),
		"right: LOST and AFTER are the death card's own rows (%s)" % str(fall))
	# I2: a big shut in at the cache is the death card's own SHUT IN row, before AFTER
	var fall_s := RaidLogic.retreat_fall_lines(0, ub, 1, next_unmade, "Old Gristle")
	var card_s := RaidLogic.death_rows_with_shut(RaidLogic.death_card_rows("x", {}, ub, 1, "", next_unmade), "Old Gristle")
	var fall_ok := fall_s.size() == 3 and card_s.size() >= 3
	for i in mini(fall_s.size(), 3):
		var cr: Dictionary = card_s[card_s.size() - 3 + i]   # the card's LOST, SHUT IN, AFTER rows
		fall_ok = fall_ok and str(fall_s[i]["text"]).ends_with(str(cr["text"])) and fall_s[i]["key"] == cr["key"]
	fall_ok = fall_ok and str(fall_s[1]["text"]) == "SHUT IN · " + str(card_s[card_s.size() - 2]["text"])
	t.ok(fall_ok and fall_s[1]["text"].begins_with("SHUT IN · Old Gristle"), "right, a shut-in big: LOST, SHUT IN, AFTER are the death card's rows (%s)" % str(fall_s))
	t.ok(str(RaidLogic.retreat_fall_lines(0, ub, 1, next_unmade, "")) == str(RaidLogic.retreat_fall_lines(0, ub, 1, next_unmade)), "no shut-in big: the column is unchanged")
	t.ok(RaidLogic.retreat_fall_lines(1, ub, 1, next_unmade, "Old Gristle").size() == 1, "a charge left still replaces the column")
	t.ok(RaidLogic.retreat_fall_lines(0, {}, 0, next_unmade)[0]["text"].ends_with("nothing"), "nothing at stake reads nothing")
	var rev := RaidLogic.retreat_fall_lines(1, ub, 2, next_unmade)
	t.ok(rev.size() == 1 and rev[0]["text"] == "a phylactery charge revives her here (at most once per dungeon)", "a charge left: the revive line, no LOST or AFTER")
	t.ok(RaidLogic.RETREAT_HEAD == "RETREAT NOW" and RaidLogic.FALL_HEAD == "IF RELISH FALLS", "the column heads")
	var rl := _func_src(hsrc, "func _retreat_lines(")
	t.ok(rl.contains("di[\"shut\"]"), "the retreat panel passes the death card's shut-in big")
	t.ok(rl.contains("RaidLogic.retreat_fall_lines(") and rl.contains("death_inputs()") and rl.contains("RaidLogic.retreat_keep_lines("), "the HUD builds both columns from the endings' own death inputs")
	var esrc := FileAccess.get_file_as_string("res://scripts/raid/raid_endings.gd")
	t.ok(_func_src(esrc, "func death_rows(").contains("death_inputs()") and _func_src(esrc, "func death_inputs(").contains("RaidLogic.unbanked("), "the death card reads the same death_inputs")
	var rcfg: Dictionary = TestUtil.load_json("res://configs/raid.json").get("hud", {}).get("retreat", {})
	t.ok(rcfg.has("_doc") and float(rcfg.get("btn_h", 0)) >= 44.0 and int(rcfg.get("line_px", 0)) >= 13, "hud.retreat: doc, 44 px buttons, no text under 13 px")
	var p := RaidRetreatPanel.new()
	p.configure(rcfg)
	p.open([left, fall])
	t.ok(p.size.x >= 700.0 and p.retreat_rect().size.y >= 44.0 and p.retreat_rect().end.y <= p.size.y, "two columns: the panel is wide, its buttons stay inside")
	var h_fall := p.size.y
	p.open([_cl(["a"]), rev])
	t.ok(p.size.y < h_fall, "a shorter pair of columns: a shorter plate (%.0f vs %.0f)" % [p.size.y, h_fall])
	p.free()
	# A3: the undead line under the idle hint until the first raise
	t.ok(RaidLogic.hint_sub_text(false, false, false) == RaidLogic.HINT_IDLE_SUB and RaidLogic.HINT_IDLE_SUB == "your undead fight on their own · keep Relish safe and raise more", "idle, no raise yet: the second line")
	t.ok(RaidLogic.hint_sub_text(false, false, true) == "", "after the first raise: one line")
	t.ok(RaidLogic.hint_sub_text(true, false, false) == "" and RaidLogic.hint_sub_text(false, true, false) == "", "the trance and exit hints take the line alone")
	t.ok(hsrc.contains("RaidLogic.hint_sub_text(raid.trance_active, at_exit, raid.first_raise_done)"), "the HUD picks the second line with the helper")
	# A4: PHYLACT. explanation and the loot uses
	t.ok(RaidLogic.phylactery_meaning(0) == PackedStringArray(["revives Relish in place, at most once per dungeon.", "The Ossuary Tower crafts it from essence."]), "no charge: the Jargon line in two rows")
	t.ok(RaidLogic.phylactery_meaning(2) == PackedStringArray(["a death here revives her in place, once"]), "charges: one row, what one does now")
	for n in [0, 2]:
		for m in RaidLogic.phylactery_meaning(n):
			t.ok(ThemeDB.fallback_font.get_string_size(m, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x <= 320.0, "PHYLACT. meaning (%d) row fits the value column at 13 px: %s" % [n, m])
	t.ok(RaidLogic.loot_uses_line(RaidLogic.loot_counts({})) == "", "no loot: no uses line")
	t.ok(RaidLogic.loot_uses_line(RaidLogic.loot_counts({"blueprints": [{}]})) == "", "blueprints alone: no use line")
	var all := RaidLogic.loot_uses_line(RaidLogic.loot_counts({"relics": 1, "husks": [{}], "remnants": [{}], "essence": 2}))
	var husk := "husk: the frame a big undead is raised in · lay it on the crypt slab and slot remnants to shape it"
	t.ok(all == "relics are spent when you build · " + husk + " · essence pays for backups (Ossuary Tower)", "every kind: relics, the husk piece only, essence (%s)" % all)
	t.ok(RaidLogic.loot_uses_line(RaidLogic.loot_counts({"husks": [{}]})) == husk, "husks alone: the Jargon husk line")
	t.ok(RaidLogic.loot_uses_line(RaidLogic.loot_counts({"remnants": [{}]})) == "remnants feed the crypt slab, which raises big undead", "remnants without husks: the glossary's loot sentence")
	var cr := RaidLogic.clear_card_rows("X", RaidLogic.loot_counts({"relics": 1}))
	t.ok(cr.size() == 5 and cr[3]["label"] == "USE" and cr[3]["key"] == "text_dim" and cr[4]["label"] == "NEXT", "the clear card: a dim USE row after LOOT")
	t.ok(RaidLogic.clear_card_rows("X", RaidLogic.loot_counts({})).size() == 4, "nothing found: no USE row")
	var dc: Dictionary = RaidLogic.DEATH_CARD
	var vw := float(dc["w"]) - 2.0 * float(dc["pad"]) - float(dc["label_w"])
	var worst := ThemeDB.fallback_font.get_multiline_string_size(all, HORIZONTAL_ALIGNMENT_LEFT, vw, int(dc["value_px"]))
	t.ok(worst.y <= 5.0 * float(dc["value_px"]) * 1.4, "the longest USE text wraps to at most 5 lines on the card (%.0f px tall)" % worst.y)


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
	t.ok(labels == ["BROKEN", "TAKEN", "LOOT", "USE", "NEXT"], "the rows in order (USE: what the loot is for)")
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
			t.ok(WardenLogic.counter_line(sp, []) == base + " · you have none: make one at the Crypt slab", "%s: the counter line, no bigs" % tag)
			t.ok(WardenLogic.counter_line(sp, [thr - 1, 0]) == base + " · none in your party: make one at the Crypt slab", "%s: the counter line, none meets it" % tag)
			t.ok(WardenLogic.counter_line(sp, [thr, thr + 3, thr - 1]) == base + " · 2 in your party", "%s: the counter line, 2 of 3 meet it" % tag)
			# I1: every wrapped break row fits the awake block's plate (680 px less its 12 px insets), at 13 px
			var inner := RaidLogic.WARDEN_BLOCK_W - 2.0 * RaidLogic.WARDEN_BLOCK_INSET
			for vals in [[], [thr - 1], [thr]]:
				var rows: Array = [WardenLogic.break_line(sp, shown)]
				if tk != "":
					rows.append(tk)
				rows.append(WardenLogic.counter_line(sp, vals))
				var wrapped := RaidLogic.wrap_break_rows(rows, ThemeDB.fallback_font, RaidLogic.BREAK_ROW_PX, inner)
				var widest := 0.0
				for ln in wrapped:
					widest = maxf(widest, ThemeDB.fallback_font.get_string_size(ln, HORIZONTAL_ALIGNMENT_LEFT, -1, RaidLogic.BREAK_ROW_PX).x)
				t.ok(wrapped.size() >= rows.size() and widest <= inner, "%s %s: wrapped break rows fit the plate (%d lines, widest %.0f of %.0f px)" % [tag, str(vals), wrapped.size(), widest, inner])
	t.ok(RaidLogic.wrap_break_rows(["a", "b"], ThemeDB.fallback_font, 13, 600.0) == PackedStringArray(["a", "b"]), "short break rows stay one line each")
	t.ok(RaidLogic.wrap_break_rows(["COUNTER · a big undead with beef 6+ snuffs an acolyte in one blow · you have none: make one at the Crypt slab"], ThemeDB.fallback_font, 13, 656.0).size() >= 2,
		"the long Pyre-priest counter row wraps")
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


## An inner-class method's source (one tab in): up to the next method, inner or top-level, or `stop` at most.
func _inner_src(src: String, head: String, from := 0) -> String:
	var i := src.find(head, from)
	if i < 0:
		return ""
	var j1 := src.find("\n\tfunc ", i + 10)
	var j2 := src.find("\nfunc ", i + 10)
	var j := j1 if j2 < 0 or (j1 >= 0 and j1 < j2) else j2
	return src.substr(i, (j if j >= 0 else src.length()) - i)


## T1: the control legend. Open until a fort is taken, then a chip; only a left press on its header or
## chip toggles it; keys never do. The HUD names Game/ConfigDb, so it is checked by source text.
func _legend_tests(t: TestUtil) -> void:
	t.suite("raid_legend")
	t.ok(RaidLogic.legend_open_at_start(0) and not RaidLogic.legend_open_at_start(1) and not RaidLogic.legend_open_at_start(3),
		"open at 0 forts taken, collapsed after one or more")
	var cfg: Dictionary = TestUtil.load_json("res://configs/raid.json").get("hud", {}).get("legend", {})
	t.ok(cfg.has("_doc") and float(cfg.get("chip_h", 0)) >= 44.0 and float(cfg.get("key_px", 0)) >= 14.0 and float(cfg.get("row_px", 0)) >= 15.0 and float(cfg.get("plate_alpha", 0)) >= 0.96,
		"hud.legend is documented, with a 44 px chip, 15/14 px rows and keys, and a plate of at least 0.96")
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
## A column of plain lines for the panel: [{text, key}].
func _cl(texts: Array) -> Array:
	var out: Array = []
	for s in texts:
		out.append({"text": str(s), "key": "text"})
	return out


func _retreat_panel_tests(t: TestUtil) -> void:
	t.suite("raid_retreat_panel")
	var p := RaidRetreatPanel.new()
	p.open([_cl(["a", "b", "c"]), _cl(["d"])])
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
	p.open([_cl(["a"]), _cl(["b"])])
	p.apply(p.classify(_mouse(MOUSE_BUTTON_LEFT, p.retreat_rect().get_center())))
	t.ok(got == [false, true] and not p.is_open(), "a left click on RETREAT is the one way to retreat")
	p.apply("retreat")
	t.ok(got.size() == 2, "a closed panel ignores a late choice")
	t.ok(RaidRetreatPanel.is_stay_key(_key(KEY_SPACE)) and RaidRetreatPanel.is_stay_key(_key(KEY_ESCAPE))
		and RaidRetreatPanel.is_stay_key(_mouse(MOUSE_BUTTON_RIGHT, Vector2.ZERO)), "Space, Esc and right mouse are stay keys")
	t.ok(not RaidRetreatPanel.is_stay_key(_key(KEY_SPACE, false)) and not RaidRetreatPanel.is_stay_key(_mouse(MOUSE_BUTTON_LEFT, Vector2.ZERO)),
		"a release, or a left click, is not a stay key")
	# the plate fits its lines each time it opens: a 3-line open after a 4-line one is shorter
	p.open([_cl(["a", "b", "c", "d"]), _cl(["e"])])
	var h4 := p.size.y
	p.open([_cl(["a", "b", "c"]), _cl(["e"])])
	t.ok(p.size.y < h4 and is_equal_approx(h4 - p.size.y, p.line_h), "open with 4 lines then 3: the plate shrinks by a line (%.0f -> %.0f)" % [h4, p.size.y])
	t.ok(p.retreat_rect().end.y <= p.size.y and p.stay_rect().end.y <= p.size.y, "the buttons stay inside the shrunk plate")
	# its lines follow a pickup while it shows (the HUD calls this 4 times a second), and only when they change
	p.refresh_lines([_cl(["a", "b", "c", "d"]), _cl(["e"])])
	t.ok(is_equal_approx(p.size.y, h4), "refreshed with a 4th line: the plate grows to fit")
	var same_rect := p.retreat_rect()
	p.refresh_lines([_cl(["a", "b", "c", "d"]), _cl(["e"])])
	t.ok(p.retreat_rect() == same_rect and (p.cols[0] as Array).size() == 4, "the same lines change nothing")
	p.close()
	p.refresh_lines([_cl(["x"]), _cl(["y"])])
	t.ok((p.cols[0] as Array).size() == 4, "a closed panel ignores a refresh")
	# hover clears when the mouse leaves the plate
	p.open([_cl(["a"]), _cl(["b"])])
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
	var l := RaidLogic.retreat_keep_lines(false, keep, "")
	t.ok(l[0]["text"] == "You keep everything you found and all carried essence.", "first: what you keep")
	t.ok(l[1]["text"].contains("relics 2") and l[1]["text"].contains("husks 1") and l[1]["text"].contains("essence 5"), "then the counts a retreat pays")
	t.ok(l[l.size() - 1]["text"].begins_with("The fort stays Vei's") and l.size() == 4, "then what stays: the fort stays Vei's (the uses line sits between)")
	var e := RaidLogic.retreat_keep_lines(true, RaidLogic.loot_counts(RaidLogic.empty_loot()), "\nBone Knight is on the plate · lost if you retreat.")
	t.ok(e[1]["text"].contains("nothing found yet"), "nothing found: 'nothing found yet'")
	t.ok(e[2]["text"] == "The fort stays yours.", "a held fort stays yours")
	t.ok(e.size() == 4 and e[3]["text"] == "Bone Knight is on the plate · lost if you retreat.", "the held door's line, without its newline")
	var paid := RaidLogic.loot_counts(RaidLogic.result_loot("retreated", false, {"relics": 2, "husks": [{"kind": "skeleton"}]}, 5, {}))
	t.ok(paid["relics"] == keep["relics"] and paid["husks"] == keep["husks"] and paid["essence"] == keep["essence"],
		"the counts shown are what result_loot pays a retreat")


# ----------------------------------------------------------------------------------------------------------
# Clarity round 2, task B: contrast measured on every raid HUD plate, the compact goal block, small text.

## The brightest things the world can put under a HUD plate (cream wall lines, essence motes, the undead and
## the living's cores): the worst of them is what a plate's ink must survive.
const WORLD_BRIGHT := ["vei", "essence", "undead", "living_core", "undead_core"]
const TEXT_MIN := 4.5
const LINE_MIN := 3.0


## Every Palette.c("key" literal in `src` must be `ground` or in `keys`, so a new colour on a plate is a new
## line in the contrast test.
func _guard_keys(t: TestUtil, name: String, src: String, keys: Array) -> void:
	var re := RegEx.create_from_string("Palette\\.c\\(\"(\\w+)\"")
	var bad := PackedStringArray()
	for m in re.search_all(_code(src)):
		var k := m.get_string(1)
		if k != "ground" and not keys.has(k) and not bad.has(k):
			bad.append(k)
	t.ok(bad.is_empty(), "%s draws only the inks the contrast test measures (unmeasured: %s)" % [name, ", ".join(bad)])


## Worst contrast of `key` at `alpha` over `bg(world)` across WORLD_BRIGHT: [ratio, world key].
func _worst_over(bg: Callable, key: String, alpha: float) -> Array:
	var worst := [INF, ""]
	for w in WORLD_BRIGHT:
		var under: Color = bg.call(Palette.c(w))
		var ink := RaidLogic.over(Palette.c(key), alpha, under)
		var r := RaidLogic.contrast_ratio(ink, under)
		if r < float(worst[0]):
			worst = [r, w]
	return worst


func _check_plate(t: TestUtil, name: String, bg: Callable, texts: Array, lines: Array) -> void:
	for k in texts:
		var w := _worst_over(bg, str(k), 1.0)
		t.ok(float(w[0]) >= TEXT_MIN, "%s: text `%s` is %.2f:1 over the plate on %s (needs %.1f)" % [name, k, float(w[0]), w[1], TEXT_MIN])
	for ln in lines:
		var w := _worst_over(bg, str(ln[0]), float(ln[1]))
		t.ok(float(w[0]) >= LINE_MIN, "%s: line `%s` at %.2f is %.2f:1 over the plate on %s (needs %.1f)" % [name, ln[0], float(ln[1]), float(w[0]), w[1], LINE_MIN])


func _rows_keys(rows: Array) -> Array:
	var out: Array = []
	for r in rows:
		var k := str(r["key"])
		if not out.has(k):
			out.append(k)
	return out


func _contrast_tests(t: TestUtil) -> void:
	t.suite("raid_contrast")
	# the helpers: WCAG values, sRGB compositing
	t.ok(is_equal_approx(RaidLogic.contrast_ratio(Color.BLACK, Color.WHITE), 21.0), "black on white is 21:1")
	t.ok(is_equal_approx(RaidLogic.contrast_ratio(Color.WHITE, Color.WHITE), 1.0), "a colour on itself is 1:1")
	var td := RaidLogic.contrast_ratio(Palette.c("text_dim"), Palette.c("ground"))
	t.ok(td > 5.8 and td < 6.0, "text_dim on pure ground is ~5.9:1 (%.2f)" % td)
	var mid := RaidLogic.over(Color.WHITE, 0.5, Color.BLACK)
	t.ok(is_equal_approx(mid.r, 0.5) and is_equal_approx(mid.g, 0.5) and mid.a == 1.0, "half white over black is 0.5 grey in sRGB")
	t.ok(RaidLogic.over(Color.RED, 0.0, Color.BLUE) == Color.BLUE and RaidLogic.over(Color.RED, 1.0, Color.BLUE) == Color(1, 0, 0, 1), "alpha 0 keeps the under colour, 1 the top")
	var raid_cfg: Dictionary = TestUtil.load_json("res://configs/raid.json")
	var hud: Dictionary = raid_cfg.get("hud", {})
	var a_legend := float(hud.get("legend", {}).get("plate_alpha", 0.0))
	var a_goal := float(hud.get("goal", {}).get("plate_alpha", 0.0))
	var a_stat := float(hud.get("plate_alpha", 0.0))
	var a_warden := float(hud.get("warden_plate_alpha", 0.0))
	var a_retreat := float(hud.get("retreat", {}).get("plate_alpha", 0.0))
	var dc: Dictionary = RaidLogic.DEATH_CARD
	var plate := func(alpha: float) -> Callable:
		return func(world: Color) -> Color: return RaidLogic.over(Palette.c("ground"), alpha, world)
	var card_bg := func(world: Color) -> Color:
		return RaidLogic.over(Palette.c("ground"), float(dc["plate_a"]), RaidLogic.over(Palette.c("ground"), float(dc["backdrop_a"]), world))
	var rsrc := func(f: String) -> String: return FileAccess.get_file_as_string("res://scripts/raid/" + f)
	var hs: String = rsrc.call("raid_hud.gd")
	var stat_src := hs.substr(hs.find("class StatBlock:"), hs.find("class TranceMeter:") - hs.find("class StatBlock:"))
	var warden_src := hs.substr(hs.find("class WardenBlock:"), hs.find("class Pointers:") - hs.find("class WardenBlock:"))
	t.ok(stat_src.length() > 1000 and warden_src.length() > 1000, "the StatBlock and WardenBlock sources were found")

	# the test bites: the old 0.86 plates failed text_dim over a cream wall line
	t.ok(float(_worst_over(plate.call(0.86), "text_dim", 1.0)[0]) < TEXT_MIN, "at the old 0.86 alpha, text_dim fails 4.5:1 over the brightest world colour")
	# the control legend (bottom left)
	_check_plate(t, "legend", plate.call(a_legend), ["text"], [["text", 1.0], ["text_dim", 1.0]])
	_guard_keys(t, "legend", rsrc.call("raid_legend.gd"), ["text", "text_dim"])
	# the goal block: the keys goal_rows hands it, full and compact
	var gs := {"held": false, "fort_name": "F", "warden_alive": true, "warden_name": "W", "route_text": "r", "break_rows": ["a", "b", "c"], "chest": true, "no_army": true, "goal_px": 17, "route_px": 14, "row_px": 13}
	var gkeys := _rows_keys(RaidLogic.goal_rows(gs))
	for k in _rows_keys(RaidLogic.goal_rows(gs.merged({"compact": true}))):
		if not gkeys.has(k):
			gkeys.append(k)
	_check_plate(t, "goal block", plate.call(a_goal), gkeys, [])
	_guard_keys(t, "goal block", rsrc.call("raid_goal_block.gd"), [])   # it draws the keys goal_rows hands it, nothing literal
	# the StatBlock (top left), its dim meaning and sub-lines included
	_check_plate(t, "stat block", plate.call(a_stat), ["text", "text_dim", "danger", "vei"],
		[["undead", 1.0], ["living", 1.0], ["essence", 1.0], ["relish", 1.0], ["danger", 1.0], ["undead", 0.8], ["essence", 0.8], ["relish", 0.8], ["living", 0.8], ["danger", 0.8], ["text_dim", 0.8]])   # 0.8: a hollow pip's outline (dim.a)
	_guard_keys(t, "stat block", stat_src, ["text", "text_dim", "danger", "vei", "undead", "living", "essence", "relish"])
	# the awake warden's block (top centre)
	_check_plate(t, "warden block", plate.call(a_warden), ["text", "text_dim", "danger", "vei", "undead"],
		[["vei", 0.9], ["vei", 1.0], ["undead", 1.0], ["danger", 1.0], ["text_dim", 0.8]])
	_guard_keys(t, "warden block", warden_src, ["text", "text_dim", "danger", "vei", "undead"])
	# the retreat panel
	_check_plate(t, "retreat panel", plate.call(a_retreat), ["vei", "relish", "danger", "text", "text_dim"],
		[["relish", 0.8], ["relish", 0.7], ["text_dim", 0.7], ["text_dim", 0.8]])
	_guard_keys(t, "retreat panel", rsrc.call("raid_retreat_panel.gd"), ["vei", "relish", "danger", "text", "text_dim"])
	# the bottom-centre hint (idle / trance / exit lines and the dim sub-line), the banner (cues and wake lines in
	# their colours) and the held door's prompt
	var hint_cfg: Dictionary = hud.get("hint", {})
	_check_plate(t, "hint plate", plate.call(float(hint_cfg.get("plate_alpha", 0.0))), ["text", "text_dim"], [])
	_check_plate(t, "banner plate", plate.call(float(hud.get("banner_plate_alpha", 0.0))), ["relish", "vei", "danger", "essence", "undead"], [])
	_check_plate(t, "door prompt plate", plate.call(float(hud.get("door_plate_alpha", 0.0))), ["text"], [])
	var dng: Dictionary = raid_cfg.get("danger", {})
	var frame_inner := float(dng.get("edge_inset_px", 5.0)) + float(dng.get("edge_width_px", 5.0))
	t.ok(float(hint_cfg.get("bottom_px", 0)) >= 20.0 and float(hint_cfg.get("bottom_px", 0)) >= frame_inner + 10.0, "the hint's plate sits at least 20 px above the bottom and clear of the danger frame's inner edge (%.0f px)" % frame_inner)
	# M3: the plate's stacking arithmetic (RaidLogic.hint_plate_layout): two lines, one line, and bottom_px moves it all
	var L2 := RaidLogic.hint_plate_layout(24.0, 14.0, 4.0, 500.0, 26.0, 300.0, 20.0)
	var L1 := RaidLogic.hint_plate_layout(24.0, 14.0, 4.0, 500.0, 26.0, 0.0, 0.0)
	var L2b := RaidLogic.hint_plate_layout(40.0, 14.0, 4.0, 500.0, 26.0, 300.0, 20.0)
	t.ok(L2["plate_bottom"] == -24.0 and L2["sub_bottom"] == -28.0 and L2["sub_top"] == -48.0 and L2["hint_bottom"] == -48.0 and L2["hint_top"] == -74.0 and L2["plate_top"] == -78.0,
		"two lines: the sub-line 4 px over the plate's bottom, the hint over it, the plate 4 px over that (%s)" % str(L2))
	t.ok(L2["plate_left"] == -264.0 and L2["plate_right"] == 264.0, "the plate is the wider line plus the pad each side")
	t.ok(L1["plate_bottom"] == -24.0 and L1["hint_bottom"] == -28.0 and L1["hint_top"] == -54.0 and L1["plate_top"] == -58.0, "one line: no sub-line row (%s)" % str(L1))
	t.ok(L2b["plate_bottom"] == -40.0 and L2b["plate_top"] == L2["plate_top"] - 16.0 and L2b["hint_top"] == L2["hint_top"] - 16.0 and L2b["sub_top"] == L2["sub_top"] - 16.0,
		"bottom_px moves the whole stack: 16 px more lifts every edge 16 px")
	var hsrc := _code(hs)
	var fit_src := _func_src(hsrc, "func _fit_hint_plate(")
	t.ok(fit_src.contains("RaidLogic.hint_plate_layout(") and fit_src.contains("\"bottom_px\"") and fit_src.contains("\"font_px\"") and fit_src.contains("\"sub_font_px\"") and fit_src.contains("\"gap_px\"")
		and not fit_src.contains("-1, 19)") and not fit_src.contains("-1, 15)") and not fit_src.contains("var key"), "the fit reads its sizes and gaps from hud.hint and builds no key string")
	t.ok(fit_src.contains("_door_prompt.offset_bottom = ") and fit_src.contains("door_gap_px") and not hsrc.contains("offset_top = -132.0"), "the door prompt sits over the fitted plate's top")
	t.ok(hint_cfg.has("font_px") and hint_cfg.has("sub_font_px") and hint_cfg.has("gap_px") and hint_cfg.has("door_gap_px"), "hud.hint holds the font sizes and gaps")
	var phyl_src := _inner_src(hsrc, "func set_phyl(")
	var stat_draw := _inner_src(hsrc, "func _draw()", hsrc.find("class StatBlock:"))
	t.ok(phyl_src.contains("return") and phyl_src.contains("phyl_meaning = ") and stat_draw.contains("phyl_meaning") and not stat_draw.contains("phylactery_meaning("),
		"set_phyl returns early on an unchanged count and keeps the meaning lines; the StatBlock's _draw reads them")
	t.ok(hsrc.contains("func _fit_hint_plate(") and hsrc.contains("_hint_plate") and hsrc.contains("hud\", {}).get(\"banner_plate_alpha\"") and not hsrc.contains("Palette.c(\"ground\", 0.72)"), "the HUD fits a hint plate and reads the banner's alpha from raid.json")
	# the death and clear cards at full alpha: the plate over the backdrop over the world
	var sample := RaidLogic.loot_counts({"relics": 1, "husks": [{}], "essence": 2})
	var drows := RaidLogic.death_card_rows("a wound", sample, sample, 2, "the ring", RaidLogic.death_next_row({}))
	var dkeys := _rows_keys(drows)
	for k in ["danger", "text_dim"]:
		if not dkeys.has(k):
			dkeys.append(k)
	_check_plate(t, "death card", card_bg, dkeys, [["danger", 0.8]])
	_guard_keys(t, "death card", rsrc.call("raid_death_card.gd"), dkeys)
	var ckeys := _rows_keys(RaidLogic.clear_card_rows("X", sample))
	for k in ["vei", "text_dim"]:
		if not ckeys.has(k):
			ckeys.append(k)
	_check_plate(t, "clear card", card_bg, ckeys, [["vei", 0.8]])
	_guard_keys(t, "clear card", rsrc.call("raid_clear_card.gd"), ckeys)
	# the alphas the draw code reads are the config's (a plate never hard-codes its own)
	t.ok(a_legend >= 0.96 and a_goal >= 0.9 and a_stat >= 0.9 and a_warden >= 0.9 and a_retreat >= 0.9, "every plate's alpha is configured (raid.json) and near opaque")
	t.ok(not _code(rsrc.call("raid_retreat_panel.gd")).contains("Palette.c(\"ground\", 0.95)") and not _code(warden_src).contains("Palette.c(\"ground\", 0.62)"), "no plate hard-codes its alpha")
	# the card labels fit their column at their size
	var f := ThemeDB.fallback_font
	var worst_label := 0.0
	for r in drows + RaidLogic.clear_card_rows("X", sample):
		worst_label = maxf(worst_label, f.get_string_size(str(r["label"]), HORIZONTAL_ALIGNMENT_LEFT, -1, int(dc["label_px"])).x)
	t.ok(int(dc["label_px"]) >= 14 and worst_label <= float(dc["label_w"]) - 8.0, "card labels are 14 px and fit their column (%.0f px of %.0f)" % [worst_label, float(dc["label_w"]) - 8.0])
	t.ok(f.get_string_size(RaidLogic.KEY_PILE_LINE, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x <= 420.0 - 12.0, "the floor key's second line fits the StatBlock's plate at 13 px")

	# no raid HUD text under 13 px: every literal size in a draw_string / font_size override
	var small := PackedStringArray()
	var re_ds := RegEx.create_from_string("HORIZONTAL_ALIGNMENT_\\w+,\\s*[^,]+,\\s*(\\d+)[,)]")
	var re_fs := RegEx.create_from_string("\"font_size\",\\s*(\\d+)")
	for file in ["raid_hud.gd", "raid_legend.gd", "raid_goal_block.gd", "raid_retreat_panel.gd", "raid_death_card.gd", "raid_clear_card.gd"]:
		var code := _code(rsrc.call(file))
		for re in [re_ds, re_fs]:
			for m in (re as RegEx).search_all(code):
				if int(m.get_string(1)) < 13:
					small.append("%s: %s" % [file, m.get_string(0)])
	t.ok(small.is_empty(), "no raid HUD text is set under 13 px (%s)" % ", ".join(small))
	t.ok(int(hud.get("label_px", 0)) >= 13 and int(hud.get("value_px", 0)) >= 13 and int(hud.get("legend", {}).get("row_px", 0)) >= 13 and int(hud.get("retreat", {}).get("line_px", 0)) >= 13, "the configured HUD sizes are at least 13 px")
	# B4: the living's bow is dashed (dash rhythm), the undead's strokes solid
	var us: String = rsrc.call("raid_unit.gd")
	var living_src := _func_src(us, "func _draw_living(")
	var undead_src := _func_src(us, "func _draw_undead(")
	undead_src = undead_src.substr(0, undead_src.find("\nconst "))   # up to the living's constants that follow it
	t.ok(living_src.contains("for i in LIVING_DASHES") and living_src.contains("LineGlow.layers(") and living_src.contains("draw_arc(") and living_src.contains("LineGlow.ring("), "the living's bow is dashed LineGlow arcs, the hollow ring head kept")
	t.ok(not undead_src.contains("LIVING_DASHES") and undead_src.contains("draw_line("), "the undead's strokes stay solid")
	var sweep := 3.0 * 0.56 + 2.0 * 0.36
	t.ok(us.contains("const LIVING_DASHES := 3") and us.contains("const LIVING_DASH_SWEEP := 0.56") and us.contains("const LIVING_GAP_SWEEP := 0.36") and sweep <= 2.45, "three dashes and their gaps span the bow's 2.4 rad")


## The compact goal block: the decision, the rows, the ring's rect, and the HUD's wiring (source text).
func _goal_compact_tests(t: TestUtil) -> void:
	t.suite("raid_goal_compact")
	var full := Rect2(300.0, 10.0, 680.0, 150.0)
	t.ok(RaidLogic.goal_compact(full, Rect2(600.0, 120.0, 100.0, 100.0)), "a ring reaching into the full rect: compact")
	t.ok(not RaidLogic.goal_compact(full, Rect2(600.0, 200.0, 100.0, 100.0)), "a ring below the full rect: full rows")
	t.ok(not RaidLogic.goal_compact(full, Rect2()), "no ring (awake, down, absent): full rows")
	t.ok(not RaidLogic.goal_compact(Rect2(), Rect2(600.0, 120.0, 100.0, 100.0)), "no block: nothing to shrink")
	# the test is against the FULL rect, so a ring between the compact and the full bottom keeps it compact
	var compact_rect := Rect2(300.0, 10.0, 680.0, 90.0)
	var ring_between := Rect2(600.0, 120.0, 100.0, 100.0)
	t.ok(not compact_rect.intersects(ring_between) and RaidLogic.goal_compact(full, ring_between), "a ring clear of the compact rect but under the full one stays compact (no flicker)")
	var rr := RaidLogic.warden_ring_rect(Vector2(640.0, 60.0), 1.0, 30.0, {"ring_mult": 1.9, "dash_gap_px": 7.0}, 4.0)
	t.ok(rr.get_center() == Vector2(640.0, 60.0) and is_equal_approx(rr.size.x, 2.0 * (57.0 + 7.0 + 4.0)), "the ring's rect is centred on the warden, 1.9 x radius plus the dashed ring's gap and a margin")
	t.ok(RaidLogic.warden_ring_rect(Vector2.ZERO, 2.0, 30.0, {"ring_mult": 1.9, "dash_gap_px": 7.0}, 0.0).size.x > rr.size.x, "the camera's zoom scales it")
	# the rows
	var s := {"held": false, "fort_name": "Ashgate", "warden_alive": true, "warden_name": "The Huntsman", "route_text": "you are in the warden's room",
		"break_rows": ["BREAK it", "TAKES x4", "COUNTER them"], "chest": false, "no_army": true, "goal_px": 17, "route_px": 14, "row_px": 13}
	var full_rows := RaidLogic.goal_rows(s)
	t.ok(full_rows.size() == 6 and full_rows[1]["text"] == s["route_text"] and full_rows[3]["text"] == "TAKES x4" and full_rows[5]["text"] == RaidLogic.NO_ARMY_LINE, "full: goal, route, BREAK, TAKES, COUNTER, no-army")
	var cs := s.duplicate()
	cs["compact"] = true
	var crows := RaidLogic.goal_rows(cs)
	t.ok(crows.size() == 4 and crows[0]["key"] == "vei" and crows[1]["text"] == "BREAK it" and crows[2]["text"] == "COUNTER them" and crows[3]["text"] == RaidLogic.NO_ARMY_SHORT,
		"compact: goal, BREAK, COUNTER and the short no-army row; no route, no TAKES")
	t.ok(RaidLogic.NO_ARMY_SHORT.contains("retreat, then send WAR here or bring big undead") and RaidLogic.NO_ARMY_SHORT.begins_with("NO UNDEAD") and RaidLogic.NO_ARMY_SHORT.length() < RaidLogic.NO_ARMY_LINE.length(),
		"the short no-army row keeps its advice and is shorter")
	cs["no_army"] = false
	t.ok(RaidLogic.goal_rows(cs).size() == 3, "compact without the no-army row: three rows")
	cs["break_rows"] = ["BREAK it", "COUNTER them"]
	t.ok(RaidLogic.goal_rows(cs).size() == 3 and RaidLogic.goal_rows(cs)[2]["text"] == "COUNTER them", "a spec with no TAKES row loses nothing")
	var held := s.duplicate()
	held["held"] = true
	held["compact"] = true
	t.ok(RaidLogic.goal_rows(held).size() == 2 and RaidLogic.goal_rows(held)[1]["text"] == RaidLogic.NO_ARMY_SHORT, "a held raid: the goal and the short no-army row when compact")
	# the HUD measures the full rows and tests against them
	var hcode := _code(FileAccess.get_file_as_string("res://scripts/raid/raid_hud.gd"))
	var ug := _func_src(hcode, "func _update_goal(")
	t.ok(ug.contains("height_for(full_rows)") and ug.contains("RaidLogic.goal_compact(full,") and ug.contains("_sleeping_ring_rect("), "_update_goal tests the ring against the FULL rows' rect")
	var sr := _func_src(hcode, "func _sleeping_ring_rect(")
	t.ok(sr.contains("get_global_transform_with_canvas()") and sr.contains("RaidLogic.warden_ring_rect(") and sr.contains("w.awake"), "the ring's rect goes through the canvas transform and only while the warden sleeps")
