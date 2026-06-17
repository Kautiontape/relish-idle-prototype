class_name Roster
extends RefCounted
## Fakes "the crypt handed you these" — the source of undead is a button, not a
## raid. Each worker is one of a few archetypes (weighted) carrying the full
## eight-stat line so the data shape matches the siblings; the town sim only
## reads four of them for now (beef/power → quarry, wits/power → workshop,
## speed → walk). Charm/dread/magic/persistence ride along for when the living
## become customers.

const STAT_KEYS := ["power", "beef", "speed", "wits", "charm", "dread", "magic", "persistence"]

## One undead. `id` is unique within a Sim; `rng` rolls archetype + jitter.
static func make_worker(id: int, rng: RandomNumberGenerator) -> Dictionary:
	var arch := _pick_archetype(rng)
	var stats := {}
	for k in STAT_KEYS:
		stats[k] = 0
	var jitter := int(ConfigDb.v("workers", "stat_jitter"))
	for k in (arch["stats"] as Dictionary):
		stats[k] = int(arch["stats"][k]) + rng.randi_range(0, jitter)
	return {
		"id": id,
		"name": "%s %d" % [arch["name"], id],
		"archetype": String(arch["id"]),
		"aspect": String(arch["aspect"]),
		"color": String(arch["color"]),
		"stats": stats,
	}

static func _pick_archetype(rng: RandomNumberGenerator) -> Dictionary:
	var arch: Array = ConfigDb.v("workers", "archetypes")
	var total := 0.0
	for a in arch:
		total += float(a["weight"])
	var r := rng.randf() * total
	var acc := 0.0
	for a in arch:
		acc += float(a["weight"])
		if r <= acc:
			return a
	return arch[0]
