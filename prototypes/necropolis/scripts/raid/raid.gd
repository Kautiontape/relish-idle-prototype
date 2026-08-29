extends Node2D
## The RAID scene: top-down arena raid on one of Vei's fortresses.
## Contract: setup(seed_data) → play → finished(result) exactly once.
## Standalone-safe: launched directly it seeds itself via demo_seed().

signal finished(result: Dictionary)

const GROUND := Color("#0d0d14")
const GRID_LINE := Color(0.24, 0.24, 0.34, 0.16)
const GREEN := Color("#39ff9e")
const ORANGE := Color("#ff6a2b")
const VIOLET := Color("#c04cff")
const GOLD := Color("#fff3d0")
const DANGER := Color("#ff2d55")

const SPATIAL_CELL := 56.0

var seed_data := {}
var layout := {}
var ledger: RaidLogic.Ledger = null
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

var _grid := {}
var _setup_called := false
var _built := false
var _standalone := false
var _ended := false
var _finished := false


func rcfg() -> Dictionary:
	return ConfigDb.data.get("raid", {})


func is_boss() -> bool:
	return bool(seed_data.get("boss", false))


func demo_seed() -> Dictionary:
	return {"fort_id": "vespers", "name": "Vespers", "tier": 2,
		"cap": 160.0, "living": 120.0, "undead": 10.0, "dead": 20.0,
		"boss": false, "quality": 1.5}


func _ready() -> void:
	if not _setup_called and get_tree().current_scene == self:
		setup(demo_seed())
	elif _setup_called and not _built:
		_build()


func setup(sd: Dictionary) -> void:
	seed_data = sd.duplicate(true)
	_setup_called = true
	if is_inside_tree() and not _built:
		_build()


func _build() -> void:
	_built = true
	_standalone = get_tree().current_scene == self
	var cfg := rcfg()
	var fort_id := str(seed_data.get("fort_id", "fort"))
	var tier := int(seed_data.get("tier", 1))
	layout = RaidLogic.gen_layout(fort_id, tier, is_boss(), cfg)
	ledger = RaidLogic.Ledger.new(float(seed_data.get("dead", 0.0)), float(seed_data.get("cap", 100.0)))

	# --- walls (the showpiece) ---
	var glow: float = float(cfg.get("layout", {}).get("wall_glow_px", 26.0))
	for wrect in layout["walls"]:
		var seg := RaidWall.new()
		add_child(seg)
		seg.setup(wrect, glow)

	units_root = Node2D.new()
	add_child(units_root)
	fx_root = Node2D.new()
	add_child(fx_root)

	# --- Relish just inside the southernmost door ---
	relish = RaidRelish.new()
	relish.position = layout["spawn"]
	units_root.add_child(relish)
	relish.configure(self)

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
	var arena: Vector2 = layout["size"]
	cam.zoom = Vector2.ONE * clampf(1600.0 / (arena.x + float(ccam.get("view_pad_px", 120.0))),
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

	_build_extra()
	queue_redraw()


## Standard fortress population (enemies + garrison). The boss scene replaces this.
func _populate_raid(cfg: Dictionary, fort_id: String, tier: int) -> void:
	var living := float(seed_data.get("living", 0.0))
	var cap := float(seed_data.get("cap", 100.0))
	if living > 0.05:
		var n := RaidLogic.enemy_count(living, cap, cfg)
		var mpe := living / n
		var spots := RaidLogic.populate_enemies(fort_id, layout, n, tier, cfg)
		for s in spots:
			var u := spawn_unit("enemy", s["kind"], s["pos"])
			u.mass = mpe
			u.home_room = layout["rooms"][s["room"]]
	# allied garrison undead near her spawn (the fort's own undead — not ledger mass)
	var gn := RaidLogic.garrison_count(float(seed_data.get("undead", 0.0)), cfg)
	for i in gn:
		var ang := TAU * i / maxf(1.0, gn) + 0.4
		var pos: Vector2 = relish.position + Vector2(54.0 + (i % 3) * 22.0, 0).rotated(ang)
		spawn_unit("ally", "chaff", resolve_walls(pos, 8.0))


## Boss hook — overridden by VeiBoss.
func _build_extra() -> void:
	pass


func _post_physics(_delta: float) -> void:
	pass


# ----------------------------------------------------------------- runtime ---
func _physics_process(delta: float) -> void:
	if not _built or _ended:
		return
	_rebuild_grid()
	_cam_follow()
	_post_physics(delta)


## Follow Relish, but never waste the frame on void: clamp the view to the
## arena, and center any axis where the arena is smaller than the viewport.
func _cam_follow() -> void:
	var arena: Vector2 = layout["size"]
	var view: Vector2 = get_viewport_rect().size / cam.zoom.x
	var t := relish.position
	var m := 60.0
	if view.x >= arena.x + 2.0 * m:
		t.x = arena.x * 0.5
	else:
		t.x = clampf(t.x, view.x * 0.5 - m, arena.x - view.x * 0.5 + m)
	if view.y >= arena.y + 2.0 * m:
		t.y = arena.y * 0.5
	else:
		t.y = clampf(t.y, view.y * 0.5 - m, arena.y - view.y * 0.5 + m)
	cam.position = t


func _process(_delta: float) -> void:
	if not _built:
		return
	queue_redraw()  # floor grid is static, but cheap; keeps draw order simple


func _draw() -> void:
	if layout.is_empty():
		return
	var size: Vector2 = layout["size"]
	draw_rect(Rect2(Vector2.ZERO, size), GROUND)
	var step: float = float(rcfg().get("layout", {}).get("grid_step_px", 128.0))
	var x := step
	while x < size.x:
		draw_line(Vector2(x, 0), Vector2(x, size.y), GRID_LINE, 1.0)
		x += step
	var y := step
	while y < size.y:
		draw_line(Vector2(0, y), Vector2(size.x, y), GRID_LINE, 1.0)
		y += step


func _unhandled_input(ev: InputEvent) -> void:
	if not _built or _ended:
		return
	if trance.handle_input(ev):
		get_viewport().set_input_as_handled()
		return
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and ev.pressed:
		var w := screen_to_world(ev.position)
		relish.move_target = w
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


func on_unit_died(u: RaidUnit, sacrificed: bool) -> void:
	if u.faction == "enemy":
		enemies.erase(u)
		ledger.on_kill(u.mass)
		# kills drop essence at the corpse, carrying the enemy's mass
		spawn_orb(u.global_position, u.mass, Vector2(randf_range(30, 70), 0).rotated(randf() * TAU))
		RaidFx.ring(fx_root, u.global_position, Color(ORANGE.r, ORANGE.g, ORANGE.b, 0.6), 26.0, 0.3, 2.0)
	else:
		allies.erase(u)
		if u.ledger_mass:
			ledger.on_chaff_death(u.mass)
		if u.kind == "soldier":
			army_lost["soldier"] += 1
		elif u.kind == "elite":
			army_lost["elite"] += 1
		if not sacrificed:
			RaidFx.ring(fx_root, u.global_position, Color(GREEN.r, GREEN.g, GREEN.b, 0.4), 20.0, 0.25, 2.0)
		_on_ally_died(u)


## Boss hook (corpse remnants for Vei's revive).
func _on_ally_died(_u: RaidUnit) -> void:
	pass


func has_allies() -> bool:
	for a in allies:
		if is_instance_valid(a) and a.alive:
			return true
	return false


## THE CONDUIT RULE: a lethal hit on Relish consumes the nearest allied undead.
func sacrifice_nearest_ally() -> void:
	var best: RaidUnit = null
	var bd := INF
	for a in allies:
		if not is_instance_valid(a) or not a.alive:
			continue
		var d: float = a.global_position.distance_to(relish.global_position)
		if d < bd:
			bd = d
			best = a
	if best == null:
		return
	RaidFx.soul_link(fx_root, best.global_position, relish.global_position)
	RaidFx.ring(fx_root, best.global_position, DANGER, 34.0, 0.45, 3.0)
	RaidFx.ring(fx_root, relish.global_position, DANGER, 26.0, 0.45, 2.0)
	best.die(true)


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


# --------------------------------------------------------------- spatial -----
func _rebuild_grid() -> void:
	_grid.clear()
	for u in allies:
		_grid_put(u)
	for u in enemies:
		_grid_put(u)
	if relish != null and relish.alive:
		_grid_put(relish)


func _grid_put(u: Node2D) -> void:
	var k := Vector2i(int(u.position.x / SPATIAL_CELL), int(u.position.y / SPATIAL_CELL))
	if not _grid.has(k):
		_grid[k] = []
	_grid[k].append(u)


func separation_push(u: Node2D) -> Vector2:
	var sep: float = float(rcfg().get("combat", {}).get("separation_px", 26.0))
	var out := Vector2.ZERO
	var c := Vector2i(int(u.position.x / SPATIAL_CELL), int(u.position.y / SPATIAL_CELL))
	for dy in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			var k := Vector2i(c.x + dx, c.y + dy)
			if not _grid.has(k):
				continue
			for o in _grid[k]:
				if o == u or not is_instance_valid(o):
					continue
				var d: Vector2 = u.position - o.position
				var l := d.length()
				if l < sep and l > 0.01:
					out += d / l * (1.0 - l / sep)
				elif l <= 0.01:
					out += Vector2(randf() - 0.5, randf() - 0.5)
	return out


## Keep a point inside the arena and out of internal walls (slide-friendly).
func resolve_walls(p: Vector2, r: float) -> Vector2:
	var size: Vector2 = layout["size"]
	var t: float = layout["wall_t"]
	p.x = clampf(p.x, t + r, size.x - t - r)
	p.y = clampf(p.y, t + r, size.y - t - r)
	for pass_i in 2:
		for wrect in layout["inner_walls"]:
			var g: Rect2 = (wrect as Rect2).grow(r)
			if not g.has_point(p):
				continue
			var left := p.x - g.position.x
			var right := g.end.x - p.x
			var top := p.y - g.position.y
			var bottom := g.end.y - p.y
			var m := minf(minf(left, right), minf(top, bottom))
			if m == left:
				p.x = g.position.x
			elif m == right:
				p.x = g.end.x
			elif m == top:
				p.y = g.position.y
			else:
				p.y = g.end.y
	return p


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


func set_trance(active: bool) -> void:
	trance_active = active


func show_trace_feedback(g: Dictionary, trace: PackedVector2Array) -> void:
	var fb := RaidTraceFeedback.new()
	fb.trace = trace
	fb.fitted_center = g["center"]
	fb.fitted_radius = g["radius"]
	fb.score = int(g["score"])
	fb.valid = g["valid"]
	fx_root.add_child(fb)


## A released, scored circle: consume enclosed essence, raise undead.
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
		var ang := TAU * i / float(spec["count"]) + randf() * 0.8
		var pos: Vector2 = relish.global_position + Vector2(ring_px + randf_range(-10, 26), 0).rotated(ang)
		var u := spawn_unit("ally", str(spec["kind"]), resolve_walls(pos, 10.0), true)
		if str(spec["kind"]) == "chaff":
			u.ledger_mass = true
			u.mass = float(spec["unit_mass"])
	RaidFx.ring(fx_root, relish.global_position, GREEN, ring_px + 26.0, 0.5, 3.0)


# --------------------------------------------------------------- endings -----
func request_exit() -> void:
	hud.open_exit_dialog()


func confirm_exit() -> void:
	if _ended:
		return
	_ended = true
	trance.force_end()
	RaidFx.ring(fx_root, relish.global_position, VIOLET, 60.0, 0.5, 4.0)
	_finish(_exit_result())


func on_relish_died() -> void:
	if _ended:
		return
	_ended = true
	trance.force_end()
	RaidFx.ring(fx_root, relish.global_position, DANGER, 90.0, 0.8, 4.0)
	RaidFx.ring(fx_root, relish.global_position, VIOLET, 50.0, 0.8, 3.0)
	get_tree().create_timer(0.9).timeout.connect(func() -> void: _finish(_death_result()))


func _exit_result() -> Dictionary:
	return ledger.result(str(seed_data.get("fort_id", "")), false, rcfg())


func _death_result() -> Dictionary:
	return ledger.result(str(seed_data.get("fort_id", "")), true, rcfg())


func _finish(result: Dictionary) -> void:
	if _finished:
		return
	_finished = true
	_ended = true
	Engine.time_scale = 1.0
	finished.emit(result)
	if _standalone:
		hud.show_result(result)
