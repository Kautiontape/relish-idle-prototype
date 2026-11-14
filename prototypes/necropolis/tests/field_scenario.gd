class_name FieldScenario
extends RefCounted
## Contested field-level scenarios for the catch-up field step (catchup_step; test_field_catchup.gd,
## tests/slow/field_catchup_bench.gd): sources and villages of their own on a grid of their own, no
## GameState. Villages read dominance at their cell against field.town_threshold, as _update_towns.
## Cells are 16 world px, as on the shipped grid.
## - "jumps": garrisons hold still, then change hands in steps (12 in 12 h), the way forts fall.
##   Contested (about 22% of village samples green, 20% orange) and never lingering at the threshold.
## - "drift": every garrison swings with periods of 3-9 h (about 69 owner changes in 12 h): a stress
##   case, its villages often sitting near the threshold.
## - "mixed": one-sided garrisons that drift slowly, plus 6 flips.
## - "mini": a 40 x 30 grid, 3 forts and 4 villages, for the fast suite.
## The first three are on the shipped 128 x 90 grid (crop = false) or cropped to a 64 x 45 window
## around the forts and villages (crop = true), with the two main sources moved to its corners.

const CELL := 16.0
const FORTS := [Vector2i(60, 40), Vector2i(75, 50), Vector2i(45, 55), Vector2i(85, 30), Vector2i(55, 25),
	Vector2i(90, 60), Vector2i(35, 35), Vector2i(70, 65)]
const VILLAGES := [Vector2i(63, 43), Vector2i(72, 47), Vector2i(48, 52), Vector2i(82, 33), Vector2i(58, 28),
	Vector2i(87, 57), Vector2i(38, 38), Vector2i(67, 62), Vector2i(52, 47), Vector2i(80, 40), Vector2i(65, 33),
	Vector2i(78, 58)]
const CROP := Vector2i(34, 22)
const DRIFT := [[5.0, 0.3], [7.0, 1.9], [4.0, 3.1], [9.0, 0.8], [6.0, 4.4], [3.0, 2.2], [8.0, 5.5], [5.5, 1.1]]
const DRIFT_FLIPS := {1: [3 * 3600 + 1200, 0.35], 4: [7 * 3600 + 600, -0.35]}
const JUMPS_U0 := [0.8, 0.3, 0.6, 0.2, 0.7, 0.45, 0.35, 0.55]
const JUMPS := [[1500, 1, 0.9], [4200, 4, 0.1], [6000, 2, 0.0], [9000, 6, 0.95], [13500, 0, 0.15], [18000, 3, 0.85],
	[21000, 5, 1.0], [25800, 1, 0.2], [30000, 7, 0.0], [33600, 4, 0.9], [37800, 2, 0.75], [41100, 6, 0.3]]
const MIXED_U0 := [0.92, 0.12, 0.88, 0.08, 0.85, 0.2, 0.1, 0.9]
const MIXED_PER := [9.0, 14.0, 11.0, 16.0, 8.0, 12.0, 15.0, 10.0]
const MIXED := [[5400, 1, 0.9], [12600, 4, 0.1], [19800, 6, 0.9], [27000, 0, 0.1], [34200, 3, 0.9], [39600, 5, 0.92]]

var kind := "jumps"
var w := 128
var h := 90
var main_g := Vector2i(100, 70)  # green main source (radius 2), as Covington's
var main_o := Vector2i(28, 14)  # orange main source (radius 3), as Vei's
var forts: Array = []  # Vector2i cells, radius 1, each injecting green u and orange 1 - u
var villages: Array = []  # Vector2i cells


static func make(kind_in: String, crop := false) -> FieldScenario:
	var s := FieldScenario.new()
	s.kind = kind_in
	if kind_in == "mini":
		s.w = 40
		s.h = 30
		s.main_g = Vector2i(36, 26)
		s.main_o = Vector2i(3, 3)
		s.forts = [Vector2i(14, 12), Vector2i(26, 18), Vector2i(20, 8)]
		s.villages = [Vector2i(17, 14), Vector2i(23, 16), Vector2i(20, 12), Vector2i(29, 21)]
		return s
	s.forts = FORTS.duplicate()
	s.villages = VILLAGES.duplicate()
	if crop:
		s.w = 64
		s.h = 45
		s.main_g = Vector2i(62, 43)
		s.main_o = Vector2i(1, 1)
		s.forts = FORTS.map(func(c): return c - CROP)
		s.villages = VILLAGES.map(func(c): return c - CROP)
	return s


## The field config for this grid: realm.json's field block with w and h set.
func field_cfg(base: Dictionary) -> Dictionary:
	var c := base.duplicate(true)
	c["w"] = w
	c["h"] = h
	return c


func world_size() -> Vector2:
	return Vector2(w * CELL, h * CELL)


func pos_of(c: Vector2i) -> Vector2:
	return Vector2((c.x + 0.5) * CELL, (c.y + 0.5) * CELL)


## Each fort's green share u at time t (s).
func fort_u(t: float) -> Array:
	var u: Array = []
	match kind:
		"drift":
			for i in forts.size():
				var b := 0.0
				if DRIFT_FLIPS.has(i) and t >= float(DRIFT_FLIPS[i][0]):
					b = float(DRIFT_FLIPS[i][1])
				u.append(clampf(0.5 + 0.55 * sin(TAU * t / (DRIFT[i][0] * 3600.0) + DRIFT[i][1]) + b, 0.0, 1.0))
		"jumps":
			u = JUMPS_U0.duplicate()
			for ev in JUMPS:
				if t >= float(ev[0]):
					u[ev[1]] = float(ev[2])
		"mixed":
			var base: Array = MIXED_U0.duplicate()
			for ev in MIXED:
				if t >= float(ev[0]):
					base[ev[1]] = float(ev[2])
			for i in forts.size():
				u.append(clampf(base[i] + 0.1 * sin(TAU * t / (MIXED_PER[i] * 3600.0) + i), 0.0, 1.0))
		"mini":
			u = [0.85, 0.15, 0.5]
			if t >= 900.0:
				u[1] = 0.9
			if t >= 2100.0:
				u[0] = 0.1
	return u


## One live period's sources at time t, injected into f (as GameState._inject_sources(period)).
func inject(f: InfluenceField, t: float, period: float) -> void:
	var g := 4.8
	var o := 4.5
	if kind == "drift":
		g = 4.5 + 0.6 * sin(TAU * t / (11 * 3600.0))
		o = 4.5 + 0.6 * cos(TAU * t / (13 * 3600.0))
	elif kind == "mixed":
		g = 4.8 + 0.3 * sin(TAU * t / (13 * 3600.0))
		o = 4.5 + 0.3 * cos(TAU * t / (17 * 3600.0))
	f.inject(pos_of(main_g), true, g * period, 2)
	f.inject(pos_of(main_o), false, o * period, 3)
	var u := fort_u(t)
	for i in forts.size():
		if u[i] > 0.0:
			f.inject(pos_of(forts[i]), true, 1.1 * u[i] * period, 1)
		if 1.0 - u[i] > 0.0:
			f.inject(pos_of(forts[i]), false, 1.1 * (1.0 - u[i]) * period, 1)


## Dominance (green - orange) at each village, from the live arrays.
func doms(f: InfluenceField) -> Array:
	var d: Array = []
	for c in villages:
		var i: int = c.y * f.w + c.x
		d.append(float(f.green[i]) - float(f.orange[i]))
	return d


static func owners(d: Array, threshold: float) -> Array:
	return d.map(func(v): return 1 if v > threshold else (-1 if v < -threshold else 0))


## A fresh field on this grid, pre-warmed like GameState's (prewarm_ticks at prewarm_dt, flushed).
func prewarmed(cfg: Dictionary, ticks := 90, dt := 0.2) -> InfluenceField:
	var f := InfluenceField.new()
	f.setup(field_cfg(cfg), world_size())
	for i in ticks:
		inject(f, 0.0, dt)
		f.tick(dt)
	f.flush()
	return f
