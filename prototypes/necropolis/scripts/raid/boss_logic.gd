class_name BossLogic
extends RefCounted
## Vei's final test, the boss scene's pure maths (no autoloads, no Engine, no scene tree): lane
## geometry, stream and guard-line sizes, anchor placement, beat bookkeeping, guard and mote
## accrual, weave geometry, the seed's fronts and the demo seed. The rules of the fight are
## VeiFronts'; this file only places, counts and steps. Every function is static, takes its numbers
## from `cfg` (configs/vei.json, passed in) and never mutates its arguments.
##
## lanes(size, wall_t, court, cfg) -> Array[{id, a, b}]   one per front (FRONT_IDS order, west to
##   east): a = the south start, b = the end at Vei's court (court_r_px from her).
## point_at(lane, s), lane_len(lane), lane_dir(lane)        s in 0..1 from a to b.
## contact_s(progress, cfg)        where the stream meets the guard line (guard_s0 -> guard_s1).
## stream_count(have, cfg), guard_rows(need, cfg)    the stream's glyphs and the guard line's rows.
## stream_s(count, s_end, len_px, march_px)    lane fractions of `count` evenly spaced glyphs on
##   0..s_end, shifted forward by march_px (wrapping), so a moving offset marches them.
## seg_dist(p, a, b), seg_t(p, a, b), nearest_lane(p, lanes)    the lane a raise feeds.
## anchors(lanes, cfg) -> Array[Vector2]    phase-2 anchors between the lanes at lane_s.
## beat_of(t, tempo_s), beats_crossed(b0, b1), align_t(pulse_phase, tempo_s)    the beat clock:
##   align_t is the clock start that puts beat 0 on the next tempo boundary.
## ferry_per_beat(ferry, tempo_s, cfg)    F * tempo_s * ferry_beat_scale (the break's comparison).
## horde_step(h, ferry, dt), backlog_spent(h0, h)    the horde pool; spent is never negative.
## accrue(acc, rate, dt) -> {acc, n}    whole events from a rate.
## guard_spawn(acc, dt, uncleared, alive, cfg) -> {acc, n}    guards to spawn now (cap-bounded).
## anchor_mote_rate(ferry, cfg)    motes/s at the anchors: the faster she ferries, the more essence.
## guard_ceiling(uncleared, cfg)    the most guards that can stand at once: guards.cap, or, when they
##   fall back after guards.life_s (> 0), rate_per_uncleared * uncleared * life_s if that is lower.
## ray_to_bounds(origin, through, size, wall_t)    a weave's far end: the ray from `origin` through
##   `through`, clipped to the arena's inner rect.
## weave_hits(a, b, p, reach), is_tell(beat, at, tell_beats)
## seed_fronts_empty(seed)    the seed's fronts are economy's pre-E3 zeros.
## party_lanes(seed, cfg) -> {uid: lane index}    the front each party member is counted on.
## force_fronts(fronts, n, cfg)    the demo's --boss-fronts=n override.
## demo_seed(cfg) -> Dictionary    vei.json demo.seed, deep-copied.
## backups_left(spent, charges, clones), rng_int(rng_seed)
## cleared_ids(fronts) -> Array[String]    ids of the cleared fronts, in order.
## result_of(state, won) -> Dictionary    VeiBoss._result's wiring: fight_result from VeiBoss's
##   fight_state() {seed, p1, fronts_cleared, phase1_s, deaths, spent, party_lost, horde0, horde}
##   (RESULT_KEYS, all required: a missing one is an error and returns {}); the break began when
##   phase1_s >= 0 (it is -1 until then).
## fight_result(seed, won, p1, frozen_cleared, break_began, deaths, spent, party_lost, h0, h)
##   VeiFronts.boss_result with the right fronts_cleared: the list frozen when the break began, or,
##   for a fight that ended in phase 1 (a timeout, a final death, a window close), the fronts the
##   phase-1 state `p1` has cleared so far. backlog_spent = H0 - H, never negative.
## close_fields(end_reason, spent_total) -> {won, relish_deaths}    a window close mid-fight (IDLE
##   I5): the win once she broke ("broken"), else lost; deaths = the backups spent, plus one when
##   the final-death beat was playing ("relish_unmade"). Always consistent with STATE-API 8.2.

const FRONT_IDS := ["giants", "swarm", "carvers", "raw"]


static func _f(d: Variant, key: String, def: float) -> float:
	if typeof(d) == TYPE_DICTIONARY and d.has(key) and (typeof(d[key]) == TYPE_INT or typeof(d[key]) == TYPE_FLOAT):
		return float(d[key])
	return def


static func _sec(cfg: Dictionary, key: String) -> Dictionary:
	var v: Variant = cfg.get(key, {})
	return v if typeof(v) == TYPE_DICTIONARY else {}


# ------------------------------------------------------------------------ lanes ----
static func lanes(size: Vector2, wall_t: float, court: Vector2, cfg: Dictionary) -> Array:
	var lc := _sec(cfg, "lanes")
	var xs: Variant = lc.get("x_frac", [])
	var y0 := size.y - wall_t - _f(lc, "south_margin_px", 120.0)
	var r := _f(lc, "court_r_px", 230.0)
	var arc := deg_to_rad(_f(lc, "court_arc_deg", 104.0))
	var n := FRONT_IDS.size()
	var out: Array = []
	for i in n:
		var k := float(i) / float(n - 1)
		var xf := 0.17 + 0.66 * k
		if typeof(xs) == TYPE_ARRAY and i < xs.size():
			xf = float(xs[i])
		var ang := lerpf(arc * 0.5, -arc * 0.5, k)   # west lane ends on her west side
		out.append({"id": FRONT_IDS[i], "a": Vector2(size.x * xf, y0), "b": court + Vector2(0.0, r).rotated(ang)})
	return out


static func point_at(lane: Dictionary, s: float) -> Vector2:
	return (lane["a"] as Vector2).lerp(lane["b"], s)


static func lane_len(lane: Dictionary) -> float:
	return (lane["a"] as Vector2).distance_to(lane["b"])


static func lane_dir(lane: Dictionary) -> Vector2:
	return ((lane["b"] as Vector2) - (lane["a"] as Vector2)).normalized()


static func contact_s(progress: float, cfg: Dictionary) -> float:
	var lc := _sec(cfg, "lanes")
	return lerpf(_f(lc, "guard_s0", 0.5), _f(lc, "guard_s1", 0.93), clampf(progress, 0.0, 1.0))


static func stream_count(have: float, cfg: Dictionary) -> int:
	if have <= 0.0:
		return 0
	var lc := _sec(cfg, "lanes")
	return clampi(roundi(have * _f(lc, "glyphs_per_have", 1.1)), int(_f(lc, "glyphs_min", 3.0)),
		int(_f(lc, "glyphs_max", 44.0)))


static func guard_rows(need: float, cfg: Dictionary) -> int:
	var lc := _sec(cfg, "lanes")
	return clampi(ceili(maxf(need, 0.0) * _f(lc, "rows_per_need", 0.11)), 1, int(_f(lc, "rows_max", 6.0)))


static func stream_s(count: int, s_end: float, len_px: float, march_px: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	if count <= 0 or s_end <= 0.0 or len_px <= 0.0:
		return out
	var span := s_end * len_px
	var step := span / float(count)
	var off := fposmod(march_px, step)
	for k in count:
		out.append((off + step * k) / len_px)
	return out


static func seg_t(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var l2 := ab.length_squared()
	if l2 <= 0.000001:
		return 0.0
	return clampf((p - a).dot(ab) / l2, 0.0, 1.0)


static func seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	return p.distance_to(a.lerp(b, seg_t(p, a, b)))


## The lane whose segment lies nearest `p` (ties: the westmost). -1 with no lanes.
static func nearest_lane(p: Vector2, lanes_a: Array) -> int:
	var best := -1
	var bd := INF
	for i in lanes_a.size():
		var d := seg_dist(p, lanes_a[i]["a"], lanes_a[i]["b"])
		if d < bd:
			bd = d
			best = i
	return best


## `count` anchors spread evenly (by fraction (i + 0.5) / count) along the polyline through every
## lane's point at lane_s: with four lanes and three anchors, one sits between each pair.
static func anchors(lanes_a: Array, cfg: Dictionary) -> Array:
	var ac := _sec(cfg, "anchors")
	var n := int(_f(ac, "count", 3.0))
	var s := _f(ac, "lane_s", 0.42)
	var out: Array = []
	if lanes_a.is_empty() or n <= 0:
		return out
	var pts: Array[Vector2] = []
	for l in lanes_a:
		pts.append(point_at(l, s))
	if pts.size() == 1:
		for i in n:
			out.append(pts[0])
		return out
	var total := 0.0
	for i in range(1, pts.size()):
		total += pts[i].distance_to(pts[i - 1])
	for i in n:
		var want := total * (float(i) + 0.5) / float(n)
		var acc := 0.0
		for j in range(1, pts.size()):
			var seg := pts[j].distance_to(pts[j - 1])
			if acc + seg >= want or j == pts.size() - 1:
				out.append(pts[j - 1].lerp(pts[j], clampf((want - acc) / maxf(seg, 0.0001), 0.0, 1.0)))
				break
			acc += seg
	return out


# ------------------------------------------------------------------------ beats ----
static func beat_of(t_s: float, tempo_s: float) -> float:
	return t_s / maxf(tempo_s, 0.001)


## Whole beats passed going from beat b0 to b1 (0 when b1 <= b0).
static func beats_crossed(b0: float, b1: float) -> int:
	return maxi(0, floori(b1) - floori(b0))


## The clock start (negative, scene seconds) so beat 0 lands on the next tempo boundary.
static func align_t(pulse_phase: float, tempo_s: float) -> float:
	return -(1.0 - clampf(pulse_phase, 0.0, 1.0)) * tempo_s


static func ferry_per_beat(ferry: float, tempo_s: float, cfg: Dictionary) -> float:
	return maxf(ferry, 0.0) * tempo_s * _f(cfg, "ferry_beat_scale", 0.12)


# ------------------------------------------------------------- horde, accruals ----
static func horde_step(h: float, ferry: float, dt: float) -> float:
	return maxf(0.0, h - maxf(ferry, 0.0) * dt)


static func backlog_spent(h0: float, h: float) -> float:
	return maxf(0.0, h0 - h)


static func accrue(acc: float, rate: float, dt: float) -> Dictionary:
	var a := acc + maxf(rate, 0.0) * dt
	var n := floori(a)
	return {"acc": a - n, "n": n}


static func guard_spawn(acc: float, dt: float, uncleared: int, alive: int, cfg: Dictionary) -> Dictionary:
	var gc := _sec(cfg, "guards")
	var room := maxi(0, int(_f(gc, "cap", 12.0)) - alive)
	var a := acc + _f(gc, "rate_per_uncleared", 0.3) * maxf(float(uncleared), 0.0) * dt
	var n := mini(floori(a), room)
	a -= n
	if n >= room:
		a = minf(a, 1.0)   # at the cap the lanes wait; they don't bank a flood
	return {"acc": a, "n": n}


static func guard_ceiling(uncleared: int, cfg: Dictionary) -> float:
	var gc := _sec(cfg, "guards")
	var cap := _f(gc, "cap", 12.0)
	var life := _f(gc, "life_s", 0.0)
	if life <= 0.0:
		return cap
	return minf(cap, _f(gc, "rate_per_uncleared", 0.3) * maxf(float(uncleared), 0.0) * life)


static func anchor_mote_rate(ferry: float, cfg: Dictionary) -> float:
	return maxf(ferry, 0.0) * _f(_sec(cfg, "anchors"), "motes_per_ferry", 0.5)


# ------------------------------------------------------------------------ weaves ----
static func ray_to_bounds(origin: Vector2, through: Vector2, size: Vector2, wall_t: float) -> Vector2:
	var d := through - origin
	if d.length() < 0.001:
		d = Vector2(0.0, 1.0)
	d = d.normalized()
	var lo := Vector2(wall_t, wall_t)
	var hi := size - Vector2(wall_t, wall_t)
	var tmax := INF
	if d.x > 0.0:
		tmax = minf(tmax, (hi.x - origin.x) / d.x)
	elif d.x < 0.0:
		tmax = minf(tmax, (lo.x - origin.x) / d.x)
	if d.y > 0.0:
		tmax = minf(tmax, (hi.y - origin.y) / d.y)
	elif d.y < 0.0:
		tmax = minf(tmax, (lo.y - origin.y) / d.y)
	if not is_finite(tmax) or tmax < 0.0:
		tmax = 0.0
	return origin + d * tmax


static func weave_hits(a: Vector2, b: Vector2, p: Vector2, reach: float) -> bool:
	return seg_dist(p, a, b) <= reach


static func is_tell(beat: float, at: float, tell_beats: float) -> bool:
	return beat >= at - tell_beats and beat < at


# ------------------------------------------------------------- fronts, the seed ----
static func seed_fronts_empty(seed: Dictionary) -> bool:
	var fs: Variant = seed.get("fronts", [])
	if typeof(fs) != TYPE_ARRAY or fs.is_empty():
		return true
	for f in fs:
		if typeof(f) == TYPE_DICTIONARY and (_f(f, "need", 0.0) > 0.0 or _f(f, "have", 0.0) > 0.0):
			return false
	return true


static func party_lanes(seed: Dictionary, cfg: Dictionary) -> Dictionary:
	var out := {}
	var fr := VeiFronts.have_need(VeiFronts.info_from_boss_seed(seed), cfg)
	for i in fr.size():
		for uid in fr[i]["assigned"]:
			out[String(uid)] = i
	return out


static func force_fronts(fronts: Array, n: int, cfg: Dictionary) -> Array:
	var dc := _sec(cfg, "demo")
	var met := _f(dc, "force_met_frac", 1.15)
	var short := _f(dc, "force_unmet_frac", 0.3)
	var out: Array = []
	for i in fronts.size():
		var g: Dictionary = (fronts[i] as Dictionary).duplicate(true)
		var need := float(g.get("need", 0.0))
		var have := float(g.get("have", 0.0))
		g["have"] = maxf(have, need * met) if i < n else minf(have, need * short)
		g["cleared"] = float(g["have"]) >= need
		out.append(g)
	return out


static func demo_seed(cfg: Dictionary) -> Dictionary:
	var d: Variant = _sec(cfg, "demo").get("seed", {})
	return (d as Dictionary).duplicate(true) if typeof(d) == TYPE_DICTIONARY else {}


static func backups_left(spent: Dictionary, charges: int, clones: int) -> int:
	return maxi(0, charges - int(spent.get("phylactery", 0))) + maxi(0, clones - int(spent.get("clones", 0)))


static func cleared_ids(fronts: Array) -> Array:
	var out: Array = []
	for f in fronts:
		if typeof(f) == TYPE_DICTIONARY and bool(f.get("cleared", false)):
			out.append(String(f.get("id", "")))
	return out


static func fight_result(seed: Dictionary, won: bool, p1: Dictionary, frozen_cleared: Array, break_began: bool,
		deaths: int, spent: Dictionary, party_lost: Array, h0: float, h: float) -> Dictionary:
	var cleared: Array = frozen_cleared if break_began else cleared_ids(p1.get("fronts", []))
	return VeiFronts.boss_result(seed, won, cleared, deaths, spent, party_lost, backlog_spent(h0, h))


## The keys result_of needs from VeiBoss.fight_state(); every one is required.
const RESULT_KEYS := ["seed", "p1", "fronts_cleared", "phase1_s", "deaths", "spent", "party_lost", "horde0", "horde"]


static func result_of(state: Dictionary, won: bool) -> Dictionary:
	for k in RESULT_KEYS:
		if not state.has(k):
			push_error("BossLogic.result_of: fight state has no '%s'" % k)
			return {}
	return fight_result(state["seed"], won, state["p1"], state["fronts_cleared"], float(state["phase1_s"]) >= 0.0,
		int(state["deaths"]), state["spent"], state["party_lost"], float(state["horde0"]), float(state["horde"]))


static func close_fields(end_reason: String, spent_total: int) -> Dictionary:
	var s := maxi(0, spent_total)
	return {"won": end_reason == "broken", "relish_deaths": s + 1 if end_reason == "relish_unmade" else s}


## A seed's rng_seed string as an int (a non-numeric string hashes).
static func rng_int(rng_seed: String) -> int:
	return rng_seed.to_int() if rng_seed.is_valid_int() else hash(rng_seed)


# --------------------------------------------------- HUD read-outs (D-d) ---
## clock_text(secs) -> "m:ss"    a fight time as the end card shows it (rounded to the second).
static func clock_text(secs: float) -> String:
	var s := maxi(0, roundi(secs))
	return "%d:%02d" % [s / 60, s % 60]


## push_beat(hist, gained, window) -> Array    the recent beats, newest last: 1 for a beat that
##   gained a pip (raise > ferry), 0 for a lapse. Keeps the last `window`. A new array.
static func push_beat(hist: Array, gained: bool, window: int) -> Array:
	var out := hist.duplicate()
	out.append(1 if gained else 0)
	while out.size() > maxi(1, window):
		out.pop_front()
	return out


## break_eta_s(hist, streak, need, lapse_cost, tempo_s, min_beats, max_s) -> float
##   Seconds to the break at the recent pace: the net pips per beat over `hist` (each gain +1, each
##   lapse -lapse_cost) against the pips still to fill, times the tempo. -1 (no hint) when fewer than
##   min_beats beats are known, the pace does not gain, the rule resets on a lapse (lapse_cost < 0)
##   and the window holds one, or the answer is past max_s. 0 when the meter is already full.
static func break_eta_s(hist: Array, streak: int, need: int, lapse_cost: int, tempo_s: float,
		min_beats: int, max_s: float) -> float:
	if need - streak <= 0:
		return 0.0
	var n := hist.size()
	if n < maxi(1, min_beats) or tempo_s <= 0.0:
		return -1.0
	var gains := 0
	for h in hist:
		gains += int(h)
	var lapses := n - gains
	if lapses > 0 and lapse_cost < 0:
		return -1.0
	var rate := (float(gains) - float(lapse_cost) * float(lapses)) / float(n) if lapse_cost >= 0 else float(gains) / float(n)
	if rate <= 0.0:
		return -1.0
	var eta := float(need - streak) / rate * tempo_s
	return eta if eta <= max_s else -1.0


## The words of the three read-outs below are raid.json's `vei_fight` block, passed as `words`.
## eta_text(eta_s, words) -> String    "~30 s at this pace", rounded to 5 s from 10 s up; "" for no hint (< 0).
static func eta_text(eta_s: float, words: Dictionary) -> String:
	if eta_s < 0.0:
		return ""
	var s := roundi(eta_s) if eta_s < 10.0 else roundi(eta_s / 5.0) * 5
	return RaidLogic.word_fmt(words, "eta", [maxi(1, s)])


## lapse_text(lapses, lost, words) -> String    the meter's running count: "" before the first lapse, else
##   "LAPSES ×4 · −10 beats" (the beats the streak actually lost, capped by what it held).
static func lapse_text(lapses: int, lost: int, words: Dictionary) -> String:
	if lapses <= 0:
		return ""
	return RaidLogic.word_fmt(words, "lapse", [lapses, lost, "" if lost == 1 else str(words.get("plural", ""))])


## phase2_hint(break_beats, lapse_cost, words) -> String    the line under the meter for the break's first seconds.
static func phase2_hint(break_beats: int, lapse_cost: int, words: Dictionary) -> String:
	var s := RaidLogic.word_fmt(words, "rule", [break_beats])
	return s + (RaidLogic.word_fmt(words, "rule_cost", [lapse_cost]) if lapse_cost >= 0 else str(words.get("rule_reset", "")))


## card_unlocked(t, skip_after) -> bool
##   Whether the Vei win card, shown for `t` real seconds, takes a press yet (`skip_after` s; 0 = at once).
static func card_unlocked(t: float, skip_after: float) -> bool:
	return t >= skip_after


## card_auto_due(t, auto_s) -> bool
##   Whether the win card, shown for `t` real seconds, presses its own button now (P7 item 4). A won fight is written
##   back only when the button runs (the router then opens the map), and a gap with the card up (the machine slept
##   past idle.gap_s) forfeits the open boss run: so the win card presses itself after `auto_s` (raid.json
##   gap_end.win_card_auto_s). `auto_s` <= 0: never (the loss card waits for its press, as before).
static func card_auto_due(t: float, auto_s: float) -> bool:
	return auto_s > 0.0 and t >= auto_s


## card_auto_left(t, auto_s) -> int
##   The whole seconds before the card presses itself, rounded up (the button's countdown); -1 when it never does.
static func card_auto_left(t: float, auto_s: float) -> int:
	return ceili(maxf(0.0, auto_s - t)) if auto_s > 0.0 else -1


## card_button_text(words, t, auto_s) -> String
##   The button's words: card_button, or card_button_auto with the seconds left while the card will press itself
##   (card_button when that word is blank or lost its %d).
static func card_button_text(words: Dictionary, t: float, auto_s: float) -> String:
	var left := card_auto_left(t, auto_s)
	var auto := RaidLogic.word_fmt(words, "card_button_auto", [left]) if left >= 0 else ""
	return auto if auto != "" else str(words.get("card_button", ""))


## end_card(seed, spent, party_lost, fight_t, horde0, horde) -> Dictionary
##   What the Vei win card prints, from the fight's own numbers: time_text, backups spent (phylactery,
##   clone, and of how many the run began with), big undead lost of the party, and the backlog spent
##   (horde0 - horde, never negative: the result's backlog_spent).
static func end_card(seed: Dictionary, spent: Dictionary, party_lost: Array, fight_t: float,
		horde0: float, horde: float) -> Dictionary:
	var party := 0
	var lost := 0
	var known: Array = []
	for p in seed.get("party", []):
		party += 1
		known.append(String(p.get("uid", "")))
	for u in party_lost:
		if known.has(String(u)):
			lost += 1
	var sp := int(spent.get("phylactery", 0))
	var sc := int(spent.get("clones", 0))
	return {"time_text": clock_text(fight_t), "spent_phyl": sp, "spent_clones": sc, "spent": sp + sc,
		"backups_total": int(seed.get("phylactery_charges", 0)) + int(seed.get("clones_ready", 0)),
		"party_lost": lost, "party": party, "backlog_spent": backlog_spent(horde0, horde)}


## The lost fight's words are raid.json's `vei_loss` block (the card's headline per end_reason, the banner, the
## cause and pressure rows, the HUD tag); every helper below takes that block as `words`.

## The BACKLOG row of the HUD's boss block (raid_hud.gd BossBlock), left to right at the draw's own gaps: the value
## column, then the backlog at 20 px, GAP_FERRY, the ferried text at 13 px, GAP_TAG and the pressure tag (only above
## the threshold), GAP_STATUS and the status. The block is BLOCK_W wide with an INSET on each side.
const BACKLOG_COL := 108.0
const GAP_FERRY := 10.0
const GAP_TAG := 8.0
const GAP_STATUS := 18.0
const BLOCK_W := 640.0
const BLOCK_INSET := 12.0


## The width of the BACKLOG row from its value column to the status's end (the HUD draws exactly these pieces).
static func backlog_row_w(font: Font, horde_text: String, ferry_text: String, tag: String, status: String, status_px: int) -> float:
	var w := font.get_string_size(horde_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x + GAP_FERRY
	w += font.get_string_size(ferry_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	if tag != "":
		w += GAP_TAG + font.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	return w + GAP_STATUS + font.get_string_size(status, HORIZONTAL_ALIGNMENT_LEFT, -1, status_px).x


static func _fmt(text: String, vals: Dictionary) -> String:
	var out := text
	for k in vals:
		out = out.replace("{%s}" % str(k), str(vals[k]))
	return out


## The loss banner's text per end reason (vei_boss `_lose`).
static func loss_banner(reason: String, words: Dictionary) -> String:
	return str((words.get("banner", {}) as Dictionary).get(reason, words.get("banner_unknown", "")))


## A front's name on the lane label and the BREAK THROUGH banner: raid.json vei_loss.front_names (the loss card's
## names), upper-cased; the id upper-cased where there is none. One rename moves all three places.
static func front_label(id: String, words: Dictionary) -> String:
	return str((words.get("front_names", {}) as Dictionary).get(id, id)).to_upper()


## The pressure the break's guards came with (VeiFronts.pressure_mult) as the short HUD tag, "· guards ×2.3";
## "" at or below `pressure_min` (a pool under pool_free changes nothing, so it says nothing).
static func pressure_tag(pressure: float, words: Dictionary) -> String:
	if pressure < float(words.get("pressure_min", 1.05)):
		return ""
	return _fmt(str(words.get("tag", "")), {"mult": "%.1f" % pressure})


## The loss card's GUARDS row: {label, text, key} like VeiCard rows, "×2.3 · 600 living in her reserve", or {} below
## `pressure_min`.
static func pressure_row(pressure: float, living_pool: float, words: Dictionary) -> Dictionary:
	if pressure < float(words.get("pressure_min", 1.05)):
		return {}
	return {"label": str(words.get("pressure_label", "")), "key": "living", "text": _fmt(str(words.get("pressure_text", "")),
		{"mult": "%.1f" % pressure, "pool": roundi(living_pool), "reserve": str(words.get("reserve", ""))})}


## "A", "A and B", "A, B and C" (the glossary's plain list).
static func _join_names(names: Array, words: Dictionary) -> String:
	var comma := str(words.get("join_comma", ", "))
	var conj := str(words.get("join_and", " and "))
	if names.size() <= 1:
		return "".join(PackedStringArray(names))
	return comma.join(PackedStringArray(names.slice(0, names.size() - 1))) + conj + str(names[names.size() - 1])


## The loss card's first row, naming the cause: {label, text, key}, or {} for a reason it has no row for.
## `facts`: last_hit_src (Relish.last_hit_src), streak_max, break_beats, fronts_cleared (ids), fronts_required.
static func loss_cause(reason: String, facts: Dictionary, words: Dictionary) -> Dictionary:
	match reason:
		"relish_unmade":
			var kb: Dictionary = words.get("killed_by", {})
			var src := str(facts.get("last_hit_src", ""))
			var who := str(kb.get(src, kb.get("other", "")))
			return {"label": str(words.get("killed_by_label", "")), "text": who, "key": "text"}
		"horde_ferried":
			return {"label": str(words.get("break_label", "")), "key": "text", "text": _fmt(str(words.get("break_text", "")),
				{"best": int(facts.get("streak_max", 0)), "need": int(facts.get("break_beats", 0))})}
		"fronts_held":
			var cleared: Array = facts.get("fronts_cleared", [])
			var names: Dictionary = words.get("front_names", {})
			var held: Array = []
			for id in FRONT_IDS:
				if not cleared.has(id):
					held.append(str(names.get(id, id)))
			var text := _fmt(str(words.get("fronts_text", "")), {"fell": FRONT_IDS.size() - held.size(), "total": FRONT_IDS.size(),
				"need": int(facts.get("fronts_required", 0))})
			if not held.is_empty():
				text += _fmt(str(words.get("held_clause", "")), {"held": _join_names(held, words)})
			return {"label": str(words.get("fronts_label", "")), "text": text, "key": "text"}
	return {}


## Which vei_loss.change line a lost fight reads: one per cause the card can show, "fallback" for any other. Each is a
## change that moves the cause (the file:line proofs are in the commit message):
##   weave           KILLED BY her weave: her thread hits on the beat (vei.gd weave_step), a backup revives Relish (vei_boss.gd try_phylactery)
##   living          KILLED BY her guards: guards come from the fronts still standing (guard_spawn, vei_boss.gd spawn_guard)
##   horde_ferried   BREAK: the queue ran out first; FLOOD fills it (realm_sim.gd:666 -> the seed's backlog -> horde0)
##   fronts_held     FRONTS: the fronts' have is the big undead on them (VeiFronts.have_need); FLOOD adds to Swarm and Raw only
## `facts`: last_hit_src, fronts_cleared (ids). Returns the key into words.change; "fronts_held_flood" is the fronts line
## with the FLOOD clause, chosen only when Swarm or Raw is among those that held.
static func loss_change_key(reason: String, facts: Dictionary) -> String:
	match reason:
		"relish_unmade":
			match str(facts.get("last_hit_src", "")):
				"weave":
					return "weave"
				"living":
					return "living"
		"horde_ferried":
			return "horde_ferried"
		"fronts_held":
			var cleared: Array = facts.get("fronts_cleared", [])
			for id in ["swarm", "raw"]:
				if not cleared.has(id):
					return "fronts_held_flood"
			return "fronts_held"
	return "fallback"


## The loss card's TRY NEXT row: {label, text, key} (the text of loss_change_key from raid.json vei_loss.change).
static func loss_change(reason: String, facts: Dictionary, words: Dictionary) -> Dictionary:
	var lines: Dictionary = words.get("change", {})
	var text := str(lines.get(loss_change_key(reason, facts), lines.get("fallback", "")))
	if text == "":
		return {}
	return {"label": str(words.get("change_label", "")), "text": text, "key": "text"}


## loss_card(seed, spent, party_lost, fight_t, end_reason, keep, death_words) -> Dictionary
##   What the Vei loss card prints (D-e close-out), in the win card's frame (`end_card`): time_text, the
##   backups spent and the big undead lost (the same keys; on a loss all of the seed's party, MECHANICS §6),
##   `ended` (raid.json vei_loss.ended for the reason, passed as `loss_words`; an unknown
##   one reads vei_loss.ended_unknown, "the fight is lost"), `keep_pct` (loss_backlog_keep as a whole percent) and `keep_text`
##   ("35% stays"), and `after`, the AFTER row, only for a final death (relish_unmade; with fronts_held or
##   horde_ferried she is alive at Vei, so no row). The AFTER row is RaidLogic.death_next_row's text on the
##   seed's `death_ends` (`death_words` is raid.json's `death` block: "unmade · reforms at Covington", " in N"
##   when respawn_s > 0, " · the town takes a morale shock"); a final death has spent every clone, so a seed
##   without `death_ends` reads the unmade words with no number, never the seed's clones_ready.
##   The backlog is a share, not a number: economy multiplies Vei's live queue at the writeback
##   (STATE-API §8.3, `vei.undead_queue ×= loss_backlog_keep`), which is not the seed's backlog (the
##   queue moves while she is away) and not what is left after `backlog_spent` (informational, A10).
static func loss_card(seed: Dictionary, spent: Dictionary, party_lost: Array, fight_t: float,
		end_reason: String, keep: float, death_words: Dictionary, loss_words := {}) -> Dictionary:
	var info := end_card(seed, spent, party_lost, fight_t, 0.0, 0.0)
	info.erase("backlog_spent")
	info["party_lost"] = info["party"]   # a lost fight kills the whole party (MECHANICS §6, STATE-API §8.3), not only the ones that fell in the scene
	info["lost"] = true
	info["reason"] = end_reason
	info["ended"] = str((loss_words.get("ended", {}) as Dictionary).get(end_reason, loss_words.get("ended_unknown", "")))
	var pct := clampi(roundi(keep * 100.0), 0, 100)
	info["keep_pct"] = pct
	info["keep_text"] = RaidLogic.word_fmt(loss_words, "keep_text", [pct])
	var after := {}
	if end_reason == "relish_unmade":
		var de: Variant = seed.get("death_ends", null)
		var s := {"clones_ready": 0}
		if de is Dictionary:
			s["death_ends"] = de
		after = RaidLogic.death_next_row(s, death_words)
	info["after"] = after
	return info
