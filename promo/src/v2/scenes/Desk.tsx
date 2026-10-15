// 7.97 to 40.4 s, one continuous world: the title field collapses into the phone's glass;
// the phone lies under the Mac as its trackpad; then touch, Spaces and settings, with the
// devices moving between layouts on springs instead of cutting. The phone screen is the
// real recording; the pointer and Spaces follow the recorded fingers frame by frame.
import React from "react";
import { AbsoluteFill, useCurrentFrame } from "remotion";
import { C, E, FONT, T, clamp01, keys, lerp, prog, s, spr } from "../system";
import { Kinetic } from "../ui/Kinetic";
import { MacBook, Pointer, SH, SW, Dock, Win } from "../ui/Mac";
import { Phone, phoneScreen } from "../ui/Phone";
import { PhoneClip, Seg, Touches, clipTime, fingersAt } from "../ui/Clip";
import { Floor, Ripple, Ticks } from "../ui/FX";
import { Desktop, SafariSpace } from "./Desktop";
import { HIT_DOT } from "./Hook";
import { word, words } from "../vo";

export const DESK_FROM = 7.97;

// ---------- Layouts (film seconds -> device placement) ----------
export type L = { mx: number; my: number; mw: number; px: number; py: number; ps: number; rot: number };
const LAYOUTS: [number, L][] = [
  [0, { mx: 960, my: 70, mw: 820, px: 960, py: 862, ps: 300, rot: 0 }], // establishing
  [14.3, { mx: 1300, my: 84, mw: 1040, px: 470, py: 800, ps: 340, rot: 0 }], // touch
  [23.55, { mx: 960, my: 26, mw: 1500, px: 1655, py: 905, ps: 224, rot: 0 }], // Spaces
  [31.4, { mx: 1215, my: 52, mw: 1290, px: 345, py: 840, ps: 290, rot: 0 }], // settings
  [39.25, { mx: 1340, my: 168, mw: 940, px: 600, py: 540, ps: 440, rot: 90 }], // picked up (Apps)
  [47.2, { mx: 600, my: 150, mw: 1000, px: 1240, py: 540, ps: 420, rot: 90 }], // Actions
  [55.75, { mx: 720, my: 120, mw: 1080, px: 1520, py: 540, ps: 420, rot: 90 }], // Media
];
export const layoutAt = (F: number): L => {
  const out = { ...LAYOUTS[0][1] };
  for (let i = 1; i < LAYOUTS.length; i++) {
    const k = spr(F, s(LAYOUTS[i][0]), "heavy");
    for (const key of Object.keys(out) as (keyof L)[]) out[key] += (LAYOUTS[i][1][key] - LAYOUTS[i - 1][1][key]) * k;
  }
  return out;
};

// Mac geometry for a lid width (see MacBook): screen origin and scale, in frame px.
export const macGeom = (mx: number, my: number, mw: number) => {
  const bez = mw * 0.018;
  const k = (mw - bez * 2) / SW;
  return { x0: mx - mw / 2 + bez, y0: my + bez, k, lidH: SH * k + bez * 2.4 };
};
export const toFrame = (l: L, p: { x: number; y: number }) => {
  const g = macGeom(l.mx, l.my, l.mw);
  return { x: g.x0 + p.x * g.k, y: g.y0 + p.y * g.k };
};
/** A point on the phone's (landscape) screen, 0..1, in frame px. */
const phonePoint = (l: L, u: number, v: number) => {
  const sc = phoneScreen(l.ps, "landscape");
  const x = (u - 0.5) * sc.w, y = (v - 0.5) * sc.h;
  const r = (l.rot * Math.PI) / 180;
  return { x: l.px + x * Math.cos(r) - y * Math.sin(r), y: l.py + x * Math.sin(r) + y * Math.cos(r) };
};

// ---------- Recording placement (film seconds -> clip seconds) ----------
// Still stretches of the recording (no fingers) used between the actions.
const STILL = [[7.25, 0.85], [9.55, 1.15]];
const still = (from: number, to: number): [number, number][] => {
  const out: [number, number][] = [];
  let t = from, i = 0;
  while (t < to) {
    out.push([t, STILL[i % 2][0]]);
    t += STILL[i % 2][1];
    i++;
  }
  return out;
};
const PLAN: [number, number][] = [
  ...still(7.97, 16.3),
  [16.3, 3.43], // one finger glide (3.53 to 6.13)
  ...still(19.3, 21.2),
  [21.2, 6.86], // the tap (6.97)
  ...still(21.75, 25.2),
  [25.2, 7.983], // three fingers left (8.18 to 9.50)
  [26.9, 10.683], // half back and release (10.78 to 12.30)
  ...still(28.6, 41),
];
const SEGS: Seg[] = PLAN.map(([film, src]) => ({ at: s(film), src }));

// Pointer: the glide's finger travel, at the Mac's gain.
const GLIDE0 = 3.533;
const P0 = { x: 662, y: 470 };
const GAIN = 1.5;
const pointerAt = (t: number) => {
  const f0 = fingersAt(GLIDE0)[0];
  const tt = Math.max(GLIDE0, Math.min(6.12, t));
  const f = fingersAt(tt)[0] ?? f0;
  return { x: P0.x + (f[0] - f0[0]) * 874 * GAIN, y: P0.y + (f[1] - f0[1]) * 402 * GAIN };
};

// Spaces progress (0 = Word desktop, 1 = Safari desktop), from the three fingers.
const spacesP = (F: number) => {
  const raw = (fr: number): number | null => {
    const t = clipTime(SEGS, fr);
    const fs = fingersAt(t);
    if (fs.length < 3) return null;
    const x = fs[1][0];
    if (t < 10) return clamp01((0.7042 - x) / 0.52) * 1.02;
    return 1 - (x - 0.2249) / 0.52;
  };
  if (F < s(25.2)) return 0;
  const now = raw(F);
  if (now !== null) return now;
  for (let back = 1; back < 400; back++) {
    const r = raw(F - back);
    if (r !== null) return r + (1 - r) * spr(F, F - back + 1, "settle");
  }
  return F > s(27) ? 1 : 0;
};

// ---------- Settings pane ----------
const ROWS = ["Tracking speed", "Tap to click", "Natural scrolling", "Swipe between Spaces"];
const Toggle: React.FC<{ on: number }> = ({ on }) => (
  <div style={{ position: "relative", width: 50, height: 30, borderRadius: 30, background: on > 0.5 ? C.accent : "#D3D1CC" }}>
    <div style={{ position: "absolute", top: 3, left: lerp(3, 23, on), width: 24, height: 24, borderRadius: 24, background: "#fff" }} />
  </div>
);
const SettingsWin: React.FC<{ F: number; t1: number; t2: number; t3: number }> = ({ F, t1, t2, t3 }) => {
  const tap = spr(F, s(t1), "snap");
  const nat = spr(F, s(t2), "snap");
  const speed = lerp(0.42, 0.72, spr(F, s(t3), "settle"));
  const side = ["Wi-Fi", "Bluetooth", "General", "Appearance", "Accessibility", "Displays", "Wallpaper", "Keyboard", "Trackpad", "Mouse"];
  return (
    <Win x={260} y={96} w={1000} h={700} active title="">
      <div style={{ position: "absolute", left: 0, top: -52, width: 250, bottom: 0, background: "#F0EEEA", borderRight: `1px solid ${C.ink06}`, paddingTop: 70 }}>
        {side.map((n) => (
          <div key={n} style={{ display: "flex", alignItems: "center", gap: 12, margin: "2px 12px", padding: "8px 10px", borderRadius: 9, background: n === "Trackpad" ? C.accent : "transparent", color: n === "Trackpad" ? "#fff" : C.ink, fontSize: 16, fontWeight: 500 }}>
            <div style={{ width: 22, height: 22, borderRadius: 6, background: n === "Trackpad" ? "rgba(255,255,255,0.35)" : "#B9B6AF" }} />
            {n}
          </div>
        ))}
      </div>
      <div style={{ position: "absolute", left: 290, top: 18, fontSize: 28, fontWeight: 700, letterSpacing: "-0.02em", color: C.ink }}>Trackpad</div>
      <div style={{ position: "absolute", left: 290, top: 76, display: "flex", gap: 4, padding: 3, borderRadius: 10, background: "#E7E5E0" }}>
        {["Point & Click", "Scroll & Zoom", "More Gestures"].map((t, i) => (
          <div key={t} style={{ padding: "7px 18px", borderRadius: 8, fontSize: 14, fontWeight: 600, background: i === 0 ? "#fff" : "transparent", color: C.ink }}>{t}</div>
        ))}
      </div>
      <div style={{ position: "absolute", left: 290, right: 40, top: 140, borderRadius: 14, background: "#fff", boxShadow: `0 0 0 1px ${C.ink06}` }}>
        {ROWS.map((r, i) => (
          <div key={r} style={{ height: 78, display: "flex", alignItems: "center", padding: "0 26px", borderTop: i ? `1px solid ${C.ink06}` : "none", fontSize: 19, fontWeight: 500, color: C.ink }}>
            <span style={{ flex: 1 }}>{r}</span>
            {i === 0 ? (
              <div style={{ position: "relative", width: 260, height: 30 }}>
                <div style={{ position: "absolute", left: 0, right: 0, top: 13, height: 5, borderRadius: 5, background: "#DAD8D3" }} />
                <div style={{ position: "absolute", left: 0, width: `${speed * 100}%`, top: 13, height: 5, borderRadius: 5, background: C.accent }} />
                <div style={{ position: "absolute", left: `calc(${speed * 100}% - 13px)`, top: 2, width: 26, height: 26, borderRadius: 26, background: "#fff", boxShadow: `0 0 0 1px ${C.ink12}` }} />
              </div>
            ) : i === 1 ? <Toggle on={tap} /> : i === 2 ? <Toggle on={nat} /> : <span style={{ color: C.ink60 }}>Three fingers</span>}
          </div>
        ))}
      </div>
    </Win>
  );
};
// Where each changed control sits, in screen points (for the sync dots).
const CONTROL = [{ x: 1150, y: 96 + 52 + 140 + 117 }, { x: 1180, y: 96 + 52 + 140 + 195 }, { x: 1060, y: 96 + 52 + 140 + 39 }];

// ---------- Scene ----------
export const Desk: React.FC = () => {
  const F = useCurrentFrame();
  if (F < s(DESK_FROM)) return null;
  const l = layoutAt(F);
  const g = macGeom(l.mx, l.my, l.mw);

  // Title field: opens from the hook's dot, then collapses into the phone's glass.
  const open = prog(F, s(7.97), 22, E.inOut);
  const shut = prog(F, s(10.62), 50, E.inOut);
  const sc = phoneScreen(l.ps, "landscape");
  const field = {
    x: lerp(0, l.px - sc.w / 2, shut),
    y: lerp(0, l.py - sc.h / 2, shut),
    w: lerp(1920, sc.w, shut),
    h: lerp(1080, sc.h, shut),
    r: lerp(0, 12.7 * (l.ps / 100), shut),
  };
  const bodyIn = prog(F, s(11.2), 26, E.out);
  const macIn = spr(F, s(10.9), "settle");
  const openR = Math.hypot(1920, 1080) * open;

  // Establishing: a slow orbit gives the flat drawings depth.
  const orbitY = keys(F, [[s(11.0), -7], [s(14.3), 3], [s(15.3), 0]], E.glide);
  const orbitX = keys(F, [[s(11.0), 10], [s(14.3), 5], [s(15.3), 0]], E.glide);
  // and a push toward the menu bar while Glasspad connects
  const push = keys(F, [[s(11.3), 1], [s(12.4), 2.2], [s(13.5), 2.25], [s(14.5), 1]], E.inOut);

  // Touch.
  const tClip = clipTime(SEGS, F);
  const match = prog(F, s(16.4), 22, E.inOut); // finger dot to pointer
  const ptr = F < s(16.4) ? P0 : pointerAt(tClip > 6.2 && F > s(19) ? 6.12 : tClip);
  const showPtr = F >= s(16.4) && F < s(31.8);
  const tapF = s(21.31);
  const press = F >= tapF && F < tapF + 10 ? 1 : 0;
  const shake = F >= tapF && F < tapF + 18 ? Math.sin((F - tapF) * 1.9) * 3 * Math.exp(-(F - tapF) / 6) : 0;

  // Spaces.
  const p = spacesP(F);

  // Settings changes, on the spoken words.
  const tSet = [word("settings", 5), word("settings", 6), word("settings", 8)];

  // Phone placement.
  const phone = (
    <div style={{ position: "absolute", left: l.px, top: l.py, transform: `translate(-50%, -50%) translateX(${shake}px) rotate(${l.rot}deg)` }}>
      <div style={{ opacity: bodyIn, transform: `scale(${lerp(1.06, 1, bodyIn)})` }}>
        <Phone short={l.ps} orient="landscape" island={false} screen={C.graphite}>
          <PhoneClip clip="trackpad" segs={SEGS} len={s(41)} w={sc.w} h={sc.h} />
          <Touches segs={SEGS} w={sc.w} h={sc.h} />
        </Phone>
      </div>
    </div>
  );

  const fingerAtStart = phonePoint(l, 0.2192, 0.7181);
  const ptrFrame = toFrame(l, ptr);

  return (
    <AbsoluteFill style={{ background: F < s(8.4) ? "transparent" : C.paper, overflow: "hidden" }}>
      <AbsoluteFill style={{ perspective: 2600, transformStyle: "preserve-3d" }}>
        <AbsoluteFill style={{ transform: `scale(${push}) rotateX(${orbitX}deg) rotateY(${orbitY}deg)`, transformOrigin: "1174px 160px", transformStyle: "preserve-3d" }}>
          {/* Mac */}
          <div style={{ transform: `translateZ(-60px) translateY(${lerp(80, 0, macIn)}px)`, opacity: macIn, position: "absolute", inset: 0 }}>
            <Floor x={l.mx} y={l.my + g.lidH + l.mw * 0.03} w={l.mw * 1.25} h={l.mw * 0.035} opacity={0.06} />
            <div style={{ position: "absolute", left: l.mx - l.mw / 2, top: l.my }}>
              <MacBook width={l.mw}>
                <MacScreen F={F} p={p} tSet={tSet} selected={F >= tapF + 2 ? 1 : -1} />
                <Popover F={F} />
                {showPtr ? <Pointer x={ptr.x} y={ptr.y} scale={1.3} opacity={match} press={press} /> : null}
                {F >= tapF && F < tapF + 40 ? <Ripple x={ptr.x} y={ptr.y} at={tapF} size={70} color={C.accent} dot={false} /> : null}
              </MacBook>
            </div>
          </div>
          {/* phone */}
          <div style={{ position: "absolute", inset: 0, transform: "translateZ(80px)" }}>
            {shut > 0.98 ? <Floor x={l.px} y={l.py + phoneScreen(l.ps, "landscape").h / 2 + 22} w={sc.w * 1.05} h={18} opacity={0.07 * bodyIn} /> : null}
            {phone}
          </div>
        </AbsoluteFill>
      </AbsoluteFill>

      {/* finger dot to pointer: the match cut */}
      {match > 0 && match < 1 ? (
        <div style={{ position: "absolute", left: lerp(fingerAtStart.x, ptrFrame.x, match) - 24 * (1 - match * 0.75), top: lerp(fingerAtStart.y, ptrFrame.y, match) - lerp(0, 220, Math.sin(match * Math.PI)) - 24 * (1 - match * 0.75), width: 48 * (1 - match * 0.75), height: 48 * (1 - match * 0.75), borderRadius: 48, background: C.accent }} />
      ) : null}

      {/* in step with your display: the glide's samples, one per display frame */}
      <GlideTrail F={F} l={l} />
      {F > s(18.9) && F < s(21.4) ? (
        <div style={{ opacity: 1 - prog(F, s(20.9), 24) }}>
          <Ticks x={g.x0 + 40} y={l.my + g.lidH + l.mw * 0.075} w={SW * g.k * 0.55} n={24} at={s(19.1)} every={4} />
          <div style={{ position: "absolute", left: g.x0 + 60 + SW * g.k * 0.58, top: l.my + g.lidH + l.mw * 0.075 - 30 }}>
            <Kinetic text="120 Hz" at={s(19.3)} out={s(20.95)} style={{ ...T.head, fontSize: 64 }} color={C.ink} />
          </div>
        </div>
      ) : null}
      {/* the tap, on the glass */}
      <Ripple x={phonePoint(l, 0.62, 0.48).x} y={phonePoint(l, 0.62, 0.48).y} at={tapF} size={84} color={C.paper} dot={false} />

      {/* settings arrive on the phone */}
      <SyncDots F={F} l={l} tSet={tSet} />

      {/* the title field */}
      {F < s(11.6) ? (
        <div style={{ position: "absolute", inset: 0, clipPath: `circle(${openR}px at ${HIT_DOT.x}px ${HIT_DOT.y}px)` }}>
          <div style={{ position: "absolute", left: field.x, top: field.y, width: field.w, height: field.h, borderRadius: field.r, background: C.graphite, overflow: "hidden" }}>
            <div style={{ position: "absolute", left: 0, top: 0, width: 1920, height: 1080, transform: `translate(${-field.x}px, ${-field.y}px)` }}>
              <div style={{ position: "absolute", left: 0, right: 0, top: 360, textAlign: "center" }}>
                <Kinetic text="Glasspad" by="letter" at={s(8.02)} out={s(10.22)} stagger={2.2} style={{ ...T.hero, fontSize: 210, letterSpacing: "-0.05em" }} color={C.paper} align="center" />
              </div>
              <div style={{ position: "absolute", left: 0, right: 0, top: 618, textAlign: "center" }}>
                <Kinetic text="turns it into a trackpad." at={0} times={words("reveal").slice(1).map((w) => s(w))} out={s(10.3)} stagger={2} style={{ ...T.sub, fontSize: 52 }} color={C.paper60} align="center" />
              </div>
            </div>
          </div>
        </div>
      ) : null}
    </AbsoluteFill>
  );
};

// ---------- Mac screen over time ----------
const MacScreen: React.FC<{ F: number; p: number; tSet: number[]; selected: number }> = ({ F, p, tSet, selected }) => {
  const settingsIn = spr(F, s(31.9), "settle");
  const running = ["com.apple.finder", "com.apple.Safari", "com.apple.systempreferences"];
  return (
    <div style={{ position: "absolute", left: 0, top: 0, width: SW, height: SH, overflow: "hidden" }}>
      <div style={{ position: "absolute", left: -p * SW, top: 0 }}>
        <Desktop app="TextEdit" word dock={false} selected={selected} />
      </div>
      <div style={{ position: "absolute", left: (1 - p) * SW, top: 0 }}>
        <SafariSpace />
        {F > s(31.8) && F < s(40.2) ? (
          <div style={{ position: "absolute", inset: 0, transformOrigin: "760px 450px", transform: `perspective(1600px) rotateY(${lerp(28, 0, settingsIn)}deg) scale(${lerp(0.86, 1, settingsIn) * (1 - 0.08 * prog(F, s(39.3), 24, E.in))})`, opacity: clamp01(settingsIn * 1.5) * (1 - prog(F, s(39.3), 24, E.in)) }}>
            <SettingsWin F={F} t1={tSet[0]} t2={tSet[1]} t3={tSet[2]} />
          </div>
        ) : null}
      </div>
      <Dock running={running} dark={p > 0.5} />
    </div>
  );
};

/** The glide replayed as its display-frame samples: evenly spaced in time, one per refresh. */
const GlideTrail: React.FC<{ F: number; l: L }> = ({ F, l }) => {
  if (F < s(18.95) || F > s(21.3)) return null;
  const sweep = prog(F, s(19.05), s(1.2), E.inOut);
  const fade = 1 - prog(F, s(20.85), 26);
  const n = 52;
  const dots = [];
  for (let i = 0; i < n; i++) {
    const u = i / (n - 1);
    if (u > sweep) break;
    const t = GLIDE0 + u * (6.12 - GLIDE0);
    const pt = toFrame(l, pointerAt(t));
    const age = clamp01((sweep - u) * 6);
    dots.push(<div key={i} style={{ position: "absolute", left: pt.x - 4, top: pt.y - 4, width: 8, height: 8, borderRadius: 8, background: C.accent, opacity: fade * lerp(1, 0.55, age) }} />);
  }
  return <>{dots}</>;
};

/** Each changed setting sends a dot to the phone, and its name lands above the phone. */
const SyncDots: React.FC<{ F: number; l: L; tSet: number[] }> = ({ F, l, tSet }) => {
  if (F < s(33) || F > s(39.6)) return null;
  const names = ["Tap to click", "Natural scrolling", "Tracking speed"];
  const out = prog(F, s(38.6), 30, E.in);
  return (
    <>
      {tSet.map((t, i) => {
        const from = toFrame(l, CONTROL[i]);
        const to = { x: l.px, y: l.py - 40 };
        const k = prog(F, s(t) + 6, 30, E.inOut);
        const arrived = F >= s(t) + 36;
        return (
          <React.Fragment key={i}>
            {k > 0 && k < 1 ? <div style={{ position: "absolute", left: lerp(from.x, to.x, k) - 9, top: lerp(from.y, to.y, k) - Math.sin(k * Math.PI) * 160 - 9, width: 18, height: 18, borderRadius: 18, background: C.accent }} /> : null}
            {arrived ? <Ripple x={to.x} y={to.y} at={s(t) + 36} size={90} color={C.paper} dot={false} /> : null}
            <div style={{ position: "absolute", left: l.px - 320, top: 200 + i * 86, width: 640, textAlign: "center", opacity: 1 - out, transform: `translateY(${-30 * out}px)` }}>
              <Kinetic text={names[i]} at={s(t) + 30} style={{ ...T.head, fontSize: 58 }} align="center" />
            </div>
          </React.Fragment>
        );
      })}
    </>
  );
};

/** The Glasspad menu bar app saying it is connected: the product, on the Mac side. */
const Popover: React.FC<{ F: number }> = ({ F }) => {
  const k = spr(F, s(11.85), "pop");
  const out = prog(F, s(13.55), 16, E.in);
  if (F < s(11.7) || out >= 1) return null;
  const tick = spr(F, s(12.55), "snap");
  return (
    <>
      <div style={{ position: "absolute", left: 1130, top: 4, width: 28, height: 26, borderRadius: 7, background: C.ink12 }} />
      <svg width="20" height="20" viewBox="0 0 20 20" style={{ position: "absolute", left: 1134, top: 7 }}>
        <rect x="1.5" y="3.5" width="17" height="13" rx="3.5" fill="none" stroke={C.ink} strokeWidth="1.6" />
        <circle cx="12.5" cy="10" r="2.6" fill={C.ink} />
      </svg>
      <div style={{ position: "absolute", left: 1000, top: 40, width: 330, borderRadius: 18, background: C.sheet, boxShadow: `0 0 0 1px ${C.ink12}`, transformOrigin: "145px 0px", transform: `scale(${lerp(0.85, 1, k) * (1 - out * 0.1)})`, opacity: clamp01(k * 1.4) * (1 - out), fontFamily: FONT, padding: "18px 20px" }}>
        <div style={{ fontSize: 18, fontWeight: 700, color: C.ink }}>Glasspad</div>
        <div style={{ display: "flex", alignItems: "center", gap: 10, marginTop: 14, fontSize: 16, fontWeight: 500, color: C.ink }}>
          <div style={{ width: 10, height: 10, borderRadius: 10, background: tick > 0.5 ? "#34C759" : C.ink40 }} />
          {tick > 0.5 ? "Connected" : "Looking for your iPhone"}
        </div>
        <div style={{ marginTop: 6, marginLeft: 20, fontSize: 15, color: C.ink60 }}>Soham's iPhone</div>
        <div style={{ height: 1, background: C.ink06, margin: "14px 0" }} />
        {["Pair a new iPhone", "Settings"].map((t) => (
          <div key={t} style={{ fontSize: 15, color: C.ink, padding: "4px 0" }}>{t}</div>
        ))}
      </div>
    </>
  );
};
