extends VBoxContainer
## Stances tab (MECHANICS §4.5): the stance slots with their breakdown, and one row per stance with
## a toggle (`cmd_set_stance`), state chips in text (on / suspended / active), the hold timer and
## the projected change to net rates BEFORE you toggle it (view_stances `projected`, signed and
## oblique). Under each rule, its trade in the town's numbers: the live condition and the hands it
## would move ("Now: bodies 2 / 200 (fires under 60) → it would fire; Haul to the top: ..."), from the
## views and the staffing projection. Rows are built once and updated in place on every bind.

signal command_issued

var _vcfg: Dictionary = {}
var _bcfg: Dictionary = {}
var _views: Dictionary = {}
## The shell's cached staffing projection: project.call(order, extra := {}) -> the jobs array.
var project: Callable
var _base := 2
var _slots_label: Label
var _break_label: Label
var _note_label: Label
var _none_label: Label  # the one "projected rates arrive with E3" line while no stance has a projection
var _status: Label
var _list: VBoxContainer
var _rows: Dictionary = {}  # stance id -> {toggle, chips, hold, proj, none, id}


func _ready() -> void:
	_vcfg = ConfigDb.v("town", "view", {})
	_bcfg = ConfigDb.data.get("buildings", {})
	_base = int(ConfigDb.data.get("economy", {}).get("stance", {}).get("base_slots", 2))
	add_theme_constant_override("separation", 6)
	_slots_label = TownUI.label("", 16)
	add_child(_slots_label)
	_break_label = _wrap("", 12, "text_dim")
	add_child(_break_label)
	_note_label = _wrap("", 14, "select")
	add_child(_note_label)
	_none_label = _wrap(_t("no_projection"), 12, "text_dim")
	add_child(_none_label)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var pad := MarginContainer.new()  # bottom padding: the last row clears the scroll edge when scrolled to the end
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.add_theme_constant_override("margin_bottom", int(_vcfg.get("scroll_pad_px", 16)))
	scroll.add_child(pad)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 6)
	pad.add_child(_list)
	_status = _wrap("", 14, "select")
	add_child(_status)


func _t(key: String) -> String:
	return String(_vcfg.get("behaviour", {}).get(key, key))


func _wrap(text: String, size: int, key := "text") -> Label:
	var l := TownUI.label(text, size, key)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _name_of(id: String) -> String:
	return String(_vcfg.get("stance_labels", {}).get(id, id.capitalize()))


func bind(views: Dictionary) -> void:
	if _list == null:
		return
	var st: Dictionary = views.get("stances", {})
	var slots := int(st.get("slots", 0))
	_slots_label.text = _t("slots_line").format({"used": int(st.get("used", 0)), "slots": slots})
	var home: bool = String(views.get("relish", {}).get("state", "home")) == "home"
	var parts := TownBehaviour.slot_breakdown(slots, _base, home)
	_break_label.text = _t("slots_breakdown").format({"base": parts["base"], "guild": parts["guild"], "home": parts["home"]})
	var rows: Array = st.get("stances", [])
	var suspended: Array = []
	for s in rows:
		if bool(s.get("suspended", false)):
			suspended.append(_name_of(String(s.get("id", ""))))
	var note: Array = []
	if not home:
		note.append(_t("away_note"))
	if not suspended.is_empty():
		note.append(_t("suspended_note").format({"names": ", ".join(suspended)}))
	_note_label.text = " ".join(note)
	_note_label.visible = not note.is_empty()
	var units: Dictionary = _vcfg.get("rate_units", {})
	_none_label.visible = not TownBehaviour.stances_live(views)
	_views = views
	var town: Dictionary = views.get("town", {})
	var ladder := TownBehaviour.effective(town)
	var before := _project(ladder)
	for s in rows:
		var id := String(s.get("id", ""))
		if not _rows.has(id):
			_make_row(id)
		_update_row(_rows[id], s, units)
		var job := TownBehaviour.stance_job(id, town, _vcfg)
		var after := _project(TownBehaviour.to_top(ladder, job)) if job != "" else []
		TownUI.set_parts(_rows[id]["trade"], TownBehaviour.stance_trade(id, views, before, after, _vcfg))


## The allocation for `order`, from the shell's one cached helper (set at setup, Covington.project_staffing).
func _project(order: Array) -> Array:
	return project.call(order) if project.is_valid() else []


func _make_row(id: String) -> void:
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", TownUI.panel_box())
	_list.add_child(box)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	box.add_child(col)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	col.add_child(head)
	var toggle := TownUI.button("Off")
	toggle.toggle_mode = true
	toggle.custom_minimum_size = Vector2(72, TownUI.MIN_TARGET)
	toggle.toggled.connect(_on_toggled.bind(id))
	head.add_child(toggle)
	var nm := TownUI.label(_name_of(id), 16)
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(nm)
	var chips := TownUI.label("", 14, "text_dim")
	head.add_child(chips)
	col.add_child(_wrap(String(_vcfg.get("stance_rules", {}).get(id, "")), 12, "text_dim"))
	var trade := TownUI.parts_label(13, "text", true)  # its trade in the town's numbers
	trade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(trade)
	var hold := TownUI.label("", 12, "text_dim")
	col.add_child(hold)
	var proj := TownUI.rate_label("", 14)
	proj.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(proj)
	var none := TownUI.label(_t("no_projection"), 12, "text_dim")
	col.add_child(none)
	_rows[id] = {"toggle": toggle, "chips": chips, "hold": hold, "proj": proj, "none": none, "on": false, "trade": trade}


func _update_row(r: Dictionary, s: Dictionary, units: Dictionary) -> void:
	var on := bool(s.get("on", false))
	r["on"] = on
	var toggle: Button = r["toggle"]
	toggle.set_pressed_no_signal(on)
	toggle.text = "On" if on else "Off"
	toggle.add_theme_stylebox_override("normal", TownUI.button_box_cached("active" if on else "normal"))
	var chips: Array = [_t("chip_on") if on else _t("chip_off")]
	if bool(s.get("suspended", false)):
		chips.append(_t("chip_suspended"))
	if bool(s.get("active", false)):
		chips.append(_t("chip_active"))
	(r["chips"] as Label).text = " · ".join(chips)
	var hold := float(s.get("hold_s_left", 0.0))
	(r["hold"] as Label).visible = hold > 0.0
	(r["hold"] as Label).text = _t("hold").format({"s": ceili(hold)})
	var lines := TownBehaviour.projected_parts(s.get("projected", {}), units)
	var proj: Label = r["proj"]
	var none: Label = r["none"]
	var empty: bool = (s.get("projected", {}) as Dictionary).is_empty()
	none.visible = empty and TownBehaviour.stances_live(_views)  # while none is live, the one line above says it
	proj.visible = not empty
	if not empty:
		var lead := _t("projected_off") if on else _t("projected_on")
		proj.text = lead + " " + ("   ".join(lines) if not lines.is_empty() else "±0")


func _on_toggled(pressed: bool, id: String) -> void:
	var r: Dictionary = Game.state.cmd_set_stance(id, pressed)
	if bool(r.get("ok", false)):
		_status.text = ""
	else:
		# the view, not the button, is the truth: snap back and say why
		var row: Dictionary = _rows.get(id, {})
		if not row.is_empty():
			(row["toggle"] as Button).set_pressed_no_signal(not pressed)
		var why := String(r.get("reason", ""))
		var refusals: Dictionary = _vcfg.get("behaviour", {}).get("refusals", {})
		_status.text = String(refusals.get(why, refusals.get("_unknown", why)))
	command_issued.emit()


func on_game_event(_ev: Dictionary) -> void:
	pass
