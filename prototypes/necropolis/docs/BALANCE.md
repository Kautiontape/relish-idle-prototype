# Necropolis: balance (v2)

Targets, how they're measured, and starting numbers. Every number here is a *starting* value; the
configs are the truth. When tuning moves a number, update this file in the same commit.

## 0. Start state (`economy.json` `opening.*`)
| item | value |
|---|---|
| buildings | Crypt, 1 Raising Pit, Charnel House, small Market (2 stalls) |
| lots | 24 (Hamlet uses the first 8) |
| gold / bone / bodies | 80 / 30 / 40 |
| workers | 12 (the steady state at the default valve is about 50, so the stream visibly grows) |
| living | 10 (`living_cap` 16 from the crypt district's huts) |
| valve | work 0.40 · war 0.45 · flood 0.15 |
| Relish | home, phylactery 0, no vats |
| first dungeon | Old Sluice (tier 1, Bellringer), flagged "first"; starter party `opening.starter_party` = 8 units; the chest holds a husk and the first blueprint |

## 1. Pacing targets (active play at 1×; time controls 1×/2×/4× exist)
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
| idle (no input) for 4 h | odds < 0.10; the town visibly runs and grows a little |

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
are marked ⟵.

| key | start | note |
|---|---|---|
| `valve.default` | 0.40 / 0.45 / 0.15 | `directShare` 0.22 is removed |
| `valve.slew_per_s` | 0.10 (L1) | about 10 s for a full swing |
| `P_relish` | 0 | top-level key, kept |
| `P_base`, `P_per_pit` ⟵ `P_per_slab` | 2.0, 6.0 | migrate `game.gd`'s default (2.0) to the config's 6.0 |
| `pit.burn_per_s`, `pit.bonus` | 0.6 mass/s per pit, +0.6 at full feed | burn calibrated so rot alone covers about 60%; hauling covers the rest |
| `worker.mass` | 40 | start inflow 12.8 × 0.4 / 40 = 0.128 workers/s → steady state about 61 |
| `worker.lifetime_s` | 480 | |
| `worker.body_return` | 0.25 | was 0.6, which made hauling decorative (systems review M6) |
| `worker.idle_rot_mult`, `worker.idle_cap` | 0.5, 10 | idle above the cap musters to WAR |
| `relish.travel_speed` | 220 px/s | kept |
| `relish.tide_bias` | 3.0 | |
| `relish.raise_rate` | 4.0 mass/s | was 30 (emptied piles), then 1.5 (a wash at low `q`); calibrate against the +30% ablation |
| `relish.home_rot_mult` | 0.7 | |
| `flip.hold_s`, `flip.tier_mult`, `flip.haul_mult` | 300, 0.25, 1.5 | |
| `tithe.period_s`, `tithe.backlog_scale` | 420, 0.5 | waves come faster as the odds rise |
| `tithe.warning_s`, `tithe.surge_s`, `tithe.surge_mult` | 150, 40, 3.0 | |
| `tithe.siege_block` | 0.6 | Relish halves the surge |
| `readout.ema_s` | 120 | |
| `q0`, `q_forge`, `q_raise_max`, `q.raise_ema_s`, `q_max` | 1.2, 0.1 per level, 0.6, 600, 4.0 | forge steps 0.1 (was 0.25, wider than the knife edge) |
| `stall.rate`, `market.shop_rate`, `market.price` | 0.15 /stall/s, 0.03 /living/s, 1 | start: min(2·0.15, 10·0.03) = 0.30 gold/s |
| `town.migrant_rate`, `town.leave_rate` | 0.012 /held village/s, 0.004 /s | |
| `living_cap` | 16 + 8 per house, +20 inn, +30 walls | |
| `inn.attract` | 0.02 /s per level | |
| `morale.base`, `dread_ratio`, `dread_k`, `leave_below`, `death_shock`, `shock_s` | 0.6, 4 workers/living, 0.05, 0.35, 0.3, 600 | |
| `job.haul.carry`, `job.mill.rate` | 14 mass, 0.5 bone/mass | |
| `body_store.cap` | 200 + charnel/graveyard upgrades | |
| `relics.cap`, `essence.cap` | 12, 60 (the Reliquary raises both) | |
| `stance.base_slots`, `stance.hold_s` | 2, 10 | |
| `vats.grow_per_s` | 1/300 per staffed vat | |
| `backups.clone_respawn_s`, `unmade_respawn_s` | 60, 600 | |
| `phylactery.revive_hp`, `max_per_dungeon` | 0.5, 1 | |
| `essence.per_living`, `per_undead`, `lifetime_s` | 1, 1, 12 | `lifetime_s` is the existing raid.json name |
| `loot.reclear_decay` | 0.5 | |
| `vei.fronts_required`, `break_beats`, `loss_backlog_keep` | 3, 8, 0.35 | |
| `K`, `S_vei` | 12000, 8.0 | flagged by the audit (×4.8 and ×1.6 canon); calibrate in E4 |

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
