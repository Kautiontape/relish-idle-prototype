class_name RaidTraceOverlay
extends Control
## The loop's words, in screen space on the HUD's CanvasLayer: the live readout beside the pen while a loop is
## drawn (RaidLogic.loop_readout, raid.json trace_notch live_*) and the result's head and tail ("84 — GOOD",
## "×8 SOLDIER · strength ×1.34") around the fitted ring. The ring, its notches and the trace stay in the world
## (RaidTraceFeedback); this draws only the plates and their text, anchored at a world point's screen position
## (the viewport's canvas transform) and placed by RaidLogic.live_plate_rect / result_plate_rects: inside the
## viewport by trace_notch.screen_margin_px, flipped across the anchor where a side would leave the screen, and
## off the hint plate when they can move clear. RaidHud adds it just under the retreat panel, so it draws over the
## stat block, the legend and the rest of the HUD and under the retreat, death, clear and Vei cards (which the HUD
## adds above it, all on layer 10).

var raid: Node = null
var hud: Node = null

var _live_on := false
var _live_lines: Array = []
var _live_color := Color.WHITE
var _live_tip := Vector2.ZERO   # the pen tip, world
var _results := {}              # id -> {center, radius, head, tail, color, a} (center world, radius world px)


static func _words() -> Dictionary:
	return ConfigDb.data.get("raid", {}).get("trace_notch", {})


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## The pen tip `tip` (world) and the readout's `lines` (RaidLogic.loop_readout); `score` picks the head's band
## colour (RaidTraceFeedback.band_for) when `valid`, else the plain text colour.
func show_live(tip: Vector2, lines: Array, valid: bool, score: int) -> void:
	_live_on = true
	_live_tip = tip
	_live_lines = lines
	_live_color = Palette.c(str(RaidTraceFeedback.band_for(score).key)) if valid else Palette.c("text")
	queue_redraw()


func clear_live() -> void:
	_live_on = false
	_live_lines = []
	queue_redraw()


## A result's plates: the ring's centre and radius in world units, the head, the tail ("" for none), the text's
## colour and the plates' fade `a`. Called every frame the result is alive.
func show_result(id: int, center: Vector2, radius: float, head: String, tail: String, col: Color, a: float) -> void:
	_results[id] = {"center": center, "radius": radius, "head": head, "tail": tail, "color": col, "a": a}
	queue_redraw()


func clear_result(id: int) -> void:
	if _results.erase(id):
		queue_redraw()


func _process(_delta: float) -> void:
	size = get_viewport_rect().size   # a CanvasLayer parent gives the anchors nothing to resolve against
	if _live_on or not _results.is_empty():
		queue_redraw()   # the camera moves; the words do not grade again


func _live_px(i: int) -> float:
	var w := _words()
	return float(w.get("live_ladder_px", 15)) if i == _live_lines.size() - 1 else float(w.get("live_font_px", 20))


func _avoid() -> Array:
	if hud != null and is_instance_valid(hud) and hud.has_method("panel_rects"):
		return hud.panel_rects()   # the hint plate and the control legend
	return []


## A result plate: 12 px wider than its 22 px label, 27 tall.
func _plate_size(text: String) -> Vector2:
	return Vector2(ThemeDB.fallback_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x + 12.0, 27.0)


func _draw() -> void:
	if raid == null or not is_instance_valid(raid):
		return
	var xf: Transform2D = raid.get_canvas_transform()
	var view: Vector2 = get_viewport_rect().size
	var w := _words()
	var margin := float(w.get("screen_margin_px", 8))
	var avoid := _avoid()
	if _live_on and not _live_lines.is_empty():
		_draw_live(xf, view, w, margin, avoid)
	for id in _results:
		_draw_result(_results[id], xf, view, w, margin, avoid)


func _draw_live(xf: Transform2D, view: Vector2, w: Dictionary, margin: float, avoid: Array) -> void:
	var pad := float(w.get("live_pad_px", 8))
	var tw := 0.0
	var th := 0.0
	for i in _live_lines.size():
		var px := _live_px(i)
		tw = maxf(tw, ThemeDB.fallback_font.get_string_size(str(_live_lines[i]), HORIZONTAL_ALIGNMENT_LEFT, -1, int(px)).x)
		th += px + 4.0
	var psize := Vector2(tw + pad * 2.0, th + pad * 2.0 - 4.0)
	var rect := RaidLogic.live_plate_rect(psize, xf * _live_tip, float(w.get("live_gap_px", 26)), view, margin, avoid)
	draw_rect(rect, Palette.c("ground", float(w.get("live_plate_alpha", 0.92))))
	var y := rect.position.y + pad
	for i in _live_lines.size():
		var px := _live_px(i)
		var col := Palette.c("text_dim") if i == _live_lines.size() - 1 else _live_color
		draw_string(ThemeDB.fallback_font, Vector2(rect.position.x + pad, y + px * 0.8), str(_live_lines[i]),
			HORIZONTAL_ALIGNMENT_LEFT, -1, int(px), col)
		y += px + 4.0


func _draw_result(r: Dictionary, xf: Transform2D, view: Vector2, w: Dictionary, margin: float, avoid: Array) -> void:
	var z := maxf(0.01, xf.x.length())
	var head: String = r["head"]
	var tail: String = r["tail"]
	var ts := _plate_size(tail) if tail != "" else Vector2.ZERO
	var rects := RaidLogic.result_plate_rects(_plate_size(head), ts, xf * (r["center"] as Vector2), float(r["radius"]) * z,
		float(w.get("result_gap_px", 8)), float(w.get("result_stack_gap_px", 4)), view, margin, avoid)
	var a: float = r["a"]
	var col: Color = r["color"]
	_draw_plate(rects["head"], head, col, a)
	if tail != "":
		_draw_plate(rects["tail"], tail, col, a)


func _draw_plate(rect: Rect2, text: String, col: Color, a: float) -> void:
	draw_rect(rect, Palette.c("ground", 0.62 * a))
	draw_string(ThemeDB.fallback_font, rect.position + Vector2(6.0, 21.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, col)
