class_name Hud
extends CanvasLayer
## All chrome: trance button (corner, side configurable §8), focus/cooldown
## display, warnings, haul counters, and the full-screen states (menu, haul
## summary, death). Ugly is correct — the prototype tests a feel, not a look.

signal start_raid_pressed
signal playroom_pressed(id: String)
signal menu_pressed

var trance: TranceController = null
var gameplay := false
var boss: RRUnit = null

var root: Control
var btn_view: Control
var btn_radius := 62.0
var _btn_touch := -1
var chamber_label: Label
var counters_label: Label
var warn_label: Label
var boss_label: Label
var _warn_t := 0.0
var screen: Control = null

func _ready() -> void:
	layer = 10
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	chamber_label = _label(22, Color(0.95, 0.92, 0.85))
	chamber_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	chamber_label.position = Vector2(-260, 10)
	chamber_label.size = Vector2(520, 30)
	chamber_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	boss_label = _label(18, Color(1.0, 0.55, 0.35))
	boss_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	boss_label.position = Vector2(-260, 42)
	boss_label.size = Vector2(520, 26)
	boss_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	counters_label = _label(17, Color(0.85, 0.85, 0.9))
	counters_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	counters_label.position = Vector2(-250, 74)
	counters_label.size = Vector2(240, 26)
	counters_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	warn_label = _label(26, Color(1.0, 0.25, 0.2))
	warn_label.set_anchors_preset(Control.PRESET_CENTER)
	warn_label.position = Vector2(-330, -200)
	warn_label.size = Vector2(660, 80)
	warn_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	warn_label.visible = false

	btn_view = TranceButtonView.new()
	btn_view.hud = self
	btn_view.custom_minimum_size = Vector2(btn_radius * 2 + 16, btn_radius * 2 + 36)
	if String(ConfigDb.v("timers", "button_side")) == "left":
		btn_view.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
		btn_view.position = Vector2(18, -btn_radius * 2 - 54)
	else:
		btn_view.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		btn_view.position = Vector2(-btn_radius * 2 - 34, -btn_radius * 2 - 54)
	btn_view.size = btn_view.custom_minimum_size
	btn_view.add_to_group("rr_ui_block")
	btn_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(btn_view)

	GameState.haul_changed.connect(_update_counters)
	_set_gameplay_visible(false)

func _label(font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	root.add_child(l)
	return l

func _process(delta: float) -> void:
	if gameplay:
		btn_view.queue_redraw()
	if _warn_t > 0.0:
		_warn_t -= delta
		warn_label.visible = fmod(_warn_t, 0.4) > 0.15
		if _warn_t <= 0.0:
			warn_label.visible = false
	if boss != null and is_instance_valid(boss) and boss.alive:
		var frac: float = clampf(boss.hp / boss.max_hp, 0.0, 1.0)
		var blocks := int(frac * 24.0)
		boss_label.text = "%s  [%s%s]" % [boss.display_name, "#".repeat(blocks), "-".repeat(24 - blocks)]
		boss_label.visible = true
	else:
		boss_label.visible = false

## Trance button is multitouch-claimed manually so the OTHER thumb can trace.
func _input(event: InputEvent) -> void:
	if not gameplay or trance == null:
		return
	if event is InputEventScreenTouch:
		if event.pressed and _btn_touch == -1 and _in_button(event.position):
			_btn_touch = event.index
			trance.button_down()
			get_viewport().set_input_as_handled()
		elif not event.pressed and event.index == _btn_touch:
			_btn_touch = -1
			trance.button_up()
			get_viewport().set_input_as_handled()

func _in_button(p: Vector2) -> bool:
	var center: Vector2 = btn_view.get_global_rect().position + Vector2(btn_radius + 8, btn_radius + 8)
	return p.distance_to(center) <= btn_radius + 16.0

# ---- Mode plumbing ----

func enter_gameplay(t: TranceController) -> void:
	trance = t
	gameplay = true
	boss = null
	_kill_screen()
	_set_gameplay_visible(true)
	_update_counters()

func exit_gameplay() -> void:
	trance = null
	gameplay = false
	boss = null
	chamber_label.text = ""
	_set_gameplay_visible(false)

func _set_gameplay_visible(on: bool) -> void:
	btn_view.visible = on
	chamber_label.visible = on
	counters_label.visible = on
	if not on:
		boss_label.visible = false
		warn_label.visible = false

func set_chamber(index: int, chamber_name: String, total: int) -> void:
	chamber_label.text = "Chamber %d/%d — %s" % [index + 1, total, chamber_name]

func bind_boss(b: RRUnit) -> void:
	boss = b

func warn_no_chaff() -> void:
	warn_label.text = "CHAFF GONE — PERMANENTS DIE IN HER PLACE"
	_warn_t = 2.6

func _update_counters() -> void:
	counters_label.text = "remnants %d   husks %d   kills %d" % [
		GameState.remnants.size(), GameState.husks.size(), GameState.kills]

func screens_open() -> bool:
	return screen != null

# ---- Screens ----

func _kill_screen() -> void:
	if screen != null:
		screen.queue_free()
		screen = null

func _screen_base() -> VBoxContainer:
	_kill_screen()
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_to_group("rr_ui_block")
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.06, 0.06, 0.08, 0.97)
	panel.add_theme_stylebox_override("panel", bg)
	root.add_child(panel)
	screen = panel
	var scroll := ScrollContainer.new()
	panel.add_child(scroll)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	box.custom_minimum_size = Vector2(560, 0)
	center.add_child(box)
	return box

func _title(box: VBoxContainer, text: String, color := Color(0.95, 0.92, 0.85), size := 40) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(l)

func _text(box: VBoxContainer, text: String, size := 16, color := Color(0.8, 0.8, 0.85)) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(l)
	return l

func _big_button(box: VBoxContainer, text: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 22)
	b.custom_minimum_size = Vector2(0, 54)
	b.focus_mode = Control.FOCUS_NONE  # Space belongs to the Trance, never to a button
	b.pressed.connect(cb)
	box.add_child(b)

func show_menu(playrooms: Array) -> void:
	exit_gameplay()
	var box := _screen_base()
	_title(box, "RAID & RAISE")
	_text(box, "Relish raids tombs as a conduit: her army is her weapon, her shield, and her health bar. If Relish dies, everything is lost.", 16)
	_big_button(box, "ENTER THE TOMB", func(): start_raid_pressed.emit())
	_text(box, "PLAYROOMS — isolated mechanic tests, infinitely repeatable:", 15, Color(0.6, 0.6, 0.7))
	for p in playrooms:
		_big_button(box, p[1], func(): playroom_pressed.emit(p[0]))
	_text(box, "Controls — tap: move Relish · lasso undead: select · tap: send them · drag from Relish: her path · HOLD corner button (or SPACE): Trance, then trace a circle around glowing essence · DBG (top-left): tunables, spawns, telemetry.", 13, Color(0.55, 0.55, 0.65))

func show_haul() -> void:
	var box := _screen_base()
	exit_gameplay()
	_title(box, "THE HAUL", Color(0.7, 1.0, 0.75))
	_text(box, "Kills: %d    Essence dropped: %d    Chaff raised: %d" % [GameState.kills, GameState.essence_dropped, GameState.chaff_summoned])
	_text(box, "Remnants (%d):" % GameState.remnants.size(), 18)
	for r in GameState.remnants:
		var echo_bits := []
		for e in r["echoes"]:
			echo_bits.append("%s %d (%s)" % [e["id"], e["points"], e["side"]])
		var line := "  %s [%s]" % [Loot.remnant_label(r), r["rarity"]]
		if echo_bits.size() > 0:
			line += " — " + ", ".join(echo_bits)
		_text(box, line, 15, Loot.rarity_color(r["rarity"]))
	_text(box, "Husks (%d):" % GameState.husks.size(), 18)
	for h in GameState.husks:
		_text(box, "  %s" % ConfigDb.husk(h)["name"], 15, Color(0.85, 0.75, 1.0))
	_text(box, "Circle scores (%d summons, avg %.0f):" % [GameState.circle_scores.size(), GameState.average_score()], 18)
	_text(box, _histogram_text(), 14, Color(0.5, 1.0, 0.85))
	var drift := "  << drifting RTS (circle must stay the heart)" if GameState.ratio_drifting() else ""
	_text(box, "Command : Summon ratio — %s%s" % [GameState.ratio_string(), drift], 15)
	_text(box, "The Slab is not built yet (Phase 2) — your haul fades when you leave.", 13, Color(0.55, 0.55, 0.65))
	_big_button(box, "RETURN TO THE SURFACE", func(): menu_pressed.emit())

func show_death() -> void:
	var box := _screen_base()
	exit_gameplay()
	_title(box, "RELISH IS DEAD", Color(1.0, 0.25, 0.2), 46)
	_text(box, "Everything is lost. The run. The haul. The army. That's the moral.", 18)
	_text(box, "Lost with her: %d remnants, %d husks, %d kills' worth of progress." % [
		GameState.remnants.size(), GameState.husks.size(), GameState.kills], 15, Color(0.7, 0.5, 0.5))
	_big_button(box, "BEGIN AGAIN (fresh start)", func(): menu_pressed.emit())

func _histogram_text() -> String:
	var buckets := GameState.score_histogram()
	var lines := []
	for i in 10:
		lines.append("%2d0s %s %d" % [i, "#".repeat(buckets[i]), buckets[i]])
	return "\n".join(lines)

## The corner button: cooldown shown as a radial fill on the button itself (§8.2).
class TranceButtonView:
	extends Control
	var hud: Hud

	func _draw() -> void:
		if hud == null or hud.trance == null:
			return
		var t: TranceController = hud.trance
		var c := Vector2(hud.btn_radius + 8, hud.btn_radius + 8)
		var r := hud.btn_radius
		var base := Color(0.2, 0.16, 0.3, 0.9)
		var rim := Color(0.6, 0.45, 0.9)
		match t.state:
			TranceController.State.ACTIVE:
				base = Color(0.3, 0.2, 0.5, 0.95)
				rim = Color(0.8, 0.65, 1.0)
			TranceController.State.COOLDOWN, TranceController.State.LOCKOUT:
				base = Color(0.13, 0.12, 0.17, 0.9)
				rim = Color(0.35, 0.3, 0.5)
		draw_circle(c, r, base)
		var cd := t.cooldown_frac()
		if cd > 0.0:
			# radial fill: remaining cooldown as a pie wedge
			draw_arc(c, r * 0.5, -PI / 2, -PI / 2 + TAU * cd, 40, Color(0.1, 0.08, 0.14, 0.9), r)
		if t.state == TranceController.State.ACTIVE:
			draw_arc(c, r + 5, -PI / 2, -PI / 2 + TAU * t.focus_frac(), 40, Color(0.5, 1.0, 0.85), 4.0)
		draw_arc(c, r, 0, TAU, 48, rim, 3.0)
		var f := ThemeDB.fallback_font
		draw_string(f, c + Vector2(-r, 6), "TRANCE", HORIZONTAL_ALIGNMENT_CENTER, r * 2, 18, Color(0.9, 0.85, 1.0))
		draw_string(f, c + Vector2(-r, r + 24), "hold · SPACE / R-drag", HORIZONTAL_ALIGNMENT_CENTER, r * 2, 12, Color(0.6, 0.6, 0.7))
