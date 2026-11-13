class_name RaidDanger
extends CanvasLayer
## The danger cue: thin `danger` strokes along the screen edges (screen space, never a fill).
## It pulses when Relish is hit or the sacrifice chain spends a unit for her, and holds a
## fainter edge while a warden's tell is aimed at her. Under reduced motion a steady tint
## replaces the pulse. Numbers: configs/raid.json `danger`.

var _hit_left := 0.0       # real seconds of hit pulse remaining
var _target_left := 0.0    # real seconds the "a warden is targeting her" cue stays up
var _pulse_s := 0.7
var _width := 5.0
var _inset := 5.0
var _alpha := 0.85
var _target_alpha := 0.4
var _static_alpha := 0.5
var _hold_s := 0.2
var _draw_node: Node2D = null
var _pts := PackedVector2Array()
var _last_alpha := -1.0
var _last_size := Vector2.ZERO


func _ready() -> void:
	layer = 9   # over the world, under the HUD (10)
	var c: Dictionary = ConfigDb.data.get("raid", {}).get("danger", {})
	_pulse_s = float(c.get("edge_pulse_s", 0.7))
	_width = float(c.get("edge_width_px", 5.0))
	_inset = float(c.get("edge_inset_px", 5.0))
	_alpha = float(c.get("edge_alpha", 0.85))
	_target_alpha = float(c.get("edge_target_alpha", 0.4))
	_static_alpha = float(c.get("edge_static_alpha", 0.5))
	_hold_s = float(c.get("target_hold_s", 0.2))
	_draw_node = EdgeDraw.new()
	_draw_node.owner_layer = self
	add_child(_draw_node)


## Relish was hit, or an ally was spent in her place.
func hit() -> void:
	_hit_left = _pulse_s


## A warden's tell is aimed at her. Call every physics frame the tell holds.
func targeted() -> void:
	_target_left = _hold_s


## Edge alpha right now (0 = nothing to draw).
func level() -> float:
	var reduced: bool = Pulse.reduced_motion
	if reduced:
		return _static_alpha if (_hit_left > 0.0 or _target_left > 0.0) else 0.0
	var a := 0.0
	if _hit_left > 0.0:
		a = _alpha * _hit_left / maxf(0.01, _pulse_s)
	if _target_left > 0.0:
		a = maxf(a, _target_alpha * (0.7 + 0.3 * Pulse.wave()))
	return a


func _process(delta: float) -> void:
	var real := delta / maxf(0.05, Engine.time_scale)   # real time, unaffected by the trance
	_hit_left = maxf(0.0, _hit_left - real)
	_target_left = maxf(0.0, _target_left - real)
	var a := level()
	var sz := get_viewport().get_visible_rect().size
	if a != _last_alpha or sz != _last_size:
		_last_alpha = a
		_last_size = sz
		_draw_node.queue_redraw()


func edge_points() -> PackedVector2Array:
	var sz := get_viewport().get_visible_rect().size
	var m := _inset + _width * 0.5
	_pts.resize(5)
	_pts[0] = Vector2(m, m)
	_pts[1] = Vector2(sz.x - m, m)
	_pts[2] = Vector2(sz.x - m, sz.y - m)
	_pts[3] = Vector2(m, sz.y - m)
	_pts[4] = Vector2(m, m)
	return _pts


class EdgeDraw:
	extends Node2D
	var owner_layer: RaidDanger = null

	func _draw() -> void:
		if owner_layer == null:
			return
		var a := owner_layer.level()
		if a <= 0.0:
			return
		LineGlow.polyline(self, owner_layer.edge_points(), Palette.c("danger", a), owner_layer._width, 0.8)
