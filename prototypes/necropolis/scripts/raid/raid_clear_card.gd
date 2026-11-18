class_name RaidClearCard
extends Control
## The clear card: when Relish opens the warden's chest, one card names what was won (the fort is yours,
## the warden broken, the loot, what comes next: RaidLogic.clear_card_title / clear_card_rows) before the
## win goes out. A click or SPACE after `clear.skip_after_s` dismisses it; RaidWardenRun also ends it after
## `clear.card_s`. The result and its single emit are RaidEndings' (finish guards a double).
## Modelled on RaidDeathCard. Numbers: raid.json `clear`.

signal dismissed

var title := ""
var rows: Array = []
var _t := 0.0
var _skip_after := 0.8
var _fade := 0.3
var _skipped := false


func setup(p_title: String, p_rows: Array) -> void:
	title = p_title
	rows = p_rows
	var c: Dictionary = ConfigDb.data.get("raid", {}).get("clear", {})
	_skip_after = float(c.get("skip_after_s", 0.8))
	_fade = float(c.get("fade_s", 0.3))
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


## A left click, or a SPACE press that is not an echo (a SPACE already held when the card opened is an echo
## or a press before the gate: it never skips it), once the skip gate is open.
func _input(ev: InputEvent) -> void:
	if _skipped or not can_skip():
		return
	var go := false
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		go = true
	elif ev is InputEventKey and ev.pressed and not ev.echo and ev.keycode == KEY_SPACE:
		go = true
	if go:
		_skipped = true
		get_viewport().set_input_as_handled()
		dismissed.emit()


func _draw() -> void:
	var f := ThemeDB.fallback_font
	var a := _alpha()
	var dc: Dictionary = RaidLogic.DEATH_CARD
	var w: float = dc["w"]
	var pad: float = dc["pad"]
	var lw: float = dc["label_w"]
	var row_h := 34.0
	var h := pad * 2.0 + 44.0 + row_h * rows.size() + 30.0
	var vs := get_viewport_rect().size
	var o := (vs - Vector2(w, h)) * 0.5
	draw_rect(Rect2(Vector2.ZERO, vs), Palette.c("ground", 0.55 * a))
	draw_rect(Rect2(o, Vector2(w, h)), Palette.c("ground", 0.96 * a))
	draw_rect(Rect2(o, Vector2(w, h)), Palette.c("vei", 0.8 * a), false, 2.0)
	var x := o.x + pad
	var y := o.y + pad + 22.0
	draw_string(f, Vector2(x, y), title, HORIZONTAL_ALIGNMENT_LEFT, w - pad * 2.0, 24, Palette.c("vei", a))
	y += 40.0
	for r in rows:
		draw_string(f, Vector2(x, y), str(r["label"]), HORIZONTAL_ALIGNMENT_LEFT, 110.0, 13, Palette.c("text_dim", a))
		draw_string(f, Vector2(x + lw, y), str(r["text"]), HORIZONTAL_ALIGNMENT_LEFT, w - pad * 2.0 - lw, int(dc["value_px"]), Palette.c(str(r["key"]), a))
		y += row_h
	if can_skip():
		draw_string(f, Vector2(x, y + 4.0), "click to return to the realm", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Palette.c("text_dim", a))
