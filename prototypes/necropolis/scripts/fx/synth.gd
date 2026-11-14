class_name Synth
extends Node
## The shared synthesised sound helper (VISUAL-LANGUAGE 2f). A scene adds one as a child and
## calls `play(kind, params)`; nothing touches project.godot.
##
##   var synth := Synth.new()
##   add_child(synth)
##   synth.warm(["pulse", "whoosh"])     # optional: render these now, not on their first play
##   synth.play("chime", {"score": 87})  # kinds: SynthLogic.KINDS
##
## Why pre-rendered, not an AudioStreamGenerator: every sound is short and fixed, so each one is
## rendered once (SynthLogic.render, PCM16 into an AudioStreamWAV) and kept in a static cache
## that outlives scene swaps. A play then costs a player assignment, with no per-frame GDScript
## buffer filling and nothing to underrun when a frame is slow. A small pool of AudioStreamPlayers
## (max_voices) lets sounds overlap; when all are busy the longest-playing voice is reused.
##
## Volume: each player's volume_db is master_db + the kind's gain_db (SynthLogic.volume_db).
## Mute: the mute_key (M) toggles it in any scene, and it holds for the rest of the session (a
## static, so the next scene's Synth starts muted too); configs/synth.json `muted` is the start.
## Debug sessions print "SYNTH play <kind>" per sound played (log_once kinds only on their first).
## Headless and the dummy audio driver are fine: players play into nothing. Reaches ConfigDb and
## Game by path, so a headless test can load this script.

static var _cache := {}  # SynthLogic.cache_key -> AudioStreamWAV, shared by every scene's Synth
static var _session_muted = null  # null until the key toggles it: then it holds across scenes

var _cfg := {}
var _players: Array[AudioStreamPlayer] = []
var _started_ms: Array[int] = []  # when each player last started (the oldest is reused)
var _mute_key: Key = KEY_NONE
var _debug := false
var _logged := {}


func _ready() -> void:
	var db := get_node_or_null("/root/ConfigDb")
	var live = (db.get("data") as Dictionary).get("synth") if db != null else null
	if live is Dictionary and not (live as Dictionary).is_empty():
		SynthLogic.configure(live)
	_cfg = SynthLogic.cfg()
	var game := get_node_or_null("/root/Game")
	_debug = game != null and bool(game.get("state").get("debug_enabled"))
	_mute_key = OS.find_keycode_from_string(str(_cfg.get("mute_key", "")))
	for i in maxi(int(_cfg.get("max_voices", 1)), 1):
		var p := AudioStreamPlayer.new()
		p.name = "Voice%d" % i
		add_child(p)
		_players.append(p)
		_started_ms.append(0)


## Whether sound is off: the session's toggle once pressed, else synth.json `muted`.
func is_muted() -> bool:
	return bool(_session_muted) if _session_muted != null else bool(_cfg.get("muted", false))


## Mutes or unmutes for the rest of the session (every scene's Synth); muting stops what plays.
func set_muted(on: bool) -> void:
	_session_muted = on
	if on:
		for p in _players:
			p.stop()
	print("Synth: sound ", "OFF" if on else "ON")


## Renders `kinds` into the cache now (a scene's first frames are heavy anyway), so their first
## play costs nothing. Already cached kinds are skipped.
func warm(kinds: Array) -> void:
	for k in kinds:
		_stream(str(k), {})


## Plays `kind` (SynthLogic.KINDS; a chime takes params.score 0..100). Muted: nothing plays.
func play(kind: String, params := {}) -> void:
	if is_muted() or _players.is_empty():
		return
	if not SynthLogic.KINDS.has(kind):
		push_error("Synth: unknown kind '%s'. Known: %s" % [kind, ", ".join(SynthLogic.KINDS)])
		return
	var p := _voice()
	p.stream = _stream(kind, params)
	p.volume_db = SynthLogic.volume_db(float(_cfg["master_db"]), float(SynthLogic.kind_cfg(kind, _cfg)["gain_db"]), false, _cfg)
	p.play()
	_started_ms[_players.find(p)] = Time.get_ticks_msec()
	if _debug and (not Array(_cfg.get("log_once", [])).has(kind) or not _logged.has(kind)):
		_logged[kind] = true
		print("SYNTH play ", kind)


func _stream(kind: String, params: Dictionary) -> AudioStreamWAV:
	var key := SynthLogic.cache_key(kind, params, _cfg)
	if not _cache.has(key):
		var sr := int(_cfg["sample_rate"])
		var wav := AudioStreamWAV.new()
		wav.format = AudioStreamWAV.FORMAT_16_BITS
		wav.mix_rate = sr
		wav.stereo = false
		wav.data = SynthLogic.to_pcm16(SynthLogic.render(kind, params, sr, _cfg))
		_cache[key] = wav
	return _cache[key]


## A free player, else the one that started longest ago.
func _voice() -> AudioStreamPlayer:
	var best := 0
	for i in _players.size():
		if not _players[i].playing:
			return _players[i]
		if _started_ms[i] < _started_ms[best]:
			best = i
	return _players[best]


func _unhandled_key_input(e: InputEvent) -> void:
	var k := e as InputEventKey
	if k != null and k.pressed and not k.echo and k.keycode == _mute_key:
		set_muted(not is_muted())
