import type { RuneId } from './runes.ts';

export interface ArchetypeDefinition {
  id: string;
  name: string;
  description: string;
  runeSequence: RuneId[];
  color: string;
}

function makeKey(seq: RuneId[]): string {
  return seq.join(',');
}

const ARCHETYPES: ArchetypeDefinition[] = [
  // ============================================================
  // 2-RUNE ARCHETYPES (12)
  // ============================================================
  {
    id: 'revenant', name: 'Revenant',
    description: 'Raised warrior burning with fading life.',
    runeSequence: ['breath', 'flesh'], color: '#b85c3a',
  },
  {
    id: 'soul_shackle', name: 'Soul Shackle',
    description: 'Spectral chains that leash life from the living.',
    runeSequence: ['breath', 'chain'], color: '#5a9e8f',
  },
  {
    id: 'whisper', name: 'Whisper',
    description: 'A murmur of death that saps the will to fight.',
    runeSequence: ['breath', 'veil'], color: '#6b7fa3',
  },
  {
    id: 'ghoul', name: 'Ghoul',
    description: 'Ravenous corpse that feeds on the fallen.',
    runeSequence: ['flesh', 'breath'], color: '#6b8a3a',
  },
  {
    id: 'bone_construct', name: 'Bone Construct',
    description: 'Dense skeleton bound in rigid formation.',
    runeSequence: ['flesh', 'chain'], color: '#d4c9a8',
  },
  {
    id: 'lurker', name: 'Lurker',
    description: 'Dead flesh cloaked in shadow. Strikes unseen.',
    runeSequence: ['flesh', 'veil'], color: '#3a3a5c',
  },
  {
    id: 'life_leech', name: 'Life Leech',
    description: 'Parasitic tether that feeds all nearby dead.',
    runeSequence: ['chain', 'breath'], color: '#8a5c5c',
  },
  {
    id: 'bone_wall', name: 'Bone Wall',
    description: 'Immovable rampart of fused bone.',
    runeSequence: ['chain', 'flesh'], color: '#c9b896',
  },
  {
    id: 'shadow_snare', name: 'Shadow Snare',
    description: 'Invisible chains that slow all who pass.',
    runeSequence: ['chain', 'veil'], color: '#5c4a6b',
  },
  {
    id: 'shade', name: 'Shade',
    description: 'Swift ghost that phases through the battlefield.',
    runeSequence: ['veil', 'breath'], color: '#4a6b8a',
  },
  {
    id: 'doppelganger', name: 'Doppelganger',
    description: 'Mimicking form that confuses the living.',
    runeSequence: ['veil', 'flesh'], color: '#7a6b8a',
  },
  {
    id: 'soul_anchor', name: 'Soul Anchor',
    description: 'Spirit that pins the living in place.',
    runeSequence: ['veil', 'chain'], color: '#6b5c8a',
  },

  // ============================================================
  // 3-RUNE ARCHETYPES (24)
  // ============================================================

  // BREATH-first
  {
    id: 'iron_revenant', name: 'Iron Revenant',
    description: 'Armored warrior that fights harder as it falls.',
    runeSequence: ['breath', 'flesh', 'chain'], color: '#8a6b4a',
  },
  {
    id: 'fading_revenant', name: 'Fading Revenant',
    description: 'Phase-shifts between worlds mid-swing.',
    runeSequence: ['breath', 'flesh', 'veil'], color: '#7a5c6b',
  },
  {
    id: 'sinew_shackle', name: 'Sinew Shackle',
    description: 'Corporeal chains made of twisted muscle.',
    runeSequence: ['breath', 'chain', 'flesh'], color: '#7a8a6b',
  },
  {
    id: 'spectral_leash', name: 'Spectral Leash',
    description: 'Invisible tether draining from the unseen.',
    runeSequence: ['breath', 'chain', 'veil'], color: '#5a7a8a',
  },
  {
    id: 'manifest_whisper', name: 'Manifest Whisper',
    description: 'Whisper given weight and form to block the path.',
    runeSequence: ['breath', 'veil', 'flesh'], color: '#6b7a5c',
  },
  {
    id: 'binding_whisper', name: 'Binding Whisper',
    description: 'Murmur that roots those who hear it.',
    runeSequence: ['breath', 'veil', 'chain'], color: '#5c6b8a',
  },

  // FLESH-first
  {
    id: 'chained_ghoul', name: 'Chained Ghoul',
    description: 'Bound feeder that drags its prey to a halt.',
    runeSequence: ['flesh', 'breath', 'chain'], color: '#6b7a4a',
  },
  {
    id: 'phantom_ghoul', name: 'Phantom Ghoul',
    description: 'Ghoul that feeds from between worlds.',
    runeSequence: ['flesh', 'breath', 'veil'], color: '#5c6b5c',
  },
  {
    id: 'draining_construct', name: 'Draining Construct',
    description: 'Bone fortress that drinks from attackers.',
    runeSequence: ['flesh', 'chain', 'breath'], color: '#b8a87a',
  },
  {
    id: 'phantom_construct', name: 'Phantom Construct',
    description: 'Bone wall that flickers in and out of existence.',
    runeSequence: ['flesh', 'chain', 'veil'], color: '#a89a8a',
  },
  {
    id: 'vampiric_lurker', name: 'Vampiric Lurker',
    description: 'Shadow hunter that drinks deeply from wounds.',
    runeSequence: ['flesh', 'veil', 'breath'], color: '#4a3a4a',
  },
  {
    id: 'snaring_lurker', name: 'Snaring Lurker',
    description: 'Shadow predator that pins prey before the kill.',
    runeSequence: ['flesh', 'veil', 'chain'], color: '#3a3a4a',
  },

  // CHAIN-first
  {
    id: 'flesh_leech', name: 'Flesh Leech',
    description: 'Heavy parasitic mound that saps life from all it touches.',
    runeSequence: ['chain', 'breath', 'flesh'], color: '#8a5a5a',
  },
  {
    id: 'phantom_leech', name: 'Phantom Leech',
    description: 'Invisible siphon drifting unseen among enemies.',
    runeSequence: ['chain', 'breath', 'veil'], color: '#5a6b7a',
  },
  {
    id: 'living_wall', name: 'Living Wall',
    description: 'Self-mending barricade of bone and sinew.',
    runeSequence: ['chain', 'flesh', 'breath'], color: '#c9b8a0',
  },
  {
    id: 'flickering_wall', name: 'Flickering Wall',
    description: 'Barrier that phases, letting allies through.',
    runeSequence: ['chain', 'flesh', 'veil'], color: '#a0a0b8',
  },
  {
    id: 'draining_snare', name: 'Draining Snare',
    description: 'Dark zone that weakens and drains trespassers.',
    runeSequence: ['chain', 'veil', 'breath'], color: '#5c4a5c',
  },
  {
    id: 'thorned_snare', name: 'Thorned Snare',
    description: 'Physical trap of bone spikes. Massive, immovable.',
    runeSequence: ['chain', 'veil', 'flesh'], color: '#7a6b5c',
  },

  // VEIL-first
  {
    id: 'risen_shade', name: 'Risen Shade',
    description: 'Ghost given flesh, harder to banish.',
    runeSequence: ['veil', 'breath', 'flesh'], color: '#5a7a6b',
  },
  {
    id: 'binding_shade', name: 'Binding Shade',
    description: 'Ghost that pins targets after teleporting in.',
    runeSequence: ['veil', 'breath', 'chain'], color: '#4a5c7a',
  },
  {
    id: 'hungry_double', name: 'Hungry Double',
    description: 'Doppelganger that devours what it copies.',
    runeSequence: ['veil', 'flesh', 'breath'], color: '#6b5c6b',
  },
  {
    id: 'armored_double', name: 'Armored Double',
    description: 'Fortified mimicry. Decoys are tougher.',
    runeSequence: ['veil', 'flesh', 'chain'], color: '#8a7a6b',
  },
  {
    id: 'vampiric_anchor', name: 'Vampiric Anchor',
    description: 'Spirit binder that drinks from pinned targets.',
    runeSequence: ['veil', 'chain', 'breath'], color: '#6b4a5c',
  },
  {
    id: 'fortress_anchor', name: 'Fortress Anchor',
    description: 'Immense spirit that locks enemies and absorbs blows.',
    runeSequence: ['veil', 'chain', 'flesh'], color: '#7a6b7a',
  },

  // ============================================================
  // 4-RUNE ARCHETYPES (24)
  // ============================================================

  // BREATH-first
  {
    id: 'deathknight', name: 'Deathknight',
    description: 'Paramount undead warrior. Aura empowers all allies.',
    runeSequence: ['breath', 'flesh', 'chain', 'veil'], color: '#c4a040',
  },
  {
    id: 'grave_warden', name: 'Grave Warden',
    description: 'Guardian spirit. Shields allies from death itself.',
    runeSequence: ['breath', 'flesh', 'veil', 'chain'], color: '#6ba07a',
  },
  {
    id: 'lichs_hand', name: "Lich's Hand",
    description: 'Fragment of a greater lich. Spawns lesser undead.',
    runeSequence: ['breath', 'chain', 'flesh', 'veil'], color: '#4ac0a0',
  },
  {
    id: 'deaths_embrace', name: "Death's Embrace",
    description: 'Inescapable doom. Tethers to strongest enemy.',
    runeSequence: ['breath', 'chain', 'veil', 'flesh'], color: '#5a3a4a',
  },
  {
    id: 'corpse_oracle', name: 'Corpse Oracle',
    description: 'Prophetic dead. Enemies miss constantly near it.',
    runeSequence: ['breath', 'veil', 'flesh', 'chain'], color: '#8ab0c0',
  },
  {
    id: 'doom_herald', name: 'Doom Herald',
    description: 'Harbinger of mass death. All enemies wither.',
    runeSequence: ['breath', 'veil', 'chain', 'flesh'], color: '#4a2a3a',
  },

  // FLESH-first
  {
    id: 'abomination', name: 'Abomination',
    description: 'Stitched monstrosity. Massive. Explodes on death.',
    runeSequence: ['flesh', 'breath', 'chain', 'veil'], color: '#5a7a3a',
  },
  {
    id: 'plague_bearer', name: 'Plague Bearer',
    description: 'Walking disease. Poisons everything nearby.',
    runeSequence: ['flesh', 'breath', 'veil', 'chain'], color: '#7a8a3a',
  },
  {
    id: 'bone_colossus', name: 'Bone Colossus',
    description: 'Towering skeleton construct. Knocks enemies aside.',
    runeSequence: ['flesh', 'chain', 'breath', 'veil'], color: '#d4c4a0',
  },
  {
    id: 'marrow_golem', name: 'Marrow Golem',
    description: 'Living bone that absorbs fallen allies to grow.',
    runeSequence: ['flesh', 'chain', 'veil', 'breath'], color: '#b8a880',
  },
  {
    id: 'shadow_stalker', name: 'Shadow Stalker',
    description: 'Perfect invisible predator. Always crits, fragile.',
    runeSequence: ['flesh', 'veil', 'breath', 'chain'], color: '#2a2a3a',
  },
  {
    id: 'fleshweaver', name: 'Fleshweaver',
    description: 'Rebuilds fallen minions from scraps.',
    runeSequence: ['flesh', 'veil', 'chain', 'breath'], color: '#6b4a5c',
  },

  // CHAIN-first
  {
    id: 'soul_collector', name: 'Soul Collector',
    description: 'Harvester that grows stronger with every kill.',
    runeSequence: ['chain', 'breath', 'flesh', 'veil'], color: '#8a4a6b',
  },
  {
    id: 'spirit_warden', name: 'Spirit Warden',
    description: 'Creates a sanctuary zone for the dead.',
    runeSequence: ['chain', 'breath', 'veil', 'flesh'], color: '#5a8a7a',
  },
  {
    id: 'ossuary', name: 'Ossuary',
    description: 'Bone shrine that endlessly produces minions.',
    runeSequence: ['chain', 'flesh', 'breath', 'veil'], color: '#c4b490',
  },
  {
    id: 'crypt_gate', name: 'Crypt Gate',
    description: 'Portal that relocates enemies away from you.',
    runeSequence: ['chain', 'flesh', 'veil', 'breath'], color: '#7a5a8a',
  },
  {
    id: 'netherbinder', name: 'Netherbinder',
    description: 'Reality-warping entity. Massive zone of control.',
    runeSequence: ['chain', 'veil', 'breath', 'flesh'], color: '#4a3a6b',
  },
  {
    id: 'chain_wraith', name: 'Chain Wraith',
    description: 'Multi-target binder. Chains several enemies at once.',
    runeSequence: ['chain', 'veil', 'flesh', 'breath'], color: '#5c4a7a',
  },

  // VEIL-first
  {
    id: 'revenant_king', name: 'Revenant King',
    description: 'Sovereign of the raised dead. Commands all nearby minions.',
    runeSequence: ['veil', 'breath', 'flesh', 'chain'], color: '#c4a060',
  },
  {
    id: 'wight_lord', name: 'Wight Lord',
    description: 'Armored phantom lord that pins and punishes.',
    runeSequence: ['veil', 'breath', 'chain', 'flesh'], color: '#5a6b8a',
  },
  {
    id: 'hungering_mimic', name: 'Hungering Mimic',
    description: 'Shape-stealer that devours and grows endlessly.',
    runeSequence: ['veil', 'flesh', 'breath', 'chain'], color: '#7a5c7a',
  },
  {
    id: 'pale_sentinel', name: 'Pale Sentinel',
    description: 'Mimicking guardian. Decoys everywhere.',
    runeSequence: ['veil', 'flesh', 'chain', 'breath'], color: '#a0a0b0',
  },
  {
    id: 'reaper', name: 'Reaper',
    description: 'Spirit that chains souls and feeds on them.',
    runeSequence: ['veil', 'chain', 'breath', 'flesh'], color: '#2a2a2a',
  },
  {
    id: 'tomb_warden', name: 'Tomb Warden',
    description: 'Immense spirit guardian. Locks down an area entirely.',
    runeSequence: ['veil', 'chain', 'flesh', 'breath'], color: '#6b6b8a',
  },
];

const ARCHETYPE_MAP = new Map<string, ArchetypeDefinition>(
  ARCHETYPES.map(a => [makeKey(a.runeSequence), a]),
);

export function lookupArchetype(sequence: RuneId[]): ArchetypeDefinition | undefined {
  return ARCHETYPE_MAP.get(makeKey(sequence));
}
