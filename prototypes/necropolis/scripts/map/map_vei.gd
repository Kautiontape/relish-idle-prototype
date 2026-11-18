class_name MapVei
extends MapNodeLayer
## Vei's domain (hop 2). Static layer: her core, the backlog as a countable stack of undead rings
## (with a "+N" past the cap), the odds number with the differential's sign and the drain time,
## her label and the selection ring; plus the digestion rings, dashed ring children that the
## nodes layer turns at her capacity (a node's rotation: no redraw per frame). Pulse layer: her
## outer ring on the beat at hop 2 and the tempo ring that leaves it.


## One dashed digestion ring; drawn once, then only its rotation changes.
class DigestRing extends Node2D:
	var layer: MapVei
	var index := 0

	func _draw() -> void:
		layer.draw_digest(self, index)


var _ring_key := ""  # radius + hairline the digestion rings were last drawn for


func _draw_static() -> void:
	var n := NodeLogic.ncfg()
	var vp := ctx.vei_pos
	var hw := ctx.hair_w()
	var ro := NodeLogic.vei_struct_radius(ctx.vei_radius)
	draw_circle(vp, float(n["vei_core_px"]), Palette.c("vei"))

	var b := NodeLogic.backlog_rings(ctx.model.drawn_backlog())
	var first := ro + float(n["backlog_first_gap_px"])
	var step := float(n["backlog_step_px"])
	for i in int(b["rings"]):
		glow_ring(vp, first + i * step, Palette.c("undead"), maxf(float(n["backlog_width_px"]), hw),
			float(n["backlog_glow"]), float(n["backlog_halo_max_px"]))
	var r_out := first + maxi(int(b["rings"]) - 1, 0) * step
	var size := int(MapLogic.cfg()["font_label"])
	if int(b["overflow"]) > 0:
		text(vp + Vector2.from_angle(deg_to_rad(float(n["backlog_overflow_deg"]))) * (r_out + ctx.px(float(n["overflow_gap_px"]))), "+%d" % int(b["overflow"]), size,
			Palette.c("undead"), ALIGN_LEFT, 0.0, true)

	# the reading: odds as an integer percent, then the differential's sign (labelled as her strain) and the drain time
	var line := float(n["odds_line_px"])
	var rs := NodeLogic.vei_readout_shift(vp.x, r_out, _readout_widths(), ctx.zoom, ctx.panel)  # clear of the open card, or hidden
	if not bool(rs["hidden"]) and _readout_shown():
		var x0 := vp.x + r_out + float(n["odds_gap_px"]) + ctx.px(float(rs["dx"]))
		text(Vector2(x0, vp.y), "ODDS", size, Palette.c("text_dim"), ALIGN_LEFT, -line)
		text(Vector2(x0, vp.y), NodeLogic.fmt_odds(float(ctx.readout.get("odds", 0.0))), int(n["font_odds"]), Palette.c("vei"), ALIGN_LEFT, size * float(n["odds_baseline_ratio"]), true)
		text(Vector2(x0, vp.y), _strain(), int(n["font_odds_sub"]), Palette.c("text"), ALIGN_LEFT, line * float(n["drain_line_mult"]))
	var vname := str(NodeLogic.node_names()["vei"])
	var vs := NodeLogic.vei_name_shift(vp.x, r_out, MapNodeLayer.label_width(vname, size, false), size, ctx.zoom, ctx.panel)  # clear of the open card, or hidden
	if not bool(vs["hidden"]):
		text(Vector2(vp.x - r_out - float(n["odds_gap_px"]) + ctx.px(float(vs["dx"])), vp.y), vname, size,
			Palette.c("vei", float(MapLogic.cfg()["node_label_dim_alpha"])), ALIGN_RIGHT, size * float(n["text_mid_ratio"]))
	if ctx.selected_id == "vei":
		draw_arc(vp, r_out + float(n["vei_select_pad_px"]), 0.0, TAU, int(MapLogic.cfg()["ring_samples"]), Palette.c("select"), maxf(float(n["select_width_px"]), hw))


## The backlog stack, the reading's text and the selection: all that changes between zooms. And where
## the open card puts her name and readout (NodeLogic.vei_label_sig: whole px), so a pan redraws her only when they move or hide.
func static_sig():
	var r := ctx.readout
	var lsig := []
	if not is_inf(float(ctx.panel.get("left", INF))):
		var size := int(MapLogic.cfg()["font_label"])
		var vname := str(NodeLogic.node_names()["vei"])
		lsig = NodeLogic.vei_label_sig(ctx.vei_pos.x, _r_out(), MapNodeLayer.label_width(vname, size, false), _readout_widths(), size, ctx.zoom, ctx.panel)
	return [NodeLogic.backlog_rings(ctx.model.drawn_backlog()), ctx.vei_radius,
		NodeLogic.fmt_odds(float(r.get("odds", 0.0))), int(r.get("sign", 0)),
		NodeLogic.drain_line(float(r.get("backlog", 0.0)), float(r.get("drain_s", -1.0))), ctx.selected_id == "vei", lsig, _readout_shown()]


## Whether her ODDS readout shows: not in a won game (HudLogic.vei_readout_shown).
func _readout_shown() -> bool:
	return HudLogic.vei_readout_shown(ctx.model.hud)


## The outer ring of her backlog stack (world px): where the readout and her name start.
func _r_out() -> float:
	var n := NodeLogic.ncfg()
	var b := NodeLogic.backlog_rings(ctx.model.drawn_backlog())
	return NodeLogic.vei_struct_radius(ctx.vei_radius) + float(n["backlog_first_gap_px"]) + maxi(int(b["rings"]) - 1, 0) * float(n["backlog_step_px"])


## Where her ODDS readout is drawn, in world px (Rect2() while hidden): the tooltip plate keeps off it.
func readout_rect() -> Rect2:
	if not _readout_shown():
		return Rect2()
	return NodeLogic.vei_readout_rect(ctx.vei_pos, _r_out(), _readout_widths(), ctx.zoom, ctx.panel)


## The strain line under the odds.
func _strain() -> String:
	return NodeLogic.strain_line(int(ctx.readout.get("sign", 0)), float(ctx.readout.get("backlog", 0.0)), float(ctx.readout.get("drain_s", -1.0)))


## The readout's three texts' widths in screen px: the ODDS word, the percent (bold), the strain line.
func _readout_widths() -> Array:
	var n := NodeLogic.ncfg()
	var size := int(MapLogic.cfg()["font_label"])
	return [MapNodeLayer.label_width("ODDS", size, false), MapNodeLayer.label_width(NodeLogic.fmt_odds(float(ctx.readout.get("odds", 0.0))), int(n["font_odds"])),
		MapNodeLayer.label_width(_strain(), int(n["font_odds_sub"]), false)]


## (Re)creates and redraws the digestion rings when the structure's radius, her position or the
## hairline moved. Called by MapNodes on a model refresh or a camera change, never from _draw.
func sync_rings() -> void:
	if ctx == null or ctx.model == null or ctx.model.realm.is_empty():
		return
	var ro := NodeLogic.vei_struct_radius(ctx.vei_radius)
	var key := "%.2f/%.3f/%s" % [ro, ctx.hair_w(), ctx.vei_pos]
	var specs: Array = NodeLogic.ncfg()["vei_rings"]
	if get_child_count() != specs.size():
		for c in get_children():
			remove_child(c)
			c.queue_free()
		for i in specs.size():
			var ring := DigestRing.new()
			ring.layer = self
			ring.index = i
			add_child(ring)
		_ring_key = ""
	if key == _ring_key:
		return
	_ring_key = key
	for c in get_children():
		c.position = ctx.vei_pos
		c.queue_redraw()


## F6 reloaded the config: the ring specs may have changed, so the next sync redraws.
func reset_rings() -> void:
	_ring_key = "stale"


## Draws digestion ring `i` around its own origin: `dashes` chords at `duty` of the circle, the
## LineGlow stack (capped) as one multiline per stroke.
func draw_digest(ci: CanvasItem, i: int) -> void:
	if ctx == null or ctx.model == null or ctx.model.realm.is_empty():
		return
	var n := NodeLogic.ncfg()
	var spec: Array = n["vei_rings"][i]
	var r := NodeLogic.vei_struct_radius(ctx.vei_radius) * float(spec[0])
	var dashes := int(spec[1])
	var duty := float(spec[2])
	var pts := PackedVector2Array()
	for k in dashes:
		var a0 := TAU * k / dashes
		var a1 := a0 + TAU * duty / dashes
		var am := (a0 + a1) * 0.5
		pts.append(Vector2.from_angle(a0) * r)
		pts.append(Vector2.from_angle(am) * r)
		pts.append(Vector2.from_angle(am) * r)
		pts.append(Vector2.from_angle(a1) * r)
	for l in NodeLogic.capped_layers(Palette.c("vei"), maxf(float(n["vei_ring_width_px"]), ctx.hair_w()),
			float(n["vei_glow"]), float(n["vei_halo_max_px"])):
		ci.draw_multiline(pts, l[1], l[0])


## Turns the digestion rings: ring i at angle x its multiplier (negative turns the other way).
func spin(angle: float) -> void:
	var specs: Array = NodeLogic.ncfg()["vei_rings"]
	for i in mini(get_child_count(), specs.size()):
		(get_child(i) as Node2D).rotation = angle * float(specs[i][3])


func _draw_pulse() -> void:
	var n := NodeLogic.ncfg()
	var vp := ctx.vei_pos
	var ro := NodeLogic.vei_struct_radius(ctx.vei_radius)
	var hw := ctx.hair_w()
	var hops := ctx.model.hops_of("vei")
	var w: float = Pulse.wave(hops)
	var ph: float = Pulse.phase(hops)
	var mn := float(n["vei_wave_min"])
	glow_ring(vp, ro, Palette.c("vei", mn + (1.0 - mn) * w), maxf(float(n["vei_ring_width_px"]), hw), float(n["vei_glow"]),
		float(n["vei_halo_max_px"]), Palette.c("vei"))
	glow_ring(vp, ro + float(n["vei_beat_reach_px"]) * ph, Palette.c("vei", pow(1.0 - ph, 2.0) * float(n["source_alpha"])),
		maxf(float(n["source_width_px"]), hw), 1.0, float(n["source_halo_max_px"]))
