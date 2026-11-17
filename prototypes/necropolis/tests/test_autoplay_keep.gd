extends RefCounted
## E4 step 2: the autoplayer's keep_fronts policy (tests/autoplay/autoplayer.gd; IDLE §8 "Keepers"), on a new game with
## hand-set bigs and remnants (no raid is run). It asserts:
## - a big whose wits bring KEEP_SHARE of giants' want is kept there: it joins the party first, on giants, and _reach
##   counts only the raiders;
## - a big under the share is not kept, and raid_all (the E3 policy, ablation_keep) keeps none and reaches by the party;
## - the slab fill puts giants' stat first when that brings more of its want, and raid_all keeps the magnitude fill;
## - two-front keeping (the sizing stop's ruling): both fronts' keepers at cap 6, the better-covered front's at cap 4, a
##   big that qualifies on both kept once;
## - the crypt's levels head the fill once a big is kept, or the crypt is full while a husk waits, and not before.

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


## A big whose `fid` stat brings `share` of that front's want (x = per_stat x stat).
static func _stat_for(c: Dictionary, want: float, fid: String, share: float) -> float:
	return share * want / float(c["vei"]["fronts"][fid]["per_stat"])


## The sizing stop's ruling (two-front keeping): at cap 6 (cap - RAID_ROOM = 4) two skeletons that meet giants together and
## two zombies that meet carvers together are all kept, each on its front; at cap 4 only the better-covered front's two
## are; a big that qualifies on both fronts keeps one.
func _two_fronts(c: Dictionary) -> void:
	var c6 := c.duplicate(true)
	c6["economy"]["big_undead"]["cap"] = 6
	var b := Autoplayer._bot("keep_test_two", c6, {"print_rows": false})
	b.new_game()
	var w: Dictionary = b._big_want()
	var g1 := _big(b.s, _stat_for(c, w["giants"], "giants", 0.6), 0.0)
	var g2 := _big(b.s, _stat_for(c, w["giants"], "giants", 0.5), 0.0)
	var z1 := _big(b.s, 0.0, _stat_for(c, w["carvers"], "carvers", 0.55))
	var z2 := _big(b.s, 0.0, _stat_for(c, w["carvers"], "carvers", 0.5))
	b._place()
	t.ok(b._keep == [g1, g2, z1, z2], "cap 6: both fronts' pairs are kept, giants (1.10 of its want) before carvers (1.05): %s" % str(b._keep))
	t.ok(_front(b.s, g1) == "giants" and _front(b.s, g2) == "giants" and _front(b.s, z1) == "carvers" and _front(b.s, z2) == "carvers",
		"each keeper is on its own front: %s %s %s %s" % [_front(b.s, g1), _front(b.s, g2), _front(b.s, z1), _front(b.s, z2)])
	t.ok(b._reach() == 1, "four keepers home, no raider: the reach is t1 (%d)" % b._reach())
	b.cleanup()

	var b4 := Autoplayer._bot("keep_test_two4", c, {"print_rows": false})
	b4.new_game()
	_big(b4.s, _stat_for(c, w["giants"], "giants", 0.6), 0.0)
	_big(b4.s, _stat_for(c, w["giants"], "giants", 0.5), 0.0)
	var y1 := _big(b4.s, 0.0, _stat_for(c, w["carvers"], "carvers", 0.65))
	var y2 := _big(b4.s, 0.0, _stat_for(c, w["carvers"], "carvers", 0.5))
	b4._place()
	t.ok(b4._keep == [y1, y2], "cap 4 (room for 2 keepers): the better-covered front's pair (carvers 1.15 against giants 1.10): %s" % str(b4._keep))
	b4.cleanup()

	# a big that qualifies on both: wits for 0.9 of giants, beef for 0.5 of carvers; another zombie brings 0.6 of carvers.
	# Carvers covers 1.1 alone, giants 0.9, so carvers takes both and giants has no candidate left
	var bb := Autoplayer._bot("keep_test_both", c6, {"print_rows": false})
	bb.new_game()
	var both := _big(bb.s, _stat_for(c, w["giants"], "giants", 0.9), _stat_for(c, w["carvers"], "carvers", 0.5))
	var zc := _big(bb.s, 0.0, _stat_for(c, w["carvers"], "carvers", 0.6))
	bb._place()
	t.ok(bb._keep == [zc, both] and _front(bb.s, both) == "carvers",
		"a big that qualifies on both fronts is kept once, on the front that took it first: %s, %s" % [str(bb._keep), _front(bb.s, both)])
	bb.cleanup()


## The crypt's levels (the sizing stop's ruling): no crypt entry while the crypt has room; once it is full (big undead at
## the cap) and a husk waits, the fill queues crypt level 2 first, and the latch holds after the husk is gone.
func _crypt_levels(c: Dictionary) -> void:
	for full in [false, true]:
		var b := Autoplayer._bot("keep_test_crypt", c, {"print_rows": false})
		b.new_game()
		var cap := int(b.s.view_big_undead()["cap"])
		for _i in cap - (0 if full else 1):
			_big(b.s, 0.0, 0.0)
		b.s.husks.append({"uid": b.s._mint_uid("h"), "kind": "skeleton", "rarity": "common"})
		b._fill()
		var ids := _queue_ids(b.s)
		if not full:
			t.ok(not b._crypt_up and not _queued(b.s, "lot-01"), "the crypt has room (%d of %d): no crypt level is queued: %s" % [
				cap - 1, cap, str(ids)])
		else:
			t.ok(b._crypt_up and not ids.is_empty() and str(ids[0]) == "crypt/lot-01/2",
				"the crypt full (%d) with a husk waiting: crypt level 2 heads the fill: %s" % [cap, str(ids)])
			b.s.husks.clear()
			b._fill()
			t.ok(b._crypt_up, "the latch holds with no husk left")
		b.cleanup()
	# a keeper alone (the crypt has room, no husk): the crypt's levels head the fill too
	var k := Autoplayer._bot("keep_test_crypt_k", c, {"print_rows": false})
	k.new_game()
	_big(k.s, _stat_for(c, k._big_want()["giants"], "giants", 0.5), 0.0)
	k._place()
	k._fill()
	var kids := _queue_ids(k.s)
	t.ok(k._keep.size() == 1 and k._crypt_up and not kids.is_empty() and str(kids[0]) == "crypt/lot-01/2",
		"a keeper held (%s), the crypt with room: crypt level 2 heads the fill: %s" % [str(k._keep), str(kids)])
	k.cleanup()


## The bot's husk craft (lever (b), the sizing stop's ruling 2), at craft.husk.bone 100 (a new game's bone cap is 200)
## with 120 bone and one wits remnant more than the craft eats: with giants and carvers short it crafts a skeleton (the
## wits fill brings giants the larger share); it doesn't while the queue's head waits on bone (Market level 2, 130 bone),
## with the crypt full (and then the crypt trigger fires), or with both fronts met by keepers.
func _husk_policy(c: Dictionary) -> void:
	var cl := c.duplicate(true)
	cl["economy"]["craft"]["husk"]["bone"] = 100.0
	var n := int(cl["economy"]["craft"]["husk"]["remnants"])
	var mk := func(tag: String) -> Autoplayer:
		var b := Autoplayer._bot("keep_test_husk_" + tag, cl, {"print_rows": false})
		b.new_game()
		b.s.remnants.clear()
		b.s.husks.clear()
		for i in n + 1:
			b.s.remnants.append({"uid": b.s._mint_uid("r"), "aspect": "wits", "rarity": "common", "magnitude": 1 + i % 3})
		b.s.town_sim.bone = 120.0
		return b
	var a: Autoplayer = mk.call("a")
	a._craft_husk()
	t.ok(a.crafted.size() == 1 and str(a.crafted[0][1]) == "skeleton" and a.s.husks.size() == 1 and a.s.remnants.size() == 1,
		"both fronts short, room, bone and a remnant to spare: a skeleton is crafted (%s; %d remnant left)" % [str(a.crafted), a.s.remnants.size()])
	a.s.town_sim.bone = 120.0
	for i in n - 1:
		a.s.remnants.append({"uid": a.s._mint_uid("r"), "aspect": "wits", "rarity": "common", "magnitude": 1})
	a._craft_husk()
	t.ok(a.crafted.size() == 1, "the bone back and %d remnants, exactly the craft's (none to spare for the raise): no second craft" % n)
	a.cleanup()

	var w: Autoplayer = mk.call("wait")
	var qr := w.s.cmd_queue_build("", "lot-04")
	var q: Array = w.s.view_town()["queue"]
	t.ok(bool(qr["ok"]) and not q.is_empty() and str(q[0]["reason"]) == "no_bone", "setup: Market level 2 heads the queue, waiting on bone: %s" % str(q))
	w._craft_husk()
	t.ok(w.crafted.is_empty(), "the queue's head waits on bone: no craft")
	w.cleanup()

	var f: Autoplayer = mk.call("full")
	for _i in int(f.s.view_big_undead()["cap"]):
		_big(f.s, 0.0, 0.0)
	f._craft_husk()
	t.ok(f.crafted.is_empty() and f._husk_kind(true) == "skeleton", "the crypt full: no craft, though one would go but for the room")
	f._fill()
	t.ok(f._crypt_up, "and the crypt trigger fires on it (no husk waiting, no keeper)")
	f.cleanup()

	var m: Autoplayer = mk.call("met")
	var wm: Dictionary = m._big_want()
	_big(m.s, _stat_for(c, wm["giants"], "giants", 1.0), 0.0)
	_big(m.s, 0.0, _stat_for(c, wm["carvers"], "carvers", 1.0))
	m._place()
	m._craft_husk()
	t.ok(m._keep.size() == 2 and m.crafted.is_empty(), "both fronts met by their keepers: no craft (%s)" % str(m._keep))
	m.cleanup()


static func _queued(gs: GameState, lot: String) -> bool:
	for e in gs.view_town()["queue"]:
		if str(e["lot_id"]) == lot:
			return true
	return false


static func _queue_ids(gs: GameState) -> Array:
	var out: Array = []
	for e in gs.view_town()["queue"]:
		out.append("%s/%s/%d" % [e["building_id"], e["lot_id"], int(e["level"])])
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

	# E4 step 3: a dip in Vei's pool (every tithe wave draws it) doesn't release a keeper. Two carvers bigs that meet the
	# want at her full pool together, each over what the want would be with her pool at 0 (the old rule read today's
	# need, so one alone met it and the other was released to raid)
	var dp := Autoplayer._bot("keep_test_dip", c, {"print_rows": false})
	dp.new_game()
	var cap := float(dp.s.view_vei()["pool_cap"])
	dp.s.realm.vei["living_pool"] = cap
	var wfull: float = dp._big_want()["carvers"]
	var pool_term := float(c["vei"]["fronts"]["carvers"]["need_per_pool"]) * cap
	var beef := wfull - pool_term + 0.5
	t.ok(beef < wfull and 2.0 * beef >= wfull and beef >= Autoplayer.KEEP_SHARE * wfull,
		"setup: each big (beef %.1f) is under carvers' full-pool want (%.1f), the two meet it, and each would meet the want at an empty pool (%.1f)" % [
		beef, wfull, wfull - pool_term])
	var k1 := _big(dp.s, 0.0, beef)
	var k2 := _big(dp.s, 0.0, beef)
	dp._place()
	t.ok(dp._keep == [k1, k2], "at her full pool both are kept on carvers: %s" % str(dp._keep))
	dp.s.realm.vei["living_pool"] = 0.0
	var v0 := dp.s.view_vei()
	var live_need := 0.0
	for fr in v0["fronts"]:
		if str(fr["id"]) == "carvers":
			live_need = float(fr["need"])
	t.ok(live_need - float(c["vei"]["fronts"]["carvers"]["per_q"]) * float(v0["digest_q"]) <= beef,
		"setup: with her pool at 0 today's need (%.1f) less the q term is within one big's beef" % live_need)
	t.near(float(dp._big_want()["carvers"]), wfull, 1e-9, "the want reads her full pool's need, not today's")
	dp._place()
	t.ok(dp._keep == [k1, k2], "with her pool drawn to 0 both stay kept: %s" % str(dp._keep))
	dp.cleanup()

	_two_fronts(c)
	_crypt_levels(c)
	_husk_policy(c)

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
