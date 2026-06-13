# The Slab — agent guide

**The spec is [DESIGN.md](DESIGN.md).** This prototype tests **build expression**
(does making a creature feel like making something yours) plus the **bone-pit
floor**. It is Phase 2, prototype 1 — the raise screen, with the raid faked.

Sibling prototype: `../raid-and-raise/` (Phase 1, the combat loop, frozen at
`raid-and-raise-v0.0.1`). These share **no code** — config shapes were copied,
per the monorepo's copy-paste-is-fine rule.

## Headless commands (verify every change)

```sh
godot --headless --import                              # reimport after adding files
godot --headless --script res://tests/smoke_test.gd    # math suite, exit 0 = green
godot --headless --quit-after 120                      # boot the crypt (watch for errors)
godot --headless --export-release Web build/web/index.html   # web export
docker build .                                          # deploy gate: import + smoke + export
```

Godot 4.6.2, Compatibility renderer, portrait 720×1280, single-threaded web export.

## Architecture

- `scripts/autoload/` — `ConfigDb` (all JSON, live-tweakable), `GameState`
  (material pool: forms + remnants + scraps, the shelf, the `Ossuary` instance).
- `scripts/systems/` — `loot.gd` (remnant/form rolls, copied), `build_state.gd`
  (form + slotted remnants → derived stats/echoes/name), `creature_namer.gd`
  (Adjective Noun), `ossuary.gd` (the bone pit).
- `scripts/ui/` — `creature_preview.gd` (the morph — one stat, one verb),
  `crypt.gd` (the whole room, built in code), `main.gd`.
- Scenes are built in code; `scenes/main.tscn` just hosts `main.gd`.

## Terms

- **Form** = husk (the body). **Remnant** = a slotted trait-piece. **Rune slot**
  = where a remnant goes; its **aspect** (muscle/nerve/presence/anima) gates which
  remnants fit. The form gives no stats — a blank form is a **Hollow** creature.

## Made up here (flagged per prototype rules)

- **Crypt-as-room** (user-directed): central slab, runes bloom by anatomy, bone
  pit + Vei statue in the corners. The build flow + live morph + live ghost-name
  + name-your-friend prompt are the test.
- **Adjective Noun naming** (user-directed): echo wins, else dominant stat, else
  "Hollow". Tables in `names.json`.
- **The bone pit** (user-directed): one fullness meter = quality dial; feed
  (diminishing returns) → pull (always gives something, scales with fullness,
  consumes a chunk); output hard-capped below loot; depletion on pull, passive
  decay a debug toggle. The anti-stalemate floor (you can't reach zero undead).
- **Faked raid** (haul button) and **deferred** Jar/town/persistence/Vei-fight —
  see DESIGN.md. Don't add them; they'd pollute the build-expression test.

## Gotchas (learned the hard way)

- **Rebuild-then-restyle ordering:** `queue_free()` is deferred, so rebuilding the
  rune ring must `remove_child()` first — otherwise stale rune nodes linger a
  frame and get indexed against the new/empty `slots` array (out-of-range →
  `Color("")` spam). `_restyle_runes()` also bounds its loop to `slots.size()`.
