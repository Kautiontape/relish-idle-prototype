import { Config } from '../game/Config';
import type { BehaviorTag } from '../game/spells/Archetypes';
import type { SpellEffect } from '../game/spells/SpellResolver';
import { Enemy } from './Enemy';

export class Minion {
  x: number;
  y: number;
  size: number;
  color: string;
  speed: number;
  damage: number;
  health: number;
  maxHealth: number;
  hitChance: number;
  attackCooldown: number = 0;
  target: Enemy | null = null;
  isDead: boolean = false;

  // Archetype fields
  archetype: string = 'generic';
  archetypeName: string = '';
  behaviors: BehaviorTag[] = [];
  lifespan: number | undefined;
  lifespanTimer: number | undefined;

  // Behavior state
  private hasAttacked = false; // for ambush
  private devourDamageBuff = 0;
  private devourBuffTimer = 0;
  private scalingDamageBonus = 0;
  private spawnMinionTimer = 0;
  private resurrectCooldownTimer = 0;
  private invulnerableTimer = 0;
  private isPhase = false;
  private isStationary = false;
  private teleportRange = 150; // range to teleport to target

  // Tether state
  private tetherTarget: Enemy | null = null;

  // References needed for some behaviors
  private _allEnemies: Enemy[] = [];
  private _spawnCallback: ((x: number, y: number) => void) | null = null;

  constructor(x: number, y: number, speedMultiplier: number, damageMultiplier: number) {
    this.x = x;
    this.y = y;

    // Randomize stats
    this.size = Config.MINION.SIZE + (Math.random() * 2 - 1) * Config.MINION.SIZE_VARIANCE;
    this.speed = (Config.MINION.SPEED + (Math.random() * 2 - 1) * Config.MINION.SPEED_VARIANCE) * speedMultiplier;
    this.damage = (Config.MINION.DAMAGE + (Math.random() * 2 - 1) * Config.MINION.DAMAGE_VARIANCE) * damageMultiplier;
    const healthRoll = Config.MINION.BASE_HEALTH + (Math.random() * 2 - 1) * Config.MINION.HEALTH_VARIANCE;
    this.health = healthRoll;
    this.maxHealth = healthRoll;
    this.hitChance = Math.min(1, Math.max(0, Config.MINION.HIT_CHANCE + (Math.random() * 2 - 1) * Config.MINION.HIT_CHANCE_VARIANCE));

    this.color = Config.MINION.COLOR;
  }

  static fromSpell(x: number, y: number, spell: SpellEffect): Minion {
    const m = new Minion(x, y, 1, 1);
    // Override with spell-resolved stats
    m.health = spell.finalHealth;
    m.maxHealth = spell.finalHealth;
    m.damage = spell.finalDamage;
    m.speed = spell.finalSpeed;
    m.size = Math.max(4, spell.finalSize); // minimum visible size
    m.color = spell.archetype.color;
    m.archetype = spell.archetype.id;
    m.archetypeName = spell.archetype.name;
    m.behaviors = spell.archetype.behaviors;
    m.hitChance = Config.MINION.HIT_CHANCE;

    if (spell.archetype.lifespan !== undefined) {
      m.lifespan = spell.archetype.lifespan;
      m.lifespanTimer = spell.archetype.lifespan;
    }

    // Initialize behavior flags
    for (const b of m.behaviors) {
      if (b.type === 'phase') m.isPhase = true;
      if (b.type === 'stationary') m.isStationary = true;
      if (b.type === 'invulnerable_on_spawn') m.invulnerableTimer = b.duration;
    }

    return m;
  }

  setContext(_minions: Minion[], enemies: Enemy[], spawnCallback: (x: number, y: number) => void) {
    this._allEnemies = enemies;
    this._spawnCallback = spawnCallback;
  }

  takeDamage(amount: number) {
    if (this.isDead) return;
    if (this.invulnerableTimer > 0) return;

    // Fortified: reduce damage
    const fortified = this.getBehavior('fortified');
    if (fortified && fortified.type === 'fortified') {
      amount *= (1 - fortified.damageReduction);
    }

    // Dodge: chance to avoid
    const dodge = this.getBehavior('dodge');
    if (dodge && dodge.type === 'dodge') {
      if (Math.random() < dodge.chance) return;
    }

    this.health -= amount;

    // Decoy on hit
    const decoy = this.getBehavior('decoy_on_hit');
    if (decoy && decoy.type === 'decoy_on_hit' && this._spawnCallback) {
      this._spawnCallback(this.x + (Math.random() - 0.5) * 20, this.y + (Math.random() - 0.5) * 20);
    }

    if (this.health <= 0) {
      this.health = 0;
      this.isDead = true;
      this.onDeath();
    }
  }

  private onDeath() {
    // Death explode
    const explode = this.getBehavior('death_explode');
    if (explode && explode.type === 'death_explode') {
      for (const enemy of this._allEnemies) {
        if (enemy.isDead) continue;
        const dist = this.distanceTo(enemy.x, enemy.y);
        if (dist <= explode.radius) {
          enemy.takeDamage(explode.damage);
        }
      }
    }
  }

  update(deltaTime: number, enemies: Enemy[], minions: Minion[], playerX: number, playerY: number) {
    if (this.isDead) return;

    this._allEnemies = enemies;

    // Lifespan countdown
    if (this.lifespanTimer !== undefined) {
      this.lifespanTimer -= deltaTime;
      if (this.lifespanTimer <= 0) {
        this.isDead = true;
        return;
      }
    }

    // Invulnerability timer
    if (this.invulnerableTimer > 0) {
      this.invulnerableTimer -= deltaTime;
    }

    // Devour buff decay
    if (this.devourBuffTimer > 0) {
      this.devourBuffTimer -= deltaTime;
      if (this.devourBuffTimer <= 0) {
        this.devourDamageBuff = 0;
      }
    }

    // Regen
    const regen = this.getBehavior('regen');
    if (regen && regen.type === 'regen') {
      this.health = Math.min(this.maxHealth, this.health + regen.hpPerSecond * deltaTime);
    }

    // Rage: attack speed bonus based on missing HP
    // (applied in attack section below)

    // Aura behaviors (apply each frame)
    this.applyAuras(deltaTime, enemies, minions);

    // Spawn minions behavior
    const spawner = this.getBehavior('spawn_minions');
    if (spawner && spawner.type === 'spawn_minions' && this._spawnCallback) {
      this.spawnMinionTimer += deltaTime;
      if (this.spawnMinionTimer >= spawner.interval) {
        this.spawnMinionTimer -= spawner.interval;
        this._spawnCallback(this.x + (Math.random() - 0.5) * 20, this.y + (Math.random() - 0.5) * 20);
      }
    }

    // Resurrect nearby
    const resurrect = this.getBehavior('resurrect_nearby');
    if (resurrect && resurrect.type === 'resurrect_nearby') {
      if (this.resurrectCooldownTimer > 0) {
        this.resurrectCooldownTimer -= deltaTime;
      } else {
        // Find dead minion nearby
        for (const m of minions) {
          if (!m.isDead) continue;
          const dist = this.distanceTo(m.x, m.y);
          if (dist <= resurrect.radius) {
            m.isDead = false;
            m.health = m.maxHealth * 0.5;
            this.resurrectCooldownTimer = resurrect.cooldown;
            break;
          }
        }
      }
    }

    // Update attack cooldown
    if (this.attackCooldown > 0) {
      this.attackCooldown -= deltaTime;
    }

    // Life tether behavior
    const tether = this.getBehavior('life_tether');
    if (tether && tether.type === 'life_tether') {
      this.updateLifeTether(deltaTime, enemies, tether.dps);
    }

    // Lock onto current target until dead, or find new target
    if (!this.target || this.target.isDead) {
      if (enemies.length > 0) {
        this.target = this.findNearestEnemy(enemies);
      } else {
        this.target = null;
      }
    }

    if (this.isStationary) {
      // Stationary: don't move, just run attack logic in place
      this.doAttack();
      return;
    }

    // Move towards target or player
    if (this.target && !this.target.isDead) {
      const distance = this.distanceTo(this.target.x, this.target.y);
      const collisionDist = (this.size + this.target.size) / 2;
      const attackRange = collisionDist + Config.MINION.ATTACK_RANGE;

      // Teleport attack behavior
      const teleport = this.getBehavior('teleport_attack');
      if (teleport && distance > attackRange && distance < this.teleportRange) {
        // Teleport next to target
        const dx = this.target.x - this.x;
        const dy = this.target.y - this.y;
        const dist = Math.sqrt(dx * dx + dy * dy);
        this.x = this.target.x - (dx / dist) * collisionDist;
        this.y = this.target.y - (dy / dist) * collisionDist;
      } else if (distance > attackRange) {
        const moved = this.moveTowards(this.target.x, this.target.y, deltaTime, enemies, minions);
        if (!moved && distance > attackRange + 10) {
          this.target = this.findAccessibleEnemy(enemies);
        }
      }

      this.doAttack();
    } else {
      // Return to player
      this.moveTowards(playerX, playerY, deltaTime, enemies, minions);
    }
  }

  private doAttack() {
    if (!this.target || this.target.isDead) return;

    const distance = this.distanceTo(this.target.x, this.target.y);
    const collisionDist = (this.size + this.target.size) / 2;
    const attackRange = collisionDist + Config.MINION.ATTACK_RANGE;

    if (distance > attackRange || this.attackCooldown > 0) return;

    // Calculate attack speed with rage bonus
    let attackSpeed = Config.MINION.ATTACK_SPEED;
    const rage = this.getBehavior('rage');
    if (rage && rage.type === 'rage') {
      const hpPercent = this.health / this.maxHealth;
      attackSpeed *= (1 + rage.maxAttackSpeedBonus * (1 - hpPercent));
    }

    // Effective damage with ambush and devour buffs
    let effectiveDamage = this.damage + this.scalingDamageBonus + this.devourDamageBuff;

    const ambush = this.getBehavior('ambush');
    if (ambush && ambush.type === 'ambush' && !this.hasAttacked) {
      effectiveDamage *= ambush.damageMultiplier;
      this.hasAttacked = true;
    }

    // Roll for hit
    if (Math.random() < this.hitChance) {
      this.target.takeDamage(effectiveDamage);

      // Life steal
      const lifeSteal = this.getBehavior('life_steal');
      if (lifeSteal && lifeSteal.type === 'life_steal') {
        this.health = Math.min(this.maxHealth, this.health + effectiveDamage * lifeSteal.percent);
      }

      // Slow on hit
      const slow = this.getBehavior('slow_on_hit');
      if (slow && slow.type === 'slow_on_hit') {
        this.target.applySpeedDebuff(slow.percent, slow.duration);
      }

      // Root on hit
      const root = this.getBehavior('root_on_hit');
      if (root && root.type === 'root_on_hit') {
        this.target.applyRoot(root.duration);
      }

      // Knockback
      const knockback = this.getBehavior('knockback');
      if (knockback && knockback.type === 'knockback') {
        const dx = this.target.x - this.x;
        const dy = this.target.y - this.y;
        const dist = Math.sqrt(dx * dx + dy * dy);
        if (dist > 0) {
          this.target.x += (dx / dist) * knockback.distance;
          this.target.y += (dy / dist) * knockback.distance;
        }
      }

      // Check if target died from this hit
      if (this.target.isDead) {
        this.onTargetKill();
      }
    }

    this.attackCooldown = 1 / attackSpeed;
  }

  private onTargetKill() {
    // Devour
    const devour = this.getBehavior('devour');
    if (devour && devour.type === 'devour') {
      this.health = Math.min(this.maxHealth, this.health + this.maxHealth * devour.healPercent);
      this.devourDamageBuff = this.damage * devour.damageBuff;
      this.devourBuffTimer = devour.buffDuration;
    }

    // Scaling on kill
    const scaling = this.getBehavior('scaling_on_kill');
    if (scaling && scaling.type === 'scaling_on_kill') {
      this.scalingDamageBonus += scaling.damagePerKill;
    }

    // Shadow Stalker ambush reset (re-stealth on kill if ambush multiplier >= 4)
    const ambush = this.getBehavior('ambush');
    if (ambush && ambush.type === 'ambush' && ambush.damageMultiplier >= 4) {
      this.hasAttacked = false;
    }
  }

  private updateLifeTether(deltaTime: number, enemies: Enemy[], dps: number) {
    // Find/keep tether target
    if (!this.tetherTarget || this.tetherTarget.isDead) {
      this.tetherTarget = this.findNearestEnemy(enemies);
    }
    if (!this.tetherTarget) return;

    const dist = this.distanceTo(this.tetherTarget.x, this.tetherTarget.y);
    if (dist < 150) {
      const dmg = dps * deltaTime;
      this.tetherTarget.takeDamage(dmg);
      this.health = Math.min(this.maxHealth, this.health + dmg * 0.5);
    }
  }

  private applyAuras(deltaTime: number, enemies: Enemy[], minions: Minion[]) {
    // AOE Slow
    const aoeSlow = this.getBehavior('aoe_slow');
    if (aoeSlow && aoeSlow.type === 'aoe_slow') {
      for (const enemy of enemies) {
        if (enemy.isDead) continue;
        const dist = this.distanceTo(enemy.x, enemy.y);
        if (dist <= aoeSlow.radius) {
          enemy.applySpeedDebuff(aoeSlow.percent, 0.2); // refresh each frame
        }
      }
    }

    // Damage aura
    const damageAura = this.getBehavior('damage_aura');
    if (damageAura && damageAura.type === 'damage_aura') {
      for (const enemy of enemies) {
        if (enemy.isDead) continue;
        const dist = this.distanceTo(enemy.x, enemy.y);
        if (dist <= damageAura.radius) {
          enemy.takeDamage(damageAura.dps * deltaTime);
        }
      }
    }

    // Aura ally buff
    const allyBuff = this.getBehavior('aura_ally_buff');
    if (allyBuff && allyBuff.type === 'aura_ally_buff') {
      for (const m of minions) {
        if (m === this || m.isDead) continue;
        const dist = this.distanceTo(m.x, m.y);
        if (dist <= allyBuff.radius) {
          m.applyDamageBuff(allyBuff.damageBuff);
        }
      }
    }

    // Aura enemy debuff
    const enemyDebuff = this.getBehavior('aura_enemy_debuff');
    if (enemyDebuff && enemyDebuff.type === 'aura_enemy_debuff') {
      for (const enemy of enemies) {
        if (enemy.isDead) continue;
        const dist = this.distanceTo(enemy.x, enemy.y);
        if (dist <= enemyDebuff.radius) {
          enemy.applySpeedDebuff(enemyDebuff.attackSpeedReduction, 0.2);
        }
      }
    }

    // Taunt
    const taunt = this.getBehavior('taunt');
    if (taunt && taunt.type === 'taunt') {
      for (const enemy of enemies) {
        if (enemy.isDead) continue;
        const dist = this.distanceTo(enemy.x, enemy.y);
        if (dist <= taunt.radius) {
          enemy.tauntTarget = this;
        }
      }
    }

    // Miss aura
    const missAura = this.getBehavior('miss_aura');
    if (missAura && missAura.type === 'miss_aura') {
      for (const enemy of enemies) {
        if (enemy.isDead) continue;
        const dist = this.distanceTo(enemy.x, enemy.y);
        if (dist <= missAura.radius) {
          enemy.missChance = Math.max(enemy.missChance, missAura.chance);
        }
      }
    }

    // Protection aura
    const protAura = this.getBehavior('protection_aura');
    if (protAura && protAura.type === 'protection_aura') {
      for (const m of minions) {
        if (m === this || m.isDead) continue;
        const dist = this.distanceTo(m.x, m.y);
        if (dist <= protAura.radius) {
          m.applyProtectionBuff(protAura.reduction);
        }
      }
    }
  }

  // Temporary per-frame buffs (reset each frame before auras re-apply)
  private tempDamageBuff = 0;
  private tempProtection = 0;

  applyDamageBuff(percent: number) {
    this.tempDamageBuff = Math.max(this.tempDamageBuff, percent);
  }

  applyProtectionBuff(reduction: number) {
    this.tempProtection = Math.max(this.tempProtection, reduction);
  }

  resetFrameBuffs() {
    this.tempDamageBuff = 0;
    this.tempProtection = 0;
  }

  private getBehavior(type: string): BehaviorTag | undefined {
    return this.behaviors.find(b => b.type === type);
  }

  moveTowards(targetX: number, targetY: number, deltaTime: number, enemies: Enemy[], minions: Minion[]): boolean {
    const dx = targetX - this.x;
    const dy = targetY - this.y;
    const distance = Math.sqrt(dx * dx + dy * dy);

    if (distance > 5) {
      const moveDistance = this.speed * deltaTime;

      let newX = this.x + (dx / distance) * moveDistance;
      let newY = this.y + (dy / distance) * moveDistance;

      if (this.isPhase || !this.checkCollision(newX, newY, enemies, minions)) {
        this.x = newX;
        this.y = newY;
        return true;
      }

      // If blocked, try sliding around obstacles
      const angles = [
        Math.PI / 4,
        -Math.PI / 4,
        Math.PI / 2,
        -Math.PI / 2,
      ];

      for (const angleOffset of angles) {
        const angle = Math.atan2(dy, dx) + angleOffset;
        newX = this.x + Math.cos(angle) * moveDistance;
        newY = this.y + Math.sin(angle) * moveDistance;

        if (!this.checkCollision(newX, newY, enemies, minions)) {
          this.x = newX;
          this.y = newY;
          return true;
        }
      }

      // Still blocked - try smaller movement
      newX = this.x + (dx / distance) * moveDistance * 0.5;
      newY = this.y + (dy / distance) * moveDistance * 0.5;
      if (!this.checkCollision(newX, newY, enemies, minions)) {
        this.x = newX;
        this.y = newY;
        return true;
      }
    }
    return false;
  }

  checkCollision(newX: number, newY: number, enemies: Enemy[], minions: Minion[]): boolean {
    for (const enemy of enemies) {
      if (enemy.isDead) continue;
      const dist = Math.sqrt((newX - enemy.x) ** 2 + (newY - enemy.y) ** 2);
      if (dist < (this.size + enemy.size) / 2) {
        return true;
      }
    }

    for (const minion of minions) {
      if (minion === this || minion.isDead) continue;
      const dist = Math.sqrt((newX - minion.x) ** 2 + (newY - minion.y) ** 2);
      if (dist < this.size) {
        return true;
      }
    }

    return false;
  }

  findNearestEnemy(enemies: Enemy[]): Enemy {
    let nearest = enemies[0];
    let nearestDist = this.distanceTo(nearest.x, nearest.y);

    for (const enemy of enemies) {
      if (enemy.isDead) continue;
      const dist = this.distanceTo(enemy.x, enemy.y);
      if (dist < nearestDist) {
        nearest = enemy;
        nearestDist = dist;
      }
    }

    return nearest;
  }

  findAccessibleEnemy(enemies: Enemy[]): Enemy | null {
    const liveEnemies = enemies.filter(e => !e.isDead);
    if (liveEnemies.length === 0) return null;

    const sorted = liveEnemies.sort((a, b) => {
      return this.distanceTo(a.x, a.y) - this.distanceTo(b.x, b.y);
    });

    return sorted[0];
  }

  distanceTo(x: number, y: number): number {
    const dx = x - this.x;
    const dy = y - this.y;
    return Math.sqrt(dx * dx + dy * dy);
  }

  draw(ctx: CanvasRenderingContext2D) {
    if (this.isDead) return;

    // Draw minion body
    ctx.fillStyle = this.color;
    ctx.fillRect(
      this.x - this.size / 2,
      this.y - this.size / 2,
      this.size,
      this.size
    );

    // Phase visual: semi-transparent overlay
    if (this.isPhase) {
      ctx.save();
      ctx.globalAlpha = 0.3;
      ctx.strokeStyle = '#aaddff';
      ctx.lineWidth = 1;
      ctx.strokeRect(
        this.x - this.size / 2 - 1,
        this.y - this.size / 2 - 1,
        this.size + 2,
        this.size + 2
      );
      ctx.restore();
    }

    // Invulnerable visual
    if (this.invulnerableTimer > 0) {
      ctx.save();
      ctx.globalAlpha = 0.4;
      ctx.strokeStyle = '#ffffff';
      ctx.lineWidth = 2;
      ctx.beginPath();
      ctx.arc(this.x, this.y, this.size / 2 + 3, 0, Math.PI * 2);
      ctx.stroke();
      ctx.restore();
    }

    // Draw health bar if damaged
    if (this.health < this.maxHealth) {
      const healthBarWidth = this.size;
      const healthBarHeight = 2;
      const healthPercent = this.health / this.maxHealth;

      ctx.fillStyle = '#333';
      ctx.fillRect(
        this.x - healthBarWidth / 2,
        this.y - this.size / 2 - healthBarHeight - 1,
        healthBarWidth,
        healthBarHeight
      );

      ctx.fillStyle = '#00ff00';
      ctx.fillRect(
        this.x - healthBarWidth / 2,
        this.y - this.size / 2 - healthBarHeight - 1,
        healthBarWidth * healthPercent,
        healthBarHeight
      );
    }
  }
}
