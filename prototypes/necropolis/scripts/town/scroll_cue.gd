class_name ScrollCue
extends Control
## The dock's "more below" cue (clarity round 3): while the tab on show has content below its scroll's bottom edge,
## that edge fades into the ground and a short line says to scroll, so a row the edge cuts reads as more to scroll
## to, not as clipped text. It sits over the shown panel's ScrollContainer (the covington shell sets `scroll` on
## each tab change), ignores the mouse, and redraws only when it shows, hides or moves. Text and sizes are
## town.json `view.scroll_cue`.

var scroll: ScrollContainer = null
var _cfg: Dictionary = {}
var _rect := Rect2()


func setup(cfg: Dictionary) -> void:
	_cfg = cfg
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


## Whether a scroll whose bar reads `value` of `max_value`, showing `page` of it, has more than `eps` px below.
static func more_below(value: float, page: float, max_value: float, eps: float) -> bool:
	return max_value - page - value > eps


func _process(_delta: float) -> void:
	var on := scroll != null and scroll.is_visible_in_tree()
	if on:
		var bar := scroll.get_v_scroll_bar()
		on = more_below(bar.value, bar.page, bar.max_value, float(_cfg.get("eps_px", 2.0)))
	if not on:
		visible = false
		return
	var h := float(_cfg.get("h_px", 40.0))
	var sr := scroll.get_global_rect()
	var r := Rect2(Vector2(sr.position.x, sr.end.y - h) - get_parent_control().global_position, Vector2(sr.size.x, h))
	if not visible or r != _rect:
		_rect = r
		position = r.position
		size = r.size
		visible = true
		queue_redraw()


func _draw() -> void:
	var g := Palette.c("ground")
	var clear := Color(g, 0.0)
	var fade := float(_cfg.get("fade_frac", 0.5))  # the top part fades in; the rest is solid ground under the line
	var y := size.y * fade
	draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(size.x, 0.0), Vector2(size.x, y), Vector2(0.0, y)]),
		PackedColorArray([clear, clear, g, g]))
	draw_rect(Rect2(0.0, y, size.x, size.y - y), g)
	var font := ThemeDB.fallback_font
	var fs := maxi(int(_cfg.get("px", 13)), TownUI.MIN_TEXT)
	var text := String(_cfg.get("text", ""))
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var base := size.y - float(_cfg.get("pad_px", 4.0)) - font.get_descent(fs)
	draw_string(font, Vector2((size.x - w) * 0.5, base), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
		Palette.c(String(_cfg.get("ink", "text"))))
