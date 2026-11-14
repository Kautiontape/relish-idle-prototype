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


## Vei's final test (task 9b)

`vei_boss.gd` rebuilds the boss on fronts, then the break (MECHANICS 6, GAMEPLAY 3d). Rules are `VeiFronts`; `BossLogic` places and counts; `BossLanes` draws the fronts; `RaidVei` is Vei and her weaves. Knobs: `configs/vei.json` (each block has a `_doc`). Dev: `boss_dev.gd` (`--boss-phase2`, `--boss-stress`, `--boss-fronts=n`, `--boss-backups=p,c`, `--boss-autodie/autowin=<frames>`, `--boss-hold-tell`, `--boss-prof`, `--boss-hide=`) and the bot `--boss-autoplay=<score>` (`boss_autopilot.gd`).

- **Guards go for Relish** (`BossGuard`, `vei.json guards.block_px` 50): a guard targets Relish and fights an undead only when one is within `block_px` (in its way). Why: with RaidUnit's own pick (the nearer of Relish and the nearest undead), the party's big undead at her court absorbed every guard, Relish never died in any autoplay, and her backups never mattered. The task reads "they hunt Relish and the undead"; the undead round her are her shield, and the sacrifice chain is what a guard that reaches her costs.
- **Deviation: the break is 20 beats with a lapse cost, not 8 consecutive beats** (task 9d). MECHANICS 6 says Vei breaks after `break_beats` *consecutive* beats with raise > ferry, and BALANCE 5 lists `break_beats` 8. As built (`configs/vei.json`): `break_beats` 20, and a beat without raise > ferry (a lapse) costs `lapse_cost` 4 beats of the streak instead of resetting it (`VeiFronts.break_beat`; `lapse_cost` -1 restores the reset, the code default). Why: 8 beats made the climax about 30 s and often under; 20 beats gives a 45-75 s break, and with a full reset one lapse late in a long streak threw away most of a minute.
- **The sacrifice chain is the dungeon's** (MECHANICS 5.0): a lethal hit on Relish spends chaff, then soldiers, elites, then the party's big undead, nearest within a rank (`VeiBoss.sacrifice_nearest_ally` overrides raid.gd's old boss branch, which took the plain nearest and could spend a named big undead before the chaff beside it).
- **A revive readies her trance** (`RaidTrance.ready_now`: the cooldown is spent, no stored free raise), so a backup lets her raise a new ward at once.
- **The first weave's tell is 2 beats** (`weaves.first_tell_beats`), one more than the spec's one-beat tell (`tell_beats` 1), as part of the "Vei's first weave" set piece: the thread draws itself out from her while a banner names it. Every later weave tells one beat ahead.
- **`raised.unit_cap` 20 is a perf cap.** Raises past it still count toward the break (their value feeds `break_beat`) but add no fighters. It also bounds her ward (the sacrifice chain), so it doubles as a gameplay limit; calibrate them together.
- **The horde-drained loss exists but is out of reach at demo numbers.** H is the seed's backlog (~18k) and Vei ferries it at F (~3.4/s at pool 380, q 2.6, one uncleared front), so draining takes about 90 minutes. In practice the break is a race against deaths. A Vei-calibration item; left as is.
- **fronts_cleared** in the result is the list frozen when the break begins, or, for a fight that ends in phase 1 (timeout, final death, close), what phase 1 had cleared (`BossLogic.fight_result`).
- **Legacy removed from the shared files**: raid.gd's `ledger` and the boss `_build` branch that built it, the boss branches of `on_unit_died` (VeiBoss overrides it whole), `spawn_unit`'s guard branch, the `args.boss` setup branch, `backlog_left`/`army_lost`/`_on_ally_died`/`spawn_orb`, `RaidUnit.ledger_mass`/`from_army`, and `raid_raise.gd _perform_legacy`. Kept: `sacrifice_nearest_ally`'s boss rank-0 rule (live: the boss sacrifices the plain nearest ally; Vei's balance was set with it), and `RaidLogic.Ledger`/`raise_spec` as test-only fixtures (`test_results.gd` builds a v1 result with them).
