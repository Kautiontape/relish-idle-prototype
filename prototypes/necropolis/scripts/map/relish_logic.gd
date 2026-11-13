class_name RelishLogic
extends RefCounted
## Pure logic for steering Relish from the map (no autoloads, so headless tests compile it): the
## chip's text and buttons, the m:ss ETA, the plain-words refusal reasons, the card's action list
## (MOVE / CANCEL / DESCEND / HAUL, built from the views), the route preview versus the travel
## route, and the "Relish here / Relish left" lane-why stand-in. Words live in
## configs/map_view.json ("controls").

const DOT := "·"
const ARROW := "→"


static func _c() -> Dictionary:
	return MapLogic.cfg().get("controls", {})


## "m:ss" from seconds (rounded; negative reads 0:00).
static func fmt_eta(s: float) -> String:
	var n := maxi(roundi(s), 0)
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


# --- the card's actions ----------------------------------------------------------

static func _line(text: String) -> Dictionary:
	return {"kind": "line", "text": text, "act": "", "enabled": true}


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
static func fort_actions(fort: Dictionary, relish: Dictionary, haul: Dictionary, names: Dictionary) -> Array:
	var id := str(fort.get("id", ""))
	var out := move_items(relish, id, "Relish is here")
	var can := bool(fort.get("can_descend", false))
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
	var can := bool(vei.get("can_begin", false))
	out.append(_button("BEGIN THE FINAL CONFRONTATION", "begin", can))
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


# --- "Relish here / Relish left" (stand-in) --------------------------------------

## The lane-why events one refresh makes: Relish left fort A (she started walking, or jumped to
## another fort) -> "Relish left" on war:covington:A; she arrived at fort B -> "Relish here" on
## war:covington:B. Each is {id, why, until_s}. Empty `prev` (the first read) makes none.
# TODO(api E2): view_lanes carries why
static func why_events(prev: Dictionary, cur: Dictionary, now_s: float, hold_s: float) -> Array:
	var out: Array = []
	if prev.is_empty() or cur.is_empty():
		return out
	var ps := str(prev.get("state", ""))
	var cs := str(cur.get("state", ""))
	var moved_fort := cs == "at_fort" and str(cur.get("at", "")) != str(prev.get("at", ""))
	if ps == "at_fort" and (cs == "travelling" or moved_fort):
		out.append({"id": "war:covington:%s" % str(prev.get("at", "")), "why": "Relish left", "until_s": now_s + hold_s})
	if cs == "at_fort" and (ps == "travelling" or (ps == "at_fort" and moved_fort)):
		out.append({"id": "war:covington:%s" % str(cur.get("at", "")), "why": "Relish here", "until_s": now_s + hold_s})
	return out


## The live holds after a refresh: expired ones dropped, a new event replacing any hold on the same lane.
static func why_track(prev: Dictionary, cur: Dictionary, holds: Array, now_s: float, hold_s: float) -> Array:
	var out: Array = []
	var fresh := why_events(prev, cur, now_s, hold_s)
	for h in holds:
		if float(h["until_s"]) > now_s and not fresh.any(func(e): return e["id"] == h["id"]):
			out.append(h)
	out.append_array(fresh)
	return out


## `rows` with each live hold's why filled in, only where the view's own why is empty. Returns
## copies of the touched rows (the input is not changed).
static func why_apply(rows: Array, holds: Array, now_s: float) -> Array:
	var out: Array = []
	for r in rows:
		var row: Dictionary = r
		if str(row.get("why", "")) == "":
			for h in holds:
				if h["id"] == row.get("id", "") and float(h["until_s"]) > now_s:
					row = row.duplicate()
					row["why"] = h["why"]
					break
		out.append(row)
	return out
