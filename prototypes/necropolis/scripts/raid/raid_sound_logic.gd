class_name RaidSoundLogic
extends RefCounted
## Pure helpers for the RaidSound adapter: the per-kind throttle, the known-kind gate and the
## chime params. No autoloads, no Engine (the lint enforces it); times are passed in.

## Minimum gap between two plays of the same kind (absorbs can arrive many per second).
const MIN_GAP_MS := 50


## True when a play at `now_ms` is too soon after `last_ms` (-1 or less = never played).
static func throttled(last_ms: int, now_ms: int, min_gap_ms := MIN_GAP_MS) -> bool:
	return last_ms >= 0 and now_ms - last_ms < min_gap_ms


## True when `kind` may be sent to the Synth: `known` is the Synth's kind list (empty = unknown).
static func playable(kind: String, known: Array) -> bool:
	return kind != "" and known.has(kind)


## True when the Synth's `play` looks like play(kind, params): present, and 1 or 2 arguments.
static func synth_api_ok(has_play: bool, arg_count: int) -> bool:
	return has_play and arg_count >= 1 and arg_count <= 2


## Whether a Synth may render now: it exists and is in the tree (its _ready, which loads its
## config, has run only then).
static func can_warm(has_synth: bool, in_tree: bool) -> bool:
	return has_synth and in_tree


## The chime's params: score clamped to 0..100.
static func chime_params(score: int) -> Dictionary:
	return {"score": clampi(score, 0, 100)}


## The `--raid-sound-log` line.
static func log_line(kind: String, params: Dictionary) -> String:
	return "RAID_SOUND %s %s" % [kind, JSON.stringify(params)]
