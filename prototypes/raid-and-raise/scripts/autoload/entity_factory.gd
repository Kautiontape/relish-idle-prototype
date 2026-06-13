extends Node
## Autoload "EntityFactory". Builds entities from config (data-driven, §1).
## One code path: everything returns an RRUnit differing only by setup dict.

const UnitScript := preload("res://scripts/entities/unit.gd")
const EssenceScript := preload("res://scripts/entities/essence.gd")

func make_enemy(id: String) -> RRUnit:
	var cfg: Dictionary = ConfigDb.enemy(id)
	return UnitScript.new().setup({
		"kind": RRUnit.Kind.ENEMY,
		"faction": RRUnit.Faction.ENEMY,
		"stats": cfg["stats"],
		"cadence": cfg["cadence"],
		"base_hp": cfg["base_hp"],
		"base_dmg": cfg["base_dmg"],
		"base_speed": cfg["base_speed"],
		"name": cfg["name"],
		"color": cfg["color"],
		"elite": cfg.get("elite", false),
		"boss": cfg.get("boss", false),
	})

## A permanent = Husk + slotted Remnants (§7). Validates remnants against the
## husk's Anatomy (each remnant needs a free Hollow of its parent Aspect).
func make_permanent(spec: Dictionary) -> RRUnit:
	var husk: Dictionary = ConfigDb.husk(spec["husk"])
	var anatomy: Dictionary = husk["anatomy"]
	var used := {"muscle": 0, "nerve": 0, "presence": 0, "anima": 0}
	var stats := {"power": 0.0, "beef": 0.0, "speed": 0.0, "wits": 0.0,
		"charm": 0.0, "dread": 0.0, "magic": 0.0, "persistence": 0.0}
	var echoes := {}
	var town_points := 0
	for r in spec["remnants"]:
		var aspect: String = Loot.ASPECT_OF_STAT[r["stat"]]
		used[aspect] += 1
		stats[r["stat"]] += float(r["magnitude"])
		for e in r.get("echoes", []):
			var side := echo_side(e["id"])
			if side == "combat":
				echoes[e["id"]] = echoes.get(e["id"], 0) + int(e["points"])
			else:
				town_points += int(e["points"])
	for a in used:
		if used[a] > int(anatomy[a]):
			push_error("Loadout '%s': %d %s remnants but husk %s has %d hollows" %
				[spec.get("name", "?"), used[a], a, spec["husk"], anatomy[a]])
	return UnitScript.new().setup({
		"kind": RRUnit.Kind.PERMANENT,
		"faction": RRUnit.Faction.PLAYER,
		"stats": stats,
		"cadence": husk["cadence"],
		"base_hp": husk["base_hp"],
		"base_dmg": husk["base_dmg"],
		"base_speed": husk["base_speed"],
		"name": spec.get("name", husk["name"]),
		"color": husk["color"],
		"echoes": echoes,
		"town_points": town_points,
		"source_remnants": spec["remnants"],
	})

func echo_side(id: String) -> String:
	if ConfigDb.data["echoes"]["combat"].has(id):
		return "combat"
	return "town"

## Chaff: three stats only — Power/Beef/Speed × circle accuracy (§7.3).
## Dead-flesh defaults for the base line; the gap to a raised permanent is the
## felt value of the Raising phase — do not "improve" chaff.
func make_chaff(mult: float) -> RRUnit:
	var s: Dictionary = ConfigDb.data["stats"]
	return UnitScript.new().setup({
		"kind": RRUnit.Kind.CHAFF,
		"faction": RRUnit.Faction.PLAYER,
		"stats": {
			"power": float(s["chaff_base_power"]) * mult,
			"beef": float(s["chaff_base_beef"]) * mult,
			"speed": float(s["chaff_base_speed"]) * mult,
		},
		"cadence": s["chaff_cadence"],
		"name": "",
		# Ash-lavender, NOT green: green is reserved for essence so a fresh batch
		# reads against the horde (the army is cool-toned, enemies are warm).
		"color": Color(0.66, 0.62, 0.74),
	})

func make_relish() -> RRUnit:
	return UnitScript.new().setup({
		"kind": RRUnit.Kind.RELISH,
		"faction": RRUnit.Faction.PLAYER,
		"stats": {"speed": float(ConfigDb.v("stats", "relish_speed_stat"))},
		"name": "Relish",
		"color": Color(0.78, 0.6, 0.95),
	})

func default_loadout() -> Array:
	var out: Array = []
	var specs: Array = ConfigDb.data["loadout"]["permanents"]
	var slots := int(ConfigDb.v("timers", "jar_slots"))
	for i in mini(specs.size(), slots):  # Soul Jar caps what you bring out (§3)
		out.append(make_permanent(specs[i]))
	return out

func make_essence() -> Essence:
	return EssenceScript.new()

## Arbitrary setup dict — playrooms and the debug spawner use this for
## punching bags, custom-Wits hunters, etc.
func make_custom(p: Dictionary) -> RRUnit:
	return UnitScript.new().setup(p)
