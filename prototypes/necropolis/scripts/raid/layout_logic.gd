class_name LayoutLogic
extends RefCounted
## Pure fortress layout logic: the seeded generator, room roles, doors, reachability, placement
## and wall helpers. No scene-tree or autoload dependencies. RaidLogic keeps one-line delegates
## for the entry points, so callers and tests can use either.


# ------------------------------------------------------ layout generation ----
## Deterministic per fort_id (and `opts`): each fortress is recognizably itself on revisits.
## `opts`: `held` (bool, ignored for the boss arena): the player's held fort, which gets one
## fewer room and no warden or antechamber.
## Returns { size, wall_t, walls (all Rect2), inner_walls, doors, rooms, spawn, boss, gaps, held,
## roles (per room: spawn / checkpoint / antechamber / warden / normal), hops (BFS from the spawn
## room), adj (room adjacency), warden_room and ante_room (-1 if none), checkpoints (room indices,
## spawn first) }. Every door is an exit {side, rect, center, inner, exit: true, room}; closed
## doors are drawn as wall.
static func gen_layout(fort_id: String, tier: int, is_boss: bool, cfg: Dictionary, opts: Dictionary = {}) -> Dictionary:
	var lay: Dictionary = cfg.get("layout", {})
	var held := bool(opts.get("held", false)) and not is_boss
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(fort_id)
	var last := {}
	for attempt in 8:
		var cand := _gen_once(rng, tier, is_boss, lay, held)
		if cand.is_empty():
			continue   # role assignment failed; the rng has moved on
		last = cand
		if layout_reachable(cand, float(lay.get("grid_cell", 32.0))):
			return cand
	if last.is_empty():
		# every attempt failed to place a warden room: fall back to a held-style layout
		last = _gen_once(rng, tier, is_boss, lay, true)
	return last


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
	for r in rooms:
		var d: float = (r as Rect2).get_center().distance_to(spawn)
		var wt := pow(maxf(d, 40.0), 1.5)
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
		out.append({"kind": RaidLogic.roll_enemy_kind(rng, tier, cfg), "pos": pos, "room": ri})
	return out


## Corpse piles scattered anywhere open.
static func populate_piles(fort_id: String, layout: Dictionary, count: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(fort_id) * 17 + 977
	var rooms: Array = layout["rooms"]
	var out: Array = []
	for i in count:
		var room: Rect2 = rooms[rng.randi_range(0, rooms.size() - 1)]
		var inner := room.grow(-60.0) if room.size.x > 180.0 and room.size.y > 180.0 else room.grow(-24.0)
		out.append(Vector2(rng.randf_range(inner.position.x, inner.end.x),
			rng.randf_range(inner.position.y, inner.end.y)))
	return out


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


## True when the wall rect borders or overlaps the room (the 2 px grow catches flush edges).
static func wall_touches_room(wall: Rect2, room: Rect2) -> bool:
	return wall.grow(2.0).intersects(room)


## Relish crossing into a checkpoint room: the room changed and the new one is a checkpoint.
static func checkpoint_entered(layout: Dictionary, prev_room: int, room: int) -> bool:
	return room >= 0 and room != prev_room and (layout.get("checkpoints", []) as Array).has(room)
