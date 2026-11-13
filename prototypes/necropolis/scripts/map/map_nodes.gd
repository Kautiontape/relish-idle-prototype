extends Node2D
## Draws every node on the realm from the shared MapModel: fortresses as capacity rings with
## proportional arc slices (living / undead / matte dead / dark gap = empty), Covington, Vei's
## domain, villages and the Relish token. Tempo comes from Pulse (Covington 0 hops, forts 1,
## Vei 2). Task 3 rewrites the fortress ring.

var model: MapModel
var selected_id := ""


func fort_radius(tier: int) -> float:
	return MapLogic.fort_radius(tier)


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if model == null or model.realm.is_empty():
		return
	var cfg := MapLogic.cfg()
	var font := ThemeDB.fallback_font

	for tw in model.villages:
		var p := MapModel.to_vec(tw["pos"])
		var edge := Palette.c("town")
		if tw["owner"] == "player":
			edge = Palette.c("undead")
		elif tw["owner"] == "vei":
			edge = Palette.c("living")
		draw_rect(Rect2(p - Vector2(5, 5), Vector2(10, 10)), Palette.c("town", 0.55), true)
		draw_rect(Rect2(p - Vector2(5, 5), Vector2(10, 10)), edge, false, 1.5)
		if selected_id == tw["id"]:
			draw_rect(Rect2(p - Vector2(9, 9), Vector2(18, 18)), Palette.c("select"), false, 1.5)

	for f in model.forts:
		_draw_fort(f, font)

	# Covington
	var cp := model.node_pos("covington")
	var cov_wave: float = Pulse.wave(model.hops_of("covington"))
	draw_rect(Rect2(cp - Vector2(14, 14), Vector2(28, 28)), Palette.c("undead", 0.12 + 0.08 * cov_wave), true)
	draw_rect(Rect2(cp - Vector2(14, 14), Vector2(28, 28)), Palette.c("undead"), false, 2.0)
	draw_rect(Rect2(cp - Vector2(7, 7), Vector2(14, 14)), Palette.c("undead", 0.8), true)
	_label(font, cp + Vector2(0, 30), "COVINGTON", Palette.c("undead"))
	if selected_id == "covington":
		draw_arc(cp, 24, 0, TAU, 40, Palette.c("select"), 2.0)

	# Vei's domain: the massed backlog is the green ring tightening around her
	var vp := model.node_pos("vei")
	var vh := model.hops_of("vei")
	var halo: float = Pulse.wave(vh)
	draw_circle(vp, 42, Palette.c("living", 0.10 + 0.05 * halo))
	draw_arc(vp, 42, 0, TAU, 64, Palette.c("living"), 3.0)
	draw_arc(vp, 30, 0, TAU, 48, Palette.c("vei", 0.8), 1.5)
	var spin: float = Pulse.phase(vh) * TAU / 8.0  # one ray-step per beat; eight rays, so it never seams
	for i in 8:
		var ray := Vector2.from_angle(TAU * i / 8.0 + spin)
		draw_line(vp + ray * 12.0, vp + ray * (22.0 + 3.0 * halo), Palette.c("vei", 0.7), 1.5)
	draw_circle(vp, 7, Palette.c("vei"))
	var odds := float(model.vei.get("odds", 0.0))
	if odds > 0.01:
		draw_arc(vp, 56, -PI / 2, -PI / 2 + TAU * odds, 64, Palette.c("undead", 0.75), 3.5)
		draw_arc(vp, 56, -PI / 2 + TAU * odds, -PI / 2 + TAU, 64, Palette.c("undead", 0.12), 1.5)
	_label(font, vp + Vector2(0, 62 + 14), "VEI'S DOMAIN", Palette.c("living"))
	if selected_id == "vei":
		draw_arc(vp, 48, 0, TAU, 64, Palette.c("select"), 2.0)

	_draw_relish(cfg)


func _node_radius(id: String) -> float:
	var cfg := MapLogic.cfg()
	if id == "vei":
		return float(cfg["vei_draw_radius"])
	if model.forts_by_id.has(id):
		return MapLogic.fort_radius(int(model.fort(id)["tier"]))
	return float(cfg["cov_draw_radius"])


func _draw_relish(cfg: Dictionary) -> void:
	var rel := model.relish
	if rel.is_empty():
		return
	var rp := MapModel.to_vec(rel["pos"])
	if rel["state"] != "travelling":
		rp.y -= _node_radius(str(rel["at"])) + float(cfg["relish_gap_px"])
	var w: float = Pulse.wave(model.hops_of(str(rel["at"])))
	rp.y += w * float(cfg["relish_bob_px"])
	draw_circle(rp, 6, Palette.c("relish"))
	draw_arc(rp, 9.5, 0, TAU, 24, Palette.c("relish", 0.5 + 0.3 * w), 1.5)


func _draw_fort(f: Dictionary, font: Font) -> void:
	var cfg := MapLogic.cfg()
	var p := MapModel.to_vec(f["pos"])
	var r := MapLogic.fort_radius(int(f["tier"]))
	var cap: float = f["cap"]
	var w: float = Pulse.wave(model.hops_of(f["id"]))
	draw_arc(p, r, 0, TAU, 48, Palette.c("ring_track"), float(cfg["halo_ring_width"]))
	var a0 := -PI / 2
	for part in [[f["living"], "living"], [f["undead"], "undead"], [f["dead"], "dead"]]:
		var frac: float = clampf(part[0] / cap, 0.0, 1.0)
		if frac > 0.005:
			var a1: float = a0 + TAU * frac
			if part[1] == "dead":
				LineGlow.matte_arc(self, p, r, a0, a1, Palette.c("dead"), float(cfg["halo_ring_width"]))
			else:
				draw_arc(p, r, a0, a1, maxi(6, int(48 * frac)), Palette.c(part[1]), float(cfg["halo_ring_width"]))
			a0 = a1
	# fort glyph tinted by controller
	var dom := "dead"
	if f["undead"] > f["living"] and f["undead"] > 1.0:
		dom = "undead"
	elif f["living"] > 1.0:
		dom = "living"
	draw_rect(Rect2(p - Vector2(8, 8), Vector2(16, 16)), Palette.c("ground", 0.9), true)
	draw_rect(Rect2(p - Vector2(6, 6), Vector2(12, 12)), Palette.c(dom, 0.9), true)
	for i in int(f["tier"]):
		draw_circle(p + Vector2(-9 + i * 6, 12), 1.6, Palette.c("text_dim"))
	if float(f.get("simulacrum_charges", 0.0)) > 0.0:
		_diamond(p + Vector2(0, -r - 8 + w * 1.5), 5.0, Palette.c("relish"))
	_label(font, p + Vector2(0, r + 16), f["name"], Palette.c("text_dim"))
	if selected_id == f["id"]:
		draw_arc(p, r + 7, 0, TAU, 48, Palette.c("select", 0.7 + 0.3 * w), 2.0)


func _diamond(p: Vector2, s: float, col: Color) -> void:
	var pts := PackedVector2Array([p + Vector2(0, -s), p + Vector2(s, 0), p + Vector2(0, s), p + Vector2(-s, 0)])
	draw_colored_polygon(pts, col)


func _label(font: Font, pos: Vector2, text: String, col: Color) -> void:
	var cfg := MapLogic.cfg()
	var size := int(cfg["font_label"])
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, size).x
	var p := pos + Vector2(-w / 2.0, 0)
	draw_string(font, p + Vector2(1, 1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Palette.c("ground", float(cfg["label_shadow_alpha"])))
	draw_string(font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(col, float(cfg["node_label_dim_alpha"])))
