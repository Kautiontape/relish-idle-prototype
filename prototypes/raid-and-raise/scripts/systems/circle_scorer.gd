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

## Returns {valid, score (0-100), center, radius, dev_frac, gap_frac, swept_deg}.
static func grade(points: PackedVector2Array) -> Dictionary:
	var cfg: Dictionary = ConfigDb.data["circle"]
	var bad := {"valid": false, "score": 0, "center": Vector2.ZERO, "radius": 0.0,
		"dev_frac": 1.0, "gap_frac": 1.0, "swept_deg": 0.0}
	if points.size() < int(cfg["min_points"]):
		return bad
	var f := fit(points)
	if not f["valid"]:
		return bad
	var center: Vector2 = f["center"]
	var radius: float = f["radius"]
	if radius < 8.0:
		return bad

	var dev_sum := 0.0
	for p in points:
		dev_sum += absf(p.distance_to(center) - radius)
	var dev_frac := (dev_sum / points.size()) / radius

	var gap_frac := points[0].distance_to(points[points.size() - 1]) / radius

	var swept := 0.0
	var prev_ang := (points[0] - center).angle()
	for i in range(1, points.size()):
		var ang := (points[i] - center).angle()
		swept += absf(wrapf(ang - prev_ang, -PI, PI))
		prev_ang = ang
	var swept_deg := rad_to_deg(swept)

	var dev_pen := clampf(dev_frac / float(cfg["dev_penalty_at_frac"]), 0.0, 1.0)
	var closure_pen := clampf(gap_frac / float(cfg["closure_penalty_at_frac"]), 0.0, 1.0)
	var base := clampf(1.0 - float(cfg["dev_weight"]) * dev_pen - float(cfg["closure_weight"]) * closure_pen, 0.0, 1.0)
	var coverage := clampf(swept_deg / float(cfg["min_arc_deg"]), 0.0, 1.0)
	var score := roundi(100.0 * base * coverage * coverage)

	return {"valid": true, "score": score, "center": center, "radius": radius,
		"dev_frac": dev_frac, "gap_frac": gap_frac, "swept_deg": swept_deg}

## Circle score → chaff stat multiplier: 0.5 + score/100 (§11).
static func multiplier(score: int) -> float:
	var cfg: Dictionary = ConfigDb.data["circle"]
	return float(cfg["multiplier_base"]) + float(cfg["multiplier_per_100"]) * score / 100.0
