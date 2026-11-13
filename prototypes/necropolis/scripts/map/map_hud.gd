class_name MapHud
extends Control
## The map's overlay: the stocks bar, the bottom hint, the toast, the victory banner and the
## debug speed row. Reads the shared MapModel; reacts to Game.game_event. Task 6 rewrites the
## bar rates-first.

const STOCKS := [["gold", "GOLD"], ["bone", "BONE"], ["bodies", "BODIES"], ["living", "LIVING"], ["workers", "WORKERS"]]

var model: MapModel

var _bar: Label
var _hint: Label
var _toast: Label
var _victory: Label
var _speed_row: HBoxContainer
var _toast_t := 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cfg := MapLogic.cfg()
	var pos: Array = cfg["topbar_pos_px"]
	_bar = _label(int(cfg["font_hud"]), "text")
	_bar.position = Vector2(float(pos[0]), float(pos[1]))
	_hint = _label(int(cfg["font_hint"]), "text_dim")
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
	lab.add_theme_font_size_override("font_size", int(cfg["font_label"]))
	lab.add_theme_color_override("font_color", Palette.c("text_dim"))
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
	refresh()


func refresh() -> void:
	var hud := model.hud
	var stock := {}
	for r in hud.get("rates", []):
		stock[r["id"]] = float(r["stock"])
	var parts: Array[String] = []
	for s in STOCKS:
		parts.append("%s %s" % [s[1], MapLogic.fmt_mass(stock.get(s[0], 0.0))])
	parts.append("ODDS %d%%" % roundi(float(hud.get("odds", 0.0)) * 100.0))
	var ts := float(hud.get("time_scale", 1.0))
	if not is_equal_approx(ts, 1.0):
		parts.append("[×%d]" % int(ts))
	_bar.text = "   ".join(parts)


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
