class_name RaidRoute
extends RefCounted
## Per-mover routing cache over LayoutLogic.waypoint. A mover that heads for a goal asks `steer`
## each physics frame. A direct answer (same room, or a clear line) tracks the live goal; a portal
## answer is cached and recomputed every `route_repath_s` (staggered per mover by `phase`), when the
## mover leaves the room it was routed from, or when it gets within `route_arrive_px` of it.

static var _seq := 0   # movers made since the last reset_seq (the stagger is a function of it)

var _wp := Vector2.ZERO
var _direct := true
var _t := 0.0
var _room := Rect2()
var _repath := 0.25
var _arrive := 40.0
var _pad := 14.0


func _init(cfg: Dictionary = {}) -> void:
	_repath = float(cfg.get("route_repath_s", 0.25))
	_arrive = float(cfg.get("route_arrive_px", 40.0))
	_pad = float(cfg.get("route_door_pad_px", 14.0))
	_seq += 1
	_t = fmod(float(_seq) * 0.6180339887, 1.0) * _repath   # golden-ratio stagger, deterministic


## Restart the stagger sequence. The raid calls it when it builds, before it makes any mover, so
## two same-seed raids in one process stagger (and so play) the same.
static func reset_seq() -> void:
	_seq = 0


## The point to move toward this frame.
func steer(layout: Dictionary, pos: Vector2, goal: Vector2, radius: float, delta: float) -> Vector2:
	_t -= delta
	if _t <= 0.0 or not _room.has_point(pos) or (not _direct and pos.distance_squared_to(_wp) < _arrive * _arrive):
		_t = _repath
		_wp = LayoutLogic.waypoint(layout, pos, goal, radius, _pad)
		_direct = _wp == goal
		var r := LayoutLogic.room_of(layout, pos)
		_room = (layout["rooms"][r] as Rect2) if r >= 0 else Rect2()
	return goal if _direct else _wp


## This mover's phase within the repath interval (also staggers its target picks).
func stagger() -> float:
	return _t


## Force a recompute on the next `steer` (the goal jumped).
func reset() -> void:
	_t = 0.0
