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


## The configs the unit suites build on: res://configs with the Grow stance's default off (Phase I P3), so a new game
## in a suite that tests another feature (an upgrade, the queue's walk, a contract's success path) isn't changed by
## Grow's starts. test_grow turns it on; the autoplay profiles and the game run the shipped default (shipped_configs).
static func configs() -> Dictionary:
	var c := GameState.load_configs("res://configs")
	c["economy"]["stance"]["grow"]["default_on"] = false
	return c


## res://configs as shipped (the Grow stance on in a new game): the autoplayer's and test_grow's default check.
static func shipped_configs() -> Dictionary:
	return GameState.load_configs("res://configs")
