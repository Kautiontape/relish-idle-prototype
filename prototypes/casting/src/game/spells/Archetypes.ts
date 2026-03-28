import type { RuneId } from './Runes';

export type BehaviorTag =
  | { type: 'life_steal'; percent: number }
  | { type: 'regen'; hpPerSecond: number }
  | { type: 'fortified'; damageReduction: number }
  | { type: 'dodge'; chance: number }
  | { type: 'ambush'; damageMultiplier: number }
  | { type: 'slow_on_hit'; percent: number; duration: number }
  | { type: 'root_on_hit'; duration: number }
  | { type: 'aoe_slow'; radius: number; percent: number }
  | { type: 'phase' }
  | { type: 'stationary' }
  | { type: 'life_tether'; dps: number }
  | { type: 'rage'; maxAttackSpeedBonus: number }
  | { type: 'devour'; healPercent: number; damageBuff: number; buffDuration: number }
  | { type: 'aura_ally_buff'; radius: number; damageBuff: number }
  | { type: 'aura_enemy_debuff'; radius: number; attackSpeedReduction: number }
  | { type: 'death_explode'; radius: number; damage: number }
  | { type: 'spawn_minions'; interval: number; minionType: string }
  | { type: 'resurrect_nearby'; radius: number; cooldown: number }
  | { type: 'scaling_on_kill'; damagePerKill: number }
  | { type: 'teleport_attack' }
  | { type: 'decoy_on_hit'; decoyHP: number }
  | { type: 'knockback'; distance: number }
  | { type: 'damage_aura'; radius: number; dps: number }
  | { type: 'protection_aura'; radius: number; reduction: number }
  | { type: 'taunt'; radius: number }
  | { type: 'miss_aura'; radius: number; chance: number }
  | { type: 'invulnerable_on_spawn'; duration: number };

export interface ArchetypeDefinition {
  id: string;
  name: string;
  description: string;
  runeSequence: RuneId[];
  incantation: string;
  stats: {
    health: number;
    damage: number;
    speed: number;
    size: number;
  };
  color: string;
  lifespan?: number;
  behaviors: BehaviorTag[];
}

function makeKey(seq: RuneId[]): string {
  return seq.join(',');
}

const ARCHETYPES: ArchetypeDefinition[] = [
  // ============================================================
  // 2-RUNE ARCHETYPES (12)
  // ============================================================
  {
    id: 'revenant',
    name: 'Revenant',
    description: 'Raised warrior burning with fading life.',
    runeSequence: ['breath', 'flesh'],
    incantation: 'By breath... Of flesh...',
    stats: { health: 1.0, damage: 1.0, speed: 1.0, size: 1.0 },
    color: '#b85c3a',
    behaviors: [{ type: 'rage', maxAttackSpeedBonus: 1.5 }],
  },
  {
    id: 'soul_shackle',
    name: 'Soul Shackle',
    description: 'Spectral chains that leash life from the living.',
    runeSequence: ['breath', 'chain'],
    incantation: 'By breath... In chains...',
    stats: { health: 0.7, damage: 0.6, speed: 0.8, size: 0.8 },
    color: '#5a9e8f',
    behaviors: [{ type: 'life_tether', dps: 3 }],
  },
  {
    id: 'whisper',
    name: 'Whisper',
    description: 'A murmur of death that saps the will to fight.',
    runeSequence: ['breath', 'veil'],
    incantation: 'By breath... Through veil...',
    stats: { health: 0.5, damage: 0.3, speed: 1.3, size: 0.6 },
    color: '#6b7fa3',
    behaviors: [{ type: 'aura_enemy_debuff', radius: 60, attackSpeedReduction: 0.4 }],
  },
  {
    id: 'ghoul',
    name: 'Ghoul',
    description: 'Ravenous corpse that feeds on the fallen.',
    runeSequence: ['flesh', 'breath'],
    incantation: 'Of flesh... By breath...',
    stats: { health: 1.2, damage: 1.3, speed: 1.1, size: 1.1 },
    color: '#6b8a3a',
    behaviors: [{ type: 'devour', healPercent: 0.3, damageBuff: 0.5, buffDuration: 5 }],
  },
  {
    id: 'bone_construct',
    name: 'Bone Construct',
    description: 'Dense skeleton bound in rigid formation.',
    runeSequence: ['flesh', 'chain'],
    incantation: 'Of flesh... In chains...',
    stats: { health: 2.0, damage: 0.5, speed: 0.5, size: 1.5 },
    color: '#d4c9a8',
    behaviors: [{ type: 'fortified', damageReduction: 0.5 }],
  },
  {
    id: 'lurker',
    name: 'Lurker',
    description: 'Dead flesh cloaked in shadow. Strikes unseen.',
    runeSequence: ['flesh', 'veil'],
    incantation: 'Of flesh... Through veil...',
    stats: { health: 0.6, damage: 1.5, speed: 1.4, size: 0.8 },
    color: '#3a3a5c',
    behaviors: [{ type: 'ambush', damageMultiplier: 3 }],
  },
  {
    id: 'life_leech',
    name: 'Life Leech',
    description: 'Parasitic tether that feeds all nearby dead.',
    runeSequence: ['chain', 'breath'],
    incantation: 'In chains... By breath...',
    stats: { health: 0.8, damage: 0.7, speed: 0.7, size: 0.8 },
    color: '#8a5c5c',
    behaviors: [
      { type: 'life_steal', percent: 0.3 },
      { type: 'aura_ally_buff', radius: 50, damageBuff: 0.1 },
    ],
  },
  {
    id: 'bone_wall',
    name: 'Bone Wall',
    description: 'Immovable rampart of fused bone.',
    runeSequence: ['chain', 'flesh'],
    incantation: 'In chains... Of flesh...',
    stats: { health: 3.0, damage: 0.0, speed: 0.0, size: 2.0 },
    color: '#c9b896',
    behaviors: [
      { type: 'stationary' },
      { type: 'taunt', radius: 80 },
    ],
  },
  {
    id: 'shadow_snare',
    name: 'Shadow Snare',
    description: 'Invisible chains that slow all who pass.',
    runeSequence: ['chain', 'veil'],
    incantation: 'In chains... Through veil...',
    stats: { health: 0.6, damage: 0.0, speed: 0.9, size: 0.7 },
    color: '#5c4a6b',
    behaviors: [{ type: 'aoe_slow', radius: 70, percent: 0.4 }],
  },
  {
    id: 'shade',
    name: 'Shade',
    description: 'Swift ghost that phases through the battlefield.',
    runeSequence: ['veil', 'breath'],
    incantation: 'Through veil... By breath...',
    stats: { health: 0.5, damage: 0.8, speed: 1.6, size: 0.7 },
    color: '#4a6b8a',
    behaviors: [
      { type: 'teleport_attack' },
      { type: 'phase' },
    ],
  },
  {
    id: 'doppelganger',
    name: 'Doppelganger',
    description: 'Mimicking form that confuses the living.',
    runeSequence: ['veil', 'flesh'],
    incantation: 'Through veil... Of flesh...',
    stats: { health: 0.8, damage: 0.8, speed: 1.0, size: 1.0 },
    color: '#7a6b8a',
    behaviors: [{ type: 'decoy_on_hit', decoyHP: 10 }],
  },
  {
    id: 'soul_anchor',
    name: 'Soul Anchor',
    description: 'Spirit that pins the living in place.',
    runeSequence: ['veil', 'chain'],
    incantation: 'Through veil... In chains...',
    stats: { health: 0.7, damage: 0.6, speed: 0.8, size: 0.8 },
    color: '#6b5c8a',
    behaviors: [{ type: 'root_on_hit', duration: 2 }],
  },

  // ============================================================
  // 3-RUNE ARCHETYPES (24)
  // ============================================================

  // BREATH-first
  {
    id: 'iron_revenant',
    name: 'Iron Revenant',
    description: 'Armored warrior that fights harder as it falls.',
    runeSequence: ['breath', 'flesh', 'chain'],
    incantation: 'By breath... Of flesh... In chains...',
    stats: { health: 1.5, damage: 1.0, speed: 0.8, size: 1.3 },
    color: '#8a6b4a',
    behaviors: [
      { type: 'rage', maxAttackSpeedBonus: 1.5 },
      { type: 'fortified', damageReduction: 0.3 },
    ],
  },
  {
    id: 'fading_revenant',
    name: 'Fading Revenant',
    description: 'Phase-shifts between worlds mid-swing.',
    runeSequence: ['breath', 'flesh', 'veil'],
    incantation: 'By breath... Of flesh... Through veil...',
    stats: { health: 0.8, damage: 1.0, speed: 1.1, size: 1.0 },
    color: '#7a5c6b',
    behaviors: [
      { type: 'rage', maxAttackSpeedBonus: 1.5 },
      { type: 'dodge', chance: 0.35 },
    ],
  },
  {
    id: 'sinew_shackle',
    name: 'Sinew Shackle',
    description: 'Corporeal chains made of twisted muscle.',
    runeSequence: ['breath', 'chain', 'flesh'],
    incantation: 'By breath... In chains... Of flesh...',
    stats: { health: 1.2, damage: 0.6, speed: 0.6, size: 1.1 },
    color: '#7a8a6b',
    behaviors: [
      { type: 'life_tether', dps: 3 },
      { type: 'fortified', damageReduction: 0.25 },
    ],
  },
  {
    id: 'spectral_leash',
    name: 'Spectral Leash',
    description: 'Invisible tether draining from the unseen.',
    runeSequence: ['breath', 'chain', 'veil'],
    incantation: 'By breath... In chains... Through veil...',
    stats: { health: 0.6, damage: 0.7, speed: 1.0, size: 0.7 },
    color: '#5a7a8a',
    behaviors: [
      { type: 'life_tether', dps: 3 },
      { type: 'phase' },
    ],
  },
  {
    id: 'manifest_whisper',
    name: 'Manifest Whisper',
    description: 'Whisper given weight and form to block the path.',
    runeSequence: ['breath', 'veil', 'flesh'],
    incantation: 'By breath... Through veil... Of flesh...',
    stats: { health: 0.9, damage: 0.4, speed: 0.8, size: 1.2 },
    color: '#6b7a5c',
    behaviors: [
      { type: 'aura_enemy_debuff', radius: 60, attackSpeedReduction: 0.4 },
      { type: 'taunt', radius: 70 },
    ],
  },
  {
    id: 'binding_whisper',
    name: 'Binding Whisper',
    description: 'Murmur that roots those who hear it.',
    runeSequence: ['breath', 'veil', 'chain'],
    incantation: 'By breath... Through veil... In chains...',
    stats: { health: 0.5, damage: 0.3, speed: 1.0, size: 0.7 },
    color: '#5c6b8a',
    behaviors: [
      { type: 'aura_enemy_debuff', radius: 60, attackSpeedReduction: 0.4 },
      { type: 'root_on_hit', duration: 1.5 },
    ],
  },

  // FLESH-first
  {
    id: 'chained_ghoul',
    name: 'Chained Ghoul',
    description: 'Bound feeder that drags its prey to a halt.',
    runeSequence: ['flesh', 'breath', 'chain'],
    incantation: 'Of flesh... By breath... In chains...',
    stats: { health: 1.3, damage: 1.2, speed: 0.9, size: 1.2 },
    color: '#6b7a4a',
    behaviors: [
      { type: 'devour', healPercent: 0.3, damageBuff: 0.5, buffDuration: 5 },
      { type: 'slow_on_hit', percent: 0.3, duration: 2 },
    ],
  },
  {
    id: 'phantom_ghoul',
    name: 'Phantom Ghoul',
    description: 'Ghoul that feeds from between worlds.',
    runeSequence: ['flesh', 'breath', 'veil'],
    incantation: 'Of flesh... By breath... Through veil...',
    stats: { health: 1.0, damage: 1.3, speed: 1.3, size: 1.0 },
    color: '#5c6b5c',
    behaviors: [
      { type: 'devour', healPercent: 0.3, damageBuff: 0.5, buffDuration: 5 },
      { type: 'phase' },
    ],
  },
  {
    id: 'draining_construct',
    name: 'Draining Construct',
    description: 'Bone fortress that drinks from attackers.',
    runeSequence: ['flesh', 'chain', 'breath'],
    incantation: 'Of flesh... In chains... By breath...',
    stats: { health: 2.2, damage: 0.3, speed: 0.4, size: 1.6 },
    color: '#b8a87a',
    behaviors: [
      { type: 'fortified', damageReduction: 0.5 },
      { type: 'life_steal', percent: 0.4 },
    ],
  },
  {
    id: 'phantom_construct',
    name: 'Phantom Construct',
    description: 'Bone wall that flickers in and out of existence.',
    runeSequence: ['flesh', 'chain', 'veil'],
    incantation: 'Of flesh... In chains... Through veil...',
    stats: { health: 1.8, damage: 0.5, speed: 0.4, size: 1.5 },
    color: '#a89a8a',
    behaviors: [
      { type: 'fortified', damageReduction: 0.4 },
      { type: 'dodge', chance: 0.3 },
    ],
  },
  {
    id: 'vampiric_lurker',
    name: 'Vampiric Lurker',
    description: 'Shadow hunter that drinks deeply from wounds.',
    runeSequence: ['flesh', 'veil', 'breath'],
    incantation: 'Of flesh... Through veil... By breath...',
    stats: { health: 0.7, damage: 1.3, speed: 1.3, size: 0.9 },
    color: '#4a3a4a',
    behaviors: [
      { type: 'ambush', damageMultiplier: 3 },
      { type: 'life_steal', percent: 0.35 },
    ],
  },
  {
    id: 'snaring_lurker',
    name: 'Snaring Lurker',
    description: 'Shadow predator that pins prey before the kill.',
    runeSequence: ['flesh', 'veil', 'chain'],
    incantation: 'Of flesh... Through veil... In chains...',
    stats: { health: 0.6, damage: 1.4, speed: 1.2, size: 0.8 },
    color: '#3a3a4a',
    behaviors: [
      { type: 'ambush', damageMultiplier: 3 },
      { type: 'root_on_hit', duration: 1.5 },
    ],
  },

  // CHAIN-first
  {
    id: 'flesh_leech',
    name: 'Flesh Leech',
    description: 'Heavy parasitic mound that saps life from all it touches.',
    runeSequence: ['chain', 'breath', 'flesh'],
    incantation: 'In chains... By breath... Of flesh...',
    stats: { health: 1.5, damage: 0.6, speed: 0.5, size: 1.3 },
    color: '#8a5a5a',
    behaviors: [
      { type: 'life_steal', percent: 0.3 },
      { type: 'aura_ally_buff', radius: 50, damageBuff: 0.1 },
      { type: 'fortified', damageReduction: 0.2 },
    ],
  },
  {
    id: 'phantom_leech',
    name: 'Phantom Leech',
    description: 'Invisible siphon drifting unseen among enemies.',
    runeSequence: ['chain', 'breath', 'veil'],
    incantation: 'In chains... By breath... Through veil...',
    stats: { health: 0.6, damage: 0.5, speed: 1.0, size: 0.7 },
    color: '#5a6b7a',
    behaviors: [
      { type: 'life_steal', percent: 0.3 },
      { type: 'aura_ally_buff', radius: 50, damageBuff: 0.1 },
      { type: 'phase' },
    ],
  },
  {
    id: 'living_wall',
    name: 'Living Wall',
    description: 'Self-mending barricade of bone and sinew.',
    runeSequence: ['chain', 'flesh', 'breath'],
    incantation: 'In chains... Of flesh... By breath...',
    stats: { health: 3.0, damage: 0.0, speed: 0.0, size: 2.0 },
    color: '#c9b8a0',
    behaviors: [
      { type: 'stationary' },
      { type: 'taunt', radius: 80 },
      { type: 'regen', hpPerSecond: 5 },
    ],
  },
  {
    id: 'flickering_wall',
    name: 'Flickering Wall',
    description: 'Barrier that phases, letting allies through.',
    runeSequence: ['chain', 'flesh', 'veil'],
    incantation: 'In chains... Of flesh... Through veil...',
    stats: { health: 2.5, damage: 0.0, speed: 0.0, size: 1.8 },
    color: '#a0a0b8',
    behaviors: [
      { type: 'stationary' },
      { type: 'taunt', radius: 80 },
      { type: 'dodge', chance: 0.25 },
    ],
  },
  {
    id: 'draining_snare',
    name: 'Draining Snare',
    description: 'Dark zone that weakens and drains trespassers.',
    runeSequence: ['chain', 'veil', 'breath'],
    incantation: 'In chains... Through veil... By breath...',
    stats: { health: 0.7, damage: 0.0, speed: 0.8, size: 0.8 },
    color: '#5c4a5c',
    behaviors: [
      { type: 'aoe_slow', radius: 70, percent: 0.4 },
      { type: 'damage_aura', radius: 70, dps: 2 },
    ],
  },
  {
    id: 'thorned_snare',
    name: 'Thorned Snare',
    description: 'Physical trap of bone spikes. Massive, immovable.',
    runeSequence: ['chain', 'veil', 'flesh'],
    incantation: 'In chains... Through veil... Of flesh...',
    stats: { health: 1.5, damage: 0.0, speed: 0.6, size: 1.4 },
    color: '#7a6b5c',
    behaviors: [
      { type: 'aoe_slow', radius: 70, percent: 0.4 },
      { type: 'fortified', damageReduction: 0.4 },
      { type: 'damage_aura', radius: 70, dps: 2 },
    ],
  },

  // VEIL-first
  {
    id: 'risen_shade',
    name: 'Risen Shade',
    description: 'Ghost given flesh, harder to banish.',
    runeSequence: ['veil', 'breath', 'flesh'],
    incantation: 'Through veil... By breath... Of flesh...',
    stats: { health: 1.0, damage: 0.9, speed: 1.4, size: 1.0 },
    color: '#5a7a6b',
    behaviors: [
      { type: 'teleport_attack' },
      { type: 'phase' },
      { type: 'fortified', damageReduction: 0.2 },
    ],
  },
  {
    id: 'binding_shade',
    name: 'Binding Shade',
    description: 'Ghost that pins targets after teleporting in.',
    runeSequence: ['veil', 'breath', 'chain'],
    incantation: 'Through veil... By breath... In chains...',
    stats: { health: 0.6, damage: 0.8, speed: 1.5, size: 0.8 },
    color: '#4a5c7a',
    behaviors: [
      { type: 'teleport_attack' },
      { type: 'root_on_hit', duration: 1.5 },
    ],
  },
  {
    id: 'hungry_double',
    name: 'Hungry Double',
    description: 'Doppelganger that devours what it copies.',
    runeSequence: ['veil', 'flesh', 'breath'],
    incantation: 'Through veil... Of flesh... By breath...',
    stats: { health: 1.0, damage: 1.0, speed: 1.1, size: 1.0 },
    color: '#6b5c6b',
    behaviors: [
      { type: 'decoy_on_hit', decoyHP: 10 },
      { type: 'devour', healPercent: 0.3, damageBuff: 0.5, buffDuration: 5 },
    ],
  },
  {
    id: 'armored_double',
    name: 'Armored Double',
    description: 'Fortified mimicry. Decoys are tougher.',
    runeSequence: ['veil', 'flesh', 'chain'],
    incantation: 'Through veil... Of flesh... In chains...',
    stats: { health: 1.2, damage: 0.7, speed: 0.9, size: 1.2 },
    color: '#8a7a6b',
    behaviors: [
      { type: 'decoy_on_hit', decoyHP: 20 },
      { type: 'fortified', damageReduction: 0.25 },
    ],
  },
  {
    id: 'vampiric_anchor',
    name: 'Vampiric Anchor',
    description: 'Spirit binder that drinks from pinned targets.',
    runeSequence: ['veil', 'chain', 'breath'],
    incantation: 'Through veil... In chains... By breath...',
    stats: { health: 0.8, damage: 0.7, speed: 0.8, size: 0.9 },
    color: '#6b4a5c',
    behaviors: [
      { type: 'root_on_hit', duration: 2 },
      { type: 'life_steal', percent: 0.3 },
    ],
  },
  {
    id: 'fortress_anchor',
    name: 'Fortress Anchor',
    description: 'Immense spirit that locks enemies and absorbs blows.',
    runeSequence: ['veil', 'chain', 'flesh'],
    incantation: 'Through veil... In chains... Of flesh...',
    stats: { health: 1.5, damage: 0.5, speed: 0.6, size: 1.5 },
    color: '#7a6b7a',
    behaviors: [
      { type: 'root_on_hit', duration: 2 },
      { type: 'taunt', radius: 70 },
      { type: 'fortified', damageReduction: 0.3 },
    ],
  },

  // ============================================================
  // 4-RUNE ARCHETYPES (24)
  // ============================================================

  // BREATH-first
  {
    id: 'deathknight',
    name: 'Deathknight',
    description: 'Paramount undead warrior. Aura empowers all allies.',
    runeSequence: ['breath', 'flesh', 'chain', 'veil'],
    incantation: 'By breath... Of flesh... In chains... Through veil...',
    stats: { health: 2.0, damage: 1.5, speed: 0.9, size: 1.5 },
    color: '#c4a040',
    behaviors: [
      { type: 'rage', maxAttackSpeedBonus: 1.5 },
      { type: 'fortified', damageReduction: 0.3 },
      { type: 'aura_ally_buff', radius: 80, damageBuff: 0.25 },
    ],
  },
  {
    id: 'grave_warden',
    name: 'Grave Warden',
    description: 'Guardian spirit. Shields allies from death itself.',
    runeSequence: ['breath', 'flesh', 'veil', 'chain'],
    incantation: 'By breath... Of flesh... Through veil... In chains...',
    stats: { health: 1.8, damage: 0.8, speed: 0.8, size: 1.4 },
    color: '#6ba07a',
    behaviors: [
      { type: 'rage', maxAttackSpeedBonus: 1.5 },
      { type: 'dodge', chance: 0.3 },
      { type: 'protection_aura', radius: 80, reduction: 0.4 },
    ],
  },
  {
    id: 'lichs_hand',
    name: "Lich's Hand",
    description: 'Fragment of a greater lich. Spawns lesser undead.',
    runeSequence: ['breath', 'chain', 'flesh', 'veil'],
    incantation: 'By breath... In chains... Of flesh... Through veil...',
    stats: { health: 1.5, damage: 0.6, speed: 0.7, size: 1.2 },
    color: '#4ac0a0',
    behaviors: [
      { type: 'life_tether', dps: 4 },
      { type: 'spawn_minions', interval: 8, minionType: 'skeleton' },
    ],
  },
  {
    id: 'deaths_embrace',
    name: "Death's Embrace",
    description: 'Inescapable doom. Tethers to strongest enemy.',
    runeSequence: ['breath', 'chain', 'veil', 'flesh'],
    incantation: 'By breath... In chains... Through veil... Of flesh...',
    stats: { health: 1.8, damage: 0.5, speed: 0.6, size: 1.3 },
    color: '#5a3a4a',
    behaviors: [
      { type: 'life_tether', dps: 5 },
      { type: 'root_on_hit', duration: 3 },
      { type: 'fortified', damageReduction: 0.4 },
    ],
  },
  {
    id: 'corpse_oracle',
    name: 'Corpse Oracle',
    description: 'Prophetic dead. Enemies miss constantly near it.',
    runeSequence: ['breath', 'veil', 'flesh', 'chain'],
    incantation: 'By breath... Through veil... Of flesh... In chains...',
    stats: { health: 1.2, damage: 0.3, speed: 0.7, size: 1.2 },
    color: '#8ab0c0',
    behaviors: [
      { type: 'miss_aura', radius: 80, chance: 0.5 },
      { type: 'aura_enemy_debuff', radius: 80, attackSpeedReduction: 0.3 },
      { type: 'taunt', radius: 80 },
    ],
  },
  {
    id: 'doom_herald',
    name: 'Doom Herald',
    description: 'Harbinger of mass death. All enemies wither.',
    runeSequence: ['breath', 'veil', 'chain', 'flesh'],
    incantation: 'By breath... Through veil... In chains... Of flesh...',
    stats: { health: 1.5, damage: 0.3, speed: 0.6, size: 1.4 },
    color: '#4a2a3a',
    behaviors: [
      { type: 'damage_aura', radius: 100, dps: 3 },
      { type: 'aura_enemy_debuff', radius: 100, attackSpeedReduction: 0.3 },
      { type: 'fortified', damageReduction: 0.25 },
    ],
  },

  // FLESH-first
  {
    id: 'abomination',
    name: 'Abomination',
    description: 'Stitched monstrosity. Massive. Explodes on death.',
    runeSequence: ['flesh', 'breath', 'chain', 'veil'],
    incantation: 'Of flesh... By breath... In chains... Through veil...',
    stats: { health: 2.5, damage: 1.2, speed: 0.6, size: 2.0 },
    color: '#5a7a3a',
    behaviors: [
      { type: 'devour', healPercent: 0.3, damageBuff: 0.5, buffDuration: 5 },
      { type: 'fortified', damageReduction: 0.3 },
      { type: 'death_explode', radius: 100, damage: 30 },
    ],
  },
  {
    id: 'plague_bearer',
    name: 'Plague Bearer',
    description: 'Walking disease. Poisons everything nearby.',
    runeSequence: ['flesh', 'breath', 'veil', 'chain'],
    incantation: 'Of flesh... By breath... Through veil... In chains...',
    stats: { health: 1.8, damage: 0.8, speed: 0.8, size: 1.5 },
    color: '#7a8a3a',
    behaviors: [
      { type: 'devour', healPercent: 0.3, damageBuff: 0.5, buffDuration: 5 },
      { type: 'damage_aura', radius: 70, dps: 3 },
      { type: 'aoe_slow', radius: 70, percent: 0.2 },
    ],
  },
  {
    id: 'bone_colossus',
    name: 'Bone Colossus',
    description: 'Towering skeleton construct. Knocks enemies aside.',
    runeSequence: ['flesh', 'chain', 'breath', 'veil'],
    incantation: 'Of flesh... In chains... By breath... Through veil...',
    stats: { health: 2.5, damage: 0.8, speed: 0.5, size: 2.0 },
    color: '#d4c4a0',
    behaviors: [
      { type: 'fortified', damageReduction: 0.5 },
      { type: 'knockback', distance: 40 },
      { type: 'life_steal', percent: 0.2 },
    ],
  },
  {
    id: 'marrow_golem',
    name: 'Marrow Golem',
    description: 'Living bone that absorbs fallen allies to grow.',
    runeSequence: ['flesh', 'chain', 'veil', 'breath'],
    incantation: 'Of flesh... In chains... Through veil... By breath...',
    stats: { health: 2.0, damage: 0.7, speed: 0.6, size: 1.6 },
    color: '#b8a880',
    behaviors: [
      { type: 'fortified', damageReduction: 0.4 },
      { type: 'scaling_on_kill', damagePerKill: 0.5 },
      { type: 'regen', hpPerSecond: 3 },
    ],
  },
  {
    id: 'shadow_stalker',
    name: 'Shadow Stalker',
    description: 'Perfect invisible predator. Always crits, fragile.',
    runeSequence: ['flesh', 'veil', 'breath', 'chain'],
    incantation: 'Of flesh... Through veil... By breath... In chains...',
    stats: { health: 0.5, damage: 2.0, speed: 1.5, size: 0.8 },
    color: '#2a2a3a',
    behaviors: [
      { type: 'ambush', damageMultiplier: 4 },
      { type: 'phase' },
      { type: 'life_steal', percent: 0.25 },
    ],
  },
  {
    id: 'fleshweaver',
    name: 'Fleshweaver',
    description: 'Rebuilds fallen minions from scraps.',
    runeSequence: ['flesh', 'veil', 'chain', 'breath'],
    incantation: 'Of flesh... Through veil... In chains... By breath...',
    stats: { health: 1.2, damage: 0.8, speed: 0.9, size: 1.1 },
    color: '#6b4a5c',
    behaviors: [
      { type: 'ambush', damageMultiplier: 2 },
      { type: 'resurrect_nearby', radius: 80, cooldown: 10 },
    ],
  },

  // CHAIN-first
  {
    id: 'soul_collector',
    name: 'Soul Collector',
    description: 'Harvester that grows stronger with every kill.',
    runeSequence: ['chain', 'breath', 'flesh', 'veil'],
    incantation: 'In chains... By breath... Of flesh... Through veil...',
    stats: { health: 1.2, damage: 1.0, speed: 1.0, size: 1.0 },
    color: '#8a4a6b',
    behaviors: [
      { type: 'life_steal', percent: 0.3 },
      { type: 'scaling_on_kill', damagePerKill: 1.0 },
      { type: 'phase' },
    ],
  },
  {
    id: 'spirit_warden',
    name: 'Spirit Warden',
    description: 'Creates a sanctuary zone for the dead.',
    runeSequence: ['chain', 'breath', 'veil', 'flesh'],
    incantation: 'In chains... By breath... Through veil... Of flesh...',
    stats: { health: 2.0, damage: 0.3, speed: 0.5, size: 1.5 },
    color: '#5a8a7a',
    behaviors: [
      { type: 'protection_aura', radius: 90, reduction: 0.5 },
      { type: 'regen', hpPerSecond: 3 },
      { type: 'taunt', radius: 90 },
    ],
  },
  {
    id: 'ossuary',
    name: 'Ossuary',
    description: 'Bone shrine that endlessly produces minions.',
    runeSequence: ['chain', 'flesh', 'breath', 'veil'],
    incantation: 'In chains... Of flesh... By breath... Through veil...',
    stats: { health: 3.0, damage: 0.0, speed: 0.0, size: 2.0 },
    color: '#c4b490',
    behaviors: [
      { type: 'stationary' },
      { type: 'spawn_minions', interval: 6, minionType: 'skeleton' },
      { type: 'fortified', damageReduction: 0.5 },
    ],
  },
  {
    id: 'crypt_gate',
    name: 'Crypt Gate',
    description: 'Portal that relocates enemies away from you.',
    runeSequence: ['chain', 'flesh', 'veil', 'breath'],
    incantation: 'In chains... Of flesh... Through veil... By breath...',
    stats: { health: 2.5, damage: 0.0, speed: 0.0, size: 1.8 },
    color: '#7a5a8a',
    behaviors: [
      { type: 'stationary' },
      { type: 'knockback', distance: 60 },
      { type: 'taunt', radius: 90 },
      { type: 'fortified', damageReduction: 0.4 },
    ],
  },
  {
    id: 'netherbinder',
    name: 'Netherbinder',
    description: 'Reality-warping entity. Massive zone of control.',
    runeSequence: ['chain', 'veil', 'breath', 'flesh'],
    incantation: 'In chains... Through veil... By breath... Of flesh...',
    stats: { health: 1.5, damage: 0.4, speed: 0.7, size: 1.3 },
    color: '#4a3a6b',
    behaviors: [
      { type: 'aoe_slow', radius: 90, percent: 0.6 },
      { type: 'damage_aura', radius: 90, dps: 3 },
      { type: 'life_steal', percent: 0.2 },
    ],
  },
  {
    id: 'chain_wraith',
    name: 'Chain Wraith',
    description: 'Multi-target binder. Chains several enemies at once.',
    runeSequence: ['chain', 'veil', 'flesh', 'breath'],
    incantation: 'In chains... Through veil... Of flesh... By breath...',
    stats: { health: 1.2, damage: 0.5, speed: 0.8, size: 1.1 },
    color: '#5c4a7a',
    behaviors: [
      { type: 'aoe_slow', radius: 80, percent: 0.4 },
      { type: 'root_on_hit', duration: 1.5 },
      { type: 'damage_aura', radius: 80, dps: 2 },
    ],
  },

  // VEIL-first
  {
    id: 'revenant_king',
    name: 'Revenant King',
    description: 'Sovereign of the raised dead. Commands all nearby minions.',
    runeSequence: ['veil', 'breath', 'flesh', 'chain'],
    incantation: 'Through veil... By breath... Of flesh... In chains...',
    stats: { health: 1.8, damage: 1.5, speed: 1.2, size: 1.4 },
    color: '#c4a060',
    behaviors: [
      { type: 'teleport_attack' },
      { type: 'aura_ally_buff', radius: 90, damageBuff: 0.3 },
      { type: 'rage', maxAttackSpeedBonus: 1.5 },
    ],
  },
  {
    id: 'wight_lord',
    name: 'Wight Lord',
    description: 'Armored phantom lord that pins and punishes.',
    runeSequence: ['veil', 'breath', 'chain', 'flesh'],
    incantation: 'Through veil... By breath... In chains... Of flesh...',
    stats: { health: 2.0, damage: 1.0, speed: 1.1, size: 1.5 },
    color: '#5a6b8a',
    behaviors: [
      { type: 'teleport_attack' },
      { type: 'root_on_hit', duration: 2 },
      { type: 'fortified', damageReduction: 0.35 },
    ],
  },
  {
    id: 'hungering_mimic',
    name: 'Hungering Mimic',
    description: 'Shape-stealer that devours and grows endlessly.',
    runeSequence: ['veil', 'flesh', 'breath', 'chain'],
    incantation: 'Through veil... Of flesh... By breath... In chains...',
    stats: { health: 1.2, damage: 1.2, speed: 1.1, size: 1.1 },
    color: '#7a5c7a',
    behaviors: [
      { type: 'decoy_on_hit', decoyHP: 15 },
      { type: 'devour', healPercent: 0.3, damageBuff: 0.5, buffDuration: 5 },
      { type: 'scaling_on_kill', damagePerKill: 0.5 },
    ],
  },
  {
    id: 'pale_sentinel',
    name: 'Pale Sentinel',
    description: 'Mimicking guardian. Decoys everywhere.',
    runeSequence: ['veil', 'flesh', 'chain', 'breath'],
    incantation: 'Through veil... Of flesh... In chains... By breath...',
    stats: { health: 1.8, damage: 0.6, speed: 0.8, size: 1.4 },
    color: '#a0a0b0',
    behaviors: [
      { type: 'decoy_on_hit', decoyHP: 25 },
      { type: 'fortified', damageReduction: 0.3 },
      { type: 'regen', hpPerSecond: 3 },
    ],
  },
  {
    id: 'reaper',
    name: 'Reaper',
    description: 'Spirit that chains souls and feeds on them.',
    runeSequence: ['veil', 'chain', 'breath', 'flesh'],
    incantation: 'Through veil... In chains... By breath... Of flesh...',
    stats: { health: 1.0, damage: 1.5, speed: 1.2, size: 1.0 },
    color: '#2a2a2a',
    behaviors: [
      { type: 'root_on_hit', duration: 2.5 },
      { type: 'life_steal', percent: 0.4 },
      { type: 'scaling_on_kill', damagePerKill: 1.0 },
    ],
  },
  {
    id: 'tomb_warden',
    name: 'Tomb Warden',
    description: 'Immense spirit guardian. Locks down an area entirely.',
    runeSequence: ['veil', 'chain', 'flesh', 'breath'],
    incantation: 'Through veil... In chains... Of flesh... By breath...',
    stats: { health: 2.5, damage: 0.5, speed: 0.5, size: 1.8 },
    color: '#6b6b8a',
    behaviors: [
      { type: 'root_on_hit', duration: 2 },
      { type: 'taunt', radius: 90 },
      { type: 'fortified', damageReduction: 0.4 },
      { type: 'protection_aura', radius: 80, reduction: 0.3 },
    ],
  },
];

export const ARCHETYPE_MAP: Map<string, ArchetypeDefinition> = new Map(
  ARCHETYPES.map(a => [makeKey(a.runeSequence), a])
);

export function lookupArchetype(sequence: RuneId[]): ArchetypeDefinition | undefined {
  return ARCHETYPE_MAP.get(makeKey(sequence));
}
