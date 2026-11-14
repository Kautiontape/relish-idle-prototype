class_name GameState
extends RefCounted
## All game state and logic, headless. The Game autoload is a thin shell over one
## of these. Configs are injected through setup(); randomness comes from `rng`.
## Files in scripts/sim/ never reference an autoload or Engine (a lint test
## enforces this). No signals: consumers poll
## `rev` and drain_events(). The contract is docs/STATE-API.md.

const API_VERSION := 3
const SAVE_VERSION := 2
const ARRIVE_EPS := 0.01  # px left at or under which Relish has arrived
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
## The mass ledger (scripts/sim/ledger.gd; no class_name, see there).
const Ledger := preload("res://scripts/sim/ledger.gd")
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
## How long a lane's `why` callout lasts, in sim seconds (STATE-API §5.3).
const _WHY_S := 10.0

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
## The WORK mass the valve sent in the last substep. TownSim takes all of it in the next substep
## (§3 step 2: WORK arrives one substep late), so it never accumulates. Held mass; saved as
## town.work_pending.
var work_pending := 0.0
var blueprints: Array = []  # owned blueprint ids (= the building ids they unlock), banked by apply_result
var applied_runs: Array = []  # the last 32 run ids apply_result closed (for duplicate_run); kept across new games like next_run_id
## The mass ledger's sources and sinks since the new game (§4.7, MECHANICS §2.1); saved as `ledger`.
var _ledger := Ledger.new()
# --- settings GameState keeps (TownSim holds the job ladder and the staff caps) ---
var haul_target := "auto"  # cmd_set_haul_target: "auto" or a fort id, TownSim's step input
var stances_on: Array = []  # stance ids switched on, oldest first; the newest are suspended first
var vats_staffed: Array = []  # bool per vat slot
## view_backups' stub stock (E3 grows clones in vats): ready clones. A death spends one (§8.3 step
## 10, the E1-safe rule); the vat slots are these clones until E3.
var clones_ready := 0
# --- E3 placeholders: saved and restored so a fixture can carry them; nothing reads them yet ---
var _phylactery_charges := 0  # backups.phylactery_charges (E3)
var _stance_hold := {}  # stance id -> hold seconds left (E3)
# --- the readouts (§3 step 8, MECHANICS §2.2, §3.5); saved as the `readout` block ---
## diff_ema: the EMA of the differential over readout.ema_s. q_raise_ema: the mass-weighted EMA of
## raised circle scores behind q_raise (`ema_score`, from 50); only apply_result moves it (IDLE I2).
var _readout := {"diff_ema": 0.0, "q_raise_ema": 50.0}
var _diff := 0.0  # the raw differential of the last substep, mass/s (session only)
# --- lane callouts (§5.3): lane id -> [why, until t]; the last substep's causes snapshot ---
var _why := {}
var _lane_prev := {}
# --- the town: Covington's economy is TownSim's (MECHANICS §4); the tier is GameState's ---
## Created once and reset in place (new game, load), so it is never replaced.
var town_sim := TownSim.new()
var town_tier := "hamlet"

# --- the villages and the shared flags ---
var towns: Array = []
var green_towns := 0
var won := false
var stats := {"raised_total": 0.0, "raids": 0, "deaths": 0, "sims_built": 0}

var _cfgs := {}
var _acc := 0.0
## mass/s of the last substep (step 3): the mint, its valve shares, and `muster` (TownSim's, which
## `war` includes). Session only.
var _split := {"mint": 0.0, "work": 0.0, "war": 0.0, "flood": 0.0, "muster": 0.0}
## The realm's streams of the last substep for view_rates (§5.2), mass/s, as [in, out]: `corpses`
## (Σ forts: kills and redirected garrison kills in; Relish's and the simulacra's raises and k_clear
## out, the haul added at view time) and `backlog` (Vei's undead queue: its inflow in, her digestion
## out). Session only.
var _realm_flows := {"corpses": [0.0, 0.0], "backlog": [0.0, 0.0]}
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
	town_sim.setup(cfgs)


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
	town_sim.new_game()  # BALANCE §0: the start buildings on their lots, the stocks, the default ladder
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
	_split = {"mint": 0.0, "work": 0.0, "war": 0.0, "flood": 0.0, "muster": 0.0}
	_realm_flows = {"corpses": [0.0, 0.0], "backlog": [0.0, 0.0]}
	_realm_inputs = {}
	first_dungeon_id = str(opening.get("first_dungeon", "old-sluice"))
	cleared_forts = {}
	_ledger.reset(Ledger.total(_held()))  # the opening: what the board holds now
	_phylactery_charges = 0
	clones_ready = 0
	_readout = {"diff_ema": 0.0, "q_raise_ema": 50.0}
	_diff = 0.0
	_stance_hold = {}
	blueprints = []
	haul_target = "auto"
	stances_on = []
	vats_staffed = []
	town_tier = "hamlet"
	relish = {
		"state": "home", "at": "covington", "target": "",
		"pos": [float(realm.cov_pos.x), float(realm.cov_pos.y)], "heading": 0.0,
		"dead_s_left": 0.0, "respawn_with_clone": false,
	}
	_reset_lanes()
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
	var pw: Dictionary = _sec("economy", "sim")
	var pw_dt := float(pw.get("prewarm_dt", 0.2))
	for i in int(pw.get("prewarm_ticks", 90)):
		_inject_sources(pw_dt)
		field.tick(pw_dt)
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


## Arrival: snaps to the node and settles. A journey with at most ARRIVE_EPS px left is over.
func _arrive(tgt: String) -> void:
	relish["pos"] = _node_xy(tgt)
	relish["state"] = _state_at_node(tgt)
	relish["at"] = tgt
	relish["target"] = ""


## Substep step 4 (§3): straight-line travel and arrival.
func _step_relish_travel(dt: float) -> void:
	if relish["state"] != "travelling":
		return
	var tgt: String = relish["target"]
	var dist := _dist_to(tgt)
	var step := travel_speed() * dt
	if step >= dist - ARRIVE_EPS:
		_arrive(tgt)
		return
	_face(tgt)
	var p: Array = relish["pos"]
	var q := _node_xy(tgt)
	var f := step / dist
	relish["pos"] = [p[0] + (q[0] - p[0]) * f, p[1] + (q[1] - p[1]) * f]


## What her position does now (MECHANICS §3.3): `tide_fort` is her fort while she stands at it or is
## in its dungeon; `redirect_fort` only while she stands at it (not in its dungeon). Nothing while
## dead, travelling, at Vei or home (home's rot is TownSim's step input, the slab E3's). The step-5
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
		"phylactery_charges": _phylactery_charges, "clones_ready": clones_ready,
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
	var target := _normalised(work / m, war / m, flood / m)
	if target != valve_target:
		_valve_callout()
	valve_target = target
	rev += 1
	return {"ok": true, "reason": "", "target": valve_target.duplicate()}


## Stores the target; TownSim's convoy takes it as a step input ("auto": the fort with the most dead
## above job.haul.auto_min_dead). A convoy already out finishes its trip first.
func cmd_set_haul_target(target: String) -> Dictionary:
	if target != "auto" and realm.fort_by_id(target).is_empty():
		return {"ok": false, "reason": "unknown_fort", "haul_target": ""}
	haul_target = target
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


## The sustained-differential readout (MECHANICS §3.5) from `_diff` and the saved EMA: sign is ±1
## past ±readout.sign_eps, else 0; drain_s is backlog / −EMA while the EMA < 0, else −1.0 (and −1.0
## if that would not be finite); odds = backlog / (backlog + K).
func _vei_readout() -> Dictionary:
	var ema := float(_readout["diff_ema"])
	var eps := float(_sec("realm", "readout").get("sign_eps", 0.05))
	var backlog: float = realm.vei["undead_queue"]
	var drain := -1.0
	if ema < 0.0:
		var d := backlog / -ema
		drain = d if is_finite(d) else -1.0
	return {
		"diff": _diff, "diff_ema": ema,
		"odds": realm.odds(),
		"sign": 1 if ema > eps else (-1 if ema < -eps else 0),
		"drain_s": drain,
	}


## §3 step 8: `diff = inflow − digestion` (mass/s: what entered Vei's undead queue last substep, less
## the undead she took from it), and its EMA over readout.ema_s. Lumps (dungeon chaff, grants) are
## not in the inflow.
func _update_readout(dt: float, inflow: float, digestion: float) -> void:
	_diff = inflow - digestion
	var ema_s := float(_sec("realm", "readout").get("ema_s", 120.0))
	var a := 1.0 - exp(-dt / ema_s) if ema_s > 0.0 else 1.0
	var ema := float(_readout["diff_ema"])
	_readout["diff_ema"] = ema + a * (_diff - ema)


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
		"digest_q": digest_q(),
		"phylactery_charges": _phylactery_charges,
		"phylactery_max_per_dungeon": _phylactery_max(),
		"clones_ready": clones_ready,
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
		"odds": ro["odds"], "sign": ro["sign"], "drain_s": ro["drain_s"], "digest_q": digest_q(),
		"vei_capacity": float(_cfg().get("R_vei", 50.0)),
		"fronts": _fronts(false),
		"fronts_required": _fronts_required(),
		"party": _party_entries(true),
		"phylactery_charges": _phylactery_charges, "clones_ready": clones_ready,
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


## Its role is SlabLogic's for its highest stat (town.json slab.role_by_stat; ties go in STATS
## order), so a granted big undead carries a role id the town and dungeon scenes know.
func _mint_big_undead() -> String:
	var uid := _mint_uid("u")
	var st := {}
	var top := ""
	for s in STATS:
		st[s] = rng.randf_range(1.0, 10.0)
		if top == "" or st[s] > st[top]:
			top = s
	var roles: Variant = _sec("town", "slab").get("role_by_stat", {})
	big_undead.append({
		"uid": uid, "name": "Big " + uid, "kind": HUSK_KINDS[rng.randi_range(0, HUSK_KINDS.size() - 1)],
		"role": str((roles if roles is Dictionary else {}).get(top, "hollow")), "stats": st, "place": "crypt", "front": "",
	})
	return uid


## A capped stock's cap: its base in economy.json plus the buildings' (Reliquary `relic_cap` and
## `essence_cap`; big undead: `per_crypt_level` per Crypt level above 1).
func _cap_of(section: String) -> int:
	var sec := _sec("economy", section)
	var n := int(sec.get("cap", 1 << 30))
	match section:
		"relics":
			n += int(town_sim.built_effect("relic_cap"))
		"essence":
			n += int(town_sim.built_effect("essence_cap"))
		"big_undead":
			for lot_id in town_sim.buildings:
				var b: Dictionary = town_sim.buildings[lot_id]
				if b["building_id"] == "crypt":
					n += int(sec.get("per_crypt_level", 0)) * maxi(0, int(b["level"]) - 1)
	return n


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
				applied[k] = _grant_town(k, v)
				if k == "bodies" or k == "workers":
					_ledger.source("debug", float(applied[k]) * (worker_mass() if k == "workers" else 1.0))
			"backlog":
				var old: float = realm.vei["undead_queue"]
				realm.vei["undead_queue"] = maxf(0.0, old + v)
				applied[k] = realm.vei["undead_queue"] - old
				_ledger.source("debug", float(applied[k]))
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


## A grant to one of TownSim's stocks (workers in workers, the rest in their units): floored at 0;
## bodies and living are capped at body_cap() and living_cap(), but a grant never pulls an over-cap
## stock down (E1 I4). Workers are a float (staffing is fractional) and restaff at once. Returns the
## applied delta.
func _grant_town(key: String, v: float) -> float:
	var old := float(town_sim.get(key))
	var hi := INF
	if key == "bodies":
		hi = town_sim.body_cap()
	elif key == "living":
		hi = town_sim.living_cap()
	var now := clampf(old + v, 0.0, maxf(hi, old))
	town_sim.set(key, now)
	if key == "workers":
		town_sim.restaff()
	return now - old


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
				_valve_callout()
			"forge_level":
				town_sim.forge = {"level": int(float(v)), "progress": 0.0}  # TownSim's q forge level
			"forts":
				for id in v:
					var f := realm.fort_by_id(str(id))
					for m in v[id]:
						var old: float = f[m]
						f[m] = minf(float(v[id][m]), float(f["cap"]))
						_ledger.source("debug", float(f[m]) - old)
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
# The town is TownSim's (BALANCE §0 at a new game). The job ladder and staff caps drive its
# staffing. The build family (T2.4) pays from TownSim's stocks and the relics, and constructs
# through TownSim's build job. Raise, craft and deploy are still §1.1 stubs (id checks, then ok
# with zero extras, no change); stances and vat staffing are stored and echoed (E3).

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


## The lot ids a tier opens (economy.json town.tiers.<tier>.lots; BALANCE §5).
func _tier_lots(tier: String) -> Array:
	var d: Variant = _sec("economy", "town").get("tiers", {}).get(tier, {}).get("lots", [])
	return d if d is Array else []


func _lot_unlocked(lot_id: String) -> bool:
	return _tier_lots(town_tier).has(lot_id)


## Lots holding a building (built, or a first build under way), in lot order.
func _built_lots() -> Array:
	var out: Array = []
	for l in _lots_cfg():
		var id := str(l.get("id", ""))
		if town_sim.buildings.has(id):
			out.append(id)
	return out


## Buildings of that id that have finished their first build (level ≥ 1); every building when "".
func _count_built(building_id: String) -> int:
	var n := 0
	for lot_id in town_sim.buildings:
		var b: Dictionary = town_sim.buildings[lot_id]
		if int(b["level"]) >= 1 and (building_id == "" or b["building_id"] == building_id):
			n += 1
	return n


## A `unique` building (buildings.json; the Crypt) that already stands on a lot, finished or under
## construction: a second one is refused (`unique`).
func _unique_taken(building_id: String) -> bool:
	if not bool(_buildings_cfg().get(building_id, {}).get("unique", false)):
		return false
	for lot_id in town_sim.buildings:
		if town_sim.buildings[lot_id]["building_id"] == building_id:
			return true
	return false


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


## A building's `requires` as {tier, blueprint, building} strings.
func _req_of(building_id: String) -> Dictionary:
	var r: Variant = _buildings_cfg().get(building_id, {}).get("requires", {})
	var d: Dictionary = r if r is Dictionary else {}
	return {"tier": str(d.get("tier", "")), "blueprint": str(d.get("blueprint", "")), "building": str(d.get("building", ""))}


## The tier, blueprint and building gates, in order: needs_tier, needs_blueprint, needs_building.
func _req_reason(req: Dictionary) -> String:
	if TIERS.find(req["tier"]) > TIERS.find(town_tier):
		return "needs_tier"
	if req["blueprint"] != "" and not blueprints.has(req["blueprint"]):
		return "needs_blueprint"
	if req["building"] != "" and _count_built(req["building"]) == 0:
		return "needs_building"
	return ""


## no_gold, no_bone, no_relics: gold and bone are TownSim's stocks, as view_town shows them.
func _afford_reason(cost: Dictionary) -> String:
	if town_sim.gold < cost["gold"]:
		return "no_gold"
	if town_sim.bone < cost["bone"]:
		return "no_bone"
	if relics < cost["relics"]:
		return "no_relics"
	return ""


func _pay(cost: Dictionary) -> void:
	town_sim.gold -= float(cost["gold"])
	town_sim.bone -= float(cost["bone"])
	relics -= int(cost["relics"])


## What a construction heading to `level` cost: the building's cost for level 1, else the upgrade's
## level_costs[level - 2].
func _construction_cost(building_id: String, level: int) -> Dictionary:
	var def: Dictionary = _buildings_cfg().get(building_id, {})
	if level <= 1:
		return _cost_of(def.get("cost", {}))
	var lc: Variant = def.get("level_costs", [])
	var arr: Array = lc if lc is Array else []
	return _cost_of(arr[level - 2]) if level - 2 < arr.size() else _zero_cost()


## §4.3 · E2: pays the cost at once and starts construction on a free, unlocked lot. TownSim's
## `build` job advances it; `building_started` comes out of the next substep, `building_done` when
## the work is in. A `unique` building (the Crypt) is refused while one stands (api_version 3).
func cmd_build(building_id: String, lot_id: String) -> Dictionary:
	var def: Dictionary = _buildings_cfg().get(building_id, {})
	var lot := _lot(lot_id)
	var cost := _construction_cost(building_id, 1)
	var why := ""
	if def.is_empty():
		why = "unknown_building"
	elif lot.is_empty():
		why = "unknown_lot"
	elif _unique_taken(building_id):
		why = "unique"
	elif not _lot_unlocked(lot_id):
		why = "lot_locked"
	elif town_sim.buildings.has(lot_id):
		why = "lot_taken"
	elif int(lot.get("size", 1)) < int(def.get("lot_size", 1)):
		why = "lot_too_small"
	else:
		why = _req_reason(_req_of(building_id))
		if why == "":
			why = _afford_reason(cost)
	if why != "":
		return {"ok": false, "reason": why, "cost": {}}
	var r := town_sim.start_construction(lot_id, building_id, 1)
	if not r["ok"]:
		return {"ok": false, "reason": str(r["reason"]), "cost": {}}  # unreachable: every gate is checked above
	_pay(cost)
	rev += 1
	return {"ok": true, "reason": "", "cost": cost}


## §4.3 · E2: pays level_costs and constructs the next level. The building works at its old level
## meanwhile (TownSim). Reasons in order: unknown_lot, empty_lot, under_construction, unpaid,
## max_level, needs_tier, no_gold, no_bone, no_relics.
func cmd_upgrade(lot_id: String) -> Dictionary:
	var b: Dictionary = town_sim.buildings.get(lot_id, {})
	var why := ""
	var level := 0
	var cost := {}
	if _lot(lot_id).is_empty():
		why = "unknown_lot"
	elif b.is_empty():
		why = "empty_lot"
	elif b["state"] == "constructing":
		why = "under_construction"
	elif b["state"] == "unpaid":
		why = "unpaid"
	else:
		var bid: String = b["building_id"]
		level = int(b["level"]) + 1
		if level > int(_buildings_cfg().get(bid, {}).get("max_level", 1)):
			why = "max_level"
		else:
			cost = _construction_cost(bid, level)
			why = _req_reason({"tier": _req_of(bid)["tier"], "blueprint": "", "building": ""})
			if why == "":
				why = _afford_reason(cost)
	if why != "":
		return {"ok": false, "reason": why, "level": 0, "cost": {}}
	var r := town_sim.start_construction(lot_id, b["building_id"], level)
	if not r["ok"]:
		return {"ok": false, "reason": str(r["reason"]), "level": 0, "cost": {}}  # unreachable
	_pay(cost)
	rev += 1
	return {"ok": true, "reason": "", "level": level, "cost": cost}


## A foreman placed on a lot that is cleared goes back to the crypt.
func _foreman_home(lot_id: String) -> void:
	for b in big_undead:
		if b["place"] == "town:" + lot_id:
			b["place"] = "crypt"


## §4.3 · E2: removes a finished building, no refund. The Crypt is protected.
func cmd_demolish(lot_id: String) -> Dictionary:
	var b: Dictionary = town_sim.buildings.get(lot_id, {})
	var why := ""
	if _lot(lot_id).is_empty():
		why = "unknown_lot"
	elif b.is_empty():
		why = "empty_lot"
	elif b["state"] == "constructing":
		why = "under_construction"
	elif b["building_id"] == "crypt":
		why = "protected"
	if why != "":
		return {"ok": false, "reason": why}
	town_sim.demolish(lot_id)
	_foreman_home(lot_id)
	rev += 1
	return {"ok": true, "reason": ""}


## §4.3 · E2: cancels the construction under way and refunds its cost in full (relics clamped to the
## cap). A cancelled first build frees the lot; a cancelled upgrade keeps the old level.
func cmd_cancel_build(lot_id: String) -> Dictionary:
	if _lot(lot_id).is_empty():
		return {"ok": false, "reason": "unknown_lot", "refund": {}}
	var r := town_sim.cancel_construction(lot_id)
	if not r["ok"]:
		return {"ok": false, "reason": str(r["reason"]), "refund": {}}
	var cost := _construction_cost(str(r["building_id"]), int(r["level"]))
	town_sim.gold += float(cost["gold"])
	town_sim.bone += float(cost["bone"])
	var back := mini(int(cost["relics"]), maxi(0, _cap_of("relics") - relics))
	relics += back
	if not r["upgrade"]:
		_foreman_home(lot_id)
	rev += 1
	return {"ok": true, "reason": "", "refund": {"gold": float(cost["gold"]), "bone": float(cost["bone"]), "relics": back}}


## The ladder, a permutation of JOB_IDS, top first: TownSim's workers fill job slots in this order.
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
	town_sim.set_ladder(order)
	rev += 1
	return {"ok": true, "reason": "", "order": town_sim.ladder.duplicate()}


## A lot's staff cap (-1 = none) for TownSim's staffing. A cap above the slots is accepted.
func cmd_set_staff_cap(lot_id: String, cap: int) -> Dictionary:
	var why := ""
	if _lot(lot_id).is_empty():
		why = "unknown_lot"
	elif not town_sim.buildings.has(lot_id):
		why = "empty_lot"
	elif _slots_of(town_sim.buildings[lot_id]["building_id"]) == 0:
		why = "no_jobs"
	elif cap < -1:
		why = "bad_cap"
	if why != "":
		return {"ok": false, "reason": why, "cap": 0}
	town_sim.set_staff_cap(lot_id, cap)
	rev += 1
	return {"ok": true, "reason": "", "cap": cap}


## stance.base_slots, plus the Guildhall's, plus 1 while Relish is home (MECHANICS §4.5).
func _stance_slots() -> int:
	var n := int(_sec("economy", "stance").get("base_slots", 2)) + int(town_sim.built_effect("stance_slots"))
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
		elif not town_sim.buildings.has(lot_id):
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


## Vat slots: the Chapel of Vats' `vat_slots` per level (E3 makes them grow clones).
func _vat_slots() -> int:
	return int(town_sim.built_effect("vat_slots"))


## A vat as view_backups and the save show it. Until E3 a vat is ready while a clone stock covers it.
func _vat_entry(i: int) -> Dictionary:
	var ready := i < clones_ready
	return {"slot": i, "staffed": i < vats_staffed.size() and bool(vats_staffed[i]), "grow": 1.0 if ready else 0.0, "ready": ready}


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
## {sources, sinks, held}: mass totals since the new game, and every pool of mass now (Ledger).
## Σheld + Σsinks == Σsources at every substep boundary (MECHANICS §2.1).
func ledger() -> Dictionary:
	return {"sources": _ledger.sources.duplicate(), "sinks": _ledger.sinks.duplicate(), "held": _held()}


func _held() -> Dictionary:
	return Ledger.held(realm, town_sim, work_pending, worker_mass())


## economy.json worker.mass: the mass of one worker.
func worker_mass() -> float:
	return float(_sec("economy", "worker").get("mass", 40.0))


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


## Every RATE_IDS stream as {id: [in, out]} per second, the one source of view_rates and view_hud
## (§5.2):
## - mint, work, war, flood: the last substep's valve split (session only), each a pass-through;
## - workers, bodies, gold, bone, living: TownSim's last step (saved with it). Bodies come in as rot
##   return plus the trip-averaged haul (_haul_rate), so a convoy's arrival is not a spike;
## - corpses, backlog: the realm's last substep (_realm_flows, session only); the haul leaves the
##   corpses at the same trip-averaged rate the bodies receive it.
func _rate_io() -> Dictionary:
	var r: Dictionary = town_sim.rates
	var haul := _haul_rate()
	var out := {
		"workers": [float(r["workers"]["in"]), float(r["workers"]["out"])],
		"bodies": [float(r["bodies"]["rot"]) + haul, float(r["bodies"]["out"])],
		"gold": [float(r["gold"]["in"]), float(r["gold"]["out"])],
		"bone": [float(r["bone"]["in"]), float(r["bone"]["out"])],
		"living": [float(r["living"]["in"]), float(r["living"]["out"])],
		"corpses": [float(_realm_flows["corpses"][0]), float(_realm_flows["corpses"][1]) + haul],
		"backlog": [float(_realm_flows["backlog"][0]), float(_realm_flows["backlog"][1])],
	}
	for id in ["mint", "work", "war", "flood"]:
		out[id] = [float(_split[id]), float(_split[id])]
	return out


## The convoy's trip-averaged corpse rate (mass/s): the last landed trip's load over its round trip,
## while a convoy is out; 0 while none is.
func _haul_rate() -> float:
	if (town_sim.haul["convoys"] as Array).is_empty():
		return 0.0
	return float(town_sim.rates["haul_trip"])


## TownSim's steady-state workforce: this substep's worker inflow × the lifetime now (§4.1).
func _workers_steady() -> float:
	return float(town_sim.rates["workers"]["in"]) * town_sim.lifetime_s(relish["state"] == "home")


## §5.1 · E2. Live: t, the time controls, relics and essence with their caps, won, the readout
## (sign, drain_s, odds), the valve and its split, the mint's rate, and TownSim's stocks, caps and
## net rates.
func view_hud() -> Dictionary:
	var ro := _vei_readout()
	var ts := town_sim
	var stock := {"mint": -1.0, "workers": ts.workers, "bodies": ts.bodies, "gold": ts.gold, "bone": ts.bone, "living": ts.living}
	var cap := {"bodies": ts.body_cap(), "living": ts.living_cap()}
	var io := _rate_io()
	var rates: Array = []
	for id in HUD_RATE_IDS:
		var rate := float(io[id][0]) if id == "mint" else float(io[id][0]) - float(io[id][1])
		rates.append({"id": id, "rate": rate, "stock": float(stock[id]), "cap": float(cap.get(id, -1.0)), "unit": _RATE_UNITS[id]})
	return {
		"rev": rev, "t": float(t), "time_scale": float(time_scale), "paused": paused, "rates": rates,
		"split": {"work": float(_split["work"]), "war": float(_split["war"]), "flood": float(_split["flood"])},
		"valve": valve.duplicate(), "valve_target": valve_target.duplicate(),
		"workers_steady": _workers_steady(),
		"relics": relics, "relics_cap": _cap_of("relics"), "essence": essence, "essence_cap": _cap_of("essence"),
		"sign": ro["sign"], "drain_s": ro["drain_s"], "odds": ro["odds"], "won": won,
	}


## §5.2 · E2, live for every id from E2a (_rate_io): the valve streams and the realm's corpses and
## backlog are the last substep's (session only), the town's are TownSim's. `net` is in − out (0 for
## the pass-throughs); backlog's is view_vei's raw `diff`.
func view_rates() -> Dictionary:
	var rates := {}
	var io := _rate_io()
	for id in RATE_IDS:
		var e: Array = io[id]
		rates[id] = {"in": float(e[0]), "out": float(e[1]), "net": float(e[0]) - float(e[1]), "unit": _RATE_UNITS[id]}
	return {"rev": rev, "rates": rates}


static func _lane_id(kind: String, from: String, to: String) -> String:
	return "%s:%s:%s" % [kind, from, to]


## Appends a lane when it carries mass or a live callout (zero-rate lanes are otherwise omitted).
func _add_lane(lanes: Array, kind: String, from: String, to: String, rate: float, bias: float) -> void:
	var id := _lane_id(kind, from, to)
	var why := _why_of(id)
	if rate > 0.0 or why != "":
		lanes.append({"id": id, "from": from, "to": to, "kind": kind, "rate": float(rate), "bias": float(bias), "why": why})


## §5.3 · E2. Kinds in LANE_KINDS order, forts in world order: war covington→fort (staging at held
## forts included) and covington→vei (WAR that fell through); flood covington→vei and fort→vei
## (drain); work covington→covington (the valve's WORK); dead fort→vei; living vei→fort (shipping and
## surges); haul fort→covington (the convoy's fort, trip-averaged); redirect fort→fort (raised by
## Relish or a simulacrum). Rates are last substep's mass/s.
func view_lanes() -> Dictionary:
	var lanes: Array = []
	var tide: String = _relish_effects()["tide_fort"]
	var tide_bias := float(_cfg().get("relish", {}).get("tide_bias", 3.0))
	var wave: Dictionary = realm.tithe.get("wave", {})
	var wave_fort: String = str(wave.get("fort_id", ""))
	for f in realm.forts:
		_add_lane(lanes, "war", "covington", f["id"], f["r_in"], tide_bias if f["id"] == tide else 1.0)
	_add_lane(lanes, "war", "covington", "vei", realm.r_war_to_vei, 1.0)
	_add_lane(lanes, "flood", "covington", "vei", realm.r_flood, 1.0)
	for f in realm.forts:
		_add_lane(lanes, "flood", f["id"], "vei", f["r_drain"], 1.0)
	_add_lane(lanes, "work", "covington", "covington", float(_split["work"]), 1.0)
	for f in realm.forts:
		_add_lane(lanes, "dead", f["id"], "vei", f["r_dead_out"], 1.0)
	for f in realm.forts:
		_add_lane(lanes, "living", "vei", f["id"], f["r_shipped"], float(wave.get("mult", 1.0)) if f["id"] == wave_fort else 1.0)
	var haul_fort := str(town_sim.haul["current"])
	var haul_rate := _haul_rate()
	for f in realm.forts:
		_add_lane(lanes, "haul", f["id"], "covington", haul_rate if f["id"] == haul_fort else 0.0, 1.0)
	for f in realm.forts:
		_add_lane(lanes, "redirect", f["id"], f["id"], f["r_raised"], 1.0)
	return {"rev": rev, "lanes": lanes}


func _why_of(lane_id: String) -> String:
	var e: Variant = _why.get(lane_id)
	return str(e[0]) if e != null and t < float(e[1]) else ""


## Starts a lane's callout for _WHY_S sim seconds; the newest cause wins.
func _callout(lane_id: String, why: String) -> void:
	_why[lane_id] = [why, t + _WHY_S]


func _valve_callout() -> void:
	for f in realm.forts:
		_callout(_lane_id("war", "covington", f["id"]), "valve")
	_callout(_lane_id("war", "covington", "vei"), "valve")
	_callout(_lane_id("flood", "covington", "vei"), "valve")


## What the lane causes compare between substeps: her tide and redirect forts, the held forts and
## the forts with a live simulacrum.
func _lane_state() -> Dictionary:
	var fx := _relish_effects()
	var held := {}
	for f in realm.forts:
		if RealmSim.is_held(f):
			held[f["id"]] = true
	var sims := {}
	for sm in realm.simulacra:
		if float(sm.get("charges", 0.0)) > 0.0:
			sims[str(sm.get("fort_id", ""))] = true
	return {"tide": fx["tide_fort"], "redirect": fx["redirect_fort"], "held": held, "sims": sims}


## Clears the callouts and takes the current state as the baseline (new game, load).
func _reset_lanes() -> void:
	_why = {}
	_lane_prev = _lane_state()


## Once per substep, after RealmSim: starts the callouts for what changed since the last substep
## (`evs` are this substep's realm events), and drops the expired ones.
func _note_lane_causes(evs: Array) -> void:
	var now := _lane_state()
	var was := _lane_prev
	if now["tide"] != was["tide"]:
		if was["tide"] != "":
			_callout(_lane_id("war", "covington", was["tide"]), "Relish left")
		if now["tide"] != "":
			_callout(_lane_id("war", "covington", now["tide"]), "Relish here")
	if now["redirect"] != was["redirect"]:
		for pair in [[was["redirect"], "Relish left"], [now["redirect"], "Relish here"]]:
			if pair[0] != "":
				_callout(_lane_id("redirect", pair[0], pair[0]), pair[1])
				_callout(_lane_id("dead", pair[0], "vei"), pair[1])
	for id in now["held"]:
		if not was["held"].has(id):
			_callout(_lane_id("living", "vei", id), "held")
			_callout(_lane_id("war", "covington", id), "staging")
	for id in was["held"]:
		if not now["held"].has(id):
			_callout(_lane_id("living", "vei", id), "retaken")
			_callout(_lane_id("war", "covington", id), "retaken")
	for id in now["sims"].keys() + was["sims"].keys():
		if now["sims"].has(id) != was["sims"].has(id):
			_callout(_lane_id("redirect", id, id), "simulacrum")
			_callout(_lane_id("dead", id, "vei"), "simulacrum")
	for ev in evs:
		if ev["type"] == "tithe_wave":
			_callout(_lane_id("living", "vei", ev["fort_id"]), "tithe wave")
	for id in _why.keys():
		if float(_why[id][1]) <= t:
			_why.erase(id)
	_lane_prev = now


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
		"forts": forts, "held_count": held, "digest_q": digest_q(),
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
## staging included), ship_in (tithe surges included), held, held_s_left, relish_here, tide,
## redirect, siege, tithe, can_descend. Threat and warden are still stubs.
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
		"tithe": _fort_tithe(id),
		"can_descend": why == "", "reason": why,
	}


## view_fort.tithe: targeted while a warning names the fort or its wave runs; eta_s is the time to
## the warned wave, 0.0 while the wave runs, else -1.0.
func _fort_tithe(id: String) -> Dictionary:
	var w: Dictionary = realm.tithe.get("warning", {})
	var wv: Dictionary = realm.tithe.get("wave", {})
	var warned: bool = not w.is_empty() and w["fort_id"] == id
	var active: bool = not wv.is_empty() and wv["fort_id"] == id
	var eta := maxf(0.0, float(realm.tithe["next_s"])) if warned else (0.0 if active else -1.0)
	return {"targeted": warned or active, "eta_s": eta, "wave_active": active}


## view_vei.tithe: the running wave's fort (eta_s 0.0), else the warned one (eta_s to its wave),
## else "" and -1.0 (no target chosen yet).
func _vei_tithe() -> Dictionary:
	var w: Dictionary = realm.tithe.get("warning", {})
	var wv: Dictionary = realm.tithe.get("wave", {})
	var out := {"target": "", "eta_s": -1.0, "warning": not w.is_empty(), "wave_active": not wv.is_empty(), "wave_s_left": 0.0}
	if not wv.is_empty():
		out["target"] = str(wv["fort_id"])
		out["eta_s"] = 0.0
		out["wave_s_left"] = maxf(0.0, float(wv["s_left"]))
	elif not w.is_empty():
		out["target"] = str(w["fort_id"])
		out["eta_s"] = maxf(0.0, float(realm.tithe["next_s"]))
	return out


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


## §5.7 · E1: the legacy village control, with live dominance. A player village sends TownSim
## economy.json town.migrant_rate living/s (its held_villages input).
func view_villages() -> Dictionary:
	var rate := float(_sec("economy", "town").get("migrant_rate", 0.012))
	var out: Array = []
	for tw in towns:
		var owner: String = {"green": "player", "orange": "vei"}.get(tw["control"], "none")
		out.append({
			"id": str(tw["id"]), "name": str(tw["name"]), "pos": _xy(tw["pos"]), "owner": owner,
			"dominance": float(field.dominance_at(tw["pos"])), "migrants": rate if owner == "player" else 0.0,
		})
	return {"rev": rev, "villages": out}


func _next_tier() -> Dictionary:
	var have := _count_built("")
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


## TownSim's convoy as §5.9 convoys: out is Covington → fort, back is fort → Covington.
func _convoys() -> Array:
	var out: Array = []
	for c in town_sim.haul["convoys"]:
		var fid := str(c["fort"])
		var back: bool = c["phase"] == "back"
		out.append({"from": fid if back else "covington", "to": "covington" if back else fid,
			"phase": str(c["phase"]), "t": float(c["t"]), "load": float(c["load"])})
	return out


## §5.9 · E2: TownSim's town. Lots from town.json; buildings with their state, progress, slots,
## staffing, cap, foreman, output and upkeep; the ladder and its jobs; the workforce, the living,
## morale and its factors, the stocks and caps, trade, the convoy. Stances (ladder_effective) are E3.
func view_town() -> Dictionary:
	var ts := town_sim
	var lots: Array = []
	for l in _lots_cfg():
		var id := str(l.get("id", ""))
		lots.append({"id": id, "size": int(l.get("size", 1)), "unlocked": _lot_unlocked(id),
			"building_id": str(ts.buildings.get(id, {}).get("building_id", ""))})
	var p_per_pit := float(_cfg().get("P_per_pit", 6.0))
	var haul_rate := _haul_rate()
	var staffed: Dictionary = ts.staffing.get("lots", {})
	var buildings: Array = []
	for lot_id in _built_lots():
		var b: Dictionary = ts.buildings[lot_id]
		var bid: String = b["building_id"]
		buildings.append({
			"lot_id": lot_id, "building_id": bid, "level": int(b["level"]),
			"state": str(b["state"]), "progress": float(b["progress"]), "slots": ts.lot_slots(lot_id),
			"staffed": float(staffed.get(lot_id, 0.0)), "staff_cap": int(b["staff_cap"]),
			"foreman": _foreman_of(lot_id), "output": ts.lot_output(lot_id, p_per_pit, haul_rate), "upkeep": _upkeep_of(bid),
		})
	var jobs: Array = []
	var by_job: Dictionary = ts.staffing.get("jobs", {})
	for job in ts.ladder:
		var js: Dictionary = by_job.get(job, {})
		if int(js.get("slots", 0)) > 0:
			jobs.append({"id": str(job), "slots": int(js["slots"]), "staffed": float(js["staffed"])})
	var r: Dictionary = ts.rates
	var w: Dictionary = r["workers"]
	return {
		"rev": rev, "tier": town_tier, "next_tier": _next_tier(), "lots": lots, "buildings": buildings,
		"ladder": ts.ladder.duplicate(), "ladder_effective": ts.ladder.duplicate(), "jobs": jobs,
		"workers": {
			"total": ts.workers, "idle": float(ts.staffing.get("idle", 0.0)), "in": float(w["in"]), "rot": float(w["rot"]),
			"muster": float(w["muster"]), "steady": _workers_steady(), "lifetime_s": ts.lifetime_s(relish["state"] == "home"),
		},
		"living": ts.living, "living_cap": ts.living_cap(),
		"migrants": float(r["living"]["in"]), "departures": float(r["living"]["out"]),
		"morale": {"value": ts.morale, "target": ts.morale_target(), "factors": ts.morale_factors()},
		"gold": ts.gold, "bone": ts.bone, "bodies": ts.bodies, "bodies_cap": ts.body_cap(), "trade_rate": float(r["trade_rate"]),
		"haul": {"target": haul_target, "current": str(ts.haul["current"]), "convoys": _convoys()},
		"relish_home": relish["state"] == "home",
	}


## Free unlocked lots that fit a building of `size`, in lot order.
func _free_lots(size: int) -> Array:
	var out: Array = []
	for l in _lots_cfg():
		var id := str(l.get("id", ""))
		if _lot_unlocked(id) and not town_sim.buildings.has(id) and int(l.get("size", 1)) >= size:
			out.append(id)
	return out


## view_catalog's reason, in order: the gates of `cmd_build` (unique first, as cmd_build checks it
## before the lot), then no_lot (no free unlocked lot fits), then what it costs.
func _build_gate(building_id: String, req: Dictionary, cost: Dictionary, lots: Array) -> String:
	if _unique_taken(building_id):
		return "unique"
	var why := _req_reason(req)
	if why == "" and lots.is_empty():
		why = "no_lot"
	if why == "":
		why = _afford_reason(cost)
	return why


## §5.10 · E2 (crafts E3): buildings.json in file order, with live gating.
func view_catalog() -> Dictionary:
	var cfg := _buildings_cfg()
	var out: Array = []
	var bps: Array = []
	for bid in cfg:
		var def: Dictionary = cfg[bid]
		var req := _req_of(bid)
		var cost := _cost_of(def.get("cost", {}))
		var lots := _free_lots(int(def.get("lot_size", 1)))
		var why := _build_gate(bid, req, cost, lots)
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


## §5.13 · E3. Until E3: clones_ready is the stub stock and each ready clone is a vat slot; the
## E1-safe death rule (a clone if one is ready, else unmade with the morale shock) with an
## immediate respawn.
func view_backups() -> Dictionary:
	var n := _vat_slots()
	var vats: Array = []
	for i in n:
		vats.append(_vat_entry(i))
	var outcome := "clone" if clones_ready > 0 else "unmade"
	var loses: Array = []
	if not party_uids.is_empty():
		loses.append("party")
	loses.append("unbanked_loot")
	if outcome == "unmade":
		loses.append("morale")
	return {
		"rev": rev, "phylactery_charges": _phylactery_charges, "phylactery_max_per_dungeon": _phylactery_max(),
		"clones_ready": clones_ready, "vats": vats, "death": {"outcome": outcome, "respawn_s": 0.0, "loses": loses},
		"dead_s_left": float(relish["dead_s_left"]),
	}


## §5.14 · E2 (fronts E3; assigned is live). The readout, q and the tithe are live.
## can_begin/reason are cmd_begin_boss()'s check.
func view_vei() -> Dictionary:
	var ro := _vei_readout()
	var why := _boss_reason()
	return {
		"rev": rev, "backlog": float(realm.vei["undead_queue"]), "living_pool": float(realm.vei["living_pool"]),
		"pool_cap": _pool_cap(), "diff": float(ro["diff"]), "diff_ema": float(ro["diff_ema"]),
		"sign": ro["sign"], "drain_s": ro["drain_s"], "odds": ro["odds"], "digest_q": digest_q(),
		"fronts": _fronts(true), "fronts_required": _fronts_required(), "fronts_met": 0,
		"tithe": _vei_tithe(),
		"can_begin": why == "", "reason": why, "won": won,
	}


# ----------------------------------------------------------------- §3 tick ----
func _qcfg() -> Dictionary:
	return _sec("realm", "q")


## Vei's digest cost q (MECHANICS §2.2): clamp(q0 + q_forge · forge_level + Σ foreman_q + q_raise,
## 1, q_max), q_raise = q_raise_max · max(0, (ema_score − 50) / 50). forge_level is TownSim's (the
## forge job's levels); Σ foreman_q is 0 until E3.
func digest_q() -> float:
	var qc := _qcfg()
	var ema := float(_readout["q_raise_ema"])
	var q_raise := float(qc.get("q_raise_max", 0.6)) * maxf(0.0, (ema - 50.0) / 50.0)
	var foremen := 0.0
	var q := float(qc.get("q0", 1.2)) + float(qc.get("q_forge", 0.1)) * float(town_sim.forge["level"]) + foremen + q_raise
	return clampf(q, 1.0, float(qc.get("q_max", 4.0)))


## legacy: delete when map drops the call (world_map.gd reads Game.quality()). The same q.
func quality() -> float:
	return digest_q()


## Each raised bucket {score, mass}, in apply order, moves ema_score by α = 1 − 0.5^(mass /
## q.raise_half_mass): a half-life in mass raised, not in time, so it holds while no circles arrive.
func _raise_ema(raised: Array) -> void:
	var half := float(_qcfg().get("raise_half_mass", 200.0))
	var ema := float(_readout["q_raise_ema"])
	for e in raised:
		var m := maxf(0.0, float(e["mass"]))
		var a := (1.0 - pow(0.5, m / half)) if half > 0.0 else (1.0 if m > 0.0 else 0.0)
		ema += a * (clampf(float(e["score"]), 0.0, 100.0) - ema)
	_readout["q_raise_ema"] = ema


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


## MECHANICS §3.2: mint = (P_base + P_per_pit · pits) · (1 + pit.bonus · feed), mass/s.
func _mint(pits: int, feed: float) -> float:
	var cfg: Dictionary = _cfg()
	var bonus := float(_sec("economy", "pit").get("bonus", 0.6))
	return (float(cfg.get("P_base", 2.0)) + float(cfg.get("P_per_pit", 6.0)) * pits) * (1.0 + bonus * feed)


## §3 step 2's inputs: last substep's WORK, Relish home, the villages that follow necrosis, a
## snapshot of the forts before this substep's realm step, Covington, the haul target, the relics.
func _town_inputs() -> Dictionary:
	var forts: Array = []
	for f in realm.forts:
		forts.append({"id": f["id"], "pos": _xy(f["pos"]), "dead": float(f["dead"]), "held": RealmSim.is_held(f)})
	return {
		"work_mass": work_pending, "relish_home": relish["state"] == "home", "held_villages": green_towns,
		"forts": forts, "cov_pos": _xy(realm.cov_pos), "haul_target": haul_target, "relics_available": relics,
	}


## Takes TownSim's haul pickups off the forts' dead, each clamped to what the fort holds now.
func _apply_pickups(picks: Array) -> void:
	for p in picks:
		var f := realm.fort_by_id(str(p["fort_id"]))
		if not f.is_empty():
			f["dead"] = float(f["dead"]) - minf(maxf(0.0, float(p["mass"])), float(f["dead"]))


## Re-emits a TownSim event with this substep's t. `building_started` gains `upgrade` (§6).
func _emit_town(ev: Dictionary) -> void:
	var e := ev.duplicate(true)
	if e["type"] == "building_started":
		e["upgrade"] = int(e["level"]) > 1
	_emit(e)


## The tier a town holds: it rises while the next tier's requirements hold (enough finished
## buildings and every required building id), one `tier_up` per rise. Tiers never fall.
func _rise_tiers() -> void:
	while true:
		var nt := _next_tier()
		if nt["tier"] == "" or int(nt["have"]) < int(nt["need"]) or not (nt["missing"] as Array).is_empty():
			return
		var from := town_tier
		town_tier = str(nt["tier"])
		_emit({"type": "tier_up", "tier": town_tier, "from": from})
		rev += 1


func _tick(dt: float) -> void:
	t += dt
	var cfg: Dictionary = _cfg()
	# §3 step 2: TownSim on last substep's WORK, all of it (WORK arrives one substep late)
	var town := town_sim.step(dt, _town_inputs())
	work_pending = 0.0
	_apply_pickups(town["pickups"])
	relics = maxi(0, relics - int(town["relics_spent"]))
	for ev in town["events"]:
		_emit_town(ev)
	_rise_tiers()
	# §3 step 3: the valve slews, then splits the mint; TownSim's muster joins WAR
	_slew_valve(dt)
	var mint := _mint(int(town["pits"]), float(town["feed"]))
	var muster := float(town["muster_mass"]) / dt
	_split = {"mint": mint, "work": mint * valve["work"], "war": mint * valve["war"] + muster,
		"flood": mint * valve["flood"], "muster": muster}
	work_pending = _split["work"] * dt  # delivered to TownSim next substep
	# §3 step 4: Relish's travel and state
	_step_relish_travel(dt)
	# §3 step 5: RealmSim, pure on these inputs; its events get this substep's t
	var fx := _relish_effects()
	var rcfg: Dictionary = cfg.get("relish", {})
	# (siege_block: the siege big undead's share per fort, E3; none yet)
	_realm_inputs = {
		"war": _split["war"], "flood": _split["flood"], "digest_q": digest_q(),
		"tide_fort": fx["tide_fort"], "tide_bias": float(rcfg.get("tide_bias", 3.0)),
		"redirect_fort": fx["redirect_fort"], "redirect_rate": float(rcfg.get("raise_rate", 4.0)),
		"siege_block": {},
	}
	var cleared0 := realm.cleared_total
	realm.step(dt, _realm_inputs)
	var cleared := realm.cleared_total - cleared0
	var evs := realm.drain_events()
	for ev in evs:
		_emit(ev)
	# §3 step 7: the ledger books this substep's source and sinks (held is read live)
	_ledger.source("mint", mint * dt)
	for k in ["rot_loss", "rot_overflow", "haul_overflow", "burned", "milled"]:
		_ledger.sink(k, float(town[k]))
	_ledger.sink("cleared", cleared)
	_note_realm_flows(dt, cleared)
	# §3 step 8: the readouts, and the lane callouts for what changed this substep
	_update_readout(dt, realm.vei["r_in_undead"], realm.r_digested_undead)
	_note_lane_causes(evs)
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


## view_rates' corpses and backlog for this substep (§5.2; _realm_flows).
func _note_realm_flows(dt: float, cleared: float) -> void:
	var made := 0.0
	var raised := 0.0
	for f in realm.forts:
		made += float(f["r_kills"]) + float(f["r_redirected"])
		raised += float(f["r_raised"])
	_realm_flows = {
		"corpses": [made, raised + cleared / dt],
		"backlog": [float(realm.vei["r_in_undead"]), float(realm.r_digested_undead)],
	}


func _inject_sources(dt: float) -> void:
	var fcfg: Dictionary = _cfg().get("field", {})
	var src_main: float = float(fcfg.get("src_main", 3.0))
	var src_fort: float = float(fcfg.get("src_fort", 1.1))
	field.inject(realm.cov_pos, true, src_main * (1.0 + float(_cfg().get("field_src_per_pit", 0.15)) * town_sim.pits()) * dt, 2)
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


# ------------------------------- compatibility for unported callers, and death ----
# STATE-API §2.2: built best-effort from the new state; nothing written to them is read back.

## legacy: delete when map drops the call (scripts/main.gd merges it into an unported dungeon's
## args). The pre-E1 raid seed's keys, from the live fort and q.
func raid_seed(fort_id: String) -> Dictionary:
	var f := realm.fort_by_id(fort_id)
	if f.is_empty():
		return {}
	return {
		"fort_id": fort_id, "name": f["name"], "tier": f["tier"], "cap": f["cap"],
		"living": f["living"], "undead": f["undead"], "dead": f["dead"], "boss": false, "quality": digest_q(),
	}


## legacy: delete when map drops the call (scripts/main.gd merges it into an unported boss's args).
## The pre-E1 boss seed's keys; the army is gone, so it is empty.
func boss_seed() -> Dictionary:
	return {
		"fort_id": "vei", "name": "Vei's Domain", "tier": 5, "cap": 800.0,
		"living": 500.0, "undead": 0.0, "dead": 60.0, "boss": true,
		"quality": digest_q(), "backlog": float(realm.vei["undead_queue"]),
		"army": {"soldier": 0, "elite": 0}, "vei_capacity": float(_cfg().get("R_vei", 50.0)), "odds": realm.odds(),
	}


## legacy: delete when map drops the call (scripts/main.gd merges it into the town scene's args).
## {}: the town reads views now.
func town_snapshot() -> Dictionary:
	return {}


## legacy: delete when map drops the call (scripts/main.gd passes a legacy town result). A no-op:
## town actions are commands.
@warning_ignore("unused_parameter")
func apply_town_result(r: Dictionary) -> void:
	pass


## legacy: delete when map drops the reads (world_map.gd and map_routes.gd read Game.res, army,
## town, assignments, idle_undead and gather; Game's getters forward here). The E1 stores rebuilt
## fresh from the new state (STATE-API §2.2), so a write to them changes nothing:
## res {gold, materials: bone, bodies, townsfolk: living}; army {soldier: 0, elite: 0};
## town {slabs: working pits, vats: clones_ready, forge_level, sim_stations: 0, trade_level: 0};
## assignments: staffed workers per old job (trade: stall, forge, jobs: build, gather: haul,
## slab: pit), rounded; idle_undead: idle workers, rounded; gather {target, phase, eta, load}: the
## convoy (phase "idle" and the set target, or "", when none is out). Every count is an int.
func legacy_stores() -> Dictionary:
	var ts := town_sim
	var jobs: Dictionary = ts.staffing.get("jobs", {})
	var assign := {}
	for pair in [["trade", "stall"], ["forge", "forge"], ["jobs", "build"], ["gather", "haul"], ["slab", "pit"]]:
		assign[pair[0]] = roundi(float(jobs.get(pair[1], {}).get("staffed", 0.0)))
	var gather := {"target": "" if haul_target == "auto" else haul_target, "phase": "idle", "eta": 0.0, "load": 0.0}
	for c in ts.haul["convoys"]:
		gather = {"target": str(c["fort"]), "phase": str(c["phase"]),
			"eta": (1.0 - float(c["t"])) * float(c["trip_s"]), "load": float(c["load"])}
	return {
		"res": {"gold": ts.gold, "materials": ts.bone, "bodies": ts.bodies, "townsfolk": ts.living},
		"army": {"soldier": 0, "elite": 0},
		"town": {"slabs": ts.pits(), "vats": clones_ready, "forge_level": int(ts.forge["level"]),
			"sim_stations": 0, "trade_level": 0},
		"assignments": assign,
		"idle_undead": roundi(float(ts.staffing.get("idle", 0.0))),
		"gather": gather,
	}


## Relish's death until E3 (§8.3 step 10, the E1-safe rule): a ready clone if there is one (it is
## spent), else she is unmade and the town takes morale.death_shock; she respawns home at once.
## The caller has closed the run.
func _death(run_id: int) -> void:
	stats["deaths"] += 1
	var at_node: String = relish["at"]
	var clone := clones_ready > 0
	if clone:
		clones_ready -= 1
	else:
		town_sim.add_shock(float(_sec("economy", "morale").get("death_shock", 0.3)))
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


## §8.3 raid steps 1-11 (death by the E1-safe rule until E3). The result is already validated and
## matched to the open run. Returns the minted uids.
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
		realm.start_tithe()  # the first flip starts Vei's tithe cycle (a running one is left alone)
		f["flipped_count"] = int(f.get("flipped_count", 0)) + 1
		f["clears_since_retaken"] = int(f.get("clears_since_retaken", 0)) + 1
		flip_ev = {"type": "fort_flipped", "fort_id": fort_id, "run_id": run_id, "hold_s": hold_s}
	# 3. raised mass comes out of the dead
	var raised_total := 0.0
	for e in r["raised"]:
		raised_total += float(e["mass"])
	var raised_in := minf(raised_total, float(f["dead"]))
	f["dead"] -= raised_in
	# q's circle EMA, by the mass actually raised from the fort's dead (each mass scaled by R'/R)
	var raised_scale := raised_in / raised_total if raised_total > 0.0 else 0.0
	var raised_clamped: Array = []
	for e in r["raised"]:
		raised_clamped.append({"score": e["score"], "mass": float(e["mass"]) * raised_scale})
	_raise_ema(raised_clamped)
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
	_ledger.sink("dungeon", raised_in - undead_delta - chaff)
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
	var died: bool = r["relish_died"]
	var party := _seed_party_uids(sd)
	run = {}
	_emit({"type": "loot_banked", "run_id": run_id, "fort_id": fort_id, "relics": relics_in,
		"essence": essence_in, "blueprints": new_bps, "minted": minted.duplicate()})
	if not flip_ev.is_empty():
		_emit(flip_ev)
	# 10. death: the whole party is lost (A8), then the death rule; 11. otherwise she stays
	if died:
		for uid in party:
			_remove_big_undead(uid)
		_death(run_id)
	else:
		relish["state"] = "at_fort"
	return minted


## §8.3 boss steps 1-5 (a final death by the E1-safe rule until E3).
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
		var before: float = realm.vei["undead_queue"]
		realm.vei["undead_queue"] = before * keep
		_ledger.sink("vei_fight", before - float(realm.vei["undead_queue"]))
		for uid in _seed_party_uids(sd):
			_remove_big_undead(uid)
	for uid in r["party_lost"]:
		_remove_big_undead(uid)
	_phylactery_charges = maxi(0, _phylactery_charges - int(bs["phylactery"]))
	clones_ready = maxi(0, clones_ready - clones)
	run = {}
	var cleared: Array = []
	for fid in r["fronts_cleared"]:
		cleared.append(str(fid))
	_emit({"type": "vei_result", "run_id": run_id, "won": did_win, "fronts_cleared": cleared,
		"relish_deaths": deaths, "backlog_after": float(realm.vei["undead_queue"])})
	if final_death:
		_death(run_id)
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
	# TownSim's block, plus what GameState keeps for the town: the tier, the haul target and the WORK
	# on its way (delivered next substep)
	var town: Dictionary = town_sim.to_dict()
	town["tier"] = town_tier
	town["haul"]["target"] = haul_target
	town["work_pending"] = work_pending
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
		var ve := _vat_entry(i)
		vats.append({"slot": i, "staffed": ve["staffed"], "grow": ve["grow"]})
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
			"tithe": realm.tithe.duplicate(true),
		},
		"villages": villages,
		"town": town,
		"stances": {"on": stances_on.duplicate(), "hold": _stance_hold.duplicate()},
		"inventory": {"husks": husk_list, "remnants": remnant_list, "blueprints": blueprints.duplicate(),
			"relics": relics, "essence": essence, "simulacra_ready": 0},
		"big_undead": bus,
		"party": party_uids.duplicate(),
		"backups": {"phylactery_charges": _phylactery_charges, "clones_ready": clones_ready, "vats": vats},
		"readout": _readout.duplicate(),
		"ledger": _ledger.to_dict(),
		"won": won, "stats": stats.duplicate(),
		"cleared_forts": cleared_forts.keys(), "first_dungeon": first_dungeon_id,
	}
	(d["cleared_forts"] as Array).sort()
	return SaveIO.canon(d)


## §9.1 `static migrate`: one version at a time up to SAVE_VERSION (the steps are SaveIO's). `{}` on
## failure (no `v`, a `v` that is not a whole number from 1 up, or a version from the future). At
## SAVE_VERSION it returns a deep copy; v1 → v2 moves the E1 legacy stores into the town block.
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
	if relish["state"] == "travelling" and _dist_to(relish["target"]) <= ARRIVE_EPS:
		_arrive(relish["target"])  # a save taken at ~0 px left loads settled, not stuck
	valve_target = _valve_of(m["valve"]["target"])
	valve = _valve_of(m["valve"]["current"])
	var rm: Dictionary = m["realm"]
	var flipped := false
	for e in rm["forts"]:
		var f := realm.fort_by_id(e["id"])
		for k in ["living", "undead", "dead", "r_in", "r_drain", "r_shipped", "r_dead_out", "r_raised"]:
			f[k] = float(e[k])
		realm.hold(e["id"], float(e["held_s"]))
		f["flipped_count"] = int(e["flipped_count"])
		f["clears_since_retaken"] = int(e["clears_since_retaken"])
		flipped = flipped or f["flipped_count"] > 0
	for k in realm.cov:
		realm.cov[k] = float(rm["cov"][k])
	for k in realm.vei:
		realm.vei[k] = float(rm["vei"][k])
	realm.load_tithe(rm["tithe"], flipped)
	realm.simulacra = []
	for s in rm["simulacra"]:
		var e: Dictionary = (s as Dictionary).duplicate(true)
		e["charges"] = float(e["charges"])
		e["rate"] = float(e["rate"])
		realm.simulacra.append(e)
	realm.elapsed = float(rm["elapsed"])
	realm.cleared_total = float(rm["cleared_total"])
	realm.raised_by_sims = float(rm["raised_by_sims"])
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
	haul_target = tm["haul"]["target"]
	work_pending = float(tm["work_pending"])
	town_sim.from_dict(tm)  # a load restores the saved staffing states as they were (no restaff)
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
	clones_ready = maxi(0, int(m["backups"]["clones_ready"]))
	# an E1 save's q_raise_ema is the placeholder 0.0: it loads as the neutral 50 (an EMA that starts
	# at 50 can never reach exactly 0)
	var qe := float(m["readout"]["q_raise_ema"])
	_readout = {"diff_ema": float(m["readout"]["diff_ema"]), "q_raise_ema": qe if qe != 0.0 else 50.0}
	_diff = 0.0
	_ledger.from_dict(m["ledger"], _held())  # after every pool of mass is restored
	won = bool(m["won"])
	var sm: Dictionary = m["stats"]
	stats = {"raised_total": float(sm["raised_total"]), "raids": int(sm["raids"]), "deaths": int(sm["deaths"]),
		"sims_built": int(sm["sims_built"])}
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
	realm.digest_q = digest_q()
	_split = {"mint": 0.0, "work": 0.0, "war": 0.0, "flood": 0.0, "muster": 0.0}
	_realm_flows = {"corpses": [0.0, 0.0], "backlog": [0.0, 0.0]}
	_realm_inputs = {}
	_reset_lanes()
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
