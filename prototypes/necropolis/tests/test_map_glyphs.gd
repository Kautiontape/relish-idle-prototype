extends RefCounted
## Tests for scripts/map/glyph_logic.gd (GlyphLogic): the glyph a lane kind carries, glyph
## positions against the shader's dash pattern and the anchored phase, the near crossfade, the
## siege and party layouts, big-undead stroke counts, the garrison's count and slots (and the
## chip's number, IdleLogic.garrison_units), the glyph stroke tables in LaneStyle, the demo army,
## and source lints over the new glyph files.

const PULSE := preload("res://autoload/pulse.gd")
const LINT := preload("res://tests/test_lint.gd")
const MAP_DIR := "res://scripts/map"
const SHADER_FILE := "res://shaders/map_lane.gdshader"
const GLYPH_FILES := ["glyph_logic.gd", "map_siege.gd", "map_party.gd", "map_fort_idle.gd"]

var p: Node


func run() -> int:
	var t := TestUtil.new()
	Palette.configure(TestUtil.load_json("res://configs/palette.json"))
	LineGlow.configure(TestUtil.load_json("res://configs/line_glow.json"))
	MapLogic.configure(TestUtil.load_json("res://configs/map_view.json"))
	p = PULSE.new()
	p.configure(TestUtil.load_json("res://configs/pulse.json"))
	_kinds(t)
	_counts(t)
	_motion(t)
	_fade(t)
	_strokes(t)
	_siege(t)
	_party(t)
	_garrison_count(t)
	_garrison_slots(t)
	_garrison_small(t)
	_tables(t)
	_demo(t)
	_sources(t)
	p.free()
	return t.failures


func _ch(u: float, hue_key: String) -> Dictionary:
	return p.channels(u, Palette.hue(hue_key))


func _row(kind: String, from: String, to: String, rate := 1.0) -> Dictionary:
	return {"id": "%s:%s:%s" % [kind, from, to], "from": from, "to": to, "kind": kind,
		"rate": rate, "bias": 1.0, "why": ""}


## The lowest zoom that still reads as near (the tier's hysteresis holds it there).
func _near_low() -> float:
	var c := MapLogic.cfg()
	return float(c["zoom_near_above"]) - float(c["zoom_hysteresis"])


func _near_zooms() -> Array:
	return [_near_low(), 2.2, float(MapLogic.cfg()["zoom_max"])]


func _kinds(t: TestUtil) -> void:
	t.suite("map_glyphs-kinds")
	for k in ["war", "flood", "work"]:
		t.ok(GlyphLogic.kind_for(k) == GlyphLogic.UNDEAD, "%s lanes carry undead workers" % k)
	t.ok(GlyphLogic.kind_for("living") == GlyphLogic.LIVING, "living lanes carry the living")
	t.ok(GlyphLogic.kind_for("haul") == GlyphLogic.CART, "haul keeps its carts")
	t.ok(GlyphLogic.kind_for("dead") == GlyphLogic.NONE and GlyphLogic.kind_for("redirect") == GlyphLogic.NONE,
		"the dead gutter and the redirect ring keep their dashes")
	t.ok(GlyphLogic.shader_kind(GlyphLogic.UNDEAD) == 1.0 and GlyphLogic.shader_kind(GlyphLogic.LIVING) == 2.0, "shader kinds 1 and 2")
	t.ok(GlyphLogic.shader_kind(GlyphLogic.CART) == 0.0 and GlyphLogic.shader_kind(GlyphLogic.NONE) == 0.0, "the shader draws no cart or none glyph")
	var u := GlyphLogic.shape(GlyphLogic.UNDEAD)
	var l := GlyphLogic.shape(GlyphLogic.LIVING)
	t.ok(float(u["len"]) == 10.0 and float(u["head_r"]) > float(u["width"]) * 0.5, "the undead worker: a 10 px stroke whose head dot is wider than it")
	t.ok(float(l["len"]) == 6.0 and float(l["sag"]) != 0.0 and float(l["head_w"]) < float(l["head_r"]), "the living: a 6 px arc with a hollow ring head")
	var at_near := float(MapLogic.cfg()["zoom_near_above"])
	t.ok(float(u["len"]) * at_near >= 16.0, "at near zoom the 10 px stroke is >= 16 screen px")


## How many dash centres the shader's own dash mask puts inside [lo, hi], by sampling its phase
## ph = mod(s - offset, period) along the lane: a centre is where ph climbs through dash / 2.
func _mask_centres(lo: float, hi: float, offset: float, period: float, dash: float) -> int:
	var step := 0.05
	var n := 0
	var prev := fposmod(lo - offset, period)
	if absf(prev - dash * 0.5) < 1e-6:
		n += 1
	var i := 1
	while lo + i * step <= hi:
		var ph := fposmod(lo + i * step - offset, period)
		if ph > prev and prev < dash * 0.5 and ph >= dash * 0.5:
			n += 1
		prev = ph
		i += 1
	return n


func _counts(t: TestUtil) -> void:
	t.suite("map_glyphs-counts")
	var cases := [
		[0.0, 300.0, 0.0, 96.0, 59.5], [21.0, 279.0, 13.7, 61.0, 37.8], [40.0, 410.0, 50.2, 44.0, 27.3],
		[12.5, 188.0, 95.9, 96.0, 25.0], [0.0, 188.5, 7.0, 47.125, 23.5]]
	for c in cases:
		var got := GlyphLogic.centres(c[0], c[1], c[2], c[3], c[4])
		var want := _mask_centres(c[0], c[1], c[2], c[3], c[4])
		t.ok(got.size() == want, "one glyph per dash in the drawn range: %d glyphs, %d dashes (period %.1f, trims %.1f..%.1f)" % [got.size(), want, c[3], c[0], c[1]])
		var inside := true
		for s in got:
			inside = inside and s >= c[0] and s <= c[1] and absf(fposmod(s - c[2], c[3]) - c[4] * 0.5) < 1e-3
		t.ok(inside, "each glyph sits on a dash centre inside the trims")
	t.ok(GlyphLogic.centres(0.0, 100.0, 0.0, 0.0, 0.0).is_empty() and GlyphLogic.centres(50.0, 40.0, 0.0, 10.0, 5.0).is_empty(), "no period or no drawn range: no glyphs")
	# tighter with rate, exactly as the dashes: a faster lane's shorter period fits more glyphs
	var lo_u := LaneStyle.motion(_ch(0.1, "undead"), LaneStyle.style_for(_row("war", "covington", "f")))
	var hi_u := LaneStyle.motion(_ch(0.9, "undead"), LaneStyle.style_for(_row("war", "covington", "f")))
	var n_lo := GlyphLogic.centres(0.0, 400.0, 0.0, lo_u["period"], lo_u["dash"]).size()
	var n_hi := GlyphLogic.centres(0.0, 400.0, 0.0, hi_u["period"], hi_u["dash"]).size()
	t.ok(n_hi > n_lo, "a faster lane carries more glyphs per length (%d vs %d)" % [n_hi, n_lo])


func _motion(t: TestUtil) -> void:
	t.suite("map_glyphs-motion")
	var m := LaneStyle.motion(_ch(0.6, "undead"), LaneStyle.style_for(_row("war", "covington", "f")))
	var period: float = m["period"]
	var speed: float = m["speed"]
	var t0 := 4000.0
	var off0 := LaneStyle.phase_offset(3.0, 1000.0, t0, speed, period, false)
	var a := GlyphLogic.centres(0.0, 500.0, off0, period, m["dash"])
	var first := off0 + float(m["dash"]) * 0.5
	t.near(a[0], fposmod(first, period), 1e-3, "the first glyph stands at the dash centre the offset puts there")
	var dt := 0.1
	var off1 := LaneStyle.phase_offset(3.0, 1000.0, t0 + dt * 1000.0, speed, period, false)
	var b := GlyphLogic.centres(0.0, 500.0, off1, period, m["dash"])
	var moved := true
	for s in a:
		var shifted := s + speed * dt
		var found := false
		for q in b:
			found = found or absf(q - shifted) < 1e-2
		moved = moved and (found or shifted > 500.0)
	t.ok(moved, "after dt every glyph has moved speed x dt along the lane (%.1f px)" % (speed * dt))
	t.ok(speed / period >= 0.8 - 1e-3, "marks pass at >= 0.8 Hz (%.2f Hz)" % (speed / period))
	var frozen0 := GlyphLogic.centres(0.0, 500.0, LaneStyle.phase_offset(3.0, 1000.0, t0, speed, period, true), period, m["dash"])
	var frozen1 := GlyphLogic.centres(0.0, 500.0, LaneStyle.phase_offset(3.0, 1000.0, t0 + 5000.0, speed, period, true), period, m["dash"])
	t.ok(frozen0 == frozen1, "reduced motion: the glyphs hold still on the frozen offset")


func _fade(t: TestUtil) -> void:
	t.suite("map_glyphs-fade")
	var near := float(MapLogic.cfg()["zoom_near_above"])
	var fade := float(MapLogic.cfg()["glyph_fade"])
	t.ok(fade > 0.0, "glyph_fade is configured")
	t.ok(GlyphLogic.near_weight(near - fade - 0.01) == 0.0 and GlyphLogic.near_weight(0.6) == 0.0, "0 below the fade band (mid zoom shows no glyphs)")
	t.ok(GlyphLogic.near_weight(near) == 1.0 and GlyphLogic.near_weight(2.2) == 1.0, "1 from the near threshold up")
	t.near(GlyphLogic.near_weight(near - fade * 0.5), 0.5, 1e-4, "linear in between: half way is 0.5")
	t.near(GlyphLogic.near_weight(near - fade * 0.25), 0.75, 1e-4, "a quarter from the top is 0.75")
	var fit := 0.61
	t.ok(GlyphLogic.near_weight(fit) == 0.0, "the default fit (~0.61) shows no glyphs")


func _strokes(t: TestUtil) -> void:
	t.suite("map_glyphs-strokes")
	t.ok(GlyphLogic.FILLED_SLOTS_STANDIN == 1 and GlyphLogic.stroke_count({}) == 1, "no filled_slots yet: the stand-in, one outline")
	t.ok(GlyphLogic.stroke_count({"filled_slots": 2}) == 2, "two filled slots: two nested outlines")
	t.ok(GlyphLogic.stroke_count({"filled_slots": 0}) == 1 and GlyphLogic.stroke_count({"filled_slots": 7}) == 3, "clamped to 1..3")
	var h := GlyphLogic.nest_halves(10.0, 3)
	t.ok(h.size() == 3 and h[0] == 10.0 and h[1] < h[0] and h[2] < h[1] and h[2] > 0.0, "nested inward from the outermost: %s" % str(h))
	t.ok(GlyphLogic.nest_halves(10.0, 9).size() == 3, "never more than three outlines")
	var big := float(GlyphLogic.gcfg()["big_half_px"]) * 2.0
	t.ok(big >= float(GlyphLogic.shape(GlyphLogic.UNDEAD)["len"]) * 1.8, "a big undead is about twice a worker (%.0f px tall)" % big)


## Relish's standing token over a fort of `tier` at `zoom`, as MapNodes places it: above the
## fort's outer radius by relish_gap_px and her halo.
func _standing(fort: Vector2, tier: int, zoom: float) -> Vector2:
	var n := NodeLogic.ncfg()
	var up := NodeLogic.outer_radius("fort", tier, 0.0) + float(n["relish_gap_px"]) + float(NodeLogic.relish_radii(zoom)["halo"])
	return fort - Vector2(0.0, up)


func _siege(t: TestUtil) -> void:
	t.suite("map_glyphs-siege")
	var ext := GlyphLogic.big_extent(float(GlyphLogic.gcfg()["big_half_px"]))
	var c := MapLogic.cfg()
	var fort := Vector2(500.0, 400.0)
	var ok_ring := true
	var ok_apart := true
	var ok_relish := true
	var worst := INF
	for tier in [1, 2, 3, 4]:
		var redirect_out := MapLogic.fort_radius(tier) + float(c["redirect_ring_pad_px"]) + float(c["halo_max_px"]) * 0.5
		for n in [1, 2, 3]:
			var at := GlyphLogic.siege_layout(fort, tier, n)
			ok_ring = ok_ring and at.size() == n
			for i in at.size():
				ok_ring = ok_ring and at[i].distance_to(fort) - ext >= redirect_out
				ok_ring = ok_ring and at[i].y < fort.y  # above the centre: clear of the name and the chip under it
				for j in range(i + 1, at.size()):
					ok_apart = ok_apart and at[i].distance_to(at[j]) >= ext * 2.0
				for z in _near_zooms():
					var rp := _standing(fort, tier, z)
					var d := at[i].distance_to(rp) - ext - GlyphLogic.relish_clear(z)
					worst = minf(worst, d)
					ok_relish = ok_relish and d >= 0.0
					var row := GlyphLogic.party_layout(rp, 0.0, false, 4, z)
					var pext := GlyphLogic.big_extent(float(GlyphLogic.gcfg()["party_half_px"]))
					for q in row:
						ok_relish = ok_relish and at[i].distance_to(q) >= ext + pext
	t.ok(ok_ring, "1..3 sieging big undead sit outside the redirect ring's halo, upper right of the fort")
	t.ok(ok_apart, "and clear of each other")
	t.ok(ok_relish, "and clear of Relish standing there and her party's row, at every near zoom (closest %.1f px)" % worst)
	t.ok(GlyphLogic.siege_layout(fort, 1, 0).is_empty(), "no siege, no glyphs")
	t.ok(GlyphLogic.siege_alpha(1.0) > GlyphLogic.siege_alpha(0.0) and GlyphLogic.siege_alpha(1.0) <= 1.0, "the siege pulses brighter on the beat, alpha <= 1")


func _party(t: TestUtil) -> void:
	t.suite("map_glyphs-party")
	var ext := GlyphLogic.big_extent(float(GlyphLogic.gcfg()["party_half_px"]))
	var rp := Vector2(300.0, 300.0)
	var ok := true
	var behind := true
	for z in _near_zooms():
		for heading in [0.0, 1.2, -2.5]:
			var at := GlyphLogic.party_layout(rp, heading, true, 3, z)
			var dir := Vector2.from_angle(heading)
			for i in at.size():
				ok = ok and at[i].distance_to(rp) - ext >= GlyphLogic.relish_clear(z)
				behind = behind and (at[i] - rp).dot(dir) < 0.0
				if i > 0:
					ok = ok and at[i].distance_to(at[i - 1]) >= ext * 2.0
					behind = behind and at[i].distance_to(rp) > at[i - 1].distance_to(rp)
	t.ok(ok, "travelling: the party clears her token and each other at every near zoom")
	t.ok(behind, "travelling: in party order, trailing behind her along her heading")
	var node_ok := true
	for z in _near_zooms():
		for tier in [1, 4]:
			var fort := Vector2(600.0, 600.0)
			var sp := _standing(fort, tier, z)
			var at := GlyphLogic.party_layout(sp, 0.0, false, 4, z)
			for i in at.size():
				node_ok = node_ok and at[i].distance_to(sp) - ext >= GlyphLogic.relish_clear(z)
				node_ok = node_ok and at[i].distance_to(fort) - ext >= NodeLogic.outer_radius("fort", tier, 0.0)
				node_ok = node_ok and is_equal_approx(at[i].y, sp.y)
				if i > 0:
					node_ok = node_ok and at[i].distance_to(at[i - 1]) >= ext * 2.0
	t.ok(node_ok, "standing: a row beside her, clear of her token, each other and the node's rings")
	t.ok(GlyphLogic.party_layout(rp, 0.0, true, 0, 2.0).is_empty(), "no party, no glyphs")


func _chip_number(text: String) -> int:
	var digits := ""
	for ch in text:
		if ch >= "0" and ch <= "9":
			digits += ch
	return int(digits)


func _garrison_count(t: TestUtil) -> void:
	t.suite("map_glyphs-garrison-count")
	var c: Dictionary = IdleLogic.cfg().duplicate()
	t.ok(float(c["garrison_unit_mass"]) > 0.0, "garrison_unit_mass is configured (%.1f)" % float(c["garrison_unit_mass"]))
	var all_ok := true
	var shown_ok := true
	for unit in [1.0, float(c["garrison_unit_mass"]), 4.0, 25.0]:
		var cc := c.duplicate()
		cc["garrison_unit_mass"] = unit
		for mass in [0.0, 0.4, 4.9, 5.0, 14.99, 15.0, 31.0, 64.0, 88.0, 1234.0, 12345.6]:
			var f := {"garrison": mass}
			var units := IdleLogic.garrison_units(f, cc)
			all_ok = all_ok and units == _chip_number(IdleLogic.garrison_text(f, cc))
			for slots in [1, 3, 6, 11]:
				var fill := GlyphLogic.garrison_fill(units, slots)
				shown_ok = shown_ok and int(fill["shown"]) + int(fill["plus"]) == units
				shown_ok = shown_ok and int(fill["shown"]) <= int(GlyphLogic.gcfg()["garrison_glyph_max"]) and int(fill["shown"]) <= slots
				shown_ok = shown_ok and (int(fill["plus"]) == 0 or int(fill["shown"]) < slots)
	t.ok(all_ok, "the glyph count (garrison_units) is the chip's number, for masses 0..12,345 at unit masses 1, 4, 25 and the config's")
	t.ok(shown_ok, "glyphs shown + the \"+N\" overflow always add up to it, capped at garrison_glyph_max, the +N in a free slot")
	t.ok(IdleLogic.garrison_units({"undead": 64.0, "garrison": 31.0}, c) == roundi(31.0 / float(c["garrison_unit_mass"])), "the view's garrison counts, not the fort's undead")
	t.ok(IdleLogic.garrison_units({"garrison": -5.0}, c) == 0, "never negative")
	var cc := c.duplicate()
	cc["garrison_unit_mass"] = 10.0
	t.ok(IdleLogic.garrison_units({"garrison": 44.9}, cc) == 4 and IdleLogic.garrison_units({"garrison": 45.0}, cc) == 5, "rounded half up, like the chip (44.9 -> 4, 45 -> 5 at 10 a unit)")
	t.ok(IdleLogic.garrison_units({"garrison": 34.0}, cc) == 3, "one unit lost (45 -> 34) is one glyph fewer")
	t.ok(GlyphLogic.garrison_fill(3, 0)["shown"] == 0, "no room in the ring: no glyphs (the chip still counts)")
	t.ok(GlyphLogic.garrison_fill(5, 8) == {"shown": 5, "plus": 0}, "five units in eight slots: five glyphs")


func _garrison_slots(t: TestUtil) -> void:
	t.suite("map_glyphs-garrison-slots")
	var n := NodeLogic.ncfg()
	var s := GlyphLogic.shape(GlyphLogic.UNDEAD)
	var fort := Vector2(200.0, 200.0)
	var ok := true
	var report := []
	for z in _near_zooms():
		var row := []
		for tier in [1, 2, 3, 4]:
			var slots := GlyphLogic.garrison_slots(fort, tier, z)
			var k := float(GlyphLogic.garrison_ring(tier, z)["scale"])  # the worker glyph's shrink
			var half_len := float(s["len"]) * 0.5 * k
			var head := float(s["head_r"]) * k
			var halo := maxf(float(GlyphLogic.gcfg()["garrison_halo_max_px"]), float(s["width"])) * 0.5 * k
			row.append(slots.size())
			var h := NodeLogic.state_glyph_half(z)
			var state_r: float = maxf(h, h * sqrt(2.0) * float(n["state_slash_ext"])) + float(n["state_halo_max_px"]) * 0.5 / z
			var pip_r: float = maxf(float(n["pip_radius_px"]), float(n["pip_min_screen_px"]) / z * 0.5)
			var edge: float = MapLogic.fort_radius(tier) - float(n["pip_inset_px"]) - pip_r
			for i in slots.size():
				var pos: Vector2 = slots[i]["pos"]
				var dir: Vector2 = slots[i]["dir"]
				var tail := pos - dir * half_len
				var tip := pos + dir * half_len
				var closest := Geometry2D.get_closest_point_to_segment(fort, tail, tip).distance_to(fort)
				ok = ok and closest - halo >= state_r
				ok = ok and tip.distance_to(fort) + head <= edge and tail.distance_to(fort) + halo <= edge
				ok = ok and absf(dir.dot((pos - fort).normalized())) < 1e-4
				if slots.size() > 1:
					var nx: Dictionary = slots[(i + 1) % slots.size()]
					var next_tail: Vector2 = nx["pos"] - nx["dir"] * half_len
					ok = ok and tip.distance_to(next_tail) >= head + halo
		report.append("z%.2f %s" % [z, str(row)])
	t.ok(ok, "every slot's worker clears the state glyph, stays inside the pips, runs along the ring and clears the next")
	t.ok(true, "slots per tier 1..4: %s" % ", ".join(report))
	var big := GlyphLogic.garrison_ring(4, 2.2)
	t.ok(int(big["slots"]) >= int(GlyphLogic.garrison_ring(1, 2.2)["slots"]), "a bigger fort holds at least as many")
	t.ok(int(GlyphLogic.garrison_ring(2, 2.2)["slots"]) >= 1, "a tier 2 fort shows its garrison at zoom 2.2")
	t.ok(int(GlyphLogic.garrison_ring(1, 3.0)["slots"]) >= 1 and int(GlyphLogic.garrison_ring(1, 1.6)["slots"]) >= 1, "a tier 1 ring holds a worker at both ends of near (the glyph shrinks at the low end)")


func _garrison_small(t: TestUtil) -> void:
	t.suite("map_glyphs-garrison-small-forts")
	var g := GlyphLogic.gcfg()
	var s := GlyphLogic.shape(GlyphLogic.UNDEAD)
	var fort := Vector2(200.0, 200.0)
	var lo := float(MapLogic.cfg()["zoom_near_above"])
	var hi := float(MapLogic.cfg()["zoom_max"])
	var ok_sum := true
	var ok_min := true
	var ok_out := true
	var outs := 0
	var tier1_low := GlyphLogic.garrison_plan(fort, 1, lo, 5)
	for tier in [0, 1, 2, 3]:  # tier 0 is no real fort: a ring too small even at the minimum size, to reach the fallback
		for i in 25:
			var z := lo + (hi - lo) * i / 24.0
			var k := float(GlyphLogic.garrison_ring(tier, z)["scale"])
			ok_min = ok_min and k * float(s["len"]) * z >= minf(float(g["garrison_min_len_px"]), float(s["len"]) * z) - 1e-4 and k <= 1.0
			for units in [1, 2, 5, 8, 9, 40]:
				var plan := GlyphLogic.garrison_plan(fort, tier, z, units)
				ok_sum = ok_sum and plan["glyphs"].size() + int(plan["plus"]) == units
				if plan["mode"] == "out":
					outs += 1
					var d: float = plan["glyphs"][0]["pos"].distance_to(fort)
					ok_out = ok_out and plan["glyphs"].size() == 1 and d > MapLogic.fort_radius(tier) + 14.0
					ok_out = ok_out and (int(plan["plus"]) == 0 or plan["plus_pos"].distance_to(fort) > d)
	t.ok(ok_sum, "shown + plus == units at every near zoom for tiers 1 to 3 (and 0)")
	t.ok(ok_min, "the worker glyph shrinks no further than garrison_min_len_px on screen")
	t.ok(ok_out, "the outside fallback is one glyph past the held and tithe rings, the +N beyond it")
	t.ok(outs > 0, "the fallback is reached (%d cases)" % outs)
	t.ok(GlyphLogic.garrison_plan(fort, 1, lo, 5)["glyphs"].size() >= 1, "a tier 1 fort at the low end of near still shows a worker (ring: %s, outside: %d cases)" % [tier1_low["mode"], outs])
	t.ok(GlyphLogic.garrison_plan(fort, 1, lo, 0)["glyphs"].is_empty() and int(GlyphLogic.garrison_plan(fort, 1, lo, 0)["plus"]) == 0, "no garrison: no glyph and no +N")
	t.ok(float(GlyphLogic.garrison_ring(1, lo)["scale"]) < 1.0 or int(GlyphLogic.garrison_ring(1, lo)["slots"]) > 0, "a small tier 1 ring shrinks its worker before giving up")


func _tables(t: TestUtil) -> void:
	t.suite("map_glyphs-tables")
	var style := LaneStyle.style_for(_row("war", "covington", "f"))
	var ch := _ch(0.7, "undead")
	var gw := float(GlyphLogic.shape(GlyphLogic.UNDEAD)["width"])
	var loud := LaneStyle.glyph_layers(ch, style, false, gw)
	var lane := LaneStyle.lit_layers(ch, style, false)
	var n := loud.size()
	t.ok(n == lane.size() and float(loud[n - 1]["width"]) == gw, "the glyph stroke: the lane's stack at the glyph's core width")
	var same := true
	for i in n - 1:
		same = same and loud[i]["color"] == lane[i]["color"] and loud[i]["hairline"] == lane[i]["hairline"]
	t.ok(same and bool(loud[n - 1]["hairline"]), "its halos are the lane's (colour, alpha, profile), its core a hairline")
	var body: Color = loud[n - 1]["color"]
	var head := LaneStyle.core_color(ch, style)
	t.ok(body.is_equal_approx(Color(ch["color"], LaneStyle.lane_alpha(ch, style))) and not body.is_equal_approx(head),
		"its body is the lane colour; the pale core colour is its head alone, so the head reads")
	t.ok(float(loud[0]["width"]) <= float(MapLogic.cfg()["halo_max_px"]) + 1e-4, "halo capped")
	var quiet := LaneStyle.glyph_layers(ch, style, true, gw)
	t.ok(quiet.size() == 1 and bool(quiet[0]["hairline"]) and is_equal_approx(float(quiet[0]["width"]), gw * float(MapLogic.cfg()["quiet_width_mult"])),
		"a quiet lane's glyphs are cores only: one hairline, no halos")
	t.ok(LaneStyle.core_color(ch, style, true) == quiet[0]["color"], "a quiet glyph's head takes the quiet core colour")
	t.ok(LaneStyle.lit_layers(ch, style, false, -1.0) == lane, "lit_layers without a width is the lane's own stack")
	var liv := LaneStyle.style_for(_row("living", "vei", "f"))
	var reach := GlyphLogic.lateral_reach(GlyphLogic.LIVING, float(MapLogic.cfg()["halo_max_px"]) * 0.5)
	t.ok(LaneStyle.lit_half_extent(liv) >= reach, "the living lane's ribbon holds its glyph's bulge and halo (%.1f >= %.1f)" % [LaneStyle.lit_half_extent(liv), reach])


func _demo(t: TestUtil) -> void:
	t.suite("map_glyphs-demo")
	var d: Dictionary = MapLogic.cfg()["demo_nodes"]
	var forts := [{"id": str(d["siege"]["fort"]), "siege": []}, {"id": "other", "siege": []}]
	var party := {"party": []}
	var units := {}
	var names := {}
	NodeLogic.demo_army(forts, party, units, names)
	t.ok((forts[0]["siege"] as Array).size() >= 1 and (forts[1]["siege"] as Array).is_empty(), "the demo puts a siege at its fort only")
	t.ok((party["party"] as Array).size() >= 2, "and a party of two or more")
	var named := true
	for u in forts[0]["siege"]:
		named = named and units.has(u) and names.has(u) and str(units[u]["place"]).begins_with("fort:")
	for e in party["party"]:
		named = named and units.has(e["uid"]) and names.has(e["uid"]) and str(e["place"]) == "party"
	t.ok(named, "every demo big undead is a named view_big_undead-shaped entry, placed")
	var held := 0
	for h in [d["held"]] + Array(d["also_held"]):
		held += 1 if float(h.get("undead", 0.0)) > 0.0 else 0
	t.ok(held >= 2, "the demo's held forts carry garrisons")


func _sources(t: TestUtil) -> void:
	t.suite("map_glyphs-sources")
	var banned := RegEx.new()
	banned.compile("\\bsin\\(|Time\\.get_ticks|1\\.714|\\b1714\\b|Pulse\\.wave\\([0-9]|Pulse\\.phase\\([0-9]|Color\\s*\\(\\s*[\"\\d]")
	var lines := 0
	for f in GLYPH_FILES:
		var n := 0
		for line in FileAccess.get_file_as_string("%s/%s" % [MAP_DIR, f]).split("\n"):
			n += 1
			lines += 1
			var code: String = LINT.strip_comment(line)
			if banned.search(code) != null and not line.contains("# lint-ok: bench"):
				t.ok(false, "%s:%d: %s" % [f, n, line.strip_edges()])
	t.ok(lines > 150, "scanned %d lines of glyph scripts" % lines)
	if t.failures == 0:
		t.ok(true, "no sin(), Time.get_ticks, literal tempo, literal hops or colour literals in the glyph scripts")
	t.ok(banned.search("Pulse.wave(1)") != null and banned.search("Pulse.wave(model.hops_of(id))") == null, "detector flags literal hops only")
	var nodes := FileAccess.get_file_as_string("%s/map_nodes.gd" % MAP_DIR)
	t.ok(nodes.contains("_siege.modulate.a = GlyphLogic.siege_alpha(Pulse.wave(model.hops_of("), "the siege beats on the forts' hop through its modulate")
	var shader := ""
	for line in FileAccess.get_file_as_string(SHADER_FILE).split("\n"):
		shader += line.split("//")[0] + "\n"
	t.ok(shader.contains("uniform float glyph_mix") and shader.contains("uniform float glyph_kind"), "the lane shader has a glyph mode")
	t.ok(shader.contains("* (1.0 - gm)"), "chevrons fade out as glyphs fade in")
	var routes := FileAccess.get_file_as_string("%s/map_routes.gd" % MAP_DIR)
	t.ok(routes.contains("GlyphLogic.near_weight(") and routes.contains("if gw != _glyph_w:"), "the routes set the crossfade only when the zoom changed it")
