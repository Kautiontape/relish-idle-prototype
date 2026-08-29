# Necropolis

The "sum of all concepts" baseline: one playable Godot prototype combining the
canonical REALM strategic map (relish-realms), raid-and-raise circle-drawing
combat, slab/crypt unit ideas, and a graveshift-style Covington town — an idle
game about building a giant undead factory and drowning a goddess in the dead.

Green = UNDEAD. Orange = LIVING. Grey = DEAD (matte, never glows). Blue = towns/allies.

## Run

```sh
godot --path prototypes/necropolis        # Godot 4.7, GL Compatibility, 1600×900
```

## The loop

1. **The Realm** (world map): the sim never sleeps. Covington (bottom-right)
   mints undead and dispatches them at living fortresses; garrisons grind them
   back into corpses that get shipped to Vei (top), who recycles them into
   fresh soldiers. Undead kills stay on the ground as corpses Relish can
   harvest — the critical asymmetry. The necrosis field shows territory;
   holding ground entrenches it and it spreads faster.
2. **Click a fortress → Teleport** to raid it: kill living, then hold SPACE /
   right-mouse for trance and draw circles around essence to raise undead.
   Sloppy circles = chaff (thrown at Vei to clog her digestion). Clean circles
   = soldiers/elites (your army, banked at Covington).
3. **Click Covington → Enter** to run the factory: assign undead to trade /
   forge / jobs / gather corpses (travel time is real), build slabs (minting),
   clone vats (death insurance), simulacrum stations (auto-raising copies of
   Relish with limited charges).
4. **Vei's Domain** shows the only global undead numbers: the massed backlog,
   arrivals/s vs her digestion, and confrontation odds. When you like your
   odds — and your army — begin the final confrontation: a boss raid where the
   backlog streams in as the horde.

## Tests

```sh
godot --headless --path prototypes/necropolis --script res://tests/run_tests.gd
```

Suites: realm sim (conservation, asymmetry, break-even, Vei policy, EMPTY,
simulacra), influence field (entrenchment, pushback, perf), pacing (idle must
not win; the active factory crosses 60% odds at ~2.1 sim-hours), plus the
raid/town logic suites.

## Debug

- Map bottom-left: sim speed ×1 / ×10 / ×60.
- F12: screenshot to `user://`.
- CLI (args after `--`): `--shot=/abs/path.png --frames=N` (screenshot & quit),
  `--scene=res://...` (boot a specific scene), `--select=<node-id>`,
  `--teleport=<node-id>`, `--speed=<n>`.
- All tuning numbers live in `configs/*.json` — nothing is hardcoded.

## Layout

- `scripts/sim/` — pure-logic sims (RefCounted, autoload-free, headless-testable)
- `scenes/map|town|raid|boss` + `scripts/map|town|raid` — one scene per mode,
  swapped by `scripts/main.gd` via a uniform contract: `setup(seed)` in,
  `finished(result)` out. Every scene also runs standalone with demo data.
- `autoload/` — ConfigDb (JSON configs), Game (owns all state, ticks always), Shot (debug).

See DESIGN.md for the model and the design decisions; the session working notes
live outside the repo in `../relish-idle-working/`.
