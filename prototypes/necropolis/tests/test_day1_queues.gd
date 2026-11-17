extends RefCounted
## day1's first queues all start within 8 h (F1; the run's manager for Shawn: the Bone Mill's level 1 is priced
## in gold only, BALANCE §7's "the Bone Mill's level 1 stays gold-priced", so day1's first queue never deadlocks
## on bone). Each queue is queued all at once on day1 a step in, saved, and loaded 8 h later, so the catch-up
## runner plays the 8 h (test_away's away path), and every entry must have started: a queue_started event for its
## lot among the catch-up's events, and the queue empty at the end.
## - (a) House, Well, Bakery, Bone Mill: the E2b-2 vision review's first overnight, and R2's deadlock case (at
##   60 gold and 20 bone the Mill's bone was the last of day1's 30 once the other three had theirs, and only a
##   mill makes bone, so it waited at −1.0 for ever).
## - (b) town's trial order: Bone Mill, House, House, Well, Well, Bakery, Well, Well, the first queue.max_len new
##   builds of reports/town/g3-trial-a2.tsv (B2 and g4-trial-c.tsv start with the same eight).
## - Lots: each entry on the smallest free lot that fits it (lot size, then lot order), as the trial's autoplayer
##   placed them (BuildSort.nearest_lot: size first). Its tie-break among lots of one size is the street distance
##   from the crypt; here it moves no gate, since the size-1 lots lot-05 to lot-08 all open at Hamlet and lot-09
##   to lot-12 all at Village, so lot order stands in for it. A queued entry may take a locked lot (lot_locked
##   until the tier opens it), as (b)'s last four do.
## Prints each entry's start, in seconds after the save. The field is shrunk (8 × 6) and its pre-warm off, as
## tests/test_away.gd does.
## - The start state (E4, the A1 day-1 ruling): day1 is a new game saved at an older start valve, and a fixture
##   keeps its saved valve, so (a) and (b) set the current one, economy.json opening.valve, with no slew: F1's
##   promise is about a player who just queues at the default. Never a test-side valve.
## - The bone edge (same ruling): under A1 the muster goes to Vei, and below a WAR share of opening.bone_edge.war_share
##   the pits eat every body and the mill makes none (a growth feedback, measured, no closed form). From a new game
##   with FLOOD at the opening's: (b) at the edge less 0.02 waits for ever on bone, and the views and the away report
##   say why (the head's `short`, `starved` pits_first and lever raise_war, the mill's too, afford_starved's line); at
##   the edge plus 0.02 every entry starts. The start valve keeps WAR above the edge.

var t := TestUtil.new()
var _dir := "user://test_day1_queues_%d" % OS.get_process_id()
const CLOCK := 1_800_000_000  # a "now" for the saves (unix seconds)
const AWAY_S := 28800  # 8 h
const QUEUE_A := ["house", "well", "bakery", "bone_mill"]
const QUEUE_B := ["bone_mill", "house", "house", "well", "well", "bakery", "well", "well"]


func run() -> int:
	t.suite("day1_queues")
	DirAccess.make_dir_recursive_absolute(_dir)
	var c: Dictionary = load("res://tests/test_away.gd").cfgs()
	t.ok(QUEUE_B.size() == int(c["economy"]["queue"]["max_len"]), "(setup) (b) is queue.max_len entries long")
	_queue(c, "a", "the review's first overnight", QUEUE_A)
	_queue(c, "b", "the trial's first eight", QUEUE_B)
	_edge(c)
	_cleanup()
	return t.failures


## The bone edge's bracket and its readouts (the header's last item).
func _edge(c: Dictionary) -> void:
	var open: Dictionary = c["economy"]["opening"]
	var edge := float(open["bone_edge"]["war_share"])
	t.ok(float(open["valve"]["war"]) >= edge + 0.05, "the start valve's WAR %.2f keeps 0.05 over the bone edge %.2f" % [float(open["valve"]["war"]), edge])
	var lo: Array = _queue(c, "lo", "a new game at WAR %.2f" % (edge - 0.02), QUEUE_B, edge - 0.02, false)
	var n: GameState = lo[0]
	t.ok(not (lo[1] as Array).is_empty(), "(lo) below the edge (b) waits on bone for ever: never started %s" % str(lo[1]))
	t.near(float(n.view_hud()["bone_war_share"]), edge, 0.0, "view_hud.bone_war_share is opening.bone_edge.war_share")
	var head: Dictionary = n.view_town()["queue"][0]
	var short: Dictionary = head["short"]
	t.ok(str(head["reason"]) == "no_bone" and float(head["affordable_in_s"]) == -1.0 and float(short["bone"]) > 0.0
		and float(short["bone"]) <= float(head["cost"]["bone"]) and float(short["gold"]) == 0.0,
		"(lo) the head waits never on bone and names the bone it is short of: %s" % JSON.stringify(head))
	t.ok(str(head["starved"]) == "pits_first" and str(head["lever"]) == "raise_war",
		"(lo) the head reads the mills' reason pits_first and the lever raise_war")
	var mills: Array = (n.view_town()["buildings"] as Array).filter(func(b): return n.town_sim.lot_mill_slots(str(b["lot_id"])) > 0)
	t.ok(not mills.is_empty() and mills.all(func(b): return str(b["starved"]) == "pits_first" and str(b["lever"]) == "raise_war"),
		"(lo) the mill reads starved pits_first and the lever raise_war")
	var rep: Dictionary = c["economy"]["idle"]["report"]
	var fill := {"name": StateViews._building_name(n, rep, str(head["building_id"]), int(head["level"])),
		"short": StateViews._fmt_count(rep, ceilf(float(short["bone"]))), "rate": StateViews._fmt_rate(rep, float(BuildRules.queue_net(n)["bone"]))}
	var want := [str(rep["afford_starved_fmt"]).format(fill), str(rep["afford_starved_last_fmt"]).format(fill)]
	var lines: Array = (n.view_away()["ready"] as Array).filter(func(l): return want.has(str(l["text"])) and str(l["kind"]) == "queue")
	t.ok(lines.size() == 1, "(lo) the away report's head line says the same, afford_starved's words: %s" % JSON.stringify(n.view_away()["ready"]))
	var hi: Array = _queue(c, "hi", "a new game at WAR %.2f" % (edge + 0.02), QUEUE_B, edge + 0.02, false)
	t.ok((hi[1] as Array).is_empty(), "(hi) above the edge every entry of (b) starts")


## The smallest free lot that fits `building_id` (lot size, then lot order): not built on and not taken by an entry
## queued before it; a locked lot is allowed.
static func _lot(c: Dictionary, s: GameState, building_id: String, taken: Dictionary) -> String:
	var need := int(c["buildings"][building_id]["lot_size"])
	var best := ""
	var best_size := 0
	for l in c["town"]["lots"]:
		var id := str(l["id"])
		var size := int(l.get("size", 1))
		if size >= need and not s.town_sim.buildings.has(id) and not taken.has(id) and (best == "" or size < best_size):
			best = id
			best_size = size
	return best


## day1 a step in with every one of `ids` queued at once, each on its smallest free lot; saved, then loaded 8 h on:
## every entry starts, each start printed.
## Queues `ids` a step into day1 at the start valve (or, given `war` ≥ 0, into a new game at that WAR share, FLOOD
## at the opening's and WORK the rest), saves, loads 8 h on and, for day1, checks every entry started. Returns
## [the loaded GameState, the entries that never started].
func _queue(c: Dictionary, key: String, what: String, ids: Array, war := -1.0, fixture := true) -> Array:
	var s := GameState.new(c)
	s.debug_enabled = true
	s.save_dir = _dir
	if fixture:
		t.ok(s.cmd_debug_load_fixture("day1")["ok"], "(setup) day1 loads")
	else:
		s.cmd_new_game(1)
	var v: Dictionary = c["economy"]["opening"]["valve"]
	var w := float(v["war"]) if war < 0.0 else war
	var r0 := s.cmd_set_valve(1.0 - float(v["flood"]) - w, w, float(v["flood"]))
	s.valve = s.valve_target.duplicate()  # no slew: the start state
	t.ok(r0["ok"] and is_equal_approx(float(s.valve["war"]), w), "(setup) (%s) the valve at WAR %.2f: %s" % [key, w, JSON.stringify(s.valve)])
	s.tick(s.substep_s())  # a step's rates (a fixture loads with none)
	var taken := {}
	var plan: Array = []
	var queued: Array = []
	for id in ids:
		var lot := _lot(c, s, id, taken)
		taken[lot] = true
		var r := s.cmd_queue_build(id, lot)
		t.ok(r["ok"], "(setup) (%s) %s queued on %s" % [key, id, lot])
		plan.append([id, lot])
	for row in s.view_town()["queue"]:
		queued.append("%s %s %s %.1f" % [row["building_id"], row["lot_id"], row["status"], float(row["affordable_in_s"])])
	print("  [day1_queues] (%s) at queue time: %s" % [key, str(queued)])
	s.drain_events()
	var t0 := s.t
	s.clock_override = CLOCK
	t.ok(s.cmd_save("q_" + key)["ok"], "(setup) (%s) saved" % key)
	var n := GameState.new(c)
	n.debug_enabled = true
	n.save_dir = _dir
	n.clock_override = CLOCK + AWAY_S
	var r := n.cmd_load("q_" + key)
	t.ok(r["ok"] and float(r["away_s"]) == float(AWAY_S), "(setup) (%s) loaded 8 h on, caught up: %s" % [key, str(r)])
	var at := {}
	for e in n.catchup_events():
		if e["type"] == "queue_started" and not at.has(str(e["lot_id"])):
			at[str(e["lot_id"])] = float(e["t"]) - t0
	var starts: Array = []
	var missed: Array = []
	for p in plan:
		if at.has(p[1]):
			starts.append("%s %s +%.1f s" % [p[0], p[1], float(at[p[1]])])
		else:
			missed.append("%s %s" % [p[0], p[1]])
	var left: Array = n.view_town()["queue"].map(func(row): return "%s %s %s %s %.1f" % [row["building_id"], row["lot_id"], row["status"],
		row["reason"], float(row["affordable_in_s"])])
	print("  [day1_queues] (%s) starts: %s; still queued: %s" % [key, str(starts), str(left)])
	if fixture:
		t.ok(missed.is_empty() and n.build_queue.is_empty() and (at.values().all(func(x): return float(x) <= float(AWAY_S))),
			"(%s) %s, %s: every entry starts within 8 h%s" % [key, what, ", ".join(PackedStringArray(ids)),
			"" if missed.is_empty() else ": never started " + str(missed) + ", the queue " + str(left)])
	return [n, missed]


func _cleanup() -> void:
	var d := DirAccess.open(_dir)
	if d == null:
		return
	for f in d.get_files():
		d.remove(f)
	DirAccess.remove_absolute(_dir)
