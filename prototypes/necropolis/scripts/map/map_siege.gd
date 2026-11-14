class_name MapSiege
extends MapNodeLayer
## Static layer, near zoom only: the big undead placed at each fort (view_fort.siege), one
## big-undead diamond per uid (nested outlines by GlyphLogic.stroke_count) on a small arc outside
## the fort's rings (GlyphLogic.siege_layout). MapNodes beats it on the forts' beat through its
## modulate (GlyphLogic.siege_alpha), so the pulse costs no redraw.


func _draw_static() -> void:
	if ctx.tier != "near":
		return
	var half := float(GlyphLogic.gcfg()["big_half_px"])
	for f in ctx.forts:
		var uids: Array = f.get("siege", [])
		if uids.is_empty():
			continue
		var at := GlyphLogic.siege_layout(MapModel.to_vec(f["pos"]), int(f["tier"]), uids.size())
		for i in uids.size():
			big_glyph(at[i], half, GlyphLogic.stroke_count(ctx.model.big_undead.get(str(uids[i]), {})))


## Each sieged fort and its big undead's strokes (the zoom and tier redraw it on their own).
func static_sig():
	var out: Array = []
	for f in ctx.forts:
		var uids: Array = f.get("siege", [])
		if not uids.is_empty():
			out.append([str(f["id"]), int(f["tier"]), uids.map(func(u): return GlyphLogic.stroke_count(ctx.model.big_undead.get(str(u), {})))])
	return out
