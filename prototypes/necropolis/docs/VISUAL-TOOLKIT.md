# Visual toolkit: Palette, Pulse, LineGlow

Every scene speaks one line language: hot lines on a near-black ground, light
flowing along them, one tempo for the whole game. These three pieces are where
that language lives.

**The rule: no hardcoded `Color(...)` or tempo in scene scripts. Use `Palette`
and `Pulse`.** If a scene needs a colour that isn't in `configs/palette.json`,
add the key there and say so in your report. Don't write a literal.

| Piece | File | Tuning |
|---|---|---|
| `Palette` (static class) | `scripts/fx/palette.gd` | `configs/palette.json` |
| `Pulse` (autoload) | `autoload/pulse.gd` | `configs/pulse.json` |
| `LineGlow` (static class) | `scripts/fx/line_glow.gd` | `configs/line_glow.json` |
| `DriftFloor` (Node2D) | `scripts/fx/drift_floor.gd`, `shaders/drift_floor.gdshader` | `configs/ground.json` → `drift_floor` |

## Palette

```gdscript
Palette.c("undead")            # Color #39FF9E
Palette.c("undead", 0.4)       # same colour, alpha 0.4
Palette.hue("living")          # 17.8, the hue in degrees (feed it to Pulse.channels)
Palette.has("dead_lit")        # true
Palette.keys()                 # every key
```

An unknown key calls `push_error`, listing the known keys, and returns
`Palette.MISSING` (hot magenta), so the mistake shows on screen as well as in the log.

| Key | Hex | Meaning |
|---|---|---|
| `ground` | `#05060A` | the near-black ground |
| `undead` / `undead_core` | `#39FF9E` / `#C9FFE8` | undead, and the pale core of an undead glow stroke |
| `living` / `living_core` | `#FF6A2B` / `#FFD6B0` | living, and the pale core of a living glow stroke |
| `dead` | `#6E6A7E` | dead matter: matte, never glows |
| `dead_lit` | `#997FB0` | dead matter with Relish's violet falling on it (see below) |
| `town` | `#3E5C8F` | towns and allies |
| `relish` | `#C04CFF` | Relish |
| `vei` | `#FFF3D0` | Vei |
| `danger` | `#FF2D55` | danger |
| `graticule` / `contour` / `front` | `#12182A` / `#1E2A45` / `#3E5C8F` | Angiogram ground helpers (BRIEF §6) |
| `text` / `text_dim` | `#E8E8EC` / `#8888A0` | UI text, and secondary or label text |
| `ring_track` | `#202027` | the empty track behind a capacity ring |
| `select` | `#FFD000` | UI-only selection and focus accent; distinct from every matter colour, never used for matter |

**`dead_lit` is a lit surface, not a light source.** Dead matter never emits
light, but Relish's violet falls on the piles near her or on the one she targets.
The value is `dead` mixed 25% towards `relish`, then lifted 18% towards white:
hue 272° (the dormant violet), HSV saturation 0.28, about 5.8:1 against `ground`.
Draw it with `matte_*`, never with glow strokes. LineGlow refuses to glow it.

## Pulse

The tempo is T = 1714 ms, deliberately incommensurate with the 1 s game tick
(BRIEF §6). Pulse runs on wall-clock time, not `Game.time_scale`.

```gdscript
Pulse.phase()          # 0..1 into the current beat at the source
Pulse.phase(hops)      # the same, lagged for something `hops` route steps out
Pulse.wave(hops)       # pulse intensity: 1 on the beat, decays to ~0.04
Pulse.hop_phase(hops)  # the lag itself, in beats
```

`hops` is the route-graph distance from the source. It can be fractional, so a
point halfway along a route can pulse in between its two ends. On the map, use
Covington 0, fort 1, Vei 2. That's `map_max_hops`, which applies when you
don't pass `max_hops`. For another graph, pass its depth:
`Pulse.wave(3, 6)`. The lag is angiogram's `dCov / maxd`, scaled to
`wave_spread` (0.5 beats from source to farthest node), so the farthest node
never lands back in phase and the pulse reads as a wave crossing the realm.
The per-hop lag on the map is 0.5 / 2 = 0.25 beats.

```gdscript
# an expanding tempo ring at a fort one hop out (angiogram drawNode)
var b := Pulse.phase(1.0)
var w := Pulse.wave(1.0)
LineGlow.ring(self, pos, r + b * ring_reach, Palette.c("undead", ring_alpha * w), 1.0, 0.5)
```

### Routes: rate to u to five channels

```gdscript
var u := Pulse.rate_to_u(rate)                  # log(1+rate)/log(1+25), 0..1
if u == Pulse.OFF:                              # zero rate: the route is dark
	return
var ch := Pulse.channels(u, Palette.hue("undead"))
var off := Pulse.dash_offset(ch.speed, ch.period)   # walk dashes from -period + off
# for each dash `seg` (a PackedVector2Array of ch.dash px):
LineGlow.polyline(self, seg, ch.color, ch.width, 1.0, Palette.c("undead_core"))
```

`rate_to_u(rate, ref)` takes an optional `ref`, the rate that maps to u = 1
(default 25). Below `rate_off` (0.06), and at zero, it returns `Pulse.OFF`.
Zero means off, never slow.

`channels(u, flow_hue)` returns a Dictionary:
`off, u, period, dash, speed, hz, width, alpha, hue, color`. `color` already
carries `alpha`. Given `Pulse.OFF`, it returns `off: true` with zero width and
alpha. The formulas are BRIEF §6's, with two deviations the manager decided
(audit Q7 and Q8):

- **Hue** eases from dormant violet 272° to the flow's own hue along the
  shorter arc: `272 + arc·(1−(1−u)^3.2)`, from 06-three-flow-geometry. Undead
  turns −121° to green, living +106° to orange. A mid-rate route keeps its
  identity: undead sits at 163°, not blue, and living at 6°, not danger red.
- **Mark frequency** is floored at 0.80 Hz (speed ≥ 0.80 × period). BRIEF's raw
  formulas give 0.15–3.5 Hz. **Below u ≈ 0.35 a route moves faster than
  `14 + 140u`**: at u = 0 it runs 76.8 px/s, not 14. That is intended, so slow
  routes still drip countably. The 7 Hz ceiling never binds (top is 3.5 Hz).

A dead flow (the shadow gutter) uses the motion channels but ignores `color`.
Draw it with `Palette.c("dead")` and `matte_polyline`.

### Reduced motion

`Pulse.reduced_motion` is the one flag every scene reads. When it's on,
`phase()` returns a steady 0, `wave()` a steady 0.6 (above zero, so pulsed marks
stay visible) and `dash_offset()` 0. Anything else that moves (bobbing, rotating
rays) must check the flag itself. Reduced motion must still show who is winning
(BRIEF §8). Toggle it with **F8**, or boot with `-- --reduced-motion` (works
with `--shot`). The default is in `configs/pulse.json`.

## LineGlow

Fake bloom from stacked strokes (BRIEF §8): widths 10/6/3/1.5 and alphas
.10/.22/.65/1.0, scaled so the core stroke is exactly `width`. No shaders, no
SubViewports. Call these from inside a CanvasItem's `_draw()`.

```gdscript
LineGlow.polyline(self, pts, Palette.c("undead"), 2.0)                    # full glow
LineGlow.polyline(self, pts, Palette.c("undead"), 2.0, 0.5)               # half-strength halos
LineGlow.polyline(self, pts, col, 2.0, 1.0, Palette.c("undead_core"))     # pale core
LineGlow.arc(self, center, 24.0, -PI / 2, PI / 2, Palette.c("living"), 1.5)
LineGlow.ring(self, center, 30.0, Palette.c("relish"), 1.5, 0.8)
LineGlow.matte_polyline(self, pts, Palette.c("dead"), 3.0)                # dead: one flat stroke
LineGlow.matte_arc(self, center, 24.0, 0.0, PI, Palette.c("dead_lit"), 7.0)
LineGlow.matte_ring(self, center, 24.0, Palette.c("dead"), 2.0)
```

`glow` scales halo alpha: 0 draws the core alone, 1 the full stack. `core`
colours the innermost stroke; leave it out to use the line colour. Handing a
glow function `dead` or `dead_lit`, at any alpha, calls `push_error` and draws
matte instead. `LineGlow.is_dead(col)` asks the same question, and
`LineGlow.layers(...)` returns the stroke stack as `[[width, Color], ...]`.

A glowing stroke costs four draw calls and a matte one costs one. Nobody has
measured a frame budget for it yet. If you add many glowing lanes, measure
frame time at 1600×900 against the 8 ms budget.

## DriftFloor

The floor under town and dungeon (VISUAL-LANGUAGE law 1: "the ground is
near-black and alive"). It is a slow current of sparse, faint streaks running
along a direction field that your scene provides. The map has its own
flow-field ground (`scripts/map/`); DriftFloor is the cheap version of the same
idea for every other scene. The ground unit owns it; town and dungeon use it and
don't edit it.

```gdscript
var floor := DriftFloor.new()
world.add_child(floor)
world.move_child(floor, 0)          # under everything else in the world
floor.setup(
	Rect2(Vector2.ZERO, room_size),   # where streaks live, in the floor's local space
	func(p: Vector2) -> Vector2:      # drift at p; length = strength (0..1)
		return (exit_pos - p).normalized(),
	slab_pos,                         # the exhale's source (law 5)
	"town")                           # a Palette key; "" = the config's default
```

- **The field** is one of:
  - a `Callable(local_pos) -> Vector2`, baked once on a grid of `cell_px` cells
    (at most `max_cells` a side);
  - an `Image` (`FORMAT_RGF` or `RGH`, signed drift vectors covering the rect);
  - a `Vector2`, one drift everywhere.

  Length is strength. Streaks spawn more densely where the drift is strong, and
  where it is below `min_strength` (zero, say, inside a wall or building) there
  are none. Call `set_field()` again when your field changes (a door opens, a
  street is built). **Never call it every frame:** it re-bakes on the CPU.
- **The tempo.** The exhale is Pulse's beat. It surges streak speed and length,
  with the beat lagged by distance from `source`. The lag reaches
  `Pulse.wave_spread` at the rect's farthest corner, so the wave crosses the room
  and never blinks in unison. Town's source is the crypt slab. In a dungeon,
  Relish is the source: call `floor.set_source(relish.position)` each frame. It
  sets one uniform.
- **The colour** comes from a Palette key (`set_tint(key)`). The head is lifted,
  keeping its hue, until it clears `head_contrast` (3.4:1) against `ground`, so
  even a dim key like `contour` passes the 3:1 line floor. The floor stays faint
  by being **sparse and short**, never by being dim. Dead keys (`dead`,
  `dead_lit`) are refused with an error, because dead matter never emits light.
- **Reduced motion** follows `Pulse.reduced_motion`, polled each frame. When it
  is on, streaks freeze in place and the exhale stops. Each streak is a comet,
  a solid head with a tail fading behind it, so a still frame still shows which
  way the floor runs (law 13).
- **Input.** It is a Node2D with no Control in it, so it never swallows mouse
  input. A dungeon's circle drawing passes straight through.

| Key (`drift_floor`) | Default | Meaning |
|---|---|---|
| `tint` | `town` | default Palette key |
| `density` | 1.6 | streaks per 100×100 px of rect (`max_streaks` caps it) |
| `speed` | 16 | px/s at drift strength 1 |
| `length_px`, `width_px` | 30, 2.0 | streak size |
| `head_frac`, `head_power` | 0.22, 2.2 | solid head share; tail fade curve |
| `head_contrast` | 3.4 | the head's minimum contrast against `ground` |
| `life_s` | [4, 9] | streak lifetime range in seconds (they fade in and out) |
| `exhale_speed`, `exhale_length` | 0.8, 0.35 | the surge on the beat |
| `cell_px`, `max_cells` | 32, 128 | Callable bake grid |

**Cost.** Measured on 1600×900 at the defaults: 230 streaks, wall-clock frame
0.213–0.227 ms with the floor against 0.178 ms without (vsync off, no other
nodes). That is **+0.04 ms**, and the viewport GPU time is 0.014 ms. It uses one
GPUParticles2D with a custom process shader: no SubViewport, no trail buffer, and
no per-frame GDScript beyond two uniforms. Measured on an RX 6600 XT under GL
Compatibility. Streak cores (the brightest 15% of marked pixels) were 100% ≥ 3:1,
p85 3.76:1.

## Tests

`tests/run_tests.gd` discovers every `tests/test_*.gd` that defines
`run() -> int`, so adding a suite never touches the runner. A script error
inside a suite counts as a failure. Suites run before autoloads exist, so build
what you test directly:

```gdscript
var p = preload("res://autoload/pulse.gd").new()
p.configure(TestUtil.load_json("res://configs/pulse.json"))
p.clock_ms = 857.0            # pin the clock
# ... assertions ...
p.free()
Palette.configure(TestUtil.load_json("res://configs/palette.json"))
```

Scripts that a test loads can't name an autoload (`ConfigDb`, `Pulse`)
directly: the name doesn't resolve in `--script` mode. Reach the autoload with
`get_node_or_null("/root/ConfigDb")`, as `pulse.gd` does.
