extends Node
## Entry point: routes between menu / full raid / playrooms, owns the debug
## panel, and forwards unhandled input to the active mode (trance first — the
## thumb belongs to the circle, §15.7).

const PLAYROOM_NAMES := [
	["trance_gym", "Trance Gym — the circle, alone (§12 step 1 gate)"],
	["force_field", "Force Field — magnetism, charm & dread"],
	["targeting", "Targeting — wits vs proximity×size"],
	["sacrifice", "Sacrifice — the chain that guards Relish"],
	["command", "Command — lasso, tap, hold vs drift"],
	["obstacles", "Obstacle Course — pathing & lasso-paths"],
]

const PLAYROOM_SCRIPTS := {
	"trance_gym": preload("res://scripts/playrooms/room_trance_gym.gd"),
	"force_field": preload("res://scripts/playrooms/room_force_field.gd"),
	"targeting": preload("res://scripts/playrooms/room_targeting.gd"),
	"sacrifice": preload("res://scripts/playrooms/room_sacrifice.gd"),
	"command": preload("res://scripts/playrooms/room_command.gd"),
	"obstacles": preload("res://scripts/playrooms/room_obstacles.gd"),
}

var world: Node2D
var hud: Hud
var debug_panel: DebugPanel
var mode: Node = null
var mode_id := ""
var place_spawn: Variant = null  # {id, count} armed by the debug panel

func _ready() -> void:
	add_to_group("rr_main")
	world = Node2D.new()
	world.name = "World"
	add_child(world)
	hud = Hud.new()
	add_child(hud)
	debug_panel = DebugPanel.new()
	debug_panel.main = self
	add_child(debug_panel)
	hud.start_raid_pressed.connect(start_raid)
	hud.playroom_pressed.connect(start_playroom)
	hud.menu_pressed.connect(show_menu)
	# Debug comfort knob: scales world + UI together (HiDPI desktops render the
	# portrait canvas small). stats.json: debug_ui_scale, editable live in DBG.
	ConfigDb.value_changed.connect(func(_f, _k, _v): _apply_ui_scale())
	_apply_ui_scale()
	show_menu()

func _apply_ui_scale() -> void:
	get_window().content_scale_factor = clampf(float(ConfigDb.v("stats", "debug_ui_scale")), 0.5, 3.0)

func show_menu() -> void:
	_clear_mode()
	hud.show_menu(PLAYROOM_NAMES)

func start_raid() -> void:
	_clear_mode()
	GameState.reset_run()
	var rd := RaidDirector.new()
	mode = rd
	mode_id = "raid"
	world.add_child(rd)
	rd.raid_won.connect(_on_raid_won)
	rd.raid_lost.connect(_on_raid_lost)
	rd.chamber_changed.connect(hud.set_chamber)
	rd.boss_engaged.connect(hud.bind_boss)
	rd.battlefield.no_chaff_warning.connect(hud.warn_no_chaff)
	hud.enter_gameplay(rd.trance)

func start_playroom(id: String) -> void:
	_clear_mode()
	GameState.reset_run()  # telemetry/score history reads per-room
	var room: PlayroomBase = PLAYROOM_SCRIPTS[id].new()
	mode = room
	mode_id = id
	world.add_child(room)
	room.battlefield.no_chaff_warning.connect(hud.warn_no_chaff)
	hud.enter_gameplay(room.trance)

func reset_room() -> void:
	if mode_id == "raid":
		start_raid()
	elif mode_id != "":
		start_playroom(mode_id)

func _on_raid_won() -> void:
	hud.show_haul()
	_clear_mode()

func _on_raid_lost() -> void:
	hud.show_death()        # summarizes what is about to be wiped
	GameState.total_wipe()  # §8.3: one deletion path
	_clear_mode()

func _clear_mode() -> void:
	Engine.time_scale = 1.0
	place_spawn = null
	if mode != null:
		mode.queue_free()
		mode = null
		mode_id = ""
	hud.exit_gameplay()

# ---- Input routing ----

func _unhandled_input(ev: InputEvent) -> void:
	if mode == null or hud.screens_open():
		return
	if ev is InputEventScreenTouch and ev.pressed:
		if _point_on_ui(ev.position):
			return
		if place_spawn != null:
			var bf: Battlefield = mode.battlefield
			debug_spawn(place_spawn["id"], place_spawn["count"], bf.screen_to_world(ev.position))
			place_spawn = null
			return
	# Raw mouse events must flow too: touch emulation only covers the LEFT
	# button, and the right-mouse trance binding lives on raw mouse events.
	if ev is InputEventMouseButton and ev.pressed and _point_on_ui(ev.position):
		return
	if ev is InputEventScreenTouch or ev is InputEventScreenDrag or ev is InputEventKey \
			or ev is InputEventMouseButton or ev is InputEventMouseMotion:
		mode.handle_input(ev)

func _point_on_ui(p: Vector2) -> bool:
	for c in get_tree().get_nodes_in_group("rr_ui_block"):
		if c is Control and c.is_visible_in_tree() and c.get_global_rect().has_point(p):
			return true
	return false

# ---- Debug spawning ----

func arm_place_spawn(id: String, count: int) -> void:
	place_spawn = {"id": id, "count": count}

func debug_spawn(id: String, count: int, at: Variant) -> void:
	if mode == null or not "battlefield" in mode or mode.battlefield == null:
		return
	var bf: Battlefield = mode.battlefield
	var center: Vector2 = at if at != null else bf.camera.position
	for i in count:
		var pos := center + Vector2(bf.rng.randf_range(-50, 50), bf.rng.randf_range(-50, 50))
		if id == "chaff":
			bf.spawn_unit(EntityFactory.make_chaff(1.0), pos)
		elif id == "essence":
			bf.spawn_essence(pos, 1)
		elif id.begins_with("enemy: "):
			bf.spawn_unit(EntityFactory.make_enemy(id.trim_prefix("enemy: ")), pos)
		elif id.begins_with("permanent: "):
			var pname := id.trim_prefix("permanent: ")
			for spec in ConfigDb.data["loadout"]["permanents"]:
				if spec["name"] == pname:
					bf.spawn_unit(EntityFactory.make_permanent(spec), pos)
					break
