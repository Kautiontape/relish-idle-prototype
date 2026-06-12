class_name TranceController
extends Node
## The Trance (§8.2): hold the corner button → world time dilates ×0.35,
## essence ignites, the other thumb traces a circle. Least-squares score sets
## the chaff multiplier. Completing a summon ends the trance and starts the
## cooldown. A focus meter caps any single hold (no trance camping).
## Desktop mapping (MADE UP): hold SPACE = hold the button; mouse traces.

enum State { READY, ACTIVE, COOLDOWN, LOCKOUT }

const RMB_TRACE := -2  # sentinel index: trace driven by right-mouse drag

signal state_changed

var battlefield: Battlefield
var enabled := true
var state: int = State.READY
var cooldown_left := 0.0
var cooldown_total := 1.0
var hold_left := 0.0
var trace := PackedVector2Array()
var _trace_line: Line2D = null
var _tracing_index := -1
var _button_held := false

func _exit_tree() -> void:
	Engine.time_scale = 1.0

func _process(delta: float) -> void:
	match state:
		State.COOLDOWN, State.LOCKOUT:
			cooldown_left -= delta
			if cooldown_left <= 0.0:
				state = State.READY
				state_changed.emit()
		State.ACTIVE:
			# Focus meter runs in REAL time — delta arrives dilated.
			hold_left -= delta / maxf(0.05, Engine.time_scale)
			if hold_left <= 0.0:
				_cancel()  # focus exhausted

func button_down() -> void:
	_button_held = true
	if state == State.READY and enabled:
		_begin()

func button_up() -> void:
	_button_held = false
	if state == State.ACTIVE:
		_cancel()

func _begin() -> void:
	state = State.ACTIVE
	hold_left = float(ConfigDb.v("timers", "trance_max_hold_s"))
	Engine.time_scale = float(ConfigDb.v("timers", "trance_time_scale"))
	battlefield.set_trance(true)
	state_changed.emit()

func _cancel() -> void:
	_end_trance()
	state = State.LOCKOUT  # brief lockout on release-without-summon (MADE UP)
	cooldown_total = float(ConfigDb.v("timers", "trance_release_lockout_s"))
	cooldown_left = cooldown_total
	state_changed.emit()

func _complete() -> void:
	_end_trance()
	state = State.COOLDOWN
	cooldown_total = float(ConfigDb.v("timers", "summon_cooldown_s"))
	cooldown_left = cooldown_total
	state_changed.emit()

func _end_trance() -> void:
	Engine.time_scale = 1.0
	battlefield.set_trance(false)
	_clear_trace()
	_tracing_index = -1

## Returns true if the event was consumed. Mode root routes input here first —
## the thumb belongs to the circle (§15.7).
func handle_input(ev: InputEvent) -> bool:
	if ev is InputEventKey and ev.keycode == KEY_SPACE and not ev.echo:
		if ev.pressed:
			button_down()
		else:
			button_up()
		return true
	# Desktop one-handed mapping (MADE UP): hold RIGHT mouse = hold the button,
	# and the same drag IS the trace. Laptops disable the trackpad while a key
	# is held, so Space+drag doesn't work there.
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_RIGHT:
		if ev.pressed:
			button_down()
			if state == State.ACTIVE:
				_tracing_index = RMB_TRACE
				trace = PackedVector2Array([battlefield.screen_to_world(ev.position)])
				_make_trace_line()
		else:
			if state == State.ACTIVE and _tracing_index == RMB_TRACE:
				_finish_trace()  # may summon → COOLDOWN
			_tracing_index = -1
			button_up()  # no-op unless still ACTIVE (nothing summoned)
		return true
	if ev is InputEventMouseMotion and _tracing_index == RMB_TRACE and state == State.ACTIVE:
		var wm := battlefield.screen_to_world(ev.position)
		if trace.size() == 0 or wm.distance_to(trace[trace.size() - 1]) > 5.0:
			trace.append(wm)
			if _trace_line != null:
				_trace_line.points = trace
		return true
	if state != State.ACTIVE:
		return false
	if ev is InputEventScreenTouch:
		if ev.pressed and _tracing_index == -1:
			_tracing_index = ev.index
			trace = PackedVector2Array([battlefield.screen_to_world(ev.position)])
			_make_trace_line()
			return true
		elif not ev.pressed and ev.index == _tracing_index:
			_finish_trace()
			_tracing_index = -1
			return true
	elif ev is InputEventScreenDrag and ev.index == _tracing_index:
		var w := battlefield.screen_to_world(ev.position)
		if trace.size() == 0 or w.distance_to(trace[trace.size() - 1]) > 5.0:
			trace.append(w)
			if _trace_line != null:
				_trace_line.points = trace
		return true
	return false

func _finish_trace() -> void:
	var cfg: Dictionary = ConfigDb.data["circle"]
	var length := 0.0
	for i in range(1, trace.size()):
		length += trace[i].distance_to(trace[i - 1])
	if trace.size() < int(cfg["min_points"]) or length < float(cfg["min_path_length_px"]):
		_clear_trace()  # too small to be an attempt — retry within the same hold
		return
	var g := CircleScorer.grade(trace)
	_show_feedback(g)  # feedback is MANDATORY — the player must see why 73 was 73
	var summoned := 0
	if g["valid"]:
		var mult := CircleScorer.multiplier(g["score"])
		for e in battlefield.essence_list():
			if e.global_position.distance_to(g["center"]) <= g["radius"]:
				var chaff := EntityFactory.make_chaff(mult)
				battlefield.spawn_unit(chaff, e.global_position)
				e.consume()
				summoned += 1
	GameState.add_summon(int(g["score"]), summoned)
	_complete()

func _show_feedback(g: Dictionary) -> void:
	var fb := TraceFeedback.new()
	fb.trace = trace.duplicate()
	fb.fitted_center = g["center"]
	fb.fitted_radius = g["radius"]
	fb.score = int(g["score"])
	fb.valid = g["valid"]
	battlefield.fx_root.add_child(fb)

func _make_trace_line() -> void:
	_clear_trace()
	_trace_line = Line2D.new()
	_trace_line.width = 4.0
	_trace_line.default_color = Color(0.5, 1.0, 0.85)  # trance trace color ≠ command color
	_trace_line.z_index = 70
	battlefield.fx_root.add_child(_trace_line)

func _clear_trace() -> void:
	trace = PackedVector2Array()
	if _trace_line != null and is_instance_valid(_trace_line):
		_trace_line.queue_free()
	_trace_line = null

func cooldown_frac() -> float:
	if state == State.COOLDOWN or state == State.LOCKOUT:
		return clampf(cooldown_left / cooldown_total, 0.0, 1.0)
	return 0.0

func focus_frac() -> float:
	if state == State.ACTIVE:
		return clampf(hold_left / float(ConfigDb.v("timers", "trance_max_hold_s")), 0.0, 1.0)
	return 1.0
