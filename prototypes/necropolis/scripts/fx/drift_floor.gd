class_name DriftFloor
extends Node2D
## The shared drift floor (VISUAL-LANGUAGE law 1): "The ground is near-black
## and alive." A slow current of faint streaks along a direction field the
## scene provides. Town: the street grid's slow current. Dungeon: the room
## floor's drift toward the exits. See docs/VISUAL-TOOLKIT.md, "DriftFloor".
##
##   var floor := DriftFloor.new()
##   add_child(floor)                    # first child of the world, under everything
##   floor.setup(Rect2(Vector2.ZERO, room_size), func(p: Vector2) -> Vector2:
##       return (exit_pos - p).normalized(), slab_pos, "town")
##   floor.set_source(relish.position)   # dungeon: each frame, Relish is the source
##
## The field is a Callable (local position -> drift vector; length is strength,
## 0..1, and 0 means no streaks there), an Image (FORMAT_RGF/RGH over the rect)
## or a Vector2 (one drift everywhere). A Callable is baked once to a small
## texture; call set_field() again when the scene's field changes, never per frame.
##
## Colour from Palette (a tint key, never dead), tempo and reduced motion from
## Pulse, tuning from configs/ground.json "drift_floor". GPU particles: one
## GPUParticles2D, no SubViewport, no per-frame GDScript beyond a few uniforms.

const SHADER := preload("res://shaders/drift_floor.gdshader")
const TEX_SIZE := Vector2i(64, 8)
const FALLBACK_TINT := "contour"

var rect := Rect2()
var source := Vector2.ZERO
var tint_key := ""

var _cfg := {}
var _parts: GPUParticles2D
var _mat: ShaderMaterial
var _field_tex: ImageTexture
var _reduced_applied := false
var _pulse: Node


## Build the floor. `field`: Callable, Image or Vector2 (see the header).
## `src`: where the exhale starts (law 5: town = the slab, dungeon = Relish).
## `tint`: a Palette key; "" uses the config's default.
func setup(r: Rect2, field: Variant, src := Vector2.INF, tint := "") -> void:
	rect = r
	source = src if src != Vector2.INF else r.get_center()
	if _cfg.is_empty():
		configure(_load_cfg())
	_pulse = _autoload("Pulse")
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_parts = GPUParticles2D.new()
	_parts.name = "DriftStreaks"
	_parts.amount = streak_count(rect, _cfg)
	_parts.lifetime = 3600.0         # particles respawn themselves in the shader
	_parts.explosiveness = 1.0
	_parts.fixed_fps = 0
	_parts.interpolate = false
	_parts.local_coords = true       # the rect is in this node's space
	_parts.visibility_rect = rect.grow(float(_cfg.get("length_px", 28.0)) * 2.0)
	_parts.texture = ImageTexture.create_from_image(comet_image(TEX_SIZE, float(_cfg.get("head_frac", 0.22)),
		float(_cfg.get("head_power", 2.0))))
	var cm := CanvasItemMaterial.new()
	cm.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_parts.material = cm
	_parts.process_material = _mat
	add_child(_parts)
	set_field(field)
	set_tint(tint if tint != "" else str(_cfg.get("tint", FALLBACK_TINT)))
	_apply_config()
	_sync(true)


## Rebake the drift field (a Callable, Image or Vector2).
func set_field(field: Variant) -> void:
	var img: Image
	if field is Image:
		img = (field as Image).duplicate()
		if img.get_format() != Image.FORMAT_RGH:
			img.convert(Image.FORMAT_RGH)
	elif field is Callable:
		img = bake_field(field, rect, float(_cfg.get("cell_px", 32.0)), int(_cfg.get("max_cells", 128)))
	elif field is Vector2:
		img = bake_field(func(_p: Vector2) -> Vector2: return field, rect, rect.size.x + rect.size.y, 2)
	else:
		push_error("DriftFloor.set_field: expected Callable, Image or Vector2, got %s" % type_string(typeof(field)))
		return
	if _field_tex == null or _field_tex.get_size() != Vector2(img.get_size()):
		_field_tex = ImageTexture.create_from_image(img)
	else:
		_field_tex.update(img)
	_mat.set_shader_parameter("field", _field_tex)


## Move the exhale's origin (e.g. Relish in a dungeon). Cheap: one uniform.
func set_source(pos: Vector2) -> void:
	source = pos
	if _mat != null:
		_mat.set_shader_parameter("source", source)


## Tint from a Palette key. Dead keys are refused: dead matter never emits light.
func set_tint(key: String) -> void:
	var col := Palette.c(key)
	if LineGlow.is_dead(col):
		push_error("DriftFloor: '%s' is dead matter, which never glows; using '%s'" % [key, FALLBACK_TINT])
		key = FALLBACK_TINT
		col = Palette.c(key)
	tint_key = key
	# Faint by being sparse, not dim (law 14): the head is lifted until it
	# clears `head_contrast` against the ground, whatever the tint.
	var target := float(_cfg.get("head_contrast", 3.2))
	_mat.set_shader_parameter("tint", lift_to_contrast(col, Palette.c("ground"), target))


## Tuning (configs/ground.json "drift_floor"). Call before setup() to override,
## or after it to retune live (streak count changes need a new setup()).
func configure(cfg: Dictionary) -> void:
	_cfg = cfg
	if _mat != null:
		_apply_config()


func streaks() -> int:
	return _parts.amount if _parts != null else 0


func _ready() -> void:
	if _pulse == null and _mat != null:
		_pulse = _autoload("Pulse")
		_sync(true)


func _process(_delta: float) -> void:
	if _mat != null:
		_sync(false)


func _sync(force: bool) -> void:
	if _pulse == null:
		return
	var reduced: bool = _pulse.get("reduced_motion")
	if force or reduced != _reduced_applied:
		_reduced_applied = reduced
		_apply_config()
	_mat.set_shader_parameter("beat", _pulse.call("phase", 0.0))


func _apply_config() -> void:
	var reduced := _reduced_applied
	for k in ["alpha", "speed", "length_px", "width_px", "min_strength", "exhale_speed", "exhale_length"]:
		if _cfg.has(k):
			_mat.set_shader_parameter(k, float(_cfg[k]))
	_mat.set_shader_parameter("life_s", _v2(_cfg.get("life_s", [4.0, 9.0])))
	_mat.set_shader_parameter("tex_size", Vector2(TEX_SIZE))
	_mat.set_shader_parameter("rect", Vector4(rect.position.x, rect.position.y, rect.size.x, rect.size.y))
	_mat.set_shader_parameter("source", source)
	_mat.set_shader_parameter("reach", reach(rect, source))
	_mat.set_shader_parameter("wave_spread", float(_pulse.get("wave_spread")) if _pulse != null else 0.5)
	# reduced motion (law 13): the same field held still. Comet marks keep the
	# direction; no exhale, so no frozen brightness bands either.
	_mat.set_shader_parameter("motion", 0.0 if reduced else 1.0)
	if reduced:
		_mat.set_shader_parameter("exhale_speed", 0.0)
		_mat.set_shader_parameter("exhale_length", 0.0)


# --- pure helpers (headless-tested in tests/test_ground.gd) -------------------

## `col` scaled up (hue kept, channels clamped) until its WCAG contrast
## against `ground` reaches `target`; unchanged if it already does.
static func lift_to_contrast(col: Color, ground: Color, target: float) -> Color:
	var c := Color(col, 1.0)
	var k := 1.0
	while contrast(c, ground) < target and k < 16.0:
		k *= 1.05
		c = Color(minf(col.r * k, 1.0), minf(col.g * k, 1.0), minf(col.b * k, 1.0))
	return c


## WCAG 2 contrast ratio between two colours (alpha ignored).
static func contrast(a: Color, b: Color) -> float:
	var la := _rel_lum(a)
	var lb := _rel_lum(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)


static func _rel_lum(c: Color) -> float:
	var f := func(v: float) -> float:
		return v / 12.92 if v <= 0.04045 else pow((v + 0.055) / 1.055, 2.4)
	return 0.2126 * f.call(c.r) + 0.7152 * f.call(c.g) + 0.0722 * f.call(c.b)


## Streak count for a floor: `density` per 100×100 px, clamped to [1, max_streaks].
static func streak_count(r: Rect2, cfg: Dictionary) -> int:
	var n := roundi(r.get_area() / 10000.0 * float(cfg.get("density", 1.5)))
	return clampi(n, 1, int(cfg.get("max_streaks", 4000)))


## Distance from the source to the rect's farthest corner: the lag reaches
## Pulse.wave_spread there, so the farthest streak never lands back in phase.
static func reach(r: Rect2, src: Vector2) -> float:
	var far := 0.0
	for c in [r.position, r.position + Vector2(r.size.x, 0), r.position + Vector2(0, r.size.y), r.end]:
		far = maxf(far, src.distance_to(c))
	return maxf(1.0, far)


## Sample `fn(local_pos) -> Vector2` at the centre of each cell over `r`.
## The grid is cell_px cells, capped at max_cells per side. Returns FORMAT_RGH.
static func bake_field(fn: Callable, r: Rect2, cell_px: float, max_cells: int) -> Image:
	var w := clampi(ceili(r.size.x / maxf(1.0, cell_px)), 2, maxi(2, max_cells))
	var h := clampi(ceili(r.size.y / maxf(1.0, cell_px)), 2, maxi(2, max_cells))
	var data := PackedFloat32Array()
	data.resize(w * h * 2)
	var cell := Vector2(r.size.x / w, r.size.y / h)
	for y in h:
		for x in w:
			var v: Vector2 = fn.call(r.position + Vector2((x + 0.5) * cell.x, (y + 0.5) * cell.y))
			var i := (y * w + x) * 2
			data[i] = v.x
			data[i + 1] = v.y
	var img := Image.create_from_data(w, h, false, Image.FORMAT_RGF, data.to_byte_array())
	img.convert(Image.FORMAT_RGH)    # half float: filterable on GLES3 / WebGL2
	return img


## The streak sprite: white; a solid head (the last `head_frac` of the length,
## the mark's line core) and a tail fading behind it on a power curve; soft
## across y. Modulated by the particle colour, drawn additive.
static func comet_image(size: Vector2i, head_frac: float, head_power: float) -> Image:
	var img := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	for y in size.y:
		var across := 1.0 - absf((y + 0.5) / size.y * 2.0 - 1.0)
		across = smoothstep(0.0, 0.35, across)
		for x in size.x:
			var u := (x + 0.5) / size.x
			var along := 1.0 if u >= 1.0 - head_frac else pow(u / maxf(1e-3, 1.0 - head_frac), head_power)
			img.set_pixel(x, y, Color(1, 1, 1, along * across))
	return img


## Autoloads by name from the tree root (works before this node is added, and
## returns null under the headless test runner, where autoloads don't exist).
static func _autoload(name: String) -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(name) if tree != null and tree.root != null else null


func _load_cfg() -> Dictionary:
	var db := _autoload("ConfigDb")
	if db != null:
		return ((db.get("data") as Dictionary).get("ground", {}) as Dictionary).get("drift_floor", {})
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://configs/ground.json"))
	return (parsed as Dictionary).get("drift_floor", {}) if parsed is Dictionary else {}


static func _v2(a) -> Vector2:
	if a is Array and a.size() >= 2:
		return Vector2(float(a[0]), float(a[1]))
	return Vector2.ZERO
