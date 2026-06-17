extends Node
## Autoload "ConfigDb". Loads every JSON under res://configs at startup.
## All tunables live here — nothing numeric is hardcoded. The debug panel edits
## values in place; reset_tunables() restores file values.

signal value_changed(file: String, key: String, value: Variant)

const FILES := ["stats", "workers", "yard"]

var data: Dictionary = {}
var _defaults: Dictionary = {}

func _ready() -> void:
	load_all()

func load_all() -> void:
	data.clear()
	for f in FILES:
		data[f] = _read_json("res://configs/%s.json" % f)
	_defaults = data.duplicate(true)

func _read_json(path: String) -> Variant:
	var fa := FileAccess.open(path, FileAccess.READ)
	if fa == null:
		push_error("Missing config: " + path)
		return {}
	var parsed: Variant = JSON.parse_string(fa.get_as_text())
	if parsed == null:
		push_error("Bad JSON: " + path)
		return {}
	return parsed

## Hot accessor: ConfigDb.v("stats", "harvest_time_s")
func v(file: String, key: String) -> Variant:
	return data[file][key]

func set_v(file: String, key: String, value: Variant) -> void:
	data[file][key] = value
	value_changed.emit(file, key, value)

func reset_tunables() -> void:
	data = _defaults.duplicate(true)
	value_changed.emit("*", "*", null)
