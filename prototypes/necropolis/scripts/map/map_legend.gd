class_name MapLegend
extends PanelContainer
## The fort legend (bottom-left, just above the valve): each of the four states a fort ring can read
## as, drawn with the map's own glyph and ring (MapFortGlyph.draw_state) at a small size, beside its
## word and one short line (the glossary's meanings; words in configs/map_view.json
## "clarity.legend"). Shown expanded while no fort has been taken (HudLogic.goal_shown), collapsed to
## a small "Legend" button after; a click toggles it, and the player's choice then stands for the
## session (kept here, not in a save). Static: nothing moves, so reduced motion changes nothing.

var model: MapModel
var valve: Control  # the legend sits just above it
var chip: Control  # the Relish chip: the legend stays below its bottom edge (HudLogic.legend_place)

var _open_user := -1  # -1: follow the game (open until a fort is taken), 0 closed, 1 open by the player's click
var _head: Button
var _rows: VBoxContainer
var _shown_open := true
var _legend_key: Array = []  # what refresh() last ran for (HudLogic.legend_key); empty: lay out on the next frame


## One state's glyph in a small box: its ring and its shape, drawn as the fort layer draws them.
class Glyph extends Control:
	var state := ""

	func _draw() -> void:
		var cfg := MapLogic.cfg()
		var lc: Dictionary = cfg["clarity"]["legend"]
		var n: Dictionary = cfg["nodes"]
		var c := size * 0.5
		var r := float(lc["ring_r_px"])
		var hw := float(n["hairline_screen_px"])
		var held := state == IdleLogic.SAFE
		# the ring: held draws heavy in undead green, the rest the hairline (ownership by weight)
		if held:
			var w := hw * float(n["held_ring_weight"])
			for l in NodeLogic.capped_layers(Palette.c("undead"), w, 1.0, float(n["arc_halo_max_px"])):
				draw_arc(c, r, 0.0, TAU, LineGlow.segments(r, TAU), l[1], l[0])
		else:
			draw_arc(c, r, 0.0, TAU, LineGlow.segments(r, TAU), Palette.c(str(n["hairline_key"]), float(n["hairline_alpha"])), hw)
		MapFortGlyph.draw_state(self, state, c, float(n["state_glyph_px"]) * 0.5, float(n["state_stroke_px"]),
			float(n["state_halo_max_px"]), float(n["state_slash_px"]), n)


func _ready() -> void:
	var cfg := MapLogic.cfg()
	var lc: Dictionary = cfg["clarity"]["legend"]
	set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	grow_vertical = Control.GROW_DIRECTION_BEGIN  # a taller legend rises off the valve, never into it
	var m: Array = cfg["controls"]["valve_margin_px"]
	offset_left = float(m[0])
	custom_minimum_size.x = float(lc["width_px"])
	add_theme_stylebox_override("panel", MapUi.plate_box(float(lc["plate_alpha"]), int(lc["pad_px"])))
	mouse_filter = Control.MOUSE_FILTER_STOP
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", int(lc["row_gap_px"]))
	add_child(vb)
	_head = Button.new()
	MapUi.style_button(_head, int(cfg["font_label"]))
	_head.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_head.pressed.connect(_toggle)
	vb.add_child(_head)
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", int(lc["row_gap_px"]))
	vb.add_child(_rows)
	for row in lc["rows"]:
		_rows.add_child(_row(row, lc))
	refresh()


func _row(row: Dictionary, lc: Dictionary) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", int(lc["glyph_gap_px"]))
	var g := Glyph.new()
	g.state = _glyph_state(str(row["state"]))
	var side := float(lc["glyph_px"])
	g.custom_minimum_size = Vector2(side, side)
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(g)
	var word := Label.new()  # the word beside the glyph, then its line beside it (wrapping in its own column)
	word.text = str(row["word"])
	word.custom_minimum_size.x = float(lc["word_w_px"])
	MapType.style_label(word, str(row["key"]), int(MapLogic.cfg()["font_label"]))
	word.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(word)
	var line := Label.new()
	line.text = str(row["line"])
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.custom_minimum_size.x = 1.0
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	MapType.style_label(line, "text_dim", int(MapLogic.cfg()["font_label"]))
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(line)
	return h


## The map's state a legend row draws: Vei's and retaken are both a fort of hers (a living square;
## the map tells a retaken one by its danger tag), held draws safe, overrun is its own hollow square.
func _glyph_state(id: String) -> String:
	return HudLogic.legend_glyph_state(id)


## Whether the legend shows expanded now: the player's click if there was one, else open until a
## fort is taken.
func is_open() -> bool:
	return HudLogic.legend_open(model.hud, _open_user)


## Lays out only when an input changed (HudLogic.legend_key): its parent's size, open or closed,
## the Relish chip's and the valve's rects, the row count. The first frame has no key, so it lays out.
func _process(_delta: float) -> void:
	if model == null:
		return
	var vrect := valve.get_global_rect() if valve != null else Rect2()
	var crect := chip.get_global_rect() if chip != null and is_instance_valid(chip) else Rect2()
	var key := HudLogic.legend_key(get_parent_area_size(), is_open(), _open_user, crect, vrect, _rows.get_child_count())
	if key == _legend_key:
		return
	_legend_key = key
	refresh()


## Places the legend just above the valve, as tall as it is (a container does not shrink its own
## rect), and sets its open or closed look.
func refresh() -> void:
	if model == null:
		return
	var cfg := MapLogic.cfg()
	var lc: Dictionary = cfg["clarity"]["legend"]
	var want := is_open()
	var pad := 2.0 * float(lc["pad_px"])
	var head_h := _head.get_combined_minimum_size().y
	var rows_h := 0.0
	for r in _rows.get_children():
		rows_h += (r as Control).get_combined_minimum_size().y
	var n := _rows.get_child_count()
	var h_full := pad + head_h + float(lc["row_gap_px"]) * float(n) + rows_h
	var h_compact := pad + head_h + float(lc["compact_row_gap_px"]) * float(n) + rows_h
	var x := offset_left
	var w := float(lc["width_px"])
	var gap := float(lc["gap_above_valve_px"])
	var vrect := valve.get_global_rect() if valve != null else Rect2(0.0, get_parent_area_size().y + gap, w, 0.0)
	var crect := chip.get_global_rect() if chip != null and is_instance_valid(chip) else Rect2()
	var p := HudLogic.legend_place(crect, vrect, x, w, h_full, h_compact, pad + head_h, want, _open_user == 1, gap)
	var mode := str(p["mode"])
	_shown_open = mode != "closed"
	if _rows.visible != _shown_open:
		_rows.visible = _shown_open
	var sep := int(lc["compact_row_gap_px"] if mode == "compact" else lc["row_gap_px"])
	if _rows.get_theme_constant("separation") != sep:
		_rows.add_theme_constant_override("separation", sep)
		(_rows.get_parent() as VBoxContainer).add_theme_constant_override("separation", sep)
	var txt := str(lc["open_text" if _shown_open else "closed_text"])
	if _head.text != txt:
		_head.text = txt
	var rect: Rect2 = p["rect"]
	offset_right = offset_left + w
	offset_bottom = rect.end.y - get_parent_area_size().y
	offset_top = offset_bottom - rect.size.y


func _toggle() -> void:
	_open_user = 0 if _shown_open else 1
	refresh()
