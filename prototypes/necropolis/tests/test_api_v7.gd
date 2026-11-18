extends RefCounted
## STATE-API v7's R2 additions (STATE-API §1.1; R1's `unpaid` kind is in test_api_contract.gd): the build queue's
## `affordable_in_s` on every view_town().queue entry (§5.9) and as cmd_queue_build's extra (§4.3), and the away
## report's two new ready lines in the line contract with the kinds and targets it had (§5.19). Headless, no
## autoloads.

var t: TestUtil
var _dir := "user://test_saves_api_v7_%d" % OS.get_process_id()
## Builds and upgrades that fill a fixture's queue to queue.max_len (each tried in order; refusals skipped).
const FILL := [["", "lot-02"], ["", "lot-04"], ["", "lot-04"], ["house", "lot-05"], ["well", "lot-06"], ["bakery", "lot-07"],
	["bone_mill", "lot-08"], ["house", "lot-09"], ["well", "lot-10"], ["house", "lot-11"], ["well", "lot-12"], ["", "lot-03"],
	["", "lot-03"], ["house", "lot-18"], ["well", "lot-19"], ["house", "lot-20"], ["", "lot-05"], ["", "lot-06"], ["", "lot-07"],
	["", "lot-08"], ["well", "lot-21"]]  # (Phase I P3's depth: the Market's and the charnel house's L3 are over pre_vei's cap)


func run() -> int:
	t = TestUtil.new()
	t.suite("api-v7")
	_version()
	_queue_rows()
	_queue_extra()
	_queue_extra_catching_up()
	_away_lines()
	return t.failures


func _fixture(name: String) -> GameState:
	var s := GameState.new(TestUtil.configs())
	s.debug_enabled = true
	t.ok(s.cmd_debug_load_fixture(name)["ok"], "(setup) %s loads" % name)
	return s


func _version() -> void:
	t.ok(GameState.API_VERSION == 14, "API_VERSION is 14: R2's additions joined R1's v7 entry (one milestone); E3's v8 entry follows (E3-1's save keys), then E4's v9 (the husk craft), v10 (the craft's at_cap), v11 (step 5: the muster's route and the hold forecast), v12 (step 9: the win odds and view_vei.strain), Phase I's v13 (P2: view_town's queue_slots and queue_list_max) and v14 (P3: wait_slot, the never head's skip, #19's lots, #20's revived_in_place, the odds split; STATE-API §1.1)")


## Every view_town().queue entry carries affordable_in_s, a float (the queue row's schema, ApiSchema.QUEUE_ENTRY):
## 0.0, a positive number of seconds, or exactly −1.0. Each fixture a step in with a full queue.
func _queue_rows() -> void:
	for fx in GameState.FIXTURES:
		var s := _fixture(fx)
		s.tick(s.substep_s())
		for p in FILL:
			if s.build_queue.size() < BuildRules.queue_max(s):
				s.cmd_queue_build(p[0], p[1])
		var rows: Array = s.view_town()["queue"]
		var errs: Array = []
		var odd: Array = []
		for i in rows.size():
			ApiSchema.check(rows[i], ApiSchema.QUEUE_ENTRY, "view_town.queue[%d]" % i, errs)
			var a: Variant = rows[i].get("affordable_in_s")
			if not (a is float and (a == -1.0 or a >= 0.0)):
				odd.append(str(a))
		t.ok(rows.size() == BuildRules.queue_max(s) and errs.is_empty() and odd.is_empty(),
			"v7: %s's %d queue entries each carry affordable_in_s, a float, 0.0, > 0 or −1.0 %s %s" % [fx, rows.size(), str(errs), str(odd)])


## cmd_queue_build's affordable_in_s: a float on every return, the new entry's row (the view's) on success, −1.0 on
## a refusal (no entry), next to the command's other extras.
func _queue_extra() -> void:
	var s := _fixture("day1")
	s.tick(s.substep_s())
	var bad: Array = []
	for p in [["house", "lot-05"], ["bakery", "lot-06"], ["bone_mill", "lot-07"], ["", "lot-01"]]:
		var r := s.cmd_queue_build(p[0], p[1])
		var errs: Array = []
		ApiSchema.check_command("cmd_queue_build", r, errs)
		var row: Dictionary = s.view_town()["queue"].back()
		if not (errs.is_empty() and r["ok"] and r.get("affordable_in_s") is float and r["affordable_in_s"] == row["affordable_in_s"]):
			bad.append("%s: %s %s" % [str(p), str(r), str(errs)])
	t.ok(bad.is_empty(), "v7: cmd_queue_build's affordable_in_s is a float, the new entry's view row's%s" % ("" if bad.is_empty() else ": " + str(bad)))
	var refused: Array = []
	for p in [["nope", "lot-08"], ["house", "lot-99"], ["house", "lot-02"], ["reliquary", "lot-23"]]:
		var r := s.cmd_queue_build(p[0], p[1])
		if r["ok"] or not (r.get("affordable_in_s") is float) or r["affordable_in_s"] != -1.0:
			refused.append(str(r))
	t.ok(refused.is_empty(), "v7: a refused cmd_queue_build carries affordable_in_s −1.0 (unknown_building, unknown_lot, lot_taken, cost_exceeds_cap)%s" % (
		"" if refused.is_empty() else ": " + str(refused)))


## During a chunked load's catch-up cmd_queue_build refuses with catching_up, its extras zero-valued: affordable_in_s
## −1.0 with them.
func _queue_extra_catching_up() -> void:
	DirAccess.make_dir_recursive_absolute(_dir)
	var s := _fixture("day1")
	s.save_dir = _dir
	s.clock_override = 1_800_000_000
	t.ok(s.cmd_save("cu")["ok"], "(setup) saved")
	var n := GameState.new(TestUtil.configs())
	n.debug_enabled = true
	n.save_dir = _dir
	n.clock_override = 1_800_000_000 + 3600
	t.ok(n.cmd_load("cu", true)["ok"] and n.catching_up(), "(setup) a chunked load, its catch-up pending")
	var r := n.cmd_queue_build("house", "lot-05")
	t.ok(r == {"ok": false, "reason": "catching_up", "index": -1, "cap_building": "", "store": "", "cap_level": -1, "affordable_in_s": -1.0},
		"v7: cmd_queue_build while catching up: catching_up, affordable_in_s −1.0 with the other extras: %s" % str(r))
	var dd := DirAccess.open(_dir)
	if dd != null:
		for f in dd.get_files():
			dd.remove(f)
		DirAccess.remove_absolute(_dir)


## The away report's R2 lines keep view_away's line contract with kinds and targets it already had: the queue's head
## still waiting (kind "queue", target "queue") and the raid prompt (kind "raid", target "": a raid with no fort).
## day1 with no bone and no mill, a House the head at −1.0 (F1: day1's own Bone Mill no longer waits at −1.0, its
## level 1 costs no bone), and day1 with gold and bone at their caps and nothing queued, each saved and loaded 1 min
## on.
func _away_lines() -> void:
	DirAccess.make_dir_recursive_absolute(_dir)
	var m := _fixture("day1")
	m.tick(m.substep_s())
	m.town_sim.bone = 0.0
	m.cmd_queue_build("house", "lot-05")
	m.tick(m.substep_s())
	var f := _fixture("day1")
	f.tick(f.substep_s())
	f.town_sim.gold = f.town_sim.gold_cap()
	f.town_sim.bone = f.town_sim.bone_cap()
	var lines: Array = []
	for pair in [["mill", m], ["full", f]]:
		var g: GameState = pair[1]
		g.save_dir = _dir
		g.clock_override = 1_800_000_000
		g.cmd_save(pair[0])
		var n := GameState.new(TestUtil.configs())
		n.debug_enabled = true
		n.save_dir = _dir
		n.clock_override = 1_800_000_000 + 60
		n.cmd_load(pair[0])
		lines.append_array(n.view_away()["ready"])
	var mine := lines.filter(func(l): return (l["kind"] == "queue" and str(l["text"]).contains("afforded")) or (l["kind"] == "raid" and l["target"] == ""))
	var errs: Array = []
	for l in mine:
		ApiSchema.check(l, ApiSchema.AWAY_LINE, "view_away.ready[]", errs)
	t.ok(mine.size() == 2 and errs.is_empty() and mine.all(func(l): return ApiSchema.AWAY_KINDS.has(l["kind"]) and l["target"] in ["queue", ""])
		and mine[0]["target"] == "queue" and mine[1]["kind"] == "raid",
		"v7: the queue head's line (queue, \"queue\") and the raid prompt (raid, \"\") match the line contract, kinds and targets it had: %s %s" % [
		str(mine), str(errs)])
	var dd := DirAccess.open(_dir)
	if dd != null:
		for fl in dd.get_files():
			dd.remove(fl)
		DirAccess.remove_absolute(_dir)
