extends SceneTree
## Headless verification: godot --headless --script res://tests/smoke_test.gd
## Parse-checks every script, validates configs, unit-tests scoring/loot/
## factory math, then boots the real raid and simulates a trance summon, a
## lasso command, the sacrifice chain, and a kill. Exit code 0 = green.
##
## NOTE: --script mode compiles before autoload globals are registered, so the
## test resolves singletons (Cfg/GS/Factory) and classes (CS/LT/US) by path.

var fails := 0
var cfg: Node
var gs: Node
var factory: Node
var CS: GDScript  # CircleScorer
var LT: GDScript  # Loot
var US: GDScript  # RRUnit

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame
	_ensure_autoloads()
	CS = load("res://scripts/systems/circle_scorer.gd")
	LT = load("res://scripts/systems/loot.gd")
	US = load("res://scripts/entities/unit.gd")
	_test_scripts_parse()
	_test_configs()
	_test_circle_scorer()
	_test_loot()
	_test_factory()
	await _test_raid_boot()
	if fails == 0:
		print("SMOKE: ALL PASS")
	else:
		print("SMOKE: %d FAILURES" % fails)
	quit(1 if fails > 0 else 0)

func _ensure_autoloads() -> void:
	for pair in [["ConfigDb", "res://scripts/autoload/config_db.gd"],
			["GameState", "res://scripts/autoload/game_state.gd"],
			["EntityFactory", "res://scripts/autoload/entity_factory.gd"]]:
		if root.get_node_or_null(NodePath(pair[0])) == null:
			var n: Node = (load(pair[1]) as GDScript).new()
			n.name = pair[0]
			root.add_child(n)
	cfg = root.get_node(^"ConfigDb")
	gs = root.get_node(^"GameState")
	factory = root.get_node(^"EntityFactory")

func _wait_for_chaff(bf: Node2D, chaff_kind: int, target: int, max_frames: int) -> bool:
	for i in max_frames:
		if bf.count_kind(chaff_kind) >= target:
			return true
		await physics_frame
	return bf.count_kind(chaff_kind) >= target

func check(cond: bool, label: String) -> void:
	if cond:
		print("  ok  %s" % label)
	else:
		fails += 1
		print("FAIL  %s" % label)

# 1. Every script must load (parse/compile check)
func _test_scripts_parse() -> void:
	print("[scripts]")
	var count := 0
	for path in _gd_files("res://scripts"):
		var s: Variant = load(path)
		check(s != null, path)
		count += 1
	check(count >= 20, "found %d scripts" % count)

func _gd_files(dir: String) -> Array:
	var out: Array = []
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir + "/" + f)
	for d in DirAccess.get_directories_at(dir):
		out.append_array(_gd_files(dir + "/" + d))
	return out

# 2. Configs: §11 keys present, cross-references valid
func _test_configs() -> void:
	print("[configs]")
	for key in ["hp_per_beef", "dmg_per_power", "speed_per_speed", "size_per_beef",
			"wits_lock_threshold", "wits_antibeef_coeff", "field_radius_px", "field_strength",
			"field_bias_clamp", "magic_bolt_dmg_per_magic", "magic_bolt_range_px",
			"persistence_rise_per_point", "persistence_rise_cap", "sacrifice_iframes_s",
			"chaff_base_power", "chaff_base_beef", "chaff_base_speed"]:
		check(cfg.data["stats"].has(key), "stats.%s" % key)
	for key in ["trance_time_scale", "trance_max_hold_s", "summon_cooldown_s",
			"essence_lifetime_s", "selection_expiry_s", "jar_slots"]:
		check(cfg.data["timers"].has(key), "timers.%s" % key)
	check(float(cfg.v("timers", "essence_lifetime_s")) > float(cfg.v("timers", "summon_cooldown_s")),
		"essence lifetime comfortably above summon cooldown (§13.5)")
	check(cfg.data["husks"].size() == 7, "7 husks (got %d)" % cfg.data["husks"].size())
	var chambers: Array = cfg.chambers_sorted()
	check(chambers.size() == 6, "6 chambers (5 + climax)")
	for c in chambers:
		for grp in c["spawns"]:
			check(cfg.data["enemies"].has(grp["type"]), "chamber %s enemy '%s' exists" % [c["name"], grp["type"]])
	check(bool(chambers[chambers.size() - 1].get("climax", false)), "last chamber is the climax")
	# loadout fits anatomy & echo ids exist
	var aspect_of: Dictionary = LT.ASPECT_OF_STAT
	for spec in cfg.data["loadout"]["permanents"]:
		var husk: Dictionary = cfg.husk(spec["husk"])
		var used := {"muscle": 0, "nerve": 0, "presence": 0, "anima": 0}
		for r in spec["remnants"]:
			used[aspect_of[r["stat"]]] += 1
			for e in r.get("echoes", []):
				var id: String = e["id"]
				check(cfg.data["echoes"]["combat"].has(id) or cfg.data["echoes"]["town"].has(id),
					"echo '%s' exists" % id)
		for a in used:
			check(used[a] <= int(husk["anatomy"][a]), "%s: %s hollows fit (%d <= %d)" % [spec["name"], a, used[a], husk["anatomy"][a]])

# 3. Circle scorer: grading must rank perfect > noisy > half-arc > line
func _test_circle_scorer() -> void:
	print("[circle scorer]")
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	var center := Vector2(100, -400)
	var perfect := PackedVector2Array()
	for i in 64:
		perfect.append(center + Vector2(120, 0).rotated(TAU * i / 64.0))
	var noisy := PackedVector2Array()
	for i in 64:
		noisy.append(center + Vector2(120 + rng.randf_range(-18, 18), 0).rotated(TAU * i / 64.0))
	var arc := PackedVector2Array()
	for i in 32:
		arc.append(center + Vector2(120, 0).rotated(PI * i / 31.0))
	var line := PackedVector2Array()
	for i in 40:
		line.append(Vector2(i * 8.0, i * 8.0))
	var sp: int = CS.grade(perfect)["score"]
	var sn: int = CS.grade(noisy)["score"]
	var sa: int = CS.grade(arc)["score"]
	var sl: int = CS.grade(line)["score"]
	print("  scores: perfect=%d noisy=%d arc=%d line=%d" % [sp, sn, sa, sl])
	check(sp >= 90, "perfect circle >= 90")
	check(sn < sp and sn > 35, "noisy circle between 35 and perfect")
	check(sa < sn and sa < 45, "half arc graded low")
	check(sl < 15, "straight line graded ~0")
	check(absf(CS.multiplier(100) - 1.5) < 0.001, "multiplier(100) = 1.5")
	check(absf(CS.multiplier(0) - 0.5) < 0.001, "multiplier(0) = 0.5")

# 4. Loot: rarity weights honored, magnitudes in range, echo budget exact
func _test_loot() -> void:
	print("[loot]")
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var counts := {"common": 0, "uncommon": 0, "rare": 0, "legendary": 0}
	var budget_ok := true
	var mag_ok := true
	var n := 3000
	for i in n:
		var r: Dictionary = LT.roll_remnant(rng)
		counts[r["rarity"]] += 1
		var mag_range: Array = cfg.data["rarity"]["magnitude"][r["rarity"]]
		if r["magnitude"] < int(mag_range[0]) or r["magnitude"] > int(mag_range[1]):
			mag_ok = false
		var pts := 0
		for e in r["echoes"]:
			pts += int(e["points"])
		if pts != int(cfg.data["rarity"]["echo_budget"][r["rarity"]]):
			budget_ok = false
	print("  rarity counts: %s" % str(counts))
	check(absf(counts["common"] / float(n) - 0.70) < 0.05, "common ~70%")
	check(counts["legendary"] > 0, "legendary occurs")
	check(mag_ok, "magnitudes within rarity ranges")
	check(budget_ok, "echo points spend the budget exactly")

# 5. Factory: derived stats follow §11 formulas
func _test_factory() -> void:
	print("[factory]")
	for id in cfg.data["enemies"]:
		var e: Node = factory.make_enemy(id)
		check(e != null and e.max_hp > 0, "enemy %s builds" % id)
		e.free()
	var squad: Array = factory.default_loadout()
	check(squad.size() == int(cfg.v("timers", "jar_slots")), "loadout fills the jar (5)")
	var bulwark: Node = squad[0]
	check(absf(bulwark.max_hp - (20.0 + 10.0 * 7.0)) < 0.001, "Bulwark HP = base 20 + 10×Beef7 = 90 (got %.0f)" % bulwark.max_hp)
	check(absf(bulwark.damage() - (2.0 + 2.0 * 2.0)) < 0.001, "Bulwark dmg = 2 + 2×Power2 = 6")
	check(absf(bulwark.size_scale() - (1.0 + 0.15 * 7.0)) < 0.001, "Bulwark size = 1 + 0.15×Beef7")
	var fang: Node = squad[1]
	check(fang.stats.wits >= 3.0 and fang.stats.magic > 0.0, "Fang has wits lock + magic bolt")
	for u in squad:
		u.free()
	var chaff: Node = factory.make_chaff(1.5)
	check(absf(chaff.stats.power - 3.0) < 0.001 and absf(chaff.stats.speed - 4.5) < 0.001, "chaff = base × 1.5 multiplier")
	chaff.free()

# 6. Boot the real game, run the raid, simulate the core verbs
func _test_raid_boot() -> void:
	print("[raid boot]")
	var main_scene: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main_scene)
	await process_frame
	check(main_scene.hud != null and main_scene.hud.screens_open(), "menu shows")
	main_scene.start_raid()
	for i in 10:
		await physics_frame
	var bf: Node2D = main_scene.mode.battlefield
	check(bf != null, "battlefield exists")
	check(bf.relish != null and bf.relish.alive, "relish spawned")
	check(bf.nav_region.navigation_polygon.get_polygon_count() > 0, "navmesh baked (%d polys)" % bf.nav_region.navigation_polygon.get_polygon_count())
	var enemy_faction: int = US.Faction.ENEMY
	var player_faction: int = US.Faction.PLAYER
	var chaff_kind: int = US.Kind.CHAFF
	var enemies: int = bf.living(enemy_faction).size()
	var inactive := 0
	for u in bf.all_units():
		if u.faction == enemy_faction and not u.active:
			inactive += 1
	print("  enemies targetable now: %d, dormant in later chambers: %d" % [enemies, inactive])
	check(enemies + inactive == 55, "all 55 authored enemies spawned (got %d)" % (enemies + inactive))
	check(inactive == 49, "only chamber 1 active at start")
	check(bf.living(player_faction).size() == 6, "relish + 5 permanents")

	# Regression: the FIRST input of a run is a swipe on Relish — she must move.
	# NavigationAgent2D sits dormant (velocity_computed never fires) until a
	# target is submitted once; her raw path_override velocities never submit
	# one, so she froze until a tap's order_move woke the agent.
	var rel0: Node = bf.relish
	var spawn0: Vector2 = rel0.global_position
	var ct0: Transform2D = bf.get_viewport().get_canvas_transform()
	var sw := InputEventScreenTouch.new()
	sw.pressed = true
	sw.position = ct0 * spawn0
	main_scene._unhandled_input(sw)
	check(main_scene.mode.command._mode == 2, "first-input press on Relish grabs her")  # Mode.RELISH
	for i in range(1, 6):
		var dr := InputEventScreenDrag.new()
		dr.position = ct0 * (spawn0 + Vector2(0, -36.0 * i))
		main_scene._unhandled_input(dr)
		await physics_frame
	var sw_up := InputEventScreenTouch.new()
	sw_up.pressed = false
	sw_up.position = ct0 * (spawn0 + Vector2(0, -180))
	main_scene._unhandled_input(sw_up)
	var swiped := false
	for i in 90:
		await physics_frame
		if rel0.global_position.distance_to(spawn0) > 40.0:
			swiped = true
			break
	check(swiped, "first-input swipe moves her (agent live from frame one)")
	rel0.path_override.clear()
	rel0.global_position = spawn0
	gs.command_touches = 0  # don't skew the counts the later checks expect
	await physics_frame

	# Trance summon: button → trace a circle around essence → chaff
	var trance: Node = main_scene.mode.trance
	var spot: Vector2 = bf.relish.global_position + Vector2(0, -80)
	bf.spawn_essence(spot, 3)
	await physics_frame
	trance.button_down()
	check(trance.state == 1, "trance active on hold")  # State.ACTIVE
	check(absf(Engine.time_scale - float(cfg.v("timers", "trance_time_scale"))) < 0.001, "world time dilated ×0.35")
	var trace := PackedVector2Array()
	for i in 48:
		trace.append(spot + Vector2(90, 0).rotated(TAU * i / 48.0))
	trance.trace = trace
	trance._finish_trace()
	check(gs.trance_summons == 1, "summon counted")
	check(gs.circle_scores.size() == 1 and gs.circle_scores[0] >= 85, "clean circle scored high (%d)" % gs.circle_scores[0])
	# Essence flies to Relish first (fwwwwooomp), then the chaff grows beside her.
	var grew := await _wait_for_chaff(bf, chaff_kind, 3, 240)
	check(grew, "3 essence absorbed → 3 chaff grew beside Relish (got %d)" % bf.count_kind(chaff_kind))
	check(trance.state == 2, "summon ends trance → cooldown")  # State.COOLDOWN
	check(absf(Engine.time_scale - 1.0) < 0.001, "time scale restored")

	# Command grammar: lasso the squad, send them
	var command: Node = main_scene.mode.command
	var centroid: Vector2 = bf.player_minion_centroid()
	var lasso := PackedVector2Array()
	for i in 24:
		lasso.append(centroid + Vector2(260, 0).rotated(TAU * i / 24.0))
	command._stroke = lasso
	command._handle_lasso()
	check(command.selection.size() >= 5, "lasso selected the squad (%d)" % command.selection.size())
	command._handle_tap(centroid + Vector2(0, -150))
	check(gs.command_touches == 2, "lasso + send = 2 command touches")
	var moved := 0
	for u in bf.living(player_faction):
		if u.cmd == 1:  # Cmd.MOVE
			moved += 1
	check(moved >= 5, "selected units took the move order")

	# Sacrifice chain: chaff dies in her place
	var chaff_before: int = bf.count_kind(chaff_kind)
	bf.relish_hit(null)
	await physics_frame
	check(bf.count_kind(chaff_kind) == chaff_before - 1, "nearest chaff died in Relish's place")
	check(bf.relish.alive, "relish survived")

	# Kill an enemy: drops flow
	var kills_before: int = gs.kills
	var essence_before: int = gs.essence_dropped
	var victim: Node = bf.living(enemy_faction)[0]
	victim.take_hit(null, 99999.0)
	check(gs.kills == kills_before + 1, "kill counted")
	check(gs.essence_dropped > essence_before, "kill dropped essence")

	# Run combat for a while; nothing should crash
	for i in 240:
		await physics_frame
	check(true, "240 physics frames of live combat without crashing")

	# RMB trance: right-mouse drag = hold + trace, through the real input routing
	trance.state = 0  # force READY (skip cooldown)
	trance.cooldown_left = 0.0
	var spot2: Vector2 = bf.relish.global_position + Vector2(110, -50)
	bf.spawn_essence(spot2, 2)
	await physics_frame
	var ct := bf.get_viewport().get_canvas_transform()
	var chaff_b4: int = bf.count_kind(chaff_kind)
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_RIGHT
	down.pressed = true
	down.position = ct * (spot2 + Vector2(75, 0))
	main_scene._unhandled_input(down)
	check(trance.state == 1, "RMB press enters trance")
	for i in range(1, 33):
		var mm := InputEventMouseMotion.new()
		mm.position = ct * (spot2 + Vector2(75, 0).rotated(TAU * i / 32.0))
		main_scene._unhandled_input(mm)
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_RIGHT
	up.pressed = false
	up.position = down.position
	main_scene._unhandled_input(up)
	check(gs.trance_summons == 2, "RMB release summoned (summons=%d)" % gs.trance_summons)
	var grew2 := await _wait_for_chaff(bf, chaff_kind, chaff_b4 + 2, 240)
	check(grew2, "RMB circle raised 2 chaff (have %d, wanted %d)" % [bf.count_kind(chaff_kind), chaff_b4 + 2])
	check(trance.state == 2 and absf(Engine.time_scale - 1.0) < 0.001, "RMB trance ended → cooldown")

	# Escort: when Relish heads for a door, idle minions take point toward it.
	# Staged deterministically: quiet the field, park her mid-room, send her
	# at the nearest door, and poll (combat RNG must not decide this test).
	for u in bf.living(enemy_faction):
		u.take_hit(null, 99999.0)
	await physics_frame
	var rd: Node = main_scene.mode
	bf.relish.global_position = rd._rooms[rd.current]["center"]
	bf.relish.path_override.clear()
	var door_pos: Vector2 = bf.doorways[0]
	for d in bf.doorways:
		if d.distance_to(bf.relish.global_position) < door_pos.distance_to(bf.relish.global_position):
			door_pos = d
	bf.relish.order_move(door_pos)
	var door_goal := Vector2.INF
	for i in 120:
		await physics_frame
		door_goal = bf.escort_door_goal()
		if door_goal != Vector2.INF:
			break
	check(door_goal != Vector2.INF, "relish heading reveals the door")
	check(door_goal.distance_to(door_pos) < 220.0, "escort goal is that door (+through offset)")
	for i in 30:
		await physics_frame
	var escorting := 0
	for u in bf.living(player_faction):
		if u.kind != US.Kind.RELISH and u.cmd == 0 and u._nav_goal != Vector2.INF \
				and u._nav_goal.distance_to(door_goal) < 260.0:
			escorting += 1
	check(escorting >= 3, "%d idle minions taking point to the door" % escorting)

	# Obstacle room: carved navmesh + the lasso-then-drag path grammar
	main_scene.start_playroom("obstacles")
	for i in 5:
		await physics_frame
	var bf2: Node2D = main_scene.mode.battlefield
	check(bf2.nav_region.navigation_polygon.get_polygon_count() >= 8,
		"obstacle navmesh carved (%d polys)" % bf2.nav_region.navigation_polygon.get_polygon_count())
	check(bf2.obstacles.size() == 5, "5 obstacles drawn")
	var cc: Node = main_scene.mode.command
	var c2: Vector2 = bf2.player_minion_centroid()
	cc._press(c2 + Vector2(170, 0))
	for i in range(1, 37):
		cc._move(c2 + Vector2(170, 0).rotated(TAU * i / 36.0))
	check(cc.selection.size() >= 5, "mid-stroke lasso selected the squad (%d)" % cc.selection.size())
	check(cc._mode == 1, "stroke flipped to PATH mode")  # Mode.PATH
	cc._move(c2 + Vector2(170, -40.0))
	check(not cc._path_begun, "path waits until the drag pulls away from the loop")
	for i in range(2, 7):
		cc._move(c2 + Vector2(170, -40.0 * i))
	check(cc._path_begun, "path begins past the pull-away threshold")
	cc._release()
	var pathing := 0
	for u in bf2.living(player_faction):
		if u.cmd == 3 and u.cmd_path.size() > 0:  # Cmd.PATH
			pathing += 1
	check(pathing >= 5, "squad follows the drawn path (%d units)" % pathing)
	check(gs.command_touches == 1, "lasso+path = ONE command touch")
	for i in 60:
		await physics_frame
	# Esc clears a fresh selection
	var lasso2 := PackedVector2Array()
	for i in 20:
		lasso2.append(c2 + Vector2(220, 0).rotated(TAU * i / 20.0))
	cc._stroke = lasso2
	cc._handle_lasso()
	check(cc.selection.size() > 0, "release-lasso still selects")
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	cc.handle_input(esc)
	check(cc.selection.is_empty(), "Esc clears the selection")

	# Fresh room: seal-anywhere lasso (stroke crosses ITSELF, not at its start)
	main_scene.start_playroom("obstacles")
	for i in 5:
		await physics_frame
	var bf3: Node2D = main_scene.mode.battlefield
	var cc3: Node = main_scene.mode.command
	var c3: Vector2 = bf3.player_minion_centroid()
	var rho := [Vector2(250, 250), Vector2(200, 200), Vector2(150, 150),
		Vector2(-15, 150), Vector2(-180, 150), Vector2(-180, 0), Vector2(-180, -180),
		Vector2(0, -180), Vector2(180, -180), Vector2(180, 25), Vector2(180, 230)]
	cc3._press(c3 + rho[0])
	for i in range(1, rho.size()):
		cc3._move(c3 + rho[i])
	check(cc3.selection.size() >= 4, "self-crossing loop sealed away from its start (%d selected)" % cc3.selection.size())
	cc3._move(c3 + Vector2(180, 330))
	cc3._move(c3 + Vector2(180, 420))
	cc3._move(c3 + Vector2(180, 500))
	cc3._release()
	var pathing3 := 0
	for u in bf3.living(player_faction):
		if u.cmd == 3:  # Cmd.PATH
			pathing3 += 1
	check(pathing3 >= 4, "rho-lasso squad follows the tail (%d)" % pathing3)
	# Tap on Relish clears a selection; then a ground tap moves HER again
	var lasso3 := PackedVector2Array()
	for i in 20:
		lasso3.append(c3 + Vector2(260, 0).rotated(TAU * i / 20.0))
	cc3._stroke = lasso3
	cc3._handle_lasso()
	check(cc3.selection.size() > 0, "re-lassoed for the relish-tap test")
	cc3._press(bf3.relish.global_position)
	cc3._release()
	check(cc3.selection.is_empty(), "tapping Relish clears the selection")
	cc3._press(bf3.relish.global_position + Vector2(0, -200))
	cc3._release()
	check(bf3.relish.cmd == 1, "ground tap moves Relish after commands")  # Cmd.MOVE

	# Relish pushes her minions out of the way — she gets priority when moving
	var rel3: Node = bf3.relish
	check(rel3.nav.avoidance_mask == 4 and rel3.nav.avoidance_priority == 1.0, "relish avoidance ignores minions, top priority")
	var blockers: Array = []
	rel3.global_position = main_scene.mode.room_point(0.25, 0.5)
	for i in 3:
		var b: Node = factory.make_chaff(1.0)
		bf3.spawn_unit(b, main_scene.mode.room_point(0.25, 0.55 + 0.025 * i))
		blockers.append(b)
	check(blockers[0].nav.avoidance_mask & 2 == 2 and blockers[0].nav.avoidance_priority < 1.0, "minions avoid relish at lower priority")
	rel3.velocity = Vector2(0, 60)
	blockers[0].global_position = rel3.global_position + Vector2(0, 20)
	check(blockers[0]._relish_push().length() > 0.0, "overlapping minion gets the bow-wave shove")
	var push_goal: Vector2 = main_scene.mode.room_point(0.25, 0.72)
	rel3.order_move(push_goal)
	for i in 260:
		await physics_frame
		if rel3.global_position.distance_to(push_goal) < 70.0:
			break
	check(rel3.global_position.distance_to(push_goal) < 70.0, "relish plowed through the clump to her goal")

	# Open-swipe fallback: a long stroke that starts nowhere near her and never
	# closes still belongs to her — the drawn line becomes her path.
	var touches_b4: int = gs.command_touches
	var far: Vector2 = rel3.global_position + Vector2(220, 0)
	cc3._press(far)
	check(cc3._mode == 0, "far press classifies (not a Relish grab)")  # Mode.CLASSIFY
	for i in range(1, 7):
		cc3._move(far + Vector2(0, -50.0 * i))
	cc3._release()
	check(rel3.cmd == 0 and rel3.path_override.size() >= 3,
		"open swipe becomes her path (%d pts)" % rel3.path_override.size())
	check(gs.command_touches == touches_b4 + 1, "open swipe counts one command touch")
	rel3.path_override.clear()

	main_scene.show_menu()
	await process_frame
	main_scene.queue_free()
	await process_frame
