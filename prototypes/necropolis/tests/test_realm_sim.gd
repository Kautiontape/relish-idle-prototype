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
	sim.release(h1["id"])
	sim.release(h2["id"])
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

	# --- a retake refreshes the yield and loses the fort's simulacrum (IDLE I6) --------
	sim = _mk({})
	f = sim.forts[1]
	f["clears_since_retaken"] = 3
	f["living"] = 0.0
	f["undead"] = 0.0
	sim.simulacra = [{"fort_id": f["id"], "charges": 30.0, "rate": 2.0}, {"fort_id": sim.forts[4]["id"], "charges": 30.0, "rate": 2.0}]
	sim.hold(f["id"], 0.0)
	var got_r: Array = []
	for i in int(float(sim.t["hold"]["break_s"]) / 0.5) + 1:
		sim.step(0.5, {})
		got_r.append_array(sim.drain_events().filter(func(e): return e["type"] == "fort_retaken"))
	t.ok(got_r.size() == 1 and f["clears_since_retaken"] == 0 and not f["held"], "a retake resets clears_since_retaken: %s" % str(got_r))
	t.ok(sim.simulacra.size() == 1 and sim.simulacra[0]["fort_id"] == sim.forts[4]["id"], "and the simulacrum planted there is lost, the other kept")

	# --- tithe waves --------------------------------------------------------------
	_tithe(t)
	_wave_timing(t)

	# --- E2b: the step is exact at any dt -------------------------------------------
	_long_steps(t)
	_room(t)
	_march_back(t)
	_room_clearing(t)
	_fill_raises(t)
	_fill_kills(t)
	_m4(t)

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
	var pair: Array[RealmSim] = [_mk({}), _mk({})]
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
	t.near(free["r_shipped"], _share_rate(pair[0], free), 1e-9, "a fort receives S_vei · cap_i / Σcap")
	t.ok(pair[1].forts[3]["r_shipped"] == 0.0, "a held fort gets no shipping")
	t.near(pair[0].vei["r_shipped"] - pair[1].vei["r_shipped"], free["r_shipped"], 1e-9, "Σ shipped drops by the held share")
	t.near(pair[1].forts[4]["r_shipped"], pair[0].forts[4]["r_shipped"], 1e-12, "the held share is not redistributed")
	t.ok(pair[1].forts[3]["held"] == true and pair[0].forts[3]["held"] == false, "held is visible in the fort dict")

	# --- the hold: grace, then the contest; no timer ends it ----------------------
	sim = _mk({})
	f = sim.forts[1]
	t.ok(sim.hold(f["id"], 1.0) and not sim.hold("nowhere", 1.0), "hold() takes a known fort only")
	t.ok(f["held"] and f["grace_s"] == 1.0 and f["zero_s"] == 0.0 and f["held_s"] == 1.0, "hold(): held, grace_s, zero_s 0 (held_s, deprecated, mirrors the grace)")
	f["undead"] = 50.0
	sim.step(0.5, {})
	t.near(f["grace_s"], 0.5, 1e-12, "grace_s counts down in step")
	t.ok(sim.drain_events().is_empty() and f["held"] and RealmSim.in_grace(f), "still in grace, no event")
	sim.step(0.5, {})
	t.ok(sim.drain_events().is_empty() and f["held"] and f["grace_s"] == 0.0 and RealmSim.is_contested(f),
		"the grace's end is no retake: the fort is contested")
	for i in 20:
		sim.step(0.5, {"war": 30.0})
	t.ok(sim.drain_events().filter(func(e): return e["type"] == "fort_retaken").is_empty() and f["held"], "a garrison above 0 holds it")
	t.ok(sim.release(f["id"]) and not f["held"] and f["grace_s"] == 0.0 and sim.drain_events().is_empty(), "release() ends a hold without an event")
	_contest(t)

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
			sim.hold(ids[rng.randi_range(0, ids.size() - 1)], rng.randf_range(0.0, 120.0))
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
			if ff["living"] < -1e-9 or ff["dead"] < -1e-9 or ff["undead"] < -1e-9 or ff["grace_s"] < 0.0 or ff["zero_s"] < 0.0:
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
	sim.hold(held["id"], 0.0)  # contested (its undead never drain or die here, so it holds)
	held["undead"] = 10.0
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
	sim.hold(other["id"], 0.0)
	var wv := _until(sim, "tithe_wave", {}, period)
	t.near(wv[0] - w[0], warn, 1e-9, "the wave starts warning_s after its warning")
	t.ok(wv[1]["fort_id"] == held["id"] and wv[1]["wave_id"] == 1, "the warned target stays fixed for its wave")
	t.ok(wv[1] == {"type": "tithe_wave", "wave_id": 1, "fort_id": held["id"], "surge": base, "duration_s": surge_s,
		"relish_here": false, "siege_block": 0.0}, "tithe_wave {wave_id, fort_id, surge, duration_s, relish_here, siege_block}: %s" % str(wv[1]))
	t.near(sim.tithe["next_s"], period, 1e-9, "the next wave is scheduled start to start")

	# the target rule: contested forts first, the most undead, ties in world order; never a fort in grace
	sim = _tsim()
	sim.hold(sim.forts[3]["id"], 0.0)
	sim.hold(sim.forts[6]["id"], 0.0)
	sim.forts[3]["undead"] = 5.0
	sim.forts[6]["undead"] = 9.0
	t.ok(_target_now(sim, {"war": 5.0}) == sim.forts[6]["id"], "held first: the contested fort with the most undead")
	sim = _tsim()
	sim.hold(sim.forts[3]["id"], 0.0)
	sim.hold(sim.forts[6]["id"], 0.0)
	sim.forts[3]["undead"] = 7.0
	sim.forts[6]["undead"] = 7.0
	t.ok(_target_now(sim, {}) == sim.forts[3]["id"], "a tie between contested forts goes to world order")
	sim = _tsim()
	sim.hold(sim.forts[3]["id"], 0.0)
	sim.hold(sim.forts[6]["id"], 1e6)  # in grace, with the most undead
	sim.forts[3]["undead"] = 5.0
	sim.forts[6]["undead"] = 9.0
	t.ok(_target_now(sim, {"war": 5.0}) == sim.forts[3]["id"], "a fort in grace is never a target, though it has the most undead")
	sim = _tsim()
	var near0: Dictionary = sim.forts[0]
	sim.hold(near0["id"], 1e6)  # in grace and the nearest: with nothing contested it would get the most WAR
	t.ok(_target_now(sim, {"war": 5.0}) != near0["id"] and float(near0["r_in"]) > 0.0,
		"nor is it the fort taking the most WAR: the target is the most-WAR fort not in grace")
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
	sim.hold(hf["id"], 0.0)
	hf["undead"] = 10.0
	sim.start_tithe()
	sim.tithe["next_s"] = 0.25
	sim.vei["living_pool"] = 5.0
	var before := sim.total_matter()
	sim.step(0.5, {})
	t.near(hf["r_surge"], 5.0 / 0.5, 1e-9, "bounded by her pool (5 mass of the 6 the wave's first 0.25 s want)")
	t.ok(sim.vei["living_pool"] == 0.0 and hf["r_shipped"] == hf["r_surge"], "the pool empties into the contested fort; r_shipped carries the surge (her reship found the pool empty)")
	t.near(sim.total_matter(), before, 1e-9, "the surge moves mass, it makes none")

	# no wave targets a fort in grace (MECHANICS §3.4): a warning naming one when it is flipped is
	# dropped at once and made again for another target, under the next wave id
	sim = _tsim()
	var tgt4: Dictionary = sim.forts[4]
	sim.start_tithe()
	sim.tithe["next_s"] = 3.0
	sim.step(0.5, {"war": 5.0, "tide_fort": tgt4["id"], "tide_bias": 1000.0})
	t.ok(sim.tithe["warning"].get("fort_id", "") == tgt4["id"], "a warning on Chime-fort (setup)")
	sim.drain_events()
	sim.hold(tgt4["id"], 1e6)
	t.ok(sim.tithe["warning"].is_empty(), "flipped (in grace): its warning is dropped at once")
	var rw := _until(sim, "tithe_warning", {"war": 5.0, "tide_fort": tgt4["id"], "tide_bias": 1000.0}, 1.0)
	t.ok(rw[1].get("fort_id", tgt4["id"]) != tgt4["id"] and rw[1].get("wave_id", 0) == 2,
		"and made again at the next step's end for another fort, wave 2: %s" % str(rw[1]))
	var rwv := _until(sim, "tithe_wave", {"war": 5.0, "tide_fort": tgt4["id"], "tide_bias": 1000.0}, 10.0)
	t.ok(rwv[1].get("fort_id", "") == rw[1].get("fort_id", "?") and tgt4["r_surge"] == 0.0, "its wave hits that fort, not the one in grace")
	# a save can hold such a warning (midgame_2flips: Ashgate in grace, warned): it is kept as loaded and
	# dropped by the first step's clock, which warns again (here at once: the wave is due in that step)
	sim = _tsim()
	sim.hold(sim.forts[0]["id"], 300.0)
	sim.load_tithe({"warning": {"wave_id": 1, "fort_id": sim.forts[0]["id"], "eta_s": 0.25, "surge": 24.0}}, true)
	t.ok(sim.tithe["warning"]["fort_id"] == sim.forts[0]["id"], "a loaded warning on a fort in grace is kept as loaded")
	sim.step(0.5, {"war": 5.0})
	var lw: Array = sim.drain_events()
	t.ok(lw.size() == 2 and lw[0]["type"] == "tithe_warning" and lw[0]["fort_id"] != sim.forts[0]["id"] and lw[1]["type"] == "tithe_wave"
		and lw[1]["fort_id"] == lw[0]["fort_id"] and sim.forts[0]["r_surge"] == 0.0,
		"the first step drops it, warns another fort and starts the wave there: %s" % str(lw))
	# a wave already running at a fort that enters grace delivers nothing until the grace ends; the
	# grace's end inside a step is exact, so it then delivers rate × the rest of the wave at any dt
	for dt in [0.5, 7.0, 30.0]:
		sim = _tsim()
		hf = sim.forts[2]
		sim.start_tithe()
		sim.tithe["next_s"] = 1e6
		sim.tithe["wave"] = {"wave_id": 1, "fort_id": hf["id"], "s_left": surge_s, "duration_s": surge_s, "mult": 3.0, "delivered": 0.0}
		sim.hold(hf["id"], 12.3)
		hf["undead"] = 10.0
		var dl := 0.0
		for i in int(ceil(60.0 / dt)):
			sim.step(dt, {})
			dl += float(hf["r_surge"]) * dt
		t.ok(absf(dl - base * (surge_s - 12.3)) < 1e-9 * base * surge_s and sim.tithe["wave"].is_empty(),
			"dt %.1f: a wave into a fort 12.3 s from its grace's end delivers rate × (surge_s − 12.3) = %.4f (got %.6f)" % [
			dt, base * (surge_s - 12.3), dl])

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
	var rc: Dictionary = TestUtil.configs()["realm"]
	var full: float = float(rc["tithe"]["surge_mult"]) * float(rc["S_vei"]) * float(rc["tithe"]["surge_s"])
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
	var full: float = float(tc["surge_mult"]) * float(TestUtil.configs()["realm"]["S_vei"]) * float(tc["surge_s"])
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
	_hold_rule(t)


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


## A contested fort alone: `id` held with no grace and no living or corpses, `u0` undead; every other
## fort is full of corpses (no living, no room), so all the WAR stages at `id`; Vei's pool full and a
## deep dead queue. With `wave`, one full wave starts there at once (no other wave comes).
func _contested(id: String, u0: float, wave: bool) -> RealmSim:
	var sim := _mk({})
	sim.vei["living_pool"] = 600.0
	sim.vei["dead_queue"] = 1e5
	for o in sim.forts:
		if o["id"] != id:
			o["living"] = 0.0
			o["undead"] = 0.0
			o["dead"] = o["cap"]
	var f := sim.fort_by_id(id)
	sim.hold(id, 0.0)
	f["living"] = 0.0
	f["dead"] = 0.0
	f["undead"] = u0
	sim.start_tithe()
	sim.tithe["next_s"] = 1e6
	if wave:
		var surge_s := float(sim.t["tithe"]["surge_s"])
		sim.tithe["wave"] = {"wave_id": 1, "fort_id": id, "s_left": surge_s, "duration_s": surge_s,
			"mult": float(sim.t["tithe"]["surge_mult"]), "delivered": 0.0}
	return sim


## RealmSim's inputs for a counter at `id`: "Relish" stands there (her tide and redirect: the wave
## halved, her raise), "siege" blocks tithe.siege_block of the wave.
func _counter(sim: RealmSim, id: String, war: float, mode: String) -> Dictionary:
	var inp := {"war": war, "digest_q": 1.2}
	if mode == "Relish":
		inp.merge({"tide_fort": id, "tide_bias": 3.0, "redirect_fort": id, "redirect_rate": 4.0})
	elif mode == "siege":
		inp["siege_block"] = {id: float(sim.t["tithe"]["siege_block"])}
	return inp


## Runs `sim` at `dt` for up to `seconds`; the first fort_retaken's moment (seconds from the start,
## from its place inside its step) and cause, or [-1.0, ""].
func _retake_at(sim: RealmSim, dt: float, seconds: float, inp: Dictionary) -> Array:
	var el := 0.0
	while el < seconds - 1e-9:
		sim.step(dt, inp)
		for e in sim.drain_timed():
			if e[1]["type"] == "fort_retaken":
				return [el + float(e[0]), str(e[1]["cause"])]
		el += dt
	return [-1.0, ""]


## Shawn's hold rule, both ways ("Needs WAR too", MECHANICS §3.4's arithmetic). (a) A full-cap
## garrison with no WAR loses to a full wave at once, Relish there or not, a siege or not: broken by
## the wave plus break_s (Whitecross's 520 undead outlast the 40 s wave: U reaches 0 41.5 s in, 55.5
## with a siege and 75.5 with Relish, so by U's time at 0 plus break_s, within 80 s). (b) Ashgate with 0.8 mass/s of WAR, inside the band
## [0.547, 1.035): its settled garrison (WAR / r_drain) is broken by a full wave alone, and holds it
## with Relish there or a siege; with no wave it holds (0.8 > W_c 0.343).
func _hold_rule(t: TestUtil) -> void:
	t.suite("realm_sim-hold-rule")
	var cfg: Dictionary = TestUtil.configs()["realm"]
	var brk := float(cfg["hold"]["break_s"])
	var surge_s := float(cfg["tithe"]["surge_s"])
	for id in ["ashgate", "greywall", "whitecross"]:
		for mode in ["none", "Relish", "siege"]:
			var cap := float(_mk({}).fort_by_id(id)["cap"])
			var sim := _contested(id, cap, true)
			var r := _retake_at(sim, 0.5, 1200.0, _counter(sim, id, 0.0, mode))
			var bound := surge_s + brk + (40.0 if id == "whitecross" else 0.0)
			t.ok(r[1] == "broken" and r[0] > brk and r[0] <= bound,
				"(a) %s (cap %.0f), no WAR, %s: a full-cap garrison is broken by a full wave at %.1f s (by %.0f s)" % [id, cap, mode, r[0], bound])
	var w := 0.8
	var u0: float = w / float(cfg["r_drain"])
	for c in [["none", true, false], ["Relish", true, true], ["siege", true, true], ["none", false, true]]:
		var sim := _contested("ashgate", u0, c[1])
		var r := _retake_at(sim, 0.5, 1200.0, _counter(sim, "ashgate", w, c[0]))
		var holds: bool = r[0] < 0.0
		t.ok(holds == c[2], "(b) Ashgate, WAR %.1f (garrison %.1f), %s, %s: %s" % [w, u0, c[0],
			"a full wave" if c[1] else "no wave", "holds" if holds else "broken at %.1f s" % r[0]])
	t.suite("realm_sim")


## The contest's two rules RealmSim applies itself (MECHANICS §3.4). Her reship into a contested fort
## is hold.reship_share × (1 + tithe.backlog_scale · odds) of its share, not cut to the room (Ashgate
## full of corpses still gets all of it), and nothing in grace. A grace end and a break land at their
## time inside a step: a fort reaching its grace end with no garrison, no WAR and no living ("Needs
## WAR too") starts its zero clock at the grace end and falls exactly break_s later, at steps of 0.5,
## 7, 30 and 150 s (longer than break_s); her reship by then is rate × the time since the grace end.
func _contest(t: TestUtil) -> void:
	var cfg: Dictionary = TestUtil.configs()["realm"]
	var share_k := float(cfg["hold"]["reship_share"])
	var bscale := float(cfg["tithe"]["backlog_scale"])
	var brk := float(cfg["hold"]["break_s"])
	for odds_q in [0.0, 1.0]:
		var sim := _alone({}, "corpses")
		var f: Dictionary = sim.forts[0]
		f["living"] = 0.0
		f["undead"] = 20.0
		f["dead"] = 80.0  # full of corpses: no room
		sim.vei["undead_queue"] = float(sim.t["K"]) * odds_q  # odds 0 or 0.5
		var od := sim.odds()
		sim.hold(f["id"], 0.0)
		sim.step(0.5, {})
		var want: float = share_k * (1.0 + bscale * od) * _share_rate(sim, f)
		t.near(float(f["r_shipped"]), want, 1e-12 * want,
			"odds %.2f: a contested fort full of corpses gets her reship, reship_share × (1 + backlog_scale · odds) × its share (%.6f/s)" % [od, want])
	var sim := _alone({}, "corpses")
	sim.hold(sim.forts[0]["id"], 100.0)
	sim.step(0.5, {})
	t.ok(float(sim.forts[0]["r_shipped"]) == 0.0, "in grace she ships nothing there")
	for dt in [0.5, 7.0, 30.0, 150.0]:
		sim = _alone({}, "corpses")
		var f: Dictionary = sim.forts[0]
		f["living"] = 0.0
		f["undead"] = 0.0
		f["dead"] = 0.0
		var grace := 3.7
		sim.hold(f["id"], grace)
		var rate: float = share_k * _share_rate(sim, f)  # her odds stay 0 (nothing reaches her queue)
		var shipped := 0.0
		var el := 0.0
		var at := -1.0
		var checked := false
		while el < 300.0 - 1e-9:
			sim.step(dt, {})
			shipped += float(f["r_shipped"]) * dt
			for e in sim.drain_timed():
				if e[1]["type"] == "fort_retaken" and at < 0.0:
					at = el + float(e[0])
					t.ok(e[1] == {"type": "fort_retaken", "fort_id": f["id"], "cause": "broken"}, "dt %.1f: fort_retaken {fort_id, cause: broken}" % dt)
			el += dt
			if not checked and el >= 20.0 and el < grace + brk:
				checked = true
				t.near(shipped, rate * (el - grace), 1e-9 * rate * el,
					"dt %.1f: by %.1f s her reship is rate × (%.1f − 3.7): the grace ends at its time" % [dt, el, el])
				t.near(float(f["zero_s"]), el - grace, 1e-9, "dt %.1f: its zero clock runs from the grace's end (%.6f at %.1f s)" % [dt, float(f["zero_s"]), el])
		t.near(at, grace + brk, 1e-9, "dt %.1f: Needs WAR too: no garrison and nothing coming, retaken break_s after the grace (%.6f)" % [dt, at])
		t.ok(not f["held"] and f["zero_s"] == 0.0 and f["grace_s"] == 0.0, "dt %.1f: and is no longer held" % dt)


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


## A sim whose fort 0 (Ashgate, cap 80) is the only fort that can take anything: every other fort
## is `others` ("full": living at the cap, nothing else; "corpses": full of corpses, no undead, so
## no room and no target), and Vei has a full pool and a deep dead queue.
## Vei's shipping share for fort `f`, mass/s: S_vei from the test's config × its cap / Σ the forts'
## caps (so a config change moves the expectation with it).
static func _share_rate(sim: RealmSim, f: Dictionary) -> float:
	var sum_cap := 0.0
	for g in sim.forts:
		sum_cap += float(g["cap"])
	return float(TestUtil.configs()["realm"]["S_vei"]) * float(f["cap"]) / sum_cap


func _alone(over: Dictionary, others: String) -> RealmSim:
	var sim := _mk(over)
	for i in range(1, sim.forts.size()):
		var g: Dictionary = sim.forts[i]
		g["living"] = g["cap"] if others == "full" else 0.0
		g["undead"] = 0.0
		g["dead"] = 0.0 if others == "full" else g["cap"]
	sim.vei["living_pool"] = 600.0
	sim.vei["dead_queue"] = 1e5
	return sim


## E2b T4.C (MECHANICS §3.4): the room counts the clearing. Ashgate is a hair under its cap with a
## garrison, undead that neither drain nor get pulled (only kills move them), and no WAR: its only
## room is the corpses its clearing takes, which here is every kill (the corpses run short of
## k_clear · L). 120 steps of 0.125 s ship it her share each step; one 15 s step must ship the same
## (it shipped the 0.1 of room it started with when the clearing was left out), and end at or below
## its cap.
func _room_clearing(t: TestUtil) -> void:
	var shipped := {}
	var load_end := {}
	for dt in [0.125, 15.0]:
		var sim := _alone({"r_drain": 0.0, "k_destroy": 0.0}, "full")
		var f: Dictionary = sim.forts[0]
		f["living"] = 67.4
		f["undead"] = 12.5
		f["dead"] = 0.0
		var got := 0.0
		for i in int(round(15.0 / dt)):
			sim.step(dt, {"war": 0.0, "digest_q": 1.2})
			got += float(f["r_shipped"]) * dt
		shipped[dt] = got
		load_end[dt] = float(f["living"]) + float(f["undead"]) + float(f["dead"])
	var ref := _mk({})
	var share: float = _share_rate(ref, ref.forts[0]) * 15.0
	t.ok(absf(shipped[15.0] - shipped[0.125]) <= 1e-3 * shipped[0.125] and shipped[0.125] > 0.9 * share,
		"the room counts the clearing: one 15 s step ships what 120 of 0.125 s do, within 0.1%% (%.6f, %.6f; her share %.3f)" % [
		shipped[15.0], shipped[0.125], share])
	t.ok(load_end[15.0] <= 80.0 + 1e-9 and load_end[0.125] <= 80.0 + 1e-9,
		"and Ashgate ends at or below its cap (%.6f at 15 s, %.6f at 0.125 s)" % [load_end[15.0], load_end[0.125]])


## E2b T4.C (MECHANICS §3.2, M1): a full fort with no living where Relish raises takes the WAR that
## fills it with the raises counted: the corpses there, then what Vei ships in and her living
## killed on arrival leave. Ashgate starts as in pre_vei (no living, 70.95 undead, 9.05 corpses),
## WAR to spare (what it can't take falls through to Vei). At 15 s and at 0.5 s it ends every step
## at exactly its cap, and in its steady state takes the same WAR at both (at 15 s it ended 1.05
## short and took 4.53/s where 0.5 s took 4.59 while the raises were left out).
func _fill_raises(t: TestUtil) -> void:
	var war := {}
	for dt in [0.5, 15.0]:
		var sim := _alone({}, "corpses")
		var f: Dictionary = sim.forts[0]
		f["living"] = 0.0
		f["undead"] = 70.95
		f["dead"] = 9.05
		var worst := 0.0
		for i in int(round(600.0 / dt)):
			sim.step(dt, {"war": 20.0, "digest_q": 1.2, "redirect_fort": "ashgate", "redirect_rate": 4.0})
			worst = maxf(worst, absf(float(f["living"]) + float(f["undead"]) + float(f["dead"]) - 80.0))
		war[dt] = float(f["r_in"])
		t.ok(worst <= 1e-9 * 80.0 and float(f["r_raised"]) > 0.0 and float(f["r_shipped"]) > 0.0,
			"Relish raising at a full fort with no living, dt %.1f: it ends every step at its cap (worst %s off; raising %.3f/s of what Vei ships)" % [
			dt, String.num_scientific(worst), float(f["r_raised"])])
	t.ok(_rel(war[15.0], war[0.5]) <= 1e-9,
		"and it takes the same WAR at 15 s as at 0.5 s (%.9f, %.9f mass/s)" % [war[15.0], war[0.5]])


## E2b T4.C (MECHANICS §3.2): a fort full of corpses, with no living and a few undead, that WAR
## fills (WAR to spare) takes from Vei only what its undead kill. Her drain-room shipping
## (r_drain · U, cut to her share) is more than they kill (k_kill · U); what she would have shipped
## stayed as a sliver of living, and the next step that fort took all the WAR. With her conversion
## off, the cut stays in her pool: it drops by what she shipped, no more. At 0.25, 0.5 and 2 s:
## living ends every step at 0, shipping is the kills, mass is exact. With too little WAR to fill it
## she still ships into its room, more than its undead kill, so living gather there.
func _fill_kills(t: TestUtil) -> void:
	for dt in [0.25, 0.5, 2.0]:
		var sim := _alone({"R_vei": 0.0}, "corpses")
		var f: Dictionary = sim.forts[0]
		f["living"] = 0.0
		f["undead"] = 3.6
		f["dead"] = 76.4
		var before := sim.total_matter()
		var added := 0.0
		var worst_l := 0.0
		var worst_k := 0.0
		var worst_pool := 0.0
		var cut := 0.0
		var share: float = _share_rate(sim, f)
		for i in int(round(120.0 / dt)):
			var pool0 := float(sim.vei["living_pool"])
			sim.step(dt, {"war": 30.0, "digest_q": 1.2})
			added += 30.0 * dt
			worst_l = maxf(worst_l, float(f["living"]))
			worst_k = maxf(worst_k, _rel(float(f["r_shipped"]), float(f["r_kills"])))
			worst_pool = maxf(worst_pool, absf(pool0 - float(sim.vei["living_pool"]) - float(sim.vei["r_shipped"]) * dt))
			cut += (share - float(f["r_shipped"])) * dt
		t.ok(worst_l <= 1e-12 and worst_k <= 1e-9 and float(f["r_shipped"]) > 0.0,
			"dt %.2f: a corpse-full fort WAR fills ends every step with no living (worst %s), Vei shipping it its kills (worst %s off)" % [
			dt, String.num_scientific(worst_l), String.num_scientific(worst_k)])
		t.ok(cut > 1.0 and worst_pool <= 1e-9,
			"dt %.2f: what she didn't ship stays in her pool (%.2f of her share over 120 s; worst %s off)" % [dt, cut,
			String.num_scientific(worst_pool)])
		t.near(sim.total_matter(), before + added - sim.cleared_total - sim.pool_overflow, 1e-9 * (before + added),
			"dt %.2f: mass is exact" % dt)
	var sim := _alone({"R_vei": 0.0}, "corpses")
	var f: Dictionary = sim.forts[0]
	f["living"] = 0.0
	f["undead"] = 3.6
	f["dead"] = 76.4
	sim.step(2.0, {"war": 0.002, "digest_q": 1.2})
	t.ok(float(f["living"]) > 0.0 and float(f["r_shipped"]) > 1.5 * float(f["r_kills"]) and float(f["r_in"]) > 0.0,
		"with too little WAR to fill it she still ships into its room (%.4f/s against kills of %.4f/s), so living gather (%.4f)" % [
		float(f["r_shipped"]), float(f["r_kills"]), float(f["living"])])


# ------------------------------------------------------- E2b T4.P (M4) ----
## RealmSim with the _load skip off: every give computes its room.
class NoSkip extends RealmSim:
	func _load_cuts(_f: Dictionary, _dt: float, _w_in: float, _raise_in: float, _keep: bool, _s_i: float, _give: float) -> bool:
		return true


## The tunables are read once in setup, from the config; the _load skip changes nothing. Its bound is
## an upper bound on _load at any passes, so a skipped give is the give _load would have left; and a
## realm run with the skip is bit-identical to one without it, at 0.5 and 10 s, from the shipped
## start and from a midgame-like one (living, corpses and WAR everywhere, a held fort, a redirect).
func _m4(t: TestUtil) -> void:
	t.suite("realm_sim-m4")
	var cfg: Dictionary = TestUtil.configs()["realm"]
	var sim := _mk({})
	t.ok(sim._k_kill == float(cfg["k_kill"]) and sim._r_drain == float(cfg["r_drain"]) and sim._S_vei == float(cfg["S_vei"])
		and sim._surge_mult_t == float(cfg["tithe"]["surge_mult"]) and sim._march == float(cfg["tithe"]["march_back_s"])
		and sim._policy == str(cfg["veiPolicy"]), "setup reads the tunables from realm.json")
	var o := _mk({"k_kill": 0.5, "S_vei": 3.0})
	t.ok(o._k_kill == 0.5 and o._S_vei == 3.0, "an override at setup reaches the members")
	# the bound: random forts and inputs, every passes count
	var rng := RandomNumberGenerator.new()
	rng.seed = 41
	var bad := 0
	var skipped := 0
	for i in 4000:
		var f: Dictionary = sim.forts[rng.randi() % sim.forts.size()].duplicate(true)
		var cap := float(f["cap"])
		f["living"] = rng.randf_range(0.0, 1.2) * cap if rng.randf() < 0.8 else 0.0
		f["undead"] = rng.randf_range(0.0, 1.0) * cap if rng.randf() < 0.8 else 0.0
		f["dead"] = rng.randf_range(0.0, 0.5) * cap if rng.randf() < 0.7 else 0.0
		var dt: float = [0.5, 2.0, 10.0, 15.0, 30.0][rng.randi() % 5]
		var w_in := rng.randf_range(0.0, 20.0) if rng.randf() < 0.7 else 0.0
		var raise_in := rng.randf_range(0.0, 4.0) if rng.randf() < 0.3 else 0.0
		var keep := rng.randf() < 0.3
		var q := rng.randf_range(1.0, 4.0)
		var s_i := rng.randf_range(0.0, 0.2) * cap if rng.randf() < 0.2 else 0.0
		var give := rng.randf_range(0.0, 0.3) * cap
		if not sim._load_cuts(f, dt, w_in, raise_in, keep, s_i, give):
			skipped += 1
			for passes in [1, 4]:
				if cap - sim._load(f, dt, w_in, raise_in, keep, q, passes) - s_i < give:
					bad += 1
	t.ok(bad == 0 and skipped > 500, "a skipped give always fits the room _load computes, 1 or 4 passes (%d of %d skipped, %d wrong)" % [skipped, 4000, bad])
	# a run with the skip is the run without it, bit for bit
	for dt in [0.5, 10.0]:
		for start in ["shipped", "busy"]:
			var a := _mk({})
			var b := NoSkip.new()
			var all := TestUtil.configs()
			b.setup(all["world"], all["realm"])
			for s in [a, b]:
				s.vei["living_pool"] = 400.0
				s.vei["dead_queue"] = 50.0
				if start == "busy":
					for k in s.forts.size():
						var g: Dictionary = s.forts[k]
						g["living"] = float(g["cap"]) * (0.3 + 0.05 * k)
						g["undead"] = float(g["cap"]) * 0.2
						g["dead"] = float(g["cap"]) * 0.1
					s.hold(s.forts[2]["id"], 300.0)
				s.start_tithe()
			var inp := {"war": 25.0, "flood": 3.0, "digest_q": 1.4, "redirect_fort": a.forts[4]["id"] if start == "busy" else "",
				"redirect_rate": 4.0, "tide_fort": a.forts[1]["id"], "tide_bias": 3.0}
			for i in int(round(3600.0 / dt)):
				a.step(dt, inp)
				b.step(dt, inp)
			var same := a.vei == b.vei and a.tithe == b.tithe
			for k in a.forts.size():
				same = same and a.forts[k] == b.forts[k]
			t.ok(same and a._n_load_skipped > 0 and b._n_load_skipped == 0,
				"%s start, 1 h at %s s: with the skip (%d of %d loads skipped) the realm is bit-identical to without it" % [
				start, str(dt), a._n_load_skipped, a._n_load_skipped + a._n_load])
	t.suite("realm_sim")
