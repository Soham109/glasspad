// macOS, drawn true to life at screen points: wallpaper, the menu bar (transparent, as in
// macOS 26), the Dock (glass), windows with traffic lights, a notification banner.
// The wallpaper is the film's own (layered light, no Apple artwork).
import React from "react";
import { Img } from "remotion";
import { SFT, icon, sym } from "../core";

export const WALLS = {
  dawn: "radial-gradient(120% 90% at 78% 110%, #FF9F6B 0%, rgba(255,159,107,0) 55%), radial-gradient(90% 70% at 15% 105%, #E96B8A 0%, rgba(233,107,138,0) 60%), radial-gradient(110% 80% at 50% -10%, #1B2A5A 0%, rgba(27,42,90,0) 70%), linear-gradient(180deg, #24326A 0%, #6B5B9A 55%, #F2A07B 100%)",
  dusk: "radial-gradient(100% 80% at 70% 100%, #3A6BD8 0%, rgba(58,107,216,0) 60%), radial-gradient(80% 60% at 20% 0%, #0B1230 0%, rgba(11,18,48,0) 70%), linear-gradient(180deg, #0D1328 0%, #1C2D6B 60%, #3C66C9 100%)",
  graphite: "radial-gradient(90% 70% at 30% 110%, #4A4D57 0%, rgba(74,77,87,0) 60%), linear-gradient(180deg, #1A1B1F 0%, #2C2E35 100%)",
};

export const Wallpaper: React.FC<{ kind?: keyof typeof WALLS; w: number; h: number }> = ({ kind = "dawn", w, h }) => (
  <div style={{ position: "absolute", left: 0, top: 0, width: w, height: h, background: WALLS[kind] }} />
);

/** An SF Symbol (white template PNG) tinted to `color`. */
export const Sym: React.FC<{ name: string; size: number; color?: string; style?: React.CSSProperties }> = ({ name, size, color = "#fff", style }) => (
  <div style={{ width: size, height: size, backgroundColor: color, WebkitMaskImage: `url(${sym(name)})`, WebkitMaskSize: "contain", WebkitMaskRepeat: "no-repeat", WebkitMaskPosition: "center", ...style }} />
);

export const MENU_H = 30;

export const MenuBar: React.FC<{ w: number; app: string; menus?: string[]; focus?: boolean; dark?: boolean; time?: string }> = ({ w, app, menus = ["File", "Edit", "View", "Window", "Help"], focus = false, dark = true, time = "Thu 16 Oct  9:41" }) => {
  const fg = dark ? "rgba(255,255,255,0.96)" : "rgba(0,0,0,0.88)";
  const shadow = dark ? "0 0 6px rgba(0,0,0,0.25)" : "none";
  return (
    <div style={{ position: "absolute", left: 0, top: 0, width: w, height: MENU_H, display: "flex", alignItems: "center", padding: "0 14px 0 18px", gap: 20, fontFamily: SFT, fontSize: 13.5, color: fg, textShadow: shadow, letterSpacing: "-0.01em" }}>
      <Sym name="apple.logo" size={15} color={fg} style={{ marginTop: -2 }} />
      <span style={{ fontWeight: 700 }}>{app}</span>
      {menus.map((m) => <span key={m} style={{ fontWeight: 500 }}>{m}</span>)}
      <span style={{ flex: 1 }} />
      {focus ? <Sym name="moon.fill" size={14} color={fg} /> : null}
      <Sym name="battery.100percent" size={24} color={fg} />
      <Sym name="wifi" size={16} color={fg} />
      <Sym name="magnifyingglass" size={14} color={fg} />
      <Sym name="switch.2" size={15} color={fg} />
      <span style={{ fontWeight: 500, whiteSpace: "pre" }}>{time}</span>
    </div>
  );
};

export const DOCK_APPS = ["com.apple.finder", "com.apple.Safari", "com.apple.mail", "com.apple.MobileSMS", "com.apple.iCal", "com.apple.Notes", "com.apple.Music", "com.apple.Photos", "com.apple.keynote", "com.apple.freeform", "com.apple.systempreferences"];

export const Dock: React.FC<{ w: number; h: number; apps?: string[]; running?: string[]; size?: number; bounce?: Record<string, number> }> = ({ w, h, apps = DOCK_APPS, running = [], size = 54, bounce = {} }) => {
  const gap = 6, pad = 8;
  const dw = apps.length * size + (apps.length - 1) * gap + pad * 2;
  return (
    <div style={{ position: "absolute", left: (w - dw) / 2, top: h - size - pad * 2 - 6, width: dw, height: size + pad * 2, borderRadius: 24, background: "rgba(255,255,255,0.16)", boxShadow: "inset 0 0 0 0.75px rgba(255,255,255,0.35), inset 0 1px 0 rgba(255,255,255,0.35), 0 10px 30px rgba(0,0,0,0.18)", backdropFilter: "blur(20px)" }}>
      {apps.map((id, i) => (
        <div key={id} style={{ position: "absolute", left: pad + i * (size + gap), top: pad - (bounce[id] ?? 0), width: size, height: size }}>
          <Img src={icon(id)} style={{ width: size, height: size }} />
          {running.includes(id) ? <div style={{ position: "absolute", left: size / 2 - 2, top: size + 3 + (bounce[id] ?? 0), width: 4, height: 4, borderRadius: 4, background: "rgba(255,255,255,0.85)" }} /> : null}
        </div>
      ))}
    </div>
  );
};

export const Traffic: React.FC<{ active?: boolean }> = ({ active = true }) => (
  <div style={{ display: "flex", gap: 8 }}>
    {["#FF5F57", "#FEBC2E", "#28C840"].map((c) => (
      <div key={c} style={{ width: 12, height: 12, borderRadius: 12, background: active ? c : "rgba(255,255,255,0.18)", boxShadow: active ? "inset 0 0 0 0.5px rgba(0,0,0,0.18)" : "none" }} />
    ))}
  </div>
);

/** A window: frame, shadow, traffic lights; `toolbar` sits in the title bar. */
export const Window: React.FC<{ x: number; y: number; w: number; h: number; dark?: boolean; active?: boolean; title?: string; toolbar?: React.ReactNode; bar?: number; children?: React.ReactNode; style?: React.CSSProperties }> = ({ x, y, w, h, dark = false, active = true, title, toolbar, bar = 52, children, style }) => (
  <div style={{ position: "absolute", left: x, top: y, width: w, height: h, borderRadius: 16, overflow: "hidden", background: dark ? "#1E1E20" : "#FFFFFF", boxShadow: active ? "0 0 0 0.5px rgba(0,0,0,0.35), 0 22px 60px rgba(0,0,0,0.38), 0 6px 16px rgba(0,0,0,0.2)" : "0 0 0 0.5px rgba(0,0,0,0.3), 0 10px 30px rgba(0,0,0,0.25)", fontFamily: SFT, ...style }}>
    <div style={{ position: "absolute", left: 0, top: 0, right: 0, height: bar, display: "flex", alignItems: "center", padding: "0 18px", gap: 16, background: dark ? "#2A2A2D" : "#F6F6F6", borderBottom: `1px solid ${dark ? "rgba(255,255,255,0.08)" : "rgba(0,0,0,0.08)"}` }}>
      <Traffic active={active} />
      {toolbar}
      {title ? <div style={{ position: "absolute", left: 0, right: 0, textAlign: "center", fontSize: 13.5, fontWeight: 600, color: dark ? "rgba(255,255,255,0.85)" : "rgba(0,0,0,0.8)", pointerEvents: "none" }}>{title}</div> : null}
    </div>
    <div style={{ position: "absolute", left: 0, top: bar, right: 0, bottom: 0 }}>{children}</div>
    {!active ? <div style={{ position: "absolute", inset: 0, background: dark ? "rgba(0,0,0,0.06)" : "rgba(255,255,255,0.04)" }} /> : null}
  </div>
);

/** A notification banner, top right, as macOS shows one. */
export const Banner: React.FC<{ x: number; y: number; iconId: string; title: string; body: string; time?: string; style?: React.CSSProperties }> = ({ x, y, iconId, title, body, time = "now", style }) => (
  <div style={{ position: "absolute", left: x, top: y, width: 344, borderRadius: 18, padding: "12px 14px", display: "flex", gap: 11, background: "rgba(246,246,248,0.86)", backdropFilter: "blur(24px)", boxShadow: "0 0 0 0.5px rgba(0,0,0,0.12), 0 12px 32px rgba(0,0,0,0.22)", fontFamily: SFT, color: "#1D1D1F", ...style }}>
    <Img src={icon(iconId)} style={{ width: 36, height: 36, flex: "none" }} />
    <div style={{ flex: 1, minWidth: 0 }}>
      <div style={{ display: "flex", fontSize: 13, fontWeight: 600 }}><span style={{ flex: 1 }}>{title}</span><span style={{ fontWeight: 400, color: "rgba(0,0,0,0.45)", fontSize: 12 }}>{time}</span></div>
      <div style={{ fontSize: 13, color: "rgba(0,0,0,0.75)", marginTop: 2, lineHeight: 1.3 }}>{body}</div>
    </div>
  </div>
);

/** macOS pointer; (x, y) is the hot spot. */
export const Pointer: React.FC<{ x: number; y: number; scale?: number; press?: number; opacity?: number }> = ({ x, y, scale = 1, press = 0, opacity = 1 }) => (
  <svg width={26} height={36} viewBox="0 0 17 24" style={{ position: "absolute", left: x - 2 * scale, top: y - 1.5 * scale, transform: `scale(${scale * (1 - press * 0.1)})`, transformOrigin: "2px 1.5px", opacity, overflow: "visible", filter: "drop-shadow(0 1px 1.5px rgba(0,0,0,0.35))" }}>
    <path d="M1.5 1.5 L1.5 19 L5.6 15.2 L8.4 21.6 L11.2 20.4 L8.5 14.2 L14 14.2 Z" fill="#000" stroke="#FFFFFF" strokeWidth={1.3} strokeLinejoin="round" />
  </svg>
);
