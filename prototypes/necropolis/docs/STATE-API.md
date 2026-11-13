# Necropolis: GameState API (api_version 1)

The frozen contract between the economy unit (GameState) and the scene units (map, town,
dungeon/boss, ground). `MECHANICS.md` §1.2 is the source of the names; this file gives every
signature, field, type, unit, reason and milestone. Numbers in examples are illustrative, drawn
from `BALANCE.md` §0.

## 1. Purpose, freeze rule, conventions

### 1.1 Freeze rule
- **Names and shapes freeze at E1.** After E1 changes are **additive only**: new commands, views,
  keys, event types, enum values and reasons. No rename, removal or type change.
- Every addition updates `tests/test_api_contract.gd` in the same commit and bumps
  `GameState.API_VERSION`. The test asserts the key sets and value types of every command return,
  view, event, seed and result, and fails on any rename or removal.
- Consumers ignore keys they don't know and treat an unknown `reason` as a generic refusal.
- **Milestones.** At E1 every entry exists. Entries not yet real are backed by a stub that returns
  the documented shape. The tag on each entry is the milestone where its values or effects become
  real:
  - `E1`: live now.
  - `E2`: new streams (valve, workforce, jobs, living, gold, buildings, flips, tithe, `q`).
  - `E3`: stances, backups, Vei fronts.
  - `E1/E2` (or `E1/E3`): recorded and echoed at E1, with its sim effect at the later milestone.
- **E1 stubs.** Setting commands store the setting and echo it in views:
  - `cmd_set_valve`, `cmd_set_haul_target`, `cmd_set_job_priority`, `cmd_set_staff_cap` (live
    from E2a: the valve and TownSim act on them);
  - `cmd_set_stance`, `cmd_staff_vat`, `cmd_assign_front`.

  Action commands (build, upgrade, demolish, cancel, raise, craft, deploy) run their id checks
  (`unknown_*`), then return `ok` with zero-valued extras and change nothing. Stub views return
  BALANCE §0 constants, or legacy-derived values where noted.

### 1.2 Where it lives
- `scripts/sim/game_state.gd`, `class_name GameState extends RefCounted`.
- Every command and view is a method on it. Scenes call `Game.state.cmd_*()` and
  `Game.state.view_*()`.
- **`Game.state` is one instance for the whole session.** `cmd_new_game`, `cmd_load` and
  `cmd_debug_load_fixture` reset it in place and never replace the object, so a scene may keep the
  reference.
- Scenes never mutate state except through commands. GameState never calls into a scene.

### 1.3 Conventions
| topic | rule |
|---|---|
| copies | Every view returns a fresh deep copy; editing it changes nothing. **One exception:** `view_field().field` is the live `InfluenceField` (read it, never write it; see §5.6). |
| `rev: int` | +1 on every substep and every successful command. Session-only: never saved, never reset, never decreases (a load or new game also adds 1). Every view carries the `rev` at call time. Scenes may read `Game.state.rev` directly to skip a refresh. |
| commands | Return `{ok: bool, reason: String, ...extras}`. `reason == ""` iff `ok`. Extras are present on failure too, zero-valued (`0`, `0.0`, `""`, `[]`, `-1` for ids); a nested Dictionary extra is `{}` on failure. The contract test checks nested extras' key sets only when `ok`. An E1 stub returning `ok` fills nested extras with their full key set (e.g. `cost: {gold: 0.0, bone: 0.0, relics: 0}`, and a full `big_undead` entry). A refused command changes nothing and does not bump `rev`. |
| view shape | Every view is a Dictionary with `rev` at the top level. Where MECHANICS gives a bare map or array (`view_rates`, `view_lanes`, `view_villages`), it sits under one named key (`rates`, `lanes`, `villages`). See §10 A11. |
| shared reason | `not_debug`: any `cmd_debug_*`, and the player time controls `cmd_set_time_scale` / `cmd_pause`, while `state.debug_enabled == false`. It is checked first. |
| sentinels | `-1` / `-1.0` = none or not applicable, `""` = no id. No `INF` or `NaN` anywhere in the API. |
| ids | Always `String`: node ids (12 forts from `world.json`, plus `"covington"` and `"vei"`), village ids, lot ids `"lot-01"`..`"lot-24"`, building, job, stance and front ids, item uids, slots, fixture names. Two exceptions are `int`: `run_id` and the vat `slot` index. |
| uids | Opaque `String`s minted by GameState from one counter: husks `h<n>`, remnants `r<n>`, big undead `u<n>` (e.g. `"h1"`, `"r2"`, `"u4"`). Unique across kinds and never reused. |
| positions | World pixels in `world.json` coordinates (2048 × 1440), always `[x: float, y: float]`, in views, events and saves alike. Convert with `Vector2(p[0], p[1])`. Angles are radians, `atan2(dy, dx)`, with y pointing down. |
| time | Sim seconds. Every rate is **per sim-second**. Real time appears only in the `Game` shell. |
| notation | Examples write dictionaries as `{key: value}` for brevity. Every key is a `String`; real call sites quote keys (`{"gold": 500}`). |
| order | Arrays are ordered deterministically: forts in `world.json` order, lots by id, jobs in ladder order, items by uid. |

**Units** (MECHANICS §2):
| unit | used for |
|---|---|
| mass (float) | mint, WORK/WAR/FLOOD, fort `living` / `undead` / `dead`, corpses, bodies, backlog, Vei's pool. Raw Necropolis mass (×1/100 of Realm). |
| workers (float) | the workforce; each worker is `worker.mass` (40) mass. Shown rounded. |
| living (float) | **Covington's people.** Not the same as a fort's `living`, which is mass. |
| gold, bone (float) | their own units, floored at 0 |
| relics (int), essence (int, motes) | capped stocks |

### 1.4 Constants on `GameState`
```gdscript
const API_VERSION := 1
const SAVE_VERSION := 2
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
```
**Ids that come from config:**
- Building ids (`buildings.json`, E1 set): `crypt`, `raising_pit`, `charnel_house`, `market`,
  `house`, `well`, `bakery`, `bone_mill`, `inn`, `forge`, `graveyard`, `embalmer`, `stables`,
  `chapel_of_vats`, `ossuary_tower`, `guildhall`, `watchtower`, `walls`, `plaza`, `statue`,
  `reliquary`.
- A blueprint's id is the building id it unlocks.
- Husk kinds (loot): `skeleton`, `zombie`, `hulk`, `siren`, `lich`, `wraith`, `revenant`.
- Lots `lot-01`..`lot-24` and their sizes are API (`configs/town.json`). Hamlet unlocks the first 8.

### 1.5 Other public members of `GameState`
| member | purpose |
|---|---|
| `_init(configs: Dictionary = {})` | Configs keyed by file basename (`"realm"`, `"economy"`, …); a non-empty dict calls `setup(configs)`. |
| `setup(configs: Dictionary)` | Stores the configs. Call once, before `cmd_new_game`. |
| `static load_configs(dir: String) -> Dictionary` | The one config loader, shared by `ConfigDb` and the tests. |
| `var debug_enabled: bool = false` | The shell sets it from `OS.is_debug_build()`; tests set it to true. |
| `var save_dir: String = "user://saves"` | Tests point it at a temp dir. |
| `var fixture_dir: String = "res://tests/fixtures"` | `cmd_debug_load_fixture` reads `<fixture_dir>/<name>.json`. Tests point it at a temp dir to make a bad fixture. |
| `autosave_s() -> float` | `economy.json` `sim.autosave_s` (30): the shell's autosave period in real seconds. |
| `var rev: int` | Read-only by rule. |
| `tick(dt: float, max_substeps := 0) -> int` | §3. |
| `drain_events() -> Array[Dictionary]` | §6. Called by the shell and tests, **never by scenes**. |
| `to_dict() -> Dictionary`, `from_dict(d: Dictionary) -> Dictionary` | §9. |
| `static migrate(d: Dictionary) -> Dictionary` | §9. |
| `list_saves() -> Array[Dictionary]` | §4.1. |
| `ledger() -> Dictionary` | §4.7 (tests). |
| `legacy_teleport_relish(node_id: String) -> Dictionary` | **Not contract**; §2.2. |
| `raid_seed`, `boss_seed`, `town_snapshot`, `apply_town_result`, `legacy_stores`, `quality` | **Not contract**: compatibility for unported callers, best effort from the new state; §2.2. |
| `var town_sim: TownSim` | **Not contract** (no API_VERSION bump): Covington's economy (MECHANICS §4), created once and reset in place. Tests and the fixture generator use it; scenes read the views. |

## 2. The `Game` shell (`autoload/game.gd`)

### 2.1 Contract
```gdscript
var state: GameState                  # stable for the session (§1.2)
signal game_event(ev: Dictionary)     # one signal for every event, in queue order; filter on ev.type
var autosave_enabled: bool            # false in a harness session; set once at boot, read-only by rule
func autosave() -> Dictionary         # = state.cmd_save("auto"); the router calls it after every swap;
                                      # {ok: false, reason: "disabled"} (nothing written) when !autosave_enabled
```
- **Boot (`_ready`):**
  `state = GameState.new()` once, `state.setup(ConfigDb.data)` (the same `load_configs` output), then
  `state.debug_enabled = OS.is_debug_build()` (before any boot load, since fixtures need it), then
  the boot rule over `OS.get_cmdline_user_args()`:
  - **Harness/test session:** any dev argument is present: `--shot=`, `--new-game`, `--fixture=<name>`,
    `--teleport=`, `--scene=`, `--select=`, `--speed=`, `--cheat=`, `--finish-raid`, `--trace=`,
    `--clicks=` (the `DEV_ARGS` const; `--reduced-motion` is a player flag and is not one).
    `autosave_enabled = false` for the whole session (`autosave()` returns
    `{ok: false, reason: "disabled"}` without writing, and the 30 s timer does nothing), so the
    player's `auto.json` is never touched. The boot state is `cmd_debug_load_fixture(name)` for
    `--fixture=` (if refused, an error is printed and it falls back to `cmd_new_game(randi())`),
    otherwise `cmd_new_game(randi())`.
  - **Normal launch** (none of those args): `cmd_load("auto")`; if that is not `ok` (no file, or
    corrupt), `cmd_new_game(randi())`. Autosave stays enabled, **except** after `bad_version` (a
    newer build wrote `auto.json`; worktrees share `user://`): then autosave is off for the session
    and a warning is printed, so the newer save is never overwritten.
  - Away-time catch-up on load (simulating the real time since the save file's `saved_at`) is a later
    item. Today a resume continues from the saved `t`.
- **Ticking (`_process(delta)`):**
  `state.tick(delta / maxf(0.05, Engine.time_scale) * state.time_scale, max_substeps)`. Here
  `max_substeps` is `economy.json` `sim.max_substeps_per_frame`, and any remainder over the cap is
  dropped (§3).
  - The sim runs on **real** delta. Trance's `Engine.time_scale` never slows the realm.
  - `tick` itself honours `paused`.
- **Events:** each frame, after ticking, the shell drains `state.drain_events()` and emits
  `game_event(ev)` for each event, in order.
- **Autosave:** every 30 real seconds (unscaled delta) and on every scene change (the router calls
  `autosave()`). The resulting `autosaved` / `save_failed` events reach scenes through
  `game_event`.
- **Legacy signals** keep firing until the map unit drops them. Each fires after the
  `game_event` for the same event:

  | legacy signal | fired from |
  |---|---|
  | `relish_respawned(with_vat: bool)` | event `relish_respawned`, with `with_vat = ev.with_clone` |
  | `victory` | event `vei_result` with `won == true` |
  | `defeat_boss` | event `vei_result` with `won == false` |

  `realm_ticked` is removed at E1 (it has no listeners).

### 2.2 Legacy (will be removed)
**New code must use views and commands.** These members exist only so unported scenes keep running.
Each is deleted when its last reader is ported. From E2a (T2.3b) the forwarders are filled from the
new state as a best effort, and writes to them are ignored; `time_scale` is the exception.

| member on `Game` | forwards to | today's readers |
|---|---|---|
| `realm: RealmSim` | `state.realm`, a live object replaced on new game or load, so re-read it on every use | map_nodes, map_routes, world_map, shot |
| `field: InfluenceField` | `state.field` (same caveat) | world_map, map_field_view |
| `towns: Array` | legacy village list (`{id, name, pos: Vector2, pop, control: green\|orange\|none}`) | map_nodes, world_map |
| `res`, `army`, `town`, `assignments`, `idle_undead`, `gather` | fresh dicts from `state.legacy_stores()`, rebuilt on every read (below); writes change nothing | world_map, map_routes |
| `won` | `state.won` | world_map |
| `time_scale: float` | get: `state.time_scale`. Set: writes `state.time_scale` **unvalidated** (any value > 0). Keeps working in release builds; used by the map's ×1/×10/×60 buttons and `--speed=`. | world_map, shot |
| `quality() -> float` | `state.quality()`, which is `digest_q()` | world_map |
| `raiding_fort_id() -> String` | the active raid run's fort id, or `""` | map_nodes, shot |
| `raid_seed(fort_id)`, `boss_seed()`, `town_snapshot()` | `state`'s compatibility members (below) | the router, for unported scenes (§2.3) |
| `apply_town_result(r)` | `state.apply_town_result(r)`, a no-op from E2a | the router, for an unported town scene |

**`legacy_stores()`** (E2a, what `Game`'s legacy getters read): the E1 stores rebuilt from TownSim and
the backups stock, every count an `int`:
- `res = {gold, materials: bone, bodies, townsfolk: living}`;
- `army = {soldier: 0, elite: 0}` (the army is gone);
- `town = {slabs: working pits, vats: clones_ready, forge_level, sim_stations: 0, trade_level: 0}`;
- `assignments`: staffed workers per old job, rounded: `trade` (stall), `forge`, `jobs` (build),
  `gather` (haul), `slab` (pit); `idle_undead`: idle workers, rounded;
- `gather = {target, phase, eta, load}`: TownSim's convoy (`eta = (1 − t) · trip_s`), or phase `idle`
  with the set haul target (`""` for `auto`) when none is out.

**Compatibility members on `GameState`** (not contract; each is marked `# legacy: delete when map
drops the call` and goes when the map unit drops its call):

| member | E2a behaviour | why it stays |
|---|---|---|
| `raid_seed(fort_id)` | the pre-E1 raid seed keys (`fort_id, name, tier, cap, living, undead, dead, boss: false, quality`) from the live fort and `q`; `{}` for an unknown fort | `scripts/main.gd` merges it into an unported dungeon's args |
| `boss_seed()` | the pre-E1 boss seed keys, with `quality`, `backlog`, `vei_capacity` and `odds` live and `army: {soldier: 0, elite: 0}` | `scripts/main.gd` merges it into an unported boss's args |
| `town_snapshot()` | `{}` (the town reads views) | `scripts/main.gd` merges it into the town's args |
| `apply_town_result(r)` | a no-op (town actions are commands) | `scripts/main.gd` calls it for a legacy town result |
| `legacy_stores()` | above | `Game`'s getters (world_map, map_routes) |
| `quality()` | `digest_q()` | `Game.quality()` (world_map) |

**Removed at E1** (replaced by commands): `new_game`, `begin_raid`, `end_raid`, `apply_raid_result`,
`auto_resolve_raid`, `apply_boss_result`, `auto_resolve_boss`. shot.gd's cheats move to
`cmd_debug_*` (from E2a `--cheat=boss` no longer writes `Game.army`).

**Removed at E2a:** `scripts/sim/legacy_economy.gd` (`LegacyEconomy`) and `GameState`'s `legacy`, `res`,
`army`, `town`, `assignments`, `idle_undead` and `gather` members. TownSim is the town.

**`GameState.legacy_teleport_relish(node_id: String) -> {ok, reason}`** is not contract:
- It puts Relish, alive, at the node at once, with state `home`, `at_fort` or `at_vei`.
- It refuses with the same reasons as `cmd_move_relish` and bumps `rev`.
- The router uses it only for today's map TELEPORT button (a legacy map result without `v`). It is
  removed when the map unit ships the travel UX.

### 2.3 Router and scene contract (`scripts/main.gd`; economy through E1, then map)
Every scene implements:
```gdscript
func setup(args: Dictionary) -> void      # ids only
signal finished(result: Dictionary)
```
| mode | `args` | the scene reads | `finished(result)` |
|---|---|---|---|
| map | `{mode: "map"}` | views | `{v: 2, teleport_to: String}` |
| town | `{mode: "town"}` | views | `{v: 2, teleport_to: String}` (all town actions are commands) |
| dungeon | `{mode: "dungeon", fort_id: String, run_id: int, seed_rev: int}` | `view_dungeon_seed(fort_id)` (§7.1), views | raid result v2 (§8.1) |
| boss | `{mode: "boss", run_id: int, seed_rev: int}` | `view_boss_seed()` (§7.2), views | boss result v2 (§8.2) |

- **E1 compatibility.** Until a scene is ported, the router also merges that scene's legacy seed
  keys into `args`:
  - dungeon: `Game.raid_seed(id)`;
  - boss: `Game.boss_seed()`;
  - town: `Game.town_snapshot()` (`{}` from E2a: the town reads views).

  Ported scenes ignore unknown `args` keys.
- **`teleport_to`** names the node whose scene opens next; `""` means the map. With `v: 2` it never
  moves Relish.
- **Router flow:**
  - `teleport_to` handling:
    - `"covington"`: open the town.
    - `"vei"`: call `cmd_begin_boss()`. On `ok`, open the boss; otherwise the map (which shows
      `view_vei().reason`).
    - a fort id: call `cmd_begin_dungeon(id)`. On `ok`, open the dungeon; otherwise the map.
    - an unknown id: open the map.
  - A map or town result **without `v`** (legacy): first `legacy_teleport_relish(id)` for a map
    result, or `Game.apply_town_result(r)` for a town result, then the flow above.
  - A dungeon or boss result:
    - without `v`, convert it with `Results.from_v1(kind, r, seed)` (§8.5);
    - then call `apply_result(kind, r)`;
    - if that refuses, `push_warning` and `cmd_abort_dungeon()`, so no run stays open;
    - then open the map.
  - A scene file that is missing or fails to load: `cmd_abort_dungeon()` if a run is open, then the
    map.
  - **Stale emits.** `finished` is connected before the scene is added or `setup` runs, bound to
    the emitting node. A `finished` from a node that is not `current` (a freed or replaced scene)
    is ignored, and so is any second `finished` from a node already handled.
  - **No run under the map or town.** Whenever the router is about to open the map or the town and
    `view_relish().run_id != -1`, it calls `cmd_abort_dungeon()` first (with a `push_warning`).
    "Map or town open with a run open" is unreachable.
- **On every swap:** `Engine.time_scale = 1.0`, the old scene is freed, the new one gets
  `setup(args)`, then `Game.autosave()`.
- Dungeon and boss runs force the sim's `time_scale` to 1 (§4.5).

## 3. Ticking and order

```gdscript
func tick(dt: float, max_substeps := 0) -> int   # returns the substeps run
```
- `dt` is plain sim seconds; the shell applies the time scale. It returns 0 and does nothing while
  `paused`, or when `dt` is not finite or `<= 0`.
- **Accumulator:**
  - `acc += dt`, then `n = floor(acc / sim.substep_s)` (`sim.substep_s` = 0.5).
  - If `max_substeps > 0` and `n > max_substeps`: run `max_substeps` and set `acc = 0`. The
    remainder after a hitch is dropped.
  - Otherwise `acc -= n * sim.substep_s`. The remainder is kept and saved.
  - `max_substeps = 0` means uncapped; tests and `cmd_debug_skip_time` use it.
- Each substep advances `t += sim.substep_s`, runs the steps below **in this order** (a contract
  with tests, MECHANICS §1.3), then `rev += 1`:
  1. **Stances and the job ladder.** Re-evaluated only when the beat index
     `beat_id = floor(t / beat_s)` changes, where `beat_s = pulse.json tempo_ms / 1000` (1.714).
     Emits `stance_fired`.
  2. **TownSim.** Workforce, using the previous substep's WORK (one substep late, which is
     accepted). Also jobs, haul, mill, pit burn, living, gold, bone, morale, construction and
     upkeep. Emits `building_*` and `tier_up`.
  3. **The valve.** Slew the current vector toward the target by at most `valve.slew_per_s · dt` of
     L1 distance (the sum stays 1). Split mint into WORK, WAR and FLOOD, and add muster to WAR.
  4. **Relish's travel and state** (GameState). Position, heading and arrival.
  5. **`RealmSim.step(dt, {war, flood, digest_q, tide_fort, tide_bias, redirect_fort, redirect_rate, siege_block})`.**
     Holds and the tithe state are RealmSim's own, not inputs (MECHANICS §3.1). Includes hold
     expiry and the tithe cycle, which starts at the first flip. Emits `fort_retaken`,
     `tithe_warning` and `tithe_wave`. `tide_fort` is also where Relish stands, so a surge there
     is halved; `siege_block` (fort id → the fraction of a surge a siege cancels) is `{}` until E3.
  6. **Backups.** Vats grow and respawn timers count down; Backups is the only writer of death and
     respawn. Emits `relish_respawned`.
  7. **The ledger.**
  8. **Readouts.** `diff`, its EMA over `readout.ema_s`, sign, drain time and odds.
  9. **The influence field** at `field.tick_hz`, time-sliced (owned by the ground unit after E1).
     `field.advance(budget_cells)` is called once per `tick(dt)` call, after the
     substep loop, whether or not a substep ran (not when `tick` returns early: paused, or `dt` not
     finite or <= 0). `budget_cells` is `field.slice_budget_cells`: work units (field cells processed)
     per call, `0` = no slicing; the field publishes `field.lag_ticks` late at every budget (§5.6). Determinism holds because the field publishes only inside
     `field.tick()`: `advance()` only fills a back buffer from a snapshotted input, and `tick()`
     finishes any remainder synchronously, so frame cadence changes cost, never results.
- Commands apply **immediately** when called, between frames. Their events carry the current `t`.
- The sim keeps ticking while any scene is open, including dungeons. Writebacks are clamped deltas
  (§8.3).

## 4. Commands

The format for each entry is: signature · milestone, arguments, extra return keys, reasons in check
order, effect, example. Every command also returns `ok` and `reason`.

### 4.1 Game
**`cmd_new_game(seed: int)` · E1**
- **Reasons:** `busy` (a dungeon or boss run is open).
- **Effect:**
  - Rebuilds the BALANCE §0 start state from configs, in place: TownSim's opening (`economy.json`
    `opening`: the Crypt, a Raising Pit, the Charnel House and a small Market on lots 1–4;
    gold/bone/bodies 80/30/40; 12 workers; 10 living of 16; the default ladder), the opening valve,
    Relish home with no phylactery charge or clone, Old Sluice flagged first.
  - Sets `t = 0`, `time_scale = 1`, `paused = false`.
  - Clears the event queue.
  - Leaves `run_id` and the uid counters running: they never repeat within a session.
```gdscript
Game.state.cmd_new_game(1)  # -> {ok: true, reason: ""}
```

**`cmd_save(slot: String)` · E1**
- **Args:** `slot` matches `^[a-z0-9_-]{1,32}$`. `"auto"` is the autosave slot.
- **Extras:** `saved_at: int` (unix seconds), `path: String`.
- **Reasons:** `bad_slot`, `write_failed`.
- **Effect:** writes atomically (§9.3).
  - During a run it writes the forfeited form (Relish at the fort, no run) and leaves the live state
    alone.
  - On success with slot `"auto"` it emits `autosaved`. On any failure it emits `save_failed`.
```gdscript
Game.state.cmd_save("slot1")  # -> {ok: true, reason: "", saved_at: 1794556800, path: "user://saves/slot1.json"}
```

**`cmd_load(slot: String)` · E1**
- **Reasons:** `busy`, `bad_slot`, `no_save` (missing or corrupt; a corrupt file is no save),
  `bad_version` (newer than `SAVE_VERSION`, or the migration failed).
- **Effect:** `from_dict` in place. Then `time_scale = 1`, `paused = false`, the event queue is
  cleared, and the field is pre-warmed (§9).
```gdscript
Game.state.cmd_load("auto")  # -> {ok: false, reason: "no_save"}
```

**`list_saves() -> Array[Dictionary]` · E1.** Not a command, and does not bump `rev`.
- Returns `[{slot: String, saved_at: int, summary: String}]`, newest first. Corrupt files are
  omitted.
- `summary` is display text such as `"1:04 · Village · odds 0.08"`.
```gdscript
Game.state.list_saves()  # -> [{slot: "auto", saved_at: 1794556800, summary: "1:04 · Village · odds 0.08"}]
```

**`cmd_set_time_scale(x: float)` · E1**
- **Args:** exactly `1.0`, `2.0` or `4.0`.
- **Extras:** `time_scale: float`.
- **Reasons:** `not_debug`, `in_dungeon`, `in_boss`, `invalid_scale`. `not_debug` is checked first:
  player time controls are debug-only; the idle model runs the realm at 1×.
- Debug speeds (×10, ×60) go through `cmd_debug_set_state({time_scale: x})`; the legacy
  `Game.time_scale` setter also works (§2.2). `time_scale` is not saved: a load starts at 1.
```gdscript
Game.state.cmd_set_time_scale(4)  # -> {ok: true, reason: "", time_scale: 4.0}
Game.state.cmd_set_time_scale(3)  # -> {ok: false, reason: "invalid_scale", time_scale: 1.0}
```

**`cmd_pause(b: bool)` · E1**
- **Extras:** `paused: bool`.
- **Reasons:** `not_debug` (checked first; player time controls are debug-only).
- Pauses only the realm sim. Accepted anywhere (in debug). `paused` is not saved.
```gdscript
Game.state.cmd_pause(true)  # -> {ok: true, reason: "", paused: true}
```

### 4.2 Macro
**`cmd_set_valve(work: float, war: float, flood: float)` · E1/E2**
- **Extras:** `target: {work: float, war: float, flood: float}`, normalised to sum 1.
- **Reasons:** `not_finite`, `negative`, `zero_valve` (all three are 0).
- **Effect:** sets the target. The current vector slews toward it (§3, step 3); the slew and the
  split are E2.
```gdscript
Game.state.cmd_set_valve(2, 2, 1)  # -> {ok: true, reason: "", target: {work: 0.4, war: 0.4, flood: 0.2}}
Game.state.cmd_set_valve(0, 0, 0)  # -> {ok: false, reason: "zero_valve", target: {}}
```

**`cmd_move_relish(node_id: String)` · E1**
- **Args:** a fort id, `"covington"` or `"vei"`. Village ids are unknown nodes.
- **Extras:** `eta_s: float` (sim seconds; 0 when she is already there).
- **Reasons:** `dead`, `in_dungeon`, `in_boss`, `unknown_node`.
- **Effect:**
  - She travels the straight line at `relish.travel_speed` (220 px/s), tracking `pos`.
  - A retarget mid-travel starts from where she is.
  - On arrival her state becomes `home` (Covington), `at_fort` or `at_vei`.
  - Moving to the node she stands at, or to her current target, is a no-op `ok`.
```gdscript
Game.state.cmd_move_relish("old-sluice")  # from Covington -> {ok: true, reason: "", eta_s: 1.64}
```

**`cmd_cancel_travel()` · E1**
- **Extras:** `eta_s: float`.
- **Reasons:** `not_travelling`.
- **Effect:** retargets her to `at`, the node she left, starting from where she is. If she is
  already heading to `at`, it is a no-op `ok`.
```gdscript
Game.state.cmd_cancel_travel()  # -> {ok: true, reason: "", eta_s: 0.82}
```

**`cmd_set_haul_target(target: String)` · E1/E2**
- **Args:** a fort id or `"auto"` (the richest corpse fort).
- **Extras:** `haul_target: String`.
- **Reasons:** `unknown_fort`.
- **Effect (E2a):** TownSim's convoy takes it from its next departure (a named fort is worked even
  with no dead there); a convoy already out finishes its trip.
```gdscript
Game.state.cmd_set_haul_target("ashgate")  # -> {ok: true, reason: "", haul_target: "ashgate"}
```

### 4.3 Town
Reasons shared by the build family, in check order:
- `unknown_building`, `unknown_lot`;
- `lot_locked` (the current tier doesn't open the lot);
- `lot_taken`, `lot_too_small`, `empty_lot`, `under_construction`;
- `needs_tier`, `needs_blueprint`, `needs_building`;
- `no_gold`, `no_bone`, `no_relics`.

**`cmd_build(building_id: String, lot_id: String)` · E2**
- **Extras:** `cost: {gold: float, bone: float, relics: int}`.
- **Reasons:** `unknown_building`, `unknown_lot`, `lot_locked`, `lot_taken`, `lot_too_small`,
  `needs_tier`, `needs_blueprint`, `needs_building`, `no_gold`, `no_bone`, `no_relics`.
- **Effect:** pays the cost at once and starts construction, which the `build` job advances by
  `build_work`. Emits `building_started`, and `building_done` when finished.
```gdscript
Game.state.cmd_build("house", "lot-05")  # -> {ok: true, reason: "", cost: {gold: 40.0, bone: 10.0, relics: 0}}
Game.state.cmd_build("inn", "lot-06")    # -> {ok: false, reason: "needs_tier", cost: {}}
```

**`cmd_upgrade(lot_id: String)` · E2**
- **Extras:** `level: int` (the target level), `cost: {gold, bone, relics}` from `level_costs`.
- **Reasons:** `unknown_lot`, `empty_lot`, `under_construction`, `max_level`, `needs_tier`,
  `no_gold`, `no_bone`, `no_relics`.
- **Effect:** pays, then runs construction like a build. The building keeps working at its old
  level until the upgrade is done.
```gdscript
Game.state.cmd_upgrade("lot-04")  # -> {ok: true, reason: "", level: 2, cost: {gold: 80.0, bone: 30.0, relics: 0}}
```

**`cmd_demolish(lot_id: String)` · E2**
- **Reasons:** `unknown_lot`, `empty_lot`, `under_construction` (use `cmd_cancel_build`),
  `protected` (the Crypt).
- **Effect:** frees the lot with no refund. A foreman placed there returns to the crypt.
```gdscript
Game.state.cmd_demolish("lot-03")  # -> {ok: true, reason: ""}
```

**`cmd_cancel_build(lot_id: String)` · E2**
- **Extras:** `refund: {gold, bone, relics}`.
- **Reasons:** `unknown_lot`, `not_building`.
- **Effect:**
  - Refunds the full cost; relics are clamped to the cap.
  - A cancelled new build frees the lot. A cancelled upgrade keeps the old level.
```gdscript
Game.state.cmd_cancel_build("lot-05")  # -> {ok: true, reason: "", refund: {gold: 40.0, bone: 10.0, relics: 0}}
```

**`cmd_set_job_priority(order: Array)` · E1/E2**
- **Args:** a permutation of `JOB_IDS`, top first.
- **Extras:** `order: Array[String]`.
- **Reasons:** `unknown_job`, `duplicate_job`, `missing_job`.
- **Effect (E2a):** TownSim's workers refill the job slots in this order at once.
```gdscript
Game.state.cmd_set_job_priority(["haul", "build", "pit", "stall", "mill", "forge", "tend"])
# -> {ok: true, reason: "", order: ["haul", "build", "pit", "stall", "mill", "forge", "tend"]}
```

**`cmd_set_staff_cap(lot_id: String, cap: int)` · E1/E2** (MECHANICS §4.5)
- **Args:** `cap >= 0`, or `-1` for no cap.
- **Extras:** `cap: int`.
- **Reasons:** `unknown_lot`, `empty_lot`, `no_jobs` (the building has no slots), `bad_cap`
  (`< -1`).
- A cap above the building's slots is accepted. The effective cap is `min(cap, slots)`.
- **Effect (E2a):** TownSim's staffing honours it at once. A new game clears every cap.
```gdscript
Game.state.cmd_set_staff_cap("lot-03", 1)  # -> {ok: true, reason: "", cap: 1}
```

**`cmd_set_stance(stance_id: String, on: bool)` · E1/E3**
- **Extras:** `slots: int`, `used: int`.
- **Reasons:** `unknown_stance`, `no_slot` (turning one on with every slot used; turning one off
  never fails).
- **Effect:** if the slot count later drops (Relish leaves home), the most recently enabled stances
  are `suspended`, not switched off. They resume when a slot returns.
```gdscript
Game.state.cmd_set_stance("harvest", true)  # -> {ok: true, reason: "", slots: 3, used: 1}
```

**`cmd_raise_big_undead(husk_uid: String, remnant_uids: Array, name: String)` · E2** (needs the
town unit's SlabLogic)
- **Extras:** `big_undead: Dictionary`, shaped like a `view_big_undead` entry (§5.12).
- **Reasons:** `not_home` (Relish isn't `home`), `unknown_husk`, `unknown_remnant`,
  `duplicate_remnant`, `invalid_recipe` (SlabLogic rejects the combination), `at_cap`
  (`big_undead.cap`), `bad_name` (empty or over 24 characters after `strip_edges`).
- **Effect:** consumes the husk and the remnants, computes the stats with SlabLogic, mints `u<n>`
  and places it in the crypt.
```gdscript
Game.state.cmd_raise_big_undead("h1", ["r2", "r3"], "Old Gristle")
# -> {ok: true, reason: "", big_undead: {uid: "u4", name: "Old Gristle", kind: "hulk", role: "brute",
#     stats: {power: 6.0, beef: 9.0, wits: 2.0, presence: 3.0, speed: 2.5}, place: "crypt", front: ""}}
```

**`cmd_rename_big_undead(uid: String, name: String)` · E1**
- **Extras:** `name: String`.
- **Reasons:** `unknown_uid`, `bad_name`.
```gdscript
Game.state.cmd_rename_big_undead("u4", "Gristle the Patient")  # -> {ok: true, reason: "", name: "Gristle the Patient"}
```

**`cmd_place_big_undead(uid: String, place: String)` · E1/E2**
- **Args:** `place` is one of:
  - `"town:<lot_id>"`: foreman;
  - `"fort:<fort_id>"`: siege, which adds kill power and blocks tithe;
  - `"crypt"`.
- **Extras:** `place: String`.
- **Reasons:**
  - `unknown_uid`;
  - `busy` (the uid is in an open run's party);
  - `bad_place`, `unknown_lot`, `empty_lot`;
  - `foreman_taken` (one foreman per lot);
  - `unknown_fort`.
- **Effect:** removes it from the party, if it was in it. The place is recorded at E1; foreman and
  siege effects are E2.
```gdscript
Game.state.cmd_place_big_undead("u4", "town:lot-04")  # -> {ok: true, reason: "", place: "town:lot-04"}
```

**`cmd_craft(item_id: String)` · E3**
- **Args:** one of `CRAFT_IDS`.
- **Extras:** `count: int` (the new stock: simulacra ready, or phylactery charges).
- **Reasons:** `unknown_item`, `needs_building` (no Ossuary Tower), `no_essence`, `no_relics`.
- **Effect:** instant. A simulacrum costs essence and a relic; a phylactery charge costs essence
  (amounts in config).
```gdscript
Game.state.cmd_craft("phylactery_charge")  # -> {ok: true, reason: "", count: 1}
```

**`cmd_deploy_simulacrum(fort_id: String)` · E3**
- **Extras:** `charges: float` (the planted simulacrum's charges, in mass), `ready_left: int`.
- **Reasons:** `unknown_fort`, `none_ready`.
- **Effect:** it redirects at that fort at `simulacrum.rate` until its charges run out (MECHANICS
  §3.6).
```gdscript
Game.state.cmd_deploy_simulacrum("vespers")  # -> {ok: true, reason: "", charges: 300.0, ready_left: 0}
```

**`cmd_staff_vat(slot: int, on: bool)` · E1/E3**
- **Args:** `slot` is 0..`vat_slots - 1`.
- **Extras:** `staffed: bool`.
- **Reasons:** `unknown_slot`.
- A clone grows only while its vat is staffed.
```gdscript
Game.state.cmd_staff_vat(0, true)  # -> {ok: true, reason: "", staffed: true}
```

### 4.4 Party and fronts
**`cmd_set_party(uids: Array)` · E1**
- **Args:** big-undead uids, in party order.
- **Extras:** `party: Array[String]`.
- **Reasons:** `busy`, `unknown_uid`, `duplicate_uid`.
- **Effect:** the listed uids move into the party from wherever they were. Former members not
  listed return to the crypt. The dungeon party is these big undead plus the fort's garrison units
  (§7.1).
```gdscript
Game.state.cmd_set_party(["u4", "u7"])  # -> {ok: true, reason: "", party: ["u4", "u7"]}
```

**`cmd_assign_front(uid: String, front_id: String)` · E1/E3**
- **Args:** `front_id` is one of `FRONT_IDS`, or `""` to unassign.
- **Reasons:** `busy`, `unknown_uid`, `not_in_party`, `unknown_front`.
```gdscript
Game.state.cmd_assign_front("u4", "carvers")  # -> {ok: true, reason: ""}
```

### 4.5 Runs (dungeon and boss)
Only one run is open at a time.

**`run_id`:**
- A monotonically increasing `int`, starting at 1.
- It is never reused within a session, and `next_run_id` is saved.

**`seed_rev`:**
- The state `rev` at the moment the seed was issued, recorded on the run.
- Results must echo both values.

**`cmd_begin_dungeon(fort_id: String)` · E1**
- **Extras:** `seed: Dictionary` (§7.1), `run_id: int`, `seed_rev: int`. On failure they are `{}`,
  `-1` and `-1`.
- **Reasons:** `unknown_fort`, `busy`, `dead`, `not_at_fort` (Relish isn't `at_fort` at `fort_id`;
  she must arrive first).
- **Effect:**
  - opens the run and sets Relish to `in_dungeon`;
  - sets `time_scale = 1` and `paused = false`;
  - `view_dungeon_seed(fort_id)` now returns the same seed.
```gdscript
Game.state.cmd_begin_dungeon("old-sluice")
# -> {ok: true, reason: "", run_id: 1, seed_rev: 512, seed: {v: 2, kind: "raid", run_id: 1, ...}}  (§7.1)
Game.state.cmd_begin_dungeon("ashgate")  # Relish at Old Sluice
# -> {ok: false, reason: "not_at_fort", run_id: -1, seed_rev: -1, seed: {}}
```

**`cmd_begin_boss()` · E1** (fronts E3)
- **Extras:** `seed: Dictionary` (§7.2), `run_id: int`, `seed_rev: int`.
- **Reasons:** `busy`, `dead`, `not_at_vei` (she must stand at Vei's node, state `at_vei`).
- **Effect:** opens the run, sets Relish to `in_boss`, and forces `time_scale = 1` and
  `paused = false`.
```gdscript
Game.state.cmd_begin_boss()  # -> {ok: true, reason: "", run_id: 9, seed_rev: 21950, seed: {v: 2, kind: "boss", ...}}
```

**`cmd_abort_dungeon()` · E1**
- **Extras:** `run_id: int` (the run forfeited).
- **Reasons:** `no_run`.
- **Effect:** forfeits the open run, dungeon or boss.
  - There is no writeback, no loot and no flip, and the party is intact.
  - Relish goes back to `at_fort` (or `at_vei`), and the run is closed, so a later result for it is
    `wrong_run`.
```gdscript
Game.state.cmd_abort_dungeon()  # -> {ok: true, reason: "", run_id: 1}
```

**`apply_result(kind: String, result: Dictionary)` · E1** (flip hold E2; backups E3)
- **Args:** `kind` is `"raid"` or `"boss"`; `result` is v2 (§8).
- **Extras:**
  - `errors: Array[String]`: the `Results.validate` output when the reason is `invalid`;
  - `minted: Array[String]`: the uids minted for looted items.
- **Reasons:** checked in the order below. A refusal changes nothing. This list is the
  **GameState layer**; `Results.validate`'s own codes are listed in §8.4.

  | reason | when |
  |---|---|
  | `unknown_kind` | `kind` is not `raid` or `boss` |
  | `unknown_v` | `result.v != 2` (convert v1 with `Results.from_v1` first) |
  | `invalid` | `Results.validate(kind, result)` is non-empty (see `errors`) |
  | `duplicate_run` | `run_id` was already applied. Idempotent: a repeat changes nothing. |
  | `wrong_run` | no run is open, or `run_id` isn't the open run (including a forfeited one) |
  | `wrong_kind` | the open run is the other kind |
  | `stale_seed` | `result.seed_rev` != the `seed_rev` recorded on the open run. It is **not** compared with the current `rev`, which keeps moving during the run. |
  | `wrong_fort` | raid only: `fort_id` != the open run's fort, which is where Relish is |
  | `bad_revives` | raid only: `revived_in_place` > `min(seed.phylactery_charges, seed.phylactery_max_per_dungeon)` |
  | `bad_party` | a `party_lost` uid wasn't in the seed's `party` |
  | `bad_backups` | boss only: `backups_spent` exceeds the seed's `phylactery_charges` or `clones_ready` |
- **Effect:**
  - applies the writeback (§8.3);
  - closes the run and records `run_id` as applied;
  - bumps `rev`;
  - emits `loot_banked`, plus `fort_flipped` or `vei_result`, plus `relish_died` when it applies.
- **E1 notes:**
  - ints are read with `int()`, so integral floats work, and the caller's dictionary is never changed;
  - the last 32 applied run ids are kept in `applied_runs` (for `duplicate_run`; saved at T1.5);
  - `loot_banked` reports what was actually banked: relics and essence after their caps, and only
    the blueprints that were new;
  - looted husks are minted with rarity `common` (the result carries a kind only);
  - the pre-E1 `apply_raid_result` / `apply_boss_result` are gone (T1.6).
```gdscript
Game.state.apply_result("raid", r)  # -> {ok: true, reason: "", errors: [], minted: ["h12", "r13"]}
Game.state.apply_result("raid", r)  # again -> {ok: false, reason: "duplicate_run", errors: [], minted: []}
```

### 4.6 Debug (only when `debug_enabled`; every reason list starts with `not_debug`)
Keys are generic, so the shape survives model changes. **Unknown keys are refused** (`unknown_key`)
and the whole call changes nothing. New keys are additive.

**`cmd_debug_grant(amounts: Dictionary)` · E1**
- **Args:** `{key: number}` with keys from `DEBUG_GRANT_KEYS`:
  - `gold`, `bone`, `bodies`, `relics`, `essence`, `workers`, `living`, `backlog`;
  - `husks`, `remnants`, `big_undead`: an int count ≥ 0, minted with seeded random kinds, aspects
    and stats; big undead go to the crypt.

  Negative values remove; results are clamped to `[0, cap]`.
- **Extras:**
  - `key: String`: the offending key, `""` on success;
  - `applied: Dictionary`: the actual deltas after clamping, plus `minted: Array[String]` for items.
    `applied.minted` is always present (`[]` when nothing was minted).
- **Reasons:** `not_debug`, `unknown_key`, `bad_value`.
- From E2a `gold`, `bone`, `bodies`, `workers` and `living` write TownSim's stocks (`workers` is a
  float and the job slots refill at once); `bodies` and `living` are capped at `body_cap` and
  `living_cap`, but a grant never pulls an over-cap stock down. `backlog` → `vei.undead_queue`.
```gdscript
Game.state.cmd_debug_grant({"gold": 500, "bone": 200, "husks": 1})
# -> {ok: true, reason: "", key: "", applied: {gold: 500.0, bone: 200.0, husks: 1, minted: ["h14"]}}
Game.state.cmd_debug_grant({"materials": 5})  # -> {ok: false, reason: "unknown_key", key: "materials", applied: {}}
```

**`cmd_debug_set_state(patch: Dictionary)` · E1**
- **Args:** keys from `DEBUG_STATE_KEYS`:
  - `time_scale: float` (0 < x ≤ 100), `paused: bool`;
  - `relish_at: String` (a node id: puts her there, alive and standing);
  - `valve: {work, war, flood}` (target and current, with no slew);
  - `forge_level: int` (≥ 0; TownSim's forge level, its progress reset to 0), `won: bool`;
  - `forts: {fort_id: {living?, undead?, dead?}}` (masses ≥ 0, clamped to the cap).
- **Extras:** `key: String`.
- **Reasons:** `not_debug`, `unknown_key`, `bad_value`, `busy` (`relish_at` while a run is open).
- The whole patch is validated before anything applies.
```gdscript
Game.state.cmd_debug_set_state({"time_scale": 60.0})                       # -> {ok: true, reason: "", key: ""}
Game.state.cmd_debug_set_state({"forts": {"ashgate": {"living": 0.0}}})   # -> {ok: true, reason: "", key: ""}
```

**`cmd_debug_load_fixture(name: String)` · E1**
- **Args:** one of `FIXTURES`. It loads `res://tests/fixtures/<name>.json` through `from_dict`.
- **Reasons:** `not_debug`, `busy`, `unknown_fixture`, `bad_fixture`.
```gdscript
Game.state.cmd_debug_load_fixture("pre_vei")  # -> {ok: true, reason: ""}
```

**`cmd_debug_skip_time(seconds: float)` · E1**
- **Args:** `0 < seconds <= 86400`.
- **Extras:** `substeps: int`.
- **Reasons:** `not_debug`, `bad_value`.
- **Effect:** steps the sim uncapped, **ignoring `paused`**. Events queue normally.
```gdscript
Game.state.cmd_debug_skip_time(600.0)  # -> {ok: true, reason: "", substeps: 1200}
```

### 4.7 `ledger() -> Dictionary` · E2 (for tests)
- Returns `{sources: Dictionary, sinks: Dictionary, held: Dictionary}`: `String → float` mass
  totals since the new game.
- `sources`: `mint`, `debug`.
- `sinks`: `cleared` (`k_clear`), `rot_loss`, `burned`, `milled`, `vei_fight`, `dungeon`,
  `pool_overflow` (always 0).
- `held`: every pool of mass.
- Invariant: `Σheld + Σsinks == Σsources` within 1e-6 relative.

## 5. Views

Every view returns a deep copy with `rev: int` first (§1.3). A view of an unknown id returns `{}`.
Types are exact. "mass" means a float in mass units.

### 5.1 `view_hud()` · E2
Every field is live from E2a:
- `sign`, `drain_s` and `odds` are the sustained readout (§5.14);
- `split` is the last substep's mass/s, after the slew (WAR includes TownSim's muster), and the
  `mint` entry's `rate` is that substep's mint (MECHANICS §3.2);
- the `workers`, `bodies`, `gold`, `bone` and `living` entries are TownSim's: the same stocks and
  caps `view_town` shows, and the net rates of `view_rates` (bodies count the haul trip-averaged);
- `workers_steady` is TownSim's last inflow × the lifetime now, as `view_town.workers.steady`.

| key | type | meaning |
|---|---|---|
| `t` | float | sim seconds since the new game |
| `time_scale` | float | |
| `paused` | bool | |
| `rates` | Array[Dictionary] | one per `HUD_RATE_IDS`, in order: `{id: String, rate: float, stock: float, cap: float, unit: String}`. `rate` is the signed net per sim-second; for `mint` it is production (≥ 0). `stock` is `-1.0` for mint; `cap` is `-1.0` when uncapped. |
| `split` | Dictionary | `{work, war, flood}`: mass/s now, after the slew; `war` includes muster (`muster_mass / dt`) |
| `valve`, `valve_target` | Dictionary | `{work, war, flood}` fractions summing to 1 |
| `workers_steady` | float | workers: `(work / worker.mass) · lifetime` |
| `relics`, `relics_cap`, `essence`, `essence_cap` | int | |
| `sign` | int | sustained-differential sign: `1` = ▲ (backlog growing), `-1` = ▼, `0` = holding |
| `drain_s` | float | `backlog / -EMA` when the EMA < 0, else `-1.0` (holding) |
| `odds` | float | `backlog / (backlog + K)`, 0..1 |
| `won` | bool | |
```gdscript
{rev: 3, t: 1.0, time_scale: 1.0, paused: false,
 rates: [{id: "mint", rate: 12.8, stock: -1.0, cap: -1.0, unit: "mass/s"},
         {id: "workers", rate: 0.103, stock: 12.0, cap: -1.0, unit: "workers/s"},
         {id: "bodies", rate: -0.35, stock: 40.0, cap: 200.0, unit: "mass/s"},
         {id: "gold", rate: 0.22, stock: 80.0, cap: -1.0, unit: "gold/s"},
         {id: "bone", rate: 0.0, stock: 30.0, cap: -1.0, unit: "bone/s"},
         {id: "living", rate: 0.012, stock: 10.0, cap: 16.0, unit: "living/s"}],
 split: {work: 5.12, war: 5.76, flood: 1.92},
 valve: {work: 0.4, war: 0.45, flood: 0.15}, valve_target: {work: 0.4, war: 0.45, flood: 0.15},
 workers_steady: 61.4, relics: 0, relics_cap: 12, essence: 0, essence_cap: 60,
 sign: 0, drain_s: -1.0, odds: 0.0, won: false}
```

### 5.2 `view_rates()` · E2
`{rev: int, rates: {<id>: {in: float, out: float, net: float, unit: String}}}`, with one key for
each of `GameState.RATE_IDS`.
- Rates are the last substep's flows divided by `sim.substep_s`.
- Lumps are not rates: build costs, dungeon writebacks and debug grants.
- Haul shows as its trip-averaged rate: the last landed trip's load over its round trip, while a
  convoy is out (0 while none is).
- **E2a:** `mint`, `work`, `war` and `flood` are the last substep's (session-only, §9.1); `workers`,
  `bodies`, `gold`, `bone` and `living` are TownSim's last step (saved with it). `corpses` and
  `backlog` are still 0.

| id | unit | in | out | net |
|---|---|---|---|---|
| `mint` | mass/s | pits' production | sent through the valve | 0 (a pass-through flow) |
| `work`, `war`, `flood` | mass/s | `mint · valve` share (WAR also gets muster × `worker.mass`) | delivered (= in) | 0 |
| `workers` | workers/s | `work / worker.mass` | rot + muster | in − out |
| `bodies` | mass/s | haul + rot return | pit burn + mill | in − out |
| `gold` | gold/s | trade | upkeep | in − out |
| `bone` | bone/s | mill | upkeep | in − out |
| `living` | living/s | migrants | departures | in − out |
| `corpses` | mass/s | Σ forts: your kills + redirected garrison kills | haul + Relish's raise + shipping to Vei + `k_clear` | in − out |
| `backlog` | mass/s | FLOOD + fort drain + Relish's raises | Vei's digestion | the raw `diff` |
```gdscript
{rev: 3, rates: {"mint": {in: 12.8, out: 12.8, net: 0.0, unit: "mass/s"},
                 "workers": {in: 0.128, out: 0.025, net: 0.103, unit: "workers/s"},
                 "gold": {in: 0.3, out: 0.08, net: 0.22, unit: "gold/s"}, ...one entry per RATE_IDS}}
```

### 5.3 `view_lanes()` · E2
`{rev: int, lanes: Array[Dictionary]}`. Each lane has these keys:

| key | type | meaning |
|---|---|---|
| `id` | String | `"<kind>:<from>:<to>"`, stable, for keying animations |
| `from`, `to` | String | node ids |
| `kind` | String | one of `LANE_KINDS` |
| `rate` | float | mass/s along the lane |
| `bias` | float | dispatch-weight multiplier: 1.0 neutral, `relish.tide_bias` under her tide, `tithe.surge_mult` under a wave |
| `why` | String | short change callout, `""` when none. Set for 10 sim-seconds after the lane's rate changes for a named cause. E2 values: `"Relish here"`, `"Relish left"`, `"tithe wave"`, `"held"`, `"retaken"`, `"valve"`, `"staging"`, `"simulacrum"`. |

| kind | from → to | rate |
|---|---|---|
| `war` | covington → fort (a held fort as staging) | WAR dispatch |
| `flood` | covington → vei; fort → vei | the valve's FLOOD; fort undead draining into Vei's queue |
| `work` | covington → covington | WORK (drawn at Covington) |
| `dead` | fort → vei | garrison kills shipped to Vei |
| `living` | vei → fort | Vei's living shipments, tithe surges included |
| `haul` | fort → covington | convoy corpses, trip-averaged |
| `redirect` | fort → fort | corpses kept and raised there by Relish or a simulacrum |

**E2a notes** (additive):
- **Zero-rate lanes are omitted**, unless their `why` callout is live: a lane that just dropped to
  0 (`"Relish left"`, `"held"`, `"retaken"`) stays at 0 until its callout ends. Order: kinds in
  `LANE_KINDS` order, forts in world order within a kind.
- Every kind is live: `war` (covington → fort, staging at held forts included), `flood`, `dead`,
  `living` and `redirect`, and from T2.3b `work` (covington → covington at the valve's WORK) and
  `haul` (from the fort TownSim's convoy works to covington, at the trip-averaged rate of §5.2 while
  the convoy is out).
- WAR that falls through to Vei (no fort has living and none is held) shows as a `war` lane
  **covington → vei** (`war:covington:vei`). A `war` lane's `to` may therefore be `"vei"`.
- `flood` fort → vei is the fort's undead draining into her queue; `dead` fort → vei is garrison
  kills shipped; `living` vei → fort includes tithe surges; `redirect` carries the mass/s raised
  there into undead (Relish and simulacra together).
- `bias`: `relish.tide_bias` on the war lane to her tide fort; on the living lane to a wave's
  target, `tithe.surge_mult` × the counters (½ while Relish stands there, × (1 − siege share)).
- `why` causes: `"valve"` (a new valve target: every war lane and flood covington → vei);
  `"Relish here"` / `"Relish left"` (her tide fort's war lane; her redirect fort's redirect and dead
  lanes); `"held"` (living lane) and `"staging"` (war lane) when a fort is flipped; `"retaken"`
  (both) when a hold ends; `"tithe wave"` (living lane) when a wave starts; `"simulacrum"` (redirect
  and dead lanes) when one starts or stops working at a fort. The newest cause wins. A command's
  callout starts at its `t`; the others at the substep that sees the change. Callouts are
  session-only.
```gdscript
{rev: 3, lanes: [
  {id: "war:covington:old-sluice", from: "covington", to: "old-sluice", kind: "war", rate: 1.21, bias: 3.0, why: "Relish here"},
  {id: "flood:covington:vei", from: "covington", to: "vei", kind: "flood", rate: 1.92, bias: 1.0, why: ""}]}
```

### 5.4 `view_realm()` · E1
The masses and positions are live at E1. The held, tithe, threat and warden fields follow `view_fort`.

| key | type | meaning |
|---|---|---|
| `size` | Array | `[2048.0, 1440.0]` |
| `covington` | Dictionary | `{pos: [x, y]}` |
| `vei` | Dictionary | `{pos: [x, y], radius: float, living_pool: float, pool_cap: float, backlog: float}` (mass) |
| `forts` | Array[Dictionary] | every fort in `world.json` order, in the `view_fort` shape without `rev` |
| `held_count` | int | forts held now |
| `digest_q` | float | `q` (MECHANICS §2.2) |
```gdscript
{rev: 3, size: [2048.0, 1440.0], covington: {pos: [1780.0, 1270.0]},
 vei: {pos: [1024.0, 130.0], radius: 150.0, living_pool: 412.0, pool_cap: 600.0, backlog: 0.0},
 forts: [{id: "ashgate", ...}, ...12], held_count: 0, digest_q: 1.2}
```

### 5.5 `view_fort(id: String)` · E1
The masses, positions, `relish_here` and `can_descend` are live at E1. Held, flip, tithe and siege
are E2. The warden, threat and loot hint are E2 (E1 stubs: `bellringer`, `risk: "low"`).

| key | type | meaning |
|---|---|---|
| `id`, `name` | String | |
| `tier` | int | 1..4 |
| `cap` | float | mass |
| `pos` | Array | `[x, y]` |
| `living`, `undead`, `dead`, `space` | float | mass; `space = max(0, cap − living − undead − dead)` |
| `war_in`, `ship_in` | float | mass/s: WAR arriving (staging included); Vei's living arriving (tithe surges included) |
| `held` | bool | flipped and still held |
| `held_s_left` | float | 0 when not held |
| `flipped_count` | int | times flipped |
| `first_clear` | bool | never cleared, so its chest holds a guaranteed blueprint |
| `first_dungeon` | bool | carries the first-dungeon guarantee (Old Sluice at start) |
| `clears_since_retaken` | int | |
| `yield_mult` | float | `loot.reclear_decay ^ clears_since_retaken` |
| `warden` | Dictionary | `{archetype: String, tells: Array[String]}`: one tell, or every tell with a Watchtower |
| `loot_hint` | String | display text |
| `threat` | Dictionary | `{party_strength: float, garrison_strength: float, risk: "low"\|"risky"\|"deadly", risk_pct: float}`; `risk_pct` is `-1.0` without a Watchtower |
| `relish_here`, `tide`, `redirect` | bool | she stands here; her tide applies (also in its dungeon); her redirect applies (not in its dungeon) |
| `simulacrum_charges` | float | mass left across simulacra planted here; 0 when none |
| `siege` | Array[String] | big-undead uids placed here |
| `tithe` | Dictionary | `{targeted: bool, eta_s: float, wave_active: bool}`; `eta_s` is `-1.0` when not targeted. Targeted while a warning names the fort (`eta_s`: seconds to its wave) or its wave runs (`eta_s` 0.0, `wave_active`). |
| `can_descend` | bool | `cmd_begin_dungeon(id)` would succeed now |
| `reason` | String | the reason it would return (`""`, `busy`, `dead`, `not_at_fort`) |
```gdscript
{rev: 3, id: "old-sluice", name: "Old Sluice", tier: 1, cap: 80.0, pos: [1420.0, 1305.0],
 living: 61.2, undead: 6.4, dead: 3.1, space: 9.3, war_in: 0.48, ship_in: 0.3,
 held: false, held_s_left: 0.0, flipped_count: 0, first_clear: true, first_dungeon: true,
 clears_since_retaken: 0, yield_mult: 1.0,
 warden: {archetype: "bellringer", tells: ["rings slam on the beat"]}, loot_hint: "a husk and a blueprint",
 threat: {party_strength: 8.0, garrison_strength: 6.1, risk: "low", risk_pct: -1.0},
 relish_here: false, tide: false, redirect: false, simulacrum_charges: 0.0, siege: [],
 tithe: {targeted: false, eta_s: -1.0, wave_active: false}, can_descend: false, reason: "not_at_fort"}
```

### 5.6 `view_field()` · E1
**Exception to the copy rule:** `field` is the live `InfluenceField`, so the ground unit's renderer
doesn't copy a 128 × 90 grid every frame. Read it only.
- The object is replaced on new game or load, so call `view_field()` again after a `rev` jump, or
  each refresh.
- Its method signatures (`inject`, `tick`, `dominance_at`, `advance(budget_cells: int)`, `flush()`)
  are frozen at E1, when the ground unit takes ownership.
- `advance(budget_cells)` is the time-slice hook: the ground unit fills it in to slice field work
  between ticks. The budget is **work units per call (field cells processed)**, not time; `0` means
  no slicing (all field work happens inside `tick()`). At **every** budget the field publishes
  `field.lag_ticks` ticks late (realm.json, ground-owned; default 2 = one substep, since ticks come in
  pairs per substep) — the approved lag, so results are the same at every budget. `flush()` finishes
  and publishes any in-flight slice. `GameState` calls `advance(field.slice_budget_cells)` once per `tick(dt)` call
  after the substep loop (§3 step 9), so slicing is a deterministic function of the call sequence,
  and `flush()` once after the new-game pre-warm.

| key | type | meaning |
|---|---|---|
| `field` | InfluenceField | live, read-only |
| `world_size` | Array | `[2048.0, 1440.0]` |
| `tick_hz` | float | `field.tick_hz` |
```gdscript
{rev: 3, field: <InfluenceField>, world_size: [2048.0, 1440.0], tick_hz: 5.0}
```

### 5.7 `view_villages()` · E1
`{rev: int, villages: Array[Dictionary]}`, one per `world.json` town. Each entry has these keys:

| key | type | meaning |
|---|---|---|
| `id`, `name` | String | |
| `pos` | Array | `[x, y]` |
| `owner` | String | `"player"` (necrosis holds it; it sends migrants), `"vei"`, or `"none"` |
| `dominance` | float | signed field value; above `field.town_threshold` means `player` |
| `migrants` | float | living/s this village adds to Covington |
```gdscript
{rev: 3, villages: [{id: "bellwether", name: "Bellwether", pos: [1680.0, 1330.0], owner: "player", dominance: 0.41, migrants: 0.012}, ...]}
```

### 5.8 `view_relish()` · E1
The dead fields and the backups are E3. At E1 a death respawns her at once.

| key | type | meaning |
|---|---|---|
| `state` | String | one of `RELISH_STATES` |
| `at` | String | the node she stands at; while travelling or dead, the node she last stood at |
| `target` | String | the destination while `travelling`, else `""` |
| `pos` | Array | `[x, y]` |
| `heading` | float | radians; she keeps her last heading when she stops (0 at a new game) |
| `speed` | float | px/s; 0 unless travelling |
| `eta_s` | float | `-1.0` unless travelling |
| `dead_s_left` | float | 0 unless dead |
| `respawn_with_clone` | bool | while dead: wakes from a clone (`true`) or reforms after being unmade (`false`) |
| `phylactery_charges`, `clones_ready` | int | |
| `can_descend` | bool | she could begin the dungeon of the fort she stands at, now |
| `reason` | String | `""`, else the first of `busy` > `dead` > `not_at_fort` (`not_at_fort` whenever she isn't standing at a fort: home, `at_vei`, travelling) |
| `run_id` | int | the open run, or `-1` |
| `run_kind` | String | `""`, `"raid"` or `"boss"` |
| `effects` | Dictionary | `{tide_fort: String, redirect_fort: String, home: bool}`: what her position does now (E2) |
```gdscript
{rev: 9, state: "travelling", at: "covington", target: "old-sluice", pos: [1600.0, 1287.5],
 heading: 3.045, speed: 220.0, eta_s: 0.82, dead_s_left: 0.0, respawn_with_clone: false,
 phylactery_charges: 0, clones_ready: 0, can_descend: false, reason: "not_at_fort",
 run_id: -1, run_kind: "", effects: {tide_fort: "", redirect_fort: "", home: false}}
```

### 5.9 `view_town()` · E2
From E2a (T2.3b) it is TownSim's town (MECHANICS §4): buildings with their real state, progress,
slots, staffing and output; the ladder and the jobs it staffs; the workforce and its flows; the
living, morale and its factors; the stocks and caps; trade; the convoy. The stocks are the ones
`view_hud` and `view_catalog`'s `no_gold`/`no_bone` read, so fixtures and debug grants show up in
every view. The tier is GameState's (stored; tier-ups are T2.4), lots come from `town.json`, and
`ladder_effective` is the ladder until stances (E3). Flows are TownSim's last step: 0 at a new game
until the first substep.
- `workers.lifetime_s` is the lifetime now (`worker.lifetime_s · (1 + Σ lifetime_bonus)`, ÷
  `relish.home_rot_mult` while Relish is home: 685.7 at a new game); `workers.steady` is the last
  inflow × that lifetime.
- `buildings[].output` (per second, at the current staffing; `{}` while constructing or unpaid, and
  for a building with none): a pit `{mint: P_per_pit · pits, burn: pit.burn_per_s · pits · its
  staffed share}`; stalls `{gold}` (their share of the town's sales × price); millers `{bone}`;
  haulers `{bodies}` (their share of the trip-averaged haul); smiths `{forge}` (work/s while a forge
  level is left); an inn `{living}` (its migrants/s).

| key | type | meaning |
|---|---|---|
| `tier` | String | one of `TIERS` |
| `next_tier` | Dictionary | `{tier: String, have: int, need: int, missing: Array[String]}`. `have`/`need` count buildings; `missing` lists required building ids not yet built. `tier` is `""` at City. |
| `lots` | Array[Dictionary] | `{id: String, size: int, unlocked: bool, building_id: String}` (`""` when empty) |
| `buildings` | Array[Dictionary] | one per built or building lot (below) |
| `ladder` | Array[String] | the player's job order |
| `ladder_effective` | Array[String] | the order after stances |
| `jobs` | Array[Dictionary] | in `ladder_effective` order: `{id: String, slots: int, staffed: float}` |
| `workers` | Dictionary | `{total: float, idle: float, in: float, rot: float, muster: float, steady: float, lifetime_s: float}`: workers, workers/s, sim seconds |
| `living`, `living_cap` | float | people |
| `migrants`, `departures` | float | living/s |
| `morale` | Dictionary | `{value: float, target: float, factors: Array[{id: String, delta: float}]}`. Factor ids: `base`, `amenity:<building_id>`, `dread`, `shock`. |
| `gold`, `bone`, `bodies`, `bodies_cap` | float | stocks |
| `trade_rate` | float | stall sales per second (the town draws trade arcs from it) |
| `haul` | Dictionary | `{target: String ("auto" or a fort id), current: String, convoys: Array[{from: String, to: String, phase: "out"\|"back", t: float, load: float}]}`. `t` is trip progress 0..1; `load` is mass. |
| `relish_home` | bool | the slab works |

Each `buildings` entry:

| key | type | meaning |
|---|---|---|
| `lot_id`, `building_id` | String | |
| `level` | int | 0 while the first build is under way |
| `state` | String | `"constructing"` (building or upgrading), `"active"`, `"unpaid"` (idled by unpaid upkeep), or `"idle"` (no staff, or a stance idles it) |
| `progress` | float | 0..1 while constructing, else 1.0 |
| `slots` | int | |
| `staffed` | float | |
| `staff_cap` | int | `-1` = none |
| `foreman` | String | big-undead uid, or `""` |
| `output` | Dictionary | `String → float` per second, e.g. `{gold: 0.3}`, `{mint: 6.0, burn: 0.6}` |
| `upkeep` | Dictionary | `{gold: float, bone: float}` per second |
```gdscript
{rev: 3, tier: "hamlet", next_tier: {tier: "village", have: 4, need: 6, missing: ["house"]},
 lots: [{id: "lot-01", size: 2, unlocked: true, building_id: "crypt"}, {id: "lot-05", size: 1, unlocked: true, building_id: ""}, ...24],
 buildings: [{lot_id: "lot-04", building_id: "market", level: 1, state: "active", progress: 1.0, slots: 2,
              staffed: 2.0, staff_cap: -1, foreman: "", output: {gold: 0.3}, upkeep: {gold: 0.03, bone: 0.0}}, ...],
 ladder: ["build", "haul", "pit", "stall", "mill", "forge", "tend"],
 ladder_effective: ["build", "haul", "pit", "stall", "mill", "forge", "tend"],
 jobs: [{id: "haul", slots: 3, staffed: 3.0}, {id: "pit", slots: 2, staffed: 2.0}, {id: "stall", slots: 2, staffed: 2.0}, ...],
 workers: {total: 12.0, idle: 5.0, in: 0.128, rot: 0.025, muster: 0.0, steady: 61.4, lifetime_s: 480.0},
 living: 10.0, living_cap: 16.0, migrants: 0.012, departures: 0.0,
 morale: {value: 0.6, target: 0.6, factors: [{id: "base", delta: 0.6}]},
 gold: 80.0, bone: 30.0, bodies: 40.0, bodies_cap: 200.0, trade_rate: 0.3,
 haul: {target: "auto", current: "old-sluice", convoys: [{from: "old-sluice", to: "covington", phase: "back", t: 0.4, load: 14.0}]},
 relish_home: true}
```

### 5.10 `view_catalog()` · E2 (crafts E3)
From E2a `no_gold` and `no_bone` read TownSim's stocks, `count` counts the buildings whose first build
has finished, and a lot under construction is not free. The other gates are unchanged until T2.4.

| key | type | meaning |
|---|---|---|
| `buildings` | Array[Dictionary] | one per building id (below) |
| `crafts` | Array[Dictionary] | per `CRAFT_IDS`: `{item_id: String, cost: {essence: int, relics: int}, can_craft: bool, reason: String}` (`cmd_craft`'s reasons) |
| `blueprints` | Array[Dictionary] | `{id: String, owned: bool}` |

Each `buildings` entry:

| key | type | meaning |
|---|---|---|
| `building_id` | String | |
| `cost` | Dictionary | `{gold: float, bone: float, relics: int}` |
| `upkeep` | Dictionary | `{gold: float, bone: float}` per second |
| `build_work` | float | |
| `lot_size`, `max_level`, `count` | int | `count` is the number built |
| `requires` | Dictionary | `{tier: String, blueprint: String, building: String}`, with `""` = none |
| `can_build` | bool | |
| `reason` | String | the first failing reason among `needs_tier`, `needs_blueprint`, `needs_building`, `no_lot` (no free unlocked lot fits), `no_gold`, `no_bone`, `no_relics` |
| `lots` | Array[String] | free unlocked lots it fits |
```gdscript
{rev: 3, buildings: [
  {building_id: "house", cost: {gold: 40.0, bone: 10.0, relics: 0}, upkeep: {gold: 0.01, bone: 0.0}, build_work: 60.0,
   lot_size: 1, max_level: 3, count: 0, requires: {tier: "hamlet", blueprint: "", building: ""},
   can_build: true, reason: "", lots: ["lot-05", "lot-06", "lot-07", "lot-08"]},
  {building_id: "inn", ..., can_build: false, reason: "needs_tier", lots: []}],
 crafts: [{item_id: "simulacrum", cost: {essence: 20, relics: 1}, can_craft: false, reason: "needs_building"}, ...],
 blueprints: [{id: "embalmer", owned: false}, ...]}
```

### 5.11 `view_stances()` · E3 (E1: echoes `cmd_set_stance`)
| key | type | meaning |
|---|---|---|
| `slots`, `used` | int | `stance.base_slots` + Guildhall + 1 while Relish is home |
| `beat_id` | int | the current sim beat, `floor(t / beat_s)` |
| `stances` | Array[Dictionary] | one per `STANCE_IDS` (below) |

Each `stances` entry:

| key | type | meaning |
|---|---|---|
| `id` | String | |
| `on` | bool | the player toggle |
| `suspended` | bool | on, but no slot is free |
| `active` | bool | its condition is firing now |
| `fired_beat_id` | int | the beat it last changed `active`, or `-1` |
| `hold_s_left` | float | the `stance.hold_s` remaining |
| `projected` | Dictionary | `rate_id → float`: the change in each net rate per second if toggled |
```gdscript
{rev: 3, slots: 3, used: 1, beat_id: 117, stances: [
  {id: "harvest", on: true, suspended: false, active: false, fired_beat_id: -1, hold_s_left: 0.0, projected: {bodies: 0.4, gold: -0.05}}, ...5]}
```

### 5.12 `view_inventory()`, `view_big_undead()`, `view_party()` · E1
Loot comes in through `apply_result` and grants at E1. The big-undead raise is E2.

**`view_inventory()`**

| key | type | meaning |
|---|---|---|
| `husks` | Array[Dictionary] | `{uid: String, kind: String}` |
| `remnants` | Array[Dictionary] | `{uid: String, aspect: String (one of STATS), rarity: String (one of RARITIES), magnitude: int}` |
| `blueprints` | Array[String] | owned blueprint ids |
| `relics`, `relics_cap`, `essence`, `essence_cap`, `simulacra_ready`, `phylactery_charges` | int | simulacra and charges are fungible counts, not uids |

**`view_big_undead()`**

| key | type | meaning |
|---|---|---|
| `cap`, `count` | int | `big_undead.cap` (crypt levels) |
| `big_undead` | Array[Dictionary] | entries as below |

Each big-undead entry:

| key | type | meaning |
|---|---|---|
| `uid`, `name` | String | |
| `kind` | String | its husk kind |
| `role` | String | SlabLogic's role name |
| `stats` | Dictionary | `{power, beef, wits, presence, speed}`, all float |
| `place` | String | `"crypt"`, `"town:<lot_id>"`, `"fort:<fort_id>"` or `"party"` |
| `front` | String | its front id, or `""` |

**`view_party()`**

| key | type | meaning |
|---|---|---|
| `party` | Array[Dictionary] | big-undead entries, in party order |
| `fort_id` | String | the fort Relish stands at, or `""` |
| `garrison_units`, `garrison_in_mass`, `starter_units` | int, float, int | what a descent there would take in (§7.1) |
| `strength` | float | the party-strength figure `view_fort.threat` uses |
```gdscript
view_inventory():  {rev: 3, husks: [{uid: "h1", kind: "skeleton"}], remnants: [{uid: "r2", aspect: "beef", rarity: "common", magnitude: 3}],
                    blueprints: ["embalmer"], relics: 2, relics_cap: 12, essence: 14, essence_cap: 60, simulacra_ready: 0, phylactery_charges: 0}
view_big_undead(): {rev: 3, cap: 2, count: 1, big_undead: [{uid: "u4", name: "Old Gristle", kind: "hulk", role: "brute",
                    stats: {power: 6.0, beef: 9.0, wits: 2.0, presence: 3.0, speed: 2.5}, place: "party", front: ""}]}
view_party():      {rev: 3, party: [{uid: "u4", ...}], fort_id: "old-sluice", garrison_units: 0, garrison_in_mass: 0.0, starter_units: 8, strength: 8.0}
```

### 5.13 `view_backups()` · E3
Until E3 `clones_ready` is a plain stock (GameState's, saved in `backups`; the fixtures and tests set
it, no system grows one yet) and each ready clone is a vat slot (`grow` 1.0, `ready`); the
phylactery charges are stored as is. `death` follows the E1-safe rule of §8.3 step 10.
| key | type | meaning |
|---|---|---|
| `phylactery_charges`, `phylactery_max_per_dungeon`, `clones_ready` | int | |
| `vats` | Array[Dictionary] | `{slot: int, staffed: bool, grow: float (0..1), ready: bool}` |
| `death` | Dictionary | what a death in the next run costs right now: `{outcome: "phylactery"\|"clone"\|"unmade", respawn_s: float, loses: Array[String]}`. `loses` ⊆ `party`, `unbanked_loot`, `flip`, `morale` (§8.3, step 10). |
| `dead_s_left` | float | 0 unless dead |
```gdscript
{rev: 3, phylactery_charges: 0, phylactery_max_per_dungeon: 1, clones_ready: 0,
 vats: [{slot: 0, staffed: true, grow: 0.42, ready: false}],
 death: {outcome: "unmade", respawn_s: 600.0, loses: ["unbanked_loot", "morale"]}, dead_s_left: 0.0}
```

### 5.14 `view_vei()` · E1 (EMA sign E2, tithe E2, fronts E3)
At E1, `backlog`, `living_pool`, `odds`, `sign` and `drain_s` come from the legacy readout. From E2a
they are the sustained readout (MECHANICS §3.5): `diff` is what entered her undead queue last
substep less the undead she took, per second (the backlog's net rate without lumps); `diff_ema` its
EMA; `sign` ±1 past ±`readout.sign_eps`. `tithe.target` is the running wave's fort (`eta_s` 0.0,
`wave_s_left`), else the warned fort (`eta_s` to its wave), else `""` and -1.0. `warning` is true
while a warning is pending.

| key | type | meaning |
|---|---|---|
| `backlog`, `living_pool`, `pool_cap` | float | mass |
| `diff` | float | mass/s: the raw differential this substep (0.0 after a load until the first substep) |
| `diff_ema` | float | mass/s: the EMA over `readout.ema_s` |
| `sign`, `drain_s`, `odds` | int, float, float | as in `view_hud` |
| `digest_q` | float | |
| `fronts` | Array[Dictionary] | per `FRONT_IDS`: `{id: String, need: float, have: float, cleared: bool, assigned: Array[String]}` |
| `fronts_required`, `fronts_met` | int | |
| `tithe` | Dictionary | `{target: String, eta_s: float, warning: bool, wave_active: bool, wave_s_left: float}`. `target` is `""` and `eta_s` is `-1.0` before a target is chosen. |
| `can_begin` | bool | `cmd_begin_boss()` would succeed |
| `reason` | String | `""`, `busy`, `dead` or `not_at_vei` |
| `won` | bool | |
```gdscript
{rev: 3, backlog: 18450.0, living_pool: 380.0, pool_cap: 600.0, diff: 9.4, diff_ema: 6.1, sign: 1, drain_s: -1.0,
 odds: 0.61, digest_q: 2.6,
 fronts: [{id: "giants", need: 24.0, have: 26.5, cleared: true, assigned: ["u4"]}, ...4],
 fronts_required: 3, fronts_met: 3,
 tithe: {target: "ashgate", eta_s: 88.0, warning: true, wave_active: false, wave_s_left: 0.0},
 can_begin: true, reason: "", won: false}
```

### 5.15 `view_dungeon_seed(fort_id: String)`, `view_boss_seed()` · E1
These return the open run's seed (§7), identical to what `cmd_begin_*` returned. They return `{}`
when no run of that kind is open at that fort.

## 6. Events

`drain_events() -> Array[Dictionary]`
- Every event has `t: float` (sim seconds, never decreasing) and `type: String`, plus the fields
  below.
- The queue is cleared by new game, load and fixture load.
- Scenes receive events only through `Game.game_event` (§2.1).

| type | fields | ms |
|---|---|---|
| `relish_died` | `outcome: String` (`phylactery`\|`clone`\|`unmade`), `in_place: bool` (she carried on in the run), `at: String` (node), `run_id: int`, `respawn_s: float` (0 when `in_place`) | E1 (until E3: `clone` when a clone is ready, else `unmade`, respawn 0; `phylactery` and timers E3) |
| `relish_respawned` | `with_clone: bool`, `at: String` (`"covington"`) | E1 (immediate at E1) |
| `building_started` | `lot_id: String`, `building_id: String`, `level: int` (target; 1 for a new building), `upgrade: bool` (`level > 1`) | E2 (TownSim's, from the substep after the construction starts) |
| `building_done` | `lot_id`, `building_id`, `level: int` | E2 |
| `building_unpaid` | `lot_id`, `building_id`, `unpaid: bool` (`true` = went idle, `false` = resumed) | E2 |
| `tier_up` | `tier: String`, `from: String` | E2 |
| `fort_flipped` | `fort_id: String`, `run_id: int`, `hold_s: float` | E1 (hold effects E2) |
| `fort_retaken` | `fort_id: String`, `cause: String` (`expired`\|`tithe_wave`) | E2 |
| `tithe_warning` | `wave_id: int`, `fort_id: String`, `eta_s: float`, `surge: float` (living mass/s before counters) | E2 |
| `tithe_wave` | `wave_id: int`, `fort_id: String`, `surge: float` (after counters), `duration_s: float`, `relish_here: bool`, `siege_block: float` (fraction cancelled) | E2 |
| `stance_fired` | `stance_id: String`, `active: bool`, `beat_id: int` | E3 |
| `loot_banked` | `run_id: int`, `fort_id: String`, `relics: int`, `essence: int`, `blueprints: Array[String]`, `minted: Array[String]` | E1 |
| `vei_result` | `run_id: int`, `won: bool`, `fronts_cleared: Array[String]`, `relish_deaths: int`, `backlog_after: float` | E1 |
| `autosaved` | `slot: String`, `saved_at: int` | E1 |
| `save_failed` | `slot: String`, `reason: String` (`cmd_save`'s reason) | E1 |
```gdscript
{t: 4712.5, type: "fort_flipped", fort_id: "old-sluice", run_id: 1, hold_s: 375.0}
{t: 4712.5, type: "loot_banked", run_id: 1, fort_id: "old-sluice", relics: 1, essence: 9, blueprints: ["embalmer"], minted: ["h12", "r13"]}
{t: 5100.0, type: "tithe_warning", wave_id: 2, fort_id: "old-sluice", eta_s: 150.0, surge: 24.0}
{t: 9210.0, type: "relish_died", outcome: "clone", in_place: false, at: "vespers", run_id: 4, respawn_s: 60.0}
{t: 9270.0, type: "relish_respawned", with_clone: true, at: "covington"}
{t: 11002.0, type: "vei_result", run_id: 9, won: true, fronts_cleared: ["giants", "carvers", "raw"], relish_deaths: 1, backlog_after: 18450.0}
{t: 600.0, type: "autosaved", slot: "auto", saved_at: 1794556800}
```

## 7. Seeds

Seeds are issued by `cmd_begin_dungeon` / `cmd_begin_boss`, and re-read through `view_*_seed`. Each
is a deep copy with no `rev`, and is checked by `Results.validate("raid_seed" | "boss_seed", seed)`.
- **`rng_seed`** is a decimal `String` of a 64-bit int. Use it with
  `rng.seed = seed.rng_seed.to_int()`.
- It is derived from the game seed and `run_id`. On a fresh `GameState`, which is what the determinism test uses, a fixture plus a command log reproduces it.

### 7.1 Dungeon seed (`kind: "raid"`)
| key | type | meaning |
|---|---|---|
| `v` | int | 2 |
| `kind` | String | `"raid"` |
| `run_id`, `seed_rev` | int | §4.5 |
| `rng_seed` | String | |
| `fort` | Dictionary | `{id: String, name: String, tier: int, cap: float, first_clear: bool, first_dungeon: bool, clears_since_retaken: int, yield_mult: float}` |
| `living`, `dead`, `undead` | float | the fort's masses at issue |
| `garrison_units` | int | `clampi(int(undead / raid.mass.garrison_mass_div), 0, raid.mass.garrison_max)` |
| `garrison_in_mass` | float | `garrison_units × garrison_mass_div`: the writeback baseline (§8.3). It is recorded, never recomputed. |
| `garrison_mass_div` | float | `raid.mass.garrison_mass_div` (10.0). `Results.from_v1` reads it from the seed, so the adapter needs no config. |
| `starter_units` | int | `opening.starter_party` (8) when `fort.first_dungeon`, else 0. **Massless:** they never write back. |
| `party` | Array[Dictionary] | big undead in party order: `{uid, name, kind, role, stats: {power, beef, wits, presence, speed}}` |
| `digest_q` | float | |
| `phylactery_charges` | int | the stock at issue |
| `phylactery_max_per_dungeon` | int | `phylactery.max_per_dungeon` |
| `clones_ready` | int | |
| `warden` | Dictionary | `{archetype: String, tier: int}`. The archetype comes from `raid.json` `wardens.by_fort` (dungeon-owned); the E1 stub is `bellringer`. |
| `warden_spec` | Dictionary | `{}`: a placeholder reserved for a spec GameState may carry later. The dungeon builds its spec from `warden` + `rng_seed`. |
| `loot_table_id` | String | `"t<tier>.<archetype>"`, e.g. `"t1.bellringer"` (`loot.json`) |
| `loot_hint` | String | as on the fort card |
| `chest_husk` | bool | `true` on the first dungeon: the warden's chest holds a husk |
| `watchtower` | bool | exact tells and percentages are unlocked |
| `relish_hp` | float | `raid.json relish.hp` (30) |
```gdscript
{v: 2, kind: "raid", run_id: 1, seed_rev: 512, rng_seed: "7203661890244157873",
 fort: {id: "old-sluice", name: "Old Sluice", tier: 1, cap: 80.0, first_clear: true, first_dungeon: true,
        clears_since_retaken: 0, yield_mult: 1.0},
 living: 61.2, dead: 3.1, undead: 6.4, garrison_units: 0, garrison_in_mass: 0.0, garrison_mass_div: 10.0, starter_units: 8, party: [],
 digest_q: 1.2, phylactery_charges: 0, phylactery_max_per_dungeon: 1, clones_ready: 0,
 warden: {archetype: "bellringer", tier: 1}, warden_spec: {}, loot_table_id: "t1.bellringer",
 loot_hint: "a husk and a blueprint", chest_husk: true, watchtower: false, relish_hp: 30.0}
```

### 7.2 Boss seed (`kind: "boss"`)
| key | type | meaning |
|---|---|---|
| `v` | int | 2 |
| `kind` | String | `"boss"` |
| `run_id`, `seed_rev` | int | |
| `rng_seed` | String | |
| `backlog` | float | Vei's queue at issue (the horde) |
| `living_pool` | float | |
| `odds`, `sign`, `drain_s`, `digest_q` | float, int, float, float | as in `view_vei` |
| `vei_capacity` | float | `R_vei` |
| `fronts` | Array[Dictionary] | `{id: String, need: float, have: float, assigned: Array[String]}` |
| `fronts_required` | int | `vei.fronts_required` |
| `party` | Array[Dictionary] | a big-undead entry plus `front: String` |
| `phylactery_charges`, `clones_ready` | int | the backups the fight may spend (§8.2) |
| `relish_hp` | float | |
```gdscript
{v: 2, kind: "boss", run_id: 9, seed_rev: 21950, rng_seed: "-3317425092215838120",
 backlog: 18450.0, living_pool: 380.0, odds: 0.61, sign: 1, drain_s: -1.0, digest_q: 2.6, vei_capacity: 50.0,
 fronts: [{id: "giants", need: 24.0, have: 26.5, assigned: ["u4"]}, ...4], fronts_required: 3,
 party: [{uid: "u4", name: "Old Gristle", kind: "hulk", role: "brute", stats: {...}, front: "giants"}, ...],
 phylactery_charges: 1, clones_ready: 1, relish_hp: 30.0}
```

## 8. Results

`int` fields accept a `float` with an integral value (after JSON). `apply_result` converts it.
Unknown extra keys are ignored.

### 8.1 Raid result v2 (dungeon → `apply_result("raid", r)`)
| key | type | rule |
|---|---|---|
| `v` | int | 2 |
| `run_id`, `seed_rev` | int | echoed from the seed |
| `fort_id` | String | the seed's fort |
| `warden_beaten`, `retreated`, `relish_died` | bool | **exactly one** is true: the exit |
| `revived_in_place` | int | ≥ 0: phylactery revives used in the run |
| `killed_living_mass` | float | ≥ 0 |
| `raised` | Array[Dictionary] | every raise this run, grouped: `{score: int (0..100), count: int (≥ 0), mass: float (≥ 0)}` |
| `chaff_mass` | float | ≥ 0: surviving undead that **leave with Relish** to Vei's queue |
| `garrison_mass` | float | ≥ 0: surviving undead that **stay at the fort**. That is the garrison units taken in (`garrison_in_mass`) that survived, plus raises that stay. Starter units are excluded. |
| `party_lost` | Array[String] | big-undead uids that died; no duplicates |
| `loot` | Dictionary | `{relics: int, blueprints: Array[String], husks: Array[{kind: String}], remnants: Array[{aspect: String, rarity: String, magnitude: int}], essence: int}`, all ≥ 0. **Banked loot only:** on `relish_died` the scene drops what it found since the last checkpoint room (MECHANICS §7). |

### 8.2 Boss result v2 (boss → `apply_result("boss", r)`)
| key | type | rule |
|---|---|---|
| `v` | int | 2 |
| `run_id`, `seed_rev` | int | |
| `won` | bool | |
| `fronts_cleared` | Array[String] | ⊆ `FRONT_IDS`, no duplicates |
| `relish_deaths` | int | ≥ 0 |
| `backups_spent` | Dictionary | `{phylactery: int, clones: int}`, both ≥ 0. Each death in the fight spends a phylactery charge first, then a clone. |
| `party_lost` | Array[String] | |
| `backlog_spent` | float | ≥ 0: the horde thrown in. **Informational** (telemetry); the writeback doesn't subtract it. |

Deaths must match the backups spent (`s = phylactery + clones`):
- `won` ⇒ `relish_deaths == s`;
- lost ⇒ `relish_deaths` ∈ {`s`, `s + 1`}, where `s + 1` is a final death with nothing left.

There is no `fort_id`. The open boss run is the check.

### 8.3 Writeback (`apply_result`)
**Raid.** Deltas are computed against the seed and applied to the **live** fort values `f` in this
order, each clamped. The sim has kept running during the run.
- **Net delta, no escrow:** the garrison units' mass never leaves the fort at entry.
1. `k = min(killed_living_mass, f.living)`; `f.living −= k`; `f.dead += k`.
2. If `warden_beaten`:
   - **all** the fort's living become dead: `f.dead += f.living`; `f.living = 0`;
   - the fort flips: `fort_flipped`, held for `flip.hold_s · (1 + flip.tier_mult · tier)` (hold
     E2);
   - `clears_since_retaken += 1`.
3. `R = Σ raised.mass`; `R' = min(R, f.dead)`; `f.dead −= R'`. The `q_raise` EMA takes `raised`,
   mass-weighted and scaled by `R'/R` (E2).
4. **Bound:** if `garrison_mass + chaff_mass > garrison_in_mass + R'`, scale both down
   proportionally to fit.
5. `f.undead = max(0, f.undead + garrison_mass − garrison_in_mass)`; `Δu` is the actual change.
6. Chaff is bounded by what actually left the fort: `chaff = min(chaff_mass, max(0, R' − Δu))`,
   then `vei.undead_queue += chaff`. A drained fort therefore cannot mint mass.
7. The rest, `R' − Δu − chaff`, goes to the ledger's `dungeon` sink. It is ≥ 0 by construction, so
   fort + Vei + sink is conserved.
8. Loot is banked and `loot_banked` is emitted:
   - relics and essence are added, clamped to their caps (any overflow is lost);
   - blueprints are added to the set;
   - each husk and remnant gets a minted uid.

   `fort.first_clear` and the run-wide `first_dungeon` flag clear after any raid result.
9. `party_lost` big undead are removed. `phylactery_charges −= revived_in_place` (clamped at 0), with one
   `relish_died{outcome: "phylactery", in_place: true}` per revive (E3).
10. If `relish_died` (E3, MECHANICS §7):
    - **A clone is ready:** `outcome: "clone"`. She respawns at Covington after
      `backups.clone_respawn_s`.
    - **Otherwise:** `outcome: "unmade"`. There is a morale shock, and the respawn comes after
      `backups.unmade_respawn_s`.
    - In both cases the **whole party** and the unbanked loot are lost (the scene already dropped
      loot found since the last checkpoint), the fort doesn't flip, Relish is `dead`, then
      `relish_respawned`. Nothing in the town or the realm resets (A8).
    - **Until E3** (the E1-safe rule): a ready clone (`clones_ready` > 0, spent) gives `clone`;
      otherwise `unmade`, and the town takes `morale.death_shock` (`TownSim.add_shock`). She
      respawns home at once.
11. If she didn't die, Relish is `at_fort` at that fort. The run closes.

(E1's step 12, the legacy army parity, and boss step 6 below were removed at E2a with the legacy
economy.)

**Boss.**
1. If `won`: set `won = true`. The backlog is unchanged.
   If lost: `vei.undead_queue ×= vei.loss_backlog_keep` (0.35 kept), and the whole party dies
   (MECHANICS §6).
2. `party_lost` big undead are removed.
3. `phylactery_charges −= backups_spent.phylactery`; `clones_ready −= backups_spent.clones` (both
   clamped at 0); one `relish_died{in_place: true}` per spent backup (E3).
4. A final death (`relish_deaths == s + 1`) gives `outcome: "unmade"` (MECHANICS §7), and she is
   `dead`. Otherwise she is `at_vei`. Until E3 a final death follows raid step 10's E1-safe rule.
5. Emits `vei_result` (a boss result carries no loot, so there is no `loot_banked`).

### 8.4 `Results.validate(kind: String, d: Dictionary) -> Array[String]` (`scripts/sim/results.gd`)
- A pure function of its arguments, with no state and no seed. It returns reasons, and an empty
  array means valid.
- `kind` is `raid`, `boss`, `town`, `map`, `raid_seed` or `boss_seed`.
- Each reason is a code, or `code:path` where `path` names the field (e.g. `missing:loot.relics`,
  `type:raised[2].score`).
- Both sides test with it. Seed-dependent and state-dependent checks belong to `apply_result`
  (§4.5).

| code | meaning |
|---|---|
| `unknown_kind` | `kind` isn't one of the six |
| `unknown_v` | `v` missing or != 2 |
| `missing:<path>` | a required key is absent |
| `type:<path>` | the wrong type |
| `range:<path>` | a negative mass or count, `score` outside 0..100, a non-finite float, or an `aspect`/`rarity`/front id outside its list |
| `duplicate:<path>` | a repeated uid in `party_lost`, or a repeated front in `fronts_cleared` |
| `bad_exit` | raid: not exactly one of `warden_beaten`, `retreated`, `relish_died` |
| `bad_deaths` | boss: `relish_deaths` inconsistent with `backups_spent` and `won` (§8.2) |

Town and map results are `{v: 2, teleport_to: String}`, where `teleport_to` is `""` or a node id.
Validate checks the type only; the router treats an unknown id as the map.

### 8.5 v1 → v2 adapter: `Results.from_v1(kind: String, v1: Dictionary, seed: Dictionary) -> Dictionary` (E1)
For unported scenes, the router calls it on any result without `v`, passing the open run's seed.
`run_id` and `seed_rev` come from that seed, never from the scene. Raised buckets use the band
scores (chaff < 60 → 50, soldier 60–89 → 75, elite ≥ 90 → 95).

**Raid** (today's `RaidLogic.Ledger.result` keys). Here `div = raid.mass.garrison_mass_div`,
`s = raised_soldiers`, `e = raised_elites`, `g = good_mass`.

| v1 key | v2 |
|---|---|
| `fort_id` | `fort_id` |
| `killed_living_mass` | `killed_living_mass` |
| `raised_chaff_mass` | `chaff_mass`. Also part of the chaff bucket. |
| `garrison_mass` | `garrison_mass = seed.garrison_in_mass + v1.garrison_mass + v1.good_mass`. Also part of the chaff bucket. |
| `good_mass` | the soldier and elite bucket masses, split by count share. It stays at the fort (inside `garrison_mass`). |
| `raised_soldiers` | `raised += {score: 75, count: s, mass: g · s / (s + e)}` |
| `raised_elites` | `raised += {score: 95, count: e, mass: g · e / (s + e)}` (if `s + e == 0` and `g > 0`, all of `g` goes in the soldier bucket with count 0) |
| (chaff bucket) | `raised += {score: 50, count: roundi((raised_chaff_mass + garrison_mass) / div), mass: raised_chaff_mass + garrison_mass}` |
| `relish_died` | `relish_died`; `retreated = not relish_died`; `warden_beaten = false` (v1 has no wardens) |
| `aborted` | dropped (informational) |
| (none) | `v: 2`, `run_id`, `seed_rev` from the seed, `revived_in_place: 0`, `party_lost: []` (v1 reports no party), `loot: {relics: 0, blueprints: [], husks: [], remnants: [], essence: 0}` |

Buckets with `count == 0` and `mass == 0` are omitted. The writeback then matches v1:
- dead −= chaff + garrison + good;
- vei += chaff;
- undead += garrison.

The one deliberate change: `good_mass` now stays at the fort as undead (MECHANICS §5.3) instead of
vanishing into `army`, which is gone from E2a.

**Boss** (today's `vei_boss.gd` keys)

| v1 key | v2 |
|---|---|
| `fort_id` | dropped (always `"vei"`) |
| `won` | `won` |
| `relish_died` | `relish_deaths = 1 if relish_died and not won else 0` |
| `backlog_spent` | `backlog_spent` |
| `army_lost` | dropped. `party_lost: []` (v1 has no uids). |
| (none) | `v: 2`, `run_id`, `seed_rev` from the seed, `fronts_cleared: []`, `backups_spent: {phylactery: 0, clones: 0}` |

**Town and map v1** are not converted. A legacy map result `{teleport_to}` and a legacy town result
(`town`, `assignments`, `idle_undead`, `spend`, `gather_target`, `deploy_simulacra`, `teleport_to`)
take the router's legacy path (§2.3).

## 9. Persistence

### 9.1 `to_dict()` / `from_dict(d)`
`to_dict()` must survive `JSON.parse_string(JSON.stringify(d))`:
- ints are restored from floats;
- no `Vector2`: positions are `[x, y]` arrays or rebuilt from config;
- no `INF` or `NaN`;
- no int dictionary keys: arrays are used instead;
- the RNG seed and state are saved as decimal strings.

| top-level key | type | contents |
|---|---|---|
| `v` | int | `SAVE_VERSION` (1 at E1, 2 from E2a) |
| `api_version` | int | `API_VERSION` when written (diagnostic only; never rejected) |
| `seed` | String | the game seed |
| `rng` | String | RNG state |
| `t` | float | sim seconds (keeps event `t` monotonic across a load) |
| `acc` | float | the tick accumulator's remainder |
| `next_run_id`, `next_uid` | int | counters (§4.5, §1.3) |
| `applied_runs` | Array[int] | the last 32 applied run ids |
| `relish` | Dictionary | `{state, at, target, pos: [x, y], heading, dead_s_left, respawn_with_clone}`. State is never `in_dungeon` or `in_boss`. |
| `valve` | Dictionary | `{target: {work, war, flood}, current: {work, war, flood}}` |
| `realm` | Dictionary | RealmSim: forts (array with ids: masses, `held_s`, flip and clear counts), Vei, tithe, simulacra |
| `villages` | Array[Dictionary] | `{id, owner}` |
| `town` | Dictionary | TownSim (`TownSim.to_dict()`: stocks, buildings with their staff caps, ladder, convoy, forge, morale, rates, pending events) plus GameState's `tier`, `haul.target` and `work_pending` |
| `stances` | Dictionary | toggles and hold timers |
| `inventory` | Dictionary | husks, remnants, blueprints, relics, essence, `simulacra_ready` |
| `big_undead` | Array[Dictionary] | the entries, with `place` and `front` |
| `party` | Array[String] | |
| `backups` | Dictionary | `{phylactery_charges, clones_ready, vats: [{slot, staffed, grow}]}` |
| `readout` | Dictionary | the `diff` EMA, the `q_raise` EMA |
| `ledger` | Dictionary | sources and sinks so far |
| `won` | bool | |
| `stats` | Dictionary | counters (raids, deaths, raised total) |
| `cleared_forts` | Array[String] | forts whose first clear is spent (sorted) |
| `first_dungeon` | String | the first dungeon's id until a raid result clears it, then `""` |

**What each block holds** (v2; additive keys and E3 placeholders):
- `realm`: `forts` (array in world order: `id`, `living`, `undead`, `dead`, `held_s`, `flipped_count`,
  `clears_since_retaken`, and the per-second rates `r_in`, `r_drain`, `r_shipped`, `r_dead_out`,
  `r_raised`, which the views show), `cov`, `vei` (masses and rates), `simulacra`
  (`{fort_id, charges, rate}`), `elapsed`, `cleared_total`, `raised_by_sims`, and `tithe`. Positions,
  names, caps and tiers come from config.
- `realm.tithe` (E2a, RealmSim's countdowns): `{started: bool, next_s: float (to the next wave),
  next_id: int, warning: {} | {wave_id: int, fort_id, eta_s, surge}, wave: {} | {wave_id: int,
  fort_id, s_left, duration_s, mult, delivered}}`. Loading the E1 placeholder `{warning: {wave_id,
  fort_id, eta_s, surge}}` gives a running cycle with that warning pending, `eta_s` read as the time
  left. An empty block starts the clock at load when a fort has `flipped_count > 0`, else idles. A
  `warning` or `wave` naming an unknown fort makes the save `corrupt`.
- `town` (v2): `workers`, `bodies`, `gold`, `bone`, `living`, `morale`, `shock`; `buildings`
  (`[{lot_id, building_id, level, state, progress, staff_cap, unpaid_s, build_level}]` in lot order;
  `state` is `constructing`, `active`, `idle` or `unpaid`); `ladder`; `haul: {target, current,
  convoys: [{fort, phase, t, trip_s, load, crew}]}` (at most one convoy); `forge: {level, progress}`
  (the q forge); `rates` (TownSim's last step, which the views show); `pending` (events a command
  queued that no substep has emitted yet, e.g. a `building_started`); and GameState's `tier` and
  `work_pending` (the WORK mass the last substep sent, which TownSim takes in the next). `morale`,
  `shock`, `rates` and `pending` are optional on load (TownSim's defaults: morale at its base, no
  shock, zero rates, nothing pending). A building on an unknown or repeated lot, of an unknown id, in
  another state or at a level the building lacks, a ladder that is not a permutation of `JOB_IDS`, or a
  haul target or convoy naming an unknown fort makes the save `corrupt`. A load restores the saved
  building states and recomputes the staffing; the first substep restaffs.
- `stances`: `on` (oldest first) and `hold` (E3 timers, stored as is).
- `backups`: `phylactery_charges` (E3, stored as is), `clones_ready` (the stub stock, read back) and
  `vats` (one per ready clone until E3; only `staffed` is read back).
- `readout`: `diff_ema` (the differential's EMA) and `q_raise_ema` (E2a: `ema_score`, the
  mass-weighted circle EMA behind `q_raise`, MECHANICS §2.2; a new game starts it at 50, and an E1
  save's placeholder 0.0 loads as 50, which the EMA can never reach exactly from 50). `ledger`: `sources` and `sinks` as
  `ledger()` shows them; `sinks.dungeon` is read back. `inventory.simulacra_ready` is written as 0.
- `villages` owners are `player`, `vei` or `none`. Floats are written at 15 significant digits (§10 A12).

**Not saved:**
- `rev`, `debug_enabled`, `save_dir`, the event queue;
- `time_scale` (a load starts at 1) and `paused` (a load starts unpaused);
- the open run, which is forfeited;
- the last substep's rates outside the fort, Vei and town blocks: `view_hud`'s `split` and mint
  `rate`, `view_rates`' `mint`, `work`, `war` and `flood`, `view_vei`'s raw `diff`, and the three lanes
  out of Covington's own rates (FLOOD and WAR fallen through to Vei, WORK). They read 0 (or the lane
  is absent) until the first substep after a load. Lane callouts are not saved either;
- the influence field: after a load it is pre-warmed from the loaded realm, as a new game does
  (`_prewarm_field`, including `field.flush()`), and village owners are restored from `villages`.

**Open runs.** `to_dict()` during a run writes Relish as `at_fort` at the run's fort (or `at_vei`)
with no run. On load the run is forfeited: no loot, no flip, the party intact.

**`from_dict(d: Dictionary) -> {ok: bool, reason: String}`**
- **Reasons:** `bad_version` (`v` above `SAVE_VERSION`, or the migration failed), `corrupt` (missing
  keys or wrong types).
- It resets in place, clears the event queue, bumps `rev`, and keeps
  `next_run_id = max(saved, current)` and `next_uid = max(saved, current)`, so neither ever repeats within a session.

**`static migrate(d: Dictionary) -> Dictionary`** upgrades one version at a time up to
`SAVE_VERSION`. It returns `{}` on failure (no `v`, a `v` that is not a whole number from 1 up, or a
`v` from the future); a save it cannot convert comes back as is, and `from_dict` then calls it
`corrupt`.
- **v1 → v2** (E1 → E2a, `SaveIO._migrate_1_to_2`, no configs needed): the `legacy` block goes.
  `legacy.res` gold, materials, bodies and townsfolk become the town's `gold`, `bone`, `bodies` and
  `living`; `legacy.idle_undead` + Σ `legacy.assignments` become `workers`; `legacy.town.forge_level`
  becomes `forge.level` (progress 0); `legacy.town.vats` becomes `backups.clones_ready`. v1's
  `town.lots` (the BALANCE §0 start set, which nothing at E1 changed) become working buildings with
  v1's `staff_caps`; `tier`, `ladder` and `haul.target` carry over. The legacy army, assignments and
  convoy are dropped (no convoy is out; `work_pending` 0), and morale, shock and the rates start
  fresh. A v1 save loads into a playable v2 state (tests: `tests/fixtures/v1_*.json`).

### 9.2 Files
- A save file is `to_dict()` plus three file-only keys, `slot: String`, `saved_at: int` (unix
  seconds) and `summary: String`, which `from_dict` ignores.
- The path is `<save_dir>/<slot>.json`.
- `list_saves()` reads only `saved_at` and `summary` (the slot is the file name), but skips any file
  that fails to parse, is not a Dictionary or lacks `v`. Order: `saved_at` descending, then slot.
- `summary` is `"<h>:<mm> · <Tier> · odds <0.00>"` (sim clock, town tier, Vei odds).

### 9.3 Atomic writes and corruption
- **Write:** `<slot>.json.tmp`, then close, then `DirAccess.rename_absolute` over `<slot>.json`.
- **Read:** a file that doesn't parse, isn't a Dictionary or lacks `v` is **no save** (`no_save`),
  never a crash.
- **Autosave:** slot `"auto"`, every `sim.autosave_s` (30) real seconds and on every scene change. It
  never persists `in_dungeon` or `in_boss`.
- **Refusals:** `cmd_save` emits `save_failed` for every refusal (`bad_slot` too, with the offered
  slot) and bumps `rev` only on success. `cmd_load` reports a `from_dict` `corrupt` as `no_save`, and
  checks `busy`, then `bad_slot`, before reading. A refused load changes nothing.

### 9.4 Fixtures (`tests/fixtures/`, loaded by `cmd_debug_load_fixture` and the tests)
| file | represents |
|---|---|
| `day1.json` | `cmd_new_game(1)` at t ≈ 0: the BALANCE §0 start. Crypt, 1 Raising Pit, Charnel House, small Market (2 stalls); gold/bone/bodies 80/30/40; 12 workers; 10 living (cap 16); valve 0.40/0.45/0.15; Relish home, no phylactery, no clones or vats; Old Sluice flagged first. |
| `midgame_2flips.json` | About 1 h in, Village tier: the start set plus a House, a Well and a Bone Mill (lots 5–7), which ran the hour. Old Sluice and Ashgate are held, with a tithe warning on Ashgate. Relish is travelling Covington → Greywall. 2 husks, 4 remnants, 3 big undead (one in the crypt, one as a foreman, one sieging Ashgate), a haul convoy in flight (to Greywall), 1 owned blueprint (`embalmer`), forge level 1, relics 3, essence 14. |
| `pre_vei.json` | About 3 h in, City tier: 20 buildings (the start set with the pit and the market at level 2, three more pits, two houses, a well, a bakery, a bone mill, a statue, a Chapel of Vats, a forge, an inn, a graveyard, a watchtower, the Walls and the Reliquary, whose blueprint is owned), up for the last 30 min and none unpaid. Odds ≈ 0.6, a party of 4 big undead assigned to fronts (views show fronts at 0 until E3 computes need/have; the party's front assignments are in the fixture; 3 of 4 fronts would be met), 1 phylactery charge and 1 clone ready. Relish is `at_vei`, so `cmd_begin_boss()` succeeds, and `won` is false. |
| `v1_day1.json`, `v1_midgame_2flips.json` | The E1 (save v1) `day1` and `midgame_2flips`, kept as they were for the v1 → v2 migration tests. Not loadable by name. |

- Each fixture is a `to_dict()` at the current `v`. Fields from E2/E3 systems are written by the
  generator until those systems produce them, and the fixtures are regenerated or migrated in the
  same commit as any save-shape change.
- A test loads all three after every change (save compatibility), and checks that each file is exactly
  what `to_dict()` gives after loading it (the placeholders survive).
- They are produced by `tests/fixtures/make_fixtures.gd` (commands, debug commands and
  `TownSim.place_building` from `cmd_new_game(1)`, then the fields no command can make yet written
  into the state or the dict: the town tier and `realm.tithe` on `midgame_2flips`; the tier, the
  Reliquary blueprint, `backups.phylactery_charges` and `backups.clones_ready` on `pre_vei`). Run it
  by hand when the save shape changes (it takes about 5 minutes). The `realm.tithe` it writes on `midgame_2flips` is still the
  E1 placeholder `{warning}`; from E2a the load maps it into the tithe state (a warning pending on
  Ashgate, 150 s to the wave), so the file holds the full E2a block (§9.1).
- **Contract-test coverage:** across the three fixtures, every array a view exposes is non-empty at
  least once, so the contract test can check element shapes.

## 10. Open points decided here (reversible; each has its reason)
| # | decision | why |
|---|---|---|
| A1 | A 7th Relish state, **`at_vei`** (MECHANICS §3.3 lists six). `cmd_begin_boss` requires it. | Travel is real; a fort-less node needs a standing state. Reusing `at_fort` would put tide and redirect logic at Vei. |
| A2 | **Raid `garrison_mass` is the surviving undead that stay at the fort**; the writeback is the net delta against the seed's `garrison_in_mass`. Garrison and raises that fell go to the `dungeon` sink. | MECHANICS §8 gives the name, not the meaning. This conserves matter, makes garrison losses real, and maps v1 exactly. |
| A3 | `revived_in_place` is an **int** count, not a bool. | It is checked against charges and `max_per_dungeon`; a count survives a later `max_per_dungeon > 1`. |
| A4 | **`drain_s = -1.0`** means holding; `sign` is an int. | MECHANICS allows ∞ in views. A sentinel keeps every view and fixture JSON-safe and testable. |
| A5 | **`view_field()` returns the live field.** It is the only view that isn't a copy. | Copying the grid every frame is waste; the ground unit owns it after E1. |
| A6 | **The field is not saved.** It is pre-warmed on load, and village owners are saved and restored. | It keeps saves small. Accepted drift: a village near the threshold may change owner shortly after a load, which moves migrants a little. |
| A7 | **`rev` is session-only.** | A load must never make `rev` go backwards for a scene caching on it. `seed_rev` staleness compares against the run's recorded value, not the current `rev`. |
| A8 | **A clone death and an unmade death both lose the whole party and the unbanked loot**; unmade adds the long respawn and the morale shock. MECHANICS §7's "nothing else is lost" for unmade means nothing in the town or realm resets. | Read literally, §7 made unmade (the worst outcome) cheaper for the party than a clone. The cost order must be phylactery < clone < unmade. MECHANICS §7 wording is fixed at E3. |
| A9 | **`cmd_pause` is accepted anywhere in debug builds** (release refuses `not_debug`, §4.1), and pauses only the realm. Runs force `time_scale = 1` and unpause on entry. | MECHANICS restricts only the time scale; a tree pause in the dungeon is the scene's business. |
| A10 | Boss `backlog_spent` is informational. A loss keeps `loss_backlog_keep` of the backlog; a win leaves it alone. | Legacy parity, and the ledger counts the loss sink once. |
| A11 | `view_rates` returns `{rev, rates: {id: …}}` and `view_lanes` returns `{rev, lanes: [...]}`, not MECHANICS' bare map and array. | Every view must carry `rev` (§1.3), and mixing `rev` into an id map would collide with the ids. |
| A12 | **`to_dict()` writes floats at 15 significant digits**, as `JSON.stringify` prints them. | Godot's JSON parser is not exact for 17-digit floats (about 1 in 10 differs in the last bit), so `to_dict → JSON → from_dict → to_dict` could never be equal. A loaded float differs from the live one by at most 1e-15 relative. |
| A13 | **Fixtures keep E2/E3 fields as stored values.** `realm.tithe`, `stances.hold`, `backups.phylactery_charges` and `readout` are saved and restored as is. E1 views show `phylactery_charges` (backups, relish, inventory and both seeds) from the stored value; the rest are read by no E1 view, and fronts stay at 0 until E3. | A fixture can carry them now, and E2/E3 read them without a save-shape change. |
