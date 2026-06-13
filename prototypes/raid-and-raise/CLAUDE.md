# Raid & Raise — agent guide

**The spec is [DESIGN.md](DESIGN.md).** It is a final-state specification: no archaeology, no alternatives. Where a value is a number it lives in `/configs/*.json`, never hardcoded. This build covers **Phase 1 only** (the raid); Phase 2 (the Slab/Jar/economy) waits for the human gates in DESIGN.md §12.

## Headless commands (verify every change)

```sh
godot --headless --import                              # reimport after adding files
godot --headless --script res://tests/smoke_test.gd    # full smoke suite, exit 0 = green
godot --headless --quit-after 60                       # boot the real main scene
godot --headless --export-release Web build/web/index.html   # web export (needs web_nothreads templates)
docker build .                                          # the deploy gate: import + smoke + export
```

Godot 4.6.2, Compatibility renderer, portrait 720×1280. Web export is single-threaded (`variant/thread_support=false`) so no COOP/COEP headers are needed.

## Design invariants (§15 — the tiebreakers, in order)

1. **One stat = one watchable verb.** If a mechanic can't be seen working in a crowd, it doesn't ship.
2. **Input feel is sacrosanct.** Nothing — no stat, no state — degrades command responsiveness.
3. **Fields bias movement; they never disable combat.**
4. **Luck sets pace, never ceiling.**
5. **Identity emerges from the build,** not from the drop.
6. **Relish is the conduit, not a commander and not a fighter.**
7. **The thumb belongs to the circle.** Any feature competing for it loses.

## Do not build (§14 earmark ledger)

Mutations · essence-typed spell-casting · remnant reroll · Anima-hollow ascension · Jar slot growth · flavor renaming of stats/aspects · loot/hoard climax variant · the full idle town · minion micro beyond group-and-point · a "rally" gesture · line of sight · camera zoom · procedural tombs · meta-progression around death beyond the total wipe.

## Architecture map

- `scripts/autoload/` — `ConfigDb` (all JSON, live-tweakable), `GameState` (run haul + §12 telemetry + debug flags), `EntityFactory`
- `scripts/entities/unit.gd` — the ONE entity code path (Relish/permanent/chaff/enemy differ only by setup dict + faction)
- `scripts/systems/` — `battlefield.gd` (arena: nav bake, walls, force fields, sacrifice chain, drops), `trance_controller.gd`, `command_controller.gd`, `circle_scorer.gd` (Kåsa least-squares fit), `loot.gd`, `raid_director.gd` (tomb geometry + chamber chain)
- `scripts/playrooms/` — isolated mechanic test rooms (prototype harness, not spec)
- `scripts/ui/` — `hud.gd` (trance button, screens), `debug_panel.gd` (tunables/spawn/flags/telemetry/rooms)
- Scenes are built in code; `scenes/main.tscn` is the only .tscn.

## Made up here (not in DESIGN.md) — flagged per prototype rules

- **Starting squad** (`configs/loadout.json`): Phase 1 has no Slab, but the sacrifice chain needs permanents. Config-defined default 5-permanent loadout = the Jar stand-in.
- **Desktop input mapping**: hold SPACE = hold the corner button; mouse = thumb. **Right-mouse-drag is a one-handed trance**: press RMB = hold the button, the drag is the trace, release = summon (laptop trackpads suppress the pointer while a key is held, so Space+drag fails there). Phone via the deployed URL is the true input test.
- **Debug scale knobs** (`stats.json`): `debug_ui_scale` (window content scale — world+UI, for HiDPI desktops) and `debug_view_zoom` (camera only). Harness knobs, not game zoom (§14 still bans pinch zoom).
- **Field force units**: §6's `F = k·stat/d` reads `d` in 100px units (raw px made forces invisible at spec magnitudes). `field_strength` is a slider anyway.
- **Trance release lockout** (1s, `timers.json`): doc only specifies cooldown-on-summon; the lockout stops free bullet-time stutter-spam.
- **Remnant primary stat** is uniform among the eight; echo points land on ≤2 echoes per side, chunky.
- **Wits hold threshold reuses** the §11 lock threshold (≥3); low-Wits drift delay 2s.
- **Magic units are pure ranged attackers** (bolt replaces melee) — keeps "bolts flying" watchable.
- **Sacrifice is global-nearest** (soul link), not radius-limited; a red fx line makes the chain legible.
- **Enemy statlines, chamber layouts, boss adds waves** — authored to the doc's archetype list and counts.
- **Playroom roster**: trance gym, force field, targeting, sacrifice, command, obstacle course (user asked for the concept + the magnetism and obstacle rooms; rest are my picks for the riskiest mechanics).
- **Lasso-path grammar** (user-directed, playtest): close the lasso and keep dragging — the loop selects mid-stroke, the rest of the stroke streams live as the group's path; with an active selection a new drag is also a path. Still group-level (one path for the whole selection), so the §14 "no micro beyond group-and-point" ban is stretched to group-and-path on the design owner's call. Esc clears selection; expiry raised 2s→4s (`timers.json`) on playtest feedback.
  - A loop seals wherever the stroke crosses ITSELF (self-intersection), not only back at its start.
  - The group starts following only once the drag pulls `path_start_px` away from the loop (no twitching while you finish the circle).
  - Tapping Relish clears the selection (resets the grammar); her drag-grab radius is generous (+34px).
  - **Open-swipe fallback** (user-directed, playtest): with no selection, a released stroke that is neither a tap nor a lasso and didn't start on Relish becomes HER path — she walks the drawn line from its start. Every swipe now does something.
- **Summon presentation** (user-directed): enclosed essence is pulled into Relish with accelerating speed (fwwwwooomp), then each chaff grows out of the ground beside her with a TRANS_BACK overshoot (rrawwwwr). Spawn point moved from the essence position to a ring around Relish (`circle.json: grow_ring_px`) — flagged: this changes where chaff enter the fight.
- **Door-anticipation escort** (user-directed): idle minions don't trail Relish between chambers — they move to and THROUGH the doorway her live velocity points at (cone + range in `stats.json: escort_*`), entering the next room ahead of her. Velocity-based, so backtracking and forks need no scripting. Supports doc §13.4 (auto-behavior good enough that commands are optimization).
- **Chamber transition** (user-directed, playtest): each exit has a door glow (`fx_door_glow.gd`) — red while the room is locked, blue "come on in" when cleared. Advance triggers when Relish reaches the doorway ZONE (`stats.json: exit_zone_px`), not when she fully crosses into the next room (that crossing was dead air). On the slide, idle minions are hard-ordered through the door and any unit still off-screen when the slide ends snaps to a ring behind Relish (invisible off-screen teleport — escort never stranded).
- **Tail-tolerant circle scoring** (user-directed): the score grades the sealed loop (start → closest approach back to start after ~270°, `circle.json: seal_arc_deg`); the stroke past that is a tail, punished gently (`tail_weight`) not as a giant closure gap. Closure lightened (`closure_weight` 0.35→0.15) so stopping a little short barely costs you — coverage² already gauges going all the way around.
- **Color legibility** (user-directed): chaff recolored off-green to ash-lavender (green is reserved for essence so a fresh batch reads against the horde; army cool-toned, enemies warm). Essence gets a wide faint halo (`circle.json: essence_halo_px`) that stacks where essence overlaps — a good batch pools bright green above the crowd.
- **Trance legibility** (user-directed, playtest): holding the button through a cooldown now auto-re-enters the trance when it clears (was stuck in READY-not-active limbo). Cooldown fills toward ready in bright amber (the old dark-on-dark wedge was invisible). A pulse radiates from the button across the lower screen — green "ready" on cooldown-clear, red "not yet" on a too-soon press (reads even under a thumb). The trance gym locks the trance ON (no hold/cooldown/dilation) for back-to-back scoring reps (`TranceController.set_locked`).
- **Menu** (user-directed): first screen has ENTER THE TOMB + a live settings row (Trance button side, UI scale, camera zoom); playrooms moved behind a TEST CHAMBERS submenu so the menu reads as the game, not a harness.
- **Perf** (user note): `living()`/`hostiles_of()`/`field_bias()` cached per physics frame in `battlefield.gd` (was O(n²) array churn that tanked the end-of-run frame). Behavior-neutral — avoidance/neighbor settings deliberately untouched (the crowd interaction is the point). `tests/perf_probe.gd` measures physics cost vs unit count.
- **No audio** (heartbeat/muffle earmarked with polish); trance mode-state is carried visually (dim overlay, essence ignite, trace color).

## Known tensions in the doc (resolved, not hidden)

- §13.6 "no healing exists" vs the Life Drain echo (§7.2): the echo is doc-listed, so it ships as the one sanctioned exception.
- §8.2 audio cues: omitted (see above) — visual channel only.
