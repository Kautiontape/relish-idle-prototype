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


## The workforce the town actually settles at: the view's workers_steady_kept when it has one (not
## while dragging: that is the committed valve's), else min(slots + idle_cap, steady), the idle
## beyond the cap mustering to WAR (MECHANICS 4.1). `slots` sums view_town().jobs' slots;
## `idle_cap` is economy.json worker.idle_cap.
# TODO(api-request #12): view_hud.workers_steady_kept
static func workers_kept(steady: float, hud: Dictionary, slots: int, idle_cap: float, dragging := false) -> float:
	if hud.has("workers_steady_kept") and not dragging:
		return float(hud["workers_steady_kept"])
	return minf(float(slots) + idle_cap, steady)


## "workers → 61" under WORK (`kept` from workers_kept).
static func workers_text(kept: float) -> String:
	return str(_c().get("valve_workers_fmt", "%s")) % MapLogic.fmt_mass(kept)


# --- WAR overflow ------------------------------------------------------------------

## WAR that overflows to Vei once every WAR target is capped (mass/s): while dragging, the
## projection's split.war_overflow when it has one; else view_hud.war_overflow; else the
## war:covington:vei lane's rate (that lane exists only while the overflow is > 0); else 0.
# TODO(api E2b): view_hud.war_overflow, view_projection(valve).split.war_overflow
static func war_overflow(hud: Dictionary, lanes: Array, proj: Dictionary, dragging: bool) -> float:
	if dragging and proj.get("split", {}).has("war_overflow"):
		return float(proj["split"]["war_overflow"])
	if hud.has("war_overflow"):
		return float(hud["war_overflow"])
	for r in lanes:
		if str(r.get("kind", "")) == "war" and str(r.get("from", "")) == "covington" and str(r.get("to", "")) == "vei":
			return float(r.get("rate", 0.0))
	return 0.0


## The WAR row's overflow line, {rate: "+3.1/s", text: "overflows to Vei"}, or {} with none.
static func overflow_parts(overflow: float) -> Dictionary:
	if overflow <= 0.0:
		return {}
	return {"rate": MapLogic.fmt_rate(overflow), "text": str(_c().get("valve_overflow_text", ""))}


# --- the payoff ---------------------------------------------------------------------

## Vei's differential (mass/s) at a dragged valve: view_projection(valve).backlog_diff when the
## projection has it; else the stand-in diff_ema + Δflood + Δwar x war_drain_frac, the deltas
## measured between this projection's split and the same projection at the current valve
## (`base_split`), so a drag back onto the current valve changes nothing.
# TODO(api-request #7): view_projection(valve).backlog_diff
static func diff_at(diff_ema: float, proj: Dictionary, base_split: Dictionary, war_drain_frac: float) -> float:
	if proj.has("backlog_diff"):
		return float(proj["backlog_diff"])
	var split: Dictionary = proj.get("split", {})
	return diff_ema + (float(split.get("flood", 0.0)) - float(base_split.get("flood", 0.0))) \
		+ (float(split.get("war", 0.0)) - float(base_split.get("war", 0.0))) * war_drain_frac


## Drain time at a differential: backlog / -diff while it shrinks, else -1.0 (holding, "∞").
static func drain_at(backlog: float, diff: float) -> float:
	return backlog / -diff if diff < 0.0 else -1.0


## Odds after `window_s` at a differential: b / (b + K) with b = max(backlog + diff x window, 0).
static func odds_at(backlog: float, diff: float, window_s: float, k: float) -> float:
	var b := maxf(backlog + diff * window_s, 0.0)
	return b / (b + k) if b + k > 0.0 else 0.0


## Now against the dragged valve: {now: {diff, drain_s, odds}, then: {...}}. Both sides use the
## same formulas; `now` is the current differential (diff_ema), `then` diff_at's.
static func payoff(vei: Dictionary, proj: Dictionary, base_split: Dictionary, k: float) -> Dictionary:
	var c := _c()
	var backlog := float(vei.get("backlog", 0.0))
	var window := float(c["drain_window_s"])
	var out := {}
	var diffs := {"now": float(vei.get("diff_ema", 0.0)), "then": diff_at(float(vei.get("diff_ema", 0.0)), proj, base_split, float(c["war_drain_frac"]))}
	for side in diffs:
		var d: float = diffs[side]
		out[side] = {"diff": d, "drain_s": drain_at(backlog, d), "odds": odds_at(backlog, d, window, k)}
	return out


## The payoff as one line: "Vei ▲ +2.1/s → ▲ +4.0/s" then "drain ∞ → 8m 40s" when either side
## drains, else "odds in 10 min 61% → 64%". `sign_eps` is realm.json readout.sign_eps.
static func payoff_line(p: Dictionary, sign_eps: float) -> String:
	var c := _c()
	var now: Dictionary = p["now"]
	var then: Dictionary = p["then"]
	var vei := str(c["payoff_vei_fmt"]) % [_sign_of(float(now["diff"]), sign_eps), MapLogic.fmt_rate(float(now["diff"])),
		_sign_of(float(then["diff"]), sign_eps), MapLogic.fmt_rate(float(then["diff"]))]
	var second := ""
	if float(now["drain_s"]) >= 0.0 or float(then["drain_s"]) >= 0.0:
		second = str(c["payoff_drain_fmt"]) % [MapLogic.fmt_drain(float(now["drain_s"])), MapLogic.fmt_drain(float(then["drain_s"]))]
	else:
		second = str(c["payoff_odds_fmt"]) % [str(c["payoff_window_text"]), roundi(float(now["odds"]) * 100.0), roundi(float(then["odds"]) * 100.0)]
	return vei + str(c["payoff_sep"]) + second


## What the drag gives up, one part per stream whose dragged split rate is lower than at the current
## valve (`base_split`) by more than `sign_eps`: "workers +5.1/s → +1.5/s" (WORK), "WAR +9.7/s →
## +2.0/s" (WAR), then, when WAR fell and a fort is held, "WAR supports 1 of 2". Empty when the drag
## only raises WORK and WAR.
static func payoff_costs(proj: Dictionary, base_split: Dictionary, sign_eps: float) -> Array:
	var c := _c()
	var split: Dictionary = proj.get("split", {})
	var out: Array = []
	var war_fell := false
	for pair in [["work", "payoff_work_fmt"], ["war", "payoff_war_fmt"]]:
		var was := float(base_split.get(pair[0], 0.0))
		var now := float(split.get(pair[0], 0.0))
		if now < was - sign_eps:
			out.append(str(c[pair[1]]) % [MapLogic.fmt_rate(was), MapLogic.fmt_rate(now)])
			war_fell = war_fell or pair[0] == "war"
	var sup: Dictionary = proj.get("war_supports", {})
	if war_fell and int(sup.get("m", 0)) > 0:
		out.append(str(c["payoff_supports_fmt"]) % [int(sup.get("n", 0)), int(sup.get("m", 0))])
	return out


## Which payoff row each part goes on (0 or 1). `widths` are the parts' widths, the first being the
## differential and the odds or drain; `sep_w` the separator's; `max_w` the panel's inner width. All
## on row 0 when they fit, else the first part stays and the costs wrap whole onto row 1, at the
## separator before the first cost: a part is never broken.
static func payoff_rows(widths: Array, sep_w: float, max_w: float) -> Array:
	var out: Array = []
	var total := 0.0
	for i in widths.size():
		total += float(widths[i]) + (sep_w if i > 0 else 0.0)
	var fits := total <= max_w + EPS
	for i in widths.size():
		out.append(0 if (fits or i == 0) else 1)
	return out


static func _sign_of(diff: float, eps: float) -> String:
	return MapLogic.sign_glyph(1 if diff > eps else (-1 if diff < -eps else 0))


## Whether the payoff shows: while dragging, and for payoff_hold_s after the release
## (`since_release_s` < 0: never released this session).
static func payoff_shown(dragging: bool, since_release_s: float) -> bool:
	return dragging or (since_release_s >= 0.0 and since_release_s < float(_c()["payoff_hold_s"]))


# --- the "now" ring -----------------------------------------------------------------

## Where the hollow "now" ring is drawn: at `cur`, or now_offset_px up-right of the target when
## the two are closer than that, so a zero slew is still visible.
static func now_ring_pos(cur: Vector2, target: Vector2) -> Vector2:
	var off := float(_c()["now_offset_px"])
	if cur.distance_to(target) < off:
		return target + Vector2(1.0, -1.0).normalized() * off
	return cur


## "WAR supports 0 of 3 held forts", or "" when no fort is held.
static func supports_text(proj: Dictionary) -> String:
	var s: Dictionary = proj["war_supports"]
	if int(s["m"]) <= 0:
		return ""
	return str(_c().get("valve_supports_fmt", "")) % [int(s["n"]), int(s["m"])]
