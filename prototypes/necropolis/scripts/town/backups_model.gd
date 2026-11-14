class_name BackupsModel
extends RefCounted
## The backups tab's pure helpers: what a death would cost in words, the three-step ladder, a vat's
## state, the clone silhouette's reveal, craft costs and reasons, and the staffing cost line.
## No autoloads, no Engine: `tx` = town.json view.backups.

const LADDER := ["phylactery", "clone", "unmade"]  # MECHANICS §7: the order at HP 0, best first


## "60 s", "10 min" (from `wait_switch_s` up); "" for no wait.
static func wait_text(s: float, tx: Dictionary) -> String:
	if s <= 0.0:
		return ""
	if s >= float(tx.get("wait_switch_s", 90)):
		return String(tx.get("wait_min", "{n} min")).format({"n": roundi(s / 60.0)})
	return String(tx.get("wait_s", "{n} s")).format({"n": roundi(s)})


## The outcome in words, with the wait from `respawn_s` ("" for an outcome the views don't know).
static func outcome_text(death: Dictionary, tx: Dictionary) -> String:
	var line: String = String(tx.get("outcome", {}).get(String(death.get("outcome", "")), ""))
	if line == "":
		return ""
	var wait := wait_text(float(death.get("respawn_s", 0.0)), tx)
	var after: String = String(tx.get("after", "")).format({"wait": wait}) if wait != "" else String(tx.get("at_once", ""))
	return line.format({"after": after})


## The three steps best first: [{id, current}], the step the outcome names marked.
static func ladder(outcome: String) -> Array:
	var out: Array = []
	for id in LADDER:
		out.append({"id": id, "current": id == outcome})
	return out


static func loses_text(id: String, tx: Dictionary) -> String:
	var known: Dictionary = tx.get("loses", {})
	if known.has(id):
		return String(known[id])
	return String(tx.get("loses_other", "{id}")).format({"id": id.replace("_", " ")})


static func loses_list(loses: Array, tx: Dictionary) -> Array:
	var out: Array = []
	for id in loses:
		out.append(loses_text(String(id), tx))
	return out


## "the party: Old Gristle (foreman at the Market), Big u2". `crypt_texts` = view.crypt (its place words).
static func party_text(party: Array, lot_labels: Dictionary, fort_names: Dictionary, crypt_texts: Dictionary, tx: Dictionary) -> String:
	var label := loses_text("party", tx)
	if party.is_empty():
		return label
	var names: Array = []
	for m in party:
		var place := String(m.get("place", ""))
		if place == "party" or place == "":
			names.append(String(tx.get("party_member_plain", "{name}")).format({"name": String(m.get("name", ""))}))
		else:
			names.append(String(tx.get("party_member", "{name}")).format({"name": String(m.get("name", "")),
				"place": CryptLogic.place_text(place, lot_labels, fort_names, crypt_texts)}))
	return String(tx.get("party_names", "{label}: {names}")).format({"label": label, "names": ", ".join(names)})


static func vat_state_text(vat: Dictionary, tx: Dictionary) -> String:
	var s: Dictionary = tx.get("vat_state", {})
	if bool(vat.get("ready", false)):
		return String(s.get("ready", ""))
	return String(s.get("staffed" if bool(vat.get("staffed", false)) else "unstaffed", ""))


## The figure's strokes (unit box) scaled into `r`, cut so `reveal` (0..1) of the total length is drawn.
static func reveal_strokes(unit: Array, r: Rect2, reveal: float) -> Array[PackedVector2Array]:
	var scaled: Array[PackedVector2Array] = []
	for pl in unit:
		var p := PackedVector2Array()
		for pt in pl:
			p.append(r.position + Vector2(float(pt[0]), float(pt[1])) * r.size)
		scaled.append(p)
	return TownModel.truncate(scaled, reveal)


## "20 essence, 1 relic" (a zero part is left out; "free" when both are).
static func cost_text(cost: Dictionary, tx: Dictionary) -> String:
	var parts: Array = []
	var ess := int(cost.get("essence", 0))
	var rel := int(cost.get("relics", 0))
	if ess > 0:
		parts.append(String(tx.get("cost_part", "{n} {what}")).format({"n": ess, "what": tx.get("essence", "essence")}))
	if rel > 0:
		parts.append(String(tx.get("cost_part", "{n} {what}")).format({"n": rel, "what": tx.get("relic" if rel == 1 else "relics", "relics")}))
	return ", ".join(parts) if not parts.is_empty() else String(tx.get("cost_none", "free"))


static func craft_reason_text(reason: String, tx: Dictionary) -> String:
	return String(tx.get("craft_reasons", {}).get(reason, reason.replace("_", " ")))


static func craft_label(item_id: String, tx: Dictionary) -> String:
	return String(tx.get("craft_labels", {}).get(item_id, item_id.replace("_", " ").capitalize()))


## Charges as countable pips: "◆◆◆", capped with "+n", "none" at 0.
static func pips_text(n: int, tx: Dictionary) -> String:
	if n <= 0:
		return String(tx.get("charges_none", "none"))
	var cap := int(tx.get("pip_cap", 8))
	var out: String = String(tx.get("pip", "◆")).repeat(mini(n, cap))
	if n > cap:
		out += String(tx.get("pip_more", " +{n}")).format({"n": n - cap})
	return out


## "staffing takes 1 hand from Pit" from a TownBehaviour.staffing_diff (the jobs that lose hands).
static func staffing_cost_text(diff: Array, labels: Dictionary, tx: Dictionary) -> String:
	var lost: Array = []
	for d in diff:
		var n := roundi(-float(d["delta"]))
		if n > 0:
			lost.append([String(d["id"]), n])
	lost.sort_custom(func(a: Array, b: Array) -> bool: return a[1] > b[1])
	if lost.is_empty():
		return String(tx.get("staff_cost_none", ""))
	var items: Array = []
	for l in lost:
		items.append(String(tx.get("staff_cost_item", "{n} {hand} from {job}")).format({"n": l[1],
			"hand": tx.get("hand" if l[1] == 1 else "hands", "hands"), "job": String(labels.get(l[0], String(l[0]).capitalize()))}))
	return String(tx.get("staff_cost", "staffing takes {what}")).format({"what": ", ".join(items)})


## The Chapel's upkeep {gold, bone} from view_town().buildings (the first active or building one of
## `chapel_id`), or {} when there is none or the entry carries no upkeep.
static func chapel_upkeep(buildings: Array, chapel_id: String) -> Dictionary:
	for b in buildings:
		if String(b.get("building_id", "")) == chapel_id and b.get("upkeep") is Dictionary:
			return b["upkeep"]
	return {}
