extends SceneTree
## Headless test runner: godot --headless --path . --script res://tests/run_tests.gd
## Discovers every res://tests/test_*.gd that defines run() -> int (failure count)
## and runs them in name order. Adding a suite never touches this file.
## Suites run inside _init(), before autoloads exist: build what you test directly.
## A script error inside a suite (crash, compile error) counts as a failure;
## push_error() does not, so suites can exercise loud-failure paths.
## Flags (after --): --only=a,b runs just those suites (name = file minus test_/.gd);
## --slow also runs res://tests/slow/*.gd.

const TEST_DIR := "res://tests"
const SLOW_DIR := "res://tests/slow"


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
	var only: Array[String] = []
	var slow := false
	for a in OS.get_cmdline_user_args():
		if a == "--slow":
			slow = true
		elif a.begins_with("--only="):
			for n in a.trim_prefix("--only=").split(",", false):
				only.append(n.strip_edges())
	var suites := _discover(slow)
	if not only.is_empty():
		var known := {}
		for p in suites:
			known[_suite_name(p)] = p
		var unknown: Array[String] = []
		var picked: Array[String] = []
		for n in only:
			var key := n.trim_suffix(".gd").trim_prefix("test_")
			if known.has(key):
				if not picked.has(known[key]):
					picked.append(known[key])
			else:
				unknown.append(n)
		if picked.is_empty() or not unknown.is_empty():
			printerr("Unknown suite(s): %s" % ", ".join(unknown))
			quit(1)
			return
		suites = picked.duplicate()
		suites.sort_custom(func(x, y): return _order(x) < _order(y))
	print("Running %d suite(s)" % suites.size())
	OS.add_logger(errors)
	for p in suites:
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


func _suite_name(p: String) -> String:
	return p.get_file().trim_suffix(".gd").trim_prefix("test_")


## Default suites sort before slow ones, each group by name.
func _order(p: String) -> String:
	return ("1" if p.begins_with(SLOW_DIR) else "0") + p


func _discover(slow: bool) -> Array[String]:
	var out: Array[String] = []
	for f in DirAccess.get_files_at(TEST_DIR):
		if f.begins_with("test_") and f.ends_with(".gd"):
			out.append("%s/%s" % [TEST_DIR, f])
	out.sort()
	if slow and DirAccess.dir_exists_absolute(SLOW_DIR):
		var extra: Array[String] = []
		for f in DirAccess.get_files_at(SLOW_DIR):
			if f.ends_with(".gd"):
				extra.append("%s/%s" % [SLOW_DIR, f])
		extra.sort()
		out.append_array(extra)
	return out
