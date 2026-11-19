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
		var capped := row_capped(r)
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


## Lays `cells` into `bar` (a VBoxContainer of HBoxContainer rows) as `rows` (wrap_rows' answer) says: row ri's
## box holds rows[ri]'s cells in order. The row boxes are kept and only the cells whose row changed are moved: a
## moved cell re-themes and re-shapes every Label in it, and rebuilding every row on each re-wrap cost ~12 ms a time
## (economy P9 C-d's pre_vei frame spikes). New rows get `gap` px between cells; rows no longer needed are freed.
static func place_rows(bar: Node, cells: Array, rows: Array, gap: int) -> void:
	var boxes: Array = bar.get_children()
	while boxes.size() < rows.size():
		var row := HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_theme_constant_override("separation", gap)
		bar.add_child(row)
		boxes.append(row)
	for ri in rows.size():  # each cell is in exactly one row, so once every row is placed no box holds a stray
		var box: Node = boxes[ri]
		var r: Array = rows[ri]
		for k in r.size():
			var cell: Node = cells[r[k]]
			if cell.get_parent() != box:
				if cell.get_parent() != null:
					cell.get_parent().remove_child(cell)
				box.add_child(cell)
			box.move_child(cell, k)
	for ri in range(rows.size(), boxes.size()):  # rows no longer needed: empty by now
		bar.remove_child(boxes[ri])
		(boxes[ri] as Node).queue_free()


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


## Whether Vei's odds / strain / drain show (her node's readout and the top bar's group): not once the game
## is won. The tithe line and its telegraph are not keyed on this: they follow view data.
## A beaten Vei has no odds to read (P7's design, kept after #21).
static func vei_readout_shown(hud: Dictionary) -> bool:
	return not bool(hud.get("won", false))


## Whether Vei's queue stack shows at her node (its rings and the "+N" past them): not once the game is won and
## the victory set piece has ended (`victory_ended`, MapModel's; the manager's ruling on Session 3's open 1, then
## ruling 2 on Session 4: through RUN and STOP "VEI HAS DROWNED IN THE DEAD" shows over her drowned stack, and the
## stack goes at END, with her lanes). After #21 her queue still grows on a won map (the forts' FLOOD drain, WAR with
## no target), and a beaten Vei's climbing count reads as a threat with nothing to do about it.
## NodeLogic.drawn_backlog applies it; the away panel's queue row goes at the win (AwayLogic.gains_row_shown).
static func vei_queue_shown(hud: Dictionary, victory_ended := true) -> bool:
	return not bool(hud.get("won", false)) or not victory_ended


## Whether the valve panel shows its FLOOD row and corner button: not once the game is won. The panel, its
## drag and Covington's stems then show FLOOD's share as WAR's (ValveLogic.won_valve).
## Since #21 the sim sends FLOOD's share to WAR once won, so the fold is what it does.
static func flood_shown(hud: Dictionary) -> bool:
	return not bool(hud.get("won", false))


## Whether your goal shows under the strip: at every tier (V-I1 item 9), until the game is won (the
## won strip and the victory set piece say the rest).
static func goal_shown(hud: Dictionary) -> bool:
	return not bool(hud.get("won", false))


## Whether the valve's one-line explanation shows: while no fort has been taken (view_hud's
## highest_tier_flipped is 0: existing state, no save flag). After that it stays as its hover tooltip,
## which keeps the left column short once the player knows the valve.
static func valve_explain_shown(hud: Dictionary) -> bool:
	return int(hud.get("highest_tier_flipped", 0)) == 0 and not bool(hud.get("won", false))


## Your goal under the objective strip: the config's lines, one per row. `standing`: the strip shows the
## standing objective (NextLogic.DEFAULT), which already says the second line's FLOOD-and-odds sentence, so
## only the first line shows under it (the goal stays at every tier, V-I1 item 9, without saying it twice).
static func goal_text(standing := false) -> String:
	var lines: Array = MapLogic.cfg().get("clarity", {}).get("goal_lines", [])
	if standing and not lines.is_empty():
		lines = [lines[0]]
	return "\n".join(PackedStringArray(lines))


## Whether the fort legend shows expanded: open until the player closes it (`user`: -1 not chosen yet,
## 1 open, 0 closed), then as they left it.
static func legend_open(user: int) -> bool:
	return user != 0


## The legend's `user` value at start: 0 (closed) when the player closed it earlier (MapSeen's global
## flag, kept across saves and new games), else -1 (not chosen: open).
static func legend_user(closed_by_player: bool) -> int:
	return 0 if closed_by_player else -1


## A legend row's line (clarity.legend.rows[]): its `line`, or once the game is won its `line_won` where it has one
## (the V-I3 round, ruling 2: OVERRUN's "still Vei's" is not true after her death).
static func legend_line(row: Dictionary, won: bool) -> String:
	return str(row["line_won"]) if won and row.has("line_won") else str(row["line"])


## The legend's line under HELD: what the held fort's tag can read, in the chip's own words
## (IdleLogic.word of each margin).
static func held_tag_line() -> String:
	var fmt := str(MapLogic.cfg()["clarity"]["legend"]["held_tag_fmt"])
	return fmt % [IdleLogic.word(IdleLogic.SAFE), IdleLogic.word(IdleLogic.THIN), IdleLogic.word(IdleLogic.WILL_FALL)]


## The cue on the bar that its jargon words explain themselves on hover.
static func hover_cue() -> String:
	return str(MapLogic.cfg()["clarity"]["hover_cue"])


## The bar's last cell (V-I1 item 2: every readout means something on first view): while no fort has been
## taken (bar_key_shown) the key to its jargon in the glossary's words ("MINT: undead your pits make ·
## ODDS: ... · STRAIN: ... · DRAIN: ..."), on the second row beside them, so it costs no height; after that
## the hover cue, since each word still explains itself on hover.
static func bar_cue(hud: Dictionary) -> String:
	return str(MapLogic.cfg()["clarity"]["bar_key"]) if bar_key_shown(hud) else hover_cue()


## Whether the bar's key shows: on first view, while no fort has been taken (view_hud's
## highest_tier_flipped is 0: existing state, no save flag), and not once the game is won.
static func bar_key_shown(hud: Dictionary) -> bool:
	return int(hud.get("highest_tier_flipped", 0)) == 0 and not bool(hud.get("won", false))


## The look of every map tooltip: {plate, border, text, size, pad}. The plate is the panels' own
## (MapUi.plate_box: ground lightened) at tooltip.plate_alpha, so a tooltip over a banner never shows it through.
static func tooltip_style() -> Dictionary:
	var cfg := MapLogic.cfg()
	var tc: Dictionary = cfg["clarity"]["tooltip"]
	var plate := Palette.c("ground").lightened(float(cfg["panel_bg_lighten"]))
	plate.a = float(tc["plate_alpha"])
	return {"plate": plate, "border": Palette.c("contour", float(cfg["panel_border_alpha"])), "text": Palette.c(str(tc["text_key"])),
		"size": int(tc["size_px"]), "pad": int(tc["pad_px"])}


## Where the fort legend sits and how it shows, from the real rects. `chip` and `valve` are their
## panels' rects; the legend is `w` wide at left edge `x`, bottom-aligned `gap` above the valve.
## `h_full`, `h_compact` (rows closer together) and `h_closed` (the button) are its heights.
## `want_open`: it would show expanded (open by default, or as the player left it). The Relish chip (when it
## overlaps the legend's columns) bounds the top: the legend's top is at least the chip's bottom plus
## `gap`. An open legend that does not fit at full height shows compact if that fits, else collapsed
## (the legend is open by default, so compact must serve the default on a short screen too).
## Returns {mode: "full"|"compact"|"closed", rect: Rect2}.
static func legend_place(chip: Rect2, valve: Rect2, x: float, w: float, h_full: float, h_compact: float, h_closed: float,
		want_open: bool, gap: float) -> Dictionary:
	var bottom := valve.position.y - gap
	var floor_y := -INF
	if chip.size.y > 0.0 and chip.position.x < x + w and chip.end.x > x:
		floor_y = chip.end.y + gap
	var avail := bottom - floor_y
	var mode := "closed"
	if want_open:
		if h_full <= avail:
			mode = "full"
		elif h_compact <= avail:
			mode = "compact"
	var h := h_full if mode == "full" else (h_compact if mode == "compact" else h_closed)
	return {"mode": mode, "rect": Rect2(x, bottom - h, w, h)}


## The fort state a legend row draws: Vei's and retaken are both a fort of hers (a living square;
## retaken adds its crack, legend_glyph_retaken), held draws safe (a diamond), overrun its hollow square.
static func legend_glyph_state(id: String) -> String:
	match id:
		"held":
			return IdleLogic.SAFE
		"overrun":
			return NodeLogic.OVERRUN
	return NodeLogic.HERS


## Whether a legend row's glyph wears the retaken mark (the map's crack, NodeLogic.retaken):
## only RETAKEN's, so it and VEI'S differ by shape (V-I1, cr-3 #5).
static func legend_glyph_retaken(id: String) -> bool:
	return id == "retaken"


## Where the card's top edge sits: `high` (near the screen's top, the whole height for the card)
## when the HUD's plates (`plates_right`) end `gap` clear of the card's left edge, else `low` (under them).
static func sidebar_top(viewport_w: float, card_w: float, plates_right: float, gap: float, low: float, high: float) -> float:
	return high if plates_right + gap <= viewport_w - card_w else low


## The hover line of a jargon word (the bar's MINT, ODDS, STRAIN, DRAIN; the valve's WORK, WAR,
## FLOOD), from config; "" for a word with none. Once `hud` says the game is won (view_hud.won), clarity.tips_won's
## line where it has one (the mint's: no FLOOD then).
static func tip(id: String, hud := {}) -> String:
	var c: Dictionary = MapLogic.cfg().get("clarity", {})
	var tw: Dictionary = c.get("tips_won", {})
	if bool(hud.get("won", false)) and tw.has(id):
		return str(tw[id])
	return str(c.get("tips", {}).get(id, ""))


## Which ODDS tip the bar shows: "odds_backups" once view_hud reports backups (economy P3; `backups` is
## MapModel.readout()'s, -1 when unknown), else "odds", which doesn't claim the odds count them.
static func odds_tip_id(backups: int) -> String:
	return "odds_backups" if backups >= 0 else "odds"


## The hover line `id` on a Label or Button: its tooltip is tip(id, hud) and it passes the mouse on (a Control
## that ignores the mouse shows no tooltip). A word with no line is left as it was.
static func apply_tip(c: Control, id: String, hud := {}) -> void:
	var text := tip(id, hud)
	if text != "":
		c.tooltip_text = text
		c.mouse_filter = Control.MOUSE_FILTER_PASS


## Where the plate of a bar word's tooltip goes (screen px). `word`: the word's rect; `tip`: the plate's
## size; `plates`: the HUD's text plates (the bar, strip, goal, leave line's slot, Relish chip, legend, valve);
## `card`: the open fort card (Rect2() closed), avoided but never used as an edge to sit beside. Candidates
## in order, the first clear of every plate and the card and wholly on screen (tooltip.margin_px in) wins:
## (1) just under the word (tooltip.gap_px), pushed down past each plate it meets, at the word's x;
## (2) right of the plates under the bar (the widest end of those the word is not on), just under the plates
## the word is on: over the map. Fallback, when neither is clear: the one overlapping least (the first on a
## tie), then clamped on screen; a plate larger than the viewport less its margins is shrunk to fit, so the
## result is always inside the viewport. `readouts`: the map's own text (Vei's readout and name, Covington's
## labels) in screen px, avoided like the card; candidate (2), which sits over the map, is also pushed down
## past each one it meets (they never set where the plates end).
static func tip_rect(word: Rect2, tip: Vector2, plates: Array, viewport: Vector2, card := Rect2(), readouts := []) -> Rect2:
	var tc: Dictionary = MapLogic.cfg()["clarity"]["tooltip"]
	var gap := float(tc["gap_px"])
	var margin := float(tc["margin_px"])
	var size := Vector2(minf(tip.x, viewport.x - margin * 2.0), minf(tip.y, viewport.y - margin * 2.0))
	var inside := Rect2(Vector2(margin, margin), viewport - Vector2(margin, margin) * 2.0)
	var avoid: Array = plates.duplicate()
	if card.size.x > 0.0 and card.size.y > 0.0:
		avoid.append(card)
	avoid.append_array(readouts)
	var host_end := word.end.y
	var right := 0.0
	for p in plates:
		if (p as Rect2).intersects(word):
			host_end = maxf(host_end, (p as Rect2).end.y)
		else:
			right = maxf(right, (p as Rect2).end.x)
	var down := Rect2(Vector2(word.position.x, word.end.y + gap), size)
	for _i in avoid.size() + 1:
		for p in avoid:
			if down.intersects(p):
				down.position.y = (p as Rect2).end.y + gap
	var over_map := Rect2(Vector2(right + gap, host_end + gap), size)
	for _i in readouts.size() + 1:
		for p in readouts:
			if over_map.intersects(p):
				over_map.position.y = (p as Rect2).end.y + gap
	var cands: Array = [down, over_map]
	var best := Rect2()
	var best_over := INF
	for c in cands:
		var over := 0.0
		for p in avoid:
			var i: Rect2 = (c as Rect2).intersection(p)
			over += maxf(i.size.x, 0.0) * maxf(i.size.y, 0.0)
		if not inside.encloses(c):
			over += 1.0e9  # off screen: worse than any overlap
		if over == 0.0:
			return c
		if over < best_over:
			best_over = over
			best = c
	best.position = Vector2(clampf(best.position.x, inside.position.x, inside.end.x - size.x), clampf(best.position.y, inside.position.y, inside.end.y - size.y))
	return best


## A world-px rect (the map's labels) as a screen rect: (world - camera position) x zoom + viewport / 2.
static func world_to_screen(r: Rect2, cam_pos: Vector2, zoom: float, viewport: Vector2) -> Rect2:
	return Rect2((r.position - cam_pos) * zoom + viewport * 0.5, r.size * zoom)


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


## Whether a view_hud rate row shows the cap mark (▮ FULL): it has a stock and a cap, and the stock rounds to the cap or
## over it, as the bar prints them. rate_items' `capped` and bone_full read this one rule.
static func row_capped(r: Dictionary) -> bool:
	var stock := float(r.get("stock", -1.0))
	var cap := float(r.get("cap", -1.0))
	return stock >= 0.0 and cap >= 0.0 and roundi(stock) >= roundi(cap)


## Whether `hud`'s BONE row shows ▮ FULL (row_capped): false when the hud has no bone row.
static func bone_full(hud: Dictionary) -> bool:
	for r in hud.get("rates", []):
		if str(r.get("id", "")) == "bone":
			return row_capped(r)
	return false


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


## Whether the Bone Mill row's own pits-first stall speaks (the V-I3 round, ruling 1): the mill gets no bone
## (`starved` pits_first), and nothing is short of it: not while BONE shows ▮ FULL (bone_full: the store is at its cap
## or over it, so no build waits on bone), and not on a won game (view_hud.won). `hud` {} reads as neither.
static func mill_speaks(mill: Dictionary, hud: Dictionary) -> bool:
	return str(mill.get("starved", "")) == "pits_first" and not bone_quiet(hud)


## Whether nothing can be short of bone (BONE at ▮ FULL, or the game won): the mill's line is silent then, and BONE's
## warning drops a held line at once (BoneWarn.set_line's `quiet`).
static func bone_quiet(hud: Dictionary) -> bool:
	return bool(hud.get("won", false)) or bone_full(hud)


## Whether the pits-first stall is live: the Bone Mill row ({starved, lever}) while it speaks (mill_speaks, on `hud`),
## or the queue head says so (stalled_head, whatever the store or the game).
static func pits_stalled(mill: Dictionary, head: Dictionary, hud := {}) -> bool:
	return mill_speaks(mill, hud) or not stalled_head(head).is_empty()


## BONE's stall warning on its bar label (the manager's ruling 1 on Session 4, 2026-11-18, option b). `line` is bone_line's
## text now, `now` the HUD's own clock (real seconds: BoneWarn.tick, which calls it every frame while a line is up or
## held, so the hold runs out on time with no new rev), `held` what the last call returned ({} at a mount). A
## line shows at once; once the stall is gone, its last line stays up until bone_line.hold_s has passed since the stall was
## last seen, so a stall that comes and goes every few seconds can't blink it. Once a line has shown, the label keeps the
## room of the widest line it has held, blank when off, until the map reloads (a new MapHud), so the bar keeps its rows and
## the camera its fit. On pre_vei the stall came and went every few seconds, and each re-wrap moved the camera (economy
## P9 C-d's frame spikes). Returns the next `held`.
static func show_bone_warn(warn: Label, line: String, held: Dictionary, now: float) -> Dictionary:
	var out := held
	if line != "":
		out = {"text": line, "seen": now}
	var on := out.has("seen") and now - float(out["seen"]) < float(MapLogic.cfg()["bone_line"]["hold_s"])
	var text := str(out["text"]) if on else ""
	if warn.text != text:
		warn.text = text
	if text != "":
		warn.visible = true  # and it stays in the row from now on, blank when off
		warn.custom_minimum_size.x = maxf(warn.custom_minimum_size.x, warn.get_minimum_size().x)
	return out


## The lever the stall names: the head's, else the mill's.
static func stall_lever(mill: Dictionary, head: Dictionary) -> String:
	var h := stalled_head(head)
	return str(h.get("lever", "")) if not h.is_empty() else str(mill.get("lever", ""))


## The BONE item's one-line warning, or "". A stalled queue head is named with its ETA as never
## and what it is short of ("Inn: never, 7 bone short. The pits eat every body: raise WAR": never a
## number of seconds); else the mill's own stall while it speaks (mill_speaks on `hud`: not at ▮ FULL, not
## once won): "no bone coming in: the pits eat every body. Raise WAR" (the V-I3 round, ruling 1: it is the
## income that is nil, and BONE beside it may hold a store). Only pits_first speaks: no_bodies has no lever
## and says nothing. `building_names` maps ids to labels (buildings_view); an id without one is capitalised.
static func bone_line(mill: Dictionary, head: Dictionary, building_names := {}, hud := {}) -> String:
	var c: Dictionary = MapLogic.cfg()["bone_line"]
	var lever := lever_text(stall_lever(mill, head))
	var h := stalled_head(head)
	if not h.is_empty():
		var id := str(h.get("building_id", ""))
		var short := MapLogic.fmt_mass(float(ceili(float(h.get("short", {}).get("bone", 0.0)))))
		var low := lever.substr(0, 1).to_lower() + lever.substr(1)
		return str(c["head_fmt"]) % [str(building_names.get(id, id.capitalize())), short, low]
	if mill_speaks(mill, hud):
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


## What a bar tooltip's place depends on, in whole px, as a key: the word's rect, the plate's size, the HUD's
## plates, the open card (Rect2() closed) and the viewport. Equal keys mean tip_rect would answer the same,
## so a shown plate is only re-placed when this changes.
static func tip_key(word: Rect2, tip: Vector2, plates: Array, card: Rect2, viewport: Vector2) -> Array:
	return [rects_key([word, card]), [roundi(tip.x), roundi(tip.y)], rects_key(plates), [roundi(viewport.x), roundi(viewport.y)]]


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
## `panel`: NodeLogic.panel_key (the open card's left edge and the world's screen offset; [] closed): the
## labels shift clear of the card.
static func label_key(rev: int, zoom: float, tier: String, forts: int, panel := []) -> Array:
	return [rev, roundi(zoom * 1000.0), tier, forts, panel]


## What MapLegend.refresh depends on: its parent's size, whether it is open (and the player's
## click), the Relish chip's and the valve's rects, the rows' count and `min_h` (the head's and the
## rows' combined minimum heights, summed: wrapped labels settle theirs only after a container layout).
## Refresh runs when it changes.
static func legend_key(area: Vector2, open: bool, open_user: int, chip: Rect2, valve: Rect2, rows: int, min_h: float) -> Array:
	return [area, open, open_user, chip, valve, rows, roundf(min_h * 100.0)]


## How the legend's rows draw for `mode` ("full", "compact", "closed") and the height they settled
## at (0: not measured yet). {visible, alpha}: the rows stay laid out until measured once (hidden
## rows measure one word per line), but a closed legend never shows them: alpha 0 until they hide.
static func legend_rows_state(mode: String, settled_h: float) -> Dictionary:
	var closed := mode == "closed"
	return {"visible": not closed or settled_h <= 0.0, "alpha": 0.0 if closed else 1.0}


## Whether the legend's cached key must be cleared: the rows' settled height was just first set
## (0 before, positive now), so the layout is redone with it.
static func legend_settled_first(prev_h: float, now_h: float) -> bool:
	return prev_h <= 0.0 and now_h > 0.0
