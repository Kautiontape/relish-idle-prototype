class_name RaidPickup
extends Node2D
## A remnant dropped by a living kill, lying where it fell (a small `vei` line shard: loot is not
## dead matter, so it is never matte). It does not decay. Relish picks it up by walking within
## loot.json `pickup.radius_px`; only then does it join found_loot. Whatever is left on the floor
## when the run ends is lost.

var raid: Node = null
var remnant := {}
var _t := 0.0


func _ready() -> void:
	z_index = int(ConfigDb.data.get("loot", {}).get("pickup", {}).get("z", 16))
	add_to_group("raid_pickups")
	queue_redraw()


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _physics_process(_delta: float) -> void:
	if raid == null or raid._ended:
		return
	var rel = raid.relish
	if rel == null or not is_instance_valid(rel) or not rel.alive:
		return
	var reach := float(ConfigDb.data.get("loot", {}).get("pickup", {}).get("radius_px", 40.0))
	if global_position.distance_to(rel.global_position) <= reach:
		raid.collect_pickup(self)


func _draw() -> void:
	var s := float(ConfigDb.data.get("loot", {}).get("pickup", {}).get("size_px", 9.0))
	var glow := 0.45 + 0.25 * (0.0 if Pulse.reduced_motion else sin(_t * 3.0))
	var col := Palette.c("vei")
	# a shard: a leaning blade with a short crossbar
	var pts := PackedVector2Array([Vector2(-s * 0.55, s), Vector2(-s * 0.1, -s * 1.25), Vector2(s * 0.55, s * 0.2),
		Vector2(-s * 0.55, s)])
	LineGlow.polyline(self, pts, col, 2.4, glow)
	draw_line(Vector2(-s * 0.9, s * 0.35), Vector2(s * 0.7, -s * 0.35), col, 1.6)
