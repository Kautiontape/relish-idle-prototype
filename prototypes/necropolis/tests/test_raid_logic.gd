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
			t.ok(doors.size() >= 2 + tier, "%s: doors >= 2+tier (%d)" % [label, doors.size()])
			var south := 0
			for d in doors:
				if d["side"] == "s":
					south += 1
			t.ok(south >= 1, "%s: at least one south door" % label)
			t.ok((lay["rooms"] as Array).size() >= 2 + tier, "%s: rooms >= 2+tier (%d)" % [label, (lay["rooms"] as Array).size()])
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
	t.ok((bl["size"] as Vector2).x > (RaidLogic.gen_layout("x", 4, false, cfg)["size"] as Vector2).x,
		"boss arena is the biggest layout")

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

	return t.failures
