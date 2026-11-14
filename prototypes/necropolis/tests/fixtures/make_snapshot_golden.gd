extends SceneTree
## Regenerates tests/fixtures/snapshot_golden.json for test_game_state_snapshot.gd. Run by hand only
## when GameState's behaviour is meant to change:
##   godot --headless --path prototypes/necropolis --script res://tests/fixtures/make_snapshot_golden.gd

func _init() -> void:
	var snap = load("res://tests/test_game_state_snapshot.gd").new()
	var all := {}
	for start in snap.STARTS:
		all[start] = snap.capture(start)
	var f := FileAccess.open(snap.GOLDEN, FileAccess.WRITE)
	f.store_string(JSON.stringify(all, "\t", true) + "\n")
	f.close()
	print("snapshot golden written: ", snap.GOLDEN)
	quit()
