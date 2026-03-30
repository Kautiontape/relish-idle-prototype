import { Graphics } from 'pixi.js';
import type { EssenceSystem, EssenceType } from './essences.ts';
import { runeCenter } from './runes.ts';
import { debugState } from './debug.ts';
import type { ArchetypeDefinition, BehaviorTag } from './spells.ts';

// ─── Helpers ────────────────────────────────────────────────────────────────

function hasBehavior(behaviors: BehaviorTag[], type: string): boolean {
  return behaviors.some(b => b.type === type);
}

function getBehavior<T extends BehaviorTag['type']>(
  behaviors: BehaviorTag[],
  type: T,
): Extract<BehaviorTag, { type: T }> | undefined {
  return behaviors.find(b => b.type === type) as Extract<BehaviorTag, { type: T }> | undefined;
}

function parseHexColor(hex: string): number {
  return parseInt(hex.replace('#', ''), 16);
}

// ─── Enemy type definitions ─────────────────────────────────────────────────

interface EnemyTypeDef {
  name: string;
  essenceDrops: EssenceType[][];
  strength: number;
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

// ─── Enemy SoA storage ─────────────────────────────────────────────────────

interface EnemySoA {
  x: Float32Array;
  y: Float32Array;
  vx: Float32Array;
  vy: Float32Array;
  hp: Float32Array;
  maxHp: Float32Array;
  slowTimer: Float32Array;
  slowPercent: Float32Array;
  rootTimer: Float32Array;
  tauntTarget: Int32Array; // index of undead taunting this enemy, -1 = none
  count: number;
  capacity: number;
}

function createEnemies(cap: number): EnemySoA {
  return {
    x: new Float32Array(cap),
    y: new Float32Array(cap),
    vx: new Float32Array(cap),
    vy: new Float32Array(cap),
    hp: new Float32Array(cap),
    maxHp: new Float32Array(cap),
    slowTimer: new Float32Array(cap),
    slowPercent: new Float32Array(cap),
    rootTimer: new Float32Array(cap),
    tauntTarget: new Int32Array(cap).fill(-1),
    count: 0,
    capacity: cap,
  };
}

function growEnemies(u: EnemySoA, needed: number): EnemySoA {
  if (u.count + needed <= u.capacity) return u;
  const cap = Math.max(u.capacity * 2, u.count + needed);
  const g = createEnemies(cap);
  const n = u.count;
  g.x.set(u.x.subarray(0, n));
  g.y.set(u.y.subarray(0, n));
  g.vx.set(u.vx.subarray(0, n));
  g.vy.set(u.vy.subarray(0, n));
  g.hp.set(u.hp.subarray(0, n));
  g.maxHp.set(u.maxHp.subarray(0, n));
  g.slowTimer.set(u.slowTimer.subarray(0, n));
  g.slowPercent.set(u.slowPercent.subarray(0, n));
  g.rootTimer.set(u.rootTimer.subarray(0, n));
  g.tauntTarget.set(u.tauntTarget.subarray(0, n));
  g.count = n;
  return g;
}

// ─── Undead AoS unit ────────────────────────────────────────────────────────

interface UndeadUnit {
  x: number; y: number;
  vx: number; vy: number;
  hp: number; maxHp: number;
  damage: number;
  speed: number;
  size: number;
  color: number;
  behaviors: BehaviorTag[];
  // Per-behavior state
  ambushReady: boolean;
  rageDmgMult: number;
  devourDmgBuff: number;
  devourBuffTimer: number;
  killCount: number;
  spawnTimer: number;
  resurrectTimer: number;
  invulnTimer: number;
  teleportCooldown: number;
  teleportReturnX: number;
  teleportReturnY: number;
  teleportAttacking: boolean;
  teleportAttackTimer: number;
  decoyCooldown: number;
  // Visual flash timers
  healFlash: number;
  dodgeFlash: number;
  ambushFlash: number;
}

// ─── Simple particle for visual effects ─────────────────────────────────────

interface Particle {
  x: number; y: number;
  vx: number; vy: number;
  life: number;
  maxLife: number;
  color: number;
  size: number;
}

// ─── Constants ──────────────────────────────────────────────────────────────

const BASE_RADIUS = 3;
const ENEMY_RADIUS = 5;
const UNDEAD_COLOR = 0x00ccaa;
const ENEMY_COLOR = 0xff4422;
const ENEMY_COLOR_ALT = 0xff8833;
const BASE_HP = 3;
const ENEMY_HP = 2;
const BASE_SPEED = 1.2;
const ENEMY_SPEED = 0.6;
const BASE_DAMAGE = 1;
const ENEMY_DAMAGE = 1;

const RELISH_HIT_RADIUS = 30;

let enemyTypeIndices: Uint8Array = new Uint8Array(1024);

// Track recent undead deaths for resurrect behavior
let recentUndeadDeathCount = 0;

// ─── Battlefield ────────────────────────────────────────────────────────────

export class Battlefield {
  undead: UndeadUnit[] = [];
  enemies: EnemySoA;

  private undeadGfx: Graphics;
  private enemyGfx: Graphics;
  private fxGfx: Graphics;

  private particles: Particle[] = [];

  elapsed = 0;
  private spawnAccum = 0;

  private cx: number;
  private cy: number;
  private fieldW: number;
  private fieldH: number;

  essences: EssenceSystem | null = null;

  totalKills = 0;

  gameOver = false;
  relishHitFlash = 0;

  constructor(undeadGfx: Graphics, enemyGfx: Graphics, fxGfx: Graphics, w: number, h: number) {
    this.enemies = createEnemies(2048);
    this.undeadGfx = undeadGfx;
    this.enemyGfx = enemyGfx;
    this.fxGfx = fxGfx;
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

  /** Spawn basic undead with default stats (for starting units). */
  spawnUndead(count: number) {
    const center = runeCenter(this.fieldW, this.fieldH);
    for (let i = 0; i < count; i++) {
      const angle = Math.random() * Math.PI * 2;
      const dist = Math.random() * 40;
      this.undead.push(this.createUnit(
        center.x + Math.cos(angle) * dist,
        center.y + Math.sin(angle) * dist,
        BASE_HP * debugState.undeadHpMult, BASE_DAMAGE * debugState.undeadDmgMult,
        BASE_SPEED * debugState.undeadSpeedMult, BASE_RADIUS,
        UNDEAD_COLOR, [],
      ));
    }
  }

  /** Spawn an undead from an archetype definition. */
  spawnUndeadFromArchetype(arch: ArchetypeDefinition) {
    const center = runeCenter(this.fieldW, this.fieldH);
    const angle = Math.random() * Math.PI * 2;
    const dist = Math.random() * 40;
    const hp = BASE_HP * arch.stats.health * debugState.undeadHpMult;
    const dmg = BASE_DAMAGE * arch.stats.damage * debugState.undeadDmgMult;
    const spd = BASE_SPEED * arch.stats.speed * debugState.undeadSpeedMult;
    const sz = BASE_RADIUS * arch.stats.size;
    const color = parseHexColor(arch.color);
    const unit = this.createUnit(
      center.x + Math.cos(angle) * dist,
      center.y + Math.sin(angle) * dist,
      hp, dmg, spd, sz, color, arch.behaviors,
    );
    // invulnerable_on_spawn
    const invuln = getBehavior(arch.behaviors, 'invulnerable_on_spawn');
    if (invuln) unit.invulnTimer = invuln.duration;
    this.undead.push(unit);

    // Spawn visual: small pop
    this.spawnParticles(unit.x, unit.y, color, 4, 1.0);
  }

  private createUnit(
    x: number, y: number,
    hp: number, damage: number, speed: number, size: number,
    color: number, behaviors: BehaviorTag[],
  ): UndeadUnit {
    return {
      x, y, vx: 0, vy: 0,
      hp, maxHp: hp, damage, speed, size, color,
      behaviors,
      ambushReady: hasBehavior(behaviors, 'ambush'),
      rageDmgMult: 1,
      devourDmgBuff: 0,
      devourBuffTimer: 0,
      killCount: 0,
      spawnTimer: 0,
      resurrectTimer: 0,
      invulnTimer: 0,
      teleportCooldown: 0,
      teleportReturnX: 0, teleportReturnY: 0,
      teleportAttacking: false, teleportAttackTimer: 0,
      decoyCooldown: 0,
      healFlash: 0, dodgeFlash: 0, ambushFlash: 0,
    };
  }

  private spawnEnemyWave(count: number) {
    this.enemies = growEnemies(this.enemies, count);
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

      const ex = Math.random() * this.fieldW;
      const ey = -margin;
      this.enemies.x[idx] = ex;
      this.enemies.y[idx] = ey;
      this.enemies.vx[idx] = 0;
      this.enemies.vy[idx] = 0;
      const hpVal = ENEMY_HP * et.strength * debugState.enemyStrength * debugState.enemyHpMult;
      this.enemies.hp[idx] = hpVal;
      this.enemies.maxHp[idx] = hpVal;
      this.enemies.slowTimer[idx] = 0;
      this.enemies.slowPercent[idx] = 0;
      this.enemies.rootTimer[idx] = 0;
      this.enemies.tauntTarget[idx] = -1;
    }
  }

  // ─── Update ─────────────────────────────────────────────────────────────

  update(dt: number) {
    if (this.gameOver) return;

    this.elapsed += dt;

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

    // Tick enemy debuff timers
    this.tickEnemyTimers(dt);

    // Tick undead behavior timers & per-frame effects
    this.tickUndeadBehaviors(dt);

    // Move undead toward nearest enemy
    this.moveUndead(dt);

    // Move enemies toward Relish
    this.moveEnemies(dt);

    // Check if enemies reached Relish
    this.checkRelishHits();

    // Combat
    this.resolveCombat(dt);

    // Aura effects (damage_aura, aoe_slow, etc.)
    this.resolveAuras(dt);

    // Compact dead enemies, spawn essences
    const enemyDeaths = this.compactEnemies();
    this.totalKills += enemyDeaths.length;

    if (this.essences) {
      for (const death of enemyDeaths) {
        const et = pickEnemyType();
        for (const drops of et.essenceDrops) {
          this.essences.spawn(drops, death.x, death.y);
        }
      }
    }

    // Compact dead undead
    this.compactUndead();

    // Tick particles
    this.tickParticles(dt);
  }

  private tickEnemyTimers(dt: number) {
    for (let i = 0; i < this.enemies.count; i++) {
      if (this.enemies.slowTimer[i] > 0) {
        this.enemies.slowTimer[i] -= dt;
        if (this.enemies.slowTimer[i] <= 0) {
          this.enemies.slowTimer[i] = 0;
          this.enemies.slowPercent[i] = 0;
        }
      }
      if (this.enemies.rootTimer[i] > 0) {
        this.enemies.rootTimer[i] -= dt;
        if (this.enemies.rootTimer[i] < 0) this.enemies.rootTimer[i] = 0;
      }
      // Clear taunt targets if the taunter is dead/gone
      const tt = this.enemies.tauntTarget[i];
      if (tt >= 0 && (tt >= this.undead.length || this.undead[tt].hp <= 0)) {
        this.enemies.tauntTarget[i] = -1;
      }
    }
  }

  private tickUndeadBehaviors(dt: number) {
    for (const u of this.undead) {
      if (u.hp <= 0) continue;

      // Tick visual flash timers
      if (u.healFlash > 0) u.healFlash -= dt;
      if (u.dodgeFlash > 0) u.dodgeFlash -= dt;
      if (u.ambushFlash > 0) u.ambushFlash -= dt;

      // invulnerable_on_spawn timer
      if (u.invulnTimer > 0) u.invulnTimer -= dt;

      // teleport cooldown
      if (u.teleportCooldown > 0) u.teleportCooldown -= dt;

      // decoy cooldown
      if (u.decoyCooldown > 0) u.decoyCooldown -= dt;

      // devour buff timer
      if (u.devourBuffTimer > 0) {
        u.devourBuffTimer -= dt;
        if (u.devourBuffTimer <= 0) {
          u.devourBuffTimer = 0;
          u.devourDmgBuff = 0;
        }
      }

      // regen
      const regen = getBehavior(u.behaviors, 'regen');
      if (regen) {
        const healed = regen.hpPerSecond * dt;
        u.hp = Math.min(u.maxHp, u.hp + healed);
      }

      // rage: attack speed bonus based on missing HP
      if (hasBehavior(u.behaviors, 'rage')) {
        const rageBeh = getBehavior(u.behaviors, 'rage')!;
        const hpPercent = u.hp / u.maxHp;
        // More damage as HP drops: at 0% HP = full bonus
        u.rageDmgMult = 1 + rageBeh.maxAttackSpeedBonus * (1 - hpPercent);
      }

      // spawn_minions
      const spawner = getBehavior(u.behaviors, 'spawn_minions');
      if (spawner) {
        u.spawnTimer += dt;
        if (u.spawnTimer >= spawner.interval) {
          u.spawnTimer -= spawner.interval;
          // Spawn a tiny basic undead nearby
          const angle = Math.random() * Math.PI * 2;
          const minion = this.createUnit(
            u.x + Math.cos(angle) * 15,
            u.y + Math.sin(angle) * 15,
            BASE_HP * 0.5, BASE_DAMAGE * 0.5, BASE_SPEED, BASE_RADIUS * 0.6,
            u.color, [],
          );
          this.undead.push(minion);
          this.spawnParticles(minion.x, minion.y, u.color, 3, 0.5);
        }
      }

      // resurrect_nearby
      const resurrect = getBehavior(u.behaviors, 'resurrect_nearby');
      if (resurrect) {
        u.resurrectTimer += dt;
        if (u.resurrectTimer >= resurrect.cooldown && recentUndeadDeathCount > 0) {
          u.resurrectTimer = 0;
          recentUndeadDeathCount--;
          const angle = Math.random() * Math.PI * 2;
          const minion = this.createUnit(
            u.x + Math.cos(angle) * 20,
            u.y + Math.sin(angle) * 20,
            BASE_HP * 0.6, BASE_DAMAGE * 0.6, BASE_SPEED, BASE_RADIUS * 0.7,
            0x88ffaa, [],
          );
          this.undead.push(minion);
          // Upward sparkle
          for (let p = 0; p < 5; p++) {
            this.particles.push({
              x: minion.x + (Math.random() - 0.5) * 10,
              y: minion.y,
              vx: (Math.random() - 0.5) * 20,
              vy: -40 - Math.random() * 30,
              life: 0.6, maxLife: 0.6,
              color: 0xaaffcc, size: 2,
            });
          }
        }
      }

      // teleport_attack: return after attack
      if (u.teleportAttacking) {
        u.teleportAttackTimer -= dt;
        if (u.teleportAttackTimer <= 0) {
          // Teleport back
          this.spawnParticles(u.x, u.y, u.color, 2, 0.3);
          u.x = u.teleportReturnX;
          u.y = u.teleportReturnY;
          u.teleportAttacking = false;
          this.spawnParticles(u.x, u.y, u.color, 2, 0.3);
        }
      }

      // taunt: mark nearby enemies to target this unit
      const tauntBeh = getBehavior(u.behaviors, 'taunt');
      if (tauntBeh) {
        const rSq = tauntBeh.radius * tauntBeh.radius;
        const uIdx = this.undead.indexOf(u);
        for (let ei = 0; ei < this.enemies.count; ei++) {
          const dx = this.enemies.x[ei] - u.x;
          const dy = this.enemies.y[ei] - u.y;
          if (dx * dx + dy * dy < rSq) {
            this.enemies.tauntTarget[ei] = uIdx;
          }
        }
      }
    }
  }

  private moveUndead(_dt: number) {
    for (const u of this.undead) {
      if (u.hp <= 0) continue;

      // Stationary units don't move
      if (hasBehavior(u.behaviors, 'stationary')) {
        u.vx = 0;
        u.vy = 0;
        continue;
      }

      // Teleporting units don't move normally while attacking
      if (u.teleportAttacking) continue;

      const speed = u.speed;

      // teleport_attack: find nearest enemy, teleport to it
      if (hasBehavior(u.behaviors, 'teleport_attack') && u.teleportCooldown <= 0 && this.enemies.count > 0) {
        let nearIdx = -1;
        let nearDist = Infinity;
        for (let j = 0; j < this.enemies.count; j++) {
          const dx = this.enemies.x[j] - u.x;
          const dy = this.enemies.y[j] - u.y;
          const d = dx * dx + dy * dy;
          if (d < nearDist) { nearDist = d; nearIdx = j; }
        }
        if (nearIdx >= 0 && nearDist > (u.size + ENEMY_RADIUS + 5) ** 2) {
          // Teleport to enemy
          u.teleportReturnX = u.x;
          u.teleportReturnY = u.y;
          this.spawnParticles(u.x, u.y, u.color, 3, 0.4);
          u.x = this.enemies.x[nearIdx] + (Math.random() - 0.5) * 10;
          u.y = this.enemies.y[nearIdx] + (Math.random() - 0.5) * 10;
          u.teleportAttacking = true;
          u.teleportAttackTimer = 0.3;
          u.teleportCooldown = 2.0;
          this.spawnParticles(u.x, u.y, 0xffffff, 3, 0.4);
          continue;
        }
      }

      // Find nearest enemy
      let nearX = this.cx;
      let nearY = this.cy;
      let nearDist = Infinity;

      for (let j = 0; j < this.enemies.count; j++) {
        const dx = this.enemies.x[j] - u.x;
        const dy = this.enemies.y[j] - u.y;
        const d = dx * dx + dy * dy;
        if (d < nearDist) { nearDist = d; nearX = this.enemies.x[j]; nearY = this.enemies.y[j]; }
      }

      const dx = nearX - u.x;
      const dy = nearY - u.y;
      const dist = Math.sqrt(dx * dx + dy * dy);
      const contactDist = u.size + ENEMY_RADIUS + 2;

      if (dist > contactDist) {
        u.vx = (dx / dist) * speed;
        u.vy = (dy / dist) * speed;
      } else if (dist > 1) {
        const nx = dx / dist;
        const ny = dy / dist;
        const orbitSpeed = speed * 0.6;
        const dir = (this.undead.indexOf(u) % 2 === 0) ? 1 : -1;
        u.vx = (-ny * dir * orbitSpeed) + (-nx * speed * 0.1);
        u.vy = (nx * dir * orbitSpeed) + (-ny * speed * 0.1);
      } else {
        u.vx = 0;
        u.vy = 0;
      }

      u.x += u.vx;
      u.y += u.vy;
    }
  }

  private moveEnemies(_dt: number) {
    const relish = runeCenter(this.fieldW, this.fieldH);
    const baseSpeed = ENEMY_SPEED * debugState.enemySpeedMult;

    for (let i = 0; i < this.enemies.count; i++) {
      // Rooted enemies can't move
      if (this.enemies.rootTimer[i] > 0) continue;

      // Determine target: taunt target or Relish
      let targetX = relish.x;
      let targetY = relish.y;
      const tt = this.enemies.tauntTarget[i];
      if (tt >= 0 && tt < this.undead.length && this.undead[tt].hp > 0) {
        targetX = this.undead[tt].x;
        targetY = this.undead[tt].y;
      }

      const dx = targetX - this.enemies.x[i];
      const dy = targetY - this.enemies.y[i];
      const dist = Math.sqrt(dx * dx + dy * dy);

      // Apply slow
      const slowMult = 1 - this.enemies.slowPercent[i];
      const speed = baseSpeed * slowMult;

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

  private checkRelishHits() {
    const relish = runeCenter(this.fieldW, this.fieldH);
    const hitRadSq = RELISH_HIT_RADIUS * RELISH_HIT_RADIUS;

    for (let i = 0; i < this.enemies.count; i++) {
      if (this.enemies.hp[i] <= 0) continue;

      const dx = this.enemies.x[i] - relish.x;
      const dy = this.enemies.y[i] - relish.y;
      if (dx * dx + dy * dy < hitRadSq) {
        this.enemies.hp[i] = 0;

        if (this.undead.length > 0) {
          const aliveIndices = this.undead.map((u, idx) => u.hp > 0 ? idx : -1).filter(i => i >= 0);
          if (aliveIndices.length > 0) {
            const victim = aliveIndices[Math.floor(Math.random() * aliveIndices.length)];
            this.undead[victim].hp = 0;
            this.relishHitFlash = 0.5;
          } else {
            this.gameOver = true;
            return;
          }
        } else {
          this.gameOver = true;
          return;
        }
      }
    }
  }

  private resolveCombat(dt: number) {
    const basePDmg = BASE_DAMAGE;
    const baseEDmg = ENEMY_DAMAGE * debugState.enemyDmgMult;

    for (let ei = 0; ei < this.enemies.count; ei++) {
      if (this.enemies.hp[ei] <= 0) continue;

      for (let pi = 0; pi < this.undead.length; pi++) {
        const u = this.undead[pi];
        if (u.hp <= 0) continue;

        const dx = u.x - this.enemies.x[ei];
        const dy = u.y - this.enemies.y[ei];
        const touchDist = u.size + ENEMY_RADIUS;
        const touchDistSq = touchDist * touchDist;

        if (dx * dx + dy * dy < touchDistSq) {
          // ─── Undead attacks enemy ───
          let pDmg = u.damage;

          // Rage multiplier
          pDmg *= u.rageDmgMult;

          // Devour damage buff
          pDmg += u.devourDmgBuff;

          // Scaling on kill bonus
          const scalingBeh = getBehavior(u.behaviors, 'scaling_on_kill');
          if (scalingBeh) {
            pDmg += u.killCount * scalingBeh.damagePerKill;
          }

          // Ambush first hit
          if (u.ambushReady) {
            const ambushBeh = getBehavior(u.behaviors, 'ambush');
            if (ambushBeh) {
              pDmg *= ambushBeh.damageMultiplier;
              u.ambushReady = false;
              u.ambushFlash = 0.3;
            }
          }

          // Ally buff auras from nearby undead
          for (const ally of this.undead) {
            if (ally === u || ally.hp <= 0) continue;
            const auraBuff = getBehavior(ally.behaviors, 'aura_ally_buff');
            if (auraBuff) {
              const adx = ally.x - u.x;
              const ady = ally.y - u.y;
              if (adx * adx + ady * ady < auraBuff.radius * auraBuff.radius) {
                pDmg *= (1 + auraBuff.damageBuff);
              }
            }
          }

          const actualDmg = pDmg * 0.05 * dt * 60;
          const prevHp = this.enemies.hp[ei];
          this.enemies.hp[ei] -= actualDmg;

          // Check for kill
          if (prevHp > 0 && this.enemies.hp[ei] <= 0) {
            // Devour: heal and buff on kill
            const devourBeh = getBehavior(u.behaviors, 'devour');
            if (devourBeh) {
              u.hp = Math.min(u.maxHp, u.hp + u.maxHp * devourBeh.healPercent);
              u.devourDmgBuff = devourBeh.damageBuff * basePDmg;
              u.devourBuffTimer = devourBeh.buffDuration;
              u.healFlash = 0.3;
            }

            // Scaling on kill
            if (scalingBeh) {
              u.killCount++;
              // Visual: unit gets slightly larger
              u.size += 0.15;
            }
          }

          // Life steal
          const lifeStealBeh = getBehavior(u.behaviors, 'life_steal');
          if (lifeStealBeh) {
            const healed = actualDmg * lifeStealBeh.percent;
            u.hp = Math.min(u.maxHp, u.hp + healed);
            if (healed > 0.01) u.healFlash = 0.15;
          }

          // Slow on hit
          const slowBeh = getBehavior(u.behaviors, 'slow_on_hit');
          if (slowBeh) {
            this.enemies.slowTimer[ei] = slowBeh.duration;
            this.enemies.slowPercent[ei] = Math.max(this.enemies.slowPercent[ei], slowBeh.percent);
          }

          // Root on hit
          const rootBeh = getBehavior(u.behaviors, 'root_on_hit');
          if (rootBeh) {
            this.enemies.rootTimer[ei] = Math.max(this.enemies.rootTimer[ei], rootBeh.duration);
          }

          // Knockback
          const knockBeh = getBehavior(u.behaviors, 'knockback');
          if (knockBeh) {
            const kDist = Math.sqrt(dx * dx + dy * dy);
            if (kDist > 0.1) {
              const kx = -dx / kDist;
              const ky = -dy / kDist;
              this.enemies.x[ei] += kx * knockBeh.distance * 0.05;
              this.enemies.y[ei] += ky * knockBeh.distance * 0.05;
            }
          }

          // ─── Enemy attacks undead ───
          let eDmg = baseEDmg * 0.03 * dt * 60;

          // Miss aura from nearby undead
          for (const ally of this.undead) {
            if (ally.hp <= 0) continue;
            const missBeh = getBehavior(ally.behaviors, 'miss_aura');
            if (missBeh) {
              const mdx = ally.x - this.enemies.x[ei];
              const mdy = ally.y - this.enemies.y[ei];
              if (mdx * mdx + mdy * mdy < missBeh.radius * missBeh.radius) {
                if (Math.random() < missBeh.chance) {
                  eDmg = 0; // Miss!
                  break;
                }
              }
            }
          }

          // Protection aura from nearby undead
          for (const ally of this.undead) {
            if (ally.hp <= 0) continue;
            const protBeh = getBehavior(ally.behaviors, 'protection_aura');
            if (protBeh) {
              const pdx = ally.x - u.x;
              const pdy = ally.y - u.y;
              if (pdx * pdx + pdy * pdy < protBeh.radius * protBeh.radius) {
                eDmg *= (1 - protBeh.reduction);
              }
            }
          }

          // Enemy debuff aura: reduce enemy attack damage
          for (const ally of this.undead) {
            if (ally.hp <= 0) continue;
            const debuffBeh = getBehavior(ally.behaviors, 'aura_enemy_debuff');
            if (debuffBeh) {
              const ddx = ally.x - this.enemies.x[ei];
              const ddy = ally.y - this.enemies.y[ei];
              if (ddx * ddx + ddy * ddy < debuffBeh.radius * debuffBeh.radius) {
                eDmg *= (1 - debuffBeh.attackSpeedReduction);
              }
            }
          }

          // Invulnerable check
          if (u.invulnTimer > 0) {
            eDmg = 0;
          }

          // Fortified: damage reduction
          const fortBeh = getBehavior(u.behaviors, 'fortified');
          if (fortBeh) {
            eDmg *= (1 - fortBeh.damageReduction);
          }

          // Dodge
          const dodgeBeh = getBehavior(u.behaviors, 'dodge');
          if (dodgeBeh && eDmg > 0) {
            if (Math.random() < dodgeBeh.chance) {
              eDmg = 0;
              u.dodgeFlash = 0.15;
            }
          }

          // Apply damage to undead
          if (eDmg > 0) {
            u.hp -= eDmg;

            // Decoy on hit
            const decoyBeh = getBehavior(u.behaviors, 'decoy_on_hit');
            if (decoyBeh && u.decoyCooldown <= 0) {
              u.decoyCooldown = 3.0;
              const dAngle = Math.random() * Math.PI * 2;
              const decoy = this.createUnit(
                u.x + Math.cos(dAngle) * 15,
                u.y + Math.sin(dAngle) * 15,
                decoyBeh.decoyHP * 0.1, u.damage * 0.3, u.speed, u.size * 0.7,
                u.color, [],
              );
              this.undead.push(decoy);
              this.spawnParticles(decoy.x, decoy.y, u.color, 3, 0.4);
            }
          }
        }
      }
    }
  }

  private resolveAuras(dt: number) {
    for (const u of this.undead) {
      if (u.hp <= 0) continue;

      // life_tether: damage nearest enemy in short range
      const tetherBeh = getBehavior(u.behaviors, 'life_tether');
      if (tetherBeh) {
        let nearIdx = -1;
        let nearDist = Infinity;
        const tetherRange = 60;
        for (let ei = 0; ei < this.enemies.count; ei++) {
          if (this.enemies.hp[ei] <= 0) continue;
          const dx = this.enemies.x[ei] - u.x;
          const dy = this.enemies.y[ei] - u.y;
          const d = dx * dx + dy * dy;
          if (d < nearDist && d < tetherRange * tetherRange) {
            nearDist = d;
            nearIdx = ei;
          }
        }
        if (nearIdx >= 0) {
          this.enemies.hp[nearIdx] -= tetherBeh.dps * dt;
        }
      }

      // damage_aura: damage all enemies in radius
      const dmgAuraBeh = getBehavior(u.behaviors, 'damage_aura');
      if (dmgAuraBeh) {
        const rSq = dmgAuraBeh.radius * dmgAuraBeh.radius;
        for (let ei = 0; ei < this.enemies.count; ei++) {
          if (this.enemies.hp[ei] <= 0) continue;
          const dx = this.enemies.x[ei] - u.x;
          const dy = this.enemies.y[ei] - u.y;
          if (dx * dx + dy * dy < rSq) {
            this.enemies.hp[ei] -= dmgAuraBeh.dps * dt;
          }
        }
      }

      // aoe_slow: slow all enemies in radius
      const aoeSlow = getBehavior(u.behaviors, 'aoe_slow');
      if (aoeSlow) {
        const rSq = aoeSlow.radius * aoeSlow.radius;
        for (let ei = 0; ei < this.enemies.count; ei++) {
          if (this.enemies.hp[ei] <= 0) continue;
          const dx = this.enemies.x[ei] - u.x;
          const dy = this.enemies.y[ei] - u.y;
          if (dx * dx + dy * dy < rSq) {
            this.enemies.slowPercent[ei] = Math.max(this.enemies.slowPercent[ei], aoeSlow.percent);
            this.enemies.slowTimer[ei] = Math.max(this.enemies.slowTimer[ei], 0.5);
          }
        }
      }
    }
  }

  private compactEnemies(): { x: number; y: number }[] {
    const deaths: { x: number; y: number }[] = [];
    let i = 0;
    while (i < this.enemies.count) {
      if (this.enemies.hp[i] <= 0) {
        deaths.push({ x: this.enemies.x[i], y: this.enemies.y[i] });
        const last = this.enemies.count - 1;
        if (i < last) {
          this.enemies.x[i] = this.enemies.x[last];
          this.enemies.y[i] = this.enemies.y[last];
          this.enemies.vx[i] = this.enemies.vx[last];
          this.enemies.vy[i] = this.enemies.vy[last];
          this.enemies.hp[i] = this.enemies.hp[last];
          this.enemies.maxHp[i] = this.enemies.maxHp[last];
          this.enemies.slowTimer[i] = this.enemies.slowTimer[last];
          this.enemies.slowPercent[i] = this.enemies.slowPercent[last];
          this.enemies.rootTimer[i] = this.enemies.rootTimer[last];
          this.enemies.tauntTarget[i] = this.enemies.tauntTarget[last];
          enemyTypeIndices[i] = enemyTypeIndices[last];
        }
        this.enemies.count--;
      } else {
        i++;
      }
    }
    return deaths;
  }

  private compactUndead() {
    for (let i = this.undead.length - 1; i >= 0; i--) {
      const u = this.undead[i];
      if (u.hp <= 0) {
        // death_explode
        const deathBeh = getBehavior(u.behaviors, 'death_explode');
        if (deathBeh) {
          const rSq = deathBeh.radius * deathBeh.radius;
          for (let ei = 0; ei < this.enemies.count; ei++) {
            if (this.enemies.hp[ei] <= 0) continue;
            const dx = this.enemies.x[ei] - u.x;
            const dy = this.enemies.y[ei] - u.y;
            if (dx * dx + dy * dy < rSq) {
              this.enemies.hp[ei] -= deathBeh.damage;
            }
          }
          // Explosion particles
          this.spawnParticles(u.x, u.y, u.color, 12, 1.0);
        }

        recentUndeadDeathCount++;
        this.undead.splice(i, 1);
      }
    }
  }

  // ─── Particles ──────────────────────────────────────────────────────────

  private spawnParticles(x: number, y: number, color: number, count: number, life: number) {
    for (let i = 0; i < count; i++) {
      const angle = Math.random() * Math.PI * 2;
      const speed = 20 + Math.random() * 40;
      this.particles.push({
        x, y,
        vx: Math.cos(angle) * speed,
        vy: Math.sin(angle) * speed,
        life, maxLife: life,
        color, size: 2,
      });
    }
  }

  private tickParticles(dt: number) {
    for (let i = this.particles.length - 1; i >= 0; i--) {
      const p = this.particles[i];
      p.life -= dt;
      if (p.life <= 0) {
        this.particles.splice(i, 1);
        continue;
      }
      p.x += p.vx * dt;
      p.y += p.vy * dt;
      p.vx *= 0.95;
      p.vy *= 0.95;
    }
  }

  // ─── Draw ───────────────────────────────────────────────────────────────

  draw() {
    this.drawUndead();
    this.drawEnemies();
    this.drawEffects();
  }

  private drawUndead() {
    this.undeadGfx.clear();
    for (const u of this.undead) {
      if (u.hp <= 0) continue;

      const isPhase = hasBehavior(u.behaviors, 'phase');
      const isStationary = hasBehavior(u.behaviors, 'stationary');
      const isAmbushHidden = u.ambushReady && hasBehavior(u.behaviors, 'ambush');

      let alpha = 0.9;
      if (isPhase) alpha = 0.5;
      if (isAmbushHidden) alpha = 0.35;

      // Invulnerable glow
      if (u.invulnTimer > 0) {
        const glowAlpha = Math.min(0.6, u.invulnTimer * 0.5);
        this.undeadGfx.fill({ color: 0xffffff, alpha: glowAlpha });
        this.undeadGfx.circle(u.x, u.y, u.size + 3);
        this.undeadGfx.fill();
      }

      // Heal flash (green)
      if (u.healFlash > 0) {
        this.undeadGfx.fill({ color: 0x00ff88, alpha: u.healFlash * 2 });
        this.undeadGfx.circle(u.x, u.y, u.size + 2);
        this.undeadGfx.fill();
      }

      // Dodge flash (flicker)
      if (u.dodgeFlash > 0) {
        alpha *= 0.3;
      }

      // Ambush hit flash
      if (u.ambushFlash > 0) {
        this.undeadGfx.fill({ color: 0xffffff, alpha: u.ambushFlash * 2 });
        this.undeadGfx.circle(u.x, u.y, u.size + 4);
        this.undeadGfx.fill();
      }

      // Rage tint: blend toward red as HP drops
      let drawColor = u.color;
      if (hasBehavior(u.behaviors, 'rage')) {
        const hpPct = u.hp / u.maxHp;
        if (hpPct < 0.7) {
          const t = (0.7 - hpPct) / 0.7; // 0..1
          const r = ((drawColor >> 16) & 0xff);
          const g = ((drawColor >> 8) & 0xff);
          const b = (drawColor & 0xff);
          const nr = Math.min(255, Math.floor(r + (255 - r) * t));
          const ng = Math.floor(g * (1 - t * 0.6));
          const nb = Math.floor(b * (1 - t * 0.6));
          drawColor = (nr << 16) | (ng << 8) | nb;
        }
      }

      // Draw the unit
      if (isStationary) {
        // Square for stationary
        this.undeadGfx.fill({ color: drawColor, alpha });
        this.undeadGfx.rect(u.x - u.size, u.y - u.size, u.size * 2, u.size * 2);
        this.undeadGfx.fill();
      } else {
        this.undeadGfx.fill({ color: drawColor, alpha });
        this.undeadGfx.circle(u.x, u.y, u.size);
        this.undeadGfx.fill();
      }

      // Fortified: thin white outline
      if (hasBehavior(u.behaviors, 'fortified')) {
        this.undeadGfx.stroke({ color: 0xffffff, alpha: 0.4, width: 1 });
        if (isStationary) {
          this.undeadGfx.rect(u.x - u.size - 1, u.y - u.size - 1, u.size * 2 + 2, u.size * 2 + 2);
        } else {
          this.undeadGfx.circle(u.x, u.y, u.size + 1);
        }
        this.undeadGfx.stroke();
      }

      // Phase: ghostly trail (small afterimage behind)
      if (isPhase && (Math.abs(u.vx) > 0.1 || Math.abs(u.vy) > 0.1)) {
        this.undeadGfx.fill({ color: drawColor, alpha: 0.15 });
        this.undeadGfx.circle(u.x - u.vx * 3, u.y - u.vy * 3, u.size * 0.8);
        this.undeadGfx.fill();
        this.undeadGfx.fill({ color: drawColor, alpha: 0.08 });
        this.undeadGfx.circle(u.x - u.vx * 6, u.y - u.vy * 6, u.size * 0.6);
        this.undeadGfx.fill();
      }

      // Regen: gentle green pulse overlay
      if (hasBehavior(u.behaviors, 'regen')) {
        const pulse = 0.1 + Math.sin(this.elapsed * 4 + u.x * 0.1) * 0.05;
        this.undeadGfx.fill({ color: 0x44ff88, alpha: pulse });
        this.undeadGfx.circle(u.x, u.y, u.size + 1);
        this.undeadGfx.fill();
      }
    }
  }

  private drawEnemies() {
    this.enemyGfx.clear();
    for (let i = 0; i < this.enemies.count; i++) {
      const isSlowed = this.enemies.slowTimer[i] > 0;
      const isRooted = this.enemies.rootTimer[i] > 0;

      let color = i % 3 === 0 ? ENEMY_COLOR_ALT : ENEMY_COLOR;
      let alpha = 0.9;

      // Blue tint for slowed
      if (isSlowed) {
        color = 0x6688cc;
        alpha = 0.8;
      }
      // Brown tint for rooted
      if (isRooted) {
        color = 0x664422;
        alpha = 0.85;
      }

      this.enemyGfx.fill({ color, alpha });
      const r = ENEMY_RADIUS;
      this.enemyGfx.rect(
        this.enemies.x[i] - r,
        this.enemies.y[i] - r,
        r * 2, r * 2,
      );
      this.enemyGfx.fill();
    }
  }

  private drawEffects() {
    this.fxGfx.clear();

    for (const u of this.undead) {
      if (u.hp <= 0) continue;

      // ─── Aura rings ───

      // aoe_slow: translucent circle in unit's color
      const aoeSlow = getBehavior(u.behaviors, 'aoe_slow');
      if (aoeSlow) {
        this.fxGfx.stroke({ color: u.color, alpha: 0.15, width: 1 });
        this.fxGfx.circle(u.x, u.y, aoeSlow.radius);
        this.fxGfx.stroke();
      }

      // damage_aura: red/orange pulsing ring
      const dmgAura = getBehavior(u.behaviors, 'damage_aura');
      if (dmgAura) {
        const pulse = 0.12 + Math.sin(this.elapsed * 3) * 0.05;
        this.fxGfx.stroke({ color: 0xff6633, alpha: pulse, width: 1.5 });
        this.fxGfx.circle(u.x, u.y, dmgAura.radius);
        this.fxGfx.stroke();
      }

      // protection_aura: blue ring
      const protAura = getBehavior(u.behaviors, 'protection_aura');
      if (protAura) {
        this.fxGfx.stroke({ color: 0x4488ff, alpha: 0.15, width: 1 });
        this.fxGfx.circle(u.x, u.y, protAura.radius);
        this.fxGfx.stroke();
      }

      // taunt: red/orange pulsing ring
      const tauntBeh = getBehavior(u.behaviors, 'taunt');
      if (tauntBeh) {
        const pulse = 0.12 + Math.sin(this.elapsed * 4) * 0.06;
        this.fxGfx.stroke({ color: 0xff8844, alpha: pulse, width: 1 });
        this.fxGfx.circle(u.x, u.y, tauntBeh.radius);
        this.fxGfx.stroke();
      }

      // miss_aura: faint swirling circle
      const missAura = getBehavior(u.behaviors, 'miss_aura');
      if (missAura) {
        const pulse = 0.1 + Math.sin(this.elapsed * 5 + u.y * 0.1) * 0.05;
        this.fxGfx.stroke({ color: 0xaaaaff, alpha: pulse, width: 1 });
        this.fxGfx.circle(u.x, u.y, missAura.radius);
        this.fxGfx.stroke();
      }

      // aura_ally_buff: green ring
      const allyBuff = getBehavior(u.behaviors, 'aura_ally_buff');
      if (allyBuff) {
        this.fxGfx.stroke({ color: 0x44ff66, alpha: 0.12, width: 1 });
        this.fxGfx.circle(u.x, u.y, allyBuff.radius);
        this.fxGfx.stroke();
      }

      // aura_enemy_debuff: purple ring
      const enemyDebuff = getBehavior(u.behaviors, 'aura_enemy_debuff');
      if (enemyDebuff) {
        this.fxGfx.stroke({ color: 0x9944cc, alpha: 0.12, width: 1 });
        this.fxGfx.circle(u.x, u.y, enemyDebuff.radius);
        this.fxGfx.stroke();
      }

      // ─── Life tether line ───
      const tetherBeh = getBehavior(u.behaviors, 'life_tether');
      if (tetherBeh) {
        let nearIdx = -1;
        let nearDist = Infinity;
        const tetherRange = 60;
        for (let ei = 0; ei < this.enemies.count; ei++) {
          if (this.enemies.hp[ei] <= 0) continue;
          const dx = this.enemies.x[ei] - u.x;
          const dy = this.enemies.y[ei] - u.y;
          const d = dx * dx + dy * dy;
          if (d < nearDist && d < tetherRange * tetherRange) {
            nearDist = d;
            nearIdx = ei;
          }
        }
        if (nearIdx >= 0) {
          this.fxGfx.stroke({ color: u.color, alpha: 0.5, width: 1 });
          this.fxGfx.moveTo(u.x, u.y);
          this.fxGfx.lineTo(this.enemies.x[nearIdx], this.enemies.y[nearIdx]);
          this.fxGfx.stroke();
        }
      }
    }

    // ─── Particles ───
    for (const p of this.particles) {
      const t = p.life / p.maxLife;
      this.fxGfx.fill({ color: p.color, alpha: t * 0.8 });
      this.fxGfx.circle(p.x, p.y, p.size * t);
      this.fxGfx.fill();
    }
  }

  // ─── Public helpers ───────────────────────────────────────────────────

  getUndeadCenter(): { x: number; y: number } {
    const alive = this.undead.filter(u => u.hp > 0);
    if (alive.length === 0) return { x: this.cx, y: this.cy };
    let sx = 0, sy = 0;
    for (const u of alive) {
      sx += u.x;
      sy += u.y;
    }
    return { x: sx / alive.length, y: sy / alive.length };
  }

  getUndeadCount(): number {
    return this.undead.filter(u => u.hp > 0).length;
  }

  getEnemyCount(): number {
    return this.enemies.count;
  }

  reset() {
    this.undead.length = 0;
    this.enemies.count = 0;
    this.particles.length = 0;
    this.elapsed = 0;
    this.spawnAccum = 0;
    this.totalKills = 0;
    this.gameOver = false;
    this.relishHitFlash = 0;
    recentUndeadDeathCount = 0;
    this.undeadGfx.clear();
    this.enemyGfx.clear();
    this.fxGfx.clear();
  }
}
