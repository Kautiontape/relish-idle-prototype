class_name TraceFeedback
extends Node2D
## Mandatory circle feedback (§8.2): flash the fitted ideal ring against the
## player's actual trace, with a grade, for a beat. The player must see WHY
## 73 was 73.

var trace := PackedVector2Array()
var fitted_center := Vector2.ZERO
var fitted_radius := 0.0
var score := 0
var valid := false
var _age := 0.0

func _ready() -> void:
	z_index = 75

func _life() -> float:
	return float(ConfigDb.v("circle", "feedback_hold_s")) + 0.4

func _process(delta: float) -> void:
	_age += delta / maxf(0.05, Engine.time_scale)  # real time, unaffected by trance
	if _age > _life():
		queue_free()
		return
	queue_redraw()

func _grade_color() -> Color:
	if score >= 90:
		return Color(0.4, 1.0, 0.95)
	if score >= 70:
		return Color(0.45, 0.95, 0.45)
	if score >= 40:
		return Color(1.0, 0.85, 0.3)
	return Color(1.0, 0.4, 0.3)

func _grade_word() -> String:
	if score >= 90:
		return "PERFECT"
	if score >= 70:
		return "GOOD"
	if score >= 40:
		return "SLOPPY"
	return "POOR"

func _draw() -> void:
	var hold := float(ConfigDb.v("circle", "feedback_hold_s"))
	var a := 1.0 if _age < hold else clampf(1.0 - (_age - hold) / 0.4, 0.0, 1.0)
	var col := _grade_color()
	if trace.size() >= 2:
		var pts := PackedVector2Array()
		for p in trace:
			pts.append(to_local(p))
		draw_polyline(pts, Color(col.r, col.g, col.b, a * 0.9), 3.0)
	if valid and fitted_radius > 0.0:
		var c := to_local(fitted_center)
		# dashed ideal ring
		var segs := 36
		for i in segs:
			if i % 2 == 0:
				var a0 := TAU * i / segs
				var a1 := TAU * (i + 0.8) / segs
				draw_arc(c, fitted_radius, a0, a1, 4, Color(1, 1, 1, a * 0.8), 2.0)
		draw_string(ThemeDB.fallback_font, c + Vector2(-80, -fitted_radius - 14),
			"%d — %s" % [score, _grade_word()], HORIZONTAL_ALIGNMENT_CENTER, 160, 22,
			Color(col.r, col.g, col.b, a))
	else:
		var c2 := to_local(trace[trace.size() / 2]) if trace.size() > 0 else Vector2.ZERO
		draw_string(ThemeDB.fallback_font, c2 + Vector2(-80, -20),
			"0 — NOT A CIRCLE", HORIZONTAL_ALIGNMENT_CENTER, 160, 22, Color(1, 0.4, 0.3, a))
