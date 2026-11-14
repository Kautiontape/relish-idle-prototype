class_name MapType
extends RefCounted
## The type law (VISUAL-LANGUAGE law 11), as fonts. Rates are oblique (a 9 degree skew), light and
## always signed with /s; masses and counts are upright, heavy and unsigned; labels and prose are
## upright and regular. Every font is a FontVariation on the project's default font, cached.
## Numbers (skew, weights, sizes; none under 12 px) live in configs/map_view.json "type".
## Colours are Palette keys: "text" for rates and masses, "text_dim" for labels.

static var _rate: FontVariation
static var _mass: FontVariation
static var _label: FontVariation
static var _title: FontVariation


static func _t() -> Dictionary:
	return MapLogic.cfg().get("type", {})


static func size_of(key: String) -> int:
	return int(_t().get(key, 0))


static func _make(embolden: float, skew_deg: float) -> FontVariation:
	var f := FontVariation.new()
	f.base_font = ThemeDB.fallback_font
	f.variation_embolden = embolden
	if skew_deg != 0.0:
		# Glyph outlines shear toward +x as y falls toward the top of the line: reads as italic.
		f.variation_transform = Transform2D(Vector2(1.0, 0.0), Vector2(tan(deg_to_rad(skew_deg)), 1.0), Vector2.ZERO)
	return f


static func rate_font() -> FontVariation:
	if _rate == null:
		_rate = _make(float(_t().get("rate_embolden", 0.0)), float(_t().get("skew_deg", 0.0)))
	return _rate


static func mass_font() -> FontVariation:
	if _mass == null:
		_mass = _make(float(_t().get("mass_embolden", 0.0)), 0.0)
	return _mass


static func label_font() -> FontVariation:
	if _label == null:
		_label = _make(float(_t().get("label_embolden", 0.0)), 0.0)
	return _label


static func title_font() -> FontVariation:
	if _title == null:
		_title = _make(float(_t().get("label_embolden", 0.0)), 0.0)
	return _title


static func _style(l: Label, font: Font, size: int, color_key: String) -> void:
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Palette.c(color_key))


## `size` 0 uses the type table's size; any override must still be >= 12.
static func style_rate(l: Label, color_key := "text", size := 0) -> void:
	_style(l, rate_font(), size_of("size_rate") if size == 0 else size, color_key)


static func style_mass(l: Label, color_key := "text", size := 0) -> void:
	_style(l, mass_font(), size_of("size_mass") if size == 0 else size, color_key)


static func style_label(l: Label, color_key := "text_dim", size := 0) -> void:
	_style(l, label_font(), size_of("size_label") if size == 0 else size, color_key)


static func style_title(l: Label, color_key := "text") -> void:
	_style(l, title_font(), size_of("size_title"), color_key)
