class_name RaidHuntsman
extends RaidWarden
## The Huntsman (MECHANICS 5.3): stalks Relish inside its room and lunges on the tempo. A lunge is
## telegraphed for tell_beats as a danger line to a locked point plus a reticle; on the beat it
## dashes there. A speedy big undead on the path intercepts it (the dash stops at it, the unit takes
## a hit, the Huntsman is stunned and takes extra damage). Otherwise a lunge that reaches Relish is
## a "catch" (counted even when a sacrifice soaks the hit); catches advance its phases.
## While Relish is outside its room it hunts her undead instead (the nearest in or entering the room,
## WardenLogic.hunt_target): same tell, same lunge, no catches, units on the path take the hit. So
## hiding outside costs units, and she is not safe forever.

var catches := 0
var stun_left := 0.0           # scene seconds of stun remaining
var _room := Rect2()
var _next_attack := 0.0        # beat of the next lunge
var _last_attack := 0.0
var _locked := false           # a tell is showing and the target point is fixed
var _lock_pt := Vector2.ZERO
var _dash_to := Vector2.ZERO
var _dashing := false
var _dash_left := 0.0
var _lunges := 0
var intercepts := 0            # lunges a fast big undead stopped (autopilot telemetry)
var _aim := Vector2.RIGHT      # heading drawn as the spear
var _lunge_flash := 0.0
var _hunting_undead := false   # this frame's target is an undead, not Relish
var _lock_undead := false      # the locked lunge is aimed at an undead: it cannot catch
var _route: RaidRoute = null   # stalk steering (the goal is leash-clamped, so it is a direct line today)


func _on_wake() -> void:
	var rooms: Array = raid.layout["rooms"]
	_room = rooms[int(raid.layout["warden_room"])]
	_next_attack = WardenLogic.period_beats(spec, phase)
	_route = RaidRoute.new(ConfigDb.data.get("raid", {}).get("combat", {}))


func is_stationary() -> bool:
	return false


func _phase_now() -> int:
	return WardenLogic.huntsman_phase(spec, catches)


func is_stunned() -> bool:
	return stun_left > 0.0


func take_hit(amount: float) -> void:
	super.take_hit(WardenLogic.stun_damage(spec, amount, is_stunned()))


func _on_phase_change(old: int, new: int) -> void:
	super._on_phase_change(old, new)
	if not _locked and not _dashing:
		var tell := _tell()
		_next_attack = minf(_next_attack, maxf(beat() + tell, _last_attack + WardenLogic.period_beats(spec, new)))


func _tell() -> float:
	return float(spec.get("attack", {}).get("tell_beats", 1.0))


func _speed_now() -> float:
	var phs: Array = spec.get("phases", [])
	return float((phs[clampi(phase, 0, phs.size() - 1)] as Dictionary).get("speed", 140.0))


## Who it hunts now: Relish in the room, else the nearest undead in or entering it, else nobody.
func _hunt() -> Dictionary:
	var units: Array = []
	for a in raid.allies:
		if is_instance_valid(a) and a.alive:
			units.append(a.global_position)
	var rel: RaidRelish = raid.relish
	var rel_ok := rel != null and is_instance_valid(rel) and rel.alive
	return WardenLogic.hunt_target(_room, rel.global_position if rel_ok else Vector2.INF, rel_ok, units,
		global_position, float(spec.get("attack", {}).get("hunt_margin_px", 40.0)))


func _step(delta: float) -> void:
	_lunge_flash = maxf(0.0, _lunge_flash - delta * 3.0)
	_update_hud()
	if _dashing:
		_advance_dash(delta)
	if stun_left > 0.0:
		stun_left = maxf(0.0, stun_left - delta)
		return
	if _dashing:
		return
	var b := beat()
	var tell := _tell()
	var at: Dictionary = spec.get("attack", {})
	var tgt := _hunt()
	_hunting_undead = tgt["kind"] == "undead"
	# tell: lock the target point at Relish's position while she is in the room, else at an undead
	if not _locked and b >= _next_attack - tell and tgt["kind"] != "none":
		var late := b > _next_attack - tell + 0.1
		_lock_pt = WardenLogic.lunge_target(global_position, tgt["pos"], float(at.get("range_px", 320.0)))
		_lock_undead = _hunting_undead
		_locked = true
		if late:
			_next_attack = ceilf(b + tell)   # stay on the tempo: snap to a whole beat
	if _locked:
		_aim = _lock_pt - global_position
		var rel0: RaidRelish = raid.relish
		if rel0 != null and is_instance_valid(rel0) and rel0.alive \
				and WardenLogic.lunge_hits(global_position, _lock_pt, rel0.global_position, float(at.get("hit_radius_px", 22.0)) + rel0.radius):
			raid.danger_targeted()   # the lunge tell is aimed at her
		if b >= _next_attack:
			_begin_lunge()
		return   # planted while the tell shows
	_stalk(delta, float(at.get("stalk_stop_px", 150.0)), tgt)


func _stalk(delta: float, stop_px: float, tgt: Dictionary) -> void:
	var goal := _room.get_center() if tgt["kind"] == "none" else WardenLogic.leash_clamp(_room, tgt["pos"], radius)
	var to_goal := goal - global_position
	var wait := 6.0 if tgt["kind"] == "none" else stop_px
	if to_goal.length() <= wait:
		return
	var dir := to_goal.normalized()
	if _route != null:
		var steer := _route.steer(raid.layout, global_position, goal, radius, delta) - global_position
		if steer.length() > 1.0:
			dir = steer.normalized()
	_aim = dir
	var want := global_position + dir * _speed_now() * delta
	var got: Vector2 = raid.resolve_walls(want, radius)
	if (got - global_position).length() < _speed_now() * delta * 0.3:
		var gx: Vector2 = raid.resolve_walls(global_position + Vector2(dir.x, 0) * _speed_now() * delta, radius)
		var gy: Vector2 = raid.resolve_walls(global_position + Vector2(0, dir.y) * _speed_now() * delta, radius)
		got = gx if (gx - global_position).length() > (gy - global_position).length() else gy
	global_position = WardenLogic.leash_clamp(_room, got, radius)


## Where the dash really ends: along from->to, stopping at the first wall.
func _wall_clipped(from: Vector2, to: Vector2) -> Vector2:
	var dist := from.distance_to(to)
	var steps := int(dist / 8.0)
	var last := from
	for i in range(1, steps + 1):
		var p := from.lerp(to, float(i) / float(steps))
		if raid.resolve_walls(p, radius).distance_to(p) > 1.0:
			return last
		last = p
	return to if raid.resolve_walls(to, radius).distance_to(to) <= 1.0 else last


func _begin_lunge() -> void:
	var at: Dictionary = spec.get("attack", {})
	var from := global_position
	var to := _wall_clipped(from, WardenLogic.leash_clamp(_room, _lock_pt, radius))
	var undead_hunt := _lock_undead   # aimed at an undead: no catches
	_last_attack = _next_attack
	_next_attack = _last_attack + WardenLogic.period_beats(spec, phase)
	_locked = false
	_lock_undead = false
	_lunges += 1
	_lunge_flash = 1.0
	# the weak point: fast big undead near the path
	var cands: Array = []
	var pool: Array = []
	for a in raid.allies:
		if is_instance_valid(a) and a.alive and a.kind == "big":
			cands.append({"pos": a.global_position, "speed": a.speed_stat})
			pool.append(a)
	var hit_i := WardenLogic.lunge_interceptor(spec, from, to, cands)
	var hit_r := float(at.get("hit_radius_px", 22.0))
	var dmg_u := float(at.get("dmg_unit", 8.0))
	var outcome := "miss"
	var done := {}
	if hit_i >= 0:
		var ic: RaidUnit = pool[hit_i]
		to = WardenLogic.lunge_stop(from, to, ic.global_position)
		ic.take_hit(dmg_u)
		done[ic] = true
		stun_left = float(spec.get("weak_point", {}).get("stun_beats", 2.0)) * tempo_s()
		_next_attack = maxf(_next_attack, ceilf(beat() + float(spec.get("weak_point", {}).get("stun_beats", 2.0)) + _tell()))
		outcome = "intercepted"
		intercepts += 1
		RaidFx.ring(raid.fx_root, to, Palette.c("undead"), 70.0, 0.5, 3.5)
		RaidFx.ring(raid.fx_root, to, Palette.c("text", 0.8), 36.0, 0.35, 2.5)
	# undead touched along the dash take dmg_unit, once each
	for a in raid.allies.duplicate():
		if not is_instance_valid(a) or not a.alive or done.has(a):
			continue
		if WardenLogic.lunge_hits(from, to, a.global_position, hit_r + a.radius):
			done[a] = true
			a.take_hit(dmg_u)
	if hit_i < 0 and not undead_hunt:
		var rel: RaidRelish = raid.relish
		if rel != null and is_instance_valid(rel) and rel.alive \
				and WardenLogic.lunge_hits(from, to, rel.global_position, hit_r + rel.radius):
			outcome = "caught"
			catches += 1
			rel.take_hit(float(at.get("dmg_relish", 12.0)))
	_dash_to = to
	_dash_left = from.distance_to(to)
	_dashing = true
	_aim = to - from
	if raid._standalone:
		print("RAID_WARDEN lunge n=%d %s%s catches=%d phase=%d undead_hit=%d frame=%d" % [_lunges, outcome, " (hunting undead)" if undead_hunt else "", catches, phase, done.size(), Engine.get_process_frames()])
	if _dash_left <= 0.5:
		_dashing = false


func _advance_dash(delta: float) -> void:
	var at: Dictionary = spec.get("attack", {})
	var step := minf(_dash_left, float(at.get("speed_px_s", 900.0)) * delta)
	var dir := (_dash_to - global_position).normalized()
	global_position += dir * step
	_dash_left -= step
	if _dash_left <= 0.5:
		global_position = _dash_to
		_dashing = false


func _update_hud() -> void:
	if raid.hud != null:
		raid.hud.set_warden_line("CAUGHT %d%s%s" % [catches, "   HUNTING YOUR DEAD" if _hunting_undead else "",
			"   INTERCEPTED" if is_stunned() else ""],
			"undead" if is_stunned() else "danger")


func _exit_tree() -> void:
	if raid != null and is_instance_valid(raid) and raid.hud != null:
		raid.hud.set_warden_line("", "danger")


# ------------------------------------------------------------------- draw ---
func _draw() -> void:
	if not awake or not is_stunned():
		super._draw()
	else:
		# stunned: the rings wobble (still under reduced motion) and break
		var w := float(spec.get("attack", {}).get("stun_wobble_px", 3.5))
		var s := 0.0 if Pulse.reduced_motion else sin(_breath_t * 38.0)
		draw_set_transform(Vector2(s * w, cos(_breath_t * 31.0) * w * (0.0 if Pulse.reduced_motion else 1.0)), s * 0.06, Vector2.ONE * (1.0 + 0.03 * s))
		super._draw()
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		var n := rings_left()
		for i in n:
			var r := _ring_r(i)
			for k in 3:
				var a0 := TAU * (k / 3.0) + 0.5 * i
				draw_arc(Vector2.ZERO, r, a0, a0 + 0.22, 6, Palette.c("ground", 0.95), 4.0)
	if awake:
		# the spear: a short heading stroke towards its target
		var dir := _aim.normalized() if _aim.length() > 0.01 else Vector2.RIGHT
		var col := Palette.c("danger") if (_locked or _dashing) else Palette.c("living")
		var base := dir * radius * 1.05
		var tip := dir * radius * 1.75
		LineGlow.polyline(self, PackedVector2Array([base, tip]), col, 3.0, 0.6)
		draw_line(tip, tip - dir.rotated(0.5) * 9.0, col, 3.0)
		draw_line(tip, tip - dir.rotated(-0.5) * 9.0, col, 3.0)


func _draw_telegraph(ci: CanvasItem) -> void:
	var b := beat()
	if _locked:
		var f := clampf((b - (_next_attack - _tell())) / maxf(0.01, _tell()), 0.0, 1.0)
		var to := _lock_pt - global_position
		LineGlow.polyline(ci, PackedVector2Array([Vector2.ZERO, to]), Palette.c("danger", 0.4 + 0.5 * f), 3.0, 0.6)
		var rr := 12.0 + 10.0 * (1.0 - f)
		LineGlow.ring(ci, to, rr, Palette.c("danger", 0.5 + 0.5 * f), 2.5, 0.6)
		ci.draw_line(to + Vector2(-rr - 5.0, 0), to + Vector2(rr + 5.0, 0), Palette.c("danger", 0.8), 1.5)
		ci.draw_line(to + Vector2(0, -rr - 5.0), to + Vector2(0, rr + 5.0), Palette.c("danger", 0.8), 1.5)
	if _dashing:
		var to2 := _dash_to - global_position
		ci.draw_line(Vector2.ZERO, to2, Palette.c("danger", 0.7 * _lunge_flash), 6.0)
	if is_stunned():
		var font := ThemeDB.fallback_font
		ci.draw_string(font, Vector2(-60, -radius * 1.8 - 22.0), "INTERCEPTED", HORIZONTAL_ALIGNMENT_CENTER, 120.0, 16, Palette.c("undead"))
