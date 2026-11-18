class_name RaidRetreatPanel
extends Control
## The retreat choice at an exit (Phase I, dungeon-i item 8). It replaces a ConfirmationDialog whose
## OK button took focus when it opened: Space is the trance key and also `ui_accept`, so one Space
## press with the dialog open confirmed a retreat (probed headless at cac5a17). Shawn's capture raids
## 4-9 ended "retreated" in 6-18 s without ever opening the trance, which fits that chain.
##
## Mouse only. A left click on RETREAT leaves; a left click on STAY closes it. The raid closes it
## too when Space, right mouse or Esc is pressed (`is_stay_key`: the player chose to fight) or when
## Relish walks off the exit. Nothing here takes focus and no key ever confirms. It is not modal:
## the raid runs on under it, and a click outside it still moves Relish. Its mouse filter is PASS: only a left
## button event on the plate is accepted, so a right press (the trance) and a dragged loop go through it.
## No autoloads (Palette reads its file when ConfigDb is absent), so tests drive this class headless.

signal chosen(retreat: bool)

## Sizes: raid.json hud.retreat (`configure`), these defaults when it is absent. Two columns: RETREAT NOW on
## the left, IF RELISH FALLS on the right (RaidLogic.retreat_keep_lines / retreat_fall_lines), `cols` = [left, right],
## each a list of {text, key}.
var w := 820.0          # the width asked for (hud.retreat w); `_w` is what the viewport allows
var margin := 16.0      # hud.retreat margin / gap: RaidLogic.retreat_panel_rect keeps the plate this far in from the viewport's edges and from the stat block
var gap := 16.0
var avoid_right_x := 0.0:   # the stat block plate's right edge in screen x (the HUD sets it); the plate sits right of it plus `gap`; a change re-places an open panel
	set(v):
		avoid_right_x = v
		_replace_if_moved()
var _placed_vp := Vector2.ZERO
var _placed_avoid := 0.0
var pad := 18.0
var title_px := 20
var head_px := 16
var line_px := 15
var line_h := 22.0      # the gap between two lines is line_h - the font's height at line_px, so a wrapped line adds the font's height
var col_gap := 32.0
var btn := Vector2(150.0, 44.0)   # 44 px tall: the touch-target floor
var btn_gap := 24.0
var plate_alpha := 0.97   # the panel's ground plate; a test holds its dim text at 4.5:1 over the brightest world colour

var head_keep := ""     # the column heads (hud.retreat head_keep / head_fall), set by configure
var head_fall := ""
var title := ""         # the title, the two buttons' words and the footer (hud.retreat title / btn_retreat / btn_stay / foot), set by configure
var btn_retreat := ""
var btn_stay := ""
var foot := ""
var cols: Array = [[], []]
var _w := 820.0
var _retreat_rect := Rect2()
var _stay_rect := Rect2()
var _hover := ""


func _init() -> void:
	focus_mode = Control.FOCUS_NONE
	# PASS: only a left-button event on the plate is accepted (`_gui_input`), so a left click never moves Relish
	# but a right press (the trance) and mouse motion (a loop dragged across the plate) reach the raid
	mouse_filter = Control.MOUSE_FILTER_PASS
	visible = false


## Sizes from raid.json hud.retreat (the HUD passes it; no autoload is read here). Missing keys keep the defaults.
func configure(c: Dictionary) -> void:
	w = float(c.get("w", w))
	margin = float(c.get("margin", margin))
	gap = float(c.get("gap", gap))
	_w = w
	pad = float(c.get("pad", pad))
	title_px = int(c.get("title_px", title_px))
	head_px = int(c.get("head_px", head_px))
	line_px = int(c.get("line_px", line_px))
	line_h = float(c.get("line_h", line_h))
	col_gap = float(c.get("col_gap", col_gap))
	btn = Vector2(float(c.get("btn_w", btn.x)), float(c.get("btn_h", btn.y)))
	btn_gap = float(c.get("btn_gap", btn_gap))
	plate_alpha = float(c.get("plate_alpha", plate_alpha))
	head_keep = str(c.get("head_keep", head_keep))
	head_fall = str(c.get("head_fall", head_fall))
	title = str(c.get("title", title))
	btn_retreat = str(c.get("btn_retreat", btn_retreat))
	btn_stay = str(c.get("btn_stay", btn_stay))
	foot = str(c.get("foot", foot))


## Show the panel with `p_cols` = [left, right] (RaidLogic.retreat_keep_lines, retreat_fall_lines), sized to
## them and centred in the view.
func open(p_cols: Array) -> void:
	cols = p_cols
	_fit()
	if is_inside_tree() and not get_viewport().size_changed.is_connected(_replace_if_moved):
		get_viewport().size_changed.connect(_replace_if_moved)   # a resize while it shows re-places it
	visible = true
	queue_redraw()


## New lines for the open panel (what a retreat pays changes as she picks things up): refit and redraw only
## when they differ from the ones shown.
func refresh_lines(p_cols: Array) -> void:
	if not visible or p_cols == cols:
		return
	cols = p_cols
	_fit()
	queue_redraw()


func close() -> void:
	visible = false
	_hover = ""


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT and _hover != "":
		_hover = ""
		queue_redraw()


func is_open() -> bool:
	return visible


func retreat_rect() -> Rect2:
	return _retreat_rect


func stay_rect() -> Rect2:
	return _stay_rect


## One column's width.
func _col_w() -> float:
	return RaidLogic.retreat_col_w(_w, pad, col_gap)


## The wrapped row count of one line in a column.
func _rows_of(text: String) -> int:
	var f := ThemeDB.fallback_font
	var fh := f.get_height(line_px)
	return maxi(1, roundi(f.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, _col_w(), line_px).y / fh))


## One line's height: a single row is line_h; each wrapped row adds the font's height.
func _line_cost(text: String) -> float:
	return line_h + float(_rows_of(text) - 1) * ThemeDB.fallback_font.get_height(line_px)


func _col_h(col: Array) -> float:
	var h := 0.0
	for ln in col:
		h += _line_cost(str(ln["text"]))
	return h


## The panel's size for its lines, and the two button rects (local coordinates).
func _fit() -> void:
	# the width the viewport allows (RaidLogic.retreat_panel_rect), before the columns are measured with it
	var vp := get_viewport_rect().size if is_inside_tree() else Vector2.ZERO
	var cfg := {"w": w, "margin": margin, "gap": gap}
	_w = RaidLogic.retreat_panel_rect(vp, cfg, avoid_right_x).size.x if vp.x > 0.0 else w
	var body := maxf(_col_h(cols[0]), _col_h(cols[1]))
	var h := pad + 30.0 + float(head_px) + 10.0 + body + 14.0 + btn.y + 8.0 + 18.0 + pad
	custom_minimum_size = Vector2.ZERO   # the plate's size is set outright (a stale, taller minimum would hold a shrunk plate open)
	size = Vector2(_w, h)
	var by := h - pad - 18.0 - 8.0 - btn.y
	var x0 := (_w - 2.0 * btn.x - btn_gap) * 0.5
	_retreat_rect = Rect2(Vector2(x0, by), btn)
	_stay_rect = Rect2(Vector2(x0 + btn.x + btn_gap, by), btn)
	_placed_vp = vp
	_placed_avoid = avoid_right_x
	if is_inside_tree():
		position = RaidLogic.retreat_panel_rect(vp, cfg, avoid_right_x, h).position


## The open panel's inputs moved (the viewport resized, or the stat block's right edge changed): fit and place it
## again. Nothing is done while it is shut or when neither changed.
func _replace_if_moved() -> void:
	if not visible or not is_inside_tree():
		return
	if get_viewport_rect().size == _placed_vp and is_equal_approx(avoid_right_x, _placed_avoid):
		return
	_fit()
	queue_redraw()


## What `ev` does to the open panel: "retreat" only for a left press on RETREAT, "stay" for a left
## press on STAY, else "". No key event ever returns "retreat" (Space, Enter and `ui_accept` least of all).
func classify(ev: InputEvent) -> String:
	if not (ev is InputEventMouseButton):
		return ""
	var mb := ev as InputEventMouseButton
	if mb.button_index != MOUSE_BUTTON_LEFT or not mb.pressed:
		return ""
	if _retreat_rect.has_point(mb.position):
		return "retreat"
	if _stay_rect.has_point(mb.position):
		return "stay"
	return ""


## A press that puts the panel away while it shows: Esc (the one key that means "stay and fight"), and Space or
## right mouse, which are the raise (the trance) and keep that one meaning: the panel is centred and swallows a
## left press, so left up it would sit over the motes the raise is about to circle. The raid closes the panel on
## it and then hands the event on as usual (raid.gd _unhandled_input); the foot says "Space raises and puts this away".
static func is_stay_key(ev: InputEvent) -> bool:
	if ev is InputEventKey:
		var k := ev as InputEventKey
		return k.pressed and not k.echo and (k.keycode == KEY_SPACE or k.keycode == KEY_ESCAPE)
	if ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		return mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT
	return false


## Act on a classified event: close, then say which way the player chose. "" does nothing.
func apply(choice: String) -> void:
	if choice == "" or not visible:
		return
	close()
	chosen.emit(choice == "retreat")


func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseMotion:
		var p: Vector2 = (ev as InputEventMouseMotion).position
		var hv := "retreat" if _retreat_rect.has_point(p) else ("stay" if _stay_rect.has_point(p) else "")
		if hv != _hover:
			_hover = hv
			queue_redraw()
		return
	if ev is InputEventMouseButton and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT and ev.pressed:
		accept_event()   # a left press on the plate never moves Relish; a release (a loop dragged here ends) and any other button reach the raid
		apply(classify(ev))


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var font := ThemeDB.fallback_font
	draw_rect(r, Palette.c("ground", plate_alpha))
	draw_rect(r, Palette.c("relish", 0.8), false, 2.0)
	draw_string(font, Vector2(pad, pad + 20.0), title, HORIZONTAL_ALIGNMENT_LEFT, _w - 2.0 * pad, title_px, Palette.c("vei"))
	var cw := _col_w()
	var top := pad + 30.0
	var heads := [head_keep, head_fall]
	var head_keys := ["relish", "danger"]
	for c in 2:
		var x := pad + float(c) * (cw + col_gap)
		draw_string(font, Vector2(x, top + float(head_px)), str(heads[c]), HORIZONTAL_ALIGNMENT_LEFT, cw, head_px, Palette.c(str(head_keys[c])))
		var y := top + float(head_px) + 10.0 + (line_h - font.get_height(line_px)) * 0.5 + font.get_ascent(line_px)
		for ln in cols[c]:
			var tx := str(ln["text"])
			draw_multiline_string(font, Vector2(x, y), tx, HORIZONTAL_ALIGNMENT_LEFT, cw, line_px, -1, Palette.c(str(ln.get("key", "text"))))
			y += _line_cost(tx)
	var mid := pad + cw + col_gap * 0.5
	draw_line(Vector2(mid, top + 4.0), Vector2(mid, _retreat_rect.position.y - 14.0), Palette.c("text_dim", 0.8), 1.0)
	_button(_retreat_rect, btn_retreat, Palette.c("relish", 1.0 if _hover == "retreat" else 0.7), Palette.c("vei"))
	_button(_stay_rect, btn_stay, Palette.c("text_dim", 1.0 if _hover == "stay" else 0.7), Palette.c("text"))
	draw_string(font, Vector2(0.0, size.y - pad), foot,
		HORIZONTAL_ALIGNMENT_CENTER, _w, 13, Palette.c("text_dim"))


func _button(rect: Rect2, text: String, border: Color, ink: Color) -> void:
	draw_rect(rect, Palette.c("ground", 0.9))
	draw_rect(rect, border, false, 2.0)
	draw_string(ThemeDB.fallback_font, Vector2(rect.position.x, rect.position.y + rect.size.y * 0.5 + 6.0), text,
		HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 16, ink)
