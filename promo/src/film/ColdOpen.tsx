import React from "react";
import { AbsoluteFill } from "remotion";
import { C, FONT } from "../theme";
import { bend, clamp, lerp, minJerk, prog, spring, easeIn, P } from "../motion";
import { Cam, toScreen } from "./camera";
import { Layout, geom } from "./layout";

/* The app icon (docs/brand/icon.svg, 1024 grid) as a living thing: a finger dot glides, the camera pulls
   back and the glide turns out to be the icon. Then the icon's surface becomes the phone's screen. */
/** Opaque flat mix of ink over the icon surface, so the dot never shows the trail through it. */
const mixInk = (a: number) => {
  const c = (s: number, i: number) => Math.round(s + (i - s) * a);
  return `rgb(${c(251, 26)},${c(251, 26)},${c(249, 26)})`;
};
type Glide = { down: number; ms: number; me: number; a: P; b: P; k: number; liftAt?: number };
export type ColdOpenTiming = { focus0?: P; glides: Glide[]; pull: [number, number]; word: number; tag: number; exit: number; morph: [number, number]; zFrom: number; zTo: number; center: [number, number] };

export const coldOpenTaps = (t: ColdOpenTiming) => t.glides.map((g) => g.down);

const dotState = (f: number, g: Glide) => {
  // touch: scale 0.8 -> 1 with a little overshoot, alpha up (web/src/hero.ts)
  const sc = 0.8 + 0.2 * spring(f, g.down, 420, 0.6);
  const al = clamp(spring(f, g.down, 260, 1));
  const u = minJerk((f - g.ms) / (g.me - g.ms));
  let tail = 0, lift = 0;
  if (g.liftAt !== undefined) {
    tail = clamp(spring(f, g.me + 4, 110, 1));
    lift = f >= g.liftAt ? clamp(spring(f, g.liftAt, 200, 1)) : 0;
  }
  return { sc: sc * (1 + 0.14 * lift), al: al * (1 - lift), u, tail };
};

export const ColdOpen: React.FC<{ f: number; t: ColdOpenTiming; l: Layout; phoneCam: Cam; W: number; H: number }> = ({ f, t, l, phoneCam, W, H }) => {
  if (f >= t.morph[1]) return null;
  // icon camera: zoom from inside the surface out to the icon
  const pu = minJerk((f - t.pull[0]) / (t.pull[1] - t.pull[0]));
  const z = Math.exp(lerp(Math.log(t.zFrom), Math.log(t.zTo), pu));
  const f0 = t.focus0 ?? [520, 540];
  const focus: P = [lerp(f0[0], 512, pu), lerp(f0[1], 512, pu)];
  const cx = W / 2, cy = lerp(H / 2, t.center[1], pu);
  const tr = (x: number, y: number): P => [cx + (x - focus[0]) * z, cy + (y - focus[1]) * z];

  // morph: icon surface rect -> phone screen rect (as framed by phoneCam)
  const g = geom(l);
  const [sx, sy] = toScreen(phoneCam, W, H, g.scr.x, g.scr.y);
  const target = { x: sx, y: sy, w: g.scr.w * phoneCam.z, h: g.scr.h * phoneCam.z, r: g.scr.r * phoneCam.z };
  const m = minJerk((f - t.morph[0]) / (t.morph[1] - t.morph[0] - 6));
  const [ix, iy] = tr(102, 222);
  const icon = { x: ix, y: iy, w: 820 * z, h: 580 * z, r: 140 * z };
  const rect = { x: lerp(icon.x, target.x, m), y: lerp(icon.y, target.y, m), w: lerp(icon.w, target.w, m), h: lerp(icon.h, target.h, m), r: lerp(icon.r, target.r, m) };
  const tileO = 1 - prog(f, t.morph[0], 26);
  const [tx, ty] = tr(0, 0);
  const strokeO = 1 - m;

  // dots and trails
  const dots = t.glides.map((gl, i) => {
    if (f < gl.down) return null;
    const d = dotState(f, gl);
    if (d.al <= 0.002) return null;
    const head = bend(gl.a, gl.b, gl.k, d.u);
    const u0 = gl.liftAt !== undefined ? Math.min(d.u, d.tail) : 0;
    const pts: string[] = [];
    for (let k = 0; k <= 24; k++) {
      const p = bend(gl.a, gl.b, gl.k, u0 + (d.u - u0) * (k / 24));
      const s = tr(p[0], p[1]);
      pts.push(`${s[0].toFixed(1)} ${s[1].toFixed(1)}`);
    }
    // the final glide is the icon itself; it lifts when the icon becomes the phone
    const morphLift = i === t.glides.length - 1 ? 1 - prog(f, t.morph[0] + 26, 18) : 1;
    const hs = tr(head[0], head[1]);
    return (
      <g key={i}>
        <path d={"M" + pts.join(" L")} fill="none" stroke={C.ink} strokeOpacity={0.1 * d.al * morphLift} strokeWidth={90 * z} strokeLinecap="round" strokeLinejoin="round" />
        <circle cx={hs[0]} cy={hs[1]} r={74 * z * d.sc * (i === t.glides.length - 1 ? 1 + 0.14 * prog(f, t.morph[0] + 26, 18) : 1)} fill={mixInk(0.62 * d.al)} opacity={morphLift} />
      </g>
    );
  });

  const wordIn = (k: number) => spring(f, t.word + k * 2.4, 200, 0.82);
  const out = easeIn(clamp((f - t.exit) / 18));
  const letters = "Glasspad".split("");
  const surfaceColor = m > 0 ? `rgb(${Math.round(lerp(251, 242, m))},${Math.round(lerp(251, 241, m))},${Math.round(lerp(249, 238, m))})` : C.surface;
  return (
    <AbsoluteFill style={{ pointerEvents: "none", background: f < t.morph[0] ? C.paper : "transparent" }}>
      <svg width={W} height={H} style={{ position: "absolute", inset: 0 }}>
        <rect x={tx} y={ty} width={1024 * z} height={1024 * z} rx={228 * z} fill={C.tile} opacity={tileO} />
        <rect x={rect.x} y={rect.y} width={rect.w} height={rect.h} rx={rect.r} fill={surfaceColor} stroke={C.ink} strokeOpacity={0.1 * strokeO} strokeWidth={4 * z} />
        {dots}
      </svg>
      <div style={{ position: "absolute", left: 0, right: 0, top: t.center[1] + 0.5 * 1024 * t.zTo + 54, textAlign: "center", fontFamily: FONT, color: C.ink }}>
        <div style={{ fontSize: W > H ? 132 : 150, fontWeight: 700, letterSpacing: "-0.055em", lineHeight: 0.95, display: "flex", justifyContent: "center", transform: `translateY(${-out * 40}px)`, opacity: 1 - out }}>
          {letters.map((ch, i) => (
            <span key={i} style={{ display: "inline-block", overflow: "hidden", paddingBottom: "0.08em" }}>
              <span style={{ display: "inline-block", transform: `translateY(${(1 - wordIn(i)) * 105}%)` }}>{ch}</span>
            </span>
          ))}
        </div>
        <div style={{ marginTop: 26, fontSize: W > H ? 40 : 46, fontWeight: 500, letterSpacing: "-0.03em", color: C.ink, opacity: clamp(spring(f, t.tag, 160, 1)) * (1 - out), transform: `translateY(${(1 - spring(f, t.tag, 160, 1)) * 24 - out * 40}px)`, padding: "0 60px" }}>
          Your iPhone, as a Mac trackpad.
        </div>
      </div>
    </AbsoluteFill>
  );
};

export const FILM_OPEN: ColdOpenTiming = {
  glides: [
    { down: 30, ms: 38, me: 100, a: [300, 470], b: [700, 590], k: 70, liftAt: 124 },
    { down: 150, ms: 158, me: 232, a: [300, 610], b: [660, 440], k: 0 },
  ],
  pull: [150, 300],
  word: 262,
  tag: 300,
  exit: 432,
  morph: [440, 524],
  zFrom: 2.4,
  zTo: 0.34,
  center: [960, 400],
};
