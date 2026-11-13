class_name LineGlow
extends RefCounted
## Fake bloom by stacked strokes (BRIEF §8: widths 10/6/3/1.5, alphas
## .10/.22/.65/1.0). No shaders, no SubViewports. Call from a CanvasItem's _draw():
##   LineGlow.polyline(self, pts, Palette.c("undead"), 2.0)
##   LineGlow.ring(self, pos, 24.0, Palette.c("relish"), 1.5, 0.6)
## `width` is the core stroke; halos scale with it (06-three-flow-geometry glowLane).
## `glow` scales halo alpha: 0 = core only, 1 = the full stack.
## `core` colours the innermost stroke (e.g. Palette.c("undead_core")); omitted = `col`.
##
## Dead matter never emits light: use matte_polyline / matte_arc / matte_ring
## (one flat stroke). Handing a glow function Palette "dead" or "dead_lit" errors
## and draws matte instead. Tuning: configs/line_glow.json.

## Default `core`: draw the core in the line's own colour.
const NO_CORE := Color(0, 0, 0, 0)
const CONFIG_FILE := "line_glow"

static var _widths := PackedFloat32Array()
static var _alphas := PackedFloat32Array()
static var _seg_px := 0.0
static var _seg_min := 0
static var _seg_max := 0
static var _loaded := false


static func configure(cfg: Dictionary) -> void:
	_widths = PackedFloat32Array(cfg.get("widths", []))
	_alphas = PackedFloat32Array(cfg.get("alphas", []))
	_seg_px = float(cfg.get("arc_segment_px", 0.0))
	_seg_min = int(cfg.get("arc_segments_min", 0))
	_seg_max = int(cfg.get("arc_segments_max", 0))
	if _widths.is_empty() or _widths.size() != _alphas.size() or _seg_px <= 0.0:
		push_error("LineGlow: configs/%s.json needs widths/alphas of equal length and arc_segment_px" % CONFIG_FILE)
	_loaded = true


## The stroke stack for one glowing line, outermost first: [[width, Color], ...].
## The last entry is the core, drawn at exactly `width`.
static func layers(col: Color, width: float, glow := 1.0, core := NO_CORE) -> Array:
	_ensure()
	var n := _widths.size()
	if n == 0:
		return [[width, col]]
	var k := width / _widths[n - 1]
	var out := []
	if glow > 0.0:
		for i in n - 1:
			out.append([_widths[i] * k, Color(col, clampf(col.a * _alphas[i] * glow, 0.0, 1.0))])
	var core_rgb := col if core.a <= 0.0 else core
	out.append([width, Color(core_rgb, col.a * _alphas[n - 1])])
	return out


## True for Palette "dead" and "dead_lit" at any alpha: matter that must stay matte.
static func is_dead(col: Color) -> bool:
	var rgb := Color(col, 1.0)
	return rgb.is_equal_approx(Palette.c("dead")) or rgb.is_equal_approx(Palette.c("dead_lit"))


# --- glowing -----------------------------------------------------------------

static func polyline(ci: CanvasItem, pts: PackedVector2Array, col: Color, width: float, glow := 1.0, core := NO_CORE) -> void:
	if pts.size() < 2:
		return
	if _refuse_dead(col):
		matte_polyline(ci, pts, col, width)
		return
	for l in layers(col, width, glow, core):
		ci.draw_polyline(pts, l[1], l[0])


## Angles in radians, as CanvasItem.draw_arc.
static func arc(ci: CanvasItem, center: Vector2, radius: float, a0: float, a1: float, col: Color, width: float, glow := 1.0, core := NO_CORE) -> void:
	if _refuse_dead(col):
		matte_arc(ci, center, radius, a0, a1, col, width)
		return
	var seg := segments(radius, a1 - a0)
	for l in layers(col, width, glow, core):
		ci.draw_arc(center, radius, a0, a1, seg, l[1], l[0])


static func ring(ci: CanvasItem, center: Vector2, radius: float, col: Color, width: float, glow := 1.0, core := NO_CORE) -> void:
	arc(ci, center, radius, 0.0, TAU, col, width, glow, core)


# --- matte (dead matter) -----------------------------------------------------

static func matte_polyline(ci: CanvasItem, pts: PackedVector2Array, col: Color, width: float) -> void:
	if pts.size() >= 2:
		ci.draw_polyline(pts, col, width)


static func matte_arc(ci: CanvasItem, center: Vector2, radius: float, a0: float, a1: float, col: Color, width: float) -> void:
	ci.draw_arc(center, radius, a0, a1, segments(radius, a1 - a0), col, width)


static func matte_ring(ci: CanvasItem, center: Vector2, radius: float, col: Color, width: float) -> void:
	matte_arc(ci, center, radius, 0.0, TAU, col, width)


# --- helpers -----------------------------------------------------------------

## Point count for an arc: about one segment per `arc_segment_px` of length.
static func segments(radius: float, sweep: float) -> int:
	_ensure()
	return clampi(int(ceil(absf(sweep) * radius / maxf(_seg_px, 0.001))), _seg_min, _seg_max)


static func _refuse_dead(col: Color) -> bool:
	if not is_dead(col):
		return false
	push_error("LineGlow: dead matter never emits light; use matte_* for Palette dead/dead_lit")
	return true


static func _ensure() -> void:
	if _loaded:
		return
	var raw = null
	var tree := Engine.get_main_loop() as SceneTree
	var db: Node = tree.root.get_node_or_null("ConfigDb") if tree != null else null
	if db != null:
		raw = (db.get("data") as Dictionary).get(CONFIG_FILE)
	if not raw is Dictionary:
		raw = JSON.parse_string(FileAccess.get_file_as_string("res://configs/%s.json" % CONFIG_FILE))
	configure(raw if raw is Dictionary else {})
