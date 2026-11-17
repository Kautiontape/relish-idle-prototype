extends RefCounted
## E4 step 2: the autoplayer's keep_fronts policy (tests/autoplay/autoplayer.gd; IDLE §8 "Keepers"), on a new game with
## hand-set bigs and remnants (no raid is run). It asserts:
## - a big whose wits bring KEEP_SHARE of giants' want is kept there: it joins the party first, on giants, and _reach
##   counts only the raiders;
## - a big under the share is not kept, and raid_all (the E3 policy, ablation_keep) keeps none and reaches by the party;
## - the slab fill puts giants' stat first when that brings more of its want, and raid_all keeps the magnitude fill.

var t := TestUtil.new()


static func _big(gs: GameState, wits: float, beef: float) -> String:
	var uid := gs._mint_uid("u")
	var st := {}
	for k in GameState.STATS:
		st[k] = 0.0
	st["wits"] = wits
	st["beef"] = beef
	gs.big_undead.append({"uid": uid, "name": "Test " + uid, "kind": "skeleton", "role": "hollow", "stats": st,
		"place": "crypt", "front": "", "filled_slots": 1})
	return uid


static func _party(gs: GameState) -> Array:
	var out: Array = []
	for p in gs.view_party()["party"]:
		out.append(str(p["uid"]))
	return out


static func _front(gs: GameState, uid: String) -> String:
	for b in gs.view_big_undead()["big_undead"]:
		if str(b["uid"]) == uid:
			return str(b["front"])
	return "?"


func run() -> int:
	t.suite("autoplay_keep")
	var c := Autoplayer.cfgs()
	var b := Autoplayer._bot("keep_test", c, {"print_rows": false})
	b.new_game()
	var want: float = b._big_want()["giants"]
	var keeper := _big(b.s, Autoplayer.KEEP_SHARE * want + 0.5, 0.0)
	var low := _big(b.s, Autoplayer.KEEP_SHARE * want - 0.5, 0.0)
	var other := _big(b.s, 0.0, 0.0)
	b._place()
	t.ok(b._keep == [keeper], "the big with wits >= %.2f of giants' want (%.1f) is the keeper, the one under it isn't: %s" % [
		Autoplayer.KEEP_SHARE, want, str(b._keep)])
	t.ok(_party(b.s) == [keeper, low, other] and _front(b.s, keeper) == "giants",
		"the keeper joins the party first, on giants: %s, %s" % [str(_party(b.s)), _front(b.s, keeper)])
	t.ok(b._reach() == 3, "the reach counts the two raiders only (t3), not the keeper: %d" % b._reach())

	var e3 := Autoplayer._bot("keep_test_e3", c, {"print_rows": false, "raid_all": true})
	e3.new_game()
	_big(e3.s, Autoplayer.KEEP_SHARE * want + 0.5, 0.0)
	_big(e3.s, 0.0, 0.0)
	_big(e3.s, 0.0, 0.0)
	e3._place()
	t.ok(e3._keep.is_empty() and _party(e3.s).size() == 3 and e3._reach() == 4,
		"raid_all keeps none, and the whole party reaches t4: %s, %d" % [str(e3._keep), e3._reach()])

	# the fill: a skeleton (two nerve slots: wits or speed) with two big speed remnants and two small wits ones
	var slab: Dictionary = c["town"]["slab"]
	var rems := [
		{"uid": "r1", "aspect": "speed", "rarity": "rare", "magnitude": 5},
		{"uid": "r2", "aspect": "speed", "rarity": "rare", "magnitude": 4},
		{"uid": "r3", "aspect": "wits", "rarity": "common", "magnitude": 2},
		{"uid": "r4", "aspect": "wits", "rarity": "common", "magnitude": 1},
	]
	var w_keep := float(SlabLogic.evaluate("skeleton", b._slab_fill("skeleton", rems, slab), slab)["stats"].get("wits", 0.0))
	var w_e3 := float(SlabLogic.evaluate("skeleton", e3._slab_fill("skeleton", rems, slab), slab)["stats"].get("wits", 0.0))
	t.ok(w_keep == 3.0 and w_e3 == 0.0, "keep_fronts fills the nerve slots with wits (3; got %s), raid_all by magnitude (speed; wits %s)" % [
		str(w_keep), str(w_e3)])
	b.cleanup()
	e3.cleanup()

	# E4 step 3: Vei-ready is BALANCE §1's, odds >= 0.6 as well as the fronts (fronts_required 0 here, so only the odds gate)
	var c0 := c.duplicate(true)
	c0["vei"]["fronts_required"] = 0
	var g := Autoplayer._bot("keep_test_odds", c0, {"print_rows": false})
	g.new_game()
	g._vei_check(g.s.t + 3600.0)
	var odds_new := float(g.s.view_vei()["odds"])
	t.ok(odds_new < Autoplayer.VEI_READY_ODDS and g.vei_ready_t < 0.0,
		"fronts met but odds %.3f < %.1f: no Vei-ready" % [odds_new, Autoplayer.VEI_READY_ODDS])
	g.s.realm.vei["undead_queue"] = 2.0 * float(c0["realm"]["K"])  # odds 2/3
	g._vei_check(g.s.t + 3600.0)
	t.ok(g.vei_ready_t >= 0.0, "fronts met and odds %.3f: Vei-ready at %.0f s" % [float(g.s.view_vei()["odds"]), g.vei_ready_t])
	g.cleanup()
	return t.failures
