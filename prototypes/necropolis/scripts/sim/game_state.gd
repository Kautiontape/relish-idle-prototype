class_name GameState
extends RefCounted
## All game state and logic, headless. The Game autoload is a thin shell over one
## of these. Configs are injected through setup(); randomness comes from `rng`.
## Files in scripts/sim/ never reference an autoload or Engine (a lint test
## enforces this). No signals: consumers poll
## `rev` and drain_events(). The contract is docs/STATE-API.md.

const API_VERSION := 1
const SAVE_VERSION := 1
const RELISH_STATES := ["home", "travelling", "at_fort", "at_vei", "in_dungeon", "in_boss", "dead"]
const RATE_IDS := ["mint", "work", "war", "flood", "workers", "bodies", "gold", "bone", "living", "corpses", "backlog"]
const HUD_RATE_IDS := ["mint", "workers", "bodies", "gold", "bone", "living"]
const LANE_KINDS := ["war", "flood", "work", "dead", "living", "haul", "redirect"]
const JOB_IDS := ["haul", "mill", "stall", "forge", "pit", "tend", "build"]
const STANCE_IDS := ["vigil", "harvest", "thrift", "muster", "hearth"]
const FRONT_IDS := ["giants", "swarm", "carvers", "raw"]
const CRAFT_IDS := ["simulacrum", "phylactery_charge"]
const TIERS := ["hamlet", "village", "town", "city"]
const STATS := ["power", "beef", "wits", "presence", "speed"]
const RARITIES := ["common", "uncommon", "rare", "legendary"]
const WARDEN_ARCHETYPES := ["bellringer", "huntsman", "shieldwall", "pyre_priest"]
const FIXTURES := ["day1", "midgame_2flips", "pre_vei"]
const DEBUG_GRANT_KEYS := ["gold", "bone", "bodies", "relics", "essence", "workers", "living", "backlog", "husks", "remnants", "big_undead"]
const DEBUG_STATE_KEYS := ["time_scale", "paused", "relish_at", "valve", "forge_level", "won", "forts"]
## Husk kinds (loot), STATE-API §1.4.
const HUSK_KINDS := ["skeleton", "zombie", "hulk", "siren", "lich", "wraith", "revenant"]

var realm: RealmSim
var field: InfluenceField
var time_scale := 1.0
var paused := false
var t := 0.0  # sim seconds since the new game
var debug_enabled := false
var rng := RandomNumberGenerator.new()
var rng_seed := ""  # String: 64-bit seeds do not survive JSON numbers
var rev := 0  # +1 per substep and per successful command

# --- Relish (owned here; realm.relish is a legacy mirror, see _sync_realm_relish) ---
var relish := {}
# --- runs and seeds (§4.5, §7) ---
var run := {}  # {} or {run_id, kind: "raid"|"boss", fort_id, seed_rev, seed}
var next_run_id := 1
var next_uid := 1  # one counter for h<n>, r<n>, u<n>
var game_seed := 0
var first_dungeon_id := ""  # "" once a raid result has cleared it (T1.4)
var cleared_forts := {}  # fort_id -> true once its first clear is spent (T1.4)
# --- E1 stocks and inventories (T1.3b builds the views on these) ---
var relics := 0
var essence := 0
var husks: Array = []
var remnants: Array = []
var big_undead: Array = []
var party_uids: Array = []
var valve := {"work": 0.40, "war": 0.45, "flood": 0.15}
var valve_target := {"work": 0.40, "war": 0.45, "flood": 0.15}

# --- Relish's holdings (legacy stores) ---
var army := {"soldier": 0, "elite": 0}
var res := {"gold": 30.0, "materials": 12.0, "bodies": 0.0, "townsfolk": 10.0}
var town := {"slabs": 1, "vats": 0, "sim_stations": 0, "forge_level": 0, "trade_level": 0}
var assignments := {"trade": 0, "forge": 0, "jobs": 0, "gather": 0, "slab": 0}
var idle_undead := 6  # unassigned workers in Covington
var gather := {"target": "", "phase": "idle", "eta": 0.0, "load": 0.0}
var towns: Array = []
var green_towns := 0
var won := false
var stats := {"raised_total": 0.0, "raids": 0, "deaths": 0, "sims_built": 0}

var _cfgs := {}
var _acc := 0.0
var _field_acc := 0.0
var _raiding_fort := ""  # legacy begin_raid/end_raid flag (the router still uses it)
var _events: Array = []


## `configs` is keyed by file basename; a non-empty dict calls setup().
func _init(configs: Dictionary = {}) -> void:
	if not configs.is_empty():
		setup(configs)


## `cfgs` is the dict returned by load_configs (keyed by file name).
func setup(cfgs: Dictionary) -> void:
	_cfgs = cfgs


func _cfg() -> Dictionary:
	return _cfgs.get("realm", {})


func _sec(file: String, section: String) -> Dictionary:
	var d: Variant = _cfgs.get(file, {}).get(section, {})
	return d if d is Dictionary else {}


func substep_s() -> float:
	return float(_cfgs.get("economy", {}).get("sim", {}).get("substep_s", 0.5))


func max_substeps_per_frame() -> int:
	return int(_cfgs.get("economy", {}).get("sim", {}).get("max_substeps_per_frame", 16))


func travel_speed() -> float:
	return float(_cfg().get("relish", {}).get("travel_speed", 220.0))


func drain_events() -> Array:
	var out := _events
	_events = []
	return out


func _emit(ev: Dictionary) -> void:
	ev["t"] = t
	_events.append(ev)


# ------------------------------------------------------------------ game -----
func cmd_new_game(seed: int) -> Dictionary:
	if not run.is_empty():
		return {"ok": false, "reason": "busy"}
	rng.seed = seed
	rng_seed = str(seed)
	game_seed = seed
	var cfg: Dictionary = _cfg()
	var world: Dictionary = _cfgs.get("world", {})
	var opening: Dictionary = _sec("economy", "opening")
	realm = RealmSim.new()
	realm.setup(world, cfg)
	realm.send_relish("covington")
	field = InfluenceField.new()
	field.setup(cfg.get("field", {}), RealmSim._vec(world.get("size", [2048, 1440])))
	towns = []
	for tw in world.get("towns", []):
		towns.append({
			"id": tw.get("id", ""), "name": tw.get("name", "?"),
			"pos": RealmSim._vec(tw.get("pos", [0, 0])),
			"pop": float(tw.get("pop", 30)), "control": "none",
		})
	# legacy stores back to the start state (the object is reset in place)
	army = {"soldier": 0, "elite": 0}
	res = {"gold": 30.0, "materials": 12.0, "bodies": 0.0, "townsfolk": 10.0}
	town = {"slabs": 1, "vats": 0, "sim_stations": 0, "forge_level": 0, "trade_level": 0}
	assignments = {"trade": 0, "forge": 0, "jobs": 0, "gather": 0, "slab": 0}
	idle_undead = 6
	gather = {"target": "", "phase": "idle", "eta": 0.0, "load": 0.0}
	green_towns = 0
	won = false
	stats = {"raised_total": 0.0, "raids": 0, "deaths": 0, "sims_built": 0}
	_acc = 0.0
	_field_acc = 0.0
	_raiding_fort = ""
	_events = []
	t = 0.0
	time_scale = 1.0
	paused = false
	run = {}
	relics = 0
	essence = 0
	husks = []
	remnants = []
	big_undead = []
	party_uids = []
	var v: Dictionary = opening.get("valve", {"work": 0.40, "war": 0.45, "flood": 0.15})
	valve = _normalised(float(v.get("work", 0.4)), float(v.get("war", 0.45)), float(v.get("flood", 0.15)))
	valve_target = valve.duplicate()
	first_dungeon_id = str(opening.get("first_dungeon", "old-sluice"))
	cleared_forts = {}
	relish = {
		"state": "home", "at": "covington", "target": "",
		"pos": [float(realm.cov_pos.x), float(realm.cov_pos.y)], "heading": 0.0,
		"dead_s_left": 0.0, "respawn_with_clone": false,
	}
	_sync_realm_relish()
	# pre-warm the field so the map doesn't start blank
	for i in 90:
		_inject_sources(0.2)
		field.tick(0.2)
	rev += 1
	return {"ok": true, "reason": ""}


func cmd_set_time_scale(x: float) -> Dictionary:
	if relish["state"] == "in_dungeon":
		return {"ok": false, "reason": "in_dungeon", "time_scale": time_scale}
	if relish["state"] == "in_boss":
		return {"ok": false, "reason": "in_boss", "time_scale": time_scale}
	if not (x == 1.0 or x == 2.0 or x == 4.0):
		return {"ok": false, "reason": "invalid_scale", "time_scale": time_scale}
	time_scale = x
	rev += 1
	return {"ok": true, "reason": "", "time_scale": time_scale}


func cmd_pause(b: bool) -> Dictionary:
	paused = b
	rev += 1
	return {"ok": true, "reason": "", "paused": paused}


static func _normalised(w: float, a: float, f: float) -> Dictionary:
	var s := w + a + f
	return {"work": w / s, "war": a / s, "flood": f / s}


# ----------------------------------------------------------------- relish ----
func _node_valid(id: String) -> bool:
	return id == "covington" or id == "vei" or not realm.fort_by_id(id).is_empty()


func _node_xy(id: String) -> Array:
	var p: Vector2 = realm.node_pos(id)
	return [float(p.x), float(p.y)]


func _state_at_node(id: String) -> String:
	if id == "covington":
		return "home"
	return "at_vei" if id == "vei" else "at_fort"


## Distance from her pos to a node, in doubles.
func _dist_to(id: String) -> float:
	var p: Array = relish["pos"]
	var q := _node_xy(id)
	return sqrt(pow(q[0] - p[0], 2.0) + pow(q[1] - p[1], 2.0))


func _face(id: String) -> void:
	var p: Array = relish["pos"]
	var q := _node_xy(id)
	if absf(q[0] - p[0]) > 1e-9 or absf(q[1] - p[1]) > 1e-9:
		relish["heading"] = atan2(q[1] - p[1], q[0] - p[0])


func _eta() -> float:
	if relish["state"] != "travelling":
		return -1.0
	return _dist_to(relish["target"]) / travel_speed()


func _move_refusal(node_id: String) -> String:
	match relish["state"]:
		"dead":
			return "dead"
		"in_dungeon":
			return "in_dungeon"
		"in_boss":
			return "in_boss"
	return "" if _node_valid(node_id) else "unknown_node"


func _begin_travel(node_id: String) -> void:
	relish["state"] = "travelling"
	relish["target"] = node_id
	_face(node_id)
	_sync_realm_relish()


func cmd_move_relish(node_id: String) -> Dictionary:
	var why := _move_refusal(node_id)
	if why != "":
		return {"ok": false, "reason": why, "eta_s": 0.0}
	if relish["state"] == "travelling":
		if relish["target"] != node_id:
			_begin_travel(node_id)
	elif relish["at"] != node_id:
		_begin_travel(node_id)
	rev += 1
	return {"ok": true, "reason": "", "eta_s": maxf(0.0, _eta())}


func cmd_cancel_travel() -> Dictionary:
	if relish["state"] != "travelling":
		return {"ok": false, "reason": "not_travelling", "eta_s": 0.0}
	if relish["target"] != relish["at"]:
		_begin_travel(relish["at"])
	rev += 1
	return {"ok": true, "reason": "", "eta_s": maxf(0.0, _eta())}


## NOT contract (§2.2): puts her, alive, at a node at once. For the legacy TELEPORT.
func legacy_teleport_relish(node_id: String) -> Dictionary:
	var why := _move_refusal(node_id)
	if why != "":
		return {"ok": false, "reason": why}
	_place_relish(node_id)
	rev += 1
	return {"ok": true, "reason": ""}


func _place_relish(node_id: String) -> void:
	relish["state"] = _state_at_node(node_id)
	relish["at"] = node_id
	relish["target"] = ""
	relish["pos"] = _node_xy(node_id)
	relish["dead_s_left"] = 0.0
	relish["respawn_with_clone"] = false
	_sync_realm_relish()


## Substep step 4 (§3): straight-line travel and arrival.
func _step_relish_travel(dt: float) -> void:
	if relish["state"] != "travelling":
		return
	var tgt: String = relish["target"]
	var dist := _dist_to(tgt)
	var step := travel_speed() * dt
	if step >= dist - 1e-9:
		relish["pos"] = _node_xy(tgt)
		relish["state"] = _state_at_node(tgt)
		relish["at"] = tgt
		relish["target"] = ""
		_sync_realm_relish()
		return
	_face(tgt)
	var p: Array = relish["pos"]
	var q := _node_xy(tgt)
	var f := step / dist
	relish["pos"] = [p[0] + (q[0] - p[0]) * f, p[1] + (q[1] - p[1]) * f]


## E1 rule: RealmSim keeps its own relish dict and raiding flag. Home keeps the
## legacy P_relish mint; anywhere else (or dead) the legacy channel is idle (no raise
## at forts until E2); realm.raiding follows the open run (or the legacy raid flag).
func _sync_realm_relish() -> void:
	if relish["state"] == "home":
		realm.relish["at"] = "covington"
		realm.relish["state"] = "raising"
	else:
		realm.relish["at"] = relish["at"]
		realm.relish["state"] = "idle"
	realm.relish["target"] = ""
	realm.raiding = not run.is_empty() or _raiding_fort != ""


func _descend_reason(fort_id: String) -> String:
	if not run.is_empty():
		return "busy"
	if relish["state"] == "dead":
		return "dead"
	if relish["state"] != "at_fort" or relish["at"] != fort_id:
		return "not_at_fort"
	return ""


func view_relish() -> Dictionary:
	var at: String = relish["at"]
	var reason := _descend_reason(at)
	var travelling: bool = relish["state"] == "travelling"
	return {
		"rev": rev, "state": relish["state"], "at": at, "target": relish["target"],
		"pos": (relish["pos"] as Array).duplicate(), "heading": float(relish["heading"]),
		"speed": travel_speed() if travelling else 0.0, "eta_s": _eta(),
		"dead_s_left": float(relish["dead_s_left"]),
		"respawn_with_clone": bool(relish["respawn_with_clone"]),
		"phylactery_charges": 0, "clones_ready": int(town["vats"]),
		"can_descend": reason == "" and not realm.fort_by_id(at).is_empty(),
		"reason": reason,
		"run_id": int(run.get("run_id", -1)), "run_kind": str(run.get("kind", "")),
		"effects": {"tide_fort": "", "redirect_fort": "", "home": relish["state"] == "home"},
	}


# ------------------------------------------------------------------- runs ----
func _derived_rng_seed(run_id: int) -> String:
	var hi: int = hash([game_seed, run_id])
	var lo: int = hash([run_id, game_seed])
	return str((hi << 32) | lo)


func _party_entries(with_front := false) -> Array:
	var out: Array = []
	for uid in party_uids:
		for b in big_undead:
			if b["uid"] == uid:
				var e: Dictionary = {
					"uid": b["uid"], "name": b["name"], "kind": b["kind"], "role": b["role"],
					"stats": (b["stats"] as Dictionary).duplicate(),
				}
				if with_front:
					e["front"] = b["front"]
				out.append(e)
	return out


func _backups_cfg() -> Dictionary:
	return _cfgs.get("backups", {})


func _vei_readout() -> Dictionary:
	var ro: Dictionary = realm.readout()
	var diff: float = ro["differential"]
	var backlog: float = realm.vei["undead_queue"]
	return {
		"odds": float(ro["odds"]),
		"sign": 1 if diff > 1e-9 else (-1 if diff < -1e-9 else 0),
		"drain_s": backlog / -diff if diff < -1e-9 else -1.0,
	}


func _dungeon_seed(fort_id: String, run_id: int, seed_rev: int) -> Dictionary:
	var f := realm.fort_by_id(fort_id)
	var mass: Dictionary = _sec("raid", "mass")
	var div := float(mass.get("garrison_mass_div", 10.0))
	var units := clampi(int(f["undead"] / div), 0, int(mass.get("garrison_max", 12)))
	var first: bool = first_dungeon_id != "" and fort_id == first_dungeon_id
	var by_fort: Dictionary = _sec("raid", "wardens").get("by_fort", {})
	var archetype := str(by_fort.get(fort_id, "bellringer"))
	var tier := int(f["tier"])
	return {
		"v": 2, "kind": "raid", "run_id": run_id, "seed_rev": seed_rev,
		"rng_seed": _derived_rng_seed(run_id),
		"fort": {
			"id": fort_id, "name": f["name"], "tier": tier, "cap": float(f["cap"]),
			"first_clear": not cleared_forts.has(fort_id), "first_dungeon": first,
			"clears_since_retaken": 0, "yield_mult": 1.0,
		},
		"living": float(f["living"]), "dead": float(f["dead"]), "undead": float(f["undead"]),
		"garrison_units": units, "garrison_in_mass": float(units) * div,
		"starter_units": int(_sec("economy", "opening").get("starter_party", 8)) if first else 0,
		"party": _party_entries(),
		"digest_q": quality(),
		"phylactery_charges": 0,
		"phylactery_max_per_dungeon": int(_backups_cfg().get("phylactery", {}).get("max_per_dungeon", 1)),
		"clones_ready": int(town["vats"]),
		"warden": {"archetype": archetype, "tier": tier}, "warden_spec": {},
		"loot_table_id": "t%d.%s" % [tier, archetype],
		"loot_hint": "a husk and a blueprint" if first else "",
		"chest_husk": first, "watchtower": false,
		"relish_hp": float(_cfgs.get("raid", {}).get("relish", {}).get("hp", 30.0)),
	}


func _boss_seed_v2(run_id: int, seed_rev: int) -> Dictionary:
	var ro := _vei_readout()
	var fronts: Array = []
	for id in FRONT_IDS:
		fronts.append({"id": id, "need": 0.0, "have": 0.0, "assigned": []})
	return {
		"v": 2, "kind": "boss", "run_id": run_id, "seed_rev": seed_rev,
		"rng_seed": _derived_rng_seed(run_id),
		"backlog": float(realm.vei["undead_queue"]), "living_pool": float(realm.vei["living_pool"]),
		"odds": ro["odds"], "sign": ro["sign"], "drain_s": ro["drain_s"], "digest_q": quality(),
		"vei_capacity": float(_cfg().get("R_vei", 50.0)),
		"fronts": fronts,
		"fronts_required": int(_cfgs.get("vei", {}).get("fronts_required", 3)),
		"party": _party_entries(true),
		"phylactery_charges": 0, "clones_ready": int(town["vats"]),
		"relish_hp": float(_cfgs.get("raid", {}).get("relish", {}).get("hp", 30.0)),
	}


func _open_run(kind: String, fort_id: String) -> Dictionary:
	var run_id := next_run_id
	next_run_id += 1
	rev += 1
	var seed_d := _dungeon_seed(fort_id, run_id, rev) if kind == "raid" else _boss_seed_v2(run_id, rev)
	run = {"run_id": run_id, "kind": kind, "fort_id": fort_id, "seed_rev": rev, "seed": seed_d}
	relish["state"] = "in_dungeon" if kind == "raid" else "in_boss"
	time_scale = 1.0
	paused = false
	_sync_realm_relish()
	return {"ok": true, "reason": "", "seed": seed_d.duplicate(true), "run_id": run_id, "seed_rev": rev}


func cmd_begin_dungeon(fort_id: String) -> Dictionary:
	var fail := {"ok": false, "reason": "", "seed": {}, "run_id": -1, "seed_rev": -1}
	if realm.fort_by_id(fort_id).is_empty():
		fail["reason"] = "unknown_fort"
		return fail
	var why := _descend_reason(fort_id)
	if why != "":
		fail["reason"] = why
		return fail
	return _open_run("raid", fort_id)


func cmd_begin_boss() -> Dictionary:
	var fail := {"ok": false, "reason": "", "seed": {}, "run_id": -1, "seed_rev": -1}
	if not run.is_empty():
		fail["reason"] = "busy"
	elif relish["state"] == "dead":
		fail["reason"] = "dead"
	elif relish["state"] != "at_vei":
		fail["reason"] = "not_at_vei"
	if fail["reason"] != "":
		return fail
	return _open_run("boss", "vei")


func cmd_abort_dungeon() -> Dictionary:
	if run.is_empty():
		return {"ok": false, "reason": "no_run", "run_id": -1}
	var run_id: int = run["run_id"]
	relish["state"] = "at_fort" if run["kind"] == "raid" else "at_vei"
	run = {}
	_sync_realm_relish()
	rev += 1
	return {"ok": true, "reason": "", "run_id": run_id}


func view_dungeon_seed(fort_id: String) -> Dictionary:
	if run.get("kind", "") == "raid" and run["fort_id"] == fort_id:
		return (run["seed"] as Dictionary).duplicate(true)
	return {}


func view_boss_seed() -> Dictionary:
	if run.get("kind", "") == "boss":
		return (run["seed"] as Dictionary).duplicate(true)
	return {}


## The open raid's fort (or the legacy begin_raid fort), else "".
func raiding_fort_id() -> String:
	if run.get("kind", "") == "raid":
		return run["fort_id"]
	return _raiding_fort


# ------------------------------------------------------------------ debug ----
func _is_num(v: Variant) -> bool:
	return (typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT) and is_finite(float(v))


func _is_count(v: Variant) -> bool:
	return _is_num(v) and float(v) >= 0.0 and float(v) == floorf(float(v))


func _mint_uid(prefix: String) -> String:
	var uid := "%s%d" % [prefix, next_uid]
	next_uid += 1
	return uid


func _mint_husk() -> String:
	var h := {
		"uid": _mint_uid("h"), "kind": HUSK_KINDS[rng.randi_range(0, HUSK_KINDS.size() - 1)],
		"rarity": RARITIES[rng.randi_range(0, RARITIES.size() - 1)],
	}
	husks.append(h)
	return h["uid"]


func _mint_remnant() -> String:
	var r := {
		"uid": _mint_uid("r"), "aspect": STATS[rng.randi_range(0, STATS.size() - 1)],
		"rarity": RARITIES[rng.randi_range(0, RARITIES.size() - 1)],
		"magnitude": rng.randi_range(1, 5),
	}
	remnants.append(r)
	return r["uid"]


func _mint_big_undead() -> String:
	var uid := _mint_uid("u")
	var st := {}
	for s in STATS:
		st[s] = rng.randf_range(1.0, 10.0)
	big_undead.append({
		"uid": uid, "name": "Big " + uid, "kind": HUSK_KINDS[rng.randi_range(0, HUSK_KINDS.size() - 1)],
		"role": "brute", "stats": st, "place": "crypt", "front": "",
	})
	return uid


func _cap_of(section: String) -> int:
	return int(_sec("economy", section).get("cap", 1 << 30))


func _debug_fail(reason: String, key: String) -> Dictionary:
	return {"ok": false, "reason": reason, "key": key, "applied": {}}


func cmd_debug_grant(amounts: Dictionary) -> Dictionary:
	if not debug_enabled:
		return _debug_fail("not_debug", "")
	for k in amounts:
		if not DEBUG_GRANT_KEYS.has(k):
			return _debug_fail("unknown_key", str(k))
	for k in amounts:
		var counted: bool = k == "husks" or k == "remnants" or k == "big_undead"
		if not (_is_count(amounts[k]) if counted else _is_num(amounts[k])):
			return _debug_fail("bad_value", str(k))
	var applied := {}
	var minted: Array = []
	for k in amounts:
		var v := float(amounts[k])
		match k:
			"gold", "bodies", "living":
				var store: String = "townsfolk" if k == "living" else k
				var old: float = res[store]
				res[store] = maxf(0.0, old + v)
				applied[k] = res[store] - old
			"bone":
				var old: float = res["materials"]
				res["materials"] = maxf(0.0, old + v)
				applied[k] = res["materials"] - old
			"backlog":
				var old: float = realm.vei["undead_queue"]
				realm.vei["undead_queue"] = maxf(0.0, old + v)
				applied[k] = realm.vei["undead_queue"] - old
			"workers":
				var old := idle_undead
				idle_undead = maxi(0, int(old + v))
				applied[k] = idle_undead - old
			"relics":
				var old := relics
				relics = clampi(old + int(v), 0, _cap_of("relics"))
				applied[k] = relics - old
			"essence":
				var old := essence
				essence = clampi(old + int(v), 0, _cap_of("essence"))
				applied[k] = essence - old
			"husks":
				for i in int(v):
					minted.append(_mint_husk())
				applied[k] = int(v)
			"remnants":
				for i in int(v):
					minted.append(_mint_remnant())
				applied[k] = int(v)
			"big_undead":
				for i in int(v):
					minted.append(_mint_big_undead())
				applied[k] = int(v)
	applied["minted"] = minted
	rev += 1
	return {"ok": true, "reason": "", "key": "", "applied": applied}


func _valid_valve(v: Variant) -> bool:
	if not (v is Dictionary):
		return false
	var sum := 0.0
	for k in ["work", "war", "flood"]:
		if not v.has(k) or not _is_num(v[k]) or float(v[k]) < 0.0:
			return false
		sum += float(v[k])
	return sum > 0.0


func _valid_forts(v: Variant) -> bool:
	if not (v is Dictionary):
		return false
	for id in v:
		if realm.fort_by_id(str(id)).is_empty() or not (v[id] is Dictionary):
			return false
		for k in v[id]:
			if not ["living", "undead", "dead"].has(k) or not _is_num(v[id][k]) or float(v[id][k]) < 0.0:
				return false
	return true


func cmd_debug_set_state(patch: Dictionary) -> Dictionary:
	if not debug_enabled:
		return {"ok": false, "reason": "not_debug", "key": ""}
	for k in patch:
		if not DEBUG_STATE_KEYS.has(k):
			return {"ok": false, "reason": "unknown_key", "key": str(k)}
	for k in patch:
		var v: Variant = patch[k]
		var good := false
		match k:
			"time_scale":
				good = _is_num(v) and float(v) > 0.0 and float(v) <= 100.0
			"paused", "won":
				good = typeof(v) == TYPE_BOOL
			"relish_at":
				good = typeof(v) == TYPE_STRING and _node_valid(v)
			"valve":
				good = _valid_valve(v)
			"forge_level":
				good = _is_num(v) and float(v) >= 0.0
			"forts":
				good = _valid_forts(v)
		if not good:
			return {"ok": false, "reason": "bad_value", "key": str(k)}
	if patch.has("relish_at") and not run.is_empty():
		return {"ok": false, "reason": "busy", "key": "relish_at"}
	for k in patch:
		var v: Variant = patch[k]
		match k:
			"time_scale":
				time_scale = float(v)
			"paused":
				paused = v
			"won":
				won = v
			"relish_at":
				_place_relish(v)
			"valve":
				valve = _normalised(float(v["work"]), float(v["war"]), float(v["flood"]))
				valve_target = valve.duplicate()
			"forge_level":
				town["forge_level"] = int(float(v))
			"forts":
				for id in v:
					var f := realm.fort_by_id(str(id))
					for m in v[id]:
						f[m] = minf(float(v[id][m]), float(f["cap"]))
	rev += 1
	return {"ok": true, "reason": "", "key": ""}


func cmd_debug_skip_time(seconds: float) -> Dictionary:
	if not debug_enabled:
		return {"ok": false, "reason": "not_debug", "substeps": 0}
	if not is_finite(seconds) or seconds <= 0.0 or seconds > 86400.0:
		return {"ok": false, "reason": "bad_value", "substeps": 0}
	var n := _advance(seconds, 0)
	rev += 1
	return {"ok": true, "reason": "", "substeps": n}




func quality() -> float:
	var cfg: Dictionary = _cfg()
	var q: float = float(cfg.get("q", 1.2)) \
		+ float(cfg.get("q_per_forge", 0.25)) * town["forge_level"] \
		+ float(cfg.get("q_per_elite", 0.01)) * army["elite"]
	return clampf(q, 1.0, float(cfg.get("q_max", 4.0)))


## Advances the sim by `dt` seconds in fixed substeps. Returns substeps run.
## max_substeps > 0 caps the work; the remainder is then dropped.
func tick(dt: float, max_substeps := 0) -> int:
	if paused or not is_finite(dt) or dt <= 0.0:
		return 0
	return _advance(dt, max_substeps)


func _advance(dt: float, max_substeps: int) -> int:
	var step := substep_s()
	_acc += dt
	var n := 0
	while _acc >= step - 1e-9 and (max_substeps <= 0 or n < max_substeps):
		_tick(step)
		_acc -= step
		n += 1
	if max_substeps > 0 and n >= max_substeps and _acc >= step - 1e-9:
		_acc = 0.0
	return n


func _tick(dt: float) -> void:
	t += dt
	var cfg: Dictionary = _cfg()
	realm.t["q"] = quality()
	var mint: float = float(cfg.get("P_base", 2.0)) + float(cfg.get("P_per_slab", 2.0)) * town["slabs"]
	if res["bodies"] > 0.5 and assignments["slab"] > 0:
		var burn: float = minf(res["bodies"], float(cfg.get("slab_bodies_per_s", 0.12)) * town["slabs"] * dt)
		res["bodies"] -= burn
		mint *= float(cfg.get("slab_mint_bonus", 1.6))
	realm.t["P_base"] = mint
	_step_relish_travel(dt)  # §3 step 4: after the legacy town bits above, before realm.step
	realm.step(dt)
	_tick_town(dt, cfg)
	_tick_gather(dt, cfg)
	_field_acc += dt
	var fcfg: Dictionary = cfg.get("field", {})
	var period: float = 1.0 / float(fcfg.get("tick_hz", 5.0))
	# Cap field work per tick: at high time_scale the field may lag behind the
	# realm (it is territory visualisation + town control; exactness not needed).
	var max_field_ticks: int = int(fcfg.get("max_ticks_per_step", 2))
	var field_ticks := 0
	while _field_acc >= period and field_ticks < max_field_ticks:
		_field_acc -= period
		_inject_sources(period)
		field.tick(period)
		field_ticks += 1
	if field_ticks > 0:
		_update_towns(cfg)
	_field_acc = minf(_field_acc, period * float(fcfg.get("acc_cap_periods", 4.0)))
	rev += 1


func _tick_town(dt: float, cfg: Dictionary) -> void:
	res["gold"] += (float(cfg.get("gold_per_townsfolk", 0.02)) * res["townsfolk"] \
		+ float(cfg.get("gold_per_job_worker", 0.06)) * assignments["jobs"] \
		+ float(cfg.get("gold_per_trade_worker", 0.03)) * assignments["trade"]) * dt
	res["materials"] += float(cfg.get("materials_per_trade_worker", 0.03)) * assignments["trade"] * dt
	res["townsfolk"] += float(cfg.get("migrant_rate_per_town", 0.012)) * green_towns * dt


func _tick_gather(dt: float, cfg: Dictionary) -> void:
	if assignments["gather"] <= 0:
		gather["phase"] = "idle"
		return
	var speed: float = float(cfg.get("gather_speed", 140.0))
	match gather["phase"]:
		"idle":
			var best := ""
			var best_dead := 4.0
			for f in realm.forts:
				if f["dead"] > best_dead:
					best_dead = f["dead"]
					best = f["id"]
			if gather["target"] != "" and not realm.fort_by_id(gather["target"]).is_empty():
				best = gather["target"]
			if best != "":
				gather["phase"] = "out"
				gather["target"] = best
				gather["eta"] = realm.cov_pos.distance_to(realm.node_pos(best)) / speed
		"out":
			gather["eta"] -= dt
			if gather["eta"] <= 0.0:
				var f := realm.fort_by_id(gather["target"])
				if not f.is_empty():
					var carry: float = float(cfg.get("gather_carry", 14.0)) * assignments["gather"]
					gather["load"] = minf(f["dead"], carry)
					f["dead"] -= gather["load"]
				gather["phase"] = "back"
				gather["eta"] = realm.cov_pos.distance_to(realm.node_pos(gather["target"])) / speed
		"back":
			gather["eta"] -= dt
			if gather["eta"] <= 0.0:
				res["bodies"] += gather["load"]
				gather["load"] = 0.0
				gather["phase"] = "idle"


func _inject_sources(dt: float) -> void:
	var fcfg: Dictionary = _cfg().get("field", {})
	var src_main: float = float(fcfg.get("src_main", 3.0))
	var src_fort: float = float(fcfg.get("src_fort", 1.1))
	field.inject(realm.cov_pos, true, src_main * (1.0 + 0.15 * town["slabs"]) * dt, 2)
	var vei_str: float = 1.0 + realm.vei["living_pool"] / maxf(1.0, float(_cfg().get("vei_pool_cap", 600.0)))
	field.inject(realm.vei_pos, false, src_main * vei_str * dt, 3)
	for f in realm.forts:
		var cap: float = f["cap"]
		if f["undead"] > 0.5:
			field.inject(f["pos"], true, src_fort * (f["undead"] / cap) * dt, 1)
		if f["living"] > 0.5:
			field.inject(f["pos"], false, src_fort * (f["living"] / cap) * dt, 1)


func _update_towns(cfg: Dictionary) -> void:
	var thresh: float = float(cfg.get("field", {}).get("town_threshold", 0.18))
	green_towns = 0
	for tw in towns:
		var dom: float = field.dominance_at(tw["pos"])
		tw["control"] = "green" if dom > thresh else ("orange" if dom < -thresh else "none")
		if tw["control"] == "green":
			green_towns += 1


# ------------------------------------------------------------------ raids ----
func raid_seed(fort_id: String) -> Dictionary:
	var f := realm.fort_by_id(fort_id)
	if f.is_empty():
		return {}
	return {
		"fort_id": fort_id, "name": f["name"], "tier": f["tier"], "cap": f["cap"],
		"living": f["living"], "undead": f["undead"], "dead": f["dead"],
		"boss": false, "quality": quality(),
	}


func begin_raid(fort_id: String) -> void:
	_raiding_fort = fort_id
	_sync_realm_relish()


func end_raid() -> void:
	_raiding_fort = ""
	_sync_realm_relish()


func apply_raid_result(r: Dictionary) -> void:
	var f := realm.fort_by_id(str(r.get("fort_id", "")))
	if f.is_empty():
		return
	stats["raids"] += 1
	var killed: float = minf(f["living"], float(r.get("killed_living_mass", 0.0)))
	f["living"] -= killed
	f["dead"] += killed
	var chaff: float = minf(f["dead"], float(r.get("raised_chaff_mass", 0.0)))
	f["dead"] -= chaff
	realm.vei["undead_queue"] += chaff  # worthless undead are thrown at Vei
	var good_mass: float = minf(f["dead"], float(r.get("good_mass", 0.0)))
	f["dead"] -= good_mass
	army["soldier"] += int(r.get("raised_soldiers", 0))
	army["elite"] += int(r.get("raised_elites", 0))
	var garrison: float = minf(f["dead"], float(r.get("garrison_mass", 0.0)))
	f["dead"] -= garrison
	f["undead"] += garrison
	stats["raised_total"] += chaff + good_mass + garrison
	if bool(r.get("relish_died", false)):
		_relish_dies()


func auto_resolve_raid(fort_id: String) -> void:
	# Fallback when the raid scene is unavailable: a decent but unspectacular raid.
	var f := realm.fort_by_id(fort_id)
	if f.is_empty():
		return
	apply_raid_result({
		"fort_id": fort_id,
		"killed_living_mass": f["living"] * 0.3,
		"raised_chaff_mass": (f["dead"] + f["living"] * 0.3) * 0.5,
		"raised_soldiers": 1 + int(f["tier"]),
		"raised_elites": 0,
		"good_mass": 4.0,
		"garrison_mass": (f["dead"] + f["living"] * 0.3) * 0.2,
		"relish_died": false,
	})


## Legacy death (E1 rule, §8.3 step 10): a legacy vat gives a clone, otherwise she is
## unmade and the army scatters; she respawns home at once.
func _relish_dies() -> void:
	stats["deaths"] += 1
	var clone: bool = town["vats"] > 0
	var at_node: String = relish["at"]
	var run_id := int(run.get("run_id", -1))
	if clone:
		town["vats"] -= 1
	else:
		army["soldier"] = int(army["soldier"] * 0.6)
		army["elite"] = int(army["elite"] * 0.7)
	_emit({"type": "relish_died", "outcome": "clone" if clone else "unmade", "in_place": false,
		"at": at_node, "run_id": run_id, "respawn_s": 0.0})
	run = {}
	_place_relish("covington")
	_emit({"type": "relish_respawned", "with_clone": clone, "at": "covington"})


# ------------------------------------------------------------------ town -----
func town_snapshot() -> Dictionary:
	return {
		"town": town.duplicate(true), "assignments": assignments.duplicate(true),
		"res": res.duplicate(true), "army": army.duplicate(true),
		"idle_undead": idle_undead, "quality": quality(),
		"green_towns": green_towns, "gather": gather.duplicate(true),
		"fort_ids": realm.forts.map(func(f): return f["id"]),
		"simulacra": realm.simulacra.duplicate(true),
	}


func apply_town_result(r: Dictionary) -> void:
	if r.has("town"):
		town = r["town"]
	if r.has("assignments"):
		assignments = r["assignments"]
	if r.has("idle_undead"):
		idle_undead = int(r["idle_undead"])
	var spend: Dictionary = r.get("spend", {})
	res["gold"] = maxf(0.0, res["gold"] - float(spend.get("gold", 0.0)))
	res["materials"] = maxf(0.0, res["materials"] - float(spend.get("materials", 0.0)))
	if r.has("gather_target"):
		gather["target"] = str(r["gather_target"])
	for s in r.get("deploy_simulacra", []):
		realm.simulacra.append(s)
		stats["sims_built"] += 1


# ------------------------------------------------------------------ boss -----
func boss_seed() -> Dictionary:
	return {
		"fort_id": "vei", "name": "Vei's Domain", "tier": 5, "cap": 800.0,
		"living": 500.0, "undead": 0.0, "dead": 60.0, "boss": true,
		"quality": quality(), "backlog": realm.vei["undead_queue"],
		"army": army.duplicate(true), "vei_capacity": float(_cfg().get("R_vei", 50.0)),
		"odds": realm.readout()["odds"],
	}


func apply_boss_result(r: Dictionary) -> void:
	if bool(r.get("won", false)):
		won = true
		_emit({"type": "vei_result", "won": true})
		return
	realm.vei["undead_queue"] *= 0.35  # she digests a chunk of the massed horde
	army["soldier"] = int(army["soldier"] * 0.3)
	army["elite"] = int(army["elite"] * 0.4)
	if bool(r.get("relish_died", true)):
		_relish_dies()
	_emit({"type": "vei_result", "won": false})


func auto_resolve_boss() -> void:
	var odds: float = realm.readout()["odds"]
	apply_boss_result({"won": rng.randf_range(0.0, 1.0) < odds, "relish_died": true})


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
