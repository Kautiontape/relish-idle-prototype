extends RefCounted
## Tests for synth_logic.gd (the shared synthesised sounds): every kind renders to its length,
## peaks at or under 1 with no NaN, renders the same twice, and pitches the right way (absorb
## falls, raise rises, chime rises with score); the master volume and mute map to a player's
## volume_db; the cache keys a chime by its score bucket. No autoloads.

const SR := 22050


func run() -> int:
	var t := TestUtil.new()
	t.suite("synth")
	var c := TestUtil.load_json("res://configs/synth.json")
	SynthLogic.configure(c)
	_config(t, c)
	_render(t, c)
	_pitch(t, c)
	_volume(t, c)
	_cache(t, c)
	_pcm(t)
	return t.failures


func _config(t: TestUtil, c: Dictionary) -> void:
	for k in ["sample_rate", "master_db", "muted", "mute_key", "mute_db", "max_db", "max_voices", "peak", "log_once", "kinds"]:
		t.ok(c.has(k), "synth.json has %s" % k)
	for kind in SynthLogic.KINDS:
		var k: Dictionary = c["kinds"].get(kind, {})
		t.ok(k.has("len_s") and k.has("gain_db"), "%s has its length and gain" % kind)
	t.ok(float(c["peak"]) <= 1.0, "the render peak is at most full scale")
	var pulse_db := float(c["kinds"]["pulse"]["gain_db"])
	var loudest_other := -INF
	for kind in SynthLogic.KINDS:
		if kind != "pulse":
			loudest_other = maxf(loudest_other, float(c["kinds"][kind]["gain_db"]))
	var quietest_other := INF
	for kind in SynthLogic.KINDS:
		if kind != "pulse":
			quietest_other = minf(quietest_other, float(c["kinds"][kind]["gain_db"]))
	t.ok(pulse_db <= quietest_other - 10.0, "the tempo pulse sits well under every other kind (%.0f dB vs %.0f)" % [pulse_db, quietest_other])
	t.ok(OS.find_keycode_from_string(str(c["mute_key"])) != KEY_NONE, "the mute key names a real key")


func _render(t: TestUtil, c: Dictionary) -> void:
	for kind in SynthLogic.KINDS:
		var t0 := Time.get_ticks_usec()
		var buf := SynthLogic.render(kind, {"score": 60.0}, SR)
		var ms := (Time.get_ticks_usec() - t0) / 1000.0
		var want := int(float(c["kinds"][kind]["len_s"]) * SR)
		t.ok(buf.size() == want, "%s renders %d samples (%d)" % [kind, want, buf.size()])
		var nan := false
		for x in buf:
			nan = nan or is_nan(x) or is_inf(x)
		t.ok(not nan, "%s has no NaN or inf" % kind)
		var pk := SynthLogic.peak(buf)
		t.ok(pk <= 1.0 and absf(pk - float(c["peak"])) < 1e-4, "%s peaks at the config's peak (%.4f)" % [kind, pk])
		t.ok(absf(buf[buf.size() - 1]) < 0.05 * pk, "%s ends near silence (no click)" % kind)
		t.ok(SynthLogic.render(kind, {"score": 60.0}, SR) == buf, "%s renders the same twice (seeded)" % kind)
		print("  [synth] %s rendered in %.1f ms" % [kind, ms])
	t.ok(SynthLogic.render("nope", {}, SR).is_empty(), "an unknown kind renders empty")
	t.ok(SynthLogic.render("pulse", {}, 11025).size() == int(float(c["kinds"]["pulse"]["len_s"]) * 11025), "the sample rate sets the length")
	t.ok(SynthLogic.render("pulse").size() == int(float(c["kinds"]["pulse"]["len_s"]) * int(c["sample_rate"])), "sample rate 0 uses the config's")


## Zero crossings per sample in the first and last thirds: the pitch direction a listener hears.
func _thirds(buf: PackedFloat32Array) -> Vector2:
	var n := buf.size()
	var a := float(SynthLogic.zero_crossings(buf, 0, n / 3)) / (n / 3)
	var b := float(SynthLogic.zero_crossings(buf, n - n / 3, n)) / (n / 3)
	return Vector2(a, b)


func _pitch(t: TestUtil, c: Dictionary) -> void:
	var ab := _thirds(SynthLogic.render("absorb", {}, SR))
	t.ok(ab.x > ab.y * 2.0, "absorb falls: more crossings early than late (%.4f vs %.4f)" % [ab.x, ab.y])
	var ra := _thirds(SynthLogic.render("raise", {}, SR))
	t.ok(ra.y > ra.x * 1.5, "raise rises: more crossings late than early (%.4f vs %.4f)" % [ra.x, ra.y])
	t.ok(SynthLogic.freq_at("absorb", {}, 0.0) > SynthLogic.freq_at("absorb", {}, 0.5) and SynthLogic.freq_at("absorb", {}, 0.5) > SynthLogic.freq_at("absorb", {}, 1.0), "absorb's pitch track falls")
	t.ok(SynthLogic.freq_at("raise", {}, 0.0) < SynthLogic.freq_at("raise", {}, 0.5) and SynthLogic.freq_at("raise", {}, 0.5) < SynthLogic.freq_at("raise", {}, 1.0), "raise's pitch track rises")
	var lo := SynthLogic.render("chime", {"score": 0.0}, SR)
	var hi := SynthLogic.render("chime", {"score": 100.0}, SR)
	var mid := SynthLogic.render("chime", {"score": 50.0}, SR)
	var zl := SynthLogic.zero_crossings(lo, 0, lo.size())
	var zm := SynthLogic.zero_crossings(mid, 0, mid.size())
	var zh := SynthLogic.zero_crossings(hi, 0, hi.size())
	t.ok(zl < zm and zm < zh, "chime pitch rises with score (%d < %d < %d crossings)" % [zl, zm, zh])
	var k: Dictionary = c["kinds"]["chime"]
	t.near(SynthLogic.freq_at("chime", {"score": 0.0}, 0.5), float(k["f_lo"]), 1e-3, "score 0 is f_lo")
	t.near(SynthLogic.freq_at("chime", {"score": 100.0}, 0.5), float(k["f_hi"]), 1e-3, "score 100 is f_hi")
	t.near(SynthLogic.freq_at("chime", {"score": 250.0}, 0.5), float(k["f_hi"]), 1e-3, "a score over 100 clamps")
	var pu := _thirds(SynthLogic.render("pulse", {}, SR))
	t.ok(SynthLogic.freq_at("pulse", {}, 0.0) < 120.0 and pu.x < 0.02, "the pulse is low (%.4f crossings per sample)" % pu.x)
	t.ok(SynthLogic.freq_at("flip", {}, 0.0) < SynthLogic.freq_at("flip", {}, 0.9), "the flip steps up")
	t.ok(SynthLogic.freq_at("whoosh", {}, 0.5) == 0.0 and SynthLogic.freq_at("shatter", {}, 0.5) == 0.0, "whoosh and shatter are unpitched")


func _volume(t: TestUtil, c: Dictionary) -> void:
	var mute := float(c["mute_db"])
	t.ok(SynthLogic.volume_db(-6.0, -10.0, false, c) == -16.0, "volume is master_db + the kind's gain_db")
	t.ok(SynthLogic.volume_db(-6.0, -10.0, true, c) == mute, "muted is mute_db")
	t.ok(SynthLogic.volume_db(0.0, 0.0, true, c) == mute, "muted is mute_db at any master")
	t.ok(SynthLogic.volume_db(-70.0, -30.0, false, c) == mute, "a very low volume floors at mute_db")
	t.ok(SynthLogic.volume_db(20.0, 0.0, false, c) == float(c["max_db"]), "a very high volume caps at max_db")
	t.ok(SynthLogic.volume_db(-3.0, 0.0, false, c) > SynthLogic.volume_db(-9.0, 0.0, false, c), "a higher master is louder")
	var g := float(c["kinds"]["pulse"]["gain_db"])
	t.ok(SynthLogic.volume_db(float(c["master_db"]), g, bool(c["muted"]), c) < SynthLogic.volume_db(float(c["master_db"]), float(c["kinds"]["whoosh"]["gain_db"]), false, c), "at the config's master, the pulse is quieter than the whoosh")


func _cache(t: TestUtil, c: Dictionary) -> void:
	var step := float(c["kinds"]["chime"]["score_step"])
	t.ok(SynthLogic.cache_key("whoosh", {"score": 40.0}) == "whoosh", "a plain kind's key is its name")
	t.ok(SynthLogic.cache_key("chime", {"score": 41.0}) == SynthLogic.cache_key("chime", {"score": 40.0 + step * 0.4}), "nearby scores share a chime")
	t.ok(SynthLogic.cache_key("chime", {"score": 40.0}) != SynthLogic.cache_key("chime", {"score": 40.0 + step}), "a score step apart is another chime")
	t.ok(SynthLogic.cache_key("chime", {}) == "chime:0", "no score is score 0")
	t.ok(SynthLogic.score_bucket(-5.0, step) == 0 and SynthLogic.score_bucket(120.0, step) == 100, "buckets clamp to 0..100")


func _pcm(t: TestUtil) -> void:
	var b := PackedFloat32Array([0.0, 1.0, -1.0, 0.5, 2.0])
	var p := SynthLogic.to_pcm16(b)
	t.ok(p.size() == 10, "16-bit PCM is two bytes a sample")
	t.ok(p.decode_s16(2) == 32767 and p.decode_s16(4) == -32767 and p.decode_s16(0) == 0, "full scale maps to +-32767")
	t.ok(p.decode_s16(8) == 32767, "an over-range sample clips")
