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
	return t.failures


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
