class_name Palette
extends RefCounted
## The canon colours, by name, from configs/palette.json (DESIGN.md + BRIEF §6).
##   Palette.c("undead")        -> Color
##   Palette.c("undead", 0.4)   -> same colour at alpha 0.4
## An unknown key fails loudly: push_error naming the known keys, and a hot
## magenta MISSING colour on screen. Scene scripts never write Color(...) literals.
##
## At runtime the colours come through the ConfigDb autoload. Headless tests run
## before autoloads exist, so they call Palette.configure(json) themselves; if
## ConfigDb is absent the file is read directly.

const MISSING := Color(1.0, 0.0, 1.0)
const CONFIG_FILE := "palette"

static var _colors := {}
static var _loaded := false


## Replace the palette with `raw` (key -> "#RRGGBB"). Non-colour values error.
static func configure(raw: Dictionary) -> void:
	_colors.clear()
	for k in raw:
		var v = raw[k]
		if v is String and Color.html_is_valid(v):
			_colors[k] = Color.html(v)
		else:
			push_error("Palette: '%s' is not a hex colour: %s" % [k, str(v)])
	_loaded = true


## The named colour, optionally at `alpha`. Unknown key -> push_error + MISSING.
static func c(key: String, alpha := 1.0) -> Color:
	_ensure()
	if not _colors.has(key):
		push_error("Palette: unknown colour '%s'. Known: %s" % [key, ", ".join(keys())])
		return MISSING
	return Color(_colors[key], alpha)


## The named colour's hue in degrees (0..360), for Pulse.channels().
static func hue(key: String) -> float:
	return c(key).h * 360.0


static func has(key: String) -> bool:
	_ensure()
	return _colors.has(key)


static func keys() -> Array:
	_ensure()
	return _colors.keys()


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
	if not raw is Dictionary:
		push_error("Palette: configs/%s.json is missing or not a JSON object" % CONFIG_FILE)
		raw = {}
	configure(raw)
