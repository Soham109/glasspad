// Scenes 3 to 5: Layouts (focus), Final Cut (the edit suite), Present (the stage).
import React from "react";
import { AbsoluteFill, Img, Sequence, useCurrentFrame } from "remotion";
import { C, E, FPS, SF, SFT, clamp01, lerp, phone, prog, spr, sstep } from "../core";
import { Footage, Track, cornersAt, lensPoint } from "../footage/Footage";
import { quadPoint } from "../footage/homography";
import focusTrack from "../tracks/focus-laptop.json";
import editTrack from "../tracks/edit-suite.json";
import handsTrack from "../tracks/hands-phone.json";
import { StudioPhone, phonePoint, PhonePose } from "../set/Studio";
import { EditorApp, Slide } from "../mac/Apps";
import { MenuBar, Wallpaper, Dock, Window } from "../mac/Desktop";
import { MBP } from "../devices/Mac";
import { Label, Touch, Sweep } from "../fx";
import { scene, word, lineAt } from "../timeline";

const T = (sec: number) => Math.round(sec * FPS);
const DESK_BG = "radial-gradient(70% 70% at 45% 40%, #3B2B20 0%, #241A13 60%, #120D0A 100%)";

// ---------------------------------------------------------------------------------------
// 3. Layouts: someone writing at a laptop; the phone beside it splits into two tools.
// ---------------------------------------------------------------------------------------
const LAY = scene("layouts");
const L_PHONE = 1.85; // local: cut to the phone
const L_DRAG0 = word("layouts", 0) - LAY.from + 0.02; // finger lands on "Split"
const L_DRAG1 = word("layouts", 3) - LAY.from + 0.15; // and lets go after "itself"
const L_BACK = L_DRAG1 + 1.75; // back to her, still writing
const DRAG_SHARES = [4, 8, 12, 16, 20, 24, 28, 32, 36, 40, 44, 47, 50];

const Writer: React.FC<{ t: number }> = ({ t }) => {
  const text = "Open with what changed since spring, then the questions that are still open. Keep it short, and leave time for the demo.";
  const n = Math.floor(clamp01((t - 0.2) / 3.2) * text.length);
  return (
    <div style={{ position: "absolute", inset: 0, width: MBP.w, height: MBP.h }}>
      <Wallpaper kind="dusk" w={MBP.w} h={MBP.h} />
      <Window x={120} y={60} w={1270} h={830} bar={52} title="Talk outline">
        <div style={{ position: "absolute", inset: 0, background: "#fff", padding: "60px 120px", fontFamily: SFT, color: "#1D1D1F" }}>
          <div style={{ fontSize: 34, fontWeight: 700, letterSpacing: "-0.02em" }}>Talk outline</div>
          <div style={{ fontSize: 21, lineHeight: 1.6, marginTop: 22, color: "#3A3A3C" }}>Thursday, the third floor.</div>
          <div style={{ fontSize: 21, lineHeight: 1.6, marginTop: 10 }}>{text.slice(0, n)}<span style={{ display: "inline-block", width: 2, height: 26, background: "#0A84FF", verticalAlign: "-4px", opacity: Math.floor(t * 2) % 2 ? 1 : 0.2 }} /></div>
        </div>
      </Window>
      <MenuBar w={MBP.w} app="Pages" menus={["File", "Edit", "Insert", "Format", "Arrange", "View", "Window", "Help"]} />
      <Dock w={MBP.w} h={MBP.h} size={58} running={["com.apple.finder", "com.apple.Music"]} />
    </div>
  );
};

export const Layouts: React.FC = () => {
  const f = useCurrentFrame();
  const t = f / FPS;
  // the phone, flat on the walnut desk, seen from above; a slow turn and push
  const pose: PhonePose = { x: 960 + lerp(20, -10, t / LAY.len), y: 540, size: 420 * lerp(1.0, 1.08, E.glide(clamp01((t - L_PHONE) / (LAY.len - L_PHONE)))), rz: lerp(-7, -4, t / LAY.len), orient: "landscape" };
  // which capture is on screen: Actions alone, then the clock dragged in from the left edge
  // (the app's own frames for each place of the line), then the clock beside Actions
  let img = "pinned.png";
  if (t >= L_DRAG0 + 0.12) {
    const u = clamp01((t - L_DRAG0 - 0.12) / (L_DRAG1 - L_DRAG0 - 0.12));
    const i = Math.min(DRAG_SHARES.length - 1, Math.floor(E.inOut(u) * DRAG_SHARES.length));
    img = `layout-clock-drag-${String(DRAG_SHARES[i]).padStart(3, "0")}.png`;
  }
  if (t >= L_DRAG1 + 0.05) img = "layout-clock.png";
  const share = t < L_DRAG0 ? 0.015 : lerp(0.015, 0.5, E.inOut(clamp01((t - L_DRAG0 - 0.12) / (L_DRAG1 - L_DRAG0 - 0.12))));
  const fingerAt = () => phonePoint(pose, share, 0.5);
  const cut = sstep(L_PHONE - 0.2, L_PHONE + 0.2, t) * (1 - sstep(L_BACK - 0.2, L_BACK + 0.2, t));
  return (
    <AbsoluteFill style={{ background: C.black }}>
      {t < L_PHONE + 0.3 || t > L_BACK - 0.3 ? (
        <AbsoluteFill style={{ opacity: 1 - cut }}>
          <Footage track={focusTrack as unknown as Track} from={0.6}
            lens={(lf) => (lf < T(L_BACK - 0.3) ? { zoom: lerp(1.04, 1.16, E.glide(clamp01(lf / T(2.2)))), cx: 1300, cy: 1050 } : { zoom: lerp(1.3, 1.22, E.glide(clamp01((lf - T(L_BACK)) / T(2.5)))), cx: 2300, cy: 1150 })}
            grade="saturate(0.95) contrast(1.03)"
            screens={[{ w: MBP.w, h: MBP.h, exposure: 0.9, content: <Writer t={t} /> }]} />
        </AbsoluteFill>
      ) : null}
      {t > L_PHONE - 0.3 && t < L_BACK + 0.3 ? (
        <AbsoluteFill style={{ background: DESK_BG, opacity: cut }}>
          <AbsoluteFill style={{ background: "repeating-linear-gradient(100deg, rgba(255,255,255,0.012) 0 2px, rgba(0,0,0,0.03) 3px 11px)" }} />
          <StudioPhone pose={pose} shadow={0.6}>
            <Img src={phone(img)} style={{ width: 2622, height: 1206 }} />
          </StudioPhone>
          <Touch path={fingerAt} down={T(L_DRAG0)} up={T(L_DRAG1)} size={64} />
          {/* window light falling across the desk */}
          <AbsoluteFill style={{ background: "linear-gradient(115deg, rgba(255,200,150,0) 30%, rgba(255,200,150,0.07) 50%, rgba(255,200,150,0) 70%)" }} />
        </AbsoluteFill>
      ) : null}
      <Label text="Layouts" inAt={T(0.4)} outAt={T(LAY.len - 0.05)} />
    </AbsoluteFill>
  );
};

// ---------------------------------------------------------------------------------------
// 4. Final Cut: a dark edit suite; the Blade button on the phone cuts the clip on screen.
// ---------------------------------------------------------------------------------------
const ED = scene("edit");
const E_PHONE = 2.6; // cut to the phone
const E_TAP = word("edit", 11) - ED.from + 0.05; // on "thumb"
const E_BACK = E_TAP + 0.55; // back to the room to see the cut land
const EDITOR = { w: 2100, h: 900 };

export const Edit: React.FC = () => {
  const f = useCurrentFrame();
  const t = f / FPS;
  const cutT = t >= E_BACK - 0.1 ? spr(f, T(E_BACK + 0.05), "pop") : 0;
  const pose: PhonePose = { x: 1010, y: 560, size: 560 * lerp(1.02, 1.12, E.glide(clamp01((t - E_PHONE) / (E_BACK - E_PHONE)))), rz: -14, orient: "portrait" };
  const editor = <EditorApp x={0} y={0} w={EDITOR.w} h={EDITOR.h} t={t} cut={cutT} playhead={0.46} />;
  const inRoom = t < E_PHONE || t >= E_BACK;
  const blade = phonePoint(pose, 0.245, 0.267);
  return (
    <AbsoluteFill style={{ background: C.black }}>
      {inRoom ? (
        <Footage track={editTrack as unknown as Track} from={t < E_PHONE ? 0.8 : 0.8 + E_PHONE + 0.4}
          lens={(lf) => ({ zoom: t < E_PHONE ? lerp(1.02, 1.12, E.glide(clamp01(lf / T(E_PHONE)))) : lerp(1.18, 1.26, E.glide(clamp01((lf - T(E_BACK)) / T(2.5)))), cx: 1300, cy: 820 })}
          grade="saturate(1.02) contrast(1.05)"
          screens={[{ w: EDITOR.w, h: EDITOR.h, exposure: 0.8, content: editor }]} />
      ) : (
        <AbsoluteFill style={{ background: "radial-gradient(60% 70% at 40% 30%, #1E2C2A 0%, #0D1112 60%, #050607 100%)" }}>
          {/* the keyboard's glow at the edge of the frame, as in the room */}
          <AbsoluteFill style={{ background: "radial-gradient(40% 25% at 85% 95%, rgba(255,90,160,0.18) 0%, rgba(255,90,160,0) 100%), radial-gradient(35% 30% at 10% 10%, rgba(80,220,200,0.12) 0%, rgba(80,220,200,0) 100%)" }} />
          <StudioPhone pose={pose} shadow={0.7}>
            <Img src={phone("finalcut.png")} style={{ width: 1206, height: 2622 }} />
          </StudioPhone>
          <Touch path={() => blade} down={T(E_TAP - 0.08)} up={T(E_TAP + 0.06)} size={110} />
        </AbsoluteFill>
      )}
      <Label text="Final Cut Pro" inAt={T(0.4)} outAt={T(ED.len - 0.05)} />
    </AbsoluteFill>
  );
};

// ---------------------------------------------------------------------------------------
// 5. Present: the stage. Next on the phone (real hands), the slide changes, the laser points.
// ---------------------------------------------------------------------------------------
const PR = scene("present");
const HANDS_FROM = 6.55; // seconds into the hands clip
const HANDS_PRESS = 7.42; // the finger lands on Next in the clip
const P_PRESS = word("present", 5) - PR.from + 0.05; // Next lands on "slides"
const P_HANDS = P_PRESS - (HANDS_PRESS - HANDS_FROM); // cut to the hands
const P_STAGE = P_PRESS + 1.25; // back to the stage
const P_LASER = word("present", 9) - PR.from - 0.25; // "points"

const Stage: React.FC<{ t: number; slide: number; laser: number; push: number; focusScreen: number }> = ({ t, slide, laser, push, focusScreen }) => {
  const sw = 1240 * push, sh = sw * 0.5625;
  const sx = 960 - sw / 2, sy = 470 - sh / 2 - (push - 1) * 120;
  // the laser walks along the horizon of the coast photograph
  const lu = lerp(0.18, 0.74, E.inOut(clamp01(laser / 1.6)));
  const lv = 0.58 + Math.sin(laser * 5) * 0.012;
  return (
    <AbsoluteFill style={{ background: "radial-gradient(80% 60% at 50% 38%, #1A1E2A 0%, #0A0B10 55%, #030304 100%)" }}>
      {/* the screen and its light on the stage floor */}
      <div style={{ position: "absolute", left: sx - 30, top: sy + sh + 40, width: sw + 60, height: 300, background: "radial-gradient(50% 40% at 50% 0%, rgba(150,170,255,0.22) 0%, rgba(150,170,255,0) 100%)", filter: "blur(10px)" }} />
      <div style={{ position: "absolute", left: sx, top: sy, width: sw, height: sh, overflow: "hidden", boxShadow: "0 0 120px rgba(140,160,255,0.25)", filter: focusScreen < 1 ? `blur(${(1 - focusScreen) * 6}px)` : undefined }}>
        <div style={{ position: "absolute", left: 0, top: 0, width: 1920, height: 1080, transform: `scale(${sw / 1920})`, transformOrigin: "0 0" }}>
          <Slide w={1920} h={1080} n={0} t={t} />
          <div style={{ position: "absolute", inset: 0, opacity: slide }}>
            <Slide w={1920} h={1080} n={1} t={t} />
          </div>
          {laser > 0 ? (
            <div style={{ position: "absolute", left: lu * 1920 - 22, top: lv * 1080 - 22, width: 44, height: 44, borderRadius: 44, background: "radial-gradient(circle, #FFE9E6 0%, #FF3B30 35%, rgba(255,59,48,0.35) 60%, rgba(255,59,48,0) 72%)", opacity: clamp01(laser * 4) }} />
          ) : null}
        </div>
      </div>
      {/* the stage edge and a lectern-less, empty stage: the presenter is the camera */}
      <div style={{ position: "absolute", left: 0, right: 0, top: sy + sh + 120 * push, height: 2, background: "rgba(255,255,255,0.06)" }} />
      {/* audience heads in silhouette, close to the lens */}
      {Array.from({ length: 9 }).map((_, i) => {
        const x = i * 240 - 60 + (push - 1) * (i - 4) * 160;
        const s = 1 + (push - 1) * 1.6;
        return <div key={i} style={{ position: "absolute", left: x, top: 900 + (i % 2) * 40 - (s - 1) * 40, width: 210 * s, height: 260 * s, borderRadius: "48% 48% 30% 30%", background: "#020203", filter: "blur(6px)", opacity: 0.95 }} />;
      })}
    </AbsoluteFill>
  );
};

export const Present: React.FC = () => {
  const f = useCurrentFrame();
  const t = f / FPS;
  const slide = t >= P_PRESS + 0.05 ? prog(f, T(P_PRESS + 0.05), 20, E.inOut) : 0;
  const laser = t >= P_LASER ? t - P_LASER : 0;
  const push = t < P_HANDS ? lerp(1.0, 1.06, E.glide(clamp01(t / P_HANDS))) : lerp(1.06, 1.22, E.glide(clamp01((t - P_STAGE) / (PR.len - P_STAGE))));
  const inHands = t >= P_HANDS && t < P_STAGE;
  // the timer starts on the first Next, as the app does
  const running = t >= P_PRESS;
  const secs = running ? Math.floor(t - P_PRESS) : 0;
  return (
    <AbsoluteFill style={{ background: C.black }}>
      {!inHands ? <Stage t={t} slide={slide} laser={laser} push={push} focusScreen={1} /> : null}
      {inHands ? (
        <AbsoluteFill>
          {/* behind the hands: the stage, out of focus, its slide changing */}
          <AbsoluteFill style={{ filter: "blur(9px)", transform: "scale(1.15)" }}>
            <Stage t={t} slide={slide} laser={0} push={1.25} focusScreen={1} />
          </AbsoluteFill>
          <Sequence from={T(P_HANDS)} layout="none">
            <HandsWithApp from={HANDS_FROM} t0={P_HANDS} t={t} timer={secs} running={running} />
          </Sequence>
        </AbsoluteFill>
      ) : null}
      <Label text="Present" inAt={T(0.4)} outAt={T(PR.len - 0.05)} />
    </AbsoluteFill>
  );
};

/** The keyed hands holding a phone, with the Present screen on it. */
const HandsWithApp: React.FC<{ from: number; t0: number; t: number; timer: number; running: boolean }> = ({ from, timer, running }) => {
  const tr = handsTrack as unknown as Track;
  return (
    <AbsoluteFill style={{ transform: "translate(140px, 70px) scale(1.25)", transformOrigin: "50% 60%" }}>
      <Footage track={tr} from={from} plate={false}
        grade="brightness(0.82) contrast(1.06) saturate(0.95)"
        screens={[{ w: 1206, h: 2622, exposure: 0.88, content: (
          <div style={{ position: "relative", width: 1206, height: 2622 }}>
            <Img src={phone("present.png")} style={{ width: 1206, height: 2622 }} />
            {/* the running clock, drawn the way the app draws it once the timer starts */}
            <div style={{ position: "absolute", left: 40, top: 375, width: 300, height: 140, background: "#141414" }} />
            <div style={{ position: "absolute", left: 50, top: 372, fontFamily: SF, fontSize: 122, fontWeight: 400, letterSpacing: "-0.01em", color: running ? "#F5F5F7" : "rgba(245,245,247,0.55)", fontVariantNumeric: "tabular-nums" }}>{`0:${String(timer).padStart(2, "0")}`}</div>
          </div>
        ) }]} />
    </AbsoluteFill>
  );
};

void lineAt; void cornersAt; void lensPoint; void quadPoint; void Sweep;

/** Sound cues in film seconds (scripts/v4/mix.py reads them through cues.ts). */
export const WORK_CUES = {
  tap: [LAY.from + L_DRAG0, ED.from + E_TAP - 0.08, PR.from + P_PRESS],
  drag: [[LAY.from + L_DRAG0, LAY.from + L_DRAG1]],
  blade: [ED.from + E_BACK + 0.05],
  whoosh: [PR.from + P_PRESS + 0.05],
  laser: [PR.from + P_LASER],
};
