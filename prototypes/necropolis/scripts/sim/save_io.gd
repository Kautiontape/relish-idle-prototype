class_name SaveIO
extends RefCounted
## Save-file plumbing, static only: the save spec and its checker, float canonicalisation, the
## migrate steps, the shape-and-ids check, slot validation, atomic write, reading a save file,
## the list_saves scan and the config loader. GameState owns what goes in a save and forwards here.

# The save spec: TYPE_FLOAT = any finite number, TYPE_INT = an integral number (JSON has one
# number type, so a loaded int arrives as a float and is restored with int()), [spec] = an
# Array of spec, {"*": spec} = a map, {key: spec} = a Dictionary holding at least those keys.
const _I := TYPE_INT
const _F := TYPE_FLOAT
const _S := TYPE_STRING
const _B := TYPE_BOOL
const _D := TYPE_DICTIONARY
const _VALVE_SPEC := {"work": _F, "war": _F, "flood": _F}
const SAVE_SPEC := {
	"v": _I, "api_version": _I, "seed": _S, "rng": _S, "t": _F, "acc": _F,
	"next_run_id": _I, "next_uid": _I, "applied_runs": [_I],
	"relish": {"state": _S, "at": _S, "target": _S, "pos": [_F], "heading": _F, "dead_s_left": _F, "respawn_with_clone": _B},
	"valve": {"target": _VALVE_SPEC, "current": _VALVE_SPEC},
	"realm": {
		"forts": [{"id": _S, "living": _F, "undead": _F, "dead": _F, "held_s": _F, "flipped_count": _I,
			"clears_since_retaken": _I, "r_in": _F, "r_drain": _F, "r_shipped": _F, "r_dead_out": _F, "r_raised": _F}],
		"cov": {"undead": _F, "r_out": _F},
		"vei": {"undead_queue": _F, "dead_queue": _F, "living_pool": _F, "r_in_undead": _F, "r_in_dead": _F,
			"r_converted": _F, "r_shipped": _F},
		"simulacra": [{"fort_id": _S, "charges": _F, "rate": _F}],
		"elapsed": _F, "cleared_total": _F, "raised_by_sims": _F, "tithe": _D,
	},
	"villages": [{"id": _S, "owner": _S}],
	# TownSim.to_dict() plus GameState's tier, haul.target and work_pending. TownSim's morale, shock,
	# rates and pending are written too but optional (a migrated v1 save has none): _town_problem
	# checks their types when present, and TownSim.from_dict defaults them.
	"town": {
		"tier": _S, "work_pending": _F, "workers": _F, "bodies": _F, "gold": _F, "bone": _F, "living": _F,
		"buildings": [{"lot_id": _S, "building_id": _S, "level": _I, "state": _S, "progress": _F, "staff_cap": _I,
			"unpaid_s": _F, "build_level": _I}],
		"ladder": [_S],
		"haul": {"target": _S, "current": _S, "convoys": [{"fort": _S, "phase": _S, "t": _F, "trip_s": _F, "load": _F, "crew": _F}]},
		"forge": {"level": _I, "progress": _F},
	},
	"stances": {"on": [_S], "hold": {"*": _F}},
	"inventory": {
		"husks": [{"uid": _S, "kind": _S, "rarity": _S}],
		"remnants": [{"uid": _S, "aspect": _S, "rarity": _S, "magnitude": _I}],
		"blueprints": [_S], "relics": _I, "essence": _I, "simulacra_ready": _I,
	},
	"big_undead": [{"uid": _S, "name": _S, "kind": _S, "role": _S, "place": _S, "front": _S,
		"stats": {"power": _F, "beef": _F, "wits": _F, "presence": _F, "speed": _F}}],
	"party": [_S],
	"backups": {"phylactery_charges": _I, "clones_ready": _I, "vats": [{"slot": _I, "staffed": _B, "grow": _F}]},
	"readout": {"diff_ema": _F, "q_raise_ema": _F},
	"ledger": {"sources": {"*": _F}, "sinks": {"dungeon": _F}},
	"won": _B,
	"stats": {"raised_total": _F, "raids": _I, "deaths": _I, "sims_built": _I},
	"cleared_forts": [_S], "first_dungeon": _S,
}
## TownSim's optional town keys (see SAVE_SPEC's town).
const _TOWN_OPTIONAL := {"morale": _F, "shock": _F, "rates": _D, "pending": [_D]}
const _BUILDING_STATES := ["constructing", "active", "idle", "unpaid"]
## A v1 (E1) save's town and legacy blocks, as migrate reads them.
const _V1_TOWN := {"tier": _S, "lots": [{"lot_id": _S, "building_id": _S, "level": _I}], "ladder": [_S],
	"staff_caps": {"*": _I}, "haul": {"target": _S}}
const _V1_LEGACY := {
	"res": {"gold": _F, "materials": _F, "bodies": _F, "townsfolk": _F},
	"town": {"vats": _I, "forge_level": _I},
	"assignments": {"*": _I}, "idle_undead": _I,
}


## True if `v` fits `spec` (see SAVE_SPEC).
static func fits(v: Variant, spec: Variant) -> bool:
	if typeof(spec) == TYPE_INT:
		var ty := typeof(v)
		match spec:
			TYPE_FLOAT:
				return (ty == TYPE_INT or ty == TYPE_FLOAT) and is_finite(float(v))
			TYPE_INT:
				return ty == TYPE_INT or (ty == TYPE_FLOAT and is_finite(v) and absf(v) < 9.0e15 and v == floorf(v))
			_:
				return ty == spec
	if spec is Array:
		if typeof(v) != TYPE_ARRAY:
			return false
		for e in v:
			if not fits(e, spec[0]):
				return false
		return true
	if typeof(v) != TYPE_DICTIONARY:
		return false
	if spec.has("*"):
		for k in v:
			if typeof(k) != TYPE_STRING or not fits(v[k], spec["*"]):
				return false
		return true
	for k in spec:
		if not v.has(k) or not fits(v[k], spec[k]):
			return false
	return true


## Every float in `v` as JSON writes it (15 significant digits), so that to_dict, its JSON text
## and a load of that text all agree to the last bit. Godot's JSON parser is not exact for
## 17-digit floats. A non-finite float becomes 0.0 (the state never holds one).
static func canon(v: Variant) -> Variant:
	match typeof(v):
		TYPE_FLOAT:
			return float(JSON.parse_string(JSON.stringify(v))) if is_finite(v) else 0.0
		TYPE_ARRAY:
			for i in v.size():
				v[i] = canon(v[i])
		TYPE_DICTIONARY:
			for k in v:
				v[k] = canon(v[k])
	return v


## §9.1 `GameState.migrate`: one version at a time up to `latest` (GameState.SAVE_VERSION). `{}` on
## failure (no `v`, a `v` that is not a whole number from 1 up, a version from the future, or a
## missing step). At `latest` it returns a deep copy.
static func migrate(d: Dictionary, latest: int) -> Dictionary:
	if not d.has("v") or not fits(d["v"], _I):
		return {}
	var v := int(d["v"])
	if v < 1 or v > latest:
		return {}
	var out := d.duplicate(true)
	while v < latest:
		match v:
			1:
				out = _migrate_1_to_2(out)
			_:
				return {}
		v += 1
	out["v"] = v
	return out


## v1 (E1) → v2 (E2a, TownSim). The `legacy` block's stocks become the town block's: gold, bone
## (materials), bodies, living (townsfolk), workers (idle_undead + every assignment); its forge level
## becomes TownSim's, and its vats backups.clones_ready. v1's town.lots (the BALANCE §0 start set,
## which nothing at E1 changed) become working buildings with their staff caps. The legacy army,
## assignments and convoy are dropped; morale, shock and the rates start fresh at the load. A v1
## save whose town or legacy block is malformed is left as is, so the v2 check calls it corrupt.
static func _migrate_1_to_2(d: Dictionary) -> Dictionary:
	if not fits(d.get("town"), _V1_TOWN) or not fits(d.get("legacy"), _V1_LEGACY) or not (d.get("backups") is Dictionary):
		return d
	var tn: Dictionary = d["town"]
	var lg: Dictionary = d["legacy"]
	var buildings: Array = []
	for l in tn["lots"]:
		var lot_id: String = l["lot_id"]
		buildings.append({"lot_id": lot_id, "building_id": l["building_id"], "level": int(l["level"]), "state": "active",
			"progress": 1.0, "staff_cap": int(tn["staff_caps"].get(lot_id, -1)), "unpaid_s": 0.0, "build_level": int(l["level"])})
	var workers := float(lg["idle_undead"])
	for k in lg["assignments"]:
		workers += float(lg["assignments"][k])
	var res: Dictionary = lg["res"]
	d["town"] = {
		"tier": tn["tier"], "work_pending": 0.0, "workers": maxf(0.0, workers),
		"bodies": float(res["bodies"]), "gold": float(res["gold"]), "bone": float(res["materials"]), "living": float(res["townsfolk"]),
		"buildings": buildings, "ladder": (tn["ladder"] as Array).duplicate(),
		"haul": {"target": tn["haul"]["target"], "current": "", "convoys": []},
		"forge": {"level": int(lg["town"]["forge_level"]), "progress": 0.0},
	}
	d["backups"]["clones_ready"] = maxi(0, int(lg["town"]["vats"]))
	d.erase("legacy")
	return d


## "" if the migrated save `m` is sound, else why not. The shape first, then every id it names
## (`cfgs` is the GameState configs dict).
static func problem(m: Dictionary, cfgs: Dictionary) -> String:
	if not fits(m, SAVE_SPEC):
		return "shape"
	if not (m["seed"] as String).is_valid_int() or not (m["rng"] as String).is_valid_int():
		return "seed"
	var world: Dictionary = cfgs.get("world", {})
	var fort_ids := {}
	for f in world.get("forts", []):
		fort_ids[str(f.get("id", ""))] = true
	var nodes := fort_ids.duplicate()
	nodes["covington"] = true
	nodes["vei"] = true
	var rl: Dictionary = m["relish"]
	if not GameState.RELISH_STATES.has(rl["state"]) or rl["state"] == "in_dungeon" or rl["state"] == "in_boss":
		return "relish state"
	if not nodes.has(rl["at"]) or (rl["target"] != "" and not nodes.has(rl["target"])) or (rl["pos"] as Array).size() != 2:
		return "relish node"
	if rl["state"] == "travelling" and rl["target"] == "":
		return "relish target"
	var seen := {}
	for f in m["realm"]["forts"]:
		if not fort_ids.has(f["id"]) or seen.has(f["id"]):
			return "fort id"
		seen[f["id"]] = true
	if seen.size() != fort_ids.size():
		return "fort set"
	for s in m["realm"]["simulacra"]:
		if not fort_ids.has(s["fort_id"]):
			return "simulacrum fort"
	for k in ["warning", "wave"]:  # realm.tithe is free-form (E1 placeholders); its forts are not
		var e: Variant = m["realm"]["tithe"].get(k, {})
		if e is Dictionary and e.has("fort_id") and not fort_ids.has(str(e["fort_id"])):
			return "tithe fort"
	for v in m["villages"]:
		if not ["player", "vei", "none"].has(v["owner"]):
			return "village owner"
	var town_why := _town_problem(m["town"], cfgs, fort_ids)
	if town_why != "":
		return town_why
	var on := {}
	for st in m["stances"]["on"]:
		if not GameState.STANCE_IDS.has(st) or on.has(st):
			return "stance"
		on[st] = true
	var uids := {}
	for h in m["inventory"]["husks"]:
		if uids.has(h["uid"]):
			return "uid"
		uids[h["uid"]] = true
	for r in m["inventory"]["remnants"]:
		if uids.has(r["uid"]):
			return "uid"
		uids[r["uid"]] = true
	var bu_uids := {}
	for b in m["big_undead"]:
		if uids.has(b["uid"]) or bu_uids.has(b["uid"]) or (b["front"] != "" and not GameState.FRONT_IDS.has(b["front"])):
			return "big undead"
		bu_uids[b["uid"]] = true
	seen = {}
	for u in m["party"]:
		if not bu_uids.has(u) or seen.has(u):
			return "party"
		seen[u] = true
	for id in m["cleared_forts"]:
		if not fort_ids.has(id):
			return "cleared fort"
	return ""


## "" if the town block `tn` (it already fits SAVE_SPEC) is sound: a known tier; buildings on known,
## distinct lots, of known ids, in a known state, at a level the building has; the ladder a
## permutation of JOB_IDS; the haul target, its current fort and at most one convoy naming known
## forts; TownSim's optional keys of the right type.
static func _town_problem(tn: Dictionary, cfgs: Dictionary, fort_ids: Dictionary) -> String:
	if not GameState.TIERS.has(tn["tier"]):
		return "tier"
	var lots_cfg: Variant = cfgs.get("town", {}).get("lots", [])
	var bcfg: Variant = cfgs.get("buildings", {})
	if not (bcfg is Dictionary):
		bcfg = {}
	var lot_ids := {}
	for l in (lots_cfg if lots_cfg is Array else []):
		lot_ids[str(l.get("id", ""))] = true
	var seen := {}
	for b in tn["buildings"]:
		if not lot_ids.has(b["lot_id"]) or seen.has(b["lot_id"]) or not bcfg.has(b["building_id"]):
			return "lot"
		seen[b["lot_id"]] = true
		var top := int(bcfg[b["building_id"]].get("max_level", 1))
		if not _BUILDING_STATES.has(b["state"]) or int(b["level"]) < 0 or int(b["level"]) > top \
				or int(b["build_level"]) < 1 or int(b["build_level"]) > top:
			return "building"
	var jobs := {}
	for j in tn["ladder"]:
		if not GameState.JOB_IDS.has(j) or jobs.has(j):
			return "ladder"
		jobs[j] = true
	if jobs.size() != GameState.JOB_IDS.size():
		return "ladder"
	var haul: Dictionary = tn["haul"]
	if haul["target"] != "auto" and not fort_ids.has(haul["target"]):
		return "haul target"
	if (haul["current"] != "" and not fort_ids.has(haul["current"])) or haul["convoys"].size() > 1:
		return "haul"
	for c in haul["convoys"]:
		if not fort_ids.has(c["fort"]) or not ["out", "back"].has(c["phase"]):
			return "convoy"
	for k in _TOWN_OPTIONAL:
		if tn.has(k) and not fits(tn[k], _TOWN_OPTIONAL[k]):
			return "town " + k
	return ""


## `^[a-z0-9_-]{1,32}$`, checked by hand (a regex `$` would let a trailing newline through).
static func slot_ok(slot: String) -> bool:
	if slot.length() < 1 or slot.length() > 32:
		return false
	for i in slot.length():
		var c := slot.unicode_at(i)
		if not ((c >= 97 and c <= 122) or (c >= 48 and c <= 57) or c == 95 or c == 45):
			return false
	return true


## Writes `text` to `path` by way of `<path>.tmp` and a rename (§9.3). False on any failure.
static func write_atomic(path: String, text: String) -> bool:
	var dir := path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir) and DirAccess.make_dir_recursive_absolute(dir) != OK:
		return false
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(text)
	var err := f.get_error()
	f.close()
	if err != OK or DirAccess.rename_absolute(tmp, path) != OK:
		DirAccess.remove_absolute(tmp)
		return false
	return true


## A save file as a Dictionary holding `v`, else {} (missing, unreadable, not JSON, not a
## Dictionary, no `v`): every one of those is "no save", never an error (§9.3).
static func read_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var j := JSON.new()
	if j.parse(FileAccess.get_file_as_string(path)) != OK:
		return {}
	if typeof(j.data) != TYPE_DICTIONARY or not (j.data as Dictionary).has("v"):
		return {}
	return j.data


## §4.1: `[{slot, saved_at, summary}]` of the saves in `save_dir`, newest first (ties by slot).
static func list_saves(save_dir: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not DirAccess.dir_exists_absolute(save_dir):
		return out
	for fname in DirAccess.get_files_at(save_dir):
		if not fname.ends_with(".json"):
			continue
		var slot := fname.trim_suffix(".json")
		if not slot_ok(slot):
			continue
		var d := read_file("%s/%s" % [save_dir, fname])
		if d.is_empty():
			continue
		var at: Variant = d.get("saved_at", 0)
		out.append({"slot": slot, "saved_at": int(at) if fits(at, _I) else 0, "summary": str(d.get("summary", ""))})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a["slot"] < b["slot"] if a["saved_at"] == b["saved_at"] else a["saved_at"] > b["saved_at"])
	return out


## Recursively loads every *.json under `dir` into a Dictionary keyed by the
## filename without extension. Directories starting with "." are skipped.
## Files are walked in sorted order so the result is deterministic. On a
## basename collision the first file wins and an error names both paths.
## A file that fails to parse is reported and skipped. A missing dir is {}.
## Each duplicate or parse failure also appends one string to `errors`, so
## callers (the test suite) can fail on them.
static func load_configs(dir: String, errors: Array = []) -> Dictionary:
	var out := {}
	var paths := {}
	_load_into(dir, out, paths, errors)
	return out


static func _load_into(dir: String, out: Dictionary, paths: Dictionary, errors: Array) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	d.include_hidden = true  # so the "." guards below, not the OS filter, skip dot entries
	var files := Array(d.get_files())
	files.sort()
	for f: String in files:
		if f.begins_with(".") or not f.ends_with(".json"):
			continue
		var p := dir.path_join(f)
		var key := f.trim_suffix(".json")
		if out.has(key):
			var msg := "duplicate config '%s': keeping %s, ignoring %s" % [key, paths[key], p]
			errors.append(msg)
			push_error("GameState.load_configs: " + msg)
			continue
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(p))
		if parsed == null:
			errors.append("failed to parse %s" % p)
			push_error("GameState.load_configs: failed to parse %s" % p)
			continue
		out[key] = parsed
		paths[key] = p
	var subs := Array(d.get_directories())
	subs.sort()
	for s: String in subs:
		if not s.begins_with("."):
			_load_into(dir.path_join(s), out, paths, errors)
