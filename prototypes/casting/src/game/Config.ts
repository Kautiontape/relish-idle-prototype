// Game configuration - all tweakable numbers in one place

export const Config = {
  // Combat Phase
  COMBAT: {
    DURATION: 60000, // 30 seconds per quest
    ENEMY_SPAWN_INTERVAL: 2000, // Spawn enemy every 2 seconds
    ENEMY_SPAWN_Y: 50, // Y position where enemies spawn (top of screen)
  },

  // Player
  PLAYER: {
    X: 0.5, // Relative position (0-1) of screen width
    Y: 0.85, // Relative position (0-1) of screen height
    SIZE: 20, // Size in pixels
    COLOR: '#4a9eff',
    SUMMON_COOLDOWN: 0.5, // Cooldown between summons
    CAST_TIME: 0.8, // Time to hold to complete summon
  },

  // Minions
  MINION: {
    BASE_COUNT: 10, // Starting number of minions
    SIZE: 6, // Base size in pixels
    SIZE_VARIANCE: 2, // +/- variance
    SPEED: 120, // Base pixels per second
    SPEED_VARIANCE: 40, // +/- variance
    COLOR: '#8fbc8f',
    ATTACK_RANGE: 10, // Distance at which they can attack
    DAMAGE: 5, // Base damage per attack
    DAMAGE_VARIANCE: 2, // +/- variance
    ATTACK_SPEED: 0.5, // Attacks per second
    BASE_HEALTH: 20, // Base health per minion
    HEALTH_VARIANCE: 5, // +/- variance
    HIT_CHANCE: 0.85, // Base 85% hit chance
    HIT_CHANCE_VARIANCE: 0.15, // +/- 15% variance (70-100%)
  },

  // Enemies
  ENEMY: {
    BASE_HEALTH: 50,
    SIZE: 15,
    SPEED: 30, // Move toward player speed
    COLOR: '#ff4444',
    HEALTH_BAR_HEIGHT: 3,
    DAMAGE: 8, // Damage to minions
    ATTACK_SPEED: 0.3, // Attacks per second
    ATTACK_RANGE: 10, // Distance at which they can attack
    BONE_DROP_CHANCE: 0.4, // 40% chance to drop bones
    BONES_PER_DROP: 1, // How many bones drop
  },

  // Buildings & Jobs
  TOWN: {
    BUILDINGS: [
      {
        id: 'smithy',
        name: 'Smithy',
        jobs: [
          { id: 'forge', name: 'Forge Weapons', desc: '+10% minion damage', slots: 1, bonus: { type: 'damage', value: 0.1 } },
          { id: 'armor', name: 'Craft Armor', desc: '+5% minion speed', slots: 2, bonus: { type: 'speed', value: 0.05 } },
          { id: 'enchant', name: 'Enchant Gear', desc: '+15% minion damage', slots: 3, bonus: { type: 'damage', value: 0.15 } },
        ],
      },
      {
        id: 'crypt',
        name: 'Crypt',
        jobs: [
          { id: 'raise', name: 'Raise Dead', desc: '+2 minions', slots: 1, bonus: { type: 'minions', value: 2 } },
          { id: 'animate', name: 'Animate Corpses', desc: '+4 minions', slots: 2, bonus: { type: 'minions', value: 4 } },
          { id: 'ritual', name: 'Dark Ritual', desc: '+8 minions', slots: 3, bonus: { type: 'minions', value: 8 } },
        ],
      },
      {
        id: 'inn',
        name: 'Inn',
        jobs: [
          { id: 'serve', name: 'Serve Drinks', desc: '+10 gold', slots: 1, bonus: { type: 'gold', value: 10 } },
          { id: 'entertain', name: 'Entertain Guests', desc: '+25 gold', slots: 2, bonus: { type: 'gold', value: 25 } },
          { id: 'manage', name: 'Manage Inn', desc: '+50 gold', slots: 3, bonus: { type: 'gold', value: 50 } },
        ],
      },
    ],
  },

  // Rewards
  REWARDS: {
    GOLD_PER_ENEMY: 5,
    BASE_ENEMY_REWARD: 1, // Base enemies killed per quest completion
  },

  // Ritual
  RITUAL: {
    BONE_COST: 3, // Bones needed per ritual
    MINIONS_GAINED: 1, // Minions created per ritual
  },
  // Spell casting
  SPELL: {
    RUNE_HIT_RADIUS: 40,
    MIN_RUNES: 2,
    COOLDOWN: 0.5,
    INCANTATION_DISPLAY_TIME: 3.0,
  },
} as const;
