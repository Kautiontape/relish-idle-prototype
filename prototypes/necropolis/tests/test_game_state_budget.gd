extends RefCounted
## The tick budget (MECHANICS §10 "one tick() stays under its µs budget"), on the midgame_2flips
## fixture. Headless, no autoloads. Two measurements:
## (a) Per frame, with the shipped configs (the field sliced at field.slice_budget_cells): FRAMES calls
##     of tick(1/60, max_substeps_per_frame), what the shell does at 60 fps. Most frames run no
##     substep and only advance the field's slice; one in 30 runs a substep. The median must stay
##     under the 8 ms frame budget; the max (a substep frame) is reported, not asserted.
## (b) Per substep, with the field slowed (tick_hz lowered in a copy of the configs): tick(substep_s)
##     SUBSTEPS times, what catch-up and the soaks pay per substep. A generous ceiling only:
##     wall-clock asserts flake under load.

const FRAMES := 3000
const FRAME_BUDGET_US := 8000.0
const SUBSTEPS := 2000
const SLOW_FIELD_HZ := 0.01
## (b)'s ceiling: about 9× what jenova measures (~0.35 ms), so only a real regression trips it.
const SUBSTEP_CEILING_US := 3000.0


func run() -> int:
	var t := TestUtil.new()
	t.suite("game_state_budget")
	_per_frame(t)
	_per_substep(t)
	return t.failures


func _fixture(t: TestUtil, cfgs: Dictionary) -> GameState:
	var s := GameState.new(cfgs)
	s.debug_enabled = true
	t.ok(s.cmd_debug_load_fixture("midgame_2flips")["ok"], "the midgame_2flips fixture loads")
	return s


static func _pct(sorted: Array, p: float) -> int:
	return int(sorted[mini(sorted.size() - 1, int(sorted.size() * p))])


func _per_frame(t: TestUtil) -> void:
	var cfgs := TestUtil.configs()
	var s := _fixture(t, cfgs)
	var cap := s.max_substeps_per_frame()
	var all: Array = []
	var sub: Array = []  # frames that ran a substep
	var idle: Array = []  # frames that only advanced the field
	var n := 0
	for i in FRAMES:
		var t0 := Time.get_ticks_usec()
		var k := s.tick(1.0 / 60.0, cap)
		var us := Time.get_ticks_usec() - t0
		all.append(us)
		(sub if k > 0 else idle).append(us)
		n += k
	all.sort()
	sub.sort()
	idle.sort()
	var med := _pct(all, 0.5)
	print("  [budget] per frame, tick(1/60) × %d (%d substeps, field slice %d cells): median %d µs, p90 %d µs, p99 %d µs, max %d µs" % [
		FRAMES, n, int(cfgs["realm"]["field"]["slice_budget_cells"]), med, _pct(all, 0.9), _pct(all, 0.99), all[-1]])
	print("  [budget] per frame: no-substep frames median %d µs, max %d µs; substep frames median %d µs, max %d µs (%d)" % [
		_pct(idle, 0.5), idle[-1], _pct(sub, 0.5) if not sub.is_empty() else -1, sub[-1] if not sub.is_empty() else -1, sub.size()])
	t.ok(absi(n - int(FRAMES / 30.0)) <= 1, "one substep per 30 frames (%d)" % n)
	t.ok(med < FRAME_BUDGET_US, "a frame's tick: median under the %d µs frame budget (measured %d µs; max %d µs)" % [
		int(FRAME_BUDGET_US), med, all[-1]])


func _per_substep(t: TestUtil) -> void:
	var cfgs := TestUtil.configs()
	cfgs["realm"]["field"]["tick_hz"] = SLOW_FIELD_HZ
	var s := _fixture(t, cfgs)
	var step := s.substep_s()
	var each: Array = []
	var n := 0
	var t0 := Time.get_ticks_usec()
	for i in SUBSTEPS:
		var t1 := Time.get_ticks_usec()
		n += s.tick(step)
		each.append(Time.get_ticks_usec() - t1)
	var avg := float(Time.get_ticks_usec() - t0) / float(SUBSTEPS)
	each.sort()
	t.ok(n == SUBSTEPS, "tick(substep) ran one substep each (%d)" % n)
	print("  [budget] per substep, field at %.2f Hz: avg %d µs, median %d µs, max %d µs · 1 h ≈ %.2f s · 12 h at 0.5 s steps ≈ %.1f s" % [
		SLOW_FIELD_HZ, int(avg), _pct(each, 0.5), each[-1], avg * 7200.0 / 1e6, avg * 86400.0 / 1e6])
	t.ok(avg < SUBSTEP_CEILING_US, "substep average under %d µs with the field slowed (measured %d µs)" % [int(SUBSTEP_CEILING_US), int(avg)])
