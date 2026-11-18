class_name SetpieceLogic
extends RefCounted
## Pure timing for the map's set pieces (VISUAL-LANGUAGE 2e; no autoloads, so headless tests
## compile it): the valve swing, the flip (and the first flip's larger treatment), the tithe tide,
## the garrison cleared and victory. Each runs on the tempo: its clock is beats since it started,
## from Pulse's wall clock and tempo (passed in), divided by the debug --setpiece-slow factor, so
## it elapses under reduced motion too, where each one goes straight to its end state.
## Tuning: configs/map_view.json "setpieces".

const VALVE := "valve"
const FLIP := "flip"
const FIRST_FLIP := "first_flip"
const TITHE := "tithe"
const GARRISON := "garrison"
const VICTORY := "victory"
const RETREAT := "retreat"  # back from a raid that left the fort Vei's: one callout line
const KINDS := [VALVE, FLIP, FIRST_FLIP, TITHE, GARRISON, VICTORY, RETREAT]
const TAKEN := "taken"  # return_kind: the raid took the fort (its set piece is FLIP or FIRST_FLIP)
const RUN := "run"    # victory: every lane green, running toward Vei
const STOP := "stop"  # victory: every dash frozen, the victory line up
const NONE := Vector2(-1.0, -1.0)  # no band this frame


static func cfg() -> Dictionary:
	return MapLogic.cfg().get("setpieces", {})


static func _n(key: String) -> float:
	return float(cfg()[key])


static func _s(key: String) -> String:
	return str(cfg()[key])


# --- the clock ------------------------------------------------------------------------------

## Beats since `start_ms` on Pulse's clock (`now_ms`, `tempo_ms`), stretched by the debug slow factor.
static func beats(start_ms: float, now_ms: float, tempo_ms: float, slow := 1.0) -> float:
	return maxf(now_ms - start_ms, 0.0) / maxf(tempo_ms, 1.0) / maxf(slow, 0.001)


## The beat number at hop 0 (Covington): the tempo pulse sounds when it changes. Taken from the
## clock, not Pulse.phase, so reduced motion (a steady phase) never silences it.
static func beat_index(now_ms: float, tempo_ms: float) -> int:
	return floori(now_ms / maxf(tempo_ms, 1.0))


# --- the valve swing ------------------------------------------------------------------------

## Covington's stem shares `t` beats into a swing from `from` to `to`: the dive's in-out ease over
## valve_beats; reduced motion snaps to `to`.
static func valve_shares(from: Dictionary, to: Dictionary, t: float, reduced: bool) -> Dictionary:
	var e := 1.0 if reduced else TransitionLogic.ease_t(t / _n("valve_beats"), _n("valve_ease_power"))
	var out := {}
	for k in ValveLogic.KEYS:
		out[k] = lerpf(float(from.get(k, 0.0)), float(to.get(k, 0.0)), e)
	return out


## How much brighter the stems draw (1 at the commit, 0 after the beat): fading over the beat, or
## held for the beat under reduced motion (a step, not a motion).
static func valve_bright(t: float, reduced: bool) -> float:
	var d := _n("valve_beats")
	if t >= d:
		return 0.0
	return 1.0 if reduced else 1.0 - t / d


static func valve_done(t: float) -> bool:
	return t >= _n("valve_beats")


## True when two valves differ by more than valve_eps in any share.
static func valve_moved(a: Dictionary, b: Dictionary) -> bool:
	for k in ValveLogic.KEYS:
		if absf(float(a.get(k, 0.0)) - float(b.get(k, 0.0))) > _n("valve_eps"):
			return true
	return false


# --- the flip -------------------------------------------------------------------------------

## How many of the ring's reink_segments have turned green `t` beats in: one more each
## reink_beats / reink_segments, the last exactly at reink_beats; all at once under reduced motion.
static func reink_count(t: float, reduced: bool) -> int:
	var n := int(_n("reink_segments"))
	if reduced:
		return n
	return clampi(floori(n * t / _n("reink_beats")), 0, n)


static func reink_done(t: float, reduced: bool) -> bool:
	return reduced or t >= _n("reink_beats")


## Segment `i` of `n` around a ring, in order from 12 o'clock clockwise (screen y is down): its
## start and end angles.
static func segment_arc(i: int, n: int) -> Vector2:
	var w := TAU / maxf(n, 1)
	return Vector2(-PI * 0.5 + w * i, -PI * 0.5 + w * (i + 1))


## What the set pieces keep from events, after a catch-up (away_report; its events went into the report
## and replay nothing). `taken_ids` are the forts whose fort_flipped the map heard: a fort Vei retook
## inside the catch-up is no longer one the player took, so only those still held stay. `victory`: the
## realm is won now, which the swallowed vei_result would have played, and it hasn't (`won_played`).
## Returns {taken_ids, victory}.
static func after_away(taken_ids: Array, forts: Array, won_played: bool, hud_won: bool) -> Dictionary:
	var held := {}
	for f in forts:
		if bool(f.get("held", false)):
			held[str(f.get("id", ""))] = true
	return {"taken_ids": taken_ids.filter(func(id): return held.has(str(id))), "victory": hud_won and not won_played}


## Whether `fort_id`'s flip is the game's first: no other fort has ever flipped and this one at most
## once. That holds whether the views already count this flip or not yet.
static func first_flip(fort_id: String, forts: Array) -> bool:
	for f in forts:
		var c := int(f.get("flipped_count", 0))
		if str(f.get("id", "")) == fort_id:
			if c > 1:
				return false
		elif c > 0:
			return false
	return true


static func first_flip_text(fort_name: String) -> String:
	return _s("first_flip_fmt") % fort_name


## The map's last dive into a fort: {fort, held} (held when Relish dove), or {}. Static so it
## outlives the map scene, which is freed during the raid (as MapHud._next does).
static var _last_dive := {}


## The map dove into `fort_id` (an empty id, for Covington or Vei, records nothing to match) while the
## fort was `held` or not. Only the last dive is kept.
static func note_dive(fort_id: String, held: bool) -> void:
	_last_dive = {"fort": fort_id, "held": held}


## What the map says on mounting after a scene: TAKEN, RETREAT or "" (no line). `arrive_from` is the
## node just left, `fort` its view (empty for Covington, Vei or none), `taken_event` whether the
## router replayed this fort's fort_flipped, `relish` view_relish, `dive` note_dive's record (default
## the last one). A real event is always taken. Without one, a fort held within its grace counts as
## taken (the no-snapshot swap can deliver fort_flipped after the map mounts), unless it was already
## held when Relish dove: that raid took nothing, so it says nothing. No record for this fort (a
## harness teleport that never dove from the map) allows the fallback. A fort still Vei's with Relish
## alive is a retreat (she keeps what she found); a death, a held fort past its grace and any other
## scene say nothing.
static func return_kind(arrive_from: String, fort: Dictionary, taken_event: bool, relish: Dictionary, dive := _last_dive) -> String:
	if arrive_from == "" or fort.is_empty() or str(fort.get("id", "")) != arrive_from:
		return ""
	if taken_event:
		return TAKEN
	var held := bool(fort.get("held", false))
	if held:
		var was_held := str(dive.get("fort", "")) == arrive_from and bool(dive.get("held", false))
		return TAKEN if float(fort.get("grace_s_left", 0.0)) > 0.0 and not was_held else ""
	if float(relish.get("dead_s_left", 0.0)) > 0.0 or str(relish.get("state", "")) == "dead":
		return ""
	return RETREAT


## The return line for `kind` (TAKEN or RETREAT) at a fort named `fort_name`; "" for any other kind.
static func return_text(kind: String, fort_name: String) -> String:
	match kind:
		TAKEN:
			return _s("taken_fmt") % fort_name
		RETREAT:
			return _s("retreat_fmt") % fort_name
	return ""


# --- where a callout sits ---------------------------------------------------------------------
# Everything below is in one frame: world px x zoom (the layer's screen px, origin at the world
# origin), so a ring's radius, a label plate (screen px around its anchor) and a chip share a unit.

## `text` split at its first callout_split (": ") into its two lines, the colon kept on line one
## ("Old Sluice stays Vei's:" / "you kept all you found"); [] when it has none to split at.
static func split_text(text: String) -> Array:
	var sep := _s("callout_split")
	var i := text.find(sep)
	if i <= 0 or i + sep.length() >= text.length():
		return []
	return [text.substr(0, i) + sep.rstrip(" "), text.substr(i + sep.length())]


## A fort's name and tag plates in the frame (`zoom` x world): NodeLogic.fort_label_rects at the label
## anchor MapFortRing draws them from. `tag_w` < 0: no tag line. The same plates the lane callouts keep clear of.
static func fort_plates(pos: Vector2, tier: int, name_w: float, tag_w: float, zoom: float) -> Array:
	var at := (pos + Vector2(0.0, MapLogic.fort_radius(tier) + float(NodeLogic.ncfg()["label_off_px"]))) * zoom
	var out: Array = []
	for r in NodeLogic.fort_label_rects(name_w, tag_w, int(MapLogic.cfg()["font_label"])):
		out.append(Rect2(at + (r as Rect2).position, (r as Rect2).size))
	return out


## The screen a callout may sit in, in the frame: the viewport inset callout_edge_px on every side, from
## below the top bar (`top_inset` screen px) to above the bottom bars (`bottom_top`, the screen y they start at).
static func screen_bounds(viewport: Vector2, cam_pos: Vector2, zoom: float, top_inset: float, bottom_top: float) -> Rect2:
	var e := _n("callout_edge_px")
	var r := Rect2(e, top_inset + e, viewport.x - e * 2.0, bottom_top - top_inset - e * 2.0)
	return HudLogic.screen_to_zoomed(r, cam_pos, zoom, viewport)


## Covington's and Vei's obstacles (IdleLogic.node_obstacles, world px) in the zoomed frame: {circles:
## [Vector3], rects: [Rect2]}, their discs and plates (Covington's glyph, name and stream labels; Vei's reach and name).
static func node_hard(nodes: Array, zoom: float) -> Dictionary:
	var circles: Array = []
	var rects: Array = []
	for n in nodes:
		var p: Vector2 = n["pos"]
		circles.append(Vector3(p.x * zoom, p.y * zoom, float(n["r"]) * zoom))
		for r in n["rects"]:
			rects.append(Rect2((r as Rect2).position * zoom, (r as Rect2).size * zoom))
	return {"circles": circles, "rects": rects}


## The gap between two rects (0 when they touch or overlap).
static func rect_gap(a: Rect2, b: Rect2) -> float:
	var dx := maxf(maxf(a.position.x - b.end.x, b.position.x - a.end.x), 0.0)
	var dy := maxf(maxf(a.position.y - b.end.y, b.position.y - a.end.y), 0.0)
	return Vector2(dx, dy).length()


## The gap between a rect and a circle `c` (x, y, radius); negative once the rect reaches in.
static func circle_gap(r: Rect2, c: Vector3) -> float:
	var near := Vector2(clampf(c.x, r.position.x, r.end.x), clampf(c.y, r.position.y, r.end.y))
	return near.distance_to(Vector2(c.x, c.y)) - c.z


## The rects of a callout of lines `ws` (their text widths), centred on `cx`, the first line's
## baseline at `first_by`, each a label plate (NodeLogic.label_plate: pad, ascent and height).
static func callout_rects(cx: float, first_by: float, ws: Array, size: int, line := -1.0) -> Array:
	var out: Array = []
	var step := _n("callout_line_px") if line < 0.0 else line
	for i in ws.size():
		var w := float(ws[i])
		var r := NodeLogic.label_plate(-w * 0.5, w, size, 0.0)
		out.append(Rect2(r.position + Vector2(cx, first_by + float(i) * step), r.size))
	return out


static func _hard(rects: Array, obs: Array, clear: float) -> float:
	var total := 0.0
	for r in rects:
		for o in obs:
			if o is Rect2:
				var i: Rect2 = (r as Rect2).grow(clear).intersection(o)
				total += i.size.x * i.size.y
			else:
				var c: Vector3 = o
				if circle_gap(r, c) < clear:
					var box := Rect2(c.x - c.z, c.y - c.z, c.z * 2.0, c.z * 2.0).intersection((r as Rect2).grow(clear))
					total += maxf(box.size.x * box.size.y * PI * 0.25, 1.0)
	return total


static func _soft(rects: Array, soft: Array) -> float:
	var total := 0.0
	for r in rects:
		for o in soft:
			var i: Rect2 = (r as Rect2).intersection(o)
			total += i.size.x * i.size.y
	return total


## Where a set-piece callout sits for the fort at `fort` (ring radius `ring_r`), as the shared place
## for the retreat and the taken lines. `base_y` is the baseline of its last line when it stands
## above the fort (callout_gap_px over the rings, over Relish's token when she stands there: the
## place it has always had); `widths` {one, a, b}: the text on one line, and (when it splits at
## ": ") its two lines; `own` the fort's own rects: its name and tag plates, its chip, and
## Relish's token when she stands at it. `obs` {rings: [Vector3 x, y, r], circles: [Vector3], rects:
## [Rect2], soft: [Rect2]}: the HARD ones (every other fort's ring out to its outermost, Relish's
## halo, the name and tag plates, the held forts' chips) and the SOFT (the open card, lane callouts).
## Candidates in order: centred above; the same row slid by callout_slides x its width; the two-line
## form centred above, then slid; then the same under the fort's plates; then, only when those leave
## nothing clear and on screen, beside the fort's ring (right, then left; no need to cover its x). The first with no hard and no
## soft overlap wins, else the first with no hard overlap, else the least hard overlap. A candidate is
## only a candidate when it reads as the fort's: its nearest edge within callout_drift_px of the fort's
## ring or its own rects, its span covering the fort's x (callout_x_margin_px of play), and no other
## fort's ring nearer than its own. `obs.bounds` (the visible screen less the HUD bars) is hard too:
## a place not wholly inside is dropped before that filter, or, when none fits, the least off-screen
## one is taken. When nothing reads as the fort's, the least hard overlap wins, the nearer its own fort
## on a tie. `prev` ({form, place, slide} of the last choice): kept while still on screen, free of hard
## overlap and the fort's own, so a line up on screen never hops. Returns {form: "one"|"two", place:
## "above"|"below", slide, pos (centre x, first baseline), rects, size (the font of the form chosen),
## line (its line step), hard, soft}. `widths.size_two` (optional): the font the two-line form is set in
## (callout_font_two, measured into widths a and b), its line step scaled with it.
static func callout_place(fort: Vector2, ring_r: float, base_y: float, size: int, widths: Dictionary, own: Array, obs: Dictionary, prev := {}) -> Dictionary:
	var clear := _n("callout_clear_px")
	var line := _n("callout_line_px")
	var own_ring := Vector3(fort.x, fort.y, ring_r)
	var hard_obs: Array = [own_ring]
	hard_obs.append_array(obs.get("rings", []))
	hard_obs.append_array(obs.get("circles", []))
	hard_obs.append_array(obs.get("rects", []))
	hard_obs.append_array(own)
	var soft_obs: Array = obs.get("soft", [])
	var below_top := fort.y + ring_r
	for r in own:
		below_top = maxf(below_top, (r as Rect2).end.y)
	below_top += _n("callout_below_gap_px")
	var forms: Array = [["one", [float(widths["one"])], size, line]]  # [form, line widths, font, line step]
	if widths.has("a"):
		var size2 := int(widths.get("size_two", size))  # the two-line form may be set smaller (callout_font_two)
		forms.append(["two", [float(widths["a"]), float(widths["b"])], size2, line * float(size2) / float(size)])
	var slides: Array = [0.0]
	for s in cfg()["callout_slides"]:
		slides.append(float(s))
	var cands: Array = []
	for place in ["above", "below"]:
		for fm in forms:
			var ws: Array = fm[1]
			var span := 0.0
			for w in ws:
				span = maxf(span, float(w))
			var fs: int = fm[2]
			var step: float = fm[3]
			var first_by := base_y - float(ws.size() - 1) * step if place == "above" else below_top + float(fs) * float(NodeLogic.ncfg()["plate_ascent"])
			for s in slides:
				var cx := fort.x + float(s) * span
				var rects := callout_rects(cx, first_by, ws, fs, step)
				cands.append({"form": fm[0], "place": place, "slide": float(s), "pos": Vector2(cx, first_by), "rects": rects, "size": fs, "line": step,
					"hard": _hard(rects, hard_obs, clear), "soft": _soft(rects, soft_obs), "side": false})
	# last resort, where a crowded or cornered fort leaves no row above or under it: beside the fort's ring,
	# on its middle, callout_side_gap_px off the ring (right, then left); these need not cover the fort's x
	for place in ["right", "left"]:
		for fm in forms:
			var ws: Array = fm[1]
			var span := 0.0
			for w in ws:
				span = maxf(span, float(w))
			span += float(NodeLogic.ncfg()["plate_pad_px"]) * 2.0
			var fs: int = fm[2]
			var step: float = fm[3]
			var height := float(ws.size() - 1) * step + float(fs) * float(NodeLogic.ncfg()["plate_height"])
			var first_by := fort.y - height * 0.5 + float(fs) * float(NodeLogic.ncfg()["plate_ascent"])
			var cx := fort.x + (ring_r + _n("callout_side_gap_px") + span * 0.5) * (1.0 if place == "right" else -1.0)
			var rects := callout_rects(cx, first_by, ws, fs, step)
			cands.append({"form": fm[0], "place": place, "slide": 0.0, "pos": Vector2(cx, first_by), "rects": rects, "size": fs, "line": step,
				"hard": _hard(rects, hard_obs, clear), "soft": _soft(rects, soft_obs), "side": true})
	# the screen's bounds are hard: a place not wholly inside them is dropped first
	var pool: Array = cands
	if obs.has("bounds"):
		var bounds: Rect2 = obs["bounds"]
		pool = []
		var least: Dictionary = cands[0]
		var least_off := INF
		for cd in cands:
			var off := 0.0
			for r in cd["rects"]:
				var i: Rect2 = (r as Rect2).intersection(bounds)
				off += (r as Rect2).size.x * (r as Rect2).size.y - maxf(i.size.x * i.size.y, 0.0)
			if off <= 0.5:  # Rect2 is single precision: a rect on the edge leaves a hair
				pool.append(cd)
			elif off < least_off:
				least_off = off
				least = cd
		if pool.is_empty():
			return least  # nothing fits: the least off-screen
	var valid: Array = []
	for cd in pool:
		var own_gap := _own_gap(cd["rects"], fort, own_ring, own, obs.get("rings", []), bool(cd["side"]))
		cd["own_gap"] = own_gap["gap"]
		cd["owns"] = own_gap["ok"]
		if bool(own_gap["ok"]):
			valid.append(cd)
	if not prev.is_empty():  # a line that is up does not hop: its last place stays while it is still free (a soft overlap moves it only to a fully clear place)
		var clean := false
		for cd in valid:
			clean = clean or (float(cd["hard"]) == 0.0 and float(cd["soft"]) == 0.0)
		for cd in valid:
			if str(cd["form"]) == str(prev.get("form")) and str(cd["place"]) == str(prev.get("place")) and is_equal_approx(float(cd["slide"]), float(prev.get("slide", 0.0))) and float(cd["hard"]) == 0.0 and (float(cd["soft"]) == 0.0 or not clean):
				return cd
	for cd in valid:
		if float(cd["hard"]) == 0.0 and float(cd["soft"]) == 0.0:
			return cd
	for cd in valid:
		if float(cd["hard"]) == 0.0:
			return cd
	var from: Array = valid if not valid.is_empty() else pool
	var best: Dictionary = from[0]
	for cd in from:
		var h := float(cd["hard"])
		var bh := float(best["hard"])
		if h < bh or (h == bh and (float(cd["own_gap"]) < float(best["own_gap"]) if valid.is_empty() else float(cd["soft"]) < float(best["soft"]))):
			best = cd
	return best


## How near a place is to its own fort (ring, own rects) and whether it reads as the fort's: see
## callout_place. {gap, ok}.
static func _own_gap(rects: Array, fort: Vector2, own_ring: Vector3, own: Array, others: Array, side := false) -> Dictionary:
	var left := INF
	var right := -INF
	var own_gap := INF
	var other_gap := INF
	for r in rects:
		left = minf(left, (r as Rect2).position.x)
		right = maxf(right, (r as Rect2).end.x)
		own_gap = minf(own_gap, circle_gap(r, own_ring))
		for o in own:
			own_gap = minf(own_gap, rect_gap(r, o))
		for c in others:
			other_gap = minf(other_gap, circle_gap(r, c))
	var m := _n("callout_x_margin_px")
	var ok := (side or (fort.x >= left - m and fort.x <= right + m)) and own_gap <= _n("callout_drift_px") and own_gap <= other_gap
	return {"gap": own_gap, "ok": ok}


## The first flip's green ripple at the fort's beat `phase` (Pulse.phase at its hops): {reach
## (0..1 of ripple_reach_px), alpha} while t < ripple_beats; {} after it and under reduced motion.
static func ripple(phase: float, t: float, reduced: bool) -> Dictionary:
	if reduced or t >= _n("ripple_beats"):
		return {}
	return {"reach": phase, "alpha": pow(1.0 - phase, 2.0) * _n("ripple_alpha")}


## A callout's alpha `t` beats into its `dur`: 1, fading out over the last callout_fade_beats,
## 0 after; under reduced motion 1 for the whole of it, with no fade.
static func callout_alpha(t: float, dur: float, reduced: bool) -> float:
	if t < 0.0 or t >= dur:
		return 0.0
	if reduced:
		return 1.0
	return clampf((dur - t) / maxf(_n("callout_fade_beats"), 0.001), 0.0, 1.0)


# --- bands along a lane (the tithe tide, the garrison's WAR pulse) ---------------------------

## A lane's track for a band: the curve MapLogic.lane_curve_for draws for `row` from `a` to `b`,
## sampled, its cumulative arc length, and the drawn range lo..hi (NodeLogic.trim_lengths of the
## two nodes' outer radii, so a band never crosses a node's rings).
static func track(row: Dictionary, a: Vector2, b: Vector2, r_from: float, r_to: float, samples: int) -> Dictionary:
	var c := MapLogic.lane_curve_for(row, a, b, 0.0)
	var pts := MapLogic.sample_quad(c["a"], c["c"], c["b"], samples)
	var cum := cumulative(pts)
	var length := cum[cum.size() - 1] if cum.size() > 0 else 0.0
	var trim := NodeLogic.trim_lengths(r_from, r_to, length)
	return {"pts": pts, "cum": cum, "lo": float(trim["start"]), "hi": length - float(trim["end"])}


static func cumulative(pts: PackedVector2Array) -> PackedFloat32Array:
	var cum := PackedFloat32Array()
	cum.resize(pts.size())
	for i in range(1, pts.size()):
		cum[i] = cum[i - 1] + pts[i - 1].distance_to(pts[i])
	return cum


## A band `band` px long whose head is `x` (0..1) of the way from lo to hi: its arc range.
static func band_range(x: float, band: float, lo: float, hi: float) -> Vector2:
	var s := lerpf(lo, hi, clampf(x, 0.0, 1.0))
	return Vector2(maxf(lo, s - band), s)


## The tithe tide `t` beats in, from Vei (lo) toward the fort (hi): the band's arc range over
## tide_beats; under reduced motion the whole lane, still, for tide_beats; NONE after.
static func tide(t: float, reduced: bool, lo: float, hi: float) -> Vector2:
	var d := _n("tide_beats")
	if t >= d:
		return NONE
	if reduced:
		return Vector2(lo, hi)
	return band_range(t / d, _n("tide_band_px"), lo, hi)


## The points of a sampled curve between arc lengths s0 and s1 (its end points interpolated).
static func sub_polyline(pts: PackedVector2Array, cum: PackedFloat32Array, s0: float, s1: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	if pts.size() < 2 or s1 <= s0:
		return out
	out.append(LaneStyle.point_at(pts, cum, s0))
	for i in pts.size():
		if cum[i] > s0 and cum[i] < s1:
			out.append(pts[i])
	out.append(LaneStyle.point_at(pts, cum, s1))
	return out


# --- the garrison cleared -------------------------------------------------------------------

## The real event (api-request #10), counter_garrison_cleared {fort_id, killed_mass}: {fort_id, n}
## with n her killed mass, rounded. {} for any other event.
static func garrison_from_event(ev: Dictionary) -> Dictionary:
	if str(ev.get("type", "")) != "counter_garrison_cleared":
		return {}
	return {"fort_id": str(ev.get("fort_id", "")), "n": maxi(roundi(float(ev.get("killed_mass", 0.0))), 0)}


## The callout: "Vei's living routed: −N".
static func garrison_text(n: int) -> String:
	return _s("garrison_fmt") % MapLogic.fmt_mass(n)


## Her counter-garrison as the chip counts it down, x (0..1) of the way through the drain: n at
## the start, 0 only at the end.
static func drain_count(n: int, x: float) -> int:
	return clampi(ceili(n * (1.0 - clampf(x, 0.0, 1.0))), 0, n)


## The garrison set piece `t` beats in, for a counter-garrison of `n`:
##   pulse    0..1, the WAR band from Covington to the fort (-1: none);
##   burst    0..1, the green rings at the fort once the pulse lands (-1: none);
##   ring     true: the burst's still ring (reduced motion);
##   chip     the chip's line two: {} the live chip; {text, key, squash} her counter draining to 0,
##            then flipping (squash 1 -> 0) to {live: true,
##            squash 0 -> 1}, the live margin word;
##   callout  its alpha; done.
## Reduced motion: the end state at once (the live word, the callout, the still ring).
static func garrison(t: float, n: int, reduced: bool) -> Dictionary:
	var pb := _n("garrison_pulse_beats")
	var db := _n("garrison_drain_beats")
	var fb := _n("garrison_flip_beats")
	var cb := _n("garrison_callout_beats")
	var out := {"pulse": -1.0, "burst": -1.0, "ring": false, "chip": {}, "callout": 0.0, "done": false}
	if reduced:
		out["ring"] = t < cb
		out["callout"] = callout_alpha(t, cb, true)
		out["done"] = t >= cb
		return out
	var end := maxf(pb + _n("garrison_burst_beats"), maxf(pb + db + fb, pb + cb))
	out["done"] = t >= end
	if t < pb:
		out["pulse"] = t / pb
		return out
	var u := t - pb
	if u < _n("garrison_burst_beats"):
		out["burst"] = u / _n("garrison_burst_beats")
	out["callout"] = callout_alpha(u, cb, false)
	var text := _s("garrison_counter_fmt") % MapLogic.fmt_mass(drain_count(n, u / db))
	if u < db:
		out["chip"] = {"text": text, "key": "living", "squash": 1.0}
	elif u < db + fb * 0.5:
		out["chip"] = {"text": text, "key": "living", "squash": 1.0 - (u - db) / (fb * 0.5)}
	elif u < db + fb:
		out["chip"] = {"live": true, "squash": (u - db - fb * 0.5) / (fb * 0.5)}
	return out


# --- a finished build (the callout at Covington) ----------------------------------------------
# The sim's own projection (view_catalog's `projected`, view_town's `upgrade_projected`) is the
# honest number, but it moves on to the next level once a build is done, so the model keeps the
# last real one it read per pending build in a store: {"lot:level": {building_id, rates}}.

static func proj_key(lot_id: String, level: int) -> String:
	return "%s:%d" % [lot_id, level]


## Built lots from view_town().buildings: {lot_id: {building_id, level}}. A first build under way is
## level 0 and an upgrade under way still reads its old level, so a level only rises on `done`.
static func lot_levels(buildings: Array) -> Dictionary:
	var out := {}
	for b in buildings:
		out[str(b["lot_id"])] = {"building_id": str(b["building_id"]), "level": int(b["level"])}
	return out


## The builds that finished between two snapshots of lot_levels: a lot whose level rose, or whose
## building changed, [{lot_id, building_id, level}] by lot id. A level-0 lot has built nothing yet.
static func rises(before: Dictionary, now: Dictionary) -> Array:
	var out: Array = []
	var ids := now.keys()
	ids.sort()
	for id in ids:
		var n: Dictionary = now[id]
		if int(n["level"]) < 1:
			continue
		var b: Dictionary = before.get(id, {})
		if b.is_empty() or str(b["building_id"]) != str(n["building_id"]) or int(n["level"]) > int(b["level"]):
			out.append({"lot_id": str(id), "building_id": str(n["building_id"]), "level": int(n["level"])})
	return out


## The mount's `rises` to announce: none when the away panel opens for this return (the away
## report already lists the builds that finished, so a callout would say them twice).
static func mount_builds(mount_rises: Array, away_opens: bool) -> Array:
	return [] if away_opens else mount_rises


## Whether a catalog read is worth its cost: a build is queued or under construction.
static func has_pending(town: Dictionary) -> bool:
	if not (town.get("queue", []) as Array).is_empty():
		return true
	for b in town.get("buildings", []):
		if str(b.get("state", "")) == "constructing":
			return true
	return false


## The new builds (not upgrades) waiting or under way, whose projection the catalog holds by
## building id: queued rows, and a first build under construction. [{lot_id, building_id, level: 1}].
static func pending_new(town: Dictionary) -> Array:
	var out: Array = []
	for q in town.get("queue", []):
		if not bool(q.get("upgrade", false)) and str(q.get("lot_id", "")) != "":
			out.append({"lot_id": str(q["lot_id"]), "building_id": str(q["building_id"]), "level": 1})
	for b in town.get("buildings", []):
		if str(b.get("state", "")) == "constructing" and int(b["level"]) == 0:
			out.append({"lot_id": str(b["lot_id"]), "building_id": str(b["building_id"]), "level": 1})
	return out


## Stores each built lot's upgrade_projected at the lot's next level. An empty one (cold, or the lot
## is constructing) never overwrites the last real value.
static func note_upgrades(store: Dictionary, buildings: Array) -> void:
	for b in buildings:
		var p: Dictionary = b.get("upgrade_projected", {})
		if not p.is_empty():
			store[proj_key(str(b["lot_id"]), int(b["level"]) + 1)] = {"building_id": str(b["building_id"]), "rates": p.duplicate()}


## Stores the catalog's `projected` for each pending new build (by building id) at its lot, level 1;
## an empty row keeps what was stored.
static func note_catalog(store: Dictionary, pending: Array, rows: Array) -> void:
	for p in pending:
		for r in rows:
			if str(r.get("building_id", "")) == str(p["building_id"]):
				var rates: Dictionary = r.get("projected", {})
				if not rates.is_empty():
					store[proj_key(str(p["lot_id"]), int(p["level"]))] = {"building_id": str(p["building_id"]), "rates": rates.duplicate()}
				break


## The stored rates of `building_id` on `lot_id` at `level`: {} when none (or another building's).
static func projection_for(store: Dictionary, lot_id: String, building_id: String, level: int) -> Dictionary:
	var e: Dictionary = store.get(proj_key(lot_id, level), {})
	if e.is_empty() or str(e["building_id"]) != building_id:
		return {}
	return e["rates"]


## `build` joins the callout's builds unless that lot and level is already in it (the router
## re-emits a building_done it held while the map mounted, and the mount's diff found the same one).
static func add_build(builds: Array, build: Dictionary) -> Array:
	for b in builds:
		if str(b["lot_id"]) == str(build["lot_id"]) and int(b["level"]) == int(build["level"]):
			return builds
	return builds + [build]


## The stream with the biggest |change| among build_rate_ids (the HUD's own streams, so work, war
## and flood, which are the mint again, and corpses and backlog, which have no label, never lead):
## {id, delta}, or {} when none reaches build_eps. A tie goes to the earlier stream.
static func biggest(rates: Dictionary) -> Dictionary:
	var best := {}
	for id in cfg()["build_rate_ids"]:
		var d := float(rates.get(id, 0.0))
		if absf(d) >= _n("build_eps") and (best.is_empty() or absf(d) > absf(float(best["delta"]))):
			best = {"id": str(id), "delta": d}
	return best


## The callout's line: "Inn built · MINT +0.8/s"; several builds, rates summed: "2 builds: Inn ·
## Bakery · MINT +1.1/s"; with no recorded projection (or every change under build_eps) the
## builds alone. `names` maps a building id to its label (buildings_view.json).
static func build_text(builds: Array, store: Dictionary, names: Dictionary) -> String:
	var labels: Array = []
	var sum := {}
	for b in builds:
		var id := str(b["building_id"])
		labels.append(str(names.get(id, id.capitalize())))
		var rates := projection_for(store, str(b["lot_id"]), id, int(b["level"]))
		for k in rates:
			sum[k] = float(sum.get(k, 0.0)) + float(rates[k])
	var sep := _s("build_sep")
	var head := _s("build_one_fmt") % labels[0] if labels.size() == 1 else _s("build_many_fmt") % [labels.size(), sep.join(labels)]
	var big := biggest(sum)
	if big.is_empty():
		return head
	return "%s%s%s %s" % [head, sep, str(HudLogic.LABELS.get(big["id"], str(big["id"]).to_upper())), MapLogic.fmt_rate(float(big["delta"]))]


## The line's runs by font (AwayLogic.spans): the signed rate is the rate face, the rest labels.
static func build_spans(text: String) -> Array:
	return AwayLogic.spans(text)


## The plate's alpha `t` beats in: full, fading over the last callout_fade_beats; under reduced
## motion full until it is gone.
static func build_alpha(t: float, reduced: bool) -> float:
	return callout_alpha(t, _n("build_beats"), reduced)


static func build_done(t: float) -> bool:
	return t >= _n("build_beats")


# --- victory --------------------------------------------------------------------------------

## RUN for victory_run_beats (every lane green, running toward Vei), then STOP (every dash frozen,
## the victory line up). Reduced motion: STOP at once.
static func victory_phase(t: float, reduced: bool) -> String:
	return STOP if reduced or t >= _n("victory_run_beats") else RUN


## The u a lane draws at in victory: its own, floored at victory_u_floor, so a dark lane lights.
static func victory_u(u: float) -> float:
	return maxf(u, _n("victory_u_floor"))


# --- debug triggers -------------------------------------------------------------------------

## --setpiece=<kind> and --setpiece-slow=<k>, debug sessions only: {kind ("" none), slow (1 none)}.
static func debug_args(args: Array, debug: bool) -> Dictionary:
	var out := {"kind": "", "slow": 1.0}
	if not debug:
		return out
	for a in args:
		var s := str(a)
		if s.begins_with("--setpiece="):
			var k := s.trim_prefix("--setpiece=")
			if KINDS.has(k):
				out["kind"] = k
		elif s.begins_with("--setpiece-slow=") and s.trim_prefix("--setpiece-slow=").is_valid_float():
			var f := s.trim_prefix("--setpiece-slow=").to_float()
			if f > 0.0:
				out["slow"] = f
	return out


## The debug trigger's fort: `preferred` if the realm has it, else the first held fort, else the
## first fort ("" with none).
static func demo_target(forts: Array, preferred: String) -> String:
	var held := ""
	for f in forts:
		if str(f.get("id", "")) == preferred:
			return preferred
		if held == "" and bool(f.get("held", false)):
			held = str(f["id"])
	if held != "":
		return held
	return str(forts[0].get("id", "")) if not forts.is_empty() else ""


## The debug swing's valve: debug_valve, or debug_valve_alt when the target already is it.
static func demo_valve(target: Dictionary) -> Dictionary:
	var v: Array = cfg()["debug_valve"]
	var out := {"work": float(v[0]), "war": float(v[1]), "flood": float(v[2])}
	if not valve_moved(out, target):
		var alt: Array = cfg()["debug_valve_alt"]
		out = {"work": float(alt[0]), "war": float(alt[1]), "flood": float(alt[2])}
	return out
