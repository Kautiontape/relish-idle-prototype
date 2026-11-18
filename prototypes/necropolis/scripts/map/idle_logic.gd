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
## down to the bottom of its name plate, or, when the tag line is shown, of the tag's plate under it
## (drawn at NodeLogic.tag_size(), its baseline label_line_px under the name's: the plates
## NodeLogic.fort_label_rects gives).
static func name_bottom_px(second_line: bool) -> float:
	var size := int(MapLogic.cfg()["font_label"])
	if second_line:
		return NodeLogic.label_plate(0.0, 0.0, NodeLogic.tag_size(), float(size) + float(NodeLogic.ncfg()["label_line_px"])).end.y
	return NodeLogic.label_plate(0.0, 0.0, size, float(size)).end.y


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


## Every held fort's chip rect in world px at `zoom`, {id: Rect2}: the drawn places. `forts` is every
## fort, each {id, pos (Vector2), r (ring radius), held, second (a tag line under the name), w (chip
## plate width in screen px, held forts), name_w and tag_w (label text widths in screen px; -1 where
## that label is not drawn)}. `has_token` says whether Relish's token (`token`, `token_r`) is out.
## Chips are placed in fort-id order, so a later one avoids the earlier ones and the result is
## stable from frame to frame. A chip first tries its default (`chip_place` when the token is out,
## else `chip_rect`: under the name, clear of the token), then that same row slid sideways by each of
## chip_slide_fracs of its width (right, then left). It never goes above the ring or beside it: those
## places read as the tithe ring's or the raid word's, not the chip's. A place that does not read as
## its own fort's is dropped (`chip_attached`), as is one over Relish's token; of the rest it takes the first that overlaps no
## other fort's ring, name or tag plate (the plates NodeLogic.fort_label_rects gives, as
## MapCallouts._label_rects uses them) and no chip placed before it (hard), nor `nodes` (soft). `nodes` are the non-fort
## obstacles (`node_obstacles`: Covington and Vei), each {pos, r (disc radius), rects (world-px
## plates)}. When none is free it takes the least hard overlap, then the least soft; when none is
## attached, the default.
static func chip_layout(forts: Array, zoom: float, has_token: bool, token: Vector2, token_r: float, nodes := []) -> Dictionary:
	var z := maxf(zoom, 0.001)
	var c := cfg()
	var tr := token_r + float(c["chip_token_pad_px"]) / z
	var tok := Rect2(token - Vector2(tr, tr), Vector2(tr, tr) * 2.0) if has_token else Rect2()
	var size := int(MapLogic.cfg()["font_label"])
	var off := float(NodeLogic.ncfg()["label_off_px"])
	var plates: Array = []  # {id, rect}: every fort's name and tag plate, in world px
	var held: Array = []
	for f in forts:
		var p: Vector2 = f["pos"]
		if float(f["name_w"]) >= 0.0:
			var at := p + Vector2(0.0, float(f["r"]) + off)
			for pr in NodeLogic.fort_label_rects(float(f["name_w"]), float(f["tag_w"]), size):
				plates.append({"id": f["id"], "rect": Rect2(at + (pr as Rect2).position / z, (pr as Rect2).size / z)})
		if bool(f["held"]):
			held.append(f)
	held.sort_custom(func(a, b): return str(a["id"]) < str(b["id"]))
	var out := {}
	for f in held:
		var p: Vector2 = f["pos"]
		var r := float(f["r"])
		var w := float(f["w"])
		var others: Array = []
		for g in forts:
			if g["id"] != f["id"]:
				others.append(g["pos"])
		var base := chip_rect(p, r, z, bool(f["second"]), w)
		var cands: Array = [chip_place(p, r, z, bool(f["second"]), w, token, token_r, others) if has_token else base]
		for frac in c["chip_slide_fracs"]:  # then under the name, slid right then left by a share of its width
			cands.append(Rect2(base.position + Vector2(base.size.x * float(frac), 0.0), base.size))
			cands.append(Rect2(base.position - Vector2(base.size.x * float(frac), 0.0), base.size))
		# attachment is a hard filter: a place that fails it is dropped, never costed
		var own_plates: Array = []
		for pl in plates:
			if pl["id"] == f["id"]:
				own_plates.append(pl["rect"])
		var best := -1
		var best_cost := Vector2(INF, INF)
		for i in cands.size():
			if not chip_attached(cands[i], f, forts, z, own_plates) or (has_token and (cands[i] as Rect2).intersects(tok)):
				continue  # drifted from its fort, or over Relish's token
			var cost := _chip_cost(cands[i], f, forts, plates, out, tok, has_token, nodes)
			if cost == Vector2.ZERO:
				best = i
				break
			if cost.x < best_cost.x or (cost.x == best_cost.x and cost.y < best_cost.y):
				best_cost = cost
				best = i
		out[f["id"]] = cands[maxi(best, 0)]  # none attached and clear of the token: the default place (chip_place)
	return out


## Whether a chip place still reads as its own fort's on sight, in screen px: its own gap, the
## nearer of the gap from the rect to its own ring's edge and to its own name and tag plates
## (`own_plates`, world-px rects), is at most chip_attach_px, and every other fort's ring edge is at
## least own gap + chip_attach_margin_px from it.
static func chip_attached(rect: Rect2, f: Dictionary, forts: Array, zoom: float, own_plates: Array) -> bool:
	var own := _ring_gap(rect, f["pos"], float(f["r"])) * zoom
	for pr in own_plates:
		own = minf(own, _rect_gap(rect, pr) * zoom)
	if own > float(cfg()["chip_attach_px"]):
		return false
	var need := own + float(cfg()["chip_attach_margin_px"])
	for g in forts:
		if g["id"] != f["id"] and _ring_gap(rect, g["pos"], float(g["r"])) * zoom < need:
			return false
	return true


## The gap in world px between two rects; 0 when they touch or overlap.
static func _rect_gap(a: Rect2, b: Rect2) -> float:
	var dx := maxf(maxf(a.position.x - b.end.x, b.position.x - a.end.x), 0.0)
	var dy := maxf(maxf(a.position.y - b.end.y, b.position.y - a.end.y), 0.0)
	return Vector2(dx, dy).length()


## The gap in world px from `rect` to the edge of the ring at `c` (radius `r`); 0 when they touch.
static func _ring_gap(rect: Rect2, c: Vector2, r: float) -> float:
	var nearest := Vector2(clampf(c.x, rect.position.x, rect.end.x), clampf(c.y, rect.position.y, rect.end.y))
	return maxf(nearest.distance_to(c) - r, 0.0)


## How wrong a chip place is, as Vector2(hard, soft) in world px squared, compared hard first. Hard:
## the area it overlaps other forts' rings, name and tag plates, the chips already placed (`placed`,
## {id: Rect2}) and the token's rect (`tok`). Soft: the area over Covington's and Vei's discs and
## plates (`nodes`), tolerated where nothing else is free. (0, 0) is clear.
static func _chip_cost(rect: Rect2, f: Dictionary, forts: Array, plates: Array, placed: Dictionary, tok: Rect2, has_token: bool, nodes: Array) -> Vector2:
	var soft := 0.0
	var cost := 0.0
	for nd in nodes:
		var np: Vector2 = nd["pos"]
		var nr := float(nd["r"])
		if _disc_hits(rect, np, nr):
			soft += maxf(rect.intersection(Rect2(np - Vector2(nr, nr), Vector2(nr, nr) * 2.0)).get_area(), 1.0)
		for pr in nd["rects"]:
			if rect.intersects(pr):
				soft += rect.intersection(pr).get_area()
	if has_token and rect.intersects(tok):
		cost += rect.intersection(tok).get_area()
	for g in forts:
		if g["id"] == f["id"]:
			continue
		var gp: Vector2 = g["pos"]
		var gr := float(g["r"])
		if _disc_hits(rect, gp, gr):
			cost += maxf(rect.intersection(Rect2(gp - Vector2(gr, gr), Vector2(gr, gr) * 2.0)).get_area(), 1.0)
	for pl in plates:
		if pl["id"] != f["id"] and rect.intersects(pl["rect"]):
			cost += rect.intersection(pl["rect"]).get_area()
	for id in placed:
		if rect.intersects(placed[id]):
			cost += rect.intersection(placed[id]).get_area()
	return Vector2(cost, soft)


## Covington's and Vei's obstacles for `chip_layout`, in world px, from the geometry the node layers
## draw: Covington's glyph disc (cov_half_px), her name and the valve's stream labels (the rects
## NodeLogic.valve_label_layout gives, screen px from her centre, so /zoom); Vei's reach disc
## (NodeLogic.vei_reach) and her "VEI'S DOMAIN" plate (right-aligned, left of her stack, as MapVei
## draws it). `shares` is the valve's {work, war, flood}; `centroid` the forts' mean position;
## `text_w` the label widths in screen px keyed war / flood / work / covington / vei; `labels_on`:
## the stream labels show (not at far zoom).
static func node_obstacles(cov: Vector2, vei: Vector2, vei_radius: float, backlog: float, shares: Dictionary, centroid: Vector2, zoom: float, labels_on: bool, text_w: Dictionary) -> Array:
	var z := maxf(zoom, 0.001)
	var n := NodeLogic.ncfg()
	var size := int(MapLogic.cfg()["font_label"])
	var rects: Array = []
	var lay := NodeLogic.valve_label_layout(NodeLogic.valve_dirs(cov, centroid, vei), NodeLogic.valve_widths(shares), labels_on, z, text_w, float(size))
	for k in lay:
		var r: Rect2 = lay[k]["rect"]
		rects.append(Rect2(cov + r.position / z, r.size / z))
	var b := NodeLogic.backlog_rings(backlog)
	var r_out := NodeLogic.vei_struct_radius(vei_radius) + float(n["backlog_first_gap_px"]) + maxi(int(b["rings"]) - 1, 0) * float(n["backlog_step_px"])
	var vw := float(text_w["vei"])
	var vp := NodeLogic.label_plate(-vw, vw, size, size * float(n["text_mid_ratio"]))
	var at := Vector2(vei.x - r_out - float(n["odds_gap_px"]), vei.y)
	return [{"pos": cov, "r": float(n["cov_half_px"]), "rects": rects},
		{"pos": vei, "r": NodeLogic.vei_reach(vei_radius, backlog), "rects": [Rect2(at + vp.position / z, vp.size / z)]}]


## Whether the disc at `c` (radius `r`) touches `rect`.
static func _disc_hits(rect: Rect2, c: Vector2, r: float) -> bool:
	var nearest := Vector2(clampf(c.x, rect.position.x, rect.end.x), clampf(c.y, rect.position.y, rect.end.y))
	return nearest.distance_to(c) < r


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


# --- layout cache keys -------------------------------------------------------------

## The grid cell Relish's token is in, `cell` world px a side (cells centred on multiples of it, as
## MapCallouts._chip_signature rounds): the chip layout is keyed on it, so her travel re-lays out
## only on crossing a cell.
static func token_cell(pos: Vector2, cell: float) -> Vector2i:
	var g := maxf(cell, 0.001)
	return Vector2i(roundi(pos.x / g), roundi(pos.y / g))


## The cell's centre, world px: the token position the layout is computed for (the real one is
## within token_pad of it).
static func token_center(c: Vector2i, cell: float) -> Vector2:
	return Vector2(c) * cell


## How far the real token can be from its cell's centre: half the cell's diagonal. Added to the
## token's radius so a layout kept for the cell still clears her.
static func token_pad(cell: float) -> float:
	return cell * sqrt(0.5)


## What MapFortIdle._layout's result depends on, as a cache key: every input that can change it
## between frames. `inp`: zoom, tier, rev, forts (count), cell (Vector2i, ZERO with no token),
## has_token, margin_sig, shares (the valve shares node_obstacles gets), backlog, vei_radius,
## cov_pos, vei_pos, widths (each held fort's chip width, in order: its clock ticks between revs).
static func layout_key(inp: Dictionary) -> Array:
	return [inp["rev"], inp["zoom"], inp["tier"], inp["forts"], inp["has_token"], inp["cell"], inp["margin_sig"], inp["shares"],
		inp["backlog"], inp["vei_radius"], inp["cov_pos"], inp["vei_pos"], inp["widths"]]
