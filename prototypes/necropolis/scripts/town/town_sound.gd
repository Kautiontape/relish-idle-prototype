class_name TownSound
extends RefCounted
## The town's sound math, pure (no autoloads, no engine singletons), so tests run it. TownSynth is the
## thin player that pushes these samples into an AudioStreamGenerator. All numbers come from
## configs/town.json `sound`; nothing here is tuned.
##
## A voice spec: {wave: sine|saw|square, f0, f1 (Hz, an exponential sweep), dur (s), attack, release (s),
## gain (0..1), grit (0..1, noise mixed into the tone), delay (s, optional)}.
## A voice is the running state of one spec: {spec, t (s into the voice, negative while its delay runs),
## seed, done}. render() advances it.


## 0 outside [0, dur]; rises over `attack`, holds at 1, falls over the last `release` seconds.
static func env(t: float, dur: float, attack: float, release: float) -> float:
	if t < 0.0 or t > dur or dur <= 0.0:
		return 0.0
	var e := 1.0
	if attack > 0.0 and t < attack:
		e = t / attack
	if release > 0.0 and t > dur - release:
		e = minf(e, (dur - t) / release)
	return clampf(e, 0.0, 1.0)


## The frequency a fraction `u` (0..1) of the way through an exponential sweep f0 -> f1.
static func sweep_freq(u: float, f0: float, f1: float) -> float:
	if f0 <= 0.0 or f1 <= 0.0:
		return maxf(f0, f1)
	return f0 * pow(f1 / f0, clampf(u, 0.0, 1.0))


## The phase in radians after `t` seconds of a `dur`-second exponential sweep: the integral of the
## frequency (sin(2 pi f(t) t) would run the sweep twice as fast).
static func sweep_phase(t: float, dur: float, f0: float, f1: float) -> float:
	if f0 <= 0.0 or f1 <= 0.0 or dur <= 0.0:
		return TAU * maxf(f0, f1) * t
	var ratio := f1 / f0
	if absf(ratio - 1.0) < 1e-6:
		return TAU * f0 * t
	var u := clampf(t / dur, 0.0, 1.0)
	var past := maxf(t - dur, 0.0)  # past the end it holds f1
	return TAU * f0 * dur / log(ratio) * (pow(ratio, u) - 1.0) + TAU * f1 * past


## A hash noise in [-1, 1] for sample index `i` and `seed` (deterministic, no state).
static func noise(i: int, seed: int) -> float:
	var x := (i * 374761393 + seed * 668265263) & 0x7fffffff
	x = ((x ^ (x >> 13)) * 1274126177) & 0x7fffffff
	x = (x ^ (x >> 16)) & 0x7fffffff
	return float(x) / 1073741823.5 - 1.0


## One cycle of a wave at `phase` radians, -1..1.
static func wave(kind: String, phase: float) -> float:
	match kind:
		"saw":
			return 2.0 * fposmod(phase / TAU, 1.0) - 1.0
		"square":
			return 1.0 if fposmod(phase / TAU, 1.0) < 0.5 else -1.0
	return sin(phase)


## A fresh voice for `spec`. `seed` picks its noise.
static func voice(spec: Dictionary, seed := 1) -> Dictionary:
	return {"spec": spec, "t": -float(spec.get("delay", 0.0)), "seed": seed, "i": 0, "done": false}


## Renders `n` samples of voice `v` at `rate` Hz and advances it. Once it has ended it answers silence
## and `done` is true.
static func render(v: Dictionary, n: int, rate: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(n)
	var spec: Dictionary = v["spec"]
	var dur := float(spec.get("dur", 0.0))
	var f0 := float(spec.get("f0", 0.0))
	var f1 := float(spec.get("f1", f0))
	var gain := float(spec.get("gain", 0.0))
	var grit := clampf(float(spec.get("grit", 0.0)), 0.0, 1.0)
	var attack := float(spec.get("attack", 0.0))
	var release := float(spec.get("release", 0.0))
	var kind := String(spec.get("wave", "sine"))
	var seed := int(v["seed"])
	var tt := float(v["t"])
	var i0 := int(v["i"])
	var dt := 1.0 / maxf(rate, 1.0)
	for k in n:
		if tt >= 0.0 and tt <= dur:
			var tone := wave(kind, sweep_phase(tt, dur, f0, f1))
			var s := (1.0 - grit) * tone + grit * noise(i0 + k, seed)
			out[k] = s * env(tt, dur, attack, release) * gain
		tt += dt
	v["t"] = tt
	v["i"] = i0 + n
	if tt > dur:
		v["done"] = true
	return out


## The sum of `voices` over `n` samples, limited to +-1, dropping the ones that finished. `stats`
## (optional) gains, per voice `name` (a key some callers put on a voice), the count of non-zero
## samples it produced: {name: {frames, nonzero}}.
static func mix(voices: Array, n: int, rate: float, stats := {}) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(n)
	for v in voices:
		var s := render(v, n, rate)
		var nz := 0
		for k in n:
			out[k] += s[k]
			if s[k] != 0.0:
				nz += 1
		var nm := String(v.get("name", ""))
		if nm != "":
			var e: Dictionary = stats.get(nm, {"frames": 0, "nonzero": 0})
			e["frames"] = int(e["frames"]) + n
			e["nonzero"] = int(e["nonzero"]) + nz
			stats[nm] = e
	for k in n:
		out[k] = clampf(out[k], -1.0, 1.0)
	var i := voices.size() - 1
	while i >= 0:
		if bool((voices[i] as Dictionary)["done"]):
			voices.remove_at(i)
		i -= 1
	return out


## Adds `v` to `pool`; a full pool gives up its oldest voice.
static func add_voice(pool: Array, v: Dictionary, max_voices: int) -> void:
	pool.append(v)
	while pool.size() > maxi(max_voices, 1):
		pool.remove_at(0)


## The trade-blip limiter: a blip sounds only if `gap` seconds have passed since the last that did
## (last < 0 = none yet). Blips over the rate are dropped, not queued.
static func allow(now_s: float, last_s: float, gap: float) -> bool:
	return last_s < 0.0 or now_s - last_s >= gap


## The Pulse beat number at `now_ms`: it steps once per tempo, also while reduced motion holds the phase.
static func beat_index(now_ms: float, tempo_ms: float) -> int:
	return int(floor(now_ms / tempo_ms)) if tempo_ms > 0.0 else 0
