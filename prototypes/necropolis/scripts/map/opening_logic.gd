class_name OpeningLogic
extends RefCounted
## Pure logic for the opening (GAMEPLAY 6, the first 30 seconds; no autoloads, so headless tests
## compile it): whether the game is still young, which ask the objective strip holds (drag the
## valve, send Relish to the first dungeon, descend into it), the valve pointer's dashes, the pulse
## levels, and the first-tithe explanation's text. Tuning and words: configs/map_view.json "opening".

const VALVE := "valve"
const SEND := "send"
const DESCEND := "descend"
const NONE := ""


static func cfg() -> Dictionary:
	return MapLogic.cfg().get("opening", {})


## The opening runs while the game is young (hud.t under opening_s) and no fort has flipped yet.
static func active(t: float, forts: Array) -> bool:
	if t >= float(cfg()["opening_s"]):
		return false
	for f in forts:
		if int(f.get("flipped_count", 0)) > 0:
			return false
	return true


## The fort that carries the first-dungeon guarantee, or {} once a raid result has cleared it.
static func first_dungeon(forts: Array) -> Dictionary:
	for f in forts:
		if bool(f.get("first_dungeon", false)):
			return f
	return {}


## The ask now up: VALVE until the valve is first committed (`valve_seen`), SEND until Relish is
## travelling to the first dungeon or standing at it, DESCEND until it is cleared, then NONE.
## Every ask also ends when the opening does (`active`).
static func stage(t: float, forts: Array, relish: Dictionary, valve_seen: bool) -> String:
	if not active(t, forts):
		return NONE
	if not valve_seen:
		return VALVE
	var fd := first_dungeon(forts)
	if fd.is_empty():
		return NONE
	var id := str(fd["id"])
	var state := str(relish.get("state", ""))
	if state == "travelling" and str(relish.get("target", "")) == id:
		return DESCEND
	if str(relish.get("at", "")) == id and state in ["at_fort", "in_dungeon"]:
		return DESCEND
	return SEND


## {text, target} for the strip: the fort's id as the target for SEND and DESCEND (a click selects
## it), "" for the valve (nothing to click: the pointer does the leading).
static func ask(stage_id: String, forts: Array) -> Dictionary:
	var c := cfg()
	var fd := first_dungeon(forts)
	var nm := str(fd.get("name", fd.get("id", "")))
	match stage_id:
		VALVE:
			return {"text": str(c["valve_text"]), "target": ""}
		SEND:
			return {"text": str(c["send_fmt"]) % nm, "target": str(fd.get("id", ""))}
		DESCEND:
			return {"text": str(c["descend_fmt"]) % nm, "target": str(fd.get("id", ""))}
	return {"text": "", "target": ""}


## The valve pointer (line, triangle edge, hint) shows during the VALVE ask, and not while the
## handle is held.
static func pointer_shown(stage_id: String, dragging: bool) -> bool:
	return stage_id == VALVE and not dragging


## A pulse's level: the beat's wave, or a fixed full level under reduced motion (static, bright).
static func level(wave: float, reduced: bool) -> float:
	return 1.0 if reduced else clampf(wave, 0.0, 1.0)


## The pointer's dashes from `a` to `b` as segment endpoint pairs (draw_multiline's points):
## dashes of `dash` px, `gap` apart, walking `offset` px along the line toward `b` (the first
## dash may start before `a` and is clipped to it).
static func dashes(a: Vector2, b: Vector2, dash: float, gap: float, offset: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var len := a.distance_to(b)
	var period := dash + gap
	if len <= 0.0 or period <= 0.0 or dash <= 0.0:
		return out
	var dir := (b - a) / len
	var s := fposmod(offset, period) - period
	while s < len:
		var s0 := maxf(s, 0.0)
		var s1 := minf(s + dash, len)
		if s1 > s0:
			out.append(a + dir * s0)
			out.append(a + dir * s1)
		s += period
	return out


# --- the 5 s promise --------------------------------------------------------------------

## How much of a rate's final change has landed: (at - base) / (final - base); 1 when it never
## changed.
static func response_fraction(base: float, at: float, final: float) -> float:
	if is_equal_approx(final, base):
		return 1.0
	return (at - base) / (final - base)


# --- the first tithe's explanation ------------------------------------------------------

## "3:52", or the configured word once the wave is here (eta_s <= 0) or no ETA is known (-1).
static func eta_text(eta_s: float) -> String:
	if eta_s <= 0.0:
		return str(cfg()["tithe_now_text"])
	var s := ceili(eta_s)
	return "%d:%02d" % [floori(s / 60.0), s % 60]


## The explanation for the fort `fort_name` whose wave is `eta_s` away (live: the caller passes the
## fort's tithe.eta_s each refresh).
static func tithe_text(fort_name: String, eta_s: float) -> String:
	return str(cfg()["tithe_text_fmt"]) % [fort_name, eta_text(eta_s)]


## The ETA to show for `fort_id`: its view's tithe.eta_s while targeted, else `fallback` (the
## warning event's own eta_s).
static func tithe_eta(forts: Array, fort_id: String, fallback: float) -> float:
	for f in forts:
		if str(f.get("id", "")) == fort_id:
			var t: Dictionary = f.get("tithe", {})
			if bool(t.get("targeted", false)):
				return float(t.get("eta_s", fallback))
	return fallback


## The fort a debug trigger explains: the first fort a warning targets, else `preferred`.
static func debug_tithe_fort(forts: Array, preferred: String) -> String:
	for f in forts:
		if bool(f.get("tithe", {}).get("targeted", false)):
			return str(f["id"])
	return preferred


# --- placing the explanation panel ------------------------------------------------------

## Where a panel of `size` goes for a fort at screen point `anchor`: `gap` above it (below when
## there is no room under `top`), then kept `margin` inside the viewport and below `top`.
static func panel_pos(anchor: Vector2, size: Vector2, viewport: Vector2, top: float, gap: float, margin: float) -> Vector2:
	var y := anchor.y - gap - size.y
	if y < top + margin:
		y = anchor.y + gap
	var x := anchor.x - size.x * 0.5
	return Vector2(clampf(x, margin, maxf(viewport.x - size.x - margin, margin)),
		clampf(y, top + margin, maxf(viewport.y - size.y - margin, top + margin)))
