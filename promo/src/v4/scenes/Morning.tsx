// Scenes 0 to 2 (bars 0 to 16): one continuous morning at the desk.
//  0 Open      a touch on glass wakes the Mac; the camera pulls back from the phone to the desk.
//  1 Actions   live action establishing shot (a real desk, the app on the phone), then the
//              CG desk: a click on Safari, and the phone's buttons re-lay themselves.
//  2 Pinned    the phone, low and close; Split Screen snaps the windows; Do Not Disturb.
import React from "react";
import { AbsoluteFill, Freeze, Img, OffthreadVideo, Sequence, useCurrentFrame } from "remotion";
import { CameraMotionBlur } from "@remotion/motion-blur";
import { C, E, FPS, SF, clamp01, lerp, phone, prog, s, spr, sstep } from "../core";
import { DeskSet, DESK } from "../set/Desk";
import { camPath, project, Cam, CamKey } from "../set/Stage3D";
import { Dock, MenuBar, Pointer, Wallpaper, Banner } from "../mac/Desktop";
import { MailApp, SafariApp } from "../mac/Apps";
import { EXT, MBP } from "../devices/Mac";
import { Footage, Track } from "../footage/Footage";
import deskTrack from "../tracks/desk-topdown.json";
import { Label, Sweep, Touch } from "../fx";
import { scene, word } from "../timeline";

const T = (sec: number) => Math.round(sec * FPS);

// ---------- Key moments (film seconds), tied to the voice ----------
const OPEN = scene("open"), ACT = scene("actions"), PIN = scene("pinned");
const T_WAKE = 1.55; // the first touch wakes the Mac
const T_FOOT_IN = ACT.from; // the real desk
const T_CG_IN = ACT.from + 3.45; // back to the CG desk
const T_CLICK = word("actions2", 1) + 0.12; // the pointer clicks Safari on "Safari"
const REC_SWITCH = 6.95; // seconds into actions-switch.mp4 where the app shows the new front app
const T_SPLIT = word("pinned2", 0) + 0.05;
const T_BANNER = T_SPLIT + 0.75;
const T_DND = word("pinned2", 2) + 0.1;

// ---------- Phone content ----------
/** The phone's screen in the CG desk: the real recording, timed so its switch follows the click. */
const PhoneScreen: React.FC<{ t: number }> = ({ t }) => {
  if (t < T_CG_IN - 0.5) {
    // before the click the app shows Mail in front (a held frame of the recording)
    return (
      <Freeze frame={T(5.2)}>
        <OffthreadVideo src={phone("actions-switch.mp4")} muted style={{ width: 2622, height: 1206 }} />
      </Freeze>
    );
  }
  if (t < PIN.from + 0.5) {
    // the phone answers as the lens arrives on it (the app's own switch, a beat after the click)
    const startRec = REC_SWITCH - (T_CLICK + 0.5 - (T_CG_IN - 0.5));
    return (
      <Sequence from={T(T_CG_IN - 0.5)} layout="none">
        <OffthreadVideo src={phone("actions-switch.mp4")} startFrom={T(startRec)} muted style={{ width: 2622, height: 1206 }} />
      </Sequence>
    );
  }
  return <Img src={phone("pinned.png")} style={{ width: 2622, height: 1206 }} />;
};

// Tile centres in the landscape capture (px).
const TILE = { split: { x: 1562, y: 430 }, dnd: { x: 1868, y: 430 } };

// ---------- Mac screens ----------
const DisplayScreen: React.FC<{ t: number; wake: number }> = ({ t, wake }) => {
  const safariFront = t >= T_CLICK;
  const sp = t >= T_SPLIT ? spr(T(t), T(T_SPLIT) + 6, "settle") : 0;
  const top = 30 + 8, h = EXT.h - top - 92;
  const mail = { x: lerp(420, EXT.w / 2 + 4, sp), y: lerp(140, top, sp), w: lerp(1040, EXT.w / 2 - 12, sp), h: lerp(640, h, sp) };
  const saf = { x: lerp(180, 8, sp), y: lerp(80, top, sp), w: lerp(1000, EXT.w / 2 - 12, sp), h: lerp(660, h, sp) };
  const bannerIn = t >= T_BANNER ? spr(T(t), T(T_BANNER), "snap") : 0;
  const bannerOut = t >= T_DND + 0.12 ? prog(T(t), T(T_DND + 0.12), 16, E.in) : 0;
  const focus = t >= T_DND + 0.1;
  // pointer: arrives from the right, travels to the Safari window, clicks
  const pIn = prog(T(t), T(T_CLICK - 1.3), 20, E.out);
  const pm = prog(T(t), T(T_CLICK - 1.1), T(1.1), E.inOut);
  const ptr = { x: lerp(1300, 300, pm), y: lerp(620, 300, pm) };
  const press = t >= T_CLICK && t < T_CLICK + 0.14 ? 1 : 0;
  return (
    <div style={{ position: "absolute", inset: 0, opacity: wake }}>
      <Wallpaper w={EXT.w} h={EXT.h} />
      {safariFront ? <MailApp {...mail} active={false} /> : <SafariApp {...saf} active={false} />}
      {safariFront ? <SafariApp {...saf} /> : <MailApp {...mail} />}
      <MenuBar w={EXT.w} app={safariFront ? "Safari" : "Mail"} focus={focus} menus={safariFront ? ["File", "Edit", "View", "History", "Bookmarks", "Window", "Help"] : ["File", "Edit", "View", "Mailbox", "Message", "Format", "Window", "Help"]} />
      <Dock w={EXT.w} h={EXT.h} running={["com.apple.finder", "com.apple.mail", "com.apple.Safari", "com.apple.Notes"]} />
      {bannerIn > 0 && bannerOut < 1 ? (
        <Banner x={EXT.w - 344 - 14 + (1 - bannerIn) * 360 + bannerOut * 360} y={30 + 10} iconId="com.apple.MobileSMS" title="Ana Ruiz" body="Are we still on for Saturday?" style={{ opacity: 1 - bannerOut * 0.5 }} />
      ) : null}
      {t > T_CLICK - 1.3 && t < T_SPLIT - 0.4 ? <Pointer x={ptr.x} y={ptr.y} scale={1.25} press={press} opacity={pIn * (1 - prog(T(t), T(T_SPLIT - 0.8), 20, E.in))} /> : null}
    </div>
  );
};

const LaptopScreen: React.FC<{ wake: number }> = ({ wake }) => (
  <div style={{ position: "absolute", inset: 0, opacity: wake }}>
    <Wallpaper kind="dusk" w={MBP.w} h={MBP.h} />
    <MenuBar w={MBP.w} app="Finder" menus={["File", "Edit", "View", "Go", "Window", "Help"]} />
    <Dock w={MBP.w} h={MBP.h} size={58} running={["com.apple.finder", "com.apple.Music"]} />
  </div>
);

// ---------- Camera ----------
const P = DESK.phone;
const phoneC = { x: P.x, y: -P.lift - P.short / 2 + 6, z: P.z + 6 };
const displayC = { x: 0, y: -620, z: DESK.display.z };
/** A point on the phone's screen (capture px, landscape) in world space: the same transform
 *  the phone's Obj gets (bottom centre pivot, rotateY then the lean back). */
const phoneScreenWorld = (px: number, py: number) => {
  const mm = P.short / 71.9, pw = P.short * (150 / 71.9), inset = 2 * mm;
  const X = inset + (px / 2622) * (pw - 2 * inset) - pw / 2;
  const Y = inset + (py / 1206) * (P.short - 2 * inset) - P.short;
  const rx = (P.tilt * Math.PI) / 180, ry = (P.ry * Math.PI) / 180;
  const y1 = Y * Math.cos(rx), z1 = Y * Math.sin(rx);
  return { x: P.x + X * Math.cos(ry) + z1 * Math.sin(ry), y: -P.lift + y1, z: P.z - X * Math.sin(ry) + z1 * Math.cos(ry) };
};

// The phone's screen centre and the direction it faces (lean back 16, turned 22 to the left).
const SC = phoneScreenWorld(1311, 603);
const N = { x: -0.36, y: -0.28, z: 0.89 };
const along = (d: number, dy = 0, dx = 0) => ({ x: SC.x + N.x * d + dx, y: SC.y + N.y * d + dy, z: SC.z + N.z * d });
const DISP = { x: 0, y: -560, z: DESK.display.z };
const BANNER = { x: 330, y: -770, z: DESK.display.z };
const WIDE = { pos: { x: 260, y: -560, z: 2080 }, look: { x: 90, y: -330, z: 0 } };

const KEYS: CamKey[] = [
  // Open: inside the glass, the dot; then one long crane back and up to the whole desk
  { t: 0, pos: along(70), look: SC, fov: 30, aperture: 26, focus: 900 },
  { t: 1.25, pos: along(92), look: SC, fov: 30, aperture: 22 },
  { t: 6.62, pos: WIDE.pos, look: WIDE.look, fov: 34, aperture: 6, ease: E.glide },
  // Actions (CG from T_CG_IN): over the phone's shoulder, the display sharp behind it; the
  // click lands on the display, then focus racks to the phone as its buttons change
  { t: T_CG_IN - 0.45, pos: { x: 650, y: -70, z: 650 }, look: { x: 380, y: -240, z: 0 }, fov: 44, aperture: 9, focus: 1110 },
  { t: T_CLICK + 0.05, pos: { x: 628, y: -70, z: 614 }, look: { x: 389, y: -238, z: 0 }, fov: 44, aperture: 9, focus: 1090, ease: E.linear },
  { t: T_CLICK + 0.5, pos: { x: 618, y: -71, z: 598 }, look: { x: 405, y: -232, z: 10 }, fov: 43.5, aperture: 11, focus: 385, ease: E.inOut },
  { t: T_CLICK + 1.6, pos: { x: 600, y: -75, z: 560 }, look: { x: 470, y: -200, z: 60 }, fov: 42, aperture: 11, focus: 360, ease: E.inOut },
  { t: PIN.from, pos: along(300, 0, 40), look: SC, fov: 30, aperture: 12, focus: 300, ease: E.inOut },
  // Pinned: low and close on the phone, slowly orbiting
  { t: T_SPLIT - 0.02, pos: along(220, 64, -10), look: { x: SC.x, y: SC.y - 6, z: SC.z }, fov: 30, aperture: 14, ease: E.inOut },
  // whip to the display as Split Screen lands
  { t: T_SPLIT + 0.38, pos: { x: 260, y: -540, z: 950 }, look: DISP, fov: 34, aperture: 6, ease: E.inOut },
  // push toward the top right corner, where the banner comes in
  { t: T_DND + 0.5, pos: { x: 380, y: -700, z: 620 }, look: BANNER, fov: 34, aperture: 6, ease: E.inOut },
  // and out to the whole desk to close the morning
  { t: PIN.to + 0.3, pos: { x: 300, y: -520, z: 1900 }, look: { x: 120, y: -360, z: 0 }, fov: 34, aperture: 6, ease: E.glide },
];

const camAt = (t: number): Cam => camPath(KEYS, t);

/** The CG desk at this frame: devices, screens, the touches on the phone's glass, the light. */
const CGDesk: React.FC = () => {
  const f = useCurrentFrame();
  const t = f / FPS;
  const cam = camAt(t);
  const wake = clamp01(prog(f, T(T_WAKE), 40, E.out));
  // the touch that opens the film: on the phone's glass, in world space -> on screen
  const tp = project(cam, phoneScreenWorld(1311, 603));
  // the display's own light, blooming slightly into the room
  const dc = project(cam, { x: 0, y: -560, z: DESK.display.z });
  return (
    <AbsoluteFill>
      <DeskSet cam={cam} light={lerp(0.4, 1, wake)}
        display={<DisplayScreen t={t} wake={wake} />}
        laptop={<LaptopScreen wake={wake} />}
        phone={<div style={{ opacity: clamp01(prog(f, T(T_WAKE - 0.35), 24, E.out)) }}><PhoneScreen t={t} /></div>}
        phoneSweep={t > PIN.from + 0.6 && t < PIN.from + 1.6 ? (t - PIN.from - 0.6) : -1} />
      <AbsoluteFill style={{ pointerEvents: "none", mixBlendMode: "screen", opacity: 0.5 * wake, background: `radial-gradient(${Math.max(200, 900 * dc.k)}px ${Math.max(120, 520 * dc.k)}px at ${dc.x}px ${dc.y}px, rgba(190,170,255,0.18) 0%, rgba(190,170,255,0) 100%)` }} />
      {/* dawn: a soft warm beam from the window, back right */}
      <AbsoluteFill style={{ pointerEvents: "none", mixBlendMode: "screen", opacity: 0.55 * lerp(0.4, 1, wake), background: "linear-gradient(118deg, rgba(255,190,140,0) 38%, rgba(255,190,140,0.10) 52%, rgba(255,190,140,0) 66%)" }} />
      {t < 4 ? <Touch path={() => ({ x: tp.x, y: tp.y })} down={T(0.35)} up={T(T_WAKE)} size={Math.max(40, 22 * tp.k)} /> : null}
      {t > T_SPLIT - 0.4 && t < T_SPLIT + 0.8 ? (() => { const q = project(cam, phoneScreenWorld(TILE.split.x, TILE.split.y)); return <Touch path={() => ({ x: q.x, y: q.y })} down={T(T_SPLIT - 0.12)} up={T(T_SPLIT + 0.02)} size={Math.max(30, 60 * q.k)} />; })() : null}
      {t > T_DND - 0.4 && t < T_DND + 0.8 ? (() => { const q = project(cam, phoneScreenWorld(TILE.dnd.x, TILE.dnd.y)); return <Touch path={() => ({ x: q.x, y: q.y })} down={T(T_DND - 0.12)} up={T(T_DND + 0.02)} size={Math.max(24, 60 * q.k)} />; })() : null}
    </AbsoluteFill>
  );
};

export const Morning: React.FC = () => {
  const f = useCurrentFrame();
  const t = f / FPS;
  const cgVisible = t < T_FOOT_IN + 0.45 || t >= T_CG_IN - 0.45;
  const footVisible = t >= T_FOOT_IN - 0.45 && t < T_CG_IN + 0.45;
  // cross blur dissolves between live action and the CG desk
  const toFoot = sstep(T_FOOT_IN - 0.45, T_FOOT_IN + 0.15, t);
  const toCg = sstep(T_CG_IN - 0.35, T_CG_IN + 0.3, t);
  const footOpacity = toFoot * (1 - toCg);
  return (
    <AbsoluteFill style={{ background: C.black }}>
      {cgVisible ? (
        <AbsoluteFill style={{ filter: footVisible ? `blur(${(footOpacity * 14).toFixed(2)}px)` : undefined }}>
          {/* the whip to the display on Split Screen is shot with a real shutter: motion blur */}
          {t > T_SPLIT && t < T_SPLIT + 0.5 ? (
            <CameraMotionBlur shutterAngle={200} samples={7}>
              <CGDesk />
            </CameraMotionBlur>
          ) : (
            <CGDesk />
          )}
        </AbsoluteFill>
      ) : null}
      {footVisible ? (
        <AbsoluteFill style={{ opacity: footOpacity, filter: `blur(${((1 - footOpacity) * 14).toFixed(2)}px)` }}>
          <Sequence from={T(T_FOOT_IN - 0.45)} layout="none">
            <Footage track={deskTrack as unknown as Track} from={0.6}
              lens={(lf) => ({ zoom: lerp(1.0, 1.22, E.glide(clamp01(lf / T(4.3)))), cx: 2100, cy: 1080 })}
              grade="saturate(0.92) contrast(1.04) brightness(0.97)"
              screens={[{ w: 1206, h: 2622, exposure: 0.86, content: <Img src={phone("actions-mail.png")} style={{ width: 1206, height: 2622 }} /> }]} />
          </Sequence>
        </AbsoluteFill>
      ) : null}
      {/* the name, once, over the wide desk */}
      <Wordmark t={t} />
      <Label text="Actions" inAt={T(T_FOOT_IN + 0.4)} outAt={T(PIN.from - 0.1)} />
      <Label text="Pinned" inAt={T(PIN.from + 0.4)} outAt={T(PIN.to - 0.1)} />
      <Sweep at={T(PIN.from + 0.5)} w={1920} h={1080} strength={0.04} />
    </AbsoluteFill>
  );
};

const Wordmark: React.FC<{ t: number }> = ({ t }) => {
  const a = sstep(3.7, 4.5, t) * (1 - sstep(5.9, 6.5, t));
  if (a <= 0) return null;
  return (
    <div style={{ position: "absolute", left: 0, right: 0, bottom: 120, textAlign: "center", fontFamily: SF, fontSize: 64, fontWeight: 600, letterSpacing: "-0.03em", color: "#F5F5F7", opacity: a, transform: `translateY(${(1 - a) * 10}px)`, textShadow: "0 2px 30px rgba(0,0,0,0.5)" }}>Glasspad</div>
  );
};

export const MORNING_LEN = Math.round(scene("pinned").to * FPS);

/** Sound cues in film seconds (scripts/v4/mix.py reads them through cues.ts). */
export const MORNING_CUES = {
  tap: [0.35, T_SPLIT - 0.12, T_DND - 0.12],
  click: [T_CLICK],
  whoosh: [T_FOOT_IN - 0.3, T_CG_IN - 0.3, T_SPLIT + 0.05],
  chime: [T_BANNER],
  wake: [T_WAKE],
};
