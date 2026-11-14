extends RefCounted
## Tests for the M-b review fixes (task 13): the objective strip's next action (next_logic.gd),
## the held forts' fall clock and its chip under the name (idle_logic.gd), raid-worthiness,
## ownership by ring weight, the valve's payoff, WAR overflow and workers cap (valve_logic.gd),
## the fit kept clear of the valve panel (map_logic.gd), callouts kept off the card, the away
## panel's losses, and the cards' new lines. No autoloads.

const VP := Vector2(1600, 900)


## A GameState stand-in with api-request #13's projection: fall_s in either allowed shape.
class FakeProj13 extends RefCounted:
	var nested := false

	func view_projection(_valve: Dictionary) -> Dictionary:
		if nested:
			return {"margins": {"a": {"margin": "thin", "fall_s": 1234.0}}}
		return {"margins": {"a": "will_fall"}, "fall_s": {"a": 99.0}}


func run() -> int:
	var t := TestUtil.new()
	t.suite("map_next")
	Palette.configure(TestUtil.load_json("res://configs/palette.json"))
	MapLogic.configure(TestUtil.load_json("res://configs/map_view.json"))
	_clocks(t)
	_projected(t)
	_chip(t)
	_anchoring(t)
	_raid(t)
	_next(t)
	_targets(t)
	_weight(t)
	_payoff(t)
	_overflow(t)
	_workers(t)
	_fit(t)
	_callouts(t)
	_away(t)
	_cards(t)
	_demo_eta(t)
	return t.failures


func _held(id: String, ship_in: float, undead: float, extra := {}) -> Dictionary:
	var f := {"id": id, "name": id.capitalize(), "held": true, "ship_in": ship_in, "undead": undead, "first_clear": false, "yield_mult": 0.5}
	f.merge(extra, true)
	return f


func _hud(war: float, mint := 10.0) -> Dictionary:
	return {"rates": [{"id": "mint", "rate": mint}], "split": {"work": 0.0, "war": war, "flood": 0.0},
		"valve": {"work": 0.5, "war": 0.5, "flood": 0.0}, "workers_steady": 10.0}


# --- the fall clock ---------------------------------------------------------------------

func _clocks(t: TestUtil) -> void:
	t.suite("map_next-clock")
	var a := _held("a", 2.0, 60.0)
	t.near(IdleLogic.garrison_rate(a, 3.0, 2), 1.5 - 2.0, 1e-9, "stand-in rate = WAR's per-fort share - pressure")
	t.near(IdleLogic.garrison_rate(_held("a", 2.0, 60.0, {"garrison_rate": 0.3}), 3.0, 2), 0.3, 1e-9, "view_fort.garrison_rate wins")
	t.near(IdleLogic.garrison_rate(a, 3.0, 0), -2.0, 1e-9, "no held count: no support")
	t.near(IdleLogic.fall_after(60.0, -0.5), 120.0, 1e-9, "fall_s = garrison / -rate")
	t.ok(IdleLogic.fall_after(60.0, 0.0) == -1.0 and IdleLogic.fall_after(60.0, 0.4) == -1.0, "a rate >= 0 is holding (-1)")
	t.ok(IdleLogic.fall_after(-5.0, -1.0) == 0.0, "an empty garrison falls now")
	t.ok(IdleLogic.fmt_fall(2400.0) == "~40 min", "~40 min")
	t.ok(IdleLogic.fmt_fall(7200.0) == "~2 h" and IdleLogic.fmt_fall(5400.0) == "~2 h", "~2 h (90 min rounds up)")
	t.ok(IdleLogic.fmt_fall(86400.0) == "~1 d" and IdleLogic.fmt_fall(3.5 * 86400.0) == "~4 d", "~1 d, ~4 d")
	t.ok(IdleLogic.fmt_fall(10.0) == "~1 min" and IdleLogic.fmt_fall(0.0) == "~1 min", "never under ~1 min")
	t.ok(IdleLogic.fmt_fall(3599.0) == "~60 min" and IdleLogic.fmt_fall(3600.0) == "~1 h", "the unit changes at the hour")
	t.ok(IdleLogic.fmt_fall(-1.0) == "", "holding has no clock")
	var forts := [_held("a", 2.0, 60.0), _held("b", 0.0, 10.0), {"id": "c", "held": false, "ship_in": 5.0, "undead": 1.0}]
	var ck := IdleLogic.committed_clocks(forts, _hud(3.0))
	t.ok(ck.size() == 2 and not ck.has("c"), "clocks cover held forts only")
	t.near(float(ck["a"]["rate"]), -0.5, 1e-9, "a: 1.5 support - 2.0 pressure")
	t.near(float(ck["a"]["fall_s"]), 120.0, 1e-9, "a falls in 60 / 0.5 s")
	t.ok(float(ck["b"]["fall_s"]) == -1.0, "b holds")
	var real := IdleLogic.committed_clocks([_held("a", 2.0, 60.0, {"garrison_rate": -1.0, "fall_s": 777.0})], _hud(3.0))
	t.ok(float(real["a"]["rate"]) == -1.0 and float(real["a"]["fall_s"]) == 777.0, "view_fort.fall_s and garrison_rate win (they include hold.break_s)")
	var cold := {"rates": [{"id": "mint", "rate": 0.0}], "split": {"work": 0.0, "war": 0.0, "flood": 0.0}}
	t.ok(not IdleLogic.streams_known(cold) and IdleLogic.streams_known(_hud(3.0)), "after a load the streams read 0 until the first substep")
	var c0 := IdleLogic.committed_clocks(forts, cold)
	t.ok(float(c0["a"]["rate"]) == 0.0 and float(c0["a"]["fall_s"]) == -1.0, "before the first substep the stand-in reads holding, not falling")


func _projected(t: TestUtil) -> void:
	t.suite("map_next-projection")
	var forts := [_held("a", 2.0, 60.0), _held("b", 0.5, 10.0)]
	var hud := _hud(3.0)
	var same := IdleLogic.projection(null, hud, hud["valve"], forts)
	var committed := IdleLogic.committed_clocks(forts, hud)
	var ok := true
	for id in committed:
		ok = ok and is_equal_approx(float(same["clocks"][id]["rate"]), float(committed[id]["rate"]))
	t.ok(ok, "a drag onto the current valve shifts no rate")
	var more := IdleLogic.projection(null, hud, {"work": 0.0, "war": 1.0, "flood": 0.0}, forts)
	var less := IdleLogic.projection(null, hud, {"work": 1.0, "war": 0.0, "flood": 0.0}, forts)
	t.ok(float(more["clocks"]["a"]["rate"]) > float(committed["a"]["rate"]) and float(less["clocks"]["a"]["rate"]) < float(committed["a"]["rate"]), "more WAR raises the rate, less lowers it")
	t.near(float(more["clocks"]["a"]["rate"]) - float(committed["a"]["rate"]), (10.0 - 5.0) / 2.0, 1e-6, "the shift is the change in WAR's per-fort share")
	t.ok(float(less["clocks"]["b"]["fall_s"]) > 0.0, "with no WAR, b falls (a projected fall_s)")
	var p13 := FakeProj13.new()
	var flat := IdleLogic.projection(p13, hud, hud["valve"], forts)
	t.ok(flat["margins"]["a"] == "will_fall" and float(flat["clocks"]["a"]["fall_s"]) == 99.0, "a separate fall_s dict in view_projection is used")
	p13.nested = true
	var nested := IdleLogic.projection(p13, hud, hud["valve"], forts)
	t.ok(nested["margins"]["a"] == "thin" and float(nested["clocks"]["a"]["fall_s"]) == 1234.0, "{margin, fall_s} margins are read and normalised to the word")
	t.ok(IdleLogic.margin_words({"a": {"margin": "thin"}, "b": "safe"}) == {"a": "thin", "b": "safe"}, "margin_words takes both shapes")
	# the model's one accessor follows the drag
	var s := GameState.new(TestUtil.configs())
	s.debug_enabled = true
	s.cmd_debug_load_fixture("midgame_2flips")
	var m := MapModel.new(s)
	m.nodes_demo = true
	m.refresh(true)
	var id: String = m.clocks.keys()[0]
	var before := m.clock_of(id)
	var sig0 := m.margin_sig
	var proj := {"margins": {id: "will_fall"}, "clocks": {id: {"rate": -3.0, "fall_s": 1800.0}}}
	m.set_projection(proj)
	var during := m.clock_of(id)
	t.ok(during["margin"] == "will_fall" and float(during["rate"]) == -3.0 and float(during["fall_s"]) == 1800.0, "while dragging the chip reads the projected margin, rate and fall")
	t.ok(m.margin_sig != sig0 and m.margin_sig.contains("~30 min"), "the redraw signature carries the coarse clock")
	m.clear_projection()
	t.ok(m.clock_of(id) == before and m.margin_sig == sig0, "released: the committed clock is back")


func _chip(t: TestUtil) -> void:
	t.suite("map_next-chip")
	var f := _held("a", 2.0, 64.0)
	var falling := IdleLogic.chip_parts(f, "will_fall", {"rate": -0.4, "fall_s": 2400.0})
	t.ok(falling["count"] == "garrison 64" and falling["rate"] == "−0.4/s", "line one: the count and its signed rate (%s, %s)" % [falling["count"], falling["rate"]])
	t.ok(falling["word"] == "WILL FALL" and falling["fall"] == "falls in ~40 min", "line two: the word and the clock")
	t.ok(falling["key"] == "danger", "the margin's colour")
	var holding := IdleLogic.chip_parts(f, "safe", {"rate": 0.3, "fall_s": -1.0})
	t.ok(holding["rate"] == "+0.3/s" and holding["fall"] == "" and holding["word"] == "SAFE", "a holding fort has no clock")
	t.ok(IdleLogic.chip_top_px(true) > IdleLogic.chip_top_px(false), "the chip drops below the first-dungeon line")
	t.ok(IdleLogic.chip_height_px() >= 2.0 * float(IdleLogic.cfg()["chip_font"]), "two lines fit the plate")


## At real positions, every fort's chip (each one as if held) sits nearer its own fort than any
## other, at the fit zoom and at chip_min_zoom, the lowest zoom a chip shows at (chips are screen
## px, so they are largest in world px there).
func _anchoring(t: TestUtil) -> void:
	t.suite("map_next-anchor")
	var s := GameState.new(TestUtil.configs())
	s.debug_enabled = true
	s.cmd_debug_load_fixture("day1")
	var m := MapModel.new(s)
	m.refresh(true)
	var fit := MapLogic.fit_view(m.content_rect(), VP, 80.0)
	var lowest := float(IdleLogic.cfg()["chip_min_zoom"])
	t.ok(not IdleLogic.chip_shown("mid", lowest - 0.01) and IdleLogic.chip_shown("mid", lowest) and not IdleLogic.chip_shown("far", 1.0), "chips show at mid and near, from chip_min_zoom")
	var cfg := MapLogic.cfg()
	t.ok(lowest >= float(cfg["zoom_far_below"]) - float(cfg["zoom_hysteresis"]), "chip_min_zoom is inside the mid tier")
	for z in [float(fit["zoom"]), lowest, 1.0]:
		var bad: Array = []
		for f in m.forts:
			var p := MapModel.to_vec(f["pos"])
			var rect := IdleLogic.chip_rect(p, MapLogic.fort_radius(int(f["tier"])), z, NodeLogic.first_dungeon_pulse(f), 180.0)
			var own := rect.get_center().distance_to(p)
			for g in m.forts:
				if g["id"] != f["id"] and rect.get_center().distance_to(MapModel.to_vec(g["pos"])) <= own:
					bad.append("%s near %s" % [f["id"], g["id"]])
		t.ok(bad.is_empty(), "zoom %.2f: every chip is nearer its own fort than any other %s" % [z, str(bad)])
		var p0 := MapModel.to_vec(m.forts[0]["pos"])
		var r0 := IdleLogic.chip_rect(p0, MapLogic.fort_radius(int(m.forts[0]["tier"])), z, false, 180.0)
		t.ok(r0.position.y > p0.y + MapLogic.fort_radius(int(m.forts[0]["tier"])) and is_equal_approx(r0.get_center().x, p0.x), "zoom %.2f: the chip hangs centred under the name" % z)


# --- raid-worthiness --------------------------------------------------------------------------

func _raid(t: TestUtil) -> void:
	t.suite("map_next-raid")
	var y := float(NextLogic.cfg()["raid_ready_yield"])
	t.ok(y > 0.0 and y <= 1.0, "raid_ready_yield is a yield fraction")
	t.ok(NextLogic.raid_ready({"first_clear": true, "yield_mult": 0.1}) == "first_clear", "an unspent first clear is ready")
	t.ok(NextLogic.raid_ready({"first_clear": false, "yield_mult": y}) == "refilled", "a cleared fort back to raid_ready_yield is refilled")
	t.ok(NextLogic.raid_ready({"first_clear": false, "yield_mult": y - 0.01}) == "", "under it, not ready")
	t.ok(NextLogic.raid_ready({"first_clear": false, "yield_mult": 1.0, "clears_since_retaken": 0}) == "refilled", "a retake resets the clear count; a cleared fort still counts")
	var forts := [{"id": "a", "name": "A", "first_clear": true}, {"id": "b", "name": "B", "first_clear": true, "first_dungeon": true},
		{"id": "c", "name": "C", "first_clear": false, "yield_mult": 1.0}, {"id": "d", "name": "D", "first_clear": false, "yield_mult": 0.2}]
	var order: Array = NextLogic.ready_forts(forts).map(func(r): return r["fort"]["id"])
	t.ok(order == ["c", "b", "a"], "refilled first, then the first dungeon, then world order (%s)" % str(order))
	t.ok(NextLogic.ready_line(forts[2], "refilled") == {"text": "C refilled: raid it", "kind": "raid", "target": "c"}, "a refilled ready line, in view_away's shape")
	t.ok(NextLogic.ready_line(forts[1], "first_clear")["text"] == "B: first clear holds a blueprint", "a first-clear ready line")
	var n := NodeLogic.ncfg()
	t.ok(str(n["raid_word"]) != "" and float(n["raid_pip_px"]) >= 6.0, "the marker carries a word and a shape")
	var sig0 := NodeLogic.fort_static_sig({"tier": 1, "cap": 80.0, "first_clear": false, "yield_mult": 0.2}, {})
	var sig1 := NodeLogic.fort_static_sig({"tier": 1, "cap": 80.0, "first_clear": false, "yield_mult": 1.0}, {})
	t.ok(sig0 != sig1, "becoming raid-ready redraws the fort's ring")
	var ring := FileAccess.get_file_as_string("res://scripts/map/map_fort_ring.gd")
	t.ok(ring.contains("NextLogic.raid_ready(") and ring.contains("raid_word"), "the ring layer draws the marker and its word")


# --- the next action ----------------------------------------------------------------------

func _inp(extra := {}) -> Dictionary:
	var d := {"forts": [], "clocks": {}, "queue": null, "vei": {}, "readout": {"odds": 0.1}, "won": false, "opening": {}}
	d.merge(extra, true)
	return d


func _next(t: TestUtil) -> void:
	t.suite("map_next-strip")
	var c := NextLogic.cfg()
	var warn := float(c["next_fall_warn_s"])
	var vespers := _held("vespers", 1.0, 30.0, {"name": "Vespers"})
	var chime := _held("chime-fort", 1.0, 30.0, {"name": "Chime Fort"})
	var forts := [vespers, chime]
	var d := NextLogic.choose(_inp())
	t.ok(d["rule"] == "default" and d["text"] == MapLogic.cfg()["objective_text"] and d["action"]["kind"] == "none", "nothing to do: the standing objective")
	t.ok(NextLogic.choose(_inp({"won": true}))["text"] == MapLogic.cfg()["objective_won_text"], "won: the victory line")
	# 1. a fort about to fall
	var clocks := {"vespers": {"fall_s": 2400.0}, "chime-fort": {"fall_s": 3000.0}}
	var f1 := NextLogic.choose(_inp({"forts": forts, "clocks": clocks}))
	t.ok(f1["rule"] == "fall" and f1["target"] == "vespers", "the smallest fall_s wins")
	t.ok(f1["text"] == "Vespers falls in ~40 min: raise WAR or send Relish", "fall line (%s)" % f1["text"])
	t.ok(NextLogic.choose(_inp({"forts": forts, "clocks": {"vespers": {"fall_s": warn}}}))["rule"] != "fall", "at next_fall_warn_s or later: not urgent")
	t.ok(NextLogic.choose(_inp({"forts": forts, "clocks": {"vespers": {"fall_s": -1.0}}}))["rule"] != "fall", "holding: never")
	# sticky: a near-equal rival does not steal the line; a much sooner one does
	var near := {"vespers": {"fall_s": 2400.0}, "chime-fort": {"fall_s": 2300.0}}
	t.ok(NextLogic.choose(_inp({"forts": forts, "clocks": near}), f1)["target"] == "vespers", "the kept fort holds against a near-equal rival")
	t.ok(NextLogic.choose(_inp({"forts": forts, "clocks": near}))["target"] == "chime-fort", "without a previous pick the sooner one wins")
	var urgent := {"vespers": {"fall_s": 2400.0}, "chime-fort": {"fall_s": 2400.0 * float(c["switch_ratio"]) - 1.0}}
	t.ok(NextLogic.choose(_inp({"forts": forts, "clocks": urgent}), f1)["target"] == "chime-fort", "a fort falling in under switch_ratio of the kept one's time takes over")
	var tick := NextLogic.choose(_inp({"forts": forts, "clocks": {"vespers": {"fall_s": 1800.0}}}), f1)
	t.ok(tick["target"] == "vespers" and tick["text"].contains("~30 min"), "same pick: the coarse clock updates in place")
	# 2. a raid ready
	var ash := {"id": "ashgate", "name": "Ashgate", "first_clear": false, "yield_mult": 1.0}
	var r2 := NextLogic.choose(_inp({"forts": [ash]}))
	t.ok(r2["rule"] == "raid" and r2["text"] == "Ashgate refilled: raid it" and r2["action"] == {"kind": "fort", "id": "ashgate"}, "a refilled raid")
	var sluice := {"id": "old-sluice", "name": "Old Sluice", "first_clear": true, "first_dungeon": true}
	t.ok(NextLogic.choose(_inp({"forts": [sluice]}))["text"] == "Old Sluice: first clear holds a blueprint", "a first clear")
	var two := [{"id": "a", "name": "A", "first_clear": false, "yield_mult": 1.0}, {"id": "b", "name": "B", "first_clear": false, "yield_mult": 1.0}]
	t.ok(NextLogic.choose(_inp({"forts": two}), {"rule": "raid", "target": "b"})["target"] == "b", "a kept raid target holds while it is still ready")
	# 3. the queue
	t.ok(NextLogic.choose(_inp({"queue": []}))["rule"] == "queue", "an empty queue")
	t.ok(NextLogic.choose(_inp({"queue": [{"building_id": "pit"}]}))["rule"] != "queue", "a queued build: not this rule")
	t.ok(NextLogic.choose(_inp({"queue": null}))["rule"] != "queue", "no queue in the view: skipped")
	t.ok(NextLogic.choose(_inp({"queue": []}))["text"] == str(c["queue_text"]), "queue line")
	# 4. Vei
	var v4 := NextLogic.choose(_inp({"vei": {"can_begin": true}, "readout": {"odds": 0.61}}))
	t.ok(v4["rule"] == "vei" and v4["text"] == "Vei can be faced: your odds 61%", "can_begin: Vei (%s)" % v4["text"])
	t.ok(NextLogic.choose(_inp({"readout": {"odds": float(c["next_vei_odds"])}}))["rule"] == "vei", "odds at next_vei_odds: Vei")
	t.ok(NextLogic.choose(_inp({"readout": {"odds": float(c["next_vei_odds"]) - 0.01}}))["rule"] == "default", "under it, no")
	# priority
	var all := _inp({"forts": [vespers, ash], "clocks": {"vespers": {"fall_s": 600.0}}, "queue": [], "vei": {"can_begin": true}})
	t.ok(NextLogic.choose(all)["rule"] == "fall", "fall beats everything")
	all["clocks"] = {}
	t.ok(NextLogic.choose(all)["rule"] == "raid", "then a raid")
	all["forts"] = []
	t.ok(NextLogic.choose(all)["rule"] == "queue", "then the queue")
	all["queue"] = null
	t.ok(NextLogic.choose(all)["rule"] == "vei", "then Vei")
	# the opening's override
	var op := NextLogic.choose(_inp({"forts": [vespers], "clocks": {"vespers": {"fall_s": 60.0}}, "opening": {"text": "Drag the triangle", "target": "vespers"}}))
	t.ok(op["rule"] == "opening" and op["text"] == "Drag the triangle" and op["action"] == {"kind": "fort", "id": "vespers"}, "set_opening_ask beats every rule and keeps its target")
	t.ok(NextLogic.choose(_inp({"forts": [vespers], "clocks": {"vespers": {"fall_s": 60.0}}, "opening": {"text": "", "target": "vespers"}}))["rule"] == "fall", "an empty ask clears the override")
	var hud_src := FileAccess.get_file_as_string("res://scripts/map/map_hud.gd")
	t.ok(hud_src.contains("func set_opening_ask(text: String, target: String)"), "the HUD has the opening hook")


func _targets(t: TestUtil) -> void:
	t.suite("map_next-targets")
	var ids := ["ashgate"]
	t.ok(AwayLogic.action("ashgate", ids) == {"kind": "fort", "id": "ashgate"}, "a fort selects and centres it")
	t.ok(AwayLogic.action("queue", ids) == {"kind": "dive", "to": "covington"}, "the queue dives into Covington")
	t.ok(AwayLogic.action("vei", ids) == {"kind": "vei"}, "Vei selects her")
	t.ok(AwayLogic.action("", ids)["kind"] == "none", "the default line does nothing")
	var q := NextLogic.choose(_inp({"queue": []}))
	t.ok(q["action"] == {"kind": "dive", "to": "covington"}, "the queue line dives")
	t.ok(NextLogic.choose(_inp({"vei": {"can_begin": true}}))["action"] == {"kind": "vei"}, "the Vei line selects Vei")
	var wm := FileAccess.get_file_as_string("res://scripts/map/world_map.gd")
	t.ok(wm.contains("hud.next_chosen.connect(") and wm.contains("func _act_on("), "world_map acts on the strip's clicks")


# --- ownership by weight ----------------------------------------------------------------------

func _weight(t: TestUtil) -> void:
	t.suite("map_next-weight")
	var hers := NodeLogic.ring_weight(NodeLogic.HERS)
	for st in [IdleLogic.SAFE, IdleLogic.THIN, IdleLogic.WILL_FALL]:
		t.ok(NodeLogic.ring_weight(st) >= 2.0 * hers, "held (%s) ring stroke is at least 2x hers (%.1f vs %.1f)" % [st, NodeLogic.ring_weight(st), hers])
		t.ok(NodeLogic.has_core(st), "held (%s) fills its core" % st)
	t.ok(NodeLogic.ring_weight(NodeLogic.OVERRUN) >= 2.0 * hers and NodeLogic.has_core(NodeLogic.OVERRUN), "overrun (your garrison inside, not flipped) reads as yours too: heavy ring and core")
	for st in [NodeLogic.HERS, NodeLogic.CONTESTED, NodeLogic.EMPTIED]:
		t.ok(NodeLogic.ring_weight(st) == 1.0 and not NodeLogic.has_core(st), "%s keeps the thin ring and no core" % st)
	var ring := FileAccess.get_file_as_string("res://scripts/map/map_fort_ring.gd")
	t.ok(ring.contains("NodeLogic.ring_weight(") and ring.contains("NodeLogic.has_core("), "the ring layer draws with these")


# --- the valve: payoff, overflow, workers -----------------------------------------------------

func _payoff(t: TestUtil) -> void:
	t.suite("map_next-payoff")
	var vc: Dictionary = MapLogic.cfg()["controls"]
	var frac := float(vc["war_drain_frac"])
	var window := float(vc["drain_window_s"])
	var k := 12000.0
	t.near(ValveLogic.diff_at(2.0, {"split": {"war": 6.0, "flood": 3.0}}, {"war": 4.0, "flood": 1.0}, frac), 2.0 + 2.0 + 2.0 * frac, 1e-9, "stand-in: diff_ema + dFLOOD + dWAR x war_drain_frac")
	t.near(ValveLogic.diff_at(2.0, {"backlog_diff": -7.0, "split": {"war": 9.0}}, {}, frac), -7.0, 1e-9, "view_projection's backlog_diff wins")
	t.near(ValveLogic.drain_at(1000.0, -10.0), 100.0, 1e-9, "drain = backlog / -diff when shrinking")
	t.ok(ValveLogic.drain_at(1000.0, 0.0) == -1.0 and ValveLogic.drain_at(1000.0, 5.0) == -1.0, "holding or growing: ∞")
	t.near(ValveLogic.odds_at(12000.0, 0.0, window, k), 0.5, 1e-9, "odds = b / (b + K)")
	t.near(ValveLogic.odds_at(12000.0, 10.0, window, k), (12000.0 + 10.0 * window) / (24000.0 + 10.0 * window), 1e-9, "after the window at the diff")
	t.ok(ValveLogic.odds_at(100.0, -1000.0, window, k) == 0.0, "a drained backlog has no odds")
	# a drag onto the current valve: both sides identical
	var hud := {"rates": [{"id": "mint", "rate": 20.0}], "valve": {"work": 0.4, "war": 0.45, "flood": 0.15}, "split": {"work": 8.0, "war": 9.9, "flood": 3.0}, "workers_steady": 0.0}
	var vei := {"backlog": 18000.0, "diff_ema": 2.1}
	var base: Dictionary = ValveLogic.project(hud, hud["valve"])["split"]
	var same := ValveLogic.payoff(vei, ValveLogic.project(hud, hud["valve"]), base, k)
	t.ok(same["now"] == same["then"], "dragging onto the current valve changes nothing")
	var flood := ValveLogic.payoff(vei, ValveLogic.project(hud, {"work": 0.2, "war": 0.45, "flood": 0.35}), base, k)
	t.ok(float(flood["then"]["diff"]) > float(flood["now"]["diff"]) and float(flood["then"]["odds"]) > float(flood["now"]["odds"]), "more FLOOD: a higher differential and better odds")
	var line := ValveLogic.payoff_line(flood, 0.05)
	t.ok(line.begins_with("Vei ▲ +2.1/s → ▲ +"), "the line compares Vei's differential now and dragged (%s)" % line)
	t.ok(line.contains(" · odds in ") and line.contains("% → "), "growing on both sides: then the odds after the window")
	var falling := ValveLogic.payoff({"backlog": 1000.0, "diff_ema": -2.0}, ValveLogic.project(hud, {"work": 0.6, "war": 0.4, "flood": 0.0}), base, k)
	var fl := ValveLogic.payoff_line(falling, 0.05)
	t.ok(fl.contains(" · drain ") and fl.contains("▼"), "a shrinking queue is ▼ and shows the drain (%s)" % fl)
	t.ok(ValveLogic.payoff_shown(true, -1.0), "shown while dragging")
	t.ok(ValveLogic.payoff_shown(false, 0.0) and ValveLogic.payoff_shown(false, float(vc["payoff_hold_s"]) - 0.01), "and for payoff_hold_s after release")
	t.ok(not ValveLogic.payoff_shown(false, float(vc["payoff_hold_s"])) and not ValveLogic.payoff_shown(false, -1.0), "then hidden; never shown before a drag")
	var tgt := Vector2(50, 50)
	t.ok(ValveLogic.now_ring_pos(tgt, tgt).distance_to(tgt) > 0.0 and is_equal_approx(ValveLogic.now_ring_pos(tgt, tgt).distance_to(tgt), float(vc["now_offset_px"])), "a coinciding now ring sits now_offset_px off the target")
	t.ok(ValveLogic.now_ring_pos(Vector2(80, 50), tgt) == Vector2(80, 50), "a slewing now ring stays where the split is")
	var valve_src := FileAccess.get_file_as_string("res://scripts/map/map_valve.gd")
	t.ok(valve_src.contains("ValveLogic.payoff_shown(") and valve_src.contains("_since_release += delta"), "the panel times the hold from _process")


func _overflow(t: TestUtil) -> void:
	t.suite("map_next-overflow")
	var lane := {"id": "war:covington:vei", "kind": "war", "from": "covington", "to": "vei", "rate": 3.1}
	var other := {"id": "war:covington:ashgate", "kind": "war", "from": "covington", "to": "ashgate", "rate": 9.0}
	t.ok(ValveLogic.war_overflow({}, [other], {}, false) == 0.0, "no war:covington:vei lane: no overflow")
	t.near(ValveLogic.war_overflow({}, [other, lane], {}, false), 3.1, 1e-9, "today: the war:covington:vei lane's rate")
	t.near(ValveLogic.war_overflow({"war_overflow": 2.0}, [lane], {}, false), 2.0, 1e-9, "view_hud.war_overflow wins when present")
	var proj := {"split": {"war_overflow": 5.0}}
	t.near(ValveLogic.war_overflow({"war_overflow": 2.0}, [lane], proj, true), 5.0, 1e-9, "while dragging, the projection's split.war_overflow")
	t.near(ValveLogic.war_overflow({"war_overflow": 2.0}, [lane], proj, false), 2.0, 1e-9, "not dragging, the committed one")
	t.near(ValveLogic.war_overflow({}, [lane], {"split": {}}, true), 3.1, 1e-9, "a projection without the field keeps the committed source")
	t.ok(ValveLogic.overflow_parts(0.0).is_empty(), "no overflow, no line")
	var p := ValveLogic.overflow_parts(3.1)
	t.ok(p["rate"] == "+3.1/s" and p["text"] == "overflows to Vei", "the line: a signed rate in the rate face, then words")


func _workers(t: TestUtil) -> void:
	t.suite("map_next-workers")
	t.ok(ValveLogic.workers_kept(335.0, {}, 25, 10.0) == 35.0, "min(slots + idle_cap, steady)")
	t.ok(ValveLogic.workers_kept(20.0, {}, 25, 10.0) == 20.0, "under the cap: steady")
	t.ok(ValveLogic.workers_kept(335.0, {"workers_steady_kept": 31.0}, 25, 10.0) == 31.0, "view_hud.workers_steady_kept wins")
	t.ok(ValveLogic.workers_kept(335.0, {"workers_steady_kept": 31.0}, 25, 10.0, true) == 35.0, "while dragging, the projected steady is capped")
	var cfgs := TestUtil.configs()
	var cap := float(cfgs["economy"]["worker"]["idle_cap"])
	for fx in [["pre_vei", 35.0], ["midgame_2flips", 19.0]]:
		var s := GameState.new(cfgs)
		s.debug_enabled = true
		s.cmd_debug_load_fixture(fx[0])
		var m := MapModel.new(s)
		m.refresh(true)
		var kept := ValveLogic.workers_kept(float(m.hud["workers_steady"]), m.hud, m.job_slots, cap)
		t.near(kept, float(fx[1]), 1e-6, "%s: workers → %d, the town's real total (steady reads %d)" % [fx[0], roundi(kept), roundi(float(m.hud["workers_steady"]))])


# --- the fit and the callouts ------------------------------------------------------------------

## The HUD's rects at 1600x900: the valve panel (a little taller than its triangle needs, for the
## payoff lines), the objective strip and Relish's chip under it.
func _hud_rects() -> Array:
	return [_panel_rect(), Rect2(0, 34, 460, 50), Rect2(10, 90, 300, 110)]


func _panel_rect() -> Rect2:
	var cfg := MapLogic.cfg()
	var c: Dictionary = cfg["controls"]
	var w := float(c["valve_pad_px"]) + float(cfg["valve_tri_px"]) + 2.0 * float(c["valve_inner_pad_px"]) + float(c["valve_rows_w_px"])
	var h := 340.0
	return Rect2(float(c["valve_margin_px"][0]), VP.y - float(c["valve_margin_px"][1]) - h, w, h)


func _fit(t: TestUtil) -> void:
	t.suite("map_next-fit")
	var cfg := MapLogic.cfg()
	var rects := _hud_rects()
	var inset := 34.0  # the top bar; the strip and the chip are obstacles
	var floor_z := float(cfg["zoom_far_below"]) + float(cfg["zoom_hysteresis"])
	for fx in [["pre_vei", false], ["midgame_2flips", false], ["midgame_2flips", true], ["day1", false]]:
		var s := GameState.new(TestUtil.configs())
		s.debug_enabled = true
		s.cmd_debug_load_fixture(fx[0])
		var m := MapModel.new(s)
		m.nodes_demo = fx[1]
		m.refresh(true)
		var items := m.fit_items()
		var v := MapLogic.fit_view_clear(m.content_rect(), VP, inset, items, rects)
		var z := float(v["zoom"])
		var bad: Array = []
		for i in items.size():
			var r := MapLogic.item_rect(items[i], z, v["centre"], VP)
			if rects.any(func(o: Rect2): return r.intersects(o)) or r.end.y > VP.y or r.position.y < inset or r.position.x < 0.0 or r.end.x > VP.x:
				bad.append(m.forts[i]["id"] if i < m.forts.size() else "vei")
		t.ok(bad.is_empty(), "%s%s: every fort's ring and labels and Vei clear of the valve panel, the strip and the chip, on screen %s (zoom %.3f)" % [fx[0], " (demo)" if fx[1] else "", str(bad), z])
		t.ok(IdleLogic.chip_shown("mid", z), "%s: the chips show at the fit zoom" % fx[0])
		t.ok(z >= floor_z - 1e-6, "%s: the fit stays mid tier (%.3f >= %.2f)" % [fx[0], z, floor_z])
		var content := m.content_rect()
		var tl: Vector2 = (content.position - v["centre"]) * z + VP * 0.5
		var br: Vector2 = (content.end - v["centre"]) * z + VP * 0.5
		t.ok(tl.x >= -1e-3 and br.x <= VP.x + 1e-3 and tl.y >= inset - 1e-3 and br.y <= VP.y + 1e-3, "%s: the whole content stays on screen" % fx[0])
		var sluice: Dictionary = items[m.forts.map(func(f): return f["id"]).find("old-sluice")]
		t.ok(MapLogic.item_rect(sluice, z, v["centre"], VP).end.y <= VP.y - float(cfg["fit_bottom_px"]) + 1e-3, "%s: Old Sluice's lines end above the bottom edge" % fx[0])
	t.ok(MapLogic.fit_view_clear(Rect2(), VP, inset, [], []).is_empty(), "degenerate input fits nothing")
	var plain := MapLogic.fit_view(Rect2(0, 0, 1000, 1000), VP, inset)
	t.ok(MapLogic.fit_view_clear(Rect2(0, 0, 1000, 1000), VP, inset, [], []) == plain, "nothing in the way: fit_view's answer")
	var cam := FileAccess.get_file_as_string("res://scripts/map/map_camera.gd")
	t.ok(cam.contains("MapLogic.fit_view_clear("), "the camera fits around the panels")


func _callouts(t: TestUtil) -> void:
	t.suite("map_next-callouts")
	var size := Vector2(100, 20)
	var anchor := Vector2(500, 300)
	var cands := HudLogic.candidate_rects(anchor, size, Vector2(10, 10))
	var card := cands[0].grow(2.0)
	var picks := HudLogic.place([cands], 8, 2.0, [card])
	t.ok(picks[0] != 0 and picks[0] >= 0, "the first candidate under the card is skipped (took %d)" % picks[0])
	var all := Rect2(0, 0, 2000, 2000)
	t.ok(HudLogic.place([cands], 8, 2.0, [all])[0] == -1, "every candidate under the card: the callout is dropped")
	t.ok(HudLogic.place([cands], 8, 2.0)[0] == 0, "no card: the first candidate")
	# the conversion into the callouts' frame (world x zoom)
	var cam_pos := Vector2(1200, 800)
	var z := 0.6
	var world := Vector2(1500, 1000)
	var screen := (world - cam_pos) * z + VP * 0.5
	var conv := HudLogic.screen_to_zoomed(Rect2(screen, Vector2(10, 10)), cam_pos, z, VP)
	t.ok(conv.position.is_equal_approx(world * z), "a screen rect lands where world x zoom puts it")
	var co := FileAccess.get_file_as_string("res://scripts/map/map_callouts.gd")
	t.ok(co.contains("HudLogic.screen_to_zoomed(") and co.contains("cam.position"), "the callouts keep off the open card and re-place on a pan")


# --- the away panel -------------------------------------------------------------------------

func _away(t: TestUtil) -> void:
	t.suite("map_next-away")
	var losses := [{"text": "Ashgate retaken: raid it", "kind": "retaken", "target": "ashgate"},
		{"text": "Vespers retaken: raid it", "kind": "retaken", "target": "vespers"},
		{"text": "village Lorn lost to Vei", "kind": "village_lost", "target": ""}]
	t.ok(AwayLogic.losses_count(losses) == "2 forts lost · 1 village lost", "the count (%s)" % AwayLogic.losses_count(losses))
	t.ok(AwayLogic.losses_count([losses[0]]) == "1 fort lost", "singular")
	t.ok(AwayLogic.losses_count([{"kind": "overflow", "text": "x"}]) == "", "an overflow alone has no count")
	var b := AwayLogic.build({"losses": losses}, ["ashgate", "vespers"])
	var sec: Dictionary = b["sections"][0]
	t.ok(sec["key"] == "losses" and sec["lines"][0]["text"] == "2 forts lost · 1 village lost" and sec["lines"][0]["action"]["kind"] == "none", "losses lead with their count")
	t.ok(sec["lines"][1]["action"] == {"kind": "fort", "id": "ashgate"} and sec["lines"][2]["action"] == {"kind": "fort", "id": "vespers"}, "lost forts are clickable")
	t.ok(sec["lines"][3]["action"]["kind"] == "none", "a lost village is not")
	var demo: Dictionary = MapLogic.cfg()["demo_away"]
	var refilled := {}
	for row in demo["gains"] + demo["ready"]:
		if str(row["kind"]) in ["refilled", "raid"]:
			refilled[str(row["text"]).split(" ")[0]] = true
	var clash: Array = []
	for row in demo["losses"]:
		if str(row["kind"]) == "retaken" and refilled.has(str(row["text"]).split(" ")[0]):
			clash.append(row["text"])
		if str(row["kind"]) == "village_lost":
			t.ok(str(row["text"]).begins_with("village "), "a lost village is named with its noun (%s)" % row["text"])
	t.ok(clash.is_empty(), "the demo never has one fort refilled and retaken %s" % str(clash))
	var panel := FileAccess.get_file_as_string("res://scripts/map/map_away.gd")
	t.ok(panel.contains("sec[\"key\"] != \"gains\""), "the panel builds buttons for lost forts too")


# --- the cards ----------------------------------------------------------------------------------

func _cards(t: TestUtil) -> void:
	t.suite("map_next-cards")
	var f := {"held": true, "held_s_left": 374.0, "undead": 64.0}
	t.ok(CardLogic.held_chip(f)["text"] == "HELD · 6:14 left", "without fort.margin: the grace countdown")
	f["margin"] = "safe"
	var hc := CardLogic.held_chip(f)
	t.ok(hc["text"] == "garrison 64 · SAFE" and hc["key"] == "undead", "with fort.margin: the garrison and the margin (%s)" % hc["text"])
	f["margin"] = "will_fall"
	t.ok(CardLogic.held_chip(f)["key"] == "danger", "in the margin's colour")
	var loot: Dictionary = MapLogic.cfg()["cards"]["loot"]
	t.ok(CardLogic.loot_line({"yield_mult": 1.0}, loot) == "Loot: full (fresh)", "full loot says fresh")
	t.ok(CardLogic.first_clear_line({"first_clear": true}) == "first clear: guaranteed blueprint", "the first clear's reward")
	var pin := CardLogic.pinned_odds({"odds": 0.61, "sign": 1, "drain_s": -1.0, "backlog": 18000.0})
	t.ok(pin == "Your odds 61% ▲ gaining · drains in ∞", "the pinned odds (%s)" % pin)
	var cards: Dictionary = MapLogic.cfg()["cards"]
	t.ok(str(cards["vei_odds_label"]).to_lower().contains("your odds") and str(cards["vei_sign_label"]).contains("▲ = winning"), "the Vei card says whose odds and what ▲ means")
	var sb := FileAccess.get_file_as_string("res://scripts/map/map_sidebar.gd")
	t.ok(sb.contains("CardLogic.pinned_odds("), "the odds are pinned in the actions, beside BEGIN")


func _demo_eta(t: TestUtil) -> void:
	t.suite("map_next-demo")
	var s := GameState.new(TestUtil.configs())
	s.debug_enabled = true
	s.cmd_debug_load_fixture("midgame_2flips")
	var m := MapModel.new(s)
	m.nodes_demo = true
	m.realm_cfg = TestUtil.configs()["realm"]
	m.refresh(true)
	var speed := float(m.realm_cfg["relish"]["travel_speed"])
	var to := m.node_pos(str(m.relish["target"]))
	var eta := float(m.relish["eta_s"])
	t.ok(str(m.relish["state"]) == "travelling" and eta > 0.0, "the demo's travelling Relish has a real ETA (%.2f s)" % eta)
	t.near(eta, MapModel.to_vec(m.relish["pos"]).distance_to(to) / speed, 1e-3, "the rest of the way at her travel speed")
	t.ok(RelishLogic.fmt_eta(eta) != "0:00", "so stills never read 0:00")
