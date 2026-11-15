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
## - Samples every SAMPLE_S (a multiple of every dt). A metric's (METRICS) error is the worst over the
##   samples of |x − ref| / max(|ref|, floor): a quantity pinned near 0 is judged against its natural
##   scale. The floor is the body cap for bodies, Vei's pool cap for her pool, 1% of Σ fort caps for
##   the forts' pools, and 1% of the metric's peak |ref| (at least 1) for the rest.
## - The gate (IDLE §4, E2b-2 T3.3a, the run's manager's rule; judge()): a run passes when, against
##   the reference, all three hold, at economy.json `idle.catchup_gate_tol` (1%):
##   - the stocks, Vei's and Covington's smooth ones (KEY): the worst error above ≤ tol ("Vei+Cov
##     worst");
##   - each tally (TALLIES: the gold and bone caps' overflow, ledger().stores, E2b-2 T3.2), on its
##     growth over the run: (a) at the last sample (the 12 h endpoint), |x − ref| / |ref| ≤ tol, or
##     |x − ref| ≤ its floor where |ref| is under the floor (0 included: a relative error on a tally
##     that small is noise); and (b) at every sample, |x − ref| ≤ max(tol · |ref|,
##     its floor). The floors are `idle.catchup_gate_tally_floor`, a fixed amount per tally (BALANCE
##     §5). A tally starts at 0, so its early relative error means nothing: (b)'s floor carries the
##     fixed lag a 10 s step leaves, and (b) still catches a mid-run fault the endpoint averages away;
##   - the outcomes (below) equal the reference's: the same events in the same order, the same forts
##     held and holding living at the end, the same tier. Their times may differ, but each flip and
##     retake must land within TIME_BOUND_STEPS (2) × the run's step at that point of the reference's
##     (the run's manager; outcome_times()): here the row's dt, in a catch-up its dt at that moment
##     (tests/test_catchup.gd compare(), tests/slow/catchup_week.gd). A test tolerance, not a tuning number.
##   The pools and bodies ("worst" takes them with the stocks) are printed, not gated. run() asserts
##   the gate at GATE_DT for every start, and prints every row's flips and retakes against the bound.
## - The 0.25 s row is the reference's own noise: no dt can be expected to match 0.5 s closer.
## - `clip`: steps are shortened so none straddles an event IDLE §4 clips at (next_event_s, the catch-up
##   runner's): a tithe warning, a wave's start or end, a building's unpaid hold ending, gold or bone
##   reaching their floor (projected from the last step's net), Relish arriving, a construction
##   finishing and the queue's head starting on funds. Without it the table measures event
##   timing (Relish's arrival lands up to one dt late; since T3.0m a wave's start and end are exact
##   inside a step, spread over it), not the integrator. The held forts' events are not clipped
##   (E2b-2 T3.1): a garrison reaching 0 is solved inside the fort step, and RealmSim splits its own
##   step at a grace end and at a break's end, so all three land at their time at any dt.
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
## The dt the gate is asserted at: catch-up's planned idle.catchup_dt_max_s (IDLE §4).
const GATE_DT := 10.0
## The outcomes' time bound (the header; outcome_times()): each flip and retake within this many of the
## run's steps at that point of the reference's. A test tolerance, not a tuning number.
const TIME_BOUND_STEPS := 2.0
const METRICS := ["backlog", "vei_dead", "vei_pool", "fort_living", "fort_undead", "fort_dead", "workers",
	"bodies", "gold", "bone", "living"]
## The tallies the gate judges by its (a) and (b) (see the header), and each one's floor key in
## economy.json idle.catchup_gate_tally_floor.
const TALLIES := ["gold_over", "bone_over"]
const TALLY_FLOOR_KEY := {"gold_over": "gold", "bone_over": "bone"}
## Vei's stocks and Covington's smooth ones: the stocks the gate judges ("Vei+Cov worst"). The fort
## pools and bodies aren't gated: they converge as dt → 0 on midgame_2flips, and on pre_vei until its
## gold floor; fresh's, and pre_vei's after the floor, sit within about one convoy load at any dt,
## and at 10 s pre_vei's corpses wait a step for the convoy (IDLE §4, tests/slow/convergence_fine.gd).
const KEY := ["backlog", "vei_dead", "vei_pool", "workers", "gold", "bone", "living"]
const SHORT := {"backlog": "backlog", "vei_dead": "vei dead", "vei_pool": "vei pool", "fort_living": "Σliving",
	"fort_undead": "Σundead", "fort_dead": "Σdead", "workers": "workers", "bodies": "bodies", "gold": "gold",
	"bone": "bone", "gold_over": "gold over", "bone_over": "bone over", "living": "town living"}

var t := TestUtil.new()
var _cfgs := {}
var _field_us := -1.0


func run() -> int:
	t.suite("convergence")
	print("  [convergence] load average: %s" % _loadavg())
	var res := measure(STARTS, HOURS, DTS, true)
	print(table(res, HOURS))
	print(outcome_table(res, HOURS))
	print(time_lines(res, "clipped"))
	var unclipped := measure(STARTS, HOURS, [0.5, 15.0, 30.0], false)
	print(table(unclipped, HOURS, "no event clipping (Relish's arrival lands up to one dt late; a wave starts and ends at its time, spread over its steps)"))
	print(time_lines(unclipped, "no event clipping"))
	check(res)
	print(gate_check(res, GATE_DT, HOURS))
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
		"gold_over": float(s._ledger.stores["gold"]["overflow"]), "bone_over": float(s._ledger.stores["bone"]["overflow"]),
		"living": s.town_sim.living}
	for f in s.realm.forts:
		d["fort_living"] += float(f["living"])
		d["fort_undead"] += float(f["undead"])
		d["fort_dead"] += float(f["dead"])
	return d


## The time to the next boundary a step must not straddle (see `clip` above), INF when none is pending:
## the catch-up runner's own (Catchup.next_event_s, E2b-2 T3.3b), which adds a construction finishing and
## the queue's head starting on funds to the events this harness clipped at before. Neither happens from
## these starts (no construction under way, no queue), so the tables are the same.
static func next_event_s(s: GameState) -> float:
	return Catchup.next_event_s(s)


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


## Every start at every dt: {start: {dt: {err: {metric: rel}, gate (judge()), steps, us_per_step,
## coupled, neg, ledger_err, floors, peak, end_over, outcome}}}. dts[0] is each start's reference.
## `edit` (optional) changes each loaded state before it runs.
func measure(starts: Array, hours: float, dts: Array, clip: bool, edit := Callable()) -> Dictionary:
	var out := {}
	var gate := gate_of(cfgs())
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
			var row_dt: float = dt
			var step_at := func(_t: float) -> float: return row_dt  # the row's dt: the outcomes' time bound
			per[dt] = {"err": err, "gate": judge(r["samples"], ref, floors, r["outcome"], runs[dts[0]]["outcome"], gate, SAMPLE_S, step_at),
				"steps": r["steps"], "us_per_step": r["us_per_step"], "coupled": r["coupled"],
				"neg": r["neg"], "ledger_err": r["ledger_err"], "floors": floors, "peak": r["peak"], "end_over": r["end_over"],
				"outcome": r["outcome"]}
		out[st] = per
	return out


## The gate's numbers from the configs (economy.json `idle`): {tol, floor: {tally: amount}}.
static func gate_of(all: Dictionary) -> Dictionary:
	var idle: Dictionary = all["economy"]["idle"]
	var fl := {}
	for m in TALLIES:
		fl[m] = float(idle["catchup_gate_tally_floor"][TALLY_FLOOR_KEY[m]])
	return {"tol": float(idle["catchup_gate_tol"]), "floor": fl}


## The catch-up gate (IDLE §4; the header has the rule): `samples` against `ref`, both every `sample_s`
## from the same start, `floors` the stocks' (floors_of), the two runs' outcomes, and `gate` from
## gate_of(). Returns {ok, stocks: {ok, worst, metric, at}, tallies: {m: {ok, a_ok, a (relative, −1
## where ref is 0; a_ok uses the floor instead where |ref| is under it), a_d, ref_end, b_ok, b (the worst |x − ref| / its allowance), b_d, b_allow, b_at,
## floor}}, outcomes: {ok, differ: [the lists that differ, then each time-bound miss], late: [the time-bound
## misses]}}. Times are s from the start. `step_at` (t → the run's step at t) sets the outcomes' time bound
## (outcome_times()); without it the times aren't judged.
static func judge(samples: Array, ref: Array, floors: Dictionary, outcome: Dictionary, ref_outcome: Dictionary,
		gate: Dictionary, sample_s := SAMPLE_S, step_at := Callable()) -> Dictionary:
	var tol := float(gate["tol"])
	var n := mini(samples.size(), ref.size())
	var stocks := {"worst": 0.0, "metric": "", "at": 0.0}
	for m in KEY:
		for i in n:
			var y := float(ref[i][m])
			var e := absf(float(samples[i][m]) - y) / maxf(absf(y), float(floors[m]))
			if e > float(stocks["worst"]):
				stocks = {"worst": e, "metric": m, "at": i * sample_s}
	stocks["ok"] = float(stocks["worst"]) <= tol and samples.size() == ref.size()
	var ok: bool = stocks["ok"]
	var tallies := {}
	for m in TALLIES:
		var fl := float(gate["floor"][m])
		var x0 := float(samples[0][m])
		var y0 := float(ref[0][m])
		var y_end := float(ref[n - 1][m]) - y0
		var d_end := absf(float(samples[n - 1][m]) - x0 - y_end)
		var a := d_end / absf(y_end) if y_end != 0.0 else -1.0
		var tr := {"a": a, "a_d": d_end, "ref_end": y_end, "a_ok": a <= tol if absf(y_end) >= fl and y_end != 0.0 else d_end <= fl,
			"b": 0.0, "b_d": 0.0, "b_allow": fl, "b_at": 0.0, "floor": fl}
		for i in n:
			var y := float(ref[i][m]) - y0
			var d := absf(float(samples[i][m]) - x0 - y)
			var allow := maxf(tol * absf(y), fl)
			if d / allow > float(tr["b"]):
				tr["b"] = d / allow
				tr["b_d"] = d
				tr["b_allow"] = allow
				tr["b_at"] = i * sample_s
		tr["b_ok"] = float(tr["b"]) <= 1.0
		tr["ok"] = bool(tr["a_ok"]) and bool(tr["b_ok"])
		ok = ok and bool(tr["ok"])
		tallies[m] = tr
	var differ := outcomes_differ(outcome, ref_outcome, step_at)
	ok = ok and differ.is_empty()
	return {"ok": ok, "stocks": stocks, "tallies": tallies, "outcomes": {"ok": differ.is_empty(), "differ": differ,
		"late": outcome_times(outcome, ref_outcome, step_at)}}


## The outcome lists (_outcome()) that differ from the reference's: an event list when its events
## aren't the same ones in the same order, the forts held and holding living at the end as sets, and the
## tier; then, with `step_at`, each flip and retake that misses the time bound (outcome_times()). Other
## events' times may differ.
static func outcomes_differ(o: Dictionary, ref: Dictionary, step_at := Callable()) -> Array:
	var out: Array = []
	for k in ["flips", "retaken", "waves", "builds", "unpaid", "tiers"]:
		var a: Array = o[k]
		var b: Array = ref[k]
		var same := a.size() == b.size()
		for i in mini(a.size(), b.size()):
			same = same and a[i][0] == b[i][0]
		if not same:
			out.append(k)
	for k in ["held", "garrisoned"]:
		if o[k] != ref[k]:
			out.append(k)
	if o["tier"] != ref["tier"]:
		out.append("tier")
	out.append_array(outcome_times(o, ref, step_at))
	return out


## The flips and retakes that land more than TIME_BOUND_STEPS × the run's step at that point from the
## reference's (the header): pairwise in order, while both lists name the same fort (a list whose forts
## differ is outcomes_differ's already). `step_at(t)` is the judged run's step at time t (the outcome
## lists' clock); the bound takes the larger of its step at the two times, so one pair across a step
## change (catch-up's 12 h) is judged by the longer step. Each miss as "<list> #<n> <fort> at <t> s, ref
## <t> s: Δ <d> s over <k> × <h> s". [] without `step_at`.
static func outcome_times(o: Dictionary, ref: Dictionary, step_at: Callable) -> Array:
	var out: Array = []
	if not step_at.is_valid():
		return out
	for k in ["flips", "retaken"]:
		var a: Array = o[k]
		var b: Array = ref[k]
		for i in mini(a.size(), b.size()):
			if a[i][0] != b[i][0]:
				break
			var ta := float(a[i][1])
			var tb := float(b[i][1])
			var h := maxf(float(step_at.call(ta)), float(step_at.call(tb)))
			var d := absf(ta - tb)
			if d > TIME_BOUND_STEPS * h:
				out.append("%s #%d %s at %.1f s, ref %.1f s: Δ %.1f s over %s × %s s" % [k, i + 1, a[i][0], ta, tb, d,
					str(TIME_BOUND_STEPS), str(h)])
	return out


## Every row's flips and retakes against the time bound (judge()'s `late`): one line per start and dt
## that isn't the reference, "within" with the worst Δ / bound, or each miss.
static func time_lines(res: Dictionary, what: String) -> String:
	var lines: Array = ["  [convergence] %s: flips and retakes against %s × the row's dt of the reference's (TIME_BOUND_STEPS)" % [
		what, str(TIME_BOUND_STEPS)]]
	for st in res:
		var per: Dictionary = res[st]
		var dts: Array = per.keys()
		var ref: Dictionary = per[dts[0]]["outcome"]
		for dt in dts.slice(1):
			var o: Dictionary = per[dt]["outcome"]
			var late: Array = per[dt]["gate"]["outcomes"]["late"]
			var worst := 0.0
			var n := 0
			for k in ["flips", "retaken"]:
				for i in mini((o[k] as Array).size(), (ref[k] as Array).size()):
					if o[k][i][0] != ref[k][i][0]:
						break
					n += 1
					worst = maxf(worst, absf(float(o[k][i][1]) - float(ref[k][i][1])) / (TIME_BOUND_STEPS * float(dt)))
			lines.append("  [convergence] %s at %s s: %s" % [st, str(dt), ("%d within (worst %.2f of the bound)" % [n, worst])
				if late.is_empty() else "%d MISS: %s" % [late.size(), "; ".join(PackedStringArray(late))]])
	return "\n".join(PackedStringArray(lines))


## A judge() result in one line: the verdict, then each part's figure.
static func gate_line(g: Dictionary) -> String:
	var parts: Array = ["%s" % ("pass" if bool(g["ok"]) else "FAIL"),
		"stocks %s %s (%s at %.0f s)" % ["ok" if bool(g["stocks"]["ok"]) else "FAIL", _pct(float(g["stocks"]["worst"])),
			str(g["stocks"]["metric"]), float(g["stocks"]["at"])]]
	for m in TALLIES:
		var tr: Dictionary = g["tallies"][m]
		parts.append("%s (a) %s %s, (b) %s %.3f of %.3f at %.0f s" % [SHORT[m], "ok" if bool(tr["a_ok"]) else "FAIL",
			_tally_a(tr), "ok" if bool(tr["b_ok"]) else "FAIL", float(tr["b_d"]), float(tr["b_allow"]), float(tr["b_at"])])
	parts.append("outcomes %s" % ("equal" if bool(g["outcomes"]["ok"]) else "differ: " + ", ".join(PackedStringArray(g["outcomes"]["differ"]))))
	return "; ".join(PackedStringArray(parts))


## A tally's (a) figure: its relative error at the endpoint, or the difference where ref is 0.
static func _tally_a(tr: Dictionary) -> String:
	if float(tr["ref_end"]) == 0.0:
		return "ref 0, Δ %.3f (floor %.3f)" % [float(tr["a_d"]), float(tr["floor"])]
	return "%s of %.3f" % [_pct(float(tr["a"])), absf(float(tr["ref_end"]))]


## The gate at `dt` for every start of a measure() over `hours`: one line each, and the slow suite's
## assertion.
func gate_check(res: Dictionary, dt: float, hours: float) -> String:
	var gate := gate_of(cfgs())
	var lines: Array = ["  [convergence] the gate at %s s against %s s over %.0f h (IDLE §4): tol %s, tally floors %s" % [
		str(dt), str((res[res.keys()[0]] as Dictionary).keys()[0]), hours, _pct(float(gate["tol"])), str(gate["floor"])]]
	for st in res:
		var g: Dictionary = res[st][dt]["gate"]
		lines.append("  [convergence] %s at %s s: %s" % [st, str(dt), gate_line(g)])
		t.ok(bool(g["ok"]), "%s at %s s: the catch-up gate holds over %.0f h: %s" % [st, str(dt), hours, gate_line(g)])
	return "\n".join(PackedStringArray(lines))


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
	var gate := gate_of(cfgs())
	var tol := _pct(float(gate["tol"]))
	var tally_cols: Array = []
	for m in TALLIES:
		tally_cols.append("%s (a)" % SHORT[m])
		tally_cols.append("%s (b)" % SHORT[m])
	lines.append("  the gate (IDLE §4; the header): Vei+Cov worst ≤ %s; each tally (a) at the end |x − ref| / |ref| ≤ %s, (b) at every sample |x − ref| ≤ max(%s · |ref|, its floor), shown as the worst |x − ref| / that allowance; floors %s; outcomes equal (outcome_table). \"worst\" adds the pools and bodies, which are not gated" % [
		tol, tol, tol, str(gate["floor"])])
	lines.append("  | start | dt s | steps | " + " | ".join(PackedStringArray(METRICS.map(func(m): return SHORT[m])))
		+ " | worst | Vei+Cov worst | " + " | ".join(PackedStringArray(tally_cols)) + " | outcomes | gate | µs/step | 12 h s | 7 d s |")
	lines.append("  |" + "---|".repeat(METRICS.size() + tally_cols.size() + 10))
	for st in res:
		var per: Dictionary = res[st]
		var dts: Array = per.keys()
		for dt in dts:
			var r: Dictionary = per[dt]
			var g: Dictionary = r["gate"]
			var is_ref: bool = dt == dts[0]
			var cells: Array = []
			for m in METRICS:
				cells.append("ref" if is_ref else _pct(float(r["err"][m])))
			cells.append("ref" if is_ref else _pct(worst(r)))
			cells.append("ref" if is_ref else _pct(worst(r, KEY)))
			for m in TALLIES:
				var tr: Dictionary = g["tallies"][m]
				cells.append("ref" if is_ref else ("Δ %.3f" % float(tr["a_d"]) if float(tr["ref_end"]) == 0.0 else _pct(float(tr["a"]))))
				cells.append("ref" if is_ref else "%.2f/%.2f" % [float(tr["b_d"]), float(tr["b_allow"])])
			cells.append("ref" if is_ref else ("=" if bool(g["outcomes"]["ok"]) else ", ".join(PackedStringArray(g["outcomes"]["differ"]))))
			cells.append("ref" if is_ref else ("pass" if bool(g["ok"]) else "FAIL"))
			var us := float(r["us_per_step"])
			var p := projection(us, dt)
			var label := str(dt) + (" (noise)" if dt < dts[0] else "")
			lines.append("  | %s | %s | %d | %s | %.0f | %.2f | %.1f |" % [st, label, int(r["steps"]),
				" | ".join(PackedStringArray(cells)), us, p[0], p[1]])
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


## The criterion: the gate (judge(), the header) at every start, per dt, beside each dt's cost.
func recommend(res: Dictionary, cost: Dictionary) -> String:
	var dts: Array = (res[res.keys()[0]] as Dictionary).keys()
	var best := -1.0
	var failing := {}
	for dt in dts:
		if dt <= dts[0]:
			continue
		var f: Array = []
		for st in res:
			if not bool(res[st][dt]["gate"]["ok"]):
				f.append(st)
		failing[dt] = f
		if f.is_empty() and dt > best:
			best = dt
	var lines: Array = []
	lines.append("  [convergence] field: one full tick %.0f µs; %d ticks per catch-up = %.2f s (×14 for 7 d = %.1f s)" % [
		field_tick_us(), FIELD_TICKS, field_tick_us() * FIELD_TICKS / 1e6, field_tick_us() * FIELD_TICKS * 14.0 / 1e6])
	for dt in dts:
		var us := cost_us(cost, dt)
		var p := projection(us, dt)
		var verdict := "the reference" if dt == dts[0] else ("noise" if dt < dts[0] else (
			"the gate passes at every start" if (failing[dt] as Array).is_empty() else "the gate fails at " + ", ".join(PackedStringArray(failing[dt]))))
		lines.append("  [convergence] dt %s s: %.0f µs/step (worst start, best of %d) · 12 h %.2f s (budget %.0f) · 7 d %.1f s (budget %.0f) · %s%s" % [
			str(dt), us, RUNS, p[0], BUDGET_12H_S, p[1], BUDGET_7D_S, verdict,
			"  <- largest dt passing the gate at every start" if dt == best else ""])
	if best < 0.0:
		lines.append("  [convergence] no dt above %s s passes the gate at every start" % str(dts[0]))
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
