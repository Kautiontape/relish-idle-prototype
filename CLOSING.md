# CLOSING

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
