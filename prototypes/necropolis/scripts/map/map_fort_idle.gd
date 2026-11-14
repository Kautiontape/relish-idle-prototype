class_name MapFortIdle
extends MapNodeLayer
## Static layer: every held fort's chip, one plate hanging just under the fort's own name (and
## under Old Sluice's first-dungeon line when it shows), at mid and near zoom from
## idle.chip_min_zoom. Line one: the garrison as an upright count and its signed rate in the rate
## face ("garrison 64  −0.4/s"); line two: the margin word in its colour (SAFE / THIN / WILL FALL)
## and, while the rate is negative, "falls in ~2 h". The plate is bordered in the margin's
## colour: word + colour + border. Text stays idle.chip_font screen px at every zoom. Margins,
## rates and clocks are MapModel.clock_of's (the projection while the valve is dragged).
## At near zoom the garrison is also counted out inside the ring: one undead worker glyph per unit
## (IdleLogic.garrison_units, the chip's number, so both change on the same redraw), on
## GlyphLogic's slots between the state glyph and the pips, the overflow past
## glyphs.garrison_glyph_max as "+N". Static: a lost unit drops one glyph on the next refresh.
## Placement: IdleLogic.chip_top_px / chip_height_px. Tuning: configs/map_view.json "idle", "glyphs".


func _draw_static() -> void:
	if ctx.tier == "far":
		return
	var c := IdleLogic.cfg()
	for f in ctx.forts:
		if not bool(f.get("held", false)):
			continue
		if ctx.tier == "near":
			_garrison(f, MapModel.to_vec(f["pos"]))
		if IdleLogic.chip_shown(ctx.tier, ctx.zoom):
			_chip(f, c)


## Each held fort's chip text and garrison count (the chips' only inputs besides the zoom).
func static_sig():
	var out: Array = []
	for f in ctx.forts:
		if bool(f.get("held", false)):
			var ck := ctx.model.clock_of(str(f["id"]))
			out.append([str(f["id"]), IdleLogic.garrison_units(f), IdleLogic.chip_parts(f, str(ck["margin"]), ck), NodeLogic.first_dungeon_pulse(f)])
	return out


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


## The chip: a plate (idle.plate_alpha, bordered in the margin's colour) centred under the name,
## drawn in screen px (counter-scaled by the zoom), with two lines in the type law's faces.
func _chip(f: Dictionary, c: Dictionary) -> void:
	var p := MapModel.to_vec(f["pos"])
	var anchor := p + Vector2(0.0, MapLogic.fort_radius(int(f["tier"])) + float(NodeLogic.ncfg()["label_off_px"]))
	var ck := ctx.model.clock_of(str(f["id"]))
	var parts := IdleLogic.chip_parts(f, str(ck["margin"]), ck, c)
	var col := Palette.c(str(parts["key"]))
	var size := int(c["chip_font"])
	var pad := float(c["chip_pad_px"])
	var gap := float(c["chip_rate_gap_px"])
	var mass := MapType.mass_font()
	var rate := MapType.rate_font()
	var bold := _bold_font()
	var label := MapType.label_font()
	var tail := (str(c["chip_sep"]) + str(parts["fall"])) if str(parts["fall"]) != "" else ""
	var w1 := mass.get_string_size(parts["count"], HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + gap + rate.get_string_size(parts["rate"], HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var ww := bold.get_string_size(parts["word"], HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var w2 := ww + label.get_string_size(tail, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var w := maxf(w1, w2) + pad * 2.0
	var top := IdleLogic.chip_top_px(NodeLogic.first_dungeon_pulse(f))
	var sc := 1.0 / maxf(ctx.zoom, 0.001)
	draw_set_transform(anchor, 0.0, Vector2(sc, sc))
	plate(self, Rect2(-w * 0.5, top, w, IdleLogic.chip_height_px()), Palette.c("ground", float(c["plate_alpha"])), col, float(c["chip_border_px"]))
	var x := -w * 0.5 + pad
	var y1 := top + float(c["chip_pad_y_px"]) + size * float(c["plate_ascent"])
	var y2 := y1 + float(c["chip_line_px"])
	draw_string(mass, Vector2(x, y1), parts["count"], HORIZONTAL_ALIGNMENT_LEFT, -1, size, Palette.c("text"))
	draw_string(rate, Vector2(x + w1 - rate.get_string_size(parts["rate"], HORIZONTAL_ALIGNMENT_LEFT, -1, size).x, y1), parts["rate"],
		HORIZONTAL_ALIGNMENT_LEFT, -1, size, Palette.c("text"))
	draw_string(bold, Vector2(x, y2), parts["word"], HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
	if tail != "":
		draw_string(label, Vector2(x + ww, y2), tail, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Palette.c("text"))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
