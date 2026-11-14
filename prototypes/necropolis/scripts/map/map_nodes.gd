class_name MapNodes
extends Node2D
## Draws every node on the realm from the shared MapModel and owns the layers that do it: a
## static layer per fort and per other kind (Covington, Vei, the held forts' chips), the forts'
## state glyphs, and a pulse layer per kind plus Relish. A static layer redraws on a model refresh
## only when its static_sig changed, and always when the zoom, tier, selection, reduced motion or
## config changed; pulse layers redraw every frame (once per refresh under reduced motion). The
## glyphs' beat (and the siege's, near zoom: MapSiege) is their layer's modulate, so it costs no
## redraw; Relish's party (MapParty) is a pulse layer under her token. This node draws the villages and
## turns Vei's digestion rings. Tempo comes from Pulse (Covington 0 hops, forts 1, Vei 2).
## The set pieces (MapSetpieces) animate static layers between refreshes through the context's
## hooks and the redraw_* calls below.
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
var timed_layers: Array = []  # sibling layers whose draw_ms also counts here (the route preview)

var ctx := MapNodeCtx.new()

var _fort_box: Node2D  # the per-fort static ring layers, in world order
var _fort_ids: Array = []
var _glyph_beat: MapFortGlyph
var _glyph_still: MapFortGlyph
var _siege: MapSiege
var _idle: MapFortIdle
var _sigs := {}  # static layer -> its static_sig at its last redraw
var _vsig: Array = []  # the villages' owners at their last redraw
var _forts_p: MapFortRing
var _cov_s: MapCovington
var _cov_p: MapCovington
var _vei_s: MapVei
var _vei_p: MapVei
var _relish: MapRelish
var _statics: Array = []
var _pulses: Array = []
var _rev := -2
var _margin_sig := ""  # model.margin_sig at the last redraw: the idle layer redraws when it changes
var _dirty := true
var _rm := false
var _cam: Camera2D
var _cfg_ref = null
var _stamp_s := 0.0  # Pulse's clock when the model's relish entry last changed
var _lit_key := ""
var _relish_sig: Array = []  # NodeLogic.relish_sig at the last refresh: the clock restarts only when it changes
var _drawn_prev := Vector2.ZERO  # her drawn position last frame (the wake's jump rule)
var _has_drawn := false
var _draw_ms := 0.0
var _last_us := 0

# bench readout (--bench-seconds): per ground mode, the nodes' ms per frame
var _bench := false
var _samples := {}
var _frames := 0


## Where a held fort's chip is drawn, in world px (shifted clear of Relish's token).
func chip_world_rect(f: Dictionary) -> Rect2:
	return _idle.chip_world_rect(f)


func _ready() -> void:
	ctx.model = model
	ctx.selected_id = selected_id
	var realm_cfg: Dictionary = ConfigDb.data.get("realm", {})
	ctx.flip = realm_cfg.get("flip", {})
	ctx.r_vei = float(realm_cfg.get("R_vei", 0.0))
	_fort_box = Node2D.new()
	_fort_box.name = "FortStatics"
	add_child(_fort_box)
	_sync_fort_layers()
	_idle = _layer(MapFortIdle, false)
	_cov_s = _layer(MapCovington, false)
	_vei_s = _layer(MapVei, false)
	_glyph_beat = _layer(MapFortGlyph, false)
	_glyph_beat.beating = true
	_glyph_beat.name = "MapFortGlyphBeat"
	_glyph_still = _layer(MapFortGlyph, false)
	_glyph_still.name = "MapFortGlyphStill"
	_siege = _layer(MapSiege, false)
	_forts_p = _layer(MapFortRing, true)
	_cov_p = _layer(MapCovington, true)
	_vei_p = _layer(MapVei, true)
	_layer(MapParty, true)
	_relish = _layer(MapRelish, true)
	_bench = Array(OS.get_cmdline_user_args()).any(func(a): return str(a).begins_with("--bench-seconds"))


func _layer(script: GDScript, is_pulse: bool, parent: Node = null) -> MapNodeLayer:
	var l: MapNodeLayer = script.new()
	l.ctx = ctx
	l.pulse = is_pulse
	l.name = "%s%s" % [script.get_global_name(), "Pulse" if is_pulse else "Static"]
	(self if parent == null else parent).add_child(l)
	(_pulses if is_pulse else _statics).append(l)
	return l


## One static ring layer per fort, rebuilt only when the model's fort set changed (a new world).
func _sync_fort_layers() -> void:
	var ids: Array = model.forts.map(func(f): return str(f["id"]))
	if ids == _fort_ids:
		return
	for l in _fort_box.get_children():
		_statics.erase(l)
		_sigs.erase(l)
		_fort_box.remove_child(l)
		l.queue_free()
	_fort_ids = ids
	for id in ids:
		var l: MapFortRing = _layer(MapFortRing, false, _fort_box)
		l.fort_id = id
		l.name = "MapFortRingStatic_%s" % id


## A set piece changed a hook: redraw one fort's ring, the state glyphs, the chips or Covington now.
func redraw_fort(id: String) -> void:
	for l in _fort_box.get_children():
		if (l as MapFortRing).fort_id == id:
			l.queue_redraw()


func redraw_glyphs() -> void:
	_glyph_beat.queue_redraw()
	_glyph_still.queue_redraw()


func redraw_chips() -> void:
	_idle.queue_redraw()


func redraw_covington() -> void:
	_cov_s.queue_redraw()


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
	var margins_changed := model.margin_sig != _margin_sig  # only the layers whose own signature includes margins redraw
	if margins_changed:
		_margin_sig = model.margin_sig
	_update_relish(rm)
	if not rm:
		_vei_s.spin(fposmod(ctx.now_s * NodeLogic.vei_spin(ctx.r_vei), TAU))
	if refreshed or _dirty or margins_changed:
		_vei_s.sync_rings()
		for l: MapNodeLayer in _statics:
			var sig = l.static_sig()
			if _dirty or sig == null or not _sigs.has(l) or _sigs[l] != sig:
				_sigs[l] = sig
				l.queue_redraw()
		var vs: Array = model.villages.map(func(v): return str(v["owner"]))
		if _dirty or vs != _vsig:
			_vsig = vs
			queue_redraw()
	if not rm or refreshed or _dirty:
		for l in _pulses:
			l.queue_redraw()
	if not _fort_ids.is_empty():
		_glyph_beat.modulate.a = NodeLogic.state_alpha(Pulse.wave(model.hops_of(_fort_ids[0])))
		_siege.modulate.a = GlyphLogic.siege_alpha(Pulse.wave(model.hops_of(_fort_ids[0])))
	_dirty = false
	_last_us = Time.get_ticks_usec() - t0  # lint-ok: bench timing


## The frame before's cost: this script's process plus every layer's drawing, as the readout
## and a bench sample (keyed by the ground's mode).
func _record_last_frame() -> void:
	var ms := _last_us / 1000.0 + _draw_ms
	for l: MapNodeLayer in _statics + _pulses + timed_layers:
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
			_vei_s.reset_rings()
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
## light and tell the routes, and restart the extrapolation clock when she moved.
func _on_refresh() -> void:
	_rev = model.rev
	_sync_fort_layers()
	ctx.forts = model.forts
	ctx.vei = model.vei
	ctx.readout = model.readout()
	ctx.relish = model.relish
	ctx.cov_pos = model.node_pos("covington")
	ctx.vei_pos = model.node_pos("vei")
	ctx.vei_radius = float(model.realm.get("vei", {}).get("radius", 0.0))
	var sig := NodeLogic.relish_sig(model.relish)
	if sig != _relish_sig:
		_relish_sig = sig
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


## Relish's drawn position (interpolated while she travels, above her node and clear of its marks
## when she stands) and her wake. Reduced motion: no interpolation; the wake grows once per refresh.
func _update_relish(rm: bool) -> void:
	var rel := model.relish
	if rel.is_empty():
		_has_drawn = false
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
		ctx.relish_pos.y -= _node_reach(at) + float(n["relish_gap_px"]) + float(NodeLogic.relish_radii(ctx.zoom)["halo"])
	if _has_drawn and NodeLogic.wake_jumped(_drawn_prev, ctx.relish_pos):
		ctx.wake.clear()  # she jumped (new game, fixture, teleport): no streak across the map
	_drawn_prev = ctx.relish_pos
	_has_drawn = true
	if not rm:
		NodeLogic.wake_prune(ctx.wake, ctx.now_s)


## How far a node's marks reach, so her standing token (halo included) sits clear of them: Vei's
## structure, backlog stack and beat ring; a fort's rings out to its tithe ring; Covington's WORK ring.
func _node_reach(id: String) -> float:
	if id == "vei":
		return NodeLogic.outer_radius("vei", 0, ctx.vei_radius, float(ctx.vei.get("backlog", 0.0)))
	if model.forts_by_id.has(id):
		return NodeLogic.outer_radius("fort", int(model.fort(id)["tier"]), 0.0)
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
	MapNodeLayer.draw_label(self, ctx.zoom, at, s, size, Palette.c("text_dim", float(MapLogic.cfg()["node_label_dim_alpha"])),
		MapNodeLayer.ALIGN_CENTER, size)
