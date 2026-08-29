extends SceneTree
## TEMPORARY runner for the raid logic tests (deleted before hand-off).
## godot --headless --path . --script res://tests/test_raid_runner_tmp.gd
## (Scene scripts are compile-checked by the windowed scene runs instead —
## autoloads like ConfigDb are not registered in --script mode.)


func _init() -> void:
	var failures: int = preload("res://tests/test_raid_logic.gd").new().run()
	if failures == 0:
		print("RAID LOGIC: ALL TESTS PASSED")
	else:
		print("RAID LOGIC FAILURES: ", failures)
	quit(1 if failures > 0 else 0)
