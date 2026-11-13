extends RefCounted
## Results.validate and Results.from_v1 (STATE-API §8.4, §8.5), and GameState.apply_result
## with the v2 writeback (§4.5, §8.3). Headless, no autoloads.

var t: TestUtil


func _mk(seed_val := 1) -> GameState:
	var s := GameState.new(TestUtil.configs())
	s.cmd_new_game(seed_val)
	s.debug_enabled = true
	return s


func _fort(s: GameState, id: String) -> Dictionary:
	return s.realm.fort_by_id(id)


func _set_fort(s: GameState, id: String, living: float, dead: float, undead: float) -> void:
	var f := _fort(s, id)
	f["living"] = living
	f["dead"] = dead
	f["undead"] = undead


## Relish at the fort, a dungeon run open; returns the seed.
func _begin(s: GameState, fid := "old-sluice") -> Dictionary:
	s.legacy_teleport_relish(fid)
	var r := s.cmd_begin_dungeon(fid)
	t.ok(r["ok"], "begin dungeon at %s" % fid)
	return r["seed"]


func _begin_boss(s: GameState) -> Dictionary:
	s.legacy_teleport_relish("vei")
	var r := s.cmd_begin_boss()
	t.ok(r["ok"], "begin boss")
	return r["seed"]


## A valid raid result for `sd`: a retreat that changes nothing. `over` replaces keys.
func _raid_res(sd: Dictionary, over := {}) -> Dictionary:
	var r := {
		"v": 2, "run_id": sd["run_id"], "seed_rev": sd["seed_rev"], "fort_id": sd["fort"]["id"],
		"warden_beaten": false, "retreated": true, "relish_died": false, "revived_in_place": 0,
		"killed_living_mass": 0.0, "raised": [], "chaff_mass": 0.0, "garrison_mass": sd["garrison_in_mass"],
		"party_lost": [],
		"loot": {"relics": 0, "blueprints": [], "husks": [], "remnants": [], "essence": 0},
	}
	r.merge(over, true)
	return r


func _boss_res(sd: Dictionary, over := {}) -> Dictionary:
	var r := {
		"v": 2, "run_id": sd["run_id"], "seed_rev": sd["seed_rev"], "won": true, "fronts_cleared": [],
		"relish_deaths": 0, "backups_spent": {"phylactery": 0, "clones": 0}, "party_lost": [],
		"backlog_spent": 0.0,
	}
	r.merge(over, true)
	return r


func _types(evs: Array) -> Array:
	return evs.map(func(e): return e["type"])


## Everything a refusal must leave alone.
func _snap(s: GameState) -> Dictionary:
	return {
		"rev": s.rev, "uid": s.next_uid, "rng": s.rng.state, "ev": s._events.duplicate(true),
		"applied": s.applied_runs.duplicate(), "run": s.run.duplicate(true),
		"forts": s.realm.forts.duplicate(true), "vei": s.realm.vei.duplicate(), "relics": s.relics,
		"essence": s.essence, "bps": s.blueprints.duplicate(), "bu": s.big_undead.duplicate(true),
		"party": s.party_uids.duplicate(), "army": s.army.duplicate(), "vats": s.town["vats"],
		"relish": s.relish.duplicate(true), "sink": s._dungeon_sink, "husks": s.husks.duplicate(true),
		"remnants": s.remnants.duplicate(true), "stats": s.stats.duplicate(), "won": s.won,
		"cleared": s.cleared_forts.duplicate(), "first": s.first_dungeon_id,
	}


func _refused(s: GameState, kind: String, r: Dictionary, reason: String, what: String) -> Dictionary:
	var before := _snap(s)
	var out := s.apply_result(kind, r)
	t.ok(not out["ok"] and out["reason"] == reason and out["minted"] == [], "%s -> %s (got %s)" % [what, reason, out["reason"]])
	t.ok(_snap(s) == before, "%s: nothing changed" % what)
	return out


func run() -> int:
	t = TestUtil.new()
	t.suite("results")
	_validate()
	_validate_seeds()
	_from_v1()
	_reasons()
	_raid_writeback()
	_raid_death()
	_boss_writeback()
	_mass_and_charges()
	_parity()
	_misc()
	return t.failures


# ------------------------------------------------------------------ validate ----
func _good_raid() -> Dictionary:
	return {"v": 2, "run_id": 1, "seed_rev": 512, "fort_id": "old-sluice", "warden_beaten": true,
		"retreated": false, "relish_died": false, "revived_in_place": 0, "killed_living_mass": 30.0,
		"raised": [{"score": 75, "count": 2, "mass": 8.0}, {"score": 40, "count": 5, "mass": 3.0}, {"score": 99, "count": 1, "mass": 2.0}],
		"chaff_mass": 4.0, "garrison_mass": 6.0, "party_lost": ["u4", "u5"],
		"loot": {"relics": 1, "blueprints": ["embalmer"], "husks": [{"kind": "hulk"}],
			"remnants": [{"aspect": "beef", "rarity": "common", "magnitude": 3}], "essence": 9}}


func _good_boss() -> Dictionary:
	return {"v": 2, "run_id": 9, "seed_rev": 21950, "won": true, "fronts_cleared": ["giants", "raw"],
		"relish_deaths": 1, "backups_spent": {"phylactery": 1, "clones": 0}, "party_lost": ["u4"],
		"backlog_spent": 900.0}


func _with(base: Dictionary, path: Array, value: Variant) -> Dictionary:
	var d: Dictionary = base.duplicate(true)
	var cur: Variant = d
	for i in path.size() - 1:
		cur = cur[path[i]]
	cur[path[path.size() - 1]] = value
	return d


func _without(base: Dictionary, path: Array) -> Dictionary:
	var d: Dictionary = base.duplicate(true)
	var cur: Variant = d
	for i in path.size() - 1:
		cur = cur[path[i]]
	cur.erase(path[path.size() - 1])
	return d


func _v(kind: String, d: Dictionary, want: Array, what: String) -> void:
	var got := Results.validate(kind, d)
	t.ok(got == want, "%s -> %s (got %s)" % [what, str(want), str(got)])


func _validate() -> void:
	t.suite("results-validate")
	_v("raid", _good_raid(), [], "a valid raid result")
	_v("boss", _good_boss(), [], "a valid boss result")
	_v("town", {"v": 2, "teleport_to": ""}, [], "a valid town result")
	_v("map", {"v": 2, "teleport_to": "vei"}, [], "a valid map result")
	# kinds and versions
	_v("nope", {"v": 2}, ["unknown_kind"], "unknown kind")
	_v("raid_result", {}, ["unknown_kind"], "unknown kind, empty dict")
	_v("raid", _without(_good_raid(), ["v"]), ["unknown_v"], "v missing")
	_v("raid", _with(_good_raid(), ["v"], 1), ["unknown_v"], "v = 1")
	_v("raid", _with(_good_raid(), ["v"], 3), ["unknown_v"], "v = 3")
	_v("raid", _with(_good_raid(), ["v"], "2"), ["unknown_v"], "v = \"2\"")
	_v("raid", _with(_good_raid(), ["v"], 2.0), [], "v = 2.0 (after JSON)")
	_v("raid", _with(_good_raid(), ["v"], 2.5), ["unknown_v"], "v = 2.5")
	_v("town", {"teleport_to": ""}, ["unknown_v"], "town without v")
	# integral floats
	var fl := _good_raid()
	fl["run_id"] = 1.0
	fl["seed_rev"] = 512.0
	fl["revived_in_place"] = 0.0
	fl["raised"][0]["count"] = 2.0
	fl["raised"][0]["score"] = 75.0
	fl["loot"]["relics"] = 1.0
	fl["loot"]["remnants"][0]["magnitude"] = 3.0
	_v("raid", fl, [], "integral floats are accepted for ints")
	_v("raid", _with(_good_raid(), ["run_id"], 1.5), ["type:run_id"], "a non-integral float is a type error")
	_v("raid", _with(_good_raid(), ["raised", 0, "count"], 2.5), ["type:raised[0].count"], "non-integral count")
	_v("raid", _with(_good_raid(), ["run_id"], INF), ["range:run_id"], "an infinite int field is a range error")
	_v("raid", _with(_good_raid(), ["chaff_mass"], 4), [], "an int is fine for a float field")
	_v("raid", _with(_good_raid(), ["run_id"], true), ["type:run_id"], "a bool is not an int")
	# missing, type
	_v("raid", _without(_good_raid(), ["fort_id"]), ["missing:fort_id"], "missing fort_id")
	_v("raid", _without(_good_raid(), ["loot"]), ["missing:loot"], "missing loot is one code")
	_v("raid", _without(_good_raid(), ["loot", "relics"]), ["missing:loot.relics"], "missing loot.relics")
	_v("raid", _without(_good_raid(), ["raised", 1, "score"]), ["missing:raised[1].score"], "missing raised[1].score")
	_v("raid", _without(_without(_good_raid(), ["chaff_mass"]), ["garrison_mass"]), ["missing:chaff_mass", "missing:garrison_mass"], "two missing, in schema order")
	_v("raid", _with(_good_raid(), ["raised", 2, "score"], "x"), ["type:raised[2].score"], "a String score")
	_v("raid", _with(_good_raid(), ["fort_id"], 5), ["type:fort_id"], "a non-String fort_id")
	_v("raid", _with(_good_raid(), ["raised"], {}), ["type:raised"], "raised not an Array")
	_v("raid", _with(_good_raid(), ["loot"], []), ["type:loot"], "loot not a Dictionary")
	_v("raid", _with(_good_raid(), ["loot", "husks", 0], 3), ["type:loot.husks[0]"], "a husk that is not a Dictionary")
	_v("raid", _with(_good_raid(), ["party_lost", 0], 4), ["type:party_lost[0]"], "a non-String uid")
	_v("raid", _with(_good_raid(), ["warden_beaten"], 1), ["type:warden_beaten"], "an int exit flag")
	# range
	_v("raid", _with(_good_raid(), ["chaff_mass"], -1.0), ["range:chaff_mass"], "negative mass")
	_v("raid", _with(_good_raid(), ["raised", 0, "score"], 101), ["range:raised[0].score"], "score 101")
	_v("raid", _with(_good_raid(), ["raised", 0, "score"], -1), ["range:raised[0].score"], "score -1")
	_v("raid", _with(_good_raid(), ["raised", 0, "score"], 100), [], "score 100 is fine")
	_v("raid", _with(_good_raid(), ["loot", "remnants", 0, "aspect"], "luck"), ["range:loot.remnants[0].aspect"], "unknown aspect")
	_v("raid", _with(_good_raid(), ["loot", "remnants", 0, "rarity"], "mythic"), ["range:loot.remnants[0].rarity"], "unknown rarity")
	_v("raid", _with(_good_raid(), ["loot", "relics"], -1), ["range:loot.relics"], "negative relics")
	_v("raid", _with(_good_raid(), ["loot", "essence"], -3), ["range:loot.essence"], "negative essence")
	_v("raid", _with(_good_raid(), ["revived_in_place"], -1), ["range:revived_in_place"], "negative revives")
	_v("raid", _with(_good_raid(), ["killed_living_mass"], NAN), ["range:killed_living_mass"], "NaN mass")
	_v("raid", _with(_good_raid(), ["garrison_mass"], INF), ["range:garrison_mass"], "infinite mass")
	_v("raid", _with(_good_raid(), ["raised", 0, "mass"], -0.5), ["range:raised[0].mass"], "negative raised mass")
	# duplicates and the exit
	_v("raid", _with(_good_raid(), ["party_lost"], ["u4", "u5", "u4"]), ["duplicate:party_lost[2]"], "a repeated uid in party_lost")
	_v("raid", _with(_good_raid(), ["warden_beaten"], false), ["bad_exit"], "no exit set (zero)")
	_v("raid", _with(_good_raid(), ["retreated"], true), ["bad_exit"], "two exits")
	var three := _with(_with(_good_raid(), ["retreated"], true), ["relish_died"], true)
	_v("raid", three, ["bad_exit"], "three exits")
	_v("raid", _with(_good_raid(), ["relish_died"], true), ["bad_exit"], "warden_beaten and relish_died")
	var died := _with(_with(_good_raid(), ["warden_beaten"], false), ["relish_died"], true)
	_v("raid", died, [], "relish_died alone is one exit")
	_v("raid", _with(_with(_good_raid(), ["warden_beaten"], false), ["retreated"], true), [], "retreated alone is one exit")
	# extra keys are ignored
	_v("raid", _with(_good_raid(), ["aborted"], true), [], "an unknown extra key is ignored")
	_v("raid", _with(_good_raid(), ["loot", "gems"], 4), [], "an unknown nested key is ignored")
	_v("boss", _with(_good_boss(), ["note"], "x"), [], "an unknown extra key on a boss result")
	# boss
	_v("boss", _without(_good_boss(), ["backups_spent", "clones"]), ["missing:backups_spent.clones"], "missing clones")
	_v("boss", _with(_good_boss(), ["won"], 1), ["type:won"], "won not a bool")
	_v("boss", _with(_good_boss(), ["fronts_cleared"], ["giants", "nope"]), ["range:fronts_cleared[1]"], "an unknown front id")
	_v("boss", _with(_good_boss(), ["fronts_cleared"], ["giants", "raw", "giants"]), ["duplicate:fronts_cleared[2]"], "a repeated front")
	_v("boss", _with(_good_boss(), ["party_lost"], ["u1", "u1"]), ["duplicate:party_lost[1]"], "a repeated uid on a boss result")
	_v("boss", _with(_good_boss(), ["relish_deaths"], -1), ["range:relish_deaths"], "negative deaths")
	_v("boss", _with(_good_boss(), ["backups_spent", "phylactery"], -1), ["range:backups_spent.phylactery"], "negative backups")
	_v("boss", _with(_good_boss(), ["backlog_spent"], -1.0), ["range:backlog_spent"], "negative backlog_spent")
	# bad_deaths: won => deaths == s; lost => deaths in {s, s+1}
	_v("boss", _with(_good_boss(), ["relish_deaths"], 0), ["bad_deaths"], "won with deaths < s")
	_v("boss", _with(_good_boss(), ["relish_deaths"], 2), ["bad_deaths"], "won with deaths = s + 1")
	var lost := _with(_good_boss(), ["won"], false)
	_v("boss", lost, [], "lost with deaths = s")
	_v("boss", _with(lost, ["relish_deaths"], 2), [], "lost with deaths = s + 1 (a final death)")
	_v("boss", _with(lost, ["relish_deaths"], 3), ["bad_deaths"], "lost with deaths = s + 2")
	_v("boss", _with(lost, ["relish_deaths"], 0), ["bad_deaths"], "lost with deaths < s")
	var none := _with(_with(_good_boss(), ["backups_spent"], {"phylactery": 0, "clones": 0}), ["relish_deaths"], 0)
	_v("boss", none, [], "won, no deaths, no backups")
	_v("boss", _with(_with(none, ["won"], false), ["relish_deaths"], 1), [], "lost, one final death, no backups")
	_v("boss", _with(_with(none, ["won"], "x"), ["relish_deaths"], 5), ["type:won"], "a mistyped won hides bad_deaths")
	# town and map
	_v("town", {"v": 2}, ["missing:teleport_to"], "town without teleport_to")
	_v("map", {"v": 2, "teleport_to": 4}, ["type:teleport_to"], "map teleport_to not a String")
	_v("town", {"v": 2, "teleport_to": "nowhere", "spend": {}}, [], "an unknown node id is the router's business")


func _validate_seeds() -> void:
	t.suite("results-seeds")
	var s := _mk()
	var rs := _begin(s)
	_v("raid_seed", rs, [], "the raid seed cmd_begin_dungeon issues")
	_v("raid_seed", _with(rs, ["kind"], "boss"), ["range:kind"], "a raid seed claiming to be a boss seed")
	_v("raid_seed", _without(rs, ["garrison_mass_div"]), ["missing:garrison_mass_div"], "garrison_mass_div is required")
	_v("raid_seed", _without(rs, ["fort", "tier"]), ["missing:fort.tier"], "a missing nested seed key")
	_v("raid_seed", _with(rs, ["living"], "x"), ["type:living"], "a mistyped seed value")
	_v("raid_seed", _with(rs, ["v"], 1), ["unknown_v"], "a v1 seed")
	_v("raid_seed", _with(rs, ["extra"], 1), [], "extra seed keys are ignored")
	_v("raid_seed", _with(rs, ["garrison_units"], 2.0), [], "an integral float for a seed int")
	t.ok(rs["garrison_mass_div"] == 10.0 and rs["garrison_mass_div"] is float, "the raid seed carries garrison_mass_div (10.0)")
	s.cmd_abort_dungeon()
	s.cmd_debug_grant({"big_undead": 2})
	var u: Array = s.view_big_undead()["big_undead"]
	s.cmd_set_party([u[0]["uid"], u[1]["uid"]])
	s.cmd_assign_front(u[0]["uid"], "giants")
	var rp := _begin(s)
	_v("raid_seed", rp, [], "a raid seed with a party")
	_v("raid_seed", _with(rp, ["party", 0, "stats", "power"], "x"), ["type:party[0].stats.power"], "a mistyped party stat")
	s.cmd_abort_dungeon()
	var bs := _begin_boss(s)
	_v("boss_seed", bs, [], "the boss seed cmd_begin_boss issues")
	var as_boss := Results.validate("boss_seed", rs)
	t.ok(as_boss.has("range:kind") and as_boss.has("missing:backlog"), "a raid seed is not a boss seed: %s" % str(as_boss))
	_v("boss_seed", _without(bs, ["fronts_required"]), ["missing:fronts_required"], "a missing boss seed key")
	_v("boss_seed", _with(bs, ["fronts", 0, "assigned"], "x"), ["type:fronts[0].assigned"], "a mistyped fronts entry")
	_v("boss_seed", _with(bs, ["drain_s"], -1.0), [], "drain_s -1.0 is the holding sentinel")
	_v("boss_seed", _with(bs, ["sign"], -1), [], "sign -1 is legal")
	_v("boss_seed", _with(bs, ["odds"], INF), ["range:odds"], "a non-finite seed float")
	_v("boss_seed", _with(bs, ["kind"], "raid"), ["range:kind"], "a boss seed claiming to be a raid seed")


# ------------------------------------------------------------------- from_v1 ----
func _from_v1() -> void:
	t.suite("results-from-v1")
	var s := _mk()
	var sd := _begin(s)
	var cfg := TestUtil.load_json("res://configs/raid.json")
	# a v1 result as RaidLogic.Ledger produces it
	var lg := RaidLogic.Ledger.new(20.0, 160.0)
	lg.on_kill(30.0)
	lg.on_raise(40, 21.0, 7, cfg)
	lg.on_raise(75, 10.0, 7, cfg)
	lg.on_raise(95, 30.0, 9, cfg)
	var v1 := lg.result("old-sluice", false, cfg)
	var v2 := Results.from_v1("raid", v1, sd)
	t.ok(Results.validate("raid", v2) == [], "a RaidLogic result converts to a valid v2 result: %s" % str(Results.validate("raid", v2)))
	t.ok(v2["v"] == 2 and v2["run_id"] == sd["run_id"] and v2["seed_rev"] == sd["seed_rev"], "run_id and seed_rev come from the seed")
	t.ok(v2["fort_id"] == "old-sluice" and v2["killed_living_mass"] == v1["killed_living_mass"], "fort and kills carry over")
	t.ok(v2["warden_beaten"] == false and v2["retreated"] == true and v2["relish_died"] == false, "a clean v1 exit is a retreat")
	t.ok(v2["revived_in_place"] == 0 and v2["party_lost"] == [] and v2["loot"] == {"relics": 0, "blueprints": [], "husks": [], "remnants": [], "essence": 0},
		"no revives, no party, zero loot")
	t.near(v2["chaff_mass"], v1["raised_chaff_mass"], 1e-9, "chaff_mass is raised_chaff_mass")
	t.near(v2["garrison_mass"], sd["garrison_in_mass"] + v1["garrison_mass"] + v1["good_mass"], 1e-9,
		"garrison_mass = garrison_in_mass + garrison + good")
	var buckets: Dictionary = {}
	for b in v2["raised"]:
		buckets[b["score"]] = b
	t.ok(v2["raised"].size() == 3 and buckets.has(75) and buckets.has(95) and buckets.has(50), "soldier, elite and chaff buckets at 75, 95, 50")
	t.ok(buckets[75]["count"] == v1["raised_soldiers"] and buckets[95]["count"] == v1["raised_elites"], "bucket counts are the v1 counts")
	t.near(buckets[75]["mass"] + buckets[95]["mass"], v1["good_mass"], 1e-9, "good_mass is split between the two")
	t.near(buckets[75]["mass"], v1["good_mass"] * v1["raised_soldiers"] / float(v1["raised_soldiers"] + v1["raised_elites"]), 1e-9, "split by count share")
	t.near(buckets[50]["mass"], v1["raised_chaff_mass"] + v1["garrison_mass"], 1e-9, "chaff bucket mass = chaff + garrison")
	t.ok(buckets[50]["count"] == roundi((v1["raised_chaff_mass"] + v1["garrison_mass"]) / 10.0), "chaff bucket count = round(mass / div)")
	# explicit numbers
	var h := {"fort_id": "old-sluice", "killed_living_mass": 5.0, "raised_chaff_mass": 18.0, "raised_soldiers": 3,
		"raised_elites": 1, "good_mass": 8.0, "garrison_mass": 12.0, "relish_died": true, "aborted": false}
	var x := Results.from_v1("raid", h, sd)
	t.ok(x["raised"] == [{"score": 75, "count": 3, "mass": 6.0}, {"score": 95, "count": 1, "mass": 2.0}, {"score": 50, "count": 3, "mass": 30.0}],
		"exact buckets: %s" % str(x["raised"]))
	t.ok(x["relish_died"] == true and x["retreated"] == false and x["warden_beaten"] == false, "died: relish_died, not retreated")
	t.ok(x["garrison_mass"] == sd["garrison_in_mass"] + 20.0 and x["chaff_mass"] == 18.0, "garrison_mass and chaff_mass")
	t.ok(Results.validate("raid", x) == [], "valid")
	# the seed's divisor is used, defaulting to 10
	var sd5 := sd.duplicate(true)
	sd5["garrison_mass_div"] = 5.0
	t.ok(Results.from_v1("raid", h, sd5)["raised"][2]["count"] == 6, "the divisor comes from the seed")
	sd5.erase("garrison_mass_div")
	t.ok(Results.from_v1("raid", h, sd5)["raised"][2]["count"] == 3, "no divisor in the seed: 10")
	# omission and the s + e == 0 rule
	x = Results.from_v1("raid", {"fort_id": "old-sluice", "relish_died": false}, sd)
	t.ok(x["raised"] == [] and x["chaff_mass"] == 0.0 and x["garrison_mass"] == sd["garrison_in_mass"], "an empty v1 result: no buckets")
	x = Results.from_v1("raid", {"fort_id": "old-sluice", "good_mass": 7.0}, sd)
	t.ok(x["raised"] == [{"score": 75, "count": 0, "mass": 7.0}], "good_mass with no counts: all in the soldier bucket, count 0")
	x = Results.from_v1("raid", {"fort_id": "old-sluice", "raised_soldiers": 2, "good_mass": 0.0}, sd)
	t.ok(x["raised"] == [{"score": 75, "count": 2, "mass": 0.0}], "a bucket with a count but no mass stays")
	x = Results.from_v1("raid", {"fort_id": "old-sluice", "raised_elites": 2, "good_mass": 4.0}, sd)
	t.ok(x["raised"] == [{"score": 95, "count": 2, "mass": 4.0}], "elites only: the soldier bucket is omitted")
	x = Results.from_v1("raid", {"fort_id": "old-sluice", "raised_chaff_mass": 4.0}, sd)
	t.ok(x["raised"] == [{"score": 50, "count": 0, "mass": 4.0}], "chaff mass under half a unit: count 0, mass kept")
	# today's Shot --finish-raid result
	var shot := {"fort_id": "old-sluice", "killed_living_mass": 42.0, "raised_chaff_mass": 26.0, "raised_soldiers": 3,
		"raised_elites": 1, "good_mass": 9.0, "garrison_mass": 12.0, "relish_died": false, "aborted": false}
	t.ok(Results.validate("raid", Results.from_v1("raid", shot, sd)) == [], "the --finish-raid result converts to a valid v2 result")
	# boss
	s.cmd_abort_dungeon()
	var bsd := _begin_boss(s)
	var bwin := Results.from_v1("boss", {"fort_id": "vei", "won": true, "relish_died": true, "backlog_spent": 300.0, "army_lost": {"soldier": 2}}, bsd)
	t.ok(bwin == {"v": 2, "run_id": bsd["run_id"], "seed_rev": bsd["seed_rev"], "won": true, "fronts_cleared": [],
		"relish_deaths": 0, "backups_spent": {"phylactery": 0, "clones": 0}, "party_lost": [], "backlog_spent": 300.0},
		"a v1 win: no deaths (a win never reports one)")
	t.ok(Results.validate("boss", bwin) == [], "valid")
	var bloss := Results.from_v1("boss", {"fort_id": "vei", "won": false, "relish_died": true, "backlog_spent": 120.0}, bsd)
	t.ok(bloss["won"] == false and bloss["relish_deaths"] == 1 and bloss["backlog_spent"] == 120.0, "a v1 loss with a death: relish_deaths 1")
	t.ok(Results.validate("boss", bloss) == [], "valid (a final death, nothing spent)")
	t.ok(Results.from_v1("boss", {"won": false, "relish_died": false}, bsd)["relish_deaths"] == 0, "a loss without a death: 0")
	t.ok(Results.from_v1("town", {}, bsd) == {} and Results.from_v1("nope", {}, bsd) == {}, "other kinds convert to {}")


# --------------------------------------------------------- apply_result reasons ----
func _reasons() -> void:
	t.suite("results-reasons")
	var s := _mk()
	var sd := _begin(s)
	_refused(s, "town", _raid_res(sd), "unknown_kind", "kind town")
	_refused(s, "", _raid_res(sd), "unknown_kind", "empty kind")
	_refused(s, "raid_seed", {}, "unknown_kind", "a seed kind")
	_refused(s, "raid", _with(_raid_res(sd), ["v"], 1), "unknown_v", "v = 1")
	_refused(s, "raid", _without(_raid_res(sd), ["v"]), "unknown_v", "no v")
	_refused(s, "raid", _with(_with(_raid_res(sd), ["v"], 1), ["run_id"], "x"), "unknown_v", "unknown_v before invalid")
	var out := _refused(s, "raid", _with(_raid_res(sd), ["chaff_mass"], -1.0), "invalid", "a negative mass")
	t.ok(out["errors"] == ["range:chaff_mass"], "invalid carries the validate errors: %s" % str(out["errors"]))
	_refused(s, "raid", _with(_with(_raid_res(sd), ["chaff_mass"], -1.0), ["run_id"], 99), "invalid", "invalid before wrong_run")
	_refused(s, "raid", _with(_with(_raid_res(sd), ["warden_beaten"], true), ["retreated"], true), "invalid", "bad_exit is invalid")
	_refused(s, "boss", _boss_res(sd, {"relish_deaths": 3}), "invalid", "bad_deaths is invalid")
	# wrong_run before wrong_kind; wrong_kind before stale_seed
	_refused(s, "raid", _with(_raid_res(sd), ["run_id"], 99), "wrong_run", "another run id")
	_refused(s, "boss", _boss_res(sd, {"run_id": 99}), "wrong_run", "wrong_run before wrong_kind")
	_refused(s, "boss", _boss_res(sd), "wrong_kind", "a boss result for the open raid")
	_refused(s, "boss", _boss_res(sd, {"seed_rev": 1}), "wrong_kind", "wrong_kind before stale_seed")
	_refused(s, "raid", _with(_with(_raid_res(sd), ["seed_rev"], 1), ["fort_id"], "ashgate"), "stale_seed", "stale_seed before wrong_fort")
	_refused(s, "raid", _with(_with(_raid_res(sd), ["fort_id"], "ashgate"), ["revived_in_place"], 1), "wrong_fort", "wrong_fort before bad_revives")
	_refused(s, "raid", _with(_with(_raid_res(sd), ["revived_in_place"], 1), ["party_lost"], ["u99"]), "bad_revives", "bad_revives before bad_party")
	_refused(s, "raid", _with(_raid_res(sd), ["revived_in_place"], 1), "bad_revives", "a revive with no charges (seed charges 0)")
	_refused(s, "raid", _with(_raid_res(sd), ["party_lost"], ["u99"]), "bad_party", "a uid outside the seed's party")
	# a revive within min(charges, max_per_dungeon) is allowed by the check, but the seed holds 0 at E1
	var sd2 := sd.duplicate(true)
	s.run["seed"]["phylactery_charges"] = 3
	s.run["seed"]["phylactery_max_per_dungeon"] = 2
	_refused(s, "raid", _with(_raid_res(sd2), ["revived_in_place"], 3), "bad_revives", "3 revives > min(3, 2)")
	s.run["seed"]["phylactery_charges"] = 0
	s.run["seed"]["phylactery_max_per_dungeon"] = 1
	# a forfeited run is wrong_run
	var aborted_id: int = sd["run_id"]
	s.cmd_abort_dungeon()
	_refused(s, "raid", _raid_res(sd), "wrong_run", "the forfeited run")
	t.ok(not s.applied_runs.has(aborted_id), "a forfeited run is not an applied run")
	# boss reasons
	s.cmd_debug_grant({"big_undead": 1})
	var bsd := _begin_boss(s)
	_refused(s, "raid", _raid_res(sd, {"run_id": bsd["run_id"], "seed_rev": bsd["seed_rev"]}), "wrong_kind", "a raid result for the open boss run")
	_refused(s, "boss", _boss_res(bsd, {"seed_rev": bsd["seed_rev"] - 1}), "stale_seed", "stale boss seed_rev")
	_refused(s, "boss", _boss_res(bsd, {"party_lost": ["u99"]}), "bad_party", "boss bad_party")
	_refused(s, "boss", _boss_res(bsd, {"relish_deaths": 1, "backups_spent": {"phylactery": 1, "clones": 0}}), "bad_backups", "a phylactery with no charges")
	_refused(s, "boss", _boss_res(bsd, {"relish_deaths": 1, "backups_spent": {"phylactery": 0, "clones": 1}}), "bad_backups", "a clone with none ready")
	s.cmd_abort_dungeon()
	s.town["vats"] = 1
	bsd = _begin_boss(s)
	t.ok(bsd["clones_ready"] == 1, "a legacy vat is a ready clone in the seed")
	_refused(s, "boss", _boss_res(bsd, {"relish_deaths": 2, "backups_spent": {"phylactery": 0, "clones": 2}}), "bad_backups", "more clones than ready")
	var ok := s.apply_result("boss", _boss_res(bsd, {"relish_deaths": 1, "backups_spent": {"phylactery": 0, "clones": 1}}))
	t.ok(ok["ok"] and s.town["vats"] == 0, "one clone spent: ok, the legacy vat is used up")


# ------------------------------------------------------------ raid writeback ----
func _raid_writeback() -> void:
	t.suite("results-raid")
	# idempotency, success shape, rev
	var s := _mk()
	_set_fort(s, "old-sluice", 60.0, 30.0, 25.0)
	var sd := _begin(s)
	t.ok(sd["garrison_in_mass"] == 20.0, "the seed takes in two garrison units (20 mass)")
	var rv := s.rev
	var r := _raid_res(sd, {"killed_living_mass": 20.0, "garrison_mass": 20.0})
	var out := s.apply_result("raid", r)
	t.ok(out == {"ok": true, "reason": "", "errors": [], "minted": []}, "success: %s" % str(out))
	t.ok(s.rev == rv + 1, "a success bumps rev once")
	t.ok(s.run.is_empty() and s.applied_runs == [sd["run_id"]], "the run closes and is recorded")
	t.ok(s.view_relish()["state"] == "at_fort" and s.view_relish()["at"] == "old-sluice", "Relish is at the fort again")
	t.ok(s.realm.raiding == false, "the realm no longer sees a raid")
	var before := _snap(s)
	var again := s.apply_result("raid", r)
	t.ok(again == {"ok": false, "reason": "duplicate_run", "errors": [], "minted": []} and _snap(s) == before, "a repeat is duplicate_run and changes nothing")
	_refused(s, "raid", _with(r, ["chaff_mass"], -1.0), "invalid", "invalid still beats duplicate_run")
	t.ok(s.apply_result("boss", _boss_res(sd))["reason"] == "duplicate_run", "duplicate_run is checked before wrong_kind")

	# the stale seed: rev keeps moving during the run, only the recorded seed_rev counts
	s = _mk()
	sd = _begin(s)
	s.tick(30.0)
	t.ok(s.rev > sd["seed_rev"], "rev moved during the run")
	out = s.apply_result("raid", _raid_res(sd))
	t.ok(out["ok"], "the recorded seed_rev is accepted although rev moved on")
	sd = _begin(s)
	s.tick(5.0)
	_refused(s, "raid", _raid_res(sd, {"seed_rev": s.rev}), "stale_seed", "the current rev is not the seed_rev")
	_refused(s, "raid", _raid_res(sd, {"seed_rev": sd["seed_rev"] + 1}), "stale_seed", "a later rev is stale too")
	out = s.apply_result("raid", _raid_res(sd, {"run_id": float(sd["run_id"]), "seed_rev": float(sd["seed_rev"])}))
	t.ok(out["ok"], "integral floats for run_id and seed_rev are converted")

	# clamped deltas against the live fort (the sim kept running)
	s = _mk()
	_set_fort(s, "old-sluice", 60.0, 30.0, 25.0)
	sd = _begin(s)
	s.tick(60.0)
	_set_fort(s, "old-sluice", 5.0, 10.0, 25.0)  # the live fort is not the seed's any more
	var q0: float = s.realm.vei["undead_queue"]
	out = s.apply_result("raid", _raid_res(sd, {"killed_living_mass": 50.0, "chaff_mass": 8.0, "garrison_mass": 20.0,
		"raised": [{"score": 40, "count": 2, "mass": 40.0}]}))
	var f := _fort(s, "old-sluice")
	t.ok(out["ok"], "applied against the live fort")
	# k = min(50, 5) = 5 -> dead 15; R' = min(40, 15) = 15 -> dead 0; bound: 28 > 20 + 15? no
	t.near(f["living"], 0.0, 1e-9, "kills are clamped at the live living mass")
	t.near(f["dead"], 0.0, 1e-9, "raised mass is clamped at the live dead mass")
	t.near(s.realm.vei["undead_queue"] - q0, 8.0, 1e-9, "chaff goes to Vei's queue")
	t.near(s._dungeon_sink, 15.0 + 20.0 - 20.0 - 8.0, 1e-9, "sink = in + R' - out")
	t.near(s.ledger()["sinks"]["dungeon"], 7.0, 1e-9, "ledger().sinks.dungeon shows it")
	# step 4: the bound
	s = _mk()
	_set_fort(s, "old-sluice", 60.0, 30.0, 25.0)
	sd = _begin(s)
	q0 = s.realm.vei["undead_queue"]
	s.apply_result("raid", _raid_res(sd, {"chaff_mass": 40.0, "garrison_mass": 40.0, "raised": [{"score": 40, "count": 2, "mass": 10.0}]}))
	# out 80 > in 20 + R' 10 = 30: both scaled by 30/80
	t.near(s.realm.vei["undead_queue"] - q0, 15.0, 1e-9, "step 4: chaff scaled to fit")
	t.near(_fort(s, "old-sluice")["undead"], 25.0 + 15.0 - 20.0, 1e-9, "step 4: garrison scaled; the net delta is applied")
	t.near(s._dungeon_sink, 0.0, 1e-9, "everything that fit is accounted for: no sink")
	# step 5: the undead clamp at the live fort
	s = _mk()
	_set_fort(s, "old-sluice", 60.0, 30.0, 25.0)
	sd = _begin(s)
	_set_fort(s, "old-sluice", 60.0, 30.0, 4.0)  # the fort lost its undead meanwhile
	s.apply_result("raid", _raid_res(sd, {"garrison_mass": 0.0}))
	t.near(_fort(s, "old-sluice")["undead"], 0.0, 1e-9, "step 5: undead never goes negative")
	t.near(s._dungeon_sink, 4.0, 1e-9, "the 4 undead that were left are what the dungeon ate (net of the clamp, never negative)")
	# a loss of garrison goes to the sink
	s = _mk()
	_set_fort(s, "old-sluice", 60.0, 30.0, 25.0)
	sd = _begin(s)
	s.apply_result("raid", _raid_res(sd, {"garrison_mass": 5.0}))
	t.near(_fort(s, "old-sluice")["undead"], 10.0, 1e-9, "garrison that fell: undead 25 - 20 + 5")
	t.near(s._dungeon_sink, 15.0, 1e-9, "and the 15 that fell are the dungeon sink")

	# the flip, loot, caps, uids
	s = _mk()
	s.cmd_debug_grant({"relics": 11, "essence": 55, "husks": 1, "remnants": 1, "big_undead": 2})
	s.drain_events()
	var bus: Array = s.view_big_undead()["big_undead"]
	var u1: String = bus[0]["uid"]
	var u2: String = bus[1]["uid"]
	s.cmd_set_party([u1, u2])
	s.blueprints.append("embalmer")
	_set_fort(s, "old-sluice", 60.0, 30.0, 25.0)
	sd = _begin(s)
	var loot := {"relics": 5, "essence": 30, "blueprints": ["embalmer", "reliquary", "reliquary"],
		"husks": [{"kind": "hulk"}, {"kind": "wraith"}],
		"remnants": [{"aspect": "beef", "rarity": "rare", "magnitude": 4}]}
	s.tick(2.0)
	_set_fort(s, "old-sluice", 60.0, 30.0, 25.0)
	s.drain_events()
	var tnow := s.t
	out = s.apply_result("raid", _raid_res(sd, {"warden_beaten": true, "retreated": false, "killed_living_mass": 20.0,
		"raised": [{"score": 80, "count": 3, "mass": 6.0}, {"score": 95, "count": 1, "mass": 2.0}, {"score": 30, "count": 4, "mass": 4.0}],
		"chaff_mass": 3.0, "garrison_mass": 25.0, "party_lost": [u1], "loot": loot}))
	t.ok(out["ok"] and out["minted"].size() == 3 and out["errors"] == [], "success with three minted items: %s" % str(out))
	var evs := s.drain_events()
	t.ok(_types(evs) == ["loot_banked", "fort_flipped"], "events: loot_banked, then fort_flipped (%s)" % str(_types(evs)))
	t.ok(evs[0]["t"] == tnow and evs[1]["t"] == tnow, "events carry t")
	t.ok(evs[0] == {"type": "loot_banked", "t": tnow, "run_id": sd["run_id"], "fort_id": "old-sluice", "relics": 1, "essence": 5,
		"blueprints": ["reliquary"], "minted": out["minted"]}, "loot_banked: banked amounts after the caps, new blueprints only: %s" % str(evs[0]))
	t.ok(evs[1] == {"type": "fort_flipped", "t": tnow, "fort_id": "old-sluice", "run_id": sd["run_id"], "hold_s": 375.0},
		"fort_flipped: hold_s = 300 x (1 + 0.25 x tier 1) = 375: %s" % str(evs[1]))
	t.ok(s.relics == 12 and s.essence == 60, "relics and essence are capped (12, 60)")
	t.ok(s.blueprints == ["embalmer", "reliquary"], "blueprints join the set once")
	f = _fort(s, "old-sluice")
	t.ok(f["living"] == 0.0 and f["held_s"] == 375.0 and f["flipped_count"] == 1 and f["clears_since_retaken"] == 1,
		"warden beaten: all living dead, hold and counts recorded")
	var fv := s.view_fort("old-sluice")
	t.ok(fv["flipped_count"] == 1 and fv["clears_since_retaken"] == 1 and fv["first_clear"] == false and fv["first_dungeon"] == false,
		"view_fort shows the flip counts and the cleared first flags")
	t.ok(s.first_dungeon_id == "" and s.cleared_forts.has("old-sluice"), "first_clear and first_dungeon are spent")
	# 60 living -> k 20 -> living 40 -> flipped: dead = 30 + 20 + 40 = 90; R = 12 <= 90
	t.near(f["dead"], 90.0 - 12.0, 1e-9, "dead: kills, the flip, then the raised mass comes off")
	t.ok(s.army == {"soldier": 3, "elite": 1}, "step 12: score 60-89 -> soldiers, >= 90 -> elites, by count")
	var uids: Array = out["minted"]
	var seen := {}
	for h in s.husks:
		seen[h["uid"]] = true
	for r2 in s.remnants:
		seen[r2["uid"]] = true
	for u in s.big_undead:
		seen[u["uid"]] = true
	t.ok(uids[0].begins_with("h") and uids[1].begins_with("h") and uids[2].begins_with("r"), "husks first, then remnants: %s" % str(uids))
	t.ok(seen.size() == 3 + 2 + 1, "every uid is unique across husks, remnants and big undead")
	var inv := s.view_inventory()
	var inv_h: Array = inv["husks"].filter(func(h): return uids.has(h["uid"]))
	var inv_r: Array = inv["remnants"].filter(func(h): return uids.has(h["uid"]))
	t.ok(inv_h.size() == 2 and inv_h[0]["kind"] == "hulk" and inv_h[1]["kind"] == "wraith" and inv_r.size() == 1
		and inv_r[0]["aspect"] == "beef" and inv_r[0]["rarity"] == "rare" and inv_r[0]["magnitude"] == 4, "the looted items are in the inventory")
	t.ok(s.party_uids == [u2] and s.view_big_undead()["big_undead"].size() == 1 and s.view_party()["party"].size() == 1,
		"party_lost: gone from big undead and from the party list (no stale uid)")
	t.ok(s.view_relish()["state"] == "at_fort" and s.run.is_empty(), "Relish at the fort, run closed")
	# a second clear: the flip counts accumulate and first flags stay spent
	sd = _begin(s)
	t.ok(sd["fort"]["clears_since_retaken"] == 1 and sd["fort"]["first_clear"] == false and sd["fort"]["first_dungeon"] == false,
		"the next seed shows the live counts")
	s.apply_result("raid", _raid_res(sd, {"warden_beaten": true, "retreated": false}))
	t.ok(_fort(s, "old-sluice")["flipped_count"] == 2 and _fort(s, "old-sluice")["clears_since_retaken"] == 2, "a second flip counts")
	# a higher tier holds longer
	s = _mk()
	sd = _begin(s, "vespers")
	s.apply_result("raid", _raid_res(sd, {"warden_beaten": true, "retreated": false}))
	var fe := s.drain_events()
	t.near(fe[1]["hold_s"], 300.0 * 1.5, 1e-9, "tier 2 holds 450 s")
	t.ok(_types(fe) == ["loot_banked", "fort_flipped"], "an empty loot still emits loot_banked first")
	# the first clear: a retreat spends first_clear too
	s = _mk()
	sd = _begin(s, "ashgate")
	t.ok(sd["fort"]["first_clear"] == true, "ashgate was never cleared")
	s.apply_result("raid", _raid_res(sd))
	t.ok(s.view_fort("ashgate")["first_clear"] == false and s.first_dungeon_id == "", "any raid result clears first_clear and first_dungeon")
	t.ok(s.view_fort("ashgate")["flipped_count"] == 0, "a retreat does not flip")
	# the flip hold comes from realm.json
	s = _mk()
	s._cfgs["realm"]["flip"] = {"hold_s": 100.0, "tier_mult": 1.0, "haul_mult": 1.5}
	sd = _begin(s)
	s.apply_result("raid", _raid_res(sd, {"warden_beaten": true, "retreated": false}))
	t.near(s.drain_events()[1]["hold_s"], 200.0, 1e-9, "hold_s reads flip.* from realm.json")


func _raid_death() -> void:
	t.suite("results-raid-death")
	for vats in [0, 1]:
		var s := _mk()
		s.town["vats"] = vats
		s.cmd_debug_grant({"big_undead": 2})
		var bus: Array = s.view_big_undead()["big_undead"]
		var u1: String = bus[0]["uid"]
		var u2: String = bus[1]["uid"]
		s.cmd_set_party([u1, u2])
		s.army = {"soldier": 10, "elite": 10}
		_set_fort(s, "old-sluice", 60.0, 30.0, 25.0)
		var sd := _begin(s)
		s.drain_events()
		var out := s.apply_result("raid", _raid_res(sd, {"retreated": false, "relish_died": true, "killed_living_mass": 10.0,
			"raised": [{"score": 70, "count": 2, "mass": 4.0}], "garrison_mass": 20.0, "party_lost": [u1],
			"loot": {"relics": 2, "blueprints": [], "husks": [{"kind": "zombie"}], "remnants": [], "essence": 7}}))
		var evs := s.drain_events()
		t.ok(out["ok"] and _types(evs) == ["loot_banked", "relish_died", "relish_respawned"], "death events in order (%s)" % str(_types(evs)))
		t.ok(evs[1] == {"type": "relish_died", "t": s.t, "outcome": "clone" if vats == 1 else "unmade", "in_place": false,
			"at": "old-sluice", "run_id": sd["run_id"], "respawn_s": 0.0}, "relish_died: %s" % str(evs[1]))
		t.ok(evs[2] == {"type": "relish_respawned", "t": s.t, "with_clone": vats == 1, "at": "covington"}, "relish_respawned")
		t.ok(s.relics == 2 and s.essence == 7 and s.husks.size() == 1, "the banked loot is kept on a death")
		t.ok(s.big_undead.is_empty() and s.party_uids == [], "the whole party is lost (A8); no stale uid in the party list")
		t.ok(s.view_relish()["state"] == "home" and s.view_relish()["at"] == "covington" and s.run.is_empty(), "she respawns home at once")
		t.ok(_fort(s, "old-sluice").get("flipped_count", 0) == 0 and not _fort(s, "old-sluice").has("held_s"), "a death does not flip")
		t.ok(s.town["vats"] == 0, "the legacy vat is spent or was absent")
		if vats == 1:
			t.ok(s.army == {"soldier": 12, "elite": 10}, "a clone: the army stays (+2 soldiers from step 12)")
		else:
			t.ok(s.army == {"soldier": int(12 * 0.6), "elite": int(10 * 0.7)}, "unmade: the army scatters, after step 12 added")
		t.ok(s.stats["deaths"] == 1 and s.stats["raids"] == 1, "legacy stats")


# ------------------------------------------------------------ boss writeback ----
func _boss_writeback() -> void:
	t.suite("results-boss")
	var s := _mk()
	s.cmd_debug_grant({"big_undead": 2, "backlog": 1000.0})
	var bus: Array = s.view_big_undead()["big_undead"]
	var u1: String = bus[0]["uid"]
	var u2: String = bus[1]["uid"]
	s.cmd_set_party([u1, u2])
	s.army = {"soldier": 10, "elite": 10}
	var sd := _begin_boss(s)
	s.drain_events()
	var rv := s.rev
	var q0: float = s.realm.vei["undead_queue"]
	var out := s.apply_result("boss", _boss_res(sd, {"won": true, "fronts_cleared": ["giants", "raw"], "party_lost": [u1], "backlog_spent": 400.0}))
	t.ok(out == {"ok": true, "reason": "", "errors": [], "minted": []} and s.rev == rv + 1, "a win: ok, rev +1")
	var evs := s.drain_events()
	t.ok(evs == [{"type": "vei_result", "t": s.t, "run_id": sd["run_id"], "won": true, "fronts_cleared": ["giants", "raw"],
		"relish_deaths": 0, "backlog_after": q0}], "a win: one vei_result, backlog unchanged: %s" % str(evs))
	t.ok(s.won == true and s.realm.vei["undead_queue"] == q0, "won = true; backlog_spent is not subtracted")
	t.ok(s.view_relish()["state"] == "at_vei" and s.run.is_empty(), "she stays at Vei")
	t.ok(s.party_uids == [u2] and s.view_big_undead()["big_undead"].size() == 1, "party_lost removed on a win; the rest live")
	t.ok(s.army == {"soldier": 10, "elite": 10}, "no army change on a win")
	# a loss keeps 35 %, the whole party dies, the army shrinks
	s = _mk()
	s.cmd_debug_grant({"big_undead": 2, "backlog": 1000.0})
	bus = s.view_big_undead()["big_undead"]
	s.cmd_set_party([bus[0]["uid"], bus[1]["uid"]])
	s.army = {"soldier": 10, "elite": 10}
	sd = _begin_boss(s)
	s.drain_events()
	q0 = s.realm.vei["undead_queue"]
	out = s.apply_result("boss", _boss_res(sd, {"won": false, "relish_deaths": 0, "backlog_spent": 700.0}))
	t.ok(out["ok"], "a loss without a death")
	t.near(s.realm.vei["undead_queue"], q0 * 0.35, 1e-9, "the loss keeps 35 % of the backlog (vei.json)")
	t.ok(s.won == false and s.big_undead.is_empty() and s.party_uids == [], "the whole party dies on a loss")
	t.ok(s.army == {"soldier": 3, "elite": 4}, "legacy army x0.3 / x0.4")
	evs = s.drain_events()
	t.ok(_types(evs) == ["vei_result"] and evs[0]["won"] == false and evs[0]["relish_deaths"] == 0 and absf(evs[0]["backlog_after"] - q0 * 0.35) < 1e-9,
		"vei_result carries backlog_after")
	t.ok(s.view_relish()["state"] == "at_vei", "alive after a loss, she stays at Vei")
	# loss_backlog_keep from vei.json
	s = _mk()
	s._cfgs["vei"]["loss_backlog_keep"] = 0.5
	s.cmd_debug_grant({"backlog": 1000.0})
	sd = _begin_boss(s)
	s.apply_result("boss", _boss_res(sd, {"won": false}))
	t.near(s.realm.vei["undead_queue"], 500.0, 1e-9, "vei.json loss_backlog_keep is read")
	# a final death
	for vats in [0, 1]:
		s = _mk()
		s.town["vats"] = vats
		s.cmd_debug_grant({"backlog": 1000.0, "big_undead": 1})
		s.cmd_set_party([s.view_big_undead()["big_undead"][0]["uid"]])
		s.army = {"soldier": 10, "elite": 10}
		sd = _begin_boss(s)
		s.drain_events()
		out = s.apply_result("boss", _boss_res(sd, {"won": false, "relish_deaths": 1}))
		evs = s.drain_events()
		t.ok(out["ok"] and _types(evs) == ["vei_result", "relish_died", "relish_respawned"], "final death: vei_result first (%s)" % str(_types(evs)))
		t.ok(evs[1]["outcome"] == ("clone" if vats == 1 else "unmade") and evs[1]["at"] == "vei" and evs[1]["in_place"] == false
			and evs[1]["run_id"] == sd["run_id"] and evs[0]["relish_deaths"] == 1, "the legacy vat rule: %s" % str(evs[1]))
		t.ok(s.view_relish()["state"] == "home" and s.big_undead.is_empty() and s.run.is_empty(), "respawned home at once, party gone")
		t.ok(s.army == ({"soldier": 3, "elite": 4} if vats == 1 else {"soldier": 1, "elite": 2}), "army x0.3/x0.4, then the scatter when unmade")
	# a spent clone is not a death event at E1
	s = _mk()
	s.town["vats"] = 2
	sd = _begin_boss(s)
	s.drain_events()
	out = s.apply_result("boss", _boss_res(sd, {"won": false, "relish_deaths": 1, "backups_spent": {"phylactery": 0, "clones": 1}}))
	t.ok(out["ok"] and s.town["vats"] == 1 and _types(s.drain_events()) == ["vei_result"] and s.view_relish()["state"] == "at_vei",
		"a loss with a clone spent: one vat used, she carries on at Vei (in-place events are E3)")


## I2 (the writeback creates no mass) and phylactery charges are spent (§8.3).
func _mass_and_charges() -> void:
	var s := _mk()
	_set_fort(s, "old-sluice", 60.0, 30.0, 25.0)
	var sd := _begin(s)
	t.near(sd["garrison_in_mass"], 20.0, 1e-9, "garrison_in is 20")
	_set_fort(s, "old-sluice", 60.0, 30.0, 15.0)  # the fort was drained during the run
	var f := _fort(s, "old-sluice")
	var total0: float = f["living"] + f["dead"] + f["undead"] + s.realm.vei["undead_queue"] + s._dungeon_sink
	var q0: float = s.realm.vei["undead_queue"]
	s.apply_result("raid", _raid_res(sd, {"garrison_mass": 0.0, "chaff_mass": 20.0}))
	f = _fort(s, "old-sluice")
	t.near(f["undead"], 0.0, 1e-9, "drained fort: undead clamped at 0")
	t.near(s.realm.vei["undead_queue"] - q0, 15.0, 1e-9, "Vei gains exactly what the fort lost")
	t.near(s._dungeon_sink, 0.0, 1e-9, "no sink")
	var total1: float = f["living"] + f["dead"] + f["undead"] + s.realm.vei["undead_queue"] + s._dungeon_sink
	t.near(total1, total0, 1e-9, "fort + Vei + sink is conserved")
	var v := GameState.new(TestUtil.configs())
	v.debug_enabled = true
	t.ok(v.cmd_debug_load_fixture("pre_vei")["ok"], "pre_vei loads")
	t.ok(v._phylactery_charges == 1, "pre_vei holds 1 charge")
	var bsd := _begin_boss(v)
	t.ok(v.apply_result("boss", _boss_res(bsd, {"won": true, "relish_deaths": 1, "backups_spent": {"phylactery": 1, "clones": 0}}))["ok"], "boss with a revive applies")
	t.ok(v._phylactery_charges == 0, "boss writeback spends the phylactery charge")
	var w := _mk()
	w._phylactery_charges = 1
	var rsd := _begin(w)
	t.ok(w.apply_result("raid", _raid_res(rsd, {"revived_in_place": 1}))["ok"], "raid with a revive applies")
	t.ok(w._phylactery_charges == 0, "raid writeback spends the phylactery charge")


# ---------------------------------------- the pre-E1 writeback, kept here as the oracle ----
## The removed GameState.apply_raid_result, verbatim, run against `s` with no run open.
func _legacy_raid(s: GameState, r: Dictionary) -> void:
	var f := s.realm.fort_by_id(str(r.get("fort_id", "")))
	if f.is_empty():
		return
	s.stats["raids"] += 1
	var killed: float = minf(f["living"], float(r.get("killed_living_mass", 0.0)))
	f["living"] -= killed
	f["dead"] += killed
	var chaff: float = minf(f["dead"], float(r.get("raised_chaff_mass", 0.0)))
	f["dead"] -= chaff
	s.realm.vei["undead_queue"] += chaff
	var good_mass: float = minf(f["dead"], float(r.get("good_mass", 0.0)))
	f["dead"] -= good_mass
	s.army["soldier"] += int(r.get("raised_soldiers", 0))
	s.army["elite"] += int(r.get("raised_elites", 0))
	var garrison: float = minf(f["dead"], float(r.get("garrison_mass", 0.0)))
	f["dead"] -= garrison
	f["undead"] += garrison
	s.stats["raised_total"] += chaff + good_mass + garrison
	if bool(r.get("relish_died", false)):
		s._legacy_death(-1)


## The removed GameState.apply_boss_result, verbatim.
func _legacy_boss(s: GameState, r: Dictionary) -> void:
	if bool(r.get("won", false)):
		s.won = true
		s._emit(_legacy_vei(s, true, 0))
		return
	s.realm.vei["undead_queue"] *= 0.35
	s.army["soldier"] = int(s.army["soldier"] * 0.3)
	s.army["elite"] = int(s.army["elite"] * 0.4)
	var died := bool(r.get("relish_died", true))
	if died:
		s._legacy_death(-1)
	s._emit(_legacy_vei(s, false, 1 if died else 0))


func _legacy_vei(s: GameState, did_win: bool, deaths: int) -> Dictionary:
	return {"type": "vei_result", "run_id": -1, "won": did_win, "fronts_cleared": [],
		"relish_deaths": deaths, "backlog_after": float(s.realm.vei["undead_queue"])}


# -------------------------------------------------- v1 -> v2 -> writeback parity ----
func _legacy_state(seed_val: int) -> GameState:
	var s := _mk(seed_val)
	_set_fort(s, "old-sluice", 60.0, 30.0, 25.0)
	s.army = {"soldier": 4, "elite": 2}
	return s


func _parity() -> void:
	t.suite("results-parity")
	var v1 := {"fort_id": "old-sluice", "killed_living_mass": 20.0, "raised_chaff_mass": 18.0, "raised_soldiers": 3,
		"raised_elites": 1, "good_mass": 9.0, "garrison_mass": 12.0, "relish_died": false, "aborted": false}
	for died in [false, true]:
		var v1d := v1.duplicate()
		v1d["relish_died"] = died
		var a := _legacy_state(3)
		a.legacy_teleport_relish("old-sluice")
		_legacy_raid(a, v1d)
		var b := _legacy_state(3)
		var sd := _begin(b)
		var v2 := Results.from_v1("raid", v1d, sd)
		t.ok(Results.validate("raid", v2) == [], "the converted result is valid")
		var out := b.apply_result("raid", v2)
		t.ok(out["ok"], "the converted result applies")
		var fa := _fort(a, "old-sluice")
		var fb := _fort(b, "old-sluice")
		var tag := "raid%s" % (" with a death" if died else "")
		t.near(fb["dead"], fa["dead"], 1e-9, "%s: fort dead equals the legacy writeback" % tag)
		t.near(fb["living"], fa["living"], 1e-9, "%s: fort living equals" % tag)
		t.near(b.realm.vei["undead_queue"], a.realm.vei["undead_queue"], 1e-9, "%s: vei.undead_queue equals" % tag)
		t.ok(b.army == a.army, "%s: legacy army equals (%s vs %s)" % [tag, str(b.army), str(a.army)])
		# the one deliberate change: good_mass stays at the fort as undead
		t.near(fb["undead"], fa["undead"] + v1["good_mass"], 1e-9, "%s: undead = legacy + good_mass (the deliberate change)" % tag)
		t.near(b._dungeon_sink, 0.0, 1e-9, "%s: nothing is lost to the dungeon sink" % tag)
		t.ok(b.stats["deaths"] == a.stats["deaths"] and b.town["vats"] == a.town["vats"], "%s: deaths and vats equal" % tag)
		t.ok(b.view_relish()["state"] == a.view_relish()["state"] or not died, "%s: relish state" % tag)
		if died:
			t.ok(_types(b.drain_events()) == ["loot_banked", "relish_died", "relish_respawned"] and _types(a.drain_events()) == ["relish_died", "relish_respawned"],
				"%s: the v2 path adds loot_banked and keeps the legacy death events" % tag)
	# a legacy vat
	var a2 := _legacy_state(4)
	a2.town["vats"] = 1
	a2.legacy_teleport_relish("old-sluice")
	var vd := v1.duplicate()
	vd["relish_died"] = true
	_legacy_raid(a2, vd)
	var b2 := _legacy_state(4)
	b2.town["vats"] = 1
	var sd2 := _begin(b2)
	b2.apply_result("raid", Results.from_v1("raid", vd, sd2))
	t.ok(b2.town["vats"] == a2.town["vats"] and b2.army == a2.army, "raid death with a vat: vats and army equal")
	# boss
	for case in [{"won": true, "relish_died": true}, {"won": false, "relish_died": true}, {"won": false, "relish_died": false}]:
		for vats in [0, 1]:
			var a3 := _legacy_state(5)
			a3.town["vats"] = vats
			a3.cmd_debug_grant({"backlog": 2000.0})
			var b3 := _legacy_state(5)
			b3.town["vats"] = vats
			b3.cmd_debug_grant({"backlog": 2000.0})
			a3.legacy_teleport_relish("vei")
			_legacy_boss(a3, case)
			var bsd := _begin_boss(b3)
			var bv := Results.from_v1("boss", case, bsd)
			t.ok(Results.validate("boss", bv) == [], "the converted boss result is valid")
			var o3 := b3.apply_result("boss", bv)
			var lbl := "boss %s vats %d" % [str(case), vats]
			t.ok(o3["ok"], "%s: applies" % lbl)
			t.near(b3.realm.vei["undead_queue"], a3.realm.vei["undead_queue"], 1e-9, "%s: backlog equals" % lbl)
			t.ok(b3.army == a3.army and b3.won == a3.won and b3.town["vats"] == a3.town["vats"], "%s: army, won and vats equal" % lbl)
			t.ok(b3.view_relish()["state"] == a3.view_relish()["state"] or not (case["relish_died"] and not case["won"]), "%s: she is home after a death" % lbl)
			var ea := a3.drain_events().filter(func(e): return e["type"] == "vei_result")
			var eb := b3.drain_events().filter(func(e): return e["type"] == "vei_result")
			t.ok(ea.size() == 1 and eb.size() == 1 and ea[0]["won"] == eb[0]["won"] and ea[0]["relish_deaths"] == eb[0]["relish_deaths"]
				and absf(ea[0]["backlog_after"] - eb[0]["backlog_after"]) < 1e-9, "%s: the same vei_result" % lbl)


# ----------------------------------------------------------------------- misc ----
func _misc() -> void:
	t.suite("results-misc")
	# applied_runs keeps the last 32
	var s := _mk()
	var ids: Array = []
	for i in 35:
		var sd := _begin(s)
		ids.append(sd["run_id"])
		s.apply_result("raid", _raid_res(sd))
	t.ok(s.applied_runs.size() == 32 and s.applied_runs == ids.slice(3), "applied_runs keeps the last 32 run ids")
	var last_sd: Dictionary = s.cmd_begin_dungeon("old-sluice")["seed"]
	t.ok(s.apply_result("raid", _raid_res(last_sd))["ok"], "the latest run still applies")
	t.ok(s.apply_result("raid", _raid_res(last_sd))["reason"] == "duplicate_run", "and is a duplicate afterwards")
	# a new game keeps run ids unique, so applied_runs needs no reset
	var n := s.next_run_id
	s.cmd_new_game(2)
	t.ok(s.next_run_id == n and s.applied_runs.size() > 0, "applied_runs survives a new game like next_run_id")
	# the new game resets the sink
	s = _mk()
	_set_fort(s, "old-sluice", 60.0, 30.0, 25.0)
	var sd3 := _begin(s)
	s.apply_result("raid", _raid_res(sd3, {"garrison_mass": 0.0}))
	t.ok(s._dungeon_sink == 20.0, "garrison lost is sunk")
	s.cmd_new_game(3)
	t.ok(s.ledger()["sinks"]["dungeon"] == 0.0 and not _fort(s, "old-sluice").has("held_s"), "a new game resets the sink and the forts")
	# the caller's dictionary is never changed
	s = _mk()
	var sd4 := _begin(s)
	var res := _raid_res(sd4, {"run_id": float(sd4["run_id"]), "raised": [{"score": 80.0, "count": 2.0, "mass": 1.0}]})
	var copy := res.duplicate(true)
	s.apply_result("raid", res)
	t.ok(res == copy, "apply_result leaves the result untouched")
	# refusal leaves rng and uids alone even with minting loot
	s = _mk()
	var sd5 := _begin(s)
	var bad := _raid_res(sd5, {"party_lost": ["u9"], "loot": {"relics": 1, "blueprints": [], "husks": [{"kind": "hulk"}], "remnants": [], "essence": 0}})
	_refused(s, "raid", bad, "bad_party", "a refusal with minting loot")
