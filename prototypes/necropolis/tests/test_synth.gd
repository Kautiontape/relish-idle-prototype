extends RefCounted
## Tests for synth_logic.gd (the shared synthesised sounds): every kind renders to its length,
## peaks at or under 1 with no NaN, renders the same twice, and pitches the right way (absorb
## falls, raise rises, chime rises with score); the master volume and mute map to a player's
## volume_db; the cache keys a chime by its score bucket; the dungeon's six kinds (tell, slam,
## muffle, intercept, streak, unravel) behave as designed; AudioPrefs round-trips the saved mute and
## volume through a temp file, applies them to the Master bus and never writes in a harness
## session. No autoloads.

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
	_dungeon_kinds(t, c)
	_prefs(t, c)
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


func _energy(buf: PackedFloat32Array, from: int, to: int) -> float:
	var e := 0.0
	for i in range(from, mini(to, buf.size())):
		e += buf[i] * buf[i]
	return e


func _dungeon_kinds(t: TestUtil, c: Dictionary) -> void:
	for kind in ["tell", "slam", "muffle", "intercept", "streak", "unravel"]:
		t.ok(SynthLogic.KINDS.has(kind), "%s is a kind" % kind)
		var a := SynthLogic.render(kind, {"step": 7}, SR)
		t.ok(a.size() == int(float(c["kinds"][kind]["len_s"]) * SR) and a.size() > 0, "%s renders its length" % kind)
		t.ok(SynthLogic.peak(a) <= 1.0, "%s peaks at most 1" % kind)
		t.ok(SynthLogic.render(kind, {"step": 7}, SR) == a, "%s renders the same twice" % kind)
	var ks: Dictionary = c["kinds"]
	# streak: pitch rises with step; the cache buckets by step.
	var z0 := SynthLogic.zero_crossings(SynthLogic.render("streak", {"step": 0}, SR), 0, 100000)
	var z10 := SynthLogic.zero_crossings(SynthLogic.render("streak", {"step": 10}, SR), 0, 100000)
	var z20 := SynthLogic.zero_crossings(SynthLogic.render("streak", {"step": 20}, SR), 0, 100000)
	t.ok(z0 < z10 and z10 < z20, "streak pitch rises with step (%d < %d < %d crossings)" % [z0, z10, z20])
	t.ok(SynthLogic.freq_at("streak", {"step": 0}, 0.0) < SynthLogic.freq_at("streak", {"step": 20}, 0.0), "streak's pitch track rises with step")
	t.ok(SynthLogic.cache_key("streak", {"step": 4.2}) == "streak:4" and SynthLogic.cache_key("streak", {"step": 4}) == "streak:4", "nearby steps share a streak tick")
	t.ok(SynthLogic.cache_key("streak", {"step": 5}) != SynthLogic.cache_key("streak", {"step": 4}), "a step apart is another tick")
	t.ok(SynthLogic.cache_key("streak", {}) == "streak:0", "no step is step 0")
	t.ok(SynthLogic.cache_key("streak", {"step": 99}) == "streak:20" and SynthLogic.cache_key("streak", {"step": -3}) == "streak:0", "steps clamp to 0..20")
	# muffle vs slam: same onset, shorter, no ring tail.
	var slam := SynthLogic.render("slam", {}, SR)
	var muf := SynthLogic.render("muffle", {}, SR)
	t.ok(muf.size() < slam.size(), "muffle is shorter than slam")
	var onset := SR / 50  # 20 ms
	var dot := 0.0
	var na := 0.0
	var nb := 0.0
	for i in onset:
		dot += slam[i] * muf[i]
		na += slam[i] * slam[i]
		nb += muf[i] * muf[i]
	t.ok(dot / sqrt(na * nb) > 0.9, "muffle starts like slam (onset correlation %.3f)" % (dot / sqrt(na * nb)))
	var half_s := _energy(slam, slam.size() / 2, slam.size())
	var half_m := _energy(muf, muf.size() / 2, muf.size())
	t.ok(half_m < 0.05 * half_s, "muffle has no ring tail (last-half energy %.2f vs slam %.2f)" % [half_m, half_s])
	t.ok(float(ks["muffle"]["bell_mix"]) == 0.0 and float(ks["slam"]["bell_mix"]) > 0.0, "only slam has the bell")
	for key in ["boom_f0", "boom_f1", "boom_glide", "boom_decay", "thump_mix", "thump_decay", "seed"]:
		t.ok(ks["slam"][key] == ks["muffle"][key], "slam and muffle share %s (the same boom)" % key)
	# unravel: about 2 s, falls.
	var un := SynthLogic.render("unravel", {}, SR)
	t.ok(absf(float(un.size()) / SR - 2.0) < 0.25, "unravel is about 2 s (%.2f)" % (float(un.size()) / SR))
	var th := _thirds(un)
	t.ok(th.x > th.y * 1.5, "unravel falls: more crossings early than late (%.4f vs %.4f)" % [th.x, th.y])
	# tell: shorter and quieter than slam.
	t.ok(float(ks["tell"]["len_s"]) < float(ks["slam"]["len_s"]) and float(ks["tell"]["gain_db"]) < float(ks["slam"]["gain_db"]), "tell is shorter and quieter than slam")
	# intercept: a sharp attack.
	var ic := SynthLogic.render("intercept", {}, SR)
	var pk := SynthLogic.peak(ic)
	var pk10 := SynthLogic.peak(ic.slice(0, SR / 100))
	t.ok(pk10 > 0.99 * pk, "intercept peaks within its first 10 ms (%.3f of %.3f)" % [pk10, pk])
	t.ok(SynthLogic.peak(ic.slice(SR / 100, ic.size())) <= pk, "intercept's attack is its peak")
	# the buzz: energy continues after the clang has rung down.
	t.ok(_energy(ic, int(0.2 * SR), int(0.3 * SR)) > 0.0005 * _energy(ic, 0, SR / 20), "intercept buzzes after the clang")


func _fake_game(autosave: bool) -> Node:
	var scr := GDScript.new()
	scr.source_code = "extends Node\nvar autosave_enabled := true\n"
	scr.reload()
	var n := Node.new()
	n.set_script(scr)
	n.name = "Game"
	n.set("autosave_enabled", autosave)
	AudioPrefs.game_node = n  # a script test has no scene tree to hold /root/Game
	return n


func _prefs(t: TestUtil, c: Dictionary) -> void:
	var tmp := "user://test_synth_settings.cfg"
	var tmp_abs := ProjectSettings.globalize_path(tmp)
	DirAccess.remove_absolute(tmp_abs)
	AudioPrefs.settings_path = tmp
	AudioPrefs.reset()
	var bus := AudioServer.get_bus_index("Master")
	t.ok(bus >= 0, "there is a Master bus")
	var was_mute := AudioServer.is_bus_mute(bus)
	var was_db := AudioServer.get_bus_volume_db(bus)
	# pure parts
	t.ok(SynthLogic.clamp_master_db(-200.0, c) == float(c["mute_db"]) and SynthLogic.clamp_master_db(40.0, c) == float(c["max_db"]), "master_db clamps to [mute_db, max_db]")
	t.ok(SynthLogic.clamp_master_db(-3.0, c) == -3.0, "an in-range master_db is kept")
	var d := SynthLogic.merge_prefs({}, c)
	t.ok(d["muted"] == bool(c["muted"]) and d["master_db"] == float(c["master_db"]), "no saved values give the defaults")
	var m := SynthLogic.merge_prefs({"muted": true, "master_db": -12}, c)
	t.ok(m["muted"] == true and m["master_db"] == -12.0, "saved values override the defaults (an int db too)")
	m = SynthLogic.merge_prefs({"muted": "yes", "master_db": "loud"}, c)
	t.ok(m["muted"] == bool(c["muted"]) and m["master_db"] == float(c["master_db"]), "wrongly typed values fall back to the defaults")
	t.ok(SynthLogic.merge_prefs({"master_db": 99.0}, c)["master_db"] == float(c["max_db"]), "a saved db out of range is clamped")
	# defaults when the file is missing
	t.ok(not AudioPrefs.muted() and AudioPrefs.master_db() == float(c["master_db"]), "a missing file gives the defaults")
	# a corrupt file
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	f.store_string("[audio\nmuted = = nonsense {{{")
	f.close()
	AudioPrefs.reset()
	t.ok(not AudioPrefs.muted() and AudioPrefs.master_db() == float(c["master_db"]), "a corrupt file gives the defaults")
	DirAccess.remove_absolute(tmp_abs)
	# a round trip (no Game node: a plain test run may save)
	t.ok(AudioPrefs.can_save(), "with no Game node a session may save")
	AudioPrefs.reset()
	AudioPrefs.set_muted(true)
	AudioPrefs.set_master_db(-14.0)
	var cf := ConfigFile.new()
	t.ok(cf.load(tmp) == OK and cf.get_value("audio", "muted") == true and cf.get_value("audio", "master_db") == -14.0, "the preference is saved to settings.cfg's audio section")
	AudioPrefs.reset()
	t.ok(AudioPrefs.muted() and AudioPrefs.master_db() == -14.0, "it reads back after a reload")
	# apply puts it on the Master bus
	AudioServer.set_bus_mute(bus, false)
	AudioServer.set_bus_volume_db(bus, 0.0)
	AudioPrefs.apply()
	t.ok(AudioServer.is_bus_mute(bus) and AudioServer.get_bus_volume_db(bus) == -14.0, "apply sets the Master bus mute and volume")
	AudioPrefs.toggle_mute()
	t.ok(not AudioServer.is_bus_mute(bus) and not AudioPrefs.muted(), "toggle_mute unmutes the bus")
	cf = ConfigFile.new()
	cf.load(tmp)
	t.ok(cf.get_value("audio", "muted") == false, "the toggle is saved")
	AudioPrefs.set_master_db(500.0)
	t.ok(AudioServer.get_bus_volume_db(bus) == float(c["max_db"]), "set_master_db clamps on the bus")
	# other sections survive a save
	cf = ConfigFile.new()
	cf.load(tmp)
	cf.set_value("other", "keep", 1)
	cf.save(tmp)
	AudioPrefs.set_muted(true)
	cf = ConfigFile.new()
	cf.load(tmp)
	t.ok(cf.get_value("other", "keep", 0) == 1, "saving keeps other sections")
	# Synth mirrors it
	var synth := Synth.new()
	t.ok(synth.is_muted() == AudioPrefs.muted() and synth.is_muted(), "Synth.is_muted mirrors AudioPrefs")
	synth.set_muted(false)
	t.ok(not AudioPrefs.muted() and not synth.is_muted() and not AudioServer.is_bus_mute(bus), "Synth.set_muted forwards to AudioPrefs and the bus")
	synth.free()
	# a harness session applies in memory and never writes
	var mtime_before := FileAccess.get_modified_time(tmp)
	var before := FileAccess.get_file_as_string(tmp)
	var game := _fake_game(false)
	t.ok(not AudioPrefs.can_save(), "autosave_enabled false is a harness session")
	AudioPrefs.set_muted(true)
	AudioPrefs.set_master_db(-30.0)
	t.ok(AudioServer.is_bus_mute(bus) and AudioServer.get_bus_volume_db(bus) == -30.0, "a harness session still applies to the bus")
	t.ok(FileAccess.get_file_as_string(tmp) == before and FileAccess.get_modified_time(tmp) == mtime_before, "a harness session does not write the file")
	game.free()
	AudioPrefs.game_node = null
	var game2 := _fake_game(true)
	t.ok(AudioPrefs.can_save(), "autosave_enabled true may save")
	game2.free()
	AudioPrefs.game_node = null
	# clean up: the file, the static state and the bus
	DirAccess.remove_absolute(tmp_abs)
	AudioPrefs.settings_path = AudioPrefs.DEFAULT_PATH
	AudioPrefs.reset()
	AudioServer.set_bus_mute(bus, was_mute)
	AudioServer.set_bus_volume_db(bus, was_db)
