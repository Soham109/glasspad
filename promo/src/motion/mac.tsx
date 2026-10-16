import React from "react";
import { AppIcon, Box, CSS, Doc, Glyph, Mark, Win } from "./parts";
import { clamp, lerp, OUT } from "./lib";

/* Windows and system pieces on the Mac's drawn screens, in units of the display (cqw, cqh),
   in the website's style: flat windows, grey text lines, real app layouts reduced to shapes. */

/** Safari: tabs under the toolbar, an address field, a page. `tabs` may be fractional while
    a tab slides in. */
export const SafariWin: React.FC<{ box: Box; front?: boolean; z?: number; tabs?: number; active?: number; page?: React.ReactNode; o?: number; s?: number; origin?: string; style?: CSS; url?: string }> = ({ box, front, z, tabs = 2, active = 0, page, o, s, origin, style, url = "" }) => {
  const n = Math.ceil(tabs - 0.001);
  const grow = tabs - Math.floor(tabs - 0.001) ; // 0..1 for the newest tab
  return (
    <Win box={box} front={front} z={z} o={o} s={s} origin={origin} style={style}
      bar={<span className="fm-url">{url ? <><Glyph n="lock.small" />{url}</> : null}</span>}>
      <div className="fm-tabs">
        {Array.from({ length: n }, (_, i) => {
          const last = i === n - 1 && tabs % 1 !== 0;
          return <span key={i} className={i === active ? "on" : ""} style={last ? { flexGrow: OUT(grow), opacity: clamp(grow * 2) } : undefined}><i /></span>;
        })}
      </div>
      <div style={{ position: "absolute", inset: "5cqh 0 0 0", overflow: "hidden" }}>{page ?? <Doc n={14} />}</div>
    </Win>
  );
};

/** Xcode: navigator, editor, and the toolbar's Run button and activity view. */
export const XcodeWin: React.FC<{ box: Box; front?: boolean; z?: number; status?: string; running?: number; o?: number; s?: number; style?: CSS }> = ({ box, front, z, status = "Build Succeeded", running = 0, o, s, style }) => (
  <Win box={box} front={front} z={z} o={o} s={s} style={style}
    bar={<>
      <span className="fm-xrun" style={{ opacity: 1 - running * 0.45 }}><Glyph n="play.fill" /></span>
      <span className="fm-xrun"><Glyph n="stop.fill" style={{ opacity: 0.35 + running * 0.65 }} /></span>
      <span className="fm-xstat">{running > 0.5 ? <i className="fm-spin" /> : <Glyph n="hammer" />}<b>{status}</b></span>
    </>}>
    <div className="xcw">
      <div className="xc-side">{Array.from({ length: 7 }, (_, i) => <i key={i} />)}</div>
      <div className="xc-code">{["#C2185B 30%", "#1A1A1A 62%", "#2F6FE4 48%", "#1A1A1A 70%", "#8E8E93 40%", "#C2185B 22%", "#1A1A1A 56%", "#2F6FE4 36%", "#1A1A1A 44%"].map((v, i) => { const [c, w] = v.split(" "); return <i key={i} style={{ background: c, width: w }} />; })}</div>
    </div>
  </Win>
);

/** Final Cut Pro: library, viewer, the timeline with its playhead. `cut` 0..1 opens the blade. */
export const FcpWin: React.FC<{ box: Box; front?: boolean; z?: number; head?: number; cut?: number; o?: number; s?: number; style?: CSS }> = ({ box, front, z, head = 0.44, cut = 0, o, s, style }) => {
  const gap = OUT(clamp(cut)) * 0.8;
  return (
    <Win box={box} front={front} z={z} o={o} s={s} style={{ background: "#1C1C1E", ...style }} barStyle={{ background: "#2A2A2C", borderColor: "#000" }}>
      <div className="fm-fcp">
        <div className="fc-top2"><div className="fc-lib">{Array.from({ length: 6 }, (_, i) => <i key={i} />)}</div>
          <div className="fc-view"><div className="fc-frame" style={{ "--p": head } as CSS}><i className="sun" /><i className="sea" /></div></div></div>
        <div className="fc-tl2">
          <div className="fc-track v">
            <i style={{ left: "2%", width: "30%" }} />
            <i className="b" style={{ left: "32.4%", width: `${head * 100 - 32.4 - gap / 2}%` }} />
            <i className="b" style={{ left: `${head * 100 + gap / 2}%`, width: `${60.4 - head * 100 - gap / 2}%`, filter: cut > 0 ? `brightness(${1 + 0.25 * (1 - clamp(cut * 1.6))})` : undefined }} />
            <i style={{ left: "60.8%", width: "21%" }} />
          </div>
          <div className="fc-track a"><i style={{ left: "2%", width: "80%" }} /></div>
          <span className="fc-head" style={{ left: `${head * 100}%` }} />
        </div>
      </div>
    </Win>
  );
};

/** Notes, with typed text and a caret. */
export const NotesWin: React.FC<{ box: Box; front?: boolean; z?: number; text?: string; more?: string; caret?: boolean; o?: number; s?: number; style?: CSS; origin?: string }> = ({ box, front, z, text = "", more = "", caret = true, o, s, style, origin }) => (
  <Win box={box} front={front} z={z} o={o} s={s} origin={origin} style={style} barStyle={{ background: "#F6EFD9" }}>
    <div className="fm-note"><b>Friday</b><span style={{ display: "block" }}>{text}{caret && !more ? <i className="fm-caret2" /> : null}</span>{more ? <span style={{ display: "block" }}>{more}{caret ? <i className="fm-caret2" /> : null}</span> : null}</div>
  </Win>
);

/** Mail: the message list and the reading pane (the site's .mail). */
export const MailWin: React.FC<{ box: Box; front?: boolean; z?: number; o?: number; s?: number; origin?: string }> = ({ box, front, z, o, s, origin }) => (
  <Win box={box} front={front} z={z} o={o} s={s} origin={origin} barStyle={{ background: "#EAF1FB" }}>
    <div className="mail"><div className="ml-l">{Array.from({ length: 6 }, (_, i) => <i key={i} style={i === 0 ? { background: "#3D7BF2", opacity: 0.55 } : undefined} />)}</div><Doc n={8} /></div>
  </Win>
);

/** Music: artwork, the song, a progress bar. */
export const MusicWin: React.FC<{ box: Box; front?: boolean; z?: number; o?: number; s?: number; origin?: string; prog?: number }> = ({ box, front, z, o, s, origin, prog = 0.3 }) => (
  <Win box={box} front={front} z={z} o={o} s={s} origin={origin}>
    <div className="fm-music">
      <div className="art"><i className="a1" /><i className="a2" /></div>
      <div className="meta"><b>Slow Light</b><span>Paper Rooms</span><div className="pb"><i style={{ width: `${prog * 100}%` }} /></div></div>
    </div>
  </Win>
);

/** The Glasspad website, as a page in Safari. */
export const SitePage: React.FC = () => (
  <div className="fm-site">
    <Mark size={0} style={{ width: "11cqw", height: "11cqw" }} />
    <b>Glasspad</b>
    <span>A control surface for your Mac, on your iPhone.</span>
  </div>
);

/** The app switcher (Command Tab): icons in a row, the chosen one framed. p 0..1 shows it. */
export const AppSwitcher: React.FC<{ apps: string[]; sel: number; p: number }> = ({ apps, sel, p }) => {
  if (p <= 0.001) return null;
  return (
    <div className="fm-cmdtab" style={{ opacity: clamp(p * 2), transform: `translate(-50%, -50%) scale(${lerp(0.94, 1, OUT(p))})` }}>
      <span className="sel" style={{ transform: `translateX(${sel * 10.2}cqw)` }} />
      {apps.map(k => <AppIcon key={k} k={k} w="8.4cqw" />)}
    </div>
  );
};

/** A notification banner in the top right. `x` slides it (0 in place, 1 off screen). */
export const Banner: React.FC<{ app: string; title: string; text: string; x: number; o: number; blur?: number }> = ({ app, title, text, x, o, blur = 0 }) =>
  o <= 0.001 ? null : (
    <div className="fm-ban" style={{ right: "1.6cqw", top: "6.4cqh", transform: `translateX(${x * 110}%)`, opacity: o, filter: blur ? `blur(${blur}px)` : undefined }}>
      <AppIcon k={app} />
      <div><b>{title}</b><span>{text}</span></div>
    </div>
  );

/** Menu bar status glyph (the moon for Do Not Disturb). */
export const MenuMoon: React.FC<{ p: number }> = ({ p }) => (
  <span className="fm-mbi" style={{ width: `${2.6 * OUT(clamp(p))}cqh`, opacity: clamp(p * 1.5), transform: `scale(${lerp(0.4, 1, OUT(clamp(p)))})` }}>
    <Glyph n="moon.fill" />
  </span>
);
