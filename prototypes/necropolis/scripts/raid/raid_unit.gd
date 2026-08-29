class_name RaidUnit
extends Node2D
## One combat unit — enemy (orange family) or allied undead (green family).
## Simple kinematics: chase, melee on a cadence, neighbor separation, wall slide.

const ORANGE := Color("#ff6a2b")
const ORANGE_LIGHT := Color("#ff9a55")
const ORANGE_DARK := Color("#c74a15")
const GREEN := Color("#39ff9e")
const GREEN_DIM := Color("#2bbf78")
const GOLD := Color("#fff3d0")
const DANGER := Color("#ff2d55")

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
var ledger_mass := false     # true only for chaff raised this raid
var from_army := false       # boss: brought army (loss accounting)
var home_room := Rect2()
var alive := true

var _target = null           # duck-typed: global_position / radius / take_hit / alive
var _aggro := false
var _strike_t := 0.0
var _wander_pt := Vector2.ZERO
var _wander_t := 0.0
var _flash := 0.0
var _lunge := 0.0
var _facing := Vector2.RIGHT
var _grow := 0.0


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
	_strike_t = randf() * cadence
	_wander_pt = position


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
	_pick_target(cfg)

	var move := Vector2.ZERO
	if _target != null and is_instance_valid(_target) and _target.alive:
		var to_t: Vector2 = _target.global_position - global_position
		var reach: float = radius + _target.radius + float(cfg.get("strike_reach_pad", 7.0))
		_facing = to_t.normalized() if to_t.length() > 1.0 else _facing
		if to_t.length() > reach:
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
				move = d.normalized() * speed * 0.8
				_facing = d.normalized()

	move += raid.separation_push(self) * float(cfg.get("separation_push", 110.0))
	_slide_move(move, delta)
	queue_redraw()


func _pick_target(cfg: Dictionary) -> void:
	if _target != null and (not is_instance_valid(_target) or not _target.alive):
		_target = null
	if faction == "ally":
		_target = raid.nearest_enemy_of(global_position)
		return
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
	if not _aggro and best_d <= float(cfg.get("aggro_px", 260.0)):
		_aggro = true
	_target = best if _aggro else null


func _wander(delta: float, cfg: Dictionary) -> Vector2:
	_wander_t -= delta
	if _wander_t <= 0.0:
		_wander_t = randf_range(float(cfg.get("wander_repick_min_s", 2.0)),
			float(cfg.get("wander_repick_max_s", 5.0)))
		var room := home_room.grow(-40.0) if home_room.size.x > 120.0 else home_room
		_wander_pt = Vector2(randf_range(room.position.x, room.end.x),
			randf_range(room.position.y, room.end.y))
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


func _draw() -> void:
	var body := _body_color()
	if _flash > 0.0:
		body = body.lerp(Color.WHITE, minf(0.85, _flash))
	var outline := body.darkened(0.55)
	var lunge_off := _facing * _lunge * 5.0

	match kind:
		"brute":
			_draw_poly_body(6, radius, body, outline, lunge_off)
		"elite":
			draw_circle(lunge_off, radius * 1.7, Color(GREEN.r, GREEN.g, GREEN.b, 0.10))
			_draw_poly_body(6, radius, body, outline, lunge_off)
			draw_arc(lunge_off, radius + 3.0, 0, TAU, 20, Color(GREEN.r, GREEN.g, GREEN.b, 0.7), 1.5)
		"runner":
			draw_line(lunge_off - _facing * radius * 2.0, lunge_off, Color(body.r, body.g, body.b, 0.35), 2.0)
			draw_circle(lunge_off, radius, body)
			draw_arc(lunge_off, radius, 0, TAU, 16, outline, 1.5)
		"guard":
			draw_circle(lunge_off, radius * 1.5, Color(GOLD.r, GOLD.g, GOLD.b, 0.10))
			draw_circle(lunge_off, radius, body)
			draw_arc(lunge_off, radius, 0, TAU, 16, GOLD, 1.5)
		_:
			draw_circle(lunge_off, radius, body)
			draw_arc(lunge_off, radius, 0, TAU, 16, outline, 1.5)
	# facing tick (spear tip / fang)
	var tip := lunge_off + _facing * (radius + 4.0)
	draw_line(lunge_off + _facing * radius * 0.6, tip, outline.lightened(0.3), 2.0)
	if hp < max_hp:
		var w := 18.0
		var frac := clampf(hp / max_hp, 0.0, 1.0)
		var y := -radius - 7.0
		draw_rect(Rect2(-w * 0.5, y, w, 3.0), Color(0, 0, 0, 0.6))
		var fill := GREEN if faction == "ally" else ORANGE
		draw_rect(Rect2(-w * 0.5, y, w * frac, 3.0), fill)


func _draw_poly_body(sides: int, r: float, body: Color, outline: Color, off: Vector2) -> void:
	var pts := PackedVector2Array()
	for i in sides:
		pts.append(off + Vector2(r * 1.15, 0).rotated(TAU * i / sides + 0.3))
	draw_colored_polygon(pts, body)
	pts.append(pts[0])
	draw_polyline(pts, outline, 1.6)


func _body_color() -> Color:
	match kind:
		"spearman":
			return ORANGE
		"runner":
			return ORANGE_LIGHT
		"brute":
			return ORANGE_DARK
		"guard":
			return Color("#ffb066")
		"chaff":
			return GREEN_DIM
		"soldier":
			return GREEN
		"elite":
			return Color("#7dffbe")
	return ORANGE if faction == "enemy" else GREEN
