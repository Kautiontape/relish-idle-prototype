class_name RaidTrance
extends Node
## The trance: hold SPACE or RIGHT mouse → bullet time (Engine.time_scale 0.35).
## While held, LEFT-drag traces the raise circle. Release the drag → score →
## feedback → raise. Focus drains in REAL time (max hold 4s), cooldown 6s after
## a summon, 1s lockout on an empty release. Ported/simplified from
## raid-and-raise's trance_controller.gd.

enum State { READY, ACTIVE, COOLDOWN, LOCKOUT }

var raid: Node = null
var enabled := true
var state: int = State.READY
var cooldown_left := 0.0
var cooldown_total := 1.0
var hold_left := 0.0
var trace := PackedVector2Array()

var _trace_line: Line2D = null
var _tracing := false
var _button_held := false


func _cfg() -> Dictionary:
	return ConfigDb.data.get("raid", {}).get("trance", {})


func _exit_tree() -> void:
	Engine.time_scale = 1.0


func _process(delta: float) -> void:
	match state:
		State.COOLDOWN, State.LOCKOUT:
			cooldown_left -= delta
			if cooldown_left <= 0.0:
				state = State.READY
				if _button_held and enabled:
					_begin()  # held through the cooldown → re-enter immediately
		State.ACTIVE:
			# focus runs in REAL time — delta arrives dilated
			hold_left -= delta / maxf(0.05, Engine.time_scale)
			if hold_left <= 0.0:
				_cancel()


func force_end() -> void:
	enabled = false
	if state == State.ACTIVE:
		_end_trance()
		state = State.READY


## Returns true if the event was consumed.
func handle_input(ev: InputEvent) -> bool:
	if not enabled:
		return false
	if ev is InputEventKey and ev.keycode == KEY_SPACE and not ev.echo:
		if ev.pressed:
			_button_down()
		else:
			_button_up()
		return true
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_RIGHT:
		if ev.pressed:
			_button_down()
		else:
			_button_up()
		return true
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
		if ev.pressed and state == State.ACTIVE:
			_tracing = true
			trace = PackedVector2Array([raid.screen_to_world(ev.position)])
			_make_trace_line()
			return true
		if not ev.pressed and _tracing:
			_tracing = false
			if state == State.ACTIVE:
				_finish_trace()
			else:
				_clear_trace()
			return true
		return false
	if ev is InputEventMouseMotion and _tracing and state == State.ACTIVE:
		var w: Vector2 = raid.screen_to_world(ev.position)
		if trace.size() == 0 or w.distance_to(trace[trace.size() - 1]) > 5.0:
			trace.append(w)
			if _trace_line != null:
				_trace_line.points = trace
		return true
	return false


func _button_down() -> void:
	_button_held = true
	if state == State.READY and enabled:
		_begin()


func _button_up() -> void:
	_button_held = false
	if state == State.ACTIVE:
		_cancel()


func _begin() -> void:
	state = State.ACTIVE
	hold_left = float(_cfg().get("max_hold_s", 4.0))
	Engine.time_scale = float(_cfg().get("time_scale", 0.35))
	raid.set_trance(true)


func _cancel() -> void:
	_end_trance()
	state = State.LOCKOUT
	cooldown_total = float(_cfg().get("lockout_s", 1.0))
	cooldown_left = cooldown_total


func _complete() -> void:
	_end_trance()
	state = State.COOLDOWN
	cooldown_total = float(_cfg().get("cooldown_s", 6.0))
	cooldown_left = cooldown_total


func _end_trance() -> void:
	Engine.time_scale = 1.0
	_tracing = false
	if raid != null:
		raid.set_trance(false)
	_clear_trace()


func _finish_trace() -> void:
	var ccfg: Dictionary = ConfigDb.data.get("circle", {})
	var length := 0.0
	for i in range(1, trace.size()):
		length += trace[i].distance_to(trace[i - 1])
	if trace.size() < int(ccfg.get("min_points", 8)) or length < float(ccfg.get("min_path_length_px", 110)):
		_clear_trace()  # too small to be an attempt — retry within the same hold
		return
	var g := CircleScorer.grade(trace)
	raid.show_trace_feedback(g, trace.duplicate())  # the player must see WHY 73 was 73
	if g["valid"]:
		raid.perform_raise(g)
	_complete()


func _make_trace_line() -> void:
	_clear_trace()
	_trace_line = Line2D.new()
	_trace_line.width = 4.0
	_trace_line.default_color = Color("#50ffd9")
	_trace_line.z_index = 70
	raid.fx_root.add_child(_trace_line)


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
		return clampf(hold_left / float(_cfg().get("max_hold_s", 4.0)), 0.0, 1.0)
	return 1.0
