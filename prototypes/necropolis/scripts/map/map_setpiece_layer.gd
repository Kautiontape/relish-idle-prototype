class_name MapSetpieceLayer
extends MapNodeLayer
## The set pieces' own marks, over the nodes in world space, from the items MapSetpieces hands
## it each frame (set_items); it keeps no time itself. Items:
##   {kind: "band", pts, key, core, width, glow, cap}  a stretch of a lane (the tithe tide, the
##       garrison's WAR pulse), LineGlow's capped stack with a pale core;
##   {kind: "ring", pos, r, key, alpha, width, cap}    the first flip's ripple, the garrison's burst;
##   {kind: "label", pos, text, size, key, alpha}      a callout on a plate, its baseline at pos.
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
