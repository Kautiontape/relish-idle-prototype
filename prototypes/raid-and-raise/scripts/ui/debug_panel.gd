class_name DebugPanel
extends CanvasLayer
## Debug controls are first-class (prototyping rules): live tunables for every
## §11 value, force-spawning, god/pacifist/freeze toggles, room switching, and
## the §12 telemetry overlay (command:summon ratio + circle-score histogram —
## if commands dominate ~8:1 the game is drifting RTS; surface it, a human
## decides).

var main: Node = null
var panel: PanelContainer
var tabs: TabContainer
var _telemetry: Label
var _tunables_box: VBoxContainer
var _spawn_pick: OptionButton
var _spawn_count: LineEdit

func _ready() -> void:
	layer = 20
	var toggle := Button.new()
	toggle.focus_mode = Control.FOCUS_NONE
	toggle.text = "DBG"
	toggle.toggle_mode = true
	toggle.position = Vector2(8, 8)
	toggle.add_theme_font_size_override("font_size", 14)
	toggle.add_to_group("rr_ui_block")
	toggle.toggled.connect(func(on): panel.visible = on)
	add_child(toggle)

	panel = PanelContainer.new()
	# Anchored to the viewport's full height — adapts to any screen/aspect
	# instead of assuming the 1280 base fits.
	panel.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	panel.offset_left = 8.0
	panel.offset_right = 380.0
	panel.offset_top = 52.0
	panel.offset_bottom = -8.0
	panel.visible = false
	panel.add_to_group("rr_ui_block")
	panel.self_modulate = Color(1, 1, 1, 0.96)
	add_child(panel)

	tabs = TabContainer.new()
	tabs.add_theme_font_size_override("font_size", 13)
	panel.add_child(tabs)
	_build_tunables_tab()
	_build_spawn_tab()
	_build_toggles_tab()
	_build_telemetry_tab()
	_build_rooms_tab()

	var t := Timer.new()
	t.wait_time = 0.5
	t.autostart = true
	t.timeout.connect(_refresh_telemetry)
	add_child(t)

	ConfigDb.value_changed.connect(func(file, _k, _v):
		if file == "*":
			_rebuild_tunables())

func _scroll_tab(title: String) -> VBoxContainer:
	var sc := ScrollContainer.new()
	sc.name = title
	tabs.add_child(sc)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(box)
	return box

# ---- Tunables: every numeric config value, editable live ----

func _build_tunables_tab() -> void:
	_tunables_box = _scroll_tab("Tune")
	_fill_tunables()

func _rebuild_tunables() -> void:
	for c in _tunables_box.get_children():
		c.queue_free()
	_fill_tunables()

func _fill_tunables() -> void:
	var reset := Button.new()
	reset.focus_mode = Control.FOCUS_NONE
	reset.text = "Reset all to config files"
	reset.add_theme_font_size_override("font_size", 13)
	reset.pressed.connect(func(): ConfigDb.reset_tunables())
	_tunables_box.add_child(reset)
	for file in ["stats", "timers", "circle", "rarity"]:
		var header := Label.new()
		header.text = "— %s.json —" % file
		header.add_theme_font_size_override("font_size", 13)
		header.add_theme_color_override("font_color", Color(0.95, 0.85, 0.4))
		_tunables_box.add_child(header)
		var dict: Dictionary = ConfigDb.data[file]
		for key in dict:
			var val: Variant = dict[key]
			if not (val is float or val is int):
				continue
			var row := HBoxContainer.new()
			var l := Label.new()
			l.text = String(key)
			l.add_theme_font_size_override("font_size", 12)
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(l)
			var e := LineEdit.new()
			e.text = str(val)
			e.custom_minimum_size = Vector2(76, 0)
			e.add_theme_font_size_override("font_size", 12)
			var apply := func():
				if e.text.is_valid_float():
					ConfigDb.set_v(file, key, e.text.to_float())
			e.text_submitted.connect(func(_t): apply.call())
			e.focus_exited.connect(apply)
			row.add_child(e)
			_tunables_box.add_child(row)

# ---- Spawn: force-spawn any entity, at center or by tap ----

func _build_spawn_tab() -> void:
	var box := _scroll_tab("Spawn")
	_spawn_pick = OptionButton.new()
	_spawn_pick.focus_mode = Control.FOCUS_NONE
	_spawn_pick.add_theme_font_size_override("font_size", 13)
	for id in ConfigDb.data["enemies"]:
		_spawn_pick.add_item("enemy: " + id)
	for spec in ConfigDb.data["loadout"]["permanents"]:
		_spawn_pick.add_item("permanent: " + spec["name"])
	_spawn_pick.add_item("chaff")
	_spawn_pick.add_item("essence")
	box.add_child(_spawn_pick)
	var row := HBoxContainer.new()
	var cl := Label.new()
	cl.text = "count:"
	cl.add_theme_font_size_override("font_size", 13)
	row.add_child(cl)
	_spawn_count = LineEdit.new()
	_spawn_count.text = "1"
	_spawn_count.custom_minimum_size = Vector2(56, 0)
	row.add_child(_spawn_count)
	box.add_child(row)
	var b1 := Button.new()
	b1.focus_mode = Control.FOCUS_NONE
	b1.text = "Spawn at view center"
	b1.add_theme_font_size_override("font_size", 13)
	b1.pressed.connect(func(): main.debug_spawn(_picked_id(), _count(), null))
	box.add_child(b1)
	var b2 := Button.new()
	b2.focus_mode = Control.FOCUS_NONE
	b2.text = "Spawn at next tap"
	b2.add_theme_font_size_override("font_size", 13)
	b2.pressed.connect(func(): main.arm_place_spawn(_picked_id(), _count()))
	box.add_child(b2)
	var note := Label.new()
	note.text = "Spawns into the current room/raid."
	note.add_theme_font_size_override("font_size", 11)
	note.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7))
	box.add_child(note)

func _picked_id() -> String:
	return _spawn_pick.get_item_text(_spawn_pick.selected)

func _count() -> int:
	return maxi(1, _spawn_count.text.to_int())

# ---- Toggles ----

func _build_toggles_tab() -> void:
	var box := _scroll_tab("Flags")
	var labels := {
		"god": "God mode (Relish ignores hits)",
		"pacifist": "Pacifist (nobody deals damage)",
		"freeze": "Freeze enemies (no AI)",
		"show_targets": "Show target lines",
		"show_paths": "Show nav paths",
		"show_fields": "Show charm/dread field radii",
	}
	for key in labels:
		var cb := CheckBox.new()
		cb.focus_mode = Control.FOCUS_NONE
		cb.text = labels[key]
		cb.add_theme_font_size_override("font_size", 13)
		cb.button_pressed = GameState.debug[key]
		cb.toggled.connect(func(on): GameState.debug[key] = on)
		box.add_child(cb)

# ---- Telemetry (§12 debug overlay) ----

func _build_telemetry_tab() -> void:
	var box := _scroll_tab("Stats")
	_telemetry = Label.new()
	_telemetry.add_theme_font_size_override("font_size", 13)
	box.add_child(_telemetry)

func _refresh_telemetry() -> void:
	if _telemetry == null or not panel.visible:
		return
	var buckets := GameState.score_histogram()
	var hist := []
	for i in 10:
		hist.append(" %d0-%d9: %s %d" % [i, i, "#".repeat(buckets[i]), buckets[i]])
	var drift := "\n!! COMMANDS DOMINATING (>=8:1) — RTS DRIFT" if GameState.ratio_drifting() else ""
	var chaff := 0
	if main != null and main.mode != null and "battlefield" in main.mode and main.mode.battlefield != null:
		chaff = main.mode.battlefield.count_kind(RRUnit.Kind.CHAFF)
	_telemetry.text = "command touches: %d\ntrance summons: %d\nratio: %s%s\n\nkills: %d\nessence dropped: %d\nchaff raised: %d (alive now: %d)\navg circle: %.0f\n%s\n\nfps: %d" % [
		GameState.command_touches, GameState.trance_summons, GameState.ratio_string(), drift,
		GameState.kills, GameState.essence_dropped, GameState.chaff_summoned, chaff,
		GameState.average_score(), "\n".join(hist), Engine.get_frames_per_second()]

# ---- Rooms ----

func _build_rooms_tab() -> void:
	var box := _scroll_tab("Rooms")
	var mk := func(text: String, cb: Callable):
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.text = text
		b.add_theme_font_size_override("font_size", 13)
		b.pressed.connect(cb)
		box.add_child(b)
	mk.call("Menu", func(): main.show_menu())
	mk.call("Full raid", func(): main.start_raid())
	for p in main.PLAYROOM_NAMES:
		var id: String = p[0]
		mk.call("Playroom: " + p[1], func(): main.start_playroom(id))
	mk.call("Reset current room", func(): main.reset_room())
