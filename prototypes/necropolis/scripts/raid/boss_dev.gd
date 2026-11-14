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
## A RefCounted: the boss calls start() once built, tick() from _process and physics_tick() from
## its physics step.

var _boss: Node2D
var _frame0 := 0
var _autodie := -1
var _autowin := -1


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
	if cli_flag("--boss-hold-tell"):
		_boss.vei.hold_tell = true
	if cli_flag("--boss-phase2") or _boss.stress:
		_skip_fronts()


## Every frame of the scene's _process.
func tick() -> void:
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
	var motes: int = _boss.get_tree().get_nodes_in_group("raid_essence").size()
	var anchors: Array = _boss.anchors
	for i in maxi(0, int(dv.get("stress_motes", 36)) - motes):
		if anchors.is_empty():
			break
		_boss._mote(anchors[i % anchors.size()] + Vector2(_boss.rng_combat.randf_range(0.0, 40.0), 0.0).rotated(_boss.rng_combat.randf() * TAU))


## Every ally gone and a lethal hit: the next backup cracks (or the final death).
func _die() -> void:
	for a in _boss.allies.duplicate():
		if is_instance_valid(a) and a.alive:
			a.die(true)
	var rel: RaidRelish = _boss.relish
	if rel != null and rel.alive:
		rel._iframes = 0.0
		rel.take_hit(rel.max_hp + 1000.0)
