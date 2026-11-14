class_name TownSetPiece
extends RefCounted
## The town's set pieces, pure (no autoloads, no engine singletons), so tests run them:
##   the raise's collapse: the slab's rings morph point by point onto the creature's outline;
##   the named one's walk-out: where a big undead's place change sends it, the path maths, the trail,
##   the name badge's fade.


## `n` points spaced evenly along polyline `p` by length, both ends kept. A lone point repeats; an
## empty polyline gives nothing.
static func resample(p: PackedVector2Array, n: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	if p.is_empty() or n <= 0:
		return out
	var total := poly_len(p)
	if p.size() == 1 or total <= 0.0:
		for i in n:
			out.append(p[0])
		return out
	for i in n:
		out.append(point_at(p, total * float(i) / float(maxi(n - 1, 1))))
	return out


## Ease for the collapse: gathers speed as it falls in.
static func ease_in(k: float) -> float:
	var c := clampf(k, 0.0, 1.0)
	return c * c


## A ring of radius `r` split into one arc per outline stroke (arc lengths in proportion to the strokes'
## lengths, the first from straight up, clockwise), each morphed by `k` (0 = on the ring, 1 = on its stroke)
## and given `n` points: ring point i goes to stroke point i. At 0 the arcs join into the whole ring; at 1
## they are the outline. With no outline: one plain ring. Returns an Array of PackedVector2Array.
static func morph(c: Vector2, r: float, strokes: Array, k: float, n: int) -> Array:
	var out: Array = []
	var pts := maxi(n, 2)
	if strokes.is_empty():
		var ring := PackedVector2Array()
		for i in pts * 4:
			ring.append(c + Vector2.from_angle(-PI * 0.5 + TAU * float(i) / float(pts * 4 - 1)) * r)
		out.append(ring)
		return out
	var total := 0.0
	for s in strokes:
		total += poly_len(s)
	var a := -PI * 0.5
	for s in strokes:
		var span := TAU * (poly_len(s) / total if total > 0.0 else 1.0 / float(strokes.size()))
		var to := resample(s, pts)
		var arc := PackedVector2Array()
		for i in pts:
			var on := c + Vector2.from_angle(a + span * float(i) / float(pts - 1)) * r
			arc.append(on.lerp(to[i], clampf(k, 0.0, 1.0)))
		out.append(arc)
		a += span
	return out


static func poly_len(p: PackedVector2Array) -> float:
	var l := 0.0
	for i in range(1, p.size()):
		l += p[i - 1].distance_to(p[i])
	return l


## The point `s` px along `p` (clamped to its ends).
static func point_at(p: PackedVector2Array, s: float) -> Vector2:
	if p.is_empty():
		return Vector2.ZERO
	var left := maxf(s, 0.0)
	for i in range(1, p.size()):
		var l := p[i - 1].distance_to(p[i])
		if left <= l:
			return p[i - 1].lerp(p[i], left / l) if l > 0.0 else p[i]
		left -= l
	return p[p.size() - 1]


## The stretch of `p` from `s - length` to `s` (corners kept): a walker's trail.
static func trail(p: PackedVector2Array, s: float, length: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	if p.is_empty():
		return out
	var from := maxf(s - length, 0.0)
	out.append(point_at(p, from))
	var run := 0.0
	for i in range(1, p.size()):
		run += p[i - 1].distance_to(p[i])
		if run > from + 1e-6 and run < s - 1e-6:
			out.append(p[i])
	out.append(point_at(p, s))
	return out


## Distance walked after the gait moves from `g0` to `g1` steps (the agents' lockstep: whole steps of
## `step_px`, scaled by `mul`), capped at the path's `length`. The gait never runs backwards.
static func advance(d: float, g0: float, g1: float, step_px: float, mul: float, length: float) -> float:
	return minf(d + maxf(g1 - g0, 0.0) * step_px * mul, length)


## The name badge's opacity: none while it walks, then up over `fade_s` after it arrives. Reduced
## motion: whole at once on arrival.
static func badge_alpha(walking: bool, since_arrival_s: float, fade_s: float, reduced: bool) -> float:
	if walking:
		return 0.0
	if reduced or fade_s <= 0.0:
		return 1.0
	return clampf(since_arrival_s / fade_s, 0.0, 1.0)


## Which big undead start a walk. `prev` is uid -> place from the last look; `entries` the view's
## big_undead. A walk starts when an entry's place becomes `town:<lot>` (it was elsewhere, or it is new).
## The first look (`seeded` false) only records, so a loaded save does not walk. Returns
## {starts: [{uid, name, lot_id, from_lot}], prev: the places now}. `from_lot` is the building he was
## at ("" when he came from the crypt, a fort or the party, or is new), so a foreman moved between
## buildings walks from his old one.
static func transitions(prev: Dictionary, entries: Array, seeded: bool, slab := {}) -> Dictionary:
	var starts: Array = []
	var now := {}
	for e in entries:
		var uid := String(e.get("uid", ""))
		var place := String(e.get("place", ""))
		now[uid] = place
		if seeded and place.begins_with("town:") and String(prev.get(uid, "")) != place:
			var was := String(prev.get(uid, ""))
			starts.append({"uid": uid, "name": SlabLogic.display_name(e, slab) if not slab.is_empty() else String(e.get("name", "")), "lot_id": place.trim_prefix("town:"),
				"from_lot": was.trim_prefix("town:") if was.begins_with("town:") else ""})
	return {"starts": starts, "prev": now}
