// Vertical teaser, 1080 x 1920, 30 s. Its own edit, phone first: the Mac sits above, the
// phone fills the lower half. Hook, the title hit, Spaces following the fingers, Actions
// switching by itself, and the end card. Timing comes from edit.json ("teaser").
import React from "react";
import { AbsoluteFill, Img, useCurrentFrame } from "remotion";
import clips from "./clips.json";
import { C, E, FONT, T, beatPulse, clamp01, keys, lerp, prog, s, spr } from "./system";
import { Kinetic } from "./ui/Kinetic";
import { Dock, MacBook, MenuBar, Pointer, SH, SW, icon } from "./ui/Mac";
import { Phone, phoneScreen } from "./ui/Phone";
import { PhoneClip, Seg, Touches, clipTime, fingersAt } from "./ui/Clip";
import { DotWipe, Floor, Ripple } from "./ui/FX";
import { Desktop, SafariSpace, SafariWin, WALL, WordWin } from "./scenes/Desktop";
import { word, words } from "./vo";

const CL = clips as any;
const W = 1080, H = 1920;
const TW = (id: string, i: number) => word(id, i, "teaser");

// Device layouts over time (teaser seconds), blended with heavy springs like the film.
type L = { mx: number; my: number; mw: number; px: number; py: number; ps: number; rot: number };
const LAYOUTS: [number, L][] = [
  [0, { mx: 540, my: 300, mw: 960, px: 540, py: 1400, ps: 380, rot: 0 }], // trackpad under the Mac
  [11.55, { mx: 540, my: 50, mw: 900, px: 540, py: 1395, ps: 470, rot: 90 }], // picked up
];
const layoutAt = (F: number): L => {
  const out = { ...LAYOUTS[0][1] };
  for (let i = 1; i < LAYOUTS.length; i++) {
    const k = spr(F, s(LAYOUTS[i][0]), "heavy");
    for (const key of Object.keys(out) as (keyof L)[]) out[key] += (LAYOUTS[i][1][key] - LAYOUTS[i - 1][1][key]) * k;
  }
  return out;
};
const macGeom = (l: L) => {
  const bez = l.mw * 0.018;
  const k = (l.mw - bez * 2) / SW;
  return { x0: l.mx - l.mw / 2 + bez, y0: l.my + bez, k, lidH: SH * k + bez * 2.4 };
};

// Recordings.
const STILL = [[7.25, 0.85], [9.55, 1.15]];
const still = (from: number, to: number) => {
  const out: Seg[] = [];
  let t = from, i = 0;
  while (t < to) {
    out.push({ at: s(t), src: STILL[i % 2][0] });
    t += STILL[i % 2][1];
    i++;
  }
  return out;
};
const PAD: Seg[] = [...still(3.9, 8.4), { at: s(8.4), src: 7.983 }, { at: s(9.9), src: 10.683 }, ...still(11.6, 12.4)];
const ACT: Seg[] = [{ at: s(12.2), src: 2.9 }, { at: s(13.0), src: 3.95 }]; // switch at 15.7
const T_CLICK = TW("actions2", 2) + 0.06;
const T_SWITCH = 15.7;

const spacesP = (F: number) => {
  const raw = (fr: number): number | null => {
    const t = clipTime(PAD, fr);
    const fs = fingersAt(t);
    if (fs.length < 3) return null;
    const x = fs[1][0];
    if (t < 10) return clamp01((0.7042 - x) / 0.52) * 1.02;
    return 1 - (x - 0.2249) / 0.52;
  };
  if (F < s(8.4)) return 0;
  const now = raw(F);
  if (now !== null) return now;
  for (let back = 1; back < 400; back++) {
    const r = raw(F - back);
    if (r !== null) return r + (1 - r) * spr(F, F - back + 1, "settle");
  }
  return F > s(10) ? 1 : 0;
};

export const Teaser: React.FC = () => {
  const F = useCurrentFrame();
  const l = layoutAt(F);
  const g = macGeom(l);

  // ---- hook ----
  const hookPhone = spr(F, s(2.0), "heavy");
  const dotT = spr(F, s(TW("hook2", 4)), "pop");
  const HIT = { x: 540, y: 1360 };

  // ---- title field ----
  const open = prog(F, s(3.97), 22, E.inOut);
  const shut = prog(F, s(6.62), 44, E.out);
  const scL = phoneScreen(l.ps, "landscape");
  const field = { x: lerp(0, l.px - scL.w / 2, shut), y: lerp(0, l.py - scL.h / 2, shut), w: lerp(W, scL.w, shut), h: lerp(H, scL.h, shut), r: lerp(0, 12.7 * (l.ps / 100), shut) };
  const devIn = prog(F, s(7.15), 26, E.out);
  const macIn = spr(F, s(6.9), "settle");

  // ---- actions ----
  const ptrMove = prog(F, s(14.4), s(T_CLICK) - s(14.4), E.inOut);
  const ptr = { x: lerp(820, 1300, ptrMove), y: lerp(560, 420, ptrMove) };
  const safariFront = F >= s(T_CLICK);
  const p = spacesP(F);

  const scP = phoneScreen(l.ps, "portrait");
  const portrait = F >= s(12.2);
  const end = s(20.0);

  return (
    <AbsoluteFill style={{ background: C.paper, overflow: "hidden", fontFamily: FONT }}>
      {/* ---------------- hook (0 to 4) ---------------- */}
      {F < s(4.4) ? (
        <AbsoluteFill>
          <div style={{ position: "absolute", left: 540 - 260, top: lerp(580, 600, spr(F, -s(0.3), "settle")), opacity: 1 - prog(F, s(2.0), 30) }}>
            <MacBook width={520}><Desktop app="TextEdit" running={["com.apple.finder", "com.apple.Safari"]} word /></MacBook>
          </div>
          <div style={{ position: "absolute", left: 80, top: 170 }}>
            <Kinetic text="Your Mac is over there." at={0} times={words("hook1", "teaser").map(s)} out={s(1.95)} style={{ ...T.hero, fontSize: 124 }} lineBreaks={[2]} />
          </div>
          <div style={{ position: "absolute", left: 80, top: 170 }}>
            <Kinetic text="Your phone is right here." at={0} times={words("hook2", "teaser").map(s)} style={{ ...T.hero, fontSize: 124 }} lineBreaks={[2]} accent={["here"]} />
          </div>
          <div style={{ position: "absolute", left: 540 - 300, top: lerp(2000, 900, hookPhone), transform: `rotate(${lerp(-10, -4, hookPhone)}deg)`, transformOrigin: "300px 460px" }}>
            <Phone short={600} screen={C.graphite}>
              {F >= s(TW("hook2", 4)) ? <div style={{ position: "absolute", left: 300 - 22 - 28 * dotT, top: 460 - 22 - 28 * dotT, width: 56 * dotT, height: 56 * dotT, borderRadius: 56, background: "rgba(242,241,238,0.9)", transform: `scale(${1 + 0.08 * beatPulse(F, s(3.5), 9)})` }} /> : null}
            </Phone>
          </div>
          <DotWipe x={HIT.x} y={HIT.y} at={s(3.97)} dur={22} color={C.graphite} w={W} h={H} />
        </AbsoluteFill>
      ) : null}

      {/* ---------------- devices (4 to 20) ---------------- */}
      {F >= s(3.97) && F < end + 30 ? (
        <AbsoluteFill style={{ background: F < s(4.4) ? "transparent" : C.paper }}>
          <div style={{ opacity: macIn, transform: `translateY(${lerp(80, 0, macIn)}px)`, position: "absolute", inset: 0 }}>
            <Floor x={l.mx} y={l.my + g.lidH + l.mw * 0.03} w={l.mw * 1.2} h={30} opacity={0.06} />
            <div style={{ position: "absolute", left: l.mx - l.mw / 2, top: l.my }}>
              <MacBook width={l.mw}>
                <div style={{ position: "absolute", left: 0, top: 0, width: SW, height: SH, overflow: "hidden", background: WALL.dark }}>
                  {F < s(12) ? (
                    <>
                      <div style={{ position: "absolute", left: -p * SW, top: 0 }}><Desktop app="TextEdit" word dock={false} /></div>
                      <div style={{ position: "absolute", left: (1 - p) * SW, top: 0 }}><SafariSpace /></div>
                    </>
                  ) : (
                    <>
                      {safariFront ? null : <SafariWin active={false} />}
                      <WordWin active={!safariFront} />
                      {safariFront ? <SafariWin active /> : null}
                      <MenuBar app={safariFront ? "Safari" : "Microsoft Word"} dark />
                    </>
                  )}
                  <Dock running={["com.apple.finder", "com.apple.Safari", ...(F >= s(12) ? ["com.microsoft.Word"] : [])]} dark={p > 0.5 || F >= s(12)} />
                  {F >= s(14.2) ? <Pointer x={ptr.x} y={ptr.y} scale={1.5} opacity={prog(F, s(14.2), 12)} press={F >= s(T_CLICK) && F < s(T_CLICK) + 8 ? 1 : 0} /> : null}
                  {F >= s(T_CLICK) ? <Ripple x={ptr.x} y={ptr.y} at={s(T_CLICK)} size={90} color={C.accent} dot={false} /> : null}
                </div>
              </MacBook>
            </div>
          </div>
          {/* phone */}
          <div style={{ position: "absolute", left: l.px, top: l.py, transform: `translate(-50%, -50%) rotate(${portrait ? l.rot - 90 : l.rot}deg)`, opacity: shut > 0.97 ? 1 : 0 }}>
            <div style={{ opacity: devIn, transform: `scale(${lerp(1.06, 1, devIn)})` }}>
              {portrait ? (
                <Phone short={l.ps} orient="portrait" island={false} screen={C.graphite}>
                  <PhoneClip clip="actions" segs={ACT} len={end + 30} w={scP.w} h={scP.h} />
                  {F >= s(T_SWITCH) && F < s(T_SWITCH) + 50 ? <div style={{ position: "absolute", left: scP.w * 0.025, top: scP.h * 0.14, width: scP.w * 0.95, height: scP.h * 0.29, borderRadius: 26, boxShadow: `inset 0 0 0 4px ${C.accent}`, opacity: 1 - prog(F, s(T_SWITCH) + 20, 30) }} /> : null}
                </Phone>
              ) : (
                <Phone short={l.ps} orient="landscape" island={false} screen={C.graphite}>
                  <PhoneClip clip="trackpad" segs={PAD} len={s(12.4)} w={scL.w} h={scL.h} />
                  <Touches segs={PAD} w={scL.w} h={scL.h} />
                  {F >= s(7.0) && F < s(12.0) ? (
                    <div style={{ position: "absolute", left: 0, right: 0, top: scL.h * 0.4, textAlign: "center" }}>
                      <Kinetic text="Three fingers" at={s(7.1)} out={s(11.4)} stagger={3} style={{ ...T.head, fontSize: scL.h * 0.13 }} color="rgba(242,241,238,0.3)" align="center" />
                    </div>
                  ) : null}
                </Phone>
              )}
            </div>
          </div>
          {/* the Mac's choice travels to the phone */}
          {(() => {
            const k = prog(F, s(T_CLICK) + 4, 30, E.inOut);
            if (k <= 0 || k >= 1) return null;
            const a = { x: g.x0 + ptr.x * g.k, y: g.y0 + ptr.y * g.k };
            const b = { x: l.px - scP.w * 0.42, y: l.py - scP.h * 0.329 };
            const size = lerp(70, 44, k) * (1 + 0.3 * Math.sin(k * Math.PI));
            return <Img src={icon("com.apple.Safari")} style={{ position: "absolute", left: lerp(a.x, b.x, k) - size / 2, top: lerp(a.y, b.y, k) - Math.sin(k * Math.PI) * 200 - size / 2, width: size, height: size }} />;
          })()}
        </AbsoluteFill>
      ) : null}

      {/* title field */}
      {F >= s(3.97) && F < s(7.6) ? (
        <div style={{ position: "absolute", inset: 0, clipPath: `circle(${Math.hypot(W, H) * open}px at ${HIT.x}px ${HIT.y}px)` }}>
          <div style={{ position: "absolute", left: field.x, top: field.y, width: field.w, height: field.h, borderRadius: field.r, background: C.graphite, overflow: "hidden" }}>
            <div style={{ position: "absolute", left: 0, top: 0, width: W, height: H, transform: `translate(${-field.x}px, ${-field.y}px)` }}>
              <div style={{ position: "absolute", left: 0, right: 0, top: 760, textAlign: "center" }}>
                <Kinetic text="Glasspad" by="letter" at={s(4.0)} out={s(6.3)} stagger={2.2} style={{ ...T.hero, fontSize: 190, letterSpacing: "-0.05em" }} color={C.paper} align="center" />
              </div>
              <div style={{ position: "absolute", left: 0, right: 0, top: 990, textAlign: "center" }}>
                <Kinetic text="turns it into a trackpad." at={0} times={words("reveal", "teaser").slice(1).map(s)} out={s(6.4)} stagger={2} style={{ ...T.sub, fontSize: 56 }} color={C.paper60} align="center" />
              </div>
            </div>
          </div>
        </div>
      ) : null}

      {/* captions: the spoken words, as they are spoken, in the space between the devices */}
      {F >= s(7.4) && F < s(11.7) ? (
        <div style={{ position: "absolute", left: 70, right: 70, top: 1010, opacity: 1 - prog(F, s(11.3), 14) }}>
          <Kinetic text="Swipe three fingers, and your Spaces move with your hand." at={0} times={words("spaces", "teaser").map(s)} lineBreaks={[4, 7]} style={{ ...T.head, fontSize: 58 }} accent={["Spaces"]} />
        </div>
      ) : null}
      {F >= s(12.2) && F < s(19.9) ? (
        <div style={{ position: "absolute", left: 70, right: 70, top: 712, opacity: 1 - prog(F, s(19.4), 14) }}>
          {F < s(14.6) ? (
            <Kinetic text="Actions follow the app in front." at={0} times={words("actions1", "teaser").map(s)} out={s(14.35)} lineBreaks={[3]} style={{ ...T.head, fontSize: 58 }} />
          ) : (
            <Kinetic text="Switch to Safari, and the buttons switch with you." at={0} times={words("actions2", "teaser").map(s)} lineBreaks={[3, 6]} style={{ ...T.head, fontSize: 52 }} accent={["Safari"]} />
          )}
        </div>
      ) : null}

      {/* ---------------- end (20 to 30) ---------------- */}
      {F >= end ? <TeaserEnd F={F} /> : null}
    </AbsoluteFill>
  );
};

const TeaserEnd: React.FC<{ F: number }> = ({ F }) => {
  const e = s(20.0);
  const open = prog(F, e, 26, E.inOut);
  const R = Math.hypot(W, H) * open;
  const lines = ["No account.", "No cloud.", "Encrypted."];
  const fold = prog(F, s(23.6), 24, E.inOut);
  const paper = prog(F, s(24.1), 26, E.inOut);
  const tile = spr(F, s(24.2), "pop");
  const glide = prog(F, s(24.45), 40, E.inOut);
  const ICON = 260;
  const dx = lerp(300, 660, glide), dy = lerp(610, 440, glide);
  const urls = spr(F, s(28.0), "settle");
  return (
    <AbsoluteFill>
      <div style={{ position: "absolute", inset: 0, clipPath: `circle(${R}px at 540px 1400px)`, background: C.graphite }}>
        <div style={{ position: "absolute", left: 0, right: 0, top: 700, textAlign: "center", transformOrigin: "540px 120px", transform: `scale(${1 - 0.95 * fold})`, opacity: 1 - fold }}>
          {lines.map((t, i) => (
            <Kinetic key={t} text={t} at={s(20.45 + i * 1.0)} style={{ ...T.hero, fontSize: 132, lineHeight: 1.12 }} color={C.paper} align="center" />
          ))}
        </div>
      </div>
      {F >= s(23.75) && F < s(24.2) ? (() => {
        const k = spr(F, s(23.75), "pop");
        return <div style={{ position: "absolute", left: 540 - 26 * k, top: 820 - 26 * k, width: 52 * k, height: 52 * k, borderRadius: 52, background: C.paper }} />;
      })() : null}
      {F >= s(24.1) ? (
        <div style={{ position: "absolute", inset: 0, clipPath: `circle(${26 + (Math.hypot(W, H) - 26) * paper}px at 540px 820px)`, background: C.paper }}>
          <div style={{ position: "absolute", left: 540 - ICON / 2, top: 520, width: ICON, height: ICON, transform: `scale(${tile})`, borderRadius: ICON * 0.225, background: "#0E0E0E", overflow: "hidden" }}>
            <svg width={ICON} height={ICON} viewBox="0 0 1024 1024">
              <rect x="102" y="222" width="820" height="580" rx="140" fill="#1B1B1B" stroke="#FFFFFF" strokeOpacity="0.1" strokeWidth="4" />
              <line x1={300} y1={610} x2={dx} y2={dy} stroke="#FFFFFF" strokeOpacity="0.1" strokeWidth="90" strokeLinecap="round" />
              <circle cx={dx} cy={dy} r="74" fill="#FFFFFF" fillOpacity="0.62" />
            </svg>
          </div>
          <div style={{ position: "absolute", left: 0, right: 0, top: 830, textAlign: "center" }}>
            <Kinetic text="Glasspad" by="letter" at={s(TW("end", 0)) - 2} stagger={2.2} style={{ ...T.hero, fontSize: 168, letterSpacing: "-0.05em" }} align="center" />
          </div>
          <div style={{ position: "absolute", left: 0, right: 0, top: 1040, textAlign: "center" }}>
            <Kinetic text="Free and open source." at={0} times={words("end", "teaser").slice(2).map(s)} style={{ ...T.sub, fontSize: 52 }} color={C.ink60} align="center" />
          </div>
          <div style={{ position: "absolute", left: 0, right: 0, top: 1190, textAlign: "center", fontSize: 40, fontWeight: 600, letterSpacing: "-0.01em", color: C.ink, opacity: clamp01(urls * 1.3), transform: `translateY(${lerp(30, 0, urls)}px)`, lineHeight: 1.5 }}>
            <div>github.com/Soham109/glasspad</div>
            <div>glasspad.sohamaggarwal.com</div>
          </div>
          <div style={{ position: "absolute", left: 0, right: 0, bottom: 60, textAlign: "center", fontSize: 22, fontWeight: 500, color: C.ink40, opacity: clamp01(urls) }}>Music: "Uplifting Electronic Indie" by WinnieTheMoog, CC BY 4.0</div>
        </div>
      ) : null}
    </AbsoluteFill>
  );
};

export const teaserKeys = keys;
