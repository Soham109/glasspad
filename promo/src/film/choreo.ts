// Frame -> touch state for a list of phone gestures, and what the Mac does with them.
// Pure functions: the picture, the sound cue sheet and the sync check all call these.
import { Stroke, P, CURSOR0 } from "../timeline";
import { clamp, lerp, minJerk, bend, spring } from "../motion";
import type { Finger, Ripple } from "../screens/Trackpad";
import type { DesktopState } from "../screens/Desktop";

/** Phone points to Mac points: a full-width swipe covers about 60 percent of the display (docs/SPEC.md section 6). */
export const GAIN = (0.6 * 1512) / 874;
const easeInSine = (u: number) => 1 - Math.cos((clamp(u) * Math.PI) / 2); // still moving at lift, for flicks
const TAU = 20; // momentum time constant, frames

const touchIn = (f: number, down: number) => minJerk((f - down) / 10);
const lift = (f: number, up: number) => minJerk((f - up) / 13);

export const strokeU = (s: Extract<Stroke, { ms: number }>, f: number) => {
  const u = clamp((f - s.ms) / (s.me - s.ms));
  return s.kind === "move" ? minJerk(u) : s.kind === "scroll" ? easeInSine(u) : u < 0.5 ? 2 * u * u : 1 - Math.pow(-2 * u + 2, 2) / 2;
};

const movePos = (s: Extract<Stroke, { kind: "move" }>, f: number): P => bend(s.a, s.b, s.k, strokeU(s, f));

export const fingersAt = (strokes: Stroke[], f: number): Finger[] => {
  const out: Finger[] = [];
  for (const s of strokes) {
    if (s.kind === "tap") {
      if (f < s.at - 8 || f > s.at + 22) continue;
      const tin = minJerk((f - (s.at - 8)) / 7), tl = lift(f, s.at + 8);
      const press = f >= s.at && f < s.at + 6 ? 0.88 : 1;
      out.push({ x: s.x, y: s.y, o: tin * (1 - tl), s: lerp(0.7, 1, tin) * press * lerp(1, 1.12, tl) });
      continue;
    }
    if (f < s.down || f > s.up + 14) continue;
    const tin = touchIn(f, s.down), tl = lift(f, s.up);
    const o = tin * (1 - tl), sc = lerp(0.7, 1, tin) * lerp(1, 1.12, tl);
    if (s.kind === "move") {
      const p = movePos(s, f);
      out.push({ x: p[0], y: p[1], o, s: sc });
    } else if (s.kind === "scroll") {
      const u = strokeU(s, f);
      for (const p of s.pts) out.push({ x: p[0], y: p[1] + s.dy * u, o, s: sc });
    } else {
      const u = strokeU(s, f);
      for (const p of s.pts) out.push({ x: p[0] + s.dx * u, y: p[1] + s.dy * u, o, s: sc });
    }
  }
  return out;
};

export const ripplesAt = (strokes: Stroke[], f: number): Ripple[] =>
  strokes.filter((s): s is Extract<Stroke, { kind: "tap" }> => s.kind === "tap" && f >= s.at && f < s.at + 60).map((s) => ({ x: s.x, y: s.y, age: f - s.at, strong: s.strong }));

/** progress of a swipe target (Spaces or Mission Control): follows the fingers, then springs home on lift. */
export const swipeProgress = (s: Extract<Stroke, { kind: "swipe" }>, f: number) => {
  const span = s.target === "space" ? 874 * 0.48 : 402 * 0.48;
  const drag = (u: number) => clamp(Math.abs((s.dx || s.dy) * u) / span, 0, 0.92);
  if (f < s.ms) return 0;
  if (f <= s.up) return drag(strokeU(s, f));
  const p0 = drag(1);
  return p0 + (1 - p0) * spring(f, s.up, 260, 0.8);
};
/** first frame after lift where the swipe lands (progress reaches 1): the snap haptic. */
export const swipeLand = (s: Extract<Stroke, { kind: "swipe" }>) => {
  for (let f = s.up; f < s.up + 120; f++) if (swipeProgress(s, f) >= 0.999) return f;
  return s.up + 30;
};

export const desktopAt = (strokes: Stroke[], f: number): DesktopState => {
  let cx = CURSOR0[0], cy = CURSOR0[1], press = 0, front: "a" | "b" = "a", scroll = 0, space = 0, mission = 0;
  for (const s of strokes) {
    if (s.kind === "move" && f >= s.ms) {
      const p = movePos(s, f);
      cx += GAIN * (p[0] - s.a[0]);
      cy += GAIN * (p[1] - s.a[1]);
    } else if (s.kind === "tap") {
      if (f >= s.at && f < s.at + 7) press = 1;
      if (f >= s.at + 2 && s.label.includes("forward")) front = "b";
    } else if (s.kind === "scroll" && f >= s.ms) {
      const total = GAIN * -s.dy;
      scroll += total * strokeU(s, f);
      if (f > s.up) {
        const v0 = (total * (Math.PI / 2)) / (s.me - s.ms);
        scroll += v0 * TAU * (1 - Math.exp(-(f - s.up) / TAU));
      }
    } else if (s.kind === "swipe") {
      if (s.target === "space") space = Math.max(space, swipeProgress(s, f));
      else mission = Math.max(mission, swipeProgress(s, f));
    }
  }
  return { cursor: { x: cx, y: cy, press, o: 1 }, front, scroll, space, mission };
};
