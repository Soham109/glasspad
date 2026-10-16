// Open Graph image for the website (1200x630; rendered at 2x for sharpness).
// Brand-led: the app icon as a Liquid Glass object (a frosted slab refracting a soft backdrop,
// a thin specular edge, the finger dot gliding on the pad), "Glasspad" and one line.
// Text sits inside the middle 1000 px so center crops keep it.
import React from "react";
import { AbsoluteFill } from "remotion";
import { C, FONT } from "./system";

type Theme = "paper" | "graphite" | "blue";
const T = {
  paper: { bg: C.paper, ink: C.ink, soft: "rgba(26,26,26,0.58)", glass: "rgba(255,255,255,0.38)", edge: "rgba(255,255,255,0.95)", pad: "rgba(255,255,255,0.42)", line: "rgba(26,26,26,0.14)", dot: "#1A1A1A", blobs: ["#0A84FF", "#1A1A1A", "#9DB7D4"], shadow: "rgba(26,26,26,0.16)" },
  graphite: { bg: C.graphite, ink: C.paper, soft: "rgba(242,241,238,0.6)", glass: "rgba(255,255,255,0.07)", edge: "rgba(255,255,255,0.55)", pad: "rgba(255,255,255,0.06)", line: "rgba(255,255,255,0.16)", dot: "#F2F1EE", blobs: ["#0A84FF", "#F2F1EE", "#3A3A3A"], shadow: "rgba(0,0,0,0.5)" },
  blue: { bg: C.graphite, ink: C.paper, soft: "rgba(242,241,238,0.6)", glass: "rgba(255,255,255,0.10)", edge: "rgba(255,255,255,0.6)", pad: "rgba(255,255,255,0.08)", line: "rgba(255,255,255,0.18)", dot: "#FFFFFF", blobs: ["#0A84FF", "#0A84FF", "#F2F1EE"], shadow: "rgba(0,0,0,0.5)" },
};

/** The icon as glass. `s` is the slab size in px. */
const GlassIcon: React.FC<{ s: number; theme: Theme }> = ({ s, theme }) => {
  const t = T[theme];
  const r = s * 0.225;
  const k = s / 1024;
  return (
    <div style={{ position: "relative", width: s, height: s }}>
      {/* contact shadow */}
      <div style={{ position: "absolute", left: s * 0.1, right: s * 0.1, bottom: -s * 0.06, height: s * 0.12, borderRadius: "50%", background: t.shadow, filter: `blur(${s * 0.05}px)` }} />
      {/* the soft backdrop the glass refracts: three blurred shapes, seen only through the slab */}
      <div style={{ position: "absolute", inset: 0, borderRadius: r, overflow: "hidden" }}>
      <div style={{ position: "absolute", left: s * 0.42, top: s * 0.02, width: s * 0.62, height: s * 0.62, borderRadius: "50%", background: t.blobs[0], opacity: theme === "paper" ? 0.55 : 0.75, filter: `blur(${s * 0.04}px)` }} />
      <div style={{ position: "absolute", left: -s * 0.04, top: s * 0.46, width: s * 0.5, height: s * 0.5, borderRadius: "50%", background: t.blobs[1], opacity: theme === "paper" ? 0.5 : 0.35, filter: `blur(${s * 0.04}px)` }} />
      <div style={{ position: "absolute", left: s * 0.12, top: -s * 0.02, width: s * 0.36, height: s * 0.36, borderRadius: "50%", background: t.blobs[2], opacity: 0.55, filter: `blur(${s * 0.04}px)` }} />
      </div>
      {/* the slab */}
      <div style={{ position: "absolute", inset: 0, borderRadius: r, background: t.glass, backdropFilter: `blur(${s * 0.06}px) saturate(150%)`, WebkitBackdropFilter: `blur(${s * 0.06}px) saturate(150%)`, boxShadow: `inset 0 ${s * 0.004}px 0 ${t.edge}, inset 0 0 0 ${Math.max(1, s * 0.004)}px rgba(255,255,255,${theme === "paper" ? 0.6 : 0.18}), inset 0 -${s * 0.02}px ${s * 0.04}px rgba(255,255,255,${theme === "paper" ? 0.25 : 0.05})`, overflow: "hidden" }}>
        {/* specular sheen on the top edge, the only light on the object */}
        <div style={{ position: "absolute", left: "8%", right: "8%", top: 0, height: "38%", borderRadius: `0 0 50% 50%`, background: `linear-gradient(180deg, rgba(255,255,255,${theme === "paper" ? 0.55 : 0.16}) 0%, rgba(255,255,255,0) 100%)` }} />
        {/* the pad, the glide trail, the finger dot */}
        <svg width={s} height={s} viewBox="0 0 1024 1024" style={{ position: "absolute", inset: 0 }}>
          <rect x="102" y="222" width="820" height="580" rx="140" fill={t.pad} stroke="#FFFFFF" strokeOpacity={theme === "paper" ? 0.7 : 0.16} strokeWidth="4" />
          <line x1="300" y1="610" x2="660" y2="440" stroke={t.line} strokeWidth="90" strokeLinecap="round" />
        </svg>
        <div style={{ position: "absolute", left: (660 - 74) * k, top: (440 - 74) * k, width: 148 * k, height: 148 * k, borderRadius: "50%", background: t.dot, boxShadow: `inset 0 ${-10 * k}px ${18 * k}px rgba(0,0,0,${theme === "paper" ? 0.25 : 0.12}), 0 ${8 * k}px ${18 * k}px rgba(0,0,0,0.25)` }} />
      </div>
    </div>
  );
};

const Card: React.FC<{ theme: Theme }> = ({ theme }) => {
  const t = T[theme];
  return (
    <AbsoluteFill style={{ background: t.bg, overflow: "hidden" }}>
      <div style={{ position: "absolute", left: 150, top: 165 }}><GlassIcon s={300} theme={theme} /></div>
      <div style={{ position: "absolute", left: 540, top: 0, bottom: 0, width: 560, display: "flex", flexDirection: "column", justifyContent: "center", fontFamily: FONT }}>
        <div style={{ fontSize: 124, fontWeight: 700, letterSpacing: "-0.055em", lineHeight: 0.95, color: t.ink }}>Glasspad</div>
        <div style={{ marginTop: 26, fontSize: 36, fontWeight: 600, letterSpacing: "-0.025em", color: t.soft, whiteSpace: "nowrap" }}>Your iPhone, as a Mac trackpad.</div>
      </div>
    </AbsoluteFill>
  );
};

export const OGPaper: React.FC = () => <Card theme="paper" />;
export const OGGraphite: React.FC = () => <Card theme="graphite" />;
export const OGBlue: React.FC = () => <Card theme="blue" />;
