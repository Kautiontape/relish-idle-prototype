class_name TownReplay
extends RefCounted
## The welcome-back replay (town-i M2 Q-f; review-town-b's T-c item 2): once per away report in a session, the town
## replays the builds that finished while you were away, one flash each in the report's order, under a short
## "While you were away" strip of the report's build and ready lines. A ready line that names a place acts: the slab
## opens the Crypt tab, the queue (and an overflow) the Build tab, and a raid line, a fort's or the full stores'
## prompt that names none (target ""), goes back to the realm as the relic pin's To the realm does.
## Pure. `rep` is view_away(); `town` view_town(); `bv` buildings_view.json; `report` economy.json idle.report (the
## templates the report's lines were made from, so its building names can be read back); `cfg` town.json view.replay.


## The report's identity: the game (view_hud().game_id, so a new game starts the session's memory afresh; the M2
## review's should-fix 5), its time and its lines (its rev moves every substep). A load brings its own report, a new
## key, or none. 0 when there is no report.
static func key(rep: Dictionary, game_id := "") -> int:
	if (rep.get("gains", []) as Array).is_empty() and (rep.get("ready", []) as Array).is_empty() \
			and (rep.get("losses", []) as Array).is_empty():
		return 0
	return [game_id, rep.get("away_s", 0.0), rep.get("capped", false), rep.get("gains", []), rep.get("ready", []),
		rep.get("losses", [])].hash()


## Whether `rep` is due its replay: there is one, it has a line for the town, and this session hasn't replayed it
## (`replayed`, the last key replayed). Shown or dismissed alike: acting on a line of the map's panel dismisses the
## report, and its "raise at the slab" and queue lines are exactly how a player comes here.
static func due(rep: Dictionary, replayed: int, game_id := "") -> bool:
	var k := key(rep, game_id)
	return k != 0 and k != replayed and not lines(rep, {}).is_empty()


## The strip's lines: the report's build lines (gains, kind "build"), then its ready lines, at most cfg.max_lines,
## each {text, act}: "crypt", "build", "realm" or "" (a line with nothing to do here).
static func lines(rep: Dictionary, cfg: Dictionary) -> Array:
	var out: Array = []
	for l in rep.get("gains", []):
		if String(l.get("kind", "")) == "build":
			out.append({"text": String(l.get("text", "")), "act": ""})
	for l in rep.get("ready", []):
		out.append({"text": String(l.get("text", "")), "act": act_of(l)})
	var most := int(cfg.get("max_lines", 0))
	return out.slice(0, most) if most > 0 else out


## What a click on a report line does in town: the slab's Crypt tab, the Build tab (the queue's lines and an
## overflow's), back to the realm (a raid line: a fort's, or the full stores' prompt with no fort), or nothing.
static func act_of(line: Dictionary) -> String:
	var target := String(line.get("target", ""))
	if String(line.get("kind", "")) == "raid":
		return "realm"
	if target == "slab":
		return "crypt"
	if target == "queue":
		return "build"
	return ""


## The strip's title: "While you were away (8 h 12 m)".
static func title(rep: Dictionary, cfg: Dictionary) -> String:
	return String(cfg.get("title", "")).format({"time": duration(float(rep.get("away_s", 0.0)), cfg)})


## "8 h 12 m"; "12 m" under an hour; cfg.under_minute under a minute.
static func duration(away_s: float, cfg: Dictionary) -> String:
	var s := maxf(away_s, 0.0)
	if s < 60.0:
		return String(cfg.get("under_minute", ""))
	var h := int(s / 3600.0)
	var m := int(fmod(s, 3600.0) / 60.0)
	return String(cfg.get("hm", "{h} h {m} m")).format({"h": h, "m": m}) if h > 0 else String(cfg.get("m", "{m} m")).format({"m": m})


## The names in the report's "builds finished" line, in its order ([] when no build finished): read back through
## the same templates the line was made from (idle.report builds_fmt / builds_one_fmt and list_sep).
static func finished_names(rep: Dictionary, report: Dictionary) -> Array:
	var sep := String(report.get("list_sep", " · "))
	for l in rep.get("gains", []):
		if String(l.get("kind", "")) != "build":
			continue
		for f in ["builds_fmt", "builds_one_fmt"]:
			var m := _template(String(report.get(f, ""))).search(String(l.get("text", "")))
			if m != null:
				return Array(m.get_string(1).split(sep, false))
	return []


## A building's name as the report writes it: its town label, with level_fmt past level 1.
static func name_of(bid: String, level: int, bv: Dictionary, report: Dictionary) -> String:
	var name := String(bv.get(bid, {}).get("label", bid.capitalize()))
	return String(report.get("level_fmt", "{name} level {level}")).format({"name": name, "level": level}) if level > 1 else name


## The lots to flash, one per finished build in the report's order. A name matches a lot whose building has reached
## that level (view_town's level is the level done, 0 during a first build). Among several, a lot not yet flashed
## first, then one whose level is exactly the named one (the newest work), then the view's lot order. Two upgrades
## of one lot flash it twice, in order.
static func finished_lots(rep: Dictionary, town: Dictionary, bv: Dictionary, report: Dictionary) -> Array:
	# TODO(api-request #19): the build line's own `lots`, in its names' order, when the report carries them
	for l in rep.get("gains", []):
		if String(l.get("kind", "")) == "build" and l.get("lots") is Array and not (l["lots"] as Array).is_empty():
			return (l["lots"] as Array).duplicate()
	var out: Array = []
	var used := {}
	for nm in finished_names(rep, report):
		var best := ""
		var best_score := 99
		for b in town.get("buildings", []):
			var lot := String(b.get("lot_id", ""))
			var bid := String(b.get("building_id", ""))
			var lv := int(b.get("level", 0))
			for k in range(lv, 0, -1):
				if name_of(bid, k, bv, report) != String(nm):
					continue
				var score := (2 if used.has(lot) else 0) + (0 if k == lv else 1)
				if score < best_score:
					best = lot
					best_score = score
				break
		if best != "":
			out.append(best)
			used[best] = true
	return out


## A RegEx for a one-line template: its text literal, {n} a count (with thousands commas), {names} the captured rest.
static func _template(fmt: String) -> RegEx:
	var s := ""
	for ch in fmt:
		s += ("\\" + ch) if "\\^$.|?*+()[]{}".contains(ch) else ch
	s = s.replace("\\{n\\}", "[0-9][0-9,]*").replace("\\{names\\}", "(.+)")
	var re := RegEx.new()
	re.compile("^" + s + "$")
	return re
