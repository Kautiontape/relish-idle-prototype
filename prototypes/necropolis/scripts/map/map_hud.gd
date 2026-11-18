class_name MapHud
extends Control
## The map's overlay: the rates-first top bar (every stream's signed net rate, then its stock,
## then odds / sign / drain), the objective strip, the bottom hint, the toast, the victory
## banner (shown by the victory set piece, MapSetpieces, once every lane stops) and the debug
## speed row. Reads the shared MapModel; reacts to Game.game_event. Text
## comes from HudLogic and is set only when the model has a new rev; fonts from MapType.
## The objective strip is one next action (NextLogic.choose, in strict order: a fort about to
## fall, a refilled raid from the model's raid set, Vei in reach, a first-clear raid from the same
## set, else the plan: the queue empty or the standing objective), a button at least 44 px tall on
## its plate: a click emits next_chosen with the line's AwayLogic action. Its text changes only
## when the pick changes (or its coarse clock ticks). The opening pushes its asks through
## set_opening_ask, which beats every rule until cleared with "".

signal inset_changed(inset: float)  # the plates' bottom edge moved (the bar wrapped or its text changed)
signal next_chosen(action: Dictionary)  # the strip was clicked: AwayLogic.action's {kind, ...}, or {kind: "opening"} for an opening ask with no target

var model: MapModel

var _bar: VBoxContainer  # one HBoxContainer row per HudLogic.wrap_rows row
var _cells: Array = []  # the bar items (a box per stream, then the status box), in order
var _row_sig := ""
var _bar_plate: ColorRect
var _obj_plate: ColorRect
var _items: Array = []  # [{box, name, rate, stock, cap}] per stream, built on the first read
var _odds: Label
var _sign: Label
var _drain: Label
var _speed_tag: Label
var _objective: Button
var _leave: Label  # the quiet state's "Safe to leave" line under the strip (not clickable)
var _leave_plate: ColorRect
var _leave_rect := Rect2()  # the room kept for the leave line, shown or not
static var _next := {}  # the strip's pick (NextLogic.choose): kept between refreshes and map mounts so it does not flicker or flip on a return from town
static var _next_t := -1.0  # the game time of the last pick: time going backwards is a new game, which clears _next
var _opening := {}  # set_opening_ask's {text, target}
var _hint: Label
var chip: Control  # the Relish chip: the toast sits under it (set by world_map)
var _toast: Label
var _victory: Label
var _speed_row: HBoxContainer
var _toast_t := 0.0
var _last_inset := -1.0
var _hint_default := ""
var _rev := -2


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)  # also sizes it: anchored labels need a real parent rect
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cfg := MapLogic.cfg()
	var pos: Array = cfg["topbar_pos_px"]
	# darkening plates behind the bar and the objective: the map's brightest content may sit under them
	_bar_plate = _plate()
	_obj_plate = _plate()
	_leave_plate = _plate()
	_bar = VBoxContainer.new()
	_bar.position = Vector2(float(pos[0]), float(pos[1]))
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.add_theme_constant_override("separation", int(cfg["topbar_row_gap_px"]))
	add_child(_bar)
	_objective = Button.new()
	_objective.alignment = HORIZONTAL_ALIGNMENT_LEFT
	MapUi.style_button(_objective, int(cfg["objective_size_px"]))
	_objective.pressed.connect(_on_objective_pressed)
	add_child(_objective)
	_leave = _label(int(cfg["objective_size_px"]), "text")
	MapType.style_label(_leave, "text", int(cfg["objective_size_px"]))
	_leave.visible = false
	_leave_plate.visible = false
	_hint = _label(int(cfg["font_hint"]), "text_dim")
	MapType.style_label(_hint)
	_hint_default = "drag to pan · wheel to zoom · click a fortress · click Covington to enter"
	_hint.text = _hint_default
	# bottom line, to the right of the debug speed row, clear of the valve panel and the node labels
	_anchor_box(_hint, 0.0, 1.0, float(cfg["hint_left_px"]), float(cfg["hint_left_px"]) + float(cfg["hint_half_width_px"]) * 2.0, -float(cfg["hint_bottom_px"]))
	_toast = _label(int(cfg["font_toast"]), "select")
	# top-left under the Relish chip (placed by _sit_toast): clear of the nodes, near where the controls are
	_anchor_box(_toast, 0.0, 0.0, float(cfg["toast_left_px"]), float(cfg["toast_left_px"]) + float(cfg["toast_width_px"]), 0.0)
	_toast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_toast.add_theme_stylebox_override("normal", MapUi.plate_box(float(cfg["controls"]["toast_plate_alpha"]), int(cfg["controls"]["toast_pad_px"])))
	_toast.modulate.a = 0.0
	_victory = _label(int(cfg["font_victory"]), "undead")
	_anchor_box(_victory, 0.5, 0.5, -float(cfg["victory_width_px"]) * 0.5, float(cfg["victory_width_px"]) * 0.5, -float(cfg["victory_up_px"]))
	_victory.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# on the toast's plate: victory lights every lane green right under it
	_victory.add_theme_stylebox_override("normal", MapUi.plate_box(float(cfg["controls"]["toast_plate_alpha"]), int(cfg["controls"]["toast_pad_px"])))
	_victory.visible = false
	_build_speed_row(cfg)
	Game.game_event.connect(_on_event)


## Pins `l` to a horizontal/vertical anchor with x offsets and a top offset (a Control's `position`
## is absolute, so a centred label needs offsets from its anchor, not a negative position).
func _anchor_box(l: Label, ax: float, ay: float, left: float, right: float, top: float) -> void:
	l.anchor_left = ax
	l.anchor_right = ax
	l.anchor_top = ay
	l.anchor_bottom = ay
	l.offset_left = left
	l.offset_right = right
	l.offset_top = top
	l.grow_vertical = Control.GROW_DIRECTION_END


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
	for row in _bar.get_children():
		right = maxf(right, (row as Control).get_combined_minimum_size().x)
	var bar_bottom := _bar.position.y + _bar.get_combined_minimum_size().y
	_bar_plate.position = Vector2.ZERO
	_bar_plate.size = Vector2(_bar.position.x + right + pad, bar_bottom + pad)
	_objective.position = Vector2(_bar.position.x, _bar_plate.size.y)
	_objective.size = _objective.get_combined_minimum_size()
	var osz := _objective.get_combined_minimum_size()
	_obj_plate.position = Vector2(0.0, _bar_plate.size.y)
	_obj_plate.size = Vector2(_objective.position.x + osz.x + pad, osz.y + pad)
	var inset := _obj_plate.position.y + _obj_plate.size.y
	# The leave line's room is always kept under the strip, shown or not: toggling the line (a hold
	# starting or ending, a tithe warning) never changes the inset, so no refit and no chip jump.
	var lsz := _leave.get_combined_minimum_size()
	_leave.position = Vector2(_bar.position.x, inset)
	_leave.size = lsz
	_leave_plate.position = Vector2(0.0, inset)
	_leave_plate.size = Vector2(_leave.position.x + lsz.x + pad, lsz.y + pad)
	_leave_rect = Rect2(0.0, inset, _obj_plate.size.x, lsz.y + pad)
	inset += _leave_rect.size.y
	if inset != _last_inset:
		_last_inset = inset
		inset_changed.emit(inset)


## The leave line's reserved room (screen px, the strip's width): the
## default fit keeps the forts and Vei off it.
func leave_rect() -> Rect2:
	_relayout()
	return _leave_rect


## Screen px the HUD plates cover from the top (the bar and the strip): the Relish chip and the
## toast sit below this.
func top_inset() -> float:
	_relayout()
	return _last_inset


## Screen px the top bar's plate covers: the camera frames the map below this.
func bar_bottom() -> float:
	_relayout()
	return _bar_plate.size.y


## The objective strip's plate (screen px): the default fit keeps the forts and Vei off it.
func strip_rect() -> Rect2:
	_relayout()
	return Rect2(_obj_plate.position, _obj_plate.size)


func _label(font_size: int, color_key: String) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", Palette.c(color_key))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l


## Debug controls are first-class, but only exist in debug sessions: elsewhere no row is built.
func _build_speed_row(cfg: Dictionary) -> void:
	if not HudLogic.speed_row_shown(model.state):
		return
	_speed_row = HBoxContainer.new()
	_speed_row.position = Vector2(float(cfg["topbar_pos_px"][0]), float(cfg["speed_row_y_px"]))
	_speed_row.add_theme_constant_override("separation", 6)
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
	refresh(true)
	# the labels' sizes settle after their first layout: wrap and place the plates once more, so
	# panels that sit under them (the Relish chip) do not jump at the first UI tick
	await get_tree().process_frame
	if is_inside_tree():
		refresh(true)


## Builds the bar's labels once, from the first read's stream list: one box per stream,
## `name  rate  stock  cap mark`, then the status group.
func _build_bar(items: Array) -> void:
	var cfg := MapLogic.cfg()
	for it in items:
		var box := HBoxContainer.new()
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_theme_constant_override("separation", int(cfg["topbar_item_gap_px"]))
		_cells.append(box)
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
	status.add_child(spacer)
	_cells.append(status)
	var odds_name := _bar_label(status)
	MapType.style_label(odds_name)
	odds_name.text = str(cfg["cards"]["vei_odds_label"])
	_odds = _bar_label(status)
	MapType.style_mass(_odds)
	# the ▲/▼ is the backlog's sign, labelled as her strain: the odds are mostly time and can climb on a ▼
	var strain_name := _bar_label(status)
	MapType.style_label(strain_name)
	strain_name.text = str(cfg["strain_label"])
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
	_refresh_next()
	_wrap_cells()
	_relayout()
	_relayout.call_deferred()


## Lays the bar's cells into rows by HudLogic.wrap_rows (the one wrapping rule), rebuilding the
## row boxes only when the rows changed.
func _wrap_cells() -> void:
	var cfg := MapLogic.cfg()
	var widths: Array = _cells.map(func(c): return (c as Control).get_combined_minimum_size().x)
	var rows := HudLogic.wrap_rows(widths, float(cfg["topbar_gap_px"]), float(cfg["topbar_max_w_px"]))
	if str(rows) == _row_sig:
		return
	_row_sig = str(rows)
	for row in _bar.get_children():
		for c in row.get_children():
			row.remove_child(c)
		_bar.remove_child(row)
		row.queue_free()
	for r in rows:
		var row := HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_theme_constant_override("separation", int(cfg["topbar_gap_px"]))
		_bar.add_child(row)
		for i in r:
			row.add_child(_cells[i])


## A strip click: the pick's action, except that an opening ask with nothing to select (the valve)
## sends {kind: "opening"}, which the map routes to MapOpening (it flashes the triangle).
func _on_objective_pressed() -> void:
	var a: Dictionary = _next.get("action", {"kind": "none"})
	if str(_next.get("rule", "")) == NextLogic.OPENING and str(a.get("kind", "none")) == "none":
		a = {"kind": "opening"}
	next_chosen.emit(a)


## The strip's pick from the model's views (its committed clocks, not a dragged valve's), kept to
## the last pick while it still holds.
func _refresh_next() -> void:
	var inp := {"forts": model.forts, "clocks": model.clocks, "raids": model.raids, "queue": model.town_queue,
		"vei": model.vei, "readout": model.readout(), "won": bool(model.hud.get("won", false)), "opening": _opening}
	var now_t := float(model.hud.get("t", 0.0))
	if NextLogic.restarted(_next_t, now_t):
		_next = {}
	_next_t = now_t
	_next = NextLogic.choose(inp, _next)
	var act := str(_next["action"].get("kind", "none")) != "none"
	var text := str(_next["text"]) + (("   " + str(NextLogic.cfg()["hint"])) if act else "")
	if _objective.text != text:
		_objective.text = text
	# an opening ask with nothing to click (the valve) stays enabled: a disabled button would dim it
	_objective.disabled = not act and str(_next["rule"]) != NextLogic.OPENING
	_objective.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if act else Control.CURSOR_ARROW
	if str(_next["rule"]) != NextLogic.OPENING:
		set_opening_pulse(0.0)
	inp["margins"] = model.margins
	var quiet := NextLogic.quiet(inp, str(_next["rule"]))
	if quiet:
		_leave.text = NextLogic.leave_text(inp)
	_leave.visible = quiet
	_leave_plate.visible = quiet


## The opening's first-30-seconds ask (task 10): `text` on the strip, clicking acts on `target`
## (a fort id, "vei", "queue" or "slab", as the away panel's lines), over every rule. "" clears it.
func set_opening_ask(text: String, target: String) -> void:
	_opening = {"text": text, "target": target}
	_refresh_next()
	_relayout()


## The opening's pulse on the strip's plate while an ask is up: its colour leans toward undead by
## `level` x opening.plate_tint (1 held steady under reduced motion, the beat's wave otherwise).
func set_opening_pulse(level: float) -> void:
	var c := MapHud.plate_color()
	_obj_plate.color = c.lerp(Palette.c("undead", c.a), float(OpeningLogic.cfg()["plate_tint"]) * level) if level > 0.0 else c


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
		_sit_toast()
		_toast_t -= delta
		_toast.modulate.a = clampf(_toast_t / float(MapLogic.cfg()["toast_fade_s"]), 0.0, 1.0)


## A hover hint on the bottom line ("" restores the default).
func set_hover_hint(text: String) -> void:
	_hint.text = text if text != "" else _hint_default


## Puts the toast under the Relish chip's bottom edge (the HUD's inset when there is no chip).
func _sit_toast() -> void:
	var bottom := chip.position.y + chip.size.y if chip != null and is_instance_valid(chip) else 0.0
	_toast.offset_top = HudLogic.toast_top(bottom, _last_inset, float(MapLogic.cfg()["toast_gap_px"]))


func show_toast(msg: String) -> void:
	_toast.text = msg
	_sit_toast()
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
			if not ev.get("won", false):  # a win is the victory set piece's (MapSetpieces)
				show_toast("She threw the horde back. The factory must grow.")


## The victory line: the victory set piece shows it when every lane in the realm has stopped.
func show_victory() -> void:
	_victory.text = "VEI HAS DROWNED IN THE DEAD\nThe realm is quiet. The factory hums on."
	_victory.visible = true
