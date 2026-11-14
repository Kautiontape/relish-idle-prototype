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
const TIMES := "seen_at"  # the file's second section: the game time (view_hud().t) each flag was marked at

static var _memory := {}  # path -> {key: game time marked at (-1: unknown)}: this process's flags, written or not

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


## Sets `key`, marked at game time `t` (view_hud().t; -1 unknown): in memory always, in the file
## only when this session may write.
func mark(key: String, t := -1.0) -> void:
	if not _memory.has(_path):
		_memory[_path] = {}
	_memory[_path][key] = t
	if _persist:
		_cfg.set_value(SECTION, key, true)
		_cfg.set_value(TIMES, key, t)
		_cfg.save(_path)


## A new game forgets what the last one saw. TODO(api-request #18): no view carries a game
## identity, but a new game always mounts the map with game time near 0 (cmd_new_game runs only
## from Game._boot). So when `now_t <= new_game_s` every flag is forgotten whose recorded time is
## later than `now_t`, and every flag with no recorded time (-1, written before seen_at existed);
## in the file (when persisting) and in memory. Later than that, nothing is forgotten (a reload of
## a continuing game can be behind its last mark: the autosave lags).
func reconcile(now_t: float, new_game_s: float) -> void:
	if now_t > new_game_s:
		return
	var changed := false
	var mem: Dictionary = _memory.get(_path, {})
	for key in mem.keys():
		if float(mem[key]) < 0.0 or float(mem[key]) > now_t:
			mem.erase(key)
	if _persist and _cfg.has_section(SECTION):
		for key in _cfg.get_section_keys(SECTION):
			var at := float(_cfg.get_value(TIMES, key, -1.0))
			if at < 0.0 or at > now_t:
				_cfg.erase_section_key(SECTION, key)
				_cfg.erase_section_key(TIMES, key)
				changed = true
	if changed:
		_cfg.save(_path)


## Forgets the process's in-memory flags (tests).
static func forget_memory() -> void:
	_memory.clear()
