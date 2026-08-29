class_name RaidVei
extends Node2D
## Vei: large white-gold figure at the far north end. Kit (all knobs in
## configs/raid.json "boss"): melee smite, RADIANT PULSE (telegraphed ring that
## deletes crowds), REVIVE (recycles corpses/essence into living guards),
## passive heal when no undead is in contact.

const GOLD := Color("#fff3d0")
const DANGER := Color("#ff2d55")
const ORANGE := Color("#ff6a2b")

var boss: Node = null
var hp := 2000.0
var max_hp := 2000.0
var radius := 46.0
var alive := true

var _t := 0.0
var _flash := 0.0
var _smite_t := 2.0
var _pulse_t := 5.0
var _windup := -1.0          # >= 0 while telegraphing the pulse
var _revive_cd := 4.0
var _channel := -1.0         # >= 0 while channeling revive
var _channel_targets: Array = []
var _channel_mass := 0.0


func bcfg() -> Dictionary:
	return ConfigDb.data.get("raid", {}).get("boss", {})


func configure(p_boss: Node, odds: float) -> void:
	boss = p_boss
	var b := bcfg()
	radius = float(b.get("radius", 46.0))
	max_hp = float(b.get("hp_base", 1400.0)) \
		+ float(b.get("hp_per_missing_odds", 3200.0)) * maxf(0.0, float(b.get("odds_pivot", 0.8)) - odds)
	hp = max_hp
	_pulse_t = _pulse_cadence()
	z_index = 34


func _pulse_cadence() -> float:
	var b := bcfg()
	# quickens as her HP drops
	return lerpf(float(b.get("pulse_cadence_low_s", 3.2)), float(b.get("pulse_cadence_full_s", 9.0)),
		clampf(hp / maxf(1.0, max_hp), 0.0, 1.0))


func take_hit(amount: float) -> void:
	if not alive:
		return
	hp -= amount
	_flash = 1.0
	if hp <= 0.0:
		hp = 0.0
		alive = false
		boss.on_vei_died()
	queue_redraw()


func _physics_process(delta: float) -> void:
	if boss == null or boss._ended or not alive:
		return
	_t += delta
	_flash = maxf(0.0, _flash - delta * 3.0)
	var b := bcfg()

	# --- melee smite ---
	_smite_t -= delta
	if _smite_t <= 0.0:
		var range_px: float = float(b.get("smite_range_px", 92.0))
		var struck := 0
		for a in boss.allies.duplicate():
			if struck >= int(b.get("smite_targets", 4)):
				break
			if is_instance_valid(a) and a.alive \
					and a.global_position.distance_to(global_position) <= range_px + radius:
				a.take_hit(float(b.get("smite_dmg", 16.0)))
				struck += 1
		var rel = boss.relish
		if rel != null and is_instance_valid(rel) and rel.alive \
				and rel.global_position.distance_to(global_position) <= range_px + radius:
			rel.take_hit(float(b.get("smite_dmg_relish", 12.0)))
			struck += 1
		if struck > 0:
			_smite_t = float(b.get("smite_cadence_s", 1.1))
			RaidFx.ring(boss.fx_root, global_position, Color(GOLD.r, GOLD.g, GOLD.b, 0.7),
				range_px + radius, 0.25, 2.0)
		else:
			_smite_t = 0.15  # nothing in reach — check again soon

	# --- radiant pulse ---
	if _windup >= 0.0:
		_windup += delta
		if _windup >= float(b.get("pulse_windup_s", 1.2)):
			_windup = -1.0
			_do_pulse(b)
	elif _channel < 0.0:
		_pulse_t -= delta
		if _pulse_t <= 0.0:
			_windup = 0.0

	# --- revive: she recycles the dead ---
	if _channel >= 0.0:
		_channel += delta
		if _channel >= float(b.get("revive_channel_s", 2.0)):
			_channel = -1.0
			_do_revive(b)
	else:
		_revive_cd -= delta
		if _revive_cd <= 0.0 and _windup < 0.0:
			_try_start_revive(b)

	# --- passive: heals while no undead is in melee contact ---
	var contact := radius + float(b.get("heal_contact_pad_px", 42.0))
	var touched := false
	for a in boss.allies:
		if is_instance_valid(a) and a.alive and a.global_position.distance_to(global_position) <= contact:
			touched = true
			break
	if not touched:
		hp = minf(max_hp, hp + float(b.get("heal_per_s", 6.0)) * delta)

	queue_redraw()


func _do_pulse(b: Dictionary) -> void:
	var r: float = float(b.get("pulse_radius_px", 340.0))
	RaidFx.ring(boss.fx_root, global_position, GOLD, r, 0.5, 6.0)
	RaidFx.ring(boss.fx_root, global_position, Color(1, 1, 1, 0.9), r * 0.7, 0.35, 3.0)
	for a in boss.allies.duplicate():
		if not is_instance_valid(a) or not a.alive:
			continue
		if a.global_position.distance_to(global_position) > r:
			continue
		if a.kind == "chaff":
			a.die()  # she deletes crowds
		else:
			a.take_hit(float(b.get("pulse_dmg_soldier", 30.0)))
	var rel = boss.relish
	if rel != null and is_instance_valid(rel) and rel.alive \
			and rel.global_position.distance_to(global_position) <= r:
		rel.take_hit(float(b.get("pulse_dmg_relish", 10.0)))
	_pulse_t = _pulse_cadence()


func _try_start_revive(b: Dictionary) -> void:
	var r: float = float(b.get("revive_radius_px", 400.0))
	var targets: Array = []
	var mass := 0.0
	for e in get_tree().get_nodes_in_group("raid_essence"):
		if is_instance_valid(e) and not e.absorbing \
				and e.global_position.distance_to(global_position) <= r:
			targets.append(e)
			mass += e.mass
	for p in get_tree().get_nodes_in_group("raid_piles"):
		if is_instance_valid(p) and p.global_position.distance_to(global_position) <= r:
			targets.append(p)
			mass += p.mass
	var guards := 0
	for e in boss.enemies:
		if is_instance_valid(e) and e.alive and e.kind == "guard":
			guards += 1
	if mass >= float(b.get("revive_min_mass", 24.0)) and guards < int(b.get("revive_guard_cap", 18)):
		_channel = 0.0
		_channel_targets = targets
		_channel_mass = mass


func _do_revive(b: Dictionary) -> void:
	var mass := 0.0
	for t in _channel_targets:
		if not is_instance_valid(t):
			continue
		if t is RaidEssence:
			if not t.absorbing:
				mass += t.mass
				t.queue_free()
		elif t is RaidPile:
			mass += t.mass
			t.consume()
	_channel_targets = []
	var guards := 0
	for e in boss.enemies:
		if is_instance_valid(e) and e.alive and e.kind == "guard":
			guards += 1
	var n := clampi(int(mass / float(b.get("revive_mass_per_guard", 10.0))),
		1, maxi(1, int(b.get("revive_guard_cap", 18)) - guards))
	for i in n:
		var ang := PI * 0.5 + randf_range(-1.1, 1.1)  # fan out on her south side
		var pos := global_position + Vector2(radius + 40.0 + randf() * 70.0, 0).rotated(ang)
		var u = boss.spawn_unit("enemy", "guard", boss.resolve_walls(pos, 10.0), true)
		u.mass = float(b.get("guard", {}).get("mass", 10.0))
	RaidFx.ring(boss.fx_root, global_position, ORANGE, 120.0, 0.5, 3.0)
	_revive_cd = float(b.get("revive_cooldown_s", 7.0))


func _draw() -> void:
	var b := bcfg()
	# radiant pulse telegraph: expanding indicator circle
	if _windup >= 0.0:
		var wind_f := _windup / maxf(0.05, float(b.get("pulse_windup_s", 1.2)))
		var r: float = float(b.get("pulse_radius_px", 340.0))
		draw_circle(Vector2.ZERO, r, Color(GOLD.r, GOLD.g, GOLD.b, 0.05 + 0.05 * wind_f))
		draw_arc(Vector2.ZERO, r, 0, TAU, 64, Color(DANGER.r, DANGER.g, DANGER.b, 0.4 + 0.5 * wind_f), 3.0)
		draw_arc(Vector2.ZERO, r * wind_f, 0, TAU, 48, Color(GOLD.r, GOLD.g, GOLD.b, 0.8), 2.0)
	# revive channel: golden gathering glow
	if _channel >= 0.0:
		var ch_f := _channel / maxf(0.05, float(b.get("revive_channel_s", 2.0)))
		var rr: float = float(b.get("revive_radius_px", 400.0))
		draw_arc(Vector2.ZERO, rr * (1.0 - ch_f * 0.7), 0, TAU, 64,
			Color(ORANGE.r, ORANGE.g, ORANGE.b, 0.35 + 0.3 * ch_f), 2.5)
	# halo + rays: imposing white-gold
	draw_circle(Vector2.ZERO, radius * 2.4, Color(GOLD.r, GOLD.g, GOLD.b, 0.05))
	draw_circle(Vector2.ZERO, radius * 1.7, Color(GOLD.r, GOLD.g, GOLD.b, 0.09))
	for i in 12:
		var ang := TAU * i / 12.0 + _t * 0.25
		var a0 := Vector2(radius + 10.0, 0).rotated(ang)
		var a1 := Vector2(radius + 30.0 + 6.0 * sin(_t * 2.0 + i), 0).rotated(ang)
		draw_line(a0, a1, Color(GOLD.r, GOLD.g, GOLD.b, 0.55), 2.5)
	draw_arc(Vector2.ZERO, radius + 9.0, 0, TAU, 48, Color(GOLD.r, GOLD.g, GOLD.b, 0.85), 2.5)
	var body := GOLD
	if _flash > 0.0:
		body = body.lerp(DANGER, minf(0.7, _flash))
	if not alive:
		body = Color(0.5, 0.48, 0.55)
	draw_circle(Vector2.ZERO, radius, body)
	draw_circle(Vector2.ZERO, radius * 0.62, Color(1, 1, 1, 0.85))
	# a stern face slit
	draw_line(Vector2(-10, -6), Vector2(-4, -6), Color(0.25, 0.2, 0.1, 0.8), 2.5)
	draw_line(Vector2(4, -6), Vector2(10, -6), Color(0.25, 0.2, 0.1, 0.8), 2.5)
