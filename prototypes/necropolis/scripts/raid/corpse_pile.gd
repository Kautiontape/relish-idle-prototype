class_name RaidPile
extends Node2D
## A grey, matte corpse pile. Dead matter never glows. When Relish walks close
## the pile stirs: its mass converts into 2-4 essence orbs.

const GREY := Color("#6e6a7e")
const GREY_DARK := Color("#57536a")

var raid: Node = null
var mass := 4.0
var small := false          # boss remnants: dead undead, drawn smaller

var _stirred := false
var _shrink := -1.0
var _lumps: Array = []


func _ready() -> void:
	z_index = 12
	add_to_group("raid_piles")
	var rng := RandomNumberGenerator.new()
	rng.seed = int(position.x * 13.0 + position.y * 7.0) + 11
	var base := clampf(9.0 + mass * 0.7, 9.0, 26.0)
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
	if _stirred or raid == null:
		return
	var rel = raid.relish
	if rel == null or not is_instance_valid(rel) or not rel.alive:
		return
	var e: Dictionary = ConfigDb.data.get("raid", {}).get("essence", {})
	if global_position.distance_to(rel.global_position) <= float(e.get("stir_radius_px", 90.0)):
		stir()


## The pile stirs: convert its mass into essence orbs.
func stir() -> void:
	if _stirred:
		return
	_stirred = true
	remove_from_group("raid_piles")
	if raid != null:
		var e: Dictionary = ConfigDb.data.get("raid", {}).get("essence", {})
		var n := randi_range(int(e.get("stir_orbs_min", 2)), int(e.get("stir_orbs_max", 4)))
		n = maxi(1, n)
		for i in n:
			var ang := randf() * TAU
			raid.spawn_orb(global_position + Vector2(randf_range(4, 16), 0).rotated(ang),
				mass / n, Vector2(float(e.get("pop_speed_px", 85.0)), 0).rotated(ang))
	_shrink = 0.0


## Consumed whole by Vei's revive (no orbs — she takes the matter directly).
func consume() -> void:
	_stirred = true
	remove_from_group("raid_piles")
	_shrink = 0.0


func _draw() -> void:
	for l in _lumps:
		var c := GREY.lerp(GREY_DARK, l["shade"])
		draw_circle(l["off"], l["r"], c)
	# a couple of matte bone slivers
	draw_line(Vector2(-6, 2), Vector2(5, -3), Color(0.78, 0.76, 0.82, 0.55), 2.0)
	draw_line(Vector2(-2, 5), Vector2(7, 4), Color(0.72, 0.70, 0.78, 0.45), 2.0)
