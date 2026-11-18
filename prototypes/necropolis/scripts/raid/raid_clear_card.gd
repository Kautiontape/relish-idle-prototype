class_name RaidClearCard
extends Control
## The clear card: when Relish opens the warden's chest, one card names what was won (the fort is yours,
## the warden broken, the loot, what comes next: RaidLogic.clear_card_title / clear_card_rows) before the
## win goes out. A click, SPACE or Enter after `clear.skip_after_s` dismisses it; RaidWardenRun also ends it after
## `clear.card_s`. The result and its single emit are RaidEndings' (finish guards a double).
## Modelled on RaidDeathCard. Numbers: raid.json `clear`.

signal dismissed

var title := ""
var rows: Array = []
var _t := 0.0
var _skip_after := 0.8
var _fade := 0.3
var _skipped := false
var _foot := ""   # raid.json clear.foot
var _dc: Dictionary = {}   # raid.json `death`: the card's geometry (card_w, card_pad, label_w, value_px, label_px, foot_px, backdrop_a, plate_a)


func setup(p_title: String, p_rows: Array) -> void:
	title = p_title
	rows = p_rows
	var c: Dictionary = ConfigDb.data.get("raid", {}).get("clear", {})
	_skip_after = float(c.get("skip_after_s", 0.8))
	_fade = float(c.get("fade_s", 0.3))
	_foot = str(c.get("foot", ""))
	_dc = ConfigDb.data.get("raid", {}).get("death", {})
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


## Skips as the death card does (RaidLogic.card_skips): any mouse button, or a non-echo Space, Enter or keypad
## Enter press, once the skip gate is open (a key already held when the card opened is an echo: it never skips).
func _input(ev: InputEvent) -> void:
	if _skipped:
		return
	if RaidLogic.card_skips(ev, _t, _skip_after):
		_skipped = true
		get_viewport().set_input_as_handled()
		dismissed.emit()


func _draw() -> void:
	var f := ThemeDB.fallback_font
	var a := _alpha()
	var dc := _dc
	var w := float(dc.get("card_w", 0.0))
	var pad := float(dc.get("card_pad", 0.0))
	var lw := float(dc.get("label_w", 0.0))
	var vw := w - pad * 2.0 - lw
	var vpx := int(dc.get("value_px", 0))
	var heights: Array = []   # a long value wraps to a second line: its row grows (never clipped)
	var total := 0.0
	for r in rows:
		var sz := f.get_multiline_string_size(str(r["text"]), HORIZONTAL_ALIGNMENT_LEFT, vw, vpx)
		var rh := maxf(34.0, sz.y + 16.0)
		heights.append(rh)
		total += rh
	var h := pad * 2.0 + 44.0 + total + 30.0
	var vs := get_viewport_rect().size
	var o := (vs - Vector2(w, h)) * 0.5
	draw_rect(Rect2(Vector2.ZERO, vs), Palette.c("ground", float(dc.get("backdrop_a", 0.0)) * a))
	draw_rect(Rect2(o, Vector2(w, h)), Palette.c("ground", float(dc.get("plate_a", 0.0)) * a))
	draw_rect(Rect2(o, Vector2(w, h)), Palette.c("vei", 0.8 * a), false, 2.0)
	var x := o.x + pad
	var y := o.y + pad + 22.0
	draw_string(f, Vector2(x, y), title, HORIZONTAL_ALIGNMENT_LEFT, w - pad * 2.0, 24, Palette.c("vei", a))
	y += 40.0
	for i in rows.size():
		var r: Dictionary = rows[i]
		draw_string(f, Vector2(x, y), str(r["label"]), HORIZONTAL_ALIGNMENT_LEFT, lw - 8.0, int(dc.get("label_px", 0)), Palette.c("text_dim", a))
		draw_multiline_string(f, Vector2(x + lw, y), str(r["text"]), HORIZONTAL_ALIGNMENT_LEFT, vw, vpx, -1, Palette.c(str(r["key"]), a))
		y += float(heights[i])
	if can_skip():
		draw_string(f, Vector2(x, y + 4.0), _foot, HORIZONTAL_ALIGNMENT_LEFT, -1, int(dc.get("foot_px", 0)), Palette.c("text_dim", a))
