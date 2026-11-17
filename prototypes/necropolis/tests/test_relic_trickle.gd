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
	return t.failures


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
