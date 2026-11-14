class_name RaidRoute
extends RefCounted
## Per-mover routing cache over LayoutLogic.waypoint. A mover that heads for a goal asks `steer`
## each physics frame. A direct answer (same room, or a clear line) tracks the live goal; a portal
## answer is cached and recomputed every `route_repath_s` (staggered per mover by `phase`), when the
## mover leaves the room it was routed from (an answer asked in a doorway band is kept until it steps
## into a room), or when it stands within DOORSTEP_PX of its waypoint (where waypoint's answer flips
## to the far side of the gap).

static var _seq := 0   # movers made since the last reset_seq (the stagger is a function of it)
static var recomputes := 0   # waypoint asks across every mover (the --raid-perf harness reads it)

const DOORSTEP_PX := 3.0   # LayoutLogic.waypoint steps through the gap once the mover is this near its doorstep

var _wp := Vector2.ZERO
var _direct := true
var _t := 0.0
var _room := Rect2()
var _banded := false   # the answer was asked in a doorway band (no room)
var _repath := 0.25
var _pad := 14.0


func _init(cfg: Dictionary = {}) -> void:
	_repath = float(cfg.get("route_repath_s", 0.25))
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
	var redo := _t <= 0.0
	if not redo:
		if _banded:
			redo = LayoutLogic.room_of(layout, pos) >= 0   # stepped out of the doorway into a room
		else:
			redo = not _room.has_point(pos)   # left the room it was routed from
	if not redo and not _direct:
		redo = pos.distance_squared_to(_wp) <= DOORSTEP_PX * DOORSTEP_PX   # on the doorstep: through the gap
	if redo:
		_t = _repath
		recomputes += 1
		_wp = LayoutLogic.waypoint(layout, pos, goal, radius, _pad)
		_direct = _wp == goal
		var r := LayoutLogic.room_of(layout, pos)
		_banded = r < 0
		_room = (layout["rooms"][r] as Rect2) if r >= 0 else Rect2()
	return goal if _direct else _wp


## This mover's phase within the repath interval (also staggers its target picks).
func stagger() -> float:
	return _t


## Force a recompute on the next `steer` (the goal jumped).
func reset() -> void:
	_t = 0.0
