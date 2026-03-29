import { type RuneId, RUNE_IDS, RUNE_HIT_RADIUS, runeScreenPos } from './runes.ts';
import type { EssenceSystem } from './essences.ts';

export interface PathPoint {
  x: number;
  y: number;
}

export interface GestureResult {
  runeSequence: RuneId[];
  path: PathPoint[];
}

export class GestureTracker {
  private active = false;
  private path: PathPoint[] = [];
  private runeSequence: RuneId[] = [];
  private hitRunes: Set<RuneId> = new Set();
  private screenW = 0;
  private screenH = 0;

  /** Reference to essence system for gating rune hits. */
  essences: EssenceSystem | null = null;

  /** Callback fired when a rune is hit during a gesture. */
  onRuneHit: ((id: RuneId) => void) | null = null;

  setScreenSize(w: number, h: number) {
    this.screenW = w;
    this.screenH = h;
  }

  get isActive(): boolean { return this.active; }
  get currentSequence(): RuneId[] { return this.runeSequence; }
  get currentPath(): PathPoint[] { return this.path; }
  get activeHitRunes(): Set<RuneId> { return this.hitRunes; }

  startGesture(x: number, y: number) {
    this.active = true;
    this.path = [{ x, y }];
    this.runeSequence = [];
    this.hitRunes = new Set();
    this.checkRuneHits(x, y);
  }

  updateGesture(x: number, y: number) {
    if (!this.active) return;
    this.path.push({ x, y });
    this.checkRuneHits(x, y);
  }

  endGesture(): GestureResult {
    this.active = false;
    return {
      runeSequence: [...this.runeSequence],
      path: [...this.path],
    };
  }

  cancelGesture() {
    this.active = false;
    this.path = [];
    this.runeSequence = [];
    this.hitRunes = new Set();
  }

  private checkRuneHits(x: number, y: number) {
    for (const id of RUNE_IDS) {
      if (this.hitRunes.has(id)) continue;

      // Essence-gating: skip rune if no matching essence available
      if (this.essences) {
        const counts = this.essences.counts();
        if (counts[id] <= 0) continue;
      }

      const pos = runeScreenPos(id, this.screenW, this.screenH);
      const dx = x - pos.x;
      const dy = y - pos.y;
      const dist = Math.sqrt(dx * dx + dy * dy);

      if (dist <= RUNE_HIT_RADIUS) {
        this.hitRunes.add(id);
        this.runeSequence.push(id);

        // Claim an essence of this type
        if (this.essences) {
          this.essences.claim(id);
        }

        if (this.onRuneHit) {
          this.onRuneHit(id);
        }
      }
    }
  }
}
