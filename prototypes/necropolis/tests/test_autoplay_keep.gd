extends RefCounted
## E4 step 2: the autoplayer's keep_fronts policy (tests/autoplay/autoplayer.gd; IDLE §8 "Keepers"), on a new game with
## hand-set bigs and remnants (no raid is run). It asserts:
## - a big whose wits bring KEEP_SHARE of giants' want is kept there: it joins the party first, on giants, and _reach
##   counts only the raiders;
## - a big under the share is not kept, and raid_all (the E3 policy, ablation_keep) keeps none and reaches by the party;
## - the slab fill puts giants' stat first when that brings more of its want, and raid_all keeps the magnitude fill;
## - two-front keeping (the sizing stop's ruling): both fronts' keepers at cap 6, the better-covered front's at cap 4, a
##   big that qualifies on both kept once;
## - the crypt's levels head the fill once a big is kept, or the crypt is full while a husk waits, and not before;
## - Vei-ready needs the odds and the fronts met at her full pool, not only in a tithe wave's dip (the sizing stop's R2).

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

	# the order that meets more fronts wins: A brings 0.6 of giants and 0.9 of carvers, B 0.5 of giants, C and D 0.55 of
	# carvers each. Carvers covers 1.45 alone (A, C) against giants' 1.1 (A, B), but carvers first leaves giants B alone
	# (one front met); giants first takes A and B, and C and D meet carvers (two)
	var bo := Autoplayer._bot("keep_test_order", c6, {"print_rows": false})
	bo.new_game()
	var a := _big(bo.s, _stat_for(c, w["giants"], "giants", 0.6), _stat_for(c, w["carvers"], "carvers", 0.9))
	var bg := _big(bo.s, _stat_for(c, w["giants"], "giants", 0.5), 0.0)
	var cc := _big(bo.s, 0.0, _stat_for(c, w["carvers"], "carvers", 0.55))
	var dd := _big(bo.s, 0.0, _stat_for(c, w["carvers"], "carvers", 0.55))
	bo._place()
	t.ok(bo._keep == [a, bg, cc, dd] and _front(bo.s, a) == "giants" and _front(bo.s, cc) == "carvers",
		"the order that meets both fronts is kept (giants first: A, B; carvers: C, D): %s, A on %s" % [str(bo._keep), _front(bo.s, a)])
	bo.cleanup()

	# sessions at 96 h: three giants keepers (0.43, 0.36, 0.29: met) and one carvers keeper (0.41); two more carvers bigs
	# (0.41 each) arrive. Carvers first meets carvers and covers 1.43, giants first meets giants and covers 1.41: one front
	# either way, so the keepers already kept stay, rather than sending giants' second and third out to raid
	var bs := Autoplayer._bot("keep_test_stay", c6, {"print_rows": false})
	bs.new_game()
	var gk: Array = []
	for sh in [0.43, 0.36, 0.29]:
		gk.append(_big(bs.s, _stat_for(c, w["giants"], "giants", sh), 0.0))
	var c1 := _big(bs.s, 0.0, _stat_for(c, w["carvers"], "carvers", 0.41))
	bs._place()
	t.ok(bs._keep == gk + [c1], "setup: giants' three and carvers' one are kept: %s" % str(bs._keep))
	_big(bs.s, 0.0, _stat_for(c, w["carvers"], "carvers", 0.41))
	_big(bs.s, 0.0, _stat_for(c, w["carvers"], "carvers", 0.41))
	bs._place()
	t.ok(bs._keep == gk + [c1], "two more carvers bigs, one front met either way: today's keepers stay (%s)" % str(bs._keep))
	# churn (the E4 review's item 5): a look on an unchanged state keeps the same keepers and sends no party command
	bs.record = true
	var ch0: Dictionary = bs.keep_churn.duplicate(true)
	bs._place()
	t.ok(bs._keep == gk + [c1] and bs.cmd_log.is_empty() and int(bs.keep_churn["changes"]) == int(ch0["changes"]),
		"a repeat look on an unchanged state: the same keepers, no command (%s, %d commands)" % [str(bs._keep), bs.cmd_log.size()])
	t.ok(int(bs.keep_churn["looks"]) == 3 and int(bs.keep_churn["changes"]) == 1 and int(bs.keep_churn["drops_held"]) == 0
		and int(bs.keep_churn["flip_backs"]) == 0, "keep_churn over the three looks: one change (the first), no keeper dropped: %s" % str(bs.keep_churn))
	bs.cleanup()


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
		for i in n:  # the craft's: the weakest
			b.s.remnants.append({"uid": b.s._mint_uid("r"), "aspect": "wits", "rarity": "common", "magnitude": 1 + i % 3})
		for _i in 2:  # left for the raise: a skeleton's two nerve slots, wits 10, over KEEP_SHARE of giants' want
			b.s.remnants.append({"uid": b.s._mint_uid("r"), "aspect": "wits", "rarity": "rare", "magnitude": 5})
		b.s.town_sim.bone = 120.0
		return b
	var a: Autoplayer = mk.call("a")
	a._craft_husk()
	t.ok(a.crafted.size() == 1 and str(a.crafted[0][1]) == "skeleton" and a.s.husks.size() == 1 and a.s.remnants.size() == 2,
		"both fronts short, room, bone and remnants to spare: a skeleton is crafted (%s; %d remnants left)" % [str(a.crafted), a.s.remnants.size()])
	a.s.town_sim.bone = 120.0
	a.s.remnants.clear()
	for _i in n:
		a.s.remnants.append({"uid": a.s._mint_uid("r"), "aspect": "wits", "rarity": "rare", "magnitude": 5})
	a._craft_husk()
	t.ok(a.crafted.size() == 1, "the bone back and %d strong remnants, exactly the craft's (none to spare for the raise): no second craft" % n)
	a.cleanup()

	# the remnants left would fill a skeleton to wits 1 (under KEEP_SHARE of giants' want): no craft
	var wk: Autoplayer = mk.call("weak")
	wk.s.remnants.clear()
	for _i in n + 1:
		wk.s.remnants.append({"uid": wk.s._mint_uid("r"), "aspect": "wits", "rarity": "common", "magnitude": 1})
	wk._craft_husk()
	t.ok(wk.crafted.is_empty(), "a body too weak to keep (wits 1 of giants' want %.1f) isn't made" % float(wk._big_want()["giants"]))
	wk.cleanup()

	var w: Autoplayer = mk.call("wait")
	var qr := w.s.cmd_queue_build("", "lot-04")
	var q: Array = w.s.view_town()["queue"]
	t.ok(bool(qr["ok"]) and not q.is_empty() and str(q[0]["reason"]) == "no_bone", "setup: Market level 2 heads the queue, waiting on bone: %s" % str(q))
	w._craft_husk()
	t.ok(w.crafted.is_empty(), "the queue's head waits on bone: no craft")
	w.cleanup()

	# the E4 review: the craft mustn't take bone the queue's head needs, though the head doesn't wait on bone yet
	var hb: Autoplayer = mk.call("headbone")
	t.ok(bool(hb.s.cmd_queue_build("", "lot-04")["ok"]), "(setup) Market level 2 queued")
	var head_bone := float((hb.s.view_town()["queue"] as Array)[0]["cost"]["bone"])
	var price := float(cl["economy"]["craft"]["husk"]["bone"])
	hb.s.town_sim.bone = price + head_bone - 1.0
	t.ok(head_bone > 0.0 and str((hb.s.view_town()["queue"] as Array)[0]["reason"]) != "no_bone",
		"(setup) the head needs %.0f bone and doesn't wait on bone at %.0f" % [head_bone, hb.s.town_sim.bone])
	hb._craft_husk()
	t.ok(hb.crafted.is_empty(), "bone %.0f: the price %.0f would leave the head's %.0f short: no craft" % [price + head_bone - 1.0, price, head_bone])
	hb.s.town_sim.bone = price + head_bone
	hb._craft_husk()
	t.ok(hb.crafted.size() == 1 and is_equal_approx(hb.s.town_sim.bone, head_bone),
		"bone %.0f: the price leaves exactly the head's bone: it crafts (%s)" % [price + head_bone, str(hb.crafted)])
	hb.cleanup()

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

	# The bot reads the player's source, view_catalog().husk_craft, not its raw configs (the E4 review): its own copy says
	# the craft costs 1e9 bone and 99 remnants and makes zombies only, the state's (the view's) says 100 bone, n remnants,
	# skeleton or zombie, so a craft of a skeleton is the view's answer
	var vw: Autoplayer = mk.call("view")
	vw.c = cl.duplicate(true)
	vw.c["economy"]["craft"]["husk"]["bone"] = 1e9
	vw.c["economy"]["craft"]["husk"]["remnants"] = 99
	vw.c["loot"]["chest_by_tier"]["1"]["husk_kinds"] = ["zombie"]
	var hcv: Dictionary = vw.s.view_catalog()["husk_craft"]
	t.ok(bool(hcv["can_craft"]) and float(hcv["cost"]["bone"]) == 100.0 and hcv["kinds"].has("skeleton"), "(setup) the view: %s" % str(hcv))
	vw._craft_husk()
	t.ok(vw.crafted.size() == 1 and str(vw.crafted[0][1]) == "skeleton",
		"the bot follows the view's price and kinds, not its raw configs: %s" % str(vw.crafted))
	vw.cleanup()


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
	# (at carvers' need_base 18, the value it was built on: the shipped 2 since E4 step 2's sizing leaves the want at an
	# empty pool under 0, and the case needs it above)
	var cd := c.duplicate(true)
	cd["vei"]["fronts"]["carvers"]["need_base"] = 18.0
	var dp := Autoplayer._bot("keep_test_dip", cd, {"print_rows": false})
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
	# (E4 step 9) the odds at the strain (time_weight 0, backlog_cap 1), so the backlog set below sets them: this checks
	# the gate; test_win_odds checks that the odds it reads are the win odds
	c0["realm"]["odds"]["time_weight"] = 0.0
	c0["realm"]["odds"]["backlog_cap"] = 1.0
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
	_full_pool_ready(c)
	_pump_lost_cause(c)
	return t.failures


## E4 review item 11 (a): prepare_away's WAR pump (_pump_war) lets a lost cause go, as _war_topup does in a session.
## midgame_2flips with both held forts past their grace and the valve's WAR at 0.10. (0) Vei's pressure ×(mint ÷
## mint_ref)^α with mint_ref a hundredth of the mint: both forts need more than WAR_MAX, so the pump leaves the valve
## (before, it ran to WAR_MAX for them). (1) The shipped pressure: it raises WAR until neither reads a margin under 0.
func _pump_lost_cause(c: Dictionary) -> void:
	for k in 2:
		var b := Autoplayer._bot("pump_test_%d" % k, c, {"print_rows": false})
		b.s = b._fresh()
		b.s.debug_enabled = true
		t.ok(bool(b.s.cmd_debug_load_fixture("midgame_2flips")["ok"]), "(setup) midgame_2flips loads")
		for id in ["ashgate", "old-sluice"]:
			b.s.realm.hold(id, 0.0)
		if k == 0:
			b.s._mint_ref = 0.01 * (b.s._p_base + b.s._p_per_pit * float(b.s.town_sim.pits()))
		var tg: Dictionary = b.s.view_hud()["valve_target"]
		var wf := float(tg["work"]) + float(tg["flood"])
		b.s.cmd_set_valve(float(tg["work"]) / wf * 0.9, 0.1, float(tg["flood"]) / wf * 0.9)
		b.s._core_step(0.5)
		var r := b._pump_war()
		if k == 0:
			t.ok((r["let_go"] as Array).size() == 2 and absf(float(r["war"]) - 0.1) < 1e-9 and r.size() == 4 and b.s.hold_mult() > 20.0,
				"×%.1f pressure: both forts are lost causes and WAR stays at 0.10: %s" % [b.s.hold_mult(), str(r)])
		else:
			t.ok((r["let_go"] as Array).is_empty() and float(r["war"]) > 0.1 + 1e-9 and float(r["war"]) <= Autoplayer.WAR_MAX
				and float(r["min_margin"]) >= 0.0, "×%.2f pressure: WAR rises until both hold: %s" % [b.s.hold_mult(), str(r)])
		b.cleanup()


## The sizing stop's ruling R2: the bot's Vei-ready reads the fronts at her full pool (_full_met), not at the pool she
## has then. With fronts_required 2, odds 2/3 (a backlog of 2K, whose mass also meets swarm at any pool) and her pool
## drawn to 0, as in a tithe wave's dip, carvers' 3 × q meets today's need but not the full pool's: no Vei-ready, and the
## old readout (vei_ready_wave_t) records the look without moving Relish. A carvers keeper that meets the full pool's
## need makes her Vei-ready on arrival.
func _full_pool_ready(c: Dictionary) -> void:
	var c2 := c.duplicate(true)
	c2["vei"]["fronts_required"] = 2
	c2["realm"]["odds"]["time_weight"] = 0.0  # (E4 step 9) the odds at the strain, as in _keep's odds gate
	c2["realm"]["odds"]["backlog_cap"] = 1.0
	var r := Autoplayer._bot("keep_test_full_pool", c2, {"print_rows": false})
	r.new_game()
	r.s.realm.vei["undead_queue"] = 2.0 * float(c2["realm"]["K"])
	r.s.realm.vei["living_pool"] = 0.0
	var v := r.s.view_vei()
	var cap := float(v["pool_cap"])
	var full_need := r._full_need("carvers", cap)
	var car_have := 0.0
	for fr in v["fronts"]:
		if str(fr["id"]) == "carvers":
			car_have = float(fr["have"])
	t.ok(int(v["fronts_met"]) == 2 and r._full_met(v) == 1 and car_have < full_need,
		"setup: at pool 0 two fronts are met (%d), at her full pool %.0f one (%d): carvers %.2f under %.2f" % [
		int(v["fronts_met"]), cap, r._full_met(v), car_have, full_need])
	var t0 := r.s.t
	r._vei_check(r.s.t + 3600.0)
	t.ok(r.vei_ready_t < 0.0 and is_equal_approx(r.vei_ready_wave_t, t0) and str(r.s.view_relish()["state"]) == "home",
		"met only in the dip: no Vei-ready (%.0f), the wave readout at the look (%.0f), and Relish stays home" % [
		r.vei_ready_t, r.vei_ready_wave_t])
	var k := _big(r.s, 0.0, ceilf(full_need - car_have) + 1.0)
	r._place()
	t.ok(r._keep == [k] and _front(r.s, k) == "carvers", "(setup) the beef big is kept on carvers: %s" % str(r._keep))
	r._vei_check(r.s.t + 3600.0)
	t.ok(r.vei_ready_t > t0 and is_equal_approx(r.vei_ready_wave_t, t0),
		"carvers met at her full pool: Vei-ready on arrival (%.0f s), the wave readout unchanged" % r.vei_ready_t)
	r.cleanup()
