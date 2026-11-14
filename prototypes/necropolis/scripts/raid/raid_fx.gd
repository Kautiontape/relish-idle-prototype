class_name RaidFx
extends RefCounted
## Tiny one-shot effects shared by the raid and boss scenes.


## Expanding, fading ring (sacrifice flash, pulse blast, teleport, win flash).
class Ring:
	extends Node2D
	var color: Color = Palette.c("text")
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
		var col := color
		col.a = (1.0 - f) * color.a
		# reduced motion: no expansion, the ring holds its size and only fades
		var rf := 0.6 if Pulse.reduced_motion else f
		LineGlow.ring(self, Vector2.ZERO, maxf(2.0, max_radius * rf), col,
			width * (1.0 - f * 0.5), 0.5)


## Small fading double-ring at a click point (move order ping).
class Ping:
	extends Node2D
	var color: Color = Palette.c("relish")
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
		var col := color
		col.a = (1.0 - f) * 0.8
		var rf := 0.6 if Pulse.reduced_motion else f
		draw_arc(Vector2.ZERO, 6.0 + 14.0 * rf, 0, TAU, 20, col, 2.0)
		draw_circle(Vector2.ZERO, 2.5, col)


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
		draw_line(Vector2.ZERO, to_local(to_point), Palette.c("danger", a), 3.0)
		draw_circle(Vector2.ZERO, 7.0, Palette.c("danger", a * 0.7))


## A violet ring that holds, then cracks into drifting shards that fade (a backup cracking,
## VISUAL-LANGUAGE 2e). Used for the phylactery revive.
class Crack:
	extends Node2D
	var color: Color = Palette.c("relish")
	var radius := 90.0
	var duration := 1.1
	var shards := 9
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
		var hold := 0.3
		var k := clampf((f - hold) / (1.0 - hold), 0.0, 1.0)   # 0 while the ring is intact
		if Pulse.reduced_motion:
			k = 0.5 if f > hold else 0.0                      # no drift: it just shows broken
		var col := color
		col.a = color.a * (1.0 if f < hold else 1.0 - k * 0.9)
		var span := TAU / shards
		for i in shards:
			var a0 := span * i
			var gap := span * 0.55 * k + (span * 0.06 if f >= hold else 0.0)
			var push := (0.5 + 0.5 * sin(float(i) * 2.7 + 1.3)) * 26.0 * k
			LineGlow.arc(self, Vector2.ZERO, radius * (0.55 + 0.45 * minf(1.0, f * 3.0)) + push,
				a0 + gap * 0.5, a0 + span - gap * 0.5, col, 3.5 * (1.0 - k * 0.5), 0.6)


static func crack(parent: Node, pos: Vector2, color: Color, radius: float, duration := 1.1) -> void:
	RaidSound.play("shatter")
	var c := Crack.new()
	c.position = pos
	c.color = color
	c.radius = radius
	c.duration = duration
	parent.add_child(c)


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


## A remnant ding: a small vei spark ring and a tiny "+1" in text that rises and fades
## (reduced motion: no rise, it just fades in place).
class Ding:
	extends Node2D
	var ring_px := 22.0
	var ring_s := 0.35
	var text_s := 0.8
	var rise_px := 26.0
	var _t := 0.0

	func _ready() -> void:
		z_index = 73

	func _process(delta: float) -> void:
		_t += delta / maxf(0.05, Engine.time_scale)
		if _t >= maxf(ring_s, text_s):
			queue_free()
			return
		queue_redraw()

	func _draw() -> void:
		if _t < ring_s:
			var f := _t / ring_s
			var col := Palette.c("vei")
			col.a = 1.0 - f
			LineGlow.ring(self, Vector2.ZERO, maxf(2.0, ring_px * (0.6 if Pulse.reduced_motion else f)), col, 2.0, 0.5)
		var g := _t / text_s
		var rise := 0.0 if Pulse.reduced_motion else rise_px * g
		var tc := Palette.c("text")
		tc.a = clampf(1.0 - g, 0.0, 1.0)
		draw_string(ThemeDB.fallback_font, Vector2(-8.0, -10.0 - rise), "+1", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, tc)


static func ding(parent: Node, pos: Vector2, fx_cfg := {}) -> void:
	var d := Ding.new()
	d.position = pos
	d.ring_px = float(fx_cfg.get("ring_px", 22.0))
	d.ring_s = float(fx_cfg.get("ring_s", 0.35))
	d.text_s = float(fx_cfg.get("text_s", 0.8))
	d.rise_px = float(fx_cfg.get("rise_px", 26.0))
	parent.add_child(d)
