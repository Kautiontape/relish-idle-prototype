extends ScrollContainer
## Build tab: the catalog (cost, can_build and why, benefit, tier gate) sorted by the current
## need, placement on a lot, the lot inspector (upgrade, cancel, demolish) and the build queue
## (stand-in until E2). Everything it shows comes from the fetched views; enable/disable is driven by
## view_catalog (`can_build`, `reason`, `lots`) and view_town, never by a command's ok. Rows, the
## inspector and the queue's rows are built once and updated in place on every bind (the shell
## binds about 4x a second), so hover, focus and held buttons survive.
## Logic is pure in BuildSort / TownStandins.BuildQueue; text and tuning live in town.json `view`.

signal command_issued
## Ask the town view to outline `lots` for `building_id` (and dim the rest); "" ends placement.
signal placement_changed(building_id: String, lots: Array)
## The inspected lot ("" = none), for the town view's dashed outline.
signal lot_selected(lot_id: String)

var _views := {}
var _vcfg: Dictionary = {}
var _bview: Dictionary = {}
var _bcfg: Dictionary = {}
var _st := {}
var _ctx := {}

var _root: VBoxContainer
var _status: Label
var _banner: PanelContainer
var _banner_label: Label
var _rows_box: VBoxContainer
var _empty: Label
var _rows := {}  # building_id -> widgets
var _shape := ""
var _style_row: StyleBoxFlat
var _style_focus: StyleBoxFlat

var _placing := ""
var _placing_lots: Array = []
var _focus := ""
var _selected_lot := ""
var _armed_s := 0.0  # > 0 while Demolish waits for its confirming click

var _insp := {}
var _q: TownStandins.BuildQueue  # TODO(api-request #3): swap for view_town().queue + the queue commands
var _q_title: Label
var _q_empty: Label
var _q_box: VBoxContainer
var _q_pool: Array = []
var _cap_box: HBoxContainer
var _cap_label: Label
var _cap_btn: Button
var _cap_building := ""


func _ready() -> void:
	_vcfg = ConfigDb.v("town", "view", {})
	_bview = ConfigDb.data.get("buildings_view", {})
	_bcfg = ConfigDb.data.get("buildings", {})
	_q = TownStandins.BuildQueue.new(int(_vcfg.get("queue_max", 8)), _vcfg.get("cap_buildings", {}))
	_style_row = TownUI.panel_box()
	_style_focus = TownUI.panel_box()
	_style_focus.border_color = Palette.c("select")
	_style_focus.set_border_width_all(2)
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_root = VBoxContainer.new()
	_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_root.add_theme_constant_override("separation", 6)
	add_child(_root)
	_status = _wrap("", 14, "text")
	_root.add_child(_status)
	_build_banner()
	_build_inspector()
	var h := TownUI.label("Catalog", 16)
	_root.add_child(h)
	_rows_box = VBoxContainer.new()
	_rows_box.add_theme_constant_override("separation", 4)
	_root.add_child(_rows_box)
	_empty = _wrap("No buildings.", 14, "text_dim")
	_root.add_child(_empty)
	_build_queue_section()
	visibility_changed.connect(func(): if not is_visible_in_tree(): cancel_placement())


func _wrap(text: String, size := 14, key := "text") -> Label:
	var l := TownUI.label(text, size, key)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.custom_minimum_size = Vector2(40, 0)
	return l


func _btn(text: String, w := 76.0) -> Button:
	var b := TownUI.button(text)
	b.custom_minimum_size = Vector2(w, TownUI.MIN_TARGET)
	return b


func _build_banner() -> void:
	_banner = PanelContainer.new()
	_banner.add_theme_stylebox_override("panel", _style_focus)
	var row := HBoxContainer.new()
	_banner.add_child(row)
	_banner_label = _wrap("", 14, "select")
	row.add_child(_banner_label)
	var c := _btn("Cancel")
	c.pressed.connect(cancel_placement)
	row.add_child(c)
	_banner.visible = false
	_root.add_child(_banner)


# ------------------------------------------------------------------ bind ----
func bind(views: Dictionary) -> void:
	_views = views
	_st = BuildSort.stocks(views)
	_ctx = BuildSort.queue_context(views, _bcfg, _vcfg)
	if TownStandins.queue_is_standin(views.get("town", {})):
		_q.evaluate(_ctx)
	var rows: Array = views.get("catalog", {}).get("buildings", [])
	var shape := ",".join(rows.map(func(r): return String(r.get("building_id", ""))))
	if shape != _shape:
		_shape = shape
		_rebuild_rows(rows)
	_empty.visible = rows.is_empty()
	var names: Dictionary = views.get("fort_names", {})
	var sorted := BuildSort.sort_rows(rows, BuildSort.needs(views, names, _vcfg), _bview, _vcfg)
	for i in sorted.size():
		var w: Dictionary = _rows[String(sorted[i]["row"]["building_id"])]
		if w["node"].get_index() != i:
			_rows_box.move_child(w["node"], i)
		_update_row(sorted[i], w)
	_check_placement()
	_update_inspector()
	_update_queue()


func on_game_event(_ev: Dictionary) -> void:
	pass


func _row_of(bid: String) -> Dictionary:
	for r in _views.get("catalog", {}).get("buildings", []):
		if String(r.get("building_id", "")) == bid:
			return r
	return {}


func _label(bid: String) -> String:
	return BuildSort.label_of(bid, _bview)


func _reason(reason: String, row: Dictionary) -> String:
	return BuildSort.reason_text(reason, row, _st, _bview, _vcfg)


func _say(text: String) -> void:
	_status.text = text


# ------------------------------------------------------------------ rows ----
func _rebuild_rows(rows: Array) -> void:
	TownUI.clear(_rows_box)
	_rows.clear()
	for r in rows:
		var bid := String(r.get("building_id", ""))
		_rows[bid] = _make_row(bid)
		_rows_box.add_child(_rows[bid]["node"])


func _make_row(bid: String) -> Dictionary:
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", _style_row)
	var v := VBoxContainer.new()
	pc.add_child(v)
	var top := HBoxContainer.new()
	v.add_child(top)
	var nm := TownUI.label("", 16)
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(nm)
	var count := TownUI.label("", 14, "text_dim")
	top.add_child(count)
	var queue := _btn("Queue")
	queue.pressed.connect(_on_queue.bind(bid))
	top.add_child(queue)
	var place := _btn("Place")
	place.pressed.connect(_toggle_place.bind(bid))
	top.add_child(place)
	var benefit := _wrap("", 14, "text_dim")
	v.add_child(benefit)
	var cost_row := HBoxContainer.new()
	v.add_child(cost_row)
	var costs: Array = []
	for k in 3:
		var l := TownUI.label("", 14)
		cost_row.add_child(l)
		costs.append(l)
	var chip := _wrap("", 14, "select")
	v.add_child(chip)
	var rbox := HBoxContainer.new()
	v.add_child(rbox)
	var reason := _wrap("", 14, "text_dim")
	rbox.add_child(reason)
	var link := _btn("", 110.0)
	link.pressed.connect(func(): _focus_building(String(link.get_meta("target", ""))))
	rbox.add_child(link)
	return {"node": pc, "name": nm, "count": count, "queue": queue, "place": place, "benefit": benefit,
		"costs": costs, "chip": chip, "reason": reason, "link": link}


func _update_row(it: Dictionary, w: Dictionary) -> void:
	var row: Dictionary = it["row"]
	var bid := String(row.get("building_id", ""))
	var can := bool(row.get("can_build", false))
	w["name"].text = _label(bid)
	w["name"].add_theme_color_override("font_color", Palette.c("text_dim" if it["cls"] == 2 else "text"))
	w["count"].text = "built %d" % int(row.get("count", 0))
	w["benefit"].text = String(_bview.get(bid, {}).get("benefit", ""))
	var parts := BuildSort.cost_parts(row.get("cost", {}), _st)
	for k in 3:
		w["costs"][k].text = String(parts[k]["text"]) + ("  ·  " if k < 2 else "")
		w["costs"][k].add_theme_color_override("font_color", Palette.c("danger" if parts[k]["short"] else "text"))
	w["chip"].visible = it["chip"] != ""
	w["chip"].text = "Needed now: " + String(it["chip"])
	w["place"].visible = can
	w["place"].text = "Stop" if _placing == bid else "Place"
	w["queue"].visible = BuildSort.can_queue(row, _vcfg)
	w["queue"].disabled = _q.entries.size() >= _q.max_len or _free_lot(row) == ""
	var why := String(row.get("reason", ""))
	w["reason"].get_parent().visible = not can
	w["reason"].text = _reason(why, row) if not can else ""
	w["reason"].add_theme_color_override("font_color", Palette.c("text" if it["cls"] == 2 else "text_dim"))
	var target := BuildSort.fix_target(why, row, _st, _vcfg) if not can else ""
	w["link"].visible = target != ""
	w["link"].set_meta("target", target)
	w["link"].text = "Show " + _label(target) if target != "" else ""
	w["node"].add_theme_stylebox_override("panel", _style_focus if _focus == bid else _style_row)


# ------------------------------------------------------------- placement ----
func _toggle_place(bid: String) -> void:
	if _placing == bid:
		cancel_placement()
		return
	_placing = bid
	_placing_lots = []
	_check_placement()
	_say("Esc, right-click or Stop cancels.")
	_update_banner()


## Ends placement (Escape, right-click, Stop, leaving the tab).
func cancel_placement() -> void:
	if _placing == "":
		return
	_placing = ""
	_placing_lots = []
	placement_changed.emit("", [])
	_update_banner()
	for bid in _rows:
		_rows[bid]["place"].text = "Place"


func _update_banner() -> void:
	_banner.visible = _placing != ""
	_banner_label.text = "Placing %s: click a lit lot in town." % _label(_placing) if _placing != "" else ""


## Keeps the town view's lit lots in step with the catalog; a building that can't be placed any
## more (funds spent, lots gone) ends placement, with the reason.
func _check_placement() -> void:
	if _placing == "":
		return
	var row := _row_of(_placing)
	if row.is_empty() or not bool(row.get("can_build", false)):
		var why := _reason(String(row.get("reason", "")), row) if not row.is_empty() else ""
		var nm := _label(_placing)
		cancel_placement()
		_say("Can't place %s now: %s." % [nm, why])
		return
	if row.get("lots", []) != _placing_lots:
		_placing_lots = (row["lots"] as Array).duplicate()
		placement_changed.emit(_placing, _placing_lots)
	_update_banner()


func _unhandled_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if _placing != "" and k != null and k.pressed and k.keycode == KEY_ESCAPE and is_visible_in_tree():
		cancel_placement()
		get_viewport().set_input_as_handled()


## The town view reports a click: a lit lot places the building, a built lot is inspected.
func on_lot_clicked(lot_id: String) -> void:
	if _placing != "":
		var row := _row_of(_placing)
		if lot_id == "":
			_say("Click one of the lit lots, or press Esc.")
		elif lot_id in row.get("lots", []):
			var bid := _placing
			var r: Dictionary = Game.state.cmd_build(bid, lot_id)
			_report(r, "Building %s on %s." % [_label(bid), lot_id], row)
			cancel_placement()
		else:
			_say("%s: %s." % [lot_id, _reason(BuildSort.lot_refusal(_town_lot(lot_id), row), row)])
		return
	_select_lot(lot_id if _entry_at(lot_id) != {} else "")


func _town_lot(lot_id: String) -> Dictionary:
	for l in _views.get("town", {}).get("lots", []):
		if String(l.get("id", "")) == lot_id:
			return l
	return {}


func _entry_at(lot_id: String) -> Dictionary:
	for b in _views.get("town", {}).get("buildings", []):
		if String(b.get("lot_id", "")) == lot_id:
			return b
	return {}


func _report(r: Dictionary, ok_text: String, row := {}) -> void:
	if bool(r.get("ok", false)):
		_say(ok_text)
	else:
		_say("Refused: %s." % _reason(String(r.get("reason", "")), row))
	command_issued.emit()


func _focus_building(bid: String) -> void:
	if bid == "" or not _rows.has(bid):
		return
	_focus = bid
	if bool(_row_of(bid).get("can_build", false)) and _placing != bid:
		_toggle_place(bid)
	ensure_control_visible.call_deferred(_rows[bid]["node"])


# ------------------------------------------------------------- inspector ----
func _build_inspector() -> void:
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", _style_focus)
	var v := VBoxContainer.new()
	pc.add_child(v)
	var w := {"node": pc}
	w["title"] = TownUI.label("", 18)
	w["flavour"] = _wrap("", 14, "text_dim")
	for k in ["level", "state", "staffing", "foreman"]:
		w[k] = _wrap("", 14)
	for k in ["title", "flavour", "level", "state", "staffing", "foreman"]:
		v.add_child(w[k])
	var up := HBoxContainer.new()
	var ul := TownUI.label("upkeep", 14, "text_dim")
	up.add_child(ul)
	w["up_gold"] = TownUI.rate_label("", 14)
	w["up_bone"] = TownUI.rate_label("", 14)
	up.add_child(w["up_gold"])
	up.add_child(w["up_bone"])
	up.add_theme_constant_override("separation", 12)
	v.add_child(up)
	var r1 := HBoxContainer.new()
	w["upgrade"] = _btn("Upgrade", 100.0)
	w["upgrade"].size_flags_horizontal = Control.SIZE_EXPAND_FILL
	w["upgrade"].pressed.connect(_on_upgrade)
	w["queue_up"] = _btn("Queue", 76.0)
	w["queue_up"].pressed.connect(_on_queue_upgrade)
	r1.add_child(w["upgrade"])
	r1.add_child(w["queue_up"])
	v.add_child(r1)
	w["why"] = _wrap("", 14, "text_dim")
	v.add_child(w["why"])
	var r2 := HBoxContainer.new()
	w["cancel"] = _btn("Cancel build", 100.0)
	w["cancel"].size_flags_horizontal = Control.SIZE_EXPAND_FILL
	w["cancel"].pressed.connect(_on_cancel_build)
	w["demolish"] = _btn("Demolish", 100.0)
	w["demolish"].size_flags_horizontal = Control.SIZE_EXPAND_FILL
	w["demolish"].pressed.connect(_on_demolish)
	w["close"] = _btn("Close", 76.0)
	w["close"].pressed.connect(func(): _select_lot(""))
	r2.add_child(w["cancel"])
	r2.add_child(w["demolish"])
	r2.add_child(w["close"])
	v.add_child(r2)
	pc.visible = false
	_root.add_child(pc)
	_insp = w


func _select_lot(lot_id: String) -> void:
	if lot_id != _selected_lot:
		_armed_s = 0.0
		set_process(false)
	_selected_lot = lot_id
	lot_selected.emit(lot_id)
	_update_inspector()


func _update_inspector() -> void:
	var w := _insp
	var entry := _entry_at(_selected_lot) if _selected_lot != "" else {}
	if entry.is_empty():
		if _selected_lot != "":
			_selected_lot = ""
			lot_selected.emit("")
		w["node"].visible = false
		return
	var i := BuildSort.inspect(entry, _st, _bcfg, _bview, _vcfg)
	w["node"].visible = true
	w["title"].text = "%s  (%s)" % [i["label"], _selected_lot]
	w["flavour"].text = i["flavour"]
	w["level"].text = "Level %d of %d" % [i["level"], i["max_level"]]
	w["state"].text = "State: " + String(i["state_text"])
	w["staffing"].text = "Staffing: " + String(i["staffing"])
	var fm := String(i["foreman"])
	w["foreman"].text = "Foreman: none" if fm == "no foreman" else "Foreman: " + fm.trim_prefix("foreman ")
	w["up_gold"].text = "%s gold" % TownUI.fmt_rate(-float(i["upkeep"]["gold"]))
	w["up_bone"].text = "%s bone" % TownUI.fmt_rate(-float(i["upkeep"]["bone"]))
	var u: Dictionary = i["upgrade"]
	w["upgrade"].visible = u["visible"]
	w["upgrade"].disabled = not u["enabled"]
	w["upgrade"].text = "Upgrade to Lv %d: %s" % [u["level"], _cost_text(u["cost"])] if not (u["cost"] as Dictionary).is_empty() else "Upgrade"
	w["queue_up"].visible = u["visible"]
	w["queue_up"].disabled = not u["can_queue"] or _q.entries.size() >= _q.max_len or _queued_lot(_selected_lot)
	var why := ""
	if u["visible"] and not u["enabled"]:
		why = _reason(String(u["reason"]), {"cost": u["cost"]})
	w["why"].visible = why != ""
	w["why"].text = why
	var c: Dictionary = i["cancel"]
	w["cancel"].visible = c["visible"]
	w["cancel"].text = "Cancel build (refund %s)" % _cost_text(c["refund"], false) if c["visible"] else "Cancel build"
	w["demolish"].visible = i["demolish_visible"] and not c["visible"]
	w["demolish"].text = "Click again to demolish (%d s)" % int(ceil(_armed_s)) if _armed_s > 0.0 else "Demolish"


func _cost_text(cost: Dictionary, marks := true) -> String:
	var parts := BuildSort.cost_parts(cost, _st)
	var out: Array = []
	for p in parts:
		if p["key"] != "relics" or int(cost.get("relics", 0)) > 0:
			out.append(String(p["text"]) if marks else String(p["text"]).trim_prefix("! "))
	return " · ".join(out)


func _on_upgrade() -> void:
	var r: Dictionary = Game.state.cmd_upgrade(_selected_lot)
	_report(r, "Upgrading %s." % _selected_lot, {})


func _on_cancel_build() -> void:
	var r: Dictionary = Game.state.cmd_cancel_build(_selected_lot)
	_report(r, "Cancelled the build on %s." % _selected_lot, {})


func _on_demolish() -> void:
	if _armed_s <= 0.0:
		_armed_s = float(_vcfg.get("demolish_confirm_s", 3.0))
		set_process(true)
		_update_inspector()
		return
	_armed_s = 0.0
	set_process(false)
	var lot := _selected_lot
	var r: Dictionary = Game.state.cmd_demolish(lot)
	_report(r, "Demolished %s." % lot, {})
	_update_inspector()


func _process(delta: float) -> void:
	if _armed_s > 0.0:
		_armed_s = maxf(_armed_s - delta, 0.0)
		if _armed_s == 0.0:
			set_process(false)
		_update_inspector()


# ----------------------------------------------------------------- queue ----
func _build_queue_section() -> void:
	_q_title = TownUI.label("Build queue (stand-in until E2: not saved)", 16)
	_q_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_q_title.custom_minimum_size = Vector2(40, 0)
	_root.add_child(_q_title)
	_cap_box = HBoxContainer.new()
	_cap_label = _wrap("", 14, "danger")
	_cap_box.add_child(_cap_label)
	_cap_btn = _btn("", 130.0)
	_cap_btn.pressed.connect(func(): _focus_building(_cap_building))
	_cap_box.add_child(_cap_btn)
	_cap_box.visible = false
	_root.add_child(_cap_box)
	_q_empty = _wrap("Nothing queued. Queue a building to spend income while you are away.", 14, "text_dim")
	_root.add_child(_q_empty)
	_q_box = VBoxContainer.new()
	_q_box.add_theme_constant_override("separation", 4)
	_root.add_child(_q_box)


func _free_lot(row: Dictionary) -> String:
	for l in row.get("lots", []):
		if not _queued_lot(String(l)):
			return String(l)
	return ""


func _queued_lot(lot_id: String) -> bool:
	for e in _q.entries:
		if e["lot_id"] == lot_id:
			return true
	return false


func _on_queue(bid: String) -> void:
	var row := _row_of(bid)
	_add_queue({"building_id": bid, "lot_id": _free_lot(row), "upgrade": false, "level": 1, "cost": row.get("cost", {})}, row)


func _on_queue_upgrade() -> void:
	var entry := _entry_at(_selected_lot)
	var i := BuildSort.inspect(entry, _st, _bcfg, _bview, _vcfg)
	_add_queue({"building_id": i["building_id"], "lot_id": _selected_lot, "upgrade": true, "level": i["upgrade"]["level"],
		"cost": i["upgrade"]["cost"]}, {"cost": i["upgrade"]["cost"]})


func _add_queue(e: Dictionary, row: Dictionary) -> void:
	var r := _q.add(e, _ctx)
	if r["ok"]:
		_cap_box.visible = false
		_say("Queued %s on %s." % [_label(e["building_id"]), e["lot_id"]])
	elif r["reason"] == "cost_exceeds_cap":
		_show_cap_refusal(e, r)
	else:
		_say("Not queued: %s." % _reason(String(r["reason"]), row))
	_update_queue()


## "<cost> is over the <gold> cap: build <label> first", with a button that selects that building.
func _show_cap_refusal(e: Dictionary, r: Dictionary) -> void:
	var store := String(r["store"])
	var tt: Dictionary = _vcfg.get("queue_text", {})
	_cap_building = String(r["cap_building"])
	var vars := {"cost": "%d %s" % [int(ceil(float(e["cost"].get(store, 0.0)))), store], "store": store,
		"cap": int(_ctx.get(store + "_cap", -1.0)), "label": _label(_cap_building)}
	_cap_label.text = BuildSort.fmt(String(tt.get("cap_refusal" if _cap_building != "" else "cap_refusal_none", "")), vars)
	_cap_btn.visible = _cap_building != ""
	_cap_btn.text = "Show " + _label(_cap_building)
	_cap_box.visible = true
	_say("Not queued: %s." % _reason("cost_exceeds_cap", {}))


func _queue_entries() -> Array:
	return _q.entries


func _update_queue() -> void:
	var entries := _queue_entries()
	_q_empty.visible = entries.is_empty()
	while _q_pool.size() < entries.size():
		_q_pool.append(_make_q_row(_q_pool.size()))
	var tt: Dictionary = _vcfg.get("queue_text", {})
	for i in _q_pool.size():
		var w: Dictionary = _q_pool[i]
		w["node"].visible = i < entries.size()
		if i >= entries.size():
			continue
		var e: Dictionary = entries[i]
		var what := ("Upgrade %s to Lv %d" % [_label(e["building_id"]), e["level"]]) if e["upgrade"] else _label(e["building_id"])
		var status := String(e["status"])
		var why := BuildSort.reason_text(String(e["reason"]), {"cost": e["cost"]}, _st, _bview, _vcfg) if e["reason"] != "" else ""
		var glyph: String = {"next": ">", "waiting_funds": "||", "skipped_gate": "x", "queued": "-"}.get(status, "-")
		var title := "%d. %s on %s" % [i + 1, what, e["lot_id"]]
		w["title"].text = "[s]%s[/s]" % title if status == "skipped_gate" else title
		w["detail"].text = "%s %s" % [glyph, BuildSort.fmt(String(tt.get(status, "")), {"why": why})]
		w["detail"].add_theme_color_override("font_color", Palette.c(
			{"next": "text", "waiting_funds": "select", "skipped_gate": "danger", "queued": "text_dim"}.get(status, "text_dim")))
		w["up"].disabled = i == 0
		w["down"].disabled = i == entries.size() - 1


func _make_q_row(index: int) -> Dictionary:
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", _style_row)
	var h := HBoxContainer.new()
	pc.add_child(h)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)
	var title := RichTextLabel.new()
	title.bbcode_enabled = true
	title.fit_content = true
	title.scroll_active = false
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.custom_minimum_size = Vector2(40, 0)
	title.add_theme_font_size_override("normal_font_size", 14)
	title.add_theme_color_override("default_color", Palette.c("text"))
	v.add_child(title)
	var detail := _wrap("", 14, "text_dim")
	v.add_child(detail)
	var up := _btn("Up", 56.0)
	up.pressed.connect(func(): _q.move(index, -1); _update_queue())
	var down := _btn("Down", 56.0)
	down.pressed.connect(func(): _q.move(index, 1); _update_queue())
	var rm := _btn("Unqueue", 80.0)
	rm.pressed.connect(func(): _q.unqueue(index); _update_queue())
	for b in [up, down, rm]:
		h.add_child(b)
	_q_box.add_child(pc)
	return {"node": pc, "title": title, "detail": detail, "up": up, "down": down}
