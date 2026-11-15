extends RefCounted
## Catch-up's field step against live ticks (IDLE §4; run with tests/run.sh --slow
## --only=field_catchup_bench; about 12 min on jenova).
## The field step count is the shipped one: `idle.field_steps` and `idle.field_step_min_s` from
## configs/economy.json (no defaults: a missing key fails), so a step is 12 h / field_steps.
## - Cost: a 12 h catch-up's field_steps field steps (12 h / field_steps each) on the shipped 128 x 90 grid, from a
##   contested field, as total ms, per-call µs and a ratio to a live tick timed in the same run
##   (wall-clock bounds are loose: they flake under load).
## - Owners: FieldScenario "jumps" (contested, forts changing hands) over 12 h, villages sampled every
##   field step, three ways from the same pre-warmed field:
##     live:     a live 0.2 s tick every period, sources refreshed every second;
##     exact:    the same field steps, each as step / 0.2 s live ticks with the step's sources held;
##     catch-up: the same field steps, one catchup_step(step) each.
##   The acceptance (agreed with the manager): catch-up matches exact in >= 99% of village samples
##   and in green villages at the end; against live is reported beside it (a field step can't place
##   an owner change finer than its own length). Also reported: the share left after dropping
##   samples within 0.01 of the threshold (IDLE §4's accuracy fixtures aren't within a hair of one).
## - Also printed: the field's cost of a whole catch-up over elapsed times from 30 s to 7 d, at
##   field_steps calls and with field steps of at least field_step_min_s, and a step on midgame_2flips' own field.
## Environment, for one-off runs: FIELD_CATCHUP_KINDS=jumps,drift,mixed picks scenarios (only jumps
## asserts; none skips the owners); FIELD_CATCHUP_FULL=1 runs them on the shipped grid instead of the 64 x 45 crop (about
## 40 min per scenario).

const HOURS := 12.0
const PERIOD := 0.2
const HAIR := 0.01


func run() -> int:
	var t := TestUtil.new()
	t.suite("field_catchup_bench")
	var cfg: Dictionary = TestUtil.configs()["realm"]["field"]
	var th := float(cfg["town_threshold"])
	var idle: Dictionary = TestUtil.configs()["economy"]["idle"]
	var steps := int(idle["field_steps"])  # economy's most calls, and the 12 h catch-up's step count
	var min_step_s := float(idle["field_step_min_s"])  # the shortest field step economy should send (dt > catchup_exact_ticks / tick_hz)
	var step_s := HOURS * 3600.0 / steps
	var per := int(round(step_s / PERIOD))
	if absf(per * PERIOD - step_s) > 1e-6:
		t.ok(false, "a field step of %.4f s (12 h / idle.field_steps %d) must be a whole number of %.1f s live ticks" % [step_s, steps, PERIOD])
		return t.failures

	# cost, on the shipped grid
	var sc := FieldScenario.make("jumps")
	var f := sc.prewarmed(cfg)
	for i in per:
		sc.inject(f, 0.0, PERIOD)
		f.tick(PERIOD)
	f.flush()
	var live_us: Array = []
	for r in 15:
		sc.inject(f, 0.0, PERIOD)
		f.tick(PERIOD)
		var t0 := Time.get_ticks_usec()
		f.advance(0)
		live_us.append(Time.get_ticks_usec() - t0)
	f.flush()
	live_us.sort()
	var call_us: Array = []
	var cells := 0
	var total := 0
	for s in steps:
		sc.inject(f, step_s * (s + 1), PERIOD)
		var t0 := Time.get_ticks_usec()
		f.catchup_step(step_s)
		var us := Time.get_ticks_usec() - t0
		call_us.append(us)
		total += us
		cells += f.last_catchup_cells
	var sorted := call_us.duplicate()
	sorted.sort()
	var med: int = sorted[int(sorted.size() * 0.5)]
	var ratio := float(med) / float(live_us[7])
	print("  [field_catchup_bench] cost, shipped grid, %d steps of %.0f s (12 h): total %.0f ms; per call median %d µs, max %d µs; %.2f grids of cells per call; live tick median %d µs -> %.2f live ticks per call" % [
		steps, step_s, total / 1000.0, med, sorted[-1], float(cells) / steps / (f.w * f.h), live_us[7], ratio])
	t.ok(ratio <= 2.0, "a %.0f s field step costs about one live tick (%.2f; loose bound <= 2)" % [step_s, ratio])
	t.ok(total <= 3e6, "a 12 h catch-up's field steps take %.2f s (loose bound <= 3 s)" % (total / 1e6))
	# the field's cost over a catch-up's elapsed time E: field_steps calls at E / field_steps, and with field steps of
	# at least min_step_s (fewer calls for short gaps; steps up to catchup_exact_ticks ticks cost them)
	var rows: Array = ["  [field_catchup_bench] field cost of a catch-up of E, shipped grid, from the field above:",
		"  | E | %d calls: dt, total ms | dt >= %.0f s: calls, dt, total ms |" % [steps, min_step_s], "  |---|---|---|"]
	var worst := 0.0
	for e_s in [30.0, 60.0, 240.0, 600.0, 7200.0, 43200.0, 604800.0]:
		var a_ms := _cost(f, sc, e_s, steps) / 1000.0
		var calls := mini(steps, maxi(1, int(e_s / min_step_s)))
		var b_ms := _cost(f, sc, e_s, calls) / 1000.0
		worst = maxf(worst, b_ms)
		rows.append("  | %s | %.2f s, %.0f | %d, %.1f s, %.0f |" % [_dur(e_s), e_s / steps, a_ms, calls, e_s / calls, b_ms])
	print("\n".join(PackedStringArray(rows)))
	t.ok(worst <= 3000.0, "with field steps >= %.0f s no catch-up's field takes over 3 s (worst %.0f ms; loose)" % [min_step_s, worst])
	# the real game's field: midgame_2flips, its own sources (GameState._inject_sources)
	var gs := GameState.new(TestUtil.configs())
	gs.debug_enabled = true
	gs.cmd_debug_load_fixture("midgame_2flips")
	var real_us: Array = []
	var real_cells := 0
	for k in 20:
		gs._inject_sources(PERIOD)
		var t0 := Time.get_ticks_usec()
		gs.field.catchup_step(step_s)
		real_us.append(Time.get_ticks_usec() - t0)
		real_cells += gs.field.last_catchup_cells
	real_us.sort()
	print("  [field_catchup_bench] midgame_2flips' own field and sources, 20 steps of %.0f s: median %d µs (%.2f live ticks), %.2f grids of cells per call" % [
		step_s, real_us[10], float(real_us[10]) / float(live_us[7]), float(real_cells) / 20.0 / (gs.field.w * gs.field.h)])

	var kinds := OS.get_environment("FIELD_CATCHUP_KINDS")
	var full := OS.get_environment("FIELD_CATCHUP_FULL") == "1"
	for kind in (kinds.split(",") if kinds != "" else PackedStringArray(["jumps"])):
		if kind == "none":
			continue
		var r := _owners(kind, not full, cfg, th, steps, per, step_s)
		var lines: Array = ["  [field_catchup_bench] owners, %s on the %s grid, 12 h, %d villages every %.0f s (%d samples)" % [
			kind, "shipped 128 x 90" if full else "64 x 45 cropped", r["villages"], step_s, r["samples"]],
			"    live owners: %.0f%% green, %.0f%% orange, %.0f%% none; %d owner changes; %.1f%% of samples within %.2f of the threshold" % [
				r["share"][0], r["share"][1], r["share"][2], r["changes"], r["hair"], HAIR],
			"    catch-up vs exact %.2f%% (%.2f%% without those) | vs live %.2f%% | exact vs live %.2f%%" % [
				r["cu_exact"], r["cu_exact_clear"], r["cu_live"], r["exact_live"]],
			"    |dominance - exact| at villages: p99 %.3f, max %.3f; green villages at the end: catch-up %d, exact %d, live %d; non-finite %d" % [
				r["p99"], r["max"], r["green"][0], r["green"][1], r["green"][2], r["nan"]]]
		print("\n".join(PackedStringArray(lines)))
		if kind == "jumps":
			t.ok(r["cu_exact"] >= 99.0, "jumps: catch-up villages match exact live ticks in >= 99%% of samples (%.2f%%)" % r["cu_exact"])
			t.ok(r["green"][0] == r["green"][1], "jumps: green villages at the end match (%d)" % r["green"][0])
		t.ok(r["nan"] == 0, "%s: catch-up stays finite" % kind)
	return t.failures


## µs for `calls` field steps covering e_s seconds, from a copy of f's state, sources injected per call.
func _cost(f: InfluenceField, sc: FieldScenario, e_s: float, calls: int) -> int:
	var c := InfluenceField.new()
	c.setup(f.cfg, f.world_size)
	c.green = f.green.duplicate()
	c.orange = f.orange.duplicate()
	c.entrench = f.entrench.duplicate()
	c._head = [f.green.duplicate(), f.orange.duplicate(), f.entrench.duplicate()]
	var dt := e_s / calls
	var us := 0
	for k in calls:
		sc.inject(c, 43200.0 + dt * (k + 1), PERIOD)
		var t0 := Time.get_ticks_usec()
		c.catchup_step(dt)
		us += Time.get_ticks_usec() - t0
	return us


static func _dur(s: float) -> String:
	if s >= 86400.0:
		return "%.0f d" % (s / 86400.0)
	if s >= 3600.0:
		return "%.0f h" % (s / 3600.0)
	if s >= 60.0:
		return "%.0f min" % (s / 60.0)
	return "%.0f s" % s


func _owners(kind: String, crop: bool, cfg: Dictionary, th: float, steps: int, per: int, step_s: float) -> Dictionary:
	var sc := FieldScenario.make(kind, crop)
	var d_live: Array = []
	var d_exact: Array = []
	var d_cu: Array = []
	var nan := 0
	var lf := sc.prewarmed(cfg)
	for i in steps * per:
		sc.inject(lf, (i - i % 5) * PERIOD, PERIOD)  # sources refreshed every second
		lf.tick(PERIOD)
		if (i + 1) % per == 0:
			lf.flush()
			d_live.append(sc.doms(lf))
	var xf := sc.prewarmed(cfg)
	var cf := sc.prewarmed(cfg)
	for s in steps:
		var ts := step_s * (s + 1)
		for k in per:
			sc.inject(xf, ts, PERIOD)
			xf.tick(PERIOD)
		xf.flush()
		d_exact.append(sc.doms(xf))
		sc.inject(cf, ts, PERIOD)
		cf.catchup_step(step_s)
		var dc := sc.doms(cf)
		for v in dc:
			if not is_finite(v):
				nan += 1
		d_cu.append(dc)
	var same := [0, 0, 0]
	var clear := 0
	var clear_same := 0
	var hair := 0
	var errs: Array = []
	var share := [0, 0, 0]
	var changes := 0
	var all := 0
	var prev: Array = []
	for s in steps:
		var ol := FieldScenario.owners(d_live[s], th)
		var ox := FieldScenario.owners(d_exact[s], th)
		var oc := FieldScenario.owners(d_cu[s], th)
		for v in ol.size():
			all += 1
			same[0] += int(oc[v] == ox[v])
			same[1] += int(oc[v] == ol[v])
			same[2] += int(ox[v] == ol[v])
			share[0 if ol[v] == 1 else (1 if ol[v] == -1 else 2)] += 1
			errs.append(absf(float(d_cu[s][v]) - float(d_exact[s][v])))
			if absf(absf(float(d_exact[s][v])) - th) < HAIR:
				hair += 1
			else:
				clear += 1
				clear_same += int(oc[v] == ox[v])
			if not prev.is_empty() and prev[v] != ol[v]:
				changes += 1
		prev = ol
	errs.sort()
	var green := func(d: Array) -> int: return FieldScenario.owners(d, th).count(1)
	return {"villages": sc.villages.size(), "samples": all, "nan": nan, "changes": changes,
		"share": share.map(func(x): return 100.0 * x / all), "hair": 100.0 * hair / all,
		"cu_exact": 100.0 * same[0] / all, "cu_live": 100.0 * same[1] / all, "exact_live": 100.0 * same[2] / all,
		"cu_exact_clear": 100.0 * clear_same / maxi(1, clear), "p99": errs[int(errs.size() * 0.99)], "max": errs[-1],
		"green": [green.call(d_cu[-1]), green.call(d_exact[-1]), green.call(d_live[-1])]}
