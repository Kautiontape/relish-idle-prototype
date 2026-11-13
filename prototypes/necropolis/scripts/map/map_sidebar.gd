class_name MapSidebar
extends PanelContainer
## The right-hand card panel: a fortress, Covington, Vei's domain or a village, rebuilt from the
## shared MapModel's views. Actions leave through `act` (world_map turns them into `finished`).

signal act(result: Dictionary)

var model: MapModel
var selected_id := ""

var _title: Label
var _sub: Label
var _desc: Label
var _rows: VBoxContainer
var _rows_sig := ""
var _pending: Array = []
var _button: Button
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
	_button = Button.new()
	_button.custom_minimum_size = Vector2(0, float(cfg["button_min_h_px"]))
	_button.add_theme_font_size_override("font_size", int(cfg["font_button"]))
	_button.pressed.connect(_on_action)
	vb.add_child(_button)
	_confirm = ConfirmationDialog.new()
	_confirm.dialog_text = "Vei waits at the heart of her domain.\nBegin the final confrontation?"
	_confirm.ok_button_text = "Begin"
	_confirm.confirmed.connect(func(): act.emit({"teleport_to": "vei"}))
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
	_button.visible = true
	_pending.clear()
	if selected_id == MapModel.COVINGTON:
		_show_covington()
	elif selected_id == MapModel.VEI:
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


func _mint_rate() -> float:
	for r in model.hud.get("rates", []):
		if r["id"] == "mint":
			return float(r["rate"])
	return 0.0


func _show_covington() -> void:
	var town := model.state.view_town()
	var workers: Dictionary = town.get("workers", {})
	_title.text = "Covington"
	_sub.text = "HOME · THE FACTORY"
	_desc.text = _world_desc("covington")
	_row("MINTING", MapLogic.fmt_rate(_mint_rate()), "rate")
	_row("TIER", str(town.get("tier", "")).capitalize(), "text")
	_row("WORKERS", MapLogic.fmt_mass(float(workers.get("total", 0.0))), "mass")
	_row("IDLE", MapLogic.fmt_mass(float(workers.get("idle", 0.0))), "mass")
	_row("LIVING", "%s / %s" % [MapLogic.fmt_mass(float(town.get("living", 0.0))), MapLogic.fmt_mass(float(town.get("living_cap", 0.0)))], "mass")
	_button.text = "ENTER COVINGTON"


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
	_button.text = "BEGIN THE FINAL CONFRONTATION"


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
	_button.text = "TELEPORT"


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
	_button.visible = false


func _on_action() -> void:
	if selected_id == MapModel.VEI:
		_confirm.popup_centered()
	elif selected_id != "":
		act.emit({"teleport_to": selected_id})
