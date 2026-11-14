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


## The plan to warm: one {"kind", "params"} per distinct render of `kinds`, in order, deduped. A chime
## is every score bucket (kinds.chime.score_step, default 5, over 0..100); a streak is every step
## bucket (kinds.streak.step_max 20 and step_bucket 1 by default); any other kind renders once with
## no params. The buckets mirror SynthLogic.score_bucket / step_bucket, so each entry is a distinct
## cache key of the Synth. `synth_cfg` is the Synth's config (configs/synth.json; empty = defaults).
static func warm_plan(kinds: Array, synth_cfg: Dictionary) -> Array:
	var kc: Dictionary = synth_cfg.get("kinds", {})
	var out := []
	var seen := {}
	for kv in kinds:
		var kind := str(kv)
		var params := []
		if kind == "chime":
			var s := maxf(float(kc.get("chime", {}).get("score_step", 5.0)), 1.0)
			for score in 101:
				params.append({"score": roundi(roundf(float(score) / s) * s)})
		elif kind == "streak":
			var k: Dictionary = kc.get("streak", {})
			var top := float(k.get("step_max", 20))
			var b := maxf(float(k.get("step_bucket", 1)), 1.0)
			for step in int(top) + 1:
				params.append({"step": roundi(roundf(clampf(float(step), 0.0, top) / b) * b)})
		else:
			params.append({})
		for p in params:
			var key := "%s:%s" % [kind, JSON.stringify(p)]
			if not seen.has(key):
				seen[key] = true
				out.append({"kind": kind, "params": p})
	return out


## Splits a warm plan into the renders to do at once (plain kinds, no params) and those to trickle one
## per frame (chime buckets, streak steps): {"plain": [...], "param": [...]}, each in plan order.
static func split_plan(plan: Array) -> Dictionary:
	var plain := []
	var param := []
	for it in plan:
		if (it["params"] as Dictionary).is_empty():
			plain.append(it)
		else:
			param.append(it)
	return {"plain": plain, "param": param}
