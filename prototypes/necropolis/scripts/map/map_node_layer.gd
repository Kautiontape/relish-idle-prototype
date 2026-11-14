class_name MapNodeLayer
extends Node2D
## Base of one node kind's drawing: a static layer (redrawn only when the model, zoom, tier or
## selection changed) or a pulse layer (the beat-driven marks, redrawn every frame). Helpers for
## capped LineGlow strokes and for labels that stay 12+ screen px at every zoom on a plate.

const ALIGN_LEFT := -1
const ALIGN_CENTER := 0
const ALIGN_RIGHT := 1

var ctx: MapNodeCtx
var pulse := false
var draw_ms := 0.0  # accumulated since MapNodes last read it (the bench's drawing cost)

static var _bold: Font
static var _plate: StyleBoxFlat


func _draw() -> void:
	if ctx == null or ctx.model == null or ctx.model.realm.is_empty():
		return
	var t0 := Time.get_ticks_usec()  # lint-ok: bench timing
	if pulse:
		_draw_pulse()
	else:
		_draw_static()
	draw_ms += (Time.get_ticks_usec() - t0) / 1000.0  # lint-ok: bench timing


func _draw_static() -> void:
	pass


func _draw_pulse() -> void:
	pass


# --- strokes --------------------------------------------------------------------------

## A glowing arc: LineGlow's stack with the halos capped at `cap` px wide. Never for dead matter.
func glow_arc(c: Vector2, r: float, a0: float, a1: float, col: Color, w: float, glow: float, cap: float, core := LineGlow.NO_CORE) -> void:
	var seg := LineGlow.segments(r, a1 - a0)
	for l in NodeLogic.capped_layers(col, w, glow, cap, core):
		draw_arc(c, r, a0, a1, seg, l[1], l[0])


func glow_ring(c: Vector2, r: float, col: Color, w: float, glow: float, cap: float, core := LineGlow.NO_CORE) -> void:
	glow_arc(c, r, 0.0, TAU, col, w, glow, cap, core)


func glow_poly(pts: PackedVector2Array, col: Color, w: float, glow: float, cap: float, core := LineGlow.NO_CORE) -> void:
	for l in NodeLogic.capped_layers(col, w, glow, cap, core):
		draw_polyline(pts, l[1], l[0])


func diamond(p: Vector2, s: float, col: Color) -> void:
	draw_colored_polygon(PackedVector2Array([p + Vector2(0, -s), p + Vector2(s, 0), p + Vector2(0, s), p + Vector2(-s, 0)]), col)


# --- text -----------------------------------------------------------------------------

## A label anchored at world `anchor` (see draw_label), on this layer at the camera's zoom.
func text(anchor: Vector2, s: String, size: int, col: Color, align := ALIGN_CENTER, dy := 0.0, bold := false) -> void:
	draw_label(self, ctx.zoom, anchor, s, size, col, align, dy, bold)


## Text anchored at world `anchor`, drawn in screen pixels (counter-scaled by 1/zoom), so a
## `size` of 12 is 12 px on screen at any zoom, on the label plate (so the ground's streaks and
## the lanes never run through it). `dy` moves the baseline down in screen px; the text's top
## sits at the anchor when dy = size.
static func draw_label(ci: CanvasItem, zoom: float, anchor: Vector2, s: String, size: int, col: Color, align := ALIGN_CENTER, dy := 0.0, bold := false) -> void:
	var n := NodeLogic.ncfg()
	var font: Font = _bold_font() if bold else ThemeDB.fallback_font
	var sc := 1.0 / maxf(zoom, 0.001)
	ci.draw_set_transform(anchor, 0.0, Vector2(sc, sc))
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var x := 0.0
	if align == ALIGN_CENTER:
		x = -w * 0.5
	elif align == ALIGN_RIGHT:
		x = -w
	var pad := float(n["plate_pad_px"])
	plate(ci, Rect2(x - pad, dy - size * float(n["plate_ascent"]), w + pad * 2.0, size * float(n["plate_height"])), NodeLogic.label_plate_color())
	var sh := float(n["label_shadow_px"])
	ci.draw_string(font, Vector2(x + sh, dy + sh), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size,
		Palette.c("ground", float(MapLogic.cfg()["label_shadow_alpha"])))
	ci.draw_string(font, Vector2(x, dy), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## A label plate in the caller's current transform (screen px): `fill` with label_plate_radius_px
## corners, and a `border_w` px edge in `border` when given.
static func plate(ci: CanvasItem, rect: Rect2, fill: Color, border := LineGlow.NO_CORE, border_w := 0.0) -> void:
	if _plate == null:
		_plate = StyleBoxFlat.new()
		_plate.anti_aliasing = true
	_plate.bg_color = fill
	_plate.set_corner_radius_all(int(round(float(NodeLogic.ncfg()["label_plate_radius_px"]))))
	_plate.border_color = border
	_plate.set_border_width_all(int(round(border_w)))
	ci.draw_style_box(_plate, rect)


static func _bold_font() -> Font:
	if _bold == null:
		var fv := FontVariation.new()
		fv.base_font = ThemeDB.fallback_font
		fv.variation_embolden = float(NodeLogic.ncfg()["embolden"])
		_bold = fv
	return _bold
