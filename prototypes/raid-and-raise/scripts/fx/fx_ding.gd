class_name FxDing
extends Node2D
## Loot ding: floating text at the kill spot (§4 "remnants and husks ding off
## bodies mid-fight"). Floats up, fades, frees itself.

var text := ""
var color := Color.WHITE
var _age := 0.0
const LIFE := 1.4

func _ready() -> void:
	z_index = 80

func _process(delta: float) -> void:
	_age += delta
	position.y -= 34.0 * delta
	if _age > LIFE:
		queue_free()
		return
	queue_redraw()

func _draw() -> void:
	var a := clampf(1.0 - _age / LIFE, 0.0, 1.0)
	var col := color
	col.a = a
	draw_string(ThemeDB.fallback_font, Vector2(-90, 0), text, HORIZONTAL_ALIGNMENT_CENTER, 180, 15, col)
