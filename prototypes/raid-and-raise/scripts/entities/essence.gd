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

func _ready() -> void:
	life = float(ConfigDb.v("timers", "essence_lifetime_s"))
	z_index = 60  # above the trance dim overlay (50): essence ignites
	add_to_group("rr_essence")
	_pop = Vector2(randf_range(-70, 70), randf_range(-70, 70))

func _process(delta: float) -> void:
	_t += delta
	position += _pop * delta
	_pop = _pop.move_toward(Vector2.ZERO, 180.0 * delta)
	if not infinite:
		life -= delta  # delta is scaled by Engine.time_scale = world time
		if life <= 0.0:
			queue_free()
			return
	queue_redraw()

func consume() -> void:
	queue_free()

func _draw() -> void:
	var trance: bool = battlefield != null and battlefield.trance_active
	var pulse := 0.75 + 0.25 * sin(_t * 6.0)
	var col := Color(0.49, 0.89, 0.63)
	var r := 5.0
	if trance:
		col = Color(0.6, 1.0, 0.75)
		r = 7.0 + 2.0 * pulse
		draw_circle(Vector2.ZERO, r * 2.2, Color(col.r, col.g, col.b, 0.18))
	if not infinite and life < 3.0 and fmod(_t, 0.3) < 0.15:
		col.a = 0.35  # flicker: about to fade
	draw_circle(Vector2.ZERO, r, col)
	draw_circle(Vector2.ZERO, r * 0.45, Color(1, 1, 1, 0.8 * pulse))
