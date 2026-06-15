extends Node
## Autoload "ConfigDb". Loads every JSON under res://configs at startup.
## All tunables live here — nothing numeric is hardcoded. The debug panel edits
## values in place; reset_tunables() restores file values.

signal value_changed(file: String, key: String, value: Variant)

const FILES := ["stats", "rarity", "echoes", "names", "slab", "ossuary", "roles"]
const DIRS := ["husks"]

var data: Dictionary = {}
var _defaults: Dictionary = {}

func _ready() -> void:
	load_all()

func load_all() -> void:
	data.clear()
	for f in FILES:
		data[f] = _read_json("res://configs/%s.json" % f)
	for d in DIRS:
		var dict := {}
		var dir_path := "res://configs/%s" % d
		for fname in DirAccess.get_files_at(dir_path):
			if fname.ends_with(".json"):
				dict[fname.get_basename()] = _read_json(dir_path + "/" + fname)
		data[d] = dict
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

## Hot accessor: ConfigDb.v("ossuary", "drop_per_pull")
func v(file: String, key: String) -> Variant:
	return data[file][key]

func set_v(file: String, key: String, value: Variant) -> void:
	data[file][key] = value
	value_changed.emit(file, key, value)

func reset_tunables() -> void:
	data = _defaults.duplicate(true)
	value_changed.emit("*", "*", null)

func husk(id: String) -> Dictionary:
	return data["husks"][id]

## All forms (husks) as a sorted id list — the build inventory draws from this.
func form_ids() -> Array:
	var ids: Array = data["husks"].keys()
	ids.sort()
	return ids
