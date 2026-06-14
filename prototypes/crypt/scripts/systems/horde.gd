class_name Horde
extends RefCounted
## The population model. An undead is a plain Dictionary (so it tags and
## serializes like the slab's creatures); this class makes them and reads their
## shape. A blank form is a Hollow — the ablative baseline; remnants make
## champions. composition() is the legibility payoff: what shape is my horde?

const ASPECTS := ["muscle", "nerve", "presence", "anima"]

static func _zero_stats() -> Dictionary:
	var s := {}
	for k in Loot.STATS:
		s[k] = 0.0
	return s

## A bare body — no remnants, no stats. The expendable many.
static func make_hollow(id: int, form_id: String) -> Dictionary:
	return _finish({"id": id, "form_id": form_id, "stats": _zero_stats(), "echoes": {}, "tags": []})

## A kitted body — remnants summed into stats + echoes. The crafted few.
static func make_kitted(id: int, form_id: String, remnants: Array) -> Dictionary:
	var stats := _zero_stats()
	var echoes := {}
	for r in remnants:
		stats[r["stat"]] += float(r["magnitude"])
		for e in r.get("echoes", []):
			echoes[e["id"]] = int(echoes.get(e["id"], 0)) + int(e["points"])
	return _finish({"id": id, "form_id": form_id, "stats": stats, "echoes": echoes, "tags": []})

## Fill in the derived, read-only fields every view reads off a unit.
static func _finish(u: Dictionary) -> Dictionary:
	var stats: Dictionary = u["stats"]
	var echoes: Dictionary = u["echoes"]
	var noun: String = String(ConfigDb.husk(u["form_id"])["name"])
	var role: Dictionary = CreatureRole.of(stats, echoes)
	u["noun"] = noun
	u["name"] = CreatureNamer.full_name(noun, stats, echoes)
	u["role"] = String(role["role"])
	u["role_line"] = String(role["line"])
	u["aspect"] = dominant_aspect(stats)
	u["color"] = String(ConfigDb.husk(u["form_id"]).get("color", "#cccccc"))
	u["power"] = power_of(stats, echoes)
	u["tier"] = tier_of(u["power"])
	return u

static func dominant_aspect(stats: Dictionary) -> String:
	var best := ""
	var best_v := 0.0
	for s in Loot.STATS:
		if float(stats[s]) > best_v:
			best_v = float(stats[s])
			best = s
	return Loot.ASPECT_OF_STAT[best] if best != "" else "hollow"

static func power_of(stats: Dictionary, echoes: Dictionary) -> float:
	var p := float(ConfigDb.v("horde", "hollow_base_power"))
	for s in Loot.STATS:
		p += float(stats[s])
	for v in echoes.values():
		p += float(v)
	return p

static func tier_of(power: float) -> String:
	if power < float(ConfigDb.v("horde", "risen_power_threshold")):
		return "Hollow"
	if power < float(ConfigDb.v("horde", "champion_power_threshold")):
		return "Risen"
	return "Champion"

## The whole point: turn a pile into a shape. Counts by role and aspect, the
## counter-stat totals Vei's fronts are judged against, and total power.
static func composition(units: Array) -> Dictionary:
	var by_role := {}
	var by_aspect := {}
	var counter := {}
	for s in Loot.STATS:
		counter[s] = 0.0
	var total_power := 0.0
	for u in units:
		by_role[u["role"]] = int(by_role.get(u["role"], 0)) + 1
		by_aspect[u["aspect"]] = int(by_aspect.get(u["aspect"], 0)) + 1
		total_power += float(u["power"])
		var st: Dictionary = u["stats"]
		for s in Loot.STATS:
			counter[s] += float(st[s])
	return {"by_role": by_role, "by_aspect": by_aspect, "counter": counter,
		"total_power": total_power, "count": units.size()}
