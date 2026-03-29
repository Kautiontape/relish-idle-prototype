import type { RuneId } from './runes.ts';
import { RUNES } from './runes.ts';
import { debugState } from './debug.ts';

export type EssenceType = RuneId; // 'flesh' | 'breath' | 'veil' | 'chain'

export interface EssenceDrop {
  /** Single-type drops have one entry; dual drops have two. */
  types: EssenceType[];
  x: number;
  y: number;
  age: number;
  /** Set when a gesture claims this drop (by consuming one of its types). */
  claimed: boolean;
  /** Which type was claimed (for dual). */
  claimedType: EssenceType | null;
}

// Essences persist indefinitely until consumed by casting.

export class EssenceSystem {
  drops: EssenceDrop[] = [];

  /** Count available (unclaimed, alive) essences of each type. */
  counts(): Record<EssenceType, number> {
    const c: Record<EssenceType, number> = { flesh: 0, breath: 0, veil: 0, chain: 0 };
    for (const d of this.drops) {
      if (d.claimed) continue;
      for (const t of d.types) {
        c[t]++;
      }
    }
    return c;
  }

  /** Try to claim one essence matching `type`. Returns true if successful. */
  claim(type: EssenceType): boolean {
    // Prefer single-type drops first to preserve dual drops
    for (const d of this.drops) {
      if (d.claimed) continue;
      if (d.types.length === 1 && d.types[0] === type) {
        d.claimed = true;
        d.claimedType = type;
        return true;
      }
    }
    // Fall back to dual drops
    for (const d of this.drops) {
      if (d.claimed) continue;
      if (d.types.includes(type)) {
        d.claimed = true;
        d.claimedType = type;
        return true;
      }
    }
    return false;
  }

  /** Unclaim all currently-claimed essences (on gesture cancel). */
  unclaimAll() {
    for (const d of this.drops) {
      if (d.claimed) {
        d.claimed = false;
        d.claimedType = null;
      }
    }
  }

  /** Remove all claimed essences (on spell complete). Returns positions + colors. */
  consumeClaimed(): { x: number; y: number; color: number }[] {
    const results: { x: number; y: number; color: number }[] = [];
    this.drops = this.drops.filter(d => {
      if (d.claimed) {
        const t = d.claimedType ?? d.types[0];
        results.push({ x: d.x, y: d.y, color: RUNES[t].colorNum });
        return false;
      }
      return true;
    });
    return results;
  }

  /** Spawn a new essence drop at the given world position. */
  spawn(types: EssenceType[], x: number, y: number) {
    const mult = debugState.essenceDropRate;
    for (let i = 0; i < mult; i++) {
      this.drops.push({
        types: [...types],
        x: x + (i > 0 ? (Math.random() - 0.5) * 20 : 0),
        y: y + (i > 0 ? (Math.random() - 0.5) * 20 : 0),
        age: 0,
        claimed: false,
        claimedType: null,
      });
    }
  }

  update(dt: number) {
    for (const d of this.drops) {
      d.age += dt;
    }
  }

  /** Get the primary display color for a drop. */
  static dropColor(drop: EssenceDrop, time: number): number {
    if (drop.types.length === 1) {
      return RUNES[drop.types[0]].colorNum;
    }
    // Dual: pulse between the two colors
    const idx = Math.floor(time * 2) % 2;
    return RUNES[drop.types[idx]].colorNum;
  }

  /** Get alpha (dims when claimed). */
  static dropAlpha(drop: EssenceDrop): number {
    return drop.claimed ? 0.25 : 0.8;
  }
}
