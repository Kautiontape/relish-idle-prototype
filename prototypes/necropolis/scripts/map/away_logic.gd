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


## The report to show. `demo` (the --away=demo report) wins when given; else view_away when the
## state has it; else nothing ({shown: false}).
# TODO(api-request #7): view_away()
static func report(state, demo := {}) -> Dictionary:
	if not demo.is_empty():
		return demo
	if state != null and state.has_method("view_away"):
		return state.view_away()
	return {"shown": false}


## "9 h 12 m"; "12 m" under an hour; the configured words under a minute.
static func duration_text(away_s: float) -> String:
	var s := maxf(away_s, 0.0)
	if s < MIN_S:
		return str(cfg().get("under_minute", ""))
	var h := int(s / HOUR_S)
	var m := int(fmod(s, HOUR_S) / MIN_S)
	return "%d h %d m" % [h, m] if h > 0 else "%d m" % m


## What a click on a line with this `target` does: {kind: "fort", id}, {kind: "dive", to}
## (the slab and the queue live in Covington) or {kind: "none"}.
static func action(target: String, fort_ids: Array) -> Dictionary:
	if fort_ids.has(target):
		return {"kind": "fort", "id": target}
	if target == "slab" or target == "queue":
		return {"kind": "dive", "to": "covington"}
	return {"kind": "none"}


## The report as panel text: {away: "Away 9 h 12 m", capped: "capped at 7 days" or "", sections:
## [{key, title, lines: [{text, spans, action}]}]}. Sections run gains, ready, losses; gains and
## ready are left out when empty, losses always show ("Nothing lost." when there are none).
static func build(rep: Dictionary, fort_ids: Array) -> Dictionary:
	var c := cfg()
	var out := {
		"away": str(c.get("away_fmt", "%s")) % duration_text(float(rep.get("away_s", 0.0))),
		"capped": str(c.get("capped_text", "")) if bool(rep.get("capped", false)) else "",
		"sections": [],
	}
	for key in ["gains", "ready", "losses"]:
		var lines: Array = []
		for row in rep.get(key, []):
			var text := str(row.get("text", ""))
			lines.append({"text": text, "spans": spans(text), "action": action(str(row.get("target", "")), fort_ids) if key == "ready" else {"kind": "none"}})
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
