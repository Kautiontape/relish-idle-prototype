class_name RaidArena
extends Node2D
## The raid floor: layout geometry, wall segments, floor drawing, the spatial
## grid used for unit separation, and wall collision. Add it as a child of the
## raid BEFORE the units root so the floor draws under walls, units and fx.

const GROUND := Color("#0d0d14")
const GRID_LINE := Color(0.24, 0.24, 0.34, 0.16)

const SPATIAL_CELL := 56.0

var layout := {}
var cfg := {}

var _grid := {}
var _built := false


func build(p_layout: Dictionary, p_cfg: Dictionary) -> void:
	layout = p_layout
	cfg = p_cfg
	# --- walls (the showpiece) ---
	var glow: float = float(cfg.get("layout", {}).get("wall_glow_px", 26.0))
	for wrect in layout["walls"]:
		var seg := RaidWall.new()
		add_child(seg)
		seg.setup(wrect, glow)
	_built = true
	queue_redraw()


func _process(_delta: float) -> void:
	if not _built:
		return
	queue_redraw()  # floor grid is static, but cheap; keeps draw order simple


func _draw() -> void:
	if layout.is_empty():
		return
	var size: Vector2 = layout["size"]
	draw_rect(Rect2(Vector2.ZERO, size), GROUND)
	var step: float = float(cfg.get("layout", {}).get("grid_step_px", 128.0))
	var x := step
	while x < size.x:
		draw_line(Vector2(x, 0), Vector2(x, size.y), GRID_LINE, 1.0)
		x += step
	var y := step
	while y < size.y:
		draw_line(Vector2(0, y), Vector2(size.x, y), GRID_LINE, 1.0)
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
