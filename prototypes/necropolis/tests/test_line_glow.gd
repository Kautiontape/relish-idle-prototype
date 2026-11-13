extends RefCounted
## Tests for LineGlow's stroke stack (BRIEF §8) and the dead-never-glows guard.


func run() -> int:
	var t := TestUtil.new()
	t.suite("line_glow")
	Palette.configure(TestUtil.load_json("res://configs/palette.json"))
	LineGlow.configure(TestUtil.load_json("res://configs/line_glow.json"))

	var col := Color(Palette.c("undead"), 0.8)
	var ls: Array = LineGlow.layers(col, 1.5)
	t.ok(ls.size() == 4, "full glow is four stacked strokes")
	var widths := []
	var alphas := []
	for l in ls:
		widths.append(snappedf(l[0], 0.001))
		alphas.append(snappedf(l[1].a, 0.001))
	t.ok(widths == [10.0, 6.0, 3.0, 1.5], "at core width 1.5 the stack is 10/6/3/1.5 (%s)" % str(widths))
	t.ok(alphas == [0.08, 0.176, 0.52, 0.8], "alphas are .10/.22/.65/1.0 x the colour's alpha (%s)" % str(alphas))

	var wide: Array = LineGlow.layers(col, 3.0)
	t.near(wide[0][0], 20.0, 1e-4, "halos scale with the core width (06 glowLane)")
	t.near(wide[3][0], 3.0, 1e-4, "the core stroke is drawn at exactly `width`")

	var half: Array = LineGlow.layers(col, 1.5, 0.5)
	t.near(half[1][1].a, 0.8 * 0.22 * 0.5, 1e-4, "glow amount scales halo alpha")
	t.near(half[3][1].a, 0.8, 1e-4, "glow amount leaves the core alone")
	var bare: Array = LineGlow.layers(col, 1.5, 0.0)
	t.ok(bare.size() == 1 and is_equal_approx(bare[0][0], 1.5), "glow 0 is a single core stroke, not nothing")

	var core := Palette.c("undead_core")
	var cored: Array = LineGlow.layers(col, 1.5, 1.0, core)
	t.ok(Color(cored[3][1], 1.0).is_equal_approx(core), "core colour fills the innermost stroke")
	t.ok(Color(cored[0][1], 1.0).is_equal_approx(Palette.c("undead")), "halos keep the line colour")

	t.ok(LineGlow.is_dead(Palette.c("dead", 0.3)), "dead at any alpha counts as dead matter")
	t.ok(LineGlow.is_dead(Palette.c("dead_lit")), "dead_lit is a lit surface, still dead matter")
	t.ok(not LineGlow.is_dead(Palette.c("undead")), "undead may glow")

	t.ok(LineGlow.segments(24.0, TAU) >= 8, "arcs get at least the minimum segment count")
	t.ok(LineGlow.segments(4000.0, TAU) <= 128, "arcs are capped at the maximum segment count")
	return t.failures
