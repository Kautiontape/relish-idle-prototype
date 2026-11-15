class_name LayoutLogic
extends RefCounted
## Pure fortress layout logic: the seeded generator, room roles, doors, reachability, placement
## and wall helpers. No scene-tree or autoload dependencies. RaidLogic keeps one-line delegates
## for the entry points, so callers and tests can use either.


# ------------------------------------------------------ layout generation ----
## Deterministic per fort_id (and `opts`): each fortress is recognizably itself on revisits.
## `opts`: `held` (bool, ignored for the boss arena): the player's held fort, which gets one
## fewer room and no warden or antechamber.
## Roles are exclusive and the warden room and antechamber are assigned last, so the antechamber
## may also be a checkpoint (an exit beside the warden is intended: bank and leave before the
## fight) and still reads `roles[ante_room] == "antechamber"`; `checkpoints` lists it all the same.
## Returns { size, wall_t, walls (all Rect2), inner_walls, doors, rooms, spawn, boss, gaps, held,
## roles (per room: spawn / checkpoint / antechamber / warden / normal), hops (BFS from the spawn
## room), adj (room adjacency), warden_room and ante_room (-1 if none), checkpoints (room indices,
## spawn first) }. Every door is an exit {side, rect, center, inner, exit: true, room}; closed
## doors are drawn as wall.
static func gen_layout(fort_id: String, tier: int, is_boss: bool, cfg: Dictionary, opts: Dictionary = {}) -> Dictionary:
	var lay: Dictionary = cfg.get("layout", {})
	var held := bool(opts.get("held", false)) and not is_boss
	var first := bool(opts.get("first_dungeon", false)) and not is_boss and not held
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(fort_id)
	var fit_r := float(cfg.get("party", {}).get("radius", 20.0))   # the army's biggest body must reach every room
	var last := {}
	var reach := {}   # the first grid-reachable candidate, if none fits a party big undead
	for attempt in 8:
		var cand := _gen_once(rng, tier, is_boss, lay, held)
		if cand.is_empty():
			continue   # role assignment failed; the rng has moved on
		last = cand
		if layout_reachable(cand, float(lay.get("grid_cell", 32.0))):
			if fits_all_rooms(cand, fit_r):
				return _with_first(cand, first, lay)
			if reach.is_empty():
				reach = cand
	if not reach.is_empty():
		return _with_first(reach, first, lay)
	if last.is_empty():
		# every attempt failed to place a warden room: fall back to a held-style layout
		last = _gen_once(rng, tier, is_boss, lay, true)
		return last
	return _with_first(last, first, lay)


## First-dungeon bookkeeping only: the flag and the pile radius ride on the layout, geometry and the
## generator's rng are untouched (populate_piles places the pile).
static func _with_first(layout: Dictionary, first: bool, lay: Dictionary) -> Dictionary:
	if first and int(layout.get("warden_room", -1)) >= 0:
		layout["first_dungeon"] = true
		layout["first_pile_px"] = float(lay.get("first_pile_px", 220.0))
		layout["first_pile_min_px"] = float(lay.get("first_pile_min_px", 120.0))
	return layout


static func _gen_once(rng: RandomNumberGenerator, tier: int, is_boss: bool, lay: Dictionary, held: bool = false) -> Dictionary:
	var w: float
	var h: float
	if is_boss:
		w = float(lay.get("boss_w", 2600))
		h = float(lay.get("boss_h", 1800))
	else:
		var tk := str(clampi(tier, 1, 4))
		w = float((lay.get("tier_w", {}) as Dictionary).get(tk, 1400))
		h = float((lay.get("tier_h", {}) as Dictionary).get(tk, 1000))
	var t := float(lay.get("wall_thickness", 30.0))
	var door_w := float(lay.get("door_width", 150.0))

	# --- doors: 2+tier gaps around the perimeter, south always served first ---
	var n_doors := int(lay.get("boss_doors", 7)) if is_boss else 2 + tier
	var sides: Array = []
	if is_boss:
		sides = ["s", "s", "s", "n", "e", "w", "s"]
		while sides.size() > n_doors:
			sides.pop_back()
		while sides.size() < n_doors:
			sides.append(["e", "w", "n"][sides.size() % 3])
	else:
		var order := ["s", "n", "e", "w"]
		for i in n_doors:
			sides.append(order[i % 4])
	var doors: Array = []
	for side in ["s", "n", "e", "w"]:
		var k: int = sides.count(side)
		if k == 0:
			continue
		var span := (w if (side == "s" or side == "n") else h) - 2.0 * (t + 70.0)
		var slot := span / k
		for i in k:
			var lo := (t + 70.0) + slot * i + 30.0
			var hi := (t + 70.0) + slot * (i + 1) - door_w - 30.0
			var a := rng.randf_range(lo, maxf(lo, hi))
			doors.append(_mk_door(side, a, door_w, w, h, t))

	# --- outer walls minus door gaps ---
	var walls: Array = []
	walls.append_array(_side_segments("s", doors, w, h, t))
	walls.append_array(_side_segments("n", doors, w, h, t))
	walls.append_array(_side_segments("e", doors, w, h, t))
	walls.append_array(_side_segments("w", doors, w, h, t))

	# --- internal partitions: BSP into 2+tier rooms with wide gap doorways ---
	var interior := Rect2(t, t, w - 2.0 * t, h - 2.0 * t)
	var min_room := float(lay.get("min_room_px", 300.0))
	var gap_w := float(lay.get("inner_gap_width", 165.0))
	var inner_walls: Array = []
	var gaps: Array = []
	var rooms: Array = []
	if is_boss:
		# the north zone stays one open audience chamber for Vei
		var split_y := t + (h - 2.0 * t) * 0.42
		var south := Rect2(t, split_y, w - 2.0 * t, h - t - split_y)
		rooms = _bsp([south], int(lay.get("boss_rooms", 4)) - 1, min_room, gap_w, t, rng, inner_walls, gaps)
		rooms.push_front(Rect2(t, t, w - 2.0 * t, split_y - t))
	else:
		var n_rooms := 2 + tier
		if held:
			n_rooms = maxi(2, 2 + tier - int(lay.get("held_rooms_delta", 1)))
		rooms = _bsp([interior], n_rooms, min_room, gap_w, t, rng, inner_walls, gaps)
	walls.append_array(inner_walls)

	# --- Relish spawns just inside the southernmost door ---
	var s_door := {}
	for d in doors:
		if d["side"] == "s":
			if s_door.is_empty() or (is_boss and absf(d["center"].x - w * 0.5) < absf(s_door["center"].x - w * 0.5)):
				s_door = d
	if s_door.is_empty():
		s_door = doors[0]
	var spawn: Vector2 = Vector2(s_door["center"].x, h - t - 70.0)

	var layout := {"size": Vector2(w, h), "wall_t": t, "walls": walls,
		"inner_walls": inner_walls, "doors": doors, "rooms": rooms,
		"spawn": spawn, "boss": is_boss, "gaps": gaps, "held": held}
	if is_boss:
		var roles: Array[String] = []
		for i in rooms.size():
			roles.append("normal")
		layout["roles"] = roles
		layout["warden_room"] = -1
		layout["ante_room"] = -1
		var empty_i: Array[int] = []
		layout["checkpoints"] = empty_i
		layout["adj"] = room_adjacency(layout)
		layout["hops"] = room_hops(layout["adj"], room_of(layout, spawn))
	elif not _assign_roles(layout, tier, held, lay):
		return {}
	add_routing(layout, float(lay.get("route_min_gap_px", 28.0)), float(lay.get("route_fit_pad_px", 4.0)))
	return layout


# -------------------------------------------------------------- room roles ---
## Rooms touched by a gap: the gap rect grown by ~wall_t/2 + 4 meets both rooms.
static func _gap_rooms(layout: Dictionary, g: Rect2) -> Array[int]:
	var out: Array[int] = []
	var grown := g.grow(float(layout["wall_t"]) * 0.5 + 4.0)
	var rooms: Array = layout["rooms"]
	for i in rooms.size():
		if grown.intersects(rooms[i] as Rect2):
			out.append(i)
	return out


# ----------------------------------------------------------------- routing ---
## Room-graph routing tables, built once the roles have sealed their gaps (so every portal is a
## real opening). Adds layout["portals"] ("a:b" -> gap centres joining rooms a and b, both
## orders), layout["next_room"] (next_room[a][b] = neighbour of a on a shortest path to b, -1 if
## none or a == b), layout["room_hops"] (hop counts, -1 unreachable) and layout["portal_adj"].
## Slits narrower than `min_gap_px` are not portals (unless dropping them would cut a room off).
## A gap is probed across its wall to find which rooms it really joins: a gap at a T-junction can
## open onto two rooms on one side (room_adjacency, which is looser, would call those two rooms
## neighbours too), and then it yields one portal per pair, centred on the stretch that serves it.
## Each portal keeps its width (the stretch both rooms face), and the tables come per mover size:
## a mover of radius r uses only portals at least 2r + `fit_pad_px` wide (`_size_class`). Also
## adds, indexed by room pair a * n + b: layout["portal_pts"] (gap centres, as in portals) and
## layout["portal_ws"] (their widths); and per size class: layout["route_w"] (the class's narrowest
## portal, ascending; class 0 is every portal and uses next_room / room_hops), layout["route_next"]
## and layout["route_hops"] (the class's tables, null for class 0), and layout["route_fit_pad"].
static func add_routing(layout: Dictionary, min_gap_px := 28.0, fit_pad_px := 4.0) -> void:
	var rooms: Array = layout["rooms"]
	var n: int = rooms.size()
	var half := float(layout.get("wall_t", 30.0)) * 0.5 + 4.0
	var found: Array = []   # [room a, room b, centre, width]
	for g in layout.get("gaps", []):
		var gr: Rect2 = g
		var vertical := gr.size.x < gr.size.y   # a vertical wall is crossed along x
		var c := gr.get_center()
		var lo := (gr.position.y if vertical else gr.position.x) + 2.0
		var hi := (gr.end.y if vertical else gr.end.x) - 2.0
		var spans := {}   # "a:b" -> [lo, hi] along the gap where a (low side) meets b (high side)
		var at := lo
		while at <= hi:
			var pa := Vector2(c.x - half, at) if vertical else Vector2(at, c.y - half)
			var pb := Vector2(c.x + half, at) if vertical else Vector2(at, c.y + half)
			var ra := room_of(layout, pa)
			var rb := room_of(layout, pb)
			if ra >= 0 and rb >= 0 and ra != rb:
				var key := "%d:%d" % [ra, rb]
				if not spans.has(key):
					spans[key] = [at, at]
				(spans[key] as Array)[1] = at
			at += 6.0
		for key in spans:
			var sp: Array = spans[key]
			var mid: float = (float(sp[0]) + float(sp[1])) * 0.5
			var ab: PackedStringArray = key.split(":")
			var ia := int(ab[0])
			var ib := int(ab[1])
			found.append([ia, ib, Vector2(c.x, mid) if vertical else Vector2(mid, c.y),
				_span_width(gr, vertical, rooms[ia], rooms[ib])])
	_open_edges(layout, found)
	# A T-junction can leave a slit too narrow for a unit; drop those unless that cuts the graph.
	var adj_all := _portal_adj(n, found, 0.0)
	var adj := _portal_adj(n, found, min_gap_px)
	var all_hops := room_hops(adj_all, 0)
	var hops_now := room_hops(adj, 0)
	var min_w := min_gap_px
	var cut := false
	for i in n:
		cut = cut or ((all_hops[i] >= 0) != (hops_now[i] >= 0))
	if cut:
		adj = adj_all
		min_w = 0.0
	var portals := {}
	var pts_by_pair: Array = []
	var ws_by_pair: Array = []
	for i in n * n:
		pts_by_pair.append([])
		ws_by_pair.append([])
	var widths: Array[float] = []   # the distinct widths of the kept portals
	for f in found:
		if float(f[3]) < min_w:
			continue
		for k in ["%d:%d" % [f[0], f[1]], "%d:%d" % [f[1], f[0]]]:
			if not portals.has(k):
				portals[k] = []
			(portals[k] as Array).append(f[2])
		for pair in [int(f[0]) * n + int(f[1]), int(f[1]) * n + int(f[0])]:
			(pts_by_pair[pair] as Array).append(f[2])
			(ws_by_pair[pair] as Array).append(float(f[3]))
		if not widths.has(float(f[3])):
			widths.append(float(f[3]))
	widths.sort()
	for l in adj:
		(l as Array).sort()
	layout["portal_adj"] = adj
	var base := _route_tables(adj, n)
	layout["portals"] = portals
	layout["next_room"] = base[0]
	layout["room_hops"] = base[1]
	layout["portal_pts"] = pts_by_pair
	layout["portal_ws"] = ws_by_pair
	# size classes: class 0 is every kept portal (the tables above); class k keeps those >= widths[k]
	var route_w := PackedFloat64Array([widths[0] if not widths.is_empty() else 0.0])
	var route_next: Array = [null]
	var route_hops: Array = [null]
	for k in range(1, widths.size()):
		var t := _route_tables(_portal_adj(n, found, widths[k]), n)
		route_w.append(widths[k])
		route_next.append(t[0])
		route_hops.append(t[1])
	layout["route_w"] = route_w
	layout["route_next"] = route_next
	layout["route_hops"] = route_hops
	layout["route_fit_pad"] = fit_pad_px


## The opening a gap gives between rooms `ra` and `rb` on either side of its wall: the stretch of
## the gap both rooms face, along the wall. Rooms are rects, so this is exact (a T-junction's side
## room faces only part of the gap).
static func _span_width(gr: Rect2, vertical: bool, ra: Rect2, rb: Rect2) -> float:
	if vertical:
		return maxf(0.0, minf(gr.end.y, minf(ra.end.y, rb.end.y)) - maxf(gr.position.y, maxf(ra.position.y, rb.position.y)))
	return maxf(0.0, minf(gr.end.x, minf(ra.end.x, rb.end.x)) - maxf(gr.position.x, maxf(ra.position.x, rb.position.x)))


## [next_room, room_hops] over an adjacency: next_room[a][b] is a's neighbour on a shortest path to
## b (-1 if none or a == b), room_hops[a][b] the hop count (-1 unreachable).
static func _route_tables(adj: Array, n: int) -> Array:
	var next_room: Array = []
	var hops_all: Array = []
	for a in n:
		var row: Array[int] = []
		row.resize(n)
		row.fill(-1)
		next_room.append(row)
		hops_all.append(room_hops(adj, a))
	# BFS outward from each target b: a node's BFS parent is its next hop toward b
	for b in n:
		var seen: Array[bool] = []
		seen.resize(n)
		seen.fill(false)
		seen[b] = true
		var queue: Array[int] = [b]
		var qi := 0
		while qi < queue.size():
			var c: int = queue[qi]
			qi += 1
			for nb in adj[c]:
				if not seen[nb]:
					seen[nb] = true
					(next_room[nb] as Array)[b] = c
					queue.append(nb)
	return [next_room, hops_all]


## The size class of a mover of `radius`: the first class whose portals are all at least
## 2 x radius + route_fit_pad wide (0, every portal, for most movers), or -1 when no portal is.
static func _size_class(layout: Dictionary, radius: float) -> int:
	if not layout.has("route_w"):
		return 0
	var ws: PackedFloat64Array = layout["route_w"]
	var need := 2.0 * radius + float(layout.get("route_fit_pad", 0.0))
	for k in ws.size():
		if ws[k] >= need:
			return k
	return -1


## The class to route a mover of `radius` from `from_pos` to `to_pos` by: its size class, or the base
## tables (0) when no portal fits it or its class has no way between the two (a squeeze beats a stand).
static func _route_class(layout: Dictionary, from_pos: Vector2, to_pos: Vector2, radius: float) -> int:
	var k := _size_class(layout, radius)
	if k <= 0:
		return 0
	var pr := _route_pair(layout, from_pos, to_pos, k)
	if pr.x != pr.y and int((_hops_tab(layout, k)[pr.x] as Array)[pr.y]) < 0:
		return 0
	return k


static func _next_tab(layout: Dictionary, k: int) -> Array:
	return layout["next_room"] if k <= 0 else layout["route_next"][k]


static func _hops_tab(layout: Dictionary, k: int) -> Array:
	return layout["room_hops"] if k <= 0 else layout["route_hops"][k]


## The narrowest portal class k may use (0 for the base class: every portal).
static func _class_w(layout: Dictionary, k: int) -> float:
	return 0.0 if k <= 0 else float((layout["route_w"] as PackedFloat64Array)[k])


## True when a mover of `radius` can walk from the spawn room to every room through portals it fits.
static func fits_all_rooms(layout: Dictionary, radius: float) -> bool:
	var n: int = (layout["rooms"] as Array).size()
	var start := room_of(layout, layout["spawn"])
	if n <= 1 or start < 0 or not layout.has("next_room"):
		return true
	var k := _size_class(layout, radius)
	if k < 0:
		return false
	for h in (_hops_tab(layout, k)[start] as Array):
		if int(h) < 0:
			return false
	return true


## True when the segment p->q, inflated by `radius`, crosses no inner wall. The perimeter clamp is
## separate. A slab test per rect; the rect is grown by radius minus a hair so a unit that
## resolve_walls parked exactly on a wall face still reads as clear when moving along it.
static func line_clear(layout: Dictionary, p: Vector2, q: Vector2, radius: float) -> bool:
	var g := maxf(0.0, radius - 0.5)
	for w in layout.get("inner_walls", []):
		if _seg_hits_rect(p, q, (w as Rect2).grow(g)):
			return false
	return true


static func _seg_hits_rect(p: Vector2, q: Vector2, r: Rect2) -> bool:
	var t0 := 0.0
	var t1 := 1.0
	var d := q - p
	if absf(d.x) < 1e-9:
		if p.x <= r.position.x or p.x >= r.end.x:
			return false
	else:
		var inv := 1.0 / d.x
		var ta := (r.position.x - p.x) * inv
		var tb := (r.end.x - p.x) * inv
		t0 = maxf(t0, minf(ta, tb))
		t1 = minf(t1, maxf(ta, tb))
		if t0 >= t1:
			return false
	if absf(d.y) < 1e-9:
		if p.y <= r.position.y or p.y >= r.end.y:
			return false
	else:
		var inv2 := 1.0 / d.y
		var tc := (r.position.y - p.y) * inv2
		var td := (r.end.y - p.y) * inv2
		t0 = maxf(t0, minf(tc, td))
		t1 = minf(t1, maxf(tc, td))
		if t0 >= t1:
			return false
	return true


## Rooms a point belongs to for routing: its room, else (a wall band / gap) every room within a
## wall thickness, else the nearest room.
static func _route_rooms(layout: Dictionary, p: Vector2) -> Array[int]:
	var out: Array[int] = []
	var r := room_of(layout, p)
	if r >= 0:
		out.append(r)
		return out
	var rooms: Array = layout["rooms"]
	var pad := float(layout.get("wall_t", 30.0)) + 2.0
	var best := -1
	var bd := INF
	for i in rooms.size():
		var rc: Rect2 = rooms[i]
		if rc.grow(pad).has_point(p):
			out.append(i)
		var cl := Vector2(clampf(p.x, rc.position.x, rc.end.x), clampf(p.y, rc.position.y, rc.end.y))
		var dd := cl.distance_squared_to(p)
		if dd < bd:
			bd = dd
			best = i
	if out.is_empty() and best >= 0:
		out.append(best)
	return out


## The (from_room, to_room) pair to route between: the shortest hop pair (in size class `k`'s
## tables) when either point sits in a band.
static func _route_pair(layout: Dictionary, from_pos: Vector2, to_pos: Vector2, k := 0) -> Vector2i:
	var fa := _route_rooms(layout, from_pos)
	var ta := _route_rooms(layout, to_pos)
	var hops: Array = _hops_tab(layout, k)
	var best := Vector2i(fa[0], ta[0])
	var bh := 1 << 20
	for a in fa:
		for b in ta:
			var h: int = 0 if a == b else int((hops[a] as Array)[b])
			if h < 0:
				continue
			if h < bh:
				bh = h
				best = Vector2i(a, b)
	return best


## The gap centre of the portal a->b at least `min_w` wide nearest to p ((INF, INF) if none).
static func _nearest_portal(layout: Dictionary, a: int, b: int, p: Vector2, min_w := 0.0) -> Vector2:
	var best := Vector2(INF, INF)
	var bd := INF
	var pair := a * (layout["rooms"] as Array).size() + b
	var pts: Array = layout["portal_pts"][pair]
	var ws: Array = layout["portal_ws"][pair]
	for i in pts.size():
		if float(ws[i]) < min_w:
			continue
		var d := p.distance_squared_to(pts[i])
		if d < bd:
			bd = d
			best = pts[i]
	return best


## Rooms that touch with no wall band between them (the boss arena's open audience chamber meets
## the rooms below it): each free stretch of the shared edge becomes portals, one per ~360 px.
static func _open_edges(layout: Dictionary, found: Array) -> void:
	var rooms: Array = layout["rooms"]
	var walls: Array = layout.get("inner_walls", [])
	for a in rooms.size():
		for b in range(a + 1, rooms.size()):
			var ra: Rect2 = rooms[a]
			var rb: Rect2 = rooms[b]
			for horizontal in [true, false]:   # true: a shared horizontal edge (rooms stacked)
				var edge := 0.0
				var lo := 0.0
				var hi := 0.0
				var touching := false
				if horizontal:
					for pair in [[ra, rb], [rb, ra]]:
						if absf((pair[0] as Rect2).end.y - (pair[1] as Rect2).position.y) < 1.5:
							touching = true
							edge = (pair[0] as Rect2).end.y
					lo = maxf(ra.position.x, rb.position.x)
					hi = minf(ra.end.x, rb.end.x)
				else:
					for pair in [[ra, rb], [rb, ra]]:
						if absf((pair[0] as Rect2).end.x - (pair[1] as Rect2).position.x) < 1.5:
							touching = true
							edge = (pair[0] as Rect2).end.x
					lo = maxf(ra.position.y, rb.position.y)
					hi = minf(ra.end.y, rb.end.y)
				if not touching or hi - lo < 1.0:
					continue
				# free stretches of [lo, hi] along the edge, minus the walls that cross it
				var blocked: Array = []
				for w in walls:
					var wr: Rect2 = w
					if horizontal and wr.position.y <= edge + 1.0 and wr.end.y >= edge - 1.0:
						blocked.append([wr.position.x, wr.end.x])
					elif not horizontal and wr.position.x <= edge + 1.0 and wr.end.x >= edge - 1.0:
						blocked.append([wr.position.y, wr.end.y])
				blocked.sort_custom(func(x: Array, y: Array) -> bool: return x[0] < y[0])
				var cur := lo
				var stretches: Array = []
				for bl in blocked:
					if bl[0] > cur:
						stretches.append([cur, minf(float(bl[0]), hi)])
					cur = maxf(cur, float(bl[1]))
				if cur < hi:
					stretches.append([cur, hi])
				for st in stretches:
					var w0: float = st[1] - st[0]
					if w0 < 1.0:
						continue
					var chunks := maxi(1, ceili(w0 / 360.0))
					for k in chunks:
						var mid: float = st[0] + w0 * (float(k) + 0.5) / float(chunks)
						found.append([a, b, Vector2(mid, edge) if horizontal else Vector2(edge, mid), w0 / float(chunks)])


static func _portal_adj(n: int, found: Array, min_w: float) -> Array:
	var adj: Array = []
	for i in n:
		var e: Array[int] = []
		adj.append(e)
	for f in found:
		if float(f[3]) < min_w:
			continue
		if not (adj[f[0]] as Array).has(f[1]):
			(adj[f[0]] as Array).append(f[1])
		if not (adj[f[1]] as Array).has(f[0]):
			(adj[f[1]] as Array).append(f[0])
	for l in adj:
		(l as Array).sort()
	return adj


## A doorstep inside room `rc` for a gap point `c` lying in the wall band: pulled `inset` in from the
## wall face across the wall; the coordinate along the wall stays where the gap is (it is already inside
## the room's span), so a narrow T-junction stretch is not nudged into a jamb.
static func _into_room(rc: Rect2, c: Vector2, inset: float) -> Vector2:
	var out := c
	var ix := minf(inset, rc.size.x * 0.4)
	var iy := minf(inset, rc.size.y * 0.4)
	if c.x <= rc.position.x + 0.5 or c.x >= rc.end.x - 0.5:
		out.x = clampf(c.x, rc.position.x + ix, rc.end.x - ix)
	if c.y <= rc.position.y + 0.5 or c.y >= rc.end.y - 0.5:
		out.y = clampf(c.y, rc.position.y + iy, rc.end.y - iy)
	return out


## The point to steer at to get from `from_pos` toward `to_pos` (a unit of `radius`).
## Direct when both are in one room or the line is clear. Otherwise through the nearest gap on the
## BFS path of the portals this mover fits (`_route_class`): the doorstep inside the current room (the gap centre pulled `radius + door_pad` off the
## wall face so the approach cannot clip a jamb), then, once a straight line through the gap is clear
## (or the mover is on the doorstep), the far-side doorstep in the next room. A point in a wall band routes from the
## touching room that is fewest hops from the target. A target in a band of the mover's own room that a
## jamb hides goes via its doorstep. Unreachable -> `to_pos`.
static func waypoint(layout: Dictionary, from_pos: Vector2, to_pos: Vector2, radius: float,
		door_pad := 14.0) -> Vector2:
	if not layout.has("next_room"):
		return to_pos
	var rf := room_of(layout, from_pos)
	if rf >= 0 and rf == room_of(layout, to_pos):
		return to_pos
	if line_clear(layout, from_pos, to_pos, radius):
		return to_pos
	var rooms: Array = layout["rooms"]
	var inset := radius + door_pad
	var k := _route_class(layout, from_pos, to_pos, radius)
	var min_w := _class_w(layout, k)
	if rf < 0:
		# in a wall band (a doorway): step straight out into the touching room that is fewest hops from
		# the target and whose way out is clear, then route from inside it
		var hops: Array = _hops_tab(layout, k)
		var n := rooms.size()
		var targets := _route_rooms(layout, to_pos)
		var best := Vector2(INF, INF)
		var bh := 1 << 20
		var bd := INF
		var cands := _route_rooms(layout, from_pos)
		for o in cands:
			var pts: Array[Vector2] = [_into_room(rooms[o], from_pos, inset)]
			for o2 in cands:
				if o2 != o:
					var pp: Array = layout["portal_pts"][o2 * n + o]
					var pw: Array = layout["portal_ws"][o2 * n + o]
					for i in pp.size():
						if float(pw[i]) >= min_w:
							pts.append(_into_room(rooms[o], pp[i], inset))
			var h := 1 << 20
			for tr in targets:
				var hh: int = 0 if o == tr else int((hops[o] as Array)[tr])
				if hh >= 0:
					h = mini(h, hh)
			for out_pt in pts:
				if not line_clear(layout, from_pos, out_pt, radius):
					continue
				var d := from_pos.distance_squared_to(out_pt)
				if h < bh or (h == bh and d < bd):
					bh = h
					bd = d
					best = out_pt
		if best.x != INF:
			return best
	var pair := _route_pair(layout, from_pos, to_pos, k)
	var a := pair.x
	var b := pair.y
	if a == b:
		if rf >= 0 and room_of(layout, to_pos) < 0:
			# the target sits in a doorway band of this room behind a jamb (the line is blocked): the
			# doorstep in front of it first, then straight in
			var step := _into_room(rooms[a], to_pos, inset)
			if from_pos.distance_to(step) > 3.0:
				return step
		return to_pos
	var nxt: int = int((_next_tab(layout, k)[a] as Array)[b])
	if nxt < 0:
		return to_pos
	var c := _nearest_portal(layout, a, nxt, from_pos, min_w)
	if c.x == INF:
		return to_pos
	var far := _into_room(rooms[nxt], c, inset)
	if line_clear(layout, from_pos, far, radius):
		return far
	var near := _into_room(rooms[a], c, inset)
	if from_pos.distance_to(near) <= 3.0:
		return far   # on the doorstep: step through even if a jamb still grazes the line
	return near


## Cheap route length estimate from a to b for a mover of `radius` (through the portals it fits, as
## `waypoint` routes it): straight when they share a room (or either sits in a band), else through
## the nearest gap into the next room. No wall tests; a lower-bound-ish figure for leashes ("is this
## foe within N px of walking").
static func route_dist(layout: Dictionary, from_pos: Vector2, to_pos: Vector2, radius := 0.0) -> float:
	var d := from_pos.distance_to(to_pos)
	if not layout.has("next_room"):
		return d
	var rf := room_of(layout, from_pos)
	var rt := room_of(layout, to_pos)
	if rf < 0 or rt < 0 or rf == rt:
		return d
	var k := maxi(0, _size_class(layout, radius))
	if k > 0 and int((_hops_tab(layout, k)[rf] as Array)[rt]) < 0:
		k = 0   # no way this wide: as waypoint, the base tables
	var nxt: int = int((_next_tab(layout, k)[rf] as Array)[rt])
	if nxt < 0:
		return INF
	var c := _nearest_portal(layout, rf, nxt, from_pos, _class_w(layout, k))
	if c.x == INF:
		return d
	var hops: int = int((_hops_tab(layout, k)[rf] as Array)[rt])
	var rooms: Array = layout["rooms"]
	var via := from_pos.distance_to(c) + c.distance_to(to_pos)
	if hops > 1:
		# the rest of the way: room-centre to room-centre hops, a coarse bound
		via = from_pos.distance_to(c) + c.distance_to((rooms[nxt] as Rect2).get_center()) \
			+ (rooms[nxt] as Rect2).get_center().distance_to(to_pos)
	return maxf(d, via)


## True when `to_pos` is within `reach` px of walking from `from_pos` for a mover of `radius`
## (route_dist; the straight line prunes first, since route_dist is never shorter).
static func walk_within(layout: Dictionary, from_pos: Vector2, to_pos: Vector2, reach: float, radius := 0.0) -> bool:
	return from_pos.distance_to(to_pos) < reach and route_dist(layout, from_pos, to_pos, radius) < reach


## adj[i] = sorted neighbour room indices (rooms sharing a wall gap).
static func room_adjacency(layout: Dictionary) -> Array:
	var n: int = (layout["rooms"] as Array).size()
	var adj: Array = []
	for i in n:
		var e: Array[int] = []
		adj.append(e)
	for g in layout.get("gaps", []):
		var rs := _gap_rooms(layout, g)
		for a in rs:
			for b in rs:
				if a != b and not (adj[a] as Array).has(b):
					(adj[a] as Array).append(b)
	for l in adj:
		(l as Array).sort()
	return adj


## The room containing p, else -1.
static func room_of(layout: Dictionary, p: Vector2) -> int:
	var rooms: Array = layout["rooms"]
	for i in rooms.size():
		if (rooms[i] as Rect2).has_point(p):
			return i
	return -1


## BFS hop counts from `start` (-1 = unreachable).
static func room_hops(adj: Array, start: int) -> Array[int]:
	var hops: Array[int] = []
	hops.resize(adj.size())
	hops.fill(-1)
	if start < 0 or start >= adj.size():
		return hops
	hops[start] = 0
	var queue: Array[int] = [start]
	var qi := 0
	while qi < queue.size():
		var c: int = queue[qi]
		qi += 1
		for nb in adj[c]:
			if hops[nb] < 0:
				hops[nb] = hops[c] + 1
				queue.append(nb)
	return hops


static func _door_room(layout: Dictionary, d: Dictionary) -> int:
	var r := room_of(layout, d["inner"])
	if r >= 0:
		return r
	var best := -1
	var bd := INF
	var rooms: Array = layout["rooms"]
	for i in rooms.size():
		var rc: Rect2 = rooms[i]
		var cl := Vector2(clampf(d["inner"].x, rc.position.x, rc.end.x), clampf(d["inner"].y, rc.position.y, rc.end.y))
		var dd: float = cl.distance_to(d["inner"])
		if dd < bd:
			bd = dd
			best = i
	return best


## Spawn room, sealed warden room + antechamber (unless held), checkpoints, and
## one real exit per checkpoint. Mutates layout; false = this attempt failed.
static func _assign_roles(layout: Dictionary, tier: int, held: bool, lay: Dictionary) -> bool:
	var rooms: Array = layout["rooms"]
	var n := rooms.size()
	var spawn_room := room_of(layout, layout["spawn"])
	if spawn_room < 0:
		return false
	var adj := room_adjacency(layout)
	var hops := room_hops(adj, spawn_room)
	var w_room := -1
	var a_room := -1
	if not held:
		var order: Array[int] = []
		for i in n:
			if i != spawn_room and hops[i] >= 1:
				order.append(i)
		order.sort_custom(func(x: int, y: int) -> bool:
			if hops[x] != hops[y]:
				return hops[x] > hops[y]
			var ax: float = (rooms[x] as Rect2).get_area()
			var ay: float = (rooms[y] as Rect2).get_area()
			if ax != ay:
				return ax > ay
			return x < y)
		for w in order:
			var best := -1
			for nb in adj[w]:
				if nb == spawn_room:
					continue
				if hops[w] >= 2 and hops[nb] != hops[w] - 1:
					continue
				if best < 0 or (rooms[nb] as Rect2).get_area() > (rooms[best] as Rect2).get_area():
					best = nb
			if best >= 0:
				w_room = w
				a_room = best
				break
		if w_room < 0:
			return false
		# seal every gap into W except one toward A
		var kept := false
		var new_gaps: Array = []
		for g in layout["gaps"]:
			var rs := _gap_rooms(layout, g)
			if not rs.has(w_room):
				new_gaps.append(g)
				continue
			var only_wa := true
			for r in rs:
				if r != w_room and r != a_room:
					only_wa = false
			if only_wa and rs.has(a_room) and not kept:
				kept = true
				new_gaps.append(g)
			else:
				(layout["inner_walls"] as Array).append(g)
				(layout["walls"] as Array).append(g)
		layout["gaps"] = new_gaps
		adj = room_adjacency(layout)
		hops = room_hops(adj, spawn_room)
		var only_a: Array[int] = [a_room]
		if adj[w_room] != only_a or hops[w_room] < 2 or hops[w_room] != hops[a_room] + 1:
			return false
		for h in hops:
			if h < 0:
				return false

	# --- checkpoints: spawn + deepest door-bearing rooms ---
	var door_rooms: Array[int] = []
	var doors: Array = layout["doors"]
	for d in doors:
		var dr := _door_room(layout, d)
		d["room"] = dr
		door_rooms.append(dr)
	var cands: Array[int] = []
	for i in n:
		if i != w_room and i != spawn_room and door_rooms.has(i):
			cands.append(i)
	cands.sort_custom(func(x: int, y: int) -> bool:
		if hops[x] != hops[y]:
			return hops[x] > hops[y]
		return x < y)
	var extra := int((lay.get("checkpoints_by_tier", {}) as Dictionary).get(str(clampi(tier, 1, 4)), 1))
	var checkpoints: Array[int] = [spawn_room]
	for c in cands:
		if checkpoints.size() >= 1 + extra:
			break
		checkpoints.append(c)

	# --- exits: one door per checkpoint, everything else becomes wall ---
	var kept_doors: Array = []
	for ci in checkpoints:
		var pick := {}
		var pd := INF
		for d in doors:
			if d["room"] != ci:
				continue
			var dist: float
			if ci == spawn_room:
				dist = absf(d["inner"].x - layout["spawn"].x) + (0.0 if d["side"] == "s" else 1.0e5)
			else:
				dist = (d["center"] as Vector2).distance_to((rooms[ci] as Rect2).get_center())
			if dist < pd:
				pd = dist
				pick = d
		if pick.is_empty():
			return false
		kept_doors.append(pick)
	for d in doors:
		if not kept_doors.has(d):
			(layout["walls"] as Array).append(d["rect"])
	for d in kept_doors:
		d["exit"] = true
	layout["doors"] = kept_doors

	var roles: Array[String] = []
	for i in n:
		roles.append("normal")
	for c in checkpoints:
		roles[c] = "checkpoint"
	roles[spawn_room] = "spawn"
	if not held:
		roles[a_room] = "antechamber"
		roles[w_room] = "warden"
	layout["roles"] = roles
	layout["hops"] = hops
	layout["adj"] = adj
	layout["warden_room"] = w_room
	layout["ante_room"] = a_room
	layout["checkpoints"] = checkpoints
	return true


static func _mk_door(side: String, along: float, dw: float, w: float, h: float, t: float) -> Dictionary:
	match side:
		"s":
			return {"side": "s", "rect": Rect2(along, h - t, dw, t),
				"center": Vector2(along + dw * 0.5, h - t * 0.5),
				"inner": Vector2(along + dw * 0.5, h - t - 50.0)}
		"n":
			return {"side": "n", "rect": Rect2(along, 0.0, dw, t),
				"center": Vector2(along + dw * 0.5, t * 0.5),
				"inner": Vector2(along + dw * 0.5, t + 50.0)}
		"w":
			return {"side": "w", "rect": Rect2(0.0, along, t, dw),
				"center": Vector2(t * 0.5, along + dw * 0.5),
				"inner": Vector2(t + 50.0, along + dw * 0.5)}
	return {"side": "e", "rect": Rect2(w - t, along, t, dw),
		"center": Vector2(w - t * 0.5, along + dw * 0.5),
		"inner": Vector2(w - t - 50.0, along + dw * 0.5)}


## One perimeter side as wall segments with this side's door intervals cut out.
static func _side_segments(side: String, doors: Array, w: float, h: float, t: float) -> Array:
	var horizontal := side == "s" or side == "n"
	var lo := t if horizontal else 0.0          # N/S walls sit between E/W walls
	var hi := (w - t) if horizontal else h      # E/W walls run the full height
	var cuts: Array = []
	for d in doors:
		if d["side"] != side:
			continue
		var r: Rect2 = d["rect"]
		cuts.append([r.position.x, r.end.x] if horizontal else [r.position.y, r.end.y])
	cuts.sort_custom(func(a, b): return a[0] < b[0])
	var segs: Array = []
	var x := lo
	for c in cuts:
		if c[0] - x > 8.0:
			segs.append(_band_rect(side, x, c[0], w, h, t))
		x = maxf(x, c[1])
	if hi - x > 8.0:
		segs.append(_band_rect(side, x, hi, w, h, t))
	return segs


static func _band_rect(side: String, a: float, b: float, w: float, h: float, t: float) -> Rect2:
	match side:
		"s":
			return Rect2(a, h - t, b - a, t)
		"n":
			return Rect2(a, 0.0, b - a, t)
		"w":
			return Rect2(0.0, a, t, b - a)
	return Rect2(w - t, a, t, b - a)


## Split leaves until `target` rooms exist; each split line becomes a wall with
## 1-2 wide gaps (multiple routes, never a single corridor).
static func _bsp(leaves: Array, target: int, min_room: float, gap_w: float, t: float,
		rng: RandomNumberGenerator, out_walls: Array, out_gaps: Array = []) -> Array:
	var ls: Array = leaves.duplicate()
	while ls.size() < target:
		var bi := -1
		var ba := 0.0
		for i in ls.size():
			var r: Rect2 = ls[i]
			if maxf(r.size.x, r.size.y) >= 2.0 * min_room + t and r.get_area() > ba:
				ba = r.get_area()
				bi = i
		if bi < 0:
			break
		var r: Rect2 = ls[bi]
		ls.remove_at(bi)
		var vert := r.size.x >= r.size.y
		var dim := r.size.x if vert else r.size.y
		var cut := clampf(rng.randf_range(0.42, 0.58) * dim, min_room, dim - min_room)
		if vert:
			var x := r.position.x + cut
			_wall_with_gaps(Rect2(x - t * 0.5, r.position.y, t, r.size.y), gap_w, rng, out_walls, out_gaps)
			ls.append(Rect2(r.position, Vector2(cut - t * 0.5, r.size.y)))
			ls.append(Rect2(Vector2(x + t * 0.5, r.position.y), Vector2(r.size.x - cut - t * 0.5, r.size.y)))
		else:
			var y := r.position.y + cut
			_wall_with_gaps(Rect2(r.position.x, y - t * 0.5, r.size.x, t), gap_w, rng, out_walls, out_gaps)
			ls.append(Rect2(r.position, Vector2(r.size.x, cut - t * 0.5)))
			ls.append(Rect2(Vector2(r.position.x, y + t * 0.5), Vector2(r.size.x, r.size.y - cut - t * 0.5)))
	return ls


static func _wall_with_gaps(band: Rect2, gap_w: float, rng: RandomNumberGenerator, out_walls: Array, out_gaps: Array = []) -> void:
	var horizontal := band.size.x >= band.size.y
	var lo := band.position.x if horizontal else band.position.y
	var hi := band.end.x if horizontal else band.end.y
	var length := hi - lo
	var n_gaps := 2 if length > 620.0 else 1
	var margin := 40.0
	var span := length - 2.0 * margin
	var slot := span / n_gaps
	var x := lo
	for i in n_gaps:
		var glo := lo + margin + slot * i + 10.0
		var ghi := lo + margin + slot * (i + 1) - gap_w - 10.0
		var g := rng.randf_range(glo, maxf(glo, ghi))
		if g - x > 10.0:
			out_walls.append(_sub_band(band, horizontal, x, g))
		out_gaps.append(_sub_band(band, horizontal, g, g + gap_w))
		x = g + gap_w
	if hi - x > 10.0:
		out_walls.append(_sub_band(band, horizontal, x, hi))


static func _sub_band(band: Rect2, horizontal: bool, a: float, b: float) -> Rect2:
	if horizontal:
		return Rect2(a, band.position.y, b - a, band.size.y)
	return Rect2(band.position.x, a, band.size.x, b - a)


# ------------------------------------------------------------ reachability ---
## Flood fill on a coarse grid: every room center and every door must be
## walkable from the spawn point.
static func layout_reachable(layout: Dictionary, cell: float) -> bool:
	var size: Vector2 = layout["size"]
	var cols := int(ceil(size.x / cell))
	var rows := int(ceil(size.y / cell))
	if cols <= 0 or rows <= 0:
		return false
	var blocked := PackedByteArray()
	blocked.resize(cols * rows)
	for wrect in layout["walls"]:
		var r: Rect2 = wrect
		var x0 := clampi(int(r.position.x / cell), 0, cols - 1)
		var x1 := clampi(int((r.end.x - 0.01) / cell), 0, cols - 1)
		var y0 := clampi(int(r.position.y / cell), 0, rows - 1)
		var y1 := clampi(int((r.end.y - 0.01) / cell), 0, rows - 1)
		for cy in range(y0, y1 + 1):
			for cx in range(x0, x1 + 1):
				blocked[cy * cols + cx] = 1
	var start := _cell_index(layout["spawn"], cell, cols, rows)
	if blocked[start] == 1:
		return false
	var seen := PackedByteArray()
	seen.resize(cols * rows)
	seen[start] = 1
	var queue := [start]
	var qi := 0
	while qi < queue.size():
		var c: int = queue[qi]
		qi += 1
		var cx := c % cols
		var cy := c / cols
		for d in [[1, 0], [-1, 0], [0, 1], [0, -1]]:
			var nx: int = cx + d[0]
			var ny: int = cy + d[1]
			if nx < 0 or ny < 0 or nx >= cols or ny >= rows:
				continue
			var ni := ny * cols + nx
			if seen[ni] == 0 and blocked[ni] == 0:
				seen[ni] = 1
				queue.append(ni)
	for room in layout["rooms"]:
		if seen[_cell_index((room as Rect2).get_center(), cell, cols, rows)] == 0:
			return false
	for d in layout["doors"]:
		if seen[_cell_index(d["inner"], cell, cols, rows)] == 0:
			return false
	return true


static func _cell_index(p: Vector2, cell: float, cols: int, rows: int) -> int:
	var cx := clampi(int(p.x / cell), 0, cols - 1)
	var cy := clampi(int(p.y / cell), 0, rows - 1)
	return cy * cols + cx


# ------------------------------------------------------------- population ----
## Enemy placement: rooms weighted away from the spawn; never right on top of
## Relish. Deterministic per fort (rng chained off fort_id).
static func populate_enemies(fort_id: String, layout: Dictionary, count: int, tier: int,
		cfg: Dictionary) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(fort_id) * 31 + 7919
	var spawn: Vector2 = layout["spawn"]
	var rooms: Array = layout["rooms"]
	var weights: Array = []
	var total := 0.0
	var rmult: Dictionary = cfg.get("enemy_room_mult_by_fort", {}).get(fort_id, {})   # D-d/E Step 4c (greywall)
	for ri0 in rooms.size():
		var d: float = (rooms[ri0] as Rect2).get_center().distance_to(spawn)
		var wt := pow(maxf(d, 40.0), 1.5) * float(rmult.get(str(ri0), 1.0))
		weights.append(wt)
		total += wt
	var out: Array = []
	for i in count:
		var roll := rng.randf() * total
		var ri := 0
		for j in weights.size():
			roll -= weights[j]
			if roll <= 0.0:
				ri = j
				break
		var room: Rect2 = rooms[ri]
		var inner := room.grow(-70.0) if room.size.x > 200.0 and room.size.y > 200.0 else room.grow(-30.0)
		var pos := Vector2.ZERO
		for attempt in 20:
			pos = Vector2(rng.randf_range(inner.position.x, inner.end.x),
				rng.randf_range(inner.position.y, inner.end.y))
			if pos.distance_to(spawn) > 320.0:
				break
		out.append({"kind": RaidLogic.roll_enemy_kind(rng, tier, cfg, fort_id), "pos": pos, "room": ri})
	return out


## D-d/E Step 3, the guarded detour: a cache in a side room, a living group on it. The cache room is a room
## off the shortest path from the spawn to the warden room that borders a path room other than the warden
## room: a "normal" room before a checkpoint (loot banks at a checkpoint, which would change what is at
## risk), then the fewest hops from the spawn, then the lowest index. Its cache lies `detour.cache_door_px`
## into it from the gap it shares with that path room (the walk in and out stays short; the fight is the
## point). None below `detour.min_tier`, in the first dungeon or a held fort. Returns {room, from_room,
## gap, pos}, or {}.
static func detour_site(layout: Dictionary, tier: int, cfg: Dictionary) -> Dictionary:
	var dc: Dictionary = cfg.get("detour", {})
	var wr := int(layout.get("warden_room", -1))
	if dc.is_empty() or tier < int(dc.get("min_tier", 99)) or wr < 0 or bool(layout.get("first_dungeon", false)) \
			or bool(layout.get("held", false)):
		return {}
	var path := room_path(layout, room_of(layout, layout["spawn"]), wr)
	var adj: Array = layout["adj"]
	var hops: Array = layout["hops"]
	var roles: Array = layout["roles"]
	var best := -1
	var from := -1
	var bkey := 0
	var portals: Dictionary = layout.get("portals", {})
	for i in (layout["rooms"] as Array).size():
		if path.has(i):
			continue
		for nb in adj[i]:
			# a real opening onto a path room that is not the warden's (adjacency alone can be a T-junction)
			if not path.has(nb) or nb == wr or (portals.get("%d:%d" % [nb, i], []) as Array).is_empty():
				continue
			var key := (((0 if str(roles[i]) == "normal" else 1) * 100 + int(hops[i])) * 100 + int(hops[nb])) * 100 + i
			if best < 0 or key < bkey:
				best = i
				from = nb
				bkey = key
	if best < 0:
		return {}
	var gc: Vector2 = (portals["%d:%d" % [from, best]] as Array)[0]
	var rc: Rect2 = layout["rooms"][best]
	var pos := _clamp_in(rc, gc + (rc.get_center() - gc).normalized() * float(dc.get("cache_door_px", 150.0)), 40.0)
	return {"room": best, "from_room": from, "gap": gc, "pos": pos}


## The detour's guard: `detour.guard_by_tier` living (the tier's mix) within `guard_spread_px` of the
## cache, inside its room and off the walls. Its own seeded rng (the fort id). [] with no site.
static func detour_guard(fort_id: String, layout: Dictionary, tier: int, cfg: Dictionary) -> Array:
	var out: Array = []
	var site := detour_site(layout, tier, cfg)
	if site.is_empty():
		return out
	var dc: Dictionary = cfg.get("detour", {})
	var n := int((dc.get("guard_by_tier", {}) as Dictionary).get(str(clampi(tier, 1, 4)), 0))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(fort_id) * 47 + 7211
	var room: int = site["room"]
	var inner := (layout["rooms"][room] as Rect2).grow(-30.0)
	var spread := float(dc.get("guard_spread_px", 50.0))
	for i in n:
		var pos: Vector2 = site["pos"]
		for attempt in 12:
			var c: Vector2 = (site["pos"] as Vector2) + Vector2(rng.randf_range(-spread, spread), rng.randf_range(-spread, spread))
			c = Vector2(clampf(c.x, inner.position.x, inner.end.x), clampf(c.y, inner.position.y, inner.end.y))
			pos = c
			if not _in_walls(layout, c, 14.0):
				break
		out.append({"kind": RaidLogic.roll_enemy_kind(rng, tier, cfg, fort_id), "pos": pos, "room": room})
	return out


## `p` kept inside `rc` shrunk by `inset` (by at most 0.4 of each side).
static func _clamp_in(rc: Rect2, p: Vector2, inset: float) -> Vector2:
	var ix := minf(inset, rc.size.x * 0.4)
	var iy := minf(inset, rc.size.y * 0.4)
	return Vector2(clampf(p.x, rc.position.x + ix, rc.end.x - ix), clampf(p.y, rc.position.y + iy, rc.end.y - iy))


## Shortest room path from `a` to `b` over layout.adj, both ends included ([] if none).
static func room_path(layout: Dictionary, a: int, b: int) -> Array[int]:
	var out: Array[int] = []
	if a < 0 or b < 0:
		return out
	var adj: Array = layout["adj"]
	var prev := {a: -1}
	var q: Array[int] = [a]
	var qi := 0
	while qi < q.size():
		var c: int = q[qi]
		qi += 1
		if c == b:
			break
		for nb in adj[c]:
			if not prev.has(nb):
				prev[nb] = c
				q.append(nb)
	if not prev.has(b):
		return out
	var at := b
	while at != -1:
		out.push_front(at)
		at = int(prev[at])
	return out


## Corpse piles scattered anywhere open. With an antechamber, the first pile is the last chance
## pile and sits inside the antechamber's inner rect.
static func populate_piles(fort_id: String, layout: Dictionary, count: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(fort_id) * 17 + 977
	var rooms: Array = layout["rooms"]
	var ante := int(layout.get("ante_room", -1))
	var out: Array = []
	for i in count:
		var room: Rect2 = rooms[ante] if (i == 0 and ante >= 0 and ante < rooms.size()) \
			else rooms[rng.randi_range(0, rooms.size() - 1)]
		var inner := room.grow(-60.0) if room.size.x > 180.0 and room.size.y > 180.0 else room.grow(-24.0)
		out.append(Vector2(rng.randf_range(inner.position.x, inner.end.x),
			rng.randf_range(inner.position.y, inner.end.y)))
	if bool(layout.get("first_dungeon", false)) and count >= 2:
		out[1] = first_pile(fort_id, layout)   # the antechamber pile (0) stays; this one is by the spawn
	return out


## The first dungeon's near-spawn pile: inside the spawn room's inner rect, `first_pile_min_px` to
## `first_pile_px` from the spawn (outside the stir radius, inside Relish's light, so it shows lit
## and she walks into it), clear of walls. Its own deterministic rng.
static func first_pile(fort_id: String, layout: Dictionary) -> Vector2:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(fort_id) * 29 + 4001
	var spawn: Vector2 = layout["spawn"]
	var rooms: Array = layout["rooms"]
	var room: Rect2 = rooms[maxi(0, room_of(layout, spawn))]
	var inner := room.grow(-60.0) if room.size.x > 180.0 and room.size.y > 180.0 else room.grow(-24.0)
	var lo := float(layout.get("first_pile_min_px", 120.0))
	var hi := float(layout.get("first_pile_px", 220.0))
	for attempt in 48:
		var p := spawn + Vector2(rng.randf_range(lo, hi), 0).rotated(rng.randf() * TAU)
		if inner.has_point(p) and not _in_walls(layout, p, 20.0):
			return p
	# crowded: walk the heading that stays in the room the longest (northwards first)
	var best := spawn
	var bd := -1.0
	for k in 32:
		var dir := Vector2(0, -1).rotated(TAU * float(k) / 32.0)
		for d in [hi * 0.8, hi * 0.6, lo * 1.1]:
			var p2: Vector2 = spawn + dir * d
			if inner.has_point(p2) and not _in_walls(layout, p2, 20.0) and d > bd:
				bd = d
				best = p2
	return best


static func _in_walls(layout: Dictionary, p: Vector2, pad: float) -> bool:
	for w in layout.get("walls", []):
		if (w as Rect2).grow(pad).has_point(p):
			return true
	return false


## Index into layout.doors of the exit whose inner point is within `radius` of p, nearest first; -1 if none.
static func near_exit(layout: Dictionary, p: Vector2, radius: float) -> int:
	var best := -1
	var bd := radius
	var doors: Array = layout.get("doors", [])
	for i in doors.size():
		if not bool(doors[i].get("exit", false)):
			continue
		var d := p.distance_to(doors[i]["inner"])
		if d <= bd:
			bd = d
			best = i
	return best


## Merge collinear wall rects that touch or overlap along their length into one, so closed doors
## and sealed gaps do not draw as separate segments (the wall shader fades each segment's ends,
## which reads as a door jamb where there is no door). Rects are merged only when they share an
## axis (horizontal: size.x >= size.y), the same thickness and the same line; a real gap between
## two rects keeps them apart, and perpendicular rects are never touched.
static func merge_walls(rects: Array) -> Array:
	var out: Array = rects.duplicate()
	var merged := true
	while merged:
		merged = false
		for i in out.size():
			for j in range(i + 1, out.size()):
				var m := _merge_pair(out[i], out[j])
				if not m.is_empty():
					out[i] = m[0]
					out.remove_at(j)
					merged = true
					break
			if merged:
				break
	return out


## [merged] when the two rects are flush on one axis, else [].
static func _merge_pair(a: Rect2, b: Rect2) -> Array:
	var eps := 0.01
	var ha := a.size.x >= a.size.y
	if ha != (b.size.x >= b.size.y):
		return []
	var lo_a := a.position.x if ha else a.position.y
	var lo_b := b.position.x if ha else b.position.y
	var len_a := a.size.x if ha else a.size.y
	var len_b := b.size.x if ha else b.size.y
	var off_a := a.position.y if ha else a.position.x
	var off_b := b.position.y if ha else b.position.x
	var th_a := a.size.y if ha else a.size.x
	var th_b := b.size.y if ha else b.size.x
	if absf(off_a - off_b) > eps or absf(th_a - th_b) > eps:
		return []
	if lo_a > lo_b + len_b + eps or lo_b > lo_a + len_a + eps:
		return []
	var lo := minf(lo_a, lo_b)
	var hi := maxf(lo_a + len_a, lo_b + len_b)
	return [Rect2(lo, off_a, hi - lo, th_a) if ha else Rect2(off_a, lo, th_a, hi - lo)]


## True when the wall rect borders or overlaps the room (the 2 px grow catches flush edges).
static func wall_touches_room(wall: Rect2, room: Rect2) -> bool:
	return wall.grow(2.0).intersects(room)


## Relish crossing into a checkpoint room: the room changed and the new one is a checkpoint.
static func checkpoint_entered(layout: Dictionary, prev_room: int, room: int) -> bool:
	return room >= 0 and room != prev_room and (layout.get("checkpoints", []) as Array).has(room)
