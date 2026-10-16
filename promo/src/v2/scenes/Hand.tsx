// 40.4 to 60 s: the phone is picked up. Apps opens Word on the Mac; Actions changes by
// itself when the Mac switches to Safari; Dark Mode flips the Mac; Media scrubs Spotify.
// Device placement continues the Desk's springs (layoutAt), so the hand-off has no seam.
import React from "react";
import { AbsoluteFill, useCurrentFrame } from "remotion";
import clips from "../clips.json";
import { C, E, T, clamp01, lerp, prog, s, spr } from "../system";
import { Kinetic } from "../ui/Kinetic";
import { Img } from "remotion";
import { Cover, DOCK_ICON, Dock, MacBook, MenuBar, Player, Pointer, SH, SW, Win, dockIconPos, icon } from "../ui/Mac";
import { Phone, phoneScreen } from "../ui/Phone";
import { PhoneClip, Seg, clipTime } from "../ui/Clip";
import { DotWipe, Floor, Ripple } from "../ui/FX";
import { SafariWin, WALL, WordWin } from "./Desktop";
import { L, layoutAt, macGeom, toFrame } from "./Desk";
import { word } from "../vo";

export const HAND_FROM = 40.4;
const CL = clips as any;

// Recording placement, film seconds -> clip seconds.
const MENU: Seg[] = [
  { at: s(40.4), src: 3.647 }, // menu opens 40.62, Apps 42.57, Word in front 44.52
  { at: s(46.6), src: 8.6 },
];
const ACTIONS: Seg[] = [
  { at: s(47.3), src: 2.8 },
  { at: s(49.0), src: 3.533 }, // the Mac's front app becomes Safari at 52.3
];
const MEDIA: Seg[] = [{ at: s(55.82), src: 2.753 }]; // scrub 58.5 to 59.42

// Events.
const T_PILL = word("modes", 0) + 0.28;
const T_APPS = 42.36;
const T_WORD = word("apps", 1) + 0.05;
const T_CLICK_SAFARI = word("actions2", 2) + 0.06;
const T_SWITCH = 52.3;
const T_LABELS = [54.0, 54.5, 55.0];
const T_DARK = 55.0;

/** A point on the phone's portrait screen (0..1) in frame px. */
const phonePt = (l: L, u: number, v: number) => {
  const sc = phoneScreen(l.ps, "portrait");
  const x = (u - 0.5) * sc.w, y = (v - 0.5) * sc.h;
  const r = ((l.rot - 90 + ((l as any).tilt ?? 0)) * Math.PI) / 180;
  return { x: l.px + x * Math.cos(r) - y * Math.sin(r), y: l.py + x * Math.sin(r) + y * Math.cos(r) };
};

// Song position shown on the Mac, the same feed the phone got (DemoScript.swift).
const elapsedAt = (t: number) => {
  const [a, b] = CL.media.scrub as [number, number];
  if (t < a) return 41 + (t - 2.5);
  if (t < b) {
    const u = (t - a) / (b - a);
    const e = u < 0.5 ? 2 * u * u : 1 - Math.pow(-2 * u + 2, 2) / 2;
    return (41 + (a - 2.5)) * (1 - e) + 112 * e;
  }
  return 112 + (t - b);
};
const mmss = (x: number) => `${Math.floor(x / 60)}:${String(Math.floor(x % 60)).padStart(2, "0")}`;

export const Hand: React.FC = () => {
  const F = useCurrentFrame();
  if (F < s(HAND_FROM) || F > s(60.6)) return null;
  const l = layoutAt(F);
  const g = macGeom(l.mx, l.my, l.mw);
  const sc = phoneScreen(l.ps, "portrait");

  // Word: the tap sends a dot to the Dock, the icon bounces, the window opens.
  const dockWord = toFrame(l, dockIconPos("com.microsoft.Word"));
  const fly = prog(F, s(T_WORD) + 4, 26, E.inOut);
  const tapPt = phonePt(l, ...(CL.menu.wordIcon as [number, number]));
  const bounceU = clamp01((F - (s(T_WORD) + 30)) / 42);
  const bounce = bounceU > 0 && bounceU < 1 ? Math.abs(Math.sin(bounceU * Math.PI * 2)) * 46 * (1 - bounceU * 0.5) : 0;
  const wordOpen = spr(F, s(T_WORD) + 52, "settle");

  // Actions: the pointer clicks Safari, Safari comes forward, the phone follows.
  const ptrIn = prog(F, s(50.2), 18, E.out);
  const ptrMove = prog(F, s(50.45), s(T_CLICK_SAFARI) - s(50.45), E.inOut);
  const ptr = { x: lerp(820, 1300, ptrMove), y: lerp(560, 420, ptrMove) };
  const clicked = F >= s(T_CLICK_SAFARI);
  const safariFront = clicked;
  const toPhone = prog(F, s(T_CLICK_SAFARI) + 4, 34, E.inOut);
  const dark = F >= s(T_DARK) + 4;

  // Mode pushes on the phone.
  const pushApps = prog(F, s(47.3), 26, E.inOut);
  const pushMedia = prog(F, s(55.82), 26, E.inOut);

  // Media.
  const mediaIn = prog(F, s(56.1), 24, E.inOut);
  const coverFly = prog(F, s(56.28), 30, E.inOut);
  const tMedia = clipTime(MEDIA, F);
  const el = elapsedAt(tMedia);

  const screen = (darkMode: boolean) => (
    <div style={{ position: "absolute", left: 0, top: 0, width: SW, height: SH, background: WALL.dark, overflow: "hidden" }}>
      {F < s(56.6) ? (
        <div style={{ position: "absolute", inset: 0, opacity: 1 - mediaIn }}>
          {safariFront ? null : <SafariWin dark={darkMode} active={false} />}
          {F >= s(T_WORD) + 52 && F < s(56.6) ? (
            <div style={{ position: "absolute", inset: 0, transformOrigin: `${dockIconPos("com.microsoft.Word").x}px ${SH}px`, transform: `scale(${lerp(0.08, 1, wordOpen)})`, opacity: clamp01(wordOpen * 2) }}>
              <WordWin dark={darkMode} active={!safariFront} />
            </div>
          ) : null}
          {safariFront ? <SafariWin dark={darkMode} active /> : null}
        </div>
      ) : null}
      {F >= s(56.1) ? (
        <div style={{ position: "absolute", inset: 0, opacity: mediaIn, transform: `translateY(${lerp(24, 0, mediaIn)}px)` }}>
          <Win x={150} y={84} w={1212} h={720} dark title="Spotify">
            <Player progress={el / 167} elapsed={mmss(el)} remain={`-${mmss(167 - el)}`} hideCover={coverFly < 1} />
          </Win>
        </div>
      ) : null}
      <MenuBar app={F >= s(56.0) ? "Spotify" : safariFront ? "Safari" : F >= s(T_WORD) + 52 ? "Microsoft Word" : "Safari"} dark menus={["File", "Edit", "View", "Window", "Help"]} />
      <Dock running={["com.apple.finder", "com.apple.Safari", "com.apple.systempreferences", ...(F >= s(T_WORD) + 30 ? ["com.microsoft.Word"] : []), "com.spotify.client"]} bounce={{ "com.microsoft.Word": bounce }} dark={darkMode || F >= s(56)} />
      {F >= s(50.2) && F < s(56.0) ? <Pointer x={ptr.x} y={ptr.y} scale={1.4} opacity={ptrIn} press={clicked && F < s(T_CLICK_SAFARI) + 8 ? 1 : 0} /> : null}
    </div>
  );

  // Dark mode wipe origin: the Mac screen edge nearest the phone.
  const wipeOrigin = { x: SW - 40, y: SH * 0.55 };

  return (
    <AbsoluteFill style={{ background: C.paper, overflow: "hidden" }}>
      {/* Mac */}
      <Floor x={l.mx} y={l.my + g.lidH + l.mw * 0.03} w={l.mw * 1.25} h={l.mw * 0.035} opacity={0.06} />
      <div style={{ position: "absolute", left: l.mx - l.mw / 2, top: l.my }}>
        <MacBook width={l.mw}>
          {screen(false)}
          {F >= s(T_DARK) + 4 && F < s(56.0) ? (
            <DotWipe x={wipeOrigin.x} y={wipeOrigin.y} at={s(T_DARK) + 4} dur={32} color="transparent" w={SW} h={SH}>
              {screen(true)}
            </DotWipe>
          ) : null}
          {F >= s(T_CLICK_SAFARI) && F < s(T_CLICK_SAFARI) + 40 ? <Ripple x={ptr.x} y={ptr.y} at={s(T_CLICK_SAFARI)} size={80} color={C.accent} dot={false} /> : null}
        </MacBook>
      </div>

      {/* phone */}
      <Floor x={l.px} y={l.py + sc.h / 2 + 30} w={sc.w * 1.1} h={22} opacity={0.07} />
      <div style={{ position: "absolute", left: l.px, top: l.py, transform: `translate(-50%, -50%) rotate(${l.rot - 90 + l.tilt}deg)` }}>
        <Phone short={l.ps} orient="portrait" island={false} screen={C.graphite}>
          {/* mode changes push like the app's own pages, never cut */}
          <div style={{ position: "absolute", inset: 0, transform: `translateX(${-100 * pushApps}%)` }}>
            <PhoneClip clip="menu" segs={MENU} len={s(47.75)} w={sc.w} h={sc.h} />
          </div>
          <div style={{ position: "absolute", inset: 0, transform: `translateX(${100 * (1 - pushApps)}%) translateY(${-100 * pushMedia}%)` }}>
            <PhoneClip clip="actions" segs={ACTIONS} len={s(56.25)} w={sc.w} h={sc.h} />
          </div>
          <div style={{ position: "absolute", inset: 0, transform: `translateY(${100 * (1 - pushMedia)}%)` }}>
            <PhoneClip clip="media" segs={MEDIA} len={s(60.6)} w={sc.w} h={sc.h} />
          </div>
          {/* the front-app section lights up when it changes on its own */}
          {F >= s(T_SWITCH) && F < s(T_SWITCH) + 50 ? (
            <div style={{ position: "absolute", left: sc.w * 0.025, top: sc.h * 0.135, width: sc.w * 0.95, height: sc.h * 0.28, borderRadius: 22, boxShadow: `inset 0 0 0 3px ${C.accent}`, opacity: 1 - prog(F, s(T_SWITCH) + 20, 30) }} />
          ) : null}
        </Phone>
      </div>

      {/* taps on the glass */}
      {([[T_PILL, CL.menu.pill], [T_APPS, CL.menu.appsItem], [T_WORD, CL.menu.wordIcon], [T_DARK, CL.actions.darkMode]] as [number, [number, number]][]).map(([t, uv], i) => {
        const pt = phonePt(l, uv[0], uv[1]);
        return <Ripple key={i} x={pt.x} y={pt.y} at={s(t)} size={78} color={C.paper} />;
      })}
      {/* scrub finger */}
      {tMedia > CL.media.scrub[0] - 0.15 && tMedia < CL.media.scrub[1] + 0.2 && F >= s(56) ? (() => {
        const u = lerp(CL.media.scrubX[0], CL.media.scrubX[1], el / 167);
        const pt = phonePt(l, u, CL.media.scrubY);
        return <div style={{ position: "absolute", left: pt.x - 30, top: pt.y - 30, width: 60, height: 60, borderRadius: 60, boxShadow: `inset 0 0 0 3px ${C.paper}`, opacity: 0.9 }} />;
      })() : null}

      {/* Word: the icon itself leaves the phone and lands in the Dock */}
      {fly > 0 && fly < 1 ? (() => {
        const size = lerp(sc.w * 0.15, DOCK_ICON * g.k, fly) * (1 + 0.7 * Math.sin(fly * Math.PI));
        return <Img src={icon("com.microsoft.Word")} style={{ position: "absolute", left: lerp(tapPt.x, dockWord.x, fly) - size / 2, top: lerp(tapPt.y, dockWord.y, fly) - Math.sin(fly * Math.PI) * 220 - size / 2, width: size, height: size }} />;
      })() : null}
      {/* Media: the cover travels from the phone into the Mac's player */}
      {coverFly > 0 && coverFly < 1 ? (() => {
        const [u0, v0, u1] = CL.media.art as number[];
        const a = phonePt(l, u0, v0);
        const aSize = (u1 - u0) * sc.w;
        const b = toFrame(l, { x: 150 + 40, y: 84 + 52 + 40 });
        const bSize = 300 * g.k;
        const size = lerp(aSize, bSize, coverFly);
        return (
          <div style={{ position: "absolute", left: lerp(a.x, b.x, coverFly), top: lerp(a.y, b.y, coverFly) - Math.sin(coverFly * Math.PI) * 120, width: size, height: size, borderRadius: lerp(14, 6, coverFly), overflow: "hidden" }}>
            <Cover size={size} />
          </div>
        );
      })() : null}
      {/* Safari: Mac to phone */}
      {toPhone > 0 && toPhone < 1 ? (() => {
        const a = toFrame(l, ptr);
        const b = phonePt(l, 0.08, 0.163);
        const size = lerp(DOCK_ICON * g.k * 1.2, sc.w * 0.075, toPhone) * (1 + 0.3 * Math.sin(toPhone * Math.PI));
        return <Img src={icon("com.apple.Safari")} style={{ position: "absolute", left: lerp(a.x, b.x, toPhone) - size / 2, top: lerp(a.y, b.y, toPhone) - Math.sin(toPhone * Math.PI) * 200 - size / 2, width: size, height: size }} />;
      })() : null}

      {/* the app in front, named large: it changes when the Mac changes */}
      {F >= s(47.9) && F < s(54.0) ? (
        <div style={{ position: "absolute", left: l.px + l.ps / 2 + 56, top: 380, opacity: 1 - prog(F, s(53.6), 14, E.in) }}>
          <div style={{ ...T.label, fontFamily: "Inter", color: C.ink40, marginBottom: 14, opacity: prog(F, s(48.3), 20) }}>In front on your Mac</div>
          {F < s(T_SWITCH) ? (
            <Kinetic text="Microsoft Word" at={s(word("actions1", 0))} out={s(T_SWITCH) - 14} lineBreaks={[1]} style={{ ...T.head, fontSize: 70, lineHeight: 1.08 }} />
          ) : (
            <Kinetic text="Safari" by="letter" at={s(T_SWITCH)} stagger={2} style={{ ...T.head, fontSize: 70, lineHeight: 1.08 }} color={C.accent} />
          )}
        </div>
      ) : null}
      {/* pinned actions, named on the beat */}
      {F >= s(53.8) && F < s(56.2) ? (
        <div style={{ position: "absolute", left: l.px + l.ps / 2 + 56, top: 340, opacity: 1 - prog(F, s(55.75), 14, E.in) }}>
          {["Screenshot.", "Lock.", "Dark mode."].map((t, i) => (
            <Kinetic key={t} text={t} at={s(T_LABELS[i])} style={{ ...T.head, fontSize: 60, lineHeight: 1.25 }} color={i === 2 && dark ? C.accent : C.ink} />
          ))}
        </div>
      ) : null}
    </AbsoluteFill>
  );
};
