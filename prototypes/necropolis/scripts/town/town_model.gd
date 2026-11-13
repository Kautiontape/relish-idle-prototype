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

## Per lot, in config order: {id, size, rect: Rect2, unlocked, door: String, door_pos: Vector2,
## building: {} or a display entry (see _entry)}.
var lots: Array = []
## Per street edge: {a, b, from: Vector2, to: Vector2}.
var streets: Array = []
## Street node id -> Vector2 (px).
var nodes: Dictionary = {}
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
var _laid_out := false


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
	for lot in lots:
		lot["unlocked"] = bool(view_lots.get(lot["id"], {}).get("unlocked", false))
		lot["building"] = _entry(by_lot[lot["id"]], lot, town) if by_lot.has(lot["id"]) else {}


func lot(id: String) -> Dictionary:
	for l in lots:
		if l["id"] == id:
			return l
	return {}


## The silhouette of `building_id` scaled into `r`, truncated so the drawn length is `reveal` of the
## total (the last stroke partial). Reveal 0 draws nothing; an unknown id draws nothing.
func strokes(building_id: String, r: Rect2, reveal: float) -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	if reveal <= 0.0 or not _unit.has(building_id):
		return out
	var scaled: Array[PackedVector2Array] = []
	var total := 0.0
	for pl in _unit[building_id]:
		var p := PackedVector2Array()
		p.resize(pl.size())
		for i in pl.size():
			p[i] = r.position + pl[i] * r.size
		scaled.append(p)
		total += _length(p)
	if reveal >= 1.0:
		return scaled
	var left := reveal * total
	for p in scaled:
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


## The wall ring of `t` in px (an open polyline whose two ends flank the gate), if the town has
## reached that tier; else [].
func walls(t: String) -> PackedVector2Array:
	var out := PackedVector2Array()
	var idx := tiers.find(t)
	if idx < 0 or idx > tiers.find(tier):
		return out
	for p in _v.get("tier_walls", {}).get(t, []):
		out.append(_px(p))
	return out


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
	var ref_px: Array = _v.get("ref_px", [1600, 900])
	var ref := Vector2(float(ref_px[0]) - float(_v.get("dock_w", 0)), float(ref_px[1]) - float(_v.get("hud_h", 0)))
	scale = minf(r.size.x / ref.x, r.size.y / ref.y) if ref.x > 0.0 and ref.y > 0.0 else 1.0
	nodes = {}
	for id in _v.get("street_nodes", {}):
		nodes[String(id)] = _px(_v["street_nodes"][id])
	streets = []
	for e in _v.get("street_edges", []):
		var a := String(e[0])
		var b := String(e[1])
		if nodes.has(a) and nodes.has(b):
			streets.append({"a": a, "b": b, "from": nodes[a], "to": nodes[b]})
	var unit := float(_v.get("lot_unit_px", 80)) * scale
	var h := float(_v.get("lot_h_px", 88)) * scale
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
			"door": door, "door_pos": nodes.get(door, c), "building": {},
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


## Dijkstra over the street graph (a few dozen nodes), edge weights in px.
func _route(a: String, b: String) -> Array:
	var dist := {a: 0.0}
	var prev := {}
	var open := [a]
	var done := {}
	while not open.is_empty():
		var bi := 0
		for i in open.size():
			if dist[open[i]] < dist[open[bi]]:
				bi = i
		var u: String = open[bi]
		open.remove_at(bi)
		if u == b:
			break
		done[u] = true
		for n in _adj.get(u, []):
			if done.has(n) or not nodes.has(n):
				continue
			var d: float = dist[u] + nodes[u].distance_to(nodes[n])
			if not dist.has(n) or d < dist[n]:
				if not dist.has(n):
					open.append(n)
				dist[n] = d
				prev[n] = u
	if not dist.has(b):
		return []
	var out := [b]
	while out[0] != a:
		out.push_front(prev[out[0]])
	return out


# --------------------------------------------------------------- buildings ----
## Display entry for one view_town building on `lot`.
func _entry(b: Dictionary, lot: Dictionary, town: Dictionary) -> Dictionary:
	var bid := String(b.get("building_id", ""))
	var meta: Dictionary = _bview.get(bid, {})
	var state := String(b.get("state", "active"))
	var progress := clampf(float(b.get("progress", 1.0)), 0.0, 1.0)
	var slots := int(b.get("slots", 0))
	var staffed := float(b.get("staffed", 0.0))
	var jobs: Dictionary = _bcfg.get(bid, {}).get("jobs", {})
	var pip := _pips(b, jobs)
	return {
		"lot_id": String(b.get("lot_id", "")), "building_id": bid,
		"label": String(meta.get("label", bid.capitalize())), "ink": String(meta.get("ink", "town")),
		"state": state, "progress": progress, "reveal": progress if state == "constructing" else 1.0,
		"glow": _glow(b, state, String(meta.get("light_by", "always")), town),
		"pips": int(pip["pips"]), "pip_key": String(pip["pip_key"]),
		"slots": slots, "staffed": staffed, "unpaid": state == "unpaid",
		"foreman": String(b.get("foreman", "")), "rect": _footprint(bid, lot),
	}


## The silhouette's rect: the building's own lot_size wide, centred in its lot.
func _footprint(bid: String, lot: Dictionary) -> Rect2:
	var lr: Rect2 = lot["rect"]
	var size := mini(int(_bcfg.get(bid, {}).get("lot_size", lot["size"])), int(lot["size"]))
	var w := lr.size.x * float(size) / float(maxi(int(lot["size"]), 1))
	return Rect2(lr.position.x + (lr.size.x - w) * 0.5, lr.position.y, w, lr.size.y)


func _glow(b: Dictionary, state: String, light_by: String, town: Dictionary) -> float:
	match state:
		"constructing", "unpaid":
			return float(_v.get("glow_dim", 0.15))
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
			var ref := float(_v.get("glow_ref", 8.0))
			return clampf(log(1.0 + rate) / log(1.0 + ref), 0.0, 1.0) if ref > 0.0 else 0.0
		"living":
			var cap := float(town.get("living_cap", 0.0))
			return clampf(float(town.get("living", 0.0)) / cap, 0.0, 1.0) if cap > 0.0 else 0.0
		"always":
			return float(_v.get("glow_always", 0.35))
	return 0.0


## {pips, pip_key}: the main output (first of view.pip_order with a positive rate) over its pip unit,
## floored and capped at pip_max.
func _pips(b: Dictionary, jobs: Dictionary) -> Dictionary:
	if staffing_standin:
		return TownStandins.staffing_pips(b, jobs, _v)
	var out: Dictionary = b.get("output", {})
	for k in _v.get("pip_order", []):
		var rate := float(out.get(k, 0.0))
		if rate <= 0.0:
			continue
		var unit := float(_v.get("pip_unit", {}).get(k, 0.0))
		var pips := floori(rate / unit + 1e-6) if unit > 0.0 else 0
		return {"pips": clampi(pips, 0, int(_v.get("pip_max", 8))), "pip_key": String(_v.get("pip_ink", {}).get(k, ""))}
	return {"pips": 0, "pip_key": ""}
