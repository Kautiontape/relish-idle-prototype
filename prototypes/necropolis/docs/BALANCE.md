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
| workers | 12 (the steady state at the default valve is about 50, so the stream visibly grows) |
| living | 10 (`living_cap` 16 from the crypt district's huts) |
| valve | work 0.40 · war 0.45 · flood 0.15 |
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
| Vei-ready (odds ≥ 0.6 and 3 of 4 fronts met) | **2.5–3.5 h** |
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
  adjusts the values from real runs.
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
| `opening.valve` | 0.40 / 0.45 / 0.15 | `economy.json` (work / war / flood); `directShare` 0.22 is removed |
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
| `tithe.siege_block`, `tithe.relish_mult` | 0.6, 0.5 | a siege cancels 0.6 of a surge; a surge into the fort Relish stands at is × 0.5 (halved) |
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
| `body_store.cap` | 200, + charnel upgrades (+50 at level 2, +100 at level 3), +100 per graveyard level | the start Charnel House (level 1) adds nothing, so the start cap is 200 |
| `gold.cap`, market `effects.gold_cap` | 6500, + 3250 per Market level (+50% of the base) | IDLE §6, E2b-2 T3.2 (sizing below). The start Market (level 1) makes a new game's cap 9750; level 3 gives 2.5 × the base, 16 250 |
| `town.projection_refresh_s` | 5 s | the build benefit's cache (STATE-API §5.10, E2b-2 T3.2): a `projected` or `upgrade_projected` row goes stale this long after it was computed while the town's structure holds (a structure change makes every row stale at once); the frame refresh also runs only while `view_catalog()` was read within this much sim |
| `town.projection_rows_per_frame` | 1 | the build-benefit units (rows, or the baseline they diff against) refreshed on a frame that ran no substep, late in the interval, while the catalog is read (STATE-API §5.10): 0.45 to 0.55 ms each at `pre_vei`. Every row settles about 1.5 s after a change at 60 fps (41 rows over the 15 late frames of each substep) |
| `town.projection_phase` | 0.5 | the frame refresh runs only once the substep accumulator holds this fraction of `substep_s()`: scenes refetch when `rev` moves, so their work bunches up just after a substep, and background work belongs in the later part of the interval |
| `town.projection_starve_frames` | 30 | at fast-forward, when every frame substeps: after this many substep frames in a row, one row (and its baseline) goes through on the next, whatever the phase; about 1.1 ms at `pre_vei` |
| `town.projection_tol` | `rel` 1%, `abs` 0.005/s | a refreshed row keeps its old value unless some rate moved by more than `rel` × abs(old) + `abs` (the floor is half the 0.01 the build card shows), so the town's row signatures don't move on float drift every window |
| `town.projection_rows_per_call` | 0 | a test override, not a tunable: above 0 a view call refreshes up to that many of its own rows, exactly (the exactness, purity, persist and contract tests set 1000) |
| `queue.max_len` | 8 | the build queue's length (IDLE §5, E2b-2 T3.2), the town's stand-in's 8 |
| `idle.catchup_gate_tol` | 0.01 | the catch-up gate (IDLE §4, E2b-2 T3.3a, the run's manager's rule): a 10 s core step against 0.5 s over 12 h with no input. Vei's and Covington's stocks within 1% at every 600 s sample, each overflow tally within 1% at the 12 h endpoint (a) and within max(1% of it, its floor) at every sample (b), the same outcomes. The core step's share of IDLE's 2% `idle.catchup_tol`. Read only by `tests/slow/convergence.gd` (its assertion) and `test_step_accuracy` (the judge's test) |
| `idle.catchup_gate_tally_floor` | gold 6, bone 1 | (b)'s floor: a fixed amount per tally, what one 10 s step's lag can carry. **Bone 1:** at 10 s pre_vei's convoy runs 10–15 mass of corpses behind 0.5 s's (the start-of-step pickup cap, MECHANICS §4.2), about 0.7 bone of the mill's overflow; the worst (b) residual at 10 s over 12 h on the three starts is 0.74 bone (pre_vei at 600 s, where 1% of the tally is 0.65). A fifth of the judge test's 5-bone mid-run fault. **Gold 6:** no gold tally moves at any start; the largest gold income among them is 0.6 gold/s of trade (pre_vei: Market 2, four stalls at `stall.rate` 0.15; midgame_2flips and fresh 0.3), and 0.6 × 10 s = 6 gold, a whole number |
| `idle.gap_s` | 30 s | IDLE §4 When: a frame on the frame path whose real time (its sim `dt` / `time_scale`) is above this goes through catch-up instead of having its remainder past `sim.max_substeps_per_frame` dropped; under it, frames stay live play (MECHANICS §1.3). Real time, so debug fast-forward stays live |
| `idle.catchup_max_s` | 604 800 s (7 d) | the most a load catches up; more is dropped and flagged (`cmd_load`'s `capped`): a sanity cap, not a design lever (IDLE §4) |
| `idle.catchup_dt_max_s` | 10 s | catch-up's longest core step for its first `idle.catchup_dt_long_after_s`: the largest step the gate (`idle.catchup_gate_tol`, E2b-2 T3.3a) passes at every start over 12 h; 15 s fails it at pre_vei (bone over (b) 1.09 of 1.00) |
| `idle.catchup_dt_long_s` | 15 s | catch-up's longest core step past `idle.catchup_dt_long_after_s` (IDLE §4 Budget, the budget's lever 2, E2b-2 T3.3b; the run's manager's cap): a week takes 41 760 steps instead of 60 480. 15 s is the longest step whose outcomes match 0.5 s over 12 h at every start (T3.3a: 30 s flips midgame_2flips' Ashgate at 5 355 s and puts fresh at 2.38%); over 7 days its flips, retakes, forts held at the end and Relish's place match a 0.5 s run at every start (`tests/slow/catchup_week.gd`). 7 days is a timing test for the stocks only (IDLE §4) |
| `idle.catchup_dt_long_after_s` | 43 200 s (12 h) | the longer step starts this far into a catch-up: the first 12 h, the span the gate and the accuracy test judge, keep `idle.catchup_dt_max_s` |
| `idle.catchup_max_steps` | 4 320 | catch-up steps at `clamp(elapsed / this, sim.substep_s, idle.catchup_dt_max_s)` (IDLE §4 Method): 12 h at 10 s, and anything up to 36 min (2 160 s) at the live 0.5 s |
| `idle.catchup_tol` | 0.02 | the accuracy test's tolerance (IDLE §4): a catch-up against live play with no input, on Vei's and Covington's stocks and the key rates (`tests/test_catchup.gd` at 2 h, `tests/slow/catchup_accuracy.gd` at 12 h), and closed against open (I1). The core step's own share is `idle.catchup_gate_tol` |
| `idle.field_steps` | 75 | field steps per catch-up (api-request #14 asked about 150; E2b-2 T3.3b2, the run's manager's ruling: 75, on the condition that ground's owner test passes at 75, which it does: `tests/slow/field_catchup_bench.gd` run as a copy with `STEP_S` 576 s, catch-up against exact live ticks in 99.67% of village samples over 12 h, green villages equal at the end; 99.83% at its own 144). Each costs about one live field tick on the shipped grid, so 0.5–0.6 s in all instead of 0.8–1.4 s. Against 150 it changes no outcome or Vei and Covington stock over 12 h or 7 days from the three starts, and village owners by at most 1 of 12 (IDLE §4). Read by `Catchup.begin` and `test_catchup`'s load test |
| `idle.field_step_min_s` | 2 s | no field step is shorter, so a short catch-up takes fewer (120 s: 60). A field step of up to `field.catchup_exact_ticks` (8) ticks, 1.6 s, runs that many live ticks plus a solve, so without it a 30 s gap would make 60 calls (one per 0.5 s core step) costing about 180 live ticks, more than the live field's 150; with it, 15 calls of about one tick each (ground's `field_catchup_bench.gd`, its MIN_STEP_S) |
| `idle.catchup_steps_per_chunk` | 90 | core steps per frame while a chunked catch-up runs (a load's from the shell, an open-game gap's): about 50 ms at pre_vei over 12 h, where a field step falls every 29 core steps (330 µs a core step and 6.3 ms a field step: 0.55 ms a core step with the field's share). `tests/slow/catchup_bench.gd` measures a median 46 ms at pre_vei, 43 ms at fresh and 53 ms at midgame_2flips (79 ms at pre_vei for 150). A 12 h catch-up is 48 chunks, a week 464 (about 33 ms each, a field step in every third) |
| `idle.report_min_s` | 600 s | a gap at least this long gets the away report (IDLE §7, T3.3c) and its catch-up's events are collected for it; a load always is. A shorter open-game gap queues its events as live (STATE-API §6) |
| `idle.report` | the away report's text (IDLE §7, E2b-2 T3.3c; STATE-API §5.19) | every line of `view_away` is a template here, in the style of `map_view.json`'s `demo_away`: `streams` (the gains' order: backlog, mint, workers, bodies, gold, bone, living) and their `stream_labels`, `stream_fmt` and `backlog_fmt` (with `arrow_up` ▲, `arrow_down` ▼, `arrow_flat` ■), `builds_one_fmt` / `builds_fmt` (names joined by `list_sep` " · ", spaced, so a number ending one name never glues to the separator; `level_fmt` past level 1), `started_fmt` / `started_now_fmt` with `when_hm_fmt` / `when_m_fmt` (the time since you left) and one `waited_on` reason per queue reason, `refilled_fmt`, `raid_fmt`, `husk_one_fmt` / `husks_fmt`, `queue_empty`, `retaken_fmt` / `retaken_home_fmt`, `village_lost_fmt`, `overflow_fmt` with `store_labels`; and the tokens the map parses: `plus` "+", `minus` "−", `rate_unit` "/s", `thousands` ",". Three numbers: **`rate_sig_digits` 2** and **`rate_max_decimals` 3** (a rate shows two significant digits, at most three decimals: +2.1/s, +0.43/s, +0.012/s, +140/s; under 0.0005/s it reads 0/s), and **`overflow_min` 1** (a store's overflow line shows from 1 wasted, so the report never says "0 wasted"; midgame_2flips' 12 h bone overflow is 0.56) |
| `bone.cap`, bone mill `effects.bone_cap` | 200, + 100 per Bone Mill level (+50% of the base) | 300, 400, 500 at Bone Mill levels 1–3; a new game (no mill) has 200 |
| graveyard, embalmer `effects.lifetime_bonus` | +0.15, +0.5 per level | lifetime × (1 + Σ) |
| cap effects (live from T2.4) | chapel `vat_slots` 2 (view_backups.vats), guildhall `stance_slots` 1, reliquary `relic_cap` 6 and `essence_cap` 30 | per level, on top of `relics.cap`, `essence.cap` and `stance.base_slots` |
| E3 effects (data only for now) | ossuary `craft_slots` 1, watchtower `hint_precision` 1 | per level |
| `relics.cap`, `essence.cap` | 12, 60 (the Reliquary raises both to 18 and 90) | |
| `big_undead.cap`, `big_undead.per_crypt_level` ⟵ crypt `effects.big_undead_cap` | 4, +1 | the cap is 4 at Crypt level 1, 6 at level 3 (the Crypt's `effects` are empty; the number is here) |
| crypt `unique` | true | `buildings.json`: the only unique building, so a second Crypt is refused (`unique`, STATE-API §4.3) |
| `town.tiers.<tier>.buildings`, `.requires` | 0 / 6 / 12 / 20 finished buildings (the Crypt counts), plus `market` + `house`, `walls` + `chapel_of_vats`, `reliquary` | the next tier rises when both hold |
| `town.tiers.<tier>.lot_ids`, `.lots` | below the table | explicit lot ids per tier; `.lots` is their count (kept for readers that want a number) |
| `stance.base_slots`, `stance.hold_s` | 2, 10 | `stance.hold_s` is E3 and not in `economy.json` yet. IDLE §4 needs it at least catch-up's longest step in config, the larger of `idle.catchup_dt_max_s` and `idle.catchup_dt_long_s`: 15 s today (the long step, since E2b-2 T3.3b). `GameState.catchup_config_problem` reports an error at load below that, naming both keys, so E3 sets it to 15 or more, or lowers those steps |
| `vats.grow_per_s` | 1/300 per staffed vat | |
| `backups.clone_respawn_s`, `unmade_respawn_s` | 60, 600 | |
| `phylactery.revive_hp`, `max_per_dungeon` | 0.5, 1 | |
| `essence.per_living`, `per_undead`, `lifetime_s` | 1, 1, 12 | `lifetime_s` is the existing raid.json name |
| `loot.reclear_decay`, `loot.recover_s` | 0.5, 28800 s | each clear that pays loot (a flip, a counter-garrison clear) multiplies a fort's loot yield by 0.5; the yield climbs back linearly to 1 over 8 h from its last clear (a retake resets it to 1). MECHANICS §5.3 |
| `vei.fronts_required`, `break_beats`, `loss_backlog_keep` | 3, 8, 0.35 | |
| `K`, `S_vei` | 12000, 8.0 | flagged by the audit (×4.8 and ×1.6 canon); calibrate in E4 |

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

**Store caps** (E2b-2 T3.2; IDLE §6). Two constraints, and only these. *8 h fill:* the base cap is at
least 8 h of a new game's settled net income, rounded up. *Nothing stuck:* the cap with its cap
building at level 3 (2.5 × the base, at +50% per level) covers the largest single cost of that store in
`buildings.json`, so every build can be queued once the cap building is maxed. The rates are measured:
`cmd_new_game(1)`, no actions, 1 h at 0.5 s, the mean net rate over the last 10 min (the fixtures the
same way, from their load).
- **Gold:** a new game settles at +0.210 gold/s (trade 0.30, upkeep 0.09): 8 h is 6 048, so the base is
  **6 500**. The largest gold cost is the Ossuary Tower's level 3 (1 350), far under even the base, so no
  gold cost exceeds a gold cap and `cost_exceeds_cap` is never about gold with these numbers.
- **Bone:** a new game has no Bone Mill, so its net bone is 0 and the 8 h rule asks nothing. The largest
  bone cost is the Ossuary Tower's level 3 (450): 450 / 2.5 = 180, so the base is **200** (500 at Bone
  Mill level 3). The costs above the base bone cap, so `cost_exceeds_cap` is reachable: Chapel of Vats
  level 2 (240) and 3 (360), Embalmer level 3 (240), Reliquary (250), Ossuary Tower level 2 (300) and 3
  (450). A level-1 mill (300) leaves the Chapel's level 3 and the Ossuary's level 3; level 2 (400) the
  Ossuary's level 3; level 3 none.
- **Nothing stuck, checked** (the run's manager, for E4): every building and level in `buildings.json`,
  priced with `BuildRules.construction_cost`, against the highest cap the player can reach for each
  resource with one cap building at its top level: gold 6 500 + 3 × 3 250 = 16 250, bone 200 + 3 × 100 =
  500, relics 12 + 6 (the Reliquary, level 1) = 18. The top prices are the Ossuary Tower's level 3 in
  all three (1 350 gold, 450 bone, 9 relics), so **no price is above its highest reachable cap: the list
  is empty**, and `cmd_queue_build`'s `cap_level` is never −1 with the shipped numbers. (A second Market
  or Bone Mill raises a cap further; the check counts one.)
- **Relics** keep `relics.cap` 12 (+6 with the Reliquary): the largest relic cost is 9 (the Ossuary's
  level 3), so no relic cost exceeds it.

| start | gold: cap, stock, net/s, fill | bone: cap, stock, net/s, fill |
|---|---|---|
| a new game (Market 1, no mill) | 9 750, 80, +0.210, 12.8 h (the base alone: 8.5 h) | 200, 30, 0, never (no mill) |
| `midgame_2flips` (Market 1, Bone Mill 1) | 9 750, 656, +0.160, 15.8 h | 300, 328.5 (over the cap: it keeps the excess and earns nothing until under), 0 (the pits take every body), never |
| `pre_vei` (Market 2, Bone Mill 1) | 13 000, 3 616, −0.470 (falling), never | 300, 459.6 (over the cap), +0.107 uncapped (the mill's share of a body surplus), earns nothing until spent under 300 |

The 8 h rule covers only a new game: `pre_vei`'s bone, at its +0.107/s, fills its 300 cap in about 47 min
from empty.

**Building costs** (gold / bone / relics; upkeep in gold/s). Starting values; the economy unit puts
them in `buildings.json`.

| building | cost | upkeep |
|---|---|---|
| House, Well, Bakery | 30–50 / 10 / 0 | 0.01 |
| Bone Mill, Raising Pit | 60–90 / 20–40 / 0 | 0.03 |
| Market expansion, Charnel upgrade | 80 / 30 / 0 | 0.03 |
| Inn, Forge, Graveyard, Stables | 120–180 / 50 / 0–1 | 0.05 |
| Embalmer, Watchtower | 200 / 80 / 1 | 0.08 |
| Chapel of Vats, Guildhall, Walls | 300–400 / 120 / 2 | 0.12 |
| Ossuary Tower, Plaza/Statue | 350–450 / 150 / 2–3 | 0.15 |
| Reliquary | 600 / 250 / 4 | 0.2 |

## 6. Known balance risks
- **The knife edge** (systems review S5). Odds of 0.6 need a backlog of about 18,000 raw. Vei's undead
  capacity is about 42/s at q 1.2 and about 20/s at q 2.5, so the active run needs about 5–8 pits and
  `q` > 2. Calibrate pits, `K` and `S_vei` together in E4.
- **Redirect value at low `q`** is small under `cheap`. If the +30% ablation fails, raise
  `raise_rate` or let the redirect add the haul bonus.
- **FLOOD as a no-brainer** once `q` is high. The tithe waves and WORK's diminishing returns must keep
  the split moving; the static-schedule ablation checks it.
- **Gold:** the living cap and upkeep tiers must hold the stock rule. The store caps (above) bound gold
  and bone from E2b-2; pre_vei's gold falls (−0.47/s) and its bone sits over its cap.
- **Rate normalisation** (`view.rate_log_max`, 25/s on the map today) saturates at the new flow
  sizes, so it moves into config.
- **The Vei fight's feel** won't converge until `vei.json` is tuned against real circles.

## 7. Town growth over days (proposed direction, 2026-11-14, pending a trial run)
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

**Adopted structure (for economy to put in the configs after E2b; E4 tunes the numbers):**
- the dead's buildings cost mostly bone; the bone mill stays gold-priced and the Market is bought with
  bone (each producer is bought with the other resource);
- a level ladder to L8 for the job buildings and the house, relic-free to L5, with relic costs that
  never fall with level;
- the suggestion reserves the next tier's gate lots (town code, 8f73c36) and prefers upgrades;
- pits get first call on bodies.
- **E4's job:** split costs so that **neither resource piles up**. Both should be ≥ 60% spent, and the
  binder should alternate (today gold piles once the Market is bone-bought). Give gold real sinks: tier
  gates, living buildings, upkeep that scales with level. Measure where the no-raid plateau lands with
  E3's `pure_idle` and `town_only` profiles (target: 2–3 days, then "needs relics"). L6+ relic costs
  are untested without raids.
- Rent is dropped.
