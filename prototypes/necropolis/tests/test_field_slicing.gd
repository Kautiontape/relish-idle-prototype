extends RefCounted
## The time-sliced influence field (STATE-API §3 step 9, §5.6): the live field is E1's field as of
## `lag_ticks` ago plus every inject since, bit for bit, at every budget, slicing and frame cadence.
## The µs-per-cell bench is tests/slow/field_bench.gd (wall-clock asserts would flake here).

const UNBOUNDED := 1 << 30


## E1's field, frozen from f464659 (inject and tick verbatim): the unsliced step every result must
## match bit for bit. Never edit it to make a test pass.
class E1Field:
	var w := 128
	var h := 90
	var green := PackedFloat32Array()
	var orange := PackedFloat32Array()
	var entrench := PackedFloat32Array()
	var world_size := Vector2(2048, 1440)
	var cfg := {}

	func setup(cfg_in: Dictionary, world_size_in: Vector2) -> void:
		cfg = cfg_in
		w = int(cfg.get("w", 128))
		h = int(cfg.get("h", 90))
		world_size = world_size_in
		green.resize(w * h)
		orange.resize(w * h)
		entrench.resize(w * h)
		green.fill(0.0)
		orange.fill(0.0)
		entrench.fill(0.0)

	func copy() -> E1Field:
		var c := E1Field.new()
		c.cfg = cfg
		c.w = w
		c.h = h
		c.world_size = world_size
		c.green = green.duplicate()
		c.orange = orange.duplicate()
		c.entrench = entrench.duplicate()
		return c

	func cell_of(pos: Vector2) -> Vector2i:
		return Vector2i(
			clampi(int(pos.x / world_size.x * w), 0, w - 1),
			clampi(int(pos.y / world_size.y * h), 0, h - 1))

	func inject(pos: Vector2, is_green: bool, amount: float, radius := 1) -> void:
		var c := cell_of(pos)
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				var x := c.x + dx
				var y := c.y + dy
				if x < 0 or y < 0 or x >= w or y >= h:
					continue
				var fall := 1.0 / (1.0 + dx * dx + dy * dy)
				var i := y * w + x
				if is_green:
					green[i] = minf(4.0, green[i] + amount * fall)
				else:
					orange[i] = minf(4.0, orange[i] + amount * fall)

	func tick(dt: float) -> void:
		var d: float = float(cfg.get("diffuse", 0.16)) * dt * 5.0
		var decay: float = float(cfg.get("decay", 0.012)) * dt * 5.0
		var contest: float = float(cfg.get("contest", 1.35)) * dt * 5.0
		var e_rate: float = float(cfg.get("entrench_rate", 0.025)) * dt * 5.0
		var e_max: float = float(cfg.get("entrench_max", 2.5))
		var e_decay: float = float(cfg.get("entrench_decay", 0.08)) * dt * 5.0
		var g0 := green.duplicate()
		var o0 := orange.duplicate()
		for y in h:
			var row := y * w
			for x in w:
				var i := row + x
				var gl := g0[i - 1] if x > 0 else g0[i]
				var gr := g0[i + 1] if x < w - 1 else g0[i]
				var gu := g0[i - w] if y > 0 else g0[i]
				var gd := g0[i + w] if y < h - 1 else g0[i]
				var ol := o0[i - 1] if x > 0 else o0[i]
				var orr := o0[i + 1] if x < w - 1 else o0[i]
				var ou := o0[i - w] if y > 0 else o0[i]
				var od := o0[i + w] if y < h - 1 else o0[i]

				var e := entrench[i]
				# entrenchment multiplies how fast the entrenched side flows/grows here
				var g_mult := 1.0 + maxf(0.0, e)
				var o_mult := 1.0 + maxf(0.0, -e)
				var g := g0[i] + d * g_mult * ((gl + gr + gu + gd) * 0.25 - g0[i])
				var o := o0[i] + d * o_mult * ((ol + orr + ou + od) * 0.25 - o0[i])
				g *= 1.0 - decay
				o *= 1.0 - decay
				# contest: opposing influence annihilates
				var clash := minf(g, o) * contest
				g -= clash
				o -= clash
				# entrenchment: dominance deepens, opposition erodes it first
				var dom := g - o
				if dom > 0.05:
					e = minf(e_max, e + e_rate * minf(1.0, dom)) if e >= 0.0 else e + e_rate * 2.0
				elif dom < -0.05:
					e = maxf(-e_max, e - e_rate * minf(1.0, -dom)) if e <= 0.0 else e - e_rate * 2.0
				else:
					e = lerpf(e, 0.0, e_decay)
				green[i] = clampf(g, 0.0, 4.0)
				orange[i] = clampf(o, 0.0, 4.0)
				entrench[i] = e


## Records the inject/tick calls it sees, then behaves as the field.
class Recorder extends InfluenceField:
	var calls: Array = []

	func inject(pos: Vector2, is_green: bool, amount: float, radius := 1) -> void:
		calls.append([pos, is_green, amount, radius])
		super.inject(pos, is_green, amount, radius)

	func tick(dt: float) -> void:
		calls.append([dt])
		super.tick(dt)


func run() -> int:
	var t := TestUtil.new()
	t.suite("field_slicing")
	var realm_field: Dictionary = TestUtil.configs()["realm"]["field"]
	t.ok(int(realm_field.get("lag_ticks", 0)) >= int(realm_field.get("max_ticks_per_step", 1)),
		"lag_ticks covers one substep's run of field ticks (%s >= %s)" % [realm_field.get("lag_ticks"), realm_field.get("max_ticks_per_step")])
	_against_e1(t)
	_cap(t)
	_prewarm(t)
	_game_state(t)
	_fixture(t)
	return t.failures


## A small field (fast) with the real constants.
func _small_cfg(lag: int) -> Dictionary:
	var cfg: Dictionary = TestUtil.configs()["realm"]["field"].duplicate(true)
	cfg["w"] = 24
	cfg["h"] = 16
	cfg["lag_ticks"] = lag
	return cfg


## A seeded script: frames of injects (saturating, repeated on one cell, every radius), advance
## points between them, ticks of uneven dt, and a flush with injects still open before it.
func _script(seed: int, ticks: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var out: Array = []
	var last := Vector2(500, 500)
	for j in range(1, ticks + 1):
		for f in rng.randi_range(0, 4):
			for k in rng.randi_range(0, 2):
				var pos := last if rng.randf() < 0.25 else Vector2(rng.randf_range(-50, 2100), rng.randf_range(-50, 1500))
				last = pos
				var amount := rng.randf_range(3.0, 6.0) if rng.randf() < 0.2 else rng.randf_range(0.0, 1.5)
				out.append(["inject", pos, rng.randf() < 0.55, amount, rng.randi_range(0, 3)])
			out.append(["frame"])
		out.append(["tick", [0.2, 0.2, 0.2, 0.1, 0.35][rng.randi_range(0, 4)]])
		if j * 2 == ticks:
			out.append(["inject", last, true, 0.7, 1])
			out.append(["flush"])
	return out


## Every schedule, at lag 1 and 2, against E1: after each tick n (and each flush) the live arrays
## equal E1's field after tick p plus every inject made after it, p = max(n - lag, last flush).
func _against_e1(t: TestUtil) -> void:
	var steps := _script(11, 40)
	var schedules := {"advance(0) per frame": 0, "advance(1)": 1, "advance(37)": 37,
		"advance(100), across job ends": 100, "unbounded": UNBOUNDED, "never advanced (ticks compute)": -1}
	for lag in [1, 2]:
		for name in schedules:
			var budget: int = schedules[name]
			var cfg := _small_cfg(lag)
			var f := InfluenceField.new()
			f.setup(cfg, Vector2(2048, 1440))
			var e1 := E1Field.new()
			e1.setup(cfg, Vector2(2048, 1440))
			var snaps: Array = [e1.copy()]  # E1 after tick n
			var injects: Array = []  # [made after tick n, inject]
			var n := 0
			var flushed_at := 0
			var checks := 0
			var bad: Array = []
			for s in steps:
				match s[0]:
					"inject":
						f.inject(s[1], s[2], s[3], s[4])
						e1.inject(s[1], s[2], s[3], s[4])
						injects.append([n, s])
					"frame":
						if budget >= 0:
							var live := [f.green.duplicate(), f.orange.duplicate(), f.entrench.duplicate()]
							f.advance(budget)
							if [f.green, f.orange, f.entrench] != live:
								bad.append("advance() changed the live arrays after tick %d" % n)
					"tick", "flush":
						if s[0] == "tick":
							n += 1
							f.tick(s[1])
							e1.tick(s[1])
							snaps.append(e1.copy())
						else:
							f.flush()
							flushed_at = n
							if f.in_flight() != 0:
								bad.append("flush left %d ticks in flight" % f.in_flight())
						var p := maxi(n - lag, flushed_at)
						var want: E1Field = snaps[p].copy()
						for r in injects:
							if r[0] >= p:
								want.inject(r[1][1], r[1][2], r[1][3], r[1][4])
						checks += 1
						if f.green != want.green or f.orange != want.orange or f.entrench != want.entrench:
							bad.append("%s %d: live != E1 after tick %d + injects since" % [s[0], n, p])
			t.ok(bad.is_empty() and checks == 41,
				"lag %d, %s: live == E1 as of lag ticks ago + injects since, bit for bit, at all %d tick/flush boundaries %s"
				% [lag, name, checks, str(bad.slice(0, 3))])


## advance(b) computes exactly min(b, queued) cells, across job ends, and never touches the live arrays.
func _cap(t: TestUtil) -> void:
	var f := InfluenceField.new()
	f.setup(_small_cfg(2), Vector2(2048, 1440))
	var cells := 24 * 16
	f.inject(Vector2(400, 400), true, 1.0, 2)
	f.tick(0.2)
	f.inject(Vector2(1600, 1000), false, 1.0, 2)
	f.tick(0.2)
	var live := [f.green.duplicate(), f.orange.duplicate(), f.entrench.duplicate()]
	t.ok(f.queued_cells() == 2 * cells and f.in_flight() == 2, "two ticks queue two jobs, nothing published at lag 2")
	var ok := true
	var log: Array = []
	for b in [1, 37, 100, 500, 1000, 5]:
		var before := f.queued_cells()
		f.advance(b)
		log.append("%d->%d" % [b, f.last_advance_cells])
		ok = ok and f.last_advance_cells == mini(b, before) and f.queued_cells() == before - f.last_advance_cells
	t.ok(ok, "advance(b) computes exactly min(b, queued) cells, across a job's end (%s)" % ", ".join(log))
	t.ok([f.green, f.orange, f.entrench] == live, "advance() never changes the live arrays")
	f.tick(0.2)
	t.ok(f.in_flight() == 2 and f.queued_cells() == cells, "the next tick publishes the first result and queues one job")
	f.advance(0)
	t.ok(f.last_advance_cells == cells and f.queued_cells() == 0, "advance(0) computes all queued work")
	f.advance(0)
	t.ok(f.last_advance_cells == 0, "advance() with nothing queued computes nothing")
	f.flush()
	t.ok(f.in_flight() == 0 and f.queued_cells() == 0, "flush() leaves nothing in flight")


## GameState's pre-warm, flushed, is E1's pre-warm bit for bit: a new game's field doesn't move.
func _prewarm(t: TestUtil) -> void:
	var gs := GameState.new(TestUtil.configs())
	gs.cmd_new_game(1)
	var rec := Recorder.new()
	var cfg: Dictionary = gs._cfg().get("field", {})
	rec.setup(cfg, Vector2(2048, 1440))
	gs.field = rec
	gs._prewarm_field()
	var e1 := E1Field.new()
	e1.setup(cfg, Vector2(2048, 1440))
	var ticks := 0
	for c in rec.calls:
		if c.size() == 1:
			e1.tick(c[0])
			ticks += 1
		else:
			e1.inject(c[0], c[1], c[2], c[3])
	t.ok(ticks == 90 and rec.in_flight() == 0, "the pre-warm runs 90 ticks and flushes them all")
	t.ok(rec.green == e1.green and rec.orange == e1.orange and rec.entrench == e1.entrench,
		"the flushed pre-warm equals E1's 90-tick pre-warm bit for bit")


## Field arrays and village owners at a substep boundary (the only points sim code can read them:
## nothing reads the field between the field ticks of one substep).
func _digest(gs: GameState) -> String:
	var f: InfluenceField = gs.view_field()["field"]
	var owners: Array = []
	for v in gs.view_villages()["villages"]:
		owners.append(v["owner"])
	return "%d/%d/%d/%s" % [hash(f.green.to_byte_array()), hash(f.orange.to_byte_array()),
		hash(f.entrench.to_byte_array()), ",".join(owners)]


## Runs a new game (or a fixture) for `substeps` substeps at a frame cadence; returns
## {substeps done: digest} at every substep boundary the cadence lands on.
func _run(budget: int, lag: int, cadence: Callable, substeps: int, fixture := "") -> Dictionary:
	var cfgs := TestUtil.configs()
	cfgs["realm"]["field"]["slice_budget_cells"] = budget
	cfgs["realm"]["field"]["lag_ticks"] = lag
	var gs := GameState.new(cfgs)
	if fixture != "":
		gs.debug_enabled = true
		gs.cmd_debug_load_fixture(fixture)
	else:
		gs.cmd_new_game(7)
	var out := {0: _digest(gs)}
	var done := 0
	var frame := 0
	while done < substeps:
		var n := gs.tick(cadence.call(frame))
		frame += 1
		if n > 0:
			done += n
			out[done] = _digest(gs)
	return out


## Every recorded boundary of `b` matches `a`; returns the count compared, -1 on a mismatch.
func _same(a: Dictionary, b: Dictionary) -> int:
	var n := 0
	for k in b:
		if not a.has(k):
			continue
		if a[k] != b[k]:
			return -1
		n += 1
	return n


## Budgets × cadences, lag 2 and lag 1: identical field arrays and village owners at every substep.
func _game_state(t: TestUtil) -> void:
	var subs := 24
	var f64 := func(_i: int) -> float: return 1.0 / 64.0
	var f16 := func(_i: int) -> float: return 1.0 / 16.0
	var half := func(_i: int) -> float: return 0.5
	var big := func(_i: int) -> float: return 2.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var odd: Array = []
	for i in 4000:
		odd.append(rng.randi_range(1, 40) / 64.0)  # binary-exact, 1/64 .. 0.625 s
	var irregular := func(i: int) -> float: return odd[i % odd.size()]
	var ref := _run(0, 2, f64, subs)
	var runs := [
		["budget 1 at 1/64 s", _run(1, 2, f64, subs)],
		["budget 1400 at 1/64 s", _run(1400, 2, f64, subs)],
		["unbounded at 1/64 s", _run(UNBOUNDED, 2, f64, subs)],
		["budget 1400 at 1/16 s", _run(1400, 2, f16, subs)],
		["budget 1400 at 0.5 s (a substep a call)", _run(1400, 2, half, subs)],
		["budget 0 at 2 s (4 substeps a call)", _run(0, 2, big, subs)],
		["budget 1 at irregular frames", _run(1, 2, irregular, subs)],
	]
	for r in runs:
		var n := _same(ref, r[1])
		t.ok(n >= 7, "lag 2, %s == budget 0 at 1/64 s: field arrays and village owners at every substep (%d compared)" % [r[0], n])
	var ref1 := _run(0, 1, f64, subs)
	var n1 := _same(ref1, _run(1400, 1, irregular, subs))
	t.ok(n1 >= 7, "lag 1, budget 1400 at irregular frames == budget 0 at 1/64 s (%d compared)" % n1)
	t.ok(ref1[subs] != ref[subs], "the lag is gameplay, the budget is not: lag 1 and lag 2 differ")


## A pre-warmed fixture load: identical at budget 0 and 1400 after flush(), and on from there.
func _fixture(t: TestUtil) -> void:
	var gs := GameState.new(TestUtil.configs())
	gs.debug_enabled = true
	gs.cmd_debug_load_fixture("midgame_2flips")
	var f: InfluenceField = gs.view_field()["field"]
	t.ok(f.in_flight() == 0 and f.queued_cells() == 0, "a fixture load leaves nothing in flight (flushed after the pre-warm)")
	var f64 := func(_i: int) -> float: return 1.0 / 64.0
	var a := _run(0, 2, f64, 12, "midgame_2flips")
	var b := _run(1400, 2, f64, 12, "midgame_2flips")
	t.ok(a[0] == b[0], "the pre-warmed fixture load is identical at budget 0 and 1400")
	var n := _same(a, b)
	t.ok(n == 13, "and stays identical at every substep after it (%d compared)" % n)
