extends RefCounted
## The freeze guard (MECHANICS §1.2, STATE-API §1.1). Checks every command return, view,
## event, seed, result and ledger() against the schema in tests/api_schema.gd, the §1.4
## constants, and the contract's member names. Headless, no autoloads.
## Every API addition updates api_schema.gd and bumps GameState.API_VERSION (§1.1).

## STATE-API §1.4, verbatim. GameState may carry more constants.
const DOC_CONSTANTS := {
	"API_VERSION": 14,
	"SAVE_VERSION": 2,
	"RELISH_STATES": ["home", "travelling", "at_fort", "at_vei", "in_dungeon", "in_boss", "dead"],
	"RATE_IDS": ["mint", "work", "war", "flood", "workers", "bodies", "gold", "bone", "living", "corpses", "backlog"],
	"HUD_RATE_IDS": ["mint", "workers", "bodies", "gold", "bone", "living"],
	"LANE_KINDS": ["war", "flood", "work", "dead", "living", "haul", "redirect"],
	"JOB_IDS": ["haul", "mill", "stall", "forge", "pit", "tend", "build"],
	"STANCE_IDS": ["vigil", "harvest", "thrift", "muster", "hearth", "grow"],  # grow: v14 (Phase I P3, A17)
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
## then. The fixtures cannot fill them either (the test checks it). None since E3-1: the stances' projections are
## filled (FIXTURE_EMPTY has them).
const E1_EMPTY := {}
## Arrays the fixtures can't fill because they predate them (make_fixtures.gd isn't rerun; T3.2). The
## exercise still fills them (_check_coverage), and the fixture check asserts they are still empty there.
const FIXTURE_EMPTY := {
	"view_town.queue": "the build queue (T3.2) is newer than the fixtures",
	# T3.3c: the away report comes from a catch-up, which a fixture load never runs
	"view_away.gains": "the away report is a catch-up's (T3.3c)",
	"view_away.ready": "the away report is a catch-up's (T3.3c)",
	"view_away.losses": "the away report is a catch-up's (T3.3c)",
	# E3-1: a stance's projection is {} while toggling it changes nothing, and at a fixture load no stance is active
	# yet (nothing fired: the conditions are read at the first beat); the exercise fills it
	"view_stances.stances[].projected": "no stance is active at a fixture load (E3-1)",
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
	var s := GameState.new(_cfgs())
	s.debug_enabled = true
	s.save_dir = _dir
	_check_constants(s)
	_check_names(s)
	_exercise(s)
	_unpaid_line()
	_fixtures()
	_check_coverage()
	t.ok(_cleanup(), "the contract test's save directory is gone")
	return t.failures


## api_version 7 (R1; STATE-API §5.19): the away report's `unpaid` kind. pre_vei saved with 5 gold (its gold
## floor about 10 s in) and loaded 10 min on: its losses carry one line per building that went unpaid, each
## view_away's line shape with kind "unpaid" and its target the building's lot id (a lot in town.json).
func _unpaid_line() -> void:
	var s := GameState.new(_cfgs())
	s.debug_enabled = true
	s.save_dir = _dir
	s.cmd_debug_load_fixture("pre_vei")
	s.town_sim.gold = 5.0
	s.clock_override = 1_800_000_000
	t.ok(s.cmd_save("unpaid")["ok"], "(setup) pre_vei with 5 gold saved")
	var n := GameState.new(_cfgs())
	n.debug_enabled = true
	n.save_dir = _dir
	n.clock_override = 1_800_000_000 + 600
	t.ok(n.cmd_load("unpaid")["ok"], "(setup) loaded 10 min on")
	var lots: Array = TestUtil.configs()["town"]["lots"].map(func(l): return str(l["id"]))
	var unpaid: Array = n.view_away()["losses"].filter(func(l): return l["kind"] == "unpaid")
	var errs: Array = []
	for l in unpaid:
		ApiSchema.check(l, ApiSchema.AWAY_LINE, "view_away.losses[]", errs)
	t.ok(not unpaid.is_empty() and errs.is_empty() and unpaid.all(func(l): return lots.has(l["target"]) and n.town_sim.buildings.has(l["target"])),
		"v7: view_away's unpaid lines match the line contract, kind \"unpaid\" with a lot id target: %s %s" % [str(unpaid), str(errs)])


# ------------------------------------------------------------------- helpers ----
## The shipped configs with town.projection_rows_per_call lifted, so a view refreshes all its build-benefit
## rows in one call: the copy checks call each view twice, and the spread refresh (T3.2) would otherwise
## refresh more rows the second time.
func _cfgs() -> Dictionary:
	var c := TestUtil.configs()
	c["economy"]["town"]["projection_rows_per_call"] = 1000
	return c

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
		elif name == "view_staffing_projection":
			_view(s, name, [s.town_sim.effective_ladder(s.town_sim.ladder)])
		elif name == "view_projection":
			_view(s, name, [s.valve.duplicate()])
			_view(s, name, [s.valve.duplicate(), true])  # T3.4b: the wave train's margins
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
		{"t": 1.0, "type": "fort_retaken", "fort_id": "old-sluice", "cause": "broken", "war_in": 4.1, "pressure_mult": 5.2},
		{"t": 1.0, "type": "big_undead_returned", "uid": "u4", "fort_id": "old-sluice"},
		{"t": 192.5, "type": "queue_started", "building_id": "market", "lot_id": "lot-13", "level": 1, "upgrade": false, "waited_on": "needs_tier"},
		{"t": 3610.5, "type": "grow_started", "building_id": "bone_mill", "lot_id": "lot-06", "level": 3},
		{"t": 4712.5, "type": "counter_garrison_cleared", "fort_id": "ashgate", "killed_mass": 31.4},
		{"t": 5100.0, "type": "tithe_warning", "wave_id": 2, "fort_id": "old-sluice", "eta_s": 150.0, "surge": 24.0},
		{"t": 1.0, "type": "tithe_wave", "wave_id": 2, "fort_id": "old-sluice", "surge": 12.0, "duration_s": 40.0, "relish_here": true, "siege_block": 0.6},
		{"t": 1.0, "type": "stance_fired", "stance_id": "harvest", "active": true, "beat_id": 117},
		{"t": 4712.5, "type": "loot_banked", "run_id": 1, "fort_id": "old-sluice", "relics": 1, "essence": 9, "blueprints": ["embalmer"], "minted": ["h12", "r13"]},
		{"t": 11002.0, "type": "vei_result", "run_id": 9, "won": true, "fronts_cleared": ["giants", "carvers", "raw"], "relish_deaths": 1, "backlog_after": 18450.0},
		{"t": 7200.0, "type": "run_ended", "run_id": 4, "kind": "raid", "outcome": "retreated", "cause": "gap"},
		{"t": 4917.2, "type": "relish_returned", "fort_id": "greywall", "cause": "retaken"},
		{"t": 33121.0, "type": "away_report", "away_s": 33120.0, "capped": false},
		{"t": 600.0, "type": "autosaved", "slot": "auto", "saved_at": 1794556800},
		{"t": 1.0, "type": "save_failed", "slot": "slot1", "reason": "write_failed"},
	]
	var types := {}
	for ev in events:
		var errs: Array = []
		ApiSchema.check(ev, ApiSchema.EVENTS[ev["type"]], "example." + ev["type"], errs)
		t.ok(errs.is_empty(), "§6 example %s passes its schema%s" % [ev["type"], "" if errs.is_empty() else ": " + str(errs)])
		types[ev["type"]] = true
	t.ok(types.size() == 22 and ApiSchema.EVENTS.size() == 22, "all 22 §6 event types have a schema and an example (v14: grow_started)")
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
	var g := _cmd(s, "cmd_debug_grant", [{"husks": 2, "remnants": 3, "big_undead": 2, "relics": 3, "essence": 25, "gold": 500.0, "bone": 200.0}], true)
	t.ok(g.get("applied", {}).get("minted", []).size() == 7, "grant minted 7 items")
	_cmd(s, "cmd_debug_grant", [{"materials": 5}], false)
	s.debug_enabled = false
	_cmd(s, "cmd_debug_grant", [{"gold": 1}], false)
	_cmd(s, "cmd_debug_set_state", [{"paused": false}], false)
	_cmd(s, "cmd_debug_skip_time", [1.0], false)
	s.debug_enabled = true
	s.clones_ready = 1  # the backups stub stock (a vat is ready while a clone covers it)
	s.town_sim.place_building("lot-13", "chapel_of_vats", 1)  # two vat slots
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
	_cmd(s, "cmd_upgrade", ["lot-04"], false)  # under_construction
	s.town_sim.place_building("lot-06", "well", 1)
	_cmd(s, "cmd_demolish", ["lot-06"], true)
	_cmd(s, "cmd_demolish", ["lot-99"], false)
	_cmd(s, "cmd_cancel_build", ["lot-05"], true)
	_cmd(s, "cmd_cancel_build", ["lot-99"], false)
	_cmd(s, "cmd_build", ["house", "lot-05"], true)  # a house is on its way for the views below
	# the build queue (T3.2): with no mill yet, the reliquary's bone is over the base cap (cost_exceeds_cap);
	# then a level-2 Bone Mill (bone cap 700), since the Market is bought with bone (T7) and its level 3, which
	# the queued upgrade builds, is over the base cap (and, from Phase I P3's depth, 510 bone, over a level-1 mill's
	# 300): an upgrade of the market under construction waits (under_construction) and stays queued for the views
	# below; a well starts on the next substep
	_cmd(s, "cmd_queue_build", ["reliquary", "lot-23"], false)  # cost_exceeds_cap: its bone over the base cap
	s.town_sim.place_building("lot-08", "bone_mill", 2)
	_cmd(s, "cmd_queue_build", ["", "lot-04"], true)
	_cmd(s, "cmd_queue_build", ["well", "lot-06"], true)
	_cmd(s, "cmd_queue_build", ["nope", "lot-06"], false)
	_cmd(s, "cmd_reorder_queue", [[1, 0]], true)
	_cmd(s, "cmd_reorder_queue", [[0]], false)
	_cmd(s, "cmd_queue_build", ["house", "lot-07"], true)
	_cmd(s, "cmd_unqueue", [2], true)
	_cmd(s, "cmd_unqueue", [5], false)
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
	# a craft needs a building with craft_slots (the Ossuary Tower) and its costs (E3-4)
	s.town_sim.place_building("lot-14", "ossuary_tower", 1)
	s.essence = maxi(s.essence, 20)
	s.relics = maxi(s.relics, 1)
	_cmd(s, "cmd_craft", ["simulacrum"], true)
	_cmd(s, "cmd_craft", ["nope"], false)
	# v9 (E4, lever (b)): the husk craft needs economy.json craft.husk's remnants and bone
	for i in int(s._req_f("economy.craft.husk.remnants")):
		s.remnants.append({"uid": s._mint_uid("r"), "aspect": "wits", "rarity": "common", "magnitude": 1 + i})
	s.town_sim.bone = maxf(s.town_sim.bone, s._req_f("economy.craft.husk.bone"))
	# and (v10) a place in the crypt: the bigs and the husks waiting under the big_undead cap
	while s.big_undead.size() + s.husks.size() >= s._cap_of("big_undead") and not s.husks.is_empty():
		s.husks.pop_back()
	_cmd(s, "cmd_craft_husk", ["skeleton"], true)
	_cmd(s, "cmd_craft_husk", ["nope"], false)
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
	# T3.3c (api-request #4): the dungeon's checkpoint of its banked loot
	var cp_loot := {"relics": 1, "blueprints": [], "husks": [{"kind": "hulk"}], "remnants": [], "essence": 4}
	_cmd(s, "cmd_run_checkpoint", [bd["run_id"], cp_loot], true)
	_cmd(s, "cmd_run_checkpoint", [bd["run_id"], cp_loot, "won"], false)
	_cmd(s, "cmd_run_checkpoint", [int(bd["run_id"]) + 1, cp_loot], false)
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
	# (E3-1: the travel's substeps may raise stance_fired, each checked against the contract; these lists leave them out)
	var no_stances := func(e: Dictionary) -> bool: return e["type"] != "stance_fired"
	var evs := _event_list(s).filter(no_stances)
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
	# P3b (api-request #22): a lost fight can't be recorded as a win (not_won); a won one can, and the press's own result
	# still applies (here the loss: the record only resolves a run no press ends)
	_cmd(s, "cmd_boss_won", [b2["run_id"], lose], false)
	_cmd(s, "cmd_boss_won", [b2["run_id"], _with_key(lose, "won", true)], false)  # a win with a final death: invalid, errors
	_cmd(s, "cmd_boss_won", [b2["run_id"], _with_key(_with_key(lose, "won", true), "relish_deaths", 0)], true)
	_cmd(s, "apply_result", ["boss", lose], true)
	evs = _event_list(s).filter(no_stances)
	t.ok(evs.map(func(e): return e["type"]) == ["vei_result", "relish_died"], "a lost boss with a final death: vei_result first, then relish_died")
	# E3-2: she is dead for the outcome's respawn_s, then wakes at Covington
	var rs := float(evs[1]["respawn_s"])
	t.ok(rs > 0.0 and s.view_relish()["state"] == "dead" and s.view_relish()["dead_s_left"] == rs and s.view_party()["party"].is_empty(),
		"she is dead for its respawn_s (%.0f s), the party died" % rs)
	_all_views(s)  # after a boss loss, while she is dead
	var dead_move := _cmd(s, "cmd_move_relish", ["ashgate"], false)
	t.ok(dead_move["reason"] == "dead", "while dead she can't move: dead")
	s.tick(rs)
	evs = _event_list(s).filter(func(e): return e["type"] == "relish_respawned")
	t.ok(evs.size() == 1 and s.view_relish()["state"] == "home" and s.view_relish()["dead_s_left"] == 0.0,
		"after respawn_s she respawns home: relish_respawned")
	_cmd(s, "cmd_move_relish", ["ashgate"], true)
	_travel(s)
	var d2 := _cmd(s, "cmd_begin_dungeon", ["ashgate"], true)
	_cmd(s, "apply_result", ["raid", _raid_result(d2["seed"], {"retreated": false, "relish_died": true,
		"loot": {"relics": 1, "blueprints": [], "husks": [], "remnants": [], "essence": 0}})], true)
	evs = _event_list(s).filter(no_stances)
	t.ok(evs.map(func(e): return e["type"]) == ["loot_banked", "relish_died"] and s.view_relish()["state"] == "dead",
		"a raid death emits relish_died, and she is dead")
	_all_views(s)  # after a death, while she is dead
	s.tick(float(evs[1]["respawn_s"]))
	t.ok(_event_list(s).filter(func(e): return e["type"] == "relish_respawned").size() == 1 and s.view_relish()["state"] == "home",
		"then relish_respawned after its respawn_s")
	for ty in ["relish_died", "relish_respawned", "vei_result", "loot_banked", "fort_flipped", "queue_started", "stance_fired"]:
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
	s.clock_override = 1_800_000_000  # E2b-2 T3.3b: the round trip at 0 s away, so its cmd_load is +1 rev (no catch-up)
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
	# T3.3c: the away report, from a chunked load 10 min on with gold at its cap (an overflow: a ready line since E4
	# step 7) and one paying building unpaid when you leave (an unpaid line among the losses; until E4 step 7 the
	# overflow was the loss)
	s.cmd_debug_grant({"gold": 1.0e9})
	for lot_id in s.town_sim.buildings:
		var bd: Dictionary = s.town_sim.buildings[lot_id]
		var bid := str(bd["building_id"])
		if str(bd["state"]) == "active" and s.town_sim.upkeep_gold_of(bid) > 0.0 and not s.town_sim.earns_gold(bid):
			bd["state"] = "unpaid"
			bd["unpaid_s"] = 0.0
			break
	_cmd(s, "cmd_save", ["away"], true)
	s.clock_override += 600
	t.ok(s.cmd_load("away", true)["ok"] and s.catching_up(), "(setup) a chunked load 10 min on")
	_cmd(s, "cmd_dismiss_away", [], false)  # catching_up
	while s.catching_up():
		s.tick(1.0 / 60.0, s.max_substeps_per_frame())
	var away := s.view_away()
	t.ok(away["shown"] and not away["gains"].is_empty() and not away["ready"].is_empty() and not away["losses"].is_empty(),
		"(setup) its report has a line in each section: %s" % str(away["losses"]))
	_all_views(s)
	t.ok(_event_list(s).map(func(e): return e["type"]).has("away_report"), "the away_report event is in the contract")
	_cmd(s, "cmd_dismiss_away", [], true)
	s.clock_override -= 600
	s.cmd_debug_set_state({"relish_at": "ashgate"})
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
		var s := GameState.new(_cfgs())
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
		if not fixed.has(p) and not E1_EMPTY.has(p) and not FIXTURE_EMPTY.has(p):
			never.append(p)
	t.ok(never.is_empty(), "across the fixtures every array a view exposes is non-empty (never: %s)" % str(never))
	for p in FIXTURE_EMPTY:
		t.ok(paths.has(p) and not fixed.has(p), "%s is empty in every fixture (else drop it from FIXTURE_EMPTY)" % p)
	for p in E1_EMPTY:
		t.ok(not fixed.has(p), "%s is still empty in every fixture (else drop it from E1_EMPTY)" % p)
