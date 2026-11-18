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
## the raid runs on under it, and a click outside it still moves Relish.
## No autoloads (Palette reads its file when ConfigDb is absent), so tests drive this class headless.

signal chosen(retreat: bool)

const W := 600.0
const PAD := 18.0
const TITLE_PX := 20
const LINE_PX := 15
const LINE_H := 22.0
const BTN := Vector2(150.0, 44.0)   # 44 px tall: the touch-target floor
const BTN_GAP := 24.0

var title := "LEAVE THE RAID?"
var lines := PackedStringArray()
var _retreat_rect := Rect2()
var _stay_rect := Rect2()
var _hover := ""


func _init() -> void:
	focus_mode = Control.FOCUS_NONE
	mouse_filter = Control.MOUSE_FILTER_STOP   # a click on the plate never reaches the floor (no move)
	visible = false


## Show the panel with `p_lines` (RaidLogic.retreat_lines), sized to them and centred in the view.
func open(p_lines: PackedStringArray) -> void:
	lines = p_lines
	_fit()
	visible = true
	queue_redraw()


func close() -> void:
	visible = false
	_hover = ""


func is_open() -> bool:
	return visible


func retreat_rect() -> Rect2:
	return _retreat_rect


func stay_rect() -> Rect2:
	return _stay_rect


## The panel's size for its lines, and the two button rects (local coordinates).
func _fit() -> void:
	var h := PAD + 30.0 + float(lines.size()) * LINE_H + 14.0 + BTN.y + 8.0 + 18.0 + PAD
	size = Vector2(W, h)
	custom_minimum_size = size
	var by := h - PAD - 18.0 - 8.0 - BTN.y
	var x0 := (W - 2.0 * BTN.x - BTN_GAP) * 0.5
	_retreat_rect = Rect2(Vector2(x0, by), BTN)
	_stay_rect = Rect2(Vector2(x0 + BTN.x + BTN_GAP, by), BTN)
	if is_inside_tree():
		position = ((get_viewport_rect().size - size) * 0.5).floor()


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


## A press that means "stay and fight" while the panel shows: Space or right mouse (the trance) or
## Esc. The raid closes the panel on it and then hands the event on as usual.
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
	if ev is InputEventMouseButton:
		accept_event()
		apply(classify(ev))


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var font := ThemeDB.fallback_font
	draw_rect(r, Palette.c("ground", 0.95))
	draw_rect(r, Palette.c("relish", 0.8), false, 2.0)
	draw_string(font, Vector2(PAD, PAD + 20.0), title, HORIZONTAL_ALIGNMENT_LEFT, W - 2.0 * PAD, TITLE_PX, Palette.c("vei"))
	var y := PAD + 30.0 + 16.0
	for ln in lines:
		draw_string(font, Vector2(PAD, y), ln, HORIZONTAL_ALIGNMENT_LEFT, W - 2.0 * PAD, LINE_PX, Palette.c("text"))
		y += LINE_H
	_button(_retreat_rect, "RETREAT", Palette.c("relish", 1.0 if _hover == "retreat" else 0.7), Palette.c("vei"))
	_button(_stay_rect, "STAY", Palette.c("text_dim", 1.0 if _hover == "stay" else 0.7), Palette.c("text"))
	draw_string(font, Vector2(0.0, size.y - PAD), "click to choose · Space or Esc: stay and fight",
		HORIZONTAL_ALIGNMENT_CENTER, W, 13, Palette.c("text_dim"))


func _button(rect: Rect2, text: String, border: Color, ink: Color) -> void:
	draw_rect(rect, Palette.c("ground", 0.9))
	draw_rect(rect, border, false, 2.0)
	draw_string(ThemeDB.fallback_font, Vector2(rect.position.x, rect.position.y + rect.size.y * 0.5 + 6.0), text,
		HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 16, ink)
