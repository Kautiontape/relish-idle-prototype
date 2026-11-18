class_name RelishLogic
extends RefCounted
## Pure logic for steering Relish from the map (no autoloads, so headless tests compile it): the
## chip's text and buttons, the m:ss ETA, the plain-words refusal reasons, the card's action list
## (MOVE / CANCEL / DESCEND / HAUL, built from the views) and the route preview versus the
## travel route. Words live in configs/map_view.json ("controls").

const DOT := "·"
const ARROW := "→"


static func _c() -> Dictionary:
	return MapLogic.cfg().get("controls", {})


## "m:ss" from seconds, rounded UP so a countdown never reads 0:00 before it ends (a trip with
## 0.4 s left reads 0:01); negative reads 0:00. eta_ceil_eps_s absorbs float noise, so 60.0000001
## still reads 1:00.
static func fmt_eta(s: float) -> String:
	var n := maxi(ceili(s - float(_c().get("eta_ceil_eps_s", 0.0))), 0)
	return "%d:%02d" % [n / 60, n % 60]


## Seconds to cover `dist` px at `speed` px/s (0 when she has no speed).
static func eta_s(dist: float, speed: float) -> float:
	return dist / speed if speed > 0.0 else 0.0


## A refusal's reason in plain words, from config; unknown reasons get the generic fallback.
static func reason_text(reason: String) -> String:
	var table: Dictionary = _c().get("reasons", {})
	if table.has(reason):
		return str(table[reason])
	return str(_c().get("reason_fallback", "%s")) % reason


## The toast for a relish_returned event {fort_id, cause: "retaken"}: Vei retook the fort Relish stood
## at and she walks home. "" for any other event or a fort the map does not know (`names`: node id
## -> display name).
static func returned_toast(ev: Dictionary, names: Dictionary) -> String:
	if str(ev.get("type", "")) != "relish_returned" or not names.has(str(ev.get("fort_id", ""))):
		return ""
	return str(_c()["returned_fmt"]) % HudLogic.node_name(str(ev["fort_id"]), names)


# --- the chip --------------------------------------------------------------------

## Whether Relish stands at node `id` (in its dungeon or the boss fight counts).
static func is_here(relish: Dictionary, id: String) -> bool:
	if str(relish.get("at", "")) != id:
		return false
	return str(relish.get("state", "")) in ["home", "at_fort", "at_vei", "in_dungeon", "in_boss"]


## Whether she is walking to `id` now.
static func is_heading(relish: Dictionary, id: String) -> bool:
	return str(relish.get("state", "")) == "travelling" and str(relish.get("target", "")) == id


## "Relish · travelling → Ashgate · 0:04" and its siblings, one per state.
static func chip_text(relish: Dictionary, names: Dictionary) -> String:
	var at := HudLogic.node_name(str(relish.get("at", "covington")), names)
	var head := "Relish %s " % DOT
	match str(relish.get("state", "home")):
		"home":
			return head + "home (%s)" % HudLogic.node_name("covington", names)
		"at_fort":
			return head + "at %s" % at
		"travelling":
			return head + "travelling %s %s %s %s" % [ARROW, HudLogic.node_name(str(relish.get("target", "")), names),
				DOT, fmt_eta(float(relish.get("eta_s", 0.0)))]
		"in_dungeon":
			return head + "in %s's dungeon" % at
		"at_vei":
			return head + "at Vei's gates"
		"in_boss":
			return head + "facing Vei"
		"dead":
			return head + "dead %s %s" % [DOT, fmt_eta(float(relish.get("dead_s_left", 0.0)))]
	return head + str(relish.get("state", ""))


## Which chip buttons show: GO HOME unless she is home or already walking home; CANCEL only
## while she travels.
static func chip_buttons(relish: Dictionary) -> Dictionary:
	var state := str(relish.get("state", "home"))
	var home := state == "home" or is_heading(relish, "covington")
	return {"go_home": not home, "cancel": state == "travelling"}


## Whether the chip's buttons sit on the name's row (true) or wrap to a row below (false): the
## row (plate padding both sides, the name, each shown button, a gap before each) must fit in
## `max_w`. `button_ws` holds only the buttons that show. No buttons: true (one row, the name).
static func chip_inline(name_w: float, button_ws: Array, hsep: float, pad: float, max_w: float) -> bool:
	return chip_row_w(name_w, button_ws, hsep, pad) <= max_w


## The width that row needs.
static func chip_row_w(name_w: float, button_ws: Array, hsep: float, pad: float) -> float:
	var w := 2.0 * pad + name_w
	for bw in button_ws:
		w += hsep + float(bw)
	return w


# --- the card's actions ----------------------------------------------------------

static func _line(text: String, key := "") -> Dictionary:
	var out := {"kind": "line", "text": text, "act": "", "enabled": true}
	if key != "":
		out["key"] = key
	return out


static func _button(text: String, act: String, enabled := true) -> Dictionary:
	return {"kind": "button", "text": text, "act": act, "enabled": enabled}


## "Haul: Old Sluice (auto)" / "(set)". `names` maps ids to names.
static func haul_line(haul: Dictionary, names: Dictionary) -> String:
	var target := str(haul.get("target", "auto"))
	var auto := target == "auto"
	var id := str(haul.get("current", "")) if auto else target
	var who := HudLogic.node_name(id, names) if id != "" else "none yet"
	return "Haul: %s (%s)" % [who, "auto" if auto else "set"]


## Where she is, and the MOVE / CANCEL for node `id`: "Relish is here", "on her way · 0:04" with
## CANCEL, or MOVE.
static func move_items(relish: Dictionary, id: String, here_text: String) -> Array:
	if is_here(relish, id):
		return [_line(here_text)]
	if is_heading(relish, id):
		return [_line("on her way %s %s" % [DOT, fmt_eta(float(relish.get("eta_s", 0.0)))]), _button("CANCEL", "cancel")]
	return [_button("MOVE", "move")]


## The fort card's actions, in order: MOVE / CANCEL / "Relish is here", DESCEND (disabled with
## its reason in words), the haul line and its button. Items: {kind: "line"|"button", text, act, enabled}.
## `act` is "move", "cancel", "descend", "haul" or "haul_auto".
## `comes` is {ci: CardLogic.comes_in(), warn: CardLogic.comes_in_warning()}: the line above DESCEND
## is the warning (with its key) when there is one, else none (the card's plain line has the count).
static func fort_actions(fort: Dictionary, relish: Dictionary, haul: Dictionary, names: Dictionary, comes: Dictionary) -> Array:
	var id := str(fort.get("id", ""))
	var out := move_items(relish, id, "Relish is here")
	var can := bool(fort.get("can_descend", false))
	var warn: Dictionary = comes.get("warn", {})
	if not warn.is_empty():
		out.append(_line(str(warn["text"]), str(warn["key"])))
	out.append(_button("DESCEND", "descend", can))
	if not can and str(fort.get("reason", "")) != "":
		out.append(_line(reason_text(str(fort["reason"]))))
	out.append(_line(haul_line(haul, names)))
	if str(haul.get("target", "auto")) == id:
		out.append(_button("BACK TO AUTO", "haul_auto"))
	else:
		out.append(_button("HAUL FROM HERE", "haul"))
	return out


## The Vei card's actions: MOVE / CANCEL / "Relish is at Vei's gates", then BEGIN (disabled with
## its reason in words; pressing it still confirms).
static func vei_actions(vei: Dictionary, relish: Dictionary) -> Array:
	var out := move_items(relish, "vei", "Relish is at Vei's gates")
	if bool(vei.get("won", false)):
		# TODO(api-request #21): economy's _boss_reason will refuse with "won"; reason_text then gives the same words.
		out.append(_line(reason_text("won")))
		return out
	var can := bool(vei.get("can_begin", false))
	var short := CardLogic.fronts_short_text(vei)
	if short != "":
		out.append(_line(short, "danger"))
	out.append(_button("BEGIN THE FINAL TEST", "begin", can))
	if not can and str(vei.get("reason", "")) != "":
		out.append(_line(reason_text(str(vei["reason"]))))
	return out


## A structure key for an action list: buttons rebuild only when this changes; texts update in place.
static func actions_sig(items: Array) -> String:
	return "|".join(items.map(func(i): return "%s:%s:%s" % [i["kind"], i["act"], i["enabled"]]))


# --- routes ----------------------------------------------------------------------

## What to draw for Relish's routes: {travel, preview}.
## travel: she is walking, so the remaining route to `target` shows (solid, with her ETA).
## preview: the card of a node she could go to is open and she is neither there nor heading
## there, so her would-be route shows (dashed, with the ETA). `selected_is_dest` is true for a fort
## or Vei (never for a village or nothing).
static func route_state(relish: Dictionary, selected_id: String, selected_is_dest: bool) -> Dictionary:
	var state := str(relish.get("state", "home"))
	var travel := state == "travelling" and str(relish.get("target", "")) != ""
	var movable := state in ["home", "at_fort", "at_vei", "travelling"]
	var preview := movable and selected_is_dest and selected_id != "" \
			and not is_here(relish, selected_id) and not is_heading(relish, selected_id)
	return {"travel": travel, "preview": preview}


## Dash segments of the line a -> b: [[p0, p1], ...], `dash` long with `gap` between, the last
## one clipped to b. Static: no phase, so it needs no motion.
static func dash_segments(a: Vector2, b: Vector2, dash: float, gap: float) -> Array:
	var out: Array = []
	var total := a.distance_to(b)
	if total <= 0.0 or dash <= 0.0:
		return out
	var dir := (b - a) / total
	var d := 0.0
	while d < total:
		out.append([a + dir * d, a + dir * minf(d + dash, total)])
		d += dash + maxf(gap, 0.0)
	return out


## The dash segments of a -> b as a flat point list for draw_multiline (p0, p1 of each dash in turn).
static func dash_points(a: Vector2, b: Vector2, dash: float, gap: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for seg in dash_segments(a, b, dash, gap):
		out.append(seg[0])
		out.append(seg[1])
	return out


## Whether the preview needs a redraw: she moved at least `min_px` screen px since the last draw.
static func moved_enough(last: Vector2, now: Vector2, zoom: float, min_px: float) -> bool:
	return last.distance_to(now) * zoom >= min_px
