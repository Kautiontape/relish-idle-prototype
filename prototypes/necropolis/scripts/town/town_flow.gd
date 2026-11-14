extends Node2D
## The town view's per-frame layer: the street flows and the crypt slab's rings.
## Flows (law 3, law 4): each street carries its undead stream, TownAgents.edge_rates (the agents
## walking it, per second, smoothed), drawn outward from the plaza; the rate drives Pulse's five
## channels and the dashes walk at Pulse.dash_offset. A zero rate switches the street off (only its
## bed shows). Reduced motion: the dashes hold still (Pulse) and each carries a chevron pointing
## along the flow; every street also carries its ring number out from the crypt (1 at the plaza,
## TownModel.street_order), small `text_dim`, the still equivalent of the wave.
## The slab (law 5): the town's tempo source, hops 0. Concentric undead rings around the crypt
## (ellipses fitted to its footprint, so they ring the building instead of crossing its lines)
## breathe on the beat, and one ring rides out from them each beat. While Relish is away the slab
## is idle: the rings still breathe, fainter (view.slab_ring_away_alpha), and none rides out.

var model: TownModel
var vcfg: Dictionary = {}
## The streams' source: edge_rates, indexed like model.streets.
var agents: TownAgents
## The crypt's footprint (the slab sits at its centre); an empty rect when the town has no crypt.
var slab_rect := Rect2()

var _echo_ms := -1.0  # Pulse.now_ms() when a raise's echo began; -1 = none


func _process(_delta: float) -> void:
	queue_redraw()


## A raise: the slab's rings contract toward the crypt's centre over view.raise_echo.beats beats, then
## settle back (the town's echo of the crypt tab's collapse). Reduced motion: no movement, the rings
## flash bright for the same time.
func echo_raise() -> void:
	_echo_ms = Pulse.now_ms()


## 0..1..0 through the echo (0 when none): sin over its length.
func _echo() -> float:
	if _echo_ms < 0.0:
		return 0.0
	var spec: Dictionary = vcfg.get("raise_echo", {})
	var dur := float(spec.get("beats", 1.0)) * Pulse.tempo_ms
	var x := (Pulse.now_ms() - _echo_ms) / dur if dur > 0.0 else 1.0
	if x >= 1.0:
		_echo_ms = -1.0
		return 0.0
	return 1.0 if Pulse.reduced_motion else sin(PI * clampf(x, 0.0, 1.0))


func _draw() -> void:
	if model == null:
		return
	_draw_flows()
	_draw_slab()
	if Pulse.reduced_motion:
		_draw_ring_order()


func _draw_flows() -> void:
	var ref := float(vcfg.get("flow_ref", 0.0))
	var glow := float(vcfg.get("flow_glow", 0.5))
	var hue := Palette.hue("undead")
	var core := Palette.c("undead_core")
	var chev := float(vcfg.get("chevron_px", 0.0)) * model.scale
	for i in model.streets.size():
		var s: Dictionary = model.streets[i]
		var rate := agents.edge_rates[i] if agents != null and i < agents.edge_rates.size() else 0.0
		var u := Pulse.rate_to_u(rate, ref)
		if u == Pulse.OFF:
			continue
		var ch := Pulse.channels(u, hue)
		var a: Vector2 = s["near"]
		var b: Vector2 = s["far"]
		var length := a.distance_to(b)
		if length <= 0.0:
			continue
		var dir := (b - a) / length
		var period: float = ch["period"]
		var dash: float = ch["dash"]
		var d := -period + Pulse.dash_offset(ch["speed"], period)
		var segs := PackedVector2Array()
		var heads := PackedVector2Array()
		while d < length:
			var s0 := maxf(d, 0.0)
			var s1 := minf(d + dash, length)
			if s1 > s0:
				segs.append(a + dir * s0)
				segs.append(a + dir * s1)
				if s1 - s0 >= chev:
					heads.append(a + dir * s1)
			d += period
		if segs.is_empty():
			continue
		for l in LineGlow.layers(ch["color"], ch["width"], glow, core):
			draw_multiline(segs, l[1], l[0])
		if Pulse.reduced_motion and chev > 0.0:
			var side := Vector2(-dir.y, dir.x)
			var lines := PackedVector2Array()
			for h in heads:
				var tip := h + dir * chev * 0.6
				lines.append(tip)
				lines.append(tip - dir * chev + side * chev * 0.7)
				lines.append(tip)
				lines.append(tip - dir * chev - side * chev * 0.7)
			for l in LineGlow.layers(ch["color"], ch["width"] * float(vcfg.get("chevron_w_mul", 1.0)), glow, core):
				draw_multiline(lines, l[1], l[0])


func _draw_slab() -> void:
	if slab_rect.size.x <= 0.0:
		return
	var k := model.scale
	var w := float(vcfg.get("slab_ring_w_px", 1.0))
	var home := agents != null and agents.relish_home
	var alpha := float(vcfg.get("slab_ring_alpha" if home else "slab_ring_away_alpha", 1.0))
	var wave := Pulse.wave(0.0, model.depth)
	var margins: Array = vcfg.get("slab_rings_px", [])
	var echo := _echo()
	var pull := 0.0 if Pulse.reduced_motion else echo * float(vcfg.get("raise_echo", {}).get("shrink", 0.0))
	if echo > 0.0:
		alpha = lerpf(alpha, float(vcfg.get("raise_echo", {}).get("flash_alpha", 1.0)), echo)
	for m in margins:
		LineGlow.polyline(self, _ellipse(float(m) * k * (1.0 - pull)), Palette.c("undead", alpha), w, maxf(wave, echo))
	if margins.is_empty() or Pulse.reduced_motion or not home:
		return
	# One ring rides out from the outermost each beat, fading as it goes.
	var b := Pulse.phase(0.0, model.depth)
	var m0 := float(margins[margins.size() - 1]) * k
	var reach := float(vcfg.get("slab_ring_reach_px", 0.0)) * k
	LineGlow.polyline(self, _ellipse(m0 + b * reach), Palette.c("undead", alpha * wave), w, wave)


## Each street's ring number at its middle, set off to one side (view.ring_order).
func _draw_ring_order() -> void:
	var rc: Dictionary = vcfg.get("ring_order", {})
	var font := ThemeDB.fallback_font
	var fs := maxi(int(rc.get("px", TownUI.MIN_TEXT)), TownUI.MIN_TEXT)
	var off := float(rc.get("offset_px", 0.0)) * model.scale
	var col := Palette.c("text_dim")
	for i in mini(model.streets.size(), model.street_order.size()):
		var n := model.street_order[i]
		if n <= 0:
			continue
		var s: Dictionary = model.streets[i]
		var a: Vector2 = s["near"]
		var b: Vector2 = s["far"]
		var d := (b - a).normalized()
		var c := (a + b) * 0.5 + Vector2(-d.y, d.x) * off
		var t := str(n)
		var sz := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		draw_string(font, c + Vector2(-sz.x * 0.5, (font.get_ascent(fs) - font.get_descent(fs)) * 0.5), t,
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


## A closed ellipse around the crypt's footprint, `margin` px outside its half-extents.
func _ellipse(margin: float) -> PackedVector2Array:
	var c := slab_rect.get_center()
	var rx := slab_rect.size.x * 0.5 + margin
	var ry := slab_rect.size.y * 0.5 + margin
	var n := LineGlow.segments(maxf(rx, ry), TAU)
	var out := PackedVector2Array()
	out.resize(n + 1)
	for i in n + 1:
		var a := TAU * float(i) / float(n)
		out[i] = c + Vector2(cos(a) * rx, sin(a) * ry)
	return out
