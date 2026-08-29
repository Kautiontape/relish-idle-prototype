extends SceneTree
## Headless test runner: godot --headless --path . --script res://tests/run_tests.gd
## Core suites always run; worker-owned suites (raid/town) are included
## automatically once their files exist.


func _init() -> void:
	var failures := 0
	var suite_paths := [
		"res://tests/test_realm_sim.gd",
		"res://tests/test_influence_field.gd",
		"res://tests/test_pacing.gd",
		"res://tests/test_raid_logic.gd",
		"res://tests/test_town_logic.gd",
	]
	for p in suite_paths:
		if not FileAccess.file_exists(p):
			print("  (skip, not present: %s)" % p)
			continue
		var suite = load(p)
		if suite == null:
			printerr("  FAIL could not load suite %s" % p)
			failures += 1
			continue
		failures += suite.new().run()
	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("FAILURES: ", failures)
	quit(1 if failures > 0 else 0)
