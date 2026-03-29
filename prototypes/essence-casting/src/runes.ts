export type RuneId = 'breath' | 'flesh' | 'chain' | 'veil';

export interface RuneDefinition {
  id: RuneId;
  name: string;
  /** Relative position within the rune area (0-1). */
  position: { x: number; y: number };
  color: string;
  colorNum: number;
}

export const RUNES: Record<RuneId, RuneDefinition> = {
  breath: {
    id: 'breath',
    name: 'BREATH',
    position: { x: 0.5, y: 0.2 },
    color: '#7fdbca',
    colorNum: 0x7fdbca,
  },
  flesh: {
    id: 'flesh',
    name: 'FLESH',
    position: { x: 0.5, y: 0.8 },
    color: '#c97b84',
    colorNum: 0xc97b84,
  },
  chain: {
    id: 'chain',
    name: 'CHAIN',
    position: { x: 0.75, y: 0.5 },
    color: '#d4a574',
    colorNum: 0xd4a574,
  },
  veil: {
    id: 'veil',
    name: 'VEIL',
    position: { x: 0.25, y: 0.5 },
    color: '#9b8ec4',
    colorNum: 0x9b8ec4,
  },
};

export const RUNE_IDS: RuneId[] = ['breath', 'flesh', 'chain', 'veil'];

/** Default hit radius in pixels. Adjusted via debug panel. */
export let RUNE_HIT_RADIUS = 40;

export function setRuneHitRadius(r: number) {
  RUNE_HIT_RADIUS = r;
}

/**
 * Max diameter (px) of the rune area. Rune positions are mapped into a square
 * of this size (or the screen size, whichever is smaller), centered on-screen.
 */
export const RUNE_AREA_MAX = 350;

/** Convert a rune's relative position to screen coordinates.
 *  Rune area is anchored to bottom-center of screen with Relish in the middle. */
export function runeScreenPos(
  runeId: RuneId,
  screenW: number,
  screenH: number,
): { x: number; y: number } {
  const rune = RUNES[runeId];
  const areaW = Math.min(RUNE_AREA_MAX, screenW * 0.8);
  const areaH = Math.min(RUNE_AREA_MAX, screenH * 0.4);
  const ox = (screenW - areaW) / 2;
  const oy = screenH - areaH - 30; // 30px from bottom
  return {
    x: ox + rune.position.x * areaW,
    y: oy + rune.position.y * areaH,
  };
}

/** Get the center of the rune area (where Relish stands). */
export function runeCenter(screenW: number, screenH: number): { x: number; y: number } {
  const areaH = Math.min(RUNE_AREA_MAX, screenH * 0.4);
  return {
    x: screenW / 2,
    y: screenH - areaH / 2 - 30,
  };
}
