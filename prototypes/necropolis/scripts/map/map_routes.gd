class_name MapRoutes
extends Node2D
## Flow lines: the rate rendered, never a convoy tracked (BRIEF motion canon). Drawn from the
## shared MapModel's lanes only, as shader ribbons (shaders/map_lane.gdshader): one
## MeshInstance2D per lane, its mesh built once along MapLogic's curve, its look in uniforms.
## Lit lanes first, then every dead gutter (so the cut bites into the halos), then the carts.
## Per frame: one dash-offset uniform per visible lane. On a model rev: each lane's channels,
## with uniforms touched only when u moved by u_epsilon, the lane turned on, off or phantom, or
## it went quiet or loud. Quiet (LaneStyle.quiet_ids): with a fort selected, every lane off it and
## off Relish's fort; with none, each kind's lanes past glow_cap_per_kind (Relish's fort's lanes
## stay loud); re-applied on a selection too.
## Near zoom: the shader turns each war / flood / work / living lane's dashes into unit glyphs
## (GlyphLogic); the routes only set each lane's glyph shape once and the crossfade weight when
## the zoom moves it.
## Victory (set_victory, from MapSetpieces): every lane takes the undead hue at
## SetpieceLogic.victory_u, lanes leaving Vei are rebuilt reversed so every one runs toward her,
## and at "stop" every dash, gutter and cart freezes where it stands (their clock holds).
## Styling and tables: scripts/map/lane_style_logic.gd. Tuning: configs/map_view.json.

const SHADER := preload("res://shaders/map_lane.gdshader")
const CARTS_SCRIPT := preload("res://scripts/map/map_carts.gd")
const COL_PARAMS: Array[StringName] = [&"col0", &"col1", &"col2", &"col3"]
const GCOL_PARAMS: Array[StringName] = [&"gcol0", &"gcol1", &"gcol2", &"gcol3"]

var model: MapModel
## GDScript ms the routes spent last frame (offsets, any refresh, the cart overlay's draw).
var routes_ms := 0.0
## Debug only (world_map sets it for --lanes-report): print the live lanes' u and hue once at boot,
## lanes_report_wait_s after the first refresh (a fixture's valve lanes appear after the first
## sim substeps).
var lanes_report := false
## The fort whose card is open (world_map sets it): only a selection quiets every other lane.
var selected_id := "":
	set(v):
		selected_id = v
		_refocus()


## One lane's (or one gutter's) ribbon node and the state its uniforms were last set from.
class Ribbon:
	var node: MeshInstance2D
	var mat: ShaderMaterial
	var row := {}
	var style := {}
	var built := false
	var a := Vector2.ZERO
	var b := Vector2.ZERO
	var radius := 0.0
	var origin := Vector2.ZERO  # gutter: start of the reference curve its mesh was built on
	var min_cos := 1.0  # gutter: LaneStyle.lateral_cos_min of its curve
	var pts := PackedVector2Array()
	var cum := PackedFloat32Array()
	var length := 0.0
	var trim := Vector2.ZERO  # arc length not drawn at the start and end (inside the nodes)
	var ring := false
	var mode := "off"
	var quiet := false  # lit, but out of focus or past the glow cap: the core alone, narrower
	var u := -2.0
	var u_host := -2.0
	var vic := false  # styled for victory (undead hue, never quiet)
	var reversed := false  # built from `to` back to `from` (victory: a lane leaving Vei runs toward her)
	var lit := false  # gutter: its fort stands in Relish's light (dead_lit instead of dead)
	var speed := 0.0
	var period := 1.0
	var anchor_ms := 0.0  # Pulse's clock when speed/period last changed, and the offset then
	var anchor_off := 0.0
	var cart_spacing := 0.0  # haul lanes: the cart train, re-derived only when the lane's motion changed
	var cart_pips := 0
	var cart_speed := 0.0
	var cart_ms := 0.0
	var cart_off := 0.0


var _lanes := {}    # lane id -> Ribbon
var _gutters := {}  # dead lane id -> Ribbon
var _lit_forts := {}  # fort id -> true: forts in Relish's light (set_lit_forts)
var _moving: Array = []  # lit Ribbons this rev: their offsets walk every frame
var _lane_layer: Node2D
var _gutter_layer: Node2D
var _carts: Node2D
var _rev := -2
var _cfg_ref = null
var _chev := false
var _snap := false
var _eps := 0.0
var _tier := ""
var _glyph_w := 0.0  # GlyphLogic.near_weight at the camera's zoom, as last set on the lanes
var _cam: Camera2D
var _log_max := 0.0
var _vei_outer := -1.0  # Vei's trim radius (structure + backlog stack + beat ring) the lanes were last trimmed to
var _reported := false
var _report_ms := -1.0  # Pulse's clock when the --lanes-report table prints
var _victory := ""  # "" | SetpieceLogic.RUN | SetpieceLogic.STOP
var _hold_ms := -1.0  # victory's stop: the clock every offset is taken at from then on (-1: live)

# bench readout (--bench-seconds): per ground mode, the routes' ms per frame
var _bench := false
var _samples := {}
var _build_ms := 0.0
var _builds := 0
var _built_this_frame := false
var _last_us := 0
var _syncs := 0
var _sync_ms_max := 0.0
var _sync_ms_sum := 0.0
var _updates := 0
var _cart_ms_max := 0.0


## The single source of lane geometry, forwarded so callers (the ground) can reach it from the
## routes script. Both return {a, c, b, half_width, loop}: the quadratic Bezier's start, control
## and end, the CORE stroke's half width (before commit_width_mult and the halo), and whether it
## is a self-loop. Use lane_curve_for for any view_lanes row: it knows the direct FLOOD lane's
## flood_direct_bow, which lane_curve(a, b, u) alone cannot reproduce. lane_curve is the plain
## curve between two points (bow < 0: the config default).
static func lane_curve(from_pos: Vector2, to_pos: Vector2, u: float, bow := -1.0) -> Dictionary:
	return MapLogic.lane_curve(from_pos, to_pos, u, bow)


static func lane_curve_for(row: Dictionary, from_pos: Vector2, to_pos: Vector2, u: float) -> Dictionary:
	return MapLogic.lane_curve_for(row, from_pos, to_pos, u)


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
			var ms := (Time.get_ticks_usec() - ts) / 1000.0
			_syncs += 1
			_sync_ms_sum += ms
			_sync_ms_max = maxf(_sync_ms_max, ms)
	_sync_chevrons()
	if lanes_report and not _reported and _report_ms >= 0.0 and Pulse.now_ms() >= _report_ms:
		_reported = true
		_print_report()
	var now := _clock()
	var rm: bool = Pulse.reduced_motion
	for r: Ribbon in _moving:
		r.mat.set_shader_parameter(&"offset", LaneStyle.phase_offset(r.anchor_off, r.anchor_ms, now, r.speed, r.period, rm))
	_carts.tick(_tier != "far")
	_last_us = Time.get_ticks_usec() - t0


## Pulse's clock for the dashes: live, or held where victory's stop froze them.
func _clock() -> float:
	return _hold_ms if _hold_ms >= 0.0 else Pulse.now_ms()


## Victory (MapSetpieces): RUN lights every lane in the undead hue, running toward Vei; STOP also
## freezes every dash, gutter and cart at this instant; "" goes back to the views' styling. A
## change of styling restyles every lane on the next frame's sync.
func set_victory(phase: String) -> void:
	if phase == _victory:
		return
	var restyle := (_victory != "") != (phase != "")
	_victory = phase
	_hold_ms = Pulse.now_ms() if phase == SetpieceLogic.STOP else -1.0
	_carts.hold_ms = _hold_ms
	if restyle:
		_rev = -2


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
		print("ROUTES_MS mode=%s n=%d mean=%.4f max=%.4f | lanes=%d gutters=%d moving=%d | syncs=%d updates=%d sync_mean=%.3f sync_max=%.3f cart_draw_max=%.3f | builds=%d build_ms=%.3f" % [
			mode, a.size(), sum / maxf(a.size(), 1.0), mx, _lanes.size(), _gutters.size(), _moving.size(),
			_syncs, _updates, _sync_ms_sum / maxf(_syncs, 1.0), _sync_ms_max, _cart_ms_max, _builds, _build_ms])


## F6 reloads ConfigDb (map_field_view handles the key): a new map_view dictionary means new
## tuning, so re-configure MapLogic and rebuild every ribbon.
func _check_config() -> void:
	var live = ConfigDb.data.get("map_view")
	if not live is Dictionary or is_same(live, _cfg_ref):
		return
	if _cfg_ref != null:
		MapLogic.configure(live)
		for r: Ribbon in _lanes.values() + _gutters.values():
			r.built = false
			r.mode = "stale"
		_rev = -2
	_cfg_ref = live
	_log_max = float(MapLogic.cfg()["rate_log_max"])
	_eps = float(MapLogic.cfg()["u_epsilon"])


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
	_retrim_vei()
	_moving.clear()
	var tracks: Array = []
	var seen := {}
	var drawn: Array = []
	var lit: Array = []
	for r in rows:
		if r["kind"] == "dead" or not model.has_node(r["from"]) or not model.has_node(r["to"]):
			continue
		drawn.append(r)
		if _u(r) >= 0.0:
			lit.append(r)
	var quiet := _quiet_ids(lit)
	for r in drawn:
		seen[r["id"]] = true
		var lane := _lane(r)
		_apply_lane(lane, _u(r), dead_on_host.has(r["id"]), quiet.has(r["id"]))
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
	if lanes_report and _report_ms < 0.0:
		_report_ms = Pulse.now_ms() + float(MapLogic.cfg()["lanes_report_wait_s"]) * 1000.0


## --lanes-report: one line per live lane and dead gutter, sorted by id: its rate, u, the u its
## hue comes from (LaneStyle.hue_u) and the hue that gives (a gutter is matte: no hue).
func _print_report() -> void:
	var lines: Array = []
	for r: Ribbon in _lanes.values() + _gutters.values():
		if r.mode == "lit":
			var key := str(r.style["hue_key"])
			var matte := bool(r.style["matte"])
			lines.append(LaneStyle.report_line(r.row, key, r.u, r.u if matte else LaneStyle.hue_u(r.u),
				-1.0 if matte else float(_channels(r.u, key)["hue"])))
	lines.sort()
	print(LaneStyle.report_header(_log_max, float(MapLogic.cfg()["hue_u_floor"])))
	for l in lines:
		print(l)


## A lit lane's channels: Pulse's at the real u, with the hue taken at LaneStyle.hue_u(u).
func _channels(u: float, hue_key: String) -> Dictionary:
	var hue := Palette.hue(hue_key)
	return LaneStyle.with_hue(Pulse.channels(u, hue), Pulse.channels(LaneStyle.hue_u(u), hue))


var _cap_memo := {}  # the glow cap's loud set last time: LaneStyle.quiet_ids keeps it steady


func _quiet_ids(lit_rows: Array) -> Dictionary:
	return LaneStyle.quiet_ids(lit_rows, LaneStyle.selection_focus(selected_id, model.forts_by_id),
		LaneStyle.relish_focus(model.relish, model.forts_by_id), int(MapLogic.cfg()["glow_cap_per_kind"]),
		_cap_memo, float(MapLogic.cfg()["glow_cap_hysteresis"]))


## A selection changed the focus: re-apply only the lit lanes whose quiet flag flipped.
func _refocus() -> void:
	if model == null or _rev < 0:
		return
	var lit: Array = []
	for r: Ribbon in _lanes.values():
		if r.mode == "lit":
			lit.append(r.row)
	var quiet := _quiet_ids(lit)
	for r: Ribbon in _lanes.values():
		if r.mode == "lit" and quiet.has(r.row["id"]) != r.quiet:
			_apply_lane(r, r.u, false, quiet.has(r.row["id"]))


## The forts whose dead lane's gutter reads dead_lit (still matte) instead of dead: the nodes
## layer calls this on a model refresh with the forts inside Relish's light. Only gutters whose
## state changed touch their uniforms.
func set_lit_forts(ids: Array) -> void:
	var now := {}
	for id in ids:
		now[id] = true
	_lit_forts = now
	for r: Ribbon in _gutters.values():
		if r.mode == "lit" and r.lit != _lit_forts.has(str(r.row["from"])):
			_apply_gutter(r, r.u, r.u_host)


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
	var rev := _victory != "" and str(row["from"]) == MapModel.VEI and a != b
	if not r.built or a != r.a or b != r.b or radius != r.radius or rev != r.reversed:
		var t0 := Time.get_ticks_usec()
		r.built = true
		r.a = a
		r.b = b
		r.radius = radius
		r.style = LaneStyle.style_for(row)
		r.ring = radius > 0.0
		var pts: PackedVector2Array
		if r.ring:
			pts = LaneStyle.ring_points(a, radius, int(MapLogic.cfg()["ring_samples"]))
		else:
			var c := MapLogic.lane_curve_for(row, a, b, 0.0)
			pts = MapLogic.sample_quad(c["a"], c["c"], c["b"], int(MapLogic.cfg()["ribbon_samples"]))
			if rev:
				pts.reverse()  # the same curve, walked from the fort back to Vei
		r.reversed = rev
		_build(r, pts, LaneStyle.lit_half_extent(r.style), float(MapLogic.cfg()["chevron_size_px"]), true, row)
		_glyph_shape(r)
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
	if not r.built or a != r.a or b != r.b:
		var t0 := Time.get_ticks_usec()
		r.built = true
		r.a = a
		r.b = b
		r.style = LaneStyle.style_for(row)
		# built once on the off/off reference curve; gutter_curve only translates it with u
		var ref := MapLogic.gutter_curve(a, b, LaneStyle.OFF, LaneStyle.OFF)
		r.origin = ref["a"]
		var pts := MapLogic.sample_quad(ref["a"], ref["c"], ref["b"], int(MapLogic.cfg()["ribbon_samples"]))
		r.min_cos = LaneStyle.lateral_cos_min(pts, a, b)
		_build(r, pts, LaneStyle.gutter_half_extent(), float(MapLogic.cfg()["gutter_chevron_size_px"]), false, row)
		r.mode = "stale"
		_note_build(t0)
	return r


## round_caps: lit lanes give their dashes round caps; the gutter keeps butt ends (06).
func _build(r: Ribbon, pts: PackedVector2Array, half: float, chev_size: float, round_caps: bool, row: Dictionary) -> void:
	var rb := LaneStyle.ribbon(pts, half, r.ring)
	r.node.mesh = LaneStyle.to_mesh(rb)
	r.pts = pts
	r.cum = rb["cum"]
	r.length = rb["length"]
	r.mat.set_shader_parameter(&"half_extent", half)
	r.mat.set_shader_parameter(&"round_caps", 1.0 if round_caps else 0.0)
	r.mat.set_shader_parameter(&"lane_len", r.length)
	# lanes stop at the nodes' outer rings (a self-loop ring is untouched); only the drawn range
	# changes, never the curve or the mesh
	_trim(r)
	r.mat.set_shader_parameter(&"chev_size", chev_size)
	r.mat.set_shader_parameter(&"chev_width", LaneStyle.chevron_stroke(chev_size))
	r.mat.set_shader_parameter(&"chev_on", 1.0 if _chev else 0.0)
	r.mat.set_shader_parameter(&"chev_snap", 1.0 if _snap else 0.0)


## A lane's near-zoom glyph (GlyphLogic.kind_for its kind): its shape, set once per build, and the
## crossfade weight it starts at. Its glyph_kind is set when it lights (_apply_lane: 0 while
## phantom); gutters keep 0 (dead matter has no unit glyph).
func _glyph_shape(r: Ribbon) -> void:
	var sh := GlyphLogic.shape(GlyphLogic.kind_for(str(r.style["kind"])))
	r.mat.set_shader_parameter(&"glyph_len", sh["len"])
	r.mat.set_shader_parameter(&"glyph_sag", sh["sag"])
	r.mat.set_shader_parameter(&"head_r", sh["head_r"])
	r.mat.set_shader_parameter(&"head_w", sh["head_w"])
	r.mat.set_shader_parameter(&"glyph_mix", _glyph_w)


## The arc length a ribbon does not draw at each end (a self-loop ring is untouched).
func _trim(r: Ribbon) -> void:
	var t := {"start": 0.0, "end": 0.0}
	if not r.ring:
		var ends := [str(r.row["to"]), str(r.row["from"])] if r.reversed else [str(r.row["from"]), str(r.row["to"])]
		t = NodeLogic.trim_lengths(_outer(ends[0]), _outer(ends[1]), r.length)
	r.trim = Vector2(t["start"], t["end"])
	r.mat.set_shader_parameter(&"trim_start", r.trim.x)
	r.mat.set_shader_parameter(&"trim_end", r.trim.y)


## Vei's trim radius follows her backlog stack: when the rings shown (or her radius) change,
## the lanes that end or start at her are re-trimmed. A refresh-time check, no per-frame cost.
func _retrim_vei() -> void:
	var o := _outer(MapModel.VEI)
	if is_equal_approx(o, _vei_outer):
		return
	_vei_outer = o
	for r: Ribbon in _lanes.values() + _gutters.values():
		if r.built and (str(r.row["from"]) == MapModel.VEI or str(r.row["to"]) == MapModel.VEI):
			_trim(r)


## Where a lane stops at node `id` (the set pieces' bands stop there too).
func node_trim_radius(id: String) -> float:
	return _outer(id)


## Where lanes stop at a node: its outermost drawn radius (NodeLogic.outer_radius); at Vei that
## reaches past her backlog stack and beat ring so a lane never crosses the rings to count.
func _outer(id: String) -> float:
	if id == MapModel.COVINGTON:
		return NodeLogic.outer_radius("covington", 0, 0.0)
	if id == MapModel.VEI:
		return NodeLogic.outer_radius("vei", 0, float(model.realm.get("vei", {}).get("radius", 0.0)), float(model.vei.get("backlog", 0.0)))
	if model.forts_by_id.has(id):
		return NodeLogic.outer_radius("fort", int(model.fort(id)["tier"]), 0.0)
	return 0.0


func _note_build(t0: int) -> void:
	_build_ms += (Time.get_ticks_usec() - t0) / 1000.0
	_builds += 1
	_built_this_frame = true


func _apply_lane(r: Ribbon, u: float, hosts_live_dead: bool, quiet := false) -> void:
	var vic := _victory != ""
	if vic:  # every lane lights, loud, at victory's floor
		u = SetpieceLogic.victory_u(u)
		quiet = false
	var mode := LaneStyle.lane_mode(u, hosts_live_dead)
	if mode == "off":
		_hide(r)
		return
	quiet = quiet and mode == "lit"
	if mode == r.mode and quiet == r.quiet and vic == r.vic and (mode == "phantom" or absf(u - r.u) <= _eps):
		return
	r.mode = mode
	r.quiet = quiet
	r.u = u
	r.vic = vic
	var style := _victory_style(r.style) if vic else r.style
	_updates += 1
	var layers: Array
	if mode == "phantom":
		layers = LaneStyle.phantom_layers(r.style)
		_set_motion(r, {"period": 1.0, "dash": 1.0, "speed": 0.0})
		r.mat.set_shader_parameter(&"chev_col", Palette.c("void", 0.0))
		r.mat.set_shader_parameter(&"glyph_kind", 0.0)
	else:
		var ch := _channels(u, str(style["hue_key"]))
		layers = LaneStyle.lit_layers(ch, style, quiet)
		_set_motion(r, LaneStyle.motion(ch, style, r.length if r.ring else 0.0))
		var core := LaneStyle.core_color(ch, style, quiet)
		r.mat.set_shader_parameter(&"chev_col", core)
		# the glyph: the lane's stack at the glyph's stroke width in the lane colour, its head in the core colour
		var glyph := GlyphLogic.kind_for(str(r.style["kind"]))
		var gp := LaneStyle.pack(LaneStyle.glyph_layers(ch, style, quiet, float(GlyphLogic.shape(glyph)["width"])))
		r.mat.set_shader_parameter(&"glyph_kind", GlyphLogic.shader_kind(glyph))
		r.mat.set_shader_parameter(&"gwidths", gp["widths"])
		for i in LaneStyle.MAX_LAYERS:
			r.mat.set_shader_parameter(GCOL_PARAMS[i], gp["colors"][i])
		r.mat.set_shader_parameter(&"glyph_core", core)
	_set_layers(r, layers)
	if mode == "lit" and str(r.row["kind"]) == "haul":
		_set_carts(r)
	r.node.visible = true


## A lane's style in victory: the undead hue and its pale core; its own dash rhythm and width.
func _victory_style(style: Dictionary) -> Dictionary:
	var s := style.duplicate()
	s["hue_key"] = "undead"
	s["core"] = Palette.c("undead_core")
	return s


func _apply_gutter(r: Ribbon, u_dead: float, u_host: float) -> void:
	if not LaneStyle.gutter_on(u_dead):
		_hide(r)
		return
	var lit := _lit_forts.has(str(r.row["from"]))
	if r.mode == "lit" and absf(u_dead - r.u) <= _eps and is_equal_approx(u_host, r.u_host) and lit == r.lit:
		return
	r.mode = "lit"
	r.lit = lit
	r.u = u_dead
	_updates += 1
	r.u_host = u_host
	var ch: Dictionary = Pulse.channels(u_dead, Palette.hue(r.style["hue_key"]))
	# the spill stops at the host core's drawn edge (u_host < 0: the phantom's u = 0 geometry)
	var host_half := MapLogic.lane_half_width(u_host)
	_set_layers(r, LaneStyle.gutter_layers(ch, host_half, r.min_cos, lit))
	r.mat.set_shader_parameter(&"clip_edge", LaneStyle.host_edge(host_half, MapLogic.gutter_width(u_dead), r.min_cos))
	r.mat.set_shader_parameter(&"clip_half", host_half)
	_set_motion(r, LaneStyle.motion(ch, r.style))
	r.mat.set_shader_parameter(&"chev_col", LaneStyle.gutter_chevron_color(ch, lit))
	r.node.position = MapLogic.gutter_curve(r.a, r.b, u_host, u_dead)["a"] - r.origin
	r.node.visible = true


func _set_layers(r: Ribbon, layers: Array) -> void:
	var p := LaneStyle.pack(layers)
	r.mat.set_shader_parameter(&"widths", p["widths"])
	r.mat.set_shader_parameter(&"offsets", p["offsets"])
	r.mat.set_shader_parameter(&"dashed", p["dashed"])
	r.mat.set_shader_parameter(&"hairline", p["hairline"])
	for i in LaneStyle.MAX_LAYERS:
		r.mat.set_shader_parameter(COL_PARAMS[i], p["colors"][i])


## A motion change keeps the phase: the offset shown now becomes the new anchor on Pulse's clock.
func _set_motion(r: Ribbon, m: Dictionary) -> void:
	var now := _clock()
	r.anchor_off = LaneStyle.rebase_offset(r.anchor_off, r.anchor_ms, now, r.speed, r.period, m["period"])
	r.anchor_ms = now
	r.speed = m["speed"]
	r.period = m["period"]
	r.mat.set_shader_parameter(&"period", m["period"])
	r.mat.set_shader_parameter(&"dash", m["dash"])
	r.mat.set_shader_parameter(&"offset", LaneStyle.phase_offset(r.anchor_off, r.anchor_ms, now, r.speed, r.period, Pulse.reduced_motion))


## Haul lanes: the cart train is re-derived only when the lane's motion changed (the same
## u_epsilon gate as the dashes), anchored so the lead cart keeps its place.
func _set_carts(r: Ribbon) -> void:
	var c := LaneStyle.carts(float(r.row["rate"]), r.speed, r.length)
	var now := _clock()
	r.cart_off = LaneStyle.cart_anchor(r.cart_off, r.cart_ms, now, r.cart_speed, r.cart_spacing, c["spacing"], r.length)
	r.cart_ms = now
	r.cart_speed = r.speed
	r.cart_spacing = c["spacing"]
	r.cart_pips = c["pips"]


func _track(r: Ribbon) -> Dictionary:
	return {"pts": r.pts, "cum": r.cum, "length": r.length, "speed": r.cart_speed, "lo": r.trim.x, "hi": r.length - r.trim.y,
		"spacing": r.cart_spacing, "pips": r.cart_pips, "anchor_off": r.cart_off, "anchor_ms": r.cart_ms}


# --- chevrons: reduced motion, or mid zoom and nearer; snapped into the gaps while frozen ---
# --- and the near crossfade: the lanes' glyph weight, set only when the zoom changed it ---

func _sync_chevrons() -> void:
	if _cam == null or not is_instance_valid(_cam):
		_cam = get_viewport().get_camera_2d()
	var tier := "mid"
	if _cam is MapCamera:
		tier = (_cam as MapCamera).tier
	elif _cam != null:
		tier = MapLogic.zoom_tier(_cam.zoom.x, _tier)
	var gw := GlyphLogic.near_weight(_cam.zoom.x) if _cam != null else 0.0
	if gw != _glyph_w:
		_glyph_w = gw
		for r: Ribbon in _lanes.values():
			r.mat.set_shader_parameter(&"glyph_mix", gw)
	var on := LaneStyle.chevrons_on(Pulse.reduced_motion, tier)
	var snap: bool = Pulse.reduced_motion
	_tier = tier
	if on == _chev and snap == _snap:
		return
	_chev = on
	_snap = snap
	for r: Ribbon in _lanes.values() + _gutters.values():
		r.mat.set_shader_parameter(&"chev_on", 1.0 if on else 0.0)
		r.mat.set_shader_parameter(&"chev_snap", 1.0 if snap else 0.0)
