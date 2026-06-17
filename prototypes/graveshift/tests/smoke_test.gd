extends SceneTree
## Headless: godot --headless --script res://tests/smoke_test.gd
## Parse-checks scripts, validates configs, then unit-tests the work-machine:
## roster shape, the full self-hauled chain raising Supplies, the starved-bench
## bottleneck (no quarry crew → zero output), aptitude (a brute harvests faster),
## and reset. Exit 0 = green.
##
## --script runs before autoloads exist, so we add ConfigDb by hand and load the
## sim classes by path. Project scripts resolve class_names via the cache.

var fails := 0
var cfg: Node
var S: GDScript   # Sim
var R: GDScript   # Roster

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame
	_ensure_autoloads()
	S = load("res://scripts/systems/sim.gd")
	R = load("res://scripts/systems/roster.gd")
	_test_scripts_parse()
	_test_configs()
	_test_roster()
	_test_chain()
	_test_bottleneck()
	_test_aptitude()
	_test_reset()
	print("SMOKE: ALL PASS" if fails == 0 else "SMOKE: %d FAILURES" % fails)
	quit(1 if fails > 0 else 0)

func _ensure_autoloads() -> void:
	if root.get_node_or_null(^"ConfigDb") == null:
		var n: Node = (load("res://scripts/autoload/config_db.gd") as GDScript).new()
		n.name = "ConfigDb"
		root.add_child(n)
	cfg = root.get_node(^"ConfigDb")

func check(cond: bool, label: String) -> void:
	if cond:
		print("  ok  %s" % label)
	else:
		fails += 1
		print("FAIL  %s" % label)

func _new_sim() -> Object:
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var sim: Object = S.new(rng)
	sim.setup()
	return sim

func _run_for(sim: Object, seconds: float, dt: float = 0.1) -> void:
	var steps := int(seconds / dt)
	for i in steps:
		sim.tick(dt)

# 1. Every script compiles
func _test_scripts_parse() -> void:
	print("[scripts]")
	var count := 0
	for path in _gd_files("res://scripts"):
		check(load(path) != null, path)
		count += 1
	check(count >= 5, "found %d scripts" % count)

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
	for k in ["harvest_time_s", "craft_time_s", "base_walk_px", "aptitude_strength", "quarry_aptitude_stats", "workshop_aptitude_stats"]:
		check(cfg.data["stats"].has(k), "stats.%s present" % k)
	var stations: Array = cfg.v("yard", "stations")
	check(stations.size() >= 4, "yard has stations (%d)" % stations.size())
	var kinds := {}
	for s in stations:
		kinds[s["kind"]] = true
	for k in ["quarry", "workshop", "storehouse", "pit"]:
		check(kinds.has(k), "yard has a %s" % k)
	check((cfg.v("workers", "archetypes") as Array).size() >= 2, "worker archetypes present")

# 3. Roster — every undead carries the full eight-stat line
func _test_roster() -> void:
	print("[roster]")
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var w: Dictionary = R.make_worker(1, rng)
	check(w.has("stats") and (w["stats"] as Dictionary).size() == R.STAT_KEYS.size(), "worker has 8 stats")
	check(w.has("aspect") and w.has("color") and w.has("name"), "worker has aspect/color/name")

# 4. The full chain: quarry crew + workshop crew → Supplies climbs
func _test_chain() -> void:
	print("[chain]")
	var sim := _new_sim()
	check(sim.workers.size() == int(cfg.v("workers", "start_count")), "seeded start_count workers")
	check(sim.idle_count() == sim.workers.size(), "all start idle")
	sim.assign(int(sim.workers[0]["id"]), "quarry")
	sim.assign(int(sim.workers[1]["id"]), "bench")
	_run_for(sim, 120.0)
	check(sim.supplies > 0, "a quarry+workshop pair delivers Supplies (%d)" % sim.supplies)
	check(sim.throughput_per_min() > 0.0, "throughput reads above zero")

# 5. Bottleneck: a bench with no quarry feeding it makes nothing
func _test_bottleneck() -> void:
	print("[bottleneck]")
	var sim := _new_sim()
	sim.assign(int(sim.workers[0]["id"]), "bench")   # workshop crew, NO quarry crew
	_run_for(sim, 60.0)
	check(sim.supplies == 0, "a starved workshop delivers nothing (%d)" % sim.supplies)
	check(int(sim.station_by_id("quarry")["stock"]) == 0, "and the quarry stays empty")

# 6. Aptitude: a brute out-harvests a Hollow; a tinker is the better crafter
func _test_aptitude() -> void:
	print("[aptitude]")
	var sim := _new_sim()
	var brute := {"stats": {"beef": 6, "power": 4, "wits": 0, "speed": 0}}
	var hollow := {"stats": {"beef": 1, "power": 1, "wits": 1, "speed": 1}}
	var tinker := {"stats": {"beef": 0, "power": 3, "wits": 6, "speed": 2}}
	check(sim.aptitude_mult(brute, "quarry") > sim.aptitude_mult(hollow, "quarry"), "a brute harvests faster than a Hollow")
	check(sim._harvest_time(brute) < sim._harvest_time(hollow), "higher aptitude = shorter harvest time")
	check(sim.best_station_kind(brute) == "quarry", "a brute reads best-at-quarry")
	check(sim.best_station_kind(tinker) == "workshop", "a tinker reads best-at-workshop")

# 7. Reset wipes the run
func _test_reset() -> void:
	print("[reset]")
	var sim := _new_sim()
	sim.assign(int(sim.workers[0]["id"]), "quarry")
	sim.assign(int(sim.workers[1]["id"]), "bench")
	_run_for(sim, 60.0)
	sim.reset()
	check(sim.supplies == 0, "reset zeroes Supplies")
	check(sim.idle_count() == sim.workers.size(), "reset sends everyone idle again")
