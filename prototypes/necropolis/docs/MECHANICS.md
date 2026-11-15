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
| Stances | `scripts/sim/stances.gd` | economy | the job ladder and stances (§4.5) |
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
- `stance_fired`, `loot_banked`, `vei_result`;
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
- Autosave runs every 30 s and on scene change, and never persists `in_dungeon`. On load, Relish is
  at the fort and that run is forfeited.
- Three fixture saves ship in `tests/fixtures/`: day-1, mid-game with 2 flips, and pre-Vei. Scene
  units use them for screenshots and view tests.

### 1.3 Time and ticking
- `GameState.tick(dt)` takes plain sim seconds and runs fixed `sim.substep_s` (0.5) substeps.
- The autoload feeds it **real** delta × `Game.time_scale`:
  `delta / max(0.05, Engine.time_scale) * time_scale`. Trance's `Engine.time_scale` never slows the
  realm.
- At most `sim.max_substeps_per_frame` per frame. A gap above `idle.gap_s` goes through catch-up instead of being dropped (IDLE.md §4); smaller remainders are dropped.
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
   Holds and the tithe state are RealmSim's own state (§3.1), not inputs;
6. Backups;
7. the ledger;
8. readouts (EMA);
9. the influence field, at `field.tick_hz`, time-sliced by the ground unit.

Steps 1–8 are the **core step** (`GameState._core_step(dt)`): valid at any `dt`, everything in it is
exact or a rate over the step (E2b T3.0; `tests/slow/convergence.gd` measures it). Step 9, the
village owners it decides and the lanes' callouts are the **presentation step**. Live play runs the
core step, then the presentation step, for each `sim.substep_s` substep; catch-up (IDLE §4) runs
core steps of its own length and caps the presentation.

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
| relics | count | capped stock (`relics.cap`, raised by the Reliquary) | dungeons only | buildings, forge levels, phylactery, upgrades | count |
| blueprints | set | unlocks | dungeons only (first clear guaranteed) | unlock building types | set |
| essence | motes (int) | capped stock (`essence.cap`) | dungeons (carried out) | phylactery charges, simulacra | count |
| husks, remnants | items with uids | stock | dungeons | slab | count |
| living | people | stream, capped by housing (`living_cap`) | migrants, the inn | departures at low morale | net /s, cap |
| digest quality `q` | level, 1..`q_max` | derived (§2.2) | forge, foremen, circles | none | number |
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
`q = clamp(q0 + q_forge · forge_level + Σ foreman_q + q_raise, 1, q_max)` (`realm.json` `q.*`).
- `q_raise = q_raise_max · max(0, (ema_score − 50) / 50)`, where `ema_score` is a mass-weighted EMA
  over every raised undead's circle score. It starts at 50, so `q_raise` starts at 0.
- **Its half-life is in mass raised, not in seconds** (`q.raise_half_mass`, which replaces
  `q.raise_ema_s`). It moves only when a raid result is applied: for each `raised` bucket
  `{score, mass}`, in apply order, `α = 1 − 0.5^(mass / q.raise_half_mass)` and
  `ema_score += α · (score − ema_score)`. The masses are the ones actually raised: the result's masses scaled by R'/R (R' = what the fort's dead could cover, STATE-API §8.3 step 3), so a result reporting 1000 mass at a fort with 10 dead moves the EMA as if about 10 were raised. Why: IDLE I2
  says what active play earned never decays while you're away, and a time-based EMA would decay
  with every idle hour. This one holds while no circles arrive.
- `forge_level` is TownSim's forge level (the forge job, §4.2); `Σ foreman_q` is 0 until E3. The save
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
  fort's siege share (`siege_block`, E3) arrive as inputs; RealmSim never reads them from its
  config or keeps its own Relish.
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
- `work = mint · v.work` goes to TownSim as `work · dt` in the same step, `war = mint · v.war` plus
  TownSim's muster (`muster_mass / dt`) goes to RealmSim dispatch, and `flood = mint · v.flood` goes
  to `vei.undead_queue`.
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
  - WORK beyond filled slots plus `worker.idle_cap` is wasted;
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
- **Dead:** no tide, redirect, slab or bonus. **Everything else stays live:** valve, building,
  stances (vision review S3).

### 3.4 Flips and tithe waves
**Flip.** On `warden_beaten`:
- all the fort's living become dead, applied as a clamped delta;
- the fort is **held**: a grace of `flip.hold_s · (1 + flip.tier_mult · tier)` (`fort_flipped.hold_s`
  is that grace), then a contest between two pools (IDLE.md §3; E2b-2 T3.1 replaced E2a's timer,
  which retook the fort when `held_s` ran out, cause `expired`).

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
  `big_undead_returned {uid, fort_id}` right after the `fort_retaken`;
- a simulacrum planted there is lost (RealmSim drops it; `cmd_deploy_simulacrum` is still the E3
  stub, so only a save or a test plants one today);
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
  exact time left: the wave's own time doesn't depend on the step. (The target reads that step's
  WAR, a rate constant over the step.)
- **Targets:** contested held forts first (past their grace), the one with the most of your undead
  there; else the fort receiving the most WAR at that moment. A fort in grace is never a target
  (above). Ties go to world order, so with no WAR anywhere it is the first fort not in grace.
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
  - a big undead placed there as siege cancels `tithe.siege_block` of it. Siege is E3: RealmSim
    takes the cancelled fraction per fort as its `siege_block` input, 0 until then.

  Defending a flip is a real decision.
- **No wave ends a hold by itself** (E2b-2 T3.1 removed E2a's `tithe_wave` cause): it surges into the
  counter-garrison, and the contest decides (the retake above).
- **A retake** resets the fort's `clears_since_retaken` to 0 and its loot yield to 1 (§5.3).

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
- **Odds:** `backlog / (backlog + K)`.
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
    and tide, the siege's block, `q`). It is RealmSim's own `fort_step` at `hold.probe_dt_s` (10 s), each
    step cut at the next event so each lands at its time (a warning, a wave's start and end, a grace end,
    a garrison at 0 reaching `break_s`), with the zero clock as step 9 runs it (T3.3a's leave-0 split
    included), through her waves at her period (`tithe_period`, at today's odds). A contested fort gets
    her reship, a fort in grace nothing; the running wave surges `surge_mult · S_vei` × its counters into
    its target (her pool assumed to cover it). A fort whose clock reaches `break_s` is **broken** and
    leaves the held set. A clock not yet started (only a test or debug holds a fort with no flip) runs as
    if started now.
  - **Targets**, as `_tithe_target`: at each warning, the contested fort (held, past grace, not broken)
    with the most undead, ties in world order. A fort in grace is never a target; a pending warning naming
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
  - **What it reads that isn't in today's flows yet**, both committed and changed only by a command: the
    WAR **at the valve's target** (it slews there at `valve.slew_per_s`, at most 20 s for a full swing),
    and **Relish where she is travelling to** (her trip takes seconds at `relish.travel_speed`): her tide
    and redirect there, and the split with her tide moved there (`RealmSim.war_at_tide`). midgame_2flips
    as loaded has her a second from Greywall; held where she stands, the train called Old Sluice safe at
    its WAR of 1.258, which her tide cuts to 0.761 and the next waves break (retaken at 1 316 s). The
    other readouts (`garrison_rate`, `fall_s`, `war_supports`) stay at the current split. Before the
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
  headless tools) every miss probes, exactly.
- **The truth check** (`tests/slow/margin_truth.gd`): from each start, live 0.5 s steps for 12 h with no
  input; at the first substep and every 30 min to 4 h, each held fort's margin, then what happened in the
  next 8 h. midgame_2flips: 10 samples; the train read Ashgate and Old Sluice thin at t0 (Old Sluice fell
  at 1 316 s, Ashgate held: thin and pessimistic there) and Ashgate safe from 30 min to 4 h (8 safe,
  all held); the one-wave probe read all 10 safe, Old Sluice's at t0 the lie. pre_vei and fresh hold no
  fort (no sample). pre_vei with Ashgate and Vespers contested: 10 safe samples, train and one-wave
  alike, all broken at 2.2 and 2.4 h, after the town's gold ran out (pre_vei's gold floor: its pits stop,
  the mint goes from 60.8 to 2.0 and the WAR from 49.7 to 0.95 mass/s): neither probe reads the town, so
  the check counts a safe fort that fell after its WAR dropped below half its sampled value apart, as its
  WAR falling, and prints it. midgame with the valve's WAR share cut to 0.05: both read thin at t0 (the
  one-wave probe safe) and both fell. So 18 safe samples, none broken by the waves.
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
- Crafted at the Ossuary from essence and a relic.
- `cmd_deploy_simulacrum(fort_id)` plants one. It performs **Relish's redirect** at that fort at
  `simulacrum.rate` until its charges run out: garrison kills there stay as corpses while it has
  charges, and it raises corpses into the fort's undead. Charges are mass and only the raise spends
  them.
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
  - Idle beyond `worker.idle_cap` are mustered to WAR at once (`n · worker.mass` mass), so WORK is
    never a black hole, but it is waste. The workforce never ends a step above the staffable slots
    plus `idle_cap`.
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
  value is an array: the Charnel House's `body_cap` is `[0, 50, 100]`, so only its upgrades add.
  Flow effects (`pits`, `morale`, `attract`, `lifetime_bonus`, `haul_speed_mult`) need the building
  working. Capacity effects (`living_cap`, `body_cap`) also count while it is unpaid or upgrading,
  so an unpaid spell never destroys stock.

| job | building | effect |
|---|---|---|
| haul | charnel house | One convoy. It leaves when haulers are staffed, bodies are under the cap and there is a target: `auto` is the fort with the most `dead` above `job.haul.auto_min_dead` at the moment it leaves (below); otherwise it is the fort set by `cmd_set_haul_target`. Each leg takes distance / (`job.haul.speed` · (1 + Σ stables `haul_speed_mult`)), and the crew is fixed at departure. At arrival it picks up `job.haul.carry` per hauler (× `flip.haul_mult` at a held fort), clamped to the fort's `dead` at that moment, to what the fort held at the step's start (less this step's earlier pickups there) and to the store's headroom (its projected level at that moment, §4.1). The load lands on the way back; what the store can't hold once the pits and mills have taken theirs is `haul_overflow` (§4.1). A long step runs as many legs as it holds. At the body cap, haulers stay staffed but no convoy leaves. |
| mill | bone mill | each miller turns `job.mill.mass_per_s` bodies into `job.mill.rate` bone per mass, from what the pits leave (§4.1) |
| stall | market | gold = `min(staffed_stalls · stall.rate, living · market.shop_rate) · market.price`. The sales rate is `trade_rate`. |
| forge | forge | `job.forge.rate` work per worker-second toward `forge.level_work[level]`. The level completes only when `forge.level_relics[level]` relics are available; until then progress holds. This is TownSim's forge level (for `q_forge`), not the Forge building's level. |
| pit | raising pit | each working pit burns `pit.burn_per_s` × its staffed share, with first call on the bodies (below). `wanted = pit.burn_per_s · pits` counts every working pit, and `feed = min(1, burned / wanted)`. |
| tend | chapel of vats | one slot per vat, open only while that vat is staffed (§7; E2b-2): `jobs.tend` × level slots for `vat_slots` × level vats, the same count. Grows clones (§7, E3); until then only the tenders count |
| build | construction | `job.build.rate` work per worker-second against `build_work · target level`. A `build_work` of 0 completes at once. |
| foreman | (big undead only) | multiplies a building's output by `foreman.mult` + speed·`foreman.speed_k` |

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
    stalls' rate) and the forge (a level waiting for relics); only the mill's is reported.
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
  - **The hold, and its gap.** A pickup is also held to what the fort held at the step's start, less
    this step's earlier pickups there. GameState takes it off the fort before the realm step, which
    owns the corpses made inside it, so the ledger stays exact (`test_ledger`). Where the corpses
    grow inside the step, a long step's legs can't take those made inside it, and they wait for the
    next step's legs. That happens at forts with no living where Vei's shipping dies as it lands:
    pre_vei's six corpse forts, 1.88 mass/s between them. At 10 s pre_vei's convoy runs 10 to 15 mass
    behind 0.5 s's from the first minute (9.5 at 60 s, 12.9 at 600 s), and its forts hold that much
    more. The bone its mill makes over the cap, `ledger().stores.bone.overflow`, is 1.14% behind at
    600 s, falling to 0.04% by 12 h. Applying the pickups after the realm step, without the hold,
    measured 0.22% (an experiment only). Taking them needs either the realm step delivering an owed
    pickup or the pickups moving after it (§1.3's order), and both are rules the run's manager kept
    (E2b-2 T3.3a: the hold and §1.3's order stay; the sink is on file, IDLE §4). The gap is bounded:
    measured over 24 h it is the step's own corpses (their rate × dt / 2 on average) plus at most
    about one load per fort (summed, up to 28 mass at pre_vei's gold floor), and it doesn't grow
    (IDLE §4). The catch-up gate's bone floor
    (`idle.catchup_gate_tally_floor`) carries it.

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
  - **Unpaid.** When a stock can't cover it, the cheapest building by its upkeep in that stock goes
    idle (flag `unpaid`, event `building_unpaid{lot_id, building_id, unpaid: true}`). Ties go in lot
    order, and it repeats until the bill fits. Only buildings with upkeep in that stock are picked,
    so never the crypt. A building that earns that stock (stalls for gold, mills for bone) is never
    picked, because idling the only earner would lock the town out of ever paying again. What is
    still owed is paid down to 0.
    - A building that resumed inside the step (Resume, below) is billed only for the seconds it was
      paid, from its resume to the step's end. If the same step's cascade then idles it, the
      cascade takes exactly that off the bill, so it pays nothing for the step and the buildings
      still paying are billed their own upkeep and no more (since `72dfd81`).
  - An unpaid building gives no slots and no output.
  - **Resume.** It stays unpaid for at least `upkeep.unpaid_hold_s`. It resumes (`unpaid: false`)
    at the first moment its stocks cover the paying upkeep plus its own for
    `max(unpaid_hold_s, dt)`, so it doesn't chatter. Inside a step that moment is solved on the
    stocks' paths: each starts at what it held before the step's income, which comes in at a
    constant rate, and pays the working buildings' upkeep as it goes. Buildings resume in the order
    of their moments, ties in lot order. Each raises the upkeep the next must cover, and each pays
    its own from its moment on.
    - E2b T4.C: they used to be checked at the step's end, in lot order, on the stocks before the
      step's upkeep was paid. From pre_vei's gold floor a 10 s step resumed the raising pit
      (lot-02) at 7 804 s. The gold had crossed the house's (lot-05) lower threshold first, and,
      net of upkeep, it reached neither until 7 847 s and 7 853 s. The pits and WAR came back about
      45 s early, and three forts Vei had refilled with living fell instead of holding. Vei's dead
      were 31.9% off at 10 s over 12 h; now 0.50%.
  - Stocks never go negative and there is no debt.
- **The gold and bone caps** (IDLE §6, E2b-2 T3.2). `gold_cap = gold.cap + Σ gold_cap` and `bone_cap =
  bone.cap + Σ bone_cap` (`economy.json`; the Market's and the Bone Mill's per-level `effects`, capacity
  effects, so unpaid or mid-upgrade levels count). Only what came in is clipped, and the clip is exact
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
ordered list of entries `{building_id, lot_id, upgrade, waited_on}`, at most `queue.max_len` (8), saved.
Everything else an entry shows is derived from today's state by one walk, which `view_town().queue`,
`cmd_queue_build` and the core step's processing all run, so a status always says what the next
processing does.
- **What `cmd_queue_build` refuses:** only what waiting can never make valid: `queue_full`,
  `unknown_building`, `unknown_lot`, `unique` (one stands, is under construction or is queued),
  `lot_taken` (a building stands or is under construction there), `lot_too_small`; for an upgrade
  `empty_lot` (nothing stands or is queued there) and `max_level`; and `cost_exceeds_cap` (a gold, bone or
  relic cost above that store's cap now; it names the store, the building that raises its cap, the first
  in `buildings.json` with that `*_cap` effect, and `cap_level`, the lowest level of that building whose
  cap covers the price: 1 when it isn't built yet, −1 when no level does). Affordability never refuses:
  it holds the queue.
- **What it accepts as a gate** (the run's manager, 2026-11-14: IDLE §5 over api-request #3's wording,
  since growth while away is Shawn's ask): `needs_tier`, `needs_blueprint`, `needs_building`,
  `lot_locked`, a relic shortfall (`no_relics`), and for an upgrade a construction under way on its lot
  (`under_construction`) or an unpaid building (`unpaid`). A gated entry shows `skipped_gate` with that
  reason and is re-checked every step.
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
  - So several affordable entries can start in one step, in order, and build at once on the build job.
- **The manager's four rules for gated entries:**
  1. **A gated entry never stalls the queue.** The head is the first entry that isn't gated. When a gate
     clears, the entry starts at its own position: it never jumps an earlier entry that waits for funds.
  2. **A gated entry holds nothing.** It reserves no gold, bone or relics and claims no lot. If another
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

**Every building has a numeric benefit** (vision review S7). From E2b-2 (T3.2, api-request #9) the build
card shows it as the change in each net rate if the building were finished now: `view_catalog`'s
`projected` and `view_town`'s `upgrade_projected`, TownSim's own step run on a copy with the building
finished against a copy without (STATE-API §5.10). The table is the design intent:

| building | benefit | gate |
|---|---|---|
| Crypt | holds the slab; idle rest; big-undead cap +1 per level above 1 | start |
| Raising Pit | +`P_per_pit` mint; pit job | start (1) |
| Charnel House | haul job; body store cap + | start |
| Market | stall jobs (gold); + gold cap (`gold_cap` per level) | start (small) |
| House | + `living_cap` | Hamlet |
| Well, Bakery | + morale, + living cap | Hamlet |
| Bone Mill | mill job; + bone cap (`bone_cap` per level) | Hamlet |
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
  the Guildhall, plus 1 while Relish is home. Each shows its projected effect on net rates before you
  toggle it. None touches the valve (one controller per dial).

| stance | effect |
|---|---|
| Vigil | while Relish is away or dead, tend jumps to the top of the ladder |
| Harvest | while bodies < 30% of cap, haul jumps to the top |
| Thrift | buildings over a gold upkeep threshold idle when gold income < upkeep |
| Muster | idle workers muster to WAR at once (no idle cap) |
| Hearth | stalls and the inn jump to the top while morale < 0.5 |

- Stances act on the ladder's order and on binary conditions only, with a `stance.hold_s` minimum
  so nothing chatters.
- Firings show in `view_stances()` with `fired_beat_id`. The town scene flashes the affected agents
  on its next visual beat.

### 4.6 The crypt slab: big undead
- Only while Relish is home. The town scene's crypt view runs SlabLogic's live preview (ported from
  `slab/`: build_state, namer, role, live morph, hold-to-raise).
- **The raise:** `cmd_raise_big_undead(husk_uid, remnant_uids, name)`. GameState validates the
  inventory and computes the stats.
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
  - fort siege (`fort:<id>`), which adds kill power there and blocks tithe;
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
  party, then Relish.
- Your undead fight on their own.
- Essence lives `essence.lifetime_s` (12, longer than the cooldown).
- **RTS-drift guard:** the scene logs move clicks against raises. A ratio above 8:1 is a design smell,
  reported in telemetry.

### 5.1 Entry and seed
- `cmd_begin_dungeon(fort_id)` returns a seed (the full fields are in STATE-API):
  - `run_id`, `rng_seed`, the fort (tier, cap);
  - living, dead, your undead there;
  - the party from `cmd_set_party`;
  - `digest_q`, phylactery charges, clones ready;
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
    seed and `view_fort` read it live. A retake resets `yield_c` to 1, so a fort Vei retakes refreshes
    its yield (vision review M8). Saved per fort (`yield_c`, `yield_t`); an older save reads 1, as
    it showed.
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
- **Phase 1:** the fronts resolve as streams on the field, horde against her guard, each to its
  threshold. Uncleared fronts keep sending guards in phase 2.
- **Phase 2, the break** (vision review S4: a verb, not HP):
  - Vei is a ferry. She has a **ferry rate** that drains your horde.
  - Relish must **raise at anchor points** (circles around the essence of the fallen) so your raise
    rate beats her ferry rate.
  - She breaks after `vei.break_beats` consecutive tempo beats with raise > ferry.
  - Her weaves hunt Relish, telegraphed on the beat.
- **Backups in the fight:** each Relish death spends a phylactery charge first, then a ready clone.
  None left means the fight is lost. Each spent backup is a cracked violet ring.
- **Win:** `won = true`, the victory set piece, the game is beaten. Play continues (endless).
- **Lose:**
  - backlog × `vei.loss_backlog_keep` (0.35 is kept);
  - the party's big undead die;
  - the last death follows §7.

## 7. Death and backups
**Before she dies,** the sacrifice chain (§5.0) soaks lethal hits.

**At HP 0, in order:**
1. **A phylactery charge** (crafted at the Ossuary): revive in place at `phylactery.revive_hp`. At
   most `phylactery.max_per_dungeon` per dungeon.
2. **A ready clone:** she wakes at Covington after `backups.clone_respawn_s`.
   - The party and any unbanked loot are lost, and the fort doesn't flip.
   - Unbanked loot is capped at what was found since the last checkpoint room, so a 6-minute run
     never loses everything.
3. **Unmade:** she reforms after `backups.unmade_respawn_s`, with a morale shock and lost unbanked
   loot. Nothing else is lost, and nothing resets.

**Clones** grow at `vats.grow_per_s` per **staffed** vat, from 0 to 1, one clone per vat.
`view_backups` always shows what a death would cost right now.

**A staffed vat takes a hand** (E2b-2, the run's manager). A Chapel of Vats offers one tend slot per
vat (`jobs.tend` × level tend slots for `effects.vat_slots` × level vats, the same count), and a
vat's slot is open only while that vat is staffed (`cmd_staff_vat`). The job ladder fills the open
tend slots like any other (§4.5). Staffing a vat opens its slot, which takes the hand the ladder
gives it: an idle worker if there is one, else the lowest room staffed below it. Unstaffing it
closes the slot and the hand goes back to the ladder's next room, or idles. The vats are numbered
as `view_backups` numbers them: in lot order over every built Chapel (unpaid or mid-upgrade too, at
its built level), then by vat within it. An unpaid Chapel keeps its numbers but offers no slot.
Clone growth isn't tied to the tenders yet (E3).
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
| `realm.json` | economy | RealmSim tunables, `valve.*`, `relish.*`, `flip.*`, `tithe.*`, `readout.*`, `q.*` |
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
  muster joins WAR, haul pickups come off the forts, the views read TownSim, v1 saves migrate
  (`town_sim`, `game_state_town`). Building, upgrading, tiers, caps and the catalog agreeing with
  `cmd_build` (`game_state_build`).
- **Ladder and stances:** ladder ordering (`town_sim`); stances, hold and no chatter are E3 (not yet).
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
- **Vei:** front thresholds, the break-beats rule, backup order: E3 (not yet).
