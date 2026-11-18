class_name AwayLogic
extends RefCounted
## Pure logic for the "While you were away" panel (IDLE section 7; no autoloads): which report to
## show (the real view_away, else the debug stand-in), its text in IDLE's order (gains, ready now,
## losses), the font each part of a line is set in, and what clicking a ready line does.
## Tuning and the demo report: configs/map_view.json "idle".away and "demo_away".

const HOUR_S := 3600.0
const MIN_S := 60.0

static var _rate_re: RegEx
static var _mass_re: RegEx


static func cfg() -> Dictionary:
	return MapLogic.cfg().get("idle", {}).get("away", {})


## The report to show: `demo` (the --away=demo debug report) when given, else the state's
## view_away(); with no state, nothing ({shown: false}).
static func report(state, demo := {}) -> Dictionary:
	if not demo.is_empty():
		return demo
	if state != null:
		return state.view_away()
	return {"shown": false}


## Whether the panel opens for this report. With the real view_away, `shown` is the only
## authority (its rev moves every substep); for the demo report (or no state) the closed rev is
## compared too.
static func should_open(state, demo: bool, rep: Dictionary, closed_rev: int) -> bool:
	if not bool(rep.get("shown", false)):
		return false
	if demo or state == null:
		return int(rep.get("rev", 0)) != closed_rev
	return true


## Dismisses through cmd_dismiss_away (a ready line acts as DISMISS does).
static func dismiss(state) -> void:
	if state != null:
		state.cmd_dismiss_away()


## "9 h 12 m"; "12 m" under an hour; the configured words under a minute.
static func duration_text(away_s: float) -> String:
	var s := maxf(away_s, 0.0)
	if s < MIN_S:
		return str(cfg().get("under_minute", ""))
	var h := int(s / HOUR_S)
	var m := int(fmod(s, HOUR_S) / MIN_S)
	return "%d h %d m" % [h, m] if h > 0 else "%d m" % m


## What a click on a line with this `target` does: {kind: "fort", id}, {kind: "dive", to}
## (the slab and the queue live in Covington), {kind: "vei"} (select her) or {kind: "none"}.
## The away panel's lines and the objective strip both resolve their clicks here.
static func action(target: String, fort_ids: Array) -> Dictionary:
	if fort_ids.has(target):
		return {"kind": "fort", "id": target}
	if target == "slab" or target == "queue":
		return {"kind": "dive", "to": "covington"}
	if target == "vei":
		return {"kind": "vei"}
	return {"kind": "none"}


## The losses' count, first in their section: "2 forts lost · 1 village lost" (forts from
## `retaken` lines, villages from `village_lost`), or "" when neither was lost.
static func losses_count(losses: Array) -> String:
	var c := cfg()
	var forts := 0
	var villages := 0
	for row in losses:
		match str(row.get("kind", "")):
			"retaken":
				forts += 1
			"village_lost":
				villages += 1
	var parts: Array = []
	if forts > 0:
		parts.append(str(c["fort_lost_fmt" if forts == 1 else "forts_lost_fmt"]) % forts)
	if villages > 0:
		parts.append(str(c["village_lost_fmt" if villages == 1 else "villages_lost_fmt"]) % villages)
	return str(c["count_sep"]).join(parts)


## The report as panel text: {away: "Away 9 h 12 m", capped: "capped at 7 days" or "", sections:
## [{key, title, lines: [{text, spans, action}]}]}. Sections run gains, ready, losses; gains and
## ready are left out when empty, losses always show ("Nothing lost." when there are none) and lead
## with their count ("2 forts lost"). Ready and loss lines carry their target's action (a lost
## fort is clickable like a ready one); gains lines and the count do nothing.
static func build(rep: Dictionary, fort_ids: Array) -> Dictionary:
	var c := cfg()
	var out := {
		"away": str(c.get("away_fmt", "%s")) % duration_text(float(rep.get("away_s", 0.0))),
		"capped": str(c.get("capped_text", "")) if bool(rep.get("capped", false)) else "",
		"sections": [],
	}
	for key in ["gains", "ready", "losses"]:
		var lines: Array = []
		var count := losses_count(rep.get(key, [])) if key == "losses" else ""
		if count != "":
			lines.append({"text": count, "spans": spans(count), "action": {"kind": "none"}})
		for row in rep.get(key, []):
			var text := str(row.get("text", ""))
			lines.append({"text": text, "spans": spans(text), "action": action(str(row.get("target", "")), fort_ids) if key != "gains" else {"kind": "none"}})
		if key == "losses" and lines.is_empty():
			var none := str(c.get("nothing_lost", ""))
			lines.append({"text": none, "spans": spans(none), "action": {"kind": "none"}})
		if not lines.is_empty():
			out["sections"].append({"key": key, "title": str(c.get(key + "_title", "")), "lines": lines})
	return out


## A line split into runs by font: "rate" (a signed number with /s: oblique, light), "mass" (a
## number: upright, heavy) or "label" (words). [{text, kind}], neighbours of one kind merged.
static func spans(text: String) -> Array:
	_compile()
	var out: Array = []
	for tok in text.split(" ", false):
		var kind := "label"
		if _rate_re.search(tok) != null:
			kind = "rate"
		elif _mass_re.search(tok) != null:
			kind = "mass"
		if not out.is_empty() and out[-1]["kind"] == kind:
			out[-1]["text"] += " " + tok
		else:
			out.append({"text": tok, "kind": kind})
	return out


static func _compile() -> void:
	if _rate_re != null:
		return
	_rate_re = RegEx.new()
	_rate_re.compile("^[+\\-−]?\\d[\\d,\\.]*/s$")
	_mass_re = RegEx.new()
	_mass_re.compile("^[+\\-−]?\\d[\\d,\\.]*$")
