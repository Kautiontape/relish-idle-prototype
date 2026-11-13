extends RefCounted
## The influence field's cost (run with tests/run.sh --slow --only=field_bench): µs per cell for a
## whole field step, and µs per advance() slice at the shipped `field.slice_budget_cells`. That budget
## is picked to land near 600 µs on jenova. Loose bound only: wall-clock asserts flake under load.


func run() -> int:
	var t := TestUtil.new()
	t.suite("field_bench")
	var cfg: Dictionary = TestUtil.configs()["realm"]["field"]
	var budget := int(cfg.get("slice_budget_cells", 0))
	var f := InfluenceField.new()
	f.setup(cfg, Vector2(2048, 1440))
	var cells := f.w * f.h
	for i in 40:  # some texture in the field so every branch of the step runs
		f.inject(Vector2(400, 400), true, 0.6, 2)
		f.inject(Vector2(1600, 1000), false, 0.6, 3)
		f.inject(Vector2(1000, 700), i % 2 == 0, 0.8, 2)
		f.tick(0.2)
	f.flush()

	var full: Array = []
	for r in 21:
		f.tick(0.2)
		var t0 := Time.get_ticks_usec()
		f.advance(0)
		full.append(Time.get_ticks_usec() - t0)
	full.sort()
	var us_per_cell := float(full[10]) / float(f.last_advance_cells if f.last_advance_cells > 0 else cells)
	print("  field step: %d cells, median %d µs, min %d µs -> %.3f µs per cell" % [cells, full[10], full[0], us_per_cell])

	t.ok(budget > 0, "realm.json ships a sliced budget (%d cells)" % budget)
	if budget <= 0:
		return t.failures
	var slices: Array = []
	for r in 12:
		f.tick(0.2)
		while f.queued_cells() > 0:
			var t0 := Time.get_ticks_usec()
			f.advance(budget)
			if f.last_advance_cells == budget:  # full slices only
				slices.append(Time.get_ticks_usec() - t0)
	slices.sort()
	var med: int = slices[int(slices.size() * 0.5)]
	var p90: int = slices[int(slices.size() * 0.9)]
	print("  slice of %d cells: median %d µs, p90 %d µs, max %d µs (%d slices; target ~600 µs)" % [
		budget, med, p90, slices[-1], slices.size()])
	t.ok(med < 1500, "a %d-cell slice stays well under a frame (median %d µs, target ~600)" % [budget, med])
	return t.failures
