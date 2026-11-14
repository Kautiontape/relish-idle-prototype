class_name MapSeen
extends RefCounted
## "Shown once" flags for the map's teaching cues (the valve pointer, the first tithe's
## explanation), kept in a small ConfigFile outside the save: GameState is not ours. The path and
## whether it may be touched are passed in (a harness session, Game.autosave_enabled false, reads
## it as empty and never writes it, so screenshots always show the opening). Flags set in a
## session that cannot write are kept in memory for the process, so a cue that was dismissed stays
## gone when the map is remounted.

const PATH := "user://map_seen.cfg"
const SECTION := "seen"
const VALVE := "valve"
const TITHE := "tithe_explain"

static var _memory := {}  # path -> {key: true}: this process's flags, written or not

var _path := PATH
var _persist := true
var _cfg := ConfigFile.new()


func _init(path := PATH, persist := true) -> void:
	_path = path
	_persist = persist
	if persist and FileAccess.file_exists(path):
		_cfg.load(path)


func has(key: String) -> bool:
	if _memory.get(_path, {}).has(key):
		return true
	return _persist and bool(_cfg.get_value(SECTION, key, false))


## Sets `key`: in memory always, in the file only when this session may write.
func mark(key: String) -> void:
	if not _memory.has(_path):
		_memory[_path] = {}
	_memory[_path][key] = true
	if _persist:
		_cfg.set_value(SECTION, key, true)
		_cfg.save(_path)


## Forgets the process's in-memory flags (tests).
static func forget_memory() -> void:
	_memory.clear()
