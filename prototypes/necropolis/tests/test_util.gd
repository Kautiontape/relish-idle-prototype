class_name TestUtil
extends RefCounted
## Tiny assert helper shared by test suites.

var failures := 0
var _suite := ""


func suite(name: String) -> void:
	_suite = name


func ok(cond: bool, msg: String) -> void:
	if cond:
		print("  PASS [%s] %s" % [_suite, msg])
	else:
		failures += 1
		printerr("  FAIL [%s] %s" % [_suite, msg])


func near(a: float, b: float, eps: float, msg: String) -> void:
	ok(absf(a - b) <= eps, "%s (%f vs %f)" % [msg, a, b])


static func load_json(path: String) -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}
