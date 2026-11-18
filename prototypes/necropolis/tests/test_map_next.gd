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


## Projection with a real garrison_rate for fort a, in either shape.
class FakeRate13 extends RefCounted:
	var nested := false

	func view_projection(_valve: Dictionary) -> Dictionary:
		if nested:
			return {"margins": {"a": {"margin": "thin", "fall_s": 1234.0, "garrison_rate": -0.7}}}
		return {"margins": {"a": "will_fall"}, "fall_s": {"a": 99.0}, "garrison_rate": {"a": -0.7}}


func run() -> int:
	var t := TestUtil.new()
	t.suite("map_next")
	Palette.configure(TestUtil.load_json("res://configs/palette.json"))
	MapLogic.configure(TestUtil.load_json("res://configs/map_view.json"))
	_clocks(t)
	_projected(t)
	_chip(t)
	_horizon(t)
	_quiet(t)
	_anchoring(t)
	_clear_of_token(t)
	_raid(t)
	_raid_set(t)
	_raid_model(t)
	_next(t)
	_order(t)
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
	var rp := FakeRate13.new()
	var rflat := IdleLogic.projection(rp, hud, hud["valve"], forts)
	t.ok(is_equal_approx(float(rflat["clocks"]["a"]["rate"]), -0.7) and float(rflat["clocks"]["a"]["fall_s"]) == 99.0, "a real garrison_rate dict is the chip's rate, beside the real fall_s")
	t.ok(is_equal_approx(float(rflat["clocks"]["b"]["rate"]), float(committed["b"]["rate"])), "a fort the real rate leaves out keeps the stand-in")
	rp.nested = true
	var rnest := IdleLogic.projection(rp, hud, hud["valve"], forts)
	t.ok(is_equal_approx(float(rnest["clocks"]["a"]["rate"]), -0.7) and float(rnest["clocks"]["a"]["fall_s"]) == 1234.0, "a real garrison_rate inside the margins is read too")
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
	t.ok(holding["rate"] == "+0.3/s" and holding["fall"] == "holds" and holding["word"] == "SAFE", "a SAFE fort whose clock holds says SAFE · holds")
	var safe_falls := IdleLogic.chip_parts(f, "safe", {"rate": -0.1, "fall_s": 32400.0})
	t.ok(safe_falls["word"] == "SAFE" and safe_falls["fall"] == "falls in ~9 h", "a SAFE fort with a real fall_s keeps the fall text (%s)" % safe_falls["fall"])
	t.ok(IdleLogic.chip_parts(f, "thin", {"rate": 0.0, "fall_s": -1.0})["fall"] == "" and IdleLogic.chip_parts(f, "will_fall", {"rate": 0.0, "fall_s": -1.0})["fall"] == "",
		"THIN and WILL FALL with no clock are unchanged")
	var cfg := IdleLogic.cfg()
	var chip_text := "%s%s%s" % [holding["word"], cfg["chip_sep"], holding["fall"]]
	t.ok(chip_text == "SAFE · holds", "the chip's line two reads %s" % chip_text)
	t.ok(IdleLogic.chip_top_px(true) > IdleLogic.chip_top_px(false), "the chip drops below the first-dungeon line")
	t.ok(IdleLogic.chip_height_px() >= 2.0 * float(IdleLogic.cfg()["chip_font"]), "two lines fit the plate")


## The fort's horizon: the nearer of the garrison clock and the hold timer.
func _horizon(t: TestUtil) -> void:
	t.suite("map_next-horizon")
	t.ok(NextLogic.restarted(500.0, 3.0) and not NextLogic.restarted(500.0, 500.0) and not NextLogic.restarted(500.0, 900.0) and not NextLogic.restarted(-1.0, 0.0),
		"time going backwards (and only that) starts the hysteresis memory over")
	var f := _held("a", 0.0, 10.0, {"held_s_left": 600.0})
	t.near(IdleLogic.fort_horizon(f, {"fall_s": 9000.0}), 600.0, 1e-6, "the timer alone is nearer")
	t.near(IdleLogic.fort_horizon(f, {"fall_s": 300.0}), 300.0, 1e-6, "the fall clock is nearer: the minimum")
	t.near(IdleLogic.fort_horizon(f, {"fall_s": -1.0}), 600.0, 1e-6, "the timer alone")
	t.near(IdleLogic.fort_horizon(_held("a", 0.0, 10.0), {"fall_s": 900.0}), 900.0, 1e-6, "the fall clock alone")
	t.near(IdleLogic.fort_horizon(_held("a", 0.0, 10.0), {"fall_s": -1.0}), -1.0, 1e-6, "neither: -1")
	t.near(IdleLogic.fort_horizon(_held("a", 0.0, 10.0, {"held_s_left": 0.0}), {}), -1.0, 1e-6, "an empty timer does not count")
	var sp := IdleLogic.chip_parts(f, "safe", {"rate": 0.3, "fall_s": -1.0})
	t.ok(sp["word"] == "HOLD" and sp["fall"] == "ends in ~10 min" and sp["key"] == "select", "a SAFE chip with only a timer reads HOLD, not SAFE (%s, %s)" % [sp["word"], sp["fall"]])
	var tp := IdleLogic.chip_parts(f, "safe", {"rate": 0.3, "fall_s": 9000.0})
	t.ok(tp["word"] == "HOLD" and tp["fall"] == "ends in ~10 min" and tp["key"] == IdleLogic.cfg()["colors"]["hold"], "the timer nearer than the fall: HOLD in the hold colour")
	var fp := IdleLogic.chip_parts(f, "thin", {"rate": -0.2, "fall_s": 300.0})
	t.ok(fp["word"] == "THIN" and fp["fall"] == "falls in ~5 min" and fp["key"] == "select", "the fall nearer than the timer keeps its margin word (%s)" % fp["fall"])
	t.ok(IdleLogic.chip_parts(f, "will_fall", {"rate": -0.2, "fall_s": 300.0})["word"] == "WILL FALL", "WILL FALL too")
	var np := IdleLogic.chip_parts(_held("a", 0.0, 10.0), "safe", {"rate": 0.3, "fall_s": -1.0})
	t.ok(np["word"] == "SAFE" and np["fall"] == "holds", "no timer: unchanged")
	t.ok(IdleLogic.fort_horizon_parts(f, {"fall_s": 9000.0})["kind"] == "hold" and IdleLogic.fort_horizon_parts(f, {"fall_s": 300.0})["kind"] == "fall"
		and IdleLogic.fort_horizon_parts(f, {"fall_s": 600.0})["kind"] == "fall" and IdleLogic.fort_horizon_parts(_held("a", 0.0, 10.0), {})["kind"] == "", "the kind of the winning term (a tie is the fall)")
	var ln := {"forts": [_held("a", 0.0, 10.0, {"held_s_left": 180.0}), _held("b", 0.0, 10.0, {"held_s_left": 7200.0})],
		"clocks": {"a": {"fall_s": -1.0}, "b": {"fall_s": -1.0}}}
	t.ok(NextLogic.leave_text(ln) == "If you leave, A falls in ~3 min", "a near timer is a risk, not safe (%s)" % NextLogic.leave_text(ln))
	ln["forts"] = [_held("b", 0.0, 10.0, {"held_s_left": 32400.0})]
	t.ok(NextLogic.leave_text(ln) == "Safe to leave: first fort falls in ~9 h", "a far timer is safe (%s)" % NextLogic.leave_text(ln))
	ln["forts"] = [_held("b", 0.0, 10.0, {"held_s_left": 3600.0})]
	t.ok(NextLogic.leave_text(ln).begins_with("Safe to leave"), "leave_safe_s itself is safe")
	ln["forts"] = [_held("b", 0.0, 10.0, {"held_s_left": 3599.0})]
	t.ok(NextLogic.leave_text(ln).begins_with("If you leave"), "just under it is a risk")


## The quiet state and its leave line (D2).
func _quiet(t: TestUtil) -> void:
	t.suite("map_next-quiet")
	var a := _held("a", 0.0, 10.0)
	var b := _held("b", 0.0, 10.0)
	var safe := {"a": "safe", "b": "safe"}
	var inp := {"forts": [a, b], "margins": safe, "clocks": {"a": {"fall_s": -1.0}, "b": {"fall_s": -1.0}}}
	t.ok(NextLogic.quiet(inp, NextLogic.DEFAULT), "two held SAFE forts, no tithe: quiet")
	t.ok(NextLogic.quiet(inp, NextLogic.RAID) and NextLogic.quiet(inp, NextLogic.VEI), "a raid or Vei pick does not break it")
	t.ok(not NextLogic.quiet({"forts": [{"id": "x", "held": false}], "margins": {}}, NextLogic.DEFAULT), "no held fort: not quiet")
	t.ok(not NextLogic.quiet({"forts": [], "margins": {}}, NextLogic.DEFAULT), "no forts: not quiet")
	t.ok(not NextLogic.quiet({"forts": [a, b], "margins": {"a": "safe", "b": "thin"}}, NextLogic.DEFAULT), "a THIN fort: not quiet")
	t.ok(not NextLogic.quiet({"forts": [a, b], "margins": {"a": "will_fall", "b": "safe"}}, NextLogic.DEFAULT), "a WILL FALL fort: not quiet")
	var tith := _held("b", 0.0, 10.0, {"tithe": {"targeted": true, "eta_s": 100.0, "wave_active": false}})
	t.ok(not NextLogic.quiet({"forts": [a, tith], "margins": safe}, NextLogic.DEFAULT), "a targeted tithe: not quiet")
	var calm := _held("b", 0.0, 10.0, {"tithe": {"targeted": false, "eta_s": -1.0, "wave_active": false}})
	t.ok(NextLogic.quiet({"forts": [a, calm], "margins": safe}, NextLogic.DEFAULT), "an untargeted tithe is fine")
	for rule in [NextLogic.FALL, NextLogic.OPENING, NextLogic.WON]:
		t.ok(not NextLogic.quiet(inp, rule), "rule %s: not quiet" % rule)
	t.ok(NextLogic.leave_text(inp) == "Safe to leave: every fort holds at these rates", "every clock < 0: the holding line (%s)" % NextLogic.leave_text(inp))
	var fl := {"forts": [a, b], "margins": safe, "clocks": {"a": {"fall_s": 32400.0}, "b": {"fall_s": 7200.0}}}
	t.ok(NextLogic.leave_text(fl) == "Safe to leave: first fort falls in ~2 h", "the smallest fall_s names the horizon (%s)" % NextLogic.leave_text(fl))
	fl["clocks"] = {"a": {"fall_s": -1.0}, "b": {"fall_s": 32400.0}}
	t.ok(NextLogic.leave_text(fl) == "Safe to leave: first fort falls in ~9 h", "a holding fort is skipped (%s)" % NextLogic.leave_text(fl))
	# a real view's fall_s on the fort reaches the clock and so the line
	var real := _held("a", 0.0, 10.0, {"fall_s": 32400.0, "garrison_rate": -0.1})
	var ck := IdleLogic.committed_clocks([real], _hud(1.0))
	t.ok(NextLogic.leave_text({"forts": [real], "clocks": ck}) == "Safe to leave: first fort falls in ~9 h", "a fort dict carrying fall_s")
	var hud := FileAccess.get_file_as_string("res://scripts/map/map_hud.gd")
	var wm := FileAccess.get_file_as_string("res://scripts/map/world_map.gd")
	t.ok(wm.contains("--skip-time=") and wm.contains("cmd_debug_skip_time(") and wm.contains("not Game.state.debug_enabled or _skipped"), "--skip-time is a once-only debug flag")
	t.ok(hud.contains("_leave = _label(") and hud.contains("NextLogic.quiet(inp"), "the HUD shows the line from NextLogic.quiet")


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


func _with(f: Dictionary, extra: Dictionary) -> Dictionary:
	var d := f.duplicate()
	d.merge(extra, true)
	return d


## Tier 1 (two forts and the first dungeon) and two tier 2 forts, all uncleared, in world order.
func _chain() -> Array:
	return [{"id": "t1a", "tier": 1, "first_clear": true, "yield_mult": 1.0, "clears_since_retaken": 0},
		{"id": "t1b", "tier": 1, "first_clear": true, "yield_mult": 1.0, "clears_since_retaken": 0},
		{"id": "sluice", "tier": 1, "first_clear": true, "first_dungeon": true, "yield_mult": 1.0, "clears_since_retaken": 0},
		{"id": "t2a", "tier": 2, "first_clear": true, "yield_mult": 1.0, "clears_since_retaken": 0},
		{"id": "t3a", "tier": 3, "first_clear": true, "yield_mult": 1.0, "clears_since_retaken": 0}]


## Relish's token over a chip: it drops below the token, or steps aside where that lands nearer another fort.
func _clear_of_token(t: TestUtil) -> void:
	t.suite("map_next-token")
	var z := 0.7
	var p := Vector2(500, 500)
	var r := MapLogic.fort_radius(1)
	var base := IdleLogic.chip_rect(p, r, z, false, 180.0)
	var tr := float(NodeLogic.relish_radii(z)["halo"]) + 6.0 / z
	var none: Array = []
	t.ok(IdleLogic.chip_place(p, r, z, false, 180.0, p + Vector2(0, -300), tr, none) == base, "a token far from the chip leaves it where it is")
	var tok := base.get_center()
	var moved := IdleLogic.chip_place(p, r, z, false, 180.0, tok, tr, none)
	var pad := float(IdleLogic.cfg()["chip_token_pad_px"]) / z
	var trect := Rect2(tok - Vector2(tr + pad, tr + pad), Vector2(tr + pad, tr + pad) * 2.0)
	t.ok(not moved.intersects(trect), "a token on the chip: the chip is clear of it")
	t.ok(moved.position.y >= tok.y + tr and is_equal_approx(moved.position.x, base.position.x) and moved.size == base.size, "it drops past the token, same x and size")
	# a neighbour just below the chip: the drop would land nearer it, so the chip steps aside on its own row
	var near := [Vector2(p.x, p.y + 280.0)]
	var side := IdleLogic.chip_place(p, r, z, false, 180.0, tok, tr, near)
	t.ok(not side.intersects(trect) and is_equal_approx(side.position.y, base.position.y), "nearer another fort below: it steps aside instead, same row")
	t.ok(IdleLogic.chip_place(p, r, z, false, 180.0, tok + Vector2(-20, 0), tr, near).position.x > tok.x - 20.0, "a token left of centre: the chip steps to its right")
	t.ok(IdleLogic.chip_place(p, r, z, false, 180.0, tok + Vector2(20, 0), tr, near).end.x < tok.x + 20.0, "a token right of centre: the chip steps to its left")
	# the real day-1 map: every fort's moved chip, with the token on it, is clear and nearer its own fort
	var s := GameState.new(TestUtil.configs())
	s.debug_enabled = true
	s.cmd_debug_load_fixture("day1")
	var m := MapModel.new(s)
	m.refresh(true)
	var bad: Array = []
	for f in m.forts:
		var fp := MapModel.to_vec(f["pos"])
		var fr := MapLogic.fort_radius(int(f["tier"]))
		var oth: Array = []
		for g in m.forts:
			if g["id"] != f["id"]:
				oth.append(MapModel.to_vec(g["pos"]))
		var b := IdleLogic.chip_rect(fp, fr, z, false, 180.0)
		var q := IdleLogic.chip_place(fp, fr, z, false, 180.0, fp + Vector2(0.0, fr + 40.0), tr, oth)
		var own := q.get_center().distance_to(fp)
		for o in oth:
			if q.get_center().distance_to(o) <= own:
				bad.append(str(f["id"]))
				break
	t.ok(bad.is_empty(), "no fort's displaced chip is nearer another fort %s" % str(bad))
	# the callouts keep clear of the chip where it is DRAWN: the shifted rect, not the unshifted one
	var shifted_rect := Rect2(base.position + (moved.position - base.position), base.size)
	t.ok(shifted_rect == moved and shifted_rect != base, "a shifted chip's drawn rect is not its unshifted place")
	var co := FileAccess.get_file_as_string("res://scripts/map/map_callouts.gd")
	var occ := co.substr(co.find("func _chip_rects("), 700)
	t.ok(occ.contains("nodes.chip_world_rect(") and not occ.contains("IdleLogic.chip_rect("), "the callouts' occupied rects are the drawn chips'")
	var fi := FileAccess.get_file_as_string("res://scripts/map/map_fort_idle.gd")
	var cw := fi.substr(fi.find("func chip_world_rect("), 500)
	t.ok(cw.contains("_chip_shift(f, c)") and fi.substr(fi.find("func _chip(")).contains("+ _chip_shift(f, c)"),
		"the occupied rect and the drawn chip add the same _chip_shift (IdleLogic.chip_place)")


# --- raid-worthiness --------------------------------------------------------------------------

## The raid set's config with no cap, so the qualification tests see every fort that qualifies.
func _uncapped() -> Dictionary:
	var c := NextLogic.cfg().duplicate()
	c["raid_tag_max"] = 99
	return c


## The ids of NextLogic.raid_set in rank order (no positions, so ties fall to world order).
func _raid_ids(forts: Array, prev: Array = [], positions := {}, from := Vector2.ZERO, c := {}) -> Array:
	if c.is_empty():
		c = _uncapped()
	return NextLogic.raid_set(forts, prev, from, positions, c).map(func(r): return str(r["fort"]["id"]))


## Why `f` is in the (uncapped) raid set of `forts`, or "".
func _raid_why(f: Dictionary, forts: Array, prev: Array = []) -> String:
	for r in NextLogic.raid_set(forts, prev, Vector2.ZERO, {}, _uncapped()):
		if str(r["fort"]["id"]) == str(f["id"]):
			return str(r["why"])
	return ""


func _raid(t: TestUtil) -> void:
	t.suite("map_next-raid")
	var y := float(NextLogic.cfg()["raid_ready_yield"])
	t.ok(y > 0.0 and y <= 1.0, "raid_ready_yield is a yield fraction")
	var cleared := {"id": "x", "first_clear": false, "clears_since_retaken": 2, "tier": 2}
	var back := _with(cleared, {"yield_mult": y})
	t.ok(_raid_why(back, [back]) == "refilled", "a cleared fort back to raid_ready_yield is refilled")
	var decayed := _with(cleared, {"yield_mult": y - 0.01})
	t.ok(_raid_why(decayed, [decayed]) == "", "decayed under it: not ready")
	var unspent := _with(cleared, {"yield_mult": 1.0, "clears_since_retaken": 0})
	t.ok(_raid_why(unspent, [unspent]) == "", "no clear since the retake: nothing to refill")
	var fresh := {"id": "x", "first_clear": true, "tier": 1, "yield_mult": 1.0}
	t.ok(_raid_why(fresh, [fresh]) == "first_clear", "a frontier first clear is ready")
	# the frontier: the lowest tier that still has a first clear
	var chain := _chain()
	t.ok(NextLogic.frontier_tier(chain) == 1, "tier 1 first")
	var ready := func(forts: Array) -> Array: return forts.filter(func(f): return _raid_why(f, forts) != "").map(func(f): return f["id"])
	t.ok(ready.call(chain) == ["t1a", "t1b", "sluice"], "day-1 shape: only tier 1 and the first dungeon (%s)" % str(ready.call(chain)))
	t.ok(_raid_why(chain[3], chain) == "", "a tier 2 first clear waits")
	for f in chain:
		if int(f["tier"]) == 1:
			f["first_clear"] = false
			f["clears_since_retaken"] = 1
			f["yield_mult"] = 0.3
	t.ok(NextLogic.frontier_tier(chain) == 2, "all of tier 1 cleared: the frontier is tier 2")
	t.ok(ready.call(chain) == ["t2a"], "tier 2 is marked and decayed tier 1 forts are not (%s)" % str(ready.call(chain)))
	chain[0]["yield_mult"] = 1.0
	t.ok(ready.call(chain) == ["t1a", "t2a"] and _raid_why(chain[0], chain) == "refilled", "a recovered yield marks a cleared fort refilled")
	chain[0]["held"] = true
	chain[1]["held"] = true
	chain[1]["margin"] = "will_fall"
	chain[1]["yield_mult"] = 1.0
	t.ok(ready.call(chain) == ["t1a", "t1b", "t2a"], "held and overrun forts follow the same rule (%s)" % str(ready.call(chain)))
	var forts := [{"id": "a", "name": "A", "tier": 1, "first_clear": true}, {"id": "b", "name": "B", "tier": 2, "first_clear": true, "first_dungeon": true},
		{"id": "c", "name": "C", "first_clear": false, "clears_since_retaken": 1, "yield_mult": 1.0}, {"id": "d", "name": "D", "first_clear": false, "clears_since_retaken": 1, "yield_mult": 0.2}]
	var order: Array = _raid_ids(forts)
	t.ok(order == ["c", "b", "a"], "refilled first, then the first dungeon, then the frontier (%s)" % str(order))
	t.ok(NextLogic.ready_line(forts[2], "refilled") == {"text": "C refilled: raid it", "kind": "raid", "target": "c"}, "a refilled ready line, in view_away's shape")
	t.ok(NextLogic.ready_line(forts[1], "first_clear")["text"] == "B: first clear holds a blueprint", "a first-clear ready line")
	var s := GameState.new(TestUtil.configs())
	s.debug_enabled = true
	s.cmd_debug_load_fixture("day1")
	var m := MapModel.new(s)
	m.refresh(true)
	var cap := int(NextLogic.cfg()["raid_tag_max"])
	var marked: Array = m.forts.filter(func(f): return m.raid_why(str(f["id"])) != "")
	var uncleared: Array = m.forts.filter(func(f): return bool(f["first_clear"]))
	var frontier := NextLogic.frontier_tier(m.forts)
	var qual := _raid_ids(m.forts)
	t.ok(not marked.is_empty() and marked.size() < m.forts.size(), "day1: not every fort is marked (%d of %d)" % [marked.size(), m.forts.size()])
	t.ok(marked.all(func(f): return int(f["tier"]) == frontier or bool(f.get("first_dungeon", false))), "day1: only the frontier tier and the first dungeon")
	t.ok(uncleared.filter(func(f): return int(f["tier"]) == frontier).all(func(f): return qual.has(str(f["id"]))), "day1: every frontier-tier first clear qualifies")
	t.ok(marked.size() == mini(qual.size(), cap) and marked.all(func(f): return qual.has(str(f["id"]))),
		"day1: the marked forts are the first raid_tag_max of those (%d of %d)" % [marked.size(), qual.size()])
	var n := NodeLogic.ncfg()
	t.ok(str(n["raid_word"]) != "" and float(n["raid_pip_px"]) >= 6.0, "the marker carries a word and a shape")
	var sig0 := NodeLogic.fort_static_sig({"tier": 1, "cap": 80.0}, {}, "", "")
	var sig1 := NodeLogic.fort_static_sig({"tier": 1, "cap": 80.0}, {}, "", "refilled")
	t.ok(sig0 != sig1, "becoming raid-ready redraws the fort's ring")
	var held_sig := func(tier: String) -> Array: return NodeLogic.fort_static_sig({"tier": 1, "cap": 80.0}, {}, IdleLogic.SAFE, "", tier)
	t.ok(held_sig.call("mid") != held_sig.call("near") and held_sig.call("mid") == held_sig.call("far"), "a held fort's ring signature changes between overview and near")
	var ring := FileAccess.get_file_as_string("res://scripts/map/map_fort_ring.gd")
	t.ok(ring.contains("ctx.model.raid_why(") and ring.contains("raid_word"), "the ring layer draws the marker and its word from the model's raid set")


## NextLogic.raid_set: one ranked, capped set with memory (task D1).
func _raid_set(t: TestUtil) -> void:
	t.suite("map_next-raidset")
	var c := NextLogic.cfg()
	var cap := int(c["raid_tag_max"])
	var enter := float(c["raid_ready_yield"])
	var leave := float(c["raid_ready_yield_exit"])
	t.ok(cap >= 1 and leave < enter, "raid_tag_max is a count and the exit yield is under the entry one")
	var refill := func(id: String, y: float) -> Dictionary: return {"id": id, "name": id, "tier": 1, "first_clear": false, "clears_since_retaken": 1, "yield_mult": y}
	# the cap
	var many: Array = []
	for i in cap + 3:
		many.append(refill.call("r%d" % i, 1.0))
	var capped := NextLogic.raid_set(many, [], Vector2.ZERO, {})
	t.ok(capped.size() == cap, "the cap holds (%d of %d)" % [capped.size(), many.size()])
	t.ok(capped.all(func(r): return r.has("fort") and r["why"] == "refilled"), "entries are {fort, why}")
	t.ok(NextLogic.raid_set([], [], Vector2.ZERO, {}).is_empty(), "no forts: an empty set")
	# class: refilled, then the first-dungeon first clear, then a frontier first clear
	var fd := {"id": "fd", "tier": 2, "first_clear": true, "first_dungeon": true}
	var fr := {"id": "fr", "tier": 1, "first_clear": true}
	var rf: Dictionary = refill.call("rf", 1.0)
	t.ok(_raid_ids([fr, fd, rf], [], {}, Vector2.ZERO, c) == ["rf", "fd", "fr"], "class order: refilled, first dungeon, frontier (%s)" % str(_raid_ids([fr, fd, rf], [], {}, Vector2.ZERO, c)))
	# within refilled: yield descending, before memory and distance
	var lo: Dictionary = refill.call("lo", enter + 0.01)
	var hi: Dictionary = refill.call("hi", 1.0)
	var pos := {"lo": Vector2(10, 0), "hi": Vector2(500, 0)}
	t.ok(_raid_ids([lo, hi], ["lo"], pos, Vector2.ZERO, c) == ["hi", "lo"], "within refilled the higher yield ranks first, even against a kept, nearer fort")
	# memory: a kept fort beats an equal-class newcomer, even a nearer one
	var near := {"id": "near", "tier": 1, "first_clear": true}
	var far := {"id": "far", "tier": 1, "first_clear": true}
	var at := {"near": Vector2(10, 0), "far": Vector2(100, 0)}
	t.ok(_raid_ids([near, far], [], at, Vector2.ZERO, c) == ["near", "far"], "distance: the nearer fort first")
	t.ok(_raid_ids([far, near], [], at, Vector2.ZERO, c) == ["near", "far"], "distance beats world order")
	t.ok(_raid_ids([near, far], ["far"], at, Vector2.ZERO, c) == ["far", "near"], "a kept fort beats an equal-class newcomer, even a nearer one")
	t.ok(_raid_ids([near, far], [], at, Vector2(120, 0), c) == ["far", "near"], "distance is from from_pos (Relish's node)")
	var a: Dictionary = refill.call("a", 1.0)
	var b: Dictionary = refill.call("b", 1.0)
	t.ok(_raid_ids([a, b], ["b"], {}, Vector2.ZERO, c) == ["b", "a"], "equal yields: the kept refilled fort first")
	t.ok(_raid_ids([a, b], [], {}, Vector2.ZERO, c) == ["a", "b"] and _raid_ids([b, a], [], {}, Vector2.ZERO, c) == ["b", "a"], "then world order")
	t.ok(_raid_ids([near, far], [], {"near": Vector2(10, 0)}, Vector2.ZERO, c) == ["near", "far"], "a fort without a position falls back to world order, not ahead")
	# the cap keeps the best ranks: a refilled newcomer bumps the last first clear
	var firsts: Array = []
	for i in cap:
		firsts.append({"id": "f%d" % i, "tier": 1, "first_clear": true})
	var ids_before := _raid_ids(firsts, [], {}, Vector2.ZERO, c)
	var with_refill := firsts.duplicate()
	with_refill.append(rf)
	var ids_after := _raid_ids(with_refill, ids_before, {}, Vector2.ZERO, c)
	t.ok(ids_after.size() == cap and ids_after[0] == "rf" and not ids_after.has(ids_before[cap - 1]), "past the cap the lowest rank drops (%s)" % str(ids_after))
	# hysteresis on the refill
	var mid := (enter + leave) * 0.5
	var kept: Dictionary = refill.call("k", mid)
	t.ok(_raid_ids([kept], ["k"], {}, Vector2.ZERO, c) == ["k"], "a kept refilled fort at %.2f stays" % mid)
	t.ok(_raid_ids([kept], [], {}, Vector2.ZERO, c).is_empty(), "a newcomer at %.2f does not enter" % mid)
	t.ok(_raid_ids([refill.call("k", leave - 0.01)], ["k"], {}, Vector2.ZERO, c).is_empty(), "under raid_ready_yield_exit the kept fort leaves")
	t.ok(_raid_ids([refill.call("k", 0.9)], ["k"], {}, Vector2.ZERO, c) == ["k"] and _raid_ids([refill.call("k", 0.9)], [], {}, Vector2.ZERO, c).is_empty(),
		"the task's numbers: kept at 0.9 stays, a newcomer at 0.9 does not enter")


## The model computes the set once per refresh and every consumer reads it (task D1).
func _raid_model(t: TestUtil) -> void:
	t.suite("map_next-raidmodel")
	var cap := int(NextLogic.cfg()["raid_tag_max"])
	var s := GameState.new(TestUtil.configs())
	s.debug_enabled = true
	s.cmd_debug_load_fixture("midgame_2flips")
	var m := MapModel.new(s)
	m.nodes_demo = true
	m.refresh(true)
	var tagged: Array = m.forts.filter(func(f): return m.raid_why(str(f["id"])) != "").map(func(f): return str(f["id"]))
	var set_ids: Array = m.raids.map(func(r): return str(r["fort"]["id"]))
	t.ok(not tagged.is_empty() and tagged.size() <= cap, "--nodes=demo on midgame_2flips tags at most raid_tag_max forts (%d: %s)" % [tagged.size(), str(tagged)])
	var sorted_tags := tagged.duplicate()
	sorted_tags.sort()
	var sorted_set := set_ids.duplicate()
	sorted_set.sort()
	t.ok(sorted_tags == sorted_set, "the ring's tag set is the model's set (%s vs %s)" % [str(tagged), str(set_ids)])
	t.ok(m.raid_why("no-such-fort") == "" and m.raids.all(func(r): return m.raid_why(str(r["fort"]["id"])) == str(r["why"])), "raid_why gives each member's why and \"\" otherwise")
	# the strip's candidates are that same set: the HUD's inp carries model.raids
	var inp := {"forts": m.forts, "clocks": m.clocks, "queue": m.town_queue, "vei": m.vei, "readout": m.readout(),
		"won": bool(m.hud.get("won", false)), "opening": {}, "raids": m.raids}
	var pick := NextLogic.choose(inp)
	var whys := {}
	for r in m.raids:
		whys[str(r["fort"]["id"])] = str(r["why"])
	var first_of_kind := ""
	for r in m.raids:
		if pick["rule"] == "raid" and str(r["why"]) == str(whys.get(pick["target"], "")):
			first_of_kind = str(r["fort"]["id"])
			break
	t.ok(pick["rule"] != "raid" or (whys.has(pick["target"]) and pick["target"] == first_of_kind),
		"a strip raid is the set's first entry of its kind (%s: %s)" % [pick["rule"], pick["text"]])
	# from_pos: her travel target while travelling (she is heading there), else where she stands, else Covington
	var dest := str(m.relish.get("target", ""))
	t.ok(str(m.relish.get("state", "")) == "travelling" and dest != "" and m._raid_from() == m.node_pos(dest),
		"the demo's travelling Relish measures from her target (%s)" % dest)
	var saved := m.relish
	m.relish = {"state": "at_fort", "at": "ashgate", "target": ""}
	t.ok(m._raid_from() == m.node_pos("ashgate"), "standing at a fort: from that fort")
	m.relish = {"state": "travelling", "at": "covington", "target": "greywall"}
	t.ok(m._raid_from() == m.node_pos("greywall"), "travelling: from her target, not the node she left")
	m.relish = {"state": "travelling", "at": "ashgate", "target": "no-such-node"}
	t.ok(m._raid_from() == m.node_pos("ashgate"), "an unknown target: from where she last stood")
	m.relish = {"state": "home", "at": "", "target": "greywall"}
	t.ok(m._raid_from() == m.node_pos("covington"), "not travelling and nowhere known: Covington (a stale target is ignored)")
	m.relish = saved
	var hud_src := FileAccess.get_file_as_string("res://scripts/map/map_hud.gd")
	var rn := hud_src.substr(hud_src.find("func _refresh_next("), 600)
	t.ok(rn.contains("\"raids\": model.raids"), "the HUD hands the strip the model's set")
	var ring := FileAccess.get_file_as_string("res://scripts/map/map_fort_ring.gd")
	t.ok(ring.count("ctx.model.raid_why(") >= 2, "the ring's pip, tag and static signature read the model's set")
	var callers: Array = []
	for fn in DirAccess.get_files_at("res://scripts/map"):
		if not fn.ends_with(".gd"):
			continue
		var src := FileAccess.get_file_as_string("res://scripts/map/" + fn)
		if src.contains("NextLogic.raid_ready") or src.contains("NextLogic.ready_forts") or (fn != "map_model.gd" and src.contains("NextLogic.raid_set(")):
			callers.append(fn)
	t.ok(callers.is_empty(), "nothing but the model computes the set, and no per-fort raid_ready callers are left (%s)" % str(callers))
	var model_src := FileAccess.get_file_as_string("res://scripts/map/map_model.gd")
	var at_refresh := model_src.find("func refresh(")
	var body := model_src.substr(at_refresh, model_src.find("\treturn true\n", at_refresh) - at_refresh)
	t.ok(model_src.count("NextLogic.raid_set(") == 1 and body.contains("\t_refresh_raids()\n") and model_src.count("_refresh_raids()") == 2,
		"computed once, inside refresh (once per rev), and nowhere else")
	# memory: a refresh at the same state keeps the same set
	m.refresh(true)
	t.ok(m.raids.map(func(r): return str(r["fort"]["id"])) == set_ids, "a second refresh keeps the set and its order")
	# the same late state twice gives the same strip line (md-late-a/b)
	var lines: Array = []
	for i in 2:
		var s2 := GameState.new(TestUtil.configs())
		s2.debug_enabled = true
		s2.cmd_debug_load_fixture("pre_vei")
		var m2 := MapModel.new(s2)
		m2.refresh(true)
		var inp2 := {"forts": m2.forts, "clocks": m2.clocks, "queue": m2.town_queue, "vei": m2.vei, "readout": m2.readout(),
			"won": bool(m2.hud.get("won", false)), "opening": {}, "raids": m2.raids}
		var p1 := NextLogic.choose(inp2)
		var p2 := NextLogic.choose(inp2, p1)
		lines.append(str(p2["text"]))
		if i == 0:
			t.ok(p1["rule"] == "vei" and p2["rule"] == "vei" and str(p2["text"]).begins_with("Vei can be faced: your odds"),
				"pre_vei, at Vei's gates: the Vei line, not a first-clear ask (%s)" % p2["text"])
	t.ok(lines[0] == lines[1], "pre_vei twice: the same strip line (%s)" % lines[0])


# --- the next action ----------------------------------------------------------------------

## The strip's input; `raids` is the set the model would hand it (NextLogic.raid_set of the forts,
## no memory, no positions) unless the test gives one.
func _inp(extra := {}) -> Dictionary:
	var d := {"forts": [], "clocks": {}, "queue": null, "vei": {}, "readout": {"odds": 0.1}, "won": false, "opening": {}}
	d.merge(extra, true)
	if not extra.has("raids"):
		d["raids"] = NextLogic.raid_set(d["forts"], [], Vector2.ZERO, {})
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
	var ash := {"id": "ashgate", "name": "Ashgate", "first_clear": false, "clears_since_retaken": 1, "yield_mult": 1.0}
	var r2 := NextLogic.choose(_inp({"forts": [ash]}))
	t.ok(r2["rule"] == "raid" and r2["text"] == "Ashgate refilled: raid it" and r2["action"] == {"kind": "fort", "id": "ashgate"}, "a refilled raid")
	var sluice := {"id": "old-sluice", "name": "Old Sluice", "first_clear": true, "first_dungeon": true}
	t.ok(NextLogic.choose(_inp({"forts": [sluice]}))["text"] == "Old Sluice: first clear holds a blueprint", "a first clear")
	var two := [{"id": "a", "name": "A", "first_clear": false, "clears_since_retaken": 1, "yield_mult": 1.0}, {"id": "b", "name": "B", "first_clear": false, "clears_since_retaken": 1, "yield_mult": 1.0}]
	t.ok(NextLogic.choose(_inp({"forts": two}), {"rule": "raid", "target": "b"})["target"] == "b", "a kept raid target holds while it is still in the set")
	var only_a := NextLogic.raid_set([two[0]], [], Vector2.ZERO, {})
	t.ok(NextLogic.choose(_inp({"forts": two, "raids": only_a}), {"rule": "raid", "target": "b"})["target"] == "a", "out of the set, the kept target gives way to the set's first")
	# the strip takes the set it is given: it does not recompute it from the forts
	t.ok(NextLogic.choose(_inp({"forts": [ash], "raids": []}))["rule"] != "raid", "an empty set: no raid line, whatever the forts say")
	var given := NextLogic.raid_set([sluice], [], Vector2.ZERO, {})
	t.ok(NextLogic.choose(_inp({"forts": [ash, sluice], "raids": given}))["target"] == "old-sluice", "the set's first entry, not a recomputed one")
	# 3. Vei in reach: can_begin, or odds at next_vei_odds
	var v4 := NextLogic.choose(_inp({"vei": {"can_begin": true}, "readout": {"odds": 0.61}}))
	t.ok(v4["rule"] == "vei" and v4["text"] == "Vei can be faced: your odds 61%", "can_begin: Vei (%s)" % v4["text"])
	t.ok(NextLogic.choose(_inp({"readout": {"odds": float(c["next_vei_odds"])}}))["rule"] == "vei", "odds at next_vei_odds: Vei")
	t.ok(NextLogic.choose(_inp({"readout": {"odds": float(c["next_vei_odds"]) - 0.01}}))["rule"] == "default", "under it, no")
	# 4. the plan: the empty queue, else the standing objective
	t.ok(NextLogic.choose(_inp({"queue": []}))["rule"] == "queue", "an empty queue")
	t.ok(NextLogic.choose(_inp({"queue": [{"building_id": "pit"}]}))["rule"] != "queue", "a queued build: not this rule")
	t.ok(NextLogic.choose(_inp({"queue": null}))["rule"] != "queue", "no queue in the view: skipped")
	t.ok(NextLogic.choose(_inp({"queue": []}))["text"] == str(c["queue_text"]), "queue line")
	# the opening's override
	var op := NextLogic.choose(_inp({"forts": [vespers], "clocks": {"vespers": {"fall_s": 60.0}}, "opening": {"text": "Drag the triangle", "target": "vespers"}}))
	t.ok(op["rule"] == "opening" and op["text"] == "Drag the triangle" and op["action"] == {"kind": "fort", "id": "vespers"}, "set_opening_ask beats every rule and keeps its target")
	t.ok(NextLogic.choose(_inp({"forts": [vespers], "clocks": {"vespers": {"fall_s": 60.0}}, "opening": {"text": "", "target": "vespers"}}))["rule"] == "fall", "an empty ask clears the override")
	var hud_src := FileAccess.get_file_as_string("res://scripts/map/map_hud.gd")
	t.ok(hud_src.contains("func set_opening_ask(text: String, target: String)"), "the HUD has the opening hook")


## The strict order, opening > won > fall > ready raid > Vei in reach > plan, and its hysteresis (task D1).
func _order(t: TestUtil) -> void:
	t.suite("map_next-order")
	var c := NextLogic.cfg()
	var warn := float(c["next_fall_warn_s"])
	var vespers := _held("vespers", 1.0, 30.0, {"name": "Vespers"})
	var chime := _held("chime-fort", 1.0, 30.0, {"name": "Chime Fort"})
	var ash := {"id": "ashgate", "name": "Ashgate", "first_clear": false, "clears_since_retaken": 1, "yield_mult": 1.0}
	var sluice := {"id": "old-sluice", "name": "Old Sluice", "first_clear": true, "first_dungeon": true}
	var can := {"can_begin": true}
	var pair := [vespers, chime]
	# each step down
	t.ok(NextLogic.choose(_inp({"forts": [vespers, ash], "clocks": {"vespers": {"fall_s": 600.0}}, "vei": can, "queue": []}))["rule"] == "fall", "fall beats a refilled raid")
	var refilled_vs_vei := NextLogic.choose(_inp({"forts": [ash, sluice], "vei": can, "readout": {"odds": 0.7}}))
	t.ok(refilled_vs_vei["rule"] == "raid" and refilled_vs_vei["target"] == "ashgate", "a refilled raid beats Vei can_begin")
	# the blueprint ask (any first clear, the first dungeon's too) sits under Vei: at her gates the strip says Vei
	t.ok(NextLogic.choose(_inp({"forts": [sluice], "vei": can, "readout": {"odds": 0.7}}))["rule"] == "vei", "Vei can_begin beats a first-clear ask")
	t.ok(NextLogic.choose(_inp({"forts": [sluice], "readout": {"odds": 0.7}}))["rule"] == "vei", "Vei's odds alone beat a first-clear ask too")
	t.ok(NextLogic.choose(_inp({"forts": [sluice], "queue": []}))["rule"] == "raid", "a first-clear ask beats the plan")
	t.ok(NextLogic.choose(_inp({"queue": [], "vei": can}))["rule"] == "vei", "Vei in reach (can_begin) beats the plan's empty queue")
	t.ok(NextLogic.choose(_inp({"queue": [], "readout": {"odds": 0.7}}))["rule"] == "vei", "Vei in reach (odds alone) beats the plan too")
	t.ok(NextLogic.choose(_inp({"forts": [vespers, sluice], "clocks": {"vespers": {"fall_s": 600.0}}, "vei": can}))["rule"] == "fall", "a falling fort beats Vei")
	# the strip takes each raid rule's first entry of its kind from the one set, kept while still of that kind
	var both := NextLogic.raid_set([sluice, ash], [], Vector2.ZERO, {})
	t.ok(both.size() == 2 and NextLogic.choose(_inp({"forts": [sluice, ash], "raids": both}), {"rule": "raid", "target": "old-sluice"})["target"] == "ashgate",
		"a kept first-clear target does not hold the refilled rule")
	var fc := [{"id": "x", "name": "X", "tier": 1, "first_clear": true}, {"id": "y", "name": "Y", "tier": 1, "first_clear": true}]
	t.ok(NextLogic.choose(_inp({"forts": fc}), {"rule": "raid", "target": "y"})["target"] == "y", "the blueprint ask keeps its previous target while it is still a first clear")
	t.ok(NextLogic.choose(_inp({"forts": fc}))["target"] == "x", "else the set's first first clear")
	# the whole ladder, one rule removed at a time
	var all := _inp({"forts": [vespers, ash, sluice], "clocks": {"vespers": {"fall_s": 600.0}}, "queue": [], "vei": can, "readout": {"odds": 0.7}})
	t.ok(NextLogic.choose(all)["rule"] == "fall", "fall first")
	all["clocks"] = {}
	t.ok(NextLogic.choose(all)["rule"] == "raid" and NextLogic.choose(all)["target"] == "ashgate", "then the refilled raid")
	all["forts"] = [sluice]
	all["raids"] = NextLogic.raid_set([sluice], [], Vector2.ZERO, {})
	t.ok(NextLogic.choose(all)["rule"] == "vei", "then Vei in reach, over the first-clear ask")
	all["vei"] = {"can_begin": false}
	t.ok(NextLogic.choose(all)["rule"] == "vei", "odds alone still in reach")
	all["readout"] = {"odds": 0.1}
	t.ok(NextLogic.choose(all)["rule"] == "raid" and NextLogic.choose(all)["target"] == "old-sluice", "then the first-clear ask (the blueprint)")
	all["forts"] = []
	all["raids"] = []
	t.ok(NextLogic.choose(all)["rule"] == "queue", "then the plan: the empty queue")
	all["queue"] = null
	t.ok(NextLogic.choose(all)["rule"] == "default", "then the standing objective")
	# Vei's hysteresis: enter at next_vei_odds, stay to next_vei_odds_exit
	var enter := float(c["next_vei_odds"])
	var leave := float(c["next_vei_odds_exit"])
	t.ok(leave < 0.58 and 0.58 < enter and leave > 0.54, "the task's numbers sit either side of the band (%.2f..%.2f)" % [leave, enter])
	var was_vei := {"rule": "vei", "target": "vei"}
	var was_raid := {"rule": "raid", "target": "ashgate"}
	t.ok(NextLogic.choose(_inp({"readout": {"odds": 0.58}}), was_vei)["rule"] == "vei", "odds 0.58 after a VEI pick: stays VEI")
	t.ok(NextLogic.choose(_inp({"readout": {"odds": 0.58}}), was_raid)["rule"] != "vei", "the same odds after a RAID pick: does not enter")
	t.ok(NextLogic.choose(_inp({"readout": {"odds": 0.58}}))["rule"] != "vei", "nor with no previous pick")
	t.ok(NextLogic.choose(_inp({"readout": {"odds": 0.54}}), was_vei)["rule"] != "vei", "0.54: leaves")
	t.ok(NextLogic.choose(_inp({"vei": can, "readout": {"odds": 0.3}}), was_vei)["rule"] == "vei", "while can_begin holds it stays at any odds")
	# against the blueprint ask: the band decides which of the two the strip keeps
	var ask := {"rule": "raid", "target": "old-sluice"}
	var at58 := _inp({"forts": [sluice], "readout": {"odds": 0.58}})
	t.ok(NextLogic.choose(at58, ask)["rule"] == "raid", "0.58 after a first-clear RAID pick: Vei does not enter, the ask stays")
	t.ok(NextLogic.choose(at58, was_vei)["rule"] == "vei", "0.58 after a VEI pick: Vei stays over the ask")
	t.ok(NextLogic.choose(_inp({"forts": [sluice], "readout": {"odds": 0.54}}), was_vei)["target"] == "old-sluice", "0.54: Vei leaves and the ask returns")
	t.ok(NextLogic.choose(_inp({"forts": [ash], "readout": {"odds": 0.58}}), was_vei)["rule"] == "raid", "a refilled raid still beats a kept Vei")
	# fall's hysteresis: enter under next_fall_warn_s, a kept fort stays to warn x next_fall_exit_mult
	var mult := float(c["next_fall_exit_mult"])
	t.ok(mult > 1.0, "next_fall_exit_mult widens the band")
	var band := warn * (1.0 + mult) * 0.5
	var in_band := {"vespers": {"fall_s": band}}
	var was_fall := {"rule": "fall", "target": "vespers"}
	t.ok(NextLogic.choose(_inp({"forts": pair, "clocks": in_band}))["rule"] != "fall", "over next_fall_warn_s a fort does not enter")
	var kept := NextLogic.choose(_inp({"forts": pair, "clocks": in_band}), was_fall)
	t.ok(kept["rule"] == "fall" and kept["target"] == "vespers", "a kept fall target stays under warn x next_fall_exit_mult")
	t.ok(NextLogic.choose(_inp({"forts": pair, "clocks": {"vespers": {"fall_s": warn * mult}}}), was_fall)["rule"] != "fall", "at warn x next_fall_exit_mult it leaves")
	t.ok(NextLogic.choose(_inp({"forts": pair, "clocks": in_band}), {"rule": "fall", "target": "chime-fort"})["rule"] != "fall", "only the kept fort gets the band")
	t.ok(NextLogic.choose(_inp({"forts": pair, "clocks": in_band}), {"rule": "raid", "target": "vespers"})["rule"] != "fall", "only after a FALL pick")
	var rival := {"vespers": {"fall_s": band}, "chime-fort": {"fall_s": warn - 1.0}}
	t.ok(NextLogic.choose(_inp({"forts": pair, "clocks": rival}), was_fall)["target"] == "vespers", "switch_ratio still keeps the kept fort against a rival just under warn")
	var sooner := {"vespers": {"fall_s": band}, "chime-fort": {"fall_s": band * float(c["switch_ratio"]) - 1.0}}
	t.ok(NextLogic.choose(_inp({"forts": pair, "clocks": sooner}), was_fall)["target"] == "chime-fort", "and a much sooner fort still takes over")
	# determinism: the same inputs twice give the same line, and a pick is its own next pick
	var late := _inp({"forts": [ash, sluice, vespers], "clocks": {}, "queue": [], "vei": can, "readout": {"odds": 0.61}})
	var p1 := NextLogic.choose(late)
	t.ok(p1 == NextLogic.choose(late.duplicate(true)), "the same inputs give the same line (%s)" % p1["text"])
	t.ok(NextLogic.choose(late, p1) == p1, "and fed back as prev, the same line again")



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
	t.ok(not NodeLogic.yours(NodeLogic.OVERRUN), "overrun is not yours: it was never taken")
	for st in [NodeLogic.HERS, NodeLogic.CONTESTED, NodeLogic.EMPTIED, NodeLogic.OVERRUN]:
		t.ok(NodeLogic.ring_weight(st) == 1.0 and not NodeLogic.has_core(st), "%s keeps the thin ring and no core" % st)
	var ring := FileAccess.get_file_as_string("res://scripts/map/map_fort_ring.gd")
	var over_mult := float(NodeLogic.ncfg()["held_overview_mult"])
	t.ok(over_mult >= 2.0 and NodeLogic.ncfg()["overview_tiers"] == ["far", "mid"], "the overview multiplier is at least 2x, on far and mid")
	for st in [IdleLogic.SAFE, IdleLogic.THIN, IdleLogic.WILL_FALL]:
		for tier in ["far", "mid"]:
			t.ok(is_equal_approx(NodeLogic.ring_weight(st, tier), NodeLogic.ring_weight(st) * over_mult), "held (%s) ring is %.1fx heavier again at the %s tier" % [st, over_mult, tier])
		t.ok(NodeLogic.ring_weight(st, "near") == NodeLogic.ring_weight(st), "held (%s) ring is unchanged at near" % st)
	for st in [NodeLogic.HERS, NodeLogic.CONTESTED, NodeLogic.EMPTIED, NodeLogic.OVERRUN]:
		t.ok(NodeLogic.ring_weight(st, "far") == 1.0 and NodeLogic.ring_weight(st, "mid") == 1.0, "%s ring stays a hairline in the overview tiers" % st)
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
	for fx in [["pre_vei", 33.0, "; its vats are unstaffed, so their tend slots are closed"], ["midgame_2flips", 19.0, ""]]:
		var s := GameState.new(cfgs)
		s.debug_enabled = true
		s.cmd_debug_load_fixture(fx[0])
		var m := MapModel.new(s)
		m.refresh(true)
		var kept := ValveLogic.workers_kept(float(m.hud["workers_steady"]), m.hud, m.job_slots, cap)
		t.near(kept, float(fx[1]), 1e-6, "%s: workers → %d, the town's real total (steady reads %d%s)" % [fx[0], roundi(kept), roundi(float(m.hud["workers_steady"])), fx[2]])


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
	var loot := TestUtil.load_json("res://configs/loot.json")
	t.ok(CardLogic.loot_card_line({"yield_mult": 1.0}, loot) == RaidLoot.card_line({"yield_mult": 1.0}, loot), "the loot line is the dungeon's")
	t.ok(CardLogic.first_clear_line({"first_clear": true}) == "first clear: guaranteed blueprint", "the first clear's reward")
	var pin := CardLogic.pinned_odds({"odds": 0.61, "sign": 1, "drain_s": -1.0, "backlog": 18000.0})
	# the ▲ is the backlog's sign, labelled as the strain (E4 step 10, the step 9 review's item 4; was "61% ▲ gaining")
	t.ok(pin == "Your odds 61% · strain ▲ rising · drains in ∞", "the pinned odds (%s)" % pin)
	var cards: Dictionary = MapLogic.cfg()["cards"]
	t.ok(str(cards["vei_odds_label"]).to_lower().contains("your odds") and str(cards["vei_sign_label"]).contains("STRAIN (▲ = rising)"), "the Vei card says whose odds and what ▲ means")
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
	t.near(eta, float(MapLogic.cfg()["demo_nodes"]["relish"]["eta_s"]), 1e-6, "the demo's configured ETA (demo_nodes.relish.eta_s)")
	var without: Dictionary = MapLogic.cfg()["demo_nodes"]["relish"].duplicate()
	without.erase("eta_s")
	var rel := m.relish.duplicate()
	var saved: Dictionary = MapLogic.cfg()["demo_nodes"]["relish"]
	MapLogic.cfg()["demo_nodes"]["relish"] = without
	NodeLogic.demo_overlay(m.forts, m.vei, m.hud, rel, m.node_pos("covington"), m.realm_cfg.get("flip", {}), speed)
	MapLogic.cfg()["demo_nodes"]["relish"] = saved
	t.near(float(rel["eta_s"]), MapModel.to_vec(rel["pos"]).distance_to(to) / speed, 1e-3, "without eta_s, the rest of the way at her travel speed")
	t.ok(RelishLogic.fmt_eta(eta) != "0:00", "so stills never read 0:00")
