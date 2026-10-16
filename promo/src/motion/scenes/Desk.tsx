import React from "react";
import { useCurrentFrame } from "remotion";
import { BlurX, Caption, Cursor, Dock, dockBounce, Finger, Haptic, MacBook, macDisplay, MenuBar, Phone, phoneGeom, Ring, Stand, Doc, Glyph } from "../parts";
import { AppSwitcher, Banner, FcpWin, MailWin, MenuMoon, MusicWin, NotesWin, SafariWin, SitePage, XcodeWin } from "../mac";
import { ActionsLand, ModeMenu, Pill, menuTileAt } from "../screens";
import { ModesPhone, LayoutsPhone, modesEvents, layoutsEvents, LT, COUCH_REMOTE } from "./DeskPhone";
import { clamp, E, INOUT, K, KP, lerp, OUT, SP, TAP, TAPS } from "../kit";
import { barSec, sceneSec, word } from "../timeline";

/* Scenes 1 to 6 share one desk: a MacBook on the left, the iPhone on a stand on the right.
   Open, Trackpad, Actions, Pinned, then the phone stands up for the modes, and lies back down
   for Layouts. Times are film seconds. */

/* ---------- the desk ---------- */
const LID = { x: 110, y: 213, w: 820 };
export const DISP = macDisplay(LID.x, LID.y, LID.w); // the MacBook's display in world px
const DESK_Y = 846;
const PH = { cx: 1470, cy: 611, W: 720 }; // the phone on its stand, sideways
const PW = PH.W * 71.9 / 150; // short side
const PG = phoneGeom(PW);
/** World position of a point on the sideways phone's screen, in its points. */
export const padWorld = (x: number, y: number, cx = PH.cx, cy = PH.cy) => [cx - PH.W / 2 + PG.inset + x * PG.k, cy - PW / 2 + PG.inset + y * PG.k] as [number, number];
/** The finger on the pad for a pointer position (display percent): the pad's gain is 1.6. */
const fingerFor = (px: number, py: number): [number, number] => [437 + (px - 50) * 6.19, 201 + (py - 50) * 4.02];

const S = {
  open: 0, trackpad: sceneSec("trackpad"), actions: sceneSec("actions"), pinned: sceneSec("pinned"),
  modes: sceneSec("modes"), layouts: sceneSec("layouts"), remote: sceneSec("remote"),
};

/* ---------- the timeline, in film seconds ---------- */
export const T = {
  dotIn: 0.25, pulse: 0.7, zoom0: 1.05, zoom1: 3.75,
  glide0: 1.35, toDock: 3.95, openTap: 4.3,
  head0: 3.3, head1: 6.25,
  toPage: [5.05, 5.85] as const,
  scroll: [S.trackpad + 0.32, S.trackpad + 1.5] as const,
  clickTap: S.trackpad + word("trackpad", "click"),
  swipe: [S.trackpad + 3.38, S.trackpad + 3.98] as const,
  pill: S.trackpad + 5.05, menuTap: S.trackpad + 5.75,
  reopen: S.actions + 1.05,
  sw1: S.actions + 1.75, xcFront: S.actions + 2.25,
  run: S.actions + 3.35,
  sw2: S.actions + 4.55, fcFront: S.actions + 5.05,
  blade: S.actions + 6.3,
  split: S.pinned + word("pinned", "controls") - 0.2,
  dnd: S.pinned + 2.75,
  site: S.pinned + 4.25,
  stand: S.modes - 0.95,
};
/* From Actions on, the camera rests and the phone moves: forward for Actions and Pinned, upright
   for the modes, and large for Layouts. */
const CAM2 = { cx: 930, cy: 570, s: 1.15 };
const toWorld = (sx: number, sy: number) => [(sx - 960) / CAM2.s + CAM2.cx, (sy - 540) / CAM2.s + CAM2.cy];
const FORE = toWorld(1378, 752), UP = toWorld(1500, 548), BIG = toWorld(1010, 600);
type Pose = { cx: number; cy: number; sc: number; turn: number };
const POSES: [number, Pose][] = [
  [0, { cx: PH.cx, cy: PH.cy, sc: 1, turn: 1 }],
  [S.actions - 1.0, { cx: PH.cx, cy: PH.cy, sc: 1, turn: 1 }],
  [S.actions + 0.3, { cx: FORE[0], cy: FORE[1], sc: 1.25, turn: 1 }],
  [S.modes - 0.95, { cx: FORE[0], cy: FORE[1], sc: 1.25, turn: 1 }],
  [S.modes + 0.05, { cx: UP[0], cy: UP[1], sc: 370 / PW, turn: 0 }],
  [S.layouts - 0.25, { cx: UP[0], cy: UP[1], sc: 370 / PW, turn: 0 }],
  [S.layouts + 0.6, { cx: BIG[0], cy: BIG[1], sc: 1.62, turn: 1 }],
];
export function pose(t: number): Pose {
  const pick = (k: keyof Pose) => K(t, POSES.map(([a, p]) => [a, p[k]] as [number, number]));
  return { cx: pick("cx"), cy: pick("cy"), sc: pick("sc"), turn: pick("turn") };
}

export const DESK_CUES = () => ({
  tap: [T.openTap, T.clickTap, T.reopen, T.run, T.blade, T.split, T.dnd, T.site, T.menuTap, T.pill],
  haptic: [T.clickTap],
  whoosh: [T.zoom0 + 0.2, T.swipe[0] + 0.25, T.stand + 0.3],
  drag: [[T.scroll[0], T.scroll[1]], [T.swipe[0], T.swipe[1]]] as [number, number][],
  click: [T.sw1 + 0.3, T.sw2 + 0.3],
  land: [T.split + 0.08],
  chime: [] as number[],
});

const POINTER: [number, number, number][] = [
  [T.glide0, 62, 50], [2.9, 49, 66], [T.toDock, 33.6, 90.5], [T.openTap + 0.75, 33.6, 90.5], [T.toPage[1], 52, 46],
  [T.clickTap - 0.55, 52, 46], [T.clickTap - 0.12, 57, 55.5],
];

function camera(t: number): { cx: number; cy: number; s: number } {
  const home = { cx: 970, cy: 530, s: 1 };
  // the opening pull back: from inside the pad to the whole desk
  if (t < T.zoom1) {
    const u = INOUT(clamp((t - T.zoom0) / (T.zoom1 - T.zoom0)));
    const s0 = 6.2, s = Math.exp(lerp(Math.log(s0), 0, u));
    const A = padWorld(...fingerFor(62, 50));
    const end = [A[0] - home.cx + 960, A[1] - home.cy + 540];
    const sp = [lerp(960, end[0], u), lerp(540, end[1], u)];
    return { cx: A[0] - (sp[0] - 960) / s, cy: A[1] - (sp[1] - 540) / s, s };
  }
  const k: [number, number, number, number][] = [
    [T.zoom1, 970, 530, 1], [S.trackpad + 0.2, 970, 530, 1], [S.trackpad + 3.2, 1040, 545, 1.1], [S.trackpad + 4.6, 1040, 545, 1.1],
    [S.actions - 1.0, 1040, 545, 1.1], [S.actions + 0.3, CAM2.cx, CAM2.cy, CAM2.s],
  ];
  const pick = (j: number) => K(t, k.map(r => [r[0], r[j]] as [number, number]));
  return { cx: pick(1), cy: pick(2), s: pick(3) };
}

/* ---------- the Mac's screen over time ---------- */
const DOCK = ["finder", "web", "mail", "notes", "music", "xcode", "fcp", "set"];
const W_SAF2 = { x: 20, y: 9, w: 58, h: 68 }, W_XC = { x: 34, y: 15, w: 60, h: 64 }, W_FC = { x: 4, y: 12, w: 58, h: 66 };
const HALF_L = { x: 0.6, y: 5.6, w: 49.1, h: 76 }, HALF_R = { x: 50.3, y: 5.6, w: 49.1, h: 76 };
const lerpBox = (a: typeof HALF_L, b: typeof HALF_L, u: number) => ({ x: lerp(a.x, b.x, u), y: lerp(a.y, b.y, u), w: lerp(a.w, b.w, u), h: lerp(a.h, b.h, u) });

const PAGE1 = ["h", "", "88", "94", "p", "", "76", "90", "", "82", "70", "86", "", "92", "64", "h", "", "80", "p p2", "", "88", "74"];
const Page: React.FC<{ shift: number; link: number; alt: number }> = ({ shift, link, alt }) => (
  <>
    <div style={{ position: "absolute", inset: 0, opacity: 1 - alt }}>
      <Doc n={22} rows={PAGE1} shift={shift} />
      <span style={{ position: "absolute", left: "3cqw", top: `${68.5 - shift}cqh`, width: "36%", height: "1.6cqh", borderRadius: "1cqh", background: "#2F6FE4", opacity: 0.75 + 0.25 * link }} />
    </div>
    {alt > 0 ? <div style={{ position: "absolute", inset: 0, opacity: alt, transform: `translateY(${(1 - OUT(alt)) * 2}cqh)` }}><Doc n={14} rows={["p p2", "h", "", "92", "84", "", "90", "70", "", "86", "94", "62"]} /></div> : null}
  </>
);

const MacScreen: React.FC<{ t: number }> = ({ t }) => {
  // pointer
  const [px, py] = KP(t, POINTER);
  const press = TAPS(t, [T.openTap, T.clickTap]).press;
  const ptrO = t < T.glide0 - 0.1 ? 0 : E(t, T.glide0 - 0.1, 0.3) * (1 - E(t, T.swipe[1] + 0.6, 0.4));
  // Safari opens from the Dock
  const open = E(t, T.openTap + 0.18, 0.62);
  const bounceU = (t - (T.openTap + 0.02)) / 0.9;
  // two finger scroll with a little momentum, then a click on a link
  const shift = 46 * E(t, T.scroll[0] + 0.08, T.scroll[1] - T.scroll[0] - 0.05, INOUT) + 12 * E(t, T.scroll[1], 0.7);
  const alt = E(t, T.clickTap + 0.08, 0.45);
  // three finger swipe: Space 1 slides out, Space 2 in
  const spaceAt = (x: number) => (x < T.swipe[1] ? E(x, T.swipe[0] + 0.1, T.swipe[1] - T.swipe[0] - 0.1, INOUT) * 0.62 : lerp(0.62, 1, SP(x, T.swipe[1], 0.42, 0.86)));
  const space = spaceAt(t);
  const spaceV = (space - spaceAt(t - 1 / 60)) * DISP.w * 1.04; // screen px this frame
  // Space 2: front app changes
  const front = t < T.xcFront ? "web" : t < T.fcFront ? "xcode" : "fcp";
  const appName = t < T.openTap + 0.3 ? "Finder" : front === "web" ? "Safari" : front === "xcode" ? "Xcode" : "Final Cut Pro";
  const siteOpen = E(t, T.site + 0.15, 0.6);
  const menuApp = siteOpen > 0.5 ? "Safari" : appName;
  // Reopen Closed Tab, Run, Blade
  const tabs = 2 + E(t, T.reopen + 0.08, 0.45);
  const running = t > T.run + 0.62 ? 1 : 0;
  const status = t < T.run + 0.05 ? "Build Succeeded" : t < T.run + 0.62 ? "Building Glasspad" : "Running Glasspad on My Mac";
  const cut = E(t, T.blade + 0.06, 0.5);
  // Split Screen: Final Cut Pro and Xcode share the display
  const split = SP(t, T.split + 0.05, 0.5, 0.72);
  // Do Not Disturb: the moon; a banner is held back
  const moon = SP(t, T.dnd + 0.08, 0.4, 0.62);
  const banX = 1 - E(t, T.dnd + 0.02, 0.45);
  const banO = clamp(E(t, T.dnd + 0.02, 0.2) - E(t, T.dnd + 0.22, 0.35));
  const banBlur = 14 * E(t, T.dnd + 0.22, 0.35);
  // app switcher
  const sw = (t0: number) => E(t, t0, 0.16) * (1 - E(t, t0 + 0.5, 0.14));
  const swP = Math.max(sw(T.sw1), sw(T.sw2));
  const sel = t < T.sw2 - 0.1 ? K(t, [[T.sw1 + 0.18, 0], [T.sw1 + 0.36, 1]], OUT) : K(t, [[T.sw2 + 0.18, 1], [T.sw2 + 0.36, 2]], OUT);
  const z = (k: string) => (k === front ? 5 : k === "web" ? 3 : k === "xcode" ? 4 : 2);
  // Modes: Notes and Music come forward on the Mac (see DeskPhone)
  const me = modesEvents(t);
  return (
    <div className="mbx" style={{ background: "#CFCBC3" }}>
      <BlurX id="mb-spaces" px={spaceV}>
      {/* Space 1 */}
      <div style={{ position: "absolute", inset: 0, transform: `translateX(${-space * 100}%)` }}>
        <SafariWin box={{ x: 10, y: 9, w: 62, h: 72 }} front o={clamp(open * 3)} s={lerp(0.2, 1, open)} origin={`${(33.6 - 10) / 62 * 100}% ${(92 - 9) / 72 * 100}%`}
          url="" page={<Page shift={shift} link={TAP(t, T.clickTap).o} alt={alt} />} />
      </div>
      {/* Space 2 */}
      <div style={{ position: "absolute", inset: 0, transform: `translateX(${(1 - space) * 100}%)` }}>
        {/* the app that comes forward fades in over its own place in the stack */}
        {front === "fcp" && t < T.fcFront + 0.3 ? <FcpWin box={W_FC} z={2} cut={cut} /> : null}
        {front === "xcode" && t < T.xcFront + 0.3 ? <XcodeWin box={W_XC} z={3} status={status} running={running} /> : null}
        <FcpWin box={split > 0 ? lerpBox(W_FC, HALF_L, split) : W_FC} front={front === "fcp"} z={z("fcp")} cut={cut} o={front === "fcp" ? E(t, T.fcFront, 0.3) : 1} s={front === "fcp" ? lerp(0.99, 1, E(t, T.fcFront, 0.3)) : 1} />
        <XcodeWin box={split > 0 ? lerpBox(W_XC, HALF_R, split) : W_XC} front={front === "xcode"} z={z("xcode")} status={status} running={running} o={front === "xcode" ? E(t, T.xcFront, 0.3) : 1} s={front === "xcode" ? lerp(0.99, 1, E(t, T.xcFront, 0.3)) : 1} />
        <SafariWin box={W_SAF2} front={front === "web"} z={z("web")} tabs={tabs} active={tabs > 2.5 ? 2 : 0} />
        <SafariWin box={{ x: 21, y: 8, w: 58, h: 72 }} front z={9} o={clamp(siteOpen * 3)} s={lerp(0.3, 1, siteOpen)} url="glasspad.sohamaggarwal.com" page={<SitePage />} tabs={1} />
        {me.notes > 0 ? <NotesWin box={{ x: 6, y: 9, w: 52, h: 64 }} front={me.notesZ > 11} z={me.notesZ} o={clamp(me.notes * 3)} s={lerp(0.6, 1, me.notes)} text={me.typed} more={me.pasted} caret={me.caret} /> : null}
        {me.music > 0 ? <MusicWin box={{ x: 40, y: 34, w: 52, h: 38 }} front={me.musicFront} z={11} o={clamp(me.music * 3)} s={lerp(0.6, 1, me.music)} prog={me.prog} origin="40% 140%" /> : null}
        {me.mail > 0 ? <MailWin box={{ x: 28, y: 14, w: 56, h: 62 }} front={me.mailFront} z={me.mailFront ? 13 : 9} o={clamp(me.mail * 3)} s={lerp(0.6, 1, me.mail)} origin="20% 130%" /> : null}
      </div>
      </BlurX>
      <MenuBar app={me.app ?? menuApp} extra={<MenuMoon p={moon} />} />
      <Banner app="msg" title="Maya" text="Running five minutes late" x={banX} o={banO} blur={banBlur} />
      <Dock keys={DOCK} running={["finder", ...(t > T.openTap + 0.2 ? ["web"] : []), "xcode", "fcp", ...(me.music > 0 ? ["music"] : []), ...(me.notes > 0 ? ["notes"] : []), ...(me.mail > 0 ? ["mail"] : [])]}
        bounce={{ web: dockBounce(bounceU), music: dockBounce(me.musicBounce), mail: dockBounce(me.mailBounce) }} />
      <AppSwitcher apps={["web", "xcode", "fcp", "finder"]} sel={sel} p={swP} />
      <Cursor x={px} y={py} press={press} o={ptrO} />
    </div>
  );
};

/* ---------- the phone over time ---------- */
const DeskPhone: React.FC<{ t: number }> = ({ t }) => {
  // the opening dot is this finger; it lands with a pulse, glides, taps
  const [px, py] = KP(t, POINTER);
  const fp = fingerFor(px, py);
  const glide = t >= T.dotIn && t < T.swipe[0] - 0.1;
  const dotIn = SP(t, T.dotIn, 0.5, 0.62);
  const tap1 = TAPS(t, [T.openTap, T.clickTap]);
  const cam = camera(t);
  // the dot keeps about the same size on screen while the camera pulls back
  const rScreen = 1 / Math.pow(cam.s, 0.8);
  const hold = t < T.openTap - 0.3 ? 1 : t < T.toPage[1] + 0.3 ? 1 - E(t, T.openTap + 0.35, 0.3) + E(t, T.toPage[0] - 0.25, 0.25) : 1 - E(t, T.toPage[1] + 0.05, 0.3) + E(t, T.clickTap - 0.65, 0.2);
  const dotO = glide ? clamp(dotIn * 1.4) * clamp(hold) : 0;
  const ink = lerp(0.62, 0.42, E(t, 2.6, 1.0));
  // two and three fingers
  const sc = E(t, T.scroll[0], 0.15) * (1 - E(t, T.scroll[1], 0.2));
  const sy = -150 * E(t, T.scroll[0] + 0.08, T.scroll[1] - T.scroll[0] - 0.05, INOUT);
  const swO = E(t, T.swipe[0], 0.15) * (1 - E(t, T.swipe[1], 0.2));
  const sx = -210 * E(t, T.swipe[0] + 0.1, T.swipe[1] - T.swipe[0] - 0.1, INOUT);
  // the mode pill and menu, then Actions
  const pillO = E(t, T.pill - 0.35, 0.25) * (1 - E(t, T.pill + 0.05, 0.12));
  const menu = SP(t, T.pill + 0.05, 0.38, 0.82) * (1 - E(t, T.menuTap + 0.1, 0.18));
  const toActions = t >= T.menuTap + 0.12;
  const tapPill = TAP(t, T.pill), tapMenu = TAP(t, T.menuTap);
  const [mx, my] = menuTileAt("Actions", 267);
  // Actions: the tiles turn in a ripple when the front app changes
  const ripple = (t0: number) => (i: number) => i < 0 ? E(t, t0, 0.36) : E(t, t0 + 0.06 + 0.055 * i, 0.42);
  const intro = (i: number) => i < 0 ? E(t, T.menuTap + 0.16, 0.3) : E(t, T.menuTap + 0.22 + 0.05 * i, 0.4);
  const app = t < T.xcFront ? "safari" : t < T.fcFront ? "xcode" : "fcp";
  const flip = t < T.xcFront ? intro : t < T.fcFront ? ripple(T.xcFront + 0.05) : ripple(T.fcFront + 0.05);
  const prev = t < T.xcFront ? undefined : t < T.fcFront ? "safari" : "xcode";
  const taps: Record<string, number> = { "Reopen Closed Tab": T.reopen, Run: T.run, "Blade at Playhead": T.blade, "Split Screen": T.split, "Do Not Disturb": T.dnd, Glasspad: T.site };
  const tiles = Object.fromEntries(Object.entries(taps).map(([n, t0]) => [n, { press: TAP(t, t0).press, on: n === "Do Not Disturb" ? t > T.dnd + 0.05 : n === "Split Screen" ? false : undefined }]));
  const ACT_AT: Record<string, [number, number]> = {
    "Reopen Closed Tab": [62 + 60, 30 + 44 + 16 + 52], Run: [62 + 60, 30 + 44 + 16 + 52], "Blade at Playhead": [62 + 60, 30 + 44 + 16 + 52],
    "Split Screen": [462 + 60, 30 + 44 + 16 + 52], "Do Not Disturb": [462 + 190, 30 + 44 + 16 + 52], Glasspad: [462 + 320, 30 + 44 + 16 + 104 + 10 + 52],
  };
  const fingerTaps = Object.entries(taps).filter(([n]) => n !== "Reopen Closed Tab" || true).map(([n, t0]) => ({ n, t0, ...TAP(t, t0) })).filter(x => x.o > 0 || (x.ring > 0 && x.ring < 1));
  const land = (
    <div style={{ position: "absolute", inset: 0, background: "#FBFBF9" }}>
      {toActions ? <ActionsLand app={app} prevApp={prev} flip={flip} tiles={tiles} /> : null}
      {/* trackpad fingers */}
      {glide ? <><Finger x={fp[0]} y={fp[1]} o={dotO} s={rScreen * tap1.s} color={`rgba(26,26,26,${ink})`} r={23} />
        {[T.dotIn + 0.45, T.openTap, T.clickTap].map(t0 => <Ring key={t0} x={fp[0]} y={fp[1]} p={clamp((t - t0) / 0.6)} r={23 * rScreen} />)}</> : null}
      {sc > 0 ? [[-23, 0], [23, -12]].map(([dx, dy], i) => <Finger key={i} x={470 + dx} y={250 + dy + sy} o={sc} />) : null}
      {swO > 0 ? [[-46, 4], [0, -10], [46, 2]].map(([dx, dy], i) => <Finger key={i} x={540 + dx + sx} y={205 + dy} o={swO} />) : null}
      <Pill name="Trackpad" g="hand.point.up.left.fill" color="#1A1A1A" o={Math.max(pillO, toActions ? 0 : clamp(menu * 2))} s={lerp(1, 0.96, 1 - tapPill.press)} />
      <ModeMenu p={menu} current="Trackpad" hit="Actions" press={tapMenu.press} left={267} />
      {tapPill.o > 0 || (tapPill.ring > 0 && tapPill.ring < 1) ? <><Finger x={437} y={28} o={tapPill.o} s={tapPill.s} /><Ring x={437} y={28} p={tapPill.ring} /></> : null}
      {tapMenu.o > 0 || (tapMenu.ring > 0 && tapMenu.ring < 1) ? <><Finger x={mx} y={my} o={tapMenu.o} s={tapMenu.s} /><Ring x={mx} y={my} p={tapMenu.ring} /></> : null}
      {fingerTaps.map(x => { const [ax, ay] = ACT_AT[x.n]; return <React.Fragment key={x.n}><Finger x={ax} y={ay} o={x.o} s={x.s} /><Ring x={ax} y={ay} p={x.ring} /></React.Fragment>; })}
    </div>
  );
  return land;
};

/** The Remote pane leaves the phone and becomes the dark room of the next scene. */
const Grow: React.FC<{ t: number }> = ({ t }) => {
  const cam = camera(t), P = pose(LT.grow[0]);
  const r = COUCH_REMOTE;
  const toScreen = (x: number, y: number) => {
    const wx = P.cx + (x * PG.k + PG.inset - PH.W / 2) * P.sc, wy = P.cy + (y * PG.k + PG.inset - PW / 2) * P.sc;
    return [(wx - cam.cx) * cam.s + 960, (wy - cam.cy) * cam.s + 540];
  };
  const [x0, y0] = toScreen(r.x, r.y), [x1, y1] = toScreen(r.x + r.w, r.y + r.h);
  const u = E(t, LT.grow[0], LT.grow[1] - LT.grow[0], INOUT);
  const rad = 28 * PG.k * P.sc * cam.s;
  const c0 = [26, 26, 26], c1 = [43, 41, 37];
  const col = c0.map((v, i) => Math.round(lerp(v, c1[i], u)));
  return (
    <div style={{ position: "absolute", left: lerp(x0, 0, u), top: lerp(y0, 0, u), width: lerp(x1 - x0, 1920, u), height: lerp(y1 - y0, 1080, u),
      borderRadius: lerp(rad, 0, u), background: `rgb(${col.join(",")})`, opacity: E(t, LT.grow[0], 0.08) }} />
  );
};

/* ---------- the scene ---------- */
export const Desk: React.FC = () => {
  const frame = useCurrentFrame();
  const t = frame / 60;
  const cam = camera(t);
  // the phone's pose; its stand goes with it
  const P = pose(t);
  const visW = lerp(PW, PH.W, P.turn) * P.sc, visH = lerp(PW * 150 / 71.9, PW, P.turn) * P.sc;
  const standW = visW * lerp(0.78, 0.62, P.turn);
  const sU = standW / 0.62 / 21;
  const standY = P.cy + visH / 2 - 1.6 * sU;
  const hap = clamp((t - T.clickTap) / 0.55);
  const headP = E(t, T.head0, 0.7) * (1 - E(t, T.head1, 0.35));
  const capT = (id: string, a: number, b: number, color: string, text: string) => ({ id, a, b, color, text });
  const caps = [
    capT("trackpad", S.trackpad + 0.15, S.actions - 0.5, "#1A1A1A", "Trackpad"),
    capT("actions", S.actions + 0.15, S.pinned - 0.3, "#0A84FF", "Actions"),
    capT("pinned", S.pinned + 0.15, S.modes - 1.0, "#5E5CE6", "Pinned"),
  ];
  const modeCap = modesEvents(t).caption;
  const lay = layoutsEvents(t);
  const portrait = <ModesPhone t={t} />;
  const landscape = t < S.layouts - 0.2 ? <DeskPhone t={t} /> : <LayoutsPhone t={t} />;
  const mix = K(t, [[S.modes - 0.55, 1], [S.modes - 0.4, 0], [S.layouts + 0.1, 0], [S.layouts + 0.25, 1]], (u) => u);
  return (
    <div className="fm" style={{ background: "#E9E7E2" }}>
      <div className="fm-world" style={{ transform: `translate(960px, 540px) scale(${cam.s}) translate(${-cam.cx}px, ${-cam.cy}px)` }}>
        <div style={{ position: "absolute", left: -2000, right: -2000, top: DESK_Y, height: 3000, background: "#DEDBD5" }} />
        <MacBook x={LID.x} y={LID.y} lid={LID.w}><MacScreen t={t} /></MacBook>
        <Stand x={P.cx - standW / 2} y={standY} width={standW} />
        <Phone cx={P.cx} cy={P.cy} w={PW} turn={P.turn} scale={P.sc} land={landscape} port={portrait} mix={mix} />
        <Haptic x={PH.cx - PH.W / 2} y={PH.cy - PW / 2} w={PH.W} h={PW} p={hap} />
        {/* every tap on a button: a faint knock from the phone's edge */}
        {[T.reopen, T.run, T.blade, T.split, T.dnd, T.site, T.menuTap].map(t0 => {
          const p = clamp((t - t0 - 0.02) / 0.45);
          if (p <= 0 || p >= 1 || P.turn < 0.99) return null;
          return <div key={t0} style={{ position: "absolute", inset: 0, opacity: 0.55 }}><Haptic x={P.cx - visW / 2} y={P.cy - visH / 2} w={visW} h={visH} p={p} /></div>;
        })}
      </div>
      <div className="fm-head" style={{ top: 78, fontSize: 58, opacity: clamp(headP * 1.2), transform: `translateY(${(1 - OUT(clamp(headP))) * 16}px)` }}>A control surface for your Mac.</div>
      {caps.map(c => <Caption key={c.id} text={c.text} color={c.color} p={E(t, c.a, 0.6)} q={E(t, c.b, 0.35)} />)}
      {modeCap ? <Caption text={modeCap.text} color={modeCap.color} p={modeCap.p} q={modeCap.q} /> : null}
      {lay.caption ? <Caption text="Layouts" color="#0A84FF" p={lay.caption.p} q={lay.caption.q} /> : null}
      {t > LT.grow[0] ? <Grow t={t} /> : null}
    </div>
  );
};
export { Glyph };
