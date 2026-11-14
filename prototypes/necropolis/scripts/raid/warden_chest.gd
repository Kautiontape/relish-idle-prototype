class_name RaidChest
extends Node2D
## The warden's chest: a small box outline in vei with a lid stroke. It opens when Relish comes
## within `wardens.chest_open_px`; the run then ends warden_beaten (RaidWardenRun).

var raid: Node2D = null
var opened := false

var _t := 0.0


func _ready() -> void:
	z_index = 31
	queue_redraw()


func _physics_process(delta: float) -> void:
	_t += delta
	if raid == null or raid._ended or opened:
		return
	var rel: RaidRelish = raid.relish
	if rel != null and is_instance_valid(rel) and rel.alive \
			and rel.global_position.distance_to(global_position) <= float(raid.rcfg().get("wardens", {}).get("chest_open_px", 44.0)):
		opened = true
		queue_redraw()
		raid.warden_run.on_chest_opened(self)
	elif not opened:
		queue_redraw()


func _draw() -> void:
	var h := float(ConfigDb.data.get("raid", {}).get("wardens", {}).get("chest_half_px", 13.0))
	var col := Palette.c("vei")
	var box := PackedVector2Array([Vector2(-h, -h * 0.2), Vector2(h, -h * 0.2), Vector2(h, h * 0.8),
		Vector2(-h, h * 0.8), Vector2(-h, -h * 0.2)])
	if not opened:
		var glow := 0.6 + 0.4 * Pulse.wave()
		LineGlow.ring(self, Vector2.ZERO, h * 2.0, col, 1.0, 0.5 * glow)
		LineGlow.polyline(self, box, col, 2.4, 0.7)
		draw_line(Vector2(-h, -h * 0.2), Vector2(h, -h * 0.2), col, 2.4)
		draw_line(Vector2(-h, -h * 0.75), Vector2(h, -h * 0.75), col, 2.4)   # the lid stroke, closed
		draw_line(Vector2(-h, -h * 0.75), Vector2(-h, -h * 0.2), col, 2.0)
		draw_line(Vector2(h, -h * 0.75), Vector2(h, -h * 0.2), col, 2.0)
		draw_circle(Vector2(0, -h * 0.2), 2.4, Palette.c("text", 0.9))       # the latch
	else:
		LineGlow.polyline(self, box, col, 2.4, 0.7)
		draw_line(Vector2(-h, -h * 0.2), Vector2(-h * 1.15, -h * 1.1), col, 2.4)   # the lid thrown back
		draw_line(Vector2(-h * 1.15, -h * 1.1), Vector2(h * 0.85, -h * 1.1), col, 2.4)
		draw_line(Vector2(h * 0.85, -h * 1.1), Vector2(h, -h * 0.2), col, 2.0)
		LineGlow.ring(self, Vector2.ZERO, h * 1.6, Palette.c("text", 0.8), 1.5, 0.8, col)
