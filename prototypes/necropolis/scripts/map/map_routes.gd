extends Node2D
## Flow lines: the rate rendered, never a convoy tracked (BRIEF motion canon).
## Green = undead flows, orange = living shipments, matte dark = corpses to Vei
## (the shadow gutter, offset onto the undead lane). Zero-rate routes are OFF.

const GREEN := Color("39ff9e")
const ORANGE := Color("ff6a2b")
const GUTTER := Color("17171c")
const VIOLET := Color("c04cff")
const RATE_LOG_MAX := 25.0


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var realm: RealmSim = Game.realm
	var t := Time.get_ticks_msec() / 1000.0
	for f in realm.forts:
		_flow(realm.cov_pos, f["pos"], f["r_in"], GREEN, t, 0.0)
		_flow(f["pos"], realm.vei_pos, f["r_drain"], GREEN, t, 0.0)
		_flow(f["pos"], realm.vei_pos, f["r_dead_out"], GUTTER, t, -7.0, true)
		_flow(realm.vei_pos, f["pos"], f["r_shipped"], ORANGE, t, 0.0)
	var ds: float = float(realm.t.get("directShare", 0.22))
	_flow(realm.cov_pos, realm.vei_pos, realm.cov["r_out"] * ds, GREEN, t, 0.0)
	_draw_gather(t)


func _draw_gather(_t: float) -> void:
	var g: Dictionary = Game.gather
	if g["phase"] == "idle" or g["target"] == "":
		return
	var a: Vector2 = Game.realm.cov_pos
	var b: Vector2 = Game.realm.node_pos(g["target"])
	var speed: float = float(ConfigDb.v("realm", "gather_speed", 140.0))
	var total: float = a.distance_to(b) / speed
	var frac: float = clampf(1.0 - float(g["eta"]) / maxf(0.01, total), 0.0, 1.0)
	var pos: Vector2
	if g["phase"] == "out":
		pos = a.lerp(b, frac)
	else:
		pos = b.lerp(a, frac)
	draw_line(a, b, Color(GREEN, 0.10), 1.5)
	draw_circle(pos, 5.0, Color("6e6a7e") if g["phase"] == "back" else Color(GREEN, 0.8))
	draw_arc(pos, 7.5, 0, TAU, 16, Color(GREEN, 0.5), 1.5)


func _flow(a: Vector2, b: Vector2, rate: float, col: Color, t: float, lateral: float, matte := false) -> void:
	if rate < 0.06:
		return
	var u := clampf(log(1.0 + rate) / log(1.0 + RATE_LOG_MAX), 0.0, 1.0)
	var width := 1.1 + 2.6 * u
	var alpha := 0.4 + 0.6 * u
	var period := 96.0 - 52.0 * u
	var speed := 14.0 + 140.0 * u
	var dash := period * 0.5
	if matte:
		alpha = 0.85
		speed *= 0.6

	var dir := (b - a).normalized()
	var perp := Vector2(-dir.y, dir.x)  # bow-left rule
	var length := a.distance_to(b)
	var mid := (a + b) * 0.5 - perp * length * 0.07 + perp * lateral

	# sample the quadratic bow
	var pts: Array[Vector2] = []
	var n := 26
	for i in n + 1:
		var s := float(i) / n
		pts.append(a.lerp(mid, s).lerp(mid.lerp(b, s), s))
	var cum: Array[float] = [0.0]
	for i in n:
		cum.append(cum[i] + pts[i].distance_to(pts[i + 1]))
	var total: float = cum[n]

	# walk dashes with a moving offset
	var offset := fmod(t * speed, period)
	var d := -period + offset
	var c := Color(col, alpha)
	while d < total:
		var s0 := maxf(0.0, d)
		var s1 := minf(total, d + dash)
		if s1 > s0:
			_draw_sub(pts, cum, s0, s1, c, width)
		d += period


func _draw_sub(pts: Array[Vector2], cum: Array[float], s0: float, s1: float, c: Color, w: float) -> void:
	var seg: Array[Vector2] = []
	seg.append(_at(pts, cum, s0))
	for i in pts.size():
		if cum[i] > s0 and cum[i] < s1:
			seg.append(pts[i])
	seg.append(_at(pts, cum, s1))
	if seg.size() >= 2:
		draw_polyline(PackedVector2Array(seg), c, w)


func _at(pts: Array[Vector2], cum: Array[float], s: float) -> Vector2:
	for i in range(1, pts.size()):
		if cum[i] >= s:
			var span: float = cum[i] - cum[i - 1]
			var f: float = 0.0 if span <= 0.0 else (s - cum[i - 1]) / span
			return pts[i - 1].lerp(pts[i], f)
	return pts[pts.size() - 1]
