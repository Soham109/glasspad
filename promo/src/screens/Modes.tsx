import React from "react";
import { C, FONT, MODE_ACCENT } from "../theme";
import { AppTile, APPS, Icon, GL } from "./apps";
import { Dots, Rings, StatusDot, Finger, Ripple } from "./Trackpad";
import { Win, DocLines, MenuBar, MacDock, WALL1, Cursor } from "./Desktop";
import { DISP_W, DISP_H } from "../devices/Mac";
import { clamp, lerp, minJerk, spring, snappy, prog } from "../motion";

/* Recreations of the iPhone app's own screens (Apps/iOS/Sources/Modes, docs/img/modes.png),
   authored in iPhone points exactly as web/src/modes.ts lays them out. k = frames since the mode began. */

/** One finger tap on a mode screen: finger in, press, ripple, lift. */
export const tapFx = (k: number, at: number, x: number, y: number): { f: Finger[]; r: Ripple[] } => {
  const f: Finger[] = [], r: Ripple[] = [];
  if (k >= at - 9 && k <= at + 22) {
    const tin = minJerk((k - (at - 9)) / 8), tl = minJerk((k - (at + 8)) / 13);
    f.push({ x, y, o: tin * (1 - tl), s: lerp(0.7, 1, tin) * (k >= at && k < at + 6 ? 0.9 : 1) * lerp(1, 1.12, tl) });
  }
  if (k >= at && k < at + 50) r.push({ x, y, age: k - at });
  return { f, r };
};
const press = (k: number, at: number) => (k >= at && k < at + 7 ? 0.94 : 1);
const Fx: React.FC<{ fx: { f: Finger[]; r: Ripple[] }[] }> = ({ fx }) => (
  <>
    {fx.flatMap((x) => x.r).map((r, i) => <Rings key={i} r={r} />)}
    <Dots fingers={fx.flatMap((x) => x.f)} size={46} />
  </>
);
const pt: React.CSSProperties = { position: "absolute", inset: 0, background: C.paper, fontFamily: FONT, color: C.ink };
const raised: React.CSSProperties = { background: C.raised, borderRadius: 22, boxShadow: "0 0 0 1px rgba(26,26,26,0.06)" };

/* ---------------- Dock (landscape, 874 x 402) ---------------- */
export const DOCK_TILES = ["finder", "web", "mail", "notes", "cal", "music", "photos", "term"];
export const DOCK = { tapNotes: 56, open: 76 };
const dockTileCenter = (i: number): [number, number] => {
  const left = 92, right = 64, gap = 14, w = (874 - left - right - gap * 7) / 8;
  return [left + i * (w + gap) + w / 2, 201 - 16];
};
export const DockScreen: React.FC<{ k: number }> = ({ k }) => {
  const [nx, ny] = dockTileCenter(3);
  const opened = k >= DOCK.tapNotes + 2;
  return (
    <div style={pt}>
      <div style={{ position: "absolute", left: 92, right: 64, top: 0, bottom: 10, display: "grid", gridTemplateColumns: "repeat(8, 1fr)", columnGap: 14, alignContent: "center" }}>
        {DOCK_TILES.map((t, i) => {
          const run = t === "finder" || t === "web" || t === "music" || (t === "notes" && opened);
          const act = opened ? t === "notes" : t === "web";
          return (
            <div key={t} style={{ display: "flex", flexDirection: "column", alignItems: "center", gap: 7, fontSize: 13 }}>
              <AppTile k={t} size={72} style={{ transform: `scale(${t === "notes" ? press(k, DOCK.tapNotes) : 1})` }} />
              <span>{APPS[t].name}</span>
              <i style={{ width: 5, height: 5, borderRadius: 3, background: act ? "#3D7BF2" : "rgba(26,26,26,0.45)", opacity: run ? 1 : 0 }} />
            </div>
          );
        })}
      </div>
      <Fx fx={[tapFx(k, DOCK.tapNotes, nx, ny)]} />
    </div>
  );
};
const dockBounce = (k: number, at: number) => {
  const t = (k - at) / 54;
  if (t < 0 || t > 1) return 0;
  return Math.abs(Math.sin(t * Math.PI * 2)) * (t < 0.5 ? 34 : 13);
};
export const DockMac: React.FC<{ k: number }> = ({ k }) => {
  const o = clamp(spring(k, DOCK.open, 300, 0.7));
  return (
    <div style={{ position: "absolute", inset: 0, background: WALL1 }}>
      <Win r={{ x: 136, y: 118, w: 786, h: 609 }}><DocLines /></Win>
      <div style={{ position: "absolute", left: 393, top: 137, width: 726, height: 589, transformOrigin: "50% 100%", transform: `scale(${lerp(0.6, 1, o)})`, opacity: clamp(o * 2) }}>
        <Win r={{ x: 0, y: 0, w: 726, h: 589 }} bar="#F6EFD9">
          <div style={{ padding: "30px 44px", fontSize: 40, fontWeight: 600, color: C.ink }}>
            Notes
            <i style={{ display: "block", height: 14, width: "100%", borderRadius: 8, background: "rgba(26,26,26,0.12)", marginTop: 28 }} />
            <i style={{ display: "block", height: 14, width: "80%", borderRadius: 8, background: "rgba(26,26,26,0.12)", marginTop: 22 }} />
            <i style={{ display: "block", height: 14, width: "90%", borderRadius: 8, background: "rgba(26,26,26,0.12)", marginTop: 22 }} />
          </div>
        </Win>
      </div>
      <MenuBar />
      <MacDock running={{ finder: true, web: true, music: true, notes: k >= DOCK.tapNotes + 2 }} bounce={{ notes: dockBounce(k, DOCK.tapNotes + 2) }} />
    </div>
  );
};

/* ---------------- Keys (portrait 402 x 874) ---------------- */
export const KEYS = { start: 28, phrase: "See you at three" };
const typedAt = (k: number) => {
  let t = KEYS.start, n = 0;
  for (const ch of KEYS.phrase) { if (k < t) break; n++; t += ch === " " ? 7 : 4.5; }
  return n;
};
export const keysTimes = () => { const out: number[] = []; let t = KEYS.start; for (const ch of KEYS.phrase) { out.push(Math.round(t)); t += ch === " " ? 7 : 4.5; } return out; };
export const KeysScreen: React.FC<{ k: number }> = ({ k }) => {
  const n = typedAt(k);
  const txt = KEYS.phrase.slice(0, n);
  const hit = n > 0 && k < keysTimes()[n - 1] + 4 ? KEYS.phrase[n - 1].toUpperCase() : "";
  const row = (top: number, items: React.ReactNode[], h: number, r: number, fs: number) => (
    <div style={{ position: "absolute", left: 12, right: 12, top, display: "flex", gap: 8 }}>
      {items.map((it, i) => <span key={i} style={{ flex: 1, height: h, borderRadius: r, display: "grid", placeItems: "center", background: C.raised, boxShadow: "0 0 0 1px rgba(26,26,26,0.07)", fontSize: fs, textAlign: "center", lineHeight: 1.1 }}>{it}</span>)}
    </div>
  );
  const sc = (a: string, b: string) => <span>{a}<small style={{ display: "block", fontSize: 9, color: "rgba(26,26,26,0.52)" }}>{b}</small></span>;
  const key = (c: string, w?: number, bg?: string, fs = 19) => (
    <span key={c + (w ?? "")} style={{ width: w ?? 33, height: 42, borderRadius: 6, background: c === hit ? "#ADB0B8" : bg ?? "#FDFDFD", boxShadow: "0 1px 0 rgba(0,0,0,0.25)", display: "grid", placeItems: "center", fontSize: fs }}>{c === "SP" ? "" : c}</span>
  );
  return (
    <div style={pt}>
      <StatusDot />
      <div style={{ position: "absolute", left: 24, right: 24, top: 200, textAlign: "center", fontSize: 24, color: n ? C.ink : "rgba(26,26,26,0.45)" }}>{n ? txt : "Start typing"}</div>
      <div style={{ position: "absolute", left: 0, right: 0, top: 252, textAlign: "center", fontSize: 12, color: "rgba(26,26,26,0.52)" }}>Text goes straight to your Mac</div>
      {row(300, ["⌘", "⌥", "⌃", "⇧"], 46, 23, 18)}
      {row(360, [sc("⌘C", "Copy"), sc("⌘V", "Paste"), sc("⌘X", "Cut"), sc("⌘Z", "Undo"), sc("⇧⌘Z", "Redo")], 54, 27, 12)}
      {row(428, ["esc", "tab", "⌫", "←", "↑ ↓", "→"], 74, 22, 14)}
      <div style={{ position: "absolute", left: 0, right: 0, bottom: 0, height: 330, background: "#D5D6DA", padding: "44px 4px 0", display: "flex", flexDirection: "column", gap: 12 }}>
        <div style={{ display: "flex", justifyContent: "center", gap: 6 }}>{[..."QWERTYUIOP"].map((c) => key(c))}</div>
        <div style={{ display: "flex", justifyContent: "center", gap: 6 }}>{[..."ASDFGHJKL"].map((c) => key(c))}</div>
        <div style={{ display: "flex", justifyContent: "center", gap: 6 }}>{key("⇧", 46, "#ADB0B8", 15)}{[..."ZXCVBNM"].map((c) => key(c))}{key("⌫", 46, "#ADB0B8", 15)}</div>
        <div style={{ display: "flex", justifyContent: "center", gap: 6 }}>{key("123", 46, "#ADB0B8", 15)}<span style={{ flex: 1, maxWidth: 190, height: 42, borderRadius: 6, background: hit === " " ? "#ADB0B8" : "#FDFDFD", boxShadow: "0 1px 0 rgba(0,0,0,0.25)" }} />{key("⏎", 46, "#ADB0B8", 15)}</div>
      </div>
    </div>
  );
};
export const KeysMac: React.FC<{ k: number }> = ({ k }) => {
  const n = typedAt(k);
  const caret = Math.floor(k / 30) % 2 === 0 || (n > 0 && n < KEYS.phrase.length);
  return (
    <div style={{ position: "absolute", inset: 0, background: WALL1 }}>
      <Win r={{ x: 212, y: 157, w: 937, h: 589 }}>
        <div style={{ padding: "44px 56px", fontFamily: FONT, fontSize: 52, fontWeight: 500, letterSpacing: "-0.02em", color: C.ink }}>
          {KEYS.phrase.slice(0, n)}
          <span style={{ display: "inline-block", width: 4, height: 56, background: C.ink, verticalAlign: -8, marginLeft: 3, opacity: caret ? 1 : 0 }} />
        </div>
      </Win>
      <MenuBar />
    </div>
  );
};

/* ---------------- Media ---------------- */
export const MEDIA = { touch: 40, dragStart: 46, dragEnd: 100, hudOff: 140 };
const volAt = (k: number) => lerp(56, 84, minJerk((k - MEDIA.dragStart) / (MEDIA.dragEnd - MEDIA.dragStart)));
const NOTE = '<path d="M10 17V6.5l8-1.8V15"/><circle cx="8" cy="17" r="2"/><circle cx="16" cy="15" r="2"/>';
export const MediaScreen: React.FC<{ k: number }> = ({ k }) => {
  const v = volAt(k);
  const prog0 = 38 + k * 0.012;
  const bar = (top: number, val: number, knob: boolean, left = 60, right = 60) => (
    <div style={{ position: "absolute", left, right, top, height: 4, borderRadius: 2, background: "rgba(26,26,26,0.1)" }}>
      <i style={{ position: "absolute", left: 0, top: 0, bottom: 0, width: `${val}%`, borderRadius: 2, background: C.ink }} />
      {knob && <b style={{ position: "absolute", top: "50%", left: `${val}%`, width: 30, height: 20, margin: "-10px 0 0 -15px", borderRadius: 10, background: "#fff", boxShadow: "0 0 0 1px rgba(26,26,26,0.16)" }} />}
    </div>
  );
  const kx = 60 + (v / 100) * 282;
  const fx = k >= MEDIA.touch - 9 && k <= MEDIA.dragEnd + 22 ? (() => {
    const tin = minJerk((k - (MEDIA.touch - 9)) / 8), tl = minJerk((k - (MEDIA.dragEnd + 8)) / 13);
    return [{ x: kx, y: 702, o: tin * (1 - tl), s: lerp(0.7, 1, tin) * lerp(1, 1.12, tl) }];
  })() : [];
  return (
    <div style={pt}>
      <StatusDot />
      <div style={{ position: "absolute", left: 50, top: 120, width: 302, height: 302, borderRadius: 22, background: "#A9A6A0", display: "grid", placeItems: "center" }}>
        <Icon d={NOTE} size={96} color="rgba(255,255,255,0.92)" sw={1.4} />
      </div>
      <div style={{ position: "absolute", left: 0, right: 0, top: 448, textAlign: "center", fontSize: 17, fontWeight: 600 }}>Track title</div>
      <div style={{ position: "absolute", left: 0, right: 0, top: 472, textAlign: "center", fontSize: 14, color: "rgba(26,26,26,0.52)" }}>Artist</div>
      {bar(506, prog0, false, 22, 22)}
      <div style={{ position: "absolute", left: 22, right: 22, top: 520, display: "flex", justifyContent: "space-between", fontSize: 10, color: "rgba(26,26,26,0.52)", fontVariantNumeric: "tabular-nums" }}><span>1:16</span><span>-2:48</span></div>
      <div style={{ position: "absolute", left: 50, right: 50, top: 570, display: "flex", justifyContent: "space-between", alignItems: "center" }}>
        <svg width="46" height="30" viewBox="0 0 46 30" fill={C.ink}><path d="M22 3 4 15l18 12ZM42 3 24 15l18 12Z" /></svg>
        <svg width="36" height="40" viewBox="0 0 36 40" fill={C.ink}><rect x="6" y="3" width="8" height="34" rx="2" /><rect x="22" y="3" width="8" height="34" rx="2" /></svg>
        <svg width="46" height="30" viewBox="0 0 46 30" fill={C.ink}><path d="M4 3l18 12L4 27ZM24 3l18 12-18 12Z" /></svg>
      </div>
      <Icon d={GL.speaker} size={16} color="rgba(26,26,26,0.5)" style={{ position: "absolute", left: 30, top: 694 }} />
      {bar(700, v, true)}
      <Icon d={GL.sun} size={16} color="rgba(26,26,26,0.5)" style={{ position: "absolute", left: 30, top: 736 }} />
      {bar(742, 74, true)}
      <Dots fingers={fx} size={46} />
    </div>
  );
};
export const MediaMac: React.FC<{ k: number }> = ({ k }) => {
  const v = volAt(k);
  const hud = clamp(snappy(k, MEDIA.touch)) * (1 - clamp(spring(k, MEDIA.hudOff, 300, 1)));
  return (
    <div style={{ position: "absolute", inset: 0, background: WALL1, fontFamily: FONT }}>
      <div style={{ position: "absolute", left: "50%", top: "44%", width: 846, transform: "translate(-50%, -50%)", padding: 40, display: "flex", gap: 44, alignItems: "center", borderRadius: 30, background: C.surface, boxShadow: "0 0 0 1px rgba(26,26,26,0.1)" }}>
        <div style={{ width: 176, height: 176, borderRadius: 20, background: "#A9A6A0", display: "grid", placeItems: "center", flex: "none" }}><Icon d={NOTE} size={60} color="rgba(255,255,255,0.92)" sw={1.4} /></div>
        <div style={{ flex: 1 }}>
          <b style={{ display: "block", fontSize: 44, letterSpacing: "-0.02em" }}>Track title</b>
          <span style={{ fontSize: 34, color: "rgba(26,26,26,0.55)" }}>Artist</span>
          <div style={{ marginTop: 26, height: 10, borderRadius: 5, background: "rgba(26,26,26,0.12)", overflow: "hidden" }}><i style={{ display: "block", height: "100%", width: `${38 + k * 0.012}%`, background: C.ink }} /></div>
        </div>
      </div>
      <div style={{ position: "absolute", left: "50%", bottom: 120, width: 400, padding: "26px 30px", transform: `translateX(-50%) scale(${lerp(0.9, 1, hud)})`, opacity: clamp(hud), borderRadius: 26, background: "rgba(250,249,247,0.92)", boxShadow: "0 0 0 1px rgba(26,26,26,0.08)", display: "flex", alignItems: "center", gap: 22 }}>
        <Icon d={GL.speaker} size={46} color={C.ink} sw={1.8} />
        <div style={{ flex: 1, height: 12, borderRadius: 6, background: "rgba(26,26,26,0.15)", overflow: "hidden" }}><i style={{ display: "block", height: "100%", width: `${v}%`, background: C.ink }} /></div>
      </div>
      <MenuBar />
    </div>
  );
};

/* ---------------- Deck ---------------- */
export const DECK = { tap: 52 };
const DECK_BTNS: [string, string][] = [["Safari", GL.compass], ["Screenshot", GL.camera], ["Do Not Disturb", GL.moon], ["GitHub", GL.link], ["Lock Screen", GL.lock], ["Build", GL.hammer]];
const tileGrid = (top: number) => (i: number): [number, number] => {
  const w = (402 - 28 - 24) / 3;
  return [14 + (i % 3) * (w + 12) + w / 2, top + Math.floor(i / 3) * 116 + 52];
};
const Tile: React.FC<{ label: string; glyph: string; color: string; s?: number; ok?: number; style?: React.CSSProperties }> = ({ label, glyph, color, s = 1, ok = 0, style }) => (
  <div style={{ ...raised, height: 104, display: "flex", flexDirection: "column", alignItems: "center", justifyContent: "center", gap: 10, padding: 8, fontSize: 13, fontWeight: 500, textAlign: "center", lineHeight: 1.2, position: "relative", transform: `scale(${s})`, ...style }}>
    <Icon d={glyph} size={26} color={color} sw={1.7} />
    <span>{label}</span>
    <i style={{ position: "absolute", right: 8, top: 8, width: 18, height: 18, borderRadius: 9, background: C.green, opacity: clamp(ok * 2), transform: `scale(${lerp(0.4, 1, clamp(ok))})`, display: "grid", placeItems: "center" }}>
      <Icon d={GL.check} size={12} color="#fff" sw={2.6} />
    </i>
  </div>
);
export const DeckScreen: React.FC<{ k: number }> = ({ k }) => {
  const [x, y] = tileGrid(96)(2);
  const ok = clamp(snappy(k, DECK.tap + 6)) * (1 - prog(k, DECK.tap + 80, 14));
  return (
    <div style={pt}>
      <StatusDot />
      <div style={{ position: "absolute", left: 14, right: 14, top: 96, display: "grid", gridTemplateColumns: "repeat(3, 1fr)", gap: 12 }}>
        {DECK_BTNS.map(([n, g]) => <Tile key={n} label={n} glyph={g} color={MODE_ACCENT.deck} s={n === "Do Not Disturb" ? press(k, DECK.tap) : 1} ok={n === "Do Not Disturb" ? ok : 0} />)}
      </div>
      <Fx fx={[tapFx(k, DECK.tap, x, y)]} />
    </div>
  );
};
export const DeckMac: React.FC<{ k: number }> = ({ k }) => {
  const m = clamp(snappy(k, DECK.tap + 4));
  return (
    <div style={{ position: "absolute", inset: 0, background: WALL1 }}>
      <Win r={{ x: 136, y: 118, w: 786, h: 609 }}><DocLines /></Win>
      <Win r={{ x: 605, y: 206, w: 696, h: 550 }} active={false} z={0}><DocLines /></Win>
      <MenuBar extra={<span style={{ width: 30, height: 30, opacity: m, transform: `scale(${lerp(0.4, 1, m)})` }}><Icon d={GL.moon} size={30} color={C.ink} sw={2.2} /></span>} />
    </div>
  );
};

/* ---------------- Macros: per-app button sets ---------------- */
export const MACROS = { tap: 40, switchApp: 92 };
const SAFARI_SET: [string, string, string][] = [["New Private Window", GL.window, "#3D7BF2"], ["Reopen Closed Tab", GL.undo, "#3D7BF2"], ["Reader Mode", GL.reader, "#E8930C"], ["Save to Notes", GL.note, "#D9A400"], ["Show Downloads", GL.down, "#2E9E5B"]];
const XCODE_SET: [string, string, string][] = [["Build", GL.hammer, "#3D7BF2"], ["Run", GL.play, "#3D7BF2"], ["Stop", GL.stop, "#3D7BF2"], ["Test", GL.test, "#12A594"], ["Clean Build Folder", GL.broom, "#E8930C"], ["Open Quickly", GL.search, "#12A594"]];
export const MacrosScreen: React.FC<{ k: number }> = ({ k }) => {
  const [x, y] = tileGrid(150)(1);
  const sw = k - MACROS.switchApp - 6;
  const xcode = sw >= 0;
  const set = xcode ? XCODE_SET : SAFARI_SET;
  return (
    <div style={pt}>
      <StatusDot />
      <div style={{ position: "absolute", left: 14, right: 14, top: 96, height: 34, borderRadius: 17, background: "rgba(26,26,26,0.06)", display: "flex", padding: 2, fontSize: 13, fontWeight: 600 }}>
        <span style={{ flex: 1, display: "grid", placeItems: "center", borderRadius: 15, background: "#fff", boxShadow: "0 0 0 1px rgba(26,26,26,0.06)", overflow: "hidden", position: "relative" }}>
          <span style={{ position: "absolute", transform: `translateY(${-clamp(spring(sw, 0, 300, 0.9)) * 170}%)` }}>For Safari</span>
          <span style={{ position: "absolute", transform: `translateY(${(1 - clamp(spring(sw, 0, 300, 0.9))) * 170}%)` }}>For Xcode</span>
        </span>
        <span style={{ flex: 1, display: "grid", placeItems: "center", color: "rgba(26,26,26,0.7)" }}>All</span>
      </div>
      <div style={{ position: "absolute", left: 14, right: 14, top: 150, display: "grid", gridTemplateColumns: "repeat(3, 1fr)", gap: 12 }}>
        {set.map(([n, g, c], i) => {
          const e = xcode ? clamp(spring(sw, i * 3, 300, 0.75)) : 1;
          return <Tile key={n} label={n} glyph={g} color={c} s={(n === "Reopen Closed Tab" ? press(k, MACROS.tap) : 1) * lerp(0.86, 1, e)} style={{ opacity: e }} />;
        })}
      </div>
      <div style={{ ...raised, position: "absolute", left: "50%", bottom: 52, transform: "translateX(-50%)", height: 50, padding: "0 28px", borderRadius: 25, display: "flex", alignItems: "center", gap: 10, color: "#E5484D", fontWeight: 600, fontSize: 17 }}>
        <i style={{ width: 16, height: 16, borderRadius: 8, boxShadow: "inset 0 0 0 2px #E5484D", display: "grid", placeItems: "center" }}><i style={{ width: 8, height: 8, borderRadius: 4, background: "#E5484D" }} /></i>Record
      </div>
      <Fx fx={[tapFx(k, MACROS.tap, x, y)]} />
    </div>
  );
};
export const MacrosMac: React.FC<{ k: number }> = ({ k }) => {
  const tabIn = clamp(spring(k, MACROS.tap + 3, 300, 0.75));
  const xo = clamp(spring(k, MACROS.switchApp, 260, 1));
  const tab = (on: boolean, extra?: React.CSSProperties) => <span style={{ width: 210, height: 34, borderRadius: 10, background: on ? "#FBFBF9" : "#DDDAD4", ...extra }} />;
  return (
    <div style={{ position: "absolute", inset: 0, background: WALL1 }}>
      <Win r={{ x: 120, y: 110, w: 1270, h: 726 }} titleBar={<div style={{ display: "flex", gap: 10, alignItems: "center" }}>{tab(false)}{tab(tabIn < 0.5)}<span style={{ width: 210 * tabIn, height: 34, borderRadius: 10, background: "#FBFBF9", opacity: tabIn, transformOrigin: "0 50%" }} /></div>}>
        <DocLines />
      </Win>
      <div style={{ position: "absolute", inset: 0, opacity: xo }}>
        <Win r={{ x: 170, y: 140, w: 1170, h: 690 }} bg="#1E1E1E" bar="#2B2B2B" dark>
          <div style={{ padding: "34px 40px" }}>
            {[[0, 40, "#E5484D"], [1, 62, "rgba(255,255,255,0.3)"], [1, 48, "rgba(255,255,255,0.3)"], [2, 36, "#8A63E8"], [2, 58, "rgba(255,255,255,0.3)"], [1, 30, "rgba(255,255,255,0.3)"], [0, 18, "rgba(255,255,255,0.3)"], [0, 44, "#61C454"], [1, 52, "rgba(255,255,255,0.3)"], [1, 40, "rgba(255,255,255,0.3)"], [0, 14, "rgba(255,255,255,0.3)"]].map(([ind, w, c], i) => (
              <i key={i} style={{ display: "block", marginLeft: (ind as number) * 40, width: `${w}%`, height: 14, borderRadius: 7, background: c as string, marginBottom: 24 }} />
            ))}
          </div>
        </Win>
      </div>
      <MenuBar />
      <MacDock running={{ finder: true, web: true }} />
    </div>
  );
};

/* ---------------- Clipboard ---------------- */
export const CLIP = { tap: 46 };
const CLIP_TEXT = "Dinner on Friday at seven, table for four.";
export const ClipboardScreen: React.FC<{ k: number }> = ({ k }) => {
  const c = clamp(spring(k, CLIP.tap + 6, 300, 0.85));
  const card = (top: number, glyph: string, title: string, body: string, btn: React.ReactNode, extra?: React.ReactNode) => (
    <div style={{ ...raised, position: "absolute", left: 14, right: 14, top, padding: 18 }}>
      <h4 style={{ margin: 0, fontSize: 16, fontWeight: 600, display: "flex", gap: 12, alignItems: "center" }}><Icon d={glyph} size={22} color="rgba(26,26,26,0.6)" sw={1.5} />{title}</h4>
      <p style={{ margin: "4px 0 0 34px", fontSize: 13, color: "rgba(26,26,26,0.52)", lineHeight: 1.35 }}>{body}</p>
      {btn}
      {extra}
    </div>
  );
  const gbtn = (solid: boolean, label: string, s = 1) => (
    <span style={{ display: "inline-flex", alignItems: "center", gap: 6, height: 34, padding: "0 16px", borderRadius: 17, marginTop: 14, fontSize: 15, fontWeight: 500, background: solid ? "#2E9E5B" : "rgba(46,158,91,0.16)", color: solid ? "#fff" : "rgba(46,158,91,0.6)", transform: `scale(${s})` }}>{label}</span>
  );
  return (
    <div style={pt}>
      <StatusDot />
      {card(96, GL.toMac, "To your Mac", "Text or an image copied on this iPhone.", gbtn(false, "Paste"), <p style={{ margin: "12px 0 0", fontSize: 11, color: "rgba(26,26,26,0.45)" }}>Copy something on this iPhone first, then tap Paste.</p>)}
      {card(290, GL.fromMac, "From your Mac", "Copies what is on the Mac clipboard to this iPhone.", gbtn(true, "Get Mac clipboard", press(k, CLIP.tap)),
        <div style={{ marginTop: 14 * c, maxHeight: 70 * c, overflow: "hidden", padding: `${12 * c}px 14px`, borderRadius: 14, background: "rgba(26,26,26,0.04)", fontSize: 14, opacity: c, transform: `translateY(${(1 - c) * 6}px)` }}>{CLIP_TEXT}</div>)}
      <Fx fx={[tapFx(k, CLIP.tap, 98, 290 + 18 + 22 + 4 + 36 + 14 + 17 + 4)]} />
    </div>
  );
};
export const ClipboardMac: React.FC<{ k: number }> = ({ k }) => (
  <div style={{ position: "absolute", inset: 0, background: WALL1 }}>
    <Win r={{ x: 181, y: 147, w: 998, h: 609 }} bar="#F6EFD9">
      <div style={{ padding: "40px 52px", fontFamily: FONT, fontSize: 40, lineHeight: 1.5, color: C.ink, letterSpacing: "-0.01em" }}>
        <b style={{ fontWeight: 600 }}>Plans</b>
        <br />
        <span style={{ background: "rgba(61,123,242,0.24)", borderRadius: 6 }}>{CLIP_TEXT}</span>
        <br />
        Bring the photos.
      </div>
    </Win>
    <MenuBar />
    <Cursor x={760} y={560} />
  </div>
);
void DISP_W; void DISP_H;

/* ---------------- Present ---------------- */
export const PRESENT = { next: 36, padDown: 78, padEnd: 138 };
export const PresentScreen: React.FC<{ k: number }> = ({ k }) => {
  const secs = Math.max(0, Math.floor((k - 6) / 60));
  const padC: [number, number] = [201, 262];
  const lu = minJerk((k - PRESENT.padDown - 4) / (PRESENT.padEnd - PRESENT.padDown - 4));
  const lx = padC[0] - 90 + 180 * lu, ly = padC[1] + 40 - Math.sin(Math.PI * lu) * 80;
  const pf: Finger[] = [];
  if (k >= PRESENT.padDown - 6 && k <= PRESENT.padEnd + 14) {
    const tin = minJerk((k - (PRESENT.padDown - 6)) / 8), tl = minJerk((k - PRESENT.padEnd) / 13);
    pf.push({ x: lx, y: ly, o: tin * (1 - tl), s: lerp(0.7, 1, tin) * lerp(1, 1.12, tl) });
  }
  return (
    <div style={pt}>
      <StatusDot />
      <div style={{ position: "absolute", left: 14, top: 88, fontSize: 34, fontWeight: 300, color: "rgba(26,26,26,0.55)", fontVariantNumeric: "tabular-nums" }}>0:{String(secs).padStart(2, "0")}</div>
      <span style={{ ...raised, position: "absolute", top: 92, right: 60, width: 36, height: 36, borderRadius: 18, display: "grid", placeItems: "center" }}><Icon d={GL.rotate} size={16} color="#888" sw={2} /></span>
      <span style={{ position: "absolute", top: 92, right: 14, width: 36, height: 36, borderRadius: 18, display: "grid", placeItems: "center", background: MODE_ACCENT.present }}><svg viewBox="0 0 14 14" width={14} height={14}><path d="M3 1.5v11l9-5.5Z" fill="#fff" /></svg></span>
      <div style={{ ...raised, position: "absolute", left: 12, right: 12, top: 148, height: 228, display: "grid", placeItems: "center", textAlign: "center", fontSize: 13, color: "rgba(26,26,26,0.52)" }}>
        <div><Icon d={GL.wave} size={22} color={MODE_ACCENT.present} style={{ margin: "0 auto 6px" }} />Touch and hold to point</div>
      </div>
      <div style={{ ...raised, position: "absolute", left: 12, top: 392, bottom: 44, width: 98, display: "grid", placeItems: "center" }}><Icon d='<path d="m15 5-7 7 7 7"/>' size={34} color={C.ink} sw={2.4} /></div>
      <div style={{ position: "absolute", left: 120, right: 12, top: 392, bottom: 44, borderRadius: 26, background: MODE_ACCENT.present, color: "#fff", display: "grid", placeItems: "center", textAlign: "center", fontWeight: 600, fontSize: 17, transform: `scale(${press(k, PRESENT.next)})` }}>
        <div><Icon d='<path d="m9 5 7 7-7 7"/>' size={34} color="#fff" sw={2.4} style={{ margin: "0 auto 4px" }} />Next</div>
      </div>
      <Fx fx={[tapFx(k, PRESENT.next, 261, 610)]} />
      <Dots fingers={pf} size={46} />
    </div>
  );
};
export const PresentMac: React.FC<{ k: number }> = ({ k }) => {
  const s2 = k >= PRESENT.next + 2;
  const sl = clamp(spring(k, PRESENT.next + 2, 300, 1));
  const lu = minJerk((k - PRESENT.padDown - 4) / (PRESENT.padEnd - PRESENT.padDown - 4));
  const laserO = k >= PRESENT.padDown && k <= PRESENT.padEnd + 10 ? clamp((k - PRESENT.padDown) / 6) * (1 - clamp((k - PRESENT.padEnd) / 10)) : 0;
  return (
    <div style={{ position: "absolute", inset: 0, background: "#FBFBF9", fontFamily: FONT }}>
      <div style={{ position: "absolute", inset: 0, display: "flex", flexDirection: "column", justifyContent: "center", padding: "0 180px", gap: 40, opacity: s2 ? lerp(0.3, 1, sl) : 1, transform: s2 ? `translateX(${(1 - sl) * 40}px)` : undefined }}>
        <i style={{ display: "block", height: 70, width: s2 ? "48%" : "60%", borderRadius: 20, background: C.ink }} />
        <i style={{ display: "block", height: 28, width: "100%", borderRadius: 16, background: "rgba(26,26,26,0.14)" }} />
        <i style={{ display: "block", height: 28, width: s2 ? "70%" : "80%", borderRadius: 16, background: "rgba(26,26,26,0.14)" }} />
        <i style={{ display: "block", height: 28, width: s2 ? "84%" : "64%", borderRadius: 16, background: "rgba(26,26,26,0.14)" }} />
      </div>
      <span style={{ position: "absolute", right: 60, bottom: 50, fontSize: 40, color: "rgba(26,26,26,0.4)", fontVariantNumeric: "tabular-nums" }}>{s2 ? 2 : 1}</span>
      <i style={{ position: "absolute", left: 0, top: 0, width: 40, height: 40, borderRadius: 20, background: MODE_ACCENT.present, opacity: laserO * 0.9, transform: `translate(${DISP_W * (0.25 + 0.5 * lu) - 20}px, ${DISP_H * (0.62 - Math.sin(Math.PI * lu) * 0.3) - 20}px)` }} />
    </div>
  );
};

export const MODE_LIST = [
  { key: "dock", land: true, Phone: DockScreen, Mac: DockMac, title: "Dock", sub: "Open or switch Mac apps." },
  { key: "keys", Phone: KeysScreen, Mac: KeysMac, title: "Keys", sub: "Type and dictate on the phone." },
  { key: "media", Phone: MediaScreen, Mac: MediaMac, title: "Media", sub: "Now playing, volume and brightness." },
  { key: "deck", Phone: DeckScreen, Mac: DeckMac, title: "Deck", sub: "Your own buttons: apps, links, Shortcuts, keystrokes and scripts." },
  { key: "macros", Phone: MacrosScreen, Mac: MacrosMac, title: "Macros", sub: "Record and replay. The buttons follow the app in front." },
  { key: "clipboard", Phone: ClipboardScreen, Mac: ClipboardMac, title: "Clipboard", sub: "Copy between phone and Mac." },
  { key: "present", Phone: PresentScreen, Mac: PresentMac, title: "Present", sub: "Next, previous, a timer and a laser dot." },
] as const;
