# Relish Prototypes

Throwaway prototypes exploring mechanics for the Relish idle RPG. Each prototype is independent — own stack, own build, own Dockerfile. They share nothing but the deployment infrastructure (Caddy reverse proxy).

## Current

### Casting (`/casting/`)
Gesture-based rune drawing on canvas to summon minions with randomized behaviors. Tests whether freeform spell-casting feels good as a core interaction. Minions auto-fight enemy waves in timed combat rounds, then survivors get assigned to town buildings for bonuses.

- **Stack:** Vite + TypeScript + HTML Canvas
- **Key question:** Does gesture-casting feel satisfying enough to be the primary player action?
- **Status:** Live

## Separate

### Relish Idle (separate repo: `relish-idle`)
Tick-based idle RPG with deep mechanics: ritual system, incantations, component-assembly undead (Form + Core + Augment), buildings with jobs, quest state machine. Lives in its own repo — not a throwaway prototype, more of a full game build.

- **Stack:** SvelteKit 2 + TypeScript + Tailwind
- **Key question:** Can idle progression carry the town/empire management loop without real-time combat?

## Pending

### Town Manager
Focused prototype for the building/job assignment loop. How does it feel to assign minions to jobs, upgrade buildings, and watch passive resource generation? Strips away combat to isolate whether town management is engaging on its own.

- **Key question:** Is the town loop fun without combat pressure?

### Giant Horde
Massive minion swarm combat. Thousands of minions on screen, emergent behavior from simple rules. Tests whether the "exponentially growing army" fantasy translates to satisfying visuals and gameplay at scale.

- **Key question:** Does huge scale feel meaningfully different from small scale, or is it just visual noise?

### Quest System
Quest state machine and narrative progression. Branching choices, multi-stage quests with different encounter types (narrative, combat, choice, reward). Tests whether structured questing adds meaningful variety to the idle loop.

- **Key question:** Do quests feel like real decisions or just "click through to get rewards"?
