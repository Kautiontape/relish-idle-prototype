class_name MapNodeCtx
extends RefCounted
## What every node layer draws from: the shared model's entries, the camera's zoom and tier, the
## selection, Relish's drawn position and wake, and the forts in her light. MapNodes fills it;
## the layers only read it.

var model: MapModel
var selected_id := ""
var zoom := 1.0
var tier := "mid"
var forts: Array = []
var vei := {}
var readout := {}  # MapModel.readout(): odds, sign, drain_s, backlog
var vei_pos := Vector2.ZERO
var vei_radius := 0.0
var cov_pos := Vector2.ZERO
var relish := {}
var relish_pos := Vector2.ZERO  # where the token is drawn (interpolated, offset above a node when standing)
var wake: Array = []  # Vector3(x, y, t seconds)
var lit := {}  # fort id -> true: inside Relish's light
var flip := {}  # realm.json "flip"
var r_vei := 0.0  # realm.json R_vei
var now_s := 0.0  # Pulse's clock, seconds


## One screen pixel in world px.
func px(n: float) -> float:
	return n / maxf(zoom, 0.001)


## The world width that draws as a hairline (nodes.hairline_screen_px on screen).
func hair_w() -> float:
	return px(float(NodeLogic.ncfg().get("hairline_screen_px", 1.0)))
