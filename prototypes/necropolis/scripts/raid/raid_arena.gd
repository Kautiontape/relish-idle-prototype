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
var rng: RandomNumberGenerator = null   # the raid's rng_combat (set by raid.gd)
var relish: Node2D = null   # pulse source for the wall wave and the floor

var _grid := {}
var _built := false
var _walls: Array = []
var _floor: DriftFloor = null
var _dim: TranceDim = null
var _marks: ExitMarks = null
var _drift := 0.0           # wall colour drift position, in cycles
var _drift_speed := 0.05
var _diag := 1000.0
var _flash_t := 0.0         # seconds of wall flash left (the held clear's set piece)
var _flash_dur := 1.0
var _flash_col: Color = Palette.c("text")
var _flash_boost := 1.5


## The overlay that dims the line layers while the trance is active.
class TranceDim:
	extends Node2D
	var size := Vector2.ZERO
	var col: Color

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size).grow(80.0), col)


## Exit doors (VISUAL-LANGUAGE 2c: gaps with a glow lip): a relish lip on each jamb and a ring
## sigil at the door's inner point, dim until that checkpoint has banked, then lit.
class ExitMarks:
	extends Node2D
	var doors: Array = []
	var wall_t := 30.0
	var lip_len := 34.0
	var lip_w := 3.0
	var sigil_r := 14.0
	var dim_alpha := 0.3
	var banked := {}

	func _process(_d: float) -> void:
		queue_redraw()

	func _draw() -> void:
		var violet := Palette.c("relish")
		for d in doors:
			var inward := Vector2.ZERO
			var along := Vector2(1, 0)
			match str(d["side"]):
				"s": inward = Vector2(0, -1)
				"n": inward = Vector2(0, 1)
				"w": inward = Vector2(1, 0)
				_: inward = Vector2(-1, 0)
			if inward.x != 0.0:
				along = Vector2(0, 1)
			var r: Rect2 = d["rect"]
			var half_w := (r.size.x if along.x != 0.0 else r.size.y) * 0.5
			var c: Vector2 = d["center"]
			var a: Vector2 = c - inward * wall_t * 0.5
			var b: Vector2 = c + inward * (wall_t * 0.5 + lip_len)
			for sgn in [-1.0, 1.0]:
				var off: Vector2 = along * half_w * sgn
				LineGlow.polyline(self, PackedVector2Array([a + off, b + off]), violet, lip_w, 0.8)
			var lit := bool(banked.get(int(d.get("room", -1)), false))
			var p: Vector2 = d["inner"]
			if lit:
				var beat := 0.7 + 0.3 * Pulse.wave()
				LineGlow.ring(self, p, sigil_r, violet, 2.0, beat, Palette.c("text", 0.6))
				draw_circle(p, 3.0, Palette.c("text", 0.9))
			else:
				LineGlow.matte_ring(self, p, sigil_r, Palette.c("relish", dim_alpha), 1.5)


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
	var heat := float(lcfg.get("boss_wall_heat", 0.6)) if bool(layout.get("boss", false)) else 0.0
	var look := {
		"color_a": Palette.c("relish"),
		"color_b": Palette.c(controller_key),
		"heat": heat,
		"wavelength": float(lcfg.get("wall_wavelength_px", 1100.0)),
		"arena_diag": _diag,
		"stroke_half": float(lcfg.get("wall_stroke_px", 3.0)) * 0.5,
		"halo_px": float(lcfg.get("wall_halo_px", 9.0)),
		"intensity": float(lcfg.get("wall_intensity", 0.7)),
		"wave_spread": Pulse.wave_spread,
		"wave_decay": Pulse.wave_decay,
	}
	if bool(layout.get("boss", false)):
		# Vei's arena: a thicker, brighter stroke (the camera is zoomed out here)
		look["stroke_half"] = float(lcfg.get("boss_wall_stroke_px", 6.0)) * 0.5
		look["intensity"] = float(lcfg.get("boss_wall_intensity", 0.9))
	# the warden room's walls run hotter (VISUAL-LANGUAGE 2c)
	var wr := int(layout.get("warden_room", -1))
	var hot := look.duplicate()
	hot["heat"] = float(lcfg.get("boss_wall_heat", 0.6))
	# collinear flush rects (closed doors, sealed gaps and their neighbours) become one segment,
	# so the shader's end fade only draws jambs at real door gaps; hot and cold merge apart
	var hot_rects: Array = []
	var cold_rects: Array = []
	for wrect in layout["walls"]:
		if wr >= 0 and LayoutLogic.wall_touches_room(wrect, layout["rooms"][wr]):
			hot_rects.append(wrect)
		else:
			cold_rects.append(wrect)
	for is_hot in [false, true]:
		for wrect in LayoutLogic.merge_walls(hot_rects if is_hot else cold_rects):
			var seg := RaidWall.new()
			add_child(seg)
			seg.setup(wrect, hot if is_hot else look)
			_walls.append(seg)

	# --- exit doors (the dungeon only; the boss arena has none) ---
	if not bool(layout.get("boss", false)):
		var ex: Dictionary = cfg.get("exits", {})
		_marks = ExitMarks.new()
		_marks.z_index = 21
		_marks.doors = layout["doors"]
		_marks.wall_t = float(layout["wall_t"])
		_marks.lip_len = float(ex.get("lip_len_px", 34.0))
		_marks.lip_w = float(ex.get("lip_width", 3.0))
		_marks.sigil_r = float(ex.get("sigil_radius_px", 14.0))
		_marks.dim_alpha = float(ex.get("dim_alpha", 0.3))
		add_child(_marks)

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


## Checkpoint rooms that have banked (lights their exit sigils).
func set_banked(rooms: Dictionary) -> void:
	if _marks != null:
		_marks.banked = rooms.duplicate()


## The walls flash toward `key`'s palette colour and fade back over `secs` (reduced motion: a steady
## hold, then off, no fade).
func flash_walls(key: String, secs: float, boost: float) -> void:
	_flash_col = Palette.c(key)
	_flash_dur = maxf(0.05, secs)
	_flash_t = _flash_dur
	_flash_boost = boost


func _flash_step(delta: float) -> void:
	if _flash_t <= 0.0:
		return
	_flash_t = maxf(0.0, _flash_t - delta / maxf(0.05, Engine.time_scale))
	var f := _flash_t / _flash_dur
	var k := (1.0 if f > 0.0 else 0.0) if Pulse.reduced_motion else f * f
	for seg in _walls:
		seg.set_flash(k, _flash_col, _flash_boost)


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
	if _floor != null and relish != null and is_instance_valid(relish):
		_floor.set_source(_floor.to_local(rp))
	for seg in _walls:
		seg.set_beat(beat, rp, _drift, steady)
	_flash_step(delta)


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
	# ground well beyond the arena, so a small arena never shows the clear colour
	draw_rect(Rect2(Vector2.ZERO, size).grow(4000.0), Palette.c("ground"))
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
					out += Vector2(rng.randf() - 0.5, rng.randf() - 0.5) if rng != null else Vector2(0.5, 0.0)
	return out


## Keep a point inside the arena and out of internal walls (slide-friendly).
func resolve_walls(p: Vector2, r: float) -> Vector2:
	return LayoutLogic.resolve_walls(layout, p, r)
