extends RefCounted
## Tests for the idle surfaces: idle_logic.gd (margins, "WAR supports N of M", the dragged
## valve's projection), away_logic.gd (the away report's text and actions), the
## real-field-over-stand-in switch, and the chip colours' contrast. No autoloads.


## A GameState stand-in that has the E2b members.
class FakeE2 extends RefCounted:
	func view_projection(valve: Dictionary) -> Dictionary:
		return {"split": {"work": 0.0, "war": 9.0, "flood": 0.0}, "war_supports": {"n": 7, "m": 8},
			"margins": {"greywall": "thin"}, "echo": valve}

	func view_away() -> Dictionary:
		return {"rev": 5, "shown": true, "away_s": 100.0, "capped": false, "gains": [], "ready": [], "losses": []}


## An E2 away API: every view_away call carries a new rev, cmd_dismiss_away clears `shown`.
class FakeAwayApi extends RefCounted:
	var shown := true
	var rev := 100
	var dismissed := 0

	func view_away() -> Dictionary:
		rev += 1
		return {"rev": rev, "shown": shown, "away_s": 100.0}

	func cmd_dismiss_away() -> void:
		shown = false
		dismissed += 1


## One without them (E1).
class FakeE1 extends RefCounted:
	pass


func run() -> int:
	var t := TestUtil.new()
	t.suite("map_idle")
	Palette.configure(TestUtil.load_json("res://configs/palette.json"))
	MapLogic.configure(TestUtil.load_json("res://configs/map_view.json"))
	_margin(t)
	_supports(t)
	_projection(t)
	_switch(t)
	_away(t)
	_away_api(t)
	_spans(t)
	_demo(t)
	_contrast(t)
	_model(t)
	return t.failures


func _fort(id: String, ship_in: float, held := true) -> Dictionary:
	return {"id": id, "held": held, "ship_in": ship_in, "undead": 10.0}


func _margin(t: TestUtil) -> void:
	var c: Dictionary = IdleLogic.cfg()
	var safe := float(c["margin_safe_ratio"])
	var thin := float(c["margin_thin_ratio"])
	t.ok(safe > thin and thin > 0.0, "safe ratio is above thin ratio")
	t.ok(IdleLogic.margin(0.0, 0.0, c) == "safe", "no pressure is safe even with no support")
	t.ok(IdleLogic.margin(5.0, -1.0, c) == "safe", "negative pressure is safe")
	t.ok(IdleLogic.margin(safe * 2.0, 2.0, c) == "safe", "support at the safe ratio is safe")
	t.ok(IdleLogic.margin(safe * 2.0 - 0.01, 2.0, c) == "thin", "just under the safe ratio is thin")
	t.ok(IdleLogic.margin(thin * 2.0, 2.0, c) == "thin", "support at the thin ratio is thin")
	t.ok(IdleLogic.margin(thin * 2.0 - 0.01, 2.0, c) == "will_fall", "just under the thin ratio will fall")
	t.ok(IdleLogic.margin(0.0, 1.0, c) == "will_fall", "no support under pressure will fall")
	t.ok(IdleLogic.word("safe") == "SAFE" and IdleLogic.word("thin") == "THIN" and IdleLogic.word("will_fall") == "WILL FALL", "the chip words")
	var keys := {}
	for m in ["safe", "thin", "will_fall"]:
		keys[IdleLogic.color_key(m)] = true
		t.ok(Palette.has(IdleLogic.color_key(m)), "%s colour is a palette key" % m)
	t.ok(keys.size() == 3, "the three margins have three colours")
	t.ok(IdleLogic.garrison({"undead": 12.0}) == 12.0, "garrison stand-in is the fort's undead")
	t.ok(IdleLogic.garrison({"undead": 12.0, "garrison": 40.0}) == 40.0, "the view's garrison wins")


func _supports(t: TestUtil) -> void:
	var forts := [_fort("a", 0.3), _fort("b", 0.6), _fort("c", 1.2), _fort("d", 5.0, false)]
	var held := IdleLogic.held_forts(forts)
	t.ok(held.size() == 3, "held_forts skips the unheld")
	t.ok(IdleLogic.war_supports(1.0, forts)["m"] == 3, "m is the held count")
	t.ok(IdleLogic.war_supports(1.0, [])["m"] == 0, "no held forts: m is 0")
	var prev := -1
	var ok_n := true
	var ok_le := true
	for i in 21:
		var s := IdleLogic.war_supports(float(i), forts)
		ok_n = ok_n and int(s["n"]) >= prev
		ok_le = ok_le and int(s["n"]) <= int(s["m"])
		prev = int(s["n"])
	t.ok(ok_n, "more WAR never lowers n")
	t.ok(ok_le, "n never exceeds m")
	t.ok(IdleLogic.war_supports(0.0, forts)["n"] == 0, "no WAR supports none (all under pressure)")
	t.ok(IdleLogic.war_supports(300.0, forts)["n"] == 3, "plenty of WAR supports all")
	# holding more forts thins every garrison: the same WAR over twice the forts is no better
	var one := IdleLogic.margins([_fort("a", 1.0)], 2.5)
	var two := IdleLogic.margins([_fort("a", 1.0), _fort("b", 1.0)], 2.5)
	t.ok(one["a"] == "safe" and two["a"] == "thin", "WAR is split across the held forts")
	var ms := IdleLogic.margins(forts, 3.0)
	t.ok(ms.size() == 3 and not ms.has("d"), "margins cover the held forts only")


func _projection(t: TestUtil) -> void:
	var forts := [_fort("a", 0.3), _fort("b", 0.6), _fort("c", 1.2)]
	var hud := {"rates": [{"id": "mint", "rate": 3.0}], "valve": {"work": 1.0, "war": 0.0, "flood": 0.0}, "workers_steady": 10.0}
	var rank := {"will_fall": 0, "thin": 1, "safe": 2}
	var last := {}
	var mono := true
	var no_thin := true
	for i in 21:
		var war := float(i) / 20.0
		var valve := {"work": 1.0 - war, "war": war, "flood": 0.0}
		var p := IdleLogic.projection(null, hud, valve, forts)
		for id in p["margins"]:
			if last.has(id) and rank[p["margins"][id]] < rank[last[id]]:
				mono = false
			if last.get(id, "") == "safe" and p["margins"][id] == "thin":
				no_thin = false
		last = p["margins"]
		t.ok(p["war_supports"]["m"] == 3 and p["war_supports"]["n"] <= 3, "projection N of M is bounded")
	t.ok(mono, "dragging WAR up never worsens a margin")
	t.ok(no_thin, "dragging WAR up never turns a safe fort thin")
	var full := IdleLogic.projection(null, hud, {"work": 0.0, "war": 1.0, "flood": 0.0}, forts)
	t.near(float(full["split"]["war"]), 3.0, 1e-6, "split.war is mint x the WAR share")
	t.ok(full["margins"]["a"] == "safe" and full["margins"]["c"] == "will_fall", "all-WAR margins")
	var none := IdleLogic.projection(null, hud, {"work": 1.0, "war": 0.0, "flood": 0.0}, forts)
	t.ok(none["margins"]["a"] == "will_fall" and none["war_supports"]["n"] == 0, "no WAR: every held fort will fall")
	t.ok(IdleLogic.projection(null, hud, {"work": 1.0}, [])["war_supports"]["m"] == 0, "no held forts: m is 0")


func _switch(t: TestUtil) -> void:
	var forts := [_fort("greywall", 0.3), _fort("b", 0.6)]
	var hud := {"rates": [{"id": "mint", "rate": 3.0}], "valve": {"work": 1.0, "war": 0.0, "flood": 0.0}, "workers_steady": 10.0}
	var valve := {"work": 0.0, "war": 1.0, "flood": 0.0}
	var e1 := IdleLogic.projection(FakeE1.new(), hud, valve, forts)
	t.ok(e1["margins"]["greywall"] == "safe", "without view_projection the stand-in answers")
	var e2 := IdleLogic.projection(FakeE2.new(), hud, valve, forts)
	t.ok(e2["margins"] == {"greywall": "thin"}, "with view_projection its margins are used")
	t.ok(e2["war_supports"] == {"n": 7, "m": 8}, "with view_projection its N of M is used")
	t.near(float(e2["split"]["war"]), 9.0, 1e-6, "with view_projection its split is used")
	t.near(float(e2["workers_steady"]), float(e1["workers_steady"]), 1e-6, "a field the real one lacks keeps the stand-in's")
	# committed reads: the field when present, else the stand-in
	var hud0 := {"split": {"war": 3.0}}
	var held := [_fort("a", 1.0)]
	t.ok(IdleLogic.committed_margins(held, hud0) == {"a": "safe"}, "committed margin stand-in")
	var with_field := [{"id": "a", "held": true, "ship_in": 1.0, "margin": "will_fall"}]
	t.ok(IdleLogic.committed_margins(with_field, hud0) == {"a": "will_fall"}, "fort.margin wins when present")
	var blank := [{"id": "a", "held": true, "ship_in": 1.0, "margin": ""}]
	t.ok(IdleLogic.committed_margins(blank, hud0) == {"a": "safe"}, "an empty fort.margin falls back")
	t.ok(IdleLogic.committed_supports(hud0, held) == {"n": 1, "m": 1}, "committed N of M stand-in")
	t.ok(IdleLogic.committed_supports({"war_supports": {"n": 2, "m": 5}}, held) == {"n": 2, "m": 5}, "hud.war_supports wins when present")
	# the away report
	var demo := {"shown": true, "rev": 1}
	t.ok(AwayLogic.report(FakeE1.new(), {}) == {"shown": false}, "no view_away and no demo: nothing to show")
	t.ok(AwayLogic.report(null, {}) == {"shown": false}, "no state: nothing to show")
	t.ok(AwayLogic.report(FakeE1.new(), demo) == demo, "the demo report is used without view_away")
	t.ok(int(AwayLogic.report(FakeE2.new(), {})["rev"]) == 5, "view_away is used when the state has it")
	t.ok(AwayLogic.report(FakeE2.new(), demo) == demo, "the debug flag's report wins over the real one")


func _away_api(t: TestUtil) -> void:
	var api := FakeAwayApi.new()
	var closed := -1
	# the real API: shown alone decides, whatever the rev did
	var rep := AwayLogic.report(api, {})
	t.ok(AwayLogic.should_open(api, false, rep, closed), "a shown real report opens")
	closed = int(rep["rev"])  # what _close records
	t.ok(AwayLogic.should_open(api, false, AwayLogic.report(api, {}), closed), "the real report's rev moves every call: the closed rev never matches")
	# acting on a ready line dismisses through the API, so the panel stays closed on every mount
	AwayLogic.dismiss(api)
	t.ok(api.dismissed == 1 and not api.shown, "acting on a line sends cmd_dismiss_away")
	t.ok(not AwayLogic.should_open(api, false, AwayLogic.report(api, {}), closed), "after a dismissed real report the panel does not reopen")
	# the stand-in path compares rev
	var demo := {"shown": true, "rev": 1}
	t.ok(AwayLogic.should_open(FakeE1.new(), true, demo, -1), "the demo opens")
	t.ok(not AwayLogic.should_open(FakeE1.new(), true, demo, 1), "the demo's closed rev keeps it closed")
	t.ok(not AwayLogic.should_open(api, true, demo, 1), "the demo flag uses the rev even when the state has view_away")
	t.ok(not AwayLogic.should_open(FakeE1.new(), false, {"shown": false}, -1), "not shown: never open")
	AwayLogic.dismiss(FakeE1.new())
	AwayLogic.dismiss(null)
	t.ok(true, "dismiss tolerates a state without cmd_dismiss_away")


func _away(t: TestUtil) -> void:
	t.ok(AwayLogic.duration_text(33120.0) == "9 h 12 m", "9 h 12 m")
	t.ok(AwayLogic.duration_text(720.0) == "12 m", "under an hour is minutes")
	t.ok(AwayLogic.duration_text(7200.0) == "2 h 0 m", "whole hours keep the minutes")
	t.ok(AwayLogic.duration_text(10.0) == "under a minute", "under a minute")
	t.ok(AwayLogic.duration_text(-5.0) == "under a minute", "negative time is under a minute")
	var ids := ["ashgate", "greywall"]
	var rep: Dictionary = MapLogic.cfg()["demo_away"]
	var b := AwayLogic.build(rep, ids)
	t.ok(b["away"] == "Away 9 h 12 m", "away line")
	t.ok(b["capped"] == "", "not capped")
	var keys := []
	for s in b["sections"]:
		keys.append(s["key"])
	t.ok(keys == ["gains", "ready", "losses"], "order is gains, ready, losses")
	var ready: Dictionary = b["sections"][1]
	t.ok(ready["lines"].size() == 3, "three ready lines")
	t.ok(ready["lines"][0]["action"] == {"kind": "fort", "id": "ashgate"}, "a fort id selects the fort")
	t.ok(ready["lines"][1]["action"] == {"kind": "dive", "to": "covington"}, "the slab dives into Covington")
	t.ok(ready["lines"][2]["action"] == {"kind": "dive", "to": "covington"}, "the queue dives into Covington")
	t.ok(AwayLogic.action("nowhere", ids)["kind"] == "none" and AwayLogic.action("", ids)["kind"] == "none", "an unknown or empty target does nothing")
	t.ok(b["sections"][0]["lines"][0]["action"]["kind"] == "none", "gains lines are not actions")
	var capped := AwayLogic.build({"away_s": 604800.0, "capped": true, "gains": [], "ready": [], "losses": []}, ids)
	t.ok(capped["capped"] == "capped at 7 days", "capped text")
	var empty_keys := []
	for s in capped["sections"]:
		empty_keys.append(s["key"])
	t.ok(empty_keys == ["losses"], "empty gains and ready are left out; losses always show")
	t.ok(capped["sections"][0]["lines"][0]["text"] == "Nothing lost.", "no losses reads Nothing lost.")
	var lost: Array = b["sections"][2]["lines"]
	t.ok(lost.size() == (rep["losses"] as Array).size() + 1 and lost[0]["text"] == AwayLogic.losses_count(rep["losses"]) and lost[1]["text"] != "Nothing lost.", "losses are listed, led by their count")


func _spans(t: TestUtil) -> void:
	var s := AwayLogic.spans("backlog ▲ +2.1/s · +69,500")
	var kinds := []
	for x in s:
		kinds.append(x["kind"])
	t.ok(kinds == ["label", "rate", "label", "mass"], "stream line: label, rate, label, mass (%s)" % str(kinds))
	t.ok(s[1]["text"] == "+2.1/s" and s[3]["text"] == "+69,500", "rate and total are their own runs")
	var b := AwayLogic.spans("2 builds finished")
	t.ok(b[0]["kind"] == "mass" and b[1]["kind"] == "label" and b[1]["text"] == "builds finished", "a count is a mass, the words merge")
	t.ok(AwayLogic.spans("Nothing lost.").size() == 1, "plain words are one run")
	t.ok(AwayLogic.spans("rot −0.3/s")[1]["kind"] == "rate", "a minus-sign rate is a rate")


func _demo(t: TestUtil) -> void:
	var d: Dictionary = MapLogic.cfg()["demo_nodes"]
	var forts: Array = []
	for id in [d["held"]["fort"], d["also_held"][0]["fort"], d["also_held"][1]["fort"]]:
		forts.append({"id": id, "held": true, "ship_in": 0.0, "undead": 1.0})
	var all: Array = [d["held"]]
	all.append_array(d["also_held"])
	var seen := {}
	var hud := {"rates": [{"id": "mint", "rate": float(d["mint_rate"])}], "valve": {}, "workers_steady": 0.0}
	for i in forts.size():
		forts[i]["ship_in"] = float(all[i]["ship_in"])
	for war in [0.5, 0.8, 1.0]:
		var p := IdleLogic.projection(null, hud, {"work": 1.0 - war, "war": war, "flood": 0.0}, forts)
		for id in p["margins"]:
			seen[p["margins"][id]] = true
	t.ok(seen.has("safe") and seen.has("thin") and seen.has("will_fall"), "the demo held forts show all three margins across a drag")
	var c: Dictionary = IdleLogic.cfg()
	t.ok(int(c["chip_font"]) >= 12, "the chip's text (garrison, rate, word, clock) is at least 12 px")
	t.ok(float(AwayLogic.cfg()["line_min_h_px"]) >= 44.0 and float(AwayLogic.cfg()["dismiss_w_px"]) >= 44.0, "away targets are at least 44 px")


func _contrast(t: TestUtil) -> void:
	var cfg := MapLogic.cfg()
	var panel := Palette.c("ground").lightened(float(cfg["panel_bg_lighten"]))
	for m in ["safe", "thin", "will_fall"]:
		var col := Palette.c(IdleLogic.color_key(m))
		t.ok(MapLogic.contrast_ratio(col, Palette.c("ground")) >= 4.5, "%s chip text on the ground is >= 4.5:1" % m)
		# the plate lets (1 - alpha) of whatever is behind it through: the brightest palette key at worst
		var through := Palette.c("ground").lerp(Palette.c("undead"), 1.0 - float(cfg["idle"]["plate_alpha"]))
		t.ok(MapLogic.contrast_ratio(col, through) >= 4.5, "%s chip text on its plate over green WAR lanes is %.1f:1 (>= 4.5)" % [m, MapLogic.contrast_ratio(col, through)])
	for key in ["text", "text_dim", "select"]:
		t.ok(MapLogic.contrast_ratio(Palette.c(key), panel) >= 4.5, "%s on the away panel is >= 4.5:1" % key)


func _model(t: TestUtil) -> void:
	var s := GameState.new(TestUtil.configs())
	s.debug_enabled = true
	s.cmd_debug_load_fixture("midgame_2flips")
	var m := MapModel.new(s)
	m.refresh(true)
	var real_held := IdleLogic.held_forts(m.forts).size()
	t.ok(real_held > 0 and m.margins.size() == real_held and int(m.supports["m"]) == real_held,
		"every fort the view holds has a margin, and N of M counts them (%d held)" % real_held)
	var m2 := MapModel.new(s)
	m2.nodes_demo = true
	m2.refresh(true)
	var demo_held := IdleLogic.held_forts(m2.forts).size()
	t.ok(demo_held > real_held and m2.margins.size() == demo_held, "the demo holds more forts and the model has every margin (%d)" % demo_held)
	var before := m2.margin_sig
	var id: String = m2.margins.keys()[0]
	var held := m2.margin_of(id)
	var hud := m2.hud
	var proj := IdleLogic.projection(s, hud, {"work": 0.0, "war": 1.0, "flood": 0.0}, m2.forts)
	m2.set_projection(proj)
	t.ok(m2.margin_of(id) == proj["margins"][id], "while a projection is set the chips read it")
	t.ok(m2.supports_now() == proj["war_supports"], "and so does N of M")
	t.ok(m2.margin_sig != before, "the signature changes when the projected margins differ")
	m2.clear_projection()
	t.ok(m2.margin_of(id) == held and m2.margin_sig == before, "cleared: the committed margins are back")
	t.ok(m2.supports_now() == m2.supports, "cleared: the committed N of M is back")
	# the valve panel: not dragging, N of M is the committed one even when the target differs
	var tgt := IdleLogic.projection(s, hud, {"work": 1.0, "war": 0.0, "flood": 0.0}, m2.forts)
	tgt["war_supports"] = {"n": int(m2.supports["n"]) + 1, "m": int(m2.supports["m"])}  # a target the split hasn't reached
	t.ok(tgt["war_supports"] != m2.supports_now(), "the target's N of M differs from the committed (setup)")
	t.ok(IdleLogic.panel_projection(tgt, m2.supports_now(), false)["war_supports"] == m2.supports_now(), "not dragging: the panel's N of M is supports_now()")
	t.ok(IdleLogic.panel_projection(tgt, m2.supports_now(), true)["war_supports"] == tgt["war_supports"], "dragging: the panel shows the dragged valve's")
