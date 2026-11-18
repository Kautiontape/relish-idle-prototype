extends Control
## The Realm view: the scene root. Builds the world (ground, routes, nodes, the set pieces' layer,
## camera) and the UI layer (HUD, sidebar), owns the shared MapModel and the set pieces
## (MapSetpieces), and exits only via finished(result).
## Reads views through the model and sends commands through GameState; nothing else.
## Debug flags (harness sessions only, i.e. any --fixture): --valve=w,war,f  --select=<id>
## --teleport=<id>  --map-clicks=...  --lanes=demo  --nodes=demo  --away=demo  --lanes-report
## --hover=x,y (rest the cursor at screen px x,y so a tooltip opens; give --frames enough to cover the tooltip delay).
## --skip-time=S (once at boot: cmd_debug_skip_time(S) seconds of sim, e.g. past a tithe wave).

signal finished(result: Dictionary)

static var _skipped := false  # --skip-time fires once per run, not per map entry

var world: Node2D
var cam: MapCamera
var nodes_view: MapNodes
var routes_view: MapRoutes
var callouts_view: MapCallouts
var model: MapModel
var hud: MapHud
var valve: MapValve
var chip: MapRelishChip
var sidebar: MapSidebar
var away: MapAway
var setpieces: MapSetpieces
var setpiece_layer: MapSetpieceLayer
var opening: MapOpening
var tithe_explain: MapTitheExplain
var seen: MapSeen

var selected_id := ""
var _hover := ""
var _hover_key: Array = []
var _ui_acc := 0.0
var _setup_called := false
var _arrive_toast := ""  # a one-off line from the router (a refused teleport's reason), shown once on arrival
var _arrive_from := ""  # the node whose scene the player just left: the camera eases out from it
var _ui_layer: CanvasLayer


func setup(args: Dictionary) -> void:
	_setup_called = true
	_arrive_from = str(args.get("arrive_from", ""))
	_arrive_toast = str(args.get("toast", ""))


func demo_seed() -> Dictionary:
	return {}


func _ready() -> void:
	# The root Control sits under the Camera2D's canvas transform (world space), so it takes no
	# input; the map's input comes through _unhandled_input in screen space.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	MapLogic.configure(ConfigDb.data.get("map_view", {}))
	model = MapModel.new(Game.state)
	model.demo = Game.state.debug_enabled and OS.get_cmdline_user_args().has("--lanes=demo")
	model.nodes_demo = Game.state.debug_enabled and OS.get_cmdline_user_args().has("--nodes=demo")
	model.flip_cfg = ConfigDb.data.get("realm", {}).get("flip", {})
	model.realm_cfg = ConfigDb.data.get("realm", {})
	model.slab_cfg = ConfigDb.data.get("town", {}).get("slab", {})
	model.idle_cap = float(ConfigDb.data.get("economy", {}).get("worker", {}).get("idle_cap", 0.0))
	_apply_valve_arg()
	_apply_skip_arg()
	model.refresh(true)
	_build_world()
	_build_ui()
	await get_tree().process_frame  # the router's setup(args) has run by now
	if not is_inside_tree():
		return
	var return_layer := _router_layer()  # the router holds it opaque over this frame and the next
	if return_layer != null:
		_set_hud_alpha(0.0)
	hud.start()
	_hold_hud_for_return(return_layer)
	opening.refresh()
	_fit()
	var returned := setpieces.note_return(_arrive_from)  # "taken by you" or "stays Vei's", before the set pieces go live
	var ease_s := _begin_arrival()
	if ease_s > 0.0:  # the set pieces play once the camera has eased out to the map
		get_tree().create_timer(ease_s).timeout.connect(setpieces.go_live)
	else:
		setpieces.go_live()
	if returned == SetpieceLogic.TAKEN:
		_show_taken(_arrive_from, ease_s)
	if _arrive_toast != "":
		hud.show_toast(_arrive_toast)
	hud.inset_changed.connect(func(_inset: float) -> void: _refit())  # the bar's sizes settle a frame later
	setpieces.note_mount(away.open_if_shown())  # builds finished while away from the map get their callout, unless the away report lists them
	tithe_explain.open_pending()  # after the away panel: a warning pending at mount waits for it to close
	_replay_clicks()
	_hover_arg()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--select="):
			_select(arg.trim_prefix("--select="))
		elif arg.begins_with("--teleport=") and not Shot.consumed_teleport:
			Shot.consumed_teleport = true
			var dest := arg.trim_prefix("--teleport=")
			Game.state.cmd_debug_set_state({"relish_at": dest})
			await get_tree().create_timer(0.3).timeout
			if is_inside_tree():
				_dive(dest)


func _build_world() -> void:
	world = Node2D.new()
	world.name = "World"
	add_child(world)
	var field := Sprite2D.new()
	field.set_script(load("res://scripts/map/map_field_view.gd"))
	world.add_child(field)
	routes_view = MapRoutes.new()
	routes_view.model = model
	routes_view.lanes_report = Game.state.debug_enabled and OS.get_cmdline_user_args().has("--lanes-report")
	world.add_child(routes_view)
	nodes_view = MapNodes.new()
	nodes_view.model = model
	nodes_view.routes = routes_view
	var route_hint := MapRouteHint.new()  # Relish's route preview, under the nodes, on their context
	route_hint.name = "RouteHint"
	route_hint.ctx = nodes_view.ctx
	world.add_child(route_hint)
	nodes_view.timed_layers.append(route_hint)  # its drawing counts in NODES_MS
	world.add_child(nodes_view)
	cam = MapCamera.new()
	cam.name = "Camera2D"
	cam.model = model
	callouts_view = MapCallouts.new()
	callouts_view.name = "Callouts"
	callouts_view.model = model
	callouts_view.nodes = nodes_view
	callouts_view.cam = cam  # the card (the sidebar) is set in _build_ui
	world.add_child(callouts_view)
	setpiece_layer = MapSetpieceLayer.new()  # the set pieces' bands, rings and callouts, over the nodes and lane callouts
	setpiece_layer.name = "Setpieces"
	setpiece_layer.ctx = nodes_view.ctx
	setpiece_layer.pulse = true
	world.add_child(setpiece_layer)
	nodes_view.timed_layers.append(setpiece_layer)  # its drawing counts in NODES_MS
	cam.clicked.connect(_on_clicked)
	world.add_child(cam)
	cam.make_current()


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	_ui_layer = layer
	add_child(layer)
	hud = MapHud.new()
	hud.model = model
	layer.add_child(hud)
	valve = MapValve.new()
	valve.model = model
	valve.toast.connect(hud.show_toast)
	layer.add_child(valve)
	seen = MapSeen.new(MapSeen.PATH, Game.autosave_enabled)  # outside the save; a harness session reads it empty and never writes it
	seen.reconcile(str(model.hud.get("game_id", "")))  # the flags belong to one game
	var legend := MapLegend.new()  # the fort rings' key, just above the valve
	legend.seen = seen  # it keeps the player's close there
	legend.model = model
	legend.valve = valve
	layer.add_child(legend)
	chip = MapRelishChip.new()
	legend.chip = chip
	chip.model = model
	chip.hud = hud
	hud.chip = chip
	chip.cam = cam
	chip.toast.connect(hud.show_toast)
	layer.add_child(chip)
	sidebar = MapSidebar.new()
	sidebar.model = model
	sidebar.hud = hud
	sidebar.dive.connect(_dive)
	sidebar.toast.connect(hud.show_toast)
	layer.add_child(sidebar)
	callouts_view.card = sidebar  # the callouts keep off the open card
	nodes_view.card = sidebar  # the node labels shift clear of it, or hide
	hud.next_chosen.connect(_act_on)
	hud.valve = valve  # the bar's tooltips keep off the valve, the legend and the open card
	hud.legend = legend
	hud.card = sidebar
	hud.nodes = nodes_view  # and Vei's readout and the other map labels
	hud.cam = cam
	opening = MapOpening.new()
	opening.model = model
	opening.hud = hud
	opening.valve = valve
	opening.nodes = nodes_view
	opening.seen = seen
	layer.add_child(opening)
	tithe_explain = MapTitheExplain.new()
	tithe_explain.model = model
	tithe_explain.cam = cam
	tithe_explain.hud = hud
	tithe_explain.seen = seen
	tithe_explain.card = sidebar  # the plate keeps off the open card
	tithe_explain.toast.connect(hud.show_toast)
	layer.add_child(tithe_explain)
	away = MapAway.new()  # last: it opens over everything
	away.model = model
	away.demo = Game.state.debug_enabled and OS.get_cmdline_user_args().has("--away=demo")
	away.acted.connect(_act_on)
	layer.add_child(away)
	Game.game_event.connect(away.on_event)
	tithe_explain.away = away  # the explanation waits while the away panel is open, and opens when it closes
	away.closed.connect(tithe_explain.on_away_closed)
	Game.game_event.connect(tithe_explain.on_event)  # after the away panel's, so it sees the panel already open
	var tip_theme := MapUi.tooltip_theme()  # every map tooltip on its own opaque plate
	for c in layer.get_children():
		if c is Control:
			(c as Control).theme = tip_theme
	Game.game_event.connect(_on_game_event)
	setpieces = MapSetpieces.new()
	setpieces.name = "Setpieces"
	setpieces.model = model
	setpieces.nodes = nodes_view
	setpieces.routes = routes_view
	setpieces.hud = hud
	setpieces.cam = cam
	setpieces.callouts = callouts_view
	setpieces.valve = valve
	setpieces.layer = setpiece_layer
	setpieces.seen = seen
	add_child(setpieces)


## relish_returned: Vei retook the fort Relish stood at and she walks home (one toast line).
func _on_game_event(ev: Dictionary) -> void:
	var msg := RelishLogic.returned_toast(ev, model.names)
	if msg != "":
		hud.show_toast(msg)


## Pan, wheel zoom and click-select, in screen (viewport) coordinates. The HUD and the sidebar
## live in a CanvasLayer and take their own clicks first through the GUI, so anything that
## reaches here is on the bare map.
func _unhandled_input(e: InputEvent) -> void:
	cam.handle_input(e)


## F6 reloads the configs (ground handles the key): re-frame the map, unless the player moved it.
func _input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo and e.keycode == KEY_F6:
		_refit.call_deferred()


func _refit() -> void:
	MapLogic.configure(ConfigDb.data.get("map_view", {}))  # the deferred re-fit runs before MapNodes re-reads F6's tuning
	if cam != null and not cam.user_moved:
		_fit()


## The default fit: below the top bar, every fort and Vei clear of the valve panel, the objective
## strip, the leave line's room and Relish's chip.
func _fit() -> void:
	cam.fit(get_viewport_rect().size, hud.bar_bottom(), [valve.get_global_rect(), hud.strip_rect(), hud.leave_rect(), chip.get_global_rect()])


## The return from a town, dungeon or boss: the camera starts zoomed on `_arrive_from` and eases
## out to the fit. Under reduced motion the router's crossfade is all there is. Returns the ease's
## seconds (0: none).
func _begin_arrival() -> float:
	if _arrive_from == "" or Pulse.reduced_motion or not model.has_node(_arrive_from):
		return 0.0
	var tl := TransitionLogic.timeline(TransitionLogic.cfg(), TransitionLogic.OUT, false, MapTransition.slow())
	cam.begin_arrive(model.node_pos(_arrive_from), tl["zoom_s"])
	return float(tl["zoom_s"])


## A fort the raid just took: once the camera has eased out (`wait_s`), its card opens and the camera
## comes to it, so the HELD chip with Vei's grace countdown (draining) and the "taken by you" line are
## on screen together. Skipped if the player has already moved the camera.
func _show_taken(id: String, wait_s: float) -> void:
	if wait_s > 0.0:
		await get_tree().create_timer(wait_s).timeout
	if is_inside_tree() and not cam.user_moved:
		_act_on({"kind": "fort", "id": id})


## The router's dive (router contract: dive_to(node_id, duration_s) -> Signal): the camera zooms
## into the node and the whole HUD (top bar, strip, chip, sidebar, valve, callouts, toasts, away
## panel, tithe card) fades out over hud_fade_s inside that time, so the router's snapshot (taken
## once the signal fires) has none of it. The signal fires when the zoom ends.
func dive_to(node_id: String, duration_s: float) -> Signal:
	var t := {}
	if model.forts_by_id.has(node_id):  # a fort: its ring ends centred and large, for the dungeon's first room to pick up
		t = TransitionLogic.dive_fort_target(int(model.fort(node_id)["tier"]), model.node_pos(node_id), get_viewport_rect().size,
			cam.zoom.x, TransitionLogic.cfg(), float(MapLogic.cfg()["zoom_min"]))
	else:
		t = TransitionLogic.dive_target(cam.zoom.x, model.node_pos(node_id), TransitionLogic.cfg(),
			float(MapLogic.cfg()["zoom_min"]), float(MapLogic.cfg()["zoom_max"]))
	cam.begin_dive(t["zoom"], t["centre"], duration_s)
	_fade_hud(TransitionLogic.IN, TransitionLogic.hud_fade_len(TransitionLogic.cfg(), MapTransition.slow(), duration_s))
	return cam.move_done


## Hides the whole HUD at once: the router calls it when it skips the dive (reduced motion), so
## its snapshot has none of it.
func hide_hud() -> void:
	_set_hud_alpha(0.0)


## The router's Transition layer if one is up over this scene (a return from a town, dungeon or
## boss); null otherwise. It frees itself when its snapshot has faded out.
func _router_layer() -> MapTransition:
	if _arrive_from == "" or get_parent() == null:
		return null
	var tr := get_parent().get_node_or_null("Transition")
	return tr as MapTransition if tr is MapTransition and not tr.is_queued_for_deletion() else null


## The return: the HUD stays out until the router's snapshot fade is over (its layer leaves the
## tree), then fades in over hud_fade_s (at once under reduced motion).
func _hold_hud_for_return(layer: MapTransition) -> void:
	if layer == null:
		return
	if is_instance_valid(layer) and layer.is_inside_tree():
		await layer.tree_exited
	if is_inside_tree():
		_fade_hud(TransitionLogic.OUT, float(TransitionLogic.cfg()["hud_fade_s"]) * MapTransition.slow())


## Drives the HUD's alpha along TransitionLogic.hud_alpha over `seconds` (kind IN: out, OUT: in).
func _fade_hud(kind: String, seconds: float) -> void:
	var c := TransitionLogic.cfg()
	var reduced: bool = Pulse.reduced_motion
	var slow := MapTransition.slow()
	if reduced or seconds <= 0.0:
		_set_hud_alpha(0.0 if kind == TransitionLogic.IN else 1.0)  # a zero-length fade is its end state
		return
	create_tween().tween_method(func(t: float) -> void: _set_hud_alpha(TransitionLogic.hud_alpha(c, kind, false, slow, t)), 0.0, seconds, seconds)


## The HUD's alpha: every UI layer child and the callouts.
func _set_hud_alpha(a: float) -> void:
	for c in _ui_layer.get_children():
		if c is CanvasItem:
			c.modulate.a = a
	callouts_view.modulate.a = a


## Covington is a door: one click enters the town, with no card. Everything else selects.
func _on_clicked(id: String) -> void:
	if id == MapModel.COVINGTON:
		_dive(id)
	else:
		_select(id)


## A clicked line (the objective strip, an away-report line) does its AwayLogic action: a fort
## opens its card and comes to the middle, a dive enters Covington, Vei is selected.
func _act_on(a: Dictionary) -> void:
	match str(a.get("kind", "none")):
		"fort":
			_select(str(a["id"]))
			cam.centre_on(model.node_pos(str(a["id"])))
		"dive":
			_dive(str(a["to"]))
		"vei":
			_select(MapModel.VEI)
		"opening":
			opening.flash()


## Leaves the map for `node_id`'s scene (the router: a fort id begins its dungeon, "vei" the boss
## fight, "covington" opens the town). The map never moves Relish through this.
func _dive(node_id: String) -> void:
	SetpieceLogic.note_dive(node_id, bool(model.fort(node_id).get("held", false)))  # so a held fort raided again is not "taken" on return
	finished.emit({"v": 2, "teleport_to": node_id})


## Debug only: `--valve=w,war,f` sets the valve at boot through cmd_set_valve.
func _apply_valve_arg() -> void:
	if not Game.state.debug_enabled:
		return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--valve="):
			var p := arg.trim_prefix("--valve=").split(",")
			if p.size() == 3:
				Game.state.cmd_set_valve(float(p[0]), float(p[1]), float(p[2]))


## Debug only: `--skip-time=S` advances the sim S seconds once, at the first map entry.
func _apply_skip_arg() -> void:
	if not Game.state.debug_enabled or _skipped:
		return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--skip-time="):
			_skipped = true
			print("SKIP_TIME ", Game.state.cmd_debug_skip_time(float(arg.trim_prefix("--skip-time="))))


## Debug only: `--map-clicks=` replays a script in screen px once the camera fit has settled,
## through the real input path (Shot's own --clicks fire before the fit): `x,y` a click,
## `x,y>x,y` a drag (`x,y>>x,y` keeps the button down at its end), `wN` waits N frames; steps are separated by `;`.
func _replay_clicks() -> void:
	if not Game.state.debug_enabled:
		return
	var steps: Array = []
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--map-clicks="):
			steps.append_array(MapLogic.parse_steps(arg.trim_prefix("--map-clicks=")))
	if steps.is_empty():
		return
	var gap := int(MapLogic.cfg()["map_clicks_gap_frames"])
	await _frames(int(MapLogic.cfg()["map_clicks_wait_frames"]))
	for st in steps:
		match st["kind"]:
			"wait":
				await _frames(int(st["frames"]))
			"click":
				_inject_click(st["pos"], true)
				await _frames(1)
				_inject_click(st["pos"], false)
				await _frames(gap)
			"drag":
				var from: Vector2 = st["from"]
				var to: Vector2 = st["to"]
				var n := int(MapLogic.cfg()["map_drag_steps"])
				_inject_click(from, true)
				await _frames(1)
				var prev := from
				for i in range(1, n + 1):
					var p := from.lerp(to, float(i) / n)
					_inject_motion(p, p - prev)
					prev = p
					await _frames(1)
				if not bool(st.get("hold", false)):
					_inject_click(to, false)
				await _frames(gap)


## Debug only: `--hover=x,y` rests the real cursor at screen px x,y (so a control's tooltip opens):
## warps the mouse there after map_hover_wait_frames, then sends a plain motion event so the GUI sees it.
func _hover_arg() -> void:
	if not Game.state.debug_enabled:
		return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--hover="):
			var p := arg.trim_prefix("--hover=").split(",")
			if p.size() != 2:
				return
			var pos := Vector2(float(p[0]), float(p[1]))
			await _frames(int(MapLogic.cfg()["map_hover_wait_frames"]))
			if not is_inside_tree():
				return
			Input.warp_mouse(pos)
			var e := InputEventMouseMotion.new()
			e.position = pos
			e.global_position = pos
			Input.parse_input_event(e)
			return


func _frames(n: int) -> void:
	for i in n:
		if not is_inside_tree():
			return
		await get_tree().process_frame


func _inject_click(pos: Vector2, pressed: bool) -> void:
	if not is_inside_tree():
		return
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = pressed
	e.position = pos
	e.global_position = pos
	e.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	Input.parse_input_event(e)


func _inject_motion(pos: Vector2, rel: Vector2) -> void:
	if not is_inside_tree():
		return
	var e := InputEventMouseMotion.new()
	e.position = pos
	e.global_position = pos
	e.relative = rel
	e.button_mask = MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(e)


func _select(id: String) -> void:
	if id == MapModel.COVINGTON:
		id = ""  # Covington has no card: it is a door
	selected_id = id
	nodes_view.selected_id = id
	routes_view.selected_id = id
	sidebar.select(id)


## The pointer over Covington is a pointing hand with a hint in the HUD, so the door is findable.
func _update_hover() -> void:
	# Hit-test only when the mouse or the camera moved: the targets are rebuilt per call.
	var mouse := get_viewport().get_mouse_position()
	var key := [mouse, cam.position, cam.zoom.x]
	if key == _hover_key:
		return
	_hover_key = key
	var over_gui := get_viewport().gui_get_hovered_control() != null
	var id := "" if over_gui else cam.hit_test(mouse)
	if id == _hover:
		return
	_hover = id
	var door := id == MapModel.COVINGTON
	Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND if door else Input.CURSOR_ARROW)
	hud.set_hover_hint(str(MapLogic.cfg()["controls"]["hover_hint_covington"]) if door else "")


func _exit_tree() -> void:
	if tithe_explain != null and Game.game_event.is_connected(tithe_explain.on_event):
		Game.game_event.disconnect(tithe_explain.on_event)
	if away != null and Game.game_event.is_connected(away.on_event):
		Game.game_event.disconnect(away.on_event)
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)


func _process(delta: float) -> void:
	model.refresh()
	hud.tick(delta)
	chip.refresh()  # every frame: it is a no-op until the model has a new rev
	_update_hover()
	_ui_acc += delta
	if _ui_acc < float(MapLogic.cfg()["ui_refresh_s"]):
		return
	_ui_acc = 0.0
	hud.refresh()
	valve.refresh()
	sidebar.refresh()
	opening.refresh()
	tithe_explain.refresh()
