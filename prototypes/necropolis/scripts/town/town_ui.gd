class_name TownUI
extends RefCounted
## Shared Covington UI helpers: styleboxes, labels, buttons, the oblique rate font.
## Every colour is Palette.c(key). Text is at least 12 px; buttons at least 44 px tall.

const MIN_TEXT := 12
const MIN_TARGET := 44.0
const SLANT_DEG := 9.0

static var _boxes := {}  # state -> the shared button_box (built once)
static var _oblique: FontVariation = null
static var _bold: FontVariation = null


## A refused command's line: a `catching_up` refusal is a wait, not an error (C-c), so it reads as its own
## words, "Catching up on your time away: try again in a moment."; any other reason reads `refused`.
static func refusal(reason: String, why: String, refused: String) -> String:
	if reason == "catching_up" and why != "":
		return why.substr(0, 1).to_upper() + why.substr(1) + "."
	return refused


## The glossary's line for each jargon word `text` uses (`vcfg` is town.json's view; its guide.jargon: mint,
## husk, phylactery; case ignored), one per line; "" when it uses none. A label's tooltip, wherever the word shows.
## Once the game is `won` (view_hud.won), a word's guide.jargon_won line where it has one (the mint: no FLOOD then).
## The words matched are always guide.jargon's.
static func jargon_tip(text: String, vcfg: Dictionary, won := false) -> String:
	var g: Dictionary = vcfg.get("guide", {})
	var j: Dictionary = g.get("jargon", {})
	var jw: Dictionary = g.get("jargon_won", {}) if won else {}
	var out := PackedStringArray()
	for w in j:
		if text.findn(String(w)) >= 0:
			out.append(String(jw.get(w, j[w])))
	return "\n".join(out)


## Sets `c`'s tooltip to jargon_tip(`text`, `vcfg`, `won`); a Label (which ignores the mouse by default) takes the
## mouse while it has one.
static func set_jargon_tip(c: Control, text: String, vcfg: Dictionary, won := false) -> void:
	var tip := jargon_tip(text, vcfg, won)
	if c.tooltip_text != tip:
		c.tooltip_text = tip
		c.mouse_filter = Control.MOUSE_FILTER_STOP if tip != "" or not (c is Label) else Control.MOUSE_FILTER_IGNORE


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


## A button state's box, built once and shared (for the states a bind() reapplies every refetch).
static func button_box_cached(state := "normal") -> StyleBoxFlat:
	if not _boxes.has(state):
		_boxes[state] = button_box(state)
	return _boxes[state]


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


## The emboldened font (cached): emphasis that is not colour (the crypt's dominant stat).
static func bold_font() -> FontVariation:
	if _bold == null:
		_bold = FontVariation.new()
		_bold.variation_embolden = 0.9
	return _bold


## A Label that shows a signed rate in the oblique font.
static func rate_label(text := "", size := 14, key := "text") -> Label:
	var l := label(text, size, key)
	l.add_theme_font_override("font", oblique_font())
	return l


## A label for parts [[text, oblique]] (words upright, rates oblique; fill it with set_parts). `wrap`
## grows it to fit wrapped lines; otherwise it is one line, clipped at its width (give it a tooltip).
static func parts_label(size := 14, key := "text", wrap := false) -> RichTextLabel:
	var r := RichTextLabel.new()
	var px := maxi(size, MIN_TEXT)
	r.scroll_active = false
	r.fit_content = wrap
	r.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if wrap else TextServer.AUTOWRAP_OFF
	r.clip_contents = true
	r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.custom_minimum_size = Vector2(40, 0 if wrap else ceilf(px * 1.45))
	r.mouse_filter = Control.MOUSE_FILTER_PASS
	r.add_theme_font_size_override("normal_font_size", px)
	r.add_theme_color_override("default_color", Palette.c(key))
	r.set_meta("px", px)
	return r


## Fills a parts_label (only when the parts changed): oblique parts in the slanted font.
static func set_parts(r: RichTextLabel, parts: Array) -> void:
	if r.get_meta("parts", []) == parts:
		return
	r.set_meta("parts", parts.duplicate(true))
	r.clear()
	var px := int(r.get_meta("px", 14))
	for p in parts:
		if bool(p[1]):
			r.push_font(oblique_font(), px)
			r.add_text(String(p[0]))
			r.pop()
		else:
			r.add_text(String(p[0]))


## Signed per-second text: "+0.42/s", "−0.10/s" (true minus sign). `unit` replaces "s".
static func fmt_rate(x: float, unit := "s") -> String:
	var sign_ch := "−" if x < 0.0 else "+"
	return "%s%.2f/%s" % [sign_ch, absf(x), unit]


## Remove and free every child now (so rebuilds never stack).
static func clear(node: Node) -> void:
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()
