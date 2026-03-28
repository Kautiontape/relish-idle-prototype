export type RuneId = 'breath' | 'flesh' | 'chain' | 'veil';

export interface RuneDefinition {
  id: RuneId;
  name: string;
  position: { x: number; y: number }; // relative to canvas (0-1)
  color: string;
  incantationFragment: string;
}

export const RUNES: Record<RuneId, RuneDefinition> = {
  breath: {
    id: 'breath',
    name: 'BREATH',
    position: { x: 0.5, y: 0.25 },
    color: '#7fdbca',
    incantationFragment: 'By breath...',
  },
  flesh: {
    id: 'flesh',
    name: 'FLESH',
    position: { x: 0.5, y: 0.75 },
    color: '#c97b84',
    incantationFragment: 'Of flesh...',
  },
  chain: {
    id: 'chain',
    name: 'CHAIN',
    position: { x: 0.8, y: 0.5 },
    color: '#d4a574',
    incantationFragment: 'In chains...',
  },
  veil: {
    id: 'veil',
    name: 'VEIL',
    position: { x: 0.2, y: 0.5 },
    color: '#9b8ec4',
    incantationFragment: 'Through veil...',
  },
};

export const RUNE_IDS: RuneId[] = ['breath', 'flesh', 'chain', 'veil'];

export const RUNE_HIT_RADIUS = 40;
