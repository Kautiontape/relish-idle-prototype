class_name RaidFx
extends RefCounted
## Tiny one-shot effects shared by the raid and boss scenes.


## Expanding, fading ring (sacrifice flash, pulse blast, teleport, win flash).
class Ring:
	extends Node2D
	var color := Color.WHITE
	var max_radius := 60.0
	var duration := 0.4
	var width := 3.0
	var _t := 0.0

	func _ready() -> void:
		z_index = 72

	func _process(delta: float) -> void:
		_t += delta / maxf(0.05, Engine.time_scale)
		if _t >= duration:
			queue_free()
			return
		queue_redraw()

	func _draw() -> void:
		var f := _t / duration
		var a := (1.0 - f) * color.a
		draw_arc(Vector2.ZERO, maxf(2.0, max_radius * f), 0, TAU, 48,
			Color(color.r, color.g, color.b, a), width * (1.0 - f * 0.5))


## Small fading double-ring at a click point (move order ping).
class Ping:
	extends Node2D
	var color := Color("#c04cff")
	var _t := 0.0

	func _ready() -> void:
		z_index = 15

	func _process(delta: float) -> void:
		_t += delta / maxf(0.05, Engine.time_scale)
		if _t >= 0.45:
			queue_free()
			return
		queue_redraw()

	func _draw() -> void:
		var f := _t / 0.45
		var a := (1.0 - f) * 0.8
		draw_arc(Vector2.ZERO, 6.0 + 14.0 * f, 0, TAU, 20, Color(color.r, color.g, color.b, a), 2.0)
		draw_circle(Vector2.ZERO, 2.5, Color(color.r, color.g, color.b, a))


## Red soul-link flash: line from the sacrificed ally to Relish.
class SoulLink:
	extends Node2D
	var to_point := Vector2.ZERO
	var _t := 0.0

	func _ready() -> void:
		z_index = 72

	func _process(delta: float) -> void:
		_t += delta / maxf(0.05, Engine.time_scale)
		if _t >= 0.5:
			queue_free()
			return
		queue_redraw()

	func _draw() -> void:
		var a := (1.0 - _t / 0.5) * 0.9
		draw_line(Vector2.ZERO, to_local(to_point), Color(1.0, 0.18, 0.33, a), 3.0)
		draw_circle(Vector2.ZERO, 7.0, Color(1.0, 0.18, 0.33, a * 0.7))


static func ring(parent: Node, pos: Vector2, color: Color, max_radius: float,
		duration := 0.4, width := 3.0) -> void:
	var r := Ring.new()
	r.position = pos
	r.color = color
	r.max_radius = max_radius
	r.duration = duration
	r.width = width
	parent.add_child(r)


static func ping(parent: Node, pos: Vector2) -> void:
	var p := Ping.new()
	p.position = pos
	parent.add_child(p)


static func soul_link(parent: Node, from_pos: Vector2, to_pos: Vector2) -> void:
	var s := SoulLink.new()
	s.position = from_pos
	s.to_point = to_pos
	parent.add_child(s)
