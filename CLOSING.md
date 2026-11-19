# CLOSING

Phase I of the realm run (2026-11-17 to 2026-11-19) made Necropolis teach itself and play as one game, from a new game to a won one. This file says what merged, how it was gated, which balance misses were accepted, what's open, what to play first and what waits on Shawn. P8's close and the earlier Phase II note follow at the end. `RUN/` is the run folder, `~/documents/apps/kautiontape/runs/relish-realm-2026-11-13/`.

## What Phase I merged
Every Phase I unit and round, in merge order, from `git log --merges --first-parent realm/integration` after cac5a17 (Phase I's base: economy's E4 close-out). The first sha is the merge on realm/integration; the second is the branch tip it took. Each unit's report is `RUN/reports/<unit>.md` and each review is `RUN/reports/review-*.md`.

| integration | unit and round | tip |
|---|---|---|
| 5043eb3 | town-i milestone 1: why and how per building, a first goal, essence and cost lines | cfca0dc |
| 5298768 | economy P1: Vei's break pressure scales with her living pool | 8b1e808 |
| cc4aa19 | economy P2: the queue rule (a gated entry holds no slot; the list caps at 16) | 5932db6 |
| 4de9f8e | town-i milestones 1 and 2: real queue commands, gated rows, ETAs, the staffing projection, husk craft | 6cae2a1 |
| c11a48b | map-i milestone 1: only held forts look owned, state chips, who comes in, raid and retreat lines | 2e527b2 |
| 1dd80fa | dungeon-i milestone 1: the control legend, trance and essence cues, the goal block, the clear card, the retreat panel | c39ccf5 |
| 4012f35 | town-i clarity round 2: store notes, why-lines, jargon tooltips | dd9e8e0 |
| a8aa4aa | map-i clarity round 2: the goal and valve line, the held-chip layout, the legend | b62470f |
| dfe4bc2 | dungeon-i clarity round 2: COUNTER points to the Crypt slab, retreat and death costs side by side | 10879f8 |
| b0ea3ea | town-i clarity round 3: the goal on the first screen, Crypt tips, every Queue click sent | 80c0461 |
| c86da47 | map-i clarity round 3: the word rule and goal line, the legend open by default, no sliced labels | b9af06b |
| a0bfb08 | dungeon-i clarity round 3: a death ends the raid, not the game; sleep-gap handling; the assist off by default | 87095ad |
| e23818e | dungeon-i clarity-3 raid fixes: LAST CHANCE banner, the death card's "not the game" line | 2e61ae2 |
| 0361adf | map-i milestone 2: the catch-up screen, front rows, the Chapel of Vats backups hint, victory once per game | cbae7a7 |
| bf0a9b1 | dungeon-i milestone 2: the readable Vei loss, every raid and Vei word in raid.json | f10fa9f |
| be0485f | map-i V-I1 round: a plain who-comes-in line, the bar's hover lines, a cracked mark for retaken forts | 3a661f1 |
| a4c5a78 | town-i V-I1 round: the goal plate at every tier, the workers muster note | 4247398 |
| 468b528 | dungeon-i V-I1 round: circle quality shown, the tier-1 COUNTER rule, plainer death and Vei loss lines | 7ac8980 |
| d5fb916 | economy P3: the Grow stance, the bone cost ramp, the relic trickle, the odds refit | 355393f |
| b7d2caa | the manager's fix on integration: the valve payoff reads `GameState.first_odds_of` (not a merge) | (none) |
| 656a775 | dungeon-i P7: a won game ends (END, the epilogue, the town's won plate, the win card's 30 s press) | 88d97cf |
| ac1502f | economy P3b: the won state (#21), `cmd_boss_won` (#22), shown odds capped at 95%, the raid credit | 7c30d1a |
| a52bca6 | dungeon-i #22 round: Vei's win recorded as she breaks, the valve payoff reads the raid credit | cc86383 |
| aeee342 | economy P9: the P3b review's should-fixes, ruling 35, the catch-up and frame benches | 29c9c5a |
| 92f297c | dungeon-i won-polish round: the won away panel, the won valve, ODDS "with your raids" | c491b56 |
| bd56f1f | dungeon-i Session 5: BONE's warning keeps its room and holds 10 s | 03f4bf1 |
| 6b1348c | economy P9b: ruling 36 (forts keep and refill their garrisons once won), ruling 37's 12 s catch-up budget | b4dd4e1 |
| 82fc4b5 | dungeon-i Session 6: both reviews' should-fixes | 582ccb4 |
| 735a168 | economy balance pass: B1 (no raid credit for a raid that did nothing), B2, the 15-profile batch | 031f42b |
| 2ff25a7 | dungeon-i Session 7: a lost Vei attempt says what fell short; CLOSING.md opens with P8 | f7db397 |
| 6694dea | economy close-out: V-I2's measurements, B3, B4 (the honest mill income on every read) | d7ced11 |
| 2e786ed | dungeon-i's tip change: the guards tip names the fronts still standing; P8's ruling | 0550819 |
| (merging) | dungeon-i V-I3 round: the won forts read "not taken", BONE's line silent at FULL and once won, the queue says why each build waits, the away report names a village gone neutral | 84dd639 |

This branch's closing commits go on top: 116a56c (the V-I3 review's two should-fixes), ad57ee0 (the won retreat lines and the won strip), and this file with PROTOTYPES.md and DESIGN.md.

## The gate
- **V-I3 signed off** (`RUN/reports/vision-i3.md`): 36 met, 14 partial and 1 miss over 51 rows. Its re-check after the V-I3 round (`RUN/reports/vision-i3-recheck.md`) found the top three fixed and checklist #8 answered, with nothing blocking Phase I's close.
- **The suite at the final sha:** (filled at the gate, after realm/integration merges in)
- **The slow suites** were green at 2e786ed (`RUN/reports/slow-suites-2e786ed.md`): catchup_bench 402/0, catchup_accuracy 16/0, margin_truth 34/0, autoplay_away_risk 12/0, autoplay_away_risk_real 22/0 and boot_week 15/0, each rc 0 with no script error.
- **The five deterministic bots** (the four wardens and Vei) are byte-identical to c5d3902 at this gate, as at dungeon-i's earlier gates.
- **The code reviews:** Phase I's milestones and rounds were each reviewed before they merged (`RUN/reports/review-map-i-*.md`, `review-town-i-*.md`, `review-dungeon-i-*.md`, `review-economy-p*.md`, `review-economy-balance.md`, `review-batch-*.md`, `review-v-i2.md`). The last, of the V-I3 round (`review-dungeon-i-v-i3-round.md`), found no must-fix and two should-fixes. Both are fixed in 116a56c: the legend's and the valve's won wiring are now behaviour tests, and the queue's reason codes are read off the walk itself, so a new gate code fails until it has words.

## Balance misses, accepted
Sources: `RUN/reports/economy/phase-i-balance.md` §5, §13 and §14, and `RUN/reports/review-v-i2.md`. Each was ruled by the manager (reversible) and is recorded in `prototypes/necropolis/docs/BALANCE.md` §5.
- **Next affordable, S1 and S2 (ruling B3).** The bands (S1 1–3 h, S2 4–10 h) were missed as written: 408 of 487 build starts fall in a catch-up, so the gaps sit inside the aways, not the sessions. B3 re-worded the target, which now reads met. An active session still rarely starts a queued build (15% of live minutes): the builds are bone-priced and a 20-minute session earns about 370 bone.
- **ablation_held at 34%, the soft wall.** Skipping the held raids costs 34% of the levels (aim 20–25%), and that profile never reaches Vei-ready, because the giants front's undead come from held re-raids' husks. Held raids are mandatory, not optional. The fix is a husk source for a held fort (Phase II, below).
- **V-b (c), don't ship.** The 10–25% away-loss aim was an agent's, not Shawn's. The checks that replaced it pass: a prepared away loses 0 forts, and an unprepared away loses some.
- **Continuous play's aim re-set to 5–10% sooner** (from 10–30%). Seeds 1–4 come in 7.2, 9.6, 4.0 and 1.3% sooner, a mean of 5.5%. Seed 4 is limited by the fronts, the same husk dependency.
- **P8's 18.9%:** the typical human dies 18.9% of raids at tier against a 10–15% aim (P8, below).
- **catchup_bench's 7-day catch-up is over 10 s,** inside ruling 37's 12 s budget. The worst row is midgame_2flips at 11.75 s in the slow-suite run at 2e786ed (11.48 s in the balance pass), a 0.25 s margin; pre_vei is 10.94 s.

## V-I3's partials and its miss
One line each, with the follow-up `RUN/reports/vision-i3.md` §2 names. "Phase I shot" follow-ups were not taken in Phase I and fall to Phase II's first tour.
- **#5 Living people moving in the town:** a living-people read in the town (Phase II).
- **#9 Systems in the main town for Relish:** a tour shot of a built Chapel with a clone (Phase II tour).
- **#11 Better circles, better undead:** shoot the trance hint and a loop result in the tour (Phase II tour).
- **#15 Economies feeding each other:** a husk source at a held fort (Phase II, ruled).
- **#18 The WORK/WAR tradeoff:** make the choice bite (Phase II). The contradicting nag is fixed (V-I3 ruling 1).
- **#26 Flair that still makes sense:** text density on the map and the raid HUD (Phase II).
- **#28 Active play is raising undead:** a tour shot of a held re-raid (Phase II tour); the husk source (Phase II).
- **#29 Always something to do while active:** the held-fort husk source and a town fallback line when nothing is affordable (Phase II).
- **#31 Never encouraged to just not run the game:** accepted by the re-set 5–10% aim (above).
- **#34 Raids as the "always something to do":** a tour shot of a held re-raid (Phase II tour).
- **#41 The soft wall (miss):** a husk source for a held fort in loot.json, then a re-grade (Phase II, ruled).
- **#42 3–6 min raids with real risk:** rule on the 2:30–3:00 band; check length on the next capture (Phase II).
- **#43 10–15% deaths at tier:** a human capture checks t4, Vespers and fire and toll first (P8, below).
- **#47 Oopsies always possible, not fatal:** a tour shot of a backup spent in a fight that is then won (Phase II tour).
- **#51 Finding how to move and raid:** shoot the raid card on the map (done in the V-I3 round's 12-raid-entry-card); keep a post-clarity human capture queued.

## Phase II backlog
One list. The phylactery-charge mismatch is already under "Recorded for Phase II" at the end.

**Economy and balance**
- **A husk source for a held fort,** the raid wall: dungeon's loot.json plus economy's re-grade (the batch and the faithful Vei grade).
- **The solver-speed unit.**
- **Any curve change from an S1/S2 re-measure.**
- **The bots' `_reorder` and Grow reading the smoothed bone net** (after B4), with a batch re-run.
- **Field reach:** on the shipped 128 × 90 field, 8 or 9 of the 12 villages are nobody's on day 3. Re-run the batch on the shipped field before touching it (the bots' 8 × 6 field inflates villages).
- **The won game's gold decline:** −2 820 gold over a 24 h won away, with at least seven buildings stopped for unpaid upkeep.

**Raids and Vei**
- **A human capture on seeds 80–99** (seeds 60–79 are spent): t4, Vespers, and fire and toll first.
- **The 2:30–3:00 raid-length band** that no rule covers.

**The town**
- **A town fallback line** when nothing is affordable in a session.
- **Marking the started builds on the town:** "0 of 8 slots held" sits oddly beside five builds that did start, and the top row's Up button is live.

**The map and the away report**
- **A win summary card:** time, clones used, forts held.
- **04b's callout placement:** the retreat line prints over the fort's own label and collides with the WAR tooltip.
- **11b's READY row and LOSSES list.** The unpaid-upkeep line is cut at the panel's edge, which hides its own "Build a Market". "Queue empty: plan the next build" under it then reads as a clash. Fix the clip first (rows that wrap), then drop the queue-empty line when the upkeep line shows. Until then it's the only lever on screen. The LOSSES list repeats seven near-identical "stopped for … gold ran out" lines; group them.
- **The won map still says VEI'S** on the chip and the legend word for forts not taken, after her death. The tags, card lines and retreat lines are true now; the chip and legend word are the leftover.
- **The #8 card's two nits:** "you don't need one here" (a big undead) right before "this raid can't be won yet" (any undead); and "Haul: none yet (auto)" above a live HAUL FROM HERE, which reads as nothing to haul though the button only sets the target.
- **The neutral village line** has no shot. Its evidence is `test_away.gd`'s neutral and Vei-taken village cases (the exact line, kind and target) and economy's seed-3 run (`RUN/reports/economy/phase-i-balance.md` §12.2).

**Tests**
- **test_shown_net's behavioural twin.**
- **Two source pins stay** because their scripts name an autoload and can't compile headless: MapHud's BoneWarn wiring (`test_map_hud.gd`; MapHud names Game) and MapAway's footer (`test_map_idle.gd`; MapAway names ConfigDb). The logic behind each is tested (BoneWarn, `bone_quiet`, `panel_fit`).

## What Shawn plays first
Run from the repo root. The first run needs `godot --headless --path prototypes/necropolis --import`. A normal launch resumes the autosave (`~/.local/share/godot/app_userdata/Relish — Necropolis/saves/auto.json`, which holds the 2026-11-17 game) or starts a new game when there is none. Any flag after `--` other than `--reduced-motion` makes a harness session that saves nothing, so a fixture never touches the real game.
1. **A new game:** move `saves/auto.json` aside (keep it), then run `godot --path prototypes/necropolis`. For a throwaway one instead: `godot --path prototypes/necropolis -- --new-game`.
2. **The first raid:** Old Sluice is tagged "your first dungeon". Click it, MOVE Relish there, then DESCEND. Its warden is the Bellringer, and a teaching pile sits by the spawn. To record the raid for P8, launch with `godot --path prototypes/necropolis --capture` (the flag before `--`).
3. **The town:** click Covington and go in. The goal plate names the next step ("next: …"), and the queue says why each build waits.
4. **An away:** quit (the game saves), come back later and relaunch. The catch-up runs, and "While you were away" lists the gains, what's ready and the losses. In a session, the map's ×10 and ×60 buttons speed the realm up.
5. **Reaching Vei:** `godot --path prototypes/necropolis -- --fixture=midgame_2flips` starts two forts in, and `godot --path prototypes/necropolis -- --fixture=pre_vei` starts ready to face her: move Relish to Vei's gates, then BEGIN on the Vei card. A won pre_vei, to see the after-state, is `godot --path prototypes/necropolis -- --fixture=pre_vei --won`.

**The game's own guides:**
- the goal line on the map and town ("Your goal: take Vei's forts, then beat Vei");
- the town's goal plate and "next:" line;
- the map legend (open by default) and the top bar's words, which explain themselves on hover;
- the raid's CONTROLS legend and goal block ("GOAL · break … to take …");
- the clear card's LOOT, USE and NEXT, and the death card's AFTER;
- `--reduced-motion` for reduced motion, and F8 toggles it in the game.

The design docs are `prototypes/necropolis/docs/` (GAMEPLAY, MECHANICS, BALANCE, IDLE, VISUAL-LANGUAGE).

## What waits on Shawn
- **The re-capture:** a few raids at his own tier with `--capture` (step 2 above). P8 reads it. Deaths over 25% or raids under 2:30 reopen the raid knobs.
- **Grow's default:** keep Grow on by default for new games? (It is on now; older saves load with it off.)
- **V-b's reading:** a prepared away loses no forts, and an unprepared one loses some, in place of the agent's 10–25% loss aim.
- **The warned-attack assist:** a stub, off by default (LONGER WARNINGS on the raid's CONTROLS legend). Keep it, or drop it.
- **The ladder drag:** the town's drag-to-reorder ladder needs a real mouse to check where a row lands. Injected events can't place a Godot drag drop.

## P8: capture calibration, closed without a human capture

**Closed 2026-11-19 on bot evidence. No human capture was used, and no knob changed.** P8 was meant to tune raids against Shawn's own play (`RUN/phase-i-draft.md` §3, P8, and §6 Q4). The one capture he made, on 2026-11-17, ended every raid in a retreat. No re-capture came after the clarity rounds. So the manager closed P8 on the bots' numbers plus the trigger rule, as Q4 recommends. (`RUN/` is the run folder, `~/documents/apps/kautiontape/runs/relish-realm-2026-11-13/`, as in docs/BALANCE.md.)

### The trigger rule
- **Draft line 114 (P8's own rule):** "If capture shows death under 25% and raids at 3:00 or longer, this unit shrinks to recording the numbers. Exit: typical-human risk 10-15% at tier (graded on seeds 60-79 plus Shawn's records); runs 3:00 or longer."
- **Draft line 58 (the knobs' trigger):** "build none before capture; trigger: death over 25% at tier, or raids under 2:30".
- The two leave a gap. A raid between 2:30 and 3:00 doesn't fire line 58, and it doesn't meet line 114's 3:00 either. Nothing rules on that band, and this close doesn't either.
- Both lines are written for a human capture. Bot numbers can't fire the trigger or satisfy the exit. They're recorded below beside it.

### The bots on seeds 60–79 (graded 2026-11-19 at 82fc4b5)
The cells, bots and method are D-e's, so the numbers compare with its grade on seeds 40–59 (`RUN/reports/dungeon.md`). The plan was written before any row (`RUN/reports/dungeon-i/p8-grade-plan.md`). The raw rows are in `RUN/reports/dungeon-i/p8-grade-g60.tsv`.
- **Seed history:** the at-tier seeds are fresh. The first dungeon's seeds 60–67 were used once before, at 638fd85 (`RUN/reports/dungeon-i/day1-t1-raw-638fd85.tsv`).
- **The grade's sha and this one:** 82fc4b5 is bridged to the tree this file ships in by two checks:
  - the five deterministic bots are byte-identical;
  - a raid-file diff touches only the Vei loss card (`boss_logic.gd`, `vei_boss.gd`, `vei_card.gd`, and raid.json's `vei_loss` words).
- **At tier:** the 9 forts, each with its tier's standard party (t2 chime-fort, lantern-keep, vespers; t3 hollow-redoubt, mourners-gate, pale-bastion; t4 sable-hold, the-stair, whitecross), 20 seeds each.
- **The first dungeon:** old-sluice on the day-1 fixture.
- **Two bots, both at score 70:**
  - the frozen bot, which answers a tell in 0.45 s;
  - the typical human: a 1.0 s answer, a 1.0 s read on entering each room, and 0.7 s to draw each circle.
- **Rates:** a count, its Wilson 90% interval, then the seed-clustered interval (n/1.5). Retreats count as neither a death nor a win.
- **Determinism:** 400 runs, all in lockstep, no script errors.

**Deaths**
| | frozen bot | typical human | D-e (seeds 40–59): frozen / human |
|---|---|---|---|
| at tier, pooled | 18/180 = 10.0% (7–14; 6–15) | 34/180 = 18.9% (15–24; 14–25) | 15.0% / 21.1% |
| t2 / t3 / t4 (of 60) | 5 / 5 / 8 | 11 / 8 / 15 | 9 / 11 / 7 · 12 / 11 / 15 |
| first dungeon | 0/20 | 0/20 | 0/20 / 0/20 |

- Highest fort: vespers (t2), 9/20 for the typical human. Most of the typical human's deaths came to the Pyre-priest's fire (9) and the Bellringer's toll (8).
- Both bots sit inside D-e's seed noise.
  - The typical human is above the 10–15% band, as on seeds 40–59 (21.1%), and under the 25% trigger.
  - Its t4 is exactly 15/60 = 25.0%. That is "over 25%" by no margin, and it was 15/60 on seeds 40–59 as well.

**Length**
| | t2 | t3 | t4 | all |
|---|---|---|---|---|
| frozen bot, median scene s | 114.8 | 135.2 | 127.7 | 125.1 |
| typical human, median estimate s | 160.2 | 193.1 | 165.0 | 170.3 |

- The typical human's estimate is the scene seconds plus the circle's slow time, the raises, the travel, the reads and the tells. The formula is in `RUN/reports/dungeon.md`:82; it reproduces D-e's 178.3 s from D-e's own rows.
- At tier, 79 of 180 runs (44%) reach 3:00, and 58 (32%) are under 2:30.
- The first dungeon's median is 142.2 s (D-e: 139.3), and 12 of 20 are under 2:30.
- Six runs are over twice their fort's median: chime-fort 65, mourners-gate 75 and sable-hold 79 for the frozen bot; mourners-gate 61 and 68 and sable-hold 62 for the typical human. They stay in the medians, as D-e's did.

**Against the trigger (bot numbers can't fire it):**
- **Deaths:** at tier, under line 58's 25%. Above P8's 10–15% exit band for the typical human; inside it for the frozen bot.
- **Length:** the typical human's 2:50 median falls in the band between line 58's 2:30 and line 114's 3:00 that no rule covers.
- **The first dungeon** is under 2:30. Line 58 doesn't name it apart from the tiers.

### Shawn's records (2026-11-17, 21:57–22:01, `raid_capture.jsonl`)
| # | fort | tier | outcome | wall s | raises | entered the warden room | warden tells shown / struck |
|---|---|---|---|---|---|---|---|
| 1 | old-sluice (first dungeon) | 1 | retreated | 63.3 | 2 | yes | 2 / 2 (slam) |
| 2 | ashgate | 1 | retreated | 59.5 | 4 | yes | 5 / 0 (lunge, 5 dodged) |
| 3 | greywall | 1 | retreated | 26.8 | 2 | yes | 1 / 0 (lunge, dodged) |
| 4 | lantern-keep | 2 | retreated | 11.7 | 0 | no (spawn) | none |
| 5 | old-sluice (first dungeon) | 1 | retreated | 18.0 | 0 | yes | 0 / 0 |
| 6 | greywall | 1 | retreated | 10.6 | 0 | yes | none |
| 7 | ashgate | 1 | retreated | 5.9 | 0 | no (spawn) | none |
| 8 | greywall | 1 | retreated | 8.0 | 0 | no (ante) | none |
| 9 | hollow-redoubt | 3 | retreated | 12.4 | 0 | no | none (7 hits from the living) |

- **No death-rate data.** All nine retreated, with no clear and no death, so they say nothing about the 10–15% band or the 25% trigger. Their lengths are retreat lengths, not raid lengths.
- **A correction to the first reading:** five of them (1, 2, 3, 5, 6) did enter the warden room. "None reached a warden" was wrong, because the record's last room is the last room *first entered*, not where she ended (`RUN/reports/dungeon-i/handoff-1.md`).
- **Raids 4–9 fit a bug fixed since.** With the retreat dialog open, Space (also the circle key) confirmed it, so a click near the door followed by Space to start a circle ended the raid. Raids 4–9 last 6–18 s with no raise. The circle slows scene time, and raids 5–8 have scene time within 0.02 s of wall time, so it never opened; raids 4 and 9 are within 0.66 and 0.40 s, about a second of circle at most. That fits the bug and also fits deliberate retreats; the record had no field to tell them apart. 638fd85 fixed the dialog (Space closes it, only a click retreats), and capture now writes `retreat_by`. So these retreats aren't evidence about difficulty either way.

### What was not used
No human capture was used for any number, pick or ruling in P8. Every rate and length above is a bot's. Shawn's nine records are listed for completeness and carry no death or length data.

### Ruling (manager, 2026-11-18)
P8 closes as recorded, and no knob changes. The typical human's 18.9% on seeds 60–79 is above the 10–15% exit, but it is within seed noise of D-e's 21.1% on seeds 40–59. Tuning to it without a human capture would tune the raids to the bot. The ruling can be reversed: a human capture that fires the trigger reopens the knobs listed below. That capture should check these first:
- **t4 at 25%.** The typical human's 15/60 sits on line 58's trigger line, as it did on seeds 40–59.
- **Vespers at 9/20,** the typical human's highest fort.
- **Fire and toll as the top killers.** Of the typical human's 34 deaths at tier, the Pyre-priest's fire took 9 and the Bellringer's toll 8 (the grade rows' `killed_by`).
- **The 2:30–3:00 gap between lines 58 and 114.** The typical human's 2:50 median falls in it, and no rule covers it.

### What a later capture should check
A capture is three or more raids at Shawn's own tier, with `godot --path prototypes/necropolis --capture` (the flag before `--`). Each run appends one record to `~/.local/share/godot/app_userdata/Relish — Necropolis/raid_capture.jsonl`. Read it for:
- **Death at tier:** against the 10–15% band and the 25% trigger (line 58). Count deaths, not retreats.
- **Length:** wall seconds per finished raid, against 2:30 (line 58) and 3:00 (line 114). The bots' typical-human median above is the comparison.
- **`retreat_by` on every retreat,** so a chosen retreat is told apart from a misclick.
- **The answer delay.** The bracket's cliff is about 15% deaths at a 1.0 s answer and 53% at 1.5 s (score 70, seeds 20–39). A capture whose tells are answered late belongs on the steep side.
- **The Shieldwall's answered-but-struck tells** (D-e: 1 for the frozen bot, 6 for the typical human). A capture that answers a Shieldwall tell and is still struck is that open risk.
- **Whether the first raids now reach and break a warden,** after the clarity rounds that followed the 11-17 capture.

If the trigger fires, the knobs waiting on capture are `RUN/phase-i-draft.md`'s K-a (more tell lead at the lever tiers, then a re-pick of `relish_dmg_mult_by_tier`), K-c (reach knobs, the t3/t4 set pieces, the soldier plate) and K-e (economy's held-raid calibration). K-b, the longer-warnings assist, is built and off by default. **Seeds 60–79 are now spent.** A new round grades on seeds 80–99.

## Recorded for Phase II (dungeon-i Session 7, the manager's ruling of 2026-11-19)
- **Vei's fight and the odds count phylactery charges differently.** The fight spends every charge the boss seed carries (`VeiFronts.next_backup` reads the seed's raw `phylactery_charges`). The odds a player reads count at most `phylactery.max_per_dungeon` (1) (`GameState.vei_backups`). So the shown odds err low, which is the safe side. Not changed in Phase I. The loss card's advice names clones only.
