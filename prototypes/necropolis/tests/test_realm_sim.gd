extends RefCounted
## RealmSim alone (MECHANICS §3, §10): the canonical port, the necropolis extensions and the E2a
## macro streams. step(dt, inputs) is pure on its inputs, so every case drives it directly.


func _mk(overrides := {}) -> RealmSim:
	var all := TestUtil.configs()
	var cfg: Dictionary = (all["realm"] as Dictionary).duplicate(true)
	for k in overrides:
		cfg[k] = overrides[k]
	var world: Dictionary = (all["world"] as Dictionary).duplicate(true)
	var sim := RealmSim.new()
	sim.setup(world, cfg)
	return sim


func _share_ratio(sim: RealmSim, a: Dictionary, b: Dictionary) -> float:
	return a["r_in"] / b["r_in"] if b["r_in"] > 0.0 else -1.0


func run() -> int:
	var t := TestUtil.new()
	t.suite("realm_sim")

	# --- conservation with every source and sink off ---------------------------
	var sim := _mk({"k_clear": 0.0})
	var before := sim.total_matter()
	for i in 200:
		sim.step(0.5, {})
	t.near(sim.total_matter(), before, 1e-6, "matter conserved with inputs 0 and k_clear 0")
	t.ok(sim.cov["undead"] == 0.0 and sim.cov["r_out"] == 0.0, "nothing waits at Covington")

	# --- the critical asymmetry ----------------------------------------------
	sim = _mk({"k_clear": 0.0, "r_drain": 0.0, "S_vei": 0.0, "R_vei": 0.0})
	var f: Dictionary = sim.forts[0]
	f["living"] = 50.0
	f["undead"] = 30.0
	f["dead"] = 0.0
	var dead_q0: float = sim.vei["dead_queue"]
	sim.step(1.0, {})
	t.ok(f["dead"] > 0.0, "undead kills stay at the fortress as dead")
	t.ok(sim.vei["dead_queue"] > dead_q0, "garrison kills are shipped to Vei")

	# --- break-even undead fraction u* = k_destroy / (q k_kill), q from the inputs
	var q := 1.5
	var u_star: float = 0.006 / (q * 0.018)
	sim = _mk({"k_clear": 0.0, "r_drain": 0.0})
	f = sim.forts[0]
	f["living"] = 100.0
	f["undead"] = 100.0 * u_star * 1.3
	sim.step(0.1, {"digest_q": q})
	t.ok(f["r_kills"] > f["r_dead_out"], "above u* Relish banks more than she gifts")
	t.near(f["r_dead_out"], 0.006 * 100.0 / q, 1e-3 * 0.006 * 100.0 / q, "the garrison's kills fall with digest_q (k_destroy · L̄ / q: living falls a little in the step)")
	f["living"] = 100.0
	f["undead"] = 100.0 * u_star * 0.7
	sim.step(0.1, {"digest_q": q})
	t.ok(f["r_kills"] < f["r_dead_out"], "below u* the trade feeds Vei")

	# --- vei policy cheap: corpses digested first ----------------------------
	sim = _mk({"veiPolicy": "cheap", "R_vei": 10.0, "S_vei": 0.0})
	sim.vei["dead_queue"] = 100.0
	sim.vei["undead_queue"] = 100.0
	var uq0: float = sim.vei["undead_queue"]
	sim.step(1.0, {})
	t.near(sim.vei["dead_queue"], 90.0 + sim.vei["r_in_dead"], 1e-9, "cheap policy eats the dead queue first")
	t.near(sim.vei["undead_queue"], uq0 + sim.vei["r_in_undead"], 1e-9, "cheap policy leaves undead queued while dead remain")

	# --- shipping only into empty space --------------------------------------
	sim = _mk({"S_vei": 1000.0})
	sim.vei["living_pool"] = 10000.0
	for ff in sim.forts:
		ff["living"] = ff["cap"] * 0.5
		ff["dead"] = ff["cap"] * 0.5
	sim.step(1.0, {})
	var over := false
	for ff in sim.forts:
		if ff["living"] + ff["dead"] + ff["undead"] > ff["cap"] + 0.01:
			over = true
	t.ok(not over, "Vei never ships living beyond fortress space (EMPTY respected)")

	# --- clearing removes corpses --------------------------------------------
	sim = _mk({"k_clear": 0.1, "k_kill": 0.0})
	f = sim.forts[0]
	f["living"] = 100.0
	f["dead"] = 50.0
	sim.step(1.0, {})
	t.ok(f["dead"] < 50.0 and sim.cleared_total > 0.0, "garrison clears corpses over time")

	# --- the pool cap: a full pool stalls her; a near-full one takes only its headroom
	sim = _mk({"vei_pool_cap": 100.0, "S_vei": 0.0})
	sim.vei["living_pool"] = 100.0
	sim.vei["undead_queue"] = 500.0
	sim.step(1.0, {})
	t.near(sim.vei["undead_queue"], 500.0 + sim.vei["r_in_undead"], 1e-9, "a full living pool stalls Vei's digestion")
	for policy in ["cheap", "threat", "proportional"]:
		sim = _mk({"vei_pool_cap": 100.0, "S_vei": 0.0, "R_vei": 1000.0, "k_clear": 0.0, "veiPolicy": policy})
		sim.vei["living_pool"] = 95.0
		sim.vei["undead_queue"] = 500.0
		sim.vei["dead_queue"] = 500.0
		before = sim.total_matter()
		sim.step(1.0, {"digest_q": 1.5})
		t.near(sim.vei["living_pool"], 100.0, 1e-9, "%s: she converts exactly her headroom, no more" % policy)
		t.near(sim.vei["r_converted"], 5.0, 1e-9, "%s: take = headroom (5)" % policy)
		t.near(sim.total_matter(), before, 1e-6, "%s: nothing is discarded at the cap" % policy)

	# --- WAR dispatch: the distance split and the tide -------------------------
	sim = _mk({"S_vei": 0.0})
	sim.step(1.0, {"war": 10.0})
	var sum_in := 0.0
	for ff in sim.forts:
		sum_in += ff["r_in"]
	t.near(sum_in, 10.0, 1e-9, "all WAR lands on the forts (Σ r_in = war)")
	t.ok(sim.war_route == "forts" and sim.r_war_to_vei == 0.0, "route: forts")
	var a: Dictionary = sim.forts[0]
	var b: Dictionary = sim.forts[1]
	var da: float = sim.cov_pos.distance_to(a["pos"])
	var db: float = sim.cov_pos.distance_to(b["pos"])
	t.near(_share_ratio(sim, a, b), db / da, 1e-9, "the split is by 1/(dist/100)^covFalloff")
	var plain := _share_ratio(sim, a, b)
	sim = _mk({"S_vei": 0.0})
	sim.step(1.0, {"war": 10.0, "tide_fort": a["id"], "tide_bias": 3.0})
	t.near(_share_ratio(sim, sim.forts[0], sim.forts[1]), plain * 3.0, 1e-9, "the tide multiplies her fort's weight by tide_bias")
	sum_in = 0.0
	for ff in sim.forts:
		sum_in += ff["r_in"]
	t.near(sum_in, 10.0, 1e-9, "the tide moves WAR, it does not add any")
	sim = _mk({"S_vei": 0.0})
	sim.step(1.0, {"war": 10.0, "tide_fort": a["id"]})
	t.near(_share_ratio(sim, sim.forts[0], sim.forts[1]), plain, 1e-9, "a missing tide_bias is neutral (1)")

	# --- WAR with no living target: staging at held forts, else Vei ------------
	sim = _mk({"S_vei": 0.0, "R_vei": 0.0, "k_clear": 0.0, "r_drain": 0.0})
	for ff in sim.forts:
		ff["living"] = 0.0
	var h1: Dictionary = sim.forts[2]
	var h2: Dictionary = sim.forts[5]
	sim.hold(h1["id"], 100.0)
	sim.hold(h2["id"], 100.0)
	var uq := float(sim.vei["undead_queue"])
	var u1: float = h1["undead"]
	sim.step(1.0, {"war": 6.0})
	t.ok(sim.war_route == "staged", "no living target: WAR stages at the held forts")
	t.near(h1["r_staged"] + h2["r_staged"], 6.0, 1e-9, "every bit of WAR stages")
	t.ok(h1["r_in"] == h1["r_staged"], "staging shows as the fort's r_in (war_in)")
	t.near(h1["undead"] - u1, h1["r_staged"], 1e-9, "staging lands in the held fort's undead")
	var d1: float = sim.cov_pos.distance_to(h1["pos"])
	var d2: float = sim.cov_pos.distance_to(h2["pos"])
	t.near(h1["r_staged"] / h2["r_staged"], d2 / d1, 1e-9, "staging is split by the same distance weight")
	t.near(sim.vei["undead_queue"], uq, 1e-9, "no WAR reaches Vei while a fort is held")
	t.ok(sim.forts[0]["r_staged"] == 0.0 and sim.forts[0]["r_in"] == 0.0, "an unheld empty fort takes nothing")
	sim.hold(h1["id"], 0.0)
	sim.hold(h2["id"], 0.0)
	uq = float(sim.vei["undead_queue"])
	sim.step(1.0, {"war": 6.0, "flood": 2.0})
	t.ok(sim.war_route == "vei", "nothing held either: WAR falls through to Vei")
	t.near(sim.r_war_to_vei, 6.0, 1e-9, "the fall-through is recorded (r_war_to_vei)")
	t.near(sim.vei["undead_queue"] - uq, 8.0, 1e-9, "WAR and FLOOD both reach the undead queue")
	t.near(sim.readout()["inflow"], 8.0, 1e-9, "inflow = drain + FLOOD + fall-through")

	# --- held forts always pull WAR: staging alongside the forts with living ----
	sim = _mk({"S_vei": 0.0, "R_vei": 0.0, "k_clear": 0.0, "r_drain": 0.0})
	h1 = sim.forts[2]
	h1["living"] = 0.0
	sim.hold(h1["id"], 100.0)
	sim.step(1.0, {"war": 10.0})
	var near_f: Dictionary = sim.forts[0]
	t.ok(sim.war_route == "forts" and h1["r_staged"] > 0.0 and h1["r_in"] == h1["r_staged"],
		"a held fort stages WAR while other forts have living (route forts)")
	d1 = sim.cov_pos.distance_to(h1["pos"])
	var d0: float = sim.cov_pos.distance_to(near_f["pos"])
	t.near(h1["r_in"] / near_f["r_in"], d0 / d1, 1e-9, "at its distance weight, like any target")
	t.ok(near_f["r_staged"] == 0.0, "only held forts record staging")
	sum_in = 0.0
	for ff in sim.forts:
		sum_in += ff["r_in"]
	t.near(sum_in, 10.0, 1e-9, "staging is a share of WAR, not extra")
	var ratio_empty: float = h1["r_in"] / near_f["r_in"]
	h1["living"] = 10.0
	sim.step(1.0, {"war": 10.0})
	t.near(h1["r_in"] / near_f["r_in"], ratio_empty, 1e-9, "a held fort with living is weighted once, not twice")
	sim.step(1.0, {"war": 10.0, "tide_fort": h1["id"], "tide_bias": 3.0})
	t.near(h1["r_in"] / near_f["r_in"], ratio_empty * 3.0, 1e-9, "the tide multiplies a held fort's staging too")
	t.ok(sim.vei["undead_queue"] == 0.0 and sim.r_war_to_vei == 0.0, "nothing falls through while there is a target")

	# --- the readout's digestion and the partial-headroom capacity -------------
	sim = _mk({"vei_pool_cap": 100.0, "S_vei": 0.0, "R_vei": 1000.0, "k_clear": 0.0, "veiPolicy": "cheap"})
	sim.vei["living_pool"] = 95.0
	sim.vei["undead_queue"] = 500.0
	sim.vei["dead_queue"] = 2.0
	sim.step(1.0, {"digest_q": 2.0})
	t.near(sim.r_digested_undead, 3.0, 1e-9, "digestion = the undead she took (headroom 5 less 2 dead)")
	t.near(sim.readout()["capacity"], 3.0, 1e-9, "capacity: the headroom left after the dead, per second (not R/q = 500)")
	sim = _mk({"vei_pool_cap": 1e6, "S_vei": 0.0, "R_vei": 50.0, "k_clear": 0.0})
	sim.vei["undead_queue"] = 10.0
	sim.step(0.5, {"digest_q": 2.0})
	t.near(sim.r_digested_undead, 10.0 / 0.5, 1e-9, "digestion is what she took (the whole small queue)")
	t.near(sim.readout()["capacity"], 25.0, 1e-9, "capacity is R/q with room to spare")

	# --- a retake refreshes the yield ------------------------------------------
	sim = _mk({})
	f = sim.forts[1]
	f["clears_since_retaken"] = 3
	sim.hold(f["id"], 0.5)
	sim.step(0.5, {})
	t.ok(f["clears_since_retaken"] == 0 and sim.drain_events().size() == 1, "an expiry resets clears_since_retaken")

	# --- tithe waves --------------------------------------------------------------
	_tithe(t)
	_wave_timing(t)

	# --- E2b: the step is exact at any dt -------------------------------------------
	_long_steps(t)
	_room(t)
	_march_back(t)

	# --- FLOOD goes straight to the queue -------------------------------------
	sim = _mk({"S_vei": 0.0, "R_vei": 0.0, "r_drain": 0.0})
	uq = float(sim.vei["undead_queue"])
	sim.step(0.5, {"flood": 4.0})
	t.near(sim.vei["undead_queue"] - uq, 2.0, 1e-9, "FLOOD adds flood·dt to the undead queue")
	t.near(sim.cov["r_out"], 4.0, 1e-9, "cov.r_out is what Covington sent (WAR + FLOOD)")

	# --- Relish's redirect: kills stay, she raises at the rate into undead -----
	sim = _mk({"k_kill": 0.0, "k_clear": 0.0, "r_drain": 0.0, "S_vei": 0.0, "R_vei": 0.0})
	f = sim.forts[0]
	var other: Dictionary = sim.forts[1]
	f["living"] = 60.0
	f["undead"] = 20.0
	f["dead"] = 10.0
	other["undead"] = 20.0
	var dq0: float = sim.vei["dead_queue"]
	sim.step(1.0, {"redirect_fort": f["id"], "redirect_rate": 4.0})
	var destroyed: float = 0.006 * 60.0
	t.near(f["r_redirected"], destroyed, 1e-9, "garrison kills at her fort are kept (r_redirected)")
	t.ok(f["r_dead_out"] == 0.0, "nothing ships to Vei from her fort")
	t.near(sim.vei["dead_queue"] - dq0, other["r_dead_out"], 1e-9, "other forts still ship their garrison kills")
	t.near(f["r_raised"], 4.0, 1e-9, "she raises at redirect_rate")
	t.near(f["dead"], 10.0 + destroyed - 4.0, 1e-9, "the raise comes out of the fort's dead")
	t.near(f["undead"], 20.0 - destroyed + 4.0, 1e-9, "and goes into the fort's undead pool")
	f["dead"] = 1.0
	sim.step(1.0, {"redirect_fort": f["id"], "redirect_rate": 4.0})
	t.near(f["r_raised"], 1.0 + 0.006 * f["living"], 1e-6, "the raise is bounded by the fort's dead")
	t.ok(f["dead"] >= 0.0, "never below zero")

	# --- simulacra: the same redirect at their own rate, until charges run out --
	sim = _mk({"k_kill": 0.0, "k_destroy": 0.0, "k_clear": 0.0, "r_drain": 0.0})
	f = sim.forts[0]
	f["dead"] = 100.0
	var u0: float = f["undead"]
	sim.simulacra = [{"fort_id": f["id"], "charges": 10.0, "rate": 5.0}]
	sim.step(1.0, {})
	t.near(f["dead"], 95.0, 1e-9, "simulacrum raises at its rate")
	t.near(f["undead"] - u0, 5.0, 1e-9, "into the fort's undead, not Vei's queue")
	sim.step(1.0, {})
	t.ok(sim.simulacra.is_empty(), "simulacrum vanishes when charges run out")
	t.near(f["dead"], 90.0, 1e-9, "simulacrum stopped at exactly its charge count")
	t.near(sim.raised_by_sims, 10.0, 1e-9, "raised_by_sims counts it")
	sim = _mk({"k_kill": 0.0, "k_clear": 0.0, "r_drain": 0.0, "S_vei": 0.0})
	f = sim.forts[0]
	f["living"] = 60.0
	f["undead"] = 20.0
	f["dead"] = 0.0
	sim.simulacra = [{"fort_id": f["id"], "charges": 50.0, "rate": 0.1}]
	sim.step(1.0, {})
	t.ok(f["r_dead_out"] == 0.0 and f["r_redirected"] > 0.0, "a simulacrum keeps its fort's garrison kills too")
	sim.simulacra = []
	sim.step(1.0, {})
	t.ok(f["r_dead_out"] > 0.0 and f["r_redirected"] == 0.0, "once it is gone they ship again")

	# --- shipping: per-fort capacity share; a held fort's share is lost --------
	var pair: Array[RealmSim] = [_mk({"S_vei": 8.0}), _mk({"S_vei": 8.0})]
	var sum_cap := 0.0
	for ff in pair[0].forts:
		sum_cap += ff["cap"]
	for s in pair:
		s.vei["living_pool"] = 500.0
		for ff in s.forts:
			ff["living"] = ff["cap"] * 0.2
			ff["undead"] = 0.0
			ff["dead"] = 0.0
	pair[1].hold(pair[1].forts[3]["id"], 60.0)
	for s in pair:
		s.step(0.5, {})
	var free: Dictionary = pair[0].forts[3]
	t.near(free["r_shipped"], 8.0 * free["cap"] / sum_cap, 1e-9, "a fort receives S_vei · cap_i / Σcap")
	t.ok(pair[1].forts[3]["r_shipped"] == 0.0, "a held fort gets no shipping")
	t.near(pair[0].vei["r_shipped"] - pair[1].vei["r_shipped"], free["r_shipped"], 1e-9, "Σ shipped drops by the held share")
	t.near(pair[1].forts[4]["r_shipped"], pair[0].forts[4]["r_shipped"], 1e-12, "the held share is not redistributed")
	t.ok(pair[1].forts[3]["held"] == true and pair[0].forts[3]["held"] == false, "held is visible in the fort dict")

	# --- hold expiry emits fort_retaken{expired} --------------------------------
	sim = _mk({})
	f = sim.forts[1]
	t.ok(sim.hold(f["id"], 1.0) and not sim.hold("nowhere", 1.0), "hold() takes a known fort only")
	sim.step(0.5, {})
	t.near(f["held_s"], 0.5, 1e-12, "held_s counts down in step")
	t.ok(sim.drain_events().is_empty() and f["held"], "still held, no event")
	sim.step(0.5, {})
	var evs := sim.drain_events()
	t.ok(evs == [{"type": "fort_retaken", "fort_id": f["id"], "cause": "expired"}],
		"expiry records fort_retaken{cause: expired} without t: %s" % str(evs))
	t.ok(f["held_s"] == 0.0 and not f["held"] and sim.drain_events().is_empty(), "unheld; the queue is drained")
	sim.step(0.5, {})
	t.ok(sim.drain_events().is_empty(), "no repeat event")

	# --- a long run with random inputs: no negatives, mass accounted -----------
	sim = _mk({})
	sim.start_tithe()  # surges run too
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	before = sim.total_matter()
	var added := 0.0
	var neg := false
	var over_pool := false
	var surged := 0.0
	var lost := 0.0  # the march-back past her pool's cap
	var ids: Array = sim.forts.map(func(x): return x["id"])
	for i in 4000:
		var dt := 0.5
		if rng.randf() < 0.01:
			sim.hold(ids[rng.randi_range(0, ids.size() - 1)], rng.randf_range(5.0, 120.0))
		if rng.randf() < 0.005:
			sim.simulacra.append({"fort_id": ids[rng.randi_range(0, ids.size() - 1)], "charges": 40.0, "rate": 3.0})
		var war := rng.randf_range(0.0, 20.0)
		var flood := rng.randf_range(0.0, 5.0)
		var inp := {"war": war, "flood": flood, "digest_q": rng.randf_range(1.0, 4.0),
			"tide_fort": ids[rng.randi_range(0, ids.size() - 1)] if rng.randf() < 0.5 else "", "tide_bias": 3.0,
			"redirect_fort": ids[rng.randi_range(0, ids.size() - 1)] if rng.randf() < 0.5 else "", "redirect_rate": 4.0}
		sim.step(dt, inp)
		added += (war + flood) * dt
		lost += sim.pool_overflow
		for ff in sim.forts:
			if ff["living"] < -1e-9 or ff["dead"] < -1e-9 or ff["undead"] < -1e-9 or ff["held_s"] < 0.0:
				neg = true
		for k in ["undead_queue", "dead_queue", "living_pool"]:
			if sim.vei[k] < -1e-9:
				neg = true
		if sim.vei["living_pool"] > float(sim.t["vei_pool_cap"]) + 1e-9:
			over_pool = true
		for ff in sim.forts:
			surged += ff["r_surge"] * dt
		sim.drain_events()
	t.ok(surged > 0.0, "tithe surges ran during the soak (%.0f mass)" % surged)
	t.ok(not neg, "no negative pool after 2000 s of random inputs, holds, simulacra and tithe waves")
	t.ok(not over_pool, "Vei's pool never exceeds its cap")
	t.near(sim.total_matter(), before + added - sim.cleared_total - lost, 1e-6 * maxf(1.0, before + added),
		"matter: start + WAR + FLOOD − cleared − her pool's overflow (%.1f)" % lost)
	t.ok(sim.readout()["odds"] >= 0.0 and sim.readout()["odds"] < 1.0, "odds in [0,1)")
	t.ok(not sim.readout().has("directShare") and not sim.t.has("directShare"), "directShare is gone")

	return t.failures


## Steps `sim` at dt 0.5 with `inp` until an event of `type` appears (at most `max_s`). Returns
## [elapsed when it appeared, the event], or [-1.0, {}].
func _until(sim: RealmSim, type: String, inp: Dictionary, max_s: float) -> Array:
	var start := sim.elapsed
	while sim.elapsed - start < max_s:
		sim.step(0.5, inp)
		for ev in sim.drain_events():
			if ev["type"] == type:
				return [sim.elapsed, ev]
	return [-1.0, {}]


## A sim for tithe cases: no combat, no drain or clearing (masses stay where the test puts them),
## a deep pool so the surge is never pool-bound unless the test says so.
func _tsim(over := {}) -> RealmSim:
	var o := {"k_kill": 0.0, "k_destroy": 0.0, "k_clear": 0.0, "r_drain": 0.0, "R_vei": 0.0, "vei_pool_cap": 1e9}
	o.merge(over, true)
	var sim := _mk(o)
	sim.vei["living_pool"] = 1e6
	return sim


## The target of a warning raised at once (the clock forced to the warning point).
func _target_now(sim: RealmSim, inp: Dictionary) -> String:
	sim.start_tithe()
	sim.tithe["next_s"] = 1.0
	sim.drain_events()
	sim.step(0.5, inp)
	for ev in sim.drain_events():
		if ev["type"] == "tithe_warning":
			return ev["fort_id"]
	return "?"


func _tithe(t: TestUtil) -> void:
	var tc: Dictionary = TestUtil.configs()["realm"]["tithe"]
	var period := float(tc["period_s"])
	var warn := float(tc["warning_s"])
	var surge_s := float(tc["surge_s"])
	var base: float = float(tc["surge_mult"]) * float(TestUtil.configs()["realm"]["S_vei"])

	# no wave before the first flip
	var sim := _tsim()
	var r := _until(sim, "tithe_warning", {"war": 5.0}, 3.0 * period)
	t.ok(r[0] < 0.0 and not sim.tithe["started"], "no tithe before the first flip (%.0f s of WAR)" % (3.0 * period))

	# the clock: the first wave one period after the flip, its warning warning_s before
	sim = _tsim()
	var held: Dictionary = sim.forts[1]
	sim.hold(held["id"], 1e6)
	sim.start_tithe()
	t.near(sim.tithe["next_s"], period, 1e-9, "start_tithe: the first wave is period_s away at odds 0")
	sim.start_tithe()
	t.near(sim.tithe["next_s"], period, 1e-9, "a running cycle is not restarted")
	var w := _until(sim, "tithe_warning", {}, period)
	t.near(w[0], period - warn, 1e-9, "the warning comes warning_s before the wave")
	t.ok(w[1] == {"type": "tithe_warning", "wave_id": 1, "fort_id": held["id"], "eta_s": warn, "surge": base},
		"tithe_warning {wave_id, fort_id, eta_s, surge before counters}: %s" % str(w[1]))
	t.ok(typeof(w[1]["wave_id"]) == TYPE_INT and typeof(w[1]["eta_s"]) == TYPE_FLOAT, "wave_id int, eta_s float")
	# the target stays fixed: another fort is held with far more undead before the wave
	var other: Dictionary = sim.forts[4]
	other["undead"] = 1e5
	sim.hold(other["id"], 1e6)
	var wv := _until(sim, "tithe_wave", {}, period)
	t.near(wv[0] - w[0], warn, 1e-9, "the wave starts warning_s after its warning")
	t.ok(wv[1]["fort_id"] == held["id"] and wv[1]["wave_id"] == 1, "the warned target stays fixed for its wave")
	t.ok(wv[1] == {"type": "tithe_wave", "wave_id": 1, "fort_id": held["id"], "surge": base, "duration_s": surge_s,
		"relish_here": false, "siege_block": 0.0}, "tithe_wave {wave_id, fort_id, surge, duration_s, relish_here, siege_block}: %s" % str(wv[1]))
	t.near(sim.tithe["next_s"], period, 1e-9, "the next wave is scheduled start to start")

	# the target rule: held forts first, the most undead, ties in world order
	sim = _tsim()
	sim.hold(sim.forts[3]["id"], 1e6)
	sim.hold(sim.forts[6]["id"], 1e6)
	sim.forts[3]["undead"] = 5.0
	sim.forts[6]["undead"] = 9.0
	t.ok(_target_now(sim, {"war": 5.0}) == sim.forts[6]["id"], "held first: the held fort with the most undead")
	sim = _tsim()
	sim.hold(sim.forts[3]["id"], 1e6)
	sim.hold(sim.forts[6]["id"], 1e6)
	sim.forts[3]["undead"] = 7.0
	sim.forts[6]["undead"] = 7.0
	t.ok(_target_now(sim, {}) == sim.forts[3]["id"], "a tie between held forts goes to world order")
	sim = _tsim()
	var far: Dictionary = sim.forts[8]
	t.ok(_target_now(sim, {"war": 5.0, "tide_fort": far["id"], "tide_bias": 100.0}) == far["id"],
		"nothing held: the fort receiving the most WAR now (the tide pulled it far)")
	sim = _tsim()
	t.ok(_target_now(sim, {"war": 5.0}) == sim.forts[0]["id"], "nothing held, no tide: the nearest fort gets most WAR")
	sim = _tsim()
	t.ok(_target_now(sim, {}) == sim.forts[0]["id"], "no WAR anywhere: all tied at 0, world order")

	# the period shrinks as her odds rise
	sim = _tsim()
	var k := float(sim.t["K"])
	sim.vei["undead_queue"] = k  # odds 0.5
	sim.start_tithe()
	t.near(sim.tithe["next_s"], period * (1.0 - float(tc["backlog_scale"]) * 0.5), 1e-9, "period · (1 − backlog_scale · odds)")
	t.near(sim.tithe_period(), 315.0, 1e-9, "315 s at odds 0.5 (420 at odds 0)")

	# the surge: size, Relish halves it, a siege blocks its share; it ignores the share, the space and
	# the cap (Whitecross is full of living; what goes past its cap marches back, _march_back)
	for c in [["plain", {}, 1.0, false, 0.0], ["Relish", {"tide_fort": "@"}, 0.5, true, 0.0],
			["siege", {"siege_block": {"@": 0.6}}, 0.4, false, 0.6], ["both", {"tide_fort": "@", "siege_block": {"@": 0.6}}, 0.2, true, 0.6]]:
		sim = _tsim()
		var tgt: Dictionary = sim.forts[10]
		tgt["living"] = tgt["cap"]  # no space: the surge goes in anyway
		var inp := {}
		for key in c[1]:
			inp[key] = c[1][key]
		if inp.has("tide_fort"):
			inp["tide_fort"] = tgt["id"]
		if inp.has("siege_block"):
			inp["siege_block"] = {tgt["id"]: 0.6}
		sim.start_tithe()
		sim.tithe["next_s"] = 1.0
		sim.step(0.5, {"war": 5.0, "tide_fort": tgt["id"], "tide_bias": 1000.0})  # the warning picks tgt
		t.ok(sim.tithe["warning"]["fort_id"] == tgt["id"], "%s: warned on the test fort" % c[0])
		var ev := _until(sim, "tithe_wave", inp, 10.0)
		t.ok(absf(ev[1]["surge"] - base * c[2]) < 1e-9 and ev[1]["relish_here"] == c[3] and ev[1]["siege_block"] == c[4],
			"%s: tithe_wave surge %.1f, relish_here %s, siege_block %.1f: %s" % [c[0], base * c[2], c[3], c[4], str(ev[1])])
		t.ok(tgt["r_surge"] == 0.0, "%s: the step that ends at the wave's start delivers none of it" % c[0])
		sim.step(0.5, inp)
		t.near(tgt["r_surge"], base * c[2], 1e-9, "%s: surge_mult · S_vei × counters living/s" % c[0])
		t.ok(tgt["living"] > tgt["cap"], "%s: past the fort's space" % c[0])
		var delivered: float = tgt["r_surge"] * 0.5
		var guard := 1
		while not (sim.tithe["wave"] as Dictionary).is_empty() and guard < 1000:
			sim.step(0.5, inp)
			delivered += tgt["r_surge"] * 0.5
			guard += 1
		t.near(delivered, base * c[2] * surge_s, 1e-6, "%s: the wave delivers rate × surge_s" % c[0])
		sim.step(0.5, inp)
		t.ok(tgt["r_surge"] == 0.0 and guard == int(surge_s / 0.5), "%s: then stops, after surge_s" % c[0])
	# the surge comes out of her pool and is bounded by it; held forts get it (not the shipping share)
	sim = _tsim({"S_vei": 8.0})
	var hf: Dictionary = sim.forts[2]
	sim.hold(hf["id"], 1e6)
	sim.start_tithe()
	sim.tithe["next_s"] = 0.25
	sim.vei["living_pool"] = 5.0
	var before := sim.total_matter()
	sim.step(0.5, {})
	t.near(hf["r_surge"], 5.0 / 0.5, 1e-9, "bounded by her pool (5 mass of the 6 the wave's first 0.25 s want)")
	t.ok(sim.vei["living_pool"] == 0.0 and hf["r_shipped"] == hf["r_surge"], "the pool empties into the held fort; r_shipped carries the surge")
	t.near(sim.total_matter(), before, 1e-9, "the surge moves mass, it makes none")

	# the hold: kept when the garrison outlasts what the wave delivers, lost (with the event) when
	# overwhelmed. The wave delivers all of itself (no combat or drain here; the march-back doesn't
	# change what it delivered), so a garrison at the fort's full cap loses to a full wave (960) at
	# every fort; with Relish there (a 480 wave) it keeps the hold only where cap > 480 (MECHANICS §3.4)
	for c in [["outlasts", 10, 1000.0, {}, true], ["overwhelmed", 10, 100.0, {}, false],
			["Relish saves it", 10, 600.0, {"tide_fort": "@"}, true], ["no Relish", 10, 600.0, {}, false],
			["Greywall full garrison", 2, -1.0, {}, false], ["Greywall full garrison, Relish", 2, -1.0, {"tide_fort": "@"}, false],
			["Whitecross full garrison", 10, -1.0, {}, false], ["Whitecross full garrison, Relish", 10, -1.0, {"tide_fort": "@"}, true]]:
		sim = _tsim()
		hf = sim.forts[c[1]]
		hf["clears_since_retaken"] = 2
		sim.hold(hf["id"], 1e6)
		hf["living"] = 0.0
		hf["dead"] = 0.0
		hf["undead"] = c[2] if c[2] >= 0.0 else hf["cap"]
		var garrison: float = hf["undead"]
		var expect_in: float = base * surge_s * (0.5 if c[3].has("tide_fort") else 1.0)
		var inp: Dictionary = {"tide_fort": hf["id"]} if c[3].has("tide_fort") else {}
		sim.start_tithe()
		sim.tithe["next_s"] = 1.0
		sim.drain_events()
		var got: Array = []
		var delivered := 0.0
		for i in 200:
			sim.step(0.5, inp)
			delivered += float(hf["r_surge"]) * 0.5
			got.append_array(sim.drain_events().filter(func(e): return e["type"] == "fort_retaken"))
		t.ok(hf["held"] == c[4] and got.size() == (0 if c[4] else 1) and absf(delivered - expect_in) < 1e-6,
			"%s: garrison %.0f vs %.0f delivered (cap %.0f): held %s" % [c[0], garrison, delivered, hf["cap"], c[4]])
		if not c[4]:
			t.ok(got[0] == {"type": "fort_retaken", "fort_id": hf["id"], "cause": "tithe_wave"} and hf["clears_since_retaken"] == 0
				and hf["held_s"] == 0.0, "%s: fort_retaken{tithe_wave}; the yield refreshes" % c[0])
	# one retake per step: a wave that ends a hold in the step it would also expire
	sim = _tsim()
	hf = sim.forts[2]
	sim.hold(hf["id"], 1e6)
	sim.start_tithe()
	sim.tithe["next_s"] = 1.0
	_until(sim, "tithe_wave", {}, 10.0)
	sim.hold(hf["id"], surge_s - 0.25)  # the wave began at the event step's end: 0.25 s of hold left when its last step begins, so both end it there
	var all: Array = []
	for i in 100:
		sim.step(0.5, {})
		all.append_array(sim.drain_events().filter(func(e): return e["type"] == "fort_retaken"))
	t.ok(all.size() == 1 and all[0]["cause"] == "tithe_wave", "exactly one fort_retaken when the wave and the expiry coincide: %s" % str(all))

	# load_tithe: the saved shape, the E1 placeholder, an empty block
	sim = _tsim()
	sim.start_tithe()
	sim.tithe["next_s"] = 1.0
	sim.step(0.5, {})
	var saved: Dictionary = JSON.parse_string(JSON.stringify(sim.tithe))
	var back := _tsim()
	back.load_tithe(saved, false)
	t.ok(back.tithe == sim.tithe and typeof(back.tithe["next_id"]) == TYPE_INT
		and typeof(back.tithe["warning"]["wave_id"]) == TYPE_INT, "the saved shape round-trips through JSON with its types")
	back = _tsim()
	back.load_tithe({"warning": {"wave_id": 1.0, "fort_id": "ashgate", "eta_s": 150.0, "surge": 24.0}}, true)
	t.ok(back.tithe == {"started": true, "next_s": 150.0, "next_id": 2, "wave": {},
		"warning": {"wave_id": 1, "fort_id": "ashgate", "eta_s": 150.0, "surge": 24.0}}, "the E1 placeholder becomes a pending warning: %s" % str(back.tithe))
	back = _tsim()
	back.load_tithe({}, true)
	t.ok(back.tithe["started"] and back.tithe["next_s"] == period, "an empty block with a flipped fort starts the clock at load")
	back = _tsim()
	back.load_tithe({}, false)
	t.ok(not back.tithe["started"], "and without one it idles")
	back = _tsim()
	back.load_tithe({"warning": {"wave_id": 1, "fort_id": "nowhere", "eta_s": 1.0, "surge": 1.0}, "started": true, "next_s": 3.0}, true)
	t.ok(back.tithe["warning"].is_empty() and back.tithe["next_s"] == 3.0, "an entry naming an unknown fort is dropped")


## E2b T3.0m: a wave starts and ends at its exact time inside a step (MECHANICS §3.4). A step that
## ends exactly at its start delivers none of it; one that straddles the start delivers the rate ×
## the time after it; one that holds the whole wave delivers all of it and ends it. Unclipped steps
## of 0.5, 7 and 30 s deliver exactly surge_mult · S_vei · surge_s (her pool deep).
func _wave_timing(t: TestUtil) -> void:
	var tc: Dictionary = TestUtil.configs()["realm"]["tithe"]
	var rate: float = float(tc["surge_mult"]) * float(TestUtil.configs()["realm"]["S_vei"])
	var surge_s := float(tc["surge_s"])
	for c in [["ends at the start", 2.0, 0.0], ["straddles it", 2.75, 0.75], ["holds the whole wave", 60.0, surge_s]]:
		var sim := _tsim()
		var tgt: Dictionary = sim.forts[0]
		sim.start_tithe()
		sim.tithe["next_s"] = 3.0
		sim.step(1.0, {})  # the warning; the wave is 2 s on
		sim.drain_events()
		sim.step(c[1], {})
		var started := sim.drain_events().filter(func(e): return e["type"] == "tithe_wave").size() == 1
		var got: float = float(tgt["r_surge"]) * float(c[1])
		var wv: Dictionary = sim.tithe["wave"]
		var left: float = float(wv["s_left"]) if not wv.is_empty() else 0.0
		t.ok(started and absf(got - rate * float(c[2])) < 1e-9 and absf(left - (surge_s - float(c[2]))) < 1e-9
			and wv.is_empty() == (c[2] == surge_s),
			"a step that %s (%.2f s, the wave from 2 s in) delivers %.1f = %.0f/s × %.2f s; %.2f s of the wave left" % [
				c[0], c[1], got, rate, c[2], left])
	for dt in [0.5, 7.0, 30.0]:
		var sim := _tsim()
		var tgt: Dictionary = sim.forts[0]
		sim.start_tithe()
		sim.tithe["next_s"] = 200.0
		var got := 0.0
		var seen := false
		for i in int(400.0 / dt):
			sim.step(dt, {})
			got += float(tgt["r_surge"]) * dt
			seen = seen or not (sim.tithe["wave"] as Dictionary).is_empty()
		t.ok(seen and absf(got - rate * surge_s) < 1e-9 * rate * surge_s,
			"unclipped steps of %.1f s: the wave delivers %.6f, surge_mult · S_vei · surge_s = %.0f" % [dt, got, rate * surge_s])


## One fort's full state after `seconds` of steps of `dt` with constant inputs.
func _run_fort(over: Dictionary, setup: Dictionary, seconds: float, dt: float, inp: Dictionary) -> Dictionary:
	var sim := _mk(over)
	var f: Dictionary = sim.forts[0]
	for k in setup:
		if k == "pool":
			sim.vei["living_pool"] = setup[k]
		elif k in ["undead_queue", "dead_queue"]:
			sim.vei[k] = setup[k]
		else:
			f[k] = setup[k]
	var n := int(round(seconds / dt))
	var kills := 0.0
	var out_dead := 0.0
	var cleared0 := sim.cleared_total
	var shipped := 0.0
	var converted := 0.0
	for i in n:
		sim.step(dt, inp)
		kills += float(f["r_kills"]) * dt
		out_dead += float(f["r_dead_out"]) * dt
		shipped += float(sim.vei["r_shipped"]) * dt
		converted += float(sim.vei["r_converted"]) * dt
	return {"sim": sim, "f": f, "kills": kills, "dead_out": out_dead, "cleared": sim.cleared_total - cleared0,
		"shipped": shipped, "converted": converted}


static func _rel(a: float, b: float) -> float:
	return absf(a - b) / maxf(1e-9, maxf(absf(a), absf(b)))


## E2b T3.0: the problems review found at long dt (MECHANICS §3.1), each against the 0.5 s step.
func _long_steps(t: TestUtil) -> void:
	# the drain is exact: U · e^(−r·dt), never negative
	var quiet := {"k_kill": 0.0, "k_destroy": 0.0, "k_clear": 0.0, "S_vei": 0.0, "R_vei": 0.0}
	for dt in [0.5, 30.0, 120.0]:
		var r := _run_fort(quiet, {"living": 0.0, "undead": 100.0, "dead": 0.0}, 120.0, dt, {})
		t.near(float(r["f"]["undead"]), 100.0 * exp(-0.06 * 120.0), 1e-9, "dt %.1f: the drain is exact (U0 · e^(−r · 120 s))" % dt)
	var big := _run_fort(quiet, {"living": 0.0, "undead": 100.0, "dead": 0.0}, 240.0, 240.0, {})
	t.ok(float(big["f"]["undead"]) >= 0.0 and float(big["sim"].vei["undead_queue"]) > 0.0, "a 240 s step drains, never below 0")
	# a fort pinned at 0 living: Vei's shipping is killed on arrival at any dt, so the garrison destroys
	# nothing and k_clear (from ∫living) clears nothing. Under the lumps they did, k_destroy · L0 · dt / q
	# with L0 the last step's shipping: about 0.006 · 0.21 · 30 / 1.2 ≈ 0.03 mass/s at 30 s.
	var pin_cfg := {"r_drain": 0.0}
	var pin := {"living": 0.0, "undead": 40.0, "dead": 0.0, "pool": 600.0, "dead_queue": 1e5}
	var ref := _run_fort(pin_cfg, pin, 120.0, 0.5, {"digest_q": 1.2})
	for dt in [5.0, 30.0]:
		var r := _run_fort(pin_cfg, pin, 120.0, dt, {"digest_q": 1.2})
		t.ok(_rel(r["kills"], ref["kills"]) < 1e-9 and r["kills"] > 20.0,
			"pinned at 0, dt %.0f: the kills are what Vei shipped in (%.3f, %.3f at 0.5 s)" % [dt, r["kills"], ref["kills"]])
		t.ok(float(r["dead_out"]) < 1e-9 and float(ref["dead_out"]) < 1e-9 and float(r["cleared"]) < 1e-9 and float(ref["cleared"]) < 1e-9
			and float(r["f"]["living"]) == 0.0, "pinned at 0, dt %.0f: no garrison kills, no clearing, at any dt" % dt)
	# living's path: it reaches 0 at t* = L0 / (k_kill · U − S), recorded on the fort
	var sim := _mk({"r_drain": 0.0, "k_destroy": 0.0, "k_clear": 0.0, "S_vei": 0.0, "R_vei": 0.0})
	var f: Dictionary = sim.forts[0]
	f["living"] = 9.0
	f["undead"] = 50.0
	f["dead"] = 0.0
	sim.step(30.0, {})
	t.near(float(f["t_living_out"]), 9.0 / (0.018 * 50.0), 1e-9, "t* = L0 / (k_kill · U): living reaches 0 at 10 s")
	t.ok(f["living"] == 0.0 and absf(float(f["dead"]) - 9.0) < 1e-9, "then stays 0; the kills are all of it, no more")
	sim.step(30.0, {})
	t.ok(float(f["t_living_out"]) == 0.0 and float(f["t_undead_out"]) == -1.0, "t_living_out 0 when it starts at 0; t_undead_out −1 while undead remain")
	# a full-strength wave at dt 30: drawn on her pool plus what she converts in the step, it
	# delivers all of it, as at 0.5 s (a 30 s step wants 720 from a pool of 600)
	var w05 := _wave_delivered(0.5)
	var w30 := _wave_delivered(30.0)
	var full: float = float(TestUtil.configs()["realm"]["tithe"]["surge_mult"]) * 8.0 * 40.0
	t.ok(absf(w05 - full) < 1e-6 and absf(w30 - full) < 1e-6,
		"a full wave delivers all %.0f at 30 s as at 0.5 s (%.1f, %.1f; −1: her pool left [0, cap])" % [full, w30, w05])
	# Vei's headroom: at her cap, a long step converts what shipping took out in it (it used to see
	# only the start's headroom, ~0, and under-digest)
	var cap_in := {"living": 0.0, "undead": 0.0, "dead": 0.0, "pool": 600.0, "dead_queue": 1e5}
	var h05 := _run_fort({"k_kill": 0.0, "k_destroy": 0.0, "k_clear": 0.0}, cap_in, 600.0, 0.5, {})
	var h30 := _run_fort({"k_kill": 0.0, "k_destroy": 0.0, "k_clear": 0.0}, cap_in, 600.0, 30.0, {})
	t.ok(h30["shipped"] > 0.0 and _rel(h30["converted"], h30["shipped"]) < 1e-9 and _rel(h30["converted"], h05["converted"]) < 0.01,
		"at her cap a 30 s step converts what it ships (%.1f; %.1f at 0.5 s)" % [h30["converted"], h05["converted"]])
	t.near(float(h30["sim"].vei["living_pool"]), 600.0, 1e-6, "and her pool stays full")


## E2b T3.0s: shipping's room counts this step's WAR, the raises and the surge, so shipping never
## takes a fort past its cap (WAR and the surge may: space doesn't bound them). Vei ships 5× her
## rate from a deep pool into forts kept near full, with WAR, a wave cycle and Relish raising at
## Greywall. `plain` has no garrison kills, so a fort's end total is exactly its start, what arrived
## and what drained; `combat` runs every rate. Returns nothing; asserts per dt.
func _room(t: TestUtil) -> void:
	for c in [["plain", {"k_destroy": 0.0, "k_clear": 0.0}], ["combat", {}]]:
		for dt in [0.5, 5.0, 30.0]:
			var over := {"S_vei": 40.0}
			over.merge(c[1], true)
			var sim := _mk(over)
			sim.vei["living_pool"] = 600.0
			sim.vei["dead_queue"] = 1e5
			sim.start_tithe()
			sim.tithe["next_s"] = 200.0
			var worst := -INF  # the most a fort that took shipping ended above its cap
			var worst_redirect := -INF  # the same at Greywall, where Relish keeps the garrison's kills
			var shipped := 0
			var before := sim.total_matter()
			var added := 0.0
			var lost := 0.0
			for i in int(1200.0 / dt):
				for f in sim.forts:  # keep the forts near full: the room, not the share, binds
					var load: float = f["living"] + f["undead"] + f["dead"]
					if load < f["cap"]:
						f["dead"] = float(f["dead"]) + 0.98 * (f["cap"] - load)
						added += 0.98 * (f["cap"] - load)
				sim.step(dt, {"war": 6.0, "flood": 0.0, "redirect_fort": "greywall", "redirect_rate": 4.0})
				added += 6.0 * dt
				lost += sim.pool_overflow
				sim.drain_events()
				for f in sim.forts:
					if float(f["r_shipped"]) - float(f["r_surge"]) > 0.0:
						shipped += 1
						var o: float = f["living"] + f["undead"] + f["dead"] - f["cap"]
						if f["id"] == "greywall":
							worst_redirect = maxf(worst_redirect, o)
						else:
							worst = maxf(worst, o)
			t.ok(shipped > 0 and worst <= 1e-9 * 520.0,
				"%s, dt %.1f: a fort that took shipping ends at most at its cap (worst %+.6f, %d fort-steps shipped)" % [c[0], dt, worst, shipped])
			t.near(sim.total_matter(), before + added - sim.cleared_total - lost, 1e-9 * (before + added), "%s, dt %.1f: mass is exact" % [c[0], dt])
			print("  [realm_sim] room %s, dt %.1f: at Greywall (Relish raising there) the worst end above cap after shipping: %+.6f" % [
				c[0], dt, worst_redirect])
	# contested forts, nothing cleared: the kills inside the step thin the living, so the garrison's
	# pull is weaker than the living now says and the undead end higher. One step from each start
	for dt in [0.5, 5.0, 30.0, 60.0]:
		var worst := -INF
		var shipped := 0
		for lu in [[70.0, 9.0], [50.0, 29.0], [40.0, 39.0], [30.0, 49.0]]:
			for war in [0.0, 6.0, 20.0]:
				var sim := _mk({"k_clear": 0.0, "S_vei": 400.0})
				sim.vei["living_pool"] = 600.0
				sim.vei["dead_queue"] = 1e5
				for f in sim.forts:
					f["living"] = lu[0] * f["cap"] / 80.0
					f["undead"] = lu[1] * f["cap"] / 80.0
					f["dead"] = 0.0
				sim.step(dt, {"war": war, "digest_q": 1.2})
				for f in sim.forts:
					if float(f["r_shipped"]) > 0.0:
						shipped += 1
						worst = maxf(worst, f["living"] + f["undead"] + f["dead"] - f["cap"])
		t.ok(shipped > 0 and worst <= 1e-9 * 520.0,
			"contested, no clearing, dt %.1f: a fort that took shipping ends at most at its cap (worst %+.6f, %d forts shipped)" % [dt, worst, shipped])


## E2b T3.0m (MECHANICS §3.4): living above a fort's cap march back to Vei's pool at (L − cap) / τ.
## No WAR anywhere, so every wave goes to the first fort in world order (Ashgate), which has no
## undead: nothing kills its living and nothing is shipped to it while it is past its cap, so its
## excess x = L − cap only marches back, x(t) = x(end) · e^(−t/τ) after a wave. At dt 0.5, 5 and
## 30 s, clipped at the waves' starts and ends as catch-up clips: 4 waves (period_s apart, so each
## lands on what is left of the last) peak at most one wave's mass above the cap. Then the clock is
## stopped: 7τ after the last wave exactly e^(−7) (< 1e-3) of what it left above the cap remains,
## and 10τ after it Ashgate is within cap · (1 + 1e-3) (its excess at a wave's end is about 9 caps,
## so that takes ln(9 / 1e-3) ≈ 9.1τ, not 7τ). Mass is exact with her pool's overflow counted.
func _march_back(t: TestUtil) -> void:
	var tc: Dictionary = TestUtil.configs()["realm"]["tithe"]
	var tau := float(tc["march_back_s"])
	var full: float = float(tc["surge_mult"]) * 8.0 * float(tc["surge_s"])
	for dt in [0.5, 5.0, 30.0]:
		var sim := _mk({})
		sim.vei["living_pool"] = 600.0
		sim.vei["dead_queue"] = 1e5
		sim.start_tithe()
		var tgt: Dictionary = sim.forts[0]
		var cap: float = tgt["cap"]
		var before := sim.total_matter()
		var lost := 0.0
		var peak := 0.0
		var waves := 0
		var elsewhere := 0
		var ended := -1.0  # when the last wave ended (sim.elapsed)
		var x_end := 0.0  # what it left above the cap
		for guard in 40000:
			var h: float = dt  # clipped at the wave's start and end, as catch-up clips
			var running := not (sim.tithe["wave"] as Dictionary).is_empty()
			if not running:
				h = minf(dt, maxf(1e-3, float(sim.tithe["next_s"])))
			else:
				h = minf(dt, float(sim.tithe["wave"]["s_left"]))
			sim.step(h, {})
			lost += sim.pool_overflow
			for ev in sim.drain_events():
				if ev["type"] == "tithe_wave":
					waves += 1
					elsewhere += 0 if ev["fort_id"] == tgt["id"] else 1
			peak = maxf(peak, tgt["living"])
			if running and (sim.tithe["wave"] as Dictionary).is_empty() and waves >= 4:
				ended = sim.elapsed
				x_end = tgt["living"] - cap
				break
		t.ok(waves == 4 and elsewhere == 0 and tgt["undead"] == 0.0 and peak <= cap + full and peak > cap,
			"dt %.1f: 4 waves into a fort with no undead peak at %.3f, past its cap %.0f but at most cap + one wave (%.0f)" % [
				dt, peak, cap, cap + full])
		sim.tithe["next_s"] = 1e9  # no fifth wave
		sim.tithe["warning"] = {}
		var x_at := {}
		for k in [7.0, 10.0]:
			while sim.elapsed < ended + k * tau - 1e-9:
				sim.step(minf(dt, ended + k * tau - sim.elapsed), {})
				lost += sim.pool_overflow
			x_at[k] = tgt["living"] - cap
		t.ok(ended > 0.0 and absf(x_at[7.0] / (x_end * exp(-7.0)) - 1.0) < 1e-9 and x_at[7.0] <= 1e-3 * full,
			"dt %.1f: 7τ after the last wave exactly e^(−7) of its excess %.1f is left (%.4f, ≤ 1e-3 of a wave)" % [dt, x_end, x_at[7.0]])
		t.ok(x_at[10.0] <= cap * 1e-3 and x_at[10.0] > 0.0,
			"dt %.1f: 10τ after it Ashgate is back within cap · (1 + 1e-3) (%.4f above its %.0f)" % [dt, x_at[10.0], cap])
		t.near(sim.total_matter() + lost + sim.cleared_total, before, 1e-12 * before, "dt %.1f: mass is exact (%.1f lost past her pool's cap)" % [dt, lost])
	_march_path(t)
	_march_pool(t)
	_march_holds(t)


## _l_path is a flow: one step of dt from any start equals two of dt / 2 (end, ∫L and the marched
## mass add up), across its pieces: rising through the cap, decaying toward a level above it, falling
## back to it, then to 0. And fort_step's mass is exact: kills + marched + ΔL = what arrived.
func _march_path(t: TestUtil) -> void:
	var sim := _mk({})
	var tau := 60.0
	var cap := 80.0
	var worst := 0.0
	var cases := 0
	for l0 in [0.0, 40.0, 79.0, 80.0, 81.0, 400.0, 2000.0]:
		for c in [[24.0, 0.0], [24.0, 30.0], [0.0, 2.0], [0.0, 0.0], [5.0, 1.0], [0.0, 40.0]]:
			for dt in [0.5, 15.0, 120.0, 900.0]:
				sim._l_path(dt, l0, c[0], c[1], cap, tau)
				var one := [sim._le, sim._lm * dt, sim._lb]
				sim._l_path(dt / 2.0, l0, c[0], c[1], cap, tau)
				var mid := [sim._le, sim._lm * dt / 2.0, sim._lb]
				sim._l_path(dt / 2.0, mid[0], c[0], c[1], cap, tau)
				var two := [sim._le, mid[1] + sim._lm * dt / 2.0, mid[2] + sim._lb]
				for k in 3:
					worst = maxf(worst, absf(one[k] - two[k]) / maxf(1.0, absf(one[k])))
				# mass: the living's own balance (kills are the rest, so it can't miss)
				var kills: float = l0 + c[0] * dt - one[0] - one[2]
				worst = maxf(worst, maxf(0.0, -kills - 1e-9 * maxf(1.0, l0 + c[0] * dt)))
				cases += 1
	t.ok(worst < 1e-9, "_l_path: one step of dt matches two of dt / 2 (end, ∫L, marched) over %d starts, rates and dt to 900 s (worst %s)" % [
		cases, String.num_scientific(worst)])
	# the closed forms on known cases
	sim._l_path(30.0, 80.0 + 600.0, 0.0, 0.0, cap, tau)
	t.near(sim._le, 80.0 + 600.0 * exp(-0.5), 1e-9, "no kills, nothing in: the excess decays as e^(−t/τ)")
	t.near(sim._lb, 600.0 * (1.0 - exp(-0.5)), 1e-9, "and what left it marched back")
	sim._l_path(600.0, 80.0 + 10.0, 0.0, 1.0, cap, tau)
	t.near(float(sim._lt), 60.0 * log(1.0 + 10.0 / 60.0) + 80.0, 1e-9, "kills at 1/s: back at the cap at τ · ln(1 + x0 / (kill · τ)), then 0 after cap / kill")
	t.near(sim._lb, 10.0 - 60.0 * log(1.0 + 10.0 / 60.0), 1e-9, "the marched mass is the excess less the kills above the cap")
	sim._l_path(1e4, 80.0, 24.0, 4.0, cap, tau)
	t.near(sim._le, 80.0 + 20.0 * 60.0, 1e-6, "a steady inflow settles at cap + τ · (s_in − kill)")
	# fort_step: mass exact with kills, a garrison and the march-back all at once
	for dt in [0.5, 15.0, 60.0]:
		var f: Dictionary = sim.forts[0]
		f["living"] = 500.0
		f["undead"] = 30.0
		f["dead"] = 5.0
		var m0: float = f["living"] + f["undead"] + f["dead"]
		sim.fort_step(f, dt, 24.0, 3.0, 0.0, false, 1.2)
		var m1: float = f["living"] + f["undead"] + f["dead"] + sim._destroyed + sim._drained + sim._cleared + sim._marched
		t.ok(sim._marched > 0.0 and absf(m1 - (m0 + 27.0 * dt)) < 1e-12 * m0, "fort_step at dt %.1f: mass exact with the march-back (%.3f marched)" % [dt, sim._marched])


## Her pool and its overflow agree across dt (E2b T3.0m): the march-back lands after the step's
## shipping and before her conversion, which fills only the headroom it leaves, so a long step's
## lump of marched living is shipped and converted around as the short steps would. One wave into
## Ashgate (started at once) and 7τ of its tail, with WAR (so shipping goes on elsewhere and
## Ashgate's living are killed too): "full", her pool full and conversion to spare, where the march
## displaces conversion and overflows; "drained", conversion at 5/s, where the wave empties her pool
## and the march-back refills it.
func _march_pool(t: TestUtil) -> void:
	for c in [["full", {}], ["drained", {"R_vei": 5.0}]]:
		var ref := {}
		for dt in [0.5, 5.0, 15.0]:
			var r := _pool_run(c[1], dt)
			if dt == 0.5:
				ref = r
			var line := "%s, dt %.1f: pool %.3f, overflow %.3f, dead queue %.3f, marched %.3f, Ashgate living %.3f; pool in [0, cap] %s" % [
				c[0], dt, r["pool"], r["lost"], r["dq"], r["marched"], r["living"], r["in_range"]]
			print("  [realm_sim] march-back pool " + line)
			if dt == 0.5:
				t.ok(r["in_range"] and r["marched"] > 0.0 and (c[0] == "drained" or r["lost"] > 0.0), line)
				continue
			var scale: float = maxf(1.0, ref["marched"])
			var miss: float = maxf(maxf(absf(r["pool"] - ref["pool"]), absf(r["lost"] - ref["lost"])), absf(r["dq"] - ref["dq"])) / scale
			t.ok(r["in_range"] and miss < POOL_TOL, "%s, dt %.1f: her pool, overflow and conversion agree with 0.5 s within %.1f%% of the marched mass (%.4f%%)" % [
				c[0], dt, POOL_TOL * 100.0, miss * 100.0])


## _march_pool's tolerance, against the marched mass. Measured (T3.0m, τ 60 s): full 0.27% at 5 s
## and 0.84% at 15 s; drained 0.95% and 1.48%. The march-back lands after the step's surge, so when
## her pool runs dry during a wave a long step re-surges the marched living one step late: first
## order in dt, and her pool ends full at every dt. IDLE's catch-up tolerance (2%).
const POOL_TOL := 0.02


func _pool_run(over: Dictionary, dt: float) -> Dictionary:
	var sim := _mk(over)
	var tc: Dictionary = sim.t["tithe"]
	var tau := float(tc["march_back_s"])
	var tgt: Dictionary = sim.forts[0]
	sim.vei["living_pool"] = 600.0
	sim.vei["dead_queue"] = 1e5
	sim.start_tithe()
	sim.tithe["next_s"] = 1e6  # no other wave
	var surge_s := float(tc["surge_s"])
	sim.tithe["wave"] = {"wave_id": 1, "fort_id": tgt["id"], "s_left": surge_s, "duration_s": surge_s,
		"mult": float(tc["surge_mult"]), "delivered": 0.0}
	var lost := 0.0
	var marched := 0.0
	var in_range := true
	var left := surge_s + 7.0 * tau
	while left > 1e-9:
		var h := minf(dt, left)
		if not (sim.tithe["wave"] as Dictionary).is_empty():
			h = minf(h, float(sim.tithe["wave"]["s_left"]))
		sim.step(h, {"war": 6.0})
		sim.drain_events()
		lost += sim.pool_overflow
		marched += sim.r_marched * h
		left -= h
		in_range = in_range and sim.vei["living_pool"] >= 0.0 and sim.vei["living_pool"] <= 600.0 + 1e-9
	return {"pool": float(sim.vei["living_pool"]), "lost": lost, "dq": float(sim.vei["dead_queue"]), "marched": marched,
		"living": float(tgt["living"]), "in_range": in_range}


## The live hold (E2a's rule with combat, drain and the march-back on, MECHANICS §3.4): a held fort
## with a garrison at its full cap and no living or corpses takes a full wave at 0.5 s, and every
## other fort is full of corpses, so the held fort is WAR's only target (all of it stages there).
## With no WAR the garrison drains and is destroyed before the wave ends, and the hold is lost at
## Greywall (cap 90) and Whitecross (520), Relish there or not. With 30 mass/s staged the full wave
## still takes it, but Relish there (the wave halved, her raise) or a siege (0.6 of it cancelled)
## saves it: the counters matter.
func _march_holds(t: TestUtil) -> void:
	for id in ["greywall", "whitecross"]:
		for war in [0.0, 30.0]:
			for mode in ["none", "Relish", "siege"]:
				var sim := _mk({})
				sim.vei["living_pool"] = 600.0
				sim.vei["dead_queue"] = 1e5
				var f := sim.fort_by_id(id)
				sim.hold(id, 1e6)
				f["living"] = 0.0
				f["dead"] = 0.0
				f["undead"] = f["cap"]
				for o in sim.forts:
					if o["id"] != id:
						o["living"] = 0.0
						o["dead"] = o["cap"]
				sim.start_tithe()
				sim.tithe["next_s"] = 1e6
				var surge_s := float(sim.t["tithe"]["surge_s"])
				sim.tithe["wave"] = {"wave_id": 1, "fort_id": id, "s_left": surge_s, "duration_s": surge_s,
					"mult": float(sim.t["tithe"]["surge_mult"]), "delivered": 0.0}
				var inp := {"war": war}
				if mode == "Relish":
					inp.merge({"tide_fort": id, "tide_bias": 3.0, "redirect_fort": id, "redirect_rate": 4.0})
				elif mode == "siege":
					inp["siege_block"] = {id: float(sim.t["tithe"]["siege_block"])}
				var delivered := 0.0
				var got: Array = []
				for guard in 1000:
					if (sim.tithe["wave"] as Dictionary).is_empty():
						break
					sim.step(0.5, inp)
					delivered += float(f["r_surge"]) * 0.5
					got.append_array(sim.drain_events().filter(func(e): return e["type"] == "fort_retaken"))
				var expect_held: bool = war > 0.0 and mode != "none"
				t.ok(f["held"] == expect_held and got.size() == (0 if expect_held else 1),
					"live, %s (cap %.0f), WAR %.0f, %s: delivered %.0f, the garrison ends at %.1f: held %s" % [
						id, f["cap"], war, mode, delivered, f["undead"], f["held"]])


## The living one full-strength wave delivers at steps of `dt`, clipped at its start and end, or −1
## if her pool left [0, cap] (the march-back lands in it too): her pool and conversion at long steps.
func _wave_delivered(dt: float) -> float:
	var ts := _mk({"k_kill": 0.0, "k_destroy": 0.0, "k_clear": 0.0, "r_drain": 0.0})
	ts.vei["living_pool"] = 600.0
	ts.vei["dead_queue"] = 1e5
	ts.start_tithe()
	ts.tithe["next_s"] = 150.0  # the warning at once, the wave 150 s on
	var got := 0.0
	var started := false
	for guard in 2000:
		var h := dt
		if not started:
			h = minf(dt, maxf(1e-3, float(ts.tithe["next_s"])))
		elif not (ts.tithe["wave"] as Dictionary).is_empty():
			h = minf(dt, float(ts.tithe["wave"]["s_left"]))
		ts.step(h, {"war": 5.0})
		for f in ts.forts:
			got += float(f["r_surge"]) * h
		if ts.vei["living_pool"] < 0.0 or ts.vei["living_pool"] > 600.0 + 1e-9:
			return -1.0
		started = started or not (ts.tithe["wave"] as Dictionary).is_empty()
		if started and (ts.tithe["wave"] as Dictionary).is_empty():
			break
	return got
