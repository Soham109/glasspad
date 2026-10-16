// Scenes 9 to 11: everything else (the modes, then the trackpad), privacy, the end card.
import React from "react";
import { AbsoluteFill, Img, OffthreadVideo, Sequence, useCurrentFrame } from "remotion";
import { BEAT_S, C, E, FPS, SF, SFT, clamp01, lerp, phone, prog, spr, sstep } from "../core";
import { StudioPhone, PhonePose, phonePoint } from "../set/Studio";
import { Sym, Wallpaper, MenuBar, Dock } from "../mac/Desktop";
import { SafariApp, MailApp } from "../mac/Apps";
import { ExternalDisplay, EXT } from "../devices/Mac";
import { Label, Touch } from "../fx";
import { scene, word, lineAt } from "../timeline";

const T = (sec: number) => Math.round(sec * FPS);
const STUDIO = "radial-gradient(70% 70% at 50% 42%, #1B1C20 0%, #0B0B0D 60%, #050506 100%)";

// ---------------------------------------------------------------------------------------
// 9. Everything else: the mode menu, then a beat each for Keyboard, Media, Dock, Macros;
//    then the phone lies down and is a trackpad again, three fingers moving the Mac's Space.
// ---------------------------------------------------------------------------------------
const MO = scene("more");
const W = (i: number) => word("more1", i) - MO.from;
const BEATS = [
  { at: W(0) - 0.08, img: "keys.png", orient: "landscape" as const, x: 960, rz: 0 },
  { at: W(1) - 0.08, img: "media.png", orient: "portrait" as const, x: 980, rz: 0 },
  { at: W(3) - 0.08, img: "dock.png", orient: "portrait" as const, x: 940, rz: 0 },
  { at: W(5) - 0.08, img: "macros.png", orient: "portrait" as const, x: 960, rz: 0 },
];
const M_TRACK = word("more2", 0) - MO.from - 0.9; // the phone lies down
// trackpad.mp4 (the real app, scripted touches): glide, tap, three finger swipe left, half back
const TP = { start: 2.6, tap: 6.45, swipe: [7.6, 8.8] as [number, number], back: [10.1, 11.5] as [number, number] };
const TP_FROM = TP.tap - (word("more2", 8) - MO.from - M_TRACK) + 0.1; // the tap lands on "feel"

export const More: React.FC = () => {
  const f = useCurrentFrame();
  const t = f / FPS;
  let idx = -1;
  BEATS.forEach((b, i) => { if (t >= b.at) idx = i; });
  const flat = t >= M_TRACK ? spr(f, T(M_TRACK), "heavy") : 0;
  // the menu first (real recording), then the beats
  const beat = idx >= 0 ? BEATS[idx] : null;
  const bIn = beat ? spr(f, T(beat.at), "snap") : 1;
  const drift = (t / MO.len) * 30;
  const pose: PhonePose = beat
    ? { x: beat.x + drift * 0.3, y: 540, size: beat.orient === "landscape" ? 430 : 380, orient: beat.orient, rz: lerp(beat.orient === "landscape" ? -8 : 6, beat.rz, bIn), rx: 0, ry: lerp(-14, 0, bIn) }
    : { x: 960, y: 560, size: 380, orient: "portrait", ry: lerp(10, 0, clamp01(t / 0.8)), rx: 0 };
  // trackpad: the phone turns sideways, lies back and settles below the Mac's display
  const tpTime = TP_FROM + (t - M_TRACK);
  const swipeU = clamp01((tpTime - TP.swipe[0]) / (TP.swipe[1] - TP.swipe[0])) - 0.5 * clamp01((tpTime - TP.back[0]) / (TP.back[1] - TP.back[0])) * (tpTime < TP.back[1] + 0.3 ? 1 : 0);
  const space = t < M_TRACK ? 0 : E.inOut(clamp01(swipeU));
  const tapRing = tpTime >= TP.tap ? prog(f, T(t - (tpTime - TP.tap)), 30, E.out) : 0;
  const shake = tpTime >= TP.tap && tpTime < TP.tap + 0.12 ? Math.sin((tpTime - TP.tap) * 160) * 2 : 0;
  return (
    <AbsoluteFill style={{ background: STUDIO }}>
      {t < M_TRACK + 0.4 ? (
        <AbsoluteFill style={{ opacity: 1 - flat }}>
          <StudioPhone pose={pose} reflection shadow={0.35}>
            {beat ? (
              <Img src={phone(beat.img)} style={beat.orient === "landscape" ? { width: 2622, height: 1206 } : { width: 1206, height: 2622 }} />
            ) : (
              <Sequence from={-T(4.3)} layout="none">
                <OffthreadVideo src={phone("menu.mp4")} muted style={{ width: 1206, height: 2622 }} />
              </Sequence>
            )}
          </StudioPhone>
          {beat ? <Touch path={() => phonePoint(pose, 0.5, 0.5)} down={T(beat.at) - 6} up={T(beat.at)} size={60} ring={false} color="rgba(255,255,255,0.0)" /> : null}
        </AbsoluteFill>
      ) : null}
      {t >= M_TRACK - 0.1 ? (
        <AbsoluteFill style={{ opacity: clamp01(flat * 1.5) }}>
          {/* the Mac's display, its Space following three fingers */}
          <div style={{ position: "absolute", left: 960 - 440, top: 40 - (1 - flat) * 40, transform: `scale(${lerp(0.96, 1, flat)})` }}>
            <ExternalDisplay width={880} stand={false}>
              <div style={{ position: "absolute", left: 0, top: 0, width: EXT.w * 2, height: EXT.h, transform: `translateX(${-space * EXT.w}px)` }}>
                <div style={{ position: "absolute", left: 0, top: 0, width: EXT.w, height: EXT.h, overflow: "hidden" }}>
                  <Wallpaper w={EXT.w} h={EXT.h} />
                  <MailApp x={220} y={110} w={1160} h={660} />
                </div>
                <div style={{ position: "absolute", left: EXT.w, top: 0, width: EXT.w, height: EXT.h, overflow: "hidden" }}>
                  <Wallpaper kind="dusk" w={EXT.w} h={EXT.h} />
                  <SafariApp x={180} y={90} w={1240} h={680} />
                </div>
              </div>
              <MenuBar w={EXT.w} app={space > 0.5 ? "Safari" : "Mail"} />
              <Dock w={EXT.w} h={EXT.h} running={["com.apple.finder", "com.apple.mail", "com.apple.Safari"]} />
            </ExternalDisplay>
          </div>
          <div style={{ position: "absolute", inset: 0, transform: `translate(${shake}px, 0)` }}>
            <StudioPhone pose={{ x: 960, y: lerp(560, 800, flat), size: lerp(380, 420, flat), orient: "landscape", rx: lerp(0, 52, flat), rz: 0 }} shadow={0.6} perspective={1700}>
              <Sequence from={T(M_TRACK) - T(TP_FROM)} layout="none">
                <OffthreadVideo src={phone("trackpad.mp4")} muted style={{ width: 2622, height: 1206 }} />
              </Sequence>
            </StudioPhone>
          </div>
          {tapRing > 0 && tapRing < 1 ? <div style={{ position: "absolute", left: 960 - 60 - tapRing * 140, top: 800 - 30 - tapRing * 70, width: 120 + tapRing * 280, height: 60 + tapRing * 140, borderRadius: "50%", boxShadow: `inset 0 0 0 ${lerp(4, 1, tapRing)}px rgba(255,255,255,0.8)`, opacity: 1 - tapRing }} /> : null}
        </AbsoluteFill>
      ) : null}
      {/* one name per screen: each leaves as the next arrives */}
      <Label text="Modes" inAt={T(0.25)} outAt={T(BEATS[0].at) + 2} />
      {["Keyboard", "Media", "Dock", "Macros"].map((n, i) => (
        <Label key={n} text={n} inAt={T(BEATS[i].at) + 2} outAt={i < 3 ? T(BEATS[i + 1].at) + 2 : T(M_TRACK + 0.2)} />
      ))}
      <Label text="Trackpad" inAt={T(M_TRACK + 0.5)} outAt={T(MO.len - 0.05)} />
    </AbsoluteFill>
  );
};

// ---------------------------------------------------------------------------------------
// 10. Private: no account, no cloud; the phone and the Mac, one sealed line, your Wi-Fi.
// ---------------------------------------------------------------------------------------
const PV = scene("private");
const PW_ = (i: number) => word("private", i) - PV.from;

export const Private: React.FC = () => {
  const f = useCurrentFrame();
  const t = f / FPS;
  const fadeOut = (at: number) => clamp01(1 - prog(f, T(at), 22, E.in));
  const appear = (at: number) => spr(f, T(at), "settle");
  const account = appear(PW_(0) - 0.25) * fadeOut(PW_(1) + 0.45);
  const cloud = appear(PW_(2) - 0.25) * fadeOut(PW_(3) + 0.45);
  const devices = appear(PW_(4) - 0.3);
  const line = prog(f, T(PW_(4)), 26, E.inOut);
  const lock = t >= PW_(6) ? spr(f, T(PW_(6)), "pop") : 0;
  const wifi = prog(f, T(PW_(8) - 0.25), 40, E.inOut);
  const cx = 960, cy = 560;
  const L = { x: cx - 330, y: cy }, R = { x: cx + 330, y: cy };
  const strike = (v: number) => (
    <div style={{ position: "absolute", left: -10, top: "50%", width: `${v * 120}%`, height: 4, background: "#F5F5F7", transform: "rotate(-35deg)", transformOrigin: "0 50%" }} />
  );
  return (
    <AbsoluteFill style={{ background: STUDIO }}>
      {/* the account and the cloud: shown, crossed, gone */}
      {account > 0.01 ? <div style={{ position: "absolute", left: cx - 60, top: cy - 60, width: 120, height: 120, opacity: account, transform: `scale(${lerp(0.8, 1, account)})` }}><Sym name="person.crop.circle.fill" size={120} color="#F5F5F7" />{strike(clamp01((t - PW_(1)) / 0.3))}</div> : null}
      {cloud > 0.01 ? <div style={{ position: "absolute", left: cx - 70, top: cy - 60, width: 140, height: 120, opacity: cloud, transform: `scale(${lerp(0.8, 1, cloud)})` }}><Sym name="cloud.fill" size={140} color="#F5F5F7" />{strike(clamp01((t - PW_(3)) / 0.3))}</div> : null}
      {/* the two devices and the line between them */}
      <div style={{ position: "absolute", left: L.x - 90, top: L.y - 70, opacity: devices, transform: `translateX(${(1 - devices) * -60}px)` }}><Sym name="laptopcomputer" size={180} color="#F5F5F7" /></div>
      <div style={{ position: "absolute", left: R.x - 55, top: R.y - 70, opacity: devices, transform: `translateX(${(1 - devices) * 60}px)` }}><Sym name="iphone" size={130} color="#F5F5F7" /></div>
      <div style={{ position: "absolute", left: L.x + 110, top: cy - 1.5, width: (R.x - L.x - 200) * line, height: 3, borderRadius: 3, background: "rgba(245,245,247,0.7)" }} />
      {/* touches crossing the line, as dots */}
      {Array.from({ length: 6 }).map((_, i) => {
        const k = ((t - PW_(4) - i * 0.28) / 1.1);
        if (k < 0 || k > 1 || line < 1) return null;
        const x = lerp(R.x - 90, L.x + 110, k);
        return <div key={i} style={{ position: "absolute", left: x - 7, top: cy - 7, width: 14, height: 14, borderRadius: 14, background: "#F5F5F7" }} />;
      })}
      {lock > 0 ? <div style={{ position: "absolute", left: cx - 26, top: cy - 70, transform: `scale(${lock})` }}><Sym name="lock.fill" size={52} color="#F5F5F7" /></div> : null}
      {/* your Wi-Fi: the outline closes around both */}
      <svg width={1920} height={1080} style={{ position: "absolute", inset: 0 }}>
        <rect x={cx - 560} y={cy - 230} width={1120} height={460} rx={64} fill="none" stroke="rgba(245,245,247,0.55)" strokeWidth={3} pathLength={1} strokeDasharray={1} strokeDashoffset={1 - wifi} />
      </svg>
      <div style={{ position: "absolute", left: cx - 34, top: cy - 230 - 34, width: 68, height: 68, borderRadius: 68, background: "#0B0B0D", display: "flex", alignItems: "center", justifyContent: "center", opacity: wifi }}><Sym name="wifi" size={44} color="#F5F5F7" /></div>
      <Label text="Private" inAt={T(0.3)} outAt={T(PV.len - 0.05)} />
    </AbsoluteFill>
  );
};

// ---------------------------------------------------------------------------------------
// 11. End card: the dot glides once; the name; the phone tries its themes on the beat.
// ---------------------------------------------------------------------------------------
const EN = scene("end");

export const End: React.FC = () => {
  const f = useCurrentFrame();
  const t = f / FPS;
  const dot = spr(f, T(0.0), "pop");
  const glide = prog(f, T(0.25), T(0.9), E.inOut);
  const name = spr(f, T(word("end", 0) - EN.from - 0.05), "settle");
  const sub = spr(f, T(word("end", 1) - EN.from), "settle");
  const meta = spr(f, T(word("end", 4) - EN.from + 0.5), "settle");
  const themes = ["pinned.png", "pinned-paper.png", "pinned-mono.png"];
  const ti = Math.min(2, Math.max(0, Math.floor((t - 2.2) / (BEAT_S * 2))));
  const phoneIn = spr(f, T(0.6), "heavy");
  return (
    <AbsoluteFill style={{ background: STUDIO }}>
      {/* the dot glides along a short arc, as on the app icon, then becomes the wordmark's lead */}
      <div style={{ position: "absolute", left: lerp(700, 520, glide) - 18 * dot, top: lerp(560, 470, glide) - 18 * dot + Math.sin(glide * Math.PI) * -40, width: 36 * dot, height: 36 * dot, borderRadius: 36, background: "#F5F5F7", opacity: 1 - sstep(0.85, 1, name) * 0 }} />
      <div style={{ position: "absolute", left: 570, top: 405, fontFamily: SF, fontSize: 120, fontWeight: 600, letterSpacing: "-0.04em", color: "#F5F5F7", opacity: clamp01(name * 1.3), transform: `translateY(${(1 - name) * 18}px)` }}>Glasspad</div>
      <div style={{ position: "absolute", left: 576, top: 548, fontFamily: SF, fontSize: 38, fontWeight: 500, letterSpacing: "-0.015em", color: "rgba(245,245,247,0.72)", opacity: clamp01(sub * 1.3), transform: `translateY(${(1 - sub) * 12}px)` }}>Free and open source.</div>
      <div style={{ position: "absolute", left: 578, top: 622, fontFamily: SFT, fontSize: 24, fontWeight: 500, color: "rgba(245,245,247,0.5)", opacity: meta }}>github.com/Soham109/glasspad</div>
      <div style={{ position: "absolute", left: 0, right: 0, bottom: 52, textAlign: "center", fontFamily: SFT, fontSize: 17, color: "rgba(245,245,247,0.36)", opacity: meta }}>Music: &ldquo;Uplifting Electronic Indie&rdquo; by WinnieTheMoog, CC BY 4.0</div>
      <StudioPhone pose={{ x: 1420, y: 520 + (1 - phoneIn) * 60, size: 250, orient: "landscape", rz: -4, opacity: phoneIn }} shadow={0.4}>
        <Img src={phone(themes[ti])} style={{ width: 2622, height: 1206 }} />
      </StudioPhone>
    </AbsoluteFill>
  );
};

void lineAt; void C;

/** Sound cues in film seconds (scripts/v4/mix.py reads them through cues.ts). */
export const FINALE_CUES = {
  tap: BEATS.map((b) => MO.from + b.at - 0.1),
  haptic: [MO.from + M_TRACK + (TP.tap - TP_FROM)],
  swipe: [[MO.from + M_TRACK + (TP.swipe[0] - TP_FROM), MO.from + M_TRACK + (TP.swipe[1] - TP_FROM)]],
  whoosh: [MO.from + M_TRACK],
  lock: [PV.from + PW_(6)],
  dot: [EN.from],
};
