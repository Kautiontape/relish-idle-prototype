extends RefCounted
## Phase I P3 (Q-b, option (a): the run's manager's ruling of 2026-11-18): the Grow stance (MECHANICS §4.5, IDLE §5,
## STATE-API §5.11; BuildRules.grow_target, grow_step, grow_start_s; economy.json stance.grow). From constructed
## states (a new game with buildings placed and stocks set):
## - a new game starts with it on when stance.grow.default_on (off when not), and it takes no slot (stance.slot_free):
##   three slot stances still fit beside it, a fourth is refused, and it is never suspended;
## - its condition: a build or upgrade has finished since the new game (the opening's levels alone don't arm it);
## - the pick: the soonest affordable, ties in stance.grow.order; one no income can pay is passed over;
## - the upkeep test: a gold-priced level is passed over while the gold income can't pay the bill (a gold earner isn't);
## - P3b: no pick at all while any building is unpaid (a Thrift-idled one doesn't count);
## - never while a queue head waits on funds; a parked (gated) entry doesn't stop it; a lot with a queue entry, a level
##   costing relics, over a cap or behind the tier, or a building not in `order`, is never picked;
## - at most stance.grow.max_active constructions under way, anyone's;
## - off, it starts nothing; a save keeps it on or off, and a save without it (the fixtures') loads with it off;
## - catch-up starts its pick when live play does (grow_start_s's clip), within the live run's substep;
## - the autoplayer never toggles it (its STANCES).
## Revert proofs (each run once, then restored): grow_step without the `held` check, 2 FAIL (_held: it starts the
## House while the head waits, so the unqueued start finds it built); without the max_active cap, 5 FAIL (two starts at
## once in _pick_order, _held's parked case and both _max_active rows); next_event_s without grow_start_s, 1 FAIL
## (_catchup_on_time: the catch-up starts it at the step's end, +210 s against +204.5 s); grow_target without the
## relic check, 1 FAIL (_never_picks, the House's L6 under an L8 mill's cap); grow_target without the upkeep test, 2 FAIL
## (_upkeep: the House's level 2 starts on the short bill; pre_vei's hour holds 15 Grow starts and sheds 9 buildings).

var t := TestUtil.new()
var _dir := "user://test_grow_%d" % OS.get_process_id()
const CLOCK := 1_800_000_000  # a "now" for the saves (unix seconds)


func run() -> int:
	t.suite("grow")
	_default_and_slots()
	_condition()
	_pick_order()
	_held()
	_never_picks()
	_upkeep()
	_waits_unpaid()
	_max_active()
	_off()
	_save()
	_catchup_on_time()
	_bot_never_toggles()
	_cleanup()
	return t.failures


## TestUtil.configs() with `over` ({"a.b.c": value}) set; Grow on by default unless `over` says otherwise.
static func cfgs(over := {}) -> Dictionary:
	var c := TestUtil.configs()
	c["economy"]["stance"]["grow"]["default_on"] = true
	var fld: Dictionary = c["realm"]["field"]
	fld["w"] = 8
	fld["h"] = 6
	c["economy"]["sim"]["prewarm_ticks"] = 0
	for path in over:
		var keys: PackedStringArray = str(path).split(".")
		var d: Dictionary = c
		for i in keys.size() - 1:
			d = d[keys[i]]
		d[keys[-1]] = over[path]
	return c


func _mk(c: Dictionary) -> GameState:
	var s := GameState.new(c)
	s.debug_enabled = true
	s.save_dir = _dir
	s.cmd_new_game(1)
	return s


func _funds(s: GameState, gold: float, bone: float) -> void:
	s.town_sim.gold = gold
	s.town_sim.bone = bone


func _grows(evs: Array) -> Array:
	return evs.filter(func(e): return e["type"] == "grow_started")


func _row(s: GameState, id: String) -> Dictionary:
	for r in s.view_stances()["stances"]:
		if r["id"] == id:
			return r
	return {}


func _cleanup() -> void:
	var d := DirAccess.open(_dir)
	if d == null:
		return
	for f in d.get_files():
		d.remove(f)
	DirAccess.remove_absolute(_dir)


func _default_and_slots() -> void:
	var shipped := TestUtil.shipped_configs()
	t.ok(bool(shipped["economy"]["stance"]["grow"]["default_on"]) and Autoplayer.cfgs()["economy"]["stance"]["grow"]["default_on"]
		and not TestUtil.configs()["economy"]["stance"]["grow"]["default_on"],
		"Grow ships on (economy.json stance.grow.default_on), the autoplayer's configs keep it, and the unit suites' TestUtil.configs() turn it off")
	var s := _mk(cfgs())
	t.ok(s.stances_on == ["grow"], "a new game starts with Grow on (stance.grow.default_on): %s" % str(s.stances_on))
	var v := s.view_stances()
	var g := _row(s, "grow")
	t.ok(g["on"] and not g["suspended"] and int(v["used"]) == 0 and (g["projected"] as Dictionary).is_empty(),
		"view_stances: Grow on, not suspended, takes no slot (used %d of %d), projects no rate" % [int(v["used"]), int(v["slots"])])
	var slots := int(v["slots"])
	var slot_ids := ["vigil", "harvest", "thrift", "muster", "hearth"]
	for i in slots:
		t.ok(s.cmd_set_stance(slot_ids[i], true)["ok"], "(setup) %s on: slot %d of %d" % [slot_ids[i], i + 1, slots])
	var r := s.cmd_set_stance(slot_ids[slots], true)
	t.ok(not r["ok"] and r["reason"] == "no_slot", "with Grow on, the %d slots hold %d slot stances and a further one is refused (no_slot)" % [slots, slots])
	t.ok(s.cmd_set_stance("grow", false)["ok"] and s.cmd_set_stance("grow", true)["ok"] and not _row(s, "grow")["suspended"]
		and int(s.view_stances()["used"]) == slots,
		"Grow turns off and on again with every slot full, never suspended, and the used count leaves it out")
	var off := _mk(cfgs({"economy.stance.grow.default_on": false}))
	t.ok(off.stances_on.is_empty() and not _row(off, "grow")["on"], "default_on false: a new game starts with nothing on")


func _condition() -> void:
	var s := _mk(cfgs())
	_funds(s, 1000.0, 150.0)
	s.drain_events()
	s.tick(4.0)
	var evs := s.drain_events()
	t.ok(not _row(s, "grow")["active"] and _grows(evs).is_empty(), "a new game: Grow is on but not active (the opening's levels only) and starts nothing")
	s.town_sim.place_building("lot-05", "house", 1)
	s.tick(2.0)
	evs = s.drain_events()
	var fired := evs.filter(func(e): return e["type"] == "stance_fired" and e["stance_id"] == "grow")
	t.ok(_row(s, "grow")["active"] and fired.size() == 1 and bool(fired[0]["active"]),
		"a finished building arms it: active at the next beat, one stance_fired {grow, active true}")


## The pick: day1 with a House placed (Grow armed) and 200 bone, no Bone Mill (no bone income). The Market's, the
## charnel house's and the House's level 2 are affordable now (the pit's is over the 200 cap), so the tie goes to
## `order` (market before charnel_house before house) and the Market starts: one start (max_active 1). Once it is
## done the charnel house's level 2 (130 bone) is short with no bone income, so it is passed over (never stalls) and
## the House's starts, though `order` puts the charnel house first.
func _pick_order() -> void:
	var s := _mk(cfgs())
	s.town_sim.place_building("lot-05", "house", 1)
	_funds(s, 1000.0, 200.0)
	s.drain_events()
	s.tick(2.0)
	var g := _grows(s.drain_events())
	var mk2 := BuildRules.construction_cost(s, "market", 2)
	t.ok(g.size() == 1 and g[0]["building_id"] == "market" and g[0]["lot_id"] == "lot-04" and int(g[0]["level"]) == 2
		and s.town_sim.buildings["lot-04"]["state"] == "constructing" and s.town_sim.bone <= 200.0 - float(mk2["bone"]) + 1e-6,
		"three affordable now: the tie goes to order, the Market's level 2 starts, paid (%s)" % str(g))
	var bone_left := s.town_sim.bone
	var tg := BuildRules.grow_target(s)
	t.ok(tg.is_empty() or tg["lot_id"] != "lot-03" or bone_left >= float(BuildRules.construction_cost(s, "charnel_house", 2)["bone"]),
		"(setup) the charnel house's level 2 is short on bone: %.1f bone, no mill" % bone_left)
	var got: Array = []
	for i in 600:
		s.tick(1.0)
		got = _grows(s.drain_events())
		if not got.is_empty():
			break
	t.ok(got.size() == 1 and got[0]["building_id"] == "house" and got[0]["lot_id"] == "lot-05",
		"with the Market done, the charnel house (no bone income) is passed over and the House's level 2 starts: %s" % str(got))


## Never while a queue head waits on funds: day1 with a Bone Mill and a House placed while Grow is off (staffed by a
## tick), then the charnel house's upgrade queued on 100 bone (130 due): a head waiting on bone (the mill staffed, so it
## holds; ruling 3's hold). Grow on: nothing starts though the House's level 2 is affordable. Unqueued: it starts.
func _held() -> void:
	var s := _mk(cfgs())
	s.cmd_set_stance("grow", false)
	s.town_sim.place_building("lot-06", "bone_mill", 1)
	s.town_sim.place_building("lot-05", "house", 1)
	s.tick(2.0)
	_funds(s, 1000.0, 100.0)
	t.ok(s.cmd_queue_build("", "lot-03")["ok"], "(setup) the charnel house's upgrade queued")
	s.cmd_set_stance("grow", true)
	s.drain_events()
	s.tick(2.0)
	var evs := s.drain_events()
	t.ok(s._queue_held == "no_bone" and _row(s, "grow")["active"] and _grows(evs).is_empty(),
		"a head waiting on bone (%s): Grow acts on nothing, though the House's level 2 is affordable" % s._queue_held)
	t.ok(s.cmd_unqueue(0)["ok"], "(setup) unqueued")
	s.tick(1.0)
	var g := _grows(s.drain_events())
	t.ok(g.size() == 1 and g[0]["lot_id"] == "lot-05", "with the queue empty, Grow starts the House's level 2: %s" % str(g))
	# a parked entry (gated: a Watchtower needs the town tier) holds nothing and doesn't stop it
	var p := _mk(cfgs())
	p.town_sim.place_building("lot-05", "house", 1)
	_funds(p, 1000.0, 200.0)
	t.ok(p.cmd_queue_build("watchtower", "lot-06")["ok"], "(setup) a Watchtower parked")
	p.drain_events()
	p.tick(2.0)
	t.ok(p.view_town()["queue"][0]["status"] == "skipped_gate" and _grows(p.drain_events()).size() == 1,
		"a parked entry (skipped_gate %s) doesn't stop Grow" % p.view_town()["queue"][0]["reason"])


## What it never picks, from grow_target on constructed states (`order` only the House, so the opening's buildings
## aren't candidates): a level costing relics (relics on hand), a cost over a cap, a level behind the tier (an Inn's,
## in a hamlet), a lot with a queue entry, a building not in `order`.
func _never_picks() -> void:
	var c := cfgs({"economy.stance.grow.order": ["house"]})
	var s := _mk(c)
	s.relics = 50
	var top := 0
	for lv in range(1, 9):
		if int(BuildRules.construction_cost(s, "house", lv)["relics"]) > 0:
			top = lv - 1
			break
	s.town_sim.place_building("lot-05", "house", top)
	var due := BuildRules.construction_cost(s, "house", top + 1)
	s.town_sim.place_building("lot-06", "bone_mill", 8)  # a cap over the level's price, so only its relics stand in the way
	_funds(s, s.town_sim.gold_cap(), s.town_sim.bone_cap())
	t.ok(BuildRules.over_cap(s, due) == "" and s.town_sim.bone >= float(due["bone"]) and s.town_sim.gold >= float(due["gold"]),
		"(setup) the House's L%d (%s) fits the caps and the stocks" % [top + 1, str(due)])
	t.ok(BuildRules.grow_target(s).is_empty(), "a House at L%d (its L%d costs relics; %d on hand): no pick" % [top, top + 1, s.relics])
	var cap := _mk(cfgs({"economy.stance.grow.order": ["house"], "economy.bone.cap": 10.0}))
	cap.town_sim.place_building("lot-05", "house", 1)
	_funds(cap, 5000.0, 10.0)
	t.ok(BuildRules.grow_target(cap).is_empty(), "a House whose L2 (%s bone) is over a 10-bone cap: no pick" % str(BuildRules.construction_cost(cap, "house", 2)["bone"]))
	var inn := _mk(cfgs({"economy.stance.grow.order": ["inn"]}))
	inn.town_sim.place_building("lot-05", "inn", 1)
	_funds(inn, 5000.0, 200.0)
	t.ok(inn.town_tier == "hamlet" and BuildRules.grow_target(inn).is_empty(), "an Inn in a hamlet (its L2 needs the village tier): no pick")
	var q := _mk(c)
	q.town_sim.place_building("lot-05", "house", 1)
	_funds(q, 5000.0, 200.0)
	var free := BuildRules.grow_target(q)
	t.ok(q.cmd_queue_build("", "lot-05")["ok"] and BuildRules.grow_target(q).is_empty() and free.get("lot_id", "") == "lot-05",
		"the House's lot picked, then not once the player queues its upgrade")
	var other := _mk(cfgs({"economy.stance.grow.order": ["inn"]}))
	other.town_sim.place_building("lot-05", "house", 1)
	_funds(other, 5000.0, 200.0)
	t.ok(BuildRules.grow_target(other).is_empty(), "a House when `order` names only the Inn: no pick")


## The upkeep test (the run's manager's ruling 1 on handoff 5; grow_target): a level with a gold price is passed over
## while the gold income can't pay the working buildings' gold upkeep (TownSim.income_pays at gold_income() and
## gold_due()); a gold earner (the Market: stall jobs) is exempt. A new game with a House (it arms Grow), and a Statue
## and Walls placed so the bill is over the two stalls' income; then the same without them. And pre_vei as shipped
## (0.60 g/s of income against a 1.07 g/s bill), 1 h away with Grow on: nothing starts and nothing goes unpaid in the
## hour, where an ungated Grow spends its stock on the living's levels and sheds the town 57 min in (the Grow-off shed
## is 2 h 8 min in).
func _upkeep() -> void:
	var c := cfgs({"economy.stance.grow.order": ["house", "charnel_house"]})
	for order in ["two", "shipped"]:
		var s := _mk(c if order == "two" else cfgs())
		s.town_sim.place_building("lot-05", "house", 1)
		s.town_sim.place_building("lot-06", "statue", 1)
		s.town_sim.place_building("lot-07", "walls", 1)
		_funds(s, 1000.0, 200.0)
		s.drain_events()
		s.tick(2.0)
		var ts := s.town_sim
		var g := _grows(s.drain_events())
		if order == "shipped":
			t.ok(ts.gold_due() > ts.gold_income() and g.size() == 1 and g[0]["building_id"] == "market",
				"the shipped order, the same bill: the Market's level 2 (a gold earner) starts: %s" % str(g))
			continue
		t.ok(ts.gold_income() > 0.0 and ts.gold_due() > ts.gold_income(),
			"(setup) the bill over the income: %.3f g/s due, %.3f g/s in" % [ts.gold_due(), ts.gold_income()])
		var g0 := ts.gold
		s.tick(30.0)
		g.append_array(_grows(s.drain_events()))
		t.ok(g.is_empty() and BuildRules.grow_target(s).is_empty() and ts.gold > g0 - 30.0 * ts.gold_due() - 1e-6,
			"the income short of the bill, 32 s: the House's and the charnel house's level 2 are passed over, the gold only pays the upkeep (%.1f -> %.1f)" % [
			g0, ts.gold])
	var p := _mk(c)
	p.town_sim.place_building("lot-05", "house", 1)
	_funds(p, 1000.0, 200.0)
	p.drain_events()
	p.tick(2.0)
	var pg := _grows(p.drain_events())
	t.ok(p.town_sim.income_pays(p.town_sim.gold_income(), p.town_sim.gold_due()) and pg.size() == 1 and pg[0]["lot_id"] == "lot-05",
		"no Statue or Walls (%.3f g/s due, %.3f in): the House's level 2 starts: %s" % [p.town_sim.gold_due(), p.town_sim.gold_income(), str(pg)])
	var sc := cfgs()
	var v := GameState.new(sc)
	v.debug_enabled = true
	v.save_dir = _dir
	v.cmd_debug_load_fixture("pre_vei")
	v.cmd_set_stance("grow", true)
	v.tick(0.5)
	t.ok(v.town_sim.gold_due() > v.town_sim.gold_income() and v.stances_on.has("grow"),
		"(setup) pre_vei, Grow on: %.3f g/s due, %.3f in, %.0f gold" % [v.town_sim.gold_due(), v.town_sim.gold_income(), v.town_sim.gold])
	v.clock_override = CLOCK
	t.ok(v.cmd_save("up")["ok"], "(setup) saved")
	var n := GameState.new(sc)
	n.save_dir = _dir
	n.clock_override = CLOCK + 3600
	t.ok(n.cmd_load("up")["ok"], "(setup) loaded 1 h on")
	var evs := n.catchup_events()
	var unpaid := evs.filter(func(e): return e["type"] == "building_unpaid" and bool(e["unpaid"]))
	t.ok(_grows(evs).is_empty() and unpaid.is_empty(),
		"pre_vei with Grow on, 1 h away: %d Grow starts, %d buildings unpaid (%.0f gold left)" % [_grows(evs).size(), unpaid.size(), n.town_sim.gold])


## P3b (ruling 12, changed): Grow waits while any building is unpaid, whatever the income. A House whose level 2 the
## income pays, beside a Statue shed (unpaid, its hold running): no start, and no pick in view_stances; the Statue back
## at work (as its resume sets it), the House's level 2 starts.
## Revert proof: grow_target without the any_unpaid wait, 2 FAIL (the House's level 2 starts beside the unpaid Statue).
func _waits_unpaid() -> void:
	var s := _mk(cfgs({"economy.stance.grow.order": ["house"]}))
	s.town_sim.place_building("lot-05", "house", 1)
	s.town_sim.place_building("lot-06", "statue", 1)
	var sb: Dictionary = s.town_sim.buildings["lot-06"]
	sb["state"] = "unpaid"
	sb["unpaid_s"] = 600.0
	_funds(s, 1000.0, 200.0)
	s.drain_events()
	s.tick(2.0)
	var g := _grows(s.drain_events())
	var ts := s.town_sim
	t.ok(ts.income_pays(ts.gold_income(), ts.gold_due()) and str(ts.buildings["lot-06"]["state"]) == "unpaid",
		"(setup) the income pays the working bill (%.3f g/s due, %.3f in), the Statue unpaid" % [ts.gold_due(), ts.gold_income()])
	t.ok(g.is_empty() and BuildRules.grow_target(s).is_empty() and str(s.view_stances()["grow"]["building_id"]) == "",
		"a Statue unpaid: Grow starts nothing and view_stances.grow names no pick: %s" % str(g))
	t.ok(BuildRules.grow_start_s(s) == INF, "a Statue unpaid: grow_start_s is INF (catch-up clips nothing for Grow)")
	sb["state"] = "active"
	sb["unpaid_s"] = 0.0
	s.tick(1.0)
	g = _grows(s.drain_events())
	t.ok(g.size() == 1 and g[0]["lot_id"] == "lot-05",
		"the Statue back at work: the House's level 2 starts: %s" % str(g))


## stance.grow.max_active: a House under construction (the player's) keeps Grow from starting at 1; at 2 it starts one.
func _max_active() -> void:
	for n in [1, 2]:
		var s := _mk(cfgs({"economy.stance.grow.max_active": n}))
		s.town_sim.place_building("lot-05", "house", 1)
		_funds(s, 1000.0, 200.0)
		t.ok(s.cmd_build("house", "lot-06")["ok"], "(setup) a House building on lot-06")
		s.drain_events()
		s.tick(2.0)
		var g := _grows(s.drain_events())
		t.ok(g.size() == n - 1, "max_active %d with one construction under way: %d Grow starts" % [n, g.size()])


func _off() -> void:
	var s := _mk(cfgs({"economy.stance.grow.default_on": false}))
	s.town_sim.place_building("lot-05", "house", 1)
	_funds(s, 1000.0, 200.0)
	s.drain_events()
	s.tick(30.0)
	t.ok(_grows(s.drain_events()).is_empty() and _row(s, "grow")["active"], "off (default_on false): active, and nothing starts in 30 s")


func _save() -> void:
	var c := cfgs()
	for on in [true, false]:
		var s := _mk(c)
		s.cmd_set_stance("grow", on)
		s.clock_override = CLOCK
		t.ok(s.cmd_save("g")["ok"], "(setup) saved")
		var n := GameState.new(c)
		n.save_dir = _dir
		n.clock_override = CLOCK
		t.ok(n.cmd_load("g")["ok"] and n.stances_on.has("grow") == on, "a save with Grow %s loads with it %s" % ["on" if on else "off", "on" if on else "off"])
	var f := GameState.new(c)
	f.debug_enabled = true
	t.ok(f.cmd_debug_load_fixture("midgame_2flips")["ok"] and not f.stances_on.has("grow"),
		"a save without Grow (the fixtures', before v14) loads with it off: its on-list is the player's")


## Catch-up starts Grow's pick when live play would: day1 with a House placed and Grow off for 2 min (the Market's
## stalls staffed, its gold income settled), `order` only the House, then Grow on with the gold 205 s of that income
## short of the House's level 2 (so it falls mid-step). 600 s live at 0.5 s substeps against 600 s away at 10 s steps
## (catchup_max_steps 60): the catch-up's start is within the live run's substep (grow_start_s's clip).
func _catchup_on_time() -> void:
	var c := cfgs({"economy.stance.grow.order": ["house"], "economy.idle.catchup_max_steps": 60})
	var s := _mk(c)
	s.cmd_set_stance("grow", false)
	s.town_sim.place_building("lot-05", "house", 1)
	s.tick(120.0)
	var need := float(BuildRules.construction_cost(s, "house", 2)["gold"])
	var net := float(BuildRules.queue_net(s)["gold"])
	_funds(s, maxf(0.0, need - net * 205.0), 200.0)
	s.cmd_set_stance("grow", true)
	s.tick(s.substep_s())
	var tg := BuildRules.grow_target(s)
	t.ok(not tg.is_empty() and float(tg["in_s"]) > 30.0 and float(tg["in_s"]) < 590.0,
		"(setup) the House's level 2 is %.1f s away" % float(tg.get("in_s", -1.0)))
	var live := GameState.new(c)
	live.debug_enabled = true
	live.from_dict(s.to_dict())
	live.drain_events()
	live.tick(600.0)
	var lg := _grows(live.drain_events())
	s.clock_override = CLOCK
	t.ok(s.cmd_save("cu")["ok"], "(setup) saved")
	var n := GameState.new(c)
	n.save_dir = _dir
	n.clock_override = CLOCK + 600
	t.ok(n.cmd_load("cu")["ok"], "(setup) loaded 600 s on")
	var ng := _grows(n.catchup_events())
	var live_t := float(lg[0]["t"]) if lg.size() == 1 else -1.0
	var cu_t := float(ng[0]["t"]) if ng.size() == 1 else -1.0
	t.ok(live_t > s.t and fmod(live_t - s.t, 10.0) > 1.0 and fmod(live_t - s.t, 10.0) < 9.0,
		"(setup) live starts it mid-step: +%.2f s" % (live_t - s.t))
	t.ok(cu_t > 0.0 and absf(cu_t - live_t) <= 0.5 + 1e-6,
		"the catch-up starts it at +%.3f s, within the live run's substep (+%.2f s)" % [cu_t - s.t, live_t - s.t])


func _bot_never_toggles() -> void:
	t.ok(not Autoplayer.STANCES.has("grow"), "the autoplayer's stances (%s) leave Grow alone: the bots get it because it is on" % str(Autoplayer.STANCES))
