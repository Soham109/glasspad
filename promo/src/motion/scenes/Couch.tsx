import React from "react";
import { useCurrentFrame } from "remotion";
import { Caption, Finger, Glyph, Phone, Poster, Ring } from "../parts";
import { clamp, E, INOUT, K, lerp, OUT, SP, TAP } from "../kit";
import { sceneSec, word } from "../timeline";

/* Scenes 7 and 8: the couch (Remote) and the stage (Present). The TV across the room becomes the
   stage screen; the phone in hand stays where it is and changes layout. Film seconds. */

const R0 = sceneSec("remote"), P0 = sceneSec("present"), D0 = sceneSec("displays");
export const CT = {
  room: R0 + 0.05,
  skip: [R0 + 1.05, R0 + 1.45] as const,
  vol: [R0 + 2.45, R0 + 3.05] as const,
  search: R0 + 3.85, type0: R0 + 4.55, type1: R0 + 5.85, ret: R0 + 6.2,
  morph: [P0 - 0.9, P0 + 0.15] as const,
  next1: P0 + 0.75,
  hold: P0 + word("present", "time") + 0.1, laser: [P0 + word("present", "time") + 0.35, P0 + word("present", "you") + 0.45] as const,
  next2: P0 + 4.05,
};
export const COUCH_CUES = () => ({
  tap: [CT.search, CT.ret, CT.next1, CT.next2],
  swipe: [[CT.skip[0], CT.skip[1]], [CT.vol[0], CT.vol[1]]] as [number, number][],
  key: Array.from({ length: 11 }, (_, i) => CT.type0 + i * (CT.type1 - CT.type0) / 11),
  skip: [CT.skip[1]],
  whoosh: [CT.morph[0] + 0.3],
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

const SPLIT6 = Math.round((874 - 12) * 0.6), SPLIT5 = Math.round((874 - 12) * 0.5);
const QUERY = "quiet coast";

/* ---------- the phone ---------- */
const RemoteTop: React.FC<{ t: number }> = ({ t }) => {
  const search = SP(t, CT.search + 0.08, 0.42, 0.9);
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
  const search = SP(t, CT.search + 0.08, 0.42, 0.9);
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
      <div><span className="w">123</span><span className={`sp${ch === " " ? " hit" : ""}`}>space</span><span className="ret" style={ret ? { background: "#3D9BFF" } : undefined}>search</span></div>
    </div>
  );
};
const PresentTop: React.FC<{ t: number }> = ({ t }) => {
  const secs = 41 + Math.max(0, Math.floor(t - P0));
  const n1 = TAP(t, CT.next1), n2 = TAP(t, CT.next2);
  const hold = E(t, CT.hold - 0.1, 0.2) * (1 - E(t, CT.laser[1], 0.2));
  return (
    <div style={{ position: "absolute", inset: 0 }}>
      <div className="ptime on">{`0:${String(secs).padStart(2, "0")}`}</div>
      <span className="pr"><Glyph n="arrow.counterclockwise" /></span>
      <span className="pgo on"><RI g="pause" /></span>
      <div className="plaser" style={{ background: hold > 0.01 ? `rgba(255,59,48,${0.06 * hold})` : undefined }}><Glyph n="dot.radiowaves" /><span>Touch and hold to point</span></div>
      <div className="pback"><Glyph n="chevron.left" /><b>Back</b></div>
      <div className="pnext" style={{ transform: `scale(${Math.min(n1.press, n2.press)})` }}><Glyph n="chevron.right" /><b>Next</b></div>
    </div>
  );
};
/** The laser's path across the slide (fractions of the slide), and the finger's on the pad. */
const laserAt = (u: number): [number, number] => [lerp(0.3, 0.74, u) + 0.03 * Math.sin(u * Math.PI * 2), 0.62 - 0.22 * u + 0.06 * Math.sin(u * Math.PI)];

const CouchPhone: React.FC<{ t: number; present: number }> = ({ t, present }) => {
  const swipeX = E(t, CT.skip[0], CT.skip[1] - CT.skip[0], INOUT), swO = E(t, CT.skip[0] - 0.12, 0.12) * (1 - E(t, CT.skip[1], 0.18));
  const volY = E(t, CT.vol[0], CT.vol[1] - CT.vol[0], INOUT), vO = E(t, CT.vol[0] - 0.12, 0.12) * (1 - E(t, CT.vol[1], 0.18));
  const sTap = TAP(t, CT.search), rTap = TAP(t, CT.ret);
  const n1 = TAP(t, CT.next1), n2 = TAP(t, CT.next2);
  const laserU = E(t, CT.laser[0], CT.laser[1] - CT.laser[0], INOUT);
  const holdO = E(t, CT.hold - 0.15, 0.15) * (1 - E(t, CT.laser[1], 0.2));
  const red = E(t, CT.hold + 0.1, 0.25);
  const ly = laserAt(laserU)[1];
  const split = Math.round(lerp(SPLIT6, SPLIT5, present));
  return (
    <div className="pt lyp" style={{ position: "absolute", inset: 0, transform: "none", background: "#2B2B2D" }}>
      <div className={`lpt top ${present > 0.5 ? "prs" : "rmt"}`} style={{ height: split, background: present > 0.5 ? "#F2F1EE" : "#141414" }}>
        {present < 0.5 ? <RemoteTop t={t} /> : <PresentTop t={t} />}
      </div>
      <div className="lpt-div" style={{ top: split }}><i style={{ background: present > 0.5 ? undefined : "rgba(255,255,255,0.22)" }} /></div>
      <div className="lpt bot" style={{ top: split + 12, background: present > 0.5 ? "#F2F1EE" : "#1E1E1E" }} />
      {present < 0.5 ? <KBFor t={t} /> : null}
      {/* touches */}
      {present < 0.5 ? <>
        <Finger x={lerp(120, 290, swipeX)} y={250} o={swO} dark />
        <Finger x={300} y={lerp(320, 170, volY)} o={vO} dark />
        <Finger x={56} y={434 + 31} o={sTap.o} s={sTap.s} dark /><Ring x={56} y={465} p={sTap.ring} dark />
        <Finger x={355} y={874 - 300 + 12 + 3 * 54 + 21} o={rTap.o} s={rTap.s} dark /><Ring x={355} y={874 - 300 + 12 + 3 * 54 + 21} p={rTap.ring} dark />
      </> : <>
        <Finger x={280} y={335} o={n1.o} s={n1.s} /><Ring x={280} y={335} p={n1.ring} />
        <Finger x={280} y={335} o={n2.o} s={n2.s} /><Ring x={280} y={335} p={n2.ring} />
        <Finger x={lerp(120, 280, laserU)} y={189 + (ly - 0.5) * 120} o={holdO}
          color={`rgba(${Math.round(lerp(26, 255, red))},${Math.round(lerp(26, 45, red))},${Math.round(lerp(26, 32, red))},${lerp(0.42, 0.9, red)})`}
          glow={red > 0 ? `0 0 ${18 * red}px ${6 * red}px rgba(255,45,32,${0.35 * red})` : undefined} />
      </>}
    </div>
  );
};

/* ---------- the room ---------- */
const SLIDES = [
  <><b className="sl-t" style={{ width: "46%" }} /><div className="sl-two"><span /><span /></div></>,
  <><b className="sl-t" style={{ width: "58%" }} /><i style={{ width: "44%" }} /><i style={{ width: "36%" }} /><div className="sl-ch"><i style={{ height: "38%" }} /><i style={{ height: "56%" }} /><i style={{ height: "48%" }} /><i style={{ height: "74%" }} /><i style={{ height: "90%" }} /></div></>,
  <><b className="sl-t big" style={{ width: "64%" }} /><i style={{ width: "30%", margin: "2cqh auto 0" }} /></>,
];

export const Couch: React.FC = () => {
  const t = useCurrentFrame() / 60;
  const m = E(t, CT.morph[0], CT.morph[1] - CT.morph[0], INOUT); // couch to stage
  const roomIn = E(t, CT.room, 0.6);
  // TV rect (couch) to screen rect (stage), in px of the 1920 frame
  const tv = { x: 230, y: 106, w: 960 }, sc = { x: 134, y: 50 + 21, w: 1114 };
  const r = { x: lerp(tv.x, sc.x, m), y: lerp(tv.y, sc.y, m), w: lerp(tv.w, sc.w, m) };
  const h = r.w * 9 / 16;
  // TV state
  const seek = E(t, CT.skip[1], 0.25) * (1 - E(t, CT.skip[1] + 1.0, 0.3));
  const bar = E(t, CT.skip[1] - 0.05, 0.2) * (1 - E(t, CT.skip[1] + 1.5, 0.3));
  const pos = 0.31 + 0.04 * E(t, CT.skip[1] + 0.05, 0.5);
  const volO = E(t, CT.vol[0], 0.2) * (1 - E(t, CT.vol[1] + 0.8, 0.3));
  const vol = lerp(40, 70, E(t, CT.vol[0], CT.vol[1] - CT.vol[0], INOUT));
  const searchP = E(t, CT.search + 0.15, 0.45);
  const n = Math.floor(clamp((t - CT.type0) / (CT.type1 - CT.type0)) * QUERY.length + 0.0001);
  const results = (i: number) => E(t, CT.ret + 0.1 + i * 0.07, 0.45);
  const slide = t < CT.next1 + 0.05 ? 0 : t < CT.next2 + 0.05 ? 1 : 2;
  const slideIn = t < CT.next2 + 0.05 ? E(t, CT.next1 + 0.05, 0.5) : E(t, CT.next2 + 0.05, 0.5);
  const laserU = E(t, CT.laser[0], CT.laser[1] - CT.laser[0], INOUT);
  const [lx, ly] = laserAt(laserU);
  const laserO = E(t, CT.laser[0] - 0.1, 0.2) * (1 - E(t, CT.laser[1], 0.2));
  // phone in hand: couch pose to stage pose
  const ph = { cx: lerp(1325 + 206, 1363 + 201, m), cy: lerp(123 + 430, 144 + 420, m), w: lerp(413, 403, m), tilt: lerp(-5, -4, m) };
  const present = m > 0.5 ? 1 : 0;
  // colours
  const wall = m < 1 ? `rgb(${[43, 41, 37].map((v, i) => Math.round(lerp(v, [218, 214, 207][i], m))).join(",")})` : "#DAD6CF";
  const floor = `rgb(${[35, 33, 30].map((v, i) => Math.round(lerp(v, [201, 195, 185][i], m))).join(",")})`;
  const exitO = 1 - E(t, D0 - 0.45, 0.45);
  return (
    <div className="fm" style={{ background: wall }}>
      <div className="fm-world" style={{ opacity: roomIn * exitO, transform: `scale(${lerp(1, 1.02, E(t, P0, 4, INOUT))})`, transformOrigin: "50% 50%" }}>
        <div className="uc-wall" style={{ background: m < 0.99 ? `radial-gradient(60% 70% at 38% 30%, rgba(58,55,47,${1 - m}), transparent 70%)` : undefined }} />
        <div className="uc-floor" style={{ top: lerp(40, 43, m) * 19.2, background: floor }} />
        <div className="console" style={{ opacity: 1 - m }} />
        <div className="sofa" style={{ opacity: 1 - m, transform: `translateY(${m * 120}px)` }}><i /></div>
        {/* the stage roller appears as the TV becomes the screen */}
        <div style={{ position: "absolute", left: r.x - 19, top: r.y - 21, width: r.w + 38, height: 21, borderRadius: 12, background: "linear-gradient(#5A5752, #3C3A36)", opacity: m }} />
        <div style={{ position: "absolute", left: r.x, top: r.y, width: r.w }}>
          <div className="tv-b" style={{ padding: lerp(8.6, 0, m), borderRadius: lerp(11.5, 0, m), background: m < 1 ? "#0A0A0A" : "transparent", boxShadow: `0 0 0 ${2.3 * (1 - m)}px #3A3A3A, 0 0 ${154 * (1 - m)}px -19px rgba(232,197,71,${0.18 * (1 - m)}), 0 27px 58px -31px rgba(20,20,20,${0.4 * m})` }}>
            <div className="tv-s" style={{ height: h - 2 * lerp(8.6, 0, m), aspectRatio: "auto" }}>
              {/* the film */}
              <div className="tv-film" style={{ opacity: 1 - searchP }}><Poster style={{ position: "absolute", inset: 0 }} /></div>
              <div className="tv-seek" style={{ opacity: seek, transform: `scale(${lerp(0.8, 1, OUT(seek))})` }}><RI g="fwd10" /></div>
              <div className="tv-bar" style={{ opacity: bar * (1 - searchP) }}><i style={{ width: `${pos * 100}%` }} /></div>
              <div className="tv-vol" style={{ opacity: volO }}><i style={{ height: `${vol}%` }} /></div>
              {/* the search page */}
              {searchP > 0.001 ? (
                <div style={{ position: "absolute", inset: 0, background: "#141414", opacity: searchP * (1 - clamp(m * 2.5)) }}>
                  <div className="fm-tvsearch"><Glyph n="magnifyingglass" /><span>{QUERY.slice(0, n)}</span><i className="fm-caret" /></div>
                  <div className="fm-tvrow">{[0, 1, 2, 3].map(i => (
                    <span key={i} style={{ opacity: results(i), transform: `translateY(${(1 - OUT(results(i))) * 3}cqh)` }}><Poster alt={i % 2 === 1} style={{ position: "absolute", inset: 0 }} /></span>
                  ))}</div>
                </div>
              ) : null}
              {/* the slides */}
              {m > 0.001 ? (
                <div className="scr-s" style={{ position: "absolute", inset: 0, opacity: m, boxShadow: "none" }}>
                  {slideIn < 1 && slide > 0 ? <div className="slide" style={{ opacity: 1 - clamp(slideIn * 3) }}>{SLIDES[slide - 1]}</div> : null}
                  <div className="slide" style={slide > 0 && slideIn < 1 ? { opacity: clamp(slideIn * 1.6 - 0.2), transform: `translateX(${(1 - OUT(slideIn)) * 5}%)` } : undefined}>{SLIDES[slide]}</div>
                  <span className="slaser" style={{ left: `${lx * 100}%`, top: `${ly * 100}%`, opacity: laserO }} />
                  <span className="sl-n">{slide + 1}</span>
                </div>
              ) : null}
            </div>
          </div>
        </div>
        <Phone cx={ph.cx} cy={ph.cy} w={ph.w} finish={present ? "light" : "dark"} shadow="hand" tilt={ph.tilt}
          port={<CouchPhone t={t} present={present} />} />
      </div>
      <Caption text="Remote" color="#BF5AF2" dark p={E(t, R0 + 0.3, 0.6)} q={E(t, CT.morph[0], 0.3)} />
      <Caption text="Present" color="#FF453A" p={E(t, P0 + 0.1, 0.6)} q={E(t, D0 - 0.4, 0.3)} />
    </div>
  );
};
