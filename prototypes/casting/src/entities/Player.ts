import { Config } from '../game/Config';

export class Player {
  x: number;
  y: number;
  size: number;
  color: string;

  constructor(canvasWidth: number, canvasHeight: number) {
    this.x = canvasWidth * Config.PLAYER.X;
    this.y = canvasHeight * Config.PLAYER.Y;
    this.size = Config.PLAYER.SIZE;
    this.color = Config.PLAYER.COLOR;
  }

  update(_deltaTime: number) {
    // Player is now just a position marker
  }

  draw(ctx: CanvasRenderingContext2D) {
    ctx.fillStyle = this.color;
    ctx.fillRect(
      this.x - this.size / 2,
      this.y - this.size / 2,
      this.size,
      this.size
    );

    ctx.strokeStyle = '#ffff00';
    ctx.lineWidth = 2;
    ctx.strokeRect(
      this.x - this.size / 2,
      this.y - this.size / 2,
      this.size,
      this.size
    );
  }
}
