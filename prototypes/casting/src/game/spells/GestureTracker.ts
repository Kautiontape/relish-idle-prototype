import { type RuneId, RUNES, RUNE_IDS, RUNE_HIT_RADIUS } from './Runes';

export interface PathPoint {
  x: number;
  y: number;
  time: number;
}

export interface GestureResult {
  runeSequence: RuneId[];
  path: PathPoint[];
  duration: number;
}

export class GestureTracker {
  private active = false;
  private path: PathPoint[] = [];
  private runeSequence: RuneId[] = [];
  private hitRunes: Set<RuneId> = new Set();
  private startTime = 0;
  private canvasWidth = 0;
  private canvasHeight = 0;

  // Called each frame so rune positions scale with canvas
  setCanvasSize(width: number, height: number) {
    this.canvasWidth = width;
    this.canvasHeight = height;
  }

  get isActive(): boolean {
    return this.active;
  }

  get currentSequence(): RuneId[] {
    return this.runeSequence;
  }

  get currentPath(): PathPoint[] {
    return this.path;
  }

  get activeHitRunes(): Set<RuneId> {
    return this.hitRunes;
  }

  startGesture(x: number, y: number) {
    this.active = true;
    this.path = [{ x, y, time: performance.now() }];
    this.runeSequence = [];
    this.hitRunes = new Set();
    this.startTime = performance.now();

    // Check if starting position is already on a rune
    this.checkRuneHits(x, y);
  }

  updateGesture(x: number, y: number) {
    if (!this.active) return;
    this.path.push({ x, y, time: performance.now() });
    this.checkRuneHits(x, y);
  }

  endGesture(): GestureResult {
    this.active = false;
    const result: GestureResult = {
      runeSequence: [...this.runeSequence],
      path: [...this.path],
      duration: performance.now() - this.startTime,
    };
    return result;
  }

  cancelGesture() {
    this.active = false;
    this.path = [];
    this.runeSequence = [];
    this.hitRunes = new Set();
  }

  getRuneScreenPosition(runeId: RuneId): { x: number; y: number } {
    const rune = RUNES[runeId];
    return {
      x: rune.position.x * this.canvasWidth,
      y: rune.position.y * this.canvasHeight,
    };
  }

  private checkRuneHits(x: number, y: number) {
    for (const id of RUNE_IDS) {
      if (this.hitRunes.has(id)) continue;

      const pos = this.getRuneScreenPosition(id);
      const dx = x - pos.x;
      const dy = y - pos.y;
      const dist = Math.sqrt(dx * dx + dy * dy);

      if (dist <= RUNE_HIT_RADIUS) {
        this.hitRunes.add(id);
        this.runeSequence.push(id);
      }
    }
  }
}
