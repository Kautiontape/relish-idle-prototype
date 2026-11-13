extends Sprite2D
## The map ground. Three modes, switchable live with F7 so they can be compared
## in the same state (configs/ground.json "mode", or --ground=flow|old|off):
##   flow: a GPU flow field of thousands of advected streaks driven by
##         Game.field (scripts/map/flow_ground.gd). The flow-spike ground.
##   old:  the original renderer. Game.field baked to a 128×90 texture on the
##         CPU at ~6 Hz, drawn through shaders/map_field.gdshader.
##   off:  no ground, to show what the ground itself costs.
## Reduced motion is the one game-wide flag, Pulse.reduced_motion (F8, or
## -- --reduced-motion); the ground polls it and follows. The tempo is Pulse's.
## Debug keys: F5 vsync, F6 reload configs, F7 cycle mode, F9 greyscale check.
## CLI: --ground=, --vsync=off, --streaks=N, --greyscale, --ground-only (hide
## routes and nodes, for contrast measurement), --zoom=Z and --focus=x,y (set
## the map camera after it fits, for captures), and the --bench-* args in
## ground_meter.gd.

const FLOW_SCRIPT := preload("res://scripts/map/flow_ground.gd")
const METER_SCRIPT := preload("res://scripts/map/ground_meter.gd")
const OLD_SHADER := preload("res://shaders/map_field.gdshader")
const COMPOSITE_SHADER := preload("res://shaders/flow_composite.gdshader")
const GREY_SHADER := preload("res://shaders/greyscale_check.gdshader")
const MODES := ["flow", "old", "off"]

# old ground palette (unchanged from the original view)
const GREEN_BASE := Color("103a28")
const GREEN_HOT := Color("39ff9e")
const GREEN_CORE := Color("c9ffe8")
const ORANGE_BASE := Color("3a1608")
const ORANGE_HOT := Color("ff6a2b")
const ORANGE_CORE := Color("ffd6b0")
const FRONT := Color("ff2d55")

var mode := "flow"

var _cfg := {}
var _streak_override := 0
var _flow: Node = null
var _meter: CanvasLayer
var _grey: CanvasLayer
var _comp_mat: ShaderMaterial
var _old_mat: ShaderMaterial
var _img: Image
var _tex: ImageTexture
var _acc := 1.0
var _cpu_ms := 0.0
var _reduced_applied := false


func _ready() -> void:
	centered = false
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_cfg = ConfigDb.data.get("ground", {})
	mode = str(_cfg.get("mode", "flow"))
	_reduced_applied = Pulse.reduced_motion
	var grey := false
	var zoom := 0.0
	var focus := Vector2(-1, -1)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--ground="):
			mode = a.trim_prefix("--ground=")
		elif a.begins_with("--zoom="):
			zoom = float(a.trim_prefix("--zoom="))
		elif a.begins_with("--focus="):
			var xy := a.trim_prefix("--focus=").split(",")
			if xy.size() == 2:
				focus = Vector2(float(xy[0]), float(xy[1]))
		elif a == "--vsync=off":
			_set_vsync(false)
		elif a.begins_with("--streaks="):
			_streak_override = int(a.trim_prefix("--streaks="))
		elif a == "--greyscale":
			grey = true
		elif a == "--ground-only":
			set_bare.call_deferred(true)
	_old_mat = ShaderMaterial.new()
	_old_mat.shader = OLD_SHADER
	_comp_mat = ShaderMaterial.new()
	_comp_mat.shader = COMPOSITE_SHADER
	_meter = METER_SCRIPT.new()
	_meter.view = self
	add_child(_meter)
	_meter.visible = bool(_cfg.get("readout", true))
	_grey = CanvasLayer.new()
	_grey.layer = 100
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var gm := ShaderMaterial.new()
	gm.shader = GREY_SHADER
	rect.material = gm
	_grey.add_child(rect)
	_grey.visible = grey
	add_child(_grey)
	set_mode(mode)
	if zoom > 0.0 or focus.x >= 0.0:
		_set_camera_after_fit(zoom, focus)


## Debug captures: world_map fits its camera one frame after _ready; wait past
## that, then set zoom and/or centre. No effect on play.
func _set_camera_after_fit(zoom: float, focus: Vector2) -> void:
	for i in 3:
		await get_tree().process_frame
	var cam := get_viewport().get_camera_2d()
	if cam == null:
		return
	if zoom > 0.0:
		cam.zoom = Vector2(zoom, zoom)
	if focus.x >= 0.0:
		cam.position = focus


## Analysis captures: hide routes and nodes so only ground pixels remain.
## Called deferred from _ready because world_map adds them after this node.
func set_bare(on: bool) -> void:
	for sib in get_parent().get_children():
		if sib != self and sib is CanvasItem:
			(sib as CanvasItem).visible = not on


func set_mode(m: String) -> void:
	mode = m if m in MODES else "flow"
	if _flow != null and mode != "flow":
		remove_child(_flow)
		_flow.free()
		_flow = null
	var f: InfluenceField = Game.field
	match mode:
		"flow":
			if _flow == null:
				_flow = FLOW_SCRIPT.new()
				add_child(_flow)
				_flow.setup(_cfg, Pulse.reduced_motion, _streak_override)
				_reduced_applied = Pulse.reduced_motion
			texture = _flow.texture()
			scale = Vector2(f.world_size.x / _flow.trail_size.x, f.world_size.y / _flow.trail_size.y)
			_comp_mat.set_shader_parameter("gain", float(_cfg.get("composite_gain", 1.25)))
			material = _comp_mat
			visible = true
		"old":
			if _img == null:
				_img = Image.create(f.w, f.h, false, Image.FORMAT_RGBA8)
				_tex = ImageTexture.create_from_image(_img)
			texture = _tex
			scale = Vector2(f.world_size.x / f.w, f.world_size.y / f.h)
			material = _old_mat
			visible = true
			_acc = 1.0
		"off":
			texture = null
			visible = false
	_cpu_ms = 0.0


## Follow Pulse.reduced_motion (polled: Pulse has no signal for it).
func _sync_reduced() -> void:
	if Pulse.reduced_motion == _reduced_applied:
		return
	_reduced_applied = Pulse.reduced_motion
	if _flow != null:
		_flow.set_reduced(_reduced_applied)


func set_grey(on: bool) -> void:
	_grey.visible = on


func is_grey() -> bool:
	return _grey.visible


func detail() -> String:
	match mode:
		"flow":
			return "%d streaks · trail %dx%d HDR" % [_flow.streak_count(), _flow.trail_size.x, _flow.trail_size.y]
		"old":
			return "%dx%d CPU texture @6 Hz" % [Game.field.w, Game.field.h]
	return "no ground"


func trail_rid() -> RID:
	return _flow.viewport_rid() if _flow != null else RID()


## GDScript time the ground spent this frame (old: the per-cell bake; flow:
## the field texture upload). The GPU side is in the viewport timings.
func cpu_ms() -> float:
	if mode == "flow" and _flow != null:
		return _flow.last_cpu_ms
	return _cpu_ms


## Off also lifts any fps cap (e.g. --max-fps), so frame time shows real cost.
func _set_vsync(on: bool) -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if on else DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.keycode:
		KEY_F5:
			_set_vsync(DisplayServer.window_get_vsync_mode() == DisplayServer.VSYNC_DISABLED)
		KEY_F6:
			ConfigDb.reload()
			_cfg = ConfigDb.data.get("ground", {})
			if _flow != null:
				var want: int = _streak_override if _streak_override > 0 else int(_cfg.get("streaks", 9000))
				if want != _flow.streak_count() or not is_equal_approx(
						float(_cfg.get("trail_scale", 0.62)), _flow.trail_size.x / Game.field.world_size.x):
					set_mode("off")
					set_mode("flow")
				else:
					_flow.apply_config(_cfg)
					_comp_mat.set_shader_parameter("gain", float(_cfg.get("composite_gain", 1.25)))
		KEY_F7:
			set_mode(MODES[(MODES.find(mode) + 1) % MODES.size()])
		KEY_F9:
			set_grey(not is_grey())
		_:
			return
	get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	_sync_reduced()
	if mode != "old":
		return
	_cpu_ms = 0.0
	_acc += delta
	if _acc < 0.16:
		return
	_acc = 0.0
	var t0 := Time.get_ticks_usec()
	_bake_old()
	_cpu_ms = (Time.get_ticks_usec() - t0) / 1000.0


## The original ground, kept verbatim for comparison.
func _bake_old() -> void:
	var f: InfluenceField = Game.field
	var bytes := PackedByteArray()
	bytes.resize(f.w * f.h * 4)
	for i in f.w * f.h:
		var g := f.green[i]
		var o := f.orange[i]
		var e := f.entrench[i]
		var col := Color(0, 0, 0, 0)
		if g > 0.03 or o > 0.03:
			if g >= o:
				var heat := clampf(g * 0.75, 0.0, 1.0)
				col = GREEN_BASE.lerp(GREEN_HOT, heat)
				if e > 0.2:
					col = col.lerp(GREEN_CORE, clampf(e * 0.28, 0.0, 0.5))
				col.a = clampf(g * 0.55, 0.0, 0.8)
			else:
				var heat2 := clampf(o * 0.75, 0.0, 1.0)
				col = ORANGE_BASE.lerp(ORANGE_HOT, heat2)
				if e < -0.2:
					col = col.lerp(ORANGE_CORE, clampf(-e * 0.28, 0.0, 0.5))
				col.a = clampf(o * 0.55, 0.0, 0.8)
			if minf(g, o) > 0.1:
				col = col.lerp(FRONT, 0.3)
				col.a = maxf(col.a, 0.45)
		var j := i * 4
		bytes[j] = int(col.r * 255.0)
		bytes[j + 1] = int(col.g * 255.0)
		bytes[j + 2] = int(col.b * 255.0)
		bytes[j + 3] = int(col.a * 255.0)
	_img.set_data(f.w, f.h, false, Image.FORMAT_RGBA8, bytes)
	_tex.update(_img)
