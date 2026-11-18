class_name RaidLegend
extends Control
## The raid's control legend (dungeon-i T1). Shawn's first raids: "I couldn't figure out how to move at
## first." Open, it says what the mouse and Space do; collapsed, it is a "? CONTROLS" chip. The HUD opens
## it every raid until a fort has been taken (RaidLogic.legend_open_at_start), then collapsed.
##
## Mouse only: a left press on the header row (open) or on the chip (collapsed) toggles it. No key does.
## Only the toggling press is accepted; every other mouse event passes through to the raid (a right
## press on the legend still starts the trance). Anchored by its bottom-left corner: it grows upward.
## No autoloads (Palette reads its file when the config is absent).

const L_HEADER := "CONTROLS"
const L_HIDE := "hide"
const L_CHIP := "? CONTROLS"
const L_CLICK := "LEFT CLICK"
const L_MOVE := "move Relish"
const L_SPACE := "HOLD SPACE"
const L_OR := "or"
const L_MOUSE := "RIGHT MOUSE"
const L_SLOW := "slow time"
const L_DRAG := "then drag a loop around essence to RAISE undead"
const CAP_PAD := 7.0     # a key cap's side padding
const CAP_VPAD := 5.0    # and its top and bottom
const MIN_PX := 13      # nothing in the legend is set smaller
const HDR_HIT := 44.0   # the header's hit band is at least this tall (touch floor)

var is_open := true
var _row_px := 15
var _key_px := 14
var _pad := 10.0
var _gap := 8.0
var _alpha := 0.97
var _chip := Vector2(140.0, 44.0)
var _header_rect := Rect2()
var _rows: Array = []   # per row: [y, [[kind, text, x, w], ...]] kind "cap" or "txt"
var _hdr_hide_x := 0.0
var _hdr_base := 0.0   # the header label's baseline


func _init() -> void:
	focus_mode = Control.FOCUS_NONE
	mouse_filter = Control.MOUSE_FILTER_PASS   # only the toggling press is accepted; everything else reaches the raid


## `cfg` is raid.json's hud.legend; `open` the state to start in.
func setup(cfg: Dictionary, open: bool) -> void:
	_row_px = maxi(MIN_PX, int(cfg.get("row_px", 15)))
	_key_px = maxi(MIN_PX, int(cfg.get("key_px", 14)))
	_pad = float(cfg.get("pad_px", 10))
	_gap = float(cfg.get("gap_px", 8))
	_alpha = float(cfg.get("plate_alpha", 0.97))
	_chip = Vector2(float(cfg.get("chip_w", 140)), maxf(44.0, float(cfg.get("chip_h", 44))))
	is_open = open
	_fit()


## Flip open and collapsed. The bottom-left corner stays where it is (it grows upward).
func toggle() -> void:
	is_open = not is_open
	_fit()


func _w(s: String, px: int) -> float:
	return ThemeDB.fallback_font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1.0, px).x


func _fit() -> void:
	var bottom := position.y + size.y
	_rows = []
	if is_open:
		var cap_h := float(_key_px) + 2.0 * CAP_VPAD
		var hdr_h := float(_key_px) + 4.0
		# the header is the toggle's target: its hit band is at least HDR_HIT tall (the touch floor), the label
		# centred in it, so the plate grows upward by what the compact row lacked
		var hb := maxf(HDR_HIT, _pad + hdr_h + _gap * 0.5)
		_header_rect = Rect2(0.0, 0.0, 0.0, hb)
		_hdr_base = (hb - hdr_h) * 0.5 + float(_key_px) * 0.85
		var y := hb + _gap * 0.5
		var widest := _w(L_HEADER, _key_px) + 24.0 + _w(L_HIDE, _key_px)
		var spec := [
			[cap_h, [["cap", L_CLICK], ["txt", L_MOVE]]],
			[cap_h, [["cap", L_SPACE], ["txt", L_OR], ["cap", L_MOUSE], ["txt", L_SLOW]]],
			[float(_row_px) + 4.0, [["txt", L_DRAG]]],
		]
		for row in spec:
			var x := _pad
			var items := []
			for it in row[1]:
				var px := _key_px if it[0] == "cap" else _row_px
				var tw := _w(it[1], px)
				var bw := tw + 2.0 * CAP_PAD if it[0] == "cap" else tw
				items.append([it[0], it[1], x, bw])
				x += bw + _gap
			_rows.append([y, row[0], items])
			widest = maxf(widest, x - _gap - _pad)
			y += float(row[0]) + _gap
		var w := widest + 2.0 * _pad
		var h := y - _gap + _pad
		_header_rect.size.x = w
		_hdr_hide_x = w - _pad - _w(L_HIDE, _key_px)
		size = Vector2(w, h)
	else:
		size = _chip
	custom_minimum_size = Vector2.ZERO
	position.y = bottom - size.y
	queue_redraw()


## True only for a left press on the header row (open) or anywhere on the chip (collapsed). No key toggles.
func classify(ev: InputEvent) -> bool:
	if not (ev is InputEventMouseButton):
		return false
	var mb := ev as InputEventMouseButton
	if mb.button_index != MOUSE_BUTTON_LEFT or not mb.pressed:
		return false
	if is_open:
		return _header_rect.has_point(mb.position)
	return Rect2(Vector2.ZERO, size).has_point(mb.position)


func _gui_input(ev: InputEvent) -> void:
	if classify(ev):
		accept_event()
		toggle()


func _draw() -> void:
	var font := ThemeDB.fallback_font
	var r := Rect2(Vector2.ZERO, size)
	draw_rect(r, Palette.c("ground", _alpha))
	draw_rect(r.grow(-0.75), Palette.c("text_dim"), false, 1.5)
	if not is_open:
		draw_string(font, Vector2(0.0, size.y * 0.5 + float(_key_px) * 0.36), L_CHIP,
			HORIZONTAL_ALIGNMENT_CENTER, size.x, _key_px, Palette.c("text"))
		return
	var hy := _hdr_base
	draw_string(font, Vector2(_pad, hy), L_HEADER, HORIZONTAL_ALIGNMENT_LEFT, -1.0, _key_px, Palette.c("text"))
	draw_string(font, Vector2(_hdr_hide_x, hy), L_HIDE, HORIZONTAL_ALIGNMENT_LEFT, -1.0, _key_px, Palette.c("text"))
	for row in _rows:
		var y: float = row[0]
		var rh: float = row[1]
		for it in row[2]:
			var x: float = it[2]
			var bw: float = it[3]
			if it[0] == "cap":
				draw_rect(Rect2(x, y, bw, rh), Palette.c("text"), false, 1.5)   # a bright outline: the cap reads as a key
				draw_string(font, Vector2(x + CAP_PAD, y + rh * 0.5 + float(_key_px) * 0.36), it[1],
					HORIZONTAL_ALIGNMENT_LEFT, -1.0, _key_px, Palette.c("text"))
			else:
				draw_string(font, Vector2(x, y + rh * 0.5 + float(_row_px) * 0.36), it[1],
					HORIZONTAL_ALIGNMENT_LEFT, -1.0, _row_px, Palette.c("text"))
