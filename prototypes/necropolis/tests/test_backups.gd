extends RefCounted
## E3-2, the backups (MECHANICS §7; STATE-API §3 step 6, §5.13, §9.1). Clones grow in tended vats:
## - a vat grows at backups.json vats.grow_per_s × its tend hands (0..1) in the core step's backups step, only while
##   it is staffed and tended; full tending fills it in (1 − grow) / grow_per_s; partial tending, and the hands of one
##   Chapel shared over its staffed vats the lowest slot first (TownSim.vat_hands);
## - unstaffing stops the growth and keeps the progress; an unpaid Chapel offers no tend slot, so it stops too;
## - Vigil (Relish away) lifts tend to the top of the ladder, and a vat the ladder left untended grows;
## - clones_ready is the vats at 1 plus the spare clones; a death spends the lowest ready vat (back to 0), then a spare;
## - a save -> load round trip keeps every vat's grow and the spare clones; the old-save rule (a save's clones_ready
##   above its vats at 1 is kept as spare clones, one below them reads the vats); a demolished Chapel's ready clone is
##   kept as a spare;
## - catch-up: a tended pre_vei vat fills at the same time caught up as live, within one catch-up step; with no vat
##   tended a 12 h catch-up from each fixture is bit-identical to the tip's (TIP).

var t := TestUtil.new()
var _dir := "user://test_backups_%d" % OS.get_process_id()
const CLOCK := 1_800_000_000  # a "now" for the saves (unix seconds)
## The tip's 12 h catch-ups (646f288, E3-1, before the vats grew): each fixture saved and loaded 12 h on, with
## test_stances' harness configs (the field shrunk). identity() hashes the whole state (to_dict()), every event the
## catch-up collected and its away report.
const TIP := {
	"day1": {"state": "4ba81b807dbcb7691e4930b9d72b641c1b1fbc5f3d5a238c57a5fd2905f8ffe2",
		"events": "7adf8ca1cc296dda1400a30dc17e06fe586208e878f465b1cb8eed498c982412",
		"away": "977a359676d37ffbebe0472847672d4adc73cc50b00708cec3a4ce95d8918f6f", "steps": 4320, "n_events": 3},
	"midgame_2flips": {"state": "634bb07f5f66a8ede8f2ee2037f0dc130335cd3f24a1f67651c9bf5c3b99e130",
		"events": "0bc1a1375468f3e5deabd304cb9130fa6581a8bcbd978863e16c0b8448099416",
		"away": "05cda66f6b8dc51f18e6f50d5ed95c56a79d1a54c6b23f8770aff26a0f19d05e", "steps": 4422, "n_events": 367},
	"pre_vei": {"state": "3983ed76900e24729627fce8fae16be54c74579c6fe702bb45d69bff67e3fdb6",
		"events": "794d7e0224d331e98c2019bfe0b5d175b34798a7420c5d42e015f585f2182d39",
		"away": "47c37eeb42384917945ace19104f947301da6faf9c612df41baa3cfc32d5de35", "steps": 4321, "n_events": 16},
}


func run() -> int:
	t.suite("backups")
	DirAccess.make_dir_recursive_absolute(_dir)
	_tended_only()
	_fill_time()
	_partial()
	_unstaff_keeps()
	_unpaid_stops()
	_vigil()
	_spend_order()
	_round_trip()
	_old_save()
	_demolish()
	_catchup_fill()
	_identity()
	_cleanup()
	return t.failures


func _cleanup() -> void:
	var d := DirAccess.open(_dir)
	if d == null:
		return
	for f in d.get_files():
		d.remove(f)
	DirAccess.remove_absolute(_dir)


func _mk() -> GameState:
	var s := GameState.new(TestUtil.configs())
	s.cmd_new_game(1)
	s.debug_enabled = true
	return s


## day1 with a level-1 Chapel of Vats on lot-13: two vats, unstaffed, empty.
func _chapel() -> GameState:
	var s := _mk()
	s.town_sim.place_building("lot-13", "chapel_of_vats", 1)
	return s


func _fixture(name: String, c := {}) -> GameState:
	var s := GameState.new(TestUtil.configs() if c.is_empty() else c)
	s.debug_enabled = true
	s.save_dir = _dir
	t.ok(s.cmd_debug_load_fixture(name)["ok"], "(setup) %s loads" % name)
	return s


func _grow(s: GameState, slot: int) -> float:
	return float(s.view_backups()["vats"][slot]["grow"])


func _rate(s: GameState) -> float:
	return float(s._cfgs["backups"]["vats"]["grow_per_s"])


func _tend(s: GameState) -> Dictionary:
	for j in s.view_town()["jobs"]:
		if j["id"] == "tend":
			return j
	return {"id": "tend", "slots": 0, "staffed": 0.0}


## `x` through JSON, as a file holds it (its ints read back as floats), to compare with a parsed fixture.
static func _j(x: Variant) -> Variant:
	return JSON.parse_string(JSON.stringify(x))


func _outcomes(s: GameState) -> Array:
	return s.drain_events().filter(func(e): return e["type"] == "relish_died").map(func(e): return e["outcome"])


# ----------------------------------------------------------------- growth ----
## A vat grows only while it is staffed and tended: unstaffed, nothing; staffed with a hand (day1's 12 workers on 8
## slots leave idle hands), vats.grow_per_s per second; staffed but with no hand (2 workers, tend at the bottom of the
## ladder), nothing.
func _tended_only() -> void:
	var s := _chapel()
	var r := _rate(s)
	s.tick(10.0)
	t.ok(_grow(s, 0) == 0.0 and _grow(s, 1) == 0.0, "unstaffed vats don't grow (10 s)")
	t.ok(s.cmd_staff_vat(0, true)["ok"] and int(_tend(s)["slots"]) == 1 and float(_tend(s)["staffed"]) == 1.0,
		"(setup) vat 0 staffed: its tend slot opens and an idle hand takes it")
	s.tick(10.0)
	t.near(_grow(s, 0), 10.0 * r, 1e-12, "vat 0 staffed and tended: it grows at vats.grow_per_s for 10 s")
	t.ok(_grow(s, 1) == 0.0 and s.view_backups()["clones_ready"] == 0, "vat 1, unstaffed, stays empty; nothing is ready yet")
	var u := _chapel()
	u.cmd_staff_vat(0, true)
	u.town_sim.workers = 2.0
	u.town_sim.restaff()
	u.tick(10.0)
	t.ok(int(_tend(u)["slots"]) == 1 and float(_tend(u)["staffed"]) == 0.0 and _grow(u, 0) == 0.0,
		"staffed but untended (2 workers, tend at the ladder's bottom: %s): it doesn't grow" % str(_tend(u)))


## Fully tended from grow 0.5, the vat is ready after (1 − 0.5) / vats.grow_per_s, within one substep, and then holds
## a ready clone: clones_ready 1, the vat at exactly 1 (it clamps), and a death would wake her from it.
func _fill_time() -> void:
	var s := _chapel()
	s.cmd_staff_vat(0, true)
	s.vats_grow = [0.5]
	var r := _rate(s)
	var want := (1.0 - 0.5) / r
	var t0 := s.t
	var c0: int = s.view_backups()["clones_ready"]
	while not s.view_backups()["vats"][0]["ready"] and s.t - t0 < want + 10.0:
		s.tick(s.substep_s())
	var took := s.t - t0
	t.ok(c0 == 0 and s.view_backups()["vats"][0]["ready"] and took >= want - 1e-9 and took - want < s.substep_s() + 1e-9,
		"fully tended from 0.5: ready after %.3f s; (1 − grow) / grow_per_s is %.3f, within one substep" % [took, want])
	var v := s.view_backups()
	t.ok(v["clones_ready"] == 1 and v["death"]["outcome"] == "clone", "a vat at 1 is a ready clone: clones_ready 1, a death would wake her from it")
	s.tick(10.0)
	t.ok(_grow(s, 0) == 1.0 and s.view_backups()["clones_ready"] == 1, "tended on, it holds at 1 (one clone per vat)")


## Partial tending: tend on top, both vats staffed, 1.5 workers. Tend workers are staffed per Chapel, not per vat, so
## the Chapel's 1.5 hands fill its staffed vats in slot order: vat 0 one hand, vat 1 the half (TownSim.vat_hands), and
## each grows at vats.grow_per_s × its hands. With only vat 1 staffed, it takes the first hand.
func _partial() -> void:
	var s := _chapel()
	s.cmd_set_job_priority(["tend", "build", "haul", "pit", "stall", "mill", "forge"])
	s.cmd_staff_vat(0, true)
	s.cmd_staff_vat(1, true)
	s.town_sim.workers = 1.5
	s.town_sim.restaff()
	t.ok(s.town_sim.vat_hands() == [1.0, 0.5], "1.5 tend hands on two staffed vats: [1, 0.5], the lowest slot first (%s)" % str(s.town_sim.vat_hands()))
	var r := _rate(s)
	s.tick(s.substep_s())
	t.near(_grow(s, 0), s.substep_s() * r, 1e-15, "vat 0, one hand: grow_per_s × 1 × dt")
	t.near(_grow(s, 1), s.substep_s() * r * 0.5, 1e-15, "vat 1, half a hand: grow_per_s × 0.5 × dt")
	s.cmd_staff_vat(0, false)
	s.town_sim.workers = 0.5
	s.town_sim.restaff()
	t.ok(s.town_sim.vat_hands() == [0.0, 0.5], "only vat 1 staffed, half a hand: it takes it (%s)" % str(s.town_sim.vat_hands()))


## Unstaffing a vat stops its growth and keeps the progress; staffing it again carries on from there.
func _unstaff_keeps() -> void:
	var s := _chapel()
	var r := _rate(s)
	s.cmd_staff_vat(0, true)
	s.tick(20.0)
	var g1 := _grow(s, 0)
	s.cmd_staff_vat(0, false)
	s.tick(20.0)
	t.ok(g1 > 0.0 and _grow(s, 0) == g1 and int(_tend(s)["slots"]) == 0, "unstaffed: the tend slot closes and the vat keeps its %.4f" % g1)
	s.cmd_staff_vat(0, true)
	s.tick(20.0)
	t.near(_grow(s, 0), g1 + 20.0 * r, 1e-12, "staffed again, it grows on from there")


## An unpaid Chapel offers no tend slot (MECHANICS §7), so its vats stop growing (staffed still, their progress kept).
func _unpaid_stops() -> void:
	var s := _chapel()
	s.cmd_staff_vat(0, true)
	s.tick(10.0)
	var g1 := _grow(s, 0)
	var b: Dictionary = s.town_sim.buildings["lot-13"]
	b["state"] = "unpaid"
	b["unpaid_s"] = 1.0e6
	s.town_sim.restaff()
	s.tick(10.0)
	t.ok(g1 > 0.0 and _grow(s, 0) == g1 and s.view_backups()["vats"][0]["staffed"] and int(_tend(s)["slots"]) == 0
		and s.town_sim.vat_hands() == [0.0, 0.0], "an unpaid Chapel: no tend slot, no hands, the vat stays at %.4f" % g1)


## Vigil (Relish away) puts tend on top of the ladder: with 2 workers the tend slot at the bottom gets no hand and the
## vat doesn't grow; Vigil on lifts tend and the vat grows on one hand.
func _vigil() -> void:
	var s := _chapel()
	var r := _rate(s)
	s.cmd_staff_vat(0, true)
	s.town_sim.workers = 2.0
	s.town_sim.restaff()
	s.cmd_debug_set_state({"relish_at": "old-sluice"})
	s.tick(5.0)
	t.ok(_grow(s, 0) == 0.0 and s.view_stances()["stances"].filter(func(e): return e["id"] == "vigil")[0]["active"],
		"Relish away, Vigil off: its condition holds, tend stays at the bottom with no hand, the vat doesn't grow")
	s.cmd_set_stance("vigil", true)
	s.tick(5.0)
	t.ok(s.view_town()["ladder_effective"][0] == "tend", "Vigil on: tend on top")
	t.near(_grow(s, 0), 5.0 * r, 1e-12, "Vigil puts a hand on the vat: it grows at grow_per_s")


# ------------------------------------------------------------------ spend ----
## clones_ready is the vats at 1 plus the spare clones. A death spends the lowest ready vat (back to 0, so it grows
## again), and a spare only when no vat is ready (GameState.spend_clones); then she is unmade. The boss writeback's
## spent clones follow the same order.
func _spend_order() -> void:
	var s := _chapel()
	s.vats_grow = [1.0, 1.0]
	s.clones_ready = 3
	t.ok(s.view_backups()["clones_ready"] == 3 and s._clones_spare == 1, "two vats at 1 and a spare: 3 ready")
	s._death(-1)
	t.ok(s.vats_grow == [0.0, 1.0] and s._clones_spare == 1 and s.view_backups()["clones_ready"] == 2,
		"a death empties the lowest ready vat, vat 0, back to 0 (%s, spare %d)" % [str(s.vats_grow), s._clones_spare])
	s._death(-1)
	t.ok(s.vats_grow == [0.0, 0.0] and s._clones_spare == 1, "the next empties vat 1 (%s, spare %d)" % [str(s.vats_grow), s._clones_spare])
	s._death(-1)
	t.ok(s._clones_spare == 0 and s.view_backups()["clones_ready"] == 0, "then the spare")
	s._death(-1)
	t.ok(_outcomes(s) == ["clone", "clone", "clone", "unmade"], "three clones, then unmade")
	# the boss writeback's backups_spent.clones: the lowest ready vat first
	var b := _chapel()
	b.vats_grow = [1.0, 1.0]
	b.cmd_debug_set_state({"relish_at": "vei"})
	var r := b.cmd_begin_boss()
	t.ok(r["ok"], "(setup) a boss run")
	var res := {"v": 2, "run_id": r["run_id"], "seed_rev": r["seed_rev"], "won": false, "fronts_cleared": [],
		"relish_deaths": 1, "backups_spent": {"phylactery": 0, "clones": 1}, "party_lost": [], "backlog_spent": 0.0}
	t.ok(b.apply_result("boss", res)["ok"] and b.vats_grow == [0.0, 1.0] and b.view_backups()["clones_ready"] == 1,
		"a boss fight's spent clone empties the lowest ready vat (%s)" % str(b.vats_grow))


# ------------------------------------------------------------------- save ----
## A save -> JSON -> load round trip keeps each vat's grow and staffing and the spare clones, and a tended vat grows on
## the same after it.
func _round_trip() -> void:
	var s := _chapel()
	s.cmd_staff_vat(0, true)
	s.vats_grow = [0.25, 1.0]
	s.clones_ready = 2
	var d := s.to_dict()
	t.ok(d["backups"] == {"phylactery_charges": 0, "clones_ready": 2, "vats": [{"slot": 0, "staffed": true, "grow": 0.25},
		{"slot": 1, "staffed": false, "grow": 1.0}]}, "the save: each vat's grow, clones_ready the total (%s)" % str(d["backups"]))
	var n := GameState.new(TestUtil.configs())
	n.debug_enabled = true
	t.ok(n.from_dict(JSON.parse_string(JSON.stringify(d)))["ok"], "(setup) it loads from JSON")
	var a := s.view_backups()
	var b := n.view_backups()
	a.erase("rev")
	b.erase("rev")
	t.ok(a == b and n._clones_spare == 1 and n.to_dict() == d, "after the load: the same backups (%s), the spare kept, the same save" % str(b))
	s.tick(10.0)
	n.tick(10.0)
	t.ok(_grow(n, 0) == _grow(s, 0) and _grow(n, 0) > 0.25, "and the tended vat grows on the same (%.6f)" % _grow(n, 0))


## The old-save rule (MECHANICS §7): the vats' grow is the truth, and a clones_ready above the vats at 1 is kept as
## spare clones outside the vats, so a load never loses a clone; a clones_ready below them reads the vats. The fixtures
## agree already and load as they are.
func _old_save() -> void:
	var c := TestUtil.configs()
	# clones and no Chapel (a save from before E3: a v1 save's legacy vats, or a pre_vei whose Chapel was demolished)
	var d := _mk().to_dict()
	d["backups"]["clones_ready"] = 2
	var s := GameState.new(c)
	s.debug_enabled = true
	t.ok(s.from_dict(d)["ok"] and s.view_backups()["clones_ready"] == 2 and s.view_backups()["vats"] == [] and s._clones_spare == 2
		and s.to_dict()["backups"] == d["backups"], "2 clones and no Chapel: kept as 2 spare clones, saved back as they were")
	s._death(-1)
	t.ok(s.view_backups()["clones_ready"] == 1 and _outcomes(s) == ["clone"], "a death spends one of them")
	# more clones than vats at 1
	var p := TestUtil.load_json("res://tests/fixtures/pre_vei.json")
	p["backups"]["clones_ready"] = 3.0  # (a number from JSON, as the file's are)
	s = GameState.new(c)
	s.debug_enabled = true
	t.ok(s.from_dict(p)["ok"] and s.view_backups()["clones_ready"] == 3 and s._clones_spare == 2 and s.vats_grow == [1.0, 0.0]
		and _j(s.to_dict()["backups"]) == p["backups"], "pre_vei with clones_ready 3: its vats as saved (one at 1) and 2 spare clones")
	# a clones_ready below the vats at 1 (a hand-made save): the vats win
	var q := TestUtil.load_json("res://tests/fixtures/pre_vei.json")
	q["backups"]["clones_ready"] = 0
	q["backups"]["vats"][1]["grow"] = 1.0
	s = GameState.new(c)
	s.debug_enabled = true
	t.ok(s.from_dict(q)["ok"] and s.view_backups()["clones_ready"] == 2 and s._clones_spare == 0
		and int(s.to_dict()["backups"]["clones_ready"]) == 2, "clones_ready 0 with both vats at 1: the vats' 2 clones")
	# the fixtures agree and load as they are
	for fx in GameState.FIXTURES:
		var f := TestUtil.load_json("res://tests/fixtures/%s.json" % fx)
		var g := _fixture(fx)
		t.ok(_j(g.to_dict()["backups"]) == f["backups"] and g._clones_spare == 0, "%s: its backups load as saved, no spare clone (%s)" % [fx, str(f["backups"])])


## A demolished Chapel's ready clone is kept as a spare (the vat is gone, the clone isn't), so a rebuilt Chapel starts
## with empty vats and the clone counts once.
func _demolish() -> void:
	var s := _fixture("pre_vei")
	t.ok(s.view_backups()["clones_ready"] == 1 and s.cmd_demolish("lot-13")["ok"] and s.view_backups()["clones_ready"] == 1,
		"pre_vei: the Chapel demolished, its ready clone still counts")
	s.tick(s.substep_s())
	t.ok(s.view_backups()["vats"] == [] and s.view_backups()["clones_ready"] == 1 and s._clones_spare == 1 and s.vats_grow == [],
		"the next step keeps it as a spare clone, the vats gone")
	var n := GameState.new(TestUtil.configs())
	n.debug_enabled = true
	t.ok(n.from_dict(s.to_dict())["ok"] and n.view_backups()["clones_ready"] == 1, "a save and load keep it")
	s.town_sim.place_building("lot-13", "chapel_of_vats", 1)
	t.ok(s.view_backups()["clones_ready"] == 1 and _grow(s, 0) == 0.0 and _grow(s, 1) == 0.0,
		"a Chapel built again starts empty: the clone counts once")


# -------------------------------------------------------------- catch-up ----
## A tended pre_vei vat (vat 1, empty; pre_vei's idle hands tend it) fills at the same time caught up as live, within
## one catch-up step: live at 0.5 s from the save, and a 12 h catch-up run one core step per chunk (10 s steps), the
## first step boundary it shows ready at. No clip is needed: the growth is linear and clamps at 1, so each step's
## grow is exact, and no event or rule inside a catch-up reads it (no run is open during one).
func _catchup_fill() -> void:
	var c: Dictionary = load("res://tests/test_stances.gd").cfgs({"economy.idle.catchup_steps_per_chunk": 1})
	var s := _fixture("pre_vei", c)
	t.ok(s.cmd_staff_vat(1, true)["ok"], "(setup) pre_vei, vat 1 staffed")
	s.clock_override = CLOCK
	s.cmd_save("fill")
	var t0 := s.t
	var live := GameState.new(c)
	live.debug_enabled = true
	live.save_dir = _dir
	live.clock_override = CLOCK
	live.cmd_load("fill")
	while not live.view_backups()["vats"][1]["ready"] and live.t - t0 < 400.0:
		live.tick(live.substep_s())
	var t_live := live.t - t0
	var cu := GameState.new(c)
	cu.debug_enabled = true
	cu.save_dir = _dir
	cu.clock_override = CLOCK + 43200
	cu.cmd_load("fill", true)
	var step := Catchup.base_dt(cu, 43200.0)
	while cu.catching_up() and not cu.view_backups()["vats"][1]["ready"]:
		cu.tick(cu.substep_s())
	var t_cu := cu.t - t0
	var want := 1.0 / _rate(s)
	t.ok(live.view_backups()["vats"][1]["ready"] and t_live >= want - 1e-9 and t_live - want < live.substep_s() + 1e-9,
		"live: vat 1 fills %.2f s in ((1 − 0) / grow_per_s %.2f)" % [t_live, want])
	t.ok(cu.view_backups()["vats"][1]["ready"] and absf(t_cu - t_live) <= step + 1e-9,
		"caught up (%.0f s steps): it fills %.2f s in, %.2f s from live, within one catch-up step" % [step, t_cu, t_cu - t_live])


## The tip's 12 h catch-up identity (TIP's function): the whole state, the events collected and the away report.
func identity(c: Dictionary, fixture: String, seconds: int, dir: String) -> Dictionary:
	var s := GameState.new(c)
	s.debug_enabled = true
	s.save_dir = dir
	s.cmd_debug_load_fixture(fixture)
	s.clock_override = CLOCK
	s.cmd_save("identity")
	var n := GameState.new(c)
	n.debug_enabled = true
	n.save_dir = dir
	n.clock_override = CLOCK + seconds
	n.cmd_load("identity")
	var d := n.to_dict()
	var evs: Array = n.catchup_events()
	var away := n.view_away()
	away.erase("rev")
	return {"state": JSON.stringify(d).sha256_text(), "events": JSON.stringify(evs).sha256_text(),
		"away": JSON.stringify(away).sha256_text(), "steps": n._catchup.steps, "n_events": evs.size()}


## With no vat tended (no fixture staffs one), a 12 h catch-up from each fixture is bit-identical to the tip's: the
## state, every event and the away report hash the same (pre_vei's two unstaffed vats, one ready, don't move).
func _identity() -> void:
	var c: Dictionary = load("res://tests/test_stances.gd").cfgs()
	for fx in GameState.FIXTURES:
		var h := identity(c, fx, 43200, _dir)
		t.ok(TIP.get(fx, {}) == h, "%s: with no vat tended, 12 h caught up is bit-identical to the tip's (state, events, away report): %s" % [fx, str(h)])
