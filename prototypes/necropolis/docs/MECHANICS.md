# Necropolis: mechanics (v2)

The systems spec. Player intent is in `GAMEPLAY.md`. Starting numbers and pacing are in
`BALANCE.md`; this file names config keys, not values. All numbers live in `configs/*.json`. The
exact field lists of every command, view, seed, result and event live in `docs/STATE-API.md`, which
the economy unit writes at milestone E1 from §1.2 here.

**Idle model:** `IDLE.md` (2026-11-13, from Shawn's answers) wins over this doc wherever they conflict.

v2 folds in two reviews (run folder `reports/review-docs-vision.md` and
`reports/review-docs-systems.md`).

## 0. Decisions and deviations (reversible; each has its reason)
| # | decision | deviates from | why |
|---|---|---|---|
| D1 | **The valve.** Covington's mint splits WORK / WAR / FLOOD, set by the player. | BRIEF §5 "position is the only lever" | Vision: "commiting a flow of forces"; the keep-working-or-send-to-Vei tradeoff. The flow still routes itself among the forts. |
| D2 | **`P_relish` = 0.** | Necropolis 3.0, RECOMMENDED 1500 | BRIEF §12's stricter test; the audit showed staying home beat raiding. |
| D3 | **Relish redirects the dead shipment where she stands, and raises it.** | BRIEF has only the raise channel | Vision: "move Relish to change tides and redirect shipments". Position only; no routing UI. |
| D4 | **Forts flip** when their warden falls, and **Vei's tithe waves retake them.** | Realm has no capture and no pushback | Flips must matter on the macro, and the macro needs an opposing force (vision review M2). |
| D5 | **Workers are a stream with a lifetime,** counted in workers of `worker.mass`. | Constant `idle_undead` 6 | Streams, not quantities. |
| D6 | **Gold is the living's trade currency, with upkeep as its sink; living are capped by housing.** | Prior-art suggestion to drop gold | The living must feed the economy. Upkeep and the cap stop the pile-up. |
| D7 | **Big undead are a named, countable stock.** | "Streams, not stocks" | A stream for the many, a stock for the few. |
| D8 | **Essence drops from every death in a dungeon, yours included.** | Prototypes drop it from enemies only | Vision: "essences drop from undead". |
| D9 | **Death is real, backups buy it off, nothing resets.** | R&R total wipe; Obsidian "never wiped" | Vision. |
| D10 | **Vei is the ferrier;** the final test has **fronts**, then a circle-driven break. | Slab's Raven Queen; HP-scaled boss | The fiction fits a flow game; fronts are validated, and "more HP" is hated. |
| D11 | **Policies are a job-priority ladder plus named stances,** not a rule editor. | Gambits / FFXII rules (Obsidian) | Shawn's own worry: "programming homework". Rule engines oscillate (systems review). |
| D12 | **The sustained differential is a trailing mean** (EMA over `readout.ema_s`) of the true differential, not a cloned-sim probe. | Audit A2's recommendation (probe) | The trailing mean is one of the two Realm definitions (`formulas/01-reference-sim`); a probe costs 25–70 ms per refresh. |
| D13 | Hue, mark frequency and tempo phase follow 06 and angiogram (VISUAL-LANGUAGE §1). | BRIEF's literal formulas | The audit showed the literal ones erase identity or miss the band. |
| D14 | Shawn's "finish this game" overrides the repo's throwaway-prototype rules for Necropolis. | repo CLAUDE.md | Direct instruction. |

## 1. Architecture

### 1.1 Modules and owners (exclusive; see §9 for configs)
| module | file | owner unit | kind |
|---|---|---|---|
| GameState | `scripts/sim/game_state.gd` | economy | RefCounted; all state, `tick(dt)`, commands, views, events, save |
| Results | `scripts/sim/results.gd` | economy | schema validation for seeds and results, used by both sides' tests |
| RealmSim | `scripts/sim/realm_sim.gd` | economy | `step(dt, inputs)`, pure on its inputs |
| TownSim | `scripts/sim/town_sim.gd` | economy | workforce, jobs, living, gold, bone, buildings' effects |
| Stances | `scripts/sim/game_state.gd` (the stance step, E3-1), `scripts/sim/town_sim.gd` (their effects) | economy | the job ladder and stances (§4.5); planned as `stances.gd`, kept in the two files they read and write |
| Backups | `scripts/sim/backups.gd` | economy | the only writer of Relish's death and respawn state; vats, clones, phylactery |
| Ledger | `scripts/sim/ledger.gd` | economy | source/sink/held accounting (§2.1); preloaded as `GameState.Ledger`, with no `class_name` (the dungeon's inner `RaidLogic.Ledger` would clash with a global one) |
| Game (autoload) | `autoload/game.gd` | economy | thin shell: real-delta ticking, autosave, `events` signal |
| Shot (autoload) | `autoload/shot.gd` | economy | debug harness; cheats become `cmd_debug_*` |
| Router | `scripts/main.gd`, `scenes/Main.tscn` | economy through E1, **map** after | scene swap, dive transition, `Engine.time_scale` reset |
| InfluenceField | `scripts/sim/influence_field.gd` | economy through E1, **ground** after | necrosis data; signatures frozen at E1 |
| RaidLogic, wardens | `scripts/raid/raid_logic.gd` and new files | dungeon | layout, ledger, loot rolls, warden specs |
| VeiFronts | `scripts/raid/vei_fronts.gd` | dungeon | fronts and the break (§6) |
| SlabLogic | `scripts/town/slab_logic.gd` | town | pure big-undead preview (ported from `slab/`) |

**Rules:**
- Scenes never mutate state. They read views and send commands. In-scene play returns one result,
  and GameState applies it.
- Files under `scripts/sim/`, `*_logic.gd`, `vei_fronts.gd` and `slab_logic.gd` never reference
  an autoload (`Game`, `ConfigDb`, `Pulse`, `Shot`) or `Engine`. A lint test enforces this.
- One config loader, `GameState.load_configs(dir)`, is shared by ConfigDb and the tests.

### 1.2 GameState API (E1 freezes names and shapes; additive only after that)
- Every command returns `{ok, reason, ...}`, with enumerated reasons.
- Every view returns a read-only copy carrying `rev:int`.
- `api_version` lives in `to_dict()`.
- `tests/test_api_contract.gd` asserts key sets and types and fails on any rename or removal.

At E1 every entry exists, backed by stubs that return correct shapes until E2 and E3 fill them.

**Commands**
- **Game:** `cmd_new_game(seed)`, `cmd_save(slot)`, `cmd_load(slot)`, `list_saves()`,
  `cmd_set_time_scale(x)` (1, 2 or 4; refused in a dungeon or boss), `cmd_pause(b)`.
- **Macro:**
  - `cmd_set_valve(work, war, flood)` (refuses all zeroes);
  - `cmd_move_relish(node_id)` (refuses when `dead`, `in_dungeon` or `unknown_node`);
  - `cmd_cancel_travel()`;
  - `cmd_set_haul_target(fort_id | "auto")`.
- **Town:**
  - `cmd_build(building_id, lot_id)`, `cmd_upgrade(lot_id)`, `cmd_demolish(lot_id)`,
    `cmd_cancel_build(lot_id)`; the build queue `cmd_queue_build(building_id, lot_id)`, `cmd_unqueue(index)`,
    `cmd_reorder_queue(order)` (E2b-2, §4.4);
  - `cmd_set_job_priority(order:Array)`, `cmd_set_stance(stance_id, on:bool)`;
  - `cmd_raise_big_undead(husk_uid, remnant_uids, name)`, validated with SlabLogic's math;
  - `cmd_rename_big_undead(uid, name)`, `cmd_place_big_undead(uid, place)`, where place is
    `town:<lot_id>`, `fort:<id>` or `crypt`;
  - `cmd_craft(item_id)` (`simulacrum` | `phylactery_charge`), `cmd_deploy_simulacrum(fort_id)`;
  - `cmd_staff_vat(slot, on)`.
- **Dungeon and boss:**
  - `cmd_set_party(uids:Array)`;
  - `cmd_begin_dungeon(fort_id) -> {ok, seed}` (Relish must be at the fort), `cmd_abort_dungeon()`;
  - `cmd_run_checkpoint(run_id, loot, outcome)` (E2b-2 T3.3c, IDLE I5): the open raid's banked loot and the
    exit it would end in, which a close, a crash, a load or a gap ends the run from;
  - `cmd_assign_front(uid, front_id)`;
  - `cmd_begin_boss() -> {ok, seed}`;
  - `apply_result(kind, result)` (`raid` | `boss`).
- **Debug:** `cmd_debug_*` (`grant`, `set_state`, `load_fixture`, `skip_time`), debug builds only.

**Views**
- **HUD and realm:**
  - `view_hud()`: the top bar, as signed net rates (mint, workers, bodies, gold, bone, living), the
    sign, the drain time and the odds;
  - `view_rates()`: `{id: {in, out, net}}` over a fixed exported id list;
  - `view_lanes()`: `[{from, to, kind: war|flood|work|dead|living|haul|redirect, rate, bias,
    why}]`, where `why` is a short change callout such as "Relish left" or "tithe wave" (vision S1);
  - `view_realm()`, `view_fort(id)`, `view_field()`, `view_villages()`;
  - `view_away()`, `cmd_dismiss_away()` (E2b-2 T3.3c; IDLE §7): the "While you were away" report, built at
    a reporting catch-up's end, kept until dismissed;
  - `view_projection(valve, settled := false)`: the held forts' margins, "WAR supports N of M", the
    split and the payoff at another valve, pure (E2b-2, §3.5); `settled` judges the margins against the
    wave train (T3.4b), as `view_fort` does, instead of a drag's one-wave probe.
- **Relish:** `view_relish()`: state, pos, target, heading, `dead_s_left`, phylactery charges,
  clones ready, `can_descend` and the reason.
- **Town:** `view_town()`, `view_catalog()` (each building with cost, `can_build` and the reason),
  `view_stances()`, `view_backups()` (including "what a death would cost right now"),
  `view_staffing_projection(order, vats)` (the staffing another job order would give; E2b-2).
- **Inventory:** `view_inventory()` (uids for everything), `view_big_undead()`, `view_party()`.
- **Vei:** `view_vei()`: backlog, diff, sign, drain_s, odds, fronts `[{id, need, have}]`, the next
  tithe wave's ETA and target.
- **Seeds:** `view_dungeon_seed(fort_id)`, `view_boss_seed()`.

**Events:** `drain_events() -> [{t, type, ...}]`. Types:
- `relish_died{outcome}`, `relish_respawned`;
- `building_started`, `building_done`, `building_unpaid`, `tier_up`, `queue_started` (E2b-2);
- `fort_flipped`, `fort_retaken`, `big_undead_returned` (E2b-2), `tithe_warning`, `tithe_wave`;
- `stance_fired`, `loot_banked`, `vei_result`, `run_ended` (E2b-2: a gap ended the open run), `relish_returned`
  (E2b-2: her fort retaken, she walks home), `away_report` (E2b-2: the away report is ready);
- `autosaved`, `save_failed`.

The autoload re-emits each event as a signal.

**Seeds and results** carry `run_id` and `seed_rev`. `apply_result` rejects:
- a `fort_id` that isn't where Relish is;
- a repeated `run_id`;
- an unknown `v`.

Validation lives in `Results.validate(kind, dict) -> reasons[]`, and both sides test with it.

**Persistence**
- `to_dict()`/`from_dict()` survive a JSON round trip:
  - ints are restored from floats;
  - no Vector2 (positions are rebuilt from config);
  - no INF (drain "∞" is a view value only);
  - no int dictionary keys (use arrays);
  - seeds are saved as strings.
- Saves are atomic (tmp + rename) with `v` and a migrate hook. A corrupt file counts as no save.
- Autosave runs every 30 s and on scene change, and never persists `in_dungeon`. A run open at the save
  is written as `pending_retreat` (its last checkpoint; E2b-2 T3.3c, IDLE I5). On load, Relish is at the
  fort and that run ends as a retreat from its last checkpoint, before the catch-up: the loot banked by
  then, no flip; a checkpoint at the warden's victory beat ends as the win, one at the death beat as a
  death (STATE-API §4.5). A boss run is forfeited.
- Three fixture saves ship in `tests/fixtures/`: day-1, mid-game with 2 flips, and pre-Vei. Scene
  units use them for screenshots and view tests.

### 1.3 Time and ticking
- `GameState.tick(dt)` takes plain sim seconds and runs fixed `sim.substep_s` (0.5) substeps.
- The autoload feeds it **real** delta × `Game.time_scale`:
  `delta / max(0.05, Engine.time_scale) * time_scale`. Trance's `Engine.time_scale` never slows the
  realm.
- At most `sim.max_substeps_per_frame` per frame. A frame whose real time is above `idle.gap_s` goes
  through catch-up instead of being dropped (IDLE.md §4; E2b-2 T3.3b, STATE-API §3), in chunks of
  `idle.catchup_steps_per_chunk` core steps over the next frames; smaller remainders are dropped. Debug
  fast-forward stays live (the check is real time).
- Entering a dungeon or boss forces time scale 1. The router resets `Engine.time_scale = 1` on every
  scene swap.

**Order per substep** (a contract with tests):
1. stances and the job ladder (re-evaluated each beat, 1714 ms sim);
2. the valve slew and split. The mint reads the working pits now and the feed of the step before
   (both dimensionless), so the mint lags TownSim by one step, which is accepted (E2b: this
   replaces WORK arriving one substep late, a mass re-divided by the next step's dt);
3. TownSim, on this step's WORK as rate × dt, in the same step; then the tiers rise and the build queue
   is processed (§4.4);
4. Relish's travel and state (GameState);
5. `RealmSim.step(dt, {war, flood, digest_q, tide_fort, tide_bias, redirect_fort, redirect_rate})`.
   Holds and the tithe state are RealmSim's own state (§3.1), not inputs. P3b: `GameState._sync_won` runs at the
   core step's start, so a won game's split (step 2: FLOOD and the muster to WAR) and this step both see `won` (§3.4's
   "After the win");
6. Backups;
7. the ledger;
8. readouts (EMA);
9. the influence field, at `field.tick_hz`, time-sliced by the ground unit.

Steps 1–8 are the **core step** (`GameState._core_step(dt)`): valid at any `dt`, everything in it is
exact or a rate over the step (E2b T3.0; `tests/slow/convergence.gd` measures it). Step 9, the
village owners it decides and the lanes' callouts are the **presentation step**. Live play runs the
core step, then the presentation step, for each `sim.substep_s` substep. Catch-up (IDLE §4;
`scripts/sim/catchup.gd`, E2b-2 T3.3b) runs the same core step at its own lengths, clipped at events.
In place of the presentation it runs `idle.field_steps` field steps (`InfluenceField.catchup_step`, each
followed by the village owners) and the lanes' callouts once at its end, for the net change; its steps
don't count as substeps (`rev` rises by 1 for each).

The sim keeps ticking while any scene is open. Dungeon writebacks are **deltas clamped to the live
values**.

## 2. Resources and streams
| resource | unit | kind | sources | sinks | HUD |
|---|---|---|---|---|---|
| mint | mass/s | stream | raising pits (+ proportional feed bonus) | the valve | mint /s and split |
| workers | workers (`worker.mass` each) | stream with a lifetime | WORK / `worker.mass` | rot, muster | in /s, rot /s, net, steady state |
| war, flood | mass/s | stream | valve | forts / Vei's queue | per lane |
| corpses at forts | mass | pool (RealmSim `dead`) | your kills, the redirect | haul, Relish's raise, shipping to Vei, `k_clear` | pips |
| bodies | mass | capped store (`body_store.cap`) | haul, worker rot × `worker.body_return`, dungeon hauls | pit burn, mill | net /s and a bar |
| gold | gold | capped store (`gold.cap`, raised by the Market), floor 0 | market trade | upkeep, build costs; what the cap clips (`ledger().stores`) | net /s and a bar |
| bone | bone | capped store (`bone.cap`, raised by the Bone Mill), floor 0 | mill | build costs, some upkeep; what the cap clips | net /s and a bar |
| relics | count | capped stock (`relics.cap`, raised by the Reliquary) | dungeons, and from E4 step 9 the idle relic trickle: one per `economy.json` `relic_trickle.period_s` (12 h) of game time while some fort has been held `relic_trickle.hold_s` (24 h) without a break (Phase I P3, R-b; STATE-API §10 A18; until then: every fort at or below the highest tier ever flipped held, which never paid), read at each step's start; the paying seconds accrue, and are kept while it doesn't pay (the run's manager's rulings on step 9 (3)) | buildings, forge levels, phylactery, upgrades | count |
| blueprints | set | unlocks | dungeons only (first clear guaranteed) | unlock building types | set |
| essence | motes (int) | capped stock (`essence.cap`) | dungeons (carried out) | phylactery charges, simulacra | count |
| husks, remnants | items with uids | stock | dungeons | slab | count |
| living | people | stream, capped by housing (`living_cap`) | migrants, the inn | departures at low morale | net /s, cap |
| digest quality `q` | level, 1..`q_max` | derived (§2.2) | forge (a Forge foreman's through it), circles | none | number |
| big undead | named units | stock (`big_undead.cap`) | slab | dungeon and Vei deaths | names |
| backlog | mass | Vei's queue (RealmSim) | FLOOD, drain, chaff, raise | digestion, a lost Vei fight | tank level with net rate |

### 2.1 Conservation (the ledger)
Matter has one true source, the mint. Two more source keys keep the count honest: `opening`, the
mass on the board when the count began (a new game's forts, workers and bodies), and `debug`, the
net mass debug commands added or removed. The sinks (`ledger()` keys, STATE-API §4.7):
- `cleared` (`k_clear`) and `rot_loss` (1 − `body_return` of what rots);
- `burned` (pit burn) and `milled`;
- `rot_overflow` and `haul_overflow`: rot return and haul loads lost to the body cap;
- `vei_fight` (a lost Vei fight) and `dungeon` (the raid writeback's loss);
- `pool_overflow`: living marching back from above a fort's cap (§3.4) that land past Vei's pool
  cap. Her own take is limited to the pool's headroom, so only the march-back books here;
- `store_overflow`, always 0: the store caps (IDLE §6, E2b-2 T3.2) clip gold and bone, which are not
  mass. Their overflow is a currency tally beside the ledger, `ledger().stores` `{gold: {overflow},
  bone: {overflow}}` (§4.3), saved with it; the currency soak (`test_ledger`) closes on it.

Everything else is an internal transfer: Vei turning dead and undead into living, her shipping and
surges, the march-back into her pool, the valve, muster, haul pickups, the redirect and simulacra.
`held` is every pool of mass, summed live: the forts' living, undead and corpses, Vei's three
queues, bodies, workers × `worker.mass`, convoy loads and the WORK in flight to TownSim.
`scripts/sim/ledger.gd` books it (§1.3 step 7).

`GameState.ledger()` returns `{sources, sinks, held}`, and `Σheld + Σsinks == Σsources` holds within
1e-6 relative at every substep and at any `sim.substep_s` (misses measure about 1e-14). The soak
(§10) runs 1 h with random valves, Relish's moves, raids and flips, a lost Vei fight, musters, builds
and debug grants, and asserts it after every tick. It ends with two forced phases, a march-back into
a full pool and a full body store with every building unstaffed, and asserts that each books its
own overflow sink (`pool_overflow`, `rot_overflow`).

### 2.2 Digest quality `q`
`q = clamp(q0 + q_forge · forge_level + q_raise, 1, q_max)` (`realm.json` `q.*`).
- `q_raise = q_raise_max · max(0, (ema_score − 50) / 50)`, where `ema_score` is a mass-weighted EMA
  over every raised undead's circle score. It starts at 50, so `q_raise` starts at 0.
- **Its half-life is in mass raised, not in seconds** (`q.raise_half_mass`, which replaces
  `q.raise_ema_s`). It moves only when a raid result is applied: for each `raised` bucket
  `{score, mass}`, in apply order, `α = 1 − 0.5^(mass / q.raise_half_mass)` and
  `ema_score += α · (score − ema_score)`. The masses are the ones actually raised: the result's masses scaled by R'/R (R' = what the fort's dead could cover, STATE-API §8.3 step 3), so a result reporting 1000 mass at a fort with 10 dead moves the EMA as if about 10 were raised. Why: IDLE I2
  says what active play earned never decays while you're away, and a time-based EMA would decay
  with every idle hour. This one holds while no circles arrive.
- `forge_level` is TownSim's forge level (the forge job, §4.2). The formula's `Σ foreman_q` term is dropped
  (E3-3, the run's manager's ruling): a foreman adds no `q` of its own. A Forge foreman reaches `q` through
  `forge_level`, its smiths' work multiplied (§4.2), which reaches each level sooner. No save change. The save
  keeps `ema_score` as `readout.q_raise_ema`.
- Good circles visibly raise `q`, which makes every undead cost Vei more (vision review M7).

Names, to avoid confusion:
- `q` is Vei's digest cost;
- `circle_score` (0–100) and `stat_mult` (`0.5 + score/100`) belong to the dungeon;
- "carvers" is a front.

## 3. Macro: the realm

### 3.1 RealmSim (kept, with changes)
- Canonical continuous rates, scaled ×1/100, with the Necropolis extensions: EMPTY, `k_clear`, the
  pool cap and simulacra.
- The asymmetry is unchanged: your kills stay; garrison kills ship to Vei. Vei digests with `cheap`.
- `step(dt, inputs)` is pure on its inputs. The mint's split, `q`, Relish's position and each
  fort's siege share (`siege_block`, live from E3-3) arrive as inputs; RealmSim never reads them from its
  config or keeps its own Relish. The one exception inside a step: a sieged fort retaken in a part loses its
  block for the step's later parts (§3.4's retake).
- `directShare` is **removed** everywhere, including `readout()`. FLOOD replaces it. `P_relish` is 0
  (D2) and nothing reads it.
- Each fort's hold (`held`, `grace_s`, `zero_s`; §3.4) and the tithe-wave state are RealmSim state.
- **A step is split inside** at every held fort's grace end and at the moment a contested garrison
  sitting at 0 completes `hold.break_s` there (E2b-2 T3.1), so each part has every fort in one regime
  (in grace, contested or unheld) and both events land at their time at any dt. A split step's rates
  are its parts' time-weighted means; a step with neither event is one part, as before. A retake's
  `fort_retaken` carries its moment inside the step (GameState stamps `t` from it).
- **Within a step** (E2b T3.0: exact at any `dt`, so catch-up's long steps match live play):
  1. the tithe clock (§3.4: a wave's start, at its exact time inside the step);
  2. Vei's shipping (§3.4) and the surge, as **inflow rates over the step**. Shipping goes into each
     fort's room over the step: `cap` less the fort's load at the step's end without her living
     (`L + D` now less the corpses cleared and raised, plus what U's path leaves with the step's
     WAR and raises arriving, under the drain and the garrison's pull), less a surge there, never
     below 0 (§3.4). A fort WAR fills with no living takes only what its undead kill (§3.2). The surge takes all it wants, past the shipping share, the space and the cap. Both
     draw on her pool now plus what she can convert this step before her headroom (from her
     queues as they stand after FLOOD), surge first. A long step ships what the short ones would,
     and her pool never leaves [0, cap];
  3. WAR dispatch (§3.2), also a rate;
  4. FLOOD into the queue;
  5. **fort combat off each fort's path.** U is held at its mean over the step, so living's path
     `dL/dt = S − k_kill · Ū − max(0, L − cap) / τ` is linear at or below the cap and exponential
     above it, where the excess marches back to Vei (§3.4, τ = `tithe.march_back_s`). S is
     shipping plus the surge. If living reaches 0 at `t* = L0 / (k_kill · Ū − S)` it stays there,
     and from then on the kills equal the inflow. The kills are the inflow less ΔL less what
     marched back. U's
     own path, `dU/dt = W + raises − r_drain · U − k_destroy · L̄ / q`, is exact, including the
     moment U reaches 0. After that, every arriving undead is destroyed at once. **U leaving 0**
     (E2b-2 T3.3a): while U sits at 0 nothing kills the living, so their path is exact, and the
     moment the pull `k_destroy · L / q` falls back below U's inflow (WAR and the raises) along it is
     a closed form: above the cap the excess relaxes as `x(t) = c·τ + (x0 − c·τ) · e^(−t/τ)`, so it
     falls through `x* = q · inflow / k_destroy − cap` at `τ · ln((x0 − c·τ) / (x* − c·τ))`, which
     exists only when `c·τ < x* < x0` (at or under the cap, with U at 0, the living only rise). U is
     at 0 from the step's start when it starts there with the pull at or above its inflow, whatever
     the step's mean pull says, or from the moment the step's solve takes it there. A step that
     holds that moment is split there: the first piece holds U at 0, the second starts it from 0,
     both with the step's rates, and their masses add. Before, U's whole step took one regime from
     the step's mean pull, so the moment it left 0 landed anywhere inside a 10 s step (the zero
     clock below). Ū and L̄ come from
     alternating the two paths: a predictor from L0, then two corrections. The garrison's kills
     (`k_destroy · ∫L / q`, at most what the undead hold) and the drain come from U's path,
     `k_clear · ∫L` (at most the corpses) from living's. Kills at a redirect fort stay (§3.3). The
     redirect raises (Relish's, then the simulacra's) are a rate inside the step, bounded by the
     corpses. Mass is exact. Each fort records `t_living_out` and `t_undead_out`, the seconds into
     the step when living or undead reached 0 (0 when they started there), and `t_undead_back`,
     when U left 0 again; each is −1 when it did not happen. Step 8's zero clock reads the last two.
     The living that marched back land in her pool, after this step's shipping;
  6. Vei's conversion. What the march-back took past her pool's cap is lost (`pool_overflow`,
     §2.1). Her take is clamped to her pool's headroom, which **counts this step's shipping** and
     the march-back, so at her cap a long step converts what it ships less what marched back;
  7. the wave books what it delivered and ends after `surge_s`;
  8. the holds (§3.4): grace counts down; a contested garrison's zero clock runs while it sits at 0
     and restarts when it doesn't, counting only the time at 0 inside the step (`t_undead_out` to
     `t_undead_back`, or to the step's end); `hold.break_s` of it retakes the fort, at that moment;
  9. the next wave's warning, its target read from this step's dispatch and the holds as the step
     leaves them (§3.4).

### 3.2 The valve
- `mint = (P_base + P_per_pit · pits) · (1 + pit.bonus · feed)`, where
  `feed = min(1, burned / wanted)` and `wanted = pit.burn_per_s · pits`. Proportional, so nothing
  toggles. `P_base` and `P_per_pit` (6.0; it was `P_per_slab`) are `realm.json` keys, `pit.bonus` and
  `pit.burn_per_s` are `economy.json`'s. `pits` is the working pits now and `feed` the feed of the
  step before (TownSim's `rates.feed`), both dimensionless (§1.3 step 2).
- `work = mint · v.work` goes to TownSim as `work · dt` in the same step, `war = mint · v.war` goes to
  RealmSim dispatch, and `flood = mint · v.flood` plus TownSim's muster (`muster_mass / dt`) goes to
  `vei.undead_queue`. While the Muster stance acts (§4.5), the whole muster joins WAR instead.
  (E4 step 5, the run's manager's ruling A1, 2026-11-17: before it every muster joined WAR, so surplus
  WORK reached the forts 1:1 and from about day 1 the valve had two real settings, FLOOD and not-FLOOD;
  on the sessions day-3 state a WAR share of 0 still sent 54–84 mass/s of muster. Overflow to Vei's queue
  feeds the idle win condition and moves pacing least. `view_hud.split.muster_to` shows the route.)
- **Slew:** the valve vector moves toward the target by at most `valve.slew_per_s` of L1 distance per
  second, so the sum stays 1.
- **WAR dispatch:** WAR splits over the forts with living (living > 0, **or living arriving this
  step**: Vei's shipping or a surge) **and every held fort** by weight `1/(dist/100)^covFalloff`,
  with the tide (§3.3) multiplying its fort's weight. A fort that is both (a held fort a tithe surge
  filled with living) counts once.
- **A full fort with no living** (no living now, not held, not surged) takes at most the WAR that
  fills it by the step's end. Its undead drain while WAR arrives, so the rate is the one that brings
  U to `cap` less its corpses at the step's end: `D` plus what Vei ships in (killed on arrival, it
  ends as corpses) less what Relish and the simulacra raise there into U, as far as those corpses
  cover their rate. The WAR it can't take is split over the other targets by weight, and goes to
  `vei.undead_queue` (counted as fall-through) when every target is full. E2b T3.0 added this:
  such a fort used to flicker in and out of the targets as its drain opened room, and how far it
  flickered depended on the step. This rule is the continuous version of that flicker. Living
  arriving counts for the same reason: Vei's living killed on arrival leaves a fort at 0 living at
  the end of every step.
  - **The raises count** (E2b T4.C). They used to be left out, so at a fort where Relish raises
    the step ended short of the cap by `ρ · (dt − (1 − e^(−r_drain · dt)) / r_drain)` at a raise
    rate ρ, and that WAR went to other forts. With Relish at pre_vei's Ashgate (full, no living,
    raising the 0.21/s Vei ships in) it held 78.95 of 80 at 15 s and 80.00 at 0.5 s (now 80.00
    at both, with the same WAR); at her full 4/s it is 20 per step at 15 s.
  - **Vei ships it only what its undead kill** while WAR fills it (it takes its whole fill), and
    WAR fills the room the rest would have taken. The rest stays in her pool. More would leave a
    sliver of living at the step's end, and a fort with living takes its whole weight's share of
    WAR, with no limit, for the whole next step. That is the continuous-time outcome of these
    rules: the moment living appear WAR pours in, the room closes and they die, so the fort stays
    full with 0 living, its kills taking her living. A fort WAR doesn't fill (too little WAR)
    still takes her living into its room, so with no WAR such a fort fills with living again.
    Whether WAR fills it is judged with her give cut to the kills: the cut raises its fill, WAR is
    split again, and a fort whose share then falls short of its fill takes her living into the
    room its WAR leaves and gathers living, as one with too little WAR does. That can be this fort
    or one whose share fell. Over 12 h from the three starts at 0.5, 10 and 15 s it happened once
    (pre_vei at 15 s, a fort whose share fell), and that fort ended the step with no living.
    E2b T4.C measured why: in pre_vei with no haulers every fort fills with corpses within 20 min.
    Vei's shipping into the drain's room (`r_drain · U`) then outran the few undead's kills
    (`k_kill · U`, and `r_drain` > `k_kill`), so a fort with 0.04 living took all 32.7/s of WAR
    for a step, and then another fort did. Each burst grew with dt, and the forts' undead differed
    by 56% between 0.25 s and 0.5 s over 2 h. Now they differ by 0.08%.
- **Staging:** a held fort always pulls WAR as staging, at its weight, alongside the forts with
  living (§3.4). There the undead drain to Vei, so a held fort becomes a forward pump. WAR staging is
  split across the held forts, so holding more forts thins every garrison (IDLE §3).
- **WAR with no target at all** (no living anywhere and nothing held): it falls through to
  `vei.undead_queue` and counts in the inflow like FLOOD. RealmSim records which of the three
  routes it took (`war_route`: `forts` when some target has living, `staged` when only held forts
  took it, `vei`) and the fall-through rate, for the lanes.
- **The optimum split must move** over the arc and with Relish's position. Diminishing returns make
  sure of it:
  - WORK beyond filled slots plus `worker.idle_cap` is wasted for the town: it musters to Vei's queue
    with the FLOOD (§3.2, ruling A1), so it feeds the backlog but not the forts;
  - FLOOD at low `q` is cheap for Vei;
  - WAR into strong garrisons arms her.

  BALANCE's static-schedule ablation checks this.

### 3.3 Relish's location
GameState owns `relish = {state, at, target, pos, heading, dead_s_left}`, where state is one of
`home`, `travelling`, `at_fort`, `in_dungeon`, `in_boss` or `dead`.
- **Travel:**
  - she moves along the straight line at `relish.travel_speed`, tracking `pos`;
  - a retarget mid-travel starts from where she is;
  - `cmd_cancel_travel` turns her back.
- **Tide** (at a fort, including in its dungeon): that fort's WAR dispatch weight × `relish.tide_bias`.
- **Redirect** (at a fort, not in its dungeon):
  - garrison kills at that fort stay there as corpses instead of shipping to Vei;
  - she raises corpses there at `relish.raise_rate` into undead, which enter the fort's undead pool
    and then drain to Vei (costing her `q` each).
- **At home:**
  - workers rot `relish.home_rot_mult` slower;
  - the slab works;
  - stances get one extra stance slot (`relish.home_stance_bonus`).
- **Dead** (from E3-2, for the death's respawn time, §7): no tide, redirect, slab or bonus (no home rot and no
  home stance slot; Vigil's condition holds). **Everything else stays live:** valve, building, stances (vision
  review S3).
- **Her fort retaken** (IDLE I5, E2b-2 T3.3c): when the fort she stands at (`at_fort`) is retaken, she
  walks home to Covington at `relish.travel_speed`, from the retake's moment inside the step
  (`relish_returned`, and `view_relish().returned`). Live play and catch-up alike, so she never waits at a
  fort Vei holds while you're away. She must stand there at the retake: one she reaches after it, inside
  the same step, she stays at (a live substep sees the fort fall before she arrives, and she stands at a
  Vei fort as at any). In its dungeon she stays: the run goes on, and when it ends she stands at the fort.

### 3.4 Flips and tithe waves
**In this section "her odds" means her strain, `backlog / (backlog + K)`** (`RealmSim.strain`, `view_vei.strain`).
Her tithe period, reship and one-wave need read it. Since E4 step 9 the odds a player reads are the win odds of §3.5,
which nothing here reads.

**Flip.** On `warden_beaten`:
- all the fort's living become dead, applied as a clamped delta;
- the fort is **held**: a grace of `flip.hold_s · (1 + flip.tier_mult · tier)` (`fort_flipped.hold_s`
  is that grace), then a contest between two pools (IDLE.md §3; E2b-2 T3.1 replaced E2a's timer,
  which retook the fort when `held_s` ran out, cause `expired`).

**Vei's pressure at held forts** (E4 step 5, rulings B1 and B1 (ii)): her living's pull on a held fort's
garrison (grace or contested) is `k_destroy / q × hold_mult` (RealmSim `_k_dq`), with `hold_mult` =
max(1, (settled mint ÷ `hold.mint_ref`)^`hold.mint_alpha`) (GameState.hold_mult). The settled mint is
`P_base + P_per_pit · pits` (working pits; no feed, no foremen), so it is a step function of the buildings and
reads the same open and closed; `mint_ref` 8.0 is a new game's one pit, so a new game reads ×1 and the table
below is unchanged there. α 0.85 (the ruled fallback's ceiling; at 0.7 the sessions day-3 state, settled
mint 92, m 5.5, lost no fort in 24 h away, and the default valve's 0.60 WAR share keeps every margin
positive). Sub-linear: WAR grows with the mint, the need with mint^α, so a growing necropolis finds holding
somewhat easier, never trivial. Her mass, pool, fronts and boss seed don't read it. Every pull site and
readout reads it (fort_step, `_load`, `_leave_at`, `dead_rates`, `garrison_rate_of`, `_wave_breaks`,
`need_of` and the train's scratch forts). GameState sets it at each core step's start (its input), at its
end and on a load (`_sync_hold_mult`). Not saved.

**The hold's state** (RealmSim, saved): `held`, `grace_s` (grace left) and `zero_s` (seconds the
garrison has sat at 0 since it last didn't). A save from before E2b-2 carries `held_s` instead: a
fort with `held_s > 0` loads held, with `grace_s = held_s` and `zero_s = 0`.

**Grace.** While `grace_s > 0`, Vei ships nothing there and no tithe wave targets it. A warning
already naming the fort (it was warned, then flipped; or a save holds one) is dropped and made
again, for another target, at that step's end (or at once when the wave is due within the step); a
wave already running there delivers nothing while the grace lasts. midgame_2flips loads with such a
warning on Ashgate (374.5 s of grace, the wave due in 150 s): its first step warns Greywall instead. The
re-target is visible at once (E2b-2 T3.4b, `test_wave_train`'s re-target case): the moment the fort enters
grace `view_vei().tithe` has no target and `view_fort().tithe` no longer names it; the next step's warning
names the new target in both views, and a new `tithe_warning` (the next `wave_id`) names it.

**The contest** (after grace):
- **your garrison** is your undead there (`undead`), fed by WAR staging (§3.2): WAR is split across
  the held forts, so more forts thin every garrison;
- **her counter-garrison** is her living there. She **reships** at `hold.reship_share` ×
  (1 + `tithe.backlog_scale` · odds) of the share she ships any fort: `S_vei · cap_i / Σcap` per
  second (the share rule below), with the odds read at the step's start. It is drawn from her pool
  with the rest of her shipping, pro rata when the pool can't cover every give, but, like the
  surge, it is **not cut to the fort's room**: a fort full of corpses, or a garrison above its cap,
  would otherwise shut her out for good, and an unsupplied fort would never fall. With
  `reship_share` 0.5 and `backlog_scale` 0.5 the reship is 0.5× her share at odds 0 and 0.75× at
  odds 1 (Ashgate 0.103 to 0.154 mass/s, Whitecross 0.669 to 1.003);
- tithe waves target it and surge into her living there, as at any fort (counters below);
- the usual fort combat (§3.1 step 5) runs the exchange: your kills stay as corpses to haul, her
  kills ship to Vei.

**Retake.** The fort is retaken when the garrison has sat at 0 for `hold.break_s`
(`fort_retaken {fort_id, cause: "broken"}`). "At 0" is fort_step's clamped regime for U: the
garrison's pull meets or exceeds U's inflow, so U sits at 0 (its path's `t_undead_out` onward, to
`t_undead_back` when it leaves inside the step), or U is 0 with nothing arriving and nothing pulling
(no WAR and no living there yet). It is not a mass threshold. Any time with U > 0 restarts the clock.
- **The clock counts only the time at 0** (E2b-2 T3.3a): a step in which U leaves 0 counts up to
  that moment (§3.1 step 5 solves it), so a step of any length gives the zero time fine steps give.
  Before, a step whose U left 0 inside it took the whole step as one regime, at 0 or not, from its
  mean pull. midgame_2flips' Ashgate is a knife-edge: with no input each wave pins its garrison
  for 101.8 to 116.1 s of the 120 s `break_s` at 0.5 s, so its margin is 3.9 s. At
  10 s the per-wave figure was up to 5 s off 0.5 s's, either way (106.4 s against 101.6 s at the
  first wave), one wave crossed 120 s and the fort fell at 15 537 s; at 0.5 s it stood at 12 h. Now the first ten waves at 10 s pin it for 102.08, 106.76,
  111.32, 111.57, 111.76, 111.94, 112.11, 112.26, 112.41 and 112.55 s (at 0.5 s 101.76, 106.83,
  111.34, 111.55, 111.70, 111.85, 111.99, 112.12, 112.24 and 112.35 s), its longest 116.8 s (116.1),
  and it holds all 178 waves at both. What is left is when U reaches 0 inside the wave (its step's
  mean pull, as before) and the waves' own times: at 10 s they start 0.6 s late at the first and
  1.3 s by the tenth (each period reads the odds when it is scheduled).
- The drain alone never takes U exactly to 0, so a
held fort with no WAR keeps a dwindling garrison until her reship lands; from then her living's pull
pins U at 0. A fort that reaches its grace end with U = 0 and nothing coming falls exactly
`break_s` later ("Needs WAR too"). The retake lands at its time inside the step (§3.1). On a retake
(IDLE I6):
- a siege big undead there (GameState's place `fort:<id>`) returns to the crypt, with
  `big_undead_returned {uid, fort_id}` right after the `fort_retaken`. Its block is gone from that moment (E3-3):
  RealmSim splits the step at the break (§3.1) and runs the parts after it without that fort's `siege_block`
  (`RealmSim._unsieged`), and the next step's inputs have none there. A catch-up doesn't clip at a retake, so this
  holds inside its long steps too: a 10 s step with the retake 2 s in delivers a wave there as a 2 s step with the
  block and an 8 s step without it (`test_big_undead`);
- every simulacrum planted there (`cmd_deploy_simulacrum`, live from E3-4) is lost with its charges: RealmSim drops it
  at the retake's moment (`RealmSim._retaken`), so the step's parts after it raise nothing for it, live and inside a
  catch-up's long step alike (`test_crafting`);
- Relish, if she stands there, walks home (§3.3, `relish_returned` after the `big_undead_returned`; E2b-2
  T3.3c);
- `clears_since_retaken` resets to 0 (§5.3).

**The hold rule, both ways** (vision: "Needs WAR too"). Measured on RealmSim at 0.5 s (and 10 s) with
`digest_q` 1.2: the fort contested (grace 0) with no living or corpses, every other fort full of
corpses (all the WAR stages there), Vei's pool full, and one full wave at once.
- **Without waves**, a garrison holds if her reship dies on landing: the garrison its WAR `W`
  sustains with no living there, `W / r_drain`, kills `k_kill · W / r_drain` ≥ her reship `S`, so
  `W ≥ W_c = r_drain · S / k_kill` (3.33 S). Ashgate (cap 80, S 0.103 at odds 0): W_c 0.343 mass/s;
  Greywall (90): 0.386; Vespers (160): 0.686; Whitecross (520): 2.23. Below it her living gather,
  their pull grows and the garrison is pinned at 0, unless her living can't pile high enough: their
  most, with no kills, is `cap + τ · S` (the march-back's level), whose pull `k_d · (cap + τ · S) / q`
  (Ashgate 0.43 at q 1.2) the WAR may still beat. That stalemate (her living fill the fort, a small
  garrison stands) binds first once `q` is above about 1.5 at odds 0, or 1.2 at odds 0.6.
- **(a) A full-cap garrison with no staged WAR loses to a full wave, with or without Relish there.**
  W = 0, U = cap: the drain (τ = 1 / r_drain = 17 s) and the wave's pull take U to 0 at `t_z` into
  the wave, and the fort falls `break_s` later. With no Relish, U = U0 · e^(−r·t) less the pull's
  integral `(k_d · c / q) · (e^(r·t)(t/r − 1/r²) + 1/r²) · e^(−r·t)` (c = 24 living/s arriving)
  reaches 0 at t_z ≈ 23 s at Ashgate; measured 24.0 s (Greywall 25.0, Vespers 29.5, Whitecross 41.5),
  so the retake comes at t_z + 120: 143.6, 144.5, 149.5 and 161.3 s after the wave starts. With
  Relish there (her raise recycles the garrison's losses, and the wave is halved) U reaches 0 later:
  37.0, 38.5, 46.0 and 75.5 s, retaken at 156.6, 158.0, 165.8 and 195.1 s. A siege: 32.0 to 55.5 s,
  retaken at 151.5 to 175.4 s. At 10 s the retakes land within 1.2 s of these. So the fort falls by
  the wave plus `break_s` (160 s) wherever U reaches 0 inside the wave: Ashgate and Greywall in every
  mode, Vespers without Relish. At Vespers with Relish and at Whitecross U outlasts the wave (by 1.5
  to 35.5 s), and the fort falls at `t_z + break_s`.
- **(b) Near the threshold Relish or a siege flips the outcome.** The garrison settled at `W /
  r_drain` before the wave. The smallest W that holds a full wave (measured by bisection, 0.5 s; 10 s
  in brackets; re-measured at E2b-2 T3.3a, whose exact leave from 0 (§3.1 step 5) moved the 0.5 s
  column by up to 0.002 and brought the 10 s column within 0.003 of it, from up to 0.023 above; only
  Whitecross with Relish there, where U outlasts the wave, still differs, as before):

  | fort | W_c (no waves) | no counter | Relish there (halved, her raise) | Relish's ×0.5 only (her tide, in its dungeon) | siege (0.6 blocked) |
  |---|---|---|---|---|---|
  | Ashgate (80) | 0.343 | 1.033 (1.033) | 0.547 (0.547) | 0.691 (0.693) | 0.624 (0.625) |
  | Greywall (90) | 0.386 | 1.076 (1.077) | 0.583 (0.582) | 0.736 (0.737) | 0.669 (0.669) |
  | Vespers (160) | 0.686 | 1.383 (1.386) | 0.834 (0.837) | 1.051 (1.051) | 0.988 (0.988) |
  | Whitecross (520) | 2.229 | 3.028 (3.026) | 2.242 (2.219) | 2.802 (2.802) | 2.803 (2.803) |

  Before T3.3a: Ashgate 1.035 (1.040), 0.547 (0.547), 0.692 (0.703), 0.625 (0.636); Greywall 1.078
  (1.086), 0.583 (0.581), 0.736 (0.749), 0.670 (0.682); Vespers 1.384 (1.407), 0.834 (0.838), 1.052
  (1.056), 0.988 (0.995); Whitecross 3.029 (3.029), 2.242 (2.219), 2.802 (2.802), 2.803 (2.803).

  So the band where a full wave breaks the fort without Relish and it holds with her is [0.547,
  1.033) mass/s of WAR at Ashgate, [0.583, 1.076) at Greywall, [0.834, 1.383) at Vespers and
  [2.242, 3.028) at Whitecross; a siege's band starts at its column. Every edge sits above W_c: a
  fort that only just holds without waves is broken by a full wave. At Ashgate the band runs from 1.6
  to 3.0 × W_c; at Whitecross from 1.0 to 1.36 × W_c.
- `hold.reship_share` 0.5 and `hold.break_s` 120 satisfy both, so they stay at their starting values.
  A longer `break_s` can only lower the wave columns (the garrison must sit at 0 longer); a larger
  `reship_share` raises W_c in proportion.

**While held:**
- **In grace, Vei's shipping share to that fort is lost; contested, it gets only her reship**
  (above), because her shipping is per-fort capacity-limited, so a held fort lowers her effective
  `S_vei`. The share rule: fort `i` receives at most
  `S_vei · cap_i / Σcap` per second, into its room over the step and from her pool
  (plus what she converts that step). `Σcap` runs over every fort,
  held ones included, so a held fort's share is lost, not redistributed. The unused part of a full
  fort's share is lost the same way. When her pool can't cover every share, each is scaled down
  pro rata.
  - **The room over the step** is `cap` less the fort's load at the step's end without her
    living, less a surge arriving there, never below 0. The load is `L + D` now (kills only move
    living to corpses), plus what U's own path (§3.1 step 5) leaves at the step's end with this
    step's WAR and raises arriving, under the drain and the garrison's pull `k_destroy · L̄ / q`,
    less the corpses that leave: the clearing `k_clear · L̄ · dt` and the raises (bounded by the
    corpses now), together at most the corpses there (those now, the kills of the living's path
    and, at a redirect fort, what the garrison destroys). The undead the garrison destroys leave
    for Vei, or stay as corpses at a redirect fort.
  - `L̄` is the living's mean over the step with nothing shipped in, solved as fort combat solves
    it (a predictor and two corrections). Her living only add to the pull and to the clearing, so
    the real load is at most this one.
  - WAR's dispatch reads the living arriving (§3.2), so shipping is planned on the load before
    WAR (the pull read from the living now), then each share is cut to the room the step's WAR
    leaves. What that cuts stays in her pool. A fort with no living already takes only the WAR
    that leaves room for its shipping.
  - So shipping never takes a fort past its cap, at any dt (tested to 60 s with no clearing); WAR
    and the surge can. A fort with living above its cap has no room (the march-back never takes
    them below it), so the load leaves the march-back out. At a redirect fort the bound is loose
    by the drain the extra pull's kills skip (not seen in the tests).
  - History (E2b T3.0s): the room used to be `cap − L − U · e^(−r_drain · dt) − D`, which left out
    WAR, the raises and the surge (Greywall reached 90.3 of 90 in play). A room with WAR but not
    the pull under-shipped long steps (fresh's Vei stocks 3% off at 15 s over 1 h).
    Until E2b T4.C the clearing was left out ("it only frees room"), so a fort whose room came
    from its own clearing took one step's clearing less at every step. At 15 s that cut Ashgate's
    shipping from 0.206 to 0.038/s for the step after it came back under its cap
    (midgame_2flips, t 510 s). Its living fell 2.6 below the 0.125 s run's, and its slow decline
    (fewer living, a weaker pull, more undead, more kills) grew that into a fall about 10 min
    early: midgame's corpses were 217% off at 15 s over 12 h, and 41% with the clearing counted.
- the fort pulls WAR as staging (§3.2);
- haulers there get `flip.haul_mult`;
- it injects necrosis.

**Tithe waves** (Vei's counter-current; RealmSim state, deterministic, all countdowns):
- **Clock:** it starts at the game's **first flip**; no wave comes before any fort has been
  flipped. The first wave comes one interval after that flip, and each wave schedules the next one
  interval after its own start. The interval is `tithe.period_s` × (1 − `tithe.backlog_scale` ·
  odds), with the odds read when it is scheduled. She fights back harder as the queue clogs.
- **Warning:** `tithe.warning_s` before the wave, the target is chosen and announced
  (`tithe_warning` event), with the target shown on the map and on the fort's ring. The target
  stays fixed for that wave, whatever changes before it starts. It is made at the end of the step
  that reaches `warning_s`, so it can come up to one step late, never early, and its `eta_s` is the
  exact time left: the wave's own time doesn't depend on the step.
- **Targets** (E4 step 5, ruling B1 (ii)): contested held forts first (past their grace), the one with the
  **lowest margin**: its settled support (the step's `target_war`, GameState's `_train_war`: the valve's
  target at the pits' trough feed, split as the last dispatch splits WAR, so the pick doesn't follow the
  convoy's sawtooth) less its **one-wave need** (`RealmSim.need_of`: the least WAR at which it holds with
  no waves and one full wave from its settled garrison, support / `r_drain`, doesn't break it, with
  Relish's raise and tide and the siege there; a bisection to `hold.need_tol` in at most
  `hold.need_iters` halvings, her reship at her odds snapped down to `hold.need_odds_step`, memoised).
  Margins within `hold.margin_eps` tie, and ties go to world order. Else the fort receiving the most WAR
  at that moment; with no WAR anywhere, the first fort not in grace. A fort in grace is never a target
  (above). Before B1 (ii) the wave went to the most undead, so the strongest garrison drew every wave
  and shielded the weak (at the sessions day-3 state no fort fell at any pressure up to ×16). The need
  is about `k_dq` · (cap + 120) there, so it scales with `hold_mult` (§3.4). The telegraph: the fort the
  rule would pick now and the time to the next wave are in the views before the warning fixes it
  (STATE-API §5.4 `tithe.next_target`, §5.5 `hold`).
- **The wave:** a surge of `tithe.surge_mult` × `S_vei` living/s from her pool into the target for
  `tithe.surge_s` (`tithe_wave` event when it starts). The pool bounds it. It ignores the per-fort
  shipping share, the fort's space and its cap. Her normal shipping comes after it in the step and
  still respects the room, so a fort the surge took past its cap gets none.
  - **Its time is exact inside a step** (E2b T3.0m). The step that holds the wave's start surges
    only for the part after it, and the step that holds its end only up to it, as a rate over the
    step. A step that ends exactly at the start delivers none of it (the event comes in that step,
    stamped at the start), and a step holding the whole wave delivers all of it and ends it. So a
    wave delivers `surge_mult · S_vei · surge_s` at any dt, clipped or not. Before, the step that
    crossed the start surged for all of it, so a wave began up to one step early (a whole catch-up
    step when the harness clipped at the start).
- **The march-back** (E2b T3.0m, which replaces T3.0s's bound `cap · (1 + tithe.overfill)`): at
  every fort, living above the fort's cap march back to Vei's pool at `(L − cap) / τ`, with
  τ = `tithe.march_back_s`.
  - **In the step** (§3.1 step 5), living follow `dL/dt = c − max(0, L − cap) / τ` with
    `c = S − k_kill · Ū`. At or below the cap the path is linear: it rises through the cap at
    `(cap − L) / c` or reaches 0 at `L / −c`. Above it the excess `x = L − cap` relaxes toward
    `c · τ` as `x(t) = c·τ + (x0 − c·τ) · e^(−t/τ)`, so it settles at `cap + τ · c` when `c > 0`,
    and when `c < 0` it falls back to the cap at `τ · ln(1 + x0 / (−c · τ))`. `∫L dt` and the
    marched mass `∫x dt / τ` are closed forms. The kills are the rest (inflow − ΔL − marched), so
    mass is exact, and the path is exact at any dt.
  - **Where the mass goes:** the marched living land in her pool after the step's shipping and
    before her conversion. Her conversion then fills only the headroom they leave, and what lands
    above her pool's cap is lost to `pool_overflow` (§2.1). At a full pool the march-back first
    replaces what she would have converted to cover the step's shipping, and only the rest
    overflows. Landing after shipping means a long step can't ship or surge this step's march-back
    before the next step. That matters only when her pool runs dry during a wave, which re-surges it
    one step late. Measured over a wave into Ashgate and 7τ of its tail (`realm_sim`), her pool,
    overflow and conversion at 5 s and 15 s agree with 0.5 s within 0.27% and 0.84% of the marched
    mass with her pool full, and within 0.95% and 1.48% with conversion at 5/s (the wave empties
    her pool). Her pool ends full at every dt.
  - **Why** (E2b T3.0s): living leave a fort only by being killed (`k_kill · U`), and the target
    rule keeps picking the fort with the most WAR. 12 h with no input from midgame_2flips put about
    75 000 living into Greywall (cap 90), an unbounded stock that fed Vei as a WAR grinder. T3.0s
    bounded the surge at `cap · (1 + 2.0)` with a room fixed at the step's start. Corpses cleared
    during a wave's last step were never refilled, so the bound lagged at long dt (midgame's Vei
    and Covington stocks 2.6% off at 15 s over 1 h). Living above the cap stayed forever at a fort
    with no undead (Ashgate 239 after 12 h), and a garrison of `1.5 · cap` outlasted a full wave.
    The march-back has none of these: it is exact inside the step, it empties the excess, and the
    surge delivers all of itself again.
  - **The value, 60 s.** A full wave is `W = surge_mult · S_vei · surge_s = 960` mass at
    `c = 24` living/s for `T = 40` s.
    - **Peak.** Into a fort at its cap with no kills, a wave leaves `x(T) = c·τ · (1 − e^(−T/τ))`
      above the cap: 607 at τ = 40, 701 at 60 and 816 at 120. The excess then decays as
      `e^(−t/τ)`, so 7τ later `e^(−7) < 1e-3` of it is left.
    - **Waves don't stack past one wave's mass** if the cycle's peak,
      `c·τ · (1 − e^(−T/τ)) / (1 − e^(−P/τ))`, stays below W. P is the period: 420 s at odds 0,
      down to 210 s at odds 1. At P = 210 the peak is 722 at τ = 60, 858 at 90 and 988 at 120, so
      `cap + W` bounds every fort's living only for τ up to about 110. At τ = 60 the excess left
      when the next wave starts is `e^(−380/60) = 0.2%` at odds 0 and `e^(−170/60) = 6%` at P = 210.
    - **The hold** is the contest's now (the hold rule above): the wave's living add to her
      counter-garrison and their pull pins your garrison at 0 or doesn't. The march-back sets how
      fast that pull fades after the wave, so it moves the band's edges with `break_s`. (E2a
      compared the living a wave delivered, 960 or 480 with Relish there, with your undead at its
      end, so a full-cap garrison lost everywhere but Whitecross with Relish; `realm_sim`'s
      `_march_holds` measured that, and `_hold_rule` replaces it.)
    - So τ = 60 (1.5 · `surge_s`): the excess outlasts the wave (it peaks at 73% of W), it is
      nearly gone before the next wave, and `cap + W` bounds the living at the shortest period.
      `tests/slow/convergence.gd` asserts that bound over 12 h, and that no fort ends above
      `cap · 1.01` unless a wave ran there within 7τ.
- **Counters** (applied every step of the wave; the event reports them at its start):
  - Relish standing there (at the fort or in its dungeon) multiplies the surge by `tithe.relish_mult` (0.5: halves it);
  - a big undead placed there as siege cancels `tithe.siege_block` of it (live from E3-3). RealmSim
    takes the cancelled fraction per fort as its `siege_block` input: GameState gives `tithe.siege_block` at each
    fort with at least one big undead placed `fort:<id>` (`_siege_blocks`), flat, one per fort. It is the siege's
    only effect: it adds no kill power (not built; E4 only if the hold band needs it).
  - **The margin chip credits the siege** (from E4; `GameState._forecast_siege` is the step's `_siege_blocks`).
    `view_fort`'s `margin`, `fall_s` and wave train, and `view_projection`'s margins, read each fort's block as
    RealmSim's step applies it. E3-3 credited none (the run's manager's ruling: a new feature must never make the
    chip say "safe" at a fort that falls), because the wave train's support was then the WAR at the sampling
    instant, a landed load's burst held over the whole forecast, and credited, a block let that error turn safe
    where the sim breaks the fort. One substep after midgame_2flips' load the train read Ashgate's WAR at 1.427 and
    Old Sluice's at 0.970 against the 1.119 and 0.761 they settle at a minute later; with the valve's WAR cut to
    0.05 the sieged Ashgate read safe and fell at 988 s (`margin_truth`). On the settled support (§3.5, E4 must-fix
    #1) that case reads thin, credited (`test_big_undead`'s `_siege_chip_war05`). Its revert proof, never
    committed: the instant support with the block credited reads it safe again, and Old Sluice safe with Relish
    travelling to Greywall (`test_wave_train`'s `_arrival`).

  Defending a flip is a real decision.
- **No wave ends a hold by itself** (E2b-2 T3.1 removed E2a's `tithe_wave` cause): it surges into the
  counter-garrison, and the contest decides (the retake above).
- **A retake** resets the fort's `clears_since_retaken` to 0 and leaves its loot yield as it was (§5.3).
- **After the win** (P3b, api-request #21; STATE-API §10 A19): once Vei is beaten (`won`), `RealmSim.won` (synced by
  `GameState._sync_won` at each core step's start, on a load, at the win in `StateRuns.writeback_boss`, on debug's
  `won` and on a new game; `set_won` idles the tithe at once and `start_tithe` does nothing while it is set) turns
  her off. **No tithe** (no warning, wave or surge; catch-up clips at no tithe event), **no shipping, reship or
  surge** (living vei->fort lanes 0), **no dead fort->vei** (the undead her living destroy stay at the fort as
  corpses: `fort_step`'s keep path, raising none), **no retake** (a held fort's zero clock doesn't run; grace and
  `held_for_s` still count), and no forecast: `train_probe` sees no wave and every fort's `hold` reads zeros (need 0,
  margin 0, `fall_s` −1, `margin_cause` `""`). FLOOD's share and the muster go to WAR (`GameState._split_of` with
  `war_share`/`flood_share`, §3.2's split), so `split.flood` is 0 and `muster_to` `"war"`. Still running: the player's
  WAR, the garrisons (their drain into her queue too), the hold timers, the town.

### 3.5 Readouts
- **Differential:** `diff = inflow − digestion` each substep, where inflow is fort drain + FLOOD +
  WAR that fell through to Vei (§3.2). Relish's and the simulacra's raises reach her through fort
  drain; lumps (dungeon chaff, grants) are not in it. Digestion is the undead she actually took
  from her queue, per second, so `diff` is the backlog's net rate and an empty queue reads 0.
  `directShare` is gone.
- **Sustained sign:** the EMA of `diff`, `α = 1 − e^(−dt / readout.ema_s)` (120 s). It shows ▲
  when the EMA is above +ε, ▼ when below −ε, otherwise "holding". ε is `readout.sign_eps`, a small
  mass/s (0.05). One substep moves the EMA by about `diff / 240`, so a single substep flips the
  sign only past about 12 mass/s.
- **Drain time:** `backlog / −EMA` when the EMA < 0, else "holding". Never INF in state.
- **Odds** (the win odds; E4 step 9, the run's manager's ruling of 2026-11-17 13:44, option B):
  `odds.time_weight · t / (t + odds.time_s) + (1 − time_weight) · min(odds.backlog_cap, strain + credit)` (P3b: the
  raid credit, below; 0 before it), with `t` the
  game's age (sim seconds since the new game) and **strain** `backlog / (backlog + K)`. Mostly time-based, with the
  raid (backlog) part capped, so a player who is always present and raids hard reaches them sooner, but not by as much
  as the backlog alone would give. These are the odds every view shows, the boss seed carries and Vei-ready reads.
  **Nothing in the fight reads them:** her tithe period, her reship into held forts and the one-wave need read the
  strain (§3.4), so she still fights back harder as the queue clogs, not as the game ages. The odds a player reads
  therefore don't drive her pressure directly; the strain is in `view_vei.strain`, never shown as odds. Until E4
  step 9 the odds were the strain (`time_weight` 0 with `backlog_cap` 1 gives them back bit for bit).
- **Readiness and the first-attempt odds** (Phase I P3, the run's manager's odds split; STATE-API §10 A16): the win
  odds above are now the **readiness** (`view_vei.readiness`). The boss seed carries it, Vei-ready reads it (≥ 0.6)
  and BALANCE's pacing rows measure it. The **odds** a player reads are the first-attempt estimate on it and the
  backups: `readiness / (1 + exp(−(backups − odds.backups_mid) / odds.backups_scale))`, with backups = min(phylactery
  charges, `phylactery.max_per_dungeon`) + clones ready. Since P1's pool-scaled break the backups decide a first
  attempt (§6), so each clone raises the odds shown, and the readiness bounds what backups can buy. The fit is to the
  faithful grade at Vei-ready (BALANCE §5); `backups_mid` −1e9 gives the readiness back bit for bit.
  **P3b, the shown odds** (V-I2 (b)): `first_odds = min(odds.first_cap, odds.first_gain × readiness) / (1 +
  exp(−(backups − backups_mid) / backups_scale))`, `first_gain` 1.41, `first_cap` 0.95, `backups_mid` 6.72,
  `backups_scale` 1.62, fit to P3's faithful grade at readiness 0.6053 with its 1+10 point added (reads 0.01, 0.08,
  0.22, 0.46, 0.80 against 0.00, 0.05, 0.25, 0.45, 0.80 at 0+0, 1+2, 1+4, 1+6, 1+10; P3's form read 0.60 at 1+10).
  The ceiling's dependence on the readiness is a choice (all grade points sit at one readiness): proportional as
  before, up to `first_cap`. `first_gain` 1 with `first_cap` 1 is P3's form bit for bit
  (`GameState.first_odds_of(readiness, backups, mid, scale, gain := 1.0, cap := 1.0)`). The deciders (Vei-ready, the
  boss seed, the tithe, reship, need) keep reading the readiness or the strain.
- **The raid credit** (P3b, V-I2 (a); STATE-API §5.1's `raid_credit`): the readiness is `time_weight · age / (age +
  time_s) + (1 − time_weight) · min(backlog_cap, strain + credit)`, `credit = GameState.raid_credit() =
  min(odds.raid_credit_cap, odds.raid_credit × stats.raids)` (`stats.raids`: every raid result applied; saved), sized
  in BALANCE §5's P3b rows. Only the readiness reads it: `RealmSim.strain()` and what reads it (the tithe period,
  reship, need) don't move. `raid_credit` 0 is the readiness above bit for bit (`ValveLogic.odds_at` takes it as
  `credit`).
- The EMA is saved (`readout.diff_ema`); the raw `diff` is not.
- Vei's panel and the confrontation dialog show all three.
- `RealmSim.readout()` stays for its old readers with the same keys. Its `capacity` is the most
  undead she could have taken last step: her rate at `q` after the dead she took first, and her
  pool's headroom, so a nearly full pool limits it too.

**The held forts' readouts** (E2b-2 T3.1, api-requests #7 and #13; `RealmSim.readout_of`, read by
`view_fort`, `view_realm().forts[]`, `view_hud.war_supports` and `view_projection`). For a held fort
with `W` mass/s of WAR at the valve (the last dispatch's split of the valve's WAR: its weights,
Relish's tide and the full forts' limits as they stand), her reship `S` (above, at the odds now) and
`q` now:
- **The support** `A = W + ρ`, where `ρ = min(relish.raise_rate, S)` while Relish redirects there:
  at a supported fort her reship, killed on landing, is all the corpses there are to raise.
- **`garrison_rate = A − min(r_drain · S / k_kill, k_destroy · (cap + τ · S) / q)`**, mass/s. Both
  terms are fort_step's: the first is the drain (`r_drain · U`) of the smallest garrison that kills her
  reship as it lands (`k_kill · U = S`, with no living there); the second is the pull
  (`k_destroy · L / q`) of her living at their most with no garrison (`L = cap + τ · S`, the
  march-back's level). The fort holds without waves exactly when the support covers one of them
  (≥ 0): it either keeps her living at 0, or stands, small, under a full pile of them (the
  stalemate, which binds first when `q` is above about 1.5 at odds 0). Below both her living gather
  and their pull pins the garrison at 0.
  - **Why not the controller's dG/dt at today's garrison, with her living at the level the reship
    sustains** (the reading proposed for T3.1, set aside for this reason): the garrison's kills,
    `k_kill · U`, don't depend on her living, so her reship either dies on landing (level 0) or
    piles up to the cap; there is no level between to read. And `dG/dt` at today's garrison carries
    `−r_drain · G`, negative for any garrison above the level its WAR holds: a full garrison at a
    well-supplied fort would read falling, `war_supports` would count it unsupported, and "will
    fall" would mislabel forts that hold. This rate's sign is the outcome; it reads neither today's
    garrison nor today's (possibly surged) living, so it doesn't flicker through a wave.
- **`fall_s` = grace left + `min(G, A / r_drain) / −garrison_rate` + what is left of `hold.break_s`**
  (all of it, less the zero clock while the garrison already sits at 0) while the rate is < 0, else −1
  (never INF). A straight line from the level the support holds. **It errs early** (E2b-2 T3.4b, the run's
  manager: "make it err EARLY"): the fort is retaken no sooner than it says. Measured against RealmSim at
  0.5 s with no wave from a contested Ashgate (or Whitecross) with every other fort full of corpses, 38
  cases (q 1.2 and 2, 0 to 2 mass/s of WAR, the garrison at its level, at 40, 80 or 300, Relish there,
  in grace, pinned): early in every one, by 0 s (a garrison at 0 with nothing arriving: exactly
  `break_s`) to 1 377 s (0.3 mass/s with 80 undead: 236 s against 1 613 s). Two terms make it so:
  - **the line starts at the level** `A / r_drain`: a garrison above it drains to it within a few
    `1 / r_drain` (17 s), far faster than the line. From the garrison itself (before T3.4b) the clock read
    late whenever it started well above that level: 353 s against 219 s with no WAR and 80 undead, 1 981 s
    against 1 613 s at 0.3 mass/s, 1 428 s against 1 587 s at Whitecross from 300 (early only there);
  - **the zero clock**: a garrison already pinned at 0 has only `break_s − zero_s` left (60 s against
    60 s with 60 s on the clock; before, 120 s).
  - **the planned support** (the T3.4b fix batch, the run's manager): the clock is the earlier of the
    one at the current split and the one at the support the margin's train reads (the valve's target WAR,
    Relish where she is travelling to), so a valve slewing down or Relish travelling away can't make it
    late. A new game with all WAR at Ashgate, no WORK (no muster), its garrison at its 0.45 share's level:
    a substep after the WAR is cut to 0 the slewing split still holds it (`garrison_rate` +5.1 mass/s, the
    current clock −1), the planned clock says 120 s and it is retaken at 220 s (`test_wave_train`).
    `garrison_rate` and `war_supports` stay at the current split, so a row can read a positive rate
    beside a falling clock for the few seconds of a slew or a trip.
  At the level the line was already early, and stays so: with 0.2 mass/s (garrison 3.3) 143 s against
  733 s (her living climb at only `S − k_kill · G` = 0.043/s at first, and must pile to `q · W /
  k_destroy` = 40 before they pin it). So the clock is a warning of minutes against hours, never late.
- **`margin`**, checked in this order (E2b-2 T3.2, T3.4b): `will_fall` (cause `fall`) when 0 ≤ `fall_s` ≤
  `hold.safe_horizon_s` (8 h); else `thin` (cause `wave`) when **the wave train breaks it** (below); else
  `thin` (cause `fall`) when `garrison_rate` < 0 (attrition beyond the horizon: unsettled by the fall, not
  by the waves); else `thin` (cause `wave`) when the held set **hasn't settled** by the train's cap; else
  `safe`. The order is the one ruled: a fort the train breaks would also fall, but its threat is the
  waves, and a fort that falls without them is never settled anyway (it weakens every cycle). `view_fort`
  and `view_realm` read the train; `view_projection` reads it with `settled` and keeps the one-wave probe
  (below) for a drag. The run's manager: "'safe' judges against the WAVE TRAIN (correctness first; the
  worst lie = safe then breaks overnight)".
  - **The wave train** (`RealmSim.train_probe`): every held fort runs forward **together**, from
    **today's state** (each fort's garrison, her living there, its corpses, its zero clock and its
    grace; the tithe as it stands: `next_s`, a pending warning and its target, a running wave and its
    `s_left`), on scratch copies, at each fort's support (the WAR the valve sends it, Relish's redirect
    and tide, the siege's block (none credited from E3-3: §3.4's counters), `q`). It is RealmSim's own `fort_step` at `hold.probe_dt_s` (10 s), each
    step cut at the next event so each lands at its time (a warning, a wave's start and end, a grace end,
    a garrison at 0 reaching `break_s`), with the zero clock as step 9 runs it (T3.3a's leave-0 split
    included), through her waves at her period (`tithe_period`, at today's odds). A contested fort gets
    her reship, a fort in grace nothing; the running wave surges `surge_mult · S_vei` × its counters into
    its target (her pool assumed to cover it). A fort whose clock reaches `break_s` is **broken** and
    leaves the held set. A clock not yet started (only a test or debug holds a fort with no flip) runs as
    if started now.
  - **Targets**, as `_tithe_target`: at each warning, the contested fort (held, past grace, not broken)
    with the lowest margin, its `sup` WAR less its one-wave need (`need_of`, once per fort per probe: her
    odds, q and the support don't move in the probe), ties in world order. A fort in grace is never a target; a pending warning naming
    one is dropped and made again at once, as the clock does. The target is fixed at the warning, so a
    wave warned while every held fort is in grace goes elsewhere even if the grace ends before it lands.
    With no contested fort the rule's second branch (the fort receiving the most WAR) picks a fort that
    isn't held (every held fort is then in grace or broken), so that wave threatens none. Several held
    forts are probed in one joint run because the target depends on all of them: Ashgate (1.19 mass/s)
    and Old Sluice (0.81) take waves Ashgate, Old Sluice, Ashgate, ... (Ashgate's first wave leaves it
    below Old Sluice at the second warning), the order RealmSim's own 0.5 s steps give, and Old Sluice
    breaks in both (`test_wave_train`).
  - **Settled, judged jointly**: at each wave's start the probe samples the set, and compares it with the
    sample p cycles before (the smallest p with the same wave starting at both, both after the last grace
    end or break in the probe: a repeating target sequence, so A, A, A compares consecutive cycles and A,
    B, A, B every second one). Every fort's zero clock must be at 0, and within `hold.train_settle_tol` ×
    its cap (0.08 mass at Ashgate): a fort that **every** wave of those p cycles targeted must be no
    weaker (garrison no lower, her living no higher, its corpses no lower where Relish raises); **any
    other** contested fort must repeat both ways. That second rule tightens the ruled "no weaker" (the
    run's manager's design asked for no weaker everywhere): a fort no wave hit is shielded by a
    neighbour's larger garrison, and a garrison still rising there (or her living still falling, which
    would raise it) could overtake the neighbour and draw a wave it was never tested against; for a fort
    every wave already hits, more undead only keep the waves on it. Settled, every unbroken fort is;
    before that, none is (the shielded fort: `test_wave_train`'s Old Sluice beside Ashgate at 1.2 mass/s,
    never hit and the same at every sample, reads thin with the cap at 2 cycles, where Ashgate hasn't
    repeated yet, and safe at the shipped 4, where it has).
  - **The cap**: at most `hold.train_max_cycles` (4) cycles after the first sample of the current
    epoch (since the last grace end or break), and the probe stops early once settled or every fort is
    broken. A set still unsettled there reads thin, not safe. It also stops at `hold.safe_horizon_s` of
    probe time, which counts as held (only a clock pushed far off, in tests, gets there).
  - **The support it reads is the settled WAR** (E4 must-fix #1; `GameState._train_war_at`): the mint at the pits'
    trough feed (`TownSim.trough_feed`: the rot alone, burned up to what the staffed pits can burn, as with no load
    landing and an empty store) × the valve's WAR share, plus the muster TownSim settles at on that mint's WORK
    (`TownSim.workforce_steady`). Before, it read the substep's mint and muster, a landed load's feed of 1 and the
    WORK burst it musters, held across the whole forecast. One substep after midgame_2flips' load that read 9.713
    mass/s against the 7.617 the split settles at a minute later; over a convoy cycle (the sessions bot's day 2) the
    split swings 63.5 ↔ 98.7 and the settled WAR reads 63.5, its minimum, without flicker (an average over the
    last trip read 77.7–98.7). It ignores the bodies in store, so a large stock reads low for as long as the pits
    burn it at full: pessimistic, not false (a follow-up). It isn't guaranteed to err early: the train isn't
    monotone in WAR (midgame_2flips at a WAR share of 0.45 reads Ashgate safe at the settled 7.617 and thin at
    the burst's 9.713; it holds). `view_projection` reads the same settled WAR at its valve.
  - **What it reads that isn't in today's flows yet**, both committed and changed only by a command: the
    WAR **at the valve's target** (it slews there at `valve.slew_per_s`, at most 20 s for a full swing),
    and **Relish where she is travelling to** (her trip takes seconds at `relish.travel_speed`): her tide
    and redirect there, and the split with her tide moved there (`RealmSim.war_at_tide`). midgame_2flips
    as loaded has her a second from Greywall; held where she stands, the train called Old Sluice safe at
    its WAR of 1.258, which her tide cuts to 0.761 and the next waves break (retaken at 1 316 s). The
    fall clock reads the earlier of the planned and the current support (above); `garrison_rate` and
    `war_supports` stay at the current split. Before the
    first substep after a load (no dispatch yet) it reads the saved `r_in` with her where she stands, as
    they do: midgame_2flips as loaded reads both forts safe for that half second, then thin.
  - **Quiet stretches**: while every fort has no living and kills her reship as it lands (`k_kill · U ≥
    S` from now to its level), or is in grace, fort_step's path is exact over any step, and the probe goes
    straight to the next event: the same verdicts and samples as 10 s steps (to 1e-15), in 37 steps
    instead of 84 for a strong Ashgate.
  - **The odds caveat**: her odds climb over hours (the waves come faster, her reship grows) and the
    train holds today's. In the truth check below no safe fort fell to that: midgame's Ashgate read safe
    from 30 min to 4 h and stood all 12 h while her odds climbed, and pre_vei+2's forts, read safe at odds
    0.60 to 0.96 (the period from 294 to about 220 s, the reship × 1.30 to 1.48), stood until the town's
    economy failed (below).
  - **The one-wave probe** (view_projection during a drag, `margin_verified` false): RealmSim's own
    fort_step on a scratch copy of the fort at `hold.probe_dt_s` for at most `hold.probe_s` (600 s): the
    garrison at the least of today's and the level its support holds (`A / r_drain`, or the
    stalemate's), her living at the level her reship keeps there (none, or the stalemate's pile `(cap +
    τ·S − τ·k_kill·A / r) / (1 − τ·k_kill·k_destroy / (q·r))`), no corpses; one wave of `surge_mult ·
    S_vei` living/s × the counters for `surge_s` on top of her reship, with Relish's raise where she
    redirects; the zero clock as the sim runs it. Broken when the clock reaches `break_s`; survived once
    the wave is over and her living can no longer pin the garrison. Its margin is the order above with
    "one full wave breaks it" for the train and no settled test. A falling fort's probe starts at a 0
    garrison, so a full wave always breaks it and a slow fall reads `wave` unless `hold.probe_s` <
    `hold.break_s`. Its edges are the 10 s column of §3.4's table (Ashgate 1.033, Greywall 1.077,
    Vespers 1.386, Whitecross 3.026; with Relish there 0.547, 0.582, 0.837, 2.219). It misses wave
    trains: a lone Ashgate at 1.04 to 1.10 mass/s survives one wave but not the next, since her living
    from the first haven't gone when the second lands (the train breaks it at its second wave, RealmSim
    at 0.5 s retakes it after its second, at 970 s).
  - **A slow fall the train can read**: today's-state start doesn't make T3.2's slow faller (Ashgate at q
    2, 60 undead, its WAR just under the edge) reach cause `fall`: its garrison drains to its level
    within a minute and its first waves pin it past `break_s`, so it reads thin (wave). A slow fall no
    wave in the train breaks is a shielded one: Old Sluice just under the edge beside a stronger Ashgate
    that draws every wave reads thin (fall) (`test_api_v6`'s slow-fall case).
- **Cadence and cache** (`GameState._train`): one joint probe serves `view_realm`'s rows, every
  `view_fort` and `view_projection` with `settled` at the valve's target. It is computed lazily, on the
  first read after the state moved, and cached on `[rev, t, q, the support, RealmSim.train_state()]`:
  `rev` and `t` as the build projections key theirs (a catch-up's core steps move `t` without `rev`), and
  the state the probe starts from, so an edit that bumps neither still misses. Nothing in the sim reads
  the margin (`war_supports` reads `garrison_rate` only), so lazy is the same as once per step and costs a
  catch-up nothing. Since T3.2's lesson (work in a view call lands on the substep frames, where the scenes
  refetch), on the frame path (the shell's capped `tick`) a read after a substep doesn't probe when only
  live substeps have moved the state since the cached one (no command since, and `t` moved by exactly
  those substeps): it serves that verdict, at most a few substeps old, and `GameState._train_frame`
  re-probes on the next frame with no substep, at least `hold.train_frame_phase` (0.5) of a substep into
  the interval, while a view reads it; when every frame substeps it re-probes after
  `hold.train_starve_frames` (30) of them. A command re-probes at the next read, on its own frame, and so
  does a catch-up (its core steps move `t` without `rev` or the substep count). Off the frame path (tests,
  headless tools) every miss probes, exactly. A new game and every load (`from_dict`: `cmd_load`, the
  fixtures) empty the cache and turn the frame path off until the shell's next capped tick.
- **The truth check** (`tests/slow/margin_truth.gd`): from each start, live 0.5 s steps for 12 h with no
  input; at the first substep and every 30 min to 4 h, each held fort's margin, then what happened in the
  next 8 h. midgame_2flips: 10 samples; the train read Ashgate and Old Sluice thin at t0 (Old Sluice fell
  at 1 316 s, Ashgate held: thin and pessimistic there) and Ashgate safe from 30 min to 4 h (8 safe,
  all held); the one-wave probe read all 10 safe, Old Sluice's at t0 the lie. pre_vei and fresh hold no
  fort (no sample). pre_vei with Ashgate and Vespers contested (after 10 min of pre_vei's own play, past
  its opening muster burst): 18 samples, all safe, train and one-wave alike, and all held. Its gold
  reaches its floor at 7 092 s, and the upkeep sheds the Statue and the passive buildings (§4.3's shed
  order, R1), so its pits keep raising and the two forts' WAR holds (6.3 to 10.7 mass/s at the samples).
  Before R1 the cheapest-first shed stopped the pits there and the WAR went from 49.7 to 0.95 mass/s at
  7 096 s: 8 of its samples read safe and broke at about 2 h, then read will_fall. midgame with the
  valve's WAR share cut to 0.05: both read thin at t0 (the one-wave probe safe) and both fell. So 26
  safe samples, none broken.
  - **No fall is excused** (R1). E2b-2's known gap (the run's manager: accepted for E2b-2 only) counted
    a safe fort that fell after a town store's floor and its WAR's drop apart, as "its WAR fell: supply
    (E4)": 8 of 16 safe samples, all pre_vei+2's. With the shed order no safe sample falls (0 of 26), so
    the exemption is deleted: every safe fort retaken within 8 h of its sample fails the check
    (`safe_broke()`, whose synthetic cases include the old exempt one). Neither probe reads the town
    still: a floor deep enough to shed the WAR chain itself (gold income under the chain's own upkeep
    plus the Market's) would break a safe reading, and no start here has one.
- **During grace** every readout is the post-grace one: the reship it will face; `fall_s` adds the
  grace left; the margin is the train's run through the grace, which no wave reaches, from the garrison
  the grace leaves it. `grace_s_left` > 0 says so.
- **`war_supports`** `{n, m}`: `m` held forts, `n` of them with `garrison_rate` ≥ 0. More WAR never
  supports fewer (water-filling is monotone in the WAR it splits).
- **Cost** (E2b-2 T3.4b), best of 3 at a load average of about 6.5 on 12 cores (no time is asserted). The
  train probe uncached: 1 183 µs on midgame_2flips (2 held, 119 steps, unsettled at its 4-cycle cap), 1 209
  µs 10 min in (172 steps: Old Sluice broken, Ashgate settled in 3 cycles), 2 µs on pre_vei (none held),
  119 µs on pre_vei with 2 contested and 289 µs with 5 (each settled in one cycle); a cached read (the key)
  about 20 µs. `view_realm` 313 µs on midgame_2flips with the train cached (476 µs at T3.4a's tip, which ran
  two one-wave probes per call). Frames, a headless per-frame bench of the world map at 1600 × 900 (60 s of
  live play, uncapped, against T3.4a's tip `2c01f45`, best of 3 interleaved runs): on midgame_2flips the 121
  probes a run all landed on frames with no substep (p50 1.8 ms, max 2.3 to 2.5 ms, against about 0.25 ms for
  such a frame) and the substep frames got cheaper (p50 4.5 to 4.7 ms against 4.8 to 4.9); p99 774 µs (750),
  max 6.57 ms (6.95), 0 frames over 8 ms (0). On pre_vei with 2 contested, p99 805 µs (825), max 8.97 ms
  (9.01), 3 over 8 ms (3), every one a substep frame. On pre_vei as loaded (nothing held, nothing probed;
  the train adds 2 µs to a `view_realm`), p99 808 µs (799), max 8.56 ms (8.76), 3 over 8 ms (2; 13 against
  11 over the three runs, the base alone 2 to 6). Lazily on the substep frames (before the frame refresh)
  midgame's substep frames rose to p50 6.2 ms and max 8.4 ms, 6 frames over 8 ms (0), which a refresh cadence
  alone couldn't fix (each probe would still land on a substep frame). The one-wave probe (a drag's
  `view_projection`) is about
  30 µs per held fort per call; `war_supports` reads only the rate.

### 3.6 Simulacra (kept, defined)
- Crafted at the Ossuary from essence and a relic (E3-4): `cmd_craft("simulacrum")` takes `economy.json`
  `craft.simulacrum` (20 essence, 1 relic) at once and adds 1 to `simulacra_ready`, a fungible count GameState saves.
  It needs a built building with `craft_slots` (the Ossuary Tower; a capacity effect, so an unpaid or Thrift-idled one
  still crafts), checked by the effect, not the building's id. There is no stock cap: the essence (60) and relic (12)
  caps bind it. The same command crafts a phylactery charge (§7).
- `cmd_deploy_simulacrum(fort_id)` plants one (live from E3-4) at any fort, held or not, taking it from
  `simulacra_ready` (`none_ready` with none). It performs **Relish's redirect** at that fort at
  `simulacrum.rate` until its charges run out: garrison kills there stay as corpses while it has
  charges, and it raises corpses into the fort's undead. Charges are mass and only the raise spends
  them. `realm.json` `simulacrum.rate` 1.0 mass/s and `simulacrum.charges` 300 (E4 placeholders, BALANCE §5): 5 min of
  raising, a quarter of Relish's `raise_rate`, at a fort whose corpses keep up. The raise is §3.1 step 5's, after
  Relish's, bounded by the corpses; a spent one crumbles (step 6).
- Several at one fort stack: each raises at its own rate from its own charges, and `view_fort().simulacrum_charges`
  sums them.
- A retake of its fort loses it, charges and all (§3.4; IDLE I6, so one at a fort that falls while you're away is
  lost too).
- Catch-up clips a step at a simulacrum running out, while its corpses keep up (IDLE §4).
- The margin chip credits no simulacrum (§3.5's readouts read Relish's raise alone): conservative. E4 credits the
  siege (§3.4) but not this. A simulacrum's charges run out (300 at 1.0 mass/s: at most 300 s of raise), well
  inside the cycles the wave train settles over, so a standing credit would read safe where the fort falls once
  they are spent. Crediting it needs a per-fort charge budget in `RealmSim.train_probe`, and a run-out event its
  quiet stretches clip at. Not built (E4 follow-up).
- The tide is hers alone.

## 4. Economic: Covington

### 4.1 Workforce
TownSim (`scripts/sim/town_sim.gd`) runs §4.1–§4.3. Workers are counted in workers of `worker.mass`
mass; bodies, rot return, WORK and muster are mass.
- `workers' = work / worker.mass − rot − muster`. WORK arrives in the same step; the mint reads last
  step's feed instead (§1.3).
- **Rot:** a staffed worker rots at `1 / lifetime`, an idle one at `worker.idle_rot_mult / lifetime`.
- `lifetime = worker.lifetime_s · (1 + Σ lifetime_bonus) / relish.home_rot_mult` while Relish is
  home, and without the division otherwise. Home multiplies the rot *rate* by `home_rot_mult` (0.7),
  so a home lifetime is ÷ 0.7. `lifetime_bonus` comes from working Graveyards and Embalmers, per level.
- Rot returns `rot · worker.mass · worker.body_return` mass of bodies. What the body cap can't hold
  is reported as `rot_overflow`, a ledger sink.
- **The store over a step** (E2b T3.0): rot return and convoy landings come in, and what the pits
  and mills want goes out: out = min(want, B0 + in). The pits have first call on it (E2b-2): while
  the store holds bodies both draw their full want, and the step's shortfall falls on the time it
  stands empty, τ = (want − out) / (want/s − rot return/s), when only the rot return comes in (a
  landing refills it at once). In τ the rot return goes to the pits first and the mills get what
  exceeds the pits' want. So burned = want_pit/s · (dt − τ) + min(want_pit/s, rot/s) · τ and the
  mills the rest of out; with the store empty all step that is min(want_pit, in), the surplus to
  the mills. The two are netted before the cap clips, and
  only what is left above the cap overflows (a store already over the cap, after a demolition, keeps its excess and the pits draw it down; only what comes in is clipped, to `max(cap, B0 − out)`; a known edge: from over the cap with the draw outrunning the inflow, a long step books no overflow where shorter steps book the inflow until the store reaches the cap, which the gold and bone stores solve exactly, §4.3. E2b-2 T3.3a left it: no step of midgame_2flips, pre_vei or fresh over 12 h, at 0.5 s or 10 s, starts with the body store above its cap), split between `rot_overflow` and `haul_overflow` by
  their shares of the inflow. A long step near the cap books no phantom overflow. A convoy's
  departure and pickup see the store's projected level at that moment (rot in, pits and mills out,
  loads landed), and the forts' corpses at that moment too (§4.2, E2b-2 T3.3a).
- `view_town` shows the steady state, `(work / worker.mass) · lifetime`, beside the current count. That figure ignores the idle cap; `steady_kept` is where the workforce actually settles with it (STATE-API §5.9).
- **Workers are allocated by the job ladder** (§4.5).
  - Workers beyond all slots idle at the crypt and rot slower (`worker.idle_rot_mult`).
  - Idle beyond `worker.idle_cap` are mustered at once (`n · worker.mass` mass) to Vei's queue with the
    FLOOD (§3.2, ruling A1), so WORK is never a black hole, but it is waste for the town. The workforce
    never ends a step above the staffable slots plus `idle_cap`. While the Muster stance acts the idle
    cap reads 0 (§4.5, `TownSim.idle_cap`) and the whole muster joins WAR.
- **The update is exact** (IDLE §4). With the step's inflow held constant, the equation is linear in
  three regimes: all staffed (τ = `lifetime`), some idle (τ = `lifetime / idle_rot_mult`), and pinned
  at slots + `idle_cap` with the surplus mustered. Each boundary crossing is timed exactly, so one
  60 s step matches 120 half-second substeps. Rot is booked as `inflow · dt − Δworkers − muster`, so
  the three always balance.

### 4.2 Jobs (rates per staffed worker; keys in `economy.json`)
- **Slots.** A working building offers its `buildings.json` `jobs` × its level (a Chapel of Vats its
  tend slots only for its staffed vats, §7). A lot under
  construction offers `job.build.slots` build slots; a first build offers nothing else, and an
  upgrade keeps its old level's slots too (its building keeps working).
  An unpaid building offers none. Staffing is fractional.
- **Effects.** A building's numeric `effects` are per level (× level), or a per-level table when the
  value is an array: the Charnel House's `body_cap` is 0 at level 1, then +50 a level to 350 at level 8 (`[0, 50, ..., 350]`), so only its upgrades add.
  Flow effects (`pits`, `morale`, `attract`, `lifetime_bonus`, `haul_speed_mult`, the Statue's
  `death_shock_mult`, E3's `hint_precision`) need the building working. Capacity effects (`body_cap`,
  `gold_cap`, `bone_cap`, `relic_cap`, `essence_cap`, `living_cap`, `vat_slots`, `stance_slots`, and
  `craft_slots`, the craft gate from E3-4 (§3.6); `TownSim.CAPACITY_EFFECTS`) also count while it is unpaid or
  upgrading, so an unpaid spell never destroys stock.

| job | building | effect |
|---|---|---|
| haul | charnel house | One convoy. It leaves when haulers are staffed, bodies are under the cap and there is a target: `auto` is the fort with the most `dead` above `job.haul.auto_min_dead` at the moment it leaves (below); otherwise it is the fort set by `cmd_set_haul_target`. An `auto` convoy at home with no fort above the threshold leaves at the step's first `sim.substep_s` mark after a fort's projected `dead` passes it, as live play's next substep finds it, not at the step's end (E4 step 10, the I1 bone-gap probe: a 3 s catch-up step held it home and made 23% more bone over an hour; IDLE §8). Each leg takes distance / (`job.haul.speed` · (1 + Σ stables `haul_speed_mult`)), and the crew is fixed at departure. At arrival it picks up `job.haul.carry` per hauler (× `flip.haul_mult` at a held fort), clamped to the fort's `dead` at that moment, to what the fort held at the step's start (less this step's earlier pickups there) and to the store's headroom (its projected level at that moment, §4.1). What formed there since the step's start it claims, up to the carry and headroom the load leaves, and that is taken after the realm step (§4.2, the hold and the claim). The load lands on the way back; what the store can't hold once the pits and mills have taken theirs is `haul_overflow` (§4.1). A long step runs as many legs as it holds. At the body cap, haulers stay staffed but no convoy leaves. |
| mill | bone mill | each miller turns `job.mill.mass_per_s` bodies into `job.mill.rate` bone per mass, from what the pits leave (§4.1) |
| stall | market | gold = `min(staffed_stalls · stall.rate, living · market.shop_rate) · market.price`. The sales rate is `trade_rate`. |
| forge | forge | `job.forge.rate` work per worker-second toward `forge.level_work[level]`. The level completes only when `forge.level_relics[level]` relics are available; until then progress holds. This is TownSim's forge level (for `q_forge`), not the Forge building's level. |
| pit | raising pit | each working pit burns `pit.burn_per_s` × its staffed share, with first call on the bodies (below). `wanted = pit.burn_per_s · pits` counts every working pit, and `feed = min(1, burned / wanted)`. |
| tend | chapel of vats | one slot per vat, open only while that vat is staffed (§7; E2b-2): `jobs.tend` × level slots for `vat_slots` × level vats, the same count. Grows clones (§7, E3); until then only the tenders count |
| build | construction | `job.build.rate` work per worker-second against `build_work · target level`. A `build_work` of 0 completes at once. |
| foreman | (big undead only) | multiplies a building's job output by `foreman.mult` + speed·`foreman.speed_k` (live from E3-3; below) |

- **The foreman** (E3-3, the run's manager's rulings; `economy.json` `foreman`, v0 E4 placeholders, BALANCE §5).
  A big undead placed `town:<lot_id>` works there, and multiplies that building's **job output** by
  `m = foreman.mult + speed · foreman.speed_k` (speed is its stat):
  - **What it multiplies:** the Market's gold, the Bone Mill's bone, the Raising Pit's raise, the Charnel House's
    carry, the Forge's work and the Chapel of Vats' growth. The job comes from `buildings.json`, never the id:
    stall gold, mill bone, pit burn and raise, haul carry, forge work, tend growth.
  - **After the job's own caps.** The stalls' gold is `min(staffed · stall.rate, living · shop_rate) · price · m`,
    so the living cap on the sales comes first, and `trade_rate` stays the sales. The mill's bone is the bodies
    milled × `mill.rate` × m: the bodies it takes don't change, so no mass moves. A Chapel's vats grow on
    their tend hands (one per vat) × m. Two exceptions keep the mass ledger exact, and the ledger wins:
    - **The Pit:** the foreman multiplies the pit's burn too, so it draws bodies m times as fast. It also
      multiplies its weight in the pits' `wanted` and in the mint's pit count (`TownSim.pit_weight`: Σ pits × m
      over the working pits, a float). So the raise follows the burn: the pit raises m times its share of
      `P_per_pit · pits · (1 + pit.bonus · feed)` at the same feed, and burns m times the bodies for it.
    - **The Charnel House:** the carry per hauler is multiplied (the convoy's crew, fixed at departure, is the
      haulers × m). The clamps on a pickup, the fort's dead at that moment and the store's headroom, still apply
      after it.
    - **The store caps** still clip gold and bone as before, the overflow booked to `ledger().stores`. "After the
      job's caps" means the job's caps, not the store's.
  - **It gives nothing** at a building that has no job slots (a passive one), or isn't working (unpaid, idled by
    Thrift, or mid-upgrade: TownSim's state `constructing`), or has no hands staffed. The exact condition: a job
    building whose TownSim state is `active` (`TownSim._fm_works`). A foreman placed there is still allowed (no
    refusal) and changes nothing, and `view_town`'s `foreman_mult` reads 1.0.
  - **Presence:** a foreman that works adds `foreman.presence_k · presence` to the morale target, shown as the
    `foreman` factor (`view_town().morale.factors`), and clamped with the other sources (the target is 0..1).
  - **How TownSim gets it:** as state, `TownSim.foremen` (`lot_id → {speed, presence}`), which GameState sets from
    the big undead's places (`_sync_foremen`): at each core step's start, on every command that moves one, on a
    new game and on a load. It isn't saved, because the save's big undead carry the places. `clone()` carries it,
    so every projection runs with it: the stances' `projected`, the build card's and `upgrade_projected`, the
    forecasts' and margins' clones, `lot_output`, and `queue_net` / `affordable_in_s`, which read the last step's
    rates. Placing a foreman moves `structure_rev`, so the caches keyed on it refresh.
  - The foremen can't change inside a catch-up: commands are refused, and its own events move only a siege and
    the party. Whether one works follows the building's state, whose changes the catch-up clips at or TownSim
    makes at a step's start (IDLE §4).

- **The pits have first call on the bodies; the mills take only the surplus** (E2b-2, the run's
  manager). While the store holds bodies both draw their want; while it stands empty the rot
  return goes to the pits first, and the mills get what exceeds the pits' want (§4.1 has the step's
  τ). They used to share short bodies in proportion to what each wanted, so the mills ate the pits'
  feed and the mint swung with the mills' want (12.8 to 8.98 mass/s in play). Feed is still
  continuous in the supply, so it never toggles. The total taken is unchanged, so the store's path
  and the convoy's view of it are too.
  - **The town says so** (T3.4a): when the staffed mills milled less than their hands want in the
    last step, `view_town().buildings[]` reads `starved` on a building with mill slots: `"pits_first"` if the pits took
    bodies, `"no_bodies"` if they took none (STATE-API §5.9). The same shape of problem exists, unsaid,
    for the pits (store empty: `feed` < 1), the stalls (`living` · `market.shop_rate` under the staffed
    stalls' rate) and the forge (a level waiting for relics); only the mill's is reported on the buildings.
    From E4 step 10 (review-t7r1r2 §5) the stalls' is kept too (`TownSim.trade_starved` `"living_first"`, per step,
    never saved) and read by a queue head that can never be afforded on gold, not by the Market's building row: a
    Market level adds stalls, so while the living bind it sells nothing more, and the row's lever and the away
    report's line name housing or an Inn (IDLE §7). A queue row reads a flag only when it is that row's blocker
    (the E4 final review's item 5): the head waiting on funds at `affordable_in_s` −1, from the store it is never on;
    a timed wait reads `""` (STATE-API §5.9).
  - **The bone cliff** (E4, the run's manager's A1 day-1 ruling). Under A1 (§3.2) the muster goes to Vei, so
    early bodies come from WAR's corpses at the forts and the workers' rot return. Below a WAR share of about 0.54
    a new game's pits eat every body (0.20 mass/s of rot return; the forts' corpses are cleared as they form) and
    the mill makes exactly 0; above it the feedback runs (bodies → pits → mint → WAR → corpses) and bone reaches
    its cap within hours. A new game at FLOOD 0.15, the mill alone queued, 2 h (tools' edge probe):

    | WAR share | 0.45 | 0.50 | 0.53 | 0.54 | 0.55 | 0.60 |
    |---|---|---|---|---|---|---|
    | bone milled in 2 h | 3.6 | 3.5 | 3.4 | 263 (from 30–60 min) | 324 (cap) | 367 (cap) |

    It is a tipping point, not a per-fort inequality: at 0.40 the three nearest forts' WAR already beats their
    living's pull (k_destroy / q · L), so no closed form reads it off a state. The cliff stays because it is
    visible and one valve move fixes it (the ruling): the start valve is 0.25 / 0.60 / 0.15 (BALANCE §0); the
    mill's row and a queue head never affordable on bone read `starved` `"pits_first"` and `lever` `"raise_war"`, the head's
    `short` names the bone, and the away report's head line says so (IDLE §7; STATE-API §5.9, §5.19);
    `view_hud.bone_war_share` is a new game's edge (`economy.json` `opening.bone_edge.war_share`, bracketed by
    test_day1_queues) for the valve readout. Pits-first and the yields are unchanged, and there is no mill floor.
  - Why τ, not pits-first on the step's whole supply (min(want_pit, B0 + in)): that version
    depended on dt. A load landing inside a long step fed only the pits, where shorter steps let
    the mills draw while it lasted; pre_vei's bone was 44.8% off at 15 s over 1 h (0.09% with the
    proportional split, 0.11% with τ). With τ one 10 s step splits as twenty 0.5 s steps do.
  - Measured over 12 h at 10 s with no input, against the proportional split: midgame_2flips is
    short of bodies every step (rot return and the convoy bring in less than its pit wants), so
    its feed rises from 0.30 to 0.49 and its mint from 9.42 to 10.35 mass/s, while its mills get
    almost nothing (100 bodies milled in 12 h instead of 5 117; bone +50 instead of +2 558).
    pre_vei is short in 57.5% of the steps: its mean mint is 25.92 against 25.90 mass/s, its mills
    1 656 bodies against 1 837. fresh is never short.
- **The convoy reads the forts' corpses at its own moment** (E2b-2 T3.3a, as the run's manager
  ruled). TownSim runs before the realm step (§1.3), and its convoy used to read each fort's corpses
  from the snapshot taken before the step; GameState takes the pickups off them before the realm
  step. A long step's legs then found corpses the step itself would have raised or cleared. From
  midgame_2flips, whose convoy is fixed on Greywall, Relish raises the corpses there as they form
  (4 mass/s against 0.2 to 2.2 formed). A 10 s step's solve leaves about 0.047 (its raise is bounded
  by the corpses its last pass saw), and the convoy hauled that: at `9b5fc99` 115.7 mass over 12 h
  at 10 s against 0.001 at 0.5 s (167 against 0.06 at `40d62c0`), and 2.68 against 0.001 once the
  zero clock kept Ashgate held, all of it in the first 800 s. Now 0 at both.
  - **The projection.** Each fort in TownSim's snapshot carries `dead_rate` (`RealmSim.dead_rates`): the
    net rate of its corpses while it holds any, from the state before the step. What forms: the kills,
    `k_kill · U` while living stand there, else what Vei shipped in last step (`r_shipped`, killed as
    it lands) up to `k_kill · U`; and at a redirect site (Relish's fort, a live simulacrum's) what the
    garrison destroys there, `k_destroy · L / q`, with U at 0 at most the WAR and raises arriving
    (`r_in`). Less what leaves: the clearing `k_clear · L` and the raises wanted there.
    `RealmSim.dead_at(dead, rate, s) = max(0, dead + rate · s)`: at 0, what forms is raised or
    cleared as it forms. The pick (auto: the most corpses at departure) and the pickup (at arrival)
    read it at the leg's moment, less this step's earlier pickups there.
  - **What it costs in exactness.** When TownSim runs, this step's WAR (which includes TownSim's own
    muster), shipping and dispatch aren't known. So it reads the fort as it stands at the step's
    start: its pools, last step's `r_shipped` and `r_in` (where no living stand, the kills are one
    step stale), and Relish's redirect as she stands before this step's travel. It is exact while
    the step's rates hold those values.
  - **After a load.** Every input is saved (the pools, `r_shipped`, `r_in`, Relish, the simulacra,
    q's inputs), so after a load the convoy sees what the session saw, within the save's 15-digit
    rounding (`test_step_accuracy`). A session-only rate such as `r_kills` would read 0 for a step
    after every load, and the pick could differ.
  - **The hold and the claim.** A pickup's load is held to what the fort held at the step's start,
    less this step's earlier loads there. GameState takes it off the fort before the realm step, which
    owns the corpses made inside it, so the ledger stays exact (`test_ledger`). What formed at the
    fort since the step's start, as the projection reads it at the leg's moment (`dead_at` less the
    start's `dead`, less this step's earlier claims there), the leg **claims**, up to what its load
    leaves of the carry and the headroom (E4, the run's manager's A1 I1 ruling (1)). GameState takes
    each claim after the realm step (`_take_claims`), at most what the fort then holds, so the realm
    step keeps first call on those corpses. The claim rides the convoy while that leg is still on its
    way back, else goes into the body store up to its cap (`TownSim.land_claim`); what isn't taken
    stays at the fort. Mass only moves between held pools, nothing is owed, no save field is added,
    and §1.3's order and the hold stay. It is not E2b-2 T3.3a's on-file sink inside the realm step.
    - **Why.** A leg is dead-limited wherever the convoy leaves as soon as a fort holds
      `job.haul.auto_min_dead`, as it does early on: about 4.2 mass a load against a carry of 14 per
      hauler. Held to the step's start alone, a long step's legs left the corpses formed before each
      pickup at the fort. In the I1 gate's first away that was 30.5 mass over 99 legs at 3 s against
      3.4 at 0.5 s, and at forts with living the clearing took some (+8.3), so the caught-up run
      landed and milled 1.7% less and the bone-bound queue amplified it (IDLE §8).
    - **With the claim** pre_vei's convoy lands the same over 600 s, 30 min and 1 h at 3 s and 10 s as
      at 0.5 s, and leaves the same corpses and load (1 129.81 mass at 600 s at all three;
      `test_step_accuracy`). Before, 600 s at 10 s was 13.3 mass behind; at 10 s the convoy ran 10 to
      15 mass behind 0.5 s's from the first minute and the bone over the cap was 1.14% behind at 600 s.
      convergence_1h's 15 s row for pre_vei reads Σdead 0.000% (63.1% before) and its bone-over tally
      0.18 of its 1.0 floor (1.09). The catch-up gate's bone floor (`idle.catchup_gate_tally_floor`)
      stays.

### 4.3 The living
- `living' = migrants − departures`, capped at `living_cap`: `opening.living_cap` (16, the crypt
  district's huts) plus the `living_cap` effects of houses, wells, bakeries, the inn and walls. The
  update is exact (IDLE §4); migrants the cap can't house are turned away.
- `migrants = Σ held villages · town.migrant_rate + inn.attract · inn_level`. `inn.attract` is the
  Inn's `effects.attract` in `buildings.json`, per level of each working inn.
- `departures = living · town.leave_rate` while morale < `morale.leave_below`.
- **Morale** ∈ [0, 1] moves toward its target by at most `morale.ease_per_s` per second (stable at any
  step). The target, clamped to [0, 1], is:
  - `morale.base`;
  - plus Σ amenity gains: each working building's `morale` effect, per level;
  - minus dread, `max(0, workers / max(living, 1) − morale.dread_ratio) · morale.dread_k`, in worker
    units;
  - minus a death shock (`add_shock`, called from E3), which decays as `e^(−t / morale.shock_s)`. A
    working Statue multiplies each new shock by its `death_shock_mult`.

  `view_town` lists these terms as factors: `base`, `amenity:<building_id>`, `dread` and `shock`.
- **Interaction.** Each living agent cycles home → market → inn. Every stall sale is a trade event,
  which the town view draws as an arc between a living and an undead agent. The arcs are sampled, at
  most `view.max_trade_arcs`.
- **Upkeep.** Each working building pays its `upkeep {gold, bone}` per second from the stocks, after
  the step's income.
  - **Unpaid.** When a stock can't cover it, one building goes idle (flag `unpaid`, event
    `building_unpaid{lot_id, building_id, unpaid: true}`), and it repeats until the bill fits. The
    pick is by **shed order** (R1, the run's manager's rule): each building's `buildings.json`
    `shed_class`, in the order of `economy.json` `upkeep.shed_order`:
    1. `decoration`: buildings whose only effects are morale-like (the Plaza; the Statue, morale and
       its `death_shock_mult`);
    2. `passive`: the other no-job buildings (houses, the Well, the Bakery, the Inn, the Graveyard,
       the Embalmer, the Stables, the Ossuary Tower, the Guildhall, the Watchtower, the Walls, the
       Reliquary; the crypt, which has no upkeep);
    3. `job`: the job buildings outside the WAR chain (the Market, the Forge, the Chapel of Vats);
    4. the WAR chain last: `war_mill` (the Bone Mill), then `war_haul` (the charnel houses), then
       `war_pit` (the raising pits, the very last).

    Within a class the cheapest by its upkeep in that stock goes first, ties in lot order. Only
    buildings with upkeep in that stock are picked, so never the crypt. A building that earns that
    stock (stalls for gold, mills for bone) is never picked, because idling the only earner would
    lock the town out of ever paying again. What is still owed is paid down to 0.
    - **Why** (the E2b-2 vision review: "cheapest-first is backwards for this game: it kills the
      thing that holds the forts"). Cheapest first idled the raising pits (0.03 gold/s) before the
      Statue, the Reliquary and the Walls. pre_vei's gold floor (7 692 s, one Market's 0.60 gold/s
      against 1.07 of upkeep) then took its WAR from 41.9 to 0.95 mass/s for 179 s, then a plateau
      of 16.4 (mint 51.7 to 20.8). With the shed order the floor sheds only decorations and passive
      buildings (0.49 gold/s of them) and the WAR holds: its 60 s mean stays 41.9–42.2 through the
      floor and over the last hour of 12 h is 42.0 (mint 52.2; 12 h at 0.5 s from pre_vei).
    - **The charnel houses are in the WAR chain**: their haul is most of the pits' bodies. From
      pre_vei with every charnel house held unpaid for 2 h at 0.5 s (before its gold floor), the WAR
      over the last hour was 32.93 mass/s against 41.95 paid (−21.5%; the pits' feed 0.13 against
      0.60). The manager's exception (keep them ordinary job buildings) needed under 1%.
    - The class is a key, not derived from `jobs` and `effects`, because the charnel houses' place
      came from that measurement, not from their keys. `test_game_state_commands` checks each class
      is in the order and agrees with the building (no job for a decoration or a passive building,
      only morale-like effects for a decoration, jobs for the rest).
    - A building that resumed inside the step (Resume, below) is billed only for the seconds it was
      paid, from its resume to the step's end. If the same step's cascade then idles it, the
      cascade takes exactly that off the bill, so it pays nothing for the step and the buildings
      still paying are billed their own upkeep and no more (since `72dfd81`).
  - An unpaid building gives no slots and no output. It keeps its **capacity effects** (`body_cap`,
    `gold_cap`, `bone_cap`, `relic_cap`, `essence_cap`, `living_cap`, `vat_slots`, `stance_slots`,
    `craft_slots`: `TownSim.CAPACITY_EFFECTS`, §4.2) at its built level, so no cap falls and no stock
    is lost while it is unpaid or when it is paid again (R1, the manager's condition; `test_town_sim`
    and `test_game_state_build` check each key both ways with its store full).
  - It keeps its **tier and unlock contribution**: `count_built` counts a building past its first
    build whatever its state, so `next_tier`, the tier rise and `needs_building` count an unpaid
    one, and the lots follow the tier, which never falls (`test_game_state_build`).
  - **Resume.** It stays unpaid for at least `upkeep.unpaid_hold_s`. It resumes (`unpaid: false`)
    at the first moment its stocks cover the paying upkeep plus its own for
    `max(unpaid_hold_s, dt)`, so it doesn't chatter. Inside a step that moment is solved on the
    stocks' paths: each starts at what it held before the step's income, which comes in at a
    constant rate, and pays the working buildings' upkeep as it goes. Buildings resume in the order
    of their moments, ties in lot order. Each raises the upkeep the next must cover, and each pays
    its own from its moment on.
    - **The income test** (E4 step 4, the run's manager's ruling (i) on the gold-trap stop; gold only, since
      all upkeep is gold): it resumes on its own only while the gold income exceeds the paying upkeep plus
      its own by `upkeep.resume_net_min` (0: strictly positive). The stocks condition above still applies.
      **One margin** (the E4 step 4 review's must-fix): the test reads the income from state (`TownSim.gold_income`,
      as the gate below and the views do), not the step's `gold_in / dt`, and passes only when the income beats
      the bill by more than `resume_net_min` + `BuildRules.NET_EPS` (1e-9 g/s, float noise), so a tie, an income
      equal to the paying upkeep plus its own, stays unpaid at every step size. pre_vei's second House sits on that
      tie (0.60 g/s). Before, the test read `gold_in / dt` with no epsilon, so a tie resolved on rounding that
      depended on the step, open against closed (`test_gold_trap`'s tie case).
      A building that earns gold (stall jobs) or has no gold upkeep is exempt, as in the shed order.
      Without the test, any surplus was spent re-admitting the next building, so the gold pinned at one
      hold of upkeep while anything stayed unpaid (BALANCE §6, the absorbing state): sessions sat at 27.00
      gold from day 5, and no entry costing more, the Market level that would pay its way out among them,
      could start. With it a town whose income can't pay everything keeps the rest unpaid and saves the
      surplus (pre_vei: +0.01 g/s, past the Market's next level in about 20 min). A building held by the
      test reads `upkeep` as an upgrade's queue reason and `waited_on` (not `unpaid`), and the away report
      lists such buildings with the income and "Build a Market" (`idle.report.unpaid_upkeep_fmt`), or, while the
      living buy less than the stalls can sell, "build housing or an Inn" (`unpaid_upkeep_living_fmt`, Phase I P2). The
      Thrift stance's resume of the buildings it idled is unchanged; no command resumes an unpaid one.
      Thrift's resume runs no income test (`TownSim.thrift_resume` sets them active), so when it stops acting
      with the income still short, the shed order sheds them again at the next gold floor and the income
      test then holds them unpaid: one cycle, not a thrash (the E4 step 4 review's item 5).
    - E2b T4.C: they used to be checked at the step's end, in lot order, on the stocks before the
      step's upkeep was paid. From pre_vei's gold floor a 10 s step resumed the raising pit
      (lot-02) at 7 804 s. The gold had crossed the house's (lot-05) lower threshold first, and,
      net of upkeep, it reached neither until 7 847 s and 7 853 s. The pits and WAR came back about
      45 s early, and three forts Vei had refilled with living fell instead of holding. Vei's dead
      were 31.9% off at 10 s over 12 h; now 0.50%.
    - The resume order doesn't follow the shed order (R1): the cheapest threshold is crossed first,
      so the cheapest unpaid building comes back first, whatever its class. Kept, because it doesn't
      flicker: from pre_vei over 12 h at 0.5 s its floor (7 692 s) sheds the Statue, both houses, the
      Well, the Bakery, the Inn, the Graveyard, the Watchtower and the Walls (7 694.5–7 695 s), then
      the two houses resume (8 579.5 s, 8 609.5 s) and nothing is shed again: no building resumed and
      went unpaid again within `unpaid_hold_s`. The gold then sits at 18 (30 s of the 0.60 gold/s the
      paying buildings cost, which the stalls' 0.60 exactly pays). Since E4 step 4's income test the
      second House stays unpaid (resuming it would leave the net at 0), so the gold climbs at +0.01 g/s.
  - Stocks never go negative and there is no debt.
- **The gold and bone caps** (IDLE §6, E2b-2 T3.2). `gold_cap = gold.cap + Σ gold_cap` and `bone_cap =
  bone.cap + Σ bone_cap` (`economy.json`; the Market's and the Bone Mill's per-level `effects`, capacity
  effects, so unpaid or mid-upgrade levels count). The Market's is a number, 3 250 a level (6 500 to
  32 500 at its level 8); the Bone Mill's is a table per level (T7: an Array effect is the value at each
  level, as the Charnel House's `body_cap` is), caps 300, 350, 550, 900, 1 450, 2 250, 3 600, 8 600 at
  levels 1–8 over the base 200. Only what came in is clipped, and the clip is exact
  inside the step for constant rates (one 10 s step ends with the stock and the overflow of twenty 0.5 s
  steps, from under the cap or over it; `test_town_sim`). A store at or under its cap fills at income −
  upkeep and what would pass the cap overflows: the body store's rule (§4.1), what ends above `max(cap,
  S0 − upkeep)`, `S0` the store before the step. A store over its cap (a demolished Market or Bone Mill,
  an old save, a debug grant, which isn't clamped) keeps its excess and earns nothing while over it:
  every coin in overflows and the upkeep (and spending) draws it down. When the upkeep outruns the income
  it reaches the cap `(S0 − cap) / upkeep` into the step and runs on uncapped below it, so the overflow is
  income × min(dt, that moment) (T3.2's review: the step-end rule booked nothing there at a long step).
  Gold's floor of 0 and upkeep are unchanged. The overflow goes to the currency tally `ledger().stores` (§2.1), and TownSim's
  `rates.gold`/`rates.bone` carry it as `overflow`, with `in` net of it (the body store's convention), so
  `view_rates` and the HUD read the store's real net rate: 0 at a full store. The sizing is BALANCE §5.
  - Known edge: the unpaid-resume solver (Upkeep, above) reads the stocks' paths without the cap, so it
    could resume a building a few seconds early at a long step if a cap sat below the 30 s of upkeep a
    resume needs. No cap is anywhere near that (BALANCE §5).

### 4.4 Buildings
`configs/buildings.json` (economy) holds:
- cost (gold, bone, relics), upkeep, `build_work`;
- jobs (slots), effects;
- `requires` (blueprint, tier, building), `lot_size`, `max_level`, `level_costs`.

`configs/buildings_view.json` (town) holds labels, silhouettes and flavour. `configs/town.json` lot
ids and sizes are API, written by economy at E1. The town unit may move positions only.

**Tiers:**
- **Hamlet** to start;
- **Village**: 6 buildings including a market and a house;
- **Town**: 12 buildings including walls and a chapel;
- **City**: 20 buildings including a reliquary.

The tier rises by itself, in the substep the requirements first hold (`economy.json`
`town.tiers.<tier>.requires`; `tier_up{tier, from}` once per rise), and never falls: demolishing a
required building later does not take the tier away. Each tier opens lots by explicit id list
(BALANCE §5); `cmd_build` refuses a locked lot. A tier-up is a set piece (the walls draw themselves).

**Tier-gate fix (T2.4, manager ruling).** A building that *defines* the next tier must be buildable
in the tier before it, or the tier could never be reached: Walls and the Chapel of Vats are
buildable at **Village** (they make Town), and the Reliquary at **Town**, with its blueprint (it
makes City). Every other gate is as it was. Walls and the Reliquary are the only size-3 buildings and
the town has two size-3 lots, so lot-23 opens at Village and lot-24 at Town.

**Upgrades.** A building mid-upgrade works at its old level (slots, output, upkeep, effects, caps)
until the new level completes; the construction adds `job.build.slots` build slots. A cancelled
upgrade refunds in full and changes nothing else.

**The build queue** (IDLE §5, E2b-2 T3.2; `BuildRules.queue_walk`, STATE-API §4.3, §5.9). GameState keeps an
ordered list of entries `{building_id, lot_id, upgrade, waited_on}`, saved. From Phase I P2 (IDLE §5's queue rule)
`queue.max_len` (8) counts only the entries that hold a slot: a `skipped_gate` entry holds none, and the whole list
caps at `queue.max_len` × `queue.list_mult` (16). Phase I P3 (A14's amendment, STATE-API §10): the walk gives the
slots to the first `queue.max_len` entries no gate holds, in list order (a `next` row holds one until it starts); any
later one is `skipped_gate` `wait_slot`, holding nothing, so the slots never pass `queue.max_len`.
Everything else an entry shows is derived from today's state by one walk, which `view_town().queue`,
`cmd_queue_build` and the core step's processing all run, so a status always says what the next
processing does.
- **What `cmd_queue_build` refuses:** only what waiting can never make valid: `queue_full` (the list at its cap, or
  a slot-holding entry with the slots full: STATE-API §4.3),
  `unknown_building`, `unknown_lot`, `unique` (one stands, is under construction or is queued),
  `lot_taken` (a building stands or is under construction there), `lot_too_small`; for an upgrade
  `empty_lot` (nothing stands or is queued there) and `max_level`; and `cost_exceeds_cap` (a gold, bone or
  relic cost above that store's cap now; it names the store, the building that raises its cap, the first
  in `buildings.json` with that `*_cap` effect, and `cap_level`, the lowest level of that building whose
  cap covers the price: 1 when it isn't built yet, −1 when no level does). Affordability never refuses:
  it holds the queue (unless no income can pay it: the walk below).
- **What it accepts as a gate** (the run's manager, 2026-11-14: IDLE §5 over api-request #3's wording,
  since growth while away is Shawn's ask): `needs_tier`, `needs_blueprint`, `needs_building`,
  `lot_locked`, a relic shortfall (`no_relics`), and for an upgrade a construction under way on its lot
  (`under_construction`) or an unpaid building (`unpaid`). A gated entry shows `skipped_gate` with that
  reason and is re-checked every step.
- **The upkeep gate** (E4 step 4, the run's manager's E4 ruling (3), plan.md 2026-11-15 02:22: "a queued build
  whose upkeep would take net gold negative waits with a reason"): a new building is gated `upkeep` when the
  stalls' gold income now (`TownSim.gold_income`: min(staffed stalls · `stall.rate`, living · `shop_rate`) ·
  price · a Market foreman's multiplier, read from state, so it is the same before a load's first step) is
  under the gold upkeep of every building on the walk's lots (working, unpaid, Thrift-idled, under
  construction, and the entries this walk starts ahead of it) plus its own. It is judged by the resume rule's
  one margin (§4.3's income test, `TownSim.income_pays`): the income must beat that bill by more than
  `upkeep.resume_net_min` + `NET_EPS`, so a net of exactly 0 waits too, and a building the gate lets in can always
  resume once shed (the E4 step 4 review: the gate used to admit a net of 0 that the resume rule refused). A
  building with stall jobs is
  exempt (the shed order's rule: holding it could never pay the bill back), as is one with no gold upkeep.
  Upkeep is flat per building, so an upgrade adds none and is never held. It is a gate, not a funds wait: the
  entries behind it start, so a Market level queued after it can pay for it. It closes the gold trap's way in
  (BALANCE §6), not the trap itself.
- **The level an entry builds:** 1 for a new build. An upgrade builds one level above what its lot will
  have once every entry ahead of it for that lot, and the construction under way there, are done: two
  queued upgrades of a level-1 lot build 2, then 3. The level is recomputed from the order on every walk,
  so a reorder moves it; its cost is `construction_cost` at that level and its `work` `build_work ·
  level`. An upgrade's building is the one on its lot when it was queued, or the first new build queued
  there.
- **The walk**, in queue order, on a copy of the stocks and lots:
  - an entry blocked by a gate is `skipped_gate`, stays in place, and the walk goes on;
  - the first entry that isn't gated is the head. When gold and bone cover it, it is `next`: the copy pays
    its cost and takes its lot as its start will, and the walk goes on to the next head. Otherwise it is
    `waiting_funds` (`no_gold`, `no_bone`) and every later entry that isn't gated is `queued`.
  - Phase I P3 (ruling 3, "never stalls"; STATE-API §10 A15): a head short of funds that reads −1.0 at the walk's
    stocks (`BuildRules.head_dry`: `_afford_at` on a timeline from those stocks at `queue_net`'s rates) is
    `skipped_gate` with its `no_gold` / `no_bone` instead, holding nothing and no slot, and the walk goes on to the
    next head: at once when that store's producer has no staffed hands (no staffed `mill` job for bone, no staffed
    `stall` for gold), else once its entry's `never_since` is `queue.never_hold_s` (600 s) old. The core step's
    processing sets `never_since` the first step a head reads dry and clears it at any step it doesn't, and
    `Catchup.build_start_s` clips at the hold's end, so a catch-up skips it when live play does.
  - So several affordable entries can start in one step, in order, and build at once on the build job.
- **The manager's four rules for gated entries:**
  1. **A gated entry never stalls the queue.** The head is the first entry that isn't gated. When a gate
     clears, the entry starts at its own position: it never jumps an earlier entry that waits for funds.
  2. **A gated entry holds nothing.** It reserves no gold, bone or relics, claims no lot and (Phase I P2) holds
     no slot toward `queue.max_len`. If another
     entry or the player's `cmd_build` takes its lot first, it turns `skipped_gate` with `lot_taken`, and
     stays for the player to see and unqueue; it is never dropped silently. Two queued builds on one lot:
     whichever starts first takes it. An upgrade behind an entry for its lot that hasn't started shows that
     entry's gate (or `queued` when it has none).
  3. **The away report says when a gated entry started and why.** Each entry keeps `waited_on`, the last
     reason that kept it from starting (`""` if it never waited): a gate, or `no_gold`/`no_bone`. It is set
     when the entry is queued (from that first walk) and by each step's processing, never by a view. An
     entry `queued` behind a head that waits on funds takes the head's `no_gold`/`no_bone` (the funds hold
     it now, whatever gate held it before; T3.2's review), so starting in the head's step reads "when the
     funds came". `queue_started` carries it.
  4. **A relics-blocked entry reads as the plateau's ask:** its reason is exactly `no_relics`, the key
     `view_catalog` gives a row the relics can't pay for, with the same `cost.relics`. The keys match when
     gold and bone are covered; short of gold or bone as well, the catalog says `no_gold`/`no_bone`
     (`afford_reason`'s order) while the queue still reads `no_relics`, since relics are a gate there.
- **When each entry becomes affordable** (R2, the E2b-2 vision review's item 3; the run's manager for Shawn:
  the queue never stalls or jumps, so the player gets the data instead: "data, not a skip"). The same walk
  sets each entry's `affordable_in_s` (STATE-API §5.9), `0.0` affordable now, the seconds until it is at
  the current net rates, `-1.0` never at them:
  - **net rates:** each store's net now, income less upkeep, from TownSim's last step: the HUD's and
    `view_rates`' net below the cap; at the cap, where theirs clips the income to the upkeep and reads 0, the
    income before the clip (`trade`, `mill`) less the upkeep, since an entry ahead that spends the store
    brings it back. Relics have none, so a relic shortfall is `-1.0` ("raid for relics"). Catch-up's clip at
    the head's start (`Catchup.build_start_s`, IDLE §4) reads the same helper, `BuildRules.queue_net`, since
    F1, so the two never drift (it read the HUD's clipped net before, which agreed below the cap only);
  - **in queue order:** the entries that aren't gated start in order, each when the stocks, grown at those
    rates up to their caps and less what the entries ahead paid at their own starts, cover it. Up to the head
    those stocks are the walk's own copy, so `next` reads `0.0` and `waiting_funds` never does, and no entry
    reads earlier than the one ahead. A `skipped_gate` entry holds nothing: its time is its own funds' there
    ("affordable in 4 m once Walls are up"), and it pays nothing;
  - **`-1.0`** when a cost is above its cap now, a relic cost is short, a short store's net is ≤ 0, a store
    that covers it now runs under it at a negative net by then, or it costs any of a store that an entry
    ahead holding the queue never gets. An entry that costs none of that store is timed as if that one were
    moved down;
  - **held fixed:** the rates don't move with what the entries ahead build (a new building's upkeep or
    output isn't modelled: E4-3 decides what a build that would run a deficit does), and gates met later (a
    construction under way on the lot) aren't either. `cmd_queue_build` returns the new entry's, the warning
    at queue time. The away report names a head still waiting when you come back (IDLE §7).
  - **day1's first overnight** (the review's case): a House, a Well, a Bakery, then a Bone Mill. The House
    and the Well start at once, the Bakery on gold (+0.21/s) and the Mill behind it on gold too: queued, they
    read 0, 0, 190 and 476 s. Until F1 the Mill's level 1 cost 20 bone, the last of day1's 30 once the other
    three had theirs, and only a mill makes bone, so bone's net was 0 and the Mill read `-1.0` from the moment
    it was queued: a deadlock (the review found it on gold, upkeep matching income at 4 gold; at T7 it was the
    bone). Its level 1 is gold only since F1 (BALANCE §7's rule), and `tests/test_day1_queues.gd` runs that
    queue and town's trial order (Bone Mill, House, House, Well, Well, Bakery, Well, Well) 8 h through a load:
    every entry starts, the first at 7 s, 7, 207 and 538 s (the Mill later than its 476 s since the three
    ahead add upkeep the time holds fixed) and the second by 26 min.
  - **cost:** `view_town` runs the walk once on every call (Covington fetches it on each rev change). The
    times add 24 to 30 µs a call with a full queue of 8 (day1 +23.5, midgame_2flips +28.5, pre_vei +30.2:
    the timed walk against the untimed one, 79.5 → 103.0, 99.7 → 128.1 and 103.5 → 133.6 µs; `view_town`
    itself 292, 396 and 799 µs; the medians of five 400-call runs on a loaded machine, re-measured once at
    F1, where R2's figures disagreed, +20 to +45 here and +11 to +32 in its report), under the 0.2 ms that
    would need a cache on `rev`, so there is none. The core step's processing runs the
    same walk without the times (`queue_walk(..., false)`: it reads only the statuses), so live play and
    catch-up pay nothing for them: 76, 98 and 105 µs against 79, 98 and 105 before (a week's catch-up is
    about 42 000 steps, and a queue that sits all week is the case R2 is for). The two walks give every
    entry the same status, reason and waited_on and start the same entries (F1, from R2's spec review:
    `test_build_queue`'s untimed check, over the three fixtures with full queues, a step in and a minute on).
- **Processing**, once per core step, right after `BuildRules.rise_tiers` (§1.3 step 3), so a tier that
  rises this step opens its entries this step and this step's income counts: one walk, then each `next`
  entry starts through `cmd_build`'s or `cmd_upgrade`'s own path (paying its cost), in order, leaves the
  queue and emits `queue_started {building_id, lot_id, level, upgrade, waited_on}` at the step's `t`. Every
  entry that stays and was skipped or waited on funds keeps that reason as `waited_on`.
- **At any dt** (`tests/slow/queue_dt.gd` measures it; T3.3b re-measures with a build-start clip) the queue
  starts entries at step boundaries, so a start is up to one step late at a long
  step (the funds or the tier arrive inside it). Measured over 12 h of `midgame_2flips` (core steps, the
  field frozen) with a full queue of 8 (two house and well upgrades, an inn, a graveyard, stables, and
  the pit's, the market's and the mill's level 2; T3.2): the five entries affordable at once start 9.5 s
  later at 10 s (one step); the pit's and the market's upgrades, which waited on gold, 223.5 s later
  each (mean 70.6 s over the 7 starts). The 10 s run's gold ran 2.2 behind from the first constructions
  on, since a construction ends on a step boundary and its builders (top of the ladder) keep the stalls
  short a little longer, and with the new upkeep the town saved about 0.01 gold/s, so 2.2 gold took
  about 220 s. End of run: gold 9 261 against 9 330 (−0.74%), bone 29.2 against 28.5, the same levels
  everywhere; the mill's level 2 waits on bone in both. With no queue the two gold paths are identical.
  - Re-measured at T7, with the dead's buildings bought with bone (BALANCE §7): midgame_2flips earns no bone,
    so the suite starts the mill at level 2 (its queued level is 3), the bone at the queue's whole bone and
    the gold at the first five entries' and 10 more. The five start 9.5 s later at 10 s (one step); they
    finish at 90 s against 80 s, so their upkeep (about 0.17 gold/s) starts 10 s later and the 10 s run's
    gold runs 1.74 ahead from then on. At the town's +0.010 gold/s that is about 170 s, so the three entries
    that wait on gold (the pit's and the market's level 2, the mill's level 3) start 168.5, 168.5 and
    161.5 s **earlier** at 10 s (mean −56.4 s over the 8 starts): a long step's gold can run ahead as well
    as behind, by the upkeep it saves. End of run: gold 12 424 against 12 372 (+0.42%), bone 50 in both,
    the same entries in the same order and the same levels.

**Every building has a numeric benefit** (vision review S7). From E2b-2 (T3.2, api-request #9) the build
card shows it as the change in each net rate if the building were finished now: `view_catalog`'s
`projected` and `view_town`'s `upgrade_projected`, TownSim's own step run on a copy with the building
finished against a copy without (STATE-API §5.10). The table is the design intent:

| building | benefit | gate |
|---|---|---|
| Crypt | holds the slab; idle rest; big-undead cap +1 per level above 1 | start |
| Raising Pit | +`P_per_pit` mint; pit job | start (1) |
| Charnel House | haul job; body store cap + | start |
| Market | stall jobs (gold); + gold cap (`gold_cap`, 3 250 per level, to level 8) | start (small) |
| House | + `living_cap` | Hamlet |
| Well, Bakery | + morale, + living cap | Hamlet |
| Bone Mill | mill job; + bone cap (`bone_cap`, a table per level: 100 to 8 400 over levels 1–8, BALANCE §5) | Hamlet |
| Inn | + migration, + morale, + living cap | Village |
| Forge | forge job; levels need relics | Village |
| Graveyard | + body store cap; + worker lifetime | Village |
| Embalmer | + worker lifetime | Village + blueprint |
| Stables | haul trips faster | Village |
| Chapel of Vats | vat slots (view_backups.vats: 2 per level); tend job | Village (makes Town) |
| Ossuary Tower | crafts simulacra and phylactery charges | Town + blueprint |
| Guildhall | + stance slots | Town |
| Watchtower | adds precision to fort hints (exact warden tells, death-risk %) | Town |
| Walls and Gate | Town tier; + morale; + living cap | Village (makes Town) |
| Plaza, Statue of Relish | + morale; the statue softens the death shock | Town |
| Reliquary | + relic and essence caps (6 and 30) | Town + blueprint (makes City) |

### 4.5 The job ladder and stances (D11)
- **The job ladder:** an ordered list of jobs. Workers fill slots top-down. The player drags to
  reorder (`cmd_set_job_priority`), and can cap a building's staffing. That is "how the undead are
  behaving on auto".
- **One allocation** (E2b-2 T4.P): the fill is a pure function of the effective ladder (the ladder
  after stances), each lot's building, state, level and staff cap, the building defs and the
  workforce (`TownSim.staff_allocate`). Every restaff runs it, and so does
  `view_staffing_projection` (STATE-API §5.16) with another order, so a preview never drifts from
  the staffing it previews.
- **Stances:** named, pre-written behaviours the player toggles. Slots: `stance.base_slots` (2), plus
  the Guildhall, plus 1 while Relish is home; when they run short the newest are suspended (on, but no
  effect) until a slot frees. Grow (Phase I P3) takes no slot (`stance.slot_free`) and is never suspended. Each shows its projected effect on net rates before you toggle it. None
  touches the valve (one controller per dial). Live from E3-1 (the run's manager's rulings for Shawn); the
  thresholds are `economy.json` `stance`, v0 (BALANCE §5, E4 calibrates).

| stance | condition (binary) | effect while it acts |
|---|---|---|
| Vigil | Relish is away from home or dead (any state but `home`) | `tend` to the top of the effective ladder |
| Harvest | bodies < `stance.harvest_bodies_frac` (0.3) × the body cap | `haul` to the top |
| Hearth | morale < `stance.hearth_morale` (0.5) | `stall` to the top |
| Muster | idle workers: some stand idle, or the last step mustered some | the idle cap (`worker.idle_cap`) reads 0: every idle worker musters to WAR at once (without it the overflow above the cap musters to Vei's queue, §3.2) |
| Thrift | the stalls' gold income < the gold upkeep owed | idles buildings over `stance.thrift_upkeep` (0.05) gold upkeep, in its order, until the income covers what is still paid |
| Grow | a build or upgrade has finished since the new game (the finished levels total more than `opening.buildings`') | on in a new game (`stance.grow.default_on`), no slot. Right after the queue's processing, while no queue head waits on funds and fewer than `stance.grow.max_active` (1) constructions are under way: starts the upgrade, of a standing building in `stance.grow.order` whose lot has no queue entry and whose next level passes the tier gate, costs no relics and fits under every cap, that is affordable soonest at the queue's net income (ties in `order`, then lot order), once the stocks cover it; it passes over one no income can pay, and a gold-priced one while the gold income can't pay the upkeep (the Market's excepted). P3b (ruling 12, changed): it waits, with no pick, while any building is unpaid (shed). `grow_started`. Below |

- **`active` is the condition alone, for every stance, on or off** (the run's manager). A stance acts only
  while it is on, not suspended and active; an off or suspended stance shows `active` and does nothing.
- **When it is read** (STATE-API §3 step 1). Each core step starts with the stance step: at a new beat
  (`floor(t / beat_s)`, `pulse.json` `tempo_ms`, 1.714 s) every condition is read from the state the step
  starts from (TownSim's after the last step: its staffing, stocks and morale; Relish's state). Which
  stances act (the toggles and the slots) is applied at the start of every core step, and at once by
  `cmd_set_stance`, so a slot that goes with Relish suspends a stance's effect from the next step.
- **The hold.** A stance's `active` can't change again until `stance.hold_s` has passed since its last
  change (20 s; `hold_s_left` shows what is left; BALANCE §5 has why). Each change emits `stance_fired {stance_id, active,
  beat_id}` and sets `fired_beat_id` to the beat; one that never changed reads −1. The hold is at least
  catch-up's longest step (IDLE §4), so a catch-up step changes a stance at most once, as live play would.
- **Conditions that their own effect would undo.** Muster's effect leaves nobody idle, so "idle workers"
  alone would switch it off a step after it acts and on again a hold later; it reads the last step's muster
  too, so it holds while the town makes more hands than it has work for. Thrift's upkeep counts the buildings
  it idles as paying (what the town would owe without Thrift), so idling them doesn't switch it off; it stops
  when the income covers the whole bill again.
- **Several lift at once:** their jobs go to the top in `stance.priority` order (shipped `vigil`, `harvest`,
  `hearth`: Relish's way back first, a tend slot opening only for a staffed vat, so it takes few hands; then
  the pits' bodies; then the stalls), the rest of the ladder after in the player's order. `stance.top_job`
  names each ladder stance's job (config, checked at setup).
- **Hearth moves the stalls only.** The table used to say "stalls and the inn"; `buildings.json` gives the Inn
  no job slots, so nothing of the Inn can move up a ladder.
- **The effective ladder and the rooms.** The stances change `ladder_effective` (`TownSim.effective_ladder`:
  the lifted jobs on top) through `TownSim.set_top_jobs`, which marks the room cache (it is keyed on the
  player's ladder), so the one allocation restaffs at once.
- **Thrift** (the run's manager's ruling, applying R1):
  - **Reach:** only buildings whose `shed_class` ranks before `stance.thrift_spares_from` (`war_mill`) in
    `upkeep.shed_order`: decorations, passive and job buildings; never the WAR chain (Bone Mill, charnel
    houses, raising pits) at any level, and never a store's earner (a building with stall or mill jobs: the
    Market). Upkeep is the same at every level (`buildings.json` `upkeep`), so "over the threshold at its
    level" is its one figure.
  - **Order and amount:** when Thrift starts acting (its condition turns active while it is on, it is turned
    on while active, or a slot frees for it) it idles the eligible working buildings one at a time in shed
    order (the decorations first), the dearest first within a class, ties in lot order, and stops once the
    stalls' income covers the upkeep still paid, or nothing eligible is left (`TownSim.thrift_pick`). The
    income is today's: a job building idled frees hands the stalls may then take, which isn't counted, so it
    may idle one more than it needed. A building mid-upgrade isn't picked. The set is kept while it acts: a
    deficit that grows later falls to the shed order at the gold floor (§4.3), as before. When Thrift stops
    acting (inactive, off or suspended), every building it idled resumes at once and pays from that step.
  - **An idled building** takes TownSim's state `thrift`, which `view_town` shows as `"idle"` (STATE-API §5.9:
    "no staff, or a stance idles it"): like an unpaid one it offers no slots, gives no output and pays no
    upkeep, and keeps its capacity effects (its caps) and its tier count (`count_built`). It never resumes by
    the upkeep's rule, only when Thrift stops acting. An upgrade can't start on it meanwhile: `cmd_upgrade` is
    refused `unpaid`, and a queued upgrade waits on `unpaid`, until Thrift lets the building go (then it starts
    as for any working building).
  - The away report names Thrift as the reason, not the gold (IDLE §7).
  - **It doesn't flicker** (R1's measure, the run's manager: no building idled and resumed again within
    `upkeep.unpaid_hold_s`, 30 s; `slow/stances_catchup`): from pre_vei with Thrift on, 12 h live at 0.5 s,
    Thrift turns active at the first beat (2.0 s) and idles the Statue, the Walls and the Reliquary from that
    step's start (1.5 s), 0.47 gold/s of upkeep, and nothing else switches in 12 h: the stalls' 0.60 gold/s pays
    the 0.60 left, so the gold holds at 3 616 and never reaches the floor that sheds nine buildings at 7 692 s
    with no stance on (§4.3). 0 `building_unpaid`.
- **Projected** (`view_stances().stances[].projected`, STATE-API §5.11): the change in each net rate per second
  if the stance were toggled now, from the one allocation (`TownSim.staff_allocate` on the effective ladder
  the toggle would make, with Muster's cap and Thrift's buildings) and the flows TownSim's step runs on that
  staffing, against the same for the stances acting now: pure, no rev, no event.
- Firings show in `view_stances()` with `fired_beat_id`. The town scene flashes the affected agents
  on its next visual beat (for every stance's change, on or off, since `active` is for every stance).
- **Grow** (Phase I P3, Q-b: the run's manager's ruling of 2026-11-18, option (a); STATE-API §10 A17). Shawn's lever
  for an idle imbalance ("we can play with conditional stances if we feel there is an imbalance"), for his never-raid
  target: 2–3 days of real idle growth, then a visible wall. `BuildRules.grow_target` picks, `grow_step` starts,
  `grow_start_s` is catch-up's clip.
  - **Its own path, not the queue.** It starts an upgrade only when the stocks already cover it and no queue head waits
    on funds, so it never takes what the player's queue is saving; a parked (gated) entry holds nothing and doesn't
    stop it, and a lot with any queue entry is left to the player. A pick it can't afford yet holds nothing.
  - **What it never does:** build on an empty lot (the lots are the player's plan), spend relics, start a level behind
    the tier or over a cap (re-read as the caps rise), or start a burst: at most `max_active` (1) constructions under
    way, anyone's, since builders sit at the ladder's top, 3 to a site.
  - **It spends no gold a short town lives on** (the run's manager's ruling 1 on P3's handoff 5): a level with a gold
    price is passed over while the gold income can't pay the working buildings' gold upkeep (`TownSim.income_pays` at
    `gold_income()` and `gold_due()`, the margin `held_by_income` reads; a level adds no upkeep, which is per
    building). A building that earns gold (the Market) is exempt: its level is the income. Without it, pre_vei's Grow
    spent the stock on the living's levels and shed nine buildings 57 min in, against 2 h 8 min with Grow off.
  - **It waits while any building is unpaid (shed)** (P3b, the run's manager's ruling 12, changed;
    `BuildRules.any_unpaid` in `grow_target`): no pick at all, since the gold an unpaid building waits on isn't Grow's
    to spend. A Thrift-idled building doesn't hold it. `view_stances.grow` then names no pick (`building_id` `""`,
    `in_s` −1).
  - **The wall stays visible:** once every standing building is at its last relic-free level, Grow has no pick and the
    queue's parked relic entries are what's left.
  - **The step:** right after `process_queue` in the core step (§3 step 3), on the state the processing left; a step
    starts as many as the cap allows, each picked on the stocks the last left. Catch-up clips at the pick's time
    (`Catchup.next_event_s`), and a construction finishing (which frees the cap) is a clip already, so a catch-up
    starts it within the live run's substep (`test_grow`).

### 4.6 The crypt slab: big undead
- Only while Relish is home. The town scene's crypt view runs SlabLogic's live preview (ported from
  `slab/`: build_state, namer, role, live morph, hold-to-raise).
- **The raise:** `cmd_raise_big_undead(husk_uid, remnant_uids, name)`, live from E3-3 (v8). GameState
  validates the inventory and computes the stats with the town unit's `SlabLogic.evaluate(the husk's kind,
  the remnants in the order given, town.json slab)`, which the sim calls (it is RefCounted, no Engine) and
  the town scene owns. The refusals, in order: `not_home`, `unknown_husk`, `unknown_remnant`,
  `duplicate_remnant`, `invalid_recipe` (SlabLogic says not ok), `at_cap` (the cap below), `bad_name` (empty
  or over 24 characters after `strip_edges`). A raise consumes the husk and exactly those remnants, mints
  `u<n>` from the save's uid counter and stores `{uid, name, kind, role (SlabLogic's role id), stats
  (SlabLogic's), place: "crypt", front: "", filled_slots (SlabLogic's filled)}`. No event.
- **`filled_slots`** (api-request #6) is on every big-undead entry, both seeds' party and the save. One
  saved without it (a fixture's, any save before v8, a debug grant's) reads 1, the one slot the dungeon and
  the Vei fight drew before, so it fights as it did (the run's manager's ruling).
- **Stats** (one stat, one watchable verb):

  | stat | used by |
  |---|---|
  | power | the **raw** front; a warden's armour |
  | beef | the **carvers** front; survives warden slams |
  | wits | the **giants** front; flank roles vs Shieldwall |
  | presence | the **swarm** front; morale as a town foreman |
  | speed | foreman throughput; dungeon pace; Huntsman interception |

  The specialist-or-all-rounder decision pays off on the fronts (vision review M4).
- **Placement:**
  - town foreman (`town:<lot_id>`);
  - fort siege (`fort:<id>`), which blocks `tithe.siege_block` (0.6) of a tithe wave there (§3.4; live from
    E3-3). One siege per fort counts: a second is allowed and adds nothing. The block is flat, whatever the big's
    stats. A siege adds no kill power (the run's manager's ruling): that isn't built, and goes to E4 only if the
    hold band needs it;
  - the party (`cmd_set_party`);
  - the crypt.
- Cap: `big_undead.cap` (4, + `big_undead.per_crypt_level` per Crypt level above 1). They die only in dungeons or the Vei fight.

## 5. Micro: dungeons

### 5.0 Controls (from the existing scene and R&R; the dungeon unit keeps these)
| input | action |
|---|---|
| left click | move Relish |
| hold SPACE or right mouse | **trance**: world time × `trance.time_scale` (0.35), lines dim, essence ignites; capped at `trance.max_hold_s` (4) |
| left drag in trance | trace a circle. The Kåsa fit flashes the ideal ring and the integer score |
| release | raise; cooldown `trance.cooldown_s` (6), shown on the button |

- **Relish never attacks.** HP is `relish.hp`.
- **Lethal hits follow the sacrifice chain:** nearest chaff, then a soldier, then a big undead in the
  party, then Relish. The chain soaks everything except a warden's tell-attacks, which strike her directly.
- Your undead fight on their own.
- Essence lives `essence.lifetime_s` (12, longer than the cooldown).
- **RTS-drift guard:** the scene logs move clicks against raises. A ratio above 8:1 is a design smell,
  reported in telemetry.

### 5.1 Entry and seed
- `cmd_begin_dungeon(fort_id)` returns a seed (the full fields are in STATE-API):
  - `run_id`, `rng_seed`, the fort (tier, cap);
  - living, dead, your undead there;
  - the party from `cmd_set_party`;
  - `digest_q`, phylactery charges, clones ready, and what a death that ends the run ends in (`death_ends
    {outcome, respawn_s}`, view_backups' rule; E2b-2 T3.3c);
  - the warden spec, the loot table id, `relish_hp`.
- **Party:** your undead at the fort, converted to units by `raid.garrison_mass_div`, plus your
  chosen big undead.
- **The first dungeon** guarantees a starter party of `opening.starter_party` and a husk in its chest.

### 5.2 Before you descend (threat in advance; vision review M5)
Every fort card shows, **from the start**:
- the warden archetype's name and its tells, read from `raid.json` `wardens.archetypes` (the
  dungeon's own text, one source with the fight: `view_fort().warden`);
- the loot hint, read from `loot.json` `hints` (the first dungeon's `first_dungeon_hint`, else
  `hints["t<tier>.<archetype>"]`);
- the party strength against the garrison;
- the projected death risk (low, risky or deadly).

The Watchtower turns the bands into exact percentages and lists every tell.

### 5.3 In the dungeon
- **Circles** score 0–100. Every essence mote inside raises one undead with
  `stat_mult = 0.5 + score/100`. Display names stay (<60 chaff, 60–89 soldier, ≥90 elite). Each
  raise feeds `q_raise` (§2.2).
- **Essence (D8):**
  - living deaths drop `essence.per_living` motes;
  - your fallen undead drop `essence.per_undead` motes;
  - motes decay;
  - banked essence counts motes carried out.
- **Last-chance beat:** the warden's antechamber gives one free trance with no cooldown, and every
  mote in the room lit.
- **Wardens** (`RaidLogic.warden_spec`). The first two ship first; the other two follow after
  balance:
  - **Bellringer:** ring slams telegraphed on the tempo; beef soaks them; three phases at HP
    thresholds, each ring faster.
  - **Huntsman:** stalks Relish. Speed interceptors and the sacrifice chain counter it. Its phase
    gate is "Relish caught twice".
  - later, **Shieldwall:** frontal immunity; wits flankers.
  - later, **Pyre-priest:** burns corpses (denies essence); kill its acolytes first.

  Each warden has a weak point that a big-undead stat exploits (shown before the descent). Counters
  are composition, not reflexes.
- **Loot** (`configs/loot.json`):
  - by fort tier and archetype;
  - remnants ding off kills;
  - the warden's chest;
  - a blueprint guaranteed on the first clear;
  - **re-clear yield × `yield_mult`**, which recovers with real time (IDLE §3; E2b-2 T3.1): each
    clear that pays loot (a flip, a counter-garrison clear) sets `yield_c = yield_mult(now) ·
    loot.reclear_decay` and `yield_t = now`, and `yield_mult = 1 − (1 − yield_c) · max(0, 1 − (t −
    yield_t) / loot.recover_s)`. So one clear halves it, two back to back quarter it
    (`reclear_decay`²), and it is back to exactly 1 `recover_s` (8 h) after the last clear, from any
    depth. It is a function of the sim time, so a catch-up refills it with no step work; the dungeon
    seed and `view_fort` read it live. **A retake keeps the spent yield:** `yield_c` and `yield_t` are
    left as they were, so the yield goes on recovering from its last clear (the run's manager,
    2026-11-17, E4 step 6). A fort lost and retaken has already been looted, so losing it must cost,
    not pay. Until then a retake reset `yield_c` to 1, which made the re-flip after each of Vei's
    retakes a full-yield raid: in sessions to day 8 the re-flips paid 54 of 121 relics (45%), so losing
    forts sped growth, against vision review M8's aim of killing the repeat farm. Keeping it, sessions'
    re-flips pay 46 of 107 relics and its Vei-ready moves from day 5.33 back to day 6.0 (one seed, 8 days,
    before the husk craft's re-price; BALANCE §5's loot row).
    A counter-garrison clear is paid only by a fort still held when the result is applied: a held fort
    retaken during its own raid (the realm keeps stepping while she is in the dungeon) banks its
    retreat's loot as usual, but raises no clear and spends no yield, since the fort is Vei's again.
    Saved per fort (`yield_c`, `yield_t`); an older save reads 1, as it showed.
- **Exits:**
  - **warden beaten:** loot banked, fort flips;
  - **retreat** at an exit: loot banked, no flip;
  - **Relish dies:** §7.
- **Writeback:**
  - raised undead (count and mass) go back to the fort's undead;
  - chaff mass goes to Vei's queue;
  - all applied as clamped deltas.

## 6. The final test: Vei
- **Available any time** from Vei's node. The dialog shows:
  - odds, sign, drain time;
  - the four fronts as "have X / need Y";
  - the composition you've assigned (`cmd_assign_front`).
- **Fronts** (`configs/vei.json`):

  | front | cleared by |
  |---|---|
  | giants | big-undead wits |
  | swarm | backlog mass plus presence |
  | carvers | beef plus `q` |
  | raw | power plus backlog |

  Each threshold scales with Vei's living pool. You need `vei.fronts_required` (3 of 4).
  E4 step 3 (the manager's ruling): mass alone clears exactly one front, swarm. Raw needs power from bigs as well as
  the backlog, and giants and carvers need composition. The backlog terms are sized for the live backlog, about 1e8 by
  day 8 (BALANCE §5).
  Live from E3-5: `view_vei` and the boss seed carry each front's have and need, `VeiFronts.have_need` on her
  backlog, living pool, `q` and the party (an assigned member counts on its front, an unassigned one on the front of
  its highest stat), so the dialog, the town's front chip and the fight read the same numbers (STATE-API §5.14, §7.2).
- **Phase 1:** the fronts resolve as streams on the field, horde against her guard, each to its
  threshold. Uncleared fronts keep sending guards in phase 2.
- **Phase 2, the break** (vision review S4: a verb, not HP):
  - Vei is a ferry. She has a **ferry rate** that drains your horde.
  - Relish must **raise at anchor points** (circles around the essence of the fallen) so your raise
    rate beats her ferry rate.
  - The break meter fills one pip per tempo beat on which the raise rate (smoothed over
    `vei.raise_ema_beats`) beats the ferry; she breaks at `vei.break_beats` (20). A beat at or below
    the ferry is a **lapse**: it takes `vei.lapse_cost` (4) pips back
    (never below 0), so the beats need not be consecutive, but a lapse costs about four good beats.
  - Uncleared fronts' guards fall back to the line after `vei.guards.life_s` (6 s) and drop no mote,
    so they never outnumber rate × uncleared fronts × life; the fight can't snowball into a guard pile.
  - **A fuller pool presses harder** (Phase I P1): the break's guards come at `vei.guards.rate_per_uncleared` and
    `cap` × `1 + vei.pressure.per_pool × max(0, living pool − pool_free)` (`VeiFronts.pressure_mult`). Below
    `pool_free` (400) they come as listed; at her full pool of 600 the multiplier is 2.3. Her ferry already scales
    with the pool, and so do the anchor motes that feed Relish's allies, which soak her lethal hits (the sacrifice
    chain). Without this, a full pool made the break easier, not harder (BALANCE §5's fight-grade row).
  - Her weaves hunt Relish, telegraphed on the beat.
- **Backups in the fight:** each Relish death spends a phylactery charge first, then a ready clone.
  None left means the fight is lost. Each spent backup is a cracked violet ring, and from E3-5 the writeback raises
  one `relish_died {in_place: true}` for it, the charges first (STATE-API §8.3 boss step 3).
- **Win:** `won = true`, the victory set piece, the game is beaten. Play continues (endless), with Vei off (§3.4's "After the win", P3b: no tithe, no shipping, FLOOD and the muster to WAR). The win survives a gap, a load or an abort once the scene has called `cmd_boss_won` (P3b, api-request #22; STATE-API §4.5): the open boss run resolves as that win, never a forfeit.
- **Lose:**
  - backlog × `vei.loss_backlog_keep` (0.35 is kept);
  - the party's big undead die;
  - the last death follows §7.

## 7. Death and backups
**Before she dies,** the sacrifice chain (§5.0) soaks lethal hits.

**At HP 0, in order:**
1. **A phylactery charge** (crafted at the Ossuary: `cmd_craft("phylactery_charge")`, `economy.json`
   `craft.phylactery_charge`, 15 essence, from E3-4; §3.6's gate, no stock cap): revive in place at `phylactery.revive_hp`. At
   most `phylactery.max_per_dungeon` per dungeon. The dungeon reports its revives (`revived_in_place`) and
   GameState spends the charges, one `relish_died {outcome: "phylactery", in_place: true}` each (E3-2). It loses
   nothing: the run goes on.
2. **A ready clone:** she wakes at Covington after `backups.clone_respawn_s`.
   - The whole party and any unbanked loot are lost, and the fort doesn't flip.
   - Unbanked loot is capped at what was found since the last checkpoint room, so a 6-minute run
     never loses everything (the dungeon's death result carries its last checkpoint's loot,
     `RaidLogic.result_loot`, and the writeback banks it).
3. **Unmade:** she reforms after `backups.unmade_respawn_s`, with a morale shock. As with a clone, the whole
   party and the unbanked loot are lost and the fort doesn't flip (the contract, STATE-API §8.3 step 10 and
   A8, so the cost order is phylactery < clone < unmade; E3-2 fixed the old "Nothing else is lost", which
   read as keeping the party). Nothing in the town or the realm resets.

**Dead, then the respawn** (E3-2). A death that ends the run (2 or 3) leaves her `dead` at the node she died at,
`dead_s_left` the outcome's respawn time and `respawn_with_clone` which it was. The core step's backups step
(STATE-API §3 step 6) counts it down, and at 0 she wakes at Covington, home (`relish_respawned {with_clone}`).
While dead she is away from home for every rule that reads it: no home stance slot (§4.5), Vigil's condition
holds, her home effects are off (§3.3), and moving her, a descent and the Vei fight refuse with `dead` (STATE-API
§4.2, §4.5); the slab refuses `not_home`. Catch-up clips a step at her respawn (IDLE §4), so a save closed while
she is dead wakes her at the right time, and the stance slot and Vigil follow from there.

**What a death would cost now** (`view_backups().death`) follows this order: `phylactery` while a charge is left
and `max_per_dungeon` lets a dungeon use one (in place, loses nothing), else `clone`, else `unmade`, with the
respawn time and what it loses. A seed's `death_ends` is the death that ends the run, so it skips the phylactery
step (the revives come first) and reads `clone` or `unmade`, as `Results.validate` requires.

**A run that ends without the scene** (a close, a crash, a load, a gap above `idle.gap_s`; IDLE I5, E2b-2
T3.3c) banks the same bound: the dungeon tells GameState what is banked at every checkpoint room
(`cmd_run_checkpoint`, STATE-API §4.5), and the run ends from the last one as a retreat (no flip, Relish
`at_fort`), or as the win or the death when the checkpoint came at the warden's victory beat or the death
beat. Whatever was found since is lost.

**Clones** grow in the vats, from 0 to 1, one clone per vat (E3-2; the run's manager's vat rule: growth ties to the
vats). A vat at 1 holds a ready clone, and `clones_ready` is the vats at 1, plus any spare clones (below): no longer a
free stock.
- **Growth:** a vat grows at `vats.grow_per_s` × its tend hands (0..1) per second (the core step's backups step,
  STATE-API §3 step 6), so a fully tended vat at `grow` is ready in (1 − grow) / `grow_per_s` (an empty one in 300
  s). It doesn't grow while unstaffed, or while staffed but untended (its slot is open but the ladder gave the hands to
  the rooms above it). Unstaffing it stops the growth and keeps the progress. An unpaid Chapel offers no tend slot
  (below), and nor does one Thrift idles, so their vats stop too. The Vigil stance puts tend on top (§4.5).
- **The hands per vat:** tend workers are staffed per Chapel, not per vat (the ladder fills a Chapel's tend room),
  so a Chapel's tend hands go to its staffed vats in slot order, one hand each, the lowest slot first
  (`TownSim.vat_hands`), as the ladder fills its rooms top-down: 1.5 hands on two staffed vats grow the first at the
  full rate and the second at half. A ready vat that stays staffed keeps its hand (it can't grow past 1).
- **Spending:** a death that spends a clone empties the lowest ready vat back to 0, so it grows again; only when no
  vat is ready does it take a spare clone, which never regrows. The boss fight's spent clones (§8.2
  `backups_spent.clones`) follow the same order.
- **Spare clones, the old-save rule:** the vats' `grow` is the truth. A save whose `clones_ready` is above its vats
  at 1 keeps the excess as spare clones outside the vats, so a load never loses a clone; one below them reads the
  vats. Real saves reach it: a v1 save's legacy vats load as clones with no Chapel (STATE-API §9.1), and a save from
  before E3 whose Chapel was demolished kept its stub clones. From E3-2 a demolished Chapel's ready clones become
  spare clones at the next core step, and a Chapel built again starts empty. The save writes `clones_ready` as the
  total, so its shape is unchanged.
- **Catch-up**: the growth is linear and clamps at 1, so each step's update is exact at any length, the fill raises no
  event, and nothing inside a catch-up reads it (no run is open during one). From Phase I P2 catch-up clips at a tended
  vat's fill (IDLE §4, `Catchup.vat_fill_s`), so a ready clone's tend hand goes back to the ladder at the fill, as
  live (below), not up to one catch-up step late.

`view_backups` always shows what a death would cost right now.

**A staffed vat takes a hand** (E2b-2, the run's manager). A Chapel of Vats offers one tend slot per
vat (`jobs.tend` × level tend slots for `effects.vat_slots` × level vats, the same count), and a
vat's slot is open only while that vat is staffed (`cmd_staff_vat`). The job ladder fills the open
tend slots like any other (§4.5). Staffing a vat opens its slot, which takes the hand the ladder
gives it: an idle worker if there is one, else the lowest room staffed below it. Unstaffing it
closes the slot and the hand goes back to the ladder's next room, or idles. The vats are numbered
as `view_backups` numbers them: in lot order over every built Chapel (unpaid or mid-upgrade too, at
its built level), then by vat within it. An unpaid Chapel keeps its numbers but offers no slot.
From E3-2 the tend hand is what grows the vat's clone (above). **A ready clone needs no tending** (E4 step 10):
a staffed vat holding a ready clone closes its slot at the end of the step it fills in, and the hand goes back to
the ladder; spending the clone reopens it (`GameState._tended_vats`). The vat stays staffed (`view_backups`, the
save), so it takes its hand again on its own; before, a full vat kept a hand that grew nothing.
- **Measured:** a save with a Chapel and no staffed vat loses its tenders to the ladder. pre_vei
  (two unstaffed vats, 35 workers on 25 slots, the idle pool at its cap of 10) has 2 tenders fewer:
  they go idle, which puts the idle pool 2 over its cap, so its first step musters 2 workers (80
  mass) to WAR, and it settles at 33. midgame_2flips has no Chapel: nothing moves.

## 8. Contracts in short (full fields in STATE-API.md)
```
raid result: {v:2, run_id, seed_rev, fort_id, warden_beaten, retreated, relish_died, revived_in_place,
              killed_living_mass, raised:[{score:int, count:int, mass}], chaff_mass, garrison_mass,
              party_lost:[uid], loot:{relics, blueprints:[id], husks:[{kind}], remnants:[{aspect, rarity, magnitude}], essence}}
boss result: {v:2, run_id, seed_rev, won, fronts_cleared:[id], relish_deaths, backups_spent:{phylactery, clones},
              party_lost:[uid], backlog_spent}
```
GameState mints uids for looted items when it applies the result. The town scene returns only
`{v:2, teleport_to}`; all town actions are commands.

## 9. Config ownership
| file | owner | contents |
|---|---|---|
| `realm.json` | economy | RealmSim tunables, `valve.*`, `relish.*`, `simulacrum.*` (E3-4), `flip.*`, `tithe.*`, `readout.*`, `q.*` |
| `economy.json` (new) | economy | `sim.*`, `worker.*`, `job.*`, `stall.*`, `market.*`, `pit.*`, `body_store.*`, `town.*`, `inn.*`, `morale.*`, `stance.*`, `foreman.*`, caps, `opening.*` |
| `buildings.json` (new) | economy | costs, upkeep, jobs, effects, requires |
| `buildings_view.json` (new) | town | labels, silhouettes, flavour |
| `backups.json` (new) | economy | vats, clones, phylactery, respawns |
| `balance_standins.json` (new) | economy ships v0; dungeon adjusts values only | dungeon stand-in model |
| `town.json` | town (positions, view); lot ids and sizes are API | lots, yard view |
| `raid.json`, `loot.json`, `vei.json` | dungeon | combat, essence (`essence.lifetime_s`), wardens, loot, fronts |
| `world.json` | map (layout only) | the board: 12 forts, 12 villages |
| `palette.json`, `pulse.json` | foundation | look |
| `project.godot` | foundation or economy only | autoloads |

## 10. Tests (headless; `tests/run.sh` imports, then runs)
Each line names the suites that cover it at the end of E2a (`tests/test_<name>.gd`, slow ones in
`tests/slow/`, run with `--slow`); "not yet" marks what a later milestone adds.
- **E0 infra:** suite discovery (`--only`, `--slow`), the lint, the shared config loader
  (`run_tests.gd`, `lint`, `game_state_configs`).
- **Contract:** API key sets and types, additive-only; `Results.validate` for every kind; the seed
  schemas (`api_contract`, `results`, `game_state_runs`).
- **Persistence:** JSON round trip; the 3 fixtures load after every change (save compatibility);
  `in_dungeon` is never saved (`game_state_persist`).
- **Determinism:** the same seed and command log give the same `to_dict()` (`game_state`).
- **Ledger:** where every flow books, the invariant at every substep and at any substep length, the
  totals across a load, saves from before the ledger, and a 10 sim-min soak (`ledger`); the full 1 h
  soak of random inputs, conserved, with no NaN, no negatives and every pool within its cap
  (`slow/soak`).
- **Rates:** every `view_rates` id against the stream it describes, and `view_hud` from the same
  numbers (`game_state_rates`).
- **Valve:** the L1 slew keeps the sum at 1; zero is refused; held forts always stage WAR, and with
  no target at all it falls through to Vei (`game_state_macro`, `realm_sim`).
- **Relish:** travel, retarget and cancel; tide; redirect; nothing applies while dead; the order
  contract (`game_state_relish`, `game_state_macro`).
- **Flips and tithe:** grace and the contest (her reship, the zero clock, the break, the hold rule
  both ways), shipping-share loss, the clock from the first flip, warning, target, wave, counters
  (`game_state_macro`, `realm_sim`, `held_forts`); the held forts' readouts and `view_projection`
  (`api_v6`); the wave train, its targets against RealmSim's own steps, its settled rule, its cache and
  frame refresh, and the fall clock erring early (`wave_train`); whether a safe fort stands 8 h on, in live
  play (`slow/margin_truth`).
- **Town:** the workforce steady state; rot returns bodies; the gold formula; unpaid idling; the
  living cap; morale. Wired into GameState: WORK in the same substep, the pits and last step's feed drive the mint,
  the muster joins FLOOD (WAR under Muster; E4 step 5 A1), haul pickups come off the forts, the views read TownSim, v1 saves migrate
  (`town_sim`, `game_state_town`). Building, upgrading, tiers, caps and the catalog agreeing with
  `cmd_build` (`game_state_build`).
- **Ladder and stances:** ladder ordering (`town_sim`); the stances (E3-1, `stances`): each one's effect on the
  ladder and the staffing, `active` for an off stance, suspension, the hold, `fired_beat_id` and `stance_fired`,
  the priority, Thrift's order, reach and kept caps, its away line, `projected` against live, the save, and
  catch-up (bit-identical to the tip with none on; with Thrift and Muster on, 30 min at 10 s against live;
  `slow/stances_catchup` 6 h and Thrift's flicker).
- **Backups:** order; clones grow only while staffed; the loot-loss bound: E3 (not yet).
- **`q`:** the formula, and the circle EMA (mass-weighted, unchanged by 12 h of idle ticking)
  (`game_state_macro`).
- **Readouts:** the sign moves only on a sustained differential; drain time and odds
  (`game_state_macro`).
- **Pacing** (BALANCE §4): the fast smoke run by default (`pacing`); the 4 h profiles and ablations
  in `tests/slow/` (not yet; IDLE §8's autoplayer).
- **Budget** (`game_state_budget`, on `midgame_2flips`): per frame, `tick(1/60)` with the shipped
  configs, the median under the 8 ms frame budget (the max, a substep frame, is reported); per
  substep with the field slowed (what catch-up and the soaks pay), a generous ceiling. The EMA
  readout is a constant-time update inside the substep, so it has no separate measurement. The
  field's own cost is ground's (`slow/field_bench`).
- **The step at any dt** (E2b T3.0): the exact drain, a fort pinned at 0 living, t*, a full wave and
  Vei's headroom at 30 s against 0.5 s (`realm_sim`); the ledger and no negatives at 0.1–120 s
  (`ledger`); the core step's drift from 0.5 s over 1 h at 15 s (`convergence_1h`) and the full
  12 h table at 0.25–30 s with its cost, attribution and fallback price (`slow/convergence`); the
  capped field's village owners (`slow/field_cap`).
- **Dungeon:** seeded loot, re-clear decay, warden specs, essence from both sides (`raid_logic`,
  the dungeon unit's).
- **Vei:** front thresholds, the break-beats rule and the backup order are VeiFronts' (`vei_fronts`, the dungeon
  unit's). The glue (E3-5, `vei_glue`): `view_vei`'s fronts against the config formula, `counted` against `assigned`,
  the boss seed's fronts exactly the fight's recompute from the seed with ConfigDb's `vei` (the gate), and one in-place
  `relish_died` per spent backup, then a final death.
