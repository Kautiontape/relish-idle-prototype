class_name MapCamera
extends Camera2D
## The map camera: fit to the world, wheel zoom at the cursor, drag pan past a threshold, and
## click hit-testing in screen space (a node's target is at least click_min_radius_px wide).
## world_map forwards its _unhandled_input events to handle_input(): they arrive in viewport
## (screen) coordinates, after the HUD and the sidebar have had first refusal.

signal clicked(node_id: String)  # "" for empty ground

var model: MapModel
var tier := "mid"
var user_moved := false  # the player has panned or zoomed since the fit

var _pressed := false
var _panning := false
var _press_pos := Vector2.ZERO
var _tween: Tween


func _process(_delta: float) -> void:
	tier = MapLogic.zoom_tier(zoom.x, tier)


## The default fit: frame the map's content below `inset_top` px of HUD. Boot and F6 only; once
## the player has panned or zoomed (user_moved) the caller does not re-fit.
func fit(viewport_size: Vector2, inset_top := 0.0) -> void:
	var v := MapLogic.fit_view(model.content_rect(), viewport_size, inset_top)
	if v.is_empty():
		return
	zoom = Vector2(v["zoom"], v["zoom"])
	position = v["centre"]
	tier = MapLogic.zoom_tier(zoom.x, "mid")


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
