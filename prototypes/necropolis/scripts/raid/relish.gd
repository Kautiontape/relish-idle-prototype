class_name RaidRelish
extends Node2D
## Relish: a conduit, never a fighter. Click-to-move. If a lethal hit lands and
## any allied undead exists, the nearest ally is sacrificed in her place.

const VIOLET := Color("#c04cff")
const TRACE := Color("#50ffd9")
const AMBER := Color(1.0, 0.72, 0.25)
const DANGER := Color("#ff2d55")

var raid: Node = null
var hp := 30.0
var max_hp := 30.0
var speed := 240.0
var radius := 13.0
var alive := true

var move_target := Vector2.ZERO
var _iframes := 0.0
var _flash := 0.0
var _t := 0.0


func configure(p_raid: Node) -> void:
	raid = p_raid
	var r: Dictionary = ConfigDb.data.get("raid", {}).get("relish", {})
	hp = float(r.get("hp", 30.0))
	max_hp = hp
	speed = float(r.get("speed", 240.0))
	radius = float(r.get("radius", 13.0))
	move_target = position
	z_index = 35


func _physics_process(delta: float) -> void:
	if raid == null or raid._ended or not alive:
		return
	_t += delta
	_iframes = maxf(0.0, _iframes - delta)
	_flash = maxf(0.0, _flash - delta * 3.0)
	var d := move_target - global_position
	if d.length() > 6.0:
		global_position += d.normalized() * minf(speed * delta, d.length())
	global_position = raid.resolve_walls(global_position, radius)
	queue_redraw()


func take_hit(amount: float) -> void:
	if not alive or _iframes > 0.0:
		return
	if hp - amount <= 0.0 and raid.has_allies():
		# THE CONDUIT RULE: the nearest allied undead dies in her place.
		raid.sacrifice_nearest_ally()
		_iframes = float(ConfigDb.data.get("raid", {}).get("relish", {}).get("iframes_s", 0.5))
		_flash = 1.0
		queue_redraw()
		return
	hp -= amount
	_flash = 1.0
	if hp <= 0.0:
		alive = false
		raid.on_relish_died()
	queue_redraw()


func _draw() -> void:
	var body := VIOLET
	if _flash > 0.0:
		body = body.lerp(DANGER, minf(0.8, _flash))
	# glow ring halo
	draw_circle(Vector2.ZERO, radius * 2.6, Color(VIOLET.r, VIOLET.g, VIOLET.b, 0.07))
	draw_circle(Vector2.ZERO, radius * 1.8, Color(VIOLET.r, VIOLET.g, VIOLET.b, 0.12))
	draw_circle(Vector2.ZERO, radius, body)
	draw_arc(Vector2.ZERO, radius + 3.5, 0, TAU, 24, Color(VIOLET.r, VIOLET.g, VIOLET.b, 0.85), 2.0)
	draw_circle(Vector2.ZERO, radius * 0.4, Color(1, 1, 1, 0.9))
	if _iframes > 0.0:
		draw_arc(Vector2.ZERO, radius + 8.0, 0, TAU, 24, Color(DANGER.r, DANGER.g, DANGER.b, 0.6), 2.0)
	if hp < max_hp:
		var w := 30.0
		var y := -radius - 12.0
		draw_rect(Rect2(-w * 0.5, y, w, 4.0), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(-w * 0.5, y, w * clampf(hp / max_hp, 0.0, 1.0), 4.0), VIOLET)
	# trance focus / cooldown arc around her
	if raid != null and raid.trance != null:
		var tr = raid.trance
		if tr.state == RaidTrance.State.ACTIVE:
			var f: float = tr.focus_frac()
			draw_arc(Vector2.ZERO, radius + 11.0, -PI * 0.5, -PI * 0.5 + TAU * f, 32, TRACE, 3.0)
		elif tr.state == RaidTrance.State.COOLDOWN or tr.state == RaidTrance.State.LOCKOUT:
			var f2: float = 1.0 - tr.cooldown_frac()
			draw_arc(Vector2.ZERO, radius + 11.0, -PI * 0.5, -PI * 0.5 + TAU * maxf(0.02, f2), 32,
				Color(AMBER.r, AMBER.g, AMBER.b, 0.8), 2.5)
