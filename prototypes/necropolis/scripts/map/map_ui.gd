class_name MapUi
extends RefCounted
## Shared look of the map's control panels (valve, Relish chip, card buttons): a darkening plate
## and an outlined button, every colour from the Palette with amounts in configs/map_view.json.


## The plate behind a control panel: ground lightened a touch, a contour border.
static func plate_box(alpha: float, margin: int) -> StyleBoxFlat:
	var cfg := MapLogic.cfg()
	var box := StyleBoxFlat.new()
	box.bg_color = Palette.c("ground").lightened(float(cfg["panel_bg_lighten"]))
	box.bg_color.a = alpha
	box.border_color = Palette.c("contour", float(cfg["panel_border_alpha"]))
	box.set_border_width_all(1)
	box.set_content_margin_all(margin)
	return box


## An outlined button at least `button_min_h_px` tall: label font, dim text when disabled.
static func style_button(b: Button, size := 0) -> void:
	var cfg := MapLogic.cfg()
	var fsize := int(cfg["font_button"]) if size == 0 else size
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size.y = maxf(b.custom_minimum_size.y, float(cfg["button_min_h_px"]))
	b.add_theme_font_override("font", MapType.label_font())
	b.add_theme_font_size_override("font_size", fsize)
	b.add_theme_color_override("font_color", Palette.c("text"))
	b.add_theme_color_override("font_hover_color", Palette.c("select"))
	b.add_theme_color_override("font_pressed_color", Palette.c("select"))
	b.add_theme_color_override("font_disabled_color", Palette.c("text_dim"))
	var c: Dictionary = cfg["controls"]
	var step := float(cfg["panel_bg_lighten"])
	var base := Palette.c("ground").lightened(step * float(c["ui_button_lighten_mult"]))
	for state in ["normal", "hover", "pressed", "disabled"]:
		var box := StyleBoxFlat.new()
		box.bg_color = base.lightened(step * float(c["ui_hover_lighten_mult"]) if state == "hover" else 0.0)
		box.border_color = Palette.c("contour" if state != "hover" else "select", float(c["ui_button_border_alpha"]) if state != "disabled" else float(cfg["panel_border_alpha"]))
		box.set_border_width_all(1)
		box.set_content_margin_all(int(c["ui_button_margin_px"]))
		b.add_theme_stylebox_override(state, box)
