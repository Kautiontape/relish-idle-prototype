# NOTES-TOWN — the Covington scene

## Files

- `scenes/town/Covington.tscn` — root Control + script, nothing else; all UI is built in code.
- `scripts/town/covington.gd` — scene root. Contract surface (`finished` signal, `setup`, `demo_seed`, standalone self-seed in `_ready`), the whole right-hand sidebar, refresh/affordability wiring, result emission.
- `scripts/town/town_yard.gd` — the left diorama (custom `_draw`, graveshift-style). Purely cosmetic: one green dot per assigned worker on a station<->supply walk loop, idle dots loitering at the Slab, living traders at the Trading Post, gather convoy in/out at the yard edge. Reads counts live off TownLogic each frame; owns no numbers.
- `scripts/town/town_logic.gd` — `TownLogic` (RefCounted, UI-free): assignments/steppers, builds, simulacrum crafting, spend tracking, result dict. Everything the tests drive.
- `configs/town.json` — every number and every line of player-facing copy: costs, simulacrum charges/rate, effect strings, blurbs, spend grace, yard geometry (normalized station positions, radii, colors, walk speeds, supply points, roads, exit point).
- `tests/test_town_logic.gd` — 54 assertions, TestUtil pattern (`run() -> int`). Not wired into `run_tests.gd` (not mine to edit); verified via a temporary SceneTree runner, since deleted.

## How the result maps

`setup(seed)` freezes the snapshot. TownLogic copies `town`/`assignments`/`idle_undead`, and takes `res.gold/materials` as a local funds view that only ever *decreases* by purchases. On RETURN:

- `town` — the possibly-upgraded copy (slabs/vats/sim_stations/forge_level incremented by buys).
- `assignments` / `idle_undead` — stepper state; total assigned + idle is conserved (tested).
- `spend` — **deltas**, the sum of purchases this visit; never exceeds seed res + `spend_grace` (config, 5.0 — the live totals only grow while the scene is open, so a small overshoot against the stale snapshot is safe; `Game.apply_town_result` already clamps at 0).
- `gather_target` — from the "gather from" dropdown; `""` = auto (richest).
- `deploy_simulacra` — only NEW crafts this visit (`{fort_id, charges, rate}` with charges/rate from config); seed simulacra are displayed under ACTIVE ARCANA but never echoed back.
- `teleport_to` — always `""`.
- Emitted exactly once (`_finished` guard); button flips to "— DEPARTED —" in standalone runs.

## Knobs (all in configs/town.json)

- `costs.*` — slab 25 x current count, vat 30g/8m, station 80g/40m once, simulacrum 30m, forge 12m x (level+1).
- `simulacrum.charges/rate` — 300 / 3.
- `forge_quality_bonus` — 0.25, display-only mirror of realm.json `q_per_forge` (header q updates live as you buy forge levels).
- `spend_grace` — overspend allowance vs the stale snapshot (default 5.0; tests pin behavior at 0 and 5).
- `copy.*` — all sidebar strings.
- `yard.*` — station positions/radii/colors, walk/work speeds, living count, convoy speed, roads.

## Deviations / judgment calls

- Station-click nice-to-have IS in: clicking a yard station rings it green and scrolls/flashes the matching sidebar row (worker stations -> assignment rows, vats -> vat button, sim station -> craft row).
- The convoy animates a repeating leg (walk, fade out, respawn) because the seed's `eta` is frozen while the live sim ticks elsewhere; the phase ("out"/"back") and the grey load marker are truthful, the motion is theater.
- Living traders amble even at trade crew 0 — pure vibe, matching graveshift.
- `demo_seed()` is a mid-game snapshot (vat, station, convoy returning, one field simulacrum) so a standalone boot demos every system; the true fresh seed was also screenshot-verified.
- Quality readout uses seed quality + bought-forge delta only (elite contribution etc. stays the realm's business).

## Verification

- `godot --headless --import`: clean, no script errors.
- Tests: 54/54 PASS (temporary runner used and deleted; `tests/` contains no tmp file).
- Screenshots reviewed at each iteration:
  - `/tmp/necropolis-town.png` — demo seed, final look.
  - `/tmp/necropolis-town-clicks.png` — after 2 clicks on Trade "+" (2->4, idle 4->2, yard crew label + dots follow) and a Forge station click (highlight ring visible).
  - `/tmp/necropolis-town-return.png` — after clicking Slab +1 then RETURN; stdout showed the emitted result: `spend {"gold":50}`, `slabs:3`, `gather_target:"vespers"`, `teleport_to:""`.
  - `/tmp/necropolis-town-fresh.png` — prompt's exact base seed: locked/unaffordable buttons greyed, no vats/sim station/convoy drawn, 6 idle dots at the Slab.

## Rough edges

- Worker dots draw *under* station fills/labels (deliberate, keeps text legible); a dot crossing "x2" on the Slab can still kiss the glyph.
- Yard positions are normalized to the panel, so extreme window aspect ratios stretch the layout (expand-aspect project; fine at 16:9-ish).
- The `world_map` errors in boot logs come from another scene loading first under the Shot harness; not from this scene.
- Effect text in assignment rows clips on very narrow windows (tooltip carries the full line).
