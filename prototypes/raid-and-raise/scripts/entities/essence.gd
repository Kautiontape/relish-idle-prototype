class_name Essence
extends Node2D
## Drops from corpses; ammo for circle-summoning (§3). Decays in WORLD time —
## trance dilation slows decay, so timing kills near a trance window is skill,
## never theft (§8.2). Ignites visually while the Trance is held.

var battlefield = null
var life := 12.0
var _pop := Vector2.ZERO
var _t := 0.0
var infinite := false  # playroom gyms keep essence alive
var _absorbing := false
var _mult := 1.0
var _absorb_speed := 0.0

func _ready() -> void:
	life = float(ConfigDb.v("timers", "essence_lifetime_s"))
	z_index = 60  # above the trance dim overlay (50): essence ignites
	add_to_group("rr_essence")
	_pop = Vector2(randf_range(-70, 70), randf_range(-70, 70))

func _process(delta: float) -> void:
	_t += delta
	if _absorbing:
		_absorb_step(delta)
		queue_redraw()
		return
	position += _pop * delta
	_pop = _pop.move_toward(Vector2.ZERO, 180.0 * delta)
	if not infinite:
		life -= delta  # delta is scaled by Engine.time_scale = world time
		if life <= 0.0:
			queue_free()
			return
	queue_redraw()

## Summoned: fwwwwooomp — an accelerating pull into Relish; the chaff grows
## out of her side when it lands (battlefield.spawn_chaff_grown).
func absorb(mult: float) -> void:
	_absorbing = true
	_mult = mult
	_absorb_speed = float(ConfigDb.v("circle", "absorb_start_speed_px"))
	remove_from_group("rr_essence")  # no longer summonable by another circle

func _absorb_step(delta: float) -> void:
	var rel = battlefield.relish if battlefield != null else null
	if rel == null or not is_instance_valid(rel) or not rel.alive:
		queue_free()
		return
	_absorb_speed += float(ConfigDb.v("circle", "absorb_accel_px")) * delta
	global_position = global_position.move_toward(rel.global_position, _absorb_speed * delta)
	if global_position.distance_to(rel.global_position) <= rel.radius() + 6.0:
		battlefield.spawn_chaff_grown(_mult)
		queue_free()

func consume() -> void:
	queue_free()

func _draw() -> void:
	var trance: bool = battlefield != null and battlefield.trance_active
	var pulse := 0.75 + 0.25 * sin(_t * 6.0)
	var col := Color(0.49, 0.89, 0.63)
	var r := 5.0
	if _absorbing:
		# streaking toward Relish: bright core + a motion tail
		col = Color(0.7, 1.0, 0.85)
		var rel = battlefield.relish if battlefield != null else null
		if rel != null and is_instance_valid(rel):
			var dir := (to_local(rel.global_position)).normalized()
			draw_line(-dir * (8.0 + _absorb_speed * 0.04), Vector2.ZERO, Color(col.r, col.g, col.b, 0.5), 3.0)
		draw_circle(Vector2.ZERO, 6.5, col)
		draw_circle(Vector2.ZERO, 3.0, Color(1, 1, 1, 0.9))
		return
	# Glow pool: a wide, faint halo drawn above the crowd (z_index 60). One
	# stray gem stays subtle; overlapping halos stack into a bright green pool,
	# so a good BATCH of essence advertises itself through a churning horde.
	var halo := float(ConfigDb.v("circle", "essence_halo_px"))
	var halo_a := 0.05 + 0.02 * pulse
	if trance:
		halo *= 1.25
		halo_a += 0.05
	draw_circle(Vector2.ZERO, halo, Color(0.4, 1.0, 0.55, halo_a))
	draw_circle(Vector2.ZERO, halo * 0.6, Color(0.5, 1.0, 0.62, halo_a))
	if trance:
		col = Color(0.6, 1.0, 0.75)
		r = 7.0 + 2.0 * pulse
		draw_circle(Vector2.ZERO, r * 2.2, Color(col.r, col.g, col.b, 0.18))
	if not infinite and life < 3.0 and fmod(_t, 0.3) < 0.15:
		col.a = 0.35  # flicker: about to fade
	draw_circle(Vector2.ZERO, r, col)
	draw_circle(Vector2.ZERO, r * 0.45, Color(1, 1, 1, 0.8 * pulse))
