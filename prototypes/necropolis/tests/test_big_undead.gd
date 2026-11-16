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
## The foreman (MECHANICS §4.2; economy.json foreman, E4 placeholders):
## - a working foreman multiplies its building's job output by foreman.mult + speed · foreman.speed_k, per kind: the
##   Market's gold, the Bone Mill's bone (not the bodies it mills), the Raising Pit's burn and its weight in the mint
##   (the raise follows the burn), the Charnel House's carry per hauler, the Forge's work, the Chapel's vat growth;
## - nothing at a passive, unpaid, Thrift-idled, mid-upgrade or unstaffed building (a foreman placed there is allowed);
## - the convoy's clamps (the fort's dead, the store's headroom) still apply after the carry's multiplier; the gold cap
##   still clips, its overflow booked; a Pit foreman keeps the mass ledger exact;
## - presence: + foreman.presence_k · presence on the morale target, a `foreman` factor, clamped with the rest;
## - view_town's foreman_mult (TOWN_BUILDING, v8);
## - with no foreman, day1 and pre_vei 6 h live and 12 h caught up hash as the parent's (0e4f932), and midgame_2flips
##   with u8 back in the crypt too; caught up matches live with the foreman on midgame over 6 h.

var t := TestUtil.new()
var slab: Dictionary
var _dir := "user://test_big_undead_%d" % OS.get_process_id()
var _mid_off: Array = []  # _identity's midgame_2flips live run with u8 in the crypt: [state, events], for _fm_catchup
const CLOCK := 1_800_000_000  # a "now" for the saves (unix seconds)
## The parent's identity (0e4f932: E3-3's raise and the town re-pin, no foreman or siege acting), from ident() below
## run on a git archive of it: each fixture under test_stances' harness configs (the field shrunk), with the big undead
## listed moved to the crypt first, 6 h live and 12 h caught up. Hashed: to_dict() less big_undead (the places) and
## api_version, the events, the away report (sha256, the first 16 hex digits). Moving u8 or u9 changed nothing there.
const PARENT := {
	"day1": {"live": {"state": "b2547329ec83e8b8", "events": "efef071d942cfa48", "n_events": 3},
		"caught": {"state": "dbed8b898b2a905b", "events": "7adf8ca1cc296dda", "away": "977a359676d37ffb", "n_events": 3, "steps": 4320}},
	"pre_vei": {"live": {"state": "0f6f9eff6af284ef", "events": "d7ade592df96c8a9", "n_events": 16},
		"caught": {"state": "882039ef76394e9d", "events": "794d7e0224d331e9", "away": "47c37eeb42384917", "n_events": 16, "steps": 4321}},
	"midgame_2flips": {"live": {"state": "e1257bdad6bdf175", "events": "40f1447a241a7e7d", "n_events": 175},
		"caught": {"state": "efb2ac63c701837d", "events": "0bc1a1375468f3e5", "away": "05cda66f6b8dc51f", "n_events": 367, "steps": 4422}},
}
## The foreman in the per-kind cases: speed 4 (m = 1.0 + 4 × 0.05 = 1.2), presence 5 (+0.05 morale).
const FM := {"speed": 4.0, "presence": 5.0}


func run() -> int:
	t.suite("big_undead")
	slab = TestUtil.configs()["town"]["slab"]
	DirAccess.make_dir_recursive_absolute(_dir)
	_refusals()
	_order()
	_consumes()
	_matches_slab()
	_cap()
	_names()
	_save_load()
	_old_save()
	_seeds()
	t.suite("big_undead-foreman")
	_fm_kinds()
	_fm_haul()
	_fm_nothing()
	_fm_presence()
	_fm_gold_cap()
	_fm_pit_ledger()
	_fm_view()
	_fm_outputs()
	_fm_stance_flows()
	_fm_clone_sync()
	_identity()
	_fm_catchup()
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


# ------------------------------------------------------------------ the foreman ----
## FM's multiplier under the shipped config: foreman.mult + 4 · foreman.speed_k.
func _m() -> float:
	var f: Dictionary = TestUtil.configs()["economy"]["foreman"]
	return float(f["mult"]) + float(FM["speed"]) * float(f["speed_k"])


static func _near(a: float, b: float, rel := 1e-9) -> bool:
	return absf(a - b) <= rel * maxf(1.0, absf(b))


## A day1 town with a building of every job kind working and staffed: the start set (Raising Pit lot-02, Charnel House
## lot-03, Market lot-04) plus a Bone Mill (lot-05), a Forge (lot-06) and a Chapel of Vats (lot-07, both vats
## staffed), 40 more workers, the body store at 150 of 200, the gold and bone far under their caps.
func _town() -> GameState:
	var s := _mk()
	var ts := s.town_sim
	ts.place_building("lot-05", "bone_mill", 1)
	ts.place_building("lot-06", "forge", 1)
	ts.place_building("lot-07", "chapel_of_vats", 1)
	s.cmd_staff_vat(0, true)
	s.cmd_staff_vat(1, true)
	s.cmd_debug_grant({"workers": 40})
	ts.bodies = 150.0
	ts.restaff()
	return s


## `s`'s town cloned twice and stepped `dt` on the same inputs, the second with an FM foreman on `lot_id`:
## [without, with, the step's out without, with].
func _pair(s: GameState, lot_id: String, dt := 0.5) -> Array:
	var inp := s._town_inputs(0.0)
	var c0 := s.town_sim.clone()
	var c1 := s.town_sim.clone()
	c1.set_foremen({lot_id: FM.duplicate()})
	var o0 := c0.step(dt, inp.duplicate(true))
	var o1 := c1.step(dt, inp.duplicate(true))
	return [c0, c1, o0, o1]


## Each job kind's output × m: the Market's gold (after the living cap on its sales), the Bone Mill's bone (from the
## same bodies), the Raising Pit's burn and its weight in the mint, the Forge's work, the Chapel's vat growth.
func _fm_kinds() -> void:
	var s := _town()
	var m := _m()
	var p := _pair(s, "lot-04")
	var g0 := float(p[0].rates["gold"]["trade"])
	var g1 := float(p[1].rates["gold"]["trade"])
	t.ok(g0 > 0.0 and _near(g1, g0 * m) and p[1].rates["trade_rate"] == p[0].rates["trade_rate"],
		"Market: gold %.4f -> %.4f /s, × m %.2f; its sales (trade_rate) unchanged" % [g0, g1, m])
	p = _pair(s, "lot-05")
	var b0 := float(p[0].rates["bone"]["mill"])
	var b1 := float(p[1].rates["bone"]["mill"])
	t.ok(b0 > 0.0 and _near(b1, b0 * m) and p[1].rates["bodies"]["mill"] == p[0].rates["bodies"]["mill"],
		"Bone Mill: bone %.4f -> %.4f /s, × m; the bodies it mills unchanged (%.4f /s)" % [b0, b1, float(p[0].rates["bodies"]["mill"])])
	p = _pair(s, "lot-02")
	var u0 := float(p[0].rates["bodies"]["pit"])
	var u1 := float(p[1].rates["bodies"]["pit"])
	var w0: float = p[0].pit_weight()
	var w1: float = p[1].pit_weight()
	var feed := float(p[0].rates["feed"])
	var term := func(w: float) -> float: return s._mint(w, feed) / (1.0 + s._pit_bonus * feed) - s._p_base
	t.ok(u0 > 0.0 and _near(u1, u0 * m) and w0 == 1.0 and _near(w1, m) and p[1].rates["feed"] == feed
		and _near(term.call(w1), term.call(w0) * m),
		"Raising Pit: burn %.3f -> %.3f /s and its weight in the mint 1 -> %.2f, so the mint's pit term × m at the same feed %.2f" % [u0, u1, w1, feed])
	p = _pair(s, "lot-06")
	var f0 := float(p[0].rates["forge"])
	var f1 := float(p[1].rates["forge"])
	t.ok(f0 > 0.0 and _near(f1, f0 * m), "Forge: work %.3f -> %.3f /s, × m" % [f0, f1])
	p = _pair(s, "lot-07")
	var h0: Array = p[2]["vat_hands"]
	var h1: Array = p[3]["vat_hands"]
	t.ok(h0.size() == 2 and float(h0[0]) > 0.0 and _near(float(h1[0]), float(h0[0]) * m) and _near(float(h1[1]), float(h0[1]) * m)
		and p[1].vat_hands() == h0, "Chapel of Vats: each vat grows on %s -> %s, × m (its hands, vat_hands(), unchanged)" % [str(h0), str(h1)])


## The Charnel House: the carry per hauler × m (the convoy's crew, fixed at departure, is its haulers × m); the fort's
## dead and the store's headroom still clamp the load after it.
func _fm_haul() -> void:
	var m := _m()
	for cs in [["open", 1000.0, 20.0], ["the fort's dead", 30.0, 20.0], ["the store's headroom", 1000.0, 170.0]]:
		var s := _town()
		s.cmd_set_haul_target("ashgate")
		s.realm.fort_by_id("ashgate")["dead"] = float(cs[1])
		s.town_sim.bodies = float(cs[2])
		var inp := s._town_inputs(0.0)
		var cl := [s.town_sim.clone(), s.town_sim.clone()]
		cl[1].set_foremen({"lot-03": FM.duplicate()})
		var crews: Array = []
		var loads: Array = []
		for c in cl:
			c.step(0.5, inp.duplicate(true))  # the convoy leaves, its crew fixed
			var cv: Dictionary = c.haul["convoys"][0]
			crews.append(float(cv["crew"]))
			c.step((1.0 - float(cv["t"])) * float(cv["trip_s"]) + 0.25, inp.duplicate(true))  # it reaches Ashgate and loads
			var back: Dictionary = c.haul["convoys"][0]
			loads.append(float(back["load"]) if back["phase"] == "back" else -1.0)
		var carry := 14.0 * float(crews[0])
		var want_ok := false
		match cs[0]:
			"open":
				want_ok = _near(float(loads[0]), carry) and _near(float(loads[1]), carry * m)
			"the fort's dead":  # clamped to its dead at the arrival (30 less what cleared on the way), in both
				want_ok = float(loads[0]) > 0.0 and float(loads[0]) <= 30.0 and loads[1] == loads[0]
			_:
				want_ok = float(loads[0]) > 0.0 and float(loads[0]) < carry and loads[1] == loads[0]
		t.ok(_near(float(crews[1]), float(crews[0]) * m) and want_ok,
			"Charnel House, %s: crew %.1f -> %.2f, load %.2f -> %.2f" % [cs[0], float(crews[0]), float(crews[1]), float(loads[0]), float(loads[1])])


## A foreman gives nothing at a passive building (the Crypt), an unpaid one, one Thrift idles, one mid-upgrade or one
## with no hands: foreman_mult 1.0, no `foreman` morale factor, and the step bit for bit the one without it.
func _fm_nothing() -> void:
	for kind in ["passive", "unpaid", "thrift", "upgrading", "unstaffed"]:
		var s := _town()
		var ts := s.town_sim
		var lot := "lot-04"
		match kind:
			"passive":
				lot = "lot-01"
			"unpaid":
				ts.buildings[lot]["state"] = "unpaid"
				ts.buildings[lot]["unpaid_s"] = 1000.0
				ts.restaff()
			"thrift":
				ts.thrift_idle([lot])
			"upgrading":
				ts.start_construction(lot, "market", 2)  # it keeps working at level 1 while it builds
				ts.restaff()
			"unstaffed":
				ts.set_staff_cap(lot, 0)
				ts.restaff()
		var pre := ts.clone()
		pre.set_foremen({lot: FM.duplicate()})
		var p := _pair(s, lot)
		var none: bool = p[1].morale_factors().all(func(f): return f["id"] != "foreman")
		t.ok(pre.foreman_mult(lot) == 1.0 and p[1].foreman_mult(lot) == 1.0 and none and p[1].rates == p[0].rates
			and p[1].to_dict() == p[0].to_dict(), "a foreman at %s %s building gives nothing: foreman_mult 1.0, no morale, the step unchanged" % [
			"a" if kind != "unpaid" and kind != "upgrading" else "an", kind])


## Presence: + foreman.presence_k · presence on the morale target, as a `foreman` factor, clamped with the rest; none
## where the foreman doesn't work. A foreman with speed 0 still works (m = foreman.mult) and lifts morale.
func _fm_presence() -> void:
	var s := _town()
	var pk := float(TestUtil.configs()["economy"]["foreman"]["presence_k"])
	var c0 := s.town_sim.clone()
	c0.restaff()
	var c1 := s.town_sim.clone()
	c1.set_foremen({"lot-04": {"speed": 0.0, "presence": 5.0}})
	c1.restaff()
	var f1: Array = c1.morale_factors().filter(func(f): return f["id"] == "foreman")
	var t0 := c0.morale_target()
	t.ok(c0.morale_factors().all(func(f): return f["id"] != "foreman") and f1.size() == 1 and _near(float(f1[0]["delta"]), pk * 5.0)
		and _near(c1.morale_target(), minf(1.0, t0 + pk * 5.0)) and c1.foreman_mult("lot-04") == 1.0,
		"presence 5: a `foreman` factor of %.3f, the target %.3f -> %.3f (speed 0: m = foreman.mult, 1.0)" % [float(f1[0]["delta"]) if f1.size() == 1 else -1.0, t0, c1.morale_target()])
	var c2 := s.town_sim.clone()
	c2.set_foremen({"lot-04": {"speed": 0.0, "presence": 1000.0}})
	c2.restaff()
	t.ok(c2.morale_target() == 1.0, "presence 1000: the target clamped at 1, like the other sources")
	var c3 := s.town_sim.clone()
	c3.set_foremen({"lot-01": {"speed": 4.0, "presence": 5.0}})
	c3.restaff()
	t.ok(c3.morale_target() == t0 and c3.morale_factors() == c0.morale_factors(), "at the Crypt (passive) it doesn't work: no presence")
	var o0 := c0.step(10.0, s._town_inputs(0.0))
	var o1 := c1.step(10.0, s._town_inputs(0.0))
	t.ok(c1.morale > c0.morale or c0.morale >= 1.0, "a step eases morale toward the higher target: %.4f vs %.4f" % [c1.morale, c0.morale])


## The gold store cap still clips with a Market foreman: gold at its cap, the overflow booked in the ledger's stores.
func _fm_gold_cap() -> void:
	var over: Array = []
	var gold: Array = []
	var cap := 0.0
	for with_fm in [false, true]:
		var s := _mk()
		if with_fm:
			s.cmd_debug_grant({"big_undead": 1})
			s.big_undead[0]["stats"]["speed"] = FM["speed"]
			s.cmd_place_big_undead(s.big_undead[0]["uid"], "town:lot-04")
		var ts := s.town_sim
		cap = ts.gold_cap()
		ts.gold = cap - 0.01
		var o0 := float(s.ledger()["stores"]["gold"]["overflow"])
		s.tick(10.0)
		over.append(float(s.ledger()["stores"]["gold"]["overflow"]) - o0)
		gold.append(ts.gold)
	t.ok(float(over[0]) > 0.0 and float(over[1]) > float(over[0]) and _near(float(gold[0]), cap) and _near(float(gold[1]), cap),
		"gold at its cap %.0f with and without the Market's foreman; its overflow booked: %.4f -> %.4f over 10 s" % [cap, float(over[0]), float(over[1])])


## A Pit foreman: its pit burns × m and weighs × m in the mint, and the mass ledger stays exact at every substep.
func _fm_pit_ledger() -> void:
	var m := _m()
	var burned: Array = []
	var weight: Array = []
	var term: Array = []
	var worst := 0.0
	for with_fm in [false, true]:
		var s := _mk()
		s.cmd_debug_grant({"bodies": 160.0})  # to the cap, through the ledger's debug source
		if with_fm:
			s.cmd_debug_grant({"big_undead": 1})
			s.big_undead[0]["stats"]["speed"] = FM["speed"]
			s.cmd_place_big_undead(s.big_undead[0]["uid"], "town:lot-02")
		var b0 := float(s.ledger()["sinks"]["burned"])
		for i in 120:
			s.tick(0.5)
			worst = maxf(worst, GameState.Ledger.error(s.ledger()))
		burned.append(float(s.ledger()["sinks"]["burned"]) - b0)
		weight.append(s.town_sim.pit_weight())
		var feed := float(s.town_sim.rates["feed"])
		term.append(float(s._split["mint"]) / (1.0 + s._pit_bonus * feed) - s._p_base)
	t.ok(weight[0] == 1.0 and _near(float(weight[1]), m) and _near(float(burned[1]), float(burned[0]) * m, 1e-6)
		and _near(float(term[1]), float(term[0]) * m, 1e-6) and worst < 1e-9,
		"Pit foreman, 60 s: burned %.3f -> %.3f, the mint's pit term %.3f -> %.3f (× m %.2f); the ledger exact every substep (worst %s)" % [
		float(burned[0]), float(burned[1]), float(term[0]), float(term[1]), m, String.num_scientific(worst)])


## view_town's foreman_mult (TOWN_BUILDING, v8): m at the working foreman's building, 1.0 elsewhere and at a passive
## one; placing there is allowed (no new refusal); moved back to the crypt it reads 1.0 at once.
func _fm_view() -> void:
	var s := _town()
	var m := _m()
	s.cmd_debug_grant({"big_undead": 2})
	var a: Dictionary = s.big_undead[0]
	var b: Dictionary = s.big_undead[1]
	a["stats"]["speed"] = FM["speed"]
	t.ok(s.cmd_place_big_undead(a["uid"], "town:lot-04")["ok"] and s.cmd_place_big_undead(b["uid"], "town:lot-01")["ok"],
		"a foreman at the Market and one at the Crypt (passive): both placed, no refusal")
	var fm := {}
	var errs: Array = []
	for e in s.view_town()["buildings"]:
		fm[e["lot_id"]] = e["foreman_mult"]
		ApiSchema.check(e, ApiSchema.TOWN_BUILDING, "town.buildings[%s]" % e["lot_id"], errs)
	t.ok(errs.is_empty() and _near(float(fm["lot-04"]), m) and fm["lot-01"] == 1.0 and fm["lot-02"] == 1.0 and fm["lot-05"] == 1.0,
		"view_town: foreman_mult %.2f at the Market, 1.0 at the Crypt and at the buildings with none; in the contract %s" % [float(fm["lot-04"]), str(errs)])
	s.cmd_place_big_undead(a["uid"], "crypt")
	var back := 0.0
	for e in s.view_town()["buildings"]:
		if e["lot_id"] == "lot-04":
			back = float(e["foreman_mult"])
	t.ok(back == 1.0, "moved to the crypt: 1.0 at once")


## Places an FM-speed big undead (granted) on each of `lots`; returns their uids.
func _foremen_at(s: GameState, lots: Array) -> Array:
	var n := s.big_undead.size()
	s.cmd_debug_grant({"big_undead": lots.size()})
	var uids: Array = []
	for i in lots.size():
		var b: Dictionary = s.big_undead[n + i]
		b["stats"]["speed"] = FM["speed"]
		b["stats"]["presence"] = FM["presence"]
		s.cmd_place_big_undead(b["uid"], "town:" + str(lots[i]))
		uids.append(b["uid"])
	return uids


## view_town's `output` shows a working foreman's building × m: the Market's gold, the Raising Pit's mint and burn,
## the Bone Mill's bone, the Forge's work, against the same view with the foremen in the crypt.
func _fm_outputs() -> void:
	var s := _town()
	var m := _m()
	var uids := _foremen_at(s, ["lot-02", "lot-04", "lot-05", "lot-06"])
	var on := {}
	for e in s.view_town()["buildings"]:
		on[e["lot_id"]] = e["output"]
	for uid in uids:
		s.cmd_place_big_undead(uid, "crypt")
	var off := {}
	for e in s.view_town()["buildings"]:
		off[e["lot_id"]] = e["output"]
	var ok := true
	var shown: Array = []
	for pair in [["lot-04", "gold"], ["lot-02", "mint"], ["lot-02", "burn"], ["lot-05", "bone"], ["lot-06", "forge"]]:
		var a := float(off[pair[0]].get(pair[1], 0.0))
		var b := float(on[pair[0]].get(pair[1], 0.0))
		ok = ok and a > 0.0 and _near(b, a * m)
		shown.append("%s %.3f -> %.3f" % [pair[1], a, b])
	t.ok(ok and on["lot-03"] == off["lot-03"], "view_town output × m at each working foreman's building: %s" % ", ".join(PackedStringArray(shown)))


## The stances' projection runs on the foremen too (TownSim.stance_flows): the gold flow up by (m − 1) × the stalls'
## income, the bone by (m − 1) × the mill's, the pits counted as pit_weight; and Thrift's condition reads the
## Market foreman's gold (trade_income × m).
func _fm_stance_flows() -> void:
	var s := _town()
	var m := _m()
	var c0 := s.town_sim.clone()
	c0.restaff()
	var c1 := s.town_sim.clone()
	c1.set_foremen({"lot-02": FM.duplicate(), "lot-04": FM.duplicate(), "lot-05": FM.duplicate()})
	c1.restaff()
	var r0 := c0.stance_flows([], false, {}, true, 0)
	var r1 := c1.stance_flows([], false, {}, true, 0)
	var inc := c0.trade_income()
	var bone := float(c0.lot_output("lot-05", 0.0, 0.0)["bone"])
	t.ok(_near(float(r1["gold"]) - float(r0["gold"]), (m - 1.0) * inc) and _near(float(r1["bone"]) - float(r0["bone"]), (m - 1.0) * bone)
		and float(r0["pits"]) == 1.0 and _near(float(r1["pits"]), c1.pit_weight()) and _near(float(r1["pits"]), m) and r1["feed"] == r0["feed"],
		"stance_flows: gold %+.4f, bone %+.4f, pits %.2f (pit_weight), feed unchanged" % [float(r1["gold"]) - float(r0["gold"]),
		float(r1["bone"]) - float(r0["bone"]), float(r1["pits"])])
	t.ok(inc > 0.0 and _near(c1.trade_income(), inc * m), "Thrift reads the stalls' income × m: %.4f -> %.4f /s" % [inc, c1.trade_income()])


## clone() carries the foremen (every projection runs on a clone); a place that ends a foreman's work reaches TownSim
## at once, with no step between: into the party, its building demolished, its first build cancelled.
func _fm_clone_sync() -> void:
	var s := _town()
	var m := _m()
	var uid: String = _foremen_at(s, ["lot-04"])[0]
	var pit: String = _foremen_at(s, ["lot-02"])[0]
	var c := s.town_sim.clone()
	t.ok(c.foremen == s.town_sim.foremen and _near(c.foreman_mult("lot-04"), m) and _near(c.pit_weight(), m),
		"clone() carries the foremen and the staffing they read: %s, pit_weight %.2f" % [str(c.foremen), c.pit_weight()])
	var feed := float(s.town_sim.rates.get("feed", 0.0))
	var pm := float(StateViews._proj_base(s)["rates"]["mint"])
	t.ok(_near(pm, s._mint(m, feed)) and pm > s._mint(1.0, feed), "the build card's baseline (a clone stepped once) mints on the Pit foreman's weight: %.3f" % pm)
	s.cmd_place_big_undead(pit, "crypt")
	s.cmd_set_party([uid])
	t.ok(s.town_sim.foremen.is_empty() and s.town_sim.foreman_mult("lot-04") == 1.0, "into the party: TownSim drops it at once")
	s.cmd_place_big_undead(uid, "town:lot-04")
	t.ok(s.town_sim.foremen.has("lot-04"), "(setup) placed again")
	t.ok(s.cmd_demolish("lot-04")["ok"] and s.town_sim.foremen.is_empty() and s.big_undead[0]["place"] == "crypt",
		"its building demolished: home to the crypt, and TownSim drops it at once")
	var d := _mk()
	d.cmd_debug_grant({"gold": 500.0, "bone": 200.0})
	t.ok(d.cmd_build("house", "lot-05")["ok"], "(setup) a House started on lot-05")
	var u2: String = _foremen_at(d, ["lot-05"])[0]
	t.ok(d.town_sim.foremen.has("lot-05") and d.town_sim.foreman_mult("lot-05") == 1.0, "a foreman on a construction: allowed, gives nothing")
	t.ok(d.cmd_cancel_build("lot-05")["ok"] and d.town_sim.foremen.is_empty() and d._find_uid(d.big_undead, u2)["place"] == "crypt",
		"its first build cancelled: home to the crypt, and TownSim drops it at once")


## The identity harness (the parent's PARENT came from this code on a snapshot): `fx` under `c` with `crypt` moved to
## the crypt, `seconds` live (tick uncapped). Returns [the state, its events].
func _live(c: Dictionary, fx: String, crypt: Array, seconds: float) -> Array:
	var s := GameState.new(c)
	s.debug_enabled = true
	s.cmd_debug_load_fixture(fx)
	for uid in crypt:
		s.cmd_place_big_undead(uid, "crypt")
	s.drain_events()
	s.tick(seconds)
	return [s, s.drain_events()]


static func _strip(d: Dictionary) -> Dictionary:
	d.erase("big_undead")
	d.erase("api_version")
	return d


static func _hash_live(r: Array) -> Dictionary:
	var s: GameState = r[0]
	return {"state": JSON.stringify(_strip(s.to_dict())).sha256_text().left(16), "events": JSON.stringify(r[1]).sha256_text().left(16),
		"n_events": (r[1] as Array).size()}


## `fx` under `c` with `crypt` moved to the crypt, saved at CLOCK and loaded `seconds` later (caught up). Returns the
## loaded state.
func _caught(c: Dictionary, fx: String, crypt: Array, seconds: int) -> GameState:
	var s := GameState.new(c)
	s.debug_enabled = true
	s.save_dir = _dir
	s.cmd_debug_load_fixture(fx)
	for uid in crypt:
		s.cmd_place_big_undead(uid, "crypt")
	s.clock_override = CLOCK
	s.cmd_save("ident")
	var n := GameState.new(c)
	n.debug_enabled = true
	n.save_dir = _dir
	n.clock_override = CLOCK + seconds
	n.cmd_load("ident")
	return n


static func _hash_caught(n: GameState) -> Dictionary:
	var evs: Array = n.catchup_events()
	var away := n.view_away()
	away.erase("rev")
	return {"state": JSON.stringify(_strip(n.to_dict())).sha256_text().left(16), "events": JSON.stringify(evs).sha256_text().left(16),
		"away": JSON.stringify(away).sha256_text().left(16), "n_events": evs.size(), "steps": n._catchup.steps}


## With no foreman working, 6 h live and 12 h caught up hash as the parent's (PARENT): day1, pre_vei, and midgame_2flips
## with u8 (the Market's foreman) back in the crypt. The midgame live run is kept for _fm_catchup (_mid_off).
func _identity() -> void:
	var c: Dictionary = load("res://tests/test_stances.gd").cfgs()
	for cs in [["day1", []], ["pre_vei", []], ["midgame_2flips", ["u8"]]]:
		var lv := _live(c, cs[0], cs[1], 21600.0)
		if cs[0] == "midgame_2flips":
			_mid_off = lv
		var hl := _hash_live(lv)
		var hc := _hash_caught(_caught(c, cs[0], cs[1], 43200))
		t.ok(hl == PARENT[cs[0]]["live"] and hc == PARENT[cs[0]]["caught"],
			"%s%s: 6 h live and 12 h caught up hash as the parent's (0e4f932): %s, %s" % [cs[0], " with %s in the crypt" % str(cs[1]) if not cs[1].is_empty() else "", str(hl), str(hc)])


## Caught up matches live with the foreman, midgame_2flips over 6 h at the shipped step, by test_catchup's compare(): the
## stocks within idle.catchup_tol, the held forts, Covington, the outcomes; the rates no further from live than with u8
## in the crypt (the same comparison), plus the tolerance.
func _fm_catchup() -> void:
	var c: Dictionary = load("res://tests/test_stances.gd").cfgs()
	var tol := float(c["economy"]["idle"]["catchup_tol"])
	var tc = load("res://tests/test_catchup.gd")
	var on := _live(c, "midgame_2flips", [], 21600.0)
	var cu_on := _caught(c, "midgame_2flips", [], 21600)
	var r: Dictionary = tc.compare(cu_on, cu_on.catchup_events(), on[0], on[1], tol)
	var cu_off := _caught(c, "midgame_2flips", ["u8"], 21600)
	var off: Dictionary = tc.compare(cu_off, cu_off.catchup_events(), _mid_off[0], _mid_off[1], tol)
	var worse: Array = []
	for k in r["rates"]:
		if float(r["rates"][k]) > float(off["rates"][k]) + tol:
			worse.append(k)
	var stocks_ok := (r["stocks"] as Dictionary).values().all(func(e): return float(e) <= tol)
	var live_gs: GameState = on[0]
	var m := live_gs.town_sim.foreman_mult("lot-04")
	t.ok(m > 1.0 and cu_on.town_sim.foreman_mult("lot-04") == m and stocks_ok and worse.is_empty() and r["town_same"]
		and (r["outcomes"] as Array).is_empty() and r["held"][0] == r["held"][1],
		"midgame_2flips, the Market's foreman at m %.4f, 6 h caught up against live at 0.5 s: %s (u8 in the crypt: %s)" % [m, r["lines"], off["lines"]])
