extends Node2D
## The RAID scene: top-down arena raid on one of Vei's fortresses.
## Contract: setup(seed_data) → play → finished(result) exactly once.
## Standalone-safe: launched directly it seeds itself via demo_seed().

signal finished(result: Dictionary)

var seed_data := {}
var layout := {}
var ledger: RaidLogic.Ledger = null          # legacy (boss only)
var ledger_v2: RaidLogic.LedgerV2 = null     # dungeon (non-boss)
var rng_combat := RandomNumberGenerator.new()
var rng_loot := RandomNumberGenerator.new()  # reserved for the loot task
var party_died: Array = []
var relish: RaidRelish = null
var trance: RaidTrance = null
var hud: RaidHud = null
var vei: Node2D = null          # boss only; here so shared HUD code can poke it
var fx_root: Node2D = null
var units_root: Node2D = null
var cam: Camera2D = null

var enemies: Array = []
var allies: Array = []
var ally_engage_px := 620.0
var trance_active := false
var first_raise_done := false
var backlog_left := 0.0          # boss only
var army_lost := {"soldier": 0, "elite": 0}
var carried: Array = []          # essence motes in Relish's carried cluster (dungeon only)
var moves := 0                   # RAID_TELEMETRY: Relish move clicks
var raises := 0                  # RAID_TELEMETRY: successful raises (count > 0)
var _last_feedback: RaidTraceFeedback = null

var arena: RaidArena = null
var endings: RaidEndings = null
var _setup_called := false
var _built := false
var _standalone := false
var _from_run := false          # the seed came from Game.state (a run is open), not the demo
var _stress := 0                # --raid-stress=N
var _autoexit := -1             # --raid-autoexit=<frames>
var _perf := false
var _perf_cpu: Array = []
var _perf_gpu: Array = []
var _perf_done := false
var _perf_last := 0
var _perf_parts := [0.0, 0.0, 0.0]

## Run-over flag read by units, HUD, trance and the boss; lives on endings.
var _ended: bool:
	get:
		return endings.ended
	set(v):
		endings.ended = v


func _init() -> void:
	endings = RaidEndings.new(self)


func rcfg() -> Dictionary:
	return ConfigDb.data.get("raid", {})


func is_boss() -> bool:
	return bool(seed_data.get("boss", false))


## Palette key of the fortress's controller colour; it tints the walls. A Vei
## fortress is "living", the boss arena is "vei". Held (player) fortresses
## should be "undead": a later task sets `controller_key` in the seed.
func controller_key() -> String:
	return str(seed_data.get("controller_key", "vei" if is_boss() else "living"))


## Standalone setup args (VeiBoss overrides this with its legacy boss seed).
## A dev `--raid-fixture=<fixture>,<fort_id>` goes through commands only.
func demo_seed() -> Dictionary:
	var spec := _cli_value("--raid-fixture=")
	if spec != "" and Game.autosave_enabled:
		push_error("RAID_DEV --raid-fixture needs --new-game (harness session)")
		print("RAID_DEV --raid-fixture needs --new-game (harness session)")
		spec = ""
	if spec != "":
		var parts := spec.split(",")
		if parts.size() == 2:
			var fort_id := parts[1]
			var st: GameState = Game.state
			var r := st.cmd_debug_load_fixture(parts[0])
			if not r["ok"]:
				print("RAID_DEV refused: load_fixture %s -> %s" % [parts[0], r["reason"]])
			else:
				r = st.cmd_debug_set_state({"relish_at": fort_id})
				if not r["ok"]:
					print("RAID_DEV refused: set_state relish_at=%s -> %s" % [fort_id, r["reason"]])
				else:
					r = st.cmd_begin_dungeon(fort_id)
					if not r["ok"]:
						print("RAID_DEV refused: begin_dungeon %s -> %s" % [fort_id, r["reason"]])
					else:
						var sd: Dictionary = r["seed"]
						print("RAID_DEV seed issued fort=%s run_id=%d seed_rev=%d tier=%d starter_units=%d garrison_units=%d party=%d" % [
							fort_id, int(r["run_id"]), int(r["seed_rev"]), int(sd["fort"]["tier"]),
							int(sd["starter_units"]), int(sd["garrison_units"]), sd["party"].size()])
						return {"mode": "dungeon", "fort_id": fort_id,
							"run_id": r["run_id"], "seed_rev": r["seed_rev"]}
		else:
			print("RAID_DEV refused: --raid-fixture wants <fixture>,<fort_id>")
	return {"mode": "dungeon", "fort_id": ""}


static func _cli_value(prefix: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with(prefix):
			return a.trim_prefix(prefix)
	return ""


## Usage (all worktrees share user://, so the session must be a harness one):
##   godot --path . res://scenes/raid/Raid.tscn -- --new-game --raid-fixture=day1,old-sluice
static func _cli_flag(flag: String) -> bool:
	return flag in OS.get_cmdline_user_args()


func _ready() -> void:
	if not _setup_called and get_tree().current_scene == self:
		setup(demo_seed())
	elif _setup_called and not _built:
		_build()


## Router args `{mode: "dungeon", fort_id, run_id, seed_rev}` (legacy keys ignored).
## The legacy boss args (`boss: true`) are used as the seed as before.
func setup(args: Dictionary) -> void:
	if bool(args.get("boss", false)):
		seed_data = args.duplicate(true)
	else:
		seed_data = _resolve_seed(args)
	_setup_called = true
	if is_inside_tree() and not _built:
		_build()


func _resolve_seed(args: Dictionary) -> Dictionary:
	var standalone := is_inside_tree() and get_tree().current_scene == self
	var fort_id := str(args.get("fort_id", ""))
	var sd: Dictionary = {}
	if fort_id != "":
		sd = Game.state.view_dungeon_seed(fort_id)
	if sd.is_empty():
		if not standalone:
			push_warning("necropolis: raid has no open run for '%s'; using the demo seed" % fort_id)
		sd = RaidLogic.demo_seed(rcfg())
		_from_run = false
	else:
		_from_run = true
	for e in Results.validate("raid_seed", sd):
		push_error("necropolis: raid seed invalid: " + e)
	return sd


func fort_name() -> String:
	return str(seed_data.get("fort", {}).get("name", seed_data.get("name", "?")))


func fort_tier() -> int:
	return int(seed_data.get("fort", {}).get("tier", seed_data.get("tier", 1)))


func _build() -> void:
	_built = true
	_standalone = get_tree().current_scene == self
	var cfg := rcfg()
	var boss := is_boss()
	var fort_id := str(seed_data.get("fort_id", "fort")) if boss else str(seed_data.get("fort", {}).get("id", "fort"))
	var tier := int(seed_data.get("tier", 1)) if boss else fort_tier()
	layout = RaidLogic.gen_layout(fort_id, tier, boss, cfg)
	if boss:
		rng_combat.randomize()
		rng_loot.randomize()
		ledger = RaidLogic.Ledger.new(float(seed_data.get("dead", 0.0)), float(seed_data.get("cap", 100.0)))
	else:
		var base := int(str(seed_data.get("rng_seed", "1")).to_int())
		rng_combat.seed = base ^ 0x6C0AB47
		rng_loot.seed = base ^ 0x10075EED
		ledger_v2 = RaidLogic.LedgerV2.new(seed_data, cfg)

	# arena first: floor + walls draw under the units
	arena = RaidArena.new()
	arena.rng = rng_combat
	add_child(arena)
	arena.build(layout, cfg, controller_key())

	units_root = Node2D.new()
	add_child(units_root)
	fx_root = Node2D.new()
	add_child(fx_root)

	# --- Relish just inside the southernmost door ---
	relish = RaidRelish.new()
	relish.position = layout["spawn"]
	units_root.add_child(relish)
	relish.configure(self)
	arena.bind_relish(relish)

	# --- corpse piles: grey, matte, scattered on open ground ---
	var dead := float(seed_data.get("dead", 0.0))
	if dead > 0.05:
		var pc := RaidLogic.pile_count(dead, cfg)
		var ppos := RaidLogic.populate_piles(fort_id, layout, pc)
		for p in ppos:
			var pile := RaidPile.new()
			pile.raid = self
			pile.mass = dead / pc
			pile.position = p
			units_root.add_child(pile)

	if not is_boss():
		_populate_raid(cfg, fort_id, tier)

	# --- camera ---
	var ccam: Dictionary = cfg.get("camera", {})
	cam = Camera2D.new()
	cam.position_smoothing_enabled = true
	cam.position_smoothing_speed = float(ccam.get("smoothing", 5.0))
	var arena_size: Vector2 = layout["size"]
	cam.zoom = Vector2.ONE * clampf(1600.0 / (arena_size.x + float(ccam.get("view_pad_px", 120.0))),
		float(ccam.get("zoom_min", 0.72)), float(ccam.get("zoom_max", 1.15)))
	add_child(cam)
	cam.make_current()
	_cam_follow()
	cam.reset_smoothing()

	# --- trance + HUD ---
	trance = RaidTrance.new()
	trance.raid = self
	add_child(trance)
	hud = RaidHud.new()
	add_child(hud)
	hud.build(self, is_boss())

	if not boss:
		relish.hp = float(seed_data.get("relish_hp", relish.hp))
		relish.max_hp = relish.hp
	_build_extra()
	if _standalone:
		_cli_harness()


## Standalone dev args: --raid-stress=N, --raid-perf, --raid-autoexit=<frames>.
func _cli_harness() -> void:
	_stress = int(_cli_value("--raid-stress="))
	_autoexit = int(_cli_value("--raid-autoexit=")) if _cli_value("--raid-autoexit=") != "" else -1
	if _stress > 0 and not is_boss():
		_spawn_stress(_stress)
	var motes := int(_cli_value("--raid-motes=")) if _cli_value("--raid-motes=") != "" else 0
	if motes > 0 and not is_boss():
		_spawn_dev_motes(motes)
	if _cli_flag("--raid-perf"):
		_perf = true
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)


## Dev: N fresh motes (mass 1) around Relish.
func _spawn_dev_motes(n: int) -> void:
	for i in n:
		var ang := TAU * i / float(n) + 0.3
		var pos: Vector2 = relish.position + Vector2(46.0 + 12.0 * (i % 3), 0).rotated(ang)
		spawn_mote(resolve_walls(pos, 6.0), 1.0, false)


## Perf harness: N soldier-tier raised undead in rings around Relish, enemies topped up to the cap.
func _spawn_stress(n: int) -> void:
	var cfg := rcfg()
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
			var pos: Vector2 = relish.position + Vector2(r, 0).rotated(ang)
			spawn_ally_v2("raised", tier, mult, 0.0, "", stats, resolve_walls(pos, 10.0))
			made += 1
		ring += 1
	var extra := int(cfg.get("mass", {}).get("enemy_max", 34)) - enemies.size()
	if extra > 0:
		var fid := str(seed_data.get("fort", {}).get("id", "fort"))
		var spots := RaidLogic.populate_enemies(fid + "-stress", layout, extra, fort_tier(), cfg)
		for sp in spots:
			var u := spawn_unit("enemy", sp["kind"], sp["pos"])
			u.mass = 1.0
			u.home_room = layout["rooms"][sp["room"]]


## Standard fortress population from the v2 seed. The boss scene replaces this.
func _populate_raid(cfg: Dictionary, fort_id: String, tier: int) -> void:
	var sd := seed_data
	var living := float(sd.get("living", 0.0))
	var cap := float(sd.get("fort", {}).get("cap", 100.0))
	if living > 0.05:
		var n := RaidLogic.enemy_count(living, cap, cfg)
		var mpe := living / n
		var spots := RaidLogic.populate_enemies(fort_id, layout, n, tier, cfg)
		for s in spots:
			var u := spawn_unit("enemy", s["kind"], s["pos"])
			u.mass = mpe
			u.home_room = layout["rooms"][s["room"]]
	# garrison: exactly the seed's units, each carrying garrison_mass_div of ledger mass
	var gn := int(sd.get("garrison_units", 0))
	var gdiv := float(sd.get("garrison_mass_div", 10.0))
	var gmult := float(cfg.get("garrison", {}).get("stat_mult", 1.0))
	var gstats := RaidLogic.undead_stats(gmult, "chaff", cfg)
	for i in gn:
		var ang := TAU * i / maxf(1.0, gn) + 0.4
		var pos: Vector2 = relish.position + Vector2(54.0 + (i % 3) * 22.0, 0).rotated(ang)
		spawn_ally_v2("garrison", "chaff", gmult, gdiv, "", gstats, resolve_walls(pos, 8.0))
	# starters: massless chaff
	var sn := int(sd.get("starter_units", 0))
	var smult := float(cfg.get("starter", {}).get("stat_mult", 1.0))
	var sstats := RaidLogic.undead_stats(smult, "chaff", cfg)
	for i in sn:
		var ang := TAU * i / maxf(1.0, sn) + 0.9
		var pos: Vector2 = relish.position + Vector2(96.0 + (i % 2) * 22.0, 0).rotated(ang)
		spawn_ally_v2("starter", "chaff", smult, 0.0, "", sstats, resolve_walls(pos, 8.0))
	# party: one big undead per entry
	var party: Array = sd.get("party", [])
	for i in party.size():
		var e: Dictionary = party[i]
		var ang := TAU * i / maxf(1.0, party.size()) - 0.7
		var pos: Vector2 = relish.position + Vector2(150.0, 0).rotated(ang)
		var u := spawn_ally_v2("party", "big", 1.0, 0.0, str(e.get("uid", "")),
			RaidLogic.big_undead_stats(e.get("stats", {}), cfg), resolve_walls(pos, 20.0), false, "big")
		# TODO(api-request #6): party entries carry no filled_slots yet; 1 nested diamond until they do
		u.slots = maxi(1, int(e.get("filled_slots", 1)))


## Boss hook — overridden by VeiBoss.
func _build_extra() -> void:
	pass


func _post_physics(_delta: float) -> void:
	pass


# ----------------------------------------------------------------- runtime ---
func _process(_delta: float) -> void:
	if not _built:
		return
	var frame := Engine.get_process_frames()
	if _autoexit >= 0 and frame >= _autoexit and not _ended:
		_autoexit = -1
		confirm_exit()
	if _perf:
		_perf_sample(frame)


func _perf_sample(frame: int) -> void:
	if _perf_done or frame < 120:
		return
	var now := Time.get_ticks_usec()
	if frame < 600:
		if _perf_last > 0:
			_perf_cpu.append((now - _perf_last) / 1000.0)  # wall-clock frame ms
			_perf_gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid()))
			_perf_parts[0] += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
			_perf_parts[1] += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		_perf_last = now
		return
	_perf_done = true
	_perf_cpu.sort()
	_perf_gpu.sort()
	var n := maxf(1.0, _perf_cpu.size())
	print("RAID_PERF units=%d frames=%d frame_ms_avg=%.2f frame_ms_p99=%.2f gpu_avg=%.2f gpu_p99=%.2f | monitor (not frame time): process=%.2f physics=%.2f" % [
		allies.size() + enemies.size(), _perf_cpu.size(), _avg(_perf_cpu), _p99(_perf_cpu),
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


func _physics_process(delta: float) -> void:
	if not _built or _ended:
		return
	arena.rebuild_grid(allies, enemies, relish)
	_cam_follow()
	_post_physics(delta)


## Follow Relish, but never waste the frame on void: clamp the view to the
## arena, and center any axis where the arena is smaller than the viewport.
func _cam_follow() -> void:
	var arena_size: Vector2 = layout["size"]
	var view: Vector2 = get_viewport_rect().size / cam.zoom.x
	var t := relish.position
	var m := 60.0
	if view.x >= arena_size.x + 2.0 * m:
		t.x = arena_size.x * 0.5
	else:
		t.x = clampf(t.x, view.x * 0.5 - m, arena_size.x - view.x * 0.5 + m)
	if view.y >= arena_size.y + 2.0 * m:
		t.y = arena_size.y * 0.5
	else:
		t.y = clampf(t.y, view.y * 0.5 - m, arena_size.y - view.y * 0.5 + m)
	cam.position = t


func _unhandled_input(ev: InputEvent) -> void:
	if not _built or _ended:
		return
	if trance.handle_input(ev):
		get_viewport().set_input_as_handled()
		return
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and ev.pressed:
		var w := screen_to_world(ev.position)
		relish.move_target = w
		moves += 1
		RaidFx.ping(fx_root, w)
		get_viewport().set_input_as_handled()


func screen_to_world(p: Vector2) -> Vector2:
	return get_canvas_transform().affine_inverse() * p


# ------------------------------------------------------------- unit helpers --
func spawn_unit(faction: String, kind: String, pos: Vector2, grown := false) -> RaidUnit:
	var cfg := rcfg()
	var stats: Dictionary = {}
	if faction == "enemy":
		if kind == "guard":
			stats = cfg.get("boss", {}).get("guard", {})
		else:
			stats = cfg.get("enemies", {}).get(kind, {})
	else:
		stats = cfg.get("undead", {}).get(kind, {})
	var u := RaidUnit.new()
	u.position = pos
	units_root.add_child(u)
	u.configure(self, faction, kind, stats)
	if grown:
		u.grow_in()
	if faction == "enemy":
		enemies.append(u)
	else:
		allies.append(u)
	return u


## A v2 ally (raised, garrison, starter or party) with its ledger fields.
func spawn_ally_v2(role: String, tier: String, mult: float, mass: float, uid: String,
		stats: Dictionary, pos: Vector2, grown := false, kind := "") -> RaidUnit:
	var u := RaidUnit.new()
	u.position = pos
	units_root.add_child(u)
	u.configure(self, "ally", kind if kind != "" else tier, stats)
	u.role = role
	u.tier = tier
	u.stat_mult = mult
	u.mass = mass
	u.uid = uid
	if grown:
		u.grow_in()
	allies.append(u)
	return u


func on_unit_died(u: RaidUnit, sacrificed: bool) -> void:
	if u.faction == "enemy":
		enemies.erase(u)
		if is_boss():
			ledger.on_kill(u.mass)
		else:
			ledger_v2.on_kill(u.mass)
		# kills drop essence at the corpse, carrying the enemy's mass
		if is_boss():
			spawn_orb(u.global_position, u.mass, Vector2(rng_combat.randf_range(30, 70), 0).rotated(rng_combat.randf() * TAU))
		else:
			_drop_motes(u.global_position, u.mass, int(rcfg().get("essence", {}).get("per_living", 1)), false)
		RaidFx.ring(fx_root, u.global_position, Palette.c("living", 0.6), 26.0, 0.3, 2.0)
	else:
		allies.erase(u)
		if is_boss():
			if u.ledger_mass:
				ledger.on_chaff_death(u.mass)
			if u.kind == "soldier":
				army_lost["soldier"] += 1
			elif u.kind == "elite":
				army_lost["elite"] += 1
		else:
			if u.role == "party":
				party_died.append(u.uid)
			# a fallen undead returns its mass to the field; massless ones drop mass-0 motes
			var m: float = u.mass if u.role in ["raised", "garrison"] else 0.0
			_drop_motes(u.global_position, m, int(rcfg().get("essence", {}).get("per_undead", 1)), true)
		if not sacrificed:
			RaidFx.ring(fx_root, u.global_position, Palette.c("undead", 0.4), 20.0, 0.25, 2.0)
		_on_ally_died(u)


## Boss hook (corpse remnants for Vei's revive).
func _on_ally_died(_u: RaidUnit) -> void:
	pass


func has_allies() -> bool:
	for a in allies:
		if is_instance_valid(a) and a.alive:
			return true
	return false


## THE SACRIFICE CHAIN (MECHANICS 5.0): a lethal hit on Relish consumes the nearest ally of the
## lowest available rank (chaff, soldier, elite, big undead). The boss keeps plain nearest.
func sacrifice_nearest_ally() -> void:
	var pool: Array = []
	var cands: Array = []
	for a in allies:
		if not is_instance_valid(a) or not a.alive:
			continue
		pool.append(a)
		cands.append({"rank": 0 if is_boss() else RaidLogic.ally_rank(a.role, a.tier),
			"dist": a.global_position.distance_to(relish.global_position)})
	var k := RaidLogic.sacrifice_pick(cands)
	if k < 0:
		return
	var best: RaidUnit = pool[k]
	RaidFx.soul_link(fx_root, best.global_position, relish.global_position)
	RaidFx.ring(fx_root, best.global_position, Palette.c("danger"), 34.0, 0.45, 3.0)
	RaidFx.ring(fx_root, relish.global_position, Palette.c("danger"), 26.0, 0.45, 2.0)
	best.die(true)


## Alive allies by sacrifice rank, for the HUD ward line.
func ward_counts() -> Dictionary:
	var out := {"chaff": 0, "soldier": 0, "elite": 0, "big": 0}
	var names := ["chaff", "soldier", "elite", "big"]
	for a in allies:
		if is_instance_valid(a) and a.alive:
			var k: String = names[RaidLogic.ally_rank(a.role, a.tier)]
			out[k] = int(out[k]) + 1
	return out


func nearest_enemy_of(pos: Vector2):
	var best = null
	var bd := ally_engage_px
	for e in enemies:
		if not is_instance_valid(e) or not e.alive:
			continue
		var d: float = pos.distance_to(e.global_position)
		if d < bd:
			bd = d
			best = e
	return best


func nearest_ally_of(pos: Vector2):
	var best = null
	var bd := INF
	for a in allies:
		if not is_instance_valid(a) or not a.alive:
			continue
		var d: float = pos.distance_to(a.global_position)
		if d < bd:
			bd = d
			best = a
	return best



# --------------------------------------------------------------- arena -------
func separation_push(u: Node2D) -> Vector2:
	return arena.separation_push(u)


## Keep a point inside the arena and out of internal walls (slide-friendly).
func resolve_walls(p: Vector2, r: float) -> Vector2:
	return arena.resolve_walls(p, r)


# ------------------------------------------------------------- essence -------
func spawn_orb(pos: Vector2, mass: float, pop_vel := Vector2.ZERO) -> void:
	if mass <= 0.001:
		return
	var o := RaidEssence.new()
	o.raid = self
	o.mass = mass
	o.position = pos
	o.pop(pop_vel)
	units_root.add_child(o)


## One mote with explicit mass/recycled (mass 0 allowed: massless undead return no mass).
func spawn_mote(pos: Vector2, mass: float, recycled: bool, pop_vel := Vector2.ZERO) -> void:
	var o := RaidEssence.new()
	o.raid = self
	o.mass = maxf(0.0, mass)
	o.recycled = recycled
	o.position = pos
	o.pop(pop_vel)
	units_root.add_child(o)


## A death drops n motes splitting `mass` evenly.
func _drop_motes(pos: Vector2, mass: float, n: int, recycled: bool) -> void:
	if n <= 0:
		return
	var parts := RaidLogic.split_mass(mass, n)
	var e: Dictionary = rcfg().get("essence", {})
	for i in n:
		var ang := rng_combat.randf() * TAU
		var spd := rng_combat.randf_range(30.0, 70.0)
		spawn_mote(pos + Vector2(rng_combat.randf_range(0, 6), 0).rotated(ang), float(parts[i]), recycled,
			Vector2(spd, 0).rotated(ang))


# --- carried cluster ---
func carried_count() -> int:
	return carried.size()


func carry_room() -> int:
	return 0 if is_boss() else RaidLogic.carry_room(carried.size(), rcfg())


## Take a mote into the cluster at the lowest free slot. Returns false when full.
func carry_add(o: RaidEssence) -> bool:
	if carry_room() <= 0 or o.carried:
		return false
	var used := {}
	for c in carried:
		used[c.carry_slot] = true
	var slot := 0
	while used.has(slot):
		slot += 1
	o.carry_slot = slot
	o.carried = true
	carried.append(o)
	return true


func carry_release(o: RaidEssence) -> void:
	carried.erase(o)
	o.carried = false


func set_trance(active: bool) -> void:
	trance_active = active
	arena.set_trance_dim(active)


func show_trace_feedback(g: Dictionary, trace: PackedVector2Array) -> void:
	var fb := RaidTraceFeedback.new()
	fb.trace = trace
	fb.fitted_center = g["center"]
	fb.fitted_radius = g["radius"]
	fb.score = int(g["score"])
	fb.valid = g["valid"]
	fx_root.add_child(fb)
	_last_feedback = fb


## A released, scored circle: consume enclosed essence, raise one undead per mote
## (MECHANICS 5.3). The boss keeps the legacy mass-ledger raise.
func perform_raise(g: Dictionary) -> void:
	var score := int(g["score"])
	var center: Vector2 = g["center"]
	var radius: float = g["radius"]
	var picked: Array = []
	for e in get_tree().get_nodes_in_group("raid_essence"):
		if is_instance_valid(e) and not e.absorbing and e.global_position.distance_to(center) <= radius:
			picked.append(e)
	if picked.is_empty():
		return
	if is_boss():
		_perform_raise_legacy(score, picked)
		return
	var motes: Array = []
	for e in picked:
		motes.append({"mass": e.mass, "recycled": e.recycled})
		e.absorb()
	var cfg := rcfg()
	var spec := RaidLogic.raise_spec_v2(score, motes, cfg, ConfigDb.data.get("circle", {}))
	var count := int(spec["count"])
	if count <= 0:
		return
	ledger_v2.on_raise(score, float(spec["fresh_mass"]), count)
	first_raise_done = true
	raises += 1
	var tier := str(spec["tier"])
	if _last_feedback != null and is_instance_valid(_last_feedback):
		_last_feedback.raised_n = count
		_last_feedback.raised_tier = tier
	var mult := float(spec["stat_mult"])
	var stats := RaidLogic.undead_stats(mult, tier, cfg)
	var masses: Array = spec["unit_masses"]
	var ring_px: float = float(cfg.get("raise", {}).get("spawn_ring_px", 52.0))
	for i in count:
		var ang := TAU * i / float(count) + rng_combat.randf() * 0.8
		var pos: Vector2 = relish.global_position + Vector2(ring_px + rng_combat.randf_range(-10, 26), 0).rotated(ang)
		spawn_ally_v2("raised", tier, mult, float(masses[i]), "", stats, resolve_walls(pos, 10.0), true)
	RaidFx.ring(fx_root, relish.global_position, Palette.c("undead"), ring_px + 26.0, 0.5, 3.0)


func _perform_raise_legacy(score: int, picked: Array) -> void:
	var total_mass := 0.0
	for e in picked:
		total_mass += e.mass
		e.absorb()
	var spec := ledger.on_raise(score, total_mass, picked.size(), rcfg())
	if int(spec["count"]) <= 0:
		return
	first_raise_done = true
	var ring_px: float = float(rcfg().get("raise", {}).get("spawn_ring_px", 52.0))
	for i in int(spec["count"]):
		var ang := TAU * i / float(spec["count"]) + rng_combat.randf() * 0.8
		var pos: Vector2 = relish.global_position + Vector2(ring_px + rng_combat.randf_range(-10, 26), 0).rotated(ang)
		var u := spawn_unit("ally", str(spec["kind"]), resolve_walls(pos, 10.0), true)
		if str(spec["kind"]) == "chaff":
			u.ledger_mass = true
			u.mass = float(spec["unit_mass"])
	RaidFx.ring(fx_root, relish.global_position, Palette.c("undead"), ring_px + 26.0, 0.5, 3.0)


# --------------------------------------------------------------- endings -----
func request_exit() -> void:
	endings.request_exit()


func confirm_exit() -> void:
	endings.confirm_exit()


func on_relish_died() -> void:
	endings.on_relish_died()


func _exit_result() -> Dictionary:
	return _build_result("retreated")


func _death_result() -> Dictionary:
	return _build_result("relish_died")


## Raid result v2 from the ledger and every living ally.
func _build_result(exit: String) -> Dictionary:
	var survivors: Array = []
	for a in allies:
		if is_instance_valid(a) and a.alive:
			survivors.append({"role": a.role, "tier": a.tier, "mass": a.mass})
	var loot := RaidLogic.empty_loot()
	if exit == "retreated":
		loot["essence"] = carried_count()  # banked: motes carried out
	var r := ledger_v2.build_result(seed_data, exit, survivors, party_died, 0, loot, rcfg())
	for e in Results.validate("raid", r):
		push_error("necropolis: raid result invalid: " + e)
	return r


func _finish(result: Dictionary) -> void:
	endings.finish(result)


## RAID_TELEMETRY line (not part of the result dict).
func telemetry_line() -> String:
	return "RAID_TELEMETRY moves=%d raises=%d ratio=%.1f drifting=%s" % [moves, raises,
		RaidLogic.drift_ratio(moves, raises), str(RaidLogic.is_drifting(moves, raises, rcfg()))]


## Standalone only (no router): write the result back to the open run and say what happened.
func standalone_apply(result: Dictionary) -> void:
	if is_boss() or not _from_run or not result.has("v"):
		return
	var out: Dictionary = Game.state.apply_result("raid", result)
	var ex := "relish_died" if result["relish_died"] else ("warden_beaten" if result["warden_beaten"] else "retreated")
	print("RAID_RESULT exit=%s raised=%s garrison_mass=%.2f chaff_mass=%.2f apply: ok=%s reason=%s errors=%s" % [
		ex, str(result["raised"]), float(result["garrison_mass"]), float(result["chaff_mass"]),
		out["ok"], out["reason"], str(out["errors"])])
