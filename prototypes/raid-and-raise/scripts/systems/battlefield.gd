class_name Battlefield
extends Node2D
## One combat arena: nav region + walls + units + essence + corpses + fx.
## Used by the raid (chamber chain) and by every playroom. Owns the force
## field math (§6), the sacrifice chain (§8.3), and loot drops (§9).

signal relish_died
signal enemy_killed(unit: RRUnit)
signal no_chaff_warning

var rng := RandomNumberGenerator.new()
var corpses_root: Node2D
var units_root: Node2D
var fx_root: Node2D
var nav_region: NavigationRegion2D
var camera: Camera2D
var overlay: TranceOverlay
var relish: RRUnit = null
var trance_active := false
var outline := PackedVector2Array()
var obstacles: Array = []
var doorways: Array = []  # corridor centers, registered by the raid director

func _ready() -> void:
	corpses_root = Node2D.new()
	corpses_root.name = "Corpses"
	add_child(corpses_root)
	units_root = Node2D.new()
	units_root.name = "Units"
	units_root.y_sort_enabled = true
	add_child(units_root)
	fx_root = Node2D.new()
	fx_root.name = "Fx"
	add_child(fx_root)

func _exit_tree() -> void:
	Engine.time_scale = 1.0  # never leave a dead battlefield's trance dilation behind

## walkable: a single simple polygon (rooms ∪ corridors). obstacles: interior
## polygons carved out of the navmesh (pillars, bars — the obstacle course).
## Walls and obstacles double as segment collision; nav bakes with
## agent-radius erosion so doorways/gaps stay generous (§13.3).
func build_arena(walkable: PackedVector2Array, obstacle_polys: Array = []) -> void:
	outline = walkable
	obstacles = obstacle_polys
	nav_region = NavigationRegion2D.new()
	add_child(nav_region)
	var np := NavigationPolygon.new()
	np.agent_radius = float(ConfigDb.v("stats", "unit_radius_px")) + 2.0
	var src := NavigationMeshSourceGeometryData2D.new()
	src.add_traversable_outline(walkable)
	for ob in obstacles:
		src.add_obstruction_outline(ob)
	NavigationServer2D.bake_from_source_geometry_data(np, src)
	if np.get_polygon_count() == 0:
		# Fallback path if baking is unavailable: triangulate the raw outlines.
		np = NavigationPolygon.new()
		np.add_outline(walkable)
		for ob in obstacles:
			np.add_outline(ob)
		np.make_polygons_from_outlines()
	nav_region.navigation_polygon = np

	var walls := StaticBody2D.new()
	walls.collision_layer = 1
	var poly := CollisionPolygon2D.new()
	poly.build_mode = CollisionPolygon2D.BUILD_SEGMENTS
	poly.polygon = walkable
	walls.add_child(poly)
	for ob in obstacles:
		var op := CollisionPolygon2D.new()
		op.build_mode = CollisionPolygon2D.BUILD_SEGMENTS
		op.polygon = ob
		walls.add_child(op)
	add_child(walls)
	queue_redraw()

func make_camera(center: Vector2) -> Camera2D:
	camera = Camera2D.new()
	camera.position = center
	add_child(camera)
	camera.make_current()
	overlay = TranceOverlay.new()
	camera.add_child(overlay)
	return camera

func _process(_delta: float) -> void:
	# Debug knob, not a game feature (§14 bans pinch zoom): desktop screens
	# render the portrait chamber small, so testers can scale the view.
	if camera != null:
		var z := float(ConfigDb.v("stats", "debug_view_zoom"))
		if absf(camera.zoom.x - z) > 0.001:
			camera.zoom = Vector2(z, z)

# ---- Units ----

func spawn_unit(u: RRUnit, pos: Vector2) -> RRUnit:
	u.battlefield = self
	u.position = clamp_to_nav(pos)
	units_root.add_child(u)
	u.died.connect(_on_unit_died)
	if u.kind == RRUnit.Kind.RELISH:
		relish = u
	return u

func clamp_to_nav(pos: Vector2) -> Vector2:
	var map := get_world_2d().navigation_map
	if NavigationServer2D.map_get_iteration_id(map) == 0:
		return pos  # map not synced yet (first frame) — trust authored positions
	return NavigationServer2D.map_get_closest_point(map, pos)

func all_units() -> Array:
	var out: Array = []
	for u in units_root.get_children():
		if u is RRUnit:
			out.append(u)
	return out

func living(faction: int) -> Array:
	var out: Array = []
	for u in all_units():
		if u.faction == faction and u.is_targetable():
			out.append(u)
	return out

func hostiles_of(u: RRUnit) -> Array:
	return living(RRUnit.Faction.ENEMY if u.faction == RRUnit.Faction.PLAYER else RRUnit.Faction.PLAYER)

func hostile_in_reach(u: RRUnit) -> RRUnit:
	var best: RRUnit = null
	var best_d := INF
	for h in hostiles_of(u):
		var d := u.global_position.distance_to(h.global_position)
		if d <= u._melee_reach(h) and d < best_d:
			best_d = d
			best = h
	return best

func active_hostiles_near(pos: Vector2, radius: float) -> Array:
	var out: Array = []
	for u in living(RRUnit.Faction.ENEMY):
		if u.global_position.distance_to(pos) <= radius:
			out.append(u)
	return out

## Escort anticipation (playtest feedback): idle minions don't trail Relish —
## they move to (and through) the door she LOOKS like she's heading toward,
## so they enter the next chamber ahead of her. Heading is her live velocity,
## so backtracking and forks work without any scripting.
func escort_door_goal() -> Vector2:
	if relish == null or not is_instance_valid(relish) or not relish.alive or doorways.is_empty():
		return Vector2.INF
	var vel := relish.velocity
	if vel.length() < float(ConfigDb.v("stats", "escort_min_relish_speed_px")):
		return Vector2.INF
	var dirn := vel.normalized()
	var best := Vector2.INF
	var best_d := INF
	for d in doorways:
		var to: Vector2 = d - relish.global_position
		var dist := to.length()
		if dist < 60.0 or dist > float(ConfigDb.v("stats", "escort_door_range_px")):
			continue
		if dirn.dot(to / dist) < float(ConfigDb.v("stats", "escort_door_cone_dot")):
			continue
		if dist < best_d:
			best_d = dist
			best = d + dirn * float(ConfigDb.v("stats", "escort_through_px"))
	return best

func player_minion_centroid() -> Vector2:
	var sum := Vector2.ZERO
	var n := 0
	for u in living(RRUnit.Faction.PLAYER):
		if u.kind == RRUnit.Kind.RELISH:
			continue
		sum += u.global_position
		n += 1
	return sum / n if n > 0 else Vector2.INF

func count_kind(kind: int) -> int:
	var n := 0
	for u in living(RRUnit.Faction.PLAYER):
		if u.kind == kind:
			n += 1
	return n

func nearest_player_of_kind(kind: int, pos: Vector2) -> RRUnit:
	var best: RRUnit = null
	var best_d := INF
	for u in living(RRUnit.Faction.PLAYER):
		if u.kind != kind:
			continue
		var d := pos.distance_to(u.global_position)
		if d < best_d:
			best_d = d
			best = u
	return best

# ---- Force field (§6): steering bias, never hard displacement ----
## steer += Σ k·Charm/d (toward) − Σ k·Dread/d (away), within radius, with d
## measured in 100px units (raw px makes F invisible at these magnitudes).
## Total bias clamped to 40% of the agent's max speed — keeps nav stable.

func field_bias(u: RRUnit) -> Vector2:
	var radius := float(ConfigDb.v("stats", "field_radius_px"))
	var k := float(ConfigDb.v("stats", "field_strength"))
	var bias := Vector2.ZERO
	for h in hostiles_of(u):
		var charm: float = h.stats.charm
		var dread: float = h.stats.dread
		if charm <= 0.0 and dread <= 0.0:
			continue
		var d := u.global_position.distance_to(h.global_position)
		if d > radius or d < 1.0:
			continue
		var dir: Vector2 = (h.global_position - u.global_position) / d
		var d_norm := d / 100.0
		bias += dir * (k * charm / d_norm)
		bias -= dir * (k * dread / d_norm)
	return bias.limit_length(float(ConfigDb.v("stats", "field_bias_clamp")) * u.max_speed())

# ---- Sacrifice chain (§8.3) ----
## Relish is hit → nearest chaff dies in her place → else nearest permanent
## (loud warning) → else Relish dies and EVERYTHING is lost.

func relish_hit(_attacker: RRUnit) -> void:
	if relish == null or not relish.alive:
		return
	if GameState.debug.god:
		spawn_ding(relish.global_position, "(god mode)", Color(0.6, 0.6, 0.65))
		return
	if relish.iframes > 0.0:
		return
	relish.iframes = float(ConfigDb.v("stats", "sacrifice_iframes_s"))
	var chaff := nearest_player_of_kind(RRUnit.Kind.CHAFF, relish.global_position)
	if chaff != null:
		_sacrifice(chaff)
		return
	var perm := nearest_player_of_kind(RRUnit.Kind.PERMANENT, relish.global_position)
	if perm != null:
		no_chaff_warning.emit()
		_sacrifice(perm)
		return
	relish.die()  # nothing remained to die for her

func _sacrifice(u: RRUnit) -> void:
	var fx := FxLine.new()
	fx.from = relish.global_position
	fx.to = u.global_position
	fx_root.add_child(fx)
	u.die()  # a sacrificed permanent with Persistence may still rise (§8.3)

# ---- Death, drops (§9/§11) ----

func _on_unit_died(u: RRUnit) -> void:
	var c := Corpse.new()
	c.radius = u.radius()
	c.color = u.color
	c.position = u.global_position
	corpses_root.add_child(c)
	if u.echoes.has("volatile"):
		var dmg: float = u.echoes["volatile"] * float(ConfigDb.data["echoes"]["combat"]["volatile"]["per_point"])
		aoe_damage(u.global_position, float(ConfigDb.data["echoes"]["volatile_radius_px"]), dmg, u.faction)
		spawn_ding(u.global_position, "BOOM", Color(1.0, 0.6, 0.2))
	for ally in living(u.faction):
		ally.notify_ally_died()
	if u.kind == RRUnit.Kind.RELISH:
		relish_died.emit()
		return
	if u.faction == RRUnit.Faction.ENEMY:
		GameState.kills += 1
		_drop_loot(u)
		enemy_killed.emit(u)

func _drop_loot(u: RRUnit) -> void:
	var n := Loot.essence_count(rng, int(u.stats.beef))
	if u.is_boss:
		n += int(ConfigDb.v("stats", "boss_essence_burst"))  # the climax shower
	spawn_essence(u.global_position, n)
	GameState.essence_dropped += n

	var rcfg: Dictionary = ConfigDb.data["rarity"]
	var remnant_rolls := 0
	if u.is_boss:
		remnant_rolls = rng.randi_range(int(rcfg["boss_remnant_min"]), int(rcfg["boss_remnant_max"]))
	elif u.is_elite:
		if rng.randf() < float(rcfg["elite_remnant_chance"]):
			remnant_rolls = 1
	elif rng.randf() < float(rcfg["remnant_drop_chance"]):
		remnant_rolls = 1
	for i in remnant_rolls:
		var r := Loot.roll_remnant(rng)
		GameState.add_remnant(r)
		spawn_ding(u.global_position + Vector2(0, -18.0 * i),
			"%s [%s]" % [Loot.remnant_label(r), r["rarity"]], Loot.rarity_color(r["rarity"]))

	var husk_chance := 0.0
	if u.is_boss:
		husk_chance = float(rcfg["husk_drop_boss"])
	elif u.is_elite:
		husk_chance = float(rcfg["husk_drop_elite"])
	if husk_chance > 0.0 and rng.randf() < husk_chance:
		var husk_id := Loot.roll_husk(rng)
		GameState.add_husk(husk_id)
		spawn_ding(u.global_position + Vector2(0, 20), "HUSK: %s" % ConfigDb.husk(husk_id)["name"], Color(0.85, 0.75, 1.0))

func aoe_damage(pos: Vector2, radius: float, dmg: float, src_faction: int) -> void:
	for u in all_units():
		if u.faction == src_faction or not u.is_targetable():
			continue
		if u.global_position.distance_to(pos) <= radius + u.radius():
			u.take_hit(null, dmg)

# ---- Spawn helpers ----

func spawn_essence(pos: Vector2, n: int) -> void:
	for i in n:
		var e := EntityFactory.make_essence()
		e.battlefield = self
		e.position = pos + Vector2(rng.randf_range(-12, 12), rng.randf_range(-12, 12))
		add_child(e)

## Summon landing: the chaff grows out of the ground beside Relish.
func spawn_chaff_grown(mult: float) -> void:
	if relish == null or not is_instance_valid(relish) or not relish.alive:
		return
	var ring := float(ConfigDb.v("circle", "grow_ring_px"))
	var pos := relish.global_position + Vector2(ring, 0).rotated(rng.randf_range(0, TAU))
	var u := EntityFactory.make_chaff(mult)
	spawn_unit(u, pos)
	u.grow_in(float(ConfigDb.v("circle", "grow_time_s")))

func essence_list() -> Array:
	var out: Array = []
	for e in get_tree().get_nodes_in_group("rr_essence"):
		if e.battlefield == self:
			out.append(e)
	return out

func spawn_bolt(src: RRUnit, dst: RRUnit) -> void:
	var b := Projectile.new()
	b.src = src
	b.src_faction = src.faction
	b.target = dst
	b.dmg = float(ConfigDb.v("stats", "magic_bolt_dmg_per_magic")) * src.stats.magic
	b.color = Color(0.5, 0.9, 1.0) if src.faction == RRUnit.Faction.PLAYER else Color(1.0, 0.55, 0.3)
	b.position = src.global_position
	fx_root.add_child(b)

func spawn_ding(pos: Vector2, text: String, color: Color) -> void:
	var d := FxDing.new()
	d.text = text
	d.color = color
	d.position = pos
	fx_root.add_child(d)

func set_trance(on: bool) -> void:
	trance_active = on
	if overlay != null:
		overlay.visible = on

func screen_to_world(p: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform().affine_inverse() * p

# ---- Debug helpers (force-spawn etc.) ----

func clear_faction(faction: int) -> void:
	for u in all_units():
		if u.faction == faction and u.alive and u.kind != RRUnit.Kind.RELISH:
			u.queue_free()

func clear_chaff() -> void:
	for u in all_units():
		if u.kind == RRUnit.Kind.CHAFF:
			u.queue_free()

func _draw() -> void:
	if outline.size() < 3:
		return
	draw_colored_polygon(outline, Color(0.1, 0.1, 0.125))
	var closed := outline.duplicate()
	closed.append(outline[0])
	draw_polyline(closed, Color(0.24, 0.23, 0.28), 5.0)
	for ob in obstacles:
		draw_colored_polygon(ob, Color(0.2, 0.19, 0.24))
		var obc: PackedVector2Array = ob.duplicate()
		obc.append(ob[0])
		draw_polyline(obc, Color(0.32, 0.3, 0.38), 4.0)
