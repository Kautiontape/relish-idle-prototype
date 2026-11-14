extends RefCounted
## Catch-up's field step against live ticks (IDLE §4; run with tests/run.sh --slow
## --only=field_catchup_bench; about 12 min on jenova).
## - Cost: a 12 h catch-up's 144 field steps (300 s each) on the shipped 128 x 90 grid, from a
##   contested field, as total ms, per-call µs and a ratio to a live tick timed in the same run
##   (wall-clock bounds are loose: they flake under load).
## - Owners: FieldScenario "jumps" (contested, forts changing hands) over 12 h, villages sampled every
##   300 s, three ways from the same pre-warmed field:
##     live:     a live 0.2 s tick every period, sources refreshed every second;
##     exact:    the same 144 field steps, each as 1500 live ticks with the step's sources held;
##     catch-up: the same 144 field steps, one catchup_step(300) each.
##   The acceptance (agreed with the manager): catch-up matches exact in >= 99% of village samples
##   and in green villages at the end; against live is reported beside it (a field step can't place
##   an owner change finer than its own length). Also reported: the share left after dropping
##   samples within 0.01 of the threshold (IDLE §4's accuracy fixtures aren't within a hair of one).
## Environment, for one-off runs: FIELD_CATCHUP_KINDS=jumps,drift,mixed picks scenarios (only jumps
## asserts); FIELD_CATCHUP_FULL=1 runs them on the shipped grid instead of the 64 x 45 crop (about
## 40 min per scenario).

const HOURS := 12.0
const STEP_S := 300.0
const PERIOD := 0.2
const HAIR := 0.01


func run() -> int:
	var t := TestUtil.new()
	t.suite("field_catchup_bench")
	var cfg: Dictionary = TestUtil.configs()["realm"]["field"]
	var th := float(cfg["town_threshold"])
	var steps := int(HOURS * 3600.0 / STEP_S)
	var per := int(round(STEP_S / PERIOD))

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
		sc.inject(f, STEP_S * (s + 1), PERIOD)
		var t0 := Time.get_ticks_usec()
		f.catchup_step(STEP_S)
		var us := Time.get_ticks_usec() - t0
		call_us.append(us)
		total += us
		cells += f.last_catchup_cells
	var sorted := call_us.duplicate()
	sorted.sort()
	var med: int = sorted[int(sorted.size() * 0.5)]
	var ratio := float(med) / float(live_us[7])
	print("  [field_catchup_bench] cost, shipped grid, %d steps of %.0f s (12 h): total %.0f ms; per call median %d µs, max %d µs; %.2f grids of cells per call; live tick median %d µs -> %.2f live ticks per call" % [
		steps, STEP_S, total / 1000.0, med, sorted[-1], float(cells) / steps / (f.w * f.h), live_us[7], ratio])
	t.ok(ratio <= 2.0, "a 300 s field step costs about one live tick (%.2f; loose bound <= 2)" % ratio)
	t.ok(total <= 3e6, "a 12 h catch-up's field steps take %.2f s (loose bound <= 3 s)" % (total / 1e6))

	var kinds := OS.get_environment("FIELD_CATCHUP_KINDS")
	var full := OS.get_environment("FIELD_CATCHUP_FULL") == "1"
	for kind in (kinds.split(",") if kinds != "" else PackedStringArray(["jumps"])):
		var r := _owners(kind, not full, cfg, th, steps, per)
		var lines: Array = ["  [field_catchup_bench] owners, %s on the %s grid, 12 h, %d villages every %.0f s (%d samples)" % [
			kind, "shipped 128 x 90" if full else "64 x 45 cropped", r["villages"], STEP_S, r["samples"]],
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


func _owners(kind: String, crop: bool, cfg: Dictionary, th: float, steps: int, per: int) -> Dictionary:
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
		var ts := STEP_S * (s + 1)
		for k in per:
			sc.inject(xf, ts, PERIOD)
			xf.tick(PERIOD)
		xf.flush()
		d_exact.append(sc.doms(xf))
		sc.inject(cf, ts, PERIOD)
		cf.catchup_step(STEP_S)
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
