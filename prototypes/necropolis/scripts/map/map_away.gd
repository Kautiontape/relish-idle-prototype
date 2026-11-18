class_name MapAway
extends Control
## The "While you were away" panel (IDLE section 7), centred over the map: how long, then gains,
## ready now (each line a button: a fort id selects it and centres the camera, the slab and the
## queue dive into Covington) and losses, led by their count ("2 forts lost"; "Nothing lost." when
## there are none), a lost fort a button like a ready line, then DISMISS.
## Opens when the report is shown (view_away; --away=demo stand-in) and on the away_report event.
## Text: AwayLogic. Look: configs/map_view.json "idle".away. Nothing moves, so reduced motion
## needs no special case.

signal acted(action: Dictionary)  # a line was clicked: AwayLogic.action's {kind, ...}

static var _closed_rev := -1  # the report revision closed this session (the stand-in's dismiss)

var model: MapModel
var demo := false  # --away=demo: the stand-in report from map_view.json "demo_away"

var _panel: PanelContainer
var _body: VBoxContainer
var _frame: Control
var _rev := -1
var _tithe_box: VBoxContainer
var _tithe_label: Label
var _tithe_text := ""
var _tithe_action := {"kind": "none"}


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


## Opens when the report says shown and this session hasn't closed it. Returns whether it opened (the
## builds' callout skips a mount whose report lists the builds that finished).
func open_if_shown() -> bool:
	var rep := _report()
	if AwayLogic.should_open(model.state, demo, rep, _closed_rev):
		_open(rep)
		return true
	return false


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
			_body.add_child(_ready_row(line) if sec["key"] != "gains" and line["action"]["kind"] != "none" else _line_row(line["spans"]))
	_build_tithe_row(int(c["section_sep_px"]))
	_body.add_child(_spacer(int(c["section_sep_px"])))
	var b := Button.new()
	b.text = str(c["dismiss"])
	b.custom_minimum_size = Vector2(float(c["dismiss_w_px"]), float(c["line_min_h_px"]))
	b.size_flags_horizontal = Control.SIZE_SHRINK_END
	MapUi.style_button(b)
	b.pressed.connect(_dismiss)
	_body.add_child(b)
	visible = true


## The tithe telegraph line, its own row after the sections: a button like a ready line whose text
## and action _process re-reads from the model's view_vei each frame (hidden while it has nothing).
func _build_tithe_row(gap: int) -> void:
	var c := AwayLogic.cfg()
	_tithe_box = VBoxContainer.new()
	_tithe_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tithe_box.add_theme_constant_override("separation", int(c["sep_px"]))
	_tithe_box.add_child(_spacer(gap))
	var b := Button.new()
	b.custom_minimum_size.y = float(c["line_min_h_px"])
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	MapUi.style_button(b)
	_tithe_label = _label("", "text")
	_tithe_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_tithe_label.offset_left = float(c["line_pad_px"])
	_tithe_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	b.add_child(_tithe_label)
	var hint := _label(str(c["ready_hint"]), "select")
	hint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hint.offset_right = -float(c["line_pad_px"])
	b.add_child(hint)
	b.pressed.connect(func(): _act(_tithe_action))
	_tithe_box.add_child(b)
	_body.add_child(_tithe_box)
	_tithe_box.visible = false
	_tithe_text = " "  # not a line the telegraph can produce, so the first refresh sets the row
	_refresh_tithe()


func _process(_delta: float) -> void:
	if visible and _tithe_box != null:
		_refresh_tithe()


## Reads the telegraph from the model (not the report), so the ETA ticks while the panel is open.
## Text is set only when it changes.
func _refresh_tithe() -> void:
	var names := {}
	for id in model.forts_by_id:
		names[id] = str(model.forts_by_id[id].get("name", id))
	var l := AwayLogic.tithe_line(model.vei.get("tithe", {}), names, model.forts_by_id.keys())
	_tithe_action = l["action"]
	var text := str(l["text"])
	if text == _tithe_text:
		return
	_tithe_text = text
	_tithe_label.text = text
	_tithe_box.visible = text != ""


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


## A ready line or a lost fort: a button-like row at least line_min_h_px tall, with its action.
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
	AwayLogic.dismiss(model.state)  # a report is kept until dismissed: acting on a line dismisses it
	_close()
	acted.emit(a)


func _dismiss() -> void:
	AwayLogic.dismiss(model.state)
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
