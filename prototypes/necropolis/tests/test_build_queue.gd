extends RefCounted
## The build queue (IDLE §5, STATE-API §4.3 and §5.9, MECHANICS §4.4; E2b-2 T3.2, api-request #3): what
## cmd_queue_build refuses and accepts, the statuses view_town().queue shows, the run's manager's four
## rules for gated entries (2026-11-14), the levels a queue builds, processing in the core step and the
## save. Headless, no autoloads. Economy's suite.

var t: TestUtil


func _mk(cfgs: Dictionary = {}) -> GameState:
	var s := GameState.new(TestUtil.configs() if cfgs.is_empty() else cfgs)
	s.cmd_new_game(1)
	s.debug_enabled = true
	return s


func _fixture(name: String) -> GameState:
	var s := GameState.new(TestUtil.configs())
	s.debug_enabled = true
	t.ok(s.cmd_debug_load_fixture(name)["ok"], "%s loads (setup)" % name)
	return s


## Sets TownSim's gold and bone outright (a test's funds; debug grants add).
func _funds(s: GameState, gold: float, bone: float) -> void:
	s.town_sim.gold = gold
	s.town_sim.bone = bone


func _q(s: GameState) -> Array:
	return s.view_town()["queue"]


## A buildings.json effect at `level`, as TownSim._eff_b reads it (written out here, not called): a number per
## level (× level), an Array the per-level table (its entry at level − 1, the last past its end).
static func _at_level(v: Variant, level: int) -> float:
	if v is Array:
		return float(v[mini(level, (v as Array).size()) - 1]) if not (v as Array).is_empty() else 0.0
	return float(v) * level


## The lowest Bone Mill level whose bone cap (bone.cap plus its bone_cap there) covers `bone`, from the configs;
## −1 when none does. The setups below give a state the mill a bone price needs (T7: the dead's buildings are
## bought with bone).
static func _mill_level(bone: float) -> int:
	var c := TestUtil.configs()
	var m: Dictionary = c["buildings"]["bone_mill"]
	for lv in range(1, int(m["max_level"]) + 1):
		if float(c["economy"]["bone"]["cap"]) + _at_level(m["effects"]["bone_cap"], lv) >= bone:
			return lv
	return -1


func _col(rows: Array, key: String) -> Array:
	return rows.map(func(r): return r[key])


func _started(evs: Array) -> Array:
	return evs.filter(func(e): return e["type"] == "queue_started")


func run() -> int:
	t = TestUtil.new()
	_refusals()
	_accepts()
	_view_shape()
	_rule1_never_stalls()
	_rule2_holds_nothing()
	_rule3_waited_on()
	_rule4_relics()
	_funds_hold()
	_levels()
	_view_matches_step()
	_tier_rise()
	_demolish_under()
	_walk_gates()
	_cap_dropped()
	_commands()
	_save()
	_afford_deadlock()
	_afford_times()
	_afford_never()
	_afford_at_cap()
	_afford_invariant()
	return t.failures


## cmd_queue_build refuses only what waiting can never make valid, in IDLE §5's terms.
func _refusals() -> void:
	t.suite("build_queue-refusals")
	var s := _mk()
	var r := s.cmd_queue_build("nope", "lot-05")
	t.ok(r == {"ok": false, "reason": "unknown_building", "index": -1, "cap_building": "", "store": "", "cap_level": -1, "affordable_in_s": -1.0},
		"unknown_building: %s" % str(r))
	t.ok(s.cmd_queue_build("house", "lot-99")["reason"] == "unknown_lot" and s.cmd_queue_build("", "lot-99")["reason"] == "unknown_lot",
		"unknown_lot, for a build and an upgrade")
	t.ok(s.cmd_queue_build("crypt", "lot-05")["reason"] == "unique", "unique: the Crypt stands")
	t.ok(s.cmd_queue_build("house", "lot-02")["reason"] == "lot_taken", "lot_taken: the raising pit stands there")
	t.ok(s.cmd_build("house", "lot-05")["ok"], "a house under construction (setup)")
	t.ok(s.cmd_queue_build("well", "lot-05")["reason"] == "lot_taken", "lot_taken: a building under construction there")
	t.ok(s.cmd_queue_build("market", "lot-06")["reason"] == "lot_too_small", "lot_too_small: a size-2 market on a size-1 lot")
	t.ok(s.cmd_queue_build("", "lot-06")["reason"] == "empty_lot", "empty_lot: an upgrade where nothing stands or is queued")
	# max_level: every upgrade of the pit up to its max_level is accepted, one more is refused (a state with a
	# top-level Bone Mill, so every level's bone is under the cap)
	var pit := _mk()
	var top := int(TestUtil.configs()["buildings"]["raising_pit"]["max_level"])
	pit.town_sim.place_building("lot-05", "bone_mill", int(TestUtil.configs()["buildings"]["bone_mill"]["max_level"]))
	t.ok(top - 1 < int(TestUtil.configs()["economy"]["queue"]["max_len"]), "(setup) the pit's %d upgrades fit in the queue" % (top - 1))
	for i in top - 1:
		t.ok(pit.cmd_queue_build("", "lot-02")["ok"], "the pit's upgrade %d of %d is accepted" % [i + 1, top - 1])
	t.ok(pit.cmd_queue_build("", "lot-02")["reason"] == "max_level", "max_level: one more upgrade of the pit would build level %d" % (top + 1))
	# the reliquary's 250 bone is over the base bone cap (no bone mill at a new game)
	var cap := s.cmd_queue_build("reliquary", "lot-23")
	t.ok(cap["reason"] == "cost_exceeds_cap" and cap["store"] == "bone" and cap["cap_building"] == "bone_mill" and cap["index"] == -1
		and cap["cap_level"] == 1, "cost_exceeds_cap: the reliquary's bone over the bone cap; a level-1 Bone Mill (not built yet) covers it: %s" % str(cap))
	# cap_level: the lowest level of the cap building whose cap covers the price. midgame_2flips has a level-1
	# mill; a Chapel of Vats' level 3 costs more bone than its cap, and the mill level that covers it is read
	# from the configs (_mill_level)
	var mg := _fixture("midgame_2flips")
	mg.town_sim.place_building("lot-13", "chapel_of_vats", 2)
	var c3_bone := float(BuildRules.construction_cost(mg, "chapel_of_vats", 3)["bone"])
	var c3 := mg.cmd_queue_build("", "lot-13")
	t.ok(c3_bone > mg.town_sim.bone_cap() and _mill_level(c3_bone) > 1 and c3["reason"] == "cost_exceeds_cap" and c3["store"] == "bone"
		and c3["cap_level"] == _mill_level(c3_bone),
		"the chapel's level 3 (%.0f bone) over a level-1 mill's %.0f: build the mill's level %d first (cap_level): %s" % [
		c3_bone, mg.town_sim.bone_cap(), _mill_level(c3_bone), str(c3)])
	var n := _q(s).size()
	var rv := s.rev
	t.ok(s.cmd_queue_build("nope", "lot-05")["ok"] == false and _q(s).size() == n and s.rev == rv, "a refusal changes nothing, rev stays")
	# queue_full: the queue's 8, two builds on one lot allowed (queued entries don't claim lots)
	var f := _mk()
	var oks := 0
	for i in int(TestUtil.configs()["economy"]["queue"]["max_len"]):
		oks += 1 if f.cmd_queue_build("house", "lot-05")["ok"] else 0
	t.ok(oks == 8 and _q(f).size() == 8 and f.view_town()["queue_max"] == 8, "the queue holds queue.max_len = 8, all on one lot (entries don't claim lots)")
	t.ok(f.cmd_queue_build("well", "lot-06")["reason"] == "queue_full", "queue_full")
	# a config where a gold cost, and a relic cost, is over its cap: the Market raises gold's, the Reliquary relics'
	var c := TestUtil.configs().duplicate(true)
	c["economy"]["gold"]["cap"] = 10.0
	c["buildings"]["market"]["effects"]["gold_cap"] = 1.0
	c["economy"]["relics"]["cap"] = 0
	var g := _mk(c)
	var rg := g.cmd_queue_build("house", "lot-05")
	t.ok(rg["reason"] == "cost_exceeds_cap" and rg["store"] == "gold" and rg["cap_building"] == "market" and rg["cap_level"] == -1,
		"cost_exceeds_cap on gold names the Market; no Market level covers 40 gold here (%.0f at its max level): cap_level -1: %s" % [
		10.0 + float(c["buildings"]["market"]["max_level"]), str(rg)])
	var rr := g.cmd_queue_build("", "lot-01")  # the crypt's level 2 costs a relic
	t.ok(rr["reason"] == "cost_exceeds_cap" and rr["store"] == "gold", "the gold is checked before the relics: %s" % str(rr))
	c["economy"]["gold"]["cap"] = 1e6
	var h := _mk(c)
	var rh := h.cmd_queue_build("", "lot-01")
	t.ok(rh["reason"] == "cost_exceeds_cap" and rh["store"] == "relics" and rh["cap_building"] == "reliquary" and rh["cap_level"] == 1,
		"cost_exceeds_cap on relics names the Reliquary, at level 1: %s" % str(rh))
	# unique, already queued (a config that makes the well unique)
	var u := TestUtil.configs().duplicate(true)
	u["buildings"]["well"]["unique"] = true
	var w := _mk(u)
	t.ok(w.cmd_queue_build("well", "lot-05")["ok"] and w.cmd_queue_build("well", "lot-06")["reason"] == "unique", "unique: one is already queued")


## Gates that time or play can clear are accepted: each shows skipped_gate with that reason, and holds the
## queue for nothing.
func _accepts() -> void:
	t.suite("build_queue-accepts")
	var s := _mk()
	_funds(s, 0.0, 0.0)
	var cases := [["house", "lot-09", "lot_locked"], ["watchtower", "lot-05", "needs_tier"], ["", "lot-01", "no_relics"]]
	for c in cases:
		var r := s.cmd_queue_build(c[0], c[1])
		t.ok(r["ok"] and r["reason"] == "" and r["cap_building"] == "" and r["store"] == "" and r["cap_level"] == -1, "%s on %s accepted: %s" % [c[0], c[1], str(r)])
	var rows := _q(s)
	for i in cases.size():
		t.ok(rows[i]["status"] == "skipped_gate" and rows[i]["reason"] == cases[i][2], "%s on %s shows skipped_gate (%s): %s %s" % [
			cases[i][0], cases[i][1], cases[i][2], rows[i]["status"], rows[i]["reason"]])
	# needs_blueprint: the village tier, no Embalmer blueprint (and the mill its bone needs under the cap)
	var v := _mk()
	v.town_tier = "village"
	v.town_sim.place_building("lot-06", "bone_mill", _mill_level(float(BuildRules.construction_cost(v, "embalmer", 1)["bone"])))
	t.ok(v.cmd_queue_build("embalmer", "lot-05")["ok"] and _q(v)[0]["reason"] == "needs_blueprint", "needs_blueprint: %s" % _q(v)[0]["reason"])
	# needs_building (no shipped building requires another: a config where the well needs a forge)
	var c2 := TestUtil.configs().duplicate(true)
	c2["buildings"]["well"]["requires"]["building"] = "forge"
	var nb := _mk(c2)
	t.ok(nb.cmd_queue_build("well", "lot-05")["ok"] and _q(nb)[0]["reason"] == "needs_building", "needs_building: %s" % _q(nb)[0]["reason"])
	# an upgrade of a lot under construction, and of an unpaid building (a well: its levels fit the base caps)
	var u := _mk()
	_funds(u, 1000.0, 100.0)
	u.town_sim.place_building("lot-05", "well", 1)
	t.ok(u.cmd_upgrade("lot-05")["ok"] and u.cmd_queue_build("", "lot-05")["ok"], "an upgrade of the upgrading well is accepted")
	var row: Dictionary = _q(u)[0]
	t.ok(row["status"] == "skipped_gate" and row["reason"] == "under_construction" and row["level"] == 3,
		"it waits on the construction under way (under_construction) and builds level 3: %s" % str(row))
	u.town_sim.buildings["lot-04"]["state"] = "unpaid"
	u.town_sim.restaff()
	t.ok(u.cmd_queue_build("", "lot-04")["ok"] and _q(u)[1]["reason"] == "unpaid", "an unpaid building's upgrade waits (unpaid): %s" % _q(u)[1]["reason"])


## view_town().queue and queue_max: always there (an empty queue is []), every entry's keys.
func _view_shape() -> void:
	t.suite("build_queue-view")
	var s := _mk()
	var v := s.view_town()
	t.ok(v.has("queue") and v["queue"] == [] and v["queue_max"] == 8, "a new game: queue [] and queue_max 8")
	t.ok(s.cmd_queue_build("house", "lot-05")["index"] == 0 and s.cmd_queue_build("", "lot-05")["index"] == 1, "indices 0, 1")
	var rows := _q(s)
	var house: Dictionary = TestUtil.configs()["buildings"]["house"]
	t.ok(rows[0] == {"building_id": "house", "lot_id": "lot-05", "upgrade": false, "level": 1,
		"cost": {"gold": 40.0, "bone": 10.0, "relics": 0}, "work": float(house["build_work"]), "status": "next", "reason": "", "waited_on": "",
		"affordable_in_s": 0.0},
		"a new build's row: %s" % str(rows[0]))
	t.ok(rows[1]["building_id"] == "house" and rows[1]["upgrade"] and rows[1]["level"] == 2 and rows[1]["work"] == 2.0 * float(house["build_work"])
		and rows[1]["cost"] == BuildRules.construction_cost(s, "house", 2),
		"an upgrade queued behind its lot's build: the house, level 2, its level_costs and twice the work: %s" % str(rows[1]))
	var snap := s.to_dict()
	s.view_town()
	t.ok(s.to_dict() == snap, "the view changes nothing")


## Rule 1: a gated entry never stalls the queue; when its gate clears it starts at its own position, never
## ahead of an earlier entry waiting for funds.
func _rule1_never_stalls() -> void:
	t.suite("build_queue-rule1")
	var s := _mk()
	_funds(s, 100.0, 30.0)
	s.cmd_queue_build("watchtower", "lot-05")  # needs_tier
	s.cmd_queue_build("house", "lot-06")
	s.drain_events()
	s.tick(s.substep_s())
	var st := _started(s.drain_events())
	t.ok(st.size() == 1 and st[0]["building_id"] == "house" and st[0]["lot_id"] == "lot-06", "the house behind a gated watchtower starts: %s" % str(st))
	t.ok(_q(s).size() == 1 and _q(s)[0]["status"] == "skipped_gate", "the watchtower stays, skipped")
	# its gate clears behind a head waiting for funds: it doesn't jump the head
	var j := _mk()
	j.town_sim.place_building("lot-05", "house", 2)
	var h3 := BuildRules.construction_cost(j, "house", 3)
	_funds(j, float(h3["gold"]) - 20.0, float(h3["bone"]))  # short of the head's gold, not of a house's 40
	j.cmd_queue_build("", "lot-05")  # the house's level 3: more gold than there is
	j.cmd_queue_build("house", "lot-09")  # lot_locked at hamlet; 40 gold, affordable
	t.ok(_col(_q(j), "status") == ["waiting_funds", "skipped_gate"], "head waits for funds, the house is gated: %s" % str(_col(_q(j), "status")))
	j.town_tier = "village"  # opens lot-09
	t.ok(_col(_q(j), "status") == ["waiting_funds", "queued"], "the gate clears: the house is queued behind the head, not next: %s" % str(_col(_q(j), "status")))
	j.drain_events()
	j.tick(j.substep_s())
	t.ok(_started(j.drain_events()).is_empty() and _q(j).size() == 2, "and nothing starts")
	t.ok(j.build_queue[1]["waited_on"] == "no_gold", "queued behind the waiting head, its waited_on is the head's no_gold, not its old lot_locked")
	j.cmd_debug_grant({"gold": 500.0, "bone": 200.0})
	j.drain_events()
	j.tick(j.substep_s())
	var both := _started(j.drain_events())
	t.ok(both.size() == 2 and both[1]["building_id"] == "house" and both[1]["waited_on"] == "no_gold",
		"funded, both start in order, and the house's queue_started says the funds held it: %s" % str(both))


## Rule 2: a gated entry reserves nothing and claims no lot. Another entry or cmd_build taking its lot turns it
## lot_taken; it stays for the player to see.
func _rule2_holds_nothing() -> void:
	t.suite("build_queue-rule2")
	var s := _mk()
	_funds(s, 40.0, 10.0)  # exactly a house
	s.cmd_queue_build("", "lot-01")  # the crypt's level 2: no relics
	s.cmd_queue_build("watchtower", "lot-05")  # needs_tier
	s.cmd_queue_build("house", "lot-05")  # the same lot, behind it
	s.drain_events()
	s.tick(s.substep_s())
	var st := _started(s.drain_events())
	t.ok(st.size() == 1 and st[0]["building_id"] == "house", "the house starts on lot-05 with every coin there is: nothing is reserved: %s" % str(st))
	var rows := _q(s)
	t.ok(rows.size() == 2 and rows[1]["building_id"] == "watchtower" and rows[1]["status"] == "skipped_gate" and rows[1]["reason"] == "lot_taken",
		"the watchtower stays, lot_taken: %s" % str(rows))
	# the player's own cmd_build takes a gated entry's lot
	var b := _mk()
	b.cmd_queue_build("watchtower", "lot-06")
	t.ok(b.cmd_build("well", "lot-06")["ok"], "cmd_build takes lot-06 (setup)")
	t.ok(_q(b)[0]["reason"] == "lot_taken", "the queued watchtower shows lot_taken")
	b.tick(b.substep_s())
	t.ok(_q(b).size() == 1 and _q(b)[0]["status"] == "skipped_gate" and _q(b)[0]["reason"] == "lot_taken", "and stays after a step")
	# two queued builds on one lot: whichever starts first takes it
	var two := _mk()
	_funds(two, 500.0, 100.0)
	two.cmd_queue_build("house", "lot-07")
	two.cmd_queue_build("well", "lot-07")
	t.ok(_col(_q(two), "status") == ["next", "skipped_gate"] and _q(two)[1]["reason"] == "lot_taken",
		"two builds on lot-07: the house is next and the walk gives it the lot, so the well already shows lot_taken")
	two.tick(two.substep_s())
	t.ok(_q(two).size() == 1 and _q(two)[0]["building_id"] == "well" and _q(two)[0]["reason"] == "lot_taken", "the house took it; the well shows lot_taken")


## Rule 3: queue_started carries waited_on, the last reason that kept the entry from starting.
func _rule3_waited_on() -> void:
	t.suite("build_queue-rule3")
	var s := _mk()
	_funds(s, 0.0, 0.0)
	s.cmd_queue_build("house", "lot-05")
	t.ok(_q(s)[0]["status"] == "waiting_funds" and _q(s)[0]["waited_on"] == "no_gold", "queued short of gold: waiting_funds, waited_on no_gold")
	s.cmd_debug_grant({"gold": 100.0, "bone": 50.0})
	s.drain_events()
	s.tick(s.substep_s())
	var st := _started(s.drain_events())
	t.ok(st.size() == 1 and st[0]["waited_on"] == "no_gold" and st[0]["level"] == 1 and not st[0]["upgrade"] and st[0]["t"] == s.t,
		"it starts once funded: queue_started {.., waited_on: no_gold} at the step's t: %s" % str(st))
	var n := _mk()
	_funds(n, 100.0, 50.0)
	n.cmd_queue_build("house", "lot-05")
	n.drain_events()
	n.tick(n.substep_s())
	st = _started(n.drain_events())
	t.ok(st.size() == 1 and st[0]["waited_on"] == "", "one that could start at once: waited_on \"\": %s" % str(st))
	# the step's processing keeps the latest reason: queued while affordable, then its gold spent elsewhere
	var p := _mk()
	_funds(p, 100.0, 50.0)
	p.cmd_queue_build("house", "lot-05")
	t.ok(_q(p)[0]["status"] == "next" and _q(p)[0]["waited_on"] == "", "queued while affordable: next, waited_on \"\"")
	_funds(p, 0.0, 50.0)
	p.tick(p.substep_s())
	t.ok(_q(p)[0]["status"] == "waiting_funds" and _q(p)[0]["waited_on"] == "no_gold", "its gold gone, a step marks it waited_on no_gold")
	p.cmd_debug_grant({"gold": 100.0})
	p.drain_events()
	p.tick(p.substep_s())
	st = _started(p.drain_events())
	t.ok(st.size() == 1 and st[0]["waited_on"] == "no_gold", "and it starts once funded, waited_on no_gold: %s" % str(st))


## Rule 4: a relics-blocked entry reads as the plateau's ask: reason no_relics and cost.relics exactly as
## view_catalog's row for the same building.
func _rule4_relics() -> void:
	t.suite("build_queue-rule4")
	var s := _fixture("midgame_2flips")
	s.cmd_debug_grant({"relics": -100})
	_funds(s, 1000.0, 290.0)
	var row: Dictionary = {}
	for r in s.view_catalog()["buildings"]:
		if r["building_id"] == "forge":
			row = r
	t.ok(row["reason"] == "no_relics" and not (row["lots"] as Array).is_empty(), "the catalog's forge: no_relics (setup: %s)" % row["reason"])
	t.ok(s.cmd_queue_build("forge", str(row["lots"][0]))["ok"], "the forge is queued")
	var e: Dictionary = _q(s)[0]
	t.ok(e["status"] == "skipped_gate" and e["reason"] == row["reason"] and e["cost"]["relics"] == row["cost"]["relics"],
		"the entry's reason and cost.relics are the row's: %s / %d" % [e["reason"], e["cost"]["relics"]])
	s.cmd_debug_grant({"relics": 1})
	s.drain_events()
	s.tick(s.substep_s())
	var st := _started(s.drain_events())
	t.ok(st.size() == 1 and st[0]["waited_on"] == "no_relics", "a relic in: it starts, waited_on no_relics: %s" % str(st))
	# short of gold and relics both: the catalog (afford_reason's order) says no_gold, the queue no_relics
	# (relics are a gate there), and cost.relics still agrees
	var two := _fixture("midgame_2flips")
	two.cmd_debug_grant({"relics": -100})
	_funds(two, 10.0, 290.0)
	var r2: Dictionary = {}
	for r in two.view_catalog()["buildings"]:
		if r["building_id"] == "forge":
			r2 = r
	t.ok(two.cmd_queue_build("forge", str(r2["lots"][0]))["ok"], "a forge queued short of gold and relics")
	var e2: Dictionary = _q(two)[0]
	t.ok(r2["reason"] == "no_gold" and e2["status"] == "skipped_gate" and e2["reason"] == "no_relics" and e2["cost"]["relics"] == r2["cost"]["relics"],
		"both short: the catalog says %s, the queue skipped_gate / %s, cost.relics %d both" % [r2["reason"], e2["reason"], e2["cost"]["relics"]])


## An unaffordable head holds the queue (it saves toward it): nothing behind it starts first, and it starts
## the step its cost is covered.
func _funds_hold() -> void:
	t.suite("build_queue-funds")
	var s := _mk()
	s.town_sim.place_building("lot-05", "house", 1)
	var cost := BuildRules.construction_cost(s, "house", 2)
	_funds(s, float(cost["gold"]) - 1.0, float(cost["bone"]) + 10.0)  # a few steps of income short
	var well := BuildRules.construction_cost(s, "well", 1)
	t.ok(s.town_sim.gold >= float(well["gold"]) and s.town_sim.bone >= float(well["bone"]), "(setup) the well behind it is affordable on its own")
	s.cmd_queue_build("", "lot-05")
	s.cmd_queue_build("well", "lot-06")  # affordable on its own
	s.drain_events()
	var steps := 0
	var before: Array = []
	var st: Array = []
	while st.is_empty() and steps < 400:
		before = [s.town_sim.gold, _col(_q(s), "status")]
		s.tick(s.substep_s())
		steps += 1
		st = _started(s.drain_events())
		if not st.is_empty():
			t.ok(st[0]["lot_id"] == "lot-05", "nothing behind the head starts first (step %d)" % steps)
	t.ok(steps > 1 and before[1] == ["waiting_funds", "queued"] and float(before[0]) < float(cost["gold"]),
		"the head waited %d steps for its gold (%.3f < %.1f); the well behind it stayed queued" % [steps, before[0], cost["gold"]])
	t.ok(st.size() >= 1 and st[0]["lot_id"] == "lot-05" and st[0]["level"] == 2 and st[0]["waited_on"] == "no_gold",
		"the house's upgrade starts the step its gold is in: %s" % str(st))


## Levels: two queued upgrades of a level-1 lot build 2, then 3; a reorder recomputes level and cost by
## position; they start one after the other as each construction finishes. (A level-1 house on lot-06: its
## levels 2 and 3 fit the base caps; the pit's are bought with bone since T7.)
func _levels() -> void:
	t.suite("build_queue-levels")
	var s := _mk()
	_funds(s, 0.0, 0.0)
	s.town_sim.place_building("lot-06", "house", 1)
	s.cmd_queue_build("", "lot-06")
	s.cmd_queue_build("house", "lot-05")
	s.cmd_queue_build("", "lot-06")
	var rows := _q(s)
	t.ok(_col(rows, "level") == [2, 1, 3] and rows[0]["cost"] == BuildRules.construction_cost(s, "house", 2)
		and rows[2]["cost"] == BuildRules.construction_cost(s, "house", 3), "levels 2, 1, 3 with their level_costs")
	s.build_queue[0]["waited_on"] = "tag"  # tells the two upgrade entries apart
	t.ok(s.cmd_reorder_queue([2, 1, 0])["ok"], "reorder [2, 1, 0]")
	rows = _q(s)
	t.ok(_col(rows, "level") == [2, 1, 3] and rows[2]["waited_on"] == "tag" and rows[2]["cost"] == BuildRules.construction_cost(s, "house", 3),
		"the entry that was first is now last and builds level 3 at level 3's cost: %s" % str(_col(rows, "waited_on")))
	s.build_queue[2]["waited_on"] = ""
	_funds(s, 5000.0, 150.0)
	var done: Array = []
	var started: Array = []
	for i in 4000:
		s.tick(s.substep_s())
		for e in s.drain_events():
			if e["type"] == "queue_started" and e["lot_id"] == "lot-06":
				started.append(e["level"])
			elif e["type"] == "building_done" and e["lot_id"] == "lot-06":
				done.append(e["level"])
		if done.size() == 2:
			break
	t.ok(started == [2, 3] and done == [2, 3] and int(s.town_sim.buildings["lot-06"]["level"]) == 3,
		"the house on lot-06 builds 2, then 3 (started %s, done %s)" % [str(started), str(done)])


## The view's statuses say what the next step does: `next` starts; `waiting_funds` (short by more than a
## step's income, no tier rise pending), `queued` and `skipped_gate` don't.
func _view_matches_step() -> void:
	t.suite("build_queue-view-step")
	var s := _mk()
	_funds(s, 100.0, 30.0)
	s.town_sim.place_building("lot-08", "house", 2)
	s.cmd_queue_build("house", "lot-05")  # 40: next
	s.cmd_queue_build("", "lot-08")  # the house's level 3, 120: short by 60 after the house
	s.cmd_queue_build("well", "lot-06")  # behind the waiting head
	s.cmd_queue_build("watchtower", "lot-07")  # needs_tier
	t.ok(BuildRules.next_tier(s)["tier"] == "village" and BuildRules.next_tier(s)["have"] < BuildRules.next_tier(s)["need"], "no tier rise pending")
	var rows := _q(s)
	t.ok(_col(rows, "status") == ["next", "waiting_funds", "queued", "skipped_gate"], "statuses: %s" % str(_col(rows, "status")))
	s.drain_events()
	s.tick(s.substep_s())
	var st := _started(s.drain_events())
	t.ok(st.size() == 1 and st[0]["building_id"] == "house", "the next step starts the `next` entry only: %s" % str(st))
	t.ok(_col(_q(s), "status") == ["waiting_funds", "queued", "skipped_gate"], "the rest are as they were")


## A tier-gated entry starts in the step the tier rises (processing runs right after rise_tiers), with
## waited_on needs_tier.
func _tier_rise() -> void:
	t.suite("build_queue-tier")
	var s := _mk()
	_funds(s, 2000.0, 190.0)
	s.town_sim.place_building("lot-06", "well", 1)
	t.ok(s.cmd_build("house", "lot-05")["ok"], "a house on its way makes 6 with the start set (setup)")
	s.town_sim.place_building("lot-07", "bakery", 1)
	t.ok(s.cmd_queue_build("inn", "lot-13")["ok"] and _q(s)[0]["reason"] == "lot_locked", "an inn on lot-13 waits on the tier (lot_locked)")
	s.drain_events()
	var tier_t := -1.0
	var st: Array = []
	for i in 2000:
		s.tick(s.substep_s())
		var evs := s.drain_events()
		for e in evs:
			if e["type"] == "tier_up":
				tier_t = e["t"]
		st = _started(evs)
		if tier_t >= 0.0:
			break
	t.ok(tier_t >= 0.0 and st.size() == 1 and st[0]["t"] == tier_t and st[0]["building_id"] == "inn" and st[0]["waited_on"] == "lot_locked",
		"the inn starts in the tier_up's step (t %.1f), waited_on lot_locked: %s" % [tier_t, str(st)])
	var e := _mk()
	var emb := BuildRules.construction_cost(e, "embalmer", 1)
	_funds(e, 2000.0, float(emb["bone"]) + 10.0)  # the embalmer's bone and the house's (T7: it is bought with bone)
	e.town_sim.place_building("lot-06", "well", 1)
	e.town_sim.place_building("lot-07", "bakery", 1)
	e.town_sim.place_building("lot-09", "bone_mill", _mill_level(float(emb["bone"]) + 10.0))  # its cap holds that
	e.cmd_build("house", "lot-05")
	e.blueprints.append("embalmer")
	e.cmd_debug_grant({"relics": 1})
	e.cmd_queue_build("embalmer", "lot-08")
	t.ok(_q(e)[0]["waited_on"] == "needs_tier", "an embalmer on an open lot waits on needs_tier")
	e.drain_events()
	st = []
	var rose := -1.0
	for i in 2000:
		e.tick(e.substep_s())
		var evs := e.drain_events()
		for x in evs:
			if x["type"] == "tier_up":
				rose = x["t"]
		st = _started(evs)
		if not st.is_empty():
			break
	t.ok(rose >= 0.0 and st.size() == 1 and st[0]["t"] == rose and st[0]["waited_on"] == "needs_tier" and e.town_tier == "village",
		"it starts in the step the tier rose (t %.1f), waited_on needs_tier: %s" % [rose, str(st)])


## The walk's own gates, past cmd_queue_build: max_level (a cmd_upgrade under two queued upgrades moves them
## up a level), unique (a cmd_build of a unique building elsewhere), lot_too_small (an entry a save carries
## that today's sizes refuse); and a gated entry reserves no relics.
func _walk_gates() -> void:
	t.suite("build_queue-walk-gates")
	var s := _mk()
	_funds(s, 0.0, 0.0)
	var top := int(TestUtil.configs()["buildings"]["well"]["max_level"])  # a well two levels under its top
	s.town_sim.place_building("lot-05", "well", top - 2)
	s.cmd_queue_build("", "lot-05")
	s.cmd_queue_build("", "lot-05")
	_funds(s, 1000.0, 300.0)
	t.ok(s.cmd_upgrade("lot-05")["ok"], "the well's level %d started by hand under its two queued upgrades" % (top - 1))
	var rows := _q(s)
	t.ok(_col(rows, "level") == [top, top + 1] and rows[1]["status"] == "skipped_gate" and rows[1]["reason"] == "max_level",
		"they now build %d and %d; the second is skipped (max_level): %s" % [top, top + 1, str(_col(rows, "reason"))])
	var u := TestUtil.configs().duplicate(true)
	u["buildings"]["well"]["unique"] = true
	var w := _mk(u)
	_funds(w, 0.0, 0.0)
	w.cmd_queue_build("well", "lot-05")
	_funds(w, 100.0, 30.0)
	t.ok(w.cmd_build("well", "lot-06")["ok"], "a unique well built by hand elsewhere (setup)")
	t.ok(_q(w)[0]["status"] == "skipped_gate" and _q(w)[0]["reason"] == "unique", "the queued one is skipped (unique)")
	var d := _mk().to_dict()
	d["queue"] = [{"building_id": "market", "lot_id": "lot-05", "upgrade": false, "waited_on": ""}]
	var l := GameState.new(TestUtil.configs())
	t.ok(l.from_dict(d)["ok"] and _q(l)[0]["status"] == "skipped_gate" and _q(l)[0]["reason"] == "lot_too_small",
		"a saved market on a size-1 lot loads, skipped (lot_too_small)")
	var r := _mk()
	r.cmd_debug_grant({"relics": 1})
	_funds(r, 1000.0, 200.0)
	r.cmd_queue_build("watchtower", "lot-05")  # needs_tier, 1 relic
	r.cmd_queue_build("", "lot-01")  # the crypt's level 2, 1 relic
	t.ok(_col(_q(r), "status") == ["skipped_gate", "next"], "the gated watchtower reserves no relic: the crypt's upgrade is next with the only one")
	r.drain_events()
	r.tick(r.substep_s())
	var st := _started(r.drain_events())
	t.ok(st.size() == 1 and st[0]["lot_id"] == "lot-01" and r.relics == 0, "and starts with it: %s" % str(st))


## cmd_demolish under a queued upgrade: it shows skipped_gate (empty_lot) and the walk goes on.
func _demolish_under() -> void:
	t.suite("build_queue-demolish")
	var s := _mk()
	_funds(s, 100.0, 30.0)
	s.town_sim.place_building("lot-05", "house", 1)
	s.cmd_queue_build("", "lot-05")
	s.cmd_queue_build("well", "lot-06")
	t.ok(s.cmd_demolish("lot-05")["ok"], "the house is demolished")
	t.ok(_col(_q(s), "status") == ["skipped_gate", "next"] and _q(s)[0]["reason"] == "empty_lot", "its upgrade: skipped_gate (empty_lot); the well is next")
	s.drain_events()
	s.tick(s.substep_s())
	t.ok(_started(s.drain_events()).size() == 1 and _q(s).size() == 1, "the well starts; the upgrade stays")


## A cap building demolished: an entry costing more than the new cap shows skipped_gate (cost_exceeds_cap),
## and the queue behind it runs, instead of waiting forever on a cost it can never hold.
func _cap_dropped() -> void:
	t.suite("build_queue-cap")
	var s := _fixture("midgame_2flips")
	s.town_sim.place_building("lot-13", "chapel_of_vats", 1)
	s.cmd_debug_grant({"relics": 5})
	_funds(s, 1500.0, 290.0)
	var cost := BuildRules.construction_cost(s, "chapel_of_vats", 2)
	t.ok(float(cost["bone"]) > float(TestUtil.configs()["economy"]["bone"]["cap"]) and float(cost["bone"]) <= s.town_sim.bone_cap(),
		"the chapel's level 2 (%.0f bone) is over the base bone cap and under the mill's (%.0f)" % [cost["bone"], s.town_sim.bone_cap()])
	t.ok(s.cmd_queue_build("", "lot-13")["ok"] and s.cmd_queue_build("house", "lot-08")["ok"], "the chapel's upgrade and a house are queued")
	var mill := ""
	for lot_id in s.town_sim.buildings:
		if s.town_sim.buildings[lot_id]["building_id"] == "bone_mill":
			mill = lot_id
	t.ok(s.cmd_demolish(mill)["ok"], "the bone mill is demolished (cap %.0f)" % s.town_sim.bone_cap())
	t.ok(_q(s)[0]["status"] == "skipped_gate" and _q(s)[0]["reason"] == "cost_exceeds_cap" and _q(s)[1]["status"] == "next",
		"the chapel's upgrade is skipped (cost_exceeds_cap), the house next: %s" % str(_col(_q(s), "status")))
	s.drain_events()
	s.tick(s.substep_s())
	var st := _started(s.drain_events())
	t.ok(st.size() == 1 and st[0]["building_id"] == "house" and _q(s).size() == 1, "the house starts; the upgrade stays, skipped")


## cmd_unqueue and cmd_reorder_queue: their refusals, and rev.
func _commands() -> void:
	t.suite("build_queue-commands")
	var s := _mk()
	_funds(s, 0.0, 0.0)
	s.cmd_queue_build("house", "lot-05")
	s.cmd_queue_build("well", "lot-06")
	var rv := s.rev
	t.ok(s.cmd_unqueue(2) == {"ok": false, "reason": "unknown_index"} and s.cmd_unqueue(-1)["reason"] == "unknown_index" and s.rev == rv, "unknown_index; rev stays")
	for bad in [[0], [0, 0], [0, 2], [1, 0, 2], ["a", 1], [0.5, 1]]:
		t.ok(s.cmd_reorder_queue(bad) == {"ok": false, "reason": "bad_order"}, "bad_order: %s" % str(bad))
	t.ok(s.rev == rv, "refusals leave rev alone")
	t.ok(s.cmd_reorder_queue([1, 0]) == {"ok": true, "reason": ""} and s.rev == rv + 1 and _col(_q(s), "building_id") == ["well", "house"],
		"reorder [1, 0]: order[k] is the old index that moves to k; rev + 1")
	t.ok(s.cmd_reorder_queue([1.0, 0.0])["ok"] and _col(_q(s), "building_id") == ["house", "well"], "whole-number floats are indices too")
	t.ok(s.cmd_unqueue(0) == {"ok": true, "reason": ""} and _col(_q(s), "building_id") == ["well"], "unqueue 0")
	s.cmd_new_game(2)
	t.ok(_q(s).is_empty(), "a new game empties the queue")


## The save keeps the queue (an optional top-level `queue`, SAVE_VERSION 2); an old save loads with an
## empty one; entries naming a building or lot today's config lacks are dropped with a warning.
func _save() -> void:
	t.suite("build_queue-save")
	var s := _mk()
	_funds(s, 0.0, 0.0)
	s.cmd_queue_build("house", "lot-05")
	s.cmd_queue_build("watchtower", "lot-06")
	s.cmd_queue_build("", "lot-05")
	var d := s.to_dict()
	t.ok(d["queue"] == [{"building_id": "house", "lot_id": "lot-05", "upgrade": false, "waited_on": "no_gold"},
		{"building_id": "watchtower", "lot_id": "lot-06", "upgrade": false, "waited_on": "needs_tier"},
		{"building_id": "house", "lot_id": "lot-05", "upgrade": true, "waited_on": ""}], "to_dict writes the entries: %s" % str(d["queue"]))
	var back := GameState.new(TestUtil.configs())
	t.ok(back.from_dict(JSON.parse_string(JSON.stringify(d)))["ok"] and back.view_town()["queue"] == s.view_town()["queue"]
		and back.to_dict()["queue"] == d["queue"], "a JSON round trip keeps the queue and its view")
	var old := d.duplicate(true)
	old.erase("queue")
	var o := GameState.new(TestUtil.configs())
	t.ok(o.from_dict(old)["ok"] and o.view_town()["queue"] == [], "a save without `queue` loads with an empty queue")
	var odd := d.duplicate(true)
	odd["queue"].append({"building_id": "nope", "lot_id": "lot-05", "upgrade": false, "waited_on": ""})
	odd["queue"].append({"building_id": "house", "lot_id": "lot-99", "upgrade": false})
	print("  (two warnings about dropped queue entries are expected next)")
	var w := GameState.new(TestUtil.configs())
	t.ok(w.from_dict(odd)["ok"] and w.to_dict()["queue"] == d["queue"], "unknown building and lot ids are dropped (a missing waited_on reads \"\")")
	var bad := d.duplicate(true)
	bad["queue"] = [{"building_id": 3, "lot_id": "lot-05", "upgrade": false}]
	t.ok(GameState.new(TestUtil.configs()).from_dict(bad) == {"ok": false, "reason": "corrupt"}, "a queue entry of the wrong shape is corrupt")


# ------------------------------------------------------------------ R2: affordable_in_s ----
## R2 (the E2b-2 vision review, item 3; the run's manager: "data, not a skip"): view_town().queue[i].affordable_in_s
## (STATE-API §5.9, MECHANICS §4.4) is 0.0 when an entry is affordable now, the seconds until it is at today's net
## rates, or −1.0 when it never is; cmd_queue_build returns the new entry's.

## day1's first overnight (F1: the Bone Mill's level 1 is priced in gold only, 60 gold, BALANCE §7): a House, a
## Well, a Bakery, then a Bone Mill. The House and the Well are affordable now (0.0, next), the Bakery waits on gold
## at the day's +0.21/s, and the Mill waits behind it on gold too, (50 + 60 − stock) / net: it costs no bone, so
## the three's 10 bone each leave it nothing to wait on there. At 20 bone it was the last of day1's 30 and only a
## mill makes bone: −1.0 for ever, R2's deadlock (tests/test_day1_queues.gd runs both queues 8 h). With the gold
## granted all four start in one step. And a store short at a net of 0 still reads −1.0 (cmd_queue_build's
## extra too, the review's "warn at queue time"): day1 with its bone spent and no mill, a House.
func _afford_deadlock() -> void:
	t.suite("build_queue-afford-day1")
	var s := _fixture("day1")
	s.tick(s.substep_s())  # a step's rates (a fixture loads with none)
	var net: Dictionary = s.view_rates()["rates"]
	t.ok(float(net["bone"]["net"]) == 0.0 and float(net["gold"]["net"]) > 0.0 and s.town_sim.bone == 30.0,
		"(setup) day1 a step in: bone 30 at 0/s, gold at %+.3f/s" % float(net["gold"]["net"]))
	var plan := [["house", "lot-05"], ["well", "lot-06"], ["bakery", "lot-07"], ["bone_mill", "lot-08"]]
	var extras: Array = []
	var at_queue: Array = []
	for p in plan:
		var r := s.cmd_queue_build(p[0], p[1])
		extras.append(r["affordable_in_s"])
		at_queue.append(float(_q(s).back()["affordable_in_s"]))
	var rows := _q(s)
	var gold_left := s.town_sim.gold - 70.0  # after the House's 40 and the Well's 30
	var g := float(net["gold"]["net"])
	t.ok(_col(rows, "status") == ["next", "next", "waiting_funds", "queued"], "(setup) House and Well next, the Bakery waits, the Mill queued: %s" % str(_col(rows, "status")))
	t.ok(float(rows[3]["cost"]["bone"]) == 0.0 and float(rows[3]["cost"]["gold"]) == 60.0, "the Mill's level 1 costs 60 gold and no bone: %s" % str(rows[3]["cost"]))
	t.ok(rows[0]["affordable_in_s"] == 0.0 and rows[1]["affordable_in_s"] == 0.0, "affordable now: the House and the Well read 0.0")
	t.ok(absf(float(rows[2]["affordable_in_s"]) - (50.0 - gold_left) / g) < 1e-6,
		"the Bakery: (50 − %.3f) / %.3f = %.3f s" % [gold_left, g, float(rows[2]["affordable_in_s"])])
	t.ok(absf(float(rows[3]["affordable_in_s"]) - (50.0 + 60.0 - gold_left) / g) < 1e-6,
		"the Mill waits on gold behind it: (50 + 60 − %.3f) / %.3f = %.3f s, not −1.0" % [gold_left, g, float(rows[3]["affordable_in_s"])])
	t.ok(extras == at_queue and extras == _col(rows, "affordable_in_s") and float(extras[3]) > 0.0,
		"cmd_queue_build's affordable_in_s is the new entry's row, then and now: %s" % str(extras))
	s.cmd_debug_grant({"gold": 100.0})
	s.drain_events()
	s.tick(s.substep_s())
	var st := _started(s.drain_events())
	t.ok(st.size() == 4 and _q(s).is_empty() and s.town_sim.bone == 0.0,
		"the gold granted, all four start in one step, the Mill too, on the three's 30 bone: %s" % str(st.map(func(e): return e["building_id"])))
	var z := _fixture("day1")
	z.tick(z.substep_s())
	_funds(z, z.town_sim.gold, 0.0)
	var r := z.cmd_queue_build("house", "lot-05")
	var h: Dictionary = _q(z)[0]
	t.ok(h["status"] == "waiting_funds" and h["reason"] == "no_bone" and h["affordable_in_s"] == -1.0 and r["affordable_in_s"] == -1.0,
		"day1 with no bone and no mill: a House waits on bone at 0/s, −1.0 (the view and the extra): %s %s" % [str(h["affordable_in_s"]), str(r["affordable_in_s"])])


## The times: a gold-short entry with gold coming in reads (cost − stock) / net, the net view_rates (and the HUD)
## shows below the cap, to 1e-6; the one behind it counts the first's cost, (c1 + c2 − stock) / net; neither
## moves when more is queued behind. A gated entry gets its own funds' time and holds nothing.
func _afford_times() -> void:
	t.suite("build_queue-afford-times")
	var s := _fixture("day1")
	s.tick(s.substep_s())
	_funds(s, 10.0, 30.0)
	var net := float(s.view_rates()["rates"]["gold"]["net"])
	t.ok(net > 0.0 and s.town_sim.gold < s.town_sim.gold_cap(), "(setup) day1 a step in, 10 gold under its cap at %+.3f/s" % net)
	var r1 := s.cmd_queue_build("house", "lot-05")
	var r2 := s.cmd_queue_build("well", "lot-06")
	var rows := _q(s)
	t.ok(rows[0]["status"] == "waiting_funds" and absf(float(rows[0]["affordable_in_s"]) - (40.0 - 10.0) / net) < 1e-6,
		"a gold-short House: (40 − 10) / %.3f = %.6f s: %s" % [net, (40.0 - 10.0) / net, str(rows[0]["affordable_in_s"])])
	t.ok(absf(float(rows[1]["affordable_in_s"]) - (40.0 + 30.0 - 10.0) / net) < 1e-6,
		"the Well behind it counts the House's 40: (40 + 30 − 10) / %.3f = %.6f s: %s" % [net, (70.0 - 10.0) / net, str(rows[1]["affordable_in_s"])])
	t.ok(r1["affordable_in_s"] == rows[0]["affordable_in_s"] and r2["affordable_in_s"] == rows[1]["affordable_in_s"],
		"cmd_queue_build's extras match the view: %s %s" % [str(r1["affordable_in_s"]), str(r2["affordable_in_s"])])
	# a gated entry ahead holds nothing: a House on locked lot-09 put first moves neither time, and gets its own
	var g := _fixture("day1")
	g.tick(g.substep_s())
	_funds(g, 10.0, 30.0)
	g.cmd_queue_build("house", "lot-09")
	g.cmd_queue_build("house", "lot-05")
	g.cmd_queue_build("well", "lot-06")
	var gr := _q(g)
	t.ok(gr[0]["reason"] == "lot_locked" and _col(gr.slice(1), "affordable_in_s") == _col(rows, "affordable_in_s"),
		"a gated House ahead (lot_locked) holds nothing: the House's and the Well's times are as without it: %s" % str(_col(gr, "affordable_in_s")))
	t.ok(absf(float(gr[0]["affordable_in_s"]) - (40.0 - 10.0) / net) < 1e-6,
		"the gated House gets its own funds' time, (40 − 10) / %.3f: %s" % [net, str(gr[0]["affordable_in_s"])])


## −1.0: a relic shortfall (relics have no idle income), and a cost above its store's cap now. The crypt's level 2
## (1 relic) with gold and bone to spare reads −1.0 with no relics and 0.0 with one. After the Bone Mill goes, a
## Chapel of Vats level 2 costs more bone than the cap: −1.0, though the bone the store kept above its cap covers it.
func _afford_never() -> void:
	t.suite("build_queue-afford-never")
	var s := _mk()
	s.tick(s.substep_s())
	_funds(s, 1000.0, 100.0)
	var r := s.cmd_queue_build("", "lot-01")
	var row: Dictionary = _q(s)[0]
	t.ok(row["reason"] == "no_relics" and float(row["cost"]["relics"]) > s.relics and float(row["cost"]["gold"]) <= 1000.0 and float(row["cost"]["bone"]) <= 100.0,
		"(setup) the crypt's level 2 is short of relics only: %s" % str(row["cost"]))
	t.ok(row["affordable_in_s"] == -1.0 and r["affordable_in_s"] == -1.0, "a relic shortfall reads −1.0 (raid for relics), the view and the extra: %s %s" % [
		str(row["affordable_in_s"]), str(r["affordable_in_s"])])
	s.cmd_debug_grant({"relics": 1})
	t.ok(_q(s)[0]["status"] == "next" and _q(s)[0]["affordable_in_s"] == 0.0, "with the relic: next, 0.0")
	var c := _fixture("midgame_2flips")
	c.town_sim.place_building("lot-13", "chapel_of_vats", 1)
	c.cmd_debug_grant({"relics": 5})
	_funds(c, 1500.0, 290.0)
	c.tick(c.substep_s())
	_funds(c, 1500.0, 290.0)
	t.ok(c.cmd_queue_build("", "lot-13")["ok"], "(setup) the chapel's level 2 queued under the mill's cap")
	for lot_id in c.town_sim.buildings.keys():
		if c.town_sim.buildings[lot_id]["building_id"] == "bone_mill":
			c.cmd_demolish(lot_id)
	var ch: Dictionary = _q(c)[0]
	t.ok(ch["reason"] == "cost_exceeds_cap" and float(ch["cost"]["bone"]) > c.town_sim.bone_cap() and c.town_sim.bone >= float(ch["cost"]["bone"])
		and c.town_sim.gold >= float(ch["cost"]["gold"]) and c.relics >= int(ch["cost"]["relics"]),
		"(setup) the mill gone: %.0f bone over the %.0f cap, the stores holding all of it" % [float(ch["cost"]["bone"]), c.town_sim.bone_cap()])
	t.ok(ch["affordable_in_s"] == -1.0, "a cost above its store's cap reads −1.0: %s" % str(ch["affordable_in_s"]))


## At the cap: view_rates' gold net reads 0 there (its `in` is clipped down to the upkeep), but the income comes
## back once an entry ahead spends the store under its cap, so the times use the income before the clip, less the
## upkeep (TownSim's trade − out). A config with a 100-gold cap (the Market adding none): day1 at the cap, a House
## and a Bakery now, then a Well 20 gold short: 20 / (trade − out), not −1.0.
func _afford_at_cap() -> void:
	t.suite("build_queue-afford-cap")
	var c := TestUtil.configs().duplicate(true)
	c["economy"]["gold"]["cap"] = 100.0
	c["buildings"]["market"]["effects"]["gold_cap"] = 0.0
	var s := GameState.new(c)
	s.debug_enabled = true
	s.cmd_debug_load_fixture("day1")
	s.town_sim.gold = 100.0
	s.tick(s.substep_s())
	var g: Dictionary = s.town_sim.rates["gold"]
	var hud := float(s.view_rates()["rates"]["gold"]["net"])
	t.ok(s.town_sim.gold_cap() == 100.0 and s.town_sim.gold == 100.0 and absf(hud) < 1e-9 and float(g["trade"]) > float(g["out"]),
		"(setup) gold full at its 100 cap: view_rates' net %.6f/s, income %.3f/s before the clip, upkeep %.3f/s" % [hud, float(g["trade"]), float(g["out"])])
	s.cmd_queue_build("house", "lot-05")
	s.cmd_queue_build("bakery", "lot-06")
	var w := s.cmd_queue_build("well", "lot-07")
	var rows := _q(s)
	var want := (40.0 + 50.0 + 30.0 - 100.0) / (float(g["trade"]) - float(g["out"]))
	t.ok(_col(rows, "status") == ["next", "next", "waiting_funds"] and absf(float(rows[2]["affordable_in_s"]) - want) < 1e-6 and w["affordable_in_s"] == rows[2]["affordable_in_s"],
		"the Well, 20 gold short once the two ahead spend the store: %.3f s at the income before the clip, not −1.0: %s" % [want, str(rows[2]["affordable_in_s"])])


## Status and time never disagree (one walk): over each fixture's full queue (queue.max_len entries), a step in, a
## `next` entry reads 0.0, a `waiting_funds` head never does, the entries that hold the queue are timed in order
## (a later one never earlier), a −1.0 names the store it waits on and a 0.0 none.
func _afford_invariant() -> void:
	t.suite("build_queue-afford-invariant")
	var tries := [["", "lot-02"], ["", "lot-04"], ["", "lot-04"], ["house", "lot-05"], ["well", "lot-06"], ["bakery", "lot-07"],
		["bone_mill", "lot-08"], ["house", "lot-09"], ["well", "lot-10"], ["house", "lot-11"], ["well", "lot-12"], ["", "lot-03"],
		["", "lot-03"], ["house", "lot-18"], ["well", "lot-19"], ["house", "lot-20"], ["", "lot-05"], ["", "lot-06"], ["", "lot-07"]]
	for fx in GameState.FIXTURES:
		var s := _fixture(fx)
		s.tick(s.substep_s())
		for p in tries:
			if s.build_queue.size() < BuildRules.queue_max(s):
				s.cmd_queue_build(p[0], p[1])
		var w := BuildRules.queue_walk(s, s.build_queue)
		var rows: Array = w["rows"]
		var bad: Array = []
		var last := 0.0
		var never := false
		for i in rows.size():
			var r: Dictionary = rows[i]
			var a := float(r["affordable_in_s"])
			var wait := str(w["waits"][i])
			if (r["status"] == "next" and a != 0.0) or (r["status"] == "waiting_funds" and a == 0.0):
				bad.append("%d %s at %s" % [i, r["status"], a])
			if r["status"] != "skipped_gate" and a >= 0.0 and not never and a < last:
				bad.append("%d earlier than the one ahead: %s < %s" % [i, a, last])
			if r["status"] != "skipped_gate" and a >= 0.0 and not never:
				last = a
			never = never or (r["status"] == "waiting_funds" and a < 0.0)
			if (a < 0.0 and wait == "") or (a == 0.0 and wait != ""):
				bad.append("%d %s waits on '%s'" % [i, a, wait])
		print("  [afford] %s: %s" % [fx, str(rows.map(func(r): return "%s %s %.1f" % [r["building_id"], r["status"], float(r["affordable_in_s"])]))])
		t.ok(rows.size() == BuildRules.queue_max(s) and bad.is_empty(), "%s, a full queue of %d: status and time agree%s" % [fx, rows.size(), "" if bad.is_empty() else ": " + str(bad)])
