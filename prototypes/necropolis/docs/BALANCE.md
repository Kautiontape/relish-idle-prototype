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
| `flip.hold_s`, `flip.tier_mult`, `flip.haul_mult` | 300, 0.25, 1.5 | |
| `tithe.period_s`, `tithe.backlog_scale` | 420, 0.5 | waves come faster as the odds rise |
| `tithe.warning_s`, `tithe.surge_s`, `tithe.surge_mult` | 150, 40, 3.0 | |
| `tithe.siege_block`, `tithe.relish_mult` | 0.6, 0.5 | a siege cancels 0.6 of a surge; a surge into the fort Relish stands at is × 0.5 (halved) |
| `tithe.overfill` | 2.0 | a surge fills its fort to at most `cap · (1 + overfill)` (3 × cap); the rest stays in her pool. A garrison at full cap still loses its hold to a full wave (MECHANICS §3.4) |
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
| graveyard, embalmer `effects.lifetime_bonus` | +0.15, +0.5 per level | lifetime × (1 + Σ) |
| cap effects (live from T2.4) | chapel `vat_slots` 2 (view_backups.vats), guildhall `stance_slots` 1, reliquary `relic_cap` 6 and `essence_cap` 30 | per level, on top of `relics.cap`, `essence.cap` and `stance.base_slots` |
| E3 effects (data only for now) | ossuary `craft_slots` 1, watchtower `hint_precision` 1 | per level |
| `relics.cap`, `essence.cap` | 12, 60 (the Reliquary raises both to 18 and 90) | |
| `big_undead.cap`, `big_undead.per_crypt_level` ⟵ crypt `effects.big_undead_cap` | 4, +1 | the cap is 4 at Crypt level 1, 6 at level 3 (the Crypt's `effects` are empty; the number is here) |
| crypt `unique` | true | `buildings.json`: the only unique building, so a second Crypt is refused (`unique`, STATE-API §4.3) |
| `town.tiers.<tier>.buildings`, `.requires` | 0 / 6 / 12 / 20 finished buildings (the Crypt counts), plus `market` + `house`, `walls` + `chapel_of_vats`, `reliquary` | the next tier rises when both hold |
| `town.tiers.<tier>.lot_ids`, `.lots` | below the table | explicit lot ids per tier; `.lots` is their count (kept for readers that want a number) |
| `stance.base_slots`, `stance.hold_s` | 2, 10 | `stance.hold_s` is E3 and not in `economy.json` yet |
| `vats.grow_per_s` | 1/300 per staffed vat | |
| `backups.clone_respawn_s`, `unmade_respawn_s` | 60, 600 | |
| `phylactery.revive_hp`, `max_per_dungeon` | 0.5, 1 | |
| `essence.per_living`, `per_undead`, `lifetime_s` | 1, 1, 12 | `lifetime_s` is the existing raid.json name |
| `loot.reclear_decay` | 0.5 | |
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
- **Gold:** the living cap and upkeep tiers must hold the stock rule.
- **Rate normalisation** (`view.rate_log_max`, 25/s on the map today) saturates at the new flow
  sizes, so it moves into config.
- **The Vei fight's feel** won't converge until `vei.json` is tuned against real circles.
