class_name RaidTraceFeedback
extends Node2D
## Mandatory circle feedback (ported from raid-and-raise): flash the fitted
## ideal ring against the player's actual trace, with "SCORE — WORD", for about
## 1.1 real seconds. The player must see WHY a 73 was a 73.

var trace := PackedVector2Array()
var fitted_center := Vector2.ZERO
var fitted_radius := 0.0
var score := 0
var valid := false
var raised_n := 0          # set by perform_raise: units the circle made
var raised_tier := ""      # display tier: chaff | soldier | elite
var _age := 0.0


func _ready() -> void:
	z_index = 75


func _life() -> float:
	return float(ConfigDb.v("circle", "feedback_hold_s", 0.7)) + 0.4


func _process(delta: float) -> void:
	_age += delta / maxf(0.05, Engine.time_scale)  # real time, unaffected by trance
	if _age > _life():
		queue_free()
		return
	queue_redraw()


## Score bands keep their words and thresholds; colour comes from Palette keys
## only, picked apart by luminance (no rainbow).
const BANDS := [
	{ "min": 98, "key": "vei", "word": "PERFECT!" },
	{ "min": 90, "key": "undead_core", "word": "GREAT" },
	{ "min": 80, "key": "undead", "word": "GOOD" },
	{ "min": 70, "key": "undead", "word": "OKAY" },
	{ "min": 60, "key": "undead", "word": "SHAKY" },
	{ "min": 50, "key": "text_dim", "word": "POOR" },
	{ "min": 0, "key": "text_dim", "word": "AWFUL" },
]


func _band() -> Dictionary:
	for b in BANDS:
		if score >= b.min:
			return b
	return BANDS[-1]


func _grade_word() -> String:
	return _band().word


func _grade_color() -> Color:
	return Palette.c(str(_band().key))


func _draw() -> void:
	var hold := float(ConfigDb.v("circle", "feedback_hold_s", 0.7))
	var a := 1.0 if _age < hold else clampf(1.0 - (_age - hold) / 0.4, 0.0, 1.0)
	var col := _grade_color()

	# the player's actual trace, in Relish's violet
	if trace.size() >= 2:
		var pts := PackedVector2Array()
		for p in trace:
			pts.append(to_local(p))
		LineGlow.polyline(self, pts, Palette.c("relish", a * 0.9), 3.0, 0.5)

	if valid and fitted_radius > 0.0:
		var c := to_local(fitted_center)
		var segs := 36
		var ring_col := col
		ring_col.a = a * 0.9
		for i in segs:
			if i % 2 == 0:
				var a0 := TAU * i / segs
				var a1 := TAU * (i + 0.8) / segs
				draw_arc(c, fitted_radius, a0, a1, 4, ring_col, 2.0)
		_draw_notches(c, ring_col)
		var text_col := col
		text_col.a = a
		var head := "%d — %s" % [score, _grade_word()]
		_plate(c + Vector2(0, -fitted_radius - 14), head, a)
		draw_string(ThemeDB.fallback_font, c + Vector2(-80, -fitted_radius - 14),
			head, HORIZONTAL_ALIGNMENT_CENTER, 160, 22, text_col)
		if raised_n > 0 and raised_tier != "":
			var tail := "×%d %s" % [raised_n, raised_tier.to_upper()]
			_plate(c + Vector2(0, fitted_radius + 28), tail, a)
			draw_string(ThemeDB.fallback_font, c + Vector2(-80, fitted_radius + 28),
				tail, HORIZONTAL_ALIGNMENT_CENTER, 160, 22, text_col)
	else:
		var c2 := to_local(trace[trace.size() / 2]) if trace.size() > 0 else Vector2.ZERO
		draw_string(ThemeDB.fallback_font, c2 + Vector2(-80, -20),
			"0 — NOT A CIRCLE", HORIZONTAL_ALIGNMENT_CENTER, 160, 22, Palette.c("danger", a))


## A thin dark plate under a centred 22 px label whose baseline sits at `base` (walls and strokes
## run under the ring's words).
func _plate(base: Vector2, text: String, a: float) -> void:
	var w := ThemeDB.fallback_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
	draw_rect(Rect2(base + Vector2(-w * 0.5 - 6.0, -21.0), Vector2(w + 12.0, 27.0)), Palette.c("ground", 0.62 * a))


## Tier shape-code: chaff 1 notch, soldier 2, elite 3 (short radial ticks on the ring), spread
## evenly from the top, so the tier reads without the colour.
func _draw_notches(c: Vector2, col: Color) -> void:
	var n := 3 if raised_tier == "elite" else (2 if raised_tier == "soldier" else (1 if raised_tier == "chaff" else 0))
	if n == 0:
		return
	var nc: Dictionary = ConfigDb.data.get("raid", {}).get("trace_notch", {})
	var len_px := float(nc.get("len_px", 9.0))
	var w := float(nc.get("width_px", 3.0))
	for i in n:
		var dir := Vector2.UP.rotated(TAU * i / float(n))
		draw_line(c + dir * (fitted_radius - len_px), c + dir * (fitted_radius + len_px), col, w)
