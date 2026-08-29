# NOTES — RAID & BOSS scenes

Worker report for `scenes/raid/Raid.tscn` and `scenes/boss/VeiBoss.tscn`.

## Files created

| File | What it is |
|---|---|
| `scenes/raid/Raid.tscn` | Root Node2D + `raid.gd` (everything else is built in code) |
| `scenes/boss/VeiBoss.tscn` | Root Node2D + `vei_boss.gd` |
| `scripts/raid/raid.gd` | Scene orchestrator: contract (setup/demo_seed/finished), arena build, camera, input routing, spatial grid, wall collision, raise resolution, endings |
| `scripts/raid/vei_boss.gd` | Extends raid.gd: Vei, brought army, backlog chaff stream, remnants, boss result dicts |
| `scripts/raid/raid_logic.gd` | PURE logic (`RaidLogic`): mass mappings, score→tier, `Ledger` inner class, seeded layout generator, flood-fill reachability, population. No autoloads — everything takes a cfg dict |
| `scripts/raid/circle_scorer.gd` | VERBATIM copy of raid-and-raise's `circle_scorer.gd` (Kåsa fit + sealing + grade + multiplier) |
| `scripts/raid/trance.gd` | Trance port: hold SPACE/RMB → time_scale 0.35, focus drains in real time (4s), 6s cooldown on summon, 1s lockout on empty release, LEFT-drag trace |
| `scripts/raid/trace_feedback.gd` | Feedback port: fitted ring over the actual trace + "SCORE — WORD" (~1.1 real s), bands incl. 98+ rainbow PERFECT |
| `scripts/raid/relish.gd` | Relish: click-to-move conduit; lethal-hit sacrifice rule + 0.5s i-frames; focus/cooldown arc |
| `scripts/raid/raid_unit.gd` | The one combat unit (enemy + undead kinds): wander/aggro/chase/melee cadence, separation, wall slide, grow-in, hp bars |
| `scripts/raid/vei.gd` | Vei: smite, telegraphed RADIANT PULSE, REVIVE channel (recycles corpses/essence into guards), contact-gated passive heal |
| `scripts/raid/essence_orb.gd` | Glowing green orb: ~12s world-time life, drift toward Relish ≤120px, absorb streak |
| `scripts/raid/corpse_pile.gd` | Grey MATTE pile; stirs into 2-4 orbs when Relish comes ≤90px; `small=true` variant = boss remnants |
| `scripts/raid/wall_segment.gd` | One wall segment; feeds the shader per-segment uniforms (length, world offset for hue continuity) |
| `scripts/raid/raid_hud.gd` | CanvasLayer HUD: fort/tier, counters, trance meter, hint, TELEPORT button + ConfirmationDialog, boss Vei bar + backlog, standalone result panel |
| `scripts/raid/raid_fx.gd` | One-shot fx: expanding rings, click ping, red soul-link line |
| `shaders/raid/wall.gdshader` | The showpiece: rainbow hue drifting along wall length, shimmer/pulse, neon rim, soft glow apron with door-jamb end fade |
| `configs/circle.json` | UNCHANGED copy from raid-and-raise |
| `configs/raid.json` | Every tuning knob (see below) |
| `tests/test_raid_logic.gd` | Pure-logic suite (TestUtil), 148 assertions, all passing |

## Ledger → result dict

`RaidLogic.Ledger` is the single accounting authority (`raid.gd` owns one instance).

- **Spawn mapping** (exact spec formulas, knobs in `raid.json: mass`):
  `enemy_count = clampi(round(living/cap*26), 5, 34)`, `mass_per_enemy = living/enemy_count`;
  `pile_count = clampi(int(dead/8), 2, 24)`, pile mass = `dead/pile_count`;
  garrison units = `clampi(int(undead/10), 0, 12)` (chaff-stat, **not** ledger mass — they are the fort's own undead).
- **Kills**: `ledger.on_kill(enemy.mass)` → `killed_living_mass`; one orb drops at the corpse carrying that mass.
- **Raises** (`ledger.on_raise(score, M, N)`):
  - score < 60 → N chaff units, each carrying `M/N` mass into the walking `chaff_pool`;
  - 60..89 → `max(1, N/3)` soldiers (count), `good_mass += M`;
  - ≥ 90 → `max(1, N/4)` elites (count), `good_mass += M`.
  - 0 orbs enclosed → nothing raised (feedback still shows).
- **Chaff re-killed in the raid**: its mass leaves `chaff_pool` and is reported nowhere — the corpse stays at the fort (the fort's `dead` implicitly keeps it, since the result only subtracts what it names).
- **Exit split**: surviving `chaff_pool` → `garrison_mass = min(pool, 0.25*cap)`, remainder → `raised_chaff_mass`. Same split on death.
- **Conservation invariant**: `raised_chaff_mass + good_mass + garrison_mass ≤ initial_dead + killed` — holds by construction (orbs only ever carry killed or pile mass); a safety clamp exists but the stress test shows it never triggers.
- `aborted = (killed == 0 and no raise ever happened)`.
- Result keys exactly per contract: `fort_id, killed_living_mass, raised_chaff_mass, raised_soldiers, raised_elites, good_mass, garrison_mass, relish_died, aborted`.

Boss result: `{fort_id, won, relish_died, backlog_spent, army_lost:{soldier,elite}}` — `backlog_spent` = mass drained by stream spawns (8/spawn), `army_lost` counts all soldier/elite deaths.

## Tuning knobs (all in `configs/raid.json`)

- `relish`: hp 30, speed 240, radius, i-frames.
- `trance`: time_scale 0.35, max_hold 4.0, cooldown 6.0, lockout 1.0, dim alpha.
- `essence`: lifetime 12s, drift radius/speed, stir radius 90, stir orb count 2-4, pop speed.
- `mass`: 26/cap, min 5, max 34, pile div 8 (2..24), garrison div 10 (0..12), garrison keep 0.25*cap.
- `combat`: aggro 260, separation, wander pacing, strike reach, ally follow + `ally_engage_px` (see deviations).
- `enemies` (spearman/runner/brute) + `tier_mix` per tier; `undead` (chaff 8hp/1.5, soldier 22/4, elite 50/9).
- `raise`: soldier ≥60, elite ≥90, orb divisors 3/4, spawn ring.
- `layout`: per-tier sizes (t1 1100×800 … t4 2200×1500, boss 2600×1800), wall thickness/glow, door width 150, inner gap 165, min room 300, flood-fill cell 32, floor grid step.
- `camera`: zoom clamp + view pad + smoothing.
- `boss`: hp formula knobs (`hp_base 1400 + hp_per_missing_odds 3200 * max(0, 0.8 - odds)`), smite (range/dmg/targets/cadence), pulse (radius 340, windup 1.2, cadence 7→4s as hp drops, dmg), revive (radius 400, channel 2s, cooldown, mass/guard 10, guard cap), guard statline, heal 8/s when uncontacted, stream (`2 + backlog/1500`/s, 8 mass/spawn, alive-chaff cap 130), remnants (mass, cap 40).
- Circle scoring knobs live in `configs/circle.json` (verbatim; owned by the scorer).

## Deviations from the spec (all flagged)

1. **Ally seek is leashed in raids** (`combat.ally_engage_px` 620): "seek nearest enemy" globally made the garrison abandon Relish at spawn and suicide across the map. Undead engage anything within 620px of themselves, else drift back to her. The boss scene sets it to 5000 so the horde marches the whole arena to Vei.
2. **Soldier/elite counts are banked at raise** and always leave with Relish even if the in-scene unit dies ("they're counts" per spec). In the boss scene deaths ARE counted (`army_lost`).
3. **Re-killed chaff mass is dropped, not reported** — see ledger section; the literal reading (add M at raise AND re-add survivors at exit) double-counts and can exceed available mass, which the spec's own invariant forbids.
4. **Invalid-but-long traces cost the trance** (score → feedback → cooldown, even at score 0) — matches the source prototype's behavior; sub-threshold scribbles are free retries within the same hold.
5. **Outer door gaps are visual**: units are clamped inside the arena, so perimeter doors are entrances in fiction only (nothing escapes into the void). Relish still spawns just inside the southernmost door.
6. **Boss layout north 42% is one open audience chamber** (no internal walls) so Vei's court is a clean battlefield; partitions only in the south. Boss doors: 7 (4 on the south for the stream).
7. **Vei's pulse also damages elites** (same heavy hit as soldiers) — spec only named soldiers; elites surviving ~3 pulses felt right for "brutal".
8. **Undead deaths in the boss leave small grey remnants** (capped 40) — this is the matter REVIVE recycles ("she recycles your dead!"); Relish can also stir remnants back into essence, so the mid-field is a contested resource.
9. **Boss keeps the TELEPORT exit** (retreat): emits `{won: false, relish_died: false, ...}`.
10. **Garrison undead at spawn are not ledger mass** — they're the fort's pre-existing undead; their deaths report nothing.
11. `army_lost` counts deaths of ALL soldiers/elites (brought + raised mid-fight) — the consumer (Game) treats it as informational.

## Verification done

- `godot --headless --import`: clean, classes registered.
- Logic tests: **148/148 PASS** via a temporary SceneTree runner (`tests/test_raid_runner_tmp.gd`, deleted after) — ledger conservation incl. a 40-step randomized stress, clamps, score bands, layout doors ≥ 2+tier, rooms ≥ 2+tier, flood-fill reachability of every room and door, spawn validity, per-fort determinism, boss layout, population legality (positions in-arena/off-wall, tier-legal kinds).
  Note: `--script` mode has no autoloads, so anything referencing `ConfigDb` cannot be exercised there (same constraint as the existing suites); scene scripts compile clean in the real runs below.
- Windowed runs (Shot harness): zero script errors from `scripts/raid/**` or the two scenes. (The `world_map.gd` errors visible in logs come from the map worker's scene, loaded by Main before Shot swaps.)

### Screenshots taken & reviewed
- `/tmp/necropolis-raid.png` — Vespers t2: rainbow slab walls + door gaps, orange wanderers spread away from spawn, grey matte pile, garrison chaff, Relish inside the south door, full HUD + TELEPORT button.
- `/tmp/necropolis-raid-action.png` — death flow: Relish mobbed, conduit sacrifice consumed the garrison chaff, then death → standalone panel shows the emitted result dict (`relish_died: true`, `aborted: true` — nothing was killed/raised — exact contract keys).
- `/tmp/necropolis-boss.png` — 30s in: Vei white-gold with halo/rays mobbed by a green melee ring, hp bar bitten down, backlog streaming from the south doors, remnants + essence afield, LOST counter ticking (attrition, no wipe).

## Known rough edges

- **No pathfinding**: units wall-slide (axis fallback) instead of navigating; a unit can hug an internal wall for a while before finding a gap. Layout guarantees multiple routes, which masks most of it.
- **Trance can't be exercised by the screenshot harness** (no key-hold injection), so circle scoring/feedback in-scene was verified by review of the ported code + the scorer's own passing math, not by pixels.
- Enemies never de-aggro once hostile.
- The trance meter reads READY while a raise's essence is still flying in (cooldown starts at release — intended, mildly confusing).
- Boss pacing beyond the 30s probe is config-guess: pulse cadence/heal were tuned so odds 0.61 + 41s/9e is a multi-minute attrition fight, but a full win/loss playthrough wasn't scripted.
- `Engine.time_scale` is global: in integrated play the trance dilates the idle sim too (out of scope to fix here; scenes always restore 1.0 on exit/death/finish).
