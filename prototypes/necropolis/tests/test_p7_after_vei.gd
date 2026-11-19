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
	_clean()
	return t.failures


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
	var wst := st.duplicate(true)
	wst["won"] = true
	card.show_catalog("lot-05", 9, items, wst, "", true)
	var after := _row_texts(card, "raising_pit")
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
