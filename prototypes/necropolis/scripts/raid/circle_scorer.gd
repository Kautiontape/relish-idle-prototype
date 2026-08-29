class_name CircleScorer
extends RefCounted
## Least-squares circle fit (Kåsa method) + 0–100 trace grading (§8.2).
## Score combines mean radial deviation, closure quality, and angular coverage
## (coverage stops straight lines from grading as giant perfect arcs).

## Fit x² + y² = a·x + b·y + c, center = (a/2, b/2), r = sqrt(c + a²/4 + b²/4).
static func fit(points: PackedVector2Array) -> Dictionary:
	var n := points.size()
	if n < 3:
		return {"valid": false}
	var sx := 0.0; var sy := 0.0; var sxx := 0.0; var syy := 0.0; var sxy := 0.0
	var sxz := 0.0; var syz := 0.0; var sz := 0.0
	for p in points:
		var z := p.x * p.x + p.y * p.y
		sx += p.x; sy += p.y
		sxx += p.x * p.x; syy += p.y * p.y; sxy += p.x * p.y
		sxz += p.x * z; syz += p.y * z; sz += z
	# Normal equations: [sxx sxy sx; sxy syy sy; sx sy n] * [a b c] = [sxz syz sz]
	var m := [
		[sxx, sxy, sx, sxz],
		[sxy, syy, sy, syz],
		[sx, sy, float(n), sz],
	]
	if not _gauss_solve(m):
		return {"valid": false}
	var a: float = m[0][3]
	var b: float = m[1][3]
	var c: float = m[2][3]
	var r2 := c + (a * a + b * b) / 4.0
	if r2 <= 0.0:
		return {"valid": false}
	return {"valid": true, "center": Vector2(a / 2.0, b / 2.0), "radius": sqrt(r2)}

static func _gauss_solve(m: Array) -> bool:
	for col in 3:
		var pivot := col
		for row in range(col + 1, 3):
			if absf(m[row][col]) > absf(m[pivot][col]):
				pivot = row
		if absf(m[pivot][col]) < 1e-9:
			return false
		var tmp: Array = m[col]; m[col] = m[pivot]; m[pivot] = tmp
		for row in range(col + 1, 3):
			var f: float = m[row][col] / m[col][col]
			for k in range(col, 4):
				m[row][k] -= f * m[col][k]
	for col in [2, 1, 0]:
		for k in range(col + 1, 3):
			m[col][3] -= m[col][k] * m[k][3]
		m[col][3] /= m[col][col]
	return true

## The completion point: nobody lands their finger back exactly on the start.
## Once the stroke has swept most of the way around, we find where it came
## CLOSEST to the start — that's the loop they meant to draw. Everything after
## is a sloppy tail (lift-off drift), graded separately and gently, never as a
## giant closure gap. Returns the index of that completion point.
static func _completion_index(points: PackedVector2Array, center: Vector2) -> int:
	var cfg: Dictionary = ConfigDb.data["circle"]
	var seal_arc := deg_to_rad(float(cfg.get("seal_arc_deg", 270.0)))
	var start: Vector2 = points[0]
	var swept := 0.0
	var prev_ang := (points[0] - center).angle()
	var best_i := points.size() - 1
	var best_d := INF
	var sealed := false
	for i in range(1, points.size()):
		var ang := (points[i] - center).angle()
		swept += absf(wrapf(ang - prev_ang, -PI, PI))
		prev_ang = ang
		if swept >= seal_arc:
			var d := points[i].distance_to(start)
			if d < best_d:
				best_d = d
				best_i = i
				sealed = true
	return best_i if sealed else points.size() - 1

## Returns {valid, score (0-100), center, radius, dev_frac, gap_frac, swept_deg,
## tail_frac}. Grades the sealed loop (start..completion); a stop-short circle
## is judged on how close its closest approach got, not on the literal endpoint.
static func grade(points: PackedVector2Array) -> Dictionary:
	var cfg: Dictionary = ConfigDb.data["circle"]
	var bad := {"valid": false, "score": 0, "center": Vector2.ZERO, "radius": 0.0,
		"dev_frac": 1.0, "gap_frac": 1.0, "swept_deg": 0.0, "tail_frac": 0.0}
	if points.size() < int(cfg["min_points"]):
		return bad
	var f0 := fit(points)
	if not f0["valid"]:
		return bad

	# Seal off the tail, then refit on the loop alone so a long tail can't drag
	# the fitted circle (which also picks the enclosed essence).
	var seal_i := _completion_index(points, f0["center"])
	var loop: PackedVector2Array = points.slice(0, seal_i + 1)
	if loop.size() < 3:
		loop = points
		seal_i = points.size() - 1
	var f := fit(loop)
	if not f["valid"]:
		f = f0
	var center: Vector2 = f["center"]
	var radius: float = f["radius"]
	if radius < 8.0:
		return bad

	var dev_sum := 0.0
	for p in loop:
		dev_sum += absf(p.distance_to(center) - radius)
	var dev_frac := (dev_sum / loop.size()) / radius

	# Best closure: the closest the loop ever got back to its start (stopping a
	# little short barely costs you), not the post-release endpoint.
	var gap_frac := loop[loop.size() - 1].distance_to(loop[0]) / radius

	var swept := 0.0
	var prev_ang := (loop[0] - center).angle()
	for i in range(1, loop.size()):
		var ang := (loop[i] - center).angle()
		swept += absf(wrapf(ang - prev_ang, -PI, PI))
		prev_ang = ang
	var swept_deg := rad_to_deg(swept)

	# The tail: length of stroke past the completion point, as a fraction of the
	# circumference. Punished gently (tail_weight is small) — a flick-off on
	# release shouldn't tank an otherwise clean circle.
	var tail_len := 0.0
	for i in range(seal_i + 1, points.size()):
		tail_len += points[i].distance_to(points[i - 1])
	var tail_frac := tail_len / maxf(1.0, TAU * radius)

	var dev_pen := clampf(dev_frac / float(cfg["dev_penalty_at_frac"]), 0.0, 1.0)
	var closure_pen := clampf(gap_frac / float(cfg["closure_penalty_at_frac"]), 0.0, 1.0)
	var tail_pen := clampf(tail_frac / float(cfg.get("tail_penalty_at_frac", 0.6)), 0.0, 1.0)
	var base := clampf(1.0
		- float(cfg["dev_weight"]) * dev_pen
		- float(cfg["closure_weight"]) * closure_pen
		- float(cfg.get("tail_weight", 0.15)) * tail_pen, 0.0, 1.0)
	var coverage := clampf(swept_deg / float(cfg["min_arc_deg"]), 0.0, 1.0)
	var score := roundi(100.0 * base * coverage * coverage)

	return {"valid": true, "score": score, "center": center, "radius": radius,
		"dev_frac": dev_frac, "gap_frac": gap_frac, "swept_deg": swept_deg,
		"tail_frac": tail_frac}

## Circle score → chaff stat multiplier: 0.5 + score/100 (§11).
static func multiplier(score: int) -> float:
	var cfg: Dictionary = ConfigDb.data["circle"]
	return float(cfg["multiplier_base"]) + float(cfg["multiplier_per_100"]) * score / 100.0
