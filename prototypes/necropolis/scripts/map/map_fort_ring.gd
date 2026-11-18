class_name MapFortRing
extends MapNodeLayer
## The fortresses. Static layer, one per fort (`fort_id`, so a refresh redraws only the forts whose
## drawing changed: static_sig): the held core, capacity hairline, tier notches, the dark track
## with the living / undead / dead arcs, the countable pips, the held re-ink and countdown, the
## simulacrum, the raid marker, the selection ring and the labels. Ownership reads by weight, so it
## survives greyscale: forts you hold (held only, never overrun) draw the outer ring
## NodeLogic.ring_weight heavy and fill their core (NodeLogic.has_core); hers, contested, emptied
## and overrun keep the hairline and an open core. A fort in the model's raid set (MapModel.raid_why: NextLogic.raid_set, ranked
## and capped at raid_tag_max) carries a ▲ loot pip in `select` on its ring and, at mid and near
## zoom, the word "raid": a shape and a word, never colour alone. While the flip set
## piece re-inks a fort (ctx.reink), its outer ring is drawn as segments turning from living
## orange (hairline) to undead green (held weight) from 12 o'clock, and the fort draws as its old
## state until it is done. Pulse layer (every fort): the tithe countdown ring and the
## first-dungeon tempo ring, on the forts' beat (hop 1). The state glyphs: MapFortGlyph.
## Radii from the fort's edge r: arcs r-4, pips r-12, hairline r, notches r..r+4, held r+7.5,
## tithe r+12.5, selection r+19, the REDIRECT lane ring r+24 (routes).


## The fort a static layer draws (MapNodes gives each fort its own).
var fort_id := ""


func _draw_static() -> void:
	var f: Dictionary = ctx.model.fort(fort_id)
	if not f.is_empty():
		_static_fort(_piled(f))


## The fort with the dead pile it draws now (eased after a catch-up, ctx.dead_shown).
func _piled(f: Dictionary) -> Dictionary:
	if not ctx.dead_shown.has(fort_id):
		return f
	return NodeLogic.with_dead(f, float(ctx.dead_shown[fort_id]))


## What this fort's rings draw (NodeLogic.fort_static_sig), its selection and Relish's light. With
## the zoom and tier (a redraw on their own), MapNodes redraws it only when this changes.
func static_sig():
	var f: Dictionary = ctx.model.fort(fort_id)
	return [NodeLogic.fort_static_sig(_piled(f), ctx.flip, _state(f), ctx.model.raid_why(fort_id), ctx.tier), ctx.selected_id == fort_id, ctx.lit.has(fort_id),
		ctx.reink.get(fort_id, {})]


## The state the fort draws as: its live one, or the pre-flip one while its ring re-inks.
func _state(f: Dictionary) -> String:
	var rk: Dictionary = ctx.reink.get(str(f.get("id", "")), {})
	if not rk.is_empty():
		return str(rk["from"])
	return NodeLogic.fort_state(f, ctx.model.margin_of(str(f.get("id", ""))))


func _static_fort(f: Dictionary) -> void:
	var n := NodeLogic.ncfg()
	var p := MapModel.to_vec(f["pos"])
	var tier := int(f["tier"])
	var r := MapLogic.fort_radius(tier)
	var lit: bool = ctx.lit.has(f["id"])
	var dead_col := Palette.c("dead_lit" if lit else "dead")
	var hw := ctx.hair_w()
	var seg := LineGlow.segments(r, TAU)
	var state := _state(f)
	var ra := r - float(n["arc_inset_px"])
	var aw := float(n["arc_width_px"])

	# your fort's filled core: undead at held_core_alpha up to the track (pips and glyph on top)
	if NodeLogic.has_core(state):
		draw_circle(p, ra - aw * 0.5 - float(n["held_core_inset_px"]), Palette.c("undead", float(n["held_core_alpha"])))

	# the dark track and the arcs: living, undead, dead from 12 o'clock; the rest stays dark
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

	# the outer ring: capacity, ring_weight heavy where your undead hold the fort. Held: re-inked
	# undead green, with the grace countdown outside it.
	var ow := hw * NodeLogic.ring_weight(state, ctx.tier)
	var rk: Dictionary = ctx.reink.get(fort_id, {})
	if not rk.is_empty():
		_reink(p, r, rk, hw, n)
	elif bool(f.get("held", false)):
		glow_ring(p, r, Palette.c("undead"), ow, 1.0, float(n["arc_halo_max_px"]))
		var rh := r + float(n["held_off_px"])
		var hs := LineGlow.segments(rh, TAU)
		draw_arc(p, rh, 0.0, TAU, hs, Palette.c("undead", float(n["held_track_alpha"])), hw)
		var left := NodeLogic.held_fraction(f, ctx.flip)
		if left > 0.0:
			glow_arc(p, rh, -PI * 0.5, -PI * 0.5 + TAU * left, Palette.c("undead"), maxf(float(n["held_width_px"]), hw),
				float(n["held_glow"]), float(n["tithe_halo_max_px"]))
	else:
		draw_arc(p, r, 0.0, TAU, seg, Palette.c(str(n["hairline_key"]), float(n["hairline_alpha"])), ow)

	if float(f.get("simulacrum_charges", 0.0)) > 0.0:
		diamond(p + Vector2.from_angle(deg_to_rad(float(n["sim_angle_deg"]))) * r, maxf(float(n["sim_size_px"]), ctx.px(float(n["sim_min_screen_px"]))), Palette.c("relish"))

	if ctx.model.raid_why(str(f["id"])) != "":
		_raid_marker(p, r, n)

	if ctx.selected_id == f["id"]:
		draw_arc(p, r + float(n["select_pad_px"]), 0.0, TAU, int(MapLogic.cfg()["ring_samples"]), Palette.c("select"), maxf(float(n["select_width_px"]), hw))

	if NodeLogic.fort_label_shown(ctx.tier, tier):
		var at := p + Vector2(0.0, r + float(n["label_off_px"]))
		var size := int(MapLogic.cfg()["font_label"])
		text(at, str(f["name"]), size, Palette.c(NodeLogic.fort_label_key(ctx.tier), float(MapLogic.cfg()["node_label_dim_alpha"])), ALIGN_CENTER, size)
		var tag := NodeLogic.name_tag(f)
		if not tag.is_empty() and ctx.tier != "far":
			text(at, str(tag["text"]), NodeLogic.tag_size(), Palette.c(str(tag["key"])), ALIGN_CENTER, size + float(n["label_line_px"]))


## The flip's re-ink: `total` segments of the outer ring from 12 o'clock clockwise, the first
## `switched` re-inked in undead green at the held weight, the rest still living orange (hairline).
func _reink(p: Vector2, r: float, rk: Dictionary, hw: float, n: Dictionary) -> void:
	var total := int(rk["total"])
	var switched := int(rk["switched"])
	var cap := float(n["arc_halo_max_px"])
	for i in total:
		var a := SetpieceLogic.segment_arc(i, total)
		if i < switched:
			glow_arc(p, r, a.x, a.y, Palette.c("undead"), hw * NodeLogic.ring_weight(IdleLogic.SAFE, ctx.tier), 1.0, cap)
		else:
			glow_arc(p, r, a.x, a.y, Palette.c("living"), hw, 1.0, cap)


## The raid marker: a ▲ in `select` on a ground backing (raid_pip_px screen px), on the ring at
## raid_angle_deg (9 o'clock: clear of the tithe countdown, the siege, the simulacrum and Relish),
## and the word outward of it at mid and near zoom.
func _raid_marker(p: Vector2, r: float, n: Dictionary) -> void:
	var dir := Vector2.from_angle(deg_to_rad(float(n["raid_angle_deg"])))
	var c := p + dir * r
	var b := ctx.px(float(n["raid_pip_px"]))
	var back := b + ctx.px(float(n["raid_pip_back_px"])) * 2.0
	for k in [[back, Palette.c("ground")], [b, Palette.c("select")]]:
		var hs: float = float(k[0]) * 0.5
		draw_colored_polygon(PackedVector2Array([c + Vector2(0.0, -hs), c + Vector2(hs, hs), c + Vector2(-hs, hs)]), k[1])
	if ctx.tier != "far":  # the word outward of the pip, on the side it points to
		var size := int(MapLogic.cfg()["font_label"])
		var out := back * 0.5 + ctx.px(float(n["raid_word_gap_px"]))
		text(c + Vector2(signf(dir.x) * out if absf(dir.x) > 0.01 else out, 0.0), str(n["raid_word"]), size, Palette.c("select"),
			ALIGN_RIGHT if dir.x < -0.01 else ALIGN_LEFT, size * float(n["text_mid_ratio"]), true)


func _draw_pulse() -> void:
	var n := NodeLogic.ncfg()
	var hw := ctx.hair_w()
	for f in ctx.forts:
		var hops := ctx.model.hops_of(f["id"])
		var w: float = Pulse.wave(hops)
		var ph: float = Pulse.phase(hops)
		var p := MapModel.to_vec(f["pos"])
		var r := MapLogic.fort_radius(int(f["tier"]))
		var mode := NodeLogic.tithe_mode(f)
		if mode == "wave" or mode == "warning":
			_tithe(f, p, r + float(n["tithe_off_px"]), mode, w, hw, n)
		if NodeLogic.first_dungeon_pulse(f):
			var rr := r + float(n["first_reach_px"]) * ph
			glow_ring(p, rr, Palette.c("relish", pow(1.0 - ph, 2.0) * float(n["first_alpha"])),
				maxf(float(n["first_width_px"]), hw), 1.0, float(n["first_halo_max_px"]))


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
