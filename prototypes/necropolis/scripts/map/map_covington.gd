class_name MapCovington
extends MapNodeLayer
## Covington, the tempo's source (hop 0). Static layer: the undead diamond glyph, its label, the
## valve glyph (three stems whose widths are the committed WORK / WAR / FLOOD shares: the valve
## target, which the valve swing set piece tweens over a beat, brightening the stems) and the
## selection ring. The opening's cue (ctx.valve_cue) brightens the stems on the beat. Pulse layer: the source pulse rings and the core, on Pulse's phase and wave at hop 0.


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


## The valve's stem widths and brightness and the selection: all that changes between zooms. And where
## the open card puts her labels (NodeLogic.valve_label_sig: whole px), so a pan redraws her only when they move or hide.
func static_sig():
	var widths := NodeLogic.valve_widths(_shares())
	var lsig := []
	if not is_inf(float(ctx.panel.get("left", INF))):
		var dirs := NodeLogic.valve_dirs(ctx.cov_pos, NodeLogic.fort_centroid(ctx.forts), ctx.vei_pos)
		lsig = NodeLogic.valve_label_sig(_label_layout(dirs, widths), NodeLogic.panel_sx(ctx.panel, ctx.cov_pos.x, ctx.zoom), ctx.panel, ctx.zoom)
	return [widths, ctx.valve_bright, ctx.valve_cue, ctx.selected_id == "covington", lsig]


## Her labels laid out round the glyph and the stems (before the card shifts them).
func _label_layout(dirs: Dictionary, widths: Dictionary) -> Dictionary:
	var size := int(MapLogic.cfg()["font_label"])
	var names := NodeLogic.node_names()
	var text_w := {}
	for k in ["war", "flood", "work", "covington"]:
		text_w[k] = ThemeDB.fallback_font.get_string_size(names[k], HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	return NodeLogic.valve_label_layout(dirs, widths, ctx.tier != "far", ctx.zoom, text_w, float(size))


## The stems' shares: the set piece's (the committed valve, or its swing), else the view's target; no FLOOD
## stem once the game is won (HudLogic.glyph_shares).
func _shares() -> Dictionary:
	var s: Dictionary = ctx.valve_shares if not ctx.valve_shares.is_empty() else ctx.model.hud.get("valve_target", ctx.model.hud.get("valve", {}))
	return HudLogic.glyph_shares(s, ctx.model.hud)


## The valve: WAR toward the forts' centroid, FLOOD toward Vei, WORK a hook curling back home.
## Each stem is `valve_glyph_max_w x share` wide (never under a hairline); a share of 0 draws nothing.
## The four labels are placed by NodeLogic.valve_label_layout so none overlap.
func _valve(cp: Vector2, hw: float, n: Dictionary) -> void:
	var widths := NodeLogic.valve_widths(_shares())
	var dirs := NodeLogic.valve_dirs(cp, NodeLogic.fort_centroid(ctx.forts), ctx.vei_pos)
	var inner := float(n["valve_in_px"])
	var tip := inner + float(n["valve_len_px"])
	var sp := SetpieceLogic.cfg()
	var bright := maxf(ctx.valve_bright, ctx.valve_cue)
	var col := Palette.c("undead").lightened(float(sp["valve_lighten"]) * bright)
	var cap := float(n["valve_halo_max_px"])
	var glow := float(n["valve_glow"]) + float(sp["valve_glow_boost"]) * bright
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
	var names := NodeLogic.node_names()
	var lay := _label_layout(dirs, widths)
	lay = NodeLogic.shift_valve_labels(lay, NodeLogic.panel_sx(ctx.panel, cp.x, ctx.zoom), ctx.panel, ctx.zoom)  # clear of the open card and her glyph, or hidden
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
