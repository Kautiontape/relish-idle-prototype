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
## Set pieces: a fort whose ring is re-inking (ctx.reink) gets its chip when the ring is done; the
## garrison cleared (ctx.chip_fx) replaces line two with her counter-garrison draining to 0 (or the
## cleared word), then flips it (squashed to nothing and open again) to the live margin word.
## A chip that would sit over another fort's ring, name or tag, another chip or Relish's token
## takes another place around its own fort (IdleLogic.chip_layout).

var _layout_cache: Dictionary = {}
var _layout_key: Array = []


func _draw_static() -> void:
	if ctx.tier == "far":
		return
	var c := IdleLogic.cfg()
	for f in ctx.forts:
		if not bool(f.get("held", false)) or ctx.reink.has(str(f["id"])):
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
			var shift := _chip_shift(f, IdleLogic.cfg()) * ctx.zoom if IdleLogic.chip_shown(ctx.tier, ctx.zoom) else Vector2.ZERO
			out.append([str(f["id"]), IdleLogic.garrison_units(f), IdleLogic.chip_parts(f, str(ck["margin"]), ck), not NodeLogic.name_tag(f).is_empty(),
				Vector2(roundf(shift.x), roundf(shift.y)), ctx.reink.has(str(f["id"])), ctx.chip_fx.get(str(f["id"]), {})])
	return out


## Where fort `f`'s chip is drawn, in world px: its place under the name, moved clear of Relish's
## token. The callouts keep clear of this rect (MapCallouts._occupied).
func chip_world_rect(f: Dictionary) -> Rect2:
	var c := IdleLogic.cfg()
	var p := MapModel.to_vec(f["pos"])
	var w := _chip_width(f, ctx.model.clock_of(str(f["id"])), c)
	var base := IdleLogic.chip_rect(p, MapLogic.fort_radius(int(f["tier"])), ctx.zoom, not NodeLogic.name_tag(f).is_empty(), w)
	return Rect2(base.position + _chip_shift(f, c), base.size)


## How far the chip moves off its place under the name, in world px: to clear Relish's token and
## other forts' rings, labels and chips (IdleLogic.chip_layout). ZERO when its place is clear.
func _chip_shift(f: Dictionary, c: Dictionary) -> Vector2:
	var layout := _layout(c)
	if not layout.has(f["id"]):
		return Vector2.ZERO
	var p := MapModel.to_vec(f["pos"])
	var base := IdleLogic.chip_rect(p, MapLogic.fort_radius(int(f["tier"])), ctx.zoom, not NodeLogic.name_tag(f).is_empty(), _chip_width(f, ctx.model.clock_of(str(f["id"])), c))
	return (layout[f["id"]] as Rect2).position - base.position


## Every held fort's placed chip rect ({id: Rect2}, world px), IdleLogic.chip_layout over all the
## forts, recomputed only when IdleLogic.layout_key changes (the callouts and the drawing both ask,
## many times a frame). The token counts as standing at the centre of its coarse grid cell
## (callouts.token_key_px screen px, as MapCallouts._chip_signature), its radius padded by half the
## cell's diagonal so a layout kept for the cell still clears her.
func _layout(c: Dictionary) -> Dictionary:
	var shares: Dictionary = ctx.valve_shares if not ctx.valve_shares.is_empty() else ctx.model.hud.get("valve_target", ctx.model.hud.get("valve", {}))  # as MapCovington._shares
	var has_token := not ctx.relish.is_empty()
	var cell_w := ctx.px(float(MapLogic.cfg()["callouts"]["token_key_px"]))
	var cell := IdleLogic.token_cell(ctx.relish_pos, cell_w) if has_token else Vector2i.ZERO
	var widths := {}  # held fort id -> chip width (a clock ticks between revs): measured once, used for the key and the items
	var wlist: Array = []
	for g in ctx.forts:
		if bool(g.get("held", false)):
			var w := _chip_width(g, ctx.model.clock_of(str(g["id"])), c)
			widths[g["id"]] = w
			wlist.append(w)
	var key := IdleLogic.layout_key({"rev": ctx.model.rev, "zoom": ctx.zoom, "tier": ctx.tier, "forts": ctx.forts.size(), "has_token": has_token, "cell": cell,
		"margin_sig": ctx.model.margin_sig, "shares": shares, "backlog": float(ctx.vei.get("backlog", 0.0)), "vei_radius": ctx.vei_radius,
		"cov_pos": ctx.cov_pos, "vei_pos": ctx.vei_pos, "widths": wlist})
	if key == _layout_key:
		return _layout_cache
	var size := int(MapLogic.cfg()["font_label"])
	var font := ThemeDB.fallback_font  # what MapNodeLayer.draw_label measures with
	var items: Array = []
	for g in ctx.forts:
		var tag := NodeLogic.name_tag(g)
		var tier := int(g["tier"])
		var shown := NodeLogic.fort_label_shown(ctx.tier, tier)
		var tag_w := -1.0
		if shown and not tag.is_empty() and ctx.tier != "far":
			tag_w = font.get_string_size(str(tag["text"]), HORIZONTAL_ALIGNMENT_LEFT, -1, NodeLogic.tag_size()).x
		var held := bool(g.get("held", false))
		items.append({"id": g["id"], "pos": MapModel.to_vec(g["pos"]), "r": MapLogic.fort_radius(tier), "held": held, "second": not tag.is_empty(),
			"w": float(widths[g["id"]]) if held else 0.0,
			"name_w": font.get_string_size(str(g["name"]), HORIZONTAL_ALIGNMENT_LEFT, -1, size).x if shown else -1.0, "tag_w": tag_w})
	var tr := float(NodeLogic.relish_radii(ctx.zoom)["halo"]) + ctx.px(float(NodeLogic.ncfg()["relish_halo_max_px"]) * 0.5) + IdleLogic.token_pad(cell_w)
	var token := IdleLogic.token_center(cell, cell_w)
	# Covington's glyph, name and stream labels and Vei's reach and name, measured as their layers do
	var names := NodeLogic.node_names()
	var text_w := {}
	for k in names:
		text_w[k] = font.get_string_size(names[k], HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var nodes := IdleLogic.node_obstacles(ctx.cov_pos, ctx.vei_pos, ctx.vei_radius, float(ctx.vei.get("backlog", 0.0)), shares, NodeLogic.fort_centroid(ctx.forts), ctx.zoom, ctx.tier != "far", text_w)
	_layout_cache = IdleLogic.chip_layout(items, ctx.zoom, has_token, token, tr, nodes)
	_layout_key = key
	return _layout_cache


## The garrison counted out: GlyphLogic.garrison_fill of the chip's units over the fort's slots.
func _garrison(f: Dictionary, p: Vector2) -> void:
	var g := GlyphLogic.gcfg()
	var plan := GlyphLogic.garrison_plan(p, int(f["tier"]), ctx.zoom, IdleLogic.garrison_units(f))
	for gl in plan["glyphs"]:
		worker_glyph(gl["pos"], gl["dir"], float(g["garrison_glow"]), float(g["garrison_halo_max_px"]), float(plan["scale"]))
	if int(plan["plus"]) > 0:
		var size := int(g["garrison_font"])
		text(plan["plus_pos"], str(g["garrison_plus_fmt"]) % int(plan["plus"]), size, Palette.c("undead"), ALIGN_CENTER,
			size * float(NodeLogic.ncfg()["text_mid_ratio"]), true)


## The chip's plate width in screen px (its text and pads).
func _chip_width(f: Dictionary, ck: Dictionary, c: Dictionary) -> float:
	return float(_chip_metrics(f, ck, c)["w"])


## The chip's text parts and their widths in screen px: {parts, tail, w1 (line one), ww (the word), w (plate)}.
func _chip_metrics(f: Dictionary, ck: Dictionary, c: Dictionary) -> Dictionary:
	var parts := IdleLogic.chip_parts(f, str(ck["margin"]), ck, c)
	var fx: Dictionary = ctx.chip_fx.get(str(f["id"]), {})
	if fx.has("text"):  # the garrison cleared: line two is her counter (or the cleared word), no tail
		parts["word"] = str(fx["text"])
		parts["key"] = str(fx["key"])
		parts["fall"] = ""
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
	return {"parts": parts, "tail": tail, "w1": w1, "ww": ww, "w": maxf(w1, w2) + pad * 2.0}


## The chip: a plate (idle.plate_alpha, bordered in the margin's colour) centred under the name,
## drawn in screen px (counter-scaled by the zoom), with two lines in the type law's faces.
## It steps clear of Relish's token (IdleLogic.chip_place) when she stands over its place.
func _chip(f: Dictionary, c: Dictionary) -> void:
	var p := MapModel.to_vec(f["pos"])
	var anchor := p + Vector2(0.0, MapLogic.fort_radius(int(f["tier"])) + float(NodeLogic.ncfg()["label_off_px"])) + _chip_shift(f, c)
	var ck := ctx.model.clock_of(str(f["id"]))
	var m := _chip_metrics(f, ck, c)
	var parts: Dictionary = m["parts"]
	var tail := str(m["tail"])
	var w1 := float(m["w1"])
	var ww := float(m["ww"])
	var w := float(m["w"])
	var col := Palette.c(str(parts["key"]))
	var size := int(c["chip_font"])
	var pad := float(c["chip_pad_px"])
	var mass := MapType.mass_font()
	var rate := MapType.rate_font()
	var bold := _bold_font()
	var label := MapType.label_font()
	var top := IdleLogic.chip_top_px(not NodeLogic.name_tag(f).is_empty())
	var sc := 1.0 / maxf(ctx.zoom, 0.001)
	draw_set_transform(anchor, 0.0, Vector2(sc, sc))
	plate(self, Rect2(-w * 0.5, top, w, IdleLogic.chip_height_px()), Palette.c("ground", float(c["plate_alpha"])), col, float(c["chip_border_px"]))
	var x := -w * 0.5 + pad
	var y1 := top + float(c["chip_pad_y_px"]) + size * float(c["plate_ascent"])
	var y2 := y1 + float(c["chip_line_px"])
	draw_string(mass, Vector2(x, y1), parts["count"], HORIZONTAL_ALIGNMENT_LEFT, -1, size, Palette.c("text"))
	draw_string(rate, Vector2(x + w1 - rate.get_string_size(parts["rate"], HORIZONTAL_ALIGNMENT_LEFT, -1, size).x, y1), parts["rate"],
		HORIZONTAL_ALIGNMENT_LEFT, -1, size, Palette.c("text"))
	# line two, squashed about its middle while the garrison set piece flips it
	var sq := clampf(float(ctx.chip_fx.get(str(f["id"]), {}).get("squash", 1.0)), 0.0, 1.0)
	var mid := y2 - size * float(NodeLogic.ncfg()["text_mid_ratio"])
	draw_set_transform(anchor + Vector2(0.0, mid * sc * (1.0 - sq)), 0.0, Vector2(sc, sc * sq))
	if sq > 0.0:
		draw_string(bold, Vector2(x, y2), parts["word"], HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
		if tail != "":
			draw_string(label, Vector2(x + ww, y2), tail, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Palette.c("text"))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
