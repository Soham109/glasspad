// 59.85 to 76 s. The song's cover opens to fill the frame; its disc becomes the dot.
// "No account. No cloud." A private line between phone and Mac, sealed, inside your Wi-Fi.
// Everything folds back into the dot, which opens onto the end card and draws the icon.
import React from "react";
import { AbsoluteFill, useCurrentFrame } from "remotion";
import clips from "../clips.json";
import { C, E, FONT, T, beatPulse, clamp01, lerp, prog, s, spr } from "../system";
import { Kinetic } from "../ui/Kinetic";
import { Cover } from "../ui/Mac";
import { phoneScreen } from "../ui/Phone";
import { layoutAt } from "./Desk";
import { word, words } from "../vo";

const CL = clips as any;
export const OUTRO_FROM = 59.85;
const BLOOM = s(59.85);
const COLLAPSE = s(67.25);
const END = s(67.8);

export const Outro: React.FC = () => {
  const F = useCurrentFrame();
  if (F < BLOOM) return null;
  return (
    <AbsoluteFill style={{ background: F < BLOOM + 27 ? "transparent" : F < END + 24 ? C.graphite : C.paper, overflow: "hidden" }}>
      {F < END + 30 ? <Privacy F={F} /> : null}
      {F >= END ? <EndCard F={F} /> : null}
    </AbsoluteFill>
  );
};

const Privacy: React.FC<{ F: number }> = ({ F }) => {
  // Start: the cover as the phone shows it.
  const l = layoutAt(BLOOM);
  const sc = phoneScreen(l.ps, "portrait");
  const [u0, v0, u1] = CL.media.art as number[];
  const start = { x: l.px - sc.w / 2 + u0 * sc.w, y: l.py - sc.h / 2 + v0 * sc.h, size: (u1 - u0) * sc.w };
  const big = { size: 2100, x: 960 - 1050, y: 540 - 1050 + (2100 * (0.5 - 0.411)) };
  const b = prog(F, BLOOM, 27, E.inOut);
  const cov = { x: lerp(start.x, big.x, b), y: lerp(start.y, big.y, b), size: lerp(start.size, big.size, b) };
  const r0 = 22 * (cov.size / 900); // corner radius of the phone's artwork
  // The disc leaves the cover and becomes the dot.
  const shrink = prog(F, s(60.3), 28, E.inOut);
  const discC = { x: cov.x + cov.size * 0.5, y: cov.y + cov.size * (370 / 900) };
  const dotHome = { x: 960, y: 250 };
  const discR = lerp(cov.size * (200 / 900), 20, shrink);
  const disc = { x: lerp(discC.x, dotHome.x, shrink), y: lerp(discC.y, dotHome.y, shrink) };
  const coverOut = shrink > 0;

  // Diagram.
  const dIn = (t: number) => spr(F, s(t), "settle");
  const box = prog(F, s(63.0), 48, E.inOut);
  const devices = dIn(63.15);
  const sealed = F >= s(word("privacy2", 3));
  const lock = spr(F, s(word("privacy2", 3)), "pop");
  const wifi = F >= s(word("privacy2", 5)) ? beatPulse(F, s(word("privacy2", 5)), 12) : 0;
  const fold = prog(F, COLLAPSE, 30, E.inOut);
  const textOut = prog(F, s(62.75), 18, E.in);

  const P = { x: 610, y: 600 }, M = { x: 1330, y: 600 };
  const packets = [];
  if (F > s(63.5)) {
    for (let i = 0; i < 12; i++) {
      const born = s(63.5) + i * 15;
      const k = (F - born) / 54;
      if (k < 0 || k > 1) continue;
      const x = lerp(P.x + 110, M.x - 200, k);
      const isSealed = sealed && x > 960 - 10 && F > s(word("privacy2", 3));
      packets.push(<div key={i} style={{ position: "absolute", left: x - 9, top: P.y - 9, width: 18, height: 18, borderRadius: 18, background: isSealed ? "transparent" : C.paper, boxShadow: isSealed ? `inset 0 0 0 3px ${C.paper}` : undefined }} />);
    }
  }

  return (
    <AbsoluteFill>
      {/* the cover */}
      <div style={{ position: "absolute", left: cov.x, top: cov.y, width: cov.size, height: cov.size, borderRadius: lerp(r0, 0, b), overflow: "hidden", opacity: 1 }}>
        <div style={{ transform: `scale(${cov.size / 300})`, transformOrigin: "0 0" }}>
          <CoverNoDisc size={300} bar={1 - shrink} />
        </div>
      </div>
      {/* the disc, then the dot */}
      {F < COLLAPSE + 40 ? <div style={{ position: "absolute", left: disc.x - discR, top: disc.y - discR, width: discR * 2, height: discR * 2, borderRadius: discR * 2, background: C.paper, opacity: coverOut ? 1 - prog(F, s(62.9), 14) : 1 }} /> : null}

      {/* words */}
      <div style={{ position: "absolute", left: 0, right: 0, top: 360, textAlign: "center", opacity: 1 - textOut, transform: `translateY(${-40 * textOut}px)` }}>
        <Kinetic text="No account." at={0} times={words("privacy1").slice(0, 2).map(s)} style={{ ...T.hero, fontSize: 150 }} color={C.paper} align="center" />
        <Kinetic text="No cloud." at={0} times={words("privacy1").slice(2).map(s)} style={{ ...T.hero, fontSize: 150 }} color={C.paper} align="center" />
      </div>

      {/* the diagram folds into the dot the end card opens from */}
      {F >= COLLAPSE + 14 && F < END + 2 ? (() => {
        const k = spr(F, COLLAPSE + 14, "pop");
        return <div style={{ position: "absolute", left: 960 - 24 * k, top: 600 - 24 * k, width: 48 * k, height: 48 * k, borderRadius: 48, background: C.paper }} />;
      })() : null}
      {/* your Wi-Fi */}
      {F > s(62.95) ? (
        <div style={{ position: "absolute", inset: 0, transformOrigin: "960px 600px", transform: `scale(${lerp(1, 0.02, fold)})`, opacity: 1 - prog(F, COLLAPSE + 18, 12) }}>
          <svg width={1920} height={1080} style={{ position: "absolute", inset: 0 }}>
            <rect x={300} y={330} width={1320} height={540} rx={56} fill="none" stroke={wifi > 0.05 ? `rgba(242,241,238,${0.3 + 0.6 * wifi})` : C.paper30} strokeWidth={3} pathLength={1} strokeDasharray={`${box} 1`} />
          </svg>
          <div style={{ position: "absolute", left: 350, top: 362, opacity: box }}>
            <Kinetic text="Your Wi-Fi" at={s(63.35)} style={{ ...T.label, fontSize: 26 }} color={C.paper60} />
          </div>
          {/* phone */}
          <div style={{ position: "absolute", left: P.x - 75, top: P.y - 155, width: 150, height: 310, borderRadius: 30, boxShadow: `inset 0 0 0 4px ${C.paper}`, transform: `scale(${devices})` }}>
            <div style={{ position: "absolute", left: 52, top: 14, width: 46, height: 13, borderRadius: 13, background: C.paper }} />
          </div>
          {/* Mac */}
          <div style={{ position: "absolute", left: M.x - 170, top: M.y - 125, transform: `scale(${devices})`, transformOrigin: "170px 125px" }}>
            <div style={{ width: 340, height: 220, borderRadius: 18, boxShadow: `inset 0 0 0 4px ${C.paper}` }} />
            <div style={{ marginLeft: -26, marginTop: 8, width: 392, height: 10, borderRadius: 10, background: C.paper }} />
          </div>
          {/* the line, its packets, the seal */}
          <div style={{ position: "absolute", left: P.x + 110, top: P.y - 1.5, width: (M.x - 200 - P.x - 110) * prog(F, s(63.3), 30, E.out), height: 3, background: C.paper30 }} />
          {packets}
          {F > s(word("privacy2", 3)) - 6 ? (
            <div style={{ position: "absolute", left: 960 - 34, top: P.y - 100, width: 68, height: 76, transform: `scale(${lock})`, transformOrigin: "34px 76px" }}>
              <div style={{ position: "absolute", left: 14, top: lerp(-4, 8, lock), width: 40, height: 44, borderRadius: "20px 20px 0 0", boxShadow: `inset 0 0 0 6px ${C.paper}` }} />
              <div style={{ position: "absolute", left: 0, top: 34, width: 68, height: 42, borderRadius: 10, background: C.paper }} />
            </div>
          ) : null}
        </div>
      ) : null}
    </AbsoluteFill>
  );
};

/** The cover without its disc (the disc is drawn on its own so it can leave). */
const CoverNoDisc: React.FC<{ size: number; bar: number }> = ({ size, bar }) => {
  const k = size / 900;
  return (
    <div style={{ position: "relative", width: size, height: size, background: C.graphite, overflow: "hidden" }}>
      <div style={{ position: "absolute", left: 0, top: 650 * k + (1 - bar) * 260 * k, width: size, height: 70 * k, background: C.accent }} />
    </div>
  );
};

const EndCard: React.FC<{ F: number }> = ({ F }) => {
  const open = prog(F, END, 30, E.inOut);
  const R = 24 + (Math.hypot(1920, 1080) - 24) * open;
  const drift = 1 + 0.035 * prog(F, s(69), s(7), E.linear);
  const tile = spr(F, s(67.95), "pop");
  const glide = prog(F, s(68.25), 40, E.inOut);
  const ICON = 250;
  const k = ICON / 1024;
  const x1 = 300, y1 = 610, x2 = 660, y2 = 440;
  const dx = lerp(x1, x2, glide), dy = lerp(y1, y2, glide);
  const urls = spr(F, s(72.0), "settle");
  return (
    <div style={{ position: "absolute", inset: 0, clipPath: `circle(${R}px at 960px 600px)`, background: C.paper }}>
      <div style={{ position: "absolute", inset: 0, transform: `scale(${drift})`, transformOrigin: "960px 520px" }}>
        {/* icon */}
        <div style={{ position: "absolute", left: 960 - ICON / 2, top: 128, width: ICON, height: ICON, transform: `scale(${tile})`, borderRadius: ICON * 0.225, background: "#0E0E0E", overflow: "hidden" }}>
          <svg width={ICON} height={ICON} viewBox="0 0 1024 1024">
            <rect x="102" y="222" width="820" height="580" rx="140" fill="#1B1B1B" stroke="#FFFFFF" strokeOpacity="0.1" strokeWidth="4" />
            <line x1={x1} y1={y1} x2={dx} y2={dy} stroke="#FFFFFF" strokeOpacity="0.1" strokeWidth="90" strokeLinecap="round" />
            <circle cx={dx} cy={dy} r="74" fill="#FFFFFF" fillOpacity="0.62" />
          </svg>
        </div>
        <div style={{ position: "absolute", left: 0, right: 0, top: 420, textAlign: "center" }}>
          <Kinetic text="Glasspad" by="letter" at={s(word("end", 0)) - 2} stagger={2.2} style={{ ...T.hero, fontSize: 168, letterSpacing: "-0.05em" }} align="center" />
        </div>
        <div style={{ position: "absolute", left: 0, right: 0, top: 632, textAlign: "center" }}>
          <Kinetic text="Free and open source." at={0} times={words("end").slice(2).map(s)} style={{ ...T.sub, fontSize: 46, fontWeight: 500 }} color={C.ink60} align="center" />
        </div>
        <div style={{ position: "absolute", left: 0, right: 0, top: 760, display: "flex", justifyContent: "center", gap: 48, fontFamily: FONT, fontSize: 32, fontWeight: 600, letterSpacing: "-0.01em", color: C.ink, opacity: clamp01(urls * 1.3), transform: `translateY(${lerp(30, 0, urls)}px)` }}>
          <span>github.com/Soham109/glasspad</span>
          <span style={{ color: C.ink40 }}>·</span>
          <span>glasspad.sohamaggarwal.com</span>
        </div>
        <div style={{ position: "absolute", left: 0, right: 0, top: 830, textAlign: "center", fontFamily: FONT, ...T.label, fontSize: 20, color: C.ink40, opacity: clamp01(spr(F, s(72.4), "settle") * 1.3) }}>MIT License</div>
        <div style={{ position: "absolute", left: 0, right: 0, bottom: 34, textAlign: "center", fontFamily: FONT, fontSize: 17, fontWeight: 500, color: C.ink40, opacity: clamp01(spr(F, s(72.6), "settle")) }}>Music: "Brand New World" by Kai Engel, CC BY 4.0</div>
      </div>
    </div>
  );
};

export const outroCover = Cover;
