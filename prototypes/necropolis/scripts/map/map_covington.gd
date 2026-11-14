class_name MapCovington
extends MapNodeLayer
## Covington, the tempo's source (hop 0). Static layer: the undead diamond glyph, its label, the
## valve glyph (three stems whose widths are the committed WORK / WAR / FLOOD shares: the valve
## target, which the valve swing set piece tweens over a beat, brightening the stems) and the
## selection ring. Pulse layer: the source pulse rings and the core, on Pulse's phase and wave at hop 0.


func _draw_static() -> void:
	var n := NodeLogic.ncfg()
	var cp := ctx.cov_pos
	var hw := ctx.hair_w()
	var h := float(n["cov_half_px"])
	var outline := PackedVector2Array([cp + Vector2(0, -h), cp + Vector2(h, 0), cp + Vector2(0, h), cp + Vector2(-h, 0), cp + Vector2(0, -h)])
	glow_poly(outline, Palette.c("undead"), maxf(float(n["cov_width_px"]), hw), 1.0, float(n["cov_halo_max_px"]), Palette.c("undead_core"))
	_valve(cp, hw, n)
	if ctx.selected_id == "covington":
		draw_arc(cp, float(MapLogic.cfg()["work_ring_radius_px"]) + float(n["cov_select_pad_px"]), 0.0, TAU, int(MapLogic.cfg()["ring_samples"]),
			Palette.c("select"), maxf(float(n["select_width_px"]), hw))


## The valve's stem widths and brightness and the selection: all that changes between zooms.
func static_sig():
	return [NodeLogic.valve_widths(_shares()), ctx.valve_bright, ctx.selected_id == "covington"]


## The stems' shares: the set piece's (the committed valve, or its swing), else the view's target.
func _shares() -> Dictionary:
	if not ctx.valve_shares.is_empty():
		return ctx.valve_shares
	return ctx.model.hud.get("valve_target", ctx.model.hud.get("valve", {}))


## The valve: WAR toward the forts' centroid, FLOOD toward Vei, WORK a hook curling back home.
## Each stem is `valve_glyph_max_w x share` wide (never under a hairline); a share of 0 draws nothing.
## The four labels are placed by NodeLogic.valve_label_layout so none overlap.
func _valve(cp: Vector2, hw: float, n: Dictionary) -> void:
	var widths := NodeLogic.valve_widths(_shares())
	var dirs := NodeLogic.valve_dirs(cp, NodeLogic.fort_centroid(ctx.forts), ctx.vei_pos)
	var inner := float(n["valve_in_px"])
	var tip := inner + float(n["valve_len_px"])
	var sp := SetpieceLogic.cfg()
	var col := Palette.c("undead").lightened(float(sp["valve_lighten"]) * ctx.valve_bright)
	var cap := float(n["valve_halo_max_px"])
	var glow := float(n["valve_glow"]) + float(sp["valve_glow_boost"]) * ctx.valve_bright
	for k in ["war", "flood"]:
		if widths[k] > 0.0:
			var d: Vector2 = dirs[k]
			glow_poly(PackedVector2Array([cp + d * inner, cp + d * tip]), col, maxf(widths[k], hw), glow, cap)
	if widths["work"] > 0.0:
		var dw: Vector2 = dirs["work"]
		var hr := float(n["valve_hook_r_px"])
		var c := cp + dw * (inner + hr)
		var a0 := dw.angle() + PI
		glow_arc(c, hr, a0, a0 + deg_to_rad(float(n["valve_hook_sweep_deg"])), col, maxf(widths["work"], hw), glow, cap)
	var size := int(MapLogic.cfg()["font_label"])
	var names := {"war": "WAR", "flood": "FLOOD", "work": "WORK", "covington": "COVINGTON"}
	var text_w := {}
	for k in names:
		text_w[k] = ThemeDB.fallback_font.get_string_size(names[k], HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var lay := NodeLogic.valve_label_layout(dirs, widths, ctx.tier != "far", ctx.zoom, text_w, float(size))
	var dim := Palette.c("undead", float(MapLogic.cfg()["node_label_dim_alpha"]))
	for k in lay:
		var l: Dictionary = lay[k]
		text(cp + (l["off"] as Vector2) * ctx.px(1.0), names[k], size, dim, int(l["align"]), float(l["dy"]))


func _draw_pulse() -> void:
	var n := NodeLogic.ncfg()
	var cp := ctx.cov_pos
	var hw := ctx.hair_w()
	var hops := ctx.model.hops_of("covington")
	var ph: float = Pulse.phase(hops)
	var w: float = Pulse.wave(hops)
	var rings := int(n["source_rings"])
	for i in rings:
		var q := fposmod(ph + float(i) / rings, 1.0)
		glow_ring(cp, float(n["cov_half_px"]) + float(n["source_reach_px"]) * q,
			Palette.c("undead", pow(1.0 - q, 2.0) * float(n["source_alpha"])),
			maxf(float(n["source_width_px"]), hw), 1.0, float(n["source_halo_max_px"]))
	diamond(cp, float(n["cov_core_px"]) * (float(n["core_pulse_size_base"]) + float(n["core_pulse_size_wave"]) * w),
		Palette.c("undead_core", float(n["core_alpha_base"]) + float(n["core_alpha_wave"]) * w))
