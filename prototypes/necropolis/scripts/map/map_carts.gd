extends Node2D
## Carts on the haul lanes (VISUAL-LANGUAGE §2d: convoys show as carts at mid zoom and nearer).
## The cross-scene cart glyph: an open green U-box (undead LineGlow stroke) carrying matte dead
## pips (LineGlow.matte_*, Palette dead, never glowing), one pip per load unit. Carts ride at
## the lane's dash speed, spaced by its rate (LaneStyle.carts). This is the routes' one
## per-frame _draw: it redraws only while carts show, and holds still under reduced motion.

## [{pts, cum, length, speed, spacing, pips}] per lit haul lane, from map_routes on a rev.
var tracks: Array = []
## GDScript ms of the last _draw (map_routes adds it to its readout and resets it).
var draw_ms := 0.0

var _shown := false


func set_tracks(t: Array) -> void:
	tracks = t
	queue_redraw()


## Called by map_routes each frame: `show` is the zoom gate (mid and nearer).
func tick(show: bool) -> void:
	var on := show and not tracks.is_empty()
	if on != _shown:
		_shown = on
		visible = on
		queue_redraw()
	elif on and not Pulse.reduced_motion:
		queue_redraw()


func _draw() -> void:
	if not _shown:
		return
	var t0 := Time.get_ticks_usec()
	var c: Dictionary = MapLogic.cfg()["carts"]
	var hw := float(c["box_w_px"]) * 0.5
	var hh := float(c["box_h_px"]) * 0.5
	var box := PackedVector2Array([Vector2(-hw, -hh), Vector2(-hw, hh), Vector2(hw, hh), Vector2(hw, -hh)])
	var stroke := float(c["stroke_px"])
	var glow := float(c["glow"])
	var green := Palette.c("undead")
	var core := Palette.c("undead_core")
	var dead := Palette.c("dead")
	var pip := float(c["pip_px"])
	var step := pip + float(c["pip_gap_px"])
	var pip_y := hh - stroke - pip * 0.5
	for tr in tracks:
		var base: float = Pulse.dash_offset(tr["speed"], tr["spacing"])
		var n: int = tr["pips"]
		var x0 := -step * (n - 1) * 0.5
		for s in LaneStyle.cart_positions(base, tr["spacing"], tr["length"]):
			var p := LaneStyle.point_at(tr["pts"], tr["cum"], s)
			var pts := PackedVector2Array()
			for v in box:
				pts.append(p + v)
			LineGlow.polyline(self, pts, green, stroke, glow, core)
			for i in n:
				var q := p + Vector2(x0 + step * i, pip_y)
				LineGlow.matte_polyline(self, PackedVector2Array([q - Vector2(pip * 0.5, 0.0), q + Vector2(pip * 0.5, 0.0)]), dead, pip)
	draw_ms += (Time.get_ticks_usec() - t0) / 1000.0
