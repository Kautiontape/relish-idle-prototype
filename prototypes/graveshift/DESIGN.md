# Graveshift — design spec (the town, prototype 1)

A throwaway test of **the town as a self-running machine** — the third prong
beside the Raid (active combat) and the Crypt/Slab (build + horde management).
It is **not** the town's economy, its tech tree, or its immortality arc. It
isolates the one question that decides whether the town is worth building at all.

## The question

**Is running a settlement of needless, tireless undead — assigning workers,
watching the machine run, spotting and fixing bottlenecks — fun on its own,
fighting handwaved?**

Pass/fail signal (the counterpart to the Slab's "name your friend?"): **you
leave it running just to watch, and you reach in to fix a bottleneck because you
*want* to, not because a popup nagged you.**

## Why this question, and not "is city-building fun"

City-building is a solved, known-fun genre — testing it teaches nothing. The
Relish-specific twist is that her workers are the **undead**: dumb, tireless,
needless. That *deletes* the engine of RimWorld's fun (need → scarcity →
fragility → stories) and pushes the town toward **Factorio** — engineer the
throughput, watch it flow, fix the bottleneck, scale it. So the real risk, and
the only thing worth prototyping first, is: with the needy-colonist drama gone,
is the machine itself satisfying to tend? If yes, the living/masquerade/
immortality layers are spice we add later. If it's an inert spreadsheet, that
tells us the drama isn't optional — it's the load-bearing fun.

## The fiction

The undead are "super stupid workers, good at a single task, but in aggregate a
machine that functions." The living arrive from elsewhere and mill about the
amenities, either ignorant of or at peace with the undead fortress around them.
The town exists to **fuel Relish's other endeavors** — for now that's an abstract
**Supplies** meter; later it becomes gold, gear, and the infrastructure of her
refusal to die.

## The loop (what's built)

1. **A bird's-eye yard.** Fixed top-down screen. Stations are blobs: a **Bone
   Quarry**, a **Workshop**, a **Storehouse**, a **Bone Pit** (where the idle
   loiter), and an **Inn** + **Market** (where the living gather).
2. **~12 undead**, faked from a "the crypt sends N" button. Each is one of a few
   archetypes (Brute / Tinker / Runner / Hollow) carrying the full eight-stat
   line; the town reads four of them as **job aptitude** (Beef+Power → harvest,
   Wits+Power → craft, Speed → walk pace).
3. **One verb: drag.** Drag any undead onto the Quarry or Workshop to crew it;
   drop it on open ground to send it idle. No other input.
4. **One self-hauled chain.** Quarry crew stand and harvest **bone** into the
   quarry's stock. Workshop crew walk to the quarry, take a bone, walk to the
   bench, **craft** a good, carry it to the Storehouse → **Supplies +1**, repeat.
5. **The bottleneck is the crew ratio.** Overload the bench and its crew pile up
   at an empty quarry, waiting — visible starvation. Overload the quarry and bone
   stock just grows — wasted labor. Aptitude scales the pace, so a Brute on the
   quarry and a Tinker on the bench is faster than the reverse. Idle undead show
   a **Q/W hint** of the job they're best at.
6. **One meter.** Supplies climbs toward a soft target; a **/min** throughput
   readout is the Factorio "how much am I making" feedback.
7. **The living** wander between Inn and Market as pure ambient vibe — the cozy
   picture, no mechanic.

## Faked / deferred (NOT built — protects the test)

- **The raid / all combat** — the roster comes from a button, not a battle.
- **The living as customers** — they mill, they don't buy. Gold, demand,
  purchase: deferred.
- **The masquerade / suspicion** — the drama spice, added only if the machine
  proves fun.
- **Immortality, the cross-prong loop** (output arming raids / feeding an
  immortality bar) — deferred; the meter is abstract for now.
- **Building placement, construction, upgrades, tech tree** — stations are fixed.
- **Passive-while-away idle, save persistence** — deferred.
- **Pathfinding / obstacles** — straight-line movement; the yard is open.
- **Dedicated haulers / multi-stage logistics** — self-haul, one chain, for v1.

## Config map (everything tunable lives here)

- `configs/stats.json` — sim rates + coefficients: harvest/craft time, walk speed
  (base + per-Speed), **aptitude_strength** + which stats feed each job, supplies
  target, throughput window, ambient living count/speed, `debug_ui_scale`.
- `configs/workers.json` — the faked roster: start/send counts, stat jitter, and
  the **archetypes** (Brute/Tinker/Runner/Hollow: weight, aspect, color, stats).
- `configs/yard.json` — the stage: background, station list (id/kind/x/y/label/
  color), and radii (station/worker/living/reach/grab/idle-wander).

## Architecture

- `scripts/autoload/config_db.gd` — all JSON, live-tweakable (debug panel edits
  in place; `reset_tunables()` restores).
- `scripts/systems/roster.gd` — `make_worker()`: weighted archetype + jittered
  eight-stat line. The "crypt handed you these" fake.
- `scripts/systems/sim.gd` — the work-machine: stations, the worker FSM
  (idle / quarry harvest / workshop fetch→craft→deliver), aptitude (live-read so
  sliders bite), throughput, ambient living. Pure logic, headless-tickable.
- `scripts/ui/yard.gd` — the bird's-eye view: custom `_draw`, drag-to-assign
  (pointer-only, no held keys), Supplies bar, first-class debug panel.
- Scenes are built in code; `scenes/main.tscn` just hosts `main.gd`.
