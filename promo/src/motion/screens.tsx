import React from "react";
import { AppIcon, CSS, Front, Glyph, Mark, Tile } from "./parts";
import { clamp, lerp, OUT } from "./lib";

/* The iPhone app's screens, drawn in iPhone points (874 x 402 sideways, 402 x 874 upright),
   with the names, symbols and colours of the app (Apps/iOS/Sources, GlasspadKit catalogs). */

export type B = [name: string, glyph: string, color: string];

/* Each app's first six buttons, in the order StarterDefinitions.swift lists them. */
export const SAFARI: B[] = [["Reopen Closed Tab", "arrow.uturn.backward", "#0A84FF"], ["Show All Tabs", "square.grid.2x2", "#0A84FF"], ["Reader", "doc.plaintext", "#0A84FF"], ["Downloads", "arrow.down.circle", "#0A84FF"], ["Previous Tab", "chevron.left", "#0A84FF"], ["Next Tab", "chevron.right", "#0A84FF"]];
export const XCODE: B[] = [["Run", "play.fill", "#147EFB"], ["Stop", "stop.fill", "#147EFB"], ["Build", "hammer", "#147EFB"], ["Test", "checkmark.diamond", "#147EFB"], ["Clean Build Folder", "trash", "#147EFB"], ["Open Quickly", "magnifyingglass", "#147EFB"]];
export const FCP: B[] = [["Blade at Playhead", "scissors", "#BF5AF2"], ["Set Range Start", "arrow.right.to.line", "#BF5AF2"], ["Set Range End", "arrow.left.to.line", "#BF5AF2"], ["Connect Clip", "arrow.turn.right.up", "#BF5AF2"], ["Append Clip", "text.append", "#BF5AF2"], ["Detach Audio", "waveform", "#BF5AF2"]];
/* Pinned: Mac controls from DeckSystemCatalog.swift (titles, symbols, colours), a screenshot
   button and a website button (its logo is the site's own icon). */
export const PINNED: B[] = [["Split Screen", "rectangle.split.2x1.fill", "#0A84FF"], ["Do Not Disturb", "moon.fill", "#5E5CE6"], ["Night Shift", "sun.horizon.fill", "#FFD60A"], ["Keep Awake", "cup.and.saucer.fill", "#30B0C7"], ["Screenshot", "camera.viewfinder", "#0A84FF"], ["Glasspad", "", ""]];

export const APP_INFO: Record<string, { key: string; name: string; tiles: B[] }> = {
  safari: { key: "web", name: "Safari", tiles: SAFARI },
  xcode: { key: "xcode", name: "Xcode", tiles: XCODE },
  fcp: { key: "fcp", name: "Final Cut Pro", tiles: FCP },
};

/** One tile's state: appear (0..1, for the ripple), press scale, on. */
export type TileState = { a?: number; press?: number; on?: boolean };
const tileStyle = (a = 1): CSS => (a >= 0.999 ? {} : { opacity: clamp(a * 1.6), transform: `scale(${lerp(0.86, 1, OUT(a))}) translateY(${(1 - OUT(a)) * 8}px)` });

/** Actions, sideways (the site's .acl): the front app's buttons, then Pinned. */
export const ActionsLand: React.FC<{
  app: string; prevApp?: string; flip?: (i: number) => number; tiles?: Record<string, TileState>; pinnedO?: number; vars?: CSS; head?: number;
}> = ({ app, prevApp, flip, tiles = {}, pinnedO = 1, vars, head }) => {
  const info = APP_INFO[app], prev = prevApp ? APP_INFO[prevApp] : undefined;
  const h = head ?? (flip ? flip(-1) : 1); // the header turns first
  return (
    <div className="fm-acl" style={vars}>
      <div className="col a">
        <div style={{ position: "relative", height: 44 }}>
          {prev && h < 1 ? <Front k={prev.key} name={prev.name} style={{ position: "absolute", inset: 0, opacity: 1 - clamp(h * 2), transform: `translateY(${-OUT(h) * 10}px)` }} /> : null}
          <Front k={info.key} name={info.name} style={{ position: "absolute", inset: 0, ...(h < 1 ? { opacity: clamp(h * 2 - 0.6), transform: `translateY(${(1 - OUT(h)) * 10}px)` } : {}) }} />
        </div>
        <div className="ag">
          {info.tiles.map(([n, g, c], i) => {
            const a = flip ? flip(i) : 1;
            const st = tiles[n] ?? {};
            if (prev && a < 0.5) {
              const [pn, pg, pc] = prev.tiles[i];
              const ps = tiles[pn] ?? {};
              return <Tile key={i} name={pn} g={pg} c={pc} press={(ps.press ?? 1) * lerp(1, 0.86, OUT(a * 2))} style={{ opacity: 1 - clamp(a * 2.2) }} />;
            }
            const b = prev ? (a - 0.5) * 2 : a;
            return <Tile key={i} name={n} g={g} c={c} press={st.press} on={st.on} style={tileStyle(b)} />;
          })}
        </div>
      </div>
      <div className="col b" style={{ opacity: pinnedO }}>
        <div className="ph5">Pinned</div>
        <div className="ag">
          {PINNED.map(([n, g, c], i) => {
            const st = tiles[n] ?? {};
            if (n === "Glasspad") return <Tile key={i} name={n} c="#1A1A1A" press={st.press} icon={<SiteLogo />} />;
            return <Tile key={i} name={n} g={g} c={c} press={st.press} on={st.on} />;
          })}
        </div>
      </div>
    </div>
  );
};

/** A website button's face: the site's own icon as its logo (WebsiteIcons.swift fetches it). */
export const SiteLogo: React.FC = () => (
  <span style={{ width: 44, height: 44, borderRadius: 11, overflow: "hidden", display: "block", boxShadow: "0 1px 3px rgba(0,0,0,0.12)" }}>
    <Mark size={44} />
  </span>
);

/** The mode pill at the top (ModeSwitcher.swift): the mode's symbol in its accent, its name. */
export const Pill: React.FC<{ name: string; g: string; color: string; o?: number; s?: number; dark?: boolean; style?: CSS }> = ({ name, g, color, o = 1, s = 1, dark, style }) =>
  o <= 0.001 ? null : (
    <div className="fm-pill" style={{ opacity: o, transform: `translateX(-50%) scale(${s})`, ...(dark ? { background: "rgba(40,40,40,0.82)", color: "#F2F1EE" } : {}), ...style }}>
      <span style={{ color }}><Glyph n={g} /></span>{name}
    </div>
  );

/* The default mode list (ModeEditing.swift): five modes, then the tools that open on top. */
export const MODES: [string, string, string][] = [
  ["Trackpad", "hand.point.up.left.fill", "#1A1A1A"], ["Keyboard", "keyboard.fill", "#5E5CE6"], ["Media", "play.circle.fill", "#FF375F"], ["Dock", "dock.rectangle", "#0A84FF"], ["Actions", "bolt.fill.mode", "#FF9F0A"],
];
export const TOOLS: [string, string, string][] = [
  ["Clipboard", "doc.on.clipboard.fill", "#30D158"], ["Present", "play.rectangle.fill", "#FF453A"], ["Remote", "appletvremote.gen4.fill", "#BF5AF2"], ["Displays", "display.2", "#63E6E2"],
];
const LAYOUTS: [string, number[]][] = [["Desk", [0.6]], ["Type", [0.5]], ["Listen", [0.6]], ["Couch", [0.6]]];

/** The mode menu, grown from the pill. p 0..1 opens it; `hit` presses one tile. */
export const ModeMenu: React.FC<{ p: number; current: string; hit?: string; press?: number; mac?: string; left?: number }> = ({ p, current, hit, press = 1, mac = "Soham's MacBook Pro", left = 31 }) => {
  if (p <= 0.001) return null;
  const tile = ([n, g, c]: [string, string, string]) => (
    <div key={n} className={`mt${n === current ? " sel" : ""}`} style={{ color: c, transform: n === hit ? `scale(${press})` : undefined }}>
      <Glyph n={g} /><span>{n}</span>
    </div>
  );
  return (
    <>
      <div style={{ position: "absolute", inset: 0, background: "rgba(0,0,0,0.12)", opacity: clamp(p), zIndex: 19 }} />
      <div className="fm-menu" style={{ left, opacity: clamp(p * 1.6), transform: `scale(${lerp(0.92, 1, OUT(p))})` }}>
        <div className="hd"><span><Glyph n="rotate.right" /></span><b>{mac}</b><span><Glyph n="gearshape" /></span></div>
        <div className="g">{MODES.map(tile)}</div>
        <div className="lh">Layouts</div>
        <div className="g">{LAYOUTS.map(([n, s]) => (
          <div key={n} className="mt" style={{ color: "#1A1A1A" }}>
            <span className="fm-lg"><i style={{ flex: s[0] }} /><i style={{ flex: 1 - s[0] }} /></span><span>{n}</span>
          </div>
        ))}</div>
        <hr />
        <div className="g t4">{TOOLS.map(tile)}</div>
      </div>
    </>
  );
};

/** Where a menu tile sits, in portrait points (for the finger). */
export function menuTileAt(name: string, left = 31): [number, number] {
  const i = MODES.findIndex(m => m[0] === name);
  const w = (340 - 24 - 16) / 5;
  if (i >= 0) return [left + 12 + w / 2 + i * (w + 4), 62 + 10 + 44 + 8 + 33];
  const j = TOOLS.findIndex(m => m[0] === name);
  const w4 = (340 - 24 - 12) / 4;
  return [left + 12 + w4 / 2 + j * (w4 + 4), 62 + 10 + 44 + 8 + 66 + 22 + 66 + 17 + 33];
}
