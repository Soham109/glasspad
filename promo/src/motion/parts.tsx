import React from "react";
import { GLYPH } from "./site/glyphs";
import { APPS } from "./site/apps";
import { clamp, lerp, OUT, ease } from "./lib";

/* The website's drawn pieces (web/src kit.ts, scenes.ts, glyphs.ts, apps.ts, *.css) as React.
   Every moving value is passed in per frame; nothing here keeps state or animates by itself. */

export type CSS = React.CSSProperties & Record<`--${string}`, string | number>;
const html = (s: string) => ({ __html: s });

/* Extra symbols the film needs, drawn on the same 24 grid as web/src/glyphs.ts. */
const MORE: Record<string, string> = {
  "hand.point.up.left.fill": '<path class="f" d="M9.2 4.2a1.6 1.6 0 0 1 3.2 0v6.1l.6-.1a1.5 1.5 0 0 1 1.7 1.1l.1.4.5-.1a1.5 1.5 0 0 1 1.7 1l.1.4.4-.1a1.5 1.5 0 0 1 1.8 1.4v2.4a6.5 6.5 0 0 1-6.5 6.5h-.8a5.6 5.6 0 0 1-4.5-2.3l-3-4.1a1.5 1.5 0 0 1 2.3-1.9l1.6 1.6Z"/>',
  "keyboard.fill": '<path class="f" d="M4.5 6h15A2.5 2.5 0 0 1 22 8.5v7a2.5 2.5 0 0 1-2.5 2.5h-15A2.5 2.5 0 0 1 2 15.5v-7A2.5 2.5 0 0 1 4.5 6Z"/><path d="M6 9.5h.01M9 9.5h.01M12 9.5h.01M15 9.5h.01M18 9.5h.01M6 12h.01M9 12h.01M12 12h.01M15 12h.01M18 12h.01M8 14.8h8" stroke="#fff" stroke-width="1.7"/>',
  "play.circle.fill": '<circle class="f" cx="12" cy="12" r="9.5"/><path d="M10 8.3v7.4l6-3.7Z" fill="#fff" stroke="#fff" stroke-width="1" stroke-linejoin="round"/>',
  "dock.rectangle": '<rect x="3" y="4.5" width="18" height="15" rx="3"/><rect x="6.5" y="14.2" width="11" height="2.6" rx="1.3" class="f"/>',
  "bolt.fill.mode": '<path class="f" d="M13.5 2.5 5.5 13.5h5.8L10.3 21.5l8.2-11h-5.8Z"/>',
  "doc.on.clipboard.fill": '<path class="f" d="M8 4.5h1.2a2.8 2.8 0 0 1 5.6 0H16A2.5 2.5 0 0 1 18.5 7v12a2.5 2.5 0 0 1-2.5 2.5H8A2.5 2.5 0 0 1 5.5 19V7A2.5 2.5 0 0 1 8 4.5Z"/><path d="M9 4.6h6v2.2H9z" fill="#fff" stroke="none" opacity=".55"/>',
  "play.rectangle.fill": '<rect class="f" x="2.5" y="5" width="19" height="14" rx="3"/><path d="M10 9v6l5-3Z" fill="#fff" stroke="#fff" stroke-width="1" stroke-linejoin="round"/>',
  "appletvremote.gen4.fill": '<rect class="f" x="7.5" y="2.5" width="9" height="19" rx="4.5"/><circle cx="12" cy="7.5" r="2.6" fill="#fff" opacity=".6"/>',
  "display.2": '<rect x="2.5" y="6" width="11" height="8" rx="1.5"/><path d="M6.5 17.5h3M8 14v3.5"/><rect x="11.5" y="3.5" width="10" height="7.5" rx="1.5" class="f"/>',
  "rotate.right": '<path d="M16.5 4.5 19 7l-2.5 2.5"/><path d="M19 7H9.5A4.5 4.5 0 0 0 5 11.5V13"/><rect x="5" y="13" width="9" height="7" rx="1.6"/>',
  "gearshape": '<circle cx="12" cy="12" r="3"/><path d="M12 3.5l1.3 2.2 2.5-.6.6 2.5 2.2 1.3-1.2 2.2 1.2 2.2-2.2 1.3-.6 2.5-2.5-.6L12 20.5l-1.3-2.2-2.5.6-.6-2.5-2.2-1.3 1.2-2.2-1.2-2.2 2.2-1.3.6-2.5 2.5.6Z"/>',
  "globe": '<circle cx="12" cy="12" r="8"/><path d="M4 12h16M12 4c2.4 2.4 3.4 5 3.4 8s-1 5.6-3.4 8c-2.4-2.4-3.4-5-3.4-8s1-5.6 3.4-8Z"/>',
  "magnifyingglass": '<circle cx="10.5" cy="10.5" r="6"/><path d="m15 15 5 5"/>',
  "forward.end": '<path d="M6.5 6v12l9-6Z"/><path d="M17.5 6v12"/>',
  "speaker.slash": '<path d="M4 9.5h3l4.5-4v13l-4.5-4H4Z"/><path d="M3.5 3.5 20.5 20.5"/>',
  "xmark": '<path d="m7 7 10 10M17 7 7 17"/>',
  "checkmark": '<path d="m5 12.5 4.5 4.5L19 7.5"/>',
  "iphone": '<rect x="7" y="2.5" width="10" height="19" rx="2.6"/><path d="M10.5 5h3"/>',
  "lock.small": '<rect x="6" y="10.5" width="12" height="9" rx="2.2" class="f"/><path d="M8.5 10.5V8a3.5 3.5 0 0 1 7 0v2.5"/>',
  "square.and.arrow.up": '<path d="M12 3.5v11M8.5 7 12 3.5 15.5 7"/><path d="M8 10.5H6.5A1.5 1.5 0 0 0 5 12v7a1.5 1.5 0 0 0 1.5 1.5h11A1.5 1.5 0 0 0 19 19v-7a1.5 1.5 0 0 0-1.5-1.5H16"/>',
  "square.and.arrow.down": '<path d="M12 3.5v11M8.5 11 12 14.5 15.5 11"/><path d="M8 8.5H6.5A1.5 1.5 0 0 0 5 10v9a1.5 1.5 0 0 0 1.5 1.5h11A1.5 1.5 0 0 0 19 19v-9a1.5 1.5 0 0 0-1.5-1.5H16"/>',
  "doc.on.clipboard": '<rect x="5.5" y="5" width="13" height="16" rx="2.5"/><path d="M9 5V4a1 1 0 0 1 1-1h4a1 1 0 0 1 1 1v1"/>',
  "folder": '<path d="M4 7.5A1.5 1.5 0 0 1 5.5 6h4l2 2h7A1.5 1.5 0 0 1 20 9.5v8a1.5 1.5 0 0 1-1.5 1.5h-13A1.5 1.5 0 0 1 4 17.5Z"/>',
  "arrow.uturn.backward": '<path d="M9 6 5 10l4 4"/><path d="M5 10h9.5a4.5 4.5 0 0 1 0 9H11"/>',
  "arrow.turn.right.up": '<path d="M5 18.5h8a3 3 0 0 0 3-3V5.5"/><path d="M12.5 9 16 5.5 19.5 9"/>',
  "text.append": '<path d="M4 6h16M4 10.5h16M4 15h8M16.5 13v6M13.5 16h6"/>',
  "waveform": '<path d="M4 10.5v3M7.5 7.5v9M11 4.5v15M14.5 8v8M18 10v4"/>',
};
export const glyphBody = (n: string) => GLYPH[n] ?? MORE[n] ?? "";
export const Glyph: React.FC<{ n: string; style?: CSS; className?: string }> = ({ n, style, className }) => {
  const body = glyphBody(n);
  if (!body) throw new Error(`no glyph ${n}`);
  return <svg viewBox="0 0 24 24" aria-hidden="true" className={className} style={style} dangerouslySetInnerHTML={html(body)} />;
};

export const AppIcon: React.FC<{ k: string; w?: number | string; style?: CSS; cls?: string }> = ({ k, w, style, cls = "" }) => {
  if (!APPS[k]) throw new Error(`no app ${k}`);
  return (
    <span className={`app a-${k} ${cls}`} style={{ display: "grid", ...(w !== undefined ? { width: w } : {}), ...style }}>
      <svg viewBox="0 0 24 24" dangerouslySetInnerHTML={html(APPS[k][1])} />
    </span>
  );
};

/** The Glasspad mark (web/public/icon.svg): a pad, a fading glide and the finger dot. */
export const Mark: React.FC<{ size: number; style?: CSS; trail?: number; pad?: number }> = ({ size, style, trail = 1, pad = 1 }) => (
  <svg viewBox="0 0 1024 1024" width={size} height={size} style={style}>
    <rect width="1024" height="1024" rx="230" fill="#EDECE8" opacity={pad} />
    <rect x="102" y="222" width="820" height="580" rx="140" fill="#FBFBF9" stroke="#1A1A1A" strokeOpacity="0.10" strokeWidth="4" opacity={pad} />
    <line x1="300" y1="610" x2="660" y2="440" stroke="#1A1A1A" strokeOpacity={0.1 * trail} strokeWidth="90" strokeLinecap="round" />
    <circle cx="660" cy="440" r="74" fill="#1A1A1A" fillOpacity="0.62" />
  </svg>
);

/** A button as Actions draws it: a tinted circle with the symbol, the name below. */
export const Tile: React.FC<{ name: string; g?: string; c: string; press?: number; on?: boolean; style?: CSS; h?: number; icon?: React.ReactNode; o?: number }> = ({ name, g, c, press = 1, on, style, h, icon, o = 1 }) => (
  <div className={`bt${on ? " on" : ""}`} style={{ ...({ "--c": c } as CSS), transform: press !== 1 ? `scale(${press})` : undefined, opacity: o, ...(h ? { height: h } : {}), ...style }}>
    {icon ? <span className="bt-i">{icon}</span> : <span className="bt-c"><Glyph n={g!} /></span>}
    <span className="bt-n">{name}</span>
  </div>
);

/* ---------- touches, drawn in the phone's own points ---------- */

/** The finger: the film's dot. Ink at the icon's 62%, softened while it rests. */
export const Finger: React.FC<{ x: number; y: number; o: number; s?: number; dark?: boolean; r?: number; color?: string; glow?: string }> = ({ x, y, o, s = 1, dark, r = 23, color, glow }) =>
  o <= 0.001 ? null : (
    <div style={{ position: "absolute", left: x - r, top: y - r, width: r * 2, height: r * 2, borderRadius: "50%", zIndex: 30, pointerEvents: "none",
      background: color ?? (dark ? "rgba(255,255,255,0.30)" : "rgba(26,26,26,0.26)"), opacity: o, transform: `scale(${s})`,
      boxShadow: glow }} />
  );
/** The soft ring that expands from a touch; p runs 0 to 1. */
export const Ring: React.FC<{ x: number; y: number; p: number; dark?: boolean; r?: number; color?: string }> = ({ x, y, p, dark, r = 23, color }) =>
  p <= 0 || p >= 1 ? null : (
    <div style={{ position: "absolute", left: x - r, top: y - r, width: r * 2, height: r * 2, borderRadius: "50%", zIndex: 30, pointerEvents: "none",
      boxShadow: `inset 0 0 0 2px ${color ?? (dark ? "rgba(255,255,255,0.5)" : "rgba(26,26,26,0.38)")}`,
      opacity: (1 - p) * (1 - p), transform: `scale(${lerp(1, 2.3, 1 - Math.pow(1 - p, 3))})` }} />
  );

/** A tap at frame t0: the finger lands, presses, lifts; the ring; the tile press. */
export function tapAt(f: number, t0: number) {
  const land = ease(f, t0 - 9, 9);
  const lift = ease(f, t0 + 7, 13);
  const o = land * (1 - lift);
  const s = lerp(0.72, 1, land) * lerp(1, 1.12, lift);
  const press = f < t0 ? 1 : f < t0 + 6 ? lerp(1, 0.96, ease(f, t0, 4)) : lerp(0.96, 1, springish(f - t0 - 6));
  const ring = f >= t0 ? clamp((f - t0) / 32) : 0;
  return { o, s, press, ring, done: f >= t0 };
}
/** A light spring from 0 to 1 over about 20 frames, with a small overshoot. */
export function springish(d: number) {
  if (d <= 0) return 0;
  const t = d / 60;
  return 1 - Math.exp(-14 * t) * Math.cos(18 * t);
}

/** The haptic: thin arcs that leave the phone's long edge. p runs 0 to 1. Drawn in world units. */
export const Haptic: React.FC<{ x: number; y: number; w: number; h: number; p: number; dark?: boolean; side?: "bottom" | "right" | "left" }> = ({ x, y, w, h, p, dark, side = "bottom" }) => {
  if (p <= 0 || p >= 1) return null;
  const c = dark ? "255,255,255" : "26,26,26";
  return (
    <>
      {[0, 1].map(i => {
        const q = clamp((p - i * 0.18) / 0.82);
        if (q <= 0 || q >= 1) return null;
        const g = 1 - Math.pow(1 - q, 3);
        const pad = 6 + g * 26;
        const box = side === "bottom" ? { left: x - pad, top: y - pad, width: w + 2 * pad, height: h + 2 * pad } : { left: x - pad, top: y - pad, width: w + 2 * pad, height: h + 2 * pad };
        return <div key={i} style={{ position: "absolute", ...box, borderRadius: Math.min(w, h) * 0.17 + pad, boxShadow: `0 0 0 ${lerp(2.2, 1, g)}px rgba(${c},${0.32 * (1 - q)})`, pointerEvents: "none" }} />;
      })}
    </>
  );
};

/* ---------- iPhone (device.css), drawn as a portrait body that turns ---------- */

/** Geometry of a phone whose short side is `w` world px. */
export function phoneGeom(w: number) {
  const h = w * 150 / 71.9;
  const inset = 0.0365 * w;
  const k = (w - 2 * inset) / 402;
  return { w, h, inset, k };
}
/**
 * The phone, centred at (cx, cy). `turn` 0 is upright, 1 is on its side (top pointing left, as
 * the site draws landscape). `land` is laid out in 874 x 402 points, `port` in 402 x 874; `mix`
 * picks between them (0 port, 1 land) so the screen can change during the turn.
 */
export const Phone: React.FC<{
  cx: number; cy: number; w: number; turn?: number; finish?: "light" | "dark"; shadow?: "stand" | "hand";
  land?: React.ReactNode; port?: React.ReactNode; mix?: number; screenBg?: string; style?: CSS; tilt?: number; scale?: number;
}> = ({ cx, cy, w, turn = 0, finish = "light", shadow = "stand", land, port, mix, screenBg, style, tilt = 0, scale = 1 }) => {
  const g = phoneGeom(w);
  const m = mix ?? (turn > 0.5 ? 1 : 0);
  const sw = w - 2 * g.inset, sh = g.h - 2 * g.inset;
  return (
    <div className="iphone" data-orient="portrait" data-finish={finish}
      style={{ position: "absolute", left: cx - w / 2, top: cy - g.h / 2, width: w, transform: `rotate(${-90 * turn + tilt}deg) scale(${scale})`, ...style }}>
      <i className="ip-btn l action" /><i className="ip-btn l up" /><i className="ip-btn l down" /><i className="ip-btn r side" /><i className="ip-btn r cam" />
      <div className="ip-body" style={shadow === "hand" ? { boxShadow: `inset 0 0 0 0.35cqmin var(--band-edge), 0 ${w * 0.06}px ${w * 0.09}px ${-w * 0.04}px rgba(0,0,0,0.5)` } : undefined}>
        <div className="ip-bezel" />
        <div className="ip-screen" style={screenBg ? { background: screenBg } : undefined}>
          {port && m < 1 ? (
            <div className="pt" style={{ transform: `scale(${g.k})`, opacity: 1 - m }}>{port}</div>
          ) : null}
          {land && m > 0 ? (
            <div style={{ position: "absolute", left: 0, top: 0, width: sw, height: sh, opacity: m }}>
              <div className="pt land" style={{ transform: `translate(${sw}px, 0) rotate(90deg) scale(${g.k})` }}>{land}</div>
            </div>
          ) : null}
        </div>
        <div className="ip-island" />
      </div>
    </div>
  );
};

/** The phone's stand (site .sp-stand), under a landscape phone of visible width `width`. */
export const Stand: React.FC<{ x: number; y: number; width: number; o?: number; dim?: number }> = ({ x, y, width, o = 1, dim = 1 }) => {
  const u = width / 21;
  return (
    <div style={{ position: "absolute", left: x, top: y, width, height: 3.4 * u, opacity: o, filter: dim !== 1 ? `brightness(${dim})` : undefined }}>
      <div style={{ position: "absolute", left: "22%", right: "22%", top: 0, height: 1.9 * u, background: "linear-gradient(#A9A6A0, #C2BFB9)", clipPath: "polygon(14% 0, 86% 0, 100% 100%, 0 100%)" }} />
      <div style={{ position: "absolute", left: "14%", right: "14%", bottom: 0.5 * u, height: 1 * u, borderRadius: 0.5 * u, background: "#BAB7B1", boxShadow: `0 ${0.5 * u}px ${0.8 * u}px ${-0.3 * u}px rgba(20,20,20,0.3)` }} />
    </div>
  );
};

/* ---------- MacBook (redo.css .mbp), placed by its lid ---------- */
export function macGeom(lid: number) {
  const W = lid / 0.58, u = W / 100;
  // the display inside the lid, relative to the lid's top left
  return { W, u, dx: 1.1 * u + 0.28 * u * 0, dy: 1.3 * u, dw: lid - 2.2 * u, dh: lid / 1.49 - 2.7 * u, lidH: lid / 1.49 };
}
/** A MacBook whose lid's top left is at (x, y) and is `lid` wide. Children fill its display. */
export const MacBook: React.FC<{ x: number; y: number; lid: number; style?: CSS; displayStyle?: CSS; children?: React.ReactNode }> = ({ x, y, lid, style, displayStyle, children }) => {
  const g = macGeom(lid);
  return (
    <div className="mbw" style={{ position: "absolute", left: x - (g.W - lid) / 2, top: y - 4 * g.u, width: g.W, ...style }}>
      <div className="mbp">
        <div className="mbp-lid"><div className="mbp-glass" /><div className="mbp-display" style={displayStyle}>{children}</div><div className="mbp-notch" /></div>
        <div className="mbp-hinge" /><div className="mbp-base"><div className="mbp-keys" /><div className="mbp-pad" /></div><div className="mbp-lip" /><div className="mbp-shadow" />
      </div>
    </div>
  );
};
/** World rectangle of a MacBook's display. */
export const macDisplay = (x: number, y: number, lid: number) => { const g = macGeom(lid); return { x: x + g.dx, y: y + g.dy, w: g.dw, h: g.dh }; };

/* ---------- External display on a stand (surface.css .mon), placed by its frame ---------- */
export function monGeom(w: number) {
  const pad = 0.021 * w, sw = w - 2 * pad;
  return { pad, sw, sh: sw * 9 / 16 };
}
export const Monitor: React.FC<{ x: number; y: number; w: number; style?: CSS; screenStyle?: CSS; children?: React.ReactNode; dim?: number }> = ({ x, y, w, style, screenStyle, children, dim = 1 }) => (
  <div className="mon" style={{ left: x, top: y, width: w, filter: dim !== 1 ? `brightness(${dim})` : undefined, ...style }}>
    <div className="mon-frame" style={{ boxShadow: `0 0 0 ${w * 0.004}px #C6C3BD, 0 ${w * 0.035}px ${w * 0.07}px ${-w * 0.035}px rgba(20,20,20,0.4)` }}><div className="mon-screen" style={screenStyle}>{children}</div></div>
    <div style={{ width: "15%", height: 0.157 * w, margin: "-1px auto 0", background: "linear-gradient(90deg, #B4B1AB, #CFCCC6 40%, #C2BFB9)", clipPath: "polygon(8% 0, 92% 0, 100% 100%, 0 100%)" }} />
    <div style={{ width: "30%", height: 0.019 * w, margin: "0 auto", borderRadius: `${0.007 * w}px ${0.007 * w}px ${0.01 * w}px ${0.01 * w}px`, background: "#B2AFA9", boxShadow: `0 ${0.012 * w}px ${0.021 * w}px ${-0.007 * w}px rgba(20,20,20,0.3)` }} />
  </div>
);
export const monDisplay = (x: number, y: number, w: number) => { const g = monGeom(w); return { x: x + g.pad, y: y + g.pad, w: g.sw, h: g.sh }; };

/* ---------- Mac screen contents (sizes in units of the display, as on the site) ---------- */
const APPLE = '<path d="M11.6 9c0-2 1.6-2.9 1.7-3-1-1.4-2.4-1.6-2.9-1.6-1.2-.1-2.4.7-3 .7-.6 0-1.6-.7-2.6-.7C3.4 4.4 2.1 5.2 1.4 6.5 0 9 1 12.7 2.4 14.7c.7 1 1.5 2 2.5 2 1 0 1.4-.6 2.6-.6s1.5.6 2.6.6c1.1 0 1.8-1 2.4-2 .8-1.1 1.1-2.2 1.1-2.3 0 0-2-.8-2-3.4ZM9.7 3c.5-.7.9-1.6.8-2.5-.8 0-1.8.5-2.3 1.2-.5.6-1 1.5-.8 2.4.9.1 1.8-.5 2.3-1.1Z"/>';
const WIFI = '<path d="M2.5 9.5a14 14 0 0 1 19 0M5.5 12.8a9.5 9.5 0 0 1 13 0M8.6 16a5 5 0 0 1 6.8 0"/><circle cx="12" cy="19" r="1.4" fill="currentColor" stroke="none"/>';
const CC = '<rect x="3" y="5" width="18" height="6" rx="3"/><circle cx="17.5" cy="8" r="1.6" fill="currentColor"/><rect x="3" y="13" width="18" height="6" rx="3"/><circle cx="6.5" cy="16" r="1.6" fill="currentColor"/>';
export const MENUS: Record<string, string[]> = {
  Finder: ["File", "Edit", "View", "Go", "Window", "Help"],
  Safari: ["File", "Edit", "View", "History", "Bookmarks", "Window", "Help"],
  Xcode: ["File", "Edit", "View", "Find", "Navigate", "Editor", "Product", "Debug", "Window", "Help"],
  "Final Cut Pro": ["File", "Edit", "Trim", "Mark", "Clip", "Modify", "View", "Window", "Help"],
  Notes: ["File", "Edit", "Format", "View", "Window", "Help"],
  Mail: ["File", "Edit", "View", "Mailbox", "Message", "Format", "Window", "Help"],
  Music: ["File", "Edit", "Song", "View", "Controls", "Account", "Window", "Help"],
  Keynote: ["File", "Edit", "Insert", "Slide", "Format", "Arrange", "View", "Play", "Window", "Help"],
  Messages: ["File", "Edit", "View", "Conversations", "Window", "Help"],
};
/** The macOS menu bar: Apple menu, the app's menus, status items and the clock. */
export const MenuBar: React.FC<{ app: string; clock?: string; extra?: React.ReactNode; style?: CSS; appO?: number }> = ({ app, clock = "Fri 9:41", extra, style, appO = 1 }) => (
  <div className="mb" style={style}>
    <svg className="mb-apple" viewBox="0 0 14 17" dangerouslySetInnerHTML={html(APPLE)} />
    <span style={{ display: "flex", gap: "2.3cqw", opacity: appO }}>
      <b className="mb-app">{app}</b>
      {(MENUS[app] ?? []).map(m => <span key={m}>{m}</span>)}
    </span>
    <span className="mb-r">{extra}<svg className="mb-i" viewBox="0 0 24 24" dangerouslySetInnerHTML={html(WIFI)} /><svg className="mb-i" viewBox="0 0 24 24" dangerouslySetInnerHTML={html(CC)} />{clock ? <span>{clock}</span> : null}</span>
  </div>
);
export type Box = { x: number; y: number; w: number; h: number };
/** A window: traffic lights, a body. Box in percent of the display. */
export const Win: React.FC<{ box: Box; front?: boolean; z?: number; bar?: React.ReactNode; barStyle?: CSS; style?: CSS; children?: React.ReactNode; o?: number; s?: number; origin?: string }> = ({ box, front, z, bar, barStyle, style, children, o = 1, s = 1, origin }) =>
  o <= 0.001 ? null : (
    <div className={`md-win${front ? " front" : ""}`} style={{ left: `${box.x}%`, top: `${box.y}%`, width: `${box.w}%`, height: `${box.h}%`, zIndex: z ?? (front ? 3 : 2), opacity: o, transform: s !== 1 ? `scale(${s})` : undefined, transformOrigin: origin, ...style }}>
      <div className="wb" style={barStyle}><i /><i /><i />{bar}</div>
      <div className="wbody">{children}</div>
    </div>
  );
export const Doc: React.FC<{ n?: number; shift?: number; style?: CSS; rows?: string[] }> = ({ n = 14, shift = 0, style, rows }) => {
  const R = rows ?? ["h", "", "88", "94", "p", "", "76", "90", "h", "", "82", "p p2", "", "70", "86", "", "92", "64", "h", "", "80"];
  return (
    <div className="md-doc" style={{ transform: shift ? `translateY(${-shift}cqh)` : undefined, ...style }}>
      {Array.from({ length: n }, (_, i) => { const r = R[i % R.length]; return /\d/.test(r) ? <i key={i} style={{ width: r + "%" }} /> : <i key={i} className={r} />; })}
    </div>
  );
};
/** The pointer, at x, y in percent of the display. */
export const Cursor: React.FC<{ x: number; y: number; press?: number; o?: number; w?: string }> = ({ x, y, press = 1, o = 1, w }) =>
  o <= 0.001 ? null : (
    <svg className="md-cursor" viewBox="0 0 16 22" style={{ left: `${x}%`, top: `${y}%`, transform: `scale(${press})`, opacity: o, zIndex: 20, ...(w ? { width: w } : {}) }}>
      <path d="M1 1v17l4.6-4.4 3 6.9 3-1.3-3-6.8H15Z" fill="#1A1A1A" stroke="#fff" strokeWidth="1.4" strokeLinejoin="round" />
    </svg>
  );
export const Dock: React.FC<{ keys: string[]; running?: string[]; bounce?: Record<string, number>; style?: CSS; size?: number }> = ({ keys, running = [], bounce = {}, style, size }) => (
  <div className="md-dock" style={style}>
    {keys.map(k => (
      <div key={k} className="app-slot">
        <AppIcon k={k} w={size !== undefined ? `${size}cqw` : undefined} style={bounce[k] ? { transform: `translateY(${-bounce[k] * 38}%)` } : undefined} />
        <i className="md-run" style={{ opacity: running.includes(k) ? 1 : 0 }} />
      </div>
    ))}
  </div>
);
/** The macOS Dock bounce, 0 to 1 over its run (web redo.css dockBounce). */
export function dockBounce(u: number) {
  if (u <= 0 || u >= 1) return 0;
  const k: [number, number][] = [[0, 0], [0.3, 1], [0.55, 0], [0.72, 0.37], [1, 0]];
  for (let i = 1; i < k.length; i++) if (u <= k[i][0]) { const t = (u - k[i - 1][0]) / (k[i][0] - k[i - 1][0]); const e = i % 2 ? Math.sin(t * Math.PI / 2) : 1 - Math.cos(t * Math.PI / 2); return lerp(k[i - 1][1], k[i][1], e); }
  return 0;
}
/** The front app's header in Actions. */
export const Front: React.FC<{ k: string; name: string; style?: CSS }> = ({ k, name, style }) => (
  <div className="af" style={style}><span className="af-i"><AppIcon k={k} /></span><div><b>{name}</b><span>In front on your Mac</span></div></div>
);

/** A poster frame (the site's drawn film still). */
export const Poster: React.FC<{ style?: CSS; alt?: boolean }> = ({ style, alt }) => (
  <span className="pst" style={{ display: "block", ...(alt ? { background: "#2E4A3C" } : {}), ...style }}>
    <i className="s1" style={alt ? { background: "#F2E8D0", left: "60%", top: "14%", width: "22%" } : undefined} />
    <i className="s2" style={alt ? { left: "8%", top: "40%", width: "46%", height: "40%", background: "#5C8A62", borderRadius: "50% 50% 0 0" } : undefined} />
    <i className="s3" style={alt ? { background: "#3E6B4F", boxShadow: "none" } : undefined} />
  </span>
);

/** Feature name: a dot in the scene's accent, then the name. p runs 0 to 1 in, q 0 to 1 out. */
export const Caption: React.FC<{ text: string; color: string; p: number; q?: number; dark?: boolean; style?: CSS }> = ({ text, color, p, q = 0, dark, style }) => {
  const a = clamp(p), b = clamp(q);
  if (a <= 0.001 || b >= 0.999) return null;
  return (
    <div className="fm-cap" style={{ color: dark ? "#F2F1EE" : "#1A1A1A", ...style }}>
      <i style={{ background: color, transform: `scale(${OUT(clamp(a * 1.3)) * (1 - b)})` }} />
      <span style={{ opacity: clamp(a * 1.4 - 0.2) * (1 - b), transform: `translateX(${(1 - OUT(a)) * -14 - b * 10}px)` }}>{text}</span>
    </div>
  );
};

/** A horizontal motion blur for fast sideways moves: `px` is the distance moved this frame,
    in screen pixels; half of it becomes the blur, so slow moves stay sharp. */
export const BlurX: React.FC<{ id: string; px: number; children: React.ReactNode; style?: CSS }> = ({ id, px, children, style }) => {
  const sd = Math.min(10, Math.max(0, Math.abs(px) * 0.3 - 0.6));
  return (
    <div style={{ position: "absolute", inset: 0, filter: sd > 0.05 ? `url(#${id})` : undefined, ...style }}>
      {sd > 0.05 ? <svg width="0" height="0" style={{ position: "absolute" }}><filter id={id} x="-10%" y="0" width="120%" height="100%"><feGaussianBlur stdDeviation={`${sd} 0`} /></filter></svg> : null}
      {children}
    </div>
  );
};

/** A scene title: rises out of a mask on its voice line, then lifts away. p and q run 0 to 1. */
export const Title: React.FC<{ text: string; p: number; q?: number; dark?: boolean; style?: CSS }> = ({ text, p, q = 0, dark, style }) => {
  if (p <= 0.001 || q >= 0.999) return null;
  const a = OUT(clamp(p)), b = clamp(q);
  return (
    <div className="fm-title" style={{ color: dark ? "#F2F1EE" : "#1A1A1A", ...style }}>
      <span style={{ transform: `translateY(${(1 - a) * 105 - b * 18}%)`, opacity: 1 - b }}>{text}</span>
    </div>
  );
};
