extends Sprite2D
## The map ground. Three modes, switchable live with F7 so they can be compared
## in the same state (configs/ground.json "mode", or --ground=flow|old|off):
##   flow: a GPU flow field of thousands of advected streaks driven by the
##         sim's influence field (view_field; scripts/map/flow_ground.gd).
##   old:  the original renderer. The field baked to a 128×90 texture on the
##         CPU at ~6 Hz, drawn through shaders/map_field.gdshader.
##   off:  no ground, to show what the ground itself costs.
## Reduced motion is the one game-wide flag, Pulse.reduced_motion (F8, or
## -- --reduced-motion); the ground polls it and follows. The tempo is Pulse's.
## Debug keys: F5 vsync, F6 reload configs, F7 cycle mode, F9 greyscale check.
## The frame-time readout (ground_meter.gd) shows only in debug sessions with
## ground.json "readout" on (IDLE I9: debug tools stay out of release).
## CLI: --ground=, --vsync=off, --streaks=N, --greyscale, --ground-only (hide
## routes and nodes, for contrast measurement), --zoom=Z and --focus=x,y (set
## the map camera after it fits, for captures), --pan-test=S (sweep the camera
## sideways at S screen px/s, to check and time pans), and the --bench-* args
## in ground_meter.gd.

const FLOW_SCRIPT := preload("res://scripts/map/flow_ground.gd")
const METER_SCRIPT := preload("res://scripts/map/ground_meter.gd")
const OLD_SHADER := preload("res://shaders/map_field.gdshader")
const GREY_SHADER := preload("res://shaders/greyscale_check.gdshader")
const MODES := ["flow", "old", "off"]

var mode := "flow"

var _cfg := {}
var _streak_override := 0
var _flow: Node = null
var _meter: CanvasLayer
var _grey: CanvasLayer
var _old_mat: ShaderMaterial
var _img: Image
var _tex: ImageTexture
var _acc := 1.0
var _cpu_ms := 0.0
var _reduced_applied := false
var _pan_test := 0.0
var _pan_dir := 1.0
var _old_cols := {}  # the old ground's palette: the canon hues, bases darkened (old_base_darken)


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
		elif a.begins_with("--pan-test="):
			_pan_test = float(a.trim_prefix("--pan-test="))
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
	_meter = METER_SCRIPT.new()
	_meter.view = self
	add_child(_meter)
	_sync_meter()
	var dk := float(_cfg.get("old_base_darken", 0.77))
	_old_cols = {
		"green_base": Palette.c("undead").darkened(dk), "green_hot": Palette.c("undead"),
		"green_core": Palette.c("undead_core"), "orange_base": Palette.c("living").darkened(dk),
		"orange_hot": Palette.c("living"), "orange_core": Palette.c("living_core"),
		"front": Palette.c("danger"), "clear": Palette.c("void", 0.0),
	}
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


func _sync_meter() -> void:
	_meter.visible = Game.state.debug_enabled and bool(_cfg.get("readout", false))


func _field() -> InfluenceField:
	return Game.state.view_field()["field"]


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
	var f := _field()
	match mode:
		"flow":
			if _flow == null:
				_flow = FLOW_SCRIPT.new()
				add_child(_flow)
				_flow.setup(_cfg, Pulse.reduced_motion, _streak_override)
				_reduced_applied = Pulse.reduced_motion
			# the flow ground draws itself on a screen-space layer under the map
			texture = null
			material = null
			scale = Vector2.ONE
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
			return "%d/%d streaks · trail %dx%d HDR, follows camera · zoom %.2f" % [_flow.active_streaks(),
				_flow.streak_count(), _flow.trail_size.x, _flow.trail_size.y, _flow.zoom]
		"old":
			return "%dx%d CPU texture @6 Hz" % [_field().w, _field().h]
	return "no ground"


func trail_rid() -> RID:
	return _flow.viewport_rid() if _flow != null else RID()


func history_rid() -> RID:
	return _flow.history_rid() if _flow != null else RID()


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
			_sync_meter()
			if _flow != null:
				var want: int = _streak_override if _streak_override > 0 else int(_cfg.get("streaks", 9000))
				var want_size := Vector2i((get_viewport().get_visible_rect().size
						* float(_cfg.get("trail_screen_scale", 1.0))).round())
				if want != _flow.streak_count() or want_size != _flow.trail_size:
					set_mode("off")
					set_mode("flow")
				else:
					_flow.apply_config(_cfg)
		KEY_F7:
			set_mode(MODES[(MODES.find(mode) + 1) % MODES.size()])
		KEY_F9:
			set_grey(not is_grey())
		_:
			return
	get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	_sync_reduced()
	if _pan_test != 0.0:
		_pan_step(delta)
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


## Debug: sweep the camera across the world and back (--pan-test).
func _pan_step(delta: float) -> void:
	var cam := get_viewport().get_camera_2d()
	if cam == null:
		return
	var ws: Vector2 = _field().world_size
	cam.position.x += _pan_dir * _pan_test * delta / cam.zoom.x
	if cam.position.x > ws.x * 0.8:
		_pan_dir = -1.0
	elif cam.position.x < ws.x * 0.2:
		_pan_dir = 1.0


## The original ground, kept for comparison (its colours now from Palette).
func _bake_old() -> void:
	var f := _field()
	var c: Dictionary = _old_cols
	var bytes := PackedByteArray()
	bytes.resize(f.w * f.h * 4)
	for i in f.w * f.h:
		var g := f.green[i]
		var o := f.orange[i]
		var e := f.entrench[i]
		var col: Color = c["clear"]
		if g > 0.03 or o > 0.03:
			if g >= o:
				var heat := clampf(g * 0.75, 0.0, 1.0)
				col = c["green_base"].lerp(c["green_hot"], heat)
				if e > 0.2:
					col = col.lerp(c["green_core"], clampf(e * 0.28, 0.0, 0.5))
				col.a = clampf(g * 0.55, 0.0, 0.8)
			else:
				var heat2 := clampf(o * 0.75, 0.0, 1.0)
				col = c["orange_base"].lerp(c["orange_hot"], heat2)
				if e < -0.2:
					col = col.lerp(c["orange_core"], clampf(-e * 0.28, 0.0, 0.5))
				col.a = clampf(o * 0.55, 0.0, 0.8)
			if minf(g, o) > 0.1:
				col = col.lerp(c["front"], 0.3)
				col.a = maxf(col.a, 0.45)
		var j := i * 4
		bytes[j] = int(col.r * 255.0)
		bytes[j + 1] = int(col.g * 255.0)
		bytes[j + 2] = int(col.b * 255.0)
		bytes[j + 3] = int(col.a * 255.0)
	_img.set_data(f.w, f.h, false, Image.FORMAT_RGBA8, bytes)
	_tex.update(_img)
