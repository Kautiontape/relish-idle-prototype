class_name Projectile
extends Node2D
## Magic bolt (§5 Anima). Fired by any unit with Magic > 0 — same code path
## for cultist archers and player permanents. Damage = 1.5 × Magic (§11).

var src: RRUnit = null
var src_faction: int = RRUnit.Faction.ENEMY
var target: RRUnit = null
var dmg := 1.0
var color := Color(0.5, 0.9, 1.0)
var _dir := Vector2.RIGHT
var _last_target_pos := Vector2.ZERO
var _travelled := 0.0

func _ready() -> void:
	z_index = 30
	if target != null and is_instance_valid(target):
		_last_target_pos = target.global_position

func _process(delta: float) -> void:
	var speed := float(ConfigDb.v("stats", "magic_bolt_speed_px"))
	if target != null and is_instance_valid(target) and target.is_targetable():
		_last_target_pos = target.global_position
	_dir = (_last_target_pos - global_position).normalized()
	var step := speed * delta
	global_position += _dir * step
	_travelled += step
	if target != null and is_instance_valid(target) and target.is_targetable() \
			and global_position.distance_to(target.global_position) <= target.radius() + 4.0:
		target.take_hit(src if is_instance_valid(src) else null, dmg)
		queue_free()
		return
	if _travelled > float(ConfigDb.v("stats", "magic_bolt_range_px")) * 1.4 \
			or global_position.distance_to(_last_target_pos) < 6.0:
		queue_free()
		return
	queue_redraw()

func _draw() -> void:
	draw_line(-_dir * 10.0, Vector2.ZERO, color, 3.0)
	draw_circle(Vector2.ZERO, 3.0, color.lightened(0.4))
