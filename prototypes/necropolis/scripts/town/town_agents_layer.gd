extends Node2D
## The town view's agent layer, drawn every frame from TownAgents (VISUAL-LANGUAGE §2b "Agents").
## Glyphs (shared with the map and dungeon units):
##   undead worker  a straight `undead` stroke along its heading, a solid `undead_core` dot at its
##                  head (a builder's stroke tilts on the beat, a forge worker's dot flashes);
##   living         a short curved `living` stroke with a hollow ring head;
##   foreman        an `undead` diamond twice the size, one stroke per filled remnant slot, a core dot,
##                  its name on a plate beside it; a newly placed one walks from the crypt in lockstep
##                  with a fading trail (TownAgents.walkers) and its name appears on arrival;
##   cart           an open `undead` U-box pulled by an undead worker, carrying matte `dead` pips;
##   trade arc      a hop from the living buyer to the undead seller (at least view.trade_arc_min_h_px
##                  high, bowing up the screen), `living` fading to `undead`, with a chevron at the
##                  seller (shape, not only colour) and one mote riding it buyer to seller over the
##                  arc's life, `living` turning `undead` as it arrives;
##   Relish         the violet token at the slab, breathing on the beat.
## Dead pips (carried bodies, cart loads) are matte, and `dead_lit` inside Relish's light.
## Agents of one kind draw as one segment batch per glow layer, so the cost stays flat with count.
## Reduced motion: TownAgents holds everything still; arcs draw whole and static here, their mote
## still at the midpoint.

var agents: TownAgents
var model: TownModel
var vcfg: Dictionary = {}


func _draw() -> void:
	if agents == null or model == null:
		return
	var g: Dictionary = vcfg.get("agent", {})
	var k := model.scale
	_draw_living(g, k)
	_draw_undead(g, k)
	_draw_foremen(g, k)
	_draw_arcs(g, k)
	_draw_relish(g, k)


func _f(g: Dictionary, key: String) -> float:
	return float(g.get(key, 0.0))


# ------------------------------------------------------------------ undead ----
func _draw_undead(g: Dictionary, k: float) -> void:
	var length := _f(g, "undead_len_px") * k
	var core := _f(g, "core_px") * k
	var strokes := PackedVector2Array()
	var dots := PackedVector2Array()
	var flashes: Array = []
	var stanced: Array = []  # [head, tail] of agents under a stance flash
	var pips: Array = []  # [centre, lit]
	var carry := _f(g, "carry_px") * k
	for a in agents.undead:
		if a.hidden:
			continue
		var dir := a.dir.rotated(a.tilt) if a.tilt != 0.0 else a.dir
		strokes.append(a.pos - dir * length)
		strokes.append(a.pos)
		dots.append(a.pos - dir * core * 0.5)
		dots.append(a.pos + dir * core * 0.5)
		if a.flash > 0.0:
			flashes.append([a.pos, a.flash])
		if a.stance_flash:
			stanced.append([a.pos, a.pos - dir * length])
		if a.carry:
			pips.append([a.pos - dir * length * 0.5 + Vector2(-dir.y, dir.x) * carry * 1.4, agents.lit(a.pos)])
	# carts: the puller is an undead worker ahead of the box
	var boxes: Array = []
	for c in agents.carts:
		var d: Vector2 = c["dir"]
		var box := _cart_box(c, g, k)
		var head: Vector2 = c["pos"] + d * (box["half"] + _f(g, "tow_px") * k + length)
		strokes.append(head - d * length)
		strokes.append(head)
		dots.append(head - d * core * 0.5)
		dots.append(head + d * core * 0.5)
		strokes.append(c["pos"] + d * box["half"])
		strokes.append(head - d * length)
		boxes.append(box)
	if not strokes.is_empty():
		for l in LineGlow.layers(Palette.c("undead"), _f(g, "undead_w_px"), _f(g, "undead_glow")):
			draw_multiline(strokes, l[1], l[0])
		draw_multiline(dots, Palette.c("undead_core"), core)
	for f in flashes:
		var r: float = core * 0.5 * (1.0 + (_f(g, "flash_mul") - 1.0) * float(f[1]))
		LineGlow.ring(self, f[0], r * 1.6, Palette.c("undead", float(f[1])), _f(g, "undead_w_px"), 1.0)
		draw_circle(f[0], r, Palette.c("undead_core"))
	# a stance fired: the affected strokes burn in their core colour, ringed, for one beat (static
	# under reduced motion: it is the same picture, only the clock that ends it differs)
	if not stanced.is_empty():
		var sw := _f(g, "undead_w_px") * _f(g, "stance_flash_w_mul")
		var sr := core * _f(g, "stance_flash_core_mul")
		for sp in stanced:
			draw_line(sp[1], sp[0], Palette.c("undead_core"), sw)
			draw_circle(sp[0], sr, Palette.c("undead_core"))
			LineGlow.ring(self, sp[0], core * _f(g, "stance_flash_ring_mul"), Palette.c("undead"), _f(g, "undead_w_px"), 1.0)
	for b in boxes:
		LineGlow.polyline(self, b["u"], Palette.c("undead"), _f(g, "cart_w_px"), _f(g, "undead_glow"))
		for p in b["pips"]:
			pips.append([p, b["lit"]])
	var ps := _f(g, "cart_pip_px") * k
	for p in pips:
		var col := Palette.c("dead_lit" if p[1] else "dead")
		draw_rect(Rect2(p[0] - Vector2(ps, ps) * 0.5, Vector2(ps, ps)), col)


## A cart's U-box (open at the top, screen-up, so it reads as a bin whatever its heading) sized to
## its pips in rows of view.agent.cart_cols. {u: polyline, pips: centres, half: half extent along
## the heading, lit}.
func _cart_box(c: Dictionary, g: Dictionary, k: float) -> Dictionary:
	var ps := _f(g, "cart_pip_px") * k
	var gap := _f(g, "cart_pip_gap_px") * k
	var cols := maxi(int(g.get("cart_cols", 1)), 1)
	var n := int(c["pips"])
	var rows := maxi(ceili(float(n) / float(cols)), 1)
	var w := cols * (ps + gap) + gap
	var h := rows * (ps + gap) + gap
	var o: Vector2 = c["pos"]
	var tl := o + Vector2(-w * 0.5, -h * 0.5)
	var u := PackedVector2Array([tl, tl + Vector2(0, h), tl + Vector2(w, h), tl + Vector2(w, 0)])
	var pips := PackedVector2Array()
	for i in n:
		var row := i / cols
		var col := i % cols
		pips.append(tl + Vector2(gap + col * (ps + gap) + ps * 0.5, h - gap - row * (ps + gap) - ps * 0.5))
	var d: Vector2 = c["dir"]
	var half := absf(d.x) * w * 0.5 + absf(d.y) * h * 0.5
	return {"u": u, "pips": pips, "half": half, "lit": bool(c.get("lit", false))}


# ------------------------------------------------------------------ living ----
func _draw_living(g: Dictionary, k: float) -> void:
	var length := _f(g, "living_len_px") * k
	var bend := _f(g, "living_bend") * length
	var rr := _f(g, "living_ring_px") * k
	var segs := PackedVector2Array()
	var ring: Array = []
	for i in 8:
		ring.append(Vector2.from_angle(TAU * i / 8.0) * rr)
	for a in agents.living:
		var d := a.dir
		var side := Vector2(-d.y, d.x)
		var head := a.pos
		var prev := head - d * length
		for s in [0.25, 0.5, 0.75, 1.0]:
			var p: Vector2 = head - d * length * (1.0 - s) + side * bend * 4.0 * s * (1.0 - s)
			segs.append(prev)
			segs.append(p)
			prev = p
		var c := head + d * rr
		for j in 8:
			segs.append(c + ring[j])
			segs.append(c + ring[(j + 1) % 8])
	if segs.is_empty():
		return
	for l in LineGlow.layers(Palette.c("living"), _f(g, "living_w_px"), _f(g, "living_glow"), Palette.c("living_core")):
		draw_multiline(segs, l[1], l[0])


# ----------------------------------------------------------------- foremen ----
## A diamond of `strokes` equal strokes around its perimeter, small gaps between, a core dot.
func _draw_foremen(g: Dictionary, k: float) -> void:
	var h := _f(g, "big_px") * k
	for f in agents.foremen:
		if agents.is_walking(String(f["lot_id"])):
			continue  # on its way: the walker draws it
		_diamond(f["pos"], int(f["strokes"]), g, k)
		_badge(f["pos"], String(f.get("name", "")), agents.badge_alpha(String(f["lot_id"])), h)
	var wk: Dictionary = vcfg.get("walkout", {})
	var segs := maxi(int(wk.get("trail_segs", 1)), 1)
	for w in agents.walkers:
		var tr: PackedVector2Array = w["trail"]
		if tr.size() >= 2:
			# the trail fades behind it: oldest piece faintest
			var pts := TownSetPiece.resample(tr, segs + 1)
			for i in segs:
				var a := float(wk.get("trail_alpha", 1.0)) * float(i + 1) / float(segs)
				LineGlow.polyline(self, PackedVector2Array([pts[i], pts[i + 1]]), Palette.c("undead", a),
					float(wk.get("trail_w_px", 1.0)), _f(g, "big_glow") * a)
		_diamond(w["pos"], int(w["strokes"]), g, k)


## The foreman glyph (the approved diamond): an `undead` diamond, one stroke per filled remnant slot,
## a core dot.
func _diamond(c: Vector2, strokes: int, g: Dictionary, k: float) -> void:
	var h := _f(g, "big_px") * k
	var gap := _f(g, "big_gap")
	var corners: Array[Vector2] = [c + Vector2(0, -h), c + Vector2(h, 0), c + Vector2(0, h), c + Vector2(-h, 0)]
	var n := maxi(strokes, 1)
	var side: float = corners[0].distance_to(corners[1])
	var per: float = side * 4.0 / float(n)
	for i in n:
		var s0: float = per * (float(i) + gap * 0.5)
		var s1: float = per * (float(i + 1) - gap * 0.5)
		LineGlow.polyline(self, _perimeter(corners, side, s0, s1), Palette.c("undead"), _f(g, "big_w_px"),
			_f(g, "big_glow"), Palette.c("undead_core"))
	draw_circle(c, _f(g, "core_px") * k * 0.6, Palette.c("undead_core"))


## The foreman's name on a ground plate beside its diamond (>= 12 px), faded by `alpha`.
func _badge(c: Vector2, text: String, alpha: float, h: float) -> void:
	if text == "" or alpha <= 0.0:
		return
	var wk: Dictionary = vcfg.get("walkout", {})
	var font := ThemeDB.fallback_font
	var fs := maxi(int(wk.get("badge_px", TownUI.MIN_TEXT)), TownUI.MIN_TEXT)
	var pad := float(wk.get("badge_pad_px", 3.0))
	var sz := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	var host: Vector2 = (get_parent() as Control).size if get_parent() is Control else Vector2(1e6, 1e6)
	var x := c.x + h + float(wk.get("badge_gap_px", 6.0))
	if x + sz.x + pad > host.x - 2.0:  # no room on the right: on its left
		x = c.x - h - float(wk.get("badge_gap_px", 6.0)) - sz.x
	x = clampf(x, pad + 2.0, maxf(host.x - sz.x - pad - 2.0, pad + 2.0))
	var y := clampf(c.y - sz.y * 0.5, 2.0, maxf(host.y - sz.y - 2.0, 2.0))
	draw_rect(Rect2(x - pad, y, sz.x + pad * 2.0, sz.y), Palette.c("ground", alpha))
	draw_string(font, Vector2(x, y + font.get_ascent(fs)), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Palette.c("text", alpha))


## The stretch [s0, s1] (px from the first corner) of a closed square-ish perimeter.
func _perimeter(corners: Array[Vector2], side: float, s0: float, s1: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var i0 := int(floor(s0 / side))
	var i1 := int(floor(s1 / side))
	out.append(_on_side(corners, side, i0, s0 - i0 * side))
	for i in range(i0 + 1, i1 + 1):
		out.append(corners[i % 4])
	out.append(_on_side(corners, side, i1, s1 - i1 * side))
	return out


func _on_side(corners: Array[Vector2], side: float, i: int, s: float) -> Vector2:
	var a: Vector2 = corners[i % 4]
	var b: Vector2 = corners[(i + 1) % 4]
	return a.lerp(b, clampf(s / side, 0.0, 1.0))


# ---------------------------------------------------------------- trade arcs ----
## Buyer to seller: a quadratic hop (TownAgents.arc_ctrl), drawn as it lives (grows over
## view.agent.arc_grow of its life, fades over the last arc_fade), with its mote riding it;
## reduced motion: whole, static, the mote at the midpoint.
func _draw_arcs(g: Dictionary, k: float) -> void:
	var life := float(vcfg.get("trade_arc_s", 1.0))
	var w := _f(g, "arc_w_px")
	var glow := _f(g, "arc_glow")
	var chev := _f(g, "arc_chevron_px") * k
	var min_h := float(vcfg.get("trade_arc_min_h_px", 0.0)) * k
	var mote := _f(g, "arc_mote_px") * k
	var n := 12
	for arc in agents.arcs:
		var a: Vector2 = arc["buyer"].pos
		var b: Vector2 = arc["seller"].pos
		if a.distance_to(b) < 1.0:
			continue
		var x := clampf(float(arc["age"]) / maxf(life, 1e-3), 0.0, 1.0)
		var grow := 1.0
		var alpha := 1.0
		if not Pulse.reduced_motion:
			grow = clampf(x / maxf(_f(g, "arc_grow"), 1e-3), 0.0, 1.0)
			alpha = clampf((1.0 - x) / maxf(_f(g, "arc_fade"), 1e-3), 0.0, 1.0)
		var ctrl := TownAgents.arc_ctrl(a, b, _f(g, "arc_bulge"), min_h)
		var pts := PackedVector2Array()
		var us := PackedFloat32Array()
		var m := maxi(int(ceil(n * grow)), 1)
		for i in m + 1:
			var u := minf(float(i) / float(n), grow)
			pts.append(TownAgents.arc_point(a, ctrl, b, u))
			us.append(u)
		var lay_l := LineGlow.layers(Palette.c("living", alpha), w, glow)
		var lay_u := LineGlow.layers(Palette.c("undead", alpha), w, glow)
		for j in lay_l.size():
			var cols := PackedColorArray()
			for u in us:
				cols.append((lay_l[j][1] as Color).lerp(lay_u[j][1], u))
			draw_polyline_colors(pts, cols, lay_l[j][0])
		if grow >= 1.0 and chev > 0.0:
			var tip := pts[pts.size() - 1]
			var d := (tip - pts[pts.size() - 2]).normalized()
			var s := Vector2(-d.y, d.x)
			var c := PackedVector2Array([tip - d * chev + s * chev * 0.7, tip, tip - d * chev - s * chev * 0.7])
			LineGlow.polyline(self, c, Palette.c("undead", alpha), w, glow)
		if mote > 0.0:  # the sale travelling: a tiny core with a glow ring, living turning undead
			var mu := TownAgents.mote_u(float(arc["age"]), life, Pulse.reduced_motion)
			var mc := Palette.c("living", alpha).lerp(Palette.c("undead", alpha), mu)
			var mp := TownAgents.arc_point(a, ctrl, b, mu)
			LineGlow.ring(self, mp, mote * 1.4, mc, w, glow)
			draw_circle(mp, mote * 0.6, Palette.c("living_core", alpha).lerp(Palette.c("undead_core", alpha), mu))


# ------------------------------------------------------------------ Relish ----
func _draw_relish(g: Dictionary, k: float) -> void:
	if not agents.relish_home:
		return
	var p := agents.relish_pos
	var wave := Pulse.wave(0.0, model.depth)
	var r := (_f(g, "relish_r_px") + _f(g, "relish_bob_px") * wave) * k
	LineGlow.ring(self, p, r, Palette.c("relish"), _f(g, "relish_w_px"), _f(g, "relish_glow"))
	draw_circle(p, _f(g, "relish_core_px") * k, Palette.c("relish"))
