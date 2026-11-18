class_name RaidGoalBlock
extends Control
## T4: the dungeon's goal block (top centre, where the WardenBlock sits). A ground plate sized to its rows,
## each row centred and wrapped at its spaces to the plate's width. The HUD hands it the rows
## ({text, px, key}; key a Palette key) and reads `height` for its layout. Redrawn only when the rows
## change. No autoload, no input.

const PAD := 8.0
const GAP := 3.0

var plate_alpha := 0.62
var height := 0.0          # the plate's height for the rows set
var _rows: Array = []
var _lines: Array = []     # wrapped rows: {text, px, key}


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE


## Set the rows; nothing changes (no redraw) when they equal the ones shown.
func set_rows(rows: Array) -> void:
	if rows == _rows:
		return
	_rows = rows.duplicate(true)
	var w := maxf(40.0, offset_right - offset_left - 2.0 * (PAD + 4.0))
	var f := ThemeDB.fallback_font
	_lines = []
	height = 0.0
	for r in _rows:
		for ln in _wrap(f, str(r["text"]), int(r["px"]), w):
			_lines.append({"text": ln, "px": int(r["px"]), "key": str(r["key"])})
	if not _lines.is_empty():
		height = 2.0 * PAD - GAP
		for l in _lines:
			height += f.get_height(int(l["px"])) + GAP
	offset_bottom = offset_top + height
	queue_redraw()


func _wrap(f: Font, s: String, px: int, w: float) -> Array:
	var out: Array = []
	var cur := ""
	for word in s.split(" "):
		var t := word if cur == "" else cur + " " + word
		if cur != "" and f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x > w:
			out.append(cur)
			cur = word
		else:
			cur = t
	if cur != "":
		out.append(cur)
	return out


func _draw() -> void:
	if _lines.is_empty():
		return
	draw_rect(Rect2(Vector2.ZERO, Vector2(size.x, height)), Palette.c("ground", plate_alpha))
	var f := ThemeDB.fallback_font
	var y := PAD
	for l in _lines:
		var px := int(l["px"])
		var tw := f.get_string_size(str(l["text"]), HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
		draw_string(f, Vector2((size.x - tw) * 0.5, y + f.get_ascent(px)), str(l["text"]), HORIZONTAL_ALIGNMENT_LEFT, -1, px, Palette.c(str(l["key"])))
		y += f.get_height(px) + GAP
