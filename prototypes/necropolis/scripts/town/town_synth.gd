class_name TownSynth
extends Node
## The town's sound: one AudioStreamPlayer on an AudioStreamGenerator, a small pool of voices, and
## the few sounds the town makes (VISUAL-LANGUAGE §2f). The sample maths is TownSound's (pure, tested);
## this node only owns the player and pushes the buffer.
## STANDIN: swap for scripts/fx/synth.gd when the map unit lands it (it was not on the branch yet).
##
## Mute (Shawn's rule): configs/town.json `sound.mute` defaults to true. While muted the synth does no
## work at all: no player exists (it is made on the first unmute), every voice call returns at once,
## _process is off. M toggles it in the scene (Covington). `sound.volume_db` is the master volume.
## No audio device (headless, a refused player): the voices are simply never started, never an error.
##
## Voices: tier_up() (a rising chord as the walls draw), raise_grow() (a gritty rising sweep while the
## hold ring closes; raise_grow_stop() on release), raise_done() (a low thump as the collapse lands),
## trade_blip() (a short soft high blip, at most one per sound.trade_min_gap_s), beat() (a very quiet low
## pulse on each Pulse beat, sound.beat_gain).

var _cfg: Dictionary = {}
var _muted := true
var _player: AudioStreamPlayer
var _playback: AudioStreamGeneratorPlayback
var _voices: Array = []
var _last_trade := -1.0
var _failed := false
var _rate := 22050.0
## Per voice name, what has been pushed so far: {name: {frames, nonzero}} (the headless self-test reads it).
var stats := {}


func _ready() -> void:
	set_process(false)


func setup(cfg: Dictionary) -> void:
	_cfg = cfg
	_rate = float(cfg.get("mix_rate", 22050))
	set_mute(bool(cfg.get("mute", true)))


func is_muted() -> bool:
	return _muted


## True while a player exists and can sound (not muted, a device that answered).
func is_live() -> bool:
	return not _muted and _playback != null


## Muting stops everything and frees the player; unmuting makes it again.
func set_mute(on: bool) -> void:
	_muted = on
	if on:
		_voices.clear()
		set_process(false)
		if _player != null:
			_player.stop()
			_player.queue_free()
			_player = null
			_playback = null
	else:
		_ensure()


func toggle_mute() -> bool:
	set_mute(not _muted)
	return _muted


func set_volume_db(db: float) -> void:
	_cfg["volume_db"] = db
	if _player != null:
		_player.volume_db = db


func tier_up() -> void:
	for sp in _specs("tier_up"):
		_start("tier_up", sp)


func raise_grow() -> void:
	for sp in _specs("raise_grow"):
		_start("raise_grow", sp)


## The hold was let go: the sweep dies away over its own release instead of cutting off.
func raise_grow_stop() -> void:
	for v in _voices:
		if v.get("name", "") == "raise_grow":
			var sp: Dictionary = v["spec"]
			v["t"] = maxf(float(v["t"]), float(sp.get("dur", 0.0)) - float(sp.get("release", 0.0)))


func raise_done() -> void:
	for sp in _specs("raise_done"):
		_start("raise_done", sp)


## A trade blip, if the limiter allows one (sound.trade_min_gap_s since the last that sounded).
func trade_blip() -> void:
	if _muted:
		return
	var now := float(Time.get_ticks_msec()) * 0.001
	if not TownSound.allow(now, _last_trade, float(_cfg.get("trade_min_gap_s", 0.0))):
		return
	_last_trade = now
	for sp in _specs("trade_blip"):
		_start("trade_blip", sp)


## One Pulse beat: a very quiet low pulse (sound.beat_gain; 0 is off).
func beat() -> void:
	var g := float(_cfg.get("beat_gain", 0.0))
	if _muted or g <= 0.0:
		return
	for sp in _specs("beat"):
		var q: Dictionary = (sp as Dictionary).duplicate()
		q["gain"] = float(q.get("gain", 1.0)) * g
		_start("beat", q)


func _specs(key: String) -> Array:
	var v: Variant = _cfg.get(key, [])
	if v is Dictionary:
		return [v]
	return v if v is Array else []


func _start(name: String, spec: Dictionary) -> void:
	if _muted or not _ensure():
		return
	var v := TownSound.voice(spec, int(Time.get_ticks_usec() & 0xffff))
	v["name"] = name
	TownSound.add_voice(_voices, v, int(_cfg.get("voices", 8)))
	set_process(true)


## The player, made on first use. false if there is no audio device to play on.
func _ensure() -> bool:
	if _muted or _failed:
		return false
	if _playback != null:
		return true
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = _rate
	gen.buffer_length = float(_cfg.get("buffer_s", 0.25))
	_player = AudioStreamPlayer.new()
	_player.stream = gen
	_player.volume_db = float(_cfg.get("volume_db", 0.0))
	add_child(_player)
	_player.play()
	_playback = _player.get_stream_playback() as AudioStreamGeneratorPlayback
	if _playback == null:
		_failed = true  # no device answered: stay silent, never error
		_player.queue_free()
		_player = null
		return false
	return true


func _process(_delta: float) -> void:
	if _playback == null or _muted:
		set_process(false)
		return
	if _voices.is_empty():
		set_process(false)
		return
	var n := _playback.get_frames_available()
	if n <= 0:
		return
	var mono := TownSound.mix(_voices, n, _rate, stats)
	var frames := PackedVector2Array()
	frames.resize(n)
	for i in n:
		frames[i] = Vector2(mono[i], mono[i])
	_playback.push_buffer(frames)


## Debug self-test (headless or `--audio-driver Dummy` only): unmutes, starts every voice at once, lets
## the mixer run for `secs`, then mutes again. Returns {voice: {frames, nonzero}}, or {"refused": why}
## if the audio driver is anything but Dummy. Nothing audible can come out of it.
func selftest(secs: float) -> Dictionary:
	var driver := AudioServer.get_driver_name()
	if driver != "Dummy":
		return {"refused": "audio driver is %s, not Dummy" % driver}
	stats = {}
	_last_trade = -1.0
	set_mute(false)
	if not is_live():
		set_mute(true)
		return {"refused": "no audio playback on the Dummy driver"}
	tier_up()
	raise_grow()
	raise_done()
	trade_blip()
	beat()
	await get_tree().create_timer(secs).timeout
	var out := stats.duplicate(true)
	set_mute(true)
	return out
