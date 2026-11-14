extends Node
## Flow-field ground. Thousands of streak heads are advected on the GPU by a
## GPUParticles2D process shader (shaders/flow_particles.gdshader) that reads
## the sim's influence field (Game.state.view_field()) as three float textures.
## Each frame the heads draw a short segment into an HDR trail buffer that is
## never cleared, only carried over, so the segments accumulate into trails.
## This node also shows the buffer, on a screen-space layer under the map
## (shaders/flow_composite.gdshader). Streaks thin out beside the routes (the
## moat, GroundMoat), on map's own lane curves.
##
## What the game does to the current (GroundForces, render-only): the routes push
## it by their rates (view_lanes), Vei's backlog spins a clot at her gates
## (view_vei), it bends toward Relish (view_relish), and tithe surges and flips
## sweep it (view_vei().tithe and Game.game_event). Under reduced motion nothing
## advects: each head is a still comet laid along the flow, and the trail buffer
## holds only this frame.
##
## The trail buffer follows the camera at screen resolution, so near zoom
## stays crisp (the spike's world-space buffer went soft past the fit zoom):
##   - trail viewport (HDR): first a full-rect pass draws last frame's trail,
##     reprojected by the camera delta and faded by keep^dt
##     (flow_reproject.gdshader); then the particles draw on top, through the
##     map camera's transform;
##   - history viewport (HDR): a straight copy of the trail
##     (flow_copy.gdshader), because a viewport can't sample itself.
## The camera transform is read in RenderingServer.frame_pre_draw, after every
## _process and input handler, so the ground never lags the routes by a frame.
##
## Streaks stay hairlines on screen (streak_width_px) and the ink on screen is
## constant across zoom: a zoomed-in streak is longer on screen, so fewer are
## active (density_exp). Particles spawn and live in the visible part of the
## world. Port of realm-snapshot aesthetics/04-flow-field-synthwave.html.
## Tuning: configs/ground.json. Tempo and reduced motion: Pulse.

const PARTICLE_SHADER := preload("res://shaders/flow_particles.gdshader")
const STREAK_SHADER := preload("res://shaders/flow_streak.gdshader")
const REPROJECT_SHADER := preload("res://shaders/flow_reproject.gdshader")
const COPY_SHADER := preload("res://shaders/flow_copy.gdshader")
const COMPOSITE_SHADER := preload("res://shaders/flow_composite.gdshader")
const MAX_LANES := 64   # flow_particles.gdshader's MAX_LANES

var reduced := false
var field_upload_ms := 0.0
var last_cpu_ms := 0.0   # GDScript time spent by this node this frame
var trail_size := Vector2i.ZERO
var active := 1.0        # share of streaks alive this frame (zoom-dependent)
var zoom := 1.0          # map camera zoom, screen px per world unit

var _cfg := {}
var _vp: SubViewport
var _hist: SubViewport
var _reproj_rect: ColorRect
var _reproj_mat: ShaderMaterial
var _copy_rect: ColorRect
var _parts: GPUParticles2D
var _pmat: ShaderMaterial
var _layer: CanvasLayer
var _show: TextureRect
var _comp_mat: ShaderMaterial
var _texs: Array[ImageTexture] = []
var _field_acc := 999.0
var _t := 0.0
var _keep := 1.0
var _prev_xform := Transform2D.IDENTITY
var _have_prev := false
var _prev_area := -1.0
var _frame := 0
var _world_size := Vector2(2048, 1440)
var _pos := {}           # node id -> world position, from view_realm (nodes don't move)
var _forts: Array = []   # view_realm().forts, for map's demo lanes
var _demo_lanes := false # --lanes=demo: the routes draw map's demo lanes, so the moat follows them
var _moat_cache := {}    # GroundMoat's per-lane cache (cleared when the positions change)
var _warned_lanes := false
var _forces: GroundForces
var _smat: ShaderMaterial
var _relish_moving := false


func setup(cfg: Dictionary, reduced_motion: bool, streak_override := 0) -> void:
	_cfg = cfg
	reduced = reduced_motion
	var f := _field()
	_world_size = f.world_size
	_demo_lanes = Game.state.debug_enabled and OS.get_cmdline_user_args().has("--lanes=demo")
	_forces = GroundForces.new(cfg.get("forces", {}))
	_refresh_nodes()
	trail_size = _trail_size_for()

	_hist = _hdr_viewport("FlowHistory")
	_vp = _hdr_viewport("FlowTrail")
	RenderingServer.viewport_set_measure_render_time(_vp.get_viewport_rid(), true)
	RenderingServer.viewport_set_measure_render_time(_hist.get_viewport_rid(), true)

	# trail pass 1: last frame, reprojected and faded (screen space, so on a layer
	# the trail viewport's canvas transform doesn't touch)
	var rl := CanvasLayer.new()
	rl.layer = -1
	_reproj_rect = ColorRect.new()
	_reproj_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_reproj_mat = ShaderMaterial.new()
	_reproj_mat.shader = REPROJECT_SHADER
	_reproj_mat.set_shader_parameter("prev", _hist.get_texture())
	_reproj_rect.material = _reproj_mat
	rl.add_child(_reproj_rect)
	_vp.add_child(rl)

	# the history: a copy of the trail
	_copy_rect = ColorRect.new()
	_copy_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cm := ShaderMaterial.new()
	cm.shader = COPY_SHADER
	cm.set_shader_parameter("src", _vp.get_texture())
	_copy_rect.material = cm
	_hist.add_child(_copy_rect)

	# field textures: one float layer each, uploaded natively (no per-cell loop)
	for arr in [f.green, f.orange, f.entrench]:
		_texs.append(ImageTexture.create_from_image(_layer_image(arr, f.w, f.h)))

	_pmat = ShaderMaterial.new()
	_pmat.shader = PARTICLE_SHADER
	_pmat.set_shader_parameter("field_g", _texs[0])
	_pmat.set_shader_parameter("field_o", _texs[1])
	_pmat.set_shader_parameter("field_e", _texs[2])
	_pmat.set_shader_parameter("world_size", f.world_size)
	_pmat.set_shader_parameter("grid_size", Vector2(f.w, f.h))
	_pmat.set_shader_parameter("cov_pos", _pos.get("covington", Vector2.ZERO))
	_pmat.set_shader_parameter("vei_pos", _pos.get("vei", Vector2.ZERO))
	_pmat.set_shader_parameter("trail_prev", _hist.get_texture())

	_parts = GPUParticles2D.new()
	_parts.name = "Streaks"
	var n: int = streak_override if streak_override > 0 else int(cfg.get("streaks", 9000))
	_parts.amount = maxi(1, n)
	_parts.lifetime = 3600.0         # particles respawn themselves in the shader
	_parts.explosiveness = 1.0       # all heads alive from frame one
	_parts.fixed_fps = 0             # advect every rendered frame, dt-correct
	_parts.interpolate = false
	_parts.local_coords = false
	_parts.visibility_rect = Rect2(-f.world_size, f.world_size * 3.0)
	var white := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	white.fill(Color.WHITE)
	_parts.texture = ImageTexture.create_from_image(white)
	_parts.process_material = _pmat
	_smat = ShaderMaterial.new()
	_smat.shader = STREAK_SHADER
	_parts.material = _smat

	# show it: under the whole map (layer -1), 1 buffer px per screen px
	_layer = CanvasLayer.new()
	_layer.name = "FlowGroundLayer"
	_layer.layer = -1
	_show = TextureRect.new()
	_show.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_show.texture = _vp.get_texture()
	_show.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_show.stretch_mode = TextureRect.STRETCH_SCALE
	_show.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_comp_mat = ShaderMaterial.new()
	_comp_mat.shader = COMPOSITE_SHADER
	_show.material = _comp_mat
	_layer.add_child(_show)
	add_child(_layer)

	_resize()
	apply_config(cfg)
	_sync_camera()                   # spawn uniforms are right before the first start()
	_vp.add_child(_parts)
	upload_field()
	upload_lanes()
	upload_forces()
	get_viewport().size_changed.connect(_resize)
	RenderingServer.frame_pre_draw.connect(_sync_camera)
	Game.game_event.connect(on_game_event)


func _exit_tree() -> void:
	if RenderingServer.frame_pre_draw.is_connected(_sync_camera):
		RenderingServer.frame_pre_draw.disconnect(_sync_camera)
	if Game.game_event.is_connected(on_game_event):
		Game.game_event.disconnect(on_game_event)


## A game event (Game.game_event; the bench sends synthetic ones here directly): flips, retakes and
## tithe warnings or waves start their sweeps.
func on_game_event(ev: Dictionary) -> void:
	_forces.on_event(ev, _t, float(Game.state.view_hud()["t"]), _pos)


func texture() -> Texture2D:
	return _vp.get_texture()


func viewport_rid() -> RID:
	return _vp.get_viewport_rid()


func history_rid() -> RID:
	return _hist.get_viewport_rid()


func streak_count() -> int:
	return _parts.amount


func active_streaks() -> int:
	return roundi(_parts.amount * active)


func set_reduced(on: bool) -> void:
	reduced = on
	apply_config(_cfg)


## Push every tuning key to the shaders. Safe to call after a config reload.
func apply_config(cfg: Dictionary) -> void:
	_cfg = cfg
	var keys := ["speed", "speed_empty", "speed_settled", "speed_living", "front_boost",
		"draught", "draught_empty", "push", "orbit_strength", "turbulence", "turbulence_empty",
		"turbulence_land", "noise_scale", "noise_evolve", "commit_dominance", "commit_entrench",
		"entrench_ref", "tempo_amp", "dash_px", "dash_duty", "streak_width_px",
		"spawn_empty_weight", "alpha_empty", "alpha_land", "alpha_front", "core_mix", "seam_land",
		"moat_px", "moat_strength", "clump_limit", "spawn_land_weight"]
	for k in keys:
		if cfg.has(k):
			_pmat.set_shader_parameter(k, float(cfg[k]))
	_pmat.set_shader_parameter("wave_spread", Pulse.wave_spread)
	_pmat.set_shader_parameter("presence", _v2(cfg.get("presence", [0.01, 0.22])))
	_pmat.set_shader_parameter("front_range", _v2(cfg.get("front", [0.03, 0.22])))
	_pmat.set_shader_parameter("life_s", _v2(cfg.get("life_s", [2.5, 6.5])))
	_pmat.set_shader_parameter("moat_end", _v2(cfg.get("moat_end", [25.0, 70.0])))
	var cols: Dictionary = cfg.get("colors", {})
	for k in ["green", "green_core", "orange", "orange_core", "violet"]:
		if cols.has(k):
			_pmat.set_shader_parameter("col_" + k, Color(str(cols[k])))
	_comp_mat.set_shader_parameter("gain", float(cfg.get("composite_gain", 2.4)))
	_forces.cfg = cfg.get("forces", {})
	var fc: Dictionary = _forces.cfg
	var sub := func(k: String) -> Dictionary: return fc.get(k, {})
	for pair in [["route", ["push", "reach_px", "speed", "calm"]],
			["vortex", ["push", "spiral", "slow", "dense", "ink", "turbulence", "hold"]],
			["relish", ["push", "swirl", "eye_px"]],
			["surge", ["tail", "reach_px", "push", "speed", "ink"]],
			["ink", ["band_px", "push", "hold"]]]:
		var c: Dictionary = sub.call(pair[0])
		for k in pair[1]:
			if c.has(k):
				_pmat.set_shader_parameter("%s_%s" % [pair[0], k], float(c[k]))
	var cm: Dictionary = cfg.get("comet", {})
	_pmat.set_shader_parameter("comet", 1.0 if reduced else 0.0)
	_smat.set_shader_parameter("comet", 1.0 if reduced else 0.0)
	_pmat.set_shader_parameter("fade_s", _v2(cfg.get("fade_s", [0.35, 0.6])))
	for k in ["power", "dashes"]:
		if cm.has(k):
			_smat.set_shader_parameter("comet_" + k, float(cm[k]))
	_smat.set_shader_parameter("dash_duty", float(cfg.get("dash_duty", 0.5)))
	if reduced:
		# frozen comets: nothing advects, no exhale, no evolving churn; each head draws a still comet
		# laid back along the flow, into a trail buffer cleared every frame (_process)
		_pmat.set_shader_parameter("tempo_amp", 0.0)
		_pmat.set_shader_parameter("noise_evolve", 0.0)
		_pmat.set_shader_parameter("comet_px", float(cm.get("length_px", 30.0)))
		_pmat.set_shader_parameter("comet_gain", float(cm.get("gain", 1.0)))
		_pmat.set_shader_parameter("life_s", _v2(cm.get("life_s", [12.0, 30.0])))
		_pmat.set_shader_parameter("fade_s", _v2(cm.get("fade_s", [1.5, 1.5])))
		# a surge stands as one line brightening toward its fort instead of running
		_pmat.set_shader_parameter("surge_tail", 1.0)
		# calmer eddies, so the comets lie along the flow and a still frame shows direction
		var calm := float(cfg.get("reduced_turbulence", 1.0))
		for k in ["turbulence", "turbulence_empty", "turbulence_land"]:
			if cfg.has(k):
				_pmat.set_shader_parameter(k, float(cfg[k]) * calm)


func _process(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	_t += delta
	_pmat.set_shader_parameter("t", _t)          # noise evolution only
	_pmat.set_shader_parameter("beat", Pulse.phase(0.0))
	# reduced motion: the comets are redrawn every frame, so nothing carries over
	_keep = 0.0 if reduced else pow(clampf(float(_cfg.get("trail_keep_per_s", 0.03)), 0.0, 1.0), delta)
	_field_acc += delta
	if _field_acc >= 1.0 / maxf(0.1, float(_cfg.get("field_hz", 6.0))):
		_field_acc = 0.0
		upload_field()
		upload_lanes()
		upload_forces()
	elif _relish_moving:
		_upload_relish()   # she travels: follow her every frame
	_upload_sweeps()
	last_cpu_ms = (Time.get_ticks_usec() - t0) / 1000.0


## Runs in frame_pre_draw, after input and _process: the camera is final.
## Points the trail at the camera, sets the reprojection from last frame, and
## tells the particles which part of the world is on screen.
func _sync_camera() -> void:
	if not is_inside_tree():
		return
	var ts := Vector2(trail_size)
	var vsize := get_viewport().get_visible_rect().size
	var canvas: Transform2D = (get_parent() as CanvasItem).get_global_transform_with_canvas() \
		if get_parent() is CanvasItem else get_viewport().get_canvas_transform()
	var to_trail := Transform2D(0.0, Vector2(ts.x / vsize.x, ts.y / vsize.y), 0.0, Vector2.ZERO) * canvas
	# Whole-pixel translation: a pan then shifts the history by whole texels, so
	# carrying it over never resamples (a fractional shift every frame blurs the
	# trails sideways). The ground sits at most half a pixel off the routes.
	to_trail.origin = to_trail.origin.round()
	_vp.canvas_transform = to_trail
	var m := _prev_xform * to_trail.affine_inverse() if _have_prev else Transform2D.IDENTITY
	_reproj_mat.set_shader_parameter("m_x", m.x)
	_reproj_mat.set_shader_parameter("m_y", m.y)
	_reproj_mat.set_shader_parameter("m_o", m.origin)
	_reproj_mat.set_shader_parameter("keep", _keep if _have_prev else 0.0)
	# the history holds last frame, drawn through last frame's transform
	var last := _prev_xform if _have_prev else to_trail
	_pmat.set_shader_parameter("tr_x", last.x)
	_pmat.set_shader_parameter("tr_y", last.y)
	_pmat.set_shader_parameter("tr_o", last.origin)
	_pmat.set_shader_parameter("tr_size", ts)
	_prev_xform = to_trail
	_have_prev = true

	# the visible world, and how much of the screen it covers
	var inv := canvas.affine_inverse()
	var view := Rect2(inv * Vector2.ZERO, Vector2.ZERO).expand(inv * vsize)
	var ws := _world_size
	var world := Rect2(Vector2.ZERO, ws)
	zoom = canvas.get_scale().x
	var margin := float(_cfg.get("view_margin_px", 48.0)) / maxf(zoom, 1e-3)
	var seen := view.intersection(world)
	var area := seen.get_area()
	var covered := area * zoom * zoom / maxf(1.0, vsize.x * vsize.y)
	var fit := minf(vsize.x / ws.x, vsize.y / ws.y) * 0.98
	var covered_fit := ws.x * ws.y * fit * fit / maxf(1.0, vsize.x * vsize.y)
	active = clampf(pow(fit / maxf(zoom, 1e-3), float(_cfg.get("density_exp", 1.0))) * covered / maxf(covered_fit, 1e-3), 0.0, 1.0)
	# zooming out uncovers world: respawn that share at once instead of waiting a life
	var regrow := 0.0 if _prev_area <= 0.0 else clampf(1.0 - _prev_area / maxf(area, 1.0), 0.0, 1.0)
	_prev_area = area
	_frame += 1
	var keep_rect := view.grow(margin)
	# spawn in the margin too, so a pan uncovers streaks that already exist
	var spawn := keep_rect.intersection(world)
	_pmat.set_shader_parameter("spawn_rect", Vector4(spawn.position.x, spawn.position.y, spawn.size.x, spawn.size.y))
	_pmat.set_shader_parameter("keep_rect", Vector4(keep_rect.position.x, keep_rect.position.y, keep_rect.size.x, keep_rect.size.y))
	_pmat.set_shader_parameter("active", active)
	_pmat.set_shader_parameter("regrow", regrow)
	_pmat.set_shader_parameter("frame_seed", float(_frame % 65536))
	_pmat.set_shader_parameter("px_world", 1.0 / maxf(zoom, 1e-3))


func _resize() -> void:
	trail_size = _trail_size_for()
	_vp.size = trail_size
	_hist.size = trail_size
	_reproj_rect.size = Vector2(trail_size)
	_copy_rect.size = Vector2(trail_size)
	_reproj_mat.set_shader_parameter("size", Vector2(trail_size))
	_show.position = Vector2.ZERO
	_show.size = get_viewport().get_visible_rect().size
	_have_prev = false


func _trail_size_for() -> Vector2i:
	var s: Vector2 = get_viewport().get_visible_rect().size * float(_cfg.get("trail_screen_scale", 1.0))
	return Vector2i(maxi(16, roundi(s.x)), maxi(16, roundi(s.y)))


func _hdr_viewport(vp_name: String) -> SubViewport:
	var vp := SubViewport.new()
	vp.name = vp_name
	vp.size = _trail_size_for()
	vp.use_hdr_2d = true            # float trail: fades fully to black, no 8-bit ghost floor
	vp.transparent_bg = true        # cleared to (0,0,0,0) once; every pixel is rewritten after
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.render_target_clear_mode = SubViewport.CLEAR_MODE_ONCE
	add_child(vp)
	return vp


func upload_field() -> void:
	var t0 := Time.get_ticks_usec()
	var f := _field()
	var layers := [f.green, f.orange, f.entrench]
	for i in 3:
		_texs[i].update(_layer_image(layers[i], f.w, f.h))
	field_upload_ms = (Time.get_ticks_usec() - t0) / 1000.0


## The live field (STATE-API 5.6: the one view that is not a copy).
func _field() -> InfluenceField:
	return Game.state.view_field()["field"]


## Node positions from view_realm. Nodes don't move, so this runs at setup and again only when a
## lane names a node the cache lacks.
func _refresh_nodes() -> void:
	var realm := Game.state.view_realm()
	_pos = {"covington": _v2(realm["covington"]["pos"]), "vei": _v2(realm["vei"]["pos"])}
	_forts = realm["forts"]
	for f in _forts:
		_pos[str(f["id"])] = _v2(f["pos"])
	_moat_cache.clear()


## The lanes the routes draw, as the moat's quadratic bows (GroundMoat): view_lanes rows, or map's
## demo lanes when the routes draw those, on map's own curves.
func upload_lanes() -> void:
	var rows: Array = MapLogic.demo_lanes(_forts) if _demo_lanes else Game.state.view_lanes().get("lanes", [])
	if rows.any(func(r): return not _pos.has(str(r["from"])) or not _pos.has(str(r["to"]))):
		_refresh_nodes()
	var log_max := float(MapLogic.cfg()["rate_log_max"])
	var ls := GroundMoat.lanes(rows, _pos, func(rate: float) -> float: return Pulse.rate_to_u(rate, log_max), _moat_cache)
	if ls.size() > MAX_LANES and not _warned_lanes:
		_warned_lanes = true
		push_warning("flow ground: %d lanes, the moat shader takes %d; the rest get no moat" % [ls.size(), MAX_LANES])
	var n := mini(ls.size(), MAX_LANES)
	var ac := PackedVector4Array()
	var bw := PackedVector4Array()
	ac.resize(MAX_LANES)
	bw.resize(MAX_LANES)
	for i in n:
		var l: Dictionary = ls[i]
		ac[i] = Vector4(l["a"].x, l["a"].y, l["c"].x, l["c"].y)
		bw[i] = Vector4(l["b"].x, l["b"].y, l["half_width"], _forces.lane_weight(l["kind"], l["u"]))
	_pmat.set_shader_parameter("lane_ac", ac)
	_pmat.set_shader_parameter("lane_bw", bw)
	_pmat.set_shader_parameter("lane_count", n)


## Vei's clot, Relish's pull and the tithe state (GroundForces), at field_hz.
func upload_forces() -> void:
	var vei := Game.state.view_vei()
	_pmat.set_shader_parameter("vortex", _forces.vortex(vei))
	_forces.update(_t, vei.get("tithe", {}), _pos)
	_upload_relish()


func _upload_relish() -> void:
	var rel := Game.state.view_relish()
	_relish_moving = str(rel.get("state", "")) == "travelling"
	_pmat.set_shader_parameter("relish", _forces.relish(rel))


func _upload_sweeps() -> void:
	var su: Dictionary = _forces.surge_arrays(_t, reduced)
	_pmat.set_shader_parameter("surge_ac", su["ac"])
	_pmat.set_shader_parameter("surge_b", su["b"])
	_pmat.set_shader_parameter("surge_count", su["count"])
	var ik: Dictionary = _forces.ink_array(_t, reduced)
	_pmat.set_shader_parameter("ink", ik["ink"])
	_pmat.set_shader_parameter("ink_count", ik["count"])


func _layer_image(arr: PackedFloat32Array, w: int, h: int) -> Image:
	var img := Image.create_from_data(w, h, false, Image.FORMAT_RF, arr.to_byte_array())
	img.convert(Image.FORMAT_RH)     # half float: filterable on GLES3 / WebGL2 too
	return img


static func _v2(a) -> Vector2:
	if a is Array and a.size() >= 2:
		return Vector2(float(a[0]), float(a[1]))
	return Vector2.ZERO
