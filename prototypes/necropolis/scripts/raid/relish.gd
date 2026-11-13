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
		raid.sacrifice_nearest_ally()   # pings the danger edge
		_iframes = float(ConfigDb.data.get("raid", {}).get("relish", {}).get("iframes_s", 0.5))
		_flash = 1.0
		queue_redraw()
		return
	hp -= amount
	_flash = 1.0
	raid.danger_hit()
	if hp <= 0.0:
		if raid.try_phylactery():
			queue_redraw()
			return
		alive = false
		raid.on_relish_died()
	queue_redraw()


## Phylactery revive: back to `new_hp` with i-frames.
func revive(new_hp: float, iframes_s: float) -> void:
	hp = clampf(new_hp, 1.0, max_hp)
	_iframes = iframes_s
	_flash = 1.0
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
	if raid != null and not raid.is_boss() and raid.carried_count() > 0:
		# empty carry slots: faint matte ticks, so "7 of 12" reads at a glance
		var e: Dictionary = ConfigDb.data.get("raid", {}).get("essence", {})
		var used := {}
		for c in raid.carried:
			used[c.carry_slot] = true
		for i in int(e.get("carry_max", 12)):
			if not used.has(i):
				var dir := Vector2.RIGHT.rotated(raid.carry_angle(i))
				var orbit := float(e.get("carry_orbit_px", 24.0))
				draw_line(dir * (orbit - 2.0), dir * (orbit + 2.0), Palette.c("essence", 0.28), 1.5)
	if raid != null and not raid.is_boss() and raid.revived > 0:
		# one small cracked violet ring per spent phylactery; it does not come back
		var rc: Dictionary = ConfigDb.data.get("raid", {}).get("revive", {})
		for i in int(raid.revived):
			var rr: float = float(rc.get("mark_radius_px", 19.0)) + float(rc.get("mark_step_px", 4.0)) * i
			for j in 3:   # three shards with two gaps and a break: reads as cracked
				var a0: float = TAU * j / 3.0 + 0.7 * i + 0.2
				draw_arc(Vector2.ZERO, rr, a0, a0 + TAU / 3.0 - 0.55, 10, Palette.c("relish", 0.8), 1.5)
	if _iframes > 0.0:
		draw_arc(Vector2.ZERO, radius + 8.0, 0, TAU, 24, Palette.c("danger", 0.6), 2.0)
	if hp < max_hp:
		_draw_hp_arc(violet)
	# trance focus / cooldown arc around her
	if raid != null and raid.trance != null:
		var tr = raid.trance
		if tr.state == RaidTrance.State.ACTIVE:
			var f: float = tr.focus_frac()
			LineGlow.arc(self, Vector2.ZERO, radius + 11.0, -PI * 0.5, -PI * 0.5 + TAU * f,
				violet, 3.0, 0.5, Palette.c("text"))
		elif tr.state == RaidTrance.State.COOLDOWN or tr.state == RaidTrance.State.LOCKOUT:
			# segmented (one per second of cooldown) so it reads by shape, not hue alone
			var segs := maxi(1, roundi(tr.cooldown_total))
			var left: float = tr.cooldown_frac() * segs
			var step := TAU / segs
			var gap := minf(0.2, step * 0.3)
			for i in segs:
				var fill := clampf(left - i, 0.0, 1.0)
				if fill > 0.0:
					var a0 := -PI * 0.5 + step * i + gap * 0.5
					LineGlow.arc(self, Vector2.ZERO, radius + 11.0, a0, a0 + (step - gap) * fill,
						Palette.c("cooldown"), 2.5, 0.5)


## The HP arc: a ring of segments (one per `hp_seg_hp` hp, so the damage is countable) that
## drains clockwise from the top as she is hurt; `relish`, turning `danger` at or below
## `hp_low_frac`. Empty segments stay as faint tracks.
func _draw_hp_arc(violet: Color) -> void:
	var c: Dictionary = ConfigDb.data.get("raid", {}).get("danger", {})
	var r := radius + float(c.get("hp_arc_gap_px", 18.0))
	var width := float(c.get("hp_arc_width", 3.0))
	var segs := clampi(ceili(max_hp / maxf(0.1, float(c.get("hp_seg_hp", 5.0)))), 1, 12)
	var frac := clampf(hp / max_hp, 0.0, 1.0)
	var col := Palette.c("danger") if frac <= float(c.get("hp_low_frac", 0.34)) else violet
	var step := TAU / segs
	var gap := minf(0.16, step * 0.3)
	for i in segs:
		var a0 := -PI * 0.5 + step * i + gap * 0.5
		var a1 := -PI * 0.5 + step * (i + 1) - gap * 0.5
		var fill := clampf(frac * segs - i, 0.0, 1.0)
		draw_arc(Vector2.ZERO, r, a0, a1, 8, Palette.c("relish", 0.18), width)
		if fill > 0.0:
			LineGlow.arc(self, Vector2.ZERO, r, a0, a0 + (a1 - a0) * fill, col, width, 0.5)
