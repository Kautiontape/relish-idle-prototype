class_name TownGuide
extends RefCounted
## The town's new-player lines (Phase I clarity, Shawn's checklist items 10-11): why each building is
## worth building and how it's used, the first goal in town, and the lines that say what pays for what.
## Pure (add_lines aside, which only makes the two labels): every text is configs/town.json `view.guide`;
## the state is the views the Covington shell fetches.
## The goal keys off existing state only (what's placed, whether any fort was ever taken): no "seen" flag.


## One line: what building `bid` does for you → the part of the loop it feeds ("" for an unknown id).
static func why(bid: String, gcfg: Dictionary) -> String:
	return String((gcfg.get("why", {}) as Dictionary).get(bid, ""))


## One line: how the player uses `bid`. The buildings used by hand (guide.how.act) say how and where;
## every other building works on its own, staffed by the undead when buildings.json gives it jobs.
static func how(bid: String, bcfg: Dictionary, gcfg: Dictionary) -> String:
	var h: Dictionary = gcfg.get("how", {})
	var act: Dictionary = h.get("act", {})
	if act.has(bid):
		return String(act[bid])
	var jobs: Dictionary = (bcfg.get(bid, {}) as Dictionary).get("jobs", {})
	return String(h.get("staffed" if not jobs.is_empty() else "passive", ""))


## Whether `bid` is used by hand (guide.how.act): its how-line is an instruction, lit in `select`.
static func by_hand(bid: String, gcfg: Dictionary) -> bool:
	return ((gcfg.get("how", {}) as Dictionary).get("act", {}) as Dictionary).has(bid)


## The palette key a how-line draws in: `select` for a building used by hand, `text_dim` otherwise.
static func how_key(bid: String, gcfg: Dictionary) -> String:
	return "select" if by_hand(bid, gcfg) else "text_dim"


## Adds `bid`'s why-line (`text`) and how-line (how_key) to `box` as two wrapping 14 px labels, skipping an
## empty one. Their text is fixed per building, so a catalog row sets them once, when it is made.
static func add_lines(box: Container, bid: String, bcfg: Dictionary, gcfg: Dictionary) -> void:
	for pair in [[why(bid, gcfg), "text"], [how(bid, bcfg, gcfg), how_key(bid, gcfg)]]:
		if String(pair[0]) == "":
			continue
		var l := TownUI.label(String(pair[0]), 14, String(pair[1]))
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.custom_minimum_size = Vector2(40, 0)
		box.add_child(l)


## The goal plate at every tier (V-I1 top change 3, clarity-review-3 #4): the game's goal (goal.head) over the step due
## now (step). {id, head, text, short, relics}. `views` needs `town` (buildings, tier, next_tier), `inventory` and
## `forts` ([{held, flipped_count, first_dungeon, name}], the shell's realm digest); `hcfg`/`bview` word the tier.
static func goal(views: Dictionary, gcfg: Dictionary, hcfg: Dictionary, bview: Dictionary) -> Dictionary:
	var out := step(views, gcfg, hcfg, bview)
	out["head"] = String((gcfg.get("goal", {}) as Dictionary).get("head", ""))
	return out


## The step due now: the one the goal plate shows (`text`, its lead + the step) and the top bar's next: line shows
## (`short`), from one source so the two can't disagree (V-I1). In order:
## - the first steps (goal.steps, at goal.tiers only), while one's `until` isn't met: the Bone Mill, then the first fort;
## - the next tier, from HudModel.next_line (the top bar's own line): its relic wall when relics hold the tier back
##   (`relics` true), else its building count and missing gate buildings;
## - at the top tier, the realm: Vei's forts while any isn't held (still hers: Vei's, overrun or retaken), else Vei.
static func step(views: Dictionary, gcfg: Dictionary, hcfg: Dictionary, bview: Dictionary) -> Dictionary:
	var g: Dictionary = gcfg.get("goal", {})
	var lead := String(g.get("lead", ""))
	var tiers: Array = g.get("tiers", [])  # the first steps are for a new game: the early tiers only
	if tiers.is_empty() or String((views.get("town", {}) as Dictionary).get("tier", "")) in tiers:
		for st in g.get("steps", []):
			if _met(st, views):
				continue
			var vars := {"fort": first_fort(views, g)}
			return {"id": String(st.get("id", "")), "text": String(st.get("lead", lead)) + BuildSort.fmt(String(st.get("text", "")), vars),
				"short": BuildSort.fmt(String(st.get("short", "")), vars), "relics": false}
	var nl := HudModel.next_line(views, hcfg, bview)
	if String(nl["tier"]) != "":
		if bool(nl["relics"]):
			return {"id": "relics", "text": lead + BuildSort.fmt(String(g.get("relics", "")), {"tier": nl["tier"], "n": nl["need"],
				"unit": nl["unit"], "have": nl["have"]}), "short": String(nl["text"]), "relics": true}
		var missing := ""
		if not (nl["missing"] as Array).is_empty():
			missing = BuildSort.fmt(String(g.get("tier_missing", "")), {"list": ", ".join(nl["missing"])})
		return {"id": "tier", "text": lead + BuildSort.fmt(String(g.get("tier", "")), {"tier": nl["tier"], "need": nl["b_need"],
			"have": nl["b_have"], "missing": missing}), "short": String(nl["text"]), "relics": false}
	var left := forts_left(views)
	var id := "forts" if left > 0 else "vei"
	return {"id": id, "text": lead + BuildSort.fmt(String(g.get(id, "")), {"n": left}),
		"short": BuildSort.fmt(String(g.get(id + "_short", "")), {"n": left}), "relics": false}


## How many forts are still Vei's: every fort not held now (Vei's, overrun or retaken; glossary "The map's fort states").
static func forts_left(views: Dictionary) -> int:
	var n := 0
	for f in views.get("forts", []):
		if not bool(f.get("held", false)):
			n += 1
	return n


static func _met(step: Dictionary, views: Dictionary) -> bool:
	match String(step.get("until", "")):
		"built":
			return placed(views, String(step.get("building", "")))
		"fort_taken":
			return fort_taken(views)
	return true  # an unknown condition never holds a goal on screen


## Whether a building of id `bid` stands on a lot (under construction included).
static func placed(views: Dictionary, bid: String) -> bool:
	for b in (views.get("town", {}) as Dictionary).get("buildings", []):
		if String(b.get("building_id", "")) == bid:
			return true
	return false


## Whether any fort was ever taken: held now, or flipped once (flipped_count > 0) and retaken since. A save
## older than flipped_count reads 0 there, so held counts on its own.
static func fort_taken(views: Dictionary) -> bool:
	for f in views.get("forts", []):
		if bool(f.get("held", false)) or int(f.get("flipped_count", 0)) > 0:
			return true
	return false


## The first dungeon's name (the fort a new game marks "your first dungeon"), else goal.fort_any.
static func first_fort(views: Dictionary, g: Dictionary) -> String:
	for f in views.get("forts", []):
		if bool(f.get("first_dungeon", false)):
			return String(f.get("name", ""))
	return String(g.get("fort_any", ""))
