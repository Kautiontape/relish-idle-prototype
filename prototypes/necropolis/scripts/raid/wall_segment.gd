class_name RaidWall
extends Node2D
## One wall segment rendered with the wall shader as a thin stroke along its centre line
## (the collision band is not drawn). Local +x runs along the wall's length; origin sits at
## the segment's left/top center-line. The shader cycles between two Palette colours; the
## arena feeds it the Pulse beat each frame through `set_beat`.

static var _shader: Shader = null

var length := 100.0
var core_half := 15.0
var stroke_half := 1.5
var halo := 9.0

var _mat: ShaderMaterial = null


## `look`: color_a / color_b (Colors), heat, wavelength, arena_diag, stroke_half, halo_px,
## intensity.
func setup(rect: Rect2, look: Dictionary) -> void:
	stroke_half = float(look.get("stroke_half", stroke_half))
	halo = float(look.get("halo_px", halo))
	var horizontal := rect.size.x >= rect.size.y
	if horizontal:
		length = rect.size.x
		core_half = rect.size.y * 0.5
		position = Vector2(rect.position.x, rect.get_center().y)
		rotation = 0.0
	else:
		length = rect.size.y
		core_half = rect.size.x * 0.5
		position = Vector2(rect.get_center().x, rect.position.y)
		rotation = PI * 0.5
	z_index = 20
	if _shader == null:
		_shader = load("res://shaders/raid/wall.gdshader")
	_mat = ShaderMaterial.new()
	_mat.shader = _shader
	_mat.set_shader_parameter("seg_len", length)
	_mat.set_shader_parameter("world_off", position.x if horizontal else position.y)
	for k in look:
		_mat.set_shader_parameter(k, look[k])
	material = _mat


## Per frame: the beat at the source, Relish's position, the colour drift
## position, and `steady` (>= 0 under reduced motion, else -1).
func set_beat(beat: float, relish_pos: Vector2, drift: float, steady: float) -> void:
	_mat.set_shader_parameter("beat", beat)
	_mat.set_shader_parameter("relish_pos", relish_pos)
	_mat.set_shader_parameter("drift", drift)
	_mat.set_shader_parameter("steady", steady)


func _draw() -> void:
	var half_h := stroke_half + halo
	draw_rect(Rect2(0.0, -half_h, length, half_h * 2.0), Palette.c("text"))
