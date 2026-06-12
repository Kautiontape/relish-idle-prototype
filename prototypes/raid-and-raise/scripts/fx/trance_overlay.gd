class_name TranceOverlay
extends Node2D
## Trance mode-state visual (§8.2): the world dims and desaturates while the
## button is held. Parented to the camera; essence (z 60) and traces (z 70)
## draw above this overlay (z 50), so they "ignite" against the dimmed world.

func _ready() -> void:
	z_index = 50
	visible = false

func _draw() -> void:
	var vp := get_viewport_rect().size
	draw_rect(Rect2(-vp / 2.0, vp), Color(0.05, 0.04, 0.12, 0.5))
