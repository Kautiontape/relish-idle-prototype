class_name MapCatchup
extends CanvasLayer
## The router's catch-up progress screen: a plate over every scene with a title, a bar and a line
## ("3h 20m of 9h 05m"). While the catch-up runs it swallows all input (the plate stops the mouse,
## _input takes keys and the rest); it fades out after (at once under reduced motion). Decisions are
## RouterLogic's; the words and numbers are configs/map_view.json "catchup". main.gd feeds it update().

var _plate: ColorRect
var _title: Label
var _bar: ProgressBar
var _line: Label
var _alpha := 0.0
var _active := false
var _last_key := ""


func _init() -> void:
	var c := RouterLogic.catchup_cfg()
	name = "Catchup"
	layer = int(c["layer"])
	process_mode = Node.PROCESS_MODE_ALWAYS
	_plate = ColorRect.new()
	_plate.color = Palette.c("ground", float(c["plate_alpha"]))
	_plate.mouse_filter = Control.MOUSE_FILTER_STOP
	_plate.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_plate)
	var centre := CenterContainer.new()
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_plate.add_child(centre)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", int(c["gap_px"]))
	centre.add_child(box)
	_title = Label.new()
	_title.text = str(c["title"])
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	MapType.style_title(_title)
	box.add_child(_title)
	_bar = ProgressBar.new()
	_bar.min_value = 0.0
	_bar.max_value = 1.0
	_bar.show_percentage = false
	_bar.custom_minimum_size = Vector2(float(c["bar_w_px"]), float(c["bar_h_px"]))
	var track := StyleBoxFlat.new()
	track.bg_color = Palette.c("ring_track", float(c["track_alpha"]))
	var fill := StyleBoxFlat.new()
	fill.bg_color = Palette.c(str(c["fill_key"]))
	_bar.add_theme_stylebox_override("background", track)
	_bar.add_theme_stylebox_override("fill", fill)
	box.add_child(_bar)
	_line = Label.new()
	_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	MapType.style_label(_line, "text_dim", int(c["line_px"]))
	box.add_child(_line)
	visible = false


## One frame: `view` is view_catchup() (or the demo's). The bar and line change only when the
## values do; the plate's alpha follows RouterLogic.catchup_alpha.
func update(view: Dictionary, dt: float, reduced: bool) -> void:
	_active = RouterLogic.catchup_swallows(bool(view.get("active", false)))
	var c := RouterLogic.catchup_cfg()
	_alpha = RouterLogic.catchup_alpha(_alpha, _active, dt, float(c["fade_s"]), reduced)
	var shown := RouterLogic.catchup_shown(_alpha)
	if visible != shown:
		visible = shown
	if not shown:
		return
	_plate.modulate.a = _alpha
	var key := "%s|%s" % [str(view.get("done_s", 0.0)), str(view.get("total_s", 0.0))]
	if _active and key != _last_key:
		_last_key = key
		_bar.value = RouterLogic.catchup_fraction(view)
		_line.text = RouterLogic.catchup_line(view, c)


## True while input is being swallowed (the catch-up is running).
func swallowing() -> bool:
	return _active


## Every input event is taken while the catch-up runs: this node sits last under the router, so it
## hears events before the scenes' _input and the unhandled passes.
func _input(event: InputEvent) -> void:
	if _active:
		get_viewport().set_input_as_handled()
