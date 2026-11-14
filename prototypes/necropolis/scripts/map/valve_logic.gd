class_name ValveLogic
extends RefCounted
## Pure logic for the Covington valve panel (no autoloads, so headless tests compile it): the
## triangle's geometry (WORK bottom-left, WAR at the apex, FLOOD bottom-right; the handle's
## barycentric coordinates ARE the split), clamping a drag onto the triangle, corner snaps,
## integer percentages, the local projection of a dragged valve, the send throttle and the
## panel's row text. Tuning lives in configs/map_view.json ("valve_*" and "controls").

const KEYS := ["work", "war", "flood"]
const EPS := 1e-6


static func _c() -> Dictionary:
	return MapLogic.cfg().get("controls", {})


# --- geometry --------------------------------------------------------------------

static func height(side: float) -> float:
	return side * sqrt(3.0) * 0.5


## The three corners of the triangle of side `side`, in its own frame (top-left of the bounding
## box at the origin): {work, war, flood} points.
static func corners(side: float) -> Dictionary:
	return {"work": Vector2(0.0, height(side)), "war": Vector2(side * 0.5, 0.0), "flood": Vector2(side, height(side))}


## The point a valve {work, war, flood} (fractions) sits at.
static func point_of(valve: Dictionary, side: float) -> Vector2:
	var c := corners(side)
	var v := normalise(valve)
	return (c["work"] as Vector2) * v["work"] + (c["war"] as Vector2) * v["war"] + (c["flood"] as Vector2) * v["flood"]


## Raw barycentric coordinates of `p`: they sum to 1 and any is negative outside the triangle.
static func bary_of(p: Vector2, side: float) -> Dictionary:
	var c := corners(side)
	var a: Vector2 = c["work"]
	var v0: Vector2 = (c["war"] as Vector2) - a
	var v1: Vector2 = (c["flood"] as Vector2) - a
	var v2 := p - a
	var d00 := v0.dot(v0)
	var d01 := v0.dot(v1)
	var d11 := v1.dot(v1)
	var d20 := v2.dot(v0)
	var d21 := v2.dot(v1)
	var den := d00 * d11 - d01 * d01
	if absf(den) < EPS:
		return {"work": 1.0, "war": 0.0, "flood": 0.0}
	var war := (d11 * d20 - d01 * d21) / den
	var flood := (d00 * d21 - d01 * d20) / den
	return {"work": 1.0 - war - flood, "war": war, "flood": flood}


static func is_inside(p: Vector2, side: float) -> bool:
	var b := bary_of(p, side)
	return b["work"] >= -EPS and b["war"] >= -EPS and b["flood"] >= -EPS


## `p` itself inside the triangle, else the nearest point on its boundary.
static func clamp_point(p: Vector2, side: float) -> Vector2:
	if is_inside(p, side):
		return p
	var c := corners(side)
	var pts: Array = [c["work"], c["war"], c["flood"]]
	var best: Vector2 = pts[0]
	var best_d := INF
	for i in 3:
		var q := Geometry2D.get_closest_point_to_segment(p, pts[i], pts[(i + 1) % 3])
		var d := p.distance_squared_to(q)
		if d < best_d:
			best_d = d
			best = q
	return best


## The valve a (possibly outside) point means: clamped onto the triangle, shares in 0..1 summing to 1.
static func valve_at(p: Vector2, side: float) -> Dictionary:
	return normalise(bary_of(clamp_point(p, side), side))


## 100% of one corner ("work", "war" or "flood"); two zeros, which the API accepts.
static func snap(key: String) -> Dictionary:
	var out := {"work": 0.0, "war": 0.0, "flood": 0.0}
	if out.has(key):
		out[key] = 1.0
	return out


## Negatives and non-finite shares become 0, then the three sum to 1. All-zero falls back to WORK.
static func normalise(valve: Dictionary) -> Dictionary:
	var out := {}
	var sum := 0.0
	for k in KEYS:
		var x := float(valve.get(k, 0.0))
		out[k] = x if (is_finite(x) and x > 0.0) else 0.0
		sum += out[k]
	if sum <= EPS:
		return snap("work")
	for k in KEYS:
		out[k] = out[k] / sum
	return out


## Whole percentages that sum to exactly 100 (largest remainder).
static func percents(valve: Dictionary) -> Dictionary:
	var v := normalise(valve)
	var out := {}
	var left := 100
	var rem: Array = []
	for k in KEYS:
		var raw: float = v[k] * 100.0
		out[k] = int(floor(raw + EPS))
		left -= int(out[k])
		rem.append([raw - floor(raw + EPS), k])
	rem.sort_custom(func(a, b): return a[0] > b[0])
	for i in clampi(left, 0, rem.size()):
		out[rem[i][1]] += 1
	return out


## True when two valves agree to within `eps` per share.
static func same(a: Dictionary, b: Dictionary, eps: float) -> bool:
	for k in KEYS:
		if absf(float(a.get(k, 0.0)) - float(b.get(k, 0.0))) > eps:
			return false
	return true


# --- projection ------------------------------------------------------------------

static func mint_rate(hud: Dictionary) -> float:
	for r in hud.get("rates", []):
		if str(r.get("id", "")) == "mint":
			return float(r.get("rate", 0.0))
	return 0.0


## What the dragged valve would do: {split, workers_steady, war_supports: {n, m}}.
## split = mint x share; workers_steady is the view's, scaled by the WORK share against the
## committed one (unscaled when that is 0: there is nothing to scale from); war_supports is a stub.
# TODO(api-request #7): view_projection(valve)
static func project(hud: Dictionary, valve: Dictionary, held_count := 0) -> Dictionary:
	var v := normalise(valve)
	var mint := mint_rate(hud)
	var split := {}
	for k in KEYS:
		split[k] = mint * v[k]
	var steady := float(hud.get("workers_steady", 0.0))
	var cur_work := float(hud.get("valve", {}).get("work", 0.0))
	if cur_work > EPS:
		steady *= v["work"] / cur_work
	return {"split": split, "workers_steady": steady, "war_supports": {"n": 0, "m": held_count}}


# --- sending ---------------------------------------------------------------------

## The throttle for commands during a drag: at most `hz` per second, and always on release.
## `last_sent_s` < 0 means nothing was sent yet in this drag.
static func should_send(now_s: float, last_sent_s: float, hz: float, released: bool) -> bool:
	if released:
		return true
	if hz <= 0.0:
		return false
	return last_sent_s < 0.0 or now_s - last_sent_s >= 1.0 / hz


# --- panel text ------------------------------------------------------------------

const NAMES := {"work": "WORK", "war": "WAR", "flood": "FLOOD"}


## One row per stream in WORK, WAR, FLOOD order: {key, name, pct_text, rate_text, feed_text}.
static func rows(proj: Dictionary, valve: Dictionary) -> Array:
	var pct := percents(valve)
	var feeds: Dictionary = _c().get("valve_feeds", {})
	var out: Array = []
	for k in KEYS:
		out.append({"key": k, "name": NAMES[k], "pct_text": "%d%%" % int(pct[k]),
			"rate_text": MapLogic.fmt_rate(float(proj["split"][k])), "feed_text": str(feeds.get(k, ""))})
	return out


## "workers → 61" under WORK.
static func workers_text(proj: Dictionary) -> String:
	return str(_c().get("valve_workers_fmt", "%s")) % MapLogic.fmt_mass(float(proj["workers_steady"]))


## "WAR supports 0 of 3 held forts", or "" when no fort is held.
static func supports_text(proj: Dictionary) -> String:
	var s: Dictionary = proj["war_supports"]
	if int(s["m"]) <= 0:
		return ""
	return str(_c().get("valve_supports_fmt", "")) % [int(s["n"]), int(s["m"])]
