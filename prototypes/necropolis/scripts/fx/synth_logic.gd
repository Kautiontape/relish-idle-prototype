class_name SynthLogic
extends RefCounted
## The synthesised sounds (VISUAL-LANGUAGE 2f), as pure waveform math: no autoloads, so headless
## tests compile it. `render` turns a kind into one mono float buffer, peak-normalised to `peak`,
## with seeded noise so a kind always renders the same. Loudness is never baked in: the player's
## volume_db is master_db + the kind's gain_db (volume_db), so every buffer peaks the same.
## Kinds: pulse (the tempo's low thump), absorb (a falling sweep), raise (a rising gritty sweep),
## chime (pitch from params.score 0..100), whoosh (the valve swing), horn (the tithe warning),
## shatter (a backup cracking), flip (a short bright re-ink). Tuning: configs/synth.json.

const CONFIG_FILE := "res://configs/synth.json"
const KINDS := ["pulse", "absorb", "raise", "chime", "whoosh", "horn", "shatter", "flip"]

static var _cfg := {}


## Replace the config (tests pass the file; Synth passes ConfigDb's copy).
static func configure(d: Dictionary) -> void:
	_cfg = d.duplicate(true)


static func cfg() -> Dictionary:
	if _cfg.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_FILE))
		_cfg = parsed if parsed is Dictionary else {}
		if _cfg.is_empty():
			push_error("SynthLogic: %s is missing or not a JSON object" % CONFIG_FILE)
	return _cfg


static func kind_cfg(kind: String, c := {}) -> Dictionary:
	return (c if not c.is_empty() else cfg()).get("kinds", {}).get(kind, {})


# --- volume and cache ---------------------------------------------------------------

## A player's volume_db for a kind: master_db + its gain_db, clamped to [mute_db, max_db]; muted
## is mute_db (silent).
static func volume_db(master_db: float, gain_db: float, muted: bool, c := {}) -> float:
	if c.is_empty():
		c = cfg()
	var lo := float(c["mute_db"])
	if muted:
		return lo
	return clampf(master_db + gain_db, lo, float(c["max_db"]))


## The score a chime renders at: clamped to 0..100 and rounded to score_step, so the cache holds
## at most 100 / score_step + 1 chimes.
static func score_bucket(score: float, step: float) -> int:
	var s := maxf(step, 1.0)
	return roundi(roundf(clampf(score, 0.0, 100.0) / s) * s)


## One rendered sound per key: the kind, and for a chime its score bucket.
static func cache_key(kind: String, params := {}, c := {}) -> String:
	if kind == "chime":
		return "chime:%d" % score_bucket(float(params.get("score", 0.0)), float(kind_cfg(kind, c)["score_step"]))
	return kind


# --- pitch ----------------------------------------------------------------------------

## An exponential glide from f0 to f1, x (0..1) of the way through, shaped by x^pow.
static func glide(f0: float, f1: float, x: float, p: float) -> float:
	return f0 * pow(f1 / f0, pow(clampf(x, 0.0, 1.0), p))


## The chime's fundamental: f_lo at score 0 to f_hi at 100, exponentially, at its bucket.
static func chime_freq(score: float, k: Dictionary) -> float:
	var s := score_bucket(score, float(k["score_step"]))
	return float(k["f_lo"]) * pow(float(k["f_hi"]) / float(k["f_lo"]), s / 100.0)


## The pitch a kind sounds at, x (0..1) of the way through it, in Hz; 0 for the unpitched whoosh
## and shatter. render() uses the same track.
static func freq_at(kind: String, params: Dictionary, x: float, c := {}) -> float:
	var k := kind_cfg(kind, c)
	match kind:
		"pulse", "absorb", "raise", "horn":
			return glide(float(k["f0"]), float(k["f1"]), x, float(k["glide_pow"]))
		"chime":
			return chime_freq(float(params.get("score", 0.0)), k)
		"flip":
			return float(k["f0"]) if x < float(k["split"]) else float(k["f1"])
	return 0.0


# --- render -----------------------------------------------------------------------------

## `kind` as a mono buffer at `sample_rate` (<= 0: the config's), peak-normalised to `peak`,
## with no NaN. An unknown kind renders empty.
static func render(kind: String, params := {}, sample_rate := 0, c := {}) -> PackedFloat32Array:
	if c.is_empty():
		c = cfg()
	var sr := sample_rate if sample_rate > 0 else int(c["sample_rate"])
	var k := kind_cfg(kind, c)
	if k.is_empty():
		return PackedFloat32Array()
	var n := maxi(int(float(k["len_s"]) * sr), 1)
	var buf := PackedFloat32Array()
	buf.resize(n)
	match kind:
		"pulse", "absorb", "raise":
			_sweep(buf, kind, k, sr, c)
		"chime":
			_chime(buf, params, k, sr)
		"whoosh":
			_whoosh(buf, k, sr)
		"horn":
			_horn(buf, k, sr, c)
		"shatter":
			_shatter(buf, k, sr)
		"flip":
			_flip(buf, k, sr)
		_:
			return PackedFloat32Array()
	return _normalise(buf, float(c["peak"]))


## Linear attack over attack_s, then (1 - x)^decay_pow to silence at the end.
static func _env(i: int, n: int, attack_n: int, decay_pow: float) -> float:
	if i < attack_n:
		return float(i) / attack_n
	var x := float(i - attack_n) / maxf(n - attack_n, 1)
	return pow(1.0 - x, decay_pow)


## pulse (a sine thump), absorb (sine plus saw_mix of saw, falling), raise (a driven saw, rising,
## made gritty by a positive sample-and-hold amplitude wobble, so its zero crossings still follow
## the pitch).
static func _sweep(buf: PackedFloat32Array, kind: String, k: Dictionary, sr: int, c: Dictionary) -> void:
	var n := buf.size()
	var att := int(float(k["attack_s"]) * sr)
	var dp := float(k["decay_pow"])
	var saw_mix := float(k.get("saw_mix", 0.0))
	var drive := float(k.get("drive", 0.0))
	var grit := float(k.get("grit", 0.0))
	var hold := maxi(int(sr / maxf(float(k.get("grit_hz", 1.0)), 1.0)), 1)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(k.get("seed", 1))
	var am := 1.0
	var ph := 0.0
	for i in n:
		ph = fposmod(ph + freq_at(kind, {}, float(i) / n, c) / sr, 1.0)
		var s: float
		if kind == "raise":
			if i % hold == 0:
				am = 1.0 - grit * rng.randf()
			s = tanh(drive * (2.0 * ph - 1.0)) / tanh(drive) * am
		else:
			s = sin(TAU * ph) * (1.0 - saw_mix) + (2.0 * ph - 1.0) * saw_mix
		buf[i] = s * _env(i, n, att, dp)


## A bell: partials [ratio, amp, decay per s] of the score's fundamental.
static func _chime(buf: PackedFloat32Array, params: Dictionary, k: Dictionary, sr: int) -> void:
	var n := buf.size()
	var f := chime_freq(float(params.get("score", 0.0)), k)
	var att := maxi(int(float(k["attack_s"]) * sr), 1)
	var parts: Array = k["partials"]
	for i in n:
		var t := float(i) / sr
		var s := 0.0
		for p in parts:
			s += float(p[1]) * sin(TAU * f * float(p[0]) * t) * exp(-float(p[2]) * t)
		buf[i] = s * minf(float(i) / att, 1.0) * (1.0 - float(i) / n)


## Seeded noise through two one-pole lowpasses whose cutoff rides the envelope from cut0 up to
## cut1: the air brightens as the swing peaks at peak_at, then darkens away.
static func _whoosh(buf: PackedFloat32Array, k: Dictionary, sr: int) -> void:
	var n := buf.size()
	var rng := RandomNumberGenerator.new()
	rng.seed = int(k["seed"])
	var c0 := float(k["cut0"])
	var c1 := float(k["cut1"])
	var at := float(k["peak_at"])
	var y1 := 0.0
	var y2 := 0.0
	for i in n:
		var x := float(i) / n
		var e := pow(x / at, float(k["rise_pow"])) if x < at else pow(1.0 - (x - at) / (1.0 - at), float(k["fall_pow"]))
		var a := 1.0 - exp(-TAU * c0 * pow(c1 / c0, e) / sr)
		y1 += a * (rng.randf() * 2.0 - 1.0 - y1)
		y2 += a * (y1 - y2)
		buf[i] = y2 * e


## Stacked harmonics of a slightly falling fundamental with a slow vibrato, driven, held at full
## after the attack and released over release_s.
static func _horn(buf: PackedFloat32Array, k: Dictionary, sr: int, c: Dictionary) -> void:
	var n := buf.size()
	var att := maxi(int(float(k["attack_s"]) * sr), 1)
	var rel := maxi(int(float(k["release_s"]) * sr), 1)
	var harm: Array = k["harmonics"]
	var vhz := float(k["vibrato_hz"])
	var vd := float(k["vibrato_depth"])
	var drive := float(k["drive"])
	var ph := 0.0
	for i in n:
		var t := float(i) / sr
		var f := freq_at("horn", {}, float(i) / n, c) * (1.0 + vd * sin(TAU * vhz * t))
		ph = fposmod(ph + f / sr, 1.0)
		var s := 0.0
		for h in harm.size():
			s += float(harm[h]) * sin(TAU * ph * (h + 1))
		var e := minf(float(i) / att, 1.0) * minf(float(n - i) / rel, 1.0)
		buf[i] = tanh(drive * s) * e


## A crack: a fast-decaying seeded noise burst plus `pings` high sine glints, each starting in the
## first quarter at a seeded pitch between ping_lo and ping_hi.
static func _shatter(buf: PackedFloat32Array, k: Dictionary, sr: int) -> void:
	var n := buf.size()
	var rng := RandomNumberGenerator.new()
	rng.seed = int(k["seed"])
	var pings: Array = []
	for j in int(k["pings"]):
		pings.append([rng.randf_range(float(k["ping_lo"]), float(k["ping_hi"])), int(rng.randf() * 0.25 * n)])
	var nm := float(k["noise_mix"])
	var dp := float(k["decay_pow"])
	var pdp := float(k["ping_decay_pow"])
	for i in n:
		var x := float(i) / n
		var s := (rng.randf() * 2.0 - 1.0) * nm * pow(1.0 - x, dp)
		for p in pings:
			var i0: int = p[1]
			if i >= i0:
				var xr := float(i - i0) / maxf(n - i0, 1)
				s += sin(TAU * float(p[0]) * (i - i0) / sr) * pow(1.0 - xr, pdp) * (1.0 - nm)
		buf[i] = s


## Two quick bright notes, f0 then f1 at `split`, each with its own attack and decay; a sine with
## tri_mix of triangle.
static func _flip(buf: PackedFloat32Array, k: Dictionary, sr: int) -> void:
	var n := buf.size()
	var cut := int(float(k["split"]) * n)
	var att := int(float(k["attack_s"]) * sr)
	var dp := float(k["decay_pow"])
	var tm := float(k["tri_mix"])
	var ph := 0.0
	for i in n:
		var second := i >= cut
		var f := float(k["f1"]) if second else float(k["f0"])
		ph = fposmod(ph + f / sr, 1.0)
		var s := sin(TAU * ph) * (1.0 - tm) + (1.0 - 4.0 * absf(ph - 0.5)) * tm
		buf[i] = s * (_env(i - cut, n - cut, att, dp) if second else _env(i, cut, att, dp))


## Scales to `peak` (a silent buffer stays silent); a NaN sample becomes 0.
static func _normalise(buf: PackedFloat32Array, target: float) -> PackedFloat32Array:
	var m := 0.0
	for i in buf.size():
		if is_nan(buf[i]) or is_inf(buf[i]):
			buf[i] = 0.0
		m = maxf(m, absf(buf[i]))
	if m > 0.0:
		var g := target / m
		for i in buf.size():
			buf[i] *= g
	return buf


static func peak(buf: PackedFloat32Array) -> float:
	var m := 0.0
	for x in buf:
		m = maxf(m, absf(x))
	return m


## The buffer as 16-bit little-endian PCM, for AudioStreamWAV.FORMAT_16_BITS.
static func to_pcm16(buf: PackedFloat32Array) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(buf.size() * 2)
	for i in buf.size():
		out.encode_s16(i * 2, int(clampf(buf[i], -1.0, 1.0) * 32767.0))
	return out


## Sign changes in buf[from, to): a pitch estimate for a pitched kind (tests use it).
static func zero_crossings(buf: PackedFloat32Array, from: int, to: int) -> int:
	var count := 0
	for i in range(maxi(from + 1, 1), mini(to, buf.size())):
		if (buf[i - 1] < 0.0) != (buf[i] < 0.0):
			count += 1
	return count
