extends RefCounted
## Tests for scripts/map/map_logic.gd: lane geometry, the type law's formatters, zoom tiers,
## contrast, the alpha floor, the lane adapter and demo lanes, plus source lints over the
## map scripts (no colour literals, no legacy Game access).

const PULSE := preload("res://autoload/pulse.gd")
const LINT := preload("res://tests/test_lint.gd")
const MAP_DIR := "res://scripts/map"
const GROUND_FILES := ["map_field_view.gd", "flow_ground.gd", "ground_meter.gd"]
const LANE_KEYS := ["id", "from", "to", "kind", "rate", "bias", "why"]


func run() -> int:
	var t := TestUtil.new()
	Palette.configure(TestUtil.load_json("res://configs/palette.json"))
	MapLogic.configure(TestUtil.load_json("res://configs/map_view.json"))
	_curves(t)
	_gutter(t)
	_format(t)
	_zoom(t)
	_clicks(t)
	_contrast(t)
	_adapter(t)
	_demo(t)
	_lint(t)
	return t.failures


func _finite(v: Vector2) -> bool:
	return is_finite(v.x) and is_finite(v.y)


func _curves(t: TestUtil) -> void:
	t.suite("map_logic")
	var bow: float = MapLogic.cfg()["lane_bow"]
	t.near(bow, 0.17, 1e-6, "lane_bow is 0.17")
	var a := Vector2(100, 400)
	var b := Vector2(500, 400)
	var c: Dictionary = MapLogic.lane_curve(a, b, 0.5)
	t.ok(c["a"] == a and c["b"] == b and not c["loop"], "endpoints exact, not a loop")
	# heading east, left of travel is up the screen (negative y)
	var expect := Vector2(300, 400 - 400.0 * bow)
	t.ok((c["c"] as Vector2).is_equal_approx(expect), "control point is lane_bow x chord left of the midpoint (%s)" % str(c["c"]))
	var back: Dictionary = MapLogic.lane_curve(b, a, 0.5)
	t.ok((back["c"] as Vector2).is_equal_approx(Vector2(300, 400 + 400.0 * bow)), "swapping ends bows to the other side")
	# diagonal: matches the old map_routes convention c = mid - perp * L * bow
	var p := Vector2(10, 20)
	var q := Vector2(310, 420)
	var dir := (q - p).normalized()
	var perp := Vector2(-dir.y, dir.x)
	var cd: Dictionary = MapLogic.lane_curve(p, q, 0.0)
	t.ok((cd["c"] as Vector2).is_equal_approx((p + q) * 0.5 - perp * p.distance_to(q) * bow), "same sign convention as the old routes")
	t.near(MapLogic.lane_curve(a, b, 0.0)["half_width"], 0.55, 1e-5, "half width at u=0 is 1.1/2")
	t.near(MapLogic.lane_curve(a, b, 0.5)["half_width"], 1.2, 1e-5, "half width at u=0.5 is (1.1+1.3)/2")
	t.near(MapLogic.lane_curve(a, b, 1.0)["half_width"], 1.85, 1e-5, "half width at u=1 is (1.1+2.6)/2")
	t.near(MapLogic.lane_curve(a, b, -1.0)["half_width"], 0.55, 1e-5, "u < 0 (off) uses the u=0 width")
	t.near(MapLogic.lane_curve(a, b, 7.0)["half_width"], 1.85, 1e-5, "u above 1 clamps")
	var loop: Dictionary = MapLogic.lane_curve(a, a, 0.5)
	t.ok(loop["loop"] and loop["a"] == a and loop["b"] == a and loop["c"] == a, "self-loop collapses to the node")
	t.ok(_finite(loop["a"]) and _finite(loop["c"]) and _finite(loop["b"]) and is_finite(loop["half_width"]), "self-loop is finite")
	var near_loop: Dictionary = MapLogic.lane_curve(a, a + Vector2(0.5, 0), 0.5)
	t.ok(near_loop["loop"] and _finite(near_loop["c"]), "a sub-pixel chord counts as a loop")

	var pts := MapLogic.sample_quad(a, c["c"], b, 10)
	t.ok(pts.size() == 11 and pts[0] == a and pts[10].is_equal_approx(b), "sample_quad returns n+1 points, endpoints exact")
	t.ok(pts[5].is_equal_approx(Vector2(300, 400 - 400.0 * bow * 0.5)), "midpoint of the quad is halfway to the control point")
	t.ok(MapLogic.curve_length(pts) > 400.0, "a bowed curve is longer than its chord")
	t.near(MapLogic.curve_length(MapLogic.sample_quad(a, a, a, 5)), 0.0, 1e-6, "a loop has zero length")


func _gutter(t: TestUtil) -> void:
	t.suite("map_logic-gutter")
	var cfg := MapLogic.cfg()
	var a := Vector2(100, 400)
	var b := Vector2(500, 400)
	var host: Dictionary = MapLogic.lane_curve(a, b, 0.5)
	var g: Dictionary = MapLogic.gutter_curve(a, b, 0.5, 0.25)
	var gw: float = cfg["gutter_width_base"] + cfg["gutter_width_per_u"] * 0.25
	t.near(g["half_width"], gw * 0.5, 1e-5, "gutter half width is half its width")
	var want: float = host["half_width"] + gw * 0.5 + float(cfg["gutter_offset_px"])
	t.near(((g["a"] as Vector2) - (host["a"] as Vector2)).length(), want, 1e-4, "offset = host half + gutter/2 + gutter_offset_px")
	t.ok((g["a"] as Vector2).is_equal_approx(host["a"] + Vector2(0, -want)), "shifted to the bow side (left of travel)")
	t.ok(((g["c"] as Vector2) - (host["c"] as Vector2)).is_equal_approx(Vector2(0, -want)), "all three points shift together")
	t.ok(((g["b"] as Vector2) - (host["b"] as Vector2)).is_equal_approx(Vector2(0, -want)), "end point shifts too")
	var ph: Dictionary = MapLogic.gutter_curve(a, b, -1.0, 0.25)
	var h0: Dictionary = MapLogic.lane_curve(a, b, 0.0)
	var want0: float = h0["half_width"] + gw * 0.5 + float(cfg["gutter_offset_px"])
	t.near(((ph["a"] as Vector2) - (h0["a"] as Vector2)).length(), want0, 1e-4, "phantom host (u < 0) uses the u=0 host width")
	var gl: Dictionary = MapLogic.gutter_curve(a, a, 0.5, 0.5)
	t.ok(gl["loop"] and _finite(gl["c"]), "gutter of a self-loop is a finite loop")
	t.near(MapLogic.gutter_curve(a, b, 0.5, -1.0)["half_width"], float(cfg["gutter_width_base"]) * 0.5, 1e-5, "an off dead lane uses the base gutter width")


func _format(t: TestUtil) -> void:
	t.suite("map_logic-format")
	t.ok(MapLogic.fmt_rate(4.2) == "+4.2/s", "positive rate is signed: %s" % MapLogic.fmt_rate(4.2))
	t.ok(MapLogic.fmt_rate(-0.3) == "−0.3/s", "negative rate uses U+2212: %s" % MapLogic.fmt_rate(-0.3))
	t.ok(MapLogic.fmt_rate(0.0) == "+0.0/s", "zero is +0.0/s")
	t.ok(MapLogic.fmt_rate(-0.0) == "+0.0/s", "negative zero is +0.0/s")
	t.ok(MapLogic.fmt_rate(0.05) == "+0.05/s", "two decimals below 0.1: %s" % MapLogic.fmt_rate(0.05))
	t.ok(MapLogic.fmt_rate(-0.05) == "−0.05/s", "negative below 0.1")
	t.ok(MapLogic.fmt_rate(25.0) == "+25.0/s", "25 is +25.0/s")
	t.ok(MapLogic.fmt_rate(1.5, "/min") == "+1.5/min", "unit is a parameter")
	t.ok(MapLogic.fmt_mass(18450.0) == "18,450", "mass has thousands separators")
	t.ok(MapLogic.fmt_mass(0.0) == "0" and MapLogic.fmt_mass(999.4) == "999", "small masses")
	t.ok(MapLogic.fmt_mass(1234567.0) == "1,234,567", "two separators")
	t.ok(MapLogic.fmt_mass(-5.0) == "0", "mass is unsigned")
	t.ok(MapLogic.fmt_drain(-1.0) == "∞", "holding drains in infinity")
	t.ok(MapLogic.fmt_drain(45.0) == "45s", "45s")
	t.ok(MapLogic.fmt_drain(750.0) == "12m 30s", "12m 30s")
	t.ok(MapLogic.fmt_drain(3840.0) == "1h 04m", "1h 04m")
	t.ok(MapLogic.fmt_drain(0.0) == "0s", "0s")
	t.ok(MapLogic.sign_glyph(1) == "▲" and MapLogic.sign_glyph(-1) == "▼", "sign glyphs")
	t.ok(MapLogic.sign_glyph(0) == "holding", "zero is holding")


func _zoom(t: TestUtil) -> void:
	t.suite("map_logic-zoom")
	t.ok(MapLogic.zoom_tier(0.3, "") == "far" and MapLogic.zoom_tier(0.59, "") == "far", "far below 0.6")
	t.ok(MapLogic.zoom_tier(0.61, "") == "mid" and MapLogic.zoom_tier(1.6, "") == "mid", "mid between")
	t.ok(MapLogic.zoom_tier(1.61, "") == "near" and MapLogic.zoom_tier(3.0, "") == "near", "near above 1.6")
	t.ok(MapLogic.zoom_tier(0.61, "mid") == "mid", "0.61 stays mid from mid")
	t.ok(MapLogic.zoom_tier(0.61, "far") == "far", "0.61 stays far from far")
	t.ok(MapLogic.zoom_tier(0.649, "far") == "far", "far holds until 0.6 + hysteresis")
	t.ok(MapLogic.zoom_tier(0.66, "far") == "mid", "far leaves past 0.65")
	t.ok(MapLogic.zoom_tier(0.57, "mid") == "mid", "mid holds down to 0.6 - hysteresis")
	t.ok(MapLogic.zoom_tier(0.54, "mid") == "far", "mid leaves below 0.55")
	t.ok(MapLogic.zoom_tier(1.64, "mid") == "mid" and MapLogic.zoom_tier(1.66, "mid") == "near", "mid leaves for near past 1.65")
	t.ok(MapLogic.zoom_tier(1.58, "near") == "near" and MapLogic.zoom_tier(1.54, "near") == "mid", "near holds down to 1.55")
	t.ok(MapLogic.zoom_tier(3.0, "far") == "near", "a jump skips the middle tier")


func _clicks(t: TestUtil) -> void:
	t.suite("map_logic-clicks")
	var c := MapLogic.parse_clicks("1042,807;300, 400.5")
	t.ok(c.size() == 2 and c[0] == Vector2(1042, 807) and c[1] == Vector2(300, 400.5), "--map-clicks parses x,y pairs")
	t.ok(MapLogic.parse_clicks("").is_empty() and MapLogic.parse_clicks("12;a,b;1,2,3").is_empty(), "malformed pairs are skipped")
	var wm := FileAccess.get_file_as_string("res://scripts/map/world_map.gd")
	t.ok(wm.contains("func _unhandled_input(") and not wm.contains("func _gui_input(") and wm.contains("MOUSE_FILTER_IGNORE"), "map input is unhandled (screen) input and the root takes none")
	t.ok(wm.contains("debug_enabled") and wm.contains("Input.parse_input_event"), "the click replay is debug-only and uses the real input path")


func _contrast(t: TestUtil) -> void:
	t.suite("map_logic-contrast")
	t.near(MapLogic.contrast_ratio(Color.WHITE, Color.BLACK), 21.0, 0.01, "white on black is 21:1")
	t.near(MapLogic.contrast_ratio(Color.WHITE, Color.WHITE), 1.0, 1e-6, "same colour is 1:1")
	t.near(MapLogic.contrast_ratio(Color(1, 1, 1, 0.0), Color.BLACK), 1.0, 1e-6, "an invisible fg is the ground")
	var ground := Palette.c("ground")
	var dead := MapLogic.contrast_ratio(Palette.c("dead"), ground)
	t.ok(dead >= 3.0 and dead < 4.5, "canon dead is ~3.9:1 on the ground (%.2f)" % dead)
	# the alpha floor, measured against the stroke the lane shader draws as its core: the pale
	# core (undead_core / living_core) at the lane's alpha. Both clear 3:1 at the floor, the
	# binding one (living) fails just below it, and the floor never lifts Pulse's u=0 alpha, so
	# alpha keeps its u-dependence (0.4 + 0.6u).
	var p: Node = PULSE.new()
	p.configure(TestUtil.load_json("res://configs/pulse.json"))
	var floor_a: float = MapLogic.cfg()["lane_alpha_floor"]
	var worst_below := INF
	for key in ["undead_core", "living_core"]:
		var at_floor := MapLogic.contrast_ratio(Palette.c(key, floor_a), ground)
		t.ok(at_floor >= 3.0, "%s at the alpha floor reaches 3:1 (%.2f)" % [key, at_floor])
		worst_below = minf(worst_below, MapLogic.contrast_ratio(Palette.c(key, floor_a - 0.01), ground))
	t.ok(worst_below < 3.0, "the floor is the smallest: 0.01 less fails for the dimmest core (%.2f)" % worst_below)
	t.ok(floor_a <= float(p.channels(0.0, Palette.hue("undead"))["alpha"]) + 1e-6, "the floor does not lift Pulse's u=0 alpha (%.2f)" % floor_a)
	p.free()


func _row_ok(r: Dictionary) -> bool:
	if r.size() != LANE_KEYS.size() or not LANE_KEYS.all(func(k): return r.has(k)):
		return false
	return r["id"] is String and r["from"] is String and r["to"] is String and r["kind"] is String \
		and r["rate"] is float and r["bias"] is float and r["why"] is String \
		and GameState.LANE_KINDS.has(r["kind"]) \
		and r["id"] == "%s:%s:%s" % [r["kind"], r["from"], r["to"]]


func _forts() -> Array:
	return [{"id": "ashgate", "ship_in": 0.3}, {"id": "old-sluice", "ship_in": 0.0}, {"id": "greywall", "ship_in": 1.2}]


func _adapter(t: TestUtil) -> void:
	t.suite("map_logic-adapter")
	var view := [
		{"id": "war:covington:ashgate", "from": "covington", "to": "ashgate", "kind": "war", "rate": 1.5, "bias": 3.0, "why": "Relish here"},
		{"id": "flood:covington:vei", "from": "covington", "to": "vei", "kind": "flood", "rate": 0.0, "bias": 1.0, "why": ""},
	]
	var hud := {"split": {"work": 1.0, "war": 2.0, "flood": 1.92}}
	var out := MapLogic.lanes_from_views(view, _forts(), hud)
	var by := {}
	for r in out:
		by[r["id"]] = r
	t.ok(out.size() == by.size(), "ids are unique")
	t.ok(by["war:covington:ashgate"]["rate"] == 1.5 and by["war:covington:ashgate"]["bias"] == 3.0 and by["war:covington:ashgate"]["why"] == "Relish here", "view rows pass through")
	t.ok(by.has("living:vei:ashgate") and by.has("living:vei:old-sluice") and by.has("living:vei:greywall"), "a living row per fort")
	t.near(by["living:vei:greywall"]["rate"], 1.2, 1e-6, "living rate is the fort's ship_in")
	t.ok(by["living:vei:ashgate"]["from"] == "vei" and by["living:vei:ashgate"]["to"] == "ashgate", "living runs vei -> fort")
	t.near(by["flood:covington:vei"]["rate"], 1.92, 1e-6, "a 0 cov->vei flood takes the split rate")
	t.ok(out.size() == 2 + 3, "nothing else is invented (%d rows)" % out.size())
	t.ok(out.all(func(r): return _row_ok(r)), "every row has the lane shape")
	view[1]["rate"] = 4.0
	out = MapLogic.lanes_from_views(view, _forts(), hud)
	t.near(out[1]["rate"], 4.0, 1e-6, "a nonzero view flood rate is kept")
	hud["split"]["flood"] = 0.0
	view[1]["rate"] = 0.0
	out = MapLogic.lanes_from_views(view, _forts(), hud)
	t.near(out[1]["rate"], 0.0, 1e-6, "no split flood leaves the 0 alone")
	# an E2 view that already carries a living row: no stand-in for it
	view.append({"id": "living:vei:ashgate", "from": "vei", "to": "ashgate", "kind": "living", "rate": 9.0, "bias": 1.0, "why": ""})
	out = MapLogic.lanes_from_views(view, _forts(), hud)
	var count := 0
	for r in out:
		if r["id"] == "living:vei:ashgate":
			count += 1
			t.near(r["rate"], 9.0, 1e-6, "the view's living rate wins over ship_in")
	t.ok(count == 1, "the stand-in is not duplicated")
	t.ok(out.size() == 2 + 1 + 2, "the other two forts still get stand-ins")
	var none := MapLogic.lanes_from_views([], [], {})
	t.ok(none.size() == 1 and none[0]["id"] == "flood:covington:vei", "empty inputs give just the flood lane")


func _demo(t: TestUtil) -> void:
	t.suite("map_logic-demo")
	var forts: Array = []
	for f in TestUtil.load_json("res://configs/world.json")["forts"]:
		forts.append({"id": f["id"], "ship_in": 0.0})
	var rows := MapLogic.demo_lanes(forts)
	t.ok(rows.size() > 0 and rows.all(func(r): return _row_ok(r)), "demo rows have the exact lane shape")
	var kinds := {}
	var ids := {}
	var by := {}
	for r in rows:
		kinds[r["kind"]] = true
		ids[r["id"]] = true
		by[r["id"]] = r
	t.ok(GameState.LANE_KINDS.all(func(k): return kinds.has(k)), "every LANE_KINDS kind appears")
	t.ok(ids.size() == rows.size(), "demo ids are unique")
	t.ok(by.has("flood:covington:vei"), "a cov->vei flood")
	var phantom := false
	for r in rows:
		if r["kind"] == "dead" and r["rate"] > 0.0:
			var fid: String = r["from"]
			if by.has("flood:%s:vei" % fid) and by["flood:%s:vei" % fid]["rate"] == 0.0:
				phantom = true
	t.ok(phantom, "a fort has dead on and its fort->vei flood off (phantom bank)")
	var fort_flood := rows.filter(func(r): return r["kind"] == "flood" and r["from"] != "covington" and r["rate"] > 0.0)
	t.ok(fort_flood.size() > 0, "other fort->vei floods are on")
	var self_loops := rows.filter(func(r): return r["from"] == r["to"])
	t.ok(self_loops.size() == 2, "a work and a redirect self-loop")
	t.ok(rows.any(func(r): return r["kind"] == "haul" and r["to"] == "covington"), "haul runs fort->covington")
	var lo := 1e9
	var hi := 0.0
	for r in rows:
		if r["rate"] > 0.0:
			lo = minf(lo, r["rate"])
			hi = maxf(hi, r["rate"])
	t.ok(lo > 0.06 and lo < 0.1, "lowest on-rate is just above rate_off (%.3f)" % lo)
	t.ok(hi > 20.0 and hi <= 26.0, "highest rate is ~25 (%.1f)" % hi)
	t.ok(rows.filter(func(r): return r["why"] != "").size() >= 2, "a couple of rows carry a why")
	t.ok(rows.filter(func(r): return r["bias"] > 1.0).size() == 1, "one row has bias > 1")
	t.ok(MapLogic.demo_lanes(forts) == rows, "deterministic")
	t.ok(MapLogic.demo_lanes([]).is_empty(), "no forts, no rows")
	var few := MapLogic.demo_lanes([{"id": "a"}])
	t.ok(few.all(func(r): return _row_ok(r)), "a single fort still gives valid rows")


func _lint(t: TestUtil) -> void:
	t.suite("map_logic-lint")
	var lit := RegEx.new()
	lit.compile("Color\\s*\\(\\s*[\"\\d]")
	var legacy := RegEx.new()
	legacy.compile("Game\\.(realm|field|towns|res|army|town|assignments|idle_undead|gather|quality|raiding_fort_id|time_scale|won|green_towns|stats|relish_respawned|victory|defeat_boss)\\b")
	var files := 0
	for f in DirAccess.get_files_at(MAP_DIR):
		if not f.ends_with(".gd") or GROUND_FILES.has(f):
			continue
		files += 1
		var n := 0
		for line in FileAccess.get_file_as_string("%s/%s" % [MAP_DIR, f]).split("\n"):
			n += 1
			var code: String = LINT.strip_comment(line)
			if lit.search(code) != null or code.contains("Color.html(") or code.contains("Color8("):
				t.ok(false, "%s:%d colour literal: %s" % [f, n, line.strip_edges()])
			if legacy.search(code) != null or code.contains("realm.readout") or code.contains("r_drain") \
					or code.contains("r_dead_out") or code.contains("r_shipped") or code.contains("Game.realm"):
				t.ok(false, "%s:%d legacy access: %s" % [f, n, line.strip_edges()])
	t.ok(files >= 5, "linted %d map scripts" % files)
	if t.failures == 0:
		t.ok(true, "no colour literals or legacy Game access in the map scripts")
	# detector self-check
	t.ok(lit.search("Color(\"39ff9e\")") != null and lit.search("Color(0.1, 0.2, 0.3)") != null, "detector flags literals")
	t.ok(lit.search("Color(col, 0.5)") == null, "detector ignores re-alpha of a variable")
	t.ok(legacy.search("Game.town[\"x\"]") != null and legacy.search("Game.state.view_hud()") == null, "legacy detector")
