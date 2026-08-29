extends Node2D
## Draws every node on the realm: fortresses as capacity rings with
## proportional arc slices (orange living / green undead / matte grey dead /
## dark gap = empty), Covington, Vei's domain, blue towns, the Relish token.

const GREEN := Color("39ff9e")
const ORANGE := Color("ff6a2b")
const GREY := Color("55525c")
const BLUE := Color("3e5c8f")
const VIOLET := Color("c04cff")
const VEI_W := Color("fff3d0")
const RING_BG := Color("202027")
const TEXT_DIM := Color("8888a0")
const AMBER := Color("ffd000")

var selected_id := ""


func fort_radius(tier: int) -> float:
	return 24.0 + tier * 4.0


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var realm: RealmSim = Game.realm
	var t := Time.get_ticks_msec() / 1000.0
	var font := ThemeDB.fallback_font

	for tw in Game.towns:
		var p: Vector2 = tw["pos"]
		var edge := BLUE
		if tw["control"] == "green":
			edge = GREEN
		elif tw["control"] == "orange":
			edge = ORANGE
		draw_rect(Rect2(p - Vector2(5, 5), Vector2(10, 10)), Color(BLUE, 0.55), true)
		draw_rect(Rect2(p - Vector2(5, 5), Vector2(10, 10)), edge, false, 1.5)
		if selected_id == tw["id"]:
			draw_rect(Rect2(p - Vector2(9, 9), Vector2(18, 18)), AMBER, false, 1.5)

	for f in realm.forts:
		_draw_fort(f, t, font)

	# Covington
	var cp: Vector2 = realm.cov_pos
	draw_rect(Rect2(cp - Vector2(14, 14), Vector2(28, 28)), Color(GREEN, 0.16), true)
	draw_rect(Rect2(cp - Vector2(14, 14), Vector2(28, 28)), GREEN, false, 2.0)
	draw_rect(Rect2(cp - Vector2(7, 7), Vector2(14, 14)), Color(GREEN, 0.8), true)
	_label(font, cp + Vector2(0, 30), "COVINGTON", GREEN)
	if selected_id == "covington":
		draw_arc(cp, 24, 0, TAU, 40, AMBER, 2.0)

	# Vei's domain — the massed backlog is the green ring tightening around her
	var vp: Vector2 = realm.vei_pos
	var halo := 0.5 + 0.5 * sin(t * 2.0 * PI / 1.714)
	draw_circle(vp, 42, Color(ORANGE, 0.10 + 0.05 * halo))
	draw_arc(vp, 42, 0, TAU, 64, ORANGE, 3.0)
	draw_arc(vp, 30, 0, TAU, 48, Color(VEI_W, 0.8), 1.5)
	for i in 8:
		var ang := TAU * i / 8.0 + t * 0.15
		var ray := Vector2.from_angle(ang)
		draw_line(vp + ray * 12.0, vp + ray * (22.0 + 3.0 * halo), Color(VEI_W, 0.7), 1.5)
	draw_circle(vp, 7, VEI_W)
	var ro: Dictionary = realm.readout()
	var odds: float = ro["odds"]
	if odds > 0.01:
		draw_arc(vp, 56, -PI / 2, -PI / 2 + TAU * odds, 64, Color(GREEN, 0.75), 3.5)
		draw_arc(vp, 56, -PI / 2 + TAU * odds, -PI / 2 + TAU, 64, Color(GREEN, 0.12), 1.5)
	_label(font, vp + Vector2(0, 62 + 14), "VEI'S DOMAIN", ORANGE)
	if selected_id == "vei":
		draw_arc(vp, 48, 0, TAU, 64, AMBER, 2.0)

	# Relish token
	var rp := cp + Vector2(0, -22)
	var raiding := Game.raiding_fort_id()
	if raiding != "":
		rp = realm.node_pos(raiding) + Vector2(0, -fort_radius(int(realm.fort_by_id(raiding).get("tier", 1))) - 10)
	rp.y += sin(t * 3.0) * 2.0
	draw_circle(rp, 6, VIOLET)
	draw_arc(rp, 9.5, 0, TAU, 24, Color(VIOLET, 0.5 + 0.3 * sin(t * 4.0)), 1.5)


func _draw_fort(f: Dictionary, t: float, font: Font) -> void:
	var p: Vector2 = f["pos"]
	var r := fort_radius(int(f["tier"]))
	var cap: float = f["cap"]
	draw_arc(p, r, 0, TAU, 48, RING_BG, 7.0)
	var a0 := -PI / 2
	for part in [[f["living"], ORANGE], [f["undead"], GREEN], [f["dead"], GREY]]:
		var frac: float = clampf(part[0] / cap, 0.0, 1.0)
		if frac > 0.005:
			var a1: float = a0 + TAU * frac
			draw_arc(p, r, a0, a1, maxi(6, int(48 * frac)), part[1], 7.0)
			a0 = a1
	# fort glyph tinted by controller
	var dom_col := GREY
	if f["undead"] > f["living"] and f["undead"] > 1.0:
		dom_col = GREEN
	elif f["living"] > 1.0:
		dom_col = ORANGE
	draw_rect(Rect2(p - Vector2(8, 8), Vector2(16, 16)), Color("0a0a0e", 0.9), true)
	draw_rect(Rect2(p - Vector2(6, 6), Vector2(12, 12)), Color(dom_col, 0.9), true)
	for i in int(f["tier"]):
		draw_circle(p + Vector2(-9 + i * 6, 12), 1.6, TEXT_DIM)
	for s in Game.realm.simulacra:
		if s["fort_id"] == f["id"]:
			var bob := sin(t * 3.0 + p.x) * 1.5
			_diamond(p + Vector2(0, -r - 8 + bob), 5.0, VIOLET)
			break
	_label(font, p + Vector2(0, r + 16), f["name"], TEXT_DIM)
	if selected_id == f["id"]:
		var pulse := 0.7 + 0.3 * sin(t * 5.0)
		draw_arc(p, r + 7, 0, TAU, 48, Color(AMBER, pulse), 2.0)


func _diamond(p: Vector2, s: float, col: Color) -> void:
	var pts := PackedVector2Array([p + Vector2(0, -s), p + Vector2(s, 0), p + Vector2(0, s), p + Vector2(-s, 0)])
	draw_colored_polygon(pts, col)


func _label(font: Font, pos: Vector2, text: String, col: Color) -> void:
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, 12).x
	var p := pos + Vector2(-w / 2.0, 0)
	draw_string(font, p + Vector2(1, 1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0, 0, 0, 0.9))
	draw_string(font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(col, 0.9))
