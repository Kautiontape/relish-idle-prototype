extends RefCounted
## STATE-API v5 additions (economy E2b-2): view_staffing_projection (api-request #16, §5.16), TownSim's
## own staffing allocation run with another job order and an optional vat override. Headless, no
## autoloads.

var t: TestUtil
var _dir := "user://test_saves_api_v5_%d" % OS.get_process_id()


func _mk(seed_val := 1) -> GameState:
	var s := GameState.new(TestUtil.configs())
	s.cmd_new_game(seed_val)
	s.debug_enabled = true
	s.save_dir = _dir
	return s


func _fixture(name: String) -> GameState:
	var s := _mk()
	t.ok(s.cmd_debug_load_fixture(name)["ok"], "%s loads" % name)
	return s


func run() -> int:
	t = TestUtil.new()
	_same_as_view_town()
	_permuted()
	_pure()
	_refusals()
	_vat_override()
	_cleanup()
	return t.failures


## The projection's {jobs, buildings} next to view_town's: equal when the staffing is the same.
func _town_rows(s: GameState) -> Dictionary:
	var v := s.view_town()
	var b: Array = []
	for e in v["buildings"]:
		b.append({"lot_id": e["lot_id"], "staffed": e["staffed"]})
	return {"jobs": v["jobs"], "buildings": b, "idle": v["workers"]["idle"]}


func _proj_rows(p: Dictionary) -> Dictionary:
	return {"jobs": p["jobs"], "buildings": p["buildings"], "idle": p["idle"]}


## Fewer workers than slots and a staff cap, so the order decides who is staffed.
func _short(s: GameState) -> void:
	var slots := float(s.town_sim.staffing["slots"])
	t.ok(s.cmd_debug_grant({"workers": slots * 0.6 - s.town_sim.workers})["ok"], "workers cut to 60% of the slots")


func _same_as_view_town() -> void:
	t.suite("api-v5-projection-ladder")
	for name in GameState.FIXTURES:
		var s := _fixture(name)
		for phase in ["loaded", "short", "ticked"]:
			if phase == "short":
				_short(s)
			elif phase == "ticked":
				s.tick(120.0)
			var order := s.town_sim.effective_ladder(s.town_sim.ladder)
			var p := s.view_staffing_projection(order)
			t.ok(p["reason"] == "" and p["rev"] == s.rev, "%s (%s): ok, at today's rev" % [name, phase])
			t.ok(_proj_rows(p) == _town_rows(s), "%s (%s): with today's effective ladder the projection is view_town's jobs, per-lot staffed and idle exactly: %s vs %s" % [
				name, phase, str(_proj_rows(p)), str(_town_rows(s))])
			t.ok(s.view_staffing_projection(order, {}) == p, "%s (%s): vats {} is the default" % [name, phase])


## A fixture loaded, its workers cut and a staff cap of 1 on its first lot with 2 slots or more. Run
## twice it gives two bit-identical games: the projection runs on one, the command on the other (a
## save's round trip would round the workers the grant left to the save's 15 digits).
func _prepared(name: String) -> GameState:
	var s := _fixture(name)
	_short(s)
	var lot := ""
	for e in s.view_town()["buildings"]:
		if int(e["slots"]) >= 2 and lot == "":
			lot = e["lot_id"]
	t.ok(lot != "" and s.cmd_set_staff_cap(lot, 1)["ok"], "%s: a staff cap of 1 on %s" % [name, lot])
	return s


func _permuted() -> void:
	t.suite("api-v5-projection-permuted")
	var orders := [
		["tend", "forge", "mill", "stall", "pit", "haul", "build"],
		["stall", "mill", "pit", "haul", "build", "forge", "tend"],
		["pit", "stall", "haul", "mill", "build", "tend", "forge"],
	]
	var moved := 0
	for name in GameState.FIXTURES:
		var s := _prepared(name)
		var before := _town_rows(s)
		for order in orders:
			var p := s.view_staffing_projection(order)
			var c := _prepared(name)
			t.ok(_town_rows(c) == before, "%s: the copy staffs as the original" % name)
			t.ok(c.cmd_set_job_priority(order)["ok"], "%s: the copy takes %s" % [name, str(order)])
			t.ok(p["reason"] == "" and _proj_rows(p) == _town_rows(c),
				"%s, %s: the projection is what view_town shows after cmd_set_job_priority on a copy: %s vs %s" % [
				name, str(order), str(_proj_rows(p)), str(_town_rows(c))])
			if _proj_rows(p)["jobs"] != before["jobs"]:
				moved += 1
	t.ok(moved >= 6, "the orders change who is staffed in most cases (%d of 9), so the comparison means something" % moved)


func _pure() -> void:
	t.suite("api-v5-projection-pure")
	for name in GameState.FIXTURES:
		var s := _fixture(name)
		_short(s)
		var rv := s.rev
		var town := s.view_town()
		var dump := JSON.stringify(s.to_dict())
		var evs := s.drain_events().size()
		s.view_staffing_projection(["tend", "forge", "mill", "stall", "pit", "haul", "build"])
		s.view_staffing_projection(s.town_sim.ladder, {0: true, 1: false, 7: true})
		s.view_staffing_projection(["nope"])
		var p := s.view_staffing_projection(s.town_sim.ladder)
		p["jobs"].append({"id": "x"})
		t.ok(s.rev == rv, "%s: rev is unchanged" % name)
		t.ok(s.view_town() == town, "%s: view_town is unchanged" % name)
		t.ok(JSON.stringify(s.to_dict()) == dump, "%s: the save dump is unchanged" % name)
		t.ok(s.drain_events().size() == 0 and evs >= 0, "%s: no events" % name)
		t.ok(s.view_staffing_projection(s.town_sim.ladder)["jobs"].size() == town["jobs"].size(), "%s: a fresh deep copy each call" % name)


func _refusals() -> void:
	t.suite("api-v5-projection-refusals")
	var s := _fixture("midgame_2flips")
	var rv := s.rev
	var cases := [
		[["haul", "mill", "stall", "forge", "pit", "tend", "dig"], "unknown_job"],
		[["haul", "mill", "stall", "forge", "pit", "tend", 3], "unknown_job"],
		[["haul", "mill", "stall", "forge", "pit", "tend", "build", "haul"], "duplicate_job"],
		[["haul", "mill", "stall", "forge", "pit", "tend"], "missing_job"],
		[[], "missing_job"],
	]
	for c in cases:
		var p := s.view_staffing_projection(c[0])
		var cmd := s.cmd_set_job_priority(c[0])
		t.ok(p == {"rev": rv, "jobs": [], "buildings": [], "idle": 0.0, "reason": c[1]} and cmd["reason"] == c[1],
			"%s: refused with %s, as cmd_set_job_priority is (%s), with empty jobs and buildings" % [str(c[0]), c[1], str(p)])
	t.ok(s.rev == rv, "refusals change nothing")
	var sn := s.view_staffing_projection([&"haul", &"mill", &"stall", &"forge", &"pit", &"tend", &"build"])
	t.ok(sn["reason"] == "" and sn["jobs"][0]["id"] is String, "StringName ids are accepted, as the command accepts them")


## pre_vei with the tend job above the stall and three workers, the vats as `staffed` (cmd_staff_vat).
func _vat_game(staffed: Dictionary) -> GameState:
	var s := _fixture("pre_vei")
	s.cmd_set_job_priority(["tend", "stall", "pit", "haul", "build", "mill", "forge"])
	t.ok(s.cmd_debug_grant({"workers": 3.0 - s.town_sim.workers})["ok"], "three workers")
	for slot in staffed:
		t.ok(s.cmd_staff_vat(slot, staffed[slot])["ok"], "vat %d staffed: %s" % [slot, str(staffed[slot])])
	return s


## `vats` opens and closes the tend slots cmd_staff_vat would: the projection with an override is what
## view_town shows after those cmd_staff_vat calls on a twin. A hand moves between the tend slot and
## the stall below it.
func _vat_override() -> void:
	t.suite("api-v5-projection-vats")
	var s := _vat_game({})
	var order := s.town_sim.ladder
	var base := s.view_staffing_projection(order)
	t.ok(_proj_rows(base) == _town_rows(s) and base["jobs"][0]["id"] == "stall", "no vat staffed: no tend slot, the stall first")
	var rv := s.rev
	for v in [{0: true}, {1: true}, {0: true, 1: true}, {0: false}, {9: true}]:
		var p := s.view_staffing_projection(order, v)
		var c := _vat_game({})
		for slot in v:
			if slot < 2:
				c.cmd_staff_vat(slot, v[slot])
		t.ok(_proj_rows(p) == _town_rows(c), "vats %s: the projection is view_town after cmd_staff_vat on a twin: %s vs %s" % [
			str(v), str(_proj_rows(p)), str(_town_rows(c))])
	var one := s.view_staffing_projection(order, {0: true})
	t.ok(one["jobs"][0] == {"id": "tend", "slots": 1, "staffed": 1.0} and one["jobs"][1]["staffed"] == base["jobs"][0]["staffed"] - 1.0,
		"one vat staffed: the tend slot takes one hand from the stall")
	t.ok(s.rev == rv and _town_rows(s)["jobs"] == base["jobs"] and not s.vats_staffed.has(true) and s.town_sim.vats_on() == [], "the overrides changed nothing")
	var on := _vat_game({0: true})
	var off := on.view_staffing_projection(order, {0: false})
	t.ok(_proj_rows(off) == _proj_rows(base), "a staffed vat overridden off gives its hand back, as unstaffing it would")


func _cleanup() -> void:
	var d := DirAccess.open(_dir)
	if d != null:
		for f in d.get_files():
			d.remove(f)
		DirAccess.remove_absolute(_dir)
