import { GameState } from './GameState';
import { CombatPhase } from './phases/CombatPhase';
import { TownPhase } from './phases/TownPhase';

export class GameLoop {
  private gameState: GameState;
  private combatPhase: CombatPhase | null = null;
  private townPhase: TownPhase;
  private lastTime: number = 0;
  private animationId: number = 0;
  private hudElement: HTMLElement;
  private summonBarElement: HTMLElement;
  private gameOverActive: boolean = false;
  private restartClickHandler: ((e: MouseEvent) => void) | null = null;
  private canvas: HTMLCanvasElement;
  private ctx: CanvasRenderingContext2D;

  constructor(
    canvas: HTMLCanvasElement,
    ctx: CanvasRenderingContext2D
  ) {
    this.canvas = canvas;
    this.ctx = ctx;
    this.gameState = new GameState();
    this.hudElement = document.getElementById('hud')!;
    this.summonBarElement = document.getElementById('summonBar')!;

    // Hide the summon bar permanently — cooldown is now shown via trail unwind
    this.summonBarElement.classList.add('hidden');

    this.townPhase = new TownPhase(this.gameState, () => this.startCombat());
    this.startCombat();
  }

  startCombat() {
    console.log('Starting combat phase');
    this.gameState.startCombat();
    this.combatPhase = new CombatPhase(
      this.canvas,
      this.ctx,
      this.gameState,
      () => this.handleGameOver()
    );
    this.townPhase.hide();
    this.gameOverActive = false;
  }

  handleGameOver() {
    this.gameOverActive = true;
    this.restartClickHandler = () => this.restart();
    this.canvas.addEventListener('click', this.restartClickHandler);
  }

  restart() {
    if (this.restartClickHandler) {
      this.canvas.removeEventListener('click', this.restartClickHandler);
      this.restartClickHandler = null;
    }

    this.gameState = new GameState();
    this.townPhase = new TownPhase(this.gameState, () => this.startCombat());
    this.startCombat();
  }

  start() {
    this.lastTime = performance.now();
    this.loop();
  }

  stop() {
    if (this.animationId) {
      cancelAnimationFrame(this.animationId);
    }
  }

  loop = () => {
    const currentTime = performance.now();
    const deltaTime = (currentTime - this.lastTime) / 1000;
    this.lastTime = currentTime;

    this.update(deltaTime);
    this.draw();
    this.updateHUD();

    this.animationId = requestAnimationFrame(this.loop);
  };

  update(deltaTime: number) {
    if (this.gameState.phase === 'combat' && this.combatPhase) {
      this.combatPhase.update(deltaTime);
    }

    if (this.gameState.phase === 'town') {
        this.townPhase.show();
    }
  }

  draw() {
    if (this.gameState.phase === 'combat' && this.combatPhase) {
      this.combatPhase.draw();
    }
  }

  updateHUD() {
    if (this.gameState.phase === 'combat' && this.combatPhase && !this.gameOverActive) {
      const timeLeft = Math.ceil(this.gameState.combatTimer / 1000);
      const kills = this.gameState.currentQuestKills;
      const minions = this.combatPhase.minions.length;

      this.hudElement.innerHTML = `
        <div class="hud-stat">
          <div class="hud-stat-label">Time</div>
          <div class="hud-stat-value">${timeLeft}s</div>
        </div>
        <div class="hud-stat">
          <div class="hud-stat-label">Kills</div>
          <div class="hud-stat-value">${kills}</div>
        </div>
        <div class="hud-stat">
          <div class="hud-stat-label">Minions</div>
          <div class="hud-stat-value">${minions}</div>
        </div>
      `;
    } else {
      this.hudElement.innerHTML = '';
    }
  }
}
