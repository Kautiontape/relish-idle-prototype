extends Control
## The Realm view: the scene root. Builds the world (ground, routes, nodes, camera) and the UI
## layer (HUD, sidebar), owns the shared MapModel, and exits only via finished(result).
## Reads views through the model and sends commands through GameState; nothing else.

signal finished(result: Dictionary)

var world: Node2D
var cam: MapCamera
var nodes_view: MapNodes
var routes_view: MapRoutes
var callouts_view: MapCallouts
var model: MapModel
var hud: MapHud
var sidebar: MapSidebar

var selected_id := ""
var _ui_acc := 0.0
var _setup_called := false


func setup(_seed_data: Dictionary) -> void:
	_setup_called = true


func demo_seed() -> Dictionary:
	return {}


func _ready() -> void:
	# The root Control sits under the Camera2D's canvas transform (world space), so it takes no
	# input; the map's input comes through _unhandled_input in screen space.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	MapLogic.configure(ConfigDb.data.get("map_view", {}))
	model = MapModel.new(Game.state)
	model.demo = Game.state.debug_enabled and OS.get_cmdline_user_args().has("--lanes=demo")
	model.nodes_demo = Game.state.debug_enabled and OS.get_cmdline_user_args().has("--nodes=demo")
	model.flip_cfg = ConfigDb.data.get("realm", {}).get("flip", {})
	model.refresh(true)
	_build_world()
	_build_ui()
	await get_tree().process_frame
	if not is_inside_tree():
		return
	cam.fit(get_viewport_rect().size)
	hud.start()
	_replay_clicks()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--select="):
			_select(arg.trim_prefix("--select="))
		elif arg.begins_with("--teleport=") and not Shot.consumed_teleport:
			Shot.consumed_teleport = true
			var dest := arg.trim_prefix("--teleport=")
			Game.state.cmd_debug_set_state({"relish_at": dest})
			await get_tree().create_timer(0.3).timeout
			if is_inside_tree():
				finished.emit({"v": 2, "teleport_to": dest})


func _build_world() -> void:
	world = Node2D.new()
	world.name = "World"
	add_child(world)
	var field := Sprite2D.new()
	field.set_script(load("res://scripts/map/map_field_view.gd"))
	world.add_child(field)
	routes_view = MapRoutes.new()
	routes_view.model = model
	world.add_child(routes_view)
	nodes_view = MapNodes.new()
	nodes_view.model = model
	nodes_view.routes = routes_view
	world.add_child(nodes_view)
	cam = MapCamera.new()
	cam.name = "Camera2D"
	cam.model = model
	callouts_view = MapCallouts.new()
	callouts_view.name = "Callouts"
	callouts_view.model = model
	callouts_view.cam = cam
	world.add_child(callouts_view)
	cam.clicked.connect(_on_clicked)
	world.add_child(cam)
	cam.make_current()


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	hud = MapHud.new()
	hud.model = model
	layer.add_child(hud)
	sidebar = MapSidebar.new()
	sidebar.model = model
	sidebar.act.connect(func(result: Dictionary): finished.emit(result))
	layer.add_child(sidebar)


## Pan, wheel zoom and click-select, in screen (viewport) coordinates. The HUD and the sidebar
## live in a CanvasLayer and take their own clicks first through the GUI, so anything that
## reaches here is on the bare map.
func _unhandled_input(e: InputEvent) -> void:
	cam.handle_input(e)


func _on_clicked(id: String) -> void:
	_select(id)


## Debug only: `--map-clicks=x,y;x,y` (screen px). Shot's own --clicks fire before the camera
## fit, so the map replays its own once the fit has settled, through the real input path.
func _replay_clicks() -> void:
	if not Game.state.debug_enabled:
		return
	var clicks: Array[Vector2] = []
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--map-clicks="):
			clicks.append_array(MapLogic.parse_clicks(arg.trim_prefix("--map-clicks=")))
	if clicks.is_empty():
		return
	await _frames(int(MapLogic.cfg()["map_clicks_wait_frames"]))
	for c in clicks:
		_inject_click(c, true)
		await _frames(1)
		_inject_click(c, false)
		await _frames(int(MapLogic.cfg()["map_clicks_gap_frames"]))


func _frames(n: int) -> void:
	for i in n:
		if not is_inside_tree():
			return
		await get_tree().process_frame


func _inject_click(pos: Vector2, pressed: bool) -> void:
	if not is_inside_tree():
		return
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = pressed
	e.position = pos
	e.global_position = pos
	e.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	Input.parse_input_event(e)


func _select(id: String) -> void:
	selected_id = id
	nodes_view.selected_id = id
	sidebar.select(id)


func _process(delta: float) -> void:
	model.refresh()
	hud.tick(delta)
	_ui_acc += delta
	if _ui_acc < float(MapLogic.cfg()["ui_refresh_s"]):
		return
	_ui_acc = 0.0
	hud.refresh()
	sidebar.refresh()
