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
## - a stock outside the bounds is still gated by catchup_tol, and the bodies stay out of `worst`;
## - Vei's pool within one wave's drawdown D when the two runs' wave states differ, else catchup_tol (_pool, E4 step 3).

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
	_pool(c)
	_threshold_row()
	return t.failures


## The I1 replay's threshold row (the E4 review's item 9): on the measured first difference at 6563284 (a zombie craft at
## 346 115 s, bone 328.92 closed against 284.09 open, the price 300) the threshold lies between the runs, a straddle;
## both over it isn't; a queue command reads its room (queue_len < queue_max) the same way; an op with no known
## threshold lists only the stocks that differ.
func _threshold_row() -> void:
	var e := {"t": 346115.0, "op": "craft_husk", "args": ["zombie"], "ok": true, "reason": "",
		"snap": {"bone": 328.92, "remnants": 20, "gold": 460.95, "husks": 0}}
	var thr := [["bone", "ge", 300.0], ["remnants", "ge", 6.0]]
	var st := Autoplayer.threshold_row(e, {"bone": 284.09, "remnants": 20, "gold": 460.13, "husks": 0}, thr)
	t.ok(bool(st["straddle"]) and bool(st["thresholds"][0]["straddle"]) and not bool(st["thresholds"][1]["straddle"])
		and st["differ"].has("bone") and st["differ"].has("gold") and not st["differ"].has("remnants"),
		"bone 328.92 closed against 284.09 open, the price 300 between: a straddle on bone, not on the remnants: %s" % JSON.stringify(st))
	var both := Autoplayer.threshold_row(e, {"bone": 310.0, "remnants": 20, "gold": 460.95, "husks": 0}, thr)
	t.ok(not bool(both["straddle"]) and both["differ"].keys() == ["bone"], "both runs over the price: not a straddle: %s" % JSON.stringify(both))
	var qe := {"t": 274631.5, "op": "queue", "args": ["", "lot-07"], "ok": true, "reason": "", "snap": {"queue_len": 7}}
	var qs := Autoplayer.threshold_row(qe, {"queue_len": 8}, [["queue_len", "lt", 8.0]])
	t.ok(bool(qs["straddle"]), "the queue: 7 closed (room) against 8 open (full) of queue_max 8: a straddle: %s" % JSON.stringify(qs))
	var no := Autoplayer.threshold_row({"t": 1.0, "op": "party", "args": [], "ok": true, "reason": "", "snap": {"bone": 1.0}}, {"bone": 2.0}, [])
	t.ok(not bool(no["straddle"]) and (no["thresholds"] as Array).is_empty() and no["differ"].keys() == ["bone"],
		"an op with no known threshold: no straddle, the stocks that differ listed: %s" % JSON.stringify(no))
	# the step 4 review's item 7: the straddle carries its stock gap, so 328.92 against 284.09 reads as runs already
	# 15.8% apart (over the 2% tolerance), not a tie on the line; the queue's 7 against 8 is 12.5%
	t.ok(absf(float(st["stock_gap"]) - 44.83 / 284.09) < 1e-3 and absf(float(st["thresholds"][0]["gap"]) - 44.83) < 1e-6
		and float(st["thresholds"][1]["gap_rel"]) == 0.0 and absf(float(qs["stock_gap"]) - 0.125) < 1e-9 and float(no["stock_gap"]) == 0.0,
		"the stock gap beside the straddle: bone %s (%s), the queue %s; no threshold, 0" % [str(st["thresholds"][0]["gap"]),
		Autoplayer.conv_pct(float(st["stock_gap"])), Autoplayer.conv_pct(float(qs["stock_gap"]))])
	# and the bodies row: the gap at every replayed command against one load, counting the breaks the gate's day-end
	# samples miss (day 4's 140.6 against the bound 126, at 6563284)
	var br := {"n": 0, "worst": -1.0, "worst_t": -1.0, "worst_bound": 0.0, "breaks": 0, "first_break": {}}
	Autoplayer.bodies_gap_add(br, 10.0, 50.0, 40.0, 126.0)
	Autoplayer.bodies_gap_add(br, 20.0, 300.0, 159.4, 126.0)
	Autoplayer.bodies_gap_add(br, 30.0, 100.0, 300.0, 126.0)
	Autoplayer.bodies_gap_add(br, 40.0, 0.0, 0.0, 0.0)
	t.ok(int(br["n"]) == 4 and int(br["breaks"]) == 2 and float(br["worst"]) == 200.0 and float(br["worst_t"]) == 30.0
		and float(br["first_break"]["t"]) == 20.0 and float(br["first_break"]["gap"]) == 140.6,
		"the bodies row counts each command, the widest gap and each break over one load, the first kept: %s" % JSON.stringify(br))


## Vei's pool (E4 step 3, the manager's ruling (ii)), on day 2's measured samples at K 36M: the closed run full, 18.7 s
## before wave 441; the open run 11 s into wave 441, its pool drawn to 553.16.
func _pw(wave_id: int, s_left: float, next_id: int, next_s: float, period: float, q: float, give: float) -> Dictionary:
	return {"started": true, "wave_id": wave_id, "s_left": s_left, "mult": 3.0 if wave_id >= 0 else -1.0, "next_s": next_s,
		"next_id": next_id, "period": period, "q": q, "give": give, "surge_s": surge_s, "surge_mult": surge_mult,
		"S_vei": s_vei, "R_vei": r_vei}


func _ps(pool: float, pw: Dictionary) -> Dictionary:
	var x := _sample(100.0, 6.0)
	x["stocks"]["vei_pool"] = pool
	x["floors"]["vei_pool"] = 600.0
	x["pool_wave"] = pw
	return x


var surge_s := 40.0
var surge_mult := 3.0
var s_vei := 8.0
var r_vei := 50.0


## - day 2's gap (46.84, 7.8% of the cap) passes on the pool branch, with D = surge_s x (mult x S_vei + the larger give -
##   R_vei / the larger q) and the clocks' slip reported;
## - a gap one over D fails on the pool (removing the D check passes it);
## - neither run drawn (both full, the clocks apart), or both drawn on the same clock: the gap fails on catchup_tol
##   (applying D whenever the clocks differ, or always, passes them);
## - no refill inside a period (R_vei / q under the give): D never applies, the gap fails on catchup_tol.
func _pool(c: Dictionary) -> void:
	surge_s = float(c["realm"]["tithe"]["surge_s"])
	surge_mult = float(c["realm"]["tithe"]["surge_mult"])
	s_vei = float(c["realm"]["S_vei"])
	r_vei = float(c["realm"]["R_vei"])
	var closed := _pw(-1, 0.0, 441, 18.667, 362.3223, 2.23335, 5.87569)
	var open := _pw(441, 29.0352, 442, 351.225, 362.1876, 2.23233, 3.62326)
	var d := surge_s * maxf(0.0, 3.0 * s_vei + 5.87569 - r_vei / 2.23335)
	var day2 := Autoplayer.i1_compare(_ps(600.0, closed), _ps(553.1603, open), tol)
	var pw: Dictionary = day2["pool_wave"]
	t.ok(bool(day2["ok"]) and (day2["bounded"] as Dictionary).has("vei_pool") and bool(pw["applies"]),
		"day 2's pool gap (46.84, 7.8%% of the cap) passes on the pool branch: %s, %s" % [str(day2["why"]), str(pw)])
	t.near(float(pw["bound"]), d, 1e-9, "D is surge_s x (mult x S_vei + the larger give - R_vei / the larger q) = %s" % str(d))
	t.near(float(pw["slip"]), 18.667 + 362.3223 - 351.225, 1e-9, "the slip is the closed run's start of wave 442 less the open run's")
	t.ok(not bool(pw["drawn_closed"]) and bool(pw["drawn_open"]), "the closed run is full, the open one drawn: %s" % str(pw))
	var over := Autoplayer.i1_compare(_ps(600.0, closed), _ps(600.0 - (d + 1.0), open), tol)
	t.ok(not bool(over["ok"]) and _why0(over).begins_with("vei_pool"), "a gap one over D (%s) fails on the pool: %s" % [
		str(d + 1.0), str(over["why"])])
	var full := _pw(-1, 0.0, 442, 200.0, 362.1876, 2.23233, 3.62326)  # 162 s past wave 441's start: refilled
	var both_full := Autoplayer.i1_compare(_ps(600.0, closed), _ps(553.1603, full), tol)
	t.ok(not bool(both_full["ok"]) and _why0(both_full).begins_with("vei_pool") and not bool(both_full["pool_wave"]["applies"]),
		"neither drawn, the clocks apart: the gap fails on catchup_tol: %s" % str(both_full["why"]))
	var same_clock := Autoplayer.i1_compare(_ps(600.0, open), _ps(553.1603, open), tol)
	t.ok(not bool(same_clock["ok"]) and not bool(same_clock["pool_wave"]["applies"]),
		"both drawn on the same clock: the gap fails on catchup_tol: %s" % str(same_clock["why"]))
	var slow := _pw(441, 29.0352, 442, 351.225, 362.1876, 20.0, 3.62326)  # R_vei / 20 = 2.5, under the give
	var no_refill := Autoplayer.i1_compare(_ps(600.0, closed), _ps(553.1603, slow), tol)
	t.ok(not bool(no_refill["ok"]) and not bool(no_refill["pool_wave"]["premise"]),
		"no refill inside a period: D never applies, the gap fails on catchup_tol: %s" % str(no_refill["why"]))
