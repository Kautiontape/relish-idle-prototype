extends Node2D
## The town view's top per-frame layer, awake only while it has something to show:
##   floats  cause and effect: when a building's output moves (TownModel.floats), a signed oblique
##           rate ("+0.30 gold/s") rises from the building for one beat, beside a pip in the
##           output's matter (an undead ring, a living diamond, a matte dead square), its text in
##           that matter's colour (dead falls back to `text`). Reduced motion: it holds still,
##           whole, for the beat.
##   pick    the agent the player clicked: a thin `select` ring around it and a tag beside it
##           that follows it, saying what it is doing (TownAgents.describe). It clears itself
##           when the agent leaves the population.
## Tuning: configs/town.json `view` (float, pick).

var model: TownModel
var agents: TownAgents
var vcfg: Dictionary = {}
## The picked agent, or null.
var pick: TownAgents.Agent = null

var _floats: Array = []  # {lot_id, text, ink, text_key, t}


func _ready() -> void:
	set_process(false)


## Adds TownModel.floats (one update's output changes); each lives one beat from now.
func add_floats(fl: Array) -> void:
	for f in fl:
		var e: Dictionary = f.duplicate()
		e["t"] = 0.0
		_floats.append(e)
	_wake()


## Picks agent `a` (null clears).
func set_pick(a: TownAgents.Agent) -> void:
	pick = a
	_wake()
	queue_redraw()


func _wake() -> void:
	set_process(pick != null or not _floats.is_empty())


func _process(delta: float) -> void:
	var beat := maxf(Pulse.tempo_ms / 1000.0, 0.001)
	for f in _floats:
		f["t"] += delta
	_floats = _floats.filter(func(f): return f["t"] < beat)
	if pick != null and (agents == null or not agents.alive(pick)):
		pick = null
	_wake()
	queue_redraw()


func _draw() -> void:
	if model == null:
		return
	_draw_floats()
	_draw_pick()


# ------------------------------------------------------------------ floats ----
func _draw_floats() -> void:
	var fc: Dictionary = vcfg.get("float", {})
	var beat := maxf(Pulse.tempo_ms / 1000.0, 0.001)
	var font := TownUI.oblique_font()
	var fs := maxi(int(fc.get("px", TownUI.MIN_TEXT)), TownUI.MIN_TEXT)
	var ps := float(fc.get("pip_px", 6.0))
	var outline := int(fc.get("outline_px", 0))
	for f in _floats:
		var l := model.lot(String(f["lot_id"]))
		if l.is_empty() or (l["building"] as Dictionary).is_empty():
			continue
		var r: Rect2 = l["building"]["rect"]
		var x := clampf(float(f["t"]) / beat, 0.0, 1.0)
		var rise := 0.0 if Pulse.reduced_motion else x * float(fc.get("rise_px", 0.0)) * model.scale
		var alpha := 1.0 if Pulse.reduced_motion else clampf((1.0 - x) * 2.0, 0.0, 1.0)
		var text := String(f["text"])
		var sz := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		var w := ps + 4.0 + sz.x
		var base := Vector2(r.get_center().x - w * 0.5, r.position.y - 4.0 - rise)
		var pc := base + Vector2(ps * 0.5, -(font.get_ascent(fs) - font.get_descent(fs)) * 0.5)
		_pip(pc, ps, String(f["ink"]), alpha)
		var tp := base + Vector2(ps + 4.0, 0.0)
		if outline > 0:
			draw_string_outline(font, tp, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, outline, Palette.c("ground", alpha))
		draw_string(font, tp, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Palette.c(String(f["text_key"]), alpha))


## A float's matter pip: undead a ring, living a diamond, dead a matte square (no glow).
func _pip(c: Vector2, s: float, ink: String, alpha: float) -> void:
	var h := s * 0.5
	if ink == "dead" or ink == "dead_lit":
		draw_rect(Rect2(c - Vector2(h, h), Vector2(s, s)), Palette.c(ink, alpha))
	elif ink == "living":
		var d := PackedVector2Array([c + Vector2(0, -h), c + Vector2(h, 0), c + Vector2(0, h), c + Vector2(-h, 0), c + Vector2(0, -h)])
		LineGlow.polyline(self, d, Palette.c(ink, alpha), float(vcfg.get("pip_w_px", 1.0)), float(vcfg.get("pip_glow", 0.5)))
	elif Palette.has(ink):
		LineGlow.ring(self, c, h * 0.8, Palette.c(ink, alpha), float(vcfg.get("pip_w_px", 1.0)), float(vcfg.get("pip_glow", 0.5)))


# -------------------------------------------------------------------- pick ----
func _draw_pick() -> void:
	if pick == null or agents == null:
		return
	var pc: Dictionary = vcfg.get("pick", {})
	var r := float(pc.get("ring_px", 10.0)) * model.scale
	draw_arc(pick.pos, r, 0.0, TAU, 32, Palette.c("select"), float(pc.get("w_px", 1.0)))
	var text := agents.describe(pick)
	if text == "":
		return
	var font := ThemeDB.fallback_font
	var fs := maxi(int(pc.get("px", TownUI.MIN_TEXT)), TownUI.MIN_TEXT)
	var pad := float(pc.get("pad_px", 4.0))
	var sz := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	var plate := Rect2(Vector2.ZERO, Vector2(sz.x + pad * 2.0, sz.y + pad))
	var host: Vector2 = (get_parent() as Control).size if get_parent() is Control else Vector2(1e6, 1e6)
	var p := pick.pos + Vector2(r + float(pc.get("gap_px", 6.0)), -plate.size.y * 0.5)
	if p.x + plate.size.x > host.x - 4.0:  # no room on the right: beside it on the left
		p.x = pick.pos.x - r - float(pc.get("gap_px", 6.0)) - plate.size.x
	p.x = clampf(p.x, 4.0, maxf(host.x - plate.size.x - 4.0, 4.0))
	p.y = clampf(p.y, 4.0, maxf(host.y - plate.size.y - 4.0, 4.0))
	plate.position = p
	draw_rect(plate, Palette.c("ground"))
	draw_rect(plate, Palette.c("select"), false, 1.0)
	draw_string(font, p + Vector2(pad, (plate.size.y + font.get_ascent(fs) - font.get_descent(fs)) * 0.5), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Palette.c("text"))
