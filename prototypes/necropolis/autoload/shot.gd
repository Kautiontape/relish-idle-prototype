extends Node
## Debug/screenshot harness.
## CLI: godot --path . -- --shot=/abs/out.png [--scene=res://scenes/X.tscn] [--frames=40] [--clicks=x,y;x,y]
## In-game: F12 saves a screenshot to user://shot_<n>.png.

var _shot_path := ""
var _frames := 40
var _scene := ""
var _clicks: Array = []
var _n := 0


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shot="):
			_shot_path = arg.trim_prefix("--shot=")
		elif arg.begins_with("--frames="):
			_frames = int(arg.trim_prefix("--frames="))
		elif arg.begins_with("--scene="):
			_scene = arg.trim_prefix("--scene=")
		elif arg.begins_with("--clicks="):
			for pair in arg.trim_prefix("--clicks=").split(";"):
				var xy := pair.split(",")
				if xy.size() == 2:
					_clicks.append(Vector2(float(xy[0]), float(xy[1])))
	if _shot_path != "":
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
	for i in _frames:
		await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.save_png(_shot_path)
	print("SHOT_SAVED ", _shot_path)
	get_tree().quit()


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
