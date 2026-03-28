import type { ArchetypeDefinition } from './Archetypes';
import { lookupArchetype } from './Archetypes';
import type { GestureResult } from './GestureTracker';
import { Config } from '../Config';

export interface SpellEffect {
  archetype: ArchetypeDefinition;
  finalHealth: number;
  finalDamage: number;
  finalSpeed: number;
  finalSize: number;
}

export function resolveSpell(
  gesture: GestureResult,
  damageMultiplier: number,
  speedMultiplier: number
): SpellEffect | null {
  if (gesture.runeSequence.length < Config.SPELL.MIN_RUNES) {
    return null;
  }

  const archetype = lookupArchetype(gesture.runeSequence);
  if (!archetype) {
    return null;
  }

  const baseHealth = Config.MINION.BASE_HEALTH;
  const baseDamage = Config.MINION.DAMAGE;
  const baseSpeed = Config.MINION.SPEED;
  const baseSize = Config.MINION.SIZE;

  return {
    archetype,
    finalHealth: baseHealth * archetype.stats.health,
    finalDamage: baseDamage * archetype.stats.damage * damageMultiplier,
    finalSpeed: baseSpeed * archetype.stats.speed * speedMultiplier,
    finalSize: baseSize * archetype.stats.size,
  };
}
