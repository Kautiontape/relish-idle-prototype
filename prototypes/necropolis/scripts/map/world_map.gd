extends Control
## The Realm view: the scene root. Builds the world (ground, routes, nodes, camera) and the UI
## layer (HUD, sidebar), owns the shared MapModel, and exits only via finished(result).
## Reads views through the model and sends commands through GameState; nothing else.

signal finished(result: Dictionary)

var world: Node2D
var cam: MapCamera
var nodes_view: Node2D
var routes_view: Node2D
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
	mouse_filter = Control.MOUSE_FILTER_STOP
	MapLogic.configure(ConfigDb.data.get("map_view", {}))
	model = MapModel.new(Game.state)
	model.demo = Game.state.debug_enabled and OS.get_cmdline_user_args().has("--lanes=demo")
	model.refresh(true)
	_build_world()
	_build_ui()
	await get_tree().process_frame
	if not is_inside_tree():
		return
	cam.fit(get_viewport_rect().size)
	hud.start()
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
	routes_view = Node2D.new()
	routes_view.set_script(load("res://scripts/map/map_routes.gd"))
	routes_view.model = model
	world.add_child(routes_view)
	nodes_view = Node2D.new()
	nodes_view.set_script(load("res://scripts/map/map_nodes.gd"))
	nodes_view.model = model
	world.add_child(nodes_view)
	cam = MapCamera.new()
	cam.name = "Camera2D"
	cam.model = model
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


func _gui_input(e: InputEvent) -> void:
	cam.handle_input(e)


func _on_clicked(id: String) -> void:
	if sidebar.covers(get_global_mouse_position()):
		return
	_select(id)


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
