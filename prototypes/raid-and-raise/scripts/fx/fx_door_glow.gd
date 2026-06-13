class_name FxDoorGlow
extends Node2D
## A glow on the chamber exit (user-directed): RED while the room is locked
## (clear it to proceed), flips to a cool blue "come on in" when the room is
## cleared. Small opaque-center-to-transparent-edge gradient that breathes.

var open := false
var radius := 64.0
var _t := 0.0
const RINGS := 8

func _ready() -> void:
	z_index = -6  # a floor decal: units and corpses draw over it

func set_open(o: bool) -> void:
	open = o

func _process(delta: float) -> void:
	_t += delta
	queue_redraw()

func _draw() -> void:
	var pulse := 0.6 + 0.4 * sin(_t * (2.4 if open else 3.4))
	var col := Color(0.5, 0.8, 1.0) if open else Color(1.0, 0.32, 0.26)
	var peak := (0.30 if open else 0.24) * pulse
	# Outer (faint) to inner (opaque): layered alpha builds a soft gradient core.
	for i in range(RINGS, 0, -1):
		var rr := radius * float(i) / float(RINGS)
		var a := peak * (1.0 - float(i - 1) / float(RINGS))
		draw_circle(Vector2.ZERO, rr, Color(col.r, col.g, col.b, a))
	# A chevron hint: up = go (open), or a barred dot = locked.
	if open:
		var c := Color(0.8, 0.92, 1.0, 0.7 * pulse)
		draw_polyline(PackedVector2Array([Vector2(-12, 6), Vector2(0, -8), Vector2(12, 6)]), c, 3.0)
		draw_polyline(PackedVector2Array([Vector2(-12, 16), Vector2(0, 2), Vector2(12, 16)]), c, 3.0)
