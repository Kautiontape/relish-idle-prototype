import { RUNES, RUNE_IDS, RUNE_HIT_RADIUS, type RuneId } from './Runes';
import type { GestureTracker, PathPoint } from './GestureTracker';
import type { ArchetypeDefinition } from './Archetypes';
import { lookupArchetype } from './Archetypes';
import { Config } from '../Config';

interface RuneFlash {
  runeId: RuneId;
  timer: number;
}

interface CastMessage {
  name: string;
  description: string;
  color: string;
  timer: number;
  runeCount: number;
  descriptionVisible: boolean;
  nameVisible: boolean;
}

interface PromotedName {
  name: string;
  color: string;
  timer: number;
  totalTime: number;
  yOffset: number;
  fontSize: number;
  settled: boolean;
}

interface UnwindTrail {
  path: PathPoint[];
  totalLength: number;
  color: string;
  elapsed: number;
  duration: number;
}

const SHRINK_SLIDE_DURATION = 0.2;
const PROMOTED_Y = 0.87;
const PROMOTED_FONT_SIZE = 14;
const CAST_NAME_FONT_SIZE = 28;
const CAST_NAME_Y = 0.91;

export class SpellRenderer {
  private runeFlashes: RuneFlash[] = [];
  private castMessage: CastMessage | null = null;
  private promotedName: PromotedName | null = null;
  private fizzleTimer = 0;
  private pulseTime = 0;

  // Unwind state
  private unwindTrail: UnwindTrail | null = null;

  get isUnwinding(): boolean {
    return this.unwindTrail !== null;
  }

  update(deltaTime: number) {
    this.pulseTime += deltaTime;

    // Update rune flashes
    for (const flash of this.runeFlashes) {
      flash.timer -= deltaTime;
    }
    this.runeFlashes = this.runeFlashes.filter(f => f.timer > 0);

    // Update cast message
    if (this.castMessage) {
      this.castMessage.timer -= deltaTime;
      if (this.castMessage.timer <= 0) {
        this.castMessage = null;
      }
    }

    // Update promoted name
    if (this.promotedName) {
      this.promotedName.timer -= deltaTime;

      if (!this.promotedName.settled) {
        const lerpSpeed = deltaTime / SHRINK_SLIDE_DURATION;
        this.promotedName.yOffset += (PROMOTED_Y - this.promotedName.yOffset) * Math.min(1, lerpSpeed);
        this.promotedName.fontSize += (PROMOTED_FONT_SIZE - this.promotedName.fontSize) * Math.min(1, lerpSpeed);

        if (Math.abs(this.promotedName.yOffset - PROMOTED_Y) < 0.001 && Math.abs(this.promotedName.fontSize - PROMOTED_FONT_SIZE) < 0.5) {
          this.promotedName.yOffset = PROMOTED_Y;
          this.promotedName.fontSize = PROMOTED_FONT_SIZE;
          this.promotedName.settled = true;
        }
      }

      if (this.promotedName.timer <= 0) {
        this.promotedName = null;
      }
    }

    // Update fizzle
    if (this.fizzleTimer > 0) {
      this.fizzleTimer -= deltaTime;
    }

    // Update unwind
    if (this.unwindTrail) {
      this.unwindTrail.elapsed += deltaTime;
      if (this.unwindTrail.elapsed >= this.unwindTrail.duration) {
        this.unwindTrail = null;
      }
    }
  }

  onGestureStart() {
    if (this.castMessage) {
      this.castMessage.descriptionVisible = false;
    }
  }

  onRuneHit(runeId: RuneId) {
    this.runeFlashes.push({ runeId, timer: 0.5 });

    // Promote cast name to row 3 on first rune hit of a new gesture
    if (this.castMessage && this.castMessage.nameVisible) {
      this.promotedName = {
        name: this.castMessage.name,
        color: this.castMessage.color,
        timer: this.castMessage.timer,
        totalTime: Config.SPELL.INCANTATION_DISPLAY_TIME,
        yOffset: CAST_NAME_Y,
        fontSize: CAST_NAME_FONT_SIZE,
        settled: false,
      };
      this.castMessage.nameVisible = false;
    }
  }

  onSpellCast(archetype: ArchetypeDefinition, path: PathPoint[], lastRuneColor: string) {
    this.castMessage = {
      name: archetype.name,
      description: archetype.description,
      color: archetype.color,
      timer: Config.SPELL.INCANTATION_DISPLAY_TIME,
      runeCount: archetype.runeSequence.length,
      descriptionVisible: true,
      nameVisible: true,
    };

    // Start unwind: burn the trail backwards over the cooldown duration
    const totalLength = computePathLength(path);
    this.unwindTrail = {
      path: [...path],
      totalLength,
      color: lastRuneColor,
      elapsed: 0,
      duration: Config.SPELL.COOLDOWN,
    };
  }

  onFizzle() {
    this.fizzleTimer = 1.5;
  }

  draw(ctx: CanvasRenderingContext2D, tracker: GestureTracker, canvasWidth: number, canvasHeight: number) {
    this.drawRunes(ctx, tracker, canvasWidth, canvasHeight);

    if (tracker.isActive) {
      this.drawActiveTrail(ctx, tracker);
    }

    // Draw unwinding trail (cooldown visual)
    if (this.unwindTrail) {
      this.drawUnwindTrail(ctx);
    }

    this.drawPromotedName(ctx, canvasWidth, canvasHeight);
    this.drawIncantation(ctx, tracker, canvasWidth, canvasHeight);
    this.drawCastMessage(ctx, canvasWidth, canvasHeight);
    this.drawFizzle(ctx, canvasWidth, canvasHeight);
  }

  private drawRunes(ctx: CanvasRenderingContext2D, tracker: GestureTracker, canvasWidth: number, canvasHeight: number) {
    for (const id of RUNE_IDS) {
      const rune = RUNES[id];
      const x = rune.position.x * canvasWidth;
      const y = rune.position.y * canvasHeight;
      const isHit = tracker.isActive && tracker.activeHitRunes.has(id);
      const flash = this.runeFlashes.find(f => f.runeId === id);

      ctx.save();

      if (flash) {
        const alpha = flash.timer / 0.5;
        ctx.globalAlpha = 0.4 + alpha * 0.6;
        ctx.beginPath();
        ctx.arc(x, y, RUNE_HIT_RADIUS + 10 * alpha, 0, Math.PI * 2);
        ctx.fillStyle = rune.color;
        ctx.fill();
      }

      if (isHit) {
        ctx.globalAlpha = 0.2;
      } else {
        const pulse = 0.3 + Math.sin(this.pulseTime * 2 + RUNE_IDS.indexOf(id) * 1.5) * 0.1;
        ctx.globalAlpha = pulse;
      }

      ctx.beginPath();
      ctx.arc(x, y, RUNE_HIT_RADIUS, 0, Math.PI * 2);
      ctx.fillStyle = rune.color;
      ctx.fill();

      ctx.globalAlpha = isHit ? 0.15 : 0.5;
      ctx.strokeStyle = rune.color;
      ctx.lineWidth = 2;
      ctx.stroke();

      ctx.globalAlpha = isHit ? 0.2 : 0.6;
      ctx.fillStyle = '#fff';
      ctx.font = 'bold 11px monospace';
      ctx.textAlign = 'center';
      ctx.textBaseline = 'middle';
      ctx.fillText(rune.name, x, y);

      ctx.restore();
    }
  }

  private drawActiveTrail(ctx: CanvasRenderingContext2D, tracker: GestureTracker) {
    const path = tracker.currentPath;
    if (path.length < 2) return;

    const seq = tracker.currentSequence;
    const lastRune = seq.length > 0 ? RUNES[seq[seq.length - 1]] : null;
    const trailColor = lastRune ? lastRune.color : '#ffffff';

    ctx.save();
    ctx.globalAlpha = 0.6;
    ctx.strokeStyle = trailColor;
    ctx.lineWidth = 3;
    ctx.lineCap = 'round';
    ctx.lineJoin = 'round';

    ctx.beginPath();
    ctx.moveTo(path[0].x, path[0].y);
    for (let i = 1; i < path.length; i++) {
      ctx.lineTo(path[i].x, path[i].y);
    }
    ctx.stroke();

    ctx.globalAlpha = 0.2;
    ctx.lineWidth = 8;
    ctx.stroke();

    ctx.restore();
  }

  private drawUnwindTrail(ctx: CanvasRenderingContext2D) {
    const trail = this.unwindTrail!;
    const progress = trail.elapsed / trail.duration; // 0→1
    // We want to show the trail shrinking from the END backwards
    // At progress=0 the full trail is visible, at progress=1 it's gone
    const keepLength = trail.totalLength * (1 - progress);

    if (keepLength <= 0 || trail.path.length < 2) return;

    // Walk from the START of the path, accumulating length, and draw only up to keepLength
    const subPath = getSubPathByLength(trail.path, keepLength);
    if (subPath.length < 2) return;

    ctx.save();

    // Fade alpha as it unwinds
    const alpha = 0.3 + 0.3 * (1 - progress);
    ctx.globalAlpha = alpha;
    ctx.strokeStyle = trail.color;
    ctx.lineWidth = 3;
    ctx.lineCap = 'round';
    ctx.lineJoin = 'round';

    ctx.beginPath();
    ctx.moveTo(subPath[0].x, subPath[0].y);
    for (let i = 1; i < subPath.length; i++) {
      ctx.lineTo(subPath[i].x, subPath[i].y);
    }
    ctx.stroke();

    // Glow
    ctx.globalAlpha = alpha * 0.3;
    ctx.lineWidth = 8;
    ctx.stroke();

    // Bright tip at the burning end
    const tip = subPath[subPath.length - 1];
    ctx.globalAlpha = alpha + 0.2;
    ctx.beginPath();
    ctx.arc(tip.x, tip.y, 4, 0, Math.PI * 2);
    ctx.fillStyle = '#fff';
    ctx.fill();

    ctx.restore();
  }

  private drawPromotedName(ctx: CanvasRenderingContext2D, canvasWidth: number, canvasHeight: number) {
    if (!this.promotedName) return;

    const pn = this.promotedName;
    const alpha = Math.min(1, pn.timer / 0.5) * 0.7;
    const y = pn.yOffset * canvasHeight;

    ctx.save();
    ctx.globalAlpha = alpha;
    ctx.fillStyle = pn.color;
    ctx.font = `bold ${Math.round(pn.fontSize)}px serif`;
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    ctx.fillText(pn.name, canvasWidth / 2, y);
    ctx.restore();
  }

  private drawIncantation(ctx: CanvasRenderingContext2D, tracker: GestureTracker, canvasWidth: number, canvasHeight: number) {
    const seq = tracker.isActive ? tracker.currentSequence : null;
    if (!seq || seq.length === 0) return;

    const archetype = seq.length >= Config.SPELL.MIN_RUNES ? lookupArchetype(seq) : undefined;
    const cx = canvasWidth / 2;

    ctx.save();
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';

    // Backdrop pill spanning preview zone
    const pillTop = canvasHeight * 0.88;
    const pillBottom = canvasHeight * 0.97;
    ctx.globalAlpha = 0.3;
    ctx.fillStyle = '#000';
    ctx.beginPath();
    ctx.roundRect(cx - 140, pillTop, 280, pillBottom - pillTop, 8);
    ctx.fill();

    if (archetype) {
      // 1. Spell name preview — Y=0.91, muted grey
      ctx.globalAlpha = 0.5;
      ctx.fillStyle = '#666';
      ctx.font = 'bold 22px serif';
      ctx.fillText(archetype.name, cx, canvasHeight * 0.91);
    }

    // 2. Rune pills — colored text at Y=0.95 (description slot)
    const runeY = canvasHeight * 0.95;
    const parts = seq.map(id => RUNES[id].name);
    const pillText = parts.join('  \u25C7  ');
    ctx.font = 'bold 14px monospace';
    ctx.globalAlpha = 0.8;
    ctx.fillStyle = '#ddd';
    ctx.fillText(pillText, cx, runeY);

    ctx.restore();
  }

  private drawCastMessage(ctx: CanvasRenderingContext2D, canvasWidth: number, canvasHeight: number) {
    if (!this.castMessage) return;

    const { name, description, color, timer, runeCount, descriptionVisible, nameVisible } = this.castMessage;
    if (!nameVisible && !descriptionVisible) return;

    const totalTime = Config.SPELL.INCANTATION_DISPLAY_TIME;
    let alpha = 1;
    const elapsed = totalTime - timer;
    if (elapsed < 0.3) {
      alpha = elapsed / 0.3;
    } else if (timer < 0.5) {
      alpha = timer / 0.5;
    }

    const nameY = canvasHeight * CAST_NAME_Y;
    const descY = canvasHeight * 0.95;
    const cx = canvasWidth / 2;

    ctx.save();
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';

    // Measure visible content for backdrop pill
    let pillWidth = 24;
    if (nameVisible) {
      ctx.font = `bold ${CAST_NAME_FONT_SIZE}px serif`;
      pillWidth = Math.max(pillWidth, ctx.measureText(name).width + 24);
    }
    if (descriptionVisible) {
      ctx.font = 'italic 16px serif';
      pillWidth = Math.max(pillWidth, ctx.measureText(description).width + 24);
    }

    const pillTop = nameVisible ? nameY - 18 : descY - 12;
    const pillBottom = descriptionVisible ? descY + 12 : nameY + 18;

    // Backdrop pill — continuous coverage, no gap after incantation
    const backdropAlpha = elapsed < 0.3
      ? 0.3 + (0.2 * (elapsed / 0.3))   // 0.3 → 0.5 over 0.3s
      : timer < 0.5
        ? timer / 0.5 * 0.5              // fade out with text
        : 0.5;                            // steady state
    ctx.globalAlpha = backdropAlpha;
    ctx.fillStyle = '#000';
    ctx.beginPath();
    ctx.roundRect(cx - pillWidth / 2, pillTop, pillWidth, pillBottom - pillTop, 6);
    ctx.fill();

    // Color bloom in backdrop pill during first ~0.3s
    if (nameVisible && elapsed < 0.3) {
      const bloomAlpha = 0.15 * (1 - elapsed / 0.3);
      ctx.globalAlpha = bloomAlpha * backdropAlpha;
      ctx.fillStyle = color;
      ctx.beginPath();
      ctx.roundRect(cx - pillWidth / 2, pillTop, pillWidth, pillBottom - pillTop, 6);
      ctx.fill();
    }

    // Draw name in row 2
    if (nameVisible) {
      // Expand-settle on spell name
      const expandDuration = runeCount <= 2 ? 0.15 : runeCount === 3 ? 0.3 : 0.5;
      let scale = 1.0;
      if (elapsed < expandDuration) {
        const t = elapsed / expandDuration;
        const eased = 1 - (1 - t) * (1 - t);
        scale = 1.2 - 0.2 * eased;
      }

      ctx.globalAlpha = alpha;
      ctx.fillStyle = color;
      ctx.font = `bold ${CAST_NAME_FONT_SIZE}px serif`;

      if (scale !== 1.0) {
        ctx.save();
        ctx.translate(cx, nameY);
        ctx.scale(scale, scale);
        ctx.fillText(name, 0, 0);
        ctx.restore();
      } else {
        ctx.fillText(name, cx, nameY);
      }
    }

    // Draw description in row 1
    if (descriptionVisible) {
      ctx.globalAlpha = alpha;
      ctx.fillStyle = '#ccc';
      ctx.font = 'italic 16px serif';
      ctx.fillText(description, cx, descY);
    }

    ctx.restore();
  }

  private drawFizzle(ctx: CanvasRenderingContext2D, canvasWidth: number, canvasHeight: number) {
    if (this.fizzleTimer <= 0) return;

    const alpha = Math.min(1, this.fizzleTimer / 0.5);

    ctx.save();
    ctx.globalAlpha = alpha * 0.6;
    ctx.fillStyle = '#666';
    ctx.font = '24px serif';
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    ctx.fillText('...', canvasWidth / 2, canvasHeight * 0.92);
    ctx.restore();
  }
}

// Helpers

function computePathLength(path: PathPoint[]): number {
  let len = 0;
  for (let i = 1; i < path.length; i++) {
    const dx = path[i].x - path[i - 1].x;
    const dy = path[i].y - path[i - 1].y;
    len += Math.sqrt(dx * dx + dy * dy);
  }
  return len;
}

function getSubPathByLength(path: PathPoint[], maxLength: number): { x: number; y: number }[] {
  const result: { x: number; y: number }[] = [{ x: path[0].x, y: path[0].y }];
  let accumulated = 0;

  for (let i = 1; i < path.length; i++) {
    const dx = path[i].x - path[i - 1].x;
    const dy = path[i].y - path[i - 1].y;
    const segLen = Math.sqrt(dx * dx + dy * dy);

    if (accumulated + segLen >= maxLength) {
      // Interpolate the final point
      const remaining = maxLength - accumulated;
      const t = segLen > 0 ? remaining / segLen : 0;
      result.push({
        x: path[i - 1].x + dx * t,
        y: path[i - 1].y + dy * t,
      });
      break;
    }

    accumulated += segLen;
    result.push({ x: path[i].x, y: path[i].y });
  }

  return result;
}
