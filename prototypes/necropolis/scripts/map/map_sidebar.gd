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
var _stats: Label
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
	_title = _label(vb, int(cfg["font_title"]), "text")
	_sub = _label(vb, int(cfg["font_sub"]), "text_dim")
	_desc = _label(vb, int(cfg["font_body"]), "text_dim")
	_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(HSeparator.new())
	_stats = _label(vb, int(cfg["font_body"]), "text")
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


func _label(parent: Node, font_size: int, color_key: String) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", Palette.c(color_key))
	parent.add_child(l)
	return l


## Show the card for `id`, or hide the panel for "" / an unknown id.
func select(id: String) -> void:
	selected_id = id
	visible = id != ""
	if visible:
		refresh()


func covers(screen_pos: Vector2) -> bool:
	return visible and get_global_rect().has_point(screen_pos)


func refresh() -> void:
	if not visible:
		return
	_button.visible = true
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
	_stats.text = "Minting %s mass\nTier %s\nWorkers %s · idle %s\nLiving %s / %s" % [
		MapLogic.fmt_rate(_mint_rate()), str(town.get("tier", "")).capitalize(),
		MapLogic.fmt_mass(float(workers.get("total", 0.0))), MapLogic.fmt_mass(float(workers.get("idle", 0.0))),
		MapLogic.fmt_mass(float(town.get("living", 0.0))), MapLogic.fmt_mass(float(town.get("living_cap", 0.0)))]
	_button.text = "ENTER COVINGTON"


func _show_vei() -> void:
	var v := model.vei
	var sign := int(v.get("sign", 0))
	_title.text = "Vei's Domain"
	_sub.text = "THE GODDESS OF LIFE"
	_desc.text = _world_desc("vei")
	_stats.text = "UNDEAD MASSED AT HER GATES\n    %s\n\nDifferential %s %s\nDrains in %s\n\nConfrontation odds %d%%" % [
		MapLogic.fmt_mass(float(v.get("backlog", 0.0))), MapLogic.fmt_rate(float(v.get("diff", 0.0))),
		MapLogic.sign_glyph(sign), MapLogic.fmt_drain(float(v.get("drain_s", -1.0))),
		roundi(float(v.get("odds", 0.0)) * 100.0)]
	_button.text = "BEGIN THE FINAL CONFRONTATION"


func _show_fort(f: Dictionary) -> void:
	_title.text = str(f["name"])
	_sub.text = "FORTRESS · TIER %d · CAPACITY %s%s" % [f["tier"], MapLogic.fmt_mass(float(f["cap"])),
		" · HELD" if f.get("held", false) else ""]
	_desc.text = _fort_desc(str(f["id"]))
	var lines := "LIVING  %5s\nUNDEAD  %5s\nDEAD    %5s\nEMPTY   %5s\n\nWAR IN     %s\nLIVING IN  %s" % [
		MapLogic.fmt_mass(float(f["living"])), MapLogic.fmt_mass(float(f["undead"])),
		MapLogic.fmt_mass(float(f["dead"])), MapLogic.fmt_mass(float(f["space"])),
		MapLogic.fmt_rate(float(f["war_in"])), MapLogic.fmt_rate(float(f["ship_in"]))]
	if float(f.get("simulacrum_charges", 0.0)) > 0.0:
		lines += "\nsimulacrum charges %s" % MapLogic.fmt_mass(float(f["simulacrum_charges"]))
	_stats.text = lines
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
	_stats.text = "Migrants to Covington\n%s" % MapLogic.fmt_rate(float(v.get("migrants", 0.0)))
	_button.visible = false


func _on_action() -> void:
	if selected_id == MapModel.VEI:
		_confirm.popup_centered()
	elif selected_id != "":
		act.emit({"teleport_to": selected_id})
