extends Sprite2D
## Renders Game.field (the necrosis influence grid) to a texture at ~6 Hz.
## Green = undead pressure, orange = living pressure, entrenchment brightens
## toward the faction core color, contested fronts flash danger-pink.

const GREEN_BASE := Color("103a28")
const GREEN_HOT := Color("39ff9e")
const GREEN_CORE := Color("c9ffe8")
const ORANGE_BASE := Color("3a1608")
const ORANGE_HOT := Color("ff6a2b")
const ORANGE_CORE := Color("ffd6b0")
const FRONT := Color("ff2d55")

var _img: Image
var _tex: ImageTexture
var _acc := 1.0


func _ready() -> void:
	var f: InfluenceField = Game.field
	_img = Image.create(f.w, f.h, false, Image.FORMAT_RGBA8)
	_tex = ImageTexture.create_from_image(_img)
	texture = _tex
	centered = false
	scale = Vector2(f.world_size.x / f.w, f.world_size.y / f.h)
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/map_field.gdshader")
	material = mat


func _process(delta: float) -> void:
	_acc += delta
	if _acc < 0.16:
		return
	_acc = 0.0
	var f: InfluenceField = Game.field
	var bytes := PackedByteArray()
	bytes.resize(f.w * f.h * 4)
	for i in f.w * f.h:
		var g := f.green[i]
		var o := f.orange[i]
		var e := f.entrench[i]
		var col := Color(0, 0, 0, 0)
		if g > 0.03 or o > 0.03:
			if g >= o:
				var heat := clampf(g * 0.75, 0.0, 1.0)
				col = GREEN_BASE.lerp(GREEN_HOT, heat)
				if e > 0.2:
					col = col.lerp(GREEN_CORE, clampf(e * 0.28, 0.0, 0.5))
				col.a = clampf(g * 0.55, 0.0, 0.8)
			else:
				var heat2 := clampf(o * 0.75, 0.0, 1.0)
				col = ORANGE_BASE.lerp(ORANGE_HOT, heat2)
				if e < -0.2:
					col = col.lerp(ORANGE_CORE, clampf(-e * 0.28, 0.0, 0.5))
				col.a = clampf(o * 0.55, 0.0, 0.8)
			if minf(g, o) > 0.1:
				col = col.lerp(FRONT, 0.3)
				col.a = maxf(col.a, 0.45)
		var j := i * 4
		bytes[j] = int(col.r * 255.0)
		bytes[j + 1] = int(col.g * 255.0)
		bytes[j + 2] = int(col.b * 255.0)
		bytes[j + 3] = int(col.a * 255.0)
	_img.set_data(f.w, f.h, false, Image.FORMAT_RGBA8, bytes)
	_tex.update(_img)
