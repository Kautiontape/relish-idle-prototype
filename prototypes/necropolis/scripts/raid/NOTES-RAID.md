# NOTES — RAID & BOSS scenes

Worker report for `scenes/raid/Raid.tscn` and `scenes/boss/VeiBoss.tscn`.

## Files created

| File | What it is |
|---|---|
| `scenes/raid/Raid.tscn` | Root Node2D + `raid.gd` (everything else is built in code) |
| `scenes/boss/VeiBoss.tscn` | Root Node2D + `vei_boss.gd` |
| `scripts/raid/raid.gd` | Scene orchestrator: contract (setup/demo_seed/finished), arena build, camera, input routing, spatial grid, wall collision, raise resolution, endings |
| `scripts/raid/vei_boss.gd` | Extends raid.gd: Vei's final test, fronts then the break (see "Vei's final test (task 9b)") |
| `scripts/raid/boss_logic.gd`, `boss_lanes.gd`, `boss_guard.gd`, `boss_dev.gd`, `boss_autopilot.gd` | The boss's pure maths (`BossLogic`), the fronts on the field, her guards, the dev flags and the bot (task 9b) |
| `scripts/raid/raid_logic.gd` | PURE logic (`RaidLogic`): mass mappings, score→tier, the test-only v1 `Ledger` inner class and `raise_spec`, `LedgerV2`, seeded layout generator, flood-fill reachability, population. No autoloads — everything takes a cfg dict |
| `scripts/raid/circle_scorer.gd` | VERBATIM copy of raid-and-raise's `circle_scorer.gd` (Kåsa fit + sealing + grade + multiplier) |
| `scripts/raid/trance.gd` | Trance port: hold SPACE/RMB → time_scale 0.35, focus drains in real time (4s), 6s cooldown on summon, 1s lockout on empty release, LEFT-drag trace |
| `scripts/raid/trace_feedback.gd` | Feedback port: fitted ring over the actual trace + "SCORE — WORD" (~1.1 real s), bands incl. 98+ rainbow PERFECT |
| `scripts/raid/relish.gd` | Relish: click-to-move conduit; lethal-hit sacrifice rule + 0.5s i-frames; focus/cooldown arc |
| `scripts/raid/raid_unit.gd` | The one combat unit (enemy + undead kinds): wander/aggro/chase/melee cadence, separation, wall slide, grow-in, hp bars |
| `scripts/raid/vei.gd` | Vei (task 9b): her cream and gold ring glyph and her weaves (a beat-timed `danger` thread that hunts Relish) |
| `scripts/raid/essence_orb.gd` | Glowing green orb: ~12s world-time life, drift toward Relish ≤120px, absorb streak |
| `scripts/raid/corpse_pile.gd` | Grey MATTE pile; stirs into 2-4 orbs when Relish comes ≤90px |
| `scripts/raid/wall_segment.gd` | One wall segment; feeds the shader per-segment uniforms (length, world offset for hue continuity) |
| `scripts/raid/raid_hud.gd` | CanvasLayer HUD: fort/tier, counters, trance meter, hint, RETREAT button + its mouse-only retreat panel (`raid_retreat_panel.gd`, dungeon only; Phase I: Space never confirms a retreat), the boss block (fronts, horde, break pips, backups), standalone result panel |
| `scripts/raid/raid_fx.gd` | One-shot fx: expanding rings, click ping, red soul-link line |
| `shaders/raid/wall.gdshader` | The showpiece: rainbow hue drifting along wall length, shimmer/pulse, neon rim, soft glow apron with door-jamb end fade |
| `configs/circle.json` | UNCHANGED copy from raid-and-raise |
| `configs/raid.json` | Every tuning knob (see below) |
| `tests/test_raid_logic.gd` | Pure-logic suite (TestUtil), 148 assertions, all passing |

## Ledger → result dict

**Historical (v1).** `RaidLogic.Ledger` (with `raise_spec`) no longer runs in any scene: the dungeon accounts with `LedgerV2` and the boss builds its own result. It stays only as the v1 result fixture of `tests/test_results.gd` (from_v1) and `tests/test_raid_logic.gd`, and goes with them. The spawn mapping below still holds; the kill, raise and exit-split bullets describe that v1 class.

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

Boss result: the v2 boss result (STATE-API 8.2) from `VeiFronts.boss_result`, built by `BossLogic.fight_result`; see "Vei's final test (task 9b)". The boss keeps no ledger.

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
- `boss`: GONE. The raid.json `boss` block (hp, smite, pulse, revive, guard, heal, stream, remnant knobs) was removed with its only reader, `spawn_unit`'s guard branch; the boss's knobs are `configs/vei.json`. `layout.boss_*` stays (the arena reads it).
- Circle scoring knobs live in `configs/circle.json` (verbatim; owned by the scorer).

## Deviations from the spec (all flagged)

1. **Ally seek is leashed in raids** (`combat.ally_engage_px` 620): "seek nearest enemy" globally made the garrison abandon Relish at spawn and suicide across the map. Undead engage anything within 620px of themselves, else drift back to her. The boss scene sets it from `vei.json raised.engage_px`.
2. **Soldier/elite counts are banked at raise** and always leave with Relish even if the in-scene unit dies ("they're counts" per spec). (The boss has no such counts since task 9b.)
3. **Re-killed chaff mass is dropped, not reported** — see ledger section; the literal reading (add M at raise AND re-add survivors at exit) double-counts and can exceed available mass, which the spec's own invariant forbids.
4. **Invalid-but-long traces cost the trance** (score → feedback → cooldown, even at score 0) — matches the source prototype's behavior; sub-threshold scribbles are free retries within the same hold.
5. **Outer door gaps are visual**: units are clamped inside the arena, so perimeter doors are entrances in fiction only (nothing escapes into the void). Relish still spawns just inside the southernmost door.
6–9. (Superseded by task 9b: the old boss's split audience chamber, pulse, remnants and TELEPORT exit are gone. The boss arena is one open field, `vei.json arena.layout` boss_rooms 1, and there is no retreat from Vei.)
10. **Garrison undead at spawn are not ledger mass** — they're the fort's pre-existing undead; their deaths report nothing.
11. (Superseded by task 9b: no `army_lost`.)

## Verification done

- `godot --headless --import`: clean, classes registered.
- Logic tests: **148/148 PASS** via a temporary SceneTree runner (`tests/test_raid_runner_tmp.gd`, deleted after) — ledger conservation incl. a 40-step randomized stress, clamps, score bands, layout doors ≥ 2+tier, rooms ≥ 2+tier, flood-fill reachability of every room and door, spawn validity, per-fort determinism, boss layout, population legality (positions in-arena/off-wall, tier-legal kinds).
  Note: `--script` mode has no autoloads, so anything referencing `ConfigDb` cannot be exercised there (same constraint as the existing suites); scene scripts compile clean in the real runs below.
- Windowed runs (Shot harness): zero script errors from `scripts/raid/**` or the two scenes. (The `world_map.gd` errors visible in logs come from the map worker's scene, loaded by Main before Shot swaps.)

### Smoke command (acceptance run)

Walks Relish onto the deterministic Vespers corpse pile (stir → essence), then the
harness holds SPACE and drags a circle around her (score ~97 → 1 elite), then lets
the elite fight. The final frame must show `RAISED … elite 1`, `ESSENCE > 0` (orbs
from the elite's kills), `LIVING < 20`, and the log no `SCRIPT ERROR`:

```sh
WAYLAND_DISPLAY=wayland-2 flock -w 300 /tmp/necropolis-godot.lock timeout 150 \
  godot --display-driver wayland --audio-driver Dummy --rendering-driver opengl3 \
  --path /home/shawn/documents/apps/games/relish-idle-prototype/prototypes/necropolis -- \
  --shot=/tmp/necropolis-raid-raise.png --frames=240 --scene=res://scenes/raid/Raid.tscn \
  --clicks="960,546;960,546;960,546;960,546;960,546;960,546;960,546;960,546;960,546;960,546;960,546;960,546;960,546;960,546" \
  --trace=960,546,120
```

(Coords assume the 1584×873 nested-compositor window: pile A of "vespers" t2 sits at
world (890, 790); the camera is pinned at (725, 681.6) for the whole walk, zoom 1.019.)

### Screenshots taken & reviewed
- `/tmp/necropolis-raid.png` — Vespers t2: rainbow slab walls + door gaps, orange wanderers spread away from spawn, grey matte pile, garrison chaff, Relish inside the south door, full HUD + TELEPORT button.
- `/tmp/necropolis-raid-raise.png` — the acceptance frame: after the smoke command, LIVING 17 / ESSENCE 3 / RAISED elite 1, orbs pooled at Relish, elite mid-fight, amber cooldown arc. An earlier 40-frame variant of the same run captured the feedback itself: "97 — GREAT" over the fitted ring, elite growing in.
- `/tmp/necropolis-raid-action.png` — death flow: Relish mobbed, conduit sacrifice consumed the garrison chaff, then death → standalone panel shows the emitted result dict (`relish_died: true`, `aborted: true` — nothing was killed/raised — exact contract keys).
- (The old boss screenshot is superseded; task 9b's are in the run's `reports/dungeon/t9-*.png`.)

## Known rough edges

- **Room-graph routing, not pathfinding**: units, Relish's click-to-move and the Huntsman's stalk steer through doorways via `LayoutLogic.waypoint` (layout build adds `portals` per ordered room pair, a BFS `next_room` table and `room_hops`; config `combat.route_repath_s` 0.25, `route_door_pad_px` 14, `layout.route_min_gap_px` 28). Same room or a clear line (`line_clear`, slab test against the inner walls) goes straight; otherwise to a doorstep in the current room, then through the nearest gap on the shortest room path. A mover in a doorway steps out into the touching room nearest the target first. `RaidRoute` caches the portal answer per mover (a direct answer tracks the live target), recomputed every 0.25 s staggered per mover, on leaving the routed room (an answer asked in a doorway band is kept until the mover steps into a room), or on the 3 px doorstep where `waypoint` flips to the far side; a unit's target switch re-asks at once (`RaidUnit._pick_target`, as Relish's click). Target picks run on the same stagger; allies' `ally_engage_px` leash and enemy aggro use `LayoutLogic.route_dist` (straight line when the rooms are shared, else via the nearest gap and one room-centre hop; no wall tests), so a foe behind a wall counts at the cost of the doorway. The wall-slide stays as the last-resort collision response. Limits: routing is room-to-room, so inside a room a unit still walks straight to the doorstep (crowds can queue at a narrow gap, and the separation push does the rest); the portal is the gap stretch nearest the mover, not the least crowded; a T-junction stretch narrower than `route_min_gap_px` is not a portal (unless it is a room's only link); each portal keeps its width (the stretch both rooms face), and a mover of radius r routes (`waypoint`, `route_dist`) only through portals at least 2r + `layout.route_fit_pad_px` (4) wide, falling back to every portal when its size has no way at all; `gen_layout` takes the first grid-reachable attempt in which a party big undead (`party.radius`) reaches every room this way (`LayoutLogic.fits_all_rooms`; every world.json fort at every tier, and the boss arena, does); the leash distance is a one-hop estimate, not a true path length; the warden target counts walking distance too (`LayoutLogic.walk_within`), Vei in the boss arena still counts straight-line for the leash; the Huntsman's lunge is a straight line clipped by walls as before; the autopilot keeps its own room-path routing (`_toward_room`).
- Enemies never de-aggro once hostile.
- The trance meter reads READY while a raise's essence is still flying in (cooldown starts at release — intended, mildly confusing).
- **The boss is rebuilt (task 9b)** on fronts, then the break; the old HP-brawl pacing note no longer applies. Its open items are in "Vei's final test (task 9b)".
- `Engine.time_scale` is global: in integrated play the trance dilates the idle sim too (out of scope to fix here; scenes always restore 1.0 on exit/death/finish).

## Dungeon features before balance calibration (task 8b-1)

- **Ghost ring** (`ghost_ring.gd`, first dungeon only): faint dashed `relish` ring round the mote cluster while the trance is open and nothing has risen yet; hides after the first raise or when the trance ends. Same helper as the bot's circle: `RaidLogic.ghost_ring`. Config: `raid.json ghost_ring`. Dev: `--raid-trance-hold` opens the trance at start (for the shot).
- **Near-spawn pile**: `gen_layout(..., {first_dungeon})` flags the layout (geometry unchanged); `populate_piles` puts one pile `first_pile_min_px`..`first_pile_px` from the spawn (outside the 90px stir radius, inside her 220px light). With no dead (the real first dungeon) `raid.gd` builds that one pile alone and it is massless (mints no mass).
- **Floor loot** (`loot_pickup.gd`): a ding drops a `vei` shard; walking within `loot.json pickup.radius_px` collects it into `found_loot`. Left on the floor = lost. HUD: BANKED / UNBANKED (`RaidLogic.unbanked`), danger-coloured when non-zero.
- **Huntsman hides**: while Relish is outside its room it lunges at the nearest undead in or entering the room (`WardenLogic.hunt_target`, `attack.hunt_margin_px`); no catches.
- **Autopilot**: Bellringer fight raises through the slam when `WardenLogic.slam_window_open` (config `slam_*`); fetches pickups; foes behind a wall no longer trigger kiting; new result fields `first_raise_s`, `warden_hp_frac_end`, `pickups_left`, `unbanked_lost`.
- **Known deadlock (fixed by room-graph routing, see Known rough edges)**: with no pathfinding, a whole army and the enemies it targets can press on opposite sides of one wall for the entire run (seen at old-sluice: 19 raised chaff at x=593, 11 enemies at x=643). The bot then idles out and retreats with the warden untouched.

## Idle rules (task 13)

- **Held-fort clear** (`raid_held_clear.gd`, config `raid.json held`): when the last living enemy of a held (non-boss) raid dies, `RaidLoot.held_clear` is rolled and merged into `found_loot`, the banner `COUNTER-GARRISON CLEARED · <fort> holds` (+ a payoff line) shows in `undead_core`, a town-blue ring sweeps out from Relish and the walls flash toward `town` (reduced motion: no fade), the essence bonus spawns as mass-0 motes round Relish, and after `held.clear_victory_s` the run ends as `retreated` through `endings.confirm_exit` (any earlier end wins: `endings.ended` guards a double). A held fort with no living at the start has no last kill, so it clears `held.empty_clear_s` (1.0 s) after the build (`RaidHeldClear.on_built`, `RaidLogic.held_empty_clear_s`). Dev: `--raid-held --raid-autopilot=70 [--raid-held-shot=<png>]`.
- **A close ends the run** (`RaidEndings.close_request`, `raid.gd _notification`): a router-launched run that gets `NOTIFICATION_WM_CLOSE_REQUEST` emits at once, and the router applies it inside the same notification (`main.gd _on_finished` -> `_apply` -> `_open_map` -> `Game.autosave()`), so the quit save already has the run closed.
  - **Dungeon:** `retreated` paying `RaidLogic.close_loot(banked)` (the last checkpoint; found-since is lost), except during an ending beat (`endings.pending_exit`, set by the beat from `RaidLogic.pending_on`; `RaidLogic.close_plan` decides, `RaidLogic.result_loot` pays): an ending that happened while present stands. During Relish's death beat it stays `relish_died` (a death is not dodged); during the warden's victory beat (chest opened, `wardens.victory_s`) it stays `warden_beaten` with the full loot, chest included, the result the beat's timer would have built. The held-fort clear window (`held.clear_victory_s`) is not an ending beat: a close there is the checkpoint retreat (I5; a held clear is not a flip).
  - **Boss:** `VeiBoss.close_result()`. Lost, with the backups spent so far still spent and `relish_deaths` = spent (+1 if the final-death beat was playing, `BossLogic.close_fields`); the win if Vei already broke (her unravel playing). No refund of backups by closing.
  - TODO(api-request #4): replaced by economy's load-time retreat. Not covered: a kill/crash/`SceneTree.quit()` (no close request). Known: `main.gd` opens the map inside the notification, which logs "Parent node is busy setting up children" on close (pre-existing; the result is applied before it).

## Balance calibration (task 8b-2)

Measured with the headless autopilot against BALANCE 3. The party is the standard "party of tier T"
(`--raid-profile=<T> --raid-fort=<fort_id>`, `raid.json autopilot.party_profiles`, fixed before calibrating).
Each tier is measured at its two forts (one Bellringer, one Huntsman). P1 is the day1 fixture at Old Sluice.
Batches ran from a snapshot of the commit (another agent was editing the worktree).

- **The Bellringer is a re-raise fight.** An unmuffled slam (`dmg_unit` 11) kills score-50 chaff
  (10 hp) and leaves 70 and 90 nearly dead. A muffled slam (×0.35, a beef-6+ big braced at the bell) spares them for
  three or four slams. The ring reaches 260 px, so Relish re-raises the fallen from just outside it
  (the bot waits `bell_stage_px` 20 beyond it), and the warden's hp (2800 + 1250/tier) is sized so that
  takes about 100 s. Without the brace (P1 has no big, a P3 party has lost its big) the army melts every slam.
- **The Huntsman is a race the weak point wins.** Lunges hurt the undead on the dash (`dmg_unit` 8).
  A fast big intercepts and stuns it for 3 beats at ×2.5 damage, so the tier-4 party (3 fast bigs)
  stuns it far more often than a tier-2 party (one). A drawn-out fight costs the bigs, then the
  catches start. Its hp (3400 + 500/tier) keeps the fight to about 40–110 s.
- **What the fight telemetry shows** (`reports/dungeon/standins-measured.json` `fight_telemetry`, re-measured
  at c9f958a; raw lines in `reports/dungeon/acceptance-raw-c9f958a.tsv`). At tier (t2-t4, 30 runs per archetype)
  a braced bell muffles 64% of slams and fast bigs intercept 66% of lunges. In P3 that falls to 2% and 19%,
  because the tier-2 big dies on the tier-4 approach. P1 has no big (no weak point) and wins on 15.4 raises
  per fight after the wake. No death at tier; P3: 9 of 20, all after the wake. Warden hp left at t3 by score
  50 / 70 / 90: 0.101 / 0.006 / 0.006.
- **Tiers separate on the living**, not the count (every profile fort fields round(0.85 × 26) = 22).
  A heavier brute (70 hp, 10 dmg, speed 70) is 30% / 45% of the t3 / t4 mix. A tier-2 party loses its
  big there and dies (P3). Spearman and runner stay at their old lines, which P1, t1 and t2 share.
- **The first dungeon** keeps the full t1 hp (`first_dungeon.hp_mult` 1.0) but slow (×1.5) and soft
  (×0.6) slams, and 8 starters at `starter.stat_mult` 1.5.
- **Bot limits** (it is the instrument, not a player): it never uses the trance's slow-mo, never
  bails, raises only in a safe slam window, kites at 240 px, and dodges half the lunge tells. It
  walks into the warden room as soon as the way is clear, so at whitecross the Huntsman can wake
  with living still in other rooms.
- **Acceptance** (score 70, c9f958a; P2 is seeds 1-10 at each of the tier's two forts; medians in seconds;
  raw lines in `reports/dungeon/acceptance-raw-c9f958a.tsv`, the numbers in `standins-measured.json`
  `acceptance_70`, `first_dungeon`, `two_tiers_above`):

  | row | runs | died | beaten | median s |
  |---|---|---|---|---|
  | P1 first dungeon | 60 | 0 (upper bound 4.9%) | 60 | 118 |
  | P2 t2 | 20 | 0 | 20 | 138 |
  | P2 t3 | 20 | 0 | 19 | 108 |
  | P2 t4 | 20 | 0 | 20 | 126 |
  | P3 t2 party at t4 | 20 | 9 (45%) | 8 | 201 |

  The old doorway-stall and side-room misses (deaths at whitecross, a short t3) no longer show at this commit.


## D-b review fixes (readability only)

No mechanic or balance change: the two byte-identity smokes (day1 at old-sluice, P3 at hollow-redoubt, autopilot 70 seed 1) give the same `AUTOPILOT_RESULT` before and after.

- **Wardens are `vei`, never the living's orange**, each with its own glyph: the Bellringer a bell outline (one rib per phase left, a clapper that swings through the tell and strikes on the slam, held at the struck angle under reduced motion), the Huntsman an arrowhead on a lance along its aim (tip `danger` while a lunge is locked).
- **The break meter** (`WardenLogic.meter_*`, `wardens.meter_pips` 12; HUD `WardenBlock` top centre, a pip row under the glyph): the strength left as pips. An hp-phased warden gets one segment per phase, each counting down through that phase's hp band (ceil), so a notch is crossed on exactly the hit that changes `bellringer_phase` (tested at every 0.001 of hp). The Huntsman's phases are catches, so its strength is one flat row and its notches sit on the CAUGHT track (2, 4). Pips taken inside a stun window are marked `undead` with a slash for the fight and flash while the window is open; the Bellringer's counterplay reads as `MUFFLED x n of m`.
- **The weak point as it happens**: a muffled slam goes out dim and dashed with MUFFLED riding it; through the tell each bracing big (the muffle's own rule) is ringed with a line into the bell; the live brace is the word BRACED.
- **Relish's safety** (D-d/V2): with no phylactery left her halo breaks into `danger`-leaning dashes, clearly red even at full hp (`danger.exposed_min` 0.6, rising to `exposed_max`); PHYLACT. says NO REVIVE · death ends the run in `danger` whatever her hp (a state, not a mood; `exposed_tint` is no longer used by the HUD). No hits-to-death words: the conduit rule makes it depend on the allies left, so a number would not be honest. Each Huntsman catch cracks her ring for the run; the CAUGHT track's third row states the cost and the thresholds from the spec (`WardenLogic.catch_label`: "each catch costs Relish 12 hp (an ally takes a killing one) · it hunts faster at 2 and 4 catches"; first dungeon: 7 hp).
- **Loot**: one glyph per kind (`RaidLoot.floor_glyph`), all in a faint `vei` loot ring; husks and remnants matte (`dead_lit` under her light). Only remnants drop on the floor in play (`--raid-loot-sample` lays all four). A dashed pointer runs from "N on the floor" to the nearest pickup (LOOT chevron off screen). RETREAT says "banks your loot" itself, since the hint line keeps the circle hint at the spawn exit before the first raise.
- **Push or retreat**: `LIVING n left · exit W, 2 rooms · ... at risk` under RETREAT, an EXIT chevron off screen; corpse piles carry an `xN` badge; the last chance names its loose essence; the held clear names `counter-garrison −N`.

## Vei's final test (task 9b)

`vei_boss.gd` rebuilds the boss on fronts, then the break (MECHANICS 6, GAMEPLAY 3d). Rules are `VeiFronts`; `BossLogic` places and counts; `BossLanes` draws the fronts; `RaidVei` is Vei and her weaves. Knobs: `configs/vei.json` (each block has a `_doc`). Dev: `boss_dev.gd` (`--boss-phase2`, `--boss-stress`, `--boss-fronts=n`, `--boss-backups=p,c`, `--boss-autodie/autowin=<frames>`, `--boss-hold-tell`, `--boss-prof`, `--boss-hide=`, `--boss-cfg=k.k=v;...` to override `vei.json` numbers for one standalone run) and the bot `--boss-autoplay=<score>` (`boss_autopilot.gd`).

- **Guards go for Relish** (`BossGuard`, `vei.json guards.block_px` 50): a guard targets Relish and fights an undead only when one is within `block_px` (in its way). Why: with RaidUnit's own pick (the nearer of Relish and the nearest undead), the party's big undead at her court absorbed every guard, Relish never died in any autoplay, and her backups never mattered. The task reads "they hunt Relish and the undead"; the undead round her are her shield, and the sacrifice chain is what a guard that reaches her costs.
- **Deviation: the break is 20 beats with a lapse cost, not 8 consecutive beats** (task 9d). MECHANICS 6 says Vei breaks after `break_beats` *consecutive* beats with raise > ferry, and BALANCE 5 lists `break_beats` 8. As built (`configs/vei.json`): `break_beats` 20, and a beat without raise > ferry (a lapse) costs `lapse_cost` 4 beats of the streak instead of resetting it (`VeiFronts.break_beat`; `lapse_cost` -1 restores the reset, the code default). Why: 8 beats made the climax about 30 s and often under; 20 beats gives a 45-75 s break, and with a full reset one lapse late in a long streak threw away most of a minute.
- **The sacrifice chain is the dungeon's** (MECHANICS 5.0): a lethal hit on Relish spends chaff, then soldiers, elites, then the party's big undead, nearest within a rank (raid.gd `sacrifice_nearest_ally` uses `RaidLogic.ally_rank` for the boss too; its old boss branch took the plain nearest and could spend a named big undead before the chaff beside it).
- **A revive does not ready her trance** (task 9e, `vei.json backups.ready_trance` false; true restores task 9d's `RaidTrance.ready_now` on a revive: the cooldown spent, no stored free raise). Why: once the guards were bounded (below), a revive that also readied the trance recovered nine deaths in ten whatever the other revive numbers were, so V1 sat near 90% and could not be tuned.
- **Guards fall back after `guards.life_s`** (task 9e, 6 s): a guard that has stood that long returns to her line (`VeiBoss.recall_guard`, no mote), so the living guards never outnumber rate x uncleared x life_s (each guard's own `life_left` enforces it: `life_s` 0, the code default, keeps them until killed). `BossLogic.guard_ceiling` is that bound as a pure function, tested in `tests/test_vei_fronts.gd`; nothing in the scene calls it. Why: the fight was bistable. Once the guards outpaced the army they piled up to `cap`, more guards killed more undead, and the survivors lived longer still, so 5% fewer guards per second moved V1 by +22 points and V2 by +30, and 5% weaker guards V1 by +20, while 5% more moved nothing (n=40; the before and after tables are in the run's `reports/dungeon/vei-calibration-log.txt`). The ceiling ties the pile-up to the fronts left uncleared, which the player controls.
- **Damage sits off the hit-count steps** (task 9e). Relish has 30 hp and a hit is lethal at `hp - dmg <= 0`. Before 9e, two weaves (15) or three guard hits (10) made exactly 30, so a 5% cut changed how many hits killed her. Weave 13.5 and guard 8.8 keep every small sum at least 5% from 30 (1 weave + 2 guard hits 31.1, 3 guard hits 26.4, 2 weaves 27). Guard 8.8 and hp 49.5 also keep the hits a guard needs on each big undead, and on a score-70 raised undead, off whole numbers.
- **The first weave's tell is 2 beats** (`weaves.first_tell_beats`), one more than the spec's one-beat tell (`tell_beats` 1), as part of the "Vei's first weave" set piece: the thread draws itself out from her while a banner names it. Every later weave tells one beat ahead.
- **`raised.unit_cap` 20 is a perf cap.** Raises past it still count toward the break (their value feeds `break_beat`) but add no fighters. It also bounds her ward (the sacrifice chain), so it doubles as a gameplay limit; calibrate them together.
- **The horde-drained loss exists but is out of reach at demo numbers.** H is the seed's backlog (~18k) and Vei ferries it at F (~3.4/s at pool 380, q 2.6, one uncleared front), so draining takes about 90 minutes. In practice the break is a race against deaths. A Vei-calibration item; left as is.
- **fronts_cleared** in the result is the list frozen when the break begins, or, for a fight that ends in phase 1 (timeout, final death, close), what phase 1 had cleared (`BossLogic.fight_result`).
- **Legacy removed from the shared files**: raid.gd's `ledger` and the boss `_build` branch that built it, the boss branches of `on_unit_died` (VeiBoss overrides it whole), `spawn_unit`'s guard branch, the `args.boss` setup branch, `backlog_left`/`army_lost`/`_on_ally_died`/`spawn_orb`, `RaidUnit.ledger_mass`/`from_army`, and `raid_raise.gd _perform_legacy`. Later (task 9e) also `sacrifice_nearest_ally`'s boss rank-0 branch, the boss `randomize()` branch and `RaidPile.consume()`. Kept: `RaidLogic.Ledger`/`raise_spec` as test-only fixtures (`test_results.gd` builds a v1 result with them).

### Vei's win card, meter and cues (D-d V1)

- **The win card** (`vei_card.gd` `VeiCard`, built by `VeiBoss._win_card`): after the unravel and the green lanes, the board holds under a dim (`card.dim`) and one plate says VEI BREAKS, the fight time (`BossLogic.clock_text`), the backups spent as the BACKUPS row draws them (a cracked violet ring per spent one, a violet diamond or dot per unspent one, "n of m"), the big undead lost ("n of m", known party uids only) and the backlog spent (the result's `backlog_spent`, the only banked figure a boss result carries), over one "BACK TO THE REALM" button (`card.button_h_px` 54, never under 44; Enter, Space and Escape press it too, as does a click). The card takes no press for `card.skip_after_s` (0.8 s, `BossLogic.card_unlocked`; the button is dim until then), because Space is the boss trance key and a player still holding it as the set piece ends would dismiss the card unseen; the boss bot never waits, and a window close during the card is still the win. All of it is `BossLogic.end_card` plus drawing. The old 3.5 s banner is gone.
- **When `finished` emits: on the button**, not when the card shows (the router swaps to the map the moment it hears it, which would take the card away). Same dict, same single emit (`_emit`, guarded by `_emitted`). A window close while the card is up is the win: `close_result()` already reads a broken Vei as won and sets `_emitted`, so a later press does nothing. A router-launched run therefore returns to the realm on the button, as it did on the old timer. The standalone bot (`--boss-autoplay`) has no hand to click: `_win_card` emits at once, at the same moment the old timer did (its BOSS_RESULT / BOSS_AUTOPLAY lines are byte-identical). `--boss-autowin` shows the card and waits; pressing it prints BOSS_RESULT and the standalone result panel replaces the card.
- **`BREAK 8/8` in the old `t9-victory`** was a stale still, not code: `break_beats` reaches the HUD, the row under her and `--boss-autowin` from `vei.json` (20); 8 is only the code default in `VeiFronts.broken` and the `vc.get("break_beats", 8)` fallbacks, which only a config without the key reaches. The re-shot reads 20/20.
- **The meter is drawn once** in full: the HUD's BREAK row. The row under Vei is kept only as the close-to-the-break signal: it appears once the streak is within `meter.row_close_pips` (5, the last notch) of `break_beats`, and while a lapse flashes (0 keeps it always on). `RaidVei.MeterRow._shown`.
- **Beside the beat count: "~30 s at this pace"** (`BossLogic.break_eta_s`, `eta_text`). The pace is the net pips per beat over the last `meter.eta_window_beats` (8) beats (a gain +1, a lapse -`lapse_cost`), the pips still to fill over it, times the tempo. No hint before `eta_min_beats` (4) beats are known, while the pace does not gain, under the reset rule once the window holds a lapse, or past `eta_max_s`. It is scene time at the current tempo: a slowed (trance) beat clock makes it optimistic by the slow-down, hence "at this pace". `VeiBoss.beat_hist` is a new field the sim never reads.
- **Under the meter, one line**: the phase-2 rule for the break's first `meter.hint_s` (14) seconds, "keep raise > ferry for 20 beats · a lapse costs 4" (numbers from the config), and from the first lapse "LAPSES ×4 · −10 beats" (the beats the streak actually lost, capped by what it held, so 4 lapses of cost 4 show -10 when the streak was short). No LAPSES row before the first lapse.
- **BACKLOG, not HORDE**: the label says what it is, the rate reads "ferried 3.43/s" (no minus, no slant), because the real clock is deaths (the drain takes ~90 minutes, above).
- **Relish over a front label**: `Labels.label_shift` moves a lane's label plate just below her token while they would overlap (above her when the arena ends under it); it is in the redraw key.
- **The i-frames cue** (`BossLanes.SafeCue`, a child of Relish like the backup marks, driven by `VeiBoss.revive_cue` / `revive_total`): a violet ring outside her body whose arc is the i-frame time left, with orbiting sparks, and "SAFE n s" counting down under her. Reduced motion: no sparks, the arc steps once a second; the words stay. Relish's own script is untouched; the cue reads her `_iframes`.
- **Known gap: a hard kill while the card idles loses the win.** Nothing is saved until the button (the `finished` emit), so a SIGTERM or a crash with the card up drops the run as unfinished. A normal window close is safe: `close_result()` returns the win. The card also catches Enter, Space and Escape itself (`_input`), since the scene ignores input once the fight is over.
- Dev: `--boss-hold-card` (with `--boss-autoplay`) makes the bot's win show the card and wait instead of emitting and quitting, for the card screenshot from a real fight; `--boss-greyscale` puts the greyscale check shader over the whole screen (the phase-2 greyscale still).

## Reduced-motion parity (draw vs count)
- Where a carried mote COUNTS is `RaidLogic.carry_slot_angle` (a clock slot, no animation state). What is DRAWN may rock by a sine (`raid.carry_draw_angle`/`carry_draw_offset`, `essence.carry_spin_rad_s`) but never more than `essence.carry_swing_px` (3 px) from the counted slot, and not at all under reduced motion. Sim code (`_carry_step`, `carry_angle`, enclosure in `raid_raise.gd`, the bot's `_motes_near`) never calls the draw functions; `tests/test_raid_logic.gd` guards it by source.
- `tests/parity_check.sh` runs the raid bot (old-sluice day1, and the tier-3 profile at hollow-redoubt, pale-bastion and mourners-gate, seed 1) and the boss bot (seed 1) with and without `--reduced-motion` and exits non-zero on any difference in the result lines (~1 min).

## D-d/V2: death frame, run shape, zero rows
- **Death card** (`raid_death_card.gd`, `RaidEndings.on_relish_died`, config `raid.json death`): the death beat is `card_s` (4.5 s) instead of 0.9 s and shows one card: KILLED BY (`Relish.last_hit_src`: the Bellringer's slam, the Huntsman's lunge, the living, else "a wound"; a hit an ally soaked still names its source), BANKED (the last checkpoint), LOST (unbanked loot, and the party's big undead: a death costs the whole party). A click or SPACE after `skip_after_s` ends it early. The result dict and its single emit are untouched (`_finish_death` guards a double); a window close during it stays a death (`close_request`/`pending_exit`). The measuring bot never waits (`RaidAutopilot.enabled()` keeps the 0.9 s beat), so the bot lines are unchanged. Dev: `--raid-autodie=<frames> --raid-autodie-src=slam|lunge|living`.
- **Run shape**: the push line starts with "3 of 5 rooms seen" (rooms Relish has stood in, `RaidEndings.rooms_seen`, of `layout.rooms`). Seen, not cleared: a room can be crossed with the living still in it. It wraps on a narrow window like the rest of the line.
- **Last-chance banner**: "LAST CHANCE · a free trance · N loose essence to gather". N is the loose essence in the antechamber (capped by the carry room), a different figure from ESSENCE n/12 (carried) and UNBANKED (what a death loses), so it no longer says "bank".
- **Zero rows**: MUFFLED hides until the first slam (the PHASE row already says what muffles it; "×0 of 3" stays, it teaches); the Huntsman's INTERCEPTED ×0 is replaced by the weak point's words until the first intercept; the CAUGHT count digit hides at 0 (the empty diamonds teach it); WARD ranks keep their labels at 0 but drop the "0" (the labels teach the chain's order).
- **Loot key**: while anything lies on the floor, two dim rows under the stakes draw the four floor glyphs (relic, remnant, husk, blueprint) with their names and say what a grey ×9 pile is.
- **Plate**: the stat block's backing plate is `hud.plate_alpha` 0.86 so a corpse glyph under it never crosses the NO REVIVE caption.
- Dev: `--raid-greyscale` puts the greyscale check shader over the screen (the warden-fight still).

## The Shieldwall (D-d/B, task 10 part 1)
`warden_shieldwall.gd` (`RaidShieldwall`), rules in `WardenLogic.shield_*` / `flank_*` / `bash_hits`, knobs in `raid.json wardens.archetypes.shieldwall` (its `_doc`). Forts: pale-bastion (t3) and the-stair (t4); hollow-redoubt, mourners-gate, whitecross stay Huntsman and sable-hold Bellringer (the Pyre-priest task takes mourners-gate and whitecross).

- **Facing (one rule):** it turns toward the densest crowd of undead within `face_reach_px` (240): for each undead's bearing, count the undead within the front half-arc of it; the most wins, a tie goes to the bearing nearest the current facing (an even ring holds still); the goal is that sector's mean bearing (`WardenLogic.shield_goal`, re-picked every `face_repick_s` 0.15 s). The flank-role undead are left out (else it would turn to them and cancel its own weak point). With no undead in reach it faces Relish while she is in its room, else holds. It turns at the phase's `turn_deg_s`, never past the goal (`turn_step`), and is planted (no turn) from the first frame of a bash tell through the bash frame itself (`WardenLogic.shield_turns`; before D-d/F the frame that bashed turned first, up to `turn_deg_s`/60 off the lit arc, 1.2° in phase 3), so the lit arc is where the bash lands. That fix moved the Shieldwall forts' seed-1 lines (pale-bastion, the-stair; every other fort's line is byte-identical). Dormant, it faces the antechamber.
- **Hits (`hit_from`, the undead strike; RaidUnit calls it for any warden, the others forward it to `take_hit`):** the zone is read from the attacker's position (`shield_zone`). Front arc (±`front_half_deg`): GLANCE, ×`front_mult` 0.1, `clang`. Outside it: FLANKED, `flank` (`heavy` for a big undead); in full from the side, ×`back_mult` 2.5 from inside the back arc (±`back_half_deg` 45 round its back). The pips a flank hit takes are marked as the weak point's on the meter.
- **The bash:** every `period_beats`, telegraphed `tell_beats` (1) ahead: the front arc out to `reach_px` (140) is lit `danger`, with the word BASH and her edge warning when it covers her. On the beat every undead in it takes `dmg_unit` 10 and is shoved `shove_px` 50 straight away; Relish in it takes `dmg_relish` 12 (death card: "The Shieldwall's bash").
- **Phases** at hp thirds (the meter is notched there): turn 40 / 55 / 70 °/s, front ±80 / ±90 / ±100°, bash every 4 / 3 / 2 beats.
- **Weak point (wits ≥ 4, effect `flank`):** a party big undead whose wits meet it and whose target is the wall takes the flank role (`RaidWardenRun.flank_for`): it walks round the orbit (its radius + the wall's + `flank_gap_px`), `flank_step_deg` 40 at a time so it never cuts through the wall, to a post straight behind (several spread `flank_spread_deg` 34 apart), and holds its blow while it is on the shield's side. The standard t3 party's bigs have wits 4 and the t4's 5, so the stock party meets it, as for the other wardens. `--raid-party-wits=<n>` (with `--raid-profile`) sets every party big's wits, for the without arm.
- **Readability (tell -> counter -> labelled result -> meter drops):** the silhouette is a heavy `vei` shield arc over the front (one plate behind it per phase left; one falls away at each phase), a boss on the shield pointing where it faces, a helm and spine behind, and the back arc dashed with the word FLANK. A faint `danger` arc marks the bash's reach. GLANCE shows on the shield and FLANKED where the last flank landed (held `wardens.shield_label_s` 0.8 s). Each flank-role big is ringed `undead` with a line into the wall's back. HUD: "FLANKED ×n of m · took k" (the weak point's words until the first flank), row 2 "PHASE n/3" and the shield line from the spec ("front ±80° glances ×0.1 · back ×2.5 · turns 40°/s · bash every 4 beats"). Reduced motion: the facing is drawn at its sim angle, the tell's arc is steady and its word stays, the bash after-image is a step.
- **The bot** (`_vs_wall`; its tell handling is superseded by the reaction rule, see "The bot's reaction model as built"): it keeps out of the bash arc grown by `wall_margin_px` 30 and `wall_margin_deg` 15, fetches only motes and pickups outside it, and otherwise waits `wall_side_deg` 110 off the facing, `wall_stand_px` 40 beyond the bash, walking round the short way and keeping its side until the other is `wall_switch_deg` 20 nearer. Its raises there walk in from the side. AUTOPILOT_RESULT gets a `shield` dict (hits, glances, flanks, backs, role hits, damage by kind, bashes, bash hits) for this archetype only; `warden_attacks` is bashes and `warden_attacks_weak_point` is flank hits.
- **Measured** (score-70 bot, seeds 1-20 per row, the standard party at tier: `--raid-profile=3 --raid-fort=pale-bastion`, `--raid-profile=4 --raid-fort=the-stair`; "without" adds `--raid-party-wits=0`; batch from a working-tree snapshot that is sim-identical to 825a752: it differs only in HUD text (`raid_hud.gd`, `WardenLogic.shield_label`, the tells and weak-point label strings in `raid.json`, `tests/test_wardens.gd`); two rows re-run at 825a752 and one (pale-bastion seed 1, wits) at 7cf5bed give byte-identical lines; raw rows in the run's `reports/dungeon/shieldwall-raw.tsv`; fight = wake to the end, median [min-max] s):

  | fort, arm | beaten | died | fight s | hits flanked / glanced / back | damage by the flank role | big undead lost |
  |---|---|---|---|---|---|---|
  | pale-bastion t3, wits | 20/20 | 0 | 73 [57-203] | 36% / 64% / 19% | 58% | 9 of 40 |
  | pale-bastion t3, no wits | 19/20 (1 timeout) | 0 | 138 [94-582] | 30% / 70% / 13% | 0 | 40 of 40 |
  | the-stair t4, wits | 20/20 | 0 | 66 [47-101] | 46% / 54% / 25% | 59% | 5 of 60 |
  | the-stair t4, no wits | 20/20 | 0 | 107 [64-147] | 42% / 58% / 20% | 0 | 51 of 60 |

  The counter shows in who does the damage and who survives, not in the hit count: the two or three flankers land only 7-8% of the hits but, at full damage and ×2.5 in the back, 58-59% of the damage, and they live (without the wits they fight in the crowd at its shield, glance and die to the bash). That halves the t3 fight and cuts the t4 one by 38%. Ordinary undead glance on 54-70% of their hits; the rest flank because the bot raises from the wall's side. Through the shield only 3-12% of the damage lands. The bash struck Relish once in 80 runs (the bot keeps out of the arc), so the risk here is the living, as at the other wardens; whole-run medians 90 s (t3) and 105 s (t4) sit with the other wardens' (P2 108-138 s).
- Reduced-motion parity: `tests/parity_check.sh` identical, and the pale-bastion seed-1 pair (normal vs `--reduced-motion`) gives the same AUTOPILOT_RESULT. The other wardens' smokes (day1 old-sluice, P3 hollow-redoubt, seed 1) are byte-identical before and after.
- Shots (run's `reports/dungeon/`): `dd-shieldwall-tell` (the lit arc and BASH, both wits bigs at its back ringed, FLANKED), `dd-shieldwall-tell-reduced` (same frame, steady arc), `dd-shieldwall-glance` (no-wits party just after the wake: the silhouette clear, GLANCE on the shield, FLANK on the dashed back, the weak point's words on the HUD), `dd-shieldwall-flank` (the two wits bigs posted behind it, FLANKED, the meter's slashed pips), `dd-shieldwall-greyscale`. Taken with the bot (`--raid-autopilot=70 --raid-autopilot-seed=1`) at frames read off `RAID_WARDEN bash ... frame=` (a headless `--shot` run boots the same way and prints them).
- Known limits: the facing counts undead, not their strength (a big is one undead); the bash shove is a 50 px step, not a slide; a flanker in the role ignores the living around it; t4 fights run short (66 s median) because three wits-5 flankers at ×2.5 are strong: `hp_per_tier` or `back_mult` is the knob for the risk pass.

## The Pyre-priest (D-d/D, task 10 part 2)
`warden_pyre_priest.gd` (`RaidPyrePriest`) and `warden_acolyte.gd` (`RaidAcolyte`); rules in `WardenLogic`'s pyre section (`acolyte_count`/`acolyte_posts`, `ward_mult`, `is_snuffer`, `pyre_phase`, `burn_count`/`burn_aim_relish`/`burn_pick`/`relish_spots`/`burn_plan`, `in_burn`, `pile_after_burn`, `pyre_meter`/`pyre_meter_lit`, `pyre_label`, `burn_exit`), knobs in `raid.json wardens.archetypes.pyre_priest` (its `_doc`). Forts: mourners-gate (t3) and whitecross (t4).

- **Acolytes and the ward:** `acolytes_base` 0 + `acolytes_per_tier` 1 x tier acolytes (3 at t3, 4 at t4; `acolyte_hp` 150, `acolyte_radius_px` 12), posted `acolyte_ring_px` 160 behind the priest from the antechamber's gap (the swarm's way in), spread over `acolyte_arc_deg` 110 and kept in the room. They are children of the priest, not `raid.enemies`: no LIVING count, no ledger mass, nothing dropped when they fall. Undead target them like the warden (`RaidWardenRun.target_in` offers the nearest of the priest and its living acolytes), so the swarm, coming in from the front, hits the priest first. While any acolyte lives the priest takes `ward_mult` 0.2 of every hit (a dashed `vei` line from each living acolyte into it; WARDED over it while hits land through the ward).
- **The burn, on the beat:** every `period_beats` it marks burn areas `tell_beats` (1) ahead, fixed for the tell (`tell`): the phase's own area (`areas` 1) on the densest loose essence or unstirred corpse pile within `reach_px` 520 in its room (greedy coverage; a pile weighs `pile_weight` 2 motes; tie to the candidate nearest the priest), plus `areas_per_acolyte` 1 for each living acolyte beyond the first, aimed at Relish while she is in its room and reach (at most `relish_areas_max` 3: one on her, the others `relish_spread_px` 60 round her, the first straight away from the priest). On the beat (`ignite`) every loose mote inside is destroyed (BURNED −N at the area; carried motes are safe), a corpse pile inside loses `pile_burn_frac` 0.5 of its mass (burned away under `pile_min_mass` 0.5; its ×N badge follows), each undead touching an area takes `dmg_unit` 6 and Relish `dmg_relish` 8, once per beat however many areas cover them (death card: "The Pyre-priest's fire"). With nothing to burn and no acolyte fire, no area is lit. Burned essence leaves the field like early decay: the ledger never tracked loose motes, so the result is unchanged in shape.
- **Phases:** phase 1 while any acolyte lives (whatever its hp); phase 2 (EXPOSED banner, no ward) when the last falls; phase 3 at `until_hp_frac` 0.4. Fires every 4 / 3 / 2 beats, radius 72 / 90 / 105 px. A priest whose hp crossed 0.4 while still warded goes straight to phase 3 when exposed.
- **Weak point (power ≥ 6, effect `snuff`):** a big undead whose power meets it kills an acolyte in one blow (SNUFFED, `snuff`, its pips marked as the weak point's). Fighting the priest (its target is the priest or an acolyte) it takes the acolyte-hunting role (`RaidWardenRun.snuff_for`): it goes for the nearest living acolyte, ringed `undead` with a line to it. The standard t3 party's bigs have power 6.0 and 6.5 and the t4's 7-8, so the stock party meets it.
- **Break meter:** 12 pips (`WardenLogic.pyre_meter`): `wardens.pyre_pips_per_acolyte` 2 per acolyte on the right (spent as they fall), its hp's pips on the left notched at the phase-3 gate (t3: 3 + 3 hp, 6 acolyte; t4: 2 + 2 hp, 8 acolyte), a notch between the two. The two are separate bands (`WardenLogic.pyre_pip_lit`, one check for the HUD row and the in-world row): the hp pips `[0, hp_pips)` light as a prefix of its hp share, the acolytes' pips `[hp_pips, n)` as a prefix of the living, so hp lost through the ward never darkens an acolyte's pip. A snuff marks its own acolyte band (`pyre_snuff_pips`). The other wardens' meters are one prefix band through the same `pip_lit`.
- **HUD:** "SNUFFED ×n · took k" (the weak point's words until the first snuff), row 2 "PHASE n/3", "ACOLYTES n/m" (hidden at 0), the fire line from the spec ("warded ×0.2 · 3 fires every 4 beats, 2 at Relish", then "exposed · 1 fire every 3 beats" in `danger`) and "burned n essence" (hidden at 0).
- **Readability:** the silhouette is a tall robe under a hood with a `danger` flame line above it (one band across the robe per phase left; one falls away at each phase), the pyre's matte logs at its feet; acolytes are small hooded glyphs, a matte cross once fallen. A lit area is a `danger` ground circle with flame ticks round its rim (shape as well as colour), filling brighter through the tell; "step off the fire" under the area nearest her the first time; her edge warns while she stands in one. After the beat the areas leave a short after-image and BURNED −N. Reduced motion: the fill is steady, the word FIRE sits in each lit area, the flame does not sway, the after-image is a step.
- **The bot** (`_vs_pyre`; its step-off roll is superseded by the reaction rule, see "The bot's reaction model as built"): while a tell shows it first carries out a mote lying in a lit area when the trip in plus the way out fits before the beat with `burn_safe_beats` 0.35 to spare, else steps off a lit area that covers her to `burn_clear_px` 16 beyond its edge (`WardenLogic.burn_exit`), rolled once per tell with `burn_step_off` 0.8 (a decent player misreads one fire in five, as `dodge` 0.5 is for the Huntsman's lunges). Then the living, then what lies outside the fire in its room; else it waits `pyre_stand_px` 60 beyond the living acolyte nearest her (seen from the priest) and holds a raise until within `pyre_raise_px` 120 of one (unless her carry is full), so the raised undead walk into it; exposed, it waits `pyre_exposed_px` 170 from it. AUTOPILOT_RESULT gets a `pyre` dict for this archetype only (acolytes, `acolyte_kill_s` from the wake, snuffs, `exposed_s`, burns, areas, essence burned, piles and pile mass burned, burn hits on undead, `burn_relish`, `burn_soaked` (the chain spent an ally for her), damage warded and exposed, `relish_min_hp`); `warden_attacks` is burn beats and `warden_attacks_weak_point` snuffs.
- **What the missing counter costs (the risk knobs):** `ward_mult` and `acolyte_hp` (how long a party without power is held in phase 1), `areas_per_acolyte`, `relish_areas_max`, `relish_spread_px` and `dmg_relish` (the fire on Relish while acolytes live), `dmg_unit` and `pile_burn_frac` (the army and the essence it loses), and the bot's `burn_step_off`. Without power the acolytes live until raises reach them, so the fire on her and the burned essence last.
- **Measured** (score-70 bot, seeds 1-20 per row, the standard party at tier: `--raid-profile=3 --raid-fort=mourners-gate`, `--raid-profile=4 --raid-fort=whitecross`; "without" adds `--raid-party-power=5`, one under the threshold: it takes the snuff and the hunting role away but also 1.2-3.6 of each big's damage per hit, since `dmg = 3 + 1.2 x power`; batch from a `git archive` of c478820; raw rows in the run's `reports/dungeon/pyre-raw.tsv`; fight = wake to the end, median [min-max] s; lowest hp is Relish's per run, 0 when she died):

  | fort, arm | beaten | Relish died | fight s | first / last acolyte falls, s after the wake | essence burned | fires on Relish (an ally spent for her) | lowest hp | big undead lost |
  |---|---|---|---|---|---|---|---|---|
  | mourners-gate t3, power | 19/20 | 1 | 102 [58-238] | 6 [1-32] / 8 [2-34] | 1.5 [0-17] | 2 (0) | 26 [0-30] | 11 of 40 |
  | mourners-gate t3, no power | 16/20 (2 timeouts) | 2 | 150 [31-582] | 25 [10-412] / 44 [24-469] (all fell in 14) | 3 [0-21] | 15 (5) | 22 [0-30] | 20 of 40 |
  | whitecross t4, power | 20/20 | 0 | 98 [57-120] | 18 [9-33] / 22 [13-34] | 2.5 [0-14] | 0 (0) | 26 [1-30] | 1 of 60 |
  | whitecross t4, no power | 20/20 | 0 | 155 [89-332] | 41 [21-249] / 79 [34-292] | 6.5 [1-11] | 49 (22) | 6 [2-30] | 5 of 60 |

  The counter shows in how long the priest is warded and how much fire lands on her: with the power bigs the last acolyte falls 8 s (t3) and 22 s (t4) after the wake (medians; 58 of 60 and 80 of 80 acolytes snuffed), so the ward takes 1% of the damage and almost no fire reaches her; without them the acolytes fall only to raises made beside them, 25-79 s in (at t3 six runs never cleared them), the ward eats 25-29% of the damage, the fight runs about half again as long and the fire on her goes from 2 to 15 (t3) and 0 to 49 hits (t4), 22 of which cost an ally. At t4 that leaves her at 6 hp (median) and the chain absorbs the rest, so nobody dies; at t3 two deaths and two timeouts against one death. The two timeouts kept one acolyte alive to the 600 s cap (the ward still on, the priest at 17% and 47%): with the living gone there was too little essence left to raise beside it. The one death with power (seed 15, woken early with 35 mass of living about) and the two without came from the living after the army thinned (at most one fire hit before). Without power more big undead are lost (20 vs 11, 5 vs 1). Whole-run medians 130 s (t3) and 115 s (t4) with power.
- A knob probe (not committed; the same snapshot with `acolyte_hp` 250 and `dmg_relish` 12, seeds 1-10; rows in `reports/dungeon/pyre-probe-raw.tsv`): with power unchanged (10/10 and 10/10 beaten, lowest hp 23 and 26); without, lowest hp 10 at t3 (2 deaths, 1 timeout of 10) and 5 at t4 (no deaths: 11 of its 24 fire hits cost an ally). So `acolyte_hp` and `dmg_relish` move only the no-power arm (`ward_mult` and `relish_areas_max` act the same way by construction: they bite only while acolytes live); at t4 the sacrifice chain is what stands between a burned Relish and death, so `dmg_unit` (the army's attrition) and `burn_step_off` are the levers that turn that into deaths.
- An earlier batch (63a430c; rows in `reports/dungeon/pyre-raw-63a430c.tsv`) read 10/20 beaten and 9 deaths at t3 without power: the bot then held raises while kiting the living out of the room, so its army starved. That was the bot, not the warden; c478820 raises where she is when out of the room or with a foe near, and the table is from it.
- Reduced-motion parity: `tests/parity_check.sh` identical, and the mourners-gate seed-1 pair (normal vs `--reduced-motion`) and the whitecross t4 seed-1 pair give the same AUTOPILOT_RESULT and RAID_RESULT lines. The other wardens' lines (old-sluice day1, hollow-redoubt t3, pale-bastion t3, seed 1) are byte-identical to the pre-task HEAD (ebb74f0).
- Shots (run's `reports/dungeon/`, mourners-gate seed 1, frames read off `RAID_WARDEN` prints of a headless `--shot` run): `dd-pyre-tell` (no power, the first tell: three lit areas, two on Relish who misread it and stands in one, "step off the fire", the ward lines, WARDED, her edge warning), `dd-pyre-tell-reduced` (same frame: steady fill, FIRE in each area), `dd-pyre-greyscale` (same frame), `dd-pyre-burned` (BURNED −4 on the priest's own area after the beat, "burned 4 essence" on the HUD), `dd-pyre-snuffed` (power: SNUFFED over a fallen acolyte, the other power big ringed with its line to the next one, "SNUFFED ×1 · took 2" and the two slashed pips), `dd-pyre-exposed` (the EXPOSED banner, every acolyte a cross, the meter at 6/12 with six slashed pips, PHASE 2/3 "exposed · 1 fire every 3 beats", the fire on a corpse pile).
- Known limits: with nothing on the floor and no acolyte fire, the exposed priest lights nothing (3-10 burn beats a fight), so phases 2-3 press only while essence or corpses lie in reach; a fallback target (her, or the crowd at its feet) is the knob if they should press harder. Acolytes are not living units: no LIVING count, no essence or ding when they fall, and the living ignore them. The bot's step-off chance is a policy knob, not a measured human rate.

## Run length and risk calibration (D-d/E)
Measuring fields only so far: the sim is unchanged (the four seed-1 lines below are byte-identical apart from the new keys).

- **New AUTOPILOT_RESULT keys** (read off the run each physics tick in `RaidAutopilot._split_tick` / `_engaged`, written in `on_finish`; never fed back into a decision, and the tests guard that those bodies touch no rng, goal or routing state):
  - `split` {`travel_s`, `fight_s`, `trance_s`, `idle_s`}: scene seconds per bucket; they sum to `duration_s` (to the 0.01 rounding).
  - `frames_drawn` (`Engine.get_process_frames()`) and `physics_frames` (`Engine.get_physics_frames()`) when the line prints, `frames_at_start` (both counters at `start()`: 0 and 0, the scene builds on the first frame), `run_ticks` (the live physics ticks the bot counted, = `duration_s` x 60; the rest of the frames are the end beat, e.g. 90 for the 1.5 s victory beat).
  - `walk_px` (how far Relish walked in all), `walk_travel_px` (of it, in travel ticks), `route_px` (the shortest walk the bot's own routing takes from the spawn to the warden room's centre: the BFS room path through the nearest gap of each pair), `rooms_entered` (room changes, counted on think ticks; kiting through a doorway counts each crossing).
  - `killed_by`: `Relish.last_hit_src` when she died (`slam`, `lunge`, `bash`, `fire`, `living`; `wound` when nothing named it), else "". The death card's KILLED BY reads the same source.
  - The boss bot's line (`BOSS_AUTOPLAY`, `boss_autopilot.gd`) has no frame counters: that file is outside this task.
- **The time split** (`RaidLogic.time_class`, `RaidLogic.foe_engaged`; tests `raid_time_split`). Each live physics tick (1/60 s of scene time, from the build to the death or the chest; the end beats are not in `duration_s`) goes to the first bucket that matches:
  1. **trance**: the trance is open (`RaidTrance.State.ACTIVE`). The bot never opens it: `bot_raise_cooldown` raises at once without entering it, so the bot's trance share is 0 by construction. A player's trace time belongs in the bot-to-human factor, not here.
  2. **fight**: something is engaged. The warden from its wake while it lives, wherever Relish stands (standing off a slam, waiting out a tell or fetching motes in its room is its fight; its acolytes come with it), or a hostile living foe (aggro'd: it never calms) in her room (a doorway band is no room) or within `combat.aggro_px` (260) of her through any wall. Kiting, holding while the army fights and stepping off a fire are fight.
  3. **travel**: nothing engaged and Relish moved more than `SPLIT_MOVE_PX` (1 px) this tick (she walks 4 px a tick): walking the route, collecting motes and piles with no foe engaged, fetching pickups, walking to the chest after the kill.
  4. **idle**: none of these: standing with nothing engaged (holding back while calm living stand in the next room, waiting on the cooldown, the stall before the bot gives up).
  So the levers Step 3 may use (more fights, warden phases, guarded loot) land in fight; corridor length lands in travel and waits in idle. Walking through a room that holds any hostile living is fight too, so a grown room could hide walking inside fight: report `walk_px - walk_travel_px` (the walk inside fight) beside the shares. In the pilot it is 57-95% of all walking (median per tier).
- **Lockstep** (the determinism gate). In every normal run `physics_frames` is `frames_drawn` + 1 (the line prints from a process callback after that frame's physics step; the 4 seed-1 lines and all 42 pilot runs). A run that ends inside a physics tick shows 1 as well: two timeouts at 600 s (mourners-gate, no power, seeds 8 and 12), whose lines are otherwise identical to their c478820 rows in `pyre-raw.tsv`. A run is **in lockstep** when `physics_frames - frames_drawn` is 0 or 1; any other value means process frames and physics ticks fell out of step (mote drift, corpse piles and the trance cooldown advance in `_process`), and the run is excluded from every table and listed as an outlier.
- **Determinism watch.** The Pyre-priest's burn (`RaidPyrePriest._ignite`, `_mark_areas`) reads mote positions and `carried` flags that `essence_orb._process` advances (drift, absorb, the carry slots). That is deterministic under `--fixed-fps 60` (a process frame per physics tick: the lockstep rule above) but depends on frame pacing in live play: a hitch moves a mote a different distance between two ticks, so which motes a fire catches can differ from run to run. Nothing in the bot's lines depends on it; a human's run will, a little.
- **Bot dict snapshots** (D-d/F). The `shield` and `pyre` dicts of AUTOPILOT_RESULT are read off the warden at each think tick (before that frame's warden and unit physics), once more in `RaidWardenRun.on_warden_died` before it lets go of the warden (via `RaidDev.on_warden_died` to `RaidAutopilot.on_warden_died`), and again in `on_finish` while the warden is still there (Relish died, timeout). So the killing blow (`hits`, `flanks`, `dmg_*`) and the burn or bash that kills Relish (`burn_relish`, `bash_relish`) are in them. The older `_attacks` and `_attacks_wp` counters (`warden_attacks`, `warden_attacks_weak_point`, `catches`) are still the think tick's snapshot and miss the last event; they feed every fort's line, so they stay as they are.
- **Byte identity** (f77f8a9 vs f77f8a9 + these fields, seed 1, score 70, each from a `git archive` snapshot): `--raid-fixture=day1,old-sluice`, `--raid-profile=3 --raid-fort=hollow-redoubt`, `pale-bastion`, `mourners-gate`: AUTOPILOT_RESULT identical once the new keys are dropped (text and parsed), and every `RAID_WARDEN` (with its `frame=`), `RAID_RESULT` and `RAID_TELEMETRY` line identical. `tests/parity_check.sh` identical.
- **Pilot** ("pilot, pre-fix, f77f8a9 + instrumentation": a `git archive` of 9b6442d, score 70, seeds 1-3, every fort at its tier with its tier's party profile, plus the first dungeon by `--raid-fixture=day1,old-sluice`; 39 runs and 3 re-runs, rows in the run's `reports/dungeon/calibration-dd-pilot.tsv`, runner `calibration-dd-run.py`). All 42 in lockstep. Three runs ran past 2x their fort's median: old-sluice (party 1) seed 1 at 272 s, mourners-gate seed 1 at 261 s, chime-fort seed 2 at 220 s; each re-run gave a byte-identical line, so they are the sim's own spread, not the machine. They are kept out of the table (with them: t1 106, t2 128, t3 113 s). Medians in scene seconds; shares pooled over the runs:

  | row | runs | median s [min-max] | travel / fight / trance / idle % | beaten | died | raises |
  |---|---|---|---|---|---|---|
  | P1 first dungeon | 3 | 115 [106-120] | 3 / 89 / 0 / 8 | 3 | 0 | 18 |
  | t1 | 8 | 106 [40-133] | 4 / 93 / 0 / 3 | 7 | 1 (greywall seed 3, the living, 40 s, before the wake) | 16 |
  | t2 | 8 | 124 [54-216] | 5 / 91 / 0 / 4 | 8 | 0 | 17 |
  | t3 | 8 | 104 [78-165] | 9 / 83 / 0 / 7 | 8 | 0 | 11 |
  | t4 | 9 | 126 [79-282] | 12 / 83 / 0 / 5 | 9 | 0 | 14 |
  | Bellringer at tier (t2, t4) | 9 | 156 [118-282] | 5 / 92 / 0 / 3 | 9 | 0 | 20 |
  | Huntsman at tier (t2, t3) | 5 | 82 [54-95] | 13 / 72 / 0 / 15 | 5 | 0 | 10 |
  | Shieldwall at tier (t3, t4) | 6 | 134 [78-165] | 13 / 80 / 0 / 8 | 6 | 0 | 17 |
  | Pyre-priest at tier (t3, t4) | 5 | 113 [79-130] | 11 / 86 / 0 / 3 | 5 | 0 | 7 |

  Fight is most of every run because the bot waits for its army in rooms with hostile living, and the warden fight counts whole. The deep tiers travel more (t4 12%: bigger layouts). Wall clock 11.7 s per run (median; 5.6-21.9), 10x scene speed, three at once with the machine's 1-min load at 1.7-3.7 on 12 cores.
- **The bot's reaction model, as it is** (f77f8a9; read, not changed). The bot thinks every `think_frames` 3 physics frames (50 ms) and reads the warden's state, not the screen. Relish walks 240 px/s. Every tell lasts `tell_beats` 1 beat (1.714 s, `pulse.json tempo_ms`).

  | threat | what it reads | when it reacts | margin | not answered | depends on score |
  |---|---|---|---|---|---|
  | Bellringer slam | the beat clock (`_next_attack`, `beat()`): beats until the next tell | before the tell. It goes in for motes only when the trip in and back out fits before the tell with `slam_safe_beats` 1 beat to spare (`WardenLogic.slam_window_open`); otherwise it stays outside | 302 px from the bell (reach 260 + half the band + `bell_margin_px` 24), waiting `bell_stage_px` 20 beyond | never | no |
  | Huntsman lunge | `_locked` (the tell) and `_lock_pt` | the next think, 50 ms or less | 49 px off the line (22 + 13 + 14) plus `dodge_step_px` 60: 0.2 s of walking | `dodge` 0.5: half the tells, rolled once per tell | no |
  | Shieldwall bash | the facing and the arc every think, tell or not | always: it never stands in the arc | the arc grown by `wall_margin_deg` 15 and `wall_margin_px` 30 (183 px) | never | no |
  | Pyre-priest fire | `lit` and the areas (fixed for the tell) | the next think | `burn_clear_px` 16 beyond the area's edge (up to 134 px from its centre, 0.56 s) | 1 - `burn_step_off` = 0.2, rolled once per tell | no |
  | the living | every living foe in her room, every think | the next think | kites at `kite_px` 240 (110 after `stall_s` 20 s held in one room) and holds at `hold_px` 200. It ignores a foe behind a wall and outruns them all (spearman 95, runner 175, brute 70 px/s) | never | no |

  The score is read in one place: `_trace_for` searches the trace jitter until the grade lands within `score_tol` 5 of it. So it sets the raise's class and count and nothing about dodging. Two of the four wardens have no delay and no miss at all, and the Bellringer's reaction is effectively negative: the bot leaves before the tell starts. That is why the bash struck Relish once in 80 runs.
- **Proposed score tie** (built as proposed: see "The bot's reaction model as built" below). One rule for every warden tell: per tell, a **miss** chance `m` (the tell is not answered: she keeps doing what she was doing) and a **reaction delay** `d` (an answered tell is acted on `d` after it starts), both set by the target score:

  | score | m (tells missed) | d (s) | answered |
  |---|---|---|---|
  | 50 | 0.30 | 0.60 | 0.70 |
  | 70 | 0.18 | 0.45 | 0.82 |
  | 90 | 0.08 | 0.30 | 0.92 |

  Between those points both are linear in the score.
  - Basis for `d`: a choice reaction to a visual cue is about 0.35-0.5 s in the lab (Hick-Hyman, two to four choices), plus 0.1-0.2 s for a cue at the edge of the screen and a mouse move. Against a 1.714 s tell, 0.45 s still leaves 1.26 s, or 300 px of walking. That covers the lunge (49 px), any fire (134 px) and the Shieldwall's arc. So `d` rarely decides a hit, and misses are about attention, not speed.
  - Basis for `m`: a lapse of about 0.05 (a tell at the edge of the screen while she watches the army or the motes), plus the share of fight time a player's eyes are on the circle. From the pilot that share is 0.09-0.23: raises after the wake times (0.35 x a 1.5-2.5 s trace + 0.3-0.7 s of aiming) over the fight's scene seconds. Assume about 0.7 of the tells that start during a trace go unanswered. This is an assumption, not a measurement: after the trace the tell still has 0.8-1.7 s of scene time, which after `d` is 84-300 px of walking. That is plenty for the lunge (49 px), so 0.7 is too high there, and about right for a deep exit from the bell (up to 302 px). That gives 0.11-0.21. 0.18 sits in the upper half, next to the 0.2 the Pyre-priest's step-off already uses, so that fight barely moves. A score-50 player draws longer and redraws more (0.30); a score-90 player is quick on both (0.08).
  - What it changes against today, per warden:
    - Bellringer: it keeps counting beats to go in (a player can count four beats), but with `slam_safe_beats` cut to about 0.25 beat, so the tell can find her inside. The exit becomes the tell's answer, with `m` and `d`.
    - Shieldwall: it avoids the arc only while a bash tell shows (`m` and `d`), so between tells it may stand in front. It keeps the side stand as where it prefers to wait.
    - Huntsman: `dodge` goes from 0.5 to 1 - `m` = 0.82, and the step starts `d` after the lock. At score 70 this fight gets easier for the bot. The 0.5 had no stated basis.
    - Pyre-priest: `burn_step_off` goes from 0.8 to 0.82, and the step starts `d` after the tell.
    - The living: the kite starts `d` after a foe comes within `kite_px`, with no miss chance (it is not a one-beat tell).
  - The context runs ("0.6 and 1.0 of its score-70 value") then answer 0.49 and 0.82 of the tells.
- **The bot's reaction model as built** (D-d/E1b; frozen from here on: Steps 3-4 move only game knobs).
  - **One rule** (`RaidAutopilot._answers`, the one place every warden tell goes through). The first think that sees a tell rolls once whether she answers it: chance 1 - `_miss`, from `_rng_react`, a stream of its own (seed ^ 0x5EAC7105). She acts on it `_delay` scene seconds after that first sight. Until then, and all through a missed tell, she does what she would do with no tell.
  - **The knobs** (`raid.json autopilot`): `react_score` [50, 70, 90], `react_miss` [0.30, 0.18, 0.08] and `react_delay_s` [0.60, 0.45, 0.30], linear in the target score between the points and clamped outside (`RaidLogic.react_at`, tested). The basis is the proposal above and the section's `_doc`. `dodge` and `burn_step_off` are gone. The trace (`_trace_for`, ring quality) is unchanged and is the only draw left on `_rng`, so the Bellringer and Shieldwall forts (which rolled nothing before) keep their trace draws; at the Huntsman and Pyre-priest forts the trace draws no longer interleave with tell rolls.
  - **Per warden:**
    - **Bellringer:** the beat count says when to go in. The trip in and back out must fit before the next tell with `slam_safe_beats` 0.25 (was 1.0) to spare. Inside she works until she answers a slam tell (or a slam ring is out, in plain sight: no roll): on to the point she was making for, else the motes in reach, else she holds. Then she leaves. The exit is the tell's answer, not the beat count.
    - **Shieldwall:** the bash arc (with `wall_margin_*`) is kept clear only while she answers a bash tell. Between tells she fetches what lies in its room, the arc included, and otherwise waits at the side stand as before.
    - **Huntsman:** the sidestep happens on an answered lunge tell, `_delay` after the lock. Its side when nothing else decides is rolled with the tell.
    - **Pyre-priest:** the step-off, the mote carried out of a lit area and the keep-out of lit areas happen only on an answered fire tell, `_delay` after it lights.
    - **Fixed after the freeze (D-d/E Step 4b, b1233c4; the manager's ruling "missed has to mean missed").**
      - **The bug.** A missed Shieldwall tell still fed the tell's facing, arc and reach to her stand (`_wall_stand` reads them), so she dodged a tell she had missed. A missed slam's ring was still fled once it was out.
      - **The fix.** From a missed tell until it strikes, the bot plans against the state from before it (`_wall_pre`), and does not react to a missed slam until its ring has passed.
      - **Unchanged:** answered tells, m and d, and the Bellringer's beat-clock trips. A human learns the beat too.
      - It is a bug in how the frozen model was built, not a new policy. It is revertible on its own.
      - New tell geometry is answered through the same roll: the toll (fa42e59) is answered by stepping out of its ring, and the aimed lane by the existing step out of the lit arc.
    - **The living:** no miss (no one-beat tell). The kite starts `_delay` after a living foe in her room first comes within `kite_px` (`_watch_threat`, `_kite_due`); until then her old goal stands (`kite-wait`). A foe that steps out of `kite_px` and back within `_delay` is the same threat, so there is no fresh delay at the kite's edge. The first build re-armed there: at greywall t1 seed 3 it re-armed 12 times in 21 s.
  - **Measuring:** AUTOPILOT_RESULT gains `react` {`miss`, `delay_s`, `tells` seen, `answered`}. DEV `--raid-autopilot-answer-mult=<x>` scales the answered chance, for the context runs at 0.6 and 1.0; it replaces `--raid-autopilot-dodge`. The boss bot (`boss_autopilot.gd`, `vei.json autopilot.dodge`) is untouched.
  - **The seed-1 lines move** (548098e, then with the rule as it now stands; score 70; scene s; raises; Relish's hp at the end; allies at the end; warden tells answered of seen):

    | run | before | after | why |
    |---|---|---|---|
    | old-sluice day1 (Bellringer) | 105.5 s, 17 raises, hp 30, 17 allies | 98.1 s, 17 raises, hp 30, 23 allies; 11 of 12 tells | she now stays inside working until she answers each tell, so raises and positions shift. The one miss struck nothing |
    | hollow-redoubt t3 (Huntsman) | 82.2 s, 10 raises, hp 26, 27 allies | 74.5 s, 9 raises, hp 30, 32 allies; 3 of 4 | 0.82 of the lunges answered against 0.5 before, and its trace draws no longer interleave with dodge rolls |
    | pale-bastion t3 (Shieldwall) | 77.7 s, 12 raises, hp 30, 12 allies | 85.8 s, 12 raises, hp 30, 25 allies; 13 of 14 | she no longer keeps out of the arc between bashes, so she stands and fetches elsewhere. No bash struck her |
    | mourners-gate t3 (Pyre-priest) | 261.3 s, 10 raises, hp 30, 13 allies | 151.8 s, 11 raises, hp 30, 19 allies; 4 of 5 | the fire keep-out, the step-off and the mote grab happen only on answered tells, and the trace draws no longer interleave. This seed's 261 s outlier is gone |

    `tests/parity_check.sh` gives identical results (all five checks).
- **Bot-to-human factor, first draft** (real seconds added to the bot's scene seconds; outside the trance scene time is real time). Measured from the pilot:
  - Raises per run: 18 (P1), 16 (t1), 17 (t2), 11 (t3), 14 (t4). In the fights, a raise every 7-9 scene seconds after the wake, near the 6 s cooldown: the bot raises the moment the trance is ready.
  - The bot's trace time per raise is 0. It never opens the trance: `bot_raise_cooldown` raises in one think, and the cooldown starts at once.
  - Its walk in travel ticks is 0.85-2.3x `route_px` (median per tier: P1 0.85, t2 1.28, t3 1.67, t4 2.31). That walk includes the mote and pickup trips and the walk to the chest. Its whole walk is 1.7-18x the route (kiting, dodging, the warden fight).
  - `rooms_entered` 5-41 (median per tier), inflated by kiting back and forth through a doorway. The layouts have at least 2 + tier rooms. Tells per fight minute: 7-13.

  The model: human = bot scene seconds + raises x `c` + travel seconds x `r` + (2 + tier) rooms x `h` + tells x `k`.
  - `c` per raise, 1.0-3.5 s. A comfortable ring traced in 1.5-2.5 s of real time, inside the trance (`time_scale` 0.35, focus 4 s real), and the cooldown starts only when the trance closes. Since the fights raise about as often as the cooldown allows, the trace adds almost in full. Low: 1.5 s x (1 - 0.35), the scene still runs at 0.35 during it. High: 2.5 s, plus 0.5 s aiming before the trance, plus 0.5 s starting late after READY.
  - `r`, 0.10-0.30: click-to-move detours and hesitation on the travel seconds.
  - `h`, 1-3 s per room on first entry: looking, choosing to push or wait, where to stand.
  - `k`, 0-0.4 s per warden tell (`warden_attacks`): the pause or step a player makes on a tell that the bot makes in its own scene time anyway (low 0), or the beat a player loses re-aiming after it (high).
  - Not in it: retried circles (the 1 s lockout and a redraw; part of the high end), and the warden fight's own hesitation (the reaction model above covers its risk, not its time).
  - Factor (t2-t4 pooled, median per run): **1.18-1.65**. Human estimate per tier (median per run): P1 137-194 s (2.3-3.2 min), t1 2.1-3.0 min, t2 2.4-3.4 min, t3 2.0-2.6 min, t4 2.5-3.4 min. Per warden at tier: Bellringer 3.1-4.3, Shieldwall 2.6-3.7, Pyre-priest 2.1-2.5, Huntsman 1.6-2.3 min. So at f77f8a9 tiers 2-4 land below or at the bottom of the 3-6 min target, and only the Bellringer's forts reach it.
- **Baseline** (iter `base`: a `git archive` of 5b70259, i.e. the review fixes at 548098e plus the reaction rule as frozen; the pilot's set: score 70, seeds 1-3, every fort at its tier with its tier's party, plus the first dungeon by `--raid-fixture=day1,old-sluice`; rows in the run's `reports/dungeon/calibration-dd-raw.tsv`; the rows of a first baseline at 4a89a8d, before the kite fix, are kept there as `base-4a89a8d`). **This is today's split**: Steps 3-4 may not raise a tier's travel or idle share above it.
  - All 41 runs are in lockstep. Two outliers, each re-run byte-identical, are kept out: chime-fort seed 2 (282 s) and sable-hold seed 2 (338 s).
  - 0.80 of the warden tells were answered (264 of 328 at t2-t4). There were no deaths at t2-t4, but Relish ended runs at 3-14 hp.
  - Medians in scene seconds; "walk in fight" is the median `walk_px - walk_travel_px`; the pilot's value is in brackets:

  | row | runs | median s | travel / fight / trance / idle % | walk in fight px | beaten | died (killed by) |
  |---|---|---|---|---|---|---|
  | P1 first dungeon | 3 | 98 (115) | 3 / 88 / 0 / 9 (3 / 89 / 0 / 8) | 4100 (948) | 3 | 0 |
  | t1 | 9 | 103 (106) | 3 / 93 / 0 / 3 (4 / 93 / 0 / 3) | 3968 | 7 | 2 (living, at 12 s and 17 s) |
  | t2 | 8 | 103 (124) | 4 / 91 / 0 / 5 (5 / 91 / 0 / 4) | 5710 (2988) | 8 | 0 |
  | t3 | 9 | 121 (104) | 9 / 82 / 0 / 9 (9 / 83 / 0 / 7) | 10812 (9506) | 9 | 0 |
  | t4 | 8 | 125 (126) | 15 / 80 / 0 / 5 (12 / 83 / 0 / 5) | 9524 (8944) | 8 | 0 |
  | Bellringer at tier | 8 | 124 (156) | 4 / 94 / 0 / 2 | 5942 | 8 | 0 |
  | Huntsman at tier | 5 | 78 (82) | 10 / 71 / 0 / 18 | 8802 | 5 | 0 |
  | Shieldwall at tier | 6 | 110 (134) | 14 / 77 / 0 / 8 | 12316 | 6 | 0 |
  | Pyre-priest at tier | 6 | 119 (113) | 12 / 86 / 0 / 2 | 5644 | 6 | 0 |

  - Against the tier median the t2 Huntsman (chime-fort, 2 runs) is -35%; every other archetype at its tier is within 17%.
  - At n = 3 per fort these medians are noisy: the same set at 4a89a8d gave the t3 Huntsman 79 s and t4 149 s, against 137 s and 125 s here. The Step 3 checks should use seeds 1-6 per fort.
  - Time before the wake is 19-25 s per tier; the warden fight (wake to end) is 84 / 83 / 106 s at t2 / t3 / t4.
  - The two t1 deaths are new against the pilot's one. ashgate seed 3: she walked round a corner into four living after loot, kept walking for the 0.45 s delay (8 hp), kited into the Huntsman's room, woke it and was cornered there. greywall seed 3 died at 17 s before any wake; it also dies with no delay (at 40 s, as in the pilot).
  - **Human factor at this head:** 1.18-1.67 (t2-t4 pooled, median per run; t3 1.14-1.48, with few raises at the Pyre-priest). Human estimate: t2 2.0-2.9 min, t3 2.3-3.1, t4 2.4-3.2, P1 2.0-2.9.
  - **The run-length window:** the check at each step is the median per-run human estimate per tier: low at least 180 s, high at most 360 s. In bot seconds at today's factors that is about 151-211 s at t2, 158-243 s at t3 and 154-224 s at t4 (pooled 153-216 s). Today all three tiers sit 30-50 s under its floor.

## Run length, Step 3 (D-d/E): the levers
The window: at t2-t4 the median per-run human estimate (bot-to-human factor above) must be at least 180 s at its low end and at most 360 s at its high end. No archetype at tier may be more than about 30% off its tier's median. Travel and idle shares may not rise above the seeds 1-6 baseline at 5b70259 (t2 5.3 / 5.1 %, t3 10.5 / 7.5 %, t4 16.0 / 6.5 %; medians 101 / 115 / 117 s; human estimate 119-171 / 132-170 / 136-187 s; P1 100 s, 119-172 s; t1 106 s, 126-183 s, 3 of 18 died).
  - **The convention:** shares are pooled seconds over the runs, with outliers (more than 2x their fort's median, the E brief's rule) left out. That removes one run at t2 and one at t4. With every row the ceilings would read t2 4.8 / 5.4 % and t4 14.1 / 5.7 %; t3 is the same either way. Per-run medians give a third set of numbers. Claims such as "idle fell at every tier" hold under this convention.
  - **The routing fix alone** (5b70259 plus `_real_gaps`, seeds 1-6 at t2-t4, iter `rg`) gives every line byte-identical to the baseline. The two baseline outliers (chime-fort seed 2 and sable-hold seed 2, long fights) were not the T-junction stall, and the fix moves no share. Tier 1 and the first dungeon stay as they are. The calibration log is the run's `reports/dungeon/calibration-dd-log.txt`.

- **More living on the approach: measured and dropped.**
  - The probe: 2 groups of 4 living at t2-t4, laid past each gap of the path within aggro range, sharing the seed's living mass. The patch is kept as `reports/dungeon/calibration-dd-approach-groups.patch`.
  - Runs got shorter, not longer (t2-t4 medians 106 / 121 / 131 → 94 / 85 / 96 s). The wake came 2-7 s later, but the warden fight fell 16-38 s.
  - The mechanism: every living death drops a mote, and every mote is part of a raise. A fight before the wake therefore grows the army, which then shortens the warden fight. The same 8 living taken out of the fort's count gave no lengthening either.
  - The finding gives the rule for the levers below: **a warden's own pack drops nothing.**
- **The Huntsman's hunt** (`archetypes.huntsman.pack`, `WardenLogic.pack_*`, `RaidWarden._pack_step`; the mechanic is in the base warden so another warden can take a pack by config).
  - **Tell.** At each hp gate in `at_hp_frac` (0.66, 0.33), from `min_tier` 2 (never tier 1 or the first dungeon: their spec has no `pack` key, so their lines are unchanged), it sounds a horn `horn_beats` (1) ahead, on the beat.
    - World: HORN · n hounds over it, and a `danger` ring closing on each entry point. Under reduced motion the ring is steady at its final size.
    - HUD: a pack row saying "HORN · n hounds coming". RAID_WARDEN prints `horn`, `pack` and `pack down` with `frame=`.
  - **The pack.** `size_by_tier` hounds (5 at t2, 6 at t3, 7 at t4: provisional, see the calibration) come in at the two inset corners of its room farthest from Relish (`pack_spots`; no rng).
    - Hounds are `enemies.hound` (30 hp, 4 dmg, 150 px/s): hostile at once and massless.
    - They count in LIVING. They drop no motes and no dings (`RaidUnit.warden_pack`, `raid.on_unit_died`).
  - **Ward and hold.** While any hound runs:
    - The Huntsman takes `ward_mult` 0.25 of every hit (`WardenLogic.pack_ward`, in `RaidWarden.take_hit`). A stun's ×2.5 multiplies with it, giving ×0.625.
    - It does not lunge (one threat at a time: a pending lunge tell is dropped at the horn). After the last hound falls it waits a full tell before the next lunge.
    - A warden without a pack takes exactly ×1.0, so the other wardens' lines are byte-identical.
  - **The counter** is the speed weak point's bodyguard role, which already exists: a fast big undead posted by Relish strikes whatever comes into reach, so the hounds that rush her meet it first. Without fast bigs they reach her, which is the Step 4 arm's mechanism. The army's raises also answer the horn: the entry points show a beat ahead.
  - **Labelled result.**
    - While the hounds run: HOUNDS · WARDED over it, and HUD "HOUNDS n of m · it takes ×0.25".
    - After the last falls: HOUNDS DOWN in `undead` for `wardens.pack_label_s` 1.2 s.
    - Between packs the row teaches: "at 2/3 and 1/3 of its strength it calls n hounds · it is warded while they run".
    - Its break meter, a flat row before, is now notched at the gates (`WardenLogic.meter_bands`).
    - The death card names "The Huntsman's hounds" (`last_hit_src` "hound").
  - **The bot** does not answer the horn: the hounds are living, and it kites them with its reaction delay as it does any living. AUTOPILOT_RESULT gains `pack` {horns, called, down, pack_s} on lines whose warden has a pack, and `living_start` on every line.
  - **Probe** (seeds 1-6 at chime-fort t2 and hollow-redoubt t3).
    - Each pack stands about 17-20 s (`pack_s` 34-40 per fight), and the fights ran 33-50 s longer (chime-fort 56-78 → 90-128 s; hollow-redoubt 74-85 → 116-153 s in the runs she survived).
    - Hounds killed Relish in 3 of 12 runs. That is a Step 4 risk to tune, not tuned here.
    - Every other warden's line, and tier 1 and the first dungeon, are byte-identical without the new keys.
  - **Shot:** `de-huntsman-hounds.png` (chime-fort t2, seed 1, frame 2830). It shows the first pack just loosed, HOUNDS · WARDED over the Huntsman inside its army, the HUD row "HOUNDS 5 of 5 · it takes ×0.25", and the meter notched at 2/3 and 1/3.
- **The guarded detour** (`raid.json detour`, `loot.json cache`, `LayoutLogic.detour_site` / `detour_guard`, `RaidPopulate`; tests `raid_detour`).
  - **Placement.** From `min_tier` 2 (never tier 1, the first dungeon or a held fort), the cache lies in a side room.
    - The room is off the shortest path from the spawn to the warden room and opens onto a path room that is not the warden's (a real opening, not just touching rects).
    - A normal room is preferred to a checkpoint, because loot would bank there and change what is at risk.
    - **At lantern-keep and pale-bastion the cache room is a checkpoint.** lantern-keep has no other room off its path. pale-bastion's other side room (3, normal) opens only through that checkpoint, so going there would cross it anyway and add a walk the travel guard counts.
    - What that does to risk: walking into the cache room banks what she already carries. The cache itself banks when she walks back into the spawn room, which is a checkpoint at every fort and borders the cache room at 8 of 9 forts (mourners-gate's borders the antechamber). So at every fort the cache is at risk only during the guard's fight and the walk out, checkpoint room or not.
    - The cache sits `cache_door_px` 320 into the room from that opening, deep enough that the army passing the door does not wake the guard.
  - **Contents.** `loot.json cache.relics_by_tier` relic pickups (1 / 1 / 2 at t2 / t3 / t4). The count is fixed, with no roll, so the chest's and the dings' rolls are untouched. They are fetched by walking over them like any floor loot: found loot, lost on a death before it is banked.
  - **The guard.** `guard_by_tier` (4 / 5 / 6) living of the tier's mix, within `guard_spread_px` 50 of the cache.
    - They come out of the fort's own count, so the run has the same bodies, mass and motes; only their place changes.
    - The cache draws a wider dashed `vei` ring and the word CACHE (shape as well as colour; no motion of its own). The loot pointer already points at it.
  - **The bot's first rule** (Step 3, f1bf38e; replaced in 3b, see "The detour rule" below).
    - **When:** once, at her first think in the antechamber before the wake. In s3a that fell at 2.0-16.7 s (t2), 2.1-33.3 s (t3) and 3.6-59.8 s (t4).
    - **Take it when:** her hp is at least `detour_hp_frac` 0.6 of its most, and her army is at least `detour_army_mult` 2 × the guard still standing.
    - **Abandon:** if her hp falls below `detour_abandon_hp_frac` 0.3.
    - **Basis:** a decent player pushes for a side cache when healthy and with an army that wins that fight cleanly, and backs off when one or two more hits would kill her.
    - **Once taken:** the cache room is her goal, and its guard does not hold her at its door (a push: they turn hostile as she and the army come in). She is done when the cache is hers.
  - AUTOPILOT_RESULT `detour` {room, guard, offered, taken, done, abandoned, at {t, hp_frac, army, guard}, done_s, cache, cache_left} on lines with a cache. `AUTOPILOT_DETOUR <taken|declined> ... frame=` prints the decision.
  - The human factor counts a taken detour as one more room.
- **A bot routing fix that the detour exposed** (`RaidAutopilot._real_gaps`).
  - The problem: `_toward_room` walked to the nearest gap whose grown rect touched both rooms, then toward the far room's centre. A gap at a T-junction can touch both rooms and still open elsewhere, so at chime-fort the bot went back and forth between such a gap and the far room's centre until it gave up (3 of 3 seeds retreated).
  - The fix: it now uses only the gaps within half a gap's width of one of the layout's portals for the pair. It keeps every gap when the layout has none.
  - This is a pathing bug, not a reaction knob. Tier 1 and the first dungeon are byte-identical with it.
- **Shot:** `de-detour.png` (chime-fort t2, seed 1, frame 640). It shows the guarded CACHE in the side room with its four living, the loot pointer running to it, and Relish's army on its way across after she took it at frame 317 (hp 1.0, army 9 against a guard of 4).
- **Packs on the other wardens** (the same `RaidWarden._pack_step`, config only plus a hold in each `_step`).
  - **The packs:**
    - The Bellringer's ringers (`enemies.ringer`) at 2/3 and 1/3.
    - The Shieldwall's bearers (`enemies.bearer`: 40 hp, 110 px/s) at 2/3 and 1/3. On both of these the gates sit on the phase notches, so the meter is unchanged.
    - The Pyre-priest's zealots (`enemies.zealot`) at its phase-3 notch, since its acolytes already ward the start of its fight. The zealots' ward multiplies with the acolytes'.
  - **Hold.** While a pack runs, each warden holds its own attack: no slam, bash or fire tell until a beat after the last of the pack falls.
  - **Counter.** These packs have no stat counter: the counter is the army, raised where the horn shows a beat ahead. That matters for Step 4's counter rule, which these packs do not touch.
  - **Death card:** "The Bellringer's pack" (`last_hit_src` "pack").
  - **Probe** (seeds 1-3, provisional sizes 5 / 6 / 7, with the hunt and the detour).
    - Medians: t2 183, t3 127, t4 139 s. Human estimate: t2 216-304, t3 152-214, t4 165-219 s.
    - Packs stand 12-48 s a fight.
    - Deaths: 1 / 2 / 2 of 9 per tier (packs 3, hounds 1, the living 1).
    - Tier 1 and the first dungeon are byte-identical.
- **The Step 3 numbers** (iter `s3a`, seeds 1-6 at every t2-t4 fort, 54 runs, all in lockstep, none past 2x its fort's median). The pack sizes are set per warden (`size_by_tier`, t2 / t3 / t4): hounds 8 / 8 (t4 unused: no t4 Huntsman fort), ringers 4 / 6 / 8, bearers 6 / 9 / 10, zealots 6 / 6 / 12. The detour guard is 4 / 5 / 6. Medians in scene s; the human estimate is the median per-run low-high; seeds 1-6 baseline at 5b70259 → now:

  | tier | median s | travel / fight / trance / idle % | walk in fight px | human estimate s | Relish died |
  |---|---|---|---|---|---|
  | t2 | 101 → 134 | 5.3 / 89.6 / 0 / 5.1 → 5.5 / 92.4 / 0 / 2.1 | 5964 → 13870 | 119-171 → **157-219** | 0 → 0 of 18 |
  | t3 | 115 → 153 | 10.5 / 82.0 / 0 / 7.5 → 10.0 / 85.8 / 0 / 4.1 | 8468 → 14324 | 132-170 → **182-236** | 0 → 6 of 18 |
  | t4 | 117 → 142 | 16.0 / 77.5 / 0 / 6.5 → 9.0 / 84.6 / 0 / 6.4 | 8100 → 15098 | 136-187 → **166-219** | 0 → 8 of 18 |

  - **The window.**
    - t3 is in it.
    - t2 and t4 reach 87% and 92% of its floor (180 s at the low end); the high end is well inside 360 s.
    - Tier 1 and the first dungeon are unchanged (P1 100 s, human 119-172 s).
  - **The guard.** Idle fell at every tier and travel at t3 and t4. At t2 travel is 5.5% against 5.3%: the detour's walk where the guard has already fallen. This is a breach of 0.2 points.
  - **Per warden at tier** (the tier median in brackets):
    - t2: Bellringer 182 (+36%), Huntsman 101 (-25%) [134]. The Bellringer is outside the 30% rule.
    - t3: Huntsman 122 (-20%), Pyre-priest 187 (+22%), Shieldwall 180 (+18%) [153].
    - t4: Bellringer 173 (+22%), Pyre-priest 106 (-25%), Shieldwall 143 (+1%) [142].
  - **Deaths** rose with the packs: t3 6 of 18 (hounds 4, the zealots 2), t4 8 of 18 (packs 7, the living 1).
    - A death ends a run early, so t4's length is held down by its risk.
    - Step 4's lever will move both. Run length and risk have to be read together from here.
  - **The detour.**
    - Offered in every run (54 of 54).
    - Taken in 41: t2 7 of 18, t3 16, t4 18. The t2 army at the antechamber (about 7-9) is under twice a guard of 4.
    - The cache was won in 25; she abandoned 10 below 0.3 hp.
  - **Survivors only**, which is where length lands once Step 4 brings deaths to 10-15%:
    - t3 153 s, human estimate 182-241 s.
    - t4 151 s, human estimate 177-243 s: 98% of the floor.
    - t2 is unchanged (no deaths): 134 s, human estimate 157-219 s, so its shortfall and the Bellringer's +36% there are real.
  - **Step 4 facts.**
    - Deaths are dominated by the packs: t4 7 of 8, t3 6 of 6 (hounds 4, zealots 2).
    - At t4 the detour is a trap. It is taken 18 of 18, because the decision falls at 4-24 s with the starting army. She won it 4 times and abandoned it 9; 7 of the abandoned runs and all 8 deaths followed a taken detour.
    - The decision is in the second room, so the take rate follows the garrison against the guard by fort (t2 7 of 18, t3 16, t4 18) more than the run's state. A later decision point would make it a real choice.
    - The Shieldwall's bash still never struck Relish (`shield.bash_relish` 0 in 12 of 12). The bearers have no wits counter, so they give the no-wits arm no mechanism of its own.
    - Pack units draw as ordinary living glyphs; only the WARDED label and the HUD row mark them as the warden's.
  - **When each bot knob was frozen.**
  - The reaction rule (`react_*`): at 5b70259.
  - The routing through real openings (`_real_gaps`, a pathing fix): added at f1bf38e. On its own it leaves every 5b70259 line identical (iter `rg`).
  - The first detour rule: Step 3. Its replacement (3b, below) and the `detour_*` knobs are frozen from 3b on. From here only game knobs move, including the guard and the cache.

## Step 3b (D-d/E): every warden's danger gets a counter
The review of Step 3 found two problems. 13 of its 14 deaths came from packs that ignored the counters, and the Shieldwall's bash never reached Relish. 3b changes the wardens and the detour rule; the reaction rule stays frozen.

- **Packs answer their warden's counter** (`WardenLogic.pack_breaker` / `pack_verb`, `RaidWardenRun.breaks_pack` / `pack_target`, `RaidUnit._hit_enemy`, `RaidWarden.on_pack_broken`; tests `warden_pack`).
  - **One blow.** A big undead whose stat meets the warden's own weak point kills a pack unit in one blow: beef for the ringers, speed for the hounds, wits for the bearers, power for the zealots. The threshold is the weak point's own.
    - While a pack stands, such a big goes for the nearest pack unit. The Huntsman's speed bigs keep their bodyguard post at Relish and strike what comes into reach.
    - The kill shows the weak point's verb where the unit fell, for `pack_label_s`: MUFFLED, INTERCEPTED, FLANKED or SNUFFED.
    - The HUD's counter row adds the count, e.g. "SNUFFED ×3 · +6 zealots". The pack row teaches it: "... · power 6 kills one in a blow".
    - AUTOPILOT_RESULT `pack.broken` counts these kills.
  - **Off Relish.** A pack goes for her undead, not for her (`RaidUnit._pick_enemy_target`). It costs time and the army, and her risk stays in the warden's own counter-gated attacks: the unmuffled slam, the uncaught lunge, the rush and the fire.
    - Once no undead stands, the pack turns on her. Without that, a wiped army stalled the fight until the bot gave up.
    - Deaths of this kind show as "hound" or "pack" in `killed_by`, after a wipe.
  - **The ward** while a pack stands is ×0.1, down from 0.25, so a pack's time adds to the fight.
  - **The gates:** 2/3 and 1/3, on the Bellringer's and the Shieldwall's phase notches. The Pyre-priest has one gate at 0.4, its phase-3 notch.
- **The Shieldwall's rush** (`RaidShieldwall._begin_tell` / `_end_rush` / `_pinned`, `WardenLogic.shield_pinned`; `attack.rush_px` 120, `rush_half_deg` 40, `pin_px` 30).
  - **Tell.** As each bash tell starts, unless a wits flanker stands at its back, the bash is a rush. A flanker counts when it is within its orbit plus `pin_px` and off the shield's front arc. The rush lights an arc `rush_half_deg` wider and `rush_px` longer for its tell and bash, with RUSH over it. That arc reaches a conduit waiting at its side: the side stand is 223 px out at 110° off the facing, and a rush reaches 260 px at ±120-140°.
  - **Counter and labelled result.** Wits flankers posted behind pin it: the bash stays a bash, with PINNED over the wall.
  - **Why the wall and not the bot.** The bot reads the arc from `front_half_deg()` and `attack.reach_px`, and the rush writes its reach into `attack.reach_px` for those two beats. So the bot sees the lit rush arc and answers it like any bash tell, through the reaction rule (0.82 answered, 0.45 s). A missed tell, or an answer too slow to clear about 50 px, takes the 12-hp bash. The other two options were dropped:
    - "The bash reaches her stand" alone moves the bot's stand outward, because the bot reads the reach.
    - Pushing the fight into the arc depends on crowd flow.
  - A horn over a rush's tell ends that rush.
  - The `shield` dict gains `rushes`, `pins` and `rush_relish`.
- **The detour rule** (bot policy, frozen from 3b on; `RaidAutopilot._detour_tick` / `_detour_decide`; `RaidLogic.detour_take` / `detour_retreat`; `autopilot.detour_*`).
  - **When.** Once, before the wake, at the first think the guard is in view while no living foe is on her in her room. In view means a standing guard within `detour_view_px` 480 of her (about half a screen at tier zoom); with its guard down, the cache itself.
  - **Take it when:**
    - her hp is at least `detour_hp_frac` 0.6 of its most, or 0.4 with a phylactery revive left;
    - and her army is at least `detour_army_mult` 1.5 × the guard she can see.
  - **Reassess every think on the way in. Turn back when:**
    - her hp falls below `detour_retreat_hp_frac` 0.5 (0.3 with a revive);
    - or her army falls below `detour_retreat_army_mult` 1.0 × the guard still standing.
  - **Basis, a decent player.**
    - Fight a side guard only with clear numbers (1.5×, since raised soldiers trade about evenly with the tier's living) and at least one 12-hp hit of margin.
    - A revive buys a lower floor.
    - Turn back while one more hit still leaves you standing.
    - The guard holds its post, so turning back works: it does not follow her out.
- **The guard holds its post** (`RaidUnit.sentry`, `_pick_sentry_target`). It turns only on Relish or her undead inside its room, and never follows out. The fight therefore happens at the cache, the army passing the door does not draw it out, and leaving ends it.
  - `cache_door_px` is down from 320 to 130, so the walk in and out is short. This is the fix for the travel breach.
- **Measured** (the 3b code as committed: iter `s3e`, with pale-bastion and the-stair re-run as `s3f` after the rush reset; seeds 1-6 at every t2-t4 fort; all runs in lockstep; the baseline is 5b70259 seeds 1-6). Stopped rounds:
  - `s3c`: pack unit hp 60-80. Armies the counter did not reach stalled (4 timeouts, 9 bot give-ups in 40 runs).
  - `s3d`: three gates. Packs wiped t2 armies and the bot gave up.
  - Final numbers: packs ×0.1 ward; sizes hounds 10 / 10 (t4 unused), ringers 5 / 8 / 8, bearers 8 / 11 / 12, zealots 8 / 8 / 14; units 30 hp (bearers 40); cache 130 px.

  | tier | median s: base → all / survivors | travel / fight / trance / idle %, all runs | human estimate s, all / survivors | died (killed by) |
  |---|---|---|---|---|
  | t2 | 101 → 125 / 149 | 6.8 / 91.5 / 0 / 1.7 | 151-218 / 174-238 | 5 of 18 (hounds 4, living 1) |
  | t3 | 115 → 123 / 117 | 6.8 / 87.2 / 0 / 6.0 (outliers out: 9.1 / 82.7 / 0 / 8.2) | 142-200 / 142-192 | 6 (pack 3, bash 2, hound 1) |
  | t4 | 117 → 148 / 142 | 10.2 / 81.1 / 0 / 8.7 | 171-228 / 166-227 | 5 (pack 5) |

  - **The window is not reached.** The low end is 151 / 142 / 171 s against 180 s.
  - **The guard fails** at t2 travel (6.8 against 5.3%), and at t3 and t4 idle (8.2 against 7.5 and 8.7 against 6.5, outliers out).
  - **Per archetype at tier** (tier median in brackets):
    - t2: Bellringer 152 (+21%), Huntsman 83 (-34%) [125].
    - t3: Huntsman 117, Pyre-priest 145 (+23%), Shieldwall 175 (+48%) [118].
    - t4: Bellringer 184 (+24%), Pyre-priest 106 (-28%), Shieldwall 149 [148].
  - **The detour** (offered / taken / won / abandoned / died after taking it; decision times):

    | tier | offered | taken | won | abandoned | died after | decided at |
    |---|---|---|---|---|---|---|
    | t2 | 18 | 18 | 16 | 2 | 5 | 0-8 s |
    | t3 | 14 | 14 | 8 | 4 | 3 | 1-30 s |
    | t4 | 18 | 17 | 10 | 4 | 5 | 0-175 s |

    The guard is usually in view from the spawn room, so the decision still falls early. Taking it is what lifts travel: runs that took it traveled about 9-11% at t2-t3 against 2-4% for those that did not (s3a, s3e).
  - **With and without the counter** (10 seeds each, score 70; Relish died with / without):
    - vespers (beef 5): 2 / 3. Living 2; living 2 and slam 1.
    - hollow-redoubt (speed 3): 4 / 5. All hounds, after the army fell.
    - pale-bastion (wits 0): 7 / 9. Rushes struck her 61 times in each arm. Pins: 77 of 439 bash tells with wits.
    - mourners-gate (power 5): 1 / 2. Packs.
    - The counters break the packs (pack.broken 40-88 of the units called with the counter, 0 without), but no counter yet halves deaths.
  - **What blocks** (for the spec review):
    - (1) **Pack strength.** Packs strong enough to lengthen a fight at tier wipe the army. With no undead left, the pack turns on her, so 13 of the 16 deaths at t2-t4 are "pack" or "hound" after a wipe (without that rule the fight stalls). Packs weak enough not to wipe it are broken in seconds by the counter, and the fights stay short.
    - (2) **The Shieldwall's counter is split two ways.** Its wits bigs leave the flank to hunt bearers (`pack_target`), so the rush is rarely pinned, and the with-wits arm dies almost as often as the one without.
    - (3) **The detour is decided from the spawn room** (the guard is in view there), and its walk is travel.
  - **Unchanged:** tier 1, the first dungeon and Vei (byte-identical without the new keys). `parity_check.sh` gives identical results.
  - **Shots:** `de-huntsman-hounds.png` (re-shot at 10 hounds), `de-ringers-muffled.png`, `de-bearers-flanked.png`, `de-zealots-snuffed.png`, `de-shieldwall-rush.png` (no-wits arm: RUSH lit to her side stand).

## Step 3c (D-d/E): packs break off Relish, the idle sources, the death fields
The review of 3b found that every death left no army standing, and that 13 of the 16 tier deaths were packs that turned on Relish after a wipe. 3c is one redirected round with a stop rule. The reaction rule and the detour rule stay frozen.

- **The death fields** (measuring only): AUTOPILOT_RESULT gains `death_t`, `army_zero_t` (the first tick no undead stood, else -1) and `army_at_death_minus5` (undead standing 5 s before her death, from a half-second log). It also gains `unstick` {aimed_in, given_up} (below).
- **The idle sources** (found before any tuning; a debug histogram of the bot's `_why` over idle ticks):
  - **the-stair seed 1: 20 s in the spawn room and 20 s in the antechamber.** This is the bot's hold rule ("hold while living remain in this room or the next"). It waited on calm foes in the next room, about 1000 px away and 900 px from the nearest undead, until `stall_s` (20 s) ran out. Nothing moves in those 20 s and there is nothing to decide, so it is a bot wait, not a decision moment. It is cut.
  - **sable-hold seed 2: 20 s, 6.6 s and 2.9 s.** The same rule, on calm foes.
  - **hollow-redoubt seed 6: 99 s, then a retreat.** The bot walked to a remnant lying 6 px from a wall. Relish's slide makes no progress when the straight line runs along a wall face, so she stood pinned on the wall's corner until the bot's 60 s no-progress give-up. This is a bot wait.
  - None of these is a game wait, and none is a gap in `time_class`: each was a tick with no hostile foe in reach and no movement.
- **Bot fix 1, the unstick watch** (`RaidAutopilot._aim_at`; `autopilot.unstick_s` 1.5, `unstick_px` 8, `unstick_inset_px` 8). Walking to a mote, pile or pickup:
  - if she does not close on it by 8 px of walking distance in 1.5 s, she aims at the same spot pulled inside its room, as a player re-clicks a reachable spot;
  - if she still does not close in another 1.5 s, she gives it up.
  - It changes nothing while she closes on the target. hollow-redoubt seed 6 goes from 100.9 s idle and a retreat to 26.4 s idle and a won run. Tier 1, P1, Vei and three tier 2-4 lines are byte-identical without the new key.
- **Bot fix 2, the hold waits only on hostile foes** (`_decide`). A calm foe out of the army's reach is no fight to wait out.
  - the-stair seed 1: idle 40.0 s -> 0.1 s. sable-hold seed 2: idle 30.1 s -> 0.7 s.
  - **It changes the first dungeon and tier 1.** These runs held on calm foes too: P1 old-sluice seed 1 goes 98.1 -> 82.5 s, tier 1 ashgate 89.7 -> 105.6 s, old-sluice 113.2 -> 107.2 s, and pale-bastion seed 1 changes. Greywall, hollow-redoubt seed 1, whitecross seed 2 and Vei are identical. The game is untouched; only the bot's wait moved. P1 was calibrated earlier, so this is flagged.
- **A pack never turns on Relish** (`WardenLogic.pack_breaks`, `RaidWarden._scatter_pack`, `RaidUnit.scatter`). The moment no undead stands, or none stands as its horn sounds, the pack breaks:
  - it leaves the fight, gone and not killed (nothing drops, no kill is counted);
  - its ward drops, and the warden fights her alone with its own attacks, each answered by its counter;
  - THE PACK BREAKS · WARD DOWN shows over the warden for twice `pack_label_s`, and the banner says "THE PACK BREAKS — ward down";
  - `pack` gains `scatters` and `scattered`.
- **The Shieldwall's roles** (`RaidWardenRun.pack_target`, `RaidShieldwall.posted`, `RaidUnit._pack_in_reach`).
  - A wits big holding its post at the wall's back keeps the wall as its target. "Holding its post" is the pin's own test, for one unit. It strikes the pack units that come to it with the one-blow FLANKED kill.
  - Through a bash tell, every pack breaker keeps the wall. This clause never fires: the wall holds its own attack while its pack stands (`_pack_step` pushes the next tell past the pack), so no tell shows with a pack standing.
  - The hunt goes to the breakers not posted there.
  - The rush stays.
  - **A first version was worse.** In it, posted flankers held the wall but did not strike the pack. At pale-bastion seed 1 the pack then ate them: 2 of 33 tells pinned, 0 pack units FLANKED.
  - **With the strike** it is 8 of 9 tells and 16 of 18 units. That is about the 3b code's own seed-1 line (12 of 14 pinned, 21 of 22 FLANKED). The commit message of 4413cf3 compares against the first version, not 3b.
- **The death card names the missed tell** (`RaidLogic.death_tell` / `death_line`): "The Bellringer's slam · missed: the swing", "the Huntsman's lunge · missed: the line", "the Shieldwall's bash / rush · missed: the lit arc", "the Pyre-priest's fire · missed: the marked ground". A pack, the living or a wound has no tell and no "missed:". A rush that strikes her is now its own source (`killed_by` "rush").
- **Packs back to Step 3:** hounds 8 / 8, ringers 4 / 6 / 8, bearers 6 / 9 / 10, zealots 6 / 6 / 12; ward ×0.25.
- **The detour's cache at the guard's post** (`detour.cache_door_px` 130 -> 45). LayoutLogic keeps it 40 px off the walls, so it lies about 55-60 px from the gap, and she takes it inside the guard fight, stepping through the door.
  - t2, seeds 1-6: travel 7.4% -> 6.0% (`walk_travel_px` median 2628 -> 2194). That is still over the 5.3% ceiling.
  - So **the detour starts at tier 3** (`detour.min_tier` 3).
- **Pins under the measure.** At pale-bastion, seeds 1-10 with wits, 75 of 441 bash tells were pinned (17%), against 77 of 435 in 3b. The roles did not raise the pin rate where it counts.
- **AUTOPILOT_RESULT `army_zero_s`:** scene seconds after the wake with no undead standing (measuring only).
- **Measured** (the 3c code, f8dfd39 = 87c4d53 without `army_zero_s`; iter `c3`; seeds 1-6 at every t2-t4 fort; 326 of 326 runs in lockstep).
  - **Baselines.** The baseline is 5b70259. Because the bot fixes move it, `bfix` is 5b70259 with only the two bot fixes, seeds 1-6, as an A/B.
  - **The split** is pooled seconds with outliers (more than 2× their fort's median) out.
  - **The human estimate** is the median of per-run estimates.

  | tier | median s: base / bfix → all / survivors | travel / fight / trance / idle % | human estimate s, all / survivors | died (killed by) |
  |---|---|---|---|---|
  | t2 | 103 / 107 → 125 / 125 | 4.5 / 94.4 / 0 / 1.1 | 146-203 / 146-203 | 0 of 18 (2 retreated) |
  | t3 | 115 / 95 → 194 / 158 | 7.3 / 91.7 / 0 / 1.1 | 210-263 / 181-219 | 5 of 18 (rush 4, lunge 1; 2 retreated) |
  | t4 | 118 / 114 → 130 / 130 | 7.8 / 92.1 / 0 / 0.1 | 152-202 / 152-202 | 0 of 18 |

  - **The guards hold on both baselines.**
    - Travel (base / bfix ceilings): t2 4.5 against 5.3 / 5.9, t3 7.3 against 10.5 / 14.5, t4 7.8 against 16.0 / 11.6.
    - Idle: 1.1 / 1.1 / 0.1 against 5.1 / 7.5 / 6.5 (base) and 1.6 / 2.2 / 0.3 (bfix).
    - In seconds, t4 travel is 14.1 s median, against 17.8 at base and 10.1 for bfix: the t4 detour's walk.
    - Part of the low share is dilution: the fights got longer.
  - **The bot fixes alone move the baseline** (bfix against base): t3 115 -> 95 s, travel t3 10.5 -> 14.5% and t4 16.0 -> 11.6%, idle 5-8% -> 0.3-2%.
  - **Window.** The low end at t2 (146 s) and t4 (152 s) is under 160 s. That gap is reported, not padded. At t3 the survivors land 181-219 s.
  - **Per archetype** (tier median in brackets):
    - t2: Bellringer 129 (+3%; the +36% is gone with the t2 detour), Huntsman 104 (-17%) [125].
    - t3: Huntsman 193 (0%), Pyre-priest 154 (-20%), Shieldwall 255 (+32%) [194].
    - t4: Bellringer 339 (**+161%**), Pyre-priest 116 (-11%), Shieldwall 112 (-14%) [130].
    - The sable-hold Bellringer loses its party in every seed and then grinds on with raised soldiers for 260-450 s. In 3b those runs died to the pack instead. Not fixed: no one-knob change was found, and the stop rule holds.
  - **The detour** (none at t2; offered / taken / won / abandoned / taken ∧ died):
    - t3: 13 / 12 / 10 / 2 / 1.
    - t4: 18 / 17 / 7 / 5 / 0. Five were still unfinished when the run ended.
  - **How a wiped army resolves** (19 tier runs with no undead standing at some point: t2 4, t3 9, t4 6; the pack broke in 12):
    - `army_zero_s` is mostly 1-9 s. She raises again from her fallen undead's motes within seconds and grinds on. These are the long runs: all 5 tier outliers are among them.
    - Or the warden's own attack kills her: all 5 t3 deaths (rush 4, lunge 1). A pack killed no one.
    - Or there are no motes left, and the bot's existing 60 s no-progress rule retreats her. This happened in 4 Huntsman runs, with 48-71 s of no army.
    - No wait was added. There were no timeouts at tier; the arms had 3 runs at the 600 s cap.
  - **With and without the counter** (the manager's pooling: 2 forts per warden at tier, seeds 1-20, 40 runs per arm; deaths, 90% Wilson interval; fight = end minus wake, median):

    | warden (forts; without = flag) | with: died | without: died | fight s with / without |
    |---|---|---|---|
    | Bellringer (vespers, lantern-keep; beef 5) | 0 / 40 (0-6%) | 0 / 40 (0-6%) | 100 / 181 |
    | Huntsman (chime-fort, hollow-redoubt; speed 3) | 5 / 40 (6-24%), lunge 5 | 4 / 40 (5-21%), lunge 2, living 2 | 96 / 125 |
    | Shieldwall (pale-bastion, the-stair; wits 0) | 14 / 40 (24-48%), rush 14 | 16 / 40 (28-53%), rush 16 | 126 / 295 |
    | Pyre-priest (mourners-gate, whitecross; power 5) | 1 / 40 (1-10%), living 1 | 1 / 40 (1-10%), fire 1 | 105 / 193 |
    | all four | 20 / 160 = 12.5% (8.8-17.4%) | 21 / 160 = 13.1% (9.3-18.1%) | |

    - **The arms do not separate on deaths** (the bar is about 2× and at least 10 points). The counters separate on fight length, at 1.3-3×.
    - pale-bastion carries the deaths: 14 / 20 with wits, 16 / 20 without. the-stair has 0 / 20 in both arms.
    - **Why.** With packs off Relish, the warden's own attack is the only killer, and only the Shieldwall's rush kills at all often.
      - In every pale-bastion death, in both arms, both party bigs were already lost, so no wits flanker was left to pin.
      - The unpinned rushes then cut down the raised soldiers along with her: 12-21 undead still stood 5 s before 11 of the 14 deaths with wits, and before 13 of the 16 without.
      - So the risk sits in the rush's reach into the raised army after the bigs fall, not in a wipe followed by a lone finish.
      - Without its counter, a warden's fight simply runs longer.
  - **Unchanged:** Vei byte-identical. Tier 1 and P1 equal the bot-fixed lines (bfix's own effect is above). `parity_check.sh` gives identical results, 5 of 5.
  - **Shots:**
    - `de3c-pack-breaks.png`: hollow-redoubt, no speed. The banner and THE PACK BREAKS · WARD DOWN over the Huntsman, LIVING 0.
    - `de3c-shieldwall-posted.png`: pale-bastion seed 1. Posted wits flankers at the wall's back, FLANKED on the bearers coming at them while BEARERS · WARDED stands.
    - `de3c-shieldwall-pinned.png`: the first tell after that pack. BASH, PINNED.
    - `de3c-death-card.png`: "The Bellringer's slam · missed: the swing".
    - No shot shows a pinned rush with the pack standing, because the wall never tells while its pack stands.

## Step 4 (D-d/E), before the lever: the 3c review items and the per-fort causes
- **The Shieldwall's tell clause is moot by design** (b0977c1).
  - The wall holds its bash while its pack stands, so "pinning outranks hunting through a tell" in `pack_target` could never fire. It is removed.
  - Only posted wits bigs keep the wall. 4413cf3's message described the clause as live.
- **The hold and the unstick watch as pure functions** (`RaidLogic.hold_blocks` / `unstick_step`; tests `raid_bot_rules`; b4763b1). Behaviour is unchanged: 14 lines are identical.
- **The unstick watch fired on doorways, not on stuck walks.**
  - Sampled firings (whitecross s3/s19, the-stair s5/s8, mourners-gate s5, pale-bastion s4) were all the same thing. The target was in another room, and the walking distance jumped at a doorway: straight in the gap, round by room centres beyond (1012-1257 px against 539-895 straight). She was walking on, with 0-1 undead touching her and no foe near.
  - None was a crowd or a pinned walk. The clock now restarts when her room changes (0aa97d6).
  - Seeds 1-6, t2-t4: firing runs 7 -> 1. The 6 changed lines differ only in the count.
- **The residual idle is a classification gap.**
  - the-stair s16 (16.8 s) and hollow-redoubt s11 (13.9 s) are both the hold on a hostile brute in the next room. The brute was fighting her army (its nearest undead 15-30 px away) 400-850 px from her.
  - `time_class` calls that idle (no hostile foe within aggro_px or in her room), but it is the army's fight. It is kept as it is, so the baselines stay comparable.
- **No army, nothing to raise: she leaves after her reaction delay** (5e2a7a9; `RaidLogic.can_raise_from`; result `left_no_army`).
  - It applies with no undead standing, fewer than min_motes carried or within collect_px, and no pile within pile_px. It was 60 s inside a "fight".
  - Seeds 1-6: 5 Huntsman lines change (chime-fort s2 112 -> 52 s, s5 158 -> 113, hollow-redoubt s4 228 -> 180, s5 569 -> 198, s2 died at 401 -> left at 395). t1 and P1 are identical.
  - `army_zero_s` share of the run (c4): t2 0.1%, t3 0.5%, t4 0.5%.
- **One outlier rule:** "> 2× its fort's median within the run set being reported".
  - One iter is one run set, so the runner's `outlier_2x` is that rule: the tier set (`c4`) and the extra seeds (`c4x`) are separate iters.
  - c3 mixed the tier set and the arms in one iter. Its row flags used 20-seed groups at the 8 arm forts.
  - Under the rule the 3c tier shares stand as reported: t2 4.5 / 1.1, t3 7.3 / 1.1, t4 7.8 / 0.1 (travel / idle).
- **Bad outcomes in the 3c arms** (died + retreated + timeout, seeds 1-20, with / without the counter):
  - vespers 0 / 0, lantern-keep 0 / 0;
  - chime-fort 6 / 0, hollow-redoubt 7 / 10;
  - pale-bastion 14 / 17, the-stair 0 / 0;
  - mourners-gate 1 / 2, whitecross 0 / 0.
  - Pooled: 28 / 160 against 29 / 160.
- **What held the three 600 s runs open:**
  - chime-fort s8 (with speed): the army was gone and there was nothing to raise. She now leaves at 60 s.
  - pale-bastion s13 (wits 0): 90 raises against a wall that glances from the front, with no flankers. The warden was at 16% at the cap.
  - mourners-gate s15 (power 5): three undead chipped a priest warded by its living acolytes at 1.6 hp/s for 510 s. She held the pyre stand with one mote and a pile she would not stir. Progress that slow never trips the 60 s rule.
  - The last two are counter-less grinds, and they count as bad outcomes.
- **4.0: the no-counter arm faces more tells.** Tells at Relish (react.tells, 3c arms, 40 runs each), with / without:

  | warden | median | total | per fight-minute |
  |---|---|---|---|
  | Bellringer | 18 / 33 | 838 / 1423 | 10.7 / 10.9 |
  | Huntsman | 9 / 16 | 928 / 1226 | 5.4 / 7.1 |
  | Shieldwall | 18 / 54 | 1153 / 2256 | 8.8 / 11.1 |
  | Pyre-priest | 3 / 6 | 136 / 321 | 1.4 / 2.1 |

  - The per-minute rates are close (the Huntsman and the Pyre-priest a little higher without the counter), and the fights run 1.3-3× longer.
- **But the lever multiplies hits that land on her, not tells.** Hits on Relish in the same rows, with / without the counter (totals over 40 runs):
  - Huntsman catches: 50 / 110 (median 0 / 2 a run).
  - Pyre-priest burns: 14 / 58.
  - Shieldwall bashes and rushes: 194 / 269, almost all at pale-bastion (190 / 256; the-stair 4 / 13). Since the room cap, pale-bastion takes 0.4 a run, so the Shieldwall is near zero hits in both arms at both forts.
  - Bellringer: slam hits on her are not recorded; 0 deaths in 80 runs.
  - **What that means for the lever.** A damage multiplier can make the Huntsman and the Pyre-priest deadly, and separate their arms (2-4× the hits without the counter). It cannot do either for an archetype whose hits are near zero in both arms.
  - Before 4.2, a measuring-only `relish_hits` key by source (slam, lunge, bash, rush, fire, pack, living) gives the Bellringer's count and the 4.3 cause mix.
- **4.1, the per-fort causes:**
  - **pale-bastion against the-stair.** Same warden, but the warden rooms are 543 × 598 px against 1073 × 679.
    - A 260 px rush covered nearly all of pale-bastion's, so an answered tell had nowhere to go. Rush hits on her: 9.4 a run there, 0.2-0.7 at the-stair, even without wits.
    - Fixed by a general rule, not a per-fort one: the rush reach is capped at `rush_room_frac` 0.8 of the room's half-size (`WardenLogic.rush_reach`; ce17f3d). the-stair is unchanged.
    - pale-bastion with wits, seeds 1-20: deaths 14 -> 0, rush hits 0.4 a run. But the fight runs longer (256 -> 335 s median): with its bigs lost it now grinds instead of killing.
  - **chime-fort with speed.** The bodyguard post held its speed bigs at her side while the hounds ran (the Huntsman holds its lunge then).
    - The hounds wiped the army away from her. s5 trace: 29 undead to hounds in 13 s, and 2 of the 29 motes in raise reach. Then she left.
    - Fixed: there is no post while the pack stands, so they hunt it (7eecd95). Seeds 1-20: bad outcomes 6 -> 1, INTERCEPTED 51 -> 128 of 320 hounds.
  - **sable-hold: not fixed in two probes.** The slam kills 280-440 undead a run (seeds 1-4, by damage source).
    - 2 of the 3 bigs die to the fort's brutes before or at the wake in 3 of 4 seeds. The beef big then dies to the ringers or to slams.
    - Unmuffled slams churn every raise for 200+ s.
    - Probes, not committed: ringers at t4 8 -> 6 gave a median of 286 s; slam `dmg_unit` 11 -> 8 gave 259 s (339 now). Neither stops the grind.
- **Seeds 1-6 at t2-t4** (c4, the code at ce17f3d; 58/58 in lockstep):

  | tier | median s | per archetype (against the tier median) | deaths |
  |---|---|---|---|
  | t2 | 123 (human 144-201) | Bellringer 129 (+5%), Huntsman 118 (-3%) | 0 / 18 |
  | t3 | 172 (200-266) | Huntsman 158 (-8%), Pyre-priest 154 (-10%), Shieldwall 316 (+84%) | 0 / 18 |
  | t4 | 130 (152-202) | Bellringer 339 (+161%), Pyre-priest 116 (-11%), Shieldwall 112 (-14%) | 0 / 18 |

  - Travel / idle: 4.5 / 1.2, 7.2 / 1.0, 7.8 / 0.1.
  - **The two game fixes change only their own forts.** Against the bot-fix lines (`s4b`), vespers, lantern-keep, mourners-gate, the-stair, whitecross, sable-hold, t1 and P1 are identical. chime-fort and hollow-redoubt (the bodyguard fix) change 6 of 6, and pale-bastion (the cap) 5 of 6.
  - **Two forts now grind once their bigs fall:** pale-bastion (+84% at t3, against a wall its raised soldiers glance off) and sable-hold (+161%). A Relish-damage lever adds exposure in proportion to fight length, so expect its deaths to pile onto these two.
  - Not tested at pale-bastion: the checkpoint-room cache and the t3 party against the t4 party. The room geometry explained the rush hits.
  - t1 and P1 lines equal the bot-fixed ones. Vei is identical. Parity is 5 of 5.

## Step 4 (D-d/E), the lever probe and the conduit rule
- **`relish_hits` / `relish_soaked`** (3a36410): blows that reached her by source, and of them the lethal ones an undead took. They are counted on Relish and never read by the sim; 18 c4 lines and Vei are identical.
- **The conduit rule** (relish.gd `take_hit`; raid.gd `sacrifice_nearest_ally`; raid_logic.gd `ally_rank` / `sacrifice_pick`):
  - **When.** A blow that would take her hp to 0 or below, while any undead stands anywhere in the dungeon. There is no reach.
  - **Who dies.** One undead in her place: the lowest rank first (chaff, then soldier, then elite, then a party big), the nearest within that rank.
  - **The cost.** She takes no damage and gets `relish.iframes_s` (0.5 s) of grace. There is no cap and no cooldown.
  - **Design.** MECHANICS §5.0: "Lethal hits follow the sacrifice chain: nearest chaff, then a soldier, then a big undead in the party, then Relish". §7: "Before she dies, the sacrifice chain soaks lethal hits". GAMEPLAY pillar 4: "Her army is her weapon, her shield and her health bar". No reach or cap is designed either.
- **The lever candidates** (42b8427, at 1.0): `wardens.relish_dmg_mult` and `wardens.attack_dmg_mult`, from `lever_min_tier` 2, never the first dungeon.
- **Probe** (c4 code; the same 30 runs per value: t2-t4, seeds 1-10 a tier, forts in rotation):

  | value | deaths | bad outcomes | median s | `army_zero_s` share | warden blows on her (soaked) |
  |---|---|---|---|---|---|
  | x1 | 0 | 1 | 139 | 0.6% | 14: lunge 10, fire 2, rush 1, slam 1 (3) |
  | relish x2 | 0 | 0 | 150 | 0.6% | 17 (10) |
  | relish x4 | 0 | 1 | 139 | 0.6% | 14 (14: every one lethal, every one soaked) |
  | attack x1.5 | 1 (rush) | 7 | 159 | 9.1% | 9 (0) |
  | attack x2.5 | 1 (rush) | 9 | 186 | 10.8% | 15 (13) |

  - The bot answers 82% of tells and stands outside the arcs, so warden blows reach her about once in two runs. Each lethal one costs one undead.
  - Raising the damage to the army instead (attack) wipes armies (`army_zero_s` 0.6% -> 9-11%). The wipes become 600 s grinds of re-raising (Bellringer 3, Shieldwall 2) and retreats, not deaths.
  - Mini arms at attack x2.5 (10 seeds an arm), bad outcomes with / without the counter:
    - hollow-redoubt 3 / 6 (deaths 0 / 2; lunge blows on her 12 / 28);
    - mourners-gate 0 / 0 (fire 4 / 17).
  - **Verdict: no warden-damage lever reaches 10-15% deaths at tier while the conduit rule stands.** Deaths need the conduit changed (a reach, a cost, or a cap), which is the manager's call.
- **4.1 round 2, the two grinding forts (probes only, nothing committed):**
  - **pale-bastion s2 trace.** One big died to a brute in room 1 before the wake (11 s), the other to the bearers. Then bashes and rushes killed 659 raised undead over 461 s, while she raised 69 times.
  - **Can the flankers reach the wall's back?** Yes. Seed 1 pinned 16 of 16 tells while they lived; the 10% pin rate across seeds is dead flankers, not the room. The room was not grown.
  - **sable-hold** has a brute in its spawn room (542 px from the spawn); the-stair and whitecross have none. The near-spawn living per fort is in the scratch dump.
  - **Probes, seeds 1-6:**
    - fewer brutes (tier_mix t3 0.3 -> 0.2, t4 0.45 -> 0.3): sable-hold 339 -> 228 s, pale-bastion 335 -> 208 s;
    - party `hp_base` 30 -> 50: sable-hold 206 s, pale-bastion 318 s.
    - Neither reaches about 30% of its tier median (t4 130, t3 172); bigs are still lost.
  - **The shared mechanism:** the warden's area attack (slam, bash, rush) churns re-raised soldiers once the bigs are gone.

## Step 4b (D-d/E): the manager's option A
- **Tell-attacks bypass the chain** (`RaidLogic.chain_soaks`, `TELL_ATTACKS`; Relish.take_hit). The Bellringer's slam, the Huntsman's lunge, the Shieldwall's bash and rush, and the Pyre-priest's fire strike her directly. The chain still soaks the living, packs, hounds and Vei's weaves.
- **The counter is the soak:**
  - Bellringer: a MUFFLED slam no longer reaches her (`WardenLogic.slam_damage`; it took ×0.35 before). Answered: she is out of the ring as it crosses.
  - Huntsman: an INTERCEPTED lunge never reaches her (`_begin_lunge`, `hit_i < 0`). Answered: she is off the locked line.
  - Shieldwall: a bash whose tell a wits flanker pinned never strikes her (`pinned_tell`, `WardenLogic.bash_strikes_relish`). Answered: she is out of the lit arc.
  - Pyre-priest: a burn she has stepped off misses her, and each acolyte killed takes one of her fires away (`WardenLogic.burn_count`). Both as built.
- **The hit cue** (`Relish._draw_hit_cue`, `relish.hit_cue_s` 1.2): the most recent blow shows.
  - A blow that reached her hp: a jagged burst and STRUCK −N, in `danger`.
  - A blow an undead took: a smooth ring and SOAKED, in `undead`.
  - It is static, so it reads the same in greyscale and under reduced motion.
- **The docs** (f50277b) change only MECHANICS §5.0's chain line and GAMEPLAY pillar 4, as the manager authorized.
- **The grind forts.** `tier_mix_by_fort` lowers the brutes at sable-hold (0.45 -> 0.15) and pale-bastion (0.3 -> 0.1). Their bigs had died to brutes before the wake.
  - Seeds 1-6: sable-hold 339 -> 157 s (+26% of the t4 median, 125), pale-bastion 335 -> 151 s (-1% of t3's 153), with 0 deaths. No other fort moves.
- **The lever** (`wardens.relish_dmg_mult`, from tier 2). The single tell-hit as a share of her 30 hp is the same at every tier, because dmg_relish has no tier term:

  | relish_dmg_mult | slam, lunge, bash, rush (12) | fire (8) |
  |---|---|---|
  | 1.5 | 60% | 40% |
  | 1.9 | 76% | 51% |
  | 2.3 | 92% | 61% |

  - One hit kills from full hp at 2.5 (fire at 3.75).
- **Probe on the final code** (30 runs each, t2-t4, seeds 1-10, forts in rotation):

  | relish_dmg_mult | deaths | killed by |
  |---|---|---|
  | 1.5 | 3 | lunge 3 |
  | 1.9 | 3 | lunge 3 |
  | 2.3 | 4 | lunge 3, fire 1 |

  - Bad outcomes equal the deaths. 1.5 and 1.9 give identical outcomes.
  - Tell blows on her: about 8 lunges and 2 fires per 30 runs, all unsoaked. Slams and bashes almost never land: the bot answers them, and muffles and pins spare her.
  - **The curve is a staircase.** Two 12-hp blows kill from full hp from 1.25 up, two fires from 1.875 up, and one blow at 2.5.
  - Deaths sit at the Huntsman (3 of 7 runs at every value).

### Step 4b review: corrections and the reach of a missed tell
- **Corrections to the Step 4b notes above:**
  - sable-hold and pale-bastion are now their tiers' soft-living forts: brutes 0.15 and 0.1, against the tier's 0.45 and 0.3.
  - Against c5, the proper base for this build, sable-hold went 278 -> 157 s, not 339 -> 157 s.
  - The grind fix was tuned and measured on the same seeds, 1-6.
- **The bypass is gated** like the lever (`WardenLogic.lever_on`, `RaidWardenRun.tell_bypass`; 49964d2). At tier 1 and in the first dungeon the chain soaks a tell-attack as before. t1 and P1 over seeds 1-6 are identical to the c4 code (24 of 24).
- **`tell_tally`** (measuring only) counts each tell the bot sees: answered or missed, then for a missed one, countered or struck.
- **The reach of a missed, uncountered tell** (c6, x1, seeds 1-6):

  | warden | reach | answered tells struck |
  |---|---|---|
  | Bellringer | 0% of 65 | 0 |
  | Shieldwall | 6% of 32 | 0 |
  | Huntsman | 53% of 19 | 0 |
  | Pyre-priest | 30% of 10 | 0 |

- **Why the Bellringer and the Shieldwall miss: the bot's default plan already dodges them.**
  - Bellringer (raid_autopilot.gd `_vs_bell`, `_bell_target`): she goes in only when the trip fits before the next tell (by the beat clock, `slam_safe_beats`), and stands outside `radius_px` otherwise. At the tell she is outside whether or not she answers.
  - Shieldwall (`_vs_wall`, `_wall_stand`): answered and missed both head for the side stand. It is computed from the facing and `attack.reach_px` of the moment, and the rush writes into both, so a missed rush is dodged by default. Only a loot or pickup detour keeps her in the arc.
- **No game-side change fixes this for the frozen bot.**
  - A toll at her stand, a bigger slam or an aimed rush is either read by that default plan (and dodged again), or not readable, in which case answered tells land too.
  - So nothing was built. The two options need a call:
    - (a) a bot change: a missed tell plans with the geometry from before the tell until its strike, as "missed" means;
    - (b) accept that the Bellringer and the Shieldwall carry no tell risk for this bot.
- **The lever probe** (relish_dmg_mult 1.35 and 1.7; rotated 30 runs each): identical outcomes, 3 deaths of 30, all Huntsman lunges. The steps are unchanged: two 12-dmg blows kill from 1.25, two fires from 1.875, one blow from 2.5.

### Step 4b: the reach at her stand
- **Missed means missed** (b1233c4; see the reaction model). Against c6, the Huntsman, the Pyre-priest and sable-hold are identical. The Bellringer's t2 forts, both Shieldwall forts, P1 (6 of 6; its blows are still soaked) and 3 of the 18 t1 lines move. Missed rushes now land: pale-bastion has 4 deaths in 6, the-stair 1.
- **The Bellringer's toll** (e09264b; `attack.toll_radius_px` 45; WardenLogic.toll_strikes):
  - It is a ring at her spot beyond the slam's reach, from the risk gate. Stepping out is the answer.
  - A braced bell tolls nothing on her (MUFFLED). The army's damage is unchanged.
  - The bot answers it through the same roll and delay (fa42e59).
- **The Shieldwall's aimed rush** (c97c2e8; `rush_lane_half_deg` 20; WardenLogic.lane_reach):
  - It is a lane at her to the room's farthest corner. Sideways out is the answer, and a pin spares her.
  - The lane is also what the undead in it take.
- **Every tell is answerable by a human** (cc3fb06, a test). The check is lead (1 beat, 1.714 s) minus the score-50 delay (0.6 s) minus the walk to clear its area from the worst spot inside it:

  | tell-attack | margin |
  |---|---|
  | slam ring | 0.17 s |
  | toll | 0.77 s |
  | lunge | 0.97 s |
  | bash | 0.71 s |
  | aimed lane (in the-stair's room) | 0.16 s |
  | fire | 0.62 s |

  - The same at every tier: tell_beats and these reaches have no tier term. No margin is negative, so no change was made.
- **c7** (x1, seeds 1-6):
  - Reach on missed, uncountered tells: Bellringer 43% (13 of 30), Huntsman 47%, Pyre-priest 30%, Shieldwall 29% (2 of 7). Answered tells struck: 0 at all four.
  - Deaths: t2 5, t3 1, t4 7 of 18. The Bellringer accounts for 10 of its 18 runs.
  - Medians against c6: t2 119 (123), t3 138 (153), t4 126 (125).
- **The lever** (10 seeds a tier, forts rotated): t2 / t3 / t4 deaths of 10 are:

  | relish_dmg_mult | t2 | t3 | t4 |
  |---|---|---|---|
  | 1.0 | 5 | 1 | 3 |
  | 0.8 | 4 | 1 | 3 |
  | 0.6 | 3 | 0 | 3 |

  - **No value puts every tier in 5-25%.** The Bellringer sees about twice the tells per fight (15-41 against about 10 elsewhere), so its forts (vespers, sable-hold) die at any value. t3 has no Bellringer.
  - Steps: with hits of 12 x m, n hits kill from m >= 2.5/n (1.25, 0.83, 0.63 for 2, 3, 4 hits); fire's 8 x m kills in n hits from 3.75/n. Chip damage from the living blurs both.

### Step 4b: the tally gap and per-warden exposure
- **The gap was the tally's.** The killing blow ended the run before a split tick recorded it, so struck tells fell one short of the blows in every death.
  - ef91d24 books it, and adds `tell_tally.untold_blows`: blows in no seen tell's window.
  - Every blow in the 13 c7 deaths, and in the 180 runs after, followed a tell she saw. untold_blows is 0 throughout.
- **Two answered tells did strike, and both are fixed:**
  - A toll in a corner just outside the ring had no exit (lantern-keep s2). It now lands only where stepping out toward the bell keeps her out of the slam (`toll_gap_px` 40; 40d281d).
  - Kiting hid a lit tell from the roll (the-stair s1: the rush was seen 0.70 s before it struck). A warden tell is now seen and answered before the kite (0741e80, fixed after the freeze, beside "missed means missed").
- **The exposure knobs** (old -> new):

  | knob | old -> new | effect |
  |---|---|---|
  | Bellringer `toll_every` | (1) -> 3 | |
  | Bellringer `toll_gap_px` | (0) -> 40 | |
  | Pyre-priest `relish_area_every` | (none) -> 4 | aimed fires per fight about 4 -> 8.7 |
  | Shieldwall `rush_lane_over_px` | (room) -> 80 | the lane reaches 80 px past her: an answer by stepping back, 0.72 s margin |

- **e2** (x1, seeds 1-10, 2 forts x 10 per warden):

  | warden | deaths | tells per fight | reach on missed |
  |---|---|---|---|
  | Bellringer | 0 / 20 | 22.5 | 2% |
  | Huntsman | 4 / 20 | 11.3 | 56% |
  | Shieldwall | 0 / 20 | 12.5 | 56% of 9 |
  | Pyre-priest | 2 / 20 | 8.7 | 68% |

  - Answered struck: 0. Tier deaths: 1, 5 and 0 of 30.
  - Medians: t2 118, t3 130, t4 117 (vespers +35%, sable-hold +16%).
- **Not met after two rounds:**
  - The toll's exit gap leaves it almost nowhere she stands: the bot's answer kept its own 24 px slam margin, so the gap had to cover it.
  - The Shieldwall's wits pins counter 43 of its 52 missed tells, so the counter, as designed, leaves almost nothing to land.
  - The next step would be a toll gap of about 16, with the bot's exit judged against the ring's own reach, not its margin.

### Step 4b: exposure round 3 (game side only)
- **The toll's room rule** (6043ad8, replaces `toll_gap_px`): a toll lands only where she can step out of it away from the bell with the toll radius of floor to spare inside the room (`WardenLogic.toll_room_ok`), else that slam tolls nothing.
- **A pin spares her only the rush** (599c361): a pinned tell's plain bash strikes her in its lit arc. The bot's tally no longer counts a pin as a counter, so the Shieldwall's missed-uncountered count grew from 9 to 52 (not comparable to e2).
- **r3** (x1, 2 forts x 10 per warden; answered struck 0, untold_blows 0, margins toll 0.87 s and bash 0.71 s):

  | warden | deaths | reach on missed |
  |---|---|---|
  | Bellringer | 0 / 20 | 0% of 40 |
  | Huntsman | 4 / 20 | 56% of 34 |
  | Shieldwall | 0 / 20 | 10% of 52 |
  | Pyre-priest | 2 / 20 | 68% of 38 |

  - Tier deaths: t2 1/30, t3 5/30, t4 0/20 (sable-hold not in this check). Medians t2 118, t3 130, t4 111.
- **The room rule removes the toll at both Bellringer forts.** A print on a throwaway snapshot over the same 20 runs: 0 of 142 toll beats placed a toll.
  - 110 failed the rule: beyond the slam's reach (291 px: 260 + 18 + 13) in a 640 x 490 room, she has about 30 px or less of floor behind her away from the bell.
  - 31 had her inside the ring, 1 out of the room.
  - So the Bellringer is slam-only, and `toll_every` 3 is moot. An exit anywhere in the outward half-plane (sideways along the wall) would place it; not built (last round).

### Step 4b: the toll's exit rule (replaces the room rule)
- **The rule** (c4330e7, `WardenLogic.toll_exit`): a toll lands at her spot only if an exit exists.
  - The exit is a point in the room with her centre `toll_exit_margin_px` (16) beyond both the toll's reach on her and the slam's.
  - She must reach it from where she stands within the lead less `toll_react_s` (0.6 s, the score-50 delay) at 240 px/s: 267 px.
  - Sideways along the slam's edge counts. Otherwise that slam tolls nothing; the test's corner case is a corner the slam nearly fills.
- **The bot steps to that exit** (cac7f31, fixed after the freeze, beside "missed means missed"). It is the same roll as the slam; only the step's target is the rule's.
- **Worst-case exit path:**
  - The test's 10 px grid over the three at-tier Bellringer warden rooms finds an exit at every spot beyond the slam (2447 of 2447). The longest is 90 px: margin 0.74 s.
  - Measured in r4, the longest was 98 px: margin 0.71 s.
- **r4** (x1; vespers, lantern-keep, sable-hold x seeds 1-10):
  - Answered tells struck: 0 (502 tells, 115 with a toll). untold_blows: 0.
  - Tolls placed: 138 of 143 toll beats.
  - Missed, unmuffled tolls: 10, all struck. Missed and muffled: 13.

  | fort | deaths |
  |---|---|
  | vespers | 3 / 10 |
  | lantern-keep | 0 / 10 (1 retreat) |
  | sable-hold | 1 / 10 |

  - Reach on all missed, uncountered Bellringer tells: 11 of 52 (21%).
  - t1 and P1 (6 rows) are byte-identical to ccb9a3c: the toll is gated from lever_min_tier.

### Step 4b: where it stands (margins, knobs, bot fixes)
- **Margins now** (every tell-attack, human-answerable: lead 1.714 s less the score-50 delay 0.6 s less the path out at 240 px/s; `test_wardens` prints them):

  | tell-attack | the path out | margin |
  |---|---|---|
  | slam | out of the ring (260 + 18 + 13, from the bell's edge) | 0.17 s |
  | toll | to its exit, worst case: 98 px measured (r4), 90 px on the test's grid | 0.71 s measured / 0.74 s grid |
  | lunge | out of its hit radius | 0.97 s |
  | bash | out of its reach | 0.71 s |
  | fire, phase 3 (one aimed fire, 105 px) | 118 px | 0.62 s |
  | fire with `relish_spread_px` 60 (phase 1, 72 px; 3 fires along her line from the priest) | sideways 85 px, clear of all three | 0.76 s |
  | aimed lane, sideways | out of its 20-degree half-width at the far end | 0.16 s |
  | aimed lane, stepping back | `rush_lane_over_px` 80 + her radius: 93 px | 0.72 s |

- **The knobs Step 4b added** (old -> new; none existed at 5b70259; `toll_gap_px` is gone):

  | knob | old -> new |
  |---|---|
  | bellringer `toll_radius_px` | none -> 45 |
  | bellringer `toll_every` | none -> 3 |
  | bellringer `toll_exit_margin_px` | none -> 16 |
  | bellringer `toll_react_s` | none -> 0.6 |
  | shieldwall `rush_lane_half_deg` | none -> 20 |
  | shieldwall `rush_lane_over_px` | none -> 80 |
  | pyre_priest `relish_area_every` | none -> 4 |
  | wardens `relish_dmg_mult` | none -> 1.0 |
  | wardens `lever_min_tier` | none -> 2 |
  | `tier_mix_by_fort` sable-hold brute | 0.45 (the t4 mix) -> 0.15 |
  | `tier_mix_by_fort` pale-bastion brute | 0.30 (the t3 mix) -> 0.10 |

  - `toll_react_s` is the game's human-reaction budget, and it equals the score-50 `react_delay_s` (0.6 s) on purpose: a toll lands only where a score-50 player can still answer it. The game reads its own knob, never the bot's.
- **The bot's reaction rule, frozen at 5b70259, and the fixes after the freeze** (each its own commit, revertible):
  - b1233c4, 2026-11-14: missed means missed. A missed Shieldwall tell still fed its facing, arc and reach to her stand, and a missed slam's ring was fled once out (the manager's ruling).
  - fa42e59, 2026-11-14: the toll is answered through the same roll as the slam (new tell geometry: step out of its ring).
  - 0741e80, 2026-11-14: a warden tell is seen while she kites. The living's kite came first, so a lit tell could be rolled late (the-stair s1: answered, and struck).
  - cac7f31, 2026-11-14: the toll answer steps to the exit the game's rule found, so the answer and the rule cannot disagree.
  - Movement fixes from the 3c and Step 4 reviews (not the reaction rule), all 2026-11-14: the unstick watch (5a556bc) and its restart on a room change (0aa97d6), the hold on hostile foes only (fe808e7), and the no-army leave after her reaction delay (5e2a7a9).

### Step 4b Part 2: the measurement (rows at 4bc567d, score 70 unless named)
- **The review follow-ups after the batch** change no outcome: ed366ed source guards, 91bb300 dead `_tally_pinned`, 7fc00c5 the pinned-bash rule gated on `lever_on`, 197de0c the toll's own death source, b8f4605 the fire-spread margin line. The seed-1 lines (9 at-tier forts, t1 x3, P1) are byte-identical, apart from vespers s1 now booking its two toll blows as `toll`. **The batch rows book toll deaths as `slam`.**
- **The lever** (`relish_dmg_mult`; pooled t2-t4, 9 forts x seeds 1-5): x0.75 4/45, x0.9 5/45, x1.0 5/45, x1.15 6/45, x1.35 8/45. +-5% at x1.0: 5/45 at 0.95 and at 1.05.
  - The rule, set before the main batch: x1.0, in the 10-15% band, the committed default, and 1.15 differs by one death in 45. The curve is flat from 0.9 to 1.15: crossing the fire step (0.9375) changed nothing, and 1.35 is the first point clearly out.
- **At tier, x1.0** (seeds 1-19, 19 a fort): 28/171 = 16.4% (90% 12-22), above the band.
  - Per tier: t2 11/57 (19%), t3 14/57 (25%), t4 3/57 (5%).
  - Per archetype: Bellringer 8/57, Huntsman 9/38, Pyre-priest 6/38, Shieldwall 5/38.
  - Seeds 1-5 alone gave 5/45: the curve's seeds ran low.
- **Risk:**
  - Two tiers up (the t2 party at the t4 forts, 42): 28 died, 10 retreated.
  - P1: 0/60. t1: 8/42, all at greywall (8/14, all by the living). Base had 3/18 across the three t1 forts, 2/6 of them at greywall.
  - Scores 50/70/90 (t2-t4, seeds 1-4): 16/36, 4/36, 2/36.
  - Dodge context (answer x0.6, 27 runs): 10/27 against 3/27 at x1.0.
- **Causes, the 28 deaths at tier:** lunge 9, fire 5, rush 5, toll 5, slam 3, living 1. 27 had a missed tell that struck.
- **The arms** (8 forts x 20 seeds): with the counter, deaths 27/160 = 16.9% (90% 12.6-22.3) and bad outcomes 29/160. Without it, deaths 95/160 = 59.4% (52.9-65.6) and bad 96/160.
- **Length** (median scene s, seeds 1-6, now against base 5b70259 and bfix): t2 122 (103, 107), t3 138 (115, 95), t4 120 (118, 114), t1 105 (106), P1 96 (100).
  - All seeds: t2 112, t3 130, t4 120, so the human estimate is 2.2-3.4 min (P1 1.9-2.7, t1 2.0-2.9). That is under 3-6 min.
  - Idle is at most 1.6% at every tier.
- **Reach on missed, uncountered tells at tier** (target 25-50%): Bellringer 24% (22/90; tolls struck 17 of 19 missed unmuffled), Shieldwall 17% (21/123), Huntsman 62% (42/68), Pyre-priest 70% (54/77). untold_blows: 0.
- **Four answered tells struck in Part 2** (4 rows, 3 cases; 1 at tier). The gates (r3, r4) saw none. These are found, not fixed, since a fix changes the sim:
  - vespers s11, at tier and the same run in its no-beef arm: she answered the first slam outside the warden room, and the walk in (`why=warden`) took her into the live ring. The Bellringer's answer runs only in its room.
  - pale-bastion s1, no wits: the aimed rush was answered, but she switched between goals for 0.8 s before stepping out.
  - hollow-redoubt s18, no speed: game-side. The lock point (1505, 697) lay past the room edge the Huntsman is leashed to, so the dash ran to the clamped point (1505, 669), along the room edge, not along the drawn line. Her sidestep, perpendicular to the drawn line, stood 29 px from the dash's end (catch reach 35). The drawn tell and the lunge's path disagree whenever the lock point is clamped.
- **Vei:** identical to boss-before at the final head, so V1/V2 were not re-run.

### Step 4b Part 2: the spec review's corrections
- **No tier was inside the band at Part 2:** t2 19.3%, t3 24.6% and t4 5.3%. The 4c re-measure below gives the new per-tier verdict.
- **Per archetype**, three of the archetypes had n = 38 (2 forts x 19 seeds). The 4c re-measure has 40 per two-fort archetype and 60 for the Bellringer's three forts.
- **The curve** ran 3 forts per tier x 5 seeds: 15 a tier, 45 per point.
- **What each no-counter arm takes away besides the counter** (`raid.json party`: hp 30 + 8 per beef, damage 3 + 1.2 per power, speed 90 + 10 per speed px/s):
  - Bellringer, `--raid-party-beef=5`: the t2 big drops from beef 6 to 5, under the muffle threshold of 6. Its hp falls from 78 to 70.
  - Huntsman, `--raid-party-speed=3`: speed 4 becomes 3 (130 to 120 px/s) at t2. At t3 the bigs drop from speed 4 and 6 to 3 (130 and 150 to 120 px/s). All fall under the intercept threshold of 4.
  - Shieldwall, `--raid-party-wits=0`: the t3 bigs drop from wits 4 and 4 to 0, the t4 bigs from 5, 5 and 5 to 0. That puts them under the flank threshold of 4. Wits changes nothing else in the raid: no hp, damage or speed.
  - Pyre-priest, `--raid-party-power=5`: the t3 bigs drop from power 6 and 6.5 to 5, so their hit falls from 10.2 and 10.8 to 9.0. The t4 bigs drop from 7, 7.5 and 8 to 5, so their hit falls from 11.4, 12.0 and 12.6 to 9.0. All fall under the snuff threshold of 6.
- **Reach against 25-50%:** none of the four wardens was inside it. The Bellringer (24%) and the Shieldwall (17%) were below it; the Huntsman (62%) and the Pyre-priest (70%) were above it.
- **Precision:**
  - The toll fields. `toll_missed` (19) counts the tolls on missed tells that no bracing big muffled. `toll_missed_struck` (17) counts how many of those struck her, and `toll_missed_muffled` (34) counts the missed tolls that a brace muffled. "17 of 19 missed unmuffled" means `toll_missed_struck` / `toll_missed`.
  - The idle share: Part 2's numbers pool seconds over the runs with outliers left out (more than 2x their fort's median). Pooled over the per-run splits with every row, the share is 0.1-2.1% (t1 2.1, t2 1.6). Both NOTES and the report now give the method with the number.
  - The base medians t2 103 and t4 118 hold only with the outliers left out; with every row they are 105.5 and 119.2.

## Step 4c (D-d/E): one bounded round (option b)
- **The lunge clamp** (d79f3d0, `WardenLogic.lunge_lock`): the lock point is clamped to the Huntsman's leash as the tell begins, so the drawn line is the dash's line. The test checks that the ends match at the leash edge, and that a sidestep off the drawn line by the catch reach is safe all along it.
  - Seed-1 lines: identical at every fort except hollow-redoubt, which went from beaten to dead.
  - At x1.0, seeds 1-19: 10 of 19 chime-fort rows and 3 of 19 hollow-redoubt rows moved. t1 Huntsman forts (seeds 1-3): unmoved.
  - hollow-redoubt s18, no speed: the old caught lunge now locks on an undead and misses. A later answered lunge still lands, because the bot alternates between its sidestep goal and its approach goal at the doorway under the room (a bot fault).
  - Shot: de4c-lunge-clamped.png.
- **greywall (t1) trace** (s3; all ours: `LayoutLogic.populate_enemies`):
  - The opening room holds 5 of the 22 living, the long middle room 12 and the warden room 5.
  - The army clears the opening by 7.5 s. Going for loot, she reaches the middle room's door (15 living within 250 px). 17 follow her back and wipe the 6 garrison chaff by 13.4 s, and she dies at 16.8 s.
  - The count is 22 at every t1 fort; the world.json cap only sets the mass per enemy.
  - The fix (b842fef, `enemy_room_mult_by_fort` greywall {1: 0.5, 2: 2}) gave 1/19 on seeds 1-19, **but 6/20 on fresh seeds 20-39**: it does not meet the bar (ashgate and old-sluice 0/14). The army is still gone at 13.5-16.1 s (the 18 g4c rows with an army-zero time). Traced at s20: the warden room's 12 leave it within 6 s and gather in the middle room. The spread is not the lever; their leash or the t1 garrison is. Not tried this round.
- **The lever per tier** (a80402f, c9d3f36; `relish_dmg_mult_by_tier`), picked on seeds 1-19 by the rule fixed before the runs:

  | tier | x1.0 | the other value | pick |
  |---|---|---|---|
  | t2 | 12/57 | x0.75: 7/57 | 0.75 |
  | t3 | 15/57 | x0.75: 11/57 | 0.75 |
  | t4 | 3/57 | x1.35: 7/57 | 1.35 |

  - In missed tells (her hp is 30):
    - At 0.75, slam, toll, lunge, bash and rush hit for 9 (30% of her hp; 4 kill her), and fire for 6 (20%; 5 kill).
    - At 1.35 they hit for 16.2 (54%; 2 kill), and fire for 10.8 (36%; 3 kill).
- **Re-measure at the final config** (822ed92, fresh seeds 20-39, score 70; the band is judged at score 70):
  - At tier: 25/180 = 13.9% (90% 10-19). t2 6/60 (10.0%) and t3 8/60 (13.3%) are in the band; t4 11/60 (18.3%) is above it.
  - Per archetype: Bellringer 9/60, Huntsman 6/40, Pyre-priest 9/40, Shieldwall 1/40.
  - Per fort: vespers 4, chime-fort 2, lantern-keep 0, hollow-redoubt 4, mourners-gate 3, pale-bastion 1, sable-hold 5, the-stair 0, whitecross 6 (of 20 each).
  - Causes: fire 9, lunge 6, toll 6, slam 3, rush 1. 24 of 25 had a missed tell that struck.
  - Answered tells struck: 3; 2 traced as bot faults, sable-hold s38 untraced. hollow-redoubt s33 is the doorway alternation; sable-hold s34 is the walk into a live ring outside the warden room, like vespers s11. sable-hold s38 is untraced: a slam death at 40.4 s after one tell, answered and struck, with no bell block and her army still standing (army_zero_t -1). untold_blows: 0.
  - Scores 50/70/90 (seeds 20-23): 15/36, 1/36, 1/36. Dodge, answer x0.6: 5/27 against 1/27.
  - Arms (with = the at-tier rows, same arguments): with the counter 20/160 = 12.5% (8.8-17.4), bad 22. Without, 62/160 = 38.8% (32.7-45.2), bad 67. That is 3.1x and 26 points. At chime-fort both arms are 2/20.
  - Two tiers up: 27/42 died, 12 retreated.
  - P1, ashgate and old-sluice: seeds 1-3 identical, so the Part 2 rows stand (P1 0/60).
  - greywall t1: 6/20; scores 50/90 at greywall 2/5 and 0/5.
  - Reach on missed, uncountered tells (target 25-50%): none inside. Bellringer 23% and Shieldwall 12% are below; Huntsman 66% and Pyre-priest 74% are above.
  - Length (median scene s; split pooled over runs with outliers out, the Part 2 method; the baselines ran at seeds 1-6):

    | tier | median | human estimate (low against 2:40) | base / bfix |
    |---|---|---|---|
    | t2 | 118 | 139-197 (-21 s) | 103 / 107 |
    | t3 | 123 | 141-193 (-19 s) | 115 / 95 |
    | t4 | 126 | 151-215 (-9 s) | 118 / 114 |
    | t1 | 106 | 127-186 (-33 s) | |
    | P1 | 93 | 112-162 (-48 s) | |

    Idle is 0.3-1.3% at t2-t4.
  - Lockstep held; the 9 reruns are identical.
- greywall t1, seeds 20-39 (g4cbase, 443df3d, before the room knob; seed 1 equals base): 11/20 died (90% 37-72), median army_zero_t 14.3 s, 1 death within 10 s of it, median 46 s. With the knob (g4c): 6/20 (16-48), 14.7 s, 0, 127 s. The 22 living at every t1 fort: raid_logic.gd:13 (enemy_count, living / cap x mass.enemies_per_cap 26) with the profile's living = cap x autopilot.profile_living_frac 0.85 (raid_logic.gd:133; raid.json:116, :442), all ours; in a real run the living come from the realm's seed (not ours).
- **Per fort, the m4c at-tier rows** (seeds 20-39, 20 a fort; toll split from slam):

  | fort | deaths | causes | answered struck | untold |
  |---|---|---|---|---|
  | vespers | 4 | toll 2, slam 2 | 0 | 0 |
  | chime-fort | 2 | lunge 2 | 0 | 0 |
  | lantern-keep | 0 | | 0 | 0 |
  | hollow-redoubt | 4 | lunge 4 | 1 | 0 |
  | pale-bastion | 1 | rush 1 | 0 | 0 |
  | mourners-gate | 3 | fire 3 | 0 | 0 |
  | the-stair | 0 | | 0 | 0 |
  | whitecross | 6 | fire 6 | 0 | 0 |
  | sable-hold | 5 | toll 4, slam 1 | 2 | 0 |

## The quality pass (opus review of 5b70259..5d22c9f)
- **Fixed, behaviour:**
  - 89f2151: the muffled slam spares Relish only where the lever is on. Below it (t1, the first dungeon) she takes dmg_relish x the weak point's dmg_mult again, as at 5b70259.
  - 984602b: the Shieldwall's shield is the phase's arc (`shield_half_deg`) in `hit_from` and on the glyph. A lane (20 deg) or a rush (wider) is the attack's arc only.
  - 93ec7ca, a bot fix after the freeze (the reaction delay): the stand plans against the wall before the tell until she answers it. Inside the delay it had read the live tell, and the aimed lane snapped its facing to her.
    - The other handlers read no tell geometry before `_answers` turns true. `_vs_bell` reads the toll only on leaving (answered, or a ring out in plain sight). `_dodge_step` is gated by `_answers`. `_vs_pyre` reads the fire areas only while `stepping`.
  - fd295bd: a horn over a toll's tell clears the toll. This is draw only: nothing reads it then.
  - c0d00b6: the slam's preview is drawn at radius + band/2. This is draw only (shot dq-slam-preview.png). The expanding ring already spans its band.
- **Fixed, lines byte-identical:**
  - 28962cd: `pack_rest_beats` and `pack_spawn_wall_px` moved into config.
  - 28fe990: the CAUGHT label drops the ally note where the tell bypass is on.
  - 6e7d9a5: the tests now read what they claim. The lunge's drawn end equals the dash's end with walls included, through the pure `WardenLogic.wall_clipped` and `LayoutLogic.resolve_walls`. The margins use each warden's own lead (all 1 beat, so no margin moved). The fire's radius comes from config.
  - 8f5975d: source guards.
- **Seed-1 lines** (13 raid lines and Vei, bcb7a37 against 8f5975d): only pale-bastion moved (94 -> 97 s, still beaten). t1, P1 and Vei are identical. Both Shieldwall forts were re-measured on the m4c seeds; the-stair's seed 1 had no lane in reach, but it is the same warden.
- **Before -> after** (seeds 20-39, score 70):
  - At tier: 25/180 = 13.9% (10-19) -> 26/180 = 14.4% (11-19). t4 went 11 -> 12 (the-stair 0 -> 1). Shieldwall 1/40 -> 2/40, rush deaths 1 -> 2.
  - Arms: with 20/160 -> 21/160; without 62/160 -> 71/160 (the no-wits arms answer at her delay now).
  - Scores 50/90: 15/36 -> 16/36, and 1/36 unchanged. Dodge 5/27 and two up 27/42 unchanged.
  - Shieldwall reach: 12% -> 11%. Medians: t3 123, t4 126 -> 127.
- **Notes only:**
  - The untold_blows windows are hardcoded at 1.5 and 1.0 beats, and blows outside `_answers` count. Both can only inflate the count, and it is 0, so the 0 stands.
  - The rush and the pin are not gated on `lever_on`, but no Shieldwall fort sits at t1 or in the first dungeon.
  - There is a 13 px band that neither the toll (`in_ring` adds her radius) nor the slam strikes. It is a safe gap, not a hidden hit.
  - greywall's room knob is sanctioned by the manager.
- **Re-shoot (quality pass), stills at 0398377/8350858 in reports/dungeon:**
  - dq-warden-greyscale-pack and dq-warden-greyscale-struck. In 15 sampled runs the bot took no blow while a pack stood: the warden's attacks pause and it kites the living.
  - dq-death-toll and dq-death-fire: the card now has KILLED BY and MISSED rows (0398377). The toll line had clipped at the card's edge; the widest value is now 215 of 396 px.
  - dq-roomline-lastchance, dq-danger-0phyl and dq-danger-0phyl-reduced.
  - dq-huntsman-caught: CAUGHT 1, "each catch costs Relish 9 hp · it hunts faster at 2 and 4 catches". The earlier frame fell after the Huntsman died: RAID_WARDEN died printed between the second catch at 7403 and frame 7463, and the block hides a dead warden.
  - dq-vei-victory-dim and dq-vei-victory: the button dim, then live after card.skip_after_s.
  - dq-vei-phase2-greyscale (cfabd41's rule line) and dq-vei-iframes-reduced ("SAFE 3 s").
  - The "--raid-warden skips the death card" was dev-path only and not about --raid-warden. --raid-autodie hit at process frame 0, so the 4.5 s card was gone before an N-based shot. Fixed in 8350858; seed-1 lines are identical (13/13).

## D-e: the human bracket, capture mode and the fairness floor
### Reconcile (record only; the analysis was done before D-e)
- **The two figures are the same runs.** D-d's score-70 cell (1/36, seeds 20-23) is the at-tier m4c/qm rows for those seeds.
- **Deaths per 4-seed block** (seeds 20-23, 24-27, 28-31, 32-35, 36-39; 36 runs each): 1, 2, 10, 7, 6 (26 of 180).
- **Deaths cluster by seed.** Per-seed death counts across the 9 forts have about 1.5x the binomial variance: 1.71 against 1.11 at seeds 20-39, and 1.83 against 1.23 at seeds 1-19.
- **The likely cause:** `_rng` and `_rng_react` (raid_autopilot.gd `start()`, lines 167-168 at 3a4ec38) are seeded from the run seed alone, so a seed's trace jitter and tell rolls repeat at every fort.
- **The seeding stays as it is**, because changing it would break every baseline.
- **Reporting from here on:** Wilson 90% plus a seed-clustered interval (Wilson on n_eff = n / 1.5), with configs compared paired on the same seeds.

### Step 0: the fast-forward to 3a4ec38 (economy's API v5)
- The 13 seed-1 raid lines (9 at tier, 3 at t1, P1) and Vei's seed-1 line, score 70, on `git archive` snapshots of 37fee80 and 3a4ec38: all 14 byte-identical (they also equal `qid` at 8f5975d). The m4c + qm rows at seeds 20-39 stand as the baseline (iters `de0pre`, `de0`).
- **The baseline is the bot as it stands: score 70 reacts in 0.45 s** (`react_delay_s` at 70), with no read pause and no draw. The brief's "0.6 s" is the score-50 delay, so `hb70d06` is a degraded profile, not the baseline.

### The degraded bot (D-e 2a; b895836; `raid.json autopilot.human`; each knob off unless given)
- **`--raid-autopilot-delay=<s>`** sets the one reaction delay `_delay`: the warden tell's answer, the kite from the living and the no-army leave. The miss chance stays the score's (`react_miss`): **delay and miss are decoupled** from here on, so `hb50d10` misses 0.30 of the tells and reacts in 1.0 s.
- **`--raid-autopilot-read[=<s>]`**, the read pause.
  - On her first entry into each room (the spawn room included; a doorway band is no room) she stands `<s>` scene seconds: no move, no raise.
  - The policy still runs every think, so every tell and threat is seen and rolled when it would be. A dodge off a tell she answers (`RaidLogic.DODGE_WHYS`: toll-out, bell-out, wall-out, pyre-off, the lunge's sidestep) or a due kite ends the pause.
  - **1.0 s** (the bare flag's value) is the low end of the first draft's `h` (1-3 s per room): three or four fixations on a new part of the screen at about 0.25 s each, and a click. The rest of a player's room-entry hesitation, whether to push or wait, is what the bot's hold rule already spends.
- **`--raid-autopilot-draw[=<s>]`**, the drawn circle.
  - How a human's trance spends scene time (trance.gd): holding SPACE or the right button opens it at `time_scale` 0.35; the left drag traces; the release grades and raises, and the 6 s cooldown starts only then. Focus drains in real time (`max_hold_s` 4 s, so at most 1.4 scene seconds). Releasing early is a 1 s lockout with no raise. A traced left drag is not a move click, so she cannot steer while she draws. In the game Relish keeps walking to her last click; a player stops first, or the walk drags the carried motes out of the circle.
  - The model: each raise opens the trance (`RaidTrance.bot_open`: ACTIVE, the dim, the focus bar, the split's trance bucket) and she stands `<s>` scene seconds while it is drawn. Then the circle, traced as it began, is graded and raised. A dodge off a tell she answers lets it go (`bot_cancel`: the lockout, no raise). A living foe in kite range does not: the chain still soaks the living's blows.
  - `Engine.time_scale` stays 1.0. The bot measures scene time, and a player's slowed seconds are scene seconds all the same, so lockstep holds. Real time is `RaidLogic.human_real_s`: scene + trance_s x (1 / 0.35 - 1).
  - **0.7 s** (the bare flag's value) is a 2.0 s real circle at 0.35, the middle of the first draft's 1.5-2.5 s. The aim before opening the trance and a late start after READY run at full speed and are not in it: they stay in the extra factor. Capped at `max_hold_s` x `time_scale` (1.4 s).
  - There is no extra miss for tells during a draw: the basis of `react_miss` already counts the tells that start mid-trace.
- AUTOPILOT_RESULT gains `human` {delay_s, read_s, draw_s, reads, reads_cut, draws, draws_cancelled, draws_lost} only when a knob is given. Tests: `raid_human` (RaidLogic.human_knob / draw_cap / draw_step / read_starts / human_real_s, the wiring) and the source guards.
- **Byte identity with the knobs off** (b895836 against 3a4ec38, iter `de2aid`): the 13 seed-1 lines and Vei identical.

### Capture mode (D-e 2c; d00c8c8; `RaidCapture`, off by default, local only)
- **Shawn's launch command** (from the repo root, a normal player session: the save resumes and autosaves):
  `godot --path prototypes/necropolis --capture`
  - `--capture` goes **before** any `--`. After `--` it is a user arg, and the boot rule (scripts/sim/boot_rule.gd, PLAYER_ARGS is only `--reduced-motion`) makes that a harness session: a fresh game with autosave off. Before `--` it is an engine arg; Godot passes it through, the boot rule only matches its DEV_ARGS there, and the raid reads both lists (`RaidLogic.capture_path`). No other unit's file changed. A player arg still goes after it: `godot --path prototypes/necropolis --capture -- --reduced-motion`.
  - `--capture=<path>` writes to that file instead (every test here used a scratch path, in harness sessions only).
- **The file:** `user://raid_capture.jsonl`, on Linux `~/.local/share/godot/app_userdata/Relish — Necropolis/raid_capture.jsonl` (`OS.get_user_data_dir()`; keyed by the project name, so every worktree and snapshot shares it). One JSON line per run, appended.
- **How the flag reaches the raid on the router's path:** the router (main.gd `_teleport` -> `_swap(RAID)` -> `_mount` -> `setup(args)`) passes only ids. raid.gd `_build()` runs on both paths (the router's `setup`, the standalone `_ready`) and reads the process's command line there, so nothing has to carry the flag. Dungeon runs only: the Vei fight builds no capture.
- **Hooks** (all behind `capture != null`): raid.gd `_build` creates it; `_physics_process` ticks it each live frame (after the dev bot's think, before the units move); `danger_targeted` tells it the edge warned; `RaidEndings.finish` writes the record synchronously before the emit (a death after its beat or card, the win, a retreat, the router's window close through `close_request`); raid.gd `_notification` writes on a standalone window close (`closed`) or as a scene is freed with no ending (`freed`).
- **The record** (`v` 1, `kind` "raid_capture"):
  - `at` (local time), `fort`, `tier`, `first_dungeon`, `held`, `run_id`, `seed_rev`, `archetype`, `bot` (the measuring bot played it);
  - `outcome` (`warden_beaten`, `relish_died`, `retreated`; `timeout` for the measuring bot's time-out away from an exit; `closed` / `freed` when nothing finished, unless an ending beat was playing: a standalone close during the death beat records `relish_died` with its killer, `RaidLogic.capture_unfinished`; the quality pass, D-e task 6), `closed` (a window close ended it: the router books it as a retreat, or a death during the death beat);
  - `killed_by` (Relish.last_hit_src, the death card's source) and `missed_tell` (RaidLogic.death_tell: "the swing", "the ring at your feet", "the line", "the lit arc", "the marked ground"; "" for the living or a pack);
  - `scene_s` (live scene seconds: physics steps to the death or the chest, as the bot's `duration_s`), `wall_live_s` (wall-clock seconds over those steps), `wall_s` (wall clock from the build to the write: the death card and the victory beat included);
  - `rooms`: per room she stood in, `room`, `role` (spawn, ante, warden, checkpoint, room), `first_s` (scene time of the first entry), `entries`, `scene_s` and `wall_s` spent there (`Time.get_ticks_msec` per physics step; a doorway band counts to the room she came from);
  - `tells`: per tell-attack (slam, toll, lunge, bash, rush, fire): `tells`, `shown` (she stood in the warden's room as it began), and one outcome each, first match: `struck` (a blow of it reached her: Relish.hits), `countered` (muffled, intercepted, pinned, an acolyte snuffed during it), `dodged` (aimed at her: the danger edge warned through its tell, `raid.danger_targeted`; a toll is aimed by being placed at her feet), `clear` (never aimed at her), `cancelled` (a horn, the warden's fall or the run's end took it before it struck);
  - `raises`, `relish_hits` (blows that reached her, by source).
- **Classification is the game's, never the bot's:** the warden's own state (the Bellringer's `_tell_for`, `_slam_beat`, `toll_marks`, `slams_muffled`; the Huntsman's `_locked`, `_lunges`, `intercepts`, `_lock_undead`; the Shieldwall's `_tell_for`, `rushing`, `pinned_tell`, `bashes`; the Pyre-priest's `_tell_for`, `lit`, `burns`, `snuffs`), Relish's `hits`, and the danger edge. A pinned Shieldwall tell is a `bash` (its plain bash is what lands; the pin is its counter). It reads the frame before, as the bot does, and once more at the write, so the killing blow is in it.
- **The four checks** (at d00c8c8; rows `decapoff`, `decapon`, `decaphb` in the raw file; the router probes on a throwaway SceneTree script, harness sessions only):
  - **(a) The bot's lines don't move with capture on.** On against off: 31 of 31 lines byte-identical (the 13 seed-1 lines, plus seeds 2-3 at the 9 at-tier forts). With the degraded bot (hb70d10 flags, seed 20, 9 forts) and capture, the lines equal the sweep's b895836 rows 9 of 9. Off, d00c8c8 equals de2aid 13 of 13.
  - **(b) Capture's game-side counts against the bot's `tell_tally`.** 40 runs (seeds 1-3 at tier, the 9 degraded runs, t1 and P1 seed 1). Outcome, `killed_by` and `scene_s` equal the bot's `exit`, `killed_by` and `duration_s` in 40 of 40.
    - **The evidence, kept** (a re-run of the same 40 at 187fb96 after the spec review, iter `decapchk`): one row per run in the run's `reports/dungeon/de-capture-check.tsv` (capture's tells, shown, struck, countered, dodged, clear and cancelled beside the bot's `tell_tally`, and five equality flags), and each run's capture record with its run key in `reports/dungeon/de-capture-check.jsonl`. Tells (the Bellringer's slam tells: a toll rides its slam's tell, which the bot counts once), struck, outcome, `killed_by` and `scene_s` are equal in 40 of 40. At tier the counts are the table's below; t1 and P1 differ (greywall's room leash is on at 187fb96: 53 tells, 3 struck) and match the same way.

    | warden (runs) | tells: capture / bot | struck: capture / bot | countered: capture / bot | dodged, clear, cancelled |
    |---|---|---|---|---|
    | Bellringer at tier (12) | 278 slam + 67 toll / 278 | 7 (toll 7) / 7 | 146 slam (every muffle) + 30 toll / 28 | 37, 109, 16 |
    | Huntsman at tier (8) | 132 / 132 | 9 / 9 | 22 (every intercept) / 3 | 95, 3, 3 |
    | Shieldwall (8) | 25 rush + 78 bash / 103 | 2 / 2 | 68 (pinned) / 0 | 20, 2, 11 |
    | Pyre-priest (8) | 76 / 76 | 10 / 10 | 4 (a snuff during a tell) / 0 | 50, 11, 1 |
    | t1 and P1 (4) | 99 / 99 | 6 / 6 | 0 / 0 | 72, 20, 1 |

    - Tells and struck match exactly at every warden. Struck also equals the tell-attack blows in `relish_hits`.
    - Countered differs by construction. The bot books a counter only on a tell it missed (an answered tell's muffle or intercept is not counted). It has no counter at the Shieldwall (a pin spares her only the rush) or at the Pyre-priest. Capture counts every counter that fired during a tell.
    - Dodged has no bot counterpart: the bot counts answered tells, which include tells that never threatened her.
    - Cancelled: tells a horn cut, or a tell open when the warden fell or the run ended.
  - **(c) The router path.** `--capture=<path>` before `--`, with `--new-game --teleport=old-sluice` after it: the map dives, the router opens the raid with run_id 1 (`_standalone` false, `_from_run` true), and capture is on. After `--` it works too, as a harness session.
  - **(d) Flushes.**
    - A window close through the router writes `retreated`, `closed` true, and the router applies the retreat.
    - A death writes `relish_died`, `killed_by` slam, `missed_tell` "the swing", after the death card.
    - A close during the death beat writes `relish_died`, `closed` true.
    - A standalone close (no ending) writes `closed`.
    - The bot's deaths write through the same `finish`.

### The sweep (D-e 2b; b895836; seeds 20-39; 1,160 runs, all in lockstep)
- **Profiles:** scores 50 and 70 x delays 0.6, 1.0 and 1.5 s, all with the read pause (1.0 s) and the draw (0.7 s), at the 9 forts at their tier (iters `hb<score>d<delay>`, 180 runs each). Plus the typical human at t1 and P1 (`hbt1`, 80 runs). The baseline is m4c + qm, the bot as it stands: score 70, 0.45 s, no read, no draw.
- **Length and deaths at t2-t4.** Medians in scene seconds; "real" is the median of `RaidLogic.human_real_s` per run; the split is pooled seconds with each fort's > 2x outliers left out (the Part 2 method); deaths with Wilson 90% and the seed-clustered interval (Wilson on n / 1.5). The 31 runs that retreated (left with no army, or gave up: 2 to 8 per profile, hbt1 included) stay in the medians and count as neither a death nor a win:

  | profile | median s (t2 / t3 / t4) | real s | travel / fight / trance / idle % | died |
  |---|---|---|---|---|
  | baseline (70, 0.45 s) | 123 (118 / 123 / 127) | 123 | 8.8 / 90.4 / 0 / 0.8 | 26/180 = 14.4% (11-19; 10-21) |
  | 70, 0.6 s | 140 (140 / 151 / 126) | 160 | 8.1 / 82.2 / 7.7 / 2.0 | 27/180 = 15.0% (11-20; 10-21) |
  | **70, 1.0 s (the typical human)** | **132 (127 / 140 / 131)** | **150** | 8.2 / 82.0 / 7.6 / 2.2 | 27/180 = 15.0% (11-20; 10-21) |
  | 70, 1.5 s | 117 (118 / 120 / 106) | 133 | 8.1 / 81.5 / 7.9 / 2.5 | 95/180 = 52.8% (47-59; 45-60) |
  | 50, 0.6 s | 144 (148 / 149 / 134) | 165 | 7.1 / 82.9 / 8.0 / 2.0 | 84/180 = 46.7% (41-53; 39-54) |
  | 50, 1.0 s | 144 (143 / 151 / 139) | 164 | 6.8 / 83.1 / 8.0 / 2.1 | 80/180 = 44.4% (38-51; 37-52) |
  | 50, 1.5 s | 128 (131 / 126 / 118) | 150 | 7.3 / 82.0 / 8.4 / 2.3 | 121/180 = 67.2% (61-73; 60-74) |

  - **Per tier, every profile** (60 runs each; the split pooled per tier with that tier's > 2x outliers left out; Wilson 90% in %, then the clustered interval):

  | profile, tier | median s (survivors) | travel / fight / trance / idle % | died (W90; clustered) |
  |---|---|---|---|
  | baseline, t2 | 118 (116) | 5.1 / 93.6 / 0.0 / 1.3 | 6/60 (5-18; 5-21) |
  | baseline, t3 | 123 (120) | 10.3 / 88.7 / 0.0 / 1.0 | 8/60 (8-22; 7-25) |
  | baseline, t4 | 127 (127) | 10.8 / 88.9 / 0.0 / 0.3 | 12/60 (13-30; 12-32) |
  | 70, 0.6 s, t2 | 140 (132) | 4.3 / 85.1 / 8.8 / 1.9 | 7/60 (6-20; 6-23) |
  | 70, 0.6 s, t3 | 151 (150) | 8.3 / 82.7 / 6.8 / 2.1 | 9/60 (9-24; 8-26) |
  | 70, 0.6 s, t4 | 126 (127) | 12.0 / 78.5 / 7.3 / 2.1 | 11/60 (12-28; 10-30) |
  | 70, 1.0 s, t2 | 127 (127) | 4.5 / 84.3 / 8.9 / 2.3 | 9/60 (9-24; 8-26) |
  | 70, 1.0 s, t3 | 140 (140) | 8.1 / 83.1 / 6.6 / 2.1 | 8/60 (8-22; 7-25) |
  | 70, 1.0 s, t4 | 131 (134) | 12.0 / 78.5 / 7.3 / 2.1 | 10/60 (10-26; 9-28) |
  | 70, 1.5 s, t2 | 118 (116) | 4.4 / 84.6 / 8.8 / 2.3 | 27/60 (35-56; 33-58) |
  | 70, 1.5 s, t3 | 120 (119) | 7.8 / 82.3 / 7.2 / 2.7 | 34/60 (46-67; 44-69) |
  | 70, 1.5 s, t4 | 106 (131) | 12.8 / 77.1 / 7.7 / 2.5 | 34/60 (46-67; 44-69) |
  | 50, 0.6 s, t2 | 148 (140) | 3.5 / 85.0 / 9.5 / 2.0 | 35/60 (48-68; 45-70) |
  | 50, 0.6 s, t3 | 149 (145) | 8.0 / 83.1 / 6.9 / 2.0 | 23/60 (29-49; 27-51) |
  | 50, 0.6 s, t4 | 134 (132) | 10.0 / 80.4 / 7.7 / 1.9 | 26/60 (33-54; 31-56) |
  | 50, 1.0 s, t2 | 143 (129) | 3.4 / 84.9 / 9.6 / 2.2 | 35/60 (48-68; 45-70) |
  | 50, 1.0 s, t3 | 151 (144) | 7.1 / 83.6 / 7.0 / 2.2 | 23/60 (29-49; 27-51) |
  | 50, 1.0 s, t4 | 139 (136) | 10.1 / 80.5 / 7.4 / 1.9 | 22/60 (27-47; 25-50) |
  | 50, 1.5 s, t2 | 131 (138) | 3.8 / 84.9 / 8.9 / 2.4 | 44/60 (63-82; 61-83) |
  | 50, 1.5 s, t3 | 126 (128) | 7.8 / 81.7 / 8.1 / 2.3 | 40/60 (56-76; 54-78) |
  | 50, 1.5 s, t4 | 118 (142) | 10.9 / 78.8 / 8.2 / 2.2 | 37/60 (51-71; 49-73) |

  - **Paired by seed** (fort and seed), deaths in only one of the two: baseline vs 70 at 1.0 s, 20 against 21 (median length +8 s). 70 at 0.6 vs 1.0 s, 15 against 15. 50 at 0.6 vs 1.0 s, 30 against 26. 70 at 1.0 vs 1.5 s, 8 against 76. 50 at 1.0 vs 1.5 s, 17 against 58. 70 vs 50 at 1.0 s, 7 against 60.
  - **What sets the risk is the miss chance, not the delay, up to 1.0 s.** From 0.45 to 1.0 s at score 70 the deaths do not move. Answered tells that struck: 3 of 2,116 at the baseline, 8 of 2,212 at 1.0 s. At 1.5 s they jump to 201 of 1,691. The Shieldwall's answered-and-struck tells go 0 -> 7 from 0.6 to 1.0 s (both scores), the one place the lane's negative 1.0 s margin shows.
  - The read pause and the draw put 7-8% of each run in the trance and lift idle to about 2%. With the draw's real-time stretch (x 1/0.35 inside the trance) the typical human's runs are 150 s real against the baseline's 123.
  - **t1 and P1** (the typical human, seeds 20-39):
    - P1: 0/20, median 113 s (real 133).
    - t1: 16/60 (27%; 18-37, clustered 17-39), all killed by the living. greywall accounts for 10/20 (median 41 s: early deaths, against 6/20 for g4c, the frozen bot on the same seeds), old-sluice 4/20, ashgate 2/20. The kite's 1.0 s delay and the read pause on entering its long middle room are the mechanism; greywall's living were already the t1 risk.
- **Per tell-attack** (deaths; blows that struck her / tells; at-tier rows of each profile). The slam's tells are every slam rung at the Bellringer forts (`warden_attacks`), so the slams that carried a toll are counted there too; the toll's tells (`bell.tolls`) are that subset, not more tells:

  | profile | slam | toll | lunge | bash | rush (the lane) | fire |
  |---|---|---|---|---|---|---|
  | baseline | 3; 10/1214 | 6; 22/272 | 6; 39/380 | 0; 0/391 | 2; 9/105 | 9; 37/291 |
  | 70, 0.6 s | 0; 8/1368 | 8; 36/338 | 6; 43/506 | 0; 0/319 | 6; 40/279 | 6; 34/289 |
  | 70, 1.0 s | 1; 10/1267 | 8; 30/298 | 5; 41/436 | 0; 0/344 | 5; 34/233 | 7; 28/249 |
  | 70, 1.5 s | 3; 8/947 | 27; 67/223 | 6; 29/338 | 0; 2/329 | 22; 61/94 | 35; 101/157 |
  | 50, 0.6 s | 10; 38/1631 | 34; 90/397 | 13; 67/497 | 0; 0/382 | 16; 60/257 | 10; 55/264 |
  | 50, 1.0 s | 10; 27/1598 | 34; 93/393 | 11; 53/404 | 0; 0/439 | 13; 53/188 | 12; 55/288 |
  | 50, 1.5 s | 10; 27/1136 | 35; 86/243 | 17; 75/505 | 0; 1/385 | 20; 62/101 | 37; 100/169 |

  - **Which attacks start to kill first: the fire, the lane and the toll, at 1.5 s.** Pooled over both scores, from 1.0 to 1.5 s:
    - the fire: deaths 19 -> 72, blows per tell 0.15 -> 0.62;
    - the rush (at tier a rush that reaches her is the aimed lane): 18 -> 42, 0.21 -> 0.63;
    - the toll: 42 -> 62, 0.18 -> 0.33.
    - Answered tells that struck at 1.5 s, score 70: Pyre-priest 87 of 136, toll 55, Shieldwall 55 of 386. Their margins at 1.5 s are fire -0.28, toll -0.19 and the lane's step back -0.17 s.
  - The slam (11 -> 13 deaths, 0.013 -> 0.017) and the lunge (16 -> 23, 0.11 -> 0.12; its margin is +0.07 s at 1.5 s) barely move.
  - The slam's worst case (a 226 px walk from the bell's edge, -0.23 s at 1.0 s) is a spot the bot seldom holds when a tell starts. It goes in only when the trip in and out fits before the tell (the beat clock), so at the tell it is near the ring's edge or outside it. A human who stands at the bell is in that worst case; the bot never is.
- **The step-6 gate** (the typical human, score 70 at 1.0 s with the read pause and the draw):
  - At t2-t4 the medians are 127 / 140 / 131 scene seconds, which is **148 / 152 / 150 s real**: 2:28-2:32, 28-32 s under Shawn's 3:00.
  - The degraded bot's scene time, with the trance's stretch, is the human estimate for what it models: the reaction delay, a read per room and a 2.0 s circle.
  - **An extra factor still applies** for what it leaves out:
    - the aim before opening the trance and a late start after READY: 0-1.5 s a raise (with a 2.5 s circle);
    - click-to-move detours: 0.1-0.3 of the travel seconds;
    - 0-2 s more per room than the 1.0 s read;
    - 0-0.4 s per warden tell.
  - **At the midpoints** (the spec review's figures: 0.75 s of aim per raise, 0.2 x the travel seconds, 1 s more per room read, 0.2 s per tell, with the 2 s circle) the medians are **172 / 173 / 177 s at t2 / t3 / t4, with 40-45% of runs at 180 s or more: at or just under 3:00.** My recompute of the same terms (the per-run read count for the rooms, `react.tells` for the tells) gives 168 / 169 / 173 s with 32-45% at 180 s or more; the gap is in how the terms are counted, and the reading is the same.
  - At the high end (1.5 s a raise, 0.3 x travel, 2 s a room, 0.4 s a tell) the medians are 187 / 187 / 193 s.
  - Per warden at tier, real: Bellringer 156 s, Shieldwall 158, Huntsman 144, Pyre-priest 142.

### The fairness floor (D-e 2d): not built
- **The arithmetic** (test_wardens now prints the margins at 1.0 s as well): lead 1.714 s - delay - walk. At 0.6 s: slam 0.17, lane sideways 0.16, toll 0.74, lunge 0.97, bash 0.71, fire 0.62 s. At 1.0 s: slam -0.23, lane -0.24, toll 0.34, lunge 0.57, bash 0.31, fire 0.22 s.
- **The rule:** per tell-attack, blows that struck her per tell, at-tier rows of scores 50 and 70 pooled, 0.6 -> 1.0 s. The slam or the lane kills out of proportion if its growth is at least 2x the pooled growth of the toll, lunge, bash and fire, and its deaths rise.
  - **When it was written:** the x2 rule sits in calibration-dd-log.txt's D-e header (line 335), above every sweep line. The log has no timestamps and isn't in git, and the rule wasn't in a committed file before the rows ran, so its timing can't be verified independently.
- **The sweep does not confirm it.**
  - The slam grows x0.84 (0.0153 -> 0.0129; deaths 10 -> 11).
  - The rush grows x1.11 (0.187 -> 0.207; deaths 22 -> 18).
  - The positive-margin attacks pooled grow x0.97.
  - The recompute: slam x0.84 and lane x1.11 against x2, which is x0.87 and x1.14 relative to the pooled growth. The verdict holds by a wide margin either way. No lead was added, and the 1.0 s profiles were not re-run.
  - From here on, a decision rule goes into a committed file, or a message to the manager, before its rows run.
- A lead was drafted while the sweep ran and dropped on the verdict, uncommitted: `lever_lead_beats` in WardenLogic.spec, with the toll's landing rule kept on the base lead. The lane would have needed its rush-or-lane decision moved to the earlier tell start (it is made in `_begin_tell`).
- What the sweep does show is above: past 1.0 s the fire, the lane and the toll go first, in line with their margins at 1.5 s. If the risk at tier is to hold for a slower player, those three are where the floor belongs. That is a design call, not this rule's.
- **Byte identity with every new knob off** (the head's code is d00c8c8; bc57a91 changes only a test): the 13 seed-1 lines are identical to 3a4ec38 and 37fee80 (`decapoff` against `de2aid`, `de0`), and Vei's seed-1 line is identical. `tests/parity_check.sh`: 5 of 5 identical. Suite: 52 suites, all passed.

## D-e task 3: greywall (t1), the pick rule (written before the pick rows)
- **Both targets, at the realm's count (22 living), the profile's 6-chaff garrison:**
  1. Frozen bot (score 70): at most 1/20 deaths over seeds 20-39 and at most 1/19 over seeds 1-19.
  2. Typical human (score 70, `--raid-autopilot-delay=1.0 --raid-autopilot-read=1.0 --raid-autopilot-draw=0.7`): at most 2/20 over seeds 20-39, and no more deaths than ashgate and than old-sluice under the same profile on the same seeds (so at most the smaller of the two).
- **The pick is the smallest change that meets both.** Candidates in order of size, config first (greywall's `enemy_room_mult_by_fort`): A the current {1: 0.5, 2: 2}; B {1: 0.35, 2: 2.5}; C {0: 1.5, 1: 0.4, 2: 2}; D {1: 0.25, 2: 4}. The first that meets both is the pick. If none does, the leash in code (a per-fort rule, gated so only greywall moves), its smallest setting that meets both.
- **Rows before this commit:** the measurement rows only (iters g3p-, g3f-, g3h-, g3hf-, g3h-ash/-slu: the current knob and the knob off, both counts, frozen bot and typical human), started before the rule was committed. They include candidate A's rows. Every candidate row other than A comes after it. The rows carry no timestamps: "after the rule" rests on file order in the jsonl and on commit order, and c6d6e65 itself says the A and knob-off rows started before it.
- **The leash candidates, fixed before any leash row (config B, C and D were still running; B failed both targets):** the leash (`enemy_leash_by_fort`, code in this commit's neighbours) on top of the current room weights A. In order of size: L1 rooms [2] (the warden room's living hold until she enters it); L2 rooms [1, 2]. The first that meets both targets is the pick. If neither does, the report says so.
- **What the realm hands greywall (read-only, a throwaway headless script; no save):** `cmd_begin_dungeon("greywall")` from a fresh game and from the day1 fixture give the same seed. Living 76.5 = cap 90 x realm.json:21 `start_living_frac` 0.85 (`scripts/sim/state_runs.gd:45` `f["living"]`) -> 22 enemies (`scripts/raid/raid_logic.gd:13`), the same as the profile's 22. Garrison units 0 (`scripts/sim/state_runs.gd:46`, `_garrison` at `scripts/sim/game_state.gd:493`: floor(fort undead 0 / 10)), party 0, starters 0 (not the first dungeon), undead 0, dead 0, warden huntsman, relish_hp 30. The midgame_2flips fixture gives living 76.5 (22 too), garrison 1; pre_vei living 0. So the count is the profile's; the profile's 6 chaff garrison (`configs/raid.json:455`; :451 is `profile_living_frac`) is more than the realm's day1 seed gives. Raided as seeded (`--raid-fixture=day1,greywall`) she has no army at all: the bot retreats at about 1 s (0/39 deaths, 39 retreats, both knob states), so that is not a measurable fight and the profile stands in. A per-fort multiplier on the realm's garrison would multiply 0; none was added.
- **Config cannot reach it.** The room weights only move where the 22 stand (their positions are fixed per fort, only the bot's rolls vary by seed). Rows at the profile (22 living, 6 chaff), frozen bot seeds 1-19 / 20-39, then the typical human (70, delay 1.0, read 1.0, draw 0.7) seeds 20-39:

  | config | frozen 1-19 | frozen 20-39 | human 20-39 | human median s |
  |---|---|---|---|---|
  | knob off (g3p-off) | 9/19 | 11/20 | 10/20 | 79 |
  | A {1: .5, 2: 2} (today) | 1/19 | 6/20 | 10/20 | 41 |
  | B {1: .35, 2: 2.5} | 6/19 | 6/20 | 17/20 | 33 |
  | C {0: 1.5, 1: .4, 2: 2} | 4/19 | 5/20 | 9/20 | 109 |
  | D {1: .25, 2: 4} | 5/19 | 4/20 | 16/20 | 27 |
  | **L1 leash room 2 on A** | **0/19** | **0/20** | **3/20** | 130 |
  | L2 leash rooms 1, 2 on A | 0/19 | 0/20 | 5/20 | 119 |
  | ashgate, same human profile | | | 2/20 | 100 |
  | old-sluice, same human profile | | | 4/20 | 112 |

  Wilson 90%: L1 frozen 0-12 and 0-12, human 6-32; ashgate 3-26, old-sluice 9-38. A, B, C, D all fail the frozen target; A, C and D hold the median at 109-149 s only by leaving 4-6 of 20 dead.
- **The leash** (`enemy_leash_by_fort`, `RaidLogic.leash_rooms` / `leash_holds`, `RaidUnit.leash_hold`, `RaidPopulate`; e83b760): the living of a listed room act like the detour's guard, turning only on her undead inside their room, until she first steps into it, then fight as any foe. Greywall room 2 (the warden room's living). Per fort; no other fort has an entry, so they cannot move.
- **The pick, by the rule above: none meets both.** L1's 3/20 fails both parts of the human target: it is over the 2/20, and it is worse than ashgate's 2/20 (old-sluice's is 4/20). It meets the frozen target (0/19, 0/20). The committed rule only said "if none does, the leash" (c6d6e65) and "if neither does, the report says so" (834c716): choosing L1 over L2 (3 human deaths against 5, frozen tied) came after the rows, and "closest" was my word, not the rule's. The manager accepted L1 on 2026-11-15 because the gap is inside the noise (Wilson 6-32%).
- **How L1 died for the human, and how the army fared.** The L1 and L2 rows (sha label e83b760) were run as a `--proj` probe: a copy of the e83b760 tree whose `configs/raid.json` had greywall's leash set to `"rooms": [2]` (L1) or `[1,2]` (L2), imported and run with the runner's `--proj` (the `--sha` is only a label; the committed config at e83b760 was `[]`). Re-run on a snapshot of the committed 0cdc2c7 (iters g3v-h, g3v-p; human seeds 28, 37, 39 and frozen seeds 1, 20, 30) the six result lines are byte-identical to the L1 rows. The three human deaths (g3h-L1 seeds 28, 37, 39): `army_zero_t` 12.3, 11.0 and 13.1 s with `army_zero_s` only 0.5, 2.9 and 0.6 s, the army still 10, 8 and 12 strong 5 s before she died; she died at 38, 52 and 47 s, after the warden woke at 35.5, 40.4 and 42.7 s. So the human's army was wiped early (about 11-13 s) and rebuilt, and the deaths came in the warden fight, not the early pile-on. For the frozen bot the army fell at all in only 2 of the 39 g3p-L1 runs.
- **Greywall stays a t1 fort with a fight:** L1 medians 107-114 s frozen (ashgate and old-sluice t1 127-186 s human real, 100 and 112 s scene under the human profile; greywall human 130 s scene), for the frozen bot the army's first zero comes at 22-25 s in the 2 of 39 runs where it falls at all (against 14 s at A); the leash slows the clear, it does not empty the fort. The human's army zero is at 11-13 s (above).
- **Identity:** the 12 seed-1 lines (9 at tier, ashgate, old-sluice, P1 old-sluice) are byte-identical between 5f57365 and the leash on (0cdc2c7); greywall's t1 line moves on purpose (the re-pin). Vei's seed-1 line and `parity_check.sh` identical. Rows: iters g3p-*, g3h-*, g3id-* in reports/dungeon/calibration-dd-raw.tsv(.jsonl). Rows before the rule's commit (c6d6e65): the measure rows (g3p-on/off, g3f, g3h-on/off, g3hf, g3h-ash/-slu); after it: B, C, D, L1, L2.

## D-e task 4: the Shieldwall's reach
- **Reach** is the share of missed, uncountered Shieldwall tells whose blow reached her (`tell_tally`: missed_struck / (missed - missed_countered); a pin is not a counter, 599c361). At seeds 20-39, frozen bot (score 70, 0.45 s), qm rows: 9 / 83 = 11%.
- **Guards (the manager's):** answered-but-struck Shieldwall tells must not rise: 0 for the frozen bot (qm), 7 at 1.0 s (hb70d10 4, hb50d10 3, all at the-stair). No margin below today's at 0.6 s (bash 0.71, lane 0.16 sideways / 0.72 back); the lane is not narrowed and its sideways walk not lengthened. `untold_blows` 0. t1, P1 and Vei byte-identical; any new rule gated on `lever_on`.

### Step 1: why 89% of the missed tells don't reach her (measuring only)
- **The probe:** a throwaway copy of 3cbb6e3 printing one line per bash tell from `RaidShieldwall` (pinned / lane / rush; her distance and bearing off the facing as the tell began and at the blow; the bot's roll for it; the blow). Its 40 AUTOPILOT_RESULT lines (pale-bastion t3, the-stair t4, seeds 20-39, score 70) are byte-identical to qm (40 of 40), and the typical-human copy (score 70 and 50 at 1.0 s, read 1.0, draw 0.7) to hb70d10 / hb50d10 (80 of 80). So these are the same runs; nothing was decided on them. Per tell: the run's `reports/dungeon/de-t4-shield-tells.tsv`.
- **Of all tells, 397 of 496 that came to a blow were pinned (80%).** 92 of the 99 unpinned ones were already the lane aimed at her (the other 7: she was outside its room, a wide rush).
- **The 83 missed, uncountered tells** (the side stand: 223 px out, 110 deg off the facing, within 15 px and 12 deg):

  | why it did not reach her | tells | share |
  |---|---|---|
  | pinned: a plain bash, her at her side stand at the blow | 55 | 66% |
  | (of them, walked there during the tell, the wall having turned) | (14) | |
  | cut before the blow (a horn over the tell, the warden's fall, the run's end) | 8 | 10% |
  | the lane: she walked off it sideways by chance (going to a new stand) | 5 | 6% |
  | pinned: a plain bash, her elsewhere, out of its arc or reach (walking in, fetching) | 5 | 6% |
  | pinned late (the pin under a beat old) | 1 | 1% |
  | the lane not aimed (a wide rush, her out of its room) | 0 | 0 |
  | the lane ended short | 0 | 0 |
  | **struck** (all 9 the lane) | 9 | 11% |

- **Traced:** pale-bastion s20 beat 12: pinned, she at 223 px and 110.6 deg off, still there at the blow, the bash's ±80 deg out to 140 px misses. pale-bastion s23 beat 79: the lane aimed at her at 80.9 deg off the old facing (she was 197 px out, still walking to the stand), at the blow 25.8 deg off a 20 deg lane. pale-bastion s33 beat 59: the lane at her side stand, she stands still (missed), struck at 0.0 deg.
- **The ceiling of the brief's levers:** if every missed lane struck, reach would be 14 / 83 = 17%. The aim rate (92 of 99 unpinned tells), the rush's reach and the lane's end touch 0 of the misses. A plain bash that reached her stand would need 223 px and ±110 deg: a longer or wider bash lowers the bash's 0.71 s margin, and the bot reads `attack.reach_px` and `front_half_deg()` before the tell, so its stand moves out with it; aimed at her without the reach it still misses (223 > 140 + 13). The cause is the game's: a pinned bash cannot reach the stand a player keeps on its side, and 80% of tells are pinned.
- **At 1.0 s** (the 7 answered and struck): all at the-stair, all unpinned lanes early in the fight (beats 4-12) with her 453-537 px out as she walked in. The sideways walk there is 168-197 px against the 171 px a 1.0 s reaction leaves (462 px out). No pinned tell of the 1,191 probed (frozen and 1.0 s, of 1,700 that came to a blow) began beyond 462 px; all but 12 began within 300 px.
- **With the pin counted as a counter** (as a muffle, an intercept or a snuff is at the other wardens; the manager's question, for the side-by-side): today's 83 split into 66-68 pinned and 15-17 unpinned. The tally books every tell the bot saw: 536 = 496 that came to a blow + 21 a horn cut (all pinned, in de-t4-shield-tells.tsv) + 19 still open at the warden's fall or the run's end (not in the tsv; their kind is the run's `shield.pins` and `rushes` less the tsv's). 8 of those 40 were missed: 5 pinned, 1 unpinned (pale-bastion s33, an open lane at the end), and 2 either (pale-bastion s26 and s36: a pinned horn-cut tell and an unpinned open one, one of them missed). Reach on the missed, unpinned tells is then 9 / 15-17 = 53-60% for the frozen bot, and 30 / 39-40 = 75-77% at 1.0 s (hb70d10: 104 missed, 58 pinned and 39 unpinned came to a blow, 7 cut of which 6 pinned and 1 either).

### The decision: option A, a pin is the Shieldwall's counter in reach (the manager, 2026-11-15)
- **The definition from D-e task 4 on:** a pinned Shieldwall tell is countered, as a muffled slam or an intercepted lunge is. Reach = struck / missed and uncountered, with the pinned tells out of the denominator. Nothing in the game changed; no candidate rows ran.
- **The manager's condition, that the pin is shown to be the preparation,** holds on the existing arm rows (seeds 20-39, score 70; checked by the coordinator, re-counted here from the raw rows):

  | | with wits (qm) | wits 0 (qarmo) |
  |---|---|---|
  | pale-bastion | 1/20 died | 12/20 |
  | the-stair | 1/20 | 15/20 |
  | both | 2/40 = 5% (Wilson 2-14%; clustered 1-17%) | 27/40 = 68% (55-78%; clustered 52-80%) |
  | pins / bashes (`shield`) | 431/496 (87%) | 0/586 |
  | deaths by | rush 2 | rush 27 |

- **Reach under both definitions** (seeds 20-39; frozen bot = m4c, with qm for the Shieldwall forts; the typical human = hb70d10; struck / missed less countered). The bot's tally books no counter at the Pyre-priest (an acolyte's snuff takes fires away rather than countering a tell), so its two columns are one:

  | warden | frozen, old | frozen, new | typical human, old | typical human, new |
  |---|---|---|---|---|
  | Bellringer | 26/112 = 23% | the same | 35/103 = 34% | the same |
  | Huntsman | 38/58 = 66% | the same | 40/61 = 66% | the same |
  | Shieldwall | 9/83 = 11% | 9/15-17 = 53-60% | 30/104 = 29% | 30/39-40 = 75-77% |
  | Pyre-priest | 37/50 = 74% | the same | 28/40 = 70% | the same |

  The Shieldwall's range comes from the probe and the rows' `shield` counts: 2 missed cut tells at the frozen bot and 1 at 1.0 s cannot be told pinned or not (above). Corrected after the spec review (it had 47-64% and 71-77%).
- **The grading pass computes both directly:** `tell_tally` gains `missed_pinned` (missed tells whose tell was pinned, booked as the bot first sees it; the pin is decided as the tell begins and holds through its blow) and `missed_pinned_struck` (of them, a plain bash that struck her). Measuring only, in the Shieldwall's lines only. New reach = (missed_struck - missed_pinned_struck) / (missed - missed_countered - missed_pinned); old = missed_struck / (missed - missed_countered). Capture already books a pinned tell as `countered` (`tells.bash`, D-e 2c).
- **The answered-but-struck guard** (0 frozen, 7 at 1.0 s over scores 50 and 70) is reported in the grading pass, at both profiles. Nothing here moves it: no game change.
- **t4 stays at x1.35**; seeds 40-59 grade it.

### Option B, kept off as a lever for later: `attack.rush_lane_every` (default 0)
- **The rule** (`WardenLogic.lane_due`, `RaidShieldwall._begin_tell`; gated on `lever_on`): on every `rush_lane_every`-th bash tell since the wake (counting every tell, pinned or not), a tell a wits flanker pins is the aimed lane at her all the same, where a lane can be aimed (her in its room). The pin still holds the rush off the other tells. The lane's geometry is unchanged, so every margin is too. `--raid-shield-lane-every=<n>` (dev, standalone) sets it for one run. AUTOPILOT_RESULT `shield.pin_breaks` only with it on.
- **Its readable tell:** PIN BROKEN where PINNED sits, in `danger`, through the tell; the posted flankers' rings and their lines into the wall's back drawn dashed for that tell (shape, not only colour); the HUD shield line ends "· every Nth breaks the pin" where the rule and the lever are on. The lane itself is a different shape from the bash's arc. Under reduced motion the lit arc is steady (as every tell's) and the word and the dashes are static. Not shot: off by default.
- **What it would buy** (an estimate from the probe, not measured): about 55/N more struck of 83, so N = 4 near 27% and N = 2 near 44% on the old definition. Every pinned tell in the probe began within 462 px of the wall, inside the 1.0 s sideways budget (171 px), so its lanes would be answerable at 1.0 s. Off: of the 13 seed-1 lines, 11 are byte-identical; pale-bastion and the-stair differ only by the new `missed_pinned` and `missed_pinned_struck` keys (below).

### The Pyre-priest trim test (from the D-e task 4 brief)
- **The test:** whitecross "stands out" if its deaths are >= 5/20 and more than 2x the mean of t4's other two forts, on seeds 20-39 after the Shieldwall change.
- **Applied to rows that predate it,** since no game change happened (m4c for sable-hold and whitecross, qm for the-stair): whitecross 6/20; sable-hold 5/20 and the-stair 1/20, mean 3. 6 is >= 5 but not more than 2 x 3 = 6, so whitecross does not stand out and there is no trim.

### Identity (D-e task 4)
- **The 13 seed-1 lines at 11beb24** (option B's knob off, the new tally keys in; iter `de4id`) against `g3id-post` (0cdc2c7): 11 byte-identical; pale-bastion and the-stair byte-identical once `missed_pinned` and `missed_pinned_struck` are taken out of `tell_tally` (pale-bastion s1: 1 missed, 1 of them pinned; the-stair s1: 1 missed, 0 pinned). Vei's seed-1 BOSS_RESULT is identical to 3cbb6e3's (both run in this task, side by side).
- The margins (test_wardens printout) are unchanged: at 0.6 s slam 0.17, toll 0.74, lunge 0.97, bash 0.71, fire 0.62, lane sideways 0.16 s (lane back 0.72 s, from `rush_lane_over_px` 80 + 13 px); at 1.0 s slam -0.23, toll 0.34, lunge 0.57, bash 0.31, fire 0.22, lane -0.24 s.
- Suite at 11beb24: ALL TESTS PASSED (12,221 checks). `tests/parity_check.sh`: 5 of 5 identical.

## D-e task 5: the death card's AFTER row, and the dev "STRUCK −1030"
- **The row** (`RaidLogic.death_next_row(seed)`, last on the card, label AFTER; `RaidEndings.death_rows` passes the seed the raid already holds, no `Game.*` read, `configs/backups.json` never read). The source is the seed's `death_ends` `{outcome, respawn_s}` (economy 602375e, STATE-API §7.1 v6: after any phylactery revives; not in integration yet, so no seed carries it today).
  - `clone`: "wakes at Covington", plus " in N s" only when `respawn_s` > 0 (m:ss from 60 s: "in 1:30"; a fraction rounds up to 1 s, never "0 s"). Colour `text`.
  - `unmade`: "unmade", plus " · reforms in N s" when `respawn_s` > 0. Colour `danger`.
  - `death_ends` absent (an older save): the seed's `clones_ready`, "wakes at Covington" if > 0, else "unmade". No number.
  - A phylactery revive returns from `RaidRelish.take_hit` before `on_relish_died`, so it never shows the card (source guard in test_raid_logic). Widest AFTER value 242 of 396 px.
- **Dev:** `--raid-clones=<n>` (clones_ready) and `--raid-death-ends=<clone|unmade>:<respawn_s>` (injects the key; the only way to see the number until economy merges). Standalone demo seed only.
- **The Vei fight:** the boss seed carries `death_ends` ("unmade" for a final death), but no loss card or loss text reads it. A lost fight shows only the banner "RELISH IS UNMADE" (`vei_boss.gd` `_lose`, banner text map). Reported, not built.
- **STRUCK −1030:** dev only. The only `take_hit(max_hp + 1000)` calls were `--raid-autodie` (`raid_dev.gd _autodie_hit`) and `--boss-autodie` (`boss_dev.gd _die`), both created only from those flags. Every real blow passes its own damage (slam, toll, lunge, bash, rush, fire, the living's `dmg`), and `take_hit` shows `_struck_amt = amount`, so a real lethal hit shows its real number. **Chosen:** the dev blow equals her remaining hp (the cue stays on, so the shots exercise it), not suppression: `take_hit(relish.hp)`. The first autodie blow after a revive now reads "STRUCK −15" (her revive hp), and a full-hp kill "STRUCK −30".
- **Identity:** the 13 seed-1 raid lines (iter `de4id`) at bd1dfc1 against 52b9da9: 13 of 13 byte-identical; Vei seed 1 (score 70) identical. The bot never waits on the card (`RaidAutopilot.enabled()`), and `death_next_row` runs only in the card path.
- **Shots** (reports/dungeon; `--raid-autodie=60 --frames=330`; the dev autodie names its source at any fort, so each is shot where the warden matches): dq-death-toll (vespers, Bellringer toll) and dq-death-clone (vespers, slam, `--raid-clones=1`: "wakes at Covington"); dq-death-fire (`--raid-profile=3 --raid-fort=mourners-gate`, Pyre-priest fire: "unmade"); dq-death-number (`--raid-profile=2 --raid-fort=chime-fort`, Huntsman lunge, `--raid-death-ends=clone:90`: "wakes at Covington in 1:30"; the key is injected by that dev-only override, no seed carries it yet). Profile seeds hold no phylactery, so those two read STRUCK −30.

## D-e task 6: the held door (a t2 set piece)
### The bot's door rule (bot policy, frozen from here on; written and committed before any row it decides)
- **When.** Once, at the first think she stands in the door's room before the warden wakes, her read pause over, with no living foe on her (a living foe that is not a detour guard, in her room, within `kite_px`).
- **Take it when** at least `autopilot.door_min_bigs` (2) party bigs stand and, once one is spent, a big that meets this warden's weak point (`wardens.archetypes.<id>.weak_point` stat and threshold) still stands, or none met it to begin with. **Spend** the big lowest in that stat (the first in party order on a tie). Otherwise skip it. `RaidLogic.held_door_pick`; `RaidAutopilot._door_tick` / `_door_decide`.
  - Spending the lowest never removes the last big that meets the weak point, so with two or more bigs the rule always takes the door, and the clause decides which big goes.
  - With one big it always skips. The standard t2 party (`party_profiles["2"]`) has one big, beef 6 and speed 4. That meets the Bellringer's beef 6 and the Huntsman's speed 4, so the frozen bot and the typical human skip the door at every standard t2 run.
- **Then.**
  - She walks to the doorstep.
  - She gives the order, the human's left click on that big, at the first think she is within `held_door.order_px` (220) of the plate with no foe on her.
  - Once the plate holds the door, she steps into the doorway and takes the cache.
  - She moves on. Leaving the room shuts the big in.
- **She gives it up** if the big falls before the door holds, or if the door is not open `door_wait_max_s` (8 s) after the order. A big sent stays sent, so it is shut in when she leaves.
- **Basis: a decent player.** The cache is a relic, and its price is a big that sits out the warden fight and is lost on a retreat or a death.
  - With a spare big, they spend the one least use against this warden and keep the one that answers it. The warden's label says which stat answers it ("a beefy big undead braced at the bell muffles its slams"), and the 3c arms showed a fight without its counter runs 1.3-3x longer.
  - With one big, that big is the counter, so they keep it.
- Frozen like the detour rule. The reaction rule and the detour rule are unchanged.

### The measurement arms (the manager, 2026-11-15; written before their rows)
- Seeds 20-39 only. Profiles: the frozen bot (score 70) and the typical human (score 70, `--raid-autopilot-delay=1.0 --raid-autopilot-read=1.0 --raid-autopilot-draw=0.7`).
- **Arm (a), the standard t2 party** (`--raid-profile=2` at vespers, lantern-keep and chime-fort). With the door, paired by seed against the existing no-door rows: m4c for the frozen bot, hb70d10 for the typical human.
- **Arm (b), a party with a spare big.** This is not the standard t2 party. It is the t3 party (`--raid-profile=3`: two bigs, beef 7 / speed 4 and beef 4 / speed 6) at the same three t2 forts. Its no-door rows run on a snapshot of a14d1ec (the code before the door), and it is paired by seed against them.
  - At the Bellringer forts the rule spends the beef-4 big.
  - At chime-fort (the Huntsman, speed 4) both bigs meet the weak point, so it spends the speed-4 big.
- Reported per arm, per fort and per profile:
  - the door-taken rate and which big is spent;
  - the t2 median and the share of runs at 180 s or more (the typical human with the midpoint left-out factors);
  - t2 deaths paired by seed, with Wilson 90% and the clustered interval;
  - travel against the 5.3% ceiling, and idle;
  - relics gained, and bigs spent, rejoined or lost.
- **The rule's walk, made exact before any measurement row.** The seed-1 probes showed two gaps in how the committed rule was carried out. Neither changes the decision, which big is spent, or when she orders.
  - The bot's usual gathering (piles within `pile_px` 900, in any room) took her out of the door's room before the cache was hers, so the big was shut in for nothing. While the door is taken she now gathers only inside the door's room (`_collect_node` / `_pickup_node` with that room).
  - If she does leave first anyway, the rule ends (`abandoned`) and the big stays shut in.

### The design as built (`raid.json held_door`, `RaidHeldDoor`, `LayoutLogic.held_door_site` / `carve_held_door` / `_niche_step`)
- **Gate.** `held_door.tiers` [2]: vespers, lantern-keep and chime-fort. Never the first dungeon, a held fort or the boss arena. `[]` turns it off. Every new path is gated on the carved layout (`layout.held_door`) or `raid.held_door != null`, so every other fort runs the old code.
- **Where.** The route is the greedy walk the bot's routing takes: from the spawn, through the nearest portal into each next room of the shortest room path. Every route room but the warden's is a candidate.
  - On each of its four walls, every niche position 8 px apart whose zone (niche, walls and plate, grown by `clear_px` 30) touches no gap or exit, and whose footprint (grown by `route_clear_px` 40) misses the route's segment through that room.
  - The pick is the least added walk (`detour_px`), with no rng.
  - The result: vespers, the spawn room's north wall between its two gaps to the antechamber (96 px of detour); lantern-keep, the spawn room's south wall beside the spawn exit (25 px); chime-fort, the antechamber's north wall (152 px).
  - The spawn room is a checkpoint at all three. At vespers and chime-fort the antechamber is one too, so a cache taken in the spawn room at vespers banks on entering the antechamber.
- **The niche.** 110 px along the wall by 44 px deep, 12 px walls, a 64 px door, and a 36 px plate beside the door in the room. It is part of its room (`room_of`); the routing tables are unchanged.
  - The niche and its door are solid (the plug) while the door is shut, so nothing can stand in a shut niche.
  - `LayoutLogic.waypoint` takes any mover in or out through the doorway (`_niche_step`).
  - The cache (`loot.json cache`, 1 relic at t2) lies inside, 28 px from the doorway's centre, and out of reach through the shut door (47 px from the doorstep against the 40 px pickup radius). It stays out of `raid_pickups` while the door is shut, so it is never "on the floor" and no one fetches it.
- **The order.** There was no army order to reuse: the army follows Relish and the trance raises. Standing within `order_px` 220 of the plate (her light's radius: she stands at the door), she gives the order with the move click.
  - A left click on one of her party bigs sends that big; a click on the plate sends the nearest. The click is used up: she does not walk there.
  - A click on the big was added so the player chooses which big pays, as the choice is "spend a big or keep it for the warden" and the counter big matters. The bot uses the same click (`RaidHeldDoor.click`).
- **The door.** It is open only while the sent big stands within `hold_px` 18 of the plate's centre (`RaidUnit._hold_plate`: it holds the plate before any warden role and strikes what comes into reach; it never chases). It never shuts on Relish.
  - When she stands in any other room, the sent big is shut in (`_shut_in`): off `allies` (so out of the ward, the conduit chain, the pack counters and the party line), parked behind the barred door, never struck.
  - **Its fate, in one place** (`RaidLogic.held_door_lost`, the manager's ruling): when the warden falls the door unlocks and the big rejoins at the doorstep. A retreat, a window close or a death puts its uid in `party_lost` (`RaidEndings.build_result`). No result key changed.
  - Once the warden has fallen, no order is taken, so the cache is never free after the fight.
- **Legible** (shape and words; nothing animates, so reduced motion is the same picture):
  - The shut door is a barred slab and the open door a dashed frame. The plate is dashed when empty and a solid double square when held, with a dashed tie from the plate to the door.
  - On entry: the banner and the world label "HELD DOOR · a big on the plate holds it · it stays behind".
  - The plate's prompt, while she can order: "AT THE HELD DOOR · click a big to send it (the plate sends the nearest) · it stays shut in until the warden falls · a retreat or a death loses it".
  - While held: the world label "HELD · <name>" and the HUD row "HELD DOOR · <name> holds it · leaving the room shuts it in until the warden falls".
  - On leaving: the banner and world label "SHUT IN · <name>" in `danger`, and the HUD row "SHUT IN · <name> · rejoins when the warden falls · a retreat or a death loses it". The WARD's big row drops it.
  - The retreat dialog adds "<name> is shut in at the cache: a retreat loses it." The death card gives it its own row, SHUT IN "<name> · lost at the cache", and the LOST row's big count leaves it out.
  - No new Palette key.
- **Measuring.**
  - AUTOPILOT_RESULT `door` {room, side, detour_px, state, big, fell, cache, cache_left, times {ordered, open, cache, shut, freed}, spent_s (from the order to the cache in hand), rule, at {t, stat, threshold, values, big}, done_s, wait_s (standing at the doorstep after the order, the door still shut), walk_px (from the decision to the cache), fate (lost / rejoined / kept / fell / "")}. It appears only on lines with a door.
  - Capture's record gains `door` (the same, plus `taken` and the big's `name`) only on those forts. `AUTOPILOT_DOOR <taken|declined> ... frame=` prints the decision.
- **Shots** (reports/dungeon; vespers seed 1; `--frames` with `--fixed-fps 60`):
  - de6-door-entry: the standard party, frame 75. Barred door, dashed plate, CACHE, label, banner and prompt.
  - de6-door-held: the spare-big party, frame 180. Profile big 2 on the plate, the door open, HELD and the HUD row.
  - de6-door-shut: frame 300. Behind the barred door, SHUT IN in the world, banner and HUD row; WARD big 1; the relic banked in the antechamber.
  - de6-door-shut-reduced: the same frame under `--reduced-motion`.
  - de6-door-held-greyscale: frame 180 under `--raid-greyscale`.
- **Capture, checked** (vespers, the spare-big party, seed 1, the door taken): the bot's line is identical with `--capture` on and off. The record carries `door` {taken true, big p2 "Profile big 2", times, spent_s 2.52, fate rejoined}.
- **The retreat card.** There is none to add a row to: no post-retreat card or summary reads `party_lost`. Only `sim/state_runs` (it removes the bigs), `results` and the Vei card do. The retreat confirmation dialog is the one retreat surface, and it now names the shut-in big. A window close shows nothing; the big is still in `party_lost`.
  - The death card's SHUT IN row and the dialog line are checked in source only (tests). The bot never shows the card, so no row exercises them.
- **Seed-1 probes before the rows** (working tree, scratch, not in the raw file):
  - The standard party declined the door at all three forts.
  - The spare-big party took it at all three, and its big rejoined: vespers 117.4 s (order 0.53, open 2.93, cache 3.05, shut 4.53; 1.5 s at the doorstep); lantern-keep 153.6 s (order 0.08, open 3.88, cache 18.77: the room's fight came first); chime-fort 128.9 s (order 13.98, open 17.87, cache 17.98; 3.0 s at the doorstep).
  - The wait at the doorstep is idle in the split.
- **The checkpoint review's two overlaps** (bd13552, draw only, lines byte-identical to bff1cea):
  - The world label moves off Relish's token while they would overlap, away from the wall and past her (`RaidHeldDoor.label_shift`, after the boss lanes' `label_shift`).
  - The HUD's door row is now the StatBlock's DOOR row, on its plate, wrapped to the value column (`RaidHud.wrap_chunks`). It no longer runs across the map.
  - All five shots were re-taken at bd13552 and read.

### Identity (iter `de6id`, the 13 seed-1 lines at bff1cea)
- 10 lines (t1, P1, t3, t4) are raw-identical to `de4id`. vespers is identical once the new `door` key is dropped.
- lantern-keep 106.07 → 113.47 s and chime-fort 116.05 → 108.27 s, re-pinned in 8ad7ca1. The door is declined (one big), so only the niche's walls act.
- Vei's seed-1 line is identical to a14d1ec's. `parity_check.sh` gives 5 of 5. A door-taken t2 line (vespers, the spare-big party, seed 1) is identical with and without `--reduced-motion`.

### The measurement (seeds 20-39, score 70, the three t2 forts; 372 rows, all in lockstep, no script errors)
- **Rows:**
  - with the door at bff1cea: `de6a` / `de6ah` (arm a, frozen bot / typical human), `de6b` / `de6bh` (arm b);
  - arm (b) without the door at a14d1ec: `de6b0` / `de6b0h`;
  - arm (a) without the door: m4c and hb70d10. They reproduce byte for byte at a14d1ec (`de6spot` / `de6spoth`, seeds 20-21, 12 of 12).
- **The typical human's length** is the per-run estimate `duration_s + trance_s × (1/0.35 − 1) + 0.75 × raises + 0.2 × split.travel_s + 1.0 × human.reads + 0.2 × react.tells` (seconds). The 2 s circle comes in through the trance's stretch (the 0.7 scene-second draw at a 0.35 time scale) and is not added again. The frozen bot's length is scene seconds.
- **Deaths:** Wilson 90%, then the seed-clustered interval (n / 1.5). **Split:** pooled seconds, each fort's > 2× outliers out.
- **The door taken, per arm, fort and profile:**
  - arm (a): 0 of 20 at each fort for both profiles (declined: one big);
  - arm (b): 20 of 20 at each fort for both profiles, its cache fetched every time. The big spent is p2 (beef 4) at vespers and lantern-keep, and p1 (speed 4) at chime-fort.

| arm, profile | median s, no door → door | ≥ 180 s | died, no door → door | paired: died only with / only without | travel / idle % | relics | bigs spent: rejoined / lost |
|---|---|---|---|---|---|---|---|
| a, frozen | 117.6 → 116.4 | 5 → 7 of 60 | 6/60 = 10.0% (5-18; 5-20) → 7/60 = 11.7% (6-20; 6-23) | 3 / 2 | 5.13 / 1.28 → 4.92 / 1.36 | 128 → 126 | none spent |
| a, typical human | 168.0 → 169.3 (scene 126.9 → 126.9) | 19 → 20 | 9/60 = 15.0% (9-24; 8-26) → 6/60 = 10.0% (5-18; 5-20) | 2 / 5 | 4.51 / 2.32 → 4.57 / 2.26 | 122 → 126 | none spent |
| b, frozen | 87.5 → 106.4 | 0 → 3 | 0/60 (0-4; 0-6) → 4/60 = 6.7% (3-14; 3-16) | 4 / 0 | 6.91 / 1.70 → 6.18 / 4.40 | 142 → 185 | 60: 54 / 6 (4 deaths, 2 retreats) |
| b, typical human | 129.4 → 162.3 (scene 97.0 → 123.2) | 4 → 18 | 1/60 = 1.7% (0-7; 0-9) → 2/60 = 3.3% (1-10; 1-12) | 2 / 1 | 6.00 / 3.26 → 5.79 / 5.14 | 140 → 190 | 60: 57 / 3 (2 deaths, 1 retreat) |

- **Paired per run** (door minus none, paired medians):
  - arm (a): +0.0 s (27 and 28 of 60 runs the same length);
  - arm (b): the frozen bot +22.9 scene seconds; the typical human +43.3 s on the estimate (+30.6 scene seconds).
- **Arm (a), declined: it neither pads nor idles beyond noise.**
  - Travel is 4.92% and 4.57%, under the 5.3% ceiling.
  - Idle is 1.28 → 1.36% for the frozen bot (+0.07 s a run, mean) and 2.32 → 2.26% for the typical human.
  - The niche's walls changed the length of 33 and 32 of the 60 runs. Deaths move both ways within the intervals.
  - The typical human's 15.0 → 10.0% is noise, not the door making t2 safer: 9 against 6 of 60, paired 2 against 5, with the niche's walls shifting paths, and the door declined in every run.
- **Arm (b), the trade.**
  - Length (paired medians): +22.9 scene seconds for the frozen bot, and +43.3 s on the typical human's estimate (+30.6 scene seconds). The estimate's median goes from 129 to 162 s, and the share at 180 s or more from 4 to 18 of 60.
  - Risk: 0 → 4 deaths for the frozen bot (all 4 paired against a survived run) and 1 → 2 for the typical human.
  - Loot: one relic a run (60 cache relics fetched in each profile). Result relics +43 and +50, net of the unbanked cache lost in deaths and of the chest's own rolls.
  - Travel: arm (b) without the door is already over 5.3% (6.91% and 6.00%), because the spare-big party's fights are short. The door adds 0.9 s and 1.6 s of travel a run (the walk is 352-792 px, median per fort), and the share falls to 6.18% and 5.79%.
  - Idle rises: 1.70 → 4.40% and 3.26 → 5.14%, about +3.5 s a run.
- **What the idle is.** A throwaway probe on copies of both snapshots booked each idle tick to the bot's branch: frozen bot, arm (b), seeds 20-25, 18 runs each, every line byte-identical to its batch row.
  - The doorstep wait (the big walking to the plate) is 12.6 s, 0.7 s a run. A human waits for it too.
  - The rest is the bot's hold rule, which waits while hostile living fight its army in this room or the next and which `time_class` books as idle (Step 4's classification gap): 27.3 s without the door, 78.0 s with it. 41.8 s of that came while the big held the plate:
    - with the plate's holder out of the room's fight, the route fights run longer;
    - the bot's door step comes after its hold, so it waits out the room's fight before stepping in.
  - The order-to-cache median is 2.5 s at vespers and 7-9 s at the other two. Not tuned: the bot is frozen.
- **The t2 risk band (10-15%).**
  - Arm (a), t2's own party: 11.7% (frozen) and 10.0% (typical human), inside the band.
  - Arm (b), a spare big: 6.7% and 3.3% with the door, 0% and 1.7% without. Under the band, reported as asked.

### The quality pass (D-e opus review, 3a4ec38..520cd63; one commit each)
- **Important 1, the warden falls with a big sent or on the plate** (5c1ba38). The fall frees it too (`RaidLogic.held_door_fall`: sent, held and shut all become freed). It is never shut in afterwards, the door unlocks, and a retreat after the fall keeps it.
  - Gating `_shut_in` alone was not chosen: it would leave the big on the plate and committed, so a retreat would still lose it.
  - The states are pure (`held_door_step`, `held_door_fall`, `held_door_committed`), and the order of events is tested.
- **Important 2, source guards** (ff88879): rows for the changed routing (`waypoint`, `_waypoint_rooms`, `_niche_step`), the door's `make`, `place_cache` and `fate`, `spawn_cache`, the bot's `_collect_node` and `_pickup_node`, and the new pure functions. A new guard checks that every held-door, niche-routing and door-rule sim function draws no random number.
- **Important 3, the unstick watch under the degraded bot's held goal** (79c7070).
  - While a read pause or a drawn circle holds her still, `_aim_at` no longer steps the watch or advances its clock. The first think back restarts it. The frozen bot never holds, so its lines are unchanged.
  - The closing branch's `st.in` is left as it is: clearing it would move frozen lines wherever the watch fires.
  - **Effect:**
    - The 9 hb70d10 rows at seed 20 (one per at-tier fort; `de6q3pre` at 64de0f4 against `de6q3` at 79c7070) are all identical: the watch fired in none of them.
    - The 11 hb70d10 runs where it had fired (seeds 20-39: chime-fort 1, hollow-redoubt 6, mourners-gate 2, sable-hold 1, whitecross 1; `de6q3fpre` / `de6q3f`): 9 move, and **only in `unstick.aimed_in`**. Length, exit, split and every other key are unchanged in all 11.
  - **So D-e's task 2 and task 6 human rows on seeds 20-39 carry this small bias.** It shows as a spurious `aimed_in` (hb70d10 11/180, hb50d10 8/180, de6ah 2/60, de6bh 19/60, de6b0h 6/60; de6ah has 1 `given_up`). In the sampled runs it changed nothing else. The grading pass re-measures the typical human with the fix.
- **Minor 4** (74fca39): one weak-point lookup (`RaidLogic.unit_stat`); the dead `big_stat` and the unused `CAPTURE_OUTCOMES` are gone.
- **Minor 5** (5f2d4f0): `RaidHeldDoor.fate(exit)` for the bot and capture; `RaidPopulate.spawn_cache` for both caches.
- **Minor 6** (36e0cf4): capture records the bot's time-out as `timeout`, and a standalone close during an ending beat as that beat's ending, with its killer.
- **Minor 7** (0f6fe53): the brittle tests are now behavioural (the death card's SHUT IN row, `party_lost` on a retreat) or matched on their tokens.
- **Minor 8** (b11f0b2): the door's geometry is in `raid.json held_door` at the same values.
- **Spec-review items:**
  - The retreat dialog says it by state: on the plate · lost if you retreat, or shut in at the cache (566b4e1).
  - The door's one-line labels sit beside the plate, and the prompt has its own plate; the shots were re-taken and read (64de0f4).
  - An unknown `death_ends.outcome` falls back to `clones_ready`, and a missing `respawn_s` shows no number (7e9c317).

## D-e grading pass (seeds 40-59, final config afb8dab): the plan, written before any row
Measurement only: no tuning, no picks, no code change. One `git archive` snapshot of afb8dab runs everything. If any code changes after it, the pass stops and the manager is told. Seeds 40-59 run once; the only re-runs are the 9 determinism reruns below. The rows and this plan live in `reports/dungeon/calibration-dd-raw.tsv(.jsonl)` (iters `grade-*`); the log gets a D-e grading section.

### Profiles
- **Frozen bot:** score 70, no human knobs (it reacts in 0.45 s; NOTES' "0.6 s" is the score-50 delay).
- **Typical human:** score 70, `--raid-autopilot-delay=1.0 --raid-autopilot-read=1.0 --raid-autopilot-draw=0.7`.

### The run list (seeds 40-59, 20 per cell)
| set | iters | cells | runs |
|---|---|---|---|
| 1. at tier: the 9 forts, the tier's standard party (`--raid-profile=<T> --raid-fort=<id>`) | `grade-tier-frozen`, `grade-tier-human` | 9 forts x 2 profiles | 360 |
| 2. t1: greywall, ashgate, old-sluice (`--raid-profile=1`) | `grade-t1-frozen`, `grade-t1-human` | 3 x 2 | 120 |
| 3. P1: `--raid-fixture=day1,old-sluice` | `grade-p1-frozen`, `grade-p1-human` | 1 x 2 | 40 |
| 4. held door, arm (b): the t3 party (`--raid-profile=3`) at vespers, lantern-keep and chime-fort, door on and door off | `grade-doorb-on-frozen/-human`, `grade-doorb-off-frozen/-human` | 3 x 2 x 2 | 240 |
| 5. Vei: seed 1 (`--boss-autoplay=70 --boss-seed=1`) and `parity_check.sh`'s boss line | | identity only | 2 |
| capture check: frozen, seed 40, one per at-tier fort, with `--capture=<R>/de-capture-check.d/grade-<fort>-40.jsonl` | `grade-cap` | 9 | 9 |
| determinism reruns (rep 1): typical human, seed 41, one per at-tier fort | `grade-tier-human` rep 1 | 9 | 9 |

The grading rows are 760; with capture and reruns 778 raid runs, plus the 2 Vei runs. About 14 s of wall each at 3 at once.
- **Arm (a)** is not a separate set: it is the three t2 forts of set 1 (the standard t2 party, one big, door declined).
- **Door off, one snapshot.** The code has no per-run flag for the door. The off rows run on a byte copy of the same imported snapshot with one config value changed, `configs/raid.json held_door.tiers` `[2]` -> `[]` (the documented off switch: no niche, no door, no cache). It is a config value, not code. Task 6's no-door rows ran a14d1ec instead, so the off rows here are not those rows' twin: they share afb8dab's every other line.
- Seed 40-59 batches run with `calibration-dd-run.py --sha afb8dab`, at most 3 at once, headless, `--audio-driver Dummy`.

### Reporting method (fixed here, before any row)
- **Death rates:** count, Wilson 90%, and the seed-clustered interval (Wilson on n_eff = n / 1.5, the same proportion). Retreats (left with no army, gave up) count as neither a death nor a win and stay in the medians.
- **At tier, both profiles:** pooled, per tier, per archetype, per fort. Causes: `killed_by` plus the missed tell (`RaidLogic.death_tell`), with the toll split from the slam. `untold_blows` summed. Answered-but-struck (`tell_tally.answered_struck`) per warden.
  - **The Shieldwall guard, like for like:** frozen bot 0 on seeds 20-39 (qm, 2 forts x 20) against the same on 40-59. The typical human: 7 on seeds 20-39 was hb70d10 (4) plus hb50d10 (3), over two scores, so the like-for-like comparison is hb70d10's 4 against this pass's score-70 count; both are stated, and the score-50 profile is not re-run.
- **Reach per warden, both definitions** (`tell_tally`): old = missed_struck / (missed - missed_countered); new = (missed_struck - missed_pinned_struck) / (missed - missed_countered - missed_pinned). `missed_pinned` and `missed_pinned_struck` exist in the Shieldwall's lines only, so the other wardens' two definitions are one.
- **Length:** per tier and profile: the median scene seconds and the pooled split (travel, fight, trance, idle; each fort's > 2x outliers out, the Part 2 method). For the typical human the per-run estimate is `duration_s + trance_s x (1/0.35 - 1) + 0.75 x raises + 0.2 x split.travel_s + 1.0 x human.reads + 0.2 x react.tells`, with the circle coming in through the trance's stretch only; its median, its share >= 180 s, and real seconds = `duration_s + trance_s x (1/0.35 - 1)`. The frozen bot's length is scene seconds. Guards: travel <= 5.3 / 10.5 / 16.0% at t2 / t3 / t4, idle not above the D-d final (0.3-1.3% at t2-t4, frozen).
- **t1 and P1, both profiles:** deaths per fort and pooled; for each death, whether it came in the warden fight (after `warden_wake_s`) or before, and the army at death and 5 s before (`army_at_death_minus5`); greywall against ashgate and old-sluice; length.
- **The held door:**
  - arm (a): door-taken rate; t2 median and deaths against task 6's no-door rows (seeds 20-39: 117.6 / 168.0 s median, 6 and 9 of 60 died), side by side, not paired. The human's 15.0 -> 10.0% there is noise, not the door making t2 safer.
  - arm (b): taken rate, which big, the t2 median and the share >= 180 s, deaths paired by seed door on against off (Wilson 90% and clustered), relics gained, bigs spent / rejoined / lost, travel and idle. Idle is two figures: 0.7 s a run is the doorstep wait, and the rest is the bot's hold-while-the-army-fights rule (a side finding, untuned).
- **Determinism:** the lockstep count (physics_frames - frames_drawn in 0 or 1) over every row, and the 9 reruns, which must be byte-identical (the whole AUTOPILOT_RESULT line).
- **Then:** re-measure the stand-ins (`reports/dungeon/standins-measured.json`, `measured_at` = afb8dab), run the full suite and `parity_check.sh`.

### Coverage of the manager's rulings
| item | where it's covered |
|---|---|
| t4 at x1.35 | at tier, per tier: t4 graded with Wilson and the clustered interval |
| greywall, ashgate, old-sluice at both profiles | t1 set, per fort |
| t1 pooled and the first dungeon at the typical human | t1 set pooled; P1 at both profiles |
| the answered-but-struck guard (frozen and 1.0 s, Shieldwall especially) | at tier, both profiles, per warden |
| reach under both definitions | at tier, with `missed_pinned` giving exact counts |
| D-d's 14.4% restated with its clustered interval | settled, no seeds: 26/180, Wilson 10.7-19.3%, clustered 9.9-20.5%. Restated beside the grade |
| the L1 byte-for-byte check | settled, no seeds: 6 of 6 L1 rows re-run at 0cdc2c7 were byte-identical (43021cd's NOTES line). Cited |
| the capture check (b) evidence | settled at 187fb96 (de-capture-check.tsv and .jsonl, 40 of 40). Task 6 added the door to capture, so 9 grading rows (frozen, one per at-tier fort, seed 40) re-run with `--capture`: the AUTOPILOT_RESULT must equal its no-capture grading row, and capture's tallies must match `tell_tally`. The rows are appended to the de-capture-check files |

### Addendum: the door-off override, labelled (the manager's condition, before the door-off rows)
- **The override:** the `grade-doorb-off-*` rows run on a copy of the imported afb8dab snapshot, not on the bare sha. The one change, in `configs/raid.json` `held_door`: `"tiers": [2]` -> `"tiers": []`. Nothing else differs from afb8dab.
- **Labelled so:** these rows carry label `afb8dab+door-off (raid.json held_door.tiers [2] -> [])`; the runner's sha column holds the first 9 characters, `afb8dab+d`. Every other grade row is the clean afb8dab.
- **The off rows are config-only,** and the report says so wherever it uses them: door off here means no niche, no door and no cache at all.

### Addendum: the stand-ins re-measure at afb8dab (iter `grade-standins`; the Part 2 method, not graded)
- 432 runs at the clean afb8dab snapshot, score 70 unless stated, the standard party of the tier: the 9 forts at tier seeds 20-39 (score 50 and 90: seeds 20-23); t1 ashgate and old-sluice seeds 1-14 (50/90: 1-5), greywall seeds 20-39 (50/90: 20-24); the first dungeon (day1, old-sluice) seeds 1-60; the tier-2 party at the 3 t4 forts, seeds 20-33. They replace `by_tier`, `first_dungeon`, `two_tiers_above`, `acceptance_70` and `measured_at` in `reports/dungeon/standins-measured.json`. The seed 20-39 rows are not part of the seed 40-59 grade.
- `fight_telemetry` is not re-measured; its source commit stays stated in the file.

### The grading pass: results (afb8dab, seeds 40-59, run once; plan fb38ecf, addenda 8ea9e41 and d536748)
Rows: iters `grade-*` in `reports/dungeon/calibration-dd-raw.tsv(.jsonl)`; 778 raid runs, all in lockstep (physics_frames - frames_drawn 0 or 1), no script errors, no failed runs. The door-off rows (`grade-doorb-off-*`, 120) carry label `afb8dab+door-off (raid.json held_door.tiers [2] -> [])` in the label column; the sha column is cut to `afb8dab+d`. Every other grade row is the clean afb8dab. Rates are count, Wilson 90%, then the seed-clustered interval (n / 1.5). Retreats count as neither death nor win.
- **At tier, pooled:** frozen 27/180 = 15.0% (11-20; 10-21); typical human 38/180 = 21.1% (17-27; 16-28). **Against the 10-15% band:** the typical human's 21.1% is above it, and the frozen bot's 15.0% sits at its top edge. Against seeds 20-39 the human is +6.1 points (z = 1.51, p about 0.13; z = 1.23 with the design effect): within seed noise, only just, and in the wrong direction for the band. D-d's 14.4% restated: 26/180, 10.7-19.3%, clustered 9.9-20.5% (seeds 20-39, a different seed set). The human's 15.0% on seeds 20-39 (hb70d10, 27/180) is below this pass's 21.1%, with overlapping clustered intervals (10-21 and 16-28).
- **Per tier** (frozen | human): t2 9/60 = 15.0% (9-24; 8-26) | 12/60 = 20.0% (13-30; 12-32); t3 11/60 = 18.3% (12-28; 10-30) | 11/60 = 18.3%; t4 (x1.35) 7/60 = 11.7% (6-20; 6-23) | 15/60 = 25.0% (17-35; 16-38).
- **Per archetype** (frozen | human): Bellringer 9/60 = 15.0% (9-24; 8-26) | 14/60 = 23.3% (16-33; 14-36); Huntsman 10/40 = 25.0% (16-38; 14-41) | 10/40 = 25.0%; Shieldwall 4/40 = 10.0% (5-21; 4-24) | 6/40 = 15.0% (8-26; 7-30); Pyre-priest 4/40 = 10.0% (5-21; 4-24) | 8/40 = 20.0% (12-32; 10-35).
- **Per fort** (frozen | human, of 20): vespers 6 | 8; lantern-keep 1 | 0; chime-fort 2 | 4; hollow-redoubt 8 | 6; pale-bastion 1 | 3; mourners-gate 2 | 2; sable-hold 2 | 6; the-stair 3 | 3; whitecross 2 | 6. Hollow-redoubt's 8/20 frozen (40%, 24-58; clustered 21-62) is the highest cell and all 8 are the lunge. Reported, not tuned.
- **Causes** (`killed_by`; the missed tell by `RaidLogic.death_tell`): frozen: toll 7 (the ring at your feet), slam 2 (the swing), lunge 9 (the line), rush 4 (the lit arc), fire 4 (the marked ground), living 1 (no tell). Typical human: toll 13, slam 1, lunge 10, rush 5, fire 7, living 2 (the-stair s54, whitecross s53), 38 in all. `untold_blows` is 0 in both profiles.
- **Answered-but-struck, per warden** (answered tells): frozen Bellringer 3 of 963, Huntsman 1 of 295, Shieldwall 1 of 418, Pyre-priest 0 of 219; human Bellringer 0 of 1,198, Huntsman 1 of 403, Shieldwall 6 of 469, Pyre-priest 0 of 225.
  - **The Shieldwall guard, like for like** (pale-bastion and the-stair, 40 runs each pass): frozen 1 now (the-stair) against 0 on seeds 20-39 (qm); typical human 6 now (all the-stair) against 4 in hb70d10 (the 7 earlier was hb70d10 4 + hb50d10 3). Both rose, on different seeds and from a handful of events; the guard as written ("must not have risen") is not met, and it is reported, not tuned.
- **Reach per warden** (struck / missed and uncountered; `missed_pinned` counts exact): Bellringer 28/82 = 34% frozen, 44/139 = 32% human; Huntsman 40/64 = 62%, 63/96 = 66%; Pyre-priest 42/62 = 68%, 38/60 = 63% (one definition each). Shieldwall old 24/120 = 20% frozen and 30/131 = 23% human; new (a pin is a counter) 24/29 = 83% and 30/36 = 83%, with `missed_pinned` 91 and 95 and no pinned tell struck (`missed_pinned_struck` 0).
- **Length** (median scene s; split travel / fight / trance / idle %, pooled, each fort's > 2x outliers out):

  | profile, tier | median scene s | split | notes |
  |---|---|---|---|
  | frozen t2 | 116.5 | 4.8 / 94.0 / 0.0 / 1.2 | 2 of 60 >= 180 s |
  | frozen t3 | 131.5 | 9.7 / 89.4 / 0.0 / 0.8 | 7 of 60 |
  | frozen t4 | 125.2 | 10.8 / 89.0 / 0.0 / 0.2 | 2 of 60 |
  | human t2 | 126.5 (real 149.0, estimate 168.5) | 4.0 / 85.0 / 9.1 / 1.9 | estimate >= 180 s: 26 of 60 |
  | human t3 | 147.8 (real 170.0, estimate 190.8) | 8.0 / 82.9 / 6.9 / 2.3 | 38 of 60 |
  | human t4 | 129.1 (real 149.7, estimate 169.3) | 10.8 / 80.0 / 7.5 / 1.8 | 22 of 60 |

  The typical human's estimate (the formula as written above): median 178.3 s over all 180 runs, 86 of 180 (48%) >= 180 s. Guards: travel 4.8 / 9.7 / 10.8% (frozen) and 4.0 / 8.0 / 10.8% (human) against 5.3 / 10.5 / 16.0: all under. Idle: frozen 1.2 / 0.8 / 0.2% against D-d's 0.3-1.3%: not above. Human idle 1.9 / 2.3 / 1.8% against hb70d10's 2.3 / 2.1 / 2.1%: t3 is 0.2 points over it, reported.
- **t1** (20 a fort; frozen | human): greywall 0 | 3, ashgate 2 | 3, old-sluice 0 | 1; pooled 2/60 = 3.3% (1-10; 1-12) | 7/60 = 11.7% (6-20; 6-23). Medians 113.0 s frozen; human scene 115.5, estimate 160.1, real 138.5 s. Splits 3.6 / 93.8 / 0.0 / 2.6 and 3.3 / 82.7 / 10.3 / 3.7.
  - The greywall pick targets (frozen at most 1/20; human at most 2/20 and not above ashgate and old-sluice): frozen 0/20 met; human 3/20 is over 2/20 and equal to ashgate's 3/20 (old-sluice 1/20).
  - Every t1 death was a living-pack death (`killed_by` living) with the army at 0. Frozen: ashgate s45 at 26.9 s before the wake (army 7 five seconds before), s56 at 13.0 s in the fight (wake 6.5 s; army 8). Human: 5 of 7 in the warden fight (greywall s41, s49, s58; ashgate s53, s55), 2 before the wake (ashgate s54, old-sluice s54); army five seconds before: 3, 12, 0, 2, 10, 7, 6.
- **P1** (day1, old-sluice): 0/20 both profiles; median scene 91.6 s frozen (split 4.0 / 94.9 / 0.0 / 1.1); human 103.4 s scene, estimate 139.3, real 122.3 s (3.1 / 79.9 / 9.7 / 7.3: idle is 7.3%).
- **The held door.**
  - Arm (a), the standard t2 party at 3 forts, declined 0 of 60 taken for both profiles. Frozen: 9/60 = 15.0% (9-24; 8-26), median 116.5 s, 2 of 60 >= 180 s, against task 6's no-door rows (seeds 20-39, other seeds, side by side) 6/60 = 10.0%, 117.6 s, 5 of 60. Human: 12/60 = 20.0% (13-30; 12-32), estimate median 168.5 s, 26 of 60 >= 180 s, against 9/60 = 15.0%, 168.0 s, 19. The medians match to a second; the death counts differ by 3 both ways and are not the door, as task 6's own 15.0 to 10.0% was not.
  - Arm (b) (the t3 party at the t2 forts, door on against `afb8dab+door-off`, paired by seed over 60):

  | | frozen on | frozen off | human on | human off |
  |---|---|---|---|---|
  | taken, cache fetched | 60/60 | | 58/60 (2 abandoned at lantern-keep s45, s47: she left first, the big rejoined) | |
  | died (W90; clustered) | 7/60 = 11.7% (6-20; 6-23) | 3/60 = 5.0% (2-12; 2-14) | 9/60 = 15.0% (9-24; 8-26) | 2/60 = 3.3% (1-10; 1-12) |
  | paired deaths, only with / only without | 6 / 2 | | 8 / 1 | |
  | median s | 111.6 scene | 88.3 | 161.1 estimate (122.0 scene) | 123.8 (94.8) |
  | >= 180 s | 3/60 | 0 | 14/60 | 3/60 |
  | paired median delta | +31.2 s scene | | +39.0 s estimate | |
  | travel / idle % | 5.21 / 3.50 | 6.28 / 1.86 | 5.18 / 4.35 | 5.73 / 2.97 |
  | relics (60 runs) | 190 | 142 | 184 | 147 |

  **The trade, deaths:** door on against off, frozen 7 vs 3 (6 only with, 2 only without), human 9 vs 2 (8 / 1). Task 6's door-on rates were 6.7% frozen and 3.3% human on seeds 20-39; on seeds 40-59 they are 11.7% and 15.0%. The door costs a spare-big player real risk.
  Bigs spent: p2 (beef 4) at vespers and lantern-keep, p1 (speed 4) at chime-fort, 60 a profile; frozen 53 rejoined and 7 lost, human 50 rejoined and 10 lost. The off rows' travel is above 5.3% (6.28 and 5.73), as task 6's were.
  - **Idle, as two figures.** The doorstep wait is 0.66 s (frozen) and 0.64 s (human) a run. The rise in mean idle with the door is 2.67 s (frozen, 1.66 to 4.33 s) and 2.78 s (human, 2.87 to 5.65 s), so about 2 s a run beyond the wait is the bot's hold-while-the-army-fights rule (inferred from the difference; the branch probe of task 6 was not repeated). It is a side finding left untuned.
- **Determinism:** 778 of 778 rows in lockstep. The 9 reruns (human, seed 41, one per at-tier fort, rep 1) are byte-identical to their rep-0 rows, 9 of 9. Task 6's identity checks stand; Vei seed 1 (`BOSS_AUTOPLAY` line, md5 e1ab8a0c...) is identical to the earlier runs' (e1ab8a0c...), and `parity_check.sh` gives 5 of 5 identical.
- **Capture check (9 rows, frozen, seed 40, `--capture`, iter `grade-cap`):** the AUTOPILOT_RESULT is byte-identical to the no-capture `grade-tier-frozen` row, 9 of 9. Capture's tells (tolls excluded: they ride a slam's tell), struck, outcome, `killed_by` and `scene_s` equal `tell_tally`, outcome, `killed_by` and `duration_s` in 9 of 9 (capture 154 tells with 20 tolls against the bot's 134; struck 10 against 10). Rows are appended to `de-capture-check.tsv` and `.jsonl` (records in `de-capture-check.d/grade-<fort>-40.jsonl`).
- **The stand-ins** are re-measured at afb8dab (iter `grade-standins`, 432 runs; `standins-measured.json` `measured_at` afb8dab, raw `standins-raw-afb8dab.tsv`): by_tier 70 deaths t1 0%, t2 11.7%, t3 13.3%, t4 20.0%; P1 0%; two tiers up 64.3%. `fight_telemetry` and the caveats text are the earlier file's and say so.
- **Suite and parity** (HEAD with NOTES-only commits over afb8dab): ALL TESTS PASSED; `parity_check.sh` 5 of 5 identical.

## Dungeon close-out (after D-e)

- **Identity after the fast-forward (c873475 against faaa820, iter `dzid`, score 70, seed 1):** the 13 seed-1 raid lines (9 at tier, 3 at t1, P1) are raw-identical, 13 of 13, and Vei's seed-1 `BOSS_RESULT` and `BOSS_AUTOPLAY` lines are identical (md5 8e3f1821...). Economy's API v6 moved no line.
- **Vei's loss card** (`VeiCard` with `info.lost`, built by `VeiBoss._lose_card` from `BossLogic.loss_card`; the drain's end calls it where `_emit(false)` was). Same plate, dim, gate (`card.skip_after_s`), keys and button as the win card, plate `card.loss_h_px` (520) for the extra row. The result dict, the single emit (on the button) and the close (`close_result`) are unchanged; the bot emits at once unless `--boss-hold-card`.
  - **Rows:** VEI HOLDS, then what ended it (`LOSS_WORDS`: "her fronts held · too few fell in time", "the horde was ferried · she did not break", "Relish fell with no backup left"); FIGHT TIME; BACKUPS SPENT (cracked rings, "n of m"); BIG UNDEAD LOST; BACKLOG; AFTER (only after a final death).
  - **Big undead lost** is the whole seed party ("5 of 5"), not the result's `party_lost` (only those who fell in the scene): MECHANICS §6 and STATE-API §8.3 kill the whole party on a loss, and `writeback_boss` removes every seed uid.
  - **Backlog is a share, "35% stays"** (`loss_backlog_keep`, the one config number). Economy multiplies Vei's live `undead_queue` at the writeback (STATE-API §8.3, `state_runs.gd writeback_boss`). That is neither the seed's `backlog` (her queue at issue; it moves while Relish is away) nor what is left after `backlog_spent` (informational, A10). A number would need the live queue, which only economy has.
  - **AFTER** is `RaidLogic.death_next_row`'s text on the seed's `death_ends` (words from raid.json `death.after_*`, passed in): "unmade · reforms at Covington", " in N min" only when respawn_s > 0, then " · the town takes a morale shock" (a boss final death runs `StateRuns.death(gs, run_id, 0)`: she is unmade and the town takes the shock). It is shown only for `relish_unmade`; with `fronts_held` or `horde_ferried` she is alive at Vei. A seed without `death_ends` reads "unmade · reforms at Covington · the town takes a morale shock" (clones_ready is passed as 0: a final death spent every clone). The value is long, so VeiCard lays its rows out from a list of {label, text, key} (`VeiCard.layout_rows`): a value that does not fit beside its label goes on lines under the label, wrapped in the plate's full value width, and the plate grows past `card.loss_h_px` (the minimum) by what the wrapped rows need.
  - **Button** reads "BACK TO THE REALM", the win card's wording; nothing else in the realm says "COVINGTON" on a button.
  - **Reduced motion:** the card is static; nothing animates beyond the dim. No Palette key added.
  - Tests: every end_reason, backups 0/1/2, `death_ends` absent / 0.0 / 60, source guards (`_lose_card`, the sequence's end). Shots: `dz-vei-loss.png` (a bot timeout loss, backups 1+1 unspent) and `dz-vei-loss-reduced.png` (autodie, final death).
- **The retreat dialog:** a big still walking to the plate (`sent`) reads "X is sent to the plate · lost if you retreat."; `held` keeps "is on the plate". Tested.
- **Not done, by the manager's correction:** the held door's entry line (the item was dropped).

## Telemetry bytes changed at K-f (f723711)

- **Horn over a toll's tell** (`WardenBellringer._step`): the cancelled beat is un-booked, so for runs with a horn over a toll beat the bot's telemetry differs from before K-f: the `bell` tallies (`_toll_tally`), `toll_beats`, and `bell` itself when the only counted toll was cancelled. The sim, RNG and timing are unchanged (nothing acts on `toll_beats` or `toll_marks`), so the bot's result line, e.g. seed 60 (`exit warden_beaten, duration_s 129.13, raises 20, allies_end 15, warden_wake_s 14.3`), is identical. Frozen telemetry lines of horn-over-toll runs are not byte-identical to earlier ones.
- **"Booked" means a qualifying beat** (the review-kf follow-up): `toll_beats` drops by one whenever a horn cancels a beat that was counted, whether or not its toll was placed (`_toll_beat_booked`). `toll_exit_px_max` is not rolled back: it is the worst case over placed tolls, a cancelled one included.

## Warned-attack assist (raid.json `assist`, `RaidLogic.assist_on`)

- **What it is:** an optional, off-by-default accessibility switch (CONTROLS legend row LONGER WARNINGS, or `--raid-assist`). On, every warned attack's tell window is x `tell_mult` (1.5), read through `WardenLogic.attack_tell` / `tell_len`. Session memory only. A flip applies from the next tell a warden lays, never inside a running one: each warden keeps its current tell length in `_tell_cur` (`RaidWarden._tell`), refreshed from `attack_tell` by `WardenLogic.latch_tell` only while it is not inside a tell (the Huntsman: not locked); every in-tell read and draw uses it. The hit beats, damage, RNG and loot are untouched. Off branches out before any multiply and is byte-identical to before. `tell_mult` is clamped to at least 1.
- **Trade-off, accepted:** after a pack rest the Bellringer, Shieldwall and Pyre-priest place the next hit with `WardenLogic.after_rest(beat, tell, rest)` = `ceil(ceil(beat) + tell + rest)`: on (tell 1.5) the first hit after a pack rest can land up to a beat later than off, on a whole beat, so every later hit (`last + period`) stays on the Pulse. Only the pack rest uses `after_rest`: a phase pull is `maxf(b + tell, last + period)` (bellringer, shieldwall, pyre-priest, huntsman), not rounded, off the beat on and off alike (that predates the assist). Off the operand is already whole, so nothing changes. In the short periods (2 beats) a warden also has less time between tells.
- **Bellringer toll:** on, its reach budget is sized by `WardenLogic.lay_len(tell, next_attack, beat)`, the time actually left when the tell begins late (a flip is latched once a tell is running, but an off-to-on flip in the half beat before a 1.0 tell would have started can start a short, 1.5 warning that is already part-way gone; a phase pull starts its tell on time; no revive touches the Bellringer's schedule).
- **Gap words:** the AWAY TOO LONG banner is `gap_end.banner_text` (the raid) or `gap_end.banner_text_boss` (the Vei fight: a boss run has no checkpoint, the state forfeits it and the party is intact); the legend row's words are `hud.legend.assist_label` / `assist_on` / `assist_off`.
- **Vei:** the drawn tell is `WardenLogic.lay_len(tb, next_beat, beat)`, never more than the beats left to the weave, so a late lay's thread and tick countdown match the hit, on and off.
- **Edge details, not changed:** a Bellringer phase-3 tell can start while the last ring is still out (0.6 beat), so its warning is up about 1.4 beats, not 1.5; and the bot's "untold blow" window in `raid_autopilot.gd` assumes `tell_mult` up to 1.5 (it feeds nothing).
