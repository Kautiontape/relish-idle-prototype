# Necropolis: idle (the time model), v2

Written 2026-11-13 by the run manager from Shawn's answers. v2 folds in a vision-and-systems review
(run folder `reports/review-idle.md`). **Where this doc disagrees with GAMEPLAY, MECHANICS or
BALANCE, this doc wins.** Those docs keep everything else. The lines in them that now say the opposite
point here. Numbers in this doc are E4 starting targets, not gates.

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

## 1. The model
Real time is the growth engine. The necropolis streams whether the game is open or closed, and every
load catches up the time since the save.

Active play is raising and deciding:
- you raid fortresses and draw circles (the only place you draw);
- you raise big undead on the crypt slab;
- you set up the machine that runs while you're away: the valve, the job ladder, the build queue,
  where Relish waits, and who guards which fort.

Active play feeds resources that time can't make (relics, blueprints, husks, essence, circle quality,
flips). Those raise the rates that time multiplies. The backlog, the win meter, climbs mostly while
you're away.

Leave a weak setup for days and Vei takes back every fort, but never Covington, and Relish never dies.

**Where Relish stands when you leave is your first decision.** At home she runs the slab, adds a
stance slot and slows rot. At a fort she bends the tide, redirects the dead and blunts tithe waves
there.

## 2. Rules
| # | rule | why |
|---|---|---|
| I1 | **Closed equals open.** Closed time runs the same simulation as open time, caught up on load. Closing never earns more than leaving the game open, and never less, except for what being present lets you respond to. | "never encouraged to just not run the game" |
| I2 | **Active and idle feed different resources.** Time drives the streams (mint, workers, bodies, gold, bone, the living, the backlog). Only active play makes relics, blueprints, husks, remnants, essence, circle quality (`q_raise`), flips and big undead. **What active play earned never decays while you're away.** `q_raise`'s EMA holds when no new circles arrive, and banked relics and essence stay put. | "they don't feed the same resources"; an overnight gap mustn't erase a session |
| I3 | **Dungeons and raids are the "always something to do".** Circles exist only in dungeons. A Vei fort is raided for its warden and its flip. A held fort is raided to clear its counter-garrison (§3). A retaken fort is raided to win it back. Loot yield recovers with real time (§3). | "Dungeons/raids should be the always something to do thing" |
| I4 | **Manual raising is the crypt slab** (MECHANICS §4.6), unchanged. It is not a drawing verb, so GAMEPLAY §8's "no scene borrows another's verb" stands. | "Raising manually I meant in the crypt slab" |
| I5 | **No run survives a close, a load, a crash or a gap above `idle.gap_s`.** Each ends the run as a retreat, before any catch-up: loot found before the last checkpoint room is banked, loot found since then is lost (the same bound as a death, MECHANICS §7), there's no flip, and Relish is `at_fort`. If her fort is retaken while you're away, she walks home to Covington (`relish_returned`). She never dies while away. | "Relish shouldn't die while away"; closing must not cost more than dying |
| I6 | **Everything except Covington can be lost while away:** held forts, the villages that follow them, and any simulacrum deployed at a fort that falls. Covington, its buildings, its stores (within caps) and its big undead are never lost while away. A siege big undead at a fort that falls returns to the crypt. | "lose all but the home town if ... not properly tuned to be supported" |
| I7 | **The build queue runs while away** (§5). | "Build queue while away is good" |
| I8 | **No conditional valve stances for now.** The valve stays where you set it while you're away. Add stances only if E4 shows the frozen split hurts. | "no point in premature balancing" |
| I9 | **Time controls are debug-only** (a manager inference from I1: real time is the engine). `cmd_set_time_scale` and `cmd_pause` keep their frozen signatures and return `not_debug` in release builds. The map's speed buttons show only in debug builds. A paused debug sim doesn't count as time off. | I1 |
| I10 | **Pacing is measured in days of sessions** (§8). | "pacing would be days of sessions" |

## 3. Held forts: two pools, not a timer
Today a flip holds a fort for `flip.hold_s`, so every hold lapses within hours however well you set
up. That can't express "properly tuned to be supported". From E2, a held fort is contested by the
two pools RealmSim already keeps for every fort.

**Grace.** A flip starts a grace period of `flip.hold_s · (1 + flip.tier_mult · tier)`. During grace,
Vei ships nothing there and no tithe wave targets it.

**After grace, the fort is contested:**
- **your garrison** is your undead at the fort, fed by WAR staging (MECHANICS §3.2);
- **her counter-garrison** is her living at the fort. She reships there at `hold.reship_share` of her
  normal share, rising with her odds (`tithe.backlog_scale`), and tithe waves surge into it as
  before (MECHANICS §3.4);
- RealmSim's existing fort combat runs the exchange. Your kills there stay as corpses to haul. Her
  kills ship to Vei and arm her, the usual asymmetry.

**Retake.** The fort is retaken when your garrison stays at 0 for `hold.break_s`. Refilling a
garrison takes time, so there is no threshold to chatter around. Relish there halves wave surges, and
a siege big undead blocks `tithe.siege_block` of them (MECHANICS §3.4, unchanged; no new constants).
WAR staging is split across held forts, so **holding more forts thins every garrison**. That cascade
is the "not properly tuned" failure, and it must be visible before you leave (below).

**Raiding a held fort** fights its counter-garrison:
- the dungeon seed uses the living there;
- it has no warden room, so it is a shorter run;
- clearing the room clears the counter-garrison (a clamped delta) and banks loot;
- this is how active play defends territory before you leave.

**Loot recovers with real time.** The decay from repeated clears, `loot.reclear_decay`, relaxes back
toward 1 over `loot.recover_s`. Being away refills raids, not only losing forts. The away report says
"Ashgate has refilled".

**Readable before you leave** (ships in this run; on-screen only, no timers or notifications):
- every held fort's ring shows its garrison and a margin chip, **safe / thin / will fall**, computed
  from the same stream math at the current valve and Relish's position;
- the valve panel shows "WAR supports N of M held forts";
- dragging the valve updates both live.

## 4. Catch-up
**When.**
- **Every `cmd_load`** applies catch-up from the save file's `saved_at` (integer unix seconds), so
  Continue is the launch path. One save-time field only: drop E1's duplicate `saved_unix`.
- **Long gaps while the game is open** (machine asleep, a debugger pause): a frame delta above
  `idle.gap_s` (30 s) goes through catch-up instead of being dropped (this replaces MECHANICS §1.3's
  "any remainder after a hitch is dropped").
- Negative elapsed time counts as 0. Anything above `idle.catchup_max_s` (7 days) is dropped as a
  sanity cap, not a design lever, and the report says so.
- Quitting always saves.

**Method: the same GameState, with adaptive, event-clipped steps.**
- `dt = clamp(elapsed / idle.catchup_max_steps, sim.substep_s, idle.catchup_dt_max_s)`.
- A step never straddles an event: `dt = min(dt, t_next_event − t)`. The events are a grace ending, a
  wave starting or ending, a garrison reaching 0, a break, a build starting or finishing, a store
  hitting its cap, and a floor being hit.
- First-order quantities (worker rot, `q`, the EMAs, vats) use the exact update
  `x += (x_ss − x)(1 − e^(−dt/τ))`. The EMA uses `α = 1 − e^(−dt/readout.ema_s)`.
- `stance.hold_s` must be at least `dt`.
- Gold and bone clamp to their floor of 0 and their cap on each step's net. The build queue loops
  inside a step until its head can't start.
- The influence field ticks once per catch-up step with that step's `dt`. Village owners are the one
  sim quantity that reads it. The field's results are already the same at every slice budget, so
  catch-up's field is the live field. (E2b T3.0 measured, `tests/slow/field_cap.gd`: one tick at a
  long `dt` fills the field with NaN. Its update is explicit, with `diffuse · 5 · dt` past 1 above
  about 1.25 s. 144 ticks at the live 0.2 s instead leave owners lagging: 96.8% of village-samples
  matched over 12 h, with `green_towns` off in 37 of 144. Catch-up's field needs its own plan.)
- The step sequence depends only on `(save, elapsed, config)`, never on frames. A progress screen
  advances it in fixed chunks, and chunking never changes the result.

**Budget.** 12 h in under 2 s and 7 days in under 10 s, on jenova, with a progress screen when it
takes over 1 s.
- **E2 benchmarks one substep first.** If 12 h takes over 2 s, raise `idle.catchup_dt_max_s` before
  touching the design.
- **The step is exact in its pieces; accuracy sets `idle.catchup_dt_max_s`** (E2b T3.0, which
  replaces E2a's "sub-step RealmSim below `idle.realm_dt_max_s`"). The core step
  (`GameState._core_step`, MECHANICS §1.3) changed in four places:
  - the drain is `U · (1 − e^(−r_drain · dt))`;
  - fort combat follows living's and undead's paths inside the step;
  - shipping and surges are rates, and Vei's headroom counts the step's shipping;
  - TownSim nets the body store before its cap (MECHANICS §3.1, §4.1).

  Nothing goes negative at any dt (tested to 120 s). `tests/slow/convergence.gd` measures 12 h with
  no input against a 0.5 s run, with steps clipped at the events listed under Method:
  - Vei's stocks and Covington's smooth ones stay within 0.5% up to dt 5 s (midgame_2flips 0.32%,
    fresh 0.34%) and drift to about 0.6% at 10 s.
  - The forts' pools and the body store didn't converge at any dt: 0.25 s already differs from
    0.5 s by up to 19%. The cause is not yet measured. The candidates are the dispatch rules'
    edges, the convoy's choice of fort, and the tithe surge's overfill (unbounded then; E2b
    T3.0s bounded it, and T3.0m marches the living above a fort's cap back to Vei, MECHANICS
    §3.4).
  - pre_vei's gold-floor upkeep cycle doesn't converge either: 2.5% at 2 s.
  - Cost, measured at `7ef1d8b`, best of 3 at a load average of about 4 on 12 cores, worst start
    (pre_vei): about 550 µs per core step. At a fixed 5 s step, 12 h takes 5.5 s and 7 days 67 s
    with 150 field ticks, so this budget is not met at any accurate dt. Catch-up's step is
    adaptive, not fixed: with `idle.catchup_max_steps` set so that 12 h steps at 5 s, 7 days steps
    at about 70 s. In a profile before T3.0, most of the step (two thirds to three quarters) was
    TownSim, which runs `_restaff` twice per step: by that profile, that is the cost lever.
- A thread is the fallback.

**Determinism.**
- The RNG comes from the saved RNG state, never from the wall clock or a global `randf`.
- Elapsed time is integer seconds on both paths.
- Events within one step are ordered by time, then by fort id.

**Accuracy test:** catch-up of T against a live run of T with no input.
- T = 2 h and 12 h; 7 days is a timing test only.
- Run from fixtures that aren't within a hair of a threshold, plus one threshold-free fixture that must
  match exactly.
- The ledger balances exactly. Key stocks and rates are within `idle.catchup_tol` (2%). Held forts
  are within ±1, and Covington is identical.

**Also test I1 itself:** the sessions profile with the game left open and untouched must equal the
same profile with the game closed.

## 5. The build queue
- An ordered list of builds and upgrades (`cmd_queue_build`, `cmd_unqueue`, `cmd_reorder_queue`), up
  to `queue.max_len`. Builds take their `build_work` through the build job, as today.
- **Processing:**
  - The queue is processed in order.
  - A head blocked by an **unmet gate** (blueprint, tier, relics) is flagged and **skipped**, because
    time can't resolve it.
  - A head blocked only by **affordability** holds the queue, which saves toward it.
- `cmd_queue_build` rejects with `cost_exceeds_cap` when a cost is above the current store cap, and
  suggests the building that raises that cap.
- The queue is how growth **compounds** while you're away. Streams level off at their steady states,
  and the queue spends them into buildings that raise those rates.

## 6. Store caps
- Gold and bone get caps (`gold.cap`, `bone.cap`), raised by buildings that economy picks in
  `buildings.json`. The bodies store is already capped. A cap only clips the top: gold's floor of 0
  and upkeep are unchanged.
- **Size the first caps so the default income takes at least about 8 h to fill,** which covers a
  night away.
- **Overflow is a ledger sink** (`store_overflow`), so the soak test stays exact. The report shows how
  much was wasted.

## 7. The away report
When you come back (after any load, or a gap over `idle.report_min_s`, 10 minutes), the map opens on
a **"While you were away"** panel. It is ordered **gains, then ready actions, then losses**:
- **gains:** how long you were away, then each core stream's net rate and net total (the backlog with
  its ▲/▼), builds finished, and forts refilled;
- **ready now,** each line an action: "Ashgate refilled: raid it", "2 husks: raise at the slab",
  "Queue empty: plan the next build";
- **losses:** "Ashgate retaken: raid it to win it back", villages lost, store overflow. An absence with
  no losses says **"Nothing lost."**

The full in/out table per stream is a debug view. API: `view_away()` (the last report, kept until
dismissed) and the `away_report` event.

## 8. Pacing (E4 starting targets, not gates; these replace BALANCE §1's hours-of-active-play targets)
**The sessions profile:** three sessions a day of 15–25 minutes, closed the rest of the time.
| target | starting value |
|---|---|
| Vei-ready under the sessions profile | about 5–8 days (about 4–10 h of active play in all) |
| share of backlog growth that happens while away, under sessions | ≥ 70% |
| dead air: active minutes in which nothing has positive projected value | < 10% |
| continuous play (open all day, always acting), in calendar time to Vei-ready | **10–30% sooner** than sessions. Being present is never pointless, and idle still wins. The throttles are loot recovery and the relic cap. |
| pure idle from a fresh start (never raids) | never Vei-ready (relics gate the endgame), but a full queue and a supported setup keep growing for about 2–3 days |
| after an 8 h night away with a sensible setup | the report shows backlog ▲ and at least one thing to do |
| away 24 h with the default setup | at least half the held forts lost |
| away 24 h with a prepared setup (WAR support, siege on the likely targets, weak forts raided before leaving) | at most a quarter lost; Covington never |
| the first session | GAMEPLAY §6's opening holds: the first dungeon, flip and big undead, and a queue set before leaving |

**The ablations stay** (BALANCE §2), measured in days under the sessions profile, plus one more:
"never raid held or refilled forts" must cost at least +20%.

**The stock rule:** no stock grows without bound over a 7-day sessions run. Every store is capped,
and the queue spends into growth.

## 9. Who builds what
- **economy:**
  - E1: one save-time field (`saved_at`; drop `saved_unix`). The time commands return `not_debug` in
    release builds.
  - E2: catch-up on every load and on long gaps, end-of-run on close or load, held forts as two pools
    with grace, reship and break, loot recovery, the build queue, store caps with a ledger sink,
    `view_away` and `away_report`, the margin-chip numbers in `view_fort`, and "WAR supports N of M"
    in `view_hud`.
  - E3: the autoplayer profiles (sessions, sessions left open, continuous, pure idle, away risk).
  - E4: calibration.
- **map:** the away report panel; the margin chip on every held fort's ring and "supports N of M" on
  the valve; speed buttons shown only in debug builds.
- **town:** the build queue UI (reorder, skipped and blocked heads, `cost_exceeds_cap`); store caps
  visible; the slab unchanged.
- **dungeon:** the held-fort raid (counter-garrison, no warden room, shorter); the fort card shows the
  loot it has recovered.
- **ground:** no change.

## 10. Future (not in this run's scope)
> a FUTURE idea is that we could Clash of Clans style warn the user if we can predict in advance when
> something would occur (e.g., a depleted territory) then we could create a timer that pops a
> notification when that time would come to warn the user.

Streams make this cheap to forecast; the margin chip in §3 is the on-screen first step.
