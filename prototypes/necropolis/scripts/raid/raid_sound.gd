class_name RaidSound
extends RefCounted
## The raid's sound adapter. Scene code calls only `RaidSound.play(kind, params)` and
## `RaidSound.warm(kinds)`; the shared synthesiser (scripts/fx/synth.gd, map's) does the work and
## owns mute, volume and the Master bus. Synth is loaded by path so this parses without it: when it
## is absent, or the kind is not one it knows, every call is a no-op. The raid scene calls
## `attach` at build; no autoload. `--raid-sound-log` prints "RAID_SOUND <kind> <params>" per call.

const SYNTH_PATH := "res://scripts/fx/synth.gd"
const SYNTH_LOGIC_PATH := "res://scripts/fx/synth_logic.gd"

## Kinds `attach` warms when the scene passes none (the scenes pass their own: raid.json
## `sound.warm`, vei.json `sound.warm`).
const WARM_KINDS := ["absorb", "raise", "chime", "shatter", "tell", "slam", "muffle", "intercept"]

static var _synth: Node = null
static var _known: Array = []
static var _last_ms := {}
static var _log := false
static var _queue: Array = []   # the warm plan still to render: {"kind", "params"}, one per frame


## Creates the Synth as a child of `parent` (the raid scene) when it exists; safe either way. The
## kinds in `warm_kinds` render ahead of use, one per frame (see `tick`), so no first play renders
## on a gameplay frame.
static func attach(parent: Node, warm_kinds: Array = WARM_KINDS) -> void:
	_synth = null
	_known = []
	_queue = []
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
	_begin_warm(warm_kinds)


## Queues the warm plan and starts the per-frame ticker (a child of the Synth, so it dies with it).
## Needs the Synth in the tree (its _ready loads the config) and its `_stream`.
static func _begin_warm(kinds: Array) -> void:
	var live := _synth != null and is_instance_valid(_synth)
	if not RaidSoundLogic.can_warm(live, live and _synth.is_inside_tree()):
		return
	# Stand-in until Synth offers a params-aware warm (the dungeon unit takes over the Synth files in
	# D-d and adds a public one): `warm(kinds)` renders a kind with no params, which leaves every
	# chime bucket and streak step to render on its first play. tests/test_raid_sound.gd fails if
	# `_stream` is renamed.
	if not _synth.has_method("_stream"):
		return
	var cfg := {}
	if ResourceLoader.exists(SYNTH_LOGIC_PATH):
		var logic := load(SYNTH_LOGIC_PATH) as Script
		if logic != null and logic.has_method("cfg"):
			cfg = logic.call("cfg")
	_queue = RaidSoundLogic.warm_plan(kinds.filter(func(k): return RaidSoundLogic.playable(str(k), _known)), cfg)
	if not _queue.is_empty():
		var t := Ticker.new()
		t.name = "WarmTicker"
		_synth.add_child(t)


## Renders the next queued kind (one per call; the Ticker calls it each frame). No sim, no RNG.
static func tick() -> void:
	if _queue.is_empty():
		return
	if _synth == null or not is_instance_valid(_synth) or not _synth.has_method("_stream"):
		_queue = []
		return
	var item: Dictionary = _queue.pop_front()
	_synth.call("_stream", item["kind"], item["params"])


## True while kinds are still queued to warm.
static func warming() -> bool:
	return not _queue.is_empty()


## Stops every voice the Synth has playing (the bots call this before they quit).
static func silence() -> void:
	if _synth == null or not is_instance_valid(_synth):
		return
	for c in _synth.get_children():
		if c is AudioStreamPlayer:
			(c as AudioStreamPlayer).stop()


class Ticker:
	extends Node

	func _process(_d: float) -> void:
		RaidSound.tick()
		if not RaidSound.warming():
			queue_free()


static func warm(kinds: Array) -> void:
	var live := _synth != null and is_instance_valid(_synth)
	if RaidSoundLogic.can_warm(live, live and _synth.is_inside_tree()):
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
