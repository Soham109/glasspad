import React from "react";
import { useCurrentFrame } from "remotion";
import { Title, Finger, Glyph, Phone, Poster, Ring } from "../parts";
import { clamp, E, INOUT, K, lerp, OUT, SP, TAP } from "../kit";
import { sceneSec, word, titleAt } from "../timeline";

/* Scenes 7 and 8: the couch (Remote) and the stage (Present). The phone in hand stays where it
   is; a touch on it opens the lit stage around the dot, and the phone is now in Present
   (PresentMode.swift): timer, laser pad, Back and Next. Film seconds. */

const R0 = sceneSec("remote"), P0 = sceneSec("present");
export const CT = {
  room: R0 + 0.05,
  skip: [R0 + 1.05, R0 + 1.45] as const,
  vol: [R0 + 2.45, R0 + 3.05] as const,
  search: R0 + 3.85, type0: R0 + 4.55, type1: R0 + 5.85, ret: R0 + 6.2,
  dot: P0 - 0.85, wipe: [P0 - 0.68, P0 - 0.02] as const,
  next1: P0 + 0.62,
  hold: P0 + word("present", "time") - 0.35, laser: [P0 + word("present", "time") - 0.15, P0 + word("present", "you") + 0.55] as const,
  next2: P0 + 4.15,
};
export const COUCH_CUES = () => ({
  tap: [CT.search, CT.ret, CT.dot, CT.next1, CT.next2],
  swipe: [[CT.skip[0], CT.skip[1]], [CT.vol[0], CT.vol[1]]] as [number, number][],
  key: Array.from({ length: 11 }, (_, i) => CT.type0 + i * (CT.type1 - CT.type0) / 11),
  skip: [CT.skip[1]],
  whoosh: [CT.wipe[0] + 0.1],
  drag: [[CT.laser[0], CT.laser[1]]] as [number, number][],
});

/* Remote glyphs (web/src/scenes.ts) */
const RG: Record<string, string> = {
  back10: '<path d="M6 12a6.5 6.5 0 1 0 2-4.7"/><path d="M7.6 3.8 8 7.6l-3.8.4"/><text x="12" y="15" text-anchor="middle" font-size="6.2" font-weight="700" fill="currentColor" stroke="none">10</text>',
  fwd10: '<path d="M18 12a6.5 6.5 0 1 1-2-4.7"/><path d="m16.4 3.8-.4 3.8 3.8.4"/><text x="12" y="15" text-anchor="middle" font-size="6.2" font-weight="700" fill="currentColor" stroke="none">10</text>',
  pause: '<rect class="f" x="6.5" y="5" width="4" height="14" rx="1.2"/><rect class="f" x="13.5" y="5" width="4" height="14" rx="1.2"/>',
  play: '<path class="f" d="M7 4.8v14.4a1 1 0 0 0 1.5.9l11.2-7.2a1 1 0 0 0 0-1.7L8.5 3.9A1 1 0 0 0 7 4.8Z"/>',
  hand: '<path d="M10 13V5.8a1.6 1.6 0 0 1 3.2 0V11M13.2 10.5v-1a1.6 1.6 0 0 1 3.2 0v1.8M16.4 11.3a1.6 1.6 0 0 1 3.2 0v2.9a6.8 6.8 0 0 1-6.8 6.8h-.6a6 6 0 0 1-4.7-2.3L4.6 15.2a1.5 1.5 0 0 1 2.3-1.9L10 16"/><path d="M5.5 7.5a5 5 0 0 1 2.4-3.6"/>',
  more: '<circle class="f" cx="6.5" cy="12" r="1.4"/><circle class="f" cx="12" cy="12" r="1.4"/><circle class="f" cx="17.5" cy="12" r="1.4"/>',
  "forward.end": '<path d="M6.5 6v12l9-6Z"/><path d="M17.5 6v12"/>',
  "speaker.slash": '<path d="M4 9.5h3l4.5-4v13l-4.5-4H4Z"/><path d="M3.5 3.5 20.5 20.5"/>',
};
const RI: React.FC<{ g: string; style?: React.CSSProperties }> = ({ g, style }) => <svg viewBox="0 0 24 24" style={style} dangerouslySetInnerHTML={{ __html: RG[g] }} />;

const SPLIT6 = Math.round((874 - 12) * 0.6);
const QUERY = "quiet coast";

/* ---------- the phone ---------- */
const RemoteTop: React.FC<{ t: number }> = ({ t }) => {
  const search = SP(t, CT.search + 0.08, 0.42, 0.9) * (1 - E(t, CT.ret + 0.75, 0.45, INOUT));
  const n = Math.floor(clamp((t - CT.type0) / (CT.type1 - CT.type0)) * QUERY.length + 0.0001);
  const per = (CT.type1 - CT.type0) / QUERY.length;
  const live = t >= CT.type0 && t < CT.type1;
  const ch = live ? QUERY[Math.min(n, QUERY.length - 1)].toUpperCase() : "";
  const hit = live && ((t - CT.type0) % per) < per * 0.6;
  const sTap = TAP(t, CT.search);
  const playing = true;
  void hit; void ch;
  return (
    <>
      <div style={{ position: "absolute", inset: 0, opacity: 1 - clamp(search * 1.4) }}>
        <div className="rh"><Poster style={{ width: 50, height: 50, borderRadius: 10, flex: "none" }} /><div className="rt"><b>The Quiet Coast</b><span>Netflix in Safari</span></div><span className="rc"><RI g="more" /></span></div>
        <div className="rpad"><span className="rhand"><RI g="hand" /></span><b>Tap to play or pause</b><span>Swipe sideways to skip,<br />up or down for volume</span></div>
        <div className="rbig"><span><RI g="back10" /></span><span className="pp"><RI g={playing ? "pause" : "play"} /></span><span><RI g="fwd10" /></span></div>
        <div className="ropts">{[["Search", "magnifyingglass"], ["Skip Intro", "forward.end"], ["Full Screen", "arrow.up.left.and.arrow.down.right"], ["Mute", "speaker.slash"]].map(([nm, g]) => (
          <span key={nm} className="ro" style={nm === "Search" ? { transform: `scale(${sTap.press})` } : undefined}>{g in RG ? <RI g={g} /> : <Glyph n={g} />}<small>{nm}</small></span>
        ))}</div>
      </div>
      {search > 0.001 ? (
        <div style={{ position: "absolute", inset: 0, opacity: clamp(search * 1.5) }}>
          <div className="fm-rs" style={{ transform: `translateY(${(1 - search) * 24}px)` }}>
            <div className="fld"><Glyph n="magnifyingglass" />{n > 0 ? <span>{QUERY.slice(0, n)}</span> : <span className="ph">Search on your Mac</span>}<i className="fm-caret2" style={{ height: 22, width: 2, background: "#0A84FF", marginLeft: -6 }} /></div>
            <p>Goes into Netflix's search box, then presses Return.</p>
          </div>
        </div>
      ) : null}
    </>
  );
};
/** The keyboard for Remote's search, over the bottom of the screen. */
const KBFor: React.FC<{ t: number }> = ({ t }) => {
  const search = SP(t, CT.search + 0.08, 0.42, 0.9) * (1 - E(t, CT.ret + 0.75, 0.45, INOUT));
  const n = Math.floor(clamp((t - CT.type0) / (CT.type1 - CT.type0)) * QUERY.length + 0.0001);
  const per = (CT.type1 - CT.type0) / QUERY.length;
  const live = t >= CT.type0 && t < CT.type1;
  const ch = live ? QUERY[Math.min(n, QUERY.length - 1)].toUpperCase() : "";
  const hit = live && ((t - CT.type0) % per) < per * 0.6;
  return <KB t={t} p={search} ch={hit ? ch : ""} />;
};
const KB: React.FC<{ t: number; p: number; ch: string }> = ({ t, p, ch }) => {
  if (p <= 0.001) return null;
  const ret = TAP(t, CT.ret).press < 0.99;
  const k = (c: string) => <span key={c} className={c === ch ? "hit" : ""}>{c.toLowerCase()}</span>;
  return (
    <div className="fm-kb" style={{ position: "absolute", top: 874 - 300, transform: `translateY(${(1 - p) * 300}px)`, zIndex: 8 }}>
      <div>{[..."QWERTYUIOP"].map(k)}</div><div>{[..."ASDFGHJKL"].map(k)}</div>
      <div><span className="w">⇧</span>{[..."ZXCVBNM"].map(k)}<span className="w">⌫</span></div>
      <div>
        <span style={{ width: 88, flex: "none", background: "#3D3D40", fontSize: 15 }}>123</span>
        <span style={{ width: 196, flex: "none", fontSize: 15, background: ch === " " ? "#8A8A8F" : "#5A5A5E" }}>space</span>
        <span style={{ width: 88, flex: "none", fontSize: 15, background: ret ? "#3D9BFF" : "#0A84FF" }}>search</span>
      </div>
    </div>
  );
};
/* ---------- Present, full screen and upright (PresentMode.swift) ---------- */
/* The laser pad: 16 pt margins, 16:10, under the timer bar. */
const PAD = { x: 16, y: 126, w: 370, h: 231 };
/* The route on the map slide, in fractions of the slide: Harbour, Lighthouse, Cliffs. */
const STOPS: [number, number][] = [[0.24, 0.72], [0.52, 0.44], [0.8, 0.58]];
/** The laser along the route, 0 to 1, resting a moment at each stop. */
function laserAt(u: number): [number, number] {
  const seg = [[0, 0.08], [0.42, 0.55], [0.92, 1]]; // where it rests
  if (u <= seg[0][1]) return STOPS[0];
  if (u < seg[1][0]) { const k = INOUT((u - seg[0][1]) / (seg[1][0] - seg[0][1])); return [lerp(STOPS[0][0], STOPS[1][0], k), lerp(STOPS[0][1], STOPS[1][1], k) - Math.sin(k * Math.PI) * 0.06]; }
  if (u <= seg[1][1]) return STOPS[1];
  if (u < seg[2][0]) { const k = INOUT((u - seg[1][1]) / (seg[2][0] - seg[1][1])); return [lerp(STOPS[1][0], STOPS[2][0], k), lerp(STOPS[1][1], STOPS[2][1], k) - Math.sin(k * Math.PI) * 0.05]; }
  return STOPS[2];
}
const PresentPhone: React.FC<{ t: number }> = ({ t }) => {
  const secs = 41 + Math.max(0, Math.floor(t - P0));
  const n1 = TAP(t, CT.next1), n2 = TAP(t, CT.next2);
  const u = E(t, CT.laser[0], CT.laser[1] - CT.laser[0], (x) => x);
  const holdO = E(t, CT.hold - 0.15, 0.15) * (1 - E(t, CT.laser[1], 0.2));
  const [lx, ly] = laserAt(u);
  const px = PAD.x + lx * PAD.w, py = PAD.y + ly * PAD.h;
  // the dot that opened the stage lifts off the pad
  const first = 1 - E(t, CT.wipe[1] - 0.1, 0.25);
  const fx = PAD.x + PAD.w / 2, fy = PAD.y + PAD.h / 2;
  const NEXT = { x: 132, y: 371, w: 254, h: 487 };
  return (
    <div className="fm-prs" style={{ position: "absolute", inset: 0, background: "#F2F1EE" }}>
      <div className="tb"><b>{`0:${String(secs).padStart(2, "0")}`}</b><span><Glyph n="arrow.counterclockwise" /></span><span><RI g="pause" /></span></div>
      <div className="pad" style={{ left: PAD.x, top: PAD.y, width: PAD.w, height: PAD.h }}>
        {holdO > 0.02 ? <i className="dot" style={{ left: lx * PAD.w - 9, top: ly * PAD.h - 9, opacity: holdO }} /> : (
          <div className="hint"><Glyph n="dot.radiowaves" /><span>Touch and hold to point</span></div>)}
      </div>
      <div className="key back" style={{ left: 16, top: NEXT.y, width: 104, height: NEXT.h }}><Glyph n="chevron.left" /><b>Back</b></div>
      <div className="key next" style={{ left: NEXT.x, top: NEXT.y, width: NEXT.w, height: NEXT.h, transform: `scale(${Math.min(n1.press, n2.press)})` }}><Glyph n="chevron.right" /><b>Next</b></div>
      <Finger x={fx} y={fy} o={first} />
      <Finger x={NEXT.x + NEXT.w / 2} y={NEXT.y + NEXT.h / 2} o={n1.o} s={n1.s} /><Ring x={NEXT.x + NEXT.w / 2} y={NEXT.y + NEXT.h / 2} p={n1.ring} />
      <Finger x={NEXT.x + NEXT.w / 2} y={NEXT.y + NEXT.h / 2} o={n2.o} s={n2.s} /><Ring x={NEXT.x + NEXT.w / 2} y={NEXT.y + NEXT.h / 2} p={n2.ring} />
      <Finger x={px} y={py} o={holdO} />
    </div>
  );
};

const CouchPhone: React.FC<{ t: number }> = ({ t }) => {
  const swipeX = E(t, CT.skip[0], CT.skip[1] - CT.skip[0], INOUT), swO = E(t, CT.skip[0] - 0.12, 0.12) * (1 - E(t, CT.skip[1], 0.18));
  const volY = E(t, CT.vol[0], CT.vol[1] - CT.vol[0], INOUT), vO = E(t, CT.vol[0] - 0.12, 0.12) * (1 - E(t, CT.vol[1], 0.18));
  const sTap = TAP(t, CT.search), rTap = TAP(t, CT.ret);
  const dTap = TAP(t, CT.dot);
  return (
    <div className="pt lyp" style={{ position: "absolute", inset: 0, transform: "none", background: "#2B2B2D" }}>
      <div className="lpt top rmt" style={{ height: SPLIT6, background: "#141414" }}><RemoteTop t={t} /></div>
      <div className="lpt-div" style={{ top: SPLIT6 }}><i style={{ background: "rgba(255,255,255,0.22)" }} /></div>
      <div className="lpt bot" style={{ top: SPLIT6 + 12, background: "#1E1E1E" }} />
      <KBFor t={t} />
      <Finger x={lerp(120, 290, swipeX)} y={250} o={swO} dark />
      <Finger x={300} y={lerp(320, 170, volY)} o={vO} dark />
      <Finger x={56} y={434 + 31} o={sTap.o} s={sTap.s} dark /><Ring x={56} y={465} p={sTap.ring} dark />
      <Finger x={355} y={874 - 300 + 12 + 3 * 54 + 21} o={rTap.o} s={rTap.s} dark /><Ring x={355} y={874 - 300 + 12 + 3 * 54 + 21} p={rTap.ring} dark />
      <Finger x={PAD.x + PAD.w / 2} y={PAD.y + PAD.h / 2} o={E(t, CT.dot - 0.15, 0.15)} dark />
      <Ring x={PAD.x + PAD.w / 2} y={PAD.y + PAD.h / 2} p={dTap.ring} dark />
    </div>
  );
};

/* ---------- the stage screen's slides: a short talk about a coast walk ---------- */
const Slide: React.FC<{ k: number; laser: [number, number] | null }> = ({ k, laser }) => {
  if (k === 0) return (
    <div className="fm-slide s0">
      <div className="tx"><b>The coast path</b><span>A weekend walk in three stops</span></div>
      <div className="ph"><i className="sun" /><i className="sea" /></div>
    </div>
  );
  if (k === 2) return <div className="fm-slide s2"><b>Questions?</b></div>;
  const near = (i: number) => (laser ? clamp(1 - Math.hypot(laser[0] - STOPS[i][0], laser[1] - STOPS[i][1]) / 0.06) : 0);
  const names = ["Harbour", "Lighthouse", "Cliffs"];
  return (
    <div className="fm-slide s1">
      <b className="h">Three stops</b>
      <svg viewBox="0 0 160 90" preserveAspectRatio="none" className="map">
        <rect width="160" height="90" fill="#F3EEE3" />
        <path d="M0 0H160V34C140 40 128 30 112 36C96 42 88 26 72 30C56 34 50 48 34 46C20 44 10 56 0 52Z" fill="#CFE0EE" />
        <path d={`M${STOPS[0][0] * 160} ${STOPS[0][1] * 90} Q 60 44 ${STOPS[1][0] * 160} ${STOPS[1][1] * 90} T ${STOPS[2][0] * 160} ${STOPS[2][1] * 90}`} fill="none" stroke="#1A1A1A" strokeOpacity="0.45" strokeWidth="0.7" strokeDasharray="2 1.6" vectorEffect="non-scaling-stroke" />
      </svg>
      {STOPS.map(([x, y], i) => (
        <div key={i} className="pin" style={{ left: `${x * 100}%`, top: `${y * 100}%`, transform: `translate(-50%, -50%) scale(${1 + 0.35 * near(i)})` }}>
          <i /><span>{names[i]}</span>
        </div>
      ))}
    </div>
  );
};

/* ---------- the two rooms ---------- */
const PH = { cx: 1545, cy: 556, w: 468, tilt: -5 };
/** Screen position of a point on the phone (its points), for the wipe's centre. */
function onPhone(x: number, y: number): [number, number] {
  const inset = 0.0365 * PH.w, k = (PH.w - 2 * inset) / 402, h = PH.w * 150 / 71.9;
  const ox = -PH.w / 2 + inset + x * k, oy = -h / 2 + inset + y * k;
  const a = (PH.tilt * Math.PI) / 180;
  return [PH.cx + ox * Math.cos(a) - oy * Math.sin(a), PH.cy + ox * Math.sin(a) + oy * Math.cos(a)];
}

export const Couch: React.FC = () => {
  const t = useCurrentFrame() / 60;
  const roomIn = E(t, CT.room, 0.6);
  const wipe = E(t, CT.wipe[0], CT.wipe[1] - CT.wipe[0], INOUT);
  const [wx, wy] = onPhone(PAD.x + PAD.w / 2, PAD.y + PAD.h / 2);
  // TV
  const seek = E(t, CT.skip[1], 0.25) * (1 - E(t, CT.skip[1] + 1.0, 0.3));
  const bar = E(t, CT.skip[1] - 0.05, 0.2) * (1 - E(t, CT.skip[1] + 1.5, 0.3));
  const pos = 0.31 + 0.04 * E(t, CT.skip[1] + 0.05, 0.5);
  const volO = E(t, CT.vol[0], 0.2) * (1 - E(t, CT.vol[1] + 0.8, 0.3));
  const vol = lerp(40, 70, E(t, CT.vol[0], CT.vol[1] - CT.vol[0], INOUT));
  const searchP = E(t, CT.search + 0.15, 0.45);
  const n = Math.floor(clamp((t - CT.type0) / (CT.type1 - CT.type0)) * QUERY.length + 0.0001);
  const results = (i: number) => E(t, CT.ret + 0.1 + i * 0.07, 0.45);
  // stage
  const slide = t < CT.next1 + 0.05 ? 0 : t < CT.next2 + 0.05 ? 1 : 2;
  const slideIn = t < CT.next2 + 0.05 ? E(t, CT.next1 + 0.05, 0.5) : E(t, CT.next2 + 0.05, 0.5);
  const u = E(t, CT.laser[0], CT.laser[1] - CT.laser[0], (x) => x);
  const laser = laserAt(u);
  const laserO = E(t, CT.laser[0] - 0.1, 0.2) * (1 - E(t, CT.laser[1], 0.2));
  const SC = { x: 134, y: 156, w: 1060 }, sh = SC.w * 9 / 16;
  const push = lerp(1, 1.025, E(t, P0, 5, INOUT));
  return (
    <div className="fm" style={{ background: "#2B2925" }}>
      {/* the couch */}
      {wipe < 1 ? (
        <div className="fm-world" style={{ opacity: roomIn }}>
          <div className="uc-wall" style={{ background: "radial-gradient(60% 70% at 38% 30%, #3A372F, #2B2925 70%)" }} />
          <div className="uc-floor" style={{ top: 40 * 19.2, background: "#23211E" }} />
          <div className="console" />
          <div className="sofa"><i /></div>
          <div style={{ position: "absolute", left: 230, top: 106, width: 960 }}>
            <div className="tv-b" style={{ padding: 8.6, borderRadius: 11.5 }}>
              <div className="tv-s">
                <div className="tv-film" style={{ opacity: 1 - searchP }}><Poster style={{ position: "absolute", inset: 0 }} /></div>
                <div className="tv-seek" style={{ opacity: seek, transform: `scale(${lerp(0.8, 1, OUT(seek))})` }}><RI g="fwd10" /></div>
                <div className="tv-bar" style={{ opacity: bar * (1 - searchP) }}><i style={{ width: `${pos * 100}%` }} /></div>
                <div className="tv-vol" style={{ opacity: volO }}><i style={{ height: `${vol}%` }} /></div>
                {searchP > 0.001 ? (
                  <div style={{ position: "absolute", inset: 0, background: "#141414", opacity: searchP }}>
                    <div className="fm-tvsearch"><Glyph n="magnifyingglass" /><span>{QUERY.slice(0, n)}</span><i className="fm-caret" /></div>
                    <div className="fm-tvrow">{[0, 1, 2, 3].map(i => (
                      <span key={i} style={{ opacity: results(i), transform: `translateY(${(1 - OUT(results(i))) * 3}cqh)` }}><Poster alt={i % 2 === 1} style={{ position: "absolute", inset: 0 }} /></span>
                    ))}</div>
                  </div>
                ) : null}
              </div>
            </div>
          </div>
          <Phone cx={PH.cx} cy={PH.cy} w={PH.w} finish="dark" shadow="hand" tilt={PH.tilt} port={<CouchPhone t={t} />} />
        </div>
      ) : null}
      {/* the stage, opening from the dot */}
      {wipe > 0 ? (
        <div className="fm-world" style={{ background: "#DAD6CF", clipPath: wipe < 1 ? `circle(${lerp(0, 2300, wipe)}px at ${wx}px ${wy}px)` : undefined }}>
          <div style={{ position: "absolute", inset: 0, transform: `scale(${push})`, transformOrigin: "40% 45%" }}>
            <div className="uc-floor" style={{ top: 860, background: "#C9C3B9" }} />
            <div style={{ position: "absolute", left: SC.x - 19, top: SC.y - 21, width: SC.w + 38, height: 21, borderRadius: 12, background: "linear-gradient(#5A5752, #3C3A36)" }} />
            <div className="scr-s" style={{ position: "absolute", left: SC.x, top: SC.y, width: SC.w, height: sh, aspectRatio: "auto" }}>
              {slideIn < 1 && slide > 0 ? <div style={{ position: "absolute", inset: 0, opacity: 1 - clamp(slideIn * 1.8) }}><Slide k={slide - 1} laser={null} /></div> : null}
              <div style={{ position: "absolute", inset: 0, ...(slide > 0 && slideIn < 1 ? { opacity: clamp(slideIn * 1.6 - 0.2), transform: `translateX(${(1 - OUT(slideIn)) * 5}%)` } : {}) }}>
                <Slide k={slide} laser={laserO > 0.5 ? laser : null} />
              </div>
              <span className="slaser" style={{ left: `${laser[0] * 100}%`, top: `${laser[1] * 100}%`, opacity: laserO }} />
              <span className="sl-n">{slide + 1}</span>
            </div>
          </div>
          <Phone cx={PH.cx} cy={PH.cy} w={PH.w} finish="light" shadow="hand" tilt={PH.tilt} port={<PresentPhone t={t} />} />
        </div>
      ) : null}
      <Title text="Remote" dark {...titleAt("remote", t)} />
      <Title text="Present" {...titleAt("present", t)} />
    </div>
  );
};
