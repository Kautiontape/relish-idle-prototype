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

	_drift_floor(t, ground.get("drift_floor", {}))
	return t.failures


## DriftFloor's pure helpers, plus one built (not in the tree) floor.
func _drift_floor(t: TestUtil, cfg: Dictionary) -> void:
	t.suite("drift_floor")
	Palette.configure(TestUtil.load_json("res://configs/palette.json"))
	var screen := Rect2(0, 0, 1600, 900)
	t.ok(not cfg.is_empty(), "ground.json has a drift_floor section")
	t.ok(DriftFloor.streak_count(screen, {"density": 1.6}) == 230, "density is streaks per 100x100 px (1600x900 at 1.6 = 230)")
	t.ok(DriftFloor.streak_count(Rect2(0, 0, 1e5, 1e5), {"density": 1.6, "max_streaks": 4000}) == 4000, "streak count is capped by max_streaks")
	t.near(DriftFloor.reach(screen, Vector2.ZERO), Vector2(1600, 900).length(), 1e-3, "the exhale's reach is the farthest corner from the source")
	t.near(DriftFloor.reach(screen, Vector2(800, 450)), Vector2(800, 450).length(), 1e-3, "a central source reaches the half-diagonal")

	var img := DriftFloor.bake_field(func(p: Vector2) -> Vector2: return Vector2(0.5, -0.25) if p.x < 800.0 else Vector2.ZERO,
		screen, 32.0, 128)
	t.ok(img.get_size() == Vector2i(50, 29), "a 32 px grid over 1600x900 bakes 50x29 cells (%s)" % str(img.get_size()))
	t.ok(img.get_format() == Image.FORMAT_RGH, "the baked field is half float (filterable on GLES3)")
	var left := img.get_pixel(0, 0)
	t.near(left.r, 0.5, 1e-3, "baked drift keeps x")
	t.near(left.g, -0.25, 1e-3, "baked drift keeps a signed y")
	t.near(img.get_pixel(49, 0).r, 0.0, 1e-3, "zero drift bakes to zero (no streaks there)")
	t.ok(DriftFloor.bake_field(func(_p: Vector2) -> Vector2: return Vector2.ONE, Rect2(0, 0, 1e4, 10), 1.0, 128).get_width() == 128,
		"the bake is capped at max_cells per side")

	var comet := DriftFloor.comet_image(Vector2i(64, 8), 0.22, 2.2)
	t.near(comet.get_pixel(63, 4).a, 1.0, 0.01, "the comet's head is solid")
	t.ok(comet.get_pixel(0, 4).a < 0.01, "the comet's tail fades to nothing")
	var mono := true
	for x in range(1, 64):
		mono = mono and comet.get_pixel(x, 4).a >= comet.get_pixel(x - 1, 4).a
	t.ok(mono, "brightness rises tail to head, so a still frame shows direction")

	var ground := Palette.c("ground")
	var lifted := DriftFloor.lift_to_contrast(Palette.c("contour"), ground, 3.4)
	t.ok(DriftFloor.contrast(lifted, ground) >= 3.4, "a dim tint is lifted to the head contrast (%.2f:1)" % DriftFloor.contrast(lifted, ground))
	t.near(lifted.h, Palette.c("contour").h, 0.02, "lifting keeps the tint's hue")
	t.ok(DriftFloor.lift_to_contrast(Palette.c("vei"), ground, 3.4) == Palette.c("vei"), "a tint already past the target is left alone")
	t.near(DriftFloor.contrast(Color.WHITE, Color.BLACK), 21.0, 1e-3, "contrast() is WCAG (white on black = 21)")

	var f := DriftFloor.new()
	print("  (an ERROR about the dead tint is expected next)")
	f.setup(screen, Vector2(1, 0), Vector2(100, 100), "dead")
	t.ok(f.tint_key != "dead", "a dead tint is refused: dead matter never glows")
	t.ok(f.streaks() == DriftFloor.streak_count(screen, cfg), "setup() builds one streak per the config's density")
	f.free()
