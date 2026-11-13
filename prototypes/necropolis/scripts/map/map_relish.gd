class_name MapRelish
extends MapNodeLayer
## Relish's token, halo and wake: a pulse-only layer (she moves). The token sits at ctx.relish_pos
## (MapNodes interpolates it between the model's 0.5 s hops); the wake is the fading violet trail
## in ctx.wake. In a dungeon or the boss fight she carries an "inside" mark; dead she is a hollow
## matte token.


func _draw_pulse() -> void:
	if ctx.relish.is_empty():
		return
	var n := NodeLogic.ncfg()
	var hw := ctx.hair_w()
	var state := str(ctx.relish.get("state", "home"))
	var rp := ctx.relish_pos
	var w: float = Pulse.wave(ctx.model.hops_of(str(ctx.relish.get("at", "covington"))))
	_wake(rp, hw, n)
	var hr := maxf(float(n["relish_halo_r_px"]), ctx.px(float(n["relish_min_screen_px"])))
	var cr := maxf(float(n["relish_core_r_px"]), ctx.px(float(n["relish_core_min_screen_px"])))
	if state == "dead":
		LineGlow.matte_ring(self, rp, hr, Palette.c("dead"), maxf(float(n["relish_width_px"]), hw))
		var x := float(n["relish_dead_x_px"])
		LineGlow.matte_polyline(self, PackedVector2Array([rp + Vector2(-x, -x), rp + Vector2(x, x)]), Palette.c("dead"), hw)
		LineGlow.matte_polyline(self, PackedVector2Array([rp + Vector2(x, -x), rp + Vector2(-x, x)]), Palette.c("dead"), hw)
		return
	glow_ring(rp, hr + float(MapLogic.cfg()["relish_bob_px"]) * w, Palette.c("relish", float(n["relish_alpha_base"]) + float(n["relish_alpha_wave"]) * w),
		maxf(float(n["relish_width_px"]), hw), 1.0, float(n["relish_halo_max_px"]))
	draw_circle(rp, cr, Palette.c("relish"))
	if state == "in_dungeon" or state == "in_boss":
		draw_circle(rp, float(n["relish_inside_r_px"]), Palette.c("ground"))
		var size := int(MapLogic.cfg()["font_label"])
		text(rp + Vector2(hr + ctx.px(float(n["relish_inside_gap_px"])), 0.0), "INSIDE", size, Palette.c("relish"), ALIGN_LEFT, size * float(n["text_mid_ratio"]))


## The wake: a polyline of her recent drawn positions, alpha 1 at her and 0 at the tail, with a
## wider, fainter pass under it. Frozen (reduced motion): it fades along its length only.
func _wake(rp: Vector2, hw: float, n: Dictionary) -> void:
	var buf := ctx.wake
	if buf.size() < 2:
		return
	var alphas := NodeLogic.wake_alphas(buf, ctx.now_s, Pulse.reduced_motion)
	var pts := PackedVector2Array()
	var core := PackedColorArray()
	var halo := PackedColorArray()
	for i in buf.size():
		pts.append(Vector2(buf[i].x, buf[i].y))
		core.append(Palette.c("relish", alphas[i]))
		halo.append(Palette.c("relish", alphas[i] * float(n["wake_halo_alpha"])))
	pts.append(rp)
	core.append(Palette.c("relish"))
	halo.append(Palette.c("relish", float(n["wake_halo_alpha"])))
	var ww := maxf(float(n["wake_width_px"]), ctx.px(float(n["wake_min_screen_px"])))
	draw_polyline_colors(pts, halo, ww * float(n["wake_halo_mult"]))
	draw_polyline_colors(pts, core, ww)
