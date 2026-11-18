extends RefCounted
## The welcome-back replay (town-i M2 Q-f): TownReplay reads the away report's "builds finished" line back through
## economy's own templates, finds each build's lot in view_town, and lists the strip's lines with what each one does
## in town (the raid prompt with no fort goes back to the realm). Once per report in a session, shown or dismissed.

var t: TestUtil
var cfg: Dictionary
var rcfg: Dictionary
var bv: Dictionary
var report: Dictionary


func run() -> int:
	t = TestUtil.new()
	t.suite("town-replay")
	cfg = TestUtil.configs()
	rcfg = cfg["town"]["view"]["replay"]
	bv = cfg["buildings_view"]
	report = cfg["economy"]["idle"]["report"]
	_names()
	_lots()
	_lines()
	_due()
	_real()
	return t.failures


func _nm(bid: String, level := 1) -> String:
	return TownReplay.name_of(bid, level, bv, report)


func _build_line(names: Array) -> Dictionary:
	var fmt := String(report["builds_one_fmt"] if names.size() == 1 else report["builds_fmt"])
	return {"text": fmt.format({"n": str(names.size()), "names": String(report["list_sep"]).join(PackedStringArray(names))}),
		"kind": "build", "target": ""}


func _names() -> void:
	var one := {"gains": [_build_line([_nm("inn")])]}
	t.ok(TownReplay.finished_names(one, report) == [_nm("inn")], "one build: '%s' reads back as %s" % [one["gains"][0]["text"], str(TownReplay.finished_names(one, report))])
	var names := [_nm("house"), _nm("market", 2), _nm("market", 3)]
	var three := {"gains": [{"text": "gold +0.2/s · +720", "kind": "stream", "target": ""}, _build_line(names),
		{"text": _nm("bakery") + " started right away", "kind": "build", "target": ""}]}
	t.ok(TownReplay.finished_names(three, report) == names, "three builds, a level name among them, in order: %s" % str(TownReplay.finished_names(three, report)))
	t.ok(TownReplay.finished_names({"gains": [three["gains"][2]]}, report).is_empty(), "a 'started' line is not a finished one")
	t.ok(TownReplay.finished_names({}, report).is_empty(), "no report: no names")


func _lots() -> void:
	var town := {"buildings": [
		{"lot_id": "lot-02", "building_id": "market", "level": 3}, {"lot_id": "lot-05", "building_id": "house", "level": 1},
		{"lot_id": "lot-06", "building_id": "house", "level": 1}, {"lot_id": "lot-07", "building_id": "inn", "level": 0}]}
	var rep := {"gains": [_build_line([_nm("house"), _nm("market", 2), _nm("market", 3), _nm("house")])]}
	var lots := TownReplay.finished_lots(rep, town, bv, report)
	t.ok(lots == ["lot-05", "lot-02", "lot-02", "lot-06"],
		"each name its lot: two Houses on two lots, one Market's two upgrades on its one lot, in order (%s)" % str(lots))
	t.ok(TownReplay.finished_lots({"gains": [_build_line([_nm("inn")])]}, town, bv, report).is_empty(),
		"an Inn still on its first build (level 0) didn't finish: no lot")
	var two := {"buildings": [{"lot_id": "lot-02", "building_id": "house", "level": 2}, {"lot_id": "lot-03", "building_id": "house", "level": 1}]}
	t.ok(TownReplay.finished_lots({"gains": [_build_line([_nm("house")])]}, two, bv, report) == ["lot-03"],
		"a level-1 House finished: the House at level 1 over one already upgraded")


func _lines() -> void:
	var rep := {"away_s": 29520.0, "gains": [{"text": "gold +1/s · +9", "kind": "stream", "target": ""}, _build_line([_nm("inn")])],
		"ready": [{"text": "2 husks: raise at the slab", "kind": "slab", "target": "slab"},
			{"text": "Your stores are full and the queue is empty: raid a fort for relics", "kind": "raid", "target": ""},
			{"text": "Ashgate refilled: raid it", "kind": "raid", "target": "ashgate"},
			{"text": "Gold filled up, 120 not stored: queue more, or raid for relics", "kind": "overflow", "target": "queue"}],
		"losses": []}
	var ls := TownReplay.lines(rep, {})
	t.ok(ls.map(func(l): return l["act"]) == ["", "crypt", "realm", "realm", "build"],
		"the build line first, then the ready lines; slab: Crypt, the fortless raid prompt and a fort's: the realm, overflow: Build (%s)" % str(ls.map(func(l): return l["act"])))
	t.ok(String(ls[0]["text"]) == String(rep["gains"][1]["text"]), "a stream line isn't in the strip")
	t.ok(TownReplay.lines(rep, {"max_lines": 2}).size() == 2, "max_lines cuts the strip")
	t.ok(TownReplay.title(rep, rcfg) == "While you were away (8 h 12 m)", "the title: '%s'" % TownReplay.title(rep, rcfg))
	t.ok(TownReplay.duration(720.0, rcfg) == "12 m" and TownReplay.duration(20.0, rcfg) == String(rcfg["under_minute"]), "short times")
	for act in ["crypt", "build", "realm"]:
		t.ok((rcfg["acts"] as Dictionary).has(act), "town.json replay.acts words the %s button" % act)


func _due() -> void:
	t.ok(TownReplay.key({"shown": false, "away_s": 0.0, "gains": [], "ready": [], "losses": []}) == 0, "no report: key 0")
	t.ok(not TownReplay.due({"gains": [], "ready": [], "losses": []}, 0), "no report: not due")
	var streams_only := {"away_s": 900.0, "gains": [{"text": "gold +1/s · +9", "kind": "stream", "target": ""}], "ready": [], "losses": []}
	t.ok(not TownReplay.due(streams_only, 0), "a report with nothing for the town (streams only): not due")
	var rep := {"shown": false, "away_s": 900.0, "gains": [_build_line([_nm("inn")])], "ready": [], "losses": []}
	t.ok(TownReplay.due(rep, 0), "a dismissed report with a build line: due (acting on a map line dismisses it)")
	t.ok(not TownReplay.due(rep, TownReplay.key(rep)), "replayed this session: not again")
	var shown := rep.duplicate(true)
	shown["shown"] = true
	t.ok(TownReplay.key(shown) == TownReplay.key(rep), "dismissing doesn't make it a new report")
	var later := rep.duplicate(true)
	later["away_s"] = 1800.0
	t.ok(TownReplay.due(later, TownReplay.key(rep)), "a later report is due its own replay")


## midgame_2flips with an Inn and a Bakery queued and the gold to pay, then a real 1 h open-game gap (tick's reporting
## catch-up): the report's finished builds read back to their lots.
func _real() -> void:
	var s := GameState.new(cfg)
	s.debug_enabled = true
	t.ok(s.cmd_debug_load_fixture("midgame_2flips")["ok"], "(setup) midgame_2flips")
	s.cmd_debug_grant({"gold": 5000.0 - s.town_sim.gold, "bone": 300.0})
	t.ok(s.cmd_queue_build("inn", "lot-13")["ok"] and s.cmd_queue_build("bakery", "lot-08")["ok"], "(setup) an Inn and a Bakery queued")
	s.tick(3600.0, s.max_substeps_per_frame())
	var guard := 0
	while s.view_catchup()["active"] and guard < 10000:
		s.tick(0.016, s.max_substeps_per_frame())
		guard += 1
	var rep := s.view_away()
	var names := TownReplay.finished_names(rep, report)
	t.ok(names.has(_nm("inn")) and names.has(_nm("bakery")), "the 1 h report names the Inn and the Bakery finished: %s" % str(names))
	var lots := TownReplay.finished_lots(rep, s.view_town(), bv, report)
	t.ok(lots.has("lot-13") and lots.has("lot-08") and lots.size() == names.size(),
		"each finished build has its lot, the Inn's lot-13 and the Bakery's lot-08 among them: %s" % str(lots))
	t.ok(TownReplay.due(rep, 0) and TownReplay.lines(rep, rcfg).size() >= 1, "the report is due its replay")
