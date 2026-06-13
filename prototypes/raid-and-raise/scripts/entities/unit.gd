class_name RRUnit
extends CharacterBody2D
## The ONE entity code path (§1). Relish, permanents, chaff, and enemies are
## all this class, differing only by config and faction. No special-cased
## combat logic per faction. Movement = NavigationAgent2D (avoidance on) plus
## force-field steering bias (§6). All coefficients live in ConfigDb.

enum Kind { RELISH, PERMANENT, CHAFF, ENEMY }
enum Faction { PLAYER, ENEMY }
enum Cmd { NONE, MOVE, HOLD, PATH }

signal died(unit: RRUnit)

# Identity (set once by EntityFactory.setup)
var kind: int = Kind.ENEMY
var faction: int = Faction.ENEMY
var stats: Dictionary = {"power": 0.0, "beef": 0.0, "speed": 0.0, "wits": 0.0,
	"charm": 0.0, "dread": 0.0, "magic": 0.0, "persistence": 0.0}
var cadence := 1.0
var base_hp := 20.0
var base_dmg := 2.0
var base_speed := 60.0
var display_name := ""
var color := Color.WHITE
var is_elite := false
var is_boss := false
var echoes: Dictionary = {}          # combat echo id -> points
var town_points := 0                 # town-side echo points (display only in Phase 1)
var source_remnants: Array = []

# Runtime
var hp := 1.0
var max_hp := 1.0
var alive := true
var active := true                   # raid chambers activate on entry
var rising := false
var rose_this_chamber := false
var selected := false
var battlefield = null               # Battlefield (untyped: avoids cyclic preload)
var target: RRUnit = null
var cmd: int = Cmd.NONE
var cmd_point := Vector2.ZERO
var cmd_path: Array = []             # lasso-drawn group path (world coords)
var path_offset := Vector2.ZERO      # per-unit formation offset along the path
var path_complete := false           # stroke released; finish then hold/drift
var path_override: Array = []        # Relish drag-path waypoints (world coords)
var relish_anchor := Vector2.INF     # auto-advance goal (raid director sets)
var iframes := 0.0

var grow_scale := 1.0               # rrawwwwr: summoned chaff grow in (visual only)
var nav: NavigationAgent2D
var _shape: CollisionShape2D
var _attack_cd := 0.0
var _retarget_t := 0.0
var _drift_t := 0.0
var _vengeful_t := 0.0
var _rise_t := 0.0
var _hit_flash := 0.0
var _knock := Vector2.ZERO
var _nav_goal := Vector2.INF

func setup(p: Dictionary) -> RRUnit:
	kind = p.get("kind", Kind.ENEMY)
	faction = p.get("faction", Faction.ENEMY)
	var s: Dictionary = p.get("stats", {})
	for k in stats:
		stats[k] = float(s.get(k, 0.0))
	cadence = float(p.get("cadence", 1.0))
	base_hp = float(p.get("base_hp", 20.0))
	base_dmg = float(p.get("base_dmg", 2.0))
	base_speed = float(p.get("base_speed", 60.0))
	display_name = p.get("name", "")
	color = Color(p.get("color", "#ffffff")) if p.get("color") is String else p.get("color", Color.WHITE)
	is_elite = p.get("elite", false)
	is_boss = p.get("boss", false)
	echoes = p.get("echoes", {})
	town_points = p.get("town_points", 0)
	source_remnants = p.get("source_remnants", [])
	max_hp = base_hp + float(ConfigDb.v("stats", "hp_per_beef")) * stats.beef
	hp = max_hp
	return self

# ---- Derived stats: read ConfigDb live so debug sliders bite immediately ----

func max_speed() -> float:
	return base_speed + float(ConfigDb.v("stats", "speed_per_speed")) * stats.speed

func damage() -> float:
	return base_dmg + float(ConfigDb.v("stats", "dmg_per_power")) * stats.power

func size_scale() -> float:
	return float(ConfigDb.v("stats", "size_base")) + float(ConfigDb.v("stats", "size_per_beef")) * stats.beef

func radius() -> float:
	var r := float(ConfigDb.v("stats", "unit_radius_px")) * size_scale()
	if kind == Kind.CHAFF:
		r *= float(ConfigDb.v("stats", "chaff_visual_scale"))
	return r

func is_targetable() -> bool:
	return alive and active and not rising

func _ready() -> void:
	_shape = CollisionShape2D.new()
	var c := CircleShape2D.new()
	c.radius = radius()
	_shape.shape = c
	add_child(_shape)
	collision_layer = 2
	collision_mask = 1  # walls only — separation between units is avoidance's job
	nav = NavigationAgent2D.new()
	nav.avoidance_enabled = true
	nav.radius = radius() + 2.0
	nav.neighbor_distance = 220.0
	nav.path_desired_distance = 10.0
	nav.target_desired_distance = 16.0
	# Relish gets priority when she moves (§15.2 input feel): she never takes
	# evasive action for her own minions — they yield to HER. Enemies stay
	# mutually solid (they're supposed to be in the way).
	# Avoidance layers: 1 = minions, 2 = Relish, 4 = enemies.
	if kind == Kind.RELISH:
		nav.avoidance_layers = 2
		nav.avoidance_mask = 4
		nav.avoidance_priority = 1.0
	elif faction == Faction.PLAYER:
		nav.avoidance_layers = 1
		nav.avoidance_mask = 1 | 2 | 4
		nav.avoidance_priority = 0.5
	else:
		nav.avoidance_layers = 4
		nav.avoidance_mask = 1 | 4
		nav.avoidance_priority = 0.7
	nav.velocity_computed.connect(_on_safe_velocity)
	add_to_group("rr_units")
	add_child(nav)
	# A NavigationAgent2D never runs avoidance — so velocity_computed never
	# fires and _on_safe_velocity never moves us — until a target has been
	# submitted once. Relish's swipe-path and flee branches feed raw velocities
	# without one, which left her frozen until the first tap (order_move) woke
	# the agent. Submit a no-op target so every unit is live from frame one.
	nav.target_position = global_position

func _process(_delta: float) -> void:
	queue_redraw()

func _physics_process(delta: float) -> void:
	iframes = maxf(0.0, iframes - delta)
	_hit_flash = maxf(0.0, _hit_flash - 3.0 * delta)
	_vengeful_t = maxf(0.0, _vengeful_t - delta)
	_knock = _knock.move_toward(Vector2.ZERO, 700.0 * delta)

	var desired := Vector2.ZERO
	if rising:
		_rise_t -= delta
		if _rise_t <= 0.0:
			_revive()
	elif alive and active and not (kind == Kind.ENEMY and GameState.debug.freeze):
		_retarget_t -= delta
		if _retarget_t <= 0.0 or not _valid_target():
			_retarget_t = float(ConfigDb.v("stats", "retarget_interval_s"))
			_choose_target()
		desired = _desired_velocity(delta) + _knock
		if kind != Kind.RELISH and faction == Faction.PLAYER:
			desired += _relish_push()  # she shoulders through her own dead
		if kind != Kind.RELISH and not GameState.debug.pacifist:
			_attack_cd -= delta
			_try_attack()
	nav.max_speed = max_speed()
	nav.velocity = desired.limit_length(max_speed())

func _on_safe_velocity(v: Vector2) -> void:
	if not alive or rising:
		return
	velocity = v
	move_and_slide()

# ---- Targeting (§5/§11): proximity × size by default; Wits locks the giant ----

func _valid_target() -> bool:
	return target != null and is_instance_valid(target) and target.is_targetable()

func _choose_target() -> void:
	if battlefield == null:
		return
	var hostiles: Array = battlefield.hostiles_of(self)
	if hostiles.is_empty():
		target = null
		return
	if kind != Kind.CHAFF and stats.wits >= float(ConfigDb.v("stats", "wits_lock_threshold")):
		# The killer's eye: lock the highest-Beef enemy, stick until it's down.
		if _valid_target():
			return
		var best: RRUnit = hostiles[0]
		for h in hostiles:
			if h.stats.beef > best.stats.beef:
				best = h
		target = best
	elif kind == Kind.CHAFF:
		target = _nearest(hostiles)
	else:
		var best_score := -1.0
		for h in hostiles:
			var d := maxf(20.0, global_position.distance_to(h.global_position))
			var score: float = h.size_scale() / d
			if score > best_score:
				best_score = score
				target = h

func _nearest(units: Array) -> RRUnit:
	var best: RRUnit = null
	var best_d := INF
	for u in units:
		var d := global_position.distance_to(u.global_position)
		if d < best_d:
			best_d = d
			best = u
	return best

# ---- Movement ----

func _desired_velocity(delta: float) -> Vector2:
	if kind == Kind.RELISH:
		return _relish_ai()
	if cmd == Cmd.PATH:
		return _follow_cmd_path()  # commands override fields (§5)
	if cmd == Cmd.MOVE:
		if global_position.distance_to(cmd_point) < 28.0:
			cmd = Cmd.HOLD
			_drift_t = float(ConfigDb.v("stats", "low_wits_drift_delay_s"))
		else:
			return _nav_velocity_to(cmd_point)  # player commands override fields (§5)
	if cmd == Cmd.HOLD:
		# High Wits holds a commanded position; low Wits drifts back to autopilot.
		if stats.wits < float(ConfigDb.v("stats", "wits_lock_threshold")):
			_drift_t -= delta
			if _drift_t <= 0.0:
				cmd = Cmd.NONE
		return Vector2.ZERO
	# Autopilot
	var v := Vector2.ZERO
	if _valid_target():
		if not _in_attack_range(target):
			v = _nav_velocity_to(target.global_position)
	elif faction == Faction.PLAYER and battlefield != null and battlefield.relish != null:
		var rel: RRUnit = battlefield.relish
		if rel.alive:
			var door: Vector2 = battlefield.escort_door_goal()
			if door != Vector2.INF:
				v = _nav_velocity_to(door)  # take point: through the door ahead of her
			elif global_position.distance_to(rel.global_position) > float(ConfigDb.v("stats", "follow_relish_distance_px")):
				v = _nav_velocity_to(rel.global_position)
	if battlefield != null:
		v += battlefield.field_bias(self)  # §6: bias, never hard displacement
	return v

func _nav_velocity_to(goal: Vector2) -> Vector2:
	if _nav_goal == Vector2.INF or _nav_goal.distance_to(goal) > 24.0:
		nav.target_position = goal
		_nav_goal = goal
	if nav.is_navigation_finished():
		return Vector2.ZERO
	return (nav.get_next_path_position() - global_position).normalized() * max_speed()

func _relish_ai() -> Vector2:
	# Relish never attacks (§5). Cowardly kiting; player overrides via §8.1.
	if path_override.size() > 0:
		var pt: Vector2 = path_override[0]
		if global_position.distance_to(pt) < 16.0:
			path_override.pop_front()
			return Vector2.ZERO
		return (pt - global_position).normalized() * max_speed()
	if cmd == Cmd.MOVE:
		if global_position.distance_to(cmd_point) < 18.0:
			cmd = Cmd.NONE
		else:
			return _nav_velocity_to(cmd_point)
	var flee_radius := float(ConfigDb.v("stats", "relish_flee_radius_px"))
	var threats: Array = battlefield.active_hostiles_near(global_position, flee_radius) if battlefield else []
	if threats.size() > 0:
		var flee := Vector2.ZERO
		for t in threats:
			var d := maxf(24.0, global_position.distance_to(t.global_position))
			flee += (global_position - t.global_position).normalized() * (flee_radius / d)
		var dir := flee.normalized()
		var centroid: Vector2 = battlefield.player_minion_centroid()
		if centroid != Vector2.INF:
			dir = (flee.normalized() * 0.7 + (centroid - global_position).normalized() * 0.5).normalized()
		return dir * max_speed()
	if relish_anchor != Vector2.INF and global_position.distance_to(relish_anchor) > 50.0:
		return _nav_velocity_to(relish_anchor)
	return Vector2.ZERO

# ---- Combat ----

func _melee_reach(t: RRUnit) -> float:
	return radius() + t.radius() + float(ConfigDb.v("stats", "melee_reach_px"))

func _in_attack_range(t: RRUnit) -> bool:
	var d := global_position.distance_to(t.global_position)
	if stats.magic > 0.0:
		return d <= float(ConfigDb.v("stats", "magic_bolt_range_px")) * 0.85
	return d <= _melee_reach(t)

func _try_attack() -> void:
	if _attack_cd > 0.0:
		return
	var swing: RRUnit = null
	if stats.magic > 0.0:
		if _valid_target() and global_position.distance_to(target.global_position) <= float(ConfigDb.v("stats", "magic_bolt_range_px")):
			swing = target
	else:
		if _valid_target() and global_position.distance_to(target.global_position) <= _melee_reach(target):
			swing = target
		elif battlefield != null:
			swing = battlefield.hostile_in_reach(self)  # fights what's in its face
	if swing == null:
		return
	_attack_cd = 1.0 / maxf(0.05, cadence * _frenzy_mult())
	if stats.magic > 0.0:
		battlefield.spawn_bolt(self, swing)
	else:
		_strike(swing)

func _frenzy_mult() -> float:
	if echoes.has("frenzy") and hp < max_hp * 0.5:
		return 1.0 + echoes["frenzy"] * float(ConfigDb.data["echoes"]["combat"]["frenzy"]["per_point"])
	return 1.0

func attack_damage_against(t: RRUnit) -> float:
	var dmg := damage()
	if stats.wits > 0.0:
		dmg *= 1.0 + float(ConfigDb.v("stats", "wits_antibeef_coeff")) * stats.wits * t.stats.beef
	if _vengeful_t > 0.0 and echoes.has("vengeful"):
		dmg *= 1.0 + echoes["vengeful"] * float(ConfigDb.data["echoes"]["combat"]["vengeful"]["per_point"])
	return dmg

func _strike(t: RRUnit) -> void:
	var dmg := attack_damage_against(t)
	t.take_hit(self, dmg)
	if echoes.has("life_drain"):
		# Doc-listed echo — the one sanctioned exception to "no healing exists".
		hp = minf(max_hp, hp + dmg * echoes["life_drain"] * float(ConfigDb.data["echoes"]["combat"]["life_drain"]["per_point"]))
	var kb := float(ConfigDb.v("stats", "knockback_base"))
	if echoes.has("heavy_blow"):
		kb *= 1.0 + echoes["heavy_blow"] * float(ConfigDb.data["echoes"]["combat"]["heavy_blow"]["per_point"])
	kb /= 1.0 + float(ConfigDb.v("stats", "knockback_beef_resist")) * t.stats.beef
	t.apply_knock((t.global_position - global_position).normalized() * kb * 8.0)

func apply_knock(v: Vector2) -> void:
	_knock = (_knock + v).limit_length(320.0)

## Bow wave: when moving Relish overlaps a minion, the minion gets shoved
## radially clear — works even on units holding a commanded post (physical
## yielding, not a command override).
func _relish_push() -> Vector2:
	if battlefield == null:
		return Vector2.ZERO
	var rel: RRUnit = battlefield.relish
	if rel == null or not is_instance_valid(rel) or not rel.alive or rel == self:
		return Vector2.ZERO
	if rel.velocity.length() < float(ConfigDb.v("stats", "escort_min_relish_speed_px")):
		return Vector2.ZERO
	var d := global_position.distance_to(rel.global_position)
	var clearance := rel.radius() + radius() + float(ConfigDb.v("stats", "relish_push_pad_px"))
	if d >= clearance:
		return Vector2.ZERO
	var away := global_position - rel.global_position
	if away.length() < 1.0:
		away = rel.velocity.orthogonal()  # dead-center overlap: shove sideways
	return away.normalized() * float(ConfigDb.v("stats", "relish_push_speed_px")) * (1.0 - d / clearance)

func take_hit(attacker: RRUnit, dmg: float) -> void:
	if not alive or rising:
		return
	if kind == Kind.RELISH:
		battlefield.relish_hit(attacker)  # the sacrifice chain (§8.3)
		return
	hp -= dmg
	_hit_flash = 1.0
	if hp <= 0.0:
		die()

func notify_ally_died() -> void:
	if echoes.has("vengeful"):
		_vengeful_t = float(ConfigDb.data["echoes"]["vengeful_duration_s"])

func die() -> void:
	if not alive:
		return
	alive = false
	selected = false
	target = null
	died.emit(self)  # battlefield: corpse, drops, volatile, vengeful broadcast
	if kind == Kind.PERMANENT and stats.persistence > 0.0 and not rose_this_chamber and battlefield != null:
		var chance := minf(float(ConfigDb.v("stats", "persistence_rise_cap")),
			float(ConfigDb.v("stats", "persistence_rise_per_point")) * stats.persistence)
		if battlefield.rng.randf() < chance:
			# Won't stay dead — once per chamber (§5/§11).
			rose_this_chamber = true
			rising = true
			_rise_t = float(ConfigDb.v("stats", "persistence_rise_delay_s"))
			visible = false
			_shape.set_deferred("disabled", true)
			return
	queue_free()

func _revive() -> void:
	rising = false
	alive = true
	hp = max_hp * float(ConfigDb.v("stats", "persistence_revive_hp_frac"))
	visible = true
	_shape.set_deferred("disabled", false)
	if battlefield != null:
		battlefield.spawn_ding(global_position, "RISES", Color(1.0, 0.85, 0.4))

func reset_chamber_flags() -> void:
	rose_this_chamber = false

# ---- Orders (coarse only: group-and-point / group-and-path, §8.1) ----

func order_move(point: Vector2) -> void:
	cmd = Cmd.MOVE
	cmd_point = point
	cmd_path.clear()
	path_override.clear()

## Off-screen reposition (chamber transition straggler gather): drop the unit at
## a new spot and wipe stale movement state so it re-paths from there cleanly.
func snap_to(pos: Vector2) -> void:
	global_position = pos
	velocity = Vector2.ZERO
	cmd = Cmd.NONE
	cmd_path.clear()
	path_override.clear()
	_nav_goal = Vector2.INF
	if nav != null:
		nav.target_position = pos

## Lasso-path: the whole selection follows one drawn path (still no per-unit
## micro). Waypoints stream in live while the player drags.
func order_path(offset: Vector2) -> void:
	cmd = Cmd.PATH
	cmd_path = []
	path_offset = offset
	path_complete = false

func append_path_point(p: Vector2) -> void:
	cmd_path.append(p + path_offset)

func finish_path() -> void:
	path_complete = true

func cancel_empty_path() -> void:
	if cmd == Cmd.PATH and cmd_path.is_empty():
		cmd = Cmd.NONE

func cancel_path() -> void:
	if cmd == Cmd.PATH:
		cmd = Cmd.NONE
		cmd_path.clear()

## Summon entrance: scale up from nothing with an overshoot (TRANS_BACK).
## Visual only — radius() for combat/physics is unaffected.
func grow_in(duration: float) -> void:
	grow_scale = 0.05
	_attack_cd = maxf(_attack_cd, duration)
	var tw := create_tween()
	tw.tween_property(self, "grow_scale", 1.0, duration) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _follow_cmd_path() -> Vector2:
	if cmd_path.size() > 0:
		var pt: Vector2 = cmd_path[0]
		if global_position.distance_to(pt) < 20.0 + radius() * 0.5:
			cmd_path.pop_front()
			return Vector2.ZERO
		return (pt - global_position).normalized() * max_speed()
	if path_complete:
		cmd = Cmd.HOLD  # arrived: high Wits holds, low Wits drifts (§5)
		_drift_t = float(ConfigDb.v("stats", "low_wits_drift_delay_s"))
	return Vector2.ZERO

# ---- Visuals: ugly is correct; size must be SEEN (Beef scales the body) ----

func _draw() -> void:
	var r := radius() * grow_scale
	var body := color if alive else color.darkened(0.6)
	if rising:
		return
	# Presence fields — faint aura so the verbs are watchable
	if GameState.debug.show_fields and alive and active:
		var fr := float(ConfigDb.v("stats", "field_radius_px"))
		if stats.charm > 0.0:
			draw_arc(Vector2.ZERO, fr, 0, TAU, 48, Color(1.0, 0.5, 0.8, 0.10), 2.0)
		if stats.dread > 0.0:
			draw_arc(Vector2.ZERO, fr, 0, TAU, 48, Color(0.5, 0.6, 1.0, 0.10), 2.0)
	draw_circle(Vector2.ZERO, r, body)
	var ring := Color(0.45, 0.95, 1.0) if faction == Faction.PLAYER else Color(0.85, 0.25, 0.2)
	draw_arc(Vector2.ZERO, r, 0, TAU, 32, ring, 2.0)
	if kind == Kind.RELISH:
		draw_circle(Vector2.ZERO, r * 0.55, Color(0.55, 0.3, 0.8))
		draw_polyline(PackedVector2Array([Vector2(-6, -r - 4), Vector2(0, -r - 12), Vector2(6, -r - 4)]), Color(0.85, 0.7, 1.0), 2.0)
		if iframes > 0.0:
			draw_arc(Vector2.ZERO, r + 6.0, 0, TAU, 32, Color(1, 1, 1, 0.7), 2.0)
		# Pending route ghost: faint grey, consumed as she walks it
		if alive and path_override.size() > 0:
			var ghost := PackedVector2Array([Vector2.ZERO])
			for p in path_override:
				ghost.append(to_local(p))
			draw_polyline(ghost, Color(0.82, 0.82, 0.88, 0.28), 3.0)
			draw_circle(ghost[ghost.size() - 1], 5.0, Color(0.82, 0.82, 0.88, 0.4))
		elif alive and cmd == Cmd.MOVE:
			var lp := to_local(cmd_point)
			draw_circle(lp, 4.5, Color(0.82, 0.82, 0.88, 0.35))
			draw_arc(lp, 9.0, 0, TAU, 16, Color(0.82, 0.82, 0.88, 0.3), 1.5)
	if is_elite:
		draw_arc(Vector2.ZERO, r + 4.0, 0, TAU, 32, Color(1.0, 0.85, 0.3), 2.0)
	if is_boss:
		draw_arc(Vector2.ZERO, r + 5.0, 0, TAU, 48, Color(1.0, 0.5, 0.2), 3.0)
		draw_arc(Vector2.ZERO, r + 10.0, 0, TAU, 48, Color(1.0, 0.5, 0.2, 0.5), 2.0)
	if selected:
		draw_arc(Vector2.ZERO, r + 8.0, 0, TAU, 32, Color(1.0, 0.95, 0.3), 3.0)
	if cmd == Cmd.HOLD and stats.wits >= float(ConfigDb.v("stats", "wits_lock_threshold")):
		draw_arc(Vector2.ZERO, r + 8.0, 0, TAU, 6, Color(1.0, 0.95, 0.3, 0.5), 1.5)
	if _hit_flash > 0.0:
		draw_circle(Vector2.ZERO, r, Color(1, 1, 1, _hit_flash * 0.55))
	if alive and hp < max_hp:
		var w := r * 2.0
		draw_rect(Rect2(-r, -r - 9.0, w, 4.0), Color(0.15, 0.15, 0.18))
		draw_rect(Rect2(-r, -r - 9.0, w * clampf(hp / max_hp, 0.0, 1.0), 4.0), Color(0.4, 0.9, 0.45))
	if GameState.debug.show_targets and _valid_target():
		draw_line(Vector2.ZERO, to_local(target.global_position), Color(1, 0.4, 0.3, 0.35), 1.5)
	if GameState.debug.show_paths and not nav.is_navigation_finished():
		var path := nav.get_current_navigation_path()
		if path.size() > 1:
			var pts := PackedVector2Array()
			for p in path:
				pts.append(to_local(p))
			draw_polyline(pts, Color(0.4, 1.0, 0.6, 0.3), 1.0)
	if display_name != "" and (kind == Kind.PERMANENT or kind == Kind.RELISH or is_elite or is_boss):
		var f := ThemeDB.fallback_font
		draw_string(f, Vector2(-40, -r - 14.0), display_name, HORIZONTAL_ALIGNMENT_CENTER, 80, 11, Color(1, 1, 1, 0.55))
