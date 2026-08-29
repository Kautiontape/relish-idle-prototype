extends Control
## COVINGTON — Relish's home town, the factory that never sleeps.
## Standalone scene: setup(seed) in, finished(result) out, exactly once.
## The yard (left) is a purely presentational diorama; the sidebar (right) is
## where the player reallocates the undead workforce, builds arcana, and heads
## back to the realm. The live economy ticks in the Game autoload the whole
## time, so resources shown here are the frozen seed minus local spends only.

signal finished(result: Dictionary)

const TownYardScript := preload("res://scripts/town/town_yard.gd")

const COL_BG := Color("#0C0C0E")
const COL_PANEL := Color("#141417")
const COL_SIDEBAR := Color("#0F0F13")
const COL_BORDER := Color("#2A2A30")
const COL_TEXT := Color("#E8E8EC")
const COL_DIM := Color("#8888A0")
const COL_AMBER := Color("#FFD000")
const COL_GREEN := Color("#39FF9E")
const COL_VIOLET := Color("#C04CFF")
const COL_ORANGE := Color("#FF6A2B")
const COL_GREY := Color("#6E6A7E")

var logic: TownLogic = null
var yard = null  # town_yard.gd instance (untyped: script-defined API)
var seed_in := {}
var _setup_done := false
var _finished := false

# UI refs
var _scroll: ScrollContainer
var _res_label: RichTextLabel
var _idle_label: Label
var _count_labels := {}          # task -> Label
var _minus_btns := {}
var _plus_btns := {}
var _row_panels := {}            # task -> Control (scroll/flash targets)
var _gather_opt: OptionButton
var _btn_slab: Button
var _btn_vat: Button
var _btn_station: Button
var _btn_craft: Button
var _btn_forge: Button
var _sim_opt: OptionButton
var _craft_row: Control
var _arcana: RichTextLabel
var _return_btn: Button


# ------------------------------------------------------------------ contract -
func _ready() -> void:
	_build_ui()
	if not _setup_done and get_tree().current_scene == self:
		setup(demo_seed())
	_standalone_check.call_deferred()


func _standalone_check() -> void:
	# change_scene_to_file can assign current_scene around _ready; re-check once
	# the tree has settled so running this scene directly always self-seeds.
	if not _setup_done and get_tree().current_scene == self:
		setup(demo_seed())


func setup(seed_data: Dictionary) -> void:
	_setup_done = true
	seed_in = seed_data.duplicate(true)
	logic = TownLogic.new()
	logic.setup(seed_in, _cfg())
	yard.bind(logic, seed_in, _cfg())
	_fill_fort_options()
	_refresh()


func demo_seed() -> Dictionary:
	# Mid-game snapshot so a standalone run shows every system working at once
	# (crews on all tasks, a vat pod, the sim station, a returning convoy).
	return {
		"town": {"slabs": 2, "vats": 1, "sim_stations": 1, "forge_level": 1, "trade_level": 0},
		"assignments": {"trade": 2, "forge": 1, "jobs": 2, "gather": 2, "slab": 1},
		"res": {"gold": 120.0, "materials": 64.0, "bodies": 9.0, "townsfolk": 12.0},
		"army": {"soldier": 14, "elite": 2},
		"idle_undead": 4, "quality": 1.45, "green_towns": 1,
		"gather": {"target": "vespers", "phase": "back", "eta": 6.0, "load": 11.0},
		"fort_ids": ["ashgate", "old-sluice", "greywall", "vespers", "chime-fort",
			"lantern-keep", "hollow-redoubt", "pale-bastion", "mourners-gate",
			"the-stair", "whitecross", "sable-hold"],
		"simulacra": [{"fort_id": "greywall", "charges": 182.0, "rate": 3.0}],
	}


func _cfg() -> Dictionary:
	return ConfigDb.data.get("town", {})


func _copy(key: String, def := "") -> String:
	return str((_cfg().get("copy", {}) as Dictionary).get(key, def))


func _copy_map(key: String) -> Dictionary:
	return (_cfg().get("copy", {}) as Dictionary).get(key, {})


func _fort_name(id: String) -> String:
	for f in (ConfigDb.data.get("world", {}) as Dictionary).get("forts", []):
		if str(f.get("id", "")) == id:
			return str(f.get("name", id))
	return id.replace("-", " ").capitalize()


# ------------------------------------------------------------------ UI build -
func _build_ui() -> void:
	# Full-rect anchors resolve against the viewport even under a plain-Node
	# parent (Main), so no manual sizing is needed.
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.color = COL_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var split := HBoxContainer.new()
	split.set_anchors_preset(Control.PRESET_FULL_RECT)
	split.add_theme_constant_override("separation", 0)
	add_child(split)

	yard = TownYardScript.new()
	yard.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	yard.size_flags_stretch_ratio = 0.58
	yard.station_clicked.connect(_on_station_clicked)
	split.add_child(yard)

	var sidebar := PanelContainer.new()
	sidebar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sidebar.size_flags_stretch_ratio = 0.42
	var sb_style := StyleBoxFlat.new()
	sb_style.bg_color = COL_SIDEBAR
	sb_style.border_color = COL_BORDER
	sb_style.border_width_left = 1
	sb_style.content_margin_left = 14.0
	sb_style.content_margin_right = 14.0
	sb_style.content_margin_top = 10.0
	sb_style.content_margin_bottom = 10.0
	sidebar.add_theme_stylebox_override("panel", sb_style)
	split.add_child(sidebar)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	sidebar.add_child(col)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(_scroll)

	var stack := VBoxContainer.new()
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.add_theme_constant_override("separation", 8)
	_scroll.add_child(stack)

	stack.add_child(_build_header())
	stack.add_child(_build_assignments())
	stack.add_child(_build_build())
	stack.add_child(_build_arcana())
	col.add_child(_build_foot())


func _build_header() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	var title := Label.new()
	title.text = "COVINGTON"
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", COL_TEXT)
	box.add_child(title)
	var flavor := Label.new()
	flavor.text = _copy("flavor", "The factory. It never sleeps.")
	flavor.add_theme_font_size_override("font_size", 12)
	flavor.add_theme_color_override("font_color", COL_DIM)
	box.add_child(flavor)
	_res_label = RichTextLabel.new()
	_res_label.bbcode_enabled = true
	_res_label.fit_content = true
	_res_label.scroll_active = false
	_res_label.add_theme_font_size_override("normal_font_size", 13)
	box.add_child(_res_label)
	return box


func _build_assignments() -> Control:
	var body := _section("ASSIGNMENTS — the undead workforce")
	_idle_label = Label.new()
	_idle_label.add_theme_font_size_override("font_size", 15)
	_idle_label.add_theme_color_override("font_color", COL_GREEN)
	body.add_child(_idle_label)
	var names: Dictionary = _copy_map("task_names")
	for task in TownLogic.TASKS:
		body.add_child(_assign_row(task, str(names.get(task, task.capitalize()))))
	# gather destination picker
	var grow := HBoxContainer.new()
	grow.add_theme_constant_override("separation", 6)
	var glabel := Label.new()
	glabel.text = "gather from:"
	glabel.add_theme_font_size_override("font_size", 11)
	glabel.add_theme_color_override("font_color", COL_DIM)
	grow.add_child(glabel)
	_gather_opt = OptionButton.new()
	_gather_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_gather_opt.add_theme_font_size_override("font_size", 11)
	_gather_opt.item_selected.connect(_on_gather_selected)
	grow.add_child(_gather_opt)
	body.add_child(grow)
	return body.get_parent()


func _assign_row(task: String, display: String) -> Control:
	var wrap := PanelContainer.new()
	var clear := StyleBoxEmpty.new()
	clear.content_margin_top = 1.0
	clear.content_margin_bottom = 1.0
	wrap.add_theme_stylebox_override("panel", clear)
	_row_panels[task] = wrap

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	wrap.add_child(row)

	var name_l := Label.new()
	name_l.text = display
	name_l.custom_minimum_size = Vector2(104, 0)
	name_l.add_theme_font_size_override("font_size", 13)
	name_l.add_theme_color_override("font_color", COL_TEXT)
	row.add_child(name_l)

	var minus := Button.new()
	minus.text = "-"
	minus.custom_minimum_size = Vector2(26, 26)
	minus.focus_mode = Control.FOCUS_NONE
	_style_button(minus)
	minus.pressed.connect(func():
		if logic != null and logic.unassign(task):
			_refresh())
	_minus_btns[task] = minus
	row.add_child(minus)

	var count := Label.new()
	count.custom_minimum_size = Vector2(26, 0)
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	count.add_theme_font_size_override("font_size", 14)
	count.add_theme_color_override("font_color", COL_GREEN)
	_count_labels[task] = count
	row.add_child(count)

	var plus := Button.new()
	plus.text = "+"
	plus.custom_minimum_size = Vector2(26, 26)
	plus.focus_mode = Control.FOCUS_NONE
	_style_button(plus)
	plus.pressed.connect(func():
		if logic != null and logic.assign(task):
			_refresh())
	_plus_btns[task] = plus
	row.add_child(plus)

	var fx := Label.new()
	fx.text = str(_copy_map("effects").get(task, ""))
	fx.tooltip_text = fx.text
	fx.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fx.clip_text = true
	fx.add_theme_font_size_override("font_size", 10)
	fx.add_theme_color_override("font_color", COL_DIM)
	row.add_child(fx)
	return wrap


func _build_build() -> Control:
	var body := _section("BUILD")
	var blurbs: Dictionary = _copy_map("blurbs")

	_btn_slab = _build_btn(body, str(blurbs.get("slab", "")), func():
		if logic != null and logic.buy_slab():
			_refresh())
	_row_panels["build_slab"] = _btn_slab

	_btn_vat = _build_btn(body, str(blurbs.get("vat", "")), func():
		if logic != null and logic.buy_vat():
			_refresh())
	_row_panels["vats"] = _btn_vat

	_btn_station = _build_btn(body, str(blurbs.get("sim_station", "")), func():
		if logic != null and logic.buy_station():
			_refresh())

	# craft simulacrum: button + fort picker on one row
	_craft_row = HBoxContainer.new()
	_craft_row.add_theme_constant_override("separation", 6)
	_btn_craft = Button.new()
	_btn_craft.focus_mode = Control.FOCUS_NONE
	_btn_craft.add_theme_font_size_override("font_size", 12)
	_style_button(_btn_craft)
	_btn_craft.pressed.connect(func():
		var idx := _sim_opt.selected
		if logic != null and idx >= 0 and logic.craft_simulacrum(str(_sim_opt.get_item_metadata(idx))):
			_refresh())
	_craft_row.add_child(_btn_craft)
	_sim_opt = OptionButton.new()
	_sim_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sim_opt.add_theme_font_size_override("font_size", 11)
	_craft_row.add_child(_sim_opt)
	body.add_child(_craft_row)
	body.add_child(_blurb(str(blurbs.get("simulacrum", ""))))
	_row_panels["sim"] = _craft_row

	_btn_forge = _build_btn(body, str(blurbs.get("forge", "")), func():
		if logic != null and logic.buy_forge():
			_refresh())
	return body.get_parent()


func _build_btn(body: VBoxContainer, blurb_text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_size_override("font_size", 12)
	_style_button(b)
	b.pressed.connect(cb)
	body.add_child(b)
	body.add_child(_blurb(blurb_text))
	return b


func _blurb(text: String) -> Label:
	var l := Label.new()
	l.text = "   " + text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", 10)
	l.add_theme_color_override("font_color", COL_DIM)
	return l


func _build_arcana() -> Control:
	var body := _section("ACTIVE ARCANA")
	_arcana = RichTextLabel.new()
	_arcana.bbcode_enabled = true
	_arcana.fit_content = true
	_arcana.scroll_active = false
	_arcana.add_theme_font_size_override("normal_font_size", 12)
	body.add_child(_arcana)
	return body.get_parent()


func _build_foot() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	_return_btn = Button.new()
	_return_btn.text = "RETURN TO THE REALM"
	_return_btn.custom_minimum_size = Vector2(0, 46)
	_return_btn.focus_mode = Control.FOCUS_NONE
	_return_btn.add_theme_font_size_override("font_size", 16)
	_style_button(_return_btn, true)
	_return_btn.pressed.connect(_on_return)
	box.add_child(_return_btn)
	var cap := Label.new()
	cap.text = _copy("live_caption", "(live totals tick in the realm)")
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cap.add_theme_font_size_override("font_size", 10)
	cap.add_theme_color_override("font_color", COL_DIM)
	box.add_child(cap)
	return box


## PanelContainer section with a dim uppercase title; returns the content VBox.
func _section(title: String) -> VBoxContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = COL_PANEL
	style.border_color = COL_BORDER
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.content_margin_left = 10.0
	style.content_margin_right = 10.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	panel.add_theme_stylebox_override("panel", style)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 4)
	panel.add_child(body)
	var t := Label.new()
	t.text = title
	t.add_theme_font_size_override("font_size", 11)
	t.add_theme_color_override("font_color", COL_DIM)
	body.add_child(t)
	return body


func _style_button(b: Button, accent := false) -> void:
	var mk := func(bg: Color, border: Color) -> StyleBoxFlat:
		var s := StyleBoxFlat.new()
		s.bg_color = bg
		s.border_color = border
		s.set_border_width_all(1)
		s.set_corner_radius_all(4)
		s.content_margin_left = 8.0
		s.content_margin_right = 8.0
		s.content_margin_top = 4.0
		s.content_margin_bottom = 4.0
		return s
	b.add_theme_stylebox_override("normal", mk.call(Color("#1B1B20"), COL_AMBER * Color(1, 1, 1, 0.6) if accent else COL_BORDER))
	b.add_theme_stylebox_override("hover", mk.call(Color("#232329"), COL_AMBER if accent else Color("#3A3A44")))
	b.add_theme_stylebox_override("pressed", mk.call(Color("#2A2A30"), COL_AMBER if accent else Color("#3A3A44")))
	b.add_theme_stylebox_override("disabled", mk.call(Color("#141417"), Color("#222228")))
	b.add_theme_color_override("font_color", COL_AMBER if accent else COL_TEXT)
	b.add_theme_color_override("font_hover_color", COL_AMBER if accent else Color.WHITE)
	b.add_theme_color_override("font_pressed_color", COL_AMBER if accent else Color.WHITE)
	b.add_theme_color_override("font_disabled_color", Color("#55556A"))


# ------------------------------------------------------------------ dropdowns
func _fill_fort_options() -> void:
	_gather_opt.clear()
	_gather_opt.add_item("auto (richest)")
	_gather_opt.set_item_metadata(0, "")
	var select := 0
	for i in logic.fort_ids.size():
		var id: String = str(logic.fort_ids[i])
		_gather_opt.add_item(_fort_name(id))
		_gather_opt.set_item_metadata(i + 1, id)
		if id == logic.gather_target:
			select = i + 1
	_gather_opt.select(select)

	_sim_opt.clear()
	for i in logic.fort_ids.size():
		var id: String = str(logic.fort_ids[i])
		_sim_opt.add_item(_fort_name(id))
		_sim_opt.set_item_metadata(i, id)
	if _sim_opt.item_count > 0:
		_sim_opt.select(0)


func _on_gather_selected(idx: int) -> void:
	logic.gather_target = str(_gather_opt.get_item_metadata(idx))


# ------------------------------------------------------------------ refresh --
func _refresh() -> void:
	if logic == null:
		return
	var res: Dictionary = seed_in.get("res", {})
	var army: Dictionary = seed_in.get("army", {})
	_res_label.text = "[color=#FFD000]gold %.0f[/color]  ·  [color=#E8E8EC]materials %.0f[/color]  ·  [color=#6E6A7E]bodies %.0f[/color]  ·  [color=#FF6A2B]townsfolk %.0f[/color]  ·  [color=#39FF9E]q %.2f[/color]  ·  [color=#8888A0]army %d / %de[/color]" % [
		logic.display_funds("gold"), logic.display_funds("materials"),
		float(res.get("bodies", 0.0)), float(res.get("townsfolk", 0.0)),
		logic.quality(), int(army.get("soldier", 0)), int(army.get("elite", 0))]

	_idle_label.text = "Idle undead: %d" % logic.idle_undead
	for task in TownLogic.TASKS:
		(_count_labels[task] as Label).text = str(int(logic.assignments[task]))
		(_minus_btns[task] as Button).disabled = int(logic.assignments[task]) <= 0
		(_plus_btns[task] as Button).disabled = logic.idle_undead <= 0

	_btn_slab.text = "Slab +1  —  %.0f gold" % logic.slab_cost()
	_btn_slab.disabled = not logic.can_afford(logic.slab_cost(), 0.0)
	var vc := logic.vat_cost()
	_btn_vat.text = "Clone Vat  —  %.0f gold, %.0f mat   (pods: %d)" % [
		float(vc["gold"]), float(vc["materials"]), int(logic.town["vats"])]
	_btn_vat.disabled = not logic.can_afford(float(vc["gold"]), float(vc["materials"]))
	var sc := logic.station_cost()
	if logic.station_built():
		_btn_station.text = "Simulacrum Station  —  built"
		_btn_station.disabled = true
	else:
		_btn_station.text = "Simulacrum Station  —  %.0f gold, %.0f mat" % [
			float(sc["gold"]), float(sc["materials"])]
		_btn_station.disabled = not logic.can_afford(float(sc["gold"]), float(sc["materials"]))
	_btn_craft.text = "Craft Simulacrum  —  %.0f mat" % logic.sim_cost()
	_btn_craft.disabled = not logic.can_craft_sim()
	_btn_forge.text = "Forge upgrade (L%d)  —  %.0f mat" % [
		int(logic.town["forge_level"]) + 1, logic.forge_cost()]
	_btn_forge.disabled = not logic.can_afford(0.0, logic.forge_cost())

	_refresh_arcana()


func _refresh_arcana() -> void:
	var lines: Array[String] = []
	for s in seed_in.get("simulacra", []):
		lines.append("[color=#C04CFF]%s[/color] · %.0f charges left" % [
			_fort_name(str(s.get("fort_id", "?"))), float(s.get("charges", 0.0))])
	for s in logic.deploys:
		lines.append("[color=#C04CFF]-> %s[/color] · %.0f charges [color=#8888A0](deploying on return)[/color]" % [
			_fort_name(str(s.get("fort_id", "?"))), float(s.get("charges", 0.0))])
	lines.append("clone vats: [color=#E8E8EC]%d pod(s)[/color]" % int(logic.town["vats"]))
	var g: Dictionary = seed_in.get("gather", {})
	var phase := str(g.get("phase", "idle"))
	if phase == "out":
		lines.append("convoy: out to [color=#E8E8EC]%s[/color]" % _fort_name(str(g.get("target", "?"))))
	elif phase == "back":
		lines.append("convoy: returning · load %.0f bodies" % float(g.get("load", 0.0)))
	else:
		lines.append("convoy: idle at camp")
	_arcana.text = "[color=#8888A0]" + "[/color]\n[color=#8888A0]".join(lines) + "[/color]"


# ------------------------------------------------------------------ yard link
func _on_station_clicked(task: String) -> void:
	var target: Control = _row_panels.get(task, null)
	if target == null:
		return
	_scroll.ensure_control_visible(target)
	target.modulate = Color(0.55, 1.0, 0.75)
	var tw := create_tween()
	tw.tween_property(target, "modulate", Color.WHITE, 0.9)


# ------------------------------------------------------------------ exit -----
func _on_return() -> void:
	if _finished or logic == null:
		return
	_finished = true
	var r := logic.result()
	_return_btn.disabled = true
	_return_btn.text = "— DEPARTED —"
	print("[covington] result: ", JSON.stringify(r))
	finished.emit(r)
