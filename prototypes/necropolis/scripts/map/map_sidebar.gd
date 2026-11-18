class_name MapSidebar
extends PanelContainer
## The right-hand card panel: a fortress, Covington, Vei's domain or a village, rebuilt from the
## shared MapModel's views. Its actions (MOVE / CANCEL / DESCEND / HAUL, the Vei card's BEGIN) are
## built by RelishLogic and sent as commands; a dive (DESCEND, a confirmed BEGIN) leaves through
## `dive(node_id)`, which world_map turns into the router's `finished({v: 2, teleport_to})`.
## Vei's odds summary is pinned with the actions, beside BEGIN, out of the card's scroll. A card
## taller than its room scrolls, and its bottom edge fades into the panel while more lies below.

signal dive(node_id: String)
signal toast(msg: String)

var model: MapModel
var hud: MapHud  # its plates decide how high the card may start (set by world_map)
var selected_id := ""

var _scroll: ScrollContainer
var _scroll_box: Control  # holds the scroll and the fade over its bottom edge
var _fade: Control
var _cue: Label
var _card: MapCardView
var _actions: VBoxContainer
var _act_sig := ""
var _act_nodes: Array = []
var _confirm: ConfirmationDialog
var _descend_confirm: ConfirmationDialog
var _descend_id := ""  # the fort the descend dialog was opened for
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
	_scroll_box = Control.new()
	_scroll_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(_scroll_box)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_scroll_box.add_child(_scroll)
	_fade = Control.new()
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_fade.offset_top = -float(cfg["sidebar_fade_px"])
	_fade.draw.connect(_draw_fade)
	_scroll_box.add_child(_fade)
	_cue = Label.new()  # "▼ scroll for more", in the gap under a scrolled card's last whole block
	_cue.text = str(cfg["cards"]["scroll_cue"])
	_cue.mouse_filter = Control.MOUSE_FILTER_IGNORE
	MapType.style_label(_cue, "text_dim", int(cfg["font_body"]))
	_cue.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_cue.visible = false
	_scroll_box.add_child(_cue)
	_scroll.get_v_scroll_bar().value_changed.connect(func(_v: float) -> void: _update_fade())
	_scroll.get_v_scroll_bar().changed.connect(_update_fade)
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
	# DESCEND with nobody coming in asks first: its own dialog, so a confirmed BEGIN still dives to Vei.
	_descend_confirm = ConfirmationDialog.new()
	_descend_confirm.title = str(cfg["cards"]["descend_confirm_title"])
	_descend_confirm.ok_button_text = str(cfg["cards"]["descend_confirm_ok"])
	_descend_confirm.min_size.x = int(cfg["cards"]["confirm_w_px"])
	_descend_confirm.confirmed.connect(func(): dive.emit(_descend_id))
	add_child(_descend_confirm)


## Show the card for `id`, or hide the panel for "" / an unknown id.
func select(id: String) -> void:
	if id != selected_id:
		_scroll.scroll_vertical = 0
		_confirm.hide()  # their text is a snapshot from popup time
		_descend_confirm.hide()
	selected_id = id
	visible = id != ""
	if visible:
		refresh()


func refresh() -> void:
	if not visible:
		return
	if selected_id == MapModel.VEI:
		_card.show_card(CardBlocksLogic.vei_card(model.vei, _world_desc("vei"), model.party.get("party", []), model.unit_names, model.readout()))
		var acts := RelishLogic.vei_actions(model.vei, model.relish)
		var at := acts.find_custom(func(i): return str(i["act"]) == "begin")
		acts.insert(maxi(at, 0), {"kind": "line", "text": CardLogic.pinned_odds(model.readout()), "act": "", "enabled": true})
		_flush_actions(acts)
	elif model.forts_by_id.has(selected_id):
		var f := model.fort(selected_id)
		_card.show_card(CardBlocksLogic.fort_card(f, _fort_desc(selected_id), model.backups, model.unit_names, ConfigDb.data.get("loot", {}),
			model.party, ConfigDb.data.get("raid", {}), ConfigDb.data.get("economy", {}), _tide_bias(),
			float(model.realm_cfg.get("tithe", {}).get("siege_block", 0.0))))
		_flush_actions(RelishLogic.fort_actions(f, model.relish, model.haul, model.names, _comes(f)))
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
	if hud != null:  # where the HUD's plates leave room, the card rises to the screen's top and uses the height
		offset_top = HudLogic.sidebar_top(get_viewport_rect().size.x, float(cfg["sidebar_width_px"]), hud.plates_right(),
			float(cfg["sidebar_top_gap_px"]), float(cfg["sidebar_top_px"]), float(cfg["sidebar_top_high_px"]))
	var chrome := 2.0 * float(cfg["sidebar_margin_px"]) + 2.0 * float(cfg["sidebar_vsep_px"]) + _sep.get_combined_minimum_size().y
	var room := get_viewport_rect().size.y - offset_top - float(cfg["sidebar_bottom_px"]) - chrome - _actions.get_combined_minimum_size().y
	var full := _card.get_combined_minimum_size().y
	room = maxf(room, 0.0)
	_scroll_box.custom_minimum_size.y = clampf(full, 0.0, room)
	# A card taller than its room ends its visible area on a block boundary, with a cue line in the
	# gap under it (the scroll box fills the room, so the scroll is shortened from its bottom).
	var gap := 0.0
	_cue.visible = full > room
	if full > room:
		var cue_h := _cue.get_combined_minimum_size().y
		gap = room - CardLogic.snap_bottom(_card.block_bottoms(), maxf(room - cue_h, 0.0))
		gap = maxf(gap, cue_h)
		_cue.offset_top = -cue_h
	_scroll.offset_bottom = -gap
	_fade.offset_bottom = -gap
	_fade.offset_top = -gap - float(cfg["sidebar_fade_px"])
	_update_fade()


## The fade shows while the card runs past the bottom of its room.
func _update_fade() -> void:
	var bar := _scroll.get_v_scroll_bar()
	# only mid-scroll: at the top the visible area already ends on a whole block, so nothing fades
	_fade.visible = bar.max_value - bar.page > 0.5 and bar.value > 0.5 and bar.value < bar.max_value - bar.page - 0.5
	_cue.modulate.a = 1.0 if bar.max_value - bar.page > 0.5 and bar.value < bar.max_value - bar.page - 0.5 else 0.0
	_fade.queue_redraw()


## A gradient from clear to the panel's own colour over the scroll's bottom edge.
func _draw_fade() -> void:
	var cfg := MapLogic.cfg()
	var solid := Palette.c("ground").lightened(float(cfg["panel_bg_lighten"]))
	solid.a = float(cfg["sidebar_bg_alpha"])
	var clear := solid
	clear.a = 0.0
	var sz := _fade.size
	_fade.draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(sz.x, 0.0), sz, Vector2(0.0, sz.y)]),
		PackedColorArray([clear, clear, solid, solid]))


func _tide_bias() -> float:
	return float(ConfigDb.data.get("realm", {}).get("relish", {}).get("tide_bias", 1.0))


## Who comes into a raid on fort `f` and the warning for it: {ci, warn}.
func _comes(f: Dictionary) -> Dictionary:
	var raid: Dictionary = ConfigDb.data.get("raid", {})
	var ci := CardLogic.comes_in(f, model.party, raid, ConfigDb.data.get("economy", {}))
	var tier := int(f.get("tier", 1))
	return {"ci": ci, "warn": CardLogic.comes_in_warning(ci, CardLogic.profile(tier, raid), tier, float(f.get("dead", 0.0)))}


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
				l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				ctl = l
			_actions.add_child(ctl)
			_act_nodes.append(ctl)
	for i in items.size():
		var node := _act_nodes[i] as Control
		node.set("text", items[i]["text"])
		if node is Label:  # a line's colour follows its key, which can change without the layout changing
			MapType.style_label(node as Label, str(items[i].get("key", "text_dim")), int(MapLogic.cfg()["font_body"]))


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
				var comes := _comes(model.fort(id))
				if int(comes["ci"]["total"]) == 0:
					_descend_id = id
					_descend_confirm.dialog_text = CardLogic.descend_confirm_text(comes["warn"])
					_descend_confirm.popup_centered()
				else:
					dive.emit(id)
			return
		"begin":
			if bool(model.vei.get("can_begin", false)):
				_confirm.dialog_text = CardLogic.confirm_text(model.readout(), model.vei)
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
