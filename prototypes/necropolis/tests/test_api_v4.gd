extends RefCounted
## STATE-API v4 additions (economy T3.S): the harness boot rule (is_harness_args), the settled workforce
## (workers.steady_kept and muster_steady, TownSim.workforce_steady), view_hud.war_overflow, and the
## first-run flags spent only by a win (api-request #15). Headless, no autoloads.

const GameScript := preload("res://scripts/sim/boot_rule.gd")

var t: TestUtil


func _mk(seed_val := 1) -> GameState:
	var s := GameState.new(TestUtil.configs())
	s.cmd_new_game(seed_val)
	s.debug_enabled = true
	return s


func run() -> int:
	t = TestUtil.new()
	_harness()
	_steady_helper()
	_steady_views()
	_war_overflow()
	_first_run_flags()
	_game_id()
	return t.failures


func _harness() -> void:
	t.suite("api-v4-harness-args")
	t.ok(not GameScript.is_harness_args(PackedStringArray([])), "no args: a player session")
	t.ok(not GameScript.is_harness_args(PackedStringArray(["--reduced-motion"])), "--reduced-motion is a player flag")
	t.ok(not GameScript.is_harness_args(PackedStringArray(["--reduced-motion=1"])), "--reduced-motion=value is too")
	t.ok(GameScript.is_harness_args(PackedStringArray(["--foo"])), "an unknown flag is a harness session")
	t.ok(GameScript.is_harness_args(PackedStringArray(["--valve=0.2,0.5,0.3"])), "another unit's debug flag is a harness session")
	t.ok(GameScript.is_harness_args(PackedStringArray(["--reduced-motion", "--lanes"])), "a player flag does not hide a debug one")
	t.ok(GameScript.is_harness_args(PackedStringArray(["--new-game"])), "the known dev args still are")
	t.ok(GameScript.is_harness_args(PackedStringArray(["--reduced-motionx"])), "a prefix match without = is not the player flag")
	# M3: the full decision also reads the engine args (a flag given without --) and the display server
	var none := PackedStringArray([])
	for case in [[[], [], false], [["--reduced-motion"], [], false], [["--reduced-motion=1"], [], false]]:
		t.ok(not GameScript.is_harness(PackedStringArray(case[0]), PackedStringArray(case[1]), case[2]), "is_harness: a player launch stays a player session: %s" % [case])
	for case in [[["--foo"], [], false], [["--valve=0.2,0.5,0.3"], [], false], [["--reduced-motion", "--lanes"], [], false],
			[["--new-game"], [], false], [["--reduced-motionx"], [], false]]:
		t.ok(GameScript.is_harness(PackedStringArray(case[0]), PackedStringArray(case[1]), case[2]), "is_harness: the old cases still hold: %s" % [case])
	t.ok(GameScript.is_harness(none, PackedStringArray(["--fixture=day1"]), false), "engine args [--fixture=day1] (no --) is a harness session")
	t.ok(GameScript.is_harness(none, PackedStringArray(["--new-game"]), false), "engine args [--new-game] is a harness session")
	t.ok(not GameScript.is_harness(none, PackedStringArray(["--path", "."]), false), "engine args [--path .] is not")
	t.ok(not GameScript.is_harness(none, PackedStringArray(["--fixturex"]), false), "a DEV_ARGS prefix without = is not a match")
	t.ok(GameScript.is_harness(none, PackedStringArray(["--write-movie", "x.avi"]), false), "engine args [--write-movie x.avi] is a harness session")
	t.ok(GameScript.is_harness(none, none, true), "a headless display server with no args is a harness session")


## workforce_steady equals workforce() run long, in every regime: w, and the muster rate over the last stretch.
func _steady_helper() -> void:
	t.suite("api-v4-steady-helper")
	var S := 6.0
	var C := 4.0
	var L := 100.0
	var cases := [
		{"n": "all staffed", "r": 0.05, "m": 0.25}, {"n": "all staffed, m=0", "r": 0.05, "m": 0.0},
		{"n": "idle, under the cap", "r": 0.065, "m": 0.25}, {"n": "idle, exactly at the cap", "r": 0.07, "m": 0.25},
		{"n": "pinned", "r": 0.2, "m": 0.25}, {"n": "pinned, m=0", "r": 0.1, "m": 0.0},
	]
	for c in cases:
		var r: float = c["r"]
		var m: float = c["m"]
		var want := TownSim.workforce_steady(r, L, m, S, C)
		for w0 in [0.0, 3.0, 8.0, 10.0, 25.0]:
			var a := TownSim.workforce(w0, r, 119.0 * L, L, m, S, C)
			var b := TownSim.workforce(a["w"], r, L, L, m, S, C)
			t.near(b["w"], want["kept"], 1e-6, "%s, from %s: kept" % [c["n"], str(w0)])
			t.near(float(b["muster"]) / L, want["muster"], 1e-6, "%s, from %s: muster rate" % [c["n"], str(w0)])
	t.ok(TownSim.workforce_steady(0.2, L, 0.25, S, C)["muster"] > 0.0 and TownSim.workforce_steady(0.05, L, 0.25, S, C)["muster"] == 0.0,
		"muster only when pinned")


func _steady_views() -> void:
	t.suite("api-v4-steady-views")
	var s := _mk()
	t.ok(s.cmd_debug_load_fixture("day1")["ok"], "load day1")
	s.tick(240.0)
	var w: Dictionary = s.view_town()["workers"]
	var h: Dictionary = s.view_hud()
	t.ok(w["steady_kept"] < w["steady"], "day1: steady_kept (%.1f) is below the uncapped steady (%.1f)" % [w["steady_kept"], w["steady"]])
	t.ok(absf(float(w["steady_kept"]) - float(w["total"])) <= 0.25 * float(w["total"]) + 1.0,
		"day1: steady_kept (%.1f) is close to the live total (%.1f)" % [w["steady_kept"], w["total"]])
	t.ok(h["workers_steady_kept"] == w["steady_kept"] and h["workers_steady"] == w["steady"], "the hud carries the same two numbers")
	t.ok(w["muster_steady"] >= 0.0 and w["muster_steady"] <= w["in"] + 1e-9, "muster_steady is within 0..inflow")


func _war_overflow() -> void:
	t.suite("api-v4-war-overflow")
	var s := _mk()
	t.ok(s.view_hud()["war_overflow"] == 0.0, "0 at a new game")
	# no living and no room (the dead fill every fort): Vei can ship nowhere, so the whole WAR falls through
	var patch := {}
	for f in s.view_realm()["forts"]:
		patch[f["id"]] = {"living": 0.0, "dead": 1e6}
	t.ok(s.cmd_debug_set_state({"forts": patch})["ok"], "no living and no room in any fort")
	s.tick(s.substep_s())
	t.ok(s.realm.war_route == "vei", "the substep found no target")
	var lane := -1.0
	for l in s.view_lanes()["lanes"]:
		if l["id"] == "war:covington:vei":
			lane = float(l["rate"])
	var ov: float = s.view_hud()["war_overflow"]
	t.ok(ov > 0.0 and lane >= 0.0 and ov == lane, "war_overflow (%.4f) equals the war:covington:vei lane (%.4f)" % [ov, lane])
	t.near(ov, float(s.view_hud()["split"]["war"]), 1e-9, "and it is the whole WAR split")


func _first_run_flags() -> void:
	t.suite("api-v4-first-run-flags")
	var cases := [["retreat", {}], ["death", {"retreated": false, "relish_died": true}]]
	for c in cases:
		var s := _mk()
		s.cmd_debug_set_state({"relish_at": "old-sluice"})
		var b := s.cmd_begin_dungeon("old-sluice")
		t.ok(b["ok"], "%s: begin" % c[0])
		var res := _res(b["seed"], c[1])
		var ar := s.apply_result("raid", res)
		t.ok(ar["ok"], "%s: applied (%s)" % [c[0], str(ar)])
		t.ok(s.view_fort("old-sluice")["first_clear"] and s.view_fort("old-sluice")["first_dungeon"], "%s: the fort still reads first_clear and first_dungeon" % c[0])
		s.cmd_debug_set_state({"relish_at": "old-sluice"})
		var b2 := s.cmd_begin_dungeon("old-sluice")
		t.ok(b2["ok"] and b2["seed"]["fort"]["first_clear"] and b2["seed"]["fort"]["first_dungeon"] and b2["seed"]["starter_units"] > 0,
			"%s: the next seed keeps both flags and the starter units" % c[0])
		t.ok(s.view_dungeon_seed("old-sluice")["fort"]["first_dungeon"], "%s: view_dungeon_seed agrees" % c[0])
	var s := _mk()
	s.cmd_debug_set_state({"relish_at": "old-sluice"})
	var b := s.cmd_begin_dungeon("old-sluice")
	var ar := s.apply_result("raid", _res(b["seed"], {"warden_beaten": true, "retreated": false}))
	t.ok(ar["ok"], "win: applied (%s)" % str(ar))
	t.ok(not s.view_fort("old-sluice")["first_clear"] and not s.view_fort("old-sluice")["first_dungeon"], "a win clears both flags")
	s.cmd_debug_set_state({"relish_at": "old-sluice"})
	var b2 := s.cmd_begin_dungeon("old-sluice")
	t.ok(b2["ok"] and not b2["seed"]["fort"]["first_clear"] and not b2["seed"]["fort"]["first_dungeon"], "the next seed has neither")


func _res(sd: Dictionary, over: Dictionary) -> Dictionary:
	var r := {
		"v": 2, "run_id": sd["run_id"], "seed_rev": sd["seed_rev"], "fort_id": sd["fort"]["id"],
		"warden_beaten": false, "retreated": true, "relish_died": false, "revived_in_place": 0,
		"killed_living_mass": 0.0, "raised": [], "chaff_mass": 0.0, "garrison_mass": sd["garrison_in_mass"],
		"party_lost": [], "loot": {"relics": 0, "blueprints": [], "husks": [], "remnants": [], "essence": 0},
	}
	r.merge(over, true)
	return r


func _game_id() -> void:
	t.suite("api-v4-game-id")
	var a := _mk(1)
	var b := _mk(2)
	var ida: String = a.view_hud()["game_id"]
	t.ok(ida is String and ida != "" and ida != b.view_hud()["game_id"], "two seeds, two ids (%s, %s)" % [ida, b.view_hud()["game_id"]])
	t.ok(_mk(1).view_hud()["game_id"] == ida, "the same seed gives the same id")
	a.tick(30.0)
	t.ok(a.view_hud()["game_id"] == ida, "ticking leaves it")
	var d := a.to_dict()
	t.ok(d["game_id"] == ida, "the save carries it")
	var errs := []
	ApiSchema.check(d, ApiSchema.SAVE, "to_dict", errs)
	t.ok(errs.is_empty() and d["game_id"] is String, "a fresh save validates against the SAVE schema, game_id a String: %s" % [errs])
	var bare: Dictionary = d.duplicate(true)
	bare.erase("game_id")
	errs = []
	ApiSchema.check(bare, ApiSchema.SAVE, "to_dict", errs)
	t.ok(errs.size() == 1 and "game_id" in str(errs[0]), "the schema names a missing game_id (to_dict always writes it): %s" % [errs])
	var n := GameState.new(TestUtil.configs())
	n.debug_enabled = true
	n.cmd_new_game(99)
	t.ok(n.from_dict(JSON.parse_string(JSON.stringify(d)))["ok"] and n.view_hud()["game_id"] == ida, "save, load: the id is kept")
	d.erase("game_id")
	var m := GameState.new(TestUtil.configs())
	m.cmd_new_game(5)
	t.ok(m.from_dict(d)["ok"] and m.view_hud()["game_id"] == ida, "a save without game_id loads with its seed's id")
	var f := _mk(3)
	t.ok(f.cmd_debug_load_fixture("day1")["ok"] and f.view_hud()["game_id"] != "", "a fixture gives a non-empty id")
