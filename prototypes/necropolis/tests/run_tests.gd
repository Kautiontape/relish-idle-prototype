extends SceneTree
## Headless test runner: godot --headless --path . --script res://tests/run_tests.gd
## Plain-assert pattern copied from the older prototypes' smoke tests.


func _init() -> void:
	var failures := 0
	var suites := [
		preload("res://tests/test_realm_sim.gd").new(),
		preload("res://tests/test_influence_field.gd").new(),
		preload("res://tests/test_pacing.gd").new(),
	]
	for s in suites:
		failures += s.run()
	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("FAILURES: ", failures)
	quit(1 if failures > 0 else 0)
