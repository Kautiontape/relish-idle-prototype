class_name MapFortGlyph
extends MapNodeLayer
## Every fort's one glanceable state (NodeLogic.fort_state) at its centre, drawn once per change,
## never per frame. At least state_glyph_px across its widest axis on screen at any zoom (the
## diamond tip to tip, the square and hourglass side to side, the ring's outer edge), a
## distinct SHAPE per state so greyscale still tells them apart; colour is second:
##   hers       a solid living square;
##   overrun    a hollow undead square (Vei's fort, your garrison inside, never taken: not yours);
##   contested  an hourglass, the undead's half above, the living's below;
##   emptied    a matte dead ring (never glows, never pulses);
##   held       a diamond: solid (safe), hollow (thin), hollow struck through by a danger
##              stroke (will fall). Its margin is the model's, the same one the chip shows.
## A tithe on the way adds a living triangle badge at the upper right, over any state.
## Two instances: the beating one (`beating`) draws the glowing shapes, and MapNodes sets its
## modulate alpha on the forts' beat (NodeLogic.state_alpha); the still one, above it, draws the
## emptied rings (the dead never pulse) and the badges (cut clear of the beating shapes).
## While the flip set piece re-inks a fort's ring (ctx.reink) its glyph keeps the pre-flip state,
## and changes once the ring is done.

var beating := false


func _draw_static() -> void:
	var n := NodeLogic.ncfg()
	for f in ctx.forts:
		var st := _state_of(f)
		var p := MapModel.to_vec(f["pos"])
		var h := NodeLogic.state_glyph_half(ctx.zoom)
		if beating:
			_shape(st, p, h, n)
		else:
			if st == NodeLogic.EMPTIED:
				var sw := ctx.px(float(n["state_stroke_px"]))
				LineGlow.matte_ring(self, p, h - sw * 0.5, Palette.c("dead"), sw)
			if NodeLogic.tithe_badge(f):
				_badge(p + Vector2(h, -h), n)
			elif NodeLogic.tithe_next(f):
				_badge_next(p + Vector2(h, -h), n)


## What this layer draws: each fort's state (and badge, for the still layer). With the zoom (a
## redraw on its own), MapNodes redraws the glyphs only when this changes.
func static_sig():
	var out: Array = []
	for f in ctx.forts:
		out.append(_state_of(f))
		if not beating:
			out.append(NodeLogic.tithe_mode(f))
	return out


## The fort's state, or its pre-flip one while its ring re-inks.
func _state_of(f: Dictionary) -> String:
	var rk: Dictionary = ctx.reink.get(str(f["id"]), {})
	if not rk.is_empty():
		return str(rk["from"])
	return NodeLogic.fort_state(f, ctx.model.margin_of(str(f["id"])))


func _shape(st: String, p: Vector2, h: float, n: Dictionary) -> void:
	draw_state(self, st, p, h, ctx.px(float(n["state_stroke_px"])), ctx.px(float(n["state_halo_max_px"])), ctx.px(float(n["state_slash_px"])), n)


## One state's shape on `ci`, centred at `p`, `h` from the centre to its widest edge, stroked `sw`
## wide with halos capped at `cap` and a will-fall slash `slash_w` wide. The fort layer draws it at
## every fort in world px; the legend draws the same shapes at a small size in screen px.
static func draw_state(ci: CanvasItem, st: String, p: Vector2, h: float, sw: float, cap: float, slash_w: float, n: Dictionary) -> void:
	var glow := float(n["state_glow"])
	var q := h * float(n["state_square_ratio"])
	match st:
		NodeLogic.HERS:
			ci.draw_rect(Rect2(p - Vector2(q, q), Vector2(q, q) * 2.0), Palette.c("living"), true)
		NodeLogic.OVERRUN:
			var e := q - sw * 0.5
			glow_poly_on(ci, PackedVector2Array([p + Vector2(-e, -e), p + Vector2(e, -e), p + Vector2(e, e), p + Vector2(-e, e), p + Vector2(-e, -e)]),
				Palette.c("undead"), sw, glow, cap)
		NodeLogic.CONTESTED:
			ci.draw_colored_polygon(PackedVector2Array([p + Vector2(-q, -q), p + Vector2(q, -q), p]), Palette.c("undead"))
			ci.draw_colored_polygon(PackedVector2Array([p, p + Vector2(q, q), p + Vector2(-q, q)]), Palette.c("living"))
		NodeLogic.EMPTIED:
			pass  # the still layer's matte ring
		IdleLogic.SAFE:
			diamond_on(ci, p, h, Palette.c("undead"))
		NodeLogic.HELD:  # held with no margin to show: a filled diamond in the dim ink, not SAFE's green
			diamond_on(ci, p, h, Palette.c("text_dim"))
		_:
			var d := h - sw * 0.5
			glow_poly_on(ci, PackedVector2Array([p + Vector2(0, -d), p + Vector2(d, 0), p + Vector2(0, d), p + Vector2(-d, 0), p + Vector2(0, -d)]),
				Palette.c("undead"), sw, glow, cap)
			if st == IdleLogic.WILL_FALL:
				var e := Vector2(h, h) * float(n["state_slash_ext"])
				glow_poly_on(ci, PackedVector2Array([p - e, p + e]), Palette.c("danger"), slash_w, glow, cap)


## Vei's next tithe pick: the same triangle drawn hollow (an outline, no fill, no backing), at low
## alpha, still. It sits on the still layer, so reduced motion needs no case.
func _badge_next(c: Vector2, n: Dictionary) -> void:
	var hs := ctx.px(float(n["state_badge_px"])) * 0.5
	var pts := PackedVector2Array([c + Vector2(0.0, -hs), c + Vector2(hs, hs), c + Vector2(-hs, hs), c + Vector2(0.0, -hs)])
	draw_polyline(pts, Palette.c("living", float(n["tithe_next_alpha"])), ctx.px(float(n["tithe_next_stroke_px"])))


## The tithe badge: a living triangle (state_badge_px wide and tall) on a ground backing that
## cuts it clear of the glyph.
func _badge(c: Vector2, n: Dictionary) -> void:
	var b := ctx.px(float(n["state_badge_px"]))
	var back := b + ctx.px(float(n["state_badge_back_px"])) * 2.0
	for k in [[back, Palette.c("ground")], [b, Palette.c("living")]]:
		var hs: float = float(k[0]) * 0.5
		draw_colored_polygon(PackedVector2Array([c + Vector2(0.0, -hs), c + Vector2(hs, hs), c + Vector2(-hs, hs)]), k[1])
