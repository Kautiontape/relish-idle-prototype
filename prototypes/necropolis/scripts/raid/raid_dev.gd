class_name RaidDev
extends RefCounted
## Standalone dev harness for the raid scene, created only when the scene is launched directly:
##   godot --path . res://scenes/raid/Raid.tscn -- --new-game --raid-fixture=day1,old-sluice
## Flags: --raid-fixture=<fixture>,<fort_id> (needs --new-game: all worktrees share user://),
## --raid-stress=N, --raid-perf, --raid-autoexit=<frames>, --raid-autodie=<frames>,
## --raid-held-shot=<png> (with --raid-held and the autopilot: a screenshot 0.3 s into the clear set piece), --raid-motes=N, --raid-trance-hold (open the trance at start), --raid-held, --raid-warden (Relish starts in the antechamber),
## --raid-archetype=<id> (demo seed's warden), --raid-big-speed=<n> (demo party big undead),
## --raid-ding-chance=<p> (every tier's ding chance, to see dings), --raid-warden-go (with it: Relish walks into the warden room, then to the chest),
## --raid-autopilot=<score> [--raid-autopilot-seed=<n>] [--raid-autopilot-dodge=<0..1>] (RaidAutopilot: plays the raid headless, prints AUTOPILOT_RESULT, quits),
## --raid-profile=<party_tier> --raid-fort=<fort_id> (BALANCE 3's standard party of that tier at that world.json fort; raid.json autopilot.party_profiles).
## A RefCounted, not a Node: the raid calls `start()` once the scene is built and `tick()` from
## its own _process, so it needs no tree presence of its own.

var _raid: Node2D
var _stress := 0                # --raid-stress=N
var _autoexit := -1             # --raid-autoexit=<frames>
var _autodie := -1              # --raid-autodie=<frames>
var _go := false                # --raid-warden-go autopilot
var _ap: RaidAutopilot = null   # --raid-autopilot=<score>: the headless measuring bot
var _perf := false
var _perf_cpu: Array = []
var _perf_gpu: Array = []
var _perf_done := false
var _perf_last := 0
var _perf_parts := [0.0, 0.0]   # summed TIME_PROCESS / TIME_PHYSICS_PROCESS monitors, ms


func _init(p_raid: Node2D) -> void:
	_raid = p_raid


static func cli_value(prefix: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with(prefix):
			return a.trim_prefix(prefix)
	return ""


static func cli_flag(flag: String) -> bool:
	return flag in OS.get_cmdline_user_args()


## `--raid-fixture=<fixture>,<fort_id>` goes through commands only. Returns the router-style
## setup args, or {} when the flag is absent or refused.
static func fixture_seed() -> Dictionary:
	var spec := cli_value("--raid-fixture=")
	if spec != "" and Game.autosave_enabled:
		push_error("RAID_DEV --raid-fixture needs --new-game (harness session)")
		print("RAID_DEV --raid-fixture needs --new-game (harness session)")
		return {}
	if spec == "":
		return {}
	var parts := spec.split(",")
	if parts.size() != 2:
		print("RAID_DEV refused: --raid-fixture wants <fixture>,<fort_id>")
		return {}
	var fort_id := parts[1]
	var st: GameState = Game.state
	var r := st.cmd_debug_load_fixture(parts[0])
	if not r["ok"]:
		print("RAID_DEV refused: load_fixture %s -> %s" % [parts[0], r["reason"]])
		return {}
	r = st.cmd_debug_set_state({"relish_at": fort_id})
	if not r["ok"]:
		print("RAID_DEV refused: set_state relish_at=%s -> %s" % [fort_id, r["reason"]])
		return {}
	r = st.cmd_begin_dungeon(fort_id)
	if not r["ok"]:
		print("RAID_DEV refused: begin_dungeon %s -> %s" % [fort_id, r["reason"]])
		return {}
	var sd: Dictionary = r["seed"]
	print("RAID_DEV seed issued fort=%s run_id=%d seed_rev=%d tier=%d starter_units=%d garrison_units=%d party=%d" % [
		fort_id, int(r["run_id"]), int(r["seed_rev"]), int(sd["fort"]["tier"]),
		int(sd["starter_units"]), int(sd["garrison_units"]), sd["party"].size()])
	return {"mode": "dungeon", "fort_id": fort_id, "run_id": r["run_id"], "seed_rev": r["seed_rev"]}


## `--raid-profile=<party_tier> --raid-fort=<fort_id>` (DEV, BALANCE 3's measuring runs): the standard
## party of that tier against that world.json fort (RaidLogic.profile_seed). {} when absent or refused.
static func profile_seed(cfg: Dictionary) -> Dictionary:
	var tier_s := cli_value("--raid-profile=")
	var fid := cli_value("--raid-fort=")
	if tier_s == "" and fid == "":
		return {}
	if tier_s == "" or fid == "":
		print("RAID_DEV refused: --raid-profile=<party_tier> and --raid-fort=<fort_id> go together")
		return {}
	for f in ConfigDb.data.get("world", {}).get("forts", []):
		if str(f.get("id", "")) == fid:
			var sd := RaidLogic.profile_seed(f, int(tier_s), cfg)
			print("RAID_DEV profile seed fort=%s tier=%d party_tier=%d living=%.1f dead=%.1f garrison_units=%d party=%d warden=%s" % [
				fid, int(sd["fort"]["tier"]), int(tier_s), float(sd["living"]), float(sd["dead"]),
				int(sd["garrison_units"]), (sd["party"] as Array).size(), str(sd["warden"]["archetype"])])
			return sd
	print("RAID_DEV refused: --raid-fort=%s is not a world.json fort" % fid)
	return {}


## Standalone demo seed overrides: `--raid-archetype=<id>` swaps the warden archetype and
## `--raid-big-speed=<n>` sets the party big undead's speed stat (to test the Huntsman's intercept).
static func apply_demo_overrides(sd: Dictionary) -> void:
	var arche := cli_value("--raid-archetype=")
	if arche != "":
		sd["warden"]["archetype"] = arche
		sd["loot_table_id"] = "t%d.%s" % [int(sd["warden"].get("tier", 1)), arche]
	var spd := cli_value("--raid-big-speed=")
	if spd != "":
		for e in sd.get("party", []):
			e["stats"]["speed"] = float(spd)


## Hook 1: the scene is built. Reads the dev flags and spawns the stress / mote setups.
func start() -> void:
	_stress = int(cli_value("--raid-stress="))
	_autoexit = int(cli_value("--raid-autoexit=")) if cli_value("--raid-autoexit=") != "" else -1
	_autodie = int(cli_value("--raid-autodie=")) if cli_value("--raid-autodie=") != "" else -1
	if cli_flag("--raid-warden") and not _raid.is_boss():
		_place_in_antechamber()
	_go = cli_flag("--raid-warden-go")
	if RaidAutopilot.enabled() and not _raid.is_boss():
		_ap = RaidAutopilot.new(_raid)
		_ap.start()
	if cli_flag("--raid-trance-hold") and not _raid.is_boss():
		_raid.trance._button_down()   # open the trance and keep it open (the ghost-ring shot)
	if cli_value("--raid-ding-chance=") != "":
		var by_tier: Dictionary = ConfigDb.data["loot"]["ding"]["chance_by_tier"]
		for k in by_tier.keys():
			by_tier[k] = float(cli_value("--raid-ding-chance="))
	if _stress > 0 and not _raid.is_boss():
		_spawn_stress(_stress)
	var motes := int(cli_value("--raid-motes=")) if cli_value("--raid-motes=") != "" else 0
	if motes > 0 and not _raid.is_boss():
		_spawn_dev_motes(motes)
	if cli_flag("--raid-perf"):
		_perf = true
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		RenderingServer.viewport_set_measure_render_time(_raid.get_viewport().get_viewport_rid(), true)


## Hook 2: every frame of the scene's _process.
func tick() -> void:
	var frame := Engine.get_process_frames()
	if _autoexit >= 0 and frame >= _autoexit and not _raid._ended:
		_autoexit = -1
		_raid.confirm_exit()
	if _autodie > 0 and frame % _autodie == 0 and not _raid._ended and not _raid.is_boss():
		_autodie_hit()
	if _perf:
		_perf_sample(frame)
	if _go and not _raid._ended:
		_autopilot()


## Hook 3: every physics frame of a live run (the measuring bot's think step).
func physics_tick(delta: float) -> void:
	if _ap != null:
		_ap.physics_tick(delta)


## Hook 4: the run ended (RaidEndings.finish); the bot prints its result line and quits.
func on_finish(result: Dictionary) -> void:
	if _ap != null:
		_ap.on_finish(result)


## --raid-warden: Relish starts at the centre of the antechamber (nothing without one: held, boss).
func _place_in_antechamber() -> void:
	var ar := int(_raid.layout.get("ante_room", -1))
	if ar < 0:
		print("RAID_DEV --raid-warden: this layout has no antechamber")
		return
	var rel: RaidRelish = _raid.relish
	var from := rel.position
	rel.position = _raid.resolve_walls((_raid.layout["rooms"][ar] as Rect2).get_center(), rel.radius)
	for a in _raid.allies:   # the garrison, starters and party come along
		a.position = _raid.resolve_walls(a.position + (rel.position - from), a.radius)
	rel.move_target = rel.position
	_raid._cam_follow()
	_raid.cam.reset_smoothing()


## --raid-warden-go: walk to the warden room's near edge, then the chest once it exists.
func _autopilot() -> void:
	var wr := int(_raid.layout.get("warden_room", -1))
	if wr < 0:
		return
	var run: RaidWardenRun = _raid.warden_run
	if run.chest != null and is_instance_valid(run.chest):
		_raid.relish.move_target = run.chest.global_position
	elif run.warden != null and is_instance_valid(run.warden) and not run.warden.awake:
		var room: Rect2 = _raid.layout["rooms"][wr]
		var c := room.get_center()
		var from: Vector2 = _raid.relish.position
		# a point 80px inside the room towards where Relish stands
		_raid.relish.move_target = c + (from - c).normalized() * minf(room.size.x, room.size.y) * 0.3


## Kill every ally and deal Relish a lethal hit (a revive, then the run's end).
func _autodie_hit() -> void:
	for a in _raid.allies.duplicate():
		if is_instance_valid(a) and a.alive:
			a.die(true)
	_raid.relish.take_hit(_raid.relish.max_hp + 1000.0)


## N fresh motes (mass 1) around Relish.
func _spawn_dev_motes(n: int) -> void:
	for i in n:
		var ang := TAU * i / float(n) + 0.3
		var pos: Vector2 = _raid.relish.position + Vector2(46.0 + 12.0 * (i % 3), 0).rotated(ang)
		_raid.spawn_mote(_raid.resolve_walls(pos, 6.0), 1.0, false)


## Perf harness: N soldier-tier raised undead in rings around Relish, enemies topped up to the cap.
func _spawn_stress(n: int) -> void:
	var cfg: Dictionary = _raid.rcfg()
	var mult := RaidLogic.stat_mult(75, ConfigDb.data.get("circle", {}))
	var tier := RaidLogic.score_class(75, cfg)
	var stats := RaidLogic.undead_stats(mult, tier, cfg)
	var made := 0
	var ring := 0
	while made < n:
		var r := 70.0 + 30.0 * ring
		var cap_n := maxi(6, int(TAU * r / 26.0))
		for i in mini(cap_n, n - made):
			var ang := TAU * i / float(cap_n) + ring * 0.5
			var pos: Vector2 = _raid.relish.position + Vector2(r, 0).rotated(ang)
			_raid.spawn_ally_v2("raised", tier, mult, 0.0, "", stats, _raid.resolve_walls(pos, 10.0))
			made += 1
		ring += 1
	var extra: int = int(cfg.get("mass", {}).get("enemy_max", 34)) - _raid.enemies.size()
	if extra > 0:
		var fid := str(_raid.seed_data.get("fort", {}).get("id", "fort"))
		var spots := RaidLogic.populate_enemies(fid + "-stress", _raid.layout, extra, _raid.fort_tier(), cfg)
		for sp in spots:
			var u: RaidUnit = _raid.spawn_unit("enemy", sp["kind"], sp["pos"])
			u.mass = 1.0
			u.home_room = _raid.layout["rooms"][sp["room"]]


func _perf_sample(frame: int) -> void:
	if _perf_done or frame < 120:
		return
	var now := Time.get_ticks_usec()
	if frame < 600:
		if _perf_last > 0:
			_perf_cpu.append((now - _perf_last) / 1000.0)  # wall-clock frame ms
			_perf_gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(_raid.get_viewport().get_viewport_rid()))
			_perf_parts[0] += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
			_perf_parts[1] += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		_perf_last = now
		return
	_perf_done = true
	_perf_cpu.sort()
	_perf_gpu.sort()
	var n := maxf(1.0, _perf_cpu.size())
	print("RAID_PERF units=%d frames=%d frame_ms_avg=%.2f frame_ms_p99=%.2f gpu_avg=%.2f gpu_p99=%.2f | monitor (not frame time): process=%.2f physics=%.2f" % [
		_raid.allies.size() + _raid.enemies.size(), _perf_cpu.size(), _avg(_perf_cpu), _p99(_perf_cpu),
		_avg(_perf_gpu), _p99(_perf_gpu), _perf_parts[0] / n, _perf_parts[1] / n])


static func _avg(a: Array) -> float:
	var t := 0.0
	for v in a:
		t += float(v)
	return t / maxf(1.0, a.size())


static func _p99(a: Array) -> float:
	if a.is_empty():
		return 0.0
	return float(a[mini(a.size() - 1, int(ceil(a.size() * 0.99)) - 1)])
