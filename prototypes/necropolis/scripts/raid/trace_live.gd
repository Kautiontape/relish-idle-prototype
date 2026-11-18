class_name RaidTraceLive
extends Node2D
## The readout beside the pen while a loop is drawn: what letting go now would make (the score, the tier,
## the strength, the motes inside) and the score ladder. The trance creates it when tracing starts, feeds it
## `show_lines` once per appended point (the only grading the readout costs) and frees it when the trace
## clears. The text is RaidLogic.loop_readout (raid.json trace_notch live_*). World-space node scaled by
## 1/zoom, so its px are screen px; the plate sits live_gap_px off the pen tip, kept inside the viewport.

var raid: Node = null
var _lines: Array = []
var _color := Color.WHITE
var _tip := Vector2.ZERO       # the pen tip, world
var _size := Vector2.ZERO


func _ready() -> void:
	z_index = 80


static func _words() -> Dictionary:
	return ConfigDb.data.get("raid", {}).get("trace_notch", {})


## `lines` is RaidLogic.loop_readout's result (the last is the ladder); `score` picks the head's band colour
## (RaidTraceFeedback.band_for) when `valid`, else the plain text colour.
func show_lines(tip: Vector2, lines: Array, valid: bool, score: int) -> void:
	_tip = tip
	_lines = lines
	_color = Palette.c(str(RaidTraceFeedback.band_for(score).key)) if valid else Palette.c("text")
	var w := 0.0
	var h := 0.0
	for i in lines.size():
		var px := _px(i)
		w = maxf(w, ThemeDB.fallback_font.get_string_size(str(lines[i]), HORIZONTAL_ALIGNMENT_LEFT, -1, px).x)
		h += px + 4.0
	var pad := _pad()
	_size = Vector2(w + pad * 2.0, h + pad * 2.0 - 4.0)
	_place()
	queue_redraw()


func _process(_delta: float) -> void:
	if not _lines.is_empty():
		_place()   # the camera moves; the text does not grade again


func _px(i: int) -> float:
	var w := _words()
	return float(w.get("live_ladder_px", 15)) if i == _lines.size() - 1 else float(w.get("live_font_px", 20))


func _pad() -> float:
	return float(_words().get("live_pad_px", 8))


## Top-left of the plate: the gap right and below the pen tip on screen, flipped to the other side of the tip
## where it would leave the viewport, then clamped inside it.
func _place() -> void:
	var xf: Transform2D = raid.get_canvas_transform()
	var z := maxf(0.01, xf.x.length())
	scale = Vector2.ONE / z
	var view: Vector2 = raid.get_viewport_rect().size
	var tip: Vector2 = xf * _tip
	var gap := float(_words().get("live_gap_px", 26))
	var p := tip + Vector2(gap, gap)
	if p.x + _size.x > view.x:
		p.x = tip.x - gap - _size.x
	if p.y + _size.y > view.y:
		p.y = tip.y - gap - _size.y
	p.x = clampf(p.x, 0.0, maxf(0.0, view.x - _size.x))
	p.y = clampf(p.y, 0.0, maxf(0.0, view.y - _size.y))
	global_position = xf.affine_inverse() * p


func _draw() -> void:
	if _lines.is_empty():
		return
	var w := _words()
	draw_rect(Rect2(Vector2.ZERO, _size), Palette.c("ground", float(w.get("live_plate_alpha", 0.92))))
	var pad := _pad()
	var y := pad
	for i in _lines.size():
		var px := _px(i)
		var col := Palette.c("text_dim") if i == _lines.size() - 1 else _color
		draw_string(ThemeDB.fallback_font, Vector2(pad, y + px * 0.8), str(_lines[i]), HORIZONTAL_ALIGNMENT_LEFT, -1, int(px), col)
		y += px + 4.0
