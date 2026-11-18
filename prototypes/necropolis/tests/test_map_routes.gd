extends RefCounted
## Tests for scripts/map/lane_style_logic.gd (LaneStyle) and the routes' MapLogic additions:
## the ribbon mesh builder, the per-kind style table, the gutter and phantom tables, lane_curve's
## bow override and lane_curve_for, dash motion, cart spacing, and the low-rate core contrast.

const PULSE := preload("res://autoload/pulse.gd")
const SHADER_FILE := "res://shaders/map_lane.gdshader"
const ROUTES_FILE := "res://scripts/map/map_routes.gd"

var p: Node


func run() -> int:
	var t := TestUtil.new()
	Palette.configure(TestUtil.load_json("res://configs/palette.json"))
	LineGlow.configure(TestUtil.load_json("res://configs/line_glow.json"))
	MapLogic.configure(TestUtil.load_json("res://configs/map_view.json"))
	p = PULSE.new()
	p.configure(TestUtil.load_json("res://configs/pulse.json"))
	_ribbon(t)
	_styles(t)
	_lit(t)
	_screen(t)
	_gutter(t)
	_phantom(t)
	_curves(t)
	_motion(t)
	_carts(t)
	_phase(t)
	_contrast(t)
	_sources(t)
	p.free()
	return t.failures


func _row(kind: String, from: String, to: String, rate := 1.0) -> Dictionary:
	return {"id": "%s:%s:%s" % [kind, from, to], "from": from, "to": to, "kind": kind,
		"rate": rate, "bias": 1.0, "why": ""}


func _ch(u: float, hue_key: String) -> Dictionary:
	return p.channels(u, Palette.hue(hue_key))


func _finite(v: Vector2) -> bool:
	return is_finite(v.x) and is_finite(v.y)


func _ribbon(t: TestUtil) -> void:
	t.suite("map_routes-ribbon")
	var a := Vector2(100, 400)
	var b := Vector2(700, 400)
	var c: Dictionary = MapLogic.lane_curve(a, b, 0.5)
	var pts := MapLogic.sample_quad(c["a"], c["c"], c["b"], 20)
	var r := LaneStyle.ribbon(pts, 6.0)
	var verts: PackedVector2Array = r["verts"]
	var uvs: PackedVector2Array = r["uvs"]
	t.ok(verts.size() == 2 * pts.size() and uvs.size() == verts.size(), "vertex count = 2 x points (%d)" % verts.size())
	var mono := true
	var edges := true
	for i in pts.size():
		if i > 0 and uvs[2 * i].x <= uvs[2 * i - 2].x:
			mono = false
		if uvs[2 * i].y != 1.0 or uvs[2 * i + 1].y != -1.0 or uvs[2 * i].x != uvs[2 * i + 1].x:
			edges = false
	t.ok(mono, "UV.x rises monotonically along the lane")
	t.ok(edges, "UV.y is +1 / -1 at the two edges, UV.x shared across")
	t.near(uvs[0].x, 0.0, 1e-6, "UV.x starts at 0")
	t.near(uvs[uvs.size() - 1].x, MapLogic.curve_length(pts), 1e-3, "UV.x ends at the curve length")
	t.near(r["length"], MapLogic.curve_length(pts), 1e-3, "length is the curve length")
	t.near(verts[20].distance_to(verts[21]), 12.0, 1e-3, "the two edges are 2 x half_width apart")
	# +UV.y is MapLogic's +perp side: heading east, perp = (0, 1), down the screen
	var mid := pts[10]
	t.ok(verts[20].y > mid.y and verts[21].y < mid.y, "+UV.y lies on the +perp side (right of travel)")
	var ring := LaneStyle.ring_points(Vector2(50, 60), 30.0, 32)
	t.ok(ring.size() == 33 and ring[0] == ring[32], "a ring has n+1 points and closes on itself")
	t.near(ring[8].distance_to(Vector2(50, 60)), 30.0, 1e-3, "ring points sit on the radius")
	var rr := LaneStyle.ribbon(ring, 8.0, true)
	var finite := true
	for v in rr["verts"]:
		finite = finite and _finite(v)
	t.ok(finite, "no NaN in a self-loop ring")
	var rv: PackedVector2Array = rr["verts"]
	t.ok(rv[0].is_equal_approx(rv[rv.size() - 2]) and rv[1].is_equal_approx(rv[rv.size() - 1]), "the ring's seam vertices coincide (no kink)")
	t.near(rr["length"], TAU * 30.0, 1.0, "ring length ~ the circumference")
	var degenerate := LaneStyle.ribbon(MapLogic.sample_quad(a, a, a, 5), 4.0)
	var ok_deg := true
	for v in degenerate["verts"]:
		ok_deg = ok_deg and _finite(v)
	t.ok(ok_deg, "a zero-length curve builds without NaN")
	t.ok(LaneStyle.to_mesh(r).get_surface_count() == 1, "to_mesh makes one triangle-strip surface")
	t.near(LaneStyle.point_at(pts, r["cum"], 0.0).x, a.x, 1e-4, "point_at 0 is the start")
	t.ok(LaneStyle.point_at(pts, r["cum"], r["length"] + 50.0).is_equal_approx(b), "point_at past the end clamps to the end")
	var half_s: float = r["length"] * 0.5
	t.ok(LaneStyle.point_at(pts, r["cum"], half_s).distance_to(pts[10]) < 2.0, "point_at half the length is the midpoint")
	var cov := {"from": "covington", "to": "covington", "kind": "work"}
	var red := {"from": "greywall", "to": "greywall", "kind": "redirect"}
	t.near(LaneStyle.ring_radius(cov, 1), float(MapLogic.cfg()["work_ring_radius_px"]), 1e-6, "WORK ring radius from config")
	t.ok(LaneStyle.ring_radius(red, 2) > MapLogic.fort_radius(2) and LaneStyle.ring_radius(red, 3) > LaneStyle.ring_radius(red, 2), "REDIRECT ring sits outside the fort's rings and grows with tier")


func _styles(t: TestUtil) -> void:
	t.suite("map_routes-style")
	var cfg := MapLogic.cfg()
	var kinds: Dictionary = cfg["lane_kinds"]
	var commit := float(cfg["commit_width_mult"])
	var hot := float(cfg["flood_hot_mult"])
	var war := LaneStyle.style_for(_row("war", "covington", "ashgate"))
	t.ok(war["hue_key"] == "undead" and war["core"] == Palette.c("undead_core") and war["glow"] == 1.0, "war: undead, undead_core, full glow")
	t.near(war["width_mult"], commit, 1e-6, "war is committed: commit_width_mult")
	t.ok(war["commit"] and not war["matte"] and not war["loop"] and war["host_id"] == "", "war: lit, not a loop, no host")
	var direct := LaneStyle.style_for(_row("flood", "covington", "vei"))
	t.ok(direct["direct"] and direct["commit"], "cov -> vei flood is the direct, committed FLOOD")
	t.near(direct["width_mult"], commit * hot, 1e-6, "direct flood width x commit x flood_hot")
	t.near(direct["alpha_mult"], hot, 1e-6, "direct flood alpha x flood_hot")
	t.near(direct["glow"], float(cfg["flood_direct_glow"]), 1e-6, "direct flood glow from config (1.0)")
	t.ok(direct["core"] == Palette.c("undead_core"), "direct flood core is undead_core")
	var drain := LaneStyle.style_for(_row("flood", "ashgate", "vei"))
	t.ok(not drain["direct"] and not drain["commit"] and drain["width_mult"] == 1.0 and drain["alpha_mult"] == 1.0, "fort -> vei flood: plain width and alpha")
	t.ok(drain["hue_key"] == "undead", "fort -> vei flood is undead green")
	var living := LaneStyle.style_for(_row("living", "vei", "ashgate"))
	t.ok(living["hue_key"] == "living" and living["core"] == Palette.c("living_core"), "living: orange with living_core")
	t.ok(living["duty"] < war["duty"] and living["duty"] > 0.0, "living dashes are shorter than undead's (%.2f vs %.2f)" % [living["duty"], war["duty"]])
	var haul := LaneStyle.style_for(_row("haul", "ashgate", "covington"))
	t.ok(haul["hue_key"] == "undead" and haul["period_mult"] > 1.0 and haul["duty"] < war["duty"], "haul: undead, a longer period with a long gap")
	t.ok(not haul["commit"], "haul runs home: not a committed flow")
	var dead := LaneStyle.style_for(_row("dead", "ashgate", "vei"))
	t.ok(dead["matte"] and dead["glow"] == 0.0 and dead["core"] == LineGlow.NO_CORE, "dead is matte: no glow, no core")
	t.ok(dead["host_id"] == "flood:ashgate:vei", "dead's host is that fort's fort -> vei flood")
	var work := LaneStyle.style_for(_row("work", "covington", "covington"))
	t.ok(work["loop"] and not work["commit"] and work["hue_key"] == "undead", "work: an undead ring at Covington")
	var red := LaneStyle.style_for(_row("redirect", "greywall", "greywall"))
	t.ok(red["loop"] and red["hue_key"] == "relish" and red["glow"] > 0.0, "redirect: a glowing Relish-violet ring")
	t.ok(kinds.keys().all(func(k): return GameState.LANE_KINDS.has(k)) and GameState.LANE_KINDS.all(func(k): return kinds.has(k)), "lane_kinds covers exactly LANE_KINDS")
	# greyscale rhythm: dash length / gap differ for green, orange and haul at the same u
	var mw := LaneStyle.motion(_ch(0.5, "undead"), war)
	var ml := LaneStyle.motion(_ch(0.5, "living"), living)
	var mh := LaneStyle.motion(_ch(0.5, "undead"), haul)
	var gap := func(m: Dictionary) -> float: return m["period"] - m["dash"]
	t.ok(mw["dash"] > ml["dash"] * 1.8, "green dashes are long, orange short (%.1f vs %.1f px)" % [mw["dash"], ml["dash"]])
	t.ok(gap.call(mh) > gap.call(mw) * 2.0, "haul has long gaps (%.1f vs %.1f px)" % [gap.call(mh), gap.call(mw)])


func _lit(t: TestUtil) -> void:
	t.suite("map_routes-lit")
	var war := LaneStyle.style_for(_row("war", "covington", "ashgate"))
	var hmax := float(MapLogic.cfg()["halo_max_px"])
	# at u = 0 the stack is under halo_max_px: exactly LineGlow's
	var ch0 := _ch(0.0, "undead")
	var low := LaneStyle.lit_layers(ch0, war)
	var expect := LineGlow.layers(Color(ch0["color"], LaneStyle.lane_alpha(ch0, war)),
		float(ch0["width"]) * war["width_mult"], 1.0, Palette.c("undead_core"))
	t.ok(expect[0][0] <= hmax, "u = 0 committed stack is under halo_max_px (%.1f px)" % expect[0][0])
	t.ok(low.size() == expect.size() and low.size() == 4, "a lit lane is LineGlow's 4-stroke stack")
	var same := true
	for i in low.size():
		same = same and is_equal_approx(low[i]["width"], expect[i][0]) and low[i]["color"].is_equal_approx(expect[i][1]) \
			and low[i]["offset"] == 0.0 and low[i]["dashed"]
	t.ok(same, "below the cap: widths and colours are exactly LineGlow.layers(), centred and dashed")
	t.ok(low[3]["hairline"] and not low[0]["hairline"] and not low[1]["hairline"] and not low[2]["hairline"], "only the core is a hairline")
	# at u = 0.6 the stack is capped
	var ch := _ch(0.6, "undead")
	var layers := LaneStyle.lit_layers(ch, war)
	var a := LaneStyle.lane_alpha(ch, war)
	var raw := LineGlow.layers(Color(ch["color"], a), float(ch["width"]) * war["width_mult"], 1.0, Palette.c("undead_core"))
	t.ok(raw[0][0] > hmax, "u = 0.6 committed stack exceeds halo_max_px uncapped (%.1f px)" % raw[0][0])
	t.near(layers[0]["width"], hmax, 1e-4, "the capped outer halo is halo_max_px")
	t.near(layers[3]["width"], raw[3][0], 1e-6, "the cap keeps the core width")
	t.ok(layers[0]["width"] > layers[1]["width"] and layers[1]["width"] > layers[2]["width"] and layers[2]["width"] > layers[3]["width"], "capped halos keep their order, all wider than the core")
	var cols_same := true
	for i in layers.size():
		cols_same = cols_same and layers[i]["color"].is_equal_approx(raw[i][1])
	t.ok(cols_same, "the cap changes widths only, never colours or alphas")
	t.near(LaneStyle.capped_halo(hmax * 3.0, hmax * 2.0, hmax * 3.0), hmax * 2.0, 1e-4, "a core wider than halo_max_px keeps its halos at the core")
	var core: Color = layers[3]["color"]
	t.ok(Color(core, 1.0).is_equal_approx(Palette.c("undead_core")) and is_equal_approx(core.a, a), "the core is the pale undead_core at the lane's alpha")
	t.ok(Color(layers[1]["color"], 1.0).is_equal_approx(Color(ch["color"], 1.0)), "the halos carry the hue colour")
	t.near(layers[3]["width"], float(ch["width"]) * float(MapLogic.cfg()["commit_width_mult"]), 1e-5, "core width = Pulse width x commit")
	var plain := LaneStyle.style_for(_row("flood", "ashgate", "vei"))
	t.ok(LaneStyle.lit_layers(ch, war)[3]["width"] > LaneStyle.lit_layers(ch, plain)[3]["width"] * 1.2, "a committed core stays visibly wider than an uncommitted one at the same u")
	var direct := LaneStyle.style_for(_row("flood", "covington", "vei"))
	var hot_a := LaneStyle.lane_alpha(_ch(0.9, "undead"), direct)
	t.ok(hot_a <= 1.0 and hot_a > LaneStyle.lane_alpha(_ch(0.9, "undead"), war) - 1e-6, "the direct flood is hotter, alpha capped at 1")
	var packed := LaneStyle.pack(layers.slice(0, 2))
	t.ok(packed["widths"].z == 0.0 and packed["widths"].w == 0.0 and packed["colors"].size() == 4, "pack pads to 4 layers with zero width")
	t.ok(packed["colors"][3].a == 0.0 and packed["dashed"].x == 1.0, "padding is transparent; dashed flags carry")
	t.ok(LaneStyle.pack(layers)["hairline"] == Vector4(0, 0, 0, 1), "pack carries the hairline flag on the core only")
	t.ok(LaneStyle.chevrons_on(false, "mid") and LaneStyle.chevrons_on(false, "near"), "chevrons at mid zoom and nearer")
	t.ok(not LaneStyle.chevrons_on(false, "far") and LaneStyle.chevrons_on(true, "far"), "none at far zoom unless reduced motion")
	var size := float(MapLogic.cfg()["chevron_size_px"])
	var he := LaneStyle.lit_half_extent(direct)
	var widest: float = LaneStyle.lit_layers(_ch(1.0, "undead"), direct)[0]["width"]
	t.ok(he >= widest * 0.5 and he >= size * 0.8, "the ribbon holds the widest (capped) halo and a chevron (%.1f px)" % he)


func _screen(t: TestUtil) -> void:
	t.suite("map_routes-screen")
	var fit := 1.0 / (minf(1600.0 / 2048.0, 900.0 / 1440.0) * float(MapLogic.cfg()["fit_margin"]))
	var core := LaneStyle.drawn_stroke(1.1, 0.4, fit, true)
	t.near(core["width_px"], 1.0, 1e-6, "a sub-pixel core is drawn 1 screen px wide")
	t.near(core["alpha"], 0.4, 1e-6, "and keeps its full alpha (a hairline never loses alpha to coverage)")
	var halo := LaneStyle.drawn_stroke(1.1, 0.4, fit, false)
	t.ok(is_equal_approx(halo["width_px"], 1.0) and halo["alpha"] < 0.4 * 0.7, "a sub-pixel halo is 1 px with its alpha scaled by coverage (%.2f)" % halo["alpha"])
	var wide := LaneStyle.drawn_stroke(6.0, 0.7, 0.5, true)
	t.ok(is_equal_approx(wide["width_px"], 12.0) and is_equal_approx(wide["alpha"], 0.7), "a stroke wider than a pixel is drawn as it is")
	# the centre pixel of the weakest lanes at fit zoom over the ground, composited as the shader
	# does: every layer covers the centre pixel at its drawn alpha, outermost first
	var ground := Palette.c("ground")
	for row in [_row("living", "vei", "whitecross"), _row("flood", "ashgate", "vei"), _row("war", "covington", "ashgate")]:
		var style := LaneStyle.style_for(row)
		var ch := _ch(0.0, style["hue_key"])
		var px := ground
		for l in LaneStyle.lit_layers(ch, style):
			var dr := LaneStyle.drawn_stroke(l["width"], l["color"].a, fit, l["hairline"])
			px = px.lerp(Color(l["color"], 1.0), dr["alpha"])
		var cr := MapLogic.contrast_ratio(px, ground)
		t.ok(cr >= 3.0, "%s at u = 0, fit zoom: the drawn centre pixel reaches 3:1 over ground (%.2f)" % [row["id"], cr])


func _gutter(t: TestUtil) -> void:
	t.suite("map_routes-gutter")
	var g: Dictionary = MapLogic.cfg()["gutter"]
	var ch := _ch(0.4, "dead")
	var a := float(ch["alpha"])
	var gw := MapLogic.gutter_width(0.4)
	var host_half := MapLogic.lane_half_width(0.3)
	var layers := LaneStyle.gutter_layers(ch, host_half)
	t.ok(layers.size() == 4, "spill, cut, lip, rim")
	var spill: Dictionary = layers[0]
	var cut: Dictionary = layers[1]
	var lip: Dictionary = layers[2]
	var rim: Dictionary = layers[3]
	var half := (gw + float(g["spill_px"])) * 0.5
	t.near(spill["offset"] - spill["width"] * 0.5, -half, 1e-5, "the spill's far edge is (gutter width + spill_px) / 2 out")
	t.ok(Color(spill["color"], 1.0) == Palette.c("void") and is_equal_approx(spill["color"].a, 0.6) and not spill["dashed"], "spill: black at 0.60, undashed")
	t.ok(cut["color"] == Palette.c("void") and cut["dashed"] and is_equal_approx(cut["width"], gw), "cut: pure black, dashed, gutter-wide")
	t.near(lip["offset"], gw * 0.5, 1e-5, "lip on the near edge (+UV.y, toward the host)")
	t.near(rim["offset"], -gw * 0.5, 1e-5, "rim on the far edge")
	t.near(lip["color"].a, 0.35 + 0.60 * a, 1e-5, "lip alpha 0.35 + 0.60 a")
	t.near(rim["color"].a, 0.25 + 0.40 * a, 1e-5, "rim alpha 0.25 + 0.40 a")
	var lc: Color = lip["color"]
	var rc: Color = rim["color"]
	t.ok(absf(lc.r8 - 132) <= 4 and absf(lc.g8 - 128) <= 4 and absf(lc.b8 - 150) <= 4, "lip ~ 06's rgb(132,128,150): %d,%d,%d" % [lc.r8, lc.g8, lc.b8])
	t.ok(absf(rc.r8 - 90) <= 4 and absf(rc.g8 - 87) <= 4 and absf(rc.b8 - 104) <= 4, "rim ~ 06's rgb(90,87,104): %d,%d,%d" % [rc.r8, rc.g8, rc.b8])
	t.ok(lip["dashed"] and rim["dashed"] and rc.get_luminance() < lc.get_luminance(), "lip and rim dashed; the rim is dimmer")
	var lum_ok := true
	for l in layers:
		lum_ok = lum_ok and Color(l["color"], 1.0).get_luminance() <= Palette.c("dead").lightened(float(g["lip_lighten"])).get_luminance() + 1e-4
	t.ok(lum_ok, "no gutter stroke is brighter than the matte lip: it never glows")
	t.ok(MapLogic.gutter_width(0.9) > MapLogic.gutter_width(0.4), "the gutter widens as the garrison wins")
	t.ok(LaneStyle.gutter_layers(_ch(0.9, "dead"), host_half)[1]["width"] > cut["width"], "the cut follows u_dead")
	var he := LaneStyle.gutter_half_extent()
	var fits := true
	for l in LaneStyle.gutter_layers(_ch(1.0, "dead"), MapLogic.lane_half_width(1.0)):
		fits = fits and absf(l["offset"]) + l["width"] * 0.5 <= he
	t.ok(fits, "every gutter stroke at u = 1 fits the gutter ribbon (%.1f px)" % he)
	t.near(LaneStyle.host_edge(host_half, gw), host_half + gw * 0.5 + float(MapLogic.cfg()["gutter_offset_px"]), 1e-5, "host_edge is gutter_curve's shift")
	t.ok(spill["width"] < gw + float(g["spill_px"]), "the spill is clamped on the host side (%.2f of %.2f px)" % [spill["width"], gw + float(g["spill_px"])])
	# the spill never overlaps the host's core band, whatever the host and dead widths
	var fa := Vector2(1560, 1160)
	var vei := Vector2(1024, 130)
	var hpts := MapLogic.sample_quad(fa, MapLogic.lane_curve(fa, vei, 0.0)["c"], vei, 400)
	var ref := MapLogic.gutter_curve(fa, vei, LaneStyle.OFF, LaneStyle.OFF)
	var rpts := MapLogic.sample_quad(ref["a"], ref["c"], ref["b"], 40)
	var mc := LaneStyle.lateral_cos_min(rpts, fa, vei)
	t.ok(mc < 1.0 and mc > 0.9, "a bowed lane's normals turn off its chord at the ends (min cos %.3f)" % mc)
	t.near(LaneStyle.lateral_cos_min(PackedVector2Array([Vector2(0, 0), Vector2(5, 0), Vector2(10, 0)]), Vector2(0, 0), Vector2(10, 0)), 1.0, 1e-6, "a straight lane: 1")
	var table_ok := true
	var geo_ok := true
	var worst := INF
	for uh in [LaneStyle.OFF, 0.0, 0.3, 0.7, 1.0]:
		var hh := MapLogic.lane_half_width(uh)
		for ud in [0.0, 0.5, 1.0]:
			var sl: Dictionary = LaneStyle.gutter_layers(_ch(ud, "dead"), hh, mc)[0]
			var inner: float = sl["offset"] + sl["width"] * 0.5
			var gwi := MapLogic.gutter_width(ud)
			table_ok = table_ok and inner <= LaneStyle.host_edge(hh, gwi, mc) - hh + 1e-6
			# along the real curve: the spill's inner edge stays outside the host's core band
			var live := MapLogic.gutter_curve(fa, vei, uh, ud)
			var gpts := MapLogic.sample_quad(live["a"], live["c"], live["b"], 40)
			var gv: PackedVector2Array = LaneStyle.ribbon(gpts, 1.0)["verts"]
			for i in gpts.size():
				var q: Vector2 = gpts[i] + (gv[2 * i] - gpts[i]) * inner
				var dmin := INF
				for hp in hpts:
					dmin = minf(dmin, q.distance_to(hp))
				worst = minf(worst, dmin - hh)
				geo_ok = geo_ok and dmin >= hh - 0.05
	t.ok(table_ok, "the spill's inner edge never passes the host core's outer edge (table)")
	t.ok(geo_ok, "along the curve the spill stops outside the host's core band (closest %.2f px clear)" % worst)
	# on screen: the shader's clip ends the spill's antialiased edge where the drawn core's begins
	var clip_ok := true
	for wpp in [0.3, 0.6, 1.0 / 0.6125, 3.3]:
		for hh in [MapLogic.lane_half_width(0.0), MapLogic.lane_half_width(1.0)]:
			var edge := LaneStyle.host_edge(hh, gw, mc)
			var drawn_half: float = LaneStyle.drawn_stroke(hh * 2.0, 1.0, wpp, true)["width_px"] * wpp * 0.5
			clip_ok = clip_ok and LaneStyle.spill_clip(edge, hh, wpp) + 0.5 * wpp <= edge - drawn_half - 0.5 * wpp + 1e-5
	t.ok(clip_ok, "spill_clip keeps the spill's AA edge off the drawn core and its AA edge at every zoom")
	# the gutter is the reference curve translated: one vector for a, c and b
	var live2 := MapLogic.gutter_curve(fa, vei, 0.7, 0.3)
	var d: Vector2 = live2["a"] - ref["a"]
	t.ok((live2["c"] - ref["c"]).distance_to(d) < 1e-3 and (live2["b"] - ref["b"]).distance_to(d) < 1e-3 and d.length() > 1.0,
		"gutter_curve(u) is the reference translated (one vector for a, c, b)")
	# the lip side faces the host: +UV.y of the gutter ribbon points at the host curve
	var host := MapLogic.lane_curve(fa, vei, 0.7)
	var gpts2 := MapLogic.sample_quad(live2["a"], live2["c"], live2["b"], 20)
	var gr := LaneStyle.ribbon(gpts2, 4.0)
	var hmid := MapLogic.sample_quad(host["a"], host["c"], host["b"], 20)[10]
	var v: PackedVector2Array = gr["verts"]
	t.ok(v[20].distance_to(hmid) < v[21].distance_to(hmid), "the gutter's +UV.y side (the lip) faces its host")
	t.ok(LaneStyle.gutter_chevron_color(ch).is_equal_approx(Color(lc, a * float(g["chevron_alpha_mult"]))), "gutter chevrons in the lip grey")


func _phantom(t: TestUtil) -> void:
	t.suite("map_routes-phantom")
	t.ok(LaneStyle.needs_phantom(0.3, LaneStyle.OFF), "dead on + host off -> phantom bank")
	t.ok(not LaneStyle.needs_phantom(0.3, 0.2), "dead on + host on -> no phantom")
	t.ok(not LaneStyle.needs_phantom(LaneStyle.OFF, LaneStyle.OFF), "dead off -> no phantom")
	t.ok(not LaneStyle.gutter_on(LaneStyle.OFF) and LaneStyle.gutter_on(0.0), "dead off -> no gutter at all; dead at u=0 has one")
	t.ok(LaneStyle.lane_mode(LaneStyle.OFF, true) == "phantom", "an off host with live dead draws the phantom")
	t.ok(LaneStyle.lane_mode(LaneStyle.OFF, false) == "off", "an off lane is dark")
	t.ok(LaneStyle.lane_mode(0.0, true) == "lit" and LaneStyle.lane_mode(0.5, false) == "lit", "an on lane is lit")
	var host := LaneStyle.style_for(_row("flood", "old-sluice", "vei"))
	var ph := LaneStyle.phantom_layers(host)
	t.ok(ph.size() == 1 and not ph[0]["dashed"], "phantom: one undashed line")
	t.ok(Color(ph[0]["color"], 1.0) == Palette.c("undead") and is_equal_approx(ph[0]["color"].a, float(MapLogic.cfg()["phantom_alpha"])), "host-coloured at phantom_alpha")
	t.near(ph[0]["width"], float(MapLogic.cfg()["phantom_width_px"]), 1e-6, "phantom_width_px wide")
	var rows := LaneStyle.plan_rows([_row("dead", "old-sluice", "vei", 2.0), _row("war", "covington", "ashgate")])
	var ids := rows.map(func(r): return r["id"])
	t.ok(ids.has("flood:old-sluice:vei") and rows.size() == 3, "a dead row without its host gets a 0-rate host row")
	t.ok(rows.filter(func(r): return r["id"] == "flood:old-sluice:vei")[0]["rate"] == 0.0, "the added host is off")
	var with_host := LaneStyle.plan_rows([_row("dead", "ashgate", "vei", 2.0), _row("flood", "ashgate", "vei", 1.0)])
	t.ok(with_host.size() == 2, "an existing host is not duplicated")
	t.ok(LaneStyle.plan_rows([_row("mystery", "a", "b")]).is_empty(), "unknown kinds are not drawn")
	# a won map's END: no lane with Vei at either end
	t.ok(LaneStyle.touches_vei(_row("flood", "ashgate", "vei")) and LaneStyle.touches_vei(_row("war", "vei", "ashgate")) and LaneStyle.touches_vei(_row("dead", "ashgate", "vei", 2.0)), "Vei's lanes: in, out and the dead gutter")
	t.ok(not LaneStyle.touches_vei(_row("war", "covington", "ashgate")) and not LaneStyle.touches_vei(_row("haul", "ashgate", "covington")), "the realm's own lanes are not hers")
	var mix := [_row("flood", "ashgate", "vei"), _row("war", "covington", "ashgate"), _row("war", "vei", "ashgate", 0.0), _row("dead", "ashgate", "vei", 2.0)]
	t.ok(LaneStyle.without_vei(mix, true).size() == 1 and LaneStyle.without_vei(mix, true)[0]["kind"] == "war" and LaneStyle.without_vei(mix, true)[0]["from"] == "covington", "END keeps only the realm's lanes, whatever Vei's flow")
	t.ok(LaneStyle.without_vei(mix, false).size() == 4, "before END every row stays")
	var rsrc := FileAccess.get_file_as_string("res://scripts/map/map_routes.gd")
	t.ok(rsrc.contains("LaneStyle.without_vei(LaneStyle.plan_rows(model.lanes), _vei_hidden)"), "the routes drop Vei's lanes from the plan once hidden")
	# the lane callouts follow the routes: no "why" plate for a hidden lane
	var why := [_row("flood", "covington", "vei", 3.0), _row("living", "vei", "ashgate", 2.0), _row("war", "covington", "ashgate", 1.0)]
	for r in why:
		r["why"] = "valve"
	var shown := HudLogic.callout_items(LaneStyle.without_vei(why, true), 0)
	t.ok(HudLogic.callout_items(LaneStyle.without_vei(why, false), 0).size() == 3 and shown.size() == 1 and str(shown[0]["from"]) == "covington" and str(shown[0]["to"]) == "ashgate",
		"END's callouts: only the realm's lanes keep a why plate (%d of 3)" % shown.size())
	var csrc := FileAccess.get_file_as_string("res://scripts/map/map_callouts.gd")
	t.ok(csrc.contains("HudLogic.callout_items(LaneStyle.without_vei(model.lanes, _vei_hidden)") and csrc.contains("func set_vei_hidden(on: bool)"), "the callouts drop Vei's lanes once hidden, as the routes do")


func _curves(t: TestUtil) -> void:
	t.suite("map_routes-curves")
	var cfg := MapLogic.cfg()
	var a := Vector2(1780, 1270)
	var b := Vector2(1024, 130)
	var chord := a.distance_to(b)
	var mid := (a + b) * 0.5
	var plain := MapLogic.lane_curve(a, b, 0.5)
	t.near((plain["c"] as Vector2).distance_to(mid), chord * float(cfg["lane_bow"]), 1e-2, "lane_curve without bow keeps lane_bow")
	var over := MapLogic.lane_curve(a, b, 0.5, 0.05)
	t.near((over["c"] as Vector2).distance_to(mid), chord * 0.05, 1e-2, "the bow argument overrides lane_bow")
	t.ok(((over["c"] - mid) as Vector2).dot(plain["c"] - mid) > 0.0, "same side (left of travel)")
	var direct := MapLogic.lane_curve_for(_row("flood", "covington", "vei"), a, b, 0.5)
	t.near((direct["c"] as Vector2).distance_to(mid), chord * float(cfg["flood_direct_bow"]), 1e-2, "lane_curve_for: cov -> vei flood uses flood_direct_bow")
	t.ok(float(cfg["flood_direct_bow"]) < float(cfg["lane_bow"]), "the direct FLOOD is straighter")
	var f := Vector2(1560, 1160)
	for kind_ends in [["war", "covington", f, "ashgate"], ["flood", "ashgate", f, "vei"], ["living", "vei", b, "ashgate"],
			["dead", "ashgate", f, "vei"], ["haul", "ashgate", f, "covington"]]:
		var row := _row(kind_ends[0], kind_ends[1], kind_ends[3])
		var from_pos: Vector2 = kind_ends[2]
		var to_pos: Vector2 = a if kind_ends[3] == "covington" else (b if kind_ends[3] == "vei" else f)
		if from_pos == to_pos:
			continue
		var c1 := MapLogic.lane_curve_for(row, from_pos, to_pos, 0.3)
		var c0 := MapLogic.lane_curve(from_pos, to_pos, 0.3)
		t.ok((c1["c"] as Vector2).is_equal_approx(c0["c"]), "lane_curve_for: %s uses lane_bow" % row["id"])
	t.ok(MapLogic.lane_curve_for(_row("work", "covington", "covington"), a, a, 0.3)["loop"], "a self-loop row is a loop")


func _motion(t: TestUtil) -> void:
	t.suite("map_routes-motion")
	var war := LaneStyle.style_for(_row("war", "covington", "ashgate"))
	var haul := LaneStyle.style_for(_row("haul", "ashgate", "covington"))
	var dead := LaneStyle.style_for(_row("dead", "ashgate", "vei"))
	var ch := _ch(0.0, "undead")
	var mw := LaneStyle.motion(ch, war)
	t.near(mw["period"], ch["period"], 1e-5, "war keeps Pulse's period")
	t.near(mw["dash"], ch["period"] * war["duty"], 1e-5, "dash = period x the kind's duty")
	var mh := LaneStyle.motion(ch, haul)
	t.near(mh["speed"] / mh["period"], ch["speed"] / ch["period"], 1e-5, "haul's longer period keeps the mark rate (>= 0.8 Hz)")
	var dch := _ch(0.3, "dead")
	var md := LaneStyle.motion(dch, dead)
	t.ok(is_equal_approx(md["period"], dch["period"]) and is_equal_approx(md["dash"], dch["dash"]) and is_equal_approx(md["speed"], dch["speed"]), "the gutter walks with the dead flow's own period, dash and speed")
	var circ := TAU * 44.0
	var rp := LaneStyle.ring_period(circ, 70.0)
	t.near(fposmod(circ / rp, 1.0), 0.0, 1e-4, "a ring's period tiles its circumference")
	t.ok(absf(rp - 70.0) <= 70.0 * 0.5, "and stays near the asked period (%.1f)" % rp)
	t.near(LaneStyle.ring_period(10.0, 70.0), 10.0, 1e-5, "a tiny ring gets one dash")
	var work := LaneStyle.style_for(_row("work", "covington", "covington"))
	var mr := LaneStyle.motion(ch, work, circ)
	t.near(fposmod(circ / mr["period"], 1.0), 0.0, 1e-4, "ring motion uses the tiling period")
	t.near(mr["speed"] / mr["period"], ch["speed"] / ch["period"], 1e-5, "and keeps the mark rate")


func _carts(t: TestUtil) -> void:
	t.suite("map_routes-carts")
	var c: Dictionary = MapLogic.cfg()["carts"]
	var cap := int(c["count_max"])
	var length := 400.0
	var speed := 140.0
	var prev_count := 0
	var prev_spacing := INF
	var mono := true
	for rate in [0.1, 0.3, 1.0, 3.0, 10.0, 25.0]:
		var k := LaneStyle.carts(rate, speed, length)
		mono = mono and k["count"] >= prev_count and k["spacing"] <= prev_spacing + 1e-6
		prev_count = k["count"]
		prev_spacing = k["spacing"]
		t.ok(k["count"] <= cap and k["count"] >= 1, "rate %.1f: %d carts (cap %d)" % [rate, k["count"], cap])
		t.ok(k["pips"] >= 1 and k["pips"] <= int(c["pips_max"]), "rate %.1f: %d pips per cart" % [rate, k["pips"]])
	t.ok(mono, "more rate -> closer carts, never fewer")
	t.ok(LaneStyle.carts(25.0, speed, length)["count"] == cap, "the count caps at count_max")
	var free := LaneStyle.carts(1.0, speed, length)
	t.near(free["spacing"], speed * float(c["load"]) / 1.0, 1e-3, "uncapped spacing = speed x load / rate")
	t.ok(free["pips"] == roundi(float(c["load"]) / float(c["pip_units"])), "uncapped: one pip per load unit of a full cart")
	t.ok(LaneStyle.carts(25.0, speed, length)["pips"] > free["pips"], "when the cap binds each cart carries more pips")
	t.ok(LaneStyle.carts(0.0, speed, length)["count"] == 0, "an off haul lane has no carts")
	var pos := LaneStyle.cart_positions(37.0, 120.0, length)
	var ok_pos := pos.size() > 0
	for i in pos.size():
		ok_pos = ok_pos and pos[i] >= 0.0 and pos[i] < length
		if i > 0:
			ok_pos = ok_pos and is_equal_approx(pos[i] - pos[i - 1], 120.0)
	t.ok(ok_pos and pos.size() <= int(ceil(length / 120.0)), "cart positions lie on the lane, spacing apart")
	t.ok(LaneStyle.cart_positions(0.0, 5000.0, length).size() == 1, "a still frame (reduced motion) still shows a cart")


func _phase(t: TestUtil) -> void:
	t.suite("map_routes-phase")
	# a lane at speed 100 px/s, period 80, anchored at t = 0 with offset 10
	var off := LaneStyle.phase_offset(10.0, 0.0, 500.0, 100.0, 80.0, false)
	t.near(off, fposmod(10.0 + 50.0, 80.0), 1e-4, "offset = anchor + elapsed x speed")
	t.near(LaneStyle.phase_offset(10.0, 0.0, 0.0, 100.0, 80.0, false), 10.0, 1e-5, "at the anchor it shows the anchor offset")
	var wrapped := LaneStyle.phase_offset(10.0, 0.0, 12345.0, 100.0, 80.0, false)
	t.ok(wrapped >= 0.0 and wrapped < 80.0, "the offset wraps into [0, period) (%.2f)" % wrapped)
	t.near(LaneStyle.phase_offset(10.0, 0.0, 500.0, 100.0, 80.0, true), 0.0, 1e-6, "reduced motion: 0")
	for tm in [0.0, 500.0, 1714.0, 99999.0]:
		t.ok(LaneStyle.phase_offset(10.0, 0.0, tm, 100.0, 80.0, true) == LaneStyle.phase_offset(10.0, 0.0, 0.0, 100.0, 80.0, true), "reduced motion: the same offset at t=%d ms" % int(tm))
	t.ok(LaneStyle.phase_offset(10.0, 0.0, 500.0, 100.0, 80.0, false) != LaneStyle.phase_offset(10.0, 0.0, 900.0, 100.0, 80.0, false), "full motion: the offset walks")
	t.ok(LaneStyle.chevrons_on(true, "far") and LaneStyle.chevrons_on(true, "mid"), "reduced motion: chevrons stay on at every zoom, so a still frame shows direction")
	var rs := FileAccess.get_file_as_string("res://scripts/map/map_routes.gd")
	t.ok(rs.contains("r.speed, r.period, rm))") and rs.contains("Pulse.reduced_motion))"), "every offset the routes set passes the reduced-motion flag")
	t.near(LaneStyle.phase_offset(10.0, 0.0, 500.0, 100.0, 0.0, false), 0.0, 1e-6, "a zero period shows 0")
	# continuity across a speed / period change, minutes into play
	var now := 600000.0
	var before := LaneStyle.phase_offset(10.0, 0.0, now, 100.0, 80.0, false)
	var re_same := LaneStyle.rebase_offset(10.0, 0.0, now, 100.0, 80.0, 80.0)
	t.near(re_same, before, 1e-3, "a speed-only change: the offset right after equals the one before")
	var after_speed := LaneStyle.phase_offset(re_same, now, now + 1000.0, 260.0, 80.0, false)
	t.near(after_speed, fposmod(before + 260.0, 80.0), 1e-3, "and it then walks at the new speed")
	var re_per := LaneStyle.rebase_offset(10.0, 0.0, now, 100.0, 80.0, 120.0)
	t.near(re_per / 120.0, before / 80.0, 1e-4, "a period change keeps the dash fraction")
	t.near(LaneStyle.phase_offset(re_per, now, now, 90.0, 120.0, false), re_per, 1e-5, "and the new anchor is shown at once")
	var rm_re := LaneStyle.rebase_offset(10.0, 0.0, now, 100.0, 80.0, 80.0)
	t.near(rm_re, before, 1e-3, "rebasing ignores reduced motion: F8 off again resumes the same phase")
	t.near(LaneStyle.rebase_offset(0.0, 0.0, 1000.0, 0.0, 1.0, 80.0), 0.0, 1e-6, "a fresh ribbon (speed 0, anchor 0) starts at 0")
	# carts: the lead cart keeps its place across a spacing change
	var length := 700.0
	var base0 := LaneStyle.phase_offset(33.0, 0.0, now, 140.0, 300.0, false)
	var lead0 := LaneStyle.cart_lead(base0, 300.0, length)
	var anchor1 := LaneStyle.cart_anchor(33.0, 0.0, now, 140.0, 300.0, 180.0, length)
	var lead1 := LaneStyle.cart_lead(LaneStyle.phase_offset(anchor1, now, now, 140.0, 180.0, false), 180.0, length)
	t.near(lead1, fposmod(lead0, 180.0), 1e-3, "a spacing change leaves a cart where the lead stood (%.1f mod the new spacing)" % lead0)
	var pos := LaneStyle.cart_positions(LaneStyle.phase_offset(anchor1, now, now, 140.0, 180.0, false), 180.0, length)
	t.near(pos[0], fposmod(lead0, 180.0), 1e-3, "and cart_positions agrees")
	var anchor2 := LaneStyle.cart_anchor(anchor1, now, now + 2000.0, 140.0, 180.0, 180.0, length)
	var lead_a := LaneStyle.cart_lead(LaneStyle.phase_offset(anchor1, now, now + 2000.0, 140.0, 180.0, false), 180.0, length)
	var lead_b := LaneStyle.cart_lead(LaneStyle.phase_offset(anchor2, now + 2000.0, now + 2000.0, 140.0, 180.0, false), 180.0, length)
	t.near(lead_b, lead_a, 1e-3, "a speed-only re-anchor does not move the train")
	t.near(LaneStyle.cart_anchor(5.0, 0.0, now, 140.0, 0.0, 180.0, length), 0.0, 1e-6, "a train that had no carts starts at 0")


func _contrast(t: TestUtil) -> void:
	t.suite("map_routes-contrast")
	var ground := Palette.c("ground")
	var floor_a := float(MapLogic.cfg()["lane_alpha_floor"])
	var rows := {"undead": _row("war", "covington", "ashgate"), "living": _row("living", "vei", "ashgate"),
		"relish": _row("redirect", "greywall", "greywall")}
	var binding := 0.0
	for key in rows:
		var style := LaneStyle.style_for(rows[key])
		var ch := _ch(0.0, style["hue_key"])
		var core := LaneStyle.core_color(ch, style)
		t.near(core.a, maxf(float(ch["alpha"]), floor_a), 1e-6, "%s: the lowest-u core is drawn at the floored alpha" % key)
		var cr := MapLogic.contrast_ratio(core, ground)
		t.ok(cr >= 3.0, "%s: lowest-u core (the shader's core stroke) over ground reaches 3:1 (%.2f)" % [key, cr])
		# the smallest alpha that clears 3:1 for this core
		var need := 0.0
		while MapLogic.contrast_ratio(Color(core, need), ground) < 3.0 and need < 1.0:
			need += 0.01
		if key != "relish":
			binding = maxf(binding, need)
	t.near(floor_a, binding, 0.0051, "lane_alpha_floor is the smallest alpha that keeps the dimmest core at 3:1 (%.2f)" % binding)
	var war := LaneStyle.style_for(rows["undead"])
	t.ok(LaneStyle.lane_alpha(_ch(0.5, "undead"), war) > LaneStyle.lane_alpha(_ch(0.0, "undead"), war) + 0.2, "alpha still rises with u (0.4 + 0.6u survives the floor)")


func _sources(t: TestUtil) -> void:
	t.suite("map_routes-sources")
	var shader := FileAccess.get_file_as_string(SHADER_FILE)
	var code := ""
	for line in shader.split("\n"):
		code += line.split("//")[0] + "\n"
	t.ok(shader.length() > 0 and not code.contains("TIME"), "the lane shader never reads TIME")
	t.ok(code.contains("fwidth") or code.contains("dFdx"), "the lane shader antialiases from screen derivatives")
	t.ok(not code.contains("discard"), "the lane shader discards nothing (the trim is a coverage multiply)")
	var frag := code.substr(code.find("void fragment"))
	var first_if := frag.find("if (")
	var last_dfd := maxi(frag.rfind("dFdx"), frag.rfind("dFdy"))
	t.ok(first_if > 0 and last_dfd > 0 and last_dfd < first_if, "every derivative runs before the first branch")
	var routes := FileAccess.get_file_as_string(ROUTES_FILE)
	t.ok(routes.contains("static func lane_curve_for(") and routes.contains("MapLogic.lane_curve_for(row, from_pos, to_pos, u)"), "MapRoutes.lane_curve_for forwards to MapLogic")
	t.ok(not routes.contains("func _draw"), "the old GDScript dash walker is gone (no _draw in map_routes)")
	t.ok(routes.contains("MapLogic.lane_curve(from_pos, to_pos, u, bow)"), "MapRoutes.lane_curve forwards to MapLogic")
