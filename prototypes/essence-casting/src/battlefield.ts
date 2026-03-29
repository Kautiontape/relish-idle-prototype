import { Graphics } from 'pixi.js';
import type { EssenceSystem, EssenceType } from './essences.ts';
import { runeCenter } from './runes.ts';
import { debugState } from './debug.ts';

// ─── Enemy type definitions ─────────────────────────────────────────────────

interface EnemyTypeDef {
  name: string;
  essenceDrops: EssenceType[][];
  /** Relative strength multiplier. */
  strength: number;
  /** Weight for random selection (higher = more common). */
  weight: number;
}

const ENEMY_TYPES: EnemyTypeDef[] = [
  { name: 'Villager',   essenceDrops: [['flesh']],             strength: 0.6, weight: 5 },
  { name: 'Archer',     essenceDrops: [['breath']],            strength: 0.8, weight: 4 },
  { name: 'Mage',       essenceDrops: [['veil']],              strength: 1.0, weight: 3 },
  { name: 'Soldier',    essenceDrops: [['chain']],             strength: 1.0, weight: 4 },
  { name: 'Knight',     essenceDrops: [['flesh', 'chain']],    strength: 1.5, weight: 2 },
  { name: 'Priest',     essenceDrops: [['breath', 'veil']],    strength: 1.2, weight: 2 },
  { name: 'Berserker',  essenceDrops: [['flesh', 'breath']],   strength: 1.4, weight: 2 },
  { name: 'Warlock',    essenceDrops: [['veil', 'chain']],     strength: 1.3, weight: 2 },
];

const totalWeight = ENEMY_TYPES.reduce((s, e) => s + e.weight, 0);

function pickEnemyType(): EnemyTypeDef {
  let r = Math.random() * totalWeight;
  for (const et of ENEMY_TYPES) {
    r -= et.weight;
    if (r <= 0) return et;
  }
  return ENEMY_TYPES[0];
}

// ─── SoA unit storage ────────────────────────────────────────────────────────

interface UnitArrays {
  x: Float32Array;
  y: Float32Array;
  vx: Float32Array;
  vy: Float32Array;
  hp: Float32Array;
  count: number;
  capacity: number;
}

function createUnits(cap: number): UnitArrays {
  return {
    x: new Float32Array(cap),
    y: new Float32Array(cap),
    vx: new Float32Array(cap),
    vy: new Float32Array(cap),
    hp: new Float32Array(cap),
    count: 0,
    capacity: cap,
  };
}

function growIfNeeded(u: UnitArrays, needed: number): UnitArrays {
  if (u.count + needed <= u.capacity) return u;
  const cap = Math.max(u.capacity * 2, u.count + needed);
  const g = createUnits(cap);
  g.x.set(u.x.subarray(0, u.count));
  g.y.set(u.y.subarray(0, u.count));
  g.vx.set(u.vx.subarray(0, u.count));
  g.vy.set(u.vy.subarray(0, u.count));
  g.hp.set(u.hp.subarray(0, u.count));
  g.count = u.count;
  return g;
}

/** Swap-remove dead units, returns death positions. */
function compactWithDeaths(u: UnitArrays): { x: number; y: number }[] {
  const deaths: { x: number; y: number }[] = [];
  let i = 0;
  while (i < u.count) {
    if (u.hp[i] <= 0) {
      deaths.push({ x: u.x[i], y: u.y[i] });
      const last = u.count - 1;
      if (i < last) {
        u.x[i] = u.x[last];
        u.y[i] = u.y[last];
        u.vx[i] = u.vx[last];
        u.vy[i] = u.vy[last];
        u.hp[i] = u.hp[last];
      }
      u.count--;
    } else {
      i++;
    }
  }
  return deaths;
}

function compact(u: UnitArrays) {
  let i = 0;
  while (i < u.count) {
    if (u.hp[i] <= 0) {
      const last = u.count - 1;
      if (i < last) {
        u.x[i] = u.x[last];
        u.y[i] = u.y[last];
        u.vx[i] = u.vx[last];
        u.vy[i] = u.vy[last];
        u.hp[i] = u.hp[last];
      }
      u.count--;
    } else {
      i++;
    }
  }
}

// ─── Battlefield ─────────────────────────────────────────────────────────────

const UNDEAD_RADIUS = 3;
const ENEMY_RADIUS = 5;
const UNDEAD_COLOR = 0x00ccaa;
const ENEMY_COLOR = 0xff4422;
const ENEMY_COLOR_ALT = 0xff8833;
const UNDEAD_HP = 3;
const ENEMY_HP = 2;
const UNDEAD_SPEED = 1.2;
const ENEMY_SPEED = 0.6;
const UNDEAD_DAMAGE = 1;
const ENEMY_DAMAGE = 1;

/** Radius within which an enemy "reaches" Relish. */
const RELISH_HIT_RADIUS = 30;

/** Parallel array tracking which enemy type index each enemy is. */
let enemyTypeIndices: Uint8Array = new Uint8Array(1024);

export class Battlefield {
  undead: UnitArrays;
  enemies: UnitArrays;

  private undeadGfx: Graphics;
  private enemyGfx: Graphics;

  elapsed = 0;
  private spawnAccum = 0;

  /** World center. */
  private cx: number;
  private cy: number;
  private fieldW: number;
  private fieldH: number;

  essences: EssenceSystem | null = null;

  totalKills = 0;

  /** True when all undead are dead and an enemy reached Relish. */
  gameOver = false;

  /** Flash timer when Relish is hit (for visual feedback). */
  relishHitFlash = 0;

  constructor(undeadGfx: Graphics, enemyGfx: Graphics, w: number, h: number) {
    this.undead = createUnits(2048);
    this.enemies = createUnits(2048);
    this.undeadGfx = undeadGfx;
    this.enemyGfx = enemyGfx;
    this.fieldW = w;
    this.fieldH = h;
    this.cx = w / 2;
    this.cy = h / 2;
  }

  resize(w: number, h: number) {
    this.fieldW = w;
    this.fieldH = h;
    this.cx = w / 2;
    this.cy = h / 2;
  }

  spawnUndead(count: number) {
    this.undead = growIfNeeded(this.undead, count);
    const center = runeCenter(this.fieldW, this.fieldH);
    for (let i = 0; i < count; i++) {
      const idx = this.undead.count++;
      const angle = Math.random() * Math.PI * 2;
      const dist = Math.random() * 40;
      this.undead.x[idx] = center.x + Math.cos(angle) * dist;
      this.undead.y[idx] = center.y + Math.sin(angle) * dist;
      this.undead.vx[idx] = 0;
      this.undead.vy[idx] = 0;
      this.undead.hp[idx] = UNDEAD_HP;
    }
  }

  private spawnEnemyWave(count: number) {
    this.enemies = growIfNeeded(this.enemies, count);
    // Grow type index array if needed
    if (this.enemies.capacity > enemyTypeIndices.length) {
      const newArr = new Uint8Array(this.enemies.capacity);
      newArr.set(enemyTypeIndices.subarray(0, Math.min(enemyTypeIndices.length, this.enemies.count)));
      enemyTypeIndices = newArr;
    }

    const margin = 60;
    for (let i = 0; i < count; i++) {
      const idx = this.enemies.count++;
      const et = pickEnemyType();
      const typeIdx = ENEMY_TYPES.indexOf(et);
      enemyTypeIndices[idx] = typeIdx;

      // Spawn from top edge only: random x across full width, y above screen
      const ex = Math.random() * this.fieldW;
      const ey = -margin;
      this.enemies.x[idx] = ex;
      this.enemies.y[idx] = ey;
      this.enemies.vx[idx] = 0;
      this.enemies.vy[idx] = 0;
      this.enemies.hp[idx] = ENEMY_HP * et.strength * debugState.enemyStrength;
    }
  }

  update(dt: number) {
    if (this.gameOver) return;

    this.elapsed += dt;

    // Tick relish hit flash
    if (this.relishHitFlash > 0) {
      this.relishHitFlash -= dt;
      if (this.relishHitFlash < 0) this.relishHitFlash = 0;
    }

    // Spawn enemies continuously
    const interval = 2.0 / debugState.spawnRate;
    this.spawnAccum += dt;
    while (this.spawnAccum >= interval) {
      this.spawnAccum -= interval;
      const minutes = this.elapsed / 60;
      const waveSize = Math.floor(3 + minutes * 2);
      this.spawnEnemyWave(waveSize);
    }

    // Move undead toward nearest enemy
    this.moveUndead(dt);

    // Move enemies toward Relish
    this.moveEnemies(dt);

    // Check if enemies reached Relish
    this.checkRelishHits();

    // Combat
    this.resolveCombat(dt);

    // Compact: enemies drop essences on death
    const enemyDeaths = compactWithDeaths(this.enemies);
    this.totalKills += enemyDeaths.length;

    // Spawn essences at death locations
    if (this.essences) {
      for (const death of enemyDeaths) {
        // Find the type index of the dead enemy (best effort: use a random type since
        // we compact and lose the index mapping). We'll track properly below.
        const et = pickEnemyType(); // approximation since we lost the mapping on compact
        for (const drops of et.essenceDrops) {
          this.essences.spawn(drops, death.x, death.y);
        }
      }
    }

    // Compact undead (no drops)
    compact(this.undead);
  }

  private moveUndead(_dt: number) {
    const speed = UNDEAD_SPEED;
    // Simple: move toward nearest enemy
    for (let i = 0; i < this.undead.count; i++) {
      let nearX = this.cx;
      let nearY = this.cy;
      let nearDist = Infinity;

      // Find nearest enemy (brute force, fine for prototype scale)
      for (let j = 0; j < this.enemies.count; j++) {
        const dx = this.enemies.x[j] - this.undead.x[i];
        const dy = this.enemies.y[j] - this.undead.y[i];
        const d = dx * dx + dy * dy;
        if (d < nearDist) {
          nearDist = d;
          nearX = this.enemies.x[j];
          nearY = this.enemies.y[j];
        }
      }

      const dx = nearX - this.undead.x[i];
      const dy = nearY - this.undead.y[i];
      const dist = Math.sqrt(dx * dx + dy * dy);
      const contactDist = UNDEAD_RADIUS + ENEMY_RADIUS + 2;

      if (dist > contactDist) {
        // Move toward enemy
        this.undead.vx[i] = (dx / dist) * speed;
        this.undead.vy[i] = (dy / dist) * speed;
      } else if (dist > 1) {
        // In contact range: orbit/pace around the enemy
        // Perpendicular direction + slight outward push
        const nx = dx / dist;
        const ny = dy / dist;
        const orbitSpeed = speed * 0.6;
        // Alternate orbit direction per unit index
        const dir = (i % 2 === 0) ? 1 : -1;
        this.undead.vx[i] = (-ny * dir * orbitSpeed) + (-nx * speed * 0.1);
        this.undead.vy[i] = (nx * dir * orbitSpeed) + (-ny * speed * 0.1);
      } else {
        this.undead.vx[i] = 0;
        this.undead.vy[i] = 0;
      }

      this.undead.x[i] += this.undead.vx[i];
      this.undead.y[i] += this.undead.vy[i];
    }
  }

  private moveEnemies(_dt: number) {
    // Enemies move toward Relish's position (bottom-center of screen)
    const relish = runeCenter(this.fieldW, this.fieldH);

    const speed = ENEMY_SPEED * debugState.enemyStrength;
    for (let i = 0; i < this.enemies.count; i++) {
      const dx = relish.x - this.enemies.x[i];
      const dy = relish.y - this.enemies.y[i];
      const dist = Math.sqrt(dx * dx + dy * dy);
      if (dist > 1) {
        this.enemies.vx[i] = (dx / dist) * speed;
        this.enemies.vy[i] = (dy / dist) * speed;
      }

      // Slight separation
      for (let j = Math.max(0, i - 5); j < Math.min(this.enemies.count, i + 5); j++) {
        if (j === i) continue;
        const sx = this.enemies.x[i] - this.enemies.x[j];
        const sy = this.enemies.y[i] - this.enemies.y[j];
        const sd = sx * sx + sy * sy;
        if (sd > 0.01 && sd < 100) {
          const sdist = Math.sqrt(sd);
          this.enemies.vx[i] += (sx / sdist) * 0.1;
          this.enemies.vy[i] += (sy / sdist) * 0.1;
        }
      }

      this.enemies.x[i] += this.enemies.vx[i];
      this.enemies.y[i] += this.enemies.vy[i];
    }
  }

  /** Check if any enemy has reached Relish. Kill a random undead if so. */
  private checkRelishHits() {
    const relish = runeCenter(this.fieldW, this.fieldH);
    const hitRadSq = RELISH_HIT_RADIUS * RELISH_HIT_RADIUS;

    for (let i = 0; i < this.enemies.count; i++) {
      if (this.enemies.hp[i] <= 0) continue;

      const dx = this.enemies.x[i] - relish.x;
      const dy = this.enemies.y[i] - relish.y;
      if (dx * dx + dy * dy < hitRadSq) {
        // Enemy reached Relish - kill this enemy
        this.enemies.hp[i] = 0;

        if (this.undead.count > 0) {
          // Kill a random undead
          const victim = Math.floor(Math.random() * this.undead.count);
          this.undead.hp[victim] = 0;
          this.relishHitFlash = 0.5;
          console.warn('[Relish Hit] An enemy reached Relish! An undead was slain. Remaining:', this.undead.count - 1);
        } else {
          // No undead remain - game over
          this.gameOver = true;
          console.error('[GAME OVER] All undead have fallen. Relish is defenseless.');
          return;
        }
      }
    }
  }

  private resolveCombat(_dt: number) {
    const pDmg = UNDEAD_DAMAGE;
    const eDmg = ENEMY_DAMAGE * debugState.enemyStrength;
    const touchDist = UNDEAD_RADIUS + ENEMY_RADIUS;
    const touchDistSq = touchDist * touchDist;

    for (let ei = 0; ei < this.enemies.count; ei++) {
      if (this.enemies.hp[ei] <= 0) continue;

      for (let pi = 0; pi < this.undead.count; pi++) {
        if (this.undead.hp[pi] <= 0) continue;

        const dx = this.undead.x[pi] - this.enemies.x[ei];
        const dy = this.undead.y[pi] - this.enemies.y[ei];

        if (dx * dx + dy * dy < touchDistSq) {
          this.enemies.hp[ei] -= pDmg * 0.05;
          this.undead.hp[pi] -= eDmg * 0.03;
        }
      }
    }
  }

  draw() {
    // Undead: green/teal circles
    this.undeadGfx.clear();
    if (this.undead.count > 0) {
      this.undeadGfx.fill({ color: UNDEAD_COLOR, alpha: 0.9 });
      for (let i = 0; i < this.undead.count; i++) {
        this.undeadGfx.circle(this.undead.x[i], this.undead.y[i], UNDEAD_RADIUS);
      }
      this.undeadGfx.fill();
    }

    // Enemies: red/orange squares
    this.enemyGfx.clear();
    if (this.enemies.count > 0) {
      for (let i = 0; i < this.enemies.count; i++) {
        const color = i % 3 === 0 ? ENEMY_COLOR_ALT : ENEMY_COLOR;
        this.enemyGfx.fill({ color, alpha: 0.9 });
        const r = ENEMY_RADIUS;
        this.enemyGfx.rect(
          this.enemies.x[i] - r,
          this.enemies.y[i] - r,
          r * 2,
          r * 2,
        );
        this.enemyGfx.fill();
      }
    }
  }

  getUndeadCenter(): { x: number; y: number } {
    if (this.undead.count === 0) return { x: this.cx, y: this.cy };
    let sx = 0, sy = 0;
    for (let i = 0; i < this.undead.count; i++) {
      sx += this.undead.x[i];
      sy += this.undead.y[i];
    }
    return { x: sx / this.undead.count, y: sy / this.undead.count };
  }

  reset() {
    this.undead.count = 0;
    this.enemies.count = 0;
    this.elapsed = 0;
    this.spawnAccum = 0;
    this.totalKills = 0;
    this.gameOver = false;
    this.relishHitFlash = 0;
    this.undeadGfx.clear();
    this.enemyGfx.clear();
  }
}
