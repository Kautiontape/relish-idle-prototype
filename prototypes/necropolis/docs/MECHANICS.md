# Necropolis: mechanics

The systems spec. Player-facing intent is in `GAMEPLAY.md`. Starting numbers and pacing targets are
in `BALANCE.md`; this file names config keys, not values. All numbers live in `configs/*.json`.

## 0. Decisions and deviations (reversible; each has its reason)

| # | decision | deviates from | why |
|---|---|---|---|
| D1 | **The valve.** Covington's mint splits WORK / WAR / FLOOD, set by the player. | BRIEF §5 "Relish's position is the only lever" | Vision: "commiting a flow of forces", "taking in undead or leaving them to work vs sending them to Vei". The flow still routes itself among the forts. |
| D2 | **`P_relish` = 0.** Relish mints nothing. | Necropolis 3.0 (300 Realm), RECOMMENDED 1500 | BRIEF §12's stricter test; the audit showed staying home beat raiding. Her location carries the value instead (§3.3). |
| D3 | **Relish redirects the dead shipment where she stands.** | BRIEF has only a raise channel | Vision: "move Relish to change tides and redirect shipments". It is still position-only: no explicit routing UI. |
| D4 | **Fortresses flip** when their warden falls. | Realm has no capture | Vision: a dungeon check at the end must matter on the macro. |
| D5 | **Workers are a stream with a lifetime**, fed by WORK. | Necropolis's constant `idle_undead` 6 | Vision: streams, not quantities. |
| D6 | **Gold is the living's trade currency, with upkeep as its sink.** | Prior-art suggestion to drop gold | The living must "contribute to the town's economy". Upkeep makes gold a stream (the 27k gold pile-up seen in the before-shot). |
| D7 | **Big undead are a countable stock**, the only one besides Relish's backups and loot. | "Streams, not stocks" | A stream for the many, a stock for the few (prior art: slab/crypt); a named creature needs to persist. |
| D8 | **Essence drops from every death in a dungeon, yours included.** | Every prototype drops it from enemies only | Vision: "essences drop from undead". |
| D9 | **Death is real; backups buy it off; nothing resets.** | R&R total wipe; Obsidian "never wiped" | Vision: "real risk of failure" plus "use her backups to not die". |
| D10 | **Vei is the ferrier** (Obsidian), and her final test is fought on **fronts**. | Slab's "Raven Queen"; Necropolis's HP-scaled boss | The fiction fits a flow game; fronts are the validated antidote to "more HP" (crypt playtest). |
| D11 | **Hue, mark frequency, tempo phase** follow 06/angiogram (VISUAL-LANGUAGE §1). | BRIEF's literal formulas | The audit showed the literal ones erase identity or miss the band. |

## 1. Architecture

### 1.1 Modules and owners
| module | file | kind | owns |
|---|---|---|---|
| **GameState** | `scripts/sim/game_state.gd` | RefCounted, headless-testable | all game state, `tick(dt)`, commands, views, save/load |
| Game (autoload) | `autoload/game.gd` | thin shell | holds one `GameState`, runs `_process` (time scale), emits signals, scene helpers |
| RealmSim | `scripts/sim/realm_sim.gd` | RefCounted | macro streams (§3) |
| InfluenceField | `scripts/sim/influence_field.gd` | RefCounted | necrosis ground data |
| TownSim | `scripts/sim/town_sim.gd` | RefCounted | workforce, living, jobs, buildings' effects, gold/bone streams (§4) |
| Policies | `scripts/sim/policies.gd` | RefCounted | rule evaluation (§4.5) |
| Backups | `scripts/sim/backups.gd` | RefCounted | vats, clones, phylactery, death outcomes (§7) |
| RaidLogic | `scripts/raid/raid_logic.gd` | RefCounted | dungeon layout, ledger, loot, warden spec (§5) |
| VeiFronts | `scripts/raid/vei_fronts.gd` | RefCounted | final-test fronts and outcome (§6) |
| SlabLogic | `scripts/town/slab_logic.gd` | RefCounted | big-undead construction (§4.6), ported from the `slab/` prototype |

Scenes (map, town, dungeon, boss) **never mutate state directly**. They read views and send commands,
and in-scene play returns one result dict through `finished(result)`, which GameState applies.

### 1.2 GameState public API (frozen at milestone E1; scenes code against this)
Commands (each returns `{ok: bool, reason: String}`):
- `cmd_set_valve(work: float, war: float, flood: float)`: normalised to sum 1.
- `cmd_move_relish(node_id: String)`, where `node_id` is a fort id, `"covington"` or `"vei"`.
- `cmd_build(building_id: String, lot_id: String)` and `cmd_demolish(lot_id)`.
- `cmd_set_policy(slot: int, rule: Dictionary)` and `cmd_clear_policy(slot)`.
- `cmd_place_big_undead(uid: String, place: String)`, where place is `"town:<building_id>"`,
  `"fort:<id>"`, `"party"` or `"crypt"`.
- `cmd_craft(item_id: String)`: simulacrum, phylactery charge, etc.
- `cmd_deploy_simulacrum(fort_id)`.

Scene results (applied with `apply_result(kind, result)`):
- `kind` = `"raid"`, `"town"`, `"boss"` or `"slab"`.
- Schemas in §8. Each result carries a `"v": 2` field. An unknown version fails loudly.

Views (plain dictionaries, rebuilt on read; the scenes cache them per frame):
- `view_rates()`: every stream's in, out and net per second (§2).
- `view_realm()`, `view_fort(id)`, `view_vei()` (backlog, sustained differential sign, drain time,
  odds).
- `view_relish()`: location, state, travel progress, alive or respawning and its timer, backups
  ready.
- `view_town()`: buildings, lots, jobs, workers, living, morale, policies and which fired last beat,
  tier.
- `view_inventory()`: relics, blueprints, husks, remnants, banked essence, big undead.

Persistence: `to_dict()` and `from_dict()`. The autoload autosaves to `user://necropolis_save.json`
every 30 s and on scene change, and loads on boot if a save exists. A debug key starts a new game.

### 1.3 Ticking
`GameState.tick(dt)` runs at a fixed 0.5 s sim substep (`config: sim.substep_s`), times
`Game.time_scale`. Order per substep:
1. policies, every beat (1714 ms of sim time);
2. TownSim;
3. the valve split;
4. RealmSim;
5. Relish's travel, tide and redirect;
6. backups;
7. the influence field (`field.tick_hz`).

The sim keeps ticking while any scene is open, including dungeons. While Relish is in a dungeon she
is *at* that fort and her tide applies there, but her redirect channel is off (she is busy inside).

## 2. Resources and streams

| resource | kind | sources | sinks | HUD shows |
|---|---|---|---|---|
| **undead (mint)** | stream | raising pits at Covington, fed by bodies | split by the valve | mint /s and the split |
| **workers** | stream with a lifetime | WORK share of mint | rot (`workers / lifetime`), muster to WAR | in /s, rot /s, net, and the steady state |
| **war undead** | stream (RealmSim) | WAR share; muster | killed at forts (corpses), drained to Vei | per lane |
| **flood** | stream | FLOOD share | Vei's queue | flood /s |
| **corpses (at forts)** | pool per fort (RealmSim `dead`) | your kills; Relish's redirect | haulers; Relish's raise; garrisons ship them to Vei | a pip count per fort |
| **bodies (in town)** | stream into a capped store | haulers; worker rot; dungeon hauls | raising pits (mint feed), bone mill, slab | net /s plus store bar |
| **gold** | stream | living trade at the market; contracts | building upkeep; build costs | net /s |
| **bone** | stream | bone mill (bodies → bone) | build costs; upkeep of some buildings | net /s |
| **relics** | countable stock | dungeons only | higher buildings, forge levels | count |
| **blueprints** | countable set | dungeons only | unlock building types | set |
| **essence (banked)** | countable stock | dungeons (carried out) | slab, phylactery charges | count |
| **husks, remnants** | countable stock | dungeons | slab | count |
| **living townsfolk** | stream | migrants from held villages; the inn | departures when morale is low | in /s, out /s, net |
| **quality `q`** | level | forge level, big-undead foremen, dungeon raises | none | a number |
| **big undead** | countable stock (named) | slab | dungeon deaths; the Vei fight | names and count |
| **Vei backlog** | RealmSim `vei.undead_queue` | FLOOD, drain, chaff, Relish's raise | Vei's digestion | count, sign and drain time |

**Rule: no unbounded stocks.** Every store has a cap or a sink that scales with the economy. A test
runs a 4 h autoplay and asserts that no stock grows without bound (BALANCE §4).

## 3. Macro: the realm

### 3.1 RealmSim (kept)
- The canonical continuous-rate sim, scaled ×1/100, with Necropolis's documented extensions: EMPTY,
  the pool cap, `k_clear` and simulacra.
- The asymmetry is load-bearing and unchanged: your kills stay as corpses at the fort, and the
  garrison's kills ship to Vei.
- Vei digests with the `cheap` policy.

### 3.2 The valve (D1)
- `mint = P_base_eff`, from GameState: the raising pits' base plus per-pit output, times the body
  feed bonus while bodies > 0.
- `work = mint · v.work`, `war = mint · v.war`, `flood = mint · v.flood`.
- `war` goes to RealmSim as `cov` dispatch (distance-weighted, bent by the tide).
- `flood` goes straight into `vei.undead_queue` (it replaces `directShare`).
- `work` goes to TownSim's worker inflow.
- Default valve: `config valve.default`. The valve changes no faster than `valve.slew_per_s` (a slew
  limit), so a flick of the slider reads as a tide turning, not a teleport.

### 3.3 Relish's location (D2, D3)
Relish is always in exactly one place: Covington, travelling, at a fort, in a dungeon (at a fort),
in the Vei fight, or respawning (nowhere).

- **Travel.** `relish.travel_speed` px/s along a straight line. Visible on the map.
- **At a fort (the tide).** Covington's WAR dispatch weight for that fort is multiplied by
  `relish.tide_bias`, so the stream visibly leans toward her.
- **At a fort (the redirect).** While she stands there and isn't in its dungeon:
  - that fort's garrison kills **stay as corpses at the fort** instead of shipping to Vei;
  - she raises the fort's corpses into undead at `relish.raise_rate`, and those undead drain to Vei
    as undead (costing her `q` each, not 1).

  Corpses that were Vei's recruits become her burden.
- **At Covington.** The crypt slab works (§4.6). Policies get `relish.home_policy_bonus`, an extra
  rule evaluation per beat. Workers rot `relish.home_rot_mult` slower; their mistress is watching.
- **In a dungeon.** Covington's tide applies; the redirect doesn't.
- **Respawning.** No tide, no redirect, no slab, and policies run without the home bonus.

### 3.4 Fort flips (D4)
- When a dungeon result has `warden_beaten: true`, the fort becomes **held** for
  `flip.hold_s * (1 + 0.25 · tier)` sim seconds.
- While held:
  - Vei ships no living into it;
  - its living are 0 (they became corpses in the dungeon writeback);
  - it injects necrosis like a source;
  - haulers working it get `flip.haul_mult`.
- When the hold expires, Vei can ship again. A held fort with undead present takes longer to retake,
  since the normal sim contest applies.
- `view_fort` exposes `held_s_left`.

### 3.5 Readouts (the audit's A1 and A2)
- **Sustained differential:** clone the RealmSim, mark Relish as idle, run `readout.settle_s` sim
  seconds, and read the differential. Done every `readout.refresh_s`, off the main tick, on a cloned
  state. The sign shows as ▲/▼.
- **Drain time** = `backlog / -diff` if diff < 0, else ∞ ("holding").
- **Odds** = `backlog / (backlog + K)`.
- Vei's view shows all three. The confrontation dialog shows all three before committing.

## 4. Economic: Covington

### 4.1 Workforce (D5)
- `workers' = work_inflow − workers / lifetime − muster`.
- `lifetime = worker.lifetime_s × (1 + embalmer bonus) × home_rot_mult (when Relish is home)`.
- **Rot produces bodies:** `rot · worker.body_return`.
- Workers fill **job slots** in priority order (policies can change it). Unfilled slots show empty.
  Unassigned workers idle at the crypt, where they make nothing but rot slower (`worker.idle_rot_mult`).
- Steady state = `work_inflow × lifetime`; `view_town` exposes it so the player sees the target the
  stream is heading for.

### 4.2 Jobs
| job | building | effect per worker |
|---|---|---|
| haul | charnel house | moves corpses from forts to bodies (a convoy on the map; the gather loop kept, generalised to N haulers) |
| mill | bone mill | bodies → bone at `job.mill.rate` |
| stall | market | sells to the living: gold = `min(stalls, living · market.shop_rate)` · price |
| forge | forge | quality `q` progress toward the next forge level (forge levels also need relics) |
| pit | raising pit | burns bodies for the mint feed bonus |
| tend | chapel of vats | grows clones (§7); vats only grow while staffed |
| build | any construction | build progress |
| muster | the gate | moves workers into WAR (a policy action, or a slot) |

### 4.3 Living townsfolk
- `living' = migrants − departures`.
- `migrants = Σ held villages · town.migrant_rate + inn level · inn.attract`.
- `departures = living · town.leave_rate` when morale < `morale.leave_below`.
- `morale` ∈ [0, 1], with gains and penalties per minute:
  - **raised by** amenities (inn, market, plaza, statue, chapel);
  - **lowered by** the undead to living ratio above `morale.dread_ratio`, by any unstaffed amenity,
    and by `morale.death_shock` each time Relish dies without a backup (decays over
    `morale.shock_s`).
- **The living interact.** Each living agent's day cycles through market → inn → home. At the market,
  every stall interaction is one visible trade between a living agent and an undead stall-keeper.
  The trade rate is the gold formula in §4.2. The view draws one arc per trade event, sampled, never
  more than `view.max_trade_arcs`.

### 4.4 Buildings
Defined in `configs/buildings.json`. Each entry has:
- `cost` (gold, bone, relics), `upkeep` (gold/s, bone/s);
- `build_work` (worker-seconds), `jobs` (slots), `effects` (named modifiers);
- `requires` (blueprint id, town tier, other buildings);
- `lot_size`, `tier`.

The town has a fixed lot grid (`configs/town.json`: lots with positions and sizes). Tiers are
reached by building count plus required buildings:
- **Hamlet** to start;
- **Village**: 6 buildings and a market;
- **Town**: 12 buildings, walls and a chapel;
- **City**: 20 buildings, a cathedral and a library.

Starting catalogue (the town worker can add flavour; the economy unit implements the effects):

| building | role | notes |
|---|---|---|
| Crypt | start; holds the slab; idle workers rest here | already built |
| Raising Pit (×n) | +mint; pit job burns bodies for a feed bonus | the old "slab" count |
| Charnel House | haul job; body store cap | |
| Bone Mill | mill job | |
| Market | stall jobs; living trade → gold | Village gate |
| Inn | living migration and morale | |
| Forge | forge job; q levels need relics | |
| Embalmer | + worker lifetime | "create undead faster" lives here and in the pits |
| Chapel of Vats | vat slots; tend job | Town gate |
| Ossuary Tower | crafts simulacra | |
| Guildhall | + policy slots | |
| Watchtower | shows each fort's loot hint and warden tells before descending | |
| Alchemist | banks essence; crafts phylactery charges | |
| Walls and Gate | Town tier; + morale; muster slot | |
| Plaza / Statue of Relish | morale | |
| Library | blueprint research (turns essence and time into a known blueprint) | City gate |
| Cathedral of Bone | big-undead cap +; final-test prep | City |

### 4.5 Policies (Gambits, T4)
- **Slots:** `policy.base_slots` (3), plus 1 per Guildhall level.
- **A rule** is `{when: {metric, op, value}, then: {action, arg}}`, in priority order. Evaluation is
  once per beat (1714 ms sim). Higher slots win conflicts on the same action kind.
- **Metrics:**
  - `bodies`, `bodies_rate`, `gold_rate`, `bone_rate`;
  - `workers`, `living`, `morale`;
  - `vei_diff_sign`, `backlog`;
  - `relish_home`, `relish_away`, `relish_dead`;
  - `any_fort_held`, `always`.
- **Actions:**
  - `prefer_job(job)`: moves that job to the top of the fill order this beat;
  - `muster(fraction)`: idle workers → WAR;
  - `valve(work, war, flood)`: overrides the player's valve while the rule holds;
  - `guard_vats`: tend slots fill first;
  - `hold_home`: no muster.
- The view records which rules fired each beat, so the town scene can flash the affected agents.
- **Defaults** ship in slots 1–2, so the town runs well untouched: "if bodies < N, prefer haul" and
  "if Relish is dead, guard the vats". Commands are optimisation, not maintenance.

### 4.6 The crypt slab: big undead (T5)
- **Only while Relish is home**, in the town scene's crypt view.
- **Input:** one husk, up to N remnants matching its anatomy slots, bodies, and essence.
- **Output:** one named big undead with stats: power, beef, speed, wits and presence, plus a role
  verdict and an Adjective-Noun name.
- Ported from `slab/`: `build_state.gd`, `creature_namer.gd`, `creature_role.gd`, the live-morph
  preview and hold-to-raise.
- **Big undead are placed** (`cmd_place_big_undead`) in exactly one spot:
  - **town foreman:** + that building's output;
  - **fort siege:** + kill power at that fort, and it slows the fort's retake;
  - **party:** goes into the next dungeon or the Vei fight;
  - **crypt:** resting.
- They die only in dungeons or the Vei fight. Cap: `big_undead.cap`, raised by the Cathedral.

## 5. Micro: dungeons
- **Entry.** Relish must be at the fort (travelled there), then DESCEND. The seed comes from the fort:
  - tier and cap;
  - living (scaled to a room population);
  - corpses (pre-placed piles);
  - your undead at that fort, which make up the party along with any big undead placed in `party`.
- **Layout.** Procedural rooms seeded per fort (kept from Necropolis). The last room is the
  **warden's**.
- **Circles.**
  - Trance, then trace, then a Kåsa score of 0–100 (kept).
  - **Quality is continuous:** each raised undead gets the stat multiplier `0.5 + score/100`.
  - Display tiers stay as names (<60 chaff, 60–89 soldier, ≥90 elite), but the number is what's used.
  - Every essence mote inside the circle raises one undead.
- **Essence (D8).** Every death drops motes:
  - living kills drop `essence.per_living`;
  - your fallen undead drop `essence.per_undead_mult` × their quality.

  Motes decay after `essence.life_s` of world time. Carried essence banks at exit.
- **The warden (D3)** comes from `RaidLogic.warden_spec(fort)`, with a mechanic per warden archetype:
  - **Bellringer:** telegraphed ring slams on the beat.
  - **Shieldwall:** frontal immunity; flank with fast undead.
  - **Pyre-priest:** burns corpses, denying essence; kill the acolytes first.
  - **Huntsman:** targets Relish directly; the sacrifice chain is the counter.

  Every warden has 2–3 phases, at HP thresholds or on timers, a weak point that a role (big undead or
  tier) exploits, and a telegraph on the tempo.
- **Last-chance beat.** Entering the warden's antechamber grants one free trance with no cooldown,
  and every mote in the room lit.
- **Loot.** Rolled from `configs/loot.json` by fort tier and archetype:
  - relics, a blueprint (by chance, guaranteed on first clear), husks, remnants;
  - the warden's chest on its death;
  - remnants "ding" off kills during the run.

  Watchtower hints bias the roll (prior art: crypt's reward bias).
- **Exits:**
  - **warden beaten:** loot banked, fort flips;
  - **retreat** through the exit: loot banked, no flip;
  - **Relish dies:** §7.
- Raised undead return to the fort's undead pool (mass weighted by quality). Chaff (< 60) is thrown
  at Vei's queue (kept from Necropolis).

## 6. The final test: Vei
- **Available any time** from Vei's node. The dialog shows the odds, the sign, the drain time, the
  four fronts and what is assigned to each.
- **Fronts** (`configs/vei.json`):

  | front | what clears it |
  |---|---|
  | giants | big-undead power |
  | swarm | backlog mass |
  | carvers | average quality `q` |
  | raw | total power |

  Each has a threshold that scales with Vei's living pool. The player sees "have X / need Y" per
  front; legibility was the crypt playtest's verdict.
- **Fight.**
  - Phase 1: the fronts play out as streams on the field (horde vs her guard). Clearing
    `vei.fronts_required` (3 of 4) exposes Vei.
  - Phase 2: Vei hunts Relish, with telegraphed weaves on the tempo. Relish's party and the
    remaining horde must break her.
  - Each Relish death in the fight spends one backup: phylactery charges first, then ready clones. If
    none are left, the fight is lost.
- **Win:** `won = true`, the victory sequence plays, and the game is beaten. Play can continue
  (endless; the town keeps growing).
- **Lose:**
  - backlog × `vei.loss_backlog_mult`;
  - the party's big undead die;
  - Relish follows §7 for the last death.

## 7. Death and backups (D9)
**Relish dies when** her HP hits 0 in a dungeon or the Vei fight. The sacrifice chain comes first:
chaff, then soldiers, then big undead in the party, then Relish.

**Outcomes, in order:**
1. **Phylactery charge** (crafted at the alchemist with essence and a relic): she revives in place at
   `phylactery.revive_hp`. One charge per use. In dungeons, at most `phylactery.max_per_dungeon` per
   run.
2. **A ready clone** (vat staffed and clone grown): she wakes in Covington after
   `backups.clone_respawn_s`.
   - The party is lost, and so is unbanked loot (carried essence, uncollected chest).
   - The fort doesn't flip.
3. **Unmade** (no clone ready): she reforms after `backups.unmade_respawn_s`.
   - Unbanked loot is lost.
   - Morale takes `morale.death_shock`.
   - Policies drop to `policy.base_slots − 1` until she's back.

**Clones** grow at `vats.grow_per_s` per staffed vat, from 0 to 1. A vat holds one clone. An
unstaffed vat doesn't grow its clone (prior art: the Cloning Vat needs staff). The town scene shows
every vat's clone as a countable growing silhouette.

## 8. Result schemas (v2)
```
raid:  {v:2, fort_id, warden_beaten:bool, retreated:bool, relish_died:bool, revived_in_place:int,
        killed_living_mass, raised:[{score:int, mass:float}], chaff_mass, garrison_mass,
        party_lost:[uid], loot:{relics:int, blueprints:[id], husks:[id], remnants:[{aspect, rarity, magnitude}],
        essence:int}}
town:  {v:2}  (town commands are applied live through cmd_*; the scene returns only {v:2, teleport_to})
slab:  {v:2, big_undead:{uid, name, husk, stats:{}, role}, spent:{husk, remnants:[...], bodies, essence}}
boss:  {v:2, won:bool, fronts_cleared:[id], relish_deaths:int, backups_spent:{phylactery:int, clones:int},
        party_lost:[uid], backlog_spent}
```
`apply_result` validates the keys and fails loudly on a mismatch. Tests cover every kind.

## 9. Config files and owners
| file | owner | contents |
|---|---|---|
| `realm.json` | economy | RealmSim tunables (kept), `valve.*`, `relish.*`, `flip.*`, `readout.*` |
| `economy.json` (new) | economy | `worker.*`, `job.*`, `town.migrant_rate`, `morale.*`, `market.*`, `inn.*`, `sim.substep_s` |
| `buildings.json` (new) | economy (effects), town (art/flavour fields) | catalogue |
| `policies.json` (new) | economy | metrics, actions, default rules, slots |
| `backups.json` (new) | economy | vats, clones, phylactery, respawn times |
| `loot.json` (new) | dungeon | tables by tier and archetype |
| `vei.json` (new) | dungeon | fronts, thresholds, fight phases |
| `raid.json` | dungeon | kept, plus warden archetypes and essence |
| `town.json` | town | lot grid, view settings |
| `world.json` | map / economy | board layout |
| `palette.json`, `pulse.json` | foundation | look |

## 10. Tests required (headless)
- **GameState:** every `cmd_*` (ok and refusal paths), every `apply_result` kind, `to_dict`/`from_dict`
  round-trip.
- **Valve:** conservation (work + war + flood = mint) and the slew limit.
- **Workforce:** steady state ≈ inflow × lifetime; rot returns bodies.
- **Relish:** travel time; the tide raises the dispatch share; the redirect stops dead shipping at
  her fort; nothing applies while she's respawning.
- **Flip:** held blocks shipping and expires.
- **Policies:** priority, conflicts, each metric and action, the default rules.
- **Buildings:** cost, upkeep, effects and tier gates.
- **Backups:** phylactery first, then clone, then unmade; clones grow only while staffed.
- **Readouts:** the sustained sign and the drain time on known states.
- **Pacing** (BALANCE §4): idle never wins; the active autoplayer wins in the target window; no
  unbounded stock.
- **Dungeon:** loot rolls are seeded and deterministic; the warden spec per archetype; essence from
  both sides.
- **Vei fronts:** thresholds, `fronts_required`, backup spending order.
