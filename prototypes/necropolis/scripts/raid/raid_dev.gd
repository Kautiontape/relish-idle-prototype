class_name RaidDev
extends RefCounted
## Standalone dev harness for the raid scene, created only when the scene is launched directly:
##   godot --path . res://scenes/raid/Raid.tscn -- --new-game --raid-fixture=day1,old-sluice
## Flags: --raid-fixture=<fixture>,<fort_id> (needs --new-game: all worktrees share user://),
## --raid-stress=N [--raid-stress-door] (the crowd pushed through a doorway), --raid-perf, --raid-autoexit=<frames>, --raid-autodie=<frames>,
## --raid-held-shot=<png> (with --raid-held and the autopilot: a screenshot 0.3 s into the clear set piece), --raid-motes=N, --raid-trance-hold (open the trance at start), --raid-held, --raid-warden (Relish starts in the antechamber),
## --raid-trace-demo=<frac> (with --raid-trance-hold and --raid-motes=N: a scripted loop is drawn through the trance's real tracing path, one point per frame,
##   around the motes with a slight wobble; frac of a turn: under 1 it stops mid-draw and holds, 1 or more releases it; prints TRACE_DEMO frame= score= motes= tier= released=),
## --raid-greyscale (the greyscale check over the screen), --raid-autodie-src=<slam|lunge|bash|fire|living> (who the autodie hit names on the death card),
## --raid-clones=<n> / --raid-death-ends=<clone|unmade>:<respawn_s> (the death card's AFTER row: clones_ready, or the injected seed key),
## --raid-archetype=<id> (demo seed's warden), --raid-big-speed=<n> (demo party big undead),
## --raid-ding-chance=<p> (every tier's ding chance, to see dings), --raid-warden-go (with it: Relish walks into the warden room, then to the chest),
## --raid-warden-fell=<frames> (the warden falls that many frames after it wakes: with --raid-warden-go, the clear beat's shots),
## --raid-loot-sample (one floor pickup of each loot kind in a row by Relish: the glyph screenshot; only remnants drop in play),
## --raid-autopilot=<score> [--raid-autopilot-seed=<n>] [--raid-autopilot-answer-mult=<x>] (RaidAutopilot: plays the raid headless, prints AUTOPILOT_RESULT, quits),
## --raid-profile=<party_tier> --raid-fort=<fort_id> (BALANCE 3's standard party of that tier at that world.json fort; raid.json autopilot.party_profiles),
##   with --raid-party-<stat>=<n> (power, beef, wits, presence, speed) every party big undead's <stat> set to n: the weak
##   points with and without (--raid-party-wits for the Shieldwall, --raid-party-power for the Pyre-priest).
## --raid-run-ended=<frames> (H-a: after that many frames the raid emits a synthetic run_ended {run_id: its own, kind, outcome: retreated,
##   cause: gap} through Game.game_event, as the state does when a gap above idle.gap_s ends the open run; the flag also enables the raid's
##   listener in a standalone launch. It touches no state. The raid stops, shows the AWAY TOO LONG banner and emits one result: with the
##   fixture a RAID_RESULT exit=retreated, the capture's retreat_by "gap"),
## --raid-assist (the warned-attack assist on: every warned attack's tell window x raid.json assist.tell_mult, from the next tell a warden lays, never inside a running one; the boss
##   scene reads it too, for Vei's weaves; the legend's LONGER WARNINGS row is the same switch, RaidLogic.assist_on),
## --raid-shield-lane-every=<n> sets the Shieldwall's attack.rush_lane_every for this run (D-e task 4's candidates).
## A RefCounted, not a Node: the raid calls `start()` once the scene is built and `tick()` from
## its own _process, so it needs no tree presence of its own.

var _raid: Node2D
var _stress := 0                # --raid-stress=N
var _autoexit := -1             # --raid-autoexit=<frames>
var _autodie := -1              # --raid-autodie=<frames>
var _go := false                # --raid-warden-go autopilot
var _demo_frac := -1.0          # --raid-trace-demo=<frac> (-1 off)
var _run_ended := -1           # --raid-run-ended=<frames>: the frame a synthetic run_ended goes out (-1 off)
var _fell := -1               # --raid-warden-fell=<frames>: frames after the wake, the warden falls (the clear card's shots)
var _woke_at := -1
var _ap: RaidAutopilot = null   # --raid-autopilot=<score>: the headless measuring bot
var _perf := false
var _perf_cpu: Array = []
var _perf_gpu: Array = []
var _perf_done := false
var _perf_last := 0
var _perf_parts := [0.0, 0.0]   # summed TIME_PROCESS / TIME_PHYSICS_PROCESS monitors, ms
var _perf_route := [-1, -1]     # RaidRoute.recomputes and the physics frame at the window's start


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
			for st in ["power", "beef", "wits", "presence", "speed"]:
				var v := cli_value("--raid-party-%s=" % st)
				if v != "":
					for e in sd["party"]:   # a weak point's with/without arms: only that stat of the party moves
						e["stats"][st] = float(v)
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
	# the death card's AFTER row (dev; no seed carries `death_ends` until economy merges): --raid-clones=<n> sets clones_ready,
	# --raid-death-ends=<clone|unmade>:<respawn_s> injects the key
	var cl := cli_value("--raid-clones=")
	if cl != "":
		sd["clones_ready"] = maxi(0, int(cl))
	var de := cli_value("--raid-death-ends=")
	if de != "":
		var dp := de.split(":")
		sd["death_ends"] = {"outcome": dp[0], "respawn_s": float(dp[1]) if dp.size() > 1 else 0.0}
	var spd := cli_value("--raid-big-speed=")
	if spd != "":
		for e in sd.get("party", []):
			e["stats"]["speed"] = float(spd)
	# D-e task 4's candidates on one committed sha: the Shieldwall's attack.rush_lane_every for this process only
	# (set before the warden's spec is built in _build)
	var every := cli_value("--raid-shield-lane-every=")
	if every != "":
		ConfigDb.data["raid"]["wardens"]["archetypes"]["shieldwall"]["attack"]["rush_lane_every"] = int(every)


## Hook 1: the scene is built. Reads the dev flags and spawns the stress / mote setups.
func start() -> void:
	_stress = int(cli_value("--raid-stress="))
	_autoexit = int(cli_value("--raid-autoexit=")) if cli_value("--raid-autoexit=") != "" else -1
	_autodie = int(cli_value("--raid-autodie=")) if cli_value("--raid-autodie=") != "" else -1
	_run_ended = int(cli_value("--raid-run-ended=")) if cli_value("--raid-run-ended=") != "" else -1
	if cli_value("--raid-trace-demo=") != "" and not _raid.is_boss():
		_demo_frac = float(cli_value("--raid-trace-demo="))
	if cli_flag("--raid-warden") and not _raid.is_boss():
		_place_in_antechamber()
	if cli_flag("--raid-assist"):
		RaidLogic.assist_on = true
	_go = cli_flag("--raid-warden-go")
	_fell = int(cli_value("--raid-warden-fell=")) if cli_value("--raid-warden-fell=") != "" else -1
	if RaidAutopilot.enabled() and not _raid.is_boss():
		_ap = RaidAutopilot.new(_raid)
		_ap.start()
	if cli_flag("--raid-greyscale"):   # the whole screen in greyscale (shaders/greyscale_check.gdshader), for the warden-fight check
		var cl := CanvasLayer.new()
		cl.layer = 100
		var rect := ColorRect.new()
		rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var gm := ShaderMaterial.new()
		gm.shader = load("res://shaders/greyscale_check.gdshader")
		rect.material = gm
		cl.add_child(rect)
		_raid.add_child(cl)
	if cli_flag("--raid-trance-hold") and not _raid.is_boss():
		_raid.trance._button_down()   # open the trance and keep it open (the ghost-ring shot)
	if cli_value("--raid-ding-chance=") != "":
		var by_tier: Dictionary = ConfigDb.data["loot"]["ding"]["chance_by_tier"]
		for k in by_tier.keys():
			by_tier[k] = float(cli_value("--raid-ding-chance="))
	if _stress > 0 and not _raid.is_boss():
		_spawn_stress(_stress)
	if cli_flag("--raid-loot-sample") and not _raid.is_boss():
		_spawn_loot_sample()
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
		_raid.endings.confirm_exit("dev")
	if _run_ended >= 0 and frame >= _run_ended:
		_run_ended = -1
		Game.game_event.emit({"t": 0.0, "type": "run_ended", "run_id": int(_raid.seed_data.get("run_id", 0)),
			"kind": "boss" if _raid.is_boss() else "raid", "outcome": "retreated", "cause": "gap"})
	if _autodie > 0 and frame > 0 and frame % _autodie == 0 and not _raid._ended and not _raid.is_boss():   # not at frame 0: the first hit at frame N
		_autodie_hit()
	if _perf:
		_perf_sample(frame)
	if _go and not _raid._ended:
		_autopilot()
	if _fell >= 0 and not _raid._ended:
		_fell_tick(frame)
	if _demo_frac >= 0.0 and _demo_f != -2 and not _raid._ended:
		_demo_tick(_demo_frac)


## Hook 3: every physics frame of a live run (the measuring bot's think step).
func physics_tick(delta: float) -> void:
	if _ap != null:
		_ap.physics_tick(delta)


## Hook 5: the warden died, before the run lets go of it (the bot's last read of its counts).
func on_warden_died(w: RaidWarden) -> void:
	if _ap != null:
		_ap.on_warden_died(w)


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


## --raid-warden-fell=<frames>: `frames` process frames after the warden wakes, deal it a killing blow
## (through take_hit, so it drops its motes and the chest as in play). With --raid-warden-go Relish then
## walks to the chest and opens it: the clear beat, for its screenshots.
func _fell_tick(frame: int) -> void:
	var w = _raid.warden_run.warden if _raid.warden_run != null else null
	if w == null or not is_instance_valid(w) or not w.alive or not w.awake:
		return
	if _woke_at < 0:
		_woke_at = frame
	if frame - _woke_at >= _fell:
		_fell = -1
		w.take_hit(w.max_hp * 1000.0)   # past any ward or pack multiplier


## Kill every ally and deal Relish a lethal hit (a revive, then the run's end).
func _autodie_hit() -> void:
	for a in _raid.allies.duplicate():
		if is_instance_valid(a) and a.alive:
			a.die(true)
	# the blow equals her remaining hp (lethal, hp - amount <= 0): the STRUCK cue reads a plausible number, never -1030
	_raid.relish.take_hit(_raid.relish.hp, cli_value("--raid-autodie-src="))   # src: slam | lunge | bash | fire | living (the death card)


## --raid-loot-sample: one pickup of each RaidLoot.FLOOR_KINDS kind, in a row 120 px above Relish.
func _spawn_loot_sample() -> void:
	var bps: Array = ConfigDb.data.get("loot", {}).get("first_clear_blueprint_by_tier", {}).get("1", [""])
	var items := {"relic": {}, "remnant": {"aspect": "beef", "rarity": "common", "magnitude": 1},
		"husk": {"kind": str(ConfigDb.data.get("loot", {}).get("first_dungeon_husk", "skeleton"))},
		"blueprint": {"id": str(bps[0]) if not bps.is_empty() else ""}}
	var i := 0
	for k in RaidLoot.FLOOR_KINDS:
		var pk := RaidPickup.new()
		pk.raid = _raid
		pk.kind = k
		pk.remnant = items[k]
		pk.position = _raid.resolve_walls(_raid.relish.position + Vector2(-105.0 + 70.0 * i, -120.0), 10.0)
		_raid.units_root.add_child(pk)
		i += 1


## --raid-trace-demo=<frac>: once the trance is open, a scripted loop through the trance's real tracing path
## (synthetic left-button and mouse-motion events in screen coordinates into trance.handle_input), one point per
## frame, centred on Relish and wide enough to enclose the dev motes, with a deterministic wobble (a soldier-band
## score). `frac` of a full turn: under 1 it stops mid-draw and holds, 1 or more it goes on to the release.
const DEMO_TURN_FRAMES := 90
const DEMO_WOBBLE := 0.09
const DEMO_MARGIN_PX := 28.0
var _demo_f := -1               # frames drawn so far (-1 not started, -2 done)
var _demo_c := Vector2.ZERO
var _demo_r := 0.0


func _demo_world(f: int) -> Vector2:
	var th := -PI / 2.0 + TAU * float(f) / float(DEMO_TURN_FRAMES)
	return _demo_c + Vector2(_demo_r * (1.0 + DEMO_WOBBLE * sin(3.0 * th + 0.7)), 0.0).rotated(th)


func _demo_event(pos_world: Vector2, kind: String, pressed := true) -> void:
	var xf: Transform2D = _raid.get_canvas_transform()
	var ev: InputEvent
	if kind == "motion":
		ev = InputEventMouseMotion.new()
	else:
		ev = InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
	ev.position = xf * pos_world
	_raid.trance.handle_input(ev)


func _demo_report(released: bool) -> void:
	var tr: RaidTrance = _raid.trance
	var g := CircleScorer.grade(tr.trace) if tr.trace.size() >= 3 else {"valid": false, "score": 0}
	var n := 0
	if g["valid"]:
		n = _raid.raiser.motes_inside(g["center"], float(g["radius"])).size()
	print("TRACE_DEMO frame=%d score=%d motes=%d tier=%s released=%s" % [Engine.get_process_frames(), int(g["score"]), n,
		RaidLogic.score_class(int(g["score"]), _raid.rcfg()), str(released).to_lower()])


func _demo_tick(frac: float) -> void:
	var tr: RaidTrance = _raid.trance
	if _demo_f == -1:
		if tr.state != RaidTrance.State.ACTIVE:
			return
		var far := 0.0
		_demo_c = _raid.relish.global_position
		for e in _raid.get_tree().get_nodes_in_group("raid_essence"):
			far = maxf(far, e.global_position.distance_to(_demo_c))
		_demo_r = maxf(far, 40.0) + DEMO_MARGIN_PX
		_demo_event(_demo_world(0), "button")
		_demo_f = 0
		return
	if _demo_f < 0:
		return
	var total := int(round(frac * DEMO_TURN_FRAMES))
	if _demo_f < total:
		_demo_f += 1
		_demo_event(_demo_world(_demo_f), "motion")
		return
	if frac >= 1.0:
		_demo_report(true)   # graded as the release will grade it
		_demo_event(_demo_world(_demo_f), "button", false)
		print("TRACE_DEMO raises=%d" % _raid.raises)
	else:
		_demo_report(false)
	_demo_f = -2


## N fresh motes (mass 1) around Relish.
func _spawn_dev_motes(n: int) -> void:
	for i in n:
		var ang := TAU * i / float(n) + 0.3
		var pos: Vector2 = _raid.relish.position + Vector2(46.0 + 12.0 * (i % 3), 0).rotated(ang)
		_raid.spawn_mote(_raid.resolve_walls(pos, 6.0), 1.0, false)


## Perf harness: N soldier-tier raised undead in rings around Relish, enemies topped up to the cap.
## `--raid-stress-door`: the crowd pushed through a doorway. Relish and the rings stand
## 150 px inside her room from the gap nearest her, and the topped-up enemies wait in a block 220 px
## into the room beyond, so the crowd routes through that one gap (and back to her once they are dead).
func _spawn_stress(n: int) -> void:
	var cfg: Dictionary = _raid.rcfg()
	var door := _stress_door() if cli_flag("--raid-stress-door") else {}
	if not door.is_empty():
		var rel: RaidRelish = _raid.relish
		rel.position = _raid.resolve_walls(door["near"], rel.radius)
		rel.move_target = rel.position
		print("RAID_DEV --raid-stress-door rooms %d -> %d via %s" % [door["from"], door["to"], door["gap"]])
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
		var k := 0
		for sp in spots:
			var pos: Vector2 = sp["pos"]
			var room: int = sp["room"]
			if not door.is_empty():
				# a block of rows of 6, 28 px apart, centred on the far point
				pos = _raid.resolve_walls((door["far"] as Vector2) + Vector2(float(k % 6) - 2.5, float(k / 6) - 2.5) * 28.0, 10.0)
				room = door["to"]
			k += 1
			var u: RaidUnit = _raid.spawn_unit("enemy", sp["kind"], pos)
			u.mass = 1.0
			u.home_room = _raid.layout["rooms"][room]


## --raid-stress-door: the gap nearest Relish out of her room, as {from, to, gap, near (inside her
## room, 150 px from it), far (220 px into the next room)}; {} when her room has none.
func _stress_door() -> Dictionary:
	var lay: Dictionary = _raid.layout
	var pos: Vector2 = _raid.relish.position
	var r0 := LayoutLogic.room_of(lay, pos)
	var best := {}
	var bd := INF
	for key in (lay.get("portals", {}) as Dictionary):
		var ab: PackedStringArray = str(key).split(":")
		if int(ab[0]) != r0:
			continue
		for c in lay["portals"][key]:
			if pos.distance_to(c) < bd:
				bd = pos.distance_to(c)
				best = {"from": r0, "to": int(ab[1]), "gap": c}
	if best.is_empty():
		return {}
	var rooms: Array = lay["rooms"]
	best["near"] = LayoutLogic._into_room(rooms[r0], best["gap"], 150.0)
	best["far"] = LayoutLogic._into_room(rooms[best["to"]], best["gap"], 220.0)
	return best


func _perf_sample(frame: int) -> void:
	if _perf_done or frame < 120:
		return
	var now := Time.get_ticks_usec()
	if _perf_route[0] < 0:
		_perf_route = [RaidRoute.recomputes, Engine.get_physics_frames()]
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
	var ticks := maxi(1, Engine.get_physics_frames() - int(_perf_route[1]))
	print("RAID_PERF_ROUTE recomputes=%d physics_ticks=%d per_tick=%.1f" % [RaidRoute.recomputes - int(_perf_route[0]),
		ticks, float(RaidRoute.recomputes - int(_perf_route[0])) / float(ticks)])


static func _avg(a: Array) -> float:
	var t := 0.0
	for v in a:
		t += float(v)
	return t / maxf(1.0, a.size())


static func _p99(a: Array) -> float:
	if a.is_empty():
		return 0.0
	return float(a[mini(a.size() - 1, int(ceil(a.size() * 0.99)) - 1)])
