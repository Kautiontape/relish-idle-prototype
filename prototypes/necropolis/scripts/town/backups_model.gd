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


## Whether the death numbers are still a stub, so the panel tags them "coming": town.json view.backups
## numbers_wired is false (STANDIN(E3)) and nothing in `death` shows the sim computing it for real, which
## is a wait (respawn_s > 0) or a phylactery outcome (the stub never reports either).
static func numbers_pending(death: Dictionary, tx: Dictionary) -> bool:
	if bool(tx.get("numbers_wired", false)):
		return false
	return not (float(death.get("respawn_s", 0.0)) > 0.0 or String(death.get("outcome", "")) == "phylactery")


## The ladder's current step's tag: "now", or "now · numbers coming" while the numbers are a stub.
static func ladder_now_text(tx: Dictionary, pending: bool) -> String:
	return String(tx.get("ladder_now_pending" if pending else "ladder_now", ""))


## The outcome in words, with the wait from `respawn_s` ("" for an outcome the views don't know); `pending`
## adds the "(numbers coming)" tag.
static func outcome_text(death: Dictionary, tx: Dictionary, pending := false) -> String:
	var line: String = String(tx.get("outcome", {}).get(String(death.get("outcome", "")), ""))
	if line == "":
		return ""
	var wait := wait_text(float(death.get("respawn_s", 0.0)), tx)
	var after: String = String(tx.get("after", "")).format({"wait": wait}) if wait != "" else String(tx.get("at_once", ""))
	var text := line.format({"after": after})
	return text + " " + String(tx.get("numbers_coming", "")) if pending else text


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


## "the party: Old Gristle (foreman at the Market), Hulking-Brutal Hulk". `crypt_texts` = view.crypt (its place
## words), `slab` = town.json slab: a member still carrying the mint default "Big u2" is shown by the slab's name.
static func party_text(party: Array, lot_labels: Dictionary, fort_names: Dictionary, crypt_texts: Dictionary, tx: Dictionary, slab: Dictionary = {}) -> String:
	var label := loses_text("party", tx)
	if party.is_empty():
		return label
	var names: Array = []
	for m in party:
		var place := String(m.get("place", ""))
		var shown := SlabLogic.display_name(m, slab)
		if place == "party" or place == "":
			names.append(String(tx.get("party_member_plain", "{name}")).format({"name": shown}))
		else:
			names.append(String(tx.get("party_member", "{name}")).format({"name": shown,
				"place": CryptLogic.place_text(place, lot_labels, fort_names, crypt_texts)}))
	return String(tx.get("party_names", "{label}: {names}")).format({"label": label, "names": ", ".join(names)})


## The loss as one headline: "She would lose: the party: Old Gristle, loot since the last checkpoint." `loses` =
## death.loses, `party` = view_party().party; the rest as in party_text.
static func loses_line(loses: Array, party: Array, lot_labels: Dictionary, fort_names: Dictionary, crypt_texts: Dictionary, tx: Dictionary, slab: Dictionary = {}) -> String:
	var items: Array = []
	for id in loses:
		if String(id) == "party":
			items.append(party_text(party, lot_labels, fort_names, crypt_texts, tx, slab))
		else:
			items.append(loses_text(String(id), tx))
	return "%s: %s." % [String(tx.get("loses_header", "")), ", ".join(items) if not items.is_empty() else String(tx.get("loses_none", ""))]


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


## "staffing takes 1 hand from Pit" from a TownBehaviour.staffing_diff (the jobs that lose hands), for a vat
## that is not staffed; "unstaffing frees 1 hand for Pit" (the jobs that gain them) for one that is. When no
## job hand moves and `idle` (workers.idle, -1 = unknown) holds a whole idle hand, the line says why: "10 idle
## hands: staffing costs nothing today" (the idle count rounded down).
static func staffing_cost_text(diff: Array, labels: Dictionary, tx: Dictionary, staffed := false, idle := -1.0) -> String:
	var moved: Array = []
	for d in diff:
		var n := roundi(float(d["delta"]) * (1.0 if staffed else -1.0))
		if n > 0:
			moved.append([String(d["id"]), n])
	moved.sort_custom(func(a: Array, b: Array) -> bool: return a[1] > b[1])
	var pre := "unstaff_gain" if staffed else "staff_cost"
	if moved.is_empty():
		var n := floori(idle)
		if n >= 1:
			return String(tx.get("staff_idle", "")).format({"n": n, "hands": tx.get("hand" if n == 1 else "hands", "hands")})
		return String(tx.get(pre + "_none", ""))
	var items: Array = []
	for l in moved:
		items.append(String(tx.get(pre + "_item", "{n} {hand} from {job}")).format({"n": l[1],
			"hand": tx.get("hand" if l[1] == 1 else "hands", "hands"), "job": String(labels.get(l[0], String(l[0]).capitalize()))}))
	return String(tx.get(pre, "")).format({"what": ", ".join(items)})


## The Chapel's upkeep line as parts [[text, oblique]]: "Chapel upkeep −0.50/s gold", the signed rate
## slanted like every other rate. Several stores are joined with ", "; [] when nothing is paid.
static func upkeep_parts(up: Dictionary, label: String, tx: Dictionary) -> Array:
	var out: Array = []
	for store in up:
		if float(up[store]) <= 0.0:
			continue
		if not out.is_empty():
			out.append([", ", false])
		out.append_array(HudModel.fill_parts(String(tx.get("upkeep", "")), {"label": label,
			"rate": [[TownUI.fmt_rate(-float(up[store])), true]], "store": str(store)}))
	return out


## The Chapel's upkeep {gold, bone} from view_town().buildings (the first active or building one of
## `chapel_id`), or {} when there is none or the entry carries no upkeep.
static func chapel_upkeep(buildings: Array, chapel_id: String) -> Dictionary:
	for b in buildings:
		if String(b.get("building_id", "")) == chapel_id and b.get("upkeep") is Dictionary:
			return b["upkeep"]
	return {}


# ------------------------------------------------------------- signatures ----
## Each tab section as one number over exactly the view fields it reads. Equal inputs give an equal number, so
## the panel can leave a section alone on a bind where it hasn't moved (the stocks and rates the town view
## carries change every refresh and none of these read them).
## The "what a death costs" section: the death fields, the wait, the party (with the lot and fort names its place
## words use).
static func death_sig(views: Dictionary) -> int:
	var bk: Dictionary = views.get("backups", {})
	var lots := {}
	for b in views.get("town", {}).get("buildings", []):
		lots[String(b.get("lot_id", ""))] = String(b.get("building_id", ""))
	return [bk.get("death", {}), bk.get("dead_s_left", 0.0), views.get("party", {}).get("party", []), lots,
		views.get("fort_names", {})].hash()


## The vats section: the vats, the chapel's upkeep and what the staffing projection reads: per building its id,
## state, slots, staff_cap and upkeep; the idle hands; the jobs (id, slots, staffed); the ladder. Nothing else
## the town view carries (progress, output, rot, muster, lifetime, the other worker counts) is in it, so it
## doesn't move on a refresh that only ran the sim. The idle hands are not hashed: they creep by fractions every
## tick, and they reach the vats only through the staffing-cost lines. `costs` is those lines as the panel shows
## them (staffing_costs), so the sig moves exactly when a visible line does (idle 0.5 -> 0.6 flips "takes 1 hand"
## to "no hand" with rooms full; 10.0 -> 10.4 flips nothing).
static func vats_sig(views: Dictionary, costs := []) -> int:
	var town: Dictionary = views.get("town", {})
	var bs: Array = []
	for b in town.get("buildings", []):
		bs.append([b.get("building_id", ""), b.get("state", ""), b.get("slots", 0), b.get("staff_cap", -1), b.get("upkeep", {})])
	var jobs: Array = []
	for j in town.get("jobs", []):
		jobs.append([j.get("id", ""), j.get("slots", 0), j.get("staffed", 0.0)])
	return [views.get("backups", {}).get("vats", []), views.get("backups", {}).get("clones_ready", 0), bs, jobs,
		costs, town.get("ladder", []), town.get("ladder_effective", [])].hash()


## The staffing-cost line of each vat, in vat order, from the shell's cached projection `project` (order, extra
## -> jobs): "staffing takes 1 hand from Pit" or "unstaffing frees 1 hand for Pit". [] while there is no projection.
static func staffing_costs(views: Dictionary, project: Callable, labels: Dictionary, tx: Dictionary) -> Array:
	var out: Array = []
	if not project.is_valid():
		return out
	var order: Array = TownBehaviour.effective(views.get("town", {}))
	var idle := float(views.get("town", {}).get("workers", {}).get("idle", -1.0))
	for v in views.get("backups", {}).get("vats", []):
		var staffed := bool(v.get("staffed", false))
		var diff := TownBehaviour.staffing_diff(project.call(order), project.call(order, {int(v.get("slot", 0)): not staffed}))
		out.append(staffing_cost_text(diff, labels, tx, staffed, idle))
	return out


## The ossuary section: the charges, the simulacra and stock, the craft rows.
static func ossuary_sig(views: Dictionary) -> int:
	var bk: Dictionary = views.get("backups", {})
	var inv: Dictionary = views.get("inventory", {})
	return [bk.get("phylactery_charges", 0), bk.get("phylactery_max_per_dungeon", 0), inv.get("simulacra_ready", 0),
		inv.get("essence", 0), inv.get("relics", 0), views.get("catalog", {}).get("crafts", [])].hash()
