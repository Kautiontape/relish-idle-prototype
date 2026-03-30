import { setRuneHitRadius, RUNE_HIT_RADIUS } from './runes.ts';

export interface DebugState {
  spawnRate: number;
  enemyStrength: number;
  essenceDropRate: number;
  cooldownDuration: number;
  runeHitRadius: number;
  // Unit tunables
  undeadHpMult: number;
  undeadSpeedMult: number;
  undeadDmgMult: number;
  enemyHpMult: number;
  enemySpeedMult: number;
  enemyDmgMult: number;
}

export const debugState: DebugState = {
  spawnRate: 1,
  enemyStrength: 1,
  essenceDropRate: 1,
  cooldownDuration: 1.0,
  runeHitRadius: RUNE_HIT_RADIUS,
  undeadHpMult: 1,
  undeadSpeedMult: 1,
  undeadDmgMult: 1,
  enemyHpMult: 1,
  enemySpeedMult: 1,
  enemyDmgMult: 1,
};

export type ResetCallback = () => void;
export type AddEssenceCallback = () => void;

export function initDebugPanel(onReset: ResetCallback, onAddEssence: AddEssenceCallback) {
  const panel = document.getElementById('debug-panel')!;
  const body = document.getElementById('debug-body')!;
  const toggleBtn = document.getElementById('debug-toggle-btn')!;
  const closeBtn = document.getElementById('debug-close')!;

  // Toggle open/close
  toggleBtn.addEventListener('click', () => {
    panel.classList.toggle('collapsed');
  });
  closeBtn.addEventListener('click', () => {
    panel.classList.add('collapsed');
  });

  // ─── Combat tuning ─────────────────────────────────────────────────
  addSectionLabel(body, 'Waves');

  addSlider(body, 'Spawn Rate', 0.1, 5, 0.1, debugState.spawnRate, v => {
    debugState.spawnRate = v;
  });
  addSlider(body, 'Enemy Str', 0.2, 5, 0.1, debugState.enemyStrength, v => {
    debugState.enemyStrength = v;
  });

  // ─── Undead tuning ─────────────────────────────────────────────────
  addSectionLabel(body, 'Undead');

  addSlider(body, 'HP mult', 0.2, 5, 0.1, debugState.undeadHpMult, v => {
    debugState.undeadHpMult = v;
  });
  addSlider(body, 'Speed mult', 0.2, 5, 0.1, debugState.undeadSpeedMult, v => {
    debugState.undeadSpeedMult = v;
  });
  addSlider(body, 'Dmg mult', 0.2, 5, 0.1, debugState.undeadDmgMult, v => {
    debugState.undeadDmgMult = v;
  });

  // ─── Enemy tuning ─────────────────────────────────────────────────
  addSectionLabel(body, 'Enemies');

  addSlider(body, 'HP mult', 0.2, 5, 0.1, debugState.enemyHpMult, v => {
    debugState.enemyHpMult = v;
  });
  addSlider(body, 'Speed mult', 0.2, 5, 0.1, debugState.enemySpeedMult, v => {
    debugState.enemySpeedMult = v;
  });
  addSlider(body, 'Dmg mult', 0.2, 5, 0.1, debugState.enemyDmgMult, v => {
    debugState.enemyDmgMult = v;
  });

  // ─── Casting tuning ────────────────────────────────────────────────
  addSectionLabel(body, 'Casting');

  addSlider(body, 'Essence x', 1, 5, 1, debugState.essenceDropRate, v => {
    debugState.essenceDropRate = v;
  });
  addSlider(body, 'Cooldown', 0, 3, 0.1, debugState.cooldownDuration, v => {
    debugState.cooldownDuration = v;
  });
  addSlider(body, 'Hit Radius', 20, 80, 2, debugState.runeHitRadius, v => {
    debugState.runeHitRadius = v;
    setRuneHitRadius(v);
  });

  // ─── Actions ───────────────────────────────────────────────────────
  addSectionLabel(body, 'Actions');

  addButton(body, '+5 Essences', onAddEssence);
  addButton(body, '+10 Undead', () => {
    // Dispatched via custom event so main.ts can handle
    window.dispatchEvent(new CustomEvent('debug-spawn-undead', { detail: 10 }));
  });
  addButton(body, 'Reset', onReset);
}

function addSectionLabel(parent: HTMLElement, text: string) {
  const el = document.createElement('div');
  el.style.cssText = 'color:#666;font-size:10px;text-transform:uppercase;letter-spacing:1px;margin-top:4px;border-top:1px solid #333;padding-top:4px;';
  el.textContent = text;
  parent.appendChild(el);
}

function addButton(parent: HTMLElement, text: string, onClick: () => void) {
  const btn = document.createElement('button');
  btn.className = 'debug-btn';
  btn.textContent = text;
  btn.addEventListener('click', onClick);
  parent.appendChild(btn);
}

function addSlider(
  parent: HTMLElement,
  label: string,
  min: number,
  max: number,
  step: number,
  initial: number,
  onChange: (v: number) => void,
) {
  const row = document.createElement('div');
  row.className = 'debug-row';

  const lbl = document.createElement('label');
  lbl.textContent = label;

  const input = document.createElement('input');
  input.type = 'range';
  input.min = String(min);
  input.max = String(max);
  input.step = String(step);
  input.value = String(initial);

  const val = document.createElement('span');
  val.className = 'val';
  val.textContent = String(initial);

  input.addEventListener('input', () => {
    const v = parseFloat(input.value);
    val.textContent = String(Math.round(v * 10) / 10);
    onChange(v);
  });

  row.appendChild(lbl);
  row.appendChild(input);
  row.appendChild(val);
  parent.appendChild(row);
}
