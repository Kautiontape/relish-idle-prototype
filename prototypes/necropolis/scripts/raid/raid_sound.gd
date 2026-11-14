class_name RaidSound
extends RefCounted
## The raid's sound adapter. Scene code calls only `RaidSound.play(kind, params)` and
## `RaidSound.warm(kinds)`; the shared synthesiser (scripts/fx/synth.gd, map's) does the work and
## owns mute, volume and the Master bus. Synth is loaded by path so this parses without it: when it
## is absent, or the kind is not one it knows, every call is a no-op. The raid scene calls
## `attach` at build; no autoload. `--raid-sound-log` prints "RAID_SOUND <kind> <params>" per call.

const SYNTH_PATH := "res://scripts/fx/synth.gd"
const SYNTH_LOGIC_PATH := "res://scripts/fx/synth_logic.gd"

const WARM_KINDS := ["absorb", "raise", "chime", "shatter", "tell", "slam", "muffle", "intercept"]

static var _synth: Node = null
static var _known: Array = []
static var _last_ms := {}
static var _log := false


## Creates the Synth as a child of `parent` (the raid scene) when it exists; safe either way.
static func attach(parent: Node) -> void:
	_synth = null
	_known = []
	_last_ms = {}
	_log = OS.get_cmdline_user_args().has("--raid-sound-log")
	if not ResourceLoader.exists(SYNTH_PATH):
		return
	var script := load(SYNTH_PATH) as Script
	if script == null or not script.can_instantiate():
		return
	var node = script.new()
	if not RaidSoundLogic.synth_api_ok(node.has_method("play"), node.get_method_argument_count("play")):
		push_warning("RaidSound: Synth.play has an unexpected signature; sound is off")
		node.free()
		return
	_synth = node
	parent.add_child(_synth)
	if ResourceLoader.exists(SYNTH_LOGIC_PATH):
		var logic := load(SYNTH_LOGIC_PATH) as Script
		if logic != null:
			_known = Array(logic.get_script_constant_map().get("KINDS", []))
	warm(WARM_KINDS)


static func warm(kinds: Array) -> void:
	if _synth != null and is_instance_valid(_synth):
		_synth.call("warm", kinds.filter(func(k): return RaidSoundLogic.playable(str(k), _known)))


static func play(kind: String, params := {}) -> void:
	if _log:
		print(RaidSoundLogic.log_line(kind, params))
	if _synth == null or not is_instance_valid(_synth) or not RaidSoundLogic.playable(kind, _known):
		return
	var now := Time.get_ticks_msec()
	if RaidSoundLogic.throttled(int(_last_ms.get(kind, -1)), now):
		return
	_last_ms[kind] = now
	_synth.call("play", kind, params)
