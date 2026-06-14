class_name CreaturePreview
extends Control
## The thing on the slab. Draws the husk's SILHOUETTE (a real shape, so a stranger
## reads "an undead being made"), tinted toward its dominant aspect and fleshing
## in from a faint ghost to a solid body as remnants slot. The raid's rule still
## holds: one stat, one watchable verb (spikes/auras/motes/wisps) layered around
## the shape. reveal_boost is driven by hold-to-raise — watch it become itself.

var derived: Dictionary = {}
var _t := 0.0
var grow := 1.0          # raise overshoot (TRANS_BACK) — set by the crypt on Raise
var reveal_boost := 0.0  # hold-to-raise fleshing (0..1) — set by the crypt
var hold_progress := 0.0 # hold-to-raise ring closing around the creature (0..1)
var _tex_cache: Dictionary = {}

func set_build(d: Dictionary) -> void:
	derived = d
	queue_redraw()

func _process(delta: float) -> void:
	_t += delta
	queue_redraw()  # pulses/wisps/orbits animate

func _stat(s: String) -> float:
	return float((derived.get("stats", {}) as Dictionary).get(s, 0.0))

func _tex(form_id: String) -> Texture2D:
	if not _tex_cache.has(form_id):
		_tex_cache[form_id] = load("res://assets/icons/%s.svg" % form_id) as Texture2D
	return _tex_cache[form_id]

func _draw() -> void:
	var c := size * 0.5
	if String(derived.get("form_id", "")) == "":
		draw_arc(c, 54.0, 0, TAU, 48, Color(0.5, 0.5, 0.58, 0.25), 2.0)  # empty: waiting ring
		return

	var slab: Dictionary = ConfigDb.data["slab"]
	var beef := _stat("beef")
	var power := _stat("power")
	var speed := _stat("speed")
	var wits := _stat("wits")
	var charm := _stat("charm")
	var dread := _stat("dread")
	var magic := _stat("magic")
	var persist := _stat("persistence")

	# How "fleshed" the creature is: empty form = faint ghost, fully slotted = solid.
	var slot_count := int(derived.get("slot_count", 0))
	var fill_frac := float(derived.get("filled", 0)) / float(maxi(slot_count, 1))
	var dim := float(slab["silhouette_dim_alpha"])
	var reveal := clampf(maxf(dim + (1.0 - dim) * fill_frac, reveal_boost), 0.0, 1.0)

	# Size: silhouette grows with Beef, then the raise overshoot (grow) on top.
	var sz := float(slab["silhouette_size"]) * (1.0 + float(slab["silhouette_per_beef"]) * beef) * grow
	sz = minf(sz, float(slab["silhouette_size"]) * 1.9)
	var r := sz * 0.42   # nominal body radius for placing the stat verbs
	var pulse := 0.5 + 0.5 * sin(_t * 2.2)

	var body := Color(String(derived.get("color", "#cccccc")))
	var aspect_col: Variant = _dominant_aspect_color()
	if aspect_col != null:
		body = body.lerp(aspect_col, float(slab["preview_aspect_tint"]) * (0.4 + 0.6 * fill_frac))
	if wits > 0.0:
		body = body.lightened(clampf(wits * 0.04, 0.0, 0.35))  # the killer's clarity

	var tex := _tex(String(derived["form_id"]))
	var rect := Rect2(c - Vector2(sz, sz) * 0.5, Vector2(sz, sz))

	# Persistence — a faint after-image of the actual shape that refuses to die.
	if persist > 0.0 and tex != null:
		var pa := clampf(0.10 + 0.05 * persist, 0.0, 0.5) * reveal
		var off := Vector2(sin(_t * 1.3), cos(_t * 1.1)) * 9.0
		draw_texture_rect(tex, Rect2(rect.position + off, rect.size), false, Color(body.r, body.g, body.b, pa))

	# Dread — a cold pressure ring pushing outward (the field that repels).
	if dread > 0.0:
		var dr := r + 14.0 + 8.0 * pulse + dread * 2.0
		draw_arc(c, dr, 0, TAU, 48, Color(0.45, 0.5, 1.0, clampf(0.10 + 0.05 * dread, 0, 0.6)), 3.0)
		draw_arc(c, dr + 10.0, 0, TAU, 48, Color(0.4, 0.3, 0.7, clampf(0.06 + 0.03 * dread, 0, 0.4)), 2.0)

	# Charm — a warm inviting aura that pulls (the opposite field).
	if charm > 0.0:
		draw_circle(c, r + 10.0 + 6.0 * pulse, Color(1.0, 0.55, 0.8, clampf(0.05 + 0.03 * charm, 0, 0.4)))

	# Magic — an inner glow with orbiting motes (bolts waiting to fly).
	if magic > 0.0:
		draw_circle(c, r * 0.7, Color(0.5, 0.9, 1.0, clampf(0.06 + 0.04 * magic, 0, 0.5) * reveal))
		var motes := clampi(int(round(magic)), 1, 8)
		for i in motes:
			var ang := _t * 1.6 + TAU * i / float(motes)
			draw_circle(c + Vector2(cos(ang), sin(ang)) * (r + 16.0), 3.0, Color(0.6, 0.95, 1.0, 0.85))

	# The body itself — the husk silhouette, tinted and fleshed by the build.
	if tex != null:
		draw_texture_rect(tex, rect, false, Color(body.r, body.g, body.b, reveal))

	# Power — jagged spikes around the rim (the deletion stat, visibly sharp).
	if power > 0.0:
		var spikes := clampi(int(round(power)) + 4, 4, 16)
		var slen := 7.0 + power * 1.6
		for i in spikes:
			var ang := TAU * i / float(spikes) - PI / 2.0
			var d := Vector2(cos(ang), sin(ang))
			var base := c + d * r
			var tip := c + d * (r + slen)
			var perp := d.orthogonal() * (3.0 + power * 0.2)
			draw_colored_polygon(PackedVector2Array([base - perp, tip, base + perp]), Color(0.95, 0.35, 0.25, 0.9))

	# Speed — motion wisps trailing to one side (outruns everything).
	if speed > 0.0:
		var trails := clampi(int(round(speed * 0.6)) + 1, 1, 6)
		for i in trails:
			var off := -Vector2(1, 0) * (r + 6.0 + i * 7.0)
			var sway := sin(_t * 6.0 + i) * 5.0
			draw_arc(c + off + Vector2(0, sway), 9.0 - i, PI * 0.5, PI * 1.5, 12,
				Color(0.95, 0.9, 0.4, clampf(0.5 - i * 0.07, 0, 0.6)), 2.5)

	# Hold-to-raise — a bright ring closing around the creature as it forms.
	if hold_progress > 0.0 and hold_progress < 1.0:
		draw_arc(c, r + 22.0, -PI / 2.0, -PI / 2.0 + TAU * hold_progress, 64,
			Color(0.95, 0.9, 1.0, 0.9), 4.0)

	# Echo badges — small pips above the head, combat (orange) / town (green).
	var echoes: Dictionary = derived.get("echoes", {})
	if echoes.size() > 0:
		var combat_keys: Array = ConfigDb.data["echoes"]["combat"].keys()
		var bx := c.x - (echoes.size() - 1) * 7.0
		var i := 0
		for id in echoes:
			var col := Color(1.0, 0.6, 0.2) if id in combat_keys else Color(0.5, 0.9, 0.5)
			draw_circle(Vector2(bx + i * 14.0, c.y - r - 16.0), 5.0, col)
			i += 1

func _dominant_aspect_color() -> Variant:
	var sums := {
		"muscle": _stat("power") + _stat("beef"),
		"nerve": _stat("speed") + _stat("wits"),
		"presence": _stat("charm") + _stat("dread"),
		"anima": _stat("magic") + _stat("persistence"),
	}
	var best := ""
	var best_v := 0.0
	for a in sums:
		if sums[a] > best_v:
			best_v = sums[a]
			best = a
	if best == "":
		return null
	return Color(String(ConfigDb.data["slab"]["aspect_colors"][best]))
