extends RefCounted
## E4 step 10 (review-t7r1r2 §5, the Market side of the input-limited lever). Gold is
## min(staffed stalls · stall.rate, living · market.shop_rate) · price, so while the living buy less than the stalls can
## sell, a Market level (more stalls) sells nothing more and "build a Market" is the wrong lever. TownSim.trade_starved
## reads "living_first" after such a step; a queue row short of gold and not of bone reads it as its `starved`, with the
## lever "raise_living" (economy.json town.starved_lever); and the away report's never-on-gold line and the upkeep
## gate's line, which named a Market, name housing or an Inn (idle.report afford_living_fmt / _last_fmt,
## afford_upkeep_living_fmt). The income test's "Still stopped … Build a Market" (unpaid_upkeep_fmt) is unchanged: in a
## new game the shed reaches the Market (a `job` building) and its stalls before that line could read living_first.
## - (a) A new game with a House built, the living set to 1 (sales 0.03 against the stalls' 0.30; net gold −0.07/s),
##   gold 30, bone 30, the House's level 2 (80 / 20) queued: never on gold, 50 short, `starved` living_first and the
##   lever raise_living; saved and loaded 60 s on, the head line is afford_living's. The away is short because the
##   living regrow (Covington's own migrants, TownSim's held_villages): 10 min lifts them past the upkeep, and the
##   head becomes a timed wait. Gold stays above 0, so nothing is shed.
## - (b) The same at the start's 16 living (16 · 0.03 = 0.48 over the stalls' 0.30): the stalls bind, "" and a timed
##   wait.
## - (c) The upkeep gate: a new game at 1 living, a new House queued: gated `upkeep` (income 0.03 under the bill
##   0.09 + 0.01), and after a 60 s load the line is afford_upkeep_living's.
## - (d) A new game's own step: 10 living against 2 stalls, 0.30 against 0.30, a tie: "".
## - (e) After a load trade_starved is "" until the first step (it is never saved).
## - (f) A row's own reason (the E4 final review's item 5, handoff 23 ruling 4): only a head that can never be afforded
##   (−1.0) reads the flag of the store it is never on. At 8 living (0.24 against the stalls' 0.30) trade_starved reads
##   living_first while the House's level 2 is a timed wait on gold: its starved and lever read "". The bone side by the
##   same rule: with a working Bone Mill and mill_starved set to pits_first by hand, a timed wait on bone reads "";
##   with the mill gone, the never on bone reads pits_first and raise_war. Revert proof: on 2a9e596 both timed heads
##   read the flag (gold short and not bone: trade_starved; bone short: mill_starved).
## - (g) TownSim.clone() copies both flags (the E4 final review's item 6): (a)'s state, mill_starved set to no_bodies by
##   hand, cloned; the twin reads living_first and no_bodies, and a queue walk with the twin as the town reads the
##   head's living_first and raise_living as the town itself does. Revert proof: on 2a9e596 the twin reads "" and "".
## - (h) The upkeep gate's line reads the state the gate evaluated (the E4 final review's item 7): TownSim.trade_bound()
##   at the report, not the last step's trade_starved. With market.price 0.3 (full stalls earn 0.09/s, under the bill
##   0.10, so a new House is gated at any living) and idle.catchup_max_steps 1 (a 10 s load is one 10 s step), the
##   living are placed half the step's measured growth under the tie at 10: the step's flag (step 4, at its start)
##   reads living_first and the state at its end reads "", the stalls binding. The line is afford_upkeep_fmt's ("build
##   a Market": a Market level would sell more), not afford_upkeep_living_fmt's. Revert proof: with 2a9e596's
##   state_views.gd the line follows the stale flag and reads afford_upkeep_living_fmt's.

var t := TestUtil.new()
var _dir := "user://test_trade_starved_%d" % OS.get_process_id()
const CLOCK := 1_800_000_000
const AWAY_S := 60


func run() -> int:
	t.suite("trade_starved")
	DirAccess.make_dir_recursive_absolute(_dir)
	var c: Dictionary = load("res://tests/test_away.gd").cfgs()
	var rep: Dictionary = c["economy"]["idle"]["report"]
	_never(c, rep)
	_stalls_bind(c)
	_upkeep(c, rep)
	_tie(c)
	_timed(c)
	_clone(c)
	_upkeep_state(c, rep)
	_unpaid_living(c, rep)
	_falling(c, rep)
	_cleanup()
	return t.failures


## (i) Phase I P2 (Q-d): the income test's unpaid line names the lever that applies. (a)'s House, its state set unpaid
## by hand (unpaid_s 0, so held_by_income decides) at 1 living: the income 0.03 can't pay it, and the living buy less
## than the stalls can sell, so the line is unpaid_upkeep_living_fmt's (housing or an Inn), not "Build a Market".
## Revert proof: with fee92d6's state_views.gd the line is unpaid_upkeep_fmt's and both asserts on the text fail.
func _unpaid_living(c: Dictionary, rep: Dictionary) -> void:
	var s := _with_house(c)
	s.town_sim.living = 1.0
	s.town_sim.buildings["lot-07"]["state"] = "unpaid"
	s.town_sim.buildings["lot-07"]["unpaid_s"] = 0.0
	t.ok(s.town_sim.held_by_income("lot-07") and s.town_sim.trade_bound() == "living_first",
		"(setup) (i) the House unpaid and held by the income test, the living bound (income %.4f)" % s.town_sim.gold_income())
	var n := _load(s, "unpaid_living")
	t.ok(n.town_sim.held_by_income("lot-07") and n.town_sim.trade_bound() == "living_first", "(setup) (i) still so after the load")
	var fill := {"names": StateViews._building_name(n, rep, "house", 1), "rate": StateViews._fmt_rate(rep, n.town_sim.gold_income())}
	var ready: Array = n.view_away()["ready"]
	t.ok(ready.filter(func(l): return str(l["text"]) == str(rep["unpaid_upkeep_living_fmt"]).format(fill)).size() == 1,
		"(i) the unpaid line names housing or an Inn: %s" % JSON.stringify(ready))
	t.ok(not ready.any(func(l): return str(l["text"]) == str(rep["unpaid_upkeep_fmt"]).format(fill)), "(i) and not a Market")


## (j) Phase I P2 (Q-d, the close-out's "0 gold short" corner): a head waiting on bone whose gold covers it now, but
## whose gold falls under its price by the time the bone comes, is never on gold (_afford_at's falling-net check), so
## its short gold is 0. Set by hand on (a)'s state: gold 100, bone 0, the stalls' 0.03 g/s against 0.10 out (net
## −0.07), the mill's 0.01 bone/s, trade_starved living_first; the House's level 2 (80 gold, 20 bone) queued: 2 000 s to
## its bone, by when the gold is −40. The line keeps the living's lever and drops the count (afford_living_falling_fmt
## and _last_fmt). Revert proof: with fee92d6's state_views.gd it reads "0 gold short" and both asserts on it fail.
func _falling(c: Dictionary, rep: Dictionary) -> void:
	var s := _with_house(c)
	var ts := s.town_sim
	ts.gold = 100.0
	ts.bone = 0.0
	ts.rates["gold"].merge({"in": 0.03, "trade": 0.03, "out": 0.10}, true)
	ts.rates["bone"].merge({"in": 0.01, "mill": 0.01, "out": 0.0}, true)
	ts.trade_starved = "living_first"
	t.ok(s.cmd_queue_build("", "lot-07")["ok"], "(setup) (j) the House's level 2 queued")
	var w := BuildRules.queue_walk(s, s.build_queue)
	var row: Dictionary = w["rows"][0]
	t.ok(str(row["status"]) == "waiting_funds" and str(row["reason"]) == "no_bone" and float(row["affordable_in_s"]) == -1.0
		and str(w["waits"][0]) == "gold" and str(row["starved"]) == "living_first" and float(row["short"]["gold"]) == 0.0,
		"(setup) (j) waiting on bone, never on gold, starved living_first, 0 gold short: %s" % JSON.stringify(row))
	var net := BuildRules.queue_net(s)
	var name := StateViews._building_name(s, rep, "house", 2)
	for movable in [true, false]:
		var got := StateViews.afford_text(s, rep, row, str(w["waits"][0]), net, movable)
		var want := str(rep["afford_living_falling_fmt" if movable else "afford_living_falling_last_fmt"]).format({"name": name,
			"rate": StateViews._fmt_rate(rep, float(net["gold"]))})
		t.ok(got == want and not got.contains("0 gold short"), "(j) movable %s: the living's lever, no count: %s" % [str(movable), got])


func _game(c: Dictionary) -> GameState:
	var s := GameState.new(c)
	s.debug_enabled = true
	s.save_dir = _dir
	s.cmd_new_game(1)
	return s


## A new game with a House built on lot-07 (from the start's 80 gold and 30 bone).
func _with_house(c: Dictionary) -> GameState:
	var s := _game(c)
	t.ok(s.cmd_build("house", "lot-07")["ok"], "(setup) a House on lot-07")
	var built := func() -> bool:
		for b in s.view_town()["buildings"]:
			if str(b["lot_id"]) == "lot-07" and str(b["state"]) != "constructing":
				return true
		return false
	var guard := 0
	while not built.call() and guard < 2000:
		s.tick(s.substep_s())
		guard += 1
	t.ok(built.call(), "(setup) the House is built (%d steps)" % guard)
	return s


func _load(s: GameState, key: String) -> GameState:
	s.drain_events()
	s.clock_override = CLOCK
	t.ok(s.cmd_save(key)["ok"], "(setup) (%s) saved" % key)
	var n := GameState.new(s._cfgs)
	n.debug_enabled = true
	n.save_dir = _dir
	n.clock_override = CLOCK + AWAY_S
	var r := n.cmd_load(key)
	t.ok(r["ok"] and float(r["away_s"]) == float(AWAY_S), "(setup) (%s) loaded %d s on, living %.2f: %s" % [key, AWAY_S, n.town_sim.living, str(r)])
	return n


func _never(c: Dictionary, rep: Dictionary) -> void:
	var s := _with_house(c)
	s.town_sim.living = 1.0
	s.town_sim.gold = 30.0
	s.town_sim.bone = 30.0
	t.ok(s.cmd_queue_build("", "lot-07")["ok"], "(setup) (a) the House's level 2 queued")
	s.tick(s.substep_s())
	t.ok(s.town_sim.trade_starved == "living_first", "(a) TownSim.trade_starved reads living_first: %s" % s.town_sim.trade_starved)
	var head: Dictionary = s.view_town()["queue"][0]
	var short: Dictionary = head["short"]
	t.ok(str(head["reason"]) == "no_gold" and float(head["affordable_in_s"]) == -1.0 and float(short["gold"]) > 0.0
		and float(short["bone"]) == 0.0, "(a) the head waits never on gold, short of gold only: %s" % JSON.stringify(head))
	t.ok(str(head["starved"]) == "living_first" and str(head["lever"]) == "raise_living",
		"(a) the head reads starved living_first and the lever raise_living")
	var n := _load(s, "never")
	t.ok(n.town_sim.trade_starved == "living_first", "(a) after the load's catch-up: living_first")
	var h2: Dictionary = n.view_town()["queue"][0]
	t.ok(str(h2["starved"]) == "living_first" and float(h2["affordable_in_s"]) == -1.0, "(a) the loaded head too: %s" % JSON.stringify(h2))
	var fill := {"name": StateViews._building_name(n, rep, str(h2["building_id"]), int(h2["level"])),
		"short": StateViews._fmt_count(rep, ceilf(float(h2["short"]["gold"]))),
		"rate": StateViews._fmt_rate(rep, float(BuildRules.queue_net(n)["gold"]))}
	var want := [str(rep["afford_living_fmt"]).format(fill), str(rep["afford_living_last_fmt"]).format(fill)]
	var ready: Array = n.view_away()["ready"]
	var lines: Array = ready.filter(func(l): return want.has(str(l["text"])) and str(l["kind"]) == "queue")
	t.ok(lines.size() == 1, "(a) the away report's head line is afford_living's: %s" % JSON.stringify(ready))
	t.ok(not ready.any(func(l): return str(l["text"]).contains(str(rep["afford_raise"]["gold"]))),
		"(a) no line says %s" % str(rep["afford_raise"]["gold"]))
	# (e) never saved: a fresh load reads "" before its first step
	var m := GameState.new(c)
	m.save_dir = _dir
	m.clock_override = CLOCK
	t.ok(m.cmd_load("never")["ok"] and m.town_sim.trade_starved == "", "(e) a load with no gap: \"\" before its first step")


func _stalls_bind(c: Dictionary) -> void:
	var s := _with_house(c)
	s.town_sim.living = 16.0
	s.town_sim.gold = 30.0
	s.town_sim.bone = 30.0
	t.ok(s.cmd_queue_build("", "lot-07")["ok"], "(setup) (b) the House's level 2 queued")
	s.tick(s.substep_s())
	var head: Dictionary = s.view_town()["queue"][0]
	t.ok(s.town_sim.trade_starved == "" and str(head["starved"]) == "" and str(head["lever"]) == ""
		and float(head["affordable_in_s"]) > 0.0, "(b) the stalls bind: \"\" and a timed wait: %s" % JSON.stringify(head))


func _upkeep(c: Dictionary, rep: Dictionary) -> void:
	var s := _game(c)
	s.town_sim.living = 1.0
	t.ok(s.cmd_queue_build("house", "lot-07")["ok"], "(setup) (c) a new House queued")
	s.tick(s.substep_s())
	var head: Dictionary = s.view_town()["queue"][0]
	t.ok(str(head["status"]) == "skipped_gate" and str(head["reason"]) == "upkeep", "(c) the House is gated upkeep: %s" % JSON.stringify(head))
	var n := _load(s, "upkeep")
	var want := str(rep["afford_upkeep_living_fmt"]).format({"name": StateViews._building_name(n, rep, "house", 1),
		"rate": StateViews._fmt_rate(rep, n.town_sim.gold_income())})
	var ready: Array = n.view_away()["ready"]
	t.ok(ready.filter(func(l): return str(l["text"]) == want).size() == 1, "(c) the upkeep line names housing: %s" % JSON.stringify(ready))


func _tie(c: Dictionary) -> void:
	var s := _game(c)
	s.tick(s.substep_s())
	t.ok(s.town_sim.trade_starved == "", "(d) a new game's 10 living against 2 stalls, a tie: \"\" (living %.1f)" % s.town_sim.living)


func _timed(c: Dictionary) -> void:
	var s := _with_house(c)
	s.town_sim.living = 8.0
	s.town_sim.gold = 30.0
	s.town_sim.bone = 30.0
	t.ok(s.cmd_queue_build("", "lot-07")["ok"], "(setup) (f) the House's level 2 queued")
	s.tick(s.substep_s())
	var head: Dictionary = s.view_town()["queue"][0]
	t.ok(s.town_sim.trade_starved == "living_first" and str(head["status"]) == "waiting_funds" and str(head["reason"]) == "no_gold"
		and float(head["affordable_in_s"]) > 0.0, "(setup) (f) living_first, and the head is a timed wait on gold: %s" % JSON.stringify(head))
	t.ok(str(head["starved"]) == "" and str(head["lever"]) == "", "(f) a timed wait on gold reads starved \"\" and lever \"\" under living_first")
	# the bone side: a working mill makes bone, so a head short of bone only is a timed wait
	var b := _with_house(c)
	var mill_lot := str(BuildRules.free_lots(b, 1)[0])
	t.ok(b.town_sim.place_building(mill_lot, "bone_mill", 1), "(setup) (f) a Bone Mill on %s" % mill_lot)
	b.town_sim.gold = 500.0
	b.town_sim.bone = 0.0
	b.town_sim.bodies = 200.0
	t.ok(b.cmd_queue_build("", "lot-07")["ok"], "(setup) (f) the House's level 2 queued")
	for i in 4:
		b.tick(b.substep_s())
	b.town_sim.mill_starved = "pits_first"  # by hand: the rule is the row's, whatever the step left in the flag
	var bh: Dictionary = b.view_town()["queue"][0]
	t.ok(str(bh["status"]) == "waiting_funds" and str(bh["reason"]) == "no_bone" and float(bh["affordable_in_s"]) > 0.0,
		"(setup) (f) the head is a timed wait on bone: %s" % JSON.stringify(bh))
	t.ok(str(bh["starved"]) == "" and str(bh["lever"]) == "", "(f) a timed wait on bone reads starved \"\" and lever \"\" under pits_first")
	t.ok(b.cmd_demolish(mill_lot)["ok"], "(setup) (f) the mill demolished")
	b.tick(b.substep_s())
	b.town_sim.mill_starved = "pits_first"
	var nh: Dictionary = b.view_town()["queue"][0]
	t.ok(str(nh["reason"]) == "no_bone" and float(nh["affordable_in_s"]) == -1.0 and str(nh["starved"]) == "pits_first"
		and str(nh["lever"]) == "raise_war", "(f) with no mill the head is a never on bone and reads pits_first, raise_war: %s" % JSON.stringify(nh))


func _clone(c: Dictionary) -> void:
	var s := _with_house(c)
	s.town_sim.living = 1.0
	s.town_sim.gold = 30.0
	s.town_sim.bone = 30.0
	t.ok(s.cmd_queue_build("", "lot-07")["ok"], "(setup) (g) the House's level 2 queued")
	s.tick(s.substep_s())
	s.town_sim.mill_starved = "no_bodies"  # by hand, so both flags are non-empty
	var own: Dictionary = BuildRules.queue_walk(s, s.build_queue)["rows"][0]
	t.ok(s.town_sim.trade_starved == "living_first" and str(own["starved"]) == "living_first", "(setup) (g) the town reads living_first, and so does its head")
	var tw := s.town_sim.clone()
	t.ok(tw.trade_starved == "living_first" and tw.mill_starved == "no_bodies",
		"(g) the clone copies trade_starved and mill_starved: %s, %s" % [tw.trade_starved, tw.mill_starved])
	var live := s.town_sim
	s.town_sim = tw
	var row: Dictionary = BuildRules.queue_walk(s, s.build_queue)["rows"][0]
	s.town_sim = live
	t.ok(str(row["starved"]) == "living_first" and str(row["lever"]) == "raise_living" and float(row["affordable_in_s"]) == -1.0,
		"(g) a queue walk on the twin reads the head's living_first and raise_living: %s" % JSON.stringify(row))


## Saves `s` under `key` and loads it `away` s on in a fresh game with `s`'s configs (one catch-up, as _load).
func _load_at(s: GameState, key: String, away: int) -> GameState:
	s.drain_events()
	s.clock_override = CLOCK
	t.ok(s.cmd_save(key)["ok"], "(setup) (%s) saved" % key)
	var n := GameState.new(s._cfgs)
	n.debug_enabled = true
	n.save_dir = _dir
	n.clock_override = CLOCK + away
	t.ok(n.cmd_load(key)["ok"], "(setup) (%s) loaded %d s on" % [key, away])
	return n


func _upkeep_state(c0: Dictionary, rep: Dictionary) -> void:
	var c: Dictionary = c0.duplicate(true)
	c["economy"]["market"]["price"] = 0.3
	c["economy"]["idle"]["catchup_max_steps"] = 1
	var s := _game(c)
	t.ok(s.cmd_queue_build("house", "lot-07")["ok"], "(setup) (h) a new House queued")
	s.tick(s.substep_s())
	var tie := float(c["economy"]["opening"]["living"])  # 10 living buy what the start's 2 stalls sell
	t.ok(absf(tie * s.town_sim._shop_rate - s.town_sim._job("stall") * s.town_sim._stall_rate) < 1e-9,
		"(setup) (h) %.0f living tie the staffed stalls (%.2f)" % [tie, s.town_sim._job("stall")])
	# the step's growth at the tie, measured on a dry run of the same load
	s.town_sim.living = tie
	var dry := _load_at(s, "upkeep_dry", 10)
	var grow := dry.town_sim.living - tie
	t.ok(grow > 1e-6, "(setup) (h) the living grow %.5f over the 10 s step" % grow)
	s.town_sim.living = tie - grow / 2.0
	var n := _load_at(s, "upkeep_state", 10)
	t.ok(n.town_sim.trade_starved == "living_first" and n.town_sim.trade_bound() == "",
		"(setup) (h) the last step's flag reads living_first, the state at its end \"\" (living %.5f -> %.5f)" % [tie - grow / 2.0, n.town_sim.living])
	var head: Dictionary = n.view_town()["queue"][0]
	t.ok(str(head["status"]) == "skipped_gate" and str(head["reason"]) == "upkeep", "(setup) (h) the House is gated upkeep: %s" % JSON.stringify(head))
	var fill := {"name": StateViews._building_name(n, rep, "house", 1), "rate": StateViews._fmt_rate(rep, n.town_sim.gold_income())}
	var ready: Array = n.view_away()["ready"]
	t.ok(ready.filter(func(l): return str(l["text"]) == str(rep["afford_upkeep_fmt"]).format(fill)).size() == 1
		and not ready.any(func(l): return str(l["text"]) == str(rep["afford_upkeep_living_fmt"]).format(fill)),
		"(h) the upkeep line reads the state's bind, afford_upkeep_fmt's: %s" % JSON.stringify(ready))


func _cleanup() -> void:
	var d := DirAccess.open(_dir)
	if d == null:
		return
	for f in d.get_files():
		d.remove(f)
	DirAccess.remove_absolute(_dir)
