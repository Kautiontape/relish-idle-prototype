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

var _scroll: ScrollContainer
var _card: MapCardView
var _actions: VBoxContainer
var _act_sig := ""
var _act_nodes: Array = []
var _confirm: ConfirmationDialog
var _sep: HSeparator


func _ready() -> void:
	var cfg := MapLogic.cfg()
	set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	offset_left = -float(cfg["sidebar_width_px"])
	offset_right = 0.0
	custom_minimum_size.x = float(cfg["sidebar_width_px"])
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
	vb.add_theme_constant_override("separation", int(cfg["sidebar_vsep_px"]))
	add_child(vb)
	# The card scrolls if it overflows; the actions stay pinned below it, always reachable.
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(_scroll)
	_card = MapCardView.new()
	_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_card.assign_front.connect(_assign_front)
	_scroll.add_child(_card)
	_sep = HSeparator.new()
	vb.add_child(_sep)
	_actions = VBoxContainer.new()
	_actions.add_theme_constant_override("separation", int(cfg["sidebar_row_gap_px"]))
	vb.add_child(_actions)
	_confirm = ConfirmationDialog.new()
	_confirm.title = str(cfg["cards"]["confirm_title"])
	_confirm.ok_button_text = str(cfg["cards"]["confirm_ok"])
	_confirm.min_size.x = int(cfg["cards"]["confirm_w_px"])
	_confirm.confirmed.connect(func(): dive.emit(MapModel.VEI))
	add_child(_confirm)


## Show the card for `id`, or hide the panel for "" / an unknown id.
func select(id: String) -> void:
	if id != selected_id:
		_scroll.scroll_vertical = 0
	selected_id = id
	visible = id != ""
	if visible:
		refresh()


func refresh() -> void:
	if not visible:
		return
	if selected_id == MapModel.VEI:
		_card.show_card(CardBlocksLogic.vei_card(model.vei, _world_desc("vei"), model.party.get("party", []), model.unit_names, model.readout()))
		_flush_actions(RelishLogic.vei_actions(model.vei, model.relish))
	elif model.forts_by_id.has(selected_id):
		var f := model.fort(selected_id)
		_card.show_card(CardBlocksLogic.fort_card(f, _fort_desc(selected_id), model.backups, model.unit_names))
		_flush_actions(RelishLogic.fort_actions(f, model.relish, model.haul, model.names))
	elif not model.village(selected_id).is_empty():
		_card.show_card(CardBlocksLogic.village_card(model.village(selected_id), ""))
		_flush_actions([])
	else:
		visible = false
		return
	_fit_scroll()


## The card's scroll is as tall as its content, up to what is left under the top and above the
## bottom after the pinned actions; a taller card scrolls.
func _fit_scroll() -> void:
	var cfg := MapLogic.cfg()
	var chrome := 2.0 * float(cfg["sidebar_margin_px"]) + 2.0 * float(cfg["sidebar_vsep_px"]) + _sep.get_combined_minimum_size().y
	var room := get_viewport_rect().size.y - offset_top - float(cfg["sidebar_bottom_px"]) - chrome - _actions.get_combined_minimum_size().y
	_scroll.custom_minimum_size.y = clampf(_card.get_combined_minimum_size().y, 0.0, maxf(room, 0.0))


func _world_desc(key: String) -> String:
	return str(ConfigDb.data.get("world", {}).get(key, {}).get("desc", ""))


func _fort_desc(id: String) -> String:
	for w in ConfigDb.data.get("world", {}).get("forts", []):
		if w["id"] == id:
			return str(w.get("desc", ""))
	return ""


## The card's actions, from RelishLogic (lines and buttons). Buttons are rebuilt only when the
## layout changes (so a press is never swallowed by a refresh); their texts update in place.
func _flush_actions(items: Array) -> void:
	_sep.visible = not items.is_empty()
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
				_confirm.dialog_text = CardLogic.confirm_text(model.readout())
				_confirm.popup_centered()
			return
	toast.emit(ok_msg if r["ok"] else RelishLogic.reason_text(str(r["reason"])))
	model.refresh(true)
	refresh()


## A front selector changed: send it, toast a refusal in words, and redraw from the views.
func _assign_front(uid: String, front_id: String) -> void:
	var r := model.state.cmd_assign_front(uid, front_id)
	if r["ok"]:
		var who := str(model.unit_names.get(uid, uid))
		var cards: Dictionary = MapLogic.cfg()["cards"]
		toast.emit((str(cards["assign_ok_fmt"]) % [who, CardLogic.front_name(front_id)]) if front_id != "" else str(cards["assign_cleared_fmt"]) % who)
	else:
		toast.emit(RelishLogic.reason_text(str(r["reason"])))
	model.refresh(true)
	refresh()
