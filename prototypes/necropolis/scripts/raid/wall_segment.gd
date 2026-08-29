class_name RaidWall
extends Node2D
## One chunky wall segment rendered with the rainbow-drift shader. Local +x runs
## along the wall's length; origin sits at the segment's left/top center-line.

static var _shader: Shader = null

var length := 100.0
var core_half := 15.0
var glow := 26.0


func setup(rect: Rect2, glow_px: float) -> void:
	glow = glow_px
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
	var mat := ShaderMaterial.new()
	mat.shader = _shader
	mat.set_shader_parameter("seg_len", length)
	mat.set_shader_parameter("core_half", core_half)
	mat.set_shader_parameter("glow_px", glow)
	mat.set_shader_parameter("world_off", position.x if horizontal else position.y)
	material = mat


func _draw() -> void:
	var half_h := core_half + glow
	draw_rect(Rect2(0.0, -half_h, length, half_h * 2.0), Color.WHITE)
