extends RefCounted
## The wave train (E2b-2 T3.4b; MECHANICS §3.5): a held fort's "safe" judged against her waves at her
## period, the held forts run forward together from today's state (RealmSim.train_probe), and GameState's
## cache and frame refresh around it. Constructed forts on a RealmSim with every other fort full of
## corpses (so WAR reaches only the held forts), her pool full, odds 0, q 1.2. Headless, no autoloads.

var t: TestUtil
var _r := 0.0  # r_drain


func run() -> int:
	t = TestUtil.new()
	_r = float(TestUtil.configs()["realm"]["r_drain"])
	_later_wave()
	_settles()
	_shielded()
	_settled_rule()
	_targets_sim()
	_grace()
	_still_jump()
	_fall_early()
	_fall_planned()
	_arrival()
	_settled_support()
	_cache()
	_frame()
	_reset()
	_retarget()
	return t.failures


## A RealmSim with `held` {fort_id: [undead, living, grace_s]} held and every other fort full of corpses,
## her pool full, odds 0, her clock started with the next wave `next_s` away.
func _mk(held: Dictionary, next_s: float, cfg := {}) -> RealmSim:
	var all := TestUtil.configs() if cfg.is_empty() else cfg
	var sim := RealmSim.new()
	sim.setup(all["world"], all["realm"])
	sim.vei["living_pool"] = float(all["realm"]["vei_pool_cap"])
	for o in sim.forts:
		o["living"] = 0.0
		o["undead"] = 0.0
		o["dead"] = float(o["cap"])
	for id in held:
		var f := sim.fort_by_id(id)
		f["dead"] = 0.0
		sim.hold(id, float(held[id][2]))
		f["undead"] = float(held[id][0])
		f["living"] = float(held[id][1])
	sim.start_tithe()
	sim.tithe["next_s"] = next_s
	return sim


## train_probe's support for `wars` {fort_id: WAR mass/s}: no Relish, no siege.
static func _sup(wars: Dictionary) -> Dictionary:
	var s := {}
	for id in wars:
		s[id] = [float(wars[id]), false, 4.0, false, 0.0]
	return s


## [margin, cause] from readout_of at `w` mass/s of WAR, with the fort's train verdict (`train`) or the
## one-wave probe ({}).
static func _word(sim: RealmSim, id: String, w: float, train: Dictionary) -> Array:
	var ro := sim.readout_of(sim.fort_by_id(id), w, false, 4.0, false, 0.0, 1.2, train)
	return [ro["margin"], ro["margin_cause"]]


## RealmSim's own steps forward at `dt` for `secs`: [[event type, fort_id, seconds in], ...] for the waves
## and the retakes.
static func _forward(sim: RealmSim, inp: Dictionary, secs: float, dt: float) -> Array:
	var out: Array = []
	var el := 0.0
	while el < secs - 1e-9:
		sim.step(dt, inp)
		for e in sim.drain_timed():
			var ev: Dictionary = e[1]
			if ev["type"] in ["tithe_wave", "fort_retaken"]:
				out.append([ev["type"], str(ev["fort_id"]), el + float(e[0])])
		el += dt
	return out


static func _waves(evs: Array) -> Array:
	return evs.filter(func(e): return e[0] == "tithe_wave").map(func(e): return e[1])


static func _retaken(evs: Array) -> Array:
	return evs.filter(func(e): return e[0] == "fort_retaken")


# ------------------------------------------------------------------------- the train's verdicts ----
## A contested Ashgate at 1.06 mass/s of WAR (its garrison at the level that holds, no living): one full
## wave from the weakest state its support leaves doesn't break it (the one-wave probe reads safe), but the
## train does, on a later wave: her living from the first haven't gone when the second lands. RealmSim's own
## 0.5 s steps break it on a later wave too. (The revert proof: the one-wave margin reads safe.)
func _later_wave() -> void:
	t.suite("wave-train-later")
	var w := 1.06
	var sim := _mk({"ashgate": [w / _r, 0.0, 0.0]}, sim_period())
	var tr := sim.train_probe(_sup({"ashgate": w}), 1.2)
	var v: Dictionary = tr["forts"]["ashgate"]
	t.ok(_word(sim, "ashgate", w, {}) == ["safe", ""], "the one-wave probe reads it safe (the premise)")
	t.ok(bool(v["broken"]) and (tr["targets"] as Array).size() >= 2,
		"the train breaks it, and not on the first wave (%d waves started, all at Ashgate: %s)" % [(tr["targets"] as Array).size(), str(tr["targets"])])
	t.ok(_word(sim, "ashgate", w, v) == ["thin", "wave"], "so it reads thin (wave)")
	var evs := _forward(_mk({"ashgate": [w / _r, 0.0, 0.0]}, sim_period()), {"war": w, "digest_q": 1.2}, 4.0 * sim_period(), 0.5)
	var ret := _retaken(evs)
	var before := 0
	if not ret.is_empty():
		before = evs.filter(func(e): return e[0] == "tithe_wave" and float(e[2]) < float(ret[0][2])).size()
	t.ok(ret.size() == 1 and before >= 2, "RealmSim at 0.5 s: retaken after %d waves, at %.0f s" % [before, float(ret[0][2]) if not ret.is_empty() else -1.0])


func sim_period() -> float:
	return float(TestUtil.configs()["realm"]["tithe"]["period_s"])


## A contested Ashgate at 3.0 mass/s: each wave's living are gone before the next, so the fort repeats from
## the first cycle (settled, p 1, within two cycles) and reads safe; RealmSim's own steps hold it through
## eight waves.
func _settles() -> void:
	t.suite("wave-train-settles")
	var w := 3.0
	var sim := _mk({"ashgate": [w / _r, 0.0, 0.0]}, sim_period())
	var tr := sim.train_probe(_sup({"ashgate": w}), 1.2)
	t.ok(bool(tr["settled"]) and int(tr["p"]) == 1 and int(tr["cycles"]) <= 2 and not bool(tr["forts"]["ashgate"]["broken"]),
		"settled, p %d, in %d cycles" % [tr["p"], tr["cycles"]])
	t.ok(_word(sim, "ashgate", w, tr["forts"]["ashgate"]) == ["safe", ""], "it reads safe")
	var evs := _forward(_mk({"ashgate": [w / _r, 0.0, 0.0]}, sim_period()), {"war": w, "digest_q": 1.2}, 8.5 * sim_period(), 0.5)
	t.ok(_retaken(evs).is_empty() and _waves(evs).size() >= 8, "RealmSim at 0.5 s holds it through %d waves" % _waves(evs).size())


## The shielded fort. Ashgate (1.2 mass/s, A) and Old Sluice (0.4, B), both at their levels: A has the
## larger garrison at every warning, so every wave goes to A and B is never hit, its state the same at every
## wave's start (a per-fort "no weaker than last cycle" would call it settled). A takes three cycles to
## repeat. With hold.train_max_cycles 2 the set hasn't settled by the cap, so B reads thin (wave), not safe;
## with the shipped 4 it has, and B reads what the joint rule gives (safe: no wave can reach it while A
## outranks it). Then Old Sluice at 0.81 next to Ashgate at 1.19 (the split 2.0 mass/s of WAR gives them):
## A's garrison falls below B's at the second warning, so the train tests B, and B breaks.
func _shielded() -> void:
	t.suite("wave-train-shielded")
	var wa := 1.2
	var wb := 0.4
	for cap_c in [2, 4]:
		var cfg := TestUtil.configs()
		cfg["realm"]["hold"]["train_max_cycles"] = cap_c
		var sim := _mk({"ashgate": [wa / _r, 0.0, 0.0], "old-sluice": [wb / _r, 0.0, 0.0]}, sim_period(), cfg)
		var tr := sim.train_probe(_sup({"ashgate": wa, "old-sluice": wb}), 1.2)
		var b_same := true
		var s0: PackedFloat64Array = tr["samples"][0][3]
		for smp in tr["samples"]:
			var st: PackedFloat64Array = smp[3]
			b_same = b_same and absf(st[4] - s0[4]) < 1e-6 * maxf(1.0, s0[4]) and absf(st[5] - s0[5]) < 1e-6
		var all_a: bool = (tr["targets"] as Array).all(func(x): return x == "ashgate")
		t.ok(all_a and b_same and not bool(tr["forts"]["old-sluice"]["broken"]),
			"cap %d: every wave goes to Ashgate (%s); Old Sluice is never hit and repeats at every wave's start" % [cap_c, str(tr["targets"])])
		var word := _word(sim, "old-sluice", wb, tr["forts"]["old-sluice"])
		if cap_c == 2:
			t.ok(not bool(tr["settled"]) and int(tr["cycles"]) == 2 and word == ["thin", "wave"],
				"cap 2: Ashgate hasn't repeated by the cap, so Old Sluice reads thin (wave), not safe: %s" % str(word))
		else:
			t.ok(bool(tr["settled"]) and word == ["safe", ""], "cap 4: the set settles (p %d, %d cycles); Old Sluice reads safe" % [tr["p"], tr["cycles"]])
	# the split of 2.0 mass/s between the two (their dispatch weights)
	var sim := _mk({"ashgate": [0.0, 0.0, 0.0], "old-sluice": [0.0, 0.0, 0.0]}, sim_period())
	sim.step(0.5, {"war": 2.0, "digest_q": 1.2})
	var wars: Array = sim.war_at(2.0)[0]
	var w_a: float = wars[0]
	var w_b: float = wars[1]
	var s2 := _mk({"ashgate": [w_a / _r, 0.0, 0.0], "old-sluice": [w_b / _r, 0.0, 0.0]}, sim_period())
	var tr := s2.train_probe(_sup({"ashgate": w_a, "old-sluice": w_b}), 1.2)
	t.ok(w_a > w_b and (tr["targets"] as Array).slice(0, 2) == ["ashgate", "old-sluice"] and bool(tr["forts"]["old-sluice"]["broken"])
		and _word(s2, "old-sluice", w_b, tr["forts"]["old-sluice"]) == ["thin", "wave"],
		"Ashgate %.3f, Old Sluice %.3f: the second wave goes to Old Sluice (%s), which breaks: thin (wave)" % [w_a, w_b, str(tr["targets"])])


## The settled test (RealmSim._train_settled) on made-up samples, two forts, both waves at A (index 0): B,
## never a target, must repeat both ways (a garrison still rising, or her living still falling, could draw a
## wave it was never tested against); A, every wave's target, only no weaker (more undead keep the waves on
## it). ε = hold.train_settle_tol × cap.
func _settled_rule() -> void:
	t.suite("wave-train-settled-rule")
	var sim := _mk({"ashgate": [10.0, 0.0, 0.0], "old-sluice": [5.0, 0.0, 0.0]}, 100.0)
	var cap := PackedFloat64Array([80.0, 80.0])
	var keep: Array[bool] = [false, false]
	var eps := float(TestUtil.configs()["realm"]["hold"]["train_settle_tol"]) * 80.0
	var smp := func(ua: float, la: float, ub: float, lb: float) -> Array:
		return [0, false, 0, PackedFloat64Array([ua, la, 0.0, 0.0, ub, lb, 0.0, 0.0]), [true, true]]
	var cases := [
		["the same", [10.0, 3.0, 5.0, 0.0], 1],
		["A's garrison up 2ε", [10.0 + 2.0 * eps, 3.0, 5.0, 0.0], 1],
		["A's living down 2ε", [10.0, 3.0 - 2.0 * eps, 5.0, 0.0], 1],
		["A's garrison down 2ε", [10.0 - 2.0 * eps, 3.0, 5.0, 0.0], 0],
		["A's living up 2ε", [10.0, 3.0 + 2.0 * eps, 5.0, 0.0], 0],
		["B's garrison up 2ε", [10.0, 3.0, 5.0 + 2.0 * eps, 0.0], 0],
		["B's garrison up ε/2", [10.0, 3.0, 5.0 + 0.5 * eps, 0.0], 1],
		["B's living down 2ε", [10.0, 3.0, 5.0, -2.0 * eps], 0],
	]
	for c in cases:
		var v: Array = c[1]
		var samples := [smp.call(10.0, 3.0, 5.0, 0.0), smp.call(v[0], v[1], v[2], v[3])]
		t.ok(sim._train_settled(samples, 1, 0, cap, keep) == int(c[2]), "%s: %s" % [c[0], "settled (p 1)" if int(c[2]) == 1 else "not settled"])
	var late: Array = smp.call(10.0, 3.0, 5.0, 0.0)
	var st: PackedFloat64Array = late[3]
	st[3] = 1.0
	late[3] = st
	var pinned := [smp.call(10.0, 3.0, 5.0, 0.0), late]
	t.ok(sim._train_settled(pinned, 1, 0, cap, keep) == 0, "a garrison with its zero clock running as the wave starts: not settled")


## The targets follow _tithe_target's rule, as RealmSim's own steps run forward pick them: Ashgate and Old
## Sluice with 2.0 and 3.0 mass/s of WAR split by the dispatch, garrisons at their levels. The fort with
## more undead takes each wave; at 2.0 Ashgate's first wave leaves it below Old Sluice at the second
## warning, so Old Sluice takes the second (and is retaken in both); at 3.0 Ashgate keeps them all.
func _targets_sim() -> void:
	t.suite("wave-train-targets")
	for war in [2.0, 3.0]:
		var sim := _mk({"ashgate": [0.0, 0.0, 0.0], "old-sluice": [0.0, 0.0, 0.0]}, sim_period())
		sim.step(0.5, {"war": war, "digest_q": 1.2})
		var wars: Array = sim.war_at(war)[0]
		var held := {"ashgate": [float(wars[0]) / _r, 0.0, 0.0], "old-sluice": [float(wars[1]) / _r, 0.0, 0.0]}
		var tr := _mk(held, sim_period()).train_probe(_sup({"ashgate": wars[0], "old-sluice": wars[1]}), 1.2)
		var evs := _forward(_mk(held, sim_period()), {"war": war, "digest_q": 1.2}, 6.5 * sim_period(), 0.5)
		var got: Array = _waves(evs)
		var want: Array = tr["targets"]
		var n := mini(got.size(), want.size())
		var ret_sim := _retaken(evs).map(func(e): return e[1])
		var ret_probe: Array = []
		for id in tr["forts"]:
			if tr["forts"][id]["broken"]:
				ret_probe.append(id)
		t.ok(n >= 2 and got.slice(0, n) == want.slice(0, n) and ret_sim == ret_probe,
			"WAR %.1f: the probe's targets %s are RealmSim's %s; retaken: probe %s, sim %s" % [war, str(want), str(got.slice(0, n)), str(ret_probe), str(ret_sim)])
		if war == 2.0:
			t.ok(want.slice(0, 2) == ["ashgate", "old-sluice"], "WAR 2.0: Old Sluice takes the second wave")
		else:
			t.ok(want.all(func(x): return x == "ashgate"), "WAR 3.0: Ashgate takes every wave")


## A fort in grace: Ashgate with 300 s of grace and a pending warning naming it, the wave due in 100 s. The
## warning is dropped and made again for another target (here a fort the probe doesn't hold: ""), so the
## first wave threatens none; the next, warned at 370 s (after the grace), is Ashgate's. A warning made
## during the grace would have gone elsewhere too: the target is fixed at the warning. RealmSim's own steps
## send the first wave elsewhere and the second to Ashgate. The margin is the post-grace one: at 1.06 mass/s the train
## after the grace breaks it (thin), at 3.0 it settles (safe).
func _grace() -> void:
	t.suite("wave-train-grace")
	for c in [[1.06, ["thin", "wave"]], [3.0, ["safe", ""]]]:
		var w: float = c[0]
		var mk := func() -> RealmSim:
			var s := _mk({"ashgate": [0.0, 0.0, 300.0]}, 100.0)
			s.tithe["warning"] = {"wave_id": 1, "fort_id": "ashgate", "eta_s": 100.0, "surge": 24.0}
			return s
		var sim: RealmSim = mk.call()
		var tr := sim.train_probe(_sup({"ashgate": w}), 1.2)
		var tg: Array = tr["targets"]
		t.ok(tg.size() >= 2 and tg[0] == "" and tg[1] == "ashgate",
			"WAR %.2f: the first wave (in grace) threatens none, the second is Ashgate's: %s" % [w, str(tg)])
		t.ok(bool(tr["samples"][0][1]) and not bool(tr["samples"][1][1]), "the first wave starts in grace, the second after it")
		t.ok(_word(sim, "ashgate", w, tr["forts"]["ashgate"]) == c[1], "WAR %.2f: the post-grace margin %s" % [w, str(c[1])])
		var evs := _forward(mk.call(), {"war": w, "digest_q": 1.2}, 100.0 + 1.5 * sim_period(), 0.5)
		var got := _waves(evs)
		t.ok(got.size() >= 2 and got[0] != "ashgate" and got[1] == "ashgate", "RealmSim: the first wave goes to %s, the second to %s" % [
			got[0] if got.size() > 0 else "-", got[1] if got.size() > 1 else "-"])


## The still jump (RealmSim._train_still): while every fort has no living and kills her reship as it lands
## (or is in grace), the probe steps straight to the next event. It changes nothing: the verdicts, targets,
## p, cycles and every sample agree with hold.probe_dt_s steps (train_jump off) to 1e-9, in fewer steps.
func _still_jump() -> void:
	t.suite("wave-train-still")
	var cases := [
		["Ashgate at 3.0", {"ashgate": [50.0, 0.0, 0.0]}, {"ashgate": 3.0}, sim_period()],
		["Ashgate in grace", {"ashgate": [0.0, 0.0, 300.0]}, {"ashgate": 3.0}, 100.0],
		["Ashgate 1.2, Old Sluice 0.4", {"ashgate": [20.0, 0.0, 0.0], "old-sluice": [0.4 / _r, 0.0, 0.0]}, {"ashgate": 1.2, "old-sluice": 0.4}, sim_period()],
	]
	for c in cases:
		var a := _mk(c[1], c[3])
		var b := _mk(c[1], c[3])
		b.train_jump = false
		var ta := a.train_probe(_sup(c[2]), 1.2)
		var tb := b.train_probe(_sup(c[2]), 1.2)
		var same: bool = ta["forts"] == tb["forts"] and ta["targets"] == tb["targets"] and ta["p"] == tb["p"] and ta["cycles"] == tb["cycles"] \
			and ta["samples"].size() == tb["samples"].size()
		var worst := 0.0
		if same:
			for k in ta["samples"].size():
				var sa: PackedFloat64Array = ta["samples"][k][3]
				var sb: PackedFloat64Array = tb["samples"][k][3]
				for j in sa.size():
					worst = maxf(worst, absf(sa[j] - sb[j]) / maxf(1.0, absf(sb[j])))
		t.ok(same and worst < 1e-9 and int(ta["steps"]) < int(tb["steps"]),
			"%s: the same verdicts and samples (worst %s) in %d steps, not %d" % [c[0], String.num_scientific(worst), ta["steps"], tb["steps"]])


## fall_s errs early (T3.4b §4; MECHANICS §3.5): RealmSim's own 0.5 s steps with no wave retake each fort
## no sooner than its fall_s. The cases where the old line (grace + G / −rate + break_s) read late: a full
## garrison above the level its WAR holds (the drain empties it faster than the line), with and without
## WAR; one at that level (early before and after); one already pinned at 0 with its zero clock running
## (the old line counted the whole break_s).
func _fall_early() -> void:
	t.suite("wave-train-fall")
	var horizon := float(TestUtil.configs()["realm"]["hold"]["safe_horizon_s"])
	for c in [["full, 0.3 mass/s", 0.3, 80.0, 0.0, 0.0], ["full, no WAR", 0.0, 80.0, 0.0, 0.0], ["at its level, 0.2", 0.2, 0.2 / _r, 0.0, 0.0],
			["pinned, zero clock 60 s", 0.2, 0.0, 200.0, 60.0]]:
		var sim := _mk({"ashgate": [c[2], c[3], 0.0]}, 1e9)
		var f := sim.fort_by_id("ashgate")
		f["zero_s"] = float(c[4])
		var ro := sim.readout_of(f, c[1], false, 4.0, false, 0.0, 1.2)
		var evs := _retaken(_forward(sim, {"war": c[1], "digest_q": 1.2}, horizon, 0.5))
		var at := float(evs[0][2]) if not evs.is_empty() else INF
		t.ok(float(ro["fall_s"]) >= 0.0 and float(ro["fall_s"]) <= at, "%s: fall_s %.0f s, retaken at %.0f s (early by %.0f s)" % [
			c[0], ro["fall_s"], at, at - float(ro["fall_s"])])


## fall_s at the planned support (the T3.4b fix batch, the run's manager): a new game with every fort but
## Ashgate full of corpses (all WAR goes to it), no WORK (so no muster), Ashgate contested at the level its
## 0.45 WAR share holds and the waves pushed off; then cmd_set_valve cuts WAR to 0. A substep in, the valve
## is still slewing, its split still holds the fort (garrison_rate > 0) and the current support's clock says
## it doesn't fall (−1: late, since it does). view_fort's fall_s reads the earlier of that and the planned
## support's (the valve's target: no WAR), and is early: RealmSim retakes the fort no sooner. will_fall
## follows it; garrison_rate stays the current split's.
func _fall_planned() -> void:
	t.suite("wave-train-fall-planned")
	var s := GameState.new(TestUtil.configs())
	s.cmd_new_game(1)
	s.debug_enabled = true
	s.cmd_debug_set_state({"valve": {"work": 0.0, "war": 0.45, "flood": 0.55}})
	for f in s.realm.forts:
		f["living"] = 0.0
		f["undead"] = 0.0
		f["dead"] = 0.0 if f["id"] == "ashgate" else float(f["cap"])
	s.realm.hold("ashgate", 0.0)
	s.realm.start_tithe()
	s.realm.tithe["next_s"] = 1e9
	s.tick(s.substep_s())
	s.realm.fort_by_id("ashgate")["undead"] = float(s._fort_wars()[0]) / _r
	s.tick(s.substep_s())
	t.ok(s.cmd_set_valve(0.0, 0.0, 1.0)["ok"], "(setup) WAR to 0")
	s.tick(s.substep_s())
	var f: Dictionary = s.realm.forts[0]
	var cur := s._fort_readout(f, float(s._fort_wars()[0]))
	var v := s.view_fort("ashgate")
	t.ok(s.valve != s.valve_target and float(v["garrison_rate"]) > 0.0 and float(cur["fall_s"]) < 0.0,
		"slewing (%s): the current split holds it (garrison_rate %.3f) and its clock says it doesn't fall" % [str(s.valve), float(v["garrison_rate"])])
	var t0 := s.t
	var at := INF
	for k in int(2000.0 / s.substep_s()):
		s.tick(s.substep_s())
		for e in s.drain_events():
			if e["type"] == "fort_retaken" and e["fort_id"] == "ashgate":
				at = float(e["t"]) - t0
		if at < INF:
			break
	t.ok(at < INF, "it falls: retaken %.0f s after the read" % at)
	t.ok(float(v["fall_s"]) >= 0.0 and float(v["fall_s"]) <= at and v["margin"] == "will_fall",
		"view_fort's fall_s %.0f s (the planned support's) is early, and it reads will_fall" % float(v["fall_s"]))


## A new game and a load empty the wave train's cache and turn the frame path off: after a probed state on
## the frame path, cmd_new_game and cmd_debug_load_fixture (from_dict, as cmd_load) leave nothing to serve,
## and the next read probes.
func _reset() -> void:
	t.suite("wave-train-reset")
	var s := _fixture("midgame_2flips")
	var cap := s.max_substeps_per_frame()
	for k in [0, 1]:
		s.tick(s.substep_s(), cap)
		s.view_fort("ashgate")
		t.ok(not s._train_cache.is_empty() and s._frame_path, "(setup) probed, on the frame path")
		if k == 0:
			s.cmd_new_game(2)
		else:
			t.ok(s.cmd_debug_load_fixture("midgame_2flips")["ok"], "(setup) a load")
		t.ok(s._train_cache.is_empty() and not s._frame_path, "%s: the train's cache is empty and the frame path off" % ["a new game", "a load"][k])
		if k == 0:
			s.realm.hold("ashgate", 0.0)  # a new game holds nothing: hold one to read
		s.view_fort("ashgate")
		t.ok(int(s._train_cache.get("computed", 0)) == 1, "%s: the next read probes" % ["a new game", "a load"][k])


# ------------------------------------------------------------------------- GameState around it ----
func _fixture(name: String) -> GameState:
	var s := GameState.new(TestUtil.configs())
	s.debug_enabled = true
	t.ok(s.cmd_debug_load_fixture(name)["ok"], "%s loads" % name)
	return s


## What is committed but not yet in the flows. (1) Relish's arrival: midgame_2flips a substep in, she is
## travelling to Greywall (she arrives a second later). Her tide there will pull WAR off Old Sluice, which
## the next waves then break (MECHANICS §3.5). The train reads her there already: Old Sluice reads thin, as
## it does once she has arrived. Read with her where she stands (travelling: no tide), the same train calls
## it safe. (2) The valve's slew: a substep after cmd_set_valve cuts the WAR share to 0.10, the valve is
## still slewing; the live train reads the WAR at its target (the verdicts view_projection with `settled`
## gives at the target, the same probe), not the split the valve has reached.
func _arrival() -> void:
	t.suite("wave-train-committed")
	var s := _fixture("midgame_2flips")
	s.tick(s.substep_s())
	t.ok(s.relish["state"] == "travelling" and s.relish["target"] == "greywall", "(setup) she is travelling to Greywall")
	var vf := s.view_fort("old-sluice")
	var wars := s._fort_wars()
	var here := {}
	for i in s.realm.forts.size():
		var f: Dictionary = s.realm.forts[i]
		if RealmSim.is_held(f):
			here[f["id"]] = [float(wars[i]), false, s._raise_rate, false, 0.0]
	var tr_here := s.realm.train_probe(here, s.digest_q())
	var i_os := 1
	var ro_here := s.realm.readout_of(s.realm.forts[i_os], float(wars[i_os]), false, s._raise_rate, false, 0.0, s.digest_q(), tr_here["forts"]["old-sluice"])
	t.ok(vf["margin"] == "thin" and ro_here["margin"] == "safe",
		"travelling: Old Sluice reads %s (%s) with her at Greywall, %s with her where she stands" % [vf["margin"], vf["margin_cause"], ro_here["margin"]])
	for k in 20:
		if s.relish["state"] == "at_fort":
			break
		s.tick(s.substep_s())
	t.ok(s.relish["state"] == "at_fort" and s.view_fort("old-sluice")["margin"] == "thin", "arrived at Greywall: Old Sluice reads %s" % s.view_fort("old-sluice")["margin"])
	var v := _fixture("midgame_2flips")
	v.tick(v.substep_s())
	t.ok(v.cmd_set_valve(0.75, 0.10, 0.15)["ok"], "(setup) the WAR share to 0.10")
	v.tick(v.substep_s())
	t.ok(v.valve != v.valve_target, "(setup) a substep in, the valve is still slewing: %s" % str(v.valve))
	var live := v._train_live()
	var n := int(v._train_cache.get("computed", 0))
	var ts := v.town_sim
	var mint_tr := v._mint(ts.pit_weight(), ts.trough_feed())
	var st := TownSim.workforce_steady(mint_tr * 0.75 / v.worker_mass(), ts.lifetime_s(v.relish["state"] == "home"), ts._idle_rot,
		float(ts.staffing.get("slots", 0.0)), ts.idle_cap())
	var tw := mint_tr * 0.10 + float(st["muster"]) * v.worker_mass()  # the target's settled WAR (_settled_support)
	t.ok(absf(v._train_war() - tw) < 1e-12 and v._train_valve(v._train_war()) == live and int(v._train_cache.get("computed", 0)) == n,
		"the live train reads the target's WAR (%.3f, the split is at %.3f): the settled projection there is the same probe" % [v._train_war(), float(v._split["war"])])
	var mid := v.realm.train_probe(v._train_support(float(v._split["war"]), true), v.digest_q())
	t.ok(live["forts"] != mid["forts"], "and its verdicts differ from the mid-slew split's: %s against %s" % [str(live["forts"]), str(mid["forts"])])


## The settled support (E4 must-fix #1; GameState._train_war_at). midgame_2flips a substep after its load still
## burns the saved load at a feed of 1, so the split's WAR is above the 7.617 it settles at a minute on. The
## train reads that settled WAR from the first substep (before, it read the burst's 9.713 across the whole
## forecast). A minute on, with the load burned, the pits' trough feed is their feed and the train's WAR is the
## split's. view_projection with `settled` at the valve's target is view_fort's verdict, and reads the same WAR.
func _settled_support() -> void:
	var s := _fixture("midgame_2flips")
	s.tick(s.substep_s())
	var w0 := s._train_war()
	var burst := float(s._split["war"])
	var feed0 := float(s.town_sim.rates["feed"])
	t.ok(feed0 > s.town_sim.trough_feed() + 0.1 and burst > w0 + 1.0,
		"(setup) a substep after the load the pits burn it at a feed of %.2f (trough %.2f): the split's WAR %.3f, the train's %.3f" % [
		feed0, s.town_sim.trough_feed(), burst, w0])
	var proj: Dictionary = s.view_projection(s.valve_target, true)
	var vf := s.view_fort("ashgate")
	t.ok(str(proj["margins"]["ashgate"]["margin"]) == str(vf["margin"]) and absf(s._train_war_at(s.valve_target) - w0) == 0.0,
		"view_projection with settled at the target reads view_fort's verdict at Ashgate (%s) on the same WAR" % vf["margin"])
	s.tick(60.0)
	t.near(float(s._split["war"]), w0, 1e-6, "a minute on, the split settles at the WAR the train read at the first substep")
	t.near(s.town_sim.trough_feed(), float(s.town_sim.rates["feed"]), 1e-9, "with the load burned, the trough feed is the pits' feed")
	t.near(s._train_war(), float(s._split["war"]), 1e-9, "and the train's WAR is the split's")


## The cache: one probe serves view_realm, every view_fort and view_projection with `settled` at the current
## valve, and it is exactly what a fresh probe gives; an edit of the state that bumps nothing (a test, debug)
## still misses it.
func _cache() -> void:
	t.suite("wave-train-cache")
	var s := _fixture("midgame_2flips")
	s.tick(s.substep_s())
	var n0 := int(s._train_cache.get("computed", 0))
	var realm := s.view_realm()
	var forts := {}
	for f in s.realm.forts:
		forts[f["id"]] = s.view_fort(f["id"])
	var p := s.view_projection(s.view_hud()["valve"], true)
	t.ok(int(s._train_cache.get("computed", 0)) - n0 == 1, "one probe for view_realm, every view_fort and the settled projection (%d)" % (int(s._train_cache.get("computed", 0)) - n0))
	var fresh := s.realm.train_probe(s._train_support(s._train_war(), true), s.digest_q())
	t.ok(fresh == s._train_live(), "the cached verdicts are a fresh probe's, exactly")
	var agree := true
	for f in realm["forts"]:
		if f["held"]:
			agree = agree and f["margin"] == forts[f["id"]]["margin"] and p["margins"][f["id"]]["margin"] == f["margin"]
	t.ok(agree, "view_realm, view_fort and the settled projection agree")
	s.realm.fort_by_id("ashgate")["undead"] = 0.5  # no rev, no t: the state key still moves
	s.view_fort("ashgate")
	t.ok(int(s._train_cache.get("computed", 0)) - n0 == 2, "an edit that bumps neither rev nor t re-probes")


## The frame refresh (the frame path: tick() with a substep cap). After a substep frame a view serves the
## live slot as it stands (no probe on the frame where the scenes refetch); a later frame with no substep,
## at least hold.train_frame_phase into the interval, re-probes, and then a view reads the fresh verdict
## (exactly a fresh probe's). A command re-probes at the next read. With nothing reading, no frame probes.
## When every frame substeps, the frame after hold.train_starve_frames of them re-probes. Core steps run
## outside a substep (a catch-up: t moves, rev doesn't) re-probe at the next read.
func _frame() -> void:
	t.suite("wave-train-frame")
	var s := _fixture("midgame_2flips")
	var cap := s.max_substeps_per_frame()
	var step := s.substep_s()
	var phase := float(s._cfgs["realm"]["hold"]["train_frame_phase"])
	var starve := int(s._cfgs["realm"]["hold"]["train_starve_frames"])
	var count := func() -> int: return int(s._train_cache.get("computed", 0))
	s.tick(step, cap)
	s.view_fort("ashgate")  # the first read probes
	var n := int(count.call())
	var before: Dictionary = s._train_live()
	s._acc = 0.0
	s.tick(step, cap)  # a substep frame
	var served: Dictionary = s.view_fort("ashgate")
	t.ok(count.call() == n and s._train_live() == before, "after a substep frame the views serve the live slot: no probe (%d)" % (count.call() - n))
	s.tick(maxf(step * 1e-5, (phase * 0.5) * step - s._acc), cap)  # early in the interval
	t.ok(count.call() == n, "a frame with no substep early in the interval doesn't probe")
	s.tick(maxf(step * 1e-5, phase * step - s._acc + step * 1e-5), cap)  # late in it
	t.ok(count.call() == n + 1, "a frame with no substep late in the interval re-probes")
	var fresh := s.realm.train_probe(s._train_support(s._train_war(), true), s.digest_q())
	t.ok(s._train_live() == fresh and s.view_fort("ashgate")["margin"] == s.realm.readout_of(s.realm.forts[0], float(s._fort_wars()[0]),
		false, s._raise_rate, false, 0.0, s.digest_q(), fresh["forts"]["ashgate"])["margin"] and served.has("margin"),
		"then the views read the fresh verdict, exactly")
	s.tick(maxf(step * 1e-5, phase * step - s._acc + step * 1e-5), cap)
	t.ok(count.call() == n + 1, "the state hasn't moved since: the next late frame doesn't probe")
	t.ok(s.cmd_set_valve(0.3, 0.5, 0.2)["ok"], "(a command)")
	s.view_fort("ashgate")
	t.ok(count.call() == n + 2, "a command: the next read probes at once")
	var m := int(count.call())
	for k in starve:
		s._acc = 0.0
		s.tick(step, cap)
		s.view_fort("ashgate")
		if k < starve - 1 and count.call() != m:
			break
	t.ok(count.call() == m + 1, "every frame substepping: the %d-th re-probes (%d)" % [starve, count.call() - m])
	s.view_fort("ashgate")
	var c0 := int(count.call())
	for k in 3:
		s._core_step(10.0)  # a catch-up's core steps: t moves, rev and the substep count don't
	s.view_fort("ashgate")
	t.ok(count.call() == c0 + 1, "core steps outside a substep (a catch-up): the next read probes, though rev hasn't moved")


## The re-targeted warning (MECHANICS §3.4, T3.4b §4): a warning names Ashgate (contested, the most
## undead); Ashgate enters grace (a new hold); the warning is dropped at once and the next step's warning
## names Old Sluice. view_vei().tithe and view_fort's tithe follow, and a new tithe_warning names Old Sluice.
func _retarget() -> void:
	t.suite("wave-train-retarget")
	var s := GameState.new(TestUtil.configs())
	s.cmd_new_game(1)
	s.debug_enabled = true
	s.realm.hold("ashgate", 0.0)
	s.realm.hold("old-sluice", 0.0)
	s.realm.fort_by_id("ashgate")["undead"] = 40.0
	s.realm.fort_by_id("old-sluice")["undead"] = 20.0
	s.realm.start_tithe()
	var warn_s := float(s._cfgs["realm"]["tithe"]["warning_s"])
	s.realm.tithe["next_s"] = warn_s + 0.25
	s.drain_events()
	s.tick(s.substep_s())
	var ev1 := s.drain_events().filter(func(e): return e["type"] == "tithe_warning")
	t.ok(ev1.size() == 1 and ev1[0]["fort_id"] == "ashgate" and s.view_vei()["tithe"]["target"] == "ashgate"
		and s.view_fort("ashgate")["tithe"]["targeted"], "the warning names Ashgate: %s" % str(ev1))
	s.realm.hold("ashgate", 300.0)  # Ashgate enters grace
	t.ok(s.view_vei()["tithe"]["target"] == "" and not s.view_vei()["tithe"]["warning"] and not s.view_fort("ashgate")["tithe"]["targeted"],
		"in grace: the warning is dropped, at once")
	s.tick(s.substep_s())
	var ev2 := s.drain_events().filter(func(e): return e["type"] == "tithe_warning")
	var vt: Dictionary = s.view_vei()["tithe"]
	var os_t: Dictionary = s.view_fort("old-sluice")["tithe"]
	t.ok(ev2.size() == 1 and ev2[0]["fort_id"] == "old-sluice" and int(ev2[0]["wave_id"]) == int(ev1[0]["wave_id"]) + 1,
		"the next step warns again, naming Old Sluice (wave %s): %s" % [str(ev2[0]["wave_id"]) if ev2.size() > 0 else "-", str(ev2)])
	t.ok(vt["target"] == "old-sluice" and vt["warning"] and os_t["targeted"] and float(os_t["eta_s"]) > 0.0
		and not s.view_fort("ashgate")["tithe"]["targeted"], "view_vei and view_fort show Old Sluice targeted (eta %.1f s), Ashgate not" % float(os_t["eta_s"]))
