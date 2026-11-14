class_name MapFortRing
extends MapNodeLayer
## The fortresses. Static layer: capacity hairline, tier notches, the dark track with the living /
## undead / dead arcs, the countable pips, the held re-ink and countdown, the simulacrum, the
## selection ring and the labels. Pulse layer: the state glyph at the centre (on the fort's beat,
## hop 1; NodeLogic.fort_state), the tithe countdown ring and the first-dungeon tempo ring.
## Radii from the fort's edge r: arcs r-4, pips r-12, hairline r, notches r..r+4, held r+7.5,
## tithe r+12.5, selection r+19, the REDIRECT lane ring r+24 (routes).


func _draw_static() -> void:
	for f in ctx.forts:
		_static_fort(f)


func _static_fort(f: Dictionary) -> void:
	var n := NodeLogic.ncfg()
	var p := MapModel.to_vec(f["pos"])
	var tier := int(f["tier"])
	var r := MapLogic.fort_radius(tier)
	var lit: bool = ctx.lit.has(f["id"])
	var dead_col := Palette.c("dead_lit" if lit else "dead")
	var hw := ctx.hair_w()
	var seg := LineGlow.segments(r, TAU)

	# the dark track and the arcs: living, undead, dead from 12 o'clock; the rest stays dark
	var ra := r - float(n["arc_inset_px"])
	var aw := float(n["arc_width_px"])
	draw_arc(p, ra, 0.0, TAU, seg, Palette.c("ring_track"), aw)
	var fr := NodeLogic.arc_fracs(f)
	var a0 := -PI * 0.5
	for k in NodeLogic.MATTERS:
		var frac: float = fr[k]
		if frac < float(n["arc_min_frac"]):
			continue
		var a1: float = a0 + TAU * frac
		if k == "dead":
			LineGlow.matte_arc(self, p, ra, a0, a1, dead_col, aw)
		else:
			glow_arc(p, ra, a0, a1, Palette.c(k), aw, float(n["arc_glow"]), float(n["arc_halo_max_px"]))
		a0 = a1

	# pips: one per pip_pct of capacity per matter, in arc order; empty slots are small dim dots
	if NodeLogic.pips_shown(ctx.tier):
		var layout := NodeLogic.pip_layout(f)
		var rp := r - float(n["pip_inset_px"])
		var pr := maxf(float(n["pip_radius_px"]), ctx.px(float(n["pip_min_screen_px"])) * 0.5)
		for i in layout.size():
			var at := p + Vector2.from_angle(NodeLogic.pip_angle(i)) * rp
			var m: String = layout[i]
			if m == "":
				draw_circle(at, pr * float(n["pip_empty_ratio"]), Palette.c("ring_track"))
			elif m == "dead":
				draw_circle(at, pr, dead_col)
			else:
				draw_circle(at, pr, Palette.c(m))

	# tier notches on the outer hairline
	var ticks := PackedVector2Array()
	for a in NodeLogic.notch_angles(tier):
		var d := Vector2.from_angle(a)
		ticks.append(p + d * r)
		ticks.append(p + d * (r + float(n["notch_len_px"])))
	if ticks.size() > 0:
		draw_multiline(ticks, Palette.c(str(n["hairline_key"]), float(n["hairline_alpha"])), maxf(float(n["notch_width_px"]), hw))

	# the outer hairline: capacity. Held: re-inked undead green, with the grace countdown outside it.
	if bool(f.get("held", false)):
		glow_ring(p, r, Palette.c("undead"), hw, 1.0, float(n["arc_halo_max_px"]))
		var rh := r + float(n["held_off_px"])
		var hs := LineGlow.segments(rh, TAU)
		draw_arc(p, rh, 0.0, TAU, hs, Palette.c("undead", float(n["held_track_alpha"])), hw)
		var left := NodeLogic.held_fraction(f, ctx.flip)
		if left > 0.0:
			glow_arc(p, rh, -PI * 0.5, -PI * 0.5 + TAU * left, Palette.c("undead"), maxf(float(n["held_width_px"]), hw),
				float(n["held_glow"]), float(n["tithe_halo_max_px"]))
	else:
		draw_arc(p, r, 0.0, TAU, seg, Palette.c(str(n["hairline_key"]), float(n["hairline_alpha"])), hw)

	if float(f.get("simulacrum_charges", 0.0)) > 0.0:
		diamond(p + Vector2.from_angle(deg_to_rad(float(n["sim_angle_deg"]))) * r, maxf(float(n["sim_size_px"]), ctx.px(float(n["sim_min_screen_px"]))), Palette.c("relish"))

	if ctx.selected_id == f["id"]:
		draw_arc(p, r + float(n["select_pad_px"]), 0.0, TAU, int(MapLogic.cfg()["ring_samples"]), Palette.c("select"), maxf(float(n["select_width_px"]), hw))

	if NodeLogic.fort_label_shown(ctx.tier, tier):
		var at := p + Vector2(0.0, r + float(n["label_off_px"]))
		var size := int(MapLogic.cfg()["font_label"])
		text(at, str(f["name"]), size, Palette.c("text_dim", float(MapLogic.cfg()["node_label_dim_alpha"])), ALIGN_CENTER, size)
		if NodeLogic.first_dungeon_pulse(f) and ctx.tier != "far":
			text(at, str(n["label_first_dungeon"]), size, Palette.c("relish"), ALIGN_CENTER, size + float(n["label_line_px"]))


func _draw_pulse() -> void:
	var n := NodeLogic.ncfg()
	var hw := ctx.hair_w()
	for f in ctx.forts:
		var hops := ctx.model.hops_of(f["id"])
		var w: float = Pulse.wave(hops)
		var ph: float = Pulse.phase(hops)
		var p := MapModel.to_vec(f["pos"])
		var r := MapLogic.fort_radius(int(f["tier"]))
		_state_glyph(f, p, w, n)
		var mode := NodeLogic.tithe_mode(f)
		if mode != "":
			_tithe(f, p, r + float(n["tithe_off_px"]), mode, w, hw, n)
		if NodeLogic.first_dungeon_pulse(f):
			var rr := r + float(n["first_reach_px"]) * ph
			glow_ring(p, rr, Palette.c("relish", pow(1.0 - ph, 2.0) * float(n["first_alpha"])),
				maxf(float(n["first_width_px"]), hw), 1.0, float(n["first_halo_max_px"]))


## The fort's one glanceable state (NodeLogic.fort_state), state_glyph_px across on screen at any
## zoom, a distinct SHAPE per state so greyscale still tells them apart; colour is second:
##   hers       a solid living square;
##   contested  an hourglass, the undead's half above, the living's below;
##   emptied    a matte dead ring (never glows, never pulses);
##   held       a diamond: solid (safe), hollow (thin), hollow struck through by a danger
##              stroke (will fall). Its margin is the model's, the same one the chip shows.
## A tithe on the way adds a living triangle badge at the upper right, over any state.
func _state_glyph(f: Dictionary, p: Vector2, w: float, n: Dictionary) -> void:
	var st := NodeLogic.fort_state(f, ctx.model.margin_of(str(f["id"])))
	var h := NodeLogic.state_glyph_half(ctx.zoom)
	var a := float(n["state_alpha_base"]) + float(n["state_alpha_wave"]) * w
	var sw := ctx.px(float(n["state_stroke_px"]))
	var glow := float(n["state_glow"])
	var cap := ctx.px(float(n["state_halo_max_px"]))
	var q := h * float(n["state_square_ratio"])
	match st:
		NodeLogic.HERS:
			draw_rect(Rect2(p - Vector2(q, q), Vector2(q, q) * 2.0), Palette.c("living", a), true)
		NodeLogic.CONTESTED:
			draw_colored_polygon(PackedVector2Array([p + Vector2(-q, -q), p + Vector2(q, -q), p]), Palette.c("undead", a))
			draw_colored_polygon(PackedVector2Array([p, p + Vector2(q, q), p + Vector2(-q, q)]), Palette.c("living", a))
		NodeLogic.EMPTIED:
			LineGlow.matte_ring(self, p, h * float(n["state_ring_ratio"]), Palette.c("dead"), sw)
		IdleLogic.SAFE:
			diamond(p, h, Palette.c("undead", a))
		_:
			var d := h - sw * 0.5
			glow_poly(PackedVector2Array([p + Vector2(0, -d), p + Vector2(d, 0), p + Vector2(0, d), p + Vector2(-d, 0), p + Vector2(0, -d)]),
				Palette.c("undead", a), sw, glow, cap)
			if st == IdleLogic.WILL_FALL:
				var e := Vector2(h, h) * float(n["state_slash_ext"])
				glow_poly(PackedVector2Array([p - e, p + e]), Palette.c("danger"), ctx.px(float(n["state_slash_px"])), glow, cap)
	if NodeLogic.tithe_badge(f):
		_badge(p + Vector2(h, -h), n)


## The tithe badge: a living triangle on a ground backing that cuts it clear of the glyph.
func _badge(c: Vector2, n: Dictionary) -> void:
	var b := ctx.px(float(n["state_badge_px"]))
	var back := b + ctx.px(float(n["state_badge_back_px"])) * 2.0
	for k in [[back, Palette.c("ground")], [b, Palette.c("living")]]:
		var s: float = k[0]
		draw_colored_polygon(PackedVector2Array([c + Vector2(0.0, -s * 0.6), c + Vector2(s * 0.55, s * 0.4), c + Vector2(-s * 0.55, s * 0.4)]), k[1])


## The tithe warning: an orange ring whose sweep is the time left, pulsing on the fort's beat,
## with the ETA beside it; while the wave is on, a solid danger ring.
func _tithe(f: Dictionary, p: Vector2, ra: float, mode: String, w: float, hw: float, n: Dictionary) -> void:
	var tw := maxf(float(n["tithe_width_px"]), hw)
	var cap := float(n["tithe_halo_max_px"])
	var size := int(n["font_tithe"])
	var at := p + Vector2(ra + ctx.px(float(n["tithe_text_gap_px"])), 0.0)
	if mode == "wave":
		glow_ring(p, ra, Palette.c("danger", float(n["wave_ring_min"]) + (1.0 - float(n["wave_ring_min"])) * w), tw, 1.0, cap)
		text(at, "WAVE", size, Palette.c("danger"), ALIGN_LEFT, size * float(n["text_mid_ratio"]))
		return
	var a := float(n["tithe_pulse_min"]) + (1.0 - float(n["tithe_pulse_min"])) * w
	var eta := float(f["tithe"].get("eta_s", -1.0))
	draw_arc(p, ra, 0.0, TAU, LineGlow.segments(ra, TAU), Palette.c("living", float(n["tithe_track_alpha"])), hw)
	var frac := NodeLogic.tithe_fraction(eta)
	if frac > 0.0:
		glow_arc(p, ra, -PI * 0.5, -PI * 0.5 + TAU * frac, Palette.c("living", a), tw, 1.0, cap, Palette.c("living_core", a))
	text(at, NodeLogic.fmt_eta(eta), size, Palette.c("living"), ALIGN_LEFT, size * float(n["text_mid_ratio"]), true)
