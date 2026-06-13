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

1. **A form** (husk) is placed on the slab. Its anatomy blooms **rune slots** in
   a ring — muscle / nerve / presence / anima, in the slot's aspect color.
2. **Remnants** slot into matching runes (aspect-gated). The form gives no stats;
   every stat and echo comes from the remnants — a blank form is a **Hollow**
   shambler.
3. **The creature morphs live** as you slot — Beef grows the body, the dominant
   aspect tints it, Power spikes the rim, Speed trails wisps, Wits sharpens the
   eyes, Charm/Dread auras, Magic glows + orbits, Persistence after-images, echoes
   pip above the head. (One stat = one watchable verb — the raid's rule.)
4. **The name forms live**, greyed above the slab: **Adjective Noun**. Noun = the
   form; Adjective = the strongest echo, else the dominant stat, else "Hollow".
5. **Raise** → a TRANS_BACK overshoot → **"Would you like to name your new
   friend?"** Your name replaces the ghost-name; the creature joins the shelf.

## The bone pit (ossuary)

One meter — **fullness 0..1 IS the quality dial**:
- **Feed** scraps → fullness rises with **diminishing returns** (cheap to
  mediocre, dear to full).
- **Pull** → **always** yields a form + remnant; quality scales with fullness;
  the pull **consumes a chunk** (skim the cream, then the dregs).
- Output is **hard-capped below looted gear** (rarity never exceeds uncommon,
  magnitude capped) — a floor that keeps you off zero, never a substitute for
  raiding. The gap between a pit-shambler and a looted specialist is the whole
  point.
- Depletion is **on pull, not on the clock** (passive decay is a debug toggle —
  in an idle game, bleeding investment while you're away feels bad).

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
- `configs/names.json` — the Adjective tables (echo + stat) and "Hollow".
- `configs/slab.json` — aspect colors, preview radius/tint, rune ring geometry.
- `configs/ossuary.json` — the pit: fill rate, drop per pull, quality band,
  magnitude/rarity caps, echo chance, decay toggle.
