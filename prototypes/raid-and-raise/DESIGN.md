# RELISH — Raid & Raise Prototype (working title)
### Design document for Claude Code · Godot 4.x · Greenfield

---

## 0. How to read this document

This is a **final-state specification**. Every decision in it survived design review; there is no archaeology to do and no alternatives to weigh. Where a value is a number, it is a **first-pass tuning value** and must live in a JSON config, never hardcoded. Where a rule sounds absolute ("never," "always"), it is a design invariant — do not soften it for implementation convenience without flagging it.

Build **Phase 1 before Phase 2**, in the step order in §12, respecting the gates. Step 1 exists to be killed cheaply if it fails. Do not build anything in §14 (the earmark ledger).

---

## 1. Project setup

- **Engine:** Godot 4.x, **Compatibility renderer** (web + mobile export targets).
- **Orientation:** Portrait. Base viewport 720×1280, canvas stretch mode suited to phones.
- **Greenfield project.** Two patterns are carried over *by hand* from a prior prototype as reference, not imported code:
  1. Data-driven entities: one JSON file per entity type in a config folder, discovered at startup by an autoload registry.
  2. `CharacterBody2D` + `NavigationAgent2D` movement with avoidance enabled; corpses render on a layer beneath living units.
- **One entity code path.** Relish, permanent undead, chaff, and enemies are all the same entity class, differing only by config and faction. No special-cased combat logic per faction.

Suggested structure:

```
/configs
  stats.json        # all coefficients in §11
  timers.json
  circle.json
  rarity.json
  echoes.json
  /husks/*.json
  /enemies/*.json
  /chambers/*.json
/systems            # entity_factory, force_field, trance, command, raid_director, slab
/scenes
/ui
```

---

## 2. The fantasy, one paragraph

Relish is a necromancer who fears death. She raids tombs not as a warrior but as a **conduit**: her army is her weapon, her shield, and her health bar. The dead she raises are also the treasure — bodies are the loot. Play alternates between a fast, flow-state **Raid** and a slow, deliberate **Raising** between raids. Preparation beats reflexes. And the moral of the game is absolute: **if Relish dies, everything is lost.**

---

## 3. Canonical vocabulary

Use these names in code, configs, and UI. Functional names are intentional; flavor renaming is earmarked.

| Term | Meaning |
|---|---|
| **Aspect** | One of four stat domains: **Muscle, Nerve, Presence, Anima**. |
| **Husk** | A creature chassis. Carries no growth stats — only an Anatomy, a cadence, and tiny base defaults. |
| **Anatomy** | A husk's identity: a free 4-vector of Hollow counts by Aspect, e.g. Skeleton `1/2/0/0` (Mu/Ne/Pr/An). Zeros are legal. |
| **Hollow** | An empty slot in a husk, typed by Aspect. |
| **Remnant** | A lootable component. One primary stat at a rolled magnitude, plus Echoes. Fits any Hollow of its parent Aspect. |
| **Echo** | A secondary trait on a remnant, strictly tagged **combat** or **town**. Drawn from one shared budget per remnant. |
| **Essence** | Drops from corpses. Ammo for circle-summoning chaff. |
| **Chaff** | Ephemeral circle-summoned units. Dissolve when the raid ends. |
| **Permanent** | A raised creature (Husk + slotted Remnants). Dies for real. |
| **Soul Jar** | Fixed travel slots. Caps what you bring out and what you carry home. Home roster is unlimited. |
| **The Slab** | The raising screen (Phase 2). |
| **Trance** | Summoning mode while the corner button is held. |
| **Mutation** | Qualitative rule-changer. **Earmarked — do not build.** Stats are fields; mutations are moments. |

---

## 4. The loop

**Raid (fast, active):** Load the Jar with permanents. Enter a tomb of connected chambers. Default thumb state is *command*; holding the corner button enters the *Trance* to circle-summon chaff from essence. Kills drop essence; remnants and husks ding off bodies mid-fight. Relish takes a hit → an undead dies in her place. Chambers chain to a climax. **Phase 1 climax: kill the boss** (it showers loot).

**Raising (slow, deliberate — Phase 2):** The haul is laid out. On the Slab, build permanents from husks and remnants, salvage junk into material (**luck sets pace, never ceiling**), and choose what fits in the Jar for the trip home. Home roster generates a town income stub.

One full loop is a **~10-minute sitting**: raid 5–8 min, raising 2–3. That sitting *is* the couch test.

---

## 5. The eight stats — one watchable verb each

A stat exists only if you can see it working in a crowd. Each stat is **one fictional truth** expressed in combat and (Phase 2) in town.

| Aspect | Stat | Combat verb — what you watch | Town echo (Phase 2 stub) |
|---|---|---|---|
| Muscle | **Power** | Strikes hard. Enemies die in chunks. | Haul rate, heavy output |
| Muscle | **Beef** | Immovable mass. HP, knockback resistance, **physical size** — and size is what enemies magnet onto. | Works the brutal jobs |
| Nerve | **Speed** | Quick. **Movement only.** Sheds aggro by never being the closest thing. | Task completion rate |
| Nerve | **Wits** | The killer's eye. Locks the **highest-Beef enemy**, sticks until it's down, deals bonus damage scaling with the target's Beef. **Wits is the anti-Beef.** | Runs complex jobs solo |
| Presence | **Charm** | **Pull.** An attraction field — enemies drift toward it, bending their paths. The lure. | Pulls customers, foot traffic |
| Presence | **Dread** | **Push.** A repulsion field — enemies give ground, can't close. The bodyguard / sheepdog. | Security, deters trouble |
| Anima | **Magic** | Grants a ranged bolt; scales its damage. Bolts flying. | Enchanting output |
| Anima | **Persistence** | Won't stay dead. On death, a chance to rise again — **once per chamber**, at partial HP. | Works without rest |

**Rules that complete the model:**

- **Attack cadence is a husk property, not a stat.** A body's natural rhythm, in the husk JSON.
- **Default enemy targeting = proximity × size.** Enemies swing at the biggest, closest mass. Beef self-tanks; no aggro stat exists.
- **Presence fields bias *movement*, never disable *combat*.** An enemy lured to the siren still fights whatever is in its face on arrival. No stuns, no disarms from stats.
- **Player commands override fields** while active. Input feel is sacrosanct: command responsiveness is uniform for every unit. Wits governs what units do when you are *not* steering — including holding a commanded position instead of drifting back to autopilot (high Wits holds; low Wits drifts).
- **Enemies use the same eight stats and the same code path.** Enemy Dread is rare elite flavor, not baseline.
- **Chaff get three stats only:** Power / Beef / Speed, scaled by circle accuracy. No Presence, no Wits, no Anima, never rise, dissolve at raid end. The gap between a chaff blob and a raised permanent is the felt value of the Raising phase — do not "improve" chaff.
- **Relish never attacks.** She is the conduit; her contribution is the circle and the commands.

---

## 6. Movement model — the force field

Enemy (and idle-minion) steering is a **vector sum**, applied as a bias on top of `NavigationAgent2D` pathing:

```
steer = nav_velocity
      + Σ attraction(target mass)        # proximity × size targeting
      + Σ k_charm × Charm_i / d_i        # toward charming units, within radius
      − Σ k_dread × Dread_i / d_i        # away from dreadful units, within radius
```

- Forces are **steering biases, never hard displacement** (clamp total bias ≤ 40% of the agent's max speed) — this keeps NavigationAgent2D stable in corridors.
- Stat values are literally the force coefficients; that is why every slider value is visible.
- Emergent behaviors to expect, all correct: swarms magnet onto the Beef wall; charming units lure enemies into grinders (and into danger — bait is supposed to be dangerous); dread units wall enemies off Relish or herd packs; an all-Dread melee squad pushes its own targets out of reach (legible self-sabotage, not a bug).

---

## 7. Creatures

### 7.1 Husks

A husk JSON defines: `anatomy` (Mu/Ne/Pr/An hollow counts — zeros legal), `cadence` (attacks/sec), and the universal **dead-flesh defaults** (tiny base statline so a zero-aspect creature still shambles, swings, and exists; all *growth* comes from remnants).

Starter table (first-pass values; husks drop in Phase 1, get used in Phase 2):

| Husk | Anatomy (Mu/Ne/Pr/An) | Cadence | Notes |
|---|---|---|---|
| Skeleton | 1/2/0/0 | 1.0 | cheap baseline |
| Zombie | 2/0/0/0 | 0.6 | dumb meat |
| Hulk | 3/1/0/0 | 0.5 | the wall frame |
| Siren | 0/1/3/0 | 0.8 | presence platform |
| Lich | 0/3/0/1 | 0.9 | the killer's eye frame |
| Wraith | 0/1/2/1 | 1.1 | fast, eerie |
| Revenant | 2/0/1/2 | 0.7 | won't stay dead |

Visual size scales with total Beef (see §11) — Beef must be *seen*.

### 7.2 Remnants

A remnant = **one primary stat** (one of the eight) at a rolled magnitude, **plus Echoes from one shared budget.**

- **Rarity sets the budget's size; the roll sets its allocation.** Most rolls lean heavily combat-side or town-side — that lean is the specialist identity and the Slab decision. A high-rarity remnant rolled *evenly* at high magnitude is the all-rounder jackpot: rare outcome of the same system, never the default property of rarity.
- **Echoes are strictly one-sided** (combat-tagged or town-tagged) for this prototype.
- A drop is never wrong-by-type: a Power remnant is always Power. Variance lives in magnitude and echo allocation only.
- Reroll (re-allocating a fixed budget) and Mutations (off-budget rule-changers) are **earmarked — do not build.**

Starter echoes (effects are config values):

- **Combat:** Life Drain (heal % of damage dealt), Frenzy (+cadence below 50% HP), Heavy Blow (+knockback), Volatile (explodes on death), Vengeful (+damage for 5s after an ally dies).
- **Town:** Organization, Salesmanship, Tireless, Frugal, Crafty — each contributes income points to the Phase 2 stub.

### 7.3 Chaff

Spawned only by circles. Stats = chaff base × accuracy multiplier (§11). Run-at-nearest-and-hit AI. They are the first bodies sacrificed for Relish.

---

## 8. Input specification (portrait, two thumbs)

One corner button (side configurable for handedness, `timers.json: button_side`). Everything else is the touchscreen.

### 8.1 Default state — Command

| Gesture | Effect |
|---|---|
| Closed loop drawn over friendly undead | **Lasso** — selects the group |
| Tap (with an active selection) | Send the group to that point; selection clears |
| Tap (no selection) | Move Relish to that point |
| Stroke starting on Relish | Drag her path directly |
| — | Selection expires 2s after lasso if unused |

Coarse commands only: group-and-point. **No unit micro, ever.** One grammar runs both modes: **encircle to claim** — circle minions to command them, circle essence (in Trance) to raise it.

### 8.2 Trance — hold the button

1. **Hold:** world time dilates (×0.35), screen desaturates, essence ignites/glows, trace color changes, audio muffles under a heartbeat. Unmistakable mode state.
2. **Trace a circle** over the battlefield around glowing essence.
3. **Score the trace:** least-squares circle fit; score 0–100 from mean radial deviation + closure quality. **Feedback is mandatory:** flash the fitted ideal ring against the player's actual trace, with a grade, for a beat. The player must see *why* 73 was 73.
4. **Summon:** every essence enclosed becomes one chaff; the accuracy score sets their stat multiplier. Big sloppy circle = many weak idiots; small perfect circle = one or two strong ones. This is the recurring skill choice.
5. **Completing a summon ends the Trance** (snap back to full speed); the button starts its cooldown, shown as a radial fill on the button itself.
6. A **focus meter** caps any single hold at 4s — no trance camping.

Essence decays in **world time** (dilated time slows decay), lifetime comfortably above the cooldown, so timing kills near a trance window is skill, never theft.

### 8.3 Relish, sacrifice, and death

- Relish **auto-advances** between chambers and runs cowardly kiting AI in combat; player overrides via §8.1.
- **Sacrifice chain:** when Relish is hit — the nearest chaff dies in her place → if no chaff, the nearest **permanent** dies (with a loud, unmissable warning state when chaff run out) → if nothing remains to die for her, **Relish dies.**
- A sacrificed permanent with Persistence may still rise (once per chamber) — keep this interaction; it is already paid for.
- **Relish's death is total: the run, the haul, the Jar, the home roster, the save — everything. Fresh start. That's the moral.** Implement as a single deletion path so it stays one config flag if it ever needs softening. (Phase 1, pre-persistence: death = run-over screen + full reset.)

---

## 9. Raid structure (Phase 1)

- **One authored tomb** for v1: 5 chambers + climax, defined in `/configs/chambers/`. Procedural generation earmarked.
- Chambers are doorway-connected rooms with **generous doorways** (swarm pathing through pinches is the known NavigationAgent2D failure mode).
- **Fixed camera framing each chamber. No pinch zoom. No line of sight.**
- Counts: 5–15 enemies per chamber, 20–30 at the climax; chaff on field 10–40. ("Hundreds of undead" is honored cumulatively across the raid, not per frame.)
- **Drops:** every kill yields 1+ essence (bigger enemies weighted higher); remnants ding off kills by rarity table (elites guaranteed); husks come from elites, sarcophagi (1–2 interactable per chamber), and the boss.
- **Climax v1 = KILL.** A boss fight; the boss showers remnants + a large essence burst. (*Bind* — taking the boss's husk home in a Jar slot — arrives in Phase 2, because binding pays into a Jar that doesn't exist until the Slab does. *Loot/hoard* variant earmarked.)
- **Raid end (Phase 1):** a haul summary screen — remnants, husks, essence stats, circle-score history. This is the placeholder until the Slab exists.
- Starter enemy archetypes (configs): Tomb Rat (small, fast), Guard (baseline), Brute (high Beef, visibly huge), Cultist Archer (ranged), Elite Sentinel (rare, Dread aura), Boss: Tomb Colossus (massive Beef + Power).

---

## 10. Phase 2 — The Slab, the Jar, the economy

Build only after the Phase 1 gate passes.

- **Slab UX:** inventory of husks → drag one to a center square → its hollows bloom in a ring around it with aspect icons → tap a hollow → filterable remnant list → tap to slot. **The creature preview visibly morphs as remnants slot** (identity-emerges-from-build, made literal). A **twin bar** (combat lean / town lean) updates per slot so the Jar decision is previewed while building. **Raise** button gets the flourish — it is the authored counterpart of the raid's gacha ding.
- **Soul Jar:** fixed slots (start: 5). Travel-only — outbound it holds the raid loadout; inbound it caps what finished creatures come home. Home roster unlimited.
- **Permanents die for real.** Full loss; Persistence is the hedge stat. No recovery mechanics.
- **Salvage:** unwanted remnants break down into material that crafts toward desired remnants. Luck sets pace, never ceiling.
- **Town stub:** a single income-per-minute computed from the home roster, displayed on the Slab so the twin bars mean something: `income/min = Σ over roster (0.1 × Σ primary magnitudes + 0.5 × town echo points)`.
- **Bind** added as the climax alternative: spend a Jar slot, take the boss's husk home.
- Save persistence arrives with Phase 2 — and with it, the total-wipe rule of §8.3 applies to the save.

---

## 11. First-pass numbers — all in `/configs`, none hardcoded

| Constant | Value |
|---|---|
| Jar slots | 5 |
| Trance time scale | 0.35 |
| Trance max hold | 4.0 s |
| Summon cooldown | 6.0 s |
| Essence lifetime (world time) | 12 s |
| Selection expiry | 2 s |
| Circle score → chaff multiplier | 0.5 + score/100 (range 0.5×–1.5×) |
| Chaff base (P/B/S) | 2 / 2 / 3, × multiplier |
| HP | base_hp + 10 × Beef |
| Damage per hit | base_dmg + 2 × Power |
| Move speed | base_speed + 12 × Speed (px/s) |
| Dead-flesh defaults (every husk) | base_hp 20, base_dmg 2, base_speed 60 |
| Visual/targeting size | 1 + 0.15 × Beef |
| Targeting score | size / distance (highest wins) |
| Wits behavior threshold | Wits ≥ 3 → lock highest-Beef enemy, stick until dead; below → nearest-target |
| Wits anti-Beef bonus | damage × (1 + 0.03 × Wits × target Beef) |
| Charm/Dread field | radius 250 px, F = 14 × stat / d, bias clamp 40% max speed |
| Magic bolt | damage 1.5 × Magic, range 300 px, fires at husk cadence; **tune bolt DPS ≈ 0.8 × melee DPS at equal investment** |
| Persistence rise | chance min(0.9, 0.08 × Persistence), once/chamber, revive at 50% HP |
| Sacrifice i-frames | 0.5 s |
| Remnant drop chance / kill | 18% (elites 100%, boss 3–5 guaranteed) |
| Rarity weights C/U/R/L | 70 / 22 / 7 / 1 |
| Magnitude by rarity | 1–3 / 2–5 / 4–8 / 7–12 |
| Echo budget by rarity | 2 / 4 / 7 / 12 |
| Husk drops | elite 35%, sarcophagus 60%, boss 100% |

---

## 12. Build order and gates

**Phase 1 — prove the fight.**

- **Step 0 — Scaffold.** Portrait project, Compatibility renderer, config autoload + entity factory, one gray room.
- **Step 1 — The circle, alone.** Trance button, bullet time, dummy essence, trace capture, least-squares scoring, fitted-ring feedback, chaff spawn. **GATE: does tracing circles feel good in isolation?** If not, the design fails here, cheaply. Do not proceed to mask a bad core feel with content.
- **Step 2 — One chamber.** Enemies with force-field steering and proximity×size targeting; full eight-stat combat resolution; command grammar; Relish AI + sacrifice chain; loot dings.
- **Step 3 — The full tomb.** 5 chambers + boss kill, haul summary screen, death = total reset. **GATE (the couch test): a full run fits in ~10 minutes and you want another one.**

**Phase 2 — prove the loop** (only after both gates): remnant generation with echo budgets → the Slab → Jar + outbound loadout → salvage → town income stub → bind option → save persistence (with total-wipe).

**Debug overlay (build in Step 2, it guards a kill criterion):** per-raid counts of command touches vs. trance summons, plus a circle-score histogram. If command touches dominate by ~8:1, the game is drifting RTS — the circle must stay the heart of play. Surface the ratio; a human decides.

---

## 13. Tuning landmines — content rules, written down now

1. **Difficulty must vary enemy *composition*, not just inflate Beef** — otherwise Wits (the anti-Beef) becomes mandatory and the counter-web collapses. The web: Wits answers giants, Charm answers numbers, Dread answers enemy DPS, Beef absorbs, Power deletes, Speed outruns.
2. **Ranged must not dominate:** keep Magic's DPS below melee at equal investment; Anima hollows are scarce in content anyway.
3. **Doorways generous,** push forces as steering bias only — both protect NavigationAgent2D.
4. **Minion auto-behavior must be good enough that commands are optimization, not maintenance.** If players must micromanage, the conduit fantasy dies.
5. **Essence lifetime stays comfortably above the summon cooldown** or the game eats the player's kills.
6. **No healing exists.** The dead don't heal; Persistence is the necromantic answer to sustain. Flavor commitment, hold it.

---

## 14. Do not build (earmark ledger)

Mutations (stats are fields; mutations are moments) · essence-typed spell-casting interface · remnant reroll · Anima-hollow ascension on mundane husks · Jar slot growth · flavor renaming of stats/aspects · loot/hoard climax variant · the full idle town (only the income stub exists) · minion micro beyond group-and-point · a "rally" gesture (contingency only, if swarms derp in testing) · line of sight · camera zoom · procedural tomb generation · meta-progression around death beyond the total wipe.

---

## 15. Design invariants — the tiebreakers

When implementation forces a choice this document doesn't cover, resolve it with these, in order:

1. **One stat = one watchable verb.** If a mechanic can't be seen working in a crowd, it doesn't ship.
2. **Input feel is sacrosanct.** Nothing — no stat, no state — degrades command responsiveness.
3. **Fields bias movement; they never disable combat.**
4. **Luck sets pace, never ceiling.**
5. **Identity emerges from the build,** not from the drop.
6. **Relish is the conduit, not a commander and not a fighter.**
7. **The thumb belongs to the circle.** Any feature competing for it loses.
