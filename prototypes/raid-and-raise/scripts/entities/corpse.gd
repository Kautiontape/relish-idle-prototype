class_name Corpse
extends Node2D
## Corpses render on a layer beneath living units (§1). Pure set dressing —
## fades out slowly. Loot is dropped by the battlefield, not the corpse.

var radius := 12.0
var color := Color.GRAY
var _age := 0.0
const FADE_S := 22.0

func _ready() -> void:
	z_index = -10
	rotation = randf_range(-0.4, 0.4)

func _process(delta: float) -> void:
	_age += delta
	if _age > FADE_S:
		queue_free()
		return
	queue_redraw()

func _draw() -> void:
	var a := clampf(1.0 - _age / FADE_S, 0.0, 1.0) * 0.55
	var c := color.darkened(0.55)
	c.a = a
	draw_circle(Vector2.ZERO, radius, c)
	draw_line(Vector2(-radius * 0.5, 0), Vector2(radius * 0.5, 0), Color(0, 0, 0, a * 0.6), 2.0)
