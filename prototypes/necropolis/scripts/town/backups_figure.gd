extends Control
## A vat's clone silhouette: a small standing Relish drawn as lines in `relish`, its stroke revealed
## by `grow` (0..1, like construction) over a faint ghost of the whole figure, fully lit (thicker,
## brighter) when `ready`. Redraws only when its state changes: it holds still under reduced motion.

var _tx: Dictionary = {}
var _grow := 0.0
var _ready_clone := false


func setup(tx: Dictionary) -> void:
	_tx = tx
	custom_minimum_size = Vector2(float(tx.get("fig_w_px", 56)), float(tx.get("fig_h_px", 96)))
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_state(grow: float, ready: bool) -> void:
	grow = clampf(grow, 0.0, 1.0)
	if is_equal_approx(grow, _grow) and ready == _ready_clone:
		return
	_grow = grow
	_ready_clone = ready
	queue_redraw()


func _draw() -> void:
	if _tx.is_empty():
		return
	var r := Rect2(Vector2(2, 2), size - Vector2(4, 4))
	var w := float(_tx.get("fig_w", 1.5))
	for pts in BackupsModel.reveal_strokes(_tx["figure"], r, 1.0):
		draw_polyline(pts, Palette.c("contour", float(_tx.get("fig_ghost", 0.35))), 1.0)
	if _ready_clone:
		for pts in BackupsModel.reveal_strokes(_tx["figure"], r, 1.0):
			LineGlow.polyline(self, pts, Palette.c("relish"), w * float(_tx.get("fig_ready_w_mul", 1.4)), float(_tx.get("fig_glow_ready", 1.0)))
	else:
		for pts in BackupsModel.reveal_strokes(_tx["figure"], r, _grow):
			LineGlow.polyline(self, pts, Palette.c("relish", float(_tx.get("fig_alpha_growing", 0.75))), w, float(_tx.get("fig_glow", 0.9)))
