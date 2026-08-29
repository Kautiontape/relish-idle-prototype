class_name RaidEssence
extends Node2D
## Bright green glowing essence: ammo for circle-raising. Decays in world time
## (trance dilation slows decay). Drifts gently toward Relish when she is near.

const CORE := Color("#39ff9e")

var raid: Node = null
var mass := 1.0
var life := 12.0
var absorbing := false

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


func _process(delta: float) -> void:
	_t += delta
	if absorbing:
		_absorb_step(delta)
		queue_redraw()
		return
	position += _pop * delta
	_pop = _pop.move_toward(Vector2.ZERO, 220.0 * delta)
	var e: Dictionary = ConfigDb.data.get("raid", {}).get("essence", {})
	if raid != null and raid.relish != null and is_instance_valid(raid.relish) and raid.relish.alive:
		var rp: Vector2 = raid.relish.global_position
		var d := global_position.distance_to(rp)
		var drift_r: float = float(e.get("drift_radius_px", 120.0))
		if d < drift_r and d > raid.relish.radius + 10.0:
			var speed: float = float(e.get("drift_speed_px", 46.0)) * (1.3 - d / drift_r)
			global_position = global_position.move_toward(rp, speed * delta)
	life -= delta
	if life <= 0.0:
		queue_free()
		return
	queue_redraw()


## Consumed by a circle: streak into Relish, then vanish (units grow at her side).
func absorb() -> void:
	absorbing = true
	remove_from_group("raid_essence")
	_absorb_speed = 90.0


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
	var pulse := 0.75 + 0.25 * sin(_t * 6.0)
	if absorbing:
		var col := Color(0.7, 1.0, 0.85)
		if raid != null and raid.relish != null and is_instance_valid(raid.relish):
			var dir := to_local(raid.relish.global_position).normalized()
			draw_line(-dir * (8.0 + _absorb_speed * 0.04), Vector2.ZERO, Color(col.r, col.g, col.b, 0.5), 3.0)
		draw_circle(Vector2.ZERO, 6.5, col)
		draw_circle(Vector2.ZERO, 3.0, Color(1, 1, 1, 0.9))
		return
	var trance: bool = raid != null and raid.trance_active
	var halo := 26.0
	var halo_a := 0.05 + 0.02 * pulse
	if trance:
		halo *= 1.3
		halo_a += 0.05
	draw_circle(Vector2.ZERO, halo, Color(0.25, 1.0, 0.55, halo_a))
	draw_circle(Vector2.ZERO, halo * 0.55, Color(0.3, 1.0, 0.6, halo_a))
	var col := CORE
	var r := 5.0 + 1.2 * pulse
	if trance:
		col = Color(0.55, 1.0, 0.8)
		r += 2.0
		draw_circle(Vector2.ZERO, r * 2.1, Color(col.r, col.g, col.b, 0.18))
	if life < 3.0 and fmod(_t, 0.3) < 0.15:
		col.a = 0.4  # flicker: about to dissipate
	draw_circle(Vector2.ZERO, r, col)
	draw_circle(Vector2.ZERO, r * 0.45, Color(1, 1, 1, 0.85 * pulse))
