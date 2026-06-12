class_name CommandController
extends Node
## Default thumb state (§8.1): lasso to select, tap to send (or move Relish),
## stroke-from-Relish drags her path. Coarse commands only — group-and-point,
## no unit micro, ever. One grammar: encircle to claim.

var battlefield: Battlefield
var interactables: Array = []  # sarcophagi — taps check these first
var selection: Array = []
var _sel_t := 0.0
var _stroke := PackedVector2Array()
var _touch_index := -1
var _on_relish := false
var _last_relish_pt := Vector2.ZERO
var _line: Line2D = null

func _process(delta: float) -> void:
	if selection.size() > 0:
		_sel_t -= delta
		if _sel_t <= 0.0:
			clear_selection()  # selection expires 2s after lasso if unused

func handle_input(ev: InputEvent) -> bool:
	if ev is InputEventScreenTouch:
		if ev.pressed and _touch_index == -1:
			_touch_index = ev.index
			var w := battlefield.screen_to_world(ev.position)
			_stroke = PackedVector2Array([w])
			_on_relish = battlefield.relish != null and battlefield.relish.alive \
				and w.distance_to(battlefield.relish.global_position) < battlefield.relish.radius() + 22.0
			if _on_relish:
				battlefield.relish.path_override.clear()
				battlefield.relish.cmd = RRUnit.Cmd.NONE
				_last_relish_pt = w
			_make_line()
			return true
		elif not ev.pressed and ev.index == _touch_index:
			_finish_stroke()
			_touch_index = -1
			return true
	elif ev is InputEventScreenDrag and ev.index == _touch_index:
		var w := battlefield.screen_to_world(ev.position)
		if _stroke.size() == 0 or w.distance_to(_stroke[_stroke.size() - 1]) > 5.0:
			_stroke.append(w)
			if _line != null:
				_line.points = _stroke
		if _on_relish and w.distance_to(_last_relish_pt) > 14.0:
			battlefield.relish.path_override.append(w)  # she follows as you draw
			_last_relish_pt = w
		return true
	return false

func _finish_stroke() -> void:
	_kill_line()
	if _stroke.size() == 0:
		return
	var length := 0.0
	for i in range(1, _stroke.size()):
		length += _stroke[i].distance_to(_stroke[i - 1])
	var endpoint := _stroke[_stroke.size() - 1]

	if _on_relish:
		if length > float(ConfigDb.v("circle", "tap_max_length_px")):
			GameState.add_command_touch()  # drag-her-path command
		_on_relish = false
		_stroke = PackedVector2Array()
		return

	if length <= float(ConfigDb.v("circle", "tap_max_length_px")):
		_handle_tap(endpoint)
	else:
		var gap := _stroke[0].distance_to(endpoint)
		if gap < maxf(60.0, length * 0.22):
			_handle_lasso()
	_stroke = PackedVector2Array()

func _handle_tap(point: Vector2) -> void:
	for s in interactables:
		if is_instance_valid(s) and not s.is_open and s.contains_point(point):
			s.try_open(battlefield)
			return  # opening a sarcophagus is not a command touch
	if selection.size() > 0:
		var live: Array = []
		for u in selection:
			if is_instance_valid(u) and u.alive:
				live.append(u)
		for i in live.size():
			live[i].order_move(point + _formation_offset(i, live.size()))
		clear_selection()
		GameState.add_command_touch()
	elif battlefield.relish != null and battlefield.relish.alive:
		battlefield.relish.order_move(point)
		GameState.add_command_touch()

func _handle_lasso() -> void:
	var picked: Array = []
	for u in battlefield.living(RRUnit.Faction.PLAYER):
		if u.kind == RRUnit.Kind.RELISH:
			continue
		if Geometry2D.is_point_in_polygon(u.global_position, _stroke):
			picked.append(u)
	if picked.is_empty():
		return
	clear_selection()
	selection = picked
	for u in selection:
		u.selected = true
	_sel_t = float(ConfigDb.v("timers", "selection_expiry_s"))
	GameState.add_command_touch()

func _formation_offset(i: int, n: int) -> Vector2:
	if n <= 1 or i == 0:
		return Vector2.ZERO
	var ring := 1 + (i - 1) / 6
	var slot := (i - 1) % 6
	return Vector2(34.0 * ring, 0).rotated(TAU * slot / 6.0 + ring * 0.5)

func clear_selection() -> void:
	for u in selection:
		if is_instance_valid(u):
			u.selected = false
	selection = []

func _make_line() -> void:
	_kill_line()
	_line = Line2D.new()
	_line.width = 3.0
	_line.default_color = Color(1.0, 0.9, 0.3, 0.8)  # command color ≠ trance color
	_line.z_index = 70
	battlefield.fx_root.add_child(_line)

func _kill_line() -> void:
	if _line != null and is_instance_valid(_line):
		_line.queue_free()
	_line = null
