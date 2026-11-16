extends RefCounted
## GameState: runs and seeds (STATE-API 4.5, 7, 5.15), new game and time controls
## (4.1, 3), and the E1 debug commands (4.6). Headless, no autoloads.


func _mk(seed_val := 1) -> GameState:
	var s := GameState.new(TestUtil.configs())
	s.cmd_new_game(seed_val)
	s.debug_enabled = true
	return s


func _types_ok(t: TestUtil, d: Dictionary, spec: Dictionary, what: String) -> void:
	var good := d.size() == spec.size()
	for k in spec:
		good = good and d.has(k) and typeof(d[k]) == spec[k]
	t.ok(good, "%s: exact keys and types (%s)" % [what, str(d.keys())])


func run() -> int:
	var t := TestUtil.new()
	t.suite("game-state-runs")

	# --- constants and construction ---
	t.ok(GameState.API_VERSION == 8 and GameState.RELISH_STATES.size() == 7 and GameState.FRONT_IDS.size() == 4, "constants present")
	t.ok(GameState.DEBUG_GRANT_KEYS.size() == 11 and GameState.DEBUG_STATE_KEYS.size() == 7, "debug key lists")
	var bare := GameState.new()
	t.ok(bare._cfgs.is_empty(), "_init() with no configs leaves it unset")

	# --- time commands are debug-only ---
	var rel := GameState.new(TestUtil.configs())
	rel.cmd_new_game(1)
	var rv0 := rel.rev
	t.ok(rel.cmd_set_time_scale(2.0) == {"ok": false, "reason": "not_debug", "time_scale": 1.0} and rel.time_scale == 1.0, "release: cmd_set_time_scale is not_debug")
	t.ok(rel.cmd_pause(true) == {"ok": false, "reason": "not_debug", "paused": false} and not rel.paused and rel.rev == rv0, "release: cmd_pause is not_debug, nothing changes")

	# --- I4: a grant never pulls an over-cap stock down ---
	var og := GameState.new(TestUtil.configs())
	og.debug_enabled = true
	og.cmd_new_game(1)
	for key in ["living", "bodies"]:
		var cap0 := og.town_sim.living_cap() if key == "living" else og.town_sim.body_cap()
		og.town_sim.set(key, cap0 + 5.0)  # over the cap (a demolished house, say)
		var gr := og.cmd_debug_grant({key: 1})
		t.ok(gr["ok"] and float(og.town_sim.get(key)) == cap0 + 5.0 and gr["applied"][key] == 0.0,
			"over-cap %s: a positive grant leaves it, never pulls it down to the cap (%f)" % [key, cap0])

	# --- cmd_new_game ---
	var s := _mk()
	s.tick(30.0)
	s.cmd_pause(true)
	s.cmd_set_time_scale(4)
	t.ok(s.t > 0.0 and s.time_scale == 4.0, "t advances, time scale set")
	s.cmd_debug_set_state({"relish_at": "old-sluice"})
	var b := s.cmd_begin_dungeon("old-sluice")
	var uid_before := s.next_uid
	s.cmd_debug_grant({"husks": 2})
	t.ok(s.cmd_new_game(5) == {"ok": false, "reason": "busy"}, "cmd_new_game busy while a run is open")
	s.cmd_abort_dungeon()
	var rv := s.rev
	t.ok(s.cmd_new_game(5) == {"ok": true, "reason": ""}, "cmd_new_game ok after the run closes")
	t.ok(s.t == 0.0 and s.time_scale == 1.0 and s.paused == false and s.drain_events().is_empty(), "t, scale, pause, events reset")
	t.ok(s.rev > rv and s.view_relish()["state"] == "home" and s.husks.is_empty(), "rev rises, state reset in place")
	t.ok(s.next_run_id == 2 and s.next_uid == uid_before + 2, "run ids and uids keep running across new games")
	t.ok(s.rng_seed == "5", "seed recorded")

	# --- time ---
	s = _mk()
	t.near(s.t, 0.0, 0.0, "t starts at 0")
	s.tick(2.0)
	t.near(s.t, 2.0, 1e-9, "t advances substep_s per substep")
	t.ok(s.cmd_set_time_scale(3) == {"ok": false, "reason": "invalid_scale", "time_scale": 1.0}, "invalid_scale")
	t.ok(s.cmd_set_time_scale(2.0)["time_scale"] == 2.0 and s.time_scale == 2.0, "time scale 2")
	t.ok(s.cmd_pause(true) == {"ok": true, "reason": "", "paused": true}, "pause")
	rv = s.rev
	t.ok(s.tick(10.0) == 0 and s.t == 2.0 and s.rev == rv, "tick while paused: 0, nothing moves")
	s.cmd_pause(false)
	for bad in [0.0, -1.0, INF, NAN]:
		t.ok(s.tick(bad) == 0, "tick(%s) returns 0" % str(bad))
	t.ok(s.tick(1.0) == 2, "tick resumes after unpause")
	var ev := s.drain_events()
	s.cmd_debug_set_state({"relish_at": "old-sluice"})
	s.cmd_begin_dungeon("old-sluice")
	t.ok(s.cmd_set_time_scale(2)["reason"] == "in_dungeon", "time scale refused in a dungeon")
	s.cmd_abort_dungeon()
	s.cmd_debug_set_state({"relish_at": "vei"})
	s.cmd_begin_boss()
	t.ok(s.cmd_set_time_scale(2)["reason"] == "in_boss", "time scale refused in the boss")
	s.cmd_abort_dungeon()

	# --- cmd_begin_dungeon: reasons in order ---
	s = _mk()
	var fail := {"ok": false, "reason": "unknown_fort", "seed": {}, "run_id": -1, "seed_rev": -1}
	t.ok(s.cmd_begin_dungeon("nope") == fail, "unknown_fort with zeroed extras")
	fail["reason"] = "not_at_fort"
	rv = s.rev
	t.ok(s.cmd_begin_dungeon("old-sluice") == fail and s.rev == rv, "not_at_fort from home, rev untouched")
	s.cmd_debug_set_state({"relish_at": "old-sluice"})
	t.ok(s.cmd_begin_dungeon("ashgate")["reason"] == "not_at_fort", "not_at_fort at another fort")
	s.relish["state"] = "dead"
	t.ok(s.cmd_begin_dungeon("old-sluice")["reason"] == "dead", "dead")
	t.ok(s.cmd_begin_dungeon("nope")["reason"] == "unknown_fort", "unknown_fort is checked first")
	s.relish["state"] = "at_fort"
	s.cmd_set_time_scale(4)
	s.cmd_pause(true)
	b = s.cmd_begin_dungeon("old-sluice")
	t.ok(b["ok"] and b["reason"] == "" and b["run_id"] == 1 and b["seed_rev"] == s.rev, "begin ok: run 1, seed_rev = rev")
	t.ok(s.time_scale == 1.0 and s.paused == false, "time scale forced to 1 and unpaused")
	var v := s.view_relish()
	t.ok(v["state"] == "in_dungeon" and v["run_id"] == 1 and v["run_kind"] == "raid" and v["reason"] == "busy"
		and v["can_descend"] == false, "view_relish reflects the open run")
	t.ok(s.cmd_begin_dungeon("old-sluice")["reason"] == "busy", "busy while a run is open")
	t.ok(s.cmd_begin_dungeon("nope")["reason"] == "unknown_fort", "unknown_fort beats busy")
	t.ok(s.cmd_begin_boss()["reason"] == "busy", "boss: busy")
	t.ok(s.raiding_fort_id() == "old-sluice", "raiding_fort_id is the open raid's fort")

	# --- the dungeon seed (7.1) ---
	var sd: Dictionary = b["seed"]
	_types_ok(t, sd, {"v": TYPE_INT, "kind": TYPE_STRING, "run_id": TYPE_INT, "seed_rev": TYPE_INT,
		"rng_seed": TYPE_STRING, "fort": TYPE_DICTIONARY, "living": TYPE_FLOAT, "dead": TYPE_FLOAT,
		"undead": TYPE_FLOAT, "garrison_units": TYPE_INT, "garrison_in_mass": TYPE_FLOAT, "garrison_mass_div": TYPE_FLOAT,
		"starter_units": TYPE_INT, "party": TYPE_ARRAY, "digest_q": TYPE_FLOAT,
		"phylactery_charges": TYPE_INT, "phylactery_max_per_dungeon": TYPE_INT, "clones_ready": TYPE_INT,
		"warden": TYPE_DICTIONARY, "warden_spec": TYPE_DICTIONARY, "loot_table_id": TYPE_STRING,
		"loot_hint": TYPE_STRING, "chest_husk": TYPE_BOOL, "watchtower": TYPE_BOOL, "relish_hp": TYPE_FLOAT,
		"death_ends": TYPE_DICTIONARY}, "dungeon seed")  # (death_ends: api_version 6, E2b-2 T3.3c)
	_types_ok(t, sd["fort"], {"id": TYPE_STRING, "name": TYPE_STRING, "tier": TYPE_INT, "cap": TYPE_FLOAT,
		"first_clear": TYPE_BOOL, "first_dungeon": TYPE_BOOL, "clears_since_retaken": TYPE_INT,
		"yield_mult": TYPE_FLOAT}, "seed.fort")
	t.ok(sd["v"] == 2 and sd["kind"] == "raid" and sd["run_id"] == 1 and sd["seed_rev"] == b["seed_rev"], "v, kind, ids")
	t.ok(sd["fort"]["id"] == "old-sluice" and sd["fort"]["first_dungeon"] and sd["fort"]["first_clear"], "Old Sluice is the first dungeon")
	t.ok(sd["starter_units"] == 8 and sd["chest_husk"] == true and sd["party"].is_empty(), "starter party of 8, husk chest, empty party")
	t.ok(sd["warden"] == {"archetype": "bellringer", "tier": 1} and sd["loot_table_id"] == "t1.bellringer", "warden stub and loot table id")
	t.ok(sd["warden_spec"] == {} and sd["watchtower"] == false and sd["relish_hp"] == 30.0, "spec, watchtower, hp")
	var f := s.realm.fort_by_id("old-sluice")
	var div := 10.0
	t.ok(sd["garrison_units"] == clampi(int(f["undead"] / div), 0, 12), "garrison_units formula")
	t.near(sd["garrison_in_mass"], sd["garrison_units"] * div, 1e-9, "garrison_in_mass = units x div")
	t.ok(sd["garrison_mass_div"] == div, "the seed carries garrison_mass_div (§7.1)")
	t.ok(sd["rng_seed"].to_int() != 0 and str(sd["rng_seed"].to_int()) == sd["rng_seed"], "rng_seed is a decimal 64-bit String")
	t.ok(s.view_dungeon_seed("old-sluice") == sd, "view_dungeon_seed returns the same seed")
	t.ok(s.view_dungeon_seed("ashgate").is_empty() and s.view_boss_seed().is_empty(), "other seeds are {}")
	sd["living"] = -1.0
	t.ok(s.view_dungeon_seed("old-sluice")["living"] != -1.0, "seeds are deep copies")

	# --- abort ---
	t.ok(s.cmd_abort_dungeon() == {"ok": true, "reason": "", "run_id": 1}, "abort returns the run id")
	t.ok(s.view_relish()["state"] == "at_fort" and s.view_relish()["run_id"] == -1 and s.raiding_fort_id() == "", "abort: back at the fort, run closed")
	t.ok(s.view_dungeon_seed("old-sluice").is_empty(), "seed gone after abort")
	t.ok(s.cmd_abort_dungeon() == {"ok": false, "reason": "no_run", "run_id": -1}, "no_run")

	# --- run ids increase, seed_rev recorded, seeds deterministic ---
	s.tick(5.0)
	var b2 := s.cmd_begin_dungeon("old-sluice")
	t.ok(b2["run_id"] == 2 and b2["seed_rev"] > b["seed_rev"], "run ids increase, seed_rev follows rev")
	t.ok(s.run["seed_rev"] == b2["seed_rev"], "seed_rev recorded on the run")
	t.ok(b2["seed"]["rng_seed"] != sd["rng_seed"], "rng_seed differs per run")
	s.cmd_abort_dungeon()
	var other := _mk()
	other.cmd_debug_set_state({"relish_at": "old-sluice"})
	t.ok(other.cmd_begin_dungeon("old-sluice")["seed"]["rng_seed"] == sd["rng_seed"], "same game seed + run id: same rng_seed")
	# another fort: not the first dungeon
	s.cmd_debug_set_state({"relish_at": "ashgate"})
	var b3 := s.cmd_begin_dungeon("ashgate")
	t.ok(b3["seed"]["starter_units"] == 0 and b3["seed"]["fort"]["first_dungeon"] == false and b3["seed"]["chest_husk"] == false,
		"no starter party elsewhere")
	t.ok(b3["seed"]["loot_table_id"].begins_with("t%d." % b3["seed"]["fort"]["tier"]), "loot table id uses the tier")
	s.cmd_abort_dungeon()
	# garrison clamp
	s.cmd_debug_set_state({"forts": {"ashgate": {"undead": 1.0e9}}})
	b3 = s.cmd_begin_dungeon("ashgate")
	t.ok(b3["seed"]["garrison_units"] == 8, "garrison_units follows the (cap-clamped) undead")
	s.cmd_abort_dungeon()
	s.cmd_debug_set_state({"relish_at": "whitecross"})
	s.cmd_debug_set_state({"forts": {"whitecross": {"undead": 1.0e9}}})
	b3 = s.cmd_begin_dungeon("whitecross")
	t.ok(b3["seed"]["garrison_units"] == 12 and b3["seed"]["garrison_in_mass"] == 120.0, "garrison_units clamps at garrison_max")
	s.cmd_abort_dungeon()

	# --- boss ---
	s = _mk()
	fail = {"ok": false, "reason": "not_at_vei", "seed": {}, "run_id": -1, "seed_rev": -1}
	t.ok(s.cmd_begin_boss() == fail, "boss needs at_vei")
	s.cmd_debug_set_state({"relish_at": "old-sluice"})
	t.ok(s.cmd_begin_boss()["reason"] == "not_at_vei", "not at Vei from a fort")
	s.relish["state"] = "dead"
	t.ok(s.cmd_begin_boss()["reason"] == "dead", "boss: dead")
	s.relish["state"] = "home"
	s.cmd_debug_grant({"backlog": 6000.0})
	s.cmd_debug_set_state({"relish_at": "vei"})
	s.cmd_set_time_scale(4)
	var bb := s.cmd_begin_boss()
	t.ok(bb["ok"] and bb["run_id"] == 1 and s.view_relish()["state"] == "in_boss" and s.view_relish()["run_kind"] == "boss", "boss begins")
	t.ok(s.time_scale == 1.0 and not s.paused, "boss forces time scale 1")
	var bs: Dictionary = bb["seed"]
	_types_ok(t, bs, {"v": TYPE_INT, "kind": TYPE_STRING, "run_id": TYPE_INT, "seed_rev": TYPE_INT,
		"rng_seed": TYPE_STRING, "backlog": TYPE_FLOAT, "living_pool": TYPE_FLOAT, "odds": TYPE_FLOAT,
		"sign": TYPE_INT, "drain_s": TYPE_FLOAT, "digest_q": TYPE_FLOAT, "vei_capacity": TYPE_FLOAT,
		"fronts": TYPE_ARRAY, "fronts_required": TYPE_INT, "party": TYPE_ARRAY,
		"phylactery_charges": TYPE_INT, "clones_ready": TYPE_INT, "relish_hp": TYPE_FLOAT,
		"death_ends": TYPE_DICTIONARY}, "boss seed")  # (death_ends: api_version 6, E2b-2 T3.3c)
	t.ok(bs["kind"] == "boss" and bs["v"] == 2 and bs["backlog"] == 6000.0 and bs["vei_capacity"] == 50.0, "boss seed values")
	t.ok(bs["fronts_required"] == 3 and bs["fronts"].size() == 4, "fronts_required 3, four fronts")
	var fr: Array = bs["fronts"]
	t.ok(fr.map(func(x): return x["id"]) == GameState.FRONT_IDS and fr[0] == {"id": "giants", "need": 0.0, "have": 0.0, "assigned": []},
		"fronts in FRONT_IDS order, zeroed")
	t.ok(bs["sign"] in [-1, 0, 1] and (bs["sign"] < 0) == (bs["drain_s"] >= 0.0), "drain_s only when the differential is negative")
	t.ok(s.view_boss_seed() == bs and s.view_dungeon_seed("vei").is_empty(), "view_boss_seed returns the seed")
	t.ok(s.cmd_abort_dungeon()["ok"] and s.view_relish()["state"] == "at_vei", "aborting a boss run: back at_vei")

	# --- debug: refusals ---
	s = _mk()
	s.debug_enabled = false
	t.ok(s.cmd_debug_skip_time(5.0) == {"ok": false, "reason": "not_debug", "substeps": 0}, "skip_time: not_debug")
	t.ok(s.cmd_debug_set_state({"paused": true})["reason"] == "not_debug", "set_state: not_debug first")
	t.ok(s.cmd_debug_grant({"bogus": 1}) == {"ok": false, "reason": "not_debug", "key": "", "applied": {}}, "grant: not_debug beats unknown_key")
	s.debug_enabled = true
	var g0: float = s.town_sim.gold
	rv = s.rev
	var r := s.cmd_debug_grant({"gold": 50, "husks": -1})
	t.ok(r == {"ok": false, "reason": "bad_value", "key": "husks", "applied": {}} and s.town_sim.gold == g0 and s.rev == rv,
		"bad_value is atomic (nothing applied)")
	r = s.cmd_debug_grant({"gold": "50"})
	t.ok(r["reason"] == "bad_value" and r["key"] == "gold", "a string is a bad value")
	r = s.cmd_debug_grant({"gold": NAN})
	t.ok(r["reason"] == "bad_value", "NaN is a bad value")
	r = s.cmd_debug_grant({"husks": 1.5})
	t.ok(r["reason"] == "bad_value", "counts must be whole")
	r = s.cmd_debug_grant({"gold": 5, "nope": 1, "husks": -1})
	t.ok(r["reason"] == "unknown_key" and r["key"] == "nope", "unknown_key outranks bad_value")
	r = s.cmd_debug_set_state({"paused": true, "nope": 1})
	t.ok(r["reason"] == "unknown_key" and r["key"] == "nope" and not s.paused, "set_state: unknown_key atomic")
	r = s.cmd_debug_set_state({"time_scale": 100.5})
	t.ok(r["reason"] == "bad_value" and r["key"] == "time_scale", "time_scale above 100")
	t.ok(s.cmd_debug_set_state({"time_scale": 100.0})["ok"] and s.time_scale == 100.0, "time_scale 100 ok")
	t.ok(s.cmd_debug_set_state({"paused": 1})["reason"] == "bad_value", "paused must be a bool")
	t.ok(s.cmd_debug_set_state({"relish_at": "nope"})["reason"] == "bad_value", "relish_at: unknown node")
	t.ok(s.cmd_debug_set_state({"valve": {"work": 0, "war": 0, "flood": 0}})["reason"] == "bad_value", "valve: all zero")
	t.ok(s.cmd_debug_set_state({"valve": {"work": 1, "war": -1, "flood": 1}})["reason"] == "bad_value", "valve: negative")
	t.ok(s.cmd_debug_set_state({"forge_level": -1})["reason"] == "bad_value", "forge_level >= 0")
	t.ok(s.cmd_debug_set_state({"forts": {"nope": {"living": 1.0}}})["reason"] == "bad_value", "forts: unknown fort")
	t.ok(s.cmd_debug_set_state({"forts": {"ashgate": {"living": -1.0}}})["reason"] == "bad_value", "forts: negative mass")
	t.ok(s.cmd_debug_set_state({"forge_level": 2, "time_scale": 0})["reason"] == "bad_value" and s.town_sim.forge["level"] == 0,
		"the whole patch is validated before anything applies")

	# --- debug: grants and clamps ---
	s = _mk()
	s.debug_enabled = true
	var ts := s.town_sim
	var before := {"gold": ts.gold, "bone": ts.bone, "bod": ts.bodies, "liv": ts.living, "w": ts.workers}
	r = s.cmd_debug_grant({"gold": 500.0, "bone": 200.0, "bodies": 60.0, "living": 3.0, "workers": 20, "backlog": 18000.0})
	t.ok(r["ok"] and r["key"] == "" and r["applied"]["minted"] == [], "grant ok, nothing minted")
	t.near(ts.gold, before["gold"] + 500.0, 1e-9, "gold lands on TownSim's gold")
	t.near(ts.bone, before["bone"] + 200.0, 1e-9, "bone on its bone")
	t.near(ts.bodies, before["bod"] + 60.0, 1e-9, "bodies")
	t.near(ts.living, before["liv"] + 3.0, 1e-9, "living")
	t.ok(ts.workers == before["w"] + 20.0 and ts.staffing["idle"] == ts.workers - 7.0, "workers, restaffed at once (7 slots)")
	t.near(s.realm.vei["undead_queue"], 18000.0, 1e-9, "backlog lands on vei.undead_queue")
	t.ok(r["applied"]["gold"] == 500.0 and r["applied"]["workers"] == 20.0 and r["applied"]["workers"] is float and r["applied"]["backlog"] == 18000.0, "applied echoes the deltas")
	r = s.cmd_debug_grant({"relics": 100, "essence": 1000})
	t.ok(s.relics == 12 and s.essence == 60 and r["applied"]["relics"] == 12 and r["applied"]["essence"] == 60, "relics and essence clamp to their caps")
	r = s.cmd_debug_grant({"relics": -100, "gold": -1.0e9})
	t.ok(s.relics == 0 and r["applied"]["relics"] == -12 and s.town_sim.gold == 0.0, "negative removes, floored at 0")
	t.near(r["applied"]["gold"], -(before["gold"] + 500.0), 1e-9, "applied gold is the actual (clamped) delta")
	s.cmd_debug_grant({"backlog": -1.0e9})
	t.ok(s.realm.vei["undead_queue"] == 0.0, "backlog floored at 0")

	# --- debug: caps on big_undead and living, forge_level type ---
	s = _mk()
	s.debug_enabled = true
	r = s.cmd_debug_grant({"big_undead": 5})
	t.ok(r["ok"] and s.big_undead.size() == 4 and r["applied"]["big_undead"] == 4 and r["applied"]["minted"].size() == 4,
		"big_undead mints only up to the cap (4)")
	t.ok(s.cmd_debug_grant({"big_undead": 5})["applied"] == {"big_undead": 0, "minted": []}, "big_undead at its cap mints nothing")
	s = _mk()
	s.debug_enabled = true
	s.cmd_debug_grant({"big_undead": 3})
	r = s.cmd_debug_grant({"big_undead": 5})
	t.ok(s.big_undead.size() == 4 and r["applied"]["big_undead"] == 1, "existing count counts toward the cap")
	r = s.cmd_debug_grant({"living": 1000.0, "bodies": 1000.0})
	t.ok(s.town_sim.living == 16.0 and r["applied"]["living"] == 6.0, "living clamps to living_cap() (opening.living_cap at the start)")
	t.ok(s.town_sim.bodies == 200.0 and r["applied"]["bodies"] == 160.0, "bodies clamp to body_cap()")
	rv = s.rev
	r = s.cmd_debug_set_state({"forge_level": 1.5})
	t.ok(r["reason"] == "bad_value" and r["key"] == "forge_level" and s.town_sim.forge["level"] == 0 and s.rev == rv,
		"forge_level 1.5 refused, nothing changes")

	# --- debug: minting ---
	s = _mk()
	s.debug_enabled = true
	r = s.cmd_debug_grant({"husks": 3, "remnants": 4, "big_undead": 2})
	var m: Array = r["applied"]["minted"]
	t.ok(r["ok"] and m.size() == 9 and r["applied"]["husks"] == 3 and r["applied"]["remnants"] == 4, "nine items minted")
	var seen := {}
	for u in m:
		seen[u] = true
	t.ok(seen.size() == 9, "minted uids are unique across kinds")
	t.ok(s.husks.size() == 3 and s.remnants.size() == 4 and s.big_undead.size() == 2, "stored in the inventories")
	t.ok(s.husks[0]["uid"].begins_with("h") and s.remnants[0]["uid"].begins_with("r") and s.big_undead[0]["uid"].begins_with("u"), "uid prefixes")
	t.ok(GameState.HUSK_KINDS.has(s.husks[0]["kind"]) and GameState.RARITIES.has(s.husks[0]["rarity"]), "husk kind and rarity from the lists")
	var rm: Dictionary = s.remnants[0]
	t.ok(GameState.STATS.has(rm["aspect"]) and GameState.RARITIES.has(rm["rarity"]) and rm["magnitude"] is int
		and rm["magnitude"] >= 1 and rm["magnitude"] <= 5, "remnant aspect, rarity, magnitude 1..5")
	var bu: Dictionary = s.big_undead[0]
	var stats_ok: bool = bu["stats"].size() == 5
	for k in GameState.STATS:
		stats_ok = stats_ok and bu["stats"][k] is float and bu["stats"][k] >= 1.0 and bu["stats"][k] <= 10.0
	t.ok(stats_ok and bu["name"] == "Big " + bu["uid"] and bu["place"] == "crypt" and bu["front"] == "",
		"big undead: float stats 1..10, name, crypt, no front")
	var roles: Dictionary = TestUtil.configs()["town"]["slab"]["role_by_stat"]
	var top := "power"
	for k in GameState.STATS:
		if bu["stats"][k] > bu["stats"][top]:
			top = k
	t.ok(bu["role"] == roles[top] and s.big_undead.all(func(b): return TestUtil.configs()["town"]["slab"]["roles"].has(b["role"])),
		"its role is SlabLogic's for its highest stat (%s: %s), a role id the slab knows" % [top, bu["role"]])
	var s2 := _mk()
	s2.debug_enabled = true
	s2.cmd_debug_grant({"husks": 3, "remnants": 4, "big_undead": 2})
	t.ok(s2.husks == s.husks and s2.big_undead == s.big_undead, "minting is deterministic for a seed")
	r = s.cmd_debug_grant({"husks": 1})
	t.ok(r["applied"]["minted"][0] == "h10", "the counter keeps running")
	s.cmd_new_game(2)
	r = s.cmd_debug_grant({"husks": 1})
	t.ok(r["applied"]["minted"][0] == "h11", "the uid counter survives a new game")

	# --- debug: set_state effects ---
	s = _mk()
	s.debug_enabled = true
	r = s.cmd_debug_set_state({"relish_at": "ashgate", "paused": true, "won": true, "forge_level": 3.0})
	t.ok(r["ok"] and s.view_relish()["state"] == "at_fort" and s.view_relish()["at"] == "ashgate" and s.paused and s.won
		and s.town_sim.forge == {"level": 3, "progress": 0.0}, "relish_at, paused, won, forge_level (TownSim's)")
	s.cmd_debug_set_state({"paused": false})
	s.cmd_debug_set_state({"relish_at": "vei"})
	t.ok(s.view_relish()["state"] == "at_vei", "relish_at vei")
	s.cmd_move_relish("covington")
	s.relish["state"] = "dead"
	s.cmd_debug_set_state({"relish_at": "covington"})
	t.ok(s.view_relish()["state"] == "home" and s.view_relish()["dead_s_left"] == 0.0 and s.view_relish()["effects"]["home"],
		"relish_at puts her alive and standing")
	s.cmd_debug_set_state({"valve": {"work": 2, "war": 2, "flood": 1}})
	t.near(s.valve["work"], 0.4, 1e-9, "valve normalised")
	t.ok(s.valve == s.valve_target, "valve current and target set")
	s.cmd_debug_set_state({"forts": {"ashgate": {"living": 5.0, "undead": 1.0e9, "dead": 2.0}}})
	var af := s.realm.fort_by_id("ashgate")
	t.ok(af["living"] == 5.0 and af["dead"] == 2.0 and af["undead"] == af["cap"], "fort masses set, clamped to the cap")
	s.cmd_debug_set_state({"relish_at": "ashgate"})
	s.cmd_begin_dungeon("ashgate")
	rv = s.rev
	r = s.cmd_debug_set_state({"relish_at": "covington", "paused": true})
	t.ok(r == {"ok": false, "reason": "busy", "key": "relish_at"} and not s.paused and s.rev == rv, "relish_at is busy during a run, atomically")
	t.ok(s.cmd_debug_set_state({"paused": true})["ok"], "other keys still work in a run")

	# --- skip_time ---
	s = _mk()
	s.debug_enabled = true
	s.cmd_pause(true)
	r = s.cmd_debug_skip_time(60.0)
	t.ok(r["ok"] and r["substeps"] == 120 and absf(s.t - 60.0) < 1e-9, "skip_time runs 120 substeps, ignoring pause")
	t.ok(s.paused, "still paused afterwards")
	for bad in [0.0, -5.0, 86401.0, INF, NAN]:
		t.ok(s.cmd_debug_skip_time(bad) == {"ok": false, "reason": "bad_value", "substeps": 0}, "skip_time(%s): bad_value" % str(bad))
	t.ok(s.cmd_debug_skip_time(600.0)["substeps"] == 1200, "skip_time accepts a long skip")
	return t.failures
