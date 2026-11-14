extends RefCounted
## Catch-up's field step, InfluenceField.catchup_step(dt) (IDLE §4): finite at every dt, a pure
## function of (field, injects, dt, config), published at once, close to the live ticks it stands for
## at small dt, and keeping the live field's fixed point at large dt. On FieldScenario's 40 x 30
## "mini" grid so it runs fast. Owner agreement over 12 h and the cost per call, against live ticks
## on the shipped grid, are tests/slow/field_catchup_bench.gd.

const PERIOD := 0.2


func _cfg() -> Dictionary:
	return TestUtil.load_json("res://configs/realm.json")["field"]


## A copy of f's published state on a fresh field (no queue, no scratch): the same input to a step.
static func _clone(f: InfluenceField) -> InfluenceField:
	var c := InfluenceField.new()
	c.setup(f.cfg, f.world_size)
	c.green = f.green.duplicate()
	c.orange = f.orange.duplicate()
	c.entrench = f.entrench.duplicate()
	c._head = [f.green.duplicate(), f.orange.duplicate(), f.entrench.duplicate()]
	return c


static func _maxdiff(a: PackedFloat32Array, b: PackedFloat32Array) -> float:
	var m := 0.0
	for i in a.size():
		m = maxf(m, absf(a[i] - b[i]))
	return m


static func _phi_diff(a: InfluenceField, b: InfluenceField) -> float:
	var m := 0.0
	for i in a.green.size():
		m = maxf(m, absf((a.green[i] - a.orange[i]) - (b.green[i] - b.orange[i])))
	return m


static func _vmax(a: Array, b: Array) -> float:
	var m := 0.0
	for i in a.size():
		m = maxf(m, absf(float(a[i]) - float(b[i])))
	return m


static func _sane(f: InfluenceField) -> bool:
	var em := float(f.cfg.get("entrench_max", 2.5))
	for i in f.green.size():
		var g := f.green[i]
		var o := f.orange[i]
		var e := f.entrench[i]
		if not (is_finite(g) and is_finite(o) and is_finite(e)):
			return false
		if g < 0.0 or g > 4.0 or o < 0.0 or o > 4.0 or absf(e) > em + 1e-4:
			return false
	return true


func _live(f: InfluenceField, s: FieldScenario, t: float, ticks: int) -> void:
	for k in ticks:
		s.inject(f, t, PERIOD)
		f.tick(PERIOD)
	f.flush()


func run() -> int:
	var t := TestUtil.new()
	t.suite("field_catchup")
	var cfg := _cfg()
	for k in ["catchup_exact_ticks", "catchup_sweeps", "catchup_extra_sweeps", "catchup_extra_tol", "catchup_extra_ramp_ticks", "catchup_omega",
			"catchup_eps"]:
		t.ok(cfg.has(k), "realm.json field.%s is tuned" % k)
	t.ok(float(cfg["contest"]) * 5.0 / float(cfg["tick_hz"]) >= 1.0,
		"the shipped contest wipes the weaker side each live tick (the step's one-colour-per-cell premise)")
	var s := FieldScenario.make("mini")
	var base := s.prewarmed(cfg)
	_live(base, s, 0.0, 400)  # contested and still settling

	# dt <= 0: nothing changes, the injects stay queued
	var f := _clone(base)
	s.inject(f, 0.0, PERIOD)
	var g0 := f.green.duplicate()
	var queued: int = f._open.size()
	f.catchup_step(0.0)
	f.catchup_step(-5.0)
	f.catchup_step(NAN)
	t.ok(f.green == g0 and f._open.size() == queued and queued > 0, "dt <= 0 or NaN changes nothing and leaves the injects queued")

	# published at once, injects consumed, the live pipeline restarts as after flush()
	f.catchup_step(300.0)
	t.ok(f.in_flight() == 0 and f._open.is_empty(), "after a step nothing is in flight and the injects are consumed")
	t.ok(f.green == f._head[0] and f.orange == f._head[1] and f.entrench == f._head[2],
		"the live arrays are the step's result (dominance_at and view_field read it at once)")
	var c := s.villages[0] as Vector2i
	t.ok(is_equal_approx(f.dominance_at(s.pos_of(c)), f.green[c.y * f.w + c.x] - f.orange[c.y * f.w + c.x]), "dominance_at reads the new field")
	var lag: Array = []
	for k in 3:
		s.inject(f, 300.0, PERIOD)
		f.tick(PERIOD)
		lag.append(f.in_flight())
	t.ok(lag == [1, 2, 2], "live ticks carry on after it with the usual lag (%s)" % str(lag))
	f.flush()
	t.ok(_sane(f), "and stay finite and in range")

	# queued live work is finished first: a step mid-lag equals a step after flush()
	var a := _clone(base)
	var b := _clone(base)
	for k in 5:
		s.inject(a, 0.0, PERIOD)
		a.tick(PERIOD)
		s.inject(b, 0.0, PERIOD)
		b.tick(PERIOD)
	b.flush()
	t.ok(a.in_flight() == 2 and b.in_flight() == 0, "one field has ticks in flight, the other none")
	s.inject(a, 0.0, PERIOD)
	s.inject(b, 0.0, PERIOD)
	a.catchup_step(120.0)
	b.catchup_step(120.0)
	t.ok(a.green == b.green and a.orange == b.orange and a.entrench == b.entrench,
		"a step finishes the queued live work first: the same result with or without a flush before it")

	# deterministic, nothing carried between calls: the same input gives the same bits, whatever ran before
	var p := _clone(base)
	var q := _clone(base)
	var r := _clone(base)
	s.inject(r, 0.0, PERIOD)
	r.catchup_step(77.0)  # r: its scratch holds another step's data, then other history,
	for k in 30:  # then its state set back to base's
		s.inject(r, 0.0, PERIOD)
		r.tick(PERIOD)
	r.green = base.green.duplicate()
	r.orange = base.orange.duplicate()
	r.entrench = base.entrench.duplicate()
	r.flush()
	r._head = [base.green.duplicate(), base.orange.duplicate(), base.entrench.duplicate()]
	for fld in [p, q, r]:
		s.inject(fld, 600.0, PERIOD)
		fld.catchup_step(300.0)
	t.ok(p.green == q.green and p.green == r.green and p.entrench == q.entrench and p.entrench == r.entrench,
		"deterministic: the same field, injects and dt give the same bits, whatever the field did before")
	var seq_a := _clone(base)
	var seq_b := _clone(base)
	for k in 6:
		s.inject(seq_a, 300.0 * (k + 1), PERIOD)
		seq_a.catchup_step(300.0)
	for k in 6:  # the same steps, with reads and empty work in between (a progress screen's chunks)
		seq_b.advance(1400)
		seq_b.flush()
		var _d := seq_b.dominance_at(Vector2(100, 100))
		s.inject(seq_b, 300.0 * (k + 1), PERIOD)
		seq_b.catchup_step(300.0)
	t.ok(seq_a.green == seq_b.green and seq_a.entrench == seq_b.entrench, "chunking the steps never changes the result")

	# finite and in range at every dt
	var bad: Array = []
	for dt in [1e-4, 0.2, 0.5, 5.0, 30.0, 288.0, 1200.0, 5000.0, 86400.0, 604800.0, 1e9]:
		var fd := _clone(base)
		s.inject(fd, 0.0, PERIOD)
		fd.catchup_step(dt)
		s.inject(fd, 0.0, PERIOD)
		fd.catchup_step(dt)
		if not _sane(fd):
			bad.append(dt)
	t.ok(bad.is_empty(), "finite, 0..4 and |entrench| <= max after two steps at every dt up to 1e9 s (bad: %s)" % str(bad))
	var z := InfluenceField.new()
	z.setup(s.field_cfg(cfg), s.world_size())
	z.catchup_step(5000.0)
	t.ok(z.green.count(0.0) == z.green.size() and z.orange.count(0.0) == z.orange.size(), "an empty field without sources stays empty")

	# large dt keeps the live field's fixed point, and settles to it after a flip
	var settled := _clone(base)
	_live(settled, s, 600.0, 4000)

	# small dt follows the live ticks it stands for, right after a fort flips (sources of t = 2400 s)
	for row in [[0.2, 1, 0.0], [1.0, 5, 0.0], [1.5, 7, 0.01], [5.0, 25, 0.03], [30.0, 150, 0.05], [120.0, 600, 0.06]]:
		var lv := _clone(settled)
		_live(lv, s, 2400.0, row[1])
		var cu := _clone(settled)
		s.inject(cu, 2400.0, PERIOD)
		cu.catchup_step(row[0])
		var dv := _vmax(s.doms(lv), s.doms(cu))
		t.ok(dv <= row[2], "dt %.1f s after a flip: villages within %.3f of %d live ticks (%.4f; the ticks moved them %.4f)" % [
			row[0], row[2], row[1], dv, _vmax(s.doms(lv), s.doms(settled))])
	# runs of short steps: 2 s is the shortest field step economy sends (above catchup_exact_ticks)
	for row in [[2.0, 30, 0.03], [48.0, 10, 0.03]]:
		var lv := _clone(settled)
		_live(lv, s, 2400.0, int(round(row[0] * row[1] / PERIOD)))
		var cu := _clone(settled)
		for k in row[1]:
			s.inject(cu, 2400.0, PERIOD)
			cu.catchup_step(row[0])
		var dv := _vmax(s.doms(lv), s.doms(cu))
		t.ok(dv <= row[2], "%d steps of %.0f s after a flip: villages within %.2f of the live ticks (%.4f)" % [row[1], row[0], row[2], dv])
	var hold := _clone(settled)
	s.inject(hold, 600.0, PERIOD)
	hold.catchup_step(5000.0)
	t.ok(_phi_diff(hold, settled) <= 0.01, "a settled live field stays put under a 5000 s step with the same sources (%.4f)" % _phi_diff(hold, settled))
	var lv2 := _clone(settled)
	_live(lv2, s, 2400.0, 4000)  # u flips at 2100 s: fort 0 goes orange
	var cu2 := _clone(settled)
	for k in 4:
		s.inject(cu2, 2400.0, PERIOD)
		cu2.catchup_step(200.0)
	var dv2 := _vmax(s.doms(lv2), s.doms(cu2))
	var moved := _vmax(s.doms(lv2), s.doms(settled))
	t.ok(dv2 <= 0.03 and moved > 0.2, "after a fort flips, four 200 s steps land within 0.03 of 4000 live ticks at the villages (%.4f; the flip moved them %.3f)" % [dv2, moved])
	t.ok(FieldScenario.owners(s.doms(lv2), float(cfg["town_threshold"])) == FieldScenario.owners(s.doms(cu2), float(cfg["town_threshold"])),
		"... and every village has the live owner")
	return t.failures
