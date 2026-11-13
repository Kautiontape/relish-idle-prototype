class_name RaidArena
extends Node2D
## The raid floor: layout geometry, wall segments, floor drawing, the spatial
## grid used for unit separation, and wall collision. Add it as a child of the
## raid BEFORE the units root so the floor draws under walls, units and fx.
##
## Layers (z_index): floor 0, piles 12, walls 20, units 30-34, trance dim 36,
## Relish 38, essence 60, trace 70, fx 72+. The trance dim sits between the
## dimmed line layers and the things that stay full (Relish, essence, trace).

const SPATIAL_CELL := 56.0
const DIM_Z := 36

var layout := {}
var cfg := {}
var relish: Node2D = null   # pulse source for the wall wave and the floor

var _grid := {}
var _built := false
var _walls: Array = []
var _floor: DriftFloor = null
var _dim: TranceDim = null
var _drift := 0.0           # wall colour drift position, in cycles
var _drift_speed := 0.05
var _diag := 1000.0


## The overlay that dims the line layers while the trance is active.
class TranceDim:
	extends Node2D
	var size := Vector2.ZERO
	var col: Color

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size).grow(80.0), col)


## `controller_key`: Palette key of the fortress's controller colour.
func build(p_layout: Dictionary, p_cfg: Dictionary, controller_key := "living") -> void:
	layout = p_layout
	cfg = p_cfg
	var size: Vector2 = layout["size"]
	var lcfg: Dictionary = cfg.get("layout", {})
	_diag = size.length()
	_drift_speed = float(lcfg.get("wall_drift_speed", 0.05))

	# --- the live floor: drifts toward the exits, under everything ---
	_floor = DriftFloor.new()
	add_child(_floor)
	_floor.setup(Rect2(Vector2.ZERO, size), _floor_field, layout["spawn"],
		str(cfg.get("floor", {}).get("tint", "contour")))

	# --- walls (the showpiece) ---
	var glow: float = float(lcfg.get("wall_glow_px", 26.0))
	var heat := float(lcfg.get("boss_wall_heat", 0.6)) if bool(layout.get("boss", false)) else 0.0
	var look := {
		"color_a": Palette.c("relish"),
		"color_b": Palette.c(controller_key),
		"heat": heat,
		"wavelength": float(lcfg.get("wall_wavelength_px", 1100.0)),
		"arena_diag": _diag,
		"wave_spread": Pulse.wave_spread,
		"wave_decay": Pulse.wave_decay,
	}
	for wrect in layout["walls"]:
		var seg := RaidWall.new()
		add_child(seg)
		seg.setup(wrect, glow, look)
		_walls.append(seg)

	# --- trance dim overlay (hidden until the trance starts) ---
	_dim = TranceDim.new()
	_dim.size = size
	_dim.col = Palette.c("ground", 1.0 - float(cfg.get("trance", {}).get("line_dim_to", 0.4)))
	_dim.z_index = DIM_Z
	_dim.visible = false
	add_child(_dim)

	_built = true
	queue_redraw()


## Bind Relish: the dungeon's pulse source (the floor and the wall wave).
func bind_relish(r: Node2D) -> void:
	relish = r


func set_trance_dim(on: bool) -> void:
	if _dim != null:
		_dim.visible = on


func _process(delta: float) -> void:
	if not _built:
		return
	var reduced: bool = Pulse.reduced_motion
	if not reduced:
		_drift += delta * _drift_speed   # frozen under reduced motion
	var steady: float = Pulse.wave() if reduced else -1.0
	var beat: float = Pulse.phase()
	var rp := relish.global_position if relish != null and is_instance_valid(relish) else Vector2.ZERO
	for seg in _walls:
		seg.set_beat(beat, rp, _drift, steady)


func _physics_process(_delta: float) -> void:
	if _floor != null and relish != null and is_instance_valid(relish):
		_floor.set_source(relish.position)


## Drift field: unit vector toward the nearest door's inner point, strength 1
## on open floor and 0 inside walls (inner walls and the perimeter band).
func _floor_field(p: Vector2) -> Vector2:
	var size: Vector2 = layout["size"]
	var t: float = layout["wall_t"]
	if p.x < t or p.y < t or p.x > size.x - t or p.y > size.y - t:
		return Vector2.ZERO
	for wrect in layout["inner_walls"]:
		if (wrect as Rect2).has_point(p):
			return Vector2.ZERO
	var best := Vector2.ZERO
	var bd := INF
	for d in layout["doors"]:
		var to: Vector2 = d["inner"] - p
		var l := to.length()
		if l < bd:
			bd = l
			best = to
	return best.normalized()


func _draw() -> void:
	if layout.is_empty():
		return
	var size: Vector2 = layout["size"]
	draw_rect(Rect2(Vector2.ZERO, size), Palette.c("ground"))
	var grid := Palette.c("graticule")
	var step: float = float(cfg.get("layout", {}).get("grid_step_px", 128.0))
	var x := step
	while x < size.x:
		draw_line(Vector2(x, 0), Vector2(x, size.y), grid, 1.0)
		x += step
	var y := step
	while y < size.y:
		draw_line(Vector2(0, y), Vector2(size.x, y), grid, 1.0)
		y += step


# --------------------------------------------------------------- spatial -----
func rebuild_grid(allies: Array, enemies: Array, relish) -> void:
	_grid.clear()
	for u in allies:
		_grid_put(u)
	for u in enemies:
		_grid_put(u)
	if relish != null and relish.alive:
		_grid_put(relish)


func _grid_put(u: Node2D) -> void:
	var k := Vector2i(int(u.position.x / SPATIAL_CELL), int(u.position.y / SPATIAL_CELL))
	if not _grid.has(k):
		_grid[k] = []
	_grid[k].append(u)


func separation_push(u: Node2D) -> Vector2:
	var sep: float = float(cfg.get("combat", {}).get("separation_px", 26.0))
	var out := Vector2.ZERO
	var c := Vector2i(int(u.position.x / SPATIAL_CELL), int(u.position.y / SPATIAL_CELL))
	for dy in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			var k := Vector2i(c.x + dx, c.y + dy)
			if not _grid.has(k):
				continue
			for o in _grid[k]:
				if o == u or not is_instance_valid(o):
					continue
				var d: Vector2 = u.position - o.position
				var l := d.length()
				if l < sep and l > 0.01:
					out += d / l * (1.0 - l / sep)
				elif l <= 0.01:
					out += Vector2(randf() - 0.5, randf() - 0.5)
	return out


## Keep a point inside the arena and out of internal walls (slide-friendly).
func resolve_walls(p: Vector2, r: float) -> Vector2:
	var size: Vector2 = layout["size"]
	var t: float = layout["wall_t"]
	p.x = clampf(p.x, t + r, size.x - t - r)
	p.y = clampf(p.y, t + r, size.y - t - r)
	for pass_i in 2:
		for wrect in layout["inner_walls"]:
			var g: Rect2 = (wrect as Rect2).grow(r)
			if not g.has_point(p):
				continue
			var left := p.x - g.position.x
			var right := g.end.x - p.x
			var top := p.y - g.position.y
			var bottom := g.end.y - p.y
			var m := minf(minf(left, right), minf(top, bottom))
			if m == left:
				p.x = g.position.x
			elif m == right:
				p.x = g.end.x
			elif m == top:
				p.y = g.position.y
			else:
				p.y = g.end.y
	return p
