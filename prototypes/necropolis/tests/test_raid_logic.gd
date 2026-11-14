extends RefCounted
## Pure-logic tests for the raid scenes: mass ledger math, tier→enemy-count
## mapping, layout generator validity (doors, rooms, reachability), and the
## score→raise-tier mapping. No scene tree, no autoloads.


func run() -> int:
	var t := TestUtil.new()
	var cfg := TestUtil.load_json("res://configs/raid.json")

	# --- tier → enemy-count mapping -----------------------------------------
	t.suite("raid_mass")
	t.ok(RaidLogic.enemy_count(120.0, 160.0, cfg) == 20, "120/160 living → 20 enemies")
	t.near(RaidLogic.mass_per_enemy(120.0, 160.0, cfg), 6.0, 0.001, "mass per enemy = living/count")
	t.ok(RaidLogic.enemy_count(3.0, 160.0, cfg) == 5, "tiny living clamps to 5 enemies")
	t.ok(RaidLogic.enemy_count(1000.0, 160.0, cfg) == 34, "huge living clamps to 34 enemies")
	var n := RaidLogic.enemy_count(77.0, 133.0, cfg)
	t.near(RaidLogic.mass_per_enemy(77.0, 133.0, cfg) * n, 77.0, 0.001, "enemy masses always sum to living")
	t.ok(RaidLogic.pile_count(20.0, cfg) == 2, "dead 20 → 2 piles")
	t.ok(RaidLogic.pile_count(4.0, cfg) == 2, "dead 4 clamps up to 2 piles")
	t.ok(RaidLogic.pile_count(400.0, cfg) == 24, "dead 400 clamps to 24 piles")
	t.ok(RaidLogic.garrison_count(10.0, cfg) == 1, "undead 10 → 1 garrison unit")
	t.ok(RaidLogic.garrison_count(3.0, cfg) == 0, "undead 3 → 0 garrison units")
	t.ok(RaidLogic.garrison_count(500.0, cfg) == 12, "undead 500 clamps to 12")

	# --- score → raise tier mapping -----------------------------------------
	t.suite("raid_raise")
	t.ok(RaidLogic.score_class(59, cfg) == "chaff", "59 is chaff")
	t.ok(RaidLogic.score_class(60, cfg) == "soldier", "60 is soldier")
	t.ok(RaidLogic.score_class(89, cfg) == "soldier", "89 is soldier")
	t.ok(RaidLogic.score_class(90, cfg) == "elite", "90 is elite")
	var s := RaidLogic.raise_spec(40, 21.0, 7, cfg)
	t.ok(s["kind"] == "chaff" and int(s["count"]) == 7, "sloppy circle: 7 orbs → 7 chaff")
	t.near(float(s["unit_mass"]) * 7.0, 21.0, 0.001, "chaff units carry all the mass")
	s = RaidLogic.raise_spec(75, 10.0, 7, cfg)
	t.ok(s["kind"] == "soldier" and int(s["count"]) == 2, "score 75, 7 orbs → 2 soldiers")
	s = RaidLogic.raise_spec(75, 10.0, 2, cfg)
	t.ok(int(s["count"]) == 1, "soldier raise always yields at least 1")
	s = RaidLogic.raise_spec(95, 30.0, 9, cfg)
	t.ok(s["kind"] == "elite" and int(s["count"]) == 2, "score 95, 9 orbs → 2 elites")
	s = RaidLogic.raise_spec(100, 5.0, 1, cfg)
	t.ok(s["kind"] == "elite" and int(s["count"]) == 1, "perfect tiny circle → 1 elite")
	s = RaidLogic.raise_spec(100, 0.0, 0, cfg)
	t.ok(int(s["count"]) == 0, "no orbs enclosed → nothing raised")

	# --- mass ledger: raises never exceed available mass --------------------
	t.suite("raid_ledger")
	var lg := RaidLogic.Ledger.new(20.0, 160.0)
	t.ok(lg.aborted(), "fresh ledger reads as aborted")
	lg.on_kill(6.0)
	lg.on_kill(6.0)
	lg.on_kill(6.0)
	t.near(lg.killed, 18.0, 0.001, "kills accumulate")
	t.ok(not lg.aborted(), "a kill clears the aborted flag")
	lg.on_raise(40, 12.0, 3, cfg)          # chaff raise: 12 mass in 3 units
	t.near(lg.chaff_pool, 12.0, 0.001, "chaff raise fills the walking pool")
	lg.on_chaff_death(4.0)                  # one chaff re-killed: corpse stays at the fort
	t.near(lg.chaff_pool, 8.0, 0.001, "dead chaff leaves the pool")
	lg.on_raise(75, 10.0, 3, cfg)          # soldier raise consumes 10 mass
	t.ok(lg.soldiers == 1, "soldier count banked")
	t.near(lg.good_mass, 10.0, 0.001, "good mass tracked")
	lg.on_raise(95, 8.0, 4, cfg)
	t.ok(lg.elites == 1, "elite count banked")
	var res := lg.result("vespers", false, cfg)
	t.near(float(res["killed_living_mass"]), 18.0, 0.001, "result: killed mass")
	t.near(float(res["garrison_mass"]), 8.0, 0.001, "surviving chaff below cap → all stays as garrison")
	t.near(float(res["raised_chaff_mass"]), 0.0, 0.001, "nothing left over for the chaff horde")
	t.near(float(res["good_mass"]), 18.0, 0.001, "good mass = soldier+elite raises")
	t.ok(not bool(res["aborted"]) and not bool(res["relish_died"]), "flags clean")
	var raised_total: float = float(res["raised_chaff_mass"]) + float(res["good_mass"]) + float(res["garrison_mass"])
	t.ok(raised_total <= lg.initial_dead + lg.killed + 0.001, "raised mass never exceeds dead+killed")

	# garrison cap: chaff pool beyond 0.25*cap walks home with Relish
	var lg2 := RaidLogic.Ledger.new(200.0, 100.0)   # keep cap = 25
	lg2.on_raise(30, 180.0, 12, cfg)
	var res2 := lg2.result("kest", false, cfg)
	t.near(float(res2["garrison_mass"]), 25.0, 0.001, "garrison capped at 0.25*cap")
	t.near(float(res2["raised_chaff_mass"]), 155.0, 0.001, "remainder leaves as chaff mass")
	t.ok(not bool(res2["aborted"]), "raising counts as activity even with zero kills")

	# stress: many raises can never break conservation
	var lg3 := RaidLogic.Ledger.new(50.0, 160.0)
	var pool := 50.0                      # simulated essence afield (from piles)
	var rngl := RandomNumberGenerator.new()
	rngl.seed = 99
	for i in 40:
		var kill_mass := rngl.randf_range(2.0, 7.0)
		lg3.on_kill(kill_mass)
		pool += kill_mass
		var take := minf(pool, rngl.randf_range(0.0, 12.0))
		if take > 0.5:
			pool -= take
			lg3.on_raise(rngl.randi_range(20, 100), take, 1 + rngl.randi_range(0, 5), cfg)
		if rngl.randf() < 0.3:
			lg3.on_chaff_death(minf(lg3.chaff_pool, rngl.randf_range(0.0, 5.0)))
	var res3 := lg3.result("gloom", true, cfg)
	var total3: float = float(res3["raised_chaff_mass"]) + float(res3["good_mass"]) + float(res3["garrison_mass"])
	t.ok(total3 <= lg3.initial_dead + lg3.killed + 0.001, "stress: conservation holds")
	t.ok(bool(res3["relish_died"]), "death flag carried into the result")

	# --- layout generator validity ------------------------------------------
	t.suite("raid_layout")
	var cell: float = float(cfg.get("layout", {}).get("grid_cell", 32.0))
	for tier in [1, 2, 3, 4]:
		for fid in ["vespers", "gloomspire", "kest", "hallowmere"]:
			var lay := RaidLogic.gen_layout(fid, tier, false, cfg)
			var label := "%s t%d" % [fid, tier]
			var doors: Array = lay["doors"]
			t.ok(doors.size() == (lay["checkpoints"] as Array).size(), "%s: doors == checkpoints (%d)" % [label, doors.size()])
			var south := 0
			for d in doors:
				if d["side"] == "s":
					south += 1
			t.ok(south >= 1, "%s: at least one south door" % label)
			t.ok((lay["rooms"] as Array).size() == 2 + tier, "%s: rooms == 2+tier (%d)" % [label, (lay["rooms"] as Array).size()])
			t.ok(RaidLogic.layout_reachable(lay, cell), "%s: all rooms + doors reachable" % label)
			var spawn: Vector2 = lay["spawn"]
			var size: Vector2 = lay["size"]
			t.ok(spawn.x > 0 and spawn.y > 0 and spawn.x < size.x and spawn.y < size.y,
				"%s: spawn inside the arena" % label)
			var in_wall := false
			for wrect in lay["walls"]:
				if (wrect as Rect2).has_point(spawn):
					in_wall = true
			t.ok(not in_wall, "%s: spawn not inside a wall" % label)
	# determinism: a fortress is recognizably ITSELF on revisits
	var a := RaidLogic.gen_layout("vespers", 2, false, cfg)
	var b := RaidLogic.gen_layout("vespers", 2, false, cfg)
	t.ok(a["spawn"] == b["spawn"] and (a["walls"] as Array).size() == (b["walls"] as Array).size()
		and a["walls"][0] == b["walls"][0] and (a["doors"] as Array).size() == (b["doors"] as Array).size(),
		"same fort_id → identical layout")
	var c := RaidLogic.gen_layout("gloomspire", 2, false, cfg)
	t.ok(c["spawn"] != a["spawn"] or c["walls"][0] != a["walls"][0],
		"different fort_id → different layout")
	# boss layout
	var bl := RaidLogic.gen_layout("vei", 5, true, cfg)
	t.ok((bl["doors"] as Array).size() >= 6, "boss: plenty of doors")
	var bsouth := 0
	for d in bl["doors"]:
		if d["side"] == "s":
			bsouth += 1
	t.ok(bsouth >= 2, "boss: multiple south doors for the streaming horde")
	t.ok(RaidLogic.layout_reachable(bl, cell), "boss: reachable")
	t.ok(int(bl["warden_room"]) == -1 and int(bl["ante_room"]) == -1, "boss: no warden or antechamber")
	var bnormal := true
	for r in bl["roles"]:
		bnormal = bnormal and r == "normal"
	t.ok(bnormal and (bl["roles"] as Array).size() == (bl["rooms"] as Array).size(), "boss: every role is normal")
	t.ok((bl["size"] as Vector2).x > (RaidLogic.gen_layout("x", 4, false, cfg)["size"] as Vector2).x,
		"boss arena is the biggest layout")

	_role_tests(t, cfg, cell)
	_first_pile_tests(t, cfg)
	_ghost_ring_tests(t)
	_unbanked_tests(t)

	# --- population sanity ---------------------------------------------------
	t.suite("raid_population")
	var lay4 := RaidLogic.gen_layout("vespers", 2, false, cfg)
	var spots := RaidLogic.populate_enemies("vespers", lay4, 20, 2, cfg)
	t.ok(spots.size() == 20, "asked for 20 enemy spots")
	var all_inside := true
	var none_in_walls := true
	var kinds_legal := true
	var legal: Array = RaidLogic.tier_kinds(2, cfg)
	for sp in spots:
		var p: Vector2 = sp["pos"]
		if p.x < 0 or p.y < 0 or p.x > (lay4["size"] as Vector2).x or p.y > (lay4["size"] as Vector2).y:
			all_inside = false
		for wrect in lay4["walls"]:
			if (wrect as Rect2).has_point(p):
				none_in_walls = false
		if not legal.has(sp["kind"]):
			kinds_legal = false
	t.ok(all_inside, "enemy spots inside the arena")
	t.ok(none_in_walls, "enemy spots never inside walls")
	t.ok(kinds_legal, "tier 2 rolls only tier-2 kinds")
	var t1_kinds := true
	for sp in RaidLogic.populate_enemies("kest", RaidLogic.gen_layout("kest", 1, false, cfg), 12, 1, cfg):
		if sp["kind"] != "spearman":
			t1_kinds = false
	t.ok(t1_kinds, "tier 1 fields spearmen only")

	# --- v2: seed, per-mote raise, statlines, LedgerV2 ------------------------
	var ccfg := TestUtil.load_json("res://configs/circle.json")
	t.suite("raid_v2_seed")
	var dseed := RaidLogic.demo_seed(cfg)
	t.ok(Results.validate("raid_seed", dseed) == [], "demo_seed validates as raid_seed: %s" % str(Results.validate("raid_seed", dseed)))
	t.ok(int(dseed["garrison_units"]) == RaidLogic.garrison_count(float(dseed["undead"]), cfg), "garrison_units from garrison_count")
	t.near(float(dseed["garrison_in_mass"]), float(dseed["garrison_units"]) * 10.0, 0.001, "garrison_in_mass = units x div")
	t.ok(dseed["rng_seed"] is String and str(dseed["rng_seed"]).is_valid_int(), "rng_seed is a decimal String")
	t.ok((dseed["party"] as Array).size() >= 1, "demo party has a big undead")

	t.suite("raid_v2_raise")
	t.near(RaidLogic.stat_mult(0, ccfg), 0.5, 0.0001, "stat_mult 0 = 0.5")
	t.near(RaidLogic.stat_mult(50, ccfg), 1.0, 0.0001, "stat_mult 50 = 1.0")
	t.near(RaidLogic.stat_mult(100, ccfg), 1.5, 0.0001, "stat_mult 100 = 1.5")
	var motes: Array = [{"mass": 2.0, "recycled": false}, {"mass": 3.0, "recycled": true}, {"mass": 1.5, "recycled": false}]
	var rs := RaidLogic.raise_spec_v2(75, motes, cfg, ccfg)
	t.ok(int(rs["count"]) == 3, "count == motes")
	t.near(float(rs["fresh_mass"]), 3.5, 0.0001, "fresh_mass excludes recycled")
	t.ok(rs["tier"] == "soldier", "75 is soldier")
	t.near(float(rs["stat_mult"]), 1.25, 0.0001, "stat_mult 1.25 at 75")
	t.ok((rs["unit_masses"] as Array).size() == 3 and is_equal_approx(float((rs["unit_masses"] as Array)[1]), 3.0), "unit_masses one per mote")
	t.ok(RaidLogic.raise_spec_v2(59, motes, cfg, ccfg)["tier"] == "chaff", "59 chaff")
	t.ok(RaidLogic.raise_spec_v2(60, motes, cfg, ccfg)["tier"] == "soldier", "60 soldier")
	t.ok(RaidLogic.raise_spec_v2(89, motes, cfg, ccfg)["tier"] == "soldier", "89 soldier")
	t.ok(RaidLogic.raise_spec_v2(90, motes, cfg, ccfg)["tier"] == "elite", "90 elite")
	var rz := RaidLogic.raise_spec_v2(95, [], cfg, ccfg)
	t.ok(int(rz["count"]) == 0 and rz["tier"] == "" and float(rz["fresh_mass"]) == 0.0, "zero motes: count 0, tier empty, fresh 0")

	t.suite("raid_v2_stats")
	var us := RaidLogic.undead_stats(1.5, "elite", cfg)
	t.near(float(us["hp"]), 15.0, 0.0001, "hp x mult")
	t.near(float(us["dmg"]), 3.0, 0.0001, "dmg x mult")
	t.near(float(us["speed"]), 118.0, 0.0001, "speed unchanged")
	t.near(float(us["cadence_s"]), 0.9, 0.0001, "cadence unchanged")
	t.near(float(us["radius"]), 12.0, 0.0001, "elite radius 12")
	t.near(float(RaidLogic.undead_stats(1.0, "chaff", cfg)["radius"]), 8.0, 0.0001, "chaff radius 8")
	var bs := RaidLogic.big_undead_stats({"power": 5.0, "beef": 4.0, "wits": 1.0, "presence": 1.0, "speed": 2.0}, cfg)
	t.near(float(bs["hp"]), 30.0 + 8.0 * 4.0, 0.0001, "big hp")
	t.near(float(bs["dmg"]), 3.0 + 1.2 * 5.0, 0.0001, "big dmg")
	t.near(float(bs["speed"]), 90.0 + 10.0 * 2.0, 0.0001, "big speed")
	t.near(float(bs["cadence_s"]), 1.0, 0.0001, "big cadence")
	t.near(float(bs["radius"]), 20.0, 0.0001, "big radius")

	t.suite("raid_v2_ledger")
	var vs := RaidLogic.demo_seed(cfg)
	vs["phylactery_charges"] = 1
	var uid0: String = str((vs["party"] as Array)[0]["uid"])
	var keep: float = float((cfg["mass"] as Dictionary)["garrison_keep_cap_frac"]) * float((vs["fort"] as Dictionary)["cap"])
	for ex in ["warden_beaten", "retreated", "relish_died"]:
		var lgx := RaidLogic.LedgerV2.new(vs, cfg)
		lgx.on_kill(12.0)
		lgx.on_raise(40, 5.0, 2)
		var r := lgx.build_result(vs, ex, [], [], 1 if ex == "retreated" else 0, {}, cfg)
		t.ok(Results.validate("raid", r) == [], "%s validates: %s" % [ex, str(Results.validate("raid", r))])
		t.ok(bool(r[ex]), "%s flag set" % ex)
		t.ok(int(r["revived_in_place"]) == (1 if ex == "retreated" else 0), "revived echoed")
		if ex == "relish_died":
			t.ok(r["party_lost"] == [uid0], "relish_died loses whole party")
		t.ok(int(r["run_id"]) == int(vs["run_id"]) and r["fort_id"] == "vespers", "ids echoed")
	var lgm := RaidLogic.LedgerV2.new(vs, cfg)
	lgm.on_kill(-4.0)
	lgm.on_kill(10.0)
	lgm.on_raise(40, 100.0, 10)
	lgm.on_raise(40, 50.0, 5)
	lgm.on_raise(75, 10.0, 0)
	lgm.on_raise(75, 30.0, 3)
	lgm.on_raise(95, 20.0, 2)
	var r2 := lgm.build_result(vs, "retreated", [
		{"role": "garrison", "tier": "chaff", "mass": 7.0},
		{"role": "raised", "tier": "soldier", "mass": 4.0},
		{"role": "raised", "tier": "elite", "mass": 2.0},
		{"role": "raised", "tier": "chaff", "mass": 100.0},
		{"role": "raised", "tier": "chaff", "mass": 20.0},
		{"role": "starter", "tier": "chaff", "mass": 50.0},
		{"role": "party", "tier": "", "mass": 50.0}], [uid0, "nope"], 0, {"relics": 2}, cfg)
	t.ok((r2["raised"] as Array).size() == 3, "same-score raises merge; count<=0 ignored")
	var b40: Dictionary = {}
	for bk in r2["raised"]:
		if int(bk["score"]) == 40:
			b40 = bk
	t.ok(int(b40["count"]) == 15 and is_equal_approx(float(b40["mass"]), 150.0), "merged bucket sums")
	t.near(float(r2["killed_living_mass"]), 10.0, 0.0001, "negative kill ignored")
	t.near(float(r2["garrison_mass"]), 7.0 + 4.0 + 2.0 + keep, 0.0001, "garrison = garrison+soldier+elite+kept chaff")
	t.near(float(r2["chaff_mass"]), 120.0 - keep, 0.0001, "chaff leaves = pool - kept")
	t.ok(r2["party_lost"] == [uid0], "party_died filtered to seed party")
	t.ok(int(r2["loot"]["relics"]) == 2 and (r2["loot"]["blueprints"] as Array).is_empty() and int(r2["loot"]["essence"]) == 0, "loot normalised")
	t.ok(Results.validate("raid", r2) == [], "mixed result validates")
	var rc := RaidLogic.LedgerV2.new(vs, cfg)
	rc.on_raise(40, 10.0, 2)
	rc.on_raise(75, 4.0, 1)
	rc.on_raise(99, 4.0, 3)
	var cnt := rc.raised_counts()
	t.ok(int(cnt["chaff"]) == 2 and int(cnt["soldier"]) == 1 and int(cnt["elite"]) == 3, "raised_counts by tier")
	var rb := RaidLogic.LedgerV2.new(vs, cfg).build_result(vs, "retreated", [
		{"role": "garrison", "tier": "chaff", "mass": 10.0},
		{"role": "raised", "tier": "soldier", "mass": 50.0}], [], 0, {}, cfg)
	t.ok(float(rb["garrison_mass"]) + float(rb["chaff_mass"]) <= float(vs["garrison_in_mass"]) + 1e-6, "bound scales to fit")
	var rng := RandomNumberGenerator.new()
	rng.seed = 424242
	var stress_ok := true
	for it in 60:
		var sd := RaidLogic.demo_seed(cfg)
		sd["undead"] = rng.randf_range(0.0, 200.0)
		sd["garrison_units"] = RaidLogic.garrison_count(float(sd["undead"]), cfg)
		sd["garrison_in_mass"] = float(sd["garrison_units"]) * float(sd["garrison_mass_div"])
		var lgs := RaidLogic.LedgerV2.new(sd, cfg)
		var total_raised := 0.0
		for _k in rng.randi_range(0, 6):
			lgs.on_kill(rng.randf_range(0.0, 20.0))
		for _k in rng.randi_range(0, 6):
			var ms: Array = []
			for _m in rng.randi_range(0, 8):
				ms.append({"mass": rng.randf_range(0.1, 5.0), "recycled": rng.randf() < 0.4})
			var sc := rng.randi_range(0, 100)
			var spec := RaidLogic.raise_spec_v2(sc, ms, cfg, ccfg)
			lgs.on_raise(sc, float(spec["fresh_mass"]), int(spec["count"]))
			total_raised += float(spec["fresh_mass"]) if int(spec["count"]) > 0 else 0.0
		var surv: Array = []
		for _k in rng.randi_range(0, 12):
			surv.append({"role": ["garrison", "raised", "starter", "party"][rng.randi_range(0, 3)],
				"tier": ["chaff", "soldier", "elite"][rng.randi_range(0, 2)], "mass": rng.randf_range(0.0, 15.0)})
		var rr := lgs.build_result(sd, ["warden_beaten", "retreated", "relish_died"][rng.randi_range(0, 2)], surv, [], 0, {}, cfg)
		var gm := float(rr["garrison_mass"])
		var cm := float(rr["chaff_mass"])
		if gm < 0.0 or cm < 0.0 or gm + cm > float(sd["garrison_in_mass"]) + total_raised + 1e-6 \
				or Results.validate("raid", rr) != []:
			stress_ok = false
	t.ok(stress_ok, "60-iteration stress: bound holds, masses >= 0, validates")

	# --- sacrifice chain, drift telemetry, essence from both sides ----------
	t.suite("raid_sacrifice_essence")
	t.ok(RaidLogic.sacrifice_pick([]) == -1, "no candidates -> -1")
	t.ok(RaidLogic.sacrifice_pick([{"rank": 3, "dist": 5.0}, {"rank": 1, "dist": 90.0}, {"rank": 0, "dist": 200.0}]) == 2,
		"lowest rank wins over a nearer higher rank")
	t.ok(RaidLogic.sacrifice_pick([{"rank": 0, "dist": 80.0}, {"rank": 0, "dist": 30.0}, {"rank": 1, "dist": 1.0}]) == 1,
		"same rank: the nearest wins")
	t.ok(RaidLogic.sacrifice_pick([{"rank": 2, "dist": 10.0}]) == 0, "a single candidate is picked")
	t.ok(RaidLogic.ally_rank("garrison", "chaff") == 0 and RaidLogic.ally_rank("starter", "chaff") == 0
		and RaidLogic.ally_rank("raised", "chaff") == 0, "chaff-tier roles rank 0")
	t.ok(RaidLogic.ally_rank("raised", "soldier") == 1 and RaidLogic.ally_rank("raised", "elite") == 2
		and RaidLogic.ally_rank("party", "big") == 3, "soldier 1, elite 2, party 3")
	t.near(RaidLogic.drift_ratio(24, 3), 8.0, 0.0001, "24 moves / 3 raises = 8")
	t.near(RaidLogic.drift_ratio(13, 0), 13.0, 0.0001, "no raises -> the move count")
	t.ok(not RaidLogic.is_drifting(24, 3, cfg), "8:1 is not above 8:1")
	t.ok(RaidLogic.is_drifting(25, 3, cfg), "8.33:1 drifts")
	t.ok(RaidLogic.is_drifting(9, 0, cfg) and not RaidLogic.is_drifting(8, 0, cfg), "no raises: ratio is the moves")
	for nn in [1, 2, 3, 7]:
		var parts := RaidLogic.split_mass(10.0, nn)
		var tot := 0.0
		for pm in parts:
			tot += float(pm)
		t.ok(parts.size() == nn and absf(tot - 10.0) < 1e-9, "split_mass(10, %d) sums to 10" % nn)
	t.ok(RaidLogic.split_mass(0.0, 2) == [0.0, 0.0], "massless splits to zeros")
	t.ok(RaidLogic.split_mass(5.0, 0).size() == 1, "n < 1 is treated as 1")
	t.ok(RaidLogic.carry_room(0, cfg) == 12 and RaidLogic.carry_room(11, cfg) == 1
		and RaidLogic.carry_room(12, cfg) == 0 and RaidLogic.carry_room(20, cfg) == 0, "carry_room against carry_max 12")
	t.ok(int(cfg["essence"]["per_living"]) == 1 and int(cfg["essence"]["per_undead"]) == 1, "essence per-death keys")

	_checkpoint_tests(t, cfg)
	_writeback_tests(t, cfg)
	_held_clear_tests(t, cfg)
	_profile_tests(t, cfg)
	_wall_tests(t, cfg)
	_routing_tests(t, cfg)
	return t.failures


## RaidLogic.profile_seed: BALANCE 3's standard party of tier T at a world.json fort.
func _profile_tests(t: TestUtil, cfg: Dictionary) -> void:
	t.suite("raid_profile_seed")
	var world := TestUtil.load_json("res://configs/world.json")
	var ap: Dictionary = cfg["autopilot"]
	var div := float(cfg["mass"]["garrison_mass_div"])
	var bad := 0
	var first_bad := ""
	for f in world["forts"]:
		for pt in [1, 2, 3, 4]:
			var sd := RaidLogic.profile_seed(f, pt, cfg)
			var errs := Results.validate("raid_seed", sd)
			if not errs.is_empty():
				bad += 1
				first_bad = "%s t%d %s" % [f["id"], pt, str(errs)]
	t.ok(bad == 0, "every world.json fort x party tier 1-4 validates as raid_seed (%s)" % first_bad)
	var fort: Dictionary = {}
	for f in world["forts"]:
		if f["id"] == "pale-bastion":
			fort = f
	var sd3 := RaidLogic.profile_seed(fort, 3, cfg)
	var prof: Dictionary = ap["party_profiles"]["3"]
	t.ok(sd3["fort"]["id"] == "pale-bastion" and sd3["fort"]["name"] == "Pale Bastion" and typeof(sd3["fort"]["tier"]) == TYPE_INT
		and int(sd3["fort"]["tier"]) == 3 and is_equal_approx(float(sd3["fort"]["cap"]), 320.0), "fort id, name, tier (an int) and cap come from world.json")
	t.near(float(sd3["living"]), 320.0 * float(ap["profile_living_frac"]), 1e-6, "living = cap x profile_living_frac")
	t.near(float(sd3["dead"]), 320.0 * float(ap["profile_dead_frac"]), 1e-6, "dead = cap x profile_dead_frac")
	t.ok(int(sd3["garrison_units"]) == int(prof["garrison_units"]) and is_equal_approx(float(sd3["garrison_in_mass"]), int(prof["garrison_units"]) * div)
		and is_equal_approx(float(sd3["undead"]), float(sd3["garrison_in_mass"])), "garrison_in_mass = units x div, and undead matches")
	t.ok((sd3["party"] as Array).size() == (prof["party"] as Array).size() and int(sd3["starter_units"]) == int(prof["starter_units"]), "party and starters from party_profiles[3]")
	t.near(float(sd3["party"][0]["stats"]["beef"]), float(prof["party"][0]["stats"]["beef"]), 1e-6, "party stats are the profile's")
	t.ok(not sd3["fort"]["first_clear"] and not sd3["fort"]["first_dungeon"] and int(sd3["phylactery_charges"]) == 0
		and is_equal_approx(float(sd3["fort"]["yield_mult"]), 1.0), "first_* false, yield_mult 1, no phylactery charge")
	t.ok(sd3["warden"]["archetype"] == "bellringer" and int(sd3["warden"]["tier"]) == 3 and sd3["loot_table_id"] == "t3.bellringer", "warden from wardens.by_fort")
	var hr := {}
	for f in world["forts"]:
		if f["id"] == "hollow-redoubt":
			hr = f
	t.ok(RaidLogic.profile_seed(hr, 3, cfg)["warden"]["archetype"] == "huntsman", "hollow-redoubt fields a huntsman")
	t.ok((RaidLogic.profile_seed(fort, 9, cfg)["party"] as Array).size() == (ap["party_profiles"]["4"]["party"] as Array).size(), "a party tier above 4 clamps to 4")
	var p1 := RaidLogic.profile_seed(fort, 1, cfg)
	var p4 := RaidLogic.profile_seed(fort, 4, cfg)
	t.ok((p1["party"] as Array).size() < (p4["party"] as Array).size() and int(p1["garrison_units"]) <= int(p4["garrison_units"]), "a higher tier brings more")


func _checkpoint_tests(t: TestUtil, cfg: Dictionary) -> void:
	t.suite("raid_checkpoint_exit_death")
	var found := {"relics": 2, "blueprints": ["bp_a"], "husks": [], "remnants": [{"k": 1}], "essence": 99}
	var snap := RaidLogic.loot_snapshot(found, 5)
	t.ok(snap["essence"] == 5 and snap["relics"] == 2 and snap["blueprints"] == ["bp_a"], "snapshot: counts and carried essence")
	t.ok(snap.keys().size() == RaidLogic.empty_loot().keys().size(), "snapshot has the full loot shape")
	(found["blueprints"] as Array).append("bp_b")
	(found["remnants"][0] as Dictionary)["k"] = 9
	t.ok(snap["blueprints"] == ["bp_a"] and snap["remnants"][0]["k"] == 1, "snapshot is a deep copy")
	t.ok(RaidLogic.loot_snapshot({}, 0) == RaidLogic.empty_loot(), "empty found, nothing carried = empty loot")
	var sd := {"phylactery_charges": 1, "phylactery_max_per_dungeon": 1}
	t.ok(RaidLogic.can_revive(0, sd) and not RaidLogic.can_revive(1, sd), "1 charge: one revive")
	t.ok(not RaidLogic.can_revive(0, {"phylactery_charges": 0, "phylactery_max_per_dungeon": 1}), "0 charges: none")
	t.ok(not RaidLogic.can_revive(1, {"phylactery_charges": 3, "phylactery_max_per_dungeon": 1}), "capped by max_per_dungeon")
	t.ok(RaidLogic.can_revive(1, {"phylactery_charges": 3, "phylactery_max_per_dungeon": 2})
		and not RaidLogic.can_revive(2, {"phylactery_charges": 3, "phylactery_max_per_dungeon": 2}), "max 2 of 3 charges")
	var radius := float(cfg.get("exits", {}).get("radius_px", 120.0))
	t.ok(radius == 120.0, "exits.radius_px is 120")
	var lay := RaidLogic.gen_layout("old-sluice", 2, false, cfg)
	var doors: Array = lay["doors"]
	t.ok(RaidLogic.near_exit(lay, doors[0]["inner"], radius) == 0, "standing on an exit's inner point is near it")
	var far := Vector2(-5000, -5000)
	t.ok(RaidLogic.near_exit(lay, far, radius) == -1, "far away is near no exit")
	var edge: Vector2 = doors[0]["inner"] + Vector2(radius + 1.0, 0)
	var nd := RaidLogic.near_exit({"doors": [doors[0]]}, edge, radius)
	t.ok(nd == -1, "just outside the radius is not near")
	t.ok(RaidLogic.near_exit({"doors": [doors[0]]}, doors[0]["inner"] + Vector2(radius - 1.0, 0), radius) == 0, "just inside the radius is near")
	t.ok(RaidLogic.near_exit({"doors": [{"inner": Vector2.ZERO}]}, Vector2.ZERO, radius) == -1, "a door without exit: true never counts")
	t.ok(RaidLogic.near_exit({"doors": [{"exit": true, "inner": Vector2(0, 0)}, {"exit": true, "inner": Vector2(50, 0)}]},
		Vector2(40, 0), radius) == 1, "nearest exit wins")
	var two := {"checkpoints": [0, 3]}
	t.ok(RaidLogic.checkpoint_entered(two, 1, 3) and not RaidLogic.checkpoint_entered(two, 3, 3)
		and not RaidLogic.checkpoint_entered(two, 0, 1) and not RaidLogic.checkpoint_entered(two, 3, -1), "checkpoint_entered on room change into a checkpoint")
	var room := Rect2(100, 100, 200, 200)
	t.ok(RaidLogic.wall_touches_room(Rect2(70, 100, 30, 200), room) and RaidLogic.wall_touches_room(Rect2(150, 90, 40, 10), room)
		and not RaidLogic.wall_touches_room(Rect2(400, 100, 30, 200), room), "wall_touches_room: flush yes, far no")
	# the retreat and death results validate
	var rs := RaidLogic.demo_seed(cfg)
	var lg2 := RaidLogic.LedgerV2.new(rs, cfg)
	var res := lg2.build_result(rs, "relish_died", [], [], 1, snap, cfg)
	t.ok(res["revived_in_place"] == 1 and res["loot"]["essence"] == 5, "result carries revives and the snapshot")
	# motes circled into undead after a checkpoint are spent: the snapshot's essence is capped at what is carried
	var banked := RaidLogic.loot_snapshot({"relics": 1}, 6)
	var cl := RaidLogic.clamp_banked_essence(banked, 2)
	t.ok(cl["essence"] == 2 and cl["relics"] == 1 and banked["essence"] == 6, "clamp_banked_essence caps essence, keeps the rest, copies")
	t.ok(RaidLogic.clamp_banked_essence(banked, 9)["essence"] == 6, "clamp_banked_essence never raises essence")
	t.ok(RaidLogic.clamp_banked_essence(banked, 0)["essence"] == 0 and RaidLogic.clamp_banked_essence(banked, -3)["essence"] == 0,
		"clamp_banked_essence floors at zero")
	t.ok(RaidLogic.clamp_banked_essence({}, 3) == {}, "clamp_banked_essence leaves an empty snapshot empty")
	t.ok(RaidLogic.revives_left(0, sd) == 1 and RaidLogic.revives_left(1, sd) == 0 and RaidLogic.revives_left(5, sd) == 0
		and RaidLogic.revives_left(1, {"phylactery_charges": 3, "phylactery_max_per_dungeon": 2}) == 1, "revives_left")


func _role_tests(t: TestUtil, cfg: Dictionary, cell: float) -> void:
	t.suite("raid_roles")
	var world := TestUtil.load_json("res://configs/world.json")
	var lcfg: Dictionary = cfg.get("layout", {})
	var cps: Dictionary = lcfg.get("checkpoints_by_tier", {})
	var delta := int(lcfg.get("held_rooms_delta", 1))
	for f in world["forts"]:
		var fid := str(f["id"])
		for tier in [1, 2, 3, 4]:
			for held in [false, true]:
				var label := "%s t%d%s" % [fid, tier, " held" if held else ""]
				var lay := RaidLogic.gen_layout(fid, tier, false, cfg, {"held": held})
				t.ok(RaidLogic.layout_reachable(lay, cell), "%s: reachable" % label)
				var cks: Array = lay["checkpoints"]
				var roles: Array = lay["roles"]
				var rooms: Array = lay["rooms"]
				t.ok(bool(lay["held"]) == held, "%s: held flag" % label)
				t.ok(not cks.is_empty() and roles[cks[0]] == "spawn"
					and cks[0] == RaidLogic.room_of(lay, lay["spawn"]), "%s: spawn room is checkpoints[0]" % label)
				t.ok(cks.size() <= 1 + int(cps.get(str(tier), 0)), "%s: checkpoint count (%d)" % [label, cks.size()])
				t.ok((lay["doors"] as Array).size() == cks.size(), "%s: one exit per checkpoint" % label)
				var doors_ok := true
				for d in lay["doors"]:
					doors_ok = doors_ok and bool(d.get("exit", false)) and cks.has(int(d.get("room", -1)))
				t.ok(doors_ok, "%s: every door is an exit of a checkpoint" % label)
				var wr := int(lay["warden_room"])
				if held:
					t.ok(wr == -1 and int(lay["ante_room"]) == -1 and not roles.has("warden"), "%s: no warden" % label)
					t.ok(rooms.size() == maxi(2, 2 + tier - delta), "%s: held room count (%d)" % [label, rooms.size()])
				else:
					var ar := int(lay["ante_room"])
					var adj: Array = lay["adj"]
					var hops: Array = lay["hops"]
					t.ok(wr >= 0 and ar >= 0 and wr != cks[0] and ar != cks[0], "%s: W and A are not spawn" % label)
					t.ok(wr >= 0 and adj[wr] == [ar], "%s: adj[W] == [A]" % label)
					t.ok(wr >= 0 and hops[wr] >= 2 and hops[wr] == hops[ar] + 1, "%s: warden hops" % label)
					var wdoor := false
					for d in lay["doors"]:
						wdoor = wdoor or int(d["room"]) == wr
					t.ok(not wdoor, "%s: no door in the warden room" % label)
					t.ok(roles.count("warden") == 1 and roles.count("antechamber") == 1, "%s: one warden, one antechamber" % label)
					t.ok(rooms.size() == 2 + tier, "%s: room count" % label)
				var again := RaidLogic.gen_layout(fid, tier, false, cfg, {"held": held})
				t.ok(again["walls"] == lay["walls"] and again["doors"] == lay["doors"]
					and again["roles"] == lay["roles"] and again["spawn"] == lay["spawn"],
					"%s: deterministic" % label)


## A day1 session at old-sluice with a dungeon run open; returns the seed.
func _wb_open(t: TestUtil, s: GameState) -> Dictionary:
	var r := s.cmd_begin_dungeon("old-sluice")
	t.ok(r["ok"], "begin_dungeon old-sluice (%s)" % str(r["reason"]))
	return r["seed"]


## The scene's result for `seed`: kills and raises through the real LedgerV2.
func _wb_result(sd: Dictionary, cfg: Dictionary, exit: String, killed: float, raises: Array, survivors: Array,
		revived: int, carried: int) -> Dictionary:
	var lg := RaidLogic.LedgerV2.new(sd, cfg)
	lg.on_kill(killed)
	for rz in raises:
		lg.on_raise(int(rz[0]), float(rz[1]), int(rz[2]))
	var loot := RaidLogic.loot_snapshot({}, carried)
	return lg.build_result(sd, exit, survivors, [], revived, loot, cfg)


func _writeback_tests(t: TestUtil, cfg: Dictionary) -> void:
	t.suite("raid_writeback")
	var s := GameState.new(TestUtil.configs())
	s.debug_enabled = true
	t.ok(s.cmd_debug_load_fixture("day1")["ok"], "day1 loads")
	t.ok(s.cmd_debug_set_state({"relish_at": "old-sluice"})["ok"], "relish_at old-sluice")
	var sd := _wb_open(t, s)
	var f0 := s.view_fort("old-sluice")
	var ess0 := s.essence

	# (a) a retreat with kills, raises, and survivors of each role
	var gin := float(sd["garrison_in_mass"])
	var killed := minf(10.0, float(f0["living"]))
	var surv: Array = [{"role": "garrison", "tier": "chaff", "mass": gin},
		{"role": "raised", "tier": "chaff", "mass": 4.0}, {"role": "raised", "tier": "soldier", "mass": 2.0},
		{"role": "starter", "tier": "chaff", "mass": 0.0}, {"role": "party", "tier": "big", "mass": 0.0}]
	var ra := _wb_result(sd, cfg, "retreated", killed, [[70, 4.0, 4], [95, 2.0, 1]], surv, 0, 3)
	t.ok(Results.validate("raid", ra) == [], "the retreat result validates (%s)" % str(Results.validate("raid", ra)))
	t.ok(ra["retreated"] and not ra["relish_died"] and ra["revived_in_place"] == 0 and ra["loot"]["essence"] == 3,
		"retreat: no death, no revives, 3 essence banked")
	s.drain_events()
	var out := s.apply_result("raid", ra)
	t.ok(out["ok"] and out["reason"] == "", "the retreat applies (%s)" % str(out))
	var f1 := s.view_fort("old-sluice")
	t.ok(float(f1["living"]) <= float(f0["living"]) + 1e-9 and absf(float(f0["living"]) - float(f1["living"]) - killed) < 1e-6,
		"kills come off the fort's living (%.2f -> %.2f)" % [float(f0["living"]), float(f1["living"])])
	var raised_mass := 6.0
	var dead_gain := killed - minf(raised_mass, float(f0["dead"]) + killed)
	t.ok(absf(float(f1["dead"]) - (float(f0["dead"]) + dead_gain)) < 1e-6,
		"dead = dead + kills - raised (%.2f -> %.2f)" % [float(f0["dead"]), float(f1["dead"])])
	var want_u := maxf(0.0, float(f0["undead"]) + float(ra["garrison_mass"]) - gin)
	t.ok(absf(float(f1["undead"]) - want_u) < 1e-6, "undead moves by garrison_mass - garrison_in_mass (%.2f -> %.2f)" % [float(f0["undead"]), float(f1["undead"])])
	var evs := s.drain_events()
	var banked_ev := {}
	for e in evs:
		if e["type"] == "loot_banked":
			banked_ev = e
	t.ok(not banked_ev.is_empty() and banked_ev["essence"] == mini(3, 60 - ess0) and s.essence == ess0 + int(banked_ev["essence"]),
		"loot_banked essence matches the result's carried essence (%s)" % str(banked_ev.get("essence")))
	t.ok(s.run.is_empty() and s.view_relish()["state"] == "at_fort", "the run closed and Relish stays at the fort")

	# (b) a death with no revives: the result carries the last checkpoint's essence
	s.realm.fort_by_id("old-sluice")["undead"] = 25.0   # two garrison units go in, so a death must cost undead
	var sd2 := _wb_open(t, s)
	t.ok(float(sd2["garrison_in_mass"]) == 20.0, "the second seed takes in two garrison units (20 mass)")
	var f2 := s.view_fort("old-sluice")
	var ess1 := s.essence
	var banked := RaidLogic.loot_snapshot({}, 5)
	banked = RaidLogic.clamp_banked_essence(banked, 2)   # 3 of the 5 were circled away after the checkpoint
	var lg := RaidLogic.LedgerV2.new(sd2, cfg)
	var killed2 := minf(4.0, float(f2["living"]))
	lg.on_kill(killed2)
	var rb := lg.build_result(sd2, "relish_died", [], [], 0, banked, cfg)
	t.ok(Results.validate("raid", rb) == [] and rb["relish_died"] and rb["revived_in_place"] == 0 and rb["loot"]["essence"] == 2,
		"the death result validates: essence is only what was still carried (2)")
	s.drain_events()
	out = s.apply_result("raid", rb)
	t.ok(out["ok"], "the death applies (%s)" % str(out))
	var f3 := s.view_fort("old-sluice")
	t.ok(absf(float(f2["living"]) - float(f3["living"]) - killed2) < 1e-6 and float(f3["dead"]) >= float(f2["dead"]) - 1e-9,
		"death: kills still move living to dead")
	var want_u2 := maxf(0.0, float(f2["undead"]) - float(sd2["garrison_in_mass"]))
	t.ok(float(f3["undead"]) < float(f2["undead"]) and absf(float(f3["undead"]) - want_u2) < 1e-6, "death: no survivors, so undead drops by the garrison that went in (%.2f -> %.2f)" % [float(f2["undead"]), float(f3["undead"])])
	var died := false
	var essence_ev := -1
	for e in s.drain_events():
		died = died or e["type"] == "relish_died"
		if e["type"] == "loot_banked":
			essence_ev = int(e["essence"])
	t.ok(died and essence_ev == mini(2, 60 - ess1) and s.essence == ess1 + essence_ev,
		"relish_died emitted, loot_banked essence is the clamped 2 (%d)" % essence_ev)

	# (c) a revive the seed has no charge for is refused: the scene must never revive without charges
	s.cmd_debug_set_state({"relish_at": "old-sluice"})
	var sd3 := _wb_open(t, s)
	t.ok(int(sd3["phylactery_charges"]) == 0, "day1 has no phylactery charges")
	var rc := _wb_result(sd3, cfg, "relish_died", 0.0, [], [], 1, 0)
	var rev := s.rev
	out = s.apply_result("raid", rc)
	t.ok(not out["ok"] and out["reason"] == "bad_revives" and s.rev == rev and not s.run.is_empty(),
		"revived_in_place 1 with 0 charges is bad_revives and changes nothing (%s)" % str(out["reason"]))
	t.ok(not RaidLogic.can_revive(0, sd3), "the scene's can_revive agrees: no charge, no revive")


## The idle rules (IDLE.md I3, I5): the held-fort raid's clear, and "no run survives a close".
func _held_clear_tests(t: TestUtil, cfg: Dictionary) -> void:
	t.suite("raid_held_clear")
	var h: Dictionary = cfg.get("held", {})
	t.ok(float(h.get("clear_victory_s", 0.0)) >= 1.0 and float(h.get("banner_s", 0.0)) > 0.0, "raid.json held keys: clear_victory_s, banner_s")
	# the predicate: held, not the boss, no living left, not already started
	t.ok(RaidLogic.held_clear_due(true, false, 0, false), "held, nothing living left, not started: the clear is due")
	t.ok(not RaidLogic.held_clear_due(true, false, 1, false), "one living left: not due")
	t.ok(not RaidLogic.held_clear_due(false, false, 0, false), "a fort that is not held never clears this way")
	t.ok(not RaidLogic.held_clear_due(true, true, 0, false), "the boss arena never clears this way")
	t.ok(not RaidLogic.held_clear_due(true, false, 0, true), "once started it never fires twice")
	# a held fort with no living at the build has no last kill: it clears after held.empty_clear_s
	var ecs := float(h.get("empty_clear_s", -1.0))
	t.ok(ecs > 0.0 and ecs < float(h.get("clear_victory_s", 0.0)), "raid.json held.empty_clear_s is a short positive delay: %s" % ecs)
	t.near(RaidLogic.held_empty_clear_s(true, false, 0, cfg), ecs, 1e-6, "held, no living spawned: clears after empty_clear_s")
	t.ok(RaidLogic.held_empty_clear_s(true, false, 3, cfg) < 0.0, "held with living: the last kill clears it, not the timer")
	t.ok(RaidLogic.held_empty_clear_s(false, false, 0, cfg) < 0.0, "not held: no empty clear")
	t.ok(RaidLogic.held_empty_clear_s(true, true, 0, cfg) < 0.0, "the boss arena: no empty clear")
	t.near(RaidLogic.held_empty_clear_s(true, false, 0, {}), 1.0, 1e-6, "a config without the key falls back to 1 s")
	t.ok(RaidLogic.held_banner("Old Sluice") == "COUNTER-GARRISON CLEARED · Old Sluice holds", "banner text: " + RaidLogic.held_banner("Old Sluice"))
	t.ok(RaidLogic.held_banner("") == "COUNTER-GARRISON CLEARED", "no name, no 'holds'")
	t.ok(RaidLogic.held_motes({"essence": 3}) == 3 and RaidLogic.held_motes({}) == 0 and RaidLogic.held_motes({"essence": -2}) == 0, "held_motes is the bonus count, never negative")

	# merging the held-clear roll: items join found_loot, the essence bonus is spawned, not merged
	var lcfg := TestUtil.load_json("res://configs/loot.json")
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var hc := RaidLoot.held_clear(rng, 2, 1.0, lcfg)
	var found := {"relics": 1, "remnants": [{"aspect": "power", "rarity": "common", "magnitude": 1}]}
	var merged := RaidLogic.merge_loot(found, hc)
	t.ok(int(merged["relics"]) == 1 + int(hc["relics"]) and (merged["remnants"] as Array).size() == 1 + (hc["remnants"] as Array).size(),
		"held_clear items merge into found_loot")
	t.ok(not merged.has("essence") or int(merged["essence"]) == 0, "the held_clear essence is not merged (the motes carry it)")

	t.ok(RaidLogic.held_payoff(hc) == "+%d relics · +%d remnants · +%d essence" % [int(hc["relics"]), (hc["remnants"] as Array).size(), int(hc["essence"])],
		"payoff line counts the roll: " + RaidLogic.held_payoff(hc))

	# the result of a held clear validates: retreated, loot = found + held items + carried bonus motes
	var seed_d := RaidLogic.demo_seed(cfg)
	var carried := int(hc["essence"]) + 2
	var loot := RaidLogic.loot_snapshot(merged, carried)
	for ex in ["retreated", "relish_died"]:
		var lg := RaidLogic.LedgerV2.new(seed_d, cfg)
		lg.on_kill(float(seed_d.get("living", 20.0)))
		lg.on_raise(70, 3.0, 2)
		var surv: Array = [{"role": "garrison", "tier": "chaff", "mass": float(seed_d.get("garrison_in_mass", 0.0))},
			{"role": "raised", "tier": "chaff", "mass": 3.0}, {"role": "starter", "tier": "chaff", "mass": 0.0}]
		var r := lg.build_result(seed_d, ex, surv, [], 0, loot if ex == "retreated" else RaidLogic.close_loot({}), cfg)
		t.ok(Results.validate("raid", r) == [], "held clear (%s) validates: %s" % [ex, str(Results.validate("raid", r))])
		if ex == "retreated":
			t.ok(r["retreated"] and not r["relish_died"] and not r["warden_beaten"] and int(r["loot"]["essence"]) == carried
				and int(r["loot"]["relics"]) == int(merged["relics"]), "held clear pays the found loot and the carried essence")

	# I5, the close stand-in: loot is the last checkpoint snapshot, not what was found since
	t.suite("raid_close_loot")
	var banked := RaidLogic.loot_snapshot({"relics": 1, "remnants": [{"aspect": "beef", "rarity": "common", "magnitude": 1}]}, 2)
	var later := RaidLogic.merge_loot(banked, {"relics": 3, "husks": [{"kind": "skeleton"}]})
	var snap_now := RaidLogic.loot_snapshot(later, 7)
	var cl := RaidLogic.close_loot(banked)
	t.ok(cl == banked, "close loot equals the banked snapshot")
	t.ok(cl != snap_now and int(cl["relics"]) == 1 and int(cl["essence"]) == 2 and (cl["husks"] as Array).is_empty(),
		"loot found since the checkpoint is lost, even when more was found")
	(cl["remnants"] as Array).append({"aspect": "wits", "rarity": "rare", "magnitude": 2})
	cl["relics"] = 99
	t.ok((banked["remnants"] as Array).size() == 1 and int(banked["relics"]) == 1, "close loot is a deep copy")
	t.ok(RaidLogic.close_loot({}) == RaidLogic.empty_loot(), "no checkpoint yet: close loot is the empty loot shape")

	# the writeback, on the real state (day1 fixture)
	t.suite("raid_close_writeback")
	var s := GameState.new(TestUtil.configs())
	s.debug_enabled = true
	t.ok(s.cmd_debug_load_fixture("day1")["ok"], "day1 loads")
	s.cmd_debug_set_state({"relish_at": "old-sluice"})
	var o1 := s.cmd_begin_dungeon("old-sluice")
	t.ok(o1["ok"], "begin_dungeon")
	var sd: Dictionary = o1["seed"]
	var f0 := s.view_fort("old-sluice")
	# (a) a held-style retreat: every living killed clears the counter-garrison
	var lg2 := RaidLogic.LedgerV2.new(sd, cfg)
	lg2.on_kill(float(f0["living"]))
	var hl := RaidLogic.loot_snapshot(RaidLogic.merge_loot({}, hc), int(hc["essence"]))
	var rh := lg2.build_result(sd, "retreated", [{"role": "garrison", "tier": "chaff", "mass": float(sd["garrison_in_mass"])}], [], 0, hl, cfg)
	t.ok(Results.validate("raid", rh) == [], "held-style retreat validates: " + str(Results.validate("raid", rh)))
	var out := s.apply_result("raid", rh)
	t.ok(out["ok"], "held-style retreat applies (%s)" % str(out))
	var f1 := s.view_fort("old-sluice")
	t.ok(float(f1["living"]) < 1e-6, "the fort's living drops to about 0 (%.4f -> %.4f)" % [float(f0["living"]), float(f1["living"])])
	t.ok(s.run.is_empty() and s.view_relish()["state"] == "at_fort", "run closed, Relish at the fort")
	# (b) a close-style retreat: the snapshot loot, applies ok
	s.cmd_debug_set_state({"relish_at": "old-sluice"})
	var o2 := s.cmd_begin_dungeon("old-sluice")
	t.ok(o2["ok"], "begin_dungeon again (%s)" % str(o2["reason"]))
	var sd2: Dictionary = o2["seed"]
	var lg3 := RaidLogic.LedgerV2.new(sd2, cfg)
	lg3.on_kill(minf(3.0, float(s.view_fort("old-sluice")["living"])))
	var ess_before := s.essence
	var rc := lg3.build_result(sd2, "retreated", [{"role": "starter", "tier": "chaff", "mass": 0.0}], [], 0, RaidLogic.close_loot(banked), cfg)
	t.ok(Results.validate("raid", rc) == [] and rc["retreated"] and not rc["relish_died"] and int(rc["loot"]["essence"]) == 2,
		"close-style retreat validates and carries the snapshot essence")
	out = s.apply_result("raid", rc)
	t.ok(out["ok"], "close-style retreat applies (%s)" % str(out))
	t.ok(s.run.is_empty() and s.view_relish()["state"] == "at_fort" and s.essence == ess_before + 2, "run closed, the snapshot's 2 essence banked")


func _wall_tests(t: TestUtil, cfg: Dictionary) -> void:
	t.suite("raid_walls")
	var flush := LayoutLogic.merge_walls([Rect2(0, 100, 150, 30), Rect2(150, 100, 80, 30)])
	t.ok(flush == [Rect2(0, 100, 230, 30)], "two flush horizontal rects merge into one (%s)" % str(flush))
	var overlap := LayoutLogic.merge_walls([Rect2(0, 100, 150, 30), Rect2(100, 100, 150, 30)])
	t.ok(overlap == [Rect2(0, 100, 250, 30)], "overlapping horizontal rects merge")
	var gap := LayoutLogic.merge_walls([Rect2(0, 100, 150, 30), Rect2(160, 100, 80, 30)])
	t.ok(gap.size() == 2, "a gap between them keeps two rects")
	var vert := LayoutLogic.merge_walls([Rect2(40, 0, 30, 100), Rect2(40, 100, 30, 60), Rect2(40, 160, 30, 40)])
	t.ok(vert == [Rect2(40, 0, 30, 200)], "a chain of flush vertical rects merges into one (%s)" % str(vert))
	var perp := LayoutLogic.merge_walls([Rect2(0, 100, 150, 30), Rect2(150, 100, 30, 150)])
	t.ok(perp.size() == 2 and perp.has(Rect2(0, 100, 150, 30)) and perp.has(Rect2(150, 100, 30, 150)), "perpendicular rects are untouched")
	var thick := LayoutLogic.merge_walls([Rect2(0, 100, 150, 30), Rect2(150, 100, 80, 20)])
	var off := LayoutLogic.merge_walls([Rect2(0, 100, 150, 30), Rect2(150, 130, 80, 30)])
	t.ok(thick.size() == 2 and off.size() == 2, "different thickness or a different line is not merged")
	t.ok(RaidLogic.merge_walls([Rect2(0, 0, 10, 4), Rect2(10, 0, 10, 4)]).size() == 1, "RaidLogic delegates merge_walls")
	# on real layouts: merging never grows the wall area, keeps real door gaps open, and shrinks the count
	var world := TestUtil.load_json("res://configs/world.json")
	var merged_any := false
	for f in world["forts"]:
		var lay := RaidLogic.gen_layout(str(f["id"]), 3, false, cfg)
		var walls: Array = lay["walls"]
		var m := LayoutLogic.merge_walls(walls)
		merged_any = merged_any or m.size() < walls.size()
		var open_ok := true
		for d in lay["doors"]:
			for w in m:
				open_ok = open_ok and not (w as Rect2).grow(-1.0).intersects((d["rect"] as Rect2).grow(-1.0))
		t.ok(m.size() <= walls.size() and open_ok, "%s: merged walls keep every real door gap open" % str(f["id"]))
		var same := true
		var size: Vector2 = lay["size"]
		for gy in range(0, int(size.y), 13):
			for gx in range(0, int(size.x), 13):
				var pt := Vector2(gx + 0.5, gy + 0.5)
				var in_a := false
				var in_b := false
				for w in walls:
					in_a = in_a or (w as Rect2).has_point(pt)
				for w in m:
					in_b = in_b or (w as Rect2).has_point(pt)
				same = same and in_a == in_b
		t.ok(same, "%s: the merged walls cover exactly the same ground" % str(f["id"]))
	t.ok(merged_any, "at least one fort has flush rects to merge (closed doors / sealed gaps)")

	t.suite("raid_antechamber")
	var seen := 0
	var roles_ok := true
	for i in 200:
		var lay := RaidLogic.gen_layout("ante-%d" % i, 1 + i % 4, false, cfg)
		var ar := int(lay["ante_room"])
		if ar >= 0 and (lay["checkpoints"] as Array).has(ar):
			seen += 1
			roles_ok = roles_ok and lay["roles"][ar] == "antechamber"
	t.ok(seen > 0, "some layouts put the antechamber on a checkpoint (%d of 200)" % seen)
	t.ok(roles_ok, "an antechamber that is also a checkpoint keeps the role \"antechamber\"")


func _first_pile_tests(t: TestUtil, cfg: Dictionary) -> void:
	t.suite("raid_first_pile")
	var world := TestUtil.load_json("res://configs/world.json")
	var px := float(cfg["layout"].get("first_pile_px", 0.0))
	var stir := float(cfg["essence"].get("stir_radius_px", 90.0))
	t.ok(px >= 150.0 and px <= 260.0, "layout.first_pile_px is about 220 (%f)" % px)
	var n := 0
	var near_ok := true
	var room_ok := true
	var wall_ok := true
	var ante_ok := true
	var same_ok := true
	var det_ok := true
	var off_ok := true
	var count_ok := true
	for f in world["forts"]:
		var id := str(f["id"])
		var plain := RaidLogic.gen_layout(id, 1, false, cfg)
		var lay := RaidLogic.gen_layout(id, 1, false, cfg, {"first_dungeon": true})
		var spawn: Vector2 = lay["spawn"]
		same_ok = same_ok and lay["spawn"] == plain["spawn"] and lay["rooms"] == plain["rooms"] and lay["walls"] == plain["walls"]
		var piles := RaidLogic.populate_piles(id, lay, 4)
		var base := RaidLogic.populate_piles(id, plain, 4)
		off_ok = off_ok and base.size() == 4 and not (plain.has("first_dungeon") and bool(plain["first_dungeon"]))
		count_ok = count_ok and piles.size() == 4
		det_ok = det_ok and piles == RaidLogic.populate_piles(id, lay, 4)
		var sroom := RaidLogic.room_of(lay, spawn)
		var found := 0
		for p in piles:
			var d: float = (p as Vector2).distance_to(spawn)
			if d <= px + 0.01 and d > stir and RaidLogic.room_of(lay, p) == sroom:
				found += 1
				for w in lay["walls"]:
					wall_ok = wall_ok and not (w as Rect2).has_point(p)
		near_ok = near_ok and found >= 1
		var ar := int(lay["ante_room"])
		if ar >= 0:
			var room: Rect2 = (lay["rooms"] as Array)[ar]
			var inner := room.grow(-60.0) if room.size.x > 180.0 and room.size.y > 180.0 else room.grow(-24.0)
			ante_ok = ante_ok and inner.grow(0.001).has_point(piles[0])
		n += 1
		# without the flag the base placement is unchanged by a flagged call elsewhere
		room_ok = room_ok and RaidLogic.populate_piles(id, plain, 4) == base
	t.ok(n == 12, "all 12 forts checked at tier 1 (%d)" % n)
	t.ok(near_ok, "first dungeon: a pile in the spawn room within first_pile_px of spawn, outside the stir radius")
	t.ok(wall_ok, "the near-spawn pile is never inside a wall")
	t.ok(ante_ok, "the antechamber pile is kept")
	t.ok(same_ok, "the flag changes no layout geometry")
	t.ok(det_ok and room_ok, "pile placement stays deterministic")
	t.ok(off_ok, "without the flag there is no first pile bookkeeping")
	t.ok(count_ok, "the near-spawn pile replaces one pile (count unchanged)")
	var held := RaidLogic.gen_layout("ashgate", 1, false, cfg, {"held": true, "first_dungeon": true})
	t.ok(RaidLogic.populate_piles("ashgate", held, 3).size() == 3, "held layout ignores the first-dungeon flag")


func _ghost_ring_tests(t: TestUtil) -> void:
	t.suite("raid_ghost_ring")
	var rel := Vector2(100, 100)
	var g := RaidLogic.ghost_ring([], rel, 300.0, 14.0)
	t.ok(not bool(g["ok"]), "no motes: not ok")
	g = RaidLogic.ghost_ring([Vector2(900, 900)], rel, 300.0, 14.0)
	t.ok(not bool(g["ok"]), "all motes out of reach: not ok")
	g = RaidLogic.ghost_ring([Vector2(150, 100)], rel, 300.0, 14.0)
	t.ok(bool(g["ok"]) and (g["center"] as Vector2).is_equal_approx(Vector2(150, 100)), "one mote: centred on it")
	t.near(float(g["radius"]), 14.0, 0.001, "one mote: the radius is the pad")
	var pts: Array = [Vector2(100, 100), Vector2(200, 100), Vector2(150, 200), Vector2(1000, 1000)]
	g = RaidLogic.ghost_ring(pts, rel, 300.0, 10.0)
	var c := (Vector2(100, 100) + Vector2(200, 100) + Vector2(150, 200)) / 3.0
	t.ok((g["center"] as Vector2).is_equal_approx(c), "centroid of the motes within reach only")
	var far := maxf(maxf(c.distance_to(Vector2(100, 100)), c.distance_to(Vector2(200, 100))), c.distance_to(Vector2(150, 200)))
	t.near(float(g["radius"]), far + 10.0, 0.001, "radius = farthest in-reach mote + pad")
	t.ok(int(g["count"]) == 3, "count of the motes inside the ring")
	var edge := RaidLogic.ghost_ring([Vector2(400, 100)], rel, 300.0, 5.0)
	t.ok(bool(edge["ok"]), "a mote exactly at reach counts")
	var typed: Array[Vector2] = [Vector2(120, 100)]
	t.ok(bool(RaidLogic.ghost_ring(typed, rel, 300.0, 5.0)["ok"]), "accepts a typed array")


func _unbanked_tests(t: TestUtil) -> void:
	t.suite("raid_unbanked")
	var banked := {"relics": 1, "blueprints": [], "husks": [{"kind": "skeleton"}], "remnants": [{"aspect": "power"}], "essence": 3}
	var found := {"relics": 3, "blueprints": ["embalmer"], "husks": [{"kind": "skeleton"}], "remnants": [{"a": 1}, {"a": 2}, {"a": 3}]}
	var u := RaidLogic.unbanked(found, 5, banked)
	t.ok(int(u["relics"]) == 2 and int(u["remnants"]) == 2 and int(u["husks"]) == 0 and int(u["blueprints"]) == 1, "item counts are found minus banked")
	t.ok(int(u["essence"]) == 2, "essence = carried - banked essence")
	t.ok(int(u["items"]) == 5 and int(u["total"]) == 7, "items excludes essence, total includes it")
	var z := RaidLogic.unbanked(found, 0, banked)
	t.ok(int(z["essence"]) == 0, "essence never goes negative")
	var all := RaidLogic.unbanked(found, 4, {})
	t.ok(int(all["relics"]) == 3 and int(all["remnants"]) == 3 and int(all["essence"]) == 4, "an empty banked snapshot counts as zeros")
	var none := RaidLogic.unbanked({}, 0, {})
	t.ok(int(none["total"]) == 0, "nothing found: nothing unbanked")
	var even := RaidLogic.unbanked({"relics": 1, "remnants": [{"a": 1}]}, 2, {"relics": 1, "remnants": [{"a": 1}], "essence": 2})
	t.ok(int(even["total"]) == 0, "a checkpoint with nothing since leaves nothing at stake")
	var over := RaidLogic.unbanked({"relics": 0}, 0, {"relics": 4, "essence": 9})
	t.ok(int(over["total"]) == 0, "banked above found clamps to zero")
	var b := RaidLogic.loot_counts(banked)
	t.ok(int(b["relics"]) == 1 and int(b["husks"]) == 1 and int(b["remnants"]) == 1 and int(b["essence"]) == 3 and int(b["total"]) == 6, "loot_counts reads a banked snapshot")
	t.ok(int(RaidLogic.loot_counts({})["total"]) == 0, "loot_counts of nothing is zero")


# ----------------------------------------------------------- room-graph routing ----
func _routing_tests(t: TestUtil, cfg: Dictionary) -> void:
	t.suite("raid_routing")
	var cc: Dictionary = cfg["combat"]
	# the per-mover stagger is a sequence: reset_seq (the raid calls it at build) replays it, so two
	# same-seed raids in one process stagger alike
	RaidRoute.reset_seq()
	var st_a: Array[float] = []
	for i in 7:
		st_a.append(RaidRoute.new(cc).stagger())
	RaidRoute.new(cc)   # a stray mover between raids
	RaidRoute.reset_seq()
	var st_b: Array[float] = []
	for i in 7:
		st_b.append(RaidRoute.new(cc).stagger())
	t.ok(st_a == st_b, "RaidRoute.reset_seq replays the stagger sequence: %s vs %s" % [str(st_a), str(st_b)])
	t.ok(st_a[0] != st_a[1], "consecutive movers are staggered apart")
	# a target in a doorway band of the mover's own room, hidden behind a jamb, routes via its doorstep
	# (hollow-redoubt t3: Relish at the corner of the room-0 jamb, the room 0 -> 4 gap centre past it)
	var hr := LayoutLogic.gen_layout("hollow-redoubt", 3, false, cfg, {"held": false, "first_dungeon": false})
	var jam_from := Vector2(1230, 730)
	var jam_to := Vector2(1451, 714)
	var jr := LayoutLogic.room_of(hr, jam_from)
	t.ok(jr >= 0 and LayoutLogic.room_of(hr, jam_to) < 0 and not LayoutLogic.line_clear(hr, jam_from, jam_to, 13.0),
		"fixture: the mover is in a room, the target in a band, a jamb between")
	var jw := LayoutLogic.waypoint(hr, jam_from, jam_to, 13.0, float(cc["route_door_pad_px"]))
	t.ok(jw != jam_to and (hr["rooms"][jr] as Rect2).has_point(jw) and LayoutLogic.line_clear(hr, jw, jam_to, 13.0),
		"a band target behind a jamb routes to the doorstep in the mover's room, clear of the jamb: %s" % str(jw))
	t.ok(LayoutLogic.waypoint(hr, jw, jam_to, 13.0, float(cc["route_door_pad_px"])) == jam_to, "from the doorstep it goes straight in")
	var pad := float(cc["route_door_pad_px"])
	# line_clear on a hand-made layout: one wall rect at x 100..130, y 0..200
	var toy := {"inner_walls": [Rect2(100, 0, 30, 200)]}
	t.ok(not LayoutLogic.line_clear(toy, Vector2(50, 100), Vector2(200, 100), 0.0), "line_clear: a segment through a wall is blocked")
	t.ok(LayoutLogic.line_clear(toy, Vector2(50, 100), Vector2(90, 100), 0.0), "line_clear: stopping short is clear")
	t.ok(LayoutLogic.line_clear(toy, Vector2(50, 250), Vector2(200, 250), 0.0), "line_clear: passing below the wall is clear")
	t.ok(not LayoutLogic.line_clear(toy, Vector2(50, 210), Vector2(200, 210), 15.0), "line_clear: radius inflates the wall")
	t.ok(LayoutLogic.line_clear(toy, Vector2(90, 10), Vector2(90, 190), 6.0), "line_clear: running along a wall face outside the radius is clear")
	t.ok(LayoutLogic.line_clear(toy, Vector2(85, 10), Vector2(85, 190), 15.5), "line_clear: a unit parked on the grown edge slides clear")
	t.ok(not LayoutLogic.line_clear(toy, Vector2(115, 10), Vector2(115, 190), 0.0), "line_clear: a vertical segment inside the wall is blocked")
	t.ok(LayoutLogic.line_clear({}, Vector2.ZERO, Vector2(9, 9), 5.0), "line_clear: no walls is always clear")

	var world := TestUtil.load_json("res://configs/world.json")
	var forts: Array = world["forts"]
	var layouts := 0
	var bad_tables := 0
	var bad_walks := 0
	var bad_hops := 0
	var bad_loops := 0
	var first_bad := {"tables": "", "hops": "", "walls": "", "loops": ""}
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var radius := 12.0
	var cases: Array = []
	for f in forts:
		for tier in [1, 2, 3, 4]:
			for held in [false, true]:
				cases.append({"label": "%s t%d%s" % [f["id"], tier, " held" if held else ""],
					"lay": RaidLogic.gen_layout(str(f["id"]), tier, false, cfg, {"held": held})})
	cases.append({"label": "boss", "lay": RaidLogic.gen_layout("vei", 5, true, cfg)})
	for c in cases:
		var lay: Dictionary = c["lay"]
		var label: String = c["label"]
		layouts += 1
		var rooms: Array = lay["rooms"]
		var adj: Array = lay["portal_adj"]
		var nxt: Array = lay["next_room"]
		var portals: Dictionary = lay["portals"]
		var n := rooms.size()
		# tables: portals for every adjacent pair, both orders alike; next_room follows shortest paths
		var tables_ok := true
		for a in n:
			for b in adj[a]:
				var pa: Array = portals.get("%d:%d" % [a, b], [])
				var pb: Array = portals.get("%d:%d" % [b, a], [])
				tables_ok = tables_ok and not pa.is_empty() and pa == pb
				for pt in pa:
					# a gap centre sits on both rooms' boundary and is open (not inside any wall)
					tables_ok = tables_ok and not _pt_in_walls(lay, pt)
			for b in n:
				var at := a
				var hops := 0
				while at != b and hops <= n:
					at = int((nxt[at] as Array)[b])
					if at < 0:
						break
					hops += 1
				if a == b:
					tables_ok = tables_ok and int((nxt[a] as Array)[b]) == -1
				else:
					tables_ok = tables_ok and at == b and hops == int((lay["room_hops"][a] as Array)[b])
		if not tables_ok:
			bad_tables += 1
			if first_bad["tables"] == "":
				first_bad["tables"] = label
		# walks: every ordered room pair, from a random inner point and from a corner, plus gap bands
		var starts: Array = []   # [from, to_room]
		for i in n:
			var rc: Rect2 = rooms[i]
			var inner := rc.grow(-(radius + 2.0))
			var corners := [inner.position, inner.end, Vector2(inner.position.x, inner.end.y), Vector2(inner.end.x, inner.position.y)]
			for j in n:
				if i == j:
					continue
				var from: Vector2 = corners[rng.randi() % 4] if (i + j) % 2 == 0 else \
					Vector2(rng.randf_range(inner.position.x, inner.end.x), rng.randf_range(inner.position.y, inner.end.y))
				starts.append([from, j])
		for g in lay["gaps"]:
			for j in n:
				starts.append([(g as Rect2).get_center(), j])
		for st in starts:
			var rc2: Rect2 = rooms[st[1]]
			var inner2 := rc2.grow(-(radius + 2.0))
			var to := Vector2(rng.randf_range(inner2.position.x, inner2.end.x), rng.randf_range(inner2.position.y, inner2.end.y))
			var w := _walk(lay, st[0], to, radius, 24.0, 3 * n + 4, pad)
			if not bool(w["reached"]):
				bad_hops += 1
				if first_bad["hops"] == "":
					first_bad["hops"] = "%s %s -> room %d: %s" % [label, st[0], st[1], w["why"]]
			if bool(w["crossed"]):
				bad_walks += 1
				if first_bad["walls"] == "":
					first_bad["walls"] = "%s %s -> %s" % [label, st[0], to]
			if bool(w["looped"]):
				bad_loops += 1
				if first_bad["loops"] == "":
					first_bad["loops"] = "%s %s -> %s" % [label, st[0], to]
	print("RAID_ROUTING layouts=%d bad_tables=%d bad_hops=%d bad_walks=%d bad_loops=%d %s" % [layouts, bad_tables, bad_hops, bad_walks, bad_loops, str(first_bad)])
	t.ok(layouts == forts.size() * 8 + 1, "routing: every fort x tier 1-4 x held/unheld, plus the boss arena (%d)" % layouts)
	t.ok(bad_tables == 0, "routing: portals + next_room tables are consistent (%s)" % first_bad["tables"])
	t.ok(bad_hops == 0, "routing: waypoint-following reaches the target room within 3*rooms+4 hops (%s)" % first_bad["hops"])
	t.ok(bad_walks == 0, "routing: waypoint-following never passes through an inner wall (%s)" % first_bad["walls"])
	t.ok(bad_loops == 0, "routing: waypoint-following never revisits a waypoint (%s)" % first_bad["loops"])

	# the specific shapes: same room and clear lines go straight; an unreachable target falls back
	var lay0 := RaidLogic.gen_layout("vespers", 3, false, cfg)
	var r0: Array = lay0["rooms"]
	var p0: Vector2 = (r0[0] as Rect2).get_center()
	var q0: Vector2 = (r0[0] as Rect2).get_center() + Vector2(20, 10)
	t.ok(LayoutLogic.waypoint(lay0, p0, q0, 12.0) == q0, "waypoint: same room is direct")
	var far_room := -1
	for i in r0.size():
		if i != 0 and not LayoutLogic.line_clear(lay0, p0, (r0[i] as Rect2).get_center(), 12.0):
			far_room = i
			break
	if far_room >= 0:
		var tq: Vector2 = (r0[far_room] as Rect2).get_center()
		var wp := LayoutLogic.waypoint(lay0, p0, tq, 12.0)
		t.ok(wp != tq and LayoutLogic.line_clear(lay0, p0, wp, 12.0), "waypoint: a blocked line routes to a doorstep reachable in a straight line")
	var no_route := lay0.duplicate()
	no_route.erase("next_room")
	t.ok(LayoutLogic.waypoint(no_route, p0, Vector2(9999, 9999), 12.0) == Vector2(9999, 9999), "waypoint: no table falls back to the target")
	var lay_cut := lay0.duplicate()
	lay_cut["next_room"] = [[-1, -1, -1, -1, -1, -1], [-1, -1, -1, -1, -1, -1], [-1, -1, -1, -1, -1, -1], [-1, -1, -1, -1, -1, -1], [-1, -1, -1, -1, -1, -1], [-1, -1, -1, -1, -1, -1]]
	if far_room >= 0:
		var tq2: Vector2 = (r0[far_room] as Rect2).get_center()
		t.ok(LayoutLogic.waypoint(lay_cut, p0, tq2, 12.0) == tq2, "waypoint: unreachable falls back to the target")
		t.ok(LayoutLogic.route_dist(lay0, p0, tq2) >= p0.distance_to(tq2), "route_dist is never shorter than the straight line")
		t.ok(LayoutLogic.route_dist(lay_cut, p0, tq2) == INF, "route_dist: unreachable is INF")


func _pt_in_walls(lay: Dictionary, p: Vector2) -> bool:
	for w in lay["inner_walls"]:
		if (w as Rect2).has_point(p):
			return true
	return false


## Follow waypoint() in straight `step` moves (re-asking every step: the worst case for jitter).
## reached = in the target's room within `max_hops` distinct waypoints; crossed = a move ran through
## an inner wall (sampled every ~4 px against the raw wall rect, which is 30 px thick: a body that
## grazes a face is the wall-slide's job, a waypoint that aims through the wall is not); looped = a waypoint
## came back after the walker moved on. Each move is followed by the arena's wall push-out, as in play.
func _walk(lay: Dictionary, from: Vector2, to: Vector2, radius: float, step: float, max_hops: int,
		pad: float) -> Dictionary:
	var pos := from
	var target_room := LayoutLogic.room_of(lay, to)
	var seen: Array = []
	var last := Vector2.INF
	var out := {"reached": false, "crossed": false, "looped": false, "why": ""}
	for i in 1200:
		if LayoutLogic.room_of(lay, pos) == target_room:
			out["reached"] = true
			return out
		var wp := LayoutLogic.waypoint(lay, pos, to, radius, pad)
		if wp != last:
			if seen.has(wp):
				out["looped"] = true
			seen.append(wp)
			last = wp
			if seen.size() > max_hops:
				out["why"] = "more than %d waypoints" % max_hops
				return out
		var d := wp - pos
		if d.length() < 0.5:
			out["why"] = "stalled on its waypoint at %s" % pos
			return out
		var nxt := pos + d.normalized() * minf(step, d.length())
		var n := int(ceil(pos.distance_to(nxt) / 4.0))
		for k in range(1, n + 1):
			var sp := pos.lerp(nxt, float(k) / float(n))
			for wr in lay["inner_walls"]:
				if (wr as Rect2).has_point(sp):
					out["crossed"] = true
		pos = _push_out(lay, nxt, radius)
	out["why"] = "ran out of steps at %s" % pos
	return out


## The arena's resolve_walls (raid_arena.gd), for the walker: the perimeter clamp and the push-out of inner walls.
func _push_out(lay: Dictionary, p: Vector2, r: float) -> Vector2:
	var size: Vector2 = lay["size"]
	var t: float = lay["wall_t"]
	p.x = clampf(p.x, t + r, size.x - t - r)
	p.y = clampf(p.y, t + r, size.y - t - r)
	for pass_i in 2:
		for wrect in lay["inner_walls"]:
			var g: Rect2 = (wrect as Rect2).grow(r)
			if not g.has_point(p):
				continue
			var left := p.x - g.position.x
			var right := g.end.x - p.x
			var top := p.y - g.position.y
			var bottom := g.end.y - p.y
			var m := minf(minf(left, right), minf(top, bottom))
			if m == left:
				p.x = g.position.x
			elif m == right:
				p.x = g.end.x
			elif m == top:
				p.y = g.position.y
			else:
				p.y = g.end.y
	return p
