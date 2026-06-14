class_name BuildState
extends RefCounted
## The thing on the slab: one form + remnants slotted into its rune slots. The
## form contributes no stats (a blank form = a Hollow shambler); every stat and
## echo comes from the remnants you slot. derived() is the single source of
## truth for the morph, the name, and the twin lean bar.

const ASPECT_ORDER := ["muscle", "nerve", "presence", "anima"]

var form_id := ""
var form: Dictionary = {}
var slots: Array = []   # ordered [{aspect, remnant}] — remnant {} when empty

func has_form() -> bool:
	return form_id != ""

func place_form(id: String) -> void:
	form_id = id
	form = ConfigDb.husk(id).duplicate(true)
	slots = []
	var anatomy: Dictionary = form["anatomy"]
	for aspect in ASPECT_ORDER:
		for i in int(anatomy.get(aspect, 0)):
			slots.append({"aspect": aspect, "remnant": {}})

func clear() -> void:
	form_id = ""
	form = {}
	slots = []

func empty_slot_for(aspect: String) -> int:
	for i in slots.size():
		if slots[i]["aspect"] == aspect and (slots[i]["remnant"] as Dictionary).is_empty():
			return i
	return -1

func slot_remnant(index: int, remnant: Dictionary) -> void:
	slots[index]["remnant"] = remnant

func unslot(index: int) -> Dictionary:
	var r: Dictionary = slots[index]["remnant"]
	slots[index]["remnant"] = {}
	return r

func slotted() -> Array:
	var out: Array = []
	for s in slots:
		if not (s["remnant"] as Dictionary).is_empty():
			out.append(s["remnant"])
	return out

func filled_count() -> int:
	return slotted().size()

func totals() -> Dictionary:
	var stats := {}
	for s in Loot.STATS:
		stats[s] = 0.0
	for r in slotted():
		stats[r["stat"]] += float(r["magnitude"])
	return stats

func echo_points() -> Dictionary:
	var ep := {}
	for r in slotted():
		for e in r.get("echoes", []):
			ep[e["id"]] = int(ep.get(e["id"], 0)) + int(e["points"])
	return ep

func combat_town_pts() -> Array:
	var c := 0
	var t := 0
	for r in slotted():
		c += int(r.get("combat_points", 0))
		t += int(r.get("town_points", 0))
	return [c, t]

## Everything the preview / name / lean bar reads, computed once.
func derived() -> Dictionary:
	var stats := totals()
	var echoes := echo_points()
	var ct := combat_town_pts()
	var noun: String = String(form.get("name", "?")) if has_form() else "?"
	var role := CreatureRole.of(stats, echoes)
	return {
		"form_id": form_id,
		"noun": noun,
		"color": String(form.get("color", "#cccccc")) if has_form() else "#cccccc",
		"stats": stats,
		"echoes": echoes,
		"combat_pts": ct[0],
		"town_pts": ct[1],
		"beef": float(stats["beef"]),
		"adjective": CreatureNamer.adjective(stats, echoes),
		"name": CreatureNamer.full_name(noun, stats, echoes),
		"role": role["role"],
		"good_for": role["good_for"],
		"role_line": role["line"],
		"slot_count": slots.size(),
		"filled": filled_count(),
	}
