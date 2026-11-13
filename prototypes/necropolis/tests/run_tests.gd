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
			var items := a.trim_prefix("--only=").split(",")
			for n in items:
				if n.strip_edges() == "":
					printerr("unknown arg: %s (--only needs a non-empty comma-separated list of suite names)" % a)
					quit(2)
					return
				only.append(n.strip_edges())
		else:
			printerr("unknown arg: %s (expected --slow or --only=a,b)" % a)
			quit(2)
			return
	var fast := _discover(TEST_DIR, true)
	var slow_suites := _discover(SLOW_DIR, false)
	var by_name := {}
	for p in fast + slow_suites:
		var nm := _suite_name(p)
		if by_name.has(nm):
			printerr("Suite name '%s' is ambiguous: %s and %s" % [nm, by_name[nm], p])
			quit(1)
			return
		by_name[nm] = p
	var suites: Array[String] = fast.duplicate()
	if slow:
		suites.append_array(slow_suites)
	if not only.is_empty():
		var unknown: Array[String] = []
		var slow_only: Array[String] = []
		var picked: Array[String] = []
		for n in only:
			var key := n.trim_suffix(".gd").trim_prefix("test_")
			if not by_name.has(key):
				unknown.append(n)
			elif not slow and slow_suites.has(by_name[key]):
				slow_only.append(n)
			elif not picked.has(by_name[key]):
				picked.append(by_name[key])
		if not unknown.is_empty() or not slow_only.is_empty():
			if not unknown.is_empty():
				printerr("Unknown suite(s): %s" % ", ".join(unknown))
			for n in slow_only:
				printerr("'%s' is a slow suite; add --slow" % n)
			quit(1)
			return
		suites = picked.duplicate()
		suites.sort_custom(func(x, y): return _order(x) < _order(y))
	print("Running %d suite(s)" % suites.size())
	OS.add_logger(errors)
	if not slow:
		# Slow suites do not run by default, but they must still compile.
		for p in slow_suites:
			var before := errors.count
			var sc = load(p)
			if sc == null or not sc.can_instantiate():
				printerr("  FAIL slow suite does not compile: %s" % p)
				failures += 1
			failures += errors.count - before
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


func _discover(dir: String, require_prefix: bool) -> Array[String]:
	var out: Array[String] = []
	if not DirAccess.dir_exists_absolute(dir):
		return out
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd") and (f.begins_with("test_") or not require_prefix):
			out.append("%s/%s" % [dir, f])
	out.sort()
	return out
