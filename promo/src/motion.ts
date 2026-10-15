// Frame-pure motion helpers. Everything is a function of the frame, so every render is identical.
export const clamp = (x: number, a = 0, b = 1) => Math.min(b, Math.max(a, x));
export const lerp = (a: number, b: number, t: number) => a + (b - a) * t;
export const minJerk = (t: number) => { t = clamp(t); return t * t * t * (10 + t * (-15 + 6 * t)); };
export const easeOut = (t: number) => 1 - Math.pow(1 - clamp(t), 3);
export const expoOut = (t: number) => (t >= 1 ? 1 : 1 - Math.pow(2, -10 * clamp(t)));
export const easeInOut = (t: number) => { t = clamp(t); return t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2; };
export const easeIn = (t: number) => Math.pow(clamp(t), 3);

/** progress 0..1 between frame a and frame a+d, eased */
export const prog = (f: number, a: number, d: number, ease: (t: number) => number = minJerk) => ease(clamp((f - a) / d));

/**
 * Damped spring step response, sampled at frame f after start (60 fps).
 * stiffness k, damping ratio z (below 1 overshoots). Matches web/src/spring.ts (mass 1).
 */
export const spring = (f: number, start: number, k = 300, z = 1) => {
  const t = (f - start) / 60;
  if (t <= 0) return 0;
  const w = Math.sqrt(k);
  if (z >= 1) return 1 - Math.exp(-w * t) * (1 + w * t);
  const wd = w * Math.sqrt(1 - z * z);
  return 1 - Math.exp(-z * w * t) * (Math.cos(wd * t) + ((z * w) / wd) * Math.sin(wd * t));
};
/** web/src snappy: k 420, slight overshoot */
export const snappy = (f: number, s: number) => spring(f, s, 420, 0.72);
export const soft = (f: number, s: number) => spring(f, s, 160, 1);

/** fade in over [a, a+i], out over [b-o, b] */
export const window01 = (f: number, a: number, b: number, i = 12, o = 12) => Math.min(clamp((f - a) / i), clamp((b - f) / o));

/** Quadratic bezier with a sideways bend, as in web/src/hero.ts */
export type P = [number, number];
export const bend = (a: P, b: P, k: number, u: number): P => {
  const mx = (a[0] + b[0]) / 2, my = (a[1] + b[1]) / 2;
  const dx = b[0] - a[0], dy = b[1] - a[1], len = Math.hypot(dx, dy) || 1;
  const cx = mx - (dy / len) * k, cy = my + (dx / len) * k, iu = 1 - u;
  return [iu * iu * a[0] + 2 * iu * u * cx + u * u * b[0], iu * iu * a[1] + 2 * iu * u * cy + u * u * b[1]];
};
