extends Node
## Loads every configs/**/*.json into `data` keyed by filename (no extension).
## Same pattern as raid-and-raise's ConfigDb: zero hardcoded numbers in scripts.

var data := {}


func _ready() -> void:
	reload()


func reload() -> void:
	data.clear()
	_load_dir("res://configs")


func _load_dir(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		var p := path + "/" + f
		if dir.current_is_dir() and not f.begins_with("."):
			_load_dir(p)
		elif f.ends_with(".json"):
			var parsed = JSON.parse_string(FileAccess.get_file_as_string(p))
			if parsed != null:
				data[f.trim_suffix(".json")] = parsed
		f = dir.get_next()


func v(file: String, key: String, def = null):
	if data.has(file) and (data[file] as Dictionary).has(key):
		return data[file][key]
	return def


func set_v(file: String, key: String, value) -> void:
	if not data.has(file):
		data[file] = {}
	data[file][key] = value
