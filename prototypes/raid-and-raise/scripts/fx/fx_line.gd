class_name FxLine
extends Node2D
## Sacrifice flash: a red soul-link line from Relish to the unit that died in
## her place, so the chain is legible. Fades fast.

var from := Vector2.ZERO
var to := Vector2.ZERO
var color := Color(1.0, 0.2, 0.2)
var _age := 0.0
const LIFE := 0.45

func _ready() -> void:
	z_index = 80

func _process(delta: float) -> void:
	_age += delta
	if _age > LIFE:
		queue_free()
		return
	queue_redraw()

func _draw() -> void:
	var a := clampf(1.0 - _age / LIFE, 0.0, 1.0)
	var col := color
	col.a = a
	draw_line(to_local(from), to_local(to), col, 4.0 * a + 1.0)
	draw_circle(to_local(to), 10.0 * a, Color(col.r, col.g, col.b, a * 0.5))
