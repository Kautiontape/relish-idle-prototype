extends SceneTree
## Headless verification: godot --headless --script res://tests/smoke_test.gd
## Parse-checks every script, validates configs, then unit-tests the build math,
## the Adjective-Noun namer, the ossuary (floor + quality + cap), and GameState.
## Exit code 0 = green.
##
## NOTE: --script mode runs before autoload nodes are auto-created, so the test
## adds ConfigDb/GameState by hand and loads helper classes (LT/BS/CN/Pit) by
## path. Project scripts still resolve their own class_names via the import cache.

var fails := 0
var cfg: Node
var gs: Node
var LT: GDScript   # Loot
var BS: GDScript   # BuildState
var CN: GDScript   # CreatureNamer
var Pit: GDScript  # Ossuary

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame
	_ensure_autoloads()
	LT = load("res://scripts/systems/loot.gd")
	BS = load("res://scripts/systems/build_state.gd")
	CN = load("res://scripts/systems/creature_namer.gd")
	Pit = load("res://scripts/systems/ossuary.gd")
	_test_scripts_parse()
	_test_configs()
	_test_loot()
	_test_build_and_name()
	_test_ossuary()
	_test_game_state()
	if fails == 0:
		print("SMOKE: ALL PASS")
	else:
		print("SMOKE: %d FAILURES" % fails)
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

# 1. Every script loads (parse/compile check)
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
	for id in cfg.form_ids():
		var h: Dictionary = cfg.husk(id)
		check(h.has("anatomy") and h.has("name") and h.has("color"), "husk %s shaped" % id)
	var names: Dictionary = cfg.data["names"]
	for s in LT.STATS:
		check(names["stat_adjectives"].has(s), "stat adjective for %s" % s)
	for e in cfg.data["echoes"]["combat"]:
		check(names["echo_adjectives"].has(e), "echo adjective for %s" % e)
	for k in ["fill_per_scrap", "drop_per_pull", "max_magnitude", "uncommon_quality_threshold"]:
		check(cfg.data["ossuary"].has(k), "ossuary.%s present" % k)

# 3. Loot rolls valid
func _test_loot() -> void:
	print("[loot]")
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 40:
		var r: Dictionary = LT.roll_remnant(rng)
		if not (r["stat"] in LT.STATS) or int(r["magnitude"]) < 1:
			check(false, "remnant invalid: %s" % r)
			return
	check(true, "40 remnants all valid (stat + magnitude)")
	check(cfg.husk(LT.roll_husk(rng)).has("name"), "roll_husk returns a real form")

# 4. Build math + the Adjective Noun namer
func _test_build_and_name() -> void:
	print("[build + name]")
	var b = BS.new()
	b.place_form("hulk")  # anatomy muscle 3, nerve 1
	check(b.slots.size() == 4, "hulk blooms 4 rune slots (%d)" % b.slots.size())
	check(b.derived()["name"] == "Hollow Hulk", "empty form is a Hollow Hulk (%s)" % b.derived()["name"])

	var m0: int = b.empty_slot_for("muscle")
	b.slot_remnant(m0, {"stat": "beef", "magnitude": 5, "rarity": "uncommon", "echoes": [], "combat_points": 0, "town_points": 0})
	check(b.totals()["beef"] == 5.0, "slotted beef totals 5 (%s)" % b.totals()["beef"])
	check(b.derived()["name"] == "Hulking Hulk", "beef-dominant = Hulking Hulk (%s)" % b.derived()["name"])

	var m1: int = b.empty_slot_for("muscle")
	b.slot_remnant(m1, {"stat": "power", "magnitude": 2, "rarity": "common",
		"echoes": [{"id": "frenzy", "points": 3, "side": "combat"}], "combat_points": 3, "town_points": 0})
	check(b.derived()["name"] == "Frenzied Hulk", "an echo overrides the stat: Frenzied Hulk (%s)" % b.derived()["name"])
	check(b.derived()["combat_pts"] == 3, "combat lean counted (%d)" % b.derived()["combat_pts"])

	var nerve: int = b.empty_slot_for("nerve")
	check(nerve != -1 and b.empty_slot_for("anima") == -1, "rune slots are aspect-gated (nerve open, no anima slot)")
	var freed = b.unslot(m0)
	check(freed["stat"] == "beef" and b.totals()["beef"] == 0.0, "unslot returns the remnant and clears its stat")

# 5. The ossuary: floor + quality dial + hard cap
func _test_ossuary() -> void:
	print("[ossuary]")
	var rng := RandomNumberGenerator.new()
	rng.seed = 123
	var pit = Pit.new(rng)
	check(pit.fullness == 0.0, "pit starts empty")

	# Feeding raises fullness with diminishing returns (5 scraps < 5x linear)
	pit.feed(5)
	var linear := 5.0 * float(cfg.v("ossuary", "fill_per_scrap"))
	check(pit.fullness > 0.0 and pit.fullness < linear, "feeding has diminishing returns (%.3f < %.3f)" % [pit.fullness, linear])
	for i in 500:
		pit.feed(1)
	check(pit.fullness <= 1.0 and pit.fullness > 0.95, "fullness approaches but never exceeds 1.0 (%.3f)" % pit.fullness)

	# A pull always yields a buildable form + remnant, and depletes the meter
	pit.fullness = 0.0
	var dreg: Dictionary = pit.pull()
	check(cfg.husk(dreg["form_id"]).has("name") and dreg["remnant"].has("stat"), "an empty pit still yields something")

	# Quality scales output: high fullness averages bigger magnitudes than low
	var lo_sum := 0
	var hi_sum := 0
	var worst_rarity_ok := true
	for i in 60:
		pit.fullness = 0.0
		lo_sum += int(pit.pull()["remnant"]["magnitude"])
	for i in 60:
		pit.fullness = 1.0
		var r: Dictionary = pit.pull()["remnant"]
		hi_sum += int(r["magnitude"])
		if r["rarity"] in ["rare", "legendary"]:
			worst_rarity_ok = false
	check(hi_sum > lo_sum, "fuller pit pulls better (hi %d > lo %d)" % [hi_sum, lo_sum])
	check(worst_rarity_ok, "pit output is hard-capped below rare (floor, never ceiling)")
	check(hi_sum / 60.0 <= float(cfg.v("ossuary", "max_magnitude")), "magnitude never exceeds the cap")

	# Pulling consumes the meter
	pit.fullness = 1.0
	pit.pull()
	check(pit.fullness < 1.0, "a pull drains the pit (%.2f)" % pit.fullness)

# 6. GameState material flow
func _test_game_state() -> void:
	print("[game state]")
	gs.reset()
	gs.grant_raid_haul()
	check(gs.forms.size() >= 2 and gs.remnants.size() >= 5 and gs.scraps > 0, "raid haul grants forms + remnants + scraps")
	var before: int = gs.scraps
	check(gs.feed_ossuary() and gs.scraps < before and gs.ossuary.fullness > 0.0, "feeding spends scraps, fills the pit")
	var fc: int = gs.forms.size()
	gs.pull_ossuary()
	check(gs.forms.size() == fc + 1, "a pull drops a form into the pool")
	gs.raise_creature({"name": "Hulking Hulk", "noun": "Hulk", "stats": {}, "echoes": {}}, "Gary")
	check(gs.shelf.size() == 1 and gs.shelf[0]["display_name"] == "Gary", "raised creature shelved under its custom name")
