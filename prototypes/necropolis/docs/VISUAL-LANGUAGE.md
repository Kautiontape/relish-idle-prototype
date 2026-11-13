# Necropolis: visual language

One language for every scene: the realm map, Covington, the dungeons and Vei's final test. Each
scene plays differently (macro, economic, micro), but they all look like the same game.

> "mostly black/grey background, lots of lines to represent things, but the lines are almost hot
> synthwave style with colors that flow along them so it feels constantly alive"

> "I want it to feel like I'm straight playing an abstract conceptual performance piece. I mean, it
> still needs to make sense"

> "I need this all go share the same visual language. howeever, it will have different feelings of
> mechanics. macro, economic, micro." (Shawn, 2026-11-13)

Implementation toolkit: `docs/VISUAL-TOOLKIT.md` covers the `Palette`, `Pulse` and `LineGlow` APIs.
Scene scripts never hardcode a `Color(...)`, a tempo or a glow stack.

Precedence when sources disagree: Shawn's vision (run `vision.md`) > settled Realm BRIEF decisions >
this file's older Necropolis notes.

---

## 1. The laws

1. **The ground is near-black and alive.** It is `ground #05060A`, and it always moves, because it
   carries information: which way matter is drifting, where the front is, what is settled. It is
   never wallpaper. On the map the ground is the flow field. In town it is the street grid's slow
   current. In a dungeon it is the room floor's faint drift toward the exits.
2. **Everything is a line.** Units, buildings, rooms, routes and panel frames are strokes, not
   fills. Fills are allowed only for tiny cores (a node's centre, a unit's head) and for dead matter's
   matte surfaces.
3. **Light flows along lines at the rate it stands for.** A route carrying 3/s visibly flows faster
   than one carrying 1/s. **A zero rate switches the line off** (dark, or a faint phantom bank). It
   never just slows down.
4. **One `u` drives five channels.** A rate normalises logarithmically to `u` ∈ [0, 1], which
   drives dash period `96 − 52u`, speed `14 + 140u` px/s (floored at 0.8 × period, so marks always
   pass at ≥ 0.8 Hz), width `1.1 + 2.6u`, alpha `0.4 + 0.6u`, and hue. Hue eases from dormant violet
   (272°) at u=0 to the flow's own hue at u=1, so green and orange keep their identity. Use
   `Pulse.channels(u, flow_hue)`.
5. **One tempo for the whole game: T = 1714 ms**, deliberately out of step with the sim's 0.5 s
   substep and with whole seconds. Everything that pulses shares it, phase-offset by graph distance from the scene's source,
   so the pulse reads as a wave crossing the scene, never a blink in unison:
   - **map:** Covington is the source;
   - **town:** the crypt slab is the heart;
   - **dungeon:** Relish is the source.
6. **Matter has fixed colours** (keys in `configs/palette.json`):

   | matter | key | colour | glows? |
   |---|---|---|---|
   | undead | `undead` (core `undead_core`) | `#39FF9E` (`#C9FFE8`) | yes |
   | living | `living` | `#FF6A2B` | yes |
   | dead | `dead` | `#6E6A7E` | **never** |
   | dead under Relish's light | `dead_lit` | dead lifted and tinted violet | **never emits**, it is lit |
   | Relish | `relish` | `#C04CFF` | yes |
   | Vei | `vei` | `#FFF3D0` | yes |
   | towns and allies | `town` | `#3E5C8F` | faintly |
   | danger | `danger` | `#FF2D55` | yes, sparingly |
   | ground / graticule / contour | `ground` / `graticule` / `contour` | `#05060A` / `#12182A` / `#1E2A45` | no |

7. **Dead matter never emits light.** The dead are matte, inert and unlit. **Relish's violet falls
   on the dead near her, or on the pile she's targeting** (`dead_lit`). She is the only one who can
   raise them, so she is the only light they ever catch. Corpses that ship to Vei ride the undead
   lane as the **shadow gutter**: a matte black groove cut into the green lane. It widens as the
   garrison wins.
8. **Glow is stacked strokes.** Widths 10/6/3/1.5 at alphas .10/.22/.65/1.0 (`LineGlow`). No
   blur, no full-screen post-processing per frame, no bloom pass.
9. **Count, don't brighten.** Anything the player ranks shows as a countable integer or as tally
   pips, never as brightness or thickness: the biggest corpse pile, the strongest fortress, the
   fastest route. A luminous display carries identity, binary state and small integers well, and it
   can't rank a continuum (Realm finding, oscilloscope).
10. **Streams over stocks.** The HUD's first number for any resource is its **net rate**
    (`+4.2/s`), then the in/out split. Stocks appear only when they're spent (costs) or counted
    (piles, pips). The player should "worry about the streaming quantities of undead coming in versus
    being removed".
11. **Type has a law.**
    - **Rates** are oblique (9°), light, always signed, always `/s`.
    - **Masses and counts** are upright, heavy and unsigned.
    - Text is never below 12 px.
12. **Colour is never the only signal.** Each identity carries a second channel:
    - undead flows go out from Covington and living flows come back from Vei (direction of travel);
    - the dead gutter is darker than its lane, and lanes are lighter than the ground (luminance sign);
    - green lanes run long dashes, orange short, and the gutter has none (dash rhythm).

    Check every scene in greyscale.
13. **Reduced motion keeps the story.** Flag: `Pulse.reduced_motion`. With motion off, dash offsets
    and pulses freeze, static chevrons show direction, and the ground shows a still reading of the
    same field. A player must still be able to tell who is winning.
14. **Floors:**
    - 8 ms frame budget at 1600×900, measured as CPU and GPU render time with vsync off;
    - contrast 4.5:1 for text, 3:1 for lines and bars, against `ground`;
    - click targets at least 44 px.

## 2. Same language, three feels

| scale | scene | the feel | what the lines are |
|---|---|---|---|
| **macro** | the realm map | slow, tidal, wide. You watch currents and commit flows. | routes carrying rates; the flow-field ground; fortress rings with countable pips |
| **economic** | Covington | busy, rhythmic, mechanical, like a factory's heartbeat. You watch a machine you built run itself. | streets as routes carrying worker streams; buildings as neon line silhouettes; agents as short walking strokes |
| **micro** | dungeons, and Vei's final test | tight, tactile, immediate. Your hand draws the circle. | wall lines, unit glyphs, Relish's violet trance circle, essence motes |

### 2a. Macro: the realm map
- **Ground.** The Synthwave Flow Field: thousands of thin advected streaks driven by the influence
  field.
  - They drift toward Vei wherever matter is being lost.
  - They go turbulent along the contested front.
  - They go still on settled ground.
  - The 1714 ms exhale crosses the realm from Covington.
  - Territory reads from streak hue *and* streak motion; motion carries it under the colour-blind
    check.
- **Routes.**
  - Bow left of their own direction of travel (17% of chord).
  - Five channels from `u`.
  - Undead lanes carry the shadow gutter for corpses shipping to Vei.
  - The direct Covington→Vei FLOOD lane is a separate, straighter, hotter line.
  - Committed flows are visibly wider; they are the player's own commitment.
- **Fortresses.** Concentric rings:
  - capacity as a hairline outer ring;
  - living, undead and dead as arcs;
  - pips for counts (one pip per 10% of capacity, or per N bodies);
  - tier as notches;
  - a cleared or flipped fortress turns green-lined and joins the stream.
- **Covington.** The bright source node.
  - Its pulse rings are the tempo's origin.
  - A small three-way **valve glyph** shows the WORK / WAR / FLOOD split as three lines leaving it,
    each as wide as its share.
- **Vei's domain.** A large cream structure at the top.
  - Concentric digestion rings rotate at her capacity.
  - The backlog is a countable stack of rings at her gates.
  - The odds show as a **number**, with the sustained differential's sign (▲/▼) and the drain time
    beside it.
- **Relish.** A violet token with a stacked-stroke halo.
  - When she moves, she leaves a fading violet wake along her path.
  - Where she stands, the dead within her light radius catch `dead_lit`, and the routes she bends
    visibly lean toward her.

### 2b. Economic: Covington
- **The town is a circuit you can read.**
  - Streets are routes, and every street carries the stream of agents moving along it.
  - Buildings are neon line silhouettes of a medieval fantasy town: crypt, forge, market, inn, vat
    chapel, ossuary tower, walls, guildhall and more, drawn in outline.
  - A building **lights up as it's staffed**. Its glow strokes scale with its throughput rate, and
    its output shows as a countable pip row.
  - An unbuilt lot is a dim dashed outline (a blueprint). A building under construction draws itself
    stroke by stroke.
- **Agents.**
  - Undead are short green strokes that walk with a stiff, metronomic gait.
  - The living are warm orange strokes that wander.
  - **Interactions are visible:** a brief arc between a living agent and an undead one at a stall
    (trade), a cart line between buildings (hauling), a spark at the forge.
  - Relish in town is the violet token, and the buildings near her brighten.
- **The crypt slab** is the town's heart, and the town's tempo source. When Relish works it to raise
  big undead, the slab's rings pulse on the tempo, and the bone-pit's matte dead catch her violet.
- **Policies** show in the world, not only in a panel. When a rule fires, the affected agents'
  strokes flash once on the next beat and turn toward their new task.

### 2c. Micro: dungeons and Vei
- **Rooms.**
  - Walls are flowing synthwave lines. The current rainbow-drift wall shader is retuned to the
    palette and the tempo: hue cycles only between violet and the fortress's controller colour.
  - Doors are gaps with a glow lip.
  - The boss room's walls run hotter.
- **Units.**
  - Living garrison are orange line glyphs. Your undead are green.
  - **Big undead** (from the crypt slab) are larger multi-stroke glyphs with a slow pulse.
  - Unit quality is shown by **stroke count** (tiers = 1/2/3 nested outlines), never by brightness.
- **Relish's trance.**
  - The screen's motion slows.
  - Lines dim to 40%, except Relish and the essence.
  - Her trace is a hot violet stroke.
  - Scoring feedback is the circle redrawn as a perfect ring with its score as an integer.
- **Essence** is a small violet-white mote. It drifts to Relish and gathers into countable clusters.
  Corpses are matte until her light reaches them, and then they stir.
- **The end-of-dungeon warden** is a large multi-ring glyph. Its attacks are telegraphed as
  expanding danger rings on the tempo, so the player can learn their rhythm.
- **Vei's final test** is the same language at its largest.
  - The backlog pours in as the horde stream, and the streams you built become the army.
  - Vei is cream and gold rings.
  - Her attacks land on the tempo.
  - Each backup Relish spends is a visible cracked violet ring that doesn't come back.

### 2d. Zoom levels on the map (vision: "see how my units flow")
- **Far** (zoom < 0.6): lanes are rate lines and the ground is the current.
- **Mid** (0.6–1.6): lanes gain chevrons. Fort pips become readable. Lane callouts appear (*why* a
  rate changed: "WAR → Ashgate −1.2/s · Relish left").
- **Near** (> 1.6): lanes resolve into **individual marching glyphs**, the same unit glyphs as town
  and dungeon, spaced by rate. Convoys show as carts. Relish's wake is visible.

The three scales should feel like one world you can zoom into.

### 2e. Set pieces (the performance piece's named moments)
Each gets a deliberate, short treatment on the tempo:
- **the dive** into a scene;
- **a valve swing:** the three lines from Covington visibly re-proportion;
- **the first flip:** the fortress ring re-inks from orange to green, stroke by stroke;
- **a tithe wave:** an orange tide line sweeps from Vei toward the target;
- **a tier-up:** the walls draw themselves around Covington;
- **a big undead raised:** the slab's rings collapse into the creature's outline;
- **a backup cracking** in a fight;
- **Vei's first weave;**
- **victory:** every lane in the realm runs green toward Vei and stops.

### 2f. Sound (minimal; synthesised, no asset pipeline needed)
`AudioStreamGenerator` blips are fine:
- a low pulse on the tempo (scene-wide, quiet);
- the essence absorb ("fwwwwooomp": a falling sweep);
- the raise grow-out ("rrawwwwr": a rising, gritty sweep);
- the ring-fit chime, with pitch by score;
- a valve whoosh;
- a tithe-warning horn;
- a backup-crack shatter.

Respect a master mute and a volume setting.

## 3. Moving between scenes
"Click to bounce into the main town" is one click on Covington, then a short **dive**:
- the camera zooms into the node;
- the routes carry on as the town's streets;
- the town fades up around them.

The return is the reverse. Dungeons dive through the fortress ring into the first room. The dive is
under 600 ms. With reduced motion it becomes a 150 ms crossfade. The router in `scripts/main.gd`
(owned by the map unit after E1) keeps the old scene alive under a `Transition` node for the dive,
then frees it. It resets `Engine.time_scale` on every swap.

## 4. Per-scene acceptance checklist
- [ ] No hardcoded colours, tempos or glow stacks (`Palette`, `Pulse`, `LineGlow` only).
- [ ] The ground or floor moves, and the movement means something.
- [ ] Zero-rate lines are off.
- [ ] Rankable things are counts.
- [ ] Rates are signed and oblique; masses are upright.
- [ ] Dead is matte everywhere, and `dead_lit` appears only under Relish's light.
- [ ] The greyscale screenshot is still readable.
- [ ] The reduced-motion screenshot still shows who is winning.
- [ ] Frame time is ≤ 8 ms at 1600×900 in the scene's busiest state (numbers in the unit report).
- [ ] Text contrast is ≥ 4.5:1, lines ≥ 3:1, no text under 12 px, targets ≥ 44 px.
