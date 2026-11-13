class_name MapRoutes
extends Node2D
## Flow lines: the rate rendered, never a convoy tracked (BRIEF motion canon). Drawn from the
## shared MapModel's lanes only, as shader ribbons (shaders/map_lane.gdshader): one
## MeshInstance2D per lane, its mesh built once along MapLogic's curve, its look in uniforms.
## Lit lanes first, then every dead gutter (so the cut bites into the halos), then the carts.
## Per frame: one dash-offset uniform per visible lane. On a model rev: each lane's channels,
## with uniforms touched only when u moved by u_epsilon or the lane turned on, off or phantom.
## Styling and tables: scripts/map/lane_style_logic.gd. Tuning: configs/map_view.json.

const SHADER := preload("res://shaders/map_lane.gdshader")
const CARTS_SCRIPT := preload("res://scripts/map/map_carts.gd")
const COL_PARAMS: Array[StringName] = [&"col0", &"col1", &"col2", &"col3"]

var model: MapModel
## GDScript ms the routes spent last frame (offsets, any refresh, the cart overlay's draw).
var routes_ms := 0.0


## One lane's (or one gutter's) ribbon node and the state its uniforms were last set from.
class Ribbon:
	var node: MeshInstance2D
	var mat: ShaderMaterial
	var row := {}
	var style := {}
	var geo_key := ""
	var origin := Vector2.ZERO  # gutter: start of the reference curve its mesh was built on
	var pts := PackedVector2Array()
	var cum := PackedFloat32Array()
	var length := 0.0
	var ring := false
	var mode := "off"
	var u := -2.0
	var u_host := -2.0
	var speed := 0.0
	var period := 1.0


var _lanes := {}    # lane id -> Ribbon
var _gutters := {}  # dead lane id -> Ribbon
var _moving: Array = []  # lit Ribbons this rev: their offsets walk every frame
var _lane_layer: Node2D
var _gutter_layer: Node2D
var _carts: Node2D
var _rev := -2
var _cfg_ref = null
var _chev := false
var _tier := ""
var _cam: Camera2D
var _log_max := 0.0

# bench readout (--bench-seconds): per ground mode, the routes' ms per frame
var _bench := false
var _samples := {}
var _build_ms := 0.0
var _builds := 0
var _built_this_frame := false
var _last_us := 0
var _syncs := 0
var _sync_ms_max := 0.0
var _cart_ms_max := 0.0


## The single source of lane geometry, forwarded so callers can reach it from the routes script.
static func lane_curve(from_pos: Vector2, to_pos: Vector2, u: float, bow := -1.0) -> Dictionary:
	return MapLogic.lane_curve(from_pos, to_pos, u, bow)


func _ready() -> void:
	_lane_layer = Node2D.new()
	_lane_layer.name = "Lanes"
	add_child(_lane_layer)
	_gutter_layer = Node2D.new()
	_gutter_layer.name = "Gutters"
	add_child(_gutter_layer)
	_carts = CARTS_SCRIPT.new()
	_carts.name = "Carts"
	add_child(_carts)
	_bench = Array(OS.get_cmdline_user_args()).any(func(a): return str(a).begins_with("--bench-seconds"))


func _process(_delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	_record_last_frame()
	if model == null or not is_visible_in_tree():
		routes_ms = 0.0
		return
	_check_config()
	if model.rev != _rev:
		var ts := Time.get_ticks_usec()
		_sync()
		if not _built_this_frame:
			_syncs += 1
			_sync_ms_max = maxf(_sync_ms_max, (Time.get_ticks_usec() - ts) / 1000.0)
	_sync_chevrons()
	for r: Ribbon in _moving:
		r.mat.set_shader_parameter(&"offset", Pulse.dash_offset(r.speed, r.period))
	_carts.tick(_tier != "far")
	_last_us = Time.get_ticks_usec() - t0


## The frame before's total (process + the cart draw), as the readout and a bench sample.
func _record_last_frame() -> void:
	routes_ms = _last_us / 1000.0 + float(_carts.draw_ms)
	_cart_ms_max = maxf(_cart_ms_max, float(_carts.draw_ms))
	_carts.draw_ms = 0.0
	if not _bench or _rev < 0:
		return
	if _built_this_frame:
		_built_this_frame = false
		return
	var mode := str(get_parent().get_child(0).get("mode")) if get_parent() != null else "?"
	if not _samples.has(mode):
		_samples[mode] = []
	(_samples[mode] as Array).append(routes_ms)


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
		print("ROUTES_MS mode=%s n=%d mean=%.4f max=%.4f | lanes=%d gutters=%d moving=%d | syncs=%d sync_max=%.3f cart_draw_max=%.3f | builds=%d build_ms=%.3f" % [
			mode, a.size(), sum / maxf(a.size(), 1.0), mx, _lanes.size(), _gutters.size(), _moving.size(),
			_syncs, _sync_ms_max, _cart_ms_max, _builds, _build_ms])


## F6 reloads ConfigDb (map_field_view handles the key): a new map_view dictionary means new
## tuning, so re-configure MapLogic and rebuild every ribbon.
func _check_config() -> void:
	var live = ConfigDb.data.get("map_view")
	if not live is Dictionary or is_same(live, _cfg_ref):
		return
	if _cfg_ref != null:
		MapLogic.configure(live)
		for r: Ribbon in _lanes.values() + _gutters.values():
			r.geo_key = ""
			r.mode = "stale"
		_rev = -2
	_cfg_ref = live
	_log_max = float(MapLogic.cfg()["rate_log_max"])


func _u(row) -> float:
	if row == null:
		return LaneStyle.OFF
	return Pulse.rate_to_u(float(row["rate"]), _log_max)


# --- refresh (once per model rev) -------------------------------------------------------

func _sync() -> void:
	_rev = model.rev
	var rows := LaneStyle.plan_rows(model.lanes)
	var by_id := {}
	var dead_on_host := {}
	for r in rows:
		by_id[r["id"]] = r
		var hid := LaneStyle.host_id(r)
		if hid != "" and _u(r) >= 0.0:
			dead_on_host[hid] = true
	_moving.clear()
	var tracks: Array = []
	var seen := {}
	for r in rows:
		if r["kind"] == "dead" or not model.has_node(r["from"]) or not model.has_node(r["to"]):
			continue
		seen[r["id"]] = true
		var lane := _lane(r)
		_apply_lane(lane, _u(r), dead_on_host.has(r["id"]))
		if lane.mode == "lit":
			_moving.append(lane)
			if r["kind"] == "haul":
				tracks.append(_track(lane))
	for id in _lanes:
		if not seen.has(id):
			_hide(_lanes[id])
	seen.clear()
	for r in rows:
		if r["kind"] != "dead" or r["from"] == r["to"] or not model.has_node(r["from"]) or not model.has_node(r["to"]):
			continue
		seen[r["id"]] = true
		var g := _gutter(r)
		var host: Ribbon = _lanes.get(LaneStyle.host_id(r))
		_apply_gutter(g, _u(r), host.u if host != null and host.mode == "lit" else LaneStyle.OFF)
		if g.mode == "lit":
			_moving.append(g)
	for id in _gutters:
		if not seen.has(id):
			_hide(_gutters[id])
	_carts.set_tracks(tracks)


func _hide(r: Ribbon) -> void:
	r.node.visible = false
	r.mode = "off"


func _new_ribbon(row: Dictionary, parent: Node2D) -> Ribbon:
	var r := Ribbon.new()
	r.row = row
	r.node = MeshInstance2D.new()
	r.node.name = str(row["id"]).replace(":", "_")
	r.mat = ShaderMaterial.new()
	r.mat.shader = SHADER
	r.node.material = r.mat
	r.node.visible = false
	parent.add_child(r.node)
	return r


func _lane(row: Dictionary) -> Ribbon:
	var r: Ribbon = _lanes.get(row["id"])
	if r == null:
		r = _new_ribbon(row, _lane_layer)
		_lanes[row["id"]] = r
	r.row = row
	var a := model.node_pos(row["from"])
	var b := model.node_pos(row["to"])
	var radius := 0.0
	if a == b:
		radius = LaneStyle.ring_radius(row, int(model.fort(row["from"]).get("tier", 1)))
	var key := "%s|%s|%s" % [a, b, radius]
	if key != r.geo_key:
		var t0 := Time.get_ticks_usec()
		r.geo_key = key
		r.style = LaneStyle.style_for(row)
		r.ring = radius > 0.0
		var pts: PackedVector2Array
		if r.ring:
			pts = LaneStyle.ring_points(a, radius, int(MapLogic.cfg()["ring_samples"]))
		else:
			var c := MapLogic.lane_curve_for(row, a, b, 0.0)
			pts = MapLogic.sample_quad(c["a"], c["c"], c["b"], int(MapLogic.cfg()["ribbon_samples"]))
		_build(r, pts, LaneStyle.lit_half_extent(r.style), float(MapLogic.cfg()["chevron_size_px"]))
		r.mode = "stale"
		_note_build(t0)
	return r


func _gutter(row: Dictionary) -> Ribbon:
	var r: Ribbon = _gutters.get(row["id"])
	if r == null:
		r = _new_ribbon(row, _gutter_layer)
		_gutters[row["id"]] = r
	r.row = row
	var a := model.node_pos(row["from"])
	var b := model.node_pos(row["to"])
	var key := "%s|%s" % [a, b]
	if key != r.geo_key:
		var t0 := Time.get_ticks_usec()
		r.geo_key = key
		r.style = LaneStyle.style_for(row)
		# built once on the off/off reference curve; gutter_curve only translates it with u
		var ref := MapLogic.gutter_curve(a, b, LaneStyle.OFF, LaneStyle.OFF)
		r.origin = ref["a"]
		var pts := MapLogic.sample_quad(ref["a"], ref["c"], ref["b"], int(MapLogic.cfg()["ribbon_samples"]))
		_build(r, pts, LaneStyle.gutter_half_extent(), float(MapLogic.cfg()["gutter_chevron_size_px"]))
		r.mode = "stale"
		_note_build(t0)
	return r


func _build(r: Ribbon, pts: PackedVector2Array, half: float, chev_size: float) -> void:
	var rb := LaneStyle.ribbon(pts, half, r.ring)
	r.node.mesh = LaneStyle.to_mesh(rb)
	r.pts = pts
	r.cum = rb["cum"]
	r.length = rb["length"]
	r.mat.set_shader_parameter(&"half_extent", half)
	r.mat.set_shader_parameter(&"lane_len", r.length)
	r.mat.set_shader_parameter(&"chev_size", chev_size)
	r.mat.set_shader_parameter(&"chev_width", LaneStyle.chevron_stroke(chev_size))
	r.mat.set_shader_parameter(&"chev_on", 1.0 if _chev else 0.0)


func _note_build(t0: int) -> void:
	_build_ms += (Time.get_ticks_usec() - t0) / 1000.0
	_builds += 1
	_built_this_frame = true


func _apply_lane(r: Ribbon, u: float, hosts_live_dead: bool) -> void:
	var mode := LaneStyle.lane_mode(u, hosts_live_dead)
	if mode == "off":
		_hide(r)
		return
	var eps := float(MapLogic.cfg()["u_epsilon"])
	if mode == r.mode and (mode == "phantom" or absf(u - r.u) <= eps):
		return
	r.mode = mode
	r.u = u
	var layers: Array
	if mode == "phantom":
		layers = LaneStyle.phantom_layers(r.style)
		_set_motion(r, {"period": 1.0, "dash": 1.0, "speed": 0.0})
		r.mat.set_shader_parameter(&"chev_col", Palette.c("void", 0.0))
	else:
		var ch: Dictionary = Pulse.channels(u, Palette.hue(r.style["hue_key"]))
		layers = LaneStyle.lit_layers(ch, r.style)
		_set_motion(r, LaneStyle.motion(ch, r.style, r.length if r.ring else 0.0))
		r.mat.set_shader_parameter(&"chev_col", LaneStyle.core_color(ch, r.style))
	_set_layers(r, layers)
	r.node.visible = true


func _apply_gutter(r: Ribbon, u_dead: float, u_host: float) -> void:
	if not LaneStyle.gutter_on(u_dead):
		_hide(r)
		return
	var eps := float(MapLogic.cfg()["u_epsilon"])
	if r.mode == "lit" and absf(u_dead - r.u) <= eps and is_equal_approx(u_host, r.u_host):
		return
	r.mode = "lit"
	r.u = u_dead
	r.u_host = u_host
	var ch: Dictionary = Pulse.channels(u_dead, Palette.hue(r.style["hue_key"]))
	_set_layers(r, LaneStyle.gutter_layers(ch))
	_set_motion(r, LaneStyle.motion(ch, r.style))
	r.mat.set_shader_parameter(&"chev_col", LaneStyle.gutter_chevron_color(ch))
	var a := model.node_pos(r.row["from"])
	var b := model.node_pos(r.row["to"])
	r.node.position = MapLogic.gutter_curve(a, b, u_host, u_dead)["a"] - r.origin
	r.node.visible = true


func _set_layers(r: Ribbon, layers: Array) -> void:
	var p := LaneStyle.pack(layers)
	r.mat.set_shader_parameter(&"widths", p["widths"])
	r.mat.set_shader_parameter(&"offsets", p["offsets"])
	r.mat.set_shader_parameter(&"dashed", p["dashed"])
	for i in LaneStyle.MAX_LAYERS:
		r.mat.set_shader_parameter(COL_PARAMS[i], p["colors"][i])


func _set_motion(r: Ribbon, m: Dictionary) -> void:
	r.speed = m["speed"]
	r.period = m["period"]
	r.mat.set_shader_parameter(&"period", m["period"])
	r.mat.set_shader_parameter(&"dash", m["dash"])
	r.mat.set_shader_parameter(&"offset", Pulse.dash_offset(r.speed, r.period))


func _track(r: Ribbon) -> Dictionary:
	var c := LaneStyle.carts(float(r.row["rate"]), r.speed, r.length)
	return {"pts": r.pts, "cum": r.cum, "length": r.length, "speed": r.speed,
		"spacing": c["spacing"], "pips": c["pips"]}


# --- chevrons: reduced motion, or mid zoom and nearer ------------------------------------

func _sync_chevrons() -> void:
	if _cam == null or not is_instance_valid(_cam):
		_cam = get_viewport().get_camera_2d()
	var tier := "mid"
	if _cam is MapCamera:
		tier = (_cam as MapCamera).tier
	elif _cam != null:
		tier = MapLogic.zoom_tier(_cam.zoom.x, _tier)
	var on := LaneStyle.chevrons_on(Pulse.reduced_motion, tier)
	_tier = tier
	if on == _chev:
		return
	_chev = on
	for r: Ribbon in _lanes.values() + _gutters.values():
		r.mat.set_shader_parameter(&"chev_on", 1.0 if on else 0.0)
