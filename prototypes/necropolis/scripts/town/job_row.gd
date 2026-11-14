extends PanelContainer
## One ladder row of the Jobs tab: a drag handle, the job and its building, a tick row of
## staffed/slots, and up/down buttons (the accessible way to reorder). The whole row is a drag
## source and a drop target (Control drag-and-drop); a `select` line shows where it will land.
## It owns no state: the panel tells it the order through `dropped`.

signal dropped(job: String, lower_half_of: String, lower: bool)
signal nudged(job: String, dir: int)

const DRAG_KEY := "town_job"

var job := ""
var _name: Label
var _site: Label
var _note: Label
var _count: Label
var _ticks: Control
var _up: Button
var _down: Button
var _staffed := 0.0
var _slots := 0
var _drop_edge := 0  # -1 line above the row, +1 line below, 0 none
var _flash := false
var _tick_px := [3.0, 9.0]


func setup(job_id: String, tick_px: Array) -> void:
	job = job_id
	_tick_px = tick_px
	custom_minimum_size = Vector2(0, TownUI.MIN_TARGET)
	add_theme_stylebox_override("panel", _box(false))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	add_child(col)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	col.add_child(row)
	var handle := TownUI.label("≡", 22, "text_dim")
	handle.custom_minimum_size = Vector2(TownUI.MIN_TARGET, TownUI.MIN_TARGET)
	handle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	handle.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	handle.mouse_default_cursor_shape = Control.CURSOR_DRAG
	handle.tooltip_text = "Drag to reorder"
	handle.mouse_filter = Control.MOUSE_FILTER_PASS  # a Label ignores the mouse by default: PASS shows the cursor and tooltip, and the drag still reaches the row
	row.add_child(handle)
	var names := VBoxContainer.new()
	names.add_theme_constant_override("separation", 0)
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(names)
	_name = TownUI.label("", 16)
	names.add_child(_name)
	_site = TownUI.label("", 12, "text_dim")
	names.add_child(_site)
	_ticks = Control.new()
	_ticks.custom_minimum_size = Vector2(96, TownUI.MIN_TARGET)
	_ticks.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ticks.draw.connect(_draw_ticks)
	row.add_child(_ticks)
	_count = TownUI.label("", 14)
	_count.custom_minimum_size = Vector2(44, 0)
	_count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_count)
	_up = TownUI.button("▲")
	_up.custom_minimum_size = Vector2(TownUI.MIN_TARGET, TownUI.MIN_TARGET)
	_up.tooltip_text = "Move up the ladder"
	_up.pressed.connect(func() -> void: nudged.emit(job, -1))
	row.add_child(_up)
	_down = TownUI.button("▼")
	_down.custom_minimum_size = Vector2(TownUI.MIN_TARGET, TownUI.MIN_TARGET)
	_down.tooltip_text = "Move down the ladder"
	_down.pressed.connect(func() -> void: nudged.emit(job, 1))
	row.add_child(_down)
	_note = TownUI.label("", 12, "select")
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note.visible = false
	col.add_child(_note)


## Update in place: rank (1-based), label, building text, staffing, the stance note (or "").
func update(rank: int, last: bool, label: String, site: String, staffed: float, slots: int, note: String) -> void:
	_name.text = "%d. %s" % [rank, label]
	_site.text = site
	_staffed = staffed
	_slots = slots
	_count.text = "%d/%d" % [roundi(staffed), slots]
	_up.disabled = rank <= 1
	_down.disabled = last
	_note.text = note
	_note.visible = note != ""
	_ticks.queue_redraw()


## Highlight the row (select border) for as long as `on`; the panel drives the one-beat timing.
func set_flash(on: bool) -> void:
	if on == _flash:
		return
	_flash = on
	add_theme_stylebox_override("panel", _box(on))


func _box(on: bool) -> StyleBoxFlat:
	var sb := TownUI.panel_box()
	sb.set_content_margin_all(2)
	if on:
		sb.border_color = Palette.c("select")
		sb.set_border_width_all(2)
	return sb


func _draw_ticks() -> void:
	var n := maxi(_slots, 0)
	if n == 0:
		return
	var filled := clampi(roundi(_staffed), 0, n)
	var w := _ticks.size.x
	var step := minf(w / float(n), 14.0)
	var x0 := (w - step * float(n)) * 0.5 + step * 0.5
	var mid := _ticks.size.y * 0.5
	for i in n:
		var x := x0 + step * float(i)
		if i < filled:
			_ticks.draw_line(Vector2(x, mid - _tick_px[1] * 0.5), Vector2(x, mid + _tick_px[1] * 0.5), Palette.c("undead"), 2.0)
		else:  # an open slot: a short hollow tick
			_ticks.draw_line(Vector2(x, mid - _tick_px[0] * 0.5), Vector2(x, mid + _tick_px[0] * 0.5), Palette.c("text_dim"), 1.0)


func _draw() -> void:
	if _drop_edge == 0:
		return
	var y := 0.0 if _drop_edge < 0 else size.y - 1.0
	draw_line(Vector2(0, y), Vector2(size.x, y), Palette.c("select"), 3.0)


# ---- drag and drop ----
func _get_drag_data(_at: Vector2) -> Variant:
	var preview := TownUI.label("≡ " + _name.text, 16)
	preview.add_theme_stylebox_override("normal", TownUI.panel_box())
	set_drag_preview(preview)
	return {DRAG_KEY: job}


func _can_drop_data(at: Vector2, data: Variant) -> bool:
	var ok: bool = typeof(data) == TYPE_DICTIONARY and (data as Dictionary).has(DRAG_KEY) and String(data[DRAG_KEY]) != job
	var edge := (1 if at.y > size.y * 0.5 else -1) if ok else 0
	if edge != _drop_edge:
		_drop_edge = edge
		queue_redraw()
	return ok


func _drop_data(at: Vector2, data: Variant) -> void:
	_drop_edge = 0
	queue_redraw()
	dropped.emit(String(data[DRAG_KEY]), job, at.y > size.y * 0.5)


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END or what == NOTIFICATION_MOUSE_EXIT:
		if _drop_edge != 0:
			_drop_edge = 0
			queue_redraw()
