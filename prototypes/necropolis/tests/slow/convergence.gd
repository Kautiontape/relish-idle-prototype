extends RefCounted
## The step function's convergence (E2b T3.0, IDLE §4): how far GameState._core_step(dt) drifts from
## a 0.5 s reference over 12 h with no input, and what a core step costs. Run with
## tests/run.sh --slow --only=convergence (several minutes); tests/test_convergence_1h.gd runs a 1 h,
## two-dt version of the same measure() in the default suite. The field-cap measurement is
## tests/slow/field_cap.gd.
##
## - Start states: midgame_2flips, pre_vei, and `fresh` (cmd_new_game(1) run 10 min live: no flip, so
##   no tithe and no hold; nothing at a cap yet, though its body store fills within the hour).
## - Each start is saved once to JSON and every run loads that same JSON into a fresh GameState, so
##   every run starts bit-identical.
## - Only _core_step runs: the influence field is never ticked, so village owners stay as the start
##   left them in every run (the field is frozen identically; only integrator error shows). The
##   configs are copied in memory with the field shrunk and its pre-warm off (nothing core reads it).
## - Samples every SAMPLE_S (a multiple of every dt). A metric's error is the worst over the samples
##   of |x − ref| / max(|ref|, floor): a quantity pinned near 0 is judged against its natural scale.
##   The floor is the body cap for bodies, Vei's pool cap for her pool, 1% of Σ fort caps for the
##   forts' pools, and 1% of the metric's peak |ref| (at least 1) for the rest.
## - The 0.25 s row is the reference's own noise: no dt can be expected to match 0.5 s closer.
## - `clip`: steps are shortened so none straddles an event IDLE §4 clips at: a tithe warning, a
##   wave's start or end, a hold's end, a building's unpaid hold ending, gold or bone reaching their
##   floor (projected from the last step's net), and Relish arriving. Without it the table measures
##   event timing (a hold's end and Relish's arrival land up to one dt late; since T3.0m a wave's
##   start and end are exact inside a step, spread over it), not the integrator. A garrison
##   reaching 0 is not clipped: the fort step solves it inside the step.
## - Outcomes (E2b T4.C, outcome_table()): beside the stocks, what a catch-up must get right: the
##   flips, retakes and tithe waves (fort and time), the buildings finished and the upkeep's
##   unpaid/resumed switches (lot and time), the tier, and at the end which forts are held and
##   which hold living. Each against the reference: "=" when the same come in the same order, with
##   the worst time difference.
## - Cost: a run's µs per core step is its median 10-min chunk. The cost table and the projections
##   use the best of RUNS separate 1 h runs per start and dt (timing()), with the load average read
##   beside each; the error table's µs column is the accuracy run's own (one run, loaded). Wall clock
##   is never asserted. The projections add the field: FIELD_TICKS full ticks per catch-up at the
##   best-of-RUNS cost of one. tests/slow/step_cost.gd runs the cost table alone.

const STARTS := ["midgame_2flips", "pre_vei", "fresh"]
const DTS := [0.5, 0.25, 2.0, 5.0, 10.0, 15.0, 30.0]
const HOURS := 12.0
const SAMPLE_S := 600.0
const FRESH_S := 600.0
## IDLE §4's budget, wall seconds (on jenova).
const BUDGET_12H_S := 2.0
const BUDGET_7D_S := 10.0
## The field ticks a catch-up spends (the brief's ≈100–200), held fixed whatever the length.
const FIELD_TICKS := 150
## The cost runs (timing()): best of RUNS runs of TIMING_H each, since wall clock flakes under load.
const RUNS := 3
const TIMING_H := 1.0
## The integrator's share of IDLE's 2% (event clipping and the capped field spend the rest).
const TOL := 0.005
const METRICS := ["backlog", "vei_dead", "vei_pool", "fort_living", "fort_undead", "fort_dead", "workers",
	"bodies", "gold", "bone", "living"]
## Vei's stocks and Covington's smooth ones: the secondary criterion (the fort pools and bodies
## converge as dt → 0 since E2b T4.C on midgame_2flips, and on pre_vei until its gold floor; fresh's,
## and pre_vei's after the floor, within about one convoy load; at long steps they are still far
## off: IDLE §4, tests/slow/convergence_fine.gd).
const KEY := ["backlog", "vei_dead", "vei_pool", "workers", "gold", "bone", "living"]
const SHORT := {"backlog": "backlog", "vei_dead": "vei dead", "vei_pool": "vei pool", "fort_living": "Σliving",
	"fort_undead": "Σundead", "fort_dead": "Σdead", "workers": "workers", "bodies": "bodies", "gold": "gold",
	"bone": "bone", "living": "town living"}

var t := TestUtil.new()
var _cfgs := {}
var _field_us := -1.0


func run() -> int:
	t.suite("convergence")
	print("  [convergence] load average: %s" % _loadavg())
	var res := measure(STARTS, HOURS, DTS, true)
	print(table(res, HOURS))
	print(outcome_table(res, HOURS))
	var unclipped := measure(STARTS, HOURS, [0.5, 15.0, 30.0], false)
	print(table(unclipped, HOURS, "no event clipping (hold ends and Relish's arrival land up to one dt late; a wave starts and ends at its time, spread over its steps)"))
	check(res)
	print(attribution())
	var cost := timing(STARTS, DTS)
	print(cost_table(cost))
	print(recommend(res, cost))
	print(fallback(res, cost))
	return t.failures


## The cost, best of RUNS: each start at each dt runs TIMING_H of core steps RUNS times; a run's
## cost is its median 10-min chunk, and the best (lowest) run is kept, with the load average read
## beside it. The field's tick is taken the same way. {start: {dt: [µs, loadavg]}, "field": [µs, loadavg]}.
func timing(starts: Array, dts: Array) -> Dictionary:
	var out := {}
	for st in starts:
		var js := start_json(st)
		var per := {}
		for dt in dts:
			var best := [INF, ""]
			for i in RUNS:
				var r := run_one(load_state(js), dt, TIMING_H * 3600.0, true)
				if float(r["us_per_step"]) < float(best[0]):
					best = [float(r["us_per_step"]), _loadavg()]
			per[dt] = best
		out[st] = per
	var fbest := [INF, ""]
	for i in RUNS:
		_field_us = -1.0
		var us := field_tick_us()
		if us < float(fbest[0]):
			fbest = [us, _loadavg()]
	_field_us = float(fbest[0])
	out["field"] = fbest
	return out


func cost_table(cost: Dictionary) -> String:
	var lines: Array = ["  [convergence] cost, best of %d runs of %.0f h each (µs per core step; load average at the best run)" % [RUNS, TIMING_H],
		"  | start | dt s | µs/step | 12 h s | 7 d s | load average |", "  |---|---|---|---|---|---|"]
	for st in cost:
		if st == "field":
			continue
		for dt in cost[st]:
			var us := float(cost[st][dt][0])
			var p := projection(us, dt)
			lines.append("  | %s | %s | %.0f | %.2f | %.1f | %s |" % [st, str(dt), us, p[0], p[1], cost[st][dt][1]])
	lines.append("  field: one full tick %.0f µs (best of %d medians; load %s); the projections add %d ticks" % [
		float(cost["field"][0]), RUNS, cost["field"][1], FIELD_TICKS])
	return "\n".join(PackedStringArray(lines))


static func _loadavg() -> String:
	var f := FileAccess.open("/proc/loadavg", FileAccess.READ)
	return f.get_line() if f != null else "n/a"


## The harness configs: the shipped configs with the field shrunk and its pre-warm off, in memory.
func cfgs() -> Dictionary:
	if _cfgs.is_empty():
		_cfgs = TestUtil.configs()
		var fld: Dictionary = _cfgs["realm"]["field"]
		fld["w"] = 8
		fld["h"] = 6
		_cfgs["economy"]["sim"]["prewarm_ticks"] = 0
	return _cfgs


## A start state as save JSON, built with the shipped configs (a real field decides `fresh`'s owners).
func start_json(start: String) -> String:
	var s := GameState.new(TestUtil.configs())
	s.debug_enabled = true
	if start == "fresh":
		s.cmd_new_game(1)
		s.tick(FRESH_S)
	else:
		t.ok(s.cmd_debug_load_fixture(start)["ok"], "%s loads" % start)
	return JSON.stringify(s.to_dict())


func load_state(json: String) -> GameState:
	var s := GameState.new(cfgs())
	s.debug_enabled = true
	var r := s.from_dict(JSON.parse_string(json))
	t.ok(r["ok"], "the start state loads (%s)" % str(r.get("reason", "")))
	return s


static func sample(s: GameState) -> Dictionary:
	var d := {"backlog": float(s.realm.vei["undead_queue"]), "vei_dead": float(s.realm.vei["dead_queue"]),
		"vei_pool": float(s.realm.vei["living_pool"]), "fort_living": 0.0, "fort_undead": 0.0, "fort_dead": 0.0,
		"workers": s.town_sim.workers, "bodies": s.town_sim.bodies, "gold": s.town_sim.gold, "bone": s.town_sim.bone,
		"living": s.town_sim.living}
	for f in s.realm.forts:
		d["fort_living"] += float(f["living"])
		d["fort_undead"] += float(f["undead"])
		d["fort_dead"] += float(f["dead"])
	return d


## The time to the next boundary a step must not straddle (see `clip` above). INF when none is
## pending.
static func next_event_s(s: GameState) -> float:
	var r := s.realm
	var e := INF
	if s.relish["state"] == "travelling":
		e = minf(e, maxf(0.0, s._dist_to(s.relish["target"]) - GameState.ARRIVE_EPS) / s.travel_speed())
	var ts := s.town_sim
	for lot in ts.buildings:
		var b: Dictionary = ts.buildings[lot]
		if b["state"] == "unpaid" and float(b["unpaid_s"]) > 0.0:
			e = minf(e, float(b["unpaid_s"]))
	for k in ["gold", "bone"]:
		var stock: float = ts.gold if k == "gold" else ts.bone
		var net := float(ts.rates[k]["in"]) - float(ts.rates[k]["out"])
		if stock > 1.0 and net < 0.0:
			e = minf(e, stock / -net)
	var ti: Dictionary = r.tithe
	if bool(ti.get("started", false)):
		var ns := float(ti["next_s"])
		var warn := float(r.t.get("tithe", {}).get("warning_s", 150.0))
		if (ti["warning"] as Dictionary).is_empty() and ns - warn > 0.0:
			e = minf(e, ns - warn)
		if ns > 0.0:
			e = minf(e, ns)
		var wv: Dictionary = ti["wave"]
		if not wv.is_empty() and float(wv["s_left"]) > 0.0:
			e = minf(e, float(wv["s_left"]))
	for f in r.forts:
		if float(f["held_s"]) > 0.0:
			e = minf(e, float(f["held_s"]))
	return e


## Runs `seconds` of core steps of at most `dt` from `s`, sampling every SAMPLE_S. Returns
## {samples, steps, us_per_step (median over the chunks), neg, ledger_err, coupled, peak, end_over,
## outcome (_outcome)}:
## `coupled` is the mean number of forts per step in the coupled regime (living and undead both
## above 0 at the step's end, or one of them reaching 0 inside the step); `peak` is {fort_id: [the
## most living it held at any step's end, its cap, its bound cap + one wave's mass]} and `end_over`
## the forts holding living above cap · 1.01 at the run's end with no wave there running or ended
## within 7τ (MECHANICS §3.4: what a wave leaves above the cap marches back with time constant τ).
func run_one(s: GameState, dt: float, seconds: float, clip: bool) -> Dictionary:
	var samples: Array = [sample(s)]
	var tc: Dictionary = s.realm.t.get("tithe", {})
	var wave_mass := float(tc.get("surge_mult", 3.0)) * float(s.realm.t.get("S_vei", 8.0)) * float(tc.get("surge_s", 40.0))
	var tau := float(tc.get("march_back_s", 60.0))
	var peak := {}
	var waved := {}  # fort_id -> the last time a wave ran there
	for f in s.realm.forts:
		peak[f["id"]] = [float(f["living"]), float(f["cap"]), float(f["cap"]) + wave_mass]
	var neg: Array = []
	var steps := 0
	var worst_l := 0.0
	var chunk_us: Array = []
	var chunk_steps := 0
	var chunk_t := 0
	var coupled := 0
	var t0 := s.t
	var outcome := _outcome()
	s.drain_events()
	var next_sample := SAMPLE_S
	while next_sample <= seconds + 1e-6:
		var done := s.t - t0
		var h := minf(dt, next_sample - done)
		if clip:
			var e := next_event_s(s)
			if e > 1e-6 and e < h:
				h = e
		var wv0: Dictionary = s.realm.tithe.get("wave", {})
		var u0 := Time.get_ticks_usec()
		s._core_step(h)
		chunk_t += Time.get_ticks_usec() - u0
		for wv in [wv0, s.realm.tithe.get("wave", {})]:
			if not (wv as Dictionary).is_empty():
				waved[wv["fort_id"]] = s.t
		chunk_steps += 1
		steps += 1
		for f in s.realm.forts:
			if (float(f["living"]) > 0.0 and float(f["undead"]) > 0.0) or float(f.get("t_living_out", -1.0)) > 0.0 \
					or float(f.get("t_undead_out", -1.0)) > 0.0:
				coupled += 1
			var pk: Array = peak[f["id"]]
			pk[0] = maxf(float(pk[0]), float(f["living"]))
		if s.t - t0 >= next_sample - 1e-6:
			samples.append(sample(s))
			_note(s.drain_events(), outcome, t0)
			worst_l = maxf(worst_l, GameState.Ledger.error(s.ledger()))
			_negatives(s, neg)
			chunk_us.append(float(chunk_t) / float(chunk_steps))
			chunk_t = 0
			chunk_steps = 0
			next_sample += SAMPLE_S
	chunk_us.sort()
	_note(s.drain_events(), outcome, t0)
	for f in s.realm.forts:
		if RealmSim.is_held(f):
			outcome["held"].append(str(f["id"]))
		if float(f["living"]) > 1.0:
			outcome["garrisoned"].append(str(f["id"]))
	outcome["tier"] = s.town_tier
	var end_over: Array = []
	for f in s.realm.forts:
		if float(f["living"]) > float(f["cap"]) * 1.01 and float(waved.get(f["id"], -INF)) < s.t - 7.0 * tau:
			end_over.append("%s %.2f × cap" % [f["id"], float(f["living"]) / float(f["cap"])])
	return {"samples": samples, "steps": steps, "us_per_step": chunk_us[int(chunk_us.size() / 2.0)], "neg": neg,
		"ledger_err": worst_l, "coupled": float(coupled) / maxf(1.0, float(steps)), "peak": peak, "end_over": end_over,
		"outcome": outcome}


## A run's outcomes: each event list holds [what, t − t0] in order; the rest is read at the end.
static func _outcome() -> Dictionary:
	return {"flips": [], "retaken": [], "waves": [], "builds": [], "unpaid": [], "tiers": [], "held": [],
		"garrisoned": [], "tier": ""}


static func _note(evs: Array, o: Dictionary, t0: float) -> void:
	for e in evs:
		var t := float(e.get("t", 0.0)) - t0
		match str(e.get("type", "")):
			"fort_flipped":
				o["flips"].append([str(e["fort_id"]), t])
			"fort_retaken":
				o["retaken"].append(["%s (%s)" % [e["fort_id"], e["cause"]], t])
			"tithe_wave":
				o["waves"].append([str(e["fort_id"]), t])
			"building_done":
				o["builds"].append(["%s %s L%d" % [e["lot_id"], e["building_id"], int(e["level"])], t])
			"building_unpaid":
				o["unpaid"].append(["%s %s" % [e["lot_id"], "off" if bool(e["unpaid"]) else "on"], t])
			"tier_up":
				o["tiers"].append([str(e["tier"]), t])


## An event list against the reference's: "n =" with the worst time difference when the same
## things come in the same order, else both counts and the first that differs.
static func _cmp_events(a: Array, ref: Array) -> String:
	var n := mini(a.size(), ref.size())
	var worst_t := 0.0
	for i in n:
		if a[i][0] != ref[i][0]:
			return "%d vs %d: #%d %s at %.0f s, ref %s at %.0f s" % [a.size(), ref.size(), i + 1, a[i][0], a[i][1], ref[i][0], ref[i][1]]
		worst_t = maxf(worst_t, absf(float(a[i][1]) - float(ref[i][1])))
	if a.size() != ref.size():
		var longer: Array = a if a.size() > ref.size() else ref
		return "%d vs %d: #%d %s at %.0f s only %s" % [a.size(), ref.size(), n + 1, longer[n][0], longer[n][1],
			"here" if a.size() > ref.size() else "in the ref"]
	return "%d =" % n if n == 0 else "%d = (±%.1f s)" % [n, worst_t]


static func _cmp_set(a: Array, ref: Array) -> String:
	if a == ref:
		return "%d =" % a.size()
	return "%s vs ref %s" % [",".join(PackedStringArray(a)), ",".join(PackedStringArray(ref))]


## The outcomes of measure()'s runs against each start's reference (dts[0]): see the header.
static func outcome_table(res: Dictionary, hours: float) -> String:
	var st0: String = res.keys()[0]
	var lines: Array = ["  [convergence] %.0f h outcomes vs dt %s s: event lists \"n =\" when the same come in the same order (worst time difference), forts at the end \"n =\" when the same" % [
		hours, str(res[st0].keys()[0])],
		"  | start | dt s | flips | retaken | waves | builds done | unpaid / resumed | tier ups | held at end | holding living at end | tier |",
		"  |---|---|---|---|---|---|---|---|---|---|---|"]
	for st in res:
		var per: Dictionary = res[st]
		var dts: Array = per.keys()
		var ref: Dictionary = per[dts[0]]["outcome"]
		for dt in dts:
			var o: Dictionary = per[dt]["outcome"]
			var cells: Array = []
			for k in ["flips", "retaken", "waves", "builds", "unpaid", "tiers"]:
				cells.append(_cmp_events(o[k], ref[k]) if dt != dts[0] else "%d" % (o[k] as Array).size())
			for k in ["held", "garrisoned"]:
				cells.append(_cmp_set(o[k], ref[k]) if dt != dts[0] else "%d" % (o[k] as Array).size())
			cells.append(str(o["tier"]) if dt == dts[0] or o["tier"] == ref["tier"] else "%s vs ref %s" % [o["tier"], ref["tier"]])
			lines.append("  | %s | %s | %s |" % [st, str(dt), " | ".join(PackedStringArray(cells))])
	return "\n".join(PackedStringArray(lines))


func _negatives(s: GameState, bad: Array) -> void:
	if bad.size() > 8:
		return
	var d := sample(s)
	for k in d:
		if not is_finite(float(d[k])) or float(d[k]) < -1e-9:
			bad.append("t %.0f: %s = %f" % [s.t, k, float(d[k])])
	for f in s.realm.forts:
		for k in ["living", "undead", "dead"]:
			if not is_finite(float(f[k])) or float(f[k]) < -1e-9:
				bad.append("t %.0f: %s.%s = %f" % [s.t, f["id"], k, float(f[k])])


## Every start at every dt: {start: {dt: {err: {metric: rel}, steps, us_per_step, coupled, neg,
## ledger_err, floors}}}. dts[0] is each start's reference. `edit` (optional) changes each loaded
## state before it runs.
func measure(starts: Array, hours: float, dts: Array, clip: bool, edit := Callable()) -> Dictionary:
	var out := {}
	for st in starts:
		var js := start_json(st)
		var runs := {}
		for dt in dts:
			var s := load_state(js)
			if edit.is_valid():
				edit.call(s)
			runs[dt] = run_one(s, dt, hours * 3600.0, clip)
		var ref: Array = runs[dts[0]]["samples"]
		var floors := floors_of(load_state(js), ref)
		var per := {}
		for dt in dts:
			var r: Dictionary = runs[dt]
			var err := {}
			for m in METRICS:
				var floor_m: float = floors[m]
				var e := 0.0
				for i in ref.size():
					var x := float(r["samples"][i][m])
					var y := float(ref[i][m])
					e = maxf(e, absf(x - y) / maxf(absf(y), floor_m))
				err[m] = e
			per[dt] = {"err": err, "steps": r["steps"], "us_per_step": r["us_per_step"], "coupled": r["coupled"],
				"neg": r["neg"], "ledger_err": r["ledger_err"], "floors": floors, "peak": r["peak"], "end_over": r["end_over"],
				"outcome": r["outcome"]}
		out[st] = per
	return out


## Each metric's error floor (see the header): its natural scale.
static func floors_of(s: GameState, ref: Array) -> Dictionary:
	var sum_cap := 0.0
	for f in s.realm.forts:
		sum_cap += float(f["cap"])
	var out := {}
	for m in METRICS:
		var peak := 0.0
		for smp in ref:
			peak = maxf(peak, absf(float(smp[m])))
		out[m] = maxf(1.0, 0.01 * peak)
	out["bodies"] = s.town_sim.body_cap()
	out["vei_pool"] = float(s.realm.t.get("vei_pool_cap", 600.0))
	for m in ["fort_living", "fort_undead", "fort_dead"]:
		out[m] = 0.01 * sum_cap
	return out


static func worst(per_dt: Dictionary, metrics: Array = METRICS) -> float:
	var w := 0.0
	for m in metrics:
		w = maxf(w, float(per_dt["err"][m]))
	return w


## The cost of a step at `dt`: the worst (largest) start's best-of-RUNS, µs.
static func cost_us(cost: Dictionary, dt: float) -> float:
	var w := 0.0
	for st in cost:
		if st != "field" and (cost[st] as Dictionary).has(dt):
			w = maxf(w, float(cost[st][dt][0]))
	return w


## One full field tick on the shipped field (128 × 90), µs: the median of a few, after a warm-up.
func field_tick_us() -> float:
	if _field_us < 0.0:
		var s := GameState.new(TestUtil.configs())
		s.debug_enabled = true
		s.cmd_debug_load_fixture("midgame_2flips")
		var each: Array = []
		for i in 12:
			s._inject_sources(0.2)
			var u0 := Time.get_ticks_usec()
			s.field.tick(0.2)
			s.field.flush()
			each.append(Time.get_ticks_usec() - u0)
		each.sort()
		_field_us = float(each[int(each.size() / 2.0)])
	return _field_us


## 12 h and 7 d wall seconds at `dt`: the core steps plus FIELD_TICKS field ticks (fixed, not scaled
## with the length; ×14 for 7 d is given separately).
func projection(us: float, dt: float) -> Array:
	var field_s := field_tick_us() * FIELD_TICKS / 1e6
	return [us * 43200.0 / dt / 1e6 + field_s, us * 604800.0 / dt / 1e6 + field_s]


static func _pct(x: float) -> String:
	if x < 0.0005:
		return "%.3f%%" % (x * 100.0)
	return ("%.2f%%" % (x * 100.0)) if x < 0.1 else ("%.1f%%" % (x * 100.0))


func table(res: Dictionary, hours: float, note := "") -> String:
	var lines: Array = []
	var st0: String = res.keys()[0]
	lines.append("  [convergence] %.0f h, no input, core steps only, field frozen; %s; max relative error vs dt %s s" % [
		hours, note if note != "" else "steps clipped at the events IDLE §4 lists (see the header)", str(res[st0].keys()[0])])
	var fl: Dictionary = res[st0][res[st0].keys()[0]]["floors"]
	lines.append("  floors (|ref| below them is judged against them): bodies = body cap, vei pool = %.0f, fort pools = 1%% of Σcap = %.1f, the rest 1%% of their peak" % [
		float(fl["vei_pool"]), float(fl["fort_living"])])
	lines.append("  | start | dt s | steps | " + " | ".join(PackedStringArray(METRICS.map(func(m): return SHORT[m])))
		+ " | worst | Vei+Cov worst | µs/step | 12 h s | 7 d s |")
	lines.append("  |" + "---|".repeat(METRICS.size() + 8))
	for st in res:
		var per: Dictionary = res[st]
		var dts: Array = per.keys()
		for dt in dts:
			var r: Dictionary = per[dt]
			var cells: Array = []
			for m in METRICS:
				cells.append("ref" if dt == dts[0] else _pct(float(r["err"][m])))
			var us := float(r["us_per_step"])
			var p := projection(us, dt)
			var label := str(dt) + (" (noise)" if dt < dts[0] else "")
			lines.append("  | %s | %s | %d | %s | %s | %s | %.0f | %.2f | %.1f |" % [st, label, int(r["steps"]),
				" | ".join(PackedStringArray(cells)), "ref" if dt == dts[0] else _pct(worst(r)),
				"ref" if dt == dts[0] else _pct(worst(r, KEY)), us, p[0], p[1]])
	return "\n".join(PackedStringArray(lines))


## Balanced, finite, non-negative at every sample of every run; no fort's living ever more than one
## wave's mass past its cap, and none above cap · 1.01 at the end unless a wave ran there within 7τ
## (E2b T3.0s: from midgame_2flips, 12 h with no input once took Greywall to about 850 × its cap;
## T3.0m marches the excess back, MECHANICS §3.4).
func check(res: Dictionary) -> void:
	for st in res:
		for dt in res[st]:
			var r: Dictionary = res[st][dt]
			bound_ok(r, "%s at %s s" % [st, str(dt)])
			t.ok(float(r["ledger_err"]) < 1e-6, "%s at %s s: the ledger balances (worst %s)" % [st, str(dt),
				String.num_scientific(float(r["ledger_err"]))])
			t.ok((r["neg"] as Array).is_empty(), "%s at %s s: no negative or non-finite stock%s" % [st, str(dt),
				"" if (r["neg"] as Array).is_empty() else ": " + str(r["neg"])])


## The march-back's two assertions on a run_one or measure() result (see check()).
func bound_ok(r: Dictionary, what: String) -> void:
	var over := peaks_over(r["peak"])
	t.ok(over.is_empty(), "%s: no fort's living ever passes cap + one wave's mass%s" % [what,
		"" if over.is_empty() else ": " + ", ".join(PackedStringArray(over))])
	t.ok((r["end_over"] as Array).is_empty(), "%s: at the end no fort holds living above cap · 1.01 but within 7τ of a wave%s" % [what,
		"" if (r["end_over"] as Array).is_empty() else ": " + ", ".join(PackedStringArray(r["end_over"]))])


## The forts of a run_one `peak` whose living went past their bound, as "id peak/bound".
static func peaks_over(peak: Dictionary) -> Array:
	var out: Array = []
	for id in peak:
		var p: Array = peak[id]
		if float(p[0]) > float(p[2]) * (1.0 + 1e-12) + 1e-9:
			out.append("%s %.3f/%.0f" % [id, float(p[0]), float(p[2])])
	return out


## Each fort's peak living as a multiple of its cap, per dt of one start (run_one's `peak`).
static func peak_table(res: Dictionary, start: String) -> String:
	var per: Dictionary = res[start]
	var dts: Array = per.keys()
	var ids: Array = (per[dts[0]]["peak"] as Dictionary).keys()
	var lines: Array = ["  [convergence] %s: each fort's peak living / cap (its bound: 1 + one wave's mass / cap)" % start,
		"  | dt s | " + " | ".join(PackedStringArray(ids)) + " |", "  |" + "---|".repeat(ids.size() + 1)]
	for dt in dts:
		var cells: Array = []
		for id in ids:
			var p: Array = per[dt]["peak"][id]
			cells.append("%.2f" % (float(p[0]) / float(p[1])))
		lines.append("  | %s | %s |" % [str(dt), " | ".join(PackedStringArray(cells))])
	return "\n".join(PackedStringArray(lines))


## The attribution run: pre_vei without haulers (every charnel house's staff cap at 0), 2 h. If the
## fort pools and bodies converge without the convoy, their error with it is the convoy's discrete
## near-tie choices, not the integrator.
func attribution() -> String:
	var no_haul := func(s: GameState) -> void:
		for lot in s.town_sim.buildings:
			var b: Dictionary = s.town_sim.buildings[lot]
			if int(s.town_sim._defs[b["building_id"]]["jobs"].get("haul", 0)) > 0:
				s.cmd_set_staff_cap(lot, 0)
	var a := measure(["pre_vei"], 2.0, [0.5, 0.25, 2.0, 15.0, 30.0], true, no_haul)
	var b := measure(["pre_vei"], 2.0, [0.5, 0.25, 2.0, 15.0, 30.0], true)
	return table(b, 2.0, "attribution: pre_vei with its convoy") + "\n" + table(a, 2.0, "attribution: pre_vei with no haulers") \
		+ "\n" + outcome_table(b, 2.0) + "\n" + outcome_table(a, 2.0)


## The criterion as the brief states it (every metric ≲ TOL at every start) and, as secondary
## information, the same on Vei's stocks and Covington's smooth ones (KEY) only.
func recommend(res: Dictionary, cost: Dictionary) -> String:
	var dts: Array = (res[res.keys()[0]] as Dictionary).keys()
	var best := -1.0
	var best_key := -1.0
	for dt in dts:
		if dt <= dts[0]:
			continue
		var ok := true
		var ok_key := true
		for st in res:
			ok = ok and worst(res[st][dt]) <= TOL
			ok_key = ok_key and worst(res[st][dt], KEY) <= TOL
		if ok and dt > best:
			best = dt
		if ok_key and dt > best_key:
			best_key = dt
	var lines: Array = []
	lines.append("  [convergence] field: one full tick %.0f µs; %d ticks per catch-up = %.2f s (×14 for 7 d = %.1f s)" % [
		field_tick_us(), FIELD_TICKS, field_tick_us() * FIELD_TICKS / 1e6, field_tick_us() * FIELD_TICKS * 14.0 / 1e6])
	for dt in dts:
		var us := cost_us(cost, dt)
		var p := projection(us, dt)
		lines.append("  [convergence] dt %s s: %.0f µs/step (worst start, best of %d) · 12 h %.2f s (budget %.0f) · 7 d %.1f s (budget %.0f)%s%s" % [
			str(dt), us, RUNS, p[0], BUDGET_12H_S, p[1], BUDGET_7D_S,
			"  <- largest dt with every metric within %.1f%%" % (TOL * 100.0) if dt == best else "",
			"  <- largest dt with Vei's and Covington's stocks within %.1f%%" % (TOL * 100.0) if dt == best_key else ""])
	if best < 0.0:
		lines.append("  [convergence] no dt above 0.5 s holds every metric within %.1f%% at every start" % (TOL * 100.0))
	return "\n".join(PackedStringArray(lines))


## The fallback's price: sub-stepping only the forts in the coupled regime at h, rates held from
## the outer dispatch. fort_step's own cost (the minimum over repeated chunks) × the coupled forts
## per step (measured) × (dt / h − 1) extra fort steps.
func fallback(res: Dictionary, cost: Dictionary) -> String:
	var sim := RealmSim.new()
	var all := TestUtil.configs()
	sim.setup(all["world"], all["realm"])
	var f: Dictionary = sim.forts[3]
	var best := INF
	for chunk in 20:
		var u0 := Time.get_ticks_usec()
		for i in 200:
			f["living"] = 120.0
			f["undead"] = 30.0
			f["dead"] = 5.0
			sim.fort_step(f, 15.0, 0.5, 2.0, 0.0, false, 1.2)
		best = minf(best, float(Time.get_ticks_usec() - u0) / 200.0)
	var lines: Array = ["  [convergence] fallback: fort_step %.1f µs (min of 20 chunks of 200; load %s)" % [best, _loadavg()]]
	var dts: Array = (res[res.keys()[0]] as Dictionary).keys()
	for dt in dts:
		if dt < 5.0:
			continue
		var coupled := 0.0
		for st in res:
			coupled = maxf(coupled, float(res[st][dt]["coupled"]))
		for h in [2.0, 4.0]:
			var extra := coupled * maxf(0.0, dt / h - 1.0) * best
			var p := projection(cost_us(cost, dt) + extra, dt)
			lines.append("  [convergence] fallback at dt %s s, h %.0f s: %.2f coupled forts/step (worst start) → +%.0f µs/step · 12 h %.2f s · 7 d %.1f s" % [
				str(dt), h, coupled, extra, p[0], p[1]])
	return "\n".join(PackedStringArray(lines))
