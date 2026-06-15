extends SceneTree
## Headless: godot --headless --script res://tests/smoke_test.gd
## Parse-checks scripts, validates configs, then unit-tests the crypt systems:
## unit creation, composition, raid losses (composition-driven + ablative), and
## Vei resolution (balance wins, a shapeless mob dies). Exit 0 = green.
##
## --script runs before autoloads exist, so we add ConfigDb/GameState by hand and
## load helper classes by path. Project scripts resolve class_names via the cache.

var fails := 0
var cfg: Node
var gs: Node
var H: GDScript    # Horde
var CS: GDScript   # CombatSim
var LT: GDScript   # Loot

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame
	_ensure_autoloads()
	H = load("res://scripts/systems/horde.gd")
	CS = load("res://scripts/systems/combat_sim.gd")
	LT = load("res://scripts/systems/loot.gd")
	_test_scripts_parse()
	_test_configs()
	_test_units()
	_test_composition()
	_test_raid()
	_test_vei()
	_test_game_state()
	print("SMOKE: ALL PASS" if fails == 0 else "SMOKE: %d FAILURES" % fails)
	quit(1 if fails > 0 else 0)

func _ensure_autoloads() -> void:
	for pair in [["ConfigDb", "res://scripts/autoload/config_db.gd"],
			["GameState", "res://scripts/autoload/game_state.gd"]]:
		if root.get_node_or_null(NodePath(pair[0])) == null:
			var n: Node = (load(pair[1]) as GDScript).new()
			n.name = pair[0]
			root.add_child(n)
	cfg = root.get_node(^"ConfigDb")
	gs = root.get_node(^"GameState")

func check(cond: bool, label: String) -> void:
	if cond:
		print("  ok  %s" % label)
	else:
		fails += 1
		print("FAIL  %s" % label)

func _rem(stat: String, mag: int) -> Dictionary:
	return {"stat": stat, "magnitude": mag, "rarity": "uncommon", "echoes": [], "combat_points": 0, "town_points": 0}

# 1. Every script compiles
func _test_scripts_parse() -> void:
	print("[scripts]")
	var count := 0
	for path in _gd_files("res://scripts"):
		check(load(path) != null, path)
		count += 1
	check(count >= 9, "found %d scripts" % count)

func _gd_files(dir: String) -> Array:
	var out: Array = []
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir + "/" + f)
	for d in DirAccess.get_directories_at(dir):
		out.append_array(_gd_files(dir + "/" + d))
	return out

# 2. Configs present and shaped right
func _test_configs() -> void:
	print("[configs]")
	check(cfg.form_ids().size() == 7, "7 forms loaded (%d)" % cfg.form_ids().size())
	for k in ["start_hollows", "hollow_base_power", "champion_power_threshold"]:
		check(cfg.data["horde"].has(k), "horde.%s present" % k)
	check((cfg.data["vei"]["fronts"] as Array).size() >= 3, "vei has fronts")
	check(cfg.data["vei"].has("fronts_required"), "vei has fronts_required")
	check((cfg.data["raid"]["threats"] as Array).size() >= 3, "raid has threats")
	check((cfg.data["tags"]["presets"] as Array).size() >= 3, "tag presets present")
	check((cfg.data["missions"]["difficulties"] as Array).size() >= 2, "missions board config present")
	check(cfg.data["raid"].has("survival"), "raid survival model present")

# 3. Unit creation
func _test_units() -> void:
	print("[units]")
	var hol: Dictionary = H.make_hollow(1, "skeleton")
	check(hol["role"] == "Hollow", "a blank form is a Hollow (%s)" % hol["role"])
	check(hol["tier"] == "Hollow", "low power reads as Hollow tier")
	check(hol["aspect"] == "hollow", "a Hollow has no dominant aspect")
	var kit: Dictionary = H.make_kitted(2, "hulk", [_rem("beef", 6), _rem("wits", 4)])
	check(kit["stats"]["beef"] == 6.0 and kit["stats"]["wits"] == 4.0, "kitted sums remnant stats")
	check(float(kit["power"]) > float(hol["power"]), "a kitted unit out-powers a Hollow")
	check(kit["role"] == "Bulwark", "beef-dominant kit reads as Bulwark (%s)" % kit["role"])

# 4. Composition — the legibility payoff
func _test_composition() -> void:
	print("[composition]")
	var units := [H.make_hollow(1, "skeleton"), H.make_hollow(2, "skeleton"),
		H.make_kitted(3, "hulk", [_rem("beef", 8)])]
	var comp: Dictionary = H.composition(units)
	check(int(comp["count"]) == 3, "composition counts the army")
	check(float(comp["counter"]["beef"]) == 8.0, "composition totals counter stats")
	check(int(comp["by_role"].get("Hollow", 0)) == 2, "composition buckets by role")

# 5. Raid — composition cuts losses; the tough die LESS than the frail, but no
#    one is safe and no one is doomed (probabilistic, not weakest-by-fiat).
func _test_raid() -> void:
	print("[raid]")
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var giants := {"id": "giants", "counter_stat": "wits", "base_loss_frac": 0.20}
	var weak: Array = []
	for i in 10:
		weak.append(H.make_hollow(i + 1, "skeleton"))
	var strong: Array = weak.duplicate()
	for i in 3:
		strong.append(H.make_kitted(100 + i, "lich", [_rem("wits", 9)]))
	check(CS.raid_coverage(strong, giants) > CS.raid_coverage(weak, giants), "wits coverage cuts giant losses (%.2f > %.2f)" % [CS.raid_coverage(strong, giants), CS.raid_coverage(weak, giants)])
	# A frail Hollow vs a tough champion, many raids: the champion dies less often,
	# but more than never (it can still get out of position and fall).
	var mixed: Array = [H.make_hollow(1, "skeleton"), H.make_kitted(2, "hulk", [_rem("beef", 12), _rem("persistence", 8)])]
	var hollow_deaths := 0
	var champ_deaths := 0
	var trials := 400
	for t in trials:
		var r: Dictionary = CS.resolve_raid(mixed, giants, rng)
		if 0 in r["lost_indices"]:
			hollow_deaths += 1
		if 1 in r["lost_indices"]:
			champ_deaths += 1
	check(champ_deaths < hollow_deaths, "the tough die less than the frail (%d vs %d / %d)" % [champ_deaths, hollow_deaths, trials])
	check(champ_deaths > 0, "but even the tough can fall — not weakest-only (%d)" % champ_deaths)
	# Life steal (a combat perk) raises survivability — the sim now reads echoes.
	var plain: Dictionary = H.make_kitted(3, "skeleton", [_rem("beef", 4)])
	var lifesteal := {"stat": "beef", "magnitude": 4, "rarity": "uncommon",
		"echoes": [{"id": "life_drain", "points": 6, "side": "combat"}], "combat_points": 6, "town_points": 0}
	var thief: Dictionary = H.make_kitted(4, "skeleton", [lifesteal])
	check(CS.survivability(thief) > CS.survivability(plain), "life steal raises survivability (%.1f > %.1f)" % [CS.survivability(thief), CS.survivability(plain)])

# 6. Vei — a covering army wins, a shapeless mob dies on numbers alone
func _test_vei() -> void:
	print("[vei]")
	var balanced: Array = []
	for i in 4:
		balanced.append(H.make_kitted(i + 1, "lich", [_rem("wits", 4)]))    # 16 wits
	for i in 4:
		balanced.append(H.make_kitted(i + 10, "siren", [_rem("dread", 4)])) # 16 dread
	for i in 3:
		balanced.append(H.make_kitted(i + 20, "hulk", [_rem("beef", 7)]))   # 21 beef
	var res: Dictionary = CS.resolve_vei(balanced)
	check(res["won"], "a covering army beats Vei (met %d/%d)" % [res["met"], res["need"]])
	var mob: Array = []
	for i in 30:
		mob.append(H.make_hollow(i + 1, "skeleton"))
	var mres: Dictionary = CS.resolve_vei(mob)
	check(not mres["won"], "a shapeless mob of 30 still dies to Vei (met %d/%d)" % [mres["met"], mres["need"]])

# 7. GameState flow
func _test_game_state() -> void:
	print("[game state]")
	gs.reset()
	check(gs.horde.size() > 0, "seeded with a starting horde (%d)" % gs.horde.size())
	gs.raise_all_hollows()
	check(gs.forms.size() == 0, "raise-all turns every form into a Hollow")
	check(gs.jar_size() >= 2 and gs.mission_board.size() > 0, "jar seeded (>=2) and a mission board is rolled")
	check((gs.mission_board[0] as Dictionary).has("reward") and (gs.mission_board[0] as Dictionary).has("difficulty"), "a mission carries spoils + difficulty")
	gs.active_mission = gs.mission_board[0]
	var party: Array = []
	for u in gs.horde:
		party.append(int(u["id"]))
		if party.size() >= 3:
			break
	var delta: Dictionary = gs.raid(party)
	check(delta.has("threat") and delta.has("lost") and delta.has("party_size"), "a raid returns a delta to assess")
	check(gs.forms.size() >= 1, "raid haul refills forms")
	check(gs.active_mission.is_empty() and gs.mission_board.size() > 0, "the board re-rolls after a raid")
	var n0: int = gs.horde.size()
	gs.shred_units([gs.horde[0]["id"]])
	check(gs.horde.size() == n0 - 1 and gs.ossuary.fullness > 0.0, "shredding a unit feeds the Maw")
	var tid: String = gs.add_custom_tag("Fodder", "#b97a5a")
	gs.tag_units([gs.horde[0]["id"]], tid)
	check(tid in gs.horde[0]["tags"], "a coined tag sticks to a unit")
	gs.horde.clear()
	for i in 5:
		gs.horde.append(H.make_hollow(900 + i, "skeleton"))
	var vres: Dictionary = gs.fight_vei()
	check(not vres["won"], "a weak horde loses to Vei")
	check(gs.horde.size() > 0, "a loss wipes and reseeds a fresh start")
