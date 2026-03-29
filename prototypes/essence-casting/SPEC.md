# Essence Casting Prototype — Spec

## Hypothesis
Does gesture-casting with battlefield essence drops feel good as the core combat loop?

## The Prototype
Infinite horde combat. Enemies spawn in waves, your undead fight them, dead enemies drop colored essence orbs. Swipe between rune circles to cast spells — but runes are only active when matching essences exist on the field. Summoned undead join the fight immediately.

## Essence System
- 4 essence types matching the casting prototype's runes:
  - **Flesh** (body) — orange/red
  - **Breath** (vitality) — cyan/teal
  - **Veil** (soul) — purple/blue
  - **Chain** (elemental) — green/gold
- Enemies drop essences on death. Type depends on enemy type.
- Some enemies drop dual essences (e.g., human = Flesh + Veil). Using EITHER consumes the whole drop — like dual lands in Magic.
- Visible on battlefield as small colored orbs near where the enemy died
- Counter in corner shows available essences by type

## Rune Input
- 4 rune circles on screen (positions from casting prototype: top, bottom, left, right)
- All runes GREYED OUT by default
- When an essence of that type exists, the matching rune lights up in its color
- Player swipes between lit runes to form spell sequences (2-4 rune combos from Archetypes.ts)
- On release: consumed essences vacuum toward Relish, undead is summoned
- Cooldown after cast — all runes grey briefly, then re-light based on available essences
- Runes should be closer together than casting prototype (constrained to a smaller area, especially on large screens)

## Battlefield
- PixiJS renderer (from horde-scale prototype)
- Your undead (green/teal) vs enemies (red/orange)
- Simple flocking/movement
- Essence orbs float near kill locations, pulse gently
- Summoned undead appear near Relish (player position)

## Combat
- Infinite waves, constantly spawning (no breaks between waves)
- Escalating strength over time
- Your undead and enemies fight automatically
- Dead enemies drop 1-2 essences
- Dead undead are just gone
- No win/lose condition — it's infinite, just see how long you survive and how it FEELS

## Debug Controls (floating panel)
- Spawn rate
- Enemy strength
- Essence drop rate
- Cooldown duration
- Rune circle size/spacing
- +essences button

## NOT in this prototype
- Quest loop, jar, loot, collection
- Town or progression
- Boss encounters
- Any screen other than the battlefield
