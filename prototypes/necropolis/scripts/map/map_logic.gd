class_name MapLogic
extends RefCounted
## Pure map logic (no autoloads, so headless tests can compile it): the single source of lane
## geometry (routes and the ground's lane moat both call it), the type law's text formatters,
## zoom tiers, contrast, the view_lanes adapter, and the demo lanes that --lanes=demo shots
## draw. Tuning lives in configs/map_view.json; the u -> width numbers it needs come from
## configs/pulse.json.

const VIEW_FILE := "res://configs/map_view.json"
const PULSE_FILE := "res://configs/pulse.json"
const MINUS := "−"

static var _cfg := {}
static var _pulse := {}
static var _fit_memo := {}  # fit_view_clear's answers by their inputs (cleared by configure; at most FIT_MEMO_MAX)
const FIT_MEMO_MAX := 16
static var fit_searches := 0  # how many times fit_view_clear has searched (its memo missed): the tests read it


## Replace the map config (world_map passes ConfigDb's copy at _ready; tests pass the file).
static func configure(d: Dictionary) -> void:
	_cfg = d.duplicate(true)
	_fit_memo.clear()


static func cfg() -> Dictionary:
	if _cfg.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(VIEW_FILE))
		_cfg = parsed if parsed is Dictionary else {}
		if _cfg.is_empty():
			push_error("MapLogic: %s is missing or not a JSON object" % VIEW_FILE)
	return _cfg


static func _num(key: String) -> float:
	return float(cfg().get(key, 0.0))


static func _pulse_num(key: String) -> float:
	if _pulse.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(PULSE_FILE))
		_pulse = parsed if parsed is Dictionary else {}
	return float(_pulse.get(key, 0.0))


# --- lane geometry -------------------------------------------------------------

## Half the core stroke width of a lane at intensity `u` (u < 0 = off, drawn as u = 0).
static func lane_half_width(u: float) -> float:
	var uu := clampf(u, 0.0, 1.0)
	return (_pulse_num("width_base") + _pulse_num("width_per_u") * uu) * 0.5


static func _loop_curve(p: Vector2, half_width: float) -> Dictionary:
	return {"a": p, "c": p, "b": p, "half_width": half_width, "loop": true}


## The lane's quadratic Bezier: a = from, b = to, control point bowed left of travel by
## `bow` x chord (bow < 0, the default, uses lane_bow). Self-loops (from == to) return a
## degenerate curve with loop = true.
static func lane_curve(from_pos: Vector2, to_pos: Vector2, u: float, bow := -1.0) -> Dictionary:
	var hw := lane_half_width(u)
	var chord := from_pos.distance_to(to_pos)
	if chord < 1.0:
		return _loop_curve(from_pos, hw)
	var dir := (to_pos - from_pos) / chord
	var perp := Vector2(-dir.y, dir.x)
	var k := bow if bow >= 0.0 else _num("lane_bow")
	var c := (from_pos + to_pos) * 0.5 - perp * chord * k
	return {"a": from_pos, "c": c, "b": to_pos, "half_width": hw, "loop": false}


## True for the valve's direct FLOOD lane, Covington -> Vei: the separate, straighter, hotter line.
static func is_direct_flood(row: Dictionary) -> bool:
	return str(row.get("kind", "")) == "flood" and str(row.get("from", "")) == "covington" \
		and str(row.get("to", "")) == "vei"


## lane_curve for a view_lanes row: the direct Covington -> Vei FLOOD bows by flood_direct_bow,
## every other row by lane_bow. The routes and the ground's lane moat both call this.
static func lane_curve_for(row: Dictionary, from_pos: Vector2, to_pos: Vector2, u: float) -> Dictionary:
	return lane_curve(from_pos, to_pos, u, _num("flood_direct_bow") if is_direct_flood(row) else -1.0)


## Width of the dead gutter at dead intensity `u_dead` (u < 0 counts as 0).
static func gutter_width(u_dead: float) -> float:
	return _num("gutter_width_base") + _num("gutter_width_per_u") * clampf(u_dead, 0.0, 1.0)


## The dead gutter's own curve: the host lane's curve shifted sideways, to the bow side (left
## of travel), by host half width + gutter width / 2 + gutter_offset_px. It is anchored to the
## host's GEOMETRY, so an off host (u_host < 0) still uses the u = 0 width (the phantom bank).
static func gutter_curve(from_pos: Vector2, to_pos: Vector2, u_host: float, u_dead: float) -> Dictionary:
	var host := lane_curve(from_pos, to_pos, u_host)
	var gw := gutter_width(u_dead)
	if host["loop"]:
		return _loop_curve(from_pos, gw * 0.5)
	var dir := (to_pos - from_pos).normalized()
	var perp := Vector2(-dir.y, dir.x)
	var shift: Vector2 = -perp * (host["half_width"] + gw * 0.5 + _num("gutter_offset_px"))
	return {"a": host["a"] + shift, "c": host["c"] + shift, "b": host["b"] + shift,
		"half_width": gw * 0.5, "loop": false}


static func sample_quad(a: Vector2, c: Vector2, b: Vector2, n: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var steps := maxi(n, 1)
	for i in steps + 1:
		var s := float(i) / steps
		pts.append(a.lerp(c, s).lerp(c.lerp(b, s), s))
	return pts


static func curve_length(pts: PackedVector2Array) -> float:
	var total := 0.0
	for i in range(1, pts.size()):
		total += pts[i - 1].distance_to(pts[i])
	return total


## Drawn radius of a fortress ring by tier.
static func fort_radius(tier: int) -> float:
	return _num("fort_radius_base") + tier * _num("fort_radius_per_tier")


# --- the type law's text side ----------------------------------------------------

## Always signed, with a unit: "+4.2/s", "−0.3/s", "+0.0/s". Two decimals below |0.1|
## so a faint rate is still readable.
static func fmt_rate(x: float, unit := "/s") -> String:
	var mag := absf(x)
	var body := ("%.2f" % mag) if (mag > 0.0 and mag < 0.1) else ("%.1f" % mag)
	return ("+" if x >= 0.0 else MINUS) + body + unit


## Unsigned integer with thousands separators: "18,450".
static func fmt_mass(x: float) -> String:
	var digits := str(maxi(roundi(x), 0))
	var out := ""
	for i in digits.length():
		if i > 0 and (digits.length() - i) % 3 == 0:
			out += ","
		out += digits[i]
	return out


## Time to drain Vei's backlog. drain_s < 0 (the API's -1.0) means holding: "∞".
static func fmt_drain(drain_s: float) -> String:
	if drain_s < 0.0:
		return "∞"
	var s := roundi(drain_s)
	if s < 60:
		return "%ds" % s
	if s < 3600:
		return "%dm %02ds" % [s / 60, s % 60]
	return "%dh %02dm" % [s / 3600, (s % 3600) / 60]


static func sign_glyph(sign: int) -> String:
	if sign > 0:
		return "▲"
	if sign < 0:
		return "▼"
	return "holding"


# --- camera fit ------------------------------------------------------------------

## The default fit: the zoom and the camera centre that frame `content` (world px) inside the
## viewport below `inset_top` screen px (the HUD plates), scaled by fit_margin. The content's
## centre lands in the middle of the free area, so the content fits inside it.
static func fit_view(content: Rect2, viewport: Vector2, inset_top: float) -> Dictionary:
	var free_h := viewport.y - inset_top
	if content.size.x < 1.0 or content.size.y < 1.0 or viewport.x < 1.0 or free_h < 1.0:
		return {}
	var z := minf(viewport.x / content.size.x, free_h / content.size.y) * _num("fit_margin")
	var centre := content.get_center() - Vector2(0.0, inset_top * 0.5 / z)
	return {"zoom": z, "centre": centre}


## An item's footprint on screen at a camera (`zoom`, `centre`). A fort: its ring stack (`r`, world
## px, about world `pos`) and the text hanging under it, `text_px` screen px from `below` world px
## under the centre, `half_px` screen px either side: {pos, r, below, text_px, half_px}. Anything
## else drawn in world px only (Vei's stack and reading): {world: Rect2}.
static func item_rect(it: Dictionary, zoom: float, centre: Vector2, viewport: Vector2) -> Rect2:
	if it.has("world"):
		var w: Rect2 = it["world"]
		return Rect2((w.position - centre) * zoom + viewport * 0.5, w.size * zoom)
	var c: Vector2 = ((it["pos"] as Vector2) - centre) * zoom + viewport * 0.5
	var r := float(it["r"]) * zoom
	var half := maxf(r, float(it["half_px"]))
	var bottom := maxf(r, float(it["below"]) * zoom + float(it["text_px"]))
	return Rect2(c.x - half, c.y - r, half * 2.0, r + bottom)


## The default fit kept clear of the screen's panels. fit_view's answer below `inset_top` (the top
## bar), unless an item (item_rect: every fort with its labels, Vei's stack) overlaps an
## `obstacles` rect (screen px: the valve panel, the objective strip, Relish's chip) or leaves the
## free area (below `inset_top`, fit_bottom_px above the bottom edge). Then a bounded search: at
## each zoom, shifts across the content's slack on screen (fit_shift_steps per axis, the nearest
## first), then the zoom times fit_shrink_step, at most fit_shrink_tries times and never under the
## mid tier's floor (zoom_far_below + zoom_hysteresis). The first clear camera wins; when none is,
## the one with the fewest items in the way. Returns {zoom, centre} ({} for degenerate input).
## The answer is kept by its inputs (the config only changes through configure, which drops them): the search costs
## ~5 ms, and on pre_vei the top bar re-wraps every few seconds (BONE's stall warning comes and goes), so the
## camera re-fits between the same two insets (economy P9 C-d's frame spikes). The key is the inputs' var_to_str:
## ~25 µs on pre_vei's (13 items, 1,354 chars) against ~1.1 ms a search (headless), and it is built once a fit,
## which is boot, an inset change and F6 (on pre_vei: 2 re-fits in the first 300 frames, none in the 72,000 after),
## so it stays a string.
static func fit_view_clear(content: Rect2, viewport: Vector2, inset_top: float, items: Array, obstacles: Array) -> Dictionary:
	var key := var_to_str([content, viewport, inset_top, items, obstacles])
	if _fit_memo.has(key):
		return (_fit_memo[key] as Dictionary).duplicate()
	var out := _fit_search(content, viewport, inset_top, items, obstacles)
	if _fit_memo.size() >= FIT_MEMO_MAX:
		_fit_memo.clear()
	_fit_memo[key] = out.duplicate()
	return out


## fit_view_clear's search, uncached.
static func _fit_search(content: Rect2, viewport: Vector2, inset_top: float, items: Array, obstacles: Array) -> Dictionary:
	fit_searches += 1
	var base := fit_view(content, viewport, inset_top)
	if base.is_empty():
		return base
	var floor_z := _num("zoom_far_below") + _num("zoom_hysteresis")
	var z: float = base["zoom"]
	var best := base
	var best_bad := _in_way(items, obstacles, z, base["centre"], viewport, inset_top)
	for k in int(_num("fit_shrink_tries")) + 1:
		if k > 0:
			z *= _num("fit_shrink_step")
			if z < floor_z:
				break
		var cb := content.get_center() - Vector2(0.0, inset_top * 0.5 / z)
		var cr := Rect2((content.position - cb) * z + viewport * 0.5, content.size * z)
		for s in _shifts(cr, viewport, inset_top):
			var centre: Vector2 = cb - (s as Vector2) / z
			var bad := _in_way(items, obstacles, z, centre, viewport, inset_top)
			if bad == 0:
				return {"zoom": z, "centre": centre}
			if bad < best_bad:
				best_bad = bad
				best = {"zoom": z, "centre": centre}
	return best


## Screen shifts that keep the content rect `cr` on screen below `inset_top`, nearest first.
static func _shifts(cr: Rect2, viewport: Vector2, inset_top: float) -> Array:
	var n := maxi(int(_num("fit_shift_steps")), 1)
	var xs := _span(-maxf(cr.position.x, 0.0), maxf(viewport.x - cr.end.x, 0.0), n)
	var ys := _span(-maxf(cr.position.y - inset_top, 0.0), maxf(viewport.y - cr.end.y, 0.0), n)
	var out: Array = []
	for x in xs:
		for y in ys:
			out.append(Vector2(x, y))
	out.sort_custom(func(a: Vector2, b: Vector2): return a.length_squared() < b.length_squared())
	return out


## `n` + 1 evenly spaced values from lo to hi, and 0.
static func _span(lo: float, hi: float, n: int) -> Array:
	var out: Array = [0.0]
	for i in n + 1:
		out.append(lerpf(lo, hi, float(i) / n))
	return out


## How many items are off the free area or under an obstacle at this camera.
static func _in_way(items: Array, obstacles: Array, z: float, centre: Vector2, viewport: Vector2, inset_top: float) -> int:
	var free := Rect2(0.0, inset_top, viewport.x, viewport.y - inset_top - _num("fit_bottom_px"))
	var n := 0
	for it in items:
		var r := item_rect(it, z, centre, viewport)
		if not free.encloses(r) or obstacles.any(func(o: Rect2): return r.intersects(o)):
			n += 1
	return n


# --- zoom tiers ------------------------------------------------------------------

## The `--map-clicks=x,y;x,y` list as screen-px points; malformed pairs are skipped.
static func parse_clicks(spec: String) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for pair in spec.split(";", false):
		var xy := pair.strip_edges().split(",", false)
		if xy.size() == 2 and xy[0].strip_edges().is_valid_float() and xy[1].strip_edges().is_valid_float():
			out.append(Vector2(float(xy[0]), float(xy[1])))
	return out


## The whole `--map-clicks` script as steps: "x,y" is a click, "x,y>x,y" a drag ("x,y>>x,y" held down at its end), "wN" a wait of N
## frames. Malformed items are skipped. [{kind: "click", pos}, {kind: "drag", from, to}, {kind: "wait", frames}]
static func parse_steps(spec: String) -> Array:
	var out: Array = []
	for item in spec.split(";", false):
		var it := item.strip_edges()
		if it.length() > 1 and it[0] == "w" and it.substr(1).is_valid_int():
			out.append({"kind": "wait", "frames": int(it.substr(1))})
		elif it.contains(">"):
			var hold := it.contains(">>")  # "x,y>>x,y": a drag that keeps the button down
			var ends := it.replace(">>", ">").split(">", false)
			if ends.size() == 2:
				var a := parse_clicks(ends[0])
				var b := parse_clicks(ends[1])
				if a.size() == 1 and b.size() == 1:
					out.append({"kind": "drag", "from": a[0], "to": b[0], "hold": hold})
		else:
			var pts := parse_clicks(it)
			if pts.size() == 1:
				out.append({"kind": "click", "pos": pts[0]})
	return out


## "far" / "mid" / "near". With `prev` set, the tier is only left once the zoom is past the
## threshold by zoom_hysteresis, so a zoom resting on a boundary does not flicker.
static func zoom_tier(zoom: float, prev: String) -> String:
	var far := _num("zoom_far_below")
	var near := _num("zoom_near_above")
	var h := _num("zoom_hysteresis")
	if prev == "far" and zoom < far + h:
		return "far"
	if prev == "near" and zoom > near - h:
		return "near"
	if prev == "mid" and zoom >= far - h and zoom <= near + h:
		return "mid"
	if zoom < far:
		return "far"
	if zoom > near:
		return "near"
	return "mid"


# --- contrast --------------------------------------------------------------------

static func _lin(c: float) -> float:
	return c / 12.92 if c <= 0.04045 else pow((c + 0.055) / 1.055, 2.4)


## WCAG relative luminance of `c`.
static func luminance(c: Color) -> float:
	return _luminance(c)


static func _luminance(c: Color) -> float:
	return 0.2126 * _lin(c.r) + 0.7152 * _lin(c.g) + 0.0722 * _lin(c.b)


## WCAG contrast ratio of `fg` (at its own alpha) composited over the opaque `bg`.
static func contrast_ratio(fg: Color, bg: Color) -> float:
	var over := Color(fg.r * fg.a + bg.r * (1.0 - fg.a), fg.g * fg.a + bg.g * (1.0 - fg.a),
		fg.b * fg.a + bg.b * (1.0 - fg.a))
	var l1 := _luminance(over)
	var l2 := _luminance(bg)
	return (maxf(l1, l2) + 0.05) / (minf(l1, l2) + 0.05)


# --- lanes: adapter and demo -----------------------------------------------------

static func _lane_row(kind: String, from: String, to: String, rate: float, bias := 1.0, why := "") -> Dictionary:
	return {"id": "%s:%s:%s" % [kind, from, to], "from": from, "to": to, "kind": kind,
		"rate": rate, "bias": bias, "why": why}


static func _copy_row(r: Dictionary) -> Dictionary:
	return {"id": str(r["id"]), "from": str(r["from"]), "to": str(r["to"]), "kind": str(r["kind"]),
		"rate": float(r["rate"]), "bias": float(r.get("bias", 1.0)), "why": str(r.get("why", ""))}


## view_lanes().lanes as copies in the STATE-API 5.3 row shape (bias and why defaulted when a
## row lacks them). Every kind is live since E2a, so nothing is invented.
static func lanes_from_views(view_lanes_rows: Array) -> Array:
	var out: Array = []
	for r in view_lanes_rows:
		out.append(_copy_row(r))
	return out


static func _spread(i: int, n: int, rmin: float, rmax: float) -> float:
	var t := 0.0 if n <= 1 else float(i) / (n - 1)
	return rmin * pow(rmax / rmin, t)


## Deterministic synthetic lanes exercising every LANE_KINDS kind, for --lanes=demo shots.
## Rates run from just above Pulse's rate_off to ~25. The fort at demo_lanes.phantom_fort_index
## has dead on and its fort -> vei flood at 0 (the gutter's phantom bank).
# TODO(api E2): debug stand-in
static func demo_lanes(forts: Array) -> Array:
	var d: Dictionary = cfg().get("demo_lanes", {})
	var rmin := float(d.get("rate_min", 0.08))
	var rmax := float(d.get("rate_max", 25.0))
	var n := forts.size()
	var rows: Array = []
	if n == 0:
		return rows
	var ids: Array = forts.map(func(f): return str(f["id"]))
	var dead_n := mini(int(d.get("dead_fort_count", 4)), n)
	var phantom: String = ids[mini(int(d.get("phantom_fort_index", 1)), n - 1)]
	var redirect: String = ids[mini(int(d.get("redirect_fort_index", 2)), n - 1)]
	for i in n:
		var bias := float(d.get("bias", 3.0)) if i == 0 else 1.0
		var why := str(d.get("why_bias", "")) if i == 0 else ""
		rows.append(_lane_row("war", "covington", ids[i], _spread(i, n, rmin, rmax), bias, why))
	rows.append(_lane_row("flood", "covington", "vei", _spread(n / 2, n, rmin, rmax)))
	for i in n:
		var rate := 0.0 if ids[i] == phantom else _spread((i * 5) % n, n, rmin, rmax)
		rows.append(_lane_row("flood", ids[i], "vei", rate))
	for i in dead_n:
		rows.append(_lane_row("dead", ids[i], "vei", _spread((i * 3 + 1) % n, n, rmin, rmax)))
	for i in n:
		var why := str(d.get("why_wave", "")) if i == 1 else ""
		rows.append(_lane_row("living", "vei", ids[i], _spread((i * 7 + 2) % n, n, rmin, rmax), 1.0, why))
	for i in mini(3, n):
		rows.append(_lane_row("haul", ids[i], "covington", _spread((i * 4 + 3) % n, n, rmin, rmax)))
	rows.append(_lane_row("redirect", redirect, redirect, _spread(n - 1, n, rmin, rmax)))
	rows.append(_lane_row("work", "covington", "covington", _spread(n / 2, n, rmin, rmax)))
	return rows
