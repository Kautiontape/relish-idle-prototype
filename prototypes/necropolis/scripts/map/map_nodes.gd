class_name MapNodes
extends Node2D
## Draws every node on the realm from the shared MapModel and owns the layers that do it: a
## static layer and a pulse layer per kind (forts, Covington, Vei) plus Relish. Static layers
## redraw only when the model refreshed, the zoom or tier changed, or the selection moved; pulse
## layers redraw every frame (once per refresh under reduced motion). This node draws the villages
## and turns Vei's digestion rings. Tempo comes from Pulse (Covington 0 hops, forts 1, Vei 2).
## Pure logic: node_logic.gd. Tuning: configs/map_view.json "nodes".

var model: MapModel
## Set by world_map: told which forts stand in Relish's light so their dead lane's gutter lifts.
var routes: MapRoutes
var selected_id := "":
	set(v):
		selected_id = v
		ctx.selected_id = v
		_dirty = true
## GDScript + drawing ms the nodes spent last frame (the bench's NODES_MS).
var nodes_ms := 0.0

var ctx := MapNodeCtx.new()

var _forts_s: MapFortRing
var _forts_p: MapFortRing
var _cov_s: MapCovington
var _cov_p: MapCovington
var _vei_s: MapVei
var _vei_p: MapVei
var _relish: MapRelish
var _statics: Array = []
var _pulses: Array = []
var _rev := -2
var _dirty := true
var _rm := false
var _cam: Camera2D
var _cfg_ref = null
var _stamp_s := 0.0  # Pulse's clock when the model's relish entry last changed
var _lit_key := ""
var _draw_ms := 0.0
var _last_us := 0

# bench readout (--bench-seconds): per ground mode, the nodes' ms per frame
var _bench := false
var _samples := {}
var _frames := 0


func _ready() -> void:
	ctx.model = model
	ctx.selected_id = selected_id
	var realm_cfg: Dictionary = ConfigDb.data.get("realm", {})
	ctx.flip = realm_cfg.get("flip", {})
	ctx.r_vei = float(realm_cfg.get("R_vei", 0.0))
	_forts_s = _layer(MapFortRing, false)
	_cov_s = _layer(MapCovington, false)
	_vei_s = _layer(MapVei, false)
	_forts_p = _layer(MapFortRing, true)
	_cov_p = _layer(MapCovington, true)
	_vei_p = _layer(MapVei, true)
	_relish = _layer(MapRelish, true)
	_bench = Array(OS.get_cmdline_user_args()).any(func(a): return str(a).begins_with("--bench-seconds"))


func _layer(script: GDScript, is_pulse: bool) -> MapNodeLayer:
	var l: MapNodeLayer = script.new()
	l.ctx = ctx
	l.pulse = is_pulse
	l.name = "%s%s" % [script.get_global_name(), "Pulse" if is_pulse else "Static"]
	add_child(l)
	(_pulses if is_pulse else _statics).append(l)
	return l


func _exit_tree() -> void:
	if not _bench:
		return
	for mode in _samples:
		var a: Array = _samples[mode]
		var sum := 0.0
		var mx := 0.0
		for x in a:
			sum += x
			mx = maxf(mx, x)
		print("NODES_MS mode=%s n=%d mean=%.4f max=%.4f" % [mode, a.size(), sum / maxf(a.size(), 1.0), mx])


func _process(_delta: float) -> void:
	var t0 := Time.get_ticks_usec()  # lint-ok: bench timing
	_record_last_frame()
	if model == null or model.realm.is_empty() or not is_visible_in_tree():
		nodes_ms = 0.0
		return
	_check_config()
	_sync_camera()
	var rm: bool = Pulse.reduced_motion
	ctx.now_s = Pulse.now_ms() * 0.001
	var refreshed := model.rev != _rev
	if refreshed:
		_on_refresh()
	if rm != _rm:
		_rm = rm
		_dirty = true
	_update_relish(rm)
	if not rm:
		_vei_s.spin(fposmod(ctx.now_s * NodeLogic.vei_spin(ctx.r_vei), TAU))
	if refreshed or _dirty:
		for l in _statics:
			l.queue_redraw()
		queue_redraw()
	if not rm or refreshed or _dirty:
		for l in _pulses:
			l.queue_redraw()
	_dirty = false
	_last_us = Time.get_ticks_usec() - t0  # lint-ok: bench timing


## The frame before's cost: this script's process plus every layer's drawing, as the readout
## and a bench sample (keyed by the ground's mode).
func _record_last_frame() -> void:
	var ms := _last_us / 1000.0 + _draw_ms
	for l: MapNodeLayer in _statics + _pulses:
		ms += l.draw_ms
		l.draw_ms = 0.0
	_draw_ms = 0.0
	nodes_ms = ms
	if not _bench or _rev < 0:
		return
	_frames += 1
	if _frames <= int(NodeLogic.ncfg()["bench_skip_frames"]):
		return  # the first draws build fonts and every static layer: not a steady-state frame
	var mode := str(get_parent().get_child(0).get("mode")) if get_parent() != null else "?"
	if not _samples.has(mode):
		_samples[mode] = []
	(_samples[mode] as Array).append(ms)


## F6 reloads ConfigDb: a new map_view dictionary means new tuning, so everything redraws.
func _check_config() -> void:
	var live = ConfigDb.data.get("map_view")
	if live is Dictionary and not is_same(live, _cfg_ref):
		if _cfg_ref != null:
			MapLogic.configure(live)
			_dirty = true
			_lit_key = "stale"
		_cfg_ref = live


func _sync_camera() -> void:
	if _cam == null or not is_instance_valid(_cam):
		_cam = get_viewport().get_camera_2d()
	var z := _cam.zoom.x if _cam != null else 1.0
	var tier := ctx.tier
	if _cam is MapCamera:
		tier = (_cam as MapCamera).tier
	elif _cam != null:
		tier = MapLogic.zoom_tier(z, ctx.tier)
	if tier != ctx.tier or absf(z - ctx.zoom) > ctx.zoom * float(NodeLogic.ncfg()["zoom_redraw_eps"]):
		ctx.zoom = z
		ctx.tier = tier
		_dirty = true


## Once per model refresh: pull the model's entries into the context, find the forts in Relish's
## light and tell the routes, and restart the extrapolation clock.
func _on_refresh() -> void:
	_rev = model.rev
	ctx.forts = model.forts
	ctx.vei = model.vei
	ctx.relish = model.relish
	ctx.cov_pos = model.node_pos("covington")
	ctx.vei_pos = model.node_pos("vei")
	ctx.vei_radius = float(model.realm.get("vei", {}).get("radius", 0.0))
	_stamp_s = ctx.now_s
	var ids: Array = []
	if not model.relish.is_empty():
		ids = NodeLogic.lit_fort_ids(model.forts, MapModel.to_vec(model.relish["pos"]), float(NodeLogic.ncfg()["relish_light_radius_px"]))
	ctx.lit.clear()
	for id in ids:
		ctx.lit[id] = true
	var key := ",".join(ids)
	if key != _lit_key:
		_lit_key = key
		if routes != null:
			routes.set_lit_forts(ids)
	if _rm and str(model.relish.get("state", "")) == "travelling":
		NodeLogic.wake_add(ctx.wake, MapModel.to_vec(model.relish["pos"]), ctx.now_s)
	elif _rm:
		ctx.wake.clear()


## Relish's drawn position (interpolated while she travels, offset above her node when she
## stands) and her wake. Reduced motion: no interpolation; the wake grows once per refresh.
func _update_relish(rm: bool) -> void:
	var rel := model.relish
	if rel.is_empty():
		return
	var n := NodeLogic.ncfg()
	var state := str(rel["state"])
	var base := MapModel.to_vec(rel["pos"])
	if state == "travelling":
		var tid := str(rel.get("target", ""))
		var speed_scale := 0.0 if bool(model.hud.get("paused", false)) else float(model.hud.get("time_scale", 1.0))
		var dt := 0.0 if rm else NodeLogic.extrap_dt(ctx.now_s - _stamp_s, speed_scale)
		ctx.relish_pos = NodeLogic.relish_drawn_pos(state, base, float(rel["heading"]), float(rel["speed"]), dt,
			model.node_pos(tid), model.has_node(tid))
		if model.nodes_demo:
			ctx.wake = NodeLogic.demo_wake(ctx.relish_pos, float(rel["heading"]), int(MapLogic.cfg()["demo_nodes"]["wake_points"]), ctx.now_s)
		elif not rm:
			NodeLogic.wake_add(ctx.wake, ctx.relish_pos, ctx.now_s)
	else:
		var at := str(rel.get("at", "covington"))
		if state == "dead":
			at = "covington"  # E1 respawns at once; dead she is hollow at home
		ctx.relish_pos = model.node_pos(at) if state == "dead" else base
		ctx.relish_pos.y -= _node_radius(at) + float(n["relish_gap_px"])
	if not rm:
		NodeLogic.wake_prune(ctx.wake, ctx.now_s)


func _node_radius(id: String) -> float:
	if id == "vei":
		return NodeLogic.vei_struct_radius(ctx.vei_radius)
	if model.forts_by_id.has(id):
		return MapLogic.fort_radius(int(model.fort(id)["tier"]))
	return float(MapLogic.cfg()["work_ring_radius_px"])


## The villages: small town-blue squares, their edge by owner (undead green, Vei's orange, or
## town blue); the name only at near zoom.
func _draw() -> void:
	if model == null or model.realm.is_empty():
		return
	var t0 := Time.get_ticks_usec()  # lint-ok: bench timing
	var n := NodeLogic.ncfg()
	var hw := ctx.hair_w()
	var s := float(n["village_size_px"])
	var half := Vector2(s, s) * 0.5
	for tw in model.villages:
		var p := MapModel.to_vec(tw["pos"])
		var edge := Palette.c(NodeLogic.village_edge_key(str(tw["owner"])))
		draw_rect(Rect2(p - half, half * 2.0), Palette.c("town", float(n["village_fill_alpha"])), true)
		draw_rect(Rect2(p - half, half * 2.0), edge, false, maxf(float(n["village_edge_px"]), hw))
		if ctx.selected_id == tw["id"]:
			var pad := Vector2(1, 1) * float(n["village_select_pad_px"])
			draw_rect(Rect2(p - half - pad, half * 2.0 + pad * 2.0), Palette.c("select"), false, maxf(float(n["select_width_px"]), hw))
		if ctx.tier == "near":
			var size := int(MapLogic.cfg()["font_label"])
			_village_label(p + Vector2(0.0, s * 0.5 + ctx.px(float(n["village_label_gap_px"]))), str(tw["name"]), size)
	_draw_ms += (Time.get_ticks_usec() - t0) / 1000.0  # lint-ok: bench timing


func _village_label(at: Vector2, s: String, size: int) -> void:
	var sc := 1.0 / maxf(ctx.zoom, 0.001)
	var font := ThemeDB.fallback_font
	draw_set_transform(at, 0.0, Vector2(sc, sc))
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	draw_string(font, Vector2(-w * 0.5, size), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size,
		Palette.c("text_dim", float(MapLogic.cfg()["node_label_dim_alpha"])))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
