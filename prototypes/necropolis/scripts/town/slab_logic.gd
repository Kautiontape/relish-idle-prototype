class_name SlabLogic
extends RefCounted
## The crypt slab's pure math: anatomy slots, remnant assignment, derived stats,
## role verdict and Adjective-Noun name. Ported from the slab prototype with
## every config passed in (`cfg` = configs["town"]["slab"]). No autoloads.

const STATS := ["power", "beef", "wits", "presence", "speed"]
const GROUPS := ["muscle", "nerve", "presence", "anima"]


## One group id per slot, in GROUPS order. [] for an unknown kind.
static func slots_for(kind: String, cfg: Dictionary) -> Array:
	var out: Array = []
	var anatomy: Dictionary = cfg.get("anatomy", {})
	if not anatomy.has(kind):
		return out
	for g in GROUPS:
		for _i in int(anatomy[kind].get(g, 0)):
			out.append(g)
	return out


static func fits(group: String, stat: String, cfg: Dictionary) -> bool:
	var allowed: Array = cfg.get("group_stats", {}).get(group, [])
	if "*" in allowed:
		return stat in STATS
	return stat in allowed


static func role_label(role_id: String, cfg: Dictionary) -> String:
	var r: Dictionary = cfg.get("roles", {}).get(role_id, {})
	return String(r.get("label", role_id.capitalize()))


static func evaluate(husk_kind: String, remnants: Array, cfg: Dictionary) -> Dictionary:
	var groups := slots_for(husk_kind, cfg)
	var slot_rem: Array = []
	slot_rem.resize(groups.size())
	slot_rem.fill(-1)
	var unplaced: Array = []
	var leftovers: Array = []
	var bad: bool = not cfg.get("anatomy", {}).has(husk_kind)

	# Pass 1: each remnant takes the first empty slot of its own (non-anima) group.
	for i in remnants.size():
		var stat := String(remnants[i].get("aspect", ""))
		if not (stat in STATS):
			unplaced.append(i)
			continue
		var s := _first_empty(groups, slot_rem, stat, cfg, false)
		if s >= 0:
			slot_rem[s] = i
		else:
			leftovers.append(i)
	# Pass 2: leftovers fall into empty anima slots.
	for i in leftovers:
		var s := _first_empty(groups, slot_rem, String(remnants[i]["aspect"]), cfg, true)
		if s >= 0:
			slot_rem[s] = i
		else:
			unplaced.append(i)
	unplaced.sort()

	var stats := {}
	for s in STATS:
		stats[s] = 0.0
	var slots: Array = []
	var filled := 0
	for j in groups.size():
		slots.append({"group": groups[j], "remnant_index": slot_rem[j]})
		if slot_rem[j] >= 0:
			filled += 1
			var r: Dictionary = remnants[slot_rem[j]]
			stats[String(r["aspect"])] += float(r.get("magnitude", 0))

	var ranked := _ranked(stats)
	var dominant: String = ranked[0]["stat"] if not ranked.is_empty() else ""
	var role_id := "hollow"
	if dominant != "":
		role_id = String(cfg.get("role_by_stat", {}).get(dominant, "hollow"))
	var noun := noun_of(husk_kind, cfg)
	var adj := _adjective(ranked, cfg)
	var label := role_label(role_id, cfg)
	var good_for := String(cfg.get("roles", {}).get(role_id, {}).get("good_for", ""))
	var ok: bool = not bad and unplaced.is_empty() and filled >= int(cfg.get("min_remnants", 1))
	return {
		"ok": ok,
		"reason": "" if ok else "invalid_recipe",
		"kind": husk_kind,
		"noun": noun,
		"adjective": adj,
		"name": _name_of(ranked, husk_kind, cfg),
		"stats": stats,
		"role": role_id,
		"role_label": label,
		"role_line": "%s: good for %s" % [label, good_for],
		"dominant": dominant,
		"slots": slots,
		"slot_count": groups.size(),
		"filled": filled,
		"unplaced": unplaced,
	}


## The kind's noun ("hulk" -> "Hulk").
static func noun_of(kind: String, cfg: Dictionary) -> String:
	return String(cfg.get("nouns", {}).get(kind, kind.capitalize()))


## The one naming rule: the Adjective(-Adjective) from the ranked stats, then the kind's noun.
static func _name_of(ranked: Array, kind: String, cfg: Dictionary) -> String:
	return "%s %s" % [_name_adjectives(ranked, cfg), noun_of(kind, cfg)]


## The slab's Adjective-Noun name for a `kind` and its `stats` (a big undead's stats dict): exactly what
## `evaluate` names a creature of the same kind and stat totals.
static func name_for(kind: String, stats: Dictionary, cfg: Dictionary) -> String:
	return _name_of(_ranked(stats), kind, cfg)


## True when `entry`'s name is the sim's mint default ("Big " + uid, or empty) rather than a name somebody chose.
static func has_default_name(entry: Dictionary, cfg: Dictionary) -> bool:
	var nm := String(entry.get("name", ""))
	return nm == "" or nm == String(cfg.get("default_name_prefix", "Big ")) + String(entry.get("uid", ""))


## The name to show for a big undead entry: the slab's name for its kind and stats while it still carries the
## mint default; its own name otherwise. An entry with no kind keeps whatever name it has.
static func display_name(entry: Dictionary, cfg: Dictionary) -> String:
	if has_default_name(entry, cfg) and String(entry.get("kind", "")) != "":
		return name_for(String(entry["kind"]), entry.get("stats", {}), cfg)
	return String(entry.get("name", ""))


static func _first_empty(groups: Array, slot_rem: Array, stat: String, cfg: Dictionary, anima: bool) -> int:
	for j in groups.size():
		if slot_rem[j] != -1:
			continue
		if (groups[j] == "anima") != anima:
			continue
		if fits(groups[j], stat, cfg):
			return j
	return -1


## [{stat, mag}] for stats > 0, magnitude descending, STATS order breaking ties.
static func _ranked(stats: Dictionary) -> Array:
	var ranked: Array = []
	for i in STATS.size():
		var m := float(stats.get(STATS[i], 0.0))
		if m > 0.0:
			ranked.append({"stat": STATS[i], "mag": m, "idx": i})
	ranked.sort_custom(func(a, b):
		if a["mag"] != b["mag"]:
			return a["mag"] > b["mag"]
		return a["idx"] < b["idx"])
	return ranked


static func _adjective(ranked: Array, cfg: Dictionary) -> String:
	if ranked.is_empty():
		return String(cfg.get("hollow_adjective", "Hollow"))
	return String(cfg.get("stat_adjectives", {}).get(ranked[0]["stat"], ""))


## The adjective part of the name: "A", or "A-B" when the second stat blends in.
static func _name_adjectives(ranked: Array, cfg: Dictionary) -> String:
	var a := _adjective(ranked, cfg)
	if ranked.size() >= 2:
		var share: float = ranked[1]["mag"] / ranked[0]["mag"]
		var b := String(cfg.get("stat_adjectives", {}).get(ranked[1]["stat"], ""))
		if share >= float(cfg.get("blend_threshold", 0.6)) and b != a:
			return "%s%s%s" % [a, String(cfg.get("blend_connector", "-")), b]
	return a
