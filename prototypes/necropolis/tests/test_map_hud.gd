extends RefCounted
## Tests for the type law (scripts/map/map_type.gd) and the HUD's pure logic
## (scripts/map/hud_logic.gd): the top-bar items, the status block, the lane callout text,
## their greedy non-overlapping placement and the count cap.


func run() -> int:
	var t := TestUtil.new()
	Palette.configure(TestUtil.load_json("res://configs/palette.json"))
	MapLogic.configure(TestUtil.load_json("res://configs/map_view.json"))
	_type(t)
	_contrast(t)
	_bar(t)
	_status(t)
	_callout_text(t)
	_callout_rows(t)
	_placement(t)
	_drag_cap(t)
	_rects_key(t)
	_one_source(t)
	_fit(t)
	_wrap(t)
	return t.failures


func _type(t: TestUtil) -> void:
	t.suite("map_hud-type")
	var want := tan(deg_to_rad(9.0))
	var rf := MapType.rate_font()
	var mf := MapType.mass_font()
	var lf := MapType.label_font()
	var tf := MapType.title_font()
	t.near(rf.variation_transform.y.x, want, 1e-4, "rate font is skewed 9 degrees")
	t.near(rf.variation_transform.x.y, 0.0, 1e-6, "the skew only shears")
	t.ok(rf.variation_embolden < 0.0, "rate font is lighter")
	t.near(mf.variation_transform.y.x, 0.0, 1e-6, "mass font is upright")
	t.ok(mf.variation_embolden > 0.0, "mass font is heavier")
	t.ok(mf.variation_embolden > lf.variation_embolden and lf.variation_embolden > rf.variation_embolden, "weights run rate < label < mass")
	t.near(lf.variation_transform.y.x, 0.0, 1e-6, "label font is upright")
	t.near(tf.variation_transform.y.x, 0.0, 1e-6, "title font is upright")
	t.ok(MapType.rate_font() == rf and MapType.mass_font() == mf, "fonts are cached")
	for key in ["size_rate", "size_mass", "size_label", "size_title", "size_stock"]:
		t.ok(MapType.size_of(key) >= 12, "%s is at least 12 px" % key)
	t.ok(int(MapLogic.cfg()["callouts"]["size_px"]) >= 12, "callout text is at least 12 px")
	t.ok(int(MapLogic.cfg()["objective_size_px"]) >= 12, "objective strip is at least 12 px")
	var l := Label.new()
	MapType.style_rate(l)
	t.ok(l.get_theme_font("font") == rf and l.get_theme_font_size("font_size") == MapType.size_of("size_rate"), "style_rate sets the rate font and size")
	MapType.style_mass(l, "text_dim", 13)
	t.ok(l.get_theme_font("font") == mf and l.get_theme_font_size("font_size") == 13, "style_mass takes a size override")
	t.ok(l.get_theme_color("font_color").is_equal_approx(Palette.c("text_dim")), "style_mass takes a palette key")
	MapType.style_label(l)
	t.ok(l.get_theme_font("font") == lf, "style_label sets the label font")
	l.free()


func _contrast(t: TestUtil) -> void:
	t.suite("map_hud-contrast")
	var cfg := MapLogic.cfg()
	var panel := Palette.c("ground").lightened(float(cfg["panel_bg_lighten"]))
	var grounds := {"ground": Palette.c("ground"), "panel": panel}
	# the HUD plate: ground at topbar_plate_alpha, with the brightest map content (vei) showing
	# through at 1 - alpha
	var a := float(cfg["topbar_plate_alpha"])
	var bright_key := ""
	for k in Palette.keys():
		if bright_key == "" or MapLogic.luminance(Palette.c(k)) > MapLogic.luminance(Palette.c(bright_key)):
			bright_key = k
	var through := Palette.c("ground").lerp(Palette.c(bright_key), 1.0 - a)
	for key in ["text", "text_dim", "undead", "danger", "select"]:
		var r := MapLogic.contrast_ratio(Palette.c(key), through)
		t.ok(r >= 4.5, "%s on the top-bar plate over the brightest palette key (%s) is %.1f:1 (>= 4.5)" % [key, bright_key, r])
	t.ok(a > 0.0 and a <= 1.0, "plate alpha in range")
	for key in ["text", "text_dim", "undead", "danger", "select"]:
		for g in grounds:
			var r := MapLogic.contrast_ratio(Palette.c(key), grounds[g])
			t.ok(r >= 4.5, "%s on %s is %.1f:1 (>= 4.5)" % [key, g, r])


func _hud(rates: Array, extra := {}) -> Dictionary:
	var d := {"rates": rates, "odds": 0.0, "sign": 0, "drain_s": -1.0, "time_scale": 1.0, "won": false}
	d.merge(extra, true)
	return d


func _rate(id: String, rate: float, stock: float, cap := -1.0) -> Dictionary:
	return {"id": id, "rate": rate, "stock": stock, "cap": cap, "unit": "x/s"}


func _bar(t: TestUtil) -> void:
	t.suite("map_hud-bar")
	var rates: Array = []
	for id in GameState.HUD_RATE_IDS:
		rates.append(_rate(id, 0.0, -1.0 if id == "mint" else 10.0))
	var items := HudLogic.rate_items(_hud(rates))
	t.ok(items.size() == GameState.HUD_RATE_IDS.size(), "one item per stream")
	var ids: Array = items.map(func(i): return i["id"])
	t.ok(ids == Array(GameState.HUD_RATE_IDS), "items follow HUD_RATE_IDS order")
	t.ok(items.all(func(i): return str(i["rate_text"]).ends_with("/s")), "every rate ends in /s")
	t.ok(items.all(func(i): return str(i["rate_text"]) == "+0.0/s"), "E1: every rate reads +0.0/s")
	t.ok(items[0]["stock_text"] == "", "mint has no stock")
	t.ok(items[1]["stock_text"] == "10", "a stock reads as a mass")
	t.ok(items.all(func(i): return not i["capped"] and i["cap_mark"] == ""), "no cap marker below cap")
	var sw := HudLogic.rate_items(_hud([_rate("workers", -2.34, 1234.0), _rate("bodies", 0.05, 40.0, 200.0)]))
	t.ok(sw[0]["rate_text"] == "−2.3/s", "a negative net uses the minus sign (%s)" % sw[0]["rate_text"])
	t.ok(sw[0]["stock_text"] == "1,234", "stock has thousands separators")
	t.ok(sw[1]["rate_text"] == "+0.05/s", "a faint rate gets two decimals")
	t.ok(sw[1]["stock_text"] == "40/200" and not sw[1]["capped"], "a capped stream shows /cap, no marker under it")
	var full := HudLogic.rate_items(_hud([_rate("living", 0.0, 16.0, 16.0), _rate("bodies", 0.0, 250.0, 200.0), _rate("gold", 0.0, 99999.0, -1.0)]))
	t.ok(full[0]["capped"] and full[0]["cap_mark"] != "", "at cap: marker")
	t.ok(full[1]["capped"], "over cap counts as at cap")
	t.ok(not full[2]["capped"] and full[2]["stock_text"] == "99,999", "uncapped never marks")
	t.ok(HudLogic.rate_items({}).is_empty(), "no rates, no items")


func _status(t: TestUtil) -> void:
	var gap := float(MapLogic.cfg()["toast_gap_px"])
	t.ok(HudLogic.toast_top(200.0, 90.0, gap) == 200.0 + gap, "the toast sits a gap under a two-row bar's chip, below its bottom edge")
	t.ok(HudLogic.toast_top(130.0, 90.0, gap) >= 130.0 + gap and HudLogic.toast_top(0.0, 90.0, gap) == 90.0 + gap, "one row: under the chip; no chip yet: under the inset")
	t.ok(not MapLogic.cfg().has("toast_top_px"), "the fixed toast_top_px is gone")
	t.suite("map_hud-status")
	var hold := HudLogic.status(_hud([], {"odds": 0.614, "sign": 0, "drain_s": -1.0}))
	t.ok(hold["odds_text"] == "61%", "odds are an integer percent (%s)" % hold["odds_text"])
	t.ok(hold["sign_text"] == "holding" and hold["sign"] == 0, "sign 0 reads holding")
	t.ok(hold["drain_text"] == "∞", "drain_s = -1 reads ∞")
	var up := HudLogic.status(_hud([], {"sign": 1, "drain_s": 520.0, "odds": 1.0}))
	t.ok(up["sign_text"] == "▲" and up["drain_text"] == "8m 40s" and up["odds_text"] == "100%", "up: ▲, a time, 100%")
	var down := HudLogic.status(_hud([], {"sign": -1}))
	t.ok(down["sign_text"] == "▼", "down: ▼")
	var empty := HudLogic.status({})
	t.ok(empty["odds_text"] == "0%" and empty["sign_text"] == "holding" and empty["drain_text"] == "∞", "an empty hud is safe")
	t.ok(HudLogic.speed_text(_hud([], {"time_scale": 1.0})) == "" and HudLogic.speed_text(_hud([], {"time_scale": 10.0})) == "×10", "the speed tag shows only off 1x")
	var cfg := MapLogic.cfg()
	t.ok(HudLogic.objective_text(_hud([])) == cfg["objective_text"], "the objective line")
	t.ok(HudLogic.objective_text(_hud([], {"won": true})) == cfg["objective_won_text"], "the victory line when won")
	t.ok(cfg["objective_text"] != cfg["objective_won_text"], "the two differ")


func _callout_text(t: TestUtil) -> void:
	t.suite("map_hud-callout-text")
	var names := {"covington": "Covington", "ashgate": "Ashgate", "vei": "Vei"}
	var war := {"id": "war:covington:ashgate", "from": "covington", "to": "ashgate", "kind": "war", "rate": 1.2, "bias": 1.0, "why": "Relish left"}
	t.ok(HudLogic.callout_text(war, names) == "WAR → Ashgate +1.2/s · Relish left", "callout reads like the law's example (%s)" % HudLogic.callout_text(war, names))
	var neg := war.duplicate()
	neg["rate"] = -1.2
	t.ok(HudLogic.callout_text(neg, names) == "WAR → Ashgate −1.2/s · Relish left", "negative rates use the minus sign")
	var parts := HudLogic.callout_parts(war, names)
	t.ok(parts["rate"] == "+1.2/s" and parts["head"] == "WAR → Ashgate " and parts["tail"] == " · Relish left", "parts split head, rate, tail")
	var flood := {"kind": "flood", "from": "ashgate", "to": "vei", "rate": 3.0, "why": "valve"}
	t.ok(HudLogic.callout_text(flood, names) == "FLOOD → Vei +3.0/s · valve", "kind upper-case, destination from names")
	var unknown := {"kind": "haul", "from": "x", "to": "old-sluice", "rate": 0.0, "why": "held"}
	t.ok(HudLogic.callout_text(unknown, names) == "HAUL → Old Sluice +0.0/s · held", "an unnamed id falls back to a capitalised id (%s)" % HudLogic.callout_text(unknown, names))
	var silent := war.duplicate()
	silent["why"] = ""
	t.ok(HudLogic.callout_text(silent, names) == "" and HudLogic.callout_parts(silent, names).is_empty(), "empty why: no callout")
	for kind in ["war", "flood", "dead", "living", "haul", "redirect", "work"]:
		var row := {"kind": kind, "to": "vei", "rate": 1.0, "why": "valve"}
		t.ok(HudLogic.callout_text(row, names).begins_with(kind.to_upper() + " → "), "%s is upper-case" % kind)


func _callout_rows(t: TestUtil) -> void:
	t.suite("map_hud-callout-rows")
	var rows := [
		{"id": "a", "rate": 1.0, "why": "valve"},
		{"id": "b", "rate": 9.0, "why": ""},
		{"id": "c", "rate": -5.0, "why": "held"},
		{"id": "d", "rate": 5.0, "why": "retaken"},
		{"id": "e", "rate": 0.0, "why": "staging"},
	]
	var out := HudLogic.callout_rows(rows)
	var ids: Array = out.map(func(r): return r["id"])
	t.ok(ids == ["c", "d", "a", "e"], "only rows with a why, loudest first, ties in input order (%s)" % str(ids))
	t.ok(HudLogic.callout_rows([]).is_empty(), "no rows, none")


func _drag_cap(t: TestUtil) -> void:
	t.suite("map_hud-drag-cap")
	var cfg: Dictionary = MapLogic.cfg()["callouts"]
	t.ok(HudLogic.callout_cap(false) == int(cfg["max_count"]) and int(cfg["max_count"]) == 8, "off a drag, max_count")
	t.ok(HudLogic.callout_cap(true) == 4 and int(cfg["drag_max_count"]) == 4, "during a drag, drag_max_count (4)")
	var lanes: Array = []
	for i in 7:
		lanes.append({"id": "l%d" % i, "from": "a%d" % i, "to": "b%d" % i, "kind": "war", "rate": float(i) - 3.0, "why": "valve%d" % i})
	var items := HudLogic.callout_items(lanes, 3)
	var size := Vector2(60, 20)
	var opts: Array = []
	for i in items.size():
		opts.append(HudLogic.candidate_rects(Vector2(300.0 * i, 100.0), size, Vector2(16, 26)))
	var picks := HudLogic.place(opts, HudLogic.callout_cap(true), 4.0)
	var placed := []
	for i in picks.size():
		if picks[i] >= 0:
			placed.append(str(items[i]["id"]))
	t.ok(placed.size() == 4, "seven callouts fit but a drag shows four (%d)" % placed.size())
	t.ok(placed == ["l0", "l6", "l1", "l5"], "the four with the largest |rate|: %s" % str(placed))
	var open_picks := HudLogic.place(opts, HudLogic.callout_cap(false), 4.0)
	t.ok(open_picks.filter(func(k): return k >= 0).size() == 7, "off a drag all seven place")
	var folded := HudLogic.callout_items([
		{"id": "x1", "from": "covington", "to": "a", "kind": "war", "rate": 1.0, "why": "valve"},
		{"id": "x2", "from": "covington", "to": "b", "kind": "war", "rate": 1.0, "why": "valve"},
		{"id": "x3", "from": "covington", "to": "c", "kind": "war", "rate": 1.0, "why": "valve"},
		{"id": "y", "from": "a", "to": "b", "kind": "flood", "rate": 0.5, "why": "tithe"}], 3)
	t.ok(folded.size() == 2 and bool(folded[0].get("group", false)), "collapsing still folds inside the cap")


func _rects_key(t: TestUtil) -> void:
	t.suite("map_hud-rects-key")
	var a := [Rect2(10, 20, 40, 12), Rect2(100, 100, 40, 12)]
	var b := [Rect2(10, 20, 40, 12), Rect2(100, 100, 40, 12)]
	t.ok(HudLogic.rects_key(a) == HudLogic.rects_key(b), "the same chip rects give the same key")
	var moved := [Rect2(10, 20, 40, 12), Rect2(100, 118, 40, 12)]
	t.ok(HudLogic.rects_key(a) != HudLogic.rects_key(moved), "a chip that moved gives a new key (a re-place)")
	var sub := [Rect2(10.2, 20.1, 40, 12), Rect2(100.3, 100.0, 40, 12)]
	t.ok(HudLogic.rects_key(a) == HudLogic.rects_key(sub), "a sub-pixel drift does not re-place")
	t.ok(HudLogic.rects_key([]) == [], "no chips, an empty key")


func _placement(t: TestUtil) -> void:
	t.suite("map_hud-placement")
	var size := Vector2(120, 20)
	var c := HudLogic.candidate_rects(Vector2(100, 100), size, Vector2(16, 26))
	t.ok(c.size() == 4, "four candidate rects around an anchor")
	t.ok(c.all(func(r): return r.size == size), "candidates keep the plate size")
	t.ok(c.all(func(r): return not r.has_point(Vector2(100, 100))), "no candidate covers its own anchor")
	t.ok(c[0].position.x > 100.0 and c[0].end.y < 100.0, "first candidate is up and to the right")
	var le := HudLogic.leader_end(c[0], Vector2(100, 100))
	t.ok(c[0].grow(0.01).has_point(le), "the leader ends on its plate")
	# three plates anchored at the same spot: the candidates cannot all fit
	var opts: Array = []
	for i in 6:
		opts.append(HudLogic.candidate_rects(Vector2(100, 100), size, Vector2(16, 26)))
	var picks := HudLogic.place(opts, 99, 4.0)
	t.ok(picks.size() == opts.size(), "one pick per option")
	var placed: Array[Rect2] = []
	for i in picks.size():
		if picks[i] >= 0:
			placed.append(opts[i][picks[i]])
	t.ok(placed.size() == 4, "four stacked anchors place four plates and skip two (%d)" % placed.size())
	var clash := false
	for i in placed.size():
		for j in range(i + 1, placed.size()):
			if placed[i].grow(4.0).intersects(placed[j]):
				clash = true
	t.ok(not clash, "no two placed plates intersect (gap included)")
	var capped := HudLogic.place(opts, 2, 4.0)
	t.ok(capped.count(-1) == opts.size() - 2, "the cap leaves at most 2 placed")
	t.ok(capped[0] >= 0 and capped[1] >= 0, "the cap keeps the first (loudest) ones")
	var far: Array = [[Rect2(0, 0, 10, 10)], [Rect2(500, 500, 10, 10)]]
	t.ok(HudLogic.place(far, 5, 4.0) == [0, 0], "well-separated plates all place")
	t.ok(HudLogic.place([], 5, 4.0).is_empty(), "nothing in, nothing out")


## The top bar and Vei's node read one MapModel.readout(): identical odds, sign and drain, with
## and without the --nodes=demo overlay.
func _one_source(t: TestUtil) -> void:
	t.suite("map_hud-one-source")
	var s := GameState.new(TestUtil.configs())
	s.debug_enabled = true
	s.cmd_debug_load_fixture("midgame_2flips")
	for demo in [false, true]:
		var m := MapModel.new(s)
		m.nodes_demo = demo
		m.flip_cfg = TestUtil.configs().get("realm", {}).get("flip", {})
		m.refresh(true)
		var ro := m.readout()
		var bar := HudLogic.status(m.readout())
		var vei_odds := NodeLogic.fmt_odds(float(ro["odds"]))
		var vei_sign := MapLogic.sign_glyph(int(ro["sign"]))
		var vei_drain := NodeLogic.drain_line(float(ro["backlog"]), float(ro["drain_s"]))
		var tag := "demo" if demo else "real"
		t.ok(bar["odds_text"] == vei_odds, "%s: bar odds == Vei odds (%s)" % [tag, vei_odds])
		t.ok(bar["sign_text"] == vei_sign, "%s: bar sign == Vei sign (%s)" % [tag, vei_sign])
		t.ok(ro["odds"] == m.hud["odds"] and ro["sign"] == m.hud["sign"] and ro["drain_s"] == m.hud["drain_s"], "%s: the readout is view_hud's" % tag)
		t.ok(ro["backlog"] == m.vei["backlog"], "%s: the backlog is view_vei's" % tag)
		if float(ro["backlog"]) > 0.0:
			t.ok(vei_drain == "drain " + bar["drain_text"], "%s: bar drain == Vei drain (%s)" % [tag, vei_drain])
		else:
			t.ok(bar["drain_text"] == "queue empty" and vei_drain == "queue empty", "%s: both say queue empty" % tag)
		if demo:
			var vd: Dictionary = MapLogic.cfg()["demo_nodes"]["vei"]
			t.ok(is_equal_approx(float(ro["odds"]), float(vd["odds"])) and int(ro["sign"]) == int(vd["sign"]) \
				and is_equal_approx(float(ro["drain_s"]), float(vd["drain_s"])) and is_equal_approx(float(ro["backlog"]), float(vd["backlog"])), "demo: the overlay's values come through the readout")


func _fit(t: TestUtil) -> void:
	t.suite("map_hud-fit")
	var cfg := MapLogic.cfg()
	var vp := Vector2(1600, 900)
	var inset := 70.0
	var content := Rect2(300, -40, 1500, 1400)
	var v := MapLogic.fit_view(content, vp, inset)
	var z: float = v["zoom"]
	var centre: Vector2 = v["centre"]
	# screen position of a world point: (p - centre) * z + viewport / 2
	var tl := (content.position - centre) * z + vp * 0.5
	var br := (content.end - centre) * z + vp * 0.5
	t.ok(tl.x >= 0.0 and br.x <= vp.x, "the content fits the viewport width")
	t.ok(tl.y >= inset - 1e-3 and br.y <= vp.y + 1e-3, "the content fits below the inset (top %.1f >= %.0f)" % [tl.y, inset])
	t.ok(MapLogic.fit_view(Rect2(), vp, inset).is_empty() and MapLogic.fit_view(content, vp, vp.y).is_empty(), "degenerate input fits nothing")
	var wide := MapLogic.fit_view(Rect2(0, 0, 4000, 100), vp, inset)
	t.near(float(wide["zoom"]), vp.x / 4000.0 * float(cfg["fit_margin"]), 1e-6, "a wide content is width-limited")
	var s := GameState.new(TestUtil.configs())
	s.debug_enabled = true
	s.cmd_debug_load_fixture("pre_vei")
	var m := MapModel.new(s)
	m.refresh(true)
	var rect := m.content_rect()
	t.ok(rect.size.x > 0.0 and rect.size.y > 0.0, "the model has a content rect")
	for f in m.forts:
		t.ok(rect.has_point(MapModel.to_vec(f["pos"])), "%s is inside the content" % f["id"])
	t.ok(rect.has_point(m.node_pos("covington")) and rect.has_point(m.node_pos("vei")), "Covington and Vei are inside the content")
	var reach := NodeLogic.vei_reach(float(m.realm["vei"]["radius"]), float(m.vei["backlog"]))
	t.ok(rect.position.y <= m.node_pos("vei").y - reach, "the whole Vei stack is inside the content")
	var fit := MapLogic.fit_view(rect, vp, inset)
	var tier := MapLogic.zoom_tier(float(fit["zoom"]), "mid")
	t.ok(tier == "mid", "the default fit is the mid tier (zoom %.3f)" % float(fit["zoom"]))
	t.ok(float(fit["zoom"]) >= float(cfg["zoom_far_below"]) + float(cfg["zoom_hysteresis"]), "with at least the hysteresis margin above far (%.3f >= %.2f + %.2f)" % [float(fit["zoom"]), float(cfg["zoom_far_below"]), float(cfg["zoom_hysteresis"])])
	var vtop := ((m.node_pos("vei").y - reach) - float(fit["centre"].y)) * float(fit["zoom"]) + vp.y * 0.5
	t.ok(vtop >= inset, "Vei's stack starts below the HUD (%.1f >= %.0f)" % [vtop, inset])


func _wrap(t: TestUtil) -> void:
	t.suite("map_hud-wrap")
	var cfg := MapLogic.cfg()
	var gap := float(cfg["topbar_gap_px"])
	var max_w := float(cfg["topbar_max_w_px"])
	var widths := [150, 190, 140, 170, 130, 180, 260, 220, 90]
	var rows := HudLogic.wrap_rows(widths, gap, max_w)
	var flat: Array = []
	for r in rows:
		flat.append_array(r)
	t.ok(flat == range(widths.size()), "every item appears once, in order")
	t.ok(rows.size() > 1, "these widths wrap (%d rows)" % rows.size())
	for r in rows:
		var w: float = gap * (r.size() - 1)
		for i in r:
			w += float(widths[i])
		t.ok(w <= max_w, "a row of %d items is %.0f px (<= %.0f)" % [r.size(), w, max_w])
	t.ok(HudLogic.wrap_rows([100, 100], gap, max_w) == [[0, 1]], "items that fit share a row")
	t.ok(HudLogic.wrap_rows([max_w], gap, max_w) == [[0]] and HudLogic.wrap_rows([max_w, 1], gap, max_w) == [[0], [1]], "a row may be exactly max_w; one more px wraps")
	t.ok(HudLogic.wrap_rows([2000, 50], gap, max_w) == [[0], [1]], "an over-wide item stands alone")
	t.ok(HudLogic.wrap_rows([], gap, max_w).is_empty(), "no items, no rows")
	var pos: Array = cfg["topbar_pos_px"]
	var right_edge := float(pos[0]) + max_w + float(cfg["topbar_plate_pad_px"])
	t.ok(right_edge <= 1600.0 - float(cfg["meter_reserve_px"]), "the bar's plate (%.0f) stops left of the ground meter's reserve (%.0f)" % [right_edge, 1600.0 - float(cfg["meter_reserve_px"])])
	var hud_src := FileAccess.get_file_as_string("res://scripts/map/map_hud.gd")
	t.ok(hud_src.contains("HudLogic.wrap_rows("), "the bar lays its rows out with wrap_rows")
