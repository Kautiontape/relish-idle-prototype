class_name RaidEssence
extends Node2D
## A small violet-white mote (VISUAL-LANGUAGE 2c): ammo for circle-raising. Decays in world time
## (trance dilation slows decay). Drifts gently toward Relish when she is near.

var raid: Node = null
var mass := 1.0
var life := 12.0
var absorbing := false
var recycled := false   # mass that was already raised once: not fresh dead
var carried := false    # in Relish's carried cluster (dungeon only)
var carry_slot := 0
var ignite_t := 0.0     # >0: a brief ignite flash (the antechamber's last chance)

var _t := 0.0
var _pop := Vector2.ZERO
var _absorb_speed := 0.0


func _ready() -> void:
	z_index = 60
	add_to_group("raid_essence")
	var e: Dictionary = ConfigDb.data.get("raid", {}).get("essence", {})
	life = float(e.get("lifetime_s", 12.0))
	queue_redraw()


func pop(dir: Vector2) -> void:
	_pop = dir


## Lifetime back to full and a brief ignite flash (the antechamber's last chance).
func ignite(flash_s: float) -> void:
	life = float(ConfigDb.data.get("raid", {}).get("essence", {}).get("lifetime_s", 12.0))
	ignite_t = flash_s
	queue_redraw()


func _process(delta: float) -> void:
	_t += delta
	ignite_t = maxf(0.0, ignite_t - delta)
	if absorbing:
		_absorb_step(delta)
		queue_redraw()
		return
	if carried:
		_carry_step(delta)
		queue_redraw()
		return
	position += _pop * delta
	_pop = _pop.move_toward(Vector2.ZERO, 220.0 * delta)
	var e: Dictionary = ConfigDb.data.get("raid", {}).get("essence", {})
	if raid != null and raid.relish != null and is_instance_valid(raid.relish) and raid.relish.alive:
		var rp: Vector2 = raid.relish.global_position
		var d := global_position.distance_to(rp)
		var drift_r: float = float(e.get("drift_radius_px", 120.0))
		# a full cluster keeps loose motes outside the ring so its count stays readable
		var stop_d: float = raid.relish.radius + 10.0
		if not raid.is_boss() and raid.carry_room() <= 0:
			stop_d = maxf(stop_d, float(e.get("carry_orbit_px", 24.0)) + 14.0)
		if d < drift_r and d > stop_d:
			var speed: float = float(e.get("drift_speed_px", 46.0)) * (1.3 - d / drift_r)
			global_position = global_position.move_toward(rp, speed * delta)
		if d <= float(e.get("gather_radius_px", 28.0)) and raid.carry_add(self):
			queue_redraw()
			return
	life -= delta
	if life <= 0.0:
		queue_free()
		return
	queue_redraw()


## Consumed by a circle: streak into Relish, then vanish (units grow at her side).
func absorb() -> void:
	if carried and raid != null:
		raid.carry_release(self)
	absorbing = true
	RaidSound.play("absorb")
	remove_from_group("raid_essence")
	_absorb_speed = 90.0


## A carried mote holds its slot on the ring around Relish: no decay, no drift.
func _carry_step(delta: float) -> void:
	if raid == null or raid.relish == null or not is_instance_valid(raid.relish) or not raid.relish.alive:
		return
	var e: Dictionary = ConfigDb.data.get("raid", {}).get("essence", {})
	var ang: float = raid.carry_angle(carry_slot)
	var target: Vector2 = raid.relish.global_position + Vector2(float(e.get("carry_orbit_px", 24.0)), 0).rotated(ang)
	global_position = global_position.move_toward(target, 700.0 * delta)


func _exit_tree() -> void:
	if carried and raid != null:
		raid.carry_release(self)


func _absorb_step(delta: float) -> void:
	if raid == null or raid.relish == null or not is_instance_valid(raid.relish):
		queue_free()
		return
	_absorb_speed += 2400.0 * delta
	var rp: Vector2 = raid.relish.global_position
	global_position = global_position.move_toward(rp, _absorb_speed * delta)
	if global_position.distance_to(rp) <= raid.relish.radius + 6.0:
		queue_free()


func _draw() -> void:
	var reduced: bool = Pulse.reduced_motion
	var pulse := 0.9 if reduced else 0.75 + 0.25 * sin(_t * 6.0)
	var col := Palette.c("essence")
	if absorbing:
		if raid != null and raid.relish != null and is_instance_valid(raid.relish):
			var dir := to_local(raid.relish.global_position).normalized()
			draw_line(-dir * (8.0 + _absorb_speed * 0.04), Vector2.ZERO, Palette.c("essence", 0.5), 3.0)
		draw_circle(Vector2.ZERO, 6.5, col)
		draw_circle(Vector2.ZERO, 3.0, Palette.c("text", 0.9))
		return
	if carried:
		# small and crisp so the ring reads as a count; the spin is only drawn (counted spot = node position)
		var off: Vector2 = raid.carry_draw_offset(carry_slot) if raid != null else Vector2.ZERO
		draw_circle(off, 3.6, col)
		draw_circle(off, 1.7, Palette.c("text", 0.9))
		return
	var r := 4.0 + 1.0 * pulse
	if raid != null and raid.trance_active:
		r += 2.0
	if life < 3.0:
		# about to dissipate: flicker (steady half-alpha under reduced motion)
		if reduced:
			col.a = 0.5
		elif fmod(_t, 0.3) < 0.15:
			col.a = 0.4
	LineGlow.ring(self, Vector2.ZERO, r + 3.0, col, 1.0, 0.5)
	if ignite_t > 0.0:
		LineGlow.ring(self, Vector2.ZERO, r + 8.0 + 10.0 * ignite_t, Palette.c("text", 0.9), 2.0, 1.0, col)
	draw_circle(Vector2.ZERO, r, col)
	draw_circle(Vector2.ZERO, r * 0.45, Palette.c("text", 0.85 * pulse))
