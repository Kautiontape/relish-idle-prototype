class_name Loot
extends RefCounted
## Drop rolls (§7.2, §11). A remnant = one primary stat at a rolled magnitude
## plus echoes from ONE shared budget. Rarity sets the budget; the roll sets
## its allocation (the combat/town lean).

const STATS := ["power", "beef", "speed", "wits", "charm", "dread", "magic", "persistence"]

const ASPECT_OF_STAT := {
	"power": "muscle", "beef": "muscle",
	"speed": "nerve", "wits": "nerve",
	"charm": "presence", "dread": "presence",
	"magic": "anima", "persistence": "anima",
}

static func weighted_pick(rng: RandomNumberGenerator, weights: Dictionary) -> String:
	var total := 0.0
	for k in weights:
		total += float(weights[k])
	var roll := rng.randf() * total
	for k in weights:
		roll -= float(weights[k])
		if roll <= 0.0:
			return k
	return weights.keys()[0]

static func roll_rarity(rng: RandomNumberGenerator) -> String:
	return weighted_pick(rng, ConfigDb.v("rarity", "weights"))

## MADE UP (not in doc): primary stat is uniform among the eight.
static func roll_remnant(rng: RandomNumberGenerator, forced_rarity: String = "") -> Dictionary:
	var rcfg: Dictionary = ConfigDb.data["rarity"]
	var rarity := forced_rarity if forced_rarity != "" else roll_rarity(rng)
	var stat: String = STATS[rng.randi_range(0, STATS.size() - 1)]
	var mag_range: Array = rcfg["magnitude"][rarity]
	var magnitude := rng.randi_range(int(mag_range[0]), int(mag_range[1]))
	var budget := int(rcfg["echo_budget"][rarity])

	# Lean: most rolls go heavily combat- or town-side; the even split is the
	# rare all-rounder outcome of the same system, never a property of rarity.
	var combat_share: float
	if rng.randf() < float(rcfg["lean_strong_chance"]):
		var strong := rng.randf_range(float(rcfg["lean_strong_min"]), 1.0)
		combat_share = strong if rng.randf() < 0.5 else 1.0 - strong
	else:
		combat_share = rng.randf_range(float(rcfg["lean_even_min"]), 1.0 - float(rcfg["lean_even_min"]))
	var combat_pts := roundi(budget * combat_share)
	var town_pts := budget - combat_pts

	var echoes: Array = []
	echoes.append_array(_spend(rng, "combat", combat_pts))
	echoes.append_array(_spend(rng, "town", town_pts))

	return {"stat": stat, "magnitude": magnitude, "rarity": rarity,
		"echoes": echoes, "combat_points": combat_pts, "town_points": town_pts}

## MADE UP (not in doc): a side's points land on at most two echoes, chunky.
static func _spend(rng: RandomNumberGenerator, side: String, pts: int) -> Array:
	var out: Array = []
	if pts <= 0:
		return out
	var pool: Array = ConfigDb.data["echoes"][side].keys()
	var first: String = pool[rng.randi_range(0, pool.size() - 1)]
	var first_pts := pts if pts <= 2 else rng.randi_range(ceili(pts / 2.0), pts)
	out.append({"id": first, "points": first_pts, "side": side})
	if pts - first_pts > 0:
		var second: String = pool[rng.randi_range(0, pool.size() - 1)]
		if second == first:
			out[0]["points"] = pts
		else:
			out.append({"id": second, "points": pts - first_pts, "side": side})
	return out

static func roll_husk(rng: RandomNumberGenerator) -> String:
	return weighted_pick(rng, ConfigDb.v("rarity", "husk_weights"))

## Kills drop 1+ essence, bigger enemies weighted higher (§9).
static func essence_count(rng: RandomNumberGenerator, beef: int) -> int:
	return 1 + int(beef * float(ConfigDb.v("stats", "essence_per_beef")))

static func remnant_label(r: Dictionary) -> String:
	return "%s %d" % [String(r["stat"]).capitalize(), r["magnitude"]]

static func rarity_color(rarity: String) -> Color:
	match rarity:
		"uncommon": return Color(0.45, 0.85, 0.45)
		"rare": return Color(0.4, 0.65, 1.0)
		"legendary": return Color(1.0, 0.65, 0.25)
		_: return Color(0.78, 0.78, 0.8)
