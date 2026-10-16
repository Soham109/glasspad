// Film finishing and the shared motion pieces: grain, vignette, the dot (a touch on glass),
// the feature label, light sweeps.
import React from "react";
import { AbsoluteFill, random, useCurrentFrame } from "remotion";
import { E, SFT, clamp01, lerp, prog, spr } from "./core";

/** Fine, moving film grain (a new seed every frame), over everything. */
export const Grain: React.FC<{ amount?: number }> = ({ amount = 0.06 }) => {
  const f = useCurrentFrame();
  const seed = Math.floor(random(`g${f}`) * 1000);
  return (
    <AbsoluteFill style={{ pointerEvents: "none", mixBlendMode: "overlay", opacity: amount }}>
      <svg width="100%" height="100%" preserveAspectRatio="none" viewBox="0 0 960 540">
        <filter id={`grain${f}`}>
          <feTurbulence type="fractalNoise" baseFrequency="0.9" numOctaves={2} seed={seed} stitchTiles="stitch" />
          <feColorMatrix type="saturate" values="0" />
        </filter>
        <rect width="960" height="540" filter={`url(#grain${f})`} />
      </svg>
    </AbsoluteFill>
  );
};

export const Vignette: React.FC<{ amount?: number }> = ({ amount = 0.45 }) => (
  <AbsoluteFill style={{ pointerEvents: "none", background: `radial-gradient(120% 95% at 50% 48%, rgba(0,0,0,0) 55%, rgba(0,0,0,${amount}) 100%)` }} />
);

/**
 * A fingertip on glass: the film's dot. Lands with a squash, rings once on a tap, and leaves a
 * short trail when it slides. Coordinates are in the parent's pixels.
 */
export const Touch: React.FC<{
  path: (f: number) => { x: number; y: number } | null;
  down: number; // frame the finger lands
  up: number; // frame it lifts
  size?: number;
  color?: string;
  ring?: boolean;
}> = ({ path, down, up, size = 120, color = "rgba(255,255,255,0.92)", ring = true }) => {
  const f = useCurrentFrame();
  if (f < down - 2 || f > up + 40) return null;
  const p = path(Math.min(f, up));
  if (!p) return null;
  const inT = spr(f, down - 2, "pop");
  const outT = prog(f, up, 14, E.in);
  const d = size * lerp(0.5, 1, inT) * lerp(1, 0.6, outT);
  const ringT = prog(f, down, 30, E.out);
  const trail: string[] = [];
  for (let j = 0; j <= 14; j++) {
    const q = path(Math.min(f, up) - j);
    if (!q || f - j < down) break;
    trail.push(`${trail.length ? "L" : "M"}${q.x.toFixed(1)} ${q.y.toFixed(1)}`);
  }
  return (
    <div style={{ position: "absolute", inset: 0, pointerEvents: "none" }}>
      {trail.length > 2 ? (
        <svg style={{ position: "absolute", left: 0, top: 0, overflow: "visible" }} width={1} height={1}>
          <path d={trail.join(" ")} fill="none" stroke={color} strokeOpacity={0.22 * (1 - outT)} strokeWidth={d * 0.7} strokeLinecap="round" strokeLinejoin="round" />
        </svg>
      ) : null}
      <div style={{ position: "absolute", left: p.x - d / 2, top: p.y - d / 2, width: d, height: d, borderRadius: d, background: `radial-gradient(circle, ${color} 0%, ${color} 48%, rgba(255,255,255,0) 72%)`, opacity: (1 - outT) * 0.9, boxShadow: "0 0 30px rgba(255,255,255,0.25)" }} />
      {ring ? <div style={{ position: "absolute", left: p.x - (size * lerp(0.6, 1.9, ringT)) / 2, top: p.y - (size * lerp(0.6, 1.9, ringT)) / 2, width: size * lerp(0.6, 1.9, ringT), height: size * lerp(0.6, 1.9, ringT), borderRadius: size * 2, boxShadow: `inset 0 0 0 ${lerp(5, 1.5, ringT)}px ${color}`, opacity: (1 - ringT) * 0.8 }} /> : null}
    </div>
  );
};

/** A tap at one point: Touch with a fixed path. */
export const Tap: React.FC<{ x: number; y: number; at: number; hold?: number; size?: number; color?: string }> = ({ x, y, at, hold = 8, size, color }) => (
  <Touch path={() => ({ x, y })} down={at} up={at + hold} size={size} color={color} />
);

/** The feature's name, small, bottom left, for the length of its scene. */
export const Label: React.FC<{ text: string; inAt: number; outAt: number; dark?: boolean }> = ({ text, inAt, outAt, dark = true }) => {
  const f = useCurrentFrame();
  const a = spr(f, inAt, "settle");
  const b = prog(f, outAt - 14, 14, E.in);
  if (f < inAt - 1 || f > outAt) return null;
  const fg = dark ? "#F5F5F7" : "#1D1D1F";
  return (
    <div style={{ position: "absolute", left: 96, bottom: 84, display: "flex", alignItems: "center", gap: 14, fontFamily: SFT, fontSize: 27, fontWeight: 600, letterSpacing: "-0.005em", color: fg, opacity: clamp01(a * 1.4) * (1 - b), transform: `translateY(${lerp(14, 0, a) - 8 * b}px)`, textShadow: dark ? "0 1px 18px rgba(0,0,0,0.35)" : "none" }}>
      <div style={{ width: 11, height: 11, borderRadius: 11, background: fg, transform: `scale(${a})` }} />
      {text}
    </div>
  );
};

/** A soft band of light that crosses a box once (for glass and metal). */
export const Sweep: React.FC<{ at: number; dur?: number; w: number; h: number; strength?: number; angle?: number }> = ({ at, dur = 50, w, h, strength = 0.14, angle = 22 }) => {
  const f = useCurrentFrame();
  const t = (f - at) / dur;
  if (t < 0 || t > 1) return null;
  const e = E.inOut(t);
  return (
    <div style={{ position: "absolute", inset: 0, overflow: "hidden", pointerEvents: "none" }}>
      <div style={{ position: "absolute", top: -h, height: h * 3, width: w * 0.3, left: lerp(-w * 0.5, w * 1.2, e), transform: `rotate(${angle}deg)`, background: `linear-gradient(90deg, rgba(255,255,255,0), rgba(255,255,255,${strength}), rgba(255,255,255,0))` }} />
    </div>
  );
};
