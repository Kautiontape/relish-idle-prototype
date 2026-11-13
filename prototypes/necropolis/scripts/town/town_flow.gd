extends Node2D
## The town view's per-frame layer: the street flows and the crypt slab's rings.
## Flows (law 3, law 4): each street carries its undead stream, TownAgents.edge_rates (the agents
## walking it, per second, smoothed), drawn outward from the plaza; the rate drives Pulse's five
## channels and the dashes walk at Pulse.dash_offset. A zero rate switches the street off (only its
## bed shows). Reduced motion: the dashes hold still (Pulse) and each carries a chevron pointing
## along the flow.
## The slab (law 5): the town's tempo source, hops 0. Concentric undead rings around the crypt
## (ellipses fitted to its footprint, so they ring the building instead of crossing its lines)
## breathe on the beat, and one ring rides out from them each beat.

var model: TownModel
var vcfg: Dictionary = {}
## The streams' source: edge_rates, indexed like model.streets.
var agents: TownAgents
## The crypt's footprint (the slab sits at its centre); an empty rect when the town has no crypt.
var slab_rect := Rect2()


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if model == null:
		return
	_draw_flows()
	_draw_slab()


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
	var alpha := float(vcfg.get("slab_ring_alpha", 1.0))
	var wave := Pulse.wave(0.0, model.depth)
	var margins: Array = vcfg.get("slab_rings_px", [])
	for m in margins:
		LineGlow.polyline(self, _ellipse(float(m) * k), Palette.c("undead", alpha), w, wave)
	if margins.is_empty() or Pulse.reduced_motion:
		return
	# One ring rides out from the outermost each beat, fading as it goes.
	var b := Pulse.phase(0.0, model.depth)
	var m0 := float(margins[margins.size() - 1]) * k
	var reach := float(vcfg.get("slab_ring_reach_px", 0.0)) * k
	LineGlow.polyline(self, _ellipse(m0 + b * reach), Palette.c("undead", alpha * wave), w, wave)


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
