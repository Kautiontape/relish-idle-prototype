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
var _t := 0.0
var _skip_after := 0.8
var _fade := 0.3
var _skipped := false


func setup(p_rows: Array) -> void:
	rows = p_rows
	var c: Dictionary = ConfigDb.data.get("raid", {}).get("death", {})
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
	var dc: Dictionary = RaidLogic.DEATH_CARD
	var w: float = dc["w"]
	var pad: float = dc["pad"]
	var lw: float = dc["label_w"]
	var row_h := 34.0
	var h := pad * 2.0 + 44.0 + row_h * rows.size() + 30.0
	var vs := get_viewport_rect().size
	var o := (vs - Vector2(w, h)) * 0.5
	draw_rect(Rect2(Vector2.ZERO, vs), Palette.c("ground", float(dc["backdrop_a"]) * a))
	draw_rect(Rect2(o, Vector2(w, h)), Palette.c("ground", float(dc["plate_a"]) * a))
	draw_rect(Rect2(o, Vector2(w, h)), Palette.c("danger", 0.8 * a), false, 2.0)
	var x := o.x + pad
	var y := o.y + pad + 22.0
	draw_string(f, Vector2(x, y), "RELISH FALLS", HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Palette.c("danger", a))
	y += 40.0
	for r in rows:
		draw_string(f, Vector2(x, y), str(r["label"]), HORIZONTAL_ALIGNMENT_LEFT, lw - 8.0, int(dc["label_px"]), Palette.c("text_dim", a))
		draw_string(f, Vector2(x + lw, y), str(r["text"]), HORIZONTAL_ALIGNMENT_LEFT, w - pad * 2.0 - lw, int(dc["value_px"]), Palette.c(str(r["key"]), a))
		y += row_h
	var foot := "the run ends here · click or SPACE to go on" if can_skip() else "the run ends here"
	draw_string(f, Vector2(x, y + 4.0), foot, HORIZONTAL_ALIGNMENT_LEFT, -1, int(dc["foot_px"]), Palette.c("text_dim", a))
