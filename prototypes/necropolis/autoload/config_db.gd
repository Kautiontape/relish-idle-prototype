extends Node
## Loads every configs/**/*.json into `data` keyed by filename (no extension).
## Same pattern as raid-and-raise's ConfigDb: zero hardcoded numbers in scripts.

var data := {}


func _ready() -> void:
	reload()


func reload() -> void:
	data = GameState.load_configs("res://configs")


func v(file: String, key: String, def = null):
	if data.has(file) and (data[file] as Dictionary).has(key):
		return data[file][key]
	return def


func set_v(file: String, key: String, value) -> void:
	if not data.has(file):
		data[file] = {}
	data[file][key] = value
