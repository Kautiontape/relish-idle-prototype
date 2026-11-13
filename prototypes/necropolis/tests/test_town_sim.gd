extends RefCounted
## TownSim (MECHANICS §4.1–§4.3): Covington's economy as a standalone module. Fast: no field,
## no GameState. Every number is read from the configs, so tuning never breaks these.

var t := TestUtil.new()
var _base := {}  # the real configs, loaded once


## The real configs, deep-copied, with `over` applied by dotted path ("economy.worker.idle_cap").
func _cfgs(over := {}) -> Dictionary:
	var c: Dictionary = _base.duplicate(true)
	for path in over:
		var keys: PackedStringArray = str(path).split(".")
		var d: Dictionary = c
		for i in keys.size() - 1:
			d = d[keys[i]]
		d[keys[keys.size() - 1]] = over[path]
	return c


func _sim(over := {}) -> TownSim:
	var s := TownSim.new()
	s.setup(_cfgs(over))
	s.new_game()
	return s


func _eco(section: String) -> Dictionary:
	return _base["economy"][section]


func _inp(over := {}) -> Dictionary:
	var d := {"work_mass": 0.0, "relish_home": false, "held_villages": 0, "forts": [], "cov_pos": [0.0, 0.0],
		"haul_target": "auto", "relics_available": 0}
	for k in over:
		d[k] = over[k]
	return d


## WORK (mass over dt) that holds `w` workers steady when they are all staffed.
func _hold_work(s: TownSim, w: float, dt: float) -> float:
	return w / s.lifetime_s(false) * float(_eco("worker")["mass"]) * dt


func _staffed(s: TownSim, job: String) -> float:
	return float(s.staffing["jobs"].get(job, {}).get("staffed", 0.0))


func _fort(id: String, x: float, dead: float, held := false) -> Dictionary:
	return {"id": id, "pos": [x, 0.0], "dead": dead, "held": held}


func run() -> int:
	t.suite("town_sim")
	_base = TestUtil.configs()
	var t0 := Time.get_ticks_msec()
	_start_state()
	_workforce()
	_ladder()
	_haul()
	_mill_stall_pit()
	_forge()
	_build()
	_living_morale()
	_upkeep()
	_round_trip()
	_handles()
	_soak()
	print("  [town_sim] suite ran in %d ms" % (Time.get_ticks_msec() - t0))
	return t.failures


# ------------------------------------------------------------- start state ----
func _start_state() -> void:
	var s := _sim()
	var op: Dictionary = _eco("opening")
	var want := {"lot-01": "crypt", "lot-02": "raising_pit", "lot-03": "charnel_house", "lot-04": "market"}
	var got := {}
	for lot in s.buildings:
		got[lot] = s.buildings[lot]["building_id"]
	t.ok(got == want, "new_game puts the BALANCE §0 buildings on their lots: %s" % [got])
	var all_active := true
	for lot in s.buildings:
		var b: Dictionary = s.buildings[lot]
		all_active = all_active and int(b["level"]) == 1 and b["state"] in ["active", "idle"] and int(b["staff_cap"]) == -1
	t.ok(all_active, "start buildings are level 1, working, uncapped")
	t.ok(s.gold == float(op["gold"]) and s.bone == float(op["bone"]) and s.bodies == float(op["bodies"])
		and s.workers == float(op["workers"]) and s.living == float(op["living"]),
		"stocks from economy.json opening (gold 80, bone 30, bodies 40, workers 12, living 10)")
	t.ok(s.ladder == _eco("job")["default_ladder"], "ladder is job.default_ladder")
	t.near(s.body_cap(), float(_eco("body_store")["cap"]), 1e-9, "start body cap is body_store.cap (the charnel's L1 adds nothing)")
	t.near(s.living_cap(), float(op["living_cap"]), 1e-9, "start living cap is opening.living_cap")
	t.near(s.morale_target(), float(_eco("morale")["base"]), 1e-9, "start morale target is morale.base (no start building adds morale)")
	t.near(s.morale, s.morale_target(), 1e-9, "start morale sits on its target")
	t.near(float(s.staffing["idle"]), 5.0, 1e-9, "12 workers fill 7 slots (haul 3, pit 2, stall 2): 5 idle")
	var out := s.step(0.5, _inp())
	t.near(float(out["rates"]["trade_rate"]), 0.30, 1e-9, "start trade: min(2 · 0.15, 10 · 0.03) = 0.30 sales/s")
	t.ok(int(out["pits"]) == 1, "one start pit")
	for k in ["pits", "feed", "muster_mass", "pickups", "relics_spent", "rot_overflow", "haul_overflow", "events", "rates"]:
		t.ok(out.has(k), "step output has %s" % k)


# --------------------------------------------------------------- workforce ----
func _workforce() -> void:
	var mass := float(_eco("worker")["mass"])
	var life := float(_eco("worker")["lifetime_s"])
	var home_mult := float(_base["realm"]["relish"]["home_rot_mult"])
	var ret := float(_eco("worker")["body_return"])
	var m := float(_eco("worker")["idle_rot_mult"])
	var cap := float(_eco("worker")["idle_cap"])

	# steady state (work / worker.mass) · lifetime: idle rot and muster out of the way
	var free := {"economy.worker.idle_cap": 1.0e6, "economy.worker.idle_rot_mult": 1.0}
	var s := _sim(free)
	s.workers = 0.0
	var work := 5.12  # mass/s: the start mint 12.8 × WORK 0.40
	for i in 120:
		s.step(60.0, _inp({"work_mass": work * 60.0}))
	t.near(s.workers, work / mass * life, 0.005 * work / mass * life, "steady state = (work / worker.mass) · lifetime (61.4)")
	t.near(float(s.rates["workers"]["steady"]), work / mass * life, 1e-6, "rates.workers.steady shows it")
	s = _sim(free)
	s.workers = 0.0
	for i in 120:
		s.step(60.0, _inp({"work_mass": work * 60.0, "relish_home": true}))
	t.near(s.workers, work / mass * life / home_mult, 0.005 * work / mass * life / home_mult,
		"home: steady state × 1 / home_rot_mult (lifetime ÷ 0.7)")
	t.near(s.lifetime_s(true), life / home_mult, 1e-9, "lifetime_s(home) = worker.lifetime_s / relish.home_rot_mult")

	# the exact update at 60 s steps matches 0.5 s steps within 1%
	for case in [{"w0": 0.0, "work": 5.12, "home": false, "name": "the opening, rising into muster"},
			{"w0": 30.0, "work": 0.4, "home": true, "name": "a big crew decaying through the idle band, at home"},
			{"w0": 3.0, "work": 0.6, "home": false, "name": "settling inside the idle band"}]:
		var fine := _sim()
		var coarse := _sim()
		fine.workers = case["w0"]
		coarse.workers = case["w0"]
		var mf := 0.0
		var mc := 0.0
		var rot_f := 0.0
		var rot_c := 0.0
		for i in 7200:
			var o := fine.step(0.5, _inp({"work_mass": case["work"] * 0.5, "relish_home": case["home"]}))
			mf += float(o["muster_mass"])
			rot_f += float(o["rates"]["workers"]["rot"]) * 0.5
		for i in 60:
			var o := coarse.step(60.0, _inp({"work_mass": case["work"] * 60.0, "relish_home": case["home"]}))
			mc += float(o["muster_mass"])
			rot_c += float(o["rates"]["workers"]["rot"]) * 60.0
		t.near(coarse.workers, fine.workers, 0.01 * maxf(1.0, fine.workers), "60 s steps match 0.5 s steps (workers): %s" % case["name"])
		t.near(mc, mf, 0.01 * maxf(mass, mf), "60 s steps match 0.5 s steps (muster mass): %s" % case["name"])
		t.near(rot_c, rot_f, 0.01 * maxf(1.0, rot_f), "60 s steps match 0.5 s steps (rot): %s" % case["name"])

	# the closed form w(t) = w_ss + (w0 − w_ss)·e^(−t/τ) under constant inflow, computed here from the
	# config alone, so a formula that is wrong at every step size still fails
	var r_a := 0.01  # workers/s: rL = 4.8, under the opening's 7 slots, so everyone stays staffed
	for dt in [300.0, 0.5]:
		var sa := _sim()
		sa.workers = 2.0
		for i in int(300.0 / dt):
			sa.step(dt, _inp({"work_mass": r_a * mass * dt}))
		var ss_a := r_a * life
		t.near(sa.workers, ss_a + (2.0 - ss_a) * exp(-300.0 / life), 1e-9,
			"all staffed: w = rL + (w0 − rL)e^(−t/L) after 300 s (dt %.1f)" % dt)
	var sh := _sim()
	sh.workers = 2.0
	sh.step(300.0, _inp({"work_mass": r_a * mass * 300.0, "relish_home": true}))
	var l_home := life / home_mult
	t.near(sh.workers, r_a * l_home + (2.0 - r_a * l_home) * exp(-300.0 / l_home), 1e-9,
		"home: the same closed form with lifetime / home_rot_mult")
	var r_b := 0.012  # ladder [stall]: S = 2, rL = 5.76, so w_ss = S + (rL − S)/m = 9.52, inside S + C
	for dt in [300.0, 0.5]:
		var sb := _sim()
		sb.ladder = ["stall"]
		sb.workers = 5.0
		for i in int(300.0 / dt):
			sb.step(dt, _inp({"work_mass": r_b * mass * dt}))
		var ss_b := 2.0 + (r_b * life - 2.0) / m
		t.near(sb.workers, ss_b + (5.0 - ss_b) * exp(-300.0 * m / life), 1e-9,
			"idle band: w = w_ss + (w0 − w_ss)e^(−t·m/L), w_ss = S + (rL − S)/m (dt %.1f)" % dt)

	# rot returns bodies at worker.body_return (all staffed: rot = w (1 − e^(−dt/L)))
	s = _sim()
	s.ladder = ["stall"]
	s.workers = 2.0
	s.bodies = 0.0
	var o := s.step(0.5, _inp())
	var rot := 2.0 * (1.0 - exp(-0.5 / life))
	t.near(s.workers, 2.0 - rot, 1e-12, "staffed workers rot at 1 / lifetime (exact)")
	t.near(s.bodies, rot * mass * ret, 1e-12, "rot returns rot · worker.mass · worker.body_return of bodies")
	t.near(float(o["rates"]["bodies"]["rot"]), rot * mass * ret / 0.5, 1e-9, "rates.bodies.rot is that per second")
	# home rot is slower: the rate × home_rot_mult
	s = _sim()
	s.ladder = ["stall"]
	s.workers = 2.0
	s.step(0.5, _inp({"relish_home": true}))
	t.near(2.0 - s.workers, 2.0 * (1.0 - exp(-0.5 * home_mult / life)), 1e-12, "home: rot rate × relish.home_rot_mult")
	# idle workers rot at idle_rot_mult
	s = _sim()
	s.ladder = []
	s.workers = 4.0
	s.step(0.5, _inp())
	t.near(4.0 - s.workers, 4.0 * (1.0 - exp(-0.5 * m / life)), 1e-12, "idle workers rot × worker.idle_rot_mult")
	# rot over the body cap is reported, not kept
	s = _sim()
	s.ladder = ["stall"]
	s.workers = 2.0
	s.bodies = s.body_cap() - 0.01
	o = s.step(0.5, _inp())
	t.near(s.bodies, s.body_cap(), 1e-12, "bodies stop at the body cap")
	t.near(float(o["rot_overflow"]), rot * mass * ret - 0.01, 1e-12, "the excess is rot_overflow (mass)")

	# idle beyond idle_cap is mustered (mass out)
	s = _sim()
	s.workers = 30.0  # 7 slots + idle_cap 10 = 17
	o = s.step(0.5, _inp())
	var slots := 7.0
	t.ok(float(o["muster_mass"]) >= (30.0 - slots - cap) * mass - 1e-9, "idle beyond worker.idle_cap mustered at once: %f mass" % float(o["muster_mass"]))
	t.ok(s.workers <= slots + cap + 1e-9, "workers end at or below slots + idle_cap")
	# pinned at the cap, the surplus inflow is mustered: r − (S + m·C) / L workers/s
	s = _sim()
	s.workers = slots + cap
	var r := 0.5  # workers/s, far above what 17 rot away
	o = s.step(2.0, _inp({"work_mass": r * mass * 2.0}))
	t.near(float(o["muster_mass"]), (r - (slots + m * cap) / life) * 2.0 * mass, 1e-9, "at the cap the surplus inflow musters at r − (S + m·C) / L")
	t.near(float(o["rates"]["workers"]["rot"]), (slots + m * cap) / life, 1e-12, "pinned: S staffed rot at 1/L and C idle at m/L")
	t.near(float(o["rates"]["workers"]["in"]) * 2.0, float(o["rates"]["workers"]["rot"]) * 2.0 + float(o["muster_mass"]) / mass, 1e-12,
		"pinned: inflow = rot + muster")
	t.near(s.workers, slots + cap, 1e-9, "and the workforce stays pinned at S + idle_cap")
	# conservation: in − rot − muster = Δworkers
	s = _sim()
	s.workers = 5.0
	o = s.step(60.0, _inp({"work_mass": 0.3 * mass * 60.0}))
	var wr: Dictionary = o["rates"]["workers"]
	t.near((float(wr["in"]) - float(wr["rot"]) - float(wr["muster"])) * 60.0, s.workers - 5.0, 1e-9, "workers: in − rot − muster = Δ, exactly")


# ------------------------------------------------------------------ ladder ----
func _ladder() -> void:
	var s := _sim()
	s.workers = 5.0
	s.step(0.5, _inp({"work_mass": _hold_work(s, 5.0, 0.5)}))
	t.ok(is_equal_approx(_staffed(s, "haul"), 3.0) and is_equal_approx(_staffed(s, "pit"), 2.0) and _staffed(s, "stall") < 1e-3,
		"default ladder: 5 workers fill haul 3, pit 2, stall 0")
	s = _sim()
	s.workers = 5.0
	s.buildings["lot-03"]["staff_cap"] = 1
	s.step(0.5, _inp())
	t.ok(is_equal_approx(_staffed(s, "haul"), 1.0) and is_equal_approx(_staffed(s, "pit"), 2.0),
		"a staff cap of 1 on the charnel house: haul 1, pit 2, the rest flows down")
	t.ok(is_equal_approx(float(s.staffing["slots"]), 5.0), "the cap shrinks the staffable slots to 5 (haul 1 + pit 2 + stall 2)")
	s = _sim()
	s.workers = 5.0
	s.ladder = ["stall", "pit", "haul", "build", "mill", "forge", "tend"]
	s.step(0.5, _inp({"work_mass": _hold_work(s, 5.0, 0.5)}))
	t.ok(is_equal_approx(_staffed(s, "stall"), 2.0) and is_equal_approx(_staffed(s, "pit"), 2.0) and is_equal_approx(_staffed(s, "haul"), 1.0),
		"reordered ladder: stall 2, pit 2, haul gets what is left")
	var jobs: Array = s.staffing["jobs"].keys()
	t.ok(jobs.slice(0, 3) == ["stall", "pit", "haul"], "staffing lists jobs in ladder order")
	# levels multiply slots; unpaid and constructing buildings offer none
	s = _sim()
	s.place_building("lot-04", "market", 2)
	s.workers = 20.0
	s.step(0.5, _inp())
	t.ok(int(s.staffing["jobs"]["stall"]["slots"]) == 4, "a level-2 market has 2 × 2 stall slots")
	s.buildings["lot-04"]["state"] = "unpaid"
	s.buildings["lot-04"]["unpaid_s"] = 1.0e6
	s.step(0.5, _inp())
	t.ok(int(s.staffing["jobs"]["stall"]["slots"]) == 0, "an unpaid market offers no slots")


# -------------------------------------------------------------------- haul ----
func _haul_sim(workers := 3.0) -> TownSim:
	var s := _sim()
	s.ladder = ["haul"]
	s.workers = workers
	s.bodies = 0.0
	return s


func _haul() -> void:
	var speed := float(_eco("job")["haul"]["speed"])
	var carry := float(_eco("job")["haul"]["carry"])
	var hm := float(_base["realm"]["flip"]["haul_mult"])
	var x := speed * 2.0  # a fort two seconds out
	# auto picks the richest corpse fort
	var s := _haul_sim()
	s.step(0.5, _inp({"forts": [_fort("a", x, 10.0), _fort("b", x, 50.0), _fort("c", x, 2.0)]}))
	t.ok(s.haul["current"] == "b", "auto hauls from the richest corpse fort")
	s = _haul_sim()
	var thin: float = float(_eco("job")["haul"]["auto_min_dead"]) * 0.5
	s.step(0.5, _inp({"forts": [_fort("a", x, thin), _fort("b", x, thin)]}))
	t.ok(s.haul["convoys"].is_empty(), "auto sends nobody when no fort is above job.haul.auto_min_dead")
	s = _haul_sim()
	s.step(0.5, _inp({"forts": [_fort("a", x, 10.0), _fort("b", x, 50.0)], "haul_target": "a"}))
	t.ok(s.haul["current"] == "a", "a set haul target is honoured over a richer fort")
	# carry per staffed hauler, picked up at arrival (trip = distance / speed)
	s = _haul_sim()
	var forts := [_fort("a", x, 100.0)]
	var picks: Array = []
	var arrived_step := -1
	for i in 6:
		var o := s.step(0.5, _inp({"forts": forts}))
		if not o["pickups"].is_empty():
			picks.append_array(o["pickups"])
			arrived_step = i
	t.ok(picks.size() == 1 and picks[0]["fort_id"] == "a", "one pickup in the first 3 s: %s" % [picks])
	t.near(float(picks[0]["mass"]) if picks.size() > 0 else 0.0, carry * 3.0, 1e-9, "the pickup is job.haul.carry × 3 haulers")
	t.ok(arrived_step == 3, "it lands at arrival, 2 s (distance / job.haul.speed) after departure (step %d)" % arrived_step)
	var b0 := s.bodies
	for i in 4:
		s.step(0.5, _inp({"forts": forts}))
	t.ok(s.bodies - b0 > carry * 3.0 - 1.0, "the load reaches the bodies store on the way back")
	s = _haul_sim(1.0)
	var got := 0.0
	for i in 4:
		for p in s.step(0.5, _inp({"forts": forts}))["pickups"]:
			got += float(p["mass"])
	t.near(got, carry, 1e-9, "one hauler carries job.haul.carry")
	# clamped to the fort's dead
	s = _haul_sim()
	got = 0.0
	for i in 4:
		for p in s.step(0.5, _inp({"forts": [_fort("a", x, 10.0)]}))["pickups"]:
			got += float(p["mass"])
	t.near(got, 10.0, 1e-9, "the pickup is clamped to the fort's dead")
	# × flip.haul_mult at a held fort
	s = _haul_sim()
	got = 0.0
	for i in 4:
		for p in s.step(0.5, _inp({"forts": [_fort("a", x, 1000.0, true)]}))["pickups"]:
			got += float(p["mass"])
	t.near(got, carry * 3.0 * hm, 1e-9, "a held fort yields × flip.haul_mult")
	# haulers idle at the body cap
	s = _haul_sim()
	s.bodies = s.body_cap()
	var o := s.step(0.5, _inp({"forts": forts}))
	t.ok(s.haul["convoys"].is_empty() and o["pickups"].is_empty(), "at the body cap no convoy leaves")
	# a long step runs many trips, and the total never exceeds the fort's dead
	s = _haul_sim()
	got = 0.0
	o = s.step(600.0, _inp({"forts": [_fort("a", x, 50.0)], "work_mass": _hold_work(s, 3.0, 600.0)}))
	for p in o["pickups"]:
		got += float(p["mass"])
	t.near(got, 50.0, 1e-9, "a 600 s step makes many trips, taking exactly the fort's 50 dead")
	t.ok(s.bodies <= s.body_cap() + 1e-9, "and the store stays within its cap")


# ------------------------------------------------------- mill, stall, pit ----
func _mill_stall_pit() -> void:
	var mill: Dictionary = _eco("job")["mill"]
	var s := _sim()
	t.ok(s.place_building("lot-05", "bone_mill", 1), "place_building puts a bone mill on lot-05")
	s.ladder = ["mill"]
	s.workers = 2.0
	s.bodies = 100.0
	var bone0 := s.bone
	var o := s.step(1.0, _inp({"work_mass": _hold_work(s, 2.0, 1.0)}))
	var milled := float(mill["mass_per_s"]) * 2.0 * 1.0
	t.near(float(o["rates"]["bodies"]["mill"]), milled, 1e-9, "2 millers process job.mill.mass_per_s each")
	t.near(s.bone - bone0, milled * float(mill["rate"]), 1e-9, "into job.mill.rate bone per mass")

	# the stall formula, both arms of the min
	var rate := float(_eco("stall")["rate"])
	var shop := float(_eco("market")["shop_rate"])
	var price := float(_eco("market")["price"])
	s = _sim()
	s.ladder = ["stall"]
	s.workers = 1.0
	s.living = 10.0
	o = s.step(0.5, _inp())
	t.near(float(o["rates"]["trade_rate"]), minf(1.0 * rate, 10.0 * shop), 1e-12, "stall arm: 1 stall sells stall.rate (0.15 < 10 · 0.03)")
	t.near(float(o["rates"]["gold"]["in"]), 1.0 * rate * price, 1e-12, "gold in = sales · market.price")
	s = _sim()
	s.ladder = ["stall"]
	s.workers = 2.0
	s.living = 4.0
	o = s.step(0.5, _inp())
	t.near(float(o["rates"]["trade_rate"]), 4.0 * shop, 1e-12, "living arm: 4 living buy 4 · market.shop_rate (< 2 · 0.15)")

	# pit feed is proportional: half the bodies it wants gives feed ≈ 0.5, every substep
	var burn := float(_eco("pit")["burn_per_s"])
	s = _sim({"economy.worker.body_return": 0.0})
	s.ladder = ["pit"]
	s.workers = 2.0
	s.bodies = 0.0
	var lo := 1.0
	var hi := 0.0
	for i in 120:
		s.bodies += burn * 0.5 * 0.5  # half of what one pit burns in 0.5 s
		o = s.step(0.5, _inp({"work_mass": _hold_work(s, 2.0, 0.5)}))
		lo = minf(lo, float(o["feed"]))
		hi = maxf(hi, float(o["feed"]))
	t.near(lo, 0.5, 0.005, "half the bodies: feed ≈ 0.5 (min %f)" % lo)
	t.near(hi, 0.5, 0.005, "and it never toggles across substeps (max %f)" % hi)
	s = _sim()
	s.ladder = ["pit"]
	s.workers = 1.0
	s.bodies = 100.0
	o = s.step(0.5, _inp())
	t.near(float(o["feed"]), 0.5, 1e-9, "a half-staffed pit burns half: feed 0.5 (wanted counts every pit)")
	# pit and mill share short bodies in proportion to demand
	s = _sim()
	s.place_building("lot-05", "bone_mill", 1)
	s.ladder = ["pit", "mill"]
	s.workers = 4.0
	s.bodies = 0.0
	s.bodies = 0.1  # wanted this step: pit 0.6 · 0.5 = 0.3, mill 0.4 · 0.5 = 0.2 → 0.5
	o = s.step(0.5, _inp({"work_mass": 0.0}))
	var share := float(o["rates"]["bodies"]["pit"]) / maxf(1e-12, float(o["rates"]["bodies"]["pit"]) + float(o["rates"]["bodies"]["mill"]))
	t.near(share, 0.6, 0.01, "short bodies split pit:mill in proportion to demand (0.3 : 0.2)")


# ------------------------------------------------------------------- forge ----
func _forge() -> void:
	var fc: Dictionary = _eco("forge")
	var rate := float(_eco("job")["forge"]["rate"])
	var need := float(fc["level_work"][0])
	var s := _sim()
	s.place_building("lot-13", "forge", 1)
	s.ladder = ["forge"]
	s.workers = 2.0
	var steps := int(ceil(need / (rate * 2.0) / 0.5)) + 20
	var spent := 0
	for i in steps:
		spent += int(s.step(0.5, _inp({"work_mass": _hold_work(s, 2.0, 0.5), "relics_available": 0}))["relics_spent"])
	t.ok(int(s.forge["level"]) == 0 and spent == 0, "without relics the forge level waits")
	t.near(float(s.forge["progress"]), need, 1e-9, "progress holds at forge.level_work[0]")
	var o := s.step(0.5, _inp({"work_mass": _hold_work(s, 2.0, 0.5), "relics_available": 5}))
	t.ok(int(s.forge["level"]) == 1, "with relics available the level completes")
	t.ok(int(o["relics_spent"]) == int(fc["level_relics"][0]), "relics_spent = forge.level_relics[0]")
	t.near(float(s.forge["progress"]), rate * 2.0 * 0.5, 1e-9, "the step's work past the level carries over")


# ------------------------------------------------------------------- build ----
func _build() -> void:
	var s := _sim()
	var r := s.start_construction("lot-05", "house", 1)
	t.ok(r["ok"], "start_construction on an empty lot: %s" % [r])
	t.ok(not s.start_construction("lot-01", "house", 1)["ok"], "an occupied lot is refused")
	t.ok(s.start_construction("lot-99", "house", 1)["reason"] == "unknown_lot", "an unknown lot is refused")
	t.ok(s.start_construction("lot-06", "nope", 1)["reason"] == "unknown_building", "an unknown building is refused")
	t.ok(s.start_construction("lot-06", "well", 2)["reason"] == "bad_level", "a new building starts at level 1")
	t.ok(s.buildings["lot-05"]["state"] == "constructing" and int(s.buildings["lot-05"]["level"]) == 0, "the lot is constructing, level 0")
	s.workers = 10.0
	var o := s.step(0.5, _inp())
	t.ok(o["events"].any(func(e): return e["type"] == "building_started" and e["lot_id"] == "lot-05"), "building_started comes out of the next step")
	var bslots := int(_eco("job")["build"]["slots"])
	t.ok(int(s.staffing["jobs"]["build"]["slots"]) == bslots, "a constructing lot offers job.build.slots build slots")
	t.near(s.living_cap(), float(_eco("opening")["living_cap"]), 1e-9, "a house under construction adds no living cap")
	var work := float(_base["buildings"]["house"]["build_work"])
	var per_s := float(_eco("job")["build"]["rate"]) * bslots
	var done := false
	var steps := 0
	while not done and steps < 10000:
		o = s.step(0.5, _inp({"work_mass": _hold_work(s, 10.0, 0.5)}))
		steps += 1
		done = o["events"].any(func(e): return e["type"] == "building_done" and e["lot_id"] == "lot-05")
	t.ok(done, "building_done when the build work is in")
	t.near(steps * 0.5 + 0.5, work / per_s, 0.6, "it takes build_work / (job.build.rate · staffed) seconds")
	t.ok(s.buildings["lot-05"]["state"] == "active" and int(s.buildings["lot-05"]["level"]) == 1, "the house is active at level 1")
	t.near(s.living_cap(), float(_eco("opening")["living_cap"]) + float(_base["buildings"]["house"]["effects"]["living_cap"]), 1e-9,
		"and adds its living cap")
	s.buildings["lot-05"]["state"] = "unpaid"
	t.ok(s.start_construction("lot-05", "house", 2)["reason"] == "unpaid", "an unpaid building can't upgrade")
	s.buildings["lot-05"]["state"] = "active"
	r = s.start_construction("lot-05", "house", 2)
	t.ok(r["ok"] and s.buildings["lot-05"]["state"] == "constructing" and int(s.buildings["lot-05"]["level"]) == 1, "an upgrade constructs from level 1")


# ---------------------------------------------------------- living, morale ----
func _living_morale() -> void:
	var town: Dictionary = _eco("town")
	var mo: Dictionary = _eco("morale")
	var s := _sim()
	s.place_building("lot-05", "house", 1)
	t.near(s.living_cap(), float(_eco("opening")["living_cap"]) + float(_base["buildings"]["house"]["effects"]["living_cap"]), 1e-9,
		"a house raises the living cap")
	var o := s.step(10.0, _inp({"held_villages": 2}))
	t.near(float(o["rates"]["living"]["in"]), 2.0 * float(town["migrant_rate"]), 1e-9, "migrants = held villages · town.migrant_rate")
	t.near(s.living, 10.0 + 2.0 * float(town["migrant_rate"]) * 10.0, 1e-9, "living grows by it")
	s.living = s.living_cap() - 0.01
	s.step(10.0, _inp({"held_villages": 10}))
	t.near(s.living, s.living_cap(), 1e-9, "living stops at living_cap")
	s = _sim()
	s.place_building("lot-13", "inn", 1)
	o = s.step(1.0, _inp())
	t.near(float(o["rates"]["living"]["in"]), float(_base["buildings"]["inn"]["effects"]["attract"]), 1e-9, "an inn attracts its effects.attract per level")
	# departures below the morale threshold
	s = _sim()
	s.morale = float(mo["leave_below"]) - 0.1
	s.add_shock(1.0)
	o = s.step(1.0, _inp())
	var k := float(town["leave_rate"])
	t.near(s.living, 10.0 * exp(-k), 1e-9, "below morale.leave_below the living leave at town.leave_rate (exact)")
	t.ok(float(o["rates"]["living"]["out"]) > 0.0, "and the departures show in rates")
	s = _sim()
	s.morale = float(mo["leave_below"]) + 0.1
	s.step(1.0, _inp())
	t.near(s.living, 10.0, 1e-12, "above it nobody leaves")
	# morale eases toward its target at morale.ease_per_s
	s = _sim()
	s.add_shock(0.3)
	t.near(s.morale_target(), float(mo["base"]) - 0.3, 1e-9, "a shock lowers the target")
	s.step(1.0, _inp())
	t.near(s.morale, float(mo["base"]) - float(mo["ease_per_s"]) * 1.0, 1e-9, "morale moves toward it at morale.ease_per_s")
	for i in 400:
		s.step(1.0, _inp())
	t.ok(s.morale > float(mo["base"]) - 0.3 + 0.01, "the shock decays over morale.shock_s, so morale recovers")
	# dread
	s = _sim({"economy.worker.idle_cap": 1.0e6})
	s.workers = 100.0
	s.living = 10.0
	var dread := (100.0 / 10.0 - float(mo["dread_ratio"])) * float(mo["dread_k"])
	var f: Array = s.morale_factors()
	var got := 0.0
	for e in f:
		if e["id"] == "dread":
			got = float(e["delta"])
	t.near(got, -dread, 1e-9, "dread = (workers / living − dread_ratio) · dread_k, shown as a factor")
	t.near(s.morale_target(), float(mo["base"]) - dread, 1e-9, "and subtracted from the target")
	s = _sim()
	s.place_building("lot-05", "well", 1)
	var amen := false
	for e in s.morale_factors():
		amen = amen or (e["id"] == "amenity:well" and is_equal_approx(float(e["delta"]), float(_base["buildings"]["well"]["effects"]["morale"])))
	t.ok(amen, "a well is an amenity factor (amenity:well)")


# ------------------------------------------------------------------ upkeep ----
func _upkeep() -> void:
	var hold := float(_eco("upkeep")["unpaid_hold_s"])
	# the cheapest building goes unpaid first
	var s := _sim()
	s.place_building("lot-05", "house", 1)
	s.ladder = []  # nobody sells: no income
	s.gold = 0.095  # owed this 1 s step: 0.03 · 3 + 0.01 = 0.10
	var o := s.step(1.0, _inp())
	t.ok(s.buildings["lot-05"]["state"] == "unpaid", "the house (0.01 gold/s, the cheapest) goes unpaid")
	var others := true
	for lot in ["lot-02", "lot-03", "lot-04"]:
		others = others and s.buildings[lot]["state"] != "unpaid"
	t.ok(others, "and nothing else does")
	t.ok(o["events"].any(func(e): return e["type"] == "building_unpaid" and e["lot_id"] == "lot-05" and e["building_id"] == "house" and e["unpaid"] == true),
		"building_unpaid{lot_id, building_id, unpaid: true}")
	t.near(s.gold, 0.005, 1e-9, "the rest is paid")
	# it holds for unpaid_hold_s, then resumes once affordable
	s.gold = 1000.0
	var resumed_at := -1.0
	for i in int(hold) + 5:
		o = s.step(1.0, _inp())
		if resumed_at < 0.0 and o["events"].any(func(e): return e["type"] == "building_unpaid" and e["unpaid"] == false):
			resumed_at = i + 1.0
	t.ok(resumed_at >= hold and resumed_at <= hold + 1.0, "it resumes after upkeep.unpaid_hold_s (at %f s)" % resumed_at)
	t.ok(s.buildings["lot-05"]["state"] == "active", "and is active again")
	# broke with no income: stocks never go negative and the market (the gold earner) keeps going
	s = _sim()
	s.ladder = []
	s.gold = 0.0
	s.step(1.0, _inp())
	t.ok(s.gold >= 0.0 and s.bone >= 0.0, "gold and bone never go below 0")
	t.ok(s.buildings["lot-02"]["state"] == "unpaid" and s.buildings["lot-03"]["state"] == "unpaid", "the pit and charnel house idle")
	t.ok(s.buildings["lot-04"]["state"] != "unpaid", "the market is never idled for the gold it earns (no softlock)")
	t.ok(s.buildings["lot-01"]["state"] != "unpaid", "the crypt (no upkeep) is never picked")
	# no chatter: income a little above the remaining upkeep, toggles stay ≥ hold apart
	s = _sim()
	s.ladder = ["stall"]
	s.workers = 1.0
	s.living = 2.5  # sales 0.075 gold/s vs upkeep 0.09
	s.gold = 0.0
	var last := {}
	var gaps_ok := true
	var n := 0
	var neg := false
	for i in 2400:
		o = s.step(0.5, _inp({"work_mass": _hold_work(s, 1.0, 0.5)}))
		neg = neg or s.gold < 0.0 or s.bone < 0.0
		for e in o["events"]:
			if e["type"] != "building_unpaid":
				continue
			n += 1
			var tnow := (i + 1) * 0.5
			if last.has(e["lot_id"]) and tnow - float(last[e["lot_id"]]) < hold - 1e-9:
				gaps_ok = false
			last[e["lot_id"]] = tnow
	t.ok(n >= 2 and gaps_ok, "a marginal economy idles and resumes with no chatter (%d events, each ≥ unpaid_hold_s apart)" % n)
	t.ok(not neg, "stocks never went negative")


# -------------------------------------------------------------- round trip ----
func _rich() -> TownSim:
	var s := _sim()
	s.place_building("lot-05", "house", 1)
	s.place_building("lot-13", "forge", 1)
	s.start_construction("lot-06", "well", 1)
	s.buildings["lot-03"]["staff_cap"] = 2
	s.ladder = ["build", "forge", "haul", "pit", "stall", "mill", "tend"]
	s.workers = 15.0
	s.add_shock(0.2)
	var forts := [_fort("a", 300.0, 80.0), _fort("b", 500.0, 20.0, true)]
	for i in 7:
		s.step(0.5, _inp({"forts": forts, "work_mass": 2.0, "held_villages": 1}))
	s.buildings["lot-05"]["state"] = "unpaid"
	s.buildings["lot-05"]["unpaid_s"] = 12.5
	return s


func _round_trip() -> void:
	var a := _rich()
	t.ok(not a.haul["convoys"].is_empty(), "the rich state has a convoy in flight")
	# settings changed after the last step (a command, a debug grant) must survive a load as saved
	a.ladder = []
	a.workers = 0.0
	t.ok(a.start_construction("lot-07", "house", 1)["ok"], "a build is queued just before the save")
	var d := a.to_dict()
	t.ok(d["pending"].size() == 1 and d["pending"][0]["type"] == "building_started", "its building_started is saved as pending")
	var text := JSON.stringify(d)
	var b := TownSim.new()
	b.setup(_cfgs())
	b.from_dict(JSON.parse_string(text))
	var db := b.to_dict()
	t.ok(db == d, "to_dict after a JSON round trip is equal")
	t.ok(JSON.stringify(db) == text, "and so is its JSON text (ints stay ints)")
	t.ok(text.find("inf") == -1 and text.find("nan") == -1, "no INF or NaN in the dict")
	# two loads of one file step identically
	a.from_dict(JSON.parse_string(text))
	var forts := [_fort("a", 300.0, 80.0), _fort("b", 500.0, 20.0, true)]
	for i in 200:
		var inp := _inp({"forts": forts, "work_mass": 2.0, "held_villages": 1, "relics_available": 1})
		a.step(0.5, inp)
		var ob := b.step(0.5, inp)
		if i == 0:
			t.ok(ob["events"].any(func(e): return e["type"] == "building_started" and e["lot_id"] == "lot-07" and e["level"] is int),
				"the loaded state returns the pending building_started from its first step")
	t.ok(JSON.stringify(a.to_dict()) == JSON.stringify(b.to_dict()), "two loads of one dict step identically for 100 s")


# -------------------------------------------------------------------- soak ----
# ------------------------------------------- GameState's handles (T2.3b) ----
func _handles() -> void:
	var s := _sim()
	var order := ["stall", "pit", "haul", "build", "mill", "forge", "tend"]
	s.set_ladder(order)
	t.ok(s.ladder == order and s.staffing["jobs"].keys() == order, "set_ladder sets the order and restaffs at once")
	t.ok(s.set_staff_cap("lot-04", 1) and s.buildings["lot-04"]["staff_cap"] == 1 and _staffed(s, "stall") == 1.0,
		"set_staff_cap caps a lot and restaffs at once")
	t.ok(not s.set_staff_cap("lot-09", 1) and not s.buildings.has("lot-09"), "set_staff_cap: false on an empty lot, nothing changes")
	s.set_staff_cap("lot-04", -1)
	s.workers = 3.0
	s.restaff()
	t.ok(_staffed(s, "stall") == 2.0 and _staffed(s, "pit") == 1.0 and s.buildings["lot-03"]["state"] == "idle",
		"restaff refills the slots from a changed workforce (and marks the unstaffed idle)")
	t.ok(s.pits() == 1, "pits(): the working pits")
	s.place_building("lot-05", "raising_pit", 2)
	t.ok(s.pits() == 3, "a level-2 pit counts 2")
	t.ok(s.lot_slots("lot-02") == 2 and s.lot_slots("lot-05") == 4 and s.lot_slots("lot-01") == 0 and s.lot_slots("lot-09") == 0,
		"lot_slots: jobs × level; none for the crypt or an empty lot")
	s.start_construction("lot-06", "house", 1)
	t.ok(s.lot_slots("lot-06") == int(_eco("job")["build"]["slots"]), "a construction offers the build slots")
	var full := _sim()
	var burn := float(_eco("pit")["burn_per_s"])
	t.ok(full.lot_output("lot-02", 6.0, 0.0) == {"mint": 6.0, "burn": burn}, "a staffed pit: {mint: P_per_pit, burn}")
	t.ok(full.lot_output("lot-04", 6.0, 0.0) == {"gold": minf(2.0 * float(_eco("stall")["rate"]), 10.0 * float(_eco("market")["shop_rate"])) * float(_eco("market")["price"])},
		"the market: its stalls' sales × price")
	t.ok(full.lot_output("lot-03", 6.0, 1.5) == {"bodies": 1.5} and full.lot_output("lot-01", 6.0, 1.5) == {} and full.lot_output("lot-09", 6.0, 1.5) == {},
		"the haulers: the trip-averaged haul; the crypt and an empty lot: none")
	full.set_staff_cap("lot-02", 1)
	t.ok(full.lot_output("lot-02", 6.0, 0.0) == {"mint": 6.0, "burn": burn * 0.5}, "a half-staffed pit burns half")
	full.place_building("lot-05", "bone_mill", 1)
	full.place_building("lot-13", "inn", 1)
	full.place_building("lot-14", "forge", 1)
	full.workers = 20.0
	full.restaff()
	var mill := float(_eco("job")["mill"]["mass_per_s"]) * float(_eco("job")["mill"]["rate"])
	t.ok(full.lot_output("lot-05", 6.0, 0.0) == {"bone": 2.0 * mill} and full.lot_output("lot-13", 6.0, 0.0) == {"living": float(_base["buildings"]["inn"]["effects"]["attract"])}
		and full.lot_output("lot-14", 6.0, 0.0) == {"forge": 2.0 * float(_eco("job")["forge"]["rate"])}, "a mill {bone}, an inn {living}, a forge {forge}")
	full.buildings["lot-04"]["state"] = "unpaid"
	t.ok(full.lot_output("lot-04", 6.0, 0.0) == {}, "an unpaid building gives no output")


func _soak() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var s := _sim()
	var lots: Array = []
	for l in _base["town"]["lots"]:
		lots.append(str(l["id"]))
	var ids: Array = _base["buildings"].keys()
	var jobs: Array = _eco("job")["default_ladder"].duplicate()
	var idle_cap := float(_eco("worker")["idle_cap"])
	var dts := [0.5, 0.5, 0.5, 2.0, 10.0, 60.0]
	var bad: Array = []
	var time := 0.0
	var steps := 0
	while time < 4.0 * 3600.0:
		var dt: float = dts[rng.randi() % dts.size()]
		if rng.randf() < 0.03:
			s.start_construction(lots[rng.randi() % lots.size()], ids[rng.randi() % ids.size()], 1)
		if rng.randf() < 0.01:
			var lot: String = lots[rng.randi() % lots.size()]
			if s.buildings.has(lot) and s.buildings[lot]["state"] != "constructing":
				s.start_construction(lot, s.buildings[lot]["building_id"], int(s.buildings[lot]["level"]) + 1)
		if rng.randf() < 0.01:
			jobs.shuffle()
			s.ladder = jobs.duplicate()
		if rng.randf() < 0.01:
			var lot: String = lots[rng.randi() % lots.size()]
			if s.buildings.has(lot):
				s.buildings[lot]["staff_cap"] = rng.randi_range(-1, 3)
		if rng.randf() < 0.005:
			s.gold = 0.0
		if rng.randf() < 0.005:
			s.add_shock(rng.randf_range(0.0, 0.5))
		var forts := [_fort("a", 300.0, rng.randf_range(0.0, 200.0), rng.randf() < 0.3),
			_fort("b", 700.0, rng.randf_range(0.0, 50.0), rng.randf() < 0.3), _fort("c", 1200.0, 0.0)]
		var targets := ["auto", "auto", "a", "b", "c"]
		var inp := _inp({"work_mass": rng.randf_range(0.0, 12.0) * dt, "relish_home": rng.randf() < 0.5,
			"held_villages": rng.randi_range(0, 6), "forts": forts, "haul_target": targets[rng.randi() % targets.size()],
			"relics_available": rng.randi_range(0, 2)})
		var o := s.step(dt, inp)
		time += dt
		steps += 1
		var vals := {"workers": s.workers, "bodies": s.bodies, "gold": s.gold, "bone": s.bone, "living": s.living,
			"morale": s.morale, "shock": s.shock, "feed": float(o["feed"]), "muster": float(o["muster_mass"]),
			"rot_overflow": float(o["rot_overflow"]), "haul_overflow": float(o["haul_overflow"])}
		for k in vals:
			if not is_finite(vals[k]) or vals[k] < 0.0:
				bad.append("%s = %f at %.1f s" % [k, vals[k], time])
		if s.bodies > s.body_cap() + 1e-6:
			bad.append("bodies %f over cap %f at %.1f s" % [s.bodies, s.body_cap(), time])
		if s.living > s.living_cap() + 1e-6:
			bad.append("living %f over cap %f at %.1f s" % [s.living, s.living_cap(), time])
		if s.morale > 1.0 or float(o["feed"]) > 1.0:
			bad.append("morale %f / feed %f over 1 at %.1f s" % [s.morale, float(o["feed"]), time])
		if s.workers > float(o["rates"]["workers"]["slots"]) + idle_cap + 1e-6:
			bad.append("workers %f over slots + idle_cap at %.1f s" % [s.workers, time])
		for p in o["pickups"]:
			for f in forts:
				if f["id"] == p["fort_id"] and float(p["mass"]) > float(f["dead"]) + 1e-9:
					bad.append("pickup %f over dead %f at %.1f s" % [float(p["mass"]), float(f["dead"]), time])
		for k in o["rates"]:
			var v: Variant = o["rates"][k]
			if v is Dictionary:
				for k2 in v:
					if not is_finite(float(v[k2])):
						bad.append("rates.%s.%s not finite" % [k, k2])
			elif not is_finite(float(v)):
				bad.append("rates.%s not finite" % k)
		if bad.size() > 5:
			break
	t.ok(bad.is_empty(), "4 h of random inputs (%d steps): no NaN, no negatives, every cap held %s" % [steps, bad])
	t.ok(int(s.forge["level"]) >= 0 and s.haul is Dictionary, "the soak ends in a sane state")
