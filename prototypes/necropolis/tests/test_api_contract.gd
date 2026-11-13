extends RefCounted
## The freeze guard (MECHANICS §1.2, STATE-API §1.1). Checks every command return, view,
## event, seed, result and ledger() against the schema in tests/api_schema.gd, the §1.4
## constants, and the contract's member names. Headless, no autoloads.
## Every API addition updates api_schema.gd and bumps GameState.API_VERSION (§1.1).

## STATE-API §1.4, verbatim. GameState may carry more constants.
const DOC_CONSTANTS := {
	"API_VERSION": 1,
	"SAVE_VERSION": 2,
	"RELISH_STATES": ["home", "travelling", "at_fort", "at_vei", "in_dungeon", "in_boss", "dead"],
	"RATE_IDS": ["mint", "work", "war", "flood", "workers", "bodies", "gold", "bone", "living", "corpses", "backlog"],
	"HUD_RATE_IDS": ["mint", "workers", "bodies", "gold", "bone", "living"],
	"LANE_KINDS": ["war", "flood", "work", "dead", "living", "haul", "redirect"],
	"JOB_IDS": ["haul", "mill", "stall", "forge", "pit", "tend", "build"],
	"STANCE_IDS": ["vigil", "harvest", "thrift", "muster", "hearth"],
	"FRONT_IDS": ["giants", "swarm", "carvers", "raw"],
	"CRAFT_IDS": ["simulacrum", "phylactery_charge"],
	"TIERS": ["hamlet", "village", "town", "city"],
	"STATS": ["power", "beef", "wits", "presence", "speed"],
	"RARITIES": ["common", "uncommon", "rare", "legendary"],
	"WARDEN_ARCHETYPES": ["bellringer", "huntsman", "shieldwall", "pyre_priest"],
	"FIXTURES": ["day1", "midgame_2flips", "pre_vei"],
	"DEBUG_GRANT_KEYS": ["gold", "bone", "bodies", "relics", "essence", "workers", "living", "backlog", "husks", "remnants", "big_undead"],
	"DEBUG_STATE_KEYS": ["time_scale", "paused", "relish_at", "valve", "forge_level", "won", "forts"],
}
## Arrays and maps that are empty by design until E3 fills them, so their element schemas only run
## then. The fixtures cannot fill them either (the test checks it).
const E1_EMPTY := {
	"view_stances.stances[].projected": "stance projections are E3",
}

var t: TestUtil
var _dir := "user://test_saves_contract_%d" % OS.get_process_id()
var _ok := {}  # command -> seen succeeding
var _fail := {}  # command -> seen refused
var _views_seen := {}
var _events_seen := {}
var _filled := {}  # schema paths of arrays/maps seen non-empty (ApiSchema.check's `seen`)


func run() -> int:
	t = TestUtil.new()
	t.suite("api-contract")
	_schema_self_check()
	var s := GameState.new(TestUtil.configs())
	s.debug_enabled = true
	s.save_dir = _dir
	_check_constants(s)
	_check_names(s)
	_exercise(s)
	_fixtures()
	_check_coverage()
	t.ok(_cleanup(), "the contract test's save directory is gone")
	return t.failures


# ------------------------------------------------------------------- helpers ----
func _cmd(s: GameState, name: String, args: Array, want_ok: bool) -> Dictionary:
	var rv := s.rev
	var r: Variant = s.callv(name, args)
	var errs: Array = []
	ApiSchema.check_command(name, r, errs, _filled)
	var label := "%s%s" % [name, str(args)]
	t.ok(errs.is_empty(), "%s matches the contract%s" % [label, "" if errs.is_empty() else ": " + str(errs)])
	if typeof(r) != TYPE_DICTIONARY or typeof(r.get("ok")) != TYPE_BOOL:
		return {}
	t.ok(r["ok"] == want_ok, "%s -> ok %s (reason '%s')" % [label, str(want_ok), str(r.get("reason"))])
	if r["ok"]:
		_ok[name] = true
		var want_rev := rv + 1 + (int(r["substeps"]) if name == "cmd_debug_skip_time" else 0)
		t.ok(s.rev == want_rev, "%s: success adds 1 to rev (plus its substeps)" % label)
	else:
		_fail[name] = true
		t.ok(s.rev == rv, "%s: a refusal leaves rev alone" % label)
	return r


## Messes up every nested container of a returned view, to prove the next call is unaffected.
func _scribble(v: Variant) -> void:
	if v is Dictionary:
		for k in v.keys():
			_scribble(v[k])
		v["__scribble"] = true
	elif v is Array:
		for e in v:
			_scribble(e)
		v.append("__scribble")


func _view(s: GameState, name: String, args: Array = []) -> Dictionary:
	var v: Variant = s.callv(name, args)
	var label := "%s%s" % [name, str(args) if not args.is_empty() else "()"]
	if typeof(v) != TYPE_DICTIONARY:
		t.ok(false, "%s returns a Dictionary" % label)
		return {}
	var spec: Dictionary = (ApiSchema.VIEWS[name] as Dictionary).duplicate()
	if not ApiSchema.NO_REV.has(name):
		spec["rev"] = TYPE_INT
		t.ok(not v.is_empty() and v.keys()[0] == "rev" and v["rev"] == s.rev, "%s: rev first, = the state's rev" % label)
	var errs: Array = []
	ApiSchema.check(v, spec, name, errs, _filled)
	ApiSchema.non_finite(v, name, errs)
	t.ok(errs.is_empty(), "%s matches the contract%s" % [label, "" if errs.is_empty() else ": " + str(errs)])
	var snap: Dictionary = v.duplicate(true)
	_scribble(v)
	t.ok(s.callv(name, args) == snap, "%s is a fresh deep copy" % label)
	_views_seen[name] = true
	return snap


## Every view, every fort.
func _all_views(s: GameState) -> void:
	for name in ApiSchema.VIEWS:
		if name == "view_fort":
			for f in s.realm.forts:
				_view(s, name, [f["id"]])
		elif name == "view_dungeon_seed":
			var fid: String = s.run.get("fort_id", "old-sluice")
			var seed_v := s.view_dungeon_seed(fid)
			if not seed_v.is_empty():
				_view(s, name, [fid])
		elif name == "view_boss_seed":
			if not s.view_boss_seed().is_empty():
				_view(s, name)
		else:
			_view(s, name)
	var l := s.ledger()
	var errs: Array = []
	ApiSchema.check(l, ApiSchema.LEDGER, "ledger", errs, _filled)
	ApiSchema.non_finite(l, "ledger", errs)
	t.ok(errs.is_empty(), "ledger() matches the contract%s" % ("" if errs.is_empty() else ": " + str(errs)))


func _event_list(s: GameState) -> Array:
	var evs := s.drain_events()
	var last_t := -1.0
	for ev in evs:
		var errs: Array = []
		ApiSchema.check(ev, {"t": TYPE_FLOAT, "type": TYPE_STRING}, "event", errs)
		if errs.is_empty():
			var ty: String = ev["type"]
			t.ok(ApiSchema.EVENTS.has(ty), "event type '%s' is a §6 type" % ty)
			if ApiSchema.EVENTS.has(ty):
				ApiSchema.check(ev, ApiSchema.EVENTS[ty], "event." + ty, errs)
				_events_seen[ty] = true
			t.ok(ev["t"] >= last_t, "event t never decreases (%s)" % ty)
			last_t = ev["t"]
		ApiSchema.non_finite(ev, "event", errs)
		t.ok(errs.is_empty(), "event %s matches the contract%s" % [str(ev.get("type")), "" if errs.is_empty() else ": " + str(errs)])
	return evs


func _travel(s: GameState) -> void:
	for i in 200:
		if s.relish["state"] != "travelling":
			return
		s.tick(0.5)


# ------------------------------------------------------- constants and names ----
func _check_constants(s: GameState) -> void:
	var have: Dictionary = (s.get_script() as Script).get_script_constant_map()
	for k in DOC_CONSTANTS:
		t.ok(have.has(k) and have[k] == DOC_CONSTANTS[k], "constant %s equals STATE-API §1.4" % k)
		if have.has(k):
			t.ok(typeof(have[k]) == typeof(DOC_CONSTANTS[k]), "constant %s has the doc's type" % k)


func _check_names(s: GameState) -> void:
	var names: Array = ApiSchema.COMMANDS.keys() + ApiSchema.VIEWS.keys() + ApiSchema.MEMBER_METHODS
	for n in names:
		if ApiSchema.EXPECTED_MISSING.has(n):
			t.ok(not s.has_method(n), "%s is not there yet (drop it from EXPECTED_MISSING when it lands)" % n)
		else:
			t.ok(s.has_method(n), "GameState has %s()" % n)
	for n in ApiSchema.EXPECTED_MISSING:
		t.ok(names.has(n), "EXPECTED_MISSING names a contract method: %s" % n)
	for n in ApiSchema.MEMBER_VARS:
		t.ok(n in s, "GameState has var %s" % n)
	# The other way round: a cmd_* or view_* on GameState must be in the schema (§1.1:
	# every addition updates this test).
	for m in s.get_method_list():
		var n: String = m["name"]
		if n.begins_with("cmd_"):
			t.ok(ApiSchema.COMMANDS.has(n), "%s() is in the contract schema" % n)
		elif n.begins_with("view_"):
			t.ok(ApiSchema.VIEWS.has(n), "%s() is in the contract schema" % n)
	for n in ApiSchema.COMMANDS:
		t.ok(ApiSchema.REASONS.has(n), "%s has a reason list" % n)


# --------------------------------------------------------- schema self-check ----
## The STATE-API examples (§6, §8, filled in from the tables where the doc gives none)
## must pass their own schema, so the tables in api_schema.gd stay honest.
func _schema_self_check() -> void:
	var events := [
		{"t": 9210.0, "type": "relish_died", "outcome": "clone", "in_place": false, "at": "vespers", "run_id": 4, "respawn_s": 60.0},
		{"t": 9270.0, "type": "relish_respawned", "with_clone": true, "at": "covington"},
		{"t": 1.0, "type": "building_started", "lot_id": "lot-05", "building_id": "house", "level": 1, "upgrade": false},
		{"t": 1.0, "type": "building_done", "lot_id": "lot-05", "building_id": "house", "level": 1},
		{"t": 1.0, "type": "building_unpaid", "lot_id": "lot-04", "building_id": "market", "unpaid": true},
		{"t": 1.0, "type": "tier_up", "tier": "village", "from": "hamlet"},
		{"t": 4712.5, "type": "fort_flipped", "fort_id": "old-sluice", "run_id": 1, "hold_s": 375.0},
		{"t": 1.0, "type": "fort_retaken", "fort_id": "old-sluice", "cause": "expired"},
		{"t": 5100.0, "type": "tithe_warning", "wave_id": 2, "fort_id": "old-sluice", "eta_s": 150.0, "surge": 24.0},
		{"t": 1.0, "type": "tithe_wave", "wave_id": 2, "fort_id": "old-sluice", "surge": 12.0, "duration_s": 40.0, "relish_here": true, "siege_block": 0.6},
		{"t": 1.0, "type": "stance_fired", "stance_id": "harvest", "active": true, "beat_id": 117},
		{"t": 4712.5, "type": "loot_banked", "run_id": 1, "fort_id": "old-sluice", "relics": 1, "essence": 9, "blueprints": ["embalmer"], "minted": ["h12", "r13"]},
		{"t": 11002.0, "type": "vei_result", "run_id": 9, "won": true, "fronts_cleared": ["giants", "carvers", "raw"], "relish_deaths": 1, "backlog_after": 18450.0},
		{"t": 600.0, "type": "autosaved", "slot": "auto", "saved_at": 1794556800},
		{"t": 1.0, "type": "save_failed", "slot": "slot1", "reason": "write_failed"},
	]
	var types := {}
	for ev in events:
		var errs: Array = []
		ApiSchema.check(ev, ApiSchema.EVENTS[ev["type"]], "example." + ev["type"], errs)
		t.ok(errs.is_empty(), "§6 example %s passes its schema%s" % [ev["type"], "" if errs.is_empty() else ": " + str(errs)])
		types[ev["type"]] = true
	t.ok(types.size() == 15 and ApiSchema.EVENTS.size() == 15, "all 15 §6 event types have a schema and an example")
	var raid := {"v": 2, "run_id": 1, "seed_rev": 512, "fort_id": "old-sluice", "warden_beaten": true,
		"retreated": false, "relish_died": false, "revived_in_place": 0, "killed_living_mass": 30.0,
		"raised": [{"score": 75, "count": 2, "mass": 8.0}], "chaff_mass": 4.0, "garrison_mass": 6.0,
		"party_lost": ["u4"], "loot": {"relics": 1, "blueprints": ["embalmer"], "husks": [{"kind": "hulk"}],
			"remnants": [{"aspect": "beef", "rarity": "common", "magnitude": 3}], "essence": 9}}
	var boss := {"v": 2, "run_id": 9, "seed_rev": 21950, "won": true, "fronts_cleared": ["giants"],
		"relish_deaths": 1, "backups_spent": {"phylactery": 1, "clones": 0}, "party_lost": [], "backlog_spent": 900.0}
	for pair in [["raid", raid], ["boss", boss], ["town", {"v": 2, "teleport_to": ""}], ["map", {"v": 2, "teleport_to": "vei"}]]:
		var errs: Array = []
		ApiSchema.check(pair[1], ApiSchema.RESULTS[pair[0]], "result." + pair[0], errs)
		t.ok(errs.is_empty(), "§8 %s result passes its schema%s" % [pair[0], "" if errs.is_empty() else ": " + str(errs)])
	# the checker itself: a wrong type names the path; extra keys are fine; a missing key is not
	var errs: Array = []
	ApiSchema.check({"buildings": [{"upkeep": {"gold": 1, "bone": 0.0}}]}, {"buildings": [{"upkeep": ApiSchema.UPKEEP}]}, "view_town", errs)
	t.ok(errs == ["view_town.buildings[0].upkeep.gold: expected float, got int"], "checker names the path: %s" % str(errs))
	errs = []
	ApiSchema.check({"a": 1, "extra": "x"}, {"a": TYPE_INT}, "v", errs)
	t.ok(errs.is_empty(), "extra keys are additive, not errors")
	errs = []
	ApiSchema.check({"m": {"x": 1.0, "y": INF}}, {"m": {"*": TYPE_FLOAT}, "gone": TYPE_INT}, "v", errs)
	t.ok(errs.size() == 2 and "v.m.y: non-finite" in errs[0] and errs[1] == "v.gone: missing", "map values, INF and missing keys are caught: %s" % str(errs))
	errs = []
	ApiSchema.check_command("cmd_build", {"ok": false, "reason": "nope", "cost": {"gold": 0.0}}, errs)
	t.ok(errs.size() == 2, "a refusal's reason must be listed and its nested extra {}: %s" % str(errs))


# ------------------------------------------------------------------ exercise ----
func _exercise(s: GameState) -> void:
	_cmd(s, "cmd_new_game", [1], true)
	_all_views(s)  # the fresh state

	# fill every array a view exposes
	var g := _cmd(s, "cmd_debug_grant", [{"husks": 2, "remnants": 3, "big_undead": 2, "relics": 3, "essence": 25, "gold": 10.0}], true)
	t.ok(g.get("applied", {}).get("minted", []).size() == 7, "grant minted 7 items")
	_cmd(s, "cmd_debug_grant", [{"materials": 5}], false)
	s.debug_enabled = false
	_cmd(s, "cmd_debug_grant", [{"gold": 1}], false)
	_cmd(s, "cmd_debug_set_state", [{"paused": false}], false)
	_cmd(s, "cmd_debug_skip_time", [1.0], false)
	s.debug_enabled = true
	s.clones_ready = 2  # the backups stub stock: ready clones, one vat slot each until E3
	s.blueprints.append("embalmer")  # blueprints are banked by apply_result (T1.4)
	var inv := s.view_inventory()
	var h: String = inv["husks"][0]["uid"]
	var r1: String = inv["remnants"][0]["uid"]
	var r2: String = inv["remnants"][1]["uid"]
	var bus: Array = s.view_big_undead()["big_undead"]
	var u1: String = bus[0]["uid"]
	var u2: String = bus[1]["uid"]

	# §4.1-4.4 at home: each command once ok, once refused
	s.debug_enabled = false
	_cmd(s, "cmd_set_time_scale", [2.0], false)
	_cmd(s, "cmd_pause", [true], false)
	s.debug_enabled = true
	_cmd(s, "cmd_set_time_scale", [2.0], true)
	_cmd(s, "cmd_set_time_scale", [3.0], false)
	_cmd(s, "cmd_set_time_scale", [1.0], true)
	_cmd(s, "cmd_pause", [true], true)
	_cmd(s, "cmd_pause", [false], true)
	_cmd(s, "cmd_set_valve", [2.0, 2.0, 1.0], true)
	_cmd(s, "cmd_set_valve", [0.0, 0.0, 0.0], false)
	_cmd(s, "cmd_set_haul_target", ["ashgate"], true)
	_cmd(s, "cmd_set_haul_target", ["nope"], false)
	s.tick(0.5)  # TownSim's convoy (the Charnel House's haulers) leaves for Ashgate
	_cmd(s, "cmd_build", ["house", "lot-05"], true)
	_cmd(s, "cmd_build", ["nope", "lot-05"], false)
	_cmd(s, "cmd_upgrade", ["lot-04"], true)
	_cmd(s, "cmd_upgrade", ["lot-99"], false)
	_cmd(s, "cmd_demolish", ["lot-03"], true)
	_cmd(s, "cmd_demolish", ["lot-99"], false)
	_cmd(s, "cmd_cancel_build", ["lot-05"], true)
	_cmd(s, "cmd_cancel_build", ["lot-99"], false)
	_cmd(s, "cmd_set_job_priority", [["haul", "build", "pit", "stall", "mill", "forge", "tend"]], true)
	_cmd(s, "cmd_set_job_priority", [["haul"]], false)
	_cmd(s, "cmd_set_staff_cap", ["lot-03", 2], true)
	_cmd(s, "cmd_set_staff_cap", ["lot-01", 1], false)
	_cmd(s, "cmd_set_stance", ["harvest", true], true)
	_cmd(s, "cmd_set_stance", ["nope", true], false)
	_cmd(s, "cmd_raise_big_undead", [h, [r1, r2], "Old Gristle"], true)
	_cmd(s, "cmd_raise_big_undead", ["h999", [], "x"], false)
	_cmd(s, "cmd_rename_big_undead", [u1, "Old Gristle"], true)
	_cmd(s, "cmd_rename_big_undead", [u1, "   "], false)
	_cmd(s, "cmd_place_big_undead", [u1, "town:lot-04"], true)
	_cmd(s, "cmd_place_big_undead", [u2, "fort:ashgate"], true)
	_cmd(s, "cmd_place_big_undead", [u1, "nowhere"], false)
	_cmd(s, "cmd_craft", ["simulacrum"], true)
	_cmd(s, "cmd_craft", ["nope"], false)
	_cmd(s, "cmd_deploy_simulacrum", ["vespers"], true)
	_cmd(s, "cmd_deploy_simulacrum", ["nope"], false)
	_cmd(s, "cmd_staff_vat", [1, true], true)
	_cmd(s, "cmd_staff_vat", [5, true], false)
	_cmd(s, "cmd_debug_set_state", [{"paused": false}], true)
	_cmd(s, "cmd_debug_set_state", [{"nope": 1}], false)
	_cmd(s, "cmd_debug_skip_time", [1.0], true)
	_cmd(s, "cmd_debug_skip_time", [0.0], false)
	t.ok(s.view_town()["haul"]["convoys"].size() == 1, "the convoy is in view_town")
	t.ok(s.view_fort("ashgate")["siege"] == [u2] and s.view_town()["buildings"][3]["foreman"] == u1, "siege and foreman echoed")
	_all_views(s)  # a foreman, a siege, a convoy, vats, a blueprint, a stance

	_cmd(s, "cmd_set_party", [[u1, u2]], true)
	_cmd(s, "cmd_set_party", [["u999"]], false)
	_cmd(s, "cmd_assign_front", [u1, "giants"], true)
	_cmd(s, "cmd_assign_front", [u1, "nope"], false)
	_all_views(s)  # a party with a front

	# §4.2 travel, then §4.5 a dungeon run
	_cmd(s, "cmd_move_relish", ["nope"], false)
	_cmd(s, "cmd_cancel_travel", [], false)
	_cmd(s, "cmd_move_relish", ["old-sluice"], true)
	s.tick(0.5)
	_cmd(s, "cmd_cancel_travel", [], true)
	_cmd(s, "cmd_move_relish", ["old-sluice"], true)
	_all_views(s)  # travelling
	_travel(s)
	t.ok(s.view_relish()["state"] == "at_fort", "arrived at Old Sluice")
	for f in s.realm.forts:
		var vf := s.view_fort(f["id"])
		var want := "" if f["id"] == "old-sluice" else "not_at_fort"
		t.ok(vf["can_descend"] == (want == "") and vf["reason"] == want, "view_fort(%s) can_descend agrees with cmd_begin_dungeon" % f["id"])
	_cmd(s, "cmd_begin_dungeon", ["ashgate"], false)
	var bd := _cmd(s, "cmd_begin_dungeon", ["old-sluice"], true)
	t.ok(Results.validate("raid_seed", bd["seed"]) == [], "Results.validate accepts the raid seed as issued: %s" % str(Results.validate("raid_seed", bd["seed"])))
	t.ok(bd["seed"]["garrison_mass_div"] == 10.0, "the raid seed carries garrison_mass_div (§7.1)")
	t.ok(s.view_dungeon_seed("old-sluice") == bd["seed"] and bd["seed"]["party"].size() == 2, "view_dungeon_seed is the issued seed, with the party")
	t.ok(s.view_dungeon_seed("nope") == {} and s.view_fort("nope") == {}, "views of unknown ids are {}")
	_cmd(s, "cmd_new_game", [2], false)
	_cmd(s, "cmd_set_party", [[u1]], false)
	_all_views(s)  # in the dungeon
	_cmd(s, "cmd_abort_dungeon", [], true)
	_cmd(s, "cmd_abort_dungeon", [], false)

	# the boss
	_cmd(s, "cmd_begin_boss", [], false)
	_cmd(s, "cmd_move_relish", ["vei"], true)
	_travel(s)
	t.ok(s.view_vei()["can_begin"] and s.view_vei()["reason"] == "", "view_vei can_begin at Vei")
	var bb := _cmd(s, "cmd_begin_boss", [], true)
	t.ok(s.view_boss_seed() == bb["seed"] and bb["seed"]["fronts"][0]["assigned"] == [u1], "view_boss_seed is the issued seed, fronts echoed")
	t.ok(Results.validate("boss_seed", bb["seed"]) == [], "Results.validate accepts the boss seed as issued: %s" % str(Results.validate("boss_seed", bb["seed"])))
	t.ok(s.view_vei()["reason"] == "busy" and not s.view_vei()["can_begin"], "view_vei reason busy during the run")
	_all_views(s)  # in the boss
	_cmd(s, "cmd_abort_dungeon", [], true)

	# §4.5 apply_result and the events it reaches: loot_banked and fort_flipped (a won dungeon),
	# vei_result and relish_died (a lost boss with a final death), then relish_died via a raid death
	_event_list(s)
	_cmd(s, "cmd_move_relish", ["old-sluice"], true)
	_travel(s)
	var d1 := _cmd(s, "cmd_begin_dungeon", ["old-sluice"], true)
	var win := _raid_result(d1["seed"], {"warden_beaten": true, "retreated": false, "killed_living_mass": 20.0, "party_lost": [u2],
		"raised": [{"score": 80, "count": 2, "mass": 5.0}], "chaff_mass": 2.0,
		"loot": {"relics": 1, "blueprints": ["reliquary"], "husks": [{"kind": "hulk"}],
			"remnants": [{"aspect": "beef", "rarity": "rare", "magnitude": 2}], "essence": 5}})
	var bad := _cmd(s, "apply_result", ["raid", _raid_result(d1["seed"], {"chaff_mass": -1.0})], false)
	t.ok(bad["reason"] == "invalid" and bad["errors"] == ["range:chaff_mass"], "an invalid result names its errors")
	_cmd(s, "apply_result", ["raid", {"v": 1}], false)
	var won_raid := _cmd(s, "apply_result", ["raid", win], true)
	t.ok(won_raid["minted"].size() == 2 and won_raid["errors"] == [], "the husk and the remnant are minted")
	var dup := _cmd(s, "apply_result", ["raid", win], false)
	t.ok(dup["reason"] == "duplicate_run" and dup["minted"] == [] and dup["errors"] == [], "a repeat is duplicate_run")
	var evs := _event_list(s)
	t.ok(evs.map(func(e): return e["type"]) == ["loot_banked", "fort_flipped"], "a won dungeon emits loot_banked, then fort_flipped")
	t.ok(evs[1]["hold_s"] == 375.0 and evs[0]["minted"] == won_raid["minted"], "hold_s 375 (tier 1) and the minted uids")
	t.ok(s.view_relish()["state"] == "at_fort" and s.view_fort("old-sluice")["flipped_count"] == 1, "she stays at the fort, which has flipped once")
	_all_views(s)  # after a flip, a loot and a lost party member
	_cmd(s, "cmd_move_relish", ["vei"], true)
	_travel(s)
	var b2 := _cmd(s, "cmd_begin_boss", [], true)
	var lose := {"v": 2, "run_id": b2["run_id"], "seed_rev": b2["seed_rev"], "won": false, "fronts_cleared": [],
		"relish_deaths": 1, "backups_spent": {"phylactery": 0, "clones": 0}, "party_lost": [], "backlog_spent": 100.0}
	_cmd(s, "apply_result", ["boss", _with_key(lose, "relish_deaths", 3)], false)
	_cmd(s, "apply_result", ["boss", lose], true)
	evs = _event_list(s)
	t.ok(evs.map(func(e): return e["type"]) == ["vei_result", "relish_died", "relish_respawned"], "a lost boss with a final death: vei_result first")
	t.ok(s.view_relish()["state"] == "home" and s.view_party()["party"].is_empty(), "she is home, the party died")
	_all_views(s)  # after a boss loss
	_cmd(s, "cmd_move_relish", ["ashgate"], true)
	_travel(s)
	var d2 := _cmd(s, "cmd_begin_dungeon", ["ashgate"], true)
	_cmd(s, "apply_result", ["raid", _raid_result(d2["seed"], {"retreated": false, "relish_died": true,
		"loot": {"relics": 1, "blueprints": [], "husks": [], "remnants": [], "essence": 0}})], true)
	evs = _event_list(s)
	t.ok(evs.map(func(e): return e["type"]) == ["loot_banked", "relish_died", "relish_respawned"], "a raid death emits relish_died and relish_respawned")
	for ty in ["relish_died", "relish_respawned", "vei_result", "loot_banked", "fort_flipped"]:
		t.ok(_events_seen.has(ty), "event %s checked against the contract" % ty)
	_all_views(s)  # after a death
	_persistence(s)


## A valid raid result for `sd` (a retreat that changes nothing); `over` replaces keys.
func _raid_result(sd: Dictionary, over := {}) -> Dictionary:
	var r := {
		"v": 2, "run_id": sd["run_id"], "seed_rev": sd["seed_rev"], "fort_id": sd["fort"]["id"],
		"warden_beaten": false, "retreated": true, "relish_died": false, "revived_in_place": 0,
		"killed_living_mass": 0.0, "raised": [], "chaff_mass": 0.0, "garrison_mass": sd["garrison_in_mass"],
		"party_lost": [], "loot": {"relics": 0, "blueprints": [], "husks": [], "remnants": [], "essence": 0},
	}
	r.merge(over, true)
	return r


func _with_key(d: Dictionary, k: String, v: Variant) -> Dictionary:
	var c := d.duplicate(true)
	c[k] = v
	return c


func _check_coverage() -> void:
	for name in ApiSchema.COMMANDS:
		if ApiSchema.EXPECTED_MISSING.has(name):
			continue
		t.ok(_ok.has(name), "%s exercised on a success path" % name)
		if not (ApiSchema.REASONS[name] as Array).is_empty():
			t.ok(_fail.has(name), "%s exercised on a failure path" % name)
	for name in ApiSchema.VIEWS:
		t.ok(_views_seen.has(name), "%s checked" % name)
	var paths: Array = []
	for name in ApiSchema.VIEWS:
		ApiSchema.containers(ApiSchema.VIEWS[name], name, paths)
	for name in ApiSchema.COMMANDS:
		if not ApiSchema.EXPECTED_MISSING.has(name):
			ApiSchema.containers(ApiSchema.COMMANDS[name], name, paths)
	ApiSchema.containers(ApiSchema.LEDGER, "ledger", paths)
	var empty: Array = []
	for p in paths:
		if not _filled.has(p) and not E1_EMPTY.has(p):
			empty.append(p)
	t.ok(empty.is_empty(), "every array and map element schema ran on real data (never filled: %s)" % str(empty))
	for p in E1_EMPTY:
		t.ok(paths.has(p), "E1_EMPTY names a schema path: %s" % p)


# --------------------------------------------------------------- persistence ----
func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _cleanup() -> bool:
	var d := DirAccess.open(_dir)
	if d != null:
		d.include_hidden = true
		for f in d.get_files():
			d.remove(f)
	DirAccess.remove_absolute(_dir)
	return not DirAccess.dir_exists_absolute(_dir)


## cmd_save, cmd_load, list_saves, to_dict and their events (§4.1, §6, §9).
func _persistence(s: GameState) -> void:
	var d := s.to_dict()
	var errs: Array = []
	ApiSchema.check(d, ApiSchema.SAVE, "to_dict", errs)
	ApiSchema.non_finite(d, "to_dict", errs)
	t.ok(errs.is_empty(), "to_dict() matches the top-level save schema%s" % ("" if errs.is_empty() else ": " + str(errs)))
	t.ok(d["v"] == GameState.SAVE_VERSION and d["api_version"] == GameState.API_VERSION, "to_dict carries v and api_version")
	_event_list(s)
	var sv := _cmd(s, "cmd_save", ["slot1"], true)
	t.ok(FileAccess.file_exists(sv["path"]) and sv["path"] == _dir + "/slot1.json", "cmd_save wrote its path")
	_cmd(s, "cmd_save", ["auto"], true)
	_cmd(s, "cmd_save", ["Bad Slot"], false)
	var evs := _event_list(s)
	t.ok(evs.map(func(e): return e["type"]) == ["autosaved", "save_failed"], "autosaved on the auto slot, save_failed on a refusal")
	t.ok(evs[0]["slot"] == "auto" and evs[1]["reason"] == "bad_slot" and evs[1]["slot"] == "Bad Slot", "their fields")
	var keep := s.save_dir
	print("  (an ERROR about not creating a directory is expected next)")
	s.save_dir = _dir + "/slot1.json/sub"  # under a regular file: unwritable
	var wf := _cmd(s, "cmd_save", ["slot2"], false)
	t.ok(wf["reason"] == "write_failed" and _event_list(s).map(func(e): return e["reason"]) == ["write_failed"], "write_failed and its save_failed event")
	s.save_dir = keep
	_write(_dir + "/future.json", JSON.stringify({"v": GameState.SAVE_VERSION + 1}))
	_write(_dir + "/junk.json", "{nope")
	var list := s.list_saves()
	errs = []
	ApiSchema.check(list, ApiSchema.LIST_SAVES, "list_saves", errs, _filled)
	t.ok(errs.is_empty() and list.size() == 3, "list_saves matches its schema; corrupt omitted, a future file listed %s" % str(errs))
	var rv := s.rev
	s.list_saves()
	t.ok(s.rev == rv, "list_saves is not a command: rev stays")
	_cmd(s, "cmd_load", ["slot1"], true)
	_cmd(s, "cmd_load", ["nothing"], false)
	_cmd(s, "cmd_load", ["junk"], false)
	_cmd(s, "cmd_load", ["Bad Slot"], false)
	_cmd(s, "cmd_load", ["future"], false)
	t.ok(s.cmd_load("future")["reason"] == "bad_version" and s.cmd_load("junk")["reason"] == "no_save" and s.cmd_load("nothing")["reason"] == "no_save",
		"bad_version for a future file, no_save for a corrupt or missing one")
	s.legacy_teleport_relish("ashgate")
	_cmd(s, "cmd_begin_dungeon", ["ashgate"], true)
	_cmd(s, "cmd_load", ["slot1"], false)
	_cmd(s, "cmd_debug_load_fixture", ["day1"], false)
	_cmd(s, "cmd_abort_dungeon", [], true)
	s.debug_enabled = false
	_cmd(s, "cmd_debug_load_fixture", ["day1"], false)
	s.debug_enabled = true
	_cmd(s, "cmd_debug_load_fixture", ["nope"], false)
	_cmd(s, "cmd_debug_load_fixture", ["day1"], true)
	_all_views(s)  # after a load


## §9.4: the three fixtures load through cmd_debug_load_fixture, pass every view check, and
## between them make every array a view exposes non-empty (except E1_EMPTY).
func _fixtures() -> void:
	var base := _filled
	_filled = {}
	for name in GameState.FIXTURES:
		var s := GameState.new(TestUtil.configs())
		s.debug_enabled = true
		s.save_dir = _dir
		_cmd(s, "cmd_debug_load_fixture", [name], true)
		_all_views(s)
		if name == "pre_vei":
			# the seed views are empty without a run: open the boss, then a raid with the party
			_cmd(s, "cmd_begin_boss", [], true)
			_all_views(s)
			_cmd(s, "cmd_abort_dungeon", [], true)
			s.cmd_debug_set_state({"relish_at": "ashgate"})
			_cmd(s, "cmd_begin_dungeon", ["ashgate"], true)
			_all_views(s)
			_cmd(s, "cmd_abort_dungeon", [], true)
	var fixed := _filled
	_filled = base
	for k in fixed:
		_filled[k] = true
	var paths: Array = []
	for name in ApiSchema.VIEWS:
		ApiSchema.containers(ApiSchema.VIEWS[name], name, paths)
	var never: Array = []
	for p in paths:
		if not fixed.has(p) and not E1_EMPTY.has(p):
			never.append(p)
	t.ok(never.is_empty(), "across the fixtures every array a view exposes is non-empty (never: %s)" % str(never))
	for p in E1_EMPTY:
		t.ok(not fixed.has(p), "%s is still empty in every fixture (else drop it from E1_EMPTY)" % p)
