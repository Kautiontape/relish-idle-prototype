extends SceneTree
## Headless test runner: godot --headless --path . --script res://tests/run_tests.gd
## Discovers every res://tests/test_*.gd that defines run() -> int (failure count)
## and runs them in name order. Adding a suite never touches this file.
## Suites run inside _init(), before autoloads exist: build what you test directly.
## A script error inside a suite (crash, compile error) counts as a failure;
## push_error() does not, so suites can exercise loud-failure paths.

const TEST_DIR := "res://tests"


## Counts script errors; GDScript would otherwise abort the function and carry on.
class ScriptErrors extends Logger:
	var count := 0

	func _log_error(_function: String, _file: String, _line: int, _code: String, _rationale: String,
			_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == ERROR_TYPE_SCRIPT:
			count += 1


func _init() -> void:
	var failures := 0
	var errors := ScriptErrors.new()
	OS.add_logger(errors)
	for p in _discover():
		var before := errors.count
		failures += _run_suite(p)
		var crashed := errors.count - before
		if crashed > 0:
			printerr("  FAIL %d script error(s) while running %s" % [crashed, p])
			failures += crashed
	OS.remove_logger(errors)
	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("FAILURES: ", failures)
	quit(1 if failures > 0 else 0)


func _run_suite(p: String) -> int:
	var suite = load(p)
	if suite == null or not suite.can_instantiate():
		printerr("  FAIL could not load suite %s" % p)
		return 1
	var inst = suite.new()
	if not inst.has_method("run"):
		print("  (skip, no run(): %s)" % p)
		return 0
	var n = inst.run()
	return n if n is int else 1


func _discover() -> Array[String]:
	var out: Array[String] = []
	for f in DirAccess.get_files_at(TEST_DIR):
		if f.begins_with("test_") and f.ends_with(".gd"):
			out.append("%s/%s" % [TEST_DIR, f])
	out.sort()
	return out
