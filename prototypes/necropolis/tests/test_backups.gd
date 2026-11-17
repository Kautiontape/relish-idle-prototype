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
## A death follows the backups' order, with real respawns (E3-2's second part):
## - each outcome: a phylactery charge revives her in place (loses nothing, the run goes on), else a ready clone (she
##   wakes at Covington after backups.clone_respawn_s), else unmade (after unmade_respawn_s, with the morale shock);
##   the whole party is lost in both run-ending outcomes; the charge goes before the clone; max_per_dungeon;
## - view_backups().death is what an actual death then does, and a seed's death_ends what the run-ending death does
##   (past the phylactery), with a charge present too;
## - the unbanked loot a death inside the scene loses is bounded at what was found since the last checkpoint;
## - the respawn counts down live (dead_s_left in view_relish and view_backups) and caught up (a save closed while
##   she is dead wakes her at the right t, the stance slot and Vigil following); while dead she is away from home for
##   the home stance slot, Vigil, her home effects and the dead refusals.

var t := TestUtil.new()
var _dir := "user://test_backups_%d" % OS.get_process_id()
const CLOCK := 1_800_000_000  # a "now" for the saves (unix seconds)
## The tip's 12 h catch-ups (646f288, E3-1, before the vats grew): each fixture saved and loaded 12 h on, with
## test_stances' harness configs (the field shrunk). identity() hashes the whole state (to_dict()), every event the
## catch-up collected and its away report.
## Re-pinned at E4 step 3 (the standing re-pin rule; the feature-off proofs were made at their own commits): K 12000 ->
## 36M with the fixtures' backlog re-saved to match (pre_vei 54M, midgame_2flips 12M, through the sim). day1's state and
## events stay, and its report's backlog line gains "· odds A -> B"; pre_vei's events stay, its state and report move;
## midgame's odds no longer drift up at the live scale, so fewer waves start (4 355 steps, 240 events). The values
## still agree with test_big_undead's caught runs and test_stances' reports. The notes below are from before.
## Re-pinned at E4 (API v9, the husk craft; the standing re-pin rule): the three states only, since to_dict() carries
## api_version. The proof: e299d87 with API_VERSION set back to 8 passes the old pins, events and reports unchanged.
## Re-pinned at E4's review fixes (API v10, the craft's at_cap): the three states only, as at v9. The proof: the at_cap
## commit with API_VERSION set back to 9 passes the old pins, events and reports unchanged.
## Re-pinned at E4 step 5's A1 (the muster joins FLOOD unless the Muster stance acts; API v11; the standing re-pin
## rule): all three states (api_version 11 and A1's route), and each fixture's run for the route. The proof tree (A1
## with the route forced to WAR, the early-return off and the old start valve) matches the old events and away reports,
## its states differing only by api_version 11. day1: the muster leaves WAR (10.18 -> 4.23), and day1's saved valve sits
## below the bone edge, so its bodies end at 0 (197.7 before), its mint +13 -> +9.4/s, its backlog +234,486 -> +226,861,
## and one Harvest stance_fired fewer (beat 274's off; 3 -> 2 events). midgame_2flips: WAR 7.62 -> 4.65, the backlog
## +230,846 -> +285,393, one step more (4 356); the same waves at shifted moments. pre_vei: WAR 40.9 -> 22.9, the backlog
## +1,692,203 -> +1,867,726; its events are unchanged. Was: day1 49bfe8be… / 7adf8ca1… / 31d28a99…, midgame_2flips
## b2cf7165… / 3909f7cd… / de13aae3…, pre_vei 5bc97b17… / (events) / 73b76696… (state / events / away).
const TIP := {
	"day1": {"state": "a8ee36519d9b90ad7ddd27d4b4104cadf4e6d3c7a7fe365a51cb1bd45f0a3120",
		"events": "bf49daaddc2123e6ee4b4da8affd68561ee577d54c464d657e414d0452193d34",
		"away": "4f807d582bdab4438a59f072de13bc7190c471c3faba89df978b687cfa3bc958", "steps": 4320, "n_events": 2},
	# midgame's state and away report re-baselined at E3-3's foreman: its Market's foreman (u8, m 1.183, presence +0.064)
	# takes its 12 h gold from +6,912 to +9,094, to the 9,750 cap (193 not stored), so the report's ready line is the
	# stores-full raid prompt and it gains "Gold is full: 193 not stored"; its morale 0.630 -> 0.694. The events are
	# unchanged, and with u8 in the crypt it is the parent's (test_big_undead).
	# Re-baselined again at E3-3's siege: u9's siege blocks 0.6 of every wave at Ashgate (it holds, as before, now
	# through 179 waves, one more starting inside the 12 h: 4 424 steps, 368 events); Old Sluice's retake is unchanged
	# (4 917.2 s). Her backlog gains +224,003 against +216,247, and the report adds "village Bellwether lost to Vei".
	# With u8 and u9 in the crypt it is 0e4f932's (test_big_undead)
	# E4 step 7 (the standing re-pin rule): the away report only, for the full store's line moving from losses to ready
	# ("Gold filled up, 193 not stored: queue more, or raid for relics", target the queue); the state and events are
	# unchanged (was 61a7e99c…). The same for pre_vei below (bone; was 982d56f5…)
	# E4's in-flight overlay (the standing re-pin rule; IDLE §4): the state only, for Bellwether's end owner (player, as
	# live play reads Covington's cell, not none); living at its cap of 26 either way, events and report unchanged (was
	# b1469601…). The proof: the overlay's call disabled passes the old pins
	"midgame_2flips": {"state": "54ae71490698087d9633a94208fe6ff3589e8a89da332db9bc04e0e2c2b85c10",
		"events": "7eb703c3b30d590a9bf73446b5a1531efa8cb6dd30cf1af234bee0b9f318e862",
		"away": "e0a288bf141791df9677c4b80c2eba395abac4206708b15e6417ea0741110910", "steps": 4356, "n_events": 240},
	# pre_vei re-pinned at E4 step 4's resume rule (the manager's ruling (i) on the gold-trap stop; the standing re-pin
	# rule): its floor sheds as before, but only one of the two Houses resumes, since the second would leave the gold
	# income (0.60) exactly at the paying upkeep, so one building_unpaid event fewer (15, not 16); the gold climbs at
	# +0.01 g/s instead of sitting at 18, and the report gains the "Still stopped, ... Build a Market" line. day1 and
	# midgame_2flips shed nothing in their 12 h, so they don't move.
	"pre_vei": {"state": "f23659ffea8861c02c38b3ff1afca09e23bb2a25b0d2f047411f40162a0463fe",
		"events": "e3093d57d7355dc31433aca50040e476c11b5e6fa89ed1372a608aa1860d5a84",
		"away": "a8a97ed818aeb64e80551e6ae132bcf5d846506a10834b2f47b539f39c310826", "steps": 4321, "n_events": 15},
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
	_death_order()
	_each_outcome()
	_max_per_dungeon()
	_loot_bound()
	_countdown_live()
	_away_while_dead()
	_respawn_caught_up()
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


## The tip's 12 h catch-up identity (TIP's function): the whole state (less the big undead's filled_slots, E3-3's
## key, which every fixture loads as 1), the events collected and the away report.
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
	for b in d["big_undead"]:  # the key E3-3 adds to each record (1 for every fixture's): the rest is the tip's
		b.erase("filled_slots")
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


# ------------------------------------------------------------------ death ----
const DIED := {"retreated": false, "relish_died": true}


func _clone_s(s: GameState) -> float:
	return float(s._cfgs["backups"]["backups"]["clone_respawn_s"])


func _unmade_s(s: GameState) -> float:
	return float(s._cfgs["backups"]["backups"]["unmade_respawn_s"])


## A party of two big undead; returns their uids.
func _party(s: GameState) -> Array:
	s.cmd_debug_grant({"big_undead": 2})
	var uids: Array = s.view_big_undead()["big_undead"].map(func(b): return b["uid"])
	s.cmd_set_party(uids)
	return uids


## A raid open at Old Sluice; returns its seed.
func _open_raid(s: GameState) -> Dictionary:
	s.cmd_debug_set_state({"relish_at": "old-sluice"})
	var r := s.cmd_begin_dungeon("old-sluice")
	t.ok(r["ok"], "(setup) a raid at Old Sluice")
	s.drain_events()
	return r["seed"]


## The raid result for `sd`: a retreat with nothing, `over` replacing keys.
func _raid_res(sd: Dictionary, over := {}) -> Dictionary:
	var r := {"v": 2, "run_id": sd["run_id"], "seed_rev": sd["seed_rev"], "fort_id": sd["fort"]["id"],
		"warden_beaten": false, "retreated": true, "relish_died": false, "revived_in_place": 0,
		"killed_living_mass": 0.0, "raised": [], "chaff_mass": 0.0, "garrison_mass": sd["garrison_in_mass"],
		"party_lost": [], "loot": {"relics": 0, "blueprints": [], "husks": [], "remnants": [], "essence": 0}}
	r.merge(over, true)
	return r


func _died_events(s: GameState) -> Array:
	return s.drain_events().filter(func(e): return e["type"] == "relish_died")


## MECHANICS §7's order when a charge and a clone both exist: view_backups' death reads the phylactery (in place, it
## loses nothing); the seed's death_ends is past it (the clone); in the run the dungeon revives her once in place (the
## charge, relish_died{phylactery, in_place}) and a second death ends the run from the clone, which is exactly what
## death_ends said: dead for clone_respawn_s, the vat emptied, the whole party lost, no morale shock.
func _death_order() -> void:
	var s := _chapel()
	s.vats_grow = [1.0]
	s._phylactery_charges = 1
	var party := _party(s)
	t.ok(s.view_backups()["death"] == {"outcome": "phylactery", "respawn_s": 0.0, "loses": []},
		"a charge and a clone: view_backups' death is the phylactery first: in place, it loses nothing (%s)" % str(s.view_backups()["death"]))
	var sd := _open_raid(s)
	var de: Dictionary = sd["death_ends"]
	t.ok(de == {"outcome": "clone", "respawn_s": _clone_s(s)} and int(sd["phylactery_charges"]) == 1 and Results.validate("raid_seed", sd).is_empty(),
		"the seed's death_ends is the death that ends the run, past the revive: %s" % str(de))
	var r := s.apply_result("raid", _raid_res(sd, DIED.merged({"revived_in_place": 1})))
	var evs := _died_events(s)
	t.ok(r["ok"] and evs.size() == 2 and evs[0] == {"type": "relish_died", "t": s.t, "outcome": "phylactery", "in_place": true,
		"at": "old-sluice", "run_id": sd["run_id"], "respawn_s": 0.0} and evs[1]["outcome"] == "clone" and evs[1]["in_place"] == false,
		"the revive in place, then the run-ending death from the clone: %s" % str(evs))
	t.ok(evs[1]["outcome"] == de["outcome"] and evs[1]["respawn_s"] == de["respawn_s"] and s.relish["state"] == "dead"
		and s.relish["dead_s_left"] == de["respawn_s"] and s.relish["respawn_with_clone"],
		"the run-ending death is what death_ends said: %s, dead for %.0f s from the clone" % [evs[1]["outcome"], float(s.relish["dead_s_left"])])
	t.ok(s._phylactery_charges == 0 and s.vats_grow == [0.0] and s.clones_ready == 0 and s.town_sim.shock == 0.0
		and s.big_undead.filter(func(b): return party.has(b["uid"])).is_empty() and s.party_uids.is_empty(),
		"the charge and the clone are spent, no morale shock, the whole party is lost")


## Each outcome, from view_backups().death and the seed's death_ends against what an actual death then does:
## - a phylactery charge alone: a revive in place, and the run goes on (a retreat after it): the charge spent, nothing
##   else lost (the party, the loot, Relish at the fort);
## - a clone: dead for clone_respawn_s, the whole party lost, no shock;
## - neither: unmade, dead for unmade_respawn_s, the whole party lost, the morale shock.
func _each_outcome() -> void:
	# a phylactery charge, no clone
	var p := _mk()
	p._phylactery_charges = 1
	var party := _party(p)
	var bd: Dictionary = p.view_backups()["death"]
	var sd := _open_raid(p)
	var relics0 := p.relics
	var essence0 := p.essence
	var r := p.apply_result("raid", _raid_res(sd, {"revived_in_place": 1,
		"loot": {"relics": 1, "blueprints": [], "husks": [], "remnants": [], "essence": 3}}))
	var evs := _died_events(p)
	t.ok(bd == {"outcome": "phylactery", "respawn_s": 0.0, "loses": []} and r["ok"] and evs.size() == 1 and evs[0]["outcome"] == bd["outcome"]
		and evs[0]["in_place"] and evs[0]["respawn_s"] == bd["respawn_s"],
		"phylactery: view_backups' death %s is what the revive did: in place, respawn 0" % str(bd))
	t.ok(p._phylactery_charges == 0 and p.view_relish()["state"] == "at_fort" and p.party_uids == party and p.relics == relics0 + 1
		and p.essence == essence0 + 3
		and p.town_sim.shock == 0.0 and int(p.stats["deaths"]) == 0, "the run went on: the charge spent, Relish at the fort, the party and the loot kept")
	t.ok(sd["death_ends"] == {"outcome": "unmade", "respawn_s": _unmade_s(p)}, "its seed's death_ends is past the charge: unmade (%s)" % str(sd["death_ends"]))
	# a clone, then nothing: the run-ending outcomes
	for clones in [1, 0]:
		var s := _mk()
		s.clones_ready = clones
		var uids := _party(s)
		var want: Dictionary = s.view_backups()["death"]
		var sd2 := _open_raid(s)
		t.ok(sd2["death_ends"] == {"outcome": want["outcome"], "respawn_s": want["respawn_s"]},
			"%d clones: the seed's death_ends is view_backups().death's outcome and respawn_s (%s)" % [clones, str(want)])
		t.ok(s.apply_result("raid", _raid_res(sd2, DIED.merged({"party_lost": [uids[0]]})))["ok"], "(setup) the death applies")
		var e := _died_events(s)
		var rl := s.view_relish()
		var kind := "clone" if clones == 1 else "unmade"
		var rs := _clone_s(s) if clones == 1 else _unmade_s(s)
		t.ok(e.size() == 1 and e[0]["outcome"] == want["outcome"] and e[0]["outcome"] == kind and e[0]["respawn_s"] == want["respawn_s"]
			and want["respawn_s"] == rs and rl["state"] == "dead" and rl["dead_s_left"] == rs and rl["respawn_with_clone"] == (clones == 1),
			"%s: view_backups' death is what the death did: %s for %.0f s" % [kind, e[0]["outcome"] if not e.is_empty() else "?", float(rl["dead_s_left"])])
		t.ok(want["loses"] == (["party", "unbanked_loot"] if clones == 1 else ["party", "unbanked_loot", "morale"])
			and s.big_undead.is_empty() and s.party_uids.is_empty() and s.town_sim.shock == (0.0 if clones == 1 else float(s._cfgs["economy"]["morale"]["death_shock"])),
			"%s: the whole party is lost (not only the one the dungeon reported), %s" % [kind, "no morale shock" if clones == 1 else "the morale shock"])
		t.ok(_fort(s, "old-sluice").get("flipped_count", 0) == 0, "%s: the fort doesn't flip" % kind)


func _fort(s: GameState, id: String) -> Dictionary:
	return s.realm.fort_by_id(id)


## phylactery.max_per_dungeon (1): a run may revive her in place at most that often. With 2 charges the seed carries
## the cap, a result reporting 2 revives is refused (bad_revives) and 1 spends one, leaving view_backups on the
## phylactery for the next run; with the cap at 0 no charge revives her, so view_backups' death is past it.
func _max_per_dungeon() -> void:
	var s := _mk()
	s._phylactery_charges = 2
	var sd := _open_raid(s)
	t.ok(int(sd["phylactery_max_per_dungeon"]) == 1 and s.apply_result("raid", _raid_res(sd, DIED.merged({"revived_in_place": 2})))["reason"] == "bad_revives",
		"2 charges, max_per_dungeon 1: a run reporting 2 revives is refused (bad_revives)")
	t.ok(s.apply_result("raid", _raid_res(sd, {"revived_in_place": 1}))["ok"] and s._phylactery_charges == 1
		and s.view_backups()["death"]["outcome"] == "phylactery", "1 revive spends 1; the next run's death still reads the phylactery")
	var z := _mk()
	z._phylactery_charges = 1
	z._cfgs["backups"]["phylactery"]["max_per_dungeon"] = 0
	t.ok(z.view_backups()["death"]["outcome"] == "unmade" and z.view_backups()["phylactery_max_per_dungeon"] == 0,
		"max_per_dungeon 0: a charge can't revive her, so a death would unmake her")
	var zd := _open_raid(z)
	t.ok(z.apply_result("raid", _raid_res(zd, {"revived_in_place": 1}))["reason"] == "bad_revives", "and a revive is refused")


## The unbanked loot a death inside the scene loses is bounded at what was found since the last checkpoint room: the
## dungeon's death result carries the last checkpoint's snapshot (RaidLogic.result_loot, its rule), and the writeback
## banks that on a death as on any exit, so only what was found since is lost.
func _loot_bound() -> void:
	var banked := {"relics": 1, "blueprints": [], "husks": [{"kind": "hulk"}], "remnants": [], "essence": 4}
	var found := {"relics": 3, "blueprints": [], "husks": [{"kind": "hulk"}, {"kind": "zombie"}], "remnants": [], "essence": 0}
	var loot := RaidLogic.result_loot("relish_died", false, found, 9, banked)
	t.ok(loot == banked, "the scene's death result carries the last checkpoint's loot, not what was found since: %s" % str(loot))
	var s := _mk()
	var sd := _open_raid(s)
	t.ok(s.cmd_run_checkpoint(sd["run_id"], banked)["ok"], "(setup) the checkpoint room banks it")
	var relics := s.relics
	var essence := s.essence
	t.ok(s.apply_result("raid", _raid_res(sd, DIED.merged({"loot": loot})))["ok"] and s.relics == relics + 1 and s.essence == essence + 4
		and s.husks.size() == 1, "a death banks the checkpoint's loot (relics +1, essence +4, the husk): only what was found since is lost")


## The respawn counts down live: dead_s_left in view_relish and view_backups runs down with the sim, and at
## unmade_respawn_s she wakes at Covington (relish_respawned at the death's t + respawn_s).
func _countdown_live() -> void:
	var s := _mk()
	var sd := _open_raid(s)
	s.apply_result("raid", _raid_res(sd, DIED))
	var rs := _unmade_s(s)
	var t0 := s.t
	s.drain_events()
	s.tick(rs / 2.0)
	t.ok(s.view_relish()["dead_s_left"] == rs / 2.0 and s.view_backups()["dead_s_left"] == rs / 2.0 and s.view_relish()["state"] == "dead",
		"halfway: dead_s_left %.1f in view_relish and view_backups" % float(s.view_backups()["dead_s_left"]))
	s.tick(rs / 2.0 - s.substep_s())
	t.ok(s.view_relish()["state"] == "dead" and s.view_relish()["dead_s_left"] == s.substep_s(), "a substep before: still dead")
	s.tick(s.substep_s())
	var back := s.drain_events().filter(func(e): return e["type"] == "relish_respawned")
	t.ok(back == [{"type": "relish_respawned", "t": t0 + rs, "with_clone": false, "at": "covington"}] and s.view_relish()["state"] == "home"
		and s.view_relish()["at"] == "covington" and s.view_backups()["dead_s_left"] == 0.0, "at respawn_s she reforms at Covington: %s" % str(back))


## While dead she is away from home for every rule that reads it: the home stance slot goes (3 slots home, 2 while
## dead, so the newest of three stances is suspended), Vigil's condition holds, her home effects are off (view_relish
## effects.home, TownSim's relish_home: the workers' lifetime), and the contract's `dead` refusals hold (cmd_move_relish,
## cmd_begin_dungeon, cmd_begin_boss; view_relish and view_vei say dead). The slab says not_home, as it always did.
func _away_while_dead() -> void:
	var s := _mk()
	var home_life := s.town_sim.lifetime_s(true)
	var home_slots := int(s.view_stances()["slots"])
	for id in ["harvest", "hearth", "vigil"]:
		t.ok(s.cmd_set_stance(id, true)["ok"], "(setup) %s on at home" % id)
	var sd := _open_raid(s)
	s.apply_result("raid", _raid_res(sd, DIED))
	s.tick(5.0)
	var st: Dictionary = {}
	for e in s.view_stances()["stances"]:
		st[e["id"]] = e
	t.ok(int(s.view_stances()["slots"]) == home_slots - 1 and st["vigil"]["suspended"] and st["vigil"]["active"],
		"dead: %d stance slots, not %d (no home slot), so Vigil, the newest, is suspended; its condition holds" % [int(s.view_stances()["slots"]), home_slots])
	t.ok(not s.view_relish()["effects"]["home"] and float(s.view_town()["workers"]["lifetime_s"]) == s.town_sim.lifetime_s(false)
		and s.town_sim.lifetime_s(false) != home_life, "dead: her home effects are off (effects.home false, the workers' lifetime away from her)")
	t.ok(s.cmd_move_relish("covington")["reason"] == "dead" and s.cmd_begin_dungeon("old-sluice")["reason"] == "dead"
		and s.cmd_begin_boss()["reason"] == "dead" and s.view_relish()["reason"] == "dead" and not s.view_relish()["can_descend"]
		and s.view_vei()["reason"] == "dead", "dead: move, descend and the boss refuse with dead")
	t.ok(s.cmd_raise_big_undead("h1", [], "x")["reason"] == "not_home", "the slab: not_home")
	s.tick(_unmade_s(s))
	st = {}
	for e in s.view_stances()["stances"]:
		st[e["id"]] = e
	t.ok(s.view_relish()["state"] == "home" and int(s.view_stances()["slots"]) == home_slots and not st["vigil"]["suspended"]
		and s.view_relish()["effects"]["home"], "respawned home: the home slot is back (Vigil no longer suspended), her home effects on")


## A save closed while she is dead wakes her at the right time: dead at the save (unmade, the Vigil stance on), loaded
## respawn_s + 1 h later. The catch-up clips a step at her respawn: relish_respawned at the death's t + respawn_s,
## then she is home, the home slot back, and Vigil's condition turns off within a step after it (its hold long over).
func _respawn_caught_up() -> void:
	var c: Dictionary = load("res://tests/test_stances.gd").cfgs()
	var s := GameState.new(c)
	s.cmd_new_game(1)
	s.debug_enabled = true
	s.save_dir = _dir
	s.cmd_set_stance("vigil", true)
	var sd := _open_raid(s)
	s.apply_result("raid", _raid_res(sd, DIED))
	var t_died := s.t
	var rs := _unmade_s(s)
	s.tick(30.0)
	var vigil_on: bool = s.view_stances()["stances"].filter(func(e): return e["id"] == "vigil")[0]["active"]
	s.clock_override = CLOCK
	s.cmd_save("dead")
	var away := int(rs - 30.0) + 3600
	var n := GameState.new(c)
	n.debug_enabled = true
	n.save_dir = _dir
	n.clock_override = CLOCK + away
	t.ok(n.cmd_load("dead")["ok"] and vigil_on, "(setup) dead at the save, Vigil active; loaded %d s later" % away)
	var evs := n.catchup_events()
	var back := evs.filter(func(e): return e["type"] == "relish_respawned")
	t.ok(back.size() == 1 and absf(float(back[0]["t"]) - (t_died + rs)) < 1e-6 and back[0]["with_clone"] == false,
		"caught up: relish_respawned at the death's t + respawn_s (%.3f against %.3f)" % [float(back[0]["t"]) if not back.is_empty() else -1.0, t_died + rs])
	var offs := evs.filter(func(e): return e["type"] == "stance_fired" and e["stance_id"] == "vigil" and not e["active"])
	# the conditions are read at a new beat (live play's next beat, 1.714 s), at a step boundary: within a beat and a step
	var step := Catchup.base_dt(n, float(away))
	var bound := n._beat_s + step
	t.ok(not back.is_empty() and offs.size() == 1 and float(offs[0]["t"]) > float(back[0]["t"]) and float(offs[0]["t"]) - float(back[0]["t"]) <= bound + 1e-6,
		"Vigil follows: its condition turns off %.2f s after the respawn, within a beat and a catch-up step (%.2f s)" % [
		float(offs[0]["t"]) - float(back[0]["t"]) if not offs.is_empty() and not back.is_empty() else -1.0, bound])
	t.ok(n.view_relish()["state"] == "home" and n.view_relish()["dead_s_left"] == 0.0 and int(n.view_stances()["slots"]) == int(s.view_stances()["slots"]) + 1,
		"after it she is home, and the home stance slot is back (%d slots)" % int(n.view_stances()["slots"]))
