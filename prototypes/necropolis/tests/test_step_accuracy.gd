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

var t := TestUtil.new()
const Q := 1.2  # digest_q for the realm cases
const WAR := 0.6  # mass/s of WAR, all of it staged at the contested fort


func run() -> int:
	t.suite("step_accuracy")
	_zero_clock_exact()
	_zero_clock_outcome()
	return t.failures


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
