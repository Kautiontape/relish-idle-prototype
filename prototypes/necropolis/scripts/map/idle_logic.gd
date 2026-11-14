class_name IdleLogic
extends RefCounted
## Pure logic for the idle surfaces' margins (IDLE section 3; no autoloads, so headless tests
## compile it): whether WAR staging supports a held fort (SAFE / THIN / WILL FALL), "WAR supports
## N of M held forts", and the projection of a dragged valve. Every read is "the real API field
## when GameState has it, else the stand-in here". Tuning: configs/map_view.json "idle".

const SAFE := "safe"
const THIN := "thin"
const WILL_FALL := "will_fall"
const PROJECTION_KEYS := ["split", "workers_steady", "war_supports", "margins", "backlog_diff"]
const DAY_S := 86400.0


static func cfg() -> Dictionary:
	return MapLogic.cfg().get("idle", {})


# --- margins -----------------------------------------------------------------------

## safe when support >= margin_safe_ratio x pressure, thin when >= margin_thin_ratio x pressure,
## else will_fall. No pressure is always safe.
# TODO(api-request #7): view_fort.margin
static func margin(support_rate: float, pressure_rate: float, c := {}) -> String:
	if c.is_empty():
		c = cfg()
	if pressure_rate <= 0.0:
		return SAFE
	if support_rate >= float(c["margin_safe_ratio"]) * pressure_rate:
		return SAFE
	if support_rate >= float(c["margin_thin_ratio"]) * pressure_rate:
		return THIN
	return WILL_FALL


static func held_forts(forts: Array) -> Array:
	var out: Array = []
	for f in forts:
		if bool(f.get("held", false)):
			out.append(f)
	return out


## WAR staging split evenly across the held forts: holding more thins every garrison.
static func support_per_fort(split_war: float, held_count: int) -> float:
	return split_war / float(held_count) if held_count > 0 else 0.0


## {fort_id: margin} for every held fort at a WAR split (mass/s).
# TODO(api-request #7): view_fort.margin
static func margins(forts: Array, split_war: float, c := {}) -> Dictionary:
	var held := held_forts(forts)
	var support := support_per_fort(split_war, held.size())
	var out := {}
	for f in held:
		out[str(f["id"])] = margin(support, float(f.get("ship_in", 0.0)), c)
	return out


## {n, m}: m = the held count, n = how many are not will_fall at that split.
# TODO(api-request #7): view_hud.war_supports
static func war_supports(split_war: float, held: Array, c := {}) -> Dictionary:
	var ms := margins(held, split_war, c)
	var n := 0
	for id in ms:
		if ms[id] != WILL_FALL:
			n += 1
	return {"n": n, "m": held_forts(held).size()}


## Your undead mass at a fort.
# TODO(api-request #7): view_fort.garrison
static func garrison(f: Dictionary) -> float:
	return float(f["garrison"]) if f.has("garrison") else float(f.get("undead", 0.0))


## The garrison as the chip counts it, and as many worker glyphs as the fort draws at near zoom:
## garrison / garrison_unit_mass, rounded half away from zero (fmt_mass's rounding), never negative.
static func garrison_units(f: Dictionary, c := {}) -> int:
	if c.is_empty():
		c = cfg()
	return maxi(roundi(garrison(f) / maxf(float(c.get("garrison_unit_mass", 1.0)), 0.001)), 0)


## The garrison chip's text: garrison_fmt with garrison_units (thousands separated).
static func garrison_text(f: Dictionary, c := {}) -> String:
	if c.is_empty():
		c = cfg()
	return str(c["garrison_fmt"]) % MapLogic.fmt_mass(garrison_units(f, c))


# --- the fall clock (api-request #13) ------------------------------------------------

## Whether the committed streams are known: after a load the views read 0 until the first substep
## (STATE-API 5.1), and a 0 WAR split would read as no support at all.
static func streams_known(hud: Dictionary) -> bool:
	if ValveLogic.mint_rate(hud) > 0.0:
		return true
	for k in ValveLogic.KEYS:
		if float(hud.get("split", {}).get(k, 0.0)) > 0.0:
			return true
	return false


## The garrison's net rate at a held fort (mass/s): the view's garrison_rate, else the stand-in
## support_per_fort - pressure (WAR's even share minus Vei's living arriving), at `split_war`.
# TODO(api-request #13): view_fort.garrison_rate
static func garrison_rate(f: Dictionary, split_war: float, held_count: int) -> float:
	if f.has("garrison_rate"):
		return float(f["garrison_rate"])
	return support_per_fort(split_war, held_count) - float(f.get("ship_in", 0.0))


## Seconds until a garrison of `g` is gone at `rate`: g / -rate while the rate is negative, else
## -1.0 (holding).
# TODO(api-request #13): view_fort.fall_s (this stand-in goes when the view carries it)
static func fall_after(g: float, rate: float) -> float:
	if rate >= 0.0:
		return -1.0
	return maxf(g, 0.0) / -rate


## "~40 min", "~2 h", "~1 d" (rounded, never under 1); "" while holding (s < 0).
static func fmt_fall(s: float, c := {}) -> String:
	if c.is_empty():
		c = cfg()
	if s < 0.0:
		return ""
	if s < AwayLogic.HOUR_S:
		return str(c["fall_min_fmt"]) % maxi(roundi(s / AwayLogic.MIN_S), 1)
	if s < DAY_S:
		return str(c["fall_h_fmt"]) % maxi(roundi(s / AwayLogic.HOUR_S), 1)
	return str(c["fall_d_fmt"]) % maxi(roundi(s / DAY_S), 1)


## Every held fort's committed clock, {id: {rate, fall_s}}: the view's garrison_rate and fall_s
## where it has them, else the stand-ins at the committed WAR split. Before the first substep the
## stand-in rate is 0 (holding): the streams are not known yet.
static func committed_clocks(forts: Array, hud: Dictionary) -> Dictionary:
	var held := held_forts(forts)
	var war := float(hud.get("split", {}).get("war", 0.0))
	var known := streams_known(hud)
	var out := {}
	for f in held:
		var rate := garrison_rate(f, war, held.size()) if (known or f.has("garrison_rate")) else 0.0
		var fall := float(f["fall_s"]) if f.has("fall_s") else fall_after(garrison(f), rate)
		out[str(f["id"])] = {"rate": rate, "fall_s": fall}
	return out


## The clocks at a dragged valve: each committed rate shifted by the change in WAR's per-fort
## share (`war_proj` against the committed `war_now`), and its fall from the projection's fall_s
## when `real` (view_projection) has one, else the stand-in. A real garrison_rate (same two
## shapes) replaces the shifted rate, and the stand-in fall follows it. `real` may carry fall_s as a
## {id: float} dict or inside {id: {margin, fall_s}} margins (api-request #13 allows either).
static func projected_clocks(forts: Array, committed: Dictionary, war_now: float, war_proj: float, real := {}) -> Dictionary:
	var held := held_forts(forts)
	var shift := support_per_fort(war_proj, held.size()) - support_per_fort(war_now, held.size())
	var out := {}
	for f in held:
		var id := str(f["id"])
		var rr = _real_rate(real, id)
		var rate := float(rr) if rr != null else float(committed.get(id, {}).get("rate", 0.0)) + shift
		var fall := fall_after(garrison(f), rate)
		var rf = _real_fall(real, id)
		if rf != null:
			fall = float(rf)
		out[id] = {"rate": rate, "fall_s": fall}
	return out


## The projection's own garrison_rate for `id` (api-request #13), in either shape, or null: the
## chip shows it in place of the stand-in shift, so a real fall_s never sits by a stand-in rate.
static func _real_rate(real: Dictionary, id: String):
	if real.get("garrison_rate", null) is Dictionary and real["garrison_rate"].has(id):
		return real["garrison_rate"][id]
	var m = real.get("margins", {}).get(id, null)
	if m is Dictionary and m.has("garrison_rate"):
		return m["garrison_rate"]
	return null


## The projection's fall_s for `id`, or null.
# TODO(api-request #13): view_projection fall_s, in either shape (this unwrapping goes with the stand-in)
static func _real_fall(real: Dictionary, id: String):
	if real.get("fall_s", null) is Dictionary and real["fall_s"].has(id):
		return real["fall_s"][id]
	var m = real.get("margins", {}).get(id, null)
	if m is Dictionary and m.has("fall_s"):
		return m["fall_s"]
	return null


## A margins dict with every entry a margin word: {id: "thin"} or {id: {margin, fall_s}} in.
static func margin_words(ms: Dictionary) -> Dictionary:
	var out := {}
	for id in ms:
		out[id] = str(ms[id].get("margin", "")) if ms[id] is Dictionary else str(ms[id])
	return out


## The chip's parts for a held fort under its name: line one the garrison (an upright count) and
## its signed rate, line two the margin word and, while falling, "falls in ~2 h".
## {count, rate, word, key, fall}; `clock` is {rate, fall_s}.
static func chip_parts(f: Dictionary, m: String, clock: Dictionary, c := {}) -> Dictionary:
	if c.is_empty():
		c = cfg()
	var fall := fmt_fall(float(clock.get("fall_s", -1.0)), c)
	return {"count": garrison_text(f, c), "rate": MapLogic.fmt_rate(float(clock.get("rate", 0.0))),
		"word": word(m), "key": color_key(m), "fall": (str(c["fall_fmt"]) % fall) if fall != "" else ""}


# --- the chip's place: one plate under the fort's name -------------------------------------

## Screen px from a fort's name anchor (MapFortRing's label, r + label_off_px under the centre)
## down to the bottom of its name plate, and of the first-dungeon line under it when shown.
static func name_bottom_px(second_line: bool) -> float:
	var n := NodeLogic.ncfg()
	var size := float(MapLogic.cfg()["font_label"])
	var bottom := size * (1.0 - float(n["plate_ascent"]) + float(n["plate_height"]))
	return bottom + (float(n["label_line_px"]) if second_line else 0.0)


## Screen px from the name anchor to the chip plate's top: just under the name (and the
## first-dungeon line), chip_gap_px apart.
static func chip_top_px(second_line: bool) -> float:
	return name_bottom_px(second_line) + float(cfg()["chip_gap_px"])


## The chip plate's height in screen px: two lines, chip_line_px apart, and the pads above and
## below (chip_pad_y_px; chip_pad_px is the sides').
static func chip_height_px() -> float:
	var c := cfg()
	return 2.0 * float(c["chip_pad_y_px"]) + float(c["chip_line_px"]) + float(c["chip_font"]) * float(c["plate_height"])


## Whether held forts' chips show: mid and near zoom, from chip_min_zoom (in mid's hysteresis band
## under it, a chip's screen-px plate is so tall in world px it could sit nearer a neighbour).
static func chip_shown(tier: String, zoom: float) -> bool:
	return tier != "far" and zoom >= float(cfg()["chip_min_zoom"])


## The chip's rect in world px at `zoom`, centred under the fort at `p` (ring radius `r`),
## `width_px` screen px wide.
static func chip_rect(p: Vector2, r: float, zoom: float, second_line: bool, width_px: float) -> Rect2:
	var z := maxf(zoom, 0.001)
	var top := p.y + r + float(NodeLogic.ncfg()["label_off_px"]) + chip_top_px(second_line) / z
	return Rect2(p.x - width_px * 0.5 / z, top, width_px / z, chip_height_px() / z)


## Where the chip plate really goes, in world px: `chip_rect`, moved clear of Relish's drawn
## token when they would intersect. The token's rect is `token` +- `token_r` (her halo radius plus
## its capped glow, in world px) padded by chip_token_pad_px screen px. The chip drops to just
## under the token (same x); where that lands nearer another fort in `others` (their centres)
## than its own fort `p`, it slides sideways instead (the token's nearer side, then the other), same y. A chip
## already clear is returned unmoved. Where neither lands nearer its own fort, the one that is
## less wrong (the larger margin) wins. `others` excludes the fort itself.
static func chip_place(p: Vector2, r: float, zoom: float, second_line: bool, width_px: float, token: Vector2, token_r: float, others: Array) -> Rect2:
	var base := chip_rect(p, r, zoom, second_line, width_px)
	var pad := float(cfg()["chip_token_pad_px"]) / maxf(zoom, 0.001)
	var tr := token_r + pad
	var tok := Rect2(token - Vector2(tr, tr), Vector2(tr, tr) * 2.0)
	if not base.intersects(tok):
		return base
	var down := Rect2(Vector2(base.position.x, tok.end.y), base.size)
	if _nearest_own(down, p, others):
		return down
	# the side step, on the plate's own row: the token's nearer side first, then the other
	var right := Rect2(Vector2(tok.end.x, base.position.y), base.size)
	var left := Rect2(Vector2(tok.position.x - base.size.x, base.position.y), base.size)
	var sides := [right, left] if token.x < base.get_center().x else [left, right]
	var best := down
	for cand in sides:
		if _nearest_own(cand, p, others):
			return cand
	for cand in sides:
		if _margin(cand, p, others) > _margin(best, p, others):
			best = cand
	return best


## How much nearer its own fort `p` the rect's centre is than the nearest of `others` (negative: nearer another).
static func _margin(rect: Rect2, p: Vector2, others: Array) -> float:
	var own := rect.get_center().distance_to(p)
	var best := INF
	for o in others:
		best = minf(best, rect.get_center().distance_to(o) - own)
	return best


## Whether `rect`'s centre is nearer `p` (its own fort) than every point in `others`.
static func _nearest_own(rect: Rect2, p: Vector2, others: Array) -> bool:
	var own := rect.get_center().distance_to(p)
	for o in others:
		if rect.get_center().distance_to(o) <= own:
			return false
	return true


## The committed margins: the view's per-fort field where it has one, else the stand-in at the
## committed WAR split.
static func committed_margins(forts: Array, hud: Dictionary, c := {}) -> Dictionary:
	var fallback := margins(forts, float(hud.get("split", {}).get("war", 0.0)), c)
	var out := {}
	for f in held_forts(forts):
		var id := str(f["id"])
		out[id] = str(f["margin"]) if (f.has("margin") and str(f["margin"]) != "") else str(fallback.get(id, SAFE))
	return out


## The committed "WAR supports N of M": the view's field, else the stand-in at the committed split.
static func committed_supports(hud: Dictionary, forts: Array, c := {}) -> Dictionary:
	if hud.has("war_supports"):
		return hud["war_supports"]
	return war_supports(float(hud.get("split", {}).get("war", 0.0)), forts, c)


# --- projection ------------------------------------------------------------------

## What a dragged valve would do: {split, workers_steady, war_supports: {n, m}, margins, clocks}.
## clocks: {id: {rate, fall_s}}, the committed clocks moved by the dragged WAR share.
## `state` is the GameState (or anything with view_projection): its real projection wins field
## by field; without it the stand-in over `forts` answers.
# TODO(api-request #7): view_projection(valve)
static func projection(state, hud: Dictionary, valve: Dictionary, forts: Array, c := {}) -> Dictionary:
	var held := held_forts(forts)
	var out := ValveLogic.project(hud, valve, held.size())
	var war: float = out["split"]["war"]
	out["margins"] = margins(forts, war, c)
	out["war_supports"] = war_supports(war, held, c)
	var real := {}
	if state != null and state.has_method("view_projection"):
		real = state.view_projection(ValveLogic.normalise(valve))
		for k in PROJECTION_KEYS:
			if real.has(k):
				out[k] = real[k]
	out["margins"] = margin_words(out["margins"])
	out["clocks"] = projected_clocks(forts, committed_clocks(forts, hud), float(split_at(state, hud, hud.get("valve", valve), held.size()).get("war", 0.0)),
		float(out["split"]["war"]), real)
	return out


## The split (mass/s) the same projection gives at `valve` (the current valve, for the deltas a
## drag makes, so a drag back onto it shifts nothing): the real projection's when the state has
## one with a split, else the stand-in's.
static func split_at(state, hud: Dictionary, valve: Dictionary, held_count: int) -> Dictionary:
	if state != null and state.has_method("view_projection"):
		var real: Dictionary = state.view_projection(ValveLogic.normalise(valve))
		if real.has("split"):
			return real["split"]
	return ValveLogic.project(hud, valve, held_count)["split"]


## The projection the valve panel shows: while dragging, the dragged valve's own; otherwise its
## "WAR supports N of M" is the committed one (`committed_now` = MapModel.supports_now()), so the
## panel, the chips and the glyphs share one source while the split slews to the target.
static func panel_projection(proj: Dictionary, committed_now: Dictionary, dragging: bool) -> Dictionary:
	if dragging:
		return proj
	var out := proj.duplicate()
	out["war_supports"] = committed_now
	return out


# --- chip text ---------------------------------------------------------------------

static func word(m: String) -> String:
	return str(cfg().get("words", {}).get(m, ""))


static func color_key(m: String) -> String:
	return str(cfg().get("colors", {}).get(m, "text"))
