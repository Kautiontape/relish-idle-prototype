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
    `cmd_cancel_build(lot_id)`;
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
  - `view_realm()`, `view_fort(id)`, `view_field()`, `view_villages()`.
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
- `building_started`, `building_done`, `building_unpaid`, `tier_up`;
- `fort_flipped`, `fort_retaken`, `tithe_warning`, `tithe_wave`;
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
3. TownSim, on this step's WORK as rate × dt, in the same step;
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
| gold | gold | stream, floor 0 | market trade | upkeep, build costs | net /s |
| bone | bone | stream, floor 0 | mill | build costs, some upkeep | net /s |
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
- `store_overflow`, 0 until E2b's store caps (IDLE §6).

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
- `forts[i].held_s` and the tithe-wave state are RealmSim state.
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
     moment U reaches 0. After that, every arriving undead is destroyed at once. Ū and L̄ come from
     alternating the two paths: a predictor from L0, then two corrections. The garrison's kills
     (`k_destroy · ∫L / q`, at most what the undead hold) and the drain come from U's path,
     `k_clear · ∫L` (at most the corpses) from living's. Kills at a redirect fort stay (§3.3). The
     redirect raises (Relish's, then the simulacra's) are a rate inside the step, bounded by the
     corpses. Mass is exact. Each fort records `t_living_out` and `t_undead_out`: the seconds into
     the step when living or undead reached 0 (0 when they started there), −1 when they did not.
     These are natural event boundaries for catch-up; nothing reads them yet. The living that
     marched back land in her pool, after this step's shipping;
  6. Vei's conversion. What the march-back took past her pool's cap is lost (`pool_overflow`,
     §2.1). Her take is clamped to her pool's headroom, which **counts this step's shipping** and
     the march-back, so at her cap a long step converts what it ships less what marched back;
  7. the wave books what it delivered and ends after `surge_s`; then the next wave's warning, its
     target read from this step's dispatch (§3.4);
  8. the hold countdown. A hold that runs out this step still counted as held for all of it, and a
     fort retaken this step records one `fort_retaken`, never two.

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
- the fort is **held**: a grace period of `flip.hold_s · (1 + flip.tier_mult · tier)`, then a support-vs-pressure contest (IDLE.md §3).

E2a keeps the timer: RealmSim counts `held_s` down, and at 0 the fort is no longer held and
RealmSim records `fort_retaken` with cause `expired` (GameState stamps `t`). The contest replaces it
at E2b.

**While held:**
- **Vei's shipping share to that fort is lost**, because her shipping is per-fort capacity-limited,
  so a held fort lowers her effective `S_vei`. The share rule: fort `i` receives at most
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
- **Targets:** held forts first, the one with the most of your undead there; else the fort
  receiving the most WAR at that moment. Ties go to world order, so with no WAR anywhere it is the
  first fort.
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
    - **The hold** (E2a's rule compares the living the wave delivered with your undead there when
      it ends). The march-back doesn't change what the wave delivers: 960, or 480 with Relish
      there, 384 with a siege, 192 with both. So statically, a garrison at its fort's full cap
      (`U = cap ≤ 520`) loses to a full wave at every fort, Relish saves it only at Whitecross
      (520 > 480), and The Stair (480) ties. That holds at any τ.
    - **Live** (`realm_sim`'s `_march_holds`: combat, drain and march-back on, 0.5 s). A held fort
      starts with `U = cap` and no living or corpses, and every other fort is full of corpses, so
      all the WAR stages there.
      - With no WAR its garrison drains and is destroyed before the wave ends: Greywall ends with
        0 undead and Whitecross with 0, or 0 and 90 with Relish there. So the hold is lost with or
        without Relish.
      - With WAR staged there the counters decide. At 30 mass/s the full wave still takes the hold
        (the garrison ends at 424 at Greywall and 465 at Whitecross, against 960). Relish saves it
        (509 and 557, against 480), and so does a siege (453 and 501, against 384). At 20 mass/s
        nothing saves it.
      - From τ = 40 to 120 the garrison's end moves by at most 8 (Greywall) and 0 (Whitecross),
        at 0 to 40 mass/s of WAR. Staging, the drain and the counters set the hold; τ doesn't.
    - So τ = 60 (1.5 · `surge_s`): the excess outlasts the wave (it peaks at 73% of W), it is
      nearly gone before the next wave, and `cap + W` bounds the living at the shortest period.
      `tests/slow/convergence.gd` asserts that bound over 12 h, and that no fort ends above
      `cap · 1.01` unless a wave ran there within 7τ.
- **Counters** (applied every step of the wave; the event reports them at its start):
  - Relish standing there (at the fort or in its dungeon) multiplies the surge by `tithe.relish_mult` (0.5: halves it);
  - a big undead placed there as siege cancels `tithe.siege_block` of it. Siege is E3: RealmSim
    takes the cancelled fraction per fort as its `siege_block` input, 0 until then.

  Defending a flip is a real decision.
- **Hold loss (E2a; E2b replaces the hold model, IDLE §3):** when the wave ends, a held target
  loses its hold (`fort_retaken`, cause `tithe_wave`) only if the living mass the wave delivered
  exceeds your undead there. Otherwise the hold stands, so the counters matter.
- **A retake** (either cause) resets the fort's `clears_since_retaken` to 0, so its yield refreshes
  (§5.3).

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
  only what is left above the cap overflows (a store already over the cap, after a demolition, keeps its excess and the pits draw it down; only what comes in is clipped, to `max(cap, B0 − out)`), split between `rot_overflow` and `haul_overflow` by
  their shares of the inflow. A long step near the cap books no phantom overflow. A convoy's
  departure and pickup see the store's projected level at that moment (rot in, pits and mills out,
  loads landed). Pickups still read the forts' corpses from the snapshot taken before the step, so
  a long step's later legs don't see corpses made inside it (a known gap at long steps).
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
| haul | charnel house | One convoy. It leaves when haulers are staffed, bodies are under the cap and there is a target: `auto` is the fort with the most `dead` above `job.haul.auto_min_dead`; otherwise it is the fort set by `cmd_set_haul_target`. Each leg takes distance / (`job.haul.speed` · (1 + Σ stables `haul_speed_mult`)), and the crew is fixed at departure. At arrival it picks up `job.haul.carry` per hauler (× `flip.haul_mult` at a held fort), clamped to the fort's `dead` and to the store's headroom (its projected level at that moment, §4.1). The load lands on the way back; what the store can't hold once the pits and mills have taken theirs is `haul_overflow` (§4.1). A long step runs as many legs as it holds. At the body cap, haulers stay staffed but no convoy leaves. |
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
  - Stocks never go negative and there is no debt. Gold and bone have no caps yet (IDLE §6 is E2b).

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

**Every building has a numeric benefit** (vision review S7):

| building | benefit | gate |
|---|---|---|
| Crypt | holds the slab; idle rest; big-undead cap +1 per level above 1 | start |
| Raising Pit | +`P_per_pit` mint; pit job | start (1) |
| Charnel House | haul job; body store cap + | start |
| Market | stall jobs (gold) | start (small) |
| House | + `living_cap` | Hamlet |
| Well, Bakery | + morale, + living cap | Hamlet |
| Bone Mill | mill job | Hamlet |
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
- the warden archetype and its one-line tell;
- the loot hint;
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
  - **re-clear yield × `loot.reclear_decay`^(clears since last retaken)**. A fort that Vei retakes
    and re-garrisons refreshes its yield (vision review M8).
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
- **Flips and tithe:** hold, shipping-share loss, the clock from the first flip, warning, target,
  wave, counters, the E2a hold loss (`game_state_macro`, `realm_sim`).
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
