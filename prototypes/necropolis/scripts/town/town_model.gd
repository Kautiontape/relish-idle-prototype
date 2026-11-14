class_name TownModel
extends RefCounted
## Covington's display state, pure: turns the shell's view dicts and the configs into plain data
## for the town view (lots, buildings, streets, walls) and the tests. No autoloads, no Engine, no
## Nodes; colours stay Palette key strings for the renderer to resolve.
##
##   var m := TownModel.new(town_cfg, buildings_view, buildings_cfg, economy_cfg)
##   m.update(views, Rect2(Vector2.ZERO, size))   # views: town, hud, catalog, ... (any may be {})
##   for lot in m.lots: lot.rect, lot.door, lot.building.glow, m.strokes(id, rect, reveal) ...
##
## Positions in configs are normalised to the town view rect. Sizes (lot unit, height, gap) are
## pixels at the reference 1600x900 window and scale with min(rect / reference view).

## The building whose lot is the town's heart (the slab, the tempo source, the idle workers).
const HEART := "crypt"
## A building's look (look_of): how the canvas draws it, by shape as well as colour.
const LOOKS := ["staffed", "unstaffed", "unpaid", "calm", "constructing", "heart"]

## Per lot, in config order: {id, size, rect: Rect2, unlocked, door: String, door_pos: Vector2,
## hops: float (the door's street distance from the plaza, px), building: {} or a display entry
## (see _entry)}.
var lots: Array = []
## The output changes of the last update(), one per building whose output moved by more than
## view.float.eps since the update before: {lot_id, key, delta, text (signed, "+0.30 gold/s"),
## ink (the matter's Palette key), text_key (ink, or `text` where the ink is too dark for text)}.
## A building first seen, or a different building on a lot, seeds silently.
var floats: Array = []
## Per street (same index): its ring from the crypt, 1 for the streets at the plaza, counted in
## street hops (the still equivalent of the wave under reduced motion).
var street_order := PackedInt32Array()
## Per street edge: {a, b, from: Vector2, to: Vector2, near: Vector2, far: Vector2, length: float}.
## `near`/`far` orient the edge away from the plaza (near is the end closer along the streets).
## The streams they carry are the agents' (TownAgents.edge_rates, same index).
var streets: Array = []
## Street node id -> Vector2 (px).
var nodes: Dictionary = {}
## Street node id -> shortest street distance from the plaza, px (the town's hop measure: the
## crypt slab is the tempo source, law 5). `depth` is the largest, for Pulse.wave(d, depth).
var dist: Dictionary = {}
var depth := 0.0
var tier := ""
## view_town's next_tier: {tier, have, need, missing}.
var next_tier: Dictionary = {}
## Tier ids in order (economy.json town.tiers).
var tiers: Array = []
## STANDIN(E2): true while every building's output is the E1 stub ({}).
var staffing_standin := false
var rect := Rect2()
var scale := 1.0

var _lots_cfg: Array = []
var _v: Dictionary = {}
var _bview: Dictionary = {}
var _bcfg: Dictionary = {}
var _unit: Dictionary = {}  # building id -> Array[PackedVector2Array] in the unit box
var _adj: Dictionary = {}   # node id -> Array[String]
var _paths: Dictionary = {}  # "a|b" -> PackedVector2Array
var _routes: Dictionary = {}  # "a|b" -> PackedStringArray
var _edge_of: Dictionary = {}  # "a|b" (both orders) -> index into streets
var _laid_out := false
var _prev_out: Dictionary = {}  # lot id -> {building_id, output}: the last update's, for floats


func _init(town_cfg: Dictionary = {}, buildings_view: Dictionary = {}, buildings_cfg: Dictionary = {},
		economy_cfg: Dictionary = {}) -> void:
	_lots_cfg = town_cfg.get("lots", [])
	_v = town_cfg.get("view", {})
	_bview = buildings_view
	_bcfg = buildings_cfg
	tiers = (economy_cfg.get("town", {}).get("tiers", {}) as Dictionary).keys()
	tier = String(tiers[0]) if not tiers.is_empty() else ""
	for bid in _bview:
		var pls: Array[PackedVector2Array] = []
		for pl in _bview[bid].get("strokes", []):
			var p := PackedVector2Array()
			for q in pl:
				p.append(Vector2(float(q[0]), float(q[1])))
			if p.size() >= 2:
				pls.append(p)
		_unit[bid] = pls
	for e in _v.get("street_edges", []):
		var a := String(e[0])
		var b := String(e[1])
		if not _adj.has(a):
			_adj[a] = []
		if not _adj.has(b):
			_adj[b] = []
		_adj[a].append(b)
		_adj[b].append(a)


## Rebuilds the display state from the shell's views and the view's pixel rect.
func update(views: Dictionary, r: Rect2) -> void:
	if not _laid_out or r != rect:
		_layout(r)
	var town: Dictionary = views.get("town", {})
	tier = String(town.get("tier", tiers[0] if not tiers.is_empty() else ""))
	next_tier = (town.get("next_tier", {}) as Dictionary).duplicate(true)
	var view_lots := {}
	for l in town.get("lots", []):
		view_lots[String(l.get("id", ""))] = l
	var by_lot := {}
	var built: Array = town.get("buildings", [])
	for b in built:
		by_lot[String(b.get("lot_id", ""))] = b
	staffing_standin = TownStandins.outputs_stubbed(built)
	floats = []
	for lot in lots:
		lot["unlocked"] = bool(view_lots.get(lot["id"], {}).get("unlocked", false))
		lot["building"] = _entry(by_lot[lot["id"]], lot, town) if by_lot.has(lot["id"]) else {}
		_check_float(String(lot["id"]), by_lot.get(lot["id"], {}))


func lot(id: String) -> Dictionary:
	for l in lots:
		if l["id"] == id:
			return l
	return {}


## The lot under `p`. Every lot's hit box is grown to at least `min_px` per side (around its
## centre) so small lots stay clickable; a point inside a lot's real rect wins, else the grown box
## whose centre is nearest. "" if none.
func lot_at(p: Vector2, min_px: float) -> String:
	var best := ""
	var best_d := INF
	for l in lots:
		var r: Rect2 = l["rect"]
		if r.has_point(p):
			return String(l["id"])
		var c := r.get_center()
		var box := Rect2(c - Vector2(maxf(r.size.x, min_px), maxf(r.size.y, min_px)) * 0.5,
			Vector2(maxf(r.size.x, min_px), maxf(r.size.y, min_px)))
		if box.has_point(p) and c.distance_to(p) < best_d:
			best_d = c.distance_to(p)
			best = String(l["id"])
	return best


## Places BuildSort.ghosts() on the canvas: each ghost gains `rect` (the lot's footprint; the
## queued building's, or the standing building's for an upgrade), `ring` (the number ring's centre,
## inset at the footprint's top-left) and `lot_rect`. Ghosts on unknown lots are dropped.
func ghost_layout(ghosts: Array) -> Array:
	var out: Array = []
	var ring_r := float((_v.get("ghost", {}) as Dictionary).get("ring_px", 0.0))
	for g in ghosts:
		var l := lot(String(g["lot_id"]))
		if l.is_empty():
			continue
		var bid := String(g["building_id"])
		var r: Rect2 = _footprint(bid, l)
		var e: Dictionary = g.duplicate()
		e["rect"] = r
		e["lot_rect"] = l["rect"]
		e["ring"] = r.position + Vector2(ring_r + 2.0, ring_r + 2.0)
		out.append(e)
	return out


## The silhouette of `building_id` scaled into `r`, truncated so the drawn length is `reveal` of the
## total (the last stroke partial). Reveal 0 draws nothing; an unknown id draws nothing.
func strokes(building_id: String, r: Rect2, reveal: float) -> Array[PackedVector2Array]:
	var scaled: Array[PackedVector2Array] = []
	if reveal <= 0.0 or not _unit.has(building_id):
		return scaled
	for pl in _unit[building_id]:
		var p := PackedVector2Array()
		p.resize(pl.size())
		for i in pl.size():
			p[i] = r.position + pl[i] * r.size
		scaled.append(p)
	return truncate(scaled, reveal)


## `pls` drawn in order and cut so the drawn length is `frac` of the total (the last polyline
## partial). The end of the last returned polyline is the drawing head. 0 -> [], >= 1 -> all.
static func truncate(pls: Array[PackedVector2Array], frac: float) -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	if frac <= 0.0:
		return out
	if frac >= 1.0:
		return pls.duplicate()
	var total := 0.0
	for p in pls:
		total += _length(p)
	var left := frac * total
	for p in pls:
		var l := _length(p)
		if l <= left:
			out.append(p)
			left -= l
			continue
		var part := PackedVector2Array([p[0]])
		for i in range(1, p.size()):
			var seg := p[i - 1].distance_to(p[i])
			if seg >= left:
				if left > 0.0:
					part.append(p[i - 1].lerp(p[i], left / seg))
				break
			part.append(p[i])
			left -= seg
		if part.size() >= 2:
			out.append(part)
		break
	return out


## Shortest street route between two nodes, in px (cached per rect). [] if either is unknown or
## they are not connected.
func path(from_node: String, to_node: String) -> PackedVector2Array:
	var key := from_node + "|" + to_node
	if _paths.has(key):
		return _paths[key]
	var out := PackedVector2Array()
	if nodes.has(from_node) and nodes.has(to_node):
		for id in _route(from_node, to_node):
			out.append(nodes[id])
	_paths[key] = out
	return out


## The street nodes of the shortest route between two nodes, ends included (cached per rect).
## [] if either is unknown or they are not connected; [a] when a == b.
func route(from_node: String, to_node: String) -> PackedStringArray:
	var key := from_node + "|" + to_node
	if _routes.has(key):
		return _routes[key]
	var out := PackedStringArray()
	if nodes.has(from_node) and nodes.has(to_node):
		for id in _route(from_node, to_node):
			out.append(id)
	_routes[key] = out
	return out


## Index into `streets` of the edge joining two nodes (either order), or -1.
func edge_index(a: String, b: String) -> int:
	return int(_edge_of.get(a + "|" + b, -1))


## The wall ring of `t` in px (an open polyline whose two ends flank the gate), if the town has
## reached that tier; else [].
func walls(t: String) -> PackedVector2Array:
	var idx := tiers.find(t)
	if idx < 0 or idx > tiers.find(tier):
		return PackedVector2Array()
	return wall_ring(t)


## The wall ring of `t` in px whether or not the town has reached it (the tier-up set piece draws
## it before the views catch up). [] for a tier without walls.
func wall_ring(t: String) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in _v.get("tier_walls", {}).get(t, []):
		out.append(_px(p))
	return out


## The floor's drift at `p` (px): along the nearest street, toward the crypt plaza, strength 1 on
## the street falling linearly to 0 at view.floor_reach_px (scaled); zero inside any lot rect.
func drift_at(p: Vector2) -> Vector2:
	for l in lots:
		if (l["rect"] as Rect2).has_point(p):
			return Vector2.ZERO
	var best := INF
	var dir := Vector2.ZERO
	for s in streets:
		var q := Geometry2D.get_closest_point_to_segment(p, s["near"], s["far"])
		var d := p.distance_to(q)
		if d < best:
			best = d
			dir = (s["near"] - s["far"]).normalized()
	var reach := float(_v.get("floor_reach_px", 0.0)) * scale
	if reach <= 0.0:
		return Vector2.ZERO
	return dir * clampf(1.0 - best / reach, 0.0, 1.0)


## WCAG contrast ratio of `fg` (alpha-blended over `bg`) against opaque `bg`.
static func contrast(fg: Color, bg: Color) -> float:
	var c := Color(lerpf(bg.r, fg.r, fg.a), lerpf(bg.g, fg.g, fg.a), lerpf(bg.b, fg.b, fg.a))
	var l1 := _luminance(c)
	var l2 := _luminance(bg)
	return (maxf(l1, l2) + 0.05) / (minf(l1, l2) + 0.05)


static func _luminance(c: Color) -> float:
	return 0.2126 * _lin(c.r) + 0.7152 * _lin(c.g) + 0.0722 * _lin(c.b)


static func _lin(v: float) -> float:
	return v / 12.92 if v <= 0.04045 else pow((v + 0.055) / 1.055, 2.4)


static func _length(p: PackedVector2Array) -> float:
	var l := 0.0
	for i in range(1, p.size()):
		l += p[i - 1].distance_to(p[i])
	return l


# ------------------------------------------------------------------ layout ----
func _px(p: Array) -> Vector2:
	return rect.position + Vector2(float(p[0]) * rect.size.x, float(p[1]) * rect.size.y)


func _layout(r: Rect2) -> void:
	rect = r
	_laid_out = true
	_paths.clear()
	_routes.clear()
	var ref_px: Array = _v.get("ref_px", [0, 0])
	var ref := Vector2(float(ref_px[0]) - float(_v.get("dock_w", 0)), float(ref_px[1]) - float(_v.get("hud_h", 0)))
	scale = minf(r.size.x / ref.x, r.size.y / ref.y) if ref.x > 0.0 and ref.y > 0.0 else 1.0
	nodes = {}
	for id in _v.get("street_nodes", {}):
		nodes[String(id)] = _px(_v["street_nodes"][id])
	dist = _distances("plaza")
	depth = 0.0
	for id in dist:
		depth = maxf(depth, dist[id])
	streets = []
	_edge_of = {}
	for e in _v.get("street_edges", []):
		var a := String(e[0])
		var b := String(e[1])
		if nodes.has(a) and nodes.has(b):
			var a_near := float(dist.get(a, INF)) <= float(dist.get(b, INF))
			_edge_of[a + "|" + b] = streets.size()
			_edge_of[b + "|" + a] = streets.size()
			streets.append({"a": a, "b": b, "from": nodes[a], "to": nodes[b],
				"near": nodes[a] if a_near else nodes[b], "far": nodes[b] if a_near else nodes[a],
				"length": nodes[a].distance_to(nodes[b])})
	street_order = _ring_order()
	var unit := float(_v.get("lot_unit_px", 0)) * scale
	var h := float(_v.get("lot_h_px", 0)) * scale
	var pos: Dictionary = _v.get("lot_pos", {})
	lots = []
	for l in _lots_cfg:
		var id := String(l.get("id", ""))
		var size := int(l.get("size", 1))
		var c := _px(pos.get(id, l.get("pos", [0.5, 0.5])))
		var w := float(size) * unit
		var door := _nearest(c)
		lots.append({
			"id": id, "size": size, "rect": Rect2(c - Vector2(w, h) * 0.5, Vector2(w, h)), "unlocked": false,
			"door": door, "door_pos": nodes.get(door, c), "hops": float(dist.get(door, 0.0)), "building": {},
		})


func _nearest(p: Vector2) -> String:
	var best := ""
	var best_d := INF
	for id in nodes:
		var d: float = nodes[id].distance_squared_to(p)
		if d < best_d:
			best_d = d
			best = id
	return best


## Per street: 1 + the street hops from the plaza to its nearer end (breadth first). A street the
## plaza can't reach gets 0.
func _ring_order() -> PackedInt32Array:
	var hop := {}
	if nodes.has("plaza"):
		hop["plaza"] = 0
		var q: Array = ["plaza"]
		while not q.is_empty():
			var u: String = q.pop_front()
			for n in _adj.get(u, []):
				if not hop.has(n) and nodes.has(n):
					hop[n] = int(hop[u]) + 1
					q.append(n)
	var out := PackedInt32Array()
	for s in streets:
		var ha := int(hop.get(s["a"], -1))
		var hb := int(hop.get(s["b"], -1))
		out.append(0 if ha < 0 and hb < 0 else mini(ha if ha >= 0 else hb, hb if hb >= 0 else ha) + 1)
	return out


## Street distance (px) from `src` to every node it reaches (Dijkstra).
func _distances(src: String) -> Dictionary:
	var out := {}
	if not nodes.has(src):
		return out
	out[src] = 0.0
	var open := [src]
	var done := {}
	while not open.is_empty():
		var bi := 0
		for i in open.size():
			if out[open[i]] < out[open[bi]]:
				bi = i
		var u: String = open[bi]
		open.remove_at(bi)
		done[u] = true
		for n in _adj.get(u, []):
			if done.has(n) or not nodes.has(n):
				continue
			var d: float = out[u] + nodes[u].distance_to(nodes[n])
			if not out.has(n):
				out[n] = d
				open.append(n)
			elif d < out[n]:
				out[n] = d
	return out


## Dijkstra over the street graph (a few dozen nodes), edge weights in px.
func _route(a: String, b: String) -> Array:
	var best := {a: 0.0}
	var prev := {}
	var open := [a]
	var done := {}
	while not open.is_empty():
		var bi := 0
		for i in open.size():
			if best[open[i]] < best[open[bi]]:
				bi = i
		var u: String = open[bi]
		open.remove_at(bi)
		if u == b:
			break
		done[u] = true
		for n in _adj.get(u, []):
			if done.has(n) or not nodes.has(n):
				continue
			var d: float = best[u] + nodes[u].distance_to(nodes[n])
			if not best.has(n) or d < best[n]:
				if not best.has(n):
					open.append(n)
				best[n] = d
				prev[n] = u
	if not best.has(b):
		return []
	var out := [b]
	while out[0] != a:
		out.push_front(prev[out[0]])
	return out


# --------------------------------------------------------------- buildings ----
## Display entry for one view_town building on `lot`. Beyond the view's fields: `look` (look_of),
## `pulse` (whether the slab's wave pulses it: staffed, constructing, the heart with Relish home),
## `working` / `short` (whole hands at work / open slots), `badge` ("12 working · 3 short" on a
## staffable building, "5 idle" on the heart, else ""), `pip_count` (the uncapped pip count),
## `status` and `status_parts` (status_of), `away` (the heart's "Relish away" label, else "").
func _entry(b: Dictionary, lot: Dictionary, town: Dictionary) -> Dictionary:
	var bid := String(b.get("building_id", ""))
	var meta: Dictionary = _bview.get(bid, {})
	var state := String(b.get("state", "active"))
	var progress := clampf(float(b.get("progress", 1.0)), 0.0, 1.0)
	var slots := int(b.get("slots", 0))
	var staffed := float(b.get("staffed", 0.0))
	var jobs: Dictionary = _bcfg.get(bid, {}).get("jobs", {})
	var pip := _pips(b, jobs)
	var look := look_of(bid, state, slots, not jobs.is_empty(), staffed)
	var working := working_of(staffed)
	var home := bool(town.get("relish_home", false))
	var badge := ""
	if look in ["staffed", "unstaffed"] and slots > 0:
		badge = badge_text(working, slots, _v)
	elif look == "heart":
		badge = BuildSort.fmt(String(_v.get("badge", {}).get("idle", "")),
			{"n": working_of(float(town.get("workers", {}).get("idle", 0.0)))})
	var parts := status_of(b, look, town, _bcfg, _bview, _v)
	return {
		"lot_id": String(b.get("lot_id", "")), "building_id": bid,
		"label": String(meta.get("label", bid.capitalize())), "ink": _ink(meta, town),
		"state": state, "progress": progress, "reveal": progress if state == "constructing" else 1.0,
		"glow": _glow(b, state, String(meta.get("light_by", "always")), town),
		"pips": int(pip["pips"]), "pip_key": String(pip["pip_key"]), "pip_count": int(pip["count"]),
		"slots": slots, "staffed": staffed, "unpaid": state == "unpaid",
		"foreman": String(b.get("foreman", "")), "rect": _footprint(bid, lot),
		"look": look, "pulse": look in ["staffed", "constructing"] or (look == "heart" and home),
		"working": working, "short": maxi(slots - working, 0) if look in ["staffed", "unstaffed"] else 0,
		"badge": badge, "status_parts": parts, "status": status_text(parts),
		"away": String(_v.get("status", {}).get("heart_away", "")) if look == "heart" and not home else "",
	}


## How the canvas draws a building, by shape as well as colour:
##   constructing  being built or upgraded (the reveal and progress ticks);
##   unpaid        idled by unpaid upkeep (dim outline, a warning tick);
##   heart         the crypt (Relish's violet and pulsing while she is home, undead ink away);
##   staffed       a job building with any staff, active (its ink, glow, pips; the slot ticks and the
##                 badge count whole hands, so a fraction of a hand reads "0 working · 2 short");
##   unstaffed     a job building with no staff (dim outline, a hollow slot row), or any idled one;
##   calm          a building that needs no staff, active (its ink, steady: no pulse, row or badge).
static func look_of(building_id: String, state: String, slots: int, has_jobs: bool, staffed: float) -> String:
	match state:
		"constructing":
			return "constructing"
		"unpaid":
			return "unpaid"
	if building_id == HEART:
		return "heart"
	if has_jobs or slots > 0:
		return "staffed" if state == "active" and staffed > 1e-6 else "unstaffed"
	return "calm" if state == "active" else "unstaffed"


## Whole hands at work: the floor of `staffed` (the slot ticks', the badge's and the status's count).
static func working_of(staffed: float) -> int:
	return maxi(floori(staffed + 1e-6), 0)


## "12 working · 3 short" (the short part only when slots exceed the working hands).
static func badge_text(working: int, slots: int, vcfg: Dictionary) -> String:
	var bc: Dictionary = vcfg.get("badge", {})
	var out := BuildSort.fmt(String(bc.get("working", "")), {"n": working})
	if slots > working:
		out += String(bc.get("sep", "")) + BuildSort.fmt(String(bc.get("short", "")), {"n": slots - working})
	return out


## Left offsets of `n` marks `size` wide, `gap` apart, with an extra `group_gap` after every
## `group`th mark (a tally: groups of 5 read as counts, not as a bar).
static func row_offsets(n: int, size: float, gap: float, group_gap: float, group: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var x := 0.0
	for i in n:
		if i > 0:
			x += size + gap + (group_gap if group > 0 and i % group == 0 else 0.0)
		out.append(x)
	return out


## The span of row_offsets(n, ...) from the first mark's left edge to the last one's right edge.
static func row_width(n: int, size: float, gap: float, group_gap: float, group: int) -> float:
	if n <= 0:
		return 0.0
	var o := row_offsets(n, size, gap, group_gap, group)
	return o[n - 1] + size


## The integer shown beside a pip row: the count when it is more than one group, else "".
static func count_label(n: int, group: int) -> String:
	return str(n) if n > group else ""


## A signed per-second rate of output `key` in its unit: "+0.30 gold/s", "−0.60 bodies/s" (burn
## spends bodies). view.rate_units: {key: {unit, sign, ink}}; an unknown key reads as itself.
static func rate_text(key: String, x: float, vcfg: Dictionary) -> String:
	var u: Dictionary = (vcfg.get("rate_units", {}) as Dictionary).get(key, {})
	var v := x * float(u.get("sign", 1.0))
	return "%s%.2f %s/s" % ["−" if v < 0.0 else "+", absf(v), String(u.get("unit", key))]


## The matter Palette key of output `key` (view.rate_units ink), "text" if unknown.
static func rate_ink(key: String, vcfg: Dictionary) -> String:
	return String((vcfg.get("rate_units", {}) as Dictionary).get(key, {}).get("ink", "text"))


## The key a rate's text is drawn in: its matter ink, except dead matter (matte, too dark for
## text at 4.5:1), which falls back to `text` beside a matte pip.
static func float_text_key(ink: String) -> String:
	return "text" if ink == "dead" or ink == "dead_lit" or ink == "text" else ink


## `output`'s keys in display order: view.pip_order first, then the rest sorted.
static func output_keys(output: Dictionary, vcfg: Dictionary) -> Array:
	var out: Array = []
	for k in vcfg.get("pip_order", []):
		if output.has(k):
			out.append(String(k))
	var rest: Array = []
	for k in output:
		if not String(k) in out:
			rest.append(String(k))
	rest.sort()
	return out + rest


## The building's one-line status as parts [[text, oblique: bool]] (rates oblique, words upright):
## "building: 45%", "unpaid: −0.03 gold/s upkeep", "idle: no staff (Haul is above it on the
## ladder)", "short 2 hands", "working: +0.30 gold/s", "no staff needed: +8 living cap", and the
## heart's "Relish away: slab idle". Templates: view.status. `b` is a view_town buildings entry,
## `look` its look_of(), `town` the view_town dict. Rates come from `output` (zero rates left out).
static func status_of(b: Dictionary, look: String, town: Dictionary, bcfg: Dictionary, bview: Dictionary, vcfg: Dictionary) -> Array:
	var sc: Dictionary = vcfg.get("status", {})
	var bid := String(b.get("building_id", ""))
	var slots := int(b.get("slots", 0))
	var working := working_of(float(b.get("staffed", 0.0)))
	match look:
		"constructing":
			return [[BuildSort.fmt(String(sc.get("building", "")), {"pct": roundi(float(b.get("progress", 0.0)) * 100.0)}), false]]
		"unpaid":
			var up: Dictionary = b.get("upkeep", {})
			var rates: Array = []
			for k in ["gold", "bone"]:
				if float(up.get(k, 0.0)) > 1e-6:
					rates.append(rate_text(k, -float(up[k]), vcfg))
			if rates.is_empty():
				return [[String(sc.get("unpaid_none", "")), false]]
			return _with_rates(String(sc.get("unpaid", "")), rates, String(sc.get("sep", ", ")))
		"heart":
			return [[String(sc.get("heart_home" if bool(town.get("relish_home", false)) else "heart_away", "")), false]]
		"calm":
			var ben := String(bview.get(bid, {}).get("benefit", ""))
			if ben == "":
				return [[String(sc.get("calm_none", "")), false]]
			return [[BuildSort.fmt(String(sc.get("calm", "")), {"benefit": ben}), false]]
		"unstaffed":
			return [[_idle_reason(b, town, bcfg, sc), false]]
	if slots > working:
		var n := slots - working
		return [[String(sc.get("short_one", "")) if n == 1 else BuildSort.fmt(String(sc.get("short", "")), {"n": n}), false]]
	var out: Dictionary = b.get("output", {})
	var rates: Array = []
	for k in output_keys(out, vcfg):
		if absf(float(out[k])) > 1e-6:
			rates.append(rate_text(k, float(out[k]), vcfg))
	if rates.is_empty():
		return [[String(sc.get("working_none", "")), false]]
	return _with_rates(String(sc.get("working", "")), rates, String(sc.get("sep", ", ")))


## The parts joined into one string.
static func status_text(parts: Array) -> String:
	var s := ""
	for p in parts:
		s += String(p[0])
	return s


## `tpl` split around "{rates}": the words upright, the rates (joined by `sep`) oblique.
static func _with_rates(tpl: String, rates: Array, sep: String) -> Array:
	var i := tpl.find("{rates}")
	if i < 0:
		return [[tpl, false]]
	var out: Array = []
	if i > 0:
		out.append([tpl.substr(0, i), false])
	out.append([sep.join(rates), true])
	var tail := tpl.substr(i + "{rates}".length())
	if tail != "":
		out.append([tail, false])
	return out


## Why a staffable building has no hand: its staff cap is 0; its job is off the ladder; or the
## nearest staffed job above it on the ladder takes the hands (no idle hand left at the crypt).
static func _idle_reason(b: Dictionary, town: Dictionary, bcfg: Dictionary, sc: Dictionary) -> String:
	if int(b.get("staff_cap", -1)) == 0:
		return String(sc.get("idle_capped", ""))
	var jobs: Dictionary = bcfg.get(String(b.get("building_id", "")), {}).get("jobs", {})
	if jobs.is_empty():
		return String(sc.get("idle", ""))
	var job := String(jobs.keys()[0])
	var ladder: Array = town.get("ladder_effective", [])
	var at := ladder.find(job)
	if at < 0:
		return BuildSort.fmt(String(sc.get("idle_off", "")), {"job": job.capitalize()})
	if working_of(float(town.get("workers", {}).get("idle", 0.0))) > 0:
		return String(sc.get("idle", ""))
	var staffed := {}
	for j in town.get("jobs", []):
		staffed[String(j.get("id", ""))] = float(staffed.get(String(j.get("id", "")), 0.0)) + float(j.get("staffed", 0.0))
	for i in range(at - 1, -1, -1):
		if float(staffed.get(String(ladder[i]), 0.0)) > 1e-6:
			return BuildSort.fmt(String(sc.get("idle_ladder", "")), {"job": String(ladder[i]).capitalize()})
	return String(sc.get("idle", ""))


## Compares lot `lot_id`'s building output with the last update's and records one float for the
## first output key (display order) that moved by more than view.float.eps. A building first seen,
## or a different building on the lot, seeds silently; an emptied lot forgets.
func _check_float(lot_id: String, b: Dictionary) -> void:
	if b.is_empty():
		_prev_out.erase(lot_id)
		return
	var bid := String(b.get("building_id", ""))
	var out: Dictionary = b.get("output", {})
	var prev: Dictionary = _prev_out.get(lot_id, {})
	_prev_out[lot_id] = {"building_id": bid, "output": out.duplicate()}
	if prev.is_empty() or String(prev["building_id"]) != bid:
		return
	var eps := float(_v.get("float", {}).get("eps", 0.0))
	var keys := output_keys(out, _v)
	for k in output_keys(prev["output"], _v):
		if not k in keys:
			keys.append(k)
	for k in keys:
		var d := float(out.get(k, 0.0)) - float((prev["output"] as Dictionary).get(k, 0.0))
		if absf(d) > eps:
			var ink := rate_ink(k, _v)
			floats.append({"lot_id": lot_id, "key": k, "delta": d, "text": rate_text(k, d, _v), "ink": ink,
				"text_key": float_text_key(ink)})
			return


## The building's ink key. Relish's violet only while she is home (the slab works); away, a
## relish-inked building takes view.relish_away_ink.
func _ink(meta: Dictionary, town: Dictionary) -> String:
	var ink := String(meta.get("ink", "town"))
	if ink == "relish" and not bool(town.get("relish_home", false)):
		return String(_v.get("relish_away_ink", ink))
	return ink


## The silhouette's rect: the building's own lot_size wide, centred in its lot.
func _footprint(bid: String, lot: Dictionary) -> Rect2:
	var lr: Rect2 = lot["rect"]
	var size := mini(int(_bcfg.get(bid, {}).get("lot_size", lot["size"])), int(lot["size"]))
	var w := lr.size.x * float(size) / float(maxi(int(lot["size"]), 1))
	return Rect2(lr.position.x + (lr.size.x - w) * 0.5, lr.position.y, w, lr.size.y)


func _glow(b: Dictionary, state: String, light_by: String, town: Dictionary) -> float:
	match state:
		"constructing", "unpaid":
			return float(_v.get("glow_dim", 0.0))
		"idle":
			return 0.0
	match light_by:
		"staffing":
			if staffing_standin:
				return TownStandins.staffing_glow(b)
			var rate := 0.0
			var out: Dictionary = b.get("output", {})
			for k in out:
				rate += maxf(float(out[k]), 0.0)
			var ref := float(_v.get("glow_ref", 0.0))
			return clampf(log(1.0 + rate) / log(1.0 + ref), 0.0, 1.0) if ref > 0.0 else 0.0
		"living":
			var cap := float(town.get("living_cap", 0.0))
			return clampf(float(town.get("living", 0.0)) / cap, 0.0, 1.0) if cap > 0.0 else 0.0
		"always":
			return float(_v.get("glow_always", 0.0))
	return 0.0


## {pips, pip_key, count}: the main output (first of view.pip_order with a positive rate) over its
## pip unit, floored; `pips` is capped at pip_max (what the row draws), `count` is not (the integer
## shown beside a long row).
func _pips(b: Dictionary, jobs: Dictionary) -> Dictionary:
	if staffing_standin:
		return TownStandins.staffing_pips(b, jobs, _v)
	var out: Dictionary = b.get("output", {})
	for k in _v.get("pip_order", []):
		var rate := float(out.get(k, 0.0))
		if rate <= 0.0:
			continue
		var unit := float(_v.get("pip_unit", {}).get(k, 0.0))
		var pips := maxi(floori(rate / unit + 1e-6), 0) if unit > 0.0 else 0
		return {"pips": mini(pips, int(_v.get("pip_max", 0))), "pip_key": String(_v.get("pip_ink", {}).get(k, "")), "count": pips}
	return {"pips": 0, "pip_key": "", "count": 0}
