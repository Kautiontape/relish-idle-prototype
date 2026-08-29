extends Node
## Debug/screenshot harness.
## CLI: godot --path . -- --shot=/abs/out.png [--scene=res://scenes/X.tscn] [--frames=40] [--clicks=x,y;x,y]
## In-game: F12 saves a screenshot to user://shot_<n>.png.

var _shot_path := ""
var _frames := 40
var _scene := ""
var _clicks: Array = []
var _trace := Vector3.ZERO  # cx, cy, radius — synthetic trance circle
var _finish_raid := false   # emit a canned raid result through the real path
var consumed_teleport := false  # world_map's --teleport arg fires only once per run
var _n := 0


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shot="):
			_shot_path = arg.trim_prefix("--shot=")
		elif arg.begins_with("--frames="):
			_frames = int(arg.trim_prefix("--frames="))
		elif arg.begins_with("--scene="):
			_scene = arg.trim_prefix("--scene=")
		elif arg.begins_with("--speed="):
			Game.time_scale = float(arg.trim_prefix("--speed="))
		elif arg == "--cheat=boss":
			Game.army = {"soldier": 40, "elite": 8}
			Game.town["forge_level"] = 4
			Game.realm.vei["undead_queue"] = 18000.0
		elif arg == "--finish-raid":
			_finish_raid = true
		elif arg == "--cheat=rich":
			Game.res["gold"] = 500.0
			Game.res["materials"] = 200.0
			Game.res["bodies"] = 60.0
			Game.idle_undead = 20
		elif arg.begins_with("--clicks="):
			for pair in arg.trim_prefix("--clicks=").split(";"):
				var xy := pair.split(",")
				if xy.size() == 2:
					_clicks.append(Vector2(float(xy[0]), float(xy[1])))
		elif arg.begins_with("--trace="):
			var t3 := arg.trim_prefix("--trace=").split(",")
			if t3.size() == 3:
				_trace = Vector3(float(t3[0]), float(t3[1]), float(t3[2]))
	if _shot_path != "":
		print("SHOT_BOOT frames=", _frames, " scene=", _scene)
		_run.call_deferred()


func _run() -> void:
	if _scene != "":
		get_tree().change_scene_to_file(_scene)
		await get_tree().process_frame
		await get_tree().process_frame
	for c in _clicks:
		await _click(c)
		for i in 10:
			await get_tree().process_frame
	if _trace != Vector3.ZERO:
		await _do_trace(Vector2(_trace.x, _trace.y), _trace.z)
	if _finish_raid:
		for i in 20:
			await get_tree().process_frame
		var main := get_node_or_null("/root/Main")
		if main != null and main.get("current") != null and main.current.has_signal("finished"):
			var fid: String = Game.raiding_fort_id()
			main.current.finished.emit({
				"fort_id": fid, "killed_living_mass": 42.0, "raised_chaff_mass": 26.0,
				"raised_soldiers": 3, "raised_elites": 1, "good_mass": 9.0,
				"garrison_mass": 12.0, "relish_died": false, "aborted": false,
			})
			print("FINISH_RAID emitted for ", fid)
		for i in 20:
			await get_tree().process_frame
	for i in _frames:
		await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.save_png(_shot_path)
	print("SHOT_SAVED ", _shot_path)
	get_tree().quit()


func _do_trace(c: Vector2, r: float) -> void:
	var space := InputEventKey.new()
	space.keycode = KEY_SPACE
	space.physical_keycode = KEY_SPACE
	space.pressed = true
	Input.parse_input_event(space)
	for i in 12:
		await get_tree().process_frame
	var start := c + Vector2(r, 0)
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = start
	down.global_position = start
	Input.parse_input_event(down)
	await get_tree().process_frame
	var steps := 44
	var prev := start
	for i in range(1, steps + 1):
		var ang := TAU * float(i) / steps
		var p := c + Vector2(cos(ang), sin(ang)) * r
		var mo := InputEventMouseMotion.new()
		mo.position = p
		mo.global_position = p
		mo.relative = p - prev
		mo.button_mask = MOUSE_BUTTON_MASK_LEFT
		prev = p
		Input.parse_input_event(mo)
		await get_tree().process_frame
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = prev
	up.global_position = prev
	Input.parse_input_event(up)
	await get_tree().process_frame
	var space_up := InputEventKey.new()
	space_up.keycode = KEY_SPACE
	space_up.physical_keycode = KEY_SPACE
	space_up.pressed = false
	Input.parse_input_event(space_up)
	print("TRACE_DONE center=", c, " r=", r)


func _click(pos: Vector2) -> void:
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = pos
	down.global_position = pos
	Input.parse_input_event(down)
	await get_tree().process_frame
	var up := down.duplicate()
	up.pressed = false
	Input.parse_input_event(up)
	await get_tree().process_frame


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_F12:
		_n += 1
		var img := get_viewport().get_texture().get_image()
		var p := "user://shot_%d.png" % _n
		img.save_png(p)
		print("SHOT_SAVED ", ProjectSettings.globalize_path(p))
