class_name Results
extends RefCounted
## Result and seed validation (STATE-API §8.4) and the v1 -> v2 adapter (§8.5).
## Pure static functions: no state, no config access, no autoloads.

const KINDS := ["raid", "boss", "town", "map", "raid_seed", "boss_seed"]

## Spec grammar. A String is a leaf token, an Array is [element spec], a Dictionary lists the
## required keys. Tokens: int, int+ (>= 0), float, mass (>= 0), str, bool, dict, score (0..100),
## aspect, rarity, front (the last three are a str that must be in its list).
const _RAID := {
	"run_id": "int", "seed_rev": "int", "fort_id": "str",
	"warden_beaten": "bool", "retreated": "bool", "relish_died": "bool", "revived_in_place": "int+",
	"killed_living_mass": "mass",
	"raised": [{"score": "score", "count": "int+", "mass": "mass"}],
	"chaff_mass": "mass", "garrison_mass": "mass", "party_lost": ["str"],
	"loot": {
		"relics": "int+", "blueprints": ["str"], "husks": [{"kind": "str"}],
		"remnants": [{"aspect": "aspect", "rarity": "rarity", "magnitude": "int+"}], "essence": "int+",
	},
}
const _BOSS := {
	"run_id": "int", "seed_rev": "int", "won": "bool", "fronts_cleared": ["front"],
	"relish_deaths": "int+", "backups_spent": {"phylactery": "int+", "clones": "int+"},
	"party_lost": ["str"], "backlog_spent": "mass",
}
const _TELEPORT := {"teleport_to": "str"}
const _STATS := {"power": "float", "beef": "float", "wits": "float", "presence": "float", "speed": "float"}
const _RAID_SEED := {
	"kind": "str", "run_id": "int", "seed_rev": "int", "rng_seed": "str",
	"fort": {"id": "str", "name": "str", "tier": "int", "cap": "float", "first_clear": "bool",
		"first_dungeon": "bool", "clears_since_retaken": "int", "yield_mult": "float"},
	"living": "float", "dead": "float", "undead": "float",
	"garrison_units": "int", "garrison_in_mass": "float", "garrison_mass_div": "float", "starter_units": "int",
	"party": [{"uid": "str", "name": "str", "kind": "str", "role": "str", "stats": _STATS}],
	"digest_q": "float", "phylactery_charges": "int", "phylactery_max_per_dungeon": "int",
	"clones_ready": "int", "warden": {"archetype": "str", "tier": "int"}, "warden_spec": "dict",
	"loot_table_id": "str", "loot_hint": "str", "chest_husk": "bool", "watchtower": "bool",
	"relish_hp": "float",
}
const _BOSS_SEED := {
	"kind": "str", "run_id": "int", "seed_rev": "int", "rng_seed": "str",
	"backlog": "float", "living_pool": "float", "odds": "float", "sign": "int", "drain_s": "float",
	"digest_q": "float", "vei_capacity": "float",
	"fronts": [{"id": "str", "need": "float", "have": "float", "assigned": ["str"]}],
	"fronts_required": "int",
	"party": [{"uid": "str", "name": "str", "kind": "str", "role": "str", "stats": _STATS, "front": "str"}],
	"phylactery_charges": "int", "clones_ready": "int", "relish_hp": "float",
}


## §8.4. Returns reason codes; an empty array means valid. `unknown_kind` and `unknown_v` come
## alone (nothing else can be judged). Paths read `loot.relics`, `raised[2].score`.
static func validate(kind: String, d: Dictionary) -> Array[String]:
	var errs: Array[String] = []
	if not KINDS.has(kind):
		errs.append("unknown_kind")
		return errs
	if not has_v2(d):
		errs.append("unknown_v")
		return errs
	match kind:
		"raid":
			_check(d, _RAID, "", errs)
			_raid_extras(d, errs)
		"boss":
			_check(d, _BOSS, "", errs)
			_boss_extras(d, errs)
		"town", "map":
			_check(d, _TELEPORT, "", errs)
		"raid_seed":
			_check(d, _RAID_SEED, "", errs)
			_seed_kind(d, "raid", errs)
		"boss_seed":
			_check(d, _BOSS_SEED, "", errs)
			_seed_kind(d, "boss", errs)
	return errs


## True when `d.v` is 2 (an integral float 2.0 counts, after JSON).
static func has_v2(d: Dictionary) -> bool:
	return d.has("v") and is_int_like(d["v"]) and int(d["v"]) == 2


## An int, or a finite float with an integral value.
static func is_int_like(v: Variant) -> bool:
	if typeof(v) == TYPE_INT:
		return true
	return typeof(v) == TYPE_FLOAT and is_finite(v) and v == floorf(v)


static func _is_number(v: Variant) -> bool:
	return typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT


static func _join(path: String, key: String) -> String:
	return key if path == "" else path + "." + key


static func _check(v: Variant, spec: Variant, path: String, errs: Array[String]) -> void:
	if spec is String:
		_leaf(v, spec, path, errs)
	elif spec is Array:
		if typeof(v) != TYPE_ARRAY:
			errs.append("type:" + path)
			return
		for i in v.size():
			_check(v[i], spec[0], "%s[%d]" % [path, i], errs)
	else:
		if typeof(v) != TYPE_DICTIONARY:
			errs.append("type:" + path)
			return
		for k in spec:
			var p := _join(path, k)
			if not v.has(k):
				errs.append("missing:" + p)
			else:
				_check(v[k], spec[k], p, errs)


static func _leaf(v: Variant, tok: String, path: String, errs: Array[String]) -> void:
	match tok:
		"str":
			if typeof(v) != TYPE_STRING:
				errs.append("type:" + path)
		"bool":
			if typeof(v) != TYPE_BOOL:
				errs.append("type:" + path)
		"dict":
			if typeof(v) != TYPE_DICTIONARY:
				errs.append("type:" + path)
		"int", "int+", "score":
			if not _is_number(v):
				errs.append("type:" + path)
			elif typeof(v) == TYPE_FLOAT and not is_finite(v):
				errs.append("range:" + path)
			elif not is_int_like(v):
				errs.append("type:" + path)
			elif tok == "int+" and v < 0:
				errs.append("range:" + path)
			elif tok == "score" and (v < 0 or v > 100):
				errs.append("range:" + path)
		"float", "mass":
			if not _is_number(v):
				errs.append("type:" + path)
			elif typeof(v) == TYPE_FLOAT and not is_finite(v):
				errs.append("range:" + path)
			elif tok == "mass" and v < 0:
				errs.append("range:" + path)
		"aspect", "rarity", "front":
			if typeof(v) != TYPE_STRING:
				errs.append("type:" + path)
			else:
				var list: Array = GameState.STATS if tok == "aspect" \
					else (GameState.RARITIES if tok == "rarity" else GameState.FRONT_IDS)
				if not list.has(v):
					errs.append("range:" + path)


## Appends `duplicate:<path>[i]` for each repeat of a String in `d[key]`.
static func _dups(d: Dictionary, key: String, errs: Array[String]) -> void:
	var a: Variant = d.get(key)
	if typeof(a) != TYPE_ARRAY:
		return
	var seen := {}
	for i in a.size():
		if typeof(a[i]) != TYPE_STRING:
			continue
		if seen.has(a[i]):
			errs.append("duplicate:%s[%d]" % [key, i])
		seen[a[i]] = true


static func _raid_extras(d: Dictionary, errs: Array[String]) -> void:
	_dups(d, "party_lost", errs)
	var n := 0
	for k in ["warden_beaten", "retreated", "relish_died"]:
		if typeof(d.get(k)) != TYPE_BOOL:
			return  # the type error is already reported
		if d[k]:
			n += 1
	if n != 1:
		errs.append("bad_exit")


static func _boss_extras(d: Dictionary, errs: Array[String]) -> void:
	_dups(d, "fronts_cleared", errs)
	_dups(d, "party_lost", errs)
	var bs: Variant = d.get("backups_spent")
	if typeof(d.get("won")) != TYPE_BOOL or typeof(bs) != TYPE_DICTIONARY:
		return
	var vals: Array = [d.get("relish_deaths"), bs.get("phylactery"), bs.get("clones")]
	for x in vals:
		if not is_int_like(x) or x < 0:
			return  # the type or range error is already reported
	var s := int(vals[1]) + int(vals[2])
	var deaths := int(vals[0])
	var good := deaths == s if d["won"] else (deaths == s or deaths == s + 1)
	if not good:
		errs.append("bad_deaths")


static func _seed_kind(d: Dictionary, want: String, errs: Array[String]) -> void:
	if typeof(d.get("kind")) == TYPE_STRING and d["kind"] != want:
		errs.append("range:kind")


# ------------------------------------------------------------ v1 -> v2 (§8.5) ----
static func _num(d: Dictionary, key: String) -> float:
	var v: Variant = d.get(key, 0.0)
	return float(v) if _is_number(v) else 0.0


## Converts a v1 result of `kind` ("raid" or "boss") into v2, using the open run's seed for
## `run_id`, `seed_rev` and the garrison baseline. Another kind gives {}.
static func from_v1(kind: String, v1: Dictionary, seed: Dictionary) -> Dictionary:
	match kind:
		"raid":
			return _raid_from_v1(v1, seed)
		"boss":
			return _boss_from_v1(v1, seed)
	return {}


static func _raid_from_v1(v1: Dictionary, seed: Dictionary) -> Dictionary:
	var div := float(seed.get("garrison_mass_div", 10.0))
	if div <= 0.0:
		div = 10.0
	var s := int(_num(v1, "raised_soldiers"))
	var e := int(_num(v1, "raised_elites"))
	var g := _num(v1, "good_mass")
	var chaff := _num(v1, "raised_chaff_mass")
	var garrison := _num(v1, "garrison_mass")
	var raised: Array = []
	var soldier_mass := 0.0
	var elite_mass := 0.0
	if s + e > 0:
		soldier_mass = g * float(s) / float(s + e)
		elite_mass = g * float(e) / float(s + e)
	else:
		soldier_mass = g  # no counts to split by: all of it in the soldier bucket
	_bucket(raised, 75, s, soldier_mass)
	_bucket(raised, 95, e, elite_mass)
	_bucket(raised, 50, roundi((chaff + garrison) / div), chaff + garrison)
	var died := bool(v1.get("relish_died", false))
	var fort: Dictionary = seed.get("fort", {})
	return {
		"v": 2, "run_id": int(seed.get("run_id", -1)), "seed_rev": int(seed.get("seed_rev", -1)),
		"fort_id": str(v1.get("fort_id", fort.get("id", ""))),
		"warden_beaten": false, "retreated": not died, "relish_died": died,
		"revived_in_place": 0,
		"killed_living_mass": _num(v1, "killed_living_mass"),
		"raised": raised,
		"chaff_mass": chaff,
		"garrison_mass": float(seed.get("garrison_in_mass", 0.0)) + garrison + g,
		"party_lost": [],
		"loot": {"relics": 0, "blueprints": [], "husks": [], "remnants": [], "essence": 0},
	}


## Adds a raised bucket unless it is empty (count 0 and mass 0).
static func _bucket(out: Array, score: int, count: int, mass: float) -> void:
	if count == 0 and mass == 0.0:
		return
	out.append({"score": score, "count": count, "mass": mass})


static func _boss_from_v1(v1: Dictionary, seed: Dictionary) -> Dictionary:
	var won := bool(v1.get("won", false))
	var died := bool(v1.get("relish_died", false))
	return {
		"v": 2, "run_id": int(seed.get("run_id", -1)), "seed_rev": int(seed.get("seed_rev", -1)),
		"won": won, "fronts_cleared": [], "relish_deaths": 1 if died and not won else 0,
		"backups_spent": {"phylactery": 0, "clones": 0}, "party_lost": [],
		"backlog_spent": _num(v1, "backlog_spent"),
	}
