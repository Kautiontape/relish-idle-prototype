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


## The first goal in town: the first `guide.goal.steps` entry whose `until` isn't met in `views`, as
## {id, text} (text with the lead), or {} once every step is met. `views` needs `town.buildings` and
## `forts` ([{flipped_count, first_dungeon, name}], the shell's realm digest).
static func goal(views: Dictionary, gcfg: Dictionary) -> Dictionary:
	var g: Dictionary = gcfg.get("goal", {})
	var tiers: Array = g.get("tiers", [])  # a first goal is for a new game: the early tiers only
	if not tiers.is_empty() and not String((views.get("town", {}) as Dictionary).get("tier", "")) in tiers:
		return {}
	for step in g.get("steps", []):
		if _met(step, views):
			continue
		var text := BuildSort.fmt(String(step.get("text", "")), {"fort": first_fort(views, g)})
		return {"id": String(step.get("id", "")), "text": String(g.get("lead", "")) + text}
	return {}


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
