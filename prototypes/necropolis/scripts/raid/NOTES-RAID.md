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
| `scripts/raid/raid_hud.gd` | CanvasLayer HUD: fort/tier, counters, trance meter, hint, RETREAT button + ConfirmationDialog (dungeon only), the boss block (fronts, horde, break pips, backups), standalone result panel |
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

- **The win card** (`vei_card.gd` `VeiCard`, built by `VeiBoss._win_card`): after the unravel and the green lanes, the board holds under a dim (`card.dim`) and one plate says VEI BREAKS, the fight time (`BossLogic.clock_text`), the backups spent as the BACKUPS row draws them (a cracked violet ring per spent one, a violet diamond or dot per unspent one, "n of m"), the big undead lost ("n of m", known party uids only) and the backlog spent (the result's `backlog_spent`, the only banked figure a boss result carries), over one "BACK TO THE REALM" button (`card.button_h_px` 54, never under 44; Enter, Space and Escape press it too). All of it is `BossLogic.end_card` plus drawing. The old 3.5 s banner is gone.
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
- `tests/parity_check.sh` runs the raid bot (old-sluice day1, hollow-redoubt tier 3, seed 1) and the boss bot (seed 1) with and without `--reduced-motion` and exits non-zero on any difference in the result lines (~1 min).

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

- **Facing (one rule):** it turns toward the densest crowd of undead within `face_reach_px` (240): for each undead's bearing, count the undead within the front half-arc of it; the most wins, a tie goes to the bearing nearest the current facing (an even ring holds still); the goal is that sector's mean bearing (`WardenLogic.shield_goal`, re-picked every `face_repick_s` 0.15 s). The flank-role undead are left out (else it would turn to them and cancel its own weak point). With no undead in reach it faces Relish while she is in its room, else holds. It turns at the phase's `turn_deg_s`, never past the goal (`turn_step`), and is planted (no turn) while a bash tell shows, so the lit arc is where the bash lands. Dormant, it faces the antechamber.
- **Hits (`hit_from`, the undead strike; RaidUnit calls it for any warden, the others forward it to `take_hit`):** the zone is read from the attacker's position (`shield_zone`). Front arc (±`front_half_deg`): GLANCE, ×`front_mult` 0.1, `clang`. Outside it: FLANKED, `flank` (`heavy` for a big undead); in full from the side, ×`back_mult` 2.5 from inside the back arc (±`back_half_deg` 45 round its back). The pips a flank hit takes are marked as the weak point's on the meter.
- **The bash:** every `period_beats`, telegraphed `tell_beats` (1) ahead: the front arc out to `reach_px` (140) is lit `danger`, with the word BASH and her edge warning when it covers her. On the beat every undead in it takes `dmg_unit` 10 and is shoved `shove_px` 50 straight away; Relish in it takes `dmg_relish` 12 (death card: "The Shieldwall's bash").
- **Phases** at hp thirds (the meter is notched there): turn 40 / 55 / 70 °/s, front ±80 / ±90 / ±100°, bash every 4 / 3 / 2 beats.
- **Weak point (wits ≥ 4, effect `flank`):** a party big undead whose wits meet it and whose target is the wall takes the flank role (`RaidWardenRun.flank_for`): it walks round the orbit (its radius + the wall's + `flank_gap_px`), `flank_step_deg` 40 at a time so it never cuts through the wall, to a post straight behind (several spread `flank_spread_deg` 34 apart), and holds its blow while it is on the shield's side. The standard t3 party's bigs have wits 4 and the t4's 5, so the stock party meets it, as for the other wardens. `--raid-party-wits=<n>` (with `--raid-profile`) sets every party big's wits, for the without arm.
- **Readability (tell -> counter -> labelled result -> meter drops):** the silhouette is a heavy `vei` shield arc over the front (one plate behind it per phase left; one falls away at each phase), a boss on the shield pointing where it faces, a helm and spine behind, and the back arc dashed with the word FLANK. A faint `danger` arc marks the bash's reach. GLANCE shows on the shield and FLANKED where the last flank landed (held `wardens.shield_label_s` 0.8 s). Each flank-role big is ringed `undead` with a line into the wall's back. HUD: "FLANKED ×n of m · took k" (the weak point's words until the first flank), row 2 "PHASE n/3" and the shield line from the spec ("front ±80° glances ×0.1 · back ×2.5 · turns 40°/s · bash every 4 beats"). Reduced motion: the facing is drawn at its sim angle, the tell's arc is steady and its word stays, the bash after-image is a step.
- **The bot** (`_vs_wall`): it keeps out of the bash arc grown by `wall_margin_px` 30 and `wall_margin_deg` 15, fetches only motes and pickups outside it, and otherwise waits `wall_side_deg` 110 off the facing, `wall_stand_px` 40 beyond the bash, walking round the short way and keeping its side until the other is `wall_switch_deg` 20 nearer. Its raises there walk in from the side. AUTOPILOT_RESULT gets a `shield` dict (hits, glances, flanks, backs, role hits, damage by kind, bashes, bash hits) for this archetype only; `warden_attacks` is bashes and `warden_attacks_weak_point` is flank hits.
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
- **Break meter:** 12 pips (`WardenLogic.pyre_meter`): `wardens.pyre_pips_per_acolyte` 2 per acolyte on the right (spent as they fall), its hp's pips on the left notched at the phase-3 gate (t3: 3 + 3 hp, 6 acolyte; t4: 2 + 2 hp, 8 acolyte), a notch between the two.
- **HUD:** "SNUFFED ×n · took k" (the weak point's words until the first snuff), row 2 "PHASE n/3", "ACOLYTES n/m" (hidden at 0), the fire line from the spec ("warded ×0.2 · 3 fires every 4 beats, 2 at Relish", then "exposed · 1 fire every 3 beats" in `danger`) and "burned n essence" (hidden at 0).
- **Readability:** the silhouette is a tall robe under a hood with a `danger` flame line above it (one band across the robe per phase left; one falls away at each phase), the pyre's matte logs at its feet; acolytes are small hooded glyphs, a matte cross once fallen. A lit area is a `danger` ground circle with flame ticks round its rim (shape as well as colour), filling brighter through the tell; "step off the fire" under the area nearest her the first time; her edge warns while she stands in one. After the beat the areas leave a short after-image and BURNED −N. Reduced motion: the fill is steady, the word FIRE sits in each lit area, the flame does not sway, the after-image is a step.
- **The bot** (`_vs_pyre`): while a tell shows it first carries out a mote lying in a lit area when the trip in plus the way out fits before the beat with `burn_safe_beats` 0.35 to spare, else steps off a lit area that covers her to `burn_clear_px` 16 beyond its edge (`WardenLogic.burn_exit`), rolled once per tell with `burn_step_off` 0.8 (a decent player misreads one fire in five, as `dodge` 0.5 is for the Huntsman's lunges). Then the living, then what lies outside the fire in its room; else it waits `pyre_stand_px` 60 beyond the living acolyte nearest her (seen from the priest) and holds a raise until within `pyre_raise_px` 120 of one (unless her carry is full), so the raised undead walk into it; exposed, it waits `pyre_exposed_px` 170 from it. AUTOPILOT_RESULT gets a `pyre` dict for this archetype only (acolytes, `acolyte_kill_s` from the wake, snuffs, `exposed_s`, burns, areas, essence burned, piles and pile mass burned, burn hits on undead, `burn_relish`, `burn_soaked` (the chain spent an ally for her), damage warded and exposed, `relish_min_hp`); `warden_attacks` is burn beats and `warden_attacks_weak_point` snuffs.
- **What the missing counter costs (the risk knobs):** `ward_mult` and `acolyte_hp` (how long a party without power is held in phase 1), `areas_per_acolyte`, `relish_areas_max`, `relish_spread_px` and `dmg_relish` (the fire on Relish while acolytes live), `dmg_unit` and `pile_burn_frac` (the army and the essence it loses), and the bot's `burn_step_off`. Without power the acolytes live until raises reach them, so the fire on her and the burned essence last.
- **Measured** (score-70 bot, seeds 1-20 per row, the standard party at tier: `--raid-profile=3 --raid-fort=mourners-gate`, `--raid-profile=4 --raid-fort=whitecross`; "without" adds `--raid-party-power=5`, one under the threshold: it takes the snuff and the hunting role away but also 1.2-3.6 of each big's damage per hit, since `dmg = 3 + 1.2 x power`; batch from a `git archive` of c478820; raw rows in the run's `reports/dungeon/pyre-raw.tsv`; fight = wake to the end, median [min-max] s; lowest hp is Relish's per run, 0 when she died):

  | fort, arm | beaten | Relish died | fight s | first / last acolyte falls, s after the wake | essence burned | fires on Relish (an ally spent for her) | lowest hp | big undead lost |
  |---|---|---|---|---|---|---|---|---|
  | mourners-gate t3, power | 19/20 | 1 | 102 [58-238] | 6 [1-32] / 8 [2-34] | 2 [0-17] | 2 (0) | 26 [0-30] | 11 of 40 |
  | mourners-gate t3, no power | 16/20 (2 timeouts) | 2 | 150 [31-582] | 25 [10-412] / 44 [24-469] (all fell in 14) | 3 [0-21] | 15 (5) | 22 [0-30] | 20 of 40 |
  | whitecross t4, power | 20/20 | 0 | 98 [57-120] | 18 [9-33] / 22 [13-34] | 2 [0-14] | 0 (0) | 26 [1-30] | 1 of 60 |
  | whitecross t4, no power | 20/20 | 0 | 155 [89-332] | 41 [21-249] / 79 [34-292] | 6 [1-11] | 49 (22) | 6 [2-30] | 5 of 60 |

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
- **Proposed score tie** (not built; for the next dispatch). One rule for every warden tell: per tell, a **miss** chance `m` (the tell is not answered: she keeps doing what she was doing) and a **reaction delay** `d` (an answered tell is acted on `d` after it starts), both set by the target score:

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
