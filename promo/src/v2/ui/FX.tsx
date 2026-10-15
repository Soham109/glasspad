// Shared motion graphics: the tap ripple, the dot wipe (the film's signature transition),
// the display-frame ticks, and flat grounding shadows.
import React from "react";
import { useCurrentFrame } from "remotion";
import { C, E, clamp01, lerp, prog, spr } from "../system";

/** A tap: a dot that squashes, and one ring that leaves it. */
export const Ripple: React.FC<{ x: number; y: number; at: number; size?: number; color?: string; dot?: boolean }> = ({ x, y, at, size = 60, color = C.ink, dot = true }) => {
  const f = useCurrentFrame();
  if (f < at - 2 || f > at + 40) return null;
  const ring = prog(f, at, 30, E.out);
  const d = spr(f, at - 2, "pop");
  const dotOut = prog(f, at + 10, 14, E.in);
  return (
    <>
      {dot ? <div style={{ position: "absolute", left: x - (size * 0.5 * d) / 2, top: y - (size * 0.5 * d) / 2, width: size * 0.5 * d, height: size * 0.5 * d, borderRadius: size, background: color, opacity: 1 - dotOut }} /> : null}
      <div style={{ position: "absolute", left: x - (size * lerp(0.4, 1.6, ring)) / 2, top: y - (size * lerp(0.4, 1.6, ring)) / 2, width: size * lerp(0.4, 1.6, ring), height: size * lerp(0.4, 1.6, ring), borderRadius: size * 2, boxShadow: `inset 0 0 0 ${lerp(4, 1, ring)}px ${color}`, opacity: 1 - ring }} />
    </>
  );
};

/** Signature transition: a disc of `color` grows from (x, y) until it covers the frame. */
export const DotWipe: React.FC<{ x: number; y: number; at: number; dur?: number; color: string; w?: number; h?: number; reverse?: boolean; children?: React.ReactNode }> = ({ x, y, at, dur = 36, color, w = 1920, h = 1080, reverse = false, children }) => {
  const f = useCurrentFrame();
  const t = reverse ? 1 - prog(f, at, dur, E.inOut) : prog(f, at, dur, E.inOut);
  if (t <= 0) return null;
  const maxR = Math.hypot(Math.max(x, w - x), Math.max(y, h - y));
  const r = lerp(0, maxR, t);
  return (
    <div style={{ position: "absolute", inset: 0, clipPath: `circle(${r}px at ${x}px ${y}px)`, background: color }}>
      {children}
    </div>
  );
};

/** Display frames as ticks: one per refresh, lit as the pointer lands on them. */
export const Ticks: React.FC<{ x: number; y: number; w: number; n: number; at: number; every: number; color?: string; dim?: string }> = ({ x, y, w, n, at, every, color = C.accent, dim = C.ink12 }) => {
  const f = useCurrentFrame();
  return (
    <div style={{ position: "absolute", left: x, top: y, width: w, height: 40 }}>
      {Array.from({ length: n }).map((_, i) => {
        const lit = f >= at + i * every;
        const pop = lit ? clamp01((f - (at + i * every)) / 6) : 0;
        return <div key={i} style={{ position: "absolute", left: (i / (n - 1)) * w - 2.5, top: lerp(22, 0, pop), width: 5, height: lerp(10, 36, pop), borderRadius: 5, background: lit ? color : dim }} />;
      })}
    </div>
  );
};

/** A flat contact shadow: one solid ellipse, no blur. */
export const Floor: React.FC<{ x: number; y: number; w: number; h: number; opacity?: number }> = ({ x, y, w, h, opacity = 0.08 }) => (
  <div style={{ position: "absolute", left: x - w / 2, top: y - h / 2, width: w, height: h, borderRadius: "50%", background: C.ink, opacity }} />
);
