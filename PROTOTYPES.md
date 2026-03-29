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
