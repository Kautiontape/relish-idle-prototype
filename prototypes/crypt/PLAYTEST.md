# The Crypt — playtest log

## Session 2026-06-15 (build: horde-management pass)

First session that felt like the prototype is testing the right thing. The
horde-management loop (grow a roster, read it, send the right bodies at the
right threat) is landing. The **organizing tools** are where it falls down — and
they fail for one shared reason, see the synthesis below.

### What worked — lean into these

- **Straight in: craft or mission.** No ramp, no tutorial. You either kit a
  champion or send a party. Low friction entry is a keeper.
- **The Maw stayed a backstop.** Used it only to fish for a specific relic, not
  as the main loop. That's the correct weight for it — it's the floor, not the
  game.
- **Numbers go up, legibly.** Watching the roster fill out and stronger
  creatures appear read as progress on its own.
- **Grab units, throw them in a ring, see what happens.** The party → raid
  beat is fun even with the fight faked.
- **Meters toward an end goal.** The Vei coverage strip / campaign progress gave
  a thing to climb toward.
- **Threat shown in advance → demands variety, not one optimal team.** This is a
  real win. Seeing the mission's counter-stat before you commit means you build a
  *toolbox*, not a single best squad. It defeats the "solve it once" trap.
- **Raising is intriguing.** The interesting decision is live: stack one
  monster's stats into a focused specialist, or spread for an all-rounder. That
  tension is exactly the intended hook, and it's there.

### What didn't — friction to fix

- **Filters are ineffectual.** Hard to find, unclear how to drive, barely faster
  than scroll-and-tap, and using them **hides the tags I made**.
- **Tagging is hard, and at the wrong granularity.** By the time a tag exists,
  it's not the right *size* for the team this mission needs, so you fall back to
  tapping units by hand anyway. The durable bucket doesn't match the dynamic,
  per-mission, jar-sized need.
- **Sorting feels pointless.** Power is a decent proxy for "strong" but
  inconsistent for "**appropriate** for this raid." Sort is blind to the threat.
- **Primary-stat badge isn't enough.** Showing the dominant stat is good, but
  useless when you're hunting a **secondary** stat (e.g. find the high-charm
  bodies). The badge hides the thing you're looking for.
- **"Lose your weakest, guaranteed" isn't satisfying as combat** — but it's
  accepted as a placeholder. It does usefully justify why Hollows exist (the
  ablative screen that dies for the champions), which reads well early. Real
  combat will replace it.
- **Vei needs a real fight.** Known, deferred. Deal with it when we deal with it.
- **RAISE ALL HOLLOWS is a needless big button.** Never raised Hollows directly —
  enough came off missions, and proper raising covered the rest. Demote or cut.
- **Can't read a unit's actual stats.** (Added after the session.) The token shows
  one badge (dominant stat) and the context bar shows party aggregate; tapping a
  unit just toggles it into the party. There's no way to see "beef 4 · charm 2 ·
  wits 1." Obnoxious, and a cheap fix — show the full stat line when exactly one
  unit is selected. Do this regardless of the mission work below.

### The synthesis (the one thing under most of the complaints)

Filters, sort, the badge, and tags all fail for the **same reason: they're
mission-blind.** At any given moment the player's real question is *"for THIS
raid, which bodies do I send?"* The game already knows the answer's ingredients —
the next threat is rolled and shown, it wants a specific counter-stat, the jar
has a fixed size — but none of the organizing tools point at it:

- sort is by power (threat-blind)
- filter is by role/tag (a static taxonomy, not "covers this threat")
- the badge shows the dominant stat (not the stat this raid rewards)
- tags are a taxonomy you build *ahead* of a need that's *dynamic*

So the player ends up **hand-rolling a query the game could answer for them.**
Re-pointing the existing tools at the pending mission is the fix — no new
systems, just aim the ones we have.

### Banked design answers (record, don't build yet)

- **Raid retrieval:** "you bring out what you brought in, minus losses." Felt
  like it tracks. Candidate rule for the real round-trip.
- **Hollows as ablative screen:** accepted as the early justification for a
  cheap-bodies tier. Keep.

### Proposed next steps (NOT yet built — for approval)

1. **Make the horde view mission-aware.** When a raid is pending (always), let
   the threat's counter-stat drive the tools: a "vs next raid" sort (counter-stat,
   power as tiebreak) as the default; the token badge shows the counter-stat
   value, highlighted when it helps; a "covers [threat]" filter chip.
2. **One-tap "best party."** A button that auto-selects the top-jar bodies for
   the pending threat. Answers "tagging is hard / I'd still tap by hand" by
   letting the game answer "who's best for this" on demand. Manual select stays.
3. **Badge follows your lens.** Show whichever stat you sorted/filtered by, so
   secondary-stat hunts are visible instead of hidden by the dominant stat.
4. **Cut/demote RAISE ALL HOLLOWS.** Unused; move to debug or remove.
5. **Re-examine tags.** "Coin a tag" was the intended pass-signal for organizing;
   this session it read as not-worth-it. Before cutting, try tags-as-saved-query
   (a tag = a saved filter/lens) and see if that earns its place. If not, drop it.

## Direction being explored — mission board (post-session discussion)

The threat-in-advance win suggests a bigger move: instead of one pending raid,
present **several missions to choose from**, each with a **reward hint** and a
difficulty read. The player errs toward the one they're suited for — or *stretches*
into a harder one because it drops the thing they lack ("my Bulwarks are weak, but
that mission drops a great Lich, so I'll eat some losses to go get it").

Read: this is **the same story, expanded**, not a new one. It sharpens the exact
axis that already worked, and the reward hint creates a **self-correcting loop** —
your weaknesses point you at the content that fixes them. It also feeds the Vei
coverage meter on purpose (take missions that close your failing fronts).

Refined question for this expansion: *"When you can choose which threat to face,
does trading 'I'm under-equipped here' against 'but it drops the thing I'm missing'
make a good decision?"*

Decisions banked from the discussion:

- **Quest-first flow.** Pick the mission, *then* muster the party. This inverts the
  earlier auto-select idea and makes it cleaner: the mission-aware sort/badge/filter
  and "best party" auto-fill all key off the *chosen* mission. It also resolves the
  worry that auto-fill trivializes selection — the real decision moved up a level
  (which mission), so auto-filling the party is fine.
- **Page gets a spine.** Mission board = home (the "what do I do" screen, cards show
  demand + danger + reward hint + a readiness glance). Tap a mission → muster view
  (horde scoped to it). Build/Maw unchanged. **Vei becomes the capstone card** on the
  board, not a peer tab.
- **Scope: build the board + choice + muster first (rewards hinted, haul faked and
  biased toward the hint). DEFER escalating quest chains / unlock ladders / progress
  persistence** until the single choice proves fun — that's where a prototype turns
  into "a small game." Test the atom before the ladder.

## Combat model — decisions to honor when real combat lands

These are recorded now so the faked sim doesn't quietly bake in assumptions the
real fight should overturn.

- **Perks must matter.** `echoes.json` already defines combat perks (life_drain =
  life steal, frenzy, heavy_blow, volatile, vengeful), but the faked combat had
  been *ignoring all of them* — coverage was one counter-stat, losses were the
  weakest, echoes touched nothing. Real combat must read perks; the faked sim now
  reads survivability perks (life steal foremost) as a down payment on that.
- **Losses are NOT just the weakest.** The strong can get out of position and die;
  it's just less likely. Survival is probabilistic and scales with the numbers:
  more HP (beef), persistence, wits, speed → lower death chance, plus life steal.
  But never zero (a champion can fall) and never one (a Hollow can scrape through).
  Implemented: coverage sets party-wide danger, danger is redistributed per-unit by
  survivability, then clamped to [floor, cap] so the tails stay open. Tunable in
  `raid.json → survival`.
- Offensive perks (heavy_blow, volatile, vengeful) are defined but don't touch the
  faked loss-only model yet — they need the real fight to mean anything. Flagged in
  `combat_sim.gd`.

## Built this round (mission board + muster + combat rework)

- **Mission board is the home screen.** 3 missions, each a threat + difficulty
  (Scouting/Raid/Siege → loss & reward multipliers) + a hinted reward focus. Vei is
  a capstone card, not a tab. Tabs are now Missions / Horde / Build / Maw.
- **Quest-first muster.** Choosing a mission drops you into the Horde tab scoped to
  it: a muster banner, mission-aware sort (default), gold counter-stat badge on every
  token, AUTO-FILL (best party for the counter-stat), then SEND.
- **Reward-directed haul.** The faked haul scales with difficulty and skews toward
  the hinted spoils (a husk, an aspect's remnants, or a rarity floor) — the
  "stretch for the thing that fixes my gap" loop.
- **Per-unit stat readout.** Select one unit → the context bar shows its full stat
  line + echoes (the PS fix).
- **Cut RAISE ALL HOLLOWS** from Build (kept as a debug button).
- Verified: smoke suite green, headless boot clean, web export OK, and the
  board → muster → auto-fill → send flow confirmed in-browser.

## Still open / not done this round

- Tags re-examination (tags-as-saved-query) — deferred.
- Escalating quest chains / persistence — deferred by design (test the atom first).
- Real Vei combat — still the front-coverage check.
- `DESIGN.md` / `CLAUDE.md` are still the **Slab's** docs (crypt was forked from it);
  they now describe neither the horde game nor these systems. Worth a rewrite.
