class_name RaidPile
extends Node2D
## A grey, matte corpse pile. Dead matter never glows. When Relish walks close
## the pile stirs: its mass converts into 2-4 essence orbs.

var raid: Node = null
var mass := 4.0
var look_mass := -1.0       # >= 0: size the lumps as if the pile held this (the massless first pile)
var small := false          # boss remnants: dead undead, drawn smaller

var _stirred := false
var _shrink := -1.0
var _lumps: Array = []
var _lit := false           # Relish's light falls on it (dead_lit, still matte)


func _ready() -> void:
	z_index = 12
	add_to_group("raid_piles")
	var rng := RandomNumberGenerator.new()
	rng.seed = int(position.x * 13.0 + position.y * 7.0) + 11
	var base := clampf(9.0 + (mass if look_mass < 0.0 else look_mass) * 0.7, 9.0, 26.0)
	if small:
		base = clampf(5.0 + mass * 0.4, 5.0, 9.0)
	var n := rng.randi_range(3, 5)
	for i in n:
		_lumps.append({
			"off": Vector2(rng.randf_range(-base, base), rng.randf_range(-base * 0.6, base * 0.6)),
			"r": rng.randf_range(base * 0.4, base * 0.75),
			"shade": rng.randf_range(0.0, 1.0),
		})
	queue_redraw()


func _process(delta: float) -> void:
	if _shrink >= 0.0:
		_shrink += delta
		scale = Vector2.ONE * maxf(0.01, 1.0 - _shrink / 0.25)
		if _shrink >= 0.25:
			queue_free()
		return
	if raid == null:
		return
	var rel = raid.relish
	if rel == null or not is_instance_valid(rel) or not rel.alive:
		if not _stirred:
			_set_lit(false)
		return
	var d: float = global_position.distance_to(rel.global_position)
	var rcfg: Dictionary = ConfigDb.data.get("raid", {})
	# Relish's violet falls on the dead near her (matte, never emits)
	if not _stirred:
		_set_lit(d <= float(rcfg.get("relish", {}).get("light_radius_px", 220.0)))
		if d <= float(rcfg.get("essence", {}).get("stir_radius_px", 90.0)):
			stir()


func _set_lit(on: bool) -> void:
	if on != _lit:
		_lit = on
		queue_redraw()


## The pile stirs: convert its mass into essence orbs.
func stir() -> void:
	if _stirred:
		return
	_stirred = true
	_set_lit(true)  # her light is on it as it stirs; it stays matte
	remove_from_group("raid_piles")
	if raid != null:
		var e: Dictionary = ConfigDb.data.get("raid", {}).get("essence", {})
		var n: int = raid.rng_combat.randi_range(int(e.get("stir_orbs_min", 2)), int(e.get("stir_orbs_max", 4)))
		n = maxi(1, n)
		for i in n:
			var ang: float = raid.rng_combat.randf() * TAU
			# spawn_mote, not spawn_orb: the first dungeon's pile is massless (it mints no mass) and still stirs
			raid.spawn_mote(global_position + Vector2(raid.rng_combat.randf_range(4, 16), 0).rotated(ang),
				mass / n, false, Vector2(float(e.get("pop_speed_px", 85.0)), 0).rotated(ang))
	_shrink = 0.0


## Consumed whole by Vei's revive (no orbs — she takes the matter directly).
func consume() -> void:
	_stirred = true
	_set_lit(false)  # Vei takes it; no light of Relish's on it
	remove_from_group("raid_piles")
	_shrink = 0.0


func _draw() -> void:
	# Dead is matte: flat fills only, never a glow stroke.
	var base := Palette.c("dead_lit" if _lit else "dead")
	var dark := base.darkened(0.2)
	for l in _lumps:
		draw_circle(l["off"], l["r"], base.lerp(dark, l["shade"]))
	# a couple of matte bone slivers
	var bone := base.lightened(0.3)
	draw_line(Vector2(-6, 2), Vector2(5, -3), bone, 2.0)
	draw_line(Vector2(-2, 5), Vector2(7, 4), bone, 2.0)
