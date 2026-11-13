class_name GameState
extends RefCounted
## GameState will hold all game state and the API at milestone E1. For now it
## holds only the shared config loader.
## Files in scripts/sim/ never reference the Game, ConfigDb or Engine
## autoloads (a lint test enforces this).


## Recursively loads every *.json under `dir` into a Dictionary keyed by the
## filename without extension. Directories starting with "." are skipped.
## Files are walked in sorted order so the result is deterministic. On a
## basename collision the first file wins and an error names both paths.
## A file that fails to parse is reported and skipped. A missing dir is {}.
static func load_configs(dir: String) -> Dictionary:
	var out := {}
	var paths := {}
	_load_into(dir, out, paths)
	return out


static func _load_into(dir: String, out: Dictionary, paths: Dictionary) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	var files := Array(d.get_files())
	files.sort()
	for f: String in files:
		if not f.ends_with(".json"):
			continue
		var p := dir.path_join(f)
		var key := f.trim_suffix(".json")
		if out.has(key):
			push_error("GameState.load_configs: duplicate config '%s': keeping %s, ignoring %s" % [key, paths[key], p])
			continue
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(p))
		if parsed == null:
			push_error("GameState.load_configs: failed to parse %s" % p)
			continue
		out[key] = parsed
		paths[key] = p
	var subs := Array(d.get_directories())
	subs.sort()
	for s: String in subs:
		if not s.begins_with("."):
			_load_into(dir.path_join(s), out, paths)
