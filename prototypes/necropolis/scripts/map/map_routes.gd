extends Node2D
## Flow lines: the rate rendered, never a convoy tracked (BRIEF motion canon). Drawn from the
## shared MapModel's lanes: undead green (war, flood), living orange, dead as a matte gutter
## beside its host flood lane. Zero-rate lanes are OFF. Geometry comes only from MapLogic;
## task 2 replaces this renderer with shader ribbons.

const DRAWN_KINDS := ["war", "flood", "living", "dead"]

var model: MapModel

var _rate_by_id := {}
var _cache_rev := -2


## The single source of lane geometry, forwarded so callers can reach it from the routes script.
static func lane_curve(from_pos: Vector2, to_pos: Vector2, u: float) -> Dictionary:
	return MapLogic.lane_curve(from_pos, to_pos, u)


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if model == null:
		return
	if _cache_rev != model.rev:
		_cache_rev = model.rev
		_rate_by_id.clear()
		for l in model.lanes:
			_rate_by_id[l["id"]] = float(l["rate"])
	for l in model.lanes:
		if not DRAWN_KINDS.has(l["kind"]) or not model.has_node(l["from"]) or not model.has_node(l["to"]):
			continue
		var a := model.node_pos(l["from"])
		var b := model.node_pos(l["to"])
		var u: float = Pulse.rate_to_u(float(l["rate"]))
		match l["kind"]:
			"war", "flood":
				_flow(MapLogic.lane_curve(a, b, u), u, "undead")
			"living":
				_flow(MapLogic.lane_curve(a, b, u), u, "living")
			"dead":
				var host_u: float = Pulse.rate_to_u(float(_rate_by_id.get("flood:%s:%s" % [l["from"], l["to"]], 0.0)))
				_gutter(MapLogic.gutter_curve(a, b, host_u, u), u)


func _flow(curve: Dictionary, u: float, hue_key: String) -> void:
	var ch: Dictionary = Pulse.channels(u, Palette.hue(hue_key))
	if ch["off"] or curve["loop"]:
		return
	var floor_a: float = MapLogic.cfg()["lane_alpha_floor"]
	var col := Color(ch["color"], maxf(float(ch["alpha"]), floor_a))
	_dashes(curve, col, float(ch["width"]), float(ch["period"]), float(ch["dash"]), float(ch["speed"]), false)


## The dead gutter: matte, never glowing, a little slower than its flood neighbour.
func _gutter(curve: Dictionary, u: float) -> void:
	var cfg := MapLogic.cfg()
	var ch: Dictionary = Pulse.channels(u, Palette.hue("dead"))
	if ch["off"] or curve["loop"]:
		return
	var col := Palette.c("dead", float(cfg["gutter_alpha"]))
	_dashes(curve, col, float(curve["half_width"]) * 2.0, float(ch["period"]), float(ch["dash"]),
		float(ch["speed"]) * float(cfg["gutter_speed_scale"]), true)


func _dashes(curve: Dictionary, col: Color, width: float, period: float, dash: float, speed: float, matte: bool) -> void:
	var pts := MapLogic.sample_quad(curve["a"], curve["c"], curve["b"], int(MapLogic.cfg()["lane_samples"]))
	var cum: Array[float] = [0.0]
	for i in pts.size() - 1:
		cum.append(cum[i] + pts[i].distance_to(pts[i + 1]))
	var total: float = cum[cum.size() - 1]
	var d := -period + Pulse.dash_offset(speed, period)
	while d < total:
		var s0 := maxf(0.0, d)
		var s1 := minf(total, d + dash)
		if s1 > s0:
			var seg := _sub(pts, cum, s0, s1)
			if matte:
				LineGlow.matte_polyline(self, seg, col, width)
			else:
				draw_polyline(seg, col, width)
		d += period


func _sub(pts: PackedVector2Array, cum: Array[float], s0: float, s1: float) -> PackedVector2Array:
	var seg := PackedVector2Array()
	seg.append(_at(pts, cum, s0))
	for i in pts.size():
		if cum[i] > s0 and cum[i] < s1:
			seg.append(pts[i])
	seg.append(_at(pts, cum, s1))
	return seg


func _at(pts: PackedVector2Array, cum: Array[float], s: float) -> Vector2:
	for i in range(1, pts.size()):
		if cum[i] >= s:
			var span: float = cum[i] - cum[i - 1]
			var f := 0.0 if span <= 0.0 else (s - cum[i - 1]) / span
			return pts[i - 1].lerp(pts[i], f)
	return pts[pts.size() - 1]
