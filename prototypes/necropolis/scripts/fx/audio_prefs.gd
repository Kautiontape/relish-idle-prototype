class_name AudioPrefs
extends RefCounted
## The player's sound preference (mute, master volume), kept on the Master audio bus and saved to
## user://settings.cfg, section `audio`, keys `muted` (bool) and `master_db` (float). It is a player
## preference, not game state. Defaults come from configs/synth.json.
##
## Every scene plays on the Master bus, so `apply()` is all a scene needs. In a harness session
## (/root/Game `autosave_enabled` is false: any dev arg such as --fixture) nothing is written:
## worktrees share user://, and a screenshot must not change the player's settings. The change
## still applies to the bus in memory. Reaches Game by node path, so headless tests can load this.

const SECTION := "audio"
const BUS := "Master"
const DEFAULT_PATH := "user://settings.cfg"

static var settings_path := DEFAULT_PATH  # tests point this at a temp file
static var game_node: Node = null  # tests stand a fake Game in here; null looks /root/Game up
static var _prefs := {}  # {"muted", "master_db"} once loaded; empty before


## Forgets the loaded values (the next read reloads from `settings_path`).
static func reset() -> void:
	_prefs = {}


static func muted() -> bool:
	return bool(_values()["muted"])


static func master_db() -> float:
	return float(_values()["master_db"])


## Loads the saved preference (or the defaults) and puts it on the Master bus.
static func apply() -> void:
	reset()
	_apply_bus()


static func toggle_mute() -> void:
	set_muted(not muted())


static func set_muted(on: bool) -> void:
	_values()["muted"] = on
	_apply_bus()
	_save()


static func set_master_db(db: float) -> void:
	_values()["master_db"] = SynthLogic.clamp_master_db(db)
	_apply_bus()
	_save()


## Whether this session may write the settings file: false in a harness session.
static func can_save() -> bool:
	var game: Node = game_node
	if game == null:
		var loop := Engine.get_main_loop() as SceneTree
		game = loop.root.get_node_or_null("Game") if loop != null else null
	return game == null or bool(game.get("autosave_enabled"))


static func _values() -> Dictionary:
	if _prefs.is_empty():
		var saved := {}
		var cf := ConfigFile.new()
		if cf.load(settings_path) == OK and cf.has_section(SECTION):
			for key in cf.get_section_keys(SECTION):
				saved[key] = cf.get_value(SECTION, key)
		_prefs = SynthLogic.merge_prefs(saved)
	return _prefs


static func _apply_bus() -> void:
	var bus := AudioServer.get_bus_index(BUS)
	if bus < 0:
		return
	var p := _values()
	AudioServer.set_bus_mute(bus, bool(p["muted"]))
	AudioServer.set_bus_volume_db(bus, float(p["master_db"]))


static func _save() -> void:
	if not can_save():
		return
	var cf := ConfigFile.new()
	cf.load(settings_path)  # keep other sections; a missing or corrupt file starts empty
	cf.set_value(SECTION, "muted", muted())
	cf.set_value(SECTION, "master_db", master_db())
	cf.save(settings_path)
