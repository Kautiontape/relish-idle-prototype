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
	_build_vei_panel()
	_build_debug()

	GameState.materials_changed.connect(_on_materials_changed)
	GameState.shelf_changed.connect(_rebuild_shelf)
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
	sub.position = Vector2(0, 142)
	sub.size = Vector2(720, 22)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 13)
	sub.add_theme_color_override("font_color", Color(0.5, 0.5, 0.6))
	sub.text = "THE CRYPT — place a form, slot remnants, Raise"
	add_child(sub)

	# Twin lean bar (combat | town) — identity readout while building.
	var bar := HBoxContainer.new()
	bar.position = Vector2(210, 172)
	bar.size = Vector2(300, 12)
	bar.add_theme_constant_override("separation", 0)
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
	raise_btn.text = "✦ RAISE ✦"
	raise_btn.focus_mode = Control.FOCUS_NONE
	raise_btn.add_theme_font_size_override("font_size", 22)
	raise_btn.size = Vector2(220, 52)
	raise_btn.position = SLAB_CENTER + Vector2(-110, 222)
	raise_btn.pressed.connect(_on_raise)
	add_child(raise_btn)

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
	title.text = "THE BONE PIT — feed scraps, then pull (always gives something)"
	add_child(title)

	# Fullness/quality meter
	var meter_bg := ColorRect.new()
	meter_bg.color = Color(0.05, 0.04, 0.04)
	meter_bg.position = Vector2(28, 824)
	meter_bg.size = Vector2(360, 16)
	add_child(meter_bg)
	pit_fill = ColorRect.new()
	pit_fill.color = Color(0.9, 0.55, 0.2)
	pit_fill.position = Vector2(28, 824)
	pit_fill.size = Vector2(0, 16)
	add_child(pit_fill)
	pit_label = Label.new()
	pit_label.position = Vector2(28, 846)
	pit_label.add_theme_font_size_override("font_size", 12)
	pit_label.add_theme_color_override("font_color", Color(0.7, 0.6, 0.55))
	add_child(pit_label)

	var feed := Button.new()
	feed.text = "FEED"
	feed.focus_mode = Control.FOCUS_NONE
	feed.position = Vector2(404, 820)
	feed.size = Vector2(100, 56)
	feed.pressed.connect(func(): GameState.feed_ossuary())
	add_child(feed)

	var pull := Button.new()
	pull.text = "PULL"
	pull.focus_mode = Control.FOCUS_NONE
	pull.position = Vector2(512, 820)
	pull.size = Vector2(100, 56)
	pull.pressed.connect(_on_pull)
	add_child(pull)

	pit_result = Label.new()
	pit_result.position = Vector2(620, 824)
	pit_result.size = Vector2(80, 56)
	pit_result.autowrap_mode = TextServer.AUTOWRAP_WORD
	pit_result.add_theme_font_size_override("font_size", 11)
	pit_result.add_theme_color_override("font_color", Color(0.8, 0.75, 0.6))
	add_child(pit_result)

func _build_statue() -> void:
	var statue := Button.new()
	statue.text = "VEI"
	statue.focus_mode = Control.FOCUS_NONE
	statue.position = Vector2(612, 196)
	statue.size = Vector2(92, 150)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.13, 0.13, 0.17)
	sb.border_color = Color(0.35, 0.35, 0.45)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	statue.add_theme_stylebox_override("normal", sb)
	statue.add_theme_color_override("font_color", Color(0.6, 0.62, 0.72))
	statue.pressed.connect(func(): vei_panel.visible = true)
	add_child(statue)

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
	slabel.text = "RAISED"
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

	dbg_panel = _overlay_panel(Vector2(8, 44), Vector2(330, 360))
	dbg_panel.visible = false
	var box := VBoxContainer.new()
	box.position = Vector2(12, 12)
	box.size = Vector2(306, 336)
	box.add_theme_constant_override("separation", 6)
	dbg_panel.add_child(box)
	_dbg_button(box, "RAID COMPLETE — grant haul", func(): GameState.grant_raid_haul())
	_dbg_button(box, "+50 scrap", func(): GameState.scraps += 50; GameState.materials_changed.emit())
	_dbg_button(box, "Reset crypt", func(): _reset_all())
	_dbg_slider(box, "pit fill / scrap", "ossuary", "fill_per_scrap", 0.01, 0.2, 0.01)
	_dbg_slider(box, "pit drop / pull", "ossuary", "drop_per_pull", 0.05, 0.6, 0.05)
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

func _on_raise() -> void:
	if not build.has_form():
		return
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
	_rebuild_runes()
	_refresh()

func _rebuild_shelf() -> void:
	for c in shelf_box.get_children():
		c.queue_free()
	for c in GameState.shelf:
		var p := Panel.new()
		p.custom_minimum_size = Vector2(150, 56)
		var l := Label.new()
		l.position = Vector2(8, 6)
		l.size = Vector2(138, 44)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD
		l.add_theme_font_size_override("font_size", 13)
		l.add_theme_color_override("font_color", Color(String(c.get("color", "#cccccc"))).lightened(0.2))
		l.text = String(c["display_name"])
		p.add_child(l)
		shelf_box.add_child(p)

# ---- Refresh / signals ----

func _refresh() -> void:
	var d := build.derived()
	preview.set_build(d)
	if build.has_form():
		name_label.text = d["name"]
		name_label.add_theme_color_override("font_color", Color(0.82, 0.8, 0.9))
		raise_btn.visible = true
	else:
		name_label.text = "— empty slab —"
		name_label.add_theme_color_override("font_color", Color(0.45, 0.45, 0.55))
		raise_btn.visible = false
	combat_rect.size_flags_stretch_ratio = maxf(0.02, float(d["combat_pts"]))
	town_rect.size_flags_stretch_ratio = maxf(0.02, float(d["town_pts"]))
	_restyle_runes()
	_update_pit()

func _update_pit() -> void:
	var f: float = GameState.ossuary.fullness
	pit_fill.size = Vector2(360.0 * f, 16)
	pit_fill.color = Color(0.55, 0.5, 0.5).lerp(Color(1.0, 0.65, 0.2), f)
	pit_label.text = "quality %d%%   ·   scraps: %d" % [int(f * 100.0), GameState.scraps]

func _on_materials_changed() -> void:
	_rebuild_forms()
	_update_pit()
	if picker.visible and _picking_slot >= 0 and _picking_slot < build.slots.size():
		_populate_picker(build.slots[_picking_slot]["aspect"])

func _on_pull() -> void:
	var out := GameState.pull_ossuary()
	var noun: String = ConfigDb.husk(out["form_id"])["name"]
	var r: Dictionary = out["remnant"]
	pit_result.text = "%s + %s%d" % [noun, STATS_SHORT[r["stat"]], int(r["magnitude"])]

func _reset_all() -> void:
	build.clear()
	GameState.reset()
	GameState.grant_raid_haul()
	_rebuild_runes()
	_rebuild_forms()
	_rebuild_shelf()
	_refresh()

# ---- tiny helpers ----

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
