class_name CommandController
extends Node
## Default thumb state (§8.1): lasso to select, tap to send (or move Relish),
## stroke-from-Relish drags her path. Coarse commands only — group-and-point /
## group-and-path, no per-unit micro, ever. One grammar: encircle to claim.
##
## Playtest extensions (user-directed):
## - Close the lasso and KEEP DRAGGING — the loop selects mid-stroke and the
##   rest of the stroke becomes a path the group follows live.
## - With an active selection, a new drag draws their path; a tap still sends.
## - Esc clears the selection (desktop affordance).

enum Mode { CLASSIFY, PATH, RELISH }

var battlefield: Battlefield
var interactables: Array = []  # sarcophagi — taps check these first
var selection: Array = []
var _sel_t := 0.0
var _stroke := PackedVector2Array()
var _touch_index := -1
var _mode: int = Mode.CLASSIFY
var _path_streamed := 0        # waypoints sent to the selection this stroke
var _path_from_lasso := false  # PATH began with a mid-stroke lasso (vs pre-selection)
var _path_begun := false       # streaming starts once the drag leaves the loop
var _closure_pt := Vector2.ZERO
var _last_path_pt := Vector2.ZERO
var _line: Line2D = null

func _process(delta: float) -> void:
	# Selection expires if unused — but never mid-stroke.
	if selection.size() > 0 and _touch_index == -1:
		_sel_t -= delta
		if _sel_t <= 0.0:
			clear_selection()

func handle_input(ev: InputEvent) -> bool:
	if ev is InputEventKey and ev.keycode == KEY_ESCAPE and ev.pressed and not ev.echo:
		clear_selection()
		_abort_stroke()
		return true
	if ev is InputEventScreenTouch:
		if ev.pressed and _touch_index == -1:
			_touch_index = ev.index
			_press(battlefield.screen_to_world(ev.position))
			return true
		elif not ev.pressed and ev.index == _touch_index:
			_touch_index = -1
			_release()
			return true
	elif ev is InputEventScreenDrag and ev.index == _touch_index:
		_move(battlefield.screen_to_world(ev.position))
		return true
	return false

# ---- Stroke lifecycle (world coords — testable without screen transforms) ----

func _press(w: Vector2) -> void:
	_stroke = PackedVector2Array([w])
	_path_streamed = 0
	_path_from_lasso = false
	_path_begun = false
	_make_line()
	if battlefield.relish != null and battlefield.relish.alive \
			and w.distance_to(battlefield.relish.global_position) < battlefield.relish.radius() + 34.0:
		_mode = Mode.RELISH
		battlefield.relish.path_override.clear()
		battlefield.relish.cmd = RRUnit.Cmd.NONE
		_last_path_pt = w
	elif _live_selection().size() > 0:
		_mode = Mode.PATH  # active selection: this stroke is their path
		_path_begun = true
		_begin_path(w)
	else:
		_mode = Mode.CLASSIFY

func _move(w: Vector2) -> void:
	if _stroke.size() > 0 and w.distance_to(_stroke[_stroke.size() - 1]) <= 5.0:
		return
	_stroke.append(w)
	if _line != null:
		_line.points = _stroke
	match _mode:
		Mode.RELISH:
			if w.distance_to(_last_path_pt) > 14.0:
				battlefield.relish.path_override.append(w)  # she follows as you draw
				_last_path_pt = w
		Mode.PATH:
			if not _path_begun:
				# They only break formation once the drag pulls AWAY from the loop.
				if w.distance_to(_closure_pt) >= float(ConfigDb.v("circle", "path_start_px")):
					_path_begun = true
					_begin_path(w)
			elif w.distance_to(_last_path_pt) > 14.0:
				for u in _live_selection():
					u.append_path_point(w)  # they follow as you draw
				_path_streamed += 1
				_last_path_pt = w
		Mode.CLASSIFY:
			_try_mid_stroke_lasso(w)

func _release() -> void:
	_kill_line()
	if _stroke.size() == 0:
		return
	var length := _stroke_length()
	var endpoint := _stroke[_stroke.size() - 1]
	var tap_max := float(ConfigDb.v("circle", "tap_max_length_px"))
	match _mode:
		Mode.RELISH:
			if length > tap_max:
				GameState.add_command_touch()  # drag-her-path command
			else:
				clear_selection()  # tapping the conduit resets the grammar
		Mode.PATH:
			if _path_streamed == 0:
				# Loop closed (or selection grabbed) but no path drawn.
				for u in _live_selection():
					u.cancel_empty_path()
				if _path_from_lasso:
					_sel_t = float(ConfigDb.v("timers", "selection_expiry_s"))  # plain lasso: selection stands
				elif length <= tap_max:
					_send_selection_to(endpoint)  # pre-selection tap = send (§8.1)
			else:
				for u in _live_selection():
					u.finish_path()
				if not _path_from_lasso:
					GameState.add_command_touch()  # lasso-paths already counted at the lasso
				clear_selection()
		Mode.CLASSIFY:
			if length <= tap_max:
				_handle_tap(endpoint)
			else:
				var gap := _stroke[0].distance_to(endpoint)
				if gap < maxf(60.0, length * 0.22):
					_handle_lasso()
				elif battlefield.relish != null and battlefield.relish.alive:
					_send_relish_along(_stroke)  # open swipe: the stroke is HER path
	_stroke = PackedVector2Array()
	_mode = Mode.CLASSIFY

func _abort_stroke() -> void:
	_kill_line()
	if _mode == Mode.PATH:
		for u in _live_selection():
			u.cancel_path()
	_stroke = PackedVector2Array()
	_mode = Mode.CLASSIFY
	_touch_index = -1

# ---- The neat part: the lasso that becomes a path, one unbroken stroke ----
## A loop counts as sealed wherever the stroke crosses ITSELF — no need to
## return to the starting point (playtest feedback).

func _try_mid_stroke_lasso(w: Vector2) -> void:
	var n := _stroke.size()
	if n < 8:
		return
	var loop := PackedVector2Array()
	if w.distance_to(_stroke[0]) <= 45.0:
		loop = _stroke  # came back to the start — classic closure
	else:
		var a1 := _stroke[n - 2]
		var a2 := _stroke[n - 1]
		for i in range(0, n - 4):  # newest segment vs every earlier segment
			var hit: Variant = Geometry2D.segment_intersects_segment(a1, a2, _stroke[i], _stroke[i + 1])
			if hit != null:
				loop = PackedVector2Array([hit])
				for j in range(i + 1, n):
					loop.append(_stroke[j])
				break
	if loop.size() < 3 or _polyline_length(loop) < float(ConfigDb.v("circle", "lasso_min_loop_px")):
		return
	var picked := _units_in_polygon(loop)
	if picked.is_empty():
		return
	_set_selection(picked)
	GameState.add_command_touch()
	_mode = Mode.PATH
	_path_from_lasso = true
	_path_begun = false  # path starts once the drag leaves the loop (path_start_px)
	_closure_pt = w
	if _line != null:
		_line.default_color = Color(0.5, 1.0, 0.6, 0.85)  # visible mode flip: lasso → path

func _begin_path(from: Vector2) -> void:
	_last_path_pt = from
	var live := _live_selection()
	for i in live.size():
		live[i].order_path(_formation_offset(i, live.size()))

# ---- Tap / lasso (release-time grammar, unchanged) ----

func _handle_tap(point: Vector2) -> void:
	for s in interactables:
		if is_instance_valid(s) and not s.is_open and s.contains_point(point):
			s.try_open(battlefield)
			return  # opening a sarcophagus is not a command touch
	if _live_selection().size() > 0:
		battlefield.spawn_ping(point, Color(1.0, 0.9, 0.3))  # group confirm
		_send_selection_to(point)
	elif battlefield.relish != null and battlefield.relish.alive:
		battlefield.spawn_ping(point, Color(0.78, 0.6, 0.95))  # her confirm
		battlefield.relish.order_move(point)
		GameState.add_command_touch()

## Open-swipe fallback (playtest): a stroke that is neither tap nor lasso and
## didn't start on Relish still belongs to her — she walks the drawn line.
func _send_relish_along(pts: PackedVector2Array) -> void:
	var rel: RRUnit = battlefield.relish
	rel.cmd = RRUnit.Cmd.NONE
	rel.path_override.clear()
	var last := Vector2.INF
	for p in pts:
		if last == Vector2.INF or p.distance_to(last) > 14.0:
			rel.path_override.append(p)
			last = p
	battlefield.spawn_ping(pts[0], Color(0.78, 0.6, 0.95))  # her confirm, at the pickup point
	GameState.add_command_touch()

func _send_selection_to(point: Vector2) -> void:
	var live := _live_selection()
	for i in live.size():
		live[i].order_move(point + _formation_offset(i, live.size()))
	clear_selection()
	GameState.add_command_touch()

func _handle_lasso() -> void:
	var picked := _units_in_polygon(_stroke)
	if picked.is_empty():
		return
	_set_selection(picked)
	_sel_t = float(ConfigDb.v("timers", "selection_expiry_s"))
	GameState.add_command_touch()

# ---- Selection plumbing ----

func _units_in_polygon(poly: PackedVector2Array) -> Array:
	var picked: Array = []
	for u in battlefield.living(RRUnit.Faction.PLAYER):
		if u.kind == RRUnit.Kind.RELISH:
			continue
		if Geometry2D.is_point_in_polygon(u.global_position, poly):
			picked.append(u)
	return picked

func _set_selection(picked: Array) -> void:
	clear_selection()
	selection = picked
	for u in selection:
		u.selected = true
	_sel_t = float(ConfigDb.v("timers", "selection_expiry_s"))

func _live_selection() -> Array:
	var live: Array = []
	for u in selection:
		if is_instance_valid(u) and u.alive:
			live.append(u)
	return live

func clear_selection() -> void:
	for u in selection:
		if is_instance_valid(u):
			u.selected = false
	selection = []

func _formation_offset(i: int, n: int) -> Vector2:
	if n <= 1 or i == 0:
		return Vector2.ZERO
	var ring := 1 + (i - 1) / 6
	var slot := (i - 1) % 6
	return Vector2(34.0 * ring, 0).rotated(TAU * slot / 6.0 + ring * 0.5)

func _stroke_length() -> float:
	return _polyline_length(_stroke)

func _polyline_length(pts: PackedVector2Array) -> float:
	var length := 0.0
	for i in range(1, pts.size()):
		length += pts[i].distance_to(pts[i - 1])
	return length

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
