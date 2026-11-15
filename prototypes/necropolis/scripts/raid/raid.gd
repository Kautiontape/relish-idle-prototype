extends Node2D
## The RAID scene: top-down arena raid on one of Vei's fortresses.
## Contract: setup(seed_data) → play → finished(result) exactly once.
## Standalone-safe: launched directly it seeds itself via demo_seed().

signal finished(result: Dictionary)

var seed_data := {}
var layout := {}
var ledger_v2: RaidLogic.LedgerV2 = null     # dungeon (non-boss)
var rng_combat := RandomNumberGenerator.new()
var rng_loot := RandomNumberGenerator.new()  # every loot roll (RaidLoot); seeded from the run seed
var party_died: Array = []
var relish: RaidRelish = null
var trance: RaidTrance = null
var hud: RaidHud = null
var danger: RaidDanger = null
var swarm: RaidSwarm = null
var vei: Node2D = null          # boss only; here so shared HUD code can poke it
var fx_root: Node2D = null
var units_root: Node2D = null
var cam: Camera2D = null

var enemies: Array = []
var allies: Array = []
var ally_engage_px := 620.0
var trance_active := false
var first_raise_done := false
var carried: Array = []          # essence motes in Relish's carried cluster (dungeon only)
var moves := 0                   # RAID_TELEMETRY: Relish move clicks
var raises := 0                  # RAID_TELEMETRY: successful raises (count > 0)
var _carry_t := 0.0
var held := false                # the fort is the player's (view_fort.held, or --raid-held)
var found_loot := {}             # loot found this run, minus essence (dings + the chest)
var detour_guard: Array = []      # the guarded detour's living (RaidPopulate; raid.json detour)
var detour_cache: Array = []      # its cache's pickups
var held_door: RaidHeldDoor = null   # D-e task 6: the held door (raid.json held_door), null on a fort without one

var arena: RaidArena = null
var endings: RaidEndings = null
var raiser: RaidRaise = null
var warden_run: RaidWardenRun = null
var held_clear: RaidHeldClear = null   # the held fort's counter-garrison clear (held dungeon only)
var _setup_called := false
var _built := false
var _standalone := false
var _from_run := false          # the seed came from Game.state (a run is open), not the demo
var _dev: RaidDev = null        # the standalone dev harness; null when the router launched us
var capture: RaidCapture = null # capture mode (--capture[=<path>], D-e): one record per live dungeon run; reads only

## Run-over flag read by units, HUD, trance and the boss; lives on endings.
var _ended: bool:
	get:
		return endings.ended
	set(v):
		endings.ended = v


## Phylactery revives spent this run (lives on endings; Relish draws a mark per revive).
var revived: int:
	get:
		return endings.revived


func _init() -> void:
	endings = RaidEndings.new(self)
	raiser = RaidRaise.new(self)
	warden_run = RaidWardenRun.new(self)
	held_clear = RaidHeldClear.new(self)


func rcfg() -> Dictionary:
	return ConfigDb.data.get("raid", {})


## The Synth kinds to render ahead of use (raid.json `sound.warm`; VeiBoss reads vei.json's).
func sound_warm() -> Array:
	return Array(rcfg().get("sound", {}).get("warm", RaidSound.WARM_KINDS))


func lcfg() -> Dictionary:
	return ConfigDb.data.get("loot", {})


func is_boss() -> bool:
	return bool(seed_data.get("boss", false))


## Palette key of the fortress's controller colour; it tints the walls. Walls never use the
## unit colours (living, undead): Vei's forts and the boss arena are "vei" (the boss runs hotter),
## a held (player) fortress is "town".
func controller_key() -> String:
	var k := str(seed_data.get("controller_key", ""))
	if k == "vei" or k == "town":   # a seed can never hand the walls a unit colour
		return k
	return "town" if held and not is_boss() else "vei"


## Standalone setup args (VeiBoss overrides this: its demo seed is vei.json `demo`).
## A dev `--raid-fixture=<fixture>,<fort_id>` goes through commands only.
func demo_seed() -> Dictionary:
	var sd := RaidDev.fixture_seed()
	return sd if not sd.is_empty() else {"mode": "dungeon", "fort_id": ""}


func _ready() -> void:
	if not _setup_called and get_tree().current_scene == self:
		setup(demo_seed())
	elif _setup_called and not _built:
		_build()


## Router args `{mode: "dungeon", fort_id, run_id, seed_rev}` (legacy keys ignored). VeiBoss
## overrides this with its own seed.
func setup(args: Dictionary) -> void:
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
		sd = RaidDev.profile_seed(rcfg()) if standalone else {}
		if sd.is_empty():
			sd = RaidLogic.demo_seed(rcfg())
		if standalone:
			RaidDev.apply_demo_overrides(sd)
		_from_run = false
	else:
		_from_run = true
	if standalone and RaidAutopilot.enabled():
		RaidAutopilot.apply_seed(sd)
	for e in Results.validate("raid_seed", sd):
		push_error("necropolis: raid seed invalid: " + e)
	return sd


## Open run: the economy's view of the fort. Standalone demo: the --raid-held dev arg.
func _is_held(fort_id: String) -> bool:
	if _from_run:
		return bool(Game.state.view_fort(fort_id).get("held", false))
	return RaidDev.cli_flag("--raid-held")


func fort_name() -> String:
	return str(seed_data.get("fort", {}).get("name", seed_data.get("name", "?")))


## The player's first dungeon (seed.fort.first_dungeon): taught in-world (ghost ring, a pile by the spawn).
func is_first_dungeon() -> bool:
	return not is_boss() and bool(seed_data.get("fort", {}).get("first_dungeon", false))


func fort_tier() -> int:
	return int(seed_data.get("fort", {}).get("tier", seed_data.get("tier", 1)))


func _build() -> void:
	_built = true
	RaidRoute.reset_seq()   # the per-mover stagger restarts each raid (same seed, same run)
	_standalone = get_tree().current_scene == self
	var cfg := rcfg()
	var boss := is_boss()
	var fort_id := str(seed_data.get("fort_id", "fort")) if boss else str(seed_data.get("fort", {}).get("id", "fort"))
	var tier := int(seed_data.get("tier", 1)) if boss else fort_tier()
	held = false if boss else _is_held(fort_id)
	layout = RaidLogic.gen_layout(fort_id, tier, boss, cfg, {"held": held, "first_dungeon": is_first_dungeon()})
	if not boss:
		held_door = RaidHeldDoor.make(self, layout, tier, cfg)   # carves its niche into the layout (no rng)
	if not boss:   # (VeiBoss seeds its own rngs from its seed in _build_extra and keeps no ledger)
		var base := int(str(seed_data.get("rng_seed", "1")).to_int())
		rng_combat.seed = base ^ 0x6C0AB47
		rng_loot.seed = base ^ 0x10075EED
		ledger_v2 = RaidLogic.LedgerV2.new(seed_data, cfg)

	# arena first: floor + walls draw under the units
	arena = RaidArena.new()
	arena.rng = rng_combat
	add_child(arena)
	arena.build(layout, cfg, controller_key())
	if held_door != null:
		add_child(held_door)

	units_root = Node2D.new()
	add_child(units_root)
	fx_root = Node2D.new()
	add_child(fx_root)
	RaidSound.attach(self, sound_warm())

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
	elif bool(layout.get("first_dungeon", false)) and not is_boss():
		# the first dungeon has no dead to speak of; one massless pile by the spawn still teaches the circle
		var fp := RaidPile.new()
		fp.raid = self
		fp.mass = 0.0
		fp.look_mass = float(cfg.get("layout", {}).get("first_pile_look_mass", 6.0))
		fp.position = LayoutLogic.first_pile(fort_id, layout)
		units_root.add_child(fp)

	if not is_boss():
		RaidPopulate.new(self).populate(cfg, fort_id, tier)
		warden_run.build()

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
	danger = RaidDanger.new()
	add_child(danger)
	swarm = RaidSwarm.new()
	swarm.configure(self)
	add_child(swarm)
	hud = RaidHud.new()
	add_child(hud)
	hud.build(self, is_boss())
	if is_first_dungeon() and not held:
		var gr := RaidGhostRing.new()
		gr.raid = self
		add_child(gr)

	if not boss:
		relish.hp = float(seed_data.get("relish_hp", relish.hp))
		relish.max_hp = relish.hp
	_build_extra()
	if not boss:
		endings.start()
		held_clear.on_built()
		var cap_path := RaidCapture.path_from_cli()
		if cap_path != "":   # any launch path: the router's as well as the standalone scene's
			capture = RaidCapture.new(self, cap_path)
			capture.start()
	if _standalone:
		_dev = RaidDev.new(self)
		_dev.start()


## Boss hook — overridden by VeiBoss.
func _build_extra() -> void:
	pass


func _post_physics(_delta: float) -> void:
	pass


# ----------------------------------------------------------------- runtime ---
func _process(_delta: float) -> void:
	if not _built:
		return
	_carry_t += _delta
	if _dev != null:
		_dev.tick()


func _physics_process(delta: float) -> void:
	if not _built or _ended:
		return
	if _dev != null:
		_dev.physics_tick(delta)
	if capture != null:
		capture.physics_tick(delta)   # reads the run (the last frame's warden state); changes nothing
	arena.rebuild_grid(allies, enemies, relish)
	if not is_boss():
		endings.track_position()
		warden_run.tick()
		if held_door != null:
			held_door.tick(delta)
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
		if held_door != null and held_door.click(w):
			get_viewport().set_input_as_handled()   # the held door's order (on a big, or the plate): she stays put
			return
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


## The dungeon's deaths only: VeiBoss overrides this whole function with the boss's own rules.
func on_unit_died(u: RaidUnit, sacrificed: bool) -> void:
	if u.faction == "enemy":
		enemies.erase(u)
		ledger_v2.on_kill(u.mass)
		if not u.warden_pack:   # a warden's own pack drops nothing (WardenLogic.pack_spec)
			# kills drop essence at the corpse, carrying the enemy's mass
			_drop_motes(u.global_position, u.mass, int(rcfg().get("essence", {}).get("per_living", 1)), false)
		RaidFx.ring(fx_root, u.global_position, Palette.c("living", 0.6), 26.0, 0.3, 2.0)
		if not u.warden_pack:
			_roll_ding(u.global_position)
		held_clear.on_enemy_died()
	else:
		allies.erase(u)
		if u.role == "party":
			party_died.append(u.uid)
		# a fallen undead returns its mass to the field; massless ones drop mass-0 motes
		var m: float = u.mass if u.role in ["raised", "garrison"] else 0.0
		_drop_motes(u.global_position, m, int(rcfg().get("essence", {}).get("per_undead", 1)), true)
		if not sacrificed:
			RaidFx.ring(fx_root, u.global_position, Palette.c("undead", 0.4), 20.0, 0.25, 2.0)


func has_allies() -> bool:
	for a in allies:
		if is_instance_valid(a) and a.alive:
			return true
	return false


## THE SACRIFICE CHAIN (MECHANICS 5.0): a lethal hit on Relish consumes the nearest ally of the
## lowest available rank (chaff, soldier, elite, big undead), in the dungeon and in Vei's fight alike.
func sacrifice_nearest_ally() -> void:
	var pool: Array = []
	var cands: Array = []
	for a in allies:
		if not is_instance_valid(a) or not a.alive:
			continue
		pool.append(a)
		cands.append({"rank": RaidLogic.ally_rank(a.role, a.tier),
			"dist": a.global_position.distance_to(relish.global_position)})
	var k := RaidLogic.sacrifice_pick(cands)
	if k < 0:
		return
	var best: RaidUnit = pool[k]
	danger_hit()
	RaidFx.soul_link(fx_root, best.global_position, relish.global_position)
	RaidFx.ring(fx_root, best.global_position, Palette.c("danger"), 34.0, 0.45, 3.0)
	RaidFx.ring(fx_root, relish.global_position, Palette.c("danger"), 26.0, 0.45, 2.0)
	best.die(true)


## The danger edge pulses: Relish was hit, or a unit was spent for her.
func danger_hit() -> void:
	if danger != null:
		danger.hit()


## A warden's tell is aimed at Relish (call each physics frame it holds).
func danger_targeted() -> void:
	if danger != null:
		danger.targeted()
	if capture != null:
		capture.on_targeted()


## Alive allies by sacrifice rank, for the HUD ward line.
func ward_counts() -> Dictionary:
	var out := {"chaff": 0, "soldier": 0, "elite": 0, "big": 0}
	var names := ["chaff", "soldier", "elite", "big"]
	for a in allies:
		if is_instance_valid(a) and a.alive:
			var k: String = names[RaidLogic.ally_rank(a.role, a.tier)]
			out[k] = int(out[k]) + 1
	return out


## The enemy an undead of `radius` at `pos` should fight: the nearest by walking distance within
## ally_engage_px (the warden counts too), else null.
func nearest_enemy_of(pos: Vector2, radius := 0.0):
	var best = null
	var bd := ally_engage_px
	for e in enemies:
		if not is_instance_valid(e) or not e.alive:
			continue
		var d: float = pos.distance_to(e.global_position)
		if d < bd:
			# the leash is walking distance: a foe behind a wall counts at the cost of the doorway
			# (route_dist is never shorter than the straight line, so the check above prunes safely)
			d = LayoutLogic.route_dist(layout, pos, e.global_position, radius)
			if d < bd:
				bd = d
				best = e
	var w = warden_run.target_in(pos, bd, radius)   # the warden is a target but not an `enemies` entry
	if w != null:
		best = w
	return best


## Loot the warden's chest holds, in the loot shape (RaidLoot, rolled on rng_loot).
func chest_loot() -> Dictionary:
	var fort: Dictionary = seed_data.get("fort", {})
	var owned: Array = []
	if _from_run:
		owned = Game.state.view_inventory().get("blueprints", [])
	var info := {"tier": fort_tier(), "archetype": str(seed_data.get("warden", {}).get("archetype", "")),
		"first_clear": bool(fort.get("first_clear", false)), "chest_husk": bool(seed_data.get("chest_husk", false)),
		"yield_mult": float(fort.get("yield_mult", 1.0))}
	return RaidLoot.chest(rng_loot, info, owned, lcfg())


## A living kill may ding a remnant: it drops as a pickup at the corpse (it joins found_loot only
## when Relish walks over it; whatever is left on the floor at the end is lost).
func _roll_ding(pos: Vector2) -> void:
	var fort: Dictionary = seed_data.get("fort", {})
	var rem := RaidLoot.ding(rng_loot, fort_tier(), str(seed_data.get("warden", {}).get("archetype", "")),
		float(fort.get("yield_mult", 1.0)), lcfg())
	if rem.is_empty():
		return
	var pk := RaidPickup.new()
	pk.raid = self
	pk.remnant = rem
	pk.position = resolve_walls(pos, 6.0)
	units_root.add_child(pk)


## Relish reached a pickup: its item joins found_loot (RaidLoot.pickup_loot by kind; a ding's
## remnant today), with the ding fx and "+1".
func collect_pickup(pk: RaidPickup) -> void:
	if _ended or not pk.is_in_group("raid_pickups"):
		return
	pk.remove_from_group("raid_pickups")   # queue_free is deferred; the count must drop now
	found_loot = RaidLogic.merge_loot(found_loot, RaidLoot.pickup_loot(pk.kind, pk.remnant))
	RaidFx.ding(fx_root, pk.global_position, lcfg().get("ding", {}).get("fx", {}))
	pk.queue_free()


## Pickups still lying on the floor (lost if the run ends now).
func pickups_left() -> int:
	return get_tree().get_node_count_in_group("raid_pickups")


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
	for i in n:
		var ang := rng_combat.randf() * TAU
		var spd := rng_combat.randf_range(30.0, 70.0)
		spawn_mote(pos + Vector2(rng_combat.randf_range(0, 6), 0).rotated(ang), float(parts[i]), recycled,
			Vector2(spd, 0).rotated(ang))


# --- carried cluster ---
## Angle of a clock slot: where the mote COUNTS (enclosure, bot aim, absorb). No spin in it, so it
## is the same with and without reduced motion; the spin is only drawn (carry_draw_offset).
func carry_angle(slot: int) -> float:
	var e: Dictionary = rcfg().get("essence", {})
	return RaidLogic.carry_slot_angle(slot, int(e.get("carry_max", 12)))


## Where a carried slot is DRAWN: its counted angle plus the cluster's shared spin (zero under
## reduced motion), at most carry_swing_px from the counted slot. Draw only: nothing that scores, aims or collides may read it.
func carry_draw_angle(slot: int) -> float:
	var e: Dictionary = rcfg().get("essence", {})
	var swing := RaidLogic.carry_swing_rad(float(e.get("carry_swing_px", 3.0)), float(e.get("carry_orbit_px", 24.0)))
	return carry_angle(slot) + RaidLogic.carry_draw_spin(_carry_t, float(e.get("carry_spin_rad_s", 0.8)), swing, Pulse.reduced_motion)


## How far a carried mote is drawn from its counted spot (draw only).
func carry_draw_offset(slot: int) -> Vector2:
	var r := float(rcfg().get("essence", {}).get("carry_orbit_px", 24.0))
	return Vector2(r, 0).rotated(carry_draw_angle(slot)) - Vector2(r, 0).rotated(carry_angle(slot))


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
	raiser.show_feedback(g, trace)


## A released, scored circle (MECHANICS 5.3); see RaidRaise.
func perform_raise(g: Dictionary) -> void:
	raiser.perform(g)


# --------------------------------------------------------------- endings -----
## A window close mid-run ends it now (IDLE I5 stand-in, RaidEndings.close_request): a dungeon as a
## retreat paying the last checkpoint (a death or victory beat already playing stands), the boss as a loss keeping the
## backups spent (or the win, once Vei broke). The signal runs synchronously: the router applies the
## result before the quit completes.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and endings != null:
		if capture != null:
			capture.closing = true
		endings.close_request()
		if capture != null:
			capture.flush_unfinished("closed")   # standalone: no close_request ending, so the record is written here
	elif what == NOTIFICATION_PREDELETE and capture != null:
		capture.flush_unfinished("freed")   # freed with no ending (a swap away): what there is



## Thin forwards to RaidEndings for what other files call. The result hooks stay here so the boss
## scene can override them.
func confirm_exit() -> void:
	endings.confirm_exit()


func on_relish_died() -> void:
	endings.on_relish_died()


func can_retreat() -> bool:
	return endings.can_retreat()


func try_retreat() -> void:
	endings.try_retreat()


func exit_hint_ready() -> bool:
	return endings.exit_hint_ready()


func try_phylactery() -> bool:
	return endings.try_phylactery()


func phylactery_left() -> int:
	return endings.phylactery_left()


func _exit_result() -> Dictionary:
	return endings.build_result("retreated")


func _death_result() -> Dictionary:
	return endings.build_result("relish_died")


func _finish(result: Dictionary) -> void:
	endings.finish(result)
