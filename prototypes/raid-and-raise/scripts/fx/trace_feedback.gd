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

const BANDS := [
	{ "min": 98, "color": Color(0.40, 1.00, 0.95), "word": "PERFECT!", "rainbow": true },
	{ "min": 90, "color": Color(0.40, 1.00, 0.95), "word": "GREAT" },
	{ "min": 80, "color": Color(0.45, 0.95, 0.45), "word": "GOOD" },
	{ "min": 70, "color": Color(0.70, 0.90, 0.35), "word": "OKAY" },
	{ "min": 60, "color": Color(1.00, 0.85, 0.30), "word": "SHAKY" },
	{ "min": 50, "color": Color(1.00, 0.65, 0.25), "word": "POOR" },
	{ "min": 0, "color": Color(1.00, 0.50, 0.28), "word": "AWFUL" },
]

const RAINBOW_HZ := 0.6       # full hue cycle every ~1.6s
const RAINBOW_SPATIAL := 1.5  # hue offset around the ring (turns = number of color bands visible)

func _band() -> Dictionary:
	for b in BANDS:
		if score >= b.min:
			return b
	return BANDS[-1]

func _is_rainbow() -> bool:
	return _band().get("rainbow", false)

func _grade_word() -> String:
	return _band().word

## Static color for non-rainbow bands; for rainbow, a representative hue at the current time.
func _grade_color() -> Color:
	var b := _band()
	if b.get("rainbow", false):
		return _rainbow_color(0.0)
	return b.color

## phase: 0..1 spatial offset (e.g. fraction around the ring) so the rainbow sweeps.
func _rainbow_color(phase: float) -> Color:
	var h := fposmod(_age * RAINBOW_HZ + phase * RAINBOW_SPATIAL, 1.0)
	return Color.from_hsv(h, 0.85, 1.0)

func _draw() -> void:
	var hold := float(ConfigDb.v("circle", "feedback_hold_s"))
	var a := 1.0 if _age < hold else clampf(1.0 - (_age - hold) / 0.4, 0.0, 1.0)
	var rainbow := _is_rainbow()
	var col := _grade_color()

	# player's trace
	if trace.size() >= 2:
		var pts := PackedVector2Array()
		for p in trace:
			pts.append(to_local(p))
		if rainbow:
			# per-segment hue sweep along the stroke
			for i in pts.size() - 1:
				var hue := _rainbow_color(float(i) / float(pts.size() - 1))
				draw_line(pts[i], pts[i + 1], Color(hue.r, hue.g, hue.b, a * 0.9), 3.0)
		else:
			draw_polyline(pts, Color(col.r, col.g, col.b, a * 0.9), 3.0)

	if valid and fitted_radius > 0.0:
		var c := to_local(fitted_center)
		var segs := 36
		for i in segs:
			if i % 2 == 0:
				var a0 := TAU * i / segs
				var a1 := TAU * (i + 0.8) / segs
				var ring_col := Color(1, 1, 1, a * 0.8)
				if rainbow:
					var hue := _rainbow_color(float(i) / float(segs))
					ring_col = Color(hue.r, hue.g, hue.b, a * 0.9)
				draw_arc(c, fitted_radius, a0, a1, 4, ring_col, 2.0)
		var text_col := _rainbow_color(0.0) if rainbow else col
		draw_string(ThemeDB.fallback_font, c + Vector2(-80, -fitted_radius - 14),
			"%d — %s" % [score, _grade_word()], HORIZONTAL_ALIGNMENT_CENTER, 160, 22,
			Color(text_col.r, text_col.g, text_col.b, a))
	else:
		var c2 := to_local(trace[trace.size() / 2]) if trace.size() > 0 else Vector2.ZERO
		draw_string(ThemeDB.fallback_font, c2 + Vector2(-80, -20),
			"0 — NOT A CIRCLE", HORIZONTAL_ALIGNMENT_CENTER, 160, 22, Color(1, 0.4, 0.3, a))
