extends SceneTree
## Probe: how does physics frame cost scale with unit count?
## Pacifist flag on — isolates movement/field/avoidance from combat.

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame
	for pair in [["ConfigDb", "res://scripts/autoload/config_db.gd"],
			["GameState", "res://scripts/autoload/game_state.gd"],
			["EntityFactory", "res://scripts/autoload/entity_factory.gd"]]:
		if root.get_node_or_null(NodePath(pair[0])) == null:
			var n: Node = (load(pair[1]) as GDScript).new()
			n.name = pair[0]
			root.add_child(n)
	var gs: Node = root.get_node(^"GameState")

	var main_scene: Node = (load("res://scripts/main.gd") as GDScript).new()
	root.add_child(main_scene)
	await process_frame
	main_scene.start_raid()
	gs.debug.pacifist = true
	for i in 30:
		await physics_frame

	var bf: Node2D = main_scene.mode.battlefield
	await _sample(bf, "baseline")
	for extra in [60, 120, 240]:
		main_scene.debug_spawn("chaff", extra - bf.count_kind(2) + 5, bf.relish.global_position + Vector2(0, -200))
		for i in 30:
			await physics_frame
		await _sample(bf, "+%d chaff" % extra)
	quit(0)

func _sample(bf: Node2D, label: String) -> void:
	var phys := 0.0
	var proc := 0.0
	const FRAMES := 90
	for i in FRAMES:
		await physics_frame
		phys += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
		proc += Performance.get_monitor(Performance.TIME_PROCESS)
	print("%s: %d units | physics %.2f ms/frame | process %.2f ms/frame | %d nodes" % [label,
		bf.all_units().size(), 1000.0 * phys / FRAMES, 1000.0 * proc / FRAMES,
		Performance.get_monitor(Performance.OBJECT_NODE_COUNT)])
