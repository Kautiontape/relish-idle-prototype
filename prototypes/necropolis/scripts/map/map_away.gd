class_name MapAway
extends Control
## The "While you were away" panel (IDLE section 7), centred over the map: how long, then gains,
## ready now (each line a button: a fort id selects it and centres the camera, the slab and the
## queue dive into Covington) and losses ("Nothing lost." when there are none), then DISMISS.
## Opens when the report is shown (view_away; --away=demo stand-in) and on the away_report event.
## Text: AwayLogic. Look: configs/map_view.json "idle".away. Nothing moves, so reduced motion
## needs no special case.

signal fort_chosen(fort_id: String)
signal dive(node_id: String)

static var _closed_rev := -1  # the report revision closed this session (the stand-in's dismiss)

var model: MapModel
var demo := false  # --away=demo: the stand-in report from map_view.json "demo_away"

var _panel: PanelContainer
var _body: VBoxContainer
var _frame: Control
var _rev := -1


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var centre := CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(centre)
	var c := AwayLogic.cfg()
	_panel = PanelContainer.new()
	_panel.custom_minimum_size.x = float(c["width_px"])
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.add_theme_stylebox_override("panel", MapUi.plate_box(float(c["plate_alpha"]), int(c["pad_px"])))
	centre.add_child(_panel)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", int(c["sep_px"]))
	_panel.add_child(_body)
	_frame = Control.new()  # the glowing frame, over the plate's own hairline
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame.draw.connect(_draw_frame)
	_panel.add_child(_frame)
	visible = false


## Opens when the report says shown and this session hasn't closed it.
func open_if_shown() -> void:
	var rep := _report()
	if bool(rep.get("shown", false)) and int(rep.get("rev", 0)) != _closed_rev:
		_open(rep)


## The away_report event: a new report, shown even if the last one was closed.
func on_event(ev: Dictionary) -> void:
	if str(ev.get("type", "")) != "away_report":
		return
	_closed_rev = -1
	open_if_shown()


func _report() -> Dictionary:
	var d := {}
	if demo:
		d = MapLogic.cfg().get("demo_away", {})
	return AwayLogic.report(model.state, d)


func _open(rep: Dictionary) -> void:
	_rev = int(rep.get("rev", 0))
	for ch in _body.get_children():
		_body.remove_child(ch)
		ch.queue_free()
	var c := AwayLogic.cfg()
	var fort_ids: Array = model.forts_by_id.keys()
	var built := AwayLogic.build(rep, fort_ids)
	var title := Label.new()
	MapType.style_title(title)
	title.text = str(c["title"])
	_body.add_child(title)
	var away := str(built["away"])
	if str(built["capped"]) != "":
		away += " (%s)" % built["capped"]
	_body.add_child(_label(away, "text_dim"))
	for sec in built["sections"]:
		_body.add_child(_spacer(int(c["section_sep_px"])))
		_body.add_child(_label(str(sec["title"]), "text_dim"))
		for line in sec["lines"]:
			_body.add_child(_ready_row(line) if sec["key"] == "ready" and line["action"]["kind"] != "none" else _line_row(line["spans"]))
	_body.add_child(_spacer(int(c["section_sep_px"])))
	var b := Button.new()
	b.text = str(c["dismiss"])
	b.custom_minimum_size = Vector2(float(c["dismiss_w_px"]), float(c["line_min_h_px"]))
	b.size_flags_horizontal = Control.SIZE_SHRINK_END
	MapUi.style_button(b)
	b.pressed.connect(_dismiss)
	_body.add_child(b)
	visible = true


func _label(s: String, color_key: String) -> Label:
	var l := Label.new()
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	MapType.style_label(l, color_key)
	l.text = s
	return l


func _spacer(h: int) -> Control:
	var s := Control.new()
	s.custom_minimum_size.y = h
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return s


## One line as runs in their fonts: rates oblique and light, totals upright and heavy.
func _line_row(spans: Array) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", int(AwayLogic.cfg()["sep_px"]))
	for sp in spans:
		var l := Label.new()
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		l.text = str(sp["text"])
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		match str(sp["kind"]):
			"rate":
				MapType.style_rate(l)
			"mass":
				MapType.style_mass(l)
			_:
				MapType.style_label(l, "text")
		row.add_child(l)
	return row


## A ready line: a button-like row at least line_min_h_px tall, with its action.
func _ready_row(line: Dictionary) -> Button:
	var c := AwayLogic.cfg()
	var b := Button.new()
	b.custom_minimum_size.y = float(c["line_min_h_px"])
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	MapUi.style_button(b)
	var row := _line_row(line["spans"])
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.offset_left = float(c["line_pad_px"])
	row.offset_right = -float(c["line_pad_px"])
	row.alignment = BoxContainer.ALIGNMENT_BEGIN
	b.add_child(row)
	var hint := _label(str(c["ready_hint"]), "select")
	hint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hint.offset_right = -float(c["line_pad_px"])
	b.add_child(hint)
	b.pressed.connect(_act.bind(line["action"]))
	return b


func _act(a: Dictionary) -> void:
	_close()
	if a["kind"] == "fort":
		fort_chosen.emit(str(a["id"]))
	elif a["kind"] == "dive":
		dive.emit(str(a["to"]))


func _dismiss() -> void:
	if model.state.has_method("cmd_dismiss_away"):  # TODO(api-request #7)
		model.state.cmd_dismiss_away()
	_close()


func _close() -> void:
	_closed_rev = _rev
	visible = false


func _draw_frame() -> void:
	var c := AwayLogic.cfg()
	var m := float(c["pad_px"])
	var r := Rect2(Vector2(-m, -m), _frame.size + Vector2(m, m) * 2.0)
	var pts := PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y), r.position])
	for l in NodeLogic.capped_layers(Palette.c(str(c["frame_key"])), float(c["frame_w_px"]), float(c["frame_glow"]), float(c["frame_halo_max_px"])):
		_frame.draw_polyline(pts, l[1], l[0])
