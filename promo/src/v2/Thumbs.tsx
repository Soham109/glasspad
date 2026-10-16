// Five thumbnails for the film, 1920x1080 stills (also exported at 1280x720). Same palette,
// type and assets as the film: real phone screens from the recordings, the flat Mac, the icon.
import React from "react";
import { AbsoluteFill, Img, OffthreadVideo, staticFile } from "remotion";
import clips from "./clips.json";
import { C, FONT, FPS } from "./system";
import { MacBook, Pointer, SW, icon } from "./ui/Mac";
import { Phone, phoneScreen } from "./ui/Phone";
import { fingersAt } from "./ui/Clip";
import { Desktop, SafariSpace } from "./scenes/Desktop";

const CL = clips as any;
const H: React.CSSProperties = { fontFamily: FONT, fontWeight: 700, letterSpacing: "-0.05em", lineHeight: 0.98 };

/** One frame of a phone recording. */
const Rec: React.FC<{ clip: string; t: number; w: number; h: number }> = ({ clip, t, w, h }) => (
  <OffthreadVideo src={staticFile(CL[clip].file)} startFrom={Math.round(t * FPS)} muted style={{ position: "absolute", inset: 0, width: w, height: h, objectFit: "cover" }} />
);

/** Finger rings with trails from the recorded swipe, drawn bold for small sizes. */
const Fingers: React.FC<{ t: number; back: number; w: number; h: number; color?: string; ring?: number }> = ({ t, back, w, h, color = C.paper, ring = 0.22 }) => {
  const now = fingersAt(t);
  const d = h * ring;
  return (
    <>
      <svg width={w} height={h} style={{ position: "absolute", inset: 0 }}>
        {now.map((_, k) => {
          const pts: string[] = [];
          for (let j = 0; j <= Math.round(back * FPS); j += 2) {
            const fs = fingersAt(t - j / FPS);
            if (fs.length !== now.length) break;
            pts.push(`${j ? "L" : "M"}${(fs[k][0] * w).toFixed(1)} ${(fs[k][1] * h).toFixed(1)}`);
          }
          return <path key={k} d={pts.join(" ")} fill="none" stroke={color} strokeOpacity={0.22} strokeWidth={d * 0.62} strokeLinecap="round" />;
        })}
      </svg>
      {now.map(([x, y], i) => (
        <div key={i} style={{ position: "absolute", left: x * w - d / 2, top: y * h - d / 2, width: d, height: d, borderRadius: d, background: "rgba(242,241,238,0.9)" }} />
      ))}
    </>
  );
};

// 1. "Your iPhone is a trackpad": the phone in front of the Mac, one finger mid glide.
export const Thumb1: React.FC = () => {
  const ps = 420, sc = phoneScreen(ps, "landscape");
  return (
    <AbsoluteFill style={{ background: C.paper, overflow: "hidden" }}>
      <div style={{ position: "absolute", left: 90, top: 150, ...H, fontSize: 170, color: C.ink }}>
        Your<br />iPhone is a<br /><span style={{ color: C.accent }}>trackpad.</span>
      </div>
      <div style={{ position: "absolute", left: 1010, top: 70 }}>
        <MacBook width={1080}>
          <Desktop app="TextEdit" word running={["com.apple.finder", "com.apple.Safari"]} />
          <Pointer x={980} y={430} scale={2.4} />
        </MacBook>
      </div>
      <div style={{ position: "absolute", left: 1500, top: 830, transform: "translate(-50%, -50%) rotate(-6deg)" }}>
        <Phone short={ps} orient="landscape" island={false}>
          <Rec clip="trackpad" t={7.4} w={sc.w} h={sc.h} />
          <Fingers t={4.9} back={0.9} w={sc.w} h={sc.h} ring={0.26} />
        </Phone>
      </div>
    </AbsoluteFill>
  );
};

// 2. Spaces: three fingers, long trails, the desktops sliding behind.
export const Thumb2: React.FC = () => {
  const ps = 640, sc = phoneScreen(ps, "landscape");
  const p = 0.55;
  return (
    <AbsoluteFill style={{ background: C.graphite, overflow: "hidden" }}>
      <div style={{ position: "absolute", left: 1000, top: -40, opacity: 0.95 }}>
        <MacBook width={1100} base={false}>
          <div style={{ position: "absolute", left: -p * SW, top: 0 }}><Desktop app="TextEdit" word dock={false} /></div>
          <div style={{ position: "absolute", left: (1 - p) * SW, top: 0 }}><SafariSpace /></div>
        </MacBook>
      </div>
      <div style={{ position: "absolute", left: 80, top: 70, ...H, fontSize: 160, color: C.paper }}>
        Swipe<br />between<br /><span style={{ color: C.accent }}>Spaces.</span>
      </div>
      <div style={{ position: "absolute", left: 1290, top: 845, transform: "translate(-50%, -50%) rotate(-4deg)" }}>
        <Phone short={ps} orient="landscape" island={false}>
          <Rec clip="trackpad" t={7.4} w={sc.w} h={sc.h} />
          <Fingers t={8.95} back={0.6} w={sc.w} h={sc.h} ring={0.17} />
        </Phone>
      </div>
    </AbsoluteFill>
  );
};

// 3. Actions follow the Mac: the phone's Safari buttons, the Safari icon arriving.
export const Thumb3: React.FC = () => {
  const ps = 560, sc = phoneScreen(ps, "portrait");
  return (
    <AbsoluteFill style={{ background: C.paper, overflow: "hidden" }}>
      <div style={{ position: "absolute", left: 90, top: 170, ...H, fontSize: 168, color: C.ink }}>
        Buttons<br />that follow<br /><span style={{ color: C.accent }}>your Mac.</span>
      </div>
      <div style={{ position: "absolute", left: 1500, top: 600, transform: "translate(-50%, -50%) rotate(4deg)" }}>
        <Phone short={ps} orient="portrait" island={false}>
          <Rec clip="actions" t={7.6} w={sc.w} h={sc.h} />
          <div style={{ position: "absolute", left: sc.w * 0.02, top: sc.h * 0.13, width: sc.w * 0.96, height: sc.h * 0.29, borderRadius: 30, boxShadow: `inset 0 0 0 7px ${C.accent}` }} />
        </Phone>
      </div>
      <svg width={1920} height={1080} style={{ position: "absolute", inset: 0 }}>
        <path d="M 1080 900 Q 1080 420 1270 300" fill="none" stroke={C.accent} strokeWidth={10} strokeLinecap="round" strokeDasharray="2 26" />
      </svg>
      <Img src={icon("com.apple.Safari")} style={{ position: "absolute", left: 990, top: 840, width: 180, height: 180 }} />
    </AbsoluteFill>
  );
};

// 4. Graphite: the icon, large, and the name.
export const Thumb4: React.FC = () => {
  const S = 620;
  return (
    <AbsoluteFill style={{ background: C.graphite, overflow: "hidden" }}>
      <div style={{ position: "absolute", left: 110, top: 230, width: S, height: S, borderRadius: S * 0.225, background: "#0E0E0E", boxShadow: `inset 0 0 0 3px ${C.paper12}`, overflow: "hidden" }}>
        <svg width={S} height={S} viewBox="0 0 1024 1024">
          <rect x="102" y="222" width="820" height="580" rx="140" fill="#1B1B1B" stroke="#FFFFFF" strokeOpacity="0.1" strokeWidth="4" />
          <line x1="300" y1="610" x2="660" y2="440" stroke="#FFFFFF" strokeOpacity="0.14" strokeWidth="90" strokeLinecap="round" />
          <circle cx="660" cy="440" r="74" fill="#FFFFFF" fillOpacity="0.85" />
        </svg>
      </div>
      <div style={{ position: "absolute", left: 830, top: 330, ...H, fontSize: 210, color: C.paper }}>Glasspad</div>
      <div style={{ position: "absolute", left: 838, top: 580, fontFamily: FONT, fontWeight: 600, fontSize: 76, letterSpacing: "-0.03em", lineHeight: 1.1, color: C.paper60 }}>
        Your iPhone,<br />as a Mac trackpad.
      </div>
    </AbsoluteFill>
  );
};

// 5. "Free. Open source." with the Mac and the phone side by side.
export const Thumb5: React.FC = () => {
  const ps = 430, sc = phoneScreen(ps, "portrait");
  return (
    <AbsoluteFill style={{ background: C.paper, overflow: "hidden" }}>
      <div style={{ position: "absolute", left: 90, top: 140, ...H, fontSize: 200, color: C.ink }}>
        Free.<br />Open<br />source.
      </div>
      <div style={{ position: "absolute", left: 880, top: 220 }}>
        <MacBook width={820}>
          <SafariSpace />
        </MacBook>
      </div>
      <div style={{ position: "absolute", left: 1640, top: 600, transform: "translate(-50%, -50%)" }}>
        <Phone short={ps} orient="portrait" island={false}>
          <Rec clip="menu" t={8.6} w={sc.w} h={sc.h} />
        </Phone>
      </div>
      <div style={{ position: "absolute", left: 96, top: 930, fontFamily: FONT, fontWeight: 600, fontSize: 44, letterSpacing: "-0.01em", color: C.ink60 }}>github.com/Soham109/glasspad</div>
    </AbsoluteFill>
  );
};
