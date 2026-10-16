import { Easing, interpolate, spring } from "remotion";

/* Frame-accurate motion: every value is a pure function of the frame, so any frame renders the
   same on its own (no state, no randomness, no CSS transitions). */

export const FPS = 60;
export const OUT = Easing.bezier(0.2, 0, 0, 1); // entrances and moves
export const INOUT = Easing.bezier(0.45, 0, 0.2, 1); // camera moves that start from rest
export const IN = Easing.bezier(0.5, 0, 0.9, 0.4); // exits

export const clamp = (x: number, a = 0, b = 1) => Math.min(b, Math.max(a, x));
export const lerp = (a: number, b: number, t: number) => a + (b - a) * t;
export const sec = (s: number) => Math.round(s * FPS);

/** 0 to 1 over [f0, f0 + dur] frames with an easing, clamped. */
export const ease = (f: number, f0: number, dur: number, e: (t: number) => number = OUT) =>
  dur <= 0 ? (f >= f0 ? 1 : 0) : e(clamp((f - f0) / dur));
/** Interpolate a value from a to b between frames f0 and f0 + dur. */
export const tw = (f: number, f0: number, dur: number, a: number, b: number, e: (t: number) => number = OUT) =>
  lerp(a, b, ease(f, f0, dur, e));

/** A spring from 0 to 1 starting at f0. Soft: no overshoot; snap: slight overshoot. */
export const SOFT = { damping: 26, stiffness: 170, mass: 1 };
export const SNAP = { damping: 15, stiffness: 210, mass: 0.9 };
export const POP = { damping: 12, stiffness: 260, mass: 0.7 };
export const sp = (f: number, f0: number, config = SNAP) =>
  f < f0 ? 0 : spring({ frame: f - f0, fps: FPS, config });

/** A chain of keyframes [frame, value] eased between each pair. */
export function keys(f: number, k: [number, number][], e: (t: number) => number = INOUT) {
  if (f <= k[0][0]) return k[0][1];
  for (let i = 1; i < k.length; i++) {
    if (f <= k[i][0]) return lerp(k[i - 1][1], k[i][1], e(clamp((f - k[i - 1][0]) / (k[i][0] - k[i - 1][0]))));
  }
  return k[k.length - 1][1];
}
/** Same for points. */
export function path(f: number, k: [number, number, number][], e: (t: number) => number = INOUT): [number, number] {
  return [keys(f, k.map(([t, x]) => [t, x]), e), keys(f, k.map(([t, , y]) => [t, y]), e)];
}

/** A tap at t0: the finger lands, presses for 7 frames, lifts. */
export function tap(f: number, t0: number) {
  const land = ease(f, t0 - 10, 10);
  const lift = ease(f, t0 + 8, 14);
  const opacity = land * (1 - lift);
  const scale = lerp(0.7, 1, land) * lerp(1, 1.14, lift);
  // the tile compresses to 96% while pressed and springs back
  const press = f >= t0 && f < t0 + 8 ? lerp(1, 0.96, ease(f, t0, 4)) : f >= t0 + 8 ? lerp(0.96, 1, sp(f, t0 + 8, POP)) : 1;
  const ring = f >= t0 ? clamp((f - t0) / 34) : -1; // the soft ring that expands from the touch
  return { opacity, scale, press, ring, done: f >= t0 };
}
/** Combine several taps on the same target: the active one wins. */
export function taps(f: number, ts: number[]) {
  let best = { opacity: 0, scale: 1, press: 1, ring: -1, done: false };
  for (const t of ts) {
    const r = tap(f, t);
    if (f >= t - 12 && f <= t + 40) best = { ...r, done: true };
  }
  return best;
}

/** Interpolate a hex color. */
export function mixHex(a: string, b: string, t: number) {
  const p = (h: string) => [1, 3, 5].map(i => parseInt(h.slice(i, i + 2), 16));
  const [x, y] = [p(a), p(b)];
  return "#" + x.map((v, i) => Math.round(lerp(v, y[i], clamp(t))).toString(16).padStart(2, "0")).join("");
}

export { interpolate };
