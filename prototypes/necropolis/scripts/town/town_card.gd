extends PanelContainer
## The lot card: a panel beside a lot inside the town view. For an empty lot it lists the
## buildings that fit it, mission-sorted (BuildSort), each a row with cost counts (the short part
## marked), the benefit as signed oblique rates (labelled "now" once the catalog has `projected`),
## the reason in words with a time estimate, and Build / Queue. For a built lot the panel's
## inspector widgets are parked in `insp_host`, under the building's one-line status (set_status,
## from the town view's model: words upright, rates oblique). The Build tab owns the data and the
## commands; the town view owns where the card sits and the status. Rows are built once per
## building and updated in place.
## Logic is BuildSort; text and tuning are configs/town.json `view`.

signal build_pressed(building_id: String, lot_id: String)
signal queue_pressed(building_id: String, lot_id: String)
signal close_pressed
## The catalog row under the pointer ("" for none): the view outlines the lots it fits.
signal hover_building(building_id: String)

var vcfg: Dictionary = {}
var bview: Dictionary = {}
var bcfg: Dictionary = {}
var insp_host: VBoxContainer

var _title: Label
var _scroll: ScrollContainer
var _body: VBoxContainer
var _rows_box: VBoxContainer
var _rows := {}
var _hover := ""
var _status: RichTextLabel
var _status_parts: Array = []


func setup(vcfg_: Dictionary, bview_: Dictionary, bcfg_: Dictionary) -> void:
	vcfg = vcfg_
	bview = bview_
	bcfg = bcfg_
	var sb := TownUI.panel_box()
	sb.border_color = Palette.c("select")
	add_theme_stylebox_override("panel", sb)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var card: Dictionary = vcfg.get("card", {})
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", int(card.get("row_gap_px", 6.0)))
	add_child(col)
	var head := HBoxContainer.new()
	col.add_child(head)
	_title = TownUI.label("", 16)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
	var close := TownUI.button("Close")
	close.custom_minimum_size = Vector2(76, TownUI.MIN_TARGET)
	close.pressed.connect(func(): close_pressed.emit())
	head.add_child(close)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.custom_minimum_size = Vector2(float(card.get("w_px", 400.0)), 0)
	col.add_child(_scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", int(card.get("row_gap_px", 6.0)))
	_scroll.add_child(_body)
	_rows_box = VBoxContainer.new()
	_rows_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows_box.add_theme_constant_override("separation", int(card.get("row_gap_px", 6.0)))
	_body.add_child(_rows_box)
	insp_host = VBoxContainer.new()
	insp_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_child(insp_host)
	_status = RichTextLabel.new()  # the inspector form's first line
	_status.fit_content = true
	_status.scroll_active = false
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status.add_theme_font_size_override("normal_font_size", 16)
	_status.add_theme_color_override("default_color", Palette.c("text"))
	insp_host.add_child(_status)
	_body.minimum_size_changed.connect(_fit.call_deferred)
	visible = false
	set_process(false)


func open() -> void:
	visible = true
	set_process(true)
	_fit.call_deferred()


func close() -> void:
	visible = false
	set_process(false)
	_set_hover("")


## Sizes the scroll area to its content, up to view.card.max_h_px for the whole card.
func _fit() -> void:
	if _scroll == null:
		return
	var card: Dictionary = vcfg.get("card", {})
	var room := float(card.get("max_h_px", 600.0)) - TownUI.MIN_TARGET - float(card.get("row_gap_px", 6.0)) * 2.0 - 16.0
	_scroll.custom_minimum_size = Vector2(float(card.get("w_px", 400.0)), minf(_body.get_combined_minimum_size().y, maxf(room, 120.0)))
	reset_size()


func _process(_delta: float) -> void:
	var mp := get_global_mouse_position()
	var bid := ""
	if get_global_rect().has_point(mp) and _rows_box.visible and _scroll.get_global_rect().has_point(mp):
		for id in _rows:
			var n: Control = _rows[id]["node"]
			if n.visible and n.get_global_rect().has_point(mp):
				bid = id
				break
	_set_hover(bid)


func _set_hover(bid: String) -> void:
	if bid != _hover:
		_hover = bid
		hover_building.emit(bid)


## The catalog form: `items` are BuildSort.sort_rows() items already limited to those that fit the
## lot; `st` is BuildSort.stocks(); `suggested` the suggested building id; `queue_free` tells
## whether a queue slot is free for this lot. `note` (BuildSort.reserved_note) is the line under the title
## when the suggestion keeps the lot for the next tier's gate building.
func show_catalog(lot_id: String, lot_size: int, items: Array, st: Dictionary, suggested: String, queue_free: bool, note := "") -> void:
	_title.text = "Empty lot (size %d)" % lot_size + ("\n" + note if note != "" else "")
	_rows_box.visible = true
	insp_host.visible = false
	var shown := {}
	for i in items.size():
		var it: Dictionary = items[i]
		var bid := String(it["row"].get("building_id", ""))
		if not _rows.has(bid):
			_rows[bid] = _make_row(bid)
			_rows_box.add_child(_rows[bid]["node"])
		var w: Dictionary = _rows[bid]
		shown[bid] = true
		w["node"].visible = true
		if w["node"].get_index() != i:
			_rows_box.move_child(w["node"], i)
		_update_row(w, it, lot_id, st, bid == suggested, queue_free)
	for bid in _rows:
		if not shown.has(bid):
			_rows[bid]["node"].visible = false


## The building's status line, first in the inspector form: parts [[text, oblique]]
## (TownModel.status_of). Rebuilt only when it changed.
func set_status(parts: Array) -> void:
	if parts == _status_parts:
		return
	_status_parts = parts.duplicate(true)
	_status.clear()
	for p in parts:
		if p[1]:
			_status.push_font(TownUI.oblique_font(), 16)
			_status.add_text(String(p[0]))
			_status.pop()
		else:
			_status.add_text(String(p[0]))
	_status.visible = not parts.is_empty()


## The inspector form: the panel's inspector widgets are in `insp_host`.
func show_inspector(title: String) -> void:
	_title.text = title
	_rows_box.visible = false
	insp_host.visible = true


func _make_row(bid: String) -> Dictionary:
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", TownUI.panel_box())
	pc.mouse_filter = Control.MOUSE_FILTER_PASS
	pc.custom_minimum_size = Vector2(0, TownUI.MIN_TARGET)
	var v := VBoxContainer.new()
	pc.add_child(v)
	var top := HBoxContainer.new()
	v.add_child(top)
	var nm := TownUI.label("", 16)
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(nm)
	var build := TownUI.button("Build")
	build.custom_minimum_size = Vector2(76, TownUI.MIN_TARGET)
	build.pressed.connect(func(): build_pressed.emit(bid, String(build.get_meta("lot", ""))))
	top.add_child(build)
	var queue := TownUI.button("Queue")
	queue.custom_minimum_size = Vector2(76, TownUI.MIN_TARGET)
	queue.pressed.connect(func(): queue_pressed.emit(bid, String(queue.get_meta("lot", ""))))
	top.add_child(queue)
	var tags := HBoxContainer.new()
	tags.add_theme_constant_override("separation", 10)
	v.add_child(tags)
	var sug := TownUI.label("suggested", 14, "select")
	tags.add_child(sug)
	var chip := _wrap("", 14, "select")
	tags.add_child(chip)
	var cost_row := HBoxContainer.new()
	v.add_child(cost_row)
	var costs: Array = []
	for k in 3:
		var l := TownUI.label("", 14)
		cost_row.add_child(l)
		costs.append(l)
	var ben := HBoxContainer.new()
	ben.add_theme_constant_override("separation", 10)
	v.add_child(ben)
	var rates: Array = []
	for k in 3:
		var l := TownUI.rate_label("", 14)
		ben.add_child(l)
		rates.append(l)
	var plain := _wrap("", 14, "text_dim")
	ben.add_child(plain)
	var reason := _wrap("", 14, "text_dim")
	v.add_child(reason)
	return {"node": pc, "name": nm, "build": build, "queue": queue, "sug": sug, "chip": chip, "costs": costs,
		"rates": rates, "plain": plain, "reason": reason}


func _wrap(text: String, size := 14, key := "text") -> Label:
	var l := TownUI.label(text, size, key)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.custom_minimum_size = Vector2(40, 0)
	return l


func _update_row(w: Dictionary, it: Dictionary, lot_id: String, st: Dictionary, suggested: bool, queue_free: bool) -> void:
	var row: Dictionary = it["row"]
	var bid := String(row.get("building_id", ""))
	var can := bool(row.get("can_build", false))
	var gated: bool = it["cls"] == BuildSort.CLS_GATED
	var here: bool = lot_id in row.get("lots", [])
	w["name"].text = BuildSort.label_of(bid, bview)
	w["name"].add_theme_color_override("font_color", Palette.c("text_dim" if gated else "text"))
	w["build"].visible = can and here
	w["build"].set_meta("lot", lot_id)
	w["queue"].visible = BuildSort.can_queue(row, vcfg) and here
	w["queue"].disabled = not queue_free
	w["queue"].set_meta("lot", lot_id)
	w["sug"].visible = suggested
	w["chip"].visible = it["chip"] != ""
	w["chip"].text = "Needed now: " + String(it["chip"])
	var cost: Dictionary = row.get("cost", {})
	var parts := BuildSort.cost_parts(cost, st)
	var shown: Array = [0, 1, 2] if int(cost.get("relics", 0)) > 0 else [0, 1]
	for k in 3:
		var at := shown.find(k)
		w["costs"][k].visible = at >= 0
		# separators sit between the shown parts only: never a trailing "·"
		w["costs"][k].text = String(parts[k]["text"]) + ("  ·  " if at >= 0 and at < shown.size() - 1 else "")
		w["costs"][k].add_theme_color_override("font_color", Palette.c("danger" if parts[k]["short"] else "text"))
	var ben := BuildSort.benefit(bid, row, bcfg, bview, vcfg)
	for k in 3:
		w["rates"][k].visible = k < ben["rates"].size()
		w["rates"][k].text = String(ben["rates"][k]) if k < ben["rates"].size() else ""
	w["plain"].text = "  ".join(ben["plain"])
	w["plain"].visible = not ben["plain"].is_empty()
	var why := ""
	if not can:
		why = BuildSort.row_reason(row, st, bview, vcfg)  # an unmet relic cost is said too
	elif not here:
		why = BuildSort.reason_text("no_lot", row, st, bview, vcfg)
	w["reason"].visible = why != ""
	w["reason"].text = why
	w["reason"].add_theme_color_override("font_color", Palette.c("text" if gated else "text_dim"))
