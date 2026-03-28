import './style.css';
import { GameLoop } from './game/GameLoop';

// Setup canvas
const canvas = document.getElementById('gameCanvas') as HTMLCanvasElement;
const ctx = canvas.getContext('2d')!;

// Set canvas size to match window
function resizeCanvas() {
  canvas.width = window.innerWidth;
  canvas.height = window.innerHeight;
}

resizeCanvas();
window.addEventListener('resize', resizeCanvas);

// Initialize and start game
const game = new GameLoop(canvas, ctx);
game.start();

// Prevent pull-to-refresh and other touch behaviors on mobile
document.addEventListener('touchmove', (e) => e.preventDefault(), { passive: false });
