class_name MapCamera
extends Camera2D
## The map camera: fit to the world, wheel zoom at the cursor, drag pan past a threshold, and
## click hit-testing in screen space (a node's target is at least click_min_radius_px wide).
## world_map forwards its _unhandled_input events to handle_input(): they arrive in viewport
## (screen) coordinates, after the HUD and the sidebar have had first refusal.

signal clicked(node_id: String)  # "" for empty ground
signal move_done  # a scripted dive or arrival move reached its end

var model: MapModel
var tier := "mid"
var user_moved := false  # the player has panned or zoomed since the fit

var _pressed := false
var _panning := false
var _press_pos := Vector2.ZERO
var _tween: Tween
var _move := {}  # the scripted dive (to a fixed view) or arrival (to the live fit): from_*, to_*, to_fit, dur, t
var _fit_zoom := 1.0
var _fit_pos := Vector2.ZERO


func _process(delta: float) -> void:
	if not _move.is_empty():
		_step_move(delta)
	tier = MapLogic.zoom_tier(zoom.x, tier)


## The default fit: frame the map's content below `inset_top` px of HUD, every fort's footprint
## and Vei clear of the `obstacles` (screen rects of the panels: MapLogic.fit_view_clear). Boot and
## F6 only; once the player has panned or zoomed (user_moved) the caller does not re-fit.
func fit(viewport_size: Vector2, inset_top := 0.0, obstacles: Array = []) -> void:
	var v := MapLogic.fit_view_clear(model.content_rect(), viewport_size, inset_top, model.fit_items(), obstacles)
	if v.is_empty():
		return
	_fit_zoom = v["zoom"]
	_fit_pos = v["centre"]
	if _move.is_empty() or not _move["to_fit"]:  # an arrival in progress eases to the new fit by itself
		zoom = Vector2(_fit_zoom, _fit_zoom)
		position = _fit_pos
	tier = MapLogic.zoom_tier(zoom.x, "mid")


## The router's dive: eases from the current view to `to_zoom` centred on `to_pos` over `seconds`,
## then emits move_done. Not a user move.
func begin_dive(to_zoom: float, to_pos: Vector2, seconds: float) -> void:
	_stop_tween()
	_move = {"from_zoom": zoom.x, "from_pos": position, "to_zoom": to_zoom, "to_pos": to_pos,
		"to_fit": false, "dur": seconds, "t": 0.0}


## The arrival from a scene: starts at the dive's end state on `node_pos` and eases out to the
## current default fit (it follows a re-fit) over `seconds`. Call after fit(). Not a user move;
## a pan or zoom by the player stops it.
func begin_arrive(node_pos: Vector2, seconds: float) -> void:
	_stop_tween()
	var s := TransitionLogic.arrive_start(_fit_zoom, node_pos, TransitionLogic.cfg(),
		float(MapLogic.cfg()["zoom_min"]), float(MapLogic.cfg()["zoom_max"]))
	zoom = Vector2(s["zoom"], s["zoom"])
	position = s["centre"]
	_move = {"from_zoom": s["zoom"], "from_pos": s["centre"], "to_zoom": _fit_zoom, "to_pos": _fit_pos,
		"to_fit": true, "dur": seconds, "t": 0.0}


func _step_move(delta: float) -> void:
	_move["t"] += delta
	var p := TransitionLogic.progress(_move["t"], _move["dur"])
	var e := TransitionLogic.ease_t(p, float(TransitionLogic.cfg()["ease_power"]))
	var to_zoom: float = _fit_zoom if _move["to_fit"] else _move["to_zoom"]
	var to_pos: Vector2 = _fit_pos if _move["to_fit"] else _move["to_pos"]
	var z := TransitionLogic.mix_zoom(_move["from_zoom"], to_zoom, e)
	zoom = Vector2(z, z)
	position = _move["from_pos"].lerp(to_pos, e)
	if p >= 1.0:
		_move = {}
		move_done.emit()


## Centres the camera on a world point: eased over centre_tween_s, or a jump under reduced motion.
func centre_on(world_pos: Vector2) -> void:
	user_moved = true
	_stop_tween()
	if Pulse.reduced_motion:
		position = world_pos
		return
	_tween = create_tween()
	_tween.tween_property(self, "position", world_pos, float(MapLogic.cfg()["controls"]["centre_tween_s"])) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _stop_tween() -> void:
	_move = {}
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null


func to_world(screen_pos: Vector2) -> Vector2:
	return (screen_pos - get_viewport_rect().size * 0.5) / zoom.x + position


func handle_input(e: InputEvent) -> void:
	var cfg := MapLogic.cfg()
	if e is InputEventMouseButton:
		var step: float = cfg["zoom_step"]
		if e.button_index == MOUSE_BUTTON_WHEEL_UP and e.pressed:
			zoom_at(step, e.position)
		elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN and e.pressed:
			zoom_at(1.0 / step, e.position)
		elif e.button_index == MOUSE_BUTTON_LEFT:
			if e.pressed:
				_pressed = true
				_panning = false
				_press_pos = e.position
			else:
				if _pressed and not _panning:
					clicked.emit(hit_test(e.position))
				_pressed = false
	elif e is InputEventMouseMotion and _pressed:
		if not (e.button_mask & MOUSE_BUTTON_MASK_LEFT):
			_pressed = false  # the release went to a panel: never pan on a stale press
			return
		if not _panning and (e.position - _press_pos).length() > float(cfg["drag_threshold_px"]):
			_panning = true
		if _panning:
			user_moved = true
			_stop_tween()
			position -= e.relative / zoom.x


func zoom_at(factor: float, screen_pos: Vector2) -> void:
	var cfg := MapLogic.cfg()
	user_moved = true
	_stop_tween()
	var before := to_world(screen_pos)
	var z := clampf(zoom.x * factor, float(cfg["zoom_min"]), float(cfg["zoom_max"]))
	zoom = Vector2(z, z)
	position += before - to_world(screen_pos)
	tier = MapLogic.zoom_tier(z, tier)


## The node id under a screen position, or "". The hit radius is the drawn radius x zoom, but
## never under click_min_radius_px; the nearest centre wins.
func hit_test(screen_pos: Vector2) -> String:
	var min_px: float = MapLogic.cfg()["click_min_radius_px"]
	var best := ""
	var best_d := INF
	for c in model.hit_targets():
		var centre: Vector2 = (c["pos"] - position) * zoom.x + get_viewport_rect().size * 0.5
		var d := screen_pos.distance_to(centre)
		if d < maxf(float(c["radius"]) * zoom.x, min_px) and d < best_d:
			best_d = d
			best = c["id"]
	return best
