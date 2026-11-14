class_name TownSound
extends RefCounted
## The town's sound helpers, pure (no autoloads, no engine singletons), so tests run it. The sounds
## themselves are the shared Synth's (scripts/fx/synth.gd); the town only decides which kind plays on
## which event (configs/town.json `sound.kinds`), how often trade blips may sound, and when a beat falls.


## The Synth kind for a town event ("" when the event has none): `sound` is town.json's sound block.
static func kind_for(sound: Dictionary, event: String) -> String:
	return String((sound.get("kinds", {}) as Dictionary).get(event, ""))


## The trade-blip limiter: a blip sounds only if `gap` seconds have passed since the last that did
## (last < 0 = none yet). Blips over the rate are dropped, not queued.
static func allow(now_s: float, last_s: float, gap: float) -> bool:
	return last_s < 0.0 or now_s - last_s >= gap


## The shell's per-frame beat step: {i, fire}. A muted synth computes nothing (i = -1, so the unmute frame
## records the beat rather than firing a stale one); otherwise `fire` is true when the beat index moved
## on from `last_i` (a first look, last_i < 0, only records).
static func beat_step(muted: bool, last_i: int, now_ms: float, tempo_ms: float) -> Dictionary:
	if muted:
		return {"i": -1, "fire": false}
	var bi := beat_index(now_ms, tempo_ms)
	return {"i": bi, "fire": last_i >= 0 and bi != last_i}


## The Pulse beat number at `now_ms`: it steps once per tempo, also while reduced motion holds the phase.
static func beat_index(now_ms: float, tempo_ms: float) -> int:
	return int(floor(now_ms / tempo_ms)) if tempo_ms > 0.0 else 0
