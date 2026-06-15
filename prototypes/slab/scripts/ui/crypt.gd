class_name Crypt
extends Control
## The room Relish woke up in. Center: the Slab — place a form, its rune slots
## bloom by anatomy, slot remnants and watch the creature (and its Adjective
## Noun name) take shape, then Raise and name it. Corner: the bone pit (the
## floor that keeps you off zero). Corner: Vei's statue (placeholder nemesis).
## Everything not the build is faked or stubbed — this tests the FEEL of making
## a creature that's yours, plus the pit's lottery.

const SLAB_CENTER := Vector2(360, 470)
const STATS_SHORT := {
	"power": "Pow", "beef": "Bee", "speed": "Spd", "wits": "Wit",
	"charm": "Chm", "dread": "Drd", "magic": "Mag", "persistence": "Per",
}

var build := BuildState.new()
var preview: CreaturePreview
var rune_holder: Control
var name_label: Label
var combat_rect: ColorRect
var town_rect: ColorRect
var raise_btn: Button
var forms_box: HFlowContainer
var shelf_box: HFlowContainer
var scraps_label: Label
var pit_fill: ColorRect
var pit_label: Label
var pit_result: Label

var picker: Panel
var picker_list: VBoxContainer
var picker_title: Label
var _picking_slot := -1

var name_prompt: Panel
var name_edit: LineEdit
var vei_panel: Panel
var dbg_panel: Panel

var role_label: Label
var materials_panel: Panel
var materials_list: VBoxContainer
var confirm_panel: Panel
var confirm_label: Label
var _confirm_cb := Callable()
var _holding := false
var _hold_t := 0.0

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.065, 0.085)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	_build_slab_platform()
	preview = CreaturePreview.new()
	preview.custom_minimum_size = Vector2(420, 420)
	preview.size = Vector2(420, 420)
	preview.position = SLAB_CENTER - preview.size * 0.5
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(preview)

	rune_holder = Control.new()
	rune_holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	rune_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(rune_holder)

	_build_header()
	_build_raise_button()
	_build_pit()
	_build_statue()
	_build_bottom()
	_build_picker()
	_build_name_prompt()
	_build_materials()
	_build_confirm()
	_build_vei_panel()
	_build_debug()

	GameState.materials_changed.connect(_on_materials_changed)
	GameState.shelf_changed.connect(_rebuild_shelf)
	ConfigDb.value_changed.connect(func(_f, _k, _v): _refresh())  # debug tweaks apply live
	GameState.grant_raid_haul()  # start with something to build (the faked raid)
	_rebuild_forms()
	_rebuild_shelf()
	_refresh()

# ---- Static room dressing ----

func _build_slab_platform() -> void:
	var slab := Panel.new()
	slab.size = Vector2(300, 120)
	slab.position = SLAB_CENTER + Vector2(-150, 96)  # a plinth under the creature
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.16, 0.15, 0.19)
	sb.set_corner_radius_all(10)
	sb.border_color = Color(0.3, 0.28, 0.36)
	sb.set_border_width_all(2)
	slab.add_theme_stylebox_override("panel", sb)
	slab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(slab)

func _build_header() -> void:
	name_label = Label.new()
	name_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	name_label.position = Vector2(0, 96)
	name_label.size = Vector2(720, 44)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 34)
	name_label.add_theme_color_override("font_color", Color(0.78, 0.78, 0.85))
	add_child(name_label)

	var sub := Label.new()
	sub.position = Vector2(0, 140)
	sub.size = Vector2(720, 20)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 13)
	sub.add_theme_color_override("font_color", Color(0.5, 0.5, 0.6))
	sub.text = "THE CRYPT — place a form, slot remnants, hold to Raise"
	add_child(sub)

	# The verdict: what this build is FOR (role — good for X), live as you slot.
	role_label = Label.new()
	role_label.position = Vector2(20, 162)
	role_label.size = Vector2(680, 22)
	role_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	role_label.add_theme_font_size_override("font_size", 15)
	role_label.add_theme_color_override("font_color", Color(0.85, 0.78, 0.6))
	add_child(role_label)

	# Twin lean bar (combat | town), labeled so a stranger reads the trade-off.
	var clab := Label.new()
	clab.position = Vector2(150, 190)
	clab.add_theme_font_size_override("font_size", 11)
	clab.add_theme_color_override("font_color", Color(0.95, 0.5, 0.35))
	clab.text = "COMBAT"
	add_child(clab)
	var tlab := Label.new()
	tlab.position = Vector2(510, 190)
	tlab.size = Vector2(60, 16)
	tlab.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	tlab.add_theme_font_size_override("font_size", 11)
	tlab.add_theme_color_override("font_color", Color(0.5, 0.85, 0.5))
	tlab.text = "TOWN"
	add_child(tlab)
	var bar := HBoxContainer.new()
	bar.position = Vector2(150, 206)
	bar.size = Vector2(420, 12)
	bar.add_theme_constant_override("separation", 2)
	combat_rect = ColorRect.new()
	combat_rect.color = Color(0.95, 0.45, 0.3)
	combat_rect.custom_minimum_size = Vector2(0, 12)
	combat_rect.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	town_rect = ColorRect.new()
	town_rect.color = Color(0.5, 0.85, 0.5)
	town_rect.custom_minimum_size = Vector2(0, 12)
	town_rect.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(combat_rect)
	bar.add_child(town_rect)
	add_child(bar)

func _build_raise_button() -> void:
	raise_btn = Button.new()
	raise_btn.text = "✦ HOLD TO RAISE ✦"
	raise_btn.focus_mode = Control.FOCUS_NONE
	raise_btn.add_theme_font_size_override("font_size", 20)
	raise_btn.size = Vector2(260, 52)
	raise_btn.position = SLAB_CENTER + Vector2(-130, 222)
	# Press-and-hold: the creature fleshes in under a closing ring; release early
	# cancels. Deliberate, not a one-click — you watch it become itself.
	raise_btn.button_down.connect(_raise_begin)
	raise_btn.button_up.connect(_raise_release)
	add_child(raise_btn)

func _process(delta: float) -> void:
	if not _holding:
		return
	if not build.has_form():
		_raise_cancel()
		return
	_hold_t += delta
	var p := clampf(_hold_t / float(ConfigDb.v("slab", "raise_hold_time_s")), 0.0, 1.0)
	preview.reveal_boost = p
	preview.hold_progress = p
	if p >= 1.0:
		_raise_complete()

# ---- The bone pit (ossuary) ----

func _build_pit() -> void:
	var pit := Panel.new()
	pit.position = Vector2(16, 792)
	pit.size = Vector2(688, 92)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.12, 0.1, 0.1)
	sb.set_corner_radius_all(8)
	sb.border_color = Color(0.4, 0.25, 0.22)
	sb.set_border_width_all(2)
	pit.add_theme_stylebox_override("panel", sb)
	add_child(pit)

	var title := Label.new()
	title.position = Vector2(28, 798)
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color(0.85, 0.6, 0.5))
	title.text = "THE MAW — toss anything in"
	add_child(title)

	# Quality/fullness meter
	var meter_bg := ColorRect.new()
	meter_bg.color = Color(0.05, 0.04, 0.04)
	meter_bg.position = Vector2(28, 826)
	meter_bg.size = Vector2(258, 18)
	add_child(meter_bg)
	pit_fill = ColorRect.new()
	pit_fill.color = Color(0.9, 0.55, 0.2)
	pit_fill.position = Vector2(28, 826)
	pit_fill.size = Vector2(0, 18)
	add_child(pit_fill)
	pit_label = Label.new()
	pit_label.position = Vector2(28, 848)
	pit_label.add_theme_font_size_override("font_size", 12)
	pit_label.add_theme_color_override("font_color", Color(0.7, 0.6, 0.55))
	add_child(pit_label)

	# The Maw's face: a cauldron, lit warm.
	add_child(_icon("res://assets/icons/_maw.svg", Vector2(296, 816), Vector2(52, 52), Color(0.95, 0.7, 0.45)))

	var feed := Button.new()
	feed.text = "FEED scrap"
	feed.focus_mode = Control.FOCUS_NONE
	feed.add_theme_font_size_override("font_size", 12)
	feed.position = Vector2(356, 808)
	feed.size = Vector2(82, 30)
	feed.pressed.connect(func(): GameState.feed_ossuary())
	add_child(feed)

	var toss := Button.new()
	toss.text = "TOSS…"
	toss.focus_mode = Control.FOCUS_NONE
	toss.add_theme_font_size_override("font_size", 12)
	toss.position = Vector2(356, 846)
	toss.size = Vector2(82, 30)
	toss.pressed.connect(_open_materials)
	add_child(toss)

	var pull := Button.new()
	pull.text = "PULL"
	pull.focus_mode = Control.FOCUS_NONE
	pull.position = Vector2(448, 808)
	pull.size = Vector2(96, 68)
	pull.pressed.connect(_on_pull)
	add_child(pull)

	pit_result = Label.new()
	pit_result.position = Vector2(556, 806)
	pit_result.size = Vector2(142, 72)
	pit_result.autowrap_mode = TextServer.AUTOWRAP_WORD
	pit_result.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	pit_result.add_theme_font_size_override("font_size", 12)
	pit_result.add_theme_color_override("font_color", Color(0.85, 0.8, 0.62))
	add_child(pit_result)

func _build_statue() -> void:
	var statue := Button.new()
	statue.focus_mode = Control.FOCUS_NONE
	statue.position = Vector2(612, 196)
	statue.size = Vector2(92, 150)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.13, 0.13, 0.17)
	sb.border_color = Color(0.35, 0.35, 0.45)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	for st in ["normal", "hover", "pressed"]:
		statue.add_theme_stylebox_override(st, sb)
	statue.pressed.connect(func(): vei_panel.visible = true)
	add_child(statue)

	add_child(_icon("res://assets/icons/_vei.svg", Vector2(624, 204), Vector2(68, 104), Color(0.62, 0.64, 0.78)))

	var cap := Label.new()
	cap.position = Vector2(612, 314)
	cap.size = Vector2(92, 20)
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cap.add_theme_font_size_override("font_size", 13)
	cap.add_theme_color_override("font_color", Color(0.6, 0.62, 0.72))
	cap.text = "VEI"
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(cap)

# ---- Bottom: forms inventory + shelf ----

func _build_bottom() -> void:
	var flabel := Label.new()
	flabel.position = Vector2(16, 896)
	flabel.add_theme_font_size_override("font_size", 14)
	flabel.add_theme_color_override("font_color", Color(0.7, 0.75, 0.85))
	flabel.text = "FORMS (tap to place on the slab)"
	add_child(flabel)
	forms_box = HFlowContainer.new()
	forms_box.position = Vector2(16, 920)
	forms_box.size = Vector2(688, 110)
	add_child(forms_box)

	var slabel := Label.new()
	slabel.position = Vector2(16, 1110)
	slabel.add_theme_font_size_override("font_size", 13)
	slabel.add_theme_color_override("font_color", Color(0.6, 0.65, 0.7))
	slabel.text = "ROSTER  (your warband — feed any to the Maw)"
	add_child(slabel)
	shelf_box = HFlowContainer.new()
	shelf_box.position = Vector2(16, 1132)
	shelf_box.size = Vector2(688, 130)
	add_child(shelf_box)

# ---- Overlays: remnant picker, name prompt, Vei, debug ----

func _build_picker() -> void:
	picker = _overlay_panel(Vector2(120, 300), Vector2(480, 560))
	picker_title = Label.new()
	picker_title.position = Vector2(20, 16)
	picker_title.add_theme_font_size_override("font_size", 18)
	picker.add_child(picker_title)
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(12, 50)
	scroll.size = Vector2(456, 460)
	picker.add_child(scroll)
	picker_list = VBoxContainer.new()
	picker_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	picker_list.custom_minimum_size = Vector2(440, 0)
	scroll.add_child(picker_list)
	var close := Button.new()
	close.text = "cancel"
	close.focus_mode = Control.FOCUS_NONE
	close.position = Vector2(12, 516)
	close.size = Vector2(456, 34)
	close.pressed.connect(func(): picker.visible = false)
	picker.add_child(close)

func _build_name_prompt() -> void:
	name_prompt = _overlay_panel(Vector2(110, 440), Vector2(500, 250))
	var t := Label.new()
	t.position = Vector2(24, 22)
	t.size = Vector2(452, 30)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_size_override("font_size", 20)
	t.add_theme_color_override("font_color", Color(0.9, 0.85, 1.0))
	t.text = "Would you like to name your new friend?"
	name_prompt.add_child(t)
	name_edit = LineEdit.new()
	name_edit.position = Vector2(40, 80)
	name_edit.size = Vector2(420, 48)
	name_edit.add_theme_font_size_override("font_size", 22)
	name_prompt.add_child(name_edit)
	var keepit := Button.new()
	keepit.text = "Name it"
	keepit.focus_mode = Control.FOCUS_NONE
	keepit.position = Vector2(40, 150)
	keepit.size = Vector2(200, 54)
	keepit.pressed.connect(func(): _confirm_raise(name_edit.text))
	name_prompt.add_child(keepit)
	var skip := Button.new()
	skip.text = "Keep the ghost-name"
	skip.focus_mode = Control.FOCUS_NONE
	skip.position = Vector2(260, 150)
	skip.size = Vector2(200, 54)
	skip.pressed.connect(func(): _confirm_raise(""))
	name_prompt.add_child(skip)

# ---- The Maw's materials drawer (also: your remnants, finally visible) ----

func _build_materials() -> void:
	materials_panel = _overlay_panel(Vector2(90, 250), Vector2(540, 660))
	var t := Label.new()
	t.position = Vector2(20, 16)
	t.add_theme_font_size_override("font_size", 18)
	t.add_theme_color_override("font_color", Color(0.92, 0.82, 0.72))
	t.text = "TOSS INTO THE MAW"
	materials_panel.add_child(t)
	var sub := Label.new()
	sub.position = Vector2(20, 42)
	sub.size = Vector2(500, 18)
	sub.add_theme_font_size_override("font_size", 12)
	sub.add_theme_color_override("font_color", Color(0.6, 0.6, 0.62))
	sub.text = "richer things fill more — also where your spare remnants live"
	materials_panel.add_child(sub)
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(12, 68)
	scroll.size = Vector2(516, 540)
	materials_panel.add_child(scroll)
	materials_list = VBoxContainer.new()
	materials_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	materials_list.custom_minimum_size = Vector2(500, 0)
	scroll.add_child(materials_list)
	var close := Button.new()
	close.text = "done"
	close.focus_mode = Control.FOCUS_NONE
	close.position = Vector2(12, 616)
	close.size = Vector2(516, 34)
	close.pressed.connect(func(): materials_panel.visible = false)
	materials_panel.add_child(close)

func _open_materials() -> void:
	_populate_materials()
	materials_panel.visible = true

func _populate_materials() -> void:
	for c in materials_list.get_children():
		c.queue_free()
	if GameState.scraps > 0:
		var chunk := mini(int(ConfigDb.v("ossuary", "feed_chunk")), GameState.scraps)
		_mat_row("Scraps ×%d" % GameState.scraps, "feed %d" % chunk, Color(0.72, 0.66, 0.6),
			func(): GameState.feed_ossuary(); _post_toss("fed %d scraps" % chunk))
	for r in GameState.remnants:
		var w := int(round(Loot.remnant_worth(r)))
		_mat_row(_remnant_label(r), "+%d fill" % w, Loot.rarity_color(r["rarity"]), _toss_remnant.bind(r))
	for idx in GameState.shelf.size():
		var c: Dictionary = GameState.shelf[idx]
		var w := int(round(Loot.minion_worth(c)))
		_mat_row("⚰ " + String(c["display_name"]), "sacrifice  +%d fill" % w, Color(0.82, 0.52, 0.52),
			_sacrifice_minion.bind(idx))
	if materials_list.get_child_count() == 0:
		var l := Label.new()
		l.text = "Nothing to toss. Raid for more."
		l.add_theme_color_override("font_color", Color(0.6, 0.6, 0.65))
		materials_list.add_child(l)

func _mat_row(title: String, sub: String, col: Color, cb: Callable) -> void:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 46)
	b.add_theme_font_size_override("font_size", 14)
	b.text = "%s     —     %s" % [title, sub]
	b.add_theme_color_override("font_color", col)
	b.pressed.connect(cb)
	materials_list.add_child(b)

func _toss_remnant(r: Dictionary) -> void:
	var units := GameState.feed_remnant(r)
	_post_toss("tossed %s  (+%d)" % [String(r["stat"]).capitalize(), units])

func _sacrifice_minion(idx: int) -> void:
	if idx < 0 or idx >= GameState.shelf.size():
		return
	var c: Dictionary = GameState.shelf[idx]
	var w := int(round(Loot.minion_worth(c)))
	_ask_confirm("Feed %s to the Maw?\nVei takes the body — you keep +%d fullness." % [String(c["display_name"]), w],
		func():
			var u := GameState.feed_minion(idx)
			_post_toss("%s dissolved  (+%d)" % [String(c["display_name"]), u]))

func _post_toss(msg: String) -> void:
	pit_result.text = msg
	if materials_panel.visible:
		_populate_materials()
	_refresh()

func _build_confirm() -> void:
	confirm_panel = _overlay_panel(Vector2(120, 470), Vector2(480, 240))
	confirm_label = Label.new()
	confirm_label.position = Vector2(24, 22)
	confirm_label.size = Vector2(432, 116)
	confirm_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	confirm_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	confirm_label.add_theme_font_size_override("font_size", 16)
	confirm_label.add_theme_color_override("font_color", Color(0.88, 0.82, 0.86))
	confirm_panel.add_child(confirm_label)
	var yes := Button.new()
	yes.text = "Feed it"
	yes.focus_mode = Control.FOCUS_NONE
	yes.position = Vector2(40, 162)
	yes.size = Vector2(180, 52)
	yes.pressed.connect(func():
		confirm_panel.visible = false
		if _confirm_cb.is_valid():
			_confirm_cb.call())
	confirm_panel.add_child(yes)
	var no := Button.new()
	no.text = "Keep it"
	no.focus_mode = Control.FOCUS_NONE
	no.position = Vector2(260, 162)
	no.size = Vector2(180, 52)
	no.pressed.connect(func(): confirm_panel.visible = false)
	confirm_panel.add_child(no)

func _ask_confirm(msg: String, cb: Callable) -> void:
	confirm_label.text = msg
	_confirm_cb = cb
	confirm_panel.visible = true

func _build_vei_panel() -> void:
	vei_panel = _overlay_panel(Vector2(110, 380), Vector2(500, 360))
	var t := Label.new()
	t.position = Vector2(24, 20)
	t.add_theme_font_size_override("font_size", 22)
	t.add_theme_color_override("font_color", Color(0.7, 0.72, 0.85))
	t.text = "VEI, who keeps the dead"
	vei_panel.add_child(t)
	var body := Label.new()
	body.position = Vector2(24, 64)
	body.size = Vector2(452, 180)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_font_size_override("font_size", 15)
	body.add_theme_color_override("font_color", Color(0.75, 0.75, 0.82))
	body.text = "The Raven Queen of the still and silent. She watched over your passing — and you refused it. To her every risen thing is a wound in the order of death. She is patient. She is the end of you."
	vei_panel.add_child(body)
	var challenge := Button.new()
	challenge.text = "Challenge Vei"
	challenge.focus_mode = Control.FOCUS_NONE
	challenge.position = Vector2(24, 268)
	challenge.size = Vector2(280, 56)
	challenge.pressed.connect(func(): body.text = "You are not ready to challenge Vei.")
	vei_panel.add_child(challenge)
	var close := Button.new()
	close.text = "leave"
	close.focus_mode = Control.FOCUS_NONE
	close.position = Vector2(320, 268)
	close.size = Vector2(156, 56)
	close.pressed.connect(func(): vei_panel.visible = false)
	vei_panel.add_child(close)

func _build_debug() -> void:
	var dbg := Button.new()
	dbg.text = "DBG"
	dbg.focus_mode = Control.FOCUS_NONE
	dbg.position = Vector2(8, 8)
	dbg.size = Vector2(56, 30)
	dbg.pressed.connect(func(): dbg_panel.visible = not dbg_panel.visible)
	add_child(dbg)

	dbg_panel = _overlay_panel(Vector2(8, 44), Vector2(330, 470))
	dbg_panel.visible = false
	var box := VBoxContainer.new()
	box.position = Vector2(12, 12)
	box.size = Vector2(306, 446)
	box.add_theme_constant_override("separation", 6)
	dbg_panel.add_child(box)
	_dbg_button(box, "RAID COMPLETE — grant haul", func(): GameState.grant_raid_haul())
	_dbg_button(box, "+50 scrap", func(): GameState.scraps += 50; GameState.materials_changed.emit())
	_dbg_button(box, "Reset crypt", func(): _reset_all())
	_dbg_slider(box, "maw floor frac (1=sure, 0=lottery)", "ossuary", "floor_frac", 0.0, 1.0, 0.05)
	_dbg_slider(box, "name blend threshold", "names", "blend_threshold", 0.3, 1.0, 0.05)
	_dbg_slider(box, "raise hold time (s)", "slab", "raise_hold_time_s", 0.3, 2.5, 0.1)
	_dbg_slider(box, "maw fill / scrap", "ossuary", "fill_per_scrap", 0.01, 0.2, 0.01)
	_dbg_slider(box, "maw drop / pull", "ossuary", "drop_per_pull", 0.05, 0.6, 0.05)
	var decay := CheckButton.new()
	decay.text = "pit passive decay"
	decay.focus_mode = Control.FOCUS_NONE
	decay.button_pressed = bool(ConfigDb.v("ossuary", "decay_enabled"))
	decay.toggled.connect(func(on): ConfigDb.set_v("ossuary", "decay_enabled", on))
	box.add_child(decay)

# ---- Build flow ----

func _rebuild_forms() -> void:
	for c in forms_box.get_children():
		c.queue_free()
	var counts := {}
	for id in GameState.forms:
		counts[id] = int(counts.get(id, 0)) + 1
	var ids: Array = counts.keys()
	ids.sort()
	for id in ids:
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 16)
		b.custom_minimum_size = Vector2(0, 44)
		b.text = "%s ×%d" % [ConfigDb.husk(id)["name"], counts[id]]
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(String(ConfigDb.husk(id)["color"])).darkened(0.45)
		sb.set_corner_radius_all(6)
		b.add_theme_stylebox_override("normal", sb)
		b.pressed.connect(_on_pick_form.bind(id))
		forms_box.add_child(b)

func _on_pick_form(id: String) -> void:
	if build.has_form():
		_return_build_to_pool()
	GameState.take_form(id)
	build.place_form(id)
	_rebuild_runes()
	_refresh()

func _return_build_to_pool() -> void:
	for s in build.slots:
		if not (s["remnant"] as Dictionary).is_empty():
			GameState.return_remnant(s["remnant"])
	if build.has_form():
		GameState.return_form(build.form_id)
	build.clear()

func _rebuild_runes() -> void:
	# remove_child before queue_free: queue_free is deferred, so stale runes would
	# otherwise linger a frame and _restyle_runes would index them against the new
	# (possibly empty) slots array — an out-of-range read that produced Color("").
	for c in rune_holder.get_children():
		rune_holder.remove_child(c)
		c.queue_free()
	var n := build.slots.size()
	if n == 0:
		return
	var ring := float(ConfigDb.v("slab", "rune_ring_radius"))
	var rr := float(ConfigDb.v("slab", "rune_radius"))
	for i in n:
		var ang := -PI / 2.0 + TAU * i / float(n)
		var pos := SLAB_CENTER + Vector2(cos(ang), sin(ang)) * ring
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.size = Vector2(rr * 2, rr * 2)
		b.position = pos - Vector2(rr, rr)
		b.add_theme_font_size_override("font_size", 12)
		b.pressed.connect(_on_rune.bind(i))
		rune_holder.add_child(b)
	_restyle_runes()

func _restyle_runes() -> void:
	var rr := int(ConfigDb.v("slab", "rune_radius"))
	var kids := rune_holder.get_children()
	for i in mini(kids.size(), build.slots.size()):
		var b: Button = kids[i]
		var slot: Dictionary = build.slots[i]
		var aspect: String = slot["aspect"]
		var acol := Color(String(ConfigDb.data["slab"]["aspect_colors"][aspect]))
		var filled := not (slot["remnant"] as Dictionary).is_empty()
		var sb := StyleBoxFlat.new()
		sb.set_corner_radius_all(rr)
		sb.set_border_width_all(3)
		if filled:
			var r: Dictionary = slot["remnant"]
			sb.bg_color = Loot.rarity_color(r["rarity"]).darkened(0.2)
			sb.border_color = Loot.rarity_color(r["rarity"])
			b.text = "%s%d" % [STATS_SHORT[r["stat"]], int(r["magnitude"])]
		else:
			sb.bg_color = acol.darkened(0.62)
			sb.border_color = acol
			b.text = aspect.substr(0, 1).to_upper()
		for st in ["normal", "hover", "pressed"]:
			b.add_theme_stylebox_override(st, sb)

func _on_rune(i: int) -> void:
	var slot: Dictionary = build.slots[i]
	if not (slot["remnant"] as Dictionary).is_empty():
		GameState.return_remnant(build.unslot(i))
		_refresh()
	else:
		_open_picker(i)

func _open_picker(slot_i: int) -> void:
	_picking_slot = slot_i
	var aspect: String = build.slots[slot_i]["aspect"]
	picker_title.text = "Slot a %s remnant" % aspect
	_populate_picker(aspect)
	picker.visible = true

func _populate_picker(aspect: String) -> void:
	for c in picker_list.get_children():
		c.queue_free()
	var any := false
	for r in GameState.remnants:
		if Loot.ASPECT_OF_STAT[r["stat"]] != aspect:
			continue
		any = true
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, 44)
		b.add_theme_font_size_override("font_size", 15)
		b.text = _remnant_label(r)
		b.add_theme_color_override("font_color", Loot.rarity_color(r["rarity"]))
		b.pressed.connect(_on_pick_remnant.bind(r))
		picker_list.add_child(b)
	if not any:
		var l := Label.new()
		l.text = "No %s remnants. Pull the pit or raid for more." % aspect
		l.add_theme_color_override("font_color", Color(0.6, 0.6, 0.65))
		picker_list.add_child(l)

func _on_pick_remnant(r: Dictionary) -> void:
	GameState.take_remnant(r)
	build.slot_remnant(_picking_slot, r)
	picker.visible = false
	_refresh()

func _remnant_label(r: Dictionary) -> String:
	var s := "%s %d  [%s]" % [String(r["stat"]).capitalize(), int(r["magnitude"]), r["rarity"]]
	for e in r.get("echoes", []):
		var side: Dictionary = ConfigDb.data["echoes"][e["side"]]
		if side.has(e["id"]):
			s += "  +%s" % side[e["id"]]["name"]
	return s

func _raise_begin() -> void:
	if build.has_form():
		_holding = true
		_hold_t = 0.0

func _raise_release() -> void:
	if _holding:
		_raise_cancel()  # let go before it formed — nothing happens

func _raise_cancel() -> void:
	_holding = false
	_hold_t = 0.0
	preview.reveal_boost = 0.0
	preview.hold_progress = 0.0

func _raise_complete() -> void:
	_holding = false
	preview.hold_progress = 0.0
	preview.reveal_boost = 1.0
	preview.grow = 0.6
	var tw := create_tween()
	tw.tween_property(preview, "grow", 1.0, float(ConfigDb.v("slab", "raise_grow_time_s"))) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.finished.connect(func():
		name_edit.text = String(build.derived()["name"])
		name_prompt.visible = true)

func _confirm_raise(custom: String) -> void:
	GameState.raise_creature(build.derived(), custom)
	build.clear()  # form + slotted remnants were consumed when placed/slotted
	name_prompt.visible = false
	preview.reveal_boost = 0.0
	preview.grow = 1.0
	preview.hold_progress = 0.0
	_rebuild_runes()
	_refresh()

func _rebuild_shelf() -> void:
	for c in shelf_box.get_children():
		c.queue_free()
	for idx in GameState.shelf.size():
		shelf_box.add_child(_roster_card(GameState.shelf[idx], idx))

## One creature in the box: silhouette + name + role line + feed-to-Maw.
func _roster_card(c: Dictionary, idx: int) -> Panel:
	var col := Color(String(c.get("color", "#cccccc")))
	var card := Panel.new()
	card.custom_minimum_size = Vector2(214, 118)
	var csb := StyleBoxFlat.new()
	csb.bg_color = Color(0.13, 0.13, 0.17)
	csb.set_corner_radius_all(8)
	csb.border_color = col.darkened(0.25)
	csb.set_border_width_all(2)
	card.add_theme_stylebox_override("panel", csb)

	card.add_child(_icon("res://assets/icons/%s.svg" % String(c.get("form_id", "zombie")), Vector2(8, 10), Vector2(60, 60), col.lightened(0.12)))

	var nm := Label.new()
	nm.position = Vector2(74, 8)
	nm.size = Vector2(132, 42)
	nm.autowrap_mode = TextServer.AUTOWRAP_WORD
	nm.add_theme_font_size_override("font_size", 14)
	nm.add_theme_color_override("font_color", col.lightened(0.35))
	nm.text = String(c["display_name"])
	card.add_child(nm)

	var rl := Label.new()
	rl.position = Vector2(74, 50)
	rl.size = Vector2(134, 38)
	rl.autowrap_mode = TextServer.AUTOWRAP_WORD
	rl.add_theme_font_size_override("font_size", 11)
	rl.add_theme_color_override("font_color", Color(0.72, 0.7, 0.6))
	rl.text = String(c.get("role_line", c.get("role", "")))
	card.add_child(rl)

	var feed := Button.new()
	feed.text = "▼ feed to Maw"
	feed.focus_mode = Control.FOCUS_NONE
	feed.add_theme_font_size_override("font_size", 11)
	feed.position = Vector2(8, 84)
	feed.size = Vector2(198, 26)
	feed.pressed.connect(_sacrifice_minion.bind(idx))
	card.add_child(feed)
	return card

# ---- Refresh / signals ----

func _refresh() -> void:
	var d := build.derived()
	preview.set_build(d)
	if build.has_form():
		name_label.text = d["name"]
		name_label.add_theme_color_override("font_color", Color(0.82, 0.8, 0.9))
		role_label.text = String(d["role_line"])
		raise_btn.visible = true
	else:
		name_label.text = "— empty slab —"
		name_label.add_theme_color_override("font_color", Color(0.45, 0.45, 0.55))
		role_label.text = ""
		raise_btn.visible = false
	combat_rect.size_flags_stretch_ratio = maxf(0.02, float(d["combat_pts"]))
	town_rect.size_flags_stretch_ratio = maxf(0.02, float(d["town_pts"]))
	_restyle_runes()
	_update_pit()

func _update_pit() -> void:
	var f: float = GameState.ossuary.fullness
	pit_fill.size = Vector2(258.0 * f, 18)
	pit_fill.color = Color(0.55, 0.5, 0.5).lerp(Color(1.0, 0.65, 0.2), f)
	pit_label.text = "quality %d%%   ·   scraps: %d" % [int(f * 100.0), GameState.scraps]

func _on_materials_changed() -> void:
	_rebuild_forms()
	_update_pit()
	if picker.visible and _picking_slot >= 0 and _picking_slot < build.slots.size():
		_populate_picker(build.slots[_picking_slot]["aspect"])
	if materials_panel.visible:
		_populate_materials()

func _on_pull() -> void:
	var out := GameState.pull_ossuary()
	var noun: String = ConfigDb.husk(out["form_id"])["name"]
	var r: Dictionary = out["remnant"]
	pit_result.text = "PULLED:\n%s  +  %s %d [%s]" % [noun, String(r["stat"]).capitalize(), int(r["magnitude"]), r["rarity"]]

func _reset_all() -> void:
	build.clear()
	GameState.reset()
	GameState.grant_raid_haul()
	_rebuild_runes()
	_rebuild_forms()
	_rebuild_shelf()
	_refresh()

# ---- tiny helpers ----

# A fixed-size, tintable icon. expand_mode MUST be set before size, else the
# default KEEP_SIZE pins min-size to the texture's 512px and clamps size up.
func _icon(path: String, pos: Vector2, sz: Vector2, tint: Color) -> TextureRect:
	var tr := TextureRect.new()
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.texture = load(path)
	tr.position = pos
	tr.custom_minimum_size = sz
	tr.size = sz
	tr.modulate = tint
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return tr

func _overlay_panel(pos: Vector2, sz: Vector2) -> Panel:
	var p := Panel.new()
	p.position = pos
	p.size = sz
	p.visible = false
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.1, 0.13, 0.99)
	sb.border_color = Color(0.4, 0.4, 0.5)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	p.add_theme_stylebox_override("panel", sb)
	add_child(p)
	return p

func _dbg_button(box: VBoxContainer, text: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 34)
	b.pressed.connect(cb)
	box.add_child(b)

func _dbg_slider(box: VBoxContainer, label: String, file: String, key: String, lo: float, hi: float, step: float) -> void:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", 12)
	l.text = "%s: %s" % [label, str(ConfigDb.v(file, key))]
	box.add_child(l)
	var s := HSlider.new()
	s.focus_mode = Control.FOCUS_NONE
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = float(ConfigDb.v(file, key))
	s.custom_minimum_size = Vector2(0, 24)
	s.value_changed.connect(func(v):
		l.text = "%s: %s" % [label, str(v)]
		ConfigDb.set_v(file, key, v))
	box.add_child(s)
