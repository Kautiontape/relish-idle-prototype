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
  "any remainder after a hitch is dropped" above `idle.gap_s`). The check is the frame's real time, so
  debug fast-forward stays live play; its whole seconds catch up, chunked, and the fraction stays in the
  accumulator (above `idle.catchup_max_s` the same cap as a load's applies: the excess and its fraction
  are dropped and the report says `capped`). Its events are queued under `idle.report_min_s` and
  collected for the report at or above it (STATE-API §6).
- Negative elapsed time counts as 0. Anything above `idle.catchup_max_s` (7 days) is dropped as a
  sanity cap, not a design lever, and the report says so.
- Quitting always saves.

**Method: the same GameState, with adaptive, event-clipped steps.**
- `dt = clamp(elapsed / idle.catchup_max_steps, sim.substep_s, idle.catchup_dt_max_s)`, and past the
  first `idle.catchup_dt_long_after_s` (12 h) of a catch-up the same with `idle.catchup_dt_long_s` (15 s)
  for the cap (E2b-2 T3.3b, the budget's lever 2, below).
- A step never straddles an event: `dt = min(dt, t_next_event − t)`. Catch-up clips at Relish's
  arrival, an unpaid building's resume, a construction finishing, the build queue's head starting on
  funds (its shortfall over the net income, for each currency it lacks; since F1 the net its
  `affordable_in_s` uses, `BuildRules.queue_net`: the HUD's below the cap, and at a full store the income
  before the cap's clip, so a head behind an entry that just spent the store is clipped at its start, not
  read as never), gold or bone reaching its floor,
  a tithe warning, and a wave starting or ending (`Catchup.next_event_s`, E2b-2 T3.3b; each projected
  from the state at the step's start, and an event within 1 µs is now). Since E2b-2 T3.1 RealmSim lands
  a grace ending, a garrison reaching 0 and a break at their time inside its own step (it splits the
  step at the first and last; fort combat solves the second), and TownSim solves a store hitting its
  cap inside its step, so catch-up doesn't clip at them. A gated queue entry starts on a tier rise or a
  building finishing, which are clipped already.
- First-order quantities (worker rot, `q`, the EMAs, vats) use the exact update
  `x += (x_ss − x)(1 − e^(−dt/τ))`. The EMA uses `α = 1 − e^(−dt/readout.ema_s)`.
- `stance.hold_s` must be at least catch-up's longest step in config, the larger of
  `idle.catchup_dt_max_s` and `idle.catchup_dt_long_s` (15 s today): checked at config load
  (`GameState.catchup_config_problem`, an error naming both keys, and since E3-1 a config without it;
  `test_catchup` overrides them both ways round). E3-1 ships it at 15 s.
- **The stances in catch-up** (E3-1, MECHANICS §4.5). The stance step is the core step's first (STATE-API §3
  step 1), so catch-up runs it as live play does: at a new beat each condition is read from the state the step
  starts from, and a step of 10 or 15 s crosses a beat every time. The conditions move on continuous stocks
  (bodies, morale, the stalls' income against the upkeep), and Relish's state, whose arrival is clipped already.
  **Catch-up doesn't clip at a condition's crossing; the hold alone keeps it exact enough** (the run's manager
  asked for the decision and its evidence):
  - a crossing inside a step is seen at the next step's start, at most one step late, where live play sees it
    at the next beat (1.714 s). Then the hold, at least the longest step, keeps the stance there: a step
    changes a stance at most once, as live play does, so a catch-up never chatters where live play holds, and
    each change is one step late at most;
  - nothing a stance changes is a cliff the step's other clips depend on: a ladder stance moves hands between
    jobs (the convoy, the stalls, the pits' feed: rates the step integrates), Muster's idle cap is applied
    exactly inside TownSim's workforce update, and Thrift's idled buildings pay no upkeep from the step's start;
  - **with no stance on, catch-up is bit-identical to the tip** (41749be): 12 h caught up from each fixture
    hashes the same state (to_dict() less its `stances` block and `api_version`), the same events less
    `stance_fired`, and the same away report (`test_stances`). What differs is the stance state: each
    condition's `active`, its hold and `fired_beat_id` (the save's `stances`), and the `stance_fired` events;
  - **with stances on, catch-up matches live**: pre_vei with Thrift and Muster on (both act from the first
    beat), 30 min caught up at 10 s against 30 min at 0.5 s: the same stances act and Thrift idles the same
    three buildings (the Statue, the Reliquary, the Walls) in both, Covington identical, every stock within
    0.25% (gold 0.019%: catch-up idles them from its first step's start, live play at the first beat 1.5 s in),
    the outcomes equal; its rates are as far from live as with no stance on (pre_vei's mint is a step's own
    instant, 11.3% with none on, 12.2% here) (`test_stances`). Over 6 h at the shipped step (5 s;
    `slow/stances_catchup`, measured at E3-1): midgame_2flips with Vigil, Harvest and Thrift on matches 0.5 s
    in every outcome (85 waves, Old Sluice's retake 0.2 s apart against a bound of 2 × 5 s), Covington
    identical, every stock within 0.23% and every rate within 0.008%, the same three firings in both (Vigil,
    Harvest and the off Muster turn active; Thrift's condition never holds there, its stalls out-earn its
    upkeep); pre_vei with Thrift and Muster on: the same outcomes, Covington identical (Thrift's same three
    buildings), stocks within 0.49%, its mint 35.3% apart at the end (the instant above).
- Gold and bone clamp to their floor of 0 and their cap on each step's net. The build queue loops
  inside a step until its head can't start.
- The influence field takes `idle.field_steps` (75; 150 until E2b-2 T3.3b2, below) field steps over a
  catch-up (api-request #14, ground's `InfluenceField.catchup_step`; E2b-2 T3.3b): each on the first core-step boundary at or after
  its share of the time, the last on the end, each one live period's sources, then `catchup_step` for
  the seconds since the last, then the village owners. Nothing injects between them, and the catch-up
  ends with the field published. A short catch-up takes fewer, none under `idle.field_step_min_s` (2 s;
  a field step of up to 8 ticks costs that many live ticks). Village owners are the one sim quantity
  that reads the field. (E2b T3.0 measured, `tests/slow/field_cap.gd`: one live tick at a long `dt`
  fills the field with NaN. Its update is explicit, with `diffuse · 5 · dt` past 1 above about 1.25 s.
  144 ticks at the live 0.2 s instead left owners lagging: 96.8% of village-samples matched over 12 h,
  with `green_towns` off in 37 of 144. `catchup_step` is the plan that replaced both:
  `tests/slow/field_catchup_bench.gd`.)
  - **75, not 150** (E2b-2 T3.3b2; the run's manager's ruling, ground being closed, on the condition that
    ground's own owner test passes at 75). That test is `tests/slow/field_catchup_bench.gd`: 12 h of a
    contested scenario, catch-up against the same field steps run as exact live ticks, at least 99% of
    village samples and the green villages at the end equal. It reads `idle.field_steps` and
    `idle.field_step_min_s` and steps at 12 h / `field_steps`, so it runs at the shipped count (75 steps of
    576 s: 99.67%, green 3 = 3 = 3, finite): it passes (it was 144 steps of 300 s, 99.83%, before). A field step at 12 h is then 576 s, about one
    live tick (7.6 ms median against a live tick's 9.6 ms in the same run, load about 6), so 0.4–0.7 s for
    the 75 instead of 0.9–1.4 s for the 150 (Budget). From the three starts, 75 against 150 over 12 h and 7 days
    (the shipped schedule, the 8 × 6 field and the shipped one) gives the same flips, retakes, forts held,
    Relish's place and Covington, every Vei and Covington stock equal to the printed digit (0.000%), and
    village owners at most 1 of 12 apart; `catchup_week` and `catchup_accuracy` give at 75 what they gave
    at 150.
  - **The owners' feedback** (the migrants: `green_towns` × `town.migrant_rate` while living are under their
    cap). Over 12 h from the three starts on the shipped field, catch-up against live play at 0.5 s (one
    substep a frame, at most `field.max_ticks_per_step` field ticks each), sampled hourly: the owners differ
    in at most 1 of 12 villages at any hour, at 150 and at 75 alike, and not more as time goes on
    (midgame_2flips 0–1, a village orange live and unowned caught up; pre_vei 1 in the first 2 h, when
    catch-up loses its second green village an hour or two before live play does, then 0; fresh 0). The
    migrants that feeds TownSim differ by a fixed amount set in the first hours: +0.3–0.4 living over 12 h
    at midgame_2flips and fresh (+0.1%), −24.8 at pre_vei (−4.1%, of 605 live; −11% at 3 h). It moves no
    stock: Covington's living sit at their cap throughout at all three (26, 88 and 16), so the migrants
    above it are dropped in both runs.
  - **T3.3c's living gap** (`tests/test_away.gd`'s walk-home catch-up, 16 living live against 10.1 caught up)
    is the shrunk field's: on its 8 × 6 field with no pre-warm, Covington's village is green live and goes
    unowned at catch-up's first field step, so 0.12 living of migrants arrive in 10 min against 7.2 live.
    On the shipped field, pre-warmed, the owners match at 10 of 11 samples (one village apart once, not the
    green one), the migrants are 6.84 against 6.87 and both end at the cap of 16.
- The step sequence depends only on `(save, elapsed, config)`, never on frames. A progress screen
  (`view_catchup`) advances it in fixed chunks of `idle.catchup_steps_per_chunk` core steps, one per
  frame, and chunking never changes the result (tested to the bit at chunks of 1, 7 and 150; the shipped
  chunk is 90, a median 30–33 ms since E2b-2 T3.3b2, Budget).

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
  - **The gate** (E2b-2 T3.3a, the run's manager's rule): a 10 s core step passes against 0.5 s over
    12 h, sampled every 600 s, when all three of these hold. `convergence.gd` asserts it at every
    start through one function, `judge()`. `test_step_accuracy` runs the same function on synthetic
    series: a fixed lag passes, a mid-run fault that recovers by the endpoint fails (b), a 2% rate
    error fails (a), a tally whose endpoint is under its floor passes (a) within the floor and fails outside it, and a stock 1.5% off at one sample fails.
    - **Stocks** (Vei's backlog, dead and pool; Covington's workers, gold, bone and living): the
      worst over the samples of |x − ref| / max(|ref|, floor) is at most `idle.catchup_gate_tol`
      (1%).
    - **Tallies** (the gold and bone caps' overflow, `ledger().stores`, which start at 0): (a) at the
      12 h endpoint, |x − ref| / |ref| ≤ 1% (where |ref| is under its floor, 0 included, |x − ref| within the floor instead: a relative error on a tally that small is noise, so midgame_2flips' 0.56 bone is judged by the floor); and (b) at
      every sample, |x − ref| ≤ max(1% · |ref|, its floor). A tally that starts at 0 has no
      meaningful relative error at its first samples, so (b) has a floor,
      `idle.catchup_gate_tally_floor`: a fixed amount per tally, what one 10 s step's lag can carry
      (BALANCE §5). Bone: 1 bone. At 10 s pre_vei's convoy runs 10–15 mass of corpses (about 0.7 bone)
      behind, and the worst (b) residual at 10 s over 12 h on the three starts is 0.74 bone (pre_vei
      at 600 s). Gold: 6 gold, the largest gold income among the starts (0.6 gold/s of trade) for
      10 s; no gold tally moves. (b) catches a mid-run fault that the endpoint could average away,
      without punishing that fixed lag.
    - **Outcomes**: the flips, retakes, waves, builds, upkeep switches and tier ups come in the same
      order (their times may differ; pre_vei's upkeep switches are up to 9.6 s apart), with the same
      forts held and holding living at the end.
    - The fort pools and the body store are printed beside the gate, not gated (the residual below).
      The gate replaces the harness's 0.5% "integrator's share" criterion, which took every column,
      and the store floors the tallies borrowed at `9e42c3e`.
  - **Measured at `4d9a265`** (E2b-2 T3.3a: the zero clock, MECHANICS §3.4, and the convoy reading
    each fort's corpses at its own moment, §4.2; the gate's commit changes no dynamics). The 12 h
    table (worst Vei+Covington stock at 5, 10, 15 and 30 s; 0.5 s reference): midgame_2flips 0.15%,
    0.32%, 0.50%, 34.6% (the backlog the worst up to 15 s; at 30 s Vei's dead, and Ashgate falls at
    5 355 s where 0.5 s holds it); fresh 0.46%, 0.12%, 0.52%, 2.38% (the backlog); pre_vei 0.34%,
    0.49%, 0.72%, 1.24% (Vei's dead; the backlog at 30 s). **The gate at 10 s passes at every
    start:**
    - midgame_2flips: stocks 0.32% (the backlog, at 600 s); no gold overflow at either dt; bone over
      (a) 0.000% of 0.56 bone, (b) 0.000 of its 1.000 floor; outcomes equal (181 waves within 2.7 s,
      Ashgate's retake within 0.8 s). (a) judges a tally this small by its floor, not a relative error,
      which 0.006 bone would fail;
    - pre_vei: stocks 0.49% (Vei's dead, at 7 800 s); no gold overflow; bone over (a) 0.042% of
      827.6 bone, (b) 0.740 of its 1.000 floor, at 600 s; outcomes equal (21 upkeep switches within
      9.6 s);
    - fresh: stocks 0.12% (the backlog, at 42 600 s); no overflow at either dt; outcomes equal.
    - It passes at 2 and 5 s too. At 15 s it fails at pre_vei (bone over (b) 1.09 of 1.00 at 600 s:
      a 15 s step's lag is half again a 10 s step's), and at 30 s at all three.
    - Not gated, at 10 s: midgame_2flips' fort pools 0.89% to 4.08% (Σundead the worst); fresh's
      0.04% to 1.80% and its bodies 1.09%; pre_vei's corpses 48.4%, undead 12.7% and bodies 9.20%
      (the residual below).
  - **R1, the shed order** (MECHANICS §4.3: decorations first, the WAR chain last; measured at
    `b66e7a9`, against `bbb86dd`). midgame_2flips and fresh never shed: every row of every table is
    unchanged (timings aside). pre_vei's gold floor (7 692 s) now sheds the Statue and eight passive
    buildings and nothing else, where it shed fifteen buildings with every pit, the charnel house and
    the mill among them, so its WAR holds (42.0 mass/s against a 16.4 plateau) and its realm keeps
    moving after the floor:
    - the gate at 10 s passes: stocks 0.66% (Vei's dead at 42 600 s; it was 0.49% at 7 800 s), bone
      over (a) 0.005% of 4 730 bone (0.042% of 828: the mill keeps milling past the floor), (b) 0.740 of
      1.000 at 600 s, as before; outcomes equal (11 upkeep switches within 9.6 s, 21 before). 15 s and
      30 s still fail on bone over (b) at 600 s, before the floor (1.09, 1.24), as before;
    - not gated, at 10 s: corpses 60.2% (48.4%), undead 9.51% (12.7%), bodies 4.17% (9.20%), gold
      0.001% (0.08%). The forts holding living at the end are 6, not 9: Vespers, Chime-fort and
      Lantern-keep no longer refill with her living while the WAR is near 0;
    - as dt → 0 (against 0.125 s) pre_vei now shrinks first order nearly everywhere: err(0.5) /
      err(0.25) is 2.80 for the backlog and Vei's dead, 2.56 for its living, 2.40 for its corpses
      (0.87 before) and 2.77 for its bodies (1.00); the worst at 0.5 s is its corpses, 1.62% (11.2%).
      The residual above was mostly the post-floor stand-off;
    - a week (`catchup_week`): outcomes match 0.5 s, shipped and at 10 s throughout; the stocks are
      further off than before because the realm keeps moving (shipped: backlog 0.24%, Vei's dead
      1.10%, from 0.004% and 0.026%; 10 s: 0.14% and 0.75%). 12 h (`catchup_accuracy`, printed for
      pre_vei): stocks within 0.64%, the mint 16.3% apart at the end (14.0%; below);
    - the truth check: pre_vei+2's 18 samples all read safe and hold; the supply exemption is deleted
      (MECHANICS §3.5).
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
    hence its 1.28%; the stock now grows by under 50. (Fixed at `9e42c3e`: the convoy reads each
    fort's corpses at its own moment, MECHANICS §4.2, so at 10 s it lands nothing at Greywall, as at
    0.5 s. Figures at `4d9a265` below.)
  - At `55c281f` (E2b T4.C: the clearing counts in Vei's shipping room, the raises in a full fort's
    WAR fill, a fort WAR fills with no living takes only the living its undead kill, and unpaid
    buildings resume in the order their stocks reach the threshold inside a step; MECHANICS §3.2,
    §3.4, §4.3): midgame_2flips 0.38%, 1.28%, 2.45%, 6.30% (bone the worst; the backlog 0.24%,
    0.77%, 1.40%, 3.65%); fresh 0.61%, 0.34%, 0.22%, 0.61% (0.61% at 5 s against 0.33% at
    `985c158` is inside fresh's own 0.25 s noise row, 0.69%); pre_vei 0.33%, 0.50%, 0.64%, 1.22%.
    At `985c158`: midgame_2flips 0.38%, 1.28%, 2.43%, 6.33%; fresh 0.33%, 1.56%, 0.91%, 1.17%;
    pre_vei 7.37%, 27.3%, 27.8%, 56.5%.
  - So at 10 s (the planned `idle.catchup_dt_max_s`): at `40d62c0` the smooth stocks were within
    0.34% on fresh and 0.51% on pre_vei, but midgame_2flips' bone was 14.3% off (its backlog
    0.38%), above the 2% `idle.catchup_tol`; it was 1.28% at `55c281f`. The fix was the convoy's
    pickup, not the store's split: since `9e42c3e` the convoy reads each fort's corpses at its own
    moment (MECHANICS §4.2). At `4d9a265` midgame_2flips' bone is 0.000% off and its stocks 0.32%
    (the backlog), and 10 s passes the gate at every start (above). The 1 h gate
    (`tests/test_convergence_1h.gd`, 2% at 15 s) reads 0.50% (midgame_2flips), 0.62% (pre_vei) and
    0.28% (fresh) at 15 s at `4d9a265`, the backlog the worst at each. That compares with 0.55%,
    0.50% and 0.14% at `9b5fc99`; 1.50% (midgame_2flips, bone), 0.50% and 0.14% at `40d62c0`; and
    0.80%, 0.48% and 0.14% at `55c281f`.
  - **The residual: the start-of-step pickup cap** (MECHANICS §4.2). A pickup is held to what the
    fort held at the step's start, and the realm step owns the corpses formed inside it. So at a fort
    with no living, where Vei's shipping dies as it lands, those corpses wait for the next step's
    legs. Measured on pre_vei over 24 h at 0.5, 2, 5 and 10 s (the harness's clipped steps, sampled
    every 600 s):
    - **Bounded, not growing.** Before its gold floor (about 2.2 h) the six corpse forts form 1.88
      mass/s. At 10 s their corpses sit 9.2 mass above 0.5 s's on average (the step's own corpses:
      rate · dt / 2 is 9.4), between −1.0 and +15.5 at the samples (the 48.4% is 600 s: 48.4
      against 32.9 mass), and the convoy's landed mass runs up to 25 mass behind (9.5 at 60 s, 12.9
      at 600 s; 1.4 ahead at one sample). The worst sample is the floor itself, +28 mass at 2.17 h,
      while Vespers, Chime-fort and Lantern-keep pile up corpses (124.8 mass in all at 0.5 s) before
      her living refill them. After it only Ashgate, Old Sluice and Greywall form corpses (0.64
      mass/s), and from about 3.3 h both runs repeat the same 6 600 s cycle. The gap is +0.1 to +7.8
      mass there (mean +3.9; rate · dt / 2 is 3.2): +3.93 over 2.3–13 h and +3.95 over 13–24 h
      (slope 0.005 mass/h). The convoy's landed gap stops moving too, at +24 to +32 mass: 10 s is
      ahead now. Over the floor (7 200 to 8 400 s) the 10 s convoy landed 37.4 mass more, the forts'
      clearing took 60.8 less, and 30 fewer corpses formed (`ledger().sinks.cleared`, 3 h runs).
    - **The load's sawtooth.** `job.haul.carry` is 14 mass with a fixed crew, so a one-trip shift in
      phase moves a fort's corpses by up to a load. At 2 s the gap is −9.7 to +11.4 mass (mean
      −0.1): the 34.7% at 2 s is one load out of phase against a small floor. At 5 s its mean is
      +3.5 (rate · dt / 2 is 4.7).
    - **Against a typical pile.** Per fort the gap at 10 s is at most 14.2 mass (Vespers during the
      floor; 12.1 or less elsewhere; 4.5 after the floor), about one load. A typical pile, the six
      forts' median at 0.5 s over the samples after the first hour, is 2.2 to 2.4 mass at the three that
      keep corpses and 0 at the three she refills (Σ 6.9; before the floor 5.4 to 7.0 each, Σ
      39.7). So a fort can show a load more or less than live play would. Summed, the mean offset is
      +3.9 mass on 6.9 after the floor, and +9.2 on 39.7 before it.
    - **On return** (each run's 12 h state, then live at 0.5 s for 600 s): pre_vei's body store is
      0.0 against 3.3 mass, 1.1% of its 300 cap low (0.2% at 24 h). The forts' corpses are +4.0 mass
      (+4.6 at 24 h), and the convoy +26.8 of 37 315 landed. Live from there the store is −0.6,
      +4.5 and 0.0 mass off (−0.2%, +1.5% and 0% of the cap) and the corpses +4.3, +0.7 and +0.1
      at +60, +300 and +600 s: a transient the first minutes clear. The store sits near empty (the
      pits take every body), so the table's 9.20% is its worst sample, not the endpoint: 27.6 mass
      at 2.33 h during the floor, with 10 s above 0.5 s. midgame_2flips is identical at 12 h and
      through +600 s (no corpses, nothing landed, the store at 0). fresh's store is 198.4 against
      197.0 (+0.7% of its 200 cap) and its corpses −0.08 of 222.7; after 600 s live, −0.07% and
      −0.15 mass.
    - **On file, not built:** the realm step taking the convoy's pickup as a sink inside the step.
      It needs the shortfall reconciled (a pickup a fort can't give is owed back to the convoy),
      and it changes MECHANICS §1.3's order, TownSim before the realm step. The run's manager kept
      the order and the hold (E2b-2 T3.3a).
  - As dt → 0 (`tests/slow/convergence_fine.gd`, against 0.125 s, err(0.5) / err(0.25)). At
    `4d9a265`: every midgame_2flips error is under 0.03% (the backlog 0.008% and 0.019%, ratio 2.4;
    its pools' ratios 0.6 to 5.8 on errors of 0.002% to 0.028%). fresh's backlog and Vei's dead are
    3.3 (0.15% and 0.51%), its pools 1.3 to 1.4 and its bodies 1.24 (0.75% and 0.93% of the cap).
    pre_vei's backlog is 2.0, Vei's dead 2.3, its undead 2.3 and its living 1.5, but its corpses
    (12.9% and 11.2%), bodies (1.44% at both) and gold (0.10% and 0.09%) don't shrink: the residual
    above, and below. At `40d62c0`: midgame_2flips is first order on every stock and every fort
    pool, 2.1 to 2.8 (its corpses 0.25% and 0.67%, its undead 0.06% and 0.17%; its undead were
    1.48 at `985c158`). fresh's
    backlog is 3.5 (0.15% and 0.54%), its fort pools 1.5 to 1.6 and its bodies 0.75 (1.2% and
    0.9% of the cap). pre_vei's backlog, Vei's dead and bone are 2.6 to 3.3, its living 1.8 and
    its undead 2.6, but its corpses (14.4% and 10.4%), bodies (1.4% and 1.2%) and gold (0.10% and
    0.09%) don't shrink. Up to 7 200 s, before its gold floor, the corpses' error halves (0.21 and
    0.43 mass) and the store's too (0.43 and 1.30); after the floor neither does (about 4 mass).
    That is the convoy's residual below, with the store empty instead of full.
    Outcomes (flips, retakes, waves, builds, the upkeep's switches, the tier, the forts held and
    holding living at the end) match 0.125 s at 0.25 and 0.5 s at every start, and 0.5 s up to
    30 s at every start; the upkeep's switches are stamped at their step's end, so up to one dt
    apart. At `4d9a265` they match 0.125 s as before and 0.5 s up to 15 s; at 30 s midgame_2flips'
    Ashgate falls at 5 355 s (a second retake; from the 20th wave on the waves differ, 182 against
    181).
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
    decision. (Built at `9e42c3e`, as the run's manager ruled: MECHANICS §4.2. fresh at `4d9a265`:
    above.)
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
    solved on the stocks' paths inside the step, so no clip is needed for them. (Since R1 the floor
    sheds by class, so only the Statue and eight passive buildings go unpaid and two houses resume:
    above.)
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
  - At `4d9a265` (E2b-2 T3.3a: the zero clock's split and the convoy's corpse rates) a core step at
    10 s costs midgame_2flips +3.7%, pre_vei +6.1%, fresh 0%, per step at 10 s against `9b5fc99`, as measured for those
    commits. The gate's commit changes no step, so it isn't re-measured.
  - **Measured at E2b-2 T3.3b** through the runner itself (`tests/slow/catchup_bench.gd`: `Catchup` as
    `cmd_load` runs it, field steps on the shipped 128 × 90 grid; best of 3 at a load average of about 5
    on 12 cores, other units' runs beside it), before → after the two levers below:

    | start | 12 h s (core + field) | 7 d s (core + field) | µs per core step at 7 d |
    |---|---|---|---|
    | midgame_2flips | 2.76 (1.35 + 1.40) → 2.66 (1.27 + 1.40) | 20.59 (19.37 + 1.22) → 14.40 (13.19 + 1.21) | 309 → 299 |
    | pre_vei | 2.46 (1.51 + 0.96) → 2.38 (1.44 + 0.95) | 21.31 (20.38 + 0.94) → 14.74 (13.76 + 0.99) | 337 → 329 |
    | fresh | 2.16 (1.29 + 0.88) → 2.09 (1.21 + 0.87) | 18.71 (17.82 + 0.89) → 13.08 (12.16 + 0.92) | 295 → 291 |

    "core" is the core steps and the runner (its `next_event_s` is 3–6 µs a step). A field step costs 5.8
    to 9.4 ms, above a live tick's 5.2 ms (a 288 s field step takes most of its extra sweeps), so the 150
    are 0.9–1.4 s, a third to a half of 12 h. T3.1 had projected 15.5–18.2 s for 7 days at 10 s.
  - **Lever 1, the step's own cost** (bit-identical: from the three starts, 1 h of catch-up at 10 s steps
    then 600 s live give the same `to_dict()` and events to the byte as before). A core step at 10 s from
    pre_vei is 343 µs: TownSim's step 162, RealmSim's 136, GameState's 44 (50 before). GameState now reads
    its per-step tunables once at setup (`_slew_valve` 1, `_mint` 3, `digest_q` 3 of its 4 (`q.q0` stays
    live: a test changes it after setup), `_update_readout` 1, `substep_s`, `travel_speed`, the field
    sources' 2 and the runner's warning; a read is 0.9 µs; `relish.tide_bias` stays live, as
    `test_game_state_configs` documents), and skips the tier check (`BuildRules.rise_tiers`, 6–8.5 µs)
    while neither the buildings (`TownSim.structure_rev`) nor the tier have moved. About 5% of the step.
    The largest piece left of GameState's is `_town_inputs` (17 µs: the fort snapshot and
    `RealmSim.dead_rates`).
  - **Lever 2, a longer step past 12 h** (`idle.catchup_dt_long_s` 15 s past
    `idle.catchup_dt_long_after_s` 12 h; the run's manager's cap): a week takes 41 760 core steps (plus
    clips) instead of 60 480. 7 days is a timing test for the stocks only, so the condition is the
    outcomes: over 7 days from midgame_2flips, pre_vei and fresh, the shipped schedule's flips, retakes,
    forts held at the end and Relish's place match a 0.5 s run throughout (about 1.2 M core steps), and so
    do 10 s throughout's (`tests/slow/catchup_week.gd`, shrunk field). midgame_2flips: 1 retake, Ashgate
    held at the end, Relish at Greywall in all three; Vei's and Covington's stocks within 0.40% of 0.5 s at
    the shipped schedule (0.19% at 10 s). pre_vei: nothing held, no flip or retake, Relish at Vei, stocks
    within 0.026% (0.035% at 10 s). fresh: nothing held, Relish home, stocks within 0.52% (0.12% at 10 s).
    The 0.5 s runs took 304–365 s each.
  - So at T3.3b 12 h took 2.1–2.7 s against its 2 s budget (inside the manager's 4 s behind a progress
    screen; its 150 field steps 0.9–1.4 s of it) and 7 days 13.1–14.7 s against its 10 s (the field steps
    0.9–1.2 s of it), about 1.5 times over; the table above is the measurement (T3.3b's report gave 13.0–14.6
    s). What was left of the step was TownSim's (107–162 µs) and RealmSim's (136–141 µs).
  - **Measured at E2b-2 T3.3b2** (`7b3489a` against `602375e`, `tests/slow/catchup_bench.gd`, the two run
    one after the other twice, before, after, before, after; each figure the better of its two best-of-3
    runs, at the load average beside it, 12 cores with other units' runs beside it; the bench's RealmSim
    figure now steps on the last core step's inputs, not a load's empty ones, for both):

    | start | 12 h s (core + field) | 7 d s (core + field) | µs per core step at 7 d | load average |
    |---|---|---|---|---|
    | midgame_2flips | 2.57 (1.21 + 1.35) → 1.58 (0.84 + 0.74) | 13.80 (12.64 + 1.16) → 9.70 (9.05 + 0.66) | 286 → 205 | 2.5–2.6 → 2.1–2.2 |
    | pre_vei | 2.25 (1.34 + 0.91) → 1.38 (0.91 + 0.47) | 13.92 (12.99 + 0.93) → 9.36 (8.90 + 0.46) | 311 → 213 | 1.9–2.2 → 1.9–2.0 |
    | fresh | 2.08 (1.21 + 0.86) → 1.31 (0.88 + 0.43) | 12.48 (11.61 + 0.87) → 9.45 (9.02 + 0.43) | 278 → 216 | 2.3–2.9 → 2.2 |

    The other pair of runs: before 2.08–2.58 s and 12.79–14.17 s (load 2.8–3.5), after 1.33–1.61 s and
    9.59–9.83 s (load 2.5–3.3). A chunk of 90 core steps takes a median 30–33 ms (40–52 ms before; at most
    about 50 ms with a field step in it). Two levers, below.
  - **Lever 1, a cheaper step, bit for bit.** From the three starts and a new game that builds, queues
    and rises a tier, 1 h and 12 h of catch-up at 10 s steps then 600 s live give the same `to_dict()`,
    events and unrounded state (`var_to_bytes`) as `602375e`; the convergence tables and `margin_truth` print
    what they printed at `602375e`, and the soak what it printed at `4169662` (where it first repeats),
    wall-clock fields aside. A core step at 10 s (12 h of them, best of 3, the better of two rounds, the
    versions swapped into one copy of the project and timed in turn), midgame_2flips / pre_vei / fresh:
    264 / 307 / 266 µs at `602375e`, 191 / 211 / 202 µs committed (−28%, −31%, −24%; load 2.0–3.3). The
    savings below were timed the same way one stage at a time (load 1.5–2.5), with a convoy change that
    measured within noise and was dropped (lazy fort lookups; a second, reading the snapshot once for the
    convoy's picks, also within noise, likewise):
    - RealmSim's fort combat skips a path solve whose inputs equal the last one's (`fort_step`, `_load`):
      the pull and the kills repeat in three of four passes (a garrison pinned at 0, the living's mean
      unmoved). −9 to −14 µs.
    - TownSim reads what it needs of the buildings from lists cached like the effect sums (`_lists`,
      cleared by `_mark_rooms`): the working pits, the migrants' `attract`, the morale amenities (and
      `morale_target` sums them without building the factor rows), the working and unpaid buildings'
      upkeep and the lots under construction. −28 to −71 µs (pre_vei's upkeep the most).
    - GameState refills the core step's fort snapshot for TownSim in place (`_town_inputs(…, true)`; every
      other reader still gets a fresh one) and books the ledger inline: `Ledger.sink`'s key check formats
      its message on every call, about 1 µs, ten a step. With `_load_cuts` reading e^(−r_drain · dt) once a
      step: −11 to −16 µs.
    - RealmSim's part reads each fort's held, grace and redirect-site flags once, and the dispatch writes
      `r_in` and `r_staged` once: −4 to −5 µs.
    - The test that mutates config after setup still works: `q.q0` and `relish.tide_bias` stay live.
  - **Lever 2, 75 field steps** (Method, above): the field's share of 12 h falls from 0.86–1.35 s to
    0.43–0.74 s and of 7 days from 0.87–1.16 s to 0.43–0.66 s (a field step costs 5.7–9.8 ms at 75 against
    5.7–9.0 ms at 150: at 12 h one of 576 s against 288 s).
  - **So 12 h takes 1.3–1.6 s against its 2 s budget and 7 days 9.4–9.7 s against its 10 s: both met**, at
    a load average of about 2. The week's margin is 0.3–0.6 s (9.8 s in the other pair of runs): the load
    average of 5–6 T3.3b measured at would likely use it up. A progress screen still shows for both (over
    1 s). What is
    left of the step is RealmSim's (109–115 µs) and TownSim's (65–78 µs), and GameState's own 20–31 µs.
- **A thread is the fallback, not built** (the budget's lever 3). The catch-up would run on a worker
  thread while the main thread draws the progress screen. It needs the state owned by that thread for the
  run: GameState has no locks, so no view could read it mid-run (the progress screen would read a
  guarded copy of `view_catchup`, and every other view would wait for the end, which the chunks don't
  need); commands refusing as they do now (`catching_up`); and the shell polling for the end, then
  running the frames' own time. It wouldn't shorten the run: the 41 760 core steps and 75 field steps are
  the same sequential work (each step reads the last), so a thread buys a responsive window, which the
  chunks already give at 30–50 ms a frame. To cut the wall time, the field steps could run beside the
  core on a second thread if the core took the village owners one field step late (a dynamics change to
  gate first), hiding about 0.4–0.7 s; beyond that the cost is TownSim's and RealmSim's steps.

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

- **Measured** (E2b-2 T3.3b; `tests/test_catchup.gd` at 2 h from midgame_2flips, about 8 s of the default
  suite; fresh at 2 h once with the same helper; `tests/slow/catchup_accuracy.gd` at 12 h from all three; a
  load's catch-up, the real runner, against `tick()` at 0.5 s with the presentation step, the field
  shrunk to 8 × 6 for both). Stocks are Vei's and Covington's (`convergence.gd`'s KEY), each against
  max(|live|, its floor); rates are the mint and its WAR and FLOOD, TownSim's worker inflow and gold, bone
  and living nets, and Vei's sustained differential. Both ledgers balance to 2.4e-12 or better.
  - midgame_2flips: 2 h, the backlog 0.008%, Vei's dead 0.12%, Covington's stocks under 0.0005%, the
    rates under 0.003%, 1 held fort each, Covington identical, outcomes equal (25 waves, a retake); 12 h,
    the backlog 0.025%, Vei's dead 0.22%, the differential 0.10%, outcomes equal (181 waves, a retake).
  - fresh: 2 h, the backlog 0.58%, Vei's dead 0.40%, the differential 0.81%; 12 h, 0.12%, 0.08% and
    0.21%; nothing held, Covington identical.
  - pre_vei is left out (T3.3a's attribution): its gold reaches its floor about 2.14 h in with no input,
    a threshold in reach of 2 h, and from there its pits burn from a store the convoy refills a load at a
    time. At 12 h every stock is within 0.16% and every outcome and building state matches, but the mint
    and its split read 14% apart: the mint reads the last step's feed, which a 10 s step averages over a
    landing and a 0.5 s substep doesn't. Since R1's shed order all six of its pits keep working past
    the floor (two did): stocks within 0.64%, the mint 16.3% apart (its 0.5 s WAR swings 33 to 49
    mass/s around 42 over a convoy's cycle).
  - **The threshold-free start** matches to 1e-9 relative everywhere: a new game with no workers, the
    valve all FLOOD, Vei's pool at its cap, the living at their cap and gold well inside its range, so the
    backlog grows by FLOOD (+13 942 in 30 min), gold falls by the upkeep, the differential's EMA relaxes
    exactly and no stock meets a floor or cap. 30 min at 10 s steps against 30 min at 0.5 s (the default
    suite; 1 h, +28 342, matched the same way): the whole `to_dict()` to 1e-9, the village owners aside (1 of 12 differ: the field's, which the live field ticks
    at its capped cadence, and which decide nothing there with the living at their cap).

**Also test I1 itself:** the sessions profile with the game left open and untouched must equal the
same profile with the game closed.
- **Measured** (E2b-2 T3.3b, `GameState`-level until E3's profiles; `tests/test_catchup.gd`'s `i1()` helper,
  which E3 extends): a new game's opening (the valve to 0.5 / 0.35 / 0.15, a House built, a Well queued
  on gold), then left. Open: `tick()` through the frame path at 0.25 s frames. Closed: saved, the clock
  moved, loaded. 30 min with the catch-up at its longest step, 10 s (the default suite; at the shipped
  schedule a 30 min catch-up steps at the live 0.5 s): the backlog 0.07%, Vei's dead 0.63%, gold 0.06%,
  the differential 0.12%, Covington identical, outcomes equal (both builds). 1 h at the shipped 0.83 s
  steps: 0.08%, 0.05%, 0.001% and 0.25%. 12 h (the slow suite): 0.11%, 0.10%, 0.002% and 0.22%, the
  same.

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
  economy picked in `buildings.json`: the **Market** (+3 250 gold per level) and the **Bone Mill** (a
  table per level, +100 at level 1 to +8 400 at level 8: caps 300 to 8 600; T7), both hamlet buildings
  with eight levels, so a cap can be raised from the first session. The mill's table grows with BALANCE
  §7's level ladder, so every price fits a cap the player can reach by its building's tier (BALANCE §5). The bodies store is capped too. A cap only clips the top: gold's floor of 0 and upkeep are
  unchanged.
- **The first caps take at least about 8 h of the default income to fill,** which covers a night away
  (a new game's gold: 12.8 h to its 9 750 with the start Market; BALANCE §5 has the sizing).
- **Overflow is tallied beside the ledger** (`ledger().stores`; gold and bone are not mass, so the mass
  soak is unaffected and `sinks.store_overflow` stays 0). The report shows how much was not stored (T3.3;
  W: "Gold is full: 2,162 not stored").

## 7. The away report
When you come back (after any load, or a gap over `idle.report_min_s`, 10 minutes), the map opens on
a **"While you were away"** panel. It is ordered **gains, then ready actions, then losses**:
- **gains:** how long you were away, then each core stream's net rate and net total (the backlog with
  its ▲/▼), builds finished, each queued build that started ("House started 2 h 10 m after you left,
  when the gold came in", W; "Inn started right away" when it never waited), and forts refilled;
- **ready now,** each line an action: "Ashgate refilled: raid it", "2 husks: raise at the slab",
  "Queue empty: plan the next build" (not when the stores are full: the raid prompt below takes its place);
  - **The queue's head still waiting** (R2, from the E2b-2 vision review's item 3: "come back and nothing
    happened"). When the absence ends with the queue's head waiting on funds, one line says when its funds
    come, from its `affordable_in_s` (MECHANICS §4.4): "Inn is waiting on gold: affordable in 6 m" (rounded
    up to the minute, so a wait under one never reads "0 m"), or, when it never will at the current income,
    "House can't be afforded at the current income of 0/s bone: move it down, or build a Bone Mill": the
    store, its net rate now, and what raises it (`idle.report.afford_raise`: a Market for gold, a Bone Mill
    for bone). A head short of relics, which have no idle income, gets Shawn's words with no rate (W, the
    run's manager): "Crypt level 2 needs relics: raid a fort", with ", or move it down" under the rule below
    (`afford_relics_last_fmt` only: W2 removed `afford_relics_fmt`, the move-down form, from the config,
    `REPORT_KEYS` and `report_config_problem`, since nothing can choose it). No head reaches that form: the
    queue's walk gates a relic shortfall (`no_relics`, a `skipped_gate` entry) before any head waits on funds,
    and a gated entry holds nothing. W2's relics wall (below) is what shows it. `kind` `queue`, `target`
    `queue`, so the map can dive to the queue. The
    queue never skips its head (Shawn's rule: it never stalls or jumps), so this is how the player learns
    to move a stuck head. The line never names itself or a move that can't help (F1, the run's manager):
    - **moving it down can't help** (F2): "move it down" is offered only when some other entry could start
      if the stuck one weren't ahead of it, which the report reads off the queue's walk less the stuck entry
      (`BuildRules.queue_walk` on a copy): a row that isn't `skipped_gate` (a gated entry passes the head
      anyway) and has `affordable_in_s` >= 0 (affordable now, or later at the current income). With nothing behind
      it, or only entries stuck on the same store (a House, then a Well: both need bone), or only gated ones, the
      line drops it: "House can't be afforded at the current income of 0/s bone: build a Bone Mill". With a Bone
      Mill behind it (level 1 is 60 gold, no bone) the move helps: "House can't be afforded at the current income
      of 0/s bone: move it down, or build a Bone Mill";
    - **its store's own producer** (`idle.report.afford_producer`: the Market for gold, the Bone Mill for
      bone; an upgrade counts): what raises the store would be the entry itself, so the line says a fact
      instead, true today (only a mill makes bone, only a Market gold, and a raid gives neither: loot.json
      has relics and no gold or bone): "Bone Mill level 2 can't be afforded at the current income of 0/s bone,
      and nothing else makes bone: move it down", without ": move it down" when moving it down can't help (the same rule). The
      bone fact holds until P4 makes rot a source of bone.
  - **Stores full, queue empty: raid** (R2; the run's manager, from Shawn's "needs relics: raid a fort",
    the review's question 2). When the absence ends with every capped store full (gold and bone, each within
    `idle.report.full_tol` of its cap: 1%) and the queue empty, the plateau is the wall Shawn asked for, and
    the report says so as a prompt, not neutral text: "Your stores are full and the queue is empty: raid a
    fort for relics" (`kind` `raid`, `target` `""`), in place of "Queue empty" (W: no build can be planned
    without relics, so the two would contradict each other). The full store's line stays in losses for now
    (E4 moves it). A non-empty queue never gets this prompt; the wall below is its form.
  - **The relics wall** (W2, the run's manager for Shawn): a queue of only relic-gated builds is the plateau
    Shawn wants visible, and the walk skips such an entry (`skipped_gate`, reason `no_relics`), so it never
    became a waiting head and the queue got no line. When the absence ends with no entry able to start and at
    least one skipped on `no_relics`, `ready` gets "Crypt level 2 needs relics: raid a fort"
    (`afford_relics_last_fmt`, kind `queue`, target `queue`) for the first such entry in queue order: no rate,
    no "move it down" (a gated entry holds nothing). Stores full or not. **No entry can start** is read off
    the walk's statuses: no row is `next`, and no `waiting_funds` head will be afforded (`affordable_in_s` >= 0);
    either means the town is still building, so no wall. An entry `queued` behind a head at −1.0 can't start
    either (the queue never jumps), so it doesn't clear the wall: House (−1.0 on bone), Well (queued), then a
    gated Crypt level 2 shows the House's line and the wall. A head stuck at
    −1.0 on gold or bone with a relic-gated entry in the queue shows both lines in queue order, since each
    names a different build ("House can't be afforded at the current income of 0/s bone: build a Bone Mill",
    then "Crypt level 2 needs relics: raid a fort"). The wall takes the place of the raid prompt: a non-empty
    queue never had it, so the wall is the only line, and the truly empty queue with full stores keeps
    `full_raid`.
  - **A start under a minute** (W2): a queued build that waited but began less than 60 s after you left reads
    "Inn started within a minute of you leaving, when the gold came in" (`started_brief_fmt`), not "0 m
    after". A start that didn't wait stays "started right away" (`started_now_fmt`). The cutoff is the
    report's minute rounding, `since < 60.0` in `StateViews.away_report`, the same as the unpaid line's
    "briefly" in `_unpaid_lines`; not a tuning number.
- **losses:** "Ashgate retaken: raid it to win it back", villages lost, each building that went unpaid,
  each building the Thrift stance idled (E3-1),
  each store that was full ("Gold is full: 2,162 not stored": what came in over its cap, not called waste, W).
  An absence with no losses says **"Nothing lost."**
  - **Unpaid** (R1, the run's manager; W words it as a returning player reads it): one line per building
    that was unpaid at some time during the absence, in lot order, with how long it was stopped in all (its
    `building_unpaid` spells, true then false, in the catch-up's events; one unpaid when you left counts
    from the start, one still unpaid at the end to the end), the store that ran out, and what it stopped
    doing: "Charnel House stopped for 3 h 20 m, gold ran out: hauled no corpses". The name is its town label
    (`level_fmt` past level 1), the time the report's "{h} h {m} m" / "{m} m"; under a minute in all it
    stopped "briefly" ("Charnel House stopped briefly, gold ran out: hauled no corpses",
    `unpaid_brief_fmt`), the report's minute rounding, not a tuning number. The store is each one its
    `buildings.json` upkeep is above 0 in (the same at every level), worded by `idle.report.afford_stores`:
    gold for every building today, since none pays bone; one that paid both would read "gold · bone ran out"
    (`list_sep`). "What it stopped" is one phrase per job it offers and per working effect it has (`pits`,
    `morale`, `attract`, `lifetime_bonus`, `haul_speed_mult`, `death_shock_mult`), each an
    `idle.report.unpaid_stopped` template, the same phrase said once (a raising pit's `pit` job and `pits`
    effect: "raised no undead"); a building with neither (a House, the Reliquary: only capacity effects,
    which an unpaid building keeps) has no tail: "House stopped for 14 m, gold ran out" (`unpaid_none_fmt`,
    `unpaid_none_brief_fmt`). So does one whose only working effects are in `idle.report.unpaid_inert` (F2:
    the effect keys nothing in the sim reads yet, `hint_precision` today, so a Watchtower's line reads
    "Watchtower stopped for 59 m, gold ran out", not a lie about vaguer fort hints). A key leaves that list in
    the change that makes the sim read it, and gets its words in `unpaid_stopped` then. Capacity effects count
    while unpaid (MECHANICS §4.3), so no cap falls and no stock is lost; the line no longer says "stores
    kept", which read as the stockpile's safety rather than the building's idleness. `kind` `unpaid`,
    `target` its lot id.
  - **Idled by Thrift** (E3-1, the run's manager's ruling; MECHANICS §4.5): one line per building the Thrift
    stance idled at some time during the absence, in lot order, after the unpaid lines, naming Thrift as the
    reason, not the gold: "Statue of Relish idled by Thrift for 2 h 10 m: lifted no morale, deaths shook the
    town harder" (`idle.report.thrift_fmt`; the brief's "Inn" can't be one at the shipped threshold, its 0.05
    gold/s isn't above `stance.thrift_upkeep`). Its time is the sum of its spells (the catch-up runner notes each building
    Thrift idles or resumes with its moment, `Catchup.thrift_log`; Thrift raises no event, its buildings read
    `"idle"` in `view_town`); one idled when you left counts from the start, one still idled at the end to the
    end. What it stopped is the unpaid line's phrases; under a minute it was idled "briefly"
    (`thrift_brief_fmt`), and one that stopped nothing has no tail ("Reliquary idled by Thrift for 30 m",
    `thrift_none_fmt`, `thrift_none_brief_fmt`). The same `kind` `unpaid` and lot target as R1's lines, so no
    new kind or target: the kind now means "a building stopped", by the gold running out or by Thrift
    (STATE-API §5.19). A building both unpaid and idled by Thrift in one absence gets both lines.

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
