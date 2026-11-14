class_name MapFortIdle
extends MapNodeLayer
## Static layer: every held fort's garrison (your undead there, an upright integer) and its
## margin chip, SAFE / THIN / WILL FALL, left of the ring, mid and near zoom only. The words are
## the signal; their colour (undead, select, danger) is second. Text stays idle.chip_font screen px
## at every zoom. Margins come from the model (the projection while the valve is dragged).
## At near zoom the garrison is also counted out inside the ring: one undead worker glyph per unit
## (IdleLogic.garrison_units, the chip's number, so both change on the same redraw), on
## GlyphLogic's slots between the state glyph and the pips, the overflow past
## glyphs.garrison_glyph_max as "+N". Static: a lost unit drops one glyph on the next refresh.
## Tuning: configs/map_view.json "idle" and "glyphs".


func _draw_static() -> void:
	if ctx.tier == "far":
		return
	var c := IdleLogic.cfg()
	for f in ctx.forts:
		if bool(f.get("held", false)):
			_held_fort(f, c)


## Each held fort's garrison text and margin (the chips' only inputs besides the zoom).
func static_sig():
	var out: Array = []
	for f in ctx.forts:
		if bool(f.get("held", false)):
			out.append([str(f["id"]), IdleLogic.garrison_units(f), ctx.model.margin_of(str(f["id"]))])
	return out


func _held_fort(f: Dictionary, c: Dictionary) -> void:
	var p := MapModel.to_vec(f["pos"])
	var r := MapLogic.fort_radius(int(f["tier"]))
	var edge := p + Vector2(-(r + float(c["off_px"])) - ctx.px(float(c["gap_screen_px"])), 0.0)
	var gsize := int(c["garrison_font"])
	text(edge, IdleLogic.garrison_text(f, c), gsize, Palette.c("text"), ALIGN_RIGHT, -float(c["line_gap_px"]) * 0.5, true)
	if ctx.tier == "near":
		_garrison(f, p)
	var m := ctx.model.margin_of(str(f["id"]))
	if m != "":
		_chip(edge, IdleLogic.word(m), Palette.c(IdleLogic.color_key(m)), int(c["chip_font"]), float(c["line_gap_px"]) * 0.5 + int(c["chip_font"]), c)


## The garrison counted out: GlyphLogic.garrison_fill of the chip's units over the fort's slots.
func _garrison(f: Dictionary, p: Vector2) -> void:
	var g := GlyphLogic.gcfg()
	var slots := GlyphLogic.garrison_slots(p, int(f["tier"]), ctx.zoom)
	var fill := GlyphLogic.garrison_fill(IdleLogic.garrison_units(f), slots.size())
	for i in int(fill["shown"]):
		worker_glyph(slots[i]["pos"], slots[i]["dir"], float(g["garrison_glow"]), float(g["garrison_halo_max_px"]))
	if int(fill["plus"]) > 0:
		var size := int(g["garrison_font"])
		text(slots[int(fill["shown"])]["pos"], str(g["garrison_plus_fmt"]) % int(fill["plus"]), size, Palette.c("undead"), ALIGN_CENTER,
			size * float(NodeLogic.ncfg()["text_mid_ratio"]), true)


## The label plate (rounded, at idle.plate_alpha) with a coloured border and the word in the same
## colour, right-aligned at `anchor`, drawn in screen px (counter-scaled by the zoom). `dy` is the
## word's baseline.
func _chip(anchor: Vector2, word: String, col: Color, size: int, dy: float, c: Dictionary) -> void:
	var font := _bold_font()
	var sc := 1.0 / maxf(ctx.zoom, 0.001)
	draw_set_transform(anchor, 0.0, Vector2(sc, sc))
	var w := font.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var pad := float(c["chip_pad_px"])
	var rect := Rect2(-w - pad, dy - size * float(c["plate_ascent"]) - pad, w + pad * 2.0, size * float(c["plate_height"]) + pad * 2.0)
	plate(self, rect, Palette.c("ground", float(c["plate_alpha"])), col, float(c["chip_border_px"]))
	draw_string(font, Vector2(-w, dy), word, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
