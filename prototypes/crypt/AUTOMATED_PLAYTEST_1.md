# Automated Playtest #1 — The Crypt

*Played blind (no docs read) via Playwright, ~full loop plus debug exploration. Notes are an experiential player report: what I figured out, what felt good, what felt off, and how it would plug into a larger idle RPG.*

---

## What I figured out the game *is*

I run a crypt full of the dead. Most undead start **Hollow** — blank bodies, no stats, power 2. The game is about turning blanks into champions and throwing them at the dead-keeper, Vei.

The loop I reverse-engineered:

- **The Maw** is the forge/gacha. "Fullness is the quality dial." Shred spare bodies → scraps, feed scraps to fatten the Maw, then **Pull** for a husk + a remnant. The fuller the Maw, the better the pull (pulling at low fullness gave a sad common).
- **Build ("Kit a champion")** is the heart: pick a form (Skeleton/Wraith/Zombie/Revenant), slot **remnants** into typed slots (Muscle, Nerve…). Each remnant carries a stat + rarity + keywords. The creature's **name, archetype, color, and power all emerge from the parts.**
- **Missions** demand a stat (beef/wits/dread/charm). Muster up to 2 and send. "Coverage — composition, not luck."
- **Vei** is the win: cover all her fronts at once. Lose, and the whole horde is unmade.

### Mechanics confirmed via the `dbg` menu

The debug panel exposed the underlying math:

- **`raid coverage / pt: 0.02`** — each point of the relevant stat = 2% coverage. (My champion's beef 7 → exactly 14% coverage. ~50 needed for full.)
- **`champion power threshold: 14.0`** — power ≥14 = "Champion" tier (Hollows are power 2).
- **`Vei fronts required: 3.0`** — Vei needs her stat fronts covered.
- Other knobs: Grant a big haul (x3 raids), Reset the crypt, +4 test champions, Raise all spare forms as Hollows, Re-roll mission board, reveal Vei thresholds.

### Vei's win condition (from the challenge screen)

Four fronts, each with flavor + a legible check:

| Front | Flavor | Check |
|---|---|---|
| Giants that shrug off blows | bring something that fells the big | **wits / need 14** |
| Numberless host | bring something that scatters or pulls a crowd | **dread / need 12** |
| Carvers cut deep and fast | bring a wall to soak them | **beef / need 18** |
| She is mighty | bring force enough to end her | **power / need 40** |

"Lose, and the whole horde is unmade." All-or-nothing; cover every front simultaneously.

---

## What felt genuinely good

1. **The build moment is the star.** Watching `Hollow Skeleton · power 2` snap into `Tireless Skeleton · Bulwark · power 16` the instant I slotted a rare Beef remnant was the best beat in the session. Name from the keyword, archetype from the dominant stat, a color to match — a collectible, expressive, mad-scientist hook. This is the thing worth building a game around.
2. **"Fullness is the quality dial"** is an elegant, legible gacha twist — I control my own luck by how much I invest before pulling. Banking fullness vs. pulling now is intuitive instantly.
3. **"Composition, not luck"** is the right backbone for an idle/management game — effort beats save-scumming.
4. **The Vei screen is excellent.** Per-front `your X / need Y / OK/✗` is crystal clear about what to go build. It gives the whole game direction.

---

## What felt off (and the big one bit me hard)

1. **Mission legibility gap — #1 problem.** I did everything the game pointed me toward — fed the Maw, pulled, built a champion — then sent it on the **lowest-danger** mission whose card said **"Best party beef: 7"** in confident gold. The champion **died** for **14% coverage**. Only the debug menu revealed coverage is `0.02/pt`, so beef 7 = 14% and I'd need ~50 to clear it. The card *implied* "you've got beef ✓" while I was failing catastrophically. Missions need the Vei screen's "need X" honesty.
2. **First real raid punished engagement.** A full Maw→Build investment, spent on the safest-looking mission, returned a dead champion and a modest haul. For a new player that's a "did I do this wrong?" gut-punch that nearly killed my appetite to build at all. The intro's cost/reward is inverted.
3. **I send blind.** Want projected coverage % for the mustered party *before* SEND, plus "will they die at this coverage?" "Composition not luck" only pays off if I can read the composition's outcome in advance.
4. **Vocabulary is dense.** Header says WT/DR/BF/PW; slots are MU/NE; champions show MG/CH/BF; archetypes are Hex/Charmer/Brawler/Bulwark. Had to deduce MU=Muscle=Beef; still can't confidently map MG (magic?) to the wits/dread/charm missions ask for. Slot abbreviations differing from stat abbreviations is the core confusion.
5. **Party size felt wasted.** "Jar 2," I brought 1, nothing warned me I was leaving coverage on the table.
6. **Truncated hint.** The text telling a new player where remnants come from ("Raid or PULL the Maw fo…") is cut off — exactly the info needed.

---

## Things I *wanted* to do but couldn't

The most telling cluster:

- **Find a wits or charm remnant.** I only ever saw Muscle (Beef/Power) remnants and Nerve slots I couldn't fill. Yet missions and Vei demand wits/dread/charm. Soft wall: the game asks for stats it never showed me a source for.
- **Fill a Nerve slot / build anything but a Bulwark.**
- **See what keywords do.** Life Drain, Tireless 6, Frenzy, Crafty flavor the name but never visibly *acted*. Big latent depth, currently inert to the player.
- **Win a raid.** My only raid was a loss, so I never felt the positive payoff the loop is built around.

---

## How it would plug into a larger idle RPG

This is clearly the **roster-crafting + dispatch core**. The Maw + Build is a fantastic *active* layer (the part you fiddle with and screenshot); missions are the *idle* sink. In a full idle game I'd expect raids to run on **background timers** — dispatch a party, return for the haul — with Build/Maw as the between-dispatch tinkering. Raids currently resolve instantly (fine for a prototype, but the loop is begging for the idle-timer dimension). Vei works beautifully as a **"boss wall that tells you what to farm"** — a natural chapter/prestige boundary.

---

## Bottom line

If the question is *"does assembling a creature from parts into an emergent identity feel good enough to be a core loop?"* — **yes, strongly.** The build is the soul. The scaffold around it (Maw quality-dial, composition-not-luck, Vei gate) is solid. But I'd fix the **mission legibility + first-loss feel-bad first**, because it quietly betrays the very "composition, not luck" promise that makes the rest trustworthy. I was sold by the builder, then confused by the part meant to reward it.

---

## Suggested fixes, ranked

1. Put "need X" on mission cards (mirror the Vei screen). Kill the false-positive gold "Best party beef: 7".
2. Show projected coverage % and casualty risk in the muster panel before SEND.
3. Soften or signpost the first loss — telegraph that a single mid-tier champion won't clear a mission alone.
4. Surface a source for wits/dread/charm remnants early (or explain the gating).
5. Make keywords legibly *do* something in the raid report.
6. Unify stat vs. slot vocabulary; fix truncated hint strings.
7. Nudge filling the full "jar" (party slots) for more coverage.
