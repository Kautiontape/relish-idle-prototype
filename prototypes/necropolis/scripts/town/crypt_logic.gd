class_name CryptLogic
extends RefCounted
## The crypt tab's pure helpers on top of SlabLogic (MECHANICS §4.6): the slab board and its
## click-to-slot, the gate text from Relish's state, a big undead's place in words, the name rule,
## the raise gate, the stats → verbs rows, the hold-to-raise clock and the set piece's timing.
## No autoloads, no Engine: `cfg` = configs["town"]["slab"], `texts` = town.json view.crypt.
##
## The board is {husk: uid, kind: String, order: Array[String]}: the slotted remnant uids in the
## order they were clicked. Which rune holds which remnant is never stored: it is always
## SlabLogic.evaluate's assignment of `order`, so the slab shows exactly what the raise computes.

const NAME_MAX := 24


static func board(husk_uid := "", kind := "") -> Dictionary:
	return {"husk": husk_uid, "kind": kind, "order": []}


## uid -> remnant dict, from view_inventory().remnants.
static func by_uid(remnants: Array) -> Dictionary:
	var out := {}
	for r in remnants:
		out[String(r.get("uid", ""))] = r
	return out


## The board's remnants (dicts) in click order; uids the inventory no longer has are skipped.
static func remnants_of(b: Dictionary, rems: Dictionary) -> Array:
	var out: Array = []
	for u in b.get("order", []):
		if rems.has(u):
			out.append(rems[u])
	return out


static func evaluate(b: Dictionary, rems: Dictionary, cfg: Dictionary) -> Dictionary:
	return SlabLogic.evaluate(String(b.get("kind", "")), remnants_of(b, rems), cfg)


## The uid in each slot ("" for an empty one), in slot order: evaluate's assignment of the board.
static func slot_uids(b: Dictionary, rems: Dictionary, cfg: Dictionary) -> Array:
	var order: Array = []
	for u in b.get("order", []):
		if rems.has(u):
			order.append(u)
	var out: Array = []
	for s in evaluate(b, rems, cfg)["slots"]:
		var i := int(s["remnant_index"])
		out.append(order[i] if i >= 0 else "")
	return out


## The raise's `remnant_uids`: the slotted uids in slot order.
static func slot_order(b: Dictionary, rems: Dictionary, cfg: Dictionary) -> Array:
	return slot_uids(b, rems, cfg).filter(func(u): return u != "")


## The slot `uid` would land in if clicked now (SlabLogic's own group first, anima last), or -1
## when it fits no free slot. A trial evaluate, so the rule is SlabLogic's, not the panel's.
static func landing(b: Dictionary, uid: String, rems: Dictionary, cfg: Dictionary) -> int:
	if String(b.get("husk", "")) == "" or not rems.has(uid) or uid in b.get("order", []):
		return -1
	var trial := b.duplicate(true)
	trial["order"].append(uid)
	var placed := remnants_of(trial, rems)
	var ev := SlabLogic.evaluate(String(b.get("kind", "")), placed, cfg)
	var idx := placed.size() - 1
	if idx in ev["unplaced"]:
		return -1
	for j in ev["slots"].size():
		if int(ev["slots"][j]["remnant_index"]) == idx:
			return j
	return -1


## Why a remnant can't be slotted now: "" (it lands), "no_husk", "on_slab" (already slotted),
## "no_slot" (the husk has no slot its aspect fits), "full" (every slot it fits is taken).
static func refusal(b: Dictionary, uid: String, rems: Dictionary, cfg: Dictionary) -> String:
	if String(b.get("husk", "")) == "":
		return "no_husk"
	if uid in b.get("order", []):
		return "on_slab"
	if landing(b, uid, rems, cfg) >= 0:
		return ""
	return "no_slot" if fit_groups(String(b.get("kind", "")), String(rems.get(uid, {}).get("aspect", "")), cfg).is_empty() else "full"


## The husk's groups (GROUPS order, each once) that take `aspect`.
static func fit_groups(kind: String, aspect: String, cfg: Dictionary) -> Array:
	var out: Array = []
	for g in SlabLogic.slots_for(kind, cfg):
		if not (g in out) and SlabLogic.fits(g, aspect, cfg):
			out.append(g)
	return out


## The refusal in words (view.crypt.refuse), "" when the remnant lands.
static func refusal_text(b: Dictionary, uid: String, rems: Dictionary, cfg: Dictionary, texts: Dictionary) -> String:
	var why := refusal(b, uid, rems, cfg)
	if why == "":
		return ""
	var t: Dictionary = texts.get("refuse", {})
	var kind := String(b.get("kind", ""))
	var aspect := String(rems.get(uid, {}).get("aspect", ""))
	return String(t.get(why, why)).format({
		"noun": String(cfg.get("nouns", {}).get(kind, kind.capitalize())), "aspect": aspect,
		"groups": " and ".join(fit_groups(kind, aspect, cfg)),
		"group": _group_of(b, uid, rems, cfg)})


## The group of the slot holding `uid` ("" when it isn't slotted).
static func _group_of(b: Dictionary, uid: String, rems: Dictionary, cfg: Dictionary) -> String:
	var at := slot_uids(b, rems, cfg).find(uid)
	if at < 0:
		return ""
	return String(SlabLogic.slots_for(String(b.get("kind", "")), cfg)[at])


## A remnant click: slots it where it lands, or takes it off if it is already on the slab.
## -> {board, ok, action: "slot" | "unslot" | "", reason (refusal() id), slot}
static func click_remnant(b: Dictionary, uid: String, rems: Dictionary, cfg: Dictionary) -> Dictionary:
	var nb := b.duplicate(true)
	if uid in nb.get("order", []):
		nb["order"].erase(uid)
		return {"board": nb, "ok": true, "action": "unslot", "reason": "", "slot": -1}
	var why := refusal(b, uid, rems, cfg)
	if why != "":
		return {"board": nb, "ok": false, "action": "", "reason": why, "slot": -1}
	nb["order"].append(uid)
	return {"board": nb, "ok": true, "action": "slot", "reason": "", "slot": slot_uids(nb, rems, cfg).find(uid)}


## A rune click: takes its remnant off (the others may settle into the freed slot, the way the
## raise would place them). -> {board, uid} (uid "" for an empty rune).
static func click_slot(b: Dictionary, idx: int, rems: Dictionary, cfg: Dictionary) -> Dictionary:
	var nb := b.duplicate(true)
	var su := slot_uids(b, rems, cfg)
	if idx < 0 or idx >= su.size() or String(su[idx]) == "":
		return {"board": nb, "uid": ""}
	nb["order"].erase(su[idx])
	return {"board": nb, "uid": String(su[idx])}


## The board kept in step with view_inventory(): a husk that is gone empties the slab, and
## remnants that are gone come off it.
static func reconcile(b: Dictionary, inventory: Dictionary) -> Dictionary:
	var husk := String(b.get("husk", ""))
	if husk == "":
		return b
	var kind := ""
	for h in inventory.get("husks", []):
		if String(h.get("uid", "")) == husk:
			kind = String(h.get("kind", ""))
	if kind == "":
		return board()
	var rems := by_uid(inventory.get("remnants", []))
	var nb := board(husk, kind)
	for u in b.get("order", []):
		if rems.has(u):
			nb["order"].append(u)
	return nb


## The name rule (STATE-API bad_name): 1..24 characters after strip_edges.
## -> {ok, name (stripped), reason ("" or "bad_name")}
## {uid: name to show} for big undead entries: SlabLogic.display_name (the slab's name while an entry still
## carries the mint default "Big u7", its own name otherwise). The one place the roster, the Foreman chooser
## and the place words read names from.
static func display_names(entries: Array, slab: Dictionary) -> Dictionary:
	var out := {}
	for e in entries:
		out[String(e.get("uid", ""))] = SlabLogic.display_name(e, slab)
	return out


## The debug raise's name for the creature it grants: the name the slab gave (what the player kept for the husk
## and remnants on it), else the slab's name for the granted `entry` itself.
static func raise_name(slab_name: String, entry: Dictionary, slab: Dictionary) -> String:
	return slab_name if slab_name != "" else SlabLogic.display_name(entry, slab)


## Whether the raise is still a preview (nothing is spent, no big undead rises): town.json slab.raise_wired is
## false (STANDIN(E3): the sim has no view fact that says so before the first raise) and no raise has yet
## returned a creature (`seen_live`, see raise_returned_creature), which switches the note off for good.
static func raise_is_preview(cfg: Dictionary, seen_live: bool) -> bool:
	return not bool(cfg.get("raise_wired", false)) and not seen_live


## A raise result that really made a big undead: ok and a non-empty uid (the stub returns uid "").
static func raise_returned_creature(r: Dictionary) -> bool:
	return bool(r.get("ok", false)) and String(r.get("big_undead", {}).get("uid", "")) != ""


## A timed line's seconds left after `dt` (never below 0).
static func line_left(left: float, dt: float) -> float:
	return maxf(left - dt, 0.0)


## The note a placed big undead's line carries: "coming: a foreman boosts its building in a later build" for a
## foreman place (town:<lot>), "" for any other place.
static func place_note(place: String, texts: Dictionary) -> String:
	return String(texts.get("foreman_coming", "")) if place.begins_with("town:") else ""


static func check_name(name: String) -> Dictionary:
	var nm := name.strip_edges()
	var ok := not nm.is_empty() and nm.length() <= NAME_MAX
	return {"ok": ok, "name": nm, "reason": "" if ok else "bad_name"}


## Why the slab is asleep, in words, from view_relish() ("" never: home has its own line).
## `fort_names` = fort id -> name; texts = view.crypt.
static func gate_text(relish: Dictionary, fort_names: Dictionary, texts: Dictionary) -> String:
	var g: Dictionary = texts.get("gate", {})
	var at := _node_name(String(relish.get("at", "")), fort_names, texts)
	match String(relish.get("state", "")):
		"home":
			return String(g.get("home", ""))
		"travelling":
			var target := String(relish.get("target", ""))
			if target == "covington":
				return String(g.get("travelling_home", ""))
			return String(g.get("travelling", "")).format({"to": _node_name(target, fort_names, texts)})
		"at_fort":
			return String(g.get("at_fort", "")).format({"at": at})
		"at_vei":
			return String(g.get("at_vei", ""))
		"in_dungeon":
			return String(g.get("in_dungeon", "")).format({"at": at})
		"in_boss":
			return String(g.get("in_boss", ""))
		"dead":
			var key := "dead_clone" if bool(relish.get("respawn_with_clone", false)) else "dead_unmade"
			return String(g.get(key, "")).format({"s": ceili(maxf(float(relish.get("dead_s_left", 0.0)), 0.0))})
	return String(g.get("away", ""))


static func _node_name(id: String, fort_names: Dictionary, texts: Dictionary) -> String:
	if id == "vei":
		return String(texts.get("vei_name", "Vei"))
	return String(fort_names.get(id, id.capitalize()))


## A big undead's place in words: "in the crypt", "in the party", "foreman at the Market",
## "sieging Ashgate". `lot_labels` = lot id -> building label.
static func place_text(place: String, lot_labels: Dictionary, fort_names: Dictionary, texts: Dictionary) -> String:
	var p: Dictionary = texts.get("place", {})
	if place == "crypt" or place == "party":
		return String(p.get(place, place))
	if place.begins_with("town:"):
		var lot := place.trim_prefix("town:")
		return String(p.get("town", "")).format({"label": String(lot_labels.get(lot, lot))})
	if place.begins_with("fort:"):
		var id := place.trim_prefix("fort:")
		return String(p.get("fort", "")).format({"name": String(fort_names.get(id, id.capitalize()))})
	return String(p.get("other", "{place}")).format({"place": place})


## Why the hold is disabled, in words ("" when the slab can raise). Checked in the order the
## player can fix them: Relish home, a husk on the slab, the cap, then SlabLogic's verdict.
static func raise_block(b: Dictionary, ev: Dictionary, home: bool, count: int, cap: int, cfg: Dictionary, texts: Dictionary) -> String:
	var t: Dictionary = texts.get("block", {})
	if not home:
		return String(t.get("away", ""))
	if String(b.get("husk", "")) == "":
		return String(t.get("no_husk", ""))
	if count >= cap:
		return String(t.get("cap", "")).format({"count": count, "cap": cap})
	if bool(ev.get("ok", false)):
		return ""
	if not cfg.get("anatomy", {}).has(String(b.get("kind", ""))):
		return String(t.get("kind", ""))
	var unplaced: int = (ev.get("unplaced", []) as Array).size()
	if unplaced > 0:
		return String(t.get("unplaced", "")).format({"n": unplaced})
	return String(t.get("min", "")).format({"n": int(cfg.get("min_remnants", 1))})


## The stats → verbs table: one row per stat, in SlabLogic.STATS order, all five always.
## -> [{stat, value: float, text: String (upright), helps: String, dominant: bool}]
static func stat_rows(stats: Dictionary, dominant: String, cfg: Dictionary, texts: Dictionary) -> Array:
	var out: Array = []
	for s in SlabLogic.STATS:
		out.append({"stat": s, "value": float(stats.get(s, 0.0)), "text": fmt_stat(float(stats.get(s, 0.0))),
			"helps": stat_helps(s, cfg, texts), "dominant": s == dominant})
	return out


## What a stat helps, in the town's own words and buildings: slab.stat_helps (town.json). `texts` is kept for the
## caller's signature.
static func stat_helps(stat: String, cfg: Dictionary, _texts: Dictionary) -> String:
	return String(cfg.get("stat_helps", {}).get(stat, ""))


## A stat as an upright number: whole when it is whole ("6"), else one decimal ("3.5").
static func fmt_stat(x: float) -> String:
	if absf(x - roundf(x)) < 0.05:
		return str(int(roundf(x)))
	return "%.1f" % x


## A husk button: "Hulk · muscle 3 · nerve 1" (the kind's noun and its slot anatomy).
static func husk_label(kind: String, cfg: Dictionary, sep := " · ") -> String:
	var parts: Array = [String(cfg.get("nouns", {}).get(kind, kind.capitalize()))]
	var anatomy: Dictionary = cfg.get("anatomy", {}).get(kind, {})
	for g in SlabLogic.GROUPS:
		if int(anatomy.get(g, 0)) > 0:
			parts.append("%s %d" % [g, int(anatomy[g])])
	return sep.join(parts)


## A remnant button: "power 2 · common" (aspect, magnitude, rarity).
static func remnant_label(r: Dictionary, sep := " · ") -> String:
	return "%s %d%s%s" % [String(r.get("aspect", "")), int(r.get("magnitude", 0)), sep, String(r.get("rarity", ""))]


## The siege choices: forts [{id, name, held}], held ones first, world order kept within each.
static func siege_forts(forts: Array) -> Array:
	var held: Array = []
	var rest: Array = []
	for f in forts:
		(held if bool(f.get("held", false)) else rest).append(f)
	return held + rest


## The foreman choices: built job buildings (level >= 1), in view order. A foreman multiplies job output only
## (the E3-3 ruling), so the menu offers a building whose buildings.json `jobs` aren't empty (`bcfg`), whatever its
## slots read now (a Chapel's tend slots open only while a vat is staffed); with no `bcfg`, live slots > 0.
## -> [{lot_id, label, foreman (uid or "")}]; `labels` = building id -> label.
static func foreman_lots(buildings: Array, labels: Dictionary, bcfg: Dictionary = {}) -> Array:
	var out: Array = []
	for b in buildings:
		var bid := String(b.get("building_id", ""))
		var jobs := not ((bcfg.get(bid, {}) as Dictionary).get("jobs", {}) as Dictionary).is_empty() if not bcfg.is_empty() \
			else int(b.get("slots", 0)) > 0
		if int(b.get("level", 0)) < 1 or not jobs:
			continue
		out.append({"lot_id": String(b.get("lot_id", "")), "label": String(labels.get(bid, bid.capitalize())),
			"foreman": String(b.get("foreman", ""))})
	return out


## lot id -> building label, for place_text.
static func lot_labels(buildings: Array, labels: Dictionary) -> Dictionary:
	var out := {}
	for b in buildings:
		var bid := String(b.get("building_id", ""))
		out[String(b.get("lot_id", ""))] = String(labels.get(bid, bid.capitalize()))
	return out


## Whether the raise's name field takes focus at `phase`: "formed" (the hold completed) or "key_up" (a
## Space hold's key was released). A mouse hold focuses it at once (its button is disabled the moment the
## hold completes, so button_up never comes); a Space hold waits for the key to be up, or the held key's
## repeats would type spaces into the name.
static func name_focus_now(by_key: bool, phase: String) -> bool:
	return (phase == "formed" and not by_key) or (phase == "key_up" and by_key)


## The hold clock: seconds held so far. It grows while held, stops at `hold_s`, and a release
## resets it. progress = held_s / hold_s; the raise completes only when held_s reaches hold_s.
static func hold_step(held_s: float, held: bool, dt: float, hold_s: float) -> float:
	if not held:
		return 0.0
	return minf(held_s + maxf(dt, 0.0), hold_s)


static func hold_progress(held_s: float, hold_s: float) -> float:
	if hold_s <= 0.0:
		return 1.0
	return clampf(held_s / hold_s, 0.0, 1.0)


## The set piece's collapse length: it ends on a beat, the next one at least `min_beats` away
## (`phase` = Pulse.phase(0) now, `tempo_s` = the beat in seconds), so it lasts about one beat.
static func collapse_s(phase: float, tempo_s: float, min_beats: float) -> float:
	var left := (1.0 - clampf(phase, 0.0, 1.0)) * tempo_s
	while left < min_beats * tempo_s - 0.0001:
		left += tempo_s
	return left


## Rune centres around the preview: each group clusters about its own angle (`group_deg`,
## degrees, 0 = right, clockwise on screen), its slots `step_deg` apart on an ellipse, the group's
## first slot topmost on either side.
static func rune_points(groups: Array, center: Vector2, rx: float, ry: float, group_deg: Dictionary, step_deg: float) -> Array:
	var count := {}
	for g in groups:
		count[g] = int(count.get(g, 0)) + 1
	var seen := {}
	var out: Array = []
	for g in groups:
		var k := int(seen.get(g, 0))
		seen[g] = k + 1
		var anchor := float(group_deg.get(g, 0.0))
		var down := 1.0 if cos(deg_to_rad(anchor)) >= 0.0 else -1.0  # clockwise runs down the right side, up the left
		var deg := anchor + down * (float(k) - float(count[g] - 1) * 0.5) * step_deg
		var a := deg_to_rad(deg)
		out.append(center + Vector2(cos(a) * rx, sin(a) * ry))
	return out


## Everything the crypt tab's bind reads from the views, as one number: Relish's place (what the gate says; a
## dead Relish's wait by the whole second), the husks and remnants on hand, the big undead (count, cap, each
## one's fields), the built lots (the place words and the Foreman choices) and the forts (the Siege choices,
## the place words). Equal views give an equal number, so the panel can leave itself alone on a bind where none
## of it moved; the stocks and rates the views also carry change every refresh and are not in it.
static func bind_sig(views: Dictionary) -> int:
	var relish: Dictionary = views.get("relish", {})
	var inv: Dictionary = views.get("inventory", {})
	var bu: Dictionary = views.get("big_undead", {})
	var lots: Array = []
	for b in views.get("town", {}).get("buildings", []):
		lots.append([b.get("lot_id", ""), b.get("building_id", ""), b.get("level", 0), b.get("slots", 0), b.get("foreman", "")])
	return [[relish.get("state", ""), relish.get("at", ""), relish.get("target", ""), relish.get("respawn_with_clone", false),
		ceili(maxf(float(relish.get("dead_s_left", 0.0)), 0.0))], views.get("fort_names", {}), views.get("forts", []),
		inv.get("husks", []), inv.get("remnants", []), bu.get("count", 0), bu.get("cap", 0), bu.get("big_undead", []), lots].hash()
