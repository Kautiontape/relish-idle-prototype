# Relish Prototypes

Throwaway prototypes exploring mechanics for the Relish idle RPG. Each prototype is independent — own stack, own build, own Dockerfile. They share nothing but the deployment infrastructure (Caddy reverse proxy).

## Current

### Casting (`/casting/`)
Gesture-based rune drawing on canvas to summon minions with randomized behaviors. Tests whether freeform spell-casting feels good as a core interaction. Minions auto-fight enemy waves in timed combat rounds, then survivors get assigned to town buildings for bonuses.

- **Stack:** Vite + TypeScript + HTML Canvas
- **Key question:** Does gesture-casting feel satisfying enough to be the primary player action?
- **Status:** Live

### Horde Scale (`/horde-scale/`)
Visual scale prototype. Hundreds-to-thousands of units on screen using GPU-accelerated rendering. Tests the "particle effect" feel of a massive army — does it feel like growth or visual noise? Explores zoom mechanics (zooming out to make your army tiny but dragons feel "normal" again), unit flocking/grouping, and the saturation problem (Katamari-style "new normal" where scale stops feeling impressive).

- **Stack:** Vite + TypeScript + PixiJS (WebGL)
- **Key question:** Can we make 10,000 units feel meaningfully different from 100 without it becoming noise?
- **Status:** In development

### Quest Loop (`/quest-loop/`)
Tests the bodies-on-the-field summoning loop: enemies die → bodies pile up → cast spells on bodies to raise undead → use those undead to fight harder enemies → repeat until boss. Bodies rot at quest end (no hoarding). Jar limits what you bring home.

- **Stack:** Vite + TypeScript + HTML (no canvas)
- **Key question:** Does "raise now vs wait for better bodies" feel like a meaningful choice?
- **Status:** Tested, findings documented. See `prototypes/quest-loop/FINDINGS.md`
- **Verdict:** Tension exists but choices don't feel impactful enough. Body type distinction too flat. Boss combat needs its own prototype. Spell effectiveness vs enemy tags works well. Collection safety on loss works well.

### Essence Casting (`/essence-casting/`)
Combines gesture-casting with battlefield essence drops. Infinite horde combat — enemies die and drop colored essences (Flesh/Breath/Veil/Chain) that light up matching runes. Swipe between lit runes to cast spells from the full 60-archetype set. PixiJS rendering with flocking undead, top-down enemy flow, Relish as a target.

- **Stack:** Vite + TypeScript + PixiJS (WebGL)
- **Key question:** Does gesture-casting with essence-gating feel good as the core combat loop?
- **Status:** In development
- **Builds on:** Casting (gesture system, archetypes), Horde Scale (PixiJS rendering), Quest Loop (bodies-as-resource insight)

### Raid & Raise (`/raid-and-raise/`)
Full Phase 1 build of the "Raid & Raise" design doc (`prototypes/raid-and-raise/DESIGN.md`). Relish as a conduit: portrait two-thumb input — command grammar (lasso/tap/drag) on one thumb, hold-the-button Trance with least-squares circle scoring on the other. Eight watchable stats, force-field steering (Charm pull / Dread push as nav bias), proximity×size targeting with Wits as the anti-Beef, the sacrifice chain, a 5-chamber authored tomb + Tomb Colossus climax, loot dings (essence/remnants/husks), haul summary, death = total reset. Includes 5 debug playrooms isolating each risky mechanic and a live-tunables debug panel with the §12 RTS-drift telemetry.

- **Stack:** Godot 4.6 (Compatibility renderer, single-threaded web export)
- **Key question:** Does tracing circles in bullet-time feel good enough to be the heart of combat? (Gate: the trance gym playroom. Second gate: a full run fits ~10 minutes and you want another.)
- **Status:** Phase 1 complete — the circle gate passed (it's the heart of the game). Frozen as the playable alpha, tagged `raid-and-raise-v0.0.1`. Phase 2 (the Slab) is its own prototype, not bolted onto this one.

### The Slab (`/slab/`)
Phase 2 of Raid & Raise: the raising screen, as its own prototype with the raid faked. The crypt where Relish woke — a central slab where you place a form (husk), its rune slots bloom by anatomy, you slot remnants and the creature **morphs live** (one stat, one watchable verb) while its **Adjective Noun** name forms above it ("Frenzied Skeleton"); Raise it and name your new friend. Corner: the **bone pit** — one fullness meter that's also the quality dial (feed scraps with diminishing returns, pull always gives something, output capped below loot), the anti-stalemate floor so you never hit zero undead. Corner: **Vei's statue** (placeholder nemesis). Jar/town/persistence deferred.

- **Stack:** Godot 4.6 (Compatibility renderer, single-threaded web export)
- **Key question:** Does building a creature from a form + remnants feel like making something that's *yours* (the morph + the name + naming it)? Plus: does the bone-pit floor feel good?
- **Status:** In development. Build-expression loop + ossuary working; raid faked, economy deferred.
- **Builds on:** Raid & Raise (loot tables, stat/anatomy shapes, creature-visual language — copied, not shared)

## Separate

### Relish Idle (separate repo: `relish-idle`)
Tick-based idle RPG with deep mechanics: ritual system, incantations, component-assembly undead (Form + Core + Augment), buildings with jobs, quest state machine. Lives in its own repo — not a throwaway prototype, more of a full game build.

- **Stack:** SvelteKit 2 + TypeScript + Tailwind
- **Key question:** Can idle progression carry the town/empire management loop without real-time combat?

## Pending

### Town Manager
Focused prototype for the building/job assignment loop. How does it feel to assign minions to jobs, upgrade buildings, and watch passive resource generation? Strips away combat to isolate whether town management is engaging on its own.

- **Key question:** Is the town loop fun without combat pressure?

### New Town
Starting a new town with entirely different challenges/constraints. The "prestige" alternative — you don't reset, you expand. Like Factorio Space Age: new world, new rules, you bring some resources but the challenge is so different you WANT to rebuild. Tests whether horizontal expansion feels better than vertical prestige.

- **Key question:** Does starting fresh with new constraints feel like growth or punishment?

### Boss Encounters
How does a horde fight a single massive enemy? Quest-loop testing showed that bosses using the same combat math as waves always feel wrong — either they crumple or they devour everything. Bosses need their own mechanic. Possible angles: phases (boss changes behavior as HP drops), weak points (specific undead types deal bonus damage), "last chance" moment before the boss where you go all-in on summoning, boss attacks that target groups rather than individuals, a body-economy where the boss itself drops mid-fight materials.

- **Key question:** Can army-vs-boss combat feel strategic and dramatic rather than "same combat but more HP"?
- **Informed by:** Quest-loop prototype findings — boss as "just a strong enemy" doesn't work

### Quest Challenges
Quests with unique constraints that require special builds or strategies. Not just "fight harder enemies" but "this quest is underwater so only aquatic undead work" or "this quest has anti-magic zones so spell-summoned minions die." Tests build diversity.

- **Key question:** Do build constraints create interesting choices or just frustrating gatekeeping?

### Quest System
Quest state machine and narrative progression. Branching choices, multi-stage quests with different encounter types (narrative, combat, choice, reward). Tests whether structured questing adds meaningful variety to the idle loop.

- **Key question:** Do quests feel like real decisions or just "click through to get rewards"?
