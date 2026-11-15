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
	_cleanup()
	return t.failures


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
func _queue(c: Dictionary, key: String, what: String, ids: Array) -> void:
	var s := GameState.new(c)
	s.debug_enabled = true
	s.save_dir = _dir
	t.ok(s.cmd_debug_load_fixture("day1")["ok"], "(setup) day1 loads")
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
	t.ok(missed.is_empty() and n.build_queue.is_empty() and (at.values().all(func(v): return float(v) <= float(AWAY_S))),
		"(%s) %s, %s: every entry starts within 8 h%s" % [key, what, ", ".join(PackedStringArray(ids)),
		"" if missed.is_empty() else ": never started " + str(missed) + ", the queue " + str(left)])


func _cleanup() -> void:
	var d := DirAccess.open(_dir)
	if d == null:
		return
	for f in d.get_files():
		d.remove(f)
	DirAccess.remove_absolute(_dir)
