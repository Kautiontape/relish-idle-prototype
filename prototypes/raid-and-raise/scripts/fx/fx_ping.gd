class_name FxPing
extends Node2D
## MOBA-style move confirm: a small expanding ring + shrinking dot at the
## ordered destination. "Yep, movement confirmed."

var color := Color(0.78, 0.6, 0.95)
var _age := 0.0
const LIFE := 0.55

func _ready() -> void:
	z_index = 65

func _process(delta: float) -> void:
	_age += delta
	if _age > LIFE:
		queue_free()
		return
	queue_redraw()

func _draw() -> void:
	var t := clampf(_age / LIFE, 0.0, 1.0)
	var a := 1.0 - t
	draw_arc(Vector2.ZERO, 8.0 + 26.0 * t, 0, TAU, 24, Color(color.r, color.g, color.b, a), 2.5)
	draw_circle(Vector2.ZERO, 5.0 * a, Color(color.r, color.g, color.b, a * 0.9))
