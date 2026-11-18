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


## The standing objective, or the victory line once won (NextLogic's default and won lines).
static func objective_text(hud: Dictionary) -> String:
	var cfg := MapLogic.cfg()
	return str(cfg.get("objective_won_text", "")) if hud.get("won", false) else str(cfg.get("objective_text", ""))


## Whether the run's goal and the valve's one-line explanation show: while no fort has been taken
## (view_hud.highest_tier_flipped is 0: existing state, no save flag). After that the goal line is
## gone and the valve's explanation stays as its hover tooltip.
static func goal_shown(hud: Dictionary) -> bool:
	return int(hud.get("highest_tier_flipped", 0)) == 0 and not bool(hud.get("won", false))


## The run's goal under the objective strip: the config's lines, one per row.
static func goal_text() -> String:
	return "\n".join(PackedStringArray(MapLogic.cfg().get("clarity", {}).get("goal_lines", [])))


## Whether the fort legend shows expanded: the player's click when there was one (`user`: 1 open,
## 0 closed), else while no fort has been taken (goal_shown), collapsed to a button afterwards.
static func legend_open(hud: Dictionary, user: int) -> bool:
	return goal_shown(hud) if user < 0 else user == 1


## Where the fort legend sits and how it shows, from the real rects. `chip` and `valve` are their
## panels' rects; the legend is `w` wide at left edge `x`, bottom-aligned `gap` above the valve.
## `h_full`, `h_compact` (rows closer together) and `h_closed` (the button) are its heights.
## `want_open`: it would show expanded (the game's default or the player's click); `user_open`: the
## player clicked it open. The Relish chip (when it overlaps the legend's columns) bounds the top:
## the legend's top is at least the chip's bottom plus `gap`. A default-open legend that does not fit
## at full height shows collapsed; one the player opened shows compact if that fits, else collapsed.
## Returns {mode: "full"|"compact"|"closed", rect: Rect2}.
static func legend_place(chip: Rect2, valve: Rect2, x: float, w: float, h_full: float, h_compact: float, h_closed: float,
		want_open: bool, user_open: bool, gap: float) -> Dictionary:
	var bottom := valve.position.y - gap
	var floor_y := -INF
	if chip.size.y > 0.0 and chip.position.x < x + w and chip.end.x > x:
		floor_y = chip.end.y + gap
	var avail := bottom - floor_y
	var mode := "closed"
	if want_open:
		if h_full <= avail:
			mode = "full"
		elif user_open and h_compact <= avail:
			mode = "compact"
	var h := h_full if mode == "full" else (h_compact if mode == "compact" else h_closed)
	return {"mode": mode, "rect": Rect2(x, bottom - h, w, h)}


## The fort state a legend row draws: Vei's and retaken are both a fort of hers (a living square;
## the map tells a retaken one by its danger tag), held draws safe (a diamond), overrun its hollow square.
static func legend_glyph_state(id: String) -> String:
	match id:
		"held":
			return IdleLogic.SAFE
		"overrun":
			return NodeLogic.OVERRUN
	return NodeLogic.HERS


## Where the card's top edge sits: `high` (near the screen's top, the whole height for the card)
## when the HUD's plates (`plates_right`) end `gap` clear of the card's left edge, else `low` (under them).
static func sidebar_top(viewport_w: float, card_w: float, plates_right: float, gap: float, low: float, high: float) -> float:
	return high if plates_right + gap <= viewport_w - card_w else low


## The hover line of a jargon word (the bar's MINT, ODDS, STRAIN, DRAIN; the valve's WORK, WAR,
## FLOOD), from config; "" for a word with none.
static func tip(id: String) -> String:
	return str(MapLogic.cfg().get("clarity", {}).get("tips", {}).get(id, ""))


## The hover line `id` on a Label or Button: its tooltip is tip(id) and it passes the mouse on (a Control
## that ignores the mouse shows no tooltip). A word with no line is left as it was.
static func apply_tip(c: Control, id: String) -> void:
	var text := tip(id)
	if text != "":
		c.tooltip_text = text
		c.mouse_filter = Control.MOUSE_FILTER_PASS


## A screen rect (the open card) in a world-anchored layer's frame, world x zoom (MapCallouts'):
## screen - viewport / 2 + camera position x zoom.
static func screen_to_zoomed(r: Rect2, cam_pos: Vector2, zoom: float, viewport: Vector2) -> Rect2:
	return Rect2(r.position - viewport * 0.5 + cam_pos * zoom, r.size)


# --- lane "why" callouts --------------------------------------------------------

static func node_name(id: String, names: Dictionary) -> String:
	return str(names.get(id, id.capitalize()))


## Vei's tithe telegraph from view_vei().tithe, as {text, fort_id}: the wave running, a warning
## with its ETA, else the next pick with next_s; {"", ""} when there is nothing to say.
static func tithe_line(vei_tithe: Dictionary, names: Dictionary) -> Dictionary:
	var c: Dictionary = MapLogic.cfg()["tithe_line"]
	var target := str(vei_tithe.get("target", ""))
	if target != "":
		if bool(vei_tithe.get("wave_active", false)):
			return {"text": str(c["wave_fmt"]) % node_name(target, names), "fort_id": target}
		var eta := float(vei_tithe.get("eta_s", -1.0))
		if eta >= 0.0:
			return {"text": str(c["warning_fmt"]) % [node_name(target, names), OpeningLogic.eta_text(eta)], "fort_id": target}
	var nxt := str(vei_tithe.get("next_target", ""))
	var next_s := float(vei_tithe.get("next_s", -1.0))
	if nxt != "" and next_s >= 0.0:
		return {"text": str(c["next_fmt"]) % [node_name(nxt, names), OpeningLogic.eta_text(next_s)], "fort_id": nxt}
	return {"text": "", "fort_id": ""}


## The player's words for a view `lever` ("raise_war" -> "Raise WAR"), from bone_line.levers; an
## unknown lever reads as itself, "" as "".
static func lever_text(lever: String) -> String:
	return str(MapLogic.cfg()["bone_line"]["levers"].get(lever, lever))


## The queue head that can never be afforded while the pits eat every body: {} when `head` (a
## view_town().queue row, or {}) is not that.
static func stalled_head(head: Dictionary) -> Dictionary:
	if str(head.get("starved", "")) == "pits_first" and float(head.get("affordable_in_s", 0.0)) < 0.0:
		return head
	return {}


## Whether the pits-first stall is live: the Bone Mill row ({starved, lever}) or the queue head says so.
static func pits_stalled(mill: Dictionary, head: Dictionary) -> bool:
	return str(mill.get("starved", "")) == "pits_first" or not stalled_head(head).is_empty()


## The lever the stall names: the head's, else the mill's.
static func stall_lever(mill: Dictionary, head: Dictionary) -> String:
	var h := stalled_head(head)
	return str(h.get("lever", "")) if not h.is_empty() else str(mill.get("lever", ""))


## The BONE item's one-line warning, or "". A stalled queue head is named with its ETA as never
## and what it is short of ("Inn: never, 7 bone short. The pits eat every body: raise WAR": never a
## number of seconds); else the mill's own stall ("no bone: the pits eat every body. Raise WAR").
## Only pits_first speaks: no_bodies has no lever and says nothing. `building_names` maps ids to
## labels (buildings_view); an id without one is capitalised.
static func bone_line(mill: Dictionary, head: Dictionary, building_names := {}) -> String:
	var c: Dictionary = MapLogic.cfg()["bone_line"]
	var lever := lever_text(stall_lever(mill, head))
	var h := stalled_head(head)
	if not h.is_empty():
		var id := str(h.get("building_id", ""))
		var short := MapLogic.fmt_mass(float(ceili(float(h.get("short", {}).get("bone", 0.0)))))
		var low := lever.substr(0, 1).to_lower() + lever.substr(1)
		return str(c["head_fmt"]) % [str(building_names.get(id, id.capitalize())), short, low]
	if str(mill.get("starved", "")) == "pits_first":
		return str(c["mill_fmt"]) % lever
	return ""


## {head, rate, tail} for a lane row, or {} when its why is empty:
## "WAR → Ashgate " + "+1.2/s" (the rate font) + " · Relish left". The rate is the lane's own
## (view_lanes carries no delta), signed.
static func callout_parts(row: Dictionary, names: Dictionary) -> Dictionary:
	var why := str(row.get("why", ""))
	if why == "":
		return {}
	if bool(row.get("group", false)):
		return {"head": "%s ×%d %s %s %s " % [str(row.get("kind", "")).to_upper(), int(row["count"]), DOT, why, DOT],
			"rate": MapLogic.fmt_rate(float(row.get("rate", 0.0))),
			"tail": " " + str(MapLogic.cfg()["callouts"]["collapse_total_text"])}
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


## callout_rows with same-cause lanes folded: `collapse_min` or more lanes that share a kind, a
## why and a source node become ONE row {group: true, id, kind, from, to: "", why, rate (their sum),
## count}, anchored at that common source (Covington for the valve or staging, Vei for a tithe);
## fewer stay individual. Loudest first again, by the folded rate. `collapse_min` <= 0: no folding.
static func callout_items(lanes: Array, collapse_min: int) -> Array:
	var rows := callout_rows(lanes)
	if collapse_min <= 0:
		return rows
	var groups := {}  # kind|why|from -> {rows, rate}
	for r in rows:
		var key := "%s|%s|%s" % [r.get("kind", ""), r.get("why", ""), r.get("from", "")]
		if not groups.has(key):
			groups[key] = {"rows": [], "rate": 0.0}
		groups[key]["rows"].append(r)
		groups[key]["rate"] += float(r.get("rate", 0.0))
	var keyed: Array = []
	var seen := {}
	for i in rows.size():
		var r: Dictionary = rows[i]
		var key := "%s|%s|%s" % [r.get("kind", ""), r.get("why", ""), r.get("from", "")]
		var g: Dictionary = groups[key]
		if (g["rows"] as Array).size() < collapse_min:
			keyed.append([absf(float(r.get("rate", 0.0))), i, r])
		elif not seen.has(key):
			seen[key] = true
			keyed.append([absf(float(g["rate"])), i, {"group": true, "id": "group:" + key, "kind": r["kind"], "from": r["from"], "to": "",
				"why": r["why"], "rate": g["rate"], "count": (g["rows"] as Array).size()}])
	keyed.sort_custom(func(a, b): return a[0] > b[0] or (a[0] == b[0] and a[1] < b[1]))
	return keyed.map(func(k): return k[2])


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


## How many callouts show: callouts.max_count, or callouts.drag_max_count while the valve is dragged
## (the loudest few, so the map stays readable under the handle).
static func callout_cap(dragging: bool) -> int:
	var c: Dictionary = MapLogic.cfg()["callouts"]
	return int(c["drag_max_count"]) if dragging else int(c["max_count"])


## The chip rects the callouts keep clear of, whole px, as a layout key: a chip that moves (Relish
## stepping on or off a fort) changes it, so the callouts re-place.
static func rects_key(rects: Array) -> Array:
	return rects.map(func(r: Rect2): return [roundi(r.position.x), roundi(r.position.y), roundi(r.size.x), roundi(r.size.y)])


## Greedy placement. `options[i]` is callout i's candidate rects in preference order. Callouts
## are taken in order: each takes its first candidate that stays `gap` clear of every plate
## placed so far and of every `occupied` rect (the open card), and is skipped (-1) when none does
## or `max_count` plates are already down. Returns the chosen candidate index per callout.
static func place(options: Array, max_count: int, gap: float, occupied: Array = []) -> Array[int]:
	var picks: Array[int] = []
	var placed: Array[Rect2] = []
	for cands in options:
		var pick := -1
		if placed.size() < max_count:
			for k in cands.size():
				var r: Rect2 = cands[k]
				if occupied.any(func(o: Rect2): return r.grow(gap).intersects(o)):
					continue
				if not placed.any(func(p: Rect2): return r.grow(gap).intersects(p)):
					pick = k
					break
		if pick >= 0:
			placed.append(cands[pick])
		picks.append(pick)
	return picks


## What the fort labels' rects (MapCallouts._label_rects) depend on: the rev (names, tags), the
## zoom in thousandths, the tier and the fort count. Equal keys, equal rects.
static func label_key(rev: int, zoom: float, tier: String, forts: int) -> Array:
	return [rev, roundi(zoom * 1000.0), tier, forts]


## What MapLegend.refresh depends on: its parent's size, whether it is open (and the player's
## click), the Relish chip's and the valve's rects, the rows' count and `min_h` (the head's and the
## rows' combined minimum heights, summed: wrapped labels settle theirs only after a container layout).
## Refresh runs when it changes.
static func legend_key(area: Vector2, open: bool, open_user: int, chip: Rect2, valve: Rect2, rows: int, min_h: float) -> Array:
	return [area, open, open_user, chip, valve, rows, roundf(min_h * 100.0)]
