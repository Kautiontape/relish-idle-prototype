extends RefCounted
## A week's catch-up against a fine-step reference (IDLE §4 Budget, E2b-2 T3.3b, the run's manager's
## condition on a longer step past 12 h): 7 days caught up through the real runner from midgame_2flips,
## pre_vei and fresh, at
##   - the reference: 0.5 s throughout (idle.catchup_max_steps raised so the step is sim.substep_s, about
##     1.2 M core steps, roughly 5 min a start);
##   - the shipped schedule (10 s steps for the first 12 h, 20 s past them since E3-1, 15 s before:
##     idle.catchup_dt_long_s);
##   - and 10 s throughout (idle.catchup_dt_long_s set to idle.catchup_dt_max_s), when the shipped
##     schedule's step past 12 h is longer: T3.3a gates 10 s only over 12 h, and a flip that 10 s itself
##     causes over a week would show only against 0.5 s.
## Outcomes must match the reference: the forts held at the end, every flip and retake in order, each
## within convergence.gd's TIME_BOUND_STEPS (2) × the run's catch-up step at that moment (10 s for the first
## 12 h, idle.catchup_dt_long_s past them; the run's manager) of the reference's, and Relish's location (the
## manager: a fort that flips only because of the step size is a bug, not timing).
## Vei's and Covington's stocks are printed against the reference (7 days is a timing test for the stocks
## only, IDLE §4). The field is shrunk (8 × 6), as in tests/test_catchup.gd. Run with tests/run.sh --slow
## --only=catchup_week (about 20 min).

const STARTS := ["midgame_2flips", "pre_vei", "fresh"]
const SPAN := 604800.0

var t := TestUtil.new()


func run() -> int:
	t.suite("catchup_week")
	var cu = load("res://tests/test_catchup.gd")
	var conv = load("res://tests/slow/convergence.gd").new()
	conv.t = t
	var shipped: Dictionary = cu.cfgs()
	var fine: Dictionary = cu.cfgs({"economy.idle.catchup_max_steps": 100_000_000})
	var schedules := [["shipped", shipped]]
	var eco: Dictionary = shipped["economy"]["idle"]
	if float(eco.get("catchup_dt_long_s", 0.0)) > float(eco["catchup_dt_max_s"]):
		var ten: Dictionary = cu.cfgs({"economy.idle.catchup_dt_long_s": float(eco["catchup_dt_max_s"])})
		schedules.append(["10 s throughout", ten])
	for st in STARTS:
		var js: String = conv.start_json(st)
		var u0 := Time.get_ticks_msec()
		var ref := _week(fine, js)
		print("  [catchup_week] %s: the 0.5 s reference, %d core steps in %.0f s" % [st, int(ref["steps"]), (Time.get_ticks_msec() - u0) / 1000.0])
		for sc in schedules:
			var u1 := Time.get_ticks_msec()
			var r := _week(sc[1], js)
			var why := _outcomes(r, ref)
			var parts: Array = []
			for m in conv.KEY:
				var y := float(ref["sample"][m])
				parts.append("%s %s" % [conv.SHORT[m], conv._pct(absf(float(r["sample"][m]) - y) / maxf(absf(y), maxf(1.0, 0.01 * absf(y))))])
			print("  [catchup_week] %s, %s (%d steps, %.1f s): outcomes %s; flips %d, retakes %d, held at the end %s, Relish %s; stocks against 0.5 s: %s" % [
				st, sc[0], int(r["steps"]), (Time.get_ticks_msec() - u1) / 1000.0, "match" if why.is_empty() else "DIFFER: " + "; ".join(PackedStringArray(why)),
				(r["flips"] as Array).size(), (r["retakes"] as Array).size(), str(r["held"]), str(r["relish"]), ", ".join(PackedStringArray(parts))])
			print("  [catchup_week] %s, %s: flip and retake times (ref t, Δ / bound): %s" % [st, sc[0], _time_parts(r, ref)])
			t.ok(why.is_empty(), "%s, %s over 7 days: the forts held, every flip and retake (within the time bound), and Relish's place match the 0.5 s reference%s" % [
				st, sc[0], "" if why.is_empty() else ": " + "; ".join(PackedStringArray(why))])
	return t.failures


## A 7-day catch-up of `js` at configs `c`: {steps, flips, retakes (in order, [fort, t]), held (sorted), relish
## [state, at], sample (convergence.gd's), dt, dt_long, long_after_s (the runner's step schedule)}.
func _week(c: Dictionary, js: String) -> Dictionary:
	var s := GameState.new(c)
	s.debug_enabled = true
	t.ok(s.from_dict(JSON.parse_string(js))["ok"], "the start loads")
	var t0 := s.t
	s._catchup.begin(s, SPAN, true)
	s._catchup.run(s)
	var flips: Array = []
	var retakes: Array = []
	for e in s.catchup_events():
		if e["type"] == "fort_flipped":
			flips.append([str(e["fort_id"]), float(e["t"]) - t0])
		elif e["type"] == "fort_retaken":
			retakes.append([str(e["fort_id"]), float(e["t"]) - t0])
	var held: Array = []
	for f in s.realm.forts:
		if RealmSim.is_held(f):
			held.append(str(f["id"]))
	held.sort()
	t.ok(GameState.Ledger.error(s.ledger()) < 1e-6, "the ledger balances over the week")
	var conv = load("res://tests/slow/convergence.gd")
	return {"steps": s._catchup.steps, "flips": flips, "retakes": retakes, "held": held,
		"relish": [str(s.relish["state"]), str(s.relish["at"])], "sample": conv.sample(s),
		"dt": s._catchup.dt, "dt_long": s._catchup.dt_long, "long_after_s": s._catchup.long_after_s}


## What differs from the reference: the held set, the flips' and retakes' forts in order, each flip and
## retake outside the time bound (convergence.gd's outcome_times(), at `r`'s step at that moment), Relish's
## place.
static func _outcomes(r: Dictionary, ref: Dictionary) -> Array:
	var out: Array = []
	if r["held"] != ref["held"]:
		out.append("held %s vs %s" % [str(r["held"]), str(ref["held"])])
	for k in ["flips", "retakes"]:
		var a: Array = (r[k] as Array).map(func(e): return e[0])
		var b: Array = (ref[k] as Array).map(func(e): return e[0])
		if a != b:
			out.append("%s %d vs %d (%s vs %s)" % [k, a.size(), b.size(), str(a.slice(0, 6)), str(b.slice(0, 6))])
	out.append_array(load("res://tests/slow/convergence.gd").outcome_times(
		{"flips": r["flips"], "retaken": r["retakes"]}, {"flips": ref["flips"], "retaken": ref["retakes"]}, _step_at(r)))
	if r["relish"] != ref["relish"]:
		out.append("Relish %s vs %s" % [str(r["relish"]), str(ref["relish"])])
	return out


## A _week() result's catch-up step at t s from its start (the runner's schedule).
static func _step_at(r: Dictionary) -> Callable:
	var dt := float(r["dt"])
	var dt_long := float(r["dt_long"])
	var after := float(r["long_after_s"])
	return func(t: float) -> float: return dt_long if t >= after else dt


## Each flip's and retake's Δ from the reference's, against the bound (for the report): "fort Δ s / bound s".
static func _time_parts(r: Dictionary, ref: Dictionary) -> String:
	var parts: Array = []
	var step_at := _step_at(r)
	var k_steps: float = load("res://tests/slow/convergence.gd").TIME_BOUND_STEPS
	for k in ["flips", "retakes"]:
		for i in mini((r[k] as Array).size(), (ref[k] as Array).size()):
			if r[k][i][0] == ref[k][i][0]:
				var ta := float(r[k][i][1])
				var tb := float(ref[k][i][1])
				parts.append("%s %s %.0f s Δ %.1f / %.0f s" % [k.trim_suffix("s"), r[k][i][0], tb, absf(ta - tb),
					k_steps * maxf(float(step_at.call(ta)), float(step_at.call(tb)))])
	return "none" if parts.is_empty() else ", ".join(PackedStringArray(parts))
