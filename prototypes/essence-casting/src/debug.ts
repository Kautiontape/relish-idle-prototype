import { setRuneHitRadius, RUNE_HIT_RADIUS } from './runes.ts';

export interface DebugState {
  spawnRate: number;
  enemyStrength: number;
  essenceDropRate: number;
  cooldownDuration: number;
  runeHitRadius: number;
}

export const debugState: DebugState = {
  spawnRate: 1,
  enemyStrength: 1,
  essenceDropRate: 1,
  cooldownDuration: 1.0,
  runeHitRadius: RUNE_HIT_RADIUS,
};

export type ResetCallback = () => void;
export type AddEssenceCallback = () => void;

export function initDebugPanel(onReset: ResetCallback, onAddEssence: AddEssenceCallback) {
  const header = document.getElementById('debug-header')!;
  const body = document.getElementById('debug-body')!;

  let collapsed = false;
  header.addEventListener('click', () => {
    collapsed = !collapsed;
    body.classList.toggle('collapsed', collapsed);
    header.textContent = collapsed ? 'Debug [+]' : 'Debug';
  });

  // Spawn rate
  addSlider(body, 'Spawn Rate', 0.1, 5, 0.1, debugState.spawnRate, v => {
    debugState.spawnRate = v;
  });

  // Enemy strength
  addSlider(body, 'Enemy Str', 0.2, 5, 0.1, debugState.enemyStrength, v => {
    debugState.enemyStrength = v;
  });

  // Essence drop rate
  addSlider(body, 'Essence x', 1, 3, 1, debugState.essenceDropRate, v => {
    debugState.essenceDropRate = v;
  });

  // Cooldown
  addSlider(body, 'Cooldown', 0.2, 3, 0.1, debugState.cooldownDuration, v => {
    debugState.cooldownDuration = v;
  });

  // Rune hit radius
  addSlider(body, 'Hit Radius', 20, 80, 2, debugState.runeHitRadius, v => {
    debugState.runeHitRadius = v;
    setRuneHitRadius(v);
  });

  // +5 essences button
  const btnAdd = document.createElement('button');
  btnAdd.className = 'debug-btn';
  btnAdd.textContent = '+5 Essences';
  btnAdd.addEventListener('click', onAddEssence);
  body.appendChild(btnAdd);

  // Reset button
  const btnReset = document.createElement('button');
  btnReset.className = 'debug-btn';
  btnReset.textContent = 'Reset';
  btnReset.addEventListener('click', onReset);
  body.appendChild(btnReset);
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
