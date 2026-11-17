# Necropolis: GameState API (api_version 10)

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
- **Additions so far:** `api_version` 2 (E2a T2.4) added the `unpaid` reason to `cmd_upgrade` (§4.3).
  `api_version` 3 (E2a T2.5) added the `unique` reason to `cmd_build` and `view_catalog` (§4.3,
  §5.10), and the ledger keys `sources.opening`, `sinks.rot_overflow`, `sinks.haul_overflow`,
  `sinks.store_overflow` and `held.work_pending` (§4.7).
  `api_version` 4 (E2b T3.S) added:
  - `view_town.workers.steady_kept` and `.muster_steady`, and `view_hud.workers_steady_kept` (the
    workforce the town settles at, §5.1, §5.9);
  - `view_hud.war_overflow` and `view_hud.game_id` (§5.1); the save gains an optional `game_id` key (§9.1, `SAVE_VERSION` stays 2);
  - the `risk_pct` range documented for `view_fort.threat` (§5.5);
  - a boot rule that is safe by default (§2.1): any user arg outside `PLAYER_ARGS`, a dev flag or
    `--write-movie` in the engine args, or a headless display server is a harness session;
  - the `sinks.store_overflow` wording changed to "0 until the store caps (E2b T3.2)" (§4.7), and an
    over-cap body store keeps its excess (MECHANICS §4.1): a meaning change, not a shape change;
  - the raid writeback now spends `first_clear` and `first_dungeon` only on a win (§8.3, api-request
    #15), and `pool_overflow` is no longer always 0 since the march-back (§4.7): a meaning change,
    not a shape change;
  - **removed:** the non-contract legacy teleport helper on `GameState` (§2.2).

  `api_version` 5 (E2b-2; later E2b-2 tasks add to this entry) added:
  - `view_staffing_projection(order, vats = {})` (§5.16, api-request #16): TownSim's own staffing
    allocation run with another job order and, optionally, other vats staffed;
  - the vat rule (`cmd_staff_vat`, §4.3; MECHANICS §7): a staffed vat takes a hand, since a Chapel's
    tend slot is open only while its vat is staffed. So `view_town` shows a Chapel's tend `slots`
    only for its staffed vats: a meaning change, not a shape change.

  `api_version` 6 (E2b-2 T3.1; later E2b-2 tasks add to this entry) added:
  - **held forts as two pools** (IDLE §3, MECHANICS §3.4): a flip starts a grace, then her
    counter-garrison contests your garrison; the fort is retaken once the garrison has sat at 0 for
    `hold.break_s`. `fort_retaken`'s `cause` is now `"broken"` (§6); `"expired"` and `"tithe_wave"`
    are no longer raised (the field stays). `fort_flipped.hold_s` now means the grace (same formula).
    A `fort_retaken` carries its moment inside its substep as `t` (§6);
  - the event `big_undead_returned {uid, fort_id}` (§6): a siege big undead at a retaken fort goes
    back to the crypt (IDLE I6);
  - the save's `realm.forts[]` hold keys `held`, `grace_s` and `zero_s` (§9.1). `held_s` is read
    from older saves only (as the grace left) and no longer written;
  - **the held forts' readouts** (api-requests #7 a–c, #13; MECHANICS §3.5): on `view_fort` and
    `view_realm().forts[]`, `garrison`, `garrison_rate`, `fall_s`, `margin`, `margin_cause` and
    `grace_s_left` (§5.5); `view_hud.war_supports` (§5.1); and `view_projection(valve)` (§5.17), the
    same math at another valve, pure;
  - the event `counter_garrison_cleared {fort_id, killed_mass}` (§6, §8.3, api-request #10): a held
    fort's raid cleared its counter-garrison (and the fort was still held when the result was applied);
  - `view_fort.yield_mult` and the seed's `fort.yield_mult` are live (§5.5, §7.1; MECHANICS §5.3):
    the loot yield recovers with real time; the save's `realm.forts[]` gain `yield_c` and `yield_t`
    (§9.1);
  - (T3.2) **build benefit** (api-request #9): `view_catalog().buildings[i].projected` and
    `view_town().buildings[i].upgrade_projected` (§5.10, §5.9);
  - (T3.2) **construction time** (api-request #17): `view_town().buildings[i]` gains `work_left`, `eta_s`
    and `upgrade_work`, and `view_catalog().buildings[i]` gains `work` (§5.9, §5.10), TownSim's own numbers;
  - (T3.2) **the build queue** (IDLE §5, api-request #3; MECHANICS §4.4): `cmd_queue_build`, `cmd_unqueue`,
    `cmd_reorder_queue` (§4.3), `view_town().queue` and `.queue_max` (§5.9), the event `queue_started`
    (§6) and the save's optional `queue` key (§9.1). Gate-blocked entries are accepted as `skipped_gate`
    (the run's manager, 2026-11-14), not refused as #3 first worded it. A `cost_exceeds_cap` refusal names
    what to build first: `store`, `cap_building` and `cap_level` (the run's manager);
  - (T3.2) **the gold and bone caps** (IDLE §6; MECHANICS §4.3): `view_hud().rates[i].cap` for `gold` and
    `bone` is the live cap (it was −1.0); `view_town().gold_cap` and `.bone_cap` (§5.9); `ledger().stores`,
    the currency tally of what the caps clipped, saved with the ledger (§4.7, §9.1); `sinks.store_overflow`
    stays and is always 0. `view_rates` `gold.in` and `bone.in` are now net of what overflowed (§5.2): a
    meaning change, not a shape change;
  - (T3.2) `margin_cause` `"fall"` on a `thin` margin: a held fort that falls beyond the horizon and that
    one full wave wouldn't break reads `thin` / `"fall"`, no longer `thin` / `"wave"` (§5.5; MECHANICS
    §3.5): a meaning change, not a shape change;
  - (T3.4a) **removed:** the non-contract compatibility members `raid_seed`, `boss_seed`,
    `town_snapshot`, `apply_town_result` and `quality` on `GameState`, and `Game`'s forwarding members and
    legacy getters (§2.2);
  - (T3.4a follow-up) **removed:** `legacy_stores()`, the last compatibility member: every compatibility
    member on `GameState` is gone (§2.2); `tests/test_results.gd` now checks the state dict for an army;
  - (T3.4a) **the fort card's warden and loot lines come from the dungeon's configs** (api-request
    #5): `view_fort().warden` gains `name` (§5.5), and `warden.tells` and `loot_hint` (on `view_fort`
    and the raid seed alike) are read from `raid.json` `wardens.archetypes` and `loot.json` `hints`,
    no longer E1 constants: a meaning change, not a shape change;
  - (T3.4a) `view_town().buildings[].starved` (§5.9): a String reason a building's mills milled less than
    their hands want (`"pits_first"`, `"no_bodies"`, else `""`); town renders it in Phase I, economy gives the key;
  - (T3.4b) **a held fort's margin is judged against the wave train** (the run's manager; MECHANICS §3.5):
    `view_fort` and `view_realm().forts[]` `margin` reads `safe` only when the held forts, run forward
    together through her waves at her period from today's state, settle with it unbroken; `thin` (cause
    `wave`) when the train breaks it or hasn't settled by its cap. Its ruled order: `will_fall`, the train
    breaking it, `garrison_rate` < 0 (cause `fall`), unsettled, `safe` (§5.5): a meaning change, not a shape
    change;
  - (T3.4b) `view_projection(valve, settled := false)` (§5.17): the optional `settled` gives the wave train's
    margins at that valve; left out, a drag's one-wave margins, as before. Each `margins` row gains
    `margin_verified` (bool): true for the train's, false for the one-wave probe's;
  - (T3.4b fix batch) **current and planned readouts**: `garrison_rate` and `war_supports` read the current
    split; the margin's train reads the planned support (the valve's target, Relish where she is travelling
    to); `fall_s` is the earlier clock of the two, and `will_fall` follows it (§5.5, §5.17). So a row can show
    `garrison_rate` ≥ 0 with `fall_s` ≥ 0, or with `thin` / `"wave"`, while the valve slews down or Relish
    travels away: a meaning change, not a shape change;
  - (T3.4b) `fall_s` errs early (MECHANICS §3.5): `grace_s_left` + `min(garrison, support / r_drain) /
    −garrison_rate` + what is left of `hold.break_s` (less the zero clock while the garrison sits at 0); it
    was `garrison / −garrison_rate` + `hold.break_s`, late by up to 368 s for a garrison above the level its
    support holds: a meaning change, not a shape change;
  - (T3.3b) **every load catches up** (IDLE §4): `cmd_load` runs the real time since the file's `saved_at`
    through GameState's own core step (`scripts/sim/catchup.gd`) before it returns, and its result gains
    `away_s: float` and `capped: bool` (§4.1). Its `rev` rises by 1 plus 1 per catch-up core step. The
    catch-up's events are collected for the away report (T3.3c), not queued (§6).
    `cmd_debug_load_fixture` and `from_dict` don't catch up (§9.1);
  - (T3.3b) **chunked catch-up**: `cmd_load(slot, chunked := false)` (§4.1); with `chunked` it returns at
    once with the catch-up pending, and each `tick()` runs one chunk of it (§3). `view_catchup()` (§5.18)
    drives a progress screen (the map's, Phase I). Chunking never changes the result;
  - (T3.3b) the reason **`catching_up`** on every command while a catch-up is active (§4's conventions):
    checked first, after `not_debug` where that applies;
  - (T3.3b) **long gaps in the open game** (IDLE §4 When): on the frame path a frame whose real time is
    above `idle.gap_s` goes through catch-up instead of dropping its remainder past the substep cap (§3).
    Under `idle.report_min_s` its events are queued as live, at or above it they are collected for the
    report (§6). Debug fast-forward stays live play (the check is real time);
  - (T3.3b) the shell boots with `cmd_load("auto", true)`, and its autosave waits out a catch-up (§2.1);
    `catching_up()` (§1.5, not contract);
  - (T3.3b) `clock_override` (§1.5), the test seam for "now": `cmd_save` stamps `saved_at` and `cmd_load`
    measures the time away through it. Never saved;
  - (T3.3b) **the load flash**: a load rebuilds the last substep's split and WAR dispatch from what the save
    holds (§9.1). So `view_fort` and `view_realm().forts[]` margins, `fall_s` and `garrison_rate`,
    `view_projection` and `view_hud`'s split read what they read before the save, not the saved `r_in`
    with Relish where she stands. `view_hud.split` and mint `rate`, `view_rates`' `mint`, `work`, `war`
    and `flood`, and the WORK, FLOOD and fallen-through WAR lanes read the last substep's after a load
    instead of 0: a meaning change, not a shape change;
  - (T3.3c) **no run survives a close, a crash, a load or a gap** (IDLE I5, api-request #4):
    `cmd_run_checkpoint(run_id, loot, outcome := "retreated")` (§4.5) records the open raid's banked loot
    and the exit it would end in; the save writes the open run as `pending_retreat` (§9.1), its last
    checkpoint, and a load ends it from that through the normal writeback before the catch-up (§4.1's load
    order), where it used to forfeit it with no loot: a meaning change, not a shape change. A save
    without `pending_retreat` (older) still forfeits its run. A gap above `idle.gap_s` in the open game
    ends the open run the same way, inside the frame that finds it, with the event `run_ended` first (§3,
    §6). A boss run has nothing to bank: `cmd_run_checkpoint` refuses it with `wrong_kind`, and an ended
    boss run is forfeited as `cmd_abort_dungeon` forfeits it;
  - (T3.3c) **a dead run's refusal comes before `catching_up`**: `cmd_abort_dungeon` checks `no_run` first
    (it checked `catching_up` first), and `cmd_run_checkpoint` checks `no_run` and `wrong_run` first (§4,
    §4.5). No run is open during a catch-up, so during one they answer `no_run`: a meaning change, not a
    shape change;
  - (T3.3c) **Relish walks home from a retaken fort** (IDLE I5; the run's manager: live play and catch-up
    alike, one simulation): when the fort she stands at (`at_fort`) is retaken, she starts home to Covington
    at her travel speed from the retake's moment inside its step. The event `relish_returned {fort_id, cause:
    "retaken"}` (§6) and `view_relish().returned` (§5.8), saved as `relish.returned` (§9.1). A dynamics
    change wherever she stands at a fort that is retaken (she used to stay): a meaning change, not a shape
    change;
  - (T3.3c) **the away report** (IDLE §7, api-request #7 d): `view_away()` (§5.19), `cmd_dismiss_away()`
    (§4.1) and the event `away_report {away_s, capped}` (§6), built at the end of every reporting catch-up (a
    load's of 1 s or more, an open-game gap's of `idle.report_min_s` or more) from the events it collected
    and the state before and after; kept until dismissed, never saved. Its text comes from `economy.json`
    `idle.report`. So a load or such a gap now queues one event (`away_report`), where it queued none: a
    meaning change, not a shape change;
  - (T3.3c) **the seeds' `death_ends`** (the dungeon's D-e, via the run's manager): `{outcome: String,
    respawn_s: float}` on the raid seed (§7.1) and the boss seed (§7.2), what a death that ends the run ends
    in, from `view_backups().death`'s rule (§5.13). `Results.validate` checks it when present (§8.4), so a
    seed without it (a dungeon's own demo seed) still validates;
  - **deprecated:** `view_fort.held_s_left` stays and is always 0.0. A held fort is no longer on a
    timer; its grace is `grace_s_left`. The map's grace countdown reads `held_s_left` today and moves
    to `grace_s_left` (its Phase I), and its `fort_horizon` stops seeing a hold timer.

  `api_version` 7 (R1, from the E2b-2 vision review; the run's manager's rule) added:
  - the away report's **`unpaid` line** (§5.19, IDLE §7): a new `kind` value, `"unpaid"`, in `view_away().losses`,
    one line per building that went unpaid during the absence, "Statue of Relish stopped for 1 h 12 m, gold ran
    out: lifted no morale, deaths shook the town harder" (W's wording). Its `target` is the building's **lot id**, a new kind of
    target (additive for map: `AwayLogic.action` reads an unknown target as `none` today; a click could dive to
    Covington at that lot). An enum value is an addition under the rule above, so the version moves to 7;
  - **the upkeep's shed order** (MECHANICS §4.3, `economy.json` `upkeep.shed_order`, `buildings.json`
    `shed_class`): a stock that can't cover the upkeep idles the decorations first, then the passive no-job
    buildings, then the job buildings, the WAR chain (Bone Mill, charnel houses, raising pits) last, where it
    idled the cheapest first. `building_unpaid` (§6) and a building's `state` `unpaid` (§5.9) keep their
    meaning; which building they name changes: a meaning change, not a shape change;
  - (R2, the same review's item 3; R1 and R2 merge as one milestone, so they share this entry and there is no
    v8) **when each queued build becomes affordable**: `view_town().queue[].affordable_in_s: float` (§5.9),
    `0.0` affordable now, the seconds until it is at today's net rates, `-1.0` never at them; and
    `cmd_queue_build`'s extra `affordable_in_s: float` (§4.3), the new entry's (`-1.0` on a refusal), the
    review's warning at queue time. The walk that sets `status` sets it, so the two never disagree;
  - (R2) **the away report's `ready` says why the queue sat still, or that the stores are full** (§5.19, IDLE
    §7): a line for the queue's head still waiting on funds when the absence ends, "Inn is waiting on gold:
    affordable in 6 m" or "House can't be afforded at the current income of 0/s bone: move it down, or build a
    Bone Mill" (`kind` `queue`, `target` `"queue"`; the move down only when another queued entry could start in
    the head's place, F2), and, with the queue empty and gold and bone full (within
    `idle.report.full_tol` of their caps), the prompt "Your stores are full and the queue is empty: raid a fort
    for relics" (`kind` `raid`, `target` `""`). No new `kind` or `target` value, so `AWAY_KINDS` stands; a
    `raid` line with no fort is new (`AwayLogic.action` reads `""` as `none`): a meaning change, additive for
    map. Their text is `economy.json` `idle.report`'s new templates;
  - (F1, the run's manager; F2 sharpened the rule) **that stuck line never names itself or a move that can't
    help** (§5.19): unless some other queued entry could start if the head weren't ahead of it (the queue's walk
    less the head has a row that isn't `skipped_gate` with `affordable_in_s` >= 0) it drops "move it down"
    ("House can't be afforded at the current income of 0/s bone: build a Bone Mill": nothing behind it, or only entries
    that need bone too, or only gated ones), and a head that is its store's own producer gets a true fact for what raises it
    instead of itself ("Bone Mill level 2 can't be afforded at the current income of 0/s bone, and nothing else makes
    bone: move it down"). Text only: the line's `kind`, `target` and shape are R2's;
  - (W, E3's first task; text only: W adds no key and changes no shape, so the version stays 7 and there is no v8)
    **the away report is worded as a returning player reads it** (§5.19, IDLE §7; the run's manager's rulings on
    the review of T7 + R1 + R2): the unpaid line names the store that ran out, "Charnel House stopped for 3 h 20 m,
    gold ran out: hauled no corpses" ("stopped briefly" under a minute; no tail when it stopped nothing,
    "Watchtower stopped for 59 m, gold ran out"; no more "unpaid for", "nothing stopped" or "; stores kept"); a
    queued start reads "House started 2 h 10 m after you left, when the gold came in"; the stuck line reads "at
    the current income of 0/s bone" (the rate still a token of its own); a head short of relics reads Shawn's
    "Crypt level 2 needs relics: raid a fort" with no rate; the full
    store's line reads "Gold is full: 2,162 not stored" (`kind` `overflow`, in `losses`, as before); and "Queue
    empty: plan the next build" no longer shows beside the raid prompt: the prompt takes its place. Kinds,
    targets and the line shape are unchanged.
  - (W2, the run's manager for Shawn; text and report rules only, no key or shape change, so the version stays 7)
    **the relics wall and a start under a minute** (§5.19, IDLE §7): with no entry able to start and one skipped
    on `no_relics`, `ready` shows "Crypt level 2 needs relics: raid a fort" (`queue`, `"queue"`; `afford_relics_fmt`,
    the move-down form, is removed), and a start that waited but began under a minute in reads "Inn started
    within a minute of you leaving, when the gold came in" (`idle.report.started_brief_fmt`).

  `api_version` 8 (E3; the run's manager: E3 has one v8 entry, later E3 tasks add to it, and there is no v9).
  E3-1 (the stances go live, MECHANICS §4.5) added:
  - the save's optional **`stances.state`** (§9.1): `{stance_id: {active: bool, fired_beat_id: int}}` for each
    stance whose condition has changed, written once there is one; and the town block's building **state
    `thrift`**, a building the Thrift stance idles. A save without them (the fixtures', every save before v8)
    loads as nothing held, never fired. `SAVE_VERSION` stays 2. These are the keys that move the version to 8;
    no view, command or event gains a key, so `tests/api_schema.gd` is unchanged.

  Changes of meaning (stubs going live; no shape changes):
  - **§5.11 `view_stances`**: `active` is each stance's condition alone, computed **for every stance, on or
    off** (the run's manager); a stance acts only while it is on, not suspended and active. `fired_beat_id` is
    the beat of its `active`'s last change (−1 before any), `hold_s_left` the `stance.hold_s` left before it can
    change again, `projected` the change in each net rate if it were toggled now (sparse: `{}` when toggling it
    changes nothing). Was: `active` false, `fired_beat_id` −1, `hold_s_left` 0.0 and `projected` `{}` always;
  - **§6 `stance_fired`** is raised at each change of a stance's `active`, on or off (it was never raised);
  - **§3 step 1** runs: the conditions are read at each new beat, and the stances acting are applied every core
    step and by `cmd_set_stance` (§4.3);
  - **§5.9 `view_town`**: `ladder_effective` is the ladder after the stances acting (it was the ladder); a
    building's `state` reads `"idle"` while Thrift idles it ("a stance idles it", which nothing did); and
    `workers.steady_kept` / `.muster_steady` read an idle cap of 0 while Muster acts;
  - **§5.19 `view_away`**: the `unpaid` kind also carries the Thrift line, "Statue of Relish idled by Thrift for
    2 h 10 m: lifted no morale, deaths shook the town harder" (its lot as `target`, as R1's): the kind now means a
    building stopped, by the gold running out or by Thrift. No new kind or target, so `AWAY_KINDS` stands;
  - the build card's `projected` and `upgrade_projected` (§5.10) are computed on TownSim as the stances leave it
    (its effective ladder, idle cap and Thrift's buildings);
  - **§4.3 `cmd_upgrade` and §5.10 the queue's upgrade gate** (QF3, a change of meaning, no new reason): `unpaid`
    now also covers a building Thrift idles (state `thrift`). `cmd_upgrade` on it is refused `unpaid`, and a
    queued upgrade of it waits as `skipped_gate`, reason `unpaid` (the away report: "when it was back at work"), until
    Thrift lets the building go. Was: the upgrade started and took it out of Thrift's set, so it worked at its old
    level and the away report's Thrift line ran to the end of the absence.

  E3-2 (the backups, MECHANICS §7) adds no key (`tests/api_schema.gd` unchanged; the save shape unchanged). Changes
  of meaning (stubs going live):
  - **clones grow** (§3 step 6, §4.3 `cmd_staff_vat`): a vat grows at `vats.grow_per_s` × its tend hands while staffed
    and tended, the Chapel's tend hands going to its staffed vats in slot order (it never grew);
  - **§5.13 `view_backups`**: `vats[].grow` is live and `ready` is `grow` at 1, and `clones_ready` is the vats at 1
    plus any spare clones (was: a plain stock, slot `i` ready while `i < clones_ready`). The same `clones_ready` is in
    `view_relish` (§5.8) and both seeds (§7.1, §7.2);
  - **§8.3** a death's clone (raid step 10, boss step 4) and a boss fight's `backups_spent.clones` (boss step 3) empty
    the lowest ready vat back to 0, then a spare clone (was: the stock −1);
  - **§9.1 `backups`**: each vat's `grow` is read back, and the old-save rule reads a `clones_ready` above the vats at 1
    as spare clones (was: only `staffed` read back, `clones_ready` the stock);
  - **the death order** (MECHANICS §7; §8.3 raid steps 9–10): a raid's revives in place spend their charges with one
    `relish_died{outcome: "phylactery", in_place: true}` each (was: spent with no event), then a death that ends the run
    wakes her from a clone, else unmakes her (the clone is the lowest ready vat);
  - **real respawns** (§5.8 `view_relish`, §6 `relish_died` / `relish_respawned`, §3 step 6): a run-ending death
    leaves her `dead` at its node for the outcome's `respawn_s` (`backups.clone_respawn_s` 60, `unmade_respawn_s`
    600), `dead_s_left` counting down and `respawn_with_clone` set, then `relish_respawned` puts her home; catch-up
    clips at it (IDLE §4). While dead the home stance slot, Vigil and her home effects read her away, and the `dead`
    refusals (§4.2, §4.5) apply. Was: `respawn_s` 0.0 and an immediate `relish_respawned`, never `dead`;
  - **the party lost in both outcomes** (§8.3 step 10; A8): the code already did; MECHANICS §7's unmade line now
    says so;
  - **§5.13 `view_backups` live**: `death` reads `phylactery` while a charge can revive her (in place, `loses` []),
    else `clone` / `unmade` with the real `respawn_s`; `dead_s_left` is live. The seeds' `death_ends` (§7.1, §7.2)
    skip the phylactery step and carry the real `respawn_s` (was: 0.0).

  E3-3 (big undead, MECHANICS §4.6) adds **`filled_slots: int`** (api-request #6) to every big-undead entry:
  `view_big_undead().big_undead[]`, `view_party().party[]` and `cmd_raise_big_undead`'s `big_undead` (§5.12), the
  dungeon seed's `party[]` (§7.1) and the boss seed's (§7.2); `tests/api_schema.gd` `BIG_UNDEAD`, `SEED_PARTY` and
  `BOSS_PARTY` gain it. The save's big-undead record carries it too, optional (§9.1): **a record without it loads
  as 1** (the run's manager's ruling), so every fixture and every save before v8 does, and so does a debug mint
  (`cmd_debug_grant`'s `big_undead` raises nothing on the slab). One is what the dungeon party and the Vei fight
  drew before (`maxi(1, filled_slots ?? 1)`), so those big undead fight as they did. `SAVE_VERSION` stays 2.
  Changes of meaning (stubs going live):
  - **§4.3 the raise is live** (`cmd_raise_big_undead`): it checks the recipe with SlabLogic, consumes the husk and the
    remnants, mints `u<n>` and stores the entry in the crypt (was: an `ok` with a zero-valued entry and no change);
  - **`at_cap`** is returned when the big undead number `big_undead.cap` plus `big_undead.per_crypt_level` per
    Crypt level above 1 (`view_big_undead().cap`), and `invalid_recipe` and `bad_name` are checked (they were
    listed and never returned).

  E3-3's foreman adds **`foreman_mult: float`** to `view_town().buildings[]` (§5.9; `tests/api_schema.gd`
  `TOWN_BUILDING`): the multiplier the building's job output gets from its foreman, 1.0 with none or where one
  gives nothing. Changes of meaning:
  - **the foreman works** (MECHANICS §4.2; `cmd_place_big_undead`, §4.3): a big undead placed `town:<lot_id>` at an
    `active` job building multiplies its job output (the Market's gold, the Bone Mill's bone, the Raising Pit's burn
    and raise, the Charnel House's carry, the Forge's work, the Chapel's vat growth) by `foreman.mult + speed ·
    foreman.speed_k`, and lifts the morale target by `foreman.presence_k · presence` (a new factor id, `foreman`,
    in `view_town().morale.factors`). Every view that reads TownSim's flows shows it: `view_town` (`output`, the
    rates), `view_rates`, `view_hud`, the stances' and the build card's `projected`, the queue's `affordable_in_s`.
    Was: recorded and echoed, no effect;
  - **Σ foreman_q is dropped** from `q` (MECHANICS §2.2; `view_vei().digest_q`, the seeds' `digest_q`): a foreman
    adds no `q`. A Forge foreman reaches `q` only through the forge level its smiths reach sooner. Was: a term
    documented as 0 until E3.

  E3-3's siege adds no key. Changes of meaning:
  - **the siege block is live** (§3 step 5, MECHANICS §3.4; `cmd_place_big_undead`, §4.3): a fort with a big undead
    placed `fort:<id>` gets `tithe.siege_block` (0.6) in RealmSim's `siege_block`, flat, one per fort (a second
    siege is allowed and adds nothing). A wave there surges × (1 − 0.6), and its `tithe_wave` event's `siege_block`
    reads 0.6. A retake sends the siege home (`big_undead_returned`, as before) and the block goes from that moment,
    inside a catch-up's long step too. Was: `{}` always, `siege_block` 0.0 on every wave;
  - **the margin chip credits no siege** (the run's manager's ruling; MECHANICS §3.4): `view_fort`'s `margin`,
    `margin_cause`, `fall_s` and `garrison_rate` (the wave train), and `view_projection`'s `margins`, read every fort
    as if unsieged. So they are conservative: a fort reads `safe` only if it holds without its siege, and may read
    `thin` where the siege actually holds it. Crediting the siege is an E4 item, once the train's support mirrors the
    sim. Unchanged in shape, and unchanged from before the siege for every fort: the chip reads what it read when a
    siege did nothing;
  - **kill power is not built** (the run's manager's ruling): a siege's only effect is the block. The docs said a siege
    "adds kill power" (`cmd_place_big_undead`'s Args); that is struck, and goes to E4 only if the hold band needs it.

  E3-4's crafting (MECHANICS §3.6, §7) adds no key (`tests/api_schema.gd` unchanged; the save shape unchanged:
  `inventory.simulacra_ready` was always written, and from E3-4 it is read back, optional on load). Changes of meaning
  (stubs going live):
  - **§4.3 `cmd_craft` is live**: instant; it takes `economy.json` `craft.<item_id>`'s essence and relics and adds 1 to
    the simulacra ready or the phylactery charges, `count` the new stock. The refusals in order: `unknown_item`,
    `needs_building`, `no_essence`, `no_relics` (was: `unknown_item`, then `ok` with `count` 0 and no change);
  - **`needs_building` is read from `craft_slots`** (the run's manager's ruling): the built buildings' `craft_slots` (the
    Ossuary Tower's, 1 per level) sum to under 1. A capacity effect, so an unpaid or Thrift-idled Ossuary still crafts;
    one on its first build doesn't. `view_catalog`'s crafts give the same reason (§5.10; it read "no Ossuary Tower built",
    which agreed with the shipped configs);
  - **`simulacra_ready` is live** in `view_inventory` (§5.12) and the save (§9.1): a GameState stock, written as it
    stands and read back, a save without it reading 0 (was: 0 in both). Neither stock has a cap of its own (the run's
    manager's ruling): the essence and relic caps bind them;
  - **`stats.sims_built`** (the save's, §9.1) counts the simulacra crafted (it was never moved).

  E3-4's simulacra (MECHANICS §3.6) add no key either (`tests/api_schema.gd` unchanged; the save's `realm.simulacra`
  was always written and read back). They add **`realm.json` `simulacrum.rate` (1.0 mass/s) and `simulacrum.charges`
  (300 mass)**, read REQUIRED by GameState (E4 placeholders, BALANCE §5). Changes of meaning (stubs going live):
  - **§4.3 `cmd_deploy_simulacrum` is live**: it takes one from `simulacra_ready` and plants `{fort_id, charges, rate}`
    from those keys in RealmSim's `simulacra`, returning its `charges` (300.0) and `ready_left`. The refusals in order:
    `unknown_fort`, `none_ready` (was: `unknown_fort`, then `ok` with 0.0 charges, 0 ready left and nothing planted). Any
    fort takes one, and several at one fort stack: `view_fort().simulacrum_charges` (§5.5) sums them;
  - **simulacra raise** (RealmSim already ran its list; now a command fills it): from the next step a planted one
    performs Relish's redirect at its fort at `rate` until its charges run out, then crumbles. While it has charges the
    garrison's kills there stay as corpses (`view_rates` `corpses`, `view_lanes` `redirect` and its `"simulacrum"`
    callout, §5.2, §5.3), and the raised mass reaches Vei as that fort's drain. A retake loses it (MECHANICS §3.4; IDLE
    I6), live and inside a catch-up;
  - **catch-up clips at a simulacrum running out** (IDLE §4, `Catchup.simulacrum_out_s`): at `charges / rate` while its
    fort's corpses cover the raises wanted there until then, and not under one substep. Unclipped, one running out
    inside a 15 s step read +8.5% on its fort's undead at that step's end;
  - **the margin credits no simulacrum**, as it credits no siege (§5.5): `view_fort`'s `margin`, `margin_cause`,
    `fall_s` and `garrison_rate`, and `view_projection`'s `margins`, read a held fort's support without the raises of the
    simulacra planted there (Relish's sustained raise is the only one). Conservative; crediting them is E4's.

  E3-5 (the Vei glue, MECHANICS §6) adds **`counted: Array[String]`** to each `view_vei().fronts[]` entry (§5.14;
  `tests/api_schema.gd` `view_vei`'s fronts row): the uids VeiFronts counted on that front, so **`have` counts the uids in
  `counted`, and `assigned` lists only what the player put there** (`cmd_assign_front`). An unassigned party member is in
  the `counted` of the front of its highest stat and in no `assigned`. The boss seed's fronts (§7.2) gain nothing: they
  keep `{id, need, have, assigned}`. The save shape is unchanged. Changes of meaning (stubs going live):
  - **§5.14 `view_vei`'s fronts are live**: `need`, `have` and `cleared` are `VeiFronts.have_need`'s on her backlog (the
    undead queue), living pool, `digest_q` and the big undead, with `vei.json` (was: 0.0, 0.0 and false always), and
    `fronts_met` is the cleared count, `VeiFronts.fronts_met` (was: 0 always). `assigned` keeps its meaning;
  - **§7.2 the boss seed's fronts are live**: the same `need` and `have`, computed from the seed itself
    (`VeiFronts.info_from_boss_seed`, the fight's own recompute), `assigned` the echo (was: 0.0 and 0.0, so the fight
    computed them itself);
  - **§8.3 boss step 3 raises the fight's revives**: one `relish_died{outcome: "phylactery" | "clone", in_place: true,
    at: "vei", respawn_s: 0.0}` per backup in `backups_spent`, the phylactery charges first, then the clones
    (`VeiFronts.next_backup`'s order), after `vei_result` and before a final death's `relish_died` (was: spent with no
    event). No new event type.

  `api_version` 9 (E4 step 2's sizing stop, the run's manager's ruling 2: lever (b), the husk craft) added:
  - **§4.3 `cmd_craft_husk(kind)`**: the weakest `economy.json` `craft.husk.remnants` remnants and `craft.husk.bone`
    bone into a t1 husk (`loot.json` `chest_by_tier["1"].husk_kinds`); reasons `catching_up`, `unknown_kind`,
    `no_remnants`, `no_bone`; extra `husk`. Its costs are GUESS;
  - **§5.10 `view_catalog().husk_craft`**: `{kinds, cost: {bone, remnants}, can_craft, reason}`.
  The save shape is unchanged (a crafted husk is a husk). The town's UI for it is a Phase I item.

  `api_version` 10 (E4's steps 4–5 milestone; one entry, later steps add to it) added:
  - **§4.3 `cmd_craft_husk`'s reason `at_cap`** (the E4 code review): the crypt has no room for another husk (its big
    undead plus the husks waiting reach the `big_undead` cap), checked last; `view_catalog().husk_craft.reason`
    reads it too. The save shape is unchanged.
  - **§4.4 `cmd_queue_build`'s gate `upkeep`** (E4 step 4, the E4 ruling (3)): a new building whose gold upkeep would
    take net gold negative is `skipped_gate` with reason `upkeep`, and `waited_on` / `queue_started.waited_on` can
    read `upkeep` (`idle.report.waited_on.upkeep`). §5.19 `view_away`'s `ready` gains a line for the first such entry
    (`idle.report.afford_upkeep_fmt`, kind `queue`, target `queue`). No key changes.
  - **The resume rule's income test** (MECHANICS §4.3, `economy.json` `upkeep.resume_net_min`; the manager's ruling
    (i) on the gold-trap stop): an unpaid building held off by the income reads `upkeep` (not `unpaid`) as a queued
    upgrade's reason and `waited_on`, and `view_away`'s `ready` lists such buildings on one line
    (`idle.report.unpaid_upkeep_fmt`: the income and "Build a Market", kind `queue`, target `queue`). No key changes.
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

  Action commands were stubs that ran their id checks (`unknown_*`), then returned `ok` with
  zero-valued extras and changed nothing: build, upgrade, demolish and cancel until E2a T2.4,
  the raise until E3-3, and the craft and the deploy until E3-4. None is left. Stub views return
  BALANCE §0 constants or the stub values noted at each view.

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
const API_VERSION := 10
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
| `var clock_override: int = -1` | v6 (E2b-2 T3.3b), a test seam: unix seconds "now" when ≥ 0, else the system clock. `cmd_save` stamps `saved_at` with it and `cmd_load` measures the time away with it, the sim's one read of the wall clock. Never saved; scenes never set it. |
| `tick(dt: float, max_substeps := 0) -> int` | §3. |
| `drain_events() -> Array[Dictionary]` | §6. Called by the shell and tests, **never by scenes**. |
| `to_dict() -> Dictionary`, `from_dict(d: Dictionary) -> Dictionary` | §9. |
| `static migrate(d: Dictionary) -> Dictionary` | §9. |
| `list_saves() -> Array[Dictionary]` | §4.1. |
| `ledger() -> Dictionary` | §4.7 (tests). |
| `catching_up() -> bool` | **Not contract** (v6, E2b-2 T3.3b): whether a catch-up is active (`view_catchup().active`), for the shell's autosave. |
| `catchup_events() -> Array[Dictionary]` | **Not contract** (v6, E2b-2 T3.3b; tests and the away report, `view_away`, §5.19): the events the last catch-up that a report replaces collected instead of queuing them (a load's, or an open-game gap's of `idle.report_min_s` or more; §6), in queue order with their `t`, as deep copies; `[]` after a new game or a load with nothing to catch up. |
| `worker_mass() -> float` | **Not contract**: `economy.json` `worker.mass`, the mass of one worker (the ledger and tests use it). |
| `var relish_returned: Dictionary` | **Not contract** (v6, E2b-2 T3.3c): her last walk home from a retaken fort, `{fort_id, cause, t}` or `{}`; scenes read it as `view_relish().returned` (§5.8). Read-only by rule. |
| `static report_config_problem(cfgs: Dictionary) -> String` | **Not contract** (v6, E2b-2 T3.3c): `""` when `economy.json` `idle.report` has every key the away report reads (`GameState.REPORT_KEYS`) and words every queue reason, else what is missing; `setup()` reports it as an error (tests use it). |
| `var town_sim: TownSim` | **Not contract** (no API_VERSION bump): Covington's economy (MECHANICS §4), created once and reset in place. Tests and the fixture generator use it; scenes read the views. |

## 2. The `Game` shell (`autoload/game.gd`)

### 2.1 Contract
```gdscript
var state: GameState                  # stable for the session (§1.2)
signal game_event(ev: Dictionary)     # one signal for every event, in queue order; filter on ev.type
var autosave_enabled: bool            # false in a harness session; set once at boot, read-only by rule
func autosave() -> Dictionary         # = state.cmd_save("auto"); the router calls it after every swap;
                                      # {ok: false, reason: "disabled"} (nothing written) when !autosave_enabled;
                                      # {ok: false, reason: "catching_up"} (nothing written, no event) while
                                      # a catch-up is active (v6)
```
- **Boot (`_ready`):**
  `state = GameState.new()` once, `state.setup(ConfigDb.data)` (the same `load_configs` output), then
  `state.debug_enabled = OS.is_debug_build()` (before any boot load, since fixtures need it), then
  the boot rule over `OS.get_cmdline_user_args()`:
  - **Harness/test session:** `BootRule.is_harness(user_args, engine_args, headless)`
    (`scripts/sim/boot_rule.gd`, which holds `PLAYER_ARGS` and `DEV_ARGS`) is the pure static
    decision, called with `OS.get_cmdline_user_args()`, `OS.get_cmdline_args()` and
    `DisplayServer.get_name() == "headless"`. It is true when any of these holds:
    1. any user arg (after `--`) is not a player flag. `PLAYER_ARGS` (today only `--reduced-motion`;
       an arg matches as `--flag` or `--flag=value`) are the only user args that leave a normal
       session, so every unit's debug flags (`--valve=`, `--lanes`, `--bench-*`, ...) make a harness
       session without being registered;
    2. any engine arg (before `--`, where a flag given without the separator lands) is a `DEV_ARGS`
       entry (`--shot=`, `--new-game`, `--fixture=<name>`, `--teleport=`, `--scene=`, `--select=`,
       `--speed=`, `--cheat=`, `--finish-raid`, `--trace=`, `--clicks=`; `--flag` or `--flag=value`),
       or is `--write-movie`;
    3. the display server is headless.
    So an unregistered flag can't autosave over the shared `auto.json` only when it comes after
    `--`; one given without `--` is caught only if it is in `DEV_ARGS`.
    `BootRule.is_harness_args(user_args)` is rule 1 alone. The test runner is headless but runs under
    `--script`, where the Game autoload does not boot, so no test depends on a headless player session.
    `autosave_enabled = false` for the whole session (`autosave()` returns
    `{ok: false, reason: "disabled"}` without writing, and the 30 s timer does nothing), so the
    player's `auto.json` is never touched. The boot state is `cmd_debug_load_fixture(name)` for
    `--fixture=` (if refused, an error is printed and it falls back to `cmd_new_game(randi())`),
    otherwise `cmd_new_game(randi())`.
  - **Normal launch** (a windowed launch with no args, or only `PLAYER_ARGS`): `cmd_load("auto", true)`
    (v6: the catch-up of the time away runs in chunks over the first frames, so a week away doesn't
    freeze the window; `view_catchup` drives a progress screen); if that is not `ok` (no file, or
    corrupt), `cmd_new_game(randi())`. Autosave stays enabled, **except** after `bad_version` (a
    newer build wrote `auto.json`; worktrees share `user://`): then autosave is off for the session
    and a warning is printed, so the newer save is never overwritten.
  - The load catches up the real time since the save file's `saved_at` (IDLE §4; `cmd_load`, §4.1), so
    Continue resumes where the time away left the realm.
  - **Tested headless** (E2b-2 T3.3c): `tests/slow/boot_week.gd` compiles the shell's own source with two
    substitutions, made by exact match (`ConfigDb.data`, which `--script` lacks, becomes the same loader;
    the boot rule's harness decision becomes a normal launch), and boots it on a save taken mid-run, a week
    away: the run ends before the first chunk, the catch-up finishes, live substeps resume, the due autosave
    waits it out and then saves, the scenes' commands during it get `catching_up` or the dead-run refusals,
    and nothing is logged as an error.
- **Ticking (`_process(delta)`):**
  `state.tick(delta / maxf(0.05, Engine.time_scale) * state.time_scale, max_substeps)`. Here
  `max_substeps` is `economy.json` `sim.max_substeps_per_frame`. A frame whose real time is above
  `idle.gap_s` goes through catch-up; under it, any remainder over the cap is dropped (§3). `tick`
  divides by `time_scale` for the real time, so the shell passes nothing more.
  - The sim runs on **real** delta. Trance's `Engine.time_scale` never slows the realm.
  - `tick` itself honours `paused`.
- **Events:** each frame, after ticking, the shell drains `state.drain_events()` and emits
  `game_event(ev)` for each event, in order.
- **Autosave:** every 30 real seconds (unscaled delta) and on every scene change (the router calls
  `autosave()`). While a catch-up is active it writes nothing (a save then would lose the time still to
  run) and the 30 s clock stays due, so the save follows the catch-up. The resulting `autosaved` / `save_failed` events reach scenes through
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
| `won` | `state.won` | world_map |
| `time_scale: float` | get: `state.time_scale`. Set: writes `state.time_scale` **unvalidated** (any value > 0). Keeps working in release builds; used by the map's ×1/×10/×60 buttons and `--speed=`. | world_map, shot |
| `raiding_fort_id() -> String` | the active raid run's fort id, or `""` | map_nodes, shot |

**Compatibility members on `GameState`** (not contract): none remain. `legacy_stores()` (the E1 stores
rebuilt from the new state) was the last; it was removed once `tests/test_results.gd` stopped calling it.
`raid_seed(fort_id)`, `boss_seed()`, `town_snapshot()`, `apply_town_result(r)` and `quality()` were
removed in T3.4a, with `Game`'s forwarding members and its `res`, `army`, `town`, `assignments`,
`idle_undead` and `gather` getters: nothing called them (`view_dungeon_seed`, `view_boss_seed` and
`digest_q()` are the contract). `Results.KINDS` keeps `"raid_seed"` and `"boss_seed"`: they validate those
two views' seeds.

**Removed at E1** (replaced by commands): `new_game`, `begin_raid`, `end_raid`, `apply_raid_result`,
`auto_resolve_raid`, `apply_boss_result`, `auto_resolve_boss`. shot.gd's cheats move to
`cmd_debug_*` (from E2a `--cheat=boss` no longer writes `Game.army`).

**Removed at E2a:** `scripts/sim/legacy_economy.gd` (`LegacyEconomy`) and `GameState`'s `legacy`, `res`,
`army`, `town`, `assignments`, `idle_undead` and `gather` members. TownSim is the town.

**The legacy teleport helper was deleted at API v4.** The map's TELEPORT button was its last
scene caller. Tests and tools that need her at a node use `cmd_debug_set_state({relish_at: id})`
(§4.6), which refuses with `busy` while a run is open.

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

- **E1 compatibility** (removed in T3.4a): the router once merged a legacy seed (`Game.raid_seed`,
  `boss_seed`, `town_snapshot`) into `args` for an unported scene; nothing calls them now. Ported
  scenes ignore unknown `args` keys.
- **`teleport_to`** names the node whose scene opens next; `""` means the map. With `v: 2` it never
  moves Relish.
- **Router flow:**
  - `teleport_to` handling:
    - `"covington"`: open the town.
    - `"vei"`: call `cmd_begin_boss()`. On `ok`, open the boss; otherwise the map (which shows
      `view_vei().reason`).
    - a fort id: call `cmd_begin_dungeon(id)`. On `ok`, open the dungeon; otherwise the map.
    - an unknown id: open the map.
  - A map or town result is always v2 and the router never moves Relish for it (there is no legacy
    branch; the old teleport helper was deleted at API v4). It reads `teleport_to` and runs the
    flow above.
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
  - **Long gaps** (v6, E2b-2 T3.3b; IDLE §4 When): with `max_substeps > 0` (the frame path), a call
    whose real time, `dt / time_scale`, is above `idle.gap_s` (30 s) goes through catch-up instead:
    its whole seconds, chunked (below), with its fraction added to `acc`. So the drop above applies only
    to a hitch under `idle.gap_s`, and debug fast-forward (a large `dt` from a large `time_scale`) stays
    live play. **A run open at the gap ends first** (v6, E2b-2 T3.3c; IDLE I5: the machine asleep in a
    dungeon): inside the frame that finds the gap, before its catch-up starts, the event `run_ended {run_id,
    kind, outcome, cause: "gap"}` is queued, then the run ends from its last checkpoint as a load ends a
    `pending_retreat` (§4.5 `cmd_run_checkpoint`), and the writeback's events follow it, queued as live (not
    collected for a report). A paused sim returns 0 before any of this, so paused time is never time off (I9). A call
    with no cap (tests, `cmd_debug_skip_time`) never routes a gap: it runs its substeps as before.
  - **While a catch-up is active** (a chunked `cmd_load`'s or a gap's, `view_catchup().active`): each
    call runs one chunk of it, `idle.catchup_steps_per_chunk` core steps, instead of live time, does no
    frame work (the field's `advance`, the build benefit's and the wave train's refreshes) and returns 0.
    The calls' own `dt` accumulates. When the catch-up finishes, that time runs as the finishing call's
    `dt`: through catch-up again if its real time is above `idle.gap_s`, else as live substeps with the
    cap raised to `idle.gap_s / sim.substep_s`, so none of it is dropped at 1×.
  - Otherwise `acc -= n * sim.substep_s`. The remainder is kept and saved.
  - `max_substeps = 0` means uncapped; tests and `cmd_debug_skip_time` use it.
- Each substep advances `t += sim.substep_s`, runs the steps below **in this order** (a contract
  with tests, MECHANICS §1.3), then `rev += 1`. Steps 1–8 are the core step, valid at any length
  (catch-up runs it at its own `dt`, IDLE §4); step 9 and the lanes' callouts are the presentation
  step:
  1. **Stances and the job ladder.** Re-evaluated only when the beat index
     `beat_id = floor(t / beat_s)` changes, where `beat_s = pulse.json tempo_ms / 1000` (1.714).
     Emits `stance_fired`. (v8, E3-1; MECHANICS §4.5) Each hold runs down by the step's `dt`; at a new beat every
     stance's condition is read from the state the step starts from, and each whose hold is over and whose
     condition differs from its `active` changes (`stance_fired`, a fresh `stance.hold_s`). Then the stances
     acting (on, not suspended, active) are given to TownSim for this step: the jobs they lift, Muster's idle cap
     of 0, Thrift's buildings. Catch-up runs it the same way at its own `dt` (IDLE §4).
  2. **The valve.** Slew the current vector toward the target by at most `valve.slew_per_s · dt` of
     L1 distance (the sum stays 1). The mint reads the working pits now and the feed of the step
     before (TownSim's `rates.feed`). Split it into WORK, WAR and FLOOD.
  3. **TownSim.** Workforce, on this step's WORK (`work · dt`, in the same step: E2b replaced WORK
     arriving one substep late). Also jobs, haul, mill, pit burn, living, gold, bone, morale,
     construction and upkeep. Emits `building_*` and `tier_up`. Its muster joins this step's WAR. Then the
     tiers rise and the build queue is processed (v6; MECHANICS §4.4): its `next` entries start, in order,
     and emit `queue_started`.
  4. **Relish's travel and state** (GameState). Position, heading and arrival.
  5. **`RealmSim.step(dt, {war, flood, digest_q, tide_fort, tide_bias, redirect_fort, redirect_rate, siege_block})`.**
     Holds and the tithe state are RealmSim's own, not inputs (MECHANICS §3.1). Includes hold
     expiry and the tithe cycle, which starts at the first flip. Emits `fort_retaken`,
     `tithe_warning` and `tithe_wave`. `tide_fort` is also where Relish stands, so a surge there
     is halved; `siege_block` (fort id → the fraction of a surge a siege cancels) is `tithe.siege_block` at each fort
     with a big undead placed `fort:<id>` (v8, E3-3; `{}` before): flat, one per fort. A fort retaken inside the step
     loses it for the step's later parts, and the next step's inputs have none there (the siege went home).
  6. **Backups.** Vats grow and respawn timers count down; Backups is the only writer of death and
     respawn. Emits `relish_respawned`. (v8, E3-2; MECHANICS §7) Each vat grows by `vats.grow_per_s` × its tend
     hands × `dt`, clamped at 1, on the hands TownSim's step (step 3) staffed it with; a vat whose Chapel is gone
     leaves its ready clone as a spare. Linear, so catch-up runs it the same way at its own `dt`, exactly. While
     Relish is `dead` her `dead_s_left` runs down by `dt`, and at 0 she wakes at Covington, `home`, with
     `relish_respawned` stamped at the step's `t`; catch-up clips a step at it (IDLE §4), so it lands on her
     respawn's moment exactly.
  7. **The ledger.** Books the substep's mint (source) and its sinks: TownSim's rot loss, rot and
     haul overflow, pit burn and milling, and RealmSim's `k_clear` (§4.7). `held` is read live.
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

**`catching_up`** (v6, E2b-2 T3.3b; IDLE §4): while a catch-up is active (`view_catchup().active`: a
chunked `cmd_load`'s, or an open-game gap's), every `cmd_*` returns `{ok: false, reason: "catching_up"}`
with its own extras zero-valued, changes nothing and leaves `rev` alone. It is checked first, after
`not_debug` where that applies (the time controls and the debug commands), so it heads every reason list
below without being repeated in each. `cmd_save`'s refusal emits `save_failed` as every refusal does
(the shell's autosave doesn't call it then, §2.1). `apply_result` is not a command and isn't refused.
Views stay readable during a catch-up and show the state as far as it has run.

**The exception: the run commands** (v6, E2b-2 T3.3c; IDLE I5). Every open run ends before a catch-up
starts (§4.1's load order, §3's gaps), so no run is live during one. On a run that has ended, every run
command gives its **dead-run refusal, whether or not a catch-up is active**: `cmd_abort_dungeon` and
`cmd_run_checkpoint` check `no_run` (and `cmd_run_checkpoint` `wrong_run`) before `catching_up`, and
`apply_result`, which `catching_up` never gates, answers `duplicate_run` (an ended raid) or `wrong_run`
(an ended boss run). So a dungeon scene still sitting on an ended run learns it is over instead of being
told to wait. `cmd_begin_dungeon` and `cmd_begin_boss` open a run, not act on one, and keep `catching_up`
first.

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
- **Extras:** `saved_at: int` (unix seconds, from `clock_override` when it is set, §1.5), `path: String`.
- **Reasons:** `bad_slot`, `write_failed`.
- **Effect:** writes atomically (§9.3).
  - During a run it writes Relish at the run's fort (`at_fort`, or `at_vei`) and the run as
    `pending_retreat` (v6, E2b-2 T3.3c; §9.1), its last checkpoint, which a load ends it with; it leaves
    the live state alone.
  - On success with slot `"auto"` it emits `autosaved`. On any failure it emits `save_failed`.
```gdscript
Game.state.cmd_save("slot1")  # -> {ok: true, reason: "", saved_at: 1794556800, path: "user://saves/slot1.json"}
```

**`cmd_load(slot: String, chunked := false)` · E1 (catch-up v6)**
- **Extras** (v6, E2b-2 T3.3b): `away_s: float`, the seconds caught up, and `capped: bool`. Both are 0.0
  and false on a refusal.
- **Reasons:** `busy`, `bad_slot`, `no_save` (missing or corrupt; a corrupt file is no save),
  `bad_version` (newer than `SAVE_VERSION`, or the migration failed).
- **Effect:** `from_dict` in place. Then `time_scale = 1`, `paused = false`, the event queue is
  cleared, and the field is pre-warmed (§9).
- **The load order** (v6, E2b-2 T3.3c): `from_dict` (the state as saved, the queue cleared), then **the
  run open at the save ends** (its `pending_retreat`, §9.1: through the normal writeback, as a result of
  its last checkpoint's outcome; IDLE I5), then the catch-up below, then (when it caught up 1 s or more) the
  away report (§5.19) and its `away_report` event, queued after the run's events.
  The run's end comes first on both paths: the synchronous load and `chunked`, where it is done before
  `cmd_load` returns and so before the first chunk. Its events (`loot_banked`, `fort_flipped`,
  `relish_died`, …) are queued for the scenes as usual, stamped at the save's `t`: they happened before
  the time away. The writeback is one more `rev`.
- **Then the catch-up** (v6; IDLE §4, `scripts/sim/catchup.gd`): the time away is now (`clock_override`
  when set, §1.5) less the file's `saved_at`, in whole seconds. It is 0 when that is negative or the file
  has no `saved_at`, and at most `idle.catchup_max_s` (7 days), with `capped` true when it was more. That
  much sim time runs through the core step (§3 steps 1–8) in adaptive steps: `clamp(away /
  idle.catchup_max_steps, sim.substep_s, idle.catchup_dt_max_s)`, with `idle.catchup_dt_long_s` (15 s)
  for the cap past the first `idle.catchup_dt_long_after_s` (12 h), shortened so that none straddles a
  clip event (IDLE §4 Method). `idle.field_steps` field steps (api-request #14) run in place of the field's
  live ticks, and the field ends published. The run's events are kept for the away report, not queued
  (§6). The lanes' callouts take the net change once at its end. A 0 s load is the identity: no step
  runs and the state is the save.
- **`chunked`** (v6, an optional parameter): left out (false), the catch-up runs before `cmd_load`
  returns. True: it returns at once with the catch-up pending (`view_catchup().active`), and each
  `tick()` runs one chunk of it (§3). Meanwhile every command refuses with `catching_up` (§4). The step
  sequence depends only on the save, the time away and the configs, so the result is the same either way,
  to the bit.
- `rev` rises by 1, plus 1 for a pending retreat's writeback (v6, T3.3c), plus 1 per catch-up core step.
```gdscript
Game.state.cmd_load("auto")  # -> {ok: true, reason: "", away_s: 28800.0, capped: false}
Game.state.cmd_load("nope")  # -> {ok: false, reason: "no_save", away_s: 0.0, capped: false}
```

**`cmd_dismiss_away()` · E2b-2** (api_version 6, T3.3c; api-request #7 d, IDLE §7)
- **Extras:** none.
- **Reasons:** `catching_up` only (§4).
- **Effect:** the away report is dismissed: `view_away().shown` becomes false. Its lines stay readable until
  a new game, a load or the next report replaces them. With no report it changes nothing but `rev` (+1, a
  successful command). The map calls it from DISMISS and from acting on a ready line (`AwayLogic.dismiss`).
```gdscript
Game.state.cmd_dismiss_away()  # -> {ok: true, reason: ""}
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
- `unique` (`cmd_build` only: a `unique` building, the Crypt, already stands on a lot, finished or
  under construction; added at `api_version` 3);
- `lot_locked` (the current tier doesn't open the lot);
- `lot_taken`, `lot_too_small`, `empty_lot`, `under_construction`;
- `needs_tier`, `needs_blueprint`, `needs_building`;
- `no_gold`, `no_bone`, `no_relics`.

Live from E2a (T2.4). The town's tier rises when its requirements hold (§5.9; `tier_up`), and the
tier opens lots: the id lists are `economy.json` `town.tiers.<tier>.lot_ids` (BALANCE §5; `.lots` is the count), Hamlet being
`lot-01`..`lot-08`. A building that defines the next tier is buildable one tier before it (Walls and
the Chapel of Vats at Village, the Reliquary, with its blueprint, at Town; MECHANICS §4.4). A
construction costs its `cost` (a build) or `level_costs[level - 2]` (an upgrade to `level`), paid
at once from TownSim's gold and bone and from the relics; the `build` job advances it. A cancel
refunds that cost in full. `api_version` 2 added `unpaid` to `cmd_upgrade`; `api_version` 3 added
`unique` to `cmd_build`.

**`cmd_build(building_id: String, lot_id: String)` · E2**
- **Extras:** `cost: {gold: float, bone: float, relics: int}`.
- **Reasons:** `unknown_building`, `unknown_lot`, `unique`, `lot_locked`, `lot_taken`, `lot_too_small`,
  `needs_tier`, `needs_blueprint`, `needs_building`, `no_gold`, `no_bone`, `no_relics`.
- `unique`: `buildings.json` marks a building `"unique": true` (only the Crypt), and one already
  stands on some lot, built or under construction. Without it a second Crypt would cost nothing
  and add its level to the big-undead cap.
- **Effect:** pays the cost at once and starts construction, which the `build` job advances by
  `build_work`. Emits `building_started`, and `building_done` when finished.
```gdscript
Game.state.cmd_build("house", "lot-05")  # -> {ok: true, reason: "", cost: {gold: 40.0, bone: 10.0, relics: 0}}
Game.state.cmd_build("inn", "lot-06")    # -> {ok: false, reason: "needs_tier", cost: {}}
```

**`cmd_upgrade(lot_id: String)` · E2**
- **Extras:** `level: int` (the target level), `cost: {gold, bone, relics}` from `level_costs`.
- **Reasons:** `unknown_lot`, `empty_lot`, `under_construction`, `unpaid` (an unpaid building can't
  upgrade; added at `api_version` 2; from v8, also a building Thrift idles), `max_level`, `needs_tier` (the building's own tier, which only
  a placed building can lack), `no_gold`, `no_bone`, `no_relics`.
- **Effect:** pays, then runs construction like a build. The building keeps working at its old
  level (slots, output, upkeep and effects) until the upgrade is done; `view_town` shows it
  `constructing` meanwhile, with its old `level`.
```gdscript
Game.state.cmd_upgrade("lot-04")  # -> {ok: true, reason: "", level: 2, cost: {gold: 15.0, bone: 130.0, relics: 0}}
```

**`cmd_demolish(lot_id: String)` · E2**
- **Reasons:** `unknown_lot`, `empty_lot`, `under_construction` (use `cmd_cancel_build`),
  `protected` (the Crypt).
- **Effect:** frees the lot with no refund (its staff cap goes too). A foreman placed there returns
  to the crypt. `protected` is any Crypt.
```gdscript
Game.state.cmd_demolish("lot-03")  # -> {ok: true, reason: ""}
```

**`cmd_cancel_build(lot_id: String)` · E2**
- **Extras:** `refund: {gold, bone, relics}`.
- **Reasons:** `unknown_lot`, `not_building`.
- **Effect:**
  - Refunds the full cost (`refund` shows what came back; relics are clamped to the cap).
  - A cancelled new build frees the lot (a foreman there returns to the crypt) and drops its
    `building_started` if no substep has emitted it yet. A cancelled upgrade keeps the old level,
    still working.
```gdscript
Game.state.cmd_cancel_build("lot-05")  # -> {ok: true, reason: "", refund: {gold: 40.0, bone: 10.0, relics: 0}}
```

**`cmd_queue_build(building_id: String, lot_id: String)` · E2b-2 (api_version 6, api-request #3; IDLE §5)**
- **Args:** a building id and a lot; `building_id == ""` queues an upgrade of the building on `lot_id`
  (built or under construction), or of the first new build queued for it.
- **Extras:** `index: int` (the entry's position; −1 on a refusal), `cap_building: String`, `store:
  String` and `cap_level: int`. With `cost_exceeds_cap`: `store` is the store whose cap the cost is over
  (`gold`, `bone` or `relics`), `cap_building` the building whose `*_cap` effect raises it (the first in
  `buildings.json`), and `cap_level` the lowest level of that building whose cap covers the price: the
  cap now with its highest-level copy raised to that level, or with one built at it (so `1` when it isn't
  built yet), `-1` when no level covers it. Otherwise `""`, `""` and `-1`. From v7 (R2) `affordable_in_s:
  float`: the new entry's `affordable_in_s` as `view_town().queue` shows it (§5.9), so the player learns at
  queue time that it will wait, or never be afforded at the current income (`-1.0`); `-1.0` on a refusal (no entry).
- **Reasons**, in check order: only what waiting can never make valid. `queue_full` (`queue.max_len`,
  8), `unknown_building`, `unknown_lot`, `unique` (one stands, is under construction or is queued),
  `lot_taken` (a building stands or is under construction there: queued entries don't claim lots),
  `lot_too_small`; for an upgrade `empty_lot` (nothing stands or is queued there) and `max_level` (the
  level it would build, below, is past `max_level`); `cost_exceeds_cap` (its gold, bone or relic cost is
  above that store's cap now).
- **Accepted as gates** (the run's manager, 2026-11-14: IDLE §5 over this request's first wording; the
  town adapts its UI in Phase I): `needs_tier`, `needs_blueprint`, `needs_building`, `lot_locked`, a
  relic shortfall (`no_relics`), and for an upgrade `under_construction` and `unpaid`. The entry shows
  `skipped_gate` with that reason and starts when the gate clears. Affordability (gold, bone) never
  refuses: it holds the queue.
- **The upkeep gate** (v10, E4 step 4, the run's manager's E4 ruling (3)): a new building whose gold upkeep
  would take net gold negative is `skipped_gate` with reason `upkeep`. Net gold is the stalls' income now
  (today's staffing and living, from state) less the gold upkeep of every building on its lots (working,
  unpaid, Thrift-idled or under construction, and the entries the same walk starts ahead of it) and its own.
  It waits unless the income beats that bill by more than `upkeep.resume_net_min` + 1e-9 g/s, the resume rule's
  margin (MECHANICS §4.3), so a net of exactly 0 waits (text and rule only; no key change).
  A building with stall jobs (the Market) is exempt, as is one with no gold upkeep; an upgrade adds no upkeep
  (it is flat per building), so it is never held. The entries behind it still start, so a Market level
  queued after it can pay for it. `view_away` names the first such entry (§5.19).
- **Effect:** appends `{building_id, lot_id, upgrade, waited_on}` and bumps `rev`. The core step processes
  the queue (§3, step 3; MECHANICS §4.4).
```gdscript
Game.state.cmd_queue_build("house", "lot-06")      # -> {ok: true, reason: "", index: 0, cap_building: "", store: "", cap_level: -1, affordable_in_s: 0.0}
Game.state.cmd_queue_build("", "lot-02")           # the pit's level 2 -> {ok: true, reason: "", index: 1, ...}
Game.state.cmd_queue_build("reliquary", "lot-23")  # no mill yet -> {ok: false, reason: "cost_exceeds_cap", index: -1, cap_building: "bone_mill", store: "bone", cap_level: 1, affordable_in_s: -1.0}
# day1 a step in, a House, a Well and a Bakery queued: its Bone Mill (60 gold, no bone) waits on gold behind the Bakery
Game.state.cmd_queue_build("bone_mill", "lot-08")  # -> {ok: true, reason: "", index: 3, ..., affordable_in_s: 475.7}
# day1 with its bone spent and no mill: only a mill makes bone, so a House can't be afforded at the current income
Game.state.cmd_queue_build("house", "lot-05")      # -> {ok: true, reason: "", index: 0, ..., affordable_in_s: -1.0}
```

**`cmd_unqueue(index: int)` · E2b-2 (v6, #3)**
- **Reasons:** `unknown_index` (not 0..size − 1). **Effect:** removes the entry; `rev` + 1.

**`cmd_reorder_queue(order: Array)` · E2b-2 (v6, #3)**
- **Args:** `order[k]` is the old index that moves to position k: a permutation of the current indices
  (ints, or floats that are whole numbers).
- **Reasons:** `bad_order` (not such a permutation). **Effect:** reorders; levels and costs are recomputed
  from the new order on the next walk; `rev` + 1.
```gdscript
Game.state.cmd_reorder_queue([1, 0])  # -> {ok: true, reason: ""}
Game.state.cmd_unqueue(3)             # -> {ok: false, reason: "unknown_index"}
```

**`cmd_set_job_priority(order: Array)` · E1/E2**
- **Args:** a permutation of `JOB_IDS`, top first.
- **Extras:** `order: Array[String]`.
- **Reasons:** `unknown_job`, `duplicate_job`, `missing_job`.
- **Effect (E2a):** TownSim's workers refill the job slots in this order at once.
  `view_staffing_projection(order)` (§5.16) shows the staffing it would give before you send it, and
  refuses an `order` with the same reasons.
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
  are `suspended`, not switched off. They resume when a slot returns. (v8, E3-1) The stances acting take
  effect at once: one turned on whose condition is `active` acts now (its job lifted, Muster's idle cap, Thrift
  idling its buildings), one turned off stops now; `active` itself changes only at a beat (§3 step 1). A slot
  that goes or comes otherwise (Relish leaves or comes home, the Guildhall) moves the effects from the next core
  step.
```gdscript
Game.state.cmd_set_stance("harvest", true)  # -> {ok: true, reason: "", slots: 3, used: 1}
```

**`cmd_raise_big_undead(husk_uid: String, remnant_uids: Array, name: String)` · E2** (the town
unit's SlabLogic; live from E3-3, v8)
- **Extras:** `big_undead: Dictionary`, shaped like a `view_big_undead` entry (§5.12).
- **Reasons**, in this order: `not_home` (Relish isn't `home`), `unknown_husk`, `unknown_remnant`,
  `duplicate_remnant`, `invalid_recipe` (`SlabLogic.evaluate(the husk's kind, the remnants in the
  order given, town.json slab)` returns `ok` false: an unknown kind, a remnant no slot takes, or fewer
  than `slab.min_remnants` placed), `at_cap` (as many big undead as `view_big_undead().cap`:
  `big_undead.cap` plus `per_crypt_level` per Crypt level above 1), `bad_name` (empty or over 24
  characters after `strip_edges`).
- **Effect:** consumes the husk and exactly those remnants, mints `u<n>` from the save's uid counter
  and stores `{uid, name (stripped), kind (the husk's), role (SlabLogic's role id), stats
  (SlabLogic's), place: "crypt", front: "", filled_slots (SlabLogic's filled)}`. `rev` +1. No event.
```gdscript
Game.state.cmd_raise_big_undead("h1", ["r2", "r3"], "Old Gristle")
# -> {ok: true, reason: "", big_undead: {uid: "u4", name: "Old Gristle", kind: "hulk", role: "bulwark",
#     stats: {power: 2.0, beef: 3.0, wits: 0.0, presence: 0.0, speed: 0.0}, place: "crypt", front: "", filled_slots: 2}}
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
  - `"fort:<fort_id>"`: siege, which blocks `tithe.siege_block` of a tithe wave there (from E3-3; no kill power);
  - `"crypt"`.
- **Extras:** `place: String`.
- **Reasons:**
  - `unknown_uid`;
  - `busy` (the uid is in an open run's party);
  - `bad_place`, `unknown_lot`, `empty_lot`;
  - `foreman_taken` (one foreman per lot);
  - `unknown_fort`.
- **Effect:** removes it from the party, if it was in it. The place is recorded. From E3-3 (v8) a foreman
  works its building (MECHANICS §4.2: its job output × `foreman.mult + speed · foreman.speed_k`, its presence on
  morale; it adds no `q`), and a place where it gives nothing (a passive building, one not `active`) is still
  allowed. From E3-3 a siege blocks `tithe.siege_block` (0.6) of a tithe wave at its fort (§3 step 5 here,
  MECHANICS §3.4): flat, one per fort, so a second siege there is allowed and adds nothing. It adds no kill power
  (not built).
```gdscript
Game.state.cmd_place_big_undead("u4", "town:lot-04")  # -> {ok: true, reason: "", place: "town:lot-04"}
```

**`cmd_craft(item_id: String)` · E3 (live from E3-4, v8)**
- **Args:** one of `CRAFT_IDS`.
- **Extras:** `count: int` (the new stock: simulacra ready, or phylactery charges).
- **Reasons**, checked in this order: `unknown_item`; `needs_building` (the built buildings' `craft_slots` sum to under
  1: no Ossuary Tower past its first build. A capacity effect, so an unpaid or Thrift-idled one still crafts. A level
  above 1 adds nothing more in E3); `no_essence`; `no_relics`.
- **Effect:** instant. It takes `economy.json` `craft.<item_id>`'s costs, a simulacrum 20 essence and 1 relic and a
  phylactery charge 15 essence, and adds 1 to that stock (`view_inventory().simulacra_ready`, or the phylactery charges
  E3-2's death rule spends, MECHANICS §7); a simulacrum also counts in `stats.sims_built` (§9.1). Neither stock has a
  cap of its own (the essence and relic caps bind them; `phylactery.max_per_dungeon` limits the revives a run may use,
  not the stock). No event; no uid (both are counts). It is allowed while a run is open (§9.1 Open runs).
```gdscript
Game.state.cmd_craft("phylactery_charge")  # -> {ok: true, reason: "", count: 1}
```

**`cmd_craft_husk(kind: String)` · E4 (v9; lever (b), the E4 sizing stop's ruling 2)**
- **Args:** one of the t1 chest's husk kinds, `loot.json` `chest_by_tier["1"].husk_kinds` (`view_catalog().husk_craft.kinds`;
  shipped: `skeleton`, `zombie`).
- **Extras:** `husk: Dictionary`, the husk made, as `view_inventory().husks` lists it: `{uid: String, kind: String,
  rarity: String}` (`{}` on a refusal).
- **Reasons**, checked in this order: `unknown_kind`; `no_remnants` (fewer than `economy.json` `craft.husk.remnants`);
  `no_bone` (the bone store under `craft.husk.bone`); `at_cap` (v10: the crypt has no room for it, its big undead
  plus the husks waiting at the `big_undead` cap, the cap `cmd_raise_big_undead`'s own `at_cap` reads; a husk that
  can't be raised would sit waiting).
- **Effect:** instant. It takes the `craft.husk.remnants` weakest remnants (the smallest `magnitude` first, then the
  oldest uid) and `craft.husk.bone` bone (shipped 6 and 300, GUESS: slow and costly, the bone competing with the build
  queue; a new game's 200 bone cap is under it until the Bone Mill raises the cap), and adds `{uid: h<n> from the
  save's uid counter, kind, rarity: "common"}` to the husks, as a raid's loot does. No building, and Relish needn't be
  home (raising the husk at the slab needs her, §4.3 `cmd_raise_big_undead`). Neither bone nor remnants are mass, so the
  ledger books nothing. No event. **Phase I (town):** a button at the crypt slab, its price and reason from
  `view_catalog().husk_craft`.
```gdscript
Game.state.cmd_craft_husk("skeleton")  # -> {ok: true, reason: "", husk: {uid: "h41", kind: "skeleton", rarity: "common"}}
```

**`cmd_deploy_simulacrum(fort_id: String)` · E3 (live from E3-4, v8)**
- **Extras:** `charges: float` (the planted simulacrum's charges, in mass), `ready_left: int` (the simulacra still
  ready).
- **Reasons**, in this order: `unknown_fort`, `none_ready` (`simulacra_ready` is under 1). There are no others.
- **Effect:** it takes one from `simulacra_ready` and plants `{fort_id, charges: simulacrum.charges, rate:
  simulacrum.rate}` (`realm.json`: 300 mass, 1.0 mass/s) at that fort, held or not. From the next step it redirects
  there at `rate` until its charges run out (MECHANICS §3.6): the garrison's kills there stay as corpses and it raises
  corpses into the fort's undead; charges are mass, only the raise spends them, and at 0 it crumbles. Several at one
  fort stack (`view_fort().simulacrum_charges` sums them) and raise side by side. A retake of the fort loses it
  (MECHANICS §3.4; IDLE I6). No event.
```gdscript
Game.state.cmd_deploy_simulacrum("vespers")  # -> {ok: true, reason: "", charges: 300.0, ready_left: 0}
```

**`cmd_staff_vat(slot: int, on: bool)` · E1/E3**
- **Args:** `slot` is 0..`vat_slots - 1`.
- **Extras:** `staffed: bool`.
- **Reasons:** `unknown_slot`.
- A clone grows only while its vat is staffed and tended (v8, E3-2; MECHANICS §7): at `vats.grow_per_s` × the vat's
  tend hands (0..1), the Chapel's tend hands going to its staffed vats in slot order. Unstaffed, a vat keeps its `grow`.
- **Effect (E2b-2, api_version 5): a staffed vat takes a hand** (MECHANICS §7). A Chapel of Vats
  offers one tend slot per vat, open only while that vat is staffed. `true` opens the vat's slot at
  once and the ladder fills it like any other room (an idle worker if there is one, else the lowest
  room staffed below it gives its hand); `false` closes it and gives the hand back to the ladder's
  next room, or to the idle pool. Vats are numbered as `view_backups.vats`: in lot order over every
  built Chapel, then by vat within it. `view_town().jobs` and the Chapel's `slots` count only the
  open tend slots. `view_staffing_projection(order, {slot: on})` (§5.16) shows the move first.
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
- **Effect:** records the front. From E3-5 (v8) the member counts its stat there (`view_vei().fronts`, §5.14); unassigned,
  it counts on the front of its highest stat.
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

**`cmd_begin_boss()` · E1** (fronts live from E3-5, v8)
- **Extras:** `seed: Dictionary` (§7.2), `run_id: int`, `seed_rev: int`.
- **Reasons:** `busy`, `dead`, `not_at_vei` (she must stand at Vei's node, state `at_vei`).
- **Effect:** opens the run, sets Relish to `in_boss`, and forces `time_scale = 1` and
  `paused = false`.
```gdscript
Game.state.cmd_begin_boss()  # -> {ok: true, reason: "", run_id: 9, seed_rev: 21950, seed: {v: 2, kind: "boss", ...}}
```

**`cmd_abort_dungeon()` · E1**
- **Extras:** `run_id: int` (the run forfeited).
- **Reasons:** `no_run`, then `catching_up` (v6, E2b-2 T3.3c: a dead run's refusal comes first, §4; no
  run is open during a catch-up, so during one it answers `no_run`).
- **Effect:** forfeits the open run, dungeon or boss.
  - There is no writeback, no loot and no flip, and the party is intact.
  - Relish goes back to `at_fort` (or `at_vei`), and the run is closed, so a later result for it is
    `wrong_run`.
```gdscript
Game.state.cmd_abort_dungeon()  # -> {ok: true, reason: "", run_id: 1}
```

**`cmd_run_checkpoint(run_id: int, loot: Dictionary, outcome := "retreated")` · E2b-2** (api_version 6,
T3.3c; api-request #4, IDLE I5)
- **Args:** `run_id` the open raid's; `loot` the raid result's `loot` shape (§8.1: `{relics, blueprints,
  husks: [{kind}], remnants: [{aspect, rarity, magnitude}], essence}`), what is banked so far; `outcome`
  the exit the run would end in if it ended now: `"retreated"`, `"warden_beaten"` or `"relish_died"`.
- **Extras:** none (`{ok, reason}`).
- **Reasons**, in check order: `no_run` (no run is open), `wrong_run` (`run_id` isn't the open run),
  `wrong_kind` (the open run is a boss run: a boss result carries no loot, §8.2, so there is nothing to
  bank), `catching_up`, `invalid` (`Results.validate("raid", …)` rejects a retreat result carrying `loot`),
  `bad_outcome`. A dead run's refusals come before `catching_up` (§4): no run is open during a catch-up.
- **Effect:** the open raid records `{loot, outcome}` (a deep copy, ints as ints), **replacing its last
  checkpoint**; `rev` +1. Nothing else changes and no event is raised. **A checkpoint is only as good as
  its last call** (the run's manager): a close, a crash, a load or a gap ends the run from the last one,
  and whatever was found since is lost (the same bound as a death, MECHANICS §7).
- **When the dungeon calls it** (the dungeon, Phase I; `raid_endings.gd` already calls it when it exists):
  - at every room clear (each checkpoint room it banks), with the loot banked so far and `"retreated"`;
  - at the warden's victory beat (warden beaten, chest open), with the loot including the chest and
    `"warden_beaten"`;
  - at the death beat, with the loot the death keeps and `"relish_died"`.
- **How a run ends from it** (IDLE I5; `StateRuns.end_open`): through the normal writeback (§8.3), as the
  raid result `{outcome as the exit, loot as the banked loot, killed_living_mass 0, raised [], chaff_mass
  0, garrison_mass = the seed's garrison_in_mass (so the fort's undead don't move), revived_in_place 0,
  party_lost []}`:
  - `"retreated"`: the loot is banked, no flip, Relish `at_fort`;
  - `"warden_beaten"`: the flip and the loot, as if the scene had sent the win;
  - `"relish_died"`: a death, as `apply_result` treats one (§8.3 step 10: the whole party lost, a clone or
    unmade);
  - with no checkpoint, empty loot and `"retreated"`: nothing banked, as before T3.3c;
  - its kills aren't known, so an ended run never clears a counter-garrison (`counter_garrison_cleared`
    isn't raised and the yield isn't spent), and its phylactery revives and party losses aren't known
    either (none are applied);
  - its id joins `applied_runs`, so a late result for it is `duplicate_run`;
  - **a load (or gap) that ends a run with no checkpoint** (the save's `pending_retreat` is empty loot and
    `"retreated"`) is still a writeback, so it has its side effects: `stats.raids` goes up by 1, the run's id
    joins `applied_runs`, and `loot_banked` is emitted with zero loot (no relics, essence, blueprints or
    minted uids), `rev` rises by 1, and Relish is `at_fort`. Nothing else moves (no kill, no flip);
  - **a `relish_died` checkpoint** applies `StateRuns.death` at the end: a ready clone is spent
    (`clones_ready` −1) or she is unmade, by `clones_ready` as it stands when the end is applied, not as the
    scene saw it at the death beat (the seed's `death_ends`). Since E3-2 (v8) the vats grow clones, so
    `clones_ready` can rise between the beat and the end (a vat filling meanwhile) and the outcome follows it: a
    death the scene saw as unmade can end as a clone. The in-run phylactery revives are not applied (`revived_in_place` 0), so
    `phylactery_charges` is not spent for them either.
- **A boss run** has no checkpoint; an ended boss run is forfeited as `cmd_abort_dungeon` forfeits it (no
  writeback, the party intact, Relish `at_vei`, its id not an applied run: a late result is `wrong_run`).
- **A dead run** (ended by a load or a gap) gets clean refusals from every run command and nothing
  changes: `cmd_run_checkpoint` and `cmd_abort_dungeon` say `no_run`, `apply_result` `duplicate_run` (a
  raid) or `wrong_run` (a boss run), during a catch-up too (§4). A gap's `run_ended` tells the dungeon
  scene to leave (Phase I wires it).
```gdscript
Game.state.cmd_run_checkpoint(1, {"relics": 1, "blueprints": [], "husks": [{"kind": "hulk"}], "remnants": [], "essence": 9})
# -> {ok: true, reason: ""}
Game.state.cmd_run_checkpoint(1, loot, "warden_beaten")  # the warden's victory beat
Game.state.cmd_run_checkpoint(9, loot)  # the open run is a boss run -> {ok: false, reason: "wrong_kind"}
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
  | `duplicate_run` | `run_id` was already applied. Idempotent: a repeat changes nothing. A raid run a load or a gap ended (v6, T3.3c) is an applied run. |
  | `wrong_run` | no run is open, or `run_id` isn't the open run (including a forfeited one, and a boss run a load or a gap ended, v6) |
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
- The mass a grant applies (`bodies`, `workers` × `worker.mass`, `backlog`) books to
  `ledger().sources.debug`, a removal as a negative amount; so does `cmd_debug_set_state`'s `forts`
  (§4.7).
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

### 4.7 `ledger() -> Dictionary` · E2 (for tests; live from E2a T2.5)
- Returns `{sources: Dictionary, sinks: Dictionary, held: Dictionary, stores: Dictionary}`. `sources`,
  `sinks` and `held` are each `String → float` mass. `sources` and `sinks` are totals since the new game,
  booked where mass enters or leaves the world (`scripts/sim/ledger.gd`, preloaded as
  `GameState.Ledger`); `held` is summed from the live state at the call. A fresh copy, like a view.
- `stores` (v6, E2b-2 T3.2) is the currency tally beside the mass, outside the invariant (gold and bone
  are not mass): `{gold: {overflow: float}, bone: {overflow: float}}`, the income each store's cap
  clipped since the new game (MECHANICS §4.3; IDLE §6's "overflow is a ledger sink"). Saved with the
  ledger (§9.1); a save without it loads 0. The currency soak checks `gold_end = gold_start + Σtrade −
  Σupkeep − Σspent − stores.gold.overflow` (and bone with the mill) within 1e-9. T3.3's away report reads
  it for "store overflow" among the losses.
- **Invariant:** `Σheld + Σsinks == Σsources` within 1e-6 relative (`|miss| / max(1, Σsources)`) at
  every substep boundary and at any `sim.substep_s` (catch-up, IDLE §4). Measured misses are about
  1e-14.
- **Keys** in this order; the ones marked "+3" were added at `api_version` 3:

| section | key | what books it |
|---|---|---|
| `sources` | `mint` | the pits' production, `mint · dt` each substep (§3 step 3). The only true flow in. |
| | `debug` | net mass the debug commands added: `cmd_debug_grant`'s `bodies`, `workers` (× `worker.mass`) and `backlog`, and `cmd_debug_set_state`'s `forts`. What was applied after clamping; a removal books a negative amount. |
| | `opening` (+3) | not a flow: the mass on the board when the count began. `cmd_new_game` sets it to Σheld (the forts' garrisons and the opening workers and bodies). A save without it (written before `api_version` 3) loads with its `sinks.dungeon` kept, every other total 0, and `opening = Σheld + dungeon`. |
| `sinks` | `cleared` | `k_clear`: garrisons clearing corpses (RealmSim) |
| | `rot_loss` | rotted workers' mass that never returns: `rot · worker.mass · (1 − body_return)` |
| | `burned`, `milled` | pit burn and milling (bone is not mass) |
| | `vei_fight` | a lost Vei fight: `(1 − loss_backlog_keep)` of the backlog (§8.3) |
| | `dungeon` | the raid writeback's loss (§8.3 step 7) |
| | `pool_overflow` | what the march-back took past Vei's pool cap (`vei_pool_cap`): living above a fort's cap march back at `(L − cap) / tithe.march_back_s`, and whatever would take her pool past the cap books here; she then converts into the headroom left. Not always 0 since the march-back (v4: the meaning changed, not the shape) |
| | `rot_overflow` (+3) | rot return lost to the body cap (MECHANICS §4.1) |
| | `haul_overflow` (+3) | a landing convoy's load lost to the body cap |
| | `store_overflow` (+3) | always 0: the store caps (E2b-2 T3.2) clip gold and bone, which are not mass; their overflow is `stores` (above) |
| `held` | `fort_living`, `fort_undead`, `corpses` | Σ forts' `living`, `undead`, `dead` |
| | `backlog`, `vei_dead`, `living_pool` | Vei's undead queue, dead queue and living pool |
| | `bodies` | Covington's body store |
| | `workers` | the workforce in mass: `workers · worker.mass` |
| | `convoys` | the load of a convoy on its way home |
| | `work_pending` (+3) | WORK in flight to TownSim: 0 at every substep boundary from E2b (TownSim takes each step's WORK in that step, §3 step 3). Only a save written before that can hold some, which the next step delivers. |

- **Internal transfers book nothing:** the valve split, WORK into workers, muster into WAR, haul
  pickups, combat, drain, Vei's conversion (dead and undead into living) and her shipping, tithe
  surges, the redirect and simulacra raises, and the raid writeback's kills, flip and chaff.
- Not mass, so not in the ledger: gold, bone, Covington's living (people), relics, essence, items.
- The totals are saved (§9.1 `ledger`) and survive a load to the 15 digits a save keeps.

## 5. Views

Every view returns a deep copy with `rev: int` first (§1.3). A view of an unknown id returns `{}`.
Types are exact. "mass" means a float in mass units.

### 5.1 `view_hud()` · E2
Every field is live from E2a:
- `sign`, `drain_s` and `odds` are the sustained readout (§5.14);
- `split` is the last substep's mass/s, after the slew (WAR includes TownSim's muster), and the
  `mint` entry's `rate` is that substep's mint (MECHANICS §3.2): `view_rates`' `work`, `war`, `flood`
  and `mint` `in`;
- the `workers`, `bodies`, `gold`, `bone` and `living` entries are TownSim's: the same stocks and
  caps `view_town` shows, and the net rates of `view_rates` (bodies count the haul trip-averaged);
- `workers_steady` is TownSim's last inflow × the lifetime now, as `view_town.workers.steady`. It
  ignores the idle cap, so it reads far above the town (88 on day 1 while the town sits at 17-19);
  `workers_steady_kept` is where the workforce actually settles (see `view_town.workers`, §5.9);
- `war_overflow` is the WAR that fell through to Vei because every WAR target was capped (MECHANICS
  §3.2). It is the `war:covington:vei` lane's rate in `view_lanes` (§5.3).
- `war_supports` (v6, api-request #7 b): "WAR supports N of M held forts". `m` is the held forts,
  `n` those whose `garrison_rate` (§5.5) is ≥ 0 at the current valve.

| key | type | meaning |
|---|---|---|
| `t` | float | sim seconds since the new game |
| `time_scale` | float | |
| `paused` | bool | |
| `rates` | Array[Dictionary] | one per `HUD_RATE_IDS`, in order: `{id: String, rate: float, stock: float, cap: float, unit: String}`. `rate` is the signed net per sim-second; for `mint` it is production (≥ 0). `stock` is `-1.0` for mint; `cap` is `-1.0` when uncapped. |
| `split` | Dictionary | `{work, war, flood}`: mass/s now, after the slew; `war` includes muster (`muster_mass / dt`) |
| `valve`, `valve_target` | Dictionary | `{work, war, flood}` fractions summing to 1 |
| `workers_steady` | float | workers: `(work / worker.mass) · lifetime`; no cap |
| `workers_steady_kept` | float | workers: the workforce TownSim's ODE settles at for the current inflow, lifetime, idle rot, staffable slots and idle cap; same as `view_town.workers.steady_kept` (v4) |
| `game_id` | String | a stable identity for one game: fresh per new game, kept across its saves and loads (api-request #18). Derived from the seed, never from the rng: `"%08x" % (seed & 0xffffffff)`, 8 hex digits (`SaveIO.game_id_for`). Two games with the same seed share an id (only tests and fixtures do that). Fixtures carry none and compute it at load. |
| `war_overflow` | float | mass/s: the last substep's WAR that fell through to Vei (`view_lanes` `war:covington:vei`); 0 while a WAR target has room (v4) |
| `war_supports` | Dictionary | `{n: int, m: int}`: `m` held forts, `n` of them with `garrison_rate` ≥ 0 at the current valve (v6) |
| `relics`, `relics_cap`, `essence`, `essence_cap` | int | |
| `sign` | int | sustained-differential sign: `1` = ▲ (backlog growing), `-1` = ▼, `0` = holding |
| `drain_s` | float | `backlog / -EMA` when the EMA < 0, else `-1.0` (holding) |
| `odds` | float | `backlog / (backlog + K)`, 0..1 |
| `won` | bool | |
```gdscript
{rev: 3, game_id: "0000002a", t: 1.0, time_scale: 1.0, paused: false,
 rates: [{id: "mint", rate: 12.8, stock: -1.0, cap: -1.0, unit: "mass/s"},
         {id: "workers", rate: 0.103, stock: 12.0, cap: -1.0, unit: "workers/s"},
         {id: "bodies", rate: -0.35, stock: 40.0, cap: 200.0, unit: "mass/s"},
         {id: "gold", rate: 0.21, stock: 80.0, cap: 9750.0, unit: "gold/s"},
         {id: "bone", rate: 0.0, stock: 30.0, cap: 200.0, unit: "bone/s"},
         {id: "living", rate: 0.012, stock: 10.0, cap: 16.0, unit: "living/s"}],
 split: {work: 5.12, war: 5.76, flood: 1.92},
 valve: {work: 0.4, war: 0.45, flood: 0.15}, valve_target: {work: 0.4, war: 0.45, flood: 0.15},
 workers_steady: 61.4, workers_steady_kept: 18.2, war_overflow: 0.0, war_supports: {n: 0, m: 0},
 relics: 0, relics_cap: 12, essence: 0, essence_cap: 60,
 sign: 0, drain_s: -1.0, odds: 0.0, won: false}
```

### 5.2 `view_rates()` · E2
`{rev: int, rates: {<id>: {in: float, out: float, net: float, unit: String}}}`, with one key for
each of `GameState.RATE_IDS`.
- Rates are the last substep's flows divided by `sim.substep_s`.
- Lumps are not rates: build costs, dungeon writebacks and debug grants.
- Haul shows as its trip-averaged rate: the last landed trip's load over its round trip, while a
  convoy is out (0 while none is). It is the same number in `corpses.out` and `bodies.in`.
- **Every id is live from E2a (T2.5).** `mint`, `work`, `war`, `flood`, `corpses` and `backlog` are
  the last substep's (session-only, §9.1: 0 after a load until the first substep, except the haul's
  part of `corpses.out`); `workers`, `bodies`, `gold`, `bone` and `living` are TownSim's last step
  (saved with it). `view_hud.rates` reads the same numbers (§5.1).
- `workers.in` is TownSim's inflow, which takes **this** substep's WORK (§3 step 3): it equals
  `work.in / worker.mass`. (From E2b the mint trails TownSim's feed by one substep instead.)
- `corpses`: the garrisons' own kills (destroyed undead) go to Vei's dead queue straight from the
  fight and never lie at the fort, so they are in neither column; where Relish or a simulacrum
  redirects, they stay as corpses and count in `in`. With no convoy out, `corpses.net` is the rate of
  change of Σ forts' `dead`, lumps aside.
- `backlog`: Relish's raises reach the queue as fort drain; her chaff (§8.3) is a lump. `net` is
  `view_vei.diff` exactly, and the backlog's rate of change, lumps aside.

| id | unit | in | out | net |
|---|---|---|---|---|
| `mint` | mass/s | pits' production | sent through the valve | 0 (a pass-through flow) |
| `work`, `war`, `flood` | mass/s | `mint · valve` share (WAR also gets muster × `worker.mass`) | delivered (= in) | 0 |
| `workers` | workers/s | `work / worker.mass` | rot + muster | in − out |
| `bodies` | mass/s | haul + rot return | pit burn + mill | in − out |
| `gold` | gold/s | trade, less what overflowed the gold cap (v6) | upkeep | in − out |
| `bone` | bone/s | mill, less what overflowed the bone cap (v6) | upkeep | in − out |
| `living` | living/s | migrants | departures | in − out |
| `corpses` | mass/s | Σ forts: your kills + redirected garrison kills | haul + Relish's and the simulacra's raises + `k_clear` (shipping to Vei never lands here; see above) | in − out |
| `backlog` | mass/s | FLOOD + fort drain + WAR that fell through to Vei | Vei's digestion | the raw `diff` |
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
# a held fort's entry (midgame_2flips a substep in: 374 s of grace, then contested; post-grace readouts.
# T3.4b: the wave train reads Relish at Greywall, where she arrives a second later, and the set doesn't
# settle by the cap. At load, before the first substep, it reads the saved flows and says "safe")
{id: "ashgate", ..., held: true, held_s_left: 0.0, grace_s_left: 374.0, garrison: 23.4,
 garrison_rate: 1.463, fall_s: -1.0, margin: "thin", margin_cause: "wave", ...}
```

### 5.5 `view_fort(id: String)` · E1
The masses, positions, `relish_here` and `can_descend` are live from E1; held, flip and tithe from
E2a. `siege` lists the big undead placed there; from E3-3 (v8) a siege blocks `tithe.siege_block` of a tithe wave
at its fort, and the margin chip credits none (`margin`, below). `simulacrum_charges` is live from E3-4 (v8): the
simulacra `cmd_deploy_simulacrum` planted there, and the margin chip credits their raise no more than a siege's
block. The threat is
still the E1 stub (`risk: "low"`) until its E2 spec; the warden and loot hint come from the
dungeon's configs (v6, below); the hold's readouts
(`garrison` to `grace_s_left`) and `yield_mult` are live from v6.

| key | type | meaning |
|---|---|---|
| `id`, `name` | String | |
| `tier` | int | 1..4 |
| `cap` | float | mass |
| `pos` | Array | `[x, y]` |
| `living`, `undead`, `dead`, `space` | float | mass; `space = max(0, cap − living − undead − dead)` |
| `war_in`, `ship_in` | float | mass/s: WAR arriving (staging included); Vei's living arriving (tithe surges included) |
| `held` | bool | flipped and not yet retaken (in grace or contested; MECHANICS §3.4) |
| `held_s_left` | float | **deprecated (v6), always 0.0**: no timer ends a hold any more. The grace is `grace_s_left` |
| `grace_s_left` | float | seconds of grace left, 0 when contested or not held (v6). While it is > 0, `margin`, `margin_cause`, `fall_s` and `garrison_rate` are the post-grace ones: what the fort will face once its grace ends, so the map can show "grace 3:40, then thin" (the margin is the train's run through the grace, which no wave reaches, T3.4b) |
| `garrison` | float | mass: your undead there while held, 0 when not held (v6, api-request #7 a) |
| `garrison_rate` | float | mass/s (v6, api-request #13; MECHANICS §3.5): the support (the WAR the current valve sends it, plus Relish's sustained raise where she redirects) less the cheaper way to hold against her reship, outside waves. ≥ 0: it holds without waves; < 0: it falls. 0 when not held. **Reads the current split** (T3.4b): the valve where it is, Relish where she stands; `war_supports` too |
| `fall_s` | float | seconds until it is retaken (v6, api-request #13): at a support, `grace_s_left` + `min(garrison, support / r_drain) / −rate` + what is left of `hold.break_s` (all of it, less the zero clock while the garrison sits at 0) while that support's rate is < 0, else −1.0. **The earlier of that clock at the current split and at the planned support** (T3.4b fix batch: the valve's target WAR and Relish where she is travelling to, the support the margin's train reads), so it errs early either way: the fort is retaken no sooner. −1.0 while neither falls, or not held. Never INF. So while the valve slews down or Relish travels away, a row can show `garrison_rate` ≥ 0 with `fall_s` ≥ 0 (and `will_fall`). Before T3.4b, `garrison / −garrison_rate` + `hold.break_s` at the current split, late for a garrison above the level its support holds (MECHANICS §3.5) |
| `margin` | String | v6 (api-request #7 a), checked in this order (T3.4b): `"will_fall"` when 0 ≤ `fall_s` ≤ `hold.safe_horizon_s` (8 h; `fall_s` the earlier of current and planned, above); else `"thin"` when the wave train breaks it (the held forts run forward together through her waves at her period, from today's state, **at the planned support**: the valve at its target, Relish where she is travelling to); else `"thin"` when it falls beyond the horizon (`garrison_rate` < 0: **the current split**); else `"thin"` when the held forts haven't settled by the train's cap (`hold.train_max_cycles`); else `"safe"` (the train settles with it unbroken); `""` when not held. So while the valve slews down or Relish travels away a row can read `thin` / `"wave"` (the planned train breaks it) beside `garrison_rate` ≥ 0. Until T3.4b, `"thin"` when one full wave would break it, and `"safe"` otherwise. **No siege is credited** (v8, E3-3; MECHANICS §3.4): the train and the one-wave probe read every fort as if unsieged, so `"safe"` means it holds without its siege, and a sieged fort may read `thin` where the siege holds it (conservative; crediting it is E4's) |
| `margin_cause` | String | v6: `"fall"` for `will_fall` (the fall clock: current or planned, the earlier) and for a `thin` that falls beyond the horizon with no wave breaking it (slow attrition at the current split; E2b-2 T3.2, MECHANICS §3.5); `"wave"` for a `thin` the waves break or haven't settled (the planned support's train); `""` for safe or not held |
| `flipped_count` | int | times flipped |
| `first_clear` | bool | never cleared, so its chest holds a guaranteed blueprint |
| `first_dungeon` | bool | carries the first-dungeon guarantee (Old Sluice at start) |
| `clears_since_retaken` | int | |
| `yield_mult` | float | the loot yield now, 0..1 (v6, live; MECHANICS §5.3): `loot.reclear_decay` per clear that paid loot (a flip, a counter-garrison clear), climbing back linearly to exactly 1 over `loot.recover_s` from the last clear; 1 after a retake. The dungeon seed's `fort.yield_mult` is the same value at issue |
| `warden` | Dictionary | `{archetype: String, name: String, tells: Array[String]}` (v6, T3.4a, api-request #5): `archetype` is `raid.json` `wardens.by_fort[id]` (`"bellringer"` for a fort it doesn't list); `name` and `tells` are that archetype's `wardens.archetypes.<id>.name` and `.tells`, the dungeon's own text (`""` and `[]` for an archetype the config doesn't list). A card shows the name and the tells (the Watchtower's "every tell" is the config's whole list today) |
| `loot_hint` | String | display text (v6, T3.4a): the first dungeon reads `loot.json` `hints.first_dungeon_hint`; any other fort reads `hints["t<tier>.<archetype>"]`, `""` when the config has no such key. The raid seed's `loot_hint` is the same string |
| `threat` | Dictionary | `{party_strength: float, garrison_strength: float, risk: "low"\|"risky"\|"deadly", risk_pct: float}`; `risk_pct` is a percentage, `0.0`..`100.0` (not a fraction), and `-1.0` without a Watchtower (always `-1.0` until the Watchtower computes it) |
| `relish_here`, `tide`, `redirect` | bool | she stands here; her tide applies (also in its dungeon); her redirect applies (not in its dungeon) |
| `simulacrum_charges` | float | mass left across simulacra planted here, summed when several are (they stack); 0 when none. Each one's charges fall by what it raises and it crumbles at 0; a retake loses them all (MECHANICS §3.6, §3.4) |
| `siege` | Array[String] | big-undead uids placed here |
| `tithe` | Dictionary | `{targeted: bool, eta_s: float, wave_active: bool}`; `eta_s` is `-1.0` when not targeted. Targeted while a warning names the fort (`eta_s`: seconds to its wave) or its wave runs (`eta_s` 0.0, `wave_active`). |
| `can_descend` | bool | `cmd_begin_dungeon(id)` would succeed now |
| `reason` | String | the reason it would return (`""`, `busy`, `dead`, `not_at_fort`) |
```gdscript
{rev: 3, id: "old-sluice", name: "Old Sluice", tier: 1, cap: 80.0, pos: [1420.0, 1305.0],
 living: 61.2, undead: 6.4, dead: 3.1, space: 9.3, war_in: 0.48, ship_in: 0.3,
 held: false, held_s_left: 0.0, grace_s_left: 0.0, garrison: 0.0, garrison_rate: 0.0, fall_s: -1.0,
 margin: "", margin_cause: "", flipped_count: 0, first_clear: true, first_dungeon: true,
 clears_since_retaken: 0, yield_mult: 1.0,
 warden: {archetype: "bellringer", name: "The Bellringer", tells: ["slams ring out on the beat, and beef soaks them", "rings faster at each third of its health"]},
 loot_hint: "a husk and a blueprint",
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
| `dominance` | float | signed field value; above `field.town_threshold` means `player`. 0.0 where the field is not finite (a field ticked far past its stable dt can hold NaN; the owner then reads `none`) |
| `migrants` | float | living/s this village adds to Covington |
```gdscript
{rev: 3, villages: [{id: "bellwether", name: "Bellwether", pos: [1680.0, 1330.0], owner: "player", dominance: 0.41, migrants: 0.012}, ...]}
```

### 5.8 `view_relish()` · E1
The dead fields and the backups are E3, live from E3-2 (v8; MECHANICS §7): a death that ends a run leaves her
`dead` at the node she died at for the outcome's `respawn_s` (`dead_s_left` counting down, `respawn_with_clone`
which it was), then `relish_respawned` puts her `home` at Covington. Until E3-2 a death respawned her at once.

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
| `returned` | Dictionary | v6 (E2b-2 T3.3c; IDLE I5): her last walk home from a retaken fort, `{fort_id: String, cause: String ("retaken"), t: float (the retake's moment)}`, or `{}` when there has been none since the new game. It keeps the last one (a later walk replaces it, nothing clears it) and is saved, so a load or a missed `relish_returned` event still tells the map. The map toasts it ("Greywall retaken — Relish is walking home") and offers to send her back (Phase I): it can tell a new one by its `t` |
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
every view. The tier is GameState's (stored; it rises in `tick` when the requirements hold, T2.4: `tier_up`),
lots come from `town.json` and are unlocked by the tier, and
`ladder_effective` is the ladder after the stances acting (v8, E3-1: the jobs they lift on top, in
`stance.priority` order, then the player's ladder; MECHANICS §4.5). Flows are TownSim's last step: 0 at a new game
until the first substep.
- `workers.lifetime_s` is the lifetime now (`worker.lifetime_s · (1 + Σ lifetime_bonus)`, ÷
  `relish.home_rot_mult` while Relish is home: 685.7 at a new game); `workers.steady` is the last
  inflow × that lifetime, with no cap (v4 keeps it as it is).
- `workers.steady_kept` (v4) is the workforce TownSim's exact workforce ODE settles at, at the
  current inflow `r`, lifetime `L`, idle rot multiplier `m`, staffable slots `S` and idle cap `C`
  (`TownSim.workforce_steady`; the inputs `steady` uses): `r·L` when `r·L ≤ S`; else `S + (r·L −
  S)/m` when that is within `S + C`; else `S + C` (the idle pool pinned at its cap). With `m = 0`
  and `r·L > S` it is `S + C`. `workers.muster_steady` is the workers/s mustered to WAR there:
  `0` unless pinned, then `r − (S + m·C)/L` (`r − S/L` at `m = 0`).
- `buildings[].output` (per second, at the current staffing; `{}` while constructing or unpaid, and
  for a building with none): a pit `{mint: P_per_pit · pits, burn: pit.burn_per_s · pits · its
  staffed share}`; stalls `{gold}` (their share of the town's sales × price); millers `{bone}`;
  haulers `{bodies}` (their share of the trip-averaged haul); smiths `{forge}` (work/s while a forge
  level is left); an inn `{living}` (its migrants/s).

| key | type | meaning |
|---|---|---|
| `tier` | String | one of `TIERS` |
| `next_tier` | Dictionary | `{tier: String, have: int, need: int, missing: Array[String]}`. `have`/`need` count buildings whose first build is done (the Crypt included); `missing` lists required building ids not yet built. The tier rises when `have >= need` and `missing` is empty. `tier` is `""` at City (`need` 0). |
| `lots` | Array[Dictionary] | `{id: String, size: int, unlocked: bool, building_id: String}` (`""` when empty). `unlocked` is the tier's lot list (BALANCE §5); a lot with a building stays listed unlocked or not. |
| `buildings` | Array[Dictionary] | one per built or building lot (below) |
| `ladder` | Array[String] | the player's job order |
| `ladder_effective` | Array[String] | the order after stances |
| `jobs` | Array[Dictionary] | in `ladder_effective` order: `{id: String, slots: int, staffed: float}` |
| `workers` | Dictionary | `{total: float, idle: float, in: float, rot: float, muster: float, steady: float, steady_kept: float, muster_steady: float, lifetime_s: float}`: workers, workers/s, sim seconds |
| `living`, `living_cap` | float | people |
| `migrants`, `departures` | float | living/s |
| `morale` | Dictionary | `{value: float, target: float, factors: Array[{id: String, delta: float}]}`. Factor ids: `base`, `amenity:<building_id>`, `foreman` (v8, E3-3: the working foremen's `foreman.presence_k · presence`, only when non-zero), `dread`, `shock`. |
| `gold`, `bone`, `bodies`, `bodies_cap` | float | stocks |
| `queue` | Array[Dictionary] | the build queue in order (v6, E2b-2 T3.2, api-request #3; MECHANICS §4.4): one entry per queued build or upgrade (below). Always present: `[]` when empty, so the town's stand-in switches itself off |
| `queue_max` | int | `economy.json` `queue.max_len` (8) |
| `gold_cap`, `bone_cap` | float | the gold and bone caps (v6, E2b-2 T3.2): `gold.cap` / `bone.cap` plus the Market's and the Bone Mill's per-level `gold_cap` / `bone_cap` (MECHANICS §4.3). A store can sit above its cap after the cap drops; it keeps the excess and earns nothing until it is under |
| `trade_rate` | float | stall sales per second (the town draws trade arcs from it) |
| `haul` | Dictionary | `{target: String ("auto" or a fort id), current: String, convoys: Array[{from: String, to: String, phase: "out"\|"back", t: float, load: float}]}`. `t` is trip progress 0..1; `load` is mass. |
| `relish_home` | bool | the slab works |

Each `queue` entry (v6). Every field but `waited_on` is derived from today's state by the walk the core
step's processing runs (MECHANICS §4.4), so a status says what the next processing does. The next step
adds income and may raise the tier before the queue runs, so a `waiting_funds` head a little short can start
in it: that is correct, not a mismatch.

| key | type | meaning |
|---|---|---|
| `building_id`, `lot_id` | String | for an upgrade, the building on (or queued for) its lot |
| `upgrade` | bool | |
| `level` | int | the level it builds: 1 for a new build; for an upgrade one above what its lot will have once every entry ahead of it for that lot, and the construction under way there, are done (two queued upgrades of a level-1 lot: 2, then 3; a reorder recomputes it) |
| `cost` | Dictionary | `{gold: float, bone: float, relics: int}`: the construction's cost at `level` (`cost`, or `level_costs[level − 2]`) |
| `work` | float | the build work its construction needs: `build_work · level` (TownSim's step 6) |
| `status` | String | `"next"` (the first entry that isn't gated, and the stocks cover it; several can be `next` in a row, each paid for in turn, and all of them start in the next step), `"waiting_funds"` (that head, short of gold or bone: it holds the queue), `"skipped_gate"` (a gate holds it; the walk goes on past it), `"queued"` (behind a waiting head, or behind an entry for its lot that hasn't started) |
| `reason` | String | `""` for `next` and `queued`; `no_gold`/`no_bone` for `waiting_funds`; for `skipped_gate` the gate: `needs_tier`, `needs_blueprint`, `needs_building`, `lot_locked`, `no_relics` (`view_catalog`'s key for a row the relics can't pay, with the same `cost.relics`, when gold and bone are covered; short of gold or bone too, the catalog says `no_gold`/`no_bone` while the queue still reads `no_relics`, a gate there), `lot_taken` (another entry or `cmd_build` took its lot first), `empty_lot` (an upgrade whose building is gone), `under_construction`, `unpaid`, `max_level`, `unique`, `lot_too_small`, `cost_exceeds_cap` (a cost now above its cap, after a cap building went) |
| `waited_on` | String | the last reason that kept it from starting (a gate, or `no_gold`/`no_bone`), `""` if it never waited; set when queued and by each step's processing, never by a view. An entry `queued` behind a head waiting on funds takes the head's `no_gold`/`no_bone`. Saved. `queue_started.waited_on` carries it (§6) |
| `affordable_in_s` | float | v7 (R2): when its funds come at today's net rates, in sim seconds from now: `0.0` when the stocks cover it now, the seconds until they do, or `-1.0` when they never will at these rates. Set by the same walk as `status` (below), so the two never disagree: a `next` entry reads `0.0` and a `waiting_funds` head never does. Never saved; a view changes nothing |

**`affordable_in_s`** (v7, R2; from the E2b-2 vision review's item 3, the run's manager's ruling for Shawn: the
queue never stalls or jumps, so the player gets the data instead, and E3's autoplayer reads it too; MECHANICS
§4.4, `BuildRules.queue_walk`):
- **The net rates** are each store's net now, income less upkeep, from TownSim's last step: below its cap, the
  net `view_rates` and the HUD show for gold and bone. At the cap those clip the income down to the upkeep and
  read 0; the time uses the income before that clip (`rates.gold.trade` or `.bone.mill`, less `.out`), since
  an entry ahead that spends the store brings the income back. Relics have no idle income (0).
- **Entries ahead start first.** The entries that aren't gated (`next`, `waiting_funds`, `queued`) start in
  queue order, each when the stocks, grown at those rates (each up to its cap) and less what the entries ahead
  paid at their own starts, cover its gold, bone and relics. So an entry never reads earlier than the one
  ahead of it, and of two gold-short entries the second reads `(cost₁ + cost₂ − gold) / net`.
- **A `skipped_gate` entry** holds nothing: its time is its own funds' at its place in that order (the UI can
  say "affordable in 4 m once Walls are up"), it pays nothing, so it moves no later entry's time, and its
  status stays.
- **`-1.0`** when its cost is above its store's cap now (`cost_exceeds_cap`); its relics are short (no idle
  income: raid for relics); a store it is short of has a net ≤ 0; a store that covers it now falls under it
  by then at a negative net; or it costs any of a store that an entry ahead holding the queue never gets
  (that entry is `-1.0`; it holds the queue, so none of that store reaches this one). A later entry that
  costs none of that store gets its time as if that entry weren't there: what it would read once the player
  moves the stuck head down.
- **Held fixed:** the rates don't change with what the entries ahead build. The upkeep a new building adds,
  or its output, isn't modelled (E4-3 decides what a build that would run a deficit does), nor a gate the
  entry meets later (a construction under way on its lot). A new game and a fixture load have no step's
  rates until the first substep, so every short entry reads `-1.0` until then.

Each `buildings` entry:

| key | type | meaning |
|---|---|---|
| `lot_id`, `building_id` | String | |
| `level` | int | 0 while the first build is under way |
| `state` | String | `"constructing"` (building or upgrading), `"active"`, `"unpaid"` (idled by unpaid upkeep), or `"idle"` (no staff, or a stance idles it: from v8, E3-1, a building the Thrift stance idles, which offers no slots, gives no output and pays no upkeep, its caps and tier count kept; the save's state `thrift`) |
| `progress` | float | 0..1 while constructing, else 1.0 |
| `slots` | int | the job slots it offers now (a Chapel of Vats: its tend slots for its staffed vats only, `cmd_staff_vat`) |
| `staffed` | float | |
| `staff_cap` | int | `-1` = none |
| `foreman` | String | big-undead uid, or `""` |
| `output` | Dictionary | `String → float` per second, e.g. `{gold: 0.3}`, `{mint: 6.0, burn: 0.6}` |
| `upkeep` | Dictionary | `{gold: float, bone: float}` per second |
| `work_left` | float | v6 (E2b-2 T3.2, api-request #17): while `constructing`, the build work still to do, `build_work · target level · (1 − progress)` (TownSim's step 6); 0.0 otherwise |
| `eta_s` | float | v6 (#17): while `constructing`, `work_left` over the lot's build rate now (`job.build.rate` × the builders staffed there as TownSim's last staffing has them), so the seconds to finish if the staffing holds; `-1.0` with no builders, and on every other state |
| `upgrade_projected` | Dictionary | v6 (E2b-2 T3.2, api-request #9): `rate_id → float` over every `RATE_IDS` id, the change in each net rate if this lot's next level were finished now and staffed by the current ladder, at today's state (§5.10's `projected`, for the next level); `{}` at `max_level` or while constructing. Display-only: refreshed late in the substep interval on frames without a substep, while the catalog is being read (§5.10, cost and caching), so it can lag a change by about 1.5 s live, stays within `town.projection_tol` of the fresh value, and reads `{}` until its first refresh, and again once the lot holds another building or level than the one it was computed for (a demolish and rebuild, a finished upgrade) until it is refreshed |
| `starved` | String | v6 (T3.4a): why this building's mills milled less than their hands want, from TownSim's last step (MECHANICS §4.3). `""` for a building with no mill slots (every one but the Bone Mill), when the staffed mills milled all they want, and when none are staffed; `"pits_first"` when they milled less because the pits had first call and took bodies, the supply short of both; `"no_bodies"` when they milled less and the pits took none either (an empty store with nothing landing, or no staffed pit). A per-step figure, never saved: `""` after a new game and after a load until the first step. The town reads it in Phase I and owns the text |
| `upgrade_work` | float | v6 (#17): the build work the next level's construction needs, `build_work · (level + 1)` (for a lot under construction, the construction under way); 0.0 at `max_level` |
| `foreman_mult` | float | v8 (E3-3): the multiplier this building's job output gets from its foreman now (MECHANICS §4.2): `foreman.mult + speed · foreman.speed_k` while one works there; 1.0 with no foreman, and where one gives nothing (a passive building, or one not `active`: unpaid, idled by Thrift, mid-upgrade, no hands staffed). Its `output` already includes it |
```gdscript
{rev: 3, tier: "hamlet", next_tier: {tier: "village", have: 4, need: 6, missing: ["house"]},
 lots: [{id: "lot-01", size: 2, unlocked: true, building_id: "crypt"}, {id: "lot-05", size: 1, unlocked: true, building_id: ""}, ...24],
 buildings: [{lot_id: "lot-04", building_id: "market", level: 1, state: "active", progress: 1.0, slots: 2,
              staffed: 2.0, staff_cap: -1, foreman: "", output: {gold: 0.3}, upkeep: {gold: 0.03, bone: 0.0}}, ...],
 ladder: ["build", "haul", "pit", "stall", "mill", "forge", "tend"],
 ladder_effective: ["build", "haul", "pit", "stall", "mill", "forge", "tend"],
 jobs: [{id: "haul", slots: 3, staffed: 3.0}, {id: "pit", slots: 2, staffed: 2.0}, {id: "mill", slots: 2, staffed: 2.0}, ...],
 workers: {total: 12.0, idle: 5.0, in: 0.128, rot: 0.025, muster: 0.0, steady: 61.4, steady_kept: 18.2, muster_steady: 0.05, lifetime_s: 480.0},
 living: 10.0, living_cap: 16.0, migrants: 0.012, departures: 0.0,
 morale: {value: 0.6, target: 0.6, factors: [{id: "base", delta: 0.6}]},
 gold: 80.0, bone: 30.0, bodies: 40.0, bodies_cap: 200.0, trade_rate: 0.3,
 haul: {target: "auto", current: "old-sluice", convoys: [{from: "old-sluice", to: "covington", phase: "back", t: 0.4, load: 14.0}]},
 relish_home: true}
```

### 5.10 `view_catalog()` · E2 (crafts E3)
From E2a `no_gold` and `no_bone` read TownSim's stocks, `count` counts the buildings whose first build
has finished, and a lot under construction is not free. From T2.4 (E2a) the gates are `cmd_build`'s
(the tier, blueprint and building gates, the unlocked lots, the tier-gate fix of MECHANICS §4.4), and
`can_build`/`reason` always agree with what `cmd_build` would answer on the first lot in `lots`. Its
`reason` order is `unique` (from `api_version` 3: the Crypt once one stands), `needs_tier`,
`needs_blueprint`, `needs_building`, `no_lot`, `no_gold`, `no_bone`, `no_relics`.

| key | type | meaning |
|---|---|---|
| `buildings` | Array[Dictionary] | one per building id (below) |
| `crafts` | Array[Dictionary] | per `CRAFT_IDS`: `{item_id: String, cost: {essence: int, relics: int}, can_craft: bool, reason: String}`: `reason` is what `cmd_craft` would answer now, `""` when it would craft (from E3-4 the same rule, `needs_building` read from `craft_slots`, §4.3), and `cost` is `economy.json` `craft.<item_id>` |
| `blueprints` | Array[Dictionary] | `{id: String, owned: bool}` |
| `husk_craft` | Dictionary | v9 (E4, lever (b)): `{kinds: Array[String], cost: {bone: float, remnants: int}, can_craft: bool, reason: String}`: the kinds `cmd_craft_husk` makes (`loot.json` `chest_by_tier["1"].husk_kinds`), its price (`economy.json` `craft.husk`, GUESS), and the reason it would answer now for any of those kinds (`no_remnants`, `no_bone`, `at_cap` from v10, or `""`, §4.3). The town shows it in Phase I |

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
| `reason` | String | the first failing reason among `unique`, `needs_tier`, `needs_blueprint`, `needs_building`, `no_lot` (no free unlocked lot fits), `no_gold`, `no_bone`, `no_relics` |
| `lots` | Array[String] | free unlocked lots it fits |
| `work` | float | v6 (E2b-2 T3.2, api-request #17): the build work a new build needs, `build_work · 1` |
| `projected` | Dictionary | v6 (E2b-2 T3.2, api-request #9): `rate_id → float` over every `RATE_IDS` id, the change in each net rate if this building were finished now and staffed by the current ladder, at today's state (below) |

**`projected` and `upgrade_projected`** (v6, api-request #9) use the sim's own code, never a mirrored
formula. A copy of TownSim gets the building finished at level 1 on the row's first free lot (`lots[0]`),
or, when no free unlocked lot fits, on a hypothetical lot after the last one, so it is staffed last in
each job; for `upgrade_projected` the lot's building goes up a level in place. TownSim's own
`place_building` restaffs it with the ladder's allocation. The copy is stepped one substep from the inputs
the next core step will give TownSim (`_town_inputs`; the mint at the copy's working pits and the feed
now; WORK at the valve that step splits with) and diffed against a copy of today's TownSim stepped from
the same inputs, so the step's own drift cancels (the brief asked for a diff against the live last
substep's rates; that one would carry a substep of drift):
- `workers`, `bodies`, `gold`, `bone`, `living`: the change in that step's net rates, as `view_rates`
  computes them (`bodies` with the trip-averaged haul);
- `mint`: the change in the next step's mint (the pits' production);
- `work`, `war`, `flood`: Δmint × the valve (the current valve slewed one substep toward its target, the
  one the next step splits with; the current valve while no slew is pending). `war` leaves out any change
  in TownSim's muster;
- `backlog`: Δflood plus the change in the WAR that falls through to Vei at the next step's WAR
  (`RealmSim.war_at`, the split `view_projection` reads). The dispatch it splits by is session-only, so
  before the first substep after a load all of Δwar falls through (as in `view_projection`, §5.17);
- `corpses`: 0.0.

Checked against the sim (`test_api_v6`): a pit, a house, a market and a Bone Mill upgrade at
`midgame_2flips` give, within 1e-9, the change in `view_rates` when the building is really finished in a
copy (`place_building`) and one substep runs. Pure: nothing changes, `rev` stays, no event.

**Cost and caching** (T3.2; timings on 12 cores at a load of about 5 to 7, other Godot processes running;
no time is asserted). Each row is a TownSim clone (24 µs), its `place_building` restaff (150 µs) and one
step (250 µs): 0.45 to 0.55 ms at `pre_vei`. The baseline the rows diff against (today's TownSim cloned and
stepped from the same inputs) costs about the same. Every row at once at `pre_vei` (21 catalog rows, 20
built lots) is about 20 ms. The town fetches its views on the substep frames, the heaviest ones (Covington
fetches when `rev` moves), so the rows are cached and refreshed on the frames in between, late in each
substep interval, the influence field's `advance()` pattern (§3 step 9):
- **The views only read.** `view_catalog()` and `view_town()` return the cached rows and compute nothing.
  A row not yet computed reads `{}`: after a new game or a load (both empty the cache) and for a new lot.
  `economy.json` `town.projection_rows_per_call` (shipped 0) is a test override. Above 0 a call refreshes
  up to that many of its own part's rows, exactly; the exactness, purity, persist and contract tests set
  1000, so a call computes in full.
- **Frame work.** `GameState._advance` does it after the substep loop, on the frame path only (a capped
  `tick(dt, max_substeps)`, as `Game` calls it each frame), only when that call ran no substep, and only
  once the substep accumulator holds at least `town.projection_phase` (0.5) × `substep_s()`. Scenes
  refetch when `rev` moves, so their own work (the fetch, then the binds of what they fetched) bunches up
  in the frames just after a substep; background work belongs in the later part of the interval. It
  refreshes at most `town.projection_rows_per_frame` (1) units, the baseline counting as one; the
  baseline is recomputed only when the state has moved since it was made (a new `rev`, `t` or
  `TownSim.structure_rev`). `tick(dt)` with no cap (tests, harnesses) never does it, a paused sim doesn't,
  and T3.3b's catch-up must not.
- **Only while the catalog is wanted:** a `view_catalog()` read within the last
  `town.projection_refresh_s` of sim (the call notes its `t` in the session-only cache; nothing saved or
  shown changes). `view_town()` doesn't count, so the map (which reads `view_town()` but no projection)
  and the raids pay nothing. Covington reads `view_catalog()` on every fetch whatever the tab, so in
  practice the rows refresh while the town scene is open.
- **Fast-forward.** When every frame substeps, nothing would refresh. So after
  `town.projection_starve_frames` (30) substep frames in a row, one row goes through on the next, with
  the baseline it needs (2 units, about 1.1 ms at `pre_vei`), whatever the phase.
- **Stale.** A row is stale when `TownSim.structure_rev` (a building's arrival or removal, level, state
  or staff cap, the ladder, the vats), the tier, the valve target or Relish's being home has changed
  since it was computed (a structure change makes every row stale at once), or once
  `town.projection_refresh_s` (5 s) of sim has passed since. A stale row keeps its last value until its
  turn, with one exception: each cached `upgrade_projected` row stores the lot's `{building_id, level}`
  it was computed for, and reads `{}` once the lot holds another (after a demolish and rebuild, or a
  finished upgrade), so a card never shows another building's or level's projection. A catalog row is
  keyed by its building id, so it can't belong to another building.
- **Order.** Fixed: the baseline, then the catalog's stale rows in `buildings.json` order, then the
  lots' in lot order.
- **Tolerance.** A refreshed row's value is replaced only when some rate moved by more than
  `town.projection_tol` (`rel` × abs(old) + `abs`: 1% and an absolute floor of 0.005/s, half the 0.01 the
  build card shows). `BuildSort.row_sig` hashes the whole row, so without it every card whose floats
  drifted would re-render each window. A shown value is within that tolerance of the fresh one; the
  call override is exact.
- **Lag bound.** After a change every row shows its new value within about (rows + one baseline per
  substep) late light frames. At `pre_vei` at 60 fps each substep interval has 15 frames past the phase,
  the first of them paying the baseline, so 41 rows take about 3 substeps (1.5 s at 1x), plus up to `projection_refresh_s` for drift with no structure change
  (and a held row's tolerance). At fast-forward it is one row per `projection_starve_frames` frames. The
  build card is display-only; nothing in the sim reads a projection.
- **What the town shows.** `BuildSort` treats a `projected` that is a Dictionary as present
  (`BuildSort.benefit`, `HudModel`), so `{}` replaces the stand-in's static numbers with no benefit lines
  until the first refresh: about 1.5 s live after a load, a new game or a new lot, and always in a test
  that neither overrides the budget nor runs capped frames.
- **Measured** (the town scene at `pre_vei`, `--town-tab=build`, uncapped, headless with its per-frame
  sleep off, 20 s of sim spanning four refresh windows and an upgrade, interleaved with 3d39deb, §3 with
  no projections). The machine was shared, so only runs with no other Godot process at their start and
  end count as clean. Clean runs: 3d39deb (2) median 405–468 µs, p99 1.13–1.29 ms, max 7.5–9.0 ms,
  0–1 frames over 8 ms; this design (3) median 419–439 µs, p99 1.13–1.19 ms, max 6.7–8.5 ms, 0–1
  frames over 8 ms. Over all 26 and 22 runs, contended ones included, 23 and 14 frames went over 8 ms;
  one of them (9.3 ms, in a contended run) had a refresh unit on it. No unit ran on a substep frame.
  Before this, with §4 computing in the views (3c71a45): max 27.7–28.8 ms and 5–6 frames over 8 ms, the
  20 ms refresh each window and after the upgrade.
- **What the refresh doesn't cause** (pre-existing and town-side): the town's bind frame after a
  construction starts (the light frame after the construction-start substep), already 6.9–9.0 ms on
  3d39deb, is the frame over 8 ms in both trees; and the rare pairs of frames of about 12 ms around
  t+17–18 s, which also occur with every projection off.
- **Tests** (`test_api_v6`, `api-v6-projected-frame`): the views compute nothing; an uncapped tick
  refreshes nothing; with no recent `view_catalog()` read (or only `view_town()`) nothing refreshes; a
  light frame refreshes at most `projection_rows_per_frame` units; with every row stale a substep frame
  refreshes none; a light frame early in the interval refreshes nothing and one past the phase a unit;
  after a structure change enough light frames match a fresh full compute within
  `projection_tol`; after a window each row is its old value (within tolerance of the fresh one) or the
  fresh value; and the starve rule lets the baseline and one row through on the 30th substep frame.

```gdscript
{rev: 3, buildings: [
  {building_id: "house", cost: {gold: 40.0, bone: 10.0, relics: 0}, upkeep: {gold: 0.01, bone: 0.0}, build_work: 60.0,
   lot_size: 1, max_level: 8, count: 0, requires: {tier: "hamlet", blueprint: "", building: ""},
   can_build: true, reason: "", lots: ["lot-05", "lot-06", "lot-07", "lot-08"]},
  {building_id: "inn", ..., can_build: false, reason: "needs_tier", lots: []}],
 crafts: [{item_id: "simulacrum", cost: {essence: 20, relics: 1}, can_craft: false, reason: "needs_building"}, ...],
 blueprints: [{id: "embalmer", owned: false}, ...]}
```

### 5.11 `view_stances()` · E3 (E1: echoes `cmd_set_stance`; live from E3-1, v8)
| key | type | meaning |
|---|---|---|
| `slots`, `used` | int | `stance.base_slots` + Guildhall + 1 while Relish is home |
| `beat_id` | int | the current sim beat, `floor(t / beat_s)` |
| `stances` | Array[Dictionary] | one per `STANCE_IDS` (below) |

Each `stances` entry (MECHANICS §4.5 has each stance's condition and effect):

| key | type | meaning |
|---|---|---|
| `id` | String | |
| `on` | bool | the player toggle |
| `suspended` | bool | on, but no slot is free |
| `active` | bool | its condition is firing now. v8 (E3-1, the run's manager): the condition alone, computed for **every stance, on or off**, as the stance step last let it change (§3 step 1: at a beat, held by `stance.hold_s`). A stance acts only while it is on, not suspended and active, so an off or suspended stance can read `true` and do nothing. `false` after a new game and a fixture load until a beat reads the conditions |
| `fired_beat_id` | int | the beat it last changed `active`, or `-1` (never since the new game; a save keeps it, §9.1) |
| `hold_s_left` | float | the `stance.hold_s` remaining before `active` can change again (0.0 when none) |
| `projected` | Dictionary | `rate_id → float`: the change in each net rate per second if toggled. v8 (E3-1): toggled as `cmd_set_stance` would (turning one on with no free slot changes nothing; turning an older one off can free a slot for a suspended one), from the one allocation (`TownSim.staff_allocate` on the effective ladder the toggle makes, with Muster's idle cap and Thrift's buildings: the ones it idles, or the ones it would idle starting now) and the flows TownSim's step runs on it, against the same for today's stances (MECHANICS §4.5). **Sparse:** only the rates that move; `{}` when toggling it changes no stance's acting (an inactive stance, or one no slot has room for) or moves no rate. Pure: no `rev`, no event |

**`projected`** (v8, E3-1): `workers`, `bodies`, `gold`, `bone`, `living` are the change in that net now:
the workers' inflow (last step's) less the rot (staffed, and idle × `worker.idle_rot_mult`, over the lifetime)
and the muster (the inflow the pinned workforce can't hold); the bodies' rot return and trip-averaged haul (the
haul scaled by the haulers and the convoy's speed; 0 while no convoy is out) less the pits' burn and the mills'
draw (their want while the store holds bodies, else the pits first); the stalls' gold less the gold upkeep; the
bone milled less the bone upkeep; the migrants less the departures; each 0 at its store's cap while it would
rise. `mint` is the next step's (the pits' feed), `work`, `war` and `flood` Δmint × the valve the next step
splits with (`war` plus Muster's Δmuster × `worker.mass`), `backlog` Δflood plus the change in the WAR that falls
through to Vei (`RealmSim.war_at`), `corpses` minus the haul's change. **Not projected** (they need the sim
stepped): what morale does over time (Thrift idling a Well or the Statue lowers the morale target, which morale
eases toward at `morale.ease_per_s`, so departures and Hearth's condition move later, not now); the first
convoy a lifted haul would send (none is out, so its haul reads 0); and the one-off lump Muster sends at once
(the idle hands above the new cap of 0, a mass, not a rate). **Cost** (median of 5 × 400 calls, the cache cleared
each call, 5 s after a fixture load, on a loaded machine): 0.22 to 0.30 ms at day1, 0.22 to 0.45 ms at
midgame_2flips, 0.60 to 1.06 ms at pre_vei (one allocation per stance whose toggle changes the acting stances,
plus one for today's), over 0.2 ms, so it is cached on `[rev, t, TownSim.structure_rev]`: a cached call is about
9 µs.
```gdscript
{rev: 3, slots: 3, used: 1, beat_id: 117, stances: [
  {id: "harvest", on: true, suspended: false, active: false, fired_beat_id: -1, hold_s_left: 0.0, projected: {}},
  {id: "hearth", on: false, suspended: false, active: true, fired_beat_id: 115, hold_s_left: 11.6,
   projected: {mint: -0.6, work: -0.24, war: -0.27, flood: -0.09, bodies: -0.31, gold: 0.3, corpses: 0.12, backlog: -0.09}}, ...5]}
# (illustrative: Hearth's condition holds while it is off, so it reads active; toggling it on would lift the stalls)
```

### 5.12 `view_inventory()`, `view_big_undead()`, `view_party()` · E1
Loot comes in through `apply_result` and grants. The big-undead raise (§4.3) was a §1.1 stub until
E3-3 (v8), which made it live.

**`view_inventory()`**

| key | type | meaning |
|---|---|---|
| `husks` | Array[Dictionary] | `{uid: String, kind: String}` |
| `remnants` | Array[Dictionary] | `{uid: String, aspect: String (one of STATS), rarity: String (one of RARITIES), magnitude: int}` |
| `blueprints` | Array[String] | owned blueprint ids |
| `relics`, `relics_cap`, `essence`, `essence_cap`, `simulacra_ready`, `phylactery_charges` | int | simulacra and charges are fungible counts, not uids. From T2.4 the caps are the base plus the Reliquary (`relic_cap` 6, `essence_cap` 30). `simulacra_ready` and `phylactery_charges` are live from E3-4 (`cmd_craft` adds to them; until then `simulacra_ready` read 0), with no cap of their own |

**`view_big_undead()`**

| key | type | meaning |
|---|---|---|
| `cap`, `count` | int | `big_undead.cap` (4) plus `big_undead.per_crypt_level` (1) per Crypt level above 1 |
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
| `filled_slots` | int | v8 (E3-3, api-request #6): the remnant slots its raise filled (SlabLogic's `filled`); 1 for one raised before v8, a fixture's and a debug grant's (§9.1). The map's glyph, the town's foreman diamond and the dungeon's and the Vei fight's party units draw one stroke per slot |

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
view_big_undead(): {rev: 3, cap: 4, count: 1, big_undead: [{uid: "u4", name: "Old Gristle", kind: "hulk", role: "bulwark",
                    stats: {power: 2.0, beef: 3.0, wits: 0.0, presence: 0.0, speed: 0.0}, place: "party", front: "", filled_slots: 2}]}
view_party():      {rev: 3, party: [{uid: "u4", ...}], fort_id: "old-sluice", garrison_units: 0, garrison_in_mass: 0.0, starter_units: 8, strength: 8.0}
```

### 5.13 `view_backups()` · E3
The vats are the Chapel of Vats' `vat_slots` per level over every built Chapel (none without one; from T2.4).
From E3-2 (v8) they are live (MECHANICS §7): each vat's `grow` is its clone, 0..1, growing at `vats.grow_per_s` ×
its tend hands while it is staffed and tended, and `ready` at 1. `clones_ready` is the vats at 1 plus any spare
clones (the old-save rule: a save's clones above its vats at 1, a demolished Chapel's ready clones), no longer a
plain stock (until E3-2 it was GameState's stock, and slot `i` read `ready` while `i < clones_ready`). The
phylactery charges are a stock, crafted at the Ossuary from E3-4 (`cmd_craft("phylactery_charge")`, §4.3).

`death` (E3-2, MECHANICS §7's order) is what a death at HP 0 in the next run would cost right now:
- **`phylactery`** while a charge is left and `phylactery_max_per_dungeon` > 0: she revives in place and the run
  goes on, so it loses nothing (`respawn_s` 0.0, `loses` []);
- else **`clone`** with a clone ready: she wakes at Covington after `backups.clone_respawn_s` (60), losing the whole
  party (when there is one) and the unbanked loot;
- else **`unmade`**: she reforms after `backups.unmade_respawn_s` (600), losing those and the morale.

A seed's `death_ends` (§7.1, §7.2) is the death that ends the run, so it skips the phylactery step (a revive
doesn't end the run) and reads `clone` or `unmade` with its `respawn_s`, which `Results.validate` requires: with
no charge it equals this `death`'s `outcome` and `respawn_s`, and with one it is the step after it. Both equal what
the death then does (`relish_died`'s `outcome` and `respawn_s`, and `dead_s_left`). `dead_s_left` is live: her
respawn's seconds left while she is dead, else 0.
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

### 5.14 `view_vei()` · E1 (EMA sign E2, tithe E2, fronts live from E3-5, v8)
`sign`, `drain_s` and `odds` are the sustained readout (MECHANICS §3.5): `diff` is what entered her
undead queue last substep less the undead she took, per second (the backlog's net rate without
lumps, and `view_rates.backlog.net`); `diff_ema` its EMA; `sign` ±1 past ±`readout.sign_eps`. `tithe.target` is the running wave's fort (`eta_s` 0.0,
`wave_s_left`), else the warned fort (`eta_s` to its wave), else `""` and -1.0. `warning` is true
while a warning is pending.

The fronts (MECHANICS §6) are `VeiFronts.have_need` (`scripts/raid/vei_fronts.gd`) on her `backlog`, `living_pool`,
`digest_q` and the big undead as `view_big_undead` gives them, with `vei.json` (the very data `ConfigDb.data["vei"]`
holds, which the fight reads): `have` = `per_stat` × the stat of each uid in `counted` + `per_backlog` × backlog +
`per_q` × q, `need` = `need_base` + `need_per_pool` × living pool, `cleared` = have ≥ need, and `fronts_met` the
cleared count. A party member with a front counts there; one without counts on the front of its highest stat (ties
in `FRONT_IDS` order); a big undead outside the party counts nowhere. **`have` counts the uids in `counted`;
`assigned` lists only what the player put there** (`cmd_assign_front`'s echo, unchanged since E1). Until E3-5 `need`
and `have` were 0.0, `cleared` false and `fronts_met` 0.

| key | type | meaning |
|---|---|---|
| `backlog`, `living_pool`, `pool_cap` | float | mass |
| `diff` | float | mass/s: the raw differential this substep (0.0 after a load until the first substep) |
| `diff_ema` | float | mass/s: the EMA over `readout.ema_s` |
| `sign`, `drain_s`, `odds` | int, float, float | as in `view_hud` |
| `digest_q` | float | |
| `fronts` | Array[Dictionary] | per `FRONT_IDS`: `{id: String, need: float, have: float, cleared: bool, assigned: Array[String], counted: Array[String]}`. `counted` (v8, E3-5): the uids `have` counts, `assigned`'s plus each unassigned party member on its best-stat front; `assigned`: the uids whose front is this one |
| `fronts_required`, `fronts_met` | int | `fronts_met`: the fronts `cleared` |
| `tithe` | Dictionary | `{target: String, eta_s: float, warning: bool, wave_active: bool, wave_s_left: float}`. `target` is `""` and `eta_s` is `-1.0` before a target is chosen. |
| `can_begin` | bool | `cmd_begin_boss()` would succeed |
| `reason` | String | `""`, `busy`, `dead` or `not_at_vei` |
| `won` | bool | |
```gdscript
{rev: 3, backlog: 18450.0, living_pool: 380.0, pool_cap: 600.0, diff: 9.4, diff_ema: 6.1, sign: 1, drain_s: -1.0,
 odds: 0.61, digest_q: 2.6,
 fronts: [{id: "giants", need: 24.0, have: 26.5, cleared: true, assigned: ["u4"], counted: ["u4"]},
         {id: "swarm", need: 24.0, have: 24.9, cleared: true, assigned: ["u2"], counted: ["u1", "u2"]}, ...4],
 fronts_required: 3, fronts_met: 3,
 tithe: {target: "ashgate", eta_s: 88.0, warning: true, wave_active: false, wave_s_left: 0.0},
 can_begin: true, reason: "", won: false}
```

### 5.15 `view_dungeon_seed(fort_id: String)`, `view_boss_seed()` · E1
These return the open run's seed (§7), identical to what `cmd_begin_*` returned. They return `{}`
when no run of that kind is open at that fort.

### 5.16 `view_staffing_projection(order: Array, vats: Dictionary = {})` · E2b (api_version 5, api-request #16)
TownSim's own staffing allocation (`TownSim.staff_allocate`, the one `_restaff` runs every step)
on today's workforce, buildings and staff caps, with the job order replaced by `order`. Stances
change the order the same way they change the ladder's (`ladder_effective`, E3). The town uses it
to show what a ladder drag or a vat toggle would do before it is sent, so the preview never drifts
from the sim's rule.
- **Args:** `order`, a permutation of `JOB_IDS`, top first (`cmd_set_job_priority`'s argument);
  `vats` (optional), `{slot: bool}` with int slots: each listed vat counts as staffed (`true`) or not
  (`false`) instead of its `view_backups` state; slots it doesn't list keep theirs, and a slot with no
  vat (or one that isn't a whole number) is ignored.
- **What `vats` opens and closes:** the vat rule (`cmd_staff_vat`, §4.3; MECHANICS §7). A vat counted
  as staffed opens its Chapel's tend slot, and the ladder fills it like any other room in `order`; one
  counted as unstaffed closes it, and its hand goes to the next room or idles. So
  `view_staffing_projection(order, {slot: on})` equals `view_town()` after `cmd_staff_vat(slot, on)`
  for each listed slot, and the town reads from it which job loses or gains the hand.
- **Pure:** nothing changes, `rev` stays, and no event is queued. Like every view it is a fresh deep
  copy carrying `rev`.
- **Refusals:** an `order` that `cmd_set_job_priority` would refuse gives its reason (`unknown_job`,
  `duplicate_job`, `missing_job`, in that check order) with `jobs` and `buildings` `[]` and `idle`
  0.0.

| key | type | meaning |
|---|---|---|
| `jobs` | Array[Dictionary] | `{id: String, slots: int, staffed: float}`: the jobs with slots, in the effective order of `order`, as `view_town().jobs` lists them in `ladder_effective` order |
| `buildings` | Array[Dictionary] | `{lot_id: String, staffed: float}`: every built lot, in `view_town().buildings` order |
| `idle` | float | the workers left over (`view_town().workers.idle`) |
| `reason` | String | `""`, or the refusal above |

With `order` equal to today's `ladder_effective` and no `vats`, `jobs`, each `buildings[].staffed`
and `idle` equal `view_town()`'s exactly. With another order they equal what `view_town()` shows
after `cmd_set_job_priority(order)`.
```gdscript
Game.state.view_staffing_projection(["build", "haul", "pit", "mill", "stall", "forge", "tend"])
# -> {rev: 812, jobs: [{id: "haul", slots: 3, staffed: 3.0}, {id: "pit", slots: 2, staffed: 2.0},
#     {id: "mill", slots: 2, staffed: 2.0}, {id: "stall", slots: 2, staffed: 0.4}],
#     buildings: [{lot_id: "lot-01", staffed: 0.0}, {lot_id: "lot-02", staffed: 2.0}, {lot_id: "lot-03", staffed: 3.0},
#                 {lot_id: "lot-04", staffed: 0.4}, {lot_id: "lot-07", staffed: 2.0}], idle: 0.0, reason: ""}
Game.state.view_staffing_projection(["tend", "stall", "pit", "haul", "build", "mill", "forge"], {0: true})
# -> {rev: 812, jobs: [{id: "tend", slots: 1, staffed: 1.0}, {id: "stall", slots: 4, staffed: 2.0}, ...], ...}
#    (vat 0 staffed: its tend slot opens and takes a hand from the stall)
Game.state.view_staffing_projection(["haul", "pit"])
# -> {rev: 812, jobs: [], buildings: [], idle: 0.0, reason: "missing_job"}
```

### 5.17 `view_projection(valve: Dictionary, settled := false)` · E2b-2 (api_version 6, api-requests #7 c, #13; `settled` T3.4b)
The held forts' readouts (§5.5), "WAR supports N of M" (§5.1), the split and the payoff at another
valve, for the live valve drag. The same math as the live views, at a hypothetical valve target.
- **`settled`** (T3.4b, optional, the run's manager): the margins are judged against the wave train at
  that valve, as `view_fort` judges them (§5.5), each row `margin_verified` true; the train runs once for
  the valve and is cached with the state (about 1.2 ms on midgame_2flips, so once per drag, on its
  release: map's Phase I wires the call on release or ~150 ms with no movement; a valve whose WAR is the
  valve's target's reads the live verdict, no probe). Left out (false), a drag's margins: the one-wave probe
  (MECHANICS §3.5, a full wave from the weakest state the support leaves the fort in), each row
  `margin_verified` false, exactly as before T3.4b. Nothing else in the result depends on it.
- **Args:** `valve`, `{work, war, flood}`, normalised as `cmd_set_valve` normalises it. It refuses
  nothing: one `cmd_set_valve` would refuse (a missing or non-number key, a negative or non-finite
  share, all zeroes) is the current valve (`view_hud.valve`), and so is one within 1e-12 of it on every
  share.
- **Pure:** nothing changes, `rev` stays, no event is queued; every view and the save dump read the
  same before and after. Like every view it is a fresh deep copy carrying `rev`.
- **At the current valve, with the valve at its target and Relish not travelling, every field equals the
  live views'.** Otherwise the planned support differs: while the valve slews, or Relish travels, the
  projection reads the target valve's WAR split and her committed arrival, so its rates, `fall_s` and the
  margins that depend on them can differ from `view_fort`'s (details below). In that case (the current
  valve, with the valve at its target and Relish not travelling), `split` is `view_hud.split` (and
  `war_overflow` `view_hud.war_overflow`), `workers_steady` is `view_town.workers.steady`, `war_supports`
  is `view_hud.war_supports`, each `margins` entry's `garrison_rate` is that fort's `view_fort` one, and
  `backlog_diff` is `view_vei.diff_ema`. Each entry's `fall_s` is `view_fort`'s (in the same case), and
  with `settled` its `margin` and `margin_cause` are too, **only with the valve at its target** (as it is
  once its slew is done): `view_fort` reads the target's WAR as its
  planned support, a projection the valve passed. While the valve slews, `settled` at the target valve
  runs `view_fort`'s own train (the same probe, the same broken and settled verdicts), but its
  `garrison_rate` and `fall_s` are the target's, so its margin can differ where `fall_s` decides it. By default the margin and cause are the one-wave probe's (T3.4b:
  `view_fort` reads the train).
- **Current and planned in a row** (T3.4b fix batch): a row's `garrison_rate` reads that valve's split with
  Relish where she stands; its `fall_s` is the earlier of that clock and the clock at that valve's split
  with Relish where she is travelling to; with `settled`, its margin is the train at the latter. With her
  not travelling the two are the same.
- **Before the first substep after a load** the split is 0 (it is session-only, §5.1, §9.1), so the
  projection reads no WAR anywhere: every held fort falling. The live views read the saved `r_in`
  until then. The map knows (it waits for the streams).

| key | type | meaning |
|---|---|---|
| `valve` | Dictionary | `{work, war, flood}`: the valve evaluated (normalised; the current one for an invalid input) |
| `split` | Dictionary | `{work, war, flood, war_overflow}` mass/s: this substep's mint × the valve, WAR plus TownSim's muster as it is now; `war_overflow` the WAR that falls through to Vei at that WAR (every target at its limit), as `view_hud.war_overflow` reads it |
| `workers_steady` | float | workers: `view_town.workers.steady` × the WORK share against the current one (TownSim's steady workforce is `WORK / worker.mass × lifetime`, linear in WORK); `mint × work / worker.mass × lifetime` when the current WORK share is 0. The map's stand-in scaled the same way |
| `backlog_diff` | float | mass/s: the sustained differential (`view_vei.diff_ema`) moved by the change in FLOOD, in the WAR that falls through to Vei, and in the WAR to each fort whose garrison isn't pinned at 0 (in steady state the extra drains on to her queue, since the garrison's pull doesn't grow with it). The map's stand-in added Δflood + Δwar × a fixed fraction; this is that, from the sim's own split |
| `war_supports` | Dictionary | `{n: int, m: int}`, as `view_hud.war_supports`, at the valve's WAR |
| `margins` | Dictionary | `{fort_id: {margin: String, margin_cause: String, fall_s: float, garrison_rate: float, margin_verified: bool}}`, one per held fort, as `view_fort` computes them at the valve's WAR to that fort (each fort's WAR is the last dispatch's split of the valve's WAR: its weights, Relish's tide and the full forts' limits as they stand). `margin_verified` (T3.4b): true when the margin is the wave train's (`settled`), false when it is the drag's one-wave probe |
```gdscript
Game.state.view_projection({"work": 0.4, "war": 0.45, "flood": 0.15})   # midgame_2flips a substep in: its valve
# -> {rev: 2, valve: {work: 0.4, war: 0.45, flood: 0.15},
#     split: {work: 5.12, war: 9.71, flood: 1.92, war_overflow: 0.0}, workers_steady: 61.44, backlog_diff: 4.36,
#     war_supports: {n: 2, m: 2},
#     margins: {"ashgate": {margin: "safe", margin_cause: "", fall_s: -1.0, garrison_rate: 1.463, margin_verified: false},
#               "old-sluice": {margin: "safe", margin_cause: "", fall_s: -1.0, garrison_rate: 0.872, margin_verified: false}}}
Game.state.view_projection({"work": 0.4, "war": 0.45, "flood": 0.15}, true)   # the same, settled: the wave train's
# -> {..., margins: {"ashgate": {margin: "thin", margin_cause: "wave", fall_s: -1.0, garrison_rate: 1.463, margin_verified: true},
#               "old-sluice": {margin: "thin", margin_cause: "wave", fall_s: -1.0, garrison_rate: 0.872, margin_verified: true}}}
#    (both unsettled at the cap: Ashgate is a knife-edge, and Relish's arrival at Greywall will cut Old Sluice's WAR)
Game.state.view_projection({"work": 0.8, "war": 0.0, "flood": 0.2})   # only TownSim's muster (3.95/s) is WAR
# -> {..., split: {work: 10.24, war: 3.95, flood: 2.56, war_overflow: 0.0}, workers_steady: 122.88, backlog_diff: 0.84,
#     war_supports: {n: 2, m: 2},
#     margins: {"ashgate": {margin: "thin", margin_cause: "wave", fall_s: -1.0, garrison_rate: 0.367, margin_verified: false},
#               "old-sluice": {margin: "thin", margin_cause: "wave", fall_s: -1.0, garrison_rate: 0.126, margin_verified: false}}}
Game.state.view_projection({"work": -1.0})   # one cmd_set_valve refuses: evaluated at the current valve
```

### 5.18 `view_catchup()` · E2b-2 (api_version 6, T3.3b)
The catch-up's progress, for a progress screen (the map's, Phase I; IDLE §4).
| key | type | meaning |
|---|---|---|
| `active` | bool | a catch-up is running: a chunked `cmd_load`'s or an open-game gap's (§3). Commands refuse with `catching_up` meanwhile (§4) |
| `done_s` | float | sim seconds of it run so far; once it is done, `total_s` |
| `total_s` | float | its length in sim seconds (whole seconds); the last one's once it is done, 0 since a new game or a load with nothing to catch up |
```gdscript
Game.state.view_catchup()  # -> {rev: 52113, active: true, done_s: 86400.0, total_s: 604800.0}
```

### 5.19 `view_away()` · E2b-2 (api_version 6, T3.3c; api-request #7 d, IDLE §7)
The "While you were away" report, for the map's panel (`AwayLogic`, Phase I).
| key | type | meaning |
|---|---|---|
| `shown` | bool | a report is waiting: true from its catch-up's end until `cmd_dismiss_away` |
| `away_s` | float | the seconds it caught up (`cmd_load`'s `away_s`, or a gap's whole seconds); the map formats it |
| `capped` | bool | the time away was above `idle.catchup_max_s` and capped there (a load's, or an open-game gap's: the gap's excess, fraction too, is dropped) |
| `gains`, `ready`, `losses` | Array[Dictionary] | its lines in IDLE §7's order, each `{text: String, kind: String, target: String}` |

- **When** (`Catchup.run`, `GameState._report_away`): at the end of every **reporting catch-up**: a load's
  (`cmd_load`, either path) that caught up 1 s or more, and an open-game gap's of `idle.report_min_s` (600 s)
  or more (§3). It is built from the events that catch-up collected (`catchup_events()`, §6) and the state
  before it (taken at its start, after the run's end, §4.1) and after it, and the event `away_report` is
  queued once, then. A shorter gap's events reach the scenes live and make no report.
- **Kept until dismissed, never saved.** A later reporting catch-up replaces it; a load replaces it (a load
  with nothing to catch up leaves none); a new game clears it. Before any report: `shown` false, `away_s`
  0.0, `capped` false and the three lists empty.
- **`kind`** is one of `stream`, `build`, `refilled`, `raid`, `slab`, `queue`, `retaken`, `village_lost`,
  `overflow`, and from v7 `unpaid`; **`target`** is a fort id, `"slab"`, `"queue"` or `""` (the map's click: a
  fort, Covington's slab or queue, nothing), and from v7 a lot id for `unpaid` (additive for map: Covington at
  that lot; `AwayLogic.action` reads it as `none` until map takes it up). From v7 (R2) a `raid` line can have
  `target` `""`: the full stores' prompt names no fort.
- **gains** (`target` `""`):
  - each stream in `idle.report.streams`' order (`stream`): Vei's backlog (with ▲, ▼ or ■ for its net),
    the mint, workers, bodies, gold, bone and Covington's living, each its net rate over the absence and
    its net total: `"backlog ▲ +2.1/s · +69,552"`. The totals are the ledger's and the stores' changes:
    the mint `ledger().sources.mint`'s, the backlog, bodies and workers their `held` pools' (workers in
    workers), gold, bone and living the town's; the rate is the total over `away_s`;
  - the builds finished (`build`, `building_done` events): `"2 builds finished: Inn · Bakery"`;
  - each queued build that started (`build`, `queue_started` events), with when, measured from when you
    left, and why, one `idle.report.waited_on` template per `waited_on` value (`needs_tier` "when the tier
    rose", `no_gold` "when the gold came in", ...; `""` started at once): `"Bakery started 6 m after you left,
    when the gold came in"`, `"Inn started right away"`. A building is named by its town label
    (`buildings_view.json`, the town's), with `level_fmt` past level 1 ("Market level 2");
  - each fort refilled (`refilled`): held now, not retaken during the absence, its loot yield below 1 when
    you left and back to 1 now (MECHANICS §5.3): `"Ashgate refilled"`.
- **ready:** each refilled fort, `"Ashgate refilled: raid it"` (`raid`, the fort); husks waiting while the
  crypt has room for a big undead (fewer than its cap), wherever Relish is, `"2 husks: raise at the slab"`
  (`slab`, `"slab"`); an empty build queue, `"Queue empty: plan the next build"` (`queue`, `"queue"`), unless the
  stores are full: the raid prompt below shows in its place (W). From v7
  (R2, the E2b-2 vision review's item 3), the queue's line when it isn't empty: its head still waiting on funds
  at the end of the absence (the first `waiting_funds` entry of `view_town().queue`, §5.9), from its
  `affordable_in_s` and the store that sets it, `"Inn is waiting on gold: affordable in 6 m"` (the wait rounded
  up to the minute, `when_hm_fmt` / `when_m_fmt`), or at `-1.0` `"House can't be afforded at the current income
  of 0/s bone: move it down, or build a Bone Mill"` (that store's net rate now, `BuildRules.queue_net`, the HUD's
  below the cap, and what raises it, `idle.report.afford_raise`), and short of relics, Shawn's words with no rate,
  `"Crypt level 2 needs relics: raid a fort"` (W; no head reaches it, since the walk gates a relic shortfall as
  `no_relics` first; W2: the line instead shows for the first `no_relics` entry when no entry can start (no row `next`,
  no `waiting_funds` head with `affordable_in_s` >= 0; an entry `queued` behind a `-1.0` head can't start either), with the stores full or not, in queue order after or
  before that head's own line: `["House can't be afforded at the current income of 0/s bone: build a Bone Mill",
  "Crypt level 2 needs relics: raid a fort"]`); none when no entry waits on funds and none is relic-gated.
  W2: a start that waited but began under a minute in reads `"Inn started within a minute of you leaving, when the
  gold came in"` (`gains`; `started_now_fmt`'s "right away" stays for one that didn't wait). From F1: `"House can't be afforded at the current income of 0/s bone: build a Bone Mill"` when moving the head
  down can't help (F2: no other queued entry could start in its place: nothing behind it, or only entries stuck on
  the same store, or only gated ones; no move down), and when the head is its store's own producer
  (`idle.report.afford_producer`, the Bone Mill for bone and the Market for gold, its upgrades too) a fact in place
  of itself, `"Bone Mill level 2 can't be afforded at the current income of 0/s bone, and nothing else makes bone: move
  it down"` (`afford_raise_self`; without ": move it down" when moving it down can't help). `queue`, `"queue"`, so the map's click dives to the queue. And with the queue empty, when gold and
  bone are each within `idle.report.full_tol` (0.01) of their caps, the raid prompt `"Your stores are full and
  the queue is empty: raid a fort for relics"` (`raid`, `""`: a `raid` line with no fort, which
  `AwayLogic.action` reads as `none` today: additive for map, a meaning change of the kind), in place of
  `"Queue empty"` (W: no build can be planned without relics).
- **losses:** each fort retaken during the absence, in order (`retaken`, the fort), `"Vespers retaken: raid
  it to win it back"`, or, when Relish stood there and walked home (its `relish_returned` was collected
  with the rest, so this line and `view_relish().returned` are how the player learns of it), `"Vespers
  retaken, Relish walked home: raid it to win it back"`; each village yours when you left (`player`) and
  Vei's at the end (`village_lost`, `""`), `"village Lorn lost to Vei"`; each store's overflow from the change
  in `ledger().stores`, from `idle.report.overflow_min` (1) not stored (`overflow`, `""`), `"Gold is full: 120
  not stored"` (W: not called waste); before it, from v7 (R1), each building that went unpaid during the absence,
  in lot order (`unpaid`, its lot id), worded by W: `"<label> stopped for <time>, <store> ran out: <what it
  stopped doing>"`, `"Statue of Relish stopped for 1 h 12 m, gold ran out: lifted no morale, deaths shook the town
  harder"`. The time is the sum of its spells from the collected `building_unpaid` events (true, then false; §6):
  one unpaid when you left counts from the start, one still unpaid at the end to the end, and it reads as
  `when_hm_fmt` / `when_m_fmt`, or "briefly" under a minute (`"Charnel House stopped briefly, gold ran out:
  hauled no corpses"`). The store is each one its `buildings.json` upkeep is above 0 in, in
  `idle.report.afford_stores`' words joined by `list_sep` (gold for every building today); it is read from the
  configs, not from the event, which keeps its keys. What it stopped is one `idle.report.unpaid_stopped` phrase per
  job it offers and per working effect it has (capacity effects are kept, and so are the effects in
  `idle.report.unpaid_inert`, which nothing reads yet: F2), each phrase once, joined by `unpaid_sep`; a building
  with neither, a House, the Reliquary or the Watchtower, has no tail: `"Watchtower stopped for 59 m, gold ran
  out"`. An unpaid building's caps stand (MECHANICS §4.3). After them, from v8 (E3-1, the run's manager's
  ruling), each building the Thrift stance idled during the absence, in lot order, with the **same kind
  `unpaid` and its lot id as `target`**, naming Thrift as the reason, not the gold: `"Statue of Relish idled by
  Thrift for 2 h 10 m: lifted no morale, deaths shook the town harder"` (`idle.report.thrift_fmt`; `"Reliquary
  idled by Thrift for 30 m"` with no tail, `thrift_none_fmt`; "idled briefly" under a minute). Its time is the
  sum of its Thrift spells (the catch-up runner's `thrift_log`; Thrift raises no event), one idled when you left
  from the start, one still idled at the end to the end; what it stopped, the unpaid line's phrases. **A meaning
  change of the kind:** `unpaid` now means a building stopped, by the gold running out or by Thrift; no new
  kind or target, so `AWAY_KINDS` and the line's shape stand. Empty when nothing was lost: the map prints
  "Nothing lost."
- **Tokens** (the map parses them, `AwayLogic.spans`): a signed rate ends in `/s` (`+2.1/s`, `−0.43/s`, two
  significant digits, `0/s` under 0.0005), a mass or count is a bare number with thousands commas
  (`+69,552`, `120`), and nothing is glued to a word. The away time is never in a line: the map formats
  `away_s`. Every template is `economy.json` `idle.report` (BALANCE §5).
```gdscript
Game.state.view_away()  # midgame_2flips loaded 12 h after its save (shipped configs)
# -> {rev: 4423, shown: true, away_s: 43200.0, capped: false,
#     gains: [{text: "backlog ▲ +5.0/s · +216,247", kind: "stream", target: ""},
#             {text: "mint +10/s · +446,432", kind: "stream", target: ""},
#             {text: "workers 0/s · 0", kind: "stream", target: ""},
#             {text: "bodies 0/s · −2", kind: "stream", target: ""},
#             {text: "gold +0.16/s · +6,912", kind: "stream", target: ""},
#             {text: "bone 0/s · 0", kind: "stream", target: ""},
#             {text: "living 0/s · 0", kind: "stream", target: ""}],
#     ready: [{text: "2 husks: raise at the slab", kind: "slab", target: "slab"},
#             {text: "Queue empty: plan the next build", kind: "queue", target: "queue"}],
#     losses: [{text: "Old Sluice retaken: raid it to win it back", kind: "retaken", target: "old-sluice"}]}
# with Ashgate's yield spent before the save, gains and ready add "Ashgate refilled" and "Ashgate refilled: raid
# it"; with gold near its cap, losses add "Gold is full: 2,162 not stored" (tests/test_away.gd), and, with its bone
# over its cap as midgame_2flips' is, ready shows "Your stores are full and the queue is empty: raid a fort for
# relics" (raid, "") in place of "Queue empty" (R2; W)
Game.state.view_away()  # day1 with its bone spent and no mill, a House and a Well queued, loaded 8 h on (R2)
# -> {..., ready: [{text: "House can't be afforded at the current income of 0/s bone: build a Bone Mill",  # F2: the Well needs bone too
#                   kind: "queue", target: "queue"}], ...}
```

## 6. Events

`drain_events() -> Array[Dictionary]`
- Every event has `t: float` (sim seconds, never decreasing) and `type: String`, plus the fields
  below.
- The queue is cleared by new game, load and fixture load.
- **A catch-up whose time a report will cover raises no queued events** (v6, E2b-2 T3.3b; IDLE §4, §7).
  A load's catch-up, and an open-game gap's of `idle.report_min_s` (600 s) or more, keep their events,
  with their `t`, for the away report (`view_away`, §5.19; `GameState.catchup_events()`), and the scenes'
  queue gets none of them: only the report's `away_report`, at its end (T3.3c). A week
  away raises thousands of events, and replaying them on load would fire every setpiece, tithe explainer
  and toast at once; the report is their summary. A load already clears the queue, so this extends that
  rule.
- **A gap under `idle.report_min_s`** (from `idle.gap_s` up) has no report, so its catch-up's events are
  queued as live: all of them, uncapped and uncoalesced, each with its own `t`, reaching scenes chunk by
  chunk (§2.1). Nothing that changes state is ever dropped there: a fort retaken inside a 300 s gap
  reaches the queue (`tests/test_catchup.gd`). No event is capped or coalesced, so no re-read cue is
  needed for that band.
- **`away_report` is the cue for an on-screen scene to re-read its views** (T3.3c). These listeners keep
  state built from events, and each must re-read its views on `away_report`: a Phase I must-fix for
  their units, carried by the run's manager.
  - map: `map_setpieces` (with `setpiece_logic`), `map_tithe_explain`, `ground_forces` and
    `flow_ground` (through `ground_meter`), `map_hud`, and the away panel (`map_away`);
  - town: `covington.gd`, `town_view` and `town_hud`. The town panels (`panel_jobs`, `panel_stances`,
    `panel_backups`, `panel_build`, `panel_crypt`) take `on_game_event` only as a cue to refresh and
    ignore the event itself;
  - the router (`scripts/main.gd`) holds the events that arrive while no scene is in the tree and
    re-emits them; it keeps no state from them.
- Scenes receive events only through `Game.game_event` (§2.1).

| type | fields | ms |
|---|---|---|
| `relish_died` | `outcome: String` (`phylactery`\|`clone`\|`unmade`), `in_place: bool` (she carried on in the run), `at: String` (node), `run_id: int`, `respawn_s: float` (0 when `in_place`) | E1 (until E3: `clone` when a clone is ready, else `unmade`, respawn 0). Live from E3-2 (v8): a raid's revives in place each raise one `{outcome: "phylactery", in_place: true, respawn_s: 0.0}` (§8.3 step 9), and from E3-5 each backup the Vei fight spent one `{outcome: "phylactery" \| "clone", in_place: true, at: "vei", respawn_s: 0.0}`, the charges first (§8.3 boss step 3); a death that ends a run raises `clone` or `unmade` with its real `respawn_s` (`backups.clone_respawn_s`, `unmade_respawn_s`), and she is `dead` until it has passed |
| `relish_respawned` | `with_clone: bool`, `at: String` (`"covington"`) | E1 (immediate until E3). From E3-2 (v8) raised by the core step's backups step (§3 step 6) when her `dead_s_left` reaches 0, `respawn_s` after her `relish_died`, stamped at that step's `t` (catch-up clips at it) |
| `building_started` | `lot_id: String`, `building_id: String`, `level: int` (target; 1 for a new building), `upgrade: bool` (`level > 1`) | E2 (TownSim's, from the substep after the construction starts; `cmd_build` and `cmd_upgrade` do not emit it themselves, and a cancel before that substep drops it) |
| `building_done` | `lot_id`, `building_id`, `level: int` | E2 |
| `building_unpaid` | `lot_id`, `building_id`, `unpaid: bool` (`true` = went idle, `false` = resumed). Which building goes idle follows the shed order since R1 (decorations, then the passive no-job buildings, then the job buildings, the WAR chain last: MECHANICS §4.3, `economy.json` `upkeep.shed_order`): the event's meaning is unchanged, so a gold floor that used to raise it for a raising pit first now raises it for the Statue | E2 |
| `tier_up` | `tier: String` (the new tier), `from: String` | E2 (GameState's, in the substep a building completing makes the requirements hold; once per rise, so several in a substep when a fixture or debug placement skips tiers) |
| `fort_flipped` | `fort_id: String`, `run_id: int`, `hold_s: float` (the grace, `flip.hold_s · (1 + flip.tier_mult · tier)`; v6) | E1 (hold effects E2) |
| `fort_retaken` | `fort_id: String`, `cause: String`: `broken` (v6: the garrison sat at 0 for `hold.break_s`, MECHANICS §3.4). E2a's `expired` and `tithe_wave` are no longer raised. `t` is its moment inside the substep (v6), and it is queued ahead of that substep's events stamped at its end, so `t` never decreases | E2 |
| `queue_started` | `building_id: String`, `lot_id: String`, `level: int`, `upgrade: bool`, `waited_on: String`: a queued entry started (paid, construction begun) in the core step's processing (MECHANICS §4.4); `t` is that step's. **T3.3's away report reads `t` and `waited_on`** for "Village Market started 3 h 12 m after you left, when the tier rose" (W's wording): `needs_tier` → the tier rose, `needs_blueprint` → the blueprint came, `needs_building` → the building it needs was built, `lot_locked` → the lot opened (the tier rose), `no_relics` → relics came, `no_gold`/`no_bone` → the funds came, `lot_taken`/`empty_lot`/`under_construction`/`unpaid`/`cost_exceeds_cap` → its lot or cap came free; `""` → it started at once. Its `building_started` follows in the next substep, as after `cmd_build` | E2b-2 (v6, api-request #3) |
| `big_undead_returned` | `uid: String`, `fort_id: String`: a siege big undead at a retaken fort went back to the crypt (place `crypt`; IDLE I6). Right after its `fort_retaken`, same `t` | E2b-2 (v6) |
| `relish_returned` | `fort_id: String`, `cause: String` (`retaken`): the fort Relish stood at (`at_fort`, there at the retake's moment: not a fort she reached later in the same step) was retaken, and she started home to Covington at `relish.travel_speed` from that moment, `t` (IDLE I5): by the step's end she has walked the rest of it, and she arrives as any journey does (a catch-up clips a step at her arrival). Right after its `fort_retaken` and that retake's `big_undead_returned`, same `t`. Live play and catch-up alike; during a reporting catch-up it is collected with the rest, and the away report's retake line says so (§5.19). Not raised while she is in that fort's dungeon: the run goes on, and when it ends she stands at the fort (`at_fort`, a retreat) | E2b-2 (v6, T3.3c) |
| `counter_garrison_cleared` | `fort_id: String`, `killed_mass: float` (the writeback's clamped kill, §8.3 step 1): a held fort's raid cleared its counter-garrison (api-request #10). Raised by `apply_result("raid", …)`, after `loot_banked`, when the fort was held when the run began and is still held when the result is applied (a fort retaken mid-run raises no clear and spends no yield: its retreat banks loot as usual and its `yield_c` stays at the retake's 1), the result is a retreat (not `relish_died`), and `killed_living_mass` ≥ the seed's `living` less half of one of the dungeon's living units: the dungeon spawns `clamp(round(living / cap · mass.enemies_per_cap), mass.enemy_min, mass.enemy_max)` enemies of `living / n` each (raid.json; `raid_populate.gd`), so the tolerance is `living / (2n)`. A seed's `living` at or under `hold.clear_min_living` (0.05, the dungeon's spawn floor, mirrored: it spawns none and clears after `held.empty_clear_s`) is all tolerated, so an empty held fort's clear raises it with `killed_mass` 0 | E2b-2 (v6) |
| `tithe_warning` | `wave_id: int`, `fort_id: String`, `eta_s: float`, `surge: float` (living mass/s before counters) | E2 |
| `tithe_wave` | `wave_id: int`, `fort_id: String`, `surge: float` (after counters), `duration_s: float`, `relish_here: bool`, `siege_block: float` (fraction cancelled) | E2 |
| `stance_fired` | `stance_id: String`, `active: bool`, `beat_id: int`: a stance's `active` changed, at the beat `beat_id` (its `fired_beat_id`, §5.11), for every stance, on or off (v8, E3-1: `active` is the condition alone). Raised by the core step's stance step (§3 step 1), at most once per stance per `stance.hold_s`; stamped with the step's `t`, after that step's realm events inside it | E3 (live from E3-1) |
| `loot_banked` | `run_id: int`, `fort_id: String`, `relics: int`, `essence: int`, `blueprints: Array[String]`, `minted: Array[String]` | E1 |
| `vei_result` | `run_id: int`, `won: bool`, `fronts_cleared: Array[String]`, `relish_deaths: int`, `backlog_after: float` | E1 |
| `run_ended` | `run_id: int`, `kind: String` (`raid`\|`boss`), `outcome: String` (the exit it ended in: `retreated`, `warden_beaten` or `relish_died`; a boss run's is `retreated`), `cause: String` (`gap`): a gap above `idle.gap_s` in the open game ended the open run (IDLE I5; §3). Queued first, before the end's writeback events (`loot_banked`, …) and the gap's catch-up, so the dungeon scene knows to leave (Phase I). A load's end of a saved run raises none (no scene is on it) | E2b-2 (v6, T3.3c) |
| `away_report` | `away_s: float`, `capped: bool` (as `view_away`'s): a reporting catch-up ended and its report is in `view_away` (§5.19). Queued once per report, at the catch-up's end (its `t`), after the run's end's events and none of the catch-up's (they are the report's). The cue for an on-screen scene to re-read its views (above) | E2b-2 (v6, T3.3c) |
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
| `party` | Array[Dictionary] | big undead in party order: `{uid, name, kind, role, stats: {power, beef, wits, presence, speed}, filled_slots: int}` (`filled_slots` v8, E3-3: §5.12's) |
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
| `death_ends` | Dictionary | v6 (E2b-2 T3.3c): what a death that ends this run ends in, `{outcome: String, respawn_s: float}`: after any phylactery revives (in place, at most `phylactery_max_per_dungeon`), `"clone"` when a clone is ready (she wakes at Covington from it) else `"unmade"`, and its respawn time (E3-2, v8: `backups.clone_respawn_s` or `unmade_respawn_s`; until E3-2 a death respawned at once, 0.0). It is the death that ends the run, so it skips view_backups' phylactery step (§5.13: `view_backups().death` reads `phylactery` while a charge is left), and it is never `phylactery` (`Results.validate`, §8.4): with no charge it is `view_backups().death`'s `outcome` and `respawn_s` at issue, and with one the step after it. The run-ending death then does exactly this (`relish_died`, `dead_s_left`), by the clones ready when the result is applied. The death card's number; the dungeon falls back to text without one when it is absent |
```gdscript
{v: 2, kind: "raid", run_id: 1, seed_rev: 512, rng_seed: "7203661890244157873",
 fort: {id: "old-sluice", name: "Old Sluice", tier: 1, cap: 80.0, first_clear: true, first_dungeon: true,
        clears_since_retaken: 0, yield_mult: 1.0},
 living: 61.2, dead: 3.1, undead: 6.4, garrison_units: 0, garrison_in_mass: 0.0, garrison_mass_div: 10.0, starter_units: 8, party: [],
 digest_q: 1.2, phylactery_charges: 0, phylactery_max_per_dungeon: 1, clones_ready: 0,
 warden: {archetype: "bellringer", tier: 1}, warden_spec: {}, loot_table_id: "t1.bellringer",
 loot_hint: "a husk and a blueprint", chest_husk: true, watchtower: false, relish_hp: 30.0,
 death_ends: {outcome: "unmade", respawn_s: 600.0}}
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
| `fronts` | Array[Dictionary] | `{id: String, need: float, have: float, assigned: Array[String]}`, per `FRONT_IDS`. Live from E3-5 (v8; 0.0 and 0.0 before, so the fight computed them): `VeiFronts.have_need(VeiFronts.info_from_boss_seed(seed), vei.json)`'s `need` and `have`, the fight's own recompute from this seed, exactly; they are `view_vei`'s at issue (§5.14: the same backlog, pool, q and party). `assigned` is `cmd_assign_front`'s echo; there is no `cleared` or `counted` here |
| `fronts_required` | int | `vei.fronts_required` |
| `party` | Array[Dictionary] | a big-undead entry (with `filled_slots`, v8) plus `front: String` |
| `phylactery_charges`, `clones_ready` | int | the backups the fight may spend (§8.2) |
| `relish_hp` | float | |
| `death_ends` | Dictionary | v6 (E2b-2 T3.3c): what a death that ends the fight ends in, `{outcome: String, respawn_s: float}`. Each death spends a phylactery charge, then a clone (§8.2, MECHANICS §6), so a death ends the fight only once none is left (a final death): `"unmade"` always, with its respawn time (E3-2, v8: `backups.unmade_respawn_s`, 600; 0.0 until E3-2). The rule is `view_backups().death`'s past the phylactery step (it is the death that ends the fight, never `phylactery`) with no clone ready. (§8.3 boss step 4's death reads the clones left after those spent, so a final death with a clone still ready would wake from it; the boss scene never sends one) |
```gdscript
{v: 2, kind: "boss", run_id: 9, seed_rev: 21950, rng_seed: "-3317425092215838120",
 backlog: 18450.0, living_pool: 380.0, odds: 0.61, sign: 1, drain_s: -1.0, digest_q: 2.6, vei_capacity: 50.0,
 fronts: [{id: "giants", need: 24.0, have: 26.5, assigned: ["u4"]}, ...4], fronts_required: 3,
 party: [{uid: "u4", name: "Old Gristle", kind: "hulk", role: "brute", stats: {...}, front: "giants"}, ...],
 phylactery_charges: 1, clones_ready: 1, relish_hp: 30.0, death_ends: {outcome: "unmade", respawn_s: 600.0}}
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
| `warden_beaten`, `retreated`, `relish_died` | bool | **exactly one** is true: the exit. **Window close** (IDLE I5): a close during the warden's victory beat (warden beaten, chest open) emits `warden_beaten` with its flip, because the win happened while the player was there; a close during the death beat stays `relish_died`; a mid-run close is a `retreated`. |
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
   - the fort flips: `fort_flipped`, held with a grace of `flip.hold_s · (1 + flip.tier_mult ·
     tier)`, then contested (MECHANICS §3.4, v6);
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

   A held fort's raid that cleared its counter-garrison then raises `counter_garrison_cleared
   {fort_id, killed_mass}` (§6; v6): the run records whether its fort was held when it began, the fort
   must still be held when the result is applied (one Vei retaked during the raid banks its loot as a
   retreat does, with no event and no yield spend: the retake's `yield_c` of 1 stands), and
   `killed_mass` is step 1's clamped kill.

   `fort.first_clear` and the run-wide `first_dungeon` flag clear only when `warden_beaten` is true
   (api-request #15). A death or a retreat leaves both set, so the next first run still gets the
   starter husk and the guaranteed blueprint.
9. `party_lost` big undead are removed. `phylactery_charges −= revived_in_place` (clamped at 0), with one
   `relish_died{outcome: "phylactery", in_place: true, at: the fort, respawn_s: 0.0}` per revive (E3; live from
   E3-2, v8), queued after `loot_banked` and the flip's or clear's event, before a run-ending death's.
10. If `relish_died` (E3, MECHANICS §7):
    - **A clone is ready:** `outcome: "clone"`. She respawns at Covington after
      `backups.clone_respawn_s`.
    - **Otherwise:** `outcome: "unmade"`. There is a morale shock, and the respawn comes after
      `backups.unmade_respawn_s`.
    - In both cases the **whole party** and the unbanked loot are lost (the scene already dropped
      loot found since the last checkpoint), the fort doesn't flip, Relish is `dead`, then
      `relish_respawned`. Nothing in the town or the realm resets (A8).
    - **Live from E3-2** (v8; `StateRuns.death`): the clone spent is the lowest ready vat, emptied back to 0
      (then a spare clone); `unmade` adds `morale.death_shock` (`TownSim.add_shock`). She is `dead` at the
      fort with `dead_s_left` the outcome's `respawn_s` and `respawn_with_clone`, and the backups step (§3
      step 6) wakes her at Covington when it has passed. Until E3-2 (the E1-safe rule) she respawned home at
      once.
11. If she didn't die, Relish is `at_fort` at that fort. The run closes.

(E1's step 12, the legacy army parity, and boss step 6 below were removed at E2a with the legacy
economy.)

**Boss.**
1. If `won`: set `won = true`. The backlog is unchanged.
   If lost: `vei.undead_queue ×= vei.loss_backlog_keep` (0.35 kept), and the whole party dies
   (MECHANICS §6).
2. `party_lost` big undead are removed.
3. `phylactery_charges −= backups_spent.phylactery`; `clones_ready −= backups_spent.clones` (both
   clamped at 0; the clone is the lowest ready vat, E3-2); one `relish_died{in_place: true}` per spent backup (live
   from E3-5, v8): `{outcome: "phylactery", in_place: true, at: "vei", run_id, respawn_s: 0.0}` for each of
   `backups_spent.phylactery`, then `{outcome: "clone", ...}` for each of `backups_spent.clones`, the order the fight
   spends them (`VeiFronts.next_backup`). They are queued after `vei_result` (step 5) and before a final death's
   `relish_died`, as a raid's revives follow its `loot_banked`: `vei_result`, the revives, the final death.
4. A final death (`relish_deaths == s + 1`) gives `outcome: "unmade"` (MECHANICS §7), and she is
   `dead`. Otherwise she is `at_vei`. A final death follows raid step 10's rule (from E3-2 the shared death
   rule, `StateRuns.death`, judged at 0 clones, the seed's `death_ends` rule: a clone grown in a vat while the fight
   ran is not the fight's backup and stays ready, unspent. So `unmade`, `dead` at Vei
   for `backups.unmade_respawn_s` (600 s), the morale shock, then `relish_respawned`; `relish_died{outcome: "unmade",
   in_place: false, at: "vei", respawn_s: 600.0}`).
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

The seeds' optional keys (v6, E2b-2 T3.3c) are checked only when present: `death_ends` must be `{outcome:
"clone" | "unmade", respawn_s: float ≥ 0}` (`range:death_ends.outcome` for another outcome). A seed without
it is valid.

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
| `game_id` | String | optional, additive at API v4: `view_hud.game_id`. A save without it (v1, or v2 from before v4) gets it computed from its `seed` at load. |
| `rng` | String | RNG state |
| `t` | float | sim seconds (keeps event `t` monotonic across a load) |
| `acc` | float | the tick accumulator's remainder |
| `next_run_id`, `next_uid` | int | counters (§4.5, §1.3) |
| `applied_runs` | Array[int] | the last 32 applied run ids |
| `relish` | Dictionary | `{state, at, target, pos: [x, y], heading, dead_s_left, respawn_with_clone}`, plus `returned: {fort_id, cause, t}` (v6, E2b-2 T3.3c: `view_relish().returned`), optional, written once there is one; a save without it loads `{}`, and one naming an unknown fort is `corrupt`. State is never `in_dungeon` or `in_boss`. |
| `valve` | Dictionary | `{target: {work, war, flood}, current: {work, war, flood}}` |
| `realm` | Dictionary | RealmSim: forts (array with ids: masses, the hold, flip and clear counts), Vei, tithe, simulacra |
| `villages` | Array[Dictionary] | `{id, owner}` |
| `town` | Dictionary | TownSim (`TownSim.to_dict()`: stocks, buildings with their staff caps, ladder, convoy, forge, morale, rates, pending events) plus GameState's `tier`, `haul.target` and `work_pending` |
| `stances` | Dictionary | toggles and hold timers, and from v8 (E3-1) the optional `state` (below) |
| `inventory` | Dictionary | husks, remnants, blueprints, relics, essence, `simulacra_ready` (from E3-4 optional on load: an int when present, else `corrupt`; absent it reads 0) |
| `big_undead` | Array[Dictionary] | the entries, with `place` and `front`, and from v8 (E3-3) `filled_slots: int`, optional: an int when present (else `corrupt`), and a record without it loads as 1 (§5.12) |
| `party` | Array[String] | |
| `backups` | Dictionary | `{phylactery_charges, clones_ready, vats: [{slot, staffed, grow}]}` |
| `readout` | Dictionary | the `diff` EMA, the `q_raise` EMA |
| `ledger` | Dictionary | sources and sinks so far, and the currency tally `stores` (v6) |
| `won` | bool | |
| `stats` | Dictionary | counters (raids, deaths, raised total, and from E3-4 `sims_built`: the simulacra crafted) |
| `cleared_forts` | Array[String] | forts whose first clear is spent by a win (sorted) |
| `first_dungeon` | String | the first dungeon's id until a won raid result (`warden_beaten`) clears it, then `""` |
| `pending_retreat` | Dictionary | optional, additive at v6 (E2b-2 T3.3c; IDLE I5, api-request #4), written only while a run is open: `{run_id: int, kind: String, fort_id: String, seed_rev: int, loot: {relics, blueprints, husks, remnants, essence} (§8.1), outcome: String}`, the run's last checkpoint (`cmd_run_checkpoint`, §4.5), or empty loot and `"retreated"` when it has none (a boss run never has one; its `fort_id` is `"vei"`). `from_dict` ends the run with it (below). Present, it must match: a known `kind` and `outcome`, a raid's fort a known fort with `relish` saved `at_fort` there, a boss's `"vei"` with her `at_vei`, and loot `Results.validate` takes; else the save is `corrupt` |
| `queue` | Array[Dictionary] | optional, additive at v6 (E2b-2 T3.2; `SAVE_VERSION` stays 2, as `game_id` did): the build queue, `[{building_id: String, lot_id: String, upgrade: bool, waited_on: String}]` in order. A save without it loads an empty queue; `waited_on` is optional (`""`). An entry of another shape makes the save `corrupt`; one naming a building or lot today's config lacks, or past `queue.max_len`, is dropped with a warning |

**What each block holds** (v2; additive keys and E3 placeholders):
- `realm`: `forts` (array in world order: `id`, `living`, `undead`, `dead`, the hold, `flipped_count`,
  `clears_since_retaken`, and the per-second rates `r_in`, `r_drain`, `r_shipped`, `r_dead_out`,
  `r_raised`, which the views show), `cov`, `vei` (masses and rates), `simulacra`
  (`{fort_id, charges, rate}`), `elapsed`, `cleared_total`, `raised_by_sims`, and `tithe`. Positions,
  names, caps and tiers come from config.
- `realm.forts[]`'s hold (v6, MECHANICS §3.4): `held: bool`, `grace_s: float` (grace left; 0 once
  contested) and `zero_s: float` (seconds the garrison has sat at 0 since it last didn't). All three
  are optional on load and checked for type when present. A save from before v6 carries `held_s`
  instead, read only on load: `held_s > 0` loads held with `grace_s = held_s` and `zero_s = 0`; a
  fort with neither key loads unheld. The fixtures carry `held_s` and load this way (midgame_2flips:
  Ashgate and Old Sluice held, 374.5 s of grace each).
- `realm.forts[]`'s loot yield (v6, MECHANICS §5.3): `yield_c: float` (the yield just after the
  fort's last clear that paid loot) and `yield_t: float` (the sim time of that clear). Optional on
  load: a save without them loads `yield_c` 1, the yield it showed.
- `realm.tithe` (E2a, RealmSim's countdowns): `{started: bool, next_s: float (to the next wave),
  next_id: int, warning: {} | {wave_id: int, fort_id, eta_s, surge}, wave: {} | {wave_id: int,
  fort_id, s_left, duration_s, mult, delivered}}`. Loading the E1 placeholder `{warning: {wave_id,
  fort_id, eta_s, surge}}` gives a running cycle with that warning pending, `eta_s` read as the time
  left. An empty block starts the clock at load when a fort has `flipped_count > 0`, else idles. A
  `warning` or `wave` naming an unknown fort makes the save `corrupt`.
- `town` (v2): `workers`, `bodies`, `gold`, `bone`, `living`, `morale`, `shock`; `buildings`
  (`[{lot_id, building_id, level, state, progress, staff_cap, unpaid_s, build_level}]` in lot order;
  `state` is `constructing`, `active`, `idle` or `unpaid`, and from v8 (E3-1) `thrift`, a building the Thrift
  stance idles, which `view_town` shows as `"idle"`); `ladder`; `haul: {target, current,
  convoys: [{fort, phase, t, trip_s, load, crew}]}` (at most one convoy); `forge: {level, progress}`
  (the q forge); `rates` (TownSim's last step, which the views show); `pending` (events a command
  queued that no substep has emitted yet, e.g. a `building_started`); and GameState's `tier` and
  `work_pending` (WORK in flight to TownSim: 0 in every save from E2b, which delivers each step's
  WORK in that step; an older save's value is delivered with the next step's). `morale`,
  `shock`, `rates` and `pending` are optional on load (TownSim's defaults: morale at its base, no
  shock, zero rates, nothing pending). A building on an unknown or repeated lot, of an unknown id, in
  another state or at a level the building lacks, a ladder that is not a permutation of `JOB_IDS`, or a
  haul target or convoy naming an unknown fort makes the save `corrupt`. A load restores the saved
  building states and recomputes the staffing; the first substep restaffs.
- `stances`: `on` (oldest first) and `hold` (E3 timers: from E3-1, stance id → the seconds left of its hold,
  for each stance held; a key that isn't a stance, or a hold at 0, is dropped on load). From v8 (E3-1) the
  optional `state`: `{stance_id: {active: bool, fired_beat_id: int}}` for each stance whose condition has
  changed at least once, written once there is one (typed when present, else `corrupt`). A stance not in it
  loads inactive and never fired, so a save without it, the fixtures' `{hold: {}, on: []}` and every save before
  v8, loads as "nothing held, never fired", and the fixtures come back as they are. The hold and `active` are
  saved so a load continues the hold where the save left it (a catch-up from a save then changes the stances
  when continuing would have); `fired_beat_id` so the stances read the same after a load (a beat is
  `floor(t / beat_s)` of the saved `t`). Thrift's idled buildings are saved in the town block, as state `thrift`.
  Which stances act is not saved: a load recomputes it from these and gives TownSim their effects.
- `backups`: `phylactery_charges` (E3, stored as is), `clones_ready` and `vats` (one per vat slot). From E3-2 (v8)
  each vat's `grow` is read back as well as `staffed` (until E3-2 only `staffed` was, and `grow` was written 1.0 for
  a slot a clone covered), and `clones_ready` is written as the total, the vats at 1 plus the spare clones. **The
  old-save rule** (MECHANICS §7): the vats' `grow` is the truth, and a `clones_ready` above the vats at 1 loads the
  excess as spare clones outside the vats, so a load never loses a clone (a v1 save's legacy vats, a save whose Chapel
  was demolished); one below them reads the vats. The fixtures agree already (pre_vei: 1 clone, its vat 0 at 1.0)
  and load as they are. No key is added, so the save shape and `SAVE_VERSION` are unchanged.
- `readout`: `diff_ema` (the differential's EMA) and `q_raise_ema` (E2a: `ema_score`, the
  mass-weighted circle EMA behind `q_raise`, MECHANICS §2.2; a new game starts it at 50, and an E1
  save's placeholder 0.0 loads as 50, which the EMA can never reach exactly from 50).
- `ledger`: `{sources, sinks, stores}` as `ledger()` shows them (§4.7), every key. `stores` (v6, E2b-2
  T3.2) is optional on load and typed when present (`{store: {overflow: float}}`); a save without it reads
  0 overflow. A block with
  `sources.opening` is read back key by key (a missing key reads 0). One without it (a save from before
  `api_version` 3: E1, E2a, older fixtures) keeps only `sinks.dungeon`, and `opening` becomes what the
  save holds at load plus that sink, so the count balances from the load on.
- `inventory.simulacra_ready` is GameState's stock of simulacra crafted and not yet planted (E3-4; until E3-4 it was
  written as 0 and not read). It is written as it stands and read back; a save without it reads 0, and the fixtures
  (0) come back as they are.
- `villages` owners are `player`, `vei` or `none`. Floats are written at 15 significant digits (§10 A12).

**Not saved:**
- `rev`, `debug_enabled`, `save_dir`, the event queue;
- `time_scale` (a load starts at 1) and `paused` (a load starts unpaused);
- the open run itself (`in_dungeon` is never saved): it is written as `pending_retreat` (v6, T3.3c),
  which a load ends as a retreat from its last checkpoint;
- the last substep's rates outside the fort, Vei and town blocks: `view_hud`'s `split` and mint
  `rate`, `view_rates`' `mint`, `work`, `war`, `flood`, `corpses` and `backlog` (the haul's part of
  `corpses.out` is TownSim's, saved), `view_vei`'s raw `diff`, and the three lanes
  out of Covington's own rates (FLOOD and WAR fallen through to Vei, WORK). Since v6 (E2b-2 T3.3b, the
  load flash) a load rebuilds the split and the WAR dispatch as the last substep left them
  (`GameState._restore_dispatch`): the mint from TownSim's saved worker inflow and the valve (the next
  step's mint when the WORK share is 0), the muster from its saved rate, and each fort's dispatch weight
  and limit from its saved `r_in` and Relish's tide. So `view_hud`'s split and mint rate, `view_rates`'
  `mint`, `work`, `war` and `flood`, those three lanes and the held forts' readouts (§5.5, §5.17) read
  what they read before the save, to its 15 digits. `corpses`, `backlog` and `diff` still read 0 until
  the first substep after a load. Lane callouts are not saved either;
- the influence field: after a load it is pre-warmed from the loaded realm, as a new game does
  (`_prewarm_field`, including `field.flush()`), and village owners are restored from `villages`.

**Open runs** (IDLE I5). `to_dict()` during a run writes Relish as `at_fort` at the run's fort (or
`at_vei`) with no run, and since v6 (E2b-2 T3.3c) the run as `pending_retreat`. `from_dict` (so `cmd_load`
on both paths, and `cmd_debug_load_fixture`) ends that run after the state is restored, before any
catch-up, through the normal writeback as a result of its outcome (§4.5 `cmd_run_checkpoint`): a raid
reopens as it stood (its `run_id`, `seed_rev` and fort, Relish in its dungeon) and ends. **What the
writeback needs and where it comes from:** the result is built from `pending_retreat`'s `run_id`,
`seed_rev`, `fort_id`, `loot` and `outcome`; the seed it reads is `view_dungeon_seed`'s rule
(`StateRuns.dungeon_seed`) at the load, whose fields the writeback reads are as the run had them: the
party (the save's: no command changes it while a run is open), the phylactery stock and its per-dungeon
cap (from E3-4 `cmd_craft` can add a charge while a run is open; the retreat revives no one, so it spends none and
its check, revives ≤ the seed's charges, holds at 0 whatever the stock), and `garrison_in_mass` (the end result's `garrison_mass`
equals it, so the fort's undead don't move). Its events are queued as live, stamped at the save's `t`, and
`rev` rises by 1 more. A boss run needs nothing: the save holds it forfeited (Relish `at_vei`, no run, the
party intact). A save without `pending_retreat` (written before T3.3c) forfeits its run as before: no loot,
no flip, no event, the party intact.

**Catch-up** (v6, E2b-2 T3.3b): only `cmd_load` catches up the time since a save (§4.1), from the file's
`saved_at`. `from_dict` reads a dict, not a file, and `cmd_debug_load_fixture` loads a fixture, which has
no meaningful `saved_at` (it is a state, not a session's save), so neither catches up.

**`from_dict(d: Dictionary) -> {ok: bool, reason: String}`**
- **Reasons:** `bad_version` (`v` above `SAVE_VERSION`, or the migration failed), `corrupt` (missing
  keys or wrong types).
- It resets in place, clears the event queue, bumps `rev`, ends a `pending_retreat`'s run (above; one more
  `rev`, its events queued), and keeps
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
  seconds) and `summary: String`, which `from_dict` ignores. `cmd_load` reads `saved_at` for its
  catch-up (§4.1).
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
| `midgame_2flips.json` | About 1 h in, Village tier (it rises by itself on the first substep): the start set plus a House, a Well and a Bone Mill (lots 5–7), which ran the hour. Old Sluice and Ashgate are held, with a tithe warning on Ashgate. Vei's backlog is hand-shaped to 4000 (odds ≈ 0.25), since an hour of the full mint would leave it near `pre_vei`'s. Relish is travelling Covington → Greywall. 2 husks, 4 remnants, 3 big undead (one in the crypt, one as a foreman, one sieging Ashgate), a haul convoy in flight (to Greywall), 1 owned blueprint (`embalmer`), forge level 1, relics 3, essence 14. |
| `pre_vei.json` | About 3 h in, City tier: 20 buildings (the start set with the pit and the market at level 2, three more pits, two houses, a well, a bakery, a bone mill, a statue, a Chapel of Vats, a forge, an inn, a graveyard, a watchtower, the Walls and the Reliquary, whose blueprint is owned), up for the last 30 min and none unpaid. Odds ≈ 0.6, a party of 4 big undead assigned to fronts, one each (the assignments are in the fixture; from E3-5 the fronts are live, and at the shipped `vei.json` none is met: have / need giants 5.6 / 26, swarm 17.2 / 24, carvers 5.3 / 30, raw 25.0 / 58, so 0 of 4, short of the 3 of 4 this fixture was meant to stand for, BALANCE §1's Vei-ready row; until E3-5 they read 0), 1 phylactery charge and 1 clone ready. Relish is `at_vei`, so `cmd_begin_boss()` succeeds, and `won` is false. |
| `v1_day1.json`, `v1_midgame_2flips.json` | The E1 (save v1) `day1` and `midgame_2flips`, kept as they were for the v1 → v2 migration tests. Not loadable by name. |

- Each fixture is a `to_dict()` at the current `v`. Fields from E2/E3 systems are written by the
  generator until those systems produce them, and the fixtures are regenerated or migrated in the
  same commit as any save-shape change.
- A test loads all three after every change (save compatibility), and checks that each file is exactly
  what `to_dict()` gives after loading it (the placeholders survive).
- They are produced by `tests/fixtures/make_fixtures.gd` (commands, debug commands and
  `TownSim.place_building` from `cmd_new_game(1)`, then the fields no command can make yet written
  into the state or the dict: `realm.tithe` on `midgame_2flips`; the Reliquary blueprint,
  `backups.phylactery_charges` and `backups.clones_ready` on `pre_vei`). The town tier is no longer
  written: it rises by itself while the generator runs the sim (Village on `midgame_2flips`, City
  on `pre_vei`), and the generator stops if it does not. `midgame_2flips`'s Vei backlog is a
  hand-shaped value (4000, set with `cmd_debug_grant` after the hour): left alone, an hour of the
  full mint leaves odds near `pre_vei`'s, which does not look mid-game. Run it
  by hand when the save shape changes (it takes about 5 minutes). The `realm.tithe` it writes on `midgame_2flips` is still the
  E1 placeholder `{warning}`; from E2a the load maps it into the tithe state (a warning pending on
  Ashgate, 150 s to the wave), so the file holds the full E2a block (§9.1).
- From `api_version` 3 each fixture carries its live ledger (§4.7): `opening` is the new game's, and
  the generator's debug grants book to `sources.debug` (negative on `midgame_2flips` and `pre_vei`,
  whose hand-shaped backlogs are below what the hours left).
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
| A13 | **Fixtures keep E2/E3 fields as stored values.** `realm.tithe`, `stances.hold` (live from E3-1: the holds left; the fixtures' is empty), `backups.phylactery_charges` and `readout` are saved and restored as is. E1 views show `phylactery_charges` (backups, relish, inventory and both seeds) from the stored value; the rest are read by no E1 view. The fronts are not stored: from E3-5 they are computed from the state (§5.14), and read 0 until then. | A fixture can carry them now, and E2/E3 read them without a save-shape change. |
