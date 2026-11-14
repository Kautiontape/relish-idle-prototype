class_name HudLogic
extends RefCounted
## Pure HUD logic (no autoloads, so headless tests can compile it): the rates-first top bar's
## items, the odds / sign / drain status, the objective line, and the lane "why" callouts' text,
## ordering and greedy non-overlapping placement. Tuning lives in configs/map_view.json.

const LABELS := {"mint": "MINT", "workers": "WORKERS", "bodies": "BODIES", "gold": "GOLD", "bone": "BONE", "living": "LIVING"}
const ARROW := "→"
const DOT := "·"


## The debug speed row exists only in a debug session (IDLE I9): `state` is the GameState, or
## anything with debug_enabled.
static func speed_row_shown(state) -> bool:
	return state != null and bool(state.get("debug_enabled"))


## One item per view_hud rate row, in the view's order (HUD_RATE_IDS):
## {id, label, rate_text, stock_text, capped, cap_mark}. The signed net rate comes first on
## screen; stock_text is "" for a stock of -1 (mint) and "40/200" when the stream has a cap.
static func rate_items(hud: Dictionary) -> Array:
	var out: Array = []
	var mark := str(MapLogic.cfg().get("cap_mark", ""))
	for r in hud.get("rates", []):
		var id := str(r.get("id", ""))
		var stock := float(r.get("stock", -1.0))
		var cap := float(r.get("cap", -1.0))
		var has_stock := stock >= 0.0
		var capped := has_stock and cap >= 0.0 and roundi(stock) >= roundi(cap)
		var stock_text := ""
		if has_stock:
			stock_text = MapLogic.fmt_mass(stock)
			if cap >= 0.0:
				stock_text += "/" + MapLogic.fmt_mass(cap)
		out.append({"id": id, "label": LABELS.get(id, id.to_upper()),
			"rate_text": MapLogic.fmt_rate(float(r.get("rate", 0.0))),
			"stock_text": stock_text, "capped": capped, "cap_mark": mark if capped else ""})
	return out


## The bar's one wrapping rule: items of the given `widths` go left to right with `gap` between
## them; an item that would push the row past `max_w` starts a new row (an item alone in a row
## stays, however wide). Returns the rows as arrays of item indices.
static func wrap_rows(widths: Array, gap: float, max_w: float) -> Array:
	var rows: Array = []
	var row: Array = []
	var x := 0.0
	for i in widths.size():
		var w := float(widths[i])
		if not row.is_empty() and x + gap + w > max_w:
			rows.append(row)
			row = []
			x = 0.0
		x += (gap if not row.is_empty() else 0.0) + w
		row.append(i)
	if not row.is_empty():
		rows.append(row)
	return rows


## Whether they are winning, from MapModel.readout() (the same one Vei's node draws):
## {odds_text, sign, sign_text, drain_text}. An empty backlog reads as Vei's node does.
static func status(readout: Dictionary) -> Dictionary:
	var sign := int(readout.get("sign", 0))
	var drain := MapLogic.fmt_drain(float(readout.get("drain_s", -1.0)))
	if float(readout.get("backlog", 1.0)) <= 0.0:
		drain = str(MapLogic.cfg().get("drain_empty_text", ""))
	return {"odds_text": "%d%%" % roundi(clampf(float(readout.get("odds", 0.0)), 0.0, 1.0) * 100.0), "sign": sign,
		"sign_text": MapLogic.sign_glyph(sign), "drain_text": drain}


## Where the toast's top edge sits: `gap` px under the Relish chip's bottom edge (or the HUD's
## inset when the chip is not there), so the two never overlap however tall the bar and chip grow.
static func toast_top(chip_bottom: float, inset: float, gap: float) -> float:
	return maxf(chip_bottom, inset) + gap


## "×10" off 1x speed, else "".
static func speed_text(hud: Dictionary) -> String:
	var ts := float(hud.get("time_scale", 1.0))
	return "" if is_equal_approx(ts, 1.0) else "×%d" % roundi(ts)


## The objective strip: the standing objective, or the victory line once won.
static func objective_text(hud: Dictionary) -> String:
	var cfg := MapLogic.cfg()
	return str(cfg.get("objective_won_text", "")) if hud.get("won", false) else str(cfg.get("objective_text", ""))


# --- lane "why" callouts --------------------------------------------------------

static func node_name(id: String, names: Dictionary) -> String:
	return str(names.get(id, id.capitalize()))


## {head, rate, tail} for a lane row, or {} when its why is empty:
## "WAR → Ashgate " + "+1.2/s" (the rate font) + " · Relish left". The rate is the lane's own
## (view_lanes carries no delta), signed.
static func callout_parts(row: Dictionary, names: Dictionary) -> Dictionary:
	var why := str(row.get("why", ""))
	if why == "":
		return {}
	return {"head": "%s %s %s " % [str(row.get("kind", "")).to_upper(), ARROW, node_name(str(row.get("to", "")), names)],
		"rate": MapLogic.fmt_rate(float(row.get("rate", 0.0))), "tail": " %s %s" % [DOT, why]}


static func callout_text(row: Dictionary, names: Dictionary) -> String:
	var p := callout_parts(row, names)
	return "" if p.is_empty() else str(p["head"]) + str(p["rate"]) + str(p["tail"])


## Lane rows that carry a why, loudest (largest |rate|) first; ties keep their input order.
static func callout_rows(lanes: Array) -> Array:
	var keyed: Array = []
	for i in lanes.size():
		if str(lanes[i].get("why", "")) != "":
			keyed.append([absf(float(lanes[i].get("rate", 0.0))), i])
	keyed.sort_custom(func(a, b): return a[0] > b[0] or (a[0] == b[0] and a[1] < b[1]))
	return keyed.map(func(k): return lanes[k[1]])


## Four plate rects of `size` around `anchor`, in preference order: up-right, down-right,
## up-left, down-left, each `offset` away from the anchor on both axes.
static func candidate_rects(anchor: Vector2, size: Vector2, offset: Vector2) -> Array[Rect2]:
	var out: Array[Rect2] = []
	for sx_sy in [Vector2(1, -1), Vector2(1, 1), Vector2(-1, -1), Vector2(-1, 1)]:
		var x := anchor.x + offset.x if sx_sy.x > 0.0 else anchor.x - offset.x - size.x
		var y := anchor.y + offset.y if sx_sy.y > 0.0 else anchor.y - offset.y - size.y
		out.append(Rect2(Vector2(x, y), size))
	return out


## The point of `plate` nearest `anchor`: where the 1 px leader line ends.
static func leader_end(plate: Rect2, anchor: Vector2) -> Vector2:
	return Vector2(clampf(anchor.x, plate.position.x, plate.end.x), clampf(anchor.y, plate.position.y, plate.end.y))


## Greedy placement. `options[i]` is callout i's candidate rects in preference order. Callouts
## are taken in order: each takes its first candidate that stays `gap` clear of every plate
## placed so far, and is skipped (-1) when none does or `max_count` plates are already down.
## Returns the chosen candidate index per callout.
static func place(options: Array, max_count: int, gap: float) -> Array[int]:
	var picks: Array[int] = []
	var placed: Array[Rect2] = []
	for cands in options:
		var pick := -1
		if placed.size() < max_count:
			for k in cands.size():
				var r: Rect2 = cands[k]
				if not placed.any(func(p: Rect2): return r.grow(gap).intersects(p)):
					pick = k
					break
		if pick >= 0:
			placed.append(cands[pick])
		picks.append(pick)
	return picks
