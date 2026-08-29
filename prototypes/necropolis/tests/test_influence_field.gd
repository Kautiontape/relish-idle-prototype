extends RefCounted
## Tests for the necrosis influence field: growth, entrenchment, pushback.


func _mk() -> InfluenceField:
	var cfg: Dictionary = TestUtil.load_json("res://configs/realm.json").get("field", {})
	var f := InfluenceField.new()
	f.setup(cfg, Vector2(2048, 1440))
	return f


func run() -> int:
	var t := TestUtil.new()
	t.suite("influence_field")
	var p_a := Vector2(400, 400)
	var p_b := Vector2(1600, 1000)

	# --- injection creates dominance -----------------------------------------
	var f := _mk()
	for i in 20:
		f.inject(p_a, true, 0.5, 1)
		f.tick(0.2)
	t.ok(f.dominance_at(p_a) > 0.1, "sustained green injection dominates the cell")
	t.ok(f.entrench_at(p_a) > 0.0, "held cell builds green entrenchment")

	# --- entrenchment accelerates growth -------------------------------------
	# A: long-held cell; B: fresh cell. Same injection afterwards; A must spread more.
	var f2 := _mk()
	for i in 80:
		f2.inject(p_a, true, 0.5, 1)
		f2.tick(0.2)
	var spread_a := 0.0
	var spread_b := 0.0
	var ca := f2.cell_of(p_a)
	var cb := f2.cell_of(p_b)
	for i in 10:
		f2.inject(p_a, true, 0.5, 1)
		f2.inject(p_b, true, 0.5, 1)
		f2.tick(0.2)
	# measure neighbourhood mass (spread), not just the peak
	for dy in range(-3, 4):
		for dx in range(-3, 4):
			if absi(dx) < 2 and absi(dy) < 2:
				continue
			spread_a += f2.green[(ca.y + dy) * f2.w + ca.x + dx]
			spread_b += f2.green[(cb.y + dy) * f2.w + cb.x + dx]
	t.ok(spread_a > spread_b * 1.5, "entrenched ground spreads faster than fresh ground (%.3f vs %.3f)" % [spread_a, spread_b])

	# --- opposition pushes back: erodes entrenchment, then flips -------------
	var f3 := _mk()
	for i in 60:
		f3.inject(p_a, true, 0.4, 1)
		f3.tick(0.2)
	var e_before := f3.entrench_at(p_a)
	for i in 120:
		f3.inject(p_a, false, 1.0, 1)
		f3.tick(0.2)
	t.ok(f3.entrench_at(p_a) < e_before, "opposing pressure erodes entrenchment")
	t.ok(f3.dominance_at(p_a) < 0.0, "sustained opposing pressure flips the cell")

	# --- performance guard: one tick stays cheap -----------------------------
	var f4 := _mk()
	var t0 := Time.get_ticks_usec()
	for i in 5:
		f4.tick(0.2)
	var per_tick_ms := (Time.get_ticks_usec() - t0) / 1000.0 / 5.0
	t.ok(per_tick_ms < 25.0, "field tick under 25ms (measured %.1fms)" % per_tick_ms)

	return t.failures
