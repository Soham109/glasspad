import React from "react";
import { DISP_W, DISP_H } from "../devices/Mac";
import { AppTile } from "./apps";
import { lerp, clamp } from "../motion";

/* Mac screen contents in display points (1512 x 982). Flat: hairline edges instead of shadows. */
export type Rect = { x: number; y: number; w: number; h: number };
const pct = (l: number, t: number, w: number, h: number): Rect => ({ x: (l * DISP_W) / 100, y: (t * DISP_H) / 100, w: (w * DISP_W) / 100, h: (h * DISP_H) / 100 });
export const WIN = {
  a: pct(9, 12, 52, 62),
  b: pct(40, 21, 46, 56),
  c: pct(24, 14, 54, 62),
  d: pct(7, 30, 34, 46),
};
export const WALL1 = "#CFCBC3", WALL2 = "#B9C2C4";
const TB = 44; // title bar height in points

export const TrafficLights: React.FC<{ active: boolean; dark?: boolean }> = ({ active, dark }) => (
  <div style={{ display: "flex", gap: 9, alignItems: "center" }}>
    {["#EE6A5F", "#F5BD4F", "#61C454"].map((c, i) => (
      <i key={i} style={{ width: 14, height: 14, borderRadius: 7, background: active ? c : dark ? "rgba(255,255,255,0.2)" : "rgba(26,26,26,0.16)" }} />
    ))}
  </div>
);

export const Win: React.FC<{ r: Rect; active?: boolean; children?: React.ReactNode; bar?: string; bg?: string; z?: number; style?: React.CSSProperties; dark?: boolean; titleBar?: React.ReactNode }> = ({ r, active = true, children, bar, bg = "#FBFBF9", z, style, dark, titleBar }) => (
  <div style={{ position: "absolute", left: r.x, top: r.y, width: r.w, height: r.h, borderRadius: 18, background: bg, overflow: "hidden", boxShadow: `0 0 0 1px ${dark ? "rgba(255,255,255,0.08)" : "rgba(26,26,26,0.12)"}`, zIndex: z, ...style }}>
    <div style={{ height: TB, display: "flex", alignItems: "center", padding: "0 18px", gap: 18, background: bar, borderBottom: `1px solid ${dark ? "rgba(255,255,255,0.08)" : "rgba(26,26,26,0.08)"}` }}>
      <TrafficLights active={active} dark={dark} />
      {titleBar}
    </div>
    <div style={{ position: "absolute", left: 0, right: 0, top: TB, bottom: 0, overflow: "hidden" }}>{children}</div>
  </div>
);

const bar = (w: string | number, h = 14, c = "rgba(26,26,26,0.12)", mb = 22): React.CSSProperties => ({ display: "block", width: w, height: h, borderRadius: 8, background: c, marginBottom: mb });

/** Abstract document: headings, lines and two flat picture blocks (web/src redo.css .md-doc). */
export const DocLines: React.FC<{ offset?: number; long?: boolean }> = ({ offset = 0, long }) => {
  const block = (k: number) => (
    <React.Fragment key={k}>
      <i style={{ ...bar("46%", 26, "rgba(26,26,26,0.32)", 34), marginTop: 10 }} />
      <i style={bar("100%")} />
      <i style={bar("88%")} />
      <i style={bar("94%")} />
      <i style={{ ...bar("100%", 128, k % 2 ? "#E4D9CC" : "#D9DCD6", 30), borderRadius: 14, marginTop: 30 }} />
      <i style={bar("100%")} />
      <i style={bar("76%")} />
      <i style={bar("90%")} />
      <i style={bar("82%")} />
    </React.Fragment>
  );
  return <div style={{ padding: "30px 44px", transform: `translateY(${-offset}px)` }}>{[0, 1, 2, 3, ...(long ? [4, 5, 6] : [])].map(block)}</div>;
};

export const MenuBar: React.FC<{ extra?: React.ReactNode; dark?: boolean }> = ({ extra, dark }) => {
  const c = dark ? "rgba(242,241,238,0.6)" : "rgba(26,26,26,0.45)";
  return (
    <div style={{ position: "absolute", left: 0, right: 0, top: 0, height: 38, background: dark ? "rgba(20,20,20,0.5)" : "rgba(250,249,247,0.55)", display: "flex", alignItems: "center", gap: 30, padding: "0 28px", zIndex: 40 }}>
      <i style={{ width: 16, height: 16, borderRadius: 5, background: c }} />
      <i style={{ width: 62, height: 12, borderRadius: 6, background: c }} />
      <i style={{ width: 40, height: 12, borderRadius: 6, background: c }} />
      <i style={{ width: 44, height: 12, borderRadius: 6, background: c }} />
      <i style={{ width: 50, height: 12, borderRadius: 6, background: c }} />
      <div style={{ marginLeft: "auto", display: "flex", alignItems: "center", gap: 22 }}>
        {extra}
        <i style={{ width: 22, height: 12, borderRadius: 6, background: c }} />
        <i style={{ width: 90, height: 12, borderRadius: 6, background: dark ? "rgba(242,241,238,0.4)" : "rgba(26,26,26,0.3)" }} />
      </div>
    </div>
  );
};

export const DOCK_ORDER = ["finder", "web", "mail", "notes", "music", "photos", "term"];
export const MacDock: React.FC<{ running?: Record<string, boolean>; bounce?: Record<string, number> }> = ({ running = { finder: true, web: true }, bounce = {} }) => (
  <div style={{ position: "absolute", left: "50%", bottom: 14, transform: "translateX(-50%)", display: "flex", gap: 12, padding: "10px 12px 6px", borderRadius: 26, background: "rgba(250,249,247,0.55)", boxShadow: "0 0 0 1px rgba(255,255,255,0.5)", zIndex: 40 }}>
    {DOCK_ORDER.map((k) => (
      <div key={k} style={{ display: "flex", flexDirection: "column", alignItems: "center" }}>
        <AppTile k={k} size={64} style={{ transform: `translateY(${-(bounce[k] ?? 0)}px)` }} />
        <i style={{ width: 6, height: 6, borderRadius: 3, marginTop: 5, background: "rgba(26,26,26,0.55)", opacity: running[k] ? 1 : 0 }} />
      </div>
    ))}
  </div>
);

export const Cursor: React.FC<{ x: number; y: number; press?: number; opacity?: number; size?: number }> = ({ x, y, press = 0, opacity = 1, size = 30 }) => (
  <svg viewBox="0 0 16 22" width={(size * 16) / 22} height={size} style={{ position: "absolute", left: 0, top: 0, transformOrigin: "0 0", transform: `translate(${x}px, ${y}px) scale(${1 - 0.15 * press})`, zIndex: 60, opacity, overflow: "visible" }}>
    <path d="M1 1v17l4.6-4.4 3 6.9 3-1.3-3-6.8H15Z" fill="#1A1A1A" stroke="#fff" strokeWidth={1.4} strokeLinejoin="round" />
  </svg>
);

/** transform that carries window rect a toward rect b (uniform scale by width), for Mission Control */
const toward = (a: Rect, b: Rect, t: number): React.CSSProperties => {
  const k = lerp(1, b.w / a.w, t);
  return { transformOrigin: "0 0", transform: `translate(${lerp(0, b.x - a.x, t)}px, ${lerp(0, b.y - a.y, t)}px) scale(${k})` };
};

export type DesktopState = {
  cursor: { x: number; y: number; press: number; o: number };
  front: "a" | "b";
  scroll: number; // points the front doc has scrolled
  space: number; // 0 = desktop 1, 1 = desktop 2
  mission: number; // 0..1
};

/** The setup scene's Mac screen: two desktops side by side, windows, Mission Control, menu bar, Dock, pointer. */
export const Desktop: React.FC<{ s: DesktopState }> = ({ s }) => {
  const m = clamp(s.mission);
  // Mission Control targets for the windows on desktop 2 (the swipe lands there first)
  const mcC: Rect = { x: 760, y: 300, w: 560, h: 400 }, mcD: Rect = { x: 180, y: 330, w: 470, h: 330 };
  const shift = -s.space * DISP_W;
  const thumb = (i: number, on: boolean) => (
    <div key={i} style={{ width: 168, height: 106, borderRadius: 12, background: i === 0 ? WALL1 : WALL2, boxShadow: on ? "0 0 0 3px rgba(250,249,247,0.95)" : "0 0 0 1px rgba(250,249,247,0.5)", position: "relative", overflow: "hidden" }}>
      <i style={{ position: "absolute", left: "22%", top: "18%", width: "52%", height: "58%", borderRadius: 5, background: "#FBFBF9" }} />
    </div>
  );
  return (
    <div style={{ position: "absolute", inset: 0, overflow: "hidden" }}>
      <div style={{ position: "absolute", left: 0, top: 0, width: DISP_W * 2, height: DISP_H, transform: `translateX(${shift}px)` }}>
        <div style={{ position: "absolute", left: 0, top: 0, width: DISP_W, height: DISP_H, background: WALL1 }}>
          <Win r={WIN.b} active={s.front === "b"} z={s.front === "b" ? 3 : 1}><DocLines offset={s.front === "b" ? s.scroll : 0} long /></Win>
          <Win r={WIN.a} active={s.front === "a"} z={2}><DocLines /></Win>
        </div>
        <div style={{ position: "absolute", left: DISP_W, top: 0, width: DISP_W, height: DISP_H, background: WALL2 }}>
          <div style={{ position: "absolute", inset: 0, background: `rgba(20,20,20,${0.16 * m})` }} />
          <Win r={WIN.d} active={false} z={1} style={toward(WIN.d, mcD, m)}><DocLines /></Win>
          <Win r={WIN.c} active={m < 0.5} z={2} style={toward(WIN.c, mcC, m)}><DocLines /></Win>
          <div style={{ position: "absolute", left: 0, right: 0, top: lerp(-150, 52, m), display: "flex", justifyContent: "center", gap: 22, opacity: clamp(m * 1.6) }}>
            {thumb(0, false)}
            {thumb(1, true)}
          </div>
        </div>
      </div>
      <div style={{ opacity: 1 - clamp(m * 1.4) }}>
        <MenuBar />
        <MacDock />
      </div>
      <Cursor x={s.cursor.x} y={s.cursor.y} press={s.cursor.press} opacity={s.cursor.o * (1 - clamp(m * 2))} />
    </div>
  );
};
