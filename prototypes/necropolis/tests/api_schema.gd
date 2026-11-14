class_name ApiSchema
extends RefCounted
## The STATE-API contract as data: every command return, view, event, seed, result and
## ledger(), with exact value types, written from docs/STATE-API.md. The freeze guard
## (test_api_contract.gd) checks GameState against it; T1.4/T1.5 extend it.
##
## Spec grammar:
##   TYPE_*            the exact Variant type (floats must also be finite)
##   {key: spec, ...}  a Dictionary holding at least these keys (extra keys are additive)
##   {"*": spec}       a Dictionary map: any String keys, every value matches spec
##   [spec]            an Array whose every element matches spec
## Freeze rule (§1.1): only add. Never rename, remove or retype an entry.

const I := TYPE_INT
const F := TYPE_FLOAT
const S := TYPE_STRING
const B := TYPE_BOOL
const D := TYPE_DICTIONARY  # opaque: type only
const O := TYPE_OBJECT

# ------------------------------------------------------------- building blocks ----
const POS := [F]  # [x, y]
const VALVE := {"work": F, "war": F, "flood": F}
const COST := {"gold": F, "bone": F, "relics": I}
const UPKEEP := {"gold": F, "bone": F}
const STAT_BLOCK := {"power": F, "beef": F, "wits": F, "presence": F, "speed": F}
const BIG_UNDEAD := {"uid": S, "name": S, "kind": S, "role": S, "stats": STAT_BLOCK, "place": S, "front": S}
const SEED_PARTY := {"uid": S, "name": S, "kind": S, "role": S, "stats": STAT_BLOCK}
const BOSS_PARTY := {"uid": S, "name": S, "kind": S, "role": S, "stats": STAT_BLOCK, "front": S}

# ----------------------------------------------------------------- seeds (§7) ----
const RAID_SEED := {
	"v": I, "kind": S, "run_id": I, "seed_rev": I, "rng_seed": S,
	"fort": {"id": S, "name": S, "tier": I, "cap": F, "first_clear": B, "first_dungeon": B,
		"clears_since_retaken": I, "yield_mult": F},
	"living": F, "dead": F, "undead": F, "garrison_units": I, "garrison_in_mass": F, "garrison_mass_div": F, "starter_units": I,
	"party": [SEED_PARTY], "digest_q": F, "phylactery_charges": I, "phylactery_max_per_dungeon": I,
	"clones_ready": I, "warden": {"archetype": S, "tier": I}, "warden_spec": D, "loot_table_id": S,
	"loot_hint": S, "chest_husk": B, "watchtower": B, "relish_hp": F,
}
const BOSS_SEED := {
	"v": I, "kind": S, "run_id": I, "seed_rev": I, "rng_seed": S,
	"backlog": F, "living_pool": F, "odds": F, "sign": I, "drain_s": F, "digest_q": F, "vei_capacity": F,
	"fronts": [{"id": S, "need": F, "have": F, "assigned": [S]}], "fronts_required": I,
	"party": [BOSS_PARTY], "phylactery_charges": I, "clones_ready": I, "relish_hp": F,
}

# --------------------------------------------------------------- results (§8) ----
const RESULTS := {
	"raid": {
		"v": I, "run_id": I, "seed_rev": I, "fort_id": S,
		"warden_beaten": B, "retreated": B, "relish_died": B, "revived_in_place": I,
		"killed_living_mass": F, "raised": [{"score": I, "count": I, "mass": F}],
		"chaff_mass": F, "garrison_mass": F, "party_lost": [S],
		"loot": {"relics": I, "blueprints": [S], "husks": [{"kind": S}],
			"remnants": [{"aspect": S, "rarity": S, "magnitude": I}], "essence": I},
	},
	"boss": {
		"v": I, "run_id": I, "seed_rev": I, "won": B, "fronts_cleared": [S], "relish_deaths": I,
		"backups_spent": {"phylactery": I, "clones": I}, "party_lost": [S], "backlog_spent": F,
	},
	"town": {"v": I, "teleport_to": S},
	"map": {"v": I, "teleport_to": S},
}

# --------------------------------------------------------- commands (§4): extras ----
## Every command also returns ok: bool and reason: String. Extras are present on failure
## too; a nested Dictionary extra is {} on failure, and its keys are checked only when ok.
const COMMANDS := {
	"cmd_new_game": {},
	"cmd_save": {"saved_at": I, "path": S},
	"cmd_load": {},
	"cmd_set_time_scale": {"time_scale": F},
	"cmd_pause": {"paused": B},
	"cmd_set_valve": {"target": VALVE},
	"cmd_move_relish": {"eta_s": F},
	"cmd_cancel_travel": {"eta_s": F},
	"cmd_set_haul_target": {"haul_target": S},
	"cmd_build": {"cost": COST},
	"cmd_upgrade": {"level": I, "cost": COST},
	"cmd_demolish": {},
	"cmd_cancel_build": {"refund": COST},
	"cmd_set_job_priority": {"order": [S]},
	"cmd_set_staff_cap": {"cap": I},
	"cmd_set_stance": {"slots": I, "used": I},
	"cmd_raise_big_undead": {"big_undead": BIG_UNDEAD},
	"cmd_rename_big_undead": {"name": S},
	"cmd_place_big_undead": {"place": S},
	"cmd_craft": {"count": I},
	"cmd_deploy_simulacrum": {"charges": F, "ready_left": I},
	"cmd_staff_vat": {"staffed": B},
	"cmd_set_party": {"party": [S]},
	"cmd_assign_front": {},
	"cmd_begin_dungeon": {"seed": RAID_SEED, "run_id": I, "seed_rev": I},
	"cmd_begin_boss": {"seed": BOSS_SEED, "run_id": I, "seed_rev": I},
	"cmd_abort_dungeon": {"run_id": I},
	"apply_result": {"errors": [S], "minted": [S]},
	"cmd_debug_grant": {"key": S, "applied": {"minted": [S]}},
	"cmd_debug_set_state": {"key": S},
	"cmd_debug_load_fixture": {},
	"cmd_debug_skip_time": {"substeps": I},
}

## Every reason each command may return (§4), in the doc's check order.
const REASONS := {
	"cmd_new_game": ["busy"],
	"cmd_save": ["bad_slot", "write_failed"],
	"cmd_load": ["busy", "bad_slot", "no_save", "bad_version"],
	"cmd_set_time_scale": ["not_debug", "in_dungeon", "in_boss", "invalid_scale"],
	"cmd_pause": ["not_debug"],
	"cmd_set_valve": ["not_finite", "negative", "zero_valve"],
	"cmd_move_relish": ["dead", "in_dungeon", "in_boss", "unknown_node"],
	"cmd_cancel_travel": ["not_travelling"],
	"cmd_set_haul_target": ["unknown_fort"],
	"cmd_build": ["unknown_building", "unknown_lot", "unique", "lot_locked", "lot_taken", "lot_too_small",
		"needs_tier", "needs_blueprint", "needs_building", "no_gold", "no_bone", "no_relics"],
	"cmd_upgrade": ["unknown_lot", "empty_lot", "under_construction", "unpaid", "max_level", "needs_tier",
		"no_gold", "no_bone", "no_relics"],
	"cmd_demolish": ["unknown_lot", "empty_lot", "under_construction", "protected"],
	"cmd_cancel_build": ["unknown_lot", "not_building"],
	"cmd_set_job_priority": ["unknown_job", "duplicate_job", "missing_job"],
	"cmd_set_staff_cap": ["unknown_lot", "empty_lot", "no_jobs", "bad_cap"],
	"cmd_set_stance": ["unknown_stance", "no_slot"],
	"cmd_raise_big_undead": ["not_home", "unknown_husk", "unknown_remnant", "duplicate_remnant",
		"invalid_recipe", "at_cap", "bad_name"],
	"cmd_rename_big_undead": ["unknown_uid", "bad_name"],
	"cmd_place_big_undead": ["unknown_uid", "busy", "bad_place", "unknown_lot", "empty_lot",
		"foreman_taken", "unknown_fort"],
	"cmd_craft": ["unknown_item", "needs_building", "no_essence", "no_relics"],
	"cmd_deploy_simulacrum": ["unknown_fort", "none_ready"],
	"cmd_staff_vat": ["unknown_slot"],
	"cmd_set_party": ["busy", "unknown_uid", "duplicate_uid"],
	"cmd_assign_front": ["busy", "unknown_uid", "not_in_party", "unknown_front"],
	"cmd_begin_dungeon": ["unknown_fort", "busy", "dead", "not_at_fort"],
	"cmd_begin_boss": ["busy", "dead", "not_at_vei"],
	"cmd_abort_dungeon": ["no_run"],
	"apply_result": ["unknown_kind", "unknown_v", "invalid", "duplicate_run", "wrong_run", "wrong_kind",
		"stale_seed", "wrong_fort", "bad_revives", "bad_party", "bad_backups"],
	"cmd_debug_grant": ["not_debug", "unknown_key", "bad_value"],
	"cmd_debug_set_state": ["not_debug", "unknown_key", "bad_value", "busy"],
	"cmd_debug_load_fixture": ["not_debug", "busy", "unknown_fixture", "bad_fixture"],
	"cmd_debug_skip_time": ["not_debug", "bad_value"],
}

# ------------------------------------------------------------------ views (§5) ----
const FORT := {
	"id": S, "name": S, "tier": I, "cap": F, "pos": POS,
	"living": F, "undead": F, "dead": F, "space": F, "war_in": F, "ship_in": F,
	"held": B, "held_s_left": F, "flipped_count": I, "first_clear": B, "first_dungeon": B,
	"clears_since_retaken": I, "yield_mult": F,
	"warden": {"archetype": S, "tells": [S]}, "loot_hint": S,
	"threat": {"party_strength": F, "garrison_strength": F, "risk": S, "risk_pct": F},
	"relish_here": B, "tide": B, "redirect": B, "simulacrum_charges": F, "siege": [S],
	"tithe": {"targeted": B, "eta_s": F, "wave_active": B},
	"can_descend": B, "reason": S,
	# api_version 6 (E2b-2 T3.1, api-requests #7 a, #13): the held fort's readouts and its grace
	"garrison": F, "garrison_rate": F, "fall_s": F, "margin": S, "margin_cause": S, "grace_s_left": F,
}
const TOWN_BUILDING := {
	"lot_id": S, "building_id": S, "level": I, "state": S, "progress": F, "slots": I, "staffed": F,
	"staff_cap": I, "foreman": S, "output": {"*": F}, "upkeep": UPKEEP,
}
const CATALOG_BUILDING := {
	"building_id": S, "cost": COST, "upkeep": UPKEEP, "build_work": F, "lot_size": I, "max_level": I,
	"count": I, "requires": {"tier": S, "blueprint": S, "building": S}, "can_build": B, "reason": S,
	"lots": [S],
}

## Views without `rev` (every view carries `rev: int` except the two seed views, §7).
const VIEWS := {
	"view_hud": {
		"game_id": S, "t": F, "time_scale": F, "paused": B,
		"rates": [{"id": S, "rate": F, "stock": F, "cap": F, "unit": S}],
		"split": VALVE, "valve": VALVE, "valve_target": VALVE, "workers_steady": F, "workers_steady_kept": F, "war_overflow": F,
		"war_supports": {"n": I, "m": I},
		"relics": I, "relics_cap": I, "essence": I, "essence_cap": I,
		"sign": I, "drain_s": F, "odds": F, "won": B,
	},
	"view_rates": {"rates": {"*": {"in": F, "out": F, "net": F, "unit": S}}},
	"view_lanes": {"lanes": [{"id": S, "from": S, "to": S, "kind": S, "rate": F, "bias": F, "why": S}]},
	"view_realm": {
		"size": POS, "covington": {"pos": POS},
		"vei": {"pos": POS, "radius": F, "living_pool": F, "pool_cap": F, "backlog": F},
		"forts": [FORT], "held_count": I, "digest_q": F,
	},
	"view_fort": FORT,
	"view_field": {"field": O, "world_size": POS, "tick_hz": F},
	"view_villages": {"villages": [{"id": S, "name": S, "pos": POS, "owner": S, "dominance": F, "migrants": F}]},
	"view_relish": {
		"state": S, "at": S, "target": S, "pos": POS, "heading": F, "speed": F, "eta_s": F,
		"dead_s_left": F, "respawn_with_clone": B, "phylactery_charges": I, "clones_ready": I,
		"can_descend": B, "reason": S, "run_id": I, "run_kind": S,
		"effects": {"tide_fort": S, "redirect_fort": S, "home": B},
	},
	"view_town": {
		"tier": S, "next_tier": {"tier": S, "have": I, "need": I, "missing": [S]},
		"lots": [{"id": S, "size": I, "unlocked": B, "building_id": S}],
		"buildings": [TOWN_BUILDING], "ladder": [S], "ladder_effective": [S],
		"jobs": [{"id": S, "slots": I, "staffed": F}],
		"workers": {"total": F, "idle": F, "in": F, "rot": F, "muster": F, "steady": F, "steady_kept": F, "muster_steady": F, "lifetime_s": F},
		"living": F, "living_cap": F, "migrants": F, "departures": F,
		"morale": {"value": F, "target": F, "factors": [{"id": S, "delta": F}]},
		"gold": F, "bone": F, "bodies": F, "bodies_cap": F, "trade_rate": F,
		"haul": {"target": S, "current": S,
			"convoys": [{"from": S, "to": S, "phase": S, "t": F, "load": F}]},
		"relish_home": B,
	},
	"view_catalog": {
		"buildings": [CATALOG_BUILDING],
		"crafts": [{"item_id": S, "cost": {"essence": I, "relics": I}, "can_craft": B, "reason": S}],
		"blueprints": [{"id": S, "owned": B}],
	},
	"view_stances": {
		"slots": I, "used": I, "beat_id": I,
		"stances": [{"id": S, "on": B, "suspended": B, "active": B, "fired_beat_id": I,
			"hold_s_left": F, "projected": {"*": F}}],
	},
	"view_inventory": {
		"husks": [{"uid": S, "kind": S}],
		"remnants": [{"uid": S, "aspect": S, "rarity": S, "magnitude": I}],
		"blueprints": [S], "relics": I, "relics_cap": I, "essence": I, "essence_cap": I,
		"simulacra_ready": I, "phylactery_charges": I,
	},
	"view_big_undead": {"cap": I, "count": I, "big_undead": [BIG_UNDEAD]},
	"view_party": {
		"party": [BIG_UNDEAD], "fort_id": S, "garrison_units": I, "garrison_in_mass": F,
		"starter_units": I, "strength": F,
	},
	"view_backups": {
		"phylactery_charges": I, "phylactery_max_per_dungeon": I, "clones_ready": I,
		"vats": [{"slot": I, "staffed": B, "grow": F, "ready": B}],
		"death": {"outcome": S, "respawn_s": F, "loses": [S]}, "dead_s_left": F,
	},
	"view_vei": {
		"backlog": F, "living_pool": F, "pool_cap": F, "diff": F, "diff_ema": F,
		"sign": I, "drain_s": F, "odds": F, "digest_q": F,
		"fronts": [{"id": S, "need": F, "have": F, "cleared": B, "assigned": [S]}],
		"fronts_required": I, "fronts_met": I,
		"tithe": {"target": S, "eta_s": F, "warning": B, "wave_active": B, "wave_s_left": F},
		"can_begin": B, "reason": S, "won": B,
	},
	"view_dungeon_seed": RAID_SEED,
	"view_boss_seed": BOSS_SEED,
	# api_version 5 (E2b T4.P, api-request #16): takes `order` (and optionally `vats`); `reason` is "" or
	# the cmd_set_job_priority refusal its `order` would get
	"view_staffing_projection": {"jobs": [{"id": S, "slots": I, "staffed": F}], "buildings": [{"lot_id": S, "staffed": F}],
		"idle": F, "reason": S},
	# api_version 6 (E2b-2 T3.1, api-requests #7 c, #13): takes `valve`
	"view_projection": {"valve": VALVE, "split": {"work": F, "war": F, "flood": F, "war_overflow": F}, "workers_steady": F,
		"backlog_diff": F, "war_supports": {"n": I, "m": I},
		"margins": {"*": {"margin": S, "margin_cause": S, "fall_s": F, "garrison_rate": F}}},
}
## Views that take an id argument (and return {} for an unknown one).
const VIEW_ARGS := {"view_fort": 1, "view_dungeon_seed": 1}
## Views whose result carries no `rev` (the seeds are deep copies of what cmd_begin_* returned).
const NO_REV := ["view_dungeon_seed", "view_boss_seed"]

# ----------------------------------------------------------------- events (§6) ----
## Fields besides t: float and type: String, which every event carries.
const EVENTS := {
	"relish_died": {"outcome": S, "in_place": B, "at": S, "run_id": I, "respawn_s": F},
	"relish_respawned": {"with_clone": B, "at": S},
	"building_started": {"lot_id": S, "building_id": S, "level": I, "upgrade": B},
	"building_done": {"lot_id": S, "building_id": S, "level": I},
	"building_unpaid": {"lot_id": S, "building_id": S, "unpaid": B},
	"tier_up": {"tier": S, "from": S},
	"fort_flipped": {"fort_id": S, "run_id": I, "hold_s": F},
	"fort_retaken": {"fort_id": S, "cause": S},
	# api_version 6 (E2b-2 T3.1): a siege big undead at a retaken fort returns to the crypt (IDLE I6)
	"big_undead_returned": {"uid": S, "fort_id": S},
	# api_version 6 (E2b-2 T3.1, api-request #10): a held fort's raid cleared its counter-garrison
	"counter_garrison_cleared": {"fort_id": S, "killed_mass": F},
	"tithe_warning": {"wave_id": I, "fort_id": S, "eta_s": F, "surge": F},
	"tithe_wave": {"wave_id": I, "fort_id": S, "surge": F, "duration_s": F, "relish_here": B, "siege_block": F},
	"stance_fired": {"stance_id": S, "active": B, "beat_id": I},
	"loot_banked": {"run_id": I, "fort_id": S, "relics": I, "essence": I, "blueprints": [S], "minted": [S]},
	"vei_result": {"run_id": I, "won": B, "fronts_cleared": [S], "relish_deaths": I, "backlog_after": F},
	"autosaved": {"slot": S, "saved_at": I},
	"save_failed": {"slot": S, "reason": S},
}

# ----------------------------------------------------------- members (§1.5, §4) ----
## api_version 3 added sources.opening, sinks rot_overflow, haul_overflow and store_overflow, and
## held.work_pending.
const LEDGER := {
	"sources": {"mint": F, "debug": F, "opening": F},
	"sinks": {"cleared": F, "rot_loss": F, "burned": F, "milled": F, "vei_fight": F, "dungeon": F,
		"pool_overflow": F, "rot_overflow": F, "haul_overflow": F, "store_overflow": F},
	"held": {"fort_living": F, "fort_undead": F, "corpses": F, "backlog": F, "vei_dead": F,
		"living_pool": F, "bodies": F, "workers": F, "convoys": F, "work_pending": F},
}
const LIST_SAVES := [{"slot": S, "saved_at": I, "summary": S}]
## to_dict() (§9.1): the top-level keys and their exact types. Blocks whose insides E2/E3 will
## change are opaque (D); the rest are typed.
## `game_id` is optional on load (a save without it gets its seed's id, §9.1) but to_dict always writes it,
## so this schema, which checks to_dict's output, requires it.
const SAVE := {
	"v": I, "api_version": I, "game_id": S, "seed": S, "rng": S, "t": F, "acc": F, "next_run_id": I, "next_uid": I,
	"applied_runs": [I],
	"relish": {"state": S, "at": S, "target": S, "pos": POS, "heading": F, "dead_s_left": F, "respawn_with_clone": B},
	"valve": {"target": VALVE, "current": VALVE},
	"realm": D, "villages": [{"id": S, "owner": S}], "town": D, "stances": D, "inventory": D,
	"big_undead": [D], "party": [S], "backups": D, "readout": {"diff_ema": F, "q_raise_ema": F},
	"ledger": {"sources": {"*": F}, "sinks": {"*": F}},
	"won": B, "stats": {"raised_total": F, "raids": I, "deaths": I, "sims_built": I},
	"cleared_forts": [S], "first_dungeon": S,
}
## Methods on GameState besides the commands and views (§1.5).
const MEMBER_METHODS := ["_init", "setup", "load_configs", "tick", "drain_events", "to_dict", "from_dict",
	"migrate", "list_saves", "ledger"]
const MEMBER_VARS := ["debug_enabled", "save_dir", "rev"]
## Contract names not implemented yet (none after T1.5). The contract test fails if a listed name
## exists, so the list cannot go stale.
const EXPECTED_MISSING := []


## Appends one message per mismatch to `errs`, each naming the path
## (e.g. "view_town.buildings[0].upkeep.gold: expected float, got int").
## `seen` collects the schema paths of arrays and maps that held at least one element
## (indices written as "[]", map keys as ".*"), so a caller can tell which element
## schemas actually ran; see containers().
static func check(v: Variant, spec: Variant, path: String, errs: Array, seen: Dictionary = {}) -> void:
	_check(v, spec, path, path, errs, seen)


static func _check(v: Variant, spec: Variant, path: String, npath: String, errs: Array, seen: Dictionary) -> void:
	if typeof(spec) == TYPE_INT:
		if typeof(v) != spec:
			errs.append("%s: expected %s, got %s" % [path, type_string(spec), type_string(typeof(v))])
		elif spec == TYPE_FLOAT and not is_finite(v):
			errs.append("%s: non-finite float %s" % [path, str(v)])
		return
	if spec is Array:
		if typeof(v) != TYPE_ARRAY:
			errs.append("%s: expected Array, got %s" % [path, type_string(typeof(v))])
			return
		if not v.is_empty():
			seen[npath] = true
		for i in v.size():
			_check(v[i], spec[0], "%s[%d]" % [path, i], npath + "[]", errs, seen)
		return
	if typeof(v) != TYPE_DICTIONARY:
		errs.append("%s: expected Dictionary, got %s" % [path, type_string(typeof(v))])
		return
	if spec.has("*"):
		if not v.is_empty():
			seen[npath] = true
		for k in v:
			if typeof(k) != TYPE_STRING:
				errs.append("%s: key %s is not a String" % [path, str(k)])
			_check(v[k], spec["*"], "%s.%s" % [path, str(k)], npath + ".*", errs, seen)
		return
	for k in spec:
		if not v.has(k):
			errs.append("%s.%s: missing" % [path, k])
		else:
			_check(v[k], spec[k], "%s.%s" % [path, k], "%s.%s" % [npath, k], errs, seen)


## Every array and map path in `spec` (in check()'s `seen` notation), appended to `out`.
static func containers(spec: Variant, npath: String, out: Array) -> void:
	if spec is Array:
		out.append(npath)
		containers(spec[0], npath + "[]", out)
	elif spec is Dictionary and spec.has("*"):
		out.append(npath)
		containers(spec["*"], npath + ".*", out)
	elif spec is Dictionary:
		for k in spec:
			containers(spec[k], "%s.%s" % [npath, k], out)


## A command's return: ok, reason (== "" iff ok, else one of its reasons) and its extras.
## On failure a nested Dictionary extra must be {} and is not key-checked (§1.3).
static func check_command(name: String, r: Variant, errs: Array, seen: Dictionary = {}) -> void:
	if typeof(r) != TYPE_DICTIONARY:
		errs.append("%s: expected Dictionary, got %s" % [name, type_string(typeof(r))])
		return
	check(r, {"ok": B, "reason": S}, name, errs)
	if typeof(r.get("ok")) != TYPE_BOOL:
		return
	var ok: bool = r["ok"]
	var reason: Variant = r.get("reason", "")
	if ok and reason != "":
		errs.append("%s: ok with reason '%s'" % [name, str(reason)])
	if not ok and not (REASONS[name] as Array).has(reason):
		errs.append("%s: reason '%s' is not one of %s" % [name, str(reason), str(REASONS[name])])
	var extras: Dictionary = COMMANDS[name]
	for k in extras:
		var path := "%s.%s" % [name, k]
		if not r.has(k):
			errs.append("%s: missing" % path)
		elif not ok and extras[k] is Dictionary:
			if typeof(r[k]) != TYPE_DICTIONARY or not r[k].is_empty():
				errs.append("%s: a failed command's nested extra must be {}, got %s" % [path, str(r[k])])
		else:
			check(r[k], extras[k], path, errs, seen)
	non_finite(r, name, errs)


## Every float anywhere in `v`, schema or not, must be finite (§1.3: no INF or NaN).
static func non_finite(v: Variant, path: String, errs: Array) -> void:
	match typeof(v):
		TYPE_FLOAT:
			if not is_finite(v):
				errs.append("%s: non-finite float %s" % [path, str(v)])
		TYPE_ARRAY:
			for i in v.size():
				non_finite(v[i], "%s[%d]" % [path, i], errs)
		TYPE_DICTIONARY:
			for k in v:
				non_finite(v[k], "%s.%s" % [path, str(k)], errs)
