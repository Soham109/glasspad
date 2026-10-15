import React from "react";
import { C, MODE_ACCENT, FONT } from "../theme";
import { Icon, GL } from "./apps";
import { clamp, lerp, easeOut } from "../motion";

export type Finger = { x: number; y: number; o: number; s: number };
export type Ripple = { x: number; y: number; age: number; strong?: boolean };

/** A soft ring that leaves the finger: the visible stand-in for the haptic tap. */
export const Rings: React.FC<{ r: Ripple; dark?: boolean }> = ({ r, dark }) => {
  const rings = r.strong ? [0, 7, 14] : [0];
  const ink = dark ? "242,241,238" : "26,26,26";
  return (
    <>
      {rings.map((d) => {
        const t = (r.age - d) / 38;
        if (t < 0 || t > 1) return null;
        const e = easeOut(t);
        const rad = lerp(24, r.strong ? 92 : 64, e);
        return (
          <div key={d} style={{ position: "absolute", left: r.x - rad, top: r.y - rad, width: rad * 2, height: rad * 2, borderRadius: "50%", boxShadow: `inset 0 0 0 ${lerp(3, 1.2, e)}px rgba(${ink},${0.5 * (1 - t)})` }} />
        );
      })}
    </>
  );
};

export const Dots: React.FC<{ fingers: Finger[]; dark?: boolean; size?: number }> = ({ fingers, dark, size = 44 }) => (
  <>
    {fingers.map((f, i) =>
      f.o <= 0.001 ? null : (
        <div key={i} style={{ position: "absolute", left: f.x - size / 2, top: f.y - size / 2, width: size, height: size, borderRadius: "50%", background: dark ? "rgba(255,255,255,0.22)" : "rgba(26,26,26,0.2)", opacity: f.o, transform: `scale(${f.s})` }} />
      )
    )}
  </>
);

export const StatusDot: React.FC<{ top?: number; left?: string | number }> = ({ top = 62, left = "50%" }) => (
  <span style={{ position: "absolute", left, top, width: 7, height: 7, marginLeft: -3.5, borderRadius: 4, background: C.green }} />
);

const MODES = ["trackpad", "dock", "keys", "media", "deck", "macros", "clipboard", "present"] as const;
const TITLES: Record<string, string> = { trackpad: "Trackpad", dock: "Dock", keys: "Keys", media: "Media", deck: "Deck", macros: "Macros", clipboard: "Clipboard", present: "Present" };

/** The mode pill (top centre) and the mode menu card, as in docs/img/modes.png. Landscape screen, 874 x 402 points. */
export const ModePill: React.FC<{ o: number; mode?: string; cx?: number; top?: number }> = ({ o, mode = "trackpad", cx = 437, top = 14 }) => (
  <div style={{ position: "absolute", left: cx, top, transform: `translateX(-50%) scale(${lerp(0.92, 1, o)})`, opacity: o, height: 38, padding: "0 16px 0 14px", borderRadius: 19, background: C.raised, boxShadow: "0 0 0 1px rgba(26,26,26,0.08)", display: "flex", alignItems: "center", gap: 8, fontFamily: FONT, fontSize: 15, fontWeight: 600, color: C.ink, whiteSpace: "nowrap", zIndex: 20 }}>
    <Icon d={GL[mode as keyof typeof GL]} size={18} color={MODE_ACCENT[mode]} sw={1.8} />
    {TITLES[mode]}
    <i style={{ width: 7, height: 7, borderRadius: 4, background: C.green, marginLeft: 2 }} />
  </div>
);

export const ModeMenu: React.FC<{ open: number; pressed?: string; selected?: string; cx?: number; top?: number }> = ({ open, pressed, selected = "trackpad", cx = 437, top = 62 }) => {
  if (open <= 0.001) return null;
  return (
    <div style={{ position: "absolute", left: cx, top, width: 316, transformOrigin: "50% -30px", transform: `translateX(-50%) scale(${lerp(0.7, 1, open)})`, opacity: clamp(open * 1.6), borderRadius: 26, background: C.raised, boxShadow: "0 0 0 1px rgba(26,26,26,0.07)", padding: "12px 12px 6px", fontFamily: FONT, zIndex: 19 }}>
      <div style={{ display: "grid", gridTemplateColumns: "repeat(4, 1fr)", gap: 4 }}>
        {MODES.map((m) => (
          <div key={m} style={{ height: 62, borderRadius: 14, display: "flex", flexDirection: "column", alignItems: "center", justifyContent: "center", gap: 6, fontSize: 11, fontWeight: 500, color: C.ink, background: m === pressed ? "rgba(26,26,26,0.10)" : m === selected ? (m === "trackpad" ? "rgba(26,26,26,0.07)" : MODE_ACCENT[m] + "24") : "transparent", transform: m === pressed ? "scale(0.94)" : undefined }}>
            <Icon d={GL[m]} size={22} color={MODE_ACCENT[m]} sw={1.6} />
            {TITLES[m]}
          </div>
        ))}
      </div>
      <div style={{ display: "flex", justifyContent: "space-between", padding: "12px 12px 8px", fontSize: 13, fontWeight: 500, color: C.ink }}>
        <span style={{ display: "flex", gap: 8, alignItems: "center" }}><Icon d={GL.rotate} size={16} color={C.ink} sw={1.7} />Lock Rotation</span>
        <span style={{ display: "flex", gap: 8, alignItems: "center" }}><Icon d={GL.gear} size={16} color={C.ink} sw={1.7} />Settings</span>
      </div>
    </div>
  );
};

/** The trackpad itself: a plain surface with a dot under each finger. */
export const TrackpadScreen: React.FC<{ fingers: Finger[]; ripples: Ripple[]; dark?: boolean; pill?: number; menu?: number; pressed?: string; children?: React.ReactNode }> = ({ fingers, ripples, dark, pill = 0, menu = 0, pressed, children }) => (
  <div style={{ position: "absolute", inset: 0, background: dark ? C.graphite : C.paper }}>
    {children}
    {ripples.map((r, i) => <Rings key={i} r={r} dark={dark} />)}
    <ModePill o={pill} />
    <ModeMenu open={menu} pressed={pressed} />
    <Dots fingers={fingers} dark={dark} />
  </div>
);
