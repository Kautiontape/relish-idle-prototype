extends RefCounted
## E3-3, big undead (MECHANICS §4.6; STATE-API §4.3 cmd_raise_big_undead, §5.12, §7.1, §7.2, §9.1). The raise:
## - each refusal, in check order: not_home, unknown_husk, unknown_remnant, duplicate_remnant, invalid_recipe (the
##   town unit's SlabLogic.evaluate says not ok), at_cap, bad_name; a refusal consumes nothing and leaves rev alone;
## - a raise consumes exactly the husk and those remnants, mints u<n> from the uid counter, adds 1 to rev and raises
##   no event; the entry's stats, role and filled_slots are SlabLogic's for the same inputs;
## - at_cap at view_big_undead().cap, and the cap rising with the Crypt's level (big_undead.per_crypt_level);
## filled_slots (api-request #6):
## - save -> load keeps it (through the save's JSON); a save without it loads 1 (the run's manager's ruling), so
##   every fixture does; a non-int one is corrupt;
## - both seeds' party entries carry it (and the contract's SEED_PARTY / BOSS_PARTY).
## (test_api_v6's run-checkpoint case has the pre_vei boss seed against the parent's.)

var t := TestUtil.new()
var slab: Dictionary


func run() -> int:
	t.suite("big_undead")
	slab = TestUtil.configs()["town"]["slab"]
	_refusals()
	_order()
	_consumes()
	_matches_slab()
	_cap()
	_names()
	_save_load()
	_old_save()
	_seeds()
	return t.failures


func _mk() -> GameState:
	var s := GameState.new(TestUtil.configs())
	s.cmd_new_game(1)
	s.debug_enabled = true
	return s


## A husk of `kind`, minted as the save mints one (its uid from the counter).
func _husk(s: GameState, kind: String) -> String:
	var uid := s._mint_uid("h")
	s.husks.append({"uid": uid, "kind": kind, "rarity": "common"})
	return uid


## A remnant of `aspect` and `magnitude`.
func _rem(s: GameState, aspect: String, magnitude: int) -> String:
	var uid := s._mint_uid("r")
	s.remnants.append({"uid": uid, "aspect": aspect, "rarity": "common", "magnitude": magnitude})
	return uid


func _uids(items: Array) -> Array:
	return items.map(func(e): return e["uid"])


## Each refusal on its own; none consumes anything or moves rev.
func _refusals() -> void:
	var s := _mk()
	var h := _husk(s, "hulk")
	var beef := _rem(s, "beef", 3)
	var pres := _rem(s, "presence", 2)
	var cases := [
		[h, ["r999"], "x", "unknown_remnant"], ["h999", [beef], "x", "unknown_husk"], [h, [beef, beef], "x", "duplicate_remnant"],
		[h, [pres], "x", "invalid_recipe"],  # a hulk has no presence slot and no anima: the remnant stays unplaced
		[h, [], "x", "invalid_recipe"],  # nothing placed: under slab.min_remnants
		[h, [beef], "", "bad_name"], [h, [beef], "   ", "bad_name"], [h, [beef], "x".repeat(25), "bad_name"],
	]
	var before := [_uids(s.husks), _uids(s.remnants), s.big_undead.size(), s.rev, s.next_uid]
	for c in cases:
		var r := s.cmd_raise_big_undead(c[0], c[1], c[2])
		t.ok(r == {"ok": false, "reason": c[3], "big_undead": {}}, "raise(%s, %s, '%s') -> %s" % [c[0], str(c[1]), c[2], c[3]])
	t.ok([_uids(s.husks), _uids(s.remnants), s.big_undead.size(), s.rev, s.next_uid] == before, "the refusals consume nothing, mint nothing and leave rev")
	var ghost := _husk(s, "ghost")
	t.ok(s.cmd_raise_big_undead(ghost, [beef], "x")["reason"] == "invalid_recipe", "a kind the slab doesn't know: invalid_recipe")
	s.cmd_debug_grant({"big_undead": 4})
	t.ok(s.big_undead.size() == s.view_big_undead()["cap"] and s.cmd_raise_big_undead(h, [beef], "x")["reason"] == "at_cap",
		"at the cap (%d): at_cap" % s.view_big_undead()["cap"])
	s.cmd_move_relish("old-sluice")
	t.ok(s.cmd_raise_big_undead(h, [beef], "x")["reason"] == "not_home", "Relish away: not_home")


## The order between the three E3-3 checks: the recipe, then the cap, then the name.
func _order() -> void:
	var s := _mk()
	var h := _husk(s, "hulk")
	var beef := _rem(s, "beef", 3)
	var pres := _rem(s, "presence", 2)
	t.ok(s.cmd_raise_big_undead(h, [pres], "")["reason"] == "invalid_recipe", "an invalid recipe with a bad name: invalid_recipe first")
	s.cmd_debug_grant({"big_undead": 4})
	t.ok(s.cmd_raise_big_undead(h, [pres], "x")["reason"] == "invalid_recipe", "an invalid recipe at the cap: invalid_recipe before at_cap")
	t.ok(s.cmd_raise_big_undead(h, [beef], "")["reason"] == "at_cap", "a good recipe at the cap with a bad name: at_cap before bad_name")
	t.ok(s.cmd_raise_big_undead("h999", [pres], "")["reason"] == "unknown_husk", "the id checks come before all three")


## A raise takes exactly its husk and remnants, mints the next uid, +1 rev, no event; the rest stays.
func _consumes() -> void:
	var s := _mk()
	var h1 := _husk(s, "hulk")
	var h2 := _husk(s, "skeleton")
	var r1 := _rem(s, "beef", 3)
	var r2 := _rem(s, "power", 2)
	var r3 := _rem(s, "wits", 4)
	var r4 := _rem(s, "speed", 1)
	s.drain_events()
	var uid := "u%d" % s.next_uid
	var rv := s.rev
	var r := s.cmd_raise_big_undead(h1, [r3, r1], "Old Gristle")
	t.ok(r["ok"] and r["reason"] == "", "a hulk with wits and beef raises")
	t.ok(_uids(s.husks) == [h2] and _uids(s.remnants) == [r2, r4], "it consumed exactly that husk and those remnants: %s, %s" % [str(_uids(s.husks)), str(_uids(s.remnants))])
	t.ok(s.big_undead.size() == 1 and s.big_undead[0]["uid"] == uid and r["big_undead"]["uid"] == uid and s.next_uid == int(uid.trim_prefix("u")) + 1,
		"it minted %s from the uid counter" % uid)
	t.ok(s.rev == rv + 1 and s.drain_events().is_empty(), "+1 rev, and no event (STATE-API §6 lists none)")
	var e: Dictionary = s.view_big_undead()["big_undead"][0]
	t.ok(r["big_undead"] == e and e["place"] == "crypt" and e["front"] == "" and e["name"] == "Old Gristle" and e["kind"] == "hulk",
		"its entry: in the crypt, no front, its name and its husk's kind, as view_big_undead shows it")
	var errs: Array = []
	ApiSchema.check_command("cmd_raise_big_undead", r, errs)
	t.ok(errs.is_empty(), "the result is in the contract (BIG_UNDEAD with filled_slots): %s" % str(errs))
	t.ok(s.cmd_raise_big_undead(h1, [r2], "again")["reason"] == "unknown_husk" and s.cmd_raise_big_undead(h2, [r1], "again")["reason"] == "unknown_remnant",
		"the spent husk and remnant are gone")


## The entry's stats, role and filled_slots are SlabLogic's for the same kind and remnants, in the order given.
func _matches_slab() -> void:
	var cases := [
		["hulk", [["beef", 3], ["power", 2]]],  # 2 of 4 slots
		["lich", [["wits", 2], ["speed", 1], ["presence", 4]]],  # presence falls to the anima slot
		["revenant", [["power", 1], ["beef", 2], ["presence", 3], ["wits", 4], ["speed", 5]]],  # every slot
		["skeleton", [["speed", 5]]],
		["wraith", [["presence", 2], ["presence", 2], ["wits", 1]]],
	]
	for c in cases:
		var s := _mk()
		var h := _husk(s, c[0])
		var ids: Array = []
		var recs: Array = []
		for a in c[1]:
			var id := _rem(s, a[0], a[1])
			ids.append(id)
			recs.append(s._find_uid(s.remnants, id).duplicate())
		var want := SlabLogic.evaluate(c[0], recs, slab)
		var r := s.cmd_raise_big_undead(h, ids, "Test")
		var e: Dictionary = r.get("big_undead", {})
		t.ok(want["ok"] and r["ok"] and e["stats"] == want["stats"] and e["role"] == want["role"]
			and typeof(e["filled_slots"]) == TYPE_INT and e["filled_slots"] == want["filled"],
			"%s %s: stats %s, role %s, filled_slots %d, SlabLogic's" % [c[0], str(c[1]), str(e.get("stats")), str(e.get("role")), int(e.get("filled_slots", -1))])
		t.ok(s.big_undead[0]["filled_slots"] == want["filled"] and s.view_big_undead()["big_undead"][0] == e, "and stored so")


## The cap: big_undead.cap at a level-1 Crypt, + per_crypt_level per level above 1.
func _cap() -> void:
	var s := _mk()
	var ec: Dictionary = TestUtil.configs()["economy"]["big_undead"]
	var base := int(ec["cap"])
	t.ok(s.view_big_undead()["cap"] == base, "a level-1 Crypt: the cap is big_undead.cap (%d)" % base)
	s.cmd_debug_grant({"big_undead": base - 1})
	var h := _husk(s, "zombie")
	var r1 := _rem(s, "beef", 2)
	t.ok(s.cmd_raise_big_undead(h, [r1], "Last One")["ok"] and s.big_undead.size() == base, "one under the cap: the raise fills it")
	h = _husk(s, "zombie")
	r1 = _rem(s, "beef", 2)
	t.ok(s.cmd_raise_big_undead(h, [r1], "One Too Many")["reason"] == "at_cap", "at the cap: at_cap")
	t.ok(s.town_sim.place_building("lot-01", "crypt", 2), "(setup) the Crypt at level 2")
	var cap2 := base + int(ec["per_crypt_level"])
	t.ok(s.view_big_undead()["cap"] == cap2, "a level-2 Crypt: the cap rises by per_crypt_level, to %d" % cap2)
	t.ok(s.cmd_raise_big_undead(h, [r1], "One More")["ok"] and s.big_undead.size() == cap2, "so one more raises")
	h = _husk(s, "zombie")
	r1 = _rem(s, "beef", 2)
	t.ok(s.cmd_raise_big_undead(h, [r1], "x")["reason"] == "at_cap", "and at the new cap: at_cap")


## The name is stored stripped; 24 characters are allowed.
func _names() -> void:
	var s := _mk()
	var h := _husk(s, "zombie")
	var r1 := _rem(s, "beef", 2)
	var r := s.cmd_raise_big_undead(h, [r1], "  Old Gristle \t")
	t.ok(r["ok"] and r["big_undead"]["name"] == "Old Gristle" and s.big_undead[0]["name"] == "Old Gristle", "the name is stored stripped")
	h = _husk(s, "zombie")
	r1 = _rem(s, "beef", 2)
	var n24 := "abcdefghijklmnopqrstuvwx"
	t.ok(s.cmd_raise_big_undead(h, [r1], n24)["big_undead"].get("name", "") == n24, "24 characters: allowed")


## A raised one with filled_slots 3 keeps it through the save's JSON; an int after the load.
func _save_load() -> void:
	var s := _mk()
	var h := _husk(s, "lich")
	var ids := [_rem(s, "wits", 2), _rem(s, "speed", 1), _rem(s, "presence", 4)]
	s.cmd_raise_big_undead(h, ids, "Three")
	var d := s.to_dict()
	t.ok(d["big_undead"][0].get("filled_slots") == 3, "the save's record carries filled_slots 3")
	var n := GameState.new(TestUtil.configs())
	var res := n.from_dict(JSON.parse_string(JSON.stringify(d)))
	var e: Dictionary = n.view_big_undead()["big_undead"][0] if res["ok"] else {}
	t.ok(res["ok"] and typeof(e.get("filled_slots")) == TYPE_INT and e["filled_slots"] == 3, "save -> load (JSON) keeps it, an int: %s" % str(e.get("filled_slots")))
	t.ok(n.to_dict() == d, "and saves back the same")


## A save without filled_slots loads 1 (the old-save rule), as every fixture does; a non-int one is corrupt.
func _old_save() -> void:
	var s := _mk()
	var h := _husk(s, "lich")
	s.cmd_raise_big_undead(h, [_rem(s, "wits", 2), _rem(s, "speed", 1), _rem(s, "presence", 4)], "Three")
	var d := s.to_dict()
	d["big_undead"][0].erase("filled_slots")
	var n := GameState.new(TestUtil.configs())
	t.ok(n.from_dict(d)["ok"] and n.view_big_undead()["big_undead"][0]["filled_slots"] == 1 and n.big_undead[0]["filled_slots"] == 1,
		"a save without filled_slots loads 1")
	for bad in [1.5, "3", true]:
		var b := d.duplicate(true)
		b["big_undead"][0]["filled_slots"] = bad
		t.ok(GameState.new(TestUtil.configs()).from_dict(b)["reason"] == "corrupt", "filled_slots %s: corrupt" % var_to_str(bad))
	for fx in GameState.FIXTURES:
		var f := _mk()
		f.cmd_debug_load_fixture(fx)
		var all_one := true
		for e in f.view_big_undead()["big_undead"]:
			all_one = all_one and typeof(e["filled_slots"]) == TYPE_INT and e["filled_slots"] == 1
		for e in f.view_party()["party"]:
			all_one = all_one and e["filled_slots"] == 1
		t.ok(all_one, "%s: its %d big undead load filled_slots 1 (no fixture carries the key)" % [fx, f.big_undead.size()])


## Both seeds' party entries carry the record's filled_slots, in the contract.
func _seeds() -> void:
	var s := _mk()
	var h := _husk(s, "revenant")
	var ids := [_rem(s, "power", 1), _rem(s, "beef", 2), _rem(s, "presence", 3), _rem(s, "wits", 4), _rem(s, "speed", 5)]
	var uid: String = s.cmd_raise_big_undead(h, ids, "Five")["big_undead"]["uid"]
	s.cmd_debug_grant({"big_undead": 1})
	var old: String = s.big_undead[1]["uid"]
	s.cmd_set_party([uid, old])
	s.cmd_assign_front(uid, "giants")
	var p: Array = s.view_party()["party"]
	t.ok(p.size() == 2 and p[0]["filled_slots"] == 5 and p[1]["filled_slots"] == 1, "view_party: 5 for the raised one, 1 for a debug mint")
	s.cmd_debug_set_state({"relish_at": "old-sluice"})
	var rs: Dictionary = s.cmd_begin_dungeon("old-sluice")["seed"]
	var errs: Array = []
	ApiSchema.check(rs, ApiSchema.RAID_SEED, "raid_seed", errs)
	t.ok(rs["party"].map(func(e): return e["filled_slots"]) == [5, 1] and errs.is_empty(),
		"the dungeon seed's party carries them, in the contract: %s" % str(errs))
	s.cmd_abort_dungeon()
	s.cmd_debug_set_state({"relish_at": "vei"})
	var bs: Dictionary = s.cmd_begin_boss()["seed"]
	errs = []
	ApiSchema.check(bs, ApiSchema.BOSS_SEED, "boss_seed", errs)
	t.ok(bs["party"].map(func(e): return e["filled_slots"]) == [5, 1] and bs["party"][0]["front"] == "giants" and errs.is_empty(),
		"the boss seed's party too, with its front: %s" % str(errs))
	s.cmd_abort_dungeon()
