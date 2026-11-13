extends RefCounted
## GameState: what is real behind the remaining commands (STATE-API §4.2-4.4) and the views
## that echo them (§5). Key sets and types are test_api_contract's job; this
## suite checks behaviour and reasons. Headless, no autoloads.

## STATE-API §1.4's building ids, in order.
const BUILDING_IDS := ["crypt", "raising_pit", "charnel_house", "market", "house", "well", "bakery",
	"bone_mill", "inn", "forge", "graveyard", "embalmer", "stables", "chapel_of_vats", "ossuary_tower",
	"guildhall", "watchtower", "walls", "plaza", "statue", "reliquary"]

var t: TestUtil


func _mk() -> GameState:
	var s := GameState.new(TestUtil.configs())
	s.cmd_new_game(1)
	s.debug_enabled = true
	return s


func run() -> int:
	t = TestUtil.new()
	t.suite("game-state-commands")
	_valve()
	_haul()
	_ladder()
	_staff_caps()
	_stances()
	_big_undead()
	_busy_in_run()
	_stubs()
	_vats()
	_town_views()
	_buildings_config()
	_realm_views()
	_agreement()
	return t.failures


func _bu(s: GameState, uid: String) -> Dictionary:
	for b in s.view_big_undead()["big_undead"]:
		if b["uid"] == uid:
			return b
	return {}


func _bld(s: GameState, lot_id: String) -> Dictionary:
	for b in s.view_town()["buildings"]:
		if b["lot_id"] == lot_id:
			return b
	return {}


func _ids(arr: Array, key := "id") -> Array:
	return arr.map(func(e): return e[key])


func _no_rev(v: Dictionary) -> Dictionary:
	var d := v.duplicate(true)
	d.erase("rev")
	return d


# ---------------------------------------------------------------- §4.2 valve ----
func _valve() -> void:
	var s := _mk()
	var h := s.view_hud()
	t.near(h["valve"]["work"] + h["valve"]["war"] + h["valve"]["flood"], 1.0, 1e-12, "the start valve sums to 1")
	t.near(h["valve_target"]["war"], 0.45, 1e-12, "the start valve is BALANCE §0's")
	var rv := s.rev
	var r := s.cmd_set_valve(2, 2, 1)
	t.ok(r["ok"] and r["reason"] == "" and s.rev == rv + 1, "cmd_set_valve(2, 2, 1) ok")
	t.near(r["target"]["work"], 0.4, 1e-12, "normalised work 0.4")
	t.near(r["target"]["war"], 0.4, 1e-12, "normalised war 0.4")
	t.near(r["target"]["flood"], 0.2, 1e-12, "normalised flood 0.2")
	h = s.view_hud()
	t.ok(h["valve_target"] == r["target"] and h["valve"] != r["target"], "target echoed; the current vector slews toward it (game_state_macro)")
	rv = s.rev
	for c in [[NAN, 1.0, 1.0, "not_finite"], [1.0, INF, 1.0, "not_finite"], [NAN, -1.0, 0.0, "not_finite"],
			[-1.0, 1.0, 1.0, "negative"], [0.0, 0.0, -INF, "not_finite"], [0.0, -0.5, 0.0, "negative"],
			[0.0, 0.0, 0.0, "zero_valve"]]:
		r = s.cmd_set_valve(c[0], c[1], c[2])
		t.ok(r == {"ok": false, "reason": c[3], "target": {}}, "cmd_set_valve(%s, %s, %s) -> %s" % [c[0], c[1], c[2], c[3]])
	t.ok(s.rev == rv and s.view_hud()["valve_target"] == h["valve_target"], "refusals change nothing")
	r = s.cmd_set_valve(1.0e308, 1.0e308, 1.0e308)
	t.near(r["target"]["war"], 1.0 / 3.0, 1e-12, "huge inputs normalise without overflow")
	r = s.cmd_set_valve(0, 3, 0)
	t.ok(r["target"] == {"work": 0.0, "war": 1.0, "flood": 0.0}, "one non-zero dial takes it all")


# ----------------------------------------------------------------- §4.2 haul ----
func _haul() -> void:
	var s := _mk()
	t.ok(s.view_town()["haul"] == {"target": "auto", "current": "", "convoys": []}, "haul target auto, no convoy at the start")
	var r := s.cmd_set_haul_target("greywall")
	t.ok(r == {"ok": true, "reason": "", "haul_target": "greywall"}, "a fort id is accepted")
	t.ok(s.haul_target == "greywall" and s.view_town()["haul"]["target"] == "greywall", "it is stored and echoed")
	s.tick(1.0)  # the Charnel House's haulers leave on the first substep and move on the second
	var hv: Dictionary = s.view_town()["haul"]
	t.ok(s.town_sim.haul["convoys"].size() == 1 and s.town_sim.haul["convoys"][0]["fort"] == "greywall", "TownSim's convoy honours it")
	t.ok(hv["current"] == "greywall" and hv["convoys"].size() == 1 and hv["convoys"][0]["to"] == "greywall"
		and hv["convoys"][0]["from"] == "covington" and hv["convoys"][0]["phase"] == "out", "the convoy shows in view_town")
	t.ok(hv["convoys"][0]["t"] > 0.0 and hv["convoys"][0]["t"] < 1.0, "trip progress is between 0 and 1")
	r = s.cmd_set_haul_target("auto")
	t.ok(r["ok"] and r["haul_target"] == "auto" and s.view_town()["haul"]["target"] == "auto"
		and s.view_town()["haul"]["current"] == "greywall", "auto is stored; the convoy out finishes its trip")
	var rv := s.rev
	for bad in ["nope", "covington", "vei", "", "bellwether"]:
		t.ok(s.cmd_set_haul_target(bad) == {"ok": false, "reason": "unknown_fort", "haul_target": ""}, "haul target '%s': unknown_fort" % bad)
	t.ok(s.rev == rv and s.haul_target == "auto", "refusals change nothing")


# --------------------------------------------------------------- §4.3 ladder ----
func _ladder() -> void:
	var s := _mk()
	var v := s.view_town()
	t.ok(v["ladder"] == ["build", "haul", "pit", "stall", "mill", "forge", "tend"] and v["ladder_effective"] == v["ladder"],
		"the default ladder (economy.json job.default_ladder)")
	t.ok(_ids(v["jobs"]) == ["haul", "pit", "stall"], "jobs in ladder order, those with slots only")
	var order := ["tend", "forge", "mill", "stall", "pit", "haul", "build"]
	var r := s.cmd_set_job_priority(order)
	t.ok(r == {"ok": true, "reason": "", "order": order}, "a permutation is accepted")
	v = s.view_town()
	t.ok(v["ladder"] == order and v["ladder_effective"] == order and _ids(v["jobs"]) == ["stall", "pit", "haul"],
		"echoed; jobs follow it (no stances until E3)")
	var rv := s.rev
	for c in [[["haul", "mill", "stall", "forge", "pit", "tend", "nope"], "unknown_job"],
			[["haul", "haul", "stall", "forge", "pit", "tend", "nope"], "unknown_job"],
			[["haul", "mill", "stall", "forge", "pit", "tend", 7], "unknown_job"],
			[["haul", "haul", "stall", "forge", "pit", "tend", "build"], "duplicate_job"],
			[["haul", "mill", "stall", "forge", "pit", "tend", "build", "haul"], "duplicate_job"],
			[["haul", "mill", "stall"], "missing_job"],
			[[], "missing_job"]]:
		r = s.cmd_set_job_priority(c[0])
		t.ok(r == {"ok": false, "reason": c[1], "order": []}, "%s -> %s" % [str(c[0]), c[1]])
	t.ok(s.rev == rv and s.view_town()["ladder"] == order, "refusals change nothing")
	r = s.cmd_set_job_priority([&"haul", &"mill", &"stall", &"forge", &"pit", &"tend", &"build"])
	t.ok(r["ok"] and r["order"][0] is String and s.view_town()["ladder"][0] is String, "StringNames are stored as Strings")


# ----------------------------------------------------------- §4.3 staff caps ----
func _staff_caps() -> void:
	var s := _mk()
	var b := _bld(s, "lot-03")
	t.ok(b["building_id"] == "charnel_house" and b["slots"] == 3 and b["staffed"] == 3.0 and b["staff_cap"] == -1,
		"charnel house: 3 haul slots, full, no cap")
	t.near(s.view_town()["workers"]["idle"], 5.0, 1e-9, "BALANCE §0's 12 workers fill 7 slots, 5 idle")
	var r := s.cmd_set_staff_cap("lot-03", 1)
	t.ok(r == {"ok": true, "reason": "", "cap": 1}, "cap 1 accepted")
	b = _bld(s, "lot-03")
	t.ok(b["staff_cap"] == 1 and b["staffed"] == 1.0 and s.town_sim.buildings["lot-03"]["staff_cap"] == 1,
		"the cap is echoed, is TownSim's and limits the staffing")
	t.near(s.view_town()["workers"]["idle"], 7.0, 1e-9, "the freed workers idle")
	t.ok(s.cmd_set_staff_cap("lot-03", 9)["cap"] == 9 and _bld(s, "lot-03")["staffed"] == 3.0, "a cap above the slots is accepted (effective min)")
	t.ok(s.cmd_set_staff_cap("lot-03", 0)["ok"] and _bld(s, "lot-03")["staffed"] == 0.0, "cap 0 empties it")
	t.ok(s.cmd_set_staff_cap("lot-03", -1)["cap"] == -1 and _bld(s, "lot-03")["staff_cap"] == -1, "-1 removes the cap")
	var rv := s.rev
	for c in [["lot-99", 1, "unknown_lot"], ["", 1, "unknown_lot"], ["lot-99", -5, "unknown_lot"],
			["lot-05", 1, "empty_lot"], ["lot-05", -5, "empty_lot"], ["lot-01", 1, "no_jobs"],
			["lot-01", -5, "no_jobs"], ["lot-03", -2, "bad_cap"]]:
		t.ok(s.cmd_set_staff_cap(c[0], c[1]) == {"ok": false, "reason": c[2], "cap": 0},
			"cmd_set_staff_cap(%s, %d) -> %s" % [c[0], c[1], c[2]])
	t.ok(s.rev == rv, "refusals leave rev alone")
	s.cmd_set_staff_cap("lot-02", 1)
	s.cmd_new_game(2)
	t.ok(_bld(s, "lot-02")["staff_cap"] == -1, "a new game clears the caps")


# -------------------------------------------------------------- §4.3 stances ----
func _st(v: Dictionary, id: String) -> Dictionary:
	for e in v["stances"]:
		if e["id"] == id:
			return e
	return {}


func _stances() -> void:
	var s := _mk()
	var v := s.view_stances()
	t.ok(v["slots"] == 3 and v["used"] == 0, "at home: stance.base_slots (2) + 1")
	t.ok(_ids(v["stances"]) == GameState.STANCE_IDS and v["stances"].all(func(e): return not e["on"] and not e["suspended"]),
		"one entry per STANCE_IDS, all off")
	t.ok(_st(v, "vigil") == {"id": "vigil", "on": false, "suspended": false, "active": false, "fired_beat_id": -1,
		"hold_s_left": 0.0, "projected": {}}, "E1 entry: nothing fires or projects")
	t.ok(s.cmd_set_stance("harvest", true) == {"ok": true, "reason": "", "slots": 3, "used": 1}, "turn one on")
	s.cmd_set_stance("vigil", true)
	t.ok(s.cmd_set_stance("muster", true)["used"] == 3, "third slot")
	var rv := s.rev
	t.ok(s.cmd_set_stance("thrift", true) == {"ok": false, "reason": "no_slot", "slots": 0, "used": 0} and s.rev == rv,
		"no_slot with every slot used")
	t.ok(s.cmd_set_stance("harvest", true) == {"ok": true, "reason": "", "slots": 3, "used": 3}, "an on stance turned on again: no-op ok")
	s.cmd_move_relish("old-sluice")  # she leaves home: one slot fewer
	v = s.view_stances()
	t.ok(v["slots"] == 2 and v["used"] == 2, "away from home: 2 slots, 2 used")
	t.ok(_st(v, "muster")["on"] and _st(v, "muster")["suspended"] and not _st(v, "vigil")["suspended"]
		and not _st(v, "harvest")["suspended"], "the most recently enabled is suspended, not switched off")
	t.ok(s.cmd_set_stance("thrift", true)["reason"] == "no_slot", "no slot while one is suspended")
	t.ok(s.cmd_set_stance("harvest", false) == {"ok": true, "reason": "", "slots": 2, "used": 2}, "turning one off")
	t.ok(not _st(s.view_stances(), "muster")["suspended"], "the suspended stance resumes when a slot frees")
	t.ok(s.cmd_set_stance("harvest", false)["ok"], "turning an off stance off never fails")
	t.ok(s.cmd_set_stance("nope", true)["reason"] == "unknown_stance" and s.cmd_set_stance("nope", false)["reason"] == "unknown_stance",
		"unknown_stance")
	s.legacy_teleport_relish("covington")
	t.ok(s.view_stances()["slots"] == 3 and s.cmd_set_stance("thrift", true)["used"] == 3, "home again: 3 slots")
	s.tick(10.0)
	t.ok(s.view_stances()["beat_id"] == int(floor(s.t / 1.714)) and s.view_stances()["beat_id"] == 5, "beat_id = floor(t / beat_s)")


# -------------------------------------------------- §4.3/4.4 big undead, party ----
func _big_undead() -> void:
	var s := _mk()
	s.cmd_debug_grant({"big_undead": 2})
	var u1: String = s.big_undead[0]["uid"]
	var u2: String = s.big_undead[1]["uid"]
	# rename
	var r := s.cmd_rename_big_undead(u1, "  Old Gristle  ")
	t.ok(r == {"ok": true, "reason": "", "name": "Old Gristle"} and _bu(s, u1)["name"] == "Old Gristle", "rename strips the edges")
	t.ok(s.cmd_rename_big_undead(u1, "x".repeat(24))["ok"], "24 characters is fine")
	for bad in ["", "   ", "x".repeat(25)]:
		t.ok(s.cmd_rename_big_undead(u1, bad) == {"ok": false, "reason": "bad_name", "name": ""}, "bad_name: '%s'" % bad)
	t.ok(s.cmd_rename_big_undead("u999", "") == {"ok": false, "reason": "unknown_uid", "name": ""}, "unknown_uid first")
	s.cmd_rename_big_undead(u1, "Old Gristle")
	# party and fronts
	r = s.cmd_set_party([u2, u1])
	t.ok(r == {"ok": true, "reason": "", "party": [u2, u1]}, "set_party echoes the order")
	t.ok(_ids(s.view_party()["party"], "uid") == [u2, u1] and _bu(s, u1)["place"] == "party", "members are placed in the party, in order")
	t.ok(s.cmd_assign_front(u1, "giants") == {"ok": true, "reason": ""}, "assign a front")
	t.ok(_bu(s, u1)["front"] == "giants" and s.view_vei()["fronts"][0]["assigned"] == [u1], "the front is echoed in view_vei")
	t.ok(s.cmd_assign_front(u1, "")["ok"] and _bu(s, u1)["front"] == "", "\"\" unassigns")
	s.cmd_assign_front(u1, "carvers")
	r = s.cmd_set_party([u2])
	t.ok(r["party"] == [u2] and _bu(s, u1)["place"] == "crypt" and _bu(s, u1)["front"] == "",
		"a former member returns to the crypt and loses its front")
	var rv := s.rev
	t.ok(s.cmd_assign_front(u1, "giants")["reason"] == "not_in_party", "not_in_party")
	t.ok(s.cmd_assign_front(u2, "nope")["reason"] == "unknown_front", "unknown_front")
	t.ok(s.cmd_assign_front("u999", "nope")["reason"] == "unknown_uid", "unknown_uid before the front check")
	t.ok(s.cmd_set_party([u2, u2]) == {"ok": false, "reason": "duplicate_uid", "party": []}, "duplicate_uid")
	t.ok(s.cmd_set_party(["u999", u2, u2])["reason"] == "unknown_uid", "unknown_uid before duplicate_uid")
	t.ok(s.cmd_set_party([7])["reason"] == "unknown_uid", "a non-String uid is unknown")
	t.ok(s.rev == rv and _ids(s.view_party()["party"], "uid") == [u2], "refusals change nothing")
	t.ok(s.cmd_set_party([])["party"] == [] and _bu(s, u2)["place"] == "crypt", "an empty party sends everyone to the crypt")
	# place
	s.cmd_set_party([u1, u2])
	s.cmd_assign_front(u1, "giants")
	r = s.cmd_place_big_undead(u1, "town:lot-04")
	t.ok(r == {"ok": true, "reason": "", "place": "town:lot-04"}, "foreman at lot-04")
	t.ok(_bu(s, u1)["front"] == "" and _ids(s.view_party()["party"], "uid") == [u2] and _bld(s, "lot-04")["foreman"] == u1,
		"it leaves the party (and its front) and shows as the foreman")
	t.ok(s.cmd_place_big_undead(u1, "town:lot-04")["ok"], "placing the same foreman again is fine")
	rv = s.rev
	for c in [[u2, "town:lot-04", "foreman_taken"], [u2, "town:lot-05", "empty_lot"], [u2, "town:lot-99", "unknown_lot"],
			[u2, "town:", "unknown_lot"], [u2, "fort:nope", "unknown_fort"], [u2, "fort:", "unknown_fort"],
			[u2, "fort:covington", "unknown_fort"], [u2, "nowhere", "bad_place"], [u2, "party", "bad_place"],
			[u2, "", "bad_place"], [u2, "Crypt", "bad_place"], ["u999", "nowhere", "unknown_uid"]]:
		t.ok(s.cmd_place_big_undead(c[0], c[1]) == {"ok": false, "reason": c[2], "place": ""}, "place %s at '%s' -> %s" % c)
	t.ok(s.rev == rv, "refusals leave rev alone")
	t.ok(s.cmd_place_big_undead(u2, "fort:ashgate")["ok"] and s.view_fort("ashgate")["siege"] == [u2]
		and s.view_party()["party"].is_empty(), "siege at Ashgate, out of the party")
	t.ok(s.cmd_place_big_undead(u1, "crypt")["ok"] and _bld(s, "lot-04")["foreman"] == "", "back to the crypt frees the lot")
	t.ok(s.cmd_place_big_undead(u2, "town:lot-04")["ok"] and _bld(s, "lot-04")["foreman"] == u2
		and s.view_fort("ashgate")["siege"] == [], "a siege can move to the town")


func _busy_in_run() -> void:
	var s := _mk()
	s.cmd_debug_grant({"big_undead": 2})
	var u1: String = s.big_undead[0]["uid"]
	var u2: String = s.big_undead[1]["uid"]
	s.cmd_set_party([u1])
	s.legacy_teleport_relish("old-sluice")
	t.ok(s.cmd_begin_dungeon("old-sluice")["ok"], "a run opens")
	var rv := s.rev
	t.ok(s.cmd_set_party([u2])["reason"] == "busy" and s.cmd_set_party([])["reason"] == "busy", "set_party: busy during a run")
	t.ok(s.cmd_assign_front(u1, "giants")["reason"] == "busy", "assign_front: busy during a run")
	t.ok(s.cmd_assign_front(u2, "giants")["reason"] == "busy", "assign_front: busy for any uid while a run is open")
	t.ok(s.cmd_place_big_undead(u1, "crypt")["reason"] == "busy", "place: busy for a member of the run's party")
	t.ok(s.cmd_place_big_undead("u999", "crypt")["reason"] == "unknown_uid", "place: unknown_uid before busy")
	t.ok(s.rev == rv and _bu(s, u1)["place"] == "party", "refusals change nothing")
	t.ok(s.cmd_place_big_undead(u2, "fort:vespers")["ok"], "place: a big undead outside the run's party may move")
	t.ok(s.cmd_rename_big_undead(u1, "Mid-run")["ok"], "rename works during a run")
	s.cmd_abort_dungeon()
	t.ok(s.cmd_place_big_undead(u1, "crypt")["ok"], "after the run it may move")
	s.cmd_set_party([u1])
	s.cmd_assign_front(u1, "raw")
	s.legacy_teleport_relish("vei")
	s.cmd_begin_boss()
	t.ok(s.cmd_set_party([])["reason"] == "busy" and s.cmd_place_big_undead(u1, "crypt")["reason"] == "busy", "busy in the boss run too")
	t.ok(s.view_boss_seed()["party"][0]["front"] == "raw" and s.view_boss_seed()["fronts"][3]["assigned"] == [u1],
		"the boss seed carries the party's fronts")
	s.cmd_abort_dungeon()


# --------------------------------------------------- §1.1 E2/E3 action stubs ----
func _snapshot(s: GameState) -> Array:
	return [_no_rev(s.view_town()), _no_rev(s.view_catalog()), _no_rev(s.view_inventory()),
		_no_rev(s.view_big_undead()), _no_rev(s.view_backups()), _no_rev(s.view_hud())]


func _stubs() -> void:
	var s := _mk()
	s.cmd_debug_grant({"husks": 1, "remnants": 2, "relics": 5, "essence": 30})
	var h: String = s.husks[0]["uid"]
	var r1: String = s.remnants[0]["uid"]
	var r2: String = s.remnants[1]["uid"]
	var before := _snapshot(s)
	var rv := s.rev
	t.ok(s.cmd_craft("phylactery_charge") == {"ok": true, "reason": "", "count": 0}, "craft: ok, count 0")
	t.ok(s.cmd_deploy_simulacrum("vespers") == {"ok": true, "reason": "", "charges": 0.0, "ready_left": 0}, "deploy: ok, nothing planted")
	var raised := s.cmd_raise_big_undead(h, [r1, r2], "Old Gristle")
	t.ok(raised["ok"] and raised["big_undead"] == {"uid": "", "name": "", "kind": "", "role": "",
		"stats": {"power": 0.0, "beef": 0.0, "wits": 0.0, "presence": 0.0, "speed": 0.0}, "place": "", "front": ""},
		"raise: ok with a full-shape zero entry")
	t.ok(s.rev == rv + 3, "each stub success adds 1 to rev")
	t.ok(_snapshot(s) == before and s.realm.simulacra.is_empty(), "the stubs change nothing")
	t.ok(s.cmd_build("nope", "lot-99") == {"ok": false, "reason": "unknown_building", "cost": {}}, "build: unknown_building first")
	t.ok(s.cmd_build("house", "lot-99")["reason"] == "unknown_lot", "build: unknown_lot")
	t.ok(s.cmd_upgrade("lot-25") == {"ok": false, "reason": "unknown_lot", "level": 0, "cost": {}}, "upgrade: unknown_lot")
	t.ok(s.cmd_demolish("") == {"ok": false, "reason": "unknown_lot"}, "demolish: unknown_lot")
	t.ok(s.cmd_cancel_build("x") == {"ok": false, "reason": "unknown_lot", "refund": {}}, "cancel_build: unknown_lot")
	t.ok(s.cmd_craft("relic") == {"ok": false, "reason": "unknown_item", "count": 0}, "craft: unknown_item")
	t.ok(s.cmd_deploy_simulacrum("vei") == {"ok": false, "reason": "unknown_fort", "charges": 0.0, "ready_left": 0}, "deploy: unknown_fort")
	# the raise stub's checks, in order
	for c in [["h999", [r1], "unknown_husk"], [h, ["r999"], "unknown_remnant"], [h, [r1, r1], "duplicate_remnant"],
			[h, ["r999", r1, r1], "unknown_remnant"], [h, [7], "unknown_remnant"]]:
		t.ok(s.cmd_raise_big_undead(c[0], c[1], "x") == {"ok": false, "reason": c[2], "big_undead": {}},
			"raise(%s, %s) -> %s" % c)
	t.ok(s.cmd_raise_big_undead(h, [], "")["ok"], "raise stub: no remnants and no name pass (recipe and name checks are E2)")
	s.cmd_move_relish("old-sluice")
	t.ok(s.cmd_raise_big_undead("h999", [], "x")["reason"] == "not_home", "raise: not_home before the item checks")


# ----------------------------------------------------------------- vats ----
func _vats() -> void:
	var s := _mk()
	t.ok(s.cmd_staff_vat(0, true) == {"ok": false, "reason": "unknown_slot", "staffed": false}, "no vat slots at the start")
	var v := s.view_backups()
	t.ok(v["vats"] == [] and v["clones_ready"] == 0 and v["phylactery_charges"] == 0 and v["phylactery_max_per_dungeon"] == 1,
		"no vats, no backups")
	t.ok(v["death"] == {"outcome": "unmade", "respawn_s": 0.0, "loses": ["unbanked_loot", "morale"]},
		"a death now: unmade (the E1-safe rule, an immediate respawn until E3)")
	s.clones_ready = 1
	t.ok(s.cmd_staff_vat(0, true)["reason"] == "unknown_slot", "a clone stock alone makes no vat: it takes a Chapel of Vats")
	s.town_sim.place_building("lot-13", "chapel_of_vats", 1)
	t.ok(s.cmd_staff_vat(1, true) == {"ok": true, "reason": "", "staffed": true}, "staff vat 1")
	v = s.view_backups()
	t.ok(v["clones_ready"] == 1 and v["vats"] == [{"slot": 0, "staffed": false, "grow": 1.0, "ready": true},
		{"slot": 1, "staffed": true, "grow": 0.0, "ready": false}], "a level-1 Chapel is 2 vats, one ready for the clone; staffing echoed")
	t.ok(v["death"]["outcome"] == "clone" and v["death"]["loses"] == ["unbanked_loot"], "with a clone: no morale shock")
	s.cmd_debug_grant({"big_undead": 1})
	s.cmd_set_party([s.big_undead[0]["uid"]])
	t.ok(s.view_backups()["death"]["loses"] == ["party", "unbanked_loot"], "a party would be lost (A8)")
	t.ok(s.cmd_staff_vat(1, false)["staffed"] == false and not s.view_backups()["vats"][1]["staffed"], "unstaff")
	for bad in [-1, 2, 99]:
		t.ok(s.cmd_staff_vat(bad, true)["reason"] == "unknown_slot", "slot %d: unknown_slot" % bad)


# ------------------------------------------------------------ town views ----
func _town_views() -> void:
	var s := _mk()
	var v := s.view_town()
	t.ok(v["tier"] == "hamlet" and v["next_tier"] == {"tier": "village", "have": 4, "need": 6, "missing": ["house"]},
		"hamlet; village needs 6 buildings incl. a house")
	var town_lots: Array = TestUtil.configs()["town"]["lots"]
	t.ok(_ids(v["lots"]) == _ids(town_lots) and v["lots"].size() == 24, "24 lots from town.json, by id")
	var sizes_ok := true
	for i in 24:
		sizes_ok = sizes_ok and v["lots"][i]["size"] == int(town_lots[i]["size"]) and v["lots"][i]["unlocked"] == (i < 8)
	t.ok(sizes_ok, "lot sizes from town.json; Hamlet unlocks the first 8")
	t.ok(_ids(v["lots"].slice(0, 5), "building_id") == ["crypt", "raising_pit", "charnel_house", "market", ""],
		"the start buildings on lots 1-4")
	t.ok(_ids(v["buildings"], "lot_id") == ["lot-01", "lot-02", "lot-03", "lot-04"], "one buildings entry per built lot")
	var m := _bld(s, "lot-04")
	t.ok(m["building_id"] == "market" and m["level"] == 1 and m["state"] == "active" and m["progress"] == 1.0
		and m["slots"] == 2 and m["upkeep"] == {"gold": 0.03, "bone": 0.0} and m["foreman"] == "", "the small market (2 stalls)")
	t.ok(m["output"] == {"gold": 0.3}, "its output: min(2 · 0.15, 10 · 0.03) gold/s (%s)" % str(m["output"]))
	t.ok(_bld(s, "lot-02")["output"] == {"mint": 6.0, "burn": 0.6} and _bld(s, "lot-01")["output"] == {},
		"the pit: P_per_pit mint and its burn; the crypt: none")
	var ts := s.town_sim
	t.ok(v["gold"] == ts.gold and v["bone"] == ts.bone and v["bodies"] == ts.bodies and v["bodies_cap"] == 200.0
		and [v["gold"], v["bone"], v["bodies"]] == [80.0, 30.0, 40.0], "the stocks are TownSim's, BALANCE §0's 80/30/40 (§5.9)")
	t.ok(v["workers"]["total"] == 12.0 and v["workers"]["total"] == ts.workers and absf(v["workers"]["lifetime_s"] - 480.0 / 0.7) < 1e-9
		and v["living"] == 10.0 and v["living_cap"] == 16.0, "12 workers, living 10 of 16; Relish home: lifetime 480 / 0.7")
	s.cmd_debug_grant({"gold": 50.0, "bone": 18.0, "bodies": 40.0, "workers": 6, "living": 2})
	var vg: Dictionary = s.view_town()
	t.ok(vg["gold"] == 130.0 and vg["bone"] == 48.0 and vg["bodies"] == 80.0 and vg["workers"]["total"] == 18.0 and vg["living"] == 12.0,
		"a debug grant shows up in view_town")
	var hg: Array = s.view_hud()["rates"]
	t.ok(hg[3]["stock"] == vg["gold"] and hg[4]["stock"] == vg["bone"] and hg[2]["stock"] == vg["bodies"]
		and hg[1]["stock"] == vg["workers"]["total"] and hg[5]["stock"] == vg["living"], "view_hud and view_town agree on every stock")
	t.ok(v["morale"] == {"value": 0.6, "target": 0.6, "factors": [{"id": "base", "delta": 0.6}]}, "morale at its base")
	t.ok(v["relish_home"], "relish_home")
	var hud := s.view_hud()
	t.ok(_ids(hud["rates"]) == GameState.HUD_RATE_IDS, "view_hud.rates follow HUD_RATE_IDS")
	t.ok(hud["rates"][3]["stock"] == ts.gold and hud["rates"][4]["stock"] == ts.bone
		and hud["rates"][1]["stock"] == ts.workers, "view_hud stocks are TownSim's (§5.1)")
	t.ok(hud["rates"][0]["stock"] == -1.0 and hud["rates"][0]["cap"] == -1.0 and hud["rates"][2]["cap"] == 200.0
		and hud["rates"][5]["cap"] == 16.0, "mint has no stock or cap; bodies and living are capped")
	t.ok(hud["relics_cap"] == 12 and hud["essence_cap"] == 60 and hud["won"] == false, "caps and won")
	var rates: Dictionary = s.view_rates()["rates"]
	var keys := rates.keys()
	keys.sort()
	var want := GameState.RATE_IDS.duplicate()
	want.sort()
	t.ok(keys == want and rates["gold"]["unit"] == "gold/s" and rates["workers"]["unit"] == "workers/s", "view_rates: every RATE_IDS key, with units")
	# the catalog
	var c := s.view_catalog()
	t.ok(_ids(c["buildings"], "building_id") == BUILDING_IDS, "view_catalog: one entry per building, §1.4 order")
	var by := {}
	for e in c["buildings"]:
		by[e["building_id"]] = e
	t.ok(by["house"]["can_build"] and by["house"]["reason"] == "" and by["house"]["lots"] == ["lot-05", "lot-06", "lot-07", "lot-08"]
		and by["house"]["cost"] == {"gold": 40.0, "bone": 10.0, "relics": 0} and by["house"]["count"] == 0, "house: buildable on lots 5-8")
	t.ok(by["inn"]["reason"] == "needs_tier" and by["inn"]["lots"] == [] and not by["inn"]["can_build"], "inn: needs_tier")
	t.ok(by["embalmer"]["reason"] == "needs_tier" and by["embalmer"]["requires"]["blueprint"] == "embalmer", "embalmer: village and a blueprint")
	t.ok(by["crypt"]["count"] == 1 and by["crypt"]["reason"] == "no_lot", "crypt: built once, no free 2-lot at Hamlet")
	t.ok(c["crafts"] == [{"item_id": "simulacrum", "cost": {"essence": 20, "relics": 1}, "can_craft": false, "reason": "needs_building"},
		{"item_id": "phylactery_charge", "cost": {"essence": 15, "relics": 0}, "can_craft": false, "reason": "needs_building"}],
		"crafts need the Ossuary Tower")
	t.ok(c["blueprints"] == [{"id": "embalmer", "owned": false}, {"id": "ossuary_tower", "owned": false},
		{"id": "reliquary", "owned": false}], "the three blueprints")
	s.blueprints.append("embalmer")
	t.ok(s.view_catalog()["blueprints"][0]["owned"] and s.view_inventory()["blueprints"] == ["embalmer"], "owned blueprints echoed")
	var house := func() -> String:
		for e in s.view_catalog()["buildings"]:
			if e["building_id"] == "house":
				return e["reason"]
		return "?"
	ts.gold = 10.0
	t.ok(house.call() == "no_gold", "view_catalog no_gold reads TownSim's gold")
	ts.gold = 80.0
	ts.bone = 5.0
	t.ok(house.call() == "no_bone", "view_catalog no_bone reads TownSim's bone")


## buildings.json: the shape every entry has, and values the views rely on.
func _buildings_config() -> void:
	var cfg: Dictionary = TestUtil.configs()["buildings"]
	t.ok(cfg.keys() == BUILDING_IDS, "buildings.json: one entry per §1.4 building id, in order")
	var town_lots: Array = TestUtil.configs()["town"]["lots"]
	var lot_size := {}
	for l in town_lots:
		lot_size[l["id"]] = int(l["size"])
	for id in cfg:
		var b: Dictionary = cfg[id]
		var good: bool = b.has_all(["cost", "upkeep", "build_work", "lot_size", "max_level", "level_costs", "requires", "jobs", "effects"])
		good = good and b["cost"].has_all(["gold", "bone", "relics"]) and b["upkeep"].has_all(["gold", "bone"])
		good = good and b["requires"].has_all(["tier", "blueprint", "building"]) and GameState.TIERS.has(b["requires"]["tier"])
		good = good and (b["requires"]["blueprint"] == "" or b["requires"]["blueprint"] == id)
		good = good and (b["requires"]["building"] == "" or cfg.has(b["requires"]["building"]))
		good = good and int(b["lot_size"]) >= 1 and int(b["lot_size"]) <= 3 and int(b["max_level"]) >= 1
		good = good and b["level_costs"].size() == int(b["max_level"]) - 1
		for j in b["jobs"]:
			good = good and GameState.JOB_IDS.has(j)
		t.ok(good, "buildings.json %s has the full shape" % id)
	var start: Dictionary = TestUtil.configs()["economy"]["opening"]["buildings"]
	for lot in start:
		t.ok(int(cfg[start[lot]]["lot_size"]) <= lot_size[lot], "start building %s fits %s" % [start[lot], lot])
	t.ok(int(cfg["crypt"]["lot_size"]) == 2 and int(cfg["walls"]["lot_size"]) == 3 and int(cfg["reliquary"]["lot_size"]) == 3,
		"crypt 2, walls 3, reliquary 3")
	var bps := []
	for id in cfg:
		if cfg[id]["requires"]["blueprint"] != "":
			bps.append(id)
	t.ok(bps == ["embalmer", "ossuary_tower", "reliquary"], "blueprints gate the Embalmer, Ossuary Tower and Reliquary")


# ----------------------------------------------------------- realm views ----
func _realm_views() -> void:
	var s := _mk()
	s.tick(5.0)
	var lanes: Array = s.view_lanes()["lanes"]
	var ok_war := true
	for i in 12:
		var f: Dictionary = s.realm.forts[i]
		var l: Dictionary = lanes[i]
		ok_war = ok_war and l["id"] == "war:covington:" + f["id"] and l["from"] == "covington" and l["to"] == f["id"]
		ok_war = ok_war and l["kind"] == "war" and l["rate"] == f["r_in"] and l["bias"] == 1.0 and l["why"] == ""
	t.ok(ok_war and lanes[0]["rate"] > 0.0, "WAR lanes first: every fort (all have living), world order, at the dispatch rate")
	t.ok(lanes[12] == {"id": "flood:covington:vei", "from": "covington", "to": "vei", "kind": "flood", "rate": s.realm.r_flood, "bias": 1.0, "why": ""}
		and s.realm.r_flood > 0.0, "then the FLOOD lane to Vei at the valve's FLOOD")
	t.ok(lanes.all(func(l): return l["rate"] > 0.0 or l["why"] != ""), "zero-rate lanes without a callout are omitted")
	var realm := s.view_realm()
	t.ok(realm["size"] == [2048.0, 1440.0] and realm["covington"]["pos"] == [1780.0, 1270.0], "size and Covington")
	t.ok(realm["vei"]["pos"] == [1024.0, 130.0] and realm["vei"]["radius"] == 150.0 and realm["vei"]["pool_cap"] == 600.0, "Vei")
	var fv := s.view_fort("old-sluice")
	fv.erase("rev")
	t.ok(realm["forts"].size() == 12 and realm["forts"][1] == fv, "view_realm.forts are view_fort without rev")
	t.ok(fv["first_dungeon"] and fv["first_clear"] and fv["loot_hint"] == "a husk and a blueprint" and fv["warden"]["archetype"] == "bellringer",
		"Old Sluice is the first dungeon")
	t.ok(not s.view_fort("ashgate")["first_dungeon"] and s.view_fort("ashgate")["loot_hint"] == "", "Ashgate is not")
	t.near(fv["space"], maxf(0.0, fv["cap"] - fv["living"] - fv["undead"] - fv["dead"]), 1e-9, "space = cap - masses")
	t.ok(fv["threat"]["risk"] == "low" and fv["threat"]["risk_pct"] == -1.0 and fv["tithe"]["eta_s"] == -1.0, "E1 threat and tithe stubs")
	t.ok(not fv["relish_here"] and s.view_party()["fort_id"] == "", "she is home")
	s.legacy_teleport_relish("old-sluice")
	var p := s.view_party()
	t.ok(s.view_fort("old-sluice")["relish_here"] and p["fort_id"] == "old-sluice" and p["starter_units"] == 8, "at Old Sluice: here, starter party 8")
	var g := s.cmd_begin_dungeon("old-sluice")
	t.ok(p["garrison_units"] == g["seed"]["garrison_units"] and p["garrison_in_mass"] == g["seed"]["garrison_in_mass"],
		"view_party's garrison is what the descent takes in")
	t.ok(s.view_fort("old-sluice")["relish_here"], "still here while in its dungeon")
	s.cmd_abort_dungeon()
	s.legacy_teleport_relish("ashgate")
	t.ok(s.view_party()["starter_units"] == 0 and s.view_party()["fort_id"] == "ashgate", "no starter party elsewhere")
	var vil: Array = s.view_villages()["villages"]
	t.ok(vil.size() == 12 and vil.all(func(x): return ["player", "vei", "none"].has(x["owner"])), "12 villages with an owner")
	t.ok(vil.all(func(x): return (x["migrants"] > 0.0) == (x["owner"] == "player")), "only player villages send migrants")
	var vf := s.view_field()
	t.ok(vf["field"] == s.field and vf["world_size"] == [2048.0, 1440.0] and vf["tick_hz"] == 5.0, "view_field: the live field")
	var vv := s.view_vei()
	t.ok(_ids(vv["fronts"]) == GameState.FRONT_IDS and vv["fronts_required"] == 3 and vv["fronts_met"] == 0, "four fronts, 3 required")
	t.ok(vv["tithe"]["target"] == "" and vv["tithe"]["eta_s"] == -1.0 and not vv["tithe"]["warning"], "no flip yet, so no tithe")
	var l := s.ledger()
	t.ok(l["sources"].values().all(func(x): return x == 0.0) and l["held"].size() == 9, "ledger: E2 stub, all zero")


# ----------------------------------------- can_descend / can_begin agreement ----
## view_fort(id).can_descend/reason and view_vei().can_begin/reason must say what the
## commands would return, in every Relish state.
func _agree(s: GameState, tag: String) -> void:
	var good := true
	for f in s.realm.forts:
		var id: String = f["id"]
		var vf := s.view_fort(id)
		var rel := s.view_relish()
		var r := s.cmd_begin_dungeon(id)
		good = good and vf["reason"] == r["reason"] and vf["can_descend"] == r["ok"]
		if rel["at"] == id:
			good = good and rel["can_descend"] == r["ok"] and rel["reason"] == r["reason"]
		if r["ok"]:
			s.cmd_abort_dungeon()
	t.ok(good, "%s: view_fort agrees with cmd_begin_dungeon for every fort" % tag)
	var vv := s.view_vei()
	var b := s.cmd_begin_boss()
	t.ok(vv["reason"] == b["reason"] and vv["can_begin"] == b["ok"], "%s: view_vei agrees with cmd_begin_boss (%s)" % [tag, b["reason"]])
	if b["ok"]:
		s.cmd_abort_dungeon()


func _agreement() -> void:
	var s := _mk()
	_agree(s, "home")
	s.cmd_move_relish("ashgate")
	s.tick(0.5)
	_agree(s, "travelling")
	s.legacy_teleport_relish("ashgate")
	_agree(s, "at Ashgate")
	s.legacy_teleport_relish("vei")
	_agree(s, "at Vei")
	s.legacy_teleport_relish("whitecross")
	s.cmd_begin_dungeon("whitecross")
	_agree(s, "in a dungeon")
	s.cmd_abort_dungeon()
	s.legacy_teleport_relish("vei")
	s.cmd_begin_boss()
	_agree(s, "in the boss")
	s.cmd_abort_dungeon()
	s.relish["state"] = "dead"  # no E1 path leaves her dead (the respawn is immediate)
	_agree(s, "dead")
