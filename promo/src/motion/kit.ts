import { clamp, ease, FPS, INOUT, lerp, OUT } from "./lib";

/* Time in seconds for scene code: every helper takes the current time t (seconds). */

export const fr = (s: number) => Math.round(s * FPS);
/** 0..1 between t0 and t0 + d seconds, eased. */
export const E = (t: number, t0: number, d: number, e: (u: number) => number = OUT) => ease(t * FPS, t0 * FPS, d * FPS, e);
/** Keyframes [time, value] eased between each pair. */
export function K(t: number, k: [number, number][], e: (u: number) => number = INOUT) {
  if (t <= k[0][0]) return k[0][1];
  for (let i = 1; i < k.length; i++) if (t <= k[i][0]) return lerp(k[i - 1][1], k[i][1], e(clamp((t - k[i - 1][0]) / (k[i][0] - k[i - 1][0]))));
  return k[k.length - 1][1];
}
/** Keyframes of points. */
export function KP(t: number, k: [number, number, number][], e: (u: number) => number = INOUT): [number, number] {
  return [K(t, k.map(([a, x]) => [a, x] as [number, number]), e), K(t, k.map(([a, , y]) => [a, y] as [number, number]), e)];
}
/** A damped spring from 0 to 1 that starts at t0 (seconds): stiffness and damping like SwiftUI's
    response / dampingFraction. */
export function SP(t: number, t0: number, response = 0.38, damping = 0.82) {
  const d = t - t0;
  if (d <= 0) return 0;
  const w = (2 * Math.PI) / response, z = damping;
  if (z >= 1) return 1 - Math.exp(-w * d) * (1 + w * d);
  const wd = w * Math.sqrt(1 - z * z);
  return 1 - Math.exp(-z * w * d) * (Math.cos(wd * d) + (z * w / wd) * Math.sin(wd * d));
}
/** A tap at t0 seconds: finger in and out, the tile press, the ring. */
export function TAP(t: number, t0: number) {
  const land = E(t, t0 - 0.15, 0.15);
  const lift = E(t, t0 + 0.12, 0.22);
  const o = land * (1 - lift);
  const s = lerp(0.72, 1, land) * lerp(1, 1.12, lift);
  const press = t < t0 ? 1 : t < t0 + 0.1 ? lerp(1, 0.95, E(t, t0, 0.07)) : lerp(0.95, 1, SP(t, t0 + 0.1, 0.32, 0.55));
  const ring = t >= t0 ? clamp((t - t0) / 0.55) : 0;
  return { o, s, press, ring };
}
/** The active tap among several. */
export function TAPS(t: number, ts: number[]) {
  let best = { o: 0, s: 1, press: 1, ring: 0 };
  for (const t0 of ts) if (t >= t0 - 0.2 && t <= t0 + 0.8) best = TAP(t, t0);
  return best;
}
export const step = (t: number, t0: number) => (t >= t0 ? 1 : 0);
export { clamp, lerp, OUT, INOUT };
