class_name GameState
extends RefCounted
## All game state and logic, headless. The Game autoload is a thin shell over one
## of these. Configs are injected through setup(); randomness comes from `rng`.
## Files in scripts/sim/ never reference an autoload or Engine (a lint test
## enforces this). No signals: consumers poll
## `rev` and drain_events(). The contract is docs/STATE-API.md.

const API_VERSION := 13
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
## Every config value GameState (and StateRuns and StateViews for it) reads with no fallback, as
## "file.section.key" paths (E2b-2 T3.2: tunables whose inline defaults duplicated the configs). setup()
## checks every one (_req), so a missing key is an error at load, not a silent default, and
## tests/test_game_state_configs.gd asserts each one is present in res://configs. The first four, and the
## ones the core step and the field's sources read every step (E2b-2 T3.3b, catch-up's budget: the
## members below), are read once in setup(); the rest are read live at each use (_req_f), since tests
## change some of them after setup (realm.q.q0, realm.relish.home_stance_bonus, economy.stance.base_slots
## and others).
const REQUIRED := ["realm.relish.raise_rate", "realm.hold.clear_min_living", "loot.recover_s", "loot.reclear_decay",
	"economy.town.projection_refresh_s", "economy.town.projection_rows_per_call", "economy.town.projection_rows_per_frame",
	"economy.town.projection_phase", "economy.town.projection_starve_frames", "economy.town.projection_tol.rel",
	"economy.town.projection_tol.abs", "realm.flip.hold_s", "realm.flip.tier_mult", "economy.morale.death_shock", "vei.loss_backlog_keep",
	"realm.relish.tide_bias", "economy.queue.max_len", "economy.queue.list_mult", "economy.save.level_sanity_max",
	"economy.relic_trickle.period_s",
	"realm.hold.mint_ref", "realm.hold.mint_alpha",  # (E4 step 5, B1: hold_mult)
	"realm.odds.time_weight", "realm.odds.time_s", "realm.odds.backlog_cap",  # (E4 step 9, option B: win_odds)
	# T3.4a: the economy and realm tunables that had inline numeric fallbacks (the realm `field` block aside)
	"economy.sim.substep_s", "economy.sim.max_substeps_per_frame", "economy.sim.autosave_s", "economy.sim.prewarm_dt",
	"economy.sim.prewarm_ticks", "economy.opening.valve.work", "economy.opening.valve.war", "economy.opening.valve.flood",
	"economy.opening.starter_party", "economy.stance.base_slots", "economy.worker.mass", "economy.pit.bonus",
	"economy.town.migrant_rate",
	"realm.relish.travel_speed", "realm.relish.home_stance_bonus", "realm.readout.sign_eps", "realm.readout.ema_s",
	"realm.vei_pool_cap", "realm.field_src_per_pit", "realm.valve.slew_per_s", "realm.P_base", "realm.P_per_pit", "realm.R_vei", "realm.K",
	"realm.q.q0", "realm.q.q_forge", "realm.q.q_raise_max", "realm.q.q_max", "realm.q.raise_half_mass",
	# T3.4b: the wave train's frame refresh (_train_frame)
	"realm.hold.train_frame_phase", "realm.hold.train_starve_frames",
	# T3.3b: the catch-up runner (Catchup; IDLE §4) and the clip events it reads
	"economy.idle.gap_s", "economy.idle.catchup_max_s", "economy.idle.catchup_dt_max_s", "economy.idle.catchup_max_steps",
	"economy.idle.catchup_tol", "economy.idle.field_steps", "economy.idle.field_step_min_s", "economy.idle.report_min_s",
	"economy.idle.catchup_steps_per_chunk", "economy.idle.catchup_dt_long_s", "economy.idle.catchup_dt_long_after_s",
	"realm.tithe.warning_s",
	# E3-3: the siege's block of a tithe wave (MECHANICS §3.4; _siege_blocks)
	"realm.tithe.siege_block",
	# T3.3c: the away report's text (StateViews.away_report; its keys are REPORT_KEYS, checked in setup)
	"economy.idle.report",
	# E3-1: the stances (MECHANICS §4.5; _stance_step): the hold, the ladder stances' jobs and order, the
	# thresholds, and the beat they are read at (Thrift's two keys are TownSim's)
	"economy.stance.hold_s", "economy.stance.top_job", "economy.stance.priority", "economy.stance.harvest_bodies_frac",
	"economy.stance.hearth_morale", "pulse.tempo_ms",
	# E4 (the A1 day-1 ruling): a new game's bone edge (view_hud.bone_war_share) and the mill's lever per starved reason
	"economy.opening.bone_edge.war_share", "economy.town.starved_lever",
	# E3-2: the backups (MECHANICS §7): a tended vat's growth (_grow_vats), the death rule's respawns
	# (StateViews.death_rule) and the phylactery's revives per dungeon (_phylactery_max)
	"backups.vats.grow_per_s", "backups.backups.clone_respawn_s", "backups.backups.unmade_respawn_s",
	"backups.phylactery.max_per_dungeon",
	# E3-4: the crafts' costs (MECHANICS §3.6; cmd_craft and view_catalog's crafts, _craft_cost)
	"economy.craft.simulacrum.essence", "economy.craft.simulacrum.relics", "economy.craft.phylactery_charge.essence",
	"economy.craft.phylactery_charge.relics",
	# E4 (the sizing stop's ruling 2, lever (b)): the husk craft's price (cmd_craft_husk, view_catalog's husk_craft)
	"economy.craft.husk.bone", "economy.craft.husk.remnants",
	# E3-4: a planted simulacrum's raise and charges (MECHANICS §3.6; cmd_deploy_simulacrum)
	"realm.simulacrum.rate", "realm.simulacrum.charges"]
## economy.json idle.report's keys (E2b-2 T3.3c, IDLE §7): the away report's templates and its three numbers.
## setup() checks each is there, and that `waited_on` words every queue reason in REPORT_WAITED_ON.
const REPORT_KEYS := ["streams", "stream_labels", "stream_fmt", "backlog_fmt", "arrow_up", "arrow_down", "arrow_flat",
	"plus", "minus", "rate_unit", "thousands", "rate_sig_digits", "rate_max_decimals", "builds_one_fmt", "builds_fmt",
	"list_sep", "level_fmt", "started_fmt", "started_now_fmt", "when_hm_fmt", "when_m_fmt", "waited_on", "refilled_fmt",
	"raid_fmt", "husk_one_fmt", "husks_fmt", "queue_empty", "retaken_fmt", "retaken_home_fmt", "village_lost_fmt",
	"overflow_fmt", "store_labels", "overflow_min",
	# R1: the losses' unpaid lines (one per building unpaid during the absence; StateViews.away_report)
	"unpaid_fmt", "unpaid_sep", "unpaid_stopped", "unpaid_inert",
	# R2: ready's line for the queue's head still waiting (StateViews.afford_text) and the full stores' raid prompt
	"afford_wait_fmt", "afford_never_fmt", "afford_stores", "afford_raise", "full_tol", "full_raid",
	# F1: that line without the move down when nothing is behind the head, and its forms for a head that is its
	# store's own producer (the raise never names the entry itself)
	"afford_never_last_fmt", "afford_never_self_fmt", "afford_never_self_last_fmt", "afford_producer", "afford_raise_self",
	# W: the unpaid line under a minute ("briefly") and, when it stopped nothing, without its tail; the stuck head
	# short of relics in Shawn's words, with and without the move down
	"unpaid_brief_fmt", "unpaid_none_fmt", "unpaid_none_brief_fmt", "afford_relics_last_fmt",
	# W2: a start that waited but began within a minute of you leaving ("started within a minute of you leaving, ...")
	"started_brief_fmt",
	# E3-1: the losses' Thrift lines (one per building the Thrift stance idled during the absence; kind `unpaid`)
	"thrift_fmt", "thrift_brief_fmt", "thrift_none_fmt", "thrift_none_brief_fmt",
	# E4 step 4 (v10): ready's line for the first entry the upkeep gate holds (BuildRules.upkeep_short), and the one for
	# the buildings the resume rule's income test keeps unpaid (TownSim.held_by_income)
	"afford_upkeep_fmt", "unpaid_upkeep_fmt",
	# E4 (the A1 day-1 ruling): a head that can never be afforded on bone while the pits eat every body (the mill
	# starved pits_first): the bone it is short of and the lever, with and without the move down
	"afford_starved_fmt", "afford_starved_last_fmt",
	# E4 step 10 (review-t7r1r2 §5, the Market side): never on gold while the living buy less than the stalls can sell
	# (TownSim.trade_starved living_first), with and without the move down; and the upkeep line's form for that state
	"afford_living_fmt", "afford_living_last_fmt", "afford_upkeep_living_fmt",
	# Phase I P2 (Q-d): the income test's unpaid line in that state (housing or an Inn, not a Market), and the never-on-gold
	# line for a head whose gold covers it now but falls under it by the time its bone comes (no "0 gold short")
	"unpaid_upkeep_living_fmt", "afford_living_falling_fmt", "afford_living_falling_last_fmt"]
## The reasons a queued build's waited_on can hold (STATE-API §6 queue_started): idle.report.waited_on words each.
const REPORT_WAITED_ON := ["needs_tier", "lot_locked", "needs_blueprint", "needs_building", "no_relics", "no_gold",
	"no_bone", "lot_taken", "empty_lot", "under_construction", "unpaid", "cost_exceeds_cap", "upkeep", "wait_slot"]
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
## How long a lane's `why` callout lasts, in sim seconds (STATE-API §5.3).
const _WHY_S := 10.0
## _train's answer with no fort held (train_probe's shape; read-only).
const _TRAIN_NONE := {"forts": {}, "settled": true, "p": 0, "cycles": 0, "steps": 0, "targets": []}

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
## Her last walk home from a retaken fort (IDLE I5, E2b-2 T3.3c; _walk_home): {fort_id, cause: "retaken", t},
## or {} when there has been none since the new game. view_relish().returned; saved as relish.returned.
var relish_returned := {}
## When she arrived at the node she stands at during this core step (step 4), -INF when she was standing there
## from its start (or isn't standing): a retake in the step before it doesn't send her home (_emit_realm).
## Session only, set every core step.
var _arrived_t := -INF
# --- runs and seeds (§4.5, §7) ---
var run := {}  # {} or {run_id, kind: "raid"|"boss", fort_id, seed_rev, seed}
var next_run_id := 1
var next_uid := 1  # one counter for h<n>, r<n>, u<n>
var game_seed := 0
var first_dungeon_id := ""  # "" once a won raid result has cleared it (T1.4)
var cleared_forts := {}  # fort_id -> true once a win has spent its first clear (T1.4)
# --- stocks and inventories (views §5.12) ---
var relics := 0
## The idle relic trickle (E4 step 9, ruling 3; _relic_trickle): the paying seconds toward its next relic (saved,
## inventory.relic_trickle_s, optional: a save without it reads 0), and the relics it paid this session (not saved;
## the bots' tally)
var relic_trickle_s := 0.0
var trickle_paid := 0
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
## The build queue (IDLE §5, STATE-API §4.3; BuildRules.queue_walk): [{building_id, lot_id, upgrade: bool,
## waited_on: String}] in order, at most economy.json queue.max_len. Saved (an optional `queue` key).
var build_queue: Array = []
var vats_staffed: Array = []  # bool per vat slot
## E3-2 (MECHANICS §7): each vat's clone, 0..1 per vat slot (view_backups' numbering; a slot past the end reads
## 0). It grows at backups.json vats.grow_per_s × the vat's tend hands (TownSim.vat_hands) in the core step's
## backups step (_grow_vats), and a vat at 1 holds a ready clone. Saved as backups.vats[].grow.
var vats_grow: Array = []
## Ready clones kept outside the vats (the old-save rule, MECHANICS §7): a save's clones_ready above its vats
## at 1, and the ready clone of a vat that no longer exists (its Chapel demolished). Saved inside clones_ready.
var _clones_spare := 0
## Ready clones (view_backups.clones_ready): the vats at 1 plus the spare ones. No longer a free stock (E3-2).
## A death spends one (spend_clones: the lowest ready vat first, then a spare). Setting it (tests, a fixture's
## generator) sets the total: the spare clones make up what the vats at 1 don't hold, and a total below them
## empties ready vats from the lowest slot.
var clones_ready: int:
	get:
		return _vats_ready() + _clones_spare
	set(v):
		_set_clones_ready(v)
var _grow_per_s := 0.0  # backups.json vats.grow_per_s
# --- the crafted stocks (E3-4, MECHANICS §3.6, §7): fungible counts, no cap of their own (the essence and relic
# caps bound them); cmd_craft adds to them ---
## Phylactery charges (view_backups, saved as backups.phylactery_charges): a raid's revives in place spend them (E3-2).
var _phylactery_charges := 0
## Simulacra crafted and not yet planted (view_inventory.simulacra_ready; saved as inventory.simulacra_ready):
## cmd_deploy_simulacrum takes one. A planted one is RealmSim's (realm.simulacra).
var simulacra_ready := 0
# --- the stances (E3-1, MECHANICS §4.5; _stance_step). Saved as `stances`: hold, and the optional `state` ---
## stance id -> the seconds of its hold left: its `active` can't change again until it is gone (stance.hold_s
## after each change). Saved as stances.hold.
var _stance_hold := {}
## stance id -> true while its condition holds, as the stance step last let it change (STATE-API §5.11 `active`);
## absent = false. Saved in stances.state.
var _stance_active := {}
## stance id -> the beat of its last change (fired_beat_id); absent = -1, never fired. Saved in stances.state.
var _stance_fired := {}
## The beat the stance step last read the conditions at: they are read again once beat_at(t) moves. -1 after a new
## game (the first step reads them); a load sets the loaded t's beat. Session only.
var _stance_beat := -1
## The stances acting (on, not suspended, active) as _apply_stances last gave them to TownSim: {id: true}. Session
## only (a load recomputes it from the saved stance state; Thrift's idled buildings are saved as theirs).
var _stance_acting := {}
## view_stances' projections, cached: [[rev, t, TownSim.structure_rev], {stance id: projected}] (StateViews.
## stance_projections). Session only.
var _stance_proj: Array = []
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
# ---- tunables read once in setup() from REQUIRED (no numbers here) ----
var _raise_rate := 0.0  # realm.json relish.raise_rate: mass/s Relish raises where she redirects
var _clear_min_living := 0.0  # realm.json hold.clear_min_living: the dungeon's spawn floor, mirrored
var _recover_s := 0.0  # loot.json recover_s: a fort's loot yield back to 1 over this many seconds
var _reclear_decay := 0.0  # loot.json reclear_decay: the yield × this per clear that paid loot
# ---- the per-step tunables (E2b-2 T3.3b, catch-up's budget, lever 1: a _req_f costs about 0.9 µs and the
# core step made 10 to 14 of them), read once in setup() from REQUIRED; no test changes them after setup.
# realm.q.q0 and realm.relish.tide_bias stay live (a test changes q0 after setup; tide_bias is documented as
# read live, test_game_state_configs) ----
var _substep := 0.0  # economy.json sim.substep_s
var _slew_per_s := 0.0  # realm.json valve.slew_per_s
var _p_base := 0.0  # realm.json P_base
var _p_per_pit := 0.0  # realm.json P_per_pit
var _pit_bonus := 0.0  # economy.json pit.bonus
var _mint_ref := 0.0  # realm.json hold.mint_ref (E4 step 5, B1: hold_mult)
var _mint_alpha := 0.0  # realm.json hold.mint_alpha
var _q_raise_max := 0.0  # realm.json q.q_raise_max (q.q0 stays live: a test changes it after setup)
var _q_forge := 0.0  # realm.json q.q_forge
var _q_max := 0.0  # realm.json q.q_max
var _ema_s := 0.0  # realm.json readout.ema_s
var _travel_speed := 0.0  # realm.json relish.travel_speed
var _tithe_warning_s := 0.0  # realm.json tithe.warning_s (the catch-up's clip events)
var _src_per_pit := 0.0  # realm.json field_src_per_pit
var _vei_pool_cap := 0.0  # realm.json vei_pool_cap
var _gap_s := 0.0  # economy.json idle.gap_s (every frame's gap check)
# the stance step's tunables (E3-1; read once: the core step reads them every step)
var _beat_s := 0.0  # pulse.json tempo_ms / 1000: a beat, sim seconds
var _stance_hold_s := 0.0  # economy.json stance.hold_s
var _harvest_frac := 0.0  # economy.json stance.harvest_bodies_frac
var _hearth_morale := 0.0  # economy.json stance.hearth_morale
var _stance_priority: Array = []  # economy.json stance.priority: the ladder stances, top first when several act
var _stance_top_job := {}  # economy.json stance.top_job: ladder stance id -> the job it lifts
var _bone_war_share := 0.0  # economy.json opening.bone_edge.war_share (view_hud.bone_war_share)
var _starved_lever := {}  # economy.json town.starved_lever: TownSim.mill_starved reason -> its lever id
## [TownSim.structure_rev, town_tier] when the core step last checked the tiers and none rose: the check
## (BuildRules.rise_tiers) reads only the buildings and their levels, which move structure_rev, and the
## tier, so until either moves it would find the same. Session only (E2b-2 T3.3b, lever 1).
var _tiers_seen: Array = [-1, ""]
## The core step's own fort snapshot for TownSim (_town_inputs with `reuse`), refilled in place every step
## (E2b-2 T3.3b2: a fresh one was 12 dicts and 12 arrays a step). TownSim reads it inside its step and keeps
## none of it; every other reader (StateViews' projections keep theirs) gets a fresh one. `_step_forts_of`
## holds the realm's fort dicts and positions each entry was made from. Session only.
var _step_forts: Array = []
var _step_forts_of: Array = []
## The mass ledger's sinks the core step books from TownSim's step (Ledger.sink's, inline: _core_step).
const _TOWN_SINKS := ["rot_loss", "rot_overflow", "haul_overflow", "burned", "milled"]
var _acc := 0.0
## mass/s of the last substep (step 3): the mint, its valve shares, and `muster` (TownSim's, which `flood` includes, or
## `war` while the Muster stance acts: `muster_war`; _split_of). Session only.
var _split := {"mint": 0.0, "work": 0.0, "war": 0.0, "flood": 0.0, "muster": 0.0, "muster_war": false}
## The realm's streams of the last substep for view_rates (§5.2), mass/s, as [in, out]: `corpses`
## (Σ forts: kills and redirected garrison kills in; Relish's and the simulacra's raises and k_clear
## out, the haul added at view time) and `backlog` (Vei's undead queue: its inflow in, her digestion
## out). Session only.
var _realm_flows := {"corpses": [0.0, 0.0], "backlog": [0.0, 0.0]}
var _realm_inputs := {}  # the inputs of the last RealmSim.step (step 5), for tests
## The build benefit projections (StateViews.projections, refreshed by StateViews.projection_frame): per
## part {key: {value, t, sig, for}}, the shared baseline {state, ...}, wanted_t (view_catalog's last read),
## starve (substep frames in a row), and rows_computed / rows_replaced counts (for tests and benches);
## session only, never saved, emptied by a new game and a load.
var _proj_cache := {}
## The wave train's verdicts (_train): {live: [key, result, rev, _ticks, t], valve: [key, result, rev, _ticks, t],
## read (a view read the live slot since the frame refresh last ran), starve (substep frames in a row while
## read), computed (probes run: tests, benches)}. Session only: a new game and every load (from_dict:
## cmd_load, the fixtures) empty it (_reset_train).
var _train_cache := {}
var _margin_memo := {}
var _ticks := 0  # live substeps run this session (_tick): rev less them is the commands' share of rev
var _frame_path := false  # the shell drives tick() with a substep cap (the frame path): _train may serve the last refresh
var _field_acc := 0.0
var _req_keys := {}  # REQUIRED path -> its split keys (a cache for _req)
var _events: Array = []
## The catch-up runner (IDLE §4; scripts/sim/catchup.gd): a load's catch-up and an open-game gap's.
## Session only: a new game and every load replace it.
var _catchup := Catchup.new()
## The away report (IDLE §7, E2b-2 T3.3c; StateViews.away_report): {} or {shown, away_s, capped, gains, ready,
## losses}, built at the end of a reporting catch-up (a load's, or an open-game gap's of idle.report_min_s or
## more) and kept until dismissed (shown false) or replaced. Session only, never saved: a new game and every
## load clear it.
var _away := {}
## The test seam for the wall clock (STATE-API §1.5): unix seconds "now" when ≥ 0, else the system clock.
## cmd_save stamps saved_at and cmd_load measures the time away through it (_now_unix, the sim's one read
## of the wall clock). Never saved.
var clock_override := -1


## `configs` is keyed by file basename; a non-empty dict calls setup().
func _init(configs: Dictionary = {}) -> void:
	if not configs.is_empty():
		setup(configs)


## `cfgs` is the dict returned by load_configs (keyed by file name).
func setup(cfgs: Dictionary) -> void:
	_cfgs = cfgs
	_raise_rate = _req_f("realm.relish.raise_rate")
	_clear_min_living = _req_f("realm.hold.clear_min_living")
	_recover_s = _req_f("loot.recover_s")
	_reclear_decay = _req_f("loot.reclear_decay")
	_substep = _req_f("economy.sim.substep_s")
	_slew_per_s = _req_f("realm.valve.slew_per_s")
	_p_base = _req_f("realm.P_base")
	_p_per_pit = _req_f("realm.P_per_pit")
	_pit_bonus = _req_f("economy.pit.bonus")
	_mint_ref = _req_f("realm.hold.mint_ref")
	_mint_alpha = _req_f("realm.hold.mint_alpha")
	_q_raise_max = _req_f("realm.q.q_raise_max")
	_q_forge = _req_f("realm.q.q_forge")
	_q_max = _req_f("realm.q.q_max")
	_ema_s = _req_f("realm.readout.ema_s")
	_travel_speed = _req_f("realm.relish.travel_speed")
	_tithe_warning_s = _req_f("realm.tithe.warning_s")
	_src_per_pit = _req_f("realm.field_src_per_pit")
	_vei_pool_cap = _req_f("realm.vei_pool_cap")
	_gap_s = _req_f("economy.idle.gap_s")
	_beat_s = _req_f("pulse.tempo_ms") / 1000.0
	_stance_hold_s = _req_f("economy.stance.hold_s")
	_harvest_frac = _req_f("economy.stance.harvest_bodies_frac")
	_hearth_morale = _req_f("economy.stance.hearth_morale")
	_grow_per_s = _req_f("backups.vats.grow_per_s")
	var pri: Variant = _req("economy.stance.priority")
	var top: Variant = _req("economy.stance.top_job")
	_stance_priority = (pri as Array).duplicate() if pri is Array else []
	_stance_top_job = (top as Dictionary).duplicate() if top is Dictionary else {}
	_bone_war_share = _req_f("economy.opening.bone_edge.war_share")
	var lev: Variant = _req("economy.town.starved_lever")
	_starved_lever = (lev as Dictionary).duplicate() if lev is Dictionary else {}
	for path in REQUIRED:  # the live ones too: a missing key is reported at load, not first at its use
		_req(path)
	var why_report := report_config_problem(cfgs)
	if why_report != "":
		push_error("GameState: " + why_report)
	var hold := catchup_config_problem(cfgs)
	if hold != "":
		push_error("GameState: " + hold)
	var why_stance := stance_config_problem(cfgs)
	if why_stance != "":
		push_error("GameState: " + why_stance)
		_stance_priority = []  # no ladder stance lifts a job rather than one lifting an unknown one
	town_sim.setup(cfgs)


## IDLE §4: a stance's hold (economy.json stance.hold_s) must be at least catch-up's longest step (the larger
## of idle.catchup_dt_max_s and idle.catchup_dt_long_s), or a catch-up step could flip a stance twice inside
## its hold. "" when it holds. E3-1 made stance.hold_s live (BALANCE §5), so a config without it is a problem too.
## setup() reports a problem as an error.
static func catchup_config_problem(cfgs: Dictionary) -> String:
	var eco: Dictionary = cfgs.get("economy", {})
	var stance: Variant = eco.get("stance", {})
	if not (stance is Dictionary and ((stance as Dictionary).get("hold_s") is float or (stance as Dictionary).get("hold_s") is int)):
		return "stance.hold_s is missing: a stance's hold must be at least catch-up's longest step (idle.catchup_dt_max_s, idle.catchup_dt_long_s)"
	var hold := float(stance["hold_s"])
	var idle: Dictionary = eco.get("idle", {})
	var dt_max := maxf(float(idle.get("catchup_dt_max_s", 0.0)), float(idle.get("catchup_dt_long_s", 0.0)))
	if hold < dt_max:
		return "stance.hold_s (%s s) is under catch-up's longest step, %s s (idle.catchup_dt_max_s, idle.catchup_dt_long_s): a catch-up step must not straddle a stance's hold" % [
			str(hold), str(dt_max)]
	return ""


## IDLE §7 (E2b-2 T3.3c): "" when economy.json idle.report has every key the away report reads (REPORT_KEYS),
## its `streams` are the report's seven and labelled, its `waited_on` words every queue reason
## (REPORT_WAITED_ON) and its `store_labels` gold and bone; R2: `afford_stores` words gold, bone and relics and
## `afford_raise` gold and bone (W: a head short of relics has its own line, afford_relics_last_fmt), and `full_tol` is
## in [0, 1); F1: `afford_producer` names a buildings.json building for gold
## and for bone (the stores a building makes) and for no store the tables don't word, and `afford_raise_self`
## words each producer's store; else what is missing. setup() reports it as an error.
static func report_config_problem(cfgs: Dictionary) -> String:
	var rep: Variant = cfgs.get("economy", {}).get("idle", {}).get("report")
	if not (rep is Dictionary):
		return "config economy.idle.report is missing"
	var missing: Array = []
	for k in REPORT_KEYS:
		if not (rep as Dictionary).has(k):
			missing.append(k)
	if not missing.is_empty():
		return "config economy.idle.report lacks %s" % ", ".join(PackedStringArray(missing))
	for id in rep["streams"]:
		if not (["backlog", "mint", "workers", "bodies", "gold", "bone", "living"] as Array).has(id) or not (rep["stream_labels"] as Dictionary).has(id):
			return "config economy.idle.report.streams: %s is not a report stream with a label" % str(id)
	for w in REPORT_WAITED_ON:
		if not (rep["waited_on"] as Dictionary).has(w):
			return "config economy.idle.report.waited_on has no words for %s" % w
	for k in ["gold", "bone"]:
		if not (rep["store_labels"] as Dictionary).has(k):
			return "config economy.idle.report.store_labels has no %s" % k
	# R2: the queue head's line names the store its time waits on, for every store a queue time can wait on, and
	# what raises it, for gold and bone (W: relics' line is afford_relics_last_fmt's, "raid a fort"); the raid prompt's
	# full_tol is a fraction of the cap
	for pair in [["afford_stores", ["gold", "bone", "relics"]], ["afford_raise", ["gold", "bone"]]]:
		for k in pair[1]:
			if not (rep[pair[0]] is Dictionary and (rep[pair[0]] as Dictionary).has(k)):
				return "config economy.idle.report.%s has no %s" % [pair[0], k]
	var tol: Variant = rep["full_tol"]
	if not ((tol is float or tol is int) and float(tol) >= 0.0 and float(tol) < 1.0):
		return "config economy.idle.report.full_tol (%s) is not a fraction of the cap in [0, 1)" % str(tol)
	# F1: a head that is its store's own producer gets afford_raise_self's words, not afford_raise's (which would
	# name it): the producer of each store a building makes is a real building, and its store has those words
	var prod: Variant = rep["afford_producer"]
	var own: Variant = rep["afford_raise_self"]
	if not (prod is Dictionary and own is Dictionary):
		return "config economy.idle.report.afford_producer and afford_raise_self must be tables by store"
	var bdefs: Variant = cfgs.get("buildings", {})
	for k in ["gold", "bone"]:
		if not (prod as Dictionary).has(k):
			return "config economy.idle.report.afford_producer has no %s" % k
	for k in prod:
		if not (rep["afford_stores"] as Dictionary).has(k):
			return "config economy.idle.report.afford_producer.%s is not a store afford_stores words" % str(k)
		if not (bdefs is Dictionary and (bdefs as Dictionary).has(str(prod[k]))):
			return "config economy.idle.report.afford_producer.%s (%s) is not a building in buildings.json" % [str(k), str(prod[k])]
		if not (own as Dictionary).has(k):
			return "config economy.idle.report.afford_raise_self has no %s (afford_producer names %s)" % [str(k), str(prod[k])]
	# R1: an unpaid line words what its building stopped doing, one template per job it offers and per working
	# effect it has (every effect but TownSim.CAPACITY_EFFECTS), so each one buildings.json has needs one
	var stopped: Variant = rep["unpaid_stopped"]
	if not (stopped is Dictionary):
		return "config economy.idle.report.unpaid_stopped is not a table of words"
	var bcfg: Variant = cfgs.get("buildings", {})
	# F2: `unpaid_inert` lists the effect keys nothing in the sim reads yet (an unpaid building loses nothing by
	# them): a list of strings, each an effect key some building in buildings.json has
	var inert: Variant = rep["unpaid_inert"]
	if not inert is Array:
		return "config economy.idle.report.unpaid_inert is not a list of effect keys"
	var has_effect := {}
	for bid in (bcfg as Dictionary if bcfg is Dictionary else {}):
		var fx: Variant = (bcfg as Dictionary)[bid].get("effects", {}) if (bcfg as Dictionary)[bid] is Dictionary else {}
		for k in (fx as Dictionary if fx is Dictionary else {}):
			has_effect[str(k)] = true
	for k in inert:
		if not k is String:
			return "config economy.idle.report.unpaid_inert has a non-string entry (%s)" % str(k)
		if not has_effect.has(k):
			return "config economy.idle.report.unpaid_inert has %s, an effect no building in buildings.json has" % k
	for bid in (bcfg as Dictionary if bcfg is Dictionary else {}):
		for key in unpaid_keys((bcfg as Dictionary)[bid], inert):
			if not (stopped as Dictionary).has(key):
				return "config economy.idle.report.unpaid_stopped has no words for %s (buildings.json %s)" % [key, bid]
	return ""


## What an unpaid building stops doing, as idle.report.unpaid_stopped keys (R1, IDLE §7): the jobs its
## buildings.json `def` offers slots in, then its working effects (every effect but the capacity ones, which
## an unpaid building keeps: TownSim.CAPACITY_EFFECTS), each in the def's order. F2: not the effects in `inert`
## (idle.report.unpaid_inert), which nothing in the sim reads yet, so losing them stops nothing.
static func unpaid_keys(def: Variant, inert: Array) -> Array:
	var d: Dictionary = def if def is Dictionary else {}
	var out: Array = []
	var jobs: Variant = d.get("jobs", {})
	for j in (jobs as Dictionary if jobs is Dictionary else {}):
		if int(jobs[j]) > 0:
			out.append(str(j))
	var fx: Variant = d.get("effects", {})
	for k in (fx as Dictionary if fx is Dictionary else {}):
		if not TownSim.CAPACITY_EFFECTS.has(k) and not inert.has(str(k)):
			out.append(str(k))
	return out


## The config value at a REQUIRED path. A missing one is reported loudly and reads as null.
func _req(path: String) -> Variant:
	var keys: PackedStringArray = _req_keys.get(path, PackedStringArray())
	if keys.is_empty():  # first read of this path: it must be one of REQUIRED; its split is cached (read per step)
		assert(REQUIRED.has(path), "GameState reads %s; add it to REQUIRED" % path)
		keys = path.split(".")
		_req_keys[path] = keys
	var v: Variant = _cfgs
	for k in keys:
		if not (v is Dictionary and (v as Dictionary).has(k)):
			push_error("GameState: config %s is missing" % path)
			return null
		v = v[k]
	return v


func _req_f(path: String) -> float:
	var v: Variant = _req(path)
	return float(v) if v is float or v is int else 0.0


## The lever that fixes a mill's starved reason (TownSim.mill_starved; economy.json town.starved_lever): "raise_war"
## for "pits_first" (E4, the A1 day-1 ruling: more WAR, more corpses at the forts, bodies past the pits' want);
## "" for "" and for a reason with no lever named. view_town's mill rows and queue rows read it (STATE-API §5.9).
func starved_lever(reason: String) -> String:
	return str(_starved_lever.get(reason, "")) if reason != "" else ""


func _cfg() -> Dictionary:
	return _cfgs.get("realm", {})


func _sec(file: String, section: String) -> Dictionary:
	var d: Variant = _cfgs.get(file, {}).get(section, {})
	return d if d is Dictionary else {}


func substep_s() -> float:
	return _substep


func max_substeps_per_frame() -> int:
	return int(_req_f("economy.sim.max_substeps_per_frame"))


func travel_speed() -> float:
	return _travel_speed


func drain_events() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	out.assign(_events)
	_events = []
	return out


func _emit(ev: Dictionary) -> void:
	ev["t"] = t
	_events.append(ev)


## Whether a catch-up is under way (cmd_load with `chunked`, or an open-game gap; IDLE §4): every command
## refuses with catching_up until it is done. Not contract (view_catchup is); the shell reads it.
func catching_up() -> bool:
	return _catchup.active


## A command's refusal while a catch-up runs (STATE-API §4, `catching_up`): its own failure extras,
## zero-valued. Checked first, after not_debug where that applies.
static func _refuse_catching_up(extras := {}) -> Dictionary:
	var out := {"ok": false, "reason": "catching_up"}
	out.merge(extras)
	return out


# ------------------------------------------------------------------ game -----
func cmd_new_game(seed: int) -> Dictionary:
	if _catchup.active:
		return _refuse_catching_up()
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
	_catchup = Catchup.new()
	_away = {}
	_tiers_seen = [-1, ""]
	t = 0.0
	time_scale = 1.0
	paused = false
	run = {}
	relics = 0
	relic_trickle_s = 0.0
	trickle_paid = 0
	essence = 0
	husks = []
	remnants = []
	big_undead = []
	party_uids = []
	_sync_foremen()
	valve = _normalised(_req_f("economy.opening.valve.work"), _req_f("economy.opening.valve.war"), _req_f("economy.opening.valve.flood"))
	valve_target = valve.duplicate()
	work_pending = 0.0
	_split = {"mint": 0.0, "work": 0.0, "war": 0.0, "flood": 0.0, "muster": 0.0, "muster_war": false}
	_realm_flows = {"corpses": [0.0, 0.0], "backlog": [0.0, 0.0]}
	_proj_cache = {}
	_reset_train()
	_realm_inputs = {}
	first_dungeon_id = str(opening.get("first_dungeon", "old-sluice"))
	cleared_forts = {}
	_ledger.reset(Ledger.total(_held()))  # the opening: what the board holds now
	_phylactery_charges = 0
	simulacra_ready = 0
	vats_grow = []
	_clones_spare = 0
	_readout = {"diff_ema": 0.0, "q_raise_ema": 50.0}
	_diff = 0.0
	_stance_hold = {}
	_stance_active = {}
	_stance_fired = {}
	_stance_beat = -1
	_stance_acting = {}
	_stance_proj = []
	blueprints = []
	haul_target = "auto"
	build_queue = []
	stances_on = []
	vats_staffed = []
	town_tier = "hamlet"
	relish = {
		"state": "home", "at": "covington", "target": "",
		"pos": [float(realm.cov_pos.x), float(realm.cov_pos.y)], "heading": 0.0,
		"dead_s_left": 0.0, "respawn_with_clone": false,
	}
	relish_returned = {}
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
	var pw_dt := _req_f("economy.sim.prewarm_dt")
	for i in int(_req_f("economy.sim.prewarm_ticks")):
		_inject_sources(pw_dt)
		field.tick(pw_dt)
	field.flush()


func cmd_set_time_scale(x: float) -> Dictionary:
	if not debug_enabled:
		return {"ok": false, "reason": "not_debug", "time_scale": time_scale}
	if _catchup.active:
		return _refuse_catching_up({"time_scale": time_scale})
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
	if _catchup.active:
		return _refuse_catching_up({"paused": paused})
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
	if _catchup.active:
		return _refuse_catching_up({"eta_s": 0.0})
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
	if _catchup.active:
		return _refuse_catching_up({"eta_s": 0.0})
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


## IDLE I5 (E2b-2 T3.3c, the run's manager: live play and catch-up alike, one simulation): the fort she stands
## at (at_fort) is retaken at `from_t` inside this step, so she starts home to Covington at her travel speed
## from that moment: by the step's end (t) she has walked t − from_t of it, and arrives if that is enough
## (that step's town and realm already ran with her at the fort, as a live substep's do). A longer walk ends
## in a later step, which the catch-up clips at her arrival (Catchup.next_event_s). Records the walk
## (relish_returned). Not while she is in its dungeon: the run goes on, and when it ends she stands there.
func _walk_home(fort_id: String, from_t: float) -> void:
	_begin_travel("covington")
	_step_relish_travel(maxf(0.0, t - from_t))
	relish_returned = {"fort_id": fort_id, "cause": "retaken", "t": from_t}


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
	if _catchup.active:
		return _refuse_catching_up({"target": {}})
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
	if _catchup.active:
		return _refuse_catching_up({"haul_target": ""})
	if target != "auto" and realm.fort_by_id(target).is_empty():
		return {"ok": false, "reason": "unknown_fort", "haul_target": ""}
	haul_target = target
	rev += 1
	return {"ok": true, "reason": "", "haul_target": haul_target}


# ------------------------------------------------------------------- runs ----
## The sustained-differential readout (MECHANICS §3.5) from `_diff` and the saved EMA: sign is ±1
## past ±readout.sign_eps, else 0; drain_s is backlog / −EMA while the EMA < 0, else −1.0 (and −1.0
## if that would not be finite); odds is the win odds at the game's age (win_odds), strain her backlog / (backlog + K).
func _vei_readout() -> Dictionary:
	var ema := float(_readout["diff_ema"])
	var eps := _req_f("realm.readout.sign_eps")
	var backlog: float = realm.vei["undead_queue"]
	var drain := -1.0
	if ema < 0.0:
		var d := backlog / -ema
		drain = d if is_finite(d) else -1.0
	var strain := realm.strain()
	return {
		"diff": _diff, "diff_ema": ema,
		"odds": win_odds(t, strain), "strain": strain,
		"sign": 1 if ema > eps else (-1 if ema < -eps else 0),
		"drain_s": drain,
	}


## The win odds (MECHANICS §3.5; E4 step 9, the manager's 2026-11-17 13:44 ruling, option B) at the game's age `age_s`
## (sim seconds since the new game, `t`) and Vei's strain `strain` (RealmSim.strain): realm.json odds.time_weight ·
## age / (age + odds.time_s) + (1 − time_weight) · min(odds.backlog_cap, strain). The odds a player reads, the boss
## seed's and the bots' Vei-ready are these; her tithe period, reship and one-wave need read the strain alone, so
## nothing in the fight reads them. Read live (a test may change the config after setup). time_weight 0 with
## backlog_cap 1 is the strain bit for bit (the revert proof).
func win_odds(age_s: float, strain: float) -> float:
	return win_odds_of(age_s, strain, _req_f("realm.odds.time_weight"), _req_f("realm.odds.time_s"),
		_req_f("realm.odds.backlog_cap"))


## win_odds on explicit tunables (pure; the map's valve payoff projects with it from realm.json): w · age / (age + T) +
## (1 − w) · min(cap, strain), w clamped to 0..1; the age term is 0 at age 0 or with T ≤ 0 and no age.
static func win_odds_of(age_s: float, strain: float, w: float, time_s: float, cap: float) -> float:
	var ww := clampf(w, 0.0, 1.0)
	var a := maxf(0.0, age_s)
	var tau := a / (a + time_s) if a + time_s > 0.0 else 0.0
	return ww * tau + (1.0 - ww) * minf(cap, strain)


## §3 step 8: `diff = inflow − digestion` (mass/s: what entered Vei's undead queue last substep, less
## the undead she took from it), and its EMA over readout.ema_s. Lumps (dungeon chaff, grants) are
## not in the inflow.
func _update_readout(dt: float, inflow: float, digestion: float) -> void:
	_diff = inflow - digestion
	var ema_s := _ema_s
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


## How far a held fort's raid may fall short of its seed's living and still clear the counter-garrison
## (api-request #10): half of one living unit's mass as the dungeon spawns them (raid_populate.gd:
## RaidLogic.enemy_count's clamp(round(living / cap · enemies_per_cap), enemy_min, enemy_max)
## enemies of living / n each, raid.json mass), so a full clear reported to rounding counts. Living at
## or under hold.clear_min_living (the dungeon's spawn floor, mirrored: it spawns no enemy then and
## clears after held.empty_clear_s) is all tolerated: its clear reports 0.
func _clear_tolerance(sd: Dictionary) -> float:
	var living := maxf(0.0, float(sd.get("living", 0.0)))
	if living <= _clear_min_living:
		return living
	var m: Dictionary = _sec("raid", "mass")
	var cap := maxf(1.0, float(sd.get("fort", {}).get("cap", 100.0)))
	var n := clampi(int(round(living / cap * float(m.get("enemies_per_cap", 26.0)))), int(m.get("enemy_min", 5)), int(m.get("enemy_max", 34)))
	return 0.5 * living / float(maxi(1, n))


## A fort's loot yield now (MECHANICS §5.3, IDLE §3): `yield_c` (just after its last clear that paid
## loot) relaxing linearly back to 1 over loot.recover_s from `yield_t`: 1 − (1 − c) · max(0, 1 −
## (t − yield_t) / recover_s). Exactly 1 from recover_s on, from any depth; a function of the sim time,
## so a catch-up refills it with no step work.
func _yield_mult(f: Dictionary) -> float:
	var c := clampf(float(f.get("yield_c", 1.0)), 0.0, 1.0)
	if c >= 1.0:
		return 1.0
	var rec := _recover_s
	var left := 1.0 - (t - float(f.get("yield_t", 0.0))) / rec if rec > 0.0 else 0.0
	return 1.0 - (1.0 - c) * clampf(left, 0.0, 1.0)


## A clear that paid loot (a flip, a counter-garrison clear): the yield drops to yield_mult(now) ×
## loot.reclear_decay, from now.
func _spend_yield(f: Dictionary) -> void:
	f["yield_c"] = _yield_mult(f) * _reclear_decay
	f["yield_t"] = t


## raid.json mass.garrison_mass_div, which the seed carries so Results.from_v1 needs no config.
func _garrison_div() -> float:
	return float(_sec("raid", "mass").get("garrison_mass_div", 10.0))


func _starter_units(fort_id: String) -> int:
	return int(_req_f("economy.opening.starter_party")) if _is_first_dungeon(fort_id) else 0


## raid.json wardens.by_fort is dungeon-owned; the E1 stub is bellringer.
func _warden_archetype(fort_id: String) -> String:
	var by_fort: Variant = _sec("raid", "wardens").get("by_fort", {})
	return str((by_fort as Dictionary).get(fort_id, "bellringer")) if by_fort is Dictionary else "bellringer"


## raid.json wardens.archetypes.<id>.name and .tells, dungeon-owned: "" and [] for an archetype the
## config doesn't list (a missing key is the dungeon's to fix, never a crash here).
func _warden_name(archetype: String) -> String:
	var a: Variant = _warden_spec(archetype)
	return str((a as Dictionary).get("name", "")) if a is Dictionary else ""


## The archetype's spec, or {} when `archetypes` or the entry isn't a Dictionary.
func _warden_spec(archetype: String) -> Dictionary:
	var all: Variant = _sec("raid", "wardens").get("archetypes", {})
	var a: Variant = (all as Dictionary).get(archetype, {}) if all is Dictionary else {}
	return a if a is Dictionary else {}


func _warden_tells(archetype: String) -> Array:
	var out: Array = []
	var tells: Variant = _warden_spec(archetype).get("tells", [])
	if tells is Array:
		for t in tells:
			out.append(str(t))
	return out


## loot.json hints (dungeon-owned): the first dungeon reads `first_dungeon_hint`, any other fort
## `hints["t<tier>.<archetype>"]`, "" when the key is missing.
func _loot_hint(fort_id: String) -> String:
	var hints: Dictionary = _sec("loot", "hints")  # _sec already reads a non-Dictionary as {}
	if _is_first_dungeon(fort_id):
		return str(hints.get("first_dungeon_hint", ""))
	var f := realm.fort_by_id(fort_id)
	if f.is_empty():
		return ""
	return str(hints.get("t%d.%s" % [int(f["tier"]), _warden_archetype(fort_id)], ""))


## backups.json phylactery.max_per_dungeon: the in-place revives a dungeon may use (MECHANICS §7; REQUIRED from E3-2).
func _phylactery_max() -> int:
	return int(_req_f("backups.phylactery.max_per_dungeon"))


func _relish_hp() -> float:
	return float(_cfgs.get("raid", {}).get("relish", {}).get("hp", 30.0))


## Vei's fronts, per FRONT_IDS (MECHANICS §6; live from E3-5, v8): `need`, `have` and `cleared` are
## VeiFronts.have_need's on `info`, with the vei config `_cfgs["vei"]` (at runtime the very Dictionary ConfigDb.data["vei"]
## holds: Game._ready hands ConfigDb.data to setup(), which keeps it, no copy; VeiFronts' defaults cover a missing key).
## `assigned` echoes cmd_assign_front, as it always did: the uids whose front is that id. With `view` (view_vei's rows)
## the row also carries `cleared` and `counted`: the uids VeiFronts counted there (have_need's own `assigned`), so the
## assigned ones plus each unassigned party member on the front of its highest stat; `have` sums the stat of the uids in
## `counted`. Without it the row is the boss seed's, {id, need, have, assigned} (§7.2).
func _fronts(info: Dictionary, view: bool) -> Array:
	var out: Array = []
	for f in VeiFronts.have_need(info, _cfgs.get("vei", {})):
		var id := str(f["id"])
		var e := {"id": id, "need": float(f["need"]), "have": float(f["have"]), "assigned": _front_assigned(id)}
		if view:
			e["cleared"] = bool(f["cleared"])
			e["counted"] = (f["assigned"] as Array).duplicate()
		out.append(e)
	return out


## have_need's info from the state now (view_vei's fronts): Vei's backlog (her undead queue), her living pool,
## digest_q(), and every big undead as view_big_undead gives it (StateViews.bu_entry: its uid, stats, place and front).
func _front_info() -> Dictionary:
	var units: Array = []
	for b in big_undead:
		units.append(StateViews.bu_entry(self, b))
	return {"backlog": float(realm.vei["undead_queue"]), "living_pool": float(realm.vei["living_pool"]),
		"digest_q": digest_q(), "big_undead": units}


func _front_assigned(front_id: String) -> Array:
	var out: Array = []
	for b in big_undead:
		if b["front"] == front_id:
			out.append(b["uid"])
	return out


func _fronts_required() -> int:
	return int(_cfgs.get("vei", {}).get("fronts_required", 3))


func cmd_begin_dungeon(fort_id: String) -> Dictionary:
	if _catchup.active:
		return _refuse_catching_up({"seed": {}, "run_id": -1, "seed_rev": -1})
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
	if _catchup.active:
		return _refuse_catching_up({"seed": {}, "run_id": -1, "seed_rev": -1})
	return StateRuns.begin_boss(self)


## §4.5. no_run comes before catching_up (E2b-2 T3.3c): a dead run's refusal wins (StateRuns.abort_dungeon).
func cmd_abort_dungeon() -> Dictionary:
	return StateRuns.abort_dungeon(self)


## §4.5 (v6, E2b-2 T3.3c, api-request #4; IDLE I5): the open raid's loot banked so far (the raid result's
## `loot`, §8.1) and the exit it would end in now ("retreated", "warden_beaten" or "relish_died"), replacing
## its last checkpoint. A close, a crash, a load or a gap above idle.gap_s ends the run from it
## (StateRuns.end_open). Reasons: no_run, wrong_run, wrong_kind (a boss run banks nothing), catching_up,
## invalid, bad_outcome: a dead run's refusals come first.
func cmd_run_checkpoint(run_id: int, loot: Dictionary, outcome := "retreated") -> Dictionary:
	return StateRuns.checkpoint(self, run_id, loot, outcome)


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
	if debug_enabled and _catchup.active:
		return _refuse_catching_up({"key": "", "applied": {}})
	return DebugCmds.grant(self, amounts)


func cmd_debug_set_state(patch: Dictionary) -> Dictionary:
	if debug_enabled and _catchup.active:
		return _refuse_catching_up({"key": ""})
	return DebugCmds.set_state(self, patch)


func cmd_debug_skip_time(seconds: float) -> Dictionary:
	if debug_enabled and _catchup.active:
		return _refuse_catching_up({"substeps": 0})
	return DebugCmds.skip_time(self, seconds)


# ------------------------------------------------------------- §4.3 town ----
# The town is TownSim's (BALANCE §0 at a new game). The job ladder and staff caps drive its
# staffing. The build family (T2.4) pays from TownSim's stocks and the relics, and constructs
# through TownSim's build job. Crafting and planting simulacra are live from E3-4 (cmd_craft, at a building with
# `craft_slots`: the Ossuary Tower; cmd_deploy_simulacrum); the raise is live from E3-3 (the slab,
# cmd_raise_big_undead). The stances act from E3-1 (the stance step, below cmd_set_stance).

## Buildings of that id that have finished their first build (level ≥ 1); every building when "".
func _count_built(building_id: String) -> int:
	return BuildRules.count_built(self, building_id)


## §4.3 · E2: pays the cost at once and starts construction on a free, unlocked lot. TownSim's
## `build` job advances it; `building_started` comes out of the next substep, `building_done` when
## the work is in. A `unique` building (the Crypt) is refused while one stands (api_version 3).
func cmd_build(building_id: String, lot_id: String) -> Dictionary:
	if _catchup.active:
		return _refuse_catching_up({"cost": {}})
	return BuildRules.build(self, building_id, lot_id)


## §4.3 · E2: pays level_costs and constructs the next level. The building works at its old level
## meanwhile (TownSim). Reasons in order: unknown_lot, empty_lot, under_construction, unpaid,
## max_level, needs_tier, no_gold, no_bone, no_relics.
func cmd_upgrade(lot_id: String) -> Dictionary:
	if _catchup.active:
		return _refuse_catching_up({"level": 0, "cost": {}})
	return BuildRules.upgrade(self, lot_id)


## §4.3 · E2: removes a finished building, no refund. The Crypt is protected.
func cmd_demolish(lot_id: String) -> Dictionary:
	if _catchup.active:
		return _refuse_catching_up()
	var r := BuildRules.demolish(self, lot_id)
	_sync_foremen()  # (a foreman there went back to the crypt: BuildRules.foreman_home)
	return r


## §4.3 · E2: cancels the construction under way and refunds its cost in full (relics clamped to the
## cap). A cancelled first build frees the lot; a cancelled upgrade keeps the old level.
func cmd_cancel_build(lot_id: String) -> Dictionary:
	if _catchup.active:
		return _refuse_catching_up({"refund": {}})
	var r := BuildRules.cancel_build(self, lot_id)
	_sync_foremen()  # (a cancelled first build sends its foreman to the crypt)
	return r


## §4.3 (E2b-2 T3.2, api-request #3): queues a build, or with building_id "" an upgrade of the building on
## or queued for `lot_id`. Refuses only what waiting can't make valid; gates time or play can clear are
## accepted and show as skipped_gate; affordability holds the queue (BuildRules.queue_build). R2: the new entry's
## affordable_in_s rides along (−1.0 on a refusal).
func cmd_queue_build(building_id: String, lot_id: String) -> Dictionary:
	if _catchup.active:
		return _refuse_catching_up({"index": -1, "cap_building": "", "store": "", "cap_level": -1, "affordable_in_s": -1.0})
	return BuildRules.queue_build(self, building_id, lot_id)


## §4.3: removes queue entry `index` (unknown_index).
func cmd_unqueue(index: int) -> Dictionary:
	if _catchup.active:
		return _refuse_catching_up()
	return BuildRules.unqueue(self, index)


## §4.3: `order[k]` is the old index that moves to position k, a permutation of the current indices
## (bad_order).
func cmd_reorder_queue(order: Array) -> Dictionary:
	if _catchup.active:
		return _refuse_catching_up()
	return BuildRules.reorder_queue(self, order)


## The ladder, a permutation of JOB_IDS, top first: TownSim's workers fill job slots in this order.
func cmd_set_job_priority(order: Array) -> Dictionary:
	if _catchup.active:
		return _refuse_catching_up({"order": []})
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
	if _catchup.active:
		return _refuse_catching_up({"cap": 0})
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
	var n := int(_req_f("economy.stance.base_slots")) + int(town_sim.built_effect("stance_slots"))
	if relish["state"] == "home":
		n += int(_req_f("realm.relish.home_stance_bonus"))  # her one live home effect (§3.3)
	return n


## E1/E3: stores the toggle. When the slots run short, the most recently enabled stances
## are suspended (view_stances), not switched off. E3-1: the stances acting take effect at once
## (_apply_stances: an on stance whose condition holds acts now; `active` itself moves only at a beat).
func cmd_set_stance(stance_id: String, on: bool) -> Dictionary:
	if _catchup.active:
		return _refuse_catching_up({"slots": 0, "used": 0})
	if not STANCE_IDS.has(stance_id):
		return {"ok": false, "reason": "unknown_stance", "slots": 0, "used": 0}
	var slots := _stance_slots()
	if on and not stances_on.has(stance_id):
		if stances_on.size() >= slots:
			return {"ok": false, "reason": "no_slot", "slots": 0, "used": 0}
		stances_on.append(stance_id)
	elif not on:
		stances_on.erase(stance_id)
	_apply_stances(t)
	rev += 1
	return {"ok": true, "reason": "", "slots": slots, "used": mini(stances_on.size(), slots)}


# ------------------------------------------------------------------ the stances (E3-1) ----
## MECHANICS §4.5, STATE-API §3 step 1 and §5.11. Each stance has a binary condition, computed for every stance,
## on or off: `active` (_stance_active) is that condition as the stance step last let it change. It changes only at
## a beat (the core step's first step, when floor(t / beat_s) has moved), and not again until economy.json
## stance.hold_s has passed since its last change (_stance_hold: the seconds left); each change emits stance_fired
## and sets fired_beat_id (_stance_fired). A stance acts while it is on, not suspended and active
## (_stance_acting), and only then does its effect apply (_apply_stances).

## The beat index at `at` (STATE-API §3 step 1): floor(at / beat_s), beat_s = pulse.json tempo_ms / 1000; 0 with
## no tempo.
func beat_at(at: float) -> int:
	return int(floor(at / _beat_s)) if _beat_s > 0.0 else 0


## The stance step, §3 step 1 of a core step of `dt` (t already advanced): the holds run down by dt; at a new beat
## every stance's condition is read from the state the step starts from, and each whose hold is over and whose
## condition differs from `active` changes (stance_fired, its fired_beat_id the beat, a fresh hold); then the
## stances acting are applied, effective from the step's start (t − dt).
func _stance_step(dt: float) -> void:
	for id in _stance_hold.keys():
		var left := float(_stance_hold[id]) - dt
		if left <= 1e-9:
			_stance_hold.erase(id)
		else:
			_stance_hold[id] = left
	var beat := beat_at(t)
	if beat != _stance_beat:
		_stance_beat = beat
		for id in STANCE_IDS:
			if _stance_hold.has(id):
				continue
			var now := _stance_condition(id)
			if now == _stance_active.has(id):
				continue
			if now:
				_stance_active[id] = true
			else:
				_stance_active.erase(id)
			_stance_fired[id] = beat
			_stance_hold[id] = _stance_hold_s
			_emit({"type": "stance_fired", "stance_id": id, "active": now, "beat_id": beat})
	if not stances_on.is_empty() or not _stance_acting.is_empty():
		_apply_stances(t - dt)


## A stance's condition now (MECHANICS §4.5; its thresholds economy.json `stance`), from the state as it stands:
## - vigil: Relish is away from home or dead (any state but home);
## - harvest: the bodies are under stance.harvest_bodies_frac of the body cap;
## - hearth: morale is under stance.hearth_morale;
## - muster: there are idle workers, or the last step mustered some to WAR (so its own effect, which leaves none
##   idle, doesn't switch it off while the town makes more hands than it has work for);
## - thrift: the stalls' gold income now is under the gold upkeep the town owes, the buildings Thrift idles
##   counted as paying (TownSim.trade_income, gold_bill), so its own effect doesn't switch it off.
func _stance_condition(id: String) -> bool:
	var ts := town_sim
	match id:
		"vigil":
			return relish["state"] != "home"
		"harvest":
			return ts.bodies < _harvest_frac * ts.body_cap()
		"hearth":
			return ts.morale < _hearth_morale
		"muster":
			return float(ts.staffing.get("idle", 0.0)) > 0.0 or float(ts.rates["workers"]["muster"]) > 0.0
		"thrift":
			return ts.trade_income() < ts.gold_bill()
	return false


## The stances that would act with `on_list` the toggles (oldest first): {id: true} for each on, not suspended (within
## the slots, the oldest first) and active.
func _acting_of(on_list: Array) -> Dictionary:
	var out := {}
	if on_list.is_empty():
		return out
	var slots := _stance_slots()
	for i in mini(on_list.size(), slots):
		if _stance_active.has(on_list[i]):
			out[on_list[i]] = true
	return out


## The jobs `acting` lifts to the top of the ladder, in economy.json stance.priority order (stance.top_job).
func _top_jobs_of(acting: Dictionary) -> Array:
	var top: Array = []
	for id in _stance_priority:
		if acting.has(id):
			var j: String = _stance_top_job[id]
			if not top.has(j):
				top.append(j)
	return top


## Gives TownSim the effects of the stances acting now (MECHANICS §4.5): the ladder stances' jobs lifted
## (TownSim.set_top_jobs, which marks the room cache), Muster's idle cap of 0, and Thrift: when it starts acting it
## idles TownSim.thrift_pick's buildings; when it stops, every building it idled resumes. `at`: the moment they take
## effect (a core step's start, or a command's t), for the away report's Thrift spells. `on_load`: a load restores
## Thrift's buildings as saved and refills the staffing without marking the states. Called by every core step's
## stance step (so a slot that goes or comes with Relish, or with the Guildhall, suspends or resumes a stance's effect
## from the next step), by cmd_set_stance (at once) and after a load.
func _apply_stances(at: float, on_load := false) -> void:
	var acting := _acting_of(stances_on)
	town_sim.set_top_jobs(_top_jobs_of(acting), on_load)
	town_sim.muster_all = acting.has("muster")
	if not on_load:
		if acting.has("thrift"):
			if not _stance_acting.has("thrift"):
				_note_thrift(at, town_sim.thrift_idle(town_sim.thrift_pick()), true)
		else:
			_note_thrift(at, town_sim.thrift_resume(), false)
	_stance_acting = acting


## Thrift's spells for the away report (IDLE §7): while a reporting catch-up runs, each building Thrift idles or
## resumes is noted with its moment ([t, lot_id, idled]) on the catch-up runner.
func _note_thrift(at: float, lots: Array, idled: bool) -> void:
	if lots.is_empty() or not (_catchup.active and _catchup.report):
		return
	for lot_id in lots:
		_catchup.thrift_log.append([at, str(lot_id), idled])


## economy.json `stance`'s ladder stances, checked at setup (E3-1): `priority` lists exactly `top_job`'s stances, each
## a STANCE_IDS id, and each lifts a JOB_IDS job. "" when it holds.
static func stance_config_problem(cfgs: Dictionary) -> String:
	var st: Variant = cfgs.get("economy", {}).get("stance", {})
	if not (st is Dictionary and (st as Dictionary).get("top_job") is Dictionary and (st as Dictionary).get("priority") is Array):
		return "config economy.stance needs top_job (a table) and priority (a list)"
	var top: Dictionary = st["top_job"]
	var pri: Array = st["priority"]
	for id in top:
		if not STANCE_IDS.has(id) or not JOB_IDS.has(str(top[id])):
			return "config economy.stance.top_job.%s (%s) is not a stance lifting a job" % [str(id), str(top[id])]
		if not pri.has(id):
			return "config economy.stance.priority has no %s (top_job names it)" % str(id)
	for id in pri:
		if not top.has(id) or pri.count(id) != 1:
			return "config economy.stance.priority's %s is not one of top_job's stances, once" % str(id)
	return ""


func _find_uid(items: Array, uid: Variant) -> Dictionary:
	if typeof(uid) != TYPE_STRING:
		return {}
	for it in items:
		if it["uid"] == uid:
			return it
	return {}


## §4.3 · live from E3-3 (v8; MECHANICS §4.6): the crypt slab's raise. The refusals, in check order: catching_up,
## not_home (Relish isn't home), unknown_husk, unknown_remnant, duplicate_remnant, then the slab's
## SlabLogic.evaluate(the husk's kind, the remnants' records in the order given, town.json slab) and invalid_recipe
## when it says not ok, at_cap (big_undead.size() >= _cap_of("big_undead")), bad_name (empty or over 24 characters
## after strip_edges). On success it consumes the husk and those remnants, mints u<n> from the save's uid counter
## and stores {uid, name (stripped), kind (the husk's), role (SlabLogic's role id), stats (SlabLogic's), place
## "crypt", front "", filled_slots (SlabLogic's `filled`)}; rev +1, and the extra is that entry as view_big_undead
## shows it. No event: STATE-API §6 lists none for a raise.
func cmd_raise_big_undead(husk_uid: String, remnant_uids: Array, name: String) -> Dictionary:
	if _catchup.active:
		return _refuse_catching_up({"big_undead": {}})
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
	var husk := _find_uid(husks, husk_uid)
	var rems: Array = []
	for r in remnant_uids:
		rems.append(_find_uid(remnants, r))
	var slab := SlabLogic.evaluate(str(husk["kind"]), rems, _sec("town", "slab"))
	var nm := name.strip_edges()
	if not bool(slab["ok"]):
		why = "invalid_recipe"
	elif big_undead.size() >= _cap_of("big_undead"):
		why = "at_cap"
	elif nm.is_empty() or nm.length() > 24:
		why = "bad_name"
	if why != "":
		return {"ok": false, "reason": why, "big_undead": {}}
	_take_uid(husks, husk_uid)
	for r in remnant_uids:
		_take_uid(remnants, r)
	var st := {}
	for k in STATS:
		st[k] = float(slab["stats"].get(k, 0.0))
	var b := {"uid": _mint_uid("u"), "name": nm, "kind": str(husk["kind"]), "role": str(slab["role"]), "stats": st,
		"place": "crypt", "front": "", "filled_slots": int(slab["filled"])}
	big_undead.append(b)
	rev += 1
	return {"ok": true, "reason": "", "big_undead": StateViews.bu_entry(self, b)}


## Removes the item with that uid from `items` (the husks or the remnants).
func _take_uid(items: Array, uid: Variant) -> void:
	for i in items.size():
		if items[i]["uid"] == uid:
			items.remove_at(i)
			return


## A big undead's filled remnant slots (E3-3, api-request #6): SlabLogic's `filled` at its raise. A record without
## the key reads 1 (the run's manager's ruling): every fixture's, every save's from before v8, and a debug mint's
## (DebugCmds.mint_big_undead raises nothing on the slab). One slot is what the dungeon and the Vei fight drew before
## (vei_boss reads maxi(1, filled_slots ?? 1)), so those big undead fight as they did.
static func filled_slots_of(b: Dictionary) -> int:
	return int(b.get("filled_slots", 1))


func cmd_rename_big_undead(uid: String, name: String) -> Dictionary:
	if _catchup.active:
		return _refuse_catching_up({"name": ""})
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


## TownSim's foremen from the big undead placed `town:<lot_id>` (E3-3; TownSim.set_foremen): {lot_id: {speed,
## presence}}, their stats. Called wherever a place can change (cmd_place_big_undead, cmd_set_party, cmd_demolish,
## cmd_cancel_build), on a new game and a load, and at every core step's start, so TownSim's step and every
## projection read the placements as they stand. A catch-up changes none: commands are refused while it runs, and its
## own events move only a siege (a retake) and the party (a death).
func _sync_foremen() -> void:
	var map := {}
	for b in big_undead:
		var place := str(b["place"])
		if place.begins_with("town:"):
			var st: Dictionary = b["stats"]
			map[place.trim_prefix("town:")] = {"speed": float(st.get("speed", 0.0)), "presence": float(st.get("presence", 0.0))}
	town_sim.set_foremen(map)


## RealmSim's `siege_block` input (E3-3, the run's manager's rulings; MECHANICS §3.4): {fort_id: tithe.siege_block}
## for each fort with at least one big undead placed `fort:<id>`. One siege per fort counts (a second is allowed and
## adds nothing) and the block is flat, whatever the big's stats; a siege adds no kill power. Read from the places as
## they stand: the core step's inputs and _restore_dispatch's call it, so a placement reaches the next step at once.
## The margin and forecast credit the same (_forecast_siege, from E4). A retake sends the siege home (_emit_realm), so the next step has
## no block there; RealmSim drops it for the rest of the step the retake falls in (RealmSim.step).
func _siege_blocks() -> Dictionary:
	var out := {}
	for b in big_undead:
		var place := str(b["place"])
		if place.begins_with("fort:"):
			var id := place.trim_prefix("fort:")
			if not realm.fort_by_id(id).is_empty():
				out[id] = _req_f("realm.tithe.siege_block")
	return out


## The siege block the margin and forecast credit (MECHANICS §3.4): the step's own (_siege_blocks), from E4. E3-3 credited
## none (the run's manager's ruling: a new feature must never make the chip say "safe" at a fort that falls): the wave
## train then read the WAR at the sampling instant, a landed load's burst held over the whole forecast, and with a block
## crediting a fort near its band's edge that error turned "safe" where the sim broke it (midgame_2flips at a WAR share
## of 0.05, Ashgate retaken at 988 s). The train reads the settled WAR since E4 (_train_war_at), and credited, that case
## reads thin (test_big_undead's _siege_chip_war05; margin_truth).
func _forecast_siege() -> Dictionary:
	return _siege_blocks()


## Takes a big undead out of the party. Its front goes too: fronts are for party members.
func _leave_party(b: Dictionary) -> void:
	party_uids.erase(b["uid"])
	b["front"] = ""


## E1/E2: records the place (and takes it out of the party). From E3-3 a foreman works its building (TownSim's
## foremen, _sync_foremen; MECHANICS §4.2) and a siege blocks tithe.siege_block of a tithe wave at its fort
## (_siege_blocks; MECHANICS §3.4); a place where it gives nothing (a second siege, a passive building) is still
## allowed.
func cmd_place_big_undead(uid: String, place: String) -> Dictionary:
	if _catchup.active:
		return _refuse_catching_up({"place": ""})
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
	_sync_foremen()
	rev += 1
	return {"ok": true, "reason": "", "place": place}


## §4.3 · E3 (live from E3-4; MECHANICS §3.6, §7): crafts one item at once. Reasons, after catching_up, in
## _craft_reason's order: unknown_item, needs_building, no_essence, no_relics. It takes economy.json
## craft.<item_id>'s essence and relics and adds 1 to the simulacra ready (stats.sims_built counts it) or to the
## phylactery charges; `count` is that stock now. Neither stock has a cap of its own: the essence and relic caps
## bound them, and phylactery.max_per_dungeon limits the revives a run may use, not the stock. No event; it mints
## no uid (both stocks are counts).
func cmd_craft(item_id: String) -> Dictionary:
	if _catchup.active:
		return _refuse_catching_up({"count": 0})
	var why := _craft_reason(item_id)
	if why != "":
		return {"ok": false, "reason": why, "count": 0}
	var cost := _craft_cost(item_id)
	essence -= int(cost["essence"])
	relics -= int(cost["relics"])
	var count := 0
	if item_id == "simulacrum":
		simulacra_ready += 1
		stats["sims_built"] = int(stats["sims_built"]) + 1
		count = simulacra_ready
	else:
		_phylactery_charges += 1
		count = _phylactery_charges
	rev += 1
	return {"ok": true, "reason": "", "count": count}


## Why cmd_craft(item_id) would refuse now, "" when it would craft (E3-4; view_catalog's crafts read it too, so the
## two agree). In order: unknown_item; needs_building, while the built buildings' `craft_slots` sum to under 1
## (TownSim.built_effect: a capacity effect, so an unpaid or Thrift-idled Ossuary still crafts, and one still on its
## first build doesn't; the building is found by its effect, not its id; a level above 1 adds nothing more in E3);
## no_essence; no_relics.
func _craft_reason(item_id: String) -> String:
	if not CRAFT_IDS.has(item_id):
		return "unknown_item"
	if town_sim.built_effect("craft_slots") < 1.0:
		return "needs_building"
	var cost := _craft_cost(item_id)
	if essence < int(cost["essence"]):
		return "no_essence"
	if relics < int(cost["relics"]):
		return "no_relics"
	return ""


## A craft's cost, {essence: int, relics: int}: economy.json craft.<item_id> (REQUIRED). `item_id` is one of CRAFT_IDS.
func _craft_cost(item_id: String) -> Dictionary:
	return {"essence": int(_req_f("economy.craft.%s.essence" % item_id)), "relics": int(_req_f("economy.craft.%s.relics" % item_id))}


## §4.3 · E4 (the sizing stop's ruling 2, lever (b); v9): grinds remnants and bone into a t1 husk, at once. Reasons,
## after catching_up, in _husk_craft_reason's order: unknown_kind (not one of the t1 chest's husk_kinds, loot.json
## chest_by_tier 1), no_remnants (fewer than economy.json craft.husk.remnants), no_bone (under craft.husk.bone), at_cap
## (v10, the E4 review: the crypt has no room for it, its big undead and the husks waiting at the big_undead cap). It
## takes the weakest remnants (husk_craft_pick: the smallest magnitude first, then the oldest uid) and the bone, and
## adds {uid: h<n> from the save's uid counter, kind, rarity "common"} to the husks, as a raid's loot does. The extra is
## that husk. No event; no building, and Relish needn't be home (raising it at the slab needs her). Its costs are GUESS.
func cmd_craft_husk(kind: String) -> Dictionary:
	if _catchup.active:
		return _refuse_catching_up({"husk": {}})
	var why := _husk_craft_reason(kind)
	if why != "":
		return {"ok": false, "reason": why, "husk": {}}
	for r in husk_craft_pick(remnants, int(_req_f("economy.craft.husk.remnants"))):
		_take_uid(remnants, r["uid"])
	town_sim.bone -= _req_f("economy.craft.husk.bone")
	var h := {"uid": _mint_uid("h"), "kind": kind, "rarity": "common"}
	husks.append(h)
	rev += 1
	return {"ok": true, "reason": "", "husk": h.duplicate()}


## The kinds cmd_craft_husk makes: the t1 chest's husk_kinds (loot.json chest_by_tier 1), [] when it has none.
func husk_craft_kinds() -> Array:
	var t1: Variant = _sec("loot", "chest_by_tier").get("1", {})
	return ((t1 as Dictionary).get("husk_kinds", []) as Array).duplicate() if t1 is Dictionary else []


## Why cmd_craft_husk(kind) would refuse now, "" when it would craft. `kind` "" skips the kind check (view_catalog's
## husk_craft reads the kind-free reason).
func _husk_craft_reason(kind: String) -> String:
	if kind != "" and not husk_craft_kinds().has(kind):
		return "unknown_kind"
	if remnants.size() < int(_req_f("economy.craft.husk.remnants")):
		return "no_remnants"
	if town_sim.bone < _req_f("economy.craft.husk.bone"):
		return "no_bone"
	if big_undead.size() + husks.size() >= _cap_of("big_undead"):
		return "at_cap"
	return ""


## The remnants cmd_craft_husk takes from `rems`: the `n` weakest, the smallest magnitude first, then the oldest uid
## (r<n>'s n). Static, so the autoplayer can read what a craft would leave.
static func husk_craft_pick(rems: Array, n: int) -> Array:
	var c := rems.duplicate()
	c.sort_custom(func(a, b): return int(a["magnitude"]) < int(b["magnitude"]) or (int(a["magnitude"]) == int(b["magnitude"])
		and int(str(a["uid"]).substr(1)) < int(str(b["uid"]).substr(1))))
	return c.slice(0, maxi(0, n))


## §4.3 · E3 (live from E3-4; MECHANICS §3.6): plants a simulacrum at any fort, held or not; several at one fort
## stack (view_fort.simulacrum_charges sums them). Reasons, after catching_up: unknown_fort, then none_ready (no
## simulacrum ready). It takes one from simulacra_ready and appends {fort_id, charges: realm.json simulacrum.charges,
## rate: simulacrum.rate} to RealmSim's simulacra: from the next step it performs Relish's redirect there (RealmSim
## step 5) until its charges run out and it crumbles (step 6), or the fort is retaken, which loses it
## (RealmSim._retaken; IDLE I6). Extras: its charges and ready_left (the simulacra still ready). No event (the lanes'
## "simulacrum" callout comes from the next substep, _note_lane_causes).
func cmd_deploy_simulacrum(fort_id: String) -> Dictionary:
	if _catchup.active:
		return _refuse_catching_up({"charges": 0.0, "ready_left": 0})
	var why := ""
	if realm.fort_by_id(fort_id).is_empty():
		why = "unknown_fort"
	elif simulacra_ready < 1:
		why = "none_ready"
	if why != "":
		return {"ok": false, "reason": why, "charges": 0.0, "ready_left": 0}
	var charges := _req_f("realm.simulacrum.charges")
	simulacra_ready -= 1
	realm.simulacra.append({"fort_id": fort_id, "charges": charges, "rate": _req_f("realm.simulacrum.rate")})
	rev += 1
	return {"ok": true, "reason": "", "charges": charges, "ready_left": simulacra_ready}


## Vat slots: the Chapel of Vats' `vat_slots` per level, over every built Chapel (MECHANICS §7).
func _vat_slots() -> int:
	return int(town_sim.built_effect("vat_slots"))


## A vat's clone, 0..1 (vats_grow; a slot it doesn't reach reads 0).
func _vat_grow(i: int) -> float:
	return float(vats_grow[i]) if i < vats_grow.size() else 0.0


## A vat as view_backups and the save show it (E3-2): its clone's `grow`, ready at 1.
func _vat_entry(i: int) -> Dictionary:
	var g := _vat_grow(i)
	return {"slot": i, "staffed": i < vats_staffed.size() and bool(vats_staffed[i]), "grow": g, "ready": g >= 1.0}


## The vats holding a ready clone (grow at 1). Every entry of vats_grow counts, so a Chapel demolished between
## two core steps keeps its ready clones until the next backups step moves them to the spare ones (_grow_vats).
func _vats_ready() -> int:
	var n := 0
	for g in vats_grow:
		if float(g) >= 1.0:
			n += 1
	return n


## The vats that take a tend hand (E4 step 10, MECHANICS §7): staffed, and their clone not yet ready. A ready clone
## needs no tending, so its vat gives the hand back to the ladder until the clone is spent; vats_staffed (saved, what
## view_backups shows) keeps the player's choice. TownSim opens a tend slot per vat listed here (set_vats).
func _tended_vats() -> Array:
	var out: Array = []
	for i in vats_staffed.size():
		out.append(bool(vats_staffed[i]) and _vat_grow(i) < 1.0)
	return out


## Gives TownSim the tended vats (_tended_vats); a no-op while they are unchanged. Called after each backups step and
## wherever a clone is spent or the staffing changes, so a vat filling or emptying moves its hand at that step's end,
## live and caught up alike.
func _sync_tend() -> void:
	town_sim.set_vats(_tended_vats())


## clones_ready's setter: the total becomes `v` (≥ 0). The spare clones make up what the vats at 1 don't hold;
## a total below the vats at 1 empties ready vats from the lowest slot (and no spare is left).
func _set_clones_ready(v: int) -> void:
	var want := maxi(0, v)
	var in_vats := _vats_ready()
	if want >= in_vats:
		_clones_spare = want - in_vats
		return
	_clones_spare = 0
	var drop := in_vats - want
	for i in vats_grow.size():
		if drop <= 0:
			break
		if float(vats_grow[i]) >= 1.0:
			vats_grow[i] = 0.0
			drop -= 1
	_sync_tend()


## Spends `n` ready clones (a death's, a boss fight's; MECHANICS §7): each empties the lowest ready vat back to 0,
## so it grows again, and only when no vat is ready does it take a spare clone (which never regrows). Stops when
## none is left. Returns the clones spent.
func spend_clones(n: int) -> int:
	var spent := 0
	for i in vats_grow.size():
		if spent >= n:
			break
		if float(vats_grow[i]) >= 1.0:
			vats_grow[i] = 0.0
			spent += 1
	var spare := mini(n - spent, _clones_spare)
	_clones_spare -= spare
	if spent > 0:
		_sync_tend()  # an emptied vat that is staffed takes its tend hand again (E4 step 10)
	return spent + spare


## The core step's backups step (STATE-API §3 step 6; E3-2, MECHANICS §7), at `dt`: each vat grows by
## vats.grow_per_s × its hands × dt, clamped at 1 (linear, so the update is exact at any step: IDLE §4), on the
## hands TownSim's step staffed it with (`hands`, TownSim.vat_hands: [] while no vat is staffed, so nothing moves).
## A vat past the Chapels' slots now (its Chapel demolished) is dropped, its ready clone kept as a spare.
func _grow_vats(dt: float, hands: Array) -> void:
	for i in hands.size():
		var h := float(hands[i])
		if h <= 0.0:
			continue
		while vats_grow.size() <= i:
			vats_grow.append(0.0)
		vats_grow[i] = minf(1.0, float(vats_grow[i]) + _grow_per_s * h * dt)
	var n := _vat_slots()
	if vats_grow.size() > n:
		for i in range(n, vats_grow.size()):
			if float(vats_grow[i]) >= 1.0:
				_clones_spare += 1
		vats_grow.resize(n)


## E1/E3 (the hand E2b-2): stores the staffing, and a staffed vat takes a hand: its tend slot opens
## and the ladder fills it like any other; unstaffing it closes the slot and gives the hand back
## (MECHANICS §7). From E3-2 its clone grows while it is tended (_grow_vats); unstaffed, it keeps its progress.
func cmd_staff_vat(slot: int, on: bool) -> Dictionary:
	if _catchup.active:
		return _refuse_catching_up({"staffed": false})
	if slot < 0 or slot >= _vat_slots():
		return {"ok": false, "reason": "unknown_slot", "staffed": false}
	while vats_staffed.size() <= slot:
		vats_staffed.append(false)
	vats_staffed[slot] = on
	_sync_tend()
	rev += 1
	return {"ok": true, "reason": "", "staffed": on}


# ------------------------------------------------- §4.4 party and fronts ----
## The listed uids join the party in this order (place "party"); former members not
## listed go back to the crypt and lose their front.
func cmd_set_party(uids: Array) -> Dictionary:
	if _catchup.active:
		return _refuse_catching_up({"party": []})
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
	_sync_foremen()  # (a foreman moved into the party leaves its building)
	rev += 1
	return {"ok": true, "reason": "", "party": party_uids.duplicate()}


## E1/E3: records a party member's front ("" unassigns). From E3-5 the front counts its stat there (_fronts).
func cmd_assign_front(uid: String, front_id: String) -> Dictionary:
	if _catchup.active:
		return _refuse_catching_up()
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
## {sources, sinks, held, stores}: mass totals since the new game, every pool of mass now (Ledger), and
## the currency tally of what the gold and bone caps clipped (not mass). Σheld + Σsinks == Σsources at
## every substep boundary (MECHANICS §2.1).
func ledger() -> Dictionary:
	return {"sources": _ledger.sources.duplicate(), "sinks": _ledger.sinks.duplicate(), "held": _held(),
		"stores": _ledger.stores_copy()}


func _held() -> Dictionary:
	return Ledger.held(realm, town_sim, work_pending, worker_mass())


## economy.json worker.mass: the mass of one worker.
func worker_mass() -> float:
	return _req_f("economy.worker.mass")


# ----------------------------------------------------------------- §5 views ----
# Every view is a fresh deep copy with `rev` first; an unknown id gives {}. view_relish
# (§5.8) sits with Relish, and the seed views (§5.15) with the runs.

static func _xy(p: Vector2) -> Array:
	return [float(p.x), float(p.y)]


func _world_size() -> Array:
	var sz: Variant = _cfgs.get("world", {}).get("size", [2048, 1440])
	return [float(sz[0]), float(sz[1])]


func _pool_cap() -> float:
	return _vei_pool_cap


## Every RATE_IDS stream as {id: [in, out]} per second, the one source of view_rates and view_hud
## (§5.2):
## - mint, work, war, flood: the last substep's valve split (session only), each a pass-through;
## - workers, bodies, gold, bone, living: TownSim's last step (saved with it). Bodies come in as rot
##   return plus the trip-averaged haul (_haul_rate), so a convoy's arrival is not a spike;
## - corpses, backlog: the realm's last substep (_realm_flows, session only); the haul leaves the
##   corpses at the same trip-averaged rate the bodies receive it.
func _rate_io() -> Dictionary:
	var haul := _haul_rate()
	var out := _town_io(town_sim)
	out["corpses"] = [float(_realm_flows["corpses"][0]), float(_realm_flows["corpses"][1]) + haul]
	out["backlog"] = [float(_realm_flows["backlog"][0]), float(_realm_flows["backlog"][1])]
	for id in ["mint", "work", "war", "flood"]:
		out[id] = [float(_split[id]), float(_split[id])]
	return out


## TownSim's streams as _rate_io gives them, for `ts` (the live TownSim, or a hypothetical's): workers,
## bodies (rot return plus the trip-averaged haul), gold, bone and living, each [in, out] per second.
static func _town_io(ts: TownSim) -> Dictionary:
	var r: Dictionary = ts.rates
	return {
		"workers": [float(r["workers"]["in"]), float(r["workers"]["out"])],
		"bodies": [float(r["bodies"]["rot"]) + _haul_rate_of(ts), float(r["bodies"]["out"])],
		"gold": [float(r["gold"]["in"]), float(r["gold"]["out"])],
		"bone": [float(r["bone"]["in"]), float(r["bone"]["out"])],
		"living": [float(r["living"]["in"]), float(r["living"]["out"])],
	}


## The convoy's trip-averaged corpse rate (mass/s): the last landed trip's load over its round trip,
## while a convoy is out; 0 while none is.
func _haul_rate() -> float:
	return _haul_rate_of(town_sim)


static func _haul_rate_of(ts: TownSim) -> float:
	if (ts.haul["convoys"] as Array).is_empty():
		return 0.0
	return float(ts.rates["haul_trip"])


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


## §5.17 · E2b-2 (api_version 6, api-requests #7 c, #13): the held forts' readouts, the split and the
## payoff at another valve, without changing anything (StateViews.projection). `settled` (T3.4b): the
## margins are the wave train's at that valve, not the drag's one-wave probe.
func view_projection(valve: Dictionary, settled := false) -> Dictionary:
	return StateViews.projection(self, valve, settled)


## The WAR the current valve sends each fort, mass/s, in world order: the last dispatch's split of
## this substep's WAR (RealmSim.war_at), so view_projection at the current valve reads the same; before
## the first substep after a load, the saved r_in.
func _fort_wars() -> Array:
	if realm._disp_w.size() == realm.forts.size():
		return realm.war_at(float(_split["war"]))[0]
	var out: Array = []
	for f in realm.forts:
		out.append(float(f["r_in"]))
	return out


## A fort's hold readouts at `w_in` mass/s of WAR to it, at Relish's position now and with its siege credited
## (_forecast_siege, from E4) (MECHANICS §3.5; RealmSim.readout_of). `train` is the fort's wave-train verdict (_train_live or
## _train_valve's `forts` entry): given, the margin is the train's; left out, the one-wave margin. `plan`
## is the fort's _train_support entry (the planned support the train reads): given, fall_s is the earlier
## of the clocks at the current and the planned support.
func _fort_readout(f: Dictionary, w_in: float, train := {}, plan := []) -> Dictionary:
	var fx := _relish_effects()
	var id: String = f["id"]
	return realm.readout_of(f, w_in, fx["redirect_fort"] == id, _raise_rate,
		fx["tide_fort"] == id, RealmSim._siege_at(_forecast_siege(), id), digest_q(), train, plan)


## A new game or a load (cmd_new_game, from_dict): the wave train's cache is emptied and the frame path is
## off until the shell's next capped tick, so nothing from the old state is served. The margin views' memo
## (_margin_view) goes with it (E4 review item 1): its key doesn't name the valve or Relish, so a state loaded onto
## the same rev and t with the same fort stocks would otherwise be served the old margins.
func _reset_train() -> void:
	_train_cache = {}
	_margin_memo = {}
	_frame_path = false


## The wave train's verdicts for the live flows (MECHANICS §3.5, E2b-2 T3.4b): RealmSim.train_probe over
## every held fort at the WAR the valve sends it once its slew is done (_train_war), cached (_train).
## view_fort and view_realm read it; nothing in the sim does.
func _train_live() -> Dictionary:
	return _train(_train_war(), true)


## The WAR the live train reads, mass/s: _train_war_at the valve's target. The valve slews to its target at
## valve.slew_per_s (at most 20 s for a full swing), and nothing but a command changes the target, so the train
## reads where it is going, as it reads Relish where she is travelling to (_train_support). It is the WAR
## view_projection's train reads at the target valve, bit for bit.
func _train_war() -> float:
	return _train_war_at(valve_target)


## The settled WAR the wave train reads at valve `v` (E4 must-fix #1; MECHANICS §3.5), mass/s: the mint at the
## pits' trough feed (TownSim.trough_feed: the rot alone, no load landing) × v.war, plus the muster TownSim settles
## at on that mint's WORK (TownSim.workforce_steady at mint × v.work / worker mass, the lifetime, slots and idle cap
## now). Before, the train read this substep's mint and muster: a landed load's feed of 1 and the WORK burst it
## musters, held across the whole forecast. After midgame_2flips' load that read 9.713 against the 7.617 the split
## settles at a minute on; over a convoy cycle the split swings 63.5 ↔ 98.7 and this reads 63.5, its minimum.
## It ignores the bodies in store, so a big stock reads low for as long as the pits burn it at full.
## The muster counts only while the Muster stance acts; otherwise it goes to FLOOD (_split_of, E4 step 5 A1).
func _train_war_at(v: Dictionary) -> float:
	var mint := _mint(town_sim.pit_weight(), town_sim.trough_feed())
	if not town_sim.muster_all:
		return mint * float(v["war"])
	var wm := worker_mass()
	var r := mint * float(v["work"]) / wm if wm > 0.0 else 0.0
	var steady := TownSim.workforce_steady(r, town_sim.lifetime_s(relish["state"] == "home"), town_sim._idle_rot,
		float(town_sim.staffing.get("slots", 0.0)), town_sim.idle_cap())
	return mint * float(v["war"]) + float(steady["muster"]) * wm


## The wave train at `war` mass/s of WAR (view_projection's valve with `settled`), cached (_train).
func _train_valve(war: float) -> Dictionary:
	return _train(war, false)


## RealmSim.train_probe on _train_support(war, live), computed lazily on the first read after the state
## moved and kept in _train_cache, one slot for the live flows and one for a projected valve; either
## slot answers a call whose key matches it (view_projection with `settled` at the current valve is the
## live train). The key is [rev, t, q, the support, RealmSim.train_state()]: rev and t as the build
## projections key theirs (a catch-up's core steps move t without rev), and the state the probe starts
## from, so an edit that bumps neither (a test, debug) still misses. Session only.
## On the frame path (_frame_path) a read of the live flows doesn't probe when only live substeps have
## moved the state since the live slot was made: rev less the substeps unchanged (no command since) and t
## moved by exactly those substeps (no core step outside _tick: a catch-up's steps move t alone). It serves
## that slot, the verdict at most a few substeps old, and _train_frame refreshes it on the next frame with
## no substep. A command (a valve, a raid's flip, a move) or a catch-up probes at the next read.
## A projected valve whose WAR is the live train's (the valve's target) reads the live slot the same way,
## so view_projection with `settled` at the valve's target always equals view_fort.
func _train(war: float, live: bool) -> Dictionary:
	if not live and war == _train_war() and realm._disp_w.size() == realm.forts.size():
		live = true
	var sup := _train_support(war, live)
	if sup.is_empty():
		return _TRAIN_NONE  # nothing held: nothing to probe, nothing to refresh
	var q := digest_q()
	var key := [rev, t, q, sup, realm.train_state()]
	var slot := "live" if live else "valve"
	for s in [slot, "valve" if live else "live"]:
		var c: Array = _train_cache.get(s, [])
		if not c.is_empty() and c[0] == key:
			if s == "live":
				_train_cache["read"] = true
			return c[1]
	if live and _frame_path:
		var c: Array = _train_cache.get("live", [])
		var subs := _ticks - int(c[3]) if not c.is_empty() else 0
		if not c.is_empty() and rev - int(c[2]) == subs and absf(t - float(c[4]) - subs * substep_s()) <= 1e-6:
			_train_cache["read"] = true
			return c[1]
	return _train_probe(slot, key, sup, q)


## Runs the probe for `key` into `slot` (_train, _train_frame); `read` marks the live slot read (a view's
## call, not the frame refresh's).
func _train_probe(slot: String, key: Array, sup: Dictionary, q: float, read := true) -> Dictionary:
	var res := realm.train_probe(sup, q)
	_train_cache[slot] = [key, res, rev, _ticks, t]
	_train_cache["computed"] = int(_train_cache.get("computed", 0)) + 1
	if slot == "live" and read:
		_train_cache["read"] = true
	return res


## The frame refresh of the live slot (_advance, the frame path, after the substep loop; `substeps` the
## substeps that call ran), as StateViews.projection_frame schedules the build benefit: only while a view
## reads the live slot (`read`), and only on a frame that ran no substep with the accumulator at least
## hold.train_frame_phase of a substep in (the scenes' refetch is early in the interval). When every frame
## substeps (fast-forward), it runs after hold.train_starve_frames such frames in a row. Returns whether it
## probed.
func _train_frame(substeps: int) -> bool:
	if not bool(_train_cache.get("read", false)):
		_train_cache["starve"] = 0
		return false
	if substeps > 0:
		var starve := int(_train_cache.get("starve", 0)) + 1
		_train_cache["starve"] = starve
		if starve < int(_req_f("realm.hold.train_starve_frames")):
			return false
	elif _acc < _req_f("realm.hold.train_frame_phase") * substep_s():
		return false
	_train_cache["starve"] = 0
	_train_cache["read"] = false
	var sup := _train_support(_train_war(), true)
	var q := digest_q()
	var key := [rev, t, q, sup, realm.train_state()]
	var c: Array = _train_cache.get("live", [])
	if not c.is_empty() and c[0] == key:
		return false
	_train_probe("live", key, sup, q, false)
	return true


## train_probe's `sup` {fort_id: [w_in, redirect, raise_max, tide, block]} for every held fort (`block` from
## _forecast_siege: the step's, credited from E4), at `war`
## mass/s of WAR split as the last dispatch splits it (RealmSim.war_at). Relish's committed arrival: while
## she travels to a fort, the train reads her there (her tide and redirect, and the split with her tide
## moved there, RealmSim.war_at_tide), since her trip takes seconds (relish.travel_speed) and nothing
## but a command changes it. `live` before the first substep after a load (no dispatch yet) reads the
## saved r_in with her where she stands, as the other readouts do.
func _train_support(war: float, live: bool) -> Dictionary:
	if not realm.forts.any(func(f): return bool(f.get("held", false))):
		return {}  # nothing held: no split to read
	var fx := _relish_effects()
	var dest := str(relish["target"]) if relish["state"] == "travelling" else ""
	if realm.fort_by_id(dest).is_empty():
		dest = ""
	var wars: Array = []
	if live and realm._disp_w.size() != realm.forts.size():
		wars = _fort_wars()
	elif dest != "":
		wars = realm.war_at_tide(war, str(_realm_inputs.get("tide_fort", "")), float(_realm_inputs.get("tide_bias", 1.0)),
			dest, _req_f("realm.relish.tide_bias"))[0]
		fx = {"tide_fort": dest, "redirect_fort": dest}
	else:
		wars = realm.war_at(war)[0]
	var siege := _forecast_siege()  # (the step's blocks, credited from E4)
	var sup := {}
	for i in realm.forts.size():
		var f: Dictionary = realm.forts[i]
		if RealmSim.is_held(f):
			var id: String = f["id"]
			sup[id] = [float(wars[i]), fx["redirect_fort"] == id, _raise_rate, fx["tide_fort"] == id,
				RealmSim._siege_at(siege, id)]
	return sup


## _fort_readout's garrison_rate alone (war_supports).
func _fort_rate(f: Dictionary, w_in: float) -> float:
	var fx := _relish_effects()
	return realm.garrison_rate_of(f, w_in, fx["redirect_fort"] == str(f["id"]), _raise_rate, digest_q())


## view_projection's valve: `v` normalised as cmd_set_valve normalises it; the current valve for one
## it would refuse (not three finite numbers ≥ 0 with a positive sum) or one within 1e-12 of it.
func _projection_valve(v: Dictionary) -> Dictionary:
	var x: Array = []
	for k in ["work", "war", "flood"]:
		var e: Variant = v.get(k)
		if not (e is float or e is int) or not is_finite(float(e)) or float(e) < 0.0:
			return valve.duplicate()
		x.append(float(e))
	var m := maxf(x[0], maxf(x[1], x[2]))
	if not (m > 0.0):
		return valve.duplicate()
	var n := _normalised(x[0] / m, x[1] / m, x[2] / m)
	for k in n:
		if absf(float(n[k]) - float(valve[k])) > 1e-12:
			return n
	return valve.duplicate()


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
## morale and its factors, the stocks and caps, trade, the convoy. ladder_effective is the ladder after the
## stances acting (E3-1).
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


## §5.11 · E3, live from E3-1: the toggles, each stance's condition (`active`, on or off), its last change's beat,
## its hold left and the change in each net rate if it were toggled now (StateViews.stances).
func view_stances() -> Dictionary:
	return StateViews.stances(self)


## §5.12 · E1. The simulacra ready and the phylactery charges are live from E3-4 (cmd_craft).
func view_inventory() -> Dictionary:
	return StateViews.inventory(self)


## §5.12 · E1.
func view_big_undead() -> Dictionary:
	return StateViews.big_undead(self)


## §5.12 · E1. The garrison and starter figures are §7.1's for the fort she stands at;
## strength is E2 (0).
func view_party() -> Dictionary:
	return StateViews.party(self)


## §5.13 · E3, live from E3-2 (StateViews.backups): the vats, and what a death would cost now (StateViews.death_rule).
func view_backups() -> Dictionary:
	return StateViews.backups(self)


## §5.14 · E2 (fronts live from E3-5). The readout, q, the tithe and the fronts are live (StateViews.vei).
## can_begin/reason are cmd_begin_boss()'s check.
func view_vei() -> Dictionary:
	return StateViews.vei(self)


## §5.18 · E2b-2 (api_version 6, T3.3b): the catch-up's progress, for a progress screen (the map's, Phase
## I). `active` while one runs (a chunked cmd_load's, or an open-game gap's; IDLE §4); `done_s` of
## `total_s` sim seconds are run. Once it is done `done_s == total_s` (the last one's), and 0 and 0 before
## any since the last new game or load.
func view_catchup() -> Dictionary:
	return {"rev": rev, "active": _catchup.active, "done_s": _catchup.done_s(self), "total_s": _catchup.total_s}


## §5.19 · E2b-2 (api_version 6, T3.3c; IDLE §7, api-request #7 d): the last "While you were away" report,
## {rev, shown, away_s, capped, gains, ready, losses}, each line {text, kind, target}; shown false and every
## list empty before any (StateViews.away).
func view_away() -> Dictionary:
	return StateViews.away(self)


## §4.1 · E2b-2 (v6, T3.3c): the report is dismissed: view_away().shown becomes false (its lines stay until a
## new game, a load or the next report replaces them). Reasons: catching_up.
func cmd_dismiss_away() -> Dictionary:
	if _catchup.active:
		return _refuse_catching_up()
	if not _away.is_empty():
		_away["shown"] = false
	rev += 1
	return {"ok": true, "reason": ""}


## A reporting catch-up's end (Catchup.run, after its events are collected): the report from what it started
## from (`before`, StateViews.away_before), the state now and its collected events, then `away_report {away_s,
## capped}` queued for the scenes, once.
func _report_away(before: Dictionary, evs: Array, away_s: float, capped: bool) -> void:
	_away = StateViews.away_report(self, before, evs, away_s, capped)
	_emit({"type": "away_report", "away_s": away_s, "capped": capped})


## Not contract (tests; T3.3c's away report): the events the last catch-up that a report replaces
## collected instead of queuing them (a load's, or an open-game gap's of idle.report_min_s or more), in
## queue order with their `t`, as deep copies. [] after a new game, or a load with nothing to catch up.
func catchup_events() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e in _catchup.events:
		out.append((e as Dictionary).duplicate(true))
	return out


# ----------------------------------------------------------------- §3 tick ----
## Vei's digest cost q (MECHANICS §2.2): clamp(q0 + q_forge · forge_level + q_raise, 1, q_max), q_raise =
## q_raise_max · max(0, (ema_score − 50) / 50). forge_level is TownSim's (the forge job's levels). E3-3 dropped
## the formula's Σ foreman_q (the run's manager's ruling): a foreman adds no q of its own; a Forge foreman reaches
## q through forge_level, its smiths' work multiplied (TownSim step 5).
func digest_q() -> float:
	var ema := float(_readout["q_raise_ema"])
	var q_raise := _q_raise_max * maxf(0.0, (ema - 50.0) / 50.0)
	var q := _req_f("realm.q.q0") + _q_forge * float(town_sim.forge["level"]) + q_raise
	return clampf(q, 1.0, _q_max)


## Each raised bucket {score, mass}, in apply order, moves ema_score by α = 1 − 0.5^(mass /
## q.raise_half_mass): a half-life in mass raised, not in time, so it holds while no circles arrive.
func _raise_ema(raised: Array) -> void:
	var half := _req_f("realm.q.raise_half_mass")
	var ema := float(_readout["q_raise_ema"])
	for e in raised:
		var m := maxf(0.0, float(e["mass"]))
		var a := (1.0 - pow(0.5, m / half)) if half > 0.0 else (1.0 if m > 0.0 else 0.0)
		ema += a * (clampf(float(e["score"]), 0.0, 100.0) - ema)
	_readout["q_raise_ema"] = ema


## §3 step 3: the current valve moves toward the target along the straight line, by at most
## `valve.slew_per_s · dt` of L1 distance, so its components always sum to 1.
func _slew_valve(dt: float) -> void:
	valve = _slewed_valve(dt)


## The valve one slew of `dt` from now (pure): what _slew_valve sets, and what the build benefit's
## hypothetical step splits with (StateViews.projections).
func _slewed_valve(dt: float) -> Dictionary:
	var rate := _slew_per_s
	var l1 := 0.0
	for k in valve:
		l1 += absf(float(valve_target[k]) - float(valve[k]))
	var max_step := rate * dt
	if l1 <= max_step + 1e-12:
		return valve_target.duplicate()
	var f := max_step / l1
	var v := valve.duplicate()
	for k in v:
		v[k] = float(valve[k]) + (float(valve_target[k]) - float(valve[k])) * f
	return v


## Advances the sim by `dt` seconds in fixed substeps. Returns substeps run.
## max_substeps > 0 caps the work (the frame path); the remainder is then dropped. On the frame path a
## frame whose real time (dt / time_scale) is above idle.gap_s goes through catch-up instead (IDLE §4; its
## whole seconds, chunked, the fraction kept in the accumulator), so debug fast-forward stays live play.
## While a catch-up is active each call runs one chunk of it (idle.catchup_steps_per_chunk core steps)
## instead of live time; the calls' own time accumulates and, once the catch-up is done, runs as one
## frame's time (with the cap raised to idle.gap_s of substeps, so at 1× none of it is dropped). Returns
## 0 for a call that ran catch-up.
func tick(dt: float, max_substeps := 0) -> int:
	if paused or not is_finite(dt) or dt <= 0.0:
		return 0
	if _catchup.active:
		_catchup.frame_acc += dt
		_catchup.run(self, int(_req_f("economy.idle.catchup_steps_per_chunk")))
		if _catchup.active:
			if max_substeps > 0:
				_frame_work(0)
			return 0
		dt = _catchup.frame_acc
		_catchup.frame_acc = 0.0
		if max_substeps > 0 and not _is_gap(dt):
			max_substeps = maxi(max_substeps, ceili(_req_f("economy.idle.gap_s") / substep_s()))
	if max_substeps > 0 and _is_gap(dt):
		var whole := floorf(dt)
		# the same sanity cap as a load's (_away_of): above idle.catchup_max_s the excess is dropped whole,
		# its fraction too, and the report says capped
		var most := _req_f("economy.idle.catchup_max_s")
		var capped := whole > most
		if capped:
			whole = most
		else:
			_acc += dt - whole
		if not run.is_empty():  # IDLE I5: no run survives a gap; it ends from its last checkpoint, run_ended first
			StateRuns.end_for_gap(self)
		_catchup.begin(self, whole, whole >= _req_f("economy.idle.report_min_s"))
		_catchup.capped = capped  # (begin clears it, as cmd_load sets it after begin)
		_catchup.run(self, int(_req_f("economy.idle.catchup_steps_per_chunk")))
		_frame_work(0)
		return 0
	return _advance(dt, max_substeps)


## Whether a frame of `dt` sim seconds is a gap (IDLE §4): its real time, dt / time_scale, above idle.gap_s.
func _is_gap(dt: float) -> bool:
	return dt / (time_scale if time_scale > 0.0 else 1.0) > _gap_s


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
	# the build benefit's refresh (STATE-API §5.10): the frame path only (a capped tick), on frames that ran
	# no substep and late in the substep interval, so it never lands on the substep-and-fetch frames or the
	# scenes' binds just after them (_frame_work)
	if max_substeps > 0:
		_frame_work(n)
	return n


## The frame path's background work, once per capped tick(): the build benefit's refresh
## (StateViews.projection_frame) and the wave train's (_train_frame, MECHANICS §3.5: the same frames, so the
## probe never lands where the scenes refetch). `substeps` the substeps the frame ran. Never during a
## catch-up (IDLE §4, E2b-2 T3.3b): a catch-up's frames run a chunk of core steps and come here with no
## substep, and nothing runs until it is done.
func _frame_work(substeps: int) -> void:
	if _catchup.active:
		return
	StateViews.projection_frame(self, substeps)
	_frame_path = true
	_train_frame(substeps)


## MECHANICS §3.2: mint = (P_base + P_per_pit · pits) · (1 + pit.bonus · feed), mass/s. `pits` is the working pits
## weighted by their foremen (TownSim.pit_weight, E3-3): their count while no foreman works a pit.
func _mint(pits: float, feed: float) -> float:
	return (_p_base + _p_per_pit * pits) * (1.0 + _pit_bonus * feed)


## The valve `v`'s split of `mint` (mass/s) with TownSim's `muster` (mass/s) (MECHANICS §3.2, §4.1; E4 step 5, ruling
## A1): WORK, WAR and FLOOD at the valve's shares, and the muster to Vei's queue with the FLOOD, unless the Muster
## stance acts (town_sim.muster_all: a deliberate act, every idle worker mustered), when the whole muster joins WAR.
## Before A1 every muster joined WAR, so the WORK the slots and the idle cap couldn't keep reached the forts and the
## valve had two real settings, FLOOD and not-FLOOD. `muster_war` records the route (view_hud.split.muster_to). `to_war`
## the route (the core step's: town_sim.muster_all for the step; a reading of the last step's: its _split.muster_war).
func _split_of(mint: float, v: Dictionary, muster: float, to_war: bool) -> Dictionary:
	return {"mint": mint, "work": mint * float(v["work"]), "war": mint * float(v["war"]) + (muster if to_war else 0.0),
		"flood": mint * float(v["flood"]) + (0.0 if to_war else muster), "muster": muster, "muster_war": to_war}


## Vei's pressure at held forts (E4 step 5, ruling B1; MECHANICS §3.4): max(1, (settled mint ÷ hold.mint_ref)^
## hold.mint_alpha), the factor on her living's pull on a held fort's garrison (RealmSim._k_dq). The settled mint is
## P_base + P_per_pit · the working pits: no feed term and no foremen, so it is a step function of the buildings (a
## pit's start or stop, an unpaid one), the same open and closed, and a new game's one pit (8.0) reads ×1 at any feed.
## Sub-linear (α < 1): a growing necropolis finds holding somewhat easier, never trivial. Her mass, pool, fronts and
## boss seed don't read it.
func hold_mult() -> float:
	if not (_mint_ref > 0.0):
		return 1.0
	var m := pow((_p_base + _p_per_pit * float(town_sim.pits())) / _mint_ref, _mint_alpha)
	return maxf(1.0, m) if is_finite(m) else 1.0


## RealmSim's held-fort pressure as the state stands (hold_mult): set at a core step's start (its input, which
## dead_rates reads too) and end (the readouts read the state after it), and on a load, so the readouts and the next
## step read the same value open and closed.
func _sync_hold_mult() -> void:
	realm.hold_mult = hold_mult()


## The highest tier the player has ever flipped (E4 step 9, the manager's 2026-11-17 14:24 ruling on step 9 (3)): the
## top tier among forts with flipped_count > 0, 0 before any flip. flipped_count is saved, never reset and counts every
## flip, so this needs no field of its own and an old save reads its own history.
func highest_tier_flipped() -> int:
	var h := 0
	for f in realm.forts:
		if int(f.get("flipped_count", 0)) > 0:
			h = maxi(h, int(f["tier"]))
	return h


## The idle relic trickle pays (the same ruling, MECHANICS §2's relics row): no raidable fort remains, read as every fort at or
## below the highest tier ever flipped being held, after at least one flip. A player walled at a tier (every fort they
## can take is theirs, the next tier out of reach) still gets relics; one fort lost back to Vei stops it.
func relic_trickle_paying() -> bool:
	var h := highest_tier_flipped()
	if h < 1:
		return false
	for f in realm.forts:
		if int(f["tier"]) <= h and not RealmSim.is_held(f):
			return false
	return true


## A step of the trickle while it pays: `dt` joins relic_trickle_s, and each economy.json relic_trickle.period_s of it
## pays one relic into the store, lost if the store is at its cap (as loot is). The accrued time is kept while it
## doesn't pay. Catch-up runs it per step, reading the condition at the step's start, so open and closed play can
## differ by at most one step's length each time the condition flips.
func _relic_trickle(dt: float) -> void:
	var period := _req_f("economy.relic_trickle.period_s")
	if not (period > 0.0):
		return
	relic_trickle_s += dt
	while relic_trickle_s >= period:
		relic_trickle_s -= period
		if relics < _cap_of("relics"):
			relics += 1
			trickle_paid += 1


## The inputs the wave's target rule reads, from the state as it stands (E4 step 5, ruling B1 (ii)): the settled WAR,
## q, Relish's tide and raise, the sieges, as the next core step will give them. The margin views and the telegraph
## (StateViews.fort_hold, next_wave) read these, not the last step's _realm_inputs, so a loaded state reads as the
## live one did (q and the trough feed move at a step's end).
## The margin views' basis as the state stands (E4 step 5, B1 (ii)): {margins (RealmSim.margins_of at _margin_inputs),
## next (RealmSim._tithe_target there, "" before the clock starts)}, computed once per state and shared by every fort's
## view_fort().hold and .tithe and by view_vei().tithe (view_realm reads them for each fort: before, each fort entry
## re-derived the inputs and the margins twice). Keyed on rev, t, Vei's pressure (hold_mult, mint_ref) and the realm's
## train_state (the held forts' stocks and graces, the clock's warning and wave), so a step, a command or an edit that
## moves any of them recomputes. Session only.
func _margin_view() -> Dictionary:
	var key := [rev, t, realm.hold_mult, _mint_ref, realm.train_state()]
	if _margin_memo.get("key") == key:
		return _margin_memo
	var ins := _margin_inputs()
	var mg := realm.margins_of(ins)
	_margin_memo = {"key": key, "margins": mg,
		"next": realm._tithe_target(ins, mg) if bool(realm.tithe.get("started", false)) else ""}
	return _margin_memo


func _margin_inputs() -> Dictionary:
	var fx := _relish_effects()
	return {"target_war": _train_war(), "digest_q": digest_q(), "tide_fort": fx["tide_fort"], "redirect_fort": fx["redirect_fort"],
		"redirect_rate": _raise_rate, "siege_block": _siege_blocks()}


## §3 step 3's inputs: this step's WORK mass, Relish home, the villages that follow necrosis, a
## snapshot of the forts before this step's realm step, Covington, the haul target, the relics. Each
## fort's `dead_rate` is RealmSim's projection of its corpses over the step (RealmSim.dead_rates, with
## Relish's redirect as she stands now), so the convoy reads them at its own moment (E2b-2 T3.3a).
## With `reuse` (the core step only) the forts are _step_forts, refilled in place: the same values.
func _town_inputs(work_mass: float, reuse := false) -> Dictionary:
	var forts: Array = []
	var fx := _relish_effects()
	var redirect: String = fx["redirect_fort"]
	var rates := realm.dead_rates(redirect, _raise_rate, digest_q() if redirect != "" or not realm.simulacra.is_empty() else 1.0)
	if reuse:
		forts = _step_forts
		var n := realm.forts.size()
		if forts.size() != n:
			forts.resize(n)
			_step_forts_of.resize(n)
		for i in n:
			var f: Dictionary = realm.forts[i]
			var of: Variant = _step_forts_of[i]
			if not (of is Array and is_same(of[0], f) and of[1] == f["pos"]):
				forts[i] = {"id": f["id"], "pos": _xy(f["pos"]), "dead": 0.0, "held": false, "dead_rate": 0.0}
				_step_forts_of[i] = [f, f["pos"]]
			var e: Dictionary = forts[i]
			e["dead"] = float(f["dead"])
			e["held"] = RealmSim.is_held(f)
			e["dead_rate"] = rates[i]
	else:
		for i in realm.forts.size():
			var f: Dictionary = realm.forts[i]
			forts.append({"id": f["id"], "pos": _xy(f["pos"]), "dead": float(f["dead"]), "held": RealmSim.is_held(f),
				"dead_rate": rates[i]})
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


## Takes the convoy legs' claims (TownSim._haul: the corpses formed at a fort inside this step before a leg's
## pickup) after the realm step, which had first call on them: each at most what its fort holds now, landed by
## TownSim.land_claim (onto the convoy still on its way back, else into the body store up to its cap). What isn't
## taken stays at the fort. Mass moves between held pools only, so the ledger is unchanged (MECHANICS §4.2).
func _take_claims(claims: Array, dt: float) -> void:
	for cl in claims:
		var f := realm.fort_by_id(str(cl["fort_id"]))
		if f.is_empty():
			continue
		var got := town_sim.land_claim(minf(float(cl["mass"]), maxf(0.0, float(f["dead"]))), bool(cl["landed"]), dt)
		f["dead"] = maxf(0.0, float(f["dead"]) - got)


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
	_ticks += 1


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
	var trickle_on := relic_trickle_paying()  # (E4 step 9, ruling 3) read from the state the step starts from
	_sync_foremen()  # (E3-3) TownSim's foremen as the big undead stand; a no-op unless a place changed
	# §3 step 1: the stances (E3-1): at a new beat their conditions are read from the state the step starts from,
	# then the ones acting are given to TownSim for this step
	_stance_step(dt)
	# §3 step 2: the valve slews, then splits the mint. The mint reads the working pits now and the
	# feed of the step before (both dimensionless, so a step of any length takes them as they are)
	_slew_valve(dt)
	var mint := _mint(town_sim.pit_weight(), float(town_sim.rates.get("feed", 0.0)))
	var work := mint * float(valve["work"])
	_sync_hold_mult()  # (B1) the held-fort pressure this step: TownSim's convoy reads RealmSim.dead_rates with it
	# §3 step 3: TownSim on this step's WORK, rate × dt. A save written before the lag (E2a) can hold
	# WORK in flight: it arrives with this step's, once
	var town := town_sim.step(dt, _town_inputs(work * dt + work_pending, true))
	work_pending = 0.0
	_apply_pickups(town["pickups"])
	relics = maxi(0, relics - int(town["relics_spent"]))
	for ev in town["events"]:
		_emit_town(ev)
	if town_sim.structure_rev != int(_tiers_seen[0]) or town_tier != str(_tiers_seen[1]):
		BuildRules.rise_tiers(self)
		_tiers_seen = [town_sim.structure_rev, town_tier]
	# the build queue (IDLE §5, MECHANICS §4.4): right after the tiers, so a tier that rises this step
	# opens its entries this step and this step's income counts
	BuildRules.process_queue(self)
	# TownSim's muster joins this step's FLOOD, or its WAR while the Muster stance acts (_split_of; E4 step 5, A1)
	_split = _split_of(mint, valve, float(town["muster_mass"]) / dt, town_sim.muster_all)
	# §3 step 4: Relish's travel and state (her arrival's moment inside the step, for a walk home: _emit_realm)
	_arrived_t = -INF
	if relish["state"] == "travelling":
		var left := maxf(0.0, _dist_to(str(relish["target"])) - ARRIVE_EPS) / travel_speed()
		if left <= dt:
			_arrived_t = t - dt + left
	_step_relish_travel(dt)
	# §3 step 5: RealmSim, pure on these inputs; its events get this step's t
	var fx := _relish_effects()
	# (siege_block: tithe.siege_block at each fort a big undead sieges, E3-3: _siege_blocks)
	_realm_inputs = {
		"war": _split["war"], "flood": _split["flood"], "digest_q": digest_q(),
		"tide_fort": fx["tide_fort"], "tide_bias": _req_f("realm.relish.tide_bias"),
		"redirect_fort": fx["redirect_fort"], "redirect_rate": _raise_rate,
		"siege_block": _siege_blocks(), "hold_mult": realm.hold_mult,
		"target_war": _train_war(),  # (B1 (ii)) the settled WAR the wave's target rule splits: not the sawtooth's
	}
	var cleared0 := realm.cleared_total
	realm.step(dt, _realm_inputs)
	_take_claims(town["claims"], dt)  # the corpses the convoy's legs claimed inside the step, now the realm step is done
	var cleared := realm.cleared_total - cleared0
	var evs := _emit_realm(realm.drain_timed(), dt, mark)
	# §3 step 6: the backups (E3-2): the vats grow on the hands TownSim's step gave them, and a dead Relish's
	# respawn counts down (catch-up clips a step at it: Catchup.next_event_s)
	_grow_vats(dt, town["vat_hands"])
	_sync_tend()  # a vat whose clone filled this step gives its tend hand back (E4 step 10)
	if relish["state"] == "dead":
		_count_down_respawn(dt)
	if trickle_on:
		_relic_trickle(dt)
	# §3 step 7: the ledger books this step's source and sinks (held is read live). Ledger.source, sink and
	# overflow's own sums, inline (E2b-2 T3.3b2: their key checks format a message every call, about 1 µs each,
	# ten a step); the keys are the ledger's fixed set
	var src: Dictionary = _ledger.sources
	var snk: Dictionary = _ledger.sinks
	src["mint"] = float(src["mint"]) + mint * dt
	for k in _TOWN_SINKS:
		snk[k] = float(snk[k]) + float(town[k])
	snk["cleared"] = float(snk["cleared"]) + cleared
	# the currency tally beside the mass (not mass; IDLE §6): what the gold and bone caps clipped
	var sto: Dictionary = _ledger.stores
	sto["gold"]["overflow"] = float(sto["gold"]["overflow"]) + float(town["gold_overflow"])
	sto["bone"]["overflow"] = float(sto["bone"]["overflow"]) + float(town["bone_overflow"])
	snk["pool_overflow"] = float(snk["pool_overflow"]) + realm.pool_overflow  # the march-back past Vei's pool cap (MECHANICS §3.4)
	_note_realm_flows(dt, cleared)
	# §3 step 8: the readouts (B1: they read the held-fort pressure of the state after the step, as a load would)
	_update_readout(dt, realm.vei["r_in_undead"], realm.r_digested_undead)
	_sync_hold_mult()
	return evs


## This step's realm events ([[seconds into the step, event], ...], RealmSim.drain_timed), stamped
## at their moment: a retake inside the step carries its own time (IDLE §4), the rest the step's
## end. One stamped before the step's end goes in ahead of the step's other events (from `mark`),
## in time order, so `t` never decreases. A retake sends the siege big undead there home (IDLE I6,
## `big_undead_returned` right after it), and Relish home if she stands there (IDLE I5, _walk_home:
## `relish_returned` after those, at the same t). Returns the realm events, in queue order.
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
			# she walks home if she stood there at the retake: not if she arrived after it inside this step (a
			# live substep would have seen the fort fall before she got there, and she stays, as at any Vei fort)
			if relish["state"] == "at_fort" and str(relish["at"]) == str(ev["fort_id"]) and _arrived_t <= float(ev["t"]):
				_walk_home(str(ev["fort_id"]), float(ev["t"]))
				out.append({"type": "relish_returned", "fort_id": str(ev["fort_id"]), "cause": "retaken", "t": ev["t"]})
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
	field.inject(realm.cov_pos, true, src_main * (1.0 + _src_per_pit * town_sim.pits()) * dt, 2)
	var vei_str: float = 1.0 + realm.vei["living_pool"] / maxf(1.0, _vei_pool_cap)
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


# ------------------------------------------------------------------------ death ----

## Relish's death that ends a run (§8.3 raid step 10, boss step 4; E3-2, MECHANICS §7): StateRuns.death. The caller
## has closed the run. A raid's: it judges by the clones ready now (a boss fight's final death passes 0).
func _death(run_id: int) -> void:
	StateRuns.death(self, run_id, clones_ready)


## The backups step's respawn (§3 step 6; E3-2): dead_s_left runs down by the step's dt, and at 0 she wakes at
## Covington (_respawn). Catch-up clips a step at it, so a step never runs past it (Catchup.next_event_s).
func _count_down_respawn(dt: float) -> void:
	var left := float(relish["dead_s_left"]) - dt
	if left <= 1e-9:
		_respawn()
	else:
		relish["dead_s_left"] = left


## She wakes at Covington, home (MECHANICS §7): from her clone (`respawn_with_clone`) or reformed after being unmade.
## Emits relish_respawned {with_clone, at: "covington"} with the step's t.
func _respawn() -> void:
	var with_clone := bool(relish["respawn_with_clone"])
	_place_relish("covington")
	_emit({"type": "relish_respawned", "with_clone": with_clone, "at": "covington"})


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
	_sync_foremen()  # (E3-3: TownSim's foremen come from the loaded big undead's places)
	_reset_train()
	_catchup = Catchup.new()
	_away = {}  # a load replaces the last report (the next catch-up's, if any, follows)
	_tiers_seen = [-1, ""]
	# the vats come back after TownSim's own load: they open the tend slots (refilled, the saved
	# states kept); a staffed vat holding a ready clone opens none (_tended_vats, E4 step 10), as live play left it
	town_sim.set_vats(_tended_vats(), true)
	# the stances (E3-1): the conditions are read again at the loaded t's next beat; the ones acting are given back
	# to TownSim as saved (Thrift's buildings are in their saved state). A building Thrift idles while Thrift
	# doesn't act (a hand-made save) goes back to work
	_stance_beat = beat_at(t)
	_stance_acting = {}
	_stance_proj = []
	_apply_stances(t, true)
	if not _stance_acting.has("thrift"):
		town_sim.thrift_resume()
	_restore_dispatch()
	# IDLE I5 (E2b-2 T3.3c): a run open at the save ends now, from its last checkpoint, before any catch-up
	# (cmd_load's, either path); its events are queued as live
	if m.get("pending_retreat") is Dictionary:
		StateRuns.apply_pending(self, m["pending_retreat"])
	return {"ok": true, "reason": ""}


## The load flash (E2b-2 T3.3b; T3.4b's concern 4). The last substep's split (_split) and WAR dispatch
## (RealmSim's _disp_w, _disp_lim and r_war_to_vei) are session-only, so before the first substep after a
## load the readouts read the saved r_in with Relish where she stands, not her committed arrival or the
## valve's target: midgame_2flips as loaded read both held forts safe for a substep, then thin. This
## rebuilds them from what the save holds, as that substep left them, so a load reads what the state read
## before its save (to the save's 15 digits):
## - the mint from TownSim's saved worker inflow (WORK is the mint × the valve's work share, taken in the
##   same step), or with a work share of 0 the next step's (_mint at the working pits and the feed now);
##   the muster from TownSim's saved rate; WAR, WORK and FLOOD as that step split them;
## - each fort's dispatch weight (RealmSim._war_weight, with her tide where the saved state puts her, as
##   the step's inputs did), for every fort that step sent WAR (r_in > 0) and every held fort;
## - the limits: a fort whose r_in / weight is under the water level (the largest r_in / weight) took its
##   limit, so its limit is its r_in; the rest had room (no limit). With WAR left over for Vei every
##   target took its limit.
## Nothing saved changes (to_dict is the same) and no step runs; the first substep replaces all of it.
## view_rates' corpses and backlog and view_vei's raw diff still read 0 until then (STATE-API §9.1).
func _restore_dispatch() -> void:
	var wm := worker_mass()
	var rw: Dictionary = town_sim.rates.get("workers", {})
	var muster := float(rw.get("muster", 0.0)) * wm
	var mint := 0.0
	if float(valve["work"]) > 0.0:
		mint = float(rw.get("in", 0.0)) * wm / float(valve["work"])
	else:
		mint = _mint(town_sim.pit_weight(), float(town_sim.rates.get("feed", 0.0)))
	_split = _split_of(mint, valve, muster, town_sim.muster_all)  # (the stances are re-applied before this: from_dict)
	var war := float(_split["war"])
	var fx := _relish_effects()
	var bias := _req_f("realm.relish.tide_bias")
	_sync_hold_mult()  # (B1) the held-fort pressure of the saved state, as the step that wrote it ended
	_realm_inputs = {"war": war, "flood": _split["flood"], "digest_q": digest_q(), "tide_fort": fx["tide_fort"],
		"tide_bias": bias, "redirect_fort": fx["redirect_fort"], "redirect_rate": _raise_rate, "siege_block": _siege_blocks(),
		"hold_mult": realm.hold_mult, "target_war": _train_war()}
	var w: Array[float] = []
	var given := 0.0
	var level := 0.0
	for f in realm.forts:
		var r_in := float(f["r_in"])
		var wt: float = realm._war_weight(f, fx["tide_fort"], bias) if r_in > 0.0 or RealmSim.is_held(f) else 0.0
		w.append(wt)
		given += r_in
		if wt > 0.0:
			level = maxf(level, r_in / wt)
	var left := war - given
	var spill := left > 1e-9 * war  # WAR fell through to Vei: every target was at its limit
	var lim: Array[float] = []
	for i in realm.forts.size():
		var r_in := float(realm.forts[i]["r_in"])
		lim.append(r_in if w[i] > 0.0 and (spill or r_in < level * w[i] * (1.0 - 1e-9)) else INF)
	realm._disp_w = w
	realm._disp_lim = lim
	realm.r_war_to_vei = left if spill else 0.0
	realm.r_flood = _split["flood"]  # (view_lanes' FLOOD lane; the step sets it before it reads it)


## economy.json sim.autosave_s: real seconds between the shell's autosaves.
func autosave_s() -> float:
	return _req_f("economy.sim.autosave_s")


# ------------------------------------------------------- §4.1 save and load ----
## "1:04 · Village · odds 0.08": the clock as h:mm, the town tier, the Vei odds.
@warning_ignore("integer_division")
func _summary() -> String:
	var mins := int(t / 60.0)
	return "%d:%02d · %s · odds %.2f" % [mins / 60, mins % 60, town_tier.capitalize(), float(_vei_readout()["odds"])]


## Unix seconds now: clock_override when it is set (a test's "now"), else the system clock. The sim's one
## read of the wall clock (cmd_save stamps saved_at with it; cmd_load measures the time away with it).
func _now_unix() -> int:
	return clock_override if clock_override >= 0 else int(Time.get_unix_time_from_system())


func cmd_save(slot: String) -> Dictionary:
	var out := {"ok": false, "reason": "", "saved_at": 0, "path": ""}
	if _catchup.active:
		out["reason"] = "catching_up"  # the state is behind the clock: a save now would lose the rest
	elif not SaveIO.slot_ok(slot):
		out["reason"] = "bad_slot"
	elif realm == null:
		out["reason"] = "write_failed"  # no game to save
	else:
		var saved_at := _now_unix()
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


## §4.1. Loads the slot, then catches up the real time since its saved_at (IDLE §4): `away_s` seconds (the
## whole seconds since then, 0 if the clock went back or the file has no saved_at, at most
## idle.catchup_max_s; `capped` when it was more). Synchronous, unless `chunked`: then it returns at once
## with the catch-up pending, and tick() advances it a chunk per call (view_catchup).
func cmd_load(slot: String, chunked := false) -> Dictionary:
	var fail := {"ok": false, "reason": "", "away_s": 0.0, "capped": false}
	if _catchup.active:
		return _refuse_catching_up({"away_s": 0.0, "capped": false})
	if not run.is_empty():
		fail["reason"] = "busy"
		return fail
	if not SaveIO.slot_ok(slot):
		fail["reason"] = "bad_slot"
		return fail
	var d := SaveIO.read_file("%s/%s.json" % [save_dir, slot])
	if d.is_empty():
		fail["reason"] = "no_save"
		return fail
	var r := from_dict(d)
	if not r["ok"]:
		fail["reason"] = "bad_version" if r["reason"] == "bad_version" else "no_save"
		return fail
	var away := _away_of(d.get("saved_at"))
	_catchup.begin(self, float(away[0]), true)
	_catchup.capped = away[1]
	if not chunked:
		_catchup.run(self)
	return {"ok": true, "reason": "", "away_s": float(away[0]), "capped": away[1]}


## [the whole seconds to catch up, capped]: now (_now_unix) − `saved_at` (a save file's integer unix
## seconds), 0 when that is negative or the file has none, at most idle.catchup_max_s (capped above it).
func _away_of(saved_at: Variant) -> Array:
	if not SaveIO.fits(saved_at, TYPE_INT):
		return [0, false]
	var away := maxi(0, _now_unix() - int(saved_at))
	var most := int(_req_f("economy.idle.catchup_max_s"))
	return [mini(away, most), away > most]


## §4.1: `[{slot, saved_at, summary}]`, newest first (ties by slot). Not a command: no rev bump.
func list_saves() -> Array[Dictionary]:
	return SaveIO.list_saves(save_dir)


## §4.6, E1. Loads <fixture_dir>/<name>.json through from_dict.
func cmd_debug_load_fixture(name: String) -> Dictionary:
	if debug_enabled and _catchup.active:
		return _refuse_catching_up()
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
