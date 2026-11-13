extends RefCounted
## Ground and drift-floor wiring: one flag, one tempo, no key clashes.


func run() -> int:
	var t := TestUtil.new()
	t.suite("ground")
	var pulse := TestUtil.load_json("res://configs/pulse.json")
	var ground := TestUtil.load_json("res://configs/ground.json")

	# One flag, one tempo: the ground takes both from Pulse.
	t.ok(str(pulse.get("reduced_motion_key", "")) == "F8", "Pulse toggles reduced motion on F8")
	t.ok(not ground.has("tempo_ms"), "ground.json carries no tempo of its own (Pulse.tempo_ms)")
	t.ok(not ground.has("tempo_spread"), "ground.json carries no wave spread of its own (Pulse.wave_spread)")
	t.ok(not ground.has("reduced_motion"), "ground.json carries no reduced-motion flag (Pulse.reduced_motion)")

	# Keys: F8 is Pulse's, F9 the greyscale check; the map's other debug keys
	# and the screenshot key must not collide with either.
	var src := FileAccess.get_file_as_string("res://scripts/map/map_field_view.gd")
	t.ok(src.find("KEY_F8") < 0, "the map ground does not handle F8 (Pulse owns it)")
	t.ok(src.find("KEY_F9") >= 0, "F9 is the map's greyscale check")
	var shot := FileAccess.get_file_as_string("res://autoload/shot.gd")
	t.ok(shot.find("KEY_F8") < 0 and shot.find("KEY_F9") < 0, "the shot harness keeps off F8 and F9")
	return t.failures
