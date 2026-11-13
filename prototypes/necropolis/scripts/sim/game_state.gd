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
## The unit of each RATE_IDS rate (§5.2).
const _RATE_UNITS := {
	"mint": "mass/s", "work": "mass/s", "war": "mass/s", "flood": "mass/s", "workers": "workers/s",
	"bodies": "mass/s", "gold": "gold/s", "bone": "bone/s", "living": "living/s", "corpses": "mass/s",
	"backlog": "mass/s",
}
## E1 stub tells for view_fort.warden (the dungeon unit owns warden specs from E2).
const _WARDEN_TELLS := {"bellringer": ["rings slam on the beat"]}
## ledger().held: every pool of mass (§4.7).
const _LEDGER_HELD := ["fort_living", "fort_undead", "corpses", "backlog", "vei_dead", "living_pool", "bodies", "workers", "convoys"]

var realm: RealmSim
var field: InfluenceField
var time_scale := 1.0
var paused := false
var t := 0.0  # sim seconds since the new game
var debug_enabled := false
var save_dir := "user://saves"  # saves (§9); tests point it at a temp dir
var fixture_dir := "res://tests/fixtures"  # cmd_debug_load_fixture reads <fixture_dir>/<name>.json
var rng := RandomNumberGenerator.new()
var rng_seed := ""  # String: 64-bit seeds do not survive JSON numbers
var rev := 0  # +1 per substep and per successful command

# --- Relish (owned here; RealmSim sees only her effects, as step inputs: _relish_effects) ---
var relish := {}
# --- runs and seeds (§4.5, §7) ---
var run := {}  # {} or {run_id, kind: "raid"|"boss", fort_id, seed_rev, seed}
var next_run_id := 1
var next_uid := 1  # one counter for h<n>, r<n>, u<n>
var game_seed := 0
var first_dungeon_id := ""  # "" once a raid result has cleared it (T1.4)
var cleared_forts := {}  # fort_id -> true once its first clear is spent (T1.4)
# --- stocks and inventories (views §5.12) ---
var relics := 0
var essence := 0
var husks: Array = []
var remnants: Array = []
var big_undead: Array = []
var party_uids: Array = []
var valve := {"work": 0.40, "war": 0.45, "flood": 0.15}  # the current vector; slews toward the target (§3 step 3)
var valve_target := {"work": 0.40, "war": 0.45, "flood": 0.15}
## WORK mass the valve has sent and nothing has consumed yet. TownSim will consume it; until it
## lands this only accumulates. Held mass. Not saved yet (the save shape is frozen until its bump).
var work_pending := 0.0
var blueprints: Array = []  # owned blueprint ids (= the building ids they unlock), banked by apply_result
var applied_runs: Array = []  # the last 32 run ids apply_result closed (for duplicate_run); kept across new games like next_run_id
var _dungeon_sink := 0.0  # mass the raid writeback lost (ledger sinks.dungeon), since the new game
# --- E1 settings: stored by commands and echoed in views (§1.1 "E1 stubs") ---
var haul_target := "auto"  # cmd_set_haul_target; the legacy convoy's own pick is gather.target
var ladder: Array = []  # the player's job order, top first
var staff_caps := {}  # lot_id -> int cap; absent = -1 (no cap)
var stances_on: Array = []  # stance ids switched on, oldest first; the newest are suspended first
var vats_staffed: Array = []  # bool per vat slot
# --- E2/E3 placeholders: saved and restored so a fixture can carry them; nothing reads them at E1 ---
var _tithe := {}  # realm.tithe (E2)
var _phylactery_charges := 0  # backups.phylactery_charges (E3)
var _readout := {"diff_ema": 0.0, "q_raise_ema": 0.0}  # the diff and q_raise EMAs (E2)
var _stance_hold := {}  # stance id -> hold seconds left (E3)
# --- the town at E1: the BALANCE §0 start set (TownSim owns this from E2) ---
var town_tier := "hamlet"
var lot_buildings := {}  # lot_id -> {building_id: String, level: int}

# --- the villages and the shared flags ---
var towns: Array = []
var green_towns := 0
var won := false
var stats := {"raised_total": 0.0, "raids": 0, "deaths": 0, "sims_built": 0}

# --- the E1 legacy economy (scripts/sim/legacy_economy.gd; E2a retires it) ---
## Owns the legacy stores; the names below stay as forwarders so the shell, the scenes and the
## tests read and write them as before.
var legacy := LegacyEconomy.new()
var army: Dictionary:
	get: return legacy.army
	set(v): legacy.army = v
var res: Dictionary:
	get: return legacy.res
	set(v): legacy.res = v
var town: Dictionary:
	get: return legacy.town
	set(v): legacy.town = v
var assignments: Dictionary:
	get: return legacy.assignments
	set(v): legacy.assignments = v
var idle_undead: int:
	get: return legacy.idle_undead
	set(v): legacy.idle_undead = v
var gather: Dictionary:
	get: return legacy.gather
	set(v): legacy.gather = v

var _cfgs := {}
var _acc := 0.0
var _split := {"mint": 0.0, "work": 0.0, "war": 0.0, "flood": 0.0}  # mass/s of the last substep (step 3)
var _realm_inputs := {}  # the inputs of the last RealmSim.step (step 5), for tests
var _field_acc := 0.0
var _events: Array = []


## `configs` is keyed by file basename; a non-empty dict calls setup().
func _init(configs: Dictionary = {}) -> void:
	if not configs.is_empty():
		setup(configs)


## `cfgs` is the dict returned by load_configs (keyed by file name).
func setup(cfgs: Dictionary) -> void:
	_cfgs = cfgs
	legacy.cfgs = cfgs


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


func drain_events() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	out.assign(_events)
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
	var opening: Dictionary = _sec("economy", "opening")
	_build_realm_field_towns()
	legacy.reset()
	green_towns = 0
	won = false
	stats = {"raised_total": 0.0, "raids": 0, "deaths": 0, "sims_built": 0}
	_acc = 0.0
	_field_acc = 0.0
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
	work_pending = 0.0
	_split = {"mint": 0.0, "work": 0.0, "war": 0.0, "flood": 0.0}
	_realm_inputs = {}
	first_dungeon_id = str(opening.get("first_dungeon", "old-sluice"))
	cleared_forts = {}
	_dungeon_sink = 0.0
	_tithe = {}
	_phylactery_charges = 0
	_readout = {"diff_ema": 0.0, "q_raise_ema": 0.0}
	_stance_hold = {}
	blueprints = []
	haul_target = "auto"
	ladder = []
	for j in _sec("economy", "job").get("default_ladder", JOB_IDS):
		ladder.append(str(j))
	staff_caps = {}
	stances_on = []
	vats_staffed = []
	town_tier = "hamlet"
	lot_buildings = {}
	var start: Dictionary = opening.get("buildings", {})
	for lot_id in start:
		lot_buildings[str(lot_id)] = {"building_id": str(start[lot_id]), "level": 1}
	relish = {
		"state": "home", "at": "covington", "target": "",
		"pos": [float(realm.cov_pos.x), float(realm.cov_pos.y)], "heading": 0.0,
		"dead_s_left": 0.0, "respawn_with_clone": false,
	}
	_prewarm_field()
	rev += 1
	return {"ok": true, "reason": ""}


## The config-built parts of a game: the realm, an empty field and the villages, all neutral. A
## load rebuilds them the same way (§9).
func _build_realm_field_towns() -> void:
	var cfg: Dictionary = _cfg()
	var world: Dictionary = _cfgs.get("world", {})
	realm = RealmSim.new()
	realm.setup(world, cfg)
	legacy.realm = realm
	field = InfluenceField.new()
	field.setup(cfg.get("field", {}), RealmSim._vec(world.get("size", [2048, 1440])))
	towns = []
	for tw in world.get("towns", []):
		towns.append({
			"id": tw.get("id", ""), "name": tw.get("name", "?"),
			"pos": RealmSim._vec(tw.get("pos", [0, 0])),
			"pop": float(tw.get("pop", 30)), "control": "none",
		})


## Pre-warms the field so the map doesn't start blank, then publishes any in-flight slice.
## A load reuses it (T1.5).
func _prewarm_field() -> void:
	for i in 90:
		_inject_sources(0.2)
		field.tick(0.2)
	field.flush()


func cmd_set_time_scale(x: float) -> Dictionary:
	if not debug_enabled:
		return {"ok": false, "reason": "not_debug", "time_scale": time_scale}
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
	if not debug_enabled:
		return {"ok": false, "reason": "not_debug", "paused": paused}
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
		return
	_face(tgt)
	var p: Array = relish["pos"]
	var q := _node_xy(tgt)
	var f := step / dist
	relish["pos"] = [p[0] + (q[0] - p[0]) * f, p[1] + (q[1] - p[1]) * f]


## What her position does now (MECHANICS §3.3): `tide_fort` is her fort while she stands at it or is
## in its dungeon; `redirect_fort` only while she stands at it (not in its dungeon). Nothing while
## dead, travelling, at Vei or home (home's rot and slab effects are TownSim's, E3's). The step-5
## inputs and view_relish().effects both come from here.
func _relish_effects() -> Dictionary:
	var st: String = relish["state"]
	var at: String = relish["at"]
	return {
		"tide_fort": at if st == "at_fort" or st == "in_dungeon" else "",
		"redirect_fort": at if st == "at_fort" else "",
	}


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
		"phylactery_charges": _phylactery_charges, "clones_ready": int(legacy.town["vats"]),
		"can_descend": reason == "" and not realm.fort_by_id(at).is_empty(),
		"reason": reason,
		"run_id": int(run.get("run_id", -1)), "run_kind": str(run.get("kind", "")),
		"effects": _relish_effects().merged({"home": relish["state"] == "home"}),
	}


# ------------------------------------------------- §4.2 macro: valve, haul ----
## Sets the target (normalised) only; the current vector slews toward it each substep (§3 step 3).
func cmd_set_valve(work: float, war: float, flood: float) -> Dictionary:
	var why := ""
	if not (is_finite(work) and is_finite(war) and is_finite(flood)):
		why = "not_finite"
	elif work < 0.0 or war < 0.0 or flood < 0.0:
		why = "negative"
	elif work + war + flood <= 0.0:
		why = "zero_valve"
	if why != "":
		return {"ok": false, "reason": why, "target": {}}
	var m := maxf(work, maxf(war, flood))  # scale first so huge inputs cannot overflow the sum
	valve_target = _normalised(work / m, war / m, flood / m)
	rev += 1
	return {"ok": true, "reason": "", "target": valve_target.duplicate()}


## E1/E2: stores the target; at E1 the legacy convoy honours it through gather.target
## ("auto" clears it, so the convoy picks the richest corpse fort itself).
func cmd_set_haul_target(target: String) -> Dictionary:
	if target != "auto" and realm.fort_by_id(target).is_empty():
		return {"ok": false, "reason": "unknown_fort", "haul_target": ""}
	haul_target = target
	legacy.set_gather_target("" if target == "auto" else target)
	rev += 1
	return {"ok": true, "reason": "", "haul_target": haul_target}


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
		"diff": diff,
		"odds": float(ro["odds"]),
		"sign": 1 if diff > 1e-9 else (-1 if diff < -1e-9 else 0),
		"drain_s": backlog / -diff if diff < -1e-9 else -1.0,
	}


func _is_first_dungeon(fort_id: String) -> bool:
	return first_dungeon_id != "" and fort_id == first_dungeon_id


## [garrison_units: int, garrison_in_mass: float] a descent at the fort would take in (§7.1).
func _garrison(fort_id: String) -> Array:
	var f := realm.fort_by_id(fort_id)
	if f.is_empty():
		return [0, 0.0]
	var mass: Dictionary = _sec("raid", "mass")
	var div := _garrison_div()
	var units := clampi(int(f["undead"] / div), 0, int(mass.get("garrison_max", 12)))
	return [units, float(units) * div]


## raid.json mass.garrison_mass_div, which the seed carries so Results.from_v1 needs no config.
func _garrison_div() -> float:
	return float(_sec("raid", "mass").get("garrison_mass_div", 10.0))


func _starter_units(fort_id: String) -> int:
	return int(_sec("economy", "opening").get("starter_party", 8)) if _is_first_dungeon(fort_id) else 0


## raid.json wardens.by_fort is dungeon-owned; the E1 stub is bellringer.
func _warden_archetype(fort_id: String) -> String:
	return str(_sec("raid", "wardens").get("by_fort", {}).get(fort_id, "bellringer"))


func _loot_hint(fort_id: String) -> String:
	return "a husk and a blueprint" if _is_first_dungeon(fort_id) else ""


func _phylactery_max() -> int:
	return int(_backups_cfg().get("phylactery", {}).get("max_per_dungeon", 1))


func _relish_hp() -> float:
	return float(_cfgs.get("raid", {}).get("relish", {}).get("hp", 30.0))


## Vei's fronts, per FRONT_IDS. need/have/cleared are E3; `assigned` echoes cmd_assign_front.
func _fronts(with_cleared: bool) -> Array:
	var out: Array = []
	for id in FRONT_IDS:
		var e := {"id": id, "need": 0.0, "have": 0.0, "assigned": _front_assigned(id)}
		if with_cleared:
			e["cleared"] = false
		out.append(e)
	return out


func _front_assigned(front_id: String) -> Array:
	var out: Array = []
	for b in big_undead:
		if b["front"] == front_id:
			out.append(b["uid"])
	return out


func _dungeon_seed(fort_id: String, run_id: int, seed_rev: int) -> Dictionary:
	var f := realm.fort_by_id(fort_id)
	var g := _garrison(fort_id)
	var first := _is_first_dungeon(fort_id)
	var archetype := _warden_archetype(fort_id)
	var tier := int(f["tier"])
	return {
		"v": 2, "kind": "raid", "run_id": run_id, "seed_rev": seed_rev,
		"rng_seed": _derived_rng_seed(run_id),
		"fort": {
			"id": fort_id, "name": str(f["name"]), "tier": tier, "cap": float(f["cap"]),
			"first_clear": not cleared_forts.has(fort_id), "first_dungeon": first,
			"clears_since_retaken": int(f.get("clears_since_retaken", 0)), "yield_mult": 1.0,
		},
		"living": float(f["living"]), "dead": float(f["dead"]), "undead": float(f["undead"]),
		"garrison_units": g[0], "garrison_in_mass": g[1], "garrison_mass_div": _garrison_div(),
		"starter_units": _starter_units(fort_id),
		"party": _party_entries(),
		"digest_q": quality(),
		"phylactery_charges": _phylactery_charges,
		"phylactery_max_per_dungeon": _phylactery_max(),
		"clones_ready": int(legacy.town["vats"]),
		"warden": {"archetype": archetype, "tier": tier}, "warden_spec": {},
		"loot_table_id": "t%d.%s" % [tier, archetype],
		"loot_hint": _loot_hint(fort_id),
		"chest_husk": first, "watchtower": false,
		"relish_hp": _relish_hp(),
	}


func _boss_seed_v2(run_id: int, seed_rev: int) -> Dictionary:
	var ro := _vei_readout()
	return {
		"v": 2, "kind": "boss", "run_id": run_id, "seed_rev": seed_rev,
		"rng_seed": _derived_rng_seed(run_id),
		"backlog": float(realm.vei["undead_queue"]), "living_pool": float(realm.vei["living_pool"]),
		"odds": ro["odds"], "sign": ro["sign"], "drain_s": ro["drain_s"], "digest_q": quality(),
		"vei_capacity": float(_cfg().get("R_vei", 50.0)),
		"fronts": _fronts(false),
		"fronts_required": _fronts_required(),
		"party": _party_entries(true),
		"phylactery_charges": _phylactery_charges, "clones_ready": int(legacy.town["vats"]),
		"relish_hp": _relish_hp(),
	}


func _fronts_required() -> int:
	return int(_cfgs.get("vei", {}).get("fronts_required", 3))


func _open_run(kind: String, fort_id: String) -> Dictionary:
	var run_id := next_run_id
	next_run_id += 1
	rev += 1
	var seed_d := _dungeon_seed(fort_id, run_id, rev) if kind == "raid" else _boss_seed_v2(run_id, rev)
	run = {"run_id": run_id, "kind": kind, "fort_id": fort_id, "seed_rev": rev, "seed": seed_d}
	relish["state"] = "in_dungeon" if kind == "raid" else "in_boss"
	time_scale = 1.0
	paused = false
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


## The reason cmd_begin_boss() would refuse with now, or "" (view_vei shares it).
func _boss_reason() -> String:
	if not run.is_empty():
		return "busy"
	if relish["state"] == "dead":
		return "dead"
	if relish["state"] != "at_vei":
		return "not_at_vei"
	return ""


func cmd_begin_boss() -> Dictionary:
	var why := _boss_reason()
	if why != "":
		return {"ok": false, "reason": why, "seed": {}, "run_id": -1, "seed_rev": -1}
	return _open_run("boss", "vei")


func cmd_abort_dungeon() -> Dictionary:
	if run.is_empty():
		return {"ok": false, "reason": "no_run", "run_id": -1}
	var run_id: int = run["run_id"]
	relish["state"] = "at_fort" if run["kind"] == "raid" else "at_vei"
	run = {}
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


## The open raid's fort else "".
func raiding_fort_id() -> String:
	if run.get("kind", "") == "raid":
		return run["fort_id"]
	return ""


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
			"gold", "bodies", "living", "bone", "workers":
				applied[k] = legacy.grant(k, v)
			"backlog":
				var old: float = realm.vei["undead_queue"]
				realm.vei["undead_queue"] = maxf(0.0, old + v)
				applied[k] = realm.vei["undead_queue"] - old
			"relics":
				var old := relics
				relics = clampi(old + int(v), 0, maxi(_cap_of("relics"), old))
				applied[k] = relics - old
			"essence":
				var old := essence
				essence = clampi(old + int(v), 0, maxi(_cap_of("essence"), old))
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
				var room := maxi(0, _cap_of("big_undead") - big_undead.size())
				var n := mini(int(v), room)
				for i in n:
					minted.append(_mint_big_undead())
				applied[k] = n
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
				good = _is_count(v)
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
				legacy.set_forge_level(int(float(v)))
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


# ------------------------------------------------------------- §4.3 town ----
# At E1 the town is the BALANCE §0 start set and nothing changes it: the build family,
# raise, craft and deploy are §1.1 stubs (id checks, then ok with zero extras, no change).
# The settings (job ladder, staff caps, stances, vat staffing) are stored and echoed.

func _buildings_cfg() -> Dictionary:
	var d: Variant = _cfgs.get("buildings", {})
	return d if d is Dictionary else {}


func _lots_cfg() -> Array:
	var d: Variant = _cfgs.get("town", {}).get("lots", [])
	return d if d is Array else []


func _lot(lot_id: String) -> Dictionary:
	for l in _lots_cfg():
		if str(l.get("id", "")) == lot_id:
			return l
	return {}


## The current tier opens the first N lots (Hamlet: 8).
func _lots_unlocked() -> int:
	return int(_sec("economy", "town").get("tiers", {}).get(town_tier, {}).get("lots", 8))


## Built lots, in lot order.
func _built_lots() -> Array:
	var out: Array = []
	for l in _lots_cfg():
		var id := str(l.get("id", ""))
		if lot_buildings.has(id):
			out.append(id)
	return out


func _count_built(building_id: String) -> int:
	var n := 0
	for lot_id in lot_buildings:
		if lot_buildings[lot_id]["building_id"] == building_id:
			n += 1
	return n


## A building's job slots per job id (buildings.json `jobs`).
func _jobs_of(building_id: String) -> Dictionary:
	var d: Variant = _buildings_cfg().get(building_id, {}).get("jobs", {})
	return d if d is Dictionary else {}


func _slots_of(building_id: String) -> int:
	var jobs := _jobs_of(building_id)
	var n := 0
	for j in jobs:
		n += int(jobs[j])
	return n


func _cost_of(d: Variant) -> Dictionary:
	var c: Dictionary = d if d is Dictionary else {}
	return {"gold": float(c.get("gold", 0.0)), "bone": float(c.get("bone", 0.0)), "relics": int(c.get("relics", 0))}


func _upkeep_of(building_id: String) -> Dictionary:
	var d: Variant = _buildings_cfg().get(building_id, {}).get("upkeep", {})
	var u: Dictionary = d if d is Dictionary else {}
	return {"gold": float(u.get("gold", 0.0)), "bone": float(u.get("bone", 0.0))}


func _zero_cost() -> Dictionary:
	return {"gold": 0.0, "bone": 0.0, "relics": 0}


func _bodies_cap() -> float:
	return float(_sec("economy", "body_store").get("cap", 200.0))


## E2 stub: checks the ids, then ok with a zero cost. Nothing is built or paid.
func cmd_build(building_id: String, lot_id: String) -> Dictionary:
	var why := ""
	if not _buildings_cfg().has(building_id):
		why = "unknown_building"
	elif _lot(lot_id).is_empty():
		why = "unknown_lot"
	if why != "":
		return {"ok": false, "reason": why, "cost": {}}
	rev += 1
	return {"ok": true, "reason": "", "cost": _zero_cost()}


## E2 stub: checks the lot id, then ok with level 0 and a zero cost.
func cmd_upgrade(lot_id: String) -> Dictionary:
	if _lot(lot_id).is_empty():
		return {"ok": false, "reason": "unknown_lot", "level": 0, "cost": {}}
	rev += 1
	return {"ok": true, "reason": "", "level": 0, "cost": _zero_cost()}


## E2 stub: checks the lot id, then ok. Nothing is demolished.
func cmd_demolish(lot_id: String) -> Dictionary:
	if _lot(lot_id).is_empty():
		return {"ok": false, "reason": "unknown_lot"}
	rev += 1
	return {"ok": true, "reason": ""}


## E2 stub: checks the lot id, then ok with a zero refund.
func cmd_cancel_build(lot_id: String) -> Dictionary:
	if _lot(lot_id).is_empty():
		return {"ok": false, "reason": "unknown_lot", "refund": {}}
	rev += 1
	return {"ok": true, "reason": "", "refund": _zero_cost()}


## E1/E2: stores the ladder, a permutation of JOB_IDS, top first.
func cmd_set_job_priority(order: Array) -> Dictionary:
	var why := ""
	for j in order:
		if not (typeof(j) == TYPE_STRING or typeof(j) == TYPE_STRING_NAME) or not JOB_IDS.has(str(j)):
			why = "unknown_job"
			break
	var seen := {}
	if why == "":
		for j in order:
			if seen.has(str(j)):
				why = "duplicate_job"
				break
			seen[str(j)] = true
	if why == "" and seen.size() < JOB_IDS.size():
		why = "missing_job"
	if why != "":
		return {"ok": false, "reason": why, "order": []}
	ladder = []
	for j in order:
		ladder.append(str(j))
	rev += 1
	return {"ok": true, "reason": "", "order": ladder.duplicate()}


## E1/E2: stores a lot's staff cap (-1 = none). A cap above the slots is accepted.
func cmd_set_staff_cap(lot_id: String, cap: int) -> Dictionary:
	var why := ""
	if _lot(lot_id).is_empty():
		why = "unknown_lot"
	elif not lot_buildings.has(lot_id):
		why = "empty_lot"
	elif _slots_of(lot_buildings[lot_id]["building_id"]) == 0:
		why = "no_jobs"
	elif cap < -1:
		why = "bad_cap"
	if why != "":
		return {"ok": false, "reason": why, "cap": 0}
	staff_caps[lot_id] = cap
	rev += 1
	return {"ok": true, "reason": "", "cap": cap}


## stance.base_slots, plus the Guildhall's, plus 1 while Relish is home (MECHANICS §4.5).
func _stance_slots() -> int:
	var per_hall: Variant = _buildings_cfg().get("guildhall", {}).get("effects", {}).get("stance_slots", 1)
	var n := int(_sec("economy", "stance").get("base_slots", 2)) + _count_built("guildhall") * int(per_hall)
	if relish["state"] == "home":
		n += int(_cfg().get("relish", {}).get("home_stance_bonus", 1))  # her one live home effect (§3.3)
	return n


## E1/E3: stores the toggle. When the slots run short, the most recently enabled stances
## are suspended (view_stances), not switched off.
func cmd_set_stance(stance_id: String, on: bool) -> Dictionary:
	if not STANCE_IDS.has(stance_id):
		return {"ok": false, "reason": "unknown_stance", "slots": 0, "used": 0}
	var slots := _stance_slots()
	if on and not stances_on.has(stance_id):
		if stances_on.size() >= slots:
			return {"ok": false, "reason": "no_slot", "slots": 0, "used": 0}
		stances_on.append(stance_id)
	elif not on:
		stances_on.erase(stance_id)
	rev += 1
	return {"ok": true, "reason": "", "slots": slots, "used": mini(stances_on.size(), slots)}


func _find_uid(items: Array, uid: Variant) -> Dictionary:
	if typeof(uid) != TYPE_STRING:
		return {}
	for it in items:
		if it["uid"] == uid:
			return it
	return {}


## A big undead as views and command extras show it (§5.12).
func _bu_entry(b: Dictionary) -> Dictionary:
	var st := {}
	for k in STATS:
		st[k] = float(b["stats"].get(k, 0.0))
	return {"uid": b["uid"], "name": b["name"], "kind": b["kind"], "role": b["role"], "stats": st,
		"place": b["place"], "front": b["front"]}


## E2 stub (the raise needs the town unit's SlabLogic): checks not_home and the item ids,
## then ok with a zero-valued entry. Nothing is consumed or minted; at_cap, bad_name and
## invalid_recipe are checked from E2.
@warning_ignore("unused_parameter")
func cmd_raise_big_undead(husk_uid: String, remnant_uids: Array, name: String) -> Dictionary:
	var why := ""
	if relish["state"] != "home":
		why = "not_home"
	elif _find_uid(husks, husk_uid).is_empty():
		why = "unknown_husk"
	else:
		for r in remnant_uids:
			if _find_uid(remnants, r).is_empty():
				why = "unknown_remnant"
				break
		var seen := {}
		for r in remnant_uids:
			if why != "":
				break
			if seen.has(r):
				why = "duplicate_remnant"
			seen[r] = true
	if why != "":
		return {"ok": false, "reason": why, "big_undead": {}}
	var st := {}
	for k in STATS:
		st[k] = 0.0
	rev += 1
	return {"ok": true, "reason": "", "big_undead": {
		"uid": "", "name": "", "kind": "", "role": "", "stats": st, "place": "", "front": ""}}


func cmd_rename_big_undead(uid: String, name: String) -> Dictionary:
	var b := _find_uid(big_undead, uid)
	if b.is_empty():
		return {"ok": false, "reason": "unknown_uid", "name": ""}
	var nm := name.strip_edges()
	if nm.is_empty() or nm.length() > 24:
		return {"ok": false, "reason": "bad_name", "name": ""}
	b["name"] = nm
	rev += 1
	return {"ok": true, "reason": "", "name": nm}


## True if the uid is in the open run's party (its seed's).
func _in_run_party(uid: String) -> bool:
	if run.is_empty():
		return false
	for e in run["seed"]["party"]:
		if e["uid"] == uid:
			return true
	return false


## Uids of the big undead at a place, by uid ("town:<lot>" is the foreman, "fort:<id>" the siege).
func _uids_at(place: String) -> Array:
	var out: Array = []
	for b in big_undead:
		if b["place"] == place:
			out.append(b["uid"])
	return out


func _foreman_of(lot_id: String) -> String:
	var at := _uids_at("town:" + lot_id)
	return at[0] if not at.is_empty() else ""


## Takes a big undead out of the party. Its front goes too: fronts are for party members.
func _leave_party(b: Dictionary) -> void:
	party_uids.erase(b["uid"])
	b["front"] = ""


## E1/E2: records the place (and takes it out of the party); foreman and siege effects are E2.
func cmd_place_big_undead(uid: String, place: String) -> Dictionary:
	var b := _find_uid(big_undead, uid)
	var why := ""
	if b.is_empty():
		why = "unknown_uid"
	elif _in_run_party(uid):
		why = "busy"
	elif place.begins_with("town:"):
		var lot_id := place.trim_prefix("town:")
		var foreman := _foreman_of(lot_id)
		if _lot(lot_id).is_empty():
			why = "unknown_lot"
		elif not lot_buildings.has(lot_id):
			why = "empty_lot"
		elif foreman != "" and foreman != uid:
			why = "foreman_taken"
	elif place.begins_with("fort:"):
		if realm.fort_by_id(place.trim_prefix("fort:")).is_empty():
			why = "unknown_fort"
	elif place != "crypt":
		why = "bad_place"
	if why != "":
		return {"ok": false, "reason": why, "place": ""}
	if party_uids.has(uid):
		_leave_party(b)
	b["place"] = place
	rev += 1
	return {"ok": true, "reason": "", "place": place}


## E3 stub: checks the item id, then ok with count 0.
func cmd_craft(item_id: String) -> Dictionary:
	if not CRAFT_IDS.has(item_id):
		return {"ok": false, "reason": "unknown_item", "count": 0}
	rev += 1
	return {"ok": true, "reason": "", "count": 0}


## E3 stub: checks the fort id, then ok with zero charges.
func cmd_deploy_simulacrum(fort_id: String) -> Dictionary:
	if realm.fort_by_id(fort_id).is_empty():
		return {"ok": false, "reason": "unknown_fort", "charges": 0.0, "ready_left": 0}
	rev += 1
	return {"ok": true, "reason": "", "charges": 0.0, "ready_left": 0}


## Vat slots at E1: the legacy vat count. Each legacy vat is a ready clone.
func _vat_slots() -> int:
	return legacy.vats()


## E1/E3: stores the staffing (clones grow only while staffed from E3).
func cmd_staff_vat(slot: int, on: bool) -> Dictionary:
	if slot < 0 or slot >= _vat_slots():
		return {"ok": false, "reason": "unknown_slot", "staffed": false}
	while vats_staffed.size() <= slot:
		vats_staffed.append(false)
	vats_staffed[slot] = on
	rev += 1
	return {"ok": true, "reason": "", "staffed": on}


# ------------------------------------------------- §4.4 party and fronts ----
## The listed uids join the party in this order (place "party"); former members not
## listed go back to the crypt and lose their front.
func cmd_set_party(uids: Array) -> Dictionary:
	var why := ""
	if not run.is_empty():
		why = "busy"
	else:
		for u in uids:
			if _find_uid(big_undead, u).is_empty():
				why = "unknown_uid"
				break
	var seen := {}
	for u in uids:
		if why != "":
			break
		if seen.has(u):
			why = "duplicate_uid"
		seen[u] = true
	if why != "":
		return {"ok": false, "reason": why, "party": []}
	for u in party_uids.duplicate():
		var b := _find_uid(big_undead, u)
		if not uids.has(u) and not b.is_empty():
			_leave_party(b)
			b["place"] = "crypt"
	party_uids = []
	for u in uids:
		party_uids.append(u)
		_find_uid(big_undead, u)["place"] = "party"
	rev += 1
	return {"ok": true, "reason": "", "party": party_uids.duplicate()}


## E1/E3: records a party member's front ("" unassigns). Fronts take effect at E3.
func cmd_assign_front(uid: String, front_id: String) -> Dictionary:
	var b := _find_uid(big_undead, uid)
	var why := ""
	if not run.is_empty():
		why = "busy"
	elif b.is_empty():
		why = "unknown_uid"
	elif not party_uids.has(uid):
		why = "not_in_party"
	elif front_id != "" and not FRONT_IDS.has(front_id):
		why = "unknown_front"
	if why != "":
		return {"ok": false, "reason": why}
	b["front"] = front_id
	rev += 1
	return {"ok": true, "reason": ""}


# ------------------------------------------------------------ §4.7 ledger ----
## E2 stub: the documented shape, all zeros except sinks.dungeon (the raid writeback's loss).
## `held` names every pool of mass.
func ledger() -> Dictionary:
	var held := {}
	for k in _LEDGER_HELD:
		held[k] = 0.0
	return {
		"sources": {"mint": 0.0, "debug": 0.0},
		"sinks": {"cleared": 0.0, "rot_loss": 0.0, "burned": 0.0, "milled": 0.0, "vei_fight": 0.0,
			"dungeon": _dungeon_sink, "pool_overflow": 0.0},
		"held": held,
	}


# ----------------------------------------------------------------- §5 views ----
# Every view is a fresh deep copy with `rev` first; an unknown id gives {}. view_relish
# (§5.8) sits with Relish, and the seed views (§5.15) with the runs.

static func _xy(p: Vector2) -> Array:
	return [float(p.x), float(p.y)]


func _world_size() -> Array:
	var sz: Variant = _cfgs.get("world", {}).get("size", [2048, 1440])
	return [float(sz[0]), float(sz[1])]


func _pool_cap() -> float:
	return float(_cfg().get("vei_pool_cap", 600.0))


## §5.1 · E2. Live at E1: t, the time controls, relics and essence with their caps, won,
## and the legacy readout (sign, drain_s, odds). Stocks are the legacy `res`; rates are 0.
func view_hud() -> Dictionary:
	var ro := _vei_readout()
	var stock := {
		"mint": -1.0, "workers": legacy.workers(), "bodies": float(res["bodies"]),
		"gold": float(res["gold"]), "bone": float(res["materials"]), "living": float(res["townsfolk"]),
	}
	var cap := {"bodies": _bodies_cap(), "living": legacy.town_stock("living_cap")}
	var rates: Array = []
	for id in HUD_RATE_IDS:
		rates.append({"id": id, "rate": 0.0, "stock": stock[id], "cap": cap.get(id, -1.0), "unit": _RATE_UNITS[id]})
	return {
		"rev": rev, "t": float(t), "time_scale": float(time_scale), "paused": paused, "rates": rates,
		"split": {"work": 0.0, "war": 0.0, "flood": 0.0},
		"valve": valve.duplicate(), "valve_target": valve_target.duplicate(),
		"workers_steady": 0.0,
		"relics": relics, "relics_cap": _cap_of("relics"), "essence": essence, "essence_cap": _cap_of("essence"),
		"sign": ro["sign"], "drain_s": ro["drain_s"], "odds": ro["odds"], "won": won,
	}


## §5.2 · E2: every RATE_IDS key, zero at E1.
func view_rates() -> Dictionary:
	var rates := {}
	for id in RATE_IDS:
		rates[id] = {"in": 0.0, "out": 0.0, "net": 0.0, "unit": _RATE_UNITS[id]}
	return {"rev": rev, "rates": rates}


func _lane(kind: String, from: String, to: String, rate: float) -> Dictionary:
	return {"id": "%s:%s:%s" % [kind, from, to], "from": from, "to": to, "kind": kind,
		"rate": rate, "bias": 1.0, "why": ""}


## §5.3 · E2. E1: one WAR lane per fort (world order) at the legacy dispatch rate, then
## the FLOOD lane to Vei at 0. Bias 1.0 and no callouts until E2.
func view_lanes() -> Dictionary:
	var lanes: Array = []
	for f in realm.forts:
		lanes.append(_lane("war", "covington", f["id"], float(f["r_in"])))
	lanes.append(_lane("flood", "covington", "vei", 0.0))
	return {"rev": rev, "lanes": lanes}


## §5.4 · E1 (held_count live from E2a).
func view_realm() -> Dictionary:
	var forts: Array = []
	var held := 0
	for f in realm.forts:
		forts.append(_fort_entry(f))
		if RealmSim.is_held(f):
			held += 1
	return {
		"rev": rev, "size": _world_size(),
		"covington": {"pos": _xy(realm.cov_pos)},
		"vei": {
			"pos": _xy(realm.vei_pos),
			"radius": float(_cfgs.get("world", {}).get("vei", {}).get("radius", 150.0)),
			"living_pool": float(realm.vei["living_pool"]), "pool_cap": _pool_cap(),
			"backlog": float(realm.vei["undead_queue"]),
		},
		"forts": forts, "held_count": held, "digest_q": quality(),
	}


## The fort Relish stands at (at_fort, or in its dungeon), or "".
func _standing_fort() -> String:
	var st: String = relish["state"]
	return relish["at"] if st == "at_fort" or st == "in_dungeon" else ""


func _simulacrum_charges(fort_id: String) -> float:
	var n := 0.0
	for s in realm.simulacra:
		if str(s.get("fort_id", "")) == fort_id:
			n += float(s.get("charges", 0.0))
	return n


## A fort in the view_fort shape, without `rev`. Live: masses, positions, war_in (WAR arriving,
## staging included), ship_in, held, held_s_left, relish_here, tide, redirect, siege, can_descend.
## Tithe, threat and warden are still stubs.
func _fort_entry(f: Dictionary) -> Dictionary:
	var id: String = f["id"]
	var why := _descend_reason(id)
	var fx := _relish_effects()
	var archetype := _warden_archetype(id)
	return {
		"id": id, "name": str(f["name"]), "tier": int(f["tier"]), "cap": float(f["cap"]),
		"pos": _xy(f["pos"]),
		"living": float(f["living"]), "undead": float(f["undead"]), "dead": float(f["dead"]),
		"space": float(realm.space(f)), "war_in": float(f["r_in"]), "ship_in": float(f["r_shipped"]),
		"held": RealmSim.is_held(f), "held_s_left": float(f.get("held_s", 0.0)),
		"flipped_count": int(f.get("flipped_count", 0)),
		"first_clear": not cleared_forts.has(id), "first_dungeon": _is_first_dungeon(id),
		"clears_since_retaken": int(f.get("clears_since_retaken", 0)), "yield_mult": 1.0,
		"warden": {"archetype": archetype, "tells": (_WARDEN_TELLS.get(archetype, []) as Array).duplicate()},
		"loot_hint": _loot_hint(id),
		"threat": {"party_strength": 0.0, "garrison_strength": 0.0, "risk": "low", "risk_pct": -1.0},
		"relish_here": _standing_fort() == id, "tide": fx["tide_fort"] == id, "redirect": fx["redirect_fort"] == id,
		"simulacrum_charges": _simulacrum_charges(id),
		"siege": _uids_at("fort:" + id),
		"tithe": {"targeted": false, "eta_s": -1.0, "wave_active": false},
		"can_descend": why == "", "reason": why,
	}


## §5.5 · E1. can_descend/reason are cmd_begin_dungeon(id)'s own check.
func view_fort(id: String) -> Dictionary:
	var f := realm.fort_by_id(id)
	if f.is_empty():
		return {}
	var out := {"rev": rev}
	out.merge(_fort_entry(f))
	return out


## §5.6 · E1. The one view that is not a copy: `field` is the live InfluenceField.
func view_field() -> Dictionary:
	return {
		"rev": rev, "field": field, "world_size": _world_size(),
		"tick_hz": float(_cfg().get("field", {}).get("tick_hz", 5.0)),
	}


## §5.7 · E1: the legacy village control, with live dominance.
func view_villages() -> Dictionary:
	var rate := float(_cfg().get("migrant_rate_per_town", 0.012))
	var out: Array = []
	for tw in towns:
		var owner: String = {"green": "player", "orange": "vei"}.get(tw["control"], "none")
		out.append({
			"id": str(tw["id"]), "name": str(tw["name"]), "pos": _xy(tw["pos"]), "owner": owner,
			"dominance": float(field.dominance_at(tw["pos"])), "migrants": rate if owner == "player" else 0.0,
		})
	return {"rev": rev, "villages": out}


## E1 stand-in for the E2 job ladder: `workers` fill each job's slots top-down in ladder
## order (buildings in lot order), each lot up to its staff cap.
## Returns {lots: {lot_id: staffed}, jobs: {job: [slots, staffed]}, idle: float}.
func _staffing(workers: float) -> Dictionary:
	var by_lot := {}
	var by_job := {}
	var left := workers
	for job in ladder:
		var slots := 0
		var staffed := 0.0
		for lot_id in _built_lots():
			var n := int(_jobs_of(lot_buildings[lot_id]["building_id"]).get(job, 0))
			if n <= 0:
				continue
			slots += n
			var room := float(n)
			var cap := int(staff_caps.get(lot_id, -1))
			if cap >= 0:
				room = minf(room, float(cap) - float(by_lot.get(lot_id, 0.0)))
			var take := clampf(room, 0.0, left)
			by_lot[lot_id] = float(by_lot.get(lot_id, 0.0)) + take
			staffed += take
			left -= take
		by_job[job] = [slots, staffed]
	return {"lots": by_lot, "jobs": by_job, "idle": left}


func _next_tier() -> Dictionary:
	var have := lot_buildings.size()
	var idx := TIERS.find(town_tier)
	if idx < 0 or idx >= TIERS.size() - 1:
		return {"tier": "", "have": have, "need": 0, "missing": []}
	var nt: String = TIERS[idx + 1]
	var spec: Dictionary = _sec("economy", "town").get("tiers", {}).get(nt, {})
	var missing: Array = []
	for b in spec.get("requires", []):
		if _count_built(str(b)) == 0:
			missing.append(str(b))
	return {"tier": nt, "have": have, "need": int(spec.get("buildings", 0)), "missing": missing}


## §5.9 · E2. E1: the BALANCE §0 start layout (buildings on lots from economy.json `opening`,
## lots from town.json) with the live legacy stocks, the stored settings (ladder, staff caps, haul target, foremen), the legacy convoy.
func view_town() -> Dictionary:
	var unlocked := _lots_unlocked()
	var lots: Array = []
	for l in _lots_cfg():
		var id := str(l.get("id", ""))
		lots.append({"id": id, "size": int(l.get("size", 1)), "unlocked": lots.size() < unlocked,
			"building_id": str(lot_buildings.get(id, {}).get("building_id", ""))})
	var workers := legacy.town_stock("workers")
	var st := _staffing(workers)
	var buildings: Array = []
	for lot_id in _built_lots():
		var bid: String = lot_buildings[lot_id]["building_id"]
		buildings.append({
			"lot_id": lot_id, "building_id": bid, "level": int(lot_buildings[lot_id]["level"]),
			"state": "active", "progress": 1.0, "slots": _slots_of(bid),
			"staffed": float(st["lots"].get(lot_id, 0.0)), "staff_cap": int(staff_caps.get(lot_id, -1)),
			"foreman": _foreman_of(lot_id), "output": {}, "upkeep": _upkeep_of(bid),
		})
	var jobs: Array = []
	for job in ladder:
		var js: Array = st["jobs"][job]
		if js[0] > 0:
			jobs.append({"id": job, "slots": js[0], "staffed": js[1]})
	var morale := float(_sec("economy", "morale").get("base", 0.6))
	return {
		"rev": rev, "tier": town_tier, "next_tier": _next_tier(), "lots": lots, "buildings": buildings,
		"ladder": ladder.duplicate(), "ladder_effective": ladder.duplicate(), "jobs": jobs,
		"workers": {
			"total": workers, "idle": float(st["idle"]), "in": 0.0, "rot": 0.0, "muster": 0.0, "steady": 0.0,
			"lifetime_s": float(_sec("economy", "worker").get("lifetime_s", 480.0)),
		},
		"living": legacy.town_stock("living"), "living_cap": legacy.town_stock("living_cap"),
		"migrants": 0.0, "departures": 0.0,
		"morale": {"value": morale, "target": morale, "factors": [{"id": "base", "delta": morale}]},
		"gold": legacy.town_stock("gold"), "bone": legacy.town_stock("bone"), "bodies": legacy.town_stock("bodies"),
		"bodies_cap": _bodies_cap(), "trade_rate": 0.0,
		"haul": {"target": haul_target, "current": legacy.haul_current(), "convoys": legacy.convoys()},
		"relish_home": relish["state"] == "home",
	}


## Free unlocked lots that fit a building of `size`, in lot order.
func _free_lots(size: int) -> Array:
	var out: Array = []
	var unlocked := _lots_unlocked()
	var i := 0
	for l in _lots_cfg():
		var id := str(l.get("id", ""))
		if i < unlocked and not lot_buildings.has(id) and int(l.get("size", 1)) >= size:
			out.append(id)
		i += 1
	return out


## view_catalog's reason, in order. Gold and bone are the town's stocks as view_town shows them.
func _build_gate(req: Dictionary, cost: Dictionary, lots: Array) -> String:
	if TIERS.find(req["tier"]) > TIERS.find(town_tier):
		return "needs_tier"
	if req["blueprint"] != "" and not blueprints.has(req["blueprint"]):
		return "needs_blueprint"
	if req["building"] != "" and _count_built(req["building"]) == 0:
		return "needs_building"
	if lots.is_empty():
		return "no_lot"
	if legacy.town_stock("gold") < cost["gold"]:
		return "no_gold"
	if legacy.town_stock("bone") < cost["bone"]:
		return "no_bone"
	if relics < cost["relics"]:
		return "no_relics"
	return ""


## §5.10 · E2 (crafts E3): buildings.json in file order, with live gating.
func view_catalog() -> Dictionary:
	var cfg := _buildings_cfg()
	var out: Array = []
	var bps: Array = []
	for bid in cfg:
		var def: Dictionary = cfg[bid]
		var r: Dictionary = def.get("requires", {})
		var req := {"tier": str(r.get("tier", "")), "blueprint": str(r.get("blueprint", "")),
			"building": str(r.get("building", ""))}
		var cost := _cost_of(def.get("cost", {}))
		var lots := _free_lots(int(def.get("lot_size", 1)))
		var why := _build_gate(req, cost, lots)
		out.append({
			"building_id": str(bid), "cost": cost, "upkeep": _upkeep_of(bid),
			"build_work": float(def.get("build_work", 0.0)), "lot_size": int(def.get("lot_size", 1)),
			"max_level": int(def.get("max_level", 1)), "count": _count_built(bid), "requires": req,
			"can_build": why == "", "reason": why, "lots": lots,
		})
		if req["blueprint"] != "" and not bps.has(req["blueprint"]):
			bps.append(req["blueprint"])
	var crafts: Array = []
	for id in CRAFT_IDS:
		var c: Dictionary = _sec("economy", "craft").get(id, {})
		var cost := {"essence": int(c.get("essence", 0)), "relics": int(c.get("relics", 0))}
		var why := ""
		if _count_built("ossuary_tower") == 0:
			why = "needs_building"
		elif essence < cost["essence"]:
			why = "no_essence"
		elif relics < cost["relics"]:
			why = "no_relics"
		crafts.append({"item_id": id, "cost": cost, "can_craft": why == "", "reason": why})
	var bp_list: Array = []
	for b in bps:
		bp_list.append({"id": b, "owned": blueprints.has(b)})
	return {"rev": rev, "buildings": out, "crafts": crafts, "blueprints": bp_list}


func _beat_id() -> int:
	var beat_s := float(_cfgs.get("pulse", {}).get("tempo_ms", 1714)) / 1000.0
	return int(floor(t / beat_s)) if beat_s > 0.0 else 0


## §5.11 · E3. E1 echoes cmd_set_stance: nothing fires, nothing is projected.
func view_stances() -> Dictionary:
	var slots := _stance_slots()
	var list: Array = []
	for id in STANCE_IDS:
		var idx := stances_on.find(id)
		list.append({"id": id, "on": idx >= 0, "suspended": idx >= slots, "active": false,
			"fired_beat_id": -1, "hold_s_left": 0.0, "projected": {}})
	return {"rev": rev, "slots": slots, "used": mini(stances_on.size(), slots), "beat_id": _beat_id(), "stances": list}


## §5.12 · E1. Simulacra and phylactery charges are E3 (0).
func view_inventory() -> Dictionary:
	var hs: Array = []
	for h in husks:
		hs.append({"uid": h["uid"], "kind": h["kind"]})
	var rs: Array = []
	for r in remnants:
		rs.append({"uid": r["uid"], "aspect": r["aspect"], "rarity": r["rarity"], "magnitude": int(r["magnitude"])})
	var bps := blueprints.duplicate()
	bps.sort()
	return {
		"rev": rev, "husks": hs, "remnants": rs, "blueprints": bps,
		"relics": relics, "relics_cap": _cap_of("relics"), "essence": essence, "essence_cap": _cap_of("essence"),
		"simulacra_ready": 0, "phylactery_charges": _phylactery_charges,
	}


## §5.12 · E1.
func view_big_undead() -> Dictionary:
	var out: Array = []
	for b in big_undead:
		out.append(_bu_entry(b))
	return {"rev": rev, "cap": _cap_of("big_undead"), "count": big_undead.size(), "big_undead": out}


## §5.12 · E1. The garrison and starter figures are §7.1's for the fort she stands at;
## strength is E2 (0).
func view_party() -> Dictionary:
	var out: Array = []
	for u in party_uids:
		var b := _find_uid(big_undead, u)
		if not b.is_empty():
			out.append(_bu_entry(b))
	var fid := _standing_fort()
	var g := _garrison(fid)
	return {"rev": rev, "party": out, "fort_id": fid, "garrison_units": g[0], "garrison_in_mass": g[1],
		"starter_units": _starter_units(fid), "strength": 0.0}


## §5.13 · E3. E1: each legacy vat is a ready clone; no phylactery; the legacy death rule
## (a clone if a vat is ready, else unmade) with an immediate respawn.
func view_backups() -> Dictionary:
	var n := _vat_slots()
	var vats: Array = []
	for i in n:
		vats.append({"slot": i, "staffed": i < vats_staffed.size() and bool(vats_staffed[i]), "grow": 1.0, "ready": true})
	var outcome := "clone" if n > 0 else "unmade"
	var loses: Array = []
	if not party_uids.is_empty():
		loses.append("party")
	loses.append("unbanked_loot")
	if outcome == "unmade":
		loses.append("morale")
	return {
		"rev": rev, "phylactery_charges": _phylactery_charges, "phylactery_max_per_dungeon": _phylactery_max(),
		"clones_ready": n, "vats": vats, "death": {"outcome": outcome, "respawn_s": 0.0, "loses": loses},
		"dead_s_left": float(relish["dead_s_left"]),
	}


## §5.14 · E1. The readout is the legacy one (diff_ema = the raw diff until the E2 EMA);
## tithe is E2, fronts E3 (assigned is live). can_begin/reason are cmd_begin_boss()'s check.
func view_vei() -> Dictionary:
	var ro := _vei_readout()
	var why := _boss_reason()
	return {
		"rev": rev, "backlog": float(realm.vei["undead_queue"]), "living_pool": float(realm.vei["living_pool"]),
		"pool_cap": _pool_cap(), "diff": float(ro["diff"]), "diff_ema": float(ro["diff"]),
		"sign": ro["sign"], "drain_s": ro["drain_s"], "odds": ro["odds"], "digest_q": quality(),
		"fronts": _fronts(true), "fronts_required": _fronts_required(), "fronts_met": 0,
		"tithe": {"target": "", "eta_s": -1.0, "warning": false, "wave_active": false, "wave_s_left": 0.0},
		"can_begin": why == "", "reason": why, "won": won,
	}


# ----------------------------------------------------------------- §3 tick ----
func quality() -> float:
	return legacy.quality()


## §3 step 3: the current valve moves toward the target along the straight line, by at most
## `valve.slew_per_s · dt` of L1 distance, so its components always sum to 1.
func _slew_valve(dt: float) -> void:
	var rate := float(_cfg().get("valve", {}).get("slew_per_s", 0.10))
	var l1 := 0.0
	for k in valve:
		l1 += absf(float(valve_target[k]) - float(valve[k]))
	var max_step := rate * dt
	if l1 <= max_step + 1e-12:
		valve = valve_target.duplicate()
		return
	var f := max_step / l1
	for k in valve:
		valve[k] = float(valve[k]) + (float(valve_target[k]) - float(valve[k])) * f


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
	# §3 step 9: once per tick(dt) call, after the loop, whether or not a substep ran
	field.advance(int(_cfg().get("field", {}).get("slice_budget_cells", 0)))
	return n


func _tick(dt: float) -> void:
	t += dt
	var cfg: Dictionary = _cfg()
	# §3 step 3: the valve slews, then splits the mint. Interim mint until TownSim lands: the legacy
	# mint, P_base + P_per_slab · slabs with the legacy slab bonus (it burns slab bodies).
	_slew_valve(dt)
	var mint := legacy.mint_step(dt)
	_split = {"mint": mint, "work": mint * valve["work"], "war": mint * valve["war"], "flood": mint * valve["flood"]}
	work_pending += _split["work"] * dt  # WORK has no consumer until TownSim
	# §3 step 4: Relish's travel and state
	_step_relish_travel(dt)
	# §3 step 5: RealmSim, pure on these inputs; its events get this substep's t
	var fx := _relish_effects()
	var rcfg: Dictionary = cfg.get("relish", {})
	_realm_inputs = {
		"war": _split["war"], "flood": _split["flood"], "digest_q": quality(),
		"tide_fort": fx["tide_fort"], "tide_bias": float(rcfg.get("tide_bias", 3.0)),
		"redirect_fort": fx["redirect_fort"], "redirect_rate": float(rcfg.get("raise_rate", 4.0)),
	}
	realm.step(dt, _realm_inputs)
	for ev in realm.drain_events():
		_emit(ev)
	legacy.tick_town(dt, green_towns)
	legacy.tick_gather(dt)
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


func _inject_sources(dt: float) -> void:
	var fcfg: Dictionary = _cfg().get("field", {})
	var src_main: float = float(fcfg.get("src_main", 3.0))
	var src_fort: float = float(fcfg.get("src_fort", 1.1))
	field.inject(realm.cov_pos, true, src_main * (1.0 + 0.15 * legacy.town["slabs"]) * dt, 2)
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


# ------------------------------------------- E1 legacy forwarders and death ----
func raid_seed(fort_id: String) -> Dictionary:
	return legacy.raid_seed(fort_id)


func town_snapshot() -> Dictionary:
	return legacy.town_snapshot(green_towns)


func apply_town_result(r: Dictionary) -> void:
	stats["sims_built"] += legacy.apply_town_result(r)


func boss_seed() -> Dictionary:
	return legacy.boss_seed()


## Legacy death (E1 rule, §8.3 step 10): a legacy vat gives a clone, otherwise she is
## unmade and the army scatters; she respawns home at once. The caller has closed the run.
func _legacy_death(run_id: int) -> void:
	stats["deaths"] += 1
	var at_node: String = relish["at"]
	var clone := legacy.death_scatter()
	_emit({"type": "relish_died", "outcome": "clone" if clone else "unmade", "in_place": false,
		"at": at_node, "run_id": run_id, "respawn_s": 0.0})
	_place_relish("covington")
	_emit({"type": "relish_respawned", "with_clone": clone, "at": "covington"})


# ------------------------------------------------------------ apply_result ----
func _ar_fail(reason: String, errors: Array = []) -> Dictionary:
	return {"ok": false, "reason": reason, "errors": errors, "minted": []}


## §4.5. Refusals are checked in the documented order and change nothing (no rev, no events,
## no uids, no rng). Ints may arrive as integral floats, so every int is read with int().
func apply_result(kind: String, result: Dictionary) -> Dictionary:
	if kind != "raid" and kind != "boss":
		return _ar_fail("unknown_kind")
	if not Results.has_v2(result):
		return _ar_fail("unknown_v")
	var errs := Results.validate(kind, result)
	if not errs.is_empty():
		return _ar_fail("invalid", errs)
	var run_id := int(result["run_id"])
	if applied_runs.has(run_id):
		return _ar_fail("duplicate_run")
	if run.is_empty() or int(run["run_id"]) != run_id:
		return _ar_fail("wrong_run")
	if run["kind"] != kind:
		return _ar_fail("wrong_kind")
	if int(result["seed_rev"]) != int(run["seed_rev"]):
		return _ar_fail("stale_seed")
	var sd: Dictionary = run["seed"]
	if kind == "raid":
		if str(result["fort_id"]) != str(run["fort_id"]):
			return _ar_fail("wrong_fort")
		if int(result["revived_in_place"]) > mini(int(sd["phylactery_charges"]), int(sd["phylactery_max_per_dungeon"])):
			return _ar_fail("bad_revives")
	var party := _seed_party_uids(sd)
	for uid in result["party_lost"]:
		if not party.has(uid):
			return _ar_fail("bad_party")
	if kind == "boss":
		var bs: Dictionary = result["backups_spent"]
		if int(bs["phylactery"]) > int(sd["phylactery_charges"]) or int(bs["clones"]) > int(sd["clones_ready"]):
			return _ar_fail("bad_backups")
	var minted: Array = []
	if kind == "raid":
		minted = _writeback_raid(result)
	else:
		_writeback_boss(result)
	applied_runs.append(run_id)
	while applied_runs.size() > 32:
		applied_runs.remove_at(0)
	rev += 1
	return {"ok": true, "reason": "", "errors": [], "minted": minted}


func _seed_party_uids(sd: Dictionary) -> Array:
	var out: Array = []
	for e in sd["party"]:
		out.append(e["uid"])
	return out


## Removes a big undead for good (death in a run), from the party too.
func _remove_big_undead(uid: String) -> void:
	for i in big_undead.size():
		if big_undead[i]["uid"] == uid:
			big_undead.remove_at(i)
			break
	party_uids.erase(uid)


## §8.3 raid steps 1-12 with the E1 rules. The result is already validated and matched to the
## open run. Returns the minted uids.
func _writeback_raid(r: Dictionary) -> Array:
	var sd: Dictionary = run["seed"]
	var run_id: int = run["run_id"]
	var fort_id: String = run["fort_id"]
	var f := realm.fort_by_id(fort_id)
	stats["raids"] += 1
	# 1. kills, against the live fort
	var k := minf(float(r["killed_living_mass"]), float(f["living"]))
	f["living"] -= k
	f["dead"] += k
	# 2. the flip
	var flip_ev := {}
	if r["warden_beaten"]:
		f["dead"] += f["living"]
		f["living"] = 0.0
		var fl: Dictionary = _cfg().get("flip", {})
		var hold_s := float(fl.get("hold_s", 300.0)) * (1.0 + float(fl.get("tier_mult", 0.25)) * float(f["tier"]))
		realm.hold(fort_id, hold_s)  # RealmSim counts it down and stops her shipping there
		f["flipped_count"] = int(f.get("flipped_count", 0)) + 1
		f["clears_since_retaken"] = int(f.get("clears_since_retaken", 0)) + 1
		flip_ev = {"type": "fort_flipped", "fort_id": fort_id, "run_id": run_id, "hold_s": hold_s}
	# 3. raised mass comes out of the dead
	var raised_total := 0.0
	for e in r["raised"]:
		raised_total += float(e["mass"])
	var raised_in := minf(raised_total, float(f["dead"]))
	f["dead"] -= raised_in
	# 4. what leaves cannot exceed what went in plus what was raised
	var garrison_out := float(r["garrison_mass"])
	var chaff := float(r["chaff_mass"])
	var garrison_in := float(sd["garrison_in_mass"])
	if garrison_out + chaff > garrison_in + raised_in + 1e-9:
		var sc := (garrison_in + raised_in) / (garrison_out + chaff)
		garrison_out *= sc
		chaff *= sc
	# 5. the net garrison delta, clamped at the live undead
	var undead_before: float = f["undead"]
	f["undead"] = maxf(0.0, undead_before + garrison_out - garrison_in)
	var undead_delta: float = f["undead"] - undead_before
	# 6. chaff leaves with Relish, but never more than actually left the fort (no mass from the clamp)
	chaff = minf(chaff, maxf(0.0, raised_in - undead_delta))
	realm.vei["undead_queue"] += chaff
	# 7. whatever went in and did not come out, net of the step 5 clamp (>= 0 by construction)
	_dungeon_sink += raised_in - undead_delta - chaff
	stats["raised_total"] += raised_in
	# 8. loot
	var loot: Dictionary = r["loot"]
	var relics_in := mini(int(loot["relics"]), maxi(0, _cap_of("relics") - relics))
	relics += relics_in
	var essence_in := mini(int(loot["essence"]), maxi(0, _cap_of("essence") - essence))
	essence += essence_in
	var new_bps: Array = []
	for bp in loot["blueprints"]:
		if not blueprints.has(bp):
			blueprints.append(bp)
			new_bps.append(bp)
	var minted: Array = []
	for h in loot["husks"]:
		var uid := _mint_uid("h")
		husks.append({"uid": uid, "kind": str(h["kind"]), "rarity": "common"})
		minted.append(uid)
	for m in loot["remnants"]:
		var uid := _mint_uid("r")
		remnants.append({"uid": uid, "aspect": str(m["aspect"]), "rarity": str(m["rarity"]),
			"magnitude": int(m["magnitude"])})
		minted.append(uid)
	cleared_forts[fort_id] = true
	first_dungeon_id = ""
	# 9. the dead party members go; each in-place revive spends a phylactery charge
	_phylactery_charges = maxi(0, _phylactery_charges - int(r["revived_in_place"]))
	for uid in r["party_lost"]:
		_remove_big_undead(uid)
	# 12. E1 parity: soldiers and elites into the legacy army (before a death scatters it, as before)
	legacy.add_raised(r["raised"])
	var died: bool = r["relish_died"]
	var party := _seed_party_uids(sd)
	run = {}
	_emit({"type": "loot_banked", "run_id": run_id, "fort_id": fort_id, "relics": relics_in,
		"essence": essence_in, "blueprints": new_bps, "minted": minted.duplicate()})
	if not flip_ev.is_empty():
		_emit(flip_ev)
	# 10. death: the whole party is lost (A8), then the legacy rule; 11. otherwise she stays
	if died:
		for uid in party:
			_remove_big_undead(uid)
		_legacy_death(run_id)
	else:
		relish["state"] = "at_fort"
	return minted


## §8.3 boss steps 1-6 with the E1 rules.
func _writeback_boss(r: Dictionary) -> void:
	var sd: Dictionary = run["seed"]
	var run_id: int = run["run_id"]
	var did_win: bool = r["won"]
	var bs: Dictionary = r["backups_spent"]
	var clones := int(bs["clones"])
	var deaths := int(r["relish_deaths"])
	var final_death := deaths == int(bs["phylactery"]) + clones + 1
	if did_win:
		won = true
	else:
		var keep := float(_cfgs.get("vei", {}).get("loss_backlog_keep", 0.35))
		realm.vei["undead_queue"] *= keep
		for uid in _seed_party_uids(sd):
			_remove_big_undead(uid)
		legacy.boss_loss_scatter()
	for uid in r["party_lost"]:
		_remove_big_undead(uid)
	_phylactery_charges = maxi(0, _phylactery_charges - int(bs["phylactery"]))
	legacy.spend_clones(clones)  # legacy vats are the clones at E1
	run = {}
	var cleared: Array = []
	for fid in r["fronts_cleared"]:
		cleared.append(str(fid))
	_emit({"type": "vei_result", "run_id": run_id, "won": did_win, "fronts_cleared": cleared,
		"relish_deaths": deaths, "backlog_after": float(realm.vei["undead_queue"])})
	if final_death:
		_legacy_death(run_id)
	else:
		relish["state"] = "at_vei"


# ------------------------------------------------------------ §9 persistence ----
# The save spec, its checker and the file plumbing are SaveIO (scripts/sim/save_io.gd).

## §9.1. A deep copy that survives JSON; the open run is written in its forfeited form.
func to_dict() -> Dictionary:
	var rl := {
		"state": relish["state"], "at": relish["at"], "target": relish["target"],
		"pos": (relish["pos"] as Array).duplicate(), "heading": relish["heading"],
		"dead_s_left": relish["dead_s_left"], "respawn_with_clone": relish["respawn_with_clone"],
	}
	if not run.is_empty():
		var at: String = run["fort_id"]
		rl = {"state": "at_vei" if run["kind"] == "boss" else "at_fort", "at": at, "target": "",
			"pos": _node_xy(at), "heading": relish["heading"], "dead_s_left": 0.0, "respawn_with_clone": false}
	var forts: Array = []
	for f in realm.forts:
		forts.append({
			"id": f["id"], "living": f["living"], "undead": f["undead"], "dead": f["dead"],
			"held_s": float(f.get("held_s", 0.0)), "flipped_count": int(f.get("flipped_count", 0)),
			"clears_since_retaken": int(f.get("clears_since_retaken", 0)),
			"r_in": f["r_in"], "r_drain": f["r_drain"], "r_shipped": f["r_shipped"],
			"r_dead_out": f["r_dead_out"], "r_raised": f["r_raised"],
		})
	var villages: Array = []
	for tw in towns:
		villages.append({"id": str(tw["id"]), "owner": {"green": "player", "orange": "vei"}.get(tw["control"], "none")})
	var lots: Array = []
	var lot_ids := lot_buildings.keys()
	lot_ids.sort()
	for id in lot_ids:
		lots.append({"lot_id": id, "building_id": lot_buildings[id]["building_id"], "level": int(lot_buildings[id]["level"])})
	var husk_list: Array = []
	for h in husks:
		husk_list.append({"uid": h["uid"], "kind": h["kind"], "rarity": h["rarity"]})
	var remnant_list: Array = []
	for r in remnants:
		remnant_list.append({"uid": r["uid"], "aspect": r["aspect"], "rarity": r["rarity"], "magnitude": int(r["magnitude"])})
	var bus: Array = []
	for b in big_undead:
		bus.append({"uid": b["uid"], "name": b["name"], "kind": b["kind"], "role": b["role"],
			"place": b["place"], "front": b["front"], "stats": (b["stats"] as Dictionary).duplicate()})
	var vats: Array = []
	for i in _vat_slots():
		vats.append({"slot": i, "staffed": i < vats_staffed.size() and bool(vats_staffed[i]), "grow": 1.0})
	var led := ledger()
	var d := {
		"v": SAVE_VERSION, "api_version": API_VERSION, "seed": rng_seed, "rng": str(rng.state),
		"t": t, "acc": _acc, "next_run_id": next_run_id, "next_uid": next_uid,
		"applied_runs": applied_runs.duplicate(),
		"relish": rl,
		"valve": {"target": valve_target.duplicate(), "current": valve.duplicate()},
		"realm": {
			"forts": forts, "cov": realm.cov.duplicate(), "vei": realm.vei.duplicate(),
			"simulacra": realm.simulacra.duplicate(true), "elapsed": realm.elapsed,
			"cleared_total": realm.cleared_total, "raised_by_sims": realm.raised_by_sims,
			"tithe": _tithe.duplicate(true),
		},
		"villages": villages,
		"town": {"tier": town_tier, "lots": lots, "ladder": ladder.duplicate(), "staff_caps": staff_caps.duplicate(),
			"haul": {"target": haul_target}},
		"stances": {"on": stances_on.duplicate(), "hold": _stance_hold.duplicate()},
		"inventory": {"husks": husk_list, "remnants": remnant_list, "blueprints": blueprints.duplicate(),
			"relics": relics, "essence": essence, "simulacra_ready": 0},
		"big_undead": bus,
		"party": party_uids.duplicate(),
		"backups": {"phylactery_charges": _phylactery_charges, "clones_ready": _vat_slots(), "vats": vats},
		"readout": _readout.duplicate(),
		"ledger": {"sources": led["sources"], "sinks": led["sinks"]},
		"won": won, "stats": stats.duplicate(),
		"legacy": legacy.to_dict(),
		"cleared_forts": cleared_forts.keys(), "first_dungeon": first_dungeon_id,
	}
	(d["cleared_forts"] as Array).sort()
	return SaveIO.canon(d)


## §9.1 `static migrate`: one version at a time up to SAVE_VERSION (the steps are SaveIO's). `{}` on
## failure (no `v`, a `v` that is not a whole number from 1 up, a version from the future, or a
## missing step). v1 is the identity: it returns a deep copy.
static func migrate(d: Dictionary) -> Dictionary:
	return SaveIO.migrate(d, SAVE_VERSION)


## The number in a uid: "h12" -> 12, anything else 0.
static func _uid_num(uid: String) -> int:
	return int(uid.substr(1)) if uid.length() > 1 and uid.substr(1).is_valid_int() else 0


## §9.1. Resets in place from a save. `{ok, reason}`: `corrupt` (wrong shape, a node or id the
## configs do not know), `bad_version` (a `v` from the future, or one that cannot be migrated).
## Nothing changes on a refusal; on success `rev` rises by 1.
func from_dict(d: Dictionary) -> Dictionary:
	if not d.has("v") or not SaveIO.fits(d["v"], TYPE_FLOAT):
		return {"ok": false, "reason": "corrupt"}
	var m := migrate(d)
	if m.is_empty():
		return {"ok": false, "reason": "bad_version"}
	if SaveIO.problem(m, _cfgs) != "":
		return {"ok": false, "reason": "corrupt"}
	_apply_save(m)
	return {"ok": true, "reason": ""}


## Applies a migrated, checked save. Types are restored here: ints from floats, Vector2 from [x, y].
func _apply_save(m: Dictionary) -> void:
	_build_realm_field_towns()
	rng_seed = m["seed"]
	game_seed = rng_seed.to_int()
	rng.seed = game_seed  # first: setting the seed resets the state
	rng.state = (m["rng"] as String).to_int()
	t = float(m["t"])
	_acc = float(m["acc"])
	applied_runs = []
	for id in m["applied_runs"]:
		applied_runs.append(int(id))
	var top := maxi(maxi(next_uid, int(m["next_uid"])), 1)
	for h in m["inventory"]["husks"]:
		top = maxi(top, _uid_num(h["uid"]) + 1)
	for r in m["inventory"]["remnants"]:
		top = maxi(top, _uid_num(r["uid"]) + 1)
	for b in m["big_undead"]:
		top = maxi(top, _uid_num(b["uid"]) + 1)
	next_uid = top
	next_run_id = maxi(next_run_id, int(m["next_run_id"]))
	var rl: Dictionary = m["relish"]
	relish = {
		"state": rl["state"], "at": rl["at"], "target": rl["target"],
		"pos": [float(rl["pos"][0]), float(rl["pos"][1])], "heading": float(rl["heading"]),
		"dead_s_left": float(rl["dead_s_left"]), "respawn_with_clone": bool(rl["respawn_with_clone"]),
	}
	valve_target = _valve_of(m["valve"]["target"])
	valve = _valve_of(m["valve"]["current"])
	var rm: Dictionary = m["realm"]
	for e in rm["forts"]:
		var f := realm.fort_by_id(e["id"])
		for k in ["living", "undead", "dead", "r_in", "r_drain", "r_shipped", "r_dead_out", "r_raised"]:
			f[k] = float(e[k])
		realm.hold(e["id"], float(e["held_s"]))
		f["flipped_count"] = int(e["flipped_count"])
		f["clears_since_retaken"] = int(e["clears_since_retaken"])
	for k in realm.cov:
		realm.cov[k] = float(rm["cov"][k])
	for k in realm.vei:
		realm.vei[k] = float(rm["vei"][k])
	realm.simulacra = []
	for s in rm["simulacra"]:
		var e: Dictionary = (s as Dictionary).duplicate(true)
		e["charges"] = float(e["charges"])
		e["rate"] = float(e["rate"])
		realm.simulacra.append(e)
	realm.elapsed = float(rm["elapsed"])
	realm.cleared_total = float(rm["cleared_total"])
	realm.raised_by_sims = float(rm["raised_by_sims"])
	_tithe = (rm["tithe"] as Dictionary).duplicate(true)
	var owners := {}
	for v in m["villages"]:
		owners[v["id"]] = v["owner"]
	green_towns = 0
	for tw in towns:
		tw["control"] = {"player": "green", "vei": "orange"}.get(owners.get(tw["id"], "none"), "none")
		if tw["control"] == "green":
			green_towns += 1
	var tm: Dictionary = m["town"]
	town_tier = tm["tier"]
	lot_buildings = {}
	for l in tm["lots"]:
		lot_buildings[l["lot_id"]] = {"building_id": l["building_id"], "level": int(l["level"])}
	ladder = []
	for j in tm["ladder"]:
		ladder.append(str(j))
	staff_caps = {}
	for k in tm["staff_caps"]:
		staff_caps[k] = int(tm["staff_caps"][k])
	haul_target = tm["haul"]["target"]
	stances_on = []
	for st in m["stances"]["on"]:
		stances_on.append(str(st))
	_stance_hold = {}
	for k in m["stances"]["hold"]:
		_stance_hold[k] = float(m["stances"]["hold"][k])
	var inv: Dictionary = m["inventory"]
	husks = []
	for h in inv["husks"]:
		husks.append({"uid": h["uid"], "kind": h["kind"], "rarity": h["rarity"]})
	remnants = []
	for r in inv["remnants"]:
		remnants.append({"uid": r["uid"], "aspect": r["aspect"], "rarity": r["rarity"], "magnitude": int(r["magnitude"])})
	blueprints = []
	for b in inv["blueprints"]:
		blueprints.append(str(b))
	relics = int(inv["relics"])
	essence = int(inv["essence"])
	big_undead = []
	for b in m["big_undead"]:
		var st := {}
		for k in STATS:
			st[k] = float(b["stats"][k])
		big_undead.append({"uid": b["uid"], "name": b["name"], "kind": b["kind"], "role": b["role"],
			"stats": st, "place": b["place"], "front": b["front"]})
	party_uids = []
	for u in m["party"]:
		party_uids.append(str(u))
	vats_staffed = []
	for v in m["backups"]["vats"]:
		var slot := int(v["slot"])
		if slot >= 0 and slot < 1024:
			while vats_staffed.size() <= slot:
				vats_staffed.append(false)
			vats_staffed[slot] = bool(v["staffed"])
	_phylactery_charges = int(m["backups"]["phylactery_charges"])
	_readout = {"diff_ema": float(m["readout"]["diff_ema"]), "q_raise_ema": float(m["readout"]["q_raise_ema"])}
	_dungeon_sink = float(m["ledger"]["sinks"]["dungeon"])
	won = bool(m["won"])
	var sm: Dictionary = m["stats"]
	stats = {"raised_total": float(sm["raised_total"]), "raids": int(sm["raids"]), "deaths": int(sm["deaths"]),
		"sims_built": int(sm["sims_built"])}
	legacy.from_dict(m["legacy"])
	cleared_forts = {}
	for id in m["cleared_forts"]:
		cleared_forts[str(id)] = true
	first_dungeon_id = str(m["first_dungeon"])
	# session state: nothing of the old session survives a load
	run = {}
	_field_acc = 0.0
	_events = []
	time_scale = 1.0
	paused = false
	realm.digest_q = quality()
	work_pending = 0.0
	_split = {"mint": 0.0, "work": 0.0, "war": 0.0, "flood": 0.0}
	_realm_inputs = {}
	_prewarm_field()
	rev += 1


static func _valve_of(v: Dictionary) -> Dictionary:
	return {"work": float(v["work"]), "war": float(v["war"]), "flood": float(v["flood"])}


## economy.json sim.autosave_s: real seconds between the shell's autosaves.
func autosave_s() -> float:
	return float(_cfgs.get("economy", {}).get("sim", {}).get("autosave_s", 30.0))


# ------------------------------------------------------- §4.1 save and load ----
## "1:04 · Village · odds 0.08": the clock as h:mm, the town tier, the Vei odds.
@warning_ignore("integer_division")
func _summary() -> String:
	var mins := int(t / 60.0)
	return "%d:%02d · %s · odds %.2f" % [mins / 60, mins % 60, town_tier.capitalize(), float(_vei_readout()["odds"])]


func cmd_save(slot: String) -> Dictionary:
	var out := {"ok": false, "reason": "", "saved_at": 0, "path": ""}
	if not SaveIO.slot_ok(slot):
		out["reason"] = "bad_slot"
	elif realm == null:
		out["reason"] = "write_failed"  # no game to save
	else:
		var saved_at := int(Time.get_unix_time_from_system())
		var d := to_dict()
		d["slot"] = slot
		d["saved_at"] = saved_at
		d["summary"] = _summary()
		var path := "%s/%s.json" % [save_dir, slot]
		if SaveIO.write_atomic(path, JSON.stringify(d)):
			out = {"ok": true, "reason": "", "saved_at": saved_at, "path": path}
		else:
			out["reason"] = "write_failed"
	if out["ok"]:
		rev += 1
		if slot == "auto":
			_emit({"type": "autosaved", "slot": slot, "saved_at": out["saved_at"]})
	else:
		_emit({"type": "save_failed", "slot": slot, "reason": out["reason"]})
	return out


func cmd_load(slot: String) -> Dictionary:
	if not run.is_empty():
		return {"ok": false, "reason": "busy"}
	if not SaveIO.slot_ok(slot):
		return {"ok": false, "reason": "bad_slot"}
	var d := SaveIO.read_file("%s/%s.json" % [save_dir, slot])
	if d.is_empty():
		return {"ok": false, "reason": "no_save"}
	var r := from_dict(d)
	if r["ok"]:
		return {"ok": true, "reason": ""}
	return {"ok": false, "reason": "bad_version" if r["reason"] == "bad_version" else "no_save"}


## §4.1: `[{slot, saved_at, summary}]`, newest first (ties by slot). Not a command: no rev bump.
func list_saves() -> Array[Dictionary]:
	return SaveIO.list_saves(save_dir)


## §4.6, E1. Loads <fixture_dir>/<name>.json through from_dict.
func cmd_debug_load_fixture(name: String) -> Dictionary:
	if not debug_enabled:
		return {"ok": false, "reason": "not_debug"}
	if not run.is_empty():
		return {"ok": false, "reason": "busy"}
	if not FIXTURES.has(name):
		return {"ok": false, "reason": "unknown_fixture"}
	var d := SaveIO.read_file("%s/%s.json" % [fixture_dir, name])
	if d.is_empty() or not from_dict(d)["ok"]:
		return {"ok": false, "reason": "bad_fixture"}
	return {"ok": true, "reason": ""}


## Recursively loads every *.json under `dir` into a Dictionary keyed by the
## filename without extension. Directories starting with "." are skipped.
## Files are walked in sorted order so the result is deterministic. On a
## basename collision the first file wins and an error names both paths.
## A file that fails to parse is reported and skipped. A missing dir is {}.
## Each duplicate or parse failure also appends one string to `errors`, so
## callers (the test suite) can fail on them.
static func load_configs(dir: String, errors: Array = []) -> Dictionary:
	return SaveIO.load_configs(dir, errors)
