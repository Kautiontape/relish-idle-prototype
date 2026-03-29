import { Application, Graphics } from 'pixi.js';
import { RUNE_IDS, RUNE_HIT_RADIUS, RUNES, runeScreenPos, runeCenter } from './runes.ts';
import { EssenceSystem } from './essences.ts';
import { GestureTracker } from './gestures.ts';
import { Battlefield } from './battlefield.ts';
import { lookupArchetype } from './spells.ts';
import { showCastMessage, updateHUD } from './ui.ts';
import { debugState, initDebugPanel } from './debug.ts';

async function main() {
  const app = new Application();
  await app.init({
    resizeTo: window,
    background: 0x111111,
    antialias: false,
  });
  document.getElementById('game')!.appendChild(app.canvas);

  // Make canvas accept pointer events for gestures
  app.canvas.style.touchAction = 'none';

  // ─── Graphics layers ────────────────────────────────────────────────
  const essenceGfx = new Graphics();
  const undeadGfx = new Graphics();
  const enemyGfx = new Graphics();
  const runeGfx = new Graphics();
  const trailGfx = new Graphics();

  app.stage.addChild(essenceGfx);
  app.stage.addChild(enemyGfx);
  app.stage.addChild(undeadGfx);
  app.stage.addChild(runeGfx);
  app.stage.addChild(trailGfx);

  // ─── Spell preview element ─────────────────────────────────────────
  const previewEl = document.createElement('div');
  previewEl.id = 'spell-preview';
  previewEl.style.cssText =
    'position:absolute;left:50%;transform:translateX(-50%);' +
    'font-size:22px;font-weight:bold;font-family:monospace;' +
    'pointer-events:none;text-shadow:0 0 10px rgba(0,0,0,0.9);' +
    'opacity:0;transition:opacity 0.15s;';
  document.body.appendChild(previewEl);

  // ─── Game over overlay ─────────────────────────────────────────────
  const gameOverEl = document.createElement('div');
  gameOverEl.id = 'game-over';
  gameOverEl.style.cssText =
    'position:absolute;top:0;left:0;width:100%;height:100%;' +
    'display:none;align-items:center;justify-content:center;' +
    'flex-direction:column;background:rgba(0,0,0,0.7);z-index:200;' +
    'pointer-events:auto;font-family:monospace;color:#ff4444;';
  gameOverEl.innerHTML =
    '<div style="font-size:48px;font-weight:bold;margin-bottom:16px;">GAME OVER</div>' +
    '<div style="font-size:18px;color:#ccc;margin-bottom:24px;">All undead have fallen.</div>' +
    '<button id="restart-btn" style="font-size:16px;padding:8px 24px;cursor:pointer;' +
    'background:#333;color:#ccc;border:1px solid #666;border-radius:4px;font-family:monospace;">Restart</button>';
  document.body.appendChild(gameOverEl);

  // ─── Rune name labels (HTML over canvas) ───────────────────────────
  const runeLabels: Record<string, HTMLElement> = {};
  for (const id of RUNE_IDS) {
    const rune = RUNES[id];
    const label = document.createElement('div');
    label.className = 'rune-label';
    label.textContent = rune.name;
    label.style.cssText =
      'position:absolute;pointer-events:none;font-family:monospace;font-weight:bold;' +
      'font-size:11px;text-align:center;transform:translate(-50%,-50%);' +
      'text-shadow:0 0 6px rgba(0,0,0,0.9);transition:opacity 0.15s;';
    document.body.appendChild(label);
    runeLabels[id] = label;
  }

  // ─── Systems ────────────────────────────────────────────────────────
  const essences = new EssenceSystem();
  const battlefield = new Battlefield(
    undeadGfx, enemyGfx,
    app.screen.width, app.screen.height,
  );
  battlefield.essences = essences;

  const gesture = new GestureTracker();
  gesture.essences = essences;
  gesture.setScreenSize(app.screen.width, app.screen.height);

  // Cooldown state
  let cooldownTimer = 0;

  // Pulse clock
  let pulseTime = 0;

  // Vacuum animation state
  interface VacuumParticle { x: number; y: number; tx: number; ty: number; color: number; life: number }
  const vacuumParticles: VacuumParticle[] = [];

  // Start with a few undead
  battlefield.spawnUndead(5);

  // ─── Reset helper ─────────────────────────────────────────────────
  function doReset() {
    battlefield.reset();
    essences.drops.length = 0;
    vacuumParticles.length = 0;
    cooldownTimer = 0;
    battlefield.spawnUndead(5);
    gameOverEl.style.display = 'none';
  }

  // Restart button
  document.getElementById('restart-btn')!.addEventListener('click', doReset);

  // ─── Pointer events for gestures ────────────────────────────────────
  const getPos = (e: PointerEvent) => {
    const rect = app.canvas.getBoundingClientRect();
    return { x: e.clientX - rect.left, y: e.clientY - rect.top };
  };

  app.canvas.addEventListener('pointerdown', (e: PointerEvent) => {
    if (cooldownTimer > 0) return;
    if (battlefield.gameOver) return;
    const { x, y } = getPos(e);
    gesture.startGesture(x, y);
  });

  app.canvas.addEventListener('pointermove', (e: PointerEvent) => {
    const { x, y } = getPos(e);
    gesture.updateGesture(x, y);
  });

  app.canvas.addEventListener('pointerup', () => {
    if (!gesture.isActive) return;
    const result = gesture.endGesture();

    // Clear spell preview
    previewEl.style.opacity = '0';

    if (result.runeSequence.length >= 2) {
      const archetype = lookupArchetype(result.runeSequence);
      if (archetype) {
        // Spell success
        const consumed = essences.consumeClaimed();

        // Vacuum animation: essence positions fly toward Relish
        const vacTarget = runeCenter(app.screen.width, app.screen.height);
        for (const pos of consumed) {
          // Multiple particles per essence for a more visible effect
          for (let p = 0; p < 4; p++) {
            vacuumParticles.push({
              x: pos.x + (Math.random() - 0.5) * 10,
              y: pos.y + (Math.random() - 0.5) * 10,
              tx: vacTarget.x, ty: vacTarget.y,
              color: pos.color ?? 0xffffff,
              life: 0.6 + Math.random() * 0.2,
            });
          }
        }

        // Spawn undead — always 1 per cast
        battlefield.spawnUndead(1);

        // Show cast message
        showCastMessage(archetype.name, archetype.color);

        // Start cooldown
        cooldownTimer = debugState.cooldownDuration;
      } else {
        // Fizzle: no matching archetype
        essences.unclaimAll();
      }
    } else {
      // Too few runes: cancel
      essences.unclaimAll();
    }
  });

  // Cancel on pointer leave
  app.canvas.addEventListener('pointerleave', () => {
    if (gesture.isActive) {
      gesture.cancelGesture();
      essences.unclaimAll();
      previewEl.style.opacity = '0';
    }
  });

  // ─── Resize handler ─────────────────────────────────────────────────
  window.addEventListener('resize', () => {
    battlefield.resize(app.screen.width, app.screen.height);
    gesture.setScreenSize(app.screen.width, app.screen.height);
  });

  // ─── Debug panel ────────────────────────────────────────────────────
  initDebugPanel(
    // Reset
    doReset,
    // +5 essences
    () => {
      const cx = app.screen.width / 2;
      const cy = app.screen.height / 2;
      const types: Array<'flesh' | 'breath' | 'veil' | 'chain'> = ['flesh', 'breath', 'veil', 'chain'];
      for (const t of types) {
        essences.spawn([t], cx + (Math.random() - 0.5) * 200, cy + (Math.random() - 0.5) * 200);
      }
      // One random extra
      const extra = types[Math.floor(Math.random() * types.length)];
      essences.spawn([extra], cx + (Math.random() - 0.5) * 200, cy + (Math.random() - 0.5) * 200);
    },
  );

  // ─── Game loop ──────────────────────────────────────────────────────
  app.ticker.add((ticker) => {
    const dt = ticker.deltaTime / 60; // seconds
    pulseTime += dt;

    // Cooldown
    if (cooldownTimer > 0) {
      cooldownTimer -= dt;
      if (cooldownTimer < 0) cooldownTimer = 0;
    }

    // Check for game over
    if (battlefield.gameOver) {
      gameOverEl.style.display = 'flex';
    }

    // Update systems
    essences.update(dt);
    battlefield.update(dt);

    // Update vacuum particles — fast convergence toward Relish
    for (const p of vacuumParticles) {
      p.life -= dt;
      const t = 1 - Math.max(0, p.life / 0.7);
      const speed = 0.08 + t * 0.15; // accelerates as it approaches
      p.x += (p.tx - p.x) * speed;
      p.y += (p.ty - p.y) * speed;
    }
    // Remove dead particles (filter in place)
    for (let i = vacuumParticles.length - 1; i >= 0; i--) {
      if (vacuumParticles[i].life <= 0) vacuumParticles.splice(i, 1);
    }

    // ─── Draw ───────────────────────────────────────────────────────
    battlefield.draw();

    // Essence orbs
    essenceGfx.clear();
    for (const drop of essences.drops) {
      const color = EssenceSystem.dropColor(drop, pulseTime);
      const alpha = EssenceSystem.dropAlpha(drop);
      const pulse = 3 + Math.sin(pulseTime * 3 + drop.x * 0.1) * 1;
      essenceGfx.fill({ color, alpha });
      essenceGfx.circle(drop.x, drop.y, pulse);
      essenceGfx.fill();
    }

    // Vacuum particles — bigger, colored, obvious
    for (const p of vacuumParticles) {
      const a = Math.min(1, p.life * 2);
      const size = 3 + (1 - p.life / 0.7) * 4; // grows as it converges
      essenceGfx.fill({ color: p.color, alpha: a });
      essenceGfx.circle(p.x, p.y, size);
      essenceGfx.fill();
      // Glow
      essenceGfx.fill({ color: p.color, alpha: a * 0.3 });
      essenceGfx.circle(p.x, p.y, size + 4);
      essenceGfx.fill();
    }

    // Rune circles + Relish marker
    const w = app.screen.width;
    const h = app.screen.height;
    const essenceCounts = essences.counts();
    const center = runeCenter(w, h);

    runeGfx.clear();

    // Relish marker (center of runes) - flash red when hit
    if (battlefield.relishHitFlash > 0) {
      const flashAlpha = 0.4 + battlefield.relishHitFlash * 1.0;
      runeGfx.fill({ color: 0xFF0000, alpha: Math.min(1, flashAlpha) });
      runeGfx.circle(center.x, center.y, 12);
      runeGfx.fill();
    }
    runeGfx.fill({ color: 0xFFD000, alpha: 0.6 });
    runeGfx.circle(center.x, center.y, 8);
    runeGfx.fill();
    runeGfx.stroke({ color: 0xFFD000, alpha: 0.3, width: 2 });
    runeGfx.circle(center.x, center.y, 14);
    runeGfx.stroke();

    for (const id of RUNE_IDS) {
      const rune = RUNES[id];
      const pos = runeScreenPos(id, w, h);
      const hasEssence = essenceCounts[id] > 0;
      const isHit = gesture.isActive && gesture.activeHitRunes.has(id);
      const inCooldown = cooldownTimer > 0;

      if (inCooldown) {
        // Cooldown: very dim
        runeGfx.fill({ color: 0x333333, alpha: 0.15 });
        runeGfx.circle(pos.x, pos.y, RUNE_HIT_RADIUS);
        runeGfx.fill();
        runeGfx.stroke({ color: 0x333333, alpha: 0.2, width: 1 });
        runeGfx.circle(pos.x, pos.y, RUNE_HIT_RADIUS);
        runeGfx.stroke();
      } else if (isHit) {
        // Hit during gesture: bright flash
        runeGfx.fill({ color: rune.colorNum, alpha: 0.5 });
        runeGfx.circle(pos.x, pos.y, RUNE_HIT_RADIUS + 4);
        runeGfx.fill();
        runeGfx.stroke({ color: 0xffffff, alpha: 0.8, width: 3 });
        runeGfx.circle(pos.x, pos.y, RUNE_HIT_RADIUS + 4);
        runeGfx.stroke();
      } else if (hasEssence) {
        // ACTIVE: bright, pulsing, obvious
        const pulse = 0.5 + Math.sin(pulseTime * 3 + RUNE_IDS.indexOf(id) * 1.5) * 0.2;
        const glowSize = RUNE_HIT_RADIUS + 2 + Math.sin(pulseTime * 3 + RUNE_IDS.indexOf(id)) * 3;
        // Outer glow
        runeGfx.fill({ color: rune.colorNum, alpha: pulse * 0.2 });
        runeGfx.circle(pos.x, pos.y, glowSize + 8);
        runeGfx.fill();
        // Main circle
        runeGfx.fill({ color: rune.colorNum, alpha: pulse * 0.7 });
        runeGfx.circle(pos.x, pos.y, glowSize);
        runeGfx.fill();
        runeGfx.stroke({ color: rune.colorNum, alpha: 0.9, width: 2 });
        runeGfx.circle(pos.x, pos.y, glowSize);
        runeGfx.stroke();
      } else {
        // INACTIVE: clearly present but obviously dim
        runeGfx.fill({ color: 0x222222, alpha: 0.2 });
        runeGfx.circle(pos.x, pos.y, RUNE_HIT_RADIUS);
        runeGfx.fill();
        runeGfx.stroke({ color: 0x444444, alpha: 0.3, width: 1 });
        runeGfx.circle(pos.x, pos.y, RUNE_HIT_RADIUS);
        runeGfx.stroke();
      }
    }

    // Update rune name labels
    for (const id of RUNE_IDS) {
      const label = runeLabels[id];
      const rune = RUNES[id];
      const pos = runeScreenPos(id, w, h);
      const hasEssence = essenceCounts[id] > 0;
      const inCooldown = cooldownTimer > 0;

      label.style.left = `${pos.x}px`;
      label.style.top = `${pos.y}px`;

      if (inCooldown) {
        label.style.color = '#333';
        label.style.opacity = '0.3';
      } else if (hasEssence) {
        label.style.color = rune.color;
        label.style.opacity = '1';
      } else {
        label.style.color = '#555';
        label.style.opacity = '0.5';
      }
    }

    // Gesture trail
    trailGfx.clear();
    if (gesture.isActive) {
      const path = gesture.currentPath;
      if (path.length >= 2) {
        const seq = gesture.currentSequence;
        const lastRune = seq.length > 0 ? RUNES[seq[seq.length - 1]] : null;
        const trailColor = lastRune ? lastRune.colorNum : 0xffffff;

        trailGfx.stroke({ color: trailColor, alpha: 0.6, width: 3 });
        trailGfx.moveTo(path[0].x, path[0].y);
        for (let i = 1; i < path.length; i++) {
          trailGfx.lineTo(path[i].x, path[i].y);
        }
        trailGfx.stroke();

        // Glow
        trailGfx.stroke({ color: trailColor, alpha: 0.15, width: 8 });
        trailGfx.moveTo(path[0].x, path[0].y);
        for (let i = 1; i < path.length; i++) {
          trailGfx.lineTo(path[i].x, path[i].y);
        }
        trailGfx.stroke();
      }

      // Spell preview: show archetype name when 2+ runes are hit
      if (gesture.currentSequence.length >= 2) {
        const previewArchetype = lookupArchetype(gesture.currentSequence);
        if (previewArchetype) {
          previewEl.textContent = previewArchetype.name;
          previewEl.style.color = previewArchetype.color;
          // Position above the rune area
          const areaH = Math.min(350, h * 0.4);
          const previewY = h - areaH - 50;
          previewEl.style.top = `${previewY}px`;
          previewEl.style.opacity = '1';
        } else {
          previewEl.textContent = '???';
          previewEl.style.color = '#666';
          const areaH = Math.min(350, h * 0.4);
          previewEl.style.top = `${h - areaH - 50}px`;
          previewEl.style.opacity = '0.5';
        }
      } else {
        previewEl.style.opacity = '0';
      }
    } else {
      previewEl.style.opacity = '0';
    }

    // HUD
    updateHUD(essences, battlefield, dt);
  });
}

main();
