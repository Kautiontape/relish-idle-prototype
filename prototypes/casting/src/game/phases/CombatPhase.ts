import { Config } from '../Config';
import { GameState } from '../GameState';
import { Player } from '../../entities/Player';
import { Minion } from '../../entities/Minion';
import { Enemy } from '../../entities/Enemy';
import { GestureTracker } from '../spells/GestureTracker';
import { SpellRenderer } from '../spells/SpellRenderer';
import { RUNES } from '../spells/Runes';
import { resolveSpell, type SpellEffect } from '../spells/SpellResolver';

export class CombatPhase {
  player: Player;
  minions: Minion[] = [];
  enemies: Enemy[] = [];
  enemySpawnTimer: number = 0;
  gameOver: boolean = false;
  lastCastName: string = '';
  lastCastTimer: number = 0;

  private gestureTracker: GestureTracker;
  spellRenderer: SpellRenderer;
  private prevRuneCount = 0;

  // Pointer held state for auto-start after unwind
  private pointerHeld = false;
  private pointerX = 0;
  private pointerY = 0;
  private wasUnwinding = false;

  private mouseDownHandler: (e: MouseEvent) => void;
  private mouseMoveHandler: (e: MouseEvent) => void;
  private mouseUpHandler: (e: MouseEvent) => void;
  private touchStartHandler: (e: TouchEvent) => void;
  private touchMoveHandler: (e: TouchEvent) => void;
  private touchEndHandler: (e: TouchEvent) => void;

  private canvas: HTMLCanvasElement;
  private ctx: CanvasRenderingContext2D;
  private gameState: GameState;
  private onGameOver: () => void;

  constructor(
    canvas: HTMLCanvasElement,
    ctx: CanvasRenderingContext2D,
    gameState: GameState,
    onGameOver: () => void
  ) {
    this.canvas = canvas;
    this.ctx = ctx;
    this.gameState = gameState;
    this.onGameOver = onGameOver;
    this.player = new Player(canvas.width, canvas.height);
    this.gestureTracker = new GestureTracker();
    this.spellRenderer = new SpellRenderer();

    // Spawn first enemy immediately
    this.spawnEnemy();

    // Setup input handlers
    this.mouseDownHandler = (e: MouseEvent) => this.handlePointerDown(e.clientX, e.clientY);
    this.mouseMoveHandler = (e: MouseEvent) => this.handlePointerMove(e.clientX, e.clientY);
    this.mouseUpHandler = () => this.handlePointerUp();

    this.touchStartHandler = (e: TouchEvent) => {
      e.preventDefault();
      const touch = e.touches[0];
      this.handlePointerDown(touch.clientX, touch.clientY);
    };
    this.touchMoveHandler = (e: TouchEvent) => {
      e.preventDefault();
      const touch = e.touches[0];
      this.handlePointerMove(touch.clientX, touch.clientY);
    };
    this.touchEndHandler = (e: TouchEvent) => {
      e.preventDefault();
      this.handlePointerUp();
    };

    canvas.addEventListener('mousedown', this.mouseDownHandler);
    canvas.addEventListener('mousemove', this.mouseMoveHandler);
    canvas.addEventListener('mouseup', this.mouseUpHandler);
    canvas.addEventListener('touchstart', this.touchStartHandler);
    canvas.addEventListener('touchmove', this.touchMoveHandler);
    canvas.addEventListener('touchend', this.touchEndHandler);
  }

  private handlePointerDown(clientX: number, clientY: number) {
    if (this.gameOver) return;
    const rect = this.canvas.getBoundingClientRect();
    this.pointerX = clientX - rect.left;
    this.pointerY = clientY - rect.top;
    this.pointerHeld = true;

    // Only start gesture if not unwinding
    if (!this.spellRenderer.isUnwinding) {
      this.beginGesture(this.pointerX, this.pointerY);
    }
  }

  private handlePointerMove(clientX: number, clientY: number) {
    if (this.gameOver) return;
    const rect = this.canvas.getBoundingClientRect();
    this.pointerX = clientX - rect.left;
    this.pointerY = clientY - rect.top;

    if (!this.gestureTracker.isActive) return;

    this.gestureTracker.updateGesture(this.pointerX, this.pointerY);

    // Check for new rune hits to trigger flash
    const seq = this.gestureTracker.currentSequence;
    if (seq.length > this.prevRuneCount) {
      for (let i = this.prevRuneCount; i < seq.length; i++) {
        this.spellRenderer.onRuneHit(seq[i]);
      }
      this.prevRuneCount = seq.length;
    }
  }

  private handlePointerUp() {
    this.pointerHeld = false;

    if (this.gameOver || !this.gestureTracker.isActive) return;

    const result = this.gestureTracker.endGesture();

    const spell = resolveSpell(
      result,
      this.gameState.damageMultiplier,
      this.gameState.speedMultiplier
    );

    if (spell) {
      this.castSpell(spell);
    } else if (result.runeSequence.length > 0) {
      this.spellRenderer.onFizzle();
    }
  }

  private beginGesture(x: number, y: number) {
    this.spellRenderer.onGestureStart();
    this.gestureTracker.setCanvasSize(this.canvas.width, this.canvas.height);
    this.gestureTracker.startGesture(x, y);
    this.prevRuneCount = 0;

    // Check immediate rune hits
    const seq = this.gestureTracker.currentSequence;
    if (seq.length > 0) {
      for (let i = 0; i < seq.length; i++) {
        this.spellRenderer.onRuneHit(seq[i]);
      }
      this.prevRuneCount = seq.length;
    }
  }

  private castSpell(spell: SpellEffect) {
    const angle = Math.random() * Math.PI * 2;
    const distance = 30;
    const x = this.player.x + Math.cos(angle) * distance;
    const y = this.player.y + Math.sin(angle) * distance;

    const minion = Minion.fromSpell(x, y, spell);
    minion.setContext(this.minions, this.enemies, (sx, sy) => this.spawnTinyMinion(sx, sy));
    this.minions.push(minion);

    // Get trail color from last rune in sequence
    const seq = spell.archetype.runeSequence;
    const lastRuneColor = RUNES[seq[seq.length - 1]].color;

    // Pass the trail path to the renderer for unwind
    this.spellRenderer.onSpellCast(
      spell.archetype,
      this.gestureTracker.currentPath,
      lastRuneColor
    );
    this.lastCastName = spell.archetype.name;
    this.lastCastTimer = 3;

    this.gameState.liveMinionsInCombat = this.minions.filter(m => !m.isDead).length;
  }

  private spawnTinyMinion(x: number, y: number) {
    const m = new Minion(x, y, this.gameState.speedMultiplier, this.gameState.damageMultiplier);
    m.size = 4;
    m.health = 8;
    m.maxHealth = 8;
    m.damage = 2;
    m.speed = 80;
    m.color = '#b8a880';
    m.archetype = 'spawned';
    this.minions.push(m);
  }

  spawnEnemy() {
    const x = Math.random() * this.canvas.width;
    const enemy = new Enemy(x);
    this.enemies.push(enemy);
  }

  cleanup() {
    this.canvas.removeEventListener('mousedown', this.mouseDownHandler);
    this.canvas.removeEventListener('mousemove', this.mouseMoveHandler);
    this.canvas.removeEventListener('mouseup', this.mouseUpHandler);
    this.canvas.removeEventListener('touchstart', this.touchStartHandler);
    this.canvas.removeEventListener('touchmove', this.touchMoveHandler);
    this.canvas.removeEventListener('touchend', this.touchEndHandler);
  }

  update(deltaTime: number) {
    if (this.gameOver) return;

    // Update player
    this.player.update(deltaTime);

    // Update spell renderer
    this.spellRenderer.update(deltaTime);
    this.gestureTracker.setCanvasSize(this.canvas.width, this.canvas.height);

    // Auto-start gesture when unwind finishes while pointer is held
    if (this.wasUnwinding && !this.spellRenderer.isUnwinding && this.pointerHeld) {
      this.beginGesture(this.pointerX, this.pointerY);
    }
    this.wasUnwinding = this.spellRenderer.isUnwinding;

    // Last cast name timer
    if (this.lastCastTimer > 0) {
      this.lastCastTimer -= deltaTime;
    }

    // Update combat timer
    this.gameState.combatTimer -= deltaTime * 1000;
    if (this.gameState.combatTimer <= 0) {
      this.cleanup();
      this.gameState.endCombat();
      return;
    }

    // Spawn enemies
    this.enemySpawnTimer += deltaTime * 1000;
    if (this.enemySpawnTimer >= Config.COMBAT.ENEMY_SPAWN_INTERVAL) {
      this.spawnEnemy();
      this.enemySpawnTimer = 0;
    }

    // Reset taunt targets each frame
    for (const enemy of this.enemies) {
      if (!enemy.isDead) {
        enemy.tauntTarget = null;
      }
    }

    // Reset frame buffs on minions
    for (const minion of this.minions) {
      if (!minion.isDead) {
        minion.resetFrameBuffs();
      }
    }

    // Update minions
    for (const minion of this.minions) {
      minion.setContext(this.minions, this.enemies, (sx, sy) => this.spawnTinyMinion(sx, sy));
      minion.update(deltaTime, this.enemies, this.minions, this.player.x, this.player.y);
    }

    // Update enemies
    for (const enemy of this.enemies) {
      enemy.update(deltaTime, this.player.x, this.player.y, this.minions, this.enemies);

      if (!this.gameOver) {
        const dist = Math.sqrt(
          (enemy.x - this.player.x) ** 2 + (enemy.y - this.player.y) ** 2
        );
        if (dist < (this.player.size + enemy.size) / 2) {
          this.gameOver = true;
          this.cleanup();
          this.onGameOver();
          return;
        }
      }
    }

    // Remove dead enemies and drop bones
    const deadEnemies = this.enemies.filter((e) => e.isDead);
    if (deadEnemies.length > 0) {
      this.gameState.currentQuestKills += deadEnemies.length;

      for (const _enemy of deadEnemies) {
        if (Math.random() < Config.ENEMY.BONE_DROP_CHANCE) {
          this.gameState.bones += Config.ENEMY.BONES_PER_DROP;
        }
      }

      this.enemies = this.enemies.filter((e) => !e.isDead);
    }

    // Track and remove dead minions
    const deadMinions = this.minions.filter((m) => m.isDead && m.archetype !== 'spawned');
    if (deadMinions.length > 0) {
      this.gameState.loseMinionsPermanently(deadMinions.length);
    }
    this.minions = this.minions.filter((m) => !m.isDead);

    this.gameState.liveMinionsInCombat = this.minions.length;
  }

  draw() {
    this.ctx.fillStyle = '#0a0a0a';
    this.ctx.fillRect(0, 0, this.canvas.width, this.canvas.height);

    this.player.draw(this.ctx);

    for (const minion of this.minions) {
      minion.draw(this.ctx);
    }

    for (const enemy of this.enemies) {
      enemy.draw(this.ctx);
    }

    this.spellRenderer.draw(this.ctx, this.gestureTracker, this.canvas.width, this.canvas.height);

    if (this.gameOver) {
      this.ctx.fillStyle = 'rgba(0, 0, 0, 0.8)';
      this.ctx.fillRect(0, 0, this.canvas.width, this.canvas.height);

      this.ctx.fillStyle = '#ff4444';
      this.ctx.font = 'bold 48px Arial';
      this.ctx.textAlign = 'center';
      this.ctx.fillText('GAME OVER', this.canvas.width / 2, this.canvas.height / 2 - 40);

      this.ctx.fillStyle = '#ffffff';
      this.ctx.font = '24px Arial';
      this.ctx.fillText('An enemy reached your base!', this.canvas.width / 2, this.canvas.height / 2 + 10);

      this.ctx.font = '20px Arial';
      this.ctx.fillText('Click anywhere to restart', this.canvas.width / 2, this.canvas.height / 2 + 50);

      this.ctx.textAlign = 'left';
    }
  }
}
