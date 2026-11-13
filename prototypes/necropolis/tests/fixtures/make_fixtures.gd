extends SceneTree
## Regenerates the three fixture saves (STATE-API 9.4). Run by hand, from the repo root:
##   godot --headless --path prototypes/necropolis --script res://tests/fixtures/make_fixtures.gd
## It takes a few minutes (it really simulates 1 h and 3 h). Every state is built with
## cmd_new_game(1), then commands and debug commands, so the files are reproducible. Fields that
## no E1 command can produce yet are written straight into the save dict, marked "E2 field" or
## "E3 field" below; the state is then loaded and re-dumped, so each file is exactly what
## `to_dict()` gives after a load. Run it again (and commit the JSON) whenever the save shape
## changes, and whenever E2/E3 can produce these fields for real.

const OUT := "res://tests/fixtures"
const SAVED_UNIX := 1794556800  # a fixed wall-clock stamp, so the files stay deterministic

var _cfgs := {}


func _init() -> void:
	_cfgs = GameState.load_configs("res://configs")
	_write("day1", _day1())
	_write("midgame_2flips", _midgame())
	_write("pre_vei", _pre_vei())
	print("fixtures written to ", OUT)
	quit()


func _fail(msg: String) -> void:
	printerr("make_fixtures: " + msg)
	quit(1)
	OS.kill(OS.get_process_id())  # stop at once: _init has no way to unwind


func _need(r: Dictionary, what: String) -> Dictionary:
	if not r.get("ok", false):
		_fail("%s refused: %s" % [what, str(r)])
	return r


func _new() -> GameState:
	var s := GameState.new(_cfgs)
	s.debug_enabled = true
	_need(s.cmd_new_game(1), "cmd_new_game")
	return s


## Dumps, edits (`edit` gets the dict), loads the edit into a fresh state and writes what that
## state saves, so the file survives load -> to_dict unchanged.
func _write(name: String, d: Dictionary) -> void:
	d["saved_unix"] = SAVED_UNIX
	var chk := GameState.new(_cfgs)
	var r := chk.from_dict(JSON.parse_string(JSON.stringify(d)))
	_need(r, "from_dict(%s)" % name)
	var f := FileAccess.open("%s/%s.json" % [OUT, name], FileAccess.WRITE)
	if f == null:
		_fail("cannot write %s" % name)
	f.store_string(JSON.stringify(chk.to_dict(), "\t") + "\n")
	f.close()


## A won raid on `fort`: Relish is put there, the dungeon opens, the result flips the fort.
func _flip(s: GameState, fort: String, loot: Dictionary) -> void:
	_need(s.cmd_debug_set_state({"relish_at": fort}), "relish_at " + fort)
	var b := _need(s.cmd_begin_dungeon(fort), "begin " + fort)
	var sd: Dictionary = b["seed"]
	_need(s.apply_result("raid", {
		"v": 2, "run_id": sd["run_id"], "seed_rev": sd["seed_rev"], "fort_id": fort,
		"warden_beaten": true, "retreated": false, "relish_died": false, "revived_in_place": 0,
		"killed_living_mass": 20.0, "raised": [{"score": 80, "count": 2, "mass": 5.0}], "chaff_mass": 2.0,
		"garrison_mass": sd["garrison_in_mass"], "party_lost": [], "loot": loot,
	}), "apply_result " + fort)


func _uids(s: GameState) -> Array:
	return s.view_big_undead()["big_undead"].map(func(b): return b["uid"])


## cmd_new_game(1) at t = 0: the legacy start (gold 30, materials 12, 6 workers) until E2.
func _day1() -> Dictionary:
	return _new().to_dict()


## About 1 h in: two flips, a convoy on the road, Relish leaving Covington for Greywall.
func _midgame() -> Dictionary:
	var s := _new()
	_need(s.cmd_debug_skip_time(3600.0), "skip_time")
	_flip(s, "old-sluice", {"relics": 1, "essence": 5, "blueprints": ["embalmer"], "husks": [{"kind": "hulk"}],
		"remnants": [{"aspect": "power", "rarity": "common", "magnitude": 2}, {"aspect": "beef", "rarity": "uncommon", "magnitude": 3}]})
	_flip(s, "ashgate", {"relics": 1, "essence": 4, "blueprints": [], "husks": [{"kind": "zombie"}],
		"remnants": [{"aspect": "wits", "rarity": "rare", "magnitude": 4}, {"aspect": "speed", "rarity": "common", "magnitude": 1}]})
	# exactly 3 relics and 14 essence (the two raids banked 2 and 9)
	_need(s.cmd_debug_grant({"relics": 3 - s.relics, "essence": 14 - s.essence}), "grant relics, essence")
	_need(s.cmd_debug_grant({"big_undead": 3}), "grant big undead")
	var u := _uids(s)
	_need(s.cmd_place_big_undead(u[1], "town:lot-04"), "foreman")  # u[0] stays in the crypt
	_need(s.cmd_place_big_undead(u[2], "fort:ashgate"), "siege")
	_need(s.cmd_debug_set_state({"forge_level": 1}), "forge level")
	# the legacy haul convoy: one gatherer sent to Greywall
	s.apply_town_result({"assignments": {"trade": 0, "forge": 0, "jobs": 0, "gather": 1, "slab": 0}, "idle_undead": 5})
	_need(s.cmd_set_haul_target("greywall"), "haul target")
	_need(s.cmd_debug_set_state({"relish_at": "covington"}), "relish home")
	_need(s.cmd_move_relish("greywall"), "travel")
	s.tick(0.5)  # the convoy leaves and Relish is on the road, both still in flight
	if s.gather["phase"] != "out" or s.relish["state"] != "travelling":
		_fail("the convoy or the journey is not in flight: %s / %s" % [s.gather["phase"], s.relish["state"]])
	var d := s.to_dict()
	d["town"]["tier"] = "village"  # E2 field: no command promotes the town yet
	# E2 field: the tithe block. The warning mirrors the tithe_warning event (§6).
	d["realm"]["tithe"] = {"warning": {"wave_id": 1, "fort_id": "ashgate", "eta_s": 150.0, "surge": 24.0}}
	return d


## About 3 h in: the city, a backlog of 1.5 K (odds 0.6), a party of 4 on the 4 fronts, Relish at Vei.
func _pre_vei() -> Dictionary:
	var s := _new()
	_need(s.cmd_debug_skip_time(10800.0), "skip_time")
	_need(s.cmd_debug_grant({"big_undead": 4}), "grant big undead")
	var u := _uids(s)
	_need(s.cmd_set_party(u), "party")
	for i in u.size():
		_need(s.cmd_assign_front(u[i], GameState.FRONT_IDS[i]), "front " + str(i))
	var k := float(_cfgs["realm"]["K"])
	_need(s.cmd_debug_grant({"backlog": 1.5 * k - float(s.realm.vei["undead_queue"])}), "backlog")
	s.town["vats"] = 1  # legacy store: one vat, which is 1 clone ready at E1 (no E1 command builds a vat)
	_need(s.cmd_debug_set_state({"relish_at": "vei"}), "relish at Vei")
	var d := s.to_dict()
	d["town"]["tier"] = "city"  # E2 field: no command promotes the town yet
	d["backups"]["phylactery_charges"] = 1  # E3 field: no E1 system makes a charge
	return d
