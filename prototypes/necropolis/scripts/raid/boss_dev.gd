class_name BossDev
extends RefCounted
## DEV flags for Vei's final test, standalone runs only (vei_boss.gd creates it when the scene is
## launched directly). Never a game feature.
##   --boss-seed=<n>          the demo seed's rng_seed (guards, motes, spawns; the bot's jitter)
##   --boss-fronts=<n>        n fronts met in the demo (BossLogic.force_fronts, vei.json demo)
##   --boss-backups=<p>,<c>   the demo's phylactery charges and ready clones
##   --boss-phase2            the break from the start: the met fronts clear at once (at least
##                            fronts_required of them)
##   --boss-stress            with the break: guards held at the cap, dev.stress_raised (at most
##                            raised.unit_cap) raised undead
##                            and dev.stress_motes motes at the anchors kept topped up, Relish kept
##                            alive: the busiest phase-2 state, for --raid-perf (RaidDev, inherited)
##   --boss-autodie=<frames>  every ally gone and a lethal hit on Relish at that frame of the scene
##                            (a backup cracks, or the final death)
##   --boss-autowin=<frames>  Vei breaks at that frame (the victory set piece)
##   --boss-hold-tell         the first weave's tell holds and never lands (the phase-2 screenshot)
##   --boss-prof              frames 120..600: the frame time (p99), the viewport's CPU and GPU render
##                            time, the draw time of the boss's own nodes per frame (lanes, labels,
##                            Vei, her telegraph), the boss step per physics frame, and the stress
##                            spawns per second; one BOSS_PROF line (pair it with --raid-perf)
##   --boss-hide=a,b,...      hide layers to find their cost by elimination: units, motes, vei,
##                            lanes, hud, arena, fx, swarm
## A RefCounted: the boss calls start() once built, tick() from _process and physics_tick() from
## its physics step.

var _boss: Node2D
var _frame0 := 0
var _autodie := -1
var _autowin := -1
var _hide: PackedStringArray = PackedStringArray()
var _frames: Array = []        # wall ms between frames
var _cpu: Array = []           # viewport CPU render ms
var _gpu: Array = []
var _prof_done := false
var _last_us := 0
var _spawned := 0              # --boss-stress top-ups (units and motes)

## The --boss-prof accumulators: microseconds per key, summed over the sampled frames.
static var prof_on := false
static var _acc := {}
static var _sampling := false


## Timing hooks for the boss's own draws and step: cheap no-ops unless --boss-prof is sampling.
static func pt() -> int:
	return Time.get_ticks_usec() if _sampling else 0


static func pa(key: String, t0: int) -> void:
	if _sampling and t0 > 0:
		_acc[key] = int(_acc.get(key, 0)) + Time.get_ticks_usec() - t0


func _init(p_boss: Node2D) -> void:
	_boss = p_boss


static func cli_value(prefix: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with(prefix):
			return a.trim_prefix(prefix)
	return ""


static func cli_flag(flag: String) -> bool:
	return flag in OS.get_cmdline_user_args()


## The demo seed's overrides: --boss-seed, --boss-backups.
static func apply_seed_overrides(sd: Dictionary) -> void:
	var s := cli_value("--boss-seed=")
	if s != "":
		sd["rng_seed"] = str(int(s))
	var b := cli_value("--boss-backups=")
	if b != "":
		var parts := b.split(",")
		sd["phylactery_charges"] = maxi(0, int(parts[0]))
		sd["clones_ready"] = maxi(0, int(parts[1])) if parts.size() > 1 else 0


## --boss-fronts=<n>: the first n fronts met, the rest short.
static func apply_fronts(fronts: Array, cfg: Dictionary) -> Array:
	var n := cli_value("--boss-fronts=")
	if n == "":
		return fronts
	return BossLogic.force_fronts(fronts, clampi(int(n), 0, fronts.size()), cfg)


func start() -> void:
	_frame0 = Engine.get_process_frames()
	var d := cli_value("--boss-autodie=")
	_autodie = int(d) if d != "" else -1
	var w := cli_value("--boss-autowin=")
	_autowin = int(w) if w != "" else -1
	_boss.stress = cli_flag("--boss-stress")
	prof_on = cli_flag("--boss-prof")
	if prof_on:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		RenderingServer.viewport_set_measure_render_time(_boss.get_viewport().get_viewport_rid(), true)
	var h := cli_value("--boss-hide=")
	if h != "":
		_hide = h.split(",")
		_apply_hide()
	if cli_flag("--boss-hold-tell"):
		_boss.vei.hold_tell = true
	if cli_flag("--boss-phase2") or _boss.stress:
		_skip_fronts()


## Every frame of the scene's _process.
func tick() -> void:
	if not _hide.is_empty():
		_apply_hide()
	if prof_on:
		_prof_sample()
	var f := Engine.get_process_frames() - _frame0
	if _autodie >= 0 and f >= _autodie:
		_autodie = -1
		_die()
	if _autowin >= 0 and f >= _autowin:
		_autowin = -1
		if not _boss.is_over():
			_boss.brk["streak"] = int(_boss.vcfg().get("break_beats", 8))
			_boss.streak_max = maxi(_boss.streak_max, int(_boss.brk["streak"]))
			_boss._win()


func physics_tick(_delta: float) -> void:
	if _boss.stress and _boss.relish != null:
		_boss.relish._iframes = 1.0   # the perf state must not end


## The fronts resolve at once: every met front clears (at least fronts_required of them).
func _skip_fronts() -> void:
	var p1: Dictionary = _boss.p1
	var need := VeiFronts.required(_boss.vcfg())
	var met := 0
	var fs: Array = []
	for f in p1["fronts"]:
		var g: Dictionary = (f as Dictionary).duplicate()
		if float(g["have"]) >= float(g["need"]):
			g["cleared"] = true
			g["progress"] = 1.0
			met += 1
		fs.append(g)
	for g in fs:
		if met >= need:
			break
		if not bool(g["cleared"]):
			g["have"] = maxf(float(g["have"]), float(g["need"]))
			g["cleared"] = true
			g["progress"] = 1.0
			met += 1
	p1["fronts"] = fs
	_boss.lanes_node.fronts = fs
	for i in fs.size():
		if bool(fs[i]["cleared"]):
			_boss.lanes_node.on_cleared(i)
	_boss._begin_break()


## The break began (vei_boss._begin_break).
func on_break() -> void:
	if _boss.stress:
		stress_tick()


## --boss-stress: guards at the cap, the raised and the anchor motes topped up.
func stress_tick() -> void:
	var cfg: Dictionary = _boss.vcfg()
	var cap := int(cfg.get("guards", {}).get("cap", 12))
	var n: int = cap - _boss.guards_alive()
	for i in n:
		_boss.spawn_guard()
	var dv: Dictionary = cfg.get("dev", {})
	var raised := 0
	for a in _boss.allies:
		if is_instance_valid(a) and a.alive and a.role == "raised":
			raised += 1
	var cap_r := int(cfg.get("raised", {}).get("unit_cap", 40))
	var want := mini(int(dv.get("stress_raised", 20)), cap_r) - raised
	if want > 0:
		_boss._spawn_raised(want, "soldier", 1.25, cfg)
		_spawned += want
	_spawned += maxi(0, n)
	var motes: int = _boss.get_tree().get_nodes_in_group("raid_essence").size()
	var anchors: Array = _boss.anchors
	for i in maxi(0, int(dv.get("stress_motes", 36)) - motes):
		if anchors.is_empty():
			break
		_boss._mote(anchors[i % anchors.size()] + Vector2(_boss.rng_combat.randf_range(0.0, 40.0), 0.0).rotated(_boss.rng_combat.randf() * TAU))
		_spawned += 1


## Every ally gone and a lethal hit: the next backup cracks (or the final death).
func _die() -> void:
	for a in _boss.allies.duplicate():
		if is_instance_valid(a) and a.alive:
			a.die(true)
	var rel: RaidRelish = _boss.relish
	if rel != null and rel.alive:
		rel._iframes = 0.0
		rel.take_hit(rel.max_hp + 1000.0)


## --boss-hide: the named layers stop drawing (units and motes come and go, so it runs every frame).
func _apply_hide() -> void:
	for k in _hide:
		match k:
			"units":
				for u in _boss.allies + _boss.enemies:
					if is_instance_valid(u):
						u.visible = false
			"motes":
				for m in _boss.get_tree().get_nodes_in_group("raid_essence"):
					m.visible = false
			"vei":
				_boss.vei.visible = false
			"lanes":
				_boss.lanes_node.visible = false
			"hud":
				_boss.hud.visible = false
			"arena":
				_boss.arena.visible = false
			"fx":
				_boss.fx_root.visible = false
			"swarm":
				_boss.swarm.visible = false


## --boss-prof: sample frames 120..600 (as RaidDev's --raid-perf), then print one line.
func _prof_sample() -> void:
	var frame := Engine.get_process_frames()
	if _prof_done or frame < 120:
		return
	var now := Time.get_ticks_usec()
	if frame == 120:
		_acc.clear()
		_spawned = 0
		_sampling = true
		_last_us = now
		return
	if frame < 600:
		var rid: RID = _boss.get_viewport().get_viewport_rid()
		_frames.append((now - _last_us) / 1000.0)
		_cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(rid))
		_gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(rid))
		_last_us = now
		return
	_prof_done = true
	_sampling = false
	var n := maxf(1.0, _frames.size())
	var secs := 0.0
	for v in _frames:
		secs += float(v) / 1000.0
	var parts := ""
	for k in ["lanes", "labels", "vei", "tele", "step"]:
		parts += " %s=%.0f" % [k, float(_acc.get(k, 0)) / n]
	print("BOSS_PROF frames=%d frame_p99=%.2f frame_avg=%.2f cpu_render_avg=%.2f cpu_render_p99=%.2f gpu_p99=%.2f | us/frame:%s | units=%d motes=%d fx=%d spawns_per_s=%.1f hide=%s" % [
		_frames.size(), _p(_frames, 0.99), _avg(_frames), _avg(_cpu), _p(_cpu, 0.99), _p(_gpu, 0.99), parts,
		_boss.allies.size() + _boss.enemies.size(), _boss.get_tree().get_nodes_in_group("raid_essence").size(),
		_boss.fx_root.get_child_count(), _spawned / maxf(0.001, secs), ",".join(_hide)])


static func _avg(a: Array) -> float:
	var t := 0.0
	for v in a:
		t += float(v)
	return t / maxf(1.0, a.size())


static func _p(a: Array, q: float) -> float:
	if a.is_empty():
		return 0.0
	var s := a.duplicate()
	s.sort()
	return float(s[mini(s.size() - 1, int(ceil(s.size() * q)) - 1)])
