# Necropolis — design notes

## What this tests

Does the whole Relish concept-stack cohere as ONE game: strategic necrosis map
+ circle-raid combat + town factory + hidden-number idle escalation against a
single recycling enemy?

## The model (canonical + extensions)

The map sim is a straight port of the canonical REALM simulation
(relish-realms `lib/realm-sim.js`, spec §3 of its BRIEF), scaled ×1/100 so
fortress numbers read as headcounts. Three states of matter — LIVING, DEAD,
UNDEAD — and the whole game is which state the realm's population is in.

**The critical asymmetry (load-bearing, proven in the source prototypes):**
undead killing living leaves corpses AT the fortress (Relish's material);
living destroying undead ships those corpses TO VEI, who converts them back
into soldiers. Losing an attrition trade arms her.

Vei converts arrivals at fixed capacity `R_vei`; a corpse costs 1 capacity, an
undead costs `q` (quality). **Quality is the gate**: it divides how fast
garrisons kill your undead and multiplies what they cost Vei to digest —
"make the undead indigestible" is the Covington upgrade track. Her digestion
is `cheap`-policy (corpses first) so the you-are-arming-her loop is visible
in-session. When inflow exceeds her capacity a backlog masses at her gates:
that backlog is the win meter and sets confrontation odds
`odds = massed / (massed + K)`.

Extensions over canon (documented deviations):
- **EMPTY**: fortress space = cap − living − undead − dead. Vei only ships
  into space. Garrisons also *clear* corpses (`k_clear`) — dead can leave the
  board; denying Relish material is a defensive act.
- **Vei pool cap**: she stops converting while her fielded-army pool is full —
  keeping her fortresses topped up stalls her digestion (fixes the canonical
  dead-end-reservoir flaw and makes "let her forts stay full" a real strategy).
- **Simulacra**: limited-charge auto-raise channels planted at fortresses.
  They produce chaff that streams at Vei. Automation = chaff volume; the
  player's own circles = quality. That split is the game's thesis.
- **Raids are played, not channelled**: teleport opens the raid scene; kills
  and raises write back as mass. `P_relish` (minting while home) is tiny per
  the canonical finding that a big value deletes the entire decision space.

## Pacing (validated by tests/test_pacing.gd)

- Idle 1 h → odds ≈ 0. The factory does not build itself.
- Active-play model (slab every ~24 min, forge levels, raid every 2.5 min,
  simulacra maintained): crosses 60% odds at **~2.1 sim-hours**, 96% by 4 h,
  late differential ≈ +25/s. Numbers are meant for a few-hours arc; the ×60
  debug speed exists to compress testing.

## Canon

- GREEN #39FF9E undead · ORANGE #FF6A2B living · GREY #6E6A7E dead (matte,
  never glows) · BLUE #3E5C8F towns · Relish #C04CFF · Vei #FFF3D0 ·
  danger #FF2D55 · ground #05060A.
- Flow lines render RATE, not convoys; zero-rate routes switch OFF; corpse
  shipments ride the undead lane as a matte gutter.
- Global undead totals are hidden everywhere except Vei's panel.
- Circle scoring is the raid-and-raise Kåsa scorer verbatim: score < 60 chaff,
  60–89 soldier, ≥ 90 elite. Big sloppy circle = many weak; small perfect
  circle = few strong.

## Deliberate cuts

Web export (repo deploy infra is web-only; this runs native), Luna Pine (cut
in canon), remnant/echo depth from slab/crypt (represented as the
soldier/elite tiers + forge quality), authored raid chambers (procedural
rooms seeded per-fortress instead).
