class_name MapHud
extends Control
## The map's overlay: the rates-first top bar (every stream's signed net rate, then its stock,
## then odds / sign / drain), the objective strip, the bottom hint, the toast, the victory
## banner and the debug speed row. Reads the shared MapModel; reacts to Game.game_event. Text
## comes from HudLogic and is set only when the model has a new rev; fonts from MapType.

var model: MapModel

var _bar: HFlowContainer
var _bar_plate: ColorRect
var _obj_plate: ColorRect
var _items: Array = []  # [{box, name, rate, stock, cap}] per stream, built on the first read
var _odds: Label
var _sign: Label
var _drain: Label
var _speed_tag: Label
var _objective: Label
var _hint: Label
var _toast: Label
var _victory: Label
var _speed_row: HBoxContainer
var _toast_t := 0.0
var _rev := -2


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cfg := MapLogic.cfg()
	var pos: Array = cfg["topbar_pos_px"]
	# darkening plates behind the bar and the objective: the map's brightest content may sit under them
	_bar_plate = _plate()
	_obj_plate = _plate()
	_bar = HFlowContainer.new()
	_bar.position = Vector2(float(pos[0]), float(pos[1]))
	_bar.size.x = float(cfg["topbar_max_w_px"])
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.add_theme_constant_override("h_separation", int(cfg["topbar_gap_px"]))
	_bar.add_theme_constant_override("v_separation", int(cfg["topbar_row_gap_px"]))
	_bar.sort_children.connect(_relayout)
	add_child(_bar)
	_objective = Label.new()
	_objective.mouse_filter = Control.MOUSE_FILTER_IGNORE
	MapType.style_label(_objective, "text_dim", int(cfg["objective_size_px"]))
	add_child(_objective)
	_hint = _label(int(cfg["font_hint"]), "text_dim")
	MapType.style_label(_hint)
	_hint.text = "drag to pan · wheel to zoom · click a fortress"
	_hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_hint.position = Vector2(-float(cfg["hint_half_width_px"]), -float(cfg["hint_bottom_px"]))
	_toast = _label(int(cfg["font_toast"]), "select")
	_toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast.custom_minimum_size = Vector2(float(cfg["toast_width_px"]), 0.0)
	_toast.position = Vector2(-float(cfg["toast_width_px"]) * 0.5, float(cfg["toast_top_px"]))
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.modulate.a = 0.0
	_victory = _label(int(cfg["font_victory"]), "undead")
	_victory.set_anchors_preset(Control.PRESET_CENTER)
	_victory.custom_minimum_size = Vector2(float(cfg["victory_width_px"]), 0.0)
	_victory.position = Vector2(-float(cfg["victory_width_px"]) * 0.5, -float(cfg["victory_up_px"]))
	_victory.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_victory.visible = false
	_build_speed_row(cfg)
	Game.game_event.connect(_on_event)


func _plate() -> ColorRect:
	var r := ColorRect.new()
	r.color = MapHud.plate_color()
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(r)
	return r


## The darkening plate behind the bar text: `ground` at topbar_plate_alpha (no palette key).
static func plate_color() -> Color:
	return Palette.c("ground", float(MapLogic.cfg()["topbar_plate_alpha"]))


## Places the objective under the bar's last row and sizes both plates: each runs from the left
## edge to the right end of its content (the bar wraps before the ground meter).
func _relayout() -> void:
	var cfg := MapLogic.cfg()
	var pad := float(cfg["topbar_plate_pad_px"])
	var right := 0.0
	for c in _bar.get_children():
		right = maxf(right, (c as Control).position.x + (c as Control).size.x)
	var bar_bottom := _bar.position.y + _bar.get_combined_minimum_size().y
	_bar_plate.position = Vector2.ZERO
	_bar_plate.size = Vector2(_bar.position.x + right + pad, bar_bottom + pad)
	_objective.position = Vector2(_bar.position.x, _bar_plate.size.y)
	var osz := _objective.get_combined_minimum_size()
	_obj_plate.position = Vector2(0.0, _bar_plate.size.y)
	_obj_plate.size = Vector2(_objective.position.x + osz.x + pad, osz.y + pad)


func _label(font_size: int, color_key: String) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", Palette.c(color_key))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l


## Debug controls are first-class, but only exist in debug sessions.
func _build_speed_row(cfg: Dictionary) -> void:
	_speed_row = HBoxContainer.new()
	_speed_row.position = Vector2(float(cfg["topbar_pos_px"][0]), float(cfg["speed_row_y_px"]))
	_speed_row.add_theme_constant_override("separation", 6)
	_speed_row.visible = model.state.debug_enabled
	add_child(_speed_row)
	var lab := Label.new()
	lab.text = "SPEED"
	MapType.style_label(lab)
	_speed_row.add_child(lab)
	for spd in cfg["speed_buttons"]:
		var b := Button.new()
		b.text = "×%d" % int(spd)
		b.custom_minimum_size = Vector2(float(cfg["button_min_h_px"]), float(cfg["button_min_h_px"]))
		b.add_theme_font_size_override("font_size", int(cfg["font_label"]))
		b.pressed.connect(_set_speed.bind(float(spd)))
		_speed_row.add_child(b)


func _set_speed(spd: float) -> void:
	model.state.cmd_debug_set_state({"time_scale": spd})
	show_toast("sim speed ×%d" % int(spd))


## Call once the model has its first read.
func start() -> void:
	if model.hud.get("won", false):
		_on_victory()
	refresh(true)


## Builds the bar's labels once, from the first read's stream list: one box per stream,
## `name  rate  stock  cap mark`, then the status group.
func _build_bar(items: Array) -> void:
	var cfg := MapLogic.cfg()
	for it in items:
		var box := HBoxContainer.new()
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_theme_constant_override("separation", int(cfg["topbar_item_gap_px"]))
		_bar.add_child(box)
		var parts := {"box": box, "name": _bar_label(box), "rate": _bar_label(box), "stock": _bar_label(box), "cap": _bar_label(box)}
		MapType.style_label(parts["name"])
		MapType.style_rate(parts["rate"])
		MapType.style_mass(parts["stock"], "text_dim", MapType.size_of("size_stock"))
		MapType.style_label(parts["cap"], "text", MapType.size_of("size_stock"))
		_items.append(parts)
	var status := HBoxContainer.new()
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status.add_theme_constant_override("separation", int(cfg["topbar_item_gap_px"]))
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(float(cfg["topbar_group_gap_px"]), 0.0)
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.add_child(spacer)
	_bar.add_child(status)
	var odds_name := _bar_label(status)
	MapType.style_label(odds_name)
	odds_name.text = "ODDS"
	_odds = _bar_label(status)
	MapType.style_mass(_odds)
	_sign = _bar_label(status)
	MapType.style_mass(_sign)
	var drain_name := _bar_label(status)
	MapType.style_label(drain_name)
	drain_name.text = "DRAIN"
	_drain = _bar_label(status)
	MapType.style_mass(_drain)
	_speed_tag = _bar_label(status)
	MapType.style_label(_speed_tag, "select")


func _bar_label(parent: Node) -> Label:
	var l := Label.new()
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


## Sets the bar's text from the model's hud. A no-op until the model has a new rev.
func refresh(force := false) -> void:
	if not force and model.rev == _rev:
		return
	_rev = model.rev
	var hud := model.hud
	var items := HudLogic.rate_items(hud)
	if _items.is_empty():
		_build_bar(items)
	for i in mini(items.size(), _items.size()):
		var it: Dictionary = items[i]
		var w: Dictionary = _items[i]
		(w["name"] as Label).text = it["label"]
		(w["rate"] as Label).text = it["rate_text"]
		(w["stock"] as Label).text = it["stock_text"]
		(w["cap"] as Label).text = it["cap_mark"]
	var st := HudLogic.status(model.readout())
	_odds.text = st["odds_text"]
	_sign.text = st["sign_text"]
	_sign.add_theme_color_override("font_color", Palette.c(_sign_key(int(st["sign"]))))
	_drain.text = st["drain_text"]
	_speed_tag.text = HudLogic.speed_text(hud)
	_objective.text = HudLogic.objective_text(hud)
	_relayout.call_deferred()


## Backlog growing is good (undead), shrinking is danger; holding is neutral. The glyph is the
## signal; the colour is the second channel.
func _sign_key(sign: int) -> String:
	if sign > 0:
		return "undead"
	if sign < 0:
		return "danger"
	return "text_dim"


func tick(delta: float) -> void:
	if _toast_t > 0.0:
		_toast_t -= delta
		_toast.modulate.a = clampf(_toast_t / float(MapLogic.cfg()["toast_fade_s"]), 0.0, 1.0)


func show_toast(msg: String) -> void:
	_toast.text = msg
	_toast_t = float(MapLogic.cfg()["toast_s"])
	_toast.modulate.a = 1.0


func _on_event(ev: Dictionary) -> void:
	match ev.get("type", ""):
		"relish_respawned":
			if ev.get("with_clone", false):
				show_toast("A clone vat hisses open. Relish walks again.")
			else:
				show_toast("No vat waited. The army scattered while her body re-knit.")
		"vei_result":
			if ev.get("won", false):
				_on_victory()
			else:
				show_toast("She threw the horde back. The factory must grow.")


func _on_victory() -> void:
	_victory.text = "VEI HAS DROWNED IN THE DEAD\nThe realm is quiet. The factory hums on."
	_victory.visible = true
