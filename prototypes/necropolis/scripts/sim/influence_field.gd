class_name InfluenceField
extends RefCounted
## Necrosis influence grid. Two scalar layers (green = UNDEAD, orange = LIVING)
## plus a signed entrenchment layer: the longer a side dominates a cell, the
## faster it gains there (necrosis growth); opposing pressure erodes the
## entrenchment before it flips the territory. Not literal Gray-Scott — the
## organic look comes from diffusion + contest + the renderer's banding.

var w := 128
var h := 90
var green := PackedFloat32Array()
var orange := PackedFloat32Array()
var entrench := PackedFloat32Array()  # + entrenched green, - entrenched orange
var world_size := Vector2(2048, 1440)
var cfg := {}


func setup(cfg_in: Dictionary, world_size_in: Vector2) -> void:
	cfg = cfg_in
	w = int(cfg.get("w", 128))
	h = int(cfg.get("h", 90))
	world_size = world_size_in
	green.resize(w * h)
	orange.resize(w * h)
	entrench.resize(w * h)
	green.fill(0.0)
	orange.fill(0.0)
	entrench.fill(0.0)


func cell_of(pos: Vector2) -> Vector2i:
	return Vector2i(
		clampi(int(pos.x / world_size.x * w), 0, w - 1),
		clampi(int(pos.y / world_size.y * h), 0, h - 1))


func inject(pos: Vector2, is_green: bool, amount: float, radius := 1) -> void:
	var c := cell_of(pos)
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var x := c.x + dx
			var y := c.y + dy
			if x < 0 or y < 0 or x >= w or y >= h:
				continue
			var fall := 1.0 / (1.0 + dx * dx + dy * dy)
			var i := y * w + x
			if is_green:
				green[i] = minf(4.0, green[i] + amount * fall)
			else:
				orange[i] = minf(4.0, orange[i] + amount * fall)


func tick(dt: float) -> void:
	var d: float = float(cfg.get("diffuse", 0.16)) * dt * 5.0
	var decay: float = float(cfg.get("decay", 0.012)) * dt * 5.0
	var contest: float = float(cfg.get("contest", 1.35)) * dt * 5.0
	var e_rate: float = float(cfg.get("entrench_rate", 0.025)) * dt * 5.0
	var e_max: float = float(cfg.get("entrench_max", 2.5))
	var e_decay: float = float(cfg.get("entrench_decay", 0.08)) * dt * 5.0
	var g0 := green.duplicate()
	var o0 := orange.duplicate()
	for y in h:
		var row := y * w
		for x in w:
			var i := row + x
			var gl := g0[i - 1] if x > 0 else g0[i]
			var gr := g0[i + 1] if x < w - 1 else g0[i]
			var gu := g0[i - w] if y > 0 else g0[i]
			var gd := g0[i + w] if y < h - 1 else g0[i]
			var ol := o0[i - 1] if x > 0 else o0[i]
			var orr := o0[i + 1] if x < w - 1 else o0[i]
			var ou := o0[i - w] if y > 0 else o0[i]
			var od := o0[i + w] if y < h - 1 else o0[i]

			var e := entrench[i]
			# entrenchment multiplies how fast the entrenched side flows/grows here
			var g_mult := 1.0 + maxf(0.0, e)
			var o_mult := 1.0 + maxf(0.0, -e)
			var g := g0[i] + d * g_mult * ((gl + gr + gu + gd) * 0.25 - g0[i])
			var o := o0[i] + d * o_mult * ((ol + orr + ou + od) * 0.25 - o0[i])
			g *= 1.0 - decay
			o *= 1.0 - decay
			# contest: opposing influence annihilates
			var clash := minf(g, o) * contest
			g -= clash
			o -= clash
			# entrenchment: dominance deepens, opposition erodes it first
			var dom := g - o
			if dom > 0.05:
				e = minf(e_max, e + e_rate * minf(1.0, dom)) if e >= 0.0 else e + e_rate * 2.0
			elif dom < -0.05:
				e = maxf(-e_max, e - e_rate * minf(1.0, -dom)) if e <= 0.0 else e - e_rate * 2.0
			else:
				e = lerpf(e, 0.0, e_decay)
			green[i] = clampf(g, 0.0, 4.0)
			orange[i] = clampf(o, 0.0, 4.0)
			entrench[i] = e


func dominance_at(pos: Vector2) -> float:
	var c := cell_of(pos)
	var i := c.y * w + c.x
	return green[i] - orange[i]


func entrench_at(pos: Vector2) -> float:
	var c := cell_of(pos)
	return entrench[c.y * w + c.x]
