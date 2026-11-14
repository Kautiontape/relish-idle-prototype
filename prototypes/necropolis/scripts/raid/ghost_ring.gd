class_name RaidGhostRing
extends Node2D
## The first dungeon's teaching ring (GAMEPLAY 6): while the trance is open and nothing has been
## raised yet, a faint dashed `relish` ring sits round the best mote cluster near Relish, labelled
## "trace around the glow". It hides after the first raise, or when the trance ends. Same helper as
## the autopilot's raise circle: RaidLogic.ghost_ring.

var raid: Node = null
var _t := 0.0
var _ring := {"ok": false}
var _pts: Array = []   # the loose motes' positions, refilled in place each trance frame


func _ready() -> void:
	z_as_relative = false
	z_index = 37   # above the trance dim (36), under Relish (38)
	visible = false


func _cfg() -> Dictionary:
	return ConfigDb.data.get("raid", {}).get("ghost_ring", {})


func _process(delta: float) -> void:
	_t += delta
	var on: bool = raid != null and raid.trance_active and not raid.first_raise_done and not raid._ended \
		and raid.relish != null and is_instance_valid(raid.relish)
	if on:
		var c := _cfg()
		var motes := get_tree().get_nodes_in_group("raid_essence")
		_pts.resize(motes.size())   # sizes within its capacity reuse the storage
		var k := 0
		for o in motes:
			if is_instance_valid(o) and not o.absorbing:
				_pts[k] = o.global_position
				k += 1
		_pts.resize(k)
		_ring = RaidLogic.ghost_ring(_pts, raid.relish.global_position, float(c.get("reach_px", 300.0)),
			float(c.get("pad_px", 14.0)))
		on = bool(_ring["ok"])
	visible = on
	if on:
		queue_redraw()


func _draw() -> void:
	if not bool(_ring.get("ok", false)):
		return
	var c := _cfg()
	var ctr: Vector2 = _ring["center"]
	var rad: float = _ring["radius"]
	var dashes := maxi(6, int(c.get("dashes", 28)))
	var fill := clampf(float(c.get("dash_fill", 0.55)), 0.1, 0.95)
	var spin := 0.0 if Pulse.reduced_motion else _t * float(c.get("spin_rad_s", 0.25))
	var col := Palette.c("relish", float(c.get("alpha", 0.55)))
	var step := TAU / float(dashes)
	for i in dashes:
		var a0 := spin + step * i
		draw_arc(ctr, rad, a0, a0 + step * fill, 6, col, float(c.get("width_px", 3.0)))
	var font := ThemeDB.fallback_font
	var fs := int(c.get("label_px", 16))
	draw_string(font, ctr + Vector2(-120.0, -rad - 12.0), str(c.get("label", "trace around the glow")),
		HORIZONTAL_ALIGNMENT_CENTER, 240.0, fs, Palette.c("text", 0.85))
