class_name RaidUnit
extends Node2D
## One combat unit — enemy (orange family) or allied undead (green family).
## Simple kinematics: chase, melee on a cadence, neighbor separation, wall slide.

var raid: Node = null
var faction := "enemy"       # "enemy" | "ally"
var kind := "spearman"
var hp := 10.0
var max_hp := 10.0
var dmg := 4.0
var speed := 100.0
var cadence := 1.0
var radius := 10.0
var mass := 0.0              # enemies: dropped as essence; chaff: ledger pool mass
var role := ""               # v2 allies: "raised" | "garrison" | "starter" | "party"
var tier := ""               # v2 allies: chaff | soldier | elite | big
var stat_mult := 1.0
var uid := ""                # party only
var beef := 0.0              # party only: the entry's beef stat (the Bellringer's weak point)
var speed_stat := 0.0        # party only: the entry's speed stat (the Huntsman's weak point)
var slots := 1               # party: nested diamonds (filled slots)
var ledger_mass := false     # true only for chaff raised this raid
var from_army := false       # boss: brought army (loss accounting)
var home_room := Rect2()
var alive := true

var _guard := {}             # bodyguard post this frame ({} when not guarding)
var _target = null           # duck-typed: global_position / radius / take_hit / alive
var _aggro := false
var _strike_t := 0.0
var _wander_pt := Vector2.ZERO
var _wander_t := 0.0
var _flash := 0.0
var _lunge := 0.0
var _facing := Vector2.RIGHT
var _grow := 0.0
var _route: RaidRoute = null  # waypoint cache (room-graph routing)
var _think_t := 0.0           # target re-pick timer, staggered per unit


func configure(p_raid: Node, p_faction: String, p_kind: String, stats: Dictionary) -> void:
	raid = p_raid
	faction = p_faction
	kind = p_kind
	hp = float(stats.get("hp", 10.0))
	max_hp = hp
	dmg = float(stats.get("dmg", 4.0))
	speed = float(stats.get("speed", 100.0))
	cadence = float(stats.get("cadence_s", 1.0))
	radius = float(stats.get("radius", 10.0))
	z_index = 30 if p_faction == "enemy" else 32
	_strike_t = raid.rng_combat.randf() * cadence
	_wander_pt = position
	var ccfg: Dictionary = ConfigDb.data.get("raid", {}).get("combat", {})
	_route = RaidRoute.new(ccfg)
	_think_t = _route.stagger()


## Where to steer to reach `goal`: through the doorway when a wall is in the way, else the goal.
func _steer_to(goal: Vector2, delta: float) -> Vector2:
	if _route == null or raid.layout.is_empty():
		return goal
	return _route.steer(raid.layout, global_position, goal, radius, delta)


func grow_in() -> void:
	_grow = 0.001
	scale = Vector2.ONE * 0.2


func _physics_process(delta: float) -> void:
	if raid == null or raid._ended or not alive:
		return
	if _grow > 0.0:
		_grow += delta
		var s := minf(1.0, 0.2 + _grow * 3.4)
		scale = Vector2.ONE * s
		if s >= 1.0:
			_grow = 0.0
	_flash = maxf(0.0, _flash - delta * 4.0)
	_lunge = maxf(0.0, _lunge - delta * 5.0)
	_strike_t -= delta

	var cfg: Dictionary = ConfigDb.data.get("raid", {}).get("combat", {})
	_think_t -= delta
	if _target != null and (not is_instance_valid(_target) or not _target.alive):
		_target = null
		_think_t = 0.0   # a kill re-picks at once
	if _think_t <= 0.0:
		_think_t = float(cfg.get("route_repath_s", 0.25))
		_pick_target(cfg)

	var move := Vector2.ZERO
	_guard = raid.warden_run.guard_for(self) if faction == "ally" and kind == "big" and raid.warden_run != null else {}
	if not _guard.is_empty():
		# bodyguard (fast big undead vs an awake Huntsman): strike what is in reach, never chase
		var gp: Vector2 = _guard["point"]
		var foe = null
		var best_d := INF
		for e in raid.enemies:
			if is_instance_valid(e) and e.alive:
				var dd: float = global_position.distance_to(e.global_position) - e.radius
				if dd < best_d:
					best_d = dd
					foe = e
		if foe == null or best_d > radius + float(cfg.get("strike_reach_pad", 7.0)):
			foe = _target   # nothing else in reach: the warden, if it is close
		if foe != null and is_instance_valid(foe) and foe.alive:
			var tt: Vector2 = foe.global_position - global_position
			var rch: float = radius + foe.radius + float(cfg.get("strike_reach_pad", 7.0))
			if tt.length() <= rch and _strike_t <= 0.0:
				_strike_t = cadence
				_lunge = 1.0
				_facing = tt.normalized()
				foe.take_hit(dmg)
		var tg := gp - global_position
		if tg.length() > 6.0:
			var gs := _steer_to(gp, delta) - global_position
			if gs.length() < 1.0:
				gs = tg
			move = gs.normalized() * minf(speed * 1.3, tg.length() / maxf(delta, 0.001))
			_facing = gs.normalized()
	elif _target != null and is_instance_valid(_target) and _target.alive:
		var to_t: Vector2 = _target.global_position - global_position
		var reach: float = radius + _target.radius + float(cfg.get("strike_reach_pad", 7.0))
		_facing = to_t.normalized() if to_t.length() > 1.0 else _facing
		if to_t.length() > reach:
			var ts := _steer_to(_target.global_position, delta) - global_position
			if ts.length() > 1.0:
				_facing = ts.normalized()
			move = _facing * speed
		elif _strike_t <= 0.0:
			_strike_t = cadence
			_lunge = 1.0
			_target.take_hit(dmg)
	elif faction == "enemy":
		move = _wander(delta, cfg)
	else:
		# no enemies left: drift back toward Relish
		var rel = raid.relish
		if rel != null and is_instance_valid(rel) and rel.alive:
			var d: Vector2 = rel.global_position - global_position
			if d.length() > float(cfg.get("ally_follow_px", 150.0)):
				var fs := _steer_to(rel.global_position, delta) - global_position
				var fdir := fs.normalized() if fs.length() > 1.0 else d.normalized()
				move = fdir * speed * 0.8
				_facing = fdir

	move += raid.separation_push(self) * float(cfg.get("separation_push", 110.0))
	_slide_move(move, delta)
	queue_redraw()


func _pick_target(cfg: Dictionary) -> void:
	var was = _target
	if _target != null and (not is_instance_valid(_target) or not _target.alive):
		_target = null
	if faction == "ally":
		_target = raid.nearest_enemy_of(global_position, radius)
	else:
		_pick_enemy_target(cfg)
	if _target != was and _route != null:
		_route.reset()   # the goal jumped: route to the new target now (relish.gd does the same)


func _pick_enemy_target(cfg: Dictionary) -> void:
	# enemy: aggro within range of Relish or any undead, then stay hostile
	var best = null
	var best_d := INF
	var rel = raid.relish
	if rel != null and is_instance_valid(rel) and rel.alive:
		best = rel
		best_d = global_position.distance_to(rel.global_position)
	var na = raid.nearest_ally_of(global_position)
	if na != null:
		var d: float = global_position.distance_to(na.global_position)
		if d < best_d:
			best = na
			best_d = d
	if not _aggro and best_d <= float(cfg.get("aggro_px", 260.0)) and best != null \
			and LayoutLogic.route_dist(raid.layout, global_position, best.global_position, radius) <= float(cfg.get("aggro_px", 260.0)):
		_aggro = true   # walking distance, not through-the-wall distance
	_target = best if _aggro else null


func _wander(delta: float, cfg: Dictionary) -> Vector2:
	_wander_t -= delta
	if _wander_t <= 0.0:
		_wander_t = raid.rng_combat.randf_range(float(cfg.get("wander_repick_min_s", 2.0)),
			float(cfg.get("wander_repick_max_s", 5.0)))
		var room := home_room.grow(-40.0) if home_room.size.x > 120.0 else home_room
		_wander_pt = Vector2(raid.rng_combat.randf_range(room.position.x, room.end.x),
			raid.rng_combat.randf_range(room.position.y, room.end.y))
	var d := _wander_pt - global_position
	if d.length() < 12.0:
		return Vector2.ZERO
	_facing = d.normalized()
	return d.normalized() * speed * float(cfg.get("wander_speed_frac", 0.55))


func _slide_move(vel: Vector2, delta: float) -> void:
	if vel == Vector2.ZERO:
		global_position = raid.resolve_walls(global_position, radius)
		return
	var start := global_position
	var want := start + vel * delta
	var got: Vector2 = raid.resolve_walls(want, radius)
	if (got - start).length() < vel.length() * delta * 0.3:
		# blocked: try sliding along each axis, keep the better one
		var gx: Vector2 = raid.resolve_walls(start + Vector2(vel.x, 0) * delta, radius)
		var gy: Vector2 = raid.resolve_walls(start + Vector2(0, vel.y) * delta, radius)
		got = gx if (gx - start).length() > (gy - start).length() else gy
	global_position = got


func take_hit(amount: float) -> void:
	if not alive:
		return
	hp -= amount
	_flash = 1.0
	if hp <= 0.0:
		die()
	queue_redraw()


func die(sacrificed := false) -> void:
	if not alive:
		return
	alive = false
	if raid != null:
		raid.on_unit_died(self, sacrificed)
	queue_free()


## Glyphs (VISUAL-LANGUAGE 2c). Every kind differs by shape, not only colour:
## undead = straight strokes (count = quality) + a solid head dot; living = a bow arc
## + a hollow ring head; big undead = nested diamonds. Colours come from Palette.
func _draw() -> void:
	var lunge_off := _facing * _lunge * 5.0
	if not _guard.is_empty():
		# the bodyguard link to Relish, faint
		LineGlow.polyline(self, PackedVector2Array([Vector2.ZERO, (_guard["relish"] as Vector2) - global_position]),
			Palette.c("undead", 0.3), 1.5, 0.3)
	if kind == "big":
		_draw_big(lunge_off)
	elif faction == "ally":
		_draw_undead(lunge_off)
	else:
		_draw_living(lunge_off)
	if hp < max_hp:
		# minimal hp: a short bar under the glyph
		var w := 1.4 * radius
		var y := radius + 6.0
		var frac := clampf(hp / max_hp, 0.0, 1.0)
		draw_line(Vector2(-w * 0.5, y), Vector2(w * 0.5, y), Palette.c("ground", 0.8), 2.0)
		draw_line(Vector2(-w * 0.5, y), Vector2(-w * 0.5 + w * frac, y),
			Palette.c("undead" if faction == "ally" else "living"), 2.0)


func _flashed(col: Color) -> Color:
	if _flash > 0.0:
		return col.lerp(Palette.c("text"), minf(0.85, _flash))
	return col


## n parallel strokes (chaff 1, soldier 2, elite 3), ~2 x radius long, along the heading,
## with a core dot at the head. Sized from `radius` (dungeon zoom), not town pixels.
func _draw_undead(off: Vector2) -> void:
	var col := _flashed(Palette.c("undead"))
	var n := 3 if kind == "elite" else (2 if kind == "soldier" else 1)
	var half := radius
	var gap := radius * 0.38
	var w := maxf(2.0, radius * 0.22)
	var perp := _facing.orthogonal()
	var spread := gap * (n - 1)
	# one shared halo (LineGlow's outer layers) for the whole stroke group
	var layers := LineGlow.layers(col, w + spread, 0.45)
	for i in layers.size() - 1:
		draw_line(off - _facing * half, off + _facing * half, layers[i][1], layers[i][0])
	for i in n:
		var o := perp * (gap * (i - (n - 1) * 0.5))
		draw_line(off + o - _facing * half, off + o + _facing * half, col, w)
	draw_circle(off + _facing * (half + 1.0), radius * 0.3, _flashed(Palette.c("undead_core")))


## A bow arc (spans ~2.2 x radius) with a hollow ring head (r ~0.45 x radius) at its tip.
## A heavier `living_core` stroke keeps it readable against the orange walls.
func _draw_living(off: Vector2) -> void:
	var col := _flashed(Palette.c("living"))
	var core := _flashed(Palette.c("living_core"))
	var r := radius * 1.1
	var c := off - _facing * (radius * 0.55)
	var a0 := _facing.angle() - 1.2
	var width := maxf(2.6, radius * (0.3 if kind == "brute" else 0.24))
	LineGlow.arc(self, c, r, a0, a0 + 2.4, col, width, 0.4, core)
	LineGlow.ring(self, c + _facing * r, radius * 0.45, col, maxf(2.0, width * 0.8), 0.0, core)
	if kind == "guard":
		LineGlow.ring(self, off, radius * 1.6, Palette.c("vei"), 2.2, 0.5)


## Big undead: a diamond outline ~2x an undead glyph, a core dot, nested per filled slot,
## breathing on the Pulse (steady under reduced motion).
func _draw_big(off: Vector2) -> void:
	var col := _flashed(Palette.c("undead"))
	var k := 1.0 + 0.06 * Pulse.wave()
	var r0 := radius * 0.9 * k
	for i in slots:
		var r := r0 * (1.0 - 0.24 * i)
		var pts := PackedVector2Array([off + Vector2(0, -r), off + Vector2(r, 0), off + Vector2(0, r),
			off + Vector2(-r, 0), off + Vector2(0, -r)])
		if i == 0:
			LineGlow.polyline(self, pts, col, 2.0, 0.5)
		else:
			draw_polyline(pts, col, 1.6)
	draw_circle(off, 3.4, _flashed(Palette.c("undead_core")))
