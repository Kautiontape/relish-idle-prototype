class_name MapParty
extends MapNodeLayer
## Pulse layer (it follows her token), near zoom only: the big undead in view_party().party as
## small big-undead diamonds round Relish, in party order (GlyphLogic.party_layout): a file behind
## her along her heading while she travels, a row beside her while she stands. None while she is dead.


func _draw_pulse() -> void:
	if ctx.tier != "near" or ctx.relish.is_empty():
		return
	var state := str(ctx.relish.get("state", "home"))
	var members: Array = ctx.model.party.get("party", [])
	if state == "dead" or members.is_empty():
		return
	var at := GlyphLogic.party_layout(ctx.relish_pos, float(ctx.relish.get("heading", 0.0)), state == "travelling", members.size(), ctx.zoom)
	var half := float(GlyphLogic.gcfg()["party_half_px"])
	for i in members.size():
		big_glyph(at[i], half, GlyphLogic.stroke_count(members[i]))
