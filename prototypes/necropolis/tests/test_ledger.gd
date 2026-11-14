extends RefCounted
## The mass ledger (STATE-API §4.7, MECHANICS §2.1, §10): its keys, where each flow books, the
## invariant Σheld + Σsinks == Σsources at every substep and at any substep length, the totals across
## a save and load, saves written before the ledger, and a shortened soak (10 sim-min).
## tests/slow/soak.gd runs the full sim-hour through soak(). The influence field is slowed in a copy
## of the configs (never realm.json): nothing here reads it. Headless, no autoloads.

const Ledger := preload("res://scripts/sim/ledger.gd")
const TOL := 1e-6  # MECHANICS §2.1: the invariant, relative
const TIGHT := 1e-9  # what the unit cases hold to (a leak shows long before TOL)
const SOAK_S := 600.0  # the default suite's soak; the full hour is tests/slow/soak.gd
const SOAK_FIELD_HZ := 0.01  # the soak's field.tick_hz, lowered in memory

var t := TestUtil.new()
var _base := {}


## A copy of the configs with the field slowed and shrunk (cheap substeps); `substep` > 0 coarsens
## economy.json sim.substep_s in the copy.
func _cfgs(substep := 0.0) -> Dictionary:
	if _base.is_empty():
		_base = TestUtil.configs()
		var fld: Dictionary = _base["realm"]["field"]
		fld["tick_hz"] = 0.01
		fld["w"] = 8
		fld["h"] = 6
	var c: Dictionary = _base.duplicate(true)
	if substep > 0.0:
		c["economy"]["sim"]["substep_s"] = substep
	return c


func _mk(seed_val := 1, substep := 0.0) -> GameState:
	var s := GameState.new(_cfgs(substep))
	s.debug_enabled = true
	s.cmd_new_game(seed_val)
	return s


## A relative error for messages (GDScript's % has no %e).
static func _e(x: float) -> String:
	return String.num_scientific(x) if x != 0.0 else "0"


func _err(s: GameState) -> float:
	return Ledger.error(s.ledger())


func _src(s: GameState, k: String) -> float:
	return float(s.ledger()["sources"][k])


func _snk(s: GameState, k: String) -> float:
	return float(s.ledger()["sinks"][k])


func _sum_forts(s: GameState) -> Dictionary:
	var d := {"living": 0.0, "undead": 0.0, "dead": 0.0}
	for f in s.realm.forts:
		for k in d:
			d[k] += float(f[k])
	return d


func run() -> int:
	t.suite("ledger")
	_keys()
	_flows()
	_overflow()
	_debug()
	_runs()
	_any_dt()
	_save_load()
	_pre_ledger()
	soak(SOAK_S, 11)
	return t.failures


# ------------------------------------------------------------------- keys ----
func _keys() -> void:
	var s := _mk()
	var l := s.ledger()
	t.ok(l["sources"].keys() == ["mint", "debug", "opening"], "sources: mint, debug, opening")
	t.ok(l["sinks"].keys() == ["cleared", "rot_loss", "burned", "milled", "vei_fight", "dungeon", "pool_overflow",
		"rot_overflow", "haul_overflow", "store_overflow"], "sinks: the frozen seven, then rot_overflow, haul_overflow, store_overflow")
	t.ok(l["held"].keys() == ["fort_living", "fort_undead", "corpses", "backlog", "vei_dead", "living_pool", "bodies",
		"workers", "convoys", "work_pending"], "held: the frozen nine, then work_pending")
	var forts := _sum_forts(s)
	var h: Dictionary = l["held"]
	t.ok(h["fort_living"] == forts["living"] and h["fort_undead"] == forts["undead"] and h["corpses"] == forts["dead"],
		"held: the forts' living, undead and dead")
	t.ok(h["bodies"] == s.town_sim.bodies and h["workers"] == s.town_sim.workers * float(_base["economy"]["worker"]["mass"])
		and h["work_pending"] == 0.0, "held: bodies, workers in mass (× worker.mass) and the WORK in flight")
	t.ok(l["sources"]["opening"] == Ledger.total(h) and l["sources"]["opening"] > 0.0, "a new game: opening = Σheld (%.1f)" % l["sources"]["opening"])
	var zero := true
	for k in l["sinks"]:
		zero = zero and l["sinks"][k] == 0.0
	t.ok(zero and l["sources"]["mint"] == 0.0 and l["sources"]["debug"] == 0.0 and _err(s) == 0.0, "and every flow 0: balanced")
	var v := s.ledger()
	v["sources"]["mint"] = 99.0
	v["held"]["bodies"] = 99.0
	t.ok(_src(s, "mint") == 0.0 and s.ledger()["held"]["bodies"] == s.town_sim.bodies, "ledger() is a copy")


# ------------------------------------------------- where each flow books ----
func _flows() -> void:
	var s := _mk()
	var dt := s.substep_s()
	var c0: float = s.realm.cleared_total
	s.tick(dt)
	t.ok(_src(s, "mint") == s._split["mint"] * dt, "mint: the substep's production × dt")
	t.ok(s.ledger()["held"]["work_pending"] == 0.0 and s.work_pending == 0.0,
		"held.work_pending: 0 at the step boundary (TownSim takes each step's WORK in that step)")
	var r: Dictionary = s.town_sim.rates
	t.near(_snk(s, "burned"), float(r["bodies"]["pit"]) * dt, 1e-12, "burned: the pits' burn")
	var wk: Dictionary = _base["economy"]["worker"]
	t.near(_snk(s, "rot_loss"), float(r["workers"]["rot"]) * dt * float(wk["mass"]) * (1.0 - float(wk["body_return"])), 1e-12,
		"rot_loss: rot × worker.mass × (1 − body_return)")
	t.ok(_snk(s, "cleared") == s.realm.cleared_total - c0, "cleared: k_clear's mass")
	t.ok(_err(s) < TIGHT, "balanced after one substep")
	# two minutes with a mill: every town flow books and the count stays exact substep by substep
	s.cmd_debug_grant({"gold": 500.0, "bone": 200.0})
	s.cmd_build("bone_mill", "lot-05")
	s.cmd_set_job_priority(["build", "mill", "pit", "haul", "stall", "forge", "tend"])
	var worst := 0.0
	var before := s.ledger()
	c0 = s.realm.cleared_total
	for i in 240:
		s.tick(dt)
		worst = maxf(worst, _err(s))
	var after := s.ledger()
	t.ok(worst < TIGHT, "every substep balances (worst %s)" % _e(worst))
	t.ok(after["sinks"]["milled"] > 0.0 and after["sinks"]["burned"] > before["sinks"]["burned"] and after["sinks"]["rot_loss"] > before["sinks"]["rot_loss"],
		"milled, burned and rot_loss grow: %s" % [after["sinks"]])
	t.near(after["sinks"]["cleared"] - before["sinks"]["cleared"], s.realm.cleared_total - c0, 1e-9, "cleared follows RealmSim's k_clear total")
	t.ok(after["sources"]["debug"] == 0.0, "gold and bone are not mass: a grant of them books nothing")
	t.ok(after["sinks"]["pool_overflow"] == 0.0 and after["sinks"]["store_overflow"] == 0.0, "pool_overflow and store_overflow stay 0")


## Rot return and a landing convoy lost to a full body store.
func _overflow() -> void:
	var s := _mk()
	var dt := s.substep_s()
	s.cmd_debug_set_state({"forts": {"ashgate": {"dead": 60.0}}})
	var out := false
	for i in 200:
		s.tick(dt)
		var cv: Array = s.town_sim.haul["convoys"]
		if not cv.is_empty() and cv[0]["phase"] == "back" and float(cv[0]["load"]) > 0.0:
			out = true
			break
	t.ok(out and s.ledger()["held"]["convoys"] > 0.0, "a convoy on its way home is held (%.1f)" % s.ledger()["held"]["convoys"])
	t.ok(_err(s) < TIGHT, "balanced with a load on the road")
	var cap := s.town_sim.body_cap()
	s.cmd_debug_grant({"bodies": cap})  # fill the store (clamped at the cap)
	t.ok(s.town_sim.bodies == cap, "the store is full")
	var h0 := _snk(s, "haul_overflow")
	var r0 := _snk(s, "rot_overflow")
	for i in 40:
		s.cmd_debug_grant({"bodies": cap})
		s.tick(dt)
	t.ok(_snk(s, "haul_overflow") > h0, "haul_overflow: the load that found the store full (%.2f)" % (_snk(s, "haul_overflow") - h0))
	t.ok(_snk(s, "rot_overflow") > r0, "rot_overflow: rot return over the cap (%.3f)" % (_snk(s, "rot_overflow") - r0))
	t.ok(_err(s) < TIGHT, "balanced with both overflows")


# ------------------------------------------------------------------ debug ----
func _debug() -> void:
	var s := _mk()
	var d0 := _src(s, "debug")
	s.cmd_debug_grant({"bodies": 10.0})
	t.ok(_src(s, "debug") - d0 == 10.0, "a bodies grant books its mass")
	s.cmd_debug_grant({"bodies": -25.0})
	t.ok(_src(s, "debug") == -15.0 and s.town_sim.bodies == 25.0, "a removal books negative: debug −15, bodies 25")
	s.cmd_debug_grant({"bodies": -1000.0})
	t.ok(_src(s, "debug") == -40.0 and s.town_sim.bodies == 0.0, "only what was applied (clamped at 0)")
	s.cmd_debug_grant({"workers": 2.5})
	t.ok(_src(s, "debug") == -40.0 + 2.5 * s.worker_mass(), "workers book × worker.mass (2.5 workers)")
	s.cmd_debug_grant({"backlog": 300.0})
	var d1 := -40.0 + 2.5 * s.worker_mass() + 300.0
	t.ok(_src(s, "debug") == d1, "backlog books into Vei's queue")
	s.cmd_debug_grant({"gold": 50.0, "bone": 5.0, "living": 3.0, "relics": 1, "essence": 2})
	t.ok(_src(s, "debug") == d1, "gold, bone, Covington's living, relics and essence are not mass")
	var f: Dictionary = s.realm.fort_by_id("greywall")
	var was := float(f["living"]) + float(f["undead"]) + float(f["dead"])
	s.cmd_debug_set_state({"forts": {"greywall": {"living": 10.0, "dead": 500.0}}})
	var now := float(f["living"]) + float(f["undead"]) + float(f["dead"])
	t.ok(f["dead"] == f["cap"] and absf(_src(s, "debug") - d1 - (now - was)) < 1e-9, "set_state forts books the change (dead clamped to the cap)")
	t.ok(_err(s) < TIGHT, "balanced after every debug change")
	s.cmd_debug_skip_time(30.0)
	t.ok(_err(s) < TIGHT, "and after skipping time")


# ------------------------------------------------------ runs and the fight ----
func _runs() -> void:
	var s := _mk()
	s.cmd_debug_set_state({"forts": {"old-sluice": {"undead": 20.0, "dead": 30.0}}})
	s.cmd_debug_set_state({"relish_at": "old-sluice"})
	var b := s.cmd_begin_dungeon("old-sluice")
	var sd: Dictionary = b["seed"]
	s.tick(5.0)  # the realm keeps running during the run
	var r := Results.from_v1("raid", {"fort_id": "old-sluice"}, sd)
	r["raised"] = [{"score": 60, "count": 3, "mass": 12.0}]
	r["chaff_mass"] = 4.0
	r["garrison_mass"] = float(sd["garrison_in_mass"]) * 0.5
	var held0 := Ledger.total(s.ledger()["held"])
	t.ok(s.apply_result("raid", r)["ok"], "a raid result applies")
	var lost := _snk(s, "dungeon")
	t.ok(lost > 0.0, "dungeon: half the garrison and what was raised but not brought back (%.2f)" % lost)
	t.near(held0 - Ledger.total(s.ledger()["held"]), lost, 1e-9, "the board lost exactly the dungeon sink")
	t.ok(_err(s) < TIGHT, "balanced after the writeback")
	# a lost Vei fight: (1 − loss_backlog_keep) of the backlog
	s.cmd_debug_grant({"backlog": 1000.0})
	s.cmd_debug_set_state({"relish_at": "vei"})
	var bb := s.cmd_begin_boss()
	var q0: float = s.realm.vei["undead_queue"]
	var res := {"v": 2, "run_id": bb["run_id"], "seed_rev": bb["seed_rev"], "won": false, "fronts_cleared": [],
		"relish_deaths": 0, "backups_spent": {"phylactery": 0, "clones": 0}, "party_lost": [], "backlog_spent": 0.0}
	t.ok(s.apply_result("boss", res)["ok"], "a lost boss result applies")
	var keep := float(_base["vei"]["loss_backlog_keep"])
	t.near(_snk(s, "vei_fight"), q0 * (1.0 - keep), 1e-9, "vei_fight: (1 − loss_backlog_keep) of the backlog")
	t.ok(_err(s) < TIGHT, "balanced after the fight")


# ------------------------------------------------------------ any substep ----
## Catch-up (IDLE §4) steps at long dt: the count must not depend on the substep length, and since
## E2b T3.0 (the exact drain, the fort's path, the netted body store) nothing goes negative or
## non-finite at any of them either, 30 s and 120 s included.
func _any_dt() -> void:
	for dt in [0.1, 2.0, 8.0, 30.0, 120.0]:
		var s := GameState.new(_cfgs(dt))
		s.debug_enabled = true
		s.cmd_debug_load_fixture("midgame_2flips")
		var worst := 0.0
		var neg: Array = []
		for i in 150:
			s.tick(dt)
			worst = maxf(worst, _err(s))
			_negatives(s, neg)
		t.ok(worst < TIGHT, "substep %.1f s: balanced at every substep for %d sim-s (worst %s)" % [dt, int(150 * dt), _e(worst)])
		t.ok(neg.is_empty(), "substep %.1f s: no negative or non-finite pool%s" % [dt, "" if neg.is_empty() else ": " + str(neg.slice(0, 8))])


## _soak_check's no-negatives and finiteness checks, on their own.
func _negatives(s: GameState, bad: Array) -> void:
	if bad.size() > 20:
		return
	var at := "t %.1f" % s.t
	var l := s.ledger()
	for sec in ["sources", "sinks", "held"]:
		for k in l[sec]:
			var v := float(l[sec][k])
			if not is_finite(v):
				bad.append("%s: %s.%s not finite" % [at, sec, k])
			elif v < 0.0 and not (sec == "sources" and k == "debug"):
				bad.append("%s: %s.%s = %f < 0" % [at, sec, k, v])
	for f in s.realm.forts:
		for k in ["living", "undead", "dead"]:
			if not is_finite(float(f[k])) or float(f[k]) < 0.0:
				bad.append("%s: %s.%s = %f" % [at, f["id"], k, float(f[k])])
	var ts := s.town_sim
	var stocks := {"gold": ts.gold, "bone": ts.bone, "living": ts.living, "morale": ts.morale, "relics": float(s.relics),
		"essence": float(s.essence)}
	for k in stocks:
		if not is_finite(stocks[k]) or stocks[k] < 0.0:
			bad.append("%s: %s = %f" % [at, k, stocks[k]])


# --------------------------------------------------------------- persistence ----
func _save_load() -> void:
	var s := _mk(5)
	s.cmd_debug_grant({"bodies": 30.0, "backlog": 50.0})
	s.cmd_debug_skip_time(200.0)
	var d: Dictionary = JSON.parse_string(JSON.stringify(s.to_dict()))
	t.ok((d["ledger"]["sources"] as Dictionary).has_all(Ledger.SOURCES) and (d["ledger"]["sinks"] as Dictionary).has_all(Ledger.SINKS),
		"the save's ledger block has every source and sink")
	var n := GameState.new(_cfgs())
	n.debug_enabled = true
	t.ok(n.from_dict(d)["ok"], "it loads")
	var a := s.ledger()
	var b := n.ledger()
	var same := true
	for sec in ["sources", "sinks", "held"]:
		for k in a[sec]:
			same = same and absf(float(a[sec][k]) - float(b[sec][k])) <= 1e-12 * maxf(1.0, absf(float(a[sec][k])))
	t.ok(same, "every total survives the load (to the 15 digits a save keeps)")
	t.ok(_err(n) < TIGHT, "the loaded game balances (%s)" % _e(_err(n)))
	for i in 100:
		s.tick(s.substep_s())
		n.tick(n.substep_s())
	t.near(_src(n, "mint"), _src(s, "mint"), 1e-9 * _src(s, "mint"), "and both count on alike")
	t.ok(_err(n) < TIGHT, "still balanced")
	# a T2.5 save missing a sink reads it as 0
	var e: Dictionary = d.duplicate(true)
	(e["ledger"]["sinks"] as Dictionary).erase("store_overflow")
	e["ledger"]["sinks"]["rot_loss"] = 7.0
	var m := GameState.new(_cfgs())
	t.ok(m.from_dict(e)["ok"] and _snk(m, "store_overflow") == 0.0 and _snk(m, "rot_loss") == 7.0,
		"a ledger block with `opening` is read back key by key; a missing key reads 0")


## The fixtures carry their ledger (make_fixtures.gd writes what to_dict gives): it loads as saved and
## balances. Saves written before the ledger (E1's v1 fixtures; an E2a save, here a fixture with its
## ledger cut back to the E2a stub) hold only sinks.dungeon: it is kept, and `opening` is what the
## save holds at load, so the count balances from there.
func _pre_ledger() -> void:
	for name in GameState.FIXTURES:
		var raw := TestUtil.load_json("res://tests/fixtures/%s.json" % name)
		var s := GameState.new(_cfgs())
		s.debug_enabled = true
		t.ok(s.from_dict(raw)["ok"], "%s loads" % name)
		var l := s.ledger()
		t.ok(l["sources"] == raw["ledger"]["sources"] and l["sinks"] == raw["ledger"]["sinks"] and _err(s) < TIGHT,
			"%s: its ledger is read back and balances (%s)" % [name, _e(_err(s))])
		var stub: Dictionary = raw.duplicate(true)
		var dungeon := float(raw["ledger"]["sinks"]["dungeon"])
		stub["ledger"] = {"sources": {"mint": 0.0, "debug": 0.0}, "sinks": {"cleared": 0.0, "rot_loss": 0.0, "burned": 0.0,
			"milled": 0.0, "vei_fight": 0.0, "dungeon": dungeon, "pool_overflow": 0.0}}
		_pre_ledger_one(name + " as an E2a save", stub, dungeon)
	for name in ["v1_day1", "v1_midgame_2flips"]:
		var raw := TestUtil.load_json("res://tests/fixtures/%s.json" % name)
		_pre_ledger_one(name, raw, float(raw["ledger"]["sinks"]["dungeon"]))


func _pre_ledger_one(name: String, d: Dictionary, dungeon: float) -> void:
	var s := GameState.new(_cfgs())
	s.debug_enabled = true
	t.ok(s.from_dict(d)["ok"], "%s loads" % name)
	var l := s.ledger()
	var rest := true
	for k in l["sinks"]:
		rest = rest and (k == "dungeon" or l["sinks"][k] == 0.0)
	t.ok(l["sinks"]["dungeon"] == dungeon and rest and l["sources"]["mint"] == 0.0 and l["sources"]["debug"] == 0.0,
		"%s: its dungeon sink (%.2f) is kept, the other flows start at 0" % [name, dungeon])
	t.near(l["sources"]["opening"], Ledger.total(l["held"]) + dungeon, 1e-9, "%s: opening = Σheld + dungeon" % name)
	s.cmd_debug_skip_time(60.0)
	t.ok(_err(s) < TIGHT, "%s: balanced a minute on (%s)" % [name, _e(_err(s))])


# -------------------------------------------------------------------- soak ----
## The ledger soak (MECHANICS §2.1, §10): `sim_s` sim seconds from a new game with the shipped
## configs, the field's tick_hz lowered in memory. About every 5 sim-s one random input: the valve
## (extremes too, which muster and starve), Relish's moves (tide and the redirect where she stands),
## raids applied through apply_result (flips, kills, raises, chaff, garrison losses, deaths), a lost
## Vei fight, builds and upgrades, haul targets and the job ladder, debug grants (filling the body
## store, removals) and set_state's forts. Ticks are 1 to 8 substeps. After every tick: the invariant
## within TOL, no NaN, no negative pool or stock, every capped pool within its cap.
func soak(sim_s: float, seed_val: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	var cfgs := TestUtil.configs()
	cfgs["realm"]["field"]["tick_hz"] = SOAK_FIELD_HZ
	var s := GameState.new(cfgs)
	s.debug_enabled = true
	var wall0 := Time.get_ticks_msec()
	s.cmd_new_game(seed_val)
	var dt := s.substep_s()
	var nodes: Array = ["covington", "vei"]
	for f in s.realm.forts:
		nodes.append(f["id"])
	var bids: Array = cfgs["buildings"].keys()
	var lots: Array = []
	for l in cfgs["town"]["lots"]:
		lots.append(str(l["id"]))
	var idle_cap := float(cfgs["economy"]["worker"]["idle_cap"])
	var pool_cap := float(cfgs["realm"]["vei_pool_cap"])
	var st := {"substeps": 0, "checks": 0, "worst": 0.0, "raids": 0, "flips": 0, "deaths": 0, "boss_losses": 0,
		"waves": 0, "retaken": 0, "started": 0, "done": 0, "muster": 0.0, "moves": 0}
	var bad: Array = []
	var run_left := -1  # substeps until the open run's result comes back
	var want_boss := false
	# a mill early, so milling books too
	s.cmd_debug_grant({"gold": 300.0, "bone": 100.0})
	s.cmd_build("bone_mill", "lot-05")
	while s.t < sim_s:
		if run_left == 0:
			_soak_result(s, rng, st, bad)
			run_left = -1
		elif run_left > 0:
			run_left -= 1
		if s.run.is_empty() and want_boss and s.relish["state"] == "at_vei":
			if s.cmd_begin_boss()["ok"]:
				run_left = rng.randi_range(0, 10)
				want_boss = false
		if s.run.is_empty() and rng.randf() < 0.1:
			match rng.randi() % 9:
				0:  # the valve, extremes a third of the time
					var v := [rng.randf(), rng.randf(), rng.randf()]
					if rng.randf() < 0.33:
						v = [0.0, 0.0, 0.0]
						v[rng.randi() % 3] = 1.0
					s.cmd_set_valve(v[0], v[1], v[2])
				1, 2:  # Relish walks somewhere
					if s.cmd_move_relish(nodes[rng.randi() % nodes.size()])["ok"]:
						st["moves"] += 1
				3:  # a raid where she stands
					if s.relish["state"] == "at_fort" and s.cmd_begin_dungeon(s.relish["at"])["ok"]:
						run_left = rng.randi_range(0, 20)
				4:  # toward Vei, for a fight
					if s.cmd_move_relish("vei")["ok"]:
						want_boss = true
				5:  # builds (something the catalog offers, and a random try) and upgrades, kept affordable
					s.cmd_debug_grant({"gold": rng.randf_range(0.0, 400.0), "bone": rng.randf_range(0.0, 150.0), "relics": rng.randi_range(0, 2)})
					var offer: Array = s.view_catalog()["buildings"].filter(func(e): return e["can_build"])
					if not offer.is_empty():
						var e: Dictionary = offer[rng.randi() % offer.size()]
						s.cmd_build(e["building_id"], e["lots"][rng.randi() % e["lots"].size()])
					s.cmd_build(bids[rng.randi() % bids.size()], lots[rng.randi() % lots.size()])
					s.cmd_upgrade(lots[rng.randi() % lots.size()])
				6:  # debug grants, removals and a full body store
					var g := {}
					for k in ["bodies", "workers", "backlog", "living"]:
						if rng.randf() < 0.5:
							g[k] = rng.randf_range(-50.0, 50.0) * (0.1 if k == "workers" else 1.0)
					if rng.randf() < 0.3:
						g["bodies"] = 1000.0
					s.cmd_debug_grant(g)
				7:  # set_state's forts
					var f: Dictionary = s.realm.forts[rng.randi() % s.realm.forts.size()]
					var cap := float(f["cap"])
					s.cmd_debug_set_state({"forts": {f["id"]: {"living": rng.randf_range(0.0, cap), "dead": rng.randf_range(0.0, cap * 0.3)}}})
				8:  # haul target and the ladder
					var ids: Array = ["auto"] + nodes.slice(2)
					s.cmd_set_haul_target(ids[rng.randi() % ids.size()])
					var order := GameState.JOB_IDS.duplicate()
					order.shuffle()
					s.cmd_set_job_priority(order)
		var k := 1 if rng.randf() < 0.8 else rng.randi_range(2, 8)
		st["substeps"] += s.tick(dt * k)
		st["muster"] = maxf(st["muster"], float(s._split["muster"]))
		for ev in s.drain_events():
			match ev["type"]:
				"fort_flipped": st["flips"] += 1
				"tithe_wave": st["waves"] += 1
				"fort_retaken": st["retaken"] += 1
				"building_started": st["started"] += 1
				"building_done": st["done"] += 1
				"relish_died": st["deaths"] += 1
		_soak_check(s, st, bad, idle_cap, pool_cap)
	# Two forced phases, each asserted on its own delta (the random phase may or may not have reached
	# these sinks, and the cumulative totals would hide that):
	#  1. march-back: Vei's pool is full and a free fort holds living far above its cap, so the living
	#     marching back land above her pool's cap and pool_overflow books (MECHANICS §3.4). Both
	#     edits are booked as debug sources, as the debug commands do (set_state clamps living to
	#     the cap, so it cannot make this state).
	#  2. full store: every building unstaffed (nothing burns or mills bodies) and the body store
	#     full, so rot's return overflows and rot_overflow books.
	# Covered elsewhere (deterministic tests above): haul_overflow, in _overflow(), the convoy that
	# lands on a full store. store_overflow is not live: nothing books it (GameState.step books the
	# town's five sinks and the realm's cleared and pool_overflow only), so it is left out of the list.
	if not s.run.is_empty():
		s.cmd_abort_dungeon()
	var fort_id := ""
	for f in s.realm.forts:
		if not RealmSim.is_held(f):
			fort_id = str(f["id"])
			break
	if fort_id == "":
		bad.append("no free fort for the march-back phase")
	else:
		var f: Dictionary = s.realm.fort_by_id(fort_id)
		var pool_add := pool_cap - float(s.realm.vei["living_pool"])
		var fort_add := float(f["cap"]) * 10.0
		s.realm.vei["living_pool"] = pool_cap
		f["living"] = float(f["living"]) + fort_add
		s._ledger.source("debug", pool_add + fort_add)
		var before: Dictionary = s.ledger()["sinks"].duplicate()
		# the realm steps at SOAK_FIELD_HZ, so run past two of its periods: it steps at least once
		var t_end := s.t + 2.0 / SOAK_FIELD_HZ
		while s.t < t_end:
			st["substeps"] += s.tick(dt)
			s.drain_events()
			_soak_check(s, st, bad, idle_cap, pool_cap)
		st["phase_march"] = float(s.ledger()["sinks"]["pool_overflow"]) - float(before["pool_overflow"])
		t.ok(st["phase_march"] > 0.0, "soak march-back phase: pool_overflow booked %.2f" % st["phase_march"])
	for lot in s.town_sim.buildings:
		s.cmd_set_staff_cap(lot, 0)
	s.cmd_debug_grant({"bodies": 1000.0})
	var before2: Dictionary = s.ledger()["sinks"].duplicate()
	for i in 40:
		st["substeps"] += s.tick(dt)
		s.drain_events()
		_soak_check(s, st, bad, idle_cap, pool_cap)
	st["phase_rot"] = float(s.ledger()["sinks"]["rot_overflow"]) - float(before2["rot_overflow"])
	t.ok(st["phase_rot"] > 0.0, "soak full-store phase: rot_overflow booked %.3f" % st["phase_rot"])
	print("  [soak] forced phases: march-back pool_overflow +%.3f, full store rot_overflow +%.4f" % [
		float(st.get("phase_march", -1.0)), st["phase_rot"]])
	var wall := Time.get_ticks_msec() - wall0
	var l := s.ledger()
	print("  [soak] %d sim-s, %d substeps, %d checks, worst relative error %s, wall %d ms" % [
		int(sim_s), st["substeps"], st["checks"], _e(st["worst"]), wall])
	print("  [soak] raids %d, flips %d, tithe waves %d, retaken %d, deaths %d, Vei fights lost %d, builds %d started / %d done, Relish moves %d, muster peak %.2f mass/s" % [
		st["raids"], st["flips"], st["waves"], st["retaken"], st["deaths"], st["boss_losses"], st["started"], st["done"],
		st["moves"], st["muster"]])
	print("  [soak] sources %s" % [l["sources"]])
	print("  [soak] sinks %s" % [l["sinks"]])
	t.ok(bad.is_empty(), "soak %d sim-s: the invariant within %s after every tick (%d), no NaN, no negatives, every cap held%s" % [
		int(sim_s), _e(TOL), st["checks"], "" if bad.is_empty() else ": " + str(bad.slice(0, 8))])
	t.ok(Ledger.error(l) < TOL, "soak %d sim-s: balanced at the end (%s)" % [int(sim_s), _e(Ledger.error(l))])
	t.ok(st["flips"] > 0 and st["raids"] >= 3 and st["boss_losses"] > 0 and st["muster"] > 0.0 and st["done"] > 0,
		"soak exercised flips, raids, a lost fight, muster and builds")
	var used := true
	for k in ["cleared", "rot_loss", "burned", "milled", "vei_fight", "dungeon", "pool_overflow", "rot_overflow"]:
		used = used and float(l["sinks"][k]) > 0.0
	t.ok(used and l["sources"]["debug"] != 0.0, "every sink the soak drives booked mass, and so did debug")
	if sim_s >= 3600.0:
		t.ok(st["waves"] > 0, "a full hour sees a tithe wave")


## A random result for the open run: a raid (beaten, retreated or died; kills, raises past what the
## fort holds, chaff, garrison losses and gains) or a lost Vei fight.
func _soak_result(s: GameState, rng: RandomNumberGenerator, st: Dictionary, bad: Array) -> void:
	var run: Dictionary = s.run
	var sd: Dictionary = run["seed"]
	var res := {}
	if run["kind"] == "raid":
		var f: Dictionary = s.realm.fort_by_id(run["fort_id"])
		var exit := rng.randi() % 5
		var raised := rng.randf_range(0.0, float(f["dead"]) + 20.0)
		res = {"v": 2, "run_id": run["run_id"], "seed_rev": run["seed_rev"], "fort_id": run["fort_id"],
			"warden_beaten": exit <= 1, "retreated": exit >= 2 and exit <= 3, "relish_died": exit == 4,
			"revived_in_place": 0, "killed_living_mass": rng.randf_range(0.0, float(f["living"]) * 0.6),
			"raised": [{"score": rng.randi_range(0, 100), "count": rng.randi_range(0, 6), "mass": raised}],
			"chaff_mass": rng.randf_range(0.0, raised * 0.5),
			"garrison_mass": float(sd["garrison_in_mass"]) * rng.randf_range(0.0, 1.3), "party_lost": [],
			"loot": {"relics": rng.randi_range(0, 1), "blueprints": [], "husks": [], "remnants": [], "essence": rng.randi_range(0, 8)}}
		st["raids"] += 1
	else:
		res = {"v": 2, "run_id": run["run_id"], "seed_rev": run["seed_rev"], "won": false, "fronts_cleared": [],
			"relish_deaths": 0, "backups_spent": {"phylactery": 0, "clones": 0}, "party_lost": [], "backlog_spent": 0.0}
		st["boss_losses"] += 1
	var r := s.apply_result(run["kind"], res)
	if not r["ok"]:
		bad.append("apply_result %s refused: %s %s" % [run["kind"], r["reason"], str(r["errors"])])
		s.cmd_abort_dungeon()


func _soak_check(s: GameState, st: Dictionary, bad: Array, idle_cap: float, pool_cap: float) -> void:
	if bad.size() > 20:
		return
	st["checks"] += 1
	var at := "t %.1f" % s.t
	var l := s.ledger()
	var err := Ledger.error(l)
	if not is_finite(err) or err > TOL:
		bad.append("%s: ledger off by %s" % [at, _e(err)])
	st["worst"] = maxf(st["worst"], err if is_finite(err) else INF)
	for sec in ["sources", "sinks", "held"]:
		for k in l[sec]:
			var v := float(l[sec][k])
			if not is_finite(v):
				bad.append("%s: %s.%s not finite" % [at, sec, k])
			elif v < 0.0 and not (sec == "sources" and k == "debug"):
				bad.append("%s: %s.%s = %f < 0" % [at, sec, k, v])
	for f in s.realm.forts:
		for k in ["living", "undead", "dead"]:
			if not is_finite(float(f[k])) or float(f[k]) < 0.0:
				bad.append("%s: %s.%s = %f" % [at, f["id"], k, float(f[k])])
	var ts := s.town_sim
	var stocks := {"gold": ts.gold, "bone": ts.bone, "living": ts.living, "morale": ts.morale, "relics": float(s.relics),
		"essence": float(s.essence)}
	for k in stocks:
		if not is_finite(stocks[k]) or stocks[k] < 0.0:
			bad.append("%s: %s = %f" % [at, k, stocks[k]])
	var caps := {
		"bodies": [ts.bodies, ts.body_cap()], "town living": [ts.living, ts.living_cap()],
		"Vei's pool": [float(s.realm.vei["living_pool"]), pool_cap],
		"workers": [ts.workers, float(ts.rates["workers"]["slots"]) + idle_cap],
		"relics": [float(s.relics), float(s._cap_of("relics"))], "essence": [float(s.essence), float(s._cap_of("essence"))],
		"big undead": [float(s.big_undead.size()), float(s._cap_of("big_undead"))],
	}
	for k in caps:
		if float(caps[k][0]) > float(caps[k][1]) + 1e-6:
			bad.append("%s: %s %f over its cap %f" % [at, k, caps[k][0], caps[k][1]])
	var rates: Dictionary = s.view_rates()["rates"]
	for id in rates:
		for k in ["in", "out", "net"]:
			if not is_finite(float(rates[id][k])):
				bad.append("%s: view_rates.%s.%s not finite" % [at, id, k])
