import { Config } from '../Config';
import { GameState } from '../GameState';

type Building = (typeof Config.TOWN.BUILDINGS)[number];
type Job = Building['jobs'][number];

export class TownPhase {
  private townUI: HTMLElement;
  private onStartQuest: () => void;
  private gameState: GameState;

  constructor(gameState: GameState, onStartQuest: () => void) {
    this.gameState = gameState;
    this.townUI = document.getElementById('townUI')!;
    this.onStartQuest = onStartQuest;
    this.render();
  }

  show() {
    this.townUI.classList.remove('hidden');
    this.render();
  }

  hide() {
    this.townUI.classList.add('hidden');
  }

  render() {
    const availableMinions = this.gameState.availableMinions;
    const totalMinions = this.gameState.totalMinions;
    const gold = this.gameState.gold;
    const bones = this.gameState.bones;

    const canRitual = bones >= Config.RITUAL.BONE_COST;

    this.townUI.innerHTML = `
      <div class="town-header">
        <h2>Town Management</h2>
        <p>Assign your minions to jobs before the next quest</p>
      </div>

      <div class="resources">
        <div class="resource">
          <div class="resource-label">Minions</div>
          <div class="resource-value">${availableMinions}/${totalMinions}</div>
        </div>
        <div class="resource">
          <div class="resource-label">Bones</div>
          <div class="resource-value">${bones}</div>
        </div>
        <div class="resource">
          <div class="resource-label">Gold</div>
          <div class="resource-value">${gold}</div>
        </div>
        <div class="resource">
          <div class="resource-label">Kills</div>
          <div class="resource-value">${this.gameState.enemiesKilled}</div>
        </div>
      </div>

      <div style="margin-bottom: 20px; padding: 15px; background: rgba(80, 200, 80, 0.1); border: 2px solid rgba(80, 200, 80, 0.3); border-radius: 8px;">
        <div style="display: flex; justify-content: space-between; align-items: center;">
          <div>
            <div style="font-weight: bold; margin-bottom: 5px;">Dark Ritual</div>
            <div style="font-size: 12px; color: #aaa;">Convert ${Config.RITUAL.BONE_COST} bones → ${Config.RITUAL.MINIONS_GAINED} minion</div>
          </div>
          <button id="ritualBtn" ${!canRitual ? 'disabled' : ''} style="background: #50c850;">
            Ritual
          </button>
        </div>
      </div>

      <div class="buildings">
        ${Config.TOWN.BUILDINGS.map((building) => this.renderBuilding(building)).join('')}
      </div>

      <button class="btn-primary" id="startQuestBtn">
        Start Quest (${availableMinions} minions available)
      </button>
    `;

    // Add event listeners
    this.attachEventListeners();
  }

  renderBuilding(building: Building) {
    return `
      <div class="building">
        <div class="building-name">${building.name}</div>
        <div class="jobs">
          ${building.jobs.map((job) => this.renderJob(building.id, job)).join('')}
        </div>
      </div>
    `;
  }

  renderJob(buildingId: string, job: Job) {
    const assigned = this.gameState.getAssignedCount(buildingId, job.id);
    const canAssign = this.gameState.availableMinions > 0;
    const canUnassign = assigned > 0;

    return `
      <div class="job">
        <div class="job-info">
          <div class="job-name">${job.name}</div>
          <div class="job-desc">${job.desc} (Requires ${job.slots})</div>
        </div>
        <div class="job-controls">
          <button
            class="btn-small"
            data-action="unassign"
            data-building="${buildingId}"
            data-job="${job.id}"
            ${!canUnassign ? 'disabled' : ''}
          >-</button>
          <div class="job-assigned">${assigned}/${job.slots}</div>
          <button
            class="btn-small"
            data-action="assign"
            data-building="${buildingId}"
            data-job="${job.id}"
            ${!canAssign ? 'disabled' : ''}
          >+</button>
        </div>
      </div>
    `;
  }

  attachEventListeners() {
    // Ritual button
    const ritualBtn = document.getElementById('ritualBtn');
    ritualBtn?.addEventListener('click', () => {
      if (this.gameState.performRitual(Config.RITUAL.BONE_COST, Config.RITUAL.MINIONS_GAINED)) {
        this.render();
      }
    });

    // Job assignment buttons
    this.townUI.querySelectorAll('[data-action]').forEach((button) => {
      button.addEventListener('click', (e) => {
        const target = e.target as HTMLButtonElement;
        const action = target.dataset.action!;
        const buildingId = target.dataset.building!;
        const jobId = target.dataset.job!;

        if (action === 'assign') {
          this.gameState.assignToJob(buildingId, jobId, 1);
        } else if (action === 'unassign') {
          this.gameState.unassignFromJob(buildingId, jobId, 1);
        }

        this.render();
      });
    });

    // Start quest button
    const startQuestBtn = document.getElementById('startQuestBtn');
    startQuestBtn?.addEventListener('click', () => {
      this.hide();
      this.onStartQuest();
    });
  }
}
