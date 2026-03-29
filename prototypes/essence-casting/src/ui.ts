import type { EssenceSystem } from './essences.ts';
import type { Battlefield } from './battlefield.ts';
import { RUNES } from './runes.ts';

const essenceEl = document.getElementById('essence-counter')!;
const armyEl = document.getElementById('army-count')!;
const waveEl = document.getElementById('wave-timer')!;
const castMsgEl = document.getElementById('cast-message')!;

let castMsgTimer = 0;

export function showCastMessage(name: string, color: string) {
  castMsgEl.textContent = name;
  castMsgEl.style.color = color;
  castMsgEl.classList.add('visible');
  castMsgTimer = 2.0;
}

export function updateHUD(essences: EssenceSystem, battlefield: Battlefield, dt: number) {
  const c = essences.counts();
  essenceEl.innerHTML =
    `<span style="color:${RUNES.flesh.color}">Flesh: ${c.flesh}</span>` +
    ` | <span style="color:${RUNES.breath.color}">Breath: ${c.breath}</span>` +
    ` | <span style="color:${RUNES.veil.color}">Veil: ${c.veil}</span>` +
    ` | <span style="color:${RUNES.chain.color}">Chain: ${c.chain}</span>`;

  armyEl.textContent = `Undead: ${battlefield.undead.count}`;

  const secs = Math.floor(battlefield.elapsed);
  const m = Math.floor(secs / 60);
  const s = secs % 60;
  waveEl.textContent = `Time: ${m}:${s.toString().padStart(2, '0')}  |  Kills: ${battlefield.totalKills}`;

  // Fade cast message
  if (castMsgTimer > 0) {
    castMsgTimer -= dt;
    if (castMsgTimer <= 0) {
      castMsgEl.classList.remove('visible');
      castMsgEl.style.opacity = '0';
      castMsgEl.textContent = '';
    } else if (castMsgTimer < 0.5) {
      castMsgEl.style.opacity = String(castMsgTimer / 0.5);
    }
  }
}
