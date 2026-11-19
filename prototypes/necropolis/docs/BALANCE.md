# Necropolis: balance (v2)

Targets, how they're measured, and starting numbers. Every number here is a *starting* value; the
configs are the truth. When tuning moves a number, update this file in the same commit.

**Idle model:** `IDLE.md` (2026-11-13, from Shawn's answers) wins over this doc wherever they conflict.

## 0. Start state (`economy.json` `opening.*`)
| item | value |
|---|---|
| buildings | Crypt, 1 Raising Pit, Charnel House, small Market (2 stalls) |
| lots | 24 (Hamlet uses the first 8) |
| gold / bone / bodies | 80 / 30 / 40 |
| workers | 12 (the steady state at the default valve is about 34, 40 once the pits are fed, so the stream visibly grows; the town keeps 17, its slots plus `worker.idle_cap`, and musters the rest; it was 55 / 64 at work 0.40) |
| living | 10 (`living_cap` 16 from the crypt district's huts) |
| valve | work 0.25 · war 0.60 · flood 0.15 (E4, the run's manager's A1 day-1 ruling, 2026-11-17; was 0.40 · 0.45 · 0.15). Under A1 the muster goes to Vei, and below a WAR share of about 0.54 (`opening.bone_edge.war_share`, `view_hud.bone_war_share`) a new game's pits eat every body and the mill makes no bone (MECHANICS §4.2's table); 0.60 keeps a margin over it |
| Relish | home, phylactery 0, no clones or vats |
| first dungeon | Old Sluice (tier 1, Bellringer), flagged "first"; starter party `opening.starter_party` = 8 units; the chest holds a husk and the first blueprint |

## 1. Pacing targets (superseded by IDLE.md §7: days of sessions; the early-session rows still hold)
| moment | target |
|---|---|
| first stream response to the valve | under 5 s |
| first dungeon descent | under 4 min |
| one dungeon run, entry to exit | 3–6 min real time |
| a building affordable | every 2–4 min early, 5–8 min late |
| first big undead | under 15 min (the starter husk) |
| first warden beaten (fort flipped) | under 10 min |
| first tithe wave | about 12–15 min (after the first flip) |
| town reaches Village / Town / City | about 20 min / 1 h / 2 h |
| Vei-ready (readiness ≥ 0.6 and 3 of 4 fronts met at her full pool, IDLE §8; the readiness was `view_vei.odds` until Phase I P3's odds split) | **2.5–3.5 h** |
| idle | see IDLE.md §7: most growth happens while away |

## 2. Lever-ablation targets ("the economies feed each other")
From the autoplayer (§4): hours to Vei-ready with one lever removed, against the active profile.

| removed lever | must cost at least |
|---|---|
| **the valve** (left at default all game) | **+40%** |
| **a static valve schedule** (a timetable fixed in advance) | **+25%** (otherwise the macro is a solved opening book) |
| **Relish's tide and redirect** (she only leaves home to descend) | **+30%** |
| dungeons (never descends) | never ready (relics gate the City tier, phylactery and forge levels) |
| town building (no new buildings) | +40% |
| circle quality (always 55 instead of 85) | +15% |
| defending against tithe waves (never) | +15% |
| the job ladder and stances (defaults only) | +5–10% (defaults must be decent) |

If any lever costs less than its target, it is decorative. Fix the design before tuning anything
else.

**The ablations as built** (E3-6b's autoplayer, `tests/autoplay/autoplayer.gd`; IDLE §8). Each runs under the sessions
profile and runs the sessions baseline beside it. It prints the delta in days to Vei-ready, or, when either run never gets
there, the fronts met and the backlog at the end (with relics, buildings and levels).
- **(a) Never raid held or refilled forts** (IDLE §8's extra row, at least +20%; `autoplay_ablation_held`). The bot's raid
  pick skips every held fort, so a fort is raided until its warden falls and is then left until Vei retakes it. A refilled
  fort is a held one (IDLE §7), so this is the whole rule. Nothing else in the policy changes.
  **E4 step 6, an accepted miss** (the run's manager, 2026-11-17 11:39 ruling 1; for the step 9 vision review). The
  target was a 20–25% cost in levels at day 8 (the 2026-11-16 16:18 ruling (c)). It costs **78%** at 3379877 (28
  levels against sessions' 128) and **77%** with the retake's kept yield and the craft at 500 bone, 3 remnants (27
  against 116; one seed, 8 days). The cause is a relic wall, not rich held raids: once every fort it can reach is held,
  the no-held bot has nothing it may raid (7–8 raids in 8 days against sessions' 146–159), so its queue waits on relics
  from day 1, it never gets the bigs to reach t2, and its town stays at tier town with a 550 bone cap. Shawn's throttle
  is in (`loot.recover_s` 8 h, `loot.reclear_decay` 0.5: a held clear pays 0.32 relics at a mean yield of 0.72, a flip
  2.2–2.7). **No relic cap is shipped:** 12 a day gave 106 levels and Vei-ready day 6.33 (cost 74%), 6 a day 56 levels
  and day 7.0 (52%), and the ablation banks 12–14 relics in 8 days under any cap, so a cap only slows sessions. A relic
  source outside raids (an idle trickle) for a player who holds everything goes to step 9's vision review; it is not
  built.
  **E4 step 9, the idle relic trickle, built and kept; the miss accepted** (the run's manager's rulings on step 9 (3),
  2026-11-17 12:45 and 14:24): one relic per 12 h (`economy.json` `relic_trickle.period_s`) while every fort at or below
  the highest tier ever flipped is held (MECHANICS §2's relics row). Measured at 553a66f, with the odds lever (one seed, 8 days): it
  **never pays** in sessions, continuous or ablation_held. Sessions' and continuous's rows are identical to the runs
  without it (Vei-ready 6.0001 and 4.8291, so the ruling's keep test passes), and ablation_held still makes **27 levels
  against 116 (77%)**, over the 60% line, so the miss is accepted and reported. The cause: the no-held bot doesn't stop
  at t1. Its 8 raids are 4 at t1, 2 at t2 and 2 at t3 (7 flips, 4 retakes), so its highest tier flipped is 3 (at most one of
  its raids was lost, so at least one t3 raid flipped), a tier it can't hold. No third lever, per the ruling.
  **Why it never pays, probed** (the step 9 review's item 6, E4 step 10; tools21's tr_probe at b475eb3, one seed, 8
  days, logged at each session start): no raiding profile meets the condition. Sessions flips up to t3 (Mourner's Gate)
  in its first 20 min session and t4 on day 5, holding 3–6 forts, with 3–6 forts at or under its highest tier unheld at
  every session start (from day 2: Hollow Redoubt, Pale Bastion and Mourner's Gate, t3). The no-held bot sits at t3
  holding the 3 t1 forts, with 6 t2–t3 forts unheld. Sessions held 24 h closed from day 1's end pays 0 (its highest tier
  is already 3). While it pays it is 2 relics a day by construction, against sessions' 93 raid relics in 8 days (about
  12 a day). A finding for the manager, not tuned
- **(b) The bone-priced buildings removed** (`autoplay_ablation_bone`; rebuilt in Phase I P3, R-d). The spine's §4 row
  reads "bone-priced buildings removed costs 15%+". The table above has no such row: the lever is §7's "bone buys the
  dead's buildings". It is built as a config variant on fresh GameStates (`Autoplayer.cfgs("no_bone_buildings")`), over
  §7's list (the raising pit, charnel house, bone mill, stables, graveyard, embalmer and forge):
  - none of them levels (`max_level` 1; every level of theirs costs bone);
  - none with a bone price can be built: their blueprint is one no fort drops, so each reads `needs_blueprint`, and the
    bot doesn't park a gate no clear can lift (`Autoplayer._droppable`; every shipped blueprint drops, so no other
    profile changes);
  - the start's pit and charnel house stay at level 1, and the Bone Mill (60 gold, no bone) can still be built. Bone
    still buys the living's buildings (the Market's levels, the House's) and the Crypt's levels.

  "Removed" is read as the rows above read it: the lever is taken out, not replaced by a gold price. **Until P3 the
  variant set those bone prices to 0** (`no_bone_prices`). A price of 0 removes a brake, so that variant could only speed
  the game up: 0.83 days (14%) sooner at c15f874, and 0.17 days (3%) sooner at 4ddc25c (Vei-ready 5.0001 against
  sessions' 5.1667; 156 levels against 126 at day 8). The rebuilt variant at 4ddc25c's tree with P3's harness (one
  seed, 8 days): **never Vei-ready**, 10 buildings and 26 levels against sessions' 24 and 126 (79% fewer levels), 2 of 3
  fronts met, the backlog 98% short. Without new pits the mint stays one pit's, so this reads the dead's buildings as a
  whole (the pits' mint growth with them), not bone's price alone. The lever is defined and far over 15%.
- **The sensitivity pass** (`autoplay_sensitivity`; §8): the sessions profile at the frozen bot's death rates
  (`opts.deaths` `"frozen"`) instead of the typical human's.
- The table's other rows (the valve, a static valve schedule, Relish's tide, circle quality, defending, the ladder and
  stances) have no profile in E3.

## 3. Risk targets
- A dungeon at or below the party's tier: under 10% chance Relish dies with circles around 70.
  Two tiers above: over 40%. The first dungeon: under 5%.
- An unmade death costs about 10 minutes of progress: the respawn, the morale dip and the loot lost
  since the last checkpoint.
- Final test at odds of about 0.6 with 3 of 4 fronts met: about 60–70% win with 2 backups, under
  40% with 0.

## 4. How it's measured
- **`tests/run.sh`** imports, then runs. The default suites include a **1 h smoke** of the active
  profile.
- **`tests/slow/autoplay.gd`**: the 4 h profiles (idle, active, each ablation, static schedule). It
  takes several minutes, so it runs on demand and before every balance commit.
- **The autoplayer** drives the real GameState through commands only. The active profile:
  - reacts to the sign and the drain time;
  - moves Relish (tide and redirect at the richest corpse fort, home for the slab, defending against
    tithe warnings);
  - descends on a cadence;
  - builds from a priority list;
  - keeps the default stances.
- **Dungeon stand-in** (`configs/balance_standins.json`): loot, flip chance, duration and death
  chance by tier, party strength and an assumed circle score. Economy ships v0; the dungeon unit
  adjusts the values from real runs. v0 and its resolver: §8 (E3-6a).
- **No unbounded stock:** over a 4 h active run, no uncapped stock may end above 2× its value at 2 h.
  Gold must stay a stream.
- Output: one line per profile, e.g. `[pacing] active: ready 2.9 h · odds 0.62 · fronts 3/4`, plus
  the ablation table.

## 5. Starting numbers
Raw Necropolis units (×1/100 of Realm mass). The keys follow MECHANICS.md; renames from the old code
are marked ⟵ (old name after the arrow). Checked against the configs at the end of E2a: every key
E2a added is here with its value.

| key | start | note |
|---|---|---|
| `opening.valve` | 0.25 / 0.60 / 0.15 | `economy.json` (work / war / flood; 0.40 / 0.45 / 0.15 before E4's A1 day-1 ruling, §0); `directShare` 0.22 is removed |
| `opening.bone_edge.war_share` | 0.54 | `economy.json`: a new game's bone edge, measured (§0, MECHANICS §4.2) |
| `valve.slew_per_s` | 0.10 (L1) | about 10 s for a full swing |
| `field_src_per_pit` | 0.15 | `realm.json` top level (the `field` block is ground's): Covington's field source is `src_main · (1 + field_src_per_pit · pits)` |
| `sim.prewarm_ticks`, `sim.prewarm_dt` | 90, 0.2 s | `economy.json`: the field pre-warm at new game and load |
| `vei_pool_cap` | 600 | `realm.json`; RealmSim and GameState both fall back to 600 if it is missing |
| `P_relish` | 0 | top-level key, kept |
| `P_base`, `P_per_pit` ⟵ `P_per_slab` | 2.0, 6.0 | `realm.json` (renamed at E2a); the start mint is (2 + 6 · 1) · (1 + 0.6) = 12.8 |
| `pit.burn_per_s` ⟵ `slab_bodies_per_s`, `pit.bonus` ⟵ `slab_mint_bonus` | 0.6 mass/s per pit, +0.6 at full feed | burn calibrated so rot alone covers about 60%; hauling covers the rest (the old 0.12 and the ×1.6 multiplier, now written as its +0.6) |
| raising pit `effects.pits` | 1 per level | the pits the mint and the burn count (`buildings.json`; replaces the pit's old `effects.mint` 6 and `effects.burn` 0.6) |
| `worker.mass` | 40 | start inflow 12.8 × 0.4 / 40 = 0.128 workers/s → steady state about 61 |
| `worker.lifetime_s` | 480 | |
| `worker.body_return` | 0.25 | was 0.6, which made hauling decorative (systems review M6) |
| `worker.idle_rot_mult`, `worker.idle_cap` | 0.5, 10 | idle above the cap musters to WAR. At the opening that caps the workforce at 7 slots + 10 = 17, and the rest of WORK musters to WAR until builds add slots. |
| `relish.travel_speed` | 220 px/s | kept (the top-level duplicate `travelSpeed` is gone) |
| `relish.tide_bias` | 3.0 | |
| `relish.raise_rate` ⟵ `raiseRate` | 4.0 mass/s | was 30 (emptied piles), then 1.5 (a wash at low `q`); calibrate against the +30% ablation |
| `simulacrum.rate`, `simulacrum.charges` | 1.0 mass/s, 300 mass | `realm.json`, E3-4, v0: **E4 placeholders** (the run's manager; read REQUIRED, `GameState.REQUIRED`). A planted simulacrum performs Relish's redirect at its fort (MECHANICS §3.6): it raises corpses at `rate` until it has raised `charges`, then crumbles. 5 min of raising, a quarter of Relish's `raise_rate`, at a fort whose corpses keep up; longer where they don't (only the raise spends charges) |
| `relish.home_rot_mult` | 0.7 | |
| `relish.home_stance_bonus` | 1 | extra stance slots while she is home |
| `flip.hold_s`, `flip.tier_mult`, `flip.haul_mult` | 300, 0.25, 1.5 | `hold_s · (1 + tier_mult · tier)` is a flip's grace (375 s at tier 1, 600 at tier 4): no shipping there and no wave targets it (E2b-2; it was the whole hold) |
| `hold.reship_share` | 0.5 | after the grace her reship into a held fort is this × (1 + `tithe.backlog_scale` · odds) of her share `S_vei · cap / Σcap`, not cut to its room: 0.103 to 0.154 mass/s at Ashgate. A garrison holds without waves from `W_c = r_drain · reship / k_kill` of WAR (0.343 at Ashgate, 2.23 at Whitecross; MECHANICS §3.4) |
| `hold.break_s` | 120 s | the garrison sat at 0 this long retakes the fort. With 0.5 and 120 a full wave breaks a settled garrison at Ashgate below 1.033 mass/s of WAR, or below 0.547 with Relish there (0.624 with a siege); Whitecross 3.03, 2.24 and 2.80 (MECHANICS §3.4's band, re-measured at E2b-2 T3.3a). Kept at the starting values |
| `hold.clear_min_living` | 0.05 mass | the dungeon's spawn floor, mirrored (`raid_populate.gd` spawns no living at or under it): a held fort's raid at or under it clears its counter-garrison with nothing killed |
| `hold.safe_horizon_s` | 28800 s | 8 h (the manager's): a held fort's margin reads "will_fall" when its fall clock is under this, and "safe" only when the wave train settles with it unbroken; the train also stops at this much probe time |
| `hold.probe_dt_s`, `hold.probe_s` | 10 s, 600 s | the margin probes' step: the wave train's and the one-wave probe's RealmSim fort step on scratch copies at 10 s steps (catch-up's planned dt; their edges are the sim's at 10 s), the one-wave probe (view_projection's drag) for at most 600 s (the wave, `break_s` and the march-back's decay). About 30 µs per held fort per drag call (MECHANICS §3.5) |
| `hold.train_settle_tol` | 0.001 (× the fort's cap) | E2b-2 T3.4b: the wave train's settled test (MECHANICS §3.5): a fort every compared wave hit must be no weaker than p cycles before, and any other must repeat, within this × its cap in mass (0.08 at Ashgate, 0.52 at Whitecross; a tolerance relative to the value would mean nothing at a garrison or a living count near 0). A fort whose waves' living are gone before the next settles in one cycle; Ashgate at 1.2 mass/s settles in 3 (its living at each wave's start 66.46, 66.96, 66.96: the second step 0.5, the third 0.004) |
| `hold.train_max_cycles` | 4 | the wave train's cap, in cycles (wave start to wave start) after the last grace end or break in the probe (the run's manager: "about 4 cycles; hitting the cap unsettled reads thin, not safe"). midgame_2flips as loaded doesn't settle in 4 (both forts thin); 10 min in, with Old Sluice broken, Ashgate settles in 3 |
| `hold.train_frame_phase`, `hold.train_starve_frames` | 0.5 (of a substep), 30 frames | the train's frame refresh (GameState._train_frame), the build benefit's rule with its own keys: on the frame path it re-probes on a frame with no substep at least this far into the substep interval (the scenes refetch early in it), or, when every frame substeps, after this many such frames in a row. 1.2 ms a probe at midgame_2flips, so it stays off the substep frames (MECHANICS §3.5's cost line) |
| `tithe.period_s`, `tithe.backlog_scale` | 420, 0.5 | waves come faster as the odds rise |
| `tithe.warning_s`, `tithe.surge_s`, `tithe.surge_mult` | 150, 40, 3.0 | |
| `tithe.siege_block`, `tithe.relish_mult` | 0.6, 0.5 | a siege cancels 0.6 of a surge (live from E3-3, read REQUIRED by GameState: flat, one per fort, whatever the big's stats. **E4 step 10 keeps it flat** (the smallest choice, the brief's rule for an open point): one number the margin chip and the forecast credit exactly, and a big's stats already count where it fights (the fronts); scaling it would make the forecast read the big's stats for a lever the player can't see. A second siege at a fort adds nothing; the map's siege menu saying so is a Phase I item); a surge into the fort Relish stands at is × 0.5 (halved) |
| `tithe.march_back_s` | 60 s | living above a fort's cap march back to Vei's pool at `(L − cap) / march_back_s`; past her pool's cap they are lost (`pool_overflow`). Replaces `tithe.overfill` (2.0, E2b T3.0s). At 60 s a full wave leaves at most 701 above the cap, and waves don't stack past one wave's mass even at the shortest period (MECHANICS §3.4) |
| `readout.ema_s`, `readout.sign_eps` | 120, 0.05 mass/s | the sign flips past ±`sign_eps` of the EMA |
| `q.q0` ⟵ `q`, `q.q_forge` ⟵ `q_per_forge`, `q.q_raise_max`, `q.raise_half_mass`, `q.q_max` ⟵ `q_max` | 1.2, 0.1 per level, 0.6, 200 mass, 4.0 | forge steps 0.1 (was 0.25, wider than the knife edge); the circle EMA's half-life is in mass raised, not seconds (`q.raise_ema_s` 600 is gone; IDLE I2) |
| `stall.rate`, `market.shop_rate`, `market.price` | 0.15 /stall/s, 0.03 /living/s, 1 | start: min(2·0.15, 10·0.03) = 0.30 gold/s |
| `town.migrant_rate` ⟵ `migrant_rate_per_town`, `town.leave_rate` | 0.012 /held village/s, 0.004 /s | the old top-level key is gone from `realm.json` |
| `living_cap` | 16 (`opening.living_cap`) + per level: 8 per house, 2 per well, 4 per bakery, 20 per inn, 30 for walls | building `effects.living_cap` |
| `inn.attract` | 0.02 /s per level | the Inn's `effects.attract` in `buildings.json` |
| `morale.base`, `dread_ratio`, `dread_k`, `leave_below`, `death_shock`, `shock_s` | 0.6, 4 workers/living, 0.05, 0.35, 0.3, 600 | |
| `morale.ease_per_s` | 0.005 /s | morale moves at most this much per second; a 0.3 swing takes 1 min |
| amenity `effects.morale` (per level) | well 0.03, bakery 0.04, inn 0.04, walls 0.05, plaza 0.08, statue 0.05 | all six together lift the target from 0.6 to 0.89 |
| statue `effects.death_shock_mult` | 0.5 | each death shock halved while the Statue works |
| `job.haul.carry` ⟵ `gather_carry`, `job.mill.rate` | 14 mass, 0.5 bone/mass | |
| `job.haul.speed` ⟵ `gather_speed`, `job.haul.auto_min_dead` | 140 px/s, 4 mass | the legacy gather speed and threshold (`gather_speed` is gone from `realm.json`); Ashgate (246 px) is a 3.5 s round trip |
| stables `effects.haul_speed_mult` | +0.3 per level | haul speed × (1 + Σ) |
| `job.mill.mass_per_s` | 0.2 mass/s per miller | a level-1 mill (2 millers) turns 0.4 bodies/s into 0.2 bone/s: a 50-bone build in about 4 min |
| `job.forge.rate` | 0.5 work per worker-second | a level-1 Forge (2 smiths) makes 1 work/s |
| `forge.level_work`, `forge.level_relics` | 120 · n work for level n (8 levels); relics 1, 1, 1, 1, 2, 2, 2, 2 | level 1 in 2 min, level 8 in 16 min at a level-1 Forge; 12 relics in all (the relic cap); +0.8 `q` at the top |
| `job.build.rate`, `job.build.slots` | 0.5 work per worker-second, 3 per construction site | a House (60 work) in 40 s, the Reliquary (400) in about 4.5 min; an upgrade takes `build_work · target level` |
| `upkeep.unpaid_hold_s` | 30 s | the least time a building stays unpaid; it resumes once the stock covers 30 s of upkeep |
| `upkeep.shed_order`, building `shed_class` | `decoration`, `passive`, `job`, `war_mill`, `war_haul`, `war_pit` | R1 (the run's manager's rule; MECHANICS §4.3): while a stock can't cover the upkeep, the first class in this order goes unpaid first, the cheapest within it (ties in lot order). Decorations: Plaza, Statue. Passive (no job): Crypt, House, Well, Bakery, Inn, Graveyard, Embalmer, Stables, Ossuary Tower, Guildhall, Watchtower, Walls, Reliquary. Job: Market, Forge, Chapel of Vats. The WAR chain last: the Bone Mill, the Charnel House (its haul is most of the pits' bodies: unpaid 2 h from pre_vei it cut the WAR plateau 21.5%), the Raising Pit. Each building's class is its `buildings.json` `shed_class`, which must be in the order (`test_game_state_commands`) |
| `body_store.cap` | 200, + the Charnel House's per-level `body_cap` table (0 at level 1, then +50 a level: +100 at level 3, +350 at level 8), +100 per graveyard level | the start Charnel House (level 1) adds nothing, so the start cap is 200 |
| `gold.cap`, market `effects.gold_cap` | 6500, + 3250 per Market level (+50% of the base) | IDLE §6, E2b-2 T3.2 (sizing below). The start Market (level 1) makes a new game's cap 9750; level 3 gives 2.5 × the base, 16 250, and level 8 (T7's ladder) 5 ×, 32 500 |
| `town.projection_refresh_s` | 5 s | the build benefit's cache (STATE-API §5.10, E2b-2 T3.2): a `projected` or `upgrade_projected` row goes stale this long after it was computed while the town's structure holds (a structure change makes every row stale at once); the frame refresh also runs only while `view_catalog()` was read within this much sim |
| `town.projection_rows_per_frame` | 1 | the build-benefit units (rows, or the baseline they diff against) refreshed on a frame that ran no substep, late in the interval, while the catalog is read (STATE-API §5.10): 0.45 to 0.55 ms each at `pre_vei`. Every row settles about 1.5 s after a change at 60 fps (41 rows over the 15 late frames of each substep) |
| `town.projection_phase` | 0.5 | the frame refresh runs only once the substep accumulator holds this fraction of `substep_s()`: scenes refetch when `rev` moves, so their work bunches up just after a substep, and background work belongs in the later part of the interval |
| `town.projection_starve_frames` | 30 | at fast-forward, when every frame substeps: after this many substep frames in a row, one row (and its baseline) goes through on the next, whatever the phase; about 1.1 ms at `pre_vei` |
| `town.projection_tol` | `rel` 1%, `abs` 0.005/s | a refreshed row keeps its old value unless some rate moved by more than `rel` × abs(old) + `abs` (the floor is half the 0.01 the build card shows), so the town's row signatures don't move on float drift every window |
| `town.projection_rows_per_call` | 0 | a test override, not a tunable: above 0 a view call refreshes up to that many of its own rows, exactly (the exactness, purity, persist and contract tests set 1000) |
| `queue.max_len` | 8 | the build queue's length (IDLE §5, E2b-2 T3.2), the town's stand-in's 8 |
| `idle.catchup_gate_tol` | 0.01 | the catch-up gate (IDLE §4, E2b-2 T3.3a, the run's manager's rule): a 10 s core step against 0.5 s over 12 h with no input. Vei's and Covington's stocks within 1% at every 600 s sample, each overflow tally within 1% at the 12 h endpoint (a) and within max(1% of it, its floor) at every sample (b), the same outcomes. The core step's share of IDLE's 2% `idle.catchup_tol`. Read only by `tests/slow/convergence.gd` (its assertion) and `test_step_accuracy` (the judge's test) |
| `idle.catchup_gate_tally_floor` | gold 6, bone 1 | (b)'s floor: a fixed amount per tally, what one 10 s step's lag can carry. **Bone 1:** set when at 10 s pre_vei's convoy ran 10–15 mass of corpses behind 0.5 s's (the start-of-step pickup cap, MECHANICS §4.2), about 0.7 bone of the mill's overflow. It stays: since E4's claim that convoy lands as 0.5 s's does, and pre_vei's bone-over (b) at 15 s reads 0.18 of the floor (1.09 before). the worst (b) residual at 10 s over 12 h on the three starts is 0.74 bone (pre_vei at 600 s, where 1% of the tally is 0.65). A fifth of the judge test's 5-bone mid-run fault. **Gold 6:** no gold tally moves at any start; the largest gold income among them is 0.6 gold/s of trade (pre_vei: Market 2, four stalls at `stall.rate` 0.15; midgame_2flips and fresh 0.3), and 0.6 × 10 s = 6 gold, a whole number |
| `idle.gap_s` | 30 s | IDLE §4 When: a frame on the frame path whose real time (its sim `dt` / `time_scale`) is above this goes through catch-up instead of having its remainder past `sim.max_substeps_per_frame` dropped; under it, frames stay live play (MECHANICS §1.3). Real time, so debug fast-forward stays live |
| `idle.catchup_max_s` | 604 800 s (7 d) | the most a load catches up; more is dropped and flagged (`cmd_load`'s `capped`): a sanity cap, not a design lever (IDLE §4) |
| `idle.catchup_dt_max_s` | 10 s | catch-up's longest core step for its first `idle.catchup_dt_long_after_s`: the largest step the gate (`idle.catchup_gate_tol`, E2b-2 T3.3a) passes at every start over 12 h; 15 s fails it at pre_vei (bone over (b) 1.09 of 1.00) |
| `idle.catchup_dt_long_s` | 15 s | catch-up's longest core step past `idle.catchup_dt_long_after_s` (IDLE §4 Budget, the budget's lever 2, E2b-2 T3.3b; the run's manager's cap): a week takes 41 760 steps instead of 60 480. 15 s is the longest step whose outcomes match 0.5 s over 12 h at every start (T3.3a: 30 s flips midgame_2flips' Ashgate at 5 355 s and puts fresh at 2.38%); over 7 days its flips, retakes, forts held at the end and Relish's place match a 0.5 s run at every start (`tests/slow/catchup_week.gd`). 7 days is a timing test for the stocks only (IDLE §4). **20 s retakes Ashgate over the midgame week (0.5 s reference holds); 15 and 17.5 hold. Don't raise it without re-running catchup_week.** (E3-1 tried 20 s: midgame_2flips lost Ashgate at 229 887 s. The run's manager took it back to 15 s: a catch-up that loses a fort the live game would have held breaks the player's trust, and the player did nothing wrong; 2 s a week isn't worth that, and 17.5 s is out because its margin is unknown.) |
| `idle.catchup_dt_long_after_s` | 43 200 s (12 h) | the longer step starts this far into a catch-up: the first 12 h, the span the gate and the accuracy test judge, keep `idle.catchup_dt_max_s` |
| `idle.catchup_max_steps` | 4 320 | catch-up steps at `clamp(elapsed / this, sim.substep_s, idle.catchup_dt_max_s)` (IDLE §4 Method): 12 h at 10 s, and anything up to 36 min (2 160 s) at the live 0.5 s |
| `idle.catchup_tol` | 0.02 | the accuracy test's tolerance (IDLE §4): a catch-up against live play with no input, on Vei's and Covington's stocks and the key rates (`tests/test_catchup.gd` at 2 h, `tests/slow/catchup_accuracy.gd` at 12 h), and closed against open (I1). The core step's own share is `idle.catchup_gate_tol` |
| `idle.field_steps` | 75 | field steps per catch-up (api-request #14 asked about 150; E2b-2 T3.3b2, the run's manager's ruling: 75, on the condition that ground's owner test passes at 75, which it does: `tests/slow/field_catchup_bench.gd` run as a copy with `STEP_S` 576 s, catch-up against exact live ticks in 99.67% of village samples over 12 h, green villages equal at the end; 99.83% at its own 144). Each costs about one live field tick on the shipped grid, so 0.4–0.7 s in all instead of 0.9–1.4 s (`catchup_bench`, IDLE §4 Budget). Against 150 it changes no outcome or Vei and Covington stock over 12 h or 7 days from the three starts, and village owners by at most 1 of 12 (IDLE §4). Read by `Catchup.begin` and `test_catchup`'s load test |
| `idle.field_step_min_s` | 2 s | no field step is shorter, so a short catch-up takes fewer (120 s: 60). A field step of up to `field.catchup_exact_ticks` (8) ticks, 1.6 s, runs that many live ticks plus a solve, so without it a 30 s gap would make 60 calls (one per 0.5 s core step) costing about 180 live ticks, more than the live field's 150; with it, 15 calls of about one tick each (ground's `field_catchup_bench.gd`, its MIN_STEP_S) |
| `idle.catchup_steps_per_chunk` | 90 | core steps per frame while a chunked catch-up runs (a load's from the shell, an open-game gap's): sized at about 50 ms at pre_vei over 12 h (E2b-2 T3.3b: 330 µs a core step, a 6.3 ms field step every 29 core steps; `tests/slow/catchup_bench.gd` measured a median 46 ms at pre_vei, 43 ms at fresh and 53 ms at midgame_2flips). Since E2b-2 T3.3b2 (about 210 µs a core step, a field step every 58) the median is 30–33 ms at the three starts, at most about 50 ms with a field step in it. A 12 h catch-up is 48 chunks, a week 464 |
| `idle.report_min_s` | 600 s | a gap at least this long gets the away report (IDLE §7, T3.3c) and its catch-up's events are collected for it; a load always is. A shorter open-game gap queues its events as live (STATE-API §6) |
| `idle.report` | the away report's text (IDLE §7, E2b-2 T3.3c; STATE-API §5.19) | every line of `view_away` is a template here, in the style of `map_view.json`'s `demo_away`: `streams` (the gains' order: backlog, mint, workers, bodies, gold, bone, living) and their `stream_labels`, `stream_fmt` and `backlog_fmt` (with `arrow_up` ▲, `arrow_down` ▼, `arrow_flat` ■), `builds_one_fmt` / `builds_fmt` (names joined by `list_sep` " · ", spaced, so a number ending one name never glues to the separator; `level_fmt` past level 1), `started_fmt` "{name} started {when} after you left, {why}" (W) / `started_now_fmt` "{name} started right away" and, W2, `started_brief_fmt` "{name} started within a minute of you leaving, {why}" (a start that waited, under 60 s in; the cutoff is the report's minute rounding in `StateViews.away_report`, not a tuning number; `afford_relics_fmt` is gone, `afford_relics_last_fmt` is also the relics wall's line) with `when_hm_fmt` / `when_m_fmt` (the time since you left) and one `waited_on` reason per queue reason, `refilled_fmt`, `raid_fmt`, `husk_one_fmt` / `husks_fmt`, `queue_empty`, `retaken_fmt` / `retaken_home_fmt`, `village_lost_fmt`, `overflow_fmt` "{store} is full: {n} not stored" (W: not called waste) with `store_labels`, and (R1; W words it as a returning player reads it) `unpaid_fmt` "{name} stopped for {when}, {store} ran out: {stopped}", `unpaid_brief_fmt` "{name} stopped briefly, {store} ran out: {stopped}" (stopped under a minute in all, where `when_m_fmt` would read "0 m": the report's minute rounding, no number), and for a building that stopped nothing (only capacity or inert effects) the same with no tail, `unpaid_none_fmt` "{name} stopped for {when}, {store} ran out" and `unpaid_none_brief_fmt` "{name} stopped briefly, {store} ran out"; `{store}` is each store its buildings.json `upkeep` is above 0 in (the same at every level), in `afford_stores`' words joined by `list_sep` (gold for every building today: none pays bone); W dropped `unpaid_none` "nothing stopped" and the "; stores kept" ending; with `unpaid_stopped` (one phrase per job and per working effect a building can have: `pit` and `pits` "raised no undead", `haul` "hauled no corpses", `mill`, `stall`, `forge`, `tend`, `morale` "lifted no morale", `attract`, `lifetime_bonus`, `haul_speed_mult`, `death_shock_mult`; `report_config_problem` checks every one buildings.json has), joined by `unpaid_sep` ", "; F2 adds **`unpaid_inert`** `["hint_precision"]`, the effect keys nothing in the sim reads yet (a list of strings, each an effect some building has, checked by `report_config_problem`; `GameState.unpaid_keys` skips them, so the Watchtower's unpaid line has no tail: "Watchtower stopped for 59 m, gold ran out"). Remove a key from this list in the change that makes the sim read it, and give it words in `unpaid_stopped`. Every `unpaid_stopped` key was checked against the sim at F2: `pit`/`pits` town_sim.gd:553, 1196-1198; `haul` :568; `mill` :560; `stall` :618; `forge` :627; `tend` :698; `morale` :1200-1202; `attract` :663, 1199; `lifetime_bonus` :1435; `haul_speed_mult` :848; `death_shock_mult` :519 (`add_shock`, called by state_runs.gd:292); `hint_precision` is read nowhere, so it is inert and its words are dropped; and the tokens the map parses: `plus` "+", `minus` "−", `rate_unit` "/s", `thousands` ",". Three numbers: **`rate_sig_digits` 2** and **`rate_max_decimals` 3** (a rate shows two significant digits, at most three decimals: +2.1/s, +0.43/s, +0.012/s, +140/s; under 0.0005/s it reads 0/s), and **`overflow_min` 1** (a store's full line shows from 1 not stored, so the report never says "0 not stored"; midgame_2flips' 12 h bone overflow is 0.56). R2 adds the ready lines for the queue's head still waiting, `afford_wait_fmt` "{name} is waiting on {store}: affordable in {when}" (the wait rounded up to the minute) and `afford_never_fmt` "{name} can't be afforded at the current income of {rate} {store}: move it down, or {raise}" (W: "the current income", not "today's"; the rate before the words, a token of its own with a space each side, so the map's rate token ends in /s with nothing glued to it), with `afford_stores` (gold, bone, relics: how a line names each store, the unpaid line's store too) and `afford_raise` (what raises gold's and bone's income: "build a Market", "build a Bone Mill"; W dropped relics' "raid for relics"). W (the run's manager, Shawn's words) gives a head short of relics its own line, with no rate (relics have no idle income) and no raise: `afford_relics_last_fmt` "{name} needs relics: raid a fort", the relics wall's line (W2): shown for the first entry skipped on `no_relics` when no entry can start (no row `next`, no `waiting_funds` head that will be afforded; an entry `queued` behind a head at -1.0 can't start either). No head reaches it, since the queue's walk gates a relic shortfall first; the move-down form `afford_relics_fmt` is gone. F1 (the run's manager: the line never names itself or a move that can't help) adds `afford_never_last_fmt` "{name} can't be afforded at the current income of {rate} {store}: {raise}" for a head whose move down can't help (F2: nothing behind it could start in its place: the queue's walk less the head has no row that isn't `skipped_gate` with `affordable_in_s` >= 0), and for a head that is its store's own producer, `afford_producer` (gold `market`, bone `bone_mill`: the building whose job makes each store, matched on the building so an upgrade counts) with `afford_raise_self` (a fact, true at F1: "nothing else makes gold", "nothing else makes bone"; bone's until P4 makes rot a source) in `afford_never_self_fmt` "{name} can't be afforded at the current income of {rate} {store}, and {raise}: move it down" and `afford_never_self_last_fmt` (the same without ": move it down"). Each raise text is true of the configs (test_away checks it): only the Market's stalls make gold and only the Bone Mill's milling bone, and loot.json gives relics at every tier ("raid a fort") and no gold or bone; and the raid prompt `full_raid` "Your stores are full and the queue is empty: raid a fort for relics", shown when the queue is empty and gold and bone are each within **`full_tol` 0.01** of their caps (a fraction of the cap: 1%, so a store a coin or two under its cap still reads full; at day1's caps that is 97.5 gold and 2 bone), in place of `queue_empty` (W: you can't plan a build without relics). `report_config_problem` checks each key, the three stores in `afford_stores` and gold and bone in `afford_raise`, `full_tol` in [0, 1), and (F1) a producer for gold and bone, each a buildings.json building for a store `afford_stores` words, with its `afford_raise_self` words |
| `bone.cap`, bone mill `effects.bone_cap` | 200, + the Bone Mill's per-level table 100, 150, 350, 700, 1250, 2050, 3400, 8400 (T7) | caps 300, 350, 550, 900, 1 450, 2 250, 3 600, 8 600 at Bone Mill levels 1–8 (the rule is under Store caps below; E4 tunes it); a new game (no mill) has 200 |
| graveyard, embalmer `effects.lifetime_bonus` | +0.15, +0.5 per level | lifetime × (1 + Σ) |
| cap effects (live from T2.4) | chapel `vat_slots` 2 (view_backups.vats), guildhall `stance_slots` 1, reliquary `relic_cap` 6 and `essence_cap` 30 | per level, on top of `relics.cap`, `essence.cap` and `stance.base_slots` |
| E3 effects (data only for now) | watchtower `hint_precision` 1 | per level; `hint_precision` is in `idle.report.unpaid_inert` until the sim reads it |
| ossuary `effects.craft_slots` | 1 per level | E3-4, the craft gate (MECHANICS §3.6): `cmd_craft` refuses `needs_building` while the built buildings' `craft_slots` sum to under 1. A capacity effect, so an unpaid or Thrift-idled Ossuary still crafts. **Higher Ossuary levels add nothing in E3:** crafting is instant and has no queue, so a second slot changes nothing, and the level-2 and level-3 upgrades (900 / 300 / 6 and 1 350 / 450 / 9) bought nothing. **E4 step 10: one level** (`max_level` 1; the smallest of the three E4 options, parallel crafts or cheaper crafts per level needing code and a reason to craft faster): the 15 relics the bots' ladder spent on it last now go elsewhere |
| `craft.simulacrum`, `craft.phylactery_charge` | 20 essence + 1 relic; 15 essence | `economy.json`, E3-4, read REQUIRED (`GameState.REQUIRED`): what `cmd_craft` takes. **No stock cap** on the simulacra ready or the charges (the run's manager's ruling): the essence cap (60) and relic cap (12) bind them, so a full essence store makes 3 simulacra or 4 charges. `phylactery.max_per_dungeon` stays the per-dungeon use limit |
| `relics.cap`, `essence.cap` | 12, 60 (the Reliquary raises both to 18 and 90) | |
| `big_undead.cap`, `big_undead.per_crypt_level` ⟵ crypt `effects.big_undead_cap` | 4, +1 | the cap is 4 at Crypt level 1, 6 at level 3 (the Crypt's `effects` are empty; the number is here) |
| crypt `unique` | true | `buildings.json`: the only unique building, so a second Crypt is refused (`unique`, STATE-API §4.3) |
| `town.tiers.<tier>.buildings`, `.requires` | 0 / 6 / 12 / 20 finished buildings (the Crypt counts), plus `market` + `house`, `walls` + `chapel_of_vats`, `reliquary` | the next tier rises when both hold |
| `town.tiers.<tier>.lot_ids`, `.lots` | below the table | explicit lot ids per tier; `.lots` is their count (kept for readers that want a number) |
| `stance.base_slots` | 2 | stance slots before the Guildhall's and Relish's home one (MECHANICS §4.5) |
| `stance.hold_s` | 20 s | E3-1, v0 (E4 calibrates): a stance's `active` can't change again until this has passed since its last change (MECHANICS §4.5). **Why 20 s:** a firing lasts long enough to see its work, a whole convoy round trip to any fort at the base haul speed (3.5 s to Ashgate, 18.2 s to Sable Hold), while a condition sitting on its line can't reshuffle the hands every beat or two. **The constraint: `hold_s` ≥ the longest catch-up step (15 s,** the larger of `idle.catchup_dt_max_s` and `idle.catchup_dt_long_s`; IDLE §4), so a step can't be raised past it without moving the hold. `GameState.catchup_config_problem` reports an error at load below that, naming both keys, and since E3-1 a config without it too |
| `stance.top_job`, `stance.priority` | vigil `tend`, harvest `haul`, hearth `stall`; `[vigil, harvest, hearth]` | E3-1: the job each ladder stance lifts to the top, and their order when several act at once (MECHANICS §4.5): Vigil first (Relish's way back; a tend slot opens only for a staffed vat, so it takes few hands), then Harvest (the pits' bodies), then Hearth (the stalls). `GameState.stance_config_problem` checks each is a stance and a job, and that the priority names exactly them |
| `stance.harvest_bodies_frac` | 0.3 | E3-1, v0: Harvest's condition, bodies under this share of the body cap |
| `stance.hearth_morale` | 0.5 | E3-1, v0: Hearth's condition, morale under it (above `morale.leave_below`, 0.35, so it acts before the living start to leave) |
| `stance.thrift_upkeep` | 0.05 gold/s | E3-1, v0: Thrift idles only buildings whose gold upkeep is above it (TownSim's; the same at every level): the Embalmer, the Chapel of Vats, the Ossuary Tower, the Guildhall, the Watchtower, the Walls, the Plaza, the Statue and the Reliquary today; never the WAR chain or the Market (below) |
| `stance.thrift_spares_from` | `war_mill` | E3-1 (the run's manager's ruling, applying R1): Thrift idles only the `shed_class`es ranked before this one in `upkeep.shed_order` (decoration, passive, job), so never the WAR chain at any level. TownSim reports an error at setup if it isn't a class there |
| `idle.report` Thrift lines (E3-1) | `thrift_fmt` "{name} idled by Thrift for {when}: {stopped}", `thrift_brief_fmt` "{name} idled briefly by Thrift: {stopped}", `thrift_none_fmt` "{name} idled by Thrift for {when}", `thrift_none_brief_fmt` "{name} idled briefly by Thrift" | the losses' line for each building the Thrift stance idled during the absence (IDLE §7), naming Thrift as the reason, not the gold; `{stopped}` is the unpaid line's phrases (`unpaid_stopped`, joined by `unpaid_sep`); under a minute "briefly", as the unpaid line. In `GameState.REPORT_KEYS` |
| `vats.grow_per_s` | 1/300 (0.003333) per tended vat | E3-2 (MECHANICS §7): a vat grows at this × its tend hands (0..1) while staffed and tended, so a fully tended empty vat holds a ready clone in 300 s; untended or unstaffed it doesn't grow. Read REQUIRED (`GameState.REQUIRED`) |
| `foreman.mult`, `speed_k`, `presence_k` | 1.0, 0.05, 0.01 | E3-3, v0: **E4 placeholders** (E4 calibrates; read REQUIRED, `TownSim.REQUIRED`). A working foreman (MECHANICS §4.2) multiplies its building's job output by `mult + speed · speed_k` and lifts the morale target by `presence_k · presence`. With stats of 1 to 10 that is ×1.05 to ×1.5 and +0.01 to +0.10: midgame_2flips' u8 (speed 3.66, presence 6.44) gives the Market ×1.183 and +0.064 |
| `backups.clone_respawn_s`, `unmade_respawn_s` | 60, 600 | E3-2 (MECHANICS §7): after a run-ending death she is `dead` this long, then wakes at Covington (from a ready clone, or reformed when unmade); `view_backups().death.respawn_s` and the seeds' `death_ends` show it. Read REQUIRED |
| `phylactery.revive_hp`, `max_per_dungeon` | 0.5, 1 | `max_per_dungeon` (REQUIRED from E3-2): the in-place revives a dungeon may use; `view_backups().death` reads `phylactery` only while it is above 0. `revive_hp` is the dungeon's |
| `essence.per_living`, `per_undead`, `lifetime_s` | 1, 1, 12 | `lifetime_s` is the existing raid.json name |
| `loot.reclear_decay`, `loot.recover_s` | 0.5, 28800 s | each clear that pays loot (a flip, a counter-garrison clear) multiplies a fort's loot yield by 0.5; the yield climbs back linearly to 1 over 8 h from its last clear. A retake leaves it as it was (the run's manager, 2026-11-17: a fort lost and retaken has already been looted, so losing it costs, not pays; the old reset to 1 made each re-flip a full-yield raid, 45% of sessions' relics). MECHANICS §5.3 |
| `vei.fronts_required`, `break_beats`, `loss_backlog_keep` | 3, 20, 0.35 | `vei.json`; `lapse_cost` 4: a beat below the ferry takes 4 pips back (MECHANICS §6) |
| `vei.guards` `rate_per_uncleared`, `cap`, `life_s`; `unit.hp`, `unit.dmg` | 1.0/s, 12, 6 s; 49.5, 8.8 | tuned in D-c so no ±5% move swings the win rate by a cliff; hp and dmg sit off Relish's 30-hp hit counts on purpose. Since Phase I P1 the rate and cap are the values at a pool of `vei.pressure.pool_free` or less (the row below) |
| `vei.pressure` `pool_free`, `per_pool` | 400, 0.0065 | **Phase I P1** (at 6dc16a2; MECHANICS §6): the break's guards come at `rate_per_uncleared` and `cap` × `1 + per_pool · max(0, pool − pool_free)` (`VeiFronts.pressure_mult`, `pressured`), so her full pool of 600 sends 2.3× the guards (2.3/s a lane, 6 → 13.8 alive at one uncleared front) and the demo seed's 380 is unchanged (exactly 1). Sized on the faithful grade (the fight-grade row below): 1 + 8 at score 65 wins 9/20. Sessions reaches Vei-ready at her full pool (600 of 600), so 2.3 is the multiplier its first attempt meets; a trip in a tithe dip below 600 meets less |
| `vei.weaves.dmg`, `period_beats` | 13.5, 3 | off the 30-hp hit counts as above |
| `vei.backups` `revive_hp_frac`, `iframes_s`, `shove_px`, `shove_recover_s`, `ready_trance` | 1.0, 3 s, 180 px, 3 s, false | a revive in the Vei fight is at full hp but does not ready the trance; V1 (1+1) 65%, V2 (0+0) 15% at score 70 |
| `K`, `S_vei` | 36 000 000, 8.0 | `K` E4 step 3: ×3000 for the live backlog (sessions about 5.6M at day 1, 61M at day 5, 140M at day 8; continuous 204M), so sessions reaches odds 0.6 at about day 4.7, continuous at about day 3.4 (28% sooner; at d6ad1b7 sessions crosses 0.6 at about day 5.4, between its looks, and continuous at 3.48), and night 1 takes the odds from 0.02 to 0.11, not 0.98 to 0.998. Was 12000 (the audit's ×4.8 canon), sized for the 18k knife edge below. The fixtures' and the demo seed's backlogs were scaled by the same 3000 so their odds stay put. `S_vei` unchanged. **Since E4 step 9, `K` sizes her strain** (`backlog / (backlog + K)`), which her tithe period, reship and need read; the odds a player reads are the win odds of the row below, so these day figures are the strain's (they are E4 step 3's, at d6ad1b7) |
| `odds.time_weight`, `odds.time_s`, `odds.backlog_cap` (realm.json) | 0.7, 388 800 (4.5 days; P3b, was 345 600), 0.8 | **P3b:** time_s raised to hold sessions' Vei-ready while the raid credit (row below) moves continuous (§5's P3b rows). **E4 step 9, the odds lever** (the run's manager's 2026-11-17 13:44 ruling, option B; MECHANICS §3.5): the win odds are `time_weight · t / (t + time_s) + (1 − time_weight) · min(backlog_cap, strain)`. They drive what the player reads, the boss seed and Vei-ready, and nothing in the fight; K's strain still drives her pressure, so steps 5–8's hold calibration (α 0.85, the band, the need bins, away_risk) doesn't move. **One sizing pass**, from the ruling's start (T 4 days, w 0.7), sized on each profile's logged looks (time, backlog, fronts met at her full pool) from one run with no Vei trip: nothing in the sim reads the win odds, so one trajectory prices every (w, T, cap) up to its Vei-ready; time_weight 0 reproduces 6.0000 and 3.3034 at the look. Measured at the sized values with the profiles (one seed, 8 days, at 69542f2; unchanged through b475eb3, and 4.8358, 19.4% sooner, at c15f874 after 4f8b493's ready-vat hand: §5's calibration list): **sessions Vei-ready day 6.0001** (518 406.5 s, as before: fronts first met at its day-5.17 look, odds 0.56 there and 0.6096 at day 6's first look), **continuous day 4.8291** (417 231 s), **19.5% sooner** (was 44.9%; inside IDLE §8's 10–30% and the ruling's 35%, so no re-size and no 4-remnant trim). The cap binds neither (their strains at ready are 0.632 and 0.735) but floors any profile's 0.6 at day 4.24 (29% sooner than day 6) whatever its backlog: x = (0.6 − 0.3 · cap) / 0.7, t ≥ T · x / (1 − x). On paper, cap 0.7 would put continuous at 5.05, T 3.5 days at 4.38, w 0.6 at 4.49. **What binds sessions** (the step 9 review's item 7; sessions' rows at 0b2a9ec): the odds, at session-start looks. Its rows meet all three fronts from the day-5.33 look (the full-pool look log at 69542f2's code had them from 5.17), with the odds at 0.5618 (5.17) and 0.5724 (5.33). The next look is day 6.0's, after day 5's night, at 0.6096. So any (w, T, cap) whose 0.6 falls in that night reads day 6.0, which is why the rows above sit at 6.0000. A change to the fronts moves it only if it puts them past day 6.0. A change to the odds moves it only if it brings 0.6 forward to day 5.33 or earlier (T 3 days does: 5.1696), or pushes it past day 6.0. The cap floors any profile at day 4.24 (the review read the fronts as binding; the rows don't). Sessions' nights: odds 0.06 → 0.14 12 h after night 1's close (0.16 on its load), 0.57 → 0.60 on night 6; one night never takes them near 1. time_weight 0 with backlog_cap 1 gives the strain bit for bit (the revert proof). **The ▲/▼** is the backlog's sign, not the odds': the map labels it as the strain ("strain ▲", never right after the percent; the step 9 review's item 4, ruled 2026-11-17 16:40). **Phase I, recorded, not fixed:** the map valve's "odds in 10 min" stops moving with a drag once the projected strain passes `backlog_cap` 0.8, since min(cap, strain) is flat there and only the window's time moves it |
| `odds.raid_credit`, `odds.raid_credit_cap` (realm.json) | 0.00075 a raid, 0.12 | **P3b (V-I2 (a), the active nudge):** the readiness's strain term takes min(cap, raid_credit × raids finished) (`GameState.raid_credit`); only the readiness reads it. Two rounds, seeds 1–4 (§5's P3b rows): round 1 (time_s 4 d) put every sessions run at day 5.0 (seed 1 with 1+4: the first attempt out of band); round 2 (time_s 4.5 d, shipped) keeps sessions at P3's 5.167/5.333/5.009/5.167 and puts continuous at 4.795/4.824/4.809/5.102, 5.5% sooner on the mean (seed 1 7.2%; seed 4 is front-limited). The cap bounds active play's gain to 0.036 of readiness, about half a day near Vei-ready. |
| `odds.first_gain`, `odds.first_cap` (realm.json) | 1.41, 0.95 | **P3b (V-I2 (b), honest shown odds):** the shown odds' ceiling is min(first_cap, first_gain × readiness), not the readiness, so a 1+10 party that wins 80% reads 0.80 (P3's form read 0.60). Fit with backups_mid and backups_scale below; 1 and 1 is P3's form bit for bit. |
| `odds.backups_mid`, `odds.backups_scale` (realm.json) | 6.72, 1.62 (P3b; were 5.57, 1.24) | **P3b refit** with first_gain on the same grade plus its 1+10 point (16/20): 0.01, 0.08, 0.22, 0.46, 0.80 against 0.00, 0.05, 0.25, 0.45, 0.80 at 0+0, 1+2, 1+4, 1+6, 1+10 (readiness 0.6053). The re-grade at P3b's sessions Vei-ready (readiness 0.604) gives the same ladder: 9, 5, 1, 0 and 16 of 20. Before P3b: **Refit at P3's re-grade** (Left item 3 of P3 handoff 8): least squares on P3's faithful grade at sessions' 5.1667 Vei-ready (the next row's last entry; readiness 0.6053): 1+6 won 9/20, 1+4 5/20, 1+2 1/20, 0+0 0/20, and the fit reads 0.46, 0.23, 0.07, 0.01 (within 2 points each). The odds a player reads at sessions' Vei-ready (1 + 6) go from 0.29 to 0.46. **The form's ceiling, recorded:** continuous's seed-1 Vei-ready (day 5.0518) holds 1 + 10, and on the same seed 1 + 10 wins 16/20 (80%) against the fit's 0.60. `first_odds` never passes the readiness (0.6053 here), so a profile with ten or more backups reads about 20 points low whatever the fit. Lifting that is a change to the odds split's form, which is the manager's to make. The old fit, 7.15 and 1.76, is the provisional one below. **Phase I P3, the odds split** (the run's manager's ruling on P1's vision check (a); MECHANICS §3.5, STATE-API §10 A16): the row above is now the **readiness**, and the odds a player reads are `readiness / (1 + exp(−(backups − backups_mid) / backups_scale))`, backups = min(phylactery charges, `max_per_dungeon`) + clones ready. **Provisional:** fit by least squares on the logit to P1's faithful grade at sessions' Vei-ready (6dc16a2, score 65, readiness 0.6118): 1+8 won 9/20, 1+4 3/20, 1+2 1/20, 0+0 0/20; the fit reads 0.453, 0.139, 0.053, 0.010 (within the brief's ±10 points, and two). Refit at P3's re-grade, with the clones per profile at Vei-ready. Before the split the player read 0.61 at Vei-ready against a 45% first attempt. `backups_mid` −1e9 is the readiness bit for bit (the revert proof) |
| `vei.fronts.giants.need_base`, `carvers.need_base`; `carvers.need_per_pool` | 2, 2; 0.012 | E4 step 2's sizing (try 1; were 14 and 18): with giants' `need_per_pool` 0.02, giants needs 14 at Vei's full pool of 600. Giants' 14 sits above the best t1 skeleton's wits (9), so one t1 skeleton never fills it (the manager's ruling 4 at step 2); it takes two or three. **Carvers' `need_per_pool` 0.02 → 0.012 (9.2 at a full pool) is the one re-size of the R2 ruling**, when the bot's Vei-ready moved to the full pool (IDLE §8). Less 3 × `q` (about 6.7) carvers' want is about 2.5 beef, so one t1 big with beef 3 meets it: carvers needs a keeper, not a composition. **At d6ad1b7, Vei-ready at her full pool (3 of 4 and odds ≥ 0.6), with the in-wave readout (the pool she has then, at the look) beside it:** sessions **day 6.0001** (518 406.5 s; in-wave 518 400 s, the same look), continuous day 3.4837 (in-wave 3.4836), 42% sooner and outside the 10–30% band, ablation_keep never (giants 0). Both are **odds-bound**: sessions meets all three fronts at a full pool from day 5.0 (giants 19/14, swarm 24.1/24, carvers 13.7/9.2), but its odds are 0.5967 at day 5's last look (5.347) and 0.6356 at day 6's first, so it lands 6.5 s past day 6. At ready, sessions brings giants 14/14 (a wraith and a skeleton, wits 7 each), swarm 31.4/24, carvers 13.7/9.2 (one beef-7 zombie), raw 15.7/58. **Before R2** (carvers 0.02, the fronts at the pool she had then, at 5b86232): sessions day 5.34, continuous day 4.38 (18% sooner), both inside a tithe wave's dip; at a full pool neither had 3 of 4 in 8 days |
| The fight grade at Vei-ready (E4 step 3) | 20 seeds | The demo seed with the boss bot at score 70 (`--boss-autoplay=70`, `--boss-seed` 1–20), at d6ad1b7. **At sessions' Vei-ready** (`--boss-cfg` needs giving the demo sessions' have/need on arrival: giants 1.00, swarm 1.31, carvers 1.49, raw 0.27) **with its backups** (1 phylactery charge and 4 clones; vats best case): **19/20 won (95%)**. With the demo's 1 + 1 backups at the same ratios: 12/20 (60%). The demo as shipped (its fronts at 2.40, 1.87 and 4.09 of need, 1 + 1): 10/20 (50%). Before E4 (the old config, 1 + 1): 13/20 (65%). These step 3 and step 9 grades set only the fronts' needs: the break still ran on the demo seed's pool 380 and q 2.6 (ferry 3.43), not sessions' pool 600 and q 2.238 (ferry 5.35), so they understate how easy her break is; the E4 step 10 (b) re-grade at the end of this row corrects them. Every fight clears giants, swarm and carvers in phase 1 (20.0 s at sessions' ratios: giants at exactly its need takes `phase1.ref_s`). **Re-graded at E4 step 9** (the run's manager's 01:50 ruling (d) and 12:45 item 5: score 50, 1 + 2 backups), at 69542f2. Sessions' have/need at its day-6 Vei-ready, at her full pool: giants 1.07, swarm 1.29, carvers 1.49, raw 0.27 (`--boss-cfg` with need_per_pool 0 and need_base the demo's have ÷ that ratio). **The first attempt wins 3/20 (15%)**: every fight clears the three fronts and reaches the break (phase 1 in 18.7 s on average), then 17 end unmade, with 3.70 Relish deaths on average. That is far under the 85% line, so Vei's phase-2 pressure is not raised and vei.json is unchanged. The demo as shipped, unchanged, still grades 10/20 at score 70 with 1 + 1. **Re-graded at E4 step 10 (b), the faithful grade, a known miss** (the run's manager's 2026-11-17 18:00 and 18:59 rulings; at c15f874, seeds 1–20, wins of 20 at scores 60 / 65 / 70; the aim is 40–60% at score 65). Sessions at its day-6.0001 Vei-ready holds 1 phylactery charge and 8 clones, at pool 600, q 2.238 and backlog 63.8M, with fronts at 1.29 / 1.33 / 1.27 / 0.275 of need and a party of 4 bigs at power 0 (two skeletons, a wraith, a zombie). The faithful grade puts that party, pool, q and backlog in the demo seed of a scratch vei.json, with the needs as shipped and no overrides; its fronts reproduce sessions' haves exactly. The setup is in `RUN/reports/economy/wip/tools22/` (`mk_faithful.py`, `grade.sh`, `gsum.py`). **1 + 8: 19 / 20 / 20; 1 + 2: 17 / 20 / 19; 0 + 0 at score 65: 9/20**, so the first attempt is already inside the aim with no backups at all. With the demo party in place of hers (the needs, pool, q and backlog matched): 1 + 2 17 / 19 / 20, 1 + 4 19 / 20 / 20, 1 + 8 20 / 20 / 20. The cause: the full pool's ferry (5.35 against the demo's 3.43) drops more anchor motes (`anchors.motes_per_ferry`, 3.21 a second against 2.06), so more raised allies soak her hits, and her break kills about 0.008 a second against the demo's 0.039. **No single phase-2 number fixes it:** 1 + 8 needs about 10 deaths a fight to land in 40–60%, and the demo is lost at its 3rd death, so every lever that adds deaths or time spends the demo's lives first. The one-lever sweep (sessions at score 65 with 1 + 8, the demo party matched as above except the 0.38 row, which is faithful; the demo as shipped at score 70 with 1 + 1): shipped 20 / 10; `guards.unit.dmg` 17.6 (×2) 17 / 0; 26.4 (×3) 15 / 0; `weaves.dmg` 30 20 / 12; `break_beats` 30 20 / 1; `ferry_beat_scale` 0.38 15 (5 timeouts) / 5; 0.40 4 (15 timeouts) / 3; 0.45 0 (19 timeouts) / 0. Sessions reaches the band only near `ferry_beat_scale` 0.39–0.40, and only through the bot's 600 s timeouts (the break never comes), with the demo at about 3/20. vei.json is unchanged. **Phase I:** break pressure that scales with her pool, a code change in VeiFronts and vei_boss: the guards' rate or the weave cadence on `living_pool`, or the anchor motes taken off the pool's ferry term. The target is 40–60% at score 65 for sessions' first attempt, with the demo at 6/20 or better. **Phase I P1, pool-scaled break pressure: in band** (at 6dc16a2; the faithful grade, seeds 1–20, run 8 fights at a time as two grades of 4 at once; cac5a17's baseline ran 4 at a time, and the demo's 20 result lines match it, so the concurrency moves no outcome). The break's guards now come at `guards.rate_per_uncleared` and `cap` × the `vei.pressure` multiplier (the row above: 2.3 at her full pool, 1 at the demo's 380). The extra guards strip the raised allies that soak her lethal hits, so a full pool makes the break harder. Sessions' Vei-ready, re-read at cac5a17 (`ve_probe.gd`), is c15f874's: day 6.0001, pool 600, q 2.238, backlog 63 807 877, odds 0.6118, 1 + 8 and the same four bigs, so `mk_faithful.py` stands. **1 + 8 wins 5 / 9 / 14 at scores 60 / 65 / 70 (45% at 65). At score 65: 1 + 4 3/20, 1 + 2 1/20, 0 + 0 0/20 (was 9/20).** Every loss is a death, and no row has a timeout (each fight ends broken or unmade). At 1 + 8 and score 65 the median fight has 10 deaths (2 to 10, mean 8.40; the nine wins took 2, 4, 5, 6, 8, 8, 8, 8 and 9) and spends 8 clones, and no fight has fewer than 2 deaths, so every one spends a clone after the phylactery. At score 70 the median is 7.5 deaths (3 to 10). **The demo as shipped (score 70, 1 + 1) is 10/20 at 6dc16a2, and its 20 `BOSS_AUTOPLAY` lines are identical to cac5a17's** (2.30 deaths, 1 to 3). Baseline at cac5a17 (no pressure): 1 + 8 at 65 20/20, 1.10 deaths. The screen that sized it (on cac5a17's faithful tree, `--boss-cfg` setting the guards' rate and cap to m × 1.0/s and m × 12, 1 + 8 at 65): m 2.0 13/20, 2.4 9/20, 2.6 7/20, 3.0 6/20, 2.8 5 of the 15 seeds run. Shape (b), the anchor motes cut to `motes_per_ferry` 0.41: 0 of 14, every fight unmade at 10 deaths (her allies starve; no timeouts). Weave cadence on the pool was not needed. **The method:** `RUN/reports/economy/wip/tools22/`, as above, plus `gs.py <out> <tag>...` (wins, the median and range of deaths, median clones spent, the end reasons; `grade1.sh` now keeps the `BOSS_CFG` echo lines, so a mistyped override path shows). **Phase I P3, the faithful re-grade (ruling 4 on P3's brief): in band, vei.json unchanged** (at 180121f, seeds 1–20 at score 65, 4 at a time). The seed is the one the game builds at sessions' Vei-ready (seed 1, day 5.1667: `StateRuns.boss_seed_v2` taken at her node, `vr_probe2.gd`, written by `mk_faithful2.py`): party 5, pool 600, q 2.221, backlog 85.04M, readiness 0.6053, giants 22.0/14.0, swarm 42.5/24.0, carvers 14.7/9.2, raw 21.3/58.0. The fronts' needs stay as shipped (P3's fronts (b) record, §5's calibration rows). **Its own 1 + 6 wins 9/20 (45%)** with 6.70 deaths on average; 1 + 4 5/20, 1 + 2 1/20, 0 + 0 0/20. **The demo as shipped (score 70, 1 + 1) is still 10/20** (2.30 deaths). No row has a timeout or a script error. Logs and summary: `RUN/reports/economy/wip/tools-p3/grade-180121f/` |
| `economy.craft.husk` `bone`, `remnants` | 500, 3 | **GUESS** (lever (b), the sizing stop's ruling 2: slow and costly; `cmd_craft_husk`). **Re-priced 2026-11-17** (were 300, 6; the vision review of E4 M1, item 6: make it a real bone sink, the bone binding and the remnants a light raid-side gate; the run's manager's 11:39 ruling 3). About 600 bone, the review's figure, is never payable in sessions: at 600 it sits at its 550 bone cap from day 1 to day 7 (0 crafts in 8 days, Vei-ready 7.0001, 70 levels; the step 6 stop's probe at 3379877). 500 is 91% of that store, so while sessions' cap is 550 (to day 4) it crafts at most one a session; at day 8's 2 250 cap it crafts two in a session, twice. 3 or 4 remnants gave identical sessions runs in the stop's probe (at 3379877, with the old retake reset), where the bone binds. **With the kept yield the remnants bind for continuous:** 500 / 4 puts it at day 3.5991 (40.0% sooner) against 3.3035 at 500 / 3, because 3 remnants leave it enough to raise a 4-big party by 17.5 h, which flips 5 forts within the hour (sessions at 500 / 4 not re-measured). Measured with the retake's kept yield (MECHANICS §5.3), one seed, 8 days: sessions crafts 12 (6 by day 4; 11 at 300, 6) and is Vei-ready on day 6.0001 (518 406.5 s, as at 300, 6), 116 levels; continuous crafts 9, all by day 2.4, and is Vei-ready on day 3.3035, **44.9% sooner** (past IDLE §8's 10–30% and the ruling's 38% report line; reported, not tuned; with E4 step 9's win odds, the `odds` row, the same run is ready on day 4.8291, 19.5% sooner); ablation_keep crafts 8 and is never ready (fronts 1 of 3). A new game's 200 bone cap is under it until the Bone Mill raises the cap. Sized with the needs above so sessions reaches Vei-ready on day 5–6. The history below is from E4 step 2 (5b86232, d6ad1b7), at 300, 6 except the one 500-bone trial named: the price paced it little then: bone sat at its cap, so a 500-bone trial made the same 13 crafts in sessions (and never reached Vei-ready); the bot's conditions pace it (a short front, room in the crypt, a keeper-grade fill, the queue's head not waiting on bone), and the remnants it grinds bind. Crafts over 8 days: at 5b86232 sessions 13 (7 by day 4), continuous 9 by day 4.4, ablation_keep 14; at d6ad1b7 (carvers 9.2) sessions 12 (5 by day 4), continuous 10 by day 3.48, ablation_keep 14 |
| `vei.fronts.swarm.per_backlog`, `raw.per_backlog` | 5e-7, 2.5e-7 | E4 step 3 (the manager's ruling: mass alone clears exactly one front, swarm). Swarm is met by mass at about 48M (odds 0.57). Raw's backlog term stays under its need through 8 days of every profile (60% of 58 at ablation_keep's 139M, 88% at continuous's 204M), so raw needs power from bigs. It brings about a quarter of raw's need at sessions' day-5 backlog. Past the 8-day horizon mass alone would clear raw; a saturating term (on the odds) would close that, as a follow-up. Were 0.0006 and 0.0012 |

**Lots per tier** (`economy.json` `town.tiers.<tier>.lot_ids`; sizes are `town.json`'s: lot-01..04 and
lot-13..16 are size 2, lot-05..12 and lot-17..22 size 1, lot-23 and lot-24 size 3):

| tier | lots | count |
|---|---|---|
| Hamlet | lot-01..lot-08 | 8 |
| Village | lot-01..lot-16, lot-23 | 17 |
| Town | lot-01..lot-20, lot-23, lot-24 | 22 |
| City | lot-01..lot-24 | 24 |

Chosen so that each tier-defining building has a lot of its size in the tier where it becomes
buildable (the tier-gate fix, MECHANICS §4.4): the Chapel of Vats (size 2) at Village on lot-13..16;
Walls (size 3) at Village on lot-23; the Reliquary (size 3) at Town on lot-24. Lot-23 and lot-24 stay
shut until then so nothing small is put on them first, and a size-1 building may sit on a bigger lot
(a lot too small is the only size refusal), so the player can still block lot-23 with a house:
demolish it. Town needs 12 buildings, which Village's 17 lots hold; City needs 20 of Town's 22.

**Store caps** (E2b-2 T3.2; IDLE §6; the ladder's bone cap since T7). Two constraints, and only these.
*8 h fill:* the base cap is at least 8 h of a new game's settled net income, rounded up. *Nothing stuck:*
every price of every building level fits a cap the player can reach by that building's tier
(`tests/test_build_ladder.gd`, below), so every build can be queued once the cap buildings are climbed.
The rates are measured: `cmd_new_game(1)`, no actions, 1 h at 0.5 s, the mean net rate over the last
10 min (the fixtures the same way, from their load).
- **Gold:** a new game settles at +0.210 gold/s (trade 0.30, upkeep 0.09): 8 h is 6 048, so the base is
  **6 500**, and the Market adds 3 250 a level (32 500 at its level 8). The largest gold cost is the
  Chapel of Vats' level 8 (9 450): over the base, under the start Market's 9 750, so `cost_exceeds_cap`
  is about gold only with the Market demolished (cap_level 1). Every other gold cost is under the base.
  The ladder test passes on gold, so the Market's `gold_cap` stays 3 250 a level (T7).
- **Bone:** a new game has no Bone Mill, so its net bone is 0 and the 8 h rule asks nothing: the base is
  **200**. The Bone Mill's `bone_cap` is a table per level (T7; MECHANICS §4.3), sized with the level
  ladder by one rule, E4's to tune: **the cap at mill level L covers 1.2 × the larger of the mill's and
  the Market's level-L+1 bone cost (they climb in step), rounded up to 50; the cap at the top level covers
  every bone cost of every building level.** Each entry is the smallest that meets it, and never below
  the one before; level 1 stays 100 (the rule alone gives 50), so a level-1 mill's cap stays 300. The
  mill's next level binds at every level below the top (190, 285, 455, 730, 1 170, 1 870, 2 990, × 1.2:
  228, 342, 546, 876, 1 404, 2 244, 3 588), the Market's being smaller at each; the top is set by the
  Forge's level 8 (8 575). So the bonuses are **100, 150, 350, 700, 1 250, 2 050, 3 400, 8 400** and the
  caps 300, 350, 550, 900, 1 450, 2 250, 3 600, 8 600 (level 2's 350 is under the old linear 400). The
  jump to level 8 is the Forge's price, not the mill's or the Market's: E4's.
- **Nothing stuck, checked** (the run's manager; `tests/test_build_ladder.gd` in the default suite, T7):
  every building, level and store with a price (`BuildRules.construction_cost`): (a) from a new game with
  no cap building built, `cap_level` is not −1 (relics: the cap with every relic-cap building at its max
  level, 18); (b) the price fits the caps the climb reaches by the building's own tier (an upgrade needs
  only that tier). The climb: from the base caps with no cap building built, every cap building of that
  tier or below whose next level's whole cost (gold, bone, relics) fits the caps now is built or
  upgraded, until nothing changes. With the shipped numbers it buys the Market and the mill in step,
  levels 1 to 8, all at Hamlet (gold 32 500, bone 8 600, relics 12; Village adds nothing), and the
  Reliquary at Town (relics 18). The tightest price is the Forge's level 8, 8 575 of 8 600. The test
  also fails a per-level Array effect without one entry per level. (A second Market or Bone Mill raises
  a cap further; the check counts one.)
- **Relics** keep `relics.cap` 12 (+6 with the Reliquary): the largest relic cost is 7 (the Chapel's,
  levels 6–8; the Ossuary's level 3 at 9 went with its levels in E4 step 10); the Forge's is 4 at level 8 (Village, cap 12), so no relic
  cost exceeds the cap its tier reaches. Relic income is not checked: L6+ relic costs are untested
  without raids (E4).

| start | gold: cap, stock, net/s, fill | bone: cap, stock, net/s, fill |
|---|---|---|
| a new game (Market 1, no mill) | 9 750, 80, +0.210, 12.8 h (the base alone: 8.5 h) | 200, 30, 0, never (no mill) |
| `midgame_2flips` (Market 1, Bone Mill 1) | 9 750, 656, +0.160, 15.8 h | 300, 328.5 (over the cap: it keeps the excess and earns nothing until under), 0 (the pits take every body), never |
| `pre_vei` (Market 2, Bone Mill 1) | 13 000, 3 616, −0.470 (falling), never | 300, 459.6 (over the cap), +0.107 uncapped (the mill's share of a body surplus), earns nothing until spent under 300 |

The 8 h rule covers only a new game: `pre_vei`'s bone, at its +0.107/s, fills its 300 cap in about 47 min
from empty.

**Building costs** (T7, BALANCE §7's adopted structure: town's trial G4 config C, `g3_overrides.py b2`
then `g4_overrides.py c` in `reports/town/trial-tools/`; E4 tunes the numbers). Gold / bone / relics per
level (relics shown when above 0; level 1 is `cost`, levels 2 and up `level_costs`); upkeep in gold/s. The
dead's buildings cost mostly bone, the Bone Mill's level 1 stays gold-priced and the Market is bought
with bone. The mill's level 1 is gold only since F1 (60 gold, no bone; the run's manager for Shawn: the data
brought in line with this rule, not a tuning). G3's A2/B2 and G4's C ran it at 60 / 20, and at 20 bone day1's
first queue of a House, a Well, a Bakery and the Mill deadlocked: the three take 10 bone each of day1's 30 and
only a mill makes bone (`tests/test_day1_queues.gd`). The job buildings and the house climb to level 8; the ladder adds no relic price below level 6 (the pit, charnel house,
Market, Bone Mill and house are relic-free to level 5), and the Forge (relics 1, 2, 3, 3, 3 at L1-L5) and the Chapel of Vats
(2, 4, 6, 6, 6) keep their own; relic costs never fall with level.

| building | tier | upkeep | L1 | L2 | L3 | L4 | L5 | L6 | L7 | L8 |
|---|---|---|---|---|---|---|---|---|---|---|
| Crypt | Hamlet | 0 | 0 / 0 | 150 / 60 / 1 | 300 / 120 / 2 |  |  |  |  |  |
| Raising Pit | Hamlet | 0.03 | 15 / 150 | 30 / 305 | 50 / 450 | 80 / 720 | 130 / 1150 | 210 / 1840 / 1 | 335 / 2945 / 1 | 535 / 4710 / 1 |
| Charnel House | Hamlet | 0.03 | 15 / 130 | 15 / 130 | 30 / 255 | 50 / 410 | 80 / 655 | 130 / 1050 / 1 | 210 / 1680 / 1 | 335 / 2690 / 1 |
| Market | Hamlet | 0.03 | 10 / 90 | 15 / 130 | 30 / 255 | 45 / 410 | 75 / 650 | 120 / 1040 / 1 | 190 / 1675 / 1 | 300 / 2685 / 1 |
| House | Hamlet | 0.01 | 40 / 10 | 80 / 20 | 120 / 30 | 135 / 70 | 155 / 155 | 175 / 360 / 1 | 200 / 825 / 1 | 225 / 1880 / 1 |
| Well | Hamlet | 0.01 | 30 / 10 | 60 / 20 | 90 / 30 |  |  |  |  |  |
| Bakery | Hamlet | 0.01 | 50 / 10 | 100 / 20 | 150 / 30 |  |  |  |  |  |
| Bone Mill | Hamlet | 0.03 | 60 / 0 | 20 / 190 | 30 / 285 | 50 / 455 | 80 / 730 | 130 / 1170 / 1 | 210 / 1870 / 1 | 335 / 2990 / 1 |
| Inn | Village | 0.05 | 150 / 50 | 300 / 100 | 450 / 150 |  |  |  |  |  |
| Forge | Village | 0.05 | 30 / 275 / 1 | 65 / 540 / 2 | 95 / 820 / 3 | 150 / 1310 / 3 | 240 / 2095 / 3 | 385 / 3350 / 4 | 615 / 5360 / 4 | 985 / 8575 / 4 |
| Graveyard | Village | 0.05 | 20 / 200 | 45 / 390 | 65 / 590 |  |  |  |  |  |
| Embalmer | Village | 0.08 | 35 / 330 / 1 | 70 / 655 / 2 | 110 / 975 / 3 |  |  |  |  |  |
| Stables | Village | 0.05 | 20 / 200 | 45 / 390 | 65 / 590 |  |  |  |  |  |
| Chapel of Vats | Village | 0.12 | 300 / 120 / 2 | 600 / 240 / 4 | 900 / 360 / 6 | 1440 / 575 / 6 | 2305 / 920 / 6 | 3690 / 1470 / 7 | 5905 / 2350 / 7 | 9450 / 3760 / 7 |
| Ossuary Tower | Town | 0.15 | 450 / 150 / 3 |  |  |  |  |  |  |  |
| Guildhall | Town | 0.12 | 350 / 120 / 2 |  |  |  |  |  |  |  |
| Watchtower | Town | 0.08 | 200 / 80 / 1 |  |  |  |  |  |  |  |
| Walls and Gate | Village | 0.12 | 400 / 120 / 2 |  |  |  |  |  |  |  |
| Plaza | Town | 0.15 | 350 / 150 / 2 |  |  |  |  |  |  |  |
| Statue of Relish | Town | 0.15 | 400 / 150 / 3 |  |  |  |  |  |  |  |
| Reliquary | Town | 0.2 | 600 / 250 / 4 |  |  |  |  |  |  |  |

**Price steps in order** (E4 step 10, review-t7r1r2 §5): the Market's L1 was the same 15 / 130 as its L2, so L1 is now
10 / 90. A new game starts with its Market built, so this prices only a Market built again (a demolished start
Market). The Bone Mill's L1 → L2 (60 / 0 → 20 / 190) stays: a currency handover like the House's below (L1 is gold
only because a new game has no mill to make bone), and the price rises in total.

**The House's gold → bone handover** (E4 step 8, the brief's item). The House is a living building bought with gold,
and the only one whose ladder runs past level 3. Config C priced its L4 to L8 on the dead's bone ladder, so L4 went
from 120 gold / 30 bone to 35 / 280. In bone, the price that binds, that is ×9.3 in one level against ×1.5 to 2
below it. It is also past a new game's 200 bone cap before any mill.
- **What the sessions profile shows** (20512b1's tree, the bot's first 5 days):
  - It builds five Houses by day 1, raises them to L2 at day 2.2 and to L3 at day 4.2. It hasn't queued L4 by
    Vei-ready (day 5.3), so the change reaches the profiles only through the bot's choices.
  - Gold sits at its cap (16,250) from day 1. Bone refills to its 550 cap each 4 h away and drains in each session.
  - At its away rate (about 550 bone per 4 h, 0.038/s), L3 is 13 min of bone and the old L4 was 2 h (51% of the cap).
- **Now:** L1–L3 and L8 keep their prices, and L4 to L7 run geometrically between them in each currency. Gold rises
  ×1.13 a level (120 → 225) and bone ×2.29 (30 → 1,880), rounded to 5.
  - In bone-time each level is about 2.3× the last (L4 31 min, L5 68 min).
  - L4 and L5 (70 and 155 bone) fit a new game's 200 cap.
  - The bone share of a level's price rises from 20% at L3 to 89% at L8. The handover stays, spread over five levels.
  - L4–L8 cost 3,290 bone in all, against 4,525 before, and 890 gold against 545.
- `test_build_ladder` checks it: each currency never falls from one level to the next and rises at most 2.5×, and L4
  and L5 fit the new-game cap.

**The calibration list, measured at c15f874** (E4 step 9 (6); one seed). The numbers are the 14-profile batch on
c15f874's tree, which is sim-identical to the docs-only commits after it (`reports/economy/wip/tools22/batch-c15f874.jsonl`,
each field as `summarize.py` digests it). The targets are `reports/pacing-spine.md` §4's and IDLE §8's. Nothing here is
tuned: the run's manager's 2026-11-17 18:00 ruling has the relics, the mint swing and the t2/t3 raids before a backup
measured and recorded. The queue readings come from a probe (`wip/tools22/qw_probe.gd` with `qw_bot.gd`: the profile's
bot with its queue logged at each session end; `QW_SKIP=1` swaps in a fill that unqueues every gated entry), run on
74321d7's tree (c15f874's code), the same seed.

| target | measured | verdict |
|---|---|---|
| **pure_idle:** at least one build or level per 6 h for 48–72 h, then a plateau with the chip | 6 builds in the first 6 h of its 7-day close, the last 1.9 h in, then none for 166 h | **Missed, structural.** One setup is one queue (`queue.max_len` 8), and nothing refills it while away. Its 8 are 6 early builds, done in under 2 h at their prices, and the Chapel and the Walls, which keep their slots gated (`lot_locked` at Hamlet, then `no_relics`). The queue's length against the early prices decides this one, not the jam below |
| **town_only:** a plateau at 2–3 days, then "needs relics" | the last build at 8.0 h (28 860 s, the 08:00 session); stores full from day 1's end (16 250 gold, 550 bone); 12 buildings and 19 levels at day 8; the relics wall from the first load (4 h) | **Missed: the bot's queue jams** (below). From 8.0 h its 8 entries are all gated: the Chapel, Walls and Forge (`no_relics`), the Embalmer (`needs_blueprint`), the Ossuary (`needs_tier`), and the Reliquary and the lot-17/18 pits (`lot_locked`). Relic-free levels that fit the caps stay unqueued (the Mill and the Market at L4, a House at L2, a Pit at L3). With the gate-skipping fill it makes 50 builds against 15, takes every listed relic-free level (L5; L6 and up cost a relic), and its last build is at day 1.46, in the night after day 1. The relic-free content alone lasts about 1.5 days, short of 2–3 |
| **next affordable**, as gaps between queue starts: S0 (the first 30 min) 10–40 min, S1 (to day 1) 1–3 h, S2 (days 2–5) 4–10 h | sessions: S0 14 min; S1 median 34 min (max 1.5 h, 16 starts); S2 median 26 min (max 39 h, 46 starts) | **S0 met; S1 and S2 missed** (E3 read 14 and 7 min). Starts bunch inside the sessions. The S2 max of 39 h is the jam on days 2.4–4.0: at day 3.0 all 8 entries are gated (the Reliquary, the Chapel's L3, and the lot-21/22 pits at L1, L2 and L3) |
| **idle workers** at or below 3 after the first hour | 10 (`worker.idle_cap`) in every profile; every slot staffed at every row after 1 h | The wrong metric (§7, trial G3): idle sits at the cap whenever the inflow outruns the slots, and the rest musters to WAR. Slot growth instead: sessions 18 at 1 h, 144 at day 8; continuous 180 at day 4.84; town_only 30; pure_idle 18. The digest had no muster rate; since Phase I P3 (Q-h) its `workers.muster_per_day` replaces `idle_max_after_1h`: per day of live time the mean muster, the WORK stream and the muster's share of it (numbers at P3's batch) |
| **build value while away** at least 70% (sessions) | 79.4%; the backlog's share 96.3% | **Met** (E3: 49%). once_per_session reads 48.5%, bank_bigs 63.1% |
| **mint swing** under 10% (`mint.in`'s (max − min) / max over a day of live time, sampled every 10 s) | sessions 35–75% a day (75, 65, 51, 35, 36, 49, 39, 41); continuous 41–95% | **Missed; recorded, not tuned.** The metric counts a day's growth as swing, but a town that doesn't change swings too: town_only (no build after 8.0 h) reads 32.2% every day from day 2, and static (its 4 start buildings, no mill) 26.6%. Both sit inside the pits' feed bonus (`pit.bonus` 0.6: (1.6 − 1) / 1.6 = 37.5%; the first day of static, first30 and pure_idle reads exactly 37.5%). So it isn't the mill (pits get first call, and static has none). That the feed itself cycles is an inference, not probed |
| **a clone or phylactery charge** before the first t2 and t3 raids | sessions and continuous raid t2 at 0.04 h (Vespers) and t3 at 0.09 h (Hollow Redoubt) with neither; the Chapel is a Village building (Village at 0.8 h, the first Chapel at 3.7 h, the first clone at 4.1 h). once_per_session: t2 at 4.0 h with neither, t3 at 8.0 h with a clone | **Missed, structural** for a bot that raids t2 and t3 in its first session; recorded, not tuned. No death went unmade: sessions' 14 are 8 phylactery and 6 clone |
| **relics** 6–12 a day under sessions, enough for 25 by day 5–8 (pacing-spine §4) | sessions 14, 13, 3, 4, 17, 10, 15, 11 (87 in 8 days, 34 by day 4), 25 on day 2; continuous 25 on day 1 (126 by day 4.84); once_per_session 47, 25 on day 5 | **Missed; recorded, not tuned:** 2 days of 8 in the band, and 25 three days early. The E4 handoffs wrote this target as "5–8 by day 4", which set a running total against the spine's day window |
| **a defined bone lever** (the spine's "bone-priced buildings removed costs 15%+"; §2 (b)) | ablation_bone (every bone price 0): Vei-ready day 5.17 against sessions' 6.0001, 0.83 days (14%) sooner; 156 levels against 117 at day 8 | **Undefined by construction:** a price of 0 removes a brake, so this ablation can only speed the game. A lever reading (bone replaced by a gold price, or bone gone as a resource) isn't built |
| **active play nudges the odds** (continuous 10–30% sooner, IDLE §8) | continuous 4.8358 against 6.0001: 19.4% sooner (4.8291 and 19.5% from 69542f2 through b475eb3, before 4f8b493's ready-vat hand moved the sim) | **Met** |
| **lots and stores** (lots full with `no_lot` not before day 2; no store above 2× its value 24 h earlier; bone at least 60% spent) | sessions: lots full at day 5 (120 h); gold at most 1.34× and bone 1.64× its value a day earlier; 96.2% of the bone spent | **Met** under sessions (continuous fills its lots at 30 h) |
| **carvers by tier** | ablation_keep isn't in the batch | Not measured at c15f874 |

**The queue jam (an autoplayer defect found here; fixed in Phase I P2 at fee92d6, below).** The bot's fill
(`Autoplayer._fill`) queued a lot's next level once the level below was built, building or queued, so it counted a
gated entry as that lot's level and chained more levels onto it. A gated entry kept its slot (`skipped_gate`), so 8 of
them stopped the queue while relic-free levels waited. It jammed town_only from 8.0 h and sessions on days 2.4–4.0,
which is sessions' 39 h without a finished building and its S2 gap. The game accepted the same queue from a player. P2
answered both halves: a gated entry holds no slot (IDLE §5's queue rule), and the fill passes over gated items (IDLE
§8's policies).

**Phase I P2's re-measure, at 88e18a6** (the queue rule and fill at fee92d6, the vat clip at 88e18a6; one seed). Only
pure_idle, town_only and sessions were re-run; the other 11 rows above stay c15f874's until P3's full batch. The digest
is `reports/economy/wip/tools-p2/batch-88e18a6.jsonl` (`summarize.py`, as above). The queue hours come from
`wip/tools-p2/qh_probe.gd` with `qh_bot.gd` (each close's queue starts and the last start and finish inside it;
`QH_PARK=1` adds a player who also parks gated builds in the list's spare room, which the queue rule lets cost nothing);
the Vei-ready backups from `wip/tools22/ve_probe.gd`; the day-2 town from `wip/tools-p2/bs_probe.gd`. catchup_accuracy
11 PASS / 0 FAIL; sessions_open fails only its known 3 (I1 days 1 and 2, and the first command answered otherwise,
old-sluice at 14 569 s).

| profile | measured at 88e18a6 (c15f874 in brackets) | verdict |
|---|---|---|
| **pure_idle** (a build or level per 6 h for 48–72 h, then a plateau with the chip) | 8 builds in its 7-day close (6), the last finished 1.96 h after the close (1.9 h), then none for 166 h; gold and bone at their caps (13 000, 350) from then. Its wall is the away report's `full_raid` line ("Your stores are full and the queue is empty: raid a fort for relics") at the load, 168.33 h; the queue holds nothing, so no relics chip (both read 168.33 h at c15f874) | **Missed, structural** (below). The Chapel and the Walls no longer hold 2 of the 8 slots, and the fill doesn't park them: at the Hamlet setup they are `lot_locked`, and `park_relics` parks only a `no_relics` entry |
| **town_only** (a plateau at 2–3 days, then "needs relics") | its last relic-free build at 33.9 h (day 1.41; 8.0 h, jammed); 50 builds (15); 12 buildings and 54 levels at day 8 (19 levels); stores full from day 2 (22 750 gold, 1 450 bone); the relics wall in the report from 8.0 h and as the queue's chip from 4.05 h. The parking player also ends at day 1.41 | **Missed: the relic-free content lasts about 1.4 days**, short of 2–3. The jam is gone; this is content depth, P3's question |
| **sessions** | Vei-ready **day 6.1667** (6.0001), one session later; backups at Vei-ready **1 + 6** (1 + 8), her pool 600 (600). The first Chapel at 7.52 h (3.73 h), the first clone at 8.09 h (4.09 h). 12 deaths: 4 phylactery, 7 clone, 1 unmade (14: 8, 6, 0). Next affordable: S1 median 29 min (max 1.5 h, 17 starts); S2 median 25 min (max **51.7 h**, 49 starts). Growth away: backlog 96.3%, build value 89.1% (96.3%, 79.4%). Relics 93 in 8 days (87). Lots full at 128 h (120 h). Bone at most 7.07× its value a day earlier (1.64×): the day-3 → day-4 recovery from the stall below | **Moved by P2's fill** (ruling 2), not by the vat clip: ve_probe reads 6.1667 and 1 + 6 at fee92d6 as at 88e18a6, and 6.0001 and 1 + 8 at 8b1e808 as at cac5a17. **The stock row is now missed** (bone above 2×) |

- **sessions' bone stall, days 1.01–3.18** (the S2 max). At day 2 the town has 21.75 workers for 31 slots. Staffing
  fills the haulers (6), the pits (10) and the stalls (5.75 of 6), and leaves the Bone Mill (0 of 6), the Forge and the
  Chapel's tend unstaffed. So bone income is 0, and bone sits at 77.8 of 550 for two days. The queue's head is the
  Embalmer (330 bone, 1 relic; `waiting_funds`, `no_bone`, `affordable_in_s` −1). It holds the queue (IDLE §5's
  processing rule) with 13 entries behind it, three new Raising Pits and three pit levels among them, which would add
  the workers. Gold sits at its cap. At 8b1e808 the same day-2 town has 6 Raising Pits at L2 (24 pit slots), every
  slot staffed, the mill running and the Embalmer built, and its queue still parks gated builds (the lot-21/22 pits,
  `lot_locked`; the Chapel's L2, `no_relics`). The old fill queued a gated build ahead, and it started when its gate
  cleared while away: the Chapel at 3.73 h at c15f874 (not measured at 8b1e808), against 7.52 h now. The P2 fill issues no command for it until a look finds
  it ungated, and by then other builds are queued ahead. (This reading compares the two queues and towns; the runs
  weren't traced build by build.)
- **The parking player** (`QH_PARK=1`, at 88e18a6). Sessions reaches Vei-ready at **day 5.1667**, with **1 + 10**
  backups (10 vats), and has no stall: every close but day 6's night starts a build. town_only's last build doesn't
  move (day 1.41). So the shipped fill is slower than a player who uses the queue rule, and P3's batch has to pick its
  fill (the milestone report has the question). Continuous wasn't re-run, so IDLE §8's "10–30% sooner" has no reading
  at 88e18a6. At c15f874 it was 4.8358.
- **How long a full queue lasts** (ruling 3; the 168 h close after one 20 min setup; hours after the close):

  | pure_idle's queue | entries at the close | last start | last done |
  |---|---|---|---|
  | `max_len` 8 (shipped) | 8 | 1.94 h | 1.96 h |
  | `max_len` 16 | 16 | 3.81 h | 3.86 h |
  | `max_len` 24 | 17 (all it can reach) | 4.19 h | 4.24 h |
  | 8, parking (list 16) | 8, plus 8 parked | 3.09 h | 3.11 h |
  | 16, parking (list 32) | 14, plus 18 parked | 4.13 h | 4.16 h |

  - In the parking runs the tier reaches Village during the close, and a few parked Village builds start.
  - The rest wait on relics (the Chapel, the Walls) or on the Town tier (the Ossuary).
  - From a Hamlet setup, the relic-free content is 17–21 builds, and income finishes them in about 4.5 h. So past 16,
    `max_len` isn't the limit.
  - **A real player's queue at `max_len` 8** (sessions' 15.7 h nights; hours after the close, last start). With the
    shipped fill: 2.04, 0, 0, 1.23, 5.23, 3.14, 9.16 and 4.41 h. The two 0s are the bone stall. With parking: 1.45,
    1.63, 3.36, 1.11, 1.18, 2.73, 0 and 1.27 h. In the 3.67 h day closes the last start is 1.82–3.61 h in with the
    shipped fill (none in the stall), and 0.95–3.55 h with parking.
  - **Ruled** (the run's manager, 2026-11-18): `max_len` stays 8; 16 would buy about 2 h. The 48–72 h pure_idle target
    is a relic-free content-depth question, and it goes to P3 with these numbers. P2 adds no depth.

**Phase I P3's calibration rows** (measured on 4ddc25c's tree with P3's harness, one seed unless a second is named;
P3's batch re-reads every row).
- **R-a, relics 6–12 a day and 25 by day 5–8: recorded, not tuned** (the run's manager, 2026-11-18).
  - Sessions banks 14, 11, 4, 7, 15, 23, 6 and 16 relics (96 in 8 days, 25 on day 2), and the trickle pays 13 more
    (about 2 a day from day 2).
  - By source (`reports/economy/wip/tools-p3/rel_probe.gd`, each loot joined to its raid):
    - day 1: 13 from the seven first clears (t1 3, t2 2, t3 8), and 1 from 6 held re-raids;
    - day 2: 9 from three t2 flips, and 2 from 13 held re-raids;
    - days 3–4: held re-raids only, 4 and 7 (12 and 17 raids);
    - days 5–8: re-flips of t3 forts Vei retook (7, 16, 0 and 11), and 5–8 a day from held re-raids.
  - So the steady part (held re-raids plus the trickle) is **4–9 a day**, and the spikes are flips: **day 1's 13–16**
    (both seeds, every variant below) and the t3/t4 push near Vei-ready.
  - The bot's relics are `balance_standins.json`'s `mean_loot` (the resolver opens the chest at yield 0). Cutting it
    moves neither spike:
    - t2/t3 −1, and t2 −1 with t3 −2: day 1 stays 13–14 and 25 still lands on day 2 (seed 1). The bot flips t4 sooner,
      so day 5 reads 28–41.
    - Every tier halved: day 1 stays 12–16 and 25 lands on day 3–4 (seeds 1 and 2).
    - Vei-ready doesn't move with the cuts (5.17 at −1/−2, 5.33 halved), so relics don't bind sessions.
  - A real change would be `loot.json`'s chest relics, which dungeon-i's raid code reads, so it stays. For the balance
    pass: day 1's 13–16 and the steady 4–9 a day, against the spine's 6–12.
- **R-c, the mint swing under 10% a day: the cause named, not tuned.** It's the body store's cadence, not a change in
  the town.
  - Probed in a new game left alone, 2 h in, at 1 s ticks (`reports/economy/wip/tools-p3/mint_saw_probe.gd`):
    - a convoy lands about 4 bodies every 21 s (17–22 s);
    - the one pit burns them in about 10 s (`pit.burn_per_s` 0.6 against rot's 0.175 in);
    - it then sits at the rot-only feed (`trough_feed` 0.292) until the next load.
  - So mint.in saws between 9.4 and 12.8 mass/s: pit.bonus × (1 − trough) / (1 + pit.bonus) = **26.6%**, static's day
    reading at c15f874 to the decimal. The mean doesn't move. The day's (max − min) / max reads that saw on every day of
    every profile: sessions 36–49% a day at 4ddc25c.
  - The digest's new `mint_swing_win` reads the swing of the day's 600 s window means, so the saw averages out and the
    day's drift stays: town_only **2–4% a day** from day 2, sessions 4–18% a day (its growth).
  - A sim fix would be a steady pit draw: the pits burn at the store's mean inflow rather than each landed load. It keeps
    the mean mint and removes the saw. That's a MECHANICS change the catch-up reads (I1 bounds the bodies), so P3 doesn't
    make it.
- **R-d, a defined bone lever:** §2 (b), rebuilt. Never Vei-ready, and 79% fewer levels at day 8.
- **V-b, seeded wave jitter: not shipped** (the run's manager's ruling on P3 handoff 7, option (c); the patch is kept as
  `reports/economy/wip/tools-p3/vb-jitter.patch`).
  - Measured at a = 0.15 with "safe" read at the jitter's top, over 20 seeds: away_risk_real's prepared_72h lost
    **0 of 20** absences (0 of 120 forts), and midgame_prepared 0 of 20 (0 of 40).
  - The cause: the prepared setups leave at the WAR the bot already plays (0.80 and 0.75), and every held fort reads
    safe even at the top draw (the smallest base margins are 1.91 and 0.47 mass/s), so no draw within ±15% breaks one.
  - Shipped, it would turn most held forts' word "thin" with the loss still 0. margin_truth would go vacuous: its only
    safe samples, midgame_2flips' Ashgate, read thin under the jitter.
  - **The target is replaced.** "A prepared away loses 10–25%" came from a vision check, not from Shawn. His words are
    "you should be able to lose all but the home town if you're away and it's not properly tuned to be supported"
    (vision.md, 2026-11-13). Two checks replace it, both in the batch: **a prepared away loses 0 forts**, and **an
    unprepared away loses some**.
  - At 4ddc25c: prepared, 0 of 20. Unprepared: midgame_default loses 1 of 2 (Old Sluice retaken), and default_72h loses
    0 of 6 (it leaves at the WAR the bot plays).
- **Fronts (b), "the fronts bind again": missed, recorded (option (a)); the needs ship as they were.**
  - The target (the run's manager, 2026-11-18): sessions' Vei-ready at about day 6.0 and continuous 10–30% sooner, by
    raising `vei.json`'s front needs alone (not `odds.time_s` or the 0.7 weight), in at most three probe rounds.
  - Two rounds at 180121f's tree (this table's sim; the text-only commit after it doesn't move it). Round 1 (one seed),
    then round 2 on seeds 1–4 in both modes. Tools: `reports/economy/wip/tools-p3/vr_probe2.gd` (the boss seed taken
    at her node the moment Vei-ready is set; the old `vr_probe.gd` printed the day-8 end state), `vr_probe3.gd` and
    `sweep.py`; logs in `vr1/` and `vr2/`.
  - **Today the readiness clock sets Vei-ready, not a front.** Sessions reads 5.1667, 5.3333, 5.0 and 5.1667 on seeds
    1–4, continuous 5.0518, 5.1594, 5.0331 and 5.1018: 2%, 3%, −1% and 1% sooner.
  - **No front's have runs ahead in continuous.** At the same hour the two modes' backlogs are within 8%, and which
    one leads changes with the seed. At day 5.0: 80.1M against 80.9M, 78.5M against 72.5M, 82.3M against 87.0M, and
    78.8M against 79.7M (continuous against sessions). Giants and carvers lead in neither mode across the seeds. At E4
    step 3 continuous's backlog ran ahead (204M against 140M at day 8), which is where the odds row's 19.5% above came
    from; at 180121f it doesn't.
  - So continuous's only edge is *when* it looks. It can reach her at any hour, and sessions only at a session's start.
    A front that both modes clear at about the same time gives a lead only when it clears in the night's gap, after
    sessions' last look of day 5 (5.347) and before its next (6.0).
  - **Swarm and raw** follow the backlog, and their needs don't move the bot. Only giants' and carvers' wants steer the
    slab fill and the keepers (`Autoplayer._big_want`). At swarm 45 on seed 1 the bot raised the same 18 bigs as at the
    shipped needs, up to Vei-ready. So one never-ready trace per seed and mode gives Vei-ready at any swarm or raw need
    (`sweep.py`). Continuous / sessions (how much sooner):

    | swarm need at pool 600 (need_base) | seed 1 | seed 2 | seed 3 | seed 4 | seeds ≥10% sooner |
    |---|---|---|---|---|---|
    | 24 (12), shipped | 5.05 / 5.17 (+2%) | 5.16 / 5.33 (+3%) | 5.03 / 5.00 (−1%) | 5.10 / 5.17 (+1%) | 0 of 4 |
    | 42 (30) | 5.13 / 5.17 (+1%) | 5.17 / 6.00 (+14%) | 5.03 / 5.00 (−1%) | 5.18 / 5.17 (−0%) | 1 of 4 |
    | 45 (33) | 5.35 / 6.00 (+11%) | 5.50 / 6.00 (+8%) | 5.26 / 5.17 (−2%) | 5.44 / 5.17 (−5%) | 1 of 4 |
    | 48 (36) | 5.58 / 6.00 (+7%) | 5.72 / 6.00 (+5%) | 5.26 / 6.00 (+12%) | 5.66 / 5.17 (−10%) | 1 of 4 |
    | 51 (39) | 5.84 / 6.00 (+3%) | 5.94 / 6.00 (+1%) | 5.26 / 6.00 (+12%) | 5.66 / 6.00 (+6%) | 1 of 4 |
    | 54 (42) | 6.14 / 6.17 (+0%) | 6.17 / 6.00 (−3%) | 5.26 / 6.00 (+12%) | 5.66 / 6.33 (+11%) | 2 of 4 |

    Swarm 51 puts sessions at 6.0 on every seed, but continuous is only 1–12% sooner. At every need from 41 to 57 at
    most two seeds reach 10%, and every row but 51 has a seed where continuous is later. Swarm's per-seed spread (presence bigs
    in the party at the look: ±3, a quarter of a day of backlog) is wider than the night's window. Raw has the same
    shape. The real run at swarm 45 on seed 1 confirms the sweep: sessions 6.0001 (the walk to her node), continuous
    5.3547 (as swept; 10.8% sooner).
  - **Giants and carvers** move the bot, and not monotonically (round 1, seed 1; re-run at 180121f with the fixed probe,
    the same to the digit). Every need ×1.15: sessions never (giants stuck at 11 of 16.1), continuous 5.0196. ×1.3:
    sessions 5.0066, continuous never. The cause is the keepers' rule (`KEEP_SHARE` 0.25, `_keepers`). A big stays home
    on giants only if its wits are at least a quarter of giants' want, so raising the need raises the bar. At ×1.15
    (bar 4.03) the later wits bigs (2, 2, 3 and 4) raided and were lost, and nothing closed the 5-point gap. At ×1.3
    (bar 4.55) a wits-7 hulk arrived and cleared it. The want also steers the slab fill (`_slab_fill`), so the paths
    split at the first raise after the change: sessions at 24–28 h, continuous at 101 h. What a need does is a step on
    which husks and remnants a path draws, not a slope.
  - **The best case, and its cost.** Swarm 45 gives seed 1 11% and seed 2 8%, but seeds 3 and 4 come out later in
    continuous. It also breaks the demo seed (pool 380, backlog 55.35M), which reads swarm 27.7 against a need of 40.6
    (19.6 today). That's 2 fronts of 4 met where its doc says "3 of 4, raw short", and the demo floor (6/20) rests on
    it.
  - **What it needs:** a lever outside the needs, something continuous play builds faster than sessions does (for
    example the fronts reading what raids bring home, or the backlog running ahead again). That's a product question
    for the milestone, not a P3 tune. The faithful grade uses sessions' 5.1667 seed (seed 1, captured at her node: 1
    phylactery and 6 clones, readiness 0.6053, pool 600, backlog 85.04M).

**Phase I P3's batch, at f957849** (the 15 profiles on `git archive f957849`, one seed, with the parking fill and the
skip-fill ablation row; `reports/economy/wip/tools-p3/pbatch.sh`; digest `b-f957849-digest.txt`, logs `b-f957849/`).
Its sim is 4ddc25c's: f957849 moves only readouts and text, and every row but the new fields reads as 4ddc25c's batch
did (ablation_bone is 180121f's rebuilt variant). The targets are the phase-i-draft §4 table's.

| target | measured | verdict |
|---|---|---|
| **pure_idle grows 48–72 h** | its last build is 49.8 h into the 7-day close that starts at 0:20 (50.1 h of game time); builds per 6 h 21, 7, 5, 4, 4, 2, 2, 2, 1, then none | **Met** (the ramp, 4ddc25c; Grow on) |
| **town_only plateaus at 2–3 days** | the last build at 48.19 h, 2.01 days (4ddc25c's `qb_probe`, the same sim; the batch's `builds_per_6h` reads only its longest close, the night) | **Met**, 0.19 h inside |
| **next affordable**, the gaps between queue starts: S0 10–40 min, S1 1–3 h, S2 4–10 h | sessions: S0 median 11 min (max 22 min, 2 starts); S1 median 19 min (max 1.9 h, 52 starts); S2 median 1.6 h (max 6.3 h, 52 starts) | **S0 met; S1 and S2 missed**, the cause the c15f874 table's row above names: starts bunch inside the sessions |
| **away build value** 70% or more | sessions 87.2% (the backlog's share 96.1%) | **Met** |
| **mint swing** under 10% a day | `mint_swing_win` (the 600 s window means): sessions 79, 6.6, 6.6, 18, 8.7, 4.6, 4.4 and 5.4%; town_only 73, 19, 2.5, 1.8, 3.0, 2.1, 3.0 and 4.2%. The raw reading is 23–95% | **Recorded with its cause (R-c, above).** The windows remove the convoy saw (26.6%); what's left is a day's growth (day 1's opening, sessions' day 4). A steady town reads 2–4% |
| **relics** 6–12 a day | sessions 14, 11, 4, 7, 15, 23, 6 and 16 (96), with the trickle 13 more | **Recorded (R-a, above):** day 1's first clears and the t3/t4 re-flips, a steady 4–9 |
| **first Vei attempt** 40–60% | the faithful grade at sessions' 5.1667 seed, its own 1 + 6: 9/20 (45%). The odds it reads, 0.46 (refit) | **Met** |
| **continuous** 10–30% sooner than sessions | 5.0518 against 5.1667: 2.2% | **Missed, recorded (fronts (b), above):** no front runs ahead in continuous, so the needs can't make the lead |
| **a prepared away loses 0 forts** (replaces "loses 10–25%", V-b) | away_risk_real prepared_72h 0 of 6, midgame_prepared 0 of 2; away_risk prepared (24 h) 0 of 6 | **Met** |
| **an unprepared away loses some** | midgame_default 1 of 2 (Old Sluice); away_risk default (24 h) 1 of 6 (Chime Fort); default_72h 0 of 6 (it leaves at the WAR the bot plays); the WAR cuts 6 of 6 and 2 of 2 | **Met** |
| **ablation_held** costs 20–25% | 83 levels against 126 at day 8 (34%), and never Vei-ready; 12 raid relics, with the trickle 13 more (R-b) | **Missed, recorded:** the relic wall shrinks with R-b's trickle (77% before) but holds. The trickle's 2 a day stands against sessions' 12 |
| **clones at Vei-ready per profile** (P1's vision check (b)), graded at each count on sessions' seed (score 65) | continuous 1 + 10: 16/20 against odds 0.59; sensitivity 1 + 10 (day 5.1667): 16/20 against 0.60; sessions and static (day 5.3334) 1 + 6: 9/20 against 0.46; ablation_skip_fill 1 + 4: 5/20 against 0.23; once_per_session 1 + 2: 1/20 against 0.07 | **Within ten points except at 1 + 10**, which reads 20 points low (the form's ceiling, the odds row above). The grades hold sessions' party, pool and backlog and change only the backups |
| **the I1 check** (sessions_open, under parking) | the known 3 FAIL (I1 day 1, day 2, the commands; first divergence at 86 400 s, a `craft_husk`) | **As before, no new FAIL** |
| **R-b's trickle** | sessions 13 paid (a fort held a day) | **Met** |
| catchup_accuracy, margin_truth (slow) | 16 PASS / 0 FAIL; 34 PASS / 0 FAIL | **Pass** |

The husk price (housekeeping): `economy.craft.husk` costs 500 bone against a new game's 200 bone cap. So the craft waits
until Bone Mill levels lift the cap past 500 (the ramp's caps 300, 700, …). Not changed: no P3 row calls for it. Bone
binds the town's levels (the ramp), not the crypt, and relics don't bind sessions (R-a).

### P3b: the active nudge's sizing (V-I2 (a); the run's manager's re-set aim, continuous 5–10% sooner than sessions)

vr_probe3 without trace, seeds 1–4, Vei-ready day (backups at it). The lever is the readiness's raid credit
(`odds.raid_credit`, `raid_credit_cap`); the front needs are unchanged.

| round | values | sessions | continuous | gap, mean (per seed) |
|---|---|---|---|---|
| P3 | none, time_s 4 d | 5.167 (1+6), 5.333, 5.0, 5.167 | 5.052, 5.159, 5.033, 5.102 | 1.5% (2.2, 3.3, −0.7, 1.3) |
| 1 | 0.00075 a raid, cap 0.12, time_s 4 d | 5.000 at every seed; seed 1 with 1+4 | 4.492, 4.497, 4.473, 5.102 | 7.2% (10.2, 10.1, 10.5, −2.0) |
| 2 (shipped) | 0.00075, 0.12, time_s 4.5 d | 5.167 (1+6), 5.333 (1+10), 5.009 (1+8), 5.167 (1+10) | 4.795 (1+10), 4.824 (1+12), 4.809 (1+8), 5.102 (1+10) | **5.5%** (7.2, 9.6, 4.0, 1.3) |

Round 1 lands the gap but moves every sessions run a session early, where seed 1 has 1+4 (graded 5/20): the first
attempt would leave 40–60%. Sessions seed 1 sits 0.0035 under 0.6 at day 5.0, so any credit tips it. Round 2 slows
the time term to hold sessions' pacing. The faithful grade at round
2's sessions Vei-ready (seed 1, day 5.1667, readiness 0.604): 1+6 9/20 (the first attempt, in band), 1+4 5/20, 1+2
1/20, 0+0 0/20, 1+10 16/20. Seed 4 gains least: its continuous run is front-limited (fronts met at day 5.10).

**Ruling 35 (the run's manager, 2026-11-18, accepted; reversible): `odds.time_s` 4.5 days.** The aim was "active
play sooner, sessions unchanged", and time_s is economy's own knob, so round 2 ships: the time term slows by what the
raid credit adds, sessions keep P3's Vei-ready and continuous comes 5.5% sooner. **The spread is accepted too:** the
mean is 5.5%, seeds 3 and 4 sit at 4.0% and 1.3% (seed 4 front-limited), and the front needs stay as they are. **To
reverse it:** `odds.raid_credit` 0 with `time_s` 345 600 is P3's readiness bit for bit; pre_vei's away report
(test_backups, test_stances, test_big_undead) is re-pinned with it (its odds line moves; the state and events don't).
024c11a's message has the proof that P3's whole odds block passes the pins from before P3b.

**Ruling 37 (the run's manager, 2026-11-19, accepted; reversible): the 7-day catch-up budget is 12 s on jenova; 12 h
stays under 2 s** (IDLE §4 Budget, which said 10 s). P9's bench (`catchup_bench`, best of 3 on the d470898 archive)
read 7 days at 11.51 s (midgame_2flips), 11.08 s (pre_vei) and 9.71 s (fresh), and 12 h at 1.46–1.83 s. 80% of a
core step is the two solvers, and the one structural lever, a longer step past 12 h, is closed (15 s is
`idle.catchup_dt_long_s`'s accuracy cap). A week is the sanity cap (`idle.catchup_max_s`), reached once after a week
away, and it runs in chunks of 90 core steps (median 31–39 ms) behind the catch-up progress screen, so the game stays
responsive. **To reverse it:** 10 s again needs about 35 µs off each core step (`fort_step`, `_dispatch`,
TownSim.step) with every catch-up pin re-proved bit for bit: the solver-speed unit, on the Phase II backlog.

## 6. Known balance risks
- **The knife edge** (systems review S5). Odds of 0.6 need a backlog of about 18,000 raw. Vei's undead
  capacity is about 42/s at q 1.2 and about 20/s at q 2.5, so the active run needs about 5–8 pits and
  `q` > 2. Calibrate pits, `K` and `S_vei` together in E4.
  - **E4 step 3: there is no knife edge in the live game.** The town's inflow outruns her digestion all run, and the
    backlog grows to about 1e8 by day 8. So `K` and the fronts' `per_backlog` were sized for that scale (§5), not for
    18k.
- **Redirect value at low `q`** is small under `cheap`. If the +30% ablation fails, raise
  `raise_rate` or let the redirect add the haul bonus.
- **FLOOD as a no-brainer** once `q` is high. The tithe waves and WORK's diminishing returns must keep
  the split moving; the static-schedule ablation checks it.
- **Gold:** the living cap and upkeep tiers must hold the stock rule. The store caps (above) bound gold
  and bone from E2b-2; pre_vei's gold falls (−0.47/s) and its bone sits over its cap.
  - **The gold trap (E4 step 4): the resume rule's absorbing state.** A town whose full upkeep exceeds its gold
    income sheds buildings at the floor. MECHANICS §4.3's resume rule then re-admitted one the moment the gold
    covered a hold of the paying upkeep plus its own, so any surplus went to the next, and the gold could never climb
    past one hold while anything stayed unpaid. Sessions pinned at 27.00 from day 5 (2bb8bca through 2fe96cc), with
    every queue entry over 27 g, the gold lever (Market L4) among them. Two fixes, both in: the queue's upkeep gate
    (MECHANICS §4.4: a new building whose upkeep would take net gold negative is skipped, reason `upkeep`) closes the
    way in, and sessions no longer reaches the floor (day-end gold 13 067 at its lowest, day 5). The resume rule's
    income test (§4.3, `upkeep.resume_net_min` 0) closes the trap itself: pre_vei past its floor now saves +0.01 g/s
    and passes the Market's next level in about 20 min (test_gold_trap). Gold income that grows with the town (lever
    (iii)) is left to step 9, only if its calibration needs it.
- **Rate normalisation** (`view.rate_log_max`, 25/s on the map today) saturates at the new flow
  sizes, so it moves into config.
- **The Vei fight's feel** won't converge until `vei.json` is tuned against real circles.

## 7. Town growth over days (direction 2026-11-14, trials G3 and G4; the adopted structure is in the configs since T7)
Town's G2 run (day1, 4 h, following "suggested", no raids; `runs/.../reports/town/g2-log.tsv`) stalls:
the workforce sits at slots + `idle_cap` = 19 from minute 4 to hour 4, gold binds first (one Market,
net +0.06/s after upkeep), all 17 Village lots fill with wells and houses by 1:00, and 2,228 bone has
no sink. The whole relic-free build tree costs about 4,600 gold and 1,680 bone, about 20× too shallow
for IDLE §8's "growth continues 2–3 days without raids". Full analysis: `reports/pacing-spine.md`.
The realm has headroom to spare (test_pacing), so **the town and the relic supply are the throttle**.

Direction (manager's decision, reversible; numbers are E4's):
- **Bone buys the dead's buildings, gold the living's.** Raising pit, charnel, mill, stables,
  graveyard, embalmer and forge cost mostly bone. Market, house, well, bakery and inn cost gold.
  Gives bone a sink and stops gold binding the undead economy. *To trial first.*
- **A deep level ladder instead of more lots.** Levels 4–8 for the job buildings and houses, about
  1.6× per level, bone-heavy, relic-free to L5. Upgrading in place is the compounding that survives
  lot caps. The suggestion prefers an upgrade over filling a new lot. *To trial first.*
- **Pits get first call on bodies;** the mill takes only the surplus. This stops the 30% mint swing
  (12.8 ↔ 8.98/s) caused by the mill eating the pit's feed. *Adopted.*
- **A visible no-raid plateau.** Without relics the town reaches full Village and every relic-free
  level (about 2–3 days of growth), then shows "needs relics: raid a fort". *Adopted* (town's 4c row).
- **Held back until the trial is measured:** a second gold source (rent from the living; it risks
  making gold the next bone), bone from worker rot, and bone-bought outskirts lots.
- **Coupling:** every town fix keeps more workers in slots, so less musters to WAR. Town and realm
  pacing are measured together, by E3's profiles (`sessions`, `sessions_open`, `continuous`,
  `pure_idle`, `town_only`, `away_risk`; metrics in `reports/pacing-spine.md` §4).

**Trial G3 (2026-11-14, `reports/town/g3-trial.md`; config overrides, 4 h on day1, no raids):**
- Bone-priced dead's buildings **deadlock** if the bone mill, the only bone source, is bone-priced too
  (day1 has 30 bone). With the mill's first level kept at gold (A2/B2), growth is real: slots go
  9 → 32–37 and mint 12.8 → 32/s by 4 h, 67–90% of bone income is spent, and after the lots fill at
  about 1:06, upgrades carry the growth.
- **Gold binds next.** Net gold is +0.04/s from 1:30 (one Market against 17 buildings of upkeep), every
  upgrade reads no_gold at 4 h, and B's deep ladder barely starts (two L4s).
- **Lots go to amenities.** 7 wells, 3 houses and a bakery take the lots that Walls and the Chapel need,
  so no tier-up happens in any run.
- `idle` sits at `idle_cap` (10) whenever inflow outruns slots, by design (the surplus musters). The
  spine's "idle ≤ 3" metric is wrong; measure slot growth and the muster rate instead.

Updated direction:
- **Each resource's producer is bought with the other resource.** The bone mill costs gold, and the
  Market costs bone. Every other dead's building costs mostly bone, every other living building gold.
- **Relic costs never fall with level.** G3's rule put L4–L5 at 0 relics after L3's 2–6; that's wrong.
- **The suggestion keeps lots for the next tier's gate buildings,** and the no-need fallback never
  takes them.
- Still held back: rent as a second gold source, pending trial G4.

**Trial G4 (`reports/town/g4-trial.md`; C = G3's B2 + the Market bought with bone + monotonic relics +
gate-lot reservation; 8 h on day1, no raids):** growth runs the full 8 h with no wall. Slots go
9 → 18 (1 h) → 38 (4 h) → 53 (8 h), with 31 upgrades by 4 h, levels reach L5, and the gate lots stay
free. The binder flips: gold piles up (+1.26/s, a 20k stock at 8 h) and bone binds (89–91% spent).
Growth slows (about +3.8 slots/h over 4–8 h), and 186 of 240 chunks pick nothing (short of bone, or
gates short of relics). Rent was not trialled (it needs TownSim code), and it isn't needed: gold is now
in surplus.

**Adopted structure (in the configs at this commit, T7: G4's C exactly, bar the Bone Mill's level 1, gold-only since F1: §5; `buildings.json`, the cost table
in §5; E4 tunes the numbers):**
- the dead's buildings cost mostly bone; the bone mill stays gold-priced at its level 1 and the Market is
  bought with bone (each producer is bought with the other resource);
- a level ladder to L8 for the job buildings (raising pit, charnel house, market, bone mill, forge,
  chapel of vats) and the house; the ladder adds no relic price below L6 (the Forge keeps its own, 1, 2, 3, 3, 3 at L1-L5, and
  the Chapel of Vats its own, 2, 4, 6, 6, 6), with relic costs that never fall with level; the
  charnel house's `body_cap` table runs on to 8 entries (+50 a level, 350 at L8);
- the bone cap grows with the ladder: the Bone Mill's `bone_cap` is a table per level, 100, 150, 350, 700,
  1 250, 2 050, 3 400, 8 400 (caps 300 to 8 600). **Phase I P3's depth** (below; the ramp, shipped after the step)
  scales the dead's buildings' bone ×2.0 at L3, ×3.0 at L4 and ×4.6 from L5, and puts the mill's cap a level ahead:
  100, 500, 1 450, 3 940, 6 470, 10 150, 16 360, 39 360 (caps 300, 700, 1 650, 4 140, 6 670, 10 350, 16 560,
  39 560). The rule (§5, Store caps): each level's cap covers 1.2 ×
  the mill's and the Market's next level, rounded up to 50, and the top level's every bone cost (the
  Forge's L8, 39 445 under the ramp); `tests/test_build_ladder.gd` checks that every price fits a cap reachable by its
  building's tier. The Market's `gold_cap` stays 3 250 a level (32 500 at L8). G4 ran on town's branch
  before the store caps (8f73c36 has no gold or bone cap), so its 8 h says nothing about a capped
  ladder; with the linear 100 a level the climb stops at mill L4 (cap 600) and every price above it is
  stuck;
- the suggestion reserves the next tier's gate lots (town code, 8f73c36) and prefers upgrades;
- pits get first call on bodies (40d62c0).
- **E4's job:** split costs so that **neither resource piles up**. Both should be ≥ 60% spent, and the
  binder should alternate (today gold piles once the Market is bone-bought). Give gold real sinks: tier
  gates, living buildings, upkeep that scales with level. Measure where the no-raid plateau lands with
  E3's `pure_idle` and `town_only` profiles (target: 2–3 days, then "needs relics"). L6+ relic costs
  are untested without raids.
- Rent is dropped.

**Phase I P3's depth (Q-b; the run's manager's ruling of 2026-11-18: the Grow stance, then one depth pass sized on
pure_idle and town_only together for 48–72 h).** Shipped from 7cb0899 to 7c4a8f8 as the step below; **the ramp
replaced it** (the last paragraph of this section: the run's manager's ruling 1 on handoff 6). The step: one
multiplier, 3.5, on the **bone** price of every level from L3
of the dead's buildings (raising pit, charnel house, Market, Bone Mill, Forge, graveyard, Stables, Embalmer, Chapel of
Vats, the Crypt), relic levels included so the curve never falls from L5 to L6, and on the Bone Mill's bone cap from
its L2 (the cap at a level is (200 + table) × 3.5, so each still covers 1.2 × the mill's and the Market's next level and
the Forge's L8, 30 010, fits L8's 30 100). Left alone: every level 2 (the S0 spine: the mill's, the Market's and the
pit's L2 are its first buys), every gold price (gold isn't the binder: it sits at its cap in every profile), and the
living's buildings (House, Well, Bakery, Inn: bought with gold, and the House's handover rule above keeps its steps
at 2.5× or less and its L4 and L5 under a new game's 200 bone cap). Gold scaling was ruled out too: the Chapel's L8
at 3.5 × 9 450 gold is over the Market's L8 cap (32 500). Sized with `wip/tools-p3/qb_probe.gd` (`QB_COSTMULT`, the
whole level costs from L3 of every relic-free level, the cap from L2; 65a4990's tree plus
`wip/tools-p3/grow-step1.patch`, the step-1 rule, and the `max_active` cap, which moved nothing): the last build of
pure_idle's 168 h close and of town_only's 8 days, both ending with every relic-free level built:

| multiplier | pure_idle | town_only |
|---|---|---|
| none, Grow off (shipped before P3) | 3.69 h (14 builds) | 33.9 h (50) |
| 1, Grow on | 22.6 h (50) | 20.7 h (50) |
| 2.0 | 35.9 h | 35.4 h |
| 2.5 | 42.9 h | 42.5 h |
| 3.0 | 49.9 h | 49.8 h |
| 3.5 | 56.8 h | 56.4 h |

The time is linear in the multiplier (about 14 h per unit), and town_only tracks pure_idle within half an hour: with
Grow on, both are bone-bound on the same relic-free ceiling (12 buildings, every one at L5, the Stables at L3). Bone
only on every L3+ level of every building gave the same 56.8 h / 56.4 h at 3.5. **The step as shipped at 7cb0899** (the dead's bone only,
the living's buildings left alone; measured with the same probe on 7cb0899's configs, no overrides): pure_idle's
last build 52.8 h into its close (50 builds, 36 of them Grow's), town_only's at 54.2 h (day 2.26; 50 builds, 16
Grow's); next-affordable gaps S1 median 28 / 20 min, S2 median 1.8 / 1.8 h. sessions (raiding) reaches the City tier
with 123 builds in 8 days (27 Grow's, the last at 69.1 h), still building at the close; its S0 gaps are unchanged
(median 700 s, max 1 300 s), S1 median 16 min, S2 median 1.9 h. These are probe readings on one seed; P3's batch
measures every profile. The step from L2
to L3 is now steep on the dead's buildings (the pit's 305 to 1 575 bone, ×5.2, against ×1.5 before), a side effect
of leaving L2 alone.

**The ×4.4 ramp, probed and not taken (for the V-I2 vision check).** The run's manager's ruling on handoff 4 (4): replace
the step with a ramp over L3 to L5 if one re-probe keeps pure_idle and town_only in 48–72 h with the S0 gaps
unchanged, else keep the step. The one candidate, fixed before the run so as not to lose depth: 65a4990's bone on the
same buildings ×2.0 at L3, ×3.0 at L4 and ×4.4 from L5 (relic levels too; about the step's total over L3–L5 for
pure_idle's buildings), the mill's cap a level ahead (L2 ×2.0, L3 ×3.0, L4 up ×4.4: 500, 1 450, 3 760, 6 180, 9 700,
15 640, 37 640), so the pit's ladder reads 305, 900, 2 160, 5 060 (×3.0, ×2.4, ×2.3 a step). qb_probe on 7cb0899 with
that `buildings.json` (`wip/tools-p3/ramp.py`; digests `qb-{pi,to,se}-ramp-7cb0899.txt`): pure_idle's last build 49.2 h
(the step 52.8 h), **town_only's 47.4 h (the step 54.2 h): 0.6 h under the band**, so the step stays. S0 was unchanged
(first30: 3 starts, median 96.5 s, max 1 449.5 s; sessions 700 / 1 300 s, both as the step), and the ramp evened the
middle: town_only's S1 longest gap 2.1 h against the step's 3.6 h. A top a little steeper (about ×4.6) would likely pass;
per the ruling it wasn't iterated. sessions reached the City with 122 builds either way.

**The ramp, shipped (×2.0 L3, ×3.0 L4, ×4.6 from L5; the run's manager's ruling 1 on handoff 6, after the 08:17
ruling).** The ×4.4 ramp above with its top at ×4.6: 65a4990's bone on the same buildings, relic levels too, and the
mill's cap a level ahead (§5's ladder bullet: caps 300, 700, 1 650, 4 140, 6 670, 10 350, 16 560, 39 560, each
covering 1.20–1.24 × the mill's and the Market's next level; the Forge's L8, 39 445, fits). The pit's ladder reads 305,
900, 2 160, 5 290. Every L2, every gold price and the living's buildings are unchanged, as in the step. Built with
`wip/tools-p3/ramp.py <scratchpad with b-old.json> <out> ramp 4.6` (`step` reproduces 7cb0899's file, a self-check).
qb_probe, one seed, on 7c4a8f8's code with this file (digests `qb-{pi,to,se}-ramp46-7c4a8f8.txt`; pure_idle and
town_only re-read line for line on this commit's tree), against the step on the same code (`qb-*-cfg-7c4a8f8.txt`):

| reading | the step (×3.5, shipped to 7c4a8f8) | the ramp (shipped) |
|---|---|---|
| pure_idle last build | 52.84 h | **50.03 h** |
| town_only last build | 54.24 h | **48.19 h** (0.19 h inside the band) |
| S0, pure_idle / town_only (qb) | 1 start, 100 s | 1 start, 100 s |
| S0, sessions (qb) | median 700 s, max 1 300 s | 700 / 1 300 s |
| S0, first30 (autoplay_first30) | 3 starts, median 96.5 s, max 1 449.5 s (at 7cb0899) | 3, 96.5 s, 1 449.5 s |
| town_only's longest S1 gap | 13 017 s (3.6 h) | 7 422 s (2.1 h) |
| pure_idle's longest S1 gap | 8 206 s | 5 655 s |
| sessions | 191.05 h, 127 builds, City | 188.94 h, 122 builds, City |

Both profiles land in 48–72 h, S0 is unchanged, and the ramp evens town_only's middle. **town_only's 48.19 h sits only
0.19 h inside the band**, so a later cost change can push it out. **The rule for that (the run's manager's ruling 1 on
handoff 6):** if any later P3 change or the balance pass drops either profile below 48 h, raise the ramp's top step;
don't go back to the ×5.2 step (the step's L2 → L3 cliff, the pit's 305 → 1 575 bone). These are probe readings on
one seed; P3's batch measures every profile.

## 8. Balance stand-ins (E3-6a; `configs/balance_standins.json` v0)
The autoplayer (E3-6b) can't run the dungeon headless. `tests/autoplay/standin_resolver.gd`
(`StandinResolver.resolve(seed, standins, cfgs, opts) -> {result, duration_s, died, notes}`, a test harness, static,
no Engine) turns the seed `cmd_begin_dungeon` issued into a raid result v2 that the real `apply_result` takes, drawn
from what the dungeon unit measured. Only the resolver and the autoplayer read the file; `scripts/sim/` never does
(`tests/test_standins.gd` checks). The numbers are the dungeon unit's raw rows at afb8dab (the run's
`reports/dungeon`), rounded to 3 places, and each entry's `source` names its file, iteration and seeds.

**The rulings** (the run's manager, for Shawn):
- Loot and outcome rates are the frozen bot's at score 70 (`standins-raw-afb8dab.tsv`, iter `grade-standins`; by_tier
  and first_dungeon in `standins-measured.json`).
- Deaths and durations are the typical human's (score 70, delay 1.0, read 1.0, draw 0.7; `calibration-dd-raw.tsv`):
  - the death rate is pooled over seeds 20–39 (`hb70d10`, the rows task 6 and the grading pass compare against)
    and 40–59 (the grading pass, `grade-*-human`, rep 0) where both exist;
  - the duration is the grading pass's median per-run estimate (NOTES-RAID at 128c95a, "Length");
  - `death_rate_frozen` is `by_tier.<T>.70`'s, for E3-6b's one sensitivity pass (`opts.deaths: "frozen"`).
- A held fort's raid has no measured stand-in (GUESS, below). The held door uses its grading-pass arm (b).
- No boss stand-in: E3 measures Vei-ready, not the fight. The bot never retreats a fresh fort.

**Each entry** (`"1"`..`"4"`, `"first_dungeon"`, `"held_door"`):
- `death_rate` (human) and `death_rate_frozen`;
- `duration_s` (the human estimate's median) and `duration_s_frozen` (the frozen bot's median scene seconds);
- `death_t_frac`: a death ends the run at this × `duration_s`. It is the median human estimate of the died rows over
  that of all the rows, the same rows as `death_rate`;
- `mean_loot` {relics, remnants, husks, blueprints, essence}: the frozen bot's warden_beaten rows. A death is rolled
  apart, so the all-exits means in `by_tier` would count it twice. The first dungeon's chest husk and first-clear
  blueprint are taken out: the resolver adds them from the seed's `chest_husk` and `first_clear`;
- `kept_frac`, per kind: what a death banks of `mean_loot` (STATE-API §8.1: banked loot only). It is pooled over the 27
  died rows at tier (t2 7, t3 8, t4 12), each against its own tier's win;
- `mass.won` and `mass.died`:
  - `killed_frac`: killed_living_mass over the seed's living **mass** (`living_start` is a count of living units);
  - `raised_per_living_unit`: raised_count over living_start;
  - `garrison_survive_frac` and `raised_survivors_per_living_unit`: allies_end less the party standing and the
    starters, the garrison taken in counted first, the rest per living unit.
  - `mass.died` is the 27 pooled died rows in every entry;
- `party_lost_per_member`: a member's chance to be lost on a win (the won rows' party_lost over the profile's bigs);
- `revives`: 0.0 everywhere (the profile seeds carry no charge);
- `source`.

| entry | death_rate (human) | frozen | duration_s | frozen | death_t_frac | relics | remnants | husks | essence | party lost / member |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | 0.117 (7/60) | 0.0 (0/48) | 160.1 | 106.1 | 0.203 | 1.356 | 2.533 | 0.222 | 5.756 | 0 (no big) |
| 2 | 0.175 (21/120) | 0.117 (7/60) | 168.5 | 116.4 | 1.279 | 2.423 | 4.135 | 0.231 | 6.0 | 0.712 |
| 3 | 0.158 (19/120) | 0.133 (8/60) | 190.8 | 122.7 | 0.959 | 3.941 | 5.451 | 0.412 | 2.941 | 0.48 |
| 4 | 0.208 (25/120) | 0.2 (12/60) | 169.3 | 126.9 | 0.554 | 5.979 | 6.479 | 0.396 | 3.625 | 0.41 |
| first_dungeon | 0.0 (0/20) | 0.0 (0/60) | 139.3 | 93.0 | 0.203 (GUESS: t1's) | 1.367 | 2.7 | 0.183 | 6.483 | 0 (no big) |
| held_door | 0.15 (9/60) | 0.117 (7/60) | 161.1 | 111.6 | 1.031 | 3.509 | 4.283 | 0.302 | 5.415 | 0.528 |

Blueprints are 0.0 everywhere: the only blueprint is the chest's first clear. Every entry has `kept_frac` relics
0.1, remnants 0.173, husks, blueprints and essence 0, and `mass.died` killed 0.938, raised 4.043 per living unit,
garrison kept 0.724, raised survivors 0.153 per living unit. `mass.won` is killed 1.0 / 0.951 / 0.798 / 0.901 / 1.0 /
0.965, raised 8.015 / 6.455 / 4.058 / 5.055 / 7.403 / 5.822 per living unit, garrison kept 1.0 / 0.99 / 1.0 / 0.986 /
1.0 / 0.993, and raised survivors 0.921 / 0.639 / 0.721 / 0.63 / 0.66 / 0.611 per living unit (t1-t4, first_dungeon,
held_door).

**`"held"` (`"source": "GUESS"`).** Each multiplier applies to the tier's own entry:
- `death_rate_mult` 0.5 and `duration_mult` 0.5 (the ruling);
- `party_lost_mult` 0.5, the same reading: a short run with no warden room.

**The resolver.**
- **The entry:**
  - `held` with `opts.held`. The seed has no held key: the run records it, and the scene reads `view_fort` live, so
    E3-6b passes `view_fort(id).held` at issue;
  - otherwise `first_dungeon` with `seed.fort.first_dungeon`;
  - otherwise `held_door` when the door is taken;
  - otherwise the tier's.
- **The held door:**
  - it takes `opts.door` on a fort whose tier is in `raid.json held_door.tiers` (t2), and never the first dungeon or
    a held fort;
  - `RaidLogic.held_door_pick` must spend a big (at least `door_min_bigs`, 2, with the counter kept; one big always
    declines);
  - a declined door uses the t2 entry (the standard party). The arm's door-off rows (3/60 frozen deaths, 142
    relics) are only recorded, as `relics_per_run_without_door`.
- **Outcome:**
  - a death at the entry's rate (× 0.5 when held);
  - each charge this run may spend (`RaidLogic.can_revive`: min(charges, `phylactery_max_per_dungeon`)) revives her in
    place once, `revived_in_place` +1, and the rest of the run rolls again at the same rate;
  - otherwise `warden_beaten`, or `retreated` for a held fort's clear;
  - the frozen bot's own retreats (left with no army: t1 3 of 48, t2 and t3 1 of 60) and timeouts (none) fold into
    the clear, so the flip rate is 1 − `death_rate`.
- **Duration:** `duration_s` (× 0.5 when held), or `death_t_frac` of it on a death. E3-6b ticks the game live for it.
- **Loot:**
  - counts are `RaidLoot.scaled_count(rng, mean × (kept on a death), seed.fort.yield_mult)`, so a reclear's yield
    scales them as the scene's rolls are scaled;
  - essence counts at 1.0: it is the motes she carried, which the scene doesn't scale;
  - typed items come from the seed's table, `t<tier>.<archetype>`: remnants by `RaidLoot._remnant`, husk kinds from
    the tier's `chest_by_tier.husk_kinds`, blueprints by `first_blueprint`;
  - a win adds `RaidLoot.chest` at yield 0 with the seed's `first_clear` and `chest_husk` (the first-clear blueprint,
    or a relic when all are owned via `opts.blueprints`, and the first dungeon's husk);
  - a held clear is `RaidLoot.held_clear` (from E4 step 2 it includes the tier's chest husk roll at
    `husk_chance` × yield), and a held death banks nothing.
- **Masses:** on the seed's own fort, through `RaidLogic.LedgerV2`, the scene's own builder.
  - killed = `killed_frac` × living. A held clear kills exactly the seed's living, so the writeback raises
    `counter_garrison_cleared`.
  - One raised bucket at `score` 70: count = `raised_per_living_unit` × `RaidLogic.enemy_count`, and fresh mass =
    count × `RaidLogic.mass_per_enemy`, capped at killed + the seed's dead.
  - Survivors are the garrison taken in × `garrison_survive_frac`, plus `raised_survivors_per_living_unit` ×
    enemy_count units at mass_per_enemy. Score 70 is a soldier (`RaidLogic.score_class`), so it stays and
    `chaff_mass` is 0: chaff leaves with Relish, garrison stays.
- **Party:**
  - on a win each member is lost at `party_lost_per_member` (× 0.5 when held), except the door's big, which sits out
    the fight;
  - the door's big is lost by `RaidLogic.held_door_lost`: a death or a retreat, never a win. Its arm's 7 lost of 60
    are exactly its 7 deaths;
  - on a death the whole party is in `party_lost`, as the writeback loses it anyway.
- **Deterministic:** the rng is `seed.rng_seed ^ SALT`.

**GUESSes and limits:**
- The rows carry no raised, chaff or garrison mass (the AUTOPILOT line has none). So:
  - `raised_count` counts re-raises of recycled motes, which carry no fresh mass, and the cap on fresh mass binds
    in every entry: in effect all killed and piled mass is raised (an upper bound);
  - the survivors' split (the garrison first) and their mass per unit are GUESSes;
  - on a death the standing party can't be told apart, so all of it is taken off allies_end;
  - the first dungeon's 8 massless starters are taken off allies_end as if they all survived.
- t1 and the first dungeon's profiles have no big, so no party loss is measured there (0). Their entries have no died
  row, so they share the pooled `mass.died` and `kept_frac`. The first dungeon's `death_t_frac` is t1's.
- `death_t_frac` is above 1 at t2 (1.279) and the held door (1.031): their deaths came late, in long warden fights.
  It is kept, not clamped.
- `party_lost_per_member` is high: the t2 profile's one big is lost in 71% of its wins. That is measured, not tuned.
- The detour cache's relics are a fixed count in the scene, but here they are yield-scaled with the chest's.
- `hb70d10` ran at b895836 with the unstick watch's small bias (NOTES-RAID, D-e quality pass). In the sampled runs it
  moved only `unstick.aimed_in`.
- `_remnant` and `_by_tier` are RaidLoot's underscore-named (private by convention) table readers. They are called
  read-only, because no public reader returns a typed remnant or a tier's husk kinds.
- How the numbers were derived: a read-only script over the raw `.tsv` files, quoted in E3-6a's report. Re-derive
  them from the same rows when the dungeon re-measures.
