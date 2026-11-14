class_name TownUI
extends RefCounted
## Shared Covington UI helpers: styleboxes, labels, buttons, the oblique rate font.
## Every colour is Palette.c(key). Text is at least 12 px; buttons at least 44 px tall.

const MIN_TEXT := 12
const MIN_TARGET := 44.0
const SLANT_DEG := 9.0

static var _oblique: FontVariation = null


## Flat panel: `ground` fill, `contour` border.
static func panel_box() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Palette.c("ground")
	sb.border_color = Palette.c("contour")
	sb.set_border_width_all(1)
	sb.set_content_margin_all(8)
	return sb


## Button state box. state: "normal", "hover", "pressed", "disabled", "active".
## Border carries the state too: `select` (accent) for pressed and active.
static func button_box(state := "normal") -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Palette.c("ring_track")
	sb.border_color = Palette.c("contour")
	sb.set_border_width_all(1)
	sb.set_content_margin_all(8)
	match state:
		"hover":
			sb.bg_color = Palette.c("graticule")
		"pressed", "active":
			sb.border_color = Palette.c("select")
			sb.set_border_width_all(2)
			if state == "active":
				sb.bg_color = Palette.c("graticule")
		"disabled":
			sb.bg_color = Palette.c("ground")
	return sb


static func label(text: String, size := 14, key := "text") -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", maxi(size, MIN_TEXT))
	l.add_theme_color_override("font_color", Palette.c(key))
	return l


static func button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, MIN_TARGET)
	style_button(b)
	return b


static func style_button(b: Button) -> void:
	b.add_theme_stylebox_override("normal", button_box("normal"))
	b.add_theme_stylebox_override("hover", button_box("hover"))
	b.add_theme_stylebox_override("pressed", button_box("pressed"))
	b.add_theme_stylebox_override("hover_pressed", button_box("pressed"))
	b.add_theme_stylebox_override("disabled", button_box("disabled"))
	b.add_theme_stylebox_override("focus", button_box("pressed"))
	b.add_theme_font_size_override("font_size", 14)
	b.add_theme_color_override("font_color", Palette.c("text"))
	b.add_theme_color_override("font_hover_color", Palette.c("text"))
	b.add_theme_color_override("font_pressed_color", Palette.c("text"))
	b.add_theme_color_override("font_disabled_color", Palette.c("text_dim"))


## The slanted font for signed rates (cached).
static func oblique_font() -> FontVariation:
	if _oblique == null:
		_oblique = FontVariation.new()
		_oblique.variation_transform = Transform2D(Vector2(1, 0), Vector2(tan(deg_to_rad(SLANT_DEG)), 1), Vector2.ZERO)
	return _oblique


## A Label that shows a signed rate in the oblique font.
static func rate_label(text := "", size := 14, key := "text") -> Label:
	var l := label(text, size, key)
	l.add_theme_font_override("font", oblique_font())
	return l


## Signed per-second text: "+0.42/s", "−0.10/s" (true minus sign). `unit` replaces "s".
static func fmt_rate(x: float, unit := "s") -> String:
	var sign_ch := "−" if x < 0.0 else "+"
	return "%s%.2f/%s" % [sign_ch, absf(x), unit]


## Remove and free every child now (so rebuilds never stack).
static func clear(node: Node) -> void:
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()
