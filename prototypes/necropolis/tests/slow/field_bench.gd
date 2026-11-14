extends RefCounted
## The influence field's cost (run with tests/run.sh --slow --only=field_bench): µs per cell for a
## whole field step, µs per advance() slice at the shipped `field.slice_budget_cells` (picked to land
## near 600 µs on jenova), and the field's cost per frame at 60 fps (MECHANICS §10's 3000 µs): every
## frame one advance(budget), plus the substep's tick pair when one is due, the way GameState calls
## them. Loose bounds only: wall-clock asserts flake under load, so the frame check asserts the best
## p99 of three runs and prints the max.

const FPS := 60.0
const FRAMES := 1800  # 30 s of frames per run
const RUNS := 3
const FRAME_BUDGET_US := 3000


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
	_per_frame(t, f, cfg, budget)
	return t.failures


## GameState's cadence (§3): a substep every economy.sim.substep_s; in it, the field ticks at tick_hz
## (at most max_ticks_per_step, the injects before each tick); after every tick(dt) call, one
## advance(budget). The frames with a tick pair publish synchronously, so they carry the max.
func _per_frame(t: TestUtil, f: InfluenceField, cfg: Dictionary, budget: int) -> void:
	var substep := float(TestUtil.configs()["economy"]["sim"].get("substep_s", 0.5))
	var period := 1.0 / float(cfg.get("tick_hz", 5.0))
	var max_ticks := int(cfg.get("max_ticks_per_step", 2))
	var best_p99 := 1 << 30
	var worst := 0
	var med := 0
	var tick_frames := 0
	for run in RUNS:
		var us: Array = []
		var sub_acc := 0.0
		var field_acc := 0.0
		tick_frames = 0
		for i in FRAMES:
			var t0 := Time.get_ticks_usec()
			sub_acc += 1.0 / FPS
			if sub_acc >= substep:
				sub_acc -= substep
				field_acc += substep
				var k := 0
				while field_acc >= period and k < max_ticks:
					field_acc -= period
					f.inject(Vector2(400 + (i % 7) * 150, 400), true, 0.3, 2)
					f.inject(Vector2(1600, 1000 - (i % 5) * 100), false, 0.3, 2)
					f.tick(period)
					k += 1
				field_acc = minf(field_acc, period * float(cfg.get("acc_cap_periods", 4.0)))
				tick_frames += 1
			f.advance(budget)
			us.append(Time.get_ticks_usec() - t0)
		us.sort()
		var p99: int = us[mini(us.size() - 1, int(us.size() * 0.99))]
		if p99 < best_p99:
			best_p99 = p99
			med = us[us.size() / 2]
		worst = maxi(worst, us[-1])
	print("  per frame at %d fps (%d frames, %d with a tick pair, budget %d cells): best-of-%d p99 %d µs, median %d µs, max %d µs (target %d µs)" % [
		int(FPS), FRAMES, tick_frames, budget, RUNS, best_p99, med, worst, FRAME_BUDGET_US])
	t.ok(best_p99 <= FRAME_BUDGET_US, "the field's per-frame cost stays under MECHANICS §10's %d µs (best p99 %d µs, max %d µs)" % [
		FRAME_BUDGET_US, best_p99, worst])
