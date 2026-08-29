extends Control
## The Realm view: pannable/zoomable strategic map. Reads Game freely (it is
## the view of the live sim); exits only via finished({"teleport_to": id}).

signal finished(result: Dictionary)

const GREEN := Color("39ff9e")
const ORANGE := Color("ff6a2b")
const AMBER := Color("ffd000")
const TEXT := Color("e8e8ec")
const TEXT_DIM := Color("8888a0")

var world: Node2D
var cam: Camera2D
var nodes_view: Node2D

var selected_id := ""
var _pressed := false
var _panning := false
var _press_pos := Vector2.ZERO
var _ui_acc := 0.0
var _toast_t := 0.0
var _setup_called := false

var sidebar: PanelContainer
var sb_title: Label
var sb_sub: Label
var sb_desc: Label
var sb_stats: Label
var sb_button: Button
var top_bar: Label
var toast: Label
var victory_label: Label
var confirm: ConfirmationDialog


func setup(_seed_data: Dictionary) -> void:
	_setup_called = true


func demo_seed() -> Dictionary:
	return {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_world()
	_build_ui()
	Game.relish_respawned.connect(_on_respawn)
	Game.victory.connect(_on_victory)
	Game.defeat_boss.connect(func(): _show_toast("She threw the horde back. The factory must grow."))
	await get_tree().process_frame
	if not is_inside_tree():
		return
	_fit_camera()
	if Game.won:
		_on_victory()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--select="):
			selected_id = arg.trim_prefix("--select=")
			nodes_view.selected_id = selected_id
			sidebar.visible = true
			_refresh_sidebar()
		elif arg.begins_with("--teleport="):
			var dest := arg.trim_prefix("--teleport=")
			await get_tree().create_timer(0.3).timeout
			finished.emit({"teleport_to": dest})


func _build_world() -> void:
	world = Node2D.new()
	world.name = "World"
	add_child(world)
	var field := Sprite2D.new()
	field.set_script(load("res://scripts/map/map_field_view.gd"))
	world.add_child(field)
	var routes := Node2D.new()
	routes.set_script(load("res://scripts/map/map_routes.gd"))
	world.add_child(routes)
	nodes_view = Node2D.new()
	nodes_view.set_script(load("res://scripts/map/map_nodes.gd"))
	world.add_child(nodes_view)
	cam = Camera2D.new()
	world.add_child(cam)
	cam.make_current()


func _fit_camera() -> void:
	var ws: Vector2 = Game.field.world_size
	var vp := get_viewport_rect().size
	if vp.x < 1.0 or vp.y < 1.0:
		return
	var z: float = minf(vp.x / ws.x, vp.y / ws.y) * 0.98
	cam.zoom = Vector2(z, z)
	cam.position = ws * 0.5


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	top_bar = Label.new()
	top_bar.position = Vector2(12, 8)
	top_bar.add_theme_font_size_override("font_size", 13)
	top_bar.add_theme_color_override("font_color", TEXT)
	layer.add_child(top_bar)

	var hint := Label.new()
	hint.text = "drag to pan · wheel to zoom · click a fortress"
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", TEXT_DIM)
	hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hint.position = Vector2(-140, -26)
	layer.add_child(hint)

	# debug speed row — debug controls are first-class
	var row := HBoxContainer.new()
	row.position = Vector2(12, 870)
	row.add_theme_constant_override("separation", 6)
	layer.add_child(row)
	var lab := Label.new()
	lab.text = "SPEED"
	lab.add_theme_font_size_override("font_size", 11)
	lab.add_theme_color_override("font_color", TEXT_DIM)
	row.add_child(lab)
	for spd in [1.0, 10.0, 60.0]:
		var b := Button.new()
		b.text = "×%d" % int(spd)
		b.add_theme_font_size_override("font_size", 11)
		b.pressed.connect(func(): Game.time_scale = spd; _show_toast("sim speed ×%d" % int(spd)))
		row.add_child(b)

	toast = Label.new()
	toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	toast.position = Vector2(-260, 40)
	toast.custom_minimum_size = Vector2(520, 0)
	toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast.add_theme_font_size_override("font_size", 15)
	toast.add_theme_color_override("font_color", AMBER)
	toast.modulate.a = 0.0
	layer.add_child(toast)

	victory_label = Label.new()
	victory_label.set_anchors_preset(Control.PRESET_CENTER)
	victory_label.position = Vector2(-400, -60)
	victory_label.custom_minimum_size = Vector2(800, 0)
	victory_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	victory_label.add_theme_font_size_override("font_size", 30)
	victory_label.add_theme_color_override("font_color", GREEN)
	victory_label.visible = false
	layer.add_child(victory_label)

	# sidebar
	sidebar = PanelContainer.new()
	sidebar.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	sidebar.offset_left = -338.0
	var style := StyleBoxFlat.new()
	style.bg_color = Color("141417ee")
	style.border_color = Color("2a2a30")
	style.set_border_width_all(1)
	style.set_content_margin_all(16)
	sidebar.add_theme_stylebox_override("panel", style)
	sidebar.visible = false
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	sidebar.add_child(vb)
	sb_title = Label.new()
	sb_title.add_theme_font_size_override("font_size", 22)
	sb_title.add_theme_color_override("font_color", TEXT)
	vb.add_child(sb_title)
	sb_sub = Label.new()
	sb_sub.add_theme_font_size_override("font_size", 11)
	sb_sub.add_theme_color_override("font_color", TEXT_DIM)
	vb.add_child(sb_sub)
	sb_desc = Label.new()
	sb_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sb_desc.add_theme_font_size_override("font_size", 13)
	sb_desc.add_theme_color_override("font_color", Color("aaaab8"))
	vb.add_child(sb_desc)
	vb.add_child(HSeparator.new())
	sb_stats = Label.new()
	sb_stats.add_theme_font_size_override("font_size", 14)
	sb_stats.add_theme_color_override("font_color", TEXT)
	vb.add_child(sb_stats)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(spacer)
	sb_button = Button.new()
	sb_button.custom_minimum_size = Vector2(0, 44)
	sb_button.add_theme_font_size_override("font_size", 15)
	sb_button.pressed.connect(_on_action)
	vb.add_child(sb_button)
	layer.add_child(sidebar)

	confirm = ConfirmationDialog.new()
	confirm.dialog_text = "Vei waits at the heart of her domain.\nBegin the final confrontation?"
	confirm.ok_button_text = "Begin"
	confirm.confirmed.connect(func(): finished.emit({"teleport_to": "vei"}))
	layer.add_child(confirm)


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton:
		if e.button_index == MOUSE_BUTTON_WHEEL_UP and e.pressed:
			_zoom_at(1.13, e.position)
		elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN and e.pressed:
			_zoom_at(1.0 / 1.13, e.position)
		elif e.button_index == MOUSE_BUTTON_LEFT:
			if e.pressed:
				_pressed = true
				_panning = false
				_press_pos = e.position
			else:
				if _pressed and not _panning:
					_click_select(e.position)
				_pressed = false
	elif e is InputEventMouseMotion and _pressed:
		if not _panning and (e.position - _press_pos).length() > 6.0:
			_panning = true
		if _panning:
			cam.position -= e.relative / cam.zoom.x


func _zoom_at(factor: float, screen_pos: Vector2) -> void:
	var before := _to_world(screen_pos)
	var z: float = clampf(cam.zoom.x * factor, 0.3, 3.0)
	cam.zoom = Vector2(z, z)
	var after := _to_world(screen_pos)
	cam.position += before - after


func _to_world(screen_pos: Vector2) -> Vector2:
	return (screen_pos - get_viewport_rect().size * 0.5) / cam.zoom.x + cam.position


func _click_select(screen_pos: Vector2) -> void:
	if sidebar.visible and screen_pos.x > get_viewport_rect().size.x - 338.0:
		return
	var wp := _to_world(screen_pos)
	var realm: RealmSim = Game.realm
	var best_id := ""
	var best_d := 1e9
	var candidates: Array = [["covington", realm.cov_pos, 30.0], ["vei", realm.vei_pos, 60.0]]
	for f in realm.forts:
		candidates.append([f["id"], f["pos"], nodes_view.fort_radius(int(f["tier"])) + 10.0])
	for tw in Game.towns:
		candidates.append([tw["id"], tw["pos"], 14.0])
	for c in candidates:
		var d: float = wp.distance_to(c[1])
		if d < c[2] and d < best_d:
			best_d = d
			best_id = c[0]
	selected_id = best_id
	nodes_view.selected_id = best_id
	sidebar.visible = best_id != ""
	if best_id != "":
		_refresh_sidebar()


func _process(delta: float) -> void:
	_ui_acc += delta
	if _toast_t > 0.0:
		_toast_t -= delta
		toast.modulate.a = clampf(_toast_t / 0.8, 0.0, 1.0)
	if _ui_acc < 0.25:
		return
	_ui_acc = 0.0
	var g: Dictionary = Game.res
	top_bar.text = "GOLD %d   MATERIALS %d   BODIES %d   TOWNSFOLK %d   ARMY %d soldiers / %d elites   QUALITY %.2f%s" % [
		int(g["gold"]), int(g["materials"]), int(g["bodies"]), int(g["townsfolk"]),
		Game.army["soldier"], Game.army["elite"], Game.quality(),
		"" if is_equal_approx(Game.time_scale, 1.0) else "   [×%d]" % int(Game.time_scale)]
	if sidebar.visible:
		_refresh_sidebar()


func _refresh_sidebar() -> void:
	var realm: RealmSim = Game.realm
	sb_button.visible = true
	if selected_id == "covington":
		var w: Dictionary = ConfigDb.data.get("world", {}).get("covington", {})
		sb_title.text = "Covington"
		sb_sub.text = "HOME · THE FACTORY"
		sb_desc.text = str(w.get("desc", ""))
		sb_stats.text = "Minting %.1f undead/s\nSlabs %d · Vats %d · Forge L%d\nAssigned undead: %d · Idle: %d\nSimulacra afield: %d" % [
			realm.cov["r_out"], Game.town["slabs"], Game.town["vats"], Game.town["forge_level"],
			Game.assignments.values().reduce(func(a, b): return a + b, 0), Game.idle_undead,
			realm.simulacra.size()]
		sb_button.text = "ENTER COVINGTON"
		return
	if selected_id == "vei":
		var w2: Dictionary = ConfigDb.data.get("world", {}).get("vei", {})
		var ro: Dictionary = realm.readout()
		sb_title.text = "Vei's Domain"
		sb_sub.text = "THE GODDESS OF LIFE"
		sb_desc.text = str(w2.get("desc", ""))
		var diff: float = ro["differential"]
		sb_stats.text = "UNDEAD MASSED AT HER GATES\n    %d\n\nArriving %.1f /s\nShe digests %.1f /s\nDifferential %+.1f /s %s\n\nConfrontation odds %d%%" % [
			int(ro["massed"]), ro["inflow"], ro["capacity"], diff,
			"▲" if diff > 0.0 else "▼", int(ro["odds"] * 100.0)]
		sb_button.text = "BEGIN THE FINAL CONFRONTATION"
		return
	var f := realm.fort_by_id(selected_id)
	if not f.is_empty():
		sb_title.text = f["name"]
		sb_sub.text = "FORTRESS · TIER %d · CAPACITY %d" % [f["tier"], int(f["cap"])]
		sb_desc.text = f["desc"]
		var sim_rate := 0.0
		for s in realm.simulacra:
			if s["fort_id"] == selected_id:
				sim_rate = float(s["rate"])
		sb_stats.text = "LIVING  %4d\nUNDEAD  %4d\nDEAD    %4d\nEMPTY   %4d\n\nundead in %.1f/s · drain %.1f/s\nliving in %.1f/s · corpses out %.1f/s%s" % [
			int(f["living"]), int(f["undead"]), int(f["dead"]), int(realm.space(f)),
			f["r_in"], f["r_drain"], f["r_shipped"], f["r_dead_out"],
			"\nsimulacrum raising %.1f/s" % sim_rate if sim_rate > 0.0 else ""]
		sb_button.text = "TELEPORT"
		return
	for tw in Game.towns:
		if tw["id"] == selected_id:
			sb_title.text = tw["name"]
			sb_sub.text = "TOWN · POP %d" % int(tw["pop"])
			var ctl: String = tw["control"]
			sb_desc.text = "A small blue town. Relish cannot visit; she can only watch its lights.\n\n" + (
				"Under the necrosis, its people drift to Covington." if ctl == "green"
				else ("Held fast by Vei's living." if ctl == "orange" else "Contested ground. Nobody sleeps well."))
			sb_stats.text = "Control: %s\nGreen towns feed Covington:\n+%.3f townsfolk/s each" % [
				ctl.to_upper(), float(ConfigDb.v("realm", "migrant_rate_per_town", 0.012))]
			sb_button.visible = false
			return


func _on_action() -> void:
	if selected_id == "vei":
		confirm.popup_centered()
		return
	if selected_id != "":
		finished.emit({"teleport_to": selected_id})


func _show_toast(msg: String) -> void:
	toast.text = msg
	_toast_t = 3.0
	toast.modulate.a = 1.0


func _on_respawn(with_vat: bool) -> void:
	if with_vat:
		_show_toast("A clone vat hisses open. Relish walks again.")
	else:
		_show_toast("No vat waited. The army scattered while her body re-knit.")


func _on_victory() -> void:
	victory_label.text = "VEI HAS DROWNED IN THE DEAD\nThe realm is quiet. The factory hums on."
	victory_label.visible = true
