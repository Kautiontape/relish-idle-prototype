class_name RaidDeathCard
extends Control
## The death frame: when Relish dies in a dungeon, one card before the result goes out. What killed
## her, what the last checkpoint banked, what is lost (RaidLogic.death_card_rows). It plays in the
## death beat RaidEndings already runs (the beat is `death.card_s` long instead of 0.9 s, except in the
## measuring bot, which never waits); a click, SPACE or Enter after `death.skip_after_s` ends it early. The
## result and its single emit are RaidEndings' and unchanged: the card only holds the frame.
## A window close during it stays a death (RaidEndings.close_request). Numbers: raid.json `death`.

signal dismissed

var rows: Array = []
var _heights: Array = []   # row_heights(rows), made once in setup
var _total := 0.0
var _t := 0.0
var _skip_after := 0.8
var _fade := 0.3
var _skipped := false
var _words: Dictionary = {}   # raid.json `death`: title, sub, foot and the card's geometry


## Each row's height: 34 for a line that fits the value column, more only for a row that wraps (its text height
## plus 16): a long value wraps to a second line and its row grows (never clipped). Static so a test can measure;
## `dc` is raid.json's `death` block (the card's geometry).
static func row_heights(p_rows: Array, f: Font, dc: Dictionary) -> Array:
	var vw: float = float(dc.get("card_w", 560.0)) - float(dc.get("card_pad", 22.0)) * 2.0 - float(dc.get("label_w", 120.0))   # geometry falls back to the shipped numbers
	var vpx := int(dc.get("value_px", 18))
	var out: Array = []
	for r in p_rows:
		var sz := f.get_multiline_string_size(str(r["text"]), HORIZONTAL_ALIGNMENT_LEFT, vw, vpx)
		out.append(34.0 if sz.y <= f.get_height(vpx) + 0.5 else maxf(34.0, sz.y + 16.0))
	return out


func setup(p_rows: Array) -> void:
	rows = p_rows
	var c: Dictionary = ConfigDb.data.get("raid", {}).get("death", {})
	_heights = row_heights(rows, ThemeDB.fallback_font, c)
	_total = 0.0
	for rh in _heights:
		_total += float(rh)
	_skip_after = float(c.get("skip_after_s", 0.8))
	_fade = float(c.get("fade_s", 0.3))
	_words = c
	mouse_filter = Control.MOUSE_FILTER_IGNORE   # a child of the HUD's CanvasLayer has no parent Control: it sizes itself (_draw reads the viewport)
	set_process(true)
	queue_redraw()


func can_skip() -> bool:
	return _t >= _skip_after


func _process(delta: float) -> void:
	var was := can_skip()
	var a := _alpha()
	_t += delta / maxf(0.05, Engine.time_scale)
	if _alpha() != a or can_skip() != was:
		queue_redraw()


func _alpha() -> float:
	return 1.0 if (Pulse.reduced_motion or _fade <= 0.0) else clampf(_t / _fade, 0.0, 1.0)


func _input(ev: InputEvent) -> void:
	if _skipped:
		return
	if RaidLogic.card_skips(ev, _t, _skip_after):   # the rule both cards share
		_skipped = true
		get_viewport().set_input_as_handled()
		dismissed.emit()


func _draw() -> void:
	var f := ThemeDB.fallback_font
	var a := _alpha()
	var dc := _words   # raid.json `death`: the geometry as well as the words
	var w := float(dc.get("card_w", 560.0))   # geometry falls back to the shipped numbers (the words keep their blank fallback)
	var pad := float(dc.get("card_pad", 22.0))
	var lw := float(dc.get("label_w", 120.0))
	var vw := w - pad * 2.0 - lw
	var vpx := int(dc.get("value_px", 18))
	var heights := _heights
	var h := pad * 2.0 + 44.0 + float(dc.get("sub_h", 30.0)) + _total + 30.0
	var vs := get_viewport_rect().size
	var o := (vs - Vector2(w, h)) * 0.5
	draw_rect(Rect2(Vector2.ZERO, vs), Palette.c("ground", float(dc.get("backdrop_a", 0.8)) * a))
	draw_rect(Rect2(o, Vector2(w, h)), Palette.c("ground", float(dc.get("plate_a", 0.96)) * a))
	draw_rect(Rect2(o, Vector2(w, h)), Palette.c("danger", 0.8 * a), false, 2.0)
	var x := o.x + pad
	var y := o.y + pad + 22.0
	draw_string(f, Vector2(x, y), str(_words.get("title", "")), HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Palette.c("danger", a))
	y += 28.0
	# the second-largest line, full text colour: a death ends the raid, not the game
	draw_string(f, Vector2(x, y), str(_words.get("sub", "")), HORIZONTAL_ALIGNMENT_LEFT, w - pad * 2.0, int(dc.get("sub_px", 20)), Palette.c("text", a))
	y += 12.0 + float(dc.get("sub_h", 30.0))   # the row baselines sit as far under the sub-line as they sat under the title
	for i in rows.size():
		var r: Dictionary = rows[i]
		draw_string(f, Vector2(x, y), str(r["label"]), HORIZONTAL_ALIGNMENT_LEFT, lw - 8.0, int(dc.get("label_px", 14)), Palette.c("text_dim", a))
		draw_multiline_string(f, Vector2(x + lw, y), str(r["text"]), HORIZONTAL_ALIGNMENT_LEFT, vw, vpx, -1, Palette.c(str(r["key"]), a))
		y += float(heights[i])
	if can_skip():
		draw_string(f, Vector2(x, y + 4.0), str(_words.get("foot", "")), HORIZONTAL_ALIGNMENT_LEFT, -1, int(dc.get("foot_px", 14)), Palette.c("text_dim", a))
