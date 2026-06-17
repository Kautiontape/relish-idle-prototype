# Graveshift — agent guide

**The spec is [DESIGN.md](DESIGN.md).** This prototype tests **the town as a
self-running machine**: is assigning undead workers, watching the yard run, and
fixing bottlenecks fun on its own — combat handwaved? Cozy + Factorio, not
RimWorld (the undead have no needs, so there's no needy-colonist drama to lean
on; see DESIGN.md "Why this question").

Sibling prototypes: `../raid-and-raise/` (the raid), `../slab/` + `../crypt/`
(the raise / horde). These share **no code** — config shapes (the eight stats,
aspect/archetype language) were copied, per the monorepo's copy-paste-is-fine
rule.

## Headless commands (verify every change)

```sh
godot --headless --import                              # reimport after adding files
godot --headless --script res://tests/smoke_test.gd    # sim suite, exit 0 = green
godot --headless --quit-after 150                       # boot the yard (watch for errors)
godot --headless --export-release Web build/web/index.html   # web export (needs 4.6.x web_nothreads templates)
docker build .                                          # deploy gate: import + smoke + export
```

Godot 4.6.2 (Dockerfile pin), Compatibility renderer, portrait 400×866,
single-threaded web export. Local dev engine may be 4.6.3 — the smoke test runs
locally; the **web export only works against matching templates**, so verify the
export via `docker build` (which pins 4.6.2 and fetches the matching templates).

## The loop in one line

Drag undead onto **Quarry** (harvest bone) or **Workshop** (fetch bone → craft a
good → haul to **Storehouse** → Supplies +1). The bottleneck is the crew ratio;
aptitude (Beef/Power harvest, Wits/Power craft, Speed walk) sets the pace.

## Architecture

- `scripts/autoload/config_db.gd` — `ConfigDb`: loads `configs/*.json`, live-
  editable (`set_v` / `reset_tunables`). Only autoload.
- `scripts/systems/roster.gd` — `Roster.make_worker()`: weighted archetype +
  jittered eight-stat line. The faked "crypt sends N."
- `scripts/systems/sim.gd` — `Sim`: the work-machine. Stations (with bone
  `stock`), the worker FSM, aptitude (**live-read from ConfigDb each tick** so
  sliders bite immediately), throughput (rolling window), ambient living. Pure
  RefCounted logic + Vector2 math — **no rendering**, so the smoke test ticks it
  headlessly. Construct with `Sim.new(rng)` then call `setup()`.
- `scripts/ui/yard.gd` — `Yard` (Control): custom `_draw` of the whole yard,
  drag-to-assign input, Supplies bar, the debug panel. Owns the `Sim`, ticks it
  in `_process`.
- Scenes are built in code; `scenes/main.tscn` just hosts `main.gd`.

## Terms

- **Station** — a fixed spot (`yard.json`). Kinds: `quarry`/`workshop` are
  **assignable** (you crew them); `storehouse` is a passive sink; `pit` is the
  idle home; `inn`/`market` are ambient amenity spots for the living.
- **Aptitude** — `1 + aptitude_strength · Σ(relevant stats)`. Multiplies work
  speed (shorter harvest/craft time); Speed adds to walk px/s separately.
- **The crew ratio** — the thing you tune. The bottleneck is intentional and
  visible: a starved bench crew waits at an empty quarry.

## Made up here (not handed down by a spec — flagged per prototype rules)

- **Everything is config-driven** (`stats`/`workers`/`yard` JSON); no numbers
  hardcoded, per the monorepo rule.
- **Self-haul, one chain** (Quarry → Workshop → Storehouse): the cheapest shape
  that still produces a legible bottleneck + visible scatter. Dedicated haulers /
  multi-stage logistics deferred (DESIGN.md).
- **Four archetypes** (Brute/Tinker/Runner/Hollow) so placement has a right
  answer to discover; the eight-stat line is carried but only four stats are read
  (the rest wait for living-as-customers).
- **Idle Q/W hint glyph** — shows each idle undead's best assignable station, to
  teach who-goes-where. Toggle in debug.
- **Pointer-only input** (drag = touch via `emulate_touch_from_mouse`); **no held
  keys** (laptop trackpads drop the pointer under a held key) and a
  `debug_ui_scale` window-scale knob (phone-sized canvas otherwise feels tiny on
  a desktop). Both per the desktop-input memory.
- **Debug panel is first-class** — live sliders (harvest/craft time, walk speed,
  aptitude weight, living count) + crew/stock/throughput readouts + Living/Job-
  hint toggles + reset. The knobs ARE the prototype.
- **Ambient living** wander Inn↔Market only — vibe, zero mechanic.

## Gotchas

- **Reassigning a carrying worker drops its cargo** (assign resets FSM state +
  clears `carrying`). Acceptable for a prototype; noted in case it ever matters.
- **Web export version match**: a 4.6.3 local engine can't export with 4.6.2
  templates (and vice-versa). Don't chase it locally — `docker build` is the gate.
