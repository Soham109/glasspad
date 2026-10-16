// Thumbnails for the film, 1920x1080 stills (also exported at 1280x720). Every one shows the
// real app (simulator recordings of the iPhone app) driving a Mac whose screen visibly reacts.
// Layout grammar: headline top left, the Mac large on the right, the phone big and angled in front.
import React from "react";
import { AbsoluteFill, Img, OffthreadVideo, staticFile } from "remotion";
import clips from "./clips.json";
import { C, FONT, FPS } from "./system";
import { Dock, MacBook, MenuBar, Player, Pointer, SH, SW, Win, icon } from "./ui/Mac";
import { Phone, phoneScreen } from "./ui/Phone";
import { fingersAt } from "./ui/Clip";
import { Desktop, SafariSpace, SafariWin, TextDoc, WALL, WordWin } from "./scenes/Desktop";

const CL = clips as any;
const H: React.CSSProperties = { fontFamily: FONT, fontWeight: 700, letterSpacing: "-0.05em", lineHeight: 0.98 };

const Rec: React.FC<{ clip: string; t: number; w: number; h: number }> = ({ clip, t, w, h }) => (
  <OffthreadVideo src={staticFile(CL[clip].file)} startFrom={Math.round(t * FPS)} muted style={{ position: "absolute", inset: 0, width: w, height: h, objectFit: "cover" }} />
);

/** Recorded fingers, drawn bold so they read small: rings plus the path they just took. */
const Fingers: React.FC<{ t: number; back: number; w: number; h: number; ring?: number }> = ({ t, back, w, h, ring = 0.22 }) => {
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
          return <path key={k} d={pts.join(" ")} fill="none" stroke={C.paper} strokeOpacity={0.25} strokeWidth={d * 0.62} strokeLinecap="round" />;
        })}
      </svg>
      {now.map(([x, y], i) => (
        <div key={i} style={{ position: "absolute", left: x * w - d / 2, top: y * h - d / 2, width: d, height: d, borderRadius: d, background: "rgba(242,241,238,0.92)" }} />
      ))}
    </>
  );
};

/** Drawn three-finger stroke for gestures the recordings do not contain (Mission Control). */
const Strokes: React.FC<{ w: number; h: number; from: [number, number][]; to: [number, number][]; ring: number }> = ({ w, h, from, to, ring }) => {
  const d = h * ring;
  return (
    <>
      <svg width={w} height={h} style={{ position: "absolute", inset: 0 }}>
        {from.map(([x0, y0], i) => <line key={i} x1={x0 * w} y1={y0 * h} x2={to[i][0] * w} y2={to[i][1] * h} stroke={C.paper} strokeOpacity={0.25} strokeWidth={d * 0.62} strokeLinecap="round" />)}
      </svg>
      {to.map(([x, y], i) => <div key={i} style={{ position: "absolute", left: x * w - d / 2, top: y * h - d / 2, width: d, height: d, borderRadius: d, background: "rgba(242,241,238,0.92)" }} />)}
    </>
  );
};

const Headline: React.FC<{ lines: React.ReactNode; color?: string; size?: number; top?: number }> = ({ lines, color = C.ink, size = 150, top = 80 }) => (
  <div style={{ position: "absolute", left: 80, top, ...H, fontSize: size, color }}>{lines}</div>
);
const A: React.FC<{ children: React.ReactNode }> = ({ children }) => <span style={{ color: C.accent }}>{children}</span>;

// The Mac on the right of every thumbnail.
const MAC = { left: 800, top: 80, width: 1100 };
const Mac: React.FC<{ children: React.ReactNode }> = ({ children }) => (
  <div style={{ position: "absolute", left: MAC.left, top: MAC.top }}>
    <MacBook width={MAC.width}>{children}</MacBook>
  </div>
);

// 1. Your iPhone is a trackpad: one finger glides, the pointer lands on a folder and selects it.
export const Thumb1: React.FC = () => {
  const ps = 500, sc = phoneScreen(ps, "landscape");
  return (
    <AbsoluteFill style={{ background: C.paper, overflow: "hidden" }}>
      <Mac>
        <Desktop app="Finder" word selected={0} running={["com.apple.finder", "com.apple.Safari"]} />
        <svg width={SW} height={SH} style={{ position: "absolute", inset: 0 }}>
          <path d="M 560 760 Q 900 260 1400 120" fill="none" stroke={C.accent} strokeWidth={12} strokeLinecap="round" strokeDasharray="1 30" />
        </svg>
        <Pointer x={1405} y={118} scale={3} />
      </Mac>
      <Headline lines={<>Your iPhone<br />is a <A>trackpad.</A></>} size={124} />
      <div style={{ position: "absolute", left: 560, top: 820, transform: "translate(-50%, -50%) rotate(-7deg)" }}>
        <Phone short={ps} orient="landscape" island={false}>
          <Rec clip="trackpad" t={7.4} w={sc.w} h={sc.h} />
          <Fingers t={5.3} back={1.2} w={sc.w} h={sc.h} ring={0.25} />
        </Phone>
      </div>
    </AbsoluteFill>
  );
};

// 2. Spaces: three fingers swipe, the desktops slide with them.
export const Thumb2: React.FC = () => {
  const ps = 520, sc = phoneScreen(ps, "landscape");
  const p = 0.5;
  return (
    <AbsoluteFill style={{ background: C.graphite, overflow: "hidden" }}>
      <Mac>
        <div style={{ position: "absolute", left: 0, top: 0, width: SW, height: SH, overflow: "hidden" }}>
          <div style={{ position: "absolute", left: -p * SW, top: 0 }}><Desktop app="TextEdit" word dock={false} /></div>
          <div style={{ position: "absolute", left: (1 - p) * SW, top: 0 }}><SafariSpace /></div>
          <Dock running={["com.apple.finder", "com.apple.Safari"]} dark />
        </div>
      </Mac>
      <Headline color={C.paper} lines={<>Swipe<br />between<br /><A>Spaces.</A></>} size={112} />
      <div style={{ position: "absolute", left: 590, top: 830, transform: "translate(-50%, -50%) rotate(-6deg)" }}>
        <Phone short={ps} orient="landscape" island={false}>
          <Rec clip="trackpad" t={7.4} w={sc.w} h={sc.h} />
          <Fingers t={8.95} back={0.6} w={sc.w} h={sc.h} ring={0.18} />
        </Phone>
      </div>
    </AbsoluteFill>
  );
};

// 3. Mission Control: three fingers up, every window laid out.
const Thumbnail: React.FC<{ x: number; y: number; s: number; children: React.ReactNode; w: number; h: number }> = ({ x, y, s, children, w, h }) => (
  <div style={{ position: "absolute", left: x, top: y, width: w * s, height: h * s }}>
    <div style={{ position: "absolute", left: 0, top: 0, width: w, height: h, transform: `scale(${s})`, transformOrigin: "0 0" }}>{children}</div>
  </div>
);
const MissionControl: React.FC = () => (
  <div style={{ position: "absolute", left: 0, top: 0, width: SW, height: SH, background: "#3A3A3A" }}>
    <div style={{ position: "absolute", left: 0, right: 0, top: 22, display: "flex", justifyContent: "center", gap: 36 }}>
      {[WALL.light, WALL.dark, "#4A4A4A"].map((c, i) => (
        <div key={i} style={{ width: 190, height: 118, borderRadius: 12, background: c, boxShadow: i === 0 ? `0 0 0 4px ${C.paper}` : "none" }} />
      ))}
    </div>
    <Thumbnail x={90} y={220} s={0.42} w={900} h={700}>
      <Win x={0} y={0} w={900} h={700} title="Field notes.txt"><TextDoc /></Win>
    </Thumbnail>
    <Thumbnail x={560} y={200} s={0.48} w={1272} h={760}>
      <div style={{ position: "absolute", left: -120, top: -74 }}><SafariWin /></div>
    </Thumbnail>
    <Thumbnail x={330} y={560} s={0.36} w={1212} h={720}>
      <Win x={0} y={0} w={1212} h={720} dark title="Spotify"><Player progress={0.4} elapsed="1:07" remain="-1:40" /></Win>
    </Thumbnail>
    <Thumbnail x={830} y={590} s={0.4} w={900} h={640}>
      <Win x={0} y={0} w={900} h={640} title="Field notes.docx"><TextDoc /></Win>
    </Thumbnail>
  </div>
);
export const Thumb3: React.FC = () => {
  const ps = 520, sc = phoneScreen(ps, "landscape");
  return (
    <AbsoluteFill style={{ background: C.paper, overflow: "hidden" }}>
      <Mac><MissionControl /></Mac>
      <Headline lines={<>Mission<br />Control<br /><A>from your<br />phone.</A></>} size={112} top={70} />
      <div style={{ position: "absolute", left: 1350, top: 900, transform: "translate(-50%, -50%) rotate(-4deg)" }}>
        <Phone short={ps} orient="landscape" island={false}>
          <Strokes w={sc.w} h={sc.h} from={[[0.38, 0.88], [0.5, 0.92], [0.62, 0.88]]} to={[[0.38, 0.32], [0.5, 0.36], [0.62, 0.32]]} ring={0.19} />
        </Phone>
      </div>
    </AbsoluteFill>
  );
};

// 4. Spotify: the real Media screen, the same song playing on the Mac.
export const Thumb4: React.FC = () => {
  const ps = 500, sc = phoneScreen(ps, "portrait");
  const [u0, u1] = CL.media.scrubX as number[];
  return (
    <AbsoluteFill style={{ background: C.accent, overflow: "hidden" }}>
      <Mac>
        <div style={{ position: "absolute", inset: 0, background: WALL.dark }}>
          <Win x={110} y={70} w={1290} h={760} dark title="Spotify"><Player progress={0.68} elapsed="1:54" remain="-0:53" /></Win>
          <MenuBar app="Spotify" dark />
          <Dock running={["com.apple.finder", "com.spotify.client"]} dark />
        </div>
      </Mac>
      <Headline color={C.paper} lines={<>Spotify<br />on your<br />phone.</>} size={116} top={90} />
      <div style={{ position: "absolute", left: 860, top: 690, transform: "translate(-50%, -50%) rotate(-5deg)" }}>
        <Phone short={ps} orient="portrait" island={false}>
          <Rec clip="media" t={7.0} w={sc.w} h={sc.h} />
          <div style={{ position: "absolute", left: (u0 + (u1 - u0) * 0.68) * sc.w - 46, top: CL.media.scrubY * sc.h - 46, width: 92, height: 92, borderRadius: 92, background: "rgba(242,241,238,0.85)" }} />
        </Phone>
      </div>
    </AbsoluteFill>
  );
};

// 5. Buttons for every app: Screenshot pressed on the phone, the Mac takes the shot.
export const Thumb5: React.FC = () => {
  const ps = 500, sc = phoneScreen(ps, "portrait");
  const [su, sv] = CL.actions.screenshot as number[];
  return (
    <AbsoluteFill style={{ background: C.paper, overflow: "hidden" }}>
      <Mac>
        <div style={{ position: "absolute", inset: 0, background: WALL.dark }}>
          <SafariWin />
          <MenuBar app="Safari" dark />
          <Dock running={["com.apple.finder", "com.apple.Safari"]} dark />
          {/* the capture: a white flash frame and the floating screenshot in the corner */}
          <div style={{ position: "absolute", inset: 0, boxShadow: `inset 0 0 0 40px ${C.paper}` }} />
          <div style={{ position: "absolute", right: 60, bottom: 130, width: 380, height: 250, borderRadius: 14, background: C.paper, padding: 10, boxShadow: `0 0 0 3px ${C.ink12}` }}>
            <div style={{ position: "relative", width: 360, height: 230, overflow: "hidden", borderRadius: 8, background: WALL.dark }}>
              <div style={{ position: "absolute", left: 0, top: 0, width: SW, height: SH, transform: `scale(${360 / SW})`, transformOrigin: "0 0" }}><SafariWin /></div>
            </div>
          </div>
        </div>
      </Mac>
      <Headline lines={<>Buttons<br />for every<br /><A>app.</A></>} size={116} top={90} />
      <div style={{ position: "absolute", left: 860, top: 640, transform: "translate(-50%, -50%) rotate(-5deg)" }}>
        <Phone short={ps} orient="portrait" island={false}>
          <Rec clip="actions" t={7.6} w={sc.w} h={sc.h} />
          <div style={{ position: "absolute", left: su * sc.w - 62, top: sv * sc.h - 62, width: 124, height: 124, borderRadius: 124, boxShadow: `inset 0 0 0 9px ${C.accent}` }} />
        </Phone>
      </div>
    </AbsoluteFill>
  );
};

export const thumbIcon = icon;
export const ThumbImg = Img;

// 6. Dock: tap Word on the phone, Word opens on the Mac (Dock icon mid bounce, window opening).
export const Thumb6: React.FC = () => {
  const ps = 500, sc = phoneScreen(ps, "portrait");
  const dk = CL.dock ?? { file: CL.menu.file, wordIcon: CL.menu.wordIcon, t: 9.0 };
  const [wu, wv] = dk.wordIcon as number[];
  return (
    <AbsoluteFill style={{ background: C.graphite, overflow: "hidden" }}>
      <Mac>
        <div style={{ position: "absolute", inset: 0, background: WALL.dark }}>
          <SafariWin active={false} />
          <div style={{ position: "absolute", inset: 0, transform: "scale(0.92)", transformOrigin: "760px 900px" }}>
            <WordWin />
          </div>
          <MenuBar app="Microsoft Word" dark />
          <Dock running={["com.apple.finder", "com.apple.Safari", "com.microsoft.Word"]} bounce={{ "com.microsoft.Word": 40 }} dark />
        </div>
      </Mac>
      <Headline color={C.paper} lines={<>Open any<br /><A>Mac app.</A></>} size={116} top={90} />
      <div style={{ position: "absolute", left: 930, top: 720, transform: "translate(-50%, -50%) rotate(-5deg)" }}>
        <Phone short={ps} orient="portrait" island={false}>
          <OffthreadVideo src={staticFile(dk.file)} startFrom={Math.round(dk.t * FPS)} muted style={{ position: "absolute", inset: 0, width: sc.w, height: sc.h, objectFit: "cover" }} />
          <div style={{ position: "absolute", left: wu * sc.w - 62, top: wv * sc.h - 62, width: 124, height: 124, borderRadius: 124, boxShadow: `inset 0 0 0 9px ${C.accent}` }} />
        </Phone>
      </div>
    </AbsoluteFill>
  );
};
