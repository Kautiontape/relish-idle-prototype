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
	_cleanup()
	return t.failures


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


func _cleanup() -> void:
	var d := DirAccess.open(_dir)
	if d == null:
		return
	for f in d.get_files():
		d.remove(f)
	DirAccess.remove_absolute(_dir)
