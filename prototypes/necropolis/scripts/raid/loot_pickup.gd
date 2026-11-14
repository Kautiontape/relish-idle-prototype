class_name RaidPickup
extends Node2D
## A loot item lying where it fell. Relish picks it up by walking within loot.json
## `pickup.radius_px`; only then does it join found_loot. It does not decay. Whatever is left on the
## floor when the run ends is lost. Today only remnants drop on the floor (a living kill's ding); the
## chest's relics, husks and blueprints go straight into the loot when it opens. Each kind still has
## its own glyph (RaidLoot.floor_glyph): a remnant's leaning shard and a husk's ribbed hull are dead
## matter (matte `dead`, `dead_lit` under Relish's light), a relic's gem and a blueprint's dashed sheet
## glow `vei`. Every pickup sits in a faint `vei` loot ring breathing on the tempo, so loot never
## reads as a corpse pile or an essence mote.

var raid: Node = null
var kind := "remnant"          # relic | remnant | husk | blueprint (RaidLoot.FLOOR_KINDS)
var remnant := {}              # the item: a remnant {aspect, rarity, magnitude}, a husk {kind}, a blueprint {id}
var _lit := false              # Relish's light falls on it
var _s := 9.0                  # glyph size (loot.json pickup.size_px)
var _pts := PackedVector2Array()   # the kind's outline, built once


func _ready() -> void:
	z_index = int(ConfigDb.data.get("loot", {}).get("pickup", {}).get("z", 16))
	add_to_group("raid_pickups")
	_s = float(ConfigDb.data.get("loot", {}).get("pickup", {}).get("size_px", 9.0))
	var s := _s
	match str(RaidLoot.floor_glyph(kind, false)["shape"]):
		"gem":
			_pts = PackedVector2Array([Vector2(0, -s * 1.2), Vector2(s, -s * 0.25), Vector2(0, s * 1.2),
				Vector2(-s, -s * 0.25), Vector2(0, -s * 1.2)])
		"scroll":
			_pts = PackedVector2Array([Vector2(-s, -s * 0.8), Vector2(s * 0.55, -s * 0.8), Vector2(s, -s * 0.35),
				Vector2(s, s * 0.8), Vector2(-s, s * 0.8), Vector2(-s, -s * 0.8)])
		"husk":
			_pts = PackedVector2Array([Vector2(0, -s * 1.2), Vector2(s * 0.75, -s * 0.6), Vector2(s * 0.75, s * 0.6),
				Vector2(0, s * 1.2), Vector2(-s * 0.75, s * 0.6), Vector2(-s * 0.75, -s * 0.6), Vector2(0, -s * 1.2)])
		_:
			_pts = PackedVector2Array([Vector2(-s * 0.55, s), Vector2(-s * 0.1, -s * 1.25), Vector2(s * 0.55, s * 0.2),
				Vector2(-s * 0.55, s)])
	queue_redraw()


func _process(_delta: float) -> void:
	queue_redraw()   # the loot ring breathes on the tempo (Pulse.wave is steady under reduced motion)


func _physics_process(_delta: float) -> void:
	if raid == null or raid._ended:
		return
	var rel = raid.relish
	if rel == null or not is_instance_valid(rel) or not rel.alive:
		return
	var reach := float(ConfigDb.data.get("loot", {}).get("pickup", {}).get("radius_px", 40.0))
	var d: float = global_position.distance_to(rel.global_position)
	if d <= reach:
		raid.collect_pickup(self)
	_lit = d <= float(ConfigDb.data.get("raid", {}).get("relish", {}).get("light_radius_px", 220.0))


func _draw() -> void:
	var s := _s
	var g := RaidLoot.floor_glyph(kind, _lit)
	var col := Palette.c(str(g["key"]))
	# the loot ring: what marks this as loot to pick up
	var beat := 0.55 + 0.45 * Pulse.wave()
	LineGlow.ring(self, Vector2.ZERO, s * 2.0, Palette.c("vei", 0.5 + 0.3 * beat), 1.3, 0.5 * beat)
	match str(g["shape"]):
		"gem":
			# a relic: a cut gem, a diamond with its table line
			LineGlow.polyline(self, _pts, col, 2.2, 0.6)
			draw_line(Vector2(-s, -s * 0.25), Vector2(s, -s * 0.25), col, 1.6)
		"scroll":
			# a blueprint: a dashed sheet with a folded corner
			for i in _pts.size() - 1:
				draw_dashed_line(_pts[i], _pts[i + 1], col, 2.0, 4.0)
			draw_line(_pts[1], Vector2(s * 0.55, -s * 0.35), col, 1.6)
			draw_line(Vector2(s * 0.55, -s * 0.35), _pts[2], col, 1.6)
		"husk":
			# a husk: a hollow hull with three ribs (dead matter, matte)
			LineGlow.matte_polyline(self, _pts, col, 2.2)
			for k in 3:
				var y := (-0.45 + 0.45 * k) * s
				draw_line(Vector2(-s * 0.5, y), Vector2(s * 0.5, y), col, 1.6)
		_:
			# a remnant: a leaning shard with a short crossbar (dead matter, matte)
			LineGlow.matte_polyline(self, _pts, col, 2.4)
			draw_line(Vector2(-s * 0.9, s * 0.35), Vector2(s * 0.7, -s * 0.35), col, 1.8)
