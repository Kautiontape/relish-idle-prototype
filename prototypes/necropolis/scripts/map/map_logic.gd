class_name MapLogic
extends RefCounted
## Pure map logic (no autoloads, so headless tests can compile it): the single source of lane
## geometry (routes and the ground's lane moat both call it), the type law's text formatters,
## zoom tiers, contrast, and the lane adapter / demo lanes that stand in until economy's E2
## fills view_lanes. Tuning lives in configs/map_view.json; the u -> width numbers it needs
## come from configs/pulse.json.

const VIEW_FILE := "res://configs/map_view.json"
const PULSE_FILE := "res://configs/pulse.json"
const MINUS := "−"

static var _cfg := {}
static var _pulse := {}


## Replace the map config (world_map passes ConfigDb's copy at _ready; tests pass the file).
static func configure(d: Dictionary) -> void:
	_cfg = d.duplicate(true)


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


# --- zoom tiers ------------------------------------------------------------------

## The `--map-clicks=x,y;x,y` list as screen-px points; malformed pairs are skipped.
static func parse_clicks(spec: String) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for pair in spec.split(";", false):
		var xy := pair.strip_edges().split(",", false)
		if xy.size() == 2 and xy[0].strip_edges().is_valid_float() and xy[1].strip_edges().is_valid_float():
			out.append(Vector2(float(xy[0]), float(xy[1])))
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


## view_lanes().lanes plus E1 stand-ins, in the STATE-API 5.3 row shape. A stand-in is added
## only for an id the view does not carry; dead, fort -> vei flood, haul, redirect and work
## stay whatever the view says (0 until economy's E2).
# TODO(api E2): drop the stand-ins when view_lanes carries living rows and the FLOOD rate.
static func lanes_from_views(view_lanes_rows: Array, forts: Array, hud: Dictionary) -> Array:
	var out: Array = []
	var by_id := {}
	for r in view_lanes_rows:
		var row := _copy_row(r)
		by_id[row["id"]] = row
		out.append(row)
	for f in forts:
		var row := _lane_row("living", "vei", str(f["id"]), float(f.get("ship_in", 0.0)))
		if not by_id.has(row["id"]):
			by_id[row["id"]] = row
			out.append(row)
	var flood := float(hud.get("split", {}).get("flood", 0.0))
	var fid := "flood:covington:vei"
	if by_id.has(fid):
		if by_id[fid]["rate"] == 0.0 and flood > 0.0:
			by_id[fid]["rate"] = flood
	else:
		out.append(_lane_row("flood", "covington", "vei", flood))
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
