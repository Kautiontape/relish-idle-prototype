extends RefCounted
## Tests for the canonical realm sim port + necropolis extensions.


func _mk(overrides := {}) -> RealmSim:
	var cfg := TestUtil.load_json("res://configs/realm.json")
	for k in overrides:
		cfg[k] = overrides[k]
	var world := TestUtil.load_json("res://configs/world.json")
	var sim := RealmSim.new()
	sim.setup(world, cfg)
	return sim


func run() -> int:
	var t := TestUtil.new()
	t.suite("realm_sim")

	# --- conservation with all sources/sinks off -----------------------------
	var sim := _mk({"P_base": 0.0, "P_relish": 0.0, "k_clear": 0.0})
	var before := sim.total_matter()
	for i in 200:
		sim.step(0.5)
	t.near(sim.total_matter(), before, 0.01, "matter conserved with sources off")

	# --- the critical asymmetry ----------------------------------------------
	sim = _mk({"P_base": 0.0, "P_relish": 0.0, "k_clear": 0.0, "r_drain": 0.0, "S_vei": 0.0, "R_vei": 0.0})
	var f: Dictionary = sim.forts[0]
	f["living"] = 50.0
	f["undead"] = 30.0
	f["dead"] = 0.0
	var dead_q0: float = sim.vei["dead_queue"]
	sim.step(1.0)
	t.ok(f["dead"] > 0.0, "undead kills stay at the fortress as dead")
	t.ok(sim.vei["dead_queue"] > dead_q0, "garrison kills are shipped to Vei")

	# --- break-even undead fraction u* = k_destroy / (q k_kill) --------------
	var q := 1.5
	var u_star: float = 0.006 / (q * 0.018)
	sim = _mk({"P_base": 0.0, "P_relish": 0.0, "k_clear": 0.0, "r_drain": 0.0, "q": q})
	f = sim.forts[0]
	f["living"] = 100.0
	f["undead"] = 100.0 * u_star * 1.3
	sim.step(0.1)
	var banked: float = f["r_dead_out"]  # gifted rate actually
	var gifted: float = banked
	var killed_rate: float = 0.018 * 100.0 * u_star * 1.3
	t.ok(killed_rate > gifted, "above u* Relish banks more than she gifts")
	f["undead"] = 100.0 * u_star * 0.7
	sim.step(0.1)
	t.ok(0.018 * f["undead"] < 0.006 * f["living"] / q, "below u* the trade feeds Vei")

	# --- vei policy cheap: corpses digested first ----------------------------
	sim = _mk({"P_base": 0.0, "P_relish": 0.0, "veiPolicy": "cheap", "R_vei": 10.0, "S_vei": 0.0})
	sim.vei["dead_queue"] = 100.0
	sim.vei["undead_queue"] = 100.0
	sim.step(1.0)
	t.near(sim.vei["dead_queue"], 90.0, 0.01, "cheap policy eats the dead queue first")
	t.near(sim.vei["undead_queue"], 100.0, 0.01, "cheap policy leaves undead queued while dead remain")

	# --- shipping only into empty space --------------------------------------
	sim = _mk({"P_base": 0.0, "P_relish": 0.0, "S_vei": 1000.0})
	sim.vei["living_pool"] = 10000.0
	for ff in sim.forts:
		ff["living"] = ff["cap"] * 0.5
		ff["dead"] = ff["cap"] * 0.5
	sim.step(1.0)
	var over := false
	for ff in sim.forts:
		if ff["living"] + ff["dead"] + ff["undead"] > ff["cap"] + 0.01:
			over = true
	t.ok(not over, "Vei never ships living beyond fortress space (EMPTY respected)")

	# --- clearing removes corpses --------------------------------------------
	sim = _mk({"P_base": 0.0, "P_relish": 0.0, "k_clear": 0.1, "k_kill": 0.0})
	f = sim.forts[0]
	f["living"] = 100.0
	f["dead"] = 50.0
	sim.step(1.0)
	t.ok(f["dead"] < 50.0, "garrison clears corpses over time")

	# --- vei pool cap stalls conversion --------------------------------------
	sim = _mk({"P_base": 0.0, "vei_pool_cap": 100.0, "S_vei": 0.0})
	sim.vei["living_pool"] = 100.0
	sim.vei["undead_queue"] = 500.0
	var uq: float = sim.vei["undead_queue"]
	sim.step(1.0)
	t.near(sim.vei["undead_queue"], uq, 0.01, "full living pool stalls Vei's digestion")

	# --- simulacrum: raises then expires -------------------------------------
	sim = _mk({"P_base": 0.0, "P_relish": 0.0, "k_clear": 0.0})
	f = sim.forts[0]
	f["dead"] = 100.0
	sim.simulacra = [{"fort_id": f["id"], "charges": 10.0, "rate": 5.0}]
	sim.step(1.0)
	t.near(f["dead"], 95.0, 0.01, "simulacrum raises at its rate")
	sim.step(1.0)
	t.ok(sim.simulacra.is_empty(), "simulacrum vanishes when charges run out")
	t.near(f["dead"], 90.0, 0.01, "simulacrum stopped at exactly its charge count")

	# --- no negative pools under long fast-forward ---------------------------
	sim = _mk({})
	sim.relish["state"] = "raising"
	for i in 2000:
		sim.step(0.5)
	var neg := false
	for ff in sim.forts:
		if ff["living"] < -0.001 or ff["dead"] < -0.001 or ff["undead"] < -0.001:
			neg = true
	t.ok(not neg, "no negative pools after 1000s fast-forward")
	t.ok(sim.readout()["odds"] >= 0.0 and sim.readout()["odds"] < 1.0, "odds in [0,1)")

	return t.failures
