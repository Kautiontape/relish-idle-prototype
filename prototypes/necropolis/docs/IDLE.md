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
| I5 | **No run survives a close, a load, a crash or a gap above `idle.gap_s`.** Each ends the run as a retreat, before any catch-up: loot found before the last checkpoint room is banked, loot found since then is lost (the same bound as a death, MECHANICS §7), there's no flip, and Relish is `at_fort`. If her fort is retaken while you're away, she walks home to Covington (`relish_returned`). She never dies while away. One exception, because the outcome already happened while you were there: a close during the warden's victory beat (warden beaten, chest open) ends as the win, `warden_beaten` with its flip. A close during the death beat stays `relish_died`. | "Relish shouldn't die while away"; closing must not cost more than dying |
| I6 | **Everything except Covington can be lost while away:** held forts, the villages that follow them, and any simulacrum deployed at a fort that falls. Covington, its buildings, its stores (within caps) and its big undead are never lost while away. A siege big undead at a fort that falls returns to the crypt. | "lose all but the home town if ... not properly tuned to be supported" |
| I7 | **The build queue runs while away** (§5). | "Build queue while away is good" |
| I8 | **No conditional valve stances for now.** The valve stays where you set it while you're away. Add stances only if E4 shows the frozen split hurts. | "no point in premature balancing" |
| I9 | **Time controls are debug-only** (a manager inference from I1: real time is the engine). `cmd_set_time_scale` and `cmd_pause` keep their frozen signatures and return `not_debug` in release builds. The map's speed buttons show only in debug builds. A paused debug sim doesn't count as time off. | I1 |
| I10 | **Pacing is measured in days of sessions** (§8). | "pacing would be days of sessions" |

## 3. Held forts: two pools, not a timer
Until E2b-2 a flip held a fort for `flip.hold_s`, so every hold lapsed within hours however well
you set up. That couldn't express "properly tuned to be supported". Since E2b-2 (T3.1), a held fort
is contested by the two pools RealmSim already keeps for every fort (MECHANICS §3.4).

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
  hitting its cap, and a floor being hit. Since E2b-2 T3.1 RealmSim lands a grace ending, a garrison
  reaching 0 and a break at their time inside its own step (it splits the step at the first and
  last; fort combat solves the second), so catch-up needn't clip at them.
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
  - Measured at `40d62c0` (E2b-2 T4.P: a Chapel's tend slot opens only while its vat is staffed,
    and the pits have first call on the bodies; MECHANICS §7, §4.1, §4.2). The 12 h table (worst
    Vei+Covington stock at 5, 10, 15 and 30 s; 0.5 s reference): midgame_2flips 4.22%, 14.3%,
    26.9%, 68.7% (bone the worst; the backlog 0.14%, 0.38%, 0.64%, 1.67%); fresh 0.61%, 0.34%,
    0.22%, 0.61%; pre_vei 0.34%, 0.51%, 0.66%, 1.22%. midgame_2flips' bone is the convoy's: its
    haul target is Greywall, and a pickup reads Greywall's corpses from the snapshot taken before
    the step. At 10 s that snapshot holds the last step's kills, 0.04 mass, before this step's
    clearing takes them; at 0.5 s the clearing takes them as they form. So over 12 h the convoy
    lands 167 bodies at 10 s and 0.06 at 0.5 s. Its pit wants more than its supply every step, so
    with the pits first the mills get wm / (w − rot) of what lands while the store holds it (0.56
    of it): 95 bodies milled at 10 s against 1.2 at 0.5 s, 47 bone. The old proportional split gave
    them wm / w (0.4) of a similar 183, 36.5 bone, but on a bone stock that grew by 2 520 in 12 h,
    hence its 1.28%; the stock now grows by under 50.
  - At `55c281f` (E2b T4.C: the clearing counts in Vei's shipping room, the raises in a full fort's
    WAR fill, a fort WAR fills with no living takes only the living its undead kill, and unpaid
    buildings resume in the order their stocks reach the threshold inside a step; MECHANICS §3.2,
    §3.4, §4.3): midgame_2flips 0.38%, 1.28%, 2.45%, 6.30% (bone the worst; the backlog 0.24%,
    0.77%, 1.40%, 3.65%); fresh 0.61%, 0.34%, 0.22%, 0.61% (0.61% at 5 s against 0.33% at
    `985c158` is inside fresh's own 0.25 s noise row, 0.69%); pre_vei 0.33%, 0.50%, 0.64%, 1.22%.
    At `985c158`: midgame_2flips 0.38%, 1.28%, 2.43%, 6.33%; fresh 0.33%, 1.56%, 0.91%, 1.17%;
    pre_vei 7.37%, 27.3%, 27.8%, 56.5%.
  - So at 10 s (the planned `idle.catchup_dt_max_s`), at `40d62c0`, the smooth stocks are within
    0.34% on fresh and 0.51% on pre_vei, but midgame_2flips' bone is 14.3% off (its backlog 0.38%),
    above the 2% `idle.catchup_tol`; it was 1.28% at `55c281f`. Fixing it is the convoy's pickup
    (it would read each fort's corpses at its own moment), not the store's split. The 1 h gate
    (`tests/test_convergence_1h.gd`, 2% at 15 s) reads 1.50% (midgame_2flips, bone), 0.50%
    (pre_vei) and 0.14% (fresh) at 15 s, against 0.80%, 0.48% and 0.14% at `55c281f`.
  - As dt → 0 (`tests/slow/convergence_fine.gd`, against 0.125 s, err(0.5) / err(0.25)):
    midgame_2flips is first order on every stock and every fort pool, 2.1 to 2.8 (its corpses
    0.25% and 0.67%, its undead 0.06% and 0.17%; its undead were 1.48 at `985c158`). fresh's
    backlog is 3.5 (0.15% and 0.54%), its fort pools 1.5 to 1.6 and its bodies 0.75 (1.2% and
    0.9% of the cap). pre_vei's backlog, Vei's dead and bone are 2.6 to 3.3, its living 1.8 and
    its undead 2.6, but its corpses (14.4% and 10.4%), bodies (1.4% and 1.2%) and gold (0.10% and
    0.09%) don't shrink. Up to 7 200 s, before its gold floor, the corpses' error halves (0.21 and
    0.43 mass) and the store's too (0.43 and 1.30); after the floor neither does (about 4 mass).
    That is the convoy's residual below, with the store empty instead of full.
    Outcomes (flips, retakes, waves, builds, the upkeep's switches, the tier, the forts held and
    holding living at the end) match 0.125 s at 0.25 and 0.5 s at every start, and 0.5 s up to
    30 s at every start; the upkeep's switches are stamped at their step's end, so up to one dt
    apart.
  - fresh's residual is the convoy. Its store sits at the body cap 99.4% of the time, so every
    load is the headroom, about 2 of 200. A load lands whole and comes off one fort, the argmax
    over Ashgate, Old Sluice and Greywall, which the convoy itself keeps within about a load of
    each other. The pick reads their corpses as they stood at the step's start, up to one step
    stale. The runs' convoys leave at the same moments, but the first pick differs at 390 s
    between 0.5 s and 0.125 s, and at 687 s between 0.25 s and 0.125 s: there Greywall led Old
    Sluice by 0.0002 at 0.125 s and trailed it by 0.03 at 0.25 s (Ashgate's corpses agreed to
    1e-11). 8 to 11% of departures have the top two within 0.1, what one 0.5 s step's corpses add.
    From then on the sampled store and corpses differ by about one load at any dt. Those forts
    are full of corpses with few undead, and WAR keeps their undead at the cap less their corpses,
    so their undead differ by that load too. A pick that read each fort's corpses at its own moment
    (projected from the last step's rate) would remove the staleness. It changes how the convoy
    chooses (MECHANICS §4.2) and needs a corpse rate that survives a save, so it is left for a
    decision.
  - midgame_2flips' corpses: Ashgate, back near its cap after a wave, used to fill with corpses
    about 10 min earlier at 15 s than at 0.125 s (217% at 15 s). The seed was the room leaving out
    the clearing (MECHANICS §3.4): one 15 s step at t 510 s shipped it 0.038/s instead of 0.206/s,
    and its slow decline grew that. Now 27.9% at 15 s, 11.7% at 10 s, 0.42% at 5 s.
  - pre_vei's gold-floor upkeep cycle (fixed in T4.C, MECHANICS §4.3): at about 7 700 s its gold
    reaches 0 and every building that doesn't earn gold goes unpaid at once; they resume one at a
    time as gold comes back. Resumes used to be checked at each step's end, in lot order, on the
    stocks before the step's upkeep: at 10 s the raising pit (lot-02) resumed at 7 804 s, ahead of
    the house (lot-05) whose lower threshold the gold crossed first, and about 45 s before the
    gold, net of upkeep, reached either (7 847 s, 7 853 s). The pits and WAR came back early, and
    Vespers, Chime-fort and Lantern-keep, which Vei's living had refilled while WAR was near 0,
    fell instead of holding: Vei's dead 31.9% off at 10 s, the corpses 2 179%. The moments are now
    solved on the stocks' paths inside the step, so no clip is needed for them.
  - Cost, measured at `7ef1d8b`, best of 3 at a load average of about 4 on 12 cores, worst start
    (pre_vei): about 550 µs per core step. At a fixed 5 s step, 12 h takes 5.5 s and 7 days 67 s
    with 150 field ticks, so this budget is not met at any accurate dt. Catch-up's step is
    adaptive, not fixed (the `dt` formula under Method). With `idle.catchup_max_steps` set so
    that 12 h steps at 5 s, 7 days steps at about 70 s: that figure is derived (604 800 s /
    `idle.catchup_max_steps`, 8 640 steps), not measured. In a profile before T3.0, most of the step (two thirds to three quarters) was
    TownSim, which runs `_restaff` twice per step: by that profile, that is the cost lever.
    At `ea2ce47`, best of 3 at a load average of about 2.5: pre_vei 640 µs, midgame_2flips 420 µs
    and fresh 380 µs per core step (2-4% above `46710b0` in the same session's 1 h runs); at
    `55c281f`, at a load average of about 1.5, the worst start is 610-620 µs.
  - At `40d62c0` (E2b-2 T4.P), measured in one session with `6396edd`, best of 3 at a load average
    of about 2 on 12 cores: a core step at 10 s costs 248 µs on midgame_2flips, 298 µs on pre_vei
    and 242 µs on fresh (412, 621 and 383 µs at `6396edd`). The profile at `6396edd` had TownSim at
    48-64% of the step (no longer two thirds to three quarters), its two `_restaff` calls alone at
    25-37%. T4.P caches the staffing rooms and the buildings' effect sums (`TownSim._mark_rooms`), drops
    the step's redundant fill, and skips the shipping loads a bound shows can't cut a give
    (`RealmSim._load_cuts`), all bit-identical. TownSim is now 31-42% and RealmSim 44-53%.
  - 12 h at 10 s, measured from the three starts (4 320 core steps, best of 3): 1.09 s
    (midgame_2flips), 1.25 s (pre_vei) and 1.05 s (fresh) of core steps, plus 0.81 s for 150 field
    ticks (5.4 ms each, about 40% of the total): 1.9-2.1 s in all (2.5-3.3 s at `6396edd`). That is
    about the 2 s budget, and within the manager's 4 s behind a progress screen.
  - 7 days at 10 s (60 480 steps), projected from those µs per step with 150 field ticks: 15.5-18.2
    s (24-35 s at `6396edd`), so about 1.8 times the 10 s budget. Scaling the field's ticks with the
    length (14 × 150 for 7 days) would add 11 s more. T3.3 decides.
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
  to `queue.max_len` (8; E2b-2 T3.2, MECHANICS §4.4). Builds take their `build_work` through the build
  job, as before.
- **Processing**, every core step, right after the tier check:
  - The queue is processed in order.
  - An entry blocked by an **unmet gate** (blueprint, tier, a building, a locked lot, relics) is flagged
    `skipped_gate` and **skipped**: it holds nothing and starts at its own place once play or time
    clears the gate (the run's manager, 2026-11-14: such entries are accepted, not refused).
  - A head blocked only by **affordability** holds the queue, which saves toward it.
- `cmd_queue_build` rejects with `cost_exceeds_cap` when a cost is above the current store cap, and
  names the building that raises that cap (the Market for gold, the Bone Mill for bone, the Reliquary
  for relics).
- The queue is how growth **compounds** while you're away. Streams level off at their steady states,
  and the queue spends them into buildings that raise those rates.

## 6. Store caps
- Gold and bone have caps (`gold.cap` 6 500, `bone.cap` 200; E2b-2 T3.2), raised by the buildings
  economy picked in `buildings.json`: the **Market** (+3 250 gold per level) and the **Bone Mill** (+100
  bone per level), both hamlet buildings with three levels, so a cap can be raised from the first
  session. The bodies store is capped too. A cap only clips the top: gold's floor of 0 and upkeep are
  unchanged.
- **The first caps take at least about 8 h of the default income to fill,** which covers a night away
  (a new game's gold: 12.8 h to its 9 750 with the start Market; BALANCE §5 has the sizing).
- **Overflow is a ledger sink**, so the soak test stays exact. Gold and bone are not mass, so it is the
  currency tally `ledger().stores` beside the mass ledger (`sinks.store_overflow` stays 0). The report
  shows how much was wasted (T3.3).

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
