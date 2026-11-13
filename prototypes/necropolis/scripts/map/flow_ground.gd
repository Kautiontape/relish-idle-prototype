extends Node
## Flow-field ground (spike). Thousands of streak heads are advected on the GPU
## by a GPUParticles2D process shader (shaders/flow_particles.gdshader) that
## reads Game.field as three float textures. Each frame the heads draw a short
## segment into a world-space HDR SubViewport that is never cleared, only
## faded, so the segments accumulate into trails. The owner (map_field_view.gd)
## shows `texture()` on the map with shaders/flow_composite.gdshader.
##
## Port of realm-snapshot aesthetics/04-flow-field-synthwave.html (Canvas 2D,
## CPU particles, screen-space trail buffer) to the GPU, in world space so the
## camera can pan and zoom freely. All tuning is in configs/ground.json.

const PARTICLE_SHADER := preload("res://shaders/flow_particles.gdshader")
const STREAK_SHADER := preload("res://shaders/flow_streak.gdshader")
const FADE_SHADER := preload("res://shaders/flow_fade.gdshader")

var reduced := false
var field_upload_ms := 0.0
var last_cpu_ms := 0.0   # GDScript time spent by this node this frame
var trail_size := Vector2i.ZERO

var _cfg := {}
var _vp: SubViewport
var _fade_mat: ShaderMaterial
var _parts: GPUParticles2D
var _pmat: ShaderMaterial
var _texs: Array[ImageTexture] = []
var _field_acc := 999.0
var _t := 0.0


func setup(cfg: Dictionary, reduced_motion: bool, streak_override := 0) -> void:
	_cfg = cfg
	reduced = reduced_motion
	var f: InfluenceField = Game.field
	var ws: Vector2 = f.world_size
	var ts: float = float(cfg.get("trail_scale", 0.62))
	trail_size = Vector2i(roundi(ws.x * ts), roundi(ws.y * ts))

	_vp = SubViewport.new()
	_vp.name = "FlowTrail"
	_vp.size = trail_size
	_vp.use_hdr_2d = true            # float trail: fades fully to black, no 8-bit ghost floor
	_vp.transparent_bg = true        # cleared to (0,0,0,0) once, then never
	_vp.disable_3d = true
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_vp.render_target_clear_mode = SubViewport.CLEAR_MODE_ONCE
	add_child(_vp)
	RenderingServer.viewport_set_measure_render_time(_vp.get_viewport_rid(), true)
	_vp.canvas_transform = Transform2D(0.0, Vector2(trail_size.x / ws.x, trail_size.y / ws.y), 0.0, Vector2.ZERO)

	var fade := ColorRect.new()
	fade.size = ws
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade_mat = ShaderMaterial.new()
	_fade_mat.shader = FADE_SHADER
	fade.material = _fade_mat
	_vp.add_child(fade)

	# field textures: one float layer each, uploaded natively (no per-cell loop)
	for arr in [f.green, f.orange, f.entrench]:
		var img := _layer_image(arr, f.w, f.h)
		_texs.append(ImageTexture.create_from_image(img))

	_pmat = ShaderMaterial.new()
	_pmat.shader = PARTICLE_SHADER
	_pmat.set_shader_parameter("field_g", _texs[0])
	_pmat.set_shader_parameter("field_o", _texs[1])
	_pmat.set_shader_parameter("field_e", _texs[2])
	_pmat.set_shader_parameter("world_size", ws)
	_pmat.set_shader_parameter("grid_size", Vector2(f.w, f.h))
	_pmat.set_shader_parameter("cov_pos", Game.realm.cov_pos)
	_pmat.set_shader_parameter("vei_pos", Game.realm.vei_pos)

	_parts = GPUParticles2D.new()
	_parts.name = "Streaks"
	var n: int = streak_override if streak_override > 0 else int(cfg.get("streaks", 9000))
	_parts.amount = maxi(1, n)
	_parts.lifetime = 3600.0         # particles respawn themselves in the shader
	_parts.explosiveness = 1.0       # all heads alive from frame one
	_parts.fixed_fps = 0             # advect every rendered frame, dt-correct
	_parts.interpolate = false
	_parts.local_coords = false
	_parts.visibility_rect = Rect2(Vector2.ZERO, ws)
	var white := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	white.fill(Color.WHITE)
	_parts.texture = ImageTexture.create_from_image(white)
	_parts.process_material = _pmat
	var smat := ShaderMaterial.new()
	smat.shader = STREAK_SHADER
	_parts.material = smat
	_vp.add_child(_parts)

	apply_config(cfg)
	upload_field()


func texture() -> Texture2D:
	return _vp.get_texture()


func viewport_rid() -> RID:
	return _vp.get_viewport_rid()


func streak_count() -> int:
	return _parts.amount


func set_reduced(on: bool) -> void:
	reduced = on
	apply_config(_cfg)


## Push every tuning key to the shader. Safe to call after a config reload.
func apply_config(cfg: Dictionary) -> void:
	_cfg = cfg
	var keys := ["speed", "speed_empty", "speed_settled", "speed_living", "front_boost", "draught",
		"draught_empty", "push", "orbit_strength", "turbulence", "turbulence_empty", "turbulence_land", "noise_scale", "noise_evolve", "commit_dominance",
		"commit_entrench", "entrench_ref", "tempo_amp", "tempo_spread", "dash_px", "dash_duty",
		"streak_width", "spawn_empty_weight", "alpha_empty", "alpha_land", "alpha_front", "core_mix"]
	for k in keys:
		if cfg.has(k):
			_pmat.set_shader_parameter(k, float(cfg[k]))
	_pmat.set_shader_parameter("tempo_period", float(cfg.get("tempo_ms", 1714.0)) / 1000.0)
	_pmat.set_shader_parameter("presence", _v2(cfg.get("presence", [0.01, 0.22])))
	_pmat.set_shader_parameter("front_range", _v2(cfg.get("front", [0.03, 0.22])))
	_pmat.set_shader_parameter("life_s", _v2(cfg.get("life_s", [2.5, 6.5])))
	var cols: Dictionary = cfg.get("colors", {})
	for k in ["green", "green_core", "orange", "orange_core", "violet"]:
		if cols.has(k):
			_pmat.set_shader_parameter("col_" + k, Color(str(cols[k])))
	if reduced:
		# slow drift: same field, same colours and dashes, no exhale, frozen churn
		_pmat.set_shader_parameter("speed", float(cfg.get("speed", 64.0)) * float(cfg.get("reduced_speed", 0.1)))
		_pmat.set_shader_parameter("tempo_amp", 0.0)
		_pmat.set_shader_parameter("noise_evolve", float(cfg.get("reduced_noise_evolve", 0.0)))


func _process(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	_t += delta
	_pmat.set_shader_parameter("t", _t)
	var keep_s: float = float(_cfg.get("reduced_keep_per_s" if reduced else "trail_keep_per_s", 0.013))
	_fade_mat.set_shader_parameter("keep", pow(clampf(keep_s, 0.0, 1.0), delta))
	_field_acc += delta
	if _field_acc >= 1.0 / maxf(0.1, float(_cfg.get("field_hz", 6.0))):
		_field_acc = 0.0
		upload_field()
	last_cpu_ms = (Time.get_ticks_usec() - t0) / 1000.0


func upload_field() -> void:
	var t0 := Time.get_ticks_usec()
	var f: InfluenceField = Game.field
	var layers := [f.green, f.orange, f.entrench]
	for i in 3:
		var img := _layer_image(layers[i], f.w, f.h)
		_texs[i].update(img)
	field_upload_ms = (Time.get_ticks_usec() - t0) / 1000.0


func _layer_image(arr: PackedFloat32Array, w: int, h: int) -> Image:
	var img := Image.create_from_data(w, h, false, Image.FORMAT_RF, arr.to_byte_array())
	img.convert(Image.FORMAT_RH)     # half float: filterable on GLES3 / WebGL2 too
	return img


static func _v2(a) -> Vector2:
	if a is Array and a.size() >= 2:
		return Vector2(float(a[0]), float(a[1]))
	return Vector2.ZERO
