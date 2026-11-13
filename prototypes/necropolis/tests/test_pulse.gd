extends RefCounted
## Tests for the shared line-language toolkit: Pulse (tempo, wave, rate_to_u,
## the five §6 channels, reduced motion) and the Palette accessor.
## Expected numbers are BRIEF §6's literals, not recomputed from config.

const PULSE := preload("res://autoload/pulse.gd")


func _mk() -> Node:
	var p: Node = PULSE.new()
	p.configure(TestUtil.load_json("res://configs/pulse.json"))
	return p


func run() -> int:
	var t := TestUtil.new()
	var cfg := TestUtil.load_json("res://configs/pulse.json")
	var p := _mk()
	_tempo(t, p)
	_rate(t, p, cfg)
	_channels(t, p)
	_wave(t, p, cfg)
	_reduced(t, p)
	p.free()
	_palette(t)
	return t.failures


func _tempo(t: TestUtil, p: Node) -> void:
	t.suite("pulse-tempo")
	t.near(p.tempo_ms, 1714.0, 0.0001, "map tempo T is 1714 ms, read from configs/pulse.json")
	t.ok(not p.reduced_motion, "reduced motion is off by default")
	p.clock_ms = 0.0
	t.near(p.phase(), 0.0, 1e-6, "phase() is 0 on the beat")
	p.clock_ms = 857.0
	t.near(p.phase(), 0.5, 1e-6, "phase() is 0.5 half a beat later")
	p.clock_ms = 1714.0 * 3.0 + 428.5
	t.near(p.phase(), 0.25, 1e-6, "phase() wraps every beat")


func _rate(t: TestUtil, p: Node, cfg: Dictionary) -> void:
	t.suite("pulse-rate")
	t.ok(p.rate_to_u(0.0) == PULSE.OFF, "zero rate is OFF, not slow")
	t.ok(p.rate_to_u(-2.0) == PULSE.OFF, "negative rate is OFF")
	t.ok(p.rate_to_u(float(cfg["rate_off"]) * 0.5) == PULSE.OFF, "rate below rate_off is OFF")
	var rates := [float(cfg["rate_off"]), 0.1, 0.25, 0.5, 1.0, 2.0, 5.0, 10.0, 24.0]
	var prev := -1.0
	var mono := true
	var in_range := true
	for r in rates:
		var u: float = p.rate_to_u(r)
		mono = mono and u > prev
		in_range = in_range and u >= 0.0 and u <= 1.0
		prev = u
	t.ok(mono, "rate_to_u strictly increases below ref")
	t.ok(in_range, "rate_to_u stays in 0..1 when on")
	t.near(p.rate_to_u(25.0), 1.0, 1e-6, "rate == ref (25) maps to u = 1")
	t.near(p.rate_to_u(400.0), 1.0, 1e-6, "rate above ref clamps to u = 1")
	t.near(p.rate_to_u(1.0), log(2.0) / log(26.0), 1e-6, "u = log(1+rate)/log(1+ref)")
	t.near(p.rate_to_u(10.0, 10.0), 1.0, 1e-6, "explicit ref argument is honoured")
	var off: Dictionary = p.channels(PULSE.OFF, 150.0)
	t.ok(off["off"] == true, "channels(OFF) reports off")
	t.ok(off["width"] == 0.0 and off["alpha"] == 0.0, "channels(OFF) has zero width and alpha")
	t.ok(p.channels(0.0, 150.0)["off"] == false, "channels(0) is on (dimmest, not off)")


func _channels(t: TestUtil, p: Node) -> void:
	t.suite("pulse-channels")
	var green := 150.0
	var c0: Dictionary = p.channels(0.0, green)
	t.near(c0["period"], 96.0, 1e-4, "u=0 period 96 (96 - 52u)")
	t.near(c0["width"], 1.1, 1e-4, "u=0 width 1.1 (1.1 + 2.6u)")
	t.near(c0["alpha"], 0.4, 1e-4, "u=0 alpha 0.4 (0.4 + 0.6u)")
	t.near(c0["hue"], 272.0, 1e-4, "u=0 hue is dormant violet 272")
	t.near(c0["speed"], 0.8 * 96.0, 1e-3, "u=0 speed floored to 0.80 x 96 = 76.8 px/s (raw 14 would be 0.146 Hz)")
	t.near(c0["color"].a, 0.4, 1e-4, "color carries the alpha channel")
	var c1: Dictionary = p.channels(1.0, green)
	t.near(c1["period"], 44.0, 1e-4, "u=1 period 44")
	t.near(c1["width"], 3.7, 1e-4, "u=1 width 3.7")
	t.near(c1["alpha"], 1.0, 1e-4, "u=1 alpha 1.0")
	t.near(c1["speed"], 154.0, 1e-3, "u=1 speed 154 px/s (14 + 140u, unclamped)")
	t.near(c1["hue"], green, 1e-3, "u=1 hue is the flow's own hue (green)")
	t.near(p.channels(1.0, 17.8)["hue"], 17.8, 1e-3, "u=1 hue is the flow's own hue (orange)")
	t.near(p.channels(0.0, 17.8)["hue"], 272.0, 1e-4, "orange flow also starts at dormant 272")
	t.near(c1["dash"], 44.0 * 0.5, 1e-4, "dash length is period x dash_duty")

	# Mark frequency band: speed / period within 0.80..7.00 Hz for every u.
	var band_ok := true
	var hz_lo := 99.0
	var hz_hi := 0.0
	for i in 101:
		var ch: Dictionary = p.channels(i / 100.0, green)
		var hz: float = ch["speed"] / ch["period"]
		band_ok = band_ok and hz >= 0.8 - 1e-6 and hz <= 7.0 + 1e-6 and absf(hz - ch["hz"]) < 1e-6
		hz_lo = minf(hz_lo, hz)
		hz_hi = maxf(hz_hi, hz)
	t.ok(band_ok, "marks pass at 0.80..7.00 Hz across u in [0,1] (measured %.3f..%.3f Hz)" % [hz_lo, hz_hi])

	# Hue identity: each flow ramps along the shorter arc and is near its own hue by mid-rate.
	var und_ok := true
	for i in 11:
		var h: float = p.channels(i / 10.0, green)["hue"]
		und_ok = und_ok and h >= green - 1e-3 and h <= 272.0 + 1e-3
	t.ok(und_ok, "undead hue stays on the short arc 272 -> 150 (never through red)")
	var und_mid: float = p.channels(0.5, green)["hue"]
	var liv_mid: float = p.channels(0.5, 17.8)["hue"]
	t.ok(absf(und_mid - green) < 25.0, "mid-rate undead reads green, not blue (hue %.1f)" % und_mid)
	t.ok(absf(wrapf(liv_mid - 17.8, -180.0, 180.0)) < 25.0, "mid-rate living reads orange, not danger red (hue %.1f)" % liv_mid)


func _wave(t: TestUtil, p: Node, cfg: Dictionary) -> void:
	t.suite("pulse-wave")
	var per_hop: float = float(cfg["wave_spread"]) / float(cfg["map_max_hops"])
	t.near(p.hop_phase(1.0), per_hop, 1e-6, "one hop lags wave_spread / map_max_hops beats")
	t.near(p.hop_phase(float(cfg["map_max_hops"])), float(cfg["wave_spread"]), 1e-6, "farthest node lags wave_spread")
	t.ok(p.hop_phase(float(cfg["map_max_hops"])) < 1.0, "farthest node is not back in phase with the source")
	t.near(p.hop_phase(3.0, 6.0), p.hop_phase(1.0, 2.0), 1e-6, "hop_phase is normalised by graph depth")
	p.clock_ms = 0.0
	t.near(p.wave(), 1.0, 1e-6, "wave() is 1 on the beat at the source")
	t.ok(absf(p.wave(1.0) - p.wave(0.0)) > 0.1, "a node one hop out is not pulsing in unison")
	var lag_ms: float = per_hop * float(cfg["tempo_ms"])
	var lag_ok := true
	for base in [0.0, 300.0, 1100.0, 5000.0]:
		p.clock_ms = base
		var w0: float = p.wave(0.0)
		p.clock_ms = base + lag_ms
		var w1: float = p.wave(1.0)
		p.clock_ms = base + 2.0 * lag_ms
		var w2: float = p.wave(2.0)
		lag_ok = lag_ok and absf(w0 - w1) < 1e-4 and absf(w0 - w2) < 1e-4
	t.ok(lag_ok, "wave(h) at t + h x %.1f ms equals wave(0) at t" % lag_ms)


func _reduced(t: TestUtil, p: Node) -> void:
	t.suite("pulse-reduced-motion")
	p.reduced_motion = true
	var first := []
	var frozen := true
	for ms in [0.0, 400.0, 1234.0, 99999.0]:
		p.clock_ms = ms
		var now := [p.phase(), p.phase(1.0), p.wave(), p.wave(2.0), p.dash_offset(120.0, 60.0)]
		if first.is_empty():
			first = now
		frozen = frozen and now == first
	t.ok(frozen, "reduced motion freezes phase(), wave() and dash_offset()")
	t.ok(p.wave() > 0.0, "reduced-motion wave stays above zero, so pulsed marks stay visible")
	p.reduced_motion = false
	p.clock_ms = 0.0
	var d0: float = p.dash_offset(120.0, 60.0)
	p.clock_ms = 250.0
	t.near(p.dash_offset(120.0, 60.0) - d0, 30.0, 1e-4, "dash_offset advances speed x dt when motion is on")


func _palette(t: TestUtil) -> void:
	t.suite("palette")
	Palette.configure(TestUtil.load_json("res://configs/palette.json"))
	# DESIGN.md canon + BRIEF §6 Angiogram helpers, literally.
	var canon := {
		"ground": "05060a", "undead": "39ff9e", "undead_core": "c9ffe8", "living": "ff6a2b",
		"dead": "6e6a7e", "town": "3e5c8f", "relish": "c04cff", "vei": "fff3d0",
		"danger": "ff2d55", "graticule": "12182a", "contour": "1e2a45", "front": "3e5c8f",
	}
	var all_ok := true
	for k in canon:
		all_ok = all_ok and Palette.has(k) and Palette.c(k).is_equal_approx(Color(canon[k]))
	t.ok(all_ok, "palette knows every canon key with its canon value (%d keys)" % canon.size())
	t.ok(Palette.has("dead_lit"), "palette has dead_lit")
	t.near(Palette.c("undead", 0.4).a, 0.4, 1e-6, "c(key, alpha) applies alpha")
	t.near(Palette.hue("undead"), Color("39ff9e").h * 360.0, 1e-4, "hue(key) is the colour's hue in degrees")

	var dead := Palette.c("dead")
	var lit := Palette.c("dead_lit")
	var relish := Palette.c("relish")
	t.ok(lit.get_luminance() > dead.get_luminance(), "dead_lit is lifted in luminance over dead")
	var d_dead := absf(wrapf((dead.h - relish.h) * 360.0, -180.0, 180.0))
	var d_lit := absf(wrapf((lit.h - relish.h) * 360.0, -180.0, 180.0))
	t.ok(d_lit < d_dead, "dead_lit is tinted towards Relish's violet (%.0f deg vs %.0f deg)" % [d_lit, d_dead])
	t.ok(lit.s < 0.5 * relish.s, "dead_lit stays a dull surface, not a violet emitter (sat %.2f)" % lit.s)

	print("  (an ERROR about 'no_such_colour' is expected next)")
	t.ok(Palette.c("no_such_colour") == Palette.MISSING, "unknown key returns the MISSING colour")
	t.ok(not Palette.has("no_such_colour"), "has() is false for an unknown key")
