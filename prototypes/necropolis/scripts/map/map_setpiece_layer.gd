class_name MapSetpieceLayer
extends MapNodeLayer
## The set pieces' own marks, over the nodes in world space, from the items MapSetpieces hands
## it each frame (set_items); it keeps no time itself. Items:
##   {kind: "band", pts, key, core, width, glow, cap}  a stretch of a lane (the tithe tide, the
##       garrison's WAR pulse), LineGlow's capped stack with a pale core;
##   {kind: "ring", pos, r, key, alpha, width, cap}    the first flip's ripple, the garrison's burst;
##   {kind: "label", pos, text, size, key, alpha}      a callout on a plate, its baseline at pos.
##   {kind: "runs", pos, runs, size, alpha}            a line of runs ([{text, kind}], AwayLogic.spans) on a
##       plate, each in its MapType face (the finished build's callout), the plate's bottom centre at pos.
## Widths are screen px (never under a hairline); colours are Palette keys.

var items: Array = []


## The marks to draw now; redraws only when there are marks, or the last ones just went.
func set_items(a: Array) -> void:
	if a.is_empty() and items.is_empty():
		return
	items = a
	queue_redraw()


func _draw_pulse() -> void:
	var hw := ctx.hair_w()
	for it in items:
		match str(it["kind"]):
			"band":
				if (it["pts"] as PackedVector2Array).size() >= 2:
					glow_poly(it["pts"], Palette.c(str(it["key"])), maxf(ctx.px(float(it["width"])), hw), float(it["glow"]),
						ctx.px(float(it["cap"])), Palette.c(str(it["core"])))
			"ring":
				glow_ring(it["pos"], float(it["r"]), Palette.c(str(it["key"]), float(it["alpha"])), maxf(ctx.px(float(it["width"])), hw), 1.0,
					ctx.px(float(it["cap"])))
			"label":
				text(it["pos"], str(it["text"]), int(it["size"]), Palette.c(str(it["key"]), float(it["alpha"])), ALIGN_CENTER, 0.0, true)
			"runs":
				_draw_runs(it)


## A line of runs on a plate, in screen px at the world anchor `pos` (the plate's bottom centre):
## each run in its own face (MapType: the signed rate oblique, a count heavy, words regular), the
## way the away panel and the lane callouts set theirs. No fade of its own: `alpha` is the item's.
func _draw_runs(it: Dictionary) -> void:
	var c := SetpieceLogic.cfg()
	var size := int(it["size"])
	var a := float(it["alpha"])
	var pad := float(c["build_pad_px"])
	var lf := MapType.label_font()
	var rf := MapType.rate_font()
	var mf := MapType.mass_font()
	var runs: Array = it["runs"]
	var m := SetpieceLogic.build_metrics(runs, size)  # the same measure the placement used
	var widths: Array = m["widths"]
	var space := float(m["space"])
	var total := float(m["total"])
	var h := float(m["h"])
	var asc := float(m["asc"])
	var sc := 1.0 / maxf(ctx.zoom, 0.001)
	draw_set_transform(it["pos"], 0.0, Vector2(sc, sc))
	var fill := NodeLogic.label_plate_color()
	fill.a *= a
	plate(self, Rect2(-total * 0.5 - pad, -h - pad * 2.0, total + pad * 2.0, h + pad * 2.0), fill)
	var x := -total * 0.5
	for i in runs.size():
		var kind := str(runs[i]["kind"])
		var key := str(c["build_rate_key" if kind == "rate" else "build_label_key"])
		draw_string(SetpieceLogic.build_font_of(kind, lf, rf, mf), Vector2(x, -pad - h + asc), str(runs[i]["text"]), HORIZONTAL_ALIGNMENT_LEFT, -1, size, Palette.c(key, a))
		x += float(widths[i]) + space
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
