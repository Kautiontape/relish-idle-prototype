extends RefCounted
## E4 step 0 (the E3 review's item 2; the manager's ruling a): the I1 gate's bodies branch proved on synthetic samples, in
## the default suite. Autoplayer.i1_compare judges the bodies within one convoy load (job.haul.carry x the larger of the
## two runs' staffed haulers), never tighter than idle.catchup_tol; every other stock within catchup_tol. The samples
## here differ only where a case says so (the same t, floors, buildings and held forts), so each case is the revert
## proof of one piece:
## - two loads dropped fails on the bodies (the ruling's proof; the live gate's one-load drop can't fail by construction);
## - just under one load passes, though far over catchup_tol (removing the bounds branch fails it);
## - just over one load fails (a looser bound passes it);
## - the closed run staffing more haulers than the open one widens the bound (the open run's alone fails it), either way
##   round;
## - with no haulers in either run, catchup_tol is the bound;
## - a stock outside the bounds is still gated by catchup_tol, and the bodies stay out of `worst`.

var t := TestUtil.new()
var tol := 0.02
var carry := 14.0


func _sample(bodies: float, haulers: float, gold := 500.0) -> Dictionary:
	return {"t": 172800.0, "stocks": {"gold": gold, "bodies": bodies, "backlog": 2.5e7},
		"floors": {"gold": 65.0, "bodies": 3.0},
		"bounds": {"bodies": {"bound": carry * haulers, "carry": carry, "haulers": haulers}},
		"buildings": {"lot-01": "crypt L1", "lot-04": "charnel_house L2"}, "held": ["ashgate", "old_sluice"]}


func _why0(r: Dictionary) -> String:
	return "" if (r["why"] as Array).is_empty() else str(r["why"][0])


func run() -> int:
	t.suite("i1_gate")
	var c := Autoplayer.cfgs()
	tol = float(c["economy"]["idle"]["catchup_tol"])
	carry = float(c["economy"]["job"]["haul"]["carry"])
	var load := carry * 6.0
	var open_b := 4.0 * load  # a store of four loads, so 2% of it is far under one load
	t.ok(tol * open_b < load, "setup: one load (%s) is above catchup_tol x the store (%s)" % [str(load), str(tol * open_b)])

	var same := Autoplayer.i1_compare(_sample(open_b, 6.0), _sample(open_b, 6.0), tol)
	t.ok(bool(same["ok"]), "identical samples pass: %s" % str(same["why"]))

	var two := Autoplayer.i1_compare(_sample(open_b - 2.0 * load, 6.0), _sample(open_b, 6.0), tol)
	t.ok(not bool(two["ok"]) and _why0(two).begins_with("bodies"),
		"two loads dropped (delta %s, bound %s) fails on the bodies: %s" % [str(2.0 * load), str(load), str(two["why"])])
	t.near(float(two["bounded"]["bodies"]["delta"]), 2.0 * load, 1e-9, "two loads dropped: the delta is two loads")
	t.near(float(two["bounded"]["bodies"]["bound"]), load, 1e-9, "two loads dropped: the bound is one load")

	var under := Autoplayer.i1_compare(_sample(open_b - (load - 1.0), 6.0), _sample(open_b, 6.0), tol)
	t.ok(bool(under["ok"]) and (under["bounded"] as Dictionary).has("bodies"),
		"just under one load (delta %s, %s%% of the store) passes on the bounds branch: %s" % [str(load - 1.0),
		str(snappedf((load - 1.0) / open_b * 100.0, 0.1)), str(under["why"])])

	var over := Autoplayer.i1_compare(_sample(open_b - (load + 1.0), 6.0), _sample(open_b, 6.0), tol)
	t.ok(not bool(over["ok"]) and _why0(over).begins_with("bodies"), "just over one load (delta %s) fails on the bodies: %s" % [
		str(load + 1.0), str(over["why"])])

	# the closed run staffs 10 haulers, the open one 6: the bound is 10 loads' worth of carry, either way round
	var mid := 0.5 * (load + carry * 10.0)
	var more_closed := Autoplayer.i1_compare(_sample(open_b - mid, 10.0), _sample(open_b, 6.0), tol)
	t.ok(bool(more_closed["ok"]) and float(more_closed["bounded"]["bodies"]["bound"]) == carry * 10.0,
		"closed 10 haulers, open 6, delta %s: the bound is carry x 10 (%s) and it passes: %s" % [str(mid),
		str(more_closed["bounded"]["bodies"]["bound"]), str(more_closed["why"])])
	var more_open := Autoplayer.i1_compare(_sample(open_b - mid, 6.0), _sample(open_b, 10.0), tol)
	t.ok(bool(more_open["ok"]) and float(more_open["bounded"]["bodies"]["bound"]) == carry * 10.0,
		"closed 6 haulers, open 10, delta %s: the same bound, it passes: %s" % [str(mid), str(more_open["why"])])
	t.ok(float(more_closed["bounded"]["bodies"]["haulers_closed"]) == 10.0 and float(more_closed["bounded"]["bodies"]["haulers_open"]) == 6.0,
		"both runs' haulers are reported: %s" % str(more_closed["bounded"]["bodies"]))

	# no haulers in either run: catchup_tol x the store is the bound
	var floor_b := tol * open_b
	var none_in := Autoplayer.i1_compare(_sample(open_b - 0.9 * floor_b, 0.0), _sample(open_b, 0.0), tol)
	var none_out := Autoplayer.i1_compare(_sample(open_b - 1.1 * floor_b, 0.0), _sample(open_b, 0.0), tol)
	t.ok(bool(none_in["ok"]) and not bool(none_out["ok"]) and _why0(none_out).begins_with("bodies"),
		"no haulers: within catchup_tol x the store (%s) passes, over it fails: %s" % [str(floor_b), str(none_out["why"])])

	# a stock outside the bounds: gold 3% off fails on catchup_tol; the bodies (one load off) stay out of `worst`
	var gold_off := Autoplayer.i1_compare(_sample(open_b - (load - 1.0), 6.0, 500.0 * 1.03), _sample(open_b, 6.0), tol)
	t.ok(not bool(gold_off["ok"]) and _why0(gold_off).begins_with("gold") and str(gold_off["worst"][0]) == "gold",
		"gold 3%% off fails on catchup_tol, and the bodies stay out of worst: %s, worst %s" % [str(gold_off["why"]), str(gold_off["worst"])])
	return t.failures
