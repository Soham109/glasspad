// The Mac, flat. Screen content is authored in MacBook Pro 14" points (1512 x 982) and scaled,
// so every scene draws the same menu bar, Dock and windows at the same proportions.
import React from "react";
import { Img, staticFile } from "remotion";
import { C, FONT } from "../system";

export const SW = 1512;
export const SH = 982;
const MENU = 34;

// ---------- Device ----------
/** A MacBook seen from the front. `width` is the lid width in px. */
export const MacBook: React.FC<{ width: number; children?: React.ReactNode; base?: boolean; style?: React.CSSProperties }> = ({ width, children, base = true, style }) => {
  const bez = width * 0.018;
  const sw = width - bez * 2;
  const sh = (sw * SH) / SW;
  const lidH = sh + bez * 2.4;
  return (
    <div style={{ position: "relative", width, height: lidH + (base ? width * 0.045 : 0), ...style }}>
      <div style={{ position: "absolute", left: 0, top: 0, width, height: lidH, borderRadius: width * 0.03, background: C.bezel, boxShadow: `inset 0 0 0 ${width * 0.0025}px #2A2A2A` }} />
      <div style={{ position: "absolute", left: bez, top: bez, width: sw, height: sh, borderRadius: width * 0.012, overflow: "hidden", background: C.desk }}>
        <div style={{ position: "absolute", left: 0, top: 0, width: SW, height: SH, transform: `scale(${sw / SW})`, transformOrigin: "0 0" }}>{children}</div>
      </div>
      {/* notch */}
      <div style={{ position: "absolute", left: "50%", top: 0, width: width * 0.12, height: bez * 1.55, transform: "translateX(-50%)", background: C.bezel, borderRadius: `0 0 ${width * 0.008}px ${width * 0.008}px` }} />
      {base ? (
        <>
          <div style={{ position: "absolute", left: -width * 0.07, top: lidH - 1, width: width * 1.14, height: width * 0.022, background: C.band, borderRadius: `0 0 ${width * 0.04}px ${width * 0.04}px` }} />
          <div style={{ position: "absolute", left: "50%", top: lidH - 1, width: width * 0.16, height: width * 0.009, transform: "translateX(-50%)", background: "#A3A09A", borderRadius: `0 0 ${width * 0.01}px ${width * 0.01}px` }} />
        </>
      ) : null}
    </div>
  );
};

/** Only the display (for close shots), same bezel language. */
export const Display: React.FC<{ width: number; children?: React.ReactNode; style?: React.CSSProperties }> = ({ width, children, style }) => <MacBook width={width} base={false} style={style}>{children}</MacBook>;

// ---------- Screen chrome ----------
export const icon = (id: string) => staticFile(`v2/icons/${id}.png`);

export const MenuBar: React.FC<{ app: string; menus?: string[]; dark?: boolean; tint?: string }> = ({ app, menus = ["File", "Edit", "View", "Window", "Help"], dark = false, tint }) => {
  const fg = dark ? C.paper : C.ink;
  return (
    <div style={{ position: "absolute", left: 0, top: 0, width: SW, height: MENU, background: tint ?? (dark ? "rgba(20,20,20,0.55)" : "rgba(242,241,238,0.72)"), display: "flex", alignItems: "center", padding: "0 18px", fontFamily: FONT, fontSize: 15, color: fg, gap: 22 }}>
      <svg width="15" height="17" viewBox="0 0 15 17" style={{ marginRight: 2 }}>
        <circle cx="7.5" cy="9.5" r="6.5" fill={fg} />
      </svg>
      <span style={{ fontWeight: 700 }}>{app}</span>
      {menus.map((m) => (
        <span key={m} style={{ fontWeight: 500 }}>{m}</span>
      ))}
      <span style={{ flex: 1 }} />
      <svg width="20" height="14" viewBox="0 0 20 14">
        <path d="M10 13 L3 6 A10 10 0 0 1 17 6 Z" fill={fg} />
      </svg>
      <svg width="28" height="13" viewBox="0 0 28 13">
        <rect x="0.5" y="0.5" width="24" height="12" rx="3.5" fill="none" stroke={fg} />
        <rect x="2.5" y="2.5" width="17" height="8" rx="2" fill={fg} />
        <rect x="25.5" y="4" width="2" height="5" rx="1" fill={fg} />
      </svg>
      <span style={{ fontWeight: 500 }}>Thu 15 Oct&nbsp;&nbsp;9:41</span>
    </div>
  );
};

export const DOCK_APPS = ["com.apple.finder", "com.apple.Safari", "com.apple.mail", "com.apple.MobileSMS", "com.apple.iCal", "com.apple.Notes", "com.apple.Music", "com.spotify.client", "com.microsoft.Word", "com.microsoft.Excel", "com.apple.dt.Xcode", "com.apple.systempreferences"];
export const DOCK_ICON = 62;
const DOCK_GAP = 10;
export const dockWidth = (n = DOCK_APPS.length) => n * DOCK_ICON + (n - 1) * DOCK_GAP + 24;
/** Centre of a Dock icon in screen points. */
export const dockIconPos = (id: string) => {
  const i = DOCK_APPS.indexOf(id);
  const left = (SW - dockWidth()) / 2 + 12;
  return { x: left + i * (DOCK_ICON + DOCK_GAP) + DOCK_ICON / 2, y: SH - 10 - 12 - DOCK_ICON / 2 };
};

export const Dock: React.FC<{ running?: string[]; bounce?: Record<string, number>; dark?: boolean }> = ({ running = [], bounce = {}, dark = false }) => {
  const w = dockWidth();
  return (
    <div style={{ position: "absolute", left: (SW - w) / 2, bottom: 10, width: w, height: DOCK_ICON + 24, borderRadius: 26, background: dark ? "rgba(40,40,40,0.62)" : "rgba(251,250,248,0.62)", boxShadow: `inset 0 0 0 1px ${dark ? C.paper12 : C.ink06}` }}>
      {DOCK_APPS.map((id, i) => (
        <div key={id} style={{ position: "absolute", left: 12 + i * (DOCK_ICON + DOCK_GAP), top: 12 - (bounce[id] ?? 0), width: DOCK_ICON, height: DOCK_ICON }}>
          <Img src={icon(id)} style={{ width: DOCK_ICON, height: DOCK_ICON }} />
          {running.includes(id) ? <div style={{ position: "absolute", left: DOCK_ICON / 2 - 2.5, top: DOCK_ICON + 5 + (bounce[id] ?? 0), width: 5, height: 5, borderRadius: 5, background: dark ? C.paper : C.ink }} /> : null}
        </div>
      ))}
    </div>
  );
};

// ---------- Windows ----------
export const Win: React.FC<{ x: number; y: number; w: number; h: number; title?: string; active?: boolean; dark?: boolean; children?: React.ReactNode; style?: React.CSSProperties; bar?: number }> = ({ x, y, w, h, title, active = true, dark = false, children, style, bar = 52 }) => (
  <div style={{ position: "absolute", left: x, top: y, width: w, height: h, borderRadius: 18, overflow: "hidden", background: dark ? "#1E1E1E" : C.sheet, boxShadow: `0 0 0 1px ${dark ? C.paper12 : C.ink12}`, fontFamily: FONT, ...style }}>
    <div style={{ position: "absolute", left: 0, top: 0, right: 0, height: bar, display: "flex", alignItems: "center", padding: "0 20px", gap: 9, borderBottom: `1px solid ${dark ? C.paper12 : C.ink06}` }}>
      {["#FF5F57", "#FEBC2E", "#28C840"].map((c, i) => (
        <div key={i} style={{ width: 13, height: 13, borderRadius: 13, background: active ? c : dark ? "#3A3A3A" : "#D6D4CF" }} />
      ))}
      {title ? <div style={{ position: "absolute", left: 0, right: 0, textAlign: "center", fontSize: 15, fontWeight: 600, color: dark ? C.paper60 : C.ink60 }}>{title}</div> : null}
    </div>
    <div style={{ position: "absolute", left: 0, top: bar, right: 0, bottom: 0 }}>{children}</div>
  </div>
);

/** Grey text lines, the universal stand-in for body copy. */
export const Lines: React.FC<{ n: number; w?: number[]; gap?: number; h?: number; color?: string; x?: number; y?: number }> = ({ n, w = [100, 92, 97, 64], gap = 20, h = 9, color = C.ink12, x = 0, y = 0 }) => (
  <>
    {Array.from({ length: n }).map((_, i) => (
      <div key={i} style={{ position: "absolute", left: x, top: y + i * gap, width: `${w[i % w.length]}%`, maxWidth: `calc(100% - ${x * 2}px)`, height: h, borderRadius: h, background: color }} />
    ))}
  </>
);

export const WordDoc: React.FC<{ dark?: boolean }> = ({ dark }) => (
  <div style={{ position: "absolute", inset: 0, background: dark ? "#2A2A2A" : C.desk }}>
    <div style={{ position: "absolute", left: 0, right: 0, top: 0, height: 46, background: dark ? "#1E1E1E" : C.sheet, borderBottom: `1px solid ${C.ink06}`, display: "flex", alignItems: "center", gap: 26, padding: "0 22px", fontSize: 14, fontWeight: 600, color: "#2B5797" }}>
      {["Home", "Insert", "Draw", "Design", "Layout", "Review", "View"].map((t, i) => (
        <span key={t} style={{ color: i === 0 ? "#2B5797" : dark ? C.paper60 : C.ink60, borderBottom: i === 0 ? "2px solid #2B5797" : "none", paddingBottom: 3 }}>{t}</span>
      ))}
    </div>
    <div style={{ position: "absolute", left: "50%", top: 70, width: 560, bottom: -40, transform: "translateX(-50%)", background: dark ? "#1E1E1E" : "#FFFFFF", boxShadow: `0 0 0 1px ${C.ink06}`, padding: "56px 60px" }}>
      <NotesBody dark={dark} size={15} title={30} />
    </div>
  </div>
);

export const SafariPage: React.FC<{ dark?: boolean }> = ({ dark }) => {
  const fg = dark ? C.paper : C.ink, soft = dark ? C.paper60 : C.ink60;
  return (
    <div style={{ position: "absolute", inset: 0, background: dark ? "#1E1E1E" : "#FFFFFF", fontFamily: FONT }}>
      <div style={{ position: "absolute", left: "50%", top: 12, width: 420, height: 34, transform: "translateX(-50%)", borderRadius: 10, background: dark ? "#2C2C2C" : C.desk, display: "flex", alignItems: "center", justifyContent: "center", fontSize: 14, color: soft, fontWeight: 500 }}>glasspad.sohamaggarwal.com</div>
      <div style={{ position: "absolute", left: 60, right: 60, top: 64, height: 40, display: "flex", alignItems: "center", gap: 28, fontSize: 15, fontWeight: 500, color: soft }}>
        <span style={{ fontSize: 19, fontWeight: 700, color: fg, letterSpacing: "-0.02em", flex: 1 }}>Glasspad</span>
        <span>Modes</span><span>Privacy</span><span>Install</span>
        <span style={{ padding: "6px 14px", borderRadius: 9, background: fg, color: dark ? C.ink : C.paper, fontWeight: 600 }}>GitHub</span>
      </div>
      <div style={{ position: "absolute", left: 60, right: 60, top: 118, height: 250, borderRadius: 16, background: dark ? "#2A2A2A" : C.ink, overflow: "hidden" }}>
        <div style={{ position: "absolute", left: "60%", top: 96, width: 300, height: 34, borderRadius: 34, background: C.paper, opacity: 0.12, transform: "rotate(-24deg)", transformOrigin: "0 50%" }} />
        <div style={{ position: "absolute", left: "calc(60% + 250px)", top: 26, width: 56, height: 56, borderRadius: 56, background: C.paper, opacity: 0.7 }} />
        <div style={{ position: "absolute", left: 50, top: 58, fontSize: 48, fontWeight: 700, letterSpacing: "-0.035em", color: C.paper, lineHeight: 1.08 }}>Your iPhone,<br /><span style={{ color: C.paper60 }}>as a Mac trackpad.</span></div>
        <div style={{ position: "absolute", left: 52, top: 186, fontSize: 17, fontWeight: 500, color: C.paper60 }}>Free and open source. Private by design.</div>
      </div>
      <div style={{ position: "absolute", left: 60, right: 60, top: 400, display: "flex", gap: 36 }}>
        {[["Trackpad", "Gestures follow your Mac's own trackpad settings."], ["Modes", "Keyboard, Media, Apps and Actions, one tap away."], ["Private", "Encrypted, on your own Wi-Fi. No account."]].map(([h, t]) => (
          <div key={h} style={{ flex: 1 }}>
            <div style={{ fontSize: 20, fontWeight: 700, color: fg, letterSpacing: "-0.01em" }}>{h}</div>
            <div style={{ marginTop: 8, fontSize: 15, lineHeight: 1.45, color: soft }}>{t}</div>
          </div>
        ))}
      </div>
    </div>
  );
};

/** A plausible notes document: the same text in TextEdit and Word. */
export const NotesBody: React.FC<{ dark?: boolean; size?: number; title?: number }> = ({ dark, size = 15, title = 26 }) => {
  const fg = dark ? C.paper : C.ink, soft = dark ? C.paper60 : C.ink60;
  const p = { fontSize: size, lineHeight: 1.55, color: fg, margin: `0 0 ${size * 0.9}px` };
  return (
    <div style={{ fontFamily: FONT }}>
      <div style={{ fontSize: title, fontWeight: 700, letterSpacing: "-0.02em", color: fg }}>Field notes</div>
      <div style={{ fontSize: size * 0.9, color: soft, margin: `6px 0 ${size * 1.4}px` }}>Thursday 15 October</div>
      <div style={p}>Moved the review to Friday at ten. Mira will bring the prints from the lab, and the room on the third floor is ours until noon.</div>
      <div style={p}>For the workshop: open with what changed since spring, then the questions that are still open. Keep it short and leave time for the demo at the end.</div>
      <div style={{ ...p, fontWeight: 600 }}>Before Friday</div>
      <div style={p}>Ask Jonah about the projector cable. Print the agenda. Order more index cards.</div>
    </div>
  );
};

export const Player: React.FC<{ progress: number; elapsed: string; remain: string; hideCover?: boolean }> = ({ progress, elapsed, remain, hideCover }) => (
  <div style={{ position: "absolute", inset: 0, background: "#121212", color: C.paper, fontFamily: FONT }}>
    <div style={{ position: "absolute", left: 40, top: 40, width: 300, height: 300, borderRadius: 10, overflow: "hidden", opacity: hideCover ? 0 : 1 }}>
      <Cover size={300} />
    </div>
    <div style={{ position: "absolute", left: 380, top: 120, fontSize: 15, fontWeight: 600, color: C.paper60, letterSpacing: "0.04em" }}>SONG</div>
    <div style={{ position: "absolute", left: 380, top: 146, fontSize: 56, fontWeight: 700, letterSpacing: "-0.035em" }}>Uplifting Electronic Indie</div>
    <div style={{ position: "absolute", left: 380, top: 232, fontSize: 22, fontWeight: 500, color: C.paper60 }}>WinnieTheMoog</div>
    <div style={{ position: "absolute", left: 40, right: 40, bottom: 34, height: 64 }}>
      <div style={{ position: "absolute", left: 60, right: 60, top: 10, height: 5, borderRadius: 5, background: "rgba(242,241,238,0.25)" }} />
      <div style={{ position: "absolute", left: 60, top: 10, height: 5, borderRadius: 5, width: `calc((100% - 120px) * ${progress})`, background: C.paper }} />
      <div style={{ position: "absolute", left: `calc(60px + (100% - 120px) * ${progress} - 7px)`, top: 5, width: 15, height: 15, borderRadius: 15, background: C.paper }} />
      <div style={{ position: "absolute", left: 0, top: 3, fontSize: 13, color: C.paper60 }}>{elapsed}</div>
      <div style={{ position: "absolute", right: 0, top: 3, fontSize: 13, color: C.paper60 }}>{remain}</div>
    </div>
  </div>
);

/** The film's flat cover art, the same drawing the phone shows (DemoScript.swift). */
export const Cover: React.FC<{ size: number }> = ({ size }) => {
  const k = size / 900;
  return (
    <div style={{ position: "relative", width: size, height: size, background: C.graphite }}>
      <div style={{ position: "absolute", left: 250 * k, top: 170 * k, width: 400 * k, height: 400 * k, borderRadius: "50%", background: C.paper }} />
      <div style={{ position: "absolute", left: 395 * k, top: 315 * k, width: 110 * k, height: 110 * k, borderRadius: "50%", background: C.ink }} />
      <div style={{ position: "absolute", left: 0, top: 650 * k, width: size, height: 70 * k, background: C.accent }} />
    </div>
  );
};

// ---------- Pointer ----------
/** macOS arrow pointer; (x, y) is the hot spot. */
export const Pointer: React.FC<{ x: number; y: number; scale?: number; opacity?: number; press?: number }> = ({ x, y, scale = 1, opacity = 1, press = 0 }) => (
  <svg width={34} height={48} viewBox="0 0 17 24" style={{ position: "absolute", left: x - 3 * scale, top: y - 2 * scale, transform: `scale(${scale * (1 - press * 0.12)})`, transformOrigin: "3px 2px", opacity, overflow: "visible" }}>
    <path d="M1.5 1.5 L1.5 19 L5.6 15.2 L8.4 21.6 L11.2 20.4 L8.5 14.2 L14 14.2 Z" fill={C.ink} stroke="#FFFFFF" strokeWidth={1.4} strokeLinejoin="round" />
  </svg>
);
