extends RefCounted
## Pins GameState's behaviour (E2b T3.A): a fixed command log per starting state, then
## JSON.stringify(to_dict()) and of every view_* (but view_field) against golden strings captured
## from the code as it was before the GameState extraction (tests/fixtures/snapshot_golden.json,
## written by tests/fixtures/make_snapshot_golden.gd). Command results and events are part of it.
## A deliberate behaviour change regenerates the golden file; a refactor must not.

const GOLDEN := "res://tests/fixtures/snapshot_golden.json"
const STARTS := ["new", "day1", "midgame_2flips", "pre_vei"]
const VIEWS := ["view_hud", "view_rates", "view_lanes", "view_realm", "view_villages", "view_relish",
	"view_town", "view_catalog", "view_stances", "view_inventory", "view_big_undead", "view_party",
	"view_backups", "view_vei", "view_boss_seed"]


func _snap(s: GameState, out: Dictionary, tag: String) -> void:
	out[tag + ":to_dict"] = JSON.stringify(s.to_dict())
	for v in VIEWS:
		var d: Dictionary = s.call(v)
		if v == "view_villages":  # a dominance can be NaN, which JSON.stringify warns about: write it as text
			for vl in d["villages"]:
				vl["dominance"] = str(vl["dominance"])
		out["%s:%s" % [tag, v]] = JSON.stringify(d)
	for id in ["old-sluice", "ashgate", "no-such-fort"]:
		out["%s:view_fort:%s" % [tag, id]] = JSON.stringify(s.view_fort(id))
		out["%s:view_dungeon_seed:%s" % [tag, id]] = JSON.stringify(s.view_dungeon_seed(id))
	out[tag + ":ledger"] = JSON.stringify(s.ledger())
	out[tag + ":q"] = JSON.stringify([s.digest_q(), s.worker_mass(), s.raiding_fort_id(), s.rev])


func _log(out: Dictionary, log: Array, label: String, res: Variant) -> void:
	log.append("%s %s" % [label, JSON.stringify(res)])
	out["log"] = "\n".join(log)


func _raid_result(sd: Dictionary, over := {}) -> Dictionary:
	var r := {
		"v": 2, "run_id": sd["run_id"], "seed_rev": sd["seed_rev"], "fort_id": sd["fort"]["id"],
		"warden_beaten": false, "retreated": true, "relish_died": false, "revived_in_place": 0,
		"killed_living_mass": 0.0, "raised": [], "chaff_mass": 0.0, "garrison_mass": sd["garrison_in_mass"],
		"party_lost": [], "loot": {"relics": 0, "blueprints": [], "husks": [], "remnants": [], "essence": 0},
	}
	r.merge(over, true)
	return r


func _walk(s: GameState, dest: String) -> void:
	s.cmd_move_relish(dest)
	var n := 0
	while s.relish["state"] == "travelling" and n < 400:
		s.tick(5.0)
		n += 1


## The scripted session for one starting state: {key: string}.
func capture(start: String) -> Dictionary:
	var cfgs := TestUtil.configs()
	var fld: Dictionary = cfgs["realm"]["field"]
	fld["tick_hz"] = 0.01  # the field barely runs: the pin is about the economy
	cfgs["economy"]["sim"]["substep_s"] = 2.0  # in memory: 4x fewer substeps for the same two sim-hours
	var s := GameState.new(cfgs)
	s.debug_enabled = true
	var out := {}
	var log: Array = []
	_log(out, log, "new_game", s.cmd_new_game(7))
	if start != "new":
		_log(out, log, "fixture", s.cmd_debug_load_fixture(start))
	_snap(s, out, "start")
	# a valve change, a debug grant
	_log(out, log, "valve", s.cmd_set_valve(0.2, 0.5, 0.3))
	_log(out, log, "valve_bad", s.cmd_set_valve(0.0, 0.0, 0.0))
	_log(out, log, "grant", s.cmd_debug_grant({"gold": 2000, "bone": 1000, "bodies": 60, "relics": 4, "essence": 3,
		"workers": 4, "living": 8, "backlog": 25, "husks": 2, "remnants": 3, "big_undead": 2}))
	_log(out, log, "grant_bad", s.cmd_debug_grant({"nope": 1}))
	# builds: the first two the catalog allows, a cancel, an upgrade, refusals, a demolish
	var picked: Array = []
	for e in s.view_catalog()["buildings"]:
		if e["can_build"] and picked.size() < 2:
			picked.append(e)
	for e in picked:
		var lot: String = (s.view_catalog()["buildings"].filter(func(x): return x["building_id"] == e["building_id"])[0]["lots"] as Array)[0]
		_log(out, log, "build " + e["building_id"], s.cmd_build(e["building_id"], lot))
		e["_lot"] = lot
	if picked.size() > 1:
		_log(out, log, "cancel", s.cmd_cancel_build(picked[1]["_lot"]))
	_log(out, log, "build_bad", s.cmd_build("nope", "lot-01"))
	if not picked.is_empty():
		_log(out, log, "build_taken", s.cmd_build(picked[0]["building_id"], picked[0]["_lot"]))
		_log(out, log, "upgrade_busy", s.cmd_upgrade(picked[0]["_lot"]))
		_log(out, log, "demolish_busy", s.cmd_demolish(picked[0]["_lot"]))
	_log(out, log, "build_locked", s.cmd_build("raising_pit", "lot-24"))
	_log(out, log, "build_unique", s.cmd_build("crypt", "lot-23"))
	_log(out, log, "build_bad_lot", s.cmd_build("house", "lot-99"))
	_log(out, log, "cancel_bad", s.cmd_cancel_build("lot-99"))
	var built: Array = []
	for b in s.view_town()["buildings"]:
		if b["state"] != "constructing":
			built.append(b)
	if not built.is_empty():
		_log(out, log, "upgrade", s.cmd_upgrade(built[0]["lot_id"]))
	for b in built:
		if int(b["slots"]) > 0:
			_log(out, log, "staff_cap", s.cmd_set_staff_cap(b["lot_id"], 1))
			break
	for b in built:
		if b["building_id"] != "crypt":
			_log(out, log, "demolish", s.cmd_demolish(b["lot_id"]))
			break
	_log(out, log, "upgrade_bad", s.cmd_upgrade("lot-99"))
	_log(out, log, "demolish_bad", s.cmd_demolish("lot-99"))
	s.tick(30.0)
	_snap(s, out, "built")
	# settings: job priority, stance, haul target, vat, big undead and the party
	var ladder: Array = (s.view_town()["ladder"] as Array).duplicate()
	ladder.reverse()
	_log(out, log, "ladder", s.cmd_set_job_priority(ladder))
	_log(out, log, "stance", s.cmd_set_stance("vigil", true))
	_log(out, log, "haul", s.cmd_set_haul_target("old-sluice"))
	_log(out, log, "vat", s.cmd_staff_vat(0, true))
	var uids: Array = []
	for b in s.view_big_undead()["big_undead"]:
		uids.append(b["uid"])
	_log(out, log, "party", s.cmd_set_party(uids))
	if not uids.is_empty():
		_log(out, log, "front", s.cmd_assign_front(uids[0], "giants"))
		_log(out, log, "rename", s.cmd_rename_big_undead(uids[0], "  Grim  "))
	# Relish to a fort and back, then to the fort again
	_log(out, log, "at_home", s.cmd_debug_set_state({"relish_at": "covington"}))
	_walk(s, "old-sluice")
	_snap(s, out, "at_fort")
	_walk(s, "covington")
	_walk(s, "old-sluice")
	# a dungeon run and a flipping raid result, then a second raid in which she dies
	var b1 := s.cmd_begin_dungeon("old-sluice")
	_log(out, log, "begin_dungeon", b1)
	_snap(s, out, "in_dungeon")
	if b1["ok"]:
		var sd: Dictionary = b1["seed"]
		var lost: Array = []
		if not (sd["party"] as Array).is_empty():
			lost.append(sd["party"][0]["uid"])
		var loot := {"relics": 2, "blueprints": ["embalmer"], "husks": [{"kind": "hulk"}],
			"remnants": [{"aspect": "beef", "rarity": "rare", "magnitude": 2}], "essence": 5}
		var win := _raid_result(sd, {"warden_beaten": true, "retreated": false, "killed_living_mass": 20.0,
			"raised": [{"score": 80, "count": 2, "mass": 5.0}, {"score": 40, "count": 1, "mass": 3.0}],
			"chaff_mass": 2.0, "party_lost": lost, "loot": loot})
		_log(out, log, "stale", s.apply_result("raid", _raid_result(sd, {"seed_rev": 1})))
		_log(out, log, "apply_win", s.apply_result("raid", win))
		_log(out, log, "apply_dup", s.apply_result("raid", win))
	_snap(s, out, "after_flip")
	_log(out, log, "to_ashgate", s.cmd_debug_set_state({"relish_at": "ashgate"}))
	var b2 := s.cmd_begin_dungeon("ashgate")
	_log(out, log, "begin_dungeon2", b2)
	if b2["ok"]:
		_log(out, log, "apply_death", s.apply_result("raid", _raid_result(b2["seed"], {"relish_died": true,
			"retreated": false, "killed_living_mass": 3.0, "raised": [{"score": 60, "count": 1, "mass": 2.0}]})))
	# the boss: begin and abort, then begin and lose
	_log(out, log, "to_vei", s.cmd_debug_set_state({"relish_at": "vei"}))
	var bb := s.cmd_begin_boss()
	_log(out, log, "begin_boss", bb)
	_snap(s, out, "in_boss")
	_log(out, log, "abort", s.cmd_abort_dungeon())
	var bb2 := s.cmd_begin_boss()
	_log(out, log, "begin_boss2", bb2)
	if bb2["ok"]:
		_log(out, log, "boss_lose", s.apply_result("boss", {"v": 2, "run_id": bb2["run_id"], "seed_rev": bb2["seed_rev"],
			"won": false, "fronts_cleared": [], "relish_deaths": 1, "backups_spent": {"phylactery": 0, "clones": 0},
			"party_lost": [], "backlog_spent": 0.0}))
	# debug state and skip, then about two sim-hours
	_log(out, log, "set_state", s.cmd_debug_set_state({"time_scale": 2.0, "forge_level": 2,
		"valve": {"work": 1.0, "war": 1.0, "flood": 2.0}, "forts": {"greywall": {"living": 30.0, "dead": 12.0}}}))
	_log(out, log, "set_state_bad", s.cmd_debug_set_state({"time_scale": 0.0}))
	_log(out, log, "skip", s.cmd_debug_skip_time(120.0))
	_log(out, log, "stances2", s.cmd_set_stance("harvest", true))
	for i in 120:
		s.tick(60.0)
		if i == 59:
			_snap(s, out, "hour1")
			_log(out, log, "events1", s.drain_events())
	_log(out, log, "events2", s.drain_events())
	_snap(s, out, "end")
	return out


func run() -> int:
	var t := TestUtil.new()
	t.suite("game-state-snapshot")
	var golden := TestUtil.load_json(GOLDEN)
	t.ok(not golden.is_empty(), "the golden file loads")
	for start in STARTS:
		var want: Dictionary = golden.get(start, {})
		var got := capture(start)
		var bad: Array = []
		for k in want:
			if not got.has(k) or got[k] != want[k]:
				bad.append(k)
		for k in got:
			if not want.has(k):
				bad.append(k + " (new)")
		t.ok(bad.is_empty() and not want.is_empty(), "%s: %d snapshots equal the golden (differing: %s)" % [start, want.size(), str(bad.slice(0, 6))])
		if "log" in bad and want.has("log") and got.has("log"):
			var a: PackedStringArray = (want["log"] as String).split("\n")
			var b: PackedStringArray = (got["log"] as String).split("\n")
			for i in mini(a.size(), b.size()):
				if a[i] != b[i]:
					printerr("    first differing log line %d:\n      want %s\n      got  %s" % [i, a[i].left(300), b[i].left(300)])
					break
	return t.failures
