import React from "react";
import { useVideoConfig } from "remotion";
import "../site/device.css";
import "../site/redo.css";
import "../site/v3.css";
import "../site/surface.css";
import "../film.css";
import "./thumbs.css";
import { AppIcon, CSS, Doc, Finger, Front, Glyph, MacBook, MenuBar, Phone, Poster, Ring, Stand, Tile, Win } from "../parts";
import { NotesWin, SafariWin, XcodeWin } from "../mac";
import { ActionsLand, ModeMenu, PINNED, SiteLogo, SAFARI } from "../screens";
import { CouchPhone, CT, laserAt, PresentPhone, RI, Slide } from "../scenes/Couch";
import { StandBy, NT } from "../scenes/Night";

/* YouTube thumbnails for the motion film. Each is one feature: a two to four word headline in
   the top left (same size, place and grid on every one), and the real app on the iPhone doing
   that feature to the Mac beside it. Drawn on a 1920 x 1080 stage with the film's own parts,
   then scaled to the composition's size. The bottom right corner stays clear for YouTube's
   timestamp. */

const W = 1920, H = 1080;
const PAPER = "#E9E7E2", DESK = "#DEDBD5", INK = "#1A1A1A", LIGHT = "#F2F1EE";

const Stage: React.FC<{ bg: string; children: React.ReactNode }> = ({ bg, children }) => {
  const { width } = useVideoConfig();
  return (
    <div style={{ position: "absolute", inset: 0, background: bg, overflow: "hidden" }}>
      <div className="fm" style={{ width: W, height: H, right: "auto", bottom: "auto", transform: `scale(${width / W})`, transformOrigin: "0 0", background: bg }}>
        <div className="fm-world">{children}</div>
      </div>
    </div>
  );
};

/** The headline: heavy, tight, two lines at most; `accent` colours the words in [brackets]. */
const Head: React.FC<{ lines: string[]; accent: string; dark?: boolean; style?: CSS }> = ({ lines, accent, dark, style }) => (
  <div className="th-head" style={{ color: dark ? LIGHT : INK, ...style }}>
    {lines.map((l, i) => (
      <div key={i}>{l.split(/(\[[^\]]+\])/).map((p, j) => p.startsWith("[") ? <span key={j} style={{ color: accent }}>{p.slice(1, -1)}</span> : p)}</div>
    ))}
  </div>
);

/** A sideways phone on its stand, centred at (cx, cy), `long` world px across. */
const StandPhone: React.FC<{ cx: number; cy: number; long: number; land: React.ReactNode; finish?: "light" | "dark"; dim?: number }> = ({ cx, cy, long, land, finish, dim }) => {
  const pw = long * 71.9 / 150;
  const sW = long * 0.62, u = long / 21;
  return (
    <>
      <Stand x={cx - sW / 2} y={cy + pw / 2 - 1.6 * u} width={sW} dim={dim} />
      <Phone cx={cx} cy={cy} w={pw} turn={1} land={land} finish={finish} />
    </>
  );
};

/** A touch held on the screen: the film's finger dot and its ring. */
const Touch: React.FC<{ x: number; y: number; dark?: boolean; ring?: number }> = ({ x, y, dark, ring = 0.35 }) => (
  <><Finger x={x} y={y} o={1} dark={dark} /><Ring x={x} y={y} p={ring} dark={dark} /></>
);

/* ---------- 1. Actions: buttons for the app in front ---------- */
export const ThumbActions: React.FC = () => {
  const run: [number, number] = [62 + 60, 30 + 44 + 16 + 52];
  return (
    <Stage bg={PAPER}>
      <div className="th-desk" style={{ top: 960, background: DESK }} />
      <MacBook x={900} y={70} lid={1100}>
        <div className="mbx" style={{ background: "#CFCBC3" }}>
          <MenuBar app="Xcode" />
          <XcodeWin box={{ x: 2, y: 8, w: 96, h: 88 }} front status="Running Glasspad on My Mac" running={1} />
        </div>
      </MacBook>
      <StandPhone cx={700} cy={760} long={1180} land={
        <div style={{ position: "absolute", inset: 0, background: "#FBFBF9" }}>
          <ActionsLand app="xcode" tiles={{ Run: { press: 0.96 } }} />
          <Touch x={run[0] + 30} y={run[1] - 8} />
        </div>} />
      <Head lines={["Buttons for", "[every app.]"]} accent="#147EFB" />
    </Stage>
  );
};

/* ---------- 2. Arrange: two windows side by side ---------- */
const SPLIT_MINT = "#00C7BE";
/** Arrange, upright (ArrangeSheet.swift): arrangements, the display in miniature, Split. */
const ArrangeSheet: React.FC<{ press?: number }> = ({ press = 1 }) => {
  const opts: [string, string][] = [["Left & Right", "lr"], ["Top & Bottom", "tb"], ["Quarters", "q"], ["Full Screen", "fs"]];
  return (
    <div className="th-sheetwrap">
      <div className="th-under"><ActionsPortrait /></div>
      <div className="th-dim" />
      <div className="th-sheet">
        <div className="th-nav"><span className="th-x"><Glyph n="xmark" /></span><b>Arrange</b></div>
        <div className="th-opts">{opts.map(([n, k], i) => (
          <div key={k} className={`th-opt${i === 0 ? " on" : ""}`}><ArrGlyph k={k} on={i === 0} /><span>{n}</span></div>
        ))}</div>
        <div className="th-mini">
          <div className="th-mbar" />
          <div className="th-card l"><div className="tb"><i /><i /><i /></div><div className="lb"><AppIcon k="web" w={52} /><b>Safari<Chev /></b><small>Apple</small></div></div>
          <div className="th-card r"><div className="tb"><i /><i /><i /></div><div className="lb"><AppIcon k="notes" w={52} /><b>Notes<Chev /></b><small>Friday</small></div></div>
          <span className="th-swap"><svg viewBox="0 0 24 24"><path d="M4 8.5h14M14.5 5l3.5 3.5-3.5 3.5M20 15.5H6M9.5 12 6 15.5 9.5 19" /></svg></span>
        </div>
        <div className="th-primary" style={{ background: SPLIT_MINT, transform: `scale(${press})` }}>Split</div>
      </div>
    </div>
  );
};
const Chev: React.FC = () => <svg className="th-chev" viewBox="0 0 24 24"><path d="m8 9.5 4-4 4 4M8 14.5l4 4 4-4" /></svg>;
/** The Move & Resize glyph for an arrangement. */
const ArrGlyph: React.FC<{ k: string; on: boolean }> = ({ k, on }) => {
  const fill = on ? SPLIT_MINT : "rgba(26,26,26,0.3)", line = on ? INK : "rgba(26,26,26,0.55)";
  const full = k === "fs", bar = full ? 0 : 4.5;
  const x0 = full ? 1.3 : 2.9, y0 = x0 + bar, w = 40 - 2 * x0, h = 28 - 2 * x0 - bar, g = 1.6;
  const rects: [number, number, number, number][] =
    k === "lr" || k === "fs" ? [[x0, y0, (w - g) / 2, h], [x0 + (w + g) / 2, y0, (w - g) / 2, h]]
      : k === "tb" ? [[x0, y0, w, (h - g) / 2], [x0, y0 + (h + g) / 2, w, (h - g) / 2]]
        : [[x0, y0, (w - g) / 2, (h - g) / 2], [x0 + (w + g) / 2, y0, (w - g) / 2, (h - g) / 2], [x0, y0 + (h + g) / 2, (w - g) / 2, (h - g) / 2], [x0 + (w + g) / 2, y0 + (h + g) / 2, (w - g) / 2, (h - g) / 2]];
  return (
    <svg viewBox="0 0 40 28" width={40} height={28}>
      <defs><clipPath id={`c-${k}`}><rect x="0.65" y="0.65" width="38.7" height="26.7" rx="4.5" /></clipPath></defs>
      {!full ? <rect x="0" y="0" width="40" height={bar + 0.65} fill={line} opacity={0.3} clipPath={`url(#c-${k})`} /> : null}
      {rects.map(([x, y, rw, rh], i) => <rect key={i} x={x} y={y} width={rw} height={rh} rx={full ? 0.8 : 1.4} fill={fill} opacity={i === 0 ? 1 : 0.7} />)}
      <rect x="0.65" y="0.65" width="38.7" height="26.7" rx="4.5" fill="none" stroke={line} strokeWidth="1.3" />
    </svg>
  );
};
/** Actions upright, under the sheet: Safari's buttons, then Pinned. */
const ActionsPortrait: React.FC = () => (
  <div className="fm-acl" style={{ background: "#F2F1EE" }}>
    <div style={{ position: "absolute", left: 16, right: 16, top: 112 }}>
      <Front k="web" name="Safari" />
      <div className="ag" style={{ marginTop: 16 }}>{SAFARI.map(([n, g, c]) => <Tile key={n} name={n} g={g} c={c} />)}</div>
      <div className="ph5" style={{ marginTop: 14 }}>Pinned</div>
      <div className="ag" style={{ marginTop: 8 }}>{PINNED.map(([n, g, c]) => n === "Glasspad" ? <Tile key={n} name={n} c={INK} icon={<SiteLogo />} /> : <Tile key={n} name={n} g={g} c={c} />)}</div>
    </div>
  </div>
);
export const ThumbSplit: React.FC = () => {
  // the phone, upright and close: its top runs off the frame, the sheet fills the view
  const w = 600, h = w * 150 / 71.9;
  const btn: [number, number] = [292, 874 - 8 - 16 - 25];
  return (
    <Stage bg={PAPER}>
      <div className="th-desk" style={{ top: 960, background: DESK }} />
      <MacBook x={80} y={330} lid={860}>
        <div className="mbx" style={{ background: "#CFCBC3" }}>
          <MenuBar app="Safari" />
          <SafariWin box={{ x: 0.6, y: 5.6, w: 49.1, h: 76 }} front tabs={2} url="apple.com" page={<Doc n={16} />} />
          <NotesWin box={{ x: 50.3, y: 5.6, w: 49.1, h: 76 }} text="See you at three" caret={false} />
        </div>
      </MacBook>
      <Phone cx={1320} cy={1050 - h / 2} w={w} finish="light" shadow="hand" tilt={-3} port={
        <div style={{ position: "absolute", inset: 0 }}>
          <ArrangeSheet press={0.97} />
          <Touch x={btn[0]} y={btn[1]} />
        </div>} />
      <Head lines={["[Split] your Mac."]} accent="#00A69E" />
    </Stage>
  );
};

/* ---------- 3. Remote: the couch and the TV ---------- */
export const ThumbRemote: React.FC = () => {
  const t = CT.room + 0.5; // Remote at rest; the touch is ours, on the 10 seconds forward button
  return (
    <Stage bg="#2B2925">
      <div style={{ position: "absolute", inset: 0, background: "radial-gradient(60% 70% at 38% 40%, #3A372F, #2B2925 70%)" }} />
      <div style={{ position: "absolute", left: 0, right: 0, top: 960, bottom: 0, background: "#23211E" }} />
      <div style={{ position: "absolute", left: 90, top: 400, width: 1040 }}>
        <div className="tv-b" style={{ padding: 9, borderRadius: 12 }}>
          <div className="tv-s">
            <div className="tv-film"><Poster style={{ position: "absolute", inset: 0 }} /></div>
            <div className="tv-seek" style={{ opacity: 1 }}><RI g="fwd10" /></div>
            <div className="tv-bar" style={{ opacity: 1 }}><i style={{ width: "35%" }} /></div>
          </div>
        </div>
      </div>
      <Phone cx={1370} cy={650} w={540} finish="dark" shadow="hand" tilt={-5} port={<><CouchPhone t={t} /><Touch x={337} y={389} dark /></>} />
      <Head lines={["Your Mac’s", "[remote.]"]} accent="#BF5AF2" dark />
    </Stage>
  );
};

/* ---------- 5. StandBy: the nightstand, the Mac playing beside it ---------- */
export const ThumbStandBy: React.FC = () => {
  const t = NT.tick + 0.6;
  return (
    <Stage bg="#121317">
      <div style={{ position: "absolute", inset: 0, background: "radial-gradient(45% 70% at 18% 30%, rgba(255,214,160,0.12), transparent 70%)" }} />
      <div className="nstand" style={{ left: 0, right: 0, top: 880, filter: "brightness(0.55)" }} />
      <MacBook x={110} y={560} lid={520} style={{ filter: "brightness(0.8)" }}>
        <div className="mbx" style={{ background: "#2A2C33" }}>
          <MenuBar app="Music" />
          <Win box={{ x: 8, y: 14, w: 84, h: 62 }} front>
            <div className="fm-music"><Poster style={{ width: "22cqh", height: "22cqh", borderRadius: "1.2cqw", flex: "none" }} />
              <div className="meta"><b>Slow Light</b><span>Paper Rooms</span><div className="pb"><i style={{ width: "31%" }} /></div></div></div>
          </Win>
        </div>
      </MacBook>
      <StandPhone cx={1250} cy={630} long={1080} finish="dark" dim={0.45} land={<><StandBy t={t} /><Touch x={701} y={314} dark /></>} />
      <Head lines={["Pause [from bed.]"]} accent="#FF375F" dark />
    </Stage>
  );
};

/* ---------- 6. Every mode: the mode menu open ---------- */
export const ThumbModes: React.FC = () => {
  const w = 760, h = w * 150 / 71.9;
  return (
    <Stage bg={PAPER}>
      <div className="th-desk" style={{ top: 960, background: DESK }} />
      <MacBook x={70} y={420} lid={780}>
        <div className="mbx" style={{ background: "#CFCBC3" }}>
          <MenuBar app="Safari" />
          <SafariWin box={{ x: 8, y: 9, w: 62, h: 72 }} front page={<Doc n={16} />} />
        </div>
      </MacBook>
      <Phone cx={1290} cy={20 + h / 2} w={w} finish="light" shadow="hand" tilt={-3} port={
        <div style={{ position: "absolute", inset: 0, background: "#F2F1EE" }}>
          <ActionsPortrait />
          <div className="th-menu"><ModeMenu p={1} current="Actions" /></div>
        </div>} />
      <Head lines={["Control your", "[whole Mac.]"]} accent="#0A84FF" />
    </Stage>
  );
};

/* ---------- 7. Present: the slides, the laser, Next ---------- */
export const ThumbPresent: React.FC = () => {
  const t = CT.laser[0] + 0.48 * (CT.laser[1] - CT.laser[0]); // the laser rests on the Lighthouse
  const laser = laserAt(0.48);
  const SC = { x: 90, y: 400, w: 1040 }, sh = SC.w * 9 / 16;
  return (
    <Stage bg="#DAD6CF">
      <div style={{ position: "absolute", left: 0, right: 0, top: 960, bottom: 0, background: "#C9C3B9" }} />
      <div style={{ position: "absolute", left: SC.x - 19, top: SC.y - 21, width: SC.w + 38, height: 21, borderRadius: 12, background: "linear-gradient(#5A5752, #3C3A36)" }} />
      <div className="scr-s" style={{ position: "absolute", left: SC.x, top: SC.y, width: SC.w, height: sh, aspectRatio: "auto" }}>
        <Slide k={1} laser={laser} />
        <span className="slaser" style={{ left: `${laser[0] * 100}%`, top: `${laser[1] * 100}%`, opacity: 1 }} />
        <span className="sl-n">2</span>
      </div>
      <Phone cx={1370} cy={650} w={540} finish="light" shadow="hand" tilt={-5} port={<PresentPhone t={t} />} />
      <Head lines={["Present from", "[your iPhone.]"]} accent="#E5342A" />
    </Stage>
  );
};

export const THUMBS: [string, React.FC][] = [
  ["actions", ThumbActions], ["split", ThumbSplit], ["remote", ThumbRemote],
  ["standby", ThumbStandBy], ["modes", ThumbModes], ["present", ThumbPresent],
];
