import React from "react";
import { AbsoluteFill } from "remotion";
import { C, FONT } from "../theme";
import { Caption } from "../Captions";
import { clamp, prog, easeOut } from "../motion";

/* Measured fact only: touch updates arrive several hundred times a second. No latency number is stated.
   The strip draws one tick per update across one second. */
export const SPEED_TICKS = 300;
export const Speed: React.FC<{ f: number; at: number; end: number; W?: number; H?: number }> = ({ f, at, end, W = 1920, H = 1080 }) => {
  const k = f - at;
  const x0 = 160, x1 = W - 160, y = 600;
  const fill = prog(k, 26, 96, (t) => t); // one second of updates, drawn in 1.6 s
  const shown = Math.floor(fill * SPEED_TICKS);
  const out = clamp((f - (end - 22)) / 18);
  const ticks: React.ReactNode[] = [];
  for (let i = 0; i < shown; i++) {
    const x = x0 + ((x1 - x0) * (i + 0.5)) / SPEED_TICKS;
    const age = fill * SPEED_TICKS - i;
    const h = (i % 10 === 0 ? 72 : 52) * easeOut(clamp(age / 8));
    ticks.push(<rect key={i} x={x - 0.6} y={y - h / 2} width={1.2} height={h} rx={0.6} fill={C.ink} opacity={0.8} />);
  }
  const second = prog(k, 120, 30);
  return (
    <AbsoluteFill style={{ background: C.paper, fontFamily: FONT, opacity: 1 - out }}>
      <Caption frame={f} c={{ at: at + 10, out: end - 24, title: "Several hundred touch updates every second.", x: x0, y: 250, size: 84, maxW: 1400 }} />
      <svg width={W} height={H} style={{ position: "absolute", inset: 0 }}>
        <line x1={x0} x2={x1} y1={y + 52} y2={y + 52} stroke={C.ink} strokeOpacity={0.14 * prog(k, 20, 20)} strokeWidth={2} />
        {ticks}
      </svg>
      <div style={{ position: "absolute", left: x0, top: y + 70, fontSize: 22, fontWeight: 500, color: C.ink3, opacity: prog(k, 30, 20) }}>0 s</div>
      <div style={{ position: "absolute", right: 160, top: y + 70, fontSize: 22, fontWeight: 500, color: C.ink3, opacity: second }}>1 s</div>
      <Caption frame={f} c={{ at: at + 118, out: end - 24, title: "Straight from the glass to your Mac.", sub: "Over your own Wi-Fi, with no server in between.", x: x0, y: 770, size: 56, maxW: 1400 }} />
    </AbsoluteFill>
  );
};
