extends RefCounted
## E4 step 9, the idle relic trickle (the run's manager's rulings on step 9 (3), 2026-11-17 12:45 and 14:24; MECHANICS
## §2's relics row): one relic per economy.json relic_trickle.period_s of game time while every fort at or below the highest tier
## ever flipped is held (GameState.relic_trickle_paying), read at each step's start; the accrued seconds are saved
## (inventory.relic_trickle_s, written once non-zero, optional on load); view_hud shows highest_tier_flipped and
## relic_trickle {paying, next_s}. Headless, no autoloads.

var t: TestUtil


func run() -> int:
	t = TestUtil.new()
	t.suite("relic-trickle")
	_condition()
	_pays()
	_store_cap()
	_save()
	_open_closed_break()
	return t.failures


const CLOCK := 1_800_000_000


## midgame_2flips with every t1 fort held (Ashgate and Old Sluice flipped, so tier 1 is the highest flipped) and the
## trickle `s_in` seconds into its period. `breaker`: Greywall held past its grace on an empty garrison with the valve's
## WAR at 0 and Relish home, so it breaks after hold.break_s and the trickle stops; else every t1 fort's grace is 2 days.
static func start(c: Dictionary, s_in: float, breaker: bool) -> GameState:
	var conv = load("res://tests/slow/convergence.gd").new()
	var s := GameState.new(c)
	s.debug_enabled = true
	s.from_dict(JSON.parse_string(conv.start_json("midgame_2flips")))
	for f in s.realm.forts:
		if int(f["tier"]) == 1:
			s.realm.hold(str(f["id"]), 0.0 if breaker and str(f["id"]) == "greywall" else 2.0 * 86400.0)
	if breaker:
		var g: Dictionary = s.realm.fort_by_id("greywall")
		g["undead"] = 0.0
		g["living"] = 0.0
		g["zero_s"] = 5.0  # 5 s at 0 already: it breaks 115 s in, inside a 10 s catch-up step
		s.cmd_set_valve(0.85, 0.0, 0.15)
		s.valve = s.valve_target.duplicate()
		s._place_relish("covington")
	s._ledger.reset(GameState.Ledger.total(s._held()))  # (the garrisons set by hand)
	s.relic_trickle_s = s_in
	return s


## `s` saved, then `seconds` on: caught up (a load with the clock on: the real runner, at c's steps) and live (loaded at
## the clock, ticked at 0.5 s). [closed, open].
static func open_closed(c: Dictionary, s: GameState, seconds: float) -> Array:
	var dir := "user://test_relic_trickle_%d" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(dir)
	s.save_dir = dir
	s.clock_override = CLOCK
	s.cmd_save("tr")
	var out: Array = []
	for away in [int(seconds), 0]:
		var n := GameState.new(c)
		n.debug_enabled = true
		n.save_dir = dir
		n.clock_override = CLOCK + away
		n.cmd_load("tr")
		if away == 0:
			n.tick(seconds)
		out.append(n)
	DirAccess.remove_absolute(dir + "/tr.json")
	DirAccess.remove_absolute(dir)
	return out


## The step 9 review's item 1, the transition: open and closed over 20 min at 10 s catch-up steps, with a relic due at
## 60 s and Greywall breaking 115 s in, inside a step. Both pay the relic; the condition is read at each step's start, so
## the closed run's paying seconds run on to the end of the step the break falls in: at most one step (IDLE §8; measured
## 55 s open, 60 closed). The steady
## case (30 h, every t1 fort held throughout: the same relics and seconds) is in tests/slow/catchup_accuracy.gd.
func _open_closed_break() -> void:
	var c: Dictionary = load("res://tests/test_catchup.gd").cfgs({"economy.idle.catchup_max_steps": 120})
	var s := start(c, float(c["economy"]["relic_trickle"]["period_s"]) - 60.0, true)
	var r0 := s.relics
	t.ok(s.relic_trickle_paying(), "(setup) every t1 fort held: the trickle pays")
	var runs := open_closed(c, s, 1200.0)
	var cl: GameState = runs[0]
	var op: GameState = runs[1]
	var gone := not RealmSim.is_held(cl.realm.fort_by_id("greywall")) and not RealmSim.is_held(op.realm.fort_by_id("greywall"))
	t.ok(gone and cl.relics == r0 + 1 and op.relics == r0 + 1, "both pay the relic due at 60 s and Greywall breaks in both (relics %d -> %d closed, %d open)" % [
		r0, cl.relics, op.relics])
	var d := cl.relic_trickle_s - op.relic_trickle_s
	t.ok(op.relic_trickle_s > 0.0 and op.relic_trickle_s < 600.0 and d > 1e-6 and d <= 10.0 + 1e-6,
		"the paying seconds stop at the break: %.2f open, %.2f closed: the closed run pays on to its step's end, %.2f s (at most one 10 s step)" % [
		op.relic_trickle_s, cl.relic_trickle_s, d])


func _game() -> GameState:
	var s := GameState.new(TestUtil.configs())
	s.cmd_new_game(7)
	return s


## Every fort of `tier` held (its grace a day, so nothing retakes it in a test), the first of them flipped once.
func _hold_tier(s: GameState, tier: int) -> void:
	var first := true
	for f in s.realm.forts:
		if int(f["tier"]) == tier:
			s.realm.hold(str(f["id"]), 86400.0)
			if first:
				f["flipped_count"] = 1
				first = false


func _condition() -> void:
	var s := _game()
	t.ok(s.highest_tier_flipped() == 0 and not s.relic_trickle_paying(), "a new game: no tier flipped, no trickle")
	var hv: Dictionary = s.view_hud()
	t.ok(int(hv["highest_tier_flipped"]) == 0 and not bool(hv["relic_trickle"]["paying"]) and float(hv["relic_trickle"]["next_s"]) == -1.0,
		"view_hud: highest_tier_flipped 0, relic_trickle {paying false, next_s -1.0}")
	_hold_tier(s, 1)
	var n1 := 0
	for f in s.realm.forts:
		n1 += 1 if int(f["tier"]) == 1 else 0
	t.ok(s.highest_tier_flipped() == 1 and s.relic_trickle_paying(), "every t1 fort held (%d), one flipped: tier 1, paying" % n1)
	hv = s.view_hud()
	t.ok(bool(hv["relic_trickle"]["paying"]) and float(hv["relic_trickle"]["next_s"]) == s._req_f("economy.relic_trickle.period_s"),
		"view_hud: paying, a full period to the next relic")
	var t1: Array = s.realm.forts.filter(func(f): return int(f["tier"]) == 1)
	var lost: Dictionary = t1[-1]
	lost["held"] = false
	t.ok(not s.relic_trickle_paying(), "one t1 fort back with Vei (%s): no trickle" % lost["id"])
	s.realm.hold(str(lost["id"]), 86400.0)
	var t2: Array = s.realm.forts.filter(func(f): return int(f["tier"]) == 2)
	t2[0]["flipped_count"] = 1
	t.ok(s.highest_tier_flipped() == 2 and not s.relic_trickle_paying(), "a t2 flip raises the tier read; the t2 forts not held stop it")


func _pays() -> void:
	var s := _game()
	_hold_tier(s, 1)
	var period := s._req_f("economy.relic_trickle.period_s")
	s.relic_trickle_s = period - 1.0
	var r0 := s.relics
	s.tick(2.0)
	t.ok(s.relics == r0 + 1 and absf(s.relic_trickle_s - 1.0) < 1e-6 and s.trickle_paid == 1,
		"a period's paying seconds pay one relic (%d -> %d), the rest carried (%.3f s)" % [r0, s.relics, s.relic_trickle_s])
	var t1: Array = s.realm.forts.filter(func(f): return int(f["tier"]) == 1)
	t1[0]["held"] = false
	var kept := s.relic_trickle_s
	s.tick(2.0)
	t.ok(s.relic_trickle_s == kept and s.relics == r0 + 1, "while it doesn't pay the accrued seconds are kept and nothing is paid")
	var big := _game()
	_hold_tier(big, 1)
	big._relic_trickle(2.5 * period)
	t.ok(big.relics == 2 and absf(big.relic_trickle_s - 0.5 * period) < 1e-6, "one long step of 2.5 periods pays two and carries half (catch-up)")


func _store_cap() -> void:
	var s := _game()
	_hold_tier(s, 1)
	s.relics = s._cap_of("relics")
	s._relic_trickle(s._req_f("economy.relic_trickle.period_s"))
	t.ok(s.relics == s._cap_of("relics") and s.relic_trickle_s == 0.0, "at the relic cap the period's relic is lost, as loot's is")


func _save() -> void:
	var s := _game()
	t.ok(not (s.to_dict()["inventory"] as Dictionary).has("relic_trickle_s"), "nothing accrued: the save has no relic_trickle_s (as before)")
	_hold_tier(s, 1)
	s.relic_trickle_s = 1234.5
	var d := s.to_dict()
	t.ok(float(d["inventory"]["relic_trickle_s"]) == 1234.5, "accrued: inventory.relic_trickle_s is saved")
	var cfgs := TestUtil.configs()
	var d2: Dictionary = d.duplicate(true)
	(d2["inventory"] as Dictionary).erase("relic_trickle_s")
	var d3: Dictionary = d.duplicate(true)
	d3["inventory"]["relic_trickle_s"] = "soon"
	t.ok(SaveIO.problem(d2, cfgs) == "" and SaveIO.problem(d, cfgs) == "" and SaveIO.problem(d3, cfgs) == "inventory relic_trickle_s",
		"the key is optional, and must be a number when present")
	var m := GameState.new(cfgs)
	t.ok(m.from_dict(d)["ok"] and m.relic_trickle_s == 1234.5, "it loads back")
	t.ok(m.from_dict(d2)["ok"] and m.relic_trickle_s == 0.0, "an old save without it reads 0")
	_load_clamp(d)


## The step 9 review's item 2: a corrupt relic_trickle_s loads clamped to [0, one period], so the first paying step
## pays at most one relic and returns (1e300 looped _relic_trickle's while for good; revert proof: without the clamp
## the first and last asserts fail, and the step is skipped so the suite doesn't hang).
func _load_clamp(d: Dictionary) -> void:
	var cfgs := TestUtil.configs()
	var period := float(cfgs["economy"]["relic_trickle"]["period_s"])
	var big: Dictionary = d.duplicate(true)
	big["inventory"]["relic_trickle_s"] = 1e300
	var neg: Dictionary = d.duplicate(true)
	neg["inventory"]["relic_trickle_s"] = -5000.0
	var m := GameState.new(cfgs)
	var clamped: bool = SaveIO.problem(big, cfgs) == "" and m.from_dict(big)["ok"] and m.relic_trickle_s == period
	t.ok(clamped, "a corrupt 1e300 loads clamped to one period (%.1f s)" % m.relic_trickle_s)
	if clamped:  # (unclamped, the step below would loop for good: the revert proof fails above instead of hanging)
		var r0 := m.relics
		m._relic_trickle(1.0)
		t.ok(m.relics == r0 + 1 and absf(m.relic_trickle_s - 1.0) < 1e-6, "its first paying step pays one relic and returns (%d -> %d, %.3f s carried)" % [
			r0, m.relics, m.relic_trickle_s])
	var n := GameState.new(cfgs)
	t.ok(n.from_dict(neg)["ok"] and n.relic_trickle_s == 0.0, "a negative one loads as 0")
