extends RefCounted
## A long core step agrees with short ones where it used to land a moment at a step boundary
## (E2b-2 T3.3a; MECHANICS §2.1, §3.1, §3.4; IDLE §4). The 12 h gate is tests/slow/convergence.gd's;
## these are the default suite's regressions for the causes it found.
## - The zero clock when the garrison leaves 0: a contested fort whose garrison sits at 0 while her
##   living, above the cap after a wave, march back. With U at 0 nothing kills them, so L follows
##   cap + c·τ + (x0 − c·τ) · e^(−t/τ) exactly (c her reship, τ tithe.march_back_s) and U leaves 0 at
##   t_b = τ · ln((x0 − c·τ) / (x* − c·τ)), where the pull k_destroy · L / q falls to the WAR (x* the
##   living over the cap whose pull meets it). Each run counts that time at 0 at any dt; a fort whose
##   t_b is just under hold.break_s holds at 0.25, 10 and 30 s.
## - The convoy's pickup: the convoy reads each fort's corpses at its own moment in the step
##   (RealmSim.dead_at off the snapshot's dead_rate), for its pick and its pickup. midgame_2flips'
##   convoy, fixed on Greywall where Relish raises the corpses as they form, lands the same over 1 h
##   at 10 s as at 0.5 s; and a departure inside a step picks the fort the projection leads with, not
##   the stale snapshot's.
## - The gate's judge (convergence.gd judge(), the function its 10 s assertion calls; IDLE §4) on
##   synthetic 12 h series sampled every 600 s, with every case sized from economy.json idle's tol and
##   floors: a fixed lag under the floor passes; a mid-run fault that recovers by the endpoint passes
##   (a) and fails (b); a slope 2 tol off fails (a); a stock 1.5 tol off at one sample fails; a tally
##   whose endpoint is under its floor passes (a) within the floor and fails outside it; and outcomes
##   compare by order, not time.

var t := TestUtil.new()
const Q := 1.2  # digest_q for the realm cases
const WAR := 0.6  # mass/s of WAR, all of it staged at the contested fort


func run() -> int:
	t.suite("step_accuracy")
	_zero_clock_exact()
	_zero_clock_outcome()
	_convoy_greywall()
	_convoy_pick()
	_convoy_after_load()
	_gate_judge()
	return t.failures


## The judge on synthetic series: 73 samples, every 600 s over 12 h. The reference's bone tally grows
## at REF_SLOPE (slow on purpose: at pre_vei's 0.1 bone/s, 1% of it would be 23 bone at 6 h and the
## mid-run fault below would pass (b)); its gold tally stays 0; its stocks are flat but the backlog.
## `bone` maps a sample's index and the reference's bone tally to the run's; `stock` the index and the
## reference's backlog to the run's backlog.
const REF_SLOPE := 0.005  # bone/s
const N_SAMPLES := 73


func _series(bone: Callable, stock: Callable, slope := REF_SLOPE) -> Array:
	var ref: Array = []
	var run: Array = []
	for i in N_SAMPLES:
		var y := slope * 600.0 * i
		var r := {"backlog": 1000.0 + 10.0 * i, "vei_dead": 50.0, "vei_pool": 600.0, "workers": 40.0, "gold": 500.0,
			"bone": 300.0, "living": 20.0, "gold_over": 0.0, "bone_over": y}
		var x := r.duplicate()
		x["bone_over"] = float(bone.call(i, y))
		x["backlog"] = float(stock.call(i, float(r["backlog"])))
		ref.append(r)
		run.append(x)
	return [run, ref]


func _gate_judge() -> void:
	var c = load("res://tests/slow/convergence.gd").new()
	var gate: Dictionary = c.gate_of(TestUtil.configs())
	var tol := float(gate["tol"])
	var fl := float(gate["floor"]["bone_over"])
	var floors := {"backlog": 1.0, "vei_dead": 1.0, "vei_pool": 600.0, "workers": 1.0, "gold": 5.0, "bone": 3.0, "living": 1.0}
	var none: Dictionary = c._outcome()
	var same := func(i: int, y: float) -> float: return y
	var judge := func(s: Array, o: Dictionary, ro: Dictionary) -> Dictionary: return c.judge(s[0], s[1], floors, o, ro, gate)
	# the config's numbers, only sanity-checked: every case below is sized from them. 0.74 bone is the worst
	# (b) residual at 10 s over 12 h on the three starts (pre_vei at 600 s; IDLE §4), so the bone floor
	# has to stay at least that for the gate to pass at 10 s.
	var floors_ok := tol > 0.0
	for m in gate["floor"]:
		floors_ok = floors_ok and float(gate["floor"][m]) > 0.0
	t.ok(floors_ok and fl >= 0.74, "the gate's numbers are economy.json idle's and sane: tol %s, floors %s" % [str(tol), str(gate["floor"])])
	var y_end := REF_SLOPE * 43200.0
	var y6 := REF_SLOPE * 21600.0
	# a fixed lag: 0.7 of the floor (or of tol · the endpoint, if that is smaller) behind from the first sample on
	var lag := 0.7 * minf(fl, tol * y_end)
	var g: Dictionary = judge.call(_series(func(i: int, y: float) -> float: return maxf(0.0, y - lag) if i > 0 else y, same), none, none)
	t.ok(bool(g["ok"]) and bool(g["tallies"]["bone_over"]["a_ok"]) and bool(g["tallies"]["bone_over"]["b_ok"]),
		"a tally a fixed %.3f behind passes: %s" % [lag, c.gate_line(g)])
	# a mid-run fault: 5 times the larger of its allowance there and the floor, a bump from 3 h to 9 h, a
	# twenty-fifth of tol off at 12 h
	var bump := 5.0 * maxf(tol * y6, fl)
	var fault := func(i: int, y: float) -> float: return y * (1.0 - 0.04 * tol) + bump * maxf(0.0, 1.0 - absf(i - 36) / 18.0)
	g = judge.call(_series(fault, same), none, none)
	var tr: Dictionary = g["tallies"]["bone_over"]
	t.ok(bool(tr["a_ok"]), "a mid-run fault that recovers passes (a): %s at the end" % c._tally_a(tr))
	t.ok(not bool(tr["b_ok"]) and not bool(g["ok"]), "and fails (b), so the gate fails: %.3f off at %.0f s against %.3f" % [
		float(tr["b_d"]), float(tr["b_at"]), float(tr["b_allow"])])
	# a rate error: the tally's slope twice tol off
	g = judge.call(_series(func(i: int, y: float) -> float: return (1.0 + 2.0 * tol) * y, same), none, none)
	tr = g["tallies"]["bone_over"]
	t.ok(not bool(tr["a_ok"]) and not bool(g["ok"]), "a tally 2 tol off in its slope fails (a): %s" % c._tally_a(tr))
	# a stock 1.5 tol off at one sample
	g = judge.call(_series(same, func(i: int, x: float) -> float: return x * (1.0 + 1.5 * tol) if i == 40 else x), none, none)
	t.ok(not bool(g["stocks"]["ok"]) and not bool(g["ok"]) and g["stocks"]["metric"] == "backlog",
		"a stock 1.5 tol off at one sample fails: %s at %.0f s" % [str(g["stocks"]["metric"]), float(g["stocks"]["at"])])
	t.ok(bool(g["tallies"]["bone_over"]["ok"]) and bool(g["tallies"]["gold_over"]["ok"]), "while its tallies pass")
	# a tally whose endpoint is under its floor (midgame_2flips' bone: 0.56 against a floor of 1): (a) is
	# judged by the floor there, not by a relative error
	var small := 0.5 * fl / 43200.0
	g = judge.call(_series(func(i: int, y: float) -> float: return y + 0.3 * fl if i > 0 else y, same, small), none, none)
	tr = g["tallies"]["bone_over"]
	t.ok(float(tr["ref_end"]) < fl and bool(tr["a_ok"]) and bool(g["ok"]), "an endpoint under its floor, 0.3 floor off, passes (a): %s" % c._tally_a(tr))
	g = judge.call(_series(func(i: int, y: float) -> float: return y + 1.5 * fl if i > 0 else y, same, small), none, none)
	tr = g["tallies"]["bone_over"]
	t.ok(float(tr["ref_end"]) < fl and not bool(tr["a_ok"]) and not bool(g["ok"]), "and 1.5 floors off fails (a): %s" % c._tally_a(tr))
	# outcomes: the same switches 9.6 s apart pass; a flip only one run has fails
	var o: Dictionary = c._outcome()
	var ro: Dictionary = c._outcome()
	o["unpaid"] = [["lot-02 off", 7709.6], ["lot-02 on", 7809.6]]
	ro["unpaid"] = [["lot-02 off", 7700.0], ["lot-02 on", 7800.0]]
	var flat := _series(same, func(i: int, x: float) -> float: return x)
	t.ok(bool(judge.call(flat, o, ro)["ok"]), "the same upkeep switches 9.6 s apart: the outcomes are equal")
	o["flips"] = [["ashgate", 600.0]]
	g = judge.call(flat, o, ro)
	t.ok(not bool(g["ok"]) and g["outcomes"]["differ"] == ["flips"], "a flip only one run has: they differ (%s)" % str(g["outcomes"]["differ"]))


## A contested Ashgate with no corpses, `living` of her living and no garrison, every other fort full of
## corpses (no living, no room: all the WAR stages at Ashgate), Vei's pool full and a deep dead queue, and
## no wave to come. Her reship is the only living shipped in.
func _ash(living: float) -> RealmSim:
	var all := TestUtil.configs()
	var sim := RealmSim.new()
	sim.setup((all["world"] as Dictionary).duplicate(true), (all["realm"] as Dictionary).duplicate(true))
	sim.vei["living_pool"] = float(sim.t["vei_pool_cap"])
	sim.vei["dead_queue"] = 1e5
	for o in sim.forts:
		o["living"] = 0.0
		o["undead"] = 0.0
		o["dead"] = o["cap"]
	var f := sim.fort_by_id("ashgate")
	sim.hold("ashgate", 0.0)
	f["living"] = living
	f["dead"] = 0.0
	f["undead"] = 0.0
	sim.start_tithe()
	sim.tithe["next_s"] = 1e6
	return sim


## The living at Ashgate (from a start with no garrison) for which U leaves 0 exactly `tb` seconds in,
## and that leave's moment for a start of `living`: t_b = τ · ln((x0 − c·τ) / (x* − c·τ)).
func _living_for(tb: float) -> float:
	var sim := _ash(0.0)
	var f := sim.fort_by_id("ashgate")
	var ct: float = sim.reship_rate(f) * float(sim.t["tithe"]["march_back_s"])
	var xs: float = WAR * Q / float(sim.t["k_destroy"]) - float(f["cap"])
	return float(f["cap"]) + ct + (xs - ct) * exp(tb / float(sim.t["tithe"]["march_back_s"]))


func _leave_exact(living: float) -> float:
	var sim := _ash(living)
	var f := sim.fort_by_id("ashgate")
	var ct: float = sim.reship_rate(f) * float(sim.t["tithe"]["march_back_s"])
	var xs: float = WAR * Q / float(sim.t["k_destroy"]) - float(f["cap"])
	return float(sim.t["tithe"]["march_back_s"]) * log((living - float(f["cap"]) - ct) / (xs - ct))


## Steps `sim` at `dt` until Ashgate's garrison leaves 0 (at most `seconds`): [the time it sat at 0 (its
## zero clock before the step it left in, plus that step's t_undead_back), when it left (s from the
## start), the first fort_retaken's moment or −1].
func _run(sim: RealmSim, dt: float, seconds: float) -> Array:
	var f := sim.fort_by_id("ashgate")
	var el := 0.0
	var zero := -1.0
	var left := -1.0
	var retaken := -1.0
	var inp := {"war": WAR, "digest_q": Q}
	while el < seconds - 1e-9:
		var z0 := float(f["zero_s"])
		sim.step(dt, inp)
		for e in sim.drain_timed():
			if e[1]["type"] == "fort_retaken" and retaken < 0.0:
				retaken = el + float(e[0])
		var tb := float(f.get("t_undead_back", -1.0))
		if left < 0.0 and tb >= 0.0:
			zero = z0 + tb
			left = el + tb
		elif left < 0.0 and float(f["undead"]) > 0.0:
			zero = z0  # left 0 at the step's start (the old rule: the whole step one regime)
			left = el
		el += dt
	return [zero, left, retaken]


## Its time at 0 at 0.25 s, at 10 s (the leave inside the third step) and in one 30 s step is the
## exact t_b within 1e-6 s. Before T3.3a a 10 s step's regime came from its mean pull, so the time
## counted whole steps (20 or 30 s against t_b ≈ 23.7).
func _zero_clock_exact() -> void:
	var living := _living_for(23.7)
	var tb := _leave_exact(living)
	t.near(tb, 23.7, 1e-9, "the start: %.3f of her living at Ashgate, U leaves 0 at t_b = τ · ln((x0 − c·τ) / (x* − c·τ)) = %.6f s" % [living, tb])
	for dt in [0.25, 10.0, 30.0]:
		var r := _run(_ash(living), dt, 30.0)
		t.near(float(r[0]), tb, 1e-6, "dt %s: its time at 0 is t_b (%.6f s; off %s)" % [str(dt), float(r[0]),
			String.num_scientific(absf(float(r[0]) - tb))])
		t.near(float(r[1]), tb, 1e-6, "dt %s: and it leaves 0 at t_b, inside the step (%.6f s)" % [str(dt), float(r[1])])


## The knife-edge: t_b = 117.1 s, under hold.break_s (120). It holds at 0.25 s, and at 10 and 30 s too.
## Before T3.3a the 10 s and 30 s steps that held t_b took the whole step at 0 (their mean pull was
## above the WAR), so the clock reached 120 s and the fort fell where the short steps held it.
func _zero_clock_outcome() -> void:
	var brk := float(TestUtil.configs()["realm"]["hold"]["break_s"])
	var living := _living_for(117.1)
	t.ok(117.1 < brk, "the case: U leaves 0 %.1f s in, %.1f s before hold.break_s" % [117.1, brk - 117.1])
	for dt in [0.25, 10.0, 30.0]:
		var r := _run(_ash(living), dt, 240.0)
		t.ok(float(r[2]) < 0.0, "dt %s: the fort holds (time at 0 %.3f s, left at %.3f s; %s)" % [str(dt), float(r[0]), float(r[1]),
			"never retaken" if float(r[2]) < 0.0 else "retaken at %.1f s" % float(r[2])])
		t.near(float(r[0]), 117.1, 1e-6, "dt %s: its time at 0 is t_b" % str(dt))


## midgame_2flips with no input, 1 h of core steps at 0.5 s and at 10 s (clipped as the convergence
## harness clips, field frozen): the bodies the convoy lands. Its target is Greywall, where Relish
## stands from about 30 s and raises the corpses as they form (her 4 mass/s against 0.2 to 2.2 formed),
## so a convoy that reads them at its moment finds none. A 10 s step's solve leaves about 0.047 there
## (its raise is bounded on the corpses the solve's last pass saw), and the snapshot read that: before
## T3.3a the 10 s run landed 2.68 mass in the hour, the 0.5 s run 0.001. Within 5% of 0.5 s's figure,
## or 0.001 mass when that is 0.
func _convoy_greywall() -> void:
	var c = load("res://tests/slow/convergence.gd").new()
	var js: String = c.start_json("midgame_2flips")
	var got := {}
	for dt in [0.5, 10.0]:
		var s: GameState = c.load_state(js)
		var t0 := s.t
		var landed := 0.0
		while s.t - t0 < 3600.0 - 1e-6:
			var h := minf(dt, 3600.0 - (s.t - t0))
			var e: float = c.next_event_s(s)
			if e > 1e-6 and e < h:
				h = e
			s._core_step(h)
			landed += float(s.town_sim.rates["bodies"]["haul"]) * h
		got[dt] = landed
		t.ok(s.haul_target == "greywall", "dt %s: the convoy's target is Greywall" % str(dt))
	var ref := float(got[0.5])
	var tol := maxf(0.05 * ref, 1e-3)
	t.ok(absf(float(got[10.0]) - ref) <= tol, "midgame_2flips' convoy lands %.6f mass over 1 h at 10 s and %.6f at 0.5 s (within %.4f)" % [
		float(got[10.0]), ref, tol])


## TownSim alone: a convoy back at Covington 1 s into a 1.5 s step leaves again then. Fort a has 10
## corpses its clearing takes at 4 mass/s (dead_rate −4), fort b 8 that stay: at 1 s a has 6 and b 8, so
## the convoy picks b; the snapshot (10 against 8) picked a. Then a pickup at a's own moment: 2 s out, a
## convoy finds a's corpses at 10 − 2 · 2 = 6, not 10; and where they grow (dead_rate +3) it takes the
## 10 a held at the step's start, not 16 (the realm step owns the ones made inside it).
func _convoy_pick() -> void:
	var cfgs := TestUtil.configs()
	var speed := float(cfgs["economy"]["job"]["haul"]["speed"])
	var x := speed * 2.0  # a fort two seconds out
	var fort := func(id: String, dead: float, rate: float) -> Dictionary:
		return {"id": id, "pos": [x, 0.0], "dead": dead, "held": false, "dead_rate": rate}
	var inp := func(forts: Array) -> Dictionary:
		return {"work_mass": 0.0, "relish_home": false, "held_villages": 0, "forts": forts, "cov_pos": [0.0, 0.0],
			"haul_target": "auto", "relics_available": 0}
	var mk := func() -> TownSim:
		var ts := TownSim.new()
		ts.setup(cfgs)
		ts.new_game()
		ts.ladder = ["haul"]
		ts.workers = 3.0
		ts.bodies = 0.0
		return ts
	var s: TownSim = mk.call()
	s.haul["convoys"] = [{"fort": "b", "phase": "back", "t": 0.5, "trip_s": 2.0, "load": 0.0, "crew": 3.0}]
	s.haul["current"] = "b"
	s.step(1.5, inp.call([fort.call("a", 10.0, -4.0), fort.call("b", 8.0, 0.0)]))
	t.ok(s.haul["current"] == "b" and (s.haul["convoys"] as Array).size() == 1 and float(s.haul["convoys"][0]["t"]) > 0.0,
		"leaving 1 s into the step the convoy picks b (8 corpses) over a (10 at the step's start, 6 then): %s" % s.haul["current"])
	for c in [[-2.0, 6.0], [3.0, 10.0], [0.0, 10.0]]:
		s = mk.call()
		var o := s.step(3.0, inp.call([fort.call("a", 10.0, c[0])]))
		var got := 0.0
		for p in o["pickups"]:
			got += float(p["mass"])
		t.near(got, c[1], 1e-9, "a pickup 2 s into the step at a fort with 10 corpses and dead_rate %+.0f takes %.0f" % [c[0], c[1]])


## The projection reads only saved state (RealmSim.dead_rates: the forts' pools, their r_shipped and r_in,
## Relish's redirect, the simulacra, q), so a load doesn't change the convoy's view: every fort's
## dead_rate in TownSim's snapshot is the same after a JSON round trip, within the save's 15-digit
## rounding of the state it reads (1e-12 relative; a session-only rate, r_kills, would read 0 after a
## load). midgame_2flips 60 s in (Relish raising at Greywall, forts with and without living), and pre_vei
## (forts with no living, whose kills are what Vei shipped in last step).
func _convoy_after_load() -> void:
	var c = load("res://tests/slow/convergence.gd").new()
	for st in ["midgame_2flips", "pre_vei"]:
		var s: GameState = c.load_state(c.start_json(st))
		for i in 120:
			s._core_step(0.5)
		var a: Array = []
		for f in s._town_inputs(0.0)["forts"]:
			a.append(float(f["dead_rate"]))
		var b: Array = []
		for f in c.load_state(JSON.stringify(s.to_dict()))._town_inputs(0.0)["forts"]:
			b.append(float(f["dead_rate"]))
		var moving := 0
		var worst := 0.0
		for i in a.size():
			if float(a[i]) != 0.0:
				moving += 1
			worst = maxf(worst, absf(float(a[i]) - float(b[i])) / maxf(1.0, absf(float(a[i]))))
		t.ok(a.size() == b.size() and worst <= 1e-12 and moving > 0, "%s: every fort's dead_rate is the same after a save and load (%d of %d non-zero; worst %s)" % [
			st, moving, a.size(), String.num_scientific(worst)])
