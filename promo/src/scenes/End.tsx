import React from "react";
import { AbsoluteFill } from "remotion";
import { C, FONT } from "../theme";
import { bend, clamp, lerp, minJerk, spring, P } from "../motion";

/* End card: a paper dot lands on graphite and opens into the card; the icon's own glide plays once. */
export const END = (at: number) => ({ drop: at, iconTap: at + 44, glideS: at + 52, glideE: at + 118, word: at + 30, free: at + 60, links: at + 84 });
const GH = "M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27.68 0 1.36.09 2 .27 1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.013 8.013 0 0016 8c0-4.42-3.58-8-8-8z";

const Rise: React.FC<{ f: number; at: number; children: React.ReactNode; style?: React.CSSProperties }> = ({ f, at, children, style }) => {
  const p = spring(f, at, 200, 0.86);
  return <div style={{ overflow: "hidden", paddingBottom: "0.1em", ...style }}><div style={{ transform: `translateY(${(1 - p) * 110}%)`, opacity: clamp(p * 3) }}>{children}</div></div>;
};

export const End: React.FC<{ f: number; at: number; W?: number; H?: number }> = ({ f, at, W = 1920, H = 1080 }) => {
  const ev = END(at);
  const v = H > W;
  // the opening dot
  const open = spring(f, ev.drop, 90, 1);
  const R = Math.hypot(W, H) / 2 + 20;
  const dropIn = clamp(spring(f, ev.drop - 10, 420, 0.7));
  const r = lerp(40 * dropIn, R, open);
  // icon
  const size = v ? 340 : 250;
  const iz = size / 1024;
  const icx = W / 2, icy = v ? 620 : 300;
  const iconIn = spring(f, ev.drop + 14, 200, 0.8);
  const a: P = [300, 610], b: P = [660, 440];
  const touch = clamp(spring(f, ev.iconTap, 260, 1));
  const sc = 0.8 + 0.2 * spring(f, ev.iconTap, 420, 0.6);
  const u = minJerk((f - ev.glideS) / (ev.glideE - ev.glideS));
  const head = bend(a, b, 0, u);
  const T = (p: P): P => [icx + (p[0] - 512) * iz, icy + (p[1] - 512) * iz];
  const h = T(head), t0 = T(a);
  const mix = (al: number) => { const c = (s: number) => Math.round(s + (26 - s) * al); return `rgb(${c(251)},${c(251)},${c(249)})`; };
  const k = iconIn;
  return (
    <AbsoluteFill style={{ background: C.graphite, fontFamily: FONT, color: C.ink }}>
      <svg width={W} height={H} style={{ position: "absolute", inset: 0 }}>
        <circle cx={W / 2} cy={H / 2} r={r} fill={C.paper} />
        <g transform={`translate(${icx} ${icy}) scale(${lerp(0.8, 1, k)}) translate(${-icx} ${-icy})`} opacity={clamp(k * 2)}>
          <rect x={icx - size / 2} y={icy - size / 2} width={size} height={size} rx={228 * iz} fill={C.tile} />
          <rect x={T([102, 222])[0]} y={T([102, 222])[1]} width={820 * iz} height={580 * iz} rx={140 * iz} fill={C.surface} stroke={C.ink} strokeOpacity={0.1} strokeWidth={4 * iz} />
          {f >= ev.iconTap && (
            <>
              <line x1={t0[0]} y1={t0[1]} x2={h[0]} y2={h[1]} stroke={C.ink} strokeOpacity={0.1 * touch} strokeWidth={90 * iz} strokeLinecap="round" />
              <circle cx={h[0]} cy={h[1]} r={74 * iz * sc} fill={mix(0.62 * touch)} />
            </>
          )}
        </g>
      </svg>
      <div style={{ position: "absolute", left: 0, right: 0, top: icy + size / 2 + (v ? 70 : 44), textAlign: "center" }}>
        <Rise f={f} at={ev.word} style={{ fontSize: v ? 150 : 112, fontWeight: 700, letterSpacing: "-0.055em", lineHeight: 0.95 }}>Glasspad</Rise>
        <Rise f={f} at={ev.free} style={{ marginTop: v ? 30 : 22, fontSize: v ? 52 : 40, fontWeight: 500, letterSpacing: "-0.03em" }}>Free and open source.</Rise>
        <div style={{ marginTop: v ? 90 : 54, display: "flex", flexDirection: v ? "column" : "row", justifyContent: "center", alignItems: "center", gap: v ? 26 : 56, fontSize: v ? 38 : 30, fontWeight: 500, letterSpacing: "-0.015em" }}>
          <Rise f={f} at={ev.links}><span style={{ display: "inline-flex", alignItems: "center", gap: 14 }}><svg viewBox="0 0 16 16" width={v ? 36 : 28} height={v ? 36 : 28}><path d={GH} fill={C.ink} /></svg>github.com/Soham109/glasspad</span></Rise>
          <Rise f={f} at={ev.links + 6}><span style={{ color: C.ink2 }}>glasspad.sohamaggarwal.com</span></Rise>
        </div>
      </div>
    </AbsoluteFill>
  );
};
