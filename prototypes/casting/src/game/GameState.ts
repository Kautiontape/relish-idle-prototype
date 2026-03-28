import { Config } from './Config';

export type GamePhase = 'combat' | 'town';

export interface JobAssignment {
  jobId: string;
  buildingId: string;
  assigned: number;
}

export class GameState {
  // Phase management
  phase: GamePhase = 'combat';
  combatTimer: number = 0;

  // Resources
  gold: number = 0;
  bones: number = 0;
  totalMinions: number = Config.MINION.BASE_COUNT;
  availableMinions: number = Config.MINION.BASE_COUNT;
  liveMinionsInCombat: number = 0; // Track how many are alive in current combat

  // Bonuses (applied from jobs)
  damageMultiplier: number = 1;
  speedMultiplier: number = 1;

  // Job assignments
  jobAssignments: JobAssignment[] = [];

  // Combat stats
  enemiesKilled: number = 0;
  currentQuestKills: number = 0;

  // Called when minions die in combat
  loseMinionsPermanently(count: number) {
    this.totalMinions = Math.max(0, this.totalMinions - count);
    this.updateAvailableMinions();
  }

  // Ritual: convert bones to minions
  performRitual(boneCost: number, minionGain: number): boolean {
    if (this.bones >= boneCost) {
      this.bones -= boneCost;
      this.totalMinions += minionGain;
      this.updateAvailableMinions();
      return true;
    }
    return false;
  }

  // Update available minions based on assignments
  updateAvailableMinions() {
    const assignedCount = this.jobAssignments.reduce((sum, assignment) => sum + assignment.assigned, 0);
    this.availableMinions = this.totalMinions - assignedCount;
  }

  // Assign minions to a job
  assignToJob(buildingId: string, jobId: string, count: number): boolean {
    if (count > this.availableMinions) return false;

    const existing = this.jobAssignments.find(
      (a) => a.buildingId === buildingId && a.jobId === jobId
    );

    if (existing) {
      existing.assigned += count;
    } else {
      this.jobAssignments.push({ buildingId, jobId, assigned: count });
    }

    this.updateAvailableMinions();
    return true;
  }

  // Unassign minions from a job
  unassignFromJob(buildingId: string, jobId: string, count: number): boolean {
    const existing = this.jobAssignments.find(
      (a) => a.buildingId === buildingId && a.jobId === jobId
    );

    if (!existing || existing.assigned < count) return false;

    existing.assigned -= count;
    if (existing.assigned === 0) {
      this.jobAssignments = this.jobAssignments.filter((a) => a !== existing);
    }

    this.updateAvailableMinions();
    return true;
  }

  // Get assignment count for a specific job
  getAssignedCount(buildingId: string, jobId: string): number {
    const assignment = this.jobAssignments.find(
      (a) => a.buildingId === buildingId && a.jobId === jobId
    );
    return assignment ? assignment.assigned : 0;
  }

  // Apply job bonuses and collect rewards
  applyJobRewards() {
    // Reset multipliers
    this.damageMultiplier = 1;
    this.speedMultiplier = 1;
    let goldEarned = 0;
    let minionsGained = 0;

    // Apply bonuses from all assigned jobs
    for (const assignment of this.jobAssignments) {
      const building = Config.TOWN.BUILDINGS.find((b) => b.id === assignment.buildingId);
      if (!building) continue;

      const job = building.jobs.find((j) => j.id === assignment.jobId);
      if (!job) continue;

      // Only apply bonus if job is fully staffed
      if (assignment.assigned >= job.slots) {
        switch (job.bonus.type) {
          case 'damage':
            this.damageMultiplier += job.bonus.value;
            break;
          case 'speed':
            this.speedMultiplier += job.bonus.value;
            break;
          case 'gold':
            goldEarned += job.bonus.value;
            break;
          case 'minions':
            minionsGained += job.bonus.value;
            break;
        }
      }
    }

    this.gold += goldEarned;
    this.totalMinions += minionsGained;
    this.updateAvailableMinions();
  }

  // Start a new combat phase
  startCombat() {
    this.phase = 'combat';
    this.combatTimer = Config.COMBAT.DURATION;
    this.currentQuestKills = 0;
    this.applyJobRewards();
  }

  // End combat and go to town
  endCombat() {
    this.phase = 'town';
    // Award gold for kills
    this.gold += this.currentQuestKills * Config.REWARDS.GOLD_PER_ENEMY;
    this.enemiesKilled += this.currentQuestKills;
  }
}
