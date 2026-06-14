# The Slab — design spec (Phase 2, prototype 1)

A throwaway test of **the raising screen**, the counterpart to the Raid & Raise
combat loop. It is **not** the whole economy — it isolates the one question that
decides whether the raise loop is worth building.

## The question

**Does assembling a form + remnants into a permanent feel like creating a
creature that is visibly *yours*?** Does the preview morphing — and the name
forming — as you slot make identity feel *emergent*, not just numbers going up?

Pass/fail signal: the **"name your friend?"** prompt. If you *want* to name the
thing, it worked.

Secondary question (folded in, design owner's call): **does the bone pit floor
feel good** — the fill-to-quality, pull-always-gives-something lottery that keeps
you off zero undead.

## The fiction

The crypt is where Relish woke. She was **revivified** — not undead herself, but
she only knows how to spend that gift on undeath. The central **slab** is where
she rose. **Vei**, the Raven Queen of the still and silent, watches from the
corner: she keeps the dead, Relish refuses to stay dead, so Vei is the nemesis.
The crypt's old bones fill the **bone pit** — the floor that means you can never
be truly empty.

## The loop (what's built)

1. **A form** (husk) is placed on the slab and draws as its **silhouette** (a real
   recognizable shape — crowned-skull lich, ogre hulk, ghost wraith…). Its anatomy
   blooms **rune slots** in a ring — muscle / nerve / presence / anima.
2. **Remnants** slot into matching runes (aspect-gated). The form gives no stats;
   every stat and echo comes from the remnants — a blank form is a **Hollow**
   shambler. The silhouette is a faint **ghost** when empty and **fleshes in**
   (alpha + aspect tint) as you slot.
3. **The creature morphs live** as you slot — Beef grows it, the dominant aspect
   tints it, Power spikes the rim, Speed trails wisps, Charm/Dread auras, Magic
   glows + orbits, Persistence after-images the actual shape, echoes pip overhead.
   (One stat = one watchable verb — the raid's rule.)
4. **Name + role form live.** Name = **Adjective Noun** (an echo names it; with no
   echo the top two stats *blend* — "Brutal-Fleet Skeleton" — not majority-wins).
   **Role line** = the verdict: "Stalker — good for picking off priority targets"
   (combat only for now; an echo flavors the use-case).
5. **Hold to Raise** → the silhouette fleshes fully under a closing ring → a
   TRANS_BACK overshoot → **"name your new friend?"** → it joins the **roster**.
6. **The roster** is a card box: silhouette portrait + name + role line, and a
   **feed-to-Maw** action on every creature.

## The Maw (universal sink)

One meter — **fullness 0..1 IS the quality dial**. You **toss anything in**:
- **Scraps, unused remnants, or whole minions** — each raises fullness by its
  **worth** (a scrap is a crumb; a juicy uncommon remnant or a whole minion is a
  feast), through **diminishing returns**. The TOSS drawer doubles as the
  **materials view** — it's where your spare remnants finally become visible.
- Feeding a minion is a **sacrifice** (a confirm: *"Vei takes the body"*). The
  Maw is where your dead go — thematic resonance with the Raven Queen watching.
- **Pull** → **always** yields a form + remnant. Quality rolls in a **hybrid
  window** `[floor_frac·fullness … fullness]`: `floor_frac` 1.0 = deterministic
  (you get your fill), 0.0 = pure ceiling-lottery (up to your fill, often less),
  **0.5 = the floor rises with the ceiling** (rush without the feel-bad). Tunable
  live. The pull **consumes a chunk**.
- Output is **hard-capped below looted gear** (rarity never exceeds uncommon) — a
  floor that keeps you off zero, never a substitute for raiding.
- Depletion is **on pull, not on the clock** (passive decay is a debug toggle).

## Faked / deferred (NOT built — protects the test)

- **The raid** is a button: "RAID COMPLETE — grant haul" drops a juicy, varied
  pile of forms + remnants + scraps (uses the real loot tables).
- **Deferred:** the Jar loadout / "what do I bring" selection (a separate
  question), town income stub, salvage economy, save persistence, the real Vei
  challenge fight, the raid round-trip. Vei's statue is a tappable placeholder
  ("You are not ready to challenge Vei.").

## Config map (everything tunable lives here)

- `configs/husks/*.json` — the forms (anatomy, base stats, color, noun). Copied
  from raid-and-raise; the two prototypes share no code, only this data shape.
- `configs/rarity.json`, `configs/echoes.json`, `configs/stats.json` — remnant
  rolls + visual coefficients (copied).
- `configs/names.json` — Adjective tables (echo + stat), "Hollow", and the
  `blend_threshold`/`blend_connector` for fusing the top two stats.
- `configs/roles.json` — the verdict: stat→{role, good_for} + echo→good_for.
- `configs/slab.json` — aspect colors, rune ring geometry, **silhouette** size /
  dim-alpha / beef-scale, and `raise_hold_time_s`.
- `configs/ossuary.json` — the Maw: fill rate, `floor_frac` (hybrid window),
  drop per pull, magnitude/rarity caps, echo chance, `worth` coefficients, decay.
- `assets/icons/*.svg` — game-icons.net silhouettes (husks + raven Vei + cauldron
  Maw), CC BY 3.0, bg-stripped + runtime-tinted. See `assets/CREDITS.md`.
