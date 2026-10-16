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

// ---------- second set ----------

/** Drawn finger rings with straight trails (for gestures the recordings do not contain). */
const Strokes: React.FC<{ w: number; h: number; from: [number, number][]; to: [number, number][]; ring: number }> = ({ w, h, from, to, ring }) => {
  const d = h * ring;
  return (
    <>
      <svg width={w} height={h} style={{ position: "absolute", inset: 0 }}>
        {from.map(([x0, y0], i) => (
          <line key={i} x1={x0 * w} y1={y0 * h} x2={to[i][0] * w} y2={to[i][1] * h} stroke={C.paper} strokeOpacity={0.22} strokeWidth={d * 0.62} strokeLinecap="round" />
        ))}
      </svg>
      {to.map(([x, y], i) => (
        <div key={i} style={{ position: "absolute", left: x * w - d / 2, top: y * h - d / 2, width: d, height: d, borderRadius: d, background: "rgba(242,241,238,0.9)" }} />
      ))}
    </>
  );
};

// 6. Music: the real Media screen, the scrub under a finger.
export const Thumb6: React.FC = () => {
  const ps = 600, sc = phoneScreen(ps, "portrait");
  const [u0, u1] = CL.media.scrubX as number[];
  return (
    <AbsoluteFill style={{ background: C.accent, overflow: "hidden" }}>
      <div style={{ position: "absolute", left: 90, top: 210, ...H, fontSize: 190, color: C.paper }}>
        Control<br />your<br />music.
      </div>
      <div style={{ position: "absolute", left: 1420, top: 760, transform: "translate(-50%, -50%) rotate(-5deg)" }}>
        <Phone short={ps} orient="portrait" island={false}>
          <Rec clip="media" t={6.8} w={sc.w} h={sc.h} />
          <div style={{ position: "absolute", left: (u0 + (u1 - u0) * 0.72) * sc.w - 50, top: CL.media.scrubY * sc.h - 50, width: 100, height: 100, borderRadius: 100, background: "rgba(242,241,238,0.85)" }} />
        </Phone>
      </div>
    </AbsoluteFill>
  );
};

// 7. Apps: tap Word on the phone, it opens on the Mac.
export const Thumb7: React.FC = () => {
  const ps = 560, sc = phoneScreen(ps, "portrait");
  const [wu, wv] = CL.menu.wordIcon as number[];
  return (
    <AbsoluteFill style={{ background: C.graphite, overflow: "hidden" }}>
      <div style={{ position: "absolute", left: 90, top: 220, ...H, fontSize: 160, color: C.paper }}>
        Every<br />app, <span style={{ color: C.accent }}>one<br />tap.</span>
      </div>
      <div style={{ position: "absolute", left: 1180, top: 640, transform: "translate(-50%, -50%) rotate(-3deg)" }}>
        <Phone short={ps} orient="portrait" island={false}>
          <Rec clip="menu" t={8.6} w={sc.w} h={sc.h} />
          <div style={{ position: "absolute", left: wu * sc.w - 70, top: wv * sc.h - 70, width: 140, height: 140, borderRadius: 140, boxShadow: `inset 0 0 0 8px ${C.paper}` }} />
        </Phone>
      </div>
      <svg width={1920} height={1080} style={{ position: "absolute", inset: 0 }}>
        <path d="M 1160 560 Q 1500 220 1680 540" fill="none" stroke={C.paper} strokeOpacity={0.5} strokeWidth={10} strokeLinecap="round" strokeDasharray="2 26" />
      </svg>
      <Img src={icon("com.microsoft.Word")} style={{ position: "absolute", left: 1570, top: 520, width: 260, height: 260 }} />
    </AbsoluteFill>
  );
};

// 8. Before and after: the trackpad on the desk, and the one in your pocket.
export const Thumb8: React.FC = () => {
  const ps = 330, sc = phoneScreen(ps, "landscape");
  return (
    <AbsoluteFill style={{ background: C.paper, overflow: "hidden" }}>
      <div style={{ position: "absolute", left: 960, top: 0, width: 960, height: 1080, background: C.ink }} />
      <div style={{ position: "absolute", left: 90, top: 130, ...H, fontSize: 132, color: C.ink }}>
        Your<br />trackpad.
      </div>
      <div style={{ position: "absolute", left: 1050, top: 130, ...H, fontSize: 132, color: C.paper }}>
        Now in<br />your pocket.
      </div>
      <div style={{ position: "absolute", left: 140, top: 520, width: 640, height: 430, borderRadius: 42, background: "#DDDAD3", boxShadow: `inset 0 0 0 3px ${C.ink12}` }} />
      <div style={{ position: "absolute", left: 1440, top: 760, transform: "translate(-50%, -50%) rotate(-8deg)" }}>
        <Phone short={ps * 1.25} orient="landscape" island={false}>
          <Rec clip="trackpad" t={7.4} w={phoneScreen(ps * 1.25, "landscape").w} h={phoneScreen(ps * 1.25, "landscape").h} />
          <Fingers t={4.9} back={0.9} w={phoneScreen(ps * 1.25, "landscape").w} h={phoneScreen(ps * 1.25, "landscape").h} ring={0.26} />
        </Phone>
      </div>
      <div style={{ position: "absolute", left: sc.w * 0, top: 0 }} />
    </AbsoluteFill>
  );
};

// 9. Minimal: the finger dot's glide, one word.
export const Thumb9: React.FC = () => (
  <AbsoluteFill style={{ background: C.graphite, overflow: "hidden" }}>
    <svg width={1920} height={1080} style={{ position: "absolute", inset: 0 }}>
      <line x1={260} y1={900} x2={1430} y2={330} stroke={C.paper} strokeOpacity={0.12} strokeWidth={230} strokeLinecap="round" />
      <circle cx={1430} cy={330} r={190} fill={C.paper} fillOpacity={0.92} />
    </svg>
    <div style={{ position: "absolute", left: 120, top: 120, ...H, fontSize: 300, color: C.paper }}>Glide.</div>
  </AbsoluteFill>
);

// 10. Mission Control from the phone: three fingers up, every window laid out.
const MissionControl: React.FC = () => {
  const wins: [number, number, number, number, string][] = [[120, 230, 560, 380, "notes"], [760, 210, 640, 420, "site"], [330, 650, 420, 260, "dark"], [880, 680, 460, 250, "light"]];
  return (
    <div style={{ position: "absolute", left: 0, top: 0, width: SW, height: 982, background: "#2B2B2B" }}>
      <div style={{ position: "absolute", left: 0, right: 0, top: 26, display: "flex", justifyContent: "center", gap: 40 }}>
        {["Desktop 1", "Desktop 2", "Desktop 3"].map((d, i) => (
          <div key={d} style={{ textAlign: "center", fontFamily: FONT, fontSize: 18, fontWeight: 600, color: C.paper60 }}>
            <div style={{ width: 200, height: 120, borderRadius: 12, background: i === 0 ? "#D9D6CF" : i === 1 ? "#232323" : "#3A3A3A", boxShadow: i === 0 ? `0 0 0 4px ${C.paper}` : "none", marginBottom: 8 }} />
            {d}
          </div>
        ))}
      </div>
      {wins.map(([x, y, w, h, k]) => (
        <div key={k} style={{ position: "absolute", left: x, top: y, width: w, height: h, borderRadius: 14, background: k === "dark" ? "#1E1E1E" : C.sheet, overflow: "hidden" }}>
          <div style={{ height: 30, borderBottom: `1px solid ${C.ink06}` }} />
          {k === "site" ? <div style={{ margin: 22, height: 150, borderRadius: 12, background: C.ink }} /> : null}
          <div style={{ margin: "18px 22px", display: "grid", gap: 12 }}>
            {[90, 75, 85, 60].map((p, i) => <div key={i} style={{ width: `${p}%`, height: 10, borderRadius: 10, background: k === "dark" ? C.paper12 : C.ink12 }} />)}
          </div>
        </div>
      ))}
    </div>
  );
};
export const Thumb10: React.FC = () => {
  const ps = 380, sc = phoneScreen(ps, "landscape");
  return (
    <AbsoluteFill style={{ background: C.paper, overflow: "hidden" }}>
      <div style={{ position: "absolute", left: 90, top: 150, ...H, fontSize: 150, color: C.ink }}>
        Mission<br />Control.<br /><span style={{ color: C.accent }}>From your<br />phone.</span>
      </div>
      <div style={{ position: "absolute", left: 930, top: 60 }}>
        <MacBook width={900}><MissionControl /></MacBook>
      </div>
      <div style={{ position: "absolute", left: 1380, top: 860, transform: "translate(-50%, -50%) rotate(-3deg)" }}>
        <Phone short={ps} orient="landscape" island={false}>
          <Strokes w={sc.w} h={sc.h} from={[[0.4, 0.86], [0.52, 0.9], [0.64, 0.86]]} to={[[0.4, 0.3], [0.52, 0.34], [0.64, 0.3]]} ring={0.2} />
        </Phone>
      </div>
    </AbsoluteFill>
  );
};

// 11. Private: everything stays inside your Wi-Fi.
export const Thumb11: React.FC = () => (
  <AbsoluteFill style={{ background: C.paper, overflow: "hidden" }}>
    <div style={{ position: "absolute", left: 90, top: 120, ...H, fontSize: 190, color: C.ink }}>
      Stays on<br />your <span style={{ color: C.accent }}>Wi-Fi.</span>
    </div>
    <div style={{ position: "absolute", left: 110, top: 600, width: 1700, height: 400, borderRadius: 60, boxShadow: `inset 0 0 0 6px ${C.ink}` }} />
    <div style={{ position: "absolute", left: 300, top: 650, width: 150, height: 300, borderRadius: 30, boxShadow: `inset 0 0 0 8px ${C.ink}` }}>
      <div style={{ position: "absolute", left: 50, top: 16, width: 50, height: 14, borderRadius: 14, background: C.ink }} />
    </div>
    <div style={{ position: "absolute", left: 470, top: 796, width: 900, height: 8, background: C.ink, opacity: 0.25 }} />
    {[560, 720, 1230].map((x, i) => <div key={i} style={{ position: "absolute", left: x - 16, top: 784, width: 32, height: 32, borderRadius: 32, background: i < 2 ? C.ink : "transparent", boxShadow: `inset 0 0 0 6px ${C.ink}` }} />)}
    <div style={{ position: "absolute", left: 900, top: 690, width: 110, height: 130 }}>
      <div style={{ position: "absolute", left: 22, top: 0, width: 66, height: 72, borderRadius: "33px 33px 0 0", boxShadow: `inset 0 0 0 12px ${C.accent}` }} />
      <div style={{ position: "absolute", left: 0, top: 56, width: 110, height: 74, borderRadius: 16, background: C.accent }} />
    </div>
    <div style={{ position: "absolute", left: 1400, top: 680 }}>
      <div style={{ width: 340, height: 220, borderRadius: 20, boxShadow: `inset 0 0 0 8px ${C.ink}` }} />
      <div style={{ marginLeft: -26, marginTop: 10, width: 392, height: 14, borderRadius: 14, background: C.ink }} />
    </div>
  </AbsoluteFill>
);
