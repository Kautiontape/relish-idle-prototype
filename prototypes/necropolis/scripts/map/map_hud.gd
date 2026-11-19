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


## A bar word that explains itself on hover: a Label that draws a thin dotted underline under its text
## once it carries a tooltip (HudLogic.apply_tip), in a dim key, so the hover is discoverable and calm.
## It keeps the glossary line in tooltip_text, but Godot's own popup is switched off for it (_get_tooltip
## returns ""): the hud draws the plate itself, in the place HudLogic.tip_rect picks (MapHud._show_tip).
class TipWord extends Label:
	func _get_tooltip(_at_position: Vector2) -> String:
		return ""

	func _draw() -> void:
		if tooltip_text == "":
			return
		var cc: Dictionary = MapLogic.cfg()["clarity"]
		var col := Palette.c("text_dim", float(cc["tip_underline_alpha"]))
		var dot := float(cc["tip_underline_dot_px"])
		var step := dot + float(cc["tip_underline_gap_px"])
		var y := size.y - 1.0
		var x := 0.0
		while x < size.x:
			draw_rect(Rect2(x, y, minf(dot, size.x - x), 1.0), col)
			x += step

## The plate of a bar word's tooltip: the same look as MapUi.tooltip_theme's (MapUi.plate_box, the HUD's
## tooltip text colour and size), drawn at exactly its size and position (set by MapHud._show_tip), its
## text wrapped by the same call that measured it. It takes no mouse, so it never steals the hover.
class TipPlate extends Control:
	var text := ""
	var font: Font
	var font_size := 14
	var pad := 6
	var text_w := 0.0
	var color := Color.WHITE
	var box: StyleBox

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		z_as_relative = false
		z_index = int(MapLogic.cfg()["clarity"]["tooltip"]["z_index"])
		visible = false

	func _draw() -> void:
		draw_style_box(box, Rect2(Vector2.ZERO, size))
		draw_multiline_string(font, Vector2(pad, pad + font.get_ascent(font_size)), text, HORIZONTAL_ALIGNMENT_LEFT, text_w, font_size, -1, color,
			TextServer.BREAK_WORD_BOUND | TextServer.BREAK_MANDATORY)

var valve: Control  # the HUD's plates a bar tooltip keeps clear of (set by world_map): the valve, the legend, the open card
var legend: Control
var card: Control
var nodes: MapNodes  # set by world_map: Vei's readout and the other map labels a bar tooltip keeps clear of
var cam: Camera2D  # set by world_map: puts those labels in screen px
var _placer := TipPlacer.new()  # the shown plate's last placement (headless-tested)
var _plate_rects: Array = []  # the bar, strip, goal and leave line's rects as _relayout last set them
var _ro_key: Array = []  # what the cached map readouts below were measured for
var _ro_rects: Array = []  # the map's readouts in screen px
var _tip_word: Label  # the bar word the cursor rests on
var _tip_wait := 0.0  # seconds until its plate shows
var _tip_plate: TipPlate
var _tip_size := Vector2.ZERO  # the shown plate's size before any shrink to the viewport
var _bar: VBoxContainer  # one HBoxContainer row per HudLogic.wrap_rows row
var _cells: Array = []  # the bar items (a box per stream, then the status box), in order
var _row_sig := ""
var _bar_plate: ColorRect
var _obj_plate: ColorRect
var _items: Array = []  # [{box, name, rate, stock, cap}] per stream, built on the first read
var _odds: Label
var _odds_name: Label  # the ODDS word, whose tip follows whether the game reports backups
var _odds_tip := ""  # the tip id on _odds_name now, so a refresh re-applies only on a change
var _tips_won := false  # the won the stream words' tips were set for (HudLogic.tip: MINT's won line), re-applied on a flip
var _sign: Label
var _drain: Label
var _vei_group: Array = []  # YOUR ODDS / STRAIN / DRAIN's six labels
var _tithe: Label
var _speed_tag: Label
var _cue: Label  # the bar's last cell: the key to its words on first view, then the hover cue (HudLogic.bar_cue)
var _objective: Button
var _goal: Label  # the game's goal under the strip, at every tier until the game is won (HudLogic.goal_shown)
var _goal_plate: ColorRect
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
var _bone_warn: BoneWarn  # BONE's stall warning, its hold on this HUD's real clock (built with the bar)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)  # also sizes it: anchored labels need a real parent rect
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cfg := MapLogic.cfg()
	var pos: Array = cfg["topbar_pos_px"]
	# darkening plates behind the bar and the objective: the map's brightest content may sit under them
	_bar_plate = _plate()
	_obj_plate = _plate()
	_leave_plate = _plate()
	_goal_plate = _plate()
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
	_goal = _label(int(cfg["clarity"]["goal_size_px"]), "text")
	MapType.style_label(_goal, "text", int(cfg["clarity"]["goal_size_px"]))
	_goal.text = HudLogic.goal_text()
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
	_tip_plate = TipPlate.new()
	add_child(_tip_plate)
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
	# Your goal, under the strip while no fort has been taken; its room is in the inset only then
	var goal_on := HudLogic.goal_shown(model.hud)
	_goal.visible = goal_on
	_goal_plate.visible = goal_on
	if goal_on:
		var gsz := _goal.get_combined_minimum_size()
		_goal.position = Vector2(_bar.position.x, inset + float(MapLogic.cfg()["clarity"]["goal_gap_px"]))
		_goal.size = gsz
		_goal_plate.position = Vector2(0.0, _goal.position.y)
		_goal_plate.size = Vector2(_goal.position.x + gsz.x + pad, gsz.y + pad)
		inset = _goal_plate.position.y + _goal_plate.size.y
	# The leave line's room is always kept under the strip, shown or not: toggling the line (a hold
	# starting or ending, a tithe warning) never changes the inset, so no refit and no chip jump.
	var lsz := _leave.get_combined_minimum_size()
	_leave.position = Vector2(_bar.position.x, inset)
	_leave.size = lsz
	_leave_plate.position = Vector2(0.0, inset)
	_leave_plate.size = Vector2(_leave.position.x + lsz.x + pad, lsz.y + pad)
	_leave_rect = Rect2(0.0, inset, _obj_plate.size.x, lsz.y + pad)
	inset += _leave_rect.size.y
	_plate_rects = [Rect2(_bar_plate.position, _bar_plate.size), Rect2(_obj_plate.position, _obj_plate.size), _leave_rect]
	if goal_on:
		_plate_rects.append(Rect2(_goal_plate.position, _goal_plate.size))
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


## The screen y the bottom bars start at: the speed row (its y from config) or the hint line (the
## viewport's bottom less hint_bottom_px and its own height), whichever is higher. A callout stays above it.
func bottom_top() -> float:
	var hint_top := get_viewport_rect().size.y - float(MapLogic.cfg()["hint_bottom_px"]) - _hint.size.y
	return minf(_speed_row.position.y, hint_top)


## The right edge (screen px) of the HUD's plates at the top left: the bar, the strip, the goal and the
## leave line. The card may rise above `top_inset` only where this stays clear of it.
func plates_right() -> float:
	_relayout()
	var r := maxf(_bar_plate.size.x, _obj_plate.size.x)
	if _goal_plate.visible:
		r = maxf(r, _goal_plate.size.x)
	return maxf(r, _leave_rect.size.x)


## The objective strip's plate (screen px): the default fit keeps the forts and Vei off it.
func strip_rect() -> Rect2:
	_relayout()
	var r := Rect2(_obj_plate.position, _obj_plate.size)
	return r.merge(Rect2(_goal_plate.position, _goal_plate.size)) if _goal_plate.visible else r


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
		var parts := {"box": box, "name": _bar_label(box, true), "rate": _bar_label(box), "stock": _bar_label(box), "cap": _bar_label(box)}
		MapType.style_label(parts["name"])
		HudLogic.apply_tip(parts["name"], str(it["id"]))
		MapType.style_rate(parts["rate"])
		MapType.style_mass(parts["stock"], "text_dim", MapType.size_of("size_stock"))
		MapType.style_label(parts["cap"], "text", MapType.size_of("size_stock"))
		if str(it["id"]) == "bone":  # the pits-first warning rides beside BONE, in words (HudLogic.bone_line)
			parts["warn"] = _bar_label(box)
			MapType.style_label(parts["warn"], str(cfg["bone_line"]["key"]))
			(parts["warn"] as Label).visible = false
			_bone_warn = BoneWarn.new(parts["warn"] as Label)
		_items.append(parts)
	var status := HBoxContainer.new()
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status.add_theme_constant_override("separation", int(cfg["topbar_item_gap_px"]))
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(float(cfg["topbar_group_gap_px"]), 0.0)
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status.add_child(spacer)
	_cells.append(status)
	var odds_name := _bar_label(status, true)
	MapType.style_label(odds_name)
	odds_name.text = str(cfg["cards"]["vei_odds_label"])
	HudLogic.apply_tip(odds_name, "odds")
	_odds_name = odds_name
	_odds_tip = "odds"
	_odds = _bar_label(status)
	MapType.style_mass(_odds)
	# the ▲/▼ is the backlog's sign, labelled as her strain: the odds are mostly time and can climb on a ▼
	var strain_name := _bar_label(status, true)
	MapType.style_label(strain_name)
	strain_name.text = str(cfg["strain_label"])
	HudLogic.apply_tip(strain_name, "strain")
	_sign = _bar_label(status)
	MapType.style_mass(_sign)
	var drain_name := _bar_label(status, true)
	MapType.style_label(drain_name)
	drain_name.text = str(cfg["drain_label"])
	HudLogic.apply_tip(drain_name, "drain")
	_drain = _bar_label(status)
	MapType.style_mass(_drain)
	_vei_group = [odds_name, _odds, strain_name, _sign, drain_name, _drain]  # hidden once won (HudLogic.vei_readout_shown)
	_tithe = _bar_label(status)  # Vei's tithe telegraph; hidden while it has nothing to say
	MapType.style_label(_tithe)
	_tithe.visible = false
	_speed_tag = _bar_label(status)
	MapType.style_label(_speed_tag, "select")
	# the key to the bar's words on first view (V-I1 item 2), else the cue that they explain themselves on
	# hover: the bar's last cell, so it follows the status on the second row (wrap_rows puts it on its own
	# row only when it does not fit there)
	var cue := Label.new()
	cue.mouse_filter = Control.MOUSE_FILTER_IGNORE
	MapType.style_label(cue, str(cfg["clarity"]["hover_cue_key"]), int(cfg["clarity"]["hover_cue_size_px"]))
	cue.text = HudLogic.hover_cue()
	_cue = cue
	_cells.append(cue)


func _bar_label(parent: Node, word := false) -> Label:
	var l: Label = TipWord.new() if word else Label.new()
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	if word:  # the words that explain themselves: their plate shows after a short rest, hides on leaving
		l.mouse_entered.connect(_tip_enter.bind(l))
		l.mouse_exited.connect(_tip_leave.bind(l))
	return l


func _tip_enter(word: Label) -> void:
	_tip_word = word
	_tip_wait = float(MapLogic.cfg()["clarity"]["tooltip"]["delay_s"])


func _tip_leave(word: Label) -> void:
	if _tip_word == word:
		_hide_tip()


func _hide_tip() -> void:
	_tip_word = null
	_tip_plate.visible = false
	_placer.reset()


## The HUD's text plates a bar tooltip keeps clear of, in screen px: the bar, the strip, the goal (shown) and
## the leave line's room as _relayout last cached them (no layout pass per tick), and the Relish chip, legend
## and valve while they show.
func _tip_plates() -> Array:
	var out: Array = _plate_rects.duplicate()
	for c in [chip, legend, valve]:
		if c != null and is_instance_valid(c) and (c as Control).is_visible_in_tree():
			out.append((c as Control).get_global_rect())
	return out


## The map's own text (Vei's ODDS readout and name, Covington's labels) in screen px, measured again only when
## the camera, the viewport, the model or the open card changed (the readouts are cached between).
func _tip_readouts(card_r: Rect2, vp: Vector2) -> Array:
	if nodes == null or cam == null or not is_instance_valid(nodes) or not is_instance_valid(cam):
		return []
	# readout_rects() is built from the nodes' own ctx (refreshed in their _on_refresh, zoom past its redraw eps,
	# panel synced in their _process: all a frame behind this tick), so the key carries the rev the ctx was last
	# refreshed at (nodes.refresh_rev(), not the model's own rev, which moves first) and those too, or the cache could stay a step stale.
	var key := [cam.position, cam.zoom.x, vp, nodes.refresh_rev(), card_r, nodes.ctx.zoom, NodeLogic.panel_key(nodes.ctx.panel)]
	if key != _ro_key:
		_ro_key = key
		_ro_rects = nodes.readout_rects().map(func(r: Rect2): return HudLogic.world_to_screen(r, cam.position, cam.zoom.x, vp))
	return _ro_rects


## Shows the resting word's glossary line on its own plate: sized by the same wrap call that draws it, placed
## by HudLogic.tip_rect (clear of the HUD's plates and the open card), so what shows is where that put it.
func _show_tip() -> void:
	var st := HudLogic.tooltip_style()
	var pad := int(st["pad"])
	var font := get_theme_default_font()
	var fs := int(st["size"])
	var flags := TextServer.BREAK_WORD_BOUND | TextServer.BREAK_MANDATORY
	var limit := float(MapLogic.cfg()["clarity"]["tooltip"]["max_w_px"]) - pad * 2.0
	var text_sz := font.get_multiline_string_size(_tip_word.tooltip_text, HORIZONTAL_ALIGNMENT_LEFT, limit, fs, -1, flags)
	_tip_size = text_sz + Vector2(pad, pad) * 2.0
	var p := _tip_plate
	p.text = _tip_word.tooltip_text
	p.font = font
	p.font_size = fs
	p.pad = pad
	p.color = st["text"]
	p.box = MapUi.plate_box(float(MapLogic.cfg()["clarity"]["tooltip"]["plate_alpha"]), pad)
	_placer.reset()
	_relayout()  # the plates' cache is fresh as it first shows; the ticks after only read it
	_place_tip()


## Puts the shown plate where the TipPlacer says, only when it must move: the card opening or closing, the HUD
## re-laying out, the map's readouts moving. Called every tick while it shows.
func _place_tip() -> void:
	var open_card := card != null and is_instance_valid(card) and card.is_visible_in_tree()
	var word := Rect2(_tip_word.global_position, _tip_word.size)
	var card_r: Rect2 = card.get_global_rect() if open_card else Rect2()
	var vp := get_viewport_rect().size
	var res := _placer.place(word, _tip_size, _tip_plates(), card_r, vp, _tip_readouts(card_r, vp))
	if not res["moved"]:
		return
	var r: Rect2 = res["rect"]
	var p := _tip_plate
	p.text_w = r.size.x - p.pad * 2.0
	p.position = r.position - global_position
	p.size = r.size
	p.visible = true
	p.queue_redraw()


## Sets the bar's text from the model's hud. A no-op until the model has a new rev.
func refresh(force := false) -> void:
	if not force and model.rev == _rev:
		return
	_rev = model.rev
	var hud := model.hud
	var items := HudLogic.rate_items(hud)
	if _items.is_empty():
		_build_bar(items)
	var retip := bool(hud.get("won", false)) != _tips_won  # built with the plain tips; a won game's MINT reads its won line
	_tips_won = bool(hud.get("won", false))
	for i in mini(items.size(), _items.size()):
		var it: Dictionary = items[i]
		var w: Dictionary = _items[i]
		if retip:
			HudLogic.apply_tip(w["name"], str(it["id"]), hud)
		(w["name"] as Label).text = it["label"]
		(w["rate"] as Label).text = it["rate_text"]
		(w["stock"] as Label).text = it["stock_text"]
		(w["cap"] as Label).text = it["cap_mark"]
		if w.has("warn"):  # held 10 s and its room kept once shown, so it never re-wraps the bar or moves the camera
			_bone_warn.set_line(HudLogic.bone_line(model.mill, model.queue_stall, _building_names()))
	var ro := model.readout()
	var st := HudLogic.status(ro)
	_odds.text = st["odds_text"]
	var odds_tip := HudLogic.odds_tip_id(int(ro["backups"]))
	if odds_tip != _odds_tip:
		_odds_tip = odds_tip
		HudLogic.apply_tip(_odds_name, odds_tip)
	_sign.text = st["sign_text"]
	_sign.add_theme_color_override("font_color", Palette.c(_sign_key(int(st["sign"]))))
	_drain.text = st["drain_text"]
	var vei_on := HudLogic.vei_readout_shown(hud)
	for l in _vei_group:
		(l as Control).visible = vei_on
	var tl := HudLogic.tithe_line(model.vei.get("tithe", {}), _fort_names())
	if _tithe.text != tl["text"]:  # the ETA ticks with the model's rev; set only on a change
		_tithe.text = tl["text"]
		_tithe.visible = tl["text"] != ""
	_speed_tag.text = HudLogic.speed_text(hud)
	var cue_text := HudLogic.bar_cue(hud)
	if _cue != null and _cue.text != cue_text:
		_cue.text = cue_text
	_refresh_next()
	_wrap_cells()
	_relayout()
	_relayout.call_deferred()


## building id -> its label (configs/buildings_view.json), for the bone warning's queue head.
func _building_names() -> Dictionary:
	var names := {}
	var view: Dictionary = ConfigDb.data.get("buildings_view", {})
	for id in view:
		names[id] = str(view[id].get("label", id.capitalize()))
	return names


func _fort_names() -> Dictionary:
	var names := {}
	for id in model.forts_by_id:
		names[id] = str(model.forts_by_id[id].get("name", id))
	return names


## Lays the bar's cells into rows by HudLogic.wrap_rows (the one wrapping rule), moving them only when the rows
## changed (HudLogic.place_rows keeps the row boxes and moves only the cells whose row changed).
func _wrap_cells() -> void:
	var cfg := MapLogic.cfg()
	var widths: Array = _cells.map(func(c): return (c as Control).get_combined_minimum_size().x)
	var rows := HudLogic.wrap_rows(widths, float(cfg["topbar_gap_px"]), float(cfg["topbar_max_w_px"]))
	if str(rows) == _row_sig:
		return
	_row_sig = str(rows)
	HudLogic.place_rows(_bar, _cells, rows, int(cfg["topbar_gap_px"]))


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
		"vei": model.vei, "readout": model.readout(), "won": bool(model.hud.get("won", false)), "opening": _opening, "place": model.next_place}
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
	var goal := HudLogic.goal_text(str(_next["rule"]) == NextLogic.DEFAULT)  # the standing strip already says line two
	if _goal.text != goal:
		_goal.text = goal
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
	if _bone_warn != null:  # every frame: a held warning runs out on time even while the model has no new rev (paused)
		_bone_warn.tick(delta)
	if _tip_word != null:  # a resting bar word: its plate after the delay, gone with the word
		if not is_instance_valid(_tip_word) or not _tip_word.is_visible_in_tree():
			_hide_tip()
		elif _tip_plate.visible:
			_place_tip()
		else:
			_tip_wait -= delta
			if _tip_wait <= 0.0:
				_show_tip()
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
	_victory.text = str(MapLogic.cfg().get("victory_text", ""))
	_victory.visible = true


## The victory line goes when the set piece ends (its END phase).
func hide_victory() -> void:
	_victory.visible = false
