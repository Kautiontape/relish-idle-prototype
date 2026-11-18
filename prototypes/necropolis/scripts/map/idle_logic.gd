class_name IdleLogic
extends RefCounted
## Pure logic for the idle surfaces' margins (IDLE section 3; no autoloads, so headless tests
## compile it): whether WAR staging supports a held fort (SAFE / THIN / WILL FALL), "WAR supports
## N of M held forts", and the projection of a dragged valve. Every number is the view's own
## (view_fort's margin, garrison, garrison_rate and fall_s; view_hud's war_supports;
## view_projection's); nothing is computed here. Only a margin of "safe" is safe: a held fort whose
## margin is "" shows no margin word. Tuning: configs/map_view.json "idle".

const SAFE := "safe"
const THIN := "thin"
const WILL_FALL := "will_fall"
const PROJECTION_KEYS := ["split", "workers_steady", "war_supports", "margins", "backlog_diff"]
const DAY_S := 86400.0


static func cfg() -> Dictionary:
	return MapLogic.cfg().get("idle", {})


# --- margins -----------------------------------------------------------------------

static func held_forts(forts: Array) -> Array:
	var out: Array = []
	for f in forts:
		if bool(f.get("held", false)):
			out.append(f)
	return out


## Your undead mass at a fort: view_fort.garrison.
static func garrison(f: Dictionary) -> float:
	return float(f.get("garrison", 0.0))


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


# --- the fall clock ------------------------------------------------------------------

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


## Every held fort's committed clock, {id: {rate, fall_s}}: view_fort's garrison_rate and fall_s
## (fall_s -1.0 = not falling; during the grace it includes the grace left).
static func committed_clocks(forts: Array) -> Dictionary:
	var out := {}
	for f in held_forts(forts):
		out[str(f["id"])] = {"rate": float(f.get("garrison_rate", 0.0)), "fall_s": float(f.get("fall_s", -1.0))}
	return out


## The clocks at a dragged valve: the committed ones, with each held fort the projection has
## (`real_margins`, view_projection's {id: {margin, fall_s, garrison_rate, ...}}) read from it.
static func projected_clocks(committed: Dictionary, real_margins: Dictionary) -> Dictionary:
	var out := committed.duplicate()
	for id in real_margins:
		out[str(id)] = {"rate": float(real_margins[id].get("garrison_rate", 0.0)), "fall_s": float(real_margins[id].get("fall_s", -1.0))}
	return out


## A projection's margins as words, {id: "thin"}, from view_projection's {id: {margin, ...}}.
static func margin_words(ms: Dictionary) -> Dictionary:
	var out := {}
	for id in ms:
		out[id] = str(ms[id].get("margin", ""))
	return out


## How long a held fort lasts if left alone, in seconds: the view's fall_s (the `clock`'s), or
## -1.0 when it is not falling. The fort itself is not read: view_fort's old hold-timer field is a
## dead stub (always 0.0) and counts for nothing.
static func fort_horizon(_f: Dictionary, clock: Dictionary) -> float:
	return float(clock.get("fall_s", -1.0))


## The chip's parts for a held fort under its name: line one the garrison (an upright count) and
## its signed rate, line two the margin word (none for a margin of "") and, while falling, "falls in
## ~2 h" (the fort's horizon, fort_horizon; a SAFE fort with none says "holds").
## {count, rate, word, key, fall}; `clock` is {rate, fall_s}.
static func chip_parts(f: Dictionary, m: String, clock: Dictionary, c := {}) -> Dictionary:
	if c.is_empty():
		c = cfg()
	var fall := fmt_fall(fort_horizon(f, clock), c)
	var tail := (str(c["fall_fmt"]) % fall) if fall != "" else ""
	if tail == "" and m == SAFE:  # a SAFE fort whose clock holds says so: "SAFE · holds"
		tail = str(c["hold_text"])
	return {"count": garrison_text(f, c), "rate": MapLogic.fmt_rate(float(clock.get("rate", 0.0))),
		"word": word(m), "key": color_key(m), "fall": tail}


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


## The committed margins {id: word} of the held forts: view_fort.margin. A held fort whose margin
## is "" keeps it: no word, never SAFE.
static func committed_margins(forts: Array) -> Dictionary:
	var out := {}
	for f in held_forts(forts):
		out[str(f["id"])] = str(f.get("margin", ""))
	return out


## The committed "WAR supports N of M": view_hud.war_supports.
static func committed_supports(hud: Dictionary) -> Dictionary:
	return hud.get("war_supports", {"n": 0, "m": 0})


# --- projection ------------------------------------------------------------------

## What a dragged valve would do, view_projection(valve)'s: {split, workers_steady, war_supports:
## {n, m}, backlog_diff, margins: {id: word}, clocks: {id: {rate, fall_s}}} (the clocks are the
## committed ones for a held fort the projection does not carry). `state` is the GameState.
static func projection(state, valve: Dictionary, forts: Array) -> Dictionary:
	var real: Dictionary = state.view_projection(ValveLogic.normalise(valve))
	var out := {}
	for k in PROJECTION_KEYS:
		out[k] = real[k]
	out["margins"] = margin_words(real["margins"])
	out["clocks"] = projected_clocks(committed_clocks(forts), real["margins"])
	return out


## The split (mass/s) view_projection gives at `valve` (the current valve, for the deltas a drag
## makes, so a drag back onto it shifts nothing).
static func split_at(state, valve: Dictionary) -> Dictionary:
	return state.view_projection(ValveLogic.normalise(valve))["split"]


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
