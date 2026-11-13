# Necropolis: mechanics (v2)

The systems spec. Player intent is in `GAMEPLAY.md`. Starting numbers and pacing are in
`BALANCE.md`; this file names config keys, not values. All numbers live in `configs/*.json`. The
exact field lists of every command, view, seed, result and event live in `docs/STATE-API.md`, which
the economy unit writes at milestone E1 from §1.2 here.

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
| Ledger | `scripts/sim/ledger.gd` | economy | source/sink/held accounting (§2.1) |
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
  `Game`, `ConfigDb` or `Engine`. A lint test enforces this.
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
  `view_stances()`, `view_backups()` (including "what a death would cost right now").
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
- At most `sim.max_substeps_per_frame` per frame; any remainder after a hitch is dropped.
- Entering a dungeon or boss forces time scale 1. The router resets `Engine.time_scale = 1` on every
  scene swap.

**Order per substep** (a contract with tests):
1. stances and the job ladder (re-evaluated each beat, 1714 ms sim);
2. TownSim (WORK arrives one substep late, which is accepted);
3. the valve slew and split;
4. Relish's travel and state (GameState);
5. `RealmSim.step(dt, {war, flood, digest_q, tide_fort, redirect_fort, held:[...], surge})`;
6. Backups;
7. the ledger;
8. readouts (EMA);
9. the influence field, at `field.tick_hz`, time-sliced by the ground unit.

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
Matter has sources (mint) and sinks:
- `k_clear` and rot loss (1 − `body_return`);
- pit burn, milling;
- a lost Vei fight;
- dungeon loss;
- Vei's pool overflow, which is clamped so it is always 0. Her take is limited to the pool's
  headroom.

`GameState.ledger()` returns `{sources, sinks, held}`. A soak test runs 1 h with random valves,
flips, redirects and musters, and asserts `held + Σsinks == Σsources` within 1e-6 relative.

### 2.2 Digest quality `q`
`q = clamp(q0 + q_forge · forge_level + Σ foreman_q + q_raise, 1, q_max)`.
- `q_raise = q_raise_max · max(0, (EMA_score − 50) / 50)`, where the EMA is mass-weighted over every
  raised undead's circle score, with half-life `q.raise_ema_s`.
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
- `step(dt, inputs)` is pure on its inputs.
- `directShare` is **removed** everywhere, including `readout()`. FLOOD replaces it.
- `forts[i].held_s` and the tithe-wave state are RealmSim state.

### 3.2 The valve
- `mint = (P_base + P_per_pit · pits) · (1 + pit.bonus · feed)`, where
  `feed = min(1, burned / wanted)` and `wanted = pit.burn_per_s · pits`. Proportional, so nothing
  toggles.
- `work = mint · v.work` goes to TownSim, `war = mint · v.war` goes to RealmSim dispatch, and
  `flood = mint · v.flood` goes to `vei.undead_queue`.
- **Slew:** the valve vector moves toward the target by at most `valve.slew_per_s` of L1 distance per
  second, so the sum stays 1.
- **WAR with no living target** (every fort held or empty): it goes to the held forts as staging.
  There the undead drain to Vei, so a held fort becomes a forward pump.
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
- the fort is **held** for `flip.hold_s · (1 + flip.tier_mult · tier)`.

**While held:**
- **Vei's shipping share to that fort is lost**, because her shipping is per-fort capacity-limited,
  so a held fort lowers her effective `S_vei`;
- the fort pulls WAR as staging (§3.2);
- haulers there get `flip.haul_mult`;
- it injects necrosis.

**Tithe waves** (Vei's counter-current):
- **When:** every `tithe.period_s` × (1 − `tithe.backlog_scale` · odds). She fights back harder as
  the queue clogs.
- **Warning:** `tithe.warning_s` ahead, with the target shown on the map and on the fort's ring
  (`tithe_warning` event).
- **Targets:** held forts first, then the fort holding most of your WAR.
- **The wave:** a surge of `tithe.surge_mult` × `S_vei` living into the target for `tithe.surge_s`.
  A held fort under a wave loses its hold.
- **Counters:**
  - Relish standing there halves the surge;
  - a big undead placed there as siege cancels `tithe.siege_block` of it.

  Defending a flip is a real decision.

### 3.5 Readouts
- **Differential:** `diff = inflow − digestion` each substep, where inflow includes FLOOD and drain
  and excludes `directShare`.
- **Sustained sign:** the EMA of `diff` over `readout.ema_s` (120 s). ▲ when > +ε, ▼ when < −ε,
  otherwise "holding".
- **Drain time:** `backlog / −EMA` when the EMA < 0, else "holding". Never INF in state.
- **Odds:** `backlog / (backlog + K)`.
- Vei's panel and the confrontation dialog show all three.

### 3.6 Simulacra (kept, defined)
- Crafted at the Ossuary from essence and a relic.
- `cmd_deploy_simulacrum(fort_id)` plants one. It performs **Relish's redirect** at that fort at
  `simulacrum.rate` until its charges run out.
- The tide is hers alone.

## 4. Economic: Covington

### 4.1 Workforce
- `workers' = work / worker.mass − workers / lifetime − muster`.
- `lifetime = worker.lifetime_s · (1 + embalmer) · (home_rot_mult if Relish is home)`.
- Rot returns `rot · worker.mass · worker.body_return` mass of bodies.
- `view_town` shows the steady state, `(work / worker.mass) · lifetime`, beside the current count.
- **Workers are allocated by the job ladder** (§4.5).
  - Workers beyond all slots idle at the crypt and rot slower (`worker.idle_rot_mult`).
  - Idle beyond `worker.idle_cap` are mustered to WAR automatically, so WORK is never a black hole,
    but it is waste.

### 4.2 Jobs (rates per staffed worker; keys in `economy.json`)
| job | building | effect |
|---|---|---|
| haul | charnel house | convoys move corpses from forts to bodies. `job.haul.carry` mass per trip. The target is the auto-richest fort or `cmd_set_haul_target`. At the body cap, haulers idle. |
| mill | bone mill | bodies → bone at `job.mill.rate` (bone per mass) |
| stall | market | gold = `min(staffed_stalls · stall.rate, living · market.shop_rate) · market.price` |
| forge | forge | progress toward the next forge level (levels also cost relics) |
| pit | raising pit | burns bodies at `pit.burn_per_s` per pit for the feed bonus |
| tend | chapel of vats | grows clones (§7) |
| build | construction | `build_work` progress |
| foreman | (big undead only) | multiplies a building's output by `foreman.mult` + speed·`foreman.speed_k` |

### 4.3 The living
- `living' = migrants − departures`, capped at `living_cap`, which comes from housing (houses, inn,
  walls).
- `migrants = Σ held villages · town.migrant_rate + inn.attract · inn_level`.
- `departures = living · town.leave_rate` while morale < `morale.leave_below`.
- **Morale** ∈ [0, 1] moves toward its target at `morale.ease_per_s`. The target is:
  - `morale.base`;
  - plus Σ amenity gains;
  - minus dread, `max(0, workers / living − morale.dread_ratio) · morale.dread_k`, in worker units;
  - minus a death shock, which decays over `morale.shock_s`.
- **Interaction.** Each living agent cycles home → market → inn. Every stall sale is a trade event,
  which the town view draws as an arc between a living and an undead agent. The arcs are sampled, at
  most `view.max_trade_arcs`.
- **Unpaid upkeep.** When gold or bone can't cover upkeep, the cheapest building goes idle (flag
  `unpaid`, `building_unpaid` event). Stocks never go negative and there is no debt.

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

A tier-up is a set piece (the walls draw themselves).

**Every building has a numeric benefit** (vision review S7):

| building | benefit | gate |
|---|---|---|
| Crypt | holds the slab; idle rest; big-undead cap +1 per level | start |
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
| Chapel of Vats | vat slots; tend job | Town |
| Ossuary Tower | crafts simulacra and phylactery charges | Town + blueprint |
| Guildhall | + stance slots | Town |
| Watchtower | adds precision to fort hints (exact warden tells, death-risk %) | Town |
| Walls and Gate | Town tier; + morale; + living cap | Town |
| Plaza, Statue of Relish | + morale; the statue softens the death shock | Town |
| Reliquary | + relic and essence caps | City + blueprint |

### 4.5 The job ladder and stances (D11)
- **The job ladder:** an ordered list of jobs. Workers fill slots top-down. The player drags to
  reorder (`cmd_set_job_priority`), and can cap a building's staffing. That is "how the undead are
  behaving on auto".
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
- Cap: `big_undead.cap` (crypt levels). They die only in dungeons or the Vei fight.

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
- **E0 infra:** suite discovery (`--only`, `--slow`), the lint, the shared config loader.
- **Contract:** API key sets and types, additive-only; `Results.validate` for every kind; the seed
  schemas.
- **Persistence:** JSON round trip; the 3 fixtures load after every change (save compatibility);
  `in_dungeon` is never saved.
- **Determinism:** the same seed and command log give the same `to_dict()`.
- **Ledger soak:** 1 h of random inputs, conserved, with no NaN, no negatives and every pool within
  its cap.
- **Valve:** the L1 slew keeps the sum at 1; zero is refused; WAR with no target stages.
- **Relish:** travel, retarget and cancel; tide; redirect; nothing applies while dead; the order
  contract.
- **Flips and tithe:** hold, shipping-share loss, warning, wave, counters.
- **Town:** the workforce steady state; rot returns bodies; the gold formula; unpaid idling; the
  living cap; morale.
- **Ladder and stances:** ordering, hold, no chatter.
- **Backups:** order; clones grow only while staffed; the loot-loss bound.
- **`q`:** the formula, and the circle EMA.
- **Pacing** (BALANCE §4): the fast smoke run by default; the 4 h profiles and ablations in
  `tests/slow/`.
- **Budget:** one `tick()` stays under its µs budget; the EMA readout costs nothing extra.
- **Dungeon:** seeded loot, re-clear decay, warden specs, essence from both sides.
- **Vei:** front thresholds, the break-beats rule, backup order.
