class_name CreaturePreview
extends Control
## The thing on the slab. Reads a build's derived stats and draws a creature
## that visibly BECOMES itself as remnants slot — one stat, one watchable verb
## (the same rule the raid's units obey). This is the whole point of the test:
## numbers going up should read as an identity, not a spreadsheet.

var derived: Dictionary = {}
var _t := 0.0
var grow := 1.0   # raise overshoot (TRANS_BACK) — set by the crypt on "Raise"

func set_build(d: Dictionary) -> void:
	derived = d
	queue_redraw()

func _process(delta: float) -> void:
	_t += delta
	queue_redraw()  # pulses/wisps/orbits animate

func _stat(s: String) -> float:
	return float((derived.get("stats", {}) as Dictionary).get(s, 0.0))

func _draw() -> void:
	var c := size * 0.5
	if String(derived.get("form_id", "")) == "":
		# Empty slab: a dim waiting ring.
		draw_arc(c, 54.0, 0, TAU, 48, Color(0.5, 0.5, 0.58, 0.25), 2.0)
		return

	var slab: Dictionary = ConfigDb.data["slab"]
	var stats_cfg: Dictionary = ConfigDb.data["stats"]
	var beef := _stat("beef")
	var power := _stat("power")
	var speed := _stat("speed")
	var wits := _stat("wits")
	var charm := _stat("charm")
	var dread := _stat("dread")
	var magic := _stat("magic")
	var persist := _stat("persistence")

	var base_r := float(slab["preview_base_radius"])
	var r := base_r * (float(stats_cfg["size_base"]) + float(stats_cfg["size_per_beef"]) * beef) * grow
	r = minf(r, base_r * 3.2)  # cap so a beefy build never overruns the slab
	var pulse := 0.5 + 0.5 * sin(_t * 2.2)

	var body := Color(String(derived.get("color", "#cccccc")))
	var aspect_col: Variant = _dominant_aspect_color()
	if aspect_col != null:
		body = body.lerp(aspect_col, float(slab["preview_aspect_tint"]))

	# Persistence — a faint after-image that refuses to fully die (undying).
	if persist > 0.0:
		var a := clampf(0.12 + 0.05 * persist, 0.0, 0.5)
		draw_circle(c + Vector2(sin(_t * 1.3), cos(_t * 1.1)) * 8.0, r, Color(body.r, body.g, body.b, a))

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
		draw_circle(c, r * 0.7, Color(0.5, 0.9, 1.0, clampf(0.06 + 0.04 * magic, 0, 0.5)))
		var motes := clampi(int(round(magic)), 1, 8)
		for i in motes:
			var ang := _t * 1.6 + TAU * i / float(motes)
			draw_circle(c + Vector2(cos(ang), sin(ang)) * (r + 16.0), 3.0, Color(0.6, 0.95, 1.0, 0.85))

	# Body — size is Beef made literal; outline thickens with Beef too.
	draw_circle(c, r, body)
	draw_arc(c, r, 0, TAU, 48, body.lightened(0.3), 2.0 + minf(beef * 0.4, 6.0))

	# Power — jagged spikes around the rim (the deletion stat, visibly sharp).
	if power > 0.0:
		var spikes := clampi(int(round(power)) + 4, 4, 16)
		var len := 7.0 + power * 1.6
		for i in spikes:
			var ang := TAU * i / float(spikes) - PI / 2.0
			var d := Vector2(cos(ang), sin(ang))
			var base := c + d * r
			var tip := c + d * (r + len)
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

	# Wits — the killer's eye: a bright glint that sharpens with Wits.
	var eye_r := 3.0 + clampf(wits, 0, 8) * 1.1
	var eye_a := clampf(0.4 + wits * 0.08, 0.4, 1.0)
	for ex in [-1.0, 1.0]:
		var ep := c + Vector2(ex * r * 0.32, -r * 0.22)
		draw_circle(ep, eye_r, Color(1, 1, 1, eye_a))
		draw_circle(ep, eye_r * 0.45, Color(0.1, 0.05, 0.15, eye_a))

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
	var stats: Dictionary = derived.get("stats", {})
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
