class_name MapFortGlyph
extends MapNodeLayer
## Every fort's one glanceable state (NodeLogic.fort_state) at its centre, drawn once per change,
## never per frame. At least state_glyph_px across its widest axis on screen at any zoom (the
## diamond tip to tip, the square and hourglass corner to corner, the ring's outer edge), a
## distinct SHAPE per state so greyscale still tells them apart; colour is second:
##   hers       a solid living square;
##   overrun    a hollow undead square (her fort, your garrison inside, not flipped);
##   contested  an hourglass, the undead's half above, the living's below;
##   emptied    a matte dead ring (never glows, never pulses);
##   held       a diamond: solid (safe), hollow (thin), hollow struck through by a danger
##              stroke (will fall). Its margin is the model's, the same one the chip shows.
## A tithe on the way adds a living triangle badge at the upper right, over any state.
## Two instances: the beating one (`beating`) draws the glowing shapes, and MapNodes sets its
## modulate alpha on the forts' beat (NodeLogic.state_alpha); the still one, above it, draws the
## emptied rings (the dead never pulse) and the badges (cut clear of the beating shapes).

var beating := false


func _draw_static() -> void:
	var n := NodeLogic.ncfg()
	for f in ctx.forts:
		var st := NodeLogic.fort_state(f, ctx.model.margin_of(str(f["id"])))
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


## What this layer draws: each fort's state (and badge, for the still layer). With the zoom (a
## redraw on its own), MapNodes redraws the glyphs only when this changes.
func static_sig():
	var out: Array = []
	for f in ctx.forts:
		out.append(NodeLogic.fort_state(f, ctx.model.margin_of(str(f["id"]))))
		if not beating:
			out.append(NodeLogic.tithe_badge(f))
	return out


func _shape(st: String, p: Vector2, h: float, n: Dictionary) -> void:
	var sw := ctx.px(float(n["state_stroke_px"]))
	var glow := float(n["state_glow"])
	var cap := ctx.px(float(n["state_halo_max_px"]))
	var q := h * float(n["state_square_ratio"])
	match st:
		NodeLogic.HERS:
			draw_rect(Rect2(p - Vector2(q, q), Vector2(q, q) * 2.0), Palette.c("living"), true)
		NodeLogic.OVERRUN:
			var e := q - sw * 0.5
			glow_poly(PackedVector2Array([p + Vector2(-e, -e), p + Vector2(e, -e), p + Vector2(e, e), p + Vector2(-e, e), p + Vector2(-e, -e)]),
				Palette.c("undead"), sw, glow, cap)
		NodeLogic.CONTESTED:
			draw_colored_polygon(PackedVector2Array([p + Vector2(-q, -q), p + Vector2(q, -q), p]), Palette.c("undead"))
			draw_colored_polygon(PackedVector2Array([p, p + Vector2(q, q), p + Vector2(-q, q)]), Palette.c("living"))
		NodeLogic.EMPTIED:
			pass  # the still layer's matte ring
		IdleLogic.SAFE:
			diamond(p, h, Palette.c("undead"))
		_:
			var d := h - sw * 0.5
			glow_poly(PackedVector2Array([p + Vector2(0, -d), p + Vector2(d, 0), p + Vector2(0, d), p + Vector2(-d, 0), p + Vector2(0, -d)]),
				Palette.c("undead"), sw, glow, cap)
			if st == IdleLogic.WILL_FALL:
				var e := Vector2(h, h) * float(n["state_slash_ext"])
				glow_poly(PackedVector2Array([p - e, p + e]), Palette.c("danger"), ctx.px(float(n["state_slash_px"])), glow, cap)


## The tithe badge: a living triangle (state_badge_px wide and tall) on a ground backing that
## cuts it clear of the glyph.
func _badge(c: Vector2, n: Dictionary) -> void:
	var b := ctx.px(float(n["state_badge_px"]))
	var back := b + ctx.px(float(n["state_badge_back_px"])) * 2.0
	for k in [[back, Palette.c("ground")], [b, Palette.c("living")]]:
		var hs: float = float(k[0]) * 0.5
		draw_colored_polygon(PackedVector2Array([c + Vector2(0.0, -hs), c + Vector2(hs, hs), c + Vector2(-hs, hs)]), k[1])
