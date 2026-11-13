# Necropolis: balance

Targets, how they're measured, and starting numbers. Every number here is a *starting* value for
`configs/*.json`; the configs are the truth. When tuning moves a number, update the table here in
the same commit.

## 1. Pacing targets (active play, sim ×1)
| moment | target |
|---|---|
| first stream response to the valve | under 5 s |
| first dungeon available (Relish reaches the nearest fort) | under 3 min |
| one dungeon run, entry to exit | 3–6 min real time |
| a new building affordable | every 2–4 min early, every 5–8 min late |
| first warden beaten (fort flipped) | 15–30 min |
| first big undead raised | 20–40 min |
| town reaches Village / Town / City | about 20 min / 1 h / 2 h |
| Vei odds ≥ 60% with a winnable front composition | **2.5–3.5 h** |
| idle (no input at all) for 4 h | odds < 0.10, but the town visibly keeps running and growing a little |

## 2. Lever-ablation targets ("the economies feed each other")
These come from the autoplayer (§4), comparing hours to "Vei-ready" (odds ≥ 0.6 and fronts
clearable) with one lever removed.

| removed lever | must cost at least |
|---|---|
| dungeons (Relish never descends) | +40%, or never ready (relics gate the higher buildings) |
| town building (no new buildings) | +40% |
| Relish's tide and redirect (she stays home, except to descend) | +20% |
| policies (none) | +10%. Defaults must be decent, so the gap is small but real |
| the valve (left at default) | +15% |

If any lever costs less than its target, it is decorative. Fix the design before tuning anything
else.

## 3. Risk targets
- A dungeon run at a fort at or below the party's tier should kill Relish less than 10% of the time
  with reasonable circles. A run two tiers above should be risky (more than 40%).
- An unmade death (no clone ready) should cost about 10 minutes of progress: the respawn, the morale
  dip and the lost loot.
- At the final test with odds of about 0.6 and 3 of 4 fronts met, the win rate with 2 backups should
  be about 60–70%. With 0 backups, well under 50%.

## 4. How it's measured
- **`tests/test_pacing.gd`**, already in the repo, is rewritten to drive the real `GameState`. Relish
  is set at home by default, which fixes the audit's C4: the old test never turned `P_relish` on.
- **`tests/autoplay.gd`** (new): a headless player with three profiles.
  - **idle:** no input.
  - **active:** sets the valve, moves Relish to the richest corpse fort, descends on a cadence,
    builds by a priority list, and keeps the default policies.
  - **ablation:** active, minus one lever (§2).

  Dungeons use a **stand-in model**: expected loot, flip chance, duration and death chance by fort
  tier, party strength and an assumed circle score. The dungeon unit calibrates it from real runs and
  writes the averages into `configs/balance_standins.json`.
- **The no-unbounded-stock check.** Over a 4 h active run, no stock (gold, bone, bodies, essence,
  relics) may finish above `2 ×` its value at 2 h, unless it has a cap. Gold in particular must stay
  a stream: upkeep plus build costs consume most of income.
- Output: one line per profile in the test log, e.g. `[pacing] active: ready 2.9 h · odds 0.62 ·
  fronts 3/4`, and the ablation table.

## 5. Starting numbers
Raw Necropolis units (×1/100 of Realm mass). The keys follow MECHANICS.md.

| key | start | note |
|---|---|---|
| `valve.default` | work 0.40, war 0.45, flood 0.15 | `flood` replaces `directShare` 0.22 |
| `valve.slew_per_s` | 0.10 | a full swing takes about 10 s |
| `relish.P_relish` | 0 | D2 |
| `relish.travel_speed` | 220 px/s | kept |
| `relish.tide_bias` | 3.0 | her fort's dispatch weight multiplier |
| `relish.raise_rate` | 1.5 /s | was 30, which emptied any pile in seconds |
| `relish.home_rot_mult` | 0.7 | workers last longer while she's home |
| `P_base`, `P_per_pit` | 2.0, 6.0 | kept (the old slabs). Pits are buildings now |
| `pit feed bonus` | ×1.6 while bodies > 0 | kept |
| `worker.lifetime_s` | 480 | 8 min. Steady state = inflow × 480 |
| `worker.body_return` | 0.6 | rot → bodies |
| `worker.idle_rot_mult` | 0.5 | |
| `flip.hold_s` | 360 | × (1 + 0.25·tier) |
| `flip.haul_mult` | 1.5 | |
| `market.shop_rate` | 0.02 /living/s | × price 1 gold, capped by staffed stalls |
| `town.migrant_rate` | 0.012 /held village/s | kept |
| `inn.attract` | 0.01 /s per level | |
| `morale.dread_ratio` | 3.0 | undead per living before dread |
| `morale.leave_below` | 0.35 | |
| `morale.death_shock` | 0.30 | decays over `morale.shock_s` 600 |
| building upkeep | 0.01–0.2 gold/s | scales with tier |
| `policy.base_slots` | 3 | +1 per Guildhall level |
| `vats.grow_per_s` | 1/300 | about 5 min per clone per staffed vat |
| `backups.clone_respawn_s` | 60 | |
| `backups.unmade_respawn_s` | 600 | |
| `phylactery.revive_hp` | 0.5 | at most 1 per dungeon |
| `essence.per_living` | 1 | |
| `essence.per_undead_mult` | 0.5 | × the fallen undead's quality multiplier |
| `essence.life_s` | 12 | kept from R&R |
| `vei.fronts_required` | 3 of 4 | from crypt |
| `vei.loss_backlog_mult` | 0.35 | kept |
| `K` | 12000 | kept for now; flagged by the audit as ×4.8 canon, so revisit with the autoplayer |
| `S_vei` | 8.0 | kept; flagged ×1.6 |

## 6. Known balance risks
- **Slabs dwarf the other levers** (audit). Pits now feed on bodies, which ties minting to hauling
  and corpses. If the autoplayer still shows pits dominating, cap pits by tier.
- **FLOOD could be a no-brainer.** It is cheap for Vei to digest at low `q`, so it pays only once
  quality is up. Check that the ablation of WAR loses as well.
- **Gold bloat** (27k in the old late-game screenshot). Upkeep must scale.
- **`q` granularity:** forge steps of +0.25 are wider than the knife edge (Δq ≈ 0.19; audit).
  Consider steps of +0.1 with more levels.
- **The boss isn't converged** (NOTES-RAID). Vei's fronts replace the HP scaling; tune it with
  `vei.json`.
