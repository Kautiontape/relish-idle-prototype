class_name RaidRelish
extends Node2D
## Relish: a conduit, never a fighter. Click-to-move. If a lethal hit lands and
## any allied undead exists, the nearest ally is sacrificed in her place.

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
	z_index = 38  # above the trance dim (36): she stays at full strength


func _physics_process(delta: float) -> void:
	if raid == null or raid._ended or not alive:
		return
	_t += delta
	_iframes = maxf(0.0, _iframes - delta)
	_flash = maxf(0.0, _flash - delta * 3.0)
	var d := move_target - global_position
	if d.length() > 6.0:
		var step := d.normalized() * minf(speed * delta, d.length())
		var start := global_position
		var got: Vector2 = raid.resolve_walls(start + step, radius)
		if (got - start).length() < step.length() * 0.3:
			# blocked by a wall: slide along whichever axis still makes progress
			var gx: Vector2 = raid.resolve_walls(start + Vector2(step.x, 0), radius)
			var gy: Vector2 = raid.resolve_walls(start + Vector2(0, step.y), radius)
			got = gx if (gx - start).length() > (gy - start).length() else gy
		global_position = got
	else:
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
	var violet := Palette.c("relish")
	var body := violet
	if _flash > 0.0:
		body = body.lerp(Palette.c("danger"), minf(0.8, _flash))
	# halo breathes on the Pulse beat (steady under reduced motion)
	var beat := 0.6 + 0.4 * Pulse.wave()
	LineGlow.ring(self, Vector2.ZERO, radius * 1.8, violet, 1.5, 0.5 * beat)
	draw_circle(Vector2.ZERO, radius, body)
	LineGlow.ring(self, Vector2.ZERO, radius + 3.5, violet, 2.0, beat, Palette.c("text", 0.6))
	draw_circle(Vector2.ZERO, radius * 0.4, Palette.c("text", 0.9))
	if _iframes > 0.0:
		draw_arc(Vector2.ZERO, radius + 8.0, 0, TAU, 24, Palette.c("danger", 0.6), 2.0)
	if hp < max_hp:
		var w := 30.0
		var y := -radius - 12.0
		draw_rect(Rect2(-w * 0.5, y, w, 4.0), Palette.c("ground", 0.8))
		draw_rect(Rect2(-w * 0.5, y, w * clampf(hp / max_hp, 0.0, 1.0), 4.0), violet)
	# trance focus / cooldown arc around her
	if raid != null and raid.trance != null:
		var tr = raid.trance
		if tr.state == RaidTrance.State.ACTIVE:
			var f: float = tr.focus_frac()
			LineGlow.arc(self, Vector2.ZERO, radius + 11.0, -PI * 0.5, -PI * 0.5 + TAU * f,
				violet, 3.0, 0.5, Palette.c("text"))
		elif tr.state == RaidTrance.State.COOLDOWN or tr.state == RaidTrance.State.LOCKOUT:
			var f2: float = 1.0 - tr.cooldown_frac()
			LineGlow.arc(self, Vector2.ZERO, radius + 11.0, -PI * 0.5,
				-PI * 0.5 + TAU * maxf(0.02, f2), Palette.c("cooldown"), 2.5, 0.5)
