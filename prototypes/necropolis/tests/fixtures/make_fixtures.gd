extends SceneTree
## Regenerates the three fixture saves (STATE-API 9.4). Run by hand, from the repo root:
##   godot --headless --path prototypes/necropolis --script res://tests/fixtures/make_fixtures.gd
## It takes a few minutes (it really simulates 1 h and 3 h). Every state is built with
## cmd_new_game(1), then commands, debug commands and TownSim.place_building (a placement is instant
## and free, which a build is not; the town's tier then rises by itself, as in play), so the files are
## reproducible. Fields that no command can produce yet are
## written straight into the state or the save dict, marked "E2 field" or "E3 field" below; the
## state is then loaded and re-dumped, so each file is exactly what `to_dict()` gives after a load.
## Run it again (and commit the JSON) whenever the save shape changes, and whenever E2/E3 can
## produce these fields for real. v1_*.json are the E1 (save v1) fixtures, kept for the migration
## tests; this script never writes them.
## NOTE (E4 step 3): this script no longer reproduces the committed day1, midgame_2flips and pre_vei (save v3, from
## about 9e25dcb): today's sim gives other contents (pre_vei's bone on its cap, its vats and clones, live stances),
## which moves 32 tests at d0a70c0. At E4 step 3, midgame_2flips and pre_vei were re-saved through the sim instead:
## from_dict of the committed file, this script's own backlog step (cmd_debug_grant, which books the ledger's debug
## source; pre_vei 1.5 K, midgame_2flips K / 3), then to_dict. A full regeneration is a later item (the manager's
## ruling at the step 3 stop).

const OUT := "res://tests/fixtures"

var _cfgs := {}


func _init() -> void:
	_cfgs = GameState.load_configs("res://configs")
	# P3b (the P3 review's should-fix 1): the fixtures are made with the Grow stance off, as TestUtil.configs() runs
	# them and as the shipped fixtures were written, so regenerating them can't turn Grow on in their saves (stances.on)
	# and move every re-pin that reads "the fixtures load with Grow off"
	_cfgs["economy"]["stance"]["grow"]["default_on"] = false
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


## Takes the (edited) save dict `d`, loads it into a fresh state and writes what that state saves, so the file survives load -> to_dict unchanged.
func _write(name: String, d: Dictionary) -> void:
	var chk := GameState.new(_cfgs)
	var r := chk.from_dict(JSON.parse_string(JSON.stringify(d)))
	_need(r, "from_dict(%s)" % name)
	var f := FileAccess.open("%s/%s.json" % [OUT, name], FileAccess.WRITE)
	if f == null:
		_fail("cannot write %s" % name)
	f.store_string(JSON.stringify(chk.to_dict(), "\t") + "\n")
	f.close()


## Puts finished buildings on lots at once: [[lot_id, building_id, level], ...]. The lot must be free
## (or hold the same building, which takes the new level) and big enough; tiers and costs are not
## checked (the town's tier rises on its own once the sim runs).
func _place(s: GameState, specs: Array) -> void:
	var sizes := {}
	for l in _cfgs["town"]["lots"]:
		sizes[str(l["id"])] = int(l["size"])
	for e in specs:
		var lot: String = e[0]
		var have: Dictionary = s.town_sim.buildings.get(lot, {})
		if not have.is_empty() and have["building_id"] != e[1]:
			_fail("%s already holds %s" % [lot, have["building_id"]])
		if int(_cfgs["buildings"][e[1]]["lot_size"]) > int(sizes.get(lot, 0)):
			_fail("%s does not fit %s" % [e[1], lot])
		if not s.town_sim.place_building(lot, e[1], int(e[2])):
			_fail("place_building%s refused" % str(e))


func _check_paid(s: GameState, what: String) -> void:
	for lot in s.town_sim.buildings:
		if s.town_sim.buildings[lot]["state"] == "unpaid":
			_fail("%s: %s is unpaid" % [what, lot])


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


## cmd_new_game(1) at t = 0: BALANCE §0 (TownSim's opening).
func _day1() -> Dictionary:
	return _new().to_dict()


## About 1 h in: a village (the start set plus a house, a well and a bone mill, all working for the
## hour), two flips, a convoy on the road, Relish leaving Covington for Greywall.
func _midgame() -> Dictionary:
	var s := _new()
	_place(s, [["lot-05", "house", 1], ["lot-06", "well", 1], ["lot-07", "bone_mill", 1]])
	_need(s.cmd_debug_skip_time(3600.0), "skip_time")
	_check_paid(s, "midgame")
	if s.town_tier != "village":
		_fail("midgame is not a Village: %s" % s.town_tier)
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
	# TownSim's convoy: haulers staffed at the Charnel House, sent to Greywall (a convoy already out
	# finishes its trip first); the store needs headroom for it to leave
	_need(s.cmd_set_haul_target("greywall"), "haul target")
	var room := s.town_sim.body_cap() - 60.0 - s.town_sim.bodies
	if room < 0.0:
		_need(s.cmd_debug_grant({"bodies": room}), "bodies headroom")
	_need(s.cmd_debug_set_state({"relish_at": "covington"}), "relish home")
	_need(s.cmd_move_relish("greywall"), "travel")
	s.tick(0.5)  # a convoy is out and Relish is on the road, both still in flight
	if (s.town_sim.haul["convoys"] as Array).size() != 1 or s.relish["state"] != "travelling":
		_fail("the convoy or the journey is not in flight: %s / %s" % [str(s.town_sim.haul), s.relish["state"]])
	# HAND-SHAPED VALUE: with the full mint an hour of continuous sim leaves Vei's backlog low (odds
	# about 0.58, close to pre_vei's 0.6), which does not look mid-game. The backlog is set to K / 3
	# (odds 0.25; 4000 at K 12000, 12M at E4 step 3's 36M) with a debug command.
	var k := float(_cfgs["realm"]["K"])
	_need(s.cmd_debug_grant({"backlog": k / 3.0 - float(s.realm.vei["undead_queue"])}), "backlog")
	var d := s.to_dict()
	# E2 field: the tithe block. The warning mirrors the tithe_warning event (§6).
	d["realm"]["tithe"] = {"warning": {"wave_id": 1, "fort_id": "ashgate", "eta_s": 150.0, "surge": 24.0}}
	return d


## About 3 h in: the start set runs 2.5 h, then a city goes up (20 buildings, Walls, a Chapel of Vats,
## the Reliquary) and runs 30 min on a gold grant that covers its upkeep; a backlog of 1.5 K (odds
## 0.6), a party of 4 on the 4 fronts, a phylactery charge and a clone, Relish at Vei.
func _pre_vei() -> Dictionary:
	var s := _new()
	_need(s.cmd_debug_skip_time(9000.0), "skip_time")
	s.blueprints.append("reliquary")  # the Reliquary's blueprint, which dungeons bank (no grant makes one)
	_place(s, [
		["lot-02", "raising_pit", 2], ["lot-04", "market", 2],
		["lot-05", "house", 1], ["lot-06", "house", 1], ["lot-07", "well", 1], ["lot-08", "bakery", 1],
		["lot-09", "bone_mill", 1], ["lot-10", "raising_pit", 2], ["lot-11", "raising_pit", 1], ["lot-12", "statue", 1],
		["lot-13", "chapel_of_vats", 1], ["lot-14", "forge", 1], ["lot-15", "inn", 1], ["lot-16", "graveyard", 1],
		["lot-17", "watchtower", 1], ["lot-18", "raising_pit", 1], ["lot-23", "walls", 1], ["lot-24", "reliquary", 1],
	])
	_need(s.cmd_debug_grant({"gold": 2500.0, "bone": 200.0}), "grant upkeep")
	_need(s.cmd_debug_skip_time(1800.0), "skip_time")
	_check_paid(s, "pre_vei")
	if s.town_tier != "city":
		_fail("pre_vei is not a City: %s" % s.town_tier)
	_need(s.cmd_debug_grant({"big_undead": 4}), "grant big undead")
	var u := _uids(s)
	_need(s.cmd_set_party(u), "party")
	for i in u.size():
		_need(s.cmd_assign_front(u[i], GameState.FRONT_IDS[i]), "front " + str(i))
	var k := float(_cfgs["realm"]["K"])
	_need(s.cmd_debug_grant({"backlog": 1.5 * k - float(s.realm.vei["undead_queue"])}), "backlog")
	_need(s.cmd_debug_set_state({"relish_at": "vei"}), "relish at Vei")
	var d := s.to_dict()
	d["backups"]["phylactery_charges"] = 1  # E3 field: no system makes a charge yet
	d["backups"]["clones_ready"] = 1  # E3 field: no system grows a clone yet
	return d
