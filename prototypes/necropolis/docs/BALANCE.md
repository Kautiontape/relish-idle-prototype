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
| Vei-ready (odds ≥ 0.6 and 3 of 4 fronts met at her full pool, IDLE §8) | **2.5–3.5 h** |
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
  the highest tier ever flipped is held (MECHANICS §2's relics row). Measured at the odds lever (one seed, 8 days): it
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
- **(b) The dead's buildings without bone prices** (`autoplay_ablation_bone`). The spine's §4 row reads "bone-priced
  buildings removed costs 15%+". The table above has no such row: the lever is §7's "bone buys the dead's buildings". It is
  built as a config variant on fresh GameStates (`Autoplayer.cfgs("no_bone_prices")`): the bone price is 0 in `cost` and in
  every `level_costs` entry of §7's list (the raising pit, charnel house, bone mill, stables, graveyard, embalmer and
  forge), with their gold and relic prices unchanged. "Removed" is read as the rows above read it: the lever is taken out,
  not replaced by a gold price. The Market keeps its bone price (a living building bought with bone), and so do the Crypt's
  levels.
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
| `vei.guards` `rate_per_uncleared`, `cap`, `life_s`; `unit.hp`, `unit.dmg` | 1.0/s, 12, 6 s; 49.5, 8.8 | tuned in D-c so no ±5% move swings the win rate by a cliff; hp and dmg sit off Relish's 30-hp hit counts on purpose |
| `vei.weaves.dmg`, `period_beats` | 13.5, 3 | off the 30-hp hit counts as above |
| `vei.backups` `revive_hp_frac`, `iframes_s`, `shove_px`, `shove_recover_s`, `ready_trance` | 1.0, 3 s, 180 px, 3 s, false | a revive in the Vei fight is at full hp but does not ready the trance; V1 (1+1) 65%, V2 (0+0) 15% at score 70 |
| `K`, `S_vei` | 36 000 000, 8.0 | `K` E4 step 3: ×3000 for the live backlog (sessions about 5.6M at day 1, 61M at day 5, 140M at day 8; continuous 204M), so sessions reaches odds 0.6 at about day 4.7, continuous at about day 3.4 (28% sooner; at d6ad1b7 sessions crosses 0.6 at about day 5.4, between its looks, and continuous at 3.48), and night 1 takes the odds from 0.02 to 0.11, not 0.98 to 0.998. Was 12000 (the audit's ×4.8 canon), sized for the 18k knife edge below. The fixtures' and the demo seed's backlogs were scaled by the same 3000 so their odds stay put. `S_vei` unchanged. **Since E4 step 9, `K` sizes her strain** (`backlog / (backlog + K)`), which her tithe period, reship and need read; the odds a player reads are the win odds of the row below, so these day figures are the strain's (they are E4 step 3's, at d6ad1b7) |
| `odds.time_weight`, `odds.time_s`, `odds.backlog_cap` (realm.json) | 0.7, 345 600 (4 days), 0.8 | **E4 step 9, the odds lever** (the run's manager's 2026-11-17 13:44 ruling, option B; MECHANICS §3.5): the win odds are `time_weight · t / (t + time_s) + (1 − time_weight) · min(backlog_cap, strain)`. They drive what the player reads, the boss seed and Vei-ready, and nothing in the fight; K's strain still drives her pressure, so steps 5–8's hold calibration (α 0.85, the band, the need bins, away_risk) doesn't move. **One sizing pass**, from the ruling's start (T 4 days, w 0.7), sized on each profile's logged looks (time, backlog, fronts met at her full pool) from one run with no Vei trip: nothing in the sim reads the win odds, so one trajectory prices every (w, T, cap) up to its Vei-ready; time_weight 0 reproduces 6.0000 and 3.3034 at the look. Measured at the sized values with the profiles (one seed, 8 days, at this commit): **sessions Vei-ready day 6.0001** (518 406.5 s, as before: fronts first met at its day-5.17 look, odds 0.56 there and 0.6096 at day 6's first look), **continuous day 4.8291** (417 231 s), **19.5% sooner** (was 44.9%; inside IDLE §8's 10–30% and the ruling's 35%, so no re-size and no 4-remnant trim). The cap binds neither (their strains at ready are 0.632 and 0.735) but floors any profile's 0.6 at day 4.24 (29% sooner than day 6) whatever its backlog: x = (0.6 − 0.3 · cap) / 0.7, t ≥ T · x / (1 − x). On paper, cap 0.7 would put continuous at 5.05, T 3.5 days at 4.38, w 0.6 at 4.49. **What binds sessions** (the step 9 review's item 7; sessions' rows at 0b2a9ec): the odds, at session-start looks. Its rows meet all three fronts from the day-5.33 look (the full-pool look log at 69542f2's code had them from 5.17), with the odds at 0.5618 (5.17) and 0.5724 (5.33). The next look is day 6.0's, after day 5's night, at 0.6096. So any (w, T, cap) whose 0.6 falls in that night reads day 6.0, which is why the rows above sit at 6.0000. A change to the fronts moves it only if it puts them past day 6.0. A change to the odds moves it only if it brings 0.6 forward to day 5.33 or earlier (T 3 days does: 5.1696), or pushes it past day 6.0. The cap floors any profile at day 4.24 (the review read the fronts as binding; the rows don't). Sessions' nights: odds 0.06 → 0.14 12 h after night 1's close (0.16 on its load), 0.57 → 0.60 on night 6; one night never takes them near 1. time_weight 0 with backlog_cap 1 gives the strain bit for bit (the revert proof). **The ▲/▼** is the backlog's sign, not the odds': the map labels it as the strain ("strain ▲", never right after the percent; the step 9 review's item 4, ruled 2026-11-17 16:40). **Phase I, recorded, not fixed:** the map valve's "odds in 10 min" stops moving with a drag once the projected strain passes `backlog_cap` 0.8, since min(cap, strain) is flat there and only the window's time moves it |
| `vei.fronts.giants.need_base`, `carvers.need_base`; `carvers.need_per_pool` | 2, 2; 0.012 | E4 step 2's sizing (try 1; were 14 and 18): with giants' `need_per_pool` 0.02, giants needs 14 at Vei's full pool of 600. Giants' 14 sits above the best t1 skeleton's wits (9), so one t1 skeleton never fills it (the manager's ruling 4 at step 2); it takes two or three. **Carvers' `need_per_pool` 0.02 → 0.012 (9.2 at a full pool) is the one re-size of the R2 ruling**, when the bot's Vei-ready moved to the full pool (IDLE §8). Less 3 × `q` (about 6.7) carvers' want is about 2.5 beef, so one t1 big with beef 3 meets it: carvers needs a keeper, not a composition. **At d6ad1b7, Vei-ready at her full pool (3 of 4 and odds ≥ 0.6), with the in-wave readout (the pool she has then, at the look) beside it:** sessions **day 6.0001** (518 406.5 s; in-wave 518 400 s, the same look), continuous day 3.4837 (in-wave 3.4836), 42% sooner and outside the 10–30% band, ablation_keep never (giants 0). Both are **odds-bound**: sessions meets all three fronts at a full pool from day 5.0 (giants 19/14, swarm 24.1/24, carvers 13.7/9.2), but its odds are 0.5967 at day 5's last look (5.347) and 0.6356 at day 6's first, so it lands 6.5 s past day 6. At ready, sessions brings giants 14/14 (a wraith and a skeleton, wits 7 each), swarm 31.4/24, carvers 13.7/9.2 (one beef-7 zombie), raw 15.7/58. **Before R2** (carvers 0.02, the fronts at the pool she had then, at 5b86232): sessions day 5.34, continuous day 4.38 (18% sooner), both inside a tithe wave's dip; at a full pool neither had 3 of 4 in 8 days |
| The fight grade at Vei-ready (E4 step 3) | 20 seeds | The demo seed with the boss bot at score 70 (`--boss-autoplay=70`, `--boss-seed` 1–20), at d6ad1b7. **At sessions' Vei-ready** (`--boss-cfg` needs giving the demo sessions' have/need on arrival: giants 1.00, swarm 1.31, carvers 1.49, raw 0.27) **with its backups** (1 phylactery charge and 4 clones; vats best case): **19/20 won (95%)**. With the demo's 1 + 1 backups at the same ratios: 12/20 (60%). The demo as shipped (its fronts at 2.40, 1.87 and 4.09 of need, 1 + 1): 10/20 (50%). Before E4 (the old config, 1 + 1): 13/20 (65%). So the ratios at Vei-ready make the fight no harder than the demo's; the clones she holds decide it. Every fight clears giants, swarm and carvers in phase 1 (20.0 s at sessions' ratios: giants at exactly its need takes `phase1.ref_s`). **Re-graded at E4 step 9** (the run's manager's 01:50 ruling (d) and 12:45 item 5: score 50, 1 + 2 backups), at 69542f2. Sessions' have/need at its day-6 Vei-ready, at her full pool: giants 1.07, swarm 1.29, carvers 1.49, raw 0.27 (`--boss-cfg` with need_per_pool 0 and need_base the demo's have ÷ that ratio). **The first attempt wins 3/20 (15%)**: every fight clears the three fronts and reaches the break (phase 1 in 18.7 s on average), then 17 end unmade, with 3.70 Relish deaths on average. That is far under the 85% line, so Vei's phase-2 pressure is not raised and vei.json is unchanged. The demo as shipped, unchanged, still grades 10/20 at score 70 with 1 + 1 |
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
  1 250, 2 050, 3 400, 8 400 (caps 300 to 8 600). The rule (§5, Store caps): each level's cap covers 1.2 ×
  the mill's and the Market's next level, rounded up to 50, and the top level's every bone cost (the
  Forge's L8, 8 575); `tests/test_build_ladder.gd` checks that every price fits a cap reachable by its
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
