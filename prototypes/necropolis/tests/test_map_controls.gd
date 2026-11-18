extends RefCounted
## Tests for the map's controls: the valve panel's math (scripts/map/valve_logic.gd), Relish's
## travel UX (scripts/map/relish_logic.gd: chip text, ETA, reasons, card actions, route
## preview, the here/left lane why), the API calls the panel and buttons make against a real
## GameState, and source greps: no legacy path and no un-versioned emit in the map.

const MAP_DIR := "res://scripts/map"
const NEW_FILES := ["valve_logic.gd", "relish_logic.gd", "map_valve.gd", "map_relish_chip.gd", "map_route_hint.gd", "map_ui.gd"]
const SIDE := 200.0
## who comes in, as the sidebar passes it to RelishLogic.fort_actions: 2 + 0 undead, 1 big, no warning
const CM := {"ci": {"garrison": 2, "starter": 0, "bigs": 1, "total": 3}, "warn": {}}


func run() -> int:
	var t := TestUtil.new()
	Palette.configure(TestUtil.load_json("res://configs/palette.json"))
	MapLogic.configure(TestUtil.load_json("res://configs/map_view.json"))
	_geometry(t)
	_percents_and_project(t)
	_throttle(t)
	_panel_text(t)
	_bone_edge(t)
	_payoff_cost(t)
	_eta_and_chip(t)
	_reasons(t)
	_actions(t)
	_routes(t)
	_real_state(t)
	_steps(t)
	_sources(t)
	return t.failures


func _vclose(a: Dictionary, b: Dictionary) -> bool:
	return ValveLogic.same(a, b, 1e-4)


func _geometry(t: TestUtil) -> void:
	t.suite("map_controls-valve-geometry")
	t.ok(float(MapLogic.cfg()["valve_tri_px"]) >= 200.0, "the triangle's side is at least 200 px")
	var c := ValveLogic.corners(SIDE)
	t.near((c["war"] as Vector2).distance_to(c["work"]), SIDE, 1e-3, "WAR-WORK side is the triangle side")
	t.near((c["flood"] as Vector2).distance_to(c["work"]), SIDE, 1e-3, "FLOOD-WORK side is the triangle side")
	t.near((c["war"] as Vector2).distance_to(c["flood"]), SIDE, 1e-3, "WAR-FLOOD side is the triangle side")
	for v in [{"work": 0.4, "war": 0.45, "flood": 0.15}, {"work": 1.0, "war": 0.0, "flood": 0.0},
			{"work": 0.2, "war": 0.2, "flood": 0.6}, {"work": 0.0, "war": 0.5, "flood": 0.5}]:
		var p := ValveLogic.point_of(v, SIDE)
		t.ok(_vclose(ValveLogic.bary_of(p, SIDE), v), "round trip valve -> point -> valve %s" % str(v))
	for k in ValveLogic.KEYS:
		t.ok(ValveLogic.point_of(ValveLogic.snap(k), SIDE).is_equal_approx(c[k]), "the %s snap sits on its corner" % k)
	var centre := ValveLogic.point_of({"work": 1.0, "war": 1.0, "flood": 1.0}, SIDE)
	t.ok(_vclose(ValveLogic.valve_at(centre, SIDE), {"work": 1.0 / 3.0, "war": 1.0 / 3.0, "flood": 1.0 / 3.0}), "the centroid is thirds")
	# outside points clamp onto the triangle
	var far_out := [Vector2(-80, -80), Vector2(SIDE * 0.5, -60), Vector2(SIDE + 90, ValveLogic.height(SIDE) + 40), Vector2(SIDE * 0.5, ValveLogic.height(SIDE) + 70), Vector2(-30, ValveLogic.height(SIDE) * 0.5)]
	for p in far_out:
		var q := ValveLogic.clamp_point(p, SIDE)
		t.ok(ValveLogic.is_inside(q, SIDE), "%s clamps inside the triangle" % str(p))
		var v := ValveLogic.valve_at(p, SIDE)
		t.near(float(v["work"]) + float(v["war"]) + float(v["flood"]), 1.0, 1e-6, "the clamped valve's shares sum to 1")
		t.ok(float(v["work"]) >= 0.0 and float(v["war"]) >= 0.0 and float(v["flood"]) >= 0.0, "and none is negative")
	t.ok(ValveLogic.clamp_point(Vector2(SIDE * 0.5, -60), SIDE).is_equal_approx(c["war"]), "straight above the apex clamps to WAR")
	t.ok(_vclose(ValveLogic.valve_at(Vector2(SIDE * 0.5, -60), SIDE), ValveLogic.snap("war")), "and means 100% WAR")
	var inside := Vector2(SIDE * 0.5, ValveLogic.height(SIDE) * 0.6)
	t.ok(ValveLogic.clamp_point(inside, SIDE) == inside, "an inside point is unchanged")
	# snaps and normalising
	t.ok(ValveLogic.snap("work") == {"work": 1.0, "war": 0.0, "flood": 0.0}, "corner snap WORK = 100/0/0")
	t.ok(ValveLogic.snap("war") == {"work": 0.0, "war": 1.0, "flood": 0.0}, "corner snap WAR = 0/100/0")
	t.ok(ValveLogic.snap("flood") == {"work": 0.0, "war": 0.0, "flood": 1.0}, "corner snap FLOOD = 0/0/100")
	var n := ValveLogic.normalise({"work": 2.0, "war": 2.0, "flood": 1.0})
	t.ok(_vclose(n, {"work": 0.4, "war": 0.4, "flood": 0.2}), "normalise sums to 1 (2,2,1 -> .4,.4,.2)")
	t.ok(_vclose(ValveLogic.normalise({"work": -1.0, "war": 1.0, "flood": 0.0}), ValveLogic.snap("war")), "a negative share is dropped")
	t.ok(_vclose(ValveLogic.normalise({"work": 0.0, "war": 0.0, "flood": 0.0}), ValveLogic.snap("work")), "all-zero falls back to WORK, never NaN")


func _percents_and_project(t: TestUtil) -> void:
	t.suite("map_controls-valve-project")
	for v in [{"work": 1.0 / 3.0, "war": 1.0 / 3.0, "flood": 1.0 / 3.0}, {"work": 0.4, "war": 0.45, "flood": 0.15}, {"work": 0.333, "war": 0.333, "flood": 0.334}, ValveLogic.snap("flood")]:
		var p := ValveLogic.percents(v)
		t.ok(int(p["work"]) + int(p["war"]) + int(p["flood"]) == 100, "percents sum to exactly 100 for %s" % str(v))
	t.ok(ValveLogic.percents({"work": 0.4, "war": 0.45, "flood": 0.15}) == {"work": 40, "war": 45, "flood": 15}, "40/45/15")
	var hud := {"rates": [{"id": "mint", "rate": 10.0, "stock": -1.0, "cap": -1.0}, {"id": "gold", "rate": 1.0, "stock": 5.0, "cap": -1.0}],
		"valve": {"work": 0.4, "war": 0.4, "flood": 0.2}, "workers_steady": 60.0}
	t.near(ValveLogic.mint_rate(hud), 10.0, 1e-9, "mint rate comes from the mint row")
	t.near(ValveLogic.mint_rate({}), 0.0, 1e-9, "no rates reads 0")
	# the projection is the view's: a real GameState's view_projection, read through IdleLogic.projection
	var gs := GameState.new(TestUtil.configs())
	gs.debug_enabled = true
	gs.cmd_debug_load_fixture("midgame_2flips")
	var valve := {"work": 0.2, "war": 0.5, "flood": 0.3}
	var view := gs.view_projection(ValveLogic.normalise(valve))
	var pr := IdleLogic.projection(gs, valve, IdleLogic.held_forts(gs.view_realm()["forts"]))
	t.near(float(pr["split"]["war"]), float(view["split"]["war"]), 1e-9, "split.war is view_projection's")
	t.near(float(pr["workers_steady"]), float(view["workers_steady"]), 1e-9, "workers_steady is view_projection's")
	t.ok(pr["war_supports"] == view["war_supports"], "war_supports is view_projection's")
	t.ok(not FileAccess.get_file_as_string("res://scripts/map/valve_logic.gd").contains("static func project("), "the valve's own projection stand-in is gone")
	var rows := ValveLogic.rows(pr, valve)
	t.ok(rows[1]["rate_text"] == MapLogic.fmt_rate(float(view["split"]["war"])), "the WAR row's rate is the view's split.war")


func _throttle(t: TestUtil) -> void:
	t.suite("map_controls-valve-throttle")
	var hz := float(MapLogic.cfg()["valve_send_hz"])
	t.ok(hz > 0.0, "valve_send_hz is configured (%s)" % hz)
	t.ok(ValveLogic.should_send(0.0, -1.0, hz, false), "the first event of a drag sends")
	t.ok(not ValveLogic.should_send(0.05, 0.0, hz, false), "an event inside 1/hz does not")
	t.ok(ValveLogic.should_send(1.0 / hz + 0.001, 0.0, hz, false), "one past 1/hz does")
	t.ok(ValveLogic.should_send(0.01, 0.0, hz, true), "release always sends")
	t.ok(ValveLogic.should_send(0.0, 0.0, 0.0, true), "release sends even with hz 0")
	t.ok(not ValveLogic.should_send(5.0, 0.0, 0.0, false), "hz 0 never sends mid-drag")
	var sent := 0
	var last := -1.0
	for i in 100:  # a 1 s drag at 100 Hz of motion events
		var now := i * 0.01
		if ValveLogic.should_send(now, last, hz, false):
			sent += 1
			last = now
	t.ok(sent <= int(hz) + 1, "a 1 s drag sends at most valve_send_hz + 1 commands (%d)" % sent)
	t.ok(sent >= int(hz) - 1, "and not far fewer (%d)" % sent)


func _panel_text(t: TestUtil) -> void:
	t.suite("map_controls-valve-text")
	var pr := {"split": {"work": 2.0, "war": 2.0, "flood": 1.0}, "workers_steady": 61.4, "war_supports": {"n": 0, "m": 2}}
	var rows := ValveLogic.rows(pr, {"work": 0.4, "war": 0.4, "flood": 0.2})
	t.ok(rows.map(func(r): return r["name"]) == ["WORK", "WAR", "FLOOD"], "rows run WORK, WAR, FLOOD")
	t.ok(rows.map(func(r): return r["pct_text"]) == ["40%", "40%", "20%"], "shares are integer percentages")
	t.ok(rows.map(func(r): return r["rate_text"]) == ["+2.0/s", "+2.0/s", "+1.0/s"], "rates are signed with /s")
	t.ok(rows[0]["feed_text"] == "→ workforce" and rows[1]["feed_text"] == "→ the forts" and rows[2]["feed_text"] == "→ Vei's gates", "each stream says what it feeds")
	t.ok(ValveLogic.workers_text(float(pr["workers_steady"])) == "workers → 61", "workers → 61")
	t.ok(ValveLogic.supports_text(pr) == "WAR supports 0 of 2 held forts", "the supports line shows when forts are held")
	t.ok(ValveLogic.supports_text({"war_supports": {"n": 0, "m": 0}}) == "", "and is hidden when none is held")


## The valve marks where bone starts (view_hud.bone_war_share) and says so while the stall is live.
func _bone_edge(t: TestUtil) -> void:
	t.suite("map_controls-valve-bone-edge")
	var seg := ValveLogic.bone_tick(0.54, SIDE)
	t.ok(seg.size() == 2, "a share inside 0..1 has a tick")
	var a: Vector2 = seg[0]
	var b: Vector2 = seg[1]
	t.ok(is_equal_approx(a.y, b.y) and is_equal_approx(a.y, ValveLogic.height(SIDE) * 0.46), "the tick is level, 0.54 of the way up to WAR: y = %.1f" % a.y)
	t.ok(is_equal_approx(b.x - a.x, SIDE * 0.46), "its length is the triangle's width there (%.1f)" % (b.x - a.x))
	t.ok(absf(float(ValveLogic.bary_of(a, SIDE)["war"]) - 0.54) < 1e-4 and absf(float(ValveLogic.bary_of(b, SIDE)["war"]) - 0.54) < 1e-4, "both ends sit at WAR share 0.54")
	t.ok(ValveLogic.is_inside(a, SIDE) and ValveLogic.is_inside(b, SIDE), "and on the triangle's edges")
	t.ok(ValveLogic.bone_tick(0.0, SIDE).is_empty() and ValveLogic.bone_tick(1.0, SIDE).is_empty() and ValveLogic.bone_tick(-0.2, SIDE).is_empty(), "no edge (0, 1 or none): no tick")
	# the edge is a new game's: marked (tick, label, drag line) only while no fort has been taken
	t.ok(is_equal_approx(ValveLogic.bone_edge({"bone_war_share": 0.54, "highest_tier_flipped": 0}), 0.54), "no fort taken: the edge is marked")
	t.ok(ValveLogic.bone_edge({"bone_war_share": 0.54, "highest_tier_flipped": 1}) == 0.0, "a fort taken: the edge is stale, none marked")
	var late := ValveLogic.bone_edge({"bone_war_share": 0.54, "highest_tier_flipped": 2})
	t.ok(ValveLogic.bone_tick(late, SIDE).is_empty() and ValveLogic.bone_readout(false, "Raise WAR", true, 0.1, late) == "", "late: no tick and no below-edge line")
	t.ok(ValveLogic.bone_readout(true, "Raise WAR", false, 0.8, late) == "Raise WAR: the pits eat every body", "but a live stall's lever line stays, whatever the tier")
	var lever := "Raise WAR"
	t.ok(ValveLogic.bone_readout(true, lever, false, 0.8, 0.54) == "Raise WAR: the pits eat every body", "a live stall carries the lever line")
	t.ok(ValveLogic.bone_readout(true, lever, true, 0.3, 0.54) == "Raise WAR: the pits eat every body", "and keeps it while dragging (one line)")
	t.ok(ValveLogic.bone_readout(false, lever, false, 0.2, 0.54) == "", "no stall, no drag: nothing, even below the edge")
	t.ok(ValveLogic.bone_readout(false, lever, true, 0.3, 0.54) == "below the bone edge", "dragging under the edge says so")
	t.ok(ValveLogic.bone_readout(false, lever, true, 0.54, 0.54) == "" and ValveLogic.bone_readout(false, lever, true, 0.7, 0.54) == "", "at or above the edge: nothing")
	t.ok(ValveLogic.bone_readout(false, lever, true, 0.3, 0.0) == "", "no edge from the view: nothing")
	var c: Dictionary = MapLogic.cfg()["controls"]
	t.ok(str(c["valve_bone_label"]) == "bone", "the tick's tiny label")
	var plate := Palette.c("ground").lightened(float(MapLogic.cfg()["panel_bg_lighten"]))
	var pa := float(c["valve_plate_alpha"])
	var bright := ""
	for k in Palette.keys():
		if bright == "" or MapLogic.luminance(Palette.c(k)) > MapLogic.luminance(Palette.c(bright)):
			bright = k
	var through := Palette.c("ground").lerp(Palette.c(bright), 1.0 - pa)
	var under := plate.lerp(through, 1.0 - pa)
	for key in [str(MapLogic.cfg()["bone_line"]["key"]), str(c["valve_bone_label_key"])]:
		for g in [plate, under]:
			var r := MapLogic.contrast_ratio(Palette.c(key), g)
			t.ok(r >= 4.5, "valve text in %s reads 4.5:1 on the valve plate (%.1f)" % [key, r])
	t.ok(float(c["valve_bone_tick_w_px"]) >= 1.0, "the tick is at least 1 px")


func _payoff_cost(t: TestUtil) -> void:
	t.suite("map_controls-payoff-cost")
	var eps := 0.05
	var base := {"work": 5.1, "war": 9.7, "flood": 2.0}
	var hold := {"n": 1, "m": 2}
	t.ok(ValveLogic.payoff_costs({"split": base.duplicate(), "war_supports": hold}, base, eps).is_empty(), "a drag back onto the current valve costs nothing")
	t.ok(ValveLogic.payoff_costs({"split": {"work": 6.0, "war": 10.0, "flood": 1.0}, "war_supports": hold}, base, eps).is_empty(), "raising WORK and WAR costs nothing")
	t.ok(ValveLogic.payoff_costs({"split": {"work": 5.08, "war": 9.68, "flood": 2.0}, "war_supports": hold}, base, eps).is_empty(), "a fall within sign_eps costs nothing")
	var work_only := ValveLogic.payoff_costs({"split": {"work": 1.5, "war": 9.7, "flood": 2.0}, "war_supports": hold}, base, eps)
	t.ok(work_only == ["workers +5.1 → +1.5/s"], "WORK only: %s" % str(work_only))
	var war_only := ValveLogic.payoff_costs({"split": {"work": 5.1, "war": 2.0, "flood": 2.0}, "war_supports": hold}, base, eps)
	t.ok(war_only == ["WAR +9.7 → +2.0/s", "supports 1 of 2"], "WAR only, with its supports: %s" % str(war_only))
	var both := ValveLogic.payoff_costs({"split": {"work": 1.5, "war": 2.0, "flood": 2.0}, "war_supports": hold}, base, eps)
	t.ok(both == ["workers +5.1 → +1.5/s", "WAR +9.7 → +2.0/s", "supports 1 of 2"], "both, in WORK then WAR order: %s" % str(both))
	var none_held := ValveLogic.payoff_costs({"split": {"work": 5.1, "war": 2.0, "flood": 2.0}, "war_supports": {"n": 0, "m": 0}}, base, eps)
	t.ok(none_held == ["WAR +9.7 → +2.0/s"], "supports only when a fort is held: %s" % str(none_held))
	var war_up := ValveLogic.payoff_costs({"split": {"work": 1.5, "war": 12.0, "flood": 2.0}, "war_supports": hold}, base, eps)
	t.ok(war_up == ["workers +5.1 → +1.5/s"], "supports only when WAR falls: %s" % str(war_up))
	for part in both.slice(0, 2):
		var sp := ValveLogic.payoff_spans(part)
		var rates := sp.filter(func(x): return x["kind"] == "rate").map(func(x): return x["text"])
		t.ok(rates.size() == 2 and part.contains(rates[0]) and part.contains(rates[1]), "both numbers of '%s' are rate spans (%s)" % [part, str(rates)])
	t.ok(ValveLogic.payoff_spans("odds in 10 min 67% → 68%").all(func(x): return x["kind"] != "rate"), "percentages stay out of the rate face")
	t.ok(ValveLogic.payoff_spans("supports 1 of 2").all(func(x): return x["kind"] != "rate"), "the supports count is not a rate")
	# the wrap choice: widths and kinds of [main, cost...], the separator's width, the inner width
	var k3 := ["main", "work", "war"]
	t.ok(ValveLogic.payoff_rows([200.0, 60.0, 60.0], k3, 10.0, 400.0) == [0, 0, 0], "everything fits: one row")
	t.ok(ValveLogic.payoff_rows([200.0, 60.0, 60.0], k3, 10.0, 339.0) == [0, 1, 1], "it does not fit: the costs wrap whole, at the separator before the first")
	t.ok(ValveLogic.payoff_rows([200.0, 60.0, 60.0], k3, 10.0, 340.0) == [0, 0, 0], "an exact fit stays on one row")
	t.ok(ValveLogic.payoff_rows([200.0], ["main"], 10.0, 100.0) == [0], "a lone main part stays on row one")
	t.ok(ValveLogic.payoff_rows([], [], 10.0, 100.0).is_empty(), "no parts, no rows")
	var k4 := ["main", "work", "war", "supports"]
	var w4 := [300.0, 100.0, 100.0, 80.0]
	t.ok(ValveLogic.payoff_rows(w4, k4, 10.0, 300.0) == [0, 1, 1, 1], "row 2 exactly fits: all costs stay (%s)" % str(ValveLogic.payoff_rows(w4, k4, 10.0, 300.0)))
	t.ok(ValveLogic.payoff_rows(w4, k4, 10.0, 299.0) == [0, 1, 1, -1], "row 2 overflows: supports is dropped first")
	t.ok(ValveLogic.payoff_rows(w4, k4, 10.0, 209.0) == [0, 1, -1, -1], "a further overflow: WAR goes too, whole parts only")
	t.ok(ValveLogic.payoff_rows(w4, k4, 10.0, 99.0) == [0, -1, -1, -1], "nothing fits: the main part alone")
	t.ok(ValveLogic.payoff_rows([500.0, 100.0], ["main", "work"], 10.0, 400.0) == [0, 1], "an oversized first part sits alone on row 0, the cost below it")
	t.ok(ValveLogic.payoff_rows([500.0], ["main"], 10.0, 400.0) == [0], "an oversized lone first part stays on row 0 (it clips at the plate)")
	var kw := ["main", "war", "supports"]
	t.ok(ValveLogic.payoff_rows([300.0, 100.0, 80.0], kw, 10.0, 150.0) == [0, 1, -1], "WAR with its supports: supports dropped, WAR kept")


func _eta_and_chip(t: TestUtil) -> void:
	t.suite("map_controls-chip")
	t.ok(RelishLogic.fmt_eta(4.0) == "0:04" and RelishLogic.fmt_eta(0.0) == "0:00", "ETA m:ss: 0:04, 0:00")
	t.ok(RelishLogic.fmt_eta(90.0) == "1:30" and RelishLogic.fmt_eta(600.0) == "10:00", "ETA m:ss: 1:30, 10:00")
	t.ok(RelishLogic.fmt_eta(6.6) == "0:07" and RelishLogic.fmt_eta(-3.0) == "0:00", "rounds up, and never negative")
	t.near(RelishLogic.eta_s(440.0, 220.0), 2.0, 1e-9, "distance / travel_speed")
	t.near(RelishLogic.eta_s(440.0, 0.0), 0.0, 1e-9, "no speed: 0, no divide by zero")
	var gw := {"greywall": "Greywall", "covington": "Covington"}
	var ret := {"type": "relish_returned", "fort_id": "greywall", "cause": "retaken", "t": 90.0}
	t.ok(RelishLogic.returned_toast(ret, gw) == "Vei retook Greywall. Relish is walking home.", "relish_returned toasts the retake in the glossary's words")
	t.ok(RelishLogic.returned_toast({"type": "fort_retaken", "fort_id": "greywall"}, gw) == "", "another event type: no toast")
	t.ok(RelishLogic.returned_toast({"type": "relish_returned", "fort_id": "nowhere", "cause": "retaken"}, gw) == "", "an unknown fort: no toast")
	var names := {"covington": "Covington", "old-sluice": "Old Sluice", "ashgate": "Ashgate"}
	t.ok(RelishLogic.chip_text({"state": "home", "at": "covington"}, names) == "Relish · home (Covington)", "chip: home")
	t.ok(RelishLogic.chip_text({"state": "at_fort", "at": "old-sluice"}, names) == "Relish · at Old Sluice", "chip: at a fort")
	t.ok(RelishLogic.chip_text({"state": "travelling", "at": "covington", "target": "ashgate", "eta_s": 4.2}, names) == "Relish · travelling → Ashgate · 0:05", "chip: travelling with ETA (rounded up)")
	t.ok(RelishLogic.chip_text({"state": "in_dungeon", "at": "old-sluice"}, names) == "Relish · in Old Sluice's dungeon", "chip: in a dungeon")
	t.ok(RelishLogic.chip_text({"state": "at_vei", "at": "vei"}, names) == "Relish · at Vei's gates", "chip: at Vei's gates")
	t.ok(RelishLogic.chip_text({"state": "dead", "at": "covington", "dead_s_left": 90.0}, names) == "Relish · dead · 1:30", "chip: dead with the countdown")
	t.ok(RelishLogic.chip_text({"state": "in_boss", "at": "vei"}, names).begins_with("Relish ·"), "chip: in the boss fight")
	t.ok(RelishLogic.chip_text({"state": "at_fort", "at": "nowhere-yet"}, names) == "Relish · at Nowhere Yet", "an unknown id falls back to a capitalised id")
	var home := RelishLogic.chip_buttons({"state": "home", "at": "covington"})
	t.ok(not home["go_home"] and not home["cancel"], "home: no GO HOME, no CANCEL")
	var away := RelishLogic.chip_buttons({"state": "at_fort", "at": "old-sluice"})
	t.ok(away["go_home"] and not away["cancel"], "at a fort: GO HOME only")
	var out := RelishLogic.chip_buttons({"state": "travelling", "at": "covington", "target": "ashgate"})
	t.ok(out["go_home"] and out["cancel"], "travelling out: GO HOME and CANCEL")
	var back := RelishLogic.chip_buttons({"state": "travelling", "at": "ashgate", "target": "covington"})
	t.ok(not back["go_home"] and back["cancel"], "travelling home: CANCEL only")
	t.ok(RelishLogic.chip_buttons({"state": "dead", "at": "covington"})["go_home"], "dead away from home still offers GO HOME (the refusal says why)")
	t.ok(float(MapLogic.cfg()["button_min_h_px"]) >= 44.0, "buttons are at least 44 px tall")
	t.ok(RelishLogic.chip_inline(200.0, [100.0], 6.0, 8.0, 490.0), "chip: name + one button fit one row")
	t.ok(RelishLogic.chip_inline(200.0, [], 6.0, 8.0, 100.0) == false, "chip: a name wider than the room does not claim to fit")
	t.ok(RelishLogic.chip_inline(100.0, [], 6.0, 8.0, 490.0), "chip: no buttons, one row")
	t.ok(not RelishLogic.chip_inline(290.0, [100.0, 100.0], 6.0, 8.0, 490.0), "chip: a long travelling name with two buttons wraps")
	t.near(RelishLogic.chip_row_w(200.0, [100.0, 80.0], 6.0, 8.0), 408.0, 1e-9, "chip row width: pad both sides + name + each button and its gap")
	t.ok(RelishLogic.chip_inline(250.0, [100.0, 100.0], 6.0, 8.0, 490.0) == (16.0 + 250.0 + 212.0 <= 490.0), "chip: inline iff the row width is within max")


func _reasons(t: TestUtil) -> void:
	t.suite("map_controls-reasons")
	var by_cmd := {
		"cmd_move_relish": ["dead", "in_dungeon", "in_boss", "unknown_node"],
		"cmd_cancel_travel": ["not_travelling"],
		"cmd_begin_dungeon": ["unknown_fort", "busy", "dead", "not_at_fort"],
		"cmd_begin_boss": ["busy", "dead", "not_at_vei"],
		"cmd_set_valve": ["not_finite", "negative", "zero_valve"],
		"cmd_set_haul_target": ["unknown_fort"],
	}
	var table: Dictionary = MapLogic.cfg()["controls"]["reasons"]
	for cmd in by_cmd:
		for r in by_cmd[cmd]:
			t.ok(table.has(r) and str(table[r]) != "", "%s: reason %s has words" % [cmd, r])
			t.ok(RelishLogic.reason_text(r) == str(table[r]), "%s: reason_text uses the config" % r)
	t.ok(RelishLogic.reason_text("not_at_fort") == "Relish must stand here first. MOVE her.", "not_at_fort wording")
	t.ok(RelishLogic.reason_text("busy") == "A raid is already open", "busy wording")
	t.ok(RelishLogic.reason_text("not_at_vei") == "Relish must stand at Vei's gates. MOVE her.", "not_at_vei wording")
	t.ok(RelishLogic.reason_text("dead") == "Relish is dead" and RelishLogic.reason_text("in_dungeon") == "Relish is in a dungeon" and RelishLogic.reason_text("in_boss") == "Relish is facing Vei", "dead / in_dungeon / in_boss wording")
	var fb := RelishLogic.reason_text("totally_new")
	t.ok(fb.contains("totally_new") and fb != "", "an unknown reason gets the generic fallback (%s)" % fb)


func _fort(id: String, can: bool, reason: String) -> Dictionary:
	return {"id": id, "name": id.capitalize(), "can_descend": can, "reason": reason}


func _acts(items: Array) -> Array:
	return items.filter(func(i): return i["kind"] == "button").map(func(i): return i["act"])


func _actions(t: TestUtil) -> void:
	t.suite("map_controls-actions")
	var names := {"old-sluice": "Old Sluice", "ashgate": "Ashgate"}
	var auto := {"target": "auto", "current": "old-sluice", "convoys": []}
	var home := {"state": "home", "at": "covington", "target": "", "eta_s": -1.0}
	var a := RelishLogic.fort_actions(_fort("ashgate", false, "not_at_fort"), home, auto, names, CM)
	t.ok(_acts(a) == ["move", "descend", "haul"], "from home: MOVE, DESCEND, HAUL FROM HERE")
	t.ok(a.filter(func(i): return i["act"] == "descend")[0]["enabled"] == false, "DESCEND is disabled")
	t.ok(a.any(func(i): return i["kind"] == "line" and i["text"] == "Relish must stand here first. MOVE her."), "and says why in words")
	t.ok(a.any(func(i): return i["text"] == "Haul: Old Sluice (auto)"), "the haul line names the auto pick")
	t.ok(a.any(func(i): return i["text"] == "HAUL FROM HERE"), "the haul button")
	var trav := {"state": "travelling", "at": "covington", "target": "ashgate", "eta_s": 3.6}
	var b := RelishLogic.fort_actions(_fort("ashgate", false, "not_at_fort"), trav, auto, names, CM)
	t.ok(_acts(b) == ["cancel", "descend", "haul"], "heading here: CANCEL replaces MOVE")
	t.ok(b.any(func(i): return i["kind"] == "line" and i["text"] == "on her way · 0:04"), "with 'on her way · 0:04'")
	var other := RelishLogic.fort_actions(_fort("old-sluice", false, "not_at_fort"), trav, auto, names, CM)
	t.ok(_acts(other) == ["move", "descend", "haul"], "heading elsewhere: another fort's card still has MOVE")
	var there := {"state": "at_fort", "at": "ashgate", "target": "", "eta_s": -1.0}
	var c := RelishLogic.fort_actions(_fort("ashgate", true, ""), there, auto, names, CM)
	t.ok(_acts(c) == ["descend", "haul"], "arrived: no MOVE button")
	t.ok(c.any(func(i): return i["text"] == "Relish is here"), "it says 'Relish is here'")
	t.ok(c.filter(func(i): return i["act"] == "descend")[0]["enabled"] == true, "DESCEND is enabled when can_descend")
	t.ok(not c.any(func(i): return i["kind"] == "line" and i["text"].begins_with("Relish must")), "and shows no reason")
	var busy := RelishLogic.fort_actions(_fort("ashgate", false, "busy"), there, auto, names, CM)
	t.ok(busy.any(func(i): return i["text"] == "A raid is already open"), "busy reason in words")
	var dead := RelishLogic.fort_actions(_fort("ashgate", false, "dead"), {"state": "dead", "at": "covington"}, auto, names, CM)
	t.ok(dead.any(func(i): return i["text"] == "Relish is dead"), "dead reason in words")
	var set := RelishLogic.fort_actions(_fort("ashgate", true, ""), there, {"target": "ashgate", "current": "ashgate", "convoys": []}, names, CM)
	t.ok(_acts(set) == ["descend", "haul_auto"], "a set target shows BACK TO AUTO")
	t.ok(set.any(func(i): return i["text"] == "Haul: Ashgate (set)"), "'Haul: Ashgate (set)'")
	t.ok(RelishLogic.haul_line({"target": "auto", "current": ""}, names) == "Haul: none yet (auto)", "auto with no pick yet")
	# Vei
	var v1 := RelishLogic.vei_actions({"can_begin": false, "reason": "not_at_vei"}, home)
	t.ok(_acts(v1) == ["move", "begin"] and v1.filter(func(i): return i["act"] == "begin")[0]["enabled"] == false, "Vei: MOVE and a disabled BEGIN")
	t.ok(v1.any(func(i): return i["text"] == "Relish must stand at Vei's gates. MOVE her."), "with the reason in words")
	var v2 := RelishLogic.vei_actions({"can_begin": true, "reason": ""}, {"state": "at_vei", "at": "vei"})
	t.ok(_acts(v2) == ["begin"] and v2.filter(func(i): return i["act"] == "begin")[0]["enabled"] == true, "at Vei's gates: BEGIN enabled")
	t.ok(RelishLogic.actions_sig(a) != RelishLogic.actions_sig(c), "the structure key changes with the layout")
	t.ok(RelishLogic.actions_sig(b) == RelishLogic.actions_sig(RelishLogic.fort_actions(_fort("ashgate", false, "not_at_fort"), {"state": "travelling", "at": "covington", "target": "ashgate", "eta_s": 2.1}, auto, names, CM)), "but not with a ticking ETA")
	# the line above DESCEND: the count, or the warning in its key; the structure key ignores text and key
	var di := c.find_custom(func(i): return i["act"] == "descend")
	t.ok(di > 0 and c[di - 1]["kind"] == "line" and c[di - 1]["text"] == "2 undead and 1 big undead come in" and not c[di - 1].has("key"), "a count line directly above DESCEND")
	var warned := RelishLogic.fort_actions(_fort("ashgate", true, ""), there, auto, names,
		{"ci": {"garrison": 0, "starter": 0, "bigs": 0, "total": 0}, "warn": {"text": "No undead come in. X", "key": "danger"}})
	var wdi := warned.find_custom(func(i): return i["act"] == "descend")
	t.ok(warned[wdi - 1]["text"] == "No undead come in. X" and warned[wdi - 1]["key"] == "danger", "the warning replaces the count, with its key")
	t.ok(RelishLogic.actions_sig(warned) == RelishLogic.actions_sig(c), "the structure key ignores the line's text and key")


func _routes(t: TestUtil) -> void:
	t.suite("map_controls-routes")
	var home := {"state": "home", "at": "covington", "target": ""}
	var trav := {"state": "travelling", "at": "covington", "target": "ashgate"}
	t.ok(RelishLogic.route_state(home, "ashgate", true) == {"travel": false, "preview": true}, "home + a fort card: preview")
	t.ok(RelishLogic.route_state(home, "", false) == {"travel": false, "preview": false}, "no card: nothing")
	t.ok(RelishLogic.route_state(home, "some-village", false)["preview"] == false, "a village card: no preview")
	t.ok(RelishLogic.route_state({"state": "at_fort", "at": "ashgate", "target": ""}, "ashgate", true)["preview"] == false, "already there: no preview")
	t.ok(RelishLogic.route_state({"state": "at_fort", "at": "ashgate", "target": ""}, "vei", true)["preview"], "at a fort, Vei's card: preview")
	t.ok(RelishLogic.route_state(trav, "ashgate", true) == {"travel": true, "preview": false}, "heading to the open card: the travel route only")
	t.ok(RelishLogic.route_state(trav, "", false) == {"travel": true, "preview": false}, "travelling with no card: the travel route")
	t.ok(RelishLogic.route_state(trav, "old-sluice", true) == {"travel": true, "preview": true}, "travelling elsewhere: her route and the would-be route")
	for st in ["dead", "in_dungeon", "in_boss"]:
		t.ok(RelishLogic.route_state({"state": st, "at": "old-sluice", "target": ""}, "ashgate", true)["preview"] == false, "%s: no preview" % st)
	var segs := RelishLogic.dash_segments(Vector2.ZERO, Vector2(100, 0), 10.0, 5.0)
	t.ok(segs.size() == 7, "100 px at 10 on / 5 off is 7 dashes (%d)" % segs.size())
	t.ok(segs[0][0] == Vector2.ZERO and (segs[0][1] as Vector2).is_equal_approx(Vector2(10, 0)), "the first dash starts at the origin")
	t.ok((segs.back()[1] as Vector2).is_equal_approx(Vector2(100, 0)) or (segs.back()[1] as Vector2).x <= 100.0, "no dash runs past the end")
	t.ok(RelishLogic.dash_segments(Vector2(3, 3), Vector2(3, 3), 10.0, 5.0).is_empty(), "a zero-length line has no dashes")
	t.ok(RelishLogic.dash_segments(Vector2.ZERO, Vector2(50, 0), 0.0, 5.0).is_empty(), "a zero dash makes none (no endless loop)")
	var flat := RelishLogic.dash_points(Vector2.ZERO, Vector2(100, 0), 10.0, 5.0)
	t.ok(flat.size() == segs.size() * 2 and flat[0] == segs[0][0] and flat[1] == segs[0][1] and flat[flat.size() - 1] == segs.back()[1], "dash_points is the segments' endpoints in order, ready for one draw_multiline")
	t.ok(RelishLogic.dash_points(Vector2(3, 3), Vector2(3, 3), 10.0, 5.0).is_empty(), "no points for a zero-length line")
	t.ok(not RelishLogic.moved_enough(Vector2.ZERO, Vector2(0.2, 0.0), 1.0, 0.5), "under half a screen px: no redraw")
	t.ok(RelishLogic.moved_enough(Vector2.ZERO, Vector2(0.2, 0.0), 2.5, 0.5), "the same drift at zoom 2.5 is half a px: redraw")
	t.ok(float(MapLogic.cfg()["controls"]["route_redraw_px"]) > 0.0, "route_redraw_px is configured")


func _real_state(t: TestUtil) -> void:
	t.suite("map_controls-state")
	var s := GameState.new(TestUtil.configs())
	s.debug_enabled = true
	t.ok(s.cmd_debug_load_fixture("day1")["ok"], "fixture day1 loads")
	# the valve
	var r := s.cmd_set_valve(2, 2, 1)
	t.ok(r["ok"], "cmd_set_valve(2, 2, 1) is accepted")
	var vt: Dictionary = s.view_hud()["valve_target"]
	t.ok(_vclose(vt, {"work": 0.4, "war": 0.4, "flood": 0.2}), "the target echoes in view_hud().valve_target")
	var snap := ValveLogic.snap("war")
	t.ok(s.cmd_set_valve(snap["work"], snap["war"], snap["flood"])["ok"], "a 100%-one-corner valve (two zeros) is legal")
	t.ok(_vclose(s.view_hud()["valve_target"], snap), "and echoes")
	var bad := s.cmd_set_valve(0, 0, 0)
	t.ok(not bad["ok"] and bad["reason"] == "zero_valve" and RelishLogic.reason_text(bad["reason"]) != "", "all-zero is refused with a reason the toast can word")
	# Relish
	var names := {"covington": "Covington"}
	for f in s.view_realm()["forts"]:
		names[f["id"]] = f["name"]
	var m := s.cmd_move_relish("old-sluice")
	t.ok(m["ok"] and float(m["eta_s"]) > 0.0, "cmd_move_relish('old-sluice') is accepted with an ETA")
	var rel := s.view_relish()
	t.ok(rel["state"] == "travelling" and rel["target"] == "old-sluice", "view_relish().state == travelling")
	t.ok(RelishLogic.chip_text(rel, names).begins_with("Relish · travelling → Old Sluice · 0:0"), "the chip reads the live view (%s)" % RelishLogic.chip_text(rel, names))
	var c := s.cmd_cancel_travel()
	t.ok(c["ok"], "cmd_cancel_travel works while travelling")
	var c2 := s.cmd_cancel_travel()
	t.ok(c2["ok"] or c2["reason"] == "not_travelling", "a second cancel is a no-op or says why")
	for i in 40:
		s.tick(0.5)
	rel = s.view_relish()
	t.ok(rel["state"] == "home", "after the cancel she walks home (%s)" % rel["state"])
	var nc := s.cmd_cancel_travel()
	t.ok(not nc["ok"] and nc["reason"] == "not_travelling", "cancel at home: not_travelling")
	t.ok(RelishLogic.reason_text(nc["reason"]) == "Relish isn't travelling", "worded")
	var d0: Dictionary = s.view_realm()["forts"].filter(func(f): return f["id"] == "old-sluice")[0]
	t.ok(not d0["can_descend"] and d0["reason"] == "not_at_fort", "the card's DESCEND is disabled at home with not_at_fort")
	s.cmd_move_relish("old-sluice")
	for i in 40:
		s.tick(0.5)
	rel = s.view_relish()
	t.ok(rel["state"] == "at_fort" and rel["at"] == "old-sluice", "she arrives at the fort")
	var d1: Dictionary = s.view_realm()["forts"].filter(func(f): return f["id"] == "old-sluice")[0]
	t.ok(d1["can_descend"], "DESCEND is enabled once she has arrived")
	var acts := RelishLogic.fort_actions(d1, rel, s.view_town()["haul"], names, CM)
	t.ok(_acts(acts) == ["descend", "haul"] and acts.filter(func(i): return i["act"] == "descend")[0]["enabled"], "the card's actions reflect it")
	t.ok(s.cmd_move_relish("covington")["ok"], "GO HOME is cmd_move_relish('covington')")
	t.ok(s.view_relish()["target"] == "covington", "and she heads there")
	t.ok(not s.cmd_move_relish("nowhere")["ok"], "an unknown node is refused")
	# haul
	var h := s.cmd_set_haul_target("ashgate")
	t.ok(h["ok"] and s.view_town()["haul"]["target"] == "ashgate", "cmd_set_haul_target('ashgate') shows in view_town().haul.target")
	t.ok(RelishLogic.haul_line(s.view_town()["haul"], names) == "Haul: Ashgate (set)", "the haul line")
	t.ok(s.cmd_set_haul_target("auto")["ok"] and s.view_town()["haul"]["target"] == "auto", "BACK TO AUTO is cmd_set_haul_target('auto')")
	t.ok(RelishLogic.haul_line(s.view_town()["haul"], names).ends_with("(auto)"), "and reads (auto)")
	t.ok(not s.cmd_set_haul_target("nowhere")["ok"], "an unknown fort is refused")
	# the view's own lane why (E2a), through the model, end to end
	var s2 := GameState.new(TestUtil.configs())
	s2.debug_enabled = true
	s2.cmd_debug_load_fixture("day1")
	var model := MapModel.new(s2)
	model.refresh(true)
	s2.cmd_move_relish("old-sluice")
	for i in 40:
		s2.tick(0.5)
		if str(s2.view_relish()["state"]) == "at_fort":
			break
	model.refresh(true)
	var here: Array = model.lanes.filter(func(l): return l["id"] == "war:covington:old-sluice")
	t.ok(here.size() == 1 and here[0]["why"] == "Relish here", "the model's lanes carry the view's 'Relish here' at the fort she reached")
	var other_fort := str(s2.view_realm()["forts"].filter(func(f): return f["id"] != "old-sluice")[0]["id"])
	s2.cmd_move_relish(other_fort)
	s2.tick(0.5)
	model.refresh(true)
	var left: Array = model.lanes.filter(func(l): return l["id"] == "war:covington:old-sluice")
	t.ok(left.size() == 1 and left[0]["why"] == "Relish left", "and the view's 'Relish left' once she sets off")


func _steps(t: TestUtil) -> void:
	t.suite("map_controls-steps")
	var st := MapLogic.parse_steps("100,200;w60;300,400>320,420; bad ;w;x,y;500,600")
	t.ok(st.size() == 4, "four valid steps (%d)" % st.size())
	t.ok(st[0] == {"kind": "click", "pos": Vector2(100, 200)}, "a click")
	t.ok(st[1] == {"kind": "wait", "frames": 60}, "a wait token wN")
	t.ok(st[2] == {"kind": "drag", "from": Vector2(300, 400), "to": Vector2(320, 420), "hold": false}, "a drag x,y>x,y releases")
	var held := MapLogic.parse_steps("1,2>>3,4")
	t.ok(held.size() == 1 and held[0]["hold"] == true and held[0]["to"] == Vector2(3, 4), "x,y>>x,y keeps the button down")
	t.ok(st[3] == {"kind": "click", "pos": Vector2(500, 600)}, "the last click")
	t.ok(MapLogic.parse_steps("").is_empty(), "empty spec: no steps")
	t.ok(MapLogic.parse_clicks("100,200;w60;300,400").size() == 2, "parse_clicks still skips wait tokens")


func _sources(t: TestUtil) -> void:
	t.suite("map_controls-sources")
	var files: Array[String] = []
	for f in DirAccess.get_files_at(MAP_DIR):
		if f.ends_with(".gd"):
			files.append("%s/%s" % [MAP_DIR, f])
	files.append("res://scripts/main.gd")
	var emits := 0
	var lines := 0
	for p in files:
		var n := 0
		for line in FileAccess.get_file_as_string(p).split("\n"):
			n += 1
			lines += 1
			var code := line.split("#")[0]
			if code.contains("legacy_teleport_relish") or line.contains("legacy_teleport_relish"):
				t.ok(false, "%s:%d names legacy_teleport_relish" % [p, n])
			if code.contains("finished.emit("):
				emits += 1
				if not line.contains("\"v\""):
					t.ok(false, "%s:%d emits a result without \"v\": %s" % [p, n, line.strip_edges()])
			if p != "res://scripts/main.gd" and code.contains("\"teleport_to\"") and not line.contains("\"v\""):
				t.ok(false, "%s:%d builds a teleport result without \"v\": %s" % [p, n, line.strip_edges()])
	t.ok(emits >= 1, "found %d finished.emit() calls in %d map and router lines" % [emits, lines])
	if t.failures == 0:
		t.ok(true, "no legacy_teleport_relish and no un-versioned result in the map or the router")
	var main := FileAccess.get_file_as_string("res://scripts/main.gd")
	t.ok(not main.contains("legacy_teleport_relish"), "main.gd does not call it")
	var map_branch := main.substr(main.find("\t\tMAP:"), main.find("\t\tTOWN:") - main.find("\t\tMAP:"))
	t.ok(not map_branch.contains("legacy"), "the router's MAP branch has no legacy path")
	# time controls are debug-only (IDLE I9): no other map control touches the clock
	var all := ""
	for p in files:
		if p.begins_with(MAP_DIR):
			all += FileAccess.get_file_as_string(p)
	t.ok(not all.contains("cmd_set_time_scale") and not all.contains("cmd_pause"), "no map control calls cmd_set_time_scale or cmd_pause")
	var hud := FileAccess.get_file_as_string("%s/map_hud.gd" % MAP_DIR)
	t.ok(hud.contains("if not HudLogic.speed_row_shown(model.state):") and hud.contains("cmd_debug_set_state"), "the speed row is built only in a debug session and goes through cmd_debug_set_state")
	t.ok(not all.contains("TELEPORT\""), "no TELEPORT button")
	# the new scripts keep the visual law
	var banned := RegEx.new()
	banned.compile("\\bsin\\(|Time\\.get_ticks|1\\.714|Color\\(")
	for f in NEW_FILES:
		var p := "%s/%s" % [MAP_DIR, f]
		if not FileAccess.file_exists(p):
			t.ok(false, "%s exists" % f)
			continue
		var n := 0
		for line in FileAccess.get_file_as_string(p).split("\n"):
			n += 1
			if banned.search(line.split("#")[0]) != null and not line.contains("lint-ok"):
				t.ok(false, "%s:%d: a colour literal, sin() or a wall clock: %s" % [f, n, line.strip_edges()])
