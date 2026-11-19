extends RefCounted
## P7, after Vei falls (briefs/p7-after-vei.md item 3): a save made after the win loads into the same end state.
## `won` itself round-trips in save_io; these checks pin what P7 reads from it after a load: the town's won head,
## step and next: line (TownGuide), and the map's end state at mount (the victory settles, the Vei card offers no
## BEGIN). A not-won save of the same game is the control: it loads into the realm's usual step.
## (With economy's #21 merged, view_vei().can_begin is false with reason "won" after the win: _after_21.)

var t: TestUtil
var cfg: Dictionary
var gcfg: Dictionary
var hcfg: Dictionary
var bview: Dictionary
var _dir := "user://test_p7_after_vei_%d" % OS.get_process_id()


func run() -> int:
	t = TestUtil.new()
	t.suite("p7-after-vei")
	cfg = TestUtil.configs()
	gcfg = cfg["town"]["view"]["guide"]
	hcfg = cfg["town"]["view"]["hud"]
	bview = cfg["buildings_view"]
	DirAccess.make_dir_recursive_absolute(_dir)
	_save_after_win()
	_won_town_words()
	_catalog_rows_refresh()
	_after_21()
	_won_away()
	_won_queue()
	_won_overflow()
	_won_valve()
	_odds_tip()
	_clean()
	return t.failures


## Ruling 4 (Session 3's open 4): the ODDS hover adds "with your raids" (test_map_hud pins both lines verbatim). On
## pre_vei the bar's ODDS word carries the backups line (view_hud reports backups), raids and all; once won the ODDS
## readout is hidden (HudLogic.vei_readout_shown), so there is no won ODDS hover to word.
func _odds_tip() -> void:
	MapLogic.configure(cfg["map_view"])
	var s := GameState.new(cfg)
	s.debug_enabled = true
	s.cmd_debug_load_fixture("pre_vei")
	var m := MapModel.new(s)
	m.refresh(true)
	var id := HudLogic.odds_tip_id(int(m.readout()["backups"]))
	t.ok(id == "odds_backups" and HudLogic.tip(id, m.hud).contains("with your raids and with your backups"), "pre_vei: the bar's ODDS hover names your raids: '%s'" % HudLogic.tip(id, m.hud))
	t.ok(not HudLogic.vei_readout_shown(_won_state().view_hud()), "won: no ODDS readout, so no ODDS hover")


## Rulings 2 and 3 on the real valve (built headless, as test_map_hud's tips-on-nodes): pre_vei's valve, not won,
## carries the glossary's WAR / FLOOD line; the same valve after the flip (cmd_debug_set_state won, then a refresh)
## re-tips its WAR and FLOOD names and corners with the won line, and its overflow label, with WAR overflowing, reads
## the won words. Revert proofs: the valve's re-tip loop off; overflow_parts ignoring the hud.
func _won_valve() -> void:
	MapLogic.configure(cfg["map_view"])
	var war_line := str(cfg["map_view"]["clarity"]["tips"]["war"])
	var war_won := "WAR sends undead to your forts, spread by distance, with Relish's fort drawing 3× its share."
	var s := GameState.new(cfg)
	s.debug_enabled = true
	s.cmd_debug_load_fixture("pre_vei")
	var m := MapModel.new(s)
	m.refresh(true)
	var v := MapValve.new()
	v.model = m
	v._ready()  # not in a tree: the scene's own build, run by hand
	var tips := func() -> Array:
		var out: Array = []
		for k in ["war", "flood"]:
			out.append((v._rows[k]["name"] as Label).tooltip_text)
			out.append((v._corner_btns[k] as Control).tooltip_text)
		return out
	t.ok((tips.call() as Array).all(func(x): return x == war_line), "the control: not won, the valve's WAR and FLOOD names and corners carry the glossary's line")
	t.ok(not v._over_won_row.visible, "the control: not won, the overflow has no line of its own (it sits beside WAR's feed)")
	s.cmd_debug_set_state({"won": true})
	for i in 10:
		s.tick(60.0, s.max_substeps_per_frame())
	s.drain_events()
	m.refresh(true)
	v.refresh()
	t.ok(bool(m.hud.get("won", false)) and (tips.call() as Array).all(func(x): return x == war_won), "won: the same valve re-tips them with the won line (%s)" % str(tips.call()[0]))
	t.ok(float(m.hud.get("war_overflow", 0.0)) > 0.0 and v._over_won_rate.text == MapLogic.fmt_rate(float(m.hud["war_overflow"])) and v._over_won_text.text == "lost: your forts are full",
		"won: the valve's overflow line reads '%s %s'" % [v._over_won_rate.text, v._over_won_text.text])
	# its words don't fit beside "→ the forts" in the rows' width (a 1600×900 shot had "are full" past the plate), so
	# once won the line is its own, under the feed. The fit is read from the shot: headless font metrics run ~1.4× the
	# window's here, so a pixel check would not mean what it says.
	t.ok(v._over_won_row.visible and v._over_won_row.custom_minimum_size.y > 0.0 and v._over_rate.text == "" and v._over_text.text == "",
		"won: the overflow is on its own line, its height kept, none beside the feed")
	m.hud["war_overflow"] = 0.0  # the overflow flickers to 0 between steps (a won pre_vei: about a third of reads)
	v.refresh()
	t.ok(v._over_won_row.visible and v._over_won_text.text == "", "won with no overflow: the line stays, empty, so the panel doesn't jump")
	v.free()


## Ruling 2 (Session 3's open 2): on a won map the valve's WAR overflow line keeps its rate and reads "lost: your
## forts are full" (valve_overflow_text_won), not "overflows to Vei". On the won pre_vei 10 min on, WAR has no
## target and view_hud.war_overflow is above 0 (the sim's sink, unchanged); the same rate with a not-won hud is
## the control. Revert proof: overflow_parts ignoring the hud.
func _won_overflow() -> void:
	MapLogic.configure(cfg["map_view"])
	var s := _won_state()
	for i in 10:
		s.tick(60.0, s.max_substeps_per_frame())
	s.drain_events()
	var hud := s.view_hud()
	var over := ValveLogic.war_overflow(hud, {}, false)
	var won_p := ValveLogic.overflow_parts(over, hud)
	t.ok(bool(hud.get("won", false)) and over > 0.0 and str(won_p.get("rate", "")) == MapLogic.fmt_rate(over) and str(won_p.get("text", "")) == "lost: your forts are full",
		"won: WAR's overflow (%s) keeps its rate and reads '%s'" % [MapLogic.fmt_rate(over), won_p.get("text", "")])
	t.ok(str(ValveLogic.overflow_parts(over, {"won": false}).get("text", "")) == "overflows to Vei", "the control: not won, the same rate overflows to Vei")
	t.ok(FileAccess.get_file_as_string("res://scripts/map/map_valve.gd").contains("ValveLogic.overflow_parts(ValveLogic.war_overflow(model.hud, proj, _dragging), model.hud)"),
		"the valve passes its view_hud")


## Ruling 1 (Session 3's open 1): once won, Vei's queue stack is drawn from no backlog: no rings, no "+N", and no
## room kept for them. The control is pre_vei before the win (her stack drawn from her backlog); won and 10 min on,
## her queue is still past a ring (#21: it grows) but MapModel.drawn_backlog is 0, so her reach is her structure's
## and beat ring's alone. Every site that drew the stack or kept room for it reads drawn_backlog (source pins: the
## scenes can't load headless). Revert proof: vei_queue_shown always true.
func _won_queue() -> void:
	MapLogic.configure(cfg["map_view"])
	var c := GameState.new(cfg)
	c.debug_enabled = true
	c.cmd_debug_load_fixture("pre_vei")
	var cm := MapModel.new(c)
	cm.refresh(true)
	var cb := NodeLogic.backlog_rings(cm.drawn_backlog())
	t.ok(cm.drawn_backlog() == float(cm.vei["backlog"]) and int(cb["rings"]) > 0,
		"the control: before the win her stack is drawn from her backlog (%d rings, +%d)" % [cb["rings"], cb["overflow"]])
	var s := _won_state()
	for i in 10:
		s.tick(60.0, s.max_substeps_per_frame())
	s.drain_events()
	var m := MapModel.new(s)
	m.refresh(true)
	var backlog := float(m.vei["backlog"])
	var full := NodeLogic.backlog_rings(backlog)
	var b := NodeLogic.backlog_rings(m.drawn_backlog())
	t.ok(bool(m.hud.get("won", false)) and int(full["rings"]) > 0 and m.drawn_backlog() == 0.0 and int(b["rings"]) == 0 and int(b["overflow"]) == 0,
		"won: her queue (%.0f: %d rings, +%d) is drawn from 0: no rings, no '+N'" % [backlog, full["rings"], full["overflow"]])
	var r := float(m.realm["vei"]["radius"])
	t.ok(NodeLogic.vei_reach(r, m.drawn_backlog()) == NodeLogic.vei_reach(r, 0.0) and NodeLogic.vei_reach(r, 0.0) < NodeLogic.vei_reach(r, backlog),
		"won: her reach keeps no room for the stack (%.1f, not %.1f)" % [NodeLogic.vei_reach(r, 0.0), NodeLogic.vei_reach(r, backlog)])
	var sites := {"map_vei": 3, "map_fort_idle": 2, "map_nodes": 1, "map_routes": 1, "map_setpieces": 1}
	var missed: Array = []
	for f in sites:
		var src := FileAccess.get_file_as_string("res://scripts/map/%s.gd" % f)
		if src.count("drawn_backlog()") != int(sites[f]) or src.contains("vei.get(\"backlog\"") or src.contains("vei[\"backlog\"]"):
			missed.append(f)
	var model_src := FileAccess.get_file_as_string("res://scripts/map/map_model.gd")
	if not model_src.contains("float(realm[\"vei\"].get(\"radius\", 0.0)), drawn_backlog()) + float(cfg[\"fit_pad_px\"])"):
		missed.append("map_model (_vei_rect)")
	t.ok(missed.is_empty(), "every site that draws her stack or keeps room for it reads drawn_backlog (missed: %s)" % str(missed))


## The away panel on a won game (handoff-10 item 1; reports/screens/after/p7-map-reload-vei.png had "Vei's queue ▲
## +34/s · +34 · your odds 1% → 1%"): a won pre_vei, saved and loaded 30 min later, reports her queue (the sim's
## report is unchanged) and the panel, built with the won view_hud, leaves that row out, as P7 hides her odds
## elsewhere; the same report with a not-won hud keeps it. Revert proof: gains_row_shown always true.
func _won_away() -> void:
	MapLogic.configure(cfg["map_view"])
	var s := _won_state()
	s.clock_override = 1_800_000_000
	t.ok(bool(s.cmd_save("p7_away").get("ok", false)), "(setup) the won game saves")
	var n := GameState.new(cfg)
	n.debug_enabled = true
	n.save_dir = _dir
	n.clock_override = 1_800_000_000 + 1800
	t.ok(bool(n.cmd_load("p7_away").get("ok", false)) and bool(n.view_hud().get("won", false)), "(setup) the won game loads 30 min later, still won")
	var rep := n.view_away()
	var label := AwayLogic.queue_label(cfg["economy"])
	var queue_rows: Array = (rep.get("gains", []) as Array).filter(func(r): return str(r.get("text", "")).begins_with(label + " "))
	t.ok(label == "Vei's queue" and bool(rep.get("shown", false)) and queue_rows.size() == 1 and str(queue_rows[0]["text"]).contains(" · your odds "),
		"the won game's away report has Vei's queue row, odds and all (%s)" % str(queue_rows.map(func(r): return r["text"])))
	var texts := func(b: Dictionary) -> Array:
		var out: Array = []
		for sec in b["sections"]:
			for l in sec["lines"]:
				out.append(str(l["text"]))
		return out
	var won_lines: Array = texts.call(AwayLogic.build(rep, [], {}, {}, n.view_hud(), label))
	t.ok(not won_lines.is_empty() and won_lines.filter(func(x): return x.contains(label) or x.contains("your odds")).is_empty(),
		"won: the panel has no Vei's queue row and no odds (%s)" % str(won_lines.slice(0, 3)))
	t.ok(won_lines.size() == (texts.call(AwayLogic.build(rep, [])) as Array).size() - 1, "won: only that one row is left out")
	var plain_lines: Array = texts.call(AwayLogic.build(rep, [], {}, {}, {"won": false}, label))
	t.ok(plain_lines.has(str(queue_rows[0]["text"])), "the control: not won, the same report keeps the row")
	var src := FileAccess.get_file_as_string("res://scripts/map/map_away.gd")
	t.ok(src.contains("AwayLogic.build(rep, fort_ids, {}, {}, model.hud, AwayLogic.queue_label(ConfigDb.data.get(\"economy\", {})))"),
		"the panel builds with the model's view_hud and economy's queue label")


## P7 review 4: the town's FLOOD words after the win. The muster lines (the Build tab's "N idle hands muster to …",
## the workers cell's "idle → …" and its tip) read view_hud.split.muster_to, which economy's #21 sets to "war" once
## won: on that won view they name WAR. The Raising Pit's why line is config wording: its won variant
## (guide.why_won) names no FLOOD or Vei, and the inspector and both catalog builders pass `won`.
func _won_town_words() -> void:
	var vcfg: Dictionary = cfg["town"]["view"]
	var wv := {"hud": {"won": true, "split": {"muster_to": "war"}}, "town": {"workers": {"muster_to": "war"}}}  # api-request #21's won shape
	t.ok(HudModel.muster_name(wv, vcfg) == "WAR (your forts)" and HudModel.muster_word(wv, hcfg) == "idle → WAR"
		and HudModel.muster_tip(wv, hcfg).begins_with("Vei is beaten") and not HudModel.muster_tip(wv, hcfg).contains("Muster stance"),
		"won (#21's muster_to war): the idle hands muster to '%s', '%s'; tip '%s'" % [HudModel.muster_name(wv, vcfg), HudModel.muster_word(wv, hcfg), HudModel.muster_tip(wv, hcfg)])
	var stance := {"hud": {"won": false, "split": {"muster_to": "war"}}}
	var pre := {"hud": {"won": true, "split": {"muster_to": "flood"}}}  # a won view before #21: the sim still musters to FLOOD
	t.ok(HudModel.muster_tip(stance, hcfg).contains("Muster stance") and HudModel.muster_tip(pre, hcfg).contains("FLOOD"), "the stance's WAR tip and a pre-#21 won view's FLOOD tip are as before")
	t.ok(FileAccess.get_file_as_string("res://scripts/town/town_forecast.gd").contains("\"to\": HudModel.muster_name(views, vcfg)"), "the Build tab's idle line names the view's muster_to (HudModel.muster_name)")
	var won_pit := TownGuide.why("raising_pit", gcfg, true)
	t.ok(won_pit != "" and not won_pit.contains("FLOOD") and not won_pit.contains("Vei") and TownGuide.why("raising_pit", gcfg).contains("FLOOD to Vei"),
		"the Raising Pit's line once won: '%s' (before: '%s')" % [won_pit, TownGuide.why("raising_pit", gcfg)])
	# a won town's why lines and jargon tooltips, as a won game resolves them, name neither FLOOD nor Vei's queue
	var hits: Array = []
	for bid in (gcfg["why"] as Dictionary):
		var w := TownGuide.why(String(bid), gcfg, true)
		if w.contains("FLOOD") or w.contains("Vei's queue"):
			hits.append("why.%s '%s'" % [bid, w])
	for word in (gcfg["jargon"] as Dictionary):
		var j := TownUI.jargon_tip(String(word), vcfg, true)
		if j.contains("FLOOD") or j.contains("Vei's queue"):
			hits.append("jargon.%s '%s'" % [word, j])
	t.ok(hits.is_empty() and (gcfg["jargon"] as Dictionary).size() >= 3, "won: no why line or jargon tooltip names FLOOD or Vei's queue (%d jargon words): %s" % [
		(gcfg["jargon"] as Dictionary).size(), str(hits)])
	t.ok(String(gcfg["jargon"]["mint"]).contains("FLOOD (Vei's queue)"), "(the control) the plain mint line names FLOOD (Vei's queue), as the scan would catch")
	t.ok(not HudLogic.tip("mint", {"won": true}).contains("FLOOD") and not HudLogic.tip("mint", {"won": true}).contains("Vei's queue"), "the map's mint tip once won names no FLOOD either")
	t.ok(TownGuide.why("market", gcfg, true) == TownGuide.why("market", gcfg), "a line with no won variant stays as it is")
	var s := _won_state()
	var st := BuildSort.stocks(_views(s))
	var pit: Array = (s.view_town()["buildings"] as Array).filter(func(b): return String(b["building_id"]) == "raising_pit")
	t.ok(bool(st.get("won", false)) and not pit.is_empty() and BuildSort.inspect(pit[0], st, cfg["buildings"], bview, vcfg)["purpose"] == won_pit,
		"a won town's inspector reads the won line (stocks carry won)")
	t.ok(FileAccess.get_file_as_string("res://scripts/town/panel_build.gd").contains("TownGuide.add_lines(v, bid, _bcfg, _vcfg.get(\"guide\", {}), bool(_st.get(\"won\", false)))")
		and FileAccess.get_file_as_string("res://scripts/town/town_card.gd").contains("_make_row(bid, bool(st.get(\"won\", false)))"), "both catalog builders pass won to the why line")


## P3b merge check: the catalog rows fix each building's why line when they are built, so a row built before the win
## kept the pre-win words. Both builders now rebuild on a won flip. The lot card (TownCard, no autoload) is driven
## headless: a catalog shown on pre_vei, then the same lot shown with the won stocks, and the Raising Pit's row reads
## the won line; the Build tab (panel_build, which needs the autoload) rebuilds on BuildSort.rows_shape, tested by value.
func _catalog_rows_refresh() -> void:
	var vcfg: Dictionary = cfg["town"]["view"]
	var s := GameState.new(cfg)
	s.debug_enabled = true
	s.save_dir = _dir
	t.ok(bool(s.cmd_debug_load_fixture("pre_vei").get("ok", false)), "(setup) pre_vei loads, not won")
	var v := _views(s)
	var st := BuildSort.stocks(v)
	var items := BuildSort.fitting(BuildSort.tab_suggestion(v, bview, cfg["buildings"], vcfg)["items"], 9)
	var has_pit := items.any(func(it): return String(it["row"].get("building_id", "")) == "raising_pit")
	t.ok(has_pit and not bool(st.get("won", false)), "(setup) the Raising Pit is in the catalog")
	var card: Control = load("res://scripts/town/town_card.gd").new()
	card.setup(vcfg, bview, cfg["buildings"])
	card.show_catalog("lot-05", 9, items, st, "", true)
	var before := _row_texts(card, "raising_pit")
	var hovers: Array = []
	card.connect("hover_building", func(bid): hovers.append(bid))
	card.call("_set_hover", "raising_pit")  # the pointer on the Raising Pit's row (its mouse_entered)
	var wst := st.duplicate(true)
	wst["won"] = true
	card.show_catalog("lot-05", 9, items, wst, "", true)
	var after := _row_texts(card, "raising_pit")
	# the #22 review's should-fix 3: the flip frees the hovered row (no mouse_exited), so the hover is cleared with it
	t.ok(String(card.get("_hover")) == "" and hovers == ["raising_pit", ""], "the flip's rebuild clears the hover and says so (%s)" % str(hovers))
	card.call("_set_hover", "raising_pit")
	t.ok(hovers == ["raising_pit", "", "raising_pit"], "the rebuilt row's hover is sent again for the same building")
	var unwon := TownGuide.why("raising_pit", gcfg)
	var won_l := TownGuide.why("raising_pit", gcfg, true)
	t.ok(before.has(unwon) and not before.has(won_l), "the lot card before the win: the Raising Pit's row reads '%s'" % unwon)
	t.ok(after.has(won_l) and not after.has(unwon), "the same card once won: the row is rebuilt and reads '%s' (%s)" % [won_l, str(after)])
	card.show_catalog("lot-05", 9, items, wst, "", true)
	t.ok(_row_texts(card, "raising_pit").has(won_l), "shown again won: still the won line (no flip, no rebuild)")
	card.free()
	var rows: Array = v["catalog"].get("buildings", [])
	t.ok(BuildSort.rows_shape(rows, false) != BuildSort.rows_shape(rows, true) and BuildSort.rows_shape(rows, true) == BuildSort.rows_shape(rows, true)
		and BuildSort.rows_shape(rows, false).begins_with(String(rows[0]["building_id"])), "the Build tab's rebuild key holds the ids and won, so a flip rebuilds its rows")
	t.ok(FileAccess.get_file_as_string("res://scripts/town/panel_build.gd").contains("var shape := BuildSort.rows_shape(rows, bool(_st.get(\"won\", false)))")
		and FileAccess.get_file_as_string("res://scripts/town/panel_build.gd").find("_st = BuildSort.stocks(") < FileAccess.get_file_as_string("res://scripts/town/panel_build.gd").find("BuildSort.rows_shape("),
		"panel_build's bind keys its rows on rows_shape, with the stocks read first")


## With economy's #21 merged (P3b): what the P7 stand-ins were kept for, on the real won sim (pre_vei, won, 10 min on).
## - The muster: view_hud.split.muster_to reads "war" by itself, so the town's words name WAR.
## - BEGIN: view_vei refuses with "won", and the card's won branch gives only that reason (the generic path would
##   add the fronts line and a disabled BEGIN, so the branch stays).
## - Vei's lanes: once won some lanes into her queue still carry a rate (the forts' FLOOD drain, WAR with no target),
##   so LaneStyle.without_vei still hides real flow on a won map; it is not the identity.
func _after_21() -> void:
	var s := _won_state()
	for i in 10:
		s.tick(60.0, s.max_substeps_per_frame())
	s.drain_events()
	var v := _views(s)
	t.ok(str(v["hud"].get("split", {}).get("muster_to", "")) == "war" and HudModel.muster_word(v, hcfg) == "idle → WAR"
		and HudModel.muster_tip(v, hcfg).begins_with("Vei is beaten"), "won (#21): the muster goes to WAR, and the town says so: '%s', '%s'" % [
		HudModel.muster_word(v, hcfg), HudModel.muster_tip(v, hcfg)])
	t.ok(float(v["hud"].get("split", {}).get("flood", -1.0)) == 0.0, "won (#21): FLOOD's share is 0, as the valve's fold shows")
	var vv := s.view_vei()
	var acts := RelishLogic.vei_actions(vv, s.view_relish())
	t.ok(not bool(vv.get("can_begin", true)) and str(vv.get("reason", "")) == "won" and acts.filter(func(a): return str(a.get("act", "")) == "begin").is_empty()
		and acts.any(func(a): return str(a.get("text", "")) == RelishLogic.reason_text("won")), "won (#21): BEGIN refused with 'won'; the card shows that reason and no BEGIN (%s)" % str(acts.map(func(a): return a.get("text", ""))))
	var rows: Array = s.view_lanes().get("lanes", [])
	var at_vei: Array = rows.filter(func(r): return LaneStyle.touches_vei(r) and float(r.get("rate", 0.0)) > 0.0)
	t.ok(not at_vei.is_empty() and LaneStyle.without_vei(rows, true).filter(func(r): return LaneStyle.touches_vei(r)).is_empty(),
		"won (#21): %d lanes into Vei's queue still carry a rate (%s), and the END map hides them (without_vei)" % [at_vei.size(),
		str(at_vei.map(func(r): return "%s %s" % [r.get("kind", ""), r.get("from", "")]).slice(0, 4))])


## The texts of every Label in building `bid`'s row of a TownCard's catalog.
func _row_texts(card: Control, bid: String) -> Array:
	var out: Array = []
	var rows: Dictionary = card.get("_rows")
	if not rows.has(bid):
		return out
	var stack: Array = [rows[bid]["node"]]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Label:
			out.append((n as Label).text)
		stack.append_array(n.get_children())
	return out


func _views(s: GameState) -> Dictionary:
	var forts: Array = []
	for f in s.view_realm().get("forts", []):
		forts.append({"id": String(f["id"]), "name": String(f["name"]), "held": bool(f["held"]),
			"flipped_count": int(f.get("flipped_count", 0)), "first_dungeon": bool(f.get("first_dungeon", false))})
	return {"town": s.view_town(), "forts": forts, "catalog": s.view_catalog(), "hud": s.view_hud(),
		"inventory": s.view_inventory()}


func _goal(s: GameState) -> Dictionary:
	return TownGuide.goal(_views(s), gcfg, hcfg, bview)


## pre_vei, the fight begun and won through apply_result (the router's path), saved, then loaded into a fresh state.
func _won_state() -> GameState:
	var s := GameState.new(cfg)
	s.debug_enabled = true
	s.save_dir = _dir
	t.ok(bool(s.cmd_debug_load_fixture("pre_vei").get("ok", false)), "(setup) pre_vei loads")
	var nb := s.cmd_begin_boss()
	t.ok(bool(nb.get("ok", false)), "(setup) the fight begins")
	var r := s.apply_result("boss", {"v": 2, "run_id": nb.get("run_id", -1), "seed_rev": nb.get("seed_rev", -1), "won": true,
		"fronts_cleared": [], "relish_deaths": 0, "backups_spent": {"phylactery": 0, "clones": 0}, "party_lost": [], "backlog_spent": 0.0})
	t.ok(bool(r.get("ok", false)) and bool(s.view_hud().get("won", false)), "(setup) the win is written back: %s" % str(r))
	s.drain_events()
	return s


func _load(slot: String) -> GameState:
	var n := GameState.new(cfg)
	n.debug_enabled = true
	n.save_dir = _dir
	var l := n.cmd_load(slot)
	t.ok(bool(l.get("ok", false)), "(setup) slot %s loads: %s" % [slot, str(l)])
	return n


func _save_after_win() -> void:
	var s := _won_state()
	var before := _goal(s)
	t.ok(bool(s.cmd_save("p7_won").get("ok", false)), "(setup) the won game saves")
	var n := _load("p7_won")
	t.ok(bool(n.view_hud().get("won", false)) and bool(n.view_vei().get("won", false)), "after the load the game is still won (view_hud and view_vei)")
	t.ok(String(n.view_relish().get("state", "")) == String(s.view_relish().get("state", "")) and int(n.view_relish().get("run_id", -1)) == -1,
		"after the load Relish is where the win left her (%s), with no run open" % String(n.view_relish().get("state", "")))
	# the town: the same won head, step and next: line before and after the load
	var after := _goal(n)
	t.ok(String(after.get("id", "")) == "won" and String(after["head"]) == String(gcfg["goal"]["won_head"])
		and String(after["text"]) == String(gcfg["goal"]["won"]) and String(after["short"]) == String(gcfg["goal"]["won_short"]),
		"the loaded town's plate and next: line are the won ones: '%s' / '%s' / '%s'" % [after.get("head", ""), after.get("text", ""), after.get("short", "")])
	t.ok(after == before, "the loaded town says what it said before the save")
	var nl := TownGuide.step(_views(n), gcfg, hcfg, bview)
	t.ok(String(nl["short"]) == String(gcfg["goal"]["won_short"]), "the top bar's next: line after the load: '%s'" % nl["short"])
	# the map, mounting the loaded game (its victory seen in the session that saved it): it settles straight to the
	# end state (END: no freeze, no headline, Vei's lanes hidden), Vei's readouts and FLOOD are off, her card has no BEGIN
	MapLogic.configure(cfg["map_view"])
	var won_n := bool(n.view_hud().get("won", false))
	t.ok(SetpieceLogic.victory_settle_at_mount(won_n, true) and SetpieceLogic.victory_phase(0.0, false, true) == SetpieceLogic.END,
		"the loaded won game settles at mount, straight to END")
	t.ok(not HudLogic.vei_readout_shown(n.view_hud()) and not HudLogic.flood_shown(n.view_hud()), "after the load: no Vei odds readout and no FLOOD control")
	var acts := RelishLogic.vei_actions(n.view_vei(), n.view_relish())
	t.ok(acts.filter(func(a): return str(a.get("act", "")) == "begin").is_empty(), "after the load the Vei card offers no BEGIN (%d items)" % acts.size())
	t.ok(CardBlocksLogic.vei_card(n.view_vei(), "", [], {}, {})["blocks"].is_empty(), "after the load the Vei card reads no war")
	var cv := _load("p7_won")  # loading the same save twice reads the same end state
	t.ok(bool(cv.view_hud().get("won", false)) and _goal(cv) == after, "a second load of the save reads the same end state")
	# the control: the same game saved before the win loads into the realm's usual step and head
	var c := GameState.new(cfg)
	c.debug_enabled = true
	c.save_dir = _dir
	c.cmd_debug_load_fixture("pre_vei")
	t.ok(bool(c.cmd_save("p7_not_won").get("ok", false)), "(setup) the same game, not won, saves")
	var cg := _goal(_load("p7_not_won"))
	t.ok(String(cg.get("id", "")) != "won" and String(cg.get("head", "")) == String(gcfg["goal"]["head"]),
		"the control: a save from before the win loads with the game's goal and its '%s' step" % cg.get("id", ""))


func _clean() -> void:
	for f in DirAccess.get_files_at(_dir):
		DirAccess.remove_absolute(_dir.path_join(f))
	DirAccess.remove_absolute(_dir)
