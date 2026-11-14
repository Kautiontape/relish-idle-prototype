class_name GameState
extends RefCounted
## All game state and logic, headless. The Game autoload is a thin shell over one
## of these. Configs are injected through setup(); randomness comes from `rng`.
## Files in scripts/sim/ never reference an autoload or Engine (a lint test
## enforces this). No signals: consumers poll
## `rev` and drain_events(). The contract is docs/STATE-API.md.

const API_VERSION := 6
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
var game_id := ""  # view_hud.game_id: SaveIO.game_id_for(rng_seed), stored in the save (never drawn from rng)
var rev := 0  # +1 per substep and per successful command

# --- Relish (owned here; RealmSim sees only her effects, as step inputs: _relish_effects) ---
var relish := {}
# --- runs and seeds (§4.5, §7) ---
var run := {}  # {} or {run_id, kind: "raid"|"boss", fort_id, seed_rev, seed}
var next_run_id := 1
var next_uid := 1  # one counter for h<n>, r<n>, u<n>
var game_seed := 0
var first_dungeon_id := ""  # "" once a won raid result has cleared it (T1.4)
var cleared_forts := {}  # fort_id -> true once a win has spent its first clear (T1.4)
# --- stocks and inventories (views §5.12) ---
var relics := 0
var essence := 0
var husks: Array = []
var remnants: Array = []
var big_undead: Array = []
var party_uids: Array = []
var valve := {"work": 0.40, "war": 0.45, "flood": 0.15}  # the current vector; slews toward the target (§3 step 3)
var valve_target := {"work": 0.40, "war": 0.45, "flood": 0.15}
## WORK in flight to TownSim: 0 at every step boundary now (§3: TownSim takes each step's WORK as
## rate × dt in the same step; the mint lags instead, reading last step's feed). A save written
## before that (E2a) can hold some; the next step delivers it with its own. Held mass; saved as
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
	game_id = SaveIO.game_id_for(rng_seed)
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
	town_sim.set_vats(vats_staffed)  # (new_game cleared them too)
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
	return StateViews.relish(self)


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


func _fronts_required() -> int:
	return int(_cfgs.get("vei", {}).get("fronts_required", 3))


func cmd_begin_dungeon(fort_id: String) -> Dictionary:
	return StateRuns.begin_dungeon(self, fort_id)


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
	return StateRuns.begin_boss(self)


func cmd_abort_dungeon() -> Dictionary:
	return StateRuns.abort_dungeon(self)


func view_dungeon_seed(fort_id: String) -> Dictionary:
	return StateRuns.view_dungeon_seed(self, fort_id)


func view_boss_seed() -> Dictionary:
	return StateRuns.view_boss_seed(self)


## The open raid's fort else "".
func raiding_fort_id() -> String:
	if run.get("kind", "") == "raid":
		return run["fort_id"]
	return ""


# ------------------------------------------------------------------ debug ----
func _mint_uid(prefix: String) -> String:
	var uid := "%s%d" % [prefix, next_uid]
	next_uid += 1
	return uid


## A capped stock's cap: its base in economy.json plus the buildings' (BuildRules.cap_bonus).
func _cap_of(section: String) -> int:
	var sec := _sec("economy", section)
	return int(sec.get("cap", 1 << 30)) + BuildRules.cap_bonus(self, section)


func cmd_debug_grant(amounts: Dictionary) -> Dictionary:
	return DebugCmds.grant(self, amounts)


func cmd_debug_set_state(patch: Dictionary) -> Dictionary:
	return DebugCmds.set_state(self, patch)


func cmd_debug_skip_time(seconds: float) -> Dictionary:
	return DebugCmds.skip_time(self, seconds)


# ------------------------------------------------------------- §4.3 town ----
# The town is TownSim's (BALANCE §0 at a new game). The job ladder and staff caps drive its
# staffing. The build family (T2.4) pays from TownSim's stocks and the relics, and constructs
# through TownSim's build job. Raise, craft and deploy are still §1.1 stubs (id checks, then ok
# with zero extras, no change); stances and vat staffing are stored and echoed (E3).

## Buildings of that id that have finished their first build (level ≥ 1); every building when "".
func _count_built(building_id: String) -> int:
	return BuildRules.count_built(self, building_id)


## §4.3 · E2: pays the cost at once and starts construction on a free, unlocked lot. TownSim's
## `build` job advances it; `building_started` comes out of the next substep, `building_done` when
## the work is in. A `unique` building (the Crypt) is refused while one stands (api_version 3).
func cmd_build(building_id: String, lot_id: String) -> Dictionary:
	return BuildRules.build(self, building_id, lot_id)


## §4.3 · E2: pays level_costs and constructs the next level. The building works at its old level
## meanwhile (TownSim). Reasons in order: unknown_lot, empty_lot, under_construction, unpaid,
## max_level, needs_tier, no_gold, no_bone, no_relics.
func cmd_upgrade(lot_id: String) -> Dictionary:
	return BuildRules.upgrade(self, lot_id)


## §4.3 · E2: removes a finished building, no refund. The Crypt is protected.
func cmd_demolish(lot_id: String) -> Dictionary:
	return BuildRules.demolish(self, lot_id)


## §4.3 · E2: cancels the construction under way and refunds its cost in full (relics clamped to the
## cap). A cancelled first build frees the lot; a cancelled upgrade keeps the old level.
func cmd_cancel_build(lot_id: String) -> Dictionary:
	return BuildRules.cancel_build(self, lot_id)


## The ladder, a permutation of JOB_IDS, top first: TownSim's workers fill job slots in this order.
func cmd_set_job_priority(order: Array) -> Dictionary:
	var why := _job_order_reason(order)
	if why != "":
		return {"ok": false, "reason": why, "order": []}
	town_sim.set_ladder(order)
	rev += 1
	return {"ok": true, "reason": "", "order": town_sim.ladder.duplicate()}


## Why cmd_set_job_priority refuses `order` (unknown_job, duplicate_job, missing_job, checked in that
## order), or "" for a permutation of JOB_IDS. view_staffing_projection refuses with the same.
func _job_order_reason(order: Array) -> String:
	for j in order:
		if not (typeof(j) == TYPE_STRING or typeof(j) == TYPE_STRING_NAME) or not JOB_IDS.has(str(j)):
			return "unknown_job"
	var seen := {}
	for j in order:
		if seen.has(str(j)):
			return "duplicate_job"
		seen[str(j)] = true
	if seen.size() < JOB_IDS.size():
		return "missing_job"
	return ""


## A lot's staff cap (-1 = none) for TownSim's staffing. A cap above the slots is accepted.
func cmd_set_staff_cap(lot_id: String, cap: int) -> Dictionary:
	var why := ""
	if BuildRules.lot(self, lot_id).is_empty():
		why = "unknown_lot"
	elif not town_sim.buildings.has(lot_id):
		why = "empty_lot"
	elif BuildRules.slots_of(self, town_sim.buildings[lot_id]["building_id"]) == 0:
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
		if BuildRules.lot(self, lot_id).is_empty():
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


## E1/E3 (the hand E2b-2): stores the staffing, and a staffed vat takes a hand: its tend slot opens
## and the ladder fills it like any other; unstaffing it closes the slot and gives the hand back
## (MECHANICS §7). Clones grow only while staffed from E3.
func cmd_staff_vat(slot: int, on: bool) -> Dictionary:
	if slot < 0 or slot >= _vat_slots():
		return {"ok": false, "reason": "unknown_slot", "staffed": false}
	while vats_staffed.size() <= slot:
		vats_staffed.append(false)
	vats_staffed[slot] = on
	town_sim.set_vats(vats_staffed)
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


## TownSim's settled workforce and the WAR muster rate there (workers/s), at the live inflow,
## lifetime, idle rot, staffable slots and idle cap. `steady` ignores the idle cap; this does not.
func _workers_steady_kept() -> Dictionary:
	return town_sim.steady_kept(relish["state"] == "home")


## §5.1 · E2. Live: t, the time controls, relics and essence with their caps, won, the readout
## (sign, drain_s, odds), the valve and its split, the mint's rate, and TownSim's stocks, caps and
## net rates.
func view_hud() -> Dictionary:
	return StateViews.hud(self)


## §5.2 · E2, live for every id from E2a (_rate_io): the valve streams and the realm's corpses and
## backlog are the last substep's (session only), the town's are TownSim's. `net` is in − out (0 for
## the pass-throughs); backlog's is view_vei's raw `diff`.
func view_rates() -> Dictionary:
	return StateViews.rates(self)


static func _lane_id(kind: String, from: String, to: String) -> String:
	return "%s:%s:%s" % [kind, from, to]


## §5.3 · E2. Kinds in LANE_KINDS order, forts in world order: war covington→fort (staging at held
## forts included) and covington→vei (WAR that fell through); flood covington→vei and fort→vei
## (drain); work covington→covington (the valve's WORK); dead fort→vei; living vei→fort (shipping and
## surges); haul fort→covington (the convoy's fort, trip-averaged); redirect fort→fort (raised by
## Relish or a simulacrum). Rates are last substep's mass/s.
func view_lanes() -> Dictionary:
	return StateViews.lanes(self)


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
	return StateViews.realm(self)


## The fort Relish stands at (at_fort, or in its dungeon), or "".
func _standing_fort() -> String:
	var st: String = relish["state"]
	return relish["at"] if st == "at_fort" or st == "in_dungeon" else ""


## §5.5 · E1. can_descend/reason are cmd_begin_dungeon(id)'s own check.
func view_fort(id: String) -> Dictionary:
	return StateViews.fort(self, id)


## §5.6 · E1. The one view that is not a copy: `field` is the live InfluenceField.
func view_field() -> Dictionary:
	return {
		"rev": rev, "field": field, "world_size": _world_size(),
		"tick_hz": float(_cfg().get("field", {}).get("tick_hz", 5.0)),
	}


## §5.7 · E1: the legacy village control, with live dominance. A player village sends TownSim
## economy.json town.migrant_rate living/s (its held_villages input).
func view_villages() -> Dictionary:
	return StateViews.villages(self)


## §5.9 · E2: TownSim's town. Lots from town.json; buildings with their state, progress, slots,
## staffing, cap, foreman, output and upkeep; the ladder and its jobs; the workforce, the living,
## morale and its factors, the stocks and caps, trade, the convoy. Stances (ladder_effective) are E3.
func view_town() -> Dictionary:
	return StateViews.town(self)


## §5.16 · E2b (api_version 5, api-request #16): TownSim's own staffing allocation on today's workforce,
## buildings and staff caps, with the job order replaced by `order` (stances applied the same way) and
## the vats in `vats` ({slot: bool}) overriding the staffed ones. Pure: changes nothing, no rev bump.
## An `order` cmd_set_job_priority would refuse gives its reason with empty jobs and buildings.
func view_staffing_projection(order: Array, vats: Dictionary = {}) -> Dictionary:
	return StateViews.staffing_projection(self, order, vats)


## §5.10 · E2 (crafts E3): buildings.json in file order, with live gating.
func view_catalog() -> Dictionary:
	return StateViews.catalog(self)


## §5.11 · E3. E1 echoes cmd_set_stance: nothing fires, nothing is projected.
func view_stances() -> Dictionary:
	return StateViews.stances(self)


## §5.12 · E1. Simulacra and phylactery charges are E3 (0).
func view_inventory() -> Dictionary:
	return StateViews.inventory(self)


## §5.12 · E1.
func view_big_undead() -> Dictionary:
	return StateViews.big_undead(self)


## §5.12 · E1. The garrison and starter figures are §7.1's for the fort she stands at;
## strength is E2 (0).
func view_party() -> Dictionary:
	return StateViews.party(self)


## §5.13 · E3. Until E3: clones_ready is the stub stock and each ready clone is a vat slot; the
## E1-safe death rule (a clone if one is ready, else unmade with the morale shock) with an
## immediate respawn.
func view_backups() -> Dictionary:
	return StateViews.backups(self)


## §5.14 · E2 (fronts E3; assigned is live). The readout, q and the tithe are live.
## can_begin/reason are cmd_begin_boss()'s check.
func view_vei() -> Dictionary:
	return StateViews.vei(self)


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


## §3 step 3's inputs: this step's WORK mass, Relish home, the villages that follow necrosis, a
## snapshot of the forts before this step's realm step, Covington, the haul target, the relics.
func _town_inputs(work_mass: float) -> Dictionary:
	var forts: Array = []
	for f in realm.forts:
		forts.append({"id": f["id"], "pos": _xy(f["pos"]), "dead": float(f["dead"]), "held": RealmSim.is_held(f)})
	return {
		"work_mass": work_mass, "relish_home": relish["state"] == "home", "held_villages": green_towns,
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


## One live substep (§3): the core step, then the presentation step, both at `dt`.
func _tick(dt: float) -> void:
	var evs := _core_step(dt)
	_present_step(dt, evs)
	rev += 1


## The sim's step, valid at any `dt` (IDLE §4: live play runs it at sim.substep_s, catch-up at
## longer steps): §3 steps 1–8, everything but the presentation. TownSim, RealmSim and the readouts
## are exact or rate-based over the step, so nothing here assumes a short dt. Returns this step's
## realm events (already emitted), for the presentation step's lane callouts. Never touches the
## influence field: village owners (TownSim's held_villages) are read as they stand.
func _core_step(dt: float) -> Array:
	# a zero-length or non-finite step (a catch-up runner clipping to events) books nothing: the
	# realm's step returns early and would leave last step's pool_overflow to be booked twice, and
	# the muster rate divides by dt
	if not (dt > 0.0) or not is_finite(dt):
		return []
	t += dt
	var mark := _events.size()  # this step's events start here (a realm event inside the step goes first)
	var cfg: Dictionary = _cfg()
	# §3 step 2: the valve slews, then splits the mint. The mint reads the working pits now and the
	# feed of the step before (both dimensionless, so a step of any length takes them as they are)
	_slew_valve(dt)
	var mint := _mint(town_sim.pits(), float(town_sim.rates.get("feed", 0.0)))
	var work := mint * float(valve["work"])
	# §3 step 3: TownSim on this step's WORK, rate × dt. A save written before the lag (E2a) can hold
	# WORK in flight: it arrives with this step's, once
	var town := town_sim.step(dt, _town_inputs(work * dt + work_pending))
	work_pending = 0.0
	_apply_pickups(town["pickups"])
	relics = maxi(0, relics - int(town["relics_spent"]))
	for ev in town["events"]:
		_emit_town(ev)
	BuildRules.rise_tiers(self)
	# TownSim's muster joins this step's WAR
	var muster := float(town["muster_mass"]) / dt
	_split = {"mint": mint, "work": work, "war": mint * valve["war"] + muster,
		"flood": mint * valve["flood"], "muster": muster}
	# §3 step 4: Relish's travel and state
	_step_relish_travel(dt)
	# §3 step 5: RealmSim, pure on these inputs; its events get this step's t
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
	var evs := _emit_realm(realm.drain_timed(), dt, mark)
	# §3 step 7: the ledger books this step's source and sinks (held is read live)
	_ledger.source("mint", mint * dt)
	for k in ["rot_loss", "rot_overflow", "haul_overflow", "burned", "milled"]:
		_ledger.sink(k, float(town[k]))
	_ledger.sink("cleared", cleared)
	_ledger.sink("pool_overflow", realm.pool_overflow)  # the march-back past Vei's pool cap (MECHANICS §3.4)
	_note_realm_flows(dt, cleared)
	# §3 step 8: the readouts
	_update_readout(dt, realm.vei["r_in_undead"], realm.r_digested_undead)
	return evs


## This step's realm events ([[seconds into the step, event], ...], RealmSim.drain_timed), stamped
## at their moment: a retake inside the step carries its own time (IDLE §4), the rest the step's
## end. One stamped before the step's end goes in ahead of the step's other events (from `mark`),
## in time order, so `t` never decreases. A retake sends the siege big undead there home (IDLE I6,
## `big_undead_returned` right after it). Returns the realm events, in queue order.
func _emit_realm(timed: Array, dt: float, mark: int) -> Array:
	var early: Array = []
	var late: Array = []
	for e in timed:
		var at := float(e[0])
		var ev: Dictionary = e[1]
		ev["t"] = (t - dt + at) if at >= 0.0 and at < dt else t
		var out: Array = early if float(ev["t"]) < t else late
		out.append(ev)
		if ev["type"] == "fort_retaken":
			for uid in _uids_at("fort:" + str(ev["fort_id"])):
				_find_uid(big_undead, uid)["place"] = "crypt"
				out.append({"type": "big_undead_returned", "uid": uid, "fort_id": str(ev["fort_id"]), "t": ev["t"]})
	# insertion by t keeps equal times in the order RealmSim raised them
	var sorted: Array = []
	for ev in early:
		var k := sorted.size()
		while k > 0 and float(sorted[k - 1]["t"]) > float(ev["t"]):
			k -= 1
		sorted.insert(k, ev)
	for k in sorted.size():
		_events.insert(mark + k, sorted[k])
	_events.append_array(late)
	return sorted + late


## The presentation step (§3 step 9 and the lane callouts): what only the map shows, plus the
## village owners the field decides. `evs` are the realm events since the last presentation step.
## Live play runs it after every core step at the same dt.
func _present_step(dt: float, evs: Array) -> void:
	_note_lane_causes(evs)
	var cfg: Dictionary = _cfg()
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


## The field's signed dominance at `pos`, 0.0 where it is not finite (a field ticked far past its
## stable dt can hold NaN; the API never carries one, STATE-API §1.3).
func _dominance(pos: Vector2) -> float:
	var d := float(field.dominance_at(pos))
	return d if is_finite(d) else 0.0


## Village owners from the field: green above field.town_threshold, orange below its negative,
## else none (a non-finite field reads 0, so none).
func _update_towns(cfg: Dictionary) -> void:
	var thresh: float = float(cfg.get("field", {}).get("town_threshold", 0.18))
	green_towns = 0
	for tw in towns:
		var dom: float = _dominance(tw["pos"])
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
	StateRuns.death(self, run_id)


# ------------------------------------------------------------ apply_result ----
## §4.5. Refusals are checked in the documented order and change nothing (no rev, no events,
## no uids, no rng). Ints may arrive as integral floats, so every int is read with int().
func apply_result(kind: String, result: Dictionary) -> Dictionary:
	return StateRuns.apply_result(self, kind, result)


# ------------------------------------------------------------ §9 persistence ----
# The save spec, its checker and the file plumbing are SaveIO (scripts/sim/save_io.gd).

## §9.1. A deep copy that survives JSON; the open run is written in its forfeited form.
func to_dict() -> Dictionary:
	return SaveIO.dump(self)


## §9.1 `static migrate`: one version at a time up to SAVE_VERSION (the steps are SaveIO's). `{}` on
## failure (no `v`, a `v` that is not a whole number from 1 up, or a version from the future). At
## SAVE_VERSION it returns a deep copy; v1 → v2 moves the E1 legacy stores into the town block.
static func migrate(d: Dictionary) -> Dictionary:
	return SaveIO.migrate(d, SAVE_VERSION)


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
	SaveIO.apply(self, m)
	# the vats come back after TownSim's own load: they open the tend slots (refilled, the saved
	# states kept)
	town_sim.set_vats(vats_staffed, true)
	return {"ok": true, "reason": ""}


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
	return DebugCmds.load_fixture(self, name)


## Recursively loads every *.json under `dir` into a Dictionary keyed by the
## filename without extension. Directories starting with "." are skipped.
## Files are walked in sorted order so the result is deterministic. On a
## basename collision the first file wins and an error names both paths.
## A file that fails to parse is reported and skipped. A missing dir is {}.
## Each duplicate or parse failure also appends one string to `errors`, so
## callers (the test suite) can fail on them.
static func load_configs(dir: String, errors: Array = []) -> Dictionary:
	return SaveIO.load_configs(dir, errors)
