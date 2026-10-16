import React from "react";
import { AppIcon, BlurX, Finger, Front, Glyph, Ring, Tile } from "../parts";
import { ModeMenu, Pill, menuTileAt, SAFARI, PINNED, SiteLogo } from "../screens";
import { APPS } from "../site/apps";
import { clamp, E, INOUT, K, lerp, SP, TAP } from "../kit";
import { sceneSec, word } from "../timeline";

/* The phone during Modes (scene 5, upright) and Layouts (scene 6, sideways), and what each
   does on the Mac. Times are film seconds. */

const M = sceneSec("modes"), L = sceneSec("layouts"), R = sceneSec("remote");
export const MT = {
  pill: M + 0.55, keys: M + word("modes", "touch"),
  type0: M + 2.25, type1: M + 3.35,
  toMedia: M + 3.6, scrub: [M + 4.15, M + 4.85] as const,
  toDock: M + 5.2, mail: M + 5.75,
  toClip: M + 6.6, paste: M + 7.15,
};
export const LT = {
  split: L + 0.75, third: L + word("layouts", "three") - 0.15,
  drag: [L + 2.45, L + 3.15] as const, snap: L + 3.2,
  couch: L + 3.75, grow: [R - 0.62, R] as const,
};
export const MODES_CUES = () => ({
  tap: [MT.pill, MT.keys, MT.mail, MT.paste],
  key: Array.from({ length: 16 }, (_, i) => MT.type0 + i * ((MT.type1 - MT.type0) / 16)),
  swipe: [[MT.toMedia, MT.toMedia + 0.4], [MT.toDock, MT.toDock + 0.4], [MT.toClip, MT.toClip + 0.4]] as [number, number][],
  drag: [[MT.scrub[0], MT.scrub[1]], [LT.drag[0], LT.drag[1]]] as [number, number][],
  click: [LT.snap],
  whoosh: [LT.split, LT.third, LT.grow[0] + 0.2],
});

const PHRASE = "See you at three";
const PASTED = "See you at the station at nine.";
/** What the modes do on the Mac at time t. */
export function modesEvents(t: number) {
  const typedN = Math.floor(clamp((t - MT.type0) / (MT.type1 - MT.type0)) * PHRASE.length + 0.0001);
  const pasted = t > MT.paste + 0.12;
  const notesFront = t < MT.toMedia + 0.2 || t > MT.paste + 0.05;
  const music = E(t, MT.toMedia + 0.15, 0.55);
  const mail = E(t, MT.mail + 0.35, 0.55);
  const front = t > MT.paste + 0.05 ? "Notes" : t > MT.mail + 0.3 ? "Mail" : t > MT.toMedia + 0.15 ? "Music" : "Notes";
  const caps: [string, string, number, number][] = [
    ["Keyboard", "#5E5CE6", MT.keys + 0.1, MT.toMedia], ["Media", "#FF375F", MT.toMedia + 0.15, MT.toDock],
    ["Dock", "#0A84FF", MT.toDock + 0.15, MT.toClip], ["Clipboard", "#30D158", MT.toClip + 0.15, L - 0.15],
  ];
  const c = caps.find(([, , a, b]) => t >= a - 0.05 && t < b + 0.4);
  return {
    on: t > MT.keys,
    notes: t < MT.keys + 0.1 ? 0 : E(t, MT.keys + 0.1, 0.55),
    typed: PHRASE.slice(0, typedN),
    pasted: pasted ? PASTED : "",
    caret: true,
    notesZ: notesFront ? 12 : 10,
    music, musicFront: front === "Music", prog: lerp(0.31, 0.6, E(t, MT.scrub[0] + 0.05, MT.scrub[1] - MT.scrub[0], INOUT)),
    musicBounce: (t - (MT.toMedia + 0.02)) / 0.9,
    mail, mailFront: front === "Mail", mailBounce: (t - (MT.mail + 0.05)) / 0.9,
    app: t > MT.keys + 0.1 && t < L + 0.5 ? front : undefined,
    caption: c ? { text: c[0], color: c[1], p: E(t, c[2], 0.5), q: E(t, c[3], 0.3) } : undefined,
  };
}

/* ---------- upright screens (402 x 874 points), from the site's drawings of the app ---------- */
const KB = ["QWERTYUIOP", "ASDFGHJKL", "ZXCVBNM"];
const Keys: React.FC<{ t: number }> = ({ t }) => {
  const n = Math.floor(clamp((t - MT.type0) / (MT.type1 - MT.type0)) * PHRASE.length + 0.0001);
  const live = t >= MT.type0 && t < MT.type1 + 0.08;
  const per = (MT.type1 - MT.type0) / PHRASE.length;
  const hitOn = live && ((t - MT.type0) % per) < per * 0.6;
  const ch = live ? PHRASE[Math.min(PHRASE.length - 1, n)].toUpperCase() : "";
  const k = (c: string) => <span key={c} className={hitOn && c === ch ? "hit" : ""}>{c}</span>;
  return (
    <div className="u-keys" style={{ position: "absolute", inset: 0 }}>
      <span className="status-dot" />
      <div className={`echo${n > 0 ? " typed" : ""}`}>{n > 0 ? PHRASE.slice(0, n) : "Start typing"}</div>
      <div className="sub">Typing goes straight to your Mac</div>
      <div className="k-mods">{[["⌃", "control"], ["⌥", "option"], ["⌘", "command"], ["⇧", "shift"], ["fn", ""]].map(([a, b]) => <span key={a}><b>{a}</b>{b ? <small>{b}</small> : null}</span>)}</div>
      <div className="k-sc">{[["Copy", "⌘C"], ["Paste", "⌘V"], ["Cut", "⌘X"], ["Undo", "⌘Z"], ["Redo", "⇧⌘Z"]].map(([a, b]) => <span key={a}>{a}<small>{b}</small></span>)}</div>
      <div className="k-nav"><span style={{ gridArea: "1/1" }}>esc</span><span style={{ gridArea: "1/2" }}>tab</span><span style={{ gridArea: "1/4" }}>↑</span><span style={{ gridArea: "2/1/3/3" }}>⌫</span><span style={{ gridArea: "2/3" }}>←</span><span style={{ gridArea: "2/4" }}>↓</span><span style={{ gridArea: "2/5" }}>→</span></div>
      <div className="u-kb">
        <div>{[...KB[0]].map(k)}</div><div>{[...KB[1]].map(k)}</div>
        <div><span className="w">⇧</span>{[...KB[2]].map(k)}<span className="w">⌫</span></div>
        <div className="kb-b"><span className="w">123</span><span className={`sp${hitOn && ch === " " ? " hit" : ""}`}>space</span><span className="w">return</span></div>
      </div>
    </div>
  );
};
const fmt = (s: number) => `${Math.floor(s / 60)}:${String(Math.floor(s % 60)).padStart(2, "0")}`;
const Media: React.FC<{ t: number }> = ({ t }) => {
  const p = modesEvents(t).prog, total = 244, pos = p * total;
  const held = E(t, MT.scrub[0] - 0.1, 0.15) * (1 - E(t, MT.scrub[1], 0.2));
  return (
    <div className="u-media" style={{ position: "absolute", inset: 0 }}>
      <span className="status-dot" />
      <div className="art"><i className="a1" /><i className="a2" /><i className="a3" /></div>
      <div className="src"><i />SPOTIFY</div><div className="t">Slow Light</div><div className="a">Paper Rooms · Glass Hours</div>
      <div className="scrub"><i className="prog" style={{ width: `${p * 100}%` }} /><b className="knob" style={{ left: `${p * 100}%`, transform: `scale(${1 + 0.6 * held})` }} /></div>
      <div className="times"><span>{fmt(pos)}</span><span>-{fmt(total - pos)}</span></div>
      <div className="ctl"><svg viewBox="0 0 46 30"><path d="M22 3 4 15l18 12ZM42 3 24 15l18 12Z" /></svg><span className="pp"><svg className="pause" viewBox="0 0 36 40"><rect x="5" y="3" width="9" height="34" rx="2" /><rect x="22" y="3" width="9" height="34" rx="2" /></svg></span><svg viewBox="0 0 46 30"><path d="M4 3l18 12L4 27ZM24 3l18 12-18 12Z" /></svg></div>
    </div>
  );
};
const DOCK: [string, boolean][] = [["finder", true], ["web", true], ["mail", false], ["msg", false], ["cal", false], ["notes", true], ["rem", false], ["music", true], ["photos", false], ["xcode", true], ["term", false], ["store", false], ["set", false]];
export const dockTileAt = (i: number): [number, number] => [10 + 95.5 * (i % 4) + 47.75, 236 + 102 * Math.floor(i / 4) + 30];
const DockScreen: React.FC<{ t: number; press: number }> = ({ t, press }) => {
  const mailOn = t > MT.mail + 0.1;
  return (
    <div className="u-apps" style={{ position: "absolute", inset: 0 }}>
      <span className="status-dot" />
      <div className="hd"><b>Dock</b><span className="sub">Your Mac · {mailOn ? 7 : 6} open</span></div>
      <div className="grid">{DOCK.map(([k, r]) => (
        <div key={k} className="at"><AppIcon k={k} style={k === "mail" ? { transform: `scale(${press})` } : undefined} /><i className={`run${r || (k === "mail" && mailOn) ? " on" : ""}`} /><span>{APPS[k][0]}</span></div>
      ))}</div>
    </div>
  );
};
const Clip: React.FC<{ t: number; press: number }> = ({ t, press }) => {
  const done = E(t, MT.paste + 0.08, 0.42);
  return (
    <div className="u-clip">
      <h4>Clipboard</h4>
      <div className="cc to">
        <div className="ch"><Glyph n="square.and.arrow.up" /><div><b>Send to Mac</b><span>Text or an image you copied on this iPhone.</span></div></div>
        <div className="pv" style={{ maxHeight: 40 * done, opacity: done, marginTop: 14 * done }}>{PASTED}</div>
        <div className="crow"><span className="cbtn paste" style={{ transform: `scale(${press})` }}><Glyph n="doc.on.clipboard" />Paste</span><span className="ok" style={{ opacity: done, transform: `translateX(${(1 - done) * -6}px)` }}><Glyph n="checkmark" />Sent</span></div>
      </div>
      <div className="cc from">
        <div className="ch"><Glyph n="square.and.arrow.down" /><div><b>Get from Mac</b><span>Whatever is copied on your Mac, copied here too.</span></div></div>
        <div className="crow"><span className="cbtn get"><Glyph n="square.and.arrow.down" />Get from Mac</span></div>
      </div>
    </div>
  );
};
/** Actions upright: the front app, then Pinned (ActionsMode.swift). */
const ActionsPort: React.FC = () => (
  <div className="fm-acl" style={{ background: "#F2F1EE" }}>
    <div style={{ position: "absolute", left: 16, right: 16, top: 112 }}>
      <Front k="fcp" name="Final Cut Pro" />
      <div className="ag" style={{ marginTop: 16 }}>{[["Blade at Playhead", "scissors"], ["Set Range Start", "arrow.right.to.line"], ["Set Range End", "arrow.left.to.line"], ["Connect Clip", "arrow.turn.right.up"], ["Append Clip", "text.append"], ["Detach Audio", "waveform"]].map(([n, g]) => <Tile key={n} name={n} g={g} c="#BF5AF2" />)}</div>
      <div className="ph5" style={{ marginTop: 14 }}>Pinned</div>
      <div className="ag" style={{ marginTop: 8 }}>{PINNED.map(([n, g, c]) => n === "Glasspad" ? <Tile key={n} name={n} c="#1A1A1A" icon={<SiteLogo />} /> : <Tile key={n} name={n} g={g} c={c} on={n === "Do Not Disturb"} />)}</div>
    </div>
  </div>
);

export const ModesPhone: React.FC<{ t: number }> = ({ t }) => {
  const pillTap = TAP(t, MT.pill), keyTap = TAP(t, MT.keys);
  const pillO = E(t, MT.pill - 0.45, 0.25);
  const menu = SP(t, MT.pill + 0.05, 0.38, 0.82) * (1 - E(t, MT.keys + 0.1, 0.18));
  const pageAt = (x: number) => K(x, [[MT.toMedia, 0], [MT.toMedia + 0.42, 1], [MT.toDock, 1], [MT.toDock + 0.42, 2], [MT.toClip, 2], [MT.toClip + 0.42, 3]], INOUT);
  const page = pageAt(t), pageV = (page - pageAt(t - 1 / 60)) * 402 * 0.85;
  const inModes = t > MT.keys + 0.1;
  const [kx, ky] = menuTileAt("Keyboard");
  const scrubO = E(t, MT.scrub[0] - 0.15, 0.15) * (1 - E(t, MT.scrub[1] + 0.05, 0.2));
  const sp = modesEvents(t).prog;
  const mailTap = TAP(t, MT.mail), pasteTap = TAP(t, MT.paste);
  const [dx, dy] = dockTileAt(2);
  const screens = [<Keys t={t} />, <Media t={t} />, <DockScreen t={t} press={mailTap.press} />, <Clip t={t} press={pasteTap.press} />];
  return (
    <div style={{ position: "absolute", inset: 0, background: "#F2F1EE", overflow: "hidden" }}>
      {!inModes || t < MT.keys + 0.4 ? <ActionsPort /> : null}
      {inModes ? <BlurX id="mb-modes" px={pageV}>{screens.map((s, i) => {
        const x = (i - page) * 402;
        if (Math.abs(x) >= 402) return null;
        return <div key={i} style={{ position: "absolute", inset: 0, transform: `translateX(${x}px)`, opacity: i === 0 ? E(t, MT.keys + 0.1, 0.25) : 1, background: "#F2F1EE" }}>{s}</div>;
      })}</BlurX> : null}
      <Pill name="Actions" g="bolt.fill.mode" color="#FF9F0A" o={inModes ? 1 - E(t, MT.keys + 0.1, 0.15) : Math.max(pillO, clamp(menu * 2))} s={pillTap.press} style={{ top: 62 }} />
      <ModeMenu p={menu} current="Actions" hit="Keyboard" press={keyTap.press} />
      <Finger x={201} y={82} o={pillTap.o} s={pillTap.s} /><Ring x={201} y={82} p={pillTap.ring} />
      <Finger x={kx} y={ky} o={keyTap.o} s={keyTap.s} /><Ring x={kx} y={ky} p={keyTap.ring} />
      {page > 0.9 && page < 1.1 ? <Finger x={30 + 342 * sp} y={503} o={scrubO} /> : null}
      {page > 1.9 && page < 2.1 ? <><Finger x={dx} y={dy} o={mailTap.o} s={mailTap.s} /><Ring x={dx} y={dy} p={mailTap.ring} /></> : null}
      {page > 2.9 ? <><Finger x={84} y={248} o={pasteTap.o} s={pasteTap.s} /><Ring x={84} y={248} p={pasteTap.ring} /></> : null}
    </div>
  );
};

/* ---------- Layouts, sideways (874 x 402 points), ScreenLayout geometry ---------- */
type Rect = { x: number; y: number; w: number; h: number };
const GAP = 12;
const AREA: Rect = { x: 52, y: 14, w: 874 - 52 - 14, h: 402 - 28 };
function cut(r: Rect, share: number, across: boolean): [Rect, Rect, Rect] {
  const len = across ? r.w : r.h, a = (len - GAP) * share, b = len - GAP - a;
  return across
    ? [{ ...r, w: a }, { x: r.x + a + GAP, y: r.y, w: b, h: r.h }, { x: r.x + a, y: r.y, w: GAP, h: r.h }]
    : [{ ...r, h: a }, { x: r.x, y: r.y + a + GAP, w: r.w, h: b }, { x: r.x, y: r.y + a, w: r.w, h: GAP }];
}
const Pane: React.FC<{ r: Rect; dark?: boolean; children?: React.ReactNode; o?: number }> = ({ r, dark, children, o = 1 }) => (
  <div className={`lp-pane${dark ? " dk" : ""}`} style={{ transform: `translate(${r.x}px, ${r.y}px)`, width: r.w, height: r.h, opacity: o }}>{children}</div>
);
const ActionsPane: React.FC = () => (
  <div className="pz-ac"><Front k="web" name="Safari" />
    <div className="ag">{SAFARI.slice(0, 6).map(([n, g, c]) => <Tile key={n} name={n} g={g} c={c} />)}</div></div>
);
const MediaPane: React.FC = () => (
  <div className="pz-md"><div className="src"><i />SPOTIFY</div><b>Slow Light</b><span>Paper Rooms</span>
    <div className="ctl"><Glyph n="backward.fill" /><span className="pp"><Glyph n="pause.fill" /></span><Glyph n="forward.fill" /></div></div>
);
export function layoutsEvents(t: number) {
  const on = t > L - 0.3 && t < R + 0.1;
  return { caption: on ? { p: E(t, L + 0.2, 0.5), q: E(t, LT.couch + 0.2, 0.3) } : undefined };
}
/** The Remote pane's rect in the layout's points (for the grow into the next scene). */
export const COUCH_REMOTE = cut(AREA, 0.6, true)[0];
export const LayoutsPhone: React.FC<{ t: number }> = ({ t }) => {
  // two panes: the divider comes in from the right edge and rests at 0.6
  const two = E(t, LT.split, 0.55);
  const third = E(t, LT.third, 0.5);
  const dragU = E(t, LT.drag[0], LT.drag[1] - LT.drag[0], INOUT);
  const snapped = t >= LT.snap;
  const split = snapped ? lerp(0.375, 1 / 3, SP(t, LT.snap, 0.3, 0.6)) : lerp(0.6, 0.375, dragU);
  const s0 = lerp(1, split, two);
  const [a, rest, line] = cut(AREA, Math.min(0.9999, s0), true);
  const [b, c2, line2] = cut(rest, lerp(1, 0.5, third), false);
  const couch = E(t, LT.couch, 0.45);
  const [ca, cr, cline] = cut(AREA, 0.6, true);
  const dragO = E(t, LT.drag[0] - 0.18, 0.15) * (1 - E(t, LT.snap + 0.1, 0.2));
  const fx = line.x + GAP / 2, fy = AREA.y + AREA.h / 2;
  const snapsO = E(t, LT.drag[0], 0.15) * (1 - E(t, LT.snap + 0.15, 0.3));
  const near = Math.abs(split - 1 / 3) < 0.05;
  const tick = clamp((t - LT.snap) / 0.5);
  return (
    <div style={{ position: "absolute", inset: 0, background: "#E7E6E2" }}>
      <div style={{ position: "absolute", inset: 0, opacity: 1 - couch }}>
        <Pane r={two < 0.001 ? { x: 0, y: 0, w: 874, h: 402 } : a}><div className="pz-tp" /></Pane>
        {two > 0.001 ? <>
          <Pane r={third > 0.001 ? c2 : rest}><ActionsPane /></Pane>
          {third > 0.001 ? <Pane r={b} o={clamp(third * 2)}><MediaPane /></Pane> : null}
          <div className="lp-div" style={{ transform: `translate(${line.x}px, ${line.y}px)`, width: line.w, height: line.h, opacity: two }}><i style={{ background: dragO > 0.2 ? "#0A84FF" : undefined }} /></div>
          {third > 0.001 ? <div className="lp-div inner" aria-orientation="horizontal" style={{ transform: `translate(${line2.x}px, ${line2.y}px)`, width: line2.w, height: line2.h, opacity: third }}><i /></div> : null}
        </> : null}
        <div className="lp-snaps" style={{ opacity: snapsO }}>
          {[1 / 3, 0.5, 2 / 3].map(v => <i key={v} className={`v${near && v === 1 / 3 ? " near" : ""}`} style={{ left: AREA.x + (AREA.w - GAP) * v + GAP / 2, top: AREA.y, height: AREA.h }} />)}
        </div>
        <Finger x={fx} y={fy} o={dragO} />
        <Ring x={fx} y={fy} p={tick} color="rgba(10,132,255,0.6)" />
      </div>
      {couch > 0 ? <div style={{ position: "absolute", inset: 0, opacity: couch }}>
        <Pane r={ca} dark><div className="pz-rm"><div className="pad"><b>Tap to play or pause</b><span>Swipe sideways to skip</span></div></div></Pane>
        <Pane r={cr}><div className="pz-tp" /></Pane>
        <div className="lp-div" style={{ transform: `translate(${cline.x}px, ${cline.y}px)`, width: cline.w, height: cline.h }}><i /></div>
      </div> : null}
    </div>
  );
};
