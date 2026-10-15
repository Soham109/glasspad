/** A damped spring, mass 1. Semi-implicit Euler, stable at any frame rate. */
export class Spring {
  x: number; v = 0; target: number;
  constructor(x = 0, public k = 300, public c = 30) { this.x = x; this.target = x; }
  step(dt: number) {
    // sub-step so long frames stay stable
    let t = Math.min(dt, 0.064);
    while (t > 0) {
      const h = Math.min(t, 1 / 240);
      const a = this.k * (this.target - this.x) - this.c * this.v;
      this.v += a * h; this.x += this.v * h; t -= h;
    }
  }
  set(x: number) { this.x = x; this.target = x; this.v = 0; }
  get settled() { return Math.abs(this.target - this.x) < 0.001 && Math.abs(this.v) < 0.001; }
}
/** Critical damping for a given stiffness, times a ratio (below 1 overshoots). */
export const damp = (k: number, ratio = 1) => 2 * Math.sqrt(k) * ratio;

export const minJerk = (t: number) => t * t * t * (10 + t * (-15 + 6 * t));
export const clamp = (x: number, a: number, b: number) => Math.min(b, Math.max(a, x));
export const lerp = (a: number, b: number, t: number) => a + (b - a) * t;

export const reducedMotion = () => matchMedia("(prefers-reduced-motion: reduce)").matches;
export const nextFrame = () => new Promise<number>(r => requestAnimationFrame(r));
export const sleep = (ms: number) => new Promise<void>(r => setTimeout(r, ms));
