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
	t.near(f["r_dead_out"], 0.006 * 100.0 / q, 1e-9, "the garrison's kills fall with digest_q")
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
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	before = sim.total_matter()
	var added := 0.0
	var neg := false
	var over_pool := false
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
		for ff in sim.forts:
			if ff["living"] < -1e-9 or ff["dead"] < -1e-9 or ff["undead"] < -1e-9 or ff["held_s"] < 0.0:
				neg = true
		for k in ["undead_queue", "dead_queue", "living_pool"]:
			if sim.vei[k] < -1e-9:
				neg = true
		if sim.vei["living_pool"] > float(sim.t["vei_pool_cap"]) + 1e-9:
			over_pool = true
		sim.drain_events()
	t.ok(not neg, "no negative pool after 2000 s of random inputs, holds and simulacra")
	t.ok(not over_pool, "Vei's pool never exceeds its cap")
	t.near(sim.total_matter(), before + added - sim.cleared_total, 1e-6 * maxf(1.0, before + added),
		"matter: start + WAR + FLOOD − cleared")
	t.ok(sim.readout()["odds"] >= 0.0 and sim.readout()["odds"] < 1.0, "odds in [0,1)")
	t.ok(not sim.readout().has("directShare") and not sim.t.has("directShare"), "directShare is gone")

	return t.failures
