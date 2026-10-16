// Scenes 6 to 8: the couch (Remote), the handoff (Clipboard), two screens (Next Display).
import React from "react";
import { AbsoluteFill, Img, OffthreadVideo, Sequence, useCurrentFrame } from "remotion";
import { C, E, FPS, SFT, clamp01, lerp, phone, prog, spr, sstep } from "../core";
import { Footage, Track, cornersAt, lensPoint } from "../footage/Footage";
import couchTrack from "../tracks/couch-phone.json";
import handoffTrack from "../tracks/handoff.json";
import screensTrack from "../tracks/two-screens.json";
import { StudioPhone, phonePoint, PhonePose } from "../set/Studio";
import { NotesApp, PlayerApp, SafariApp } from "../mac/Apps";
import { Dock, MenuBar, Wallpaper } from "../mac/Desktop";
import { MacBookPro, MBP, EXT } from "../devices/Mac";
import { Label, Touch } from "../fx";
import { scene, word } from "../timeline";

const T = (sec: number) => Math.round(sec * FPS);
const PW = 1206, PH = 2622;

// ---------------------------------------------------------------------------------------
// 6. Remote: on the couch. Swipe to skip; type to search. The TV is the Mac's, playing a film.
// ---------------------------------------------------------------------------------------
const RE = scene("remote");
const R_TV1 = 3.9; // the TV
const R_SWIPE = word("remote2", 0) - RE.from - 0.05; // "Swipe"
const R_ZOOM1 = R_SWIPE - 0.35; // close on the phone
const R_TV2 = R_SWIPE + 0.62; // the TV skips
const R_TYPE = word("remote2", 3) - RE.from - 0.1; // "Type"
const R_ZOOM2 = R_TYPE - 0.3;
const R_TV3 = R_TYPE + 1.25; // the TV's search field
const R_WIDE = R_TV3 + 1.7; // back to her
const QUERY = "coast";
// keys of "coast" on the Remote's keyboard (u, v of the capture)
const KEYS: Record<string, [number, number]> = { c: [0.395, 0.815], o: [0.827, 0.694], a: [0.105, 0.755], s: [0.2, 0.755], t: [0.441, 0.694] };

const typedAt = (t: number) => QUERY.slice(0, Math.max(0, Math.min(QUERY.length, Math.floor((t - R_TYPE - 0.1) / 0.17) + 1)));

const RemoteScreen: React.FC<{ t: number; search: boolean }> = ({ t, search }) => {
  // inside the app's own pixels: the swipe on the touch surface, the taps on the keys
  const swipe = (lf: number) => {
    const u = clamp01((lf / FPS - R_SWIPE) / 0.36);
    return { x: lerp(0.28, 0.74, E.inOut(u)) * PW, y: 0.3 * PH };
  };
  const typed = typedAt(t);
  return (
    <div style={{ position: "relative", width: PW, height: PH }}>
      <Img src={phone(search ? "remote-search.png" : "remote.png")} style={{ width: PW, height: PH }} />
      {search ? (
        <>
          {/* what is typed shows in the field, as in the app */}
          {typed ? <div style={{ position: "absolute", left: 150, top: 1352, width: 800, height: 96, background: "#1F1F1F" }} /> : null}
          {typed ? <div style={{ position: "absolute", left: 180, top: 1370, fontFamily: SFT, fontSize: 46, color: "#F5F5F7" }}>{typed}</div> : null}
          {QUERY.split("").map((ch, i) => {
            const at = T(R_TYPE + 0.1 + i * 0.17);
            const [u, v] = KEYS[ch];
            return <Touch key={i} path={() => ({ x: u * PW, y: v * PH })} down={at} up={at + 5} size={150} ring={false} />;
          })}
        </>
      ) : (
        <Touch path={swipe} down={T(R_SWIPE)} up={T(R_SWIPE + 0.36)} size={170} />
      )}
    </div>
  );
};

const TV: React.FC<{ t: number; shot: number; skip: number; searchIn: number; search: string; push: number }> = ({ t, shot, skip, searchIn, search, push }) => {
  const w = 1180 * push, h = w * 0.5625;
  const x = 960 - w / 2, y = 470 - h / 2;
  return (
    <AbsoluteFill style={{ background: "radial-gradient(70% 60% at 20% 30%, #2A1E16 0%, #120D0A 60%, #070505 100%)" }}>
      {/* a lamp's warm pool on the wall, the TV's cool light in front of it */}
      <div style={{ position: "absolute", left: -200, top: -100, width: 900, height: 900, borderRadius: "50%", background: "radial-gradient(circle, rgba(255,170,100,0.22) 0%, rgba(255,170,100,0) 65%)" }} />
      <div style={{ position: "absolute", left: x - 140, top: y - 90, width: w + 280, height: h + 180, background: "radial-gradient(50% 50% at 50% 50%, rgba(120,150,255,0.16) 0%, rgba(120,150,255,0) 70%)", filter: "blur(20px)" }} />
      <div style={{ position: "absolute", left: x - 8, top: y - 8, width: w + 16, height: h + 16, borderRadius: 10, background: "#0B0B0C", boxShadow: "0 30px 80px rgba(0,0,0,0.6), inset 0 0 0 1px rgba(255,255,255,0.05)" }} />
      <div style={{ position: "absolute", left: x, top: y, width: w, height: h, overflow: "hidden", borderRadius: 3 }}>
        <div style={{ position: "absolute", left: 0, top: 0, width: 1920, height: 1080, transform: `scale(${w / 1920})`, transformOrigin: "0 0" }}>
          <PlayerApp w={1920} h={1080} t={t} shot={shot} controls={skip > 0 && skip < 1.2 ? 1 : 0} skip={skip} search={search} searchIn={searchIn} />
        </div>
      </div>
      {/* the console under it */}
      <div style={{ position: "absolute", left: 960 - w * 0.6, top: y + h + 120 * push, width: w * 1.2, height: 60 * push, borderRadius: 6, background: "linear-gradient(180deg, #3A2A20, #1E1611)" }} />
    </AbsoluteFill>
  );
};

export const Remote: React.FC = () => {
  const f = useCurrentFrame();
  const t = f / FPS;
  const tr = couchTrack as unknown as Track;
  // where the phone is in the clip, for the close ups
  const phoneCentre = (clipT: number) => {
    const q = cornersAt(tr, 0, clipT)!;
    return { cx: (q[0] + q[2] + q[4] + q[6]) / 4, cy: (q[1] + q[3] + q[5] + q[7]) / 4 };
  };
  const skip = t >= R_TV2 ? t - R_TV2 : 0;
  const shot = t >= R_TV2 + 0.12 ? 1 : 0;
  const searchIn = t >= R_TV3 ? spr(f, T(R_TV3), "settle") : 0;
  const search = t >= R_TV3 ? typedAt(Math.max(t, R_TYPE + 1.0)) : "";
  let content: React.ReactNode;
  if (t < R_TV1) {
    content = <Footage track={tr} from={0.4} lens={(lf) => ({ zoom: lerp(1.0, 1.18, E.glide(clamp01(lf / T(R_TV1)))), ...phoneCentre(0.4 + lf / FPS) })} grade="saturate(0.95) contrast(1.03)" screens={[{ w: PW, h: PH, exposure: 0.84, content: <RemoteScreen t={t} search={false} /> }]} />;
  } else if (t < R_ZOOM1) {
    content = <TV t={t} shot={0} skip={0} searchIn={0} search="" push={lerp(1.0, 1.06, clamp01((t - R_TV1) / (R_ZOOM1 - R_TV1)))} />;
  } else if (t < R_TV2) {
    content = <Footage track={tr} from={4.4 - R_ZOOM1} lens={(lf) => ({ zoom: 2.3, ...phoneCentre(4.4 - R_ZOOM1 + lf / FPS) })} grade="saturate(0.95) contrast(1.03)" screens={[{ w: PW, h: PH, exposure: 0.84, content: <RemoteScreen t={t} search={false} /> }]} />;
  } else if (t < R_ZOOM2) {
    content = <TV t={t} shot={shot} skip={skip} searchIn={0} search="" push={lerp(1.06, 1.1, clamp01((t - R_TV2) / (R_ZOOM2 - R_TV2)))} />;
  } else if (t < R_TV3) {
    content = <Footage track={tr} from={5.3 - R_ZOOM2} lens={(lf) => ({ zoom: 2.3, ...phoneCentre(5.3 - R_ZOOM2 + lf / FPS) })} grade="saturate(0.95) contrast(1.03)" screens={[{ w: PW, h: PH, exposure: 0.84, content: <RemoteScreen t={t} search /> }]} />;
  } else if (t < R_WIDE) {
    content = <TV t={t} shot={1} skip={0} searchIn={searchIn} search={search} push={lerp(1.1, 1.16, clamp01((t - R_TV3) / (R_WIDE - R_TV3)))} />;
  } else {
    content = <Footage track={tr} from={6.3 - R_WIDE} lens={(lf) => ({ zoom: lerp(1.12, 1.0, E.glide(clamp01((lf - T(R_WIDE)) / T(3)))), cx: 1900, cy: 1100 })} grade="saturate(0.95) contrast(1.03)" screens={[{ w: PW, h: PH, exposure: 0.84, content: <RemoteScreen t={R_TV3} search /> }]} />;
  }
  return (
    <AbsoluteFill style={{ background: C.black }}>
      {content}
      <Label text="Remote" inAt={T(0.4)} outAt={T(RE.len - 0.05)} />
    </AbsoluteFill>
  );
};

// ---------------------------------------------------------------------------------------
// 7. Clipboard: copied on the phone, pasted on the Mac.
// ---------------------------------------------------------------------------------------
const CL = scene("clipboard");
const C_PASTE = word("clipboard", 4) - CL.from + 0.05; // on "Paste"
const C_MAC = C_PASTE + 0.75;
const CLIP_TEXT = "Bring the prints for Mira, and the projector cable.";

export const Clipboard: React.FC = () => {
  const f = useCurrentFrame();
  const t = f / FPS;
  const tr = handoffTrack as unknown as Track;
  const land = t >= C_MAC ? prog(f, T(C_MAC + 0.25), 26, E.out) : 0;
  const lens = (lf: number) => ({ zoom: lerp(1.15, 1.32, E.glide(clamp01(lf / T(C_MAC)))), cx: 1150, cy: 1000 });
  // the copied text lifts off the phone toward the laptop (up and to the right, off frame)
  const lift = t >= C_PASTE + 0.05 ? prog(f, T(C_PASTE + 0.05), 34, E.in) : 0;
  const q = cornersAt(tr, 0, 1.0 + t);
  let chip: React.ReactNode = null;
  if (q && t < C_MAC && lift > 0) {
    const L = lens(f);
    const tl = lensPoint(tr, L, 1920, 1080, q[0], q[1]), br = lensPoint(tr, L, 1920, 1080, q[4], q[5]);
    const cx = (tl.x + br.x) / 2, cy = (tl.y + br.y) / 2;
    chip = (
      <div style={{ position: "absolute", left: lerp(cx - 170, 1500, lift), top: lerp(cy - 30, -140, lift), width: 340, padding: "14px 18px", borderRadius: 16, background: "rgba(255,255,255,0.94)", boxShadow: "0 20px 50px rgba(0,0,0,0.35)", fontFamily: SFT, fontSize: 19, color: "#1D1D1F", transform: `scale(${lerp(1, 0.8, lift)}) rotate(${lerp(0, 6, lift)}deg)`, opacity: 1 - sstep(0.85, 1, lift) }}>{CLIP_TEXT}</div>
    );
  }
  return (
    <AbsoluteFill style={{ background: C.black }}>
      {t < C_MAC ? (
        <>
          <Footage track={tr} from={1.0} lens={lens} grade="saturate(0.96) contrast(1.04) brightness(1.02)"
            screens={[{ w: PW, h: PH, exposure: 0.86, content: (
              <div style={{ position: "relative", width: PW, height: PH }}>
                <Img src={phone("clipboard-text.png")} style={{ width: PW, height: PH }} />
                <Touch path={() => ({ x: 0.205 * PW, y: 0.68 * PH })} down={T(C_PASTE - 0.08)} up={T(C_PASTE + 0.06)} size={150} color="rgba(30,30,30,0.55)" />
              </div>
            ) }]} />
          {chip}
        </>
      ) : (
        <AbsoluteFill style={{ background: "radial-gradient(80% 70% at 50% 40%, #2B2D33 0%, #121317 70%)" }}>
          <div style={{ position: "absolute", left: 960 - 760 * lerp(1, 1.06, clamp01((t - C_MAC) / 3)), top: 120 - 30 * clamp01((t - C_MAC) / 3), transform: `scale(${lerp(1, 1.06, clamp01((t - C_MAC) / 3))})`, transformOrigin: "50% 0%" }}>
            <MacBookPro width={1520} base>
              <Wallpaper kind="dusk" w={MBP.w} h={MBP.h} />
              <NotesApp x={170} y={70} w={1170} h={760} photoIn={0} />
              {/* the pasted line */}
              <div style={{ position: "absolute", left: 170 + 210 + 40, top: 70 + 58 + 92, width: 860, fontFamily: SFT, fontSize: 15, lineHeight: 1.55, color: "#3A3A3C", opacity: land, transform: `translateY(${(1 - land) * 10}px)` }}>
                <div style={{ height: 23 }} />
                <span style={{ background: `rgba(255,214,10,${0.35 * (1 - clamp01((t - C_MAC - 0.9) / 0.8))})`, borderRadius: 3 }}>{CLIP_TEXT}</span>
              </div>
              <MenuBar w={MBP.w} app="Notes" menus={["File", "Edit", "Format", "View", "Window", "Help"]} />
              <Dock w={MBP.w} h={MBP.h} size={58} running={["com.apple.finder", "com.apple.Notes"]} />
            </MacBookPro>
          </div>
          {/* the chip arriving from the phone's side (from the right) */}
          {land < 1 ? <div style={{ position: "absolute", left: lerp(1700, 740, land), top: lerp(820, 390, land), width: 340, padding: "14px 18px", borderRadius: 16, background: "rgba(255,255,255,0.94)", boxShadow: "0 20px 50px rgba(0,0,0,0.35)", fontFamily: SFT, fontSize: 19, color: "#1D1D1F", opacity: 1 - sstep(0.75, 1, land), transform: `scale(${lerp(0.9, 0.7, land)})` }}>{CLIP_TEXT}</div> : null}
        </AbsoluteFill>
      )}
      <Label text="Clipboard" inAt={T(0.4)} outAt={T(CL.len - 0.05)} />
    </AbsoluteFill>
  );
};

// ---------------------------------------------------------------------------------------
// 8. Two screens: in Displays on the phone, Safari is dragged from the Studio Display to the
//    MacBook; in the room, the window leaves the monitor and lands on the laptop.
// ---------------------------------------------------------------------------------------
const DI = scene("displays");
const D_PHONE = 1.35;
const D_DROP = word("displays", 6) - DI.from + 0.1; // the drop lands on "display"
const REC_MOVE = 6.82; // seconds into displays-move.mp4 where the app shows the move
const D_DRAG0 = D_DROP - 0.62;
const D_BACK = D_DROP + 0.55;
const D_MOVE = D_BACK + 0.1;

const MonitorScreen: React.FC<{ move: number }> = ({ move }) => (
  <div style={{ position: "absolute", inset: 0, width: EXT.w, height: EXT.h }}>
    <Wallpaper w={EXT.w} h={EXT.h} />
    <SafariApp x={200 - move * 1500} y={90} w={1100} h={680} />
    <MenuBar w={EXT.w} app={move > 0.5 ? "Finder" : "Safari"} />
    <Dock w={EXT.w} h={EXT.h} running={["com.apple.finder", "com.apple.Safari"]} />
  </div>
);
const LaptopScreen: React.FC<{ move: number }> = ({ move }) => (
  <div style={{ position: "absolute", inset: 0, width: MBP.w, height: MBP.h }}>
    <Wallpaper kind="dusk" w={MBP.w} h={MBP.h} />
    {move > 0 ? <SafariApp x={lerp(MBP.w + 40, 140, move)} y={70} w={1230} h={800} /> : null}
    <MenuBar w={MBP.w} app={move > 0.5 ? "Safari" : "Finder"} />
    <Dock w={MBP.w} h={MBP.h} size={58} running={["com.apple.finder", "com.apple.Safari"]} />
  </div>
);

export const Displays: React.FC = () => {
  const f = useCurrentFrame();
  const t = f / FPS;
  const out = t >= D_MOVE ? prog(f, T(D_MOVE), 22, E.in) : 0;
  const inn = t >= D_MOVE + 0.25 ? spr(f, T(D_MOVE + 0.25), "settle") : 0;
  const pose: PhonePose = { x: 960, y: 545, size: 470 * lerp(1.0, 1.07, E.glide(clamp01((t - D_PHONE) / (D_BACK - D_PHONE)))), rz: -5, orient: "portrait" };
  // the finger picks up Safari in the map (on the Studio Display) and drops it on the MacBook
  const drag = (lf: number) => {
    const u = E.inOut(clamp01((lf / FPS - D_DRAG0 - 0.08) / (D_DROP - D_DRAG0 - 0.08)));
    return phonePoint(pose, lerp(0.524, 0.232, u), lerp(0.259, 0.278, u));
  };
  const inRoom = t < D_PHONE || t >= D_BACK;
  return (
    <AbsoluteFill style={{ background: C.black }}>
      {inRoom ? (
        <Footage track={screensTrack as unknown as Track} from={0.3}
          lens={(lf) => (t < D_PHONE ? { zoom: lerp(1.0, 1.08, clamp01(lf / T(D_PHONE))), cx: 1500, cy: 1300 } : { zoom: lerp(1.08, 1.2, E.glide(clamp01((lf - T(D_BACK)) / T(3.5)))), cx: lerp(1550, 1050, E.inOut(clamp01((lf - T(D_MOVE)) / T(1.4)))), cy: 1300 })}
          grade="saturate(0.95) contrast(1.04)"
          screens={[
            { w: EXT.w, h: EXT.h, exposure: 0.9, content: <MonitorScreen move={out} /> },
            { w: MBP.w, h: MBP.h, exposure: 0.9, content: <LaptopScreen move={inn} /> },
          ]} />
      ) : (
        <AbsoluteFill style={{ background: "radial-gradient(70% 70% at 50% 40%, #3A3F45 0%, #1C1F23 60%, #0E1012 100%)" }}>
          <StudioPhone pose={pose} shadow={0.55}>
            <Sequence from={T(D_DROP) - T(REC_MOVE)} layout="none">
              <OffthreadVideo src={phone("displays-move.mp4")} muted style={{ width: 1206, height: 2622 }} />
            </Sequence>
          </StudioPhone>
          <Touch path={drag} down={T(D_DRAG0)} up={T(D_DROP)} size={90} />
        </AbsoluteFill>
      )}
      <Label text="Displays" inAt={T(0.4)} outAt={T(DI.len - 0.05)} />
    </AbsoluteFill>
  );
};

/** Sound cues in film seconds (scripts/v4/mix.py reads them through cues.ts). */
export const HOME_CUES = {
  tap: [CL.from + C_PASTE - 0.08, ...QUERY.split("").map((_, i) => RE.from + R_TYPE + 0.1 + i * 0.17)],
  key: QUERY.split("").map((_, i) => RE.from + R_TYPE + 0.1 + i * 0.17),
  drag: [[RE.from + R_SWIPE, RE.from + R_SWIPE + 0.36], [DI.from + D_DRAG0, DI.from + D_DROP]],
  whoosh: [CL.from + C_PASTE + 0.1, DI.from + D_MOVE + 0.05],
  skip: [RE.from + R_TV2],
  land: [CL.from + C_MAC + 0.25],
};
