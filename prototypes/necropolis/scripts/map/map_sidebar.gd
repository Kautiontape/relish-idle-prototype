class_name MapSidebar
extends PanelContainer
## The right-hand card panel: a fortress, Covington, Vei's domain or a village, rebuilt from the
## shared MapModel's views. Its actions (MOVE / CANCEL / DESCEND / HAUL, the Vei card's BEGIN) are
## built by RelishLogic and sent as commands; a dive (DESCEND, a confirmed BEGIN) leaves through
## `dive(node_id)`, which world_map turns into the router's `finished({v: 2, teleport_to})`.

signal dive(node_id: String)
signal toast(msg: String)

var model: MapModel
var selected_id := ""

var _title: Label
var _sub: Label
var _desc: Label
var _rows: VBoxContainer
var _rows_sig := ""
var _pending: Array = []
var _actions: VBoxContainer
var _act_sig := ""
var _act_nodes: Array = []
var _confirm: ConfirmationDialog


func _ready() -> void:
	var cfg := MapLogic.cfg()
	set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	offset_left = -float(cfg["sidebar_width_px"])
	offset_top = float(cfg["sidebar_top_px"])
	var style := StyleBoxFlat.new()
	style.bg_color = Palette.c("ground").lightened(float(cfg["panel_bg_lighten"]))
	style.bg_color.a = float(cfg["sidebar_bg_alpha"])
	style.border_color = Palette.c("contour", float(cfg["panel_border_alpha"]))
	style.set_border_width_all(1)
	style.set_content_margin_all(int(cfg["sidebar_margin_px"]))
	add_theme_stylebox_override("panel", style)
	visible = false
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	add_child(vb)
	_title = Label.new()
	MapType.style_title(_title)
	vb.add_child(_title)
	_sub = Label.new()
	MapType.style_label(_sub)
	vb.add_child(_sub)
	_desc = Label.new()
	MapType.style_label(_desc, "text_dim", int(cfg["font_body"]))
	_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(_desc)
	vb.add_child(HSeparator.new())
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", int(cfg["sidebar_row_gap_px"]))
	vb.add_child(_rows)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(spacer)
	_actions = VBoxContainer.new()
	_actions.add_theme_constant_override("separation", int(cfg["sidebar_row_gap_px"]))
	vb.add_child(_actions)
	_confirm = ConfirmationDialog.new()
	_confirm.dialog_text = "Vei waits at the heart of her domain.\nBegin the final confrontation?"
	_confirm.ok_button_text = "Begin"
	_confirm.confirmed.connect(func(): dive.emit(MapModel.VEI))
	add_child(_confirm)


## One stats row: a dim upright label, then its value in the type law's face for `kind`:
## "rate" (oblique, light, signed), "mass" (upright, heavy) or "text" (regular). `suffix` is a
## trailing glyph in the label face (the sign).
func _row(label: String, value: String, kind: String, suffix := "") -> void:
	_pending.append([label, value, kind, suffix])


## Show the card for `id`, or hide the panel for "" / an unknown id.
func select(id: String) -> void:
	selected_id = id
	visible = id != ""
	if visible:
		refresh()


func refresh() -> void:
	if not visible:
		return
	_pending.clear()
	if selected_id == MapModel.VEI:
		_show_vei()
	elif model.forts_by_id.has(selected_id):
		_show_fort(model.fort(selected_id))
	elif not model.village(selected_id).is_empty():
		_show_village(model.village(selected_id))
	else:
		visible = false
	_flush_rows()


## Rebuilds the stats rows only when their content changed (the card refreshes every 0.25 s).
func _flush_rows() -> void:
	var sig := str(_pending)
	if sig == _rows_sig:
		return
	_rows_sig = sig
	for c in _rows.get_children():
		_rows.remove_child(c)
		c.queue_free()
	var label_w := float(MapLogic.cfg()["sidebar_row_label_px"])
	for r in _pending:
		var box := HBoxContainer.new()
		_rows.add_child(box)
		var name_l := Label.new()
		MapType.style_label(name_l, "text_dim", int(MapLogic.cfg()["font_body"]))
		name_l.text = r[0]
		name_l.custom_minimum_size.x = label_w
		box.add_child(name_l)
		var val := Label.new()
		match r[2]:
			"rate":
				MapType.style_rate(val)
			"mass":
				MapType.style_mass(val)
			_:
				MapType.style_label(val, "text", int(MapLogic.cfg()["font_body"]))
		val.text = r[1]
		box.add_child(val)
		if r[3] != "":
			var suf := Label.new()
			MapType.style_label(suf, "text", int(MapLogic.cfg()["font_body"]))
			suf.text = " " + str(r[3])
			box.add_child(suf)


func _world_desc(key: String) -> String:
	return str(ConfigDb.data.get("world", {}).get(key, {}).get("desc", ""))


func _fort_desc(id: String) -> String:
	for w in ConfigDb.data.get("world", {}).get("forts", []):
		if w["id"] == id:
			return str(w.get("desc", ""))
	return ""


func _show_vei() -> void:
	var v := model.vei
	var sign := int(v.get("sign", 0))
	_title.text = "Vei's Domain"
	_sub.text = "THE GODDESS OF LIFE"
	_desc.text = _world_desc("vei")
	_row("MASSED AT HER GATES", MapLogic.fmt_mass(float(v.get("backlog", 0.0))), "mass")
	_row("DIFFERENTIAL", MapLogic.fmt_rate(float(v.get("diff", 0.0))), "rate", MapLogic.sign_glyph(sign))
	_row("DRAINS IN", MapLogic.fmt_drain(float(v.get("drain_s", -1.0))), "mass")
	_row("CONFRONTATION ODDS", "%d%%" % roundi(float(v.get("odds", 0.0)) * 100.0), "mass")
	_flush_actions(RelishLogic.vei_actions(v, model.relish))


func _show_fort(f: Dictionary) -> void:
	_title.text = str(f["name"])
	_sub.text = "FORTRESS · TIER %d · CAPACITY %s%s" % [f["tier"], MapLogic.fmt_mass(float(f["cap"])),
		" · HELD" if f.get("held", false) else ""]
	_desc.text = _fort_desc(str(f["id"]))
	_row("LIVING", MapLogic.fmt_mass(float(f["living"])), "mass")
	_row("UNDEAD", MapLogic.fmt_mass(float(f["undead"])), "mass")
	_row("DEAD", MapLogic.fmt_mass(float(f["dead"])), "mass")
	_row("EMPTY", MapLogic.fmt_mass(float(f["space"])), "mass")
	_row("WAR IN", MapLogic.fmt_rate(float(f["war_in"])), "rate")
	_row("LIVING IN", MapLogic.fmt_rate(float(f["ship_in"])), "rate")
	if float(f.get("simulacrum_charges", 0.0)) > 0.0:
		_row("SIMULACRUM", MapLogic.fmt_mass(float(f["simulacrum_charges"])), "mass")
	_flush_actions(RelishLogic.fort_actions(f, model.relish, model.haul, model.names))


func _show_village(v: Dictionary) -> void:
	var owner := str(v.get("owner", "none"))
	_title.text = str(v["name"])
	_sub.text = "TOWN · %s" % owner.to_upper()
	var mood := "Contested ground. Nobody sleeps well."
	if owner == "player":
		mood = "Under the necrosis, its people drift to Covington."
	elif owner == "vei":
		mood = "Held fast by Vei's living."
	_desc.text = "A small blue town. Relish cannot visit; she can only watch its lights.\n\n" + mood
	_row("MIGRANTS TO COVINGTON", MapLogic.fmt_rate(float(v.get("migrants", 0.0))), "rate")
	_flush_actions([])


## The card's actions, from RelishLogic (lines and buttons). Buttons are rebuilt only when the
## layout changes (so a press is never swallowed by a refresh); their texts update in place.
func _flush_actions(items: Array) -> void:
	var sig := RelishLogic.actions_sig(items)
	if sig != _act_sig:
		_act_sig = sig
		for c in _actions.get_children():
			_actions.remove_child(c)
			c.queue_free()
		_act_nodes.clear()
		for it in items:
			var ctl: Control
			if it["kind"] == "button":
				var b := Button.new()
				MapUi.style_button(b)
				b.disabled = not bool(it["enabled"])
				b.pressed.connect(_do.bind(str(it["act"])))
				ctl = b
			else:
				var l := Label.new()
				MapType.style_label(l, "text_dim", int(MapLogic.cfg()["font_body"]))
				l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				ctl = l
			_actions.add_child(ctl)
			_act_nodes.append(ctl)
	for i in items.size():
		(_act_nodes[i] as Control).set("text", items[i]["text"])


func _name_of(id: String) -> String:
	return HudLogic.node_name(id, model.names)


## Sends the command an action button stands for, toasts its outcome (a refusal in plain words).
func _do(act: String) -> void:
	var s := model.state
	var id := selected_id
	var r := {"ok": true, "reason": ""}
	var ok_msg := ""
	match act:
		"move":
			r = s.cmd_move_relish(id)
			ok_msg = "Relish → %s · %s" % [_name_of(id), RelishLogic.fmt_eta(float(r.get("eta_s", 0.0)))]
		"cancel":
			r = s.cmd_cancel_travel()
			ok_msg = "Relish turns back · %s" % RelishLogic.fmt_eta(float(r.get("eta_s", 0.0)))
		"haul":
			r = s.cmd_set_haul_target(id)
			ok_msg = "Haul from %s" % _name_of(id)
		"haul_auto":
			r = s.cmd_set_haul_target("auto")
			ok_msg = "Haul: auto"
		"descend":
			if bool(model.fort(id).get("can_descend", false)):
				dive.emit(id)
			return
		"begin":
			if bool(model.vei.get("can_begin", false)):
				_confirm.popup_centered()
			return
	toast.emit(ok_msg if r["ok"] else RelishLogic.reason_text(str(r["reason"])))
	model.refresh(true)
	refresh()
