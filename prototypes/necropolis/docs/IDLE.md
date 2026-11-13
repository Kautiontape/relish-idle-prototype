# Necropolis: idle (the time model), v1

Written 2026-11-13 by the run manager from Shawn's answers. **Where this doc disagrees with
GAMEPLAY, MECHANICS or BALANCE, this doc wins.** Those docs keep everything else. The lines in them
that now say the opposite point here.

## The ask (Shawn, 2026-11-13, verbatim)

> the active play should always be in "raising" the undead through the dungeon, raising undead
> manually, and making the decisions that operate while idle. You should always feel like there is a
> thing to do while active playing, but that the real growth comes over time while you are idle.

> Idle should include the game being closed. [...] you should never be encouraged to just not run the
> game. *BUT* that doesn't mean they feed the same resources. I think actively playing can nudge up
> but idle still is the way to win in the end.

> Raising manually I meant in the crypt slab, yes. The drawing circles minigame should only be for
> dungeons. Dungeons/raids should be the "always something to do" thing

> I agree Relish shouldn't die while away, but I think that you should be able to lose all but the
> home town if you're away and it's not properly tuned to be supported. Build queue while away is
> good, but we can play with conditional stances if we feel there is an imbalance, no point in
> premature balancing. I do agree that pacing would be days of sessions

## 1. The model in one paragraph
Real time is the growth engine. The necropolis streams whether the game is open or closed, and on
launch it catches up the time you were gone. Active play is raising and deciding. You raid
fortresses and draw circles, you raise big undead on the crypt slab, and you set up the machine that
runs while you're away: the valve, the job ladder, the build queue, where Relish waits, and who
guards which fort. Active play feeds resources that time can't make (relics, blueprints, husks,
essence, quality, flips). Those raise the rates that time multiplies. The backlog, the win meter,
climbs mostly while you're away. Leave a weak setup for two days and Vei takes back every fort, but
never Covington, and Relish never dies.

## 2. Rules
| # | rule | why |
|---|---|---|
| I1 | **Closed equals open.** Closed time runs the same simulation as open time, caught up on launch. Closing the game never earns more than leaving it open, and never less, except for what being present lets you respond to. | "never encouraged to just not run the game" |
| I2 | **Active and idle feed different resources.** Time drives the streams (mint, workers, bodies, gold, bone, the living, the backlog). Only active play produces relics, blueprints, husks, remnants, essence, circle quality (`q_raise`), flips and retakes, and big undead. | "they don't feed the same resources" |
| I3 | **Dungeons and raids are the "always something to do".** Circle drawing exists only in dungeons. Every fort is always raidable: re-clears decay (MECHANICS §5.3), and a fort Vei retakes refreshes its yield. | "Dungeons/raids should be the always something to do thing" |
| I4 | **Manual raising is the crypt slab** (MECHANICS §4.6), unchanged. It is not a drawing verb. GAMEPLAY §8's "no scene borrows another's verb" stands. | "Raising manually I meant in the crypt slab" |
| I5 | **Relish never dies while away.** A run cannot be open across a close: quitting mid-dungeon is a retreat without banking, so unbanked loot is lost, Relish stands at the fort, and the fort doesn't flip. | "Relish shouldn't die while away" |
| I6 | **Everything except Covington can be lost while away:** held forts, the villages that follow them, and simulacra charges. Covington, its buildings, its stocks (within caps) and the big undead are never lost while away. | "lose all but the home town if ... not properly tuned to be supported" |
| I7 | **The build queue runs while away** (§5). | "Build queue while away is good" |
| I8 | **No conditional valve stances for now.** The valve stays where you set it while you're away. Add stances only if E4 shows the frozen split hurts. | "no point in premature balancing" |
| I9 | **No player time controls.** 1×/2×/4× is debug only. Real time is the engine, so speed buttons would skip the game. | follows from I1 |
| I10 | **Pacing is measured in days of sessions** (§7). | "pacing would be days of sessions" |

## 3. Holds become contests, not timers (the change I6 needs)
Today a flip holds a fort for `flip.hold_s`, so every hold lapses within hours however well you set
up. That can't express "properly tuned to be supported". From E2:
- **A flip starts a grace period** of `flip.hold_s · (1 + flip.tier_mult · tier)`. No tithe wave
  targets the fort during grace.
- **After grace, the hold is a contest.** The fort stays held while its **support** is at least Vei's
  **pressure** there:
  - support = your undead mass at the fort (fed by WAR staging, §3.2) + siege big undead (their
    `power`, via `big_undead.siege_k`) + Relish's or a simulacrum's presence (`hold.presence_k`);
  - pressure = Vei's living inflow to that fort, which a tithe wave multiplies by `tithe.surge_mult`.
- **When pressure wins for `hold.break_s`,** the fort is retaken (`fort_retaken`). It re-garrisons,
  and its loot yield refreshes (I3).
- **Siege big undead at a retaken fort fall back to the crypt,** wounded for `big_undead.wound_s`
  (out of the party and off the fronts until healed). They never die while away (MECHANICS §4.6:
  "they die only in dungeons or the Vei fight").
- The valve's WAR share is therefore the **support you commit to your territory while you're away**:
  more WAR keeps forts and loses FLOOD. That is the main decision you make before leaving.

## 4. Catch-up (closed time and long gaps)
- **On load:** `elapsed = now_unix − saved_unix`. Negative values count as 0. Anything above
  `idle.catchup_max_s` (7 days) is dropped, as a sanity cap and not a design lever, and the report
  says so.
- **Long gaps while open** (machine asleep, a debugger pause): a frame delta above `idle.gap_s` (30 s)
  goes through catch-up instead of being dropped (this replaces MECHANICS §1.3's "any remainder after a
  hitch is dropped"). Otherwise sleeping with the game open would lose time that closing keeps,
  breaking I1.
- **Method:** the same GameState with coarse substeps (`idle.catchup_substep_s`, about 5–10 s). The
  influence field ticks at `idle.catchup_field_hz`, low. Events (tithe warnings and waves, grace ends,
  retakes, builds done, store overflows) resolve in order and are collected for the report.
- **Budget:** 12 h of catch-up in under 2 s, and 7 days in under 10 s, on jenova. Show a progress
  screen when it takes over 1 s.
- **Determinism:** the same save and the same elapsed time give an identical result.
- **Accuracy test:** catch-up of T against a live run of T with no input, from the three fixtures:
  - the ledger balances exactly;
  - key stocks and rates are within `idle.catchup_tol` (2%);
  - held-fort count is within ±1, and Covington is identical.

## 5. The build queue
- An ordered list of builds and upgrades (`cmd_queue_build`, `cmd_unqueue`, `cmd_reorder_queue`), up
  to `queue.max_len`.
- The head starts when its costs are affordable and its gates (blueprint, tier, relics) are met. It
  never skips the head, so the order is the plan. A head that can never start (a missing blueprint)
  is flagged, and the queue waits.
- It runs open or closed. It is the main way growth **compounds** while you're away: streams level off
  at their steady states, and the queue spends them into buildings that raise those rates.
- **Stores have caps** so an empty queue saturates: gold and bone get caps (`gold.cap`,
  `bone.cap`), raised by buildings that economy picks in `buildings.json`. The bodies store is
  already capped. Overflow is waste and shows in the report.

## 6. The away report
When you come back (on launch, or after a gap over `idle.report_min_s`, 10 minutes), the map opens
with a **"While you were away"** panel. It shows rates, not just totals:
- the duration, and per stream the average in, out and net per second, plus the net total (mint,
  workers, bodies, gold, bone, the living, the backlog with its ▲/▼);
- **events in order:** forts retaken (and by what), tithe waves, villages lost, builds done, store
  overflow (how much was wasted), big undead wounded;
- **what's ready now, each line an action:** "Retake Ashgate (raid)", "2 husks: raise at the slab",
  "Queue empty: plan the next build".

API: `view_away()` (the last report, kept until dismissed) and the event `away_report`.

## 7. Pacing (replaces BALANCE §1's hours-of-active-play targets; E4 calibrates)
**The sessions profile:** three sessions a day of 15–25 minutes, closed the rest of the time.
| target | value |
|---|---|
| Vei-ready under the sessions profile | **5–8 days** (about 3–5 h of active play in total) |
| share of backlog growth that happens while away, under sessions | **≥ 70%** |
| dead air: active minutes in which nothing has positive projected value | **< 10%** |
| continuous play (open all day, always acting) reaches Vei-ready, in calendar time | **at most about 30% sooner** than sessions, so idle still wins |
| pure idle from a fresh start (never descends) | never Vei-ready; plateaus within a day (relics gate tiers) |
| after an 8 h overnight gap with a sensible setup | the report shows backlog ▲ and at least one thing to do |
| away 24 h with the default setup | at least half the held forts lost |
| away 24 h with a prepared setup (WAR support plus siege on the likely targets) | at most a quarter lost; Covington never |
| first session | GAMEPLAY §6's opening still holds: first dungeon, flip and big undead, and a queue set before leaving |

**Ablations stay** (BALANCE §2), measured in days under the sessions profile, plus one more: "never
retake lost forts" must cost at least +20%.

**The stock rule** becomes: no stock grows without bound over a 7-day sessions run. Every store is
capped, and the queue spends into growth.

## 8. Who builds what
- **economy:**
  - E1: `saved_unix` in saves (done or in flight);
  - E2: catch-up and gap routing, holds as contests, the build queue, store caps, `view_away` and
    `away_report`, quitting mid-run, removing player time controls;
  - E3: the siege fall-back and wounds, and autoplayer profiles (sessions, continuous, pure idle,
    away-risk);
  - E4: calibration.
- **map:** the away report panel; remove the time-control buttons; tithe warnings and hold contests
  readable at a glance (support vs pressure at each held fort).
- **town:** the build queue UI (reorder, blocked head); store caps visible; the slab unchanged.
- **dungeon:** quitting mid-run (I5); a retaken fort's refreshed yield shown on its card.
- **ground:** no change.

## 9. Future (not in this run's scope)
Shawn's idea, verbatim:
> a FUTURE idea is that we could Clash of Clans style warn the user if we can predict in advance when
> something would occur (e.g., a depleted territory) then we could create a timer that pops a
> notification when that time would come to warn the user.

Streams make this cheap to forecast: "Ashgate's hold breaks in about 3 h at current rates", "the
bodies store fills at 02:10". A later step could add a `view_forecast()` list, and scheduled OS
notifications on close after that. Nothing in this run depends on it.
