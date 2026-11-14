class_name MapSetpieces
extends Node
## The map's set pieces (VISUAL-LANGUAGE 2e), each a short treatment on the tempo, and the quiet
## tempo pulse on every beat at Covington (hop 0):
##   valve swing   a committed valve (MapValve.committed): Covington's stems tween to the new
##                 shares over one beat, brighter for that beat; Synth "whoosh".
##   flip          fort_flipped: the fort's ring re-inks orange to green segment by segment from
##                 12 o'clock over 1.5 beats, then its glyph and chip change; Synth "flip". The
##                 game's first flip adds a green ripple on the fort's beat and a callout.
##   tithe         tithe_warning: Synth "horn"; tithe_wave: an orange band sweeps from Vei along the
##                 living lane to the target fort over 2 beats.
##   garrison      counter_garrison_cleared (or its stand-in, api-request #10): a green pulse along
##                 the fort's WAR lane from Covington, a green burst at the fort, the chip's
##                 counter-garrison draining to 0 and flipping to the margin word, a callout.
##   victory       vei_result won (or won at map open): every lane runs green toward Vei for 2
##                 beats, then every dash stops and the victory line shows.
## Garrison and victory play no sound of their own (VISUAL-LANGUAGE 2f names none).
## It hears events through Game.game_event (the router re-emits the ones it held while the map
## mounted). It drives the existing layers through small hooks: MapNodes' context
## (valve_shares / valve_bright, reink, chip_fx) and redraw_* calls, MapRoutes.set_victory,
## MapHud.show_victory and its own MapSetpieceLayer (bands, rings, callouts). Set pieces wait
## until go_live (world_map calls it once the camera's ease out of the scene just left is over),
## so they play where the player can see them. Every clock is beats on Pulse's wall clock, so
## reduced motion (each set piece straight to its end state) still times them; sounds still play.
## Debug: --setpiece=<kind> fires one at a demo fort debug_delay_s after going live;
## --setpiece-slow=k stretches every set piece k times. Always pair them with --fixture=:
## --setpiece=valve sends a real cmd_set_valve, and --setpiece is not a harness arg (DEV_ARGS),
## so without a fixture it would autosave over the shared auto.json (api-request #11). Timing: setpiece_logic.gd. Tuning:
## configs/map_view.json "setpieces"; sounds: configs/synth.json.

var model: MapModel
var nodes: MapNodes
var routes: MapRoutes
var hud: MapHud
var valve: MapValve
var layer: MapSetpieceLayer

var _synth: Synth
var _live := false
var _queue: Array = []  # set pieces that arrived before go_live: {kind, fort_id, n}
var _active: Array = []  # running: {kind, fort_id, n, start_ms, track?}
var _seen := {}  # fort id -> {event type: true} since the map opened (the garrison stand-in)
var _arrive_from := ""
var _standin_in := -1  # frames until the garrison stand-in is checked (-1: never)
var _beat := -1
var _slow := 1.0
var _debug_kind := ""
var _committed := {}  # the valve Covington's stems show at rest
var _swing := {}  # {from, to, start_ms} while the valve swing runs
var _valve_rev := -1  # the model.rev the idle valve target was last read at
var _won := false  # victory has played (or is playing): once per map


func _ready() -> void:
	_synth = Synth.new()
	_synth.name = "Synth"
	add_child(_synth)
	_synth.warm(["pulse", "whoosh", "horn", "flip"])
	Game.game_event.connect(on_event)
	valve.committed.connect(_on_valve_committed)
	var dbg := SetpieceLogic.debug_args(OS.get_cmdline_user_args(), Game.state.debug_enabled)
	_slow = float(dbg["slow"])
	_debug_kind = str(dbg["kind"])
	_committed = _target()
	nodes.ctx.valve_shares = _committed


func _exit_tree() -> void:
	if Game.game_event.is_connected(on_event):
		Game.game_event.disconnect(on_event)


func on_event(ev: Dictionary) -> void:
	var type := str(ev.get("type", ""))
	var id := str(ev.get("fort_id", ""))
	if type == "relish_died":
		id = SetpieceLogic.ANY_FORT  # a death names no fort: any held fort's stand-in refuses it
	if id != "":
		if not _seen.has(id):
			_seen[id] = {}
		_seen[id][type] = true
	match type:
		"fort_flipped":
			_add(SetpieceLogic.FIRST_FLIP if SetpieceLogic.first_flip(id, model.forts) else SetpieceLogic.FLIP, id)
		"tithe_warning":
			_synth.play("horn")
		"tithe_wave":
			_add(SetpieceLogic.TITHE, id)
		"counter_garrison_cleared":
			var g := SetpieceLogic.garrison_from_event(ev)
			_add(SetpieceLogic.GARRISON, str(g["fort_id"]), int(g["n"]))
		"vei_result":
			if bool(ev.get("won", false)):
				_add(SetpieceLogic.VICTORY, "")


## The camera has settled on the map: queued set pieces start, a won realm plays victory, the
## garrison stand-in is checked a few frames on (so the return's events have all arrived), and
## the debug trigger is armed. `arrive_from`: the node whose scene was just left.
func go_live(arrive_from: String) -> void:
	if _live or not is_inside_tree():
		return
	_live = true
	_arrive_from = arrive_from
	if bool(model.hud.get("won", false)):
		_add(SetpieceLogic.VICTORY, "")
	for p in _queue:
		_start(p)
	_queue.clear()
	_standin_in = int(SetpieceLogic.cfg()["standin_frames"]) if model.forts_by_id.has(arrive_from) else -1
	if _debug_kind != "":
		get_tree().create_timer(float(SetpieceLogic.cfg()["debug_delay_s"])).timeout.connect(_fire_debug)


func _add(kind: String, fort_id: String, n := -1) -> void:
	var p := {"kind": kind, "fort_id": fort_id, "n": n}
	if _live:
		_start(p)
	else:
		_queue.append(p)


func _start(p: Dictionary) -> void:
	var kind := str(p["kind"])
	var id := str(p["fort_id"])
	if kind == SetpieceLogic.VICTORY:
		if _won:
			return
		_won = true
	elif not model.forts_by_id.has(id):
		return
	for q in _active.duplicate():  # the same set piece at the same fort restarts
		if str(q["fort_id"]) == id and (str(q["kind"]) == kind or (kind in [SetpieceLogic.FLIP, SetpieceLogic.FIRST_FLIP] and str(q["kind"]) in [SetpieceLogic.FLIP, SetpieceLogic.FIRST_FLIP])):
			_active.erase(q)
	p["start_ms"] = Pulse.now_ms()
	_active.append(p)
	if kind == SetpieceLogic.FLIP or kind == SetpieceLogic.FIRST_FLIP:
		_synth.play("flip")
		if not Pulse.reduced_motion:
			nodes.ctx.reink[id] = {"switched": 0, "total": int(SetpieceLogic.cfg()["reink_segments"]), "from": NodeLogic.HERS}
			_redraw_fort_all(id)


func _process(_delta: float) -> void:
	_tempo()
	if _standin_in >= 0:
		_standin_in -= 1
		if _standin_in < 0:
			_check_standin()
	_valve_tick()
	var items: Array = []
	var now := Pulse.now_ms()
	var rm: bool = Pulse.reduced_motion
	for p in _active.duplicate():
		var t := SetpieceLogic.beats(float(p["start_ms"]), now, Pulse.tempo_ms, _slow)
		var done := true
		match str(p["kind"]):
			SetpieceLogic.FLIP, SetpieceLogic.FIRST_FLIP:
				done = _flip_tick(p, t, rm, items)
			SetpieceLogic.TITHE:
				done = _tithe_tick(p, t, rm, items)
			SetpieceLogic.GARRISON:
				done = _garrison_tick(p, t, rm, items)
			SetpieceLogic.VICTORY:
				done = _victory_tick(t, rm)
		if done:
			_active.erase(p)
	layer.set_items(items)


## The tempo pulse: a quiet thump on each beat at Covington. Counted from the clock, so reduced
## motion (a steady Pulse.phase) never silences it; muted, Synth plays nothing.
func _tempo() -> void:
	var b := SetpieceLogic.beat_index(Pulse.now_ms(), Pulse.tempo_ms)
	if b != _beat:
		if _beat >= 0:
			_synth.play("pulse")
		_beat = b


# --- the valve swing --------------------------------------------------------------------------

func _target() -> Dictionary:
	return ValveLogic.normalise(model.hud.get("valve_target", model.hud.get("valve", {})))


func _on_valve_committed(v: Dictionary) -> void:
	_swing_to(ValveLogic.normalise(v))


## Swings the stems from what they show now to `v` over one beat, with the whoosh. A commit that
## did not move the valve is no swing.
func _swing_to(v: Dictionary) -> void:
	var drawn: Dictionary = nodes.ctx.valve_shares if not nodes.ctx.valve_shares.is_empty() else _committed
	_committed = v
	if not SetpieceLogic.valve_moved(drawn, v):
		return
	_swing = {"from": drawn.duplicate(), "to": v, "start_ms": Pulse.now_ms()}
	_synth.play("whoosh")


## While a swing runs, tween the stems; otherwise follow a target changed from outside the panel
## (a load, a fixture) without one. Held while the handle is dragged.
func _valve_tick() -> void:
	var ctx := nodes.ctx
	if not _swing.is_empty():
		var t := SetpieceLogic.beats(float(_swing["start_ms"]), Pulse.now_ms(), Pulse.tempo_ms, _slow)
		var rm: bool = Pulse.reduced_motion
		ctx.valve_shares = SetpieceLogic.valve_shares(_swing["from"], _swing["to"], t, rm)
		ctx.valve_bright = SetpieceLogic.valve_bright(t, rm)
		if SetpieceLogic.valve_done(t):
			_swing = {}
			ctx.valve_shares = _committed
			ctx.valve_bright = 0.0
		nodes.redraw_covington()
		return
	if valve.is_dragging() or model.rev == _valve_rev:
		return  # idle: nothing to read until the model re-reads the game
	_valve_rev = model.rev
	var target := _target()
	if SetpieceLogic.valve_moved(target, _committed):
		_committed = target
		ctx.valve_shares = target
		nodes.redraw_covington()


# --- the flip ---------------------------------------------------------------------------------

func _flip_tick(p: Dictionary, t: float, rm: bool, items: Array) -> bool:
	var id := str(p["fort_id"])
	var ctx := nodes.ctx
	var done := SetpieceLogic.reink_done(t, rm)
	if not done:
		var cnt := SetpieceLogic.reink_count(t, rm)
		var rk: Dictionary = ctx.reink.get(id, {})
		if rk.is_empty() or int(rk["switched"]) != cnt:
			ctx.reink[id] = {"switched": cnt, "total": int(SetpieceLogic.cfg()["reink_segments"]), "from": NodeLogic.HERS}
			nodes.redraw_fort(id)
	elif ctx.reink.has(id):
		ctx.reink.erase(id)
		_redraw_fort_all(id)  # the ring is done: now the glyph and the chip change
	if str(p["kind"]) != SetpieceLogic.FIRST_FLIP:
		return done
	var c := SetpieceLogic.cfg()
	var f := model.fort(id)
	if f.is_empty():
		return done
	var rip := SetpieceLogic.ripple(Pulse.phase(model.hops_of(id)), t, rm)
	if not rip.is_empty():
		items.append({"kind": "ring", "pos": MapModel.to_vec(f["pos"]), "key": "undead", "alpha": float(rip["alpha"]),
			"r": MapLogic.fort_radius(int(f["tier"])) + float(c["ripple_reach_px"]) * float(rip["reach"]),
			"width": float(c["ripple_width_px"]), "cap": float(c["ripple_halo_max_px"])})
	var a := SetpieceLogic.callout_alpha(t, float(c["callout_beats"]), rm)
	if a > 0.0:
		items.append(_callout(id, SetpieceLogic.first_flip_text(str(model.names.get(id, id))), a))
	return done and t >= maxf(float(c["ripple_beats"]), float(c["callout_beats"]))


func _redraw_fort_all(id: String) -> void:
	nodes.redraw_fort(id)
	nodes.redraw_glyphs()
	nodes.redraw_chips()


## A callout centred above a fort's rings, callout_gap_px clear of them, and above Relish's token
## when she stands there (back from its dungeon, she does).
func _callout(id: String, text: String, alpha: float) -> Dictionary:
	var f := model.fort(id)
	var c := SetpieceLogic.cfg()
	var ctx := nodes.ctx
	var p := MapModel.to_vec(f["pos"])
	var gap := ctx.px(float(c["callout_gap_px"]))
	var y := p.y - NodeLogic.outer_radius("fort", int(f["tier"]), 0.0) - gap
	if str(model.relish.get("at", "")) == id and str(model.relish.get("state", "")) != "travelling":
		y = minf(y, ctx.relish_pos.y - float(NodeLogic.relish_radii(ctx.zoom)["halo"]) - gap)
	return {"kind": "label", "pos": Vector2(p.x, y), "text": text, "size": int(c["callout_font"]), "key": "undead", "alpha": alpha}


# --- bands along a lane -----------------------------------------------------------------------

## The track of the `kind` lane from `from` to `to` (the view's row when it has one, so the curve
## is the one the routes draw), trimmed off both nodes' rings.
func _track(kind: String, from: String, to: String) -> Dictionary:
	var row := {"id": "%s:%s:%s" % [kind, from, to], "kind": kind, "from": from, "to": to}
	for r in model.lanes:
		if str(r["id"]) == row["id"]:
			row = r
			break
	return SetpieceLogic.track(row, model.node_pos(from), model.node_pos(to), routes.node_trim_radius(from),
		routes.node_trim_radius(to), int(MapLogic.cfg()["ribbon_samples"]))


func _band(tr: Dictionary, b: Vector2, key: String, core: String, width: float, glow: float, cap: float) -> Dictionary:
	return {"kind": "band", "pts": SetpieceLogic.sub_polyline(tr["pts"], tr["cum"], b.x, b.y), "key": key, "core": core,
		"width": width, "glow": glow, "cap": cap}


func _tithe_tick(p: Dictionary, t: float, rm: bool, items: Array) -> bool:
	if not p.has("track"):
		p["track"] = _track("living", MapModel.VEI, str(p["fort_id"]))
	var tr: Dictionary = p["track"]
	var b := SetpieceLogic.tide(t, rm, float(tr["lo"]), float(tr["hi"]))
	if b == SetpieceLogic.NONE:
		return true
	var c := SetpieceLogic.cfg()
	items.append(_band(tr, b, "living", "living_core", float(c["tide_width_px"]), float(c["tide_glow"]), float(c["tide_halo_max_px"])))
	return false


# --- the garrison cleared ---------------------------------------------------------------------

## The stand-in for counter_garrison_cleared: back from a held fort's raid that banked loot and
## flipped nothing, the burst plays without a number.
# TODO(api-request #10): remove with SetpieceLogic.garrison_stand_in once the event is emitted.
func _check_standin() -> void:
	var g := SetpieceLogic.garrison_stand_in(_arrive_from, model.forts_by_id, _seen)
	if not g.is_empty():
		_add(SetpieceLogic.GARRISON, str(g["fort_id"]), -1)


func _garrison_tick(p: Dictionary, t: float, rm: bool, items: Array) -> bool:
	var id := str(p["fort_id"])
	var n := int(p["n"])
	var c := SetpieceLogic.cfg()
	var f := model.fort(id)
	var ctx := nodes.ctx
	if f.is_empty():
		if ctx.chip_fx.erase(id):
			nodes.redraw_chips()
		return true
	var g := SetpieceLogic.garrison(t, n, rm)
	var pos := MapModel.to_vec(f["pos"])
	var r := MapLogic.fort_radius(int(f["tier"]))
	if float(g["pulse"]) >= 0.0:
		if not p.has("track"):
			p["track"] = _track("war", MapModel.COVINGTON, id)
		var tr: Dictionary = p["track"]
		var b := SetpieceLogic.band_range(float(g["pulse"]), float(c["garrison_band_px"]), float(tr["lo"]), float(tr["hi"]))
		items.append(_band(tr, b, "undead", "undead_core", float(c["tide_width_px"]), float(c["tide_glow"]), float(c["tide_halo_max_px"])))
	var reach := float(c["garrison_burst_reach_px"])
	if float(g["burst"]) >= 0.0:
		var q := float(g["burst"])
		var rings := int(c["garrison_burst_rings"])
		for k in rings:
			items.append({"kind": "ring", "pos": pos, "r": r + reach * q * float(k + 1) / rings, "key": "undead",
				"alpha": pow(1.0 - q, 2.0), "width": float(c["garrison_burst_width_px"]), "cap": float(c["ripple_halo_max_px"])})
	elif bool(g["ring"]):  # reduced motion: the burst's still ring
		items.append({"kind": "ring", "pos": pos, "r": r + reach * 0.5, "key": "undead", "alpha": 1.0,
			"width": float(c["garrison_burst_width_px"]), "cap": float(c["ripple_halo_max_px"])})
	var chip: Dictionary = g["chip"]
	if chip != ctx.chip_fx.get(id, {}):
		if chip.is_empty():
			ctx.chip_fx.erase(id)
		else:
			ctx.chip_fx[id] = chip
		nodes.redraw_chips()
	if float(g["callout"]) > 0.0:
		items.append(_callout(id, SetpieceLogic.garrison_text(n), float(g["callout"])))
	if bool(g["done"]) and ctx.chip_fx.has(id):
		ctx.chip_fx.erase(id)
		nodes.redraw_chips()
	return bool(g["done"])


# --- victory ----------------------------------------------------------------------------------

func _victory_tick(t: float, rm: bool) -> bool:
	var ph := SetpieceLogic.victory_phase(t, rm)
	routes.set_victory(ph)
	if ph == SetpieceLogic.STOP:
		hud.show_victory()
		return true
	return false


# --- debug ------------------------------------------------------------------------------------

## --setpiece=<kind>: the set piece at the demo fort, through the same path a real event takes.
func _fire_debug() -> void:
	if not is_inside_tree() or model.forts.is_empty():
		return
	var c := SetpieceLogic.cfg()
	var id := SetpieceLogic.demo_target(model.forts, str(c["debug_target"]))
	print("SETPIECE debug ", _debug_kind, " at ", id)
	match _debug_kind:
		SetpieceLogic.VALVE:
			var v := SetpieceLogic.demo_valve(_committed)
			if bool(model.state.cmd_set_valve(v["work"], v["war"], v["flood"])["ok"]):
				_swing_to(ValveLogic.normalise(v))
		SetpieceLogic.FLIP:
			_add(SetpieceLogic.FLIP, id)
		SetpieceLogic.FIRST_FLIP:
			_add(SetpieceLogic.FIRST_FLIP, id)
		SetpieceLogic.TITHE:
			on_event({"type": "tithe_warning", "fort_id": id})
			on_event({"type": "tithe_wave", "fort_id": id})
		SetpieceLogic.GARRISON:
			on_event({"type": "counter_garrison_cleared", "fort_id": id, "killed_mass": float(c["debug_killed_mass"])})
		SetpieceLogic.VICTORY:
			on_event({"type": "vei_result", "won": true})
