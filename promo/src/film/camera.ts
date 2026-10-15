import { lerp, minJerk, clamp } from "../motion";
export type Cam = { x: number; y: number; z: number };
/** Camera move with zoom interpolated in log space, so pushes feel even. */
export const camLerp = (a: Cam, b: Cam, t: number): Cam => {
  const z = Math.exp(lerp(Math.log(a.z), Math.log(b.z), t));
  // keep the motion of the framed point proportional to the zoom change, so a push does not swing sideways
  const k = Math.abs(b.z - a.z) < 1e-6 ? t : (z - a.z) / (b.z - a.z);
  return { x: lerp(a.x, b.x, k), y: lerp(a.y, b.y, k), z };
};
export type Key = { f: number; cam: Cam; move?: number; cut?: boolean };
/** Piecewise camera: hold each key from its frame; `move` frames to glide in from the previous key (else a cut). */
export const camAt = (keys: Key[], f: number): Cam => {
  let cur = keys[0].cam;
  for (let i = 0; i < keys.length; i++) {
    const k = keys[i];
    if (f < k.f) break;
    if (k.move && i > 0) {
      const prev = cur;
      const t = minJerk(clamp((f - k.f) / k.move));
      cur = camLerp(prev, k.cam, t);
      if (f < k.f + k.move) return cur;
      cur = k.cam;
    } else cur = k.cam;
  }
  return cur;
};
export const toScreen = (c: Cam, W: number, H: number, x: number, y: number) => [W / 2 + (x - c.x) * c.z, H / 2 + (y - c.y) * c.z] as [number, number];
export const worldTransform = (c: Cam, W: number, H: number) => `translate(${W / 2 - c.x * c.z}px, ${H / 2 - c.y * c.z}px) scale(${c.z})`;
