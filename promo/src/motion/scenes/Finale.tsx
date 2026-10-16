import React from "react";
import { useCurrentFrame } from "remotion";
import { Caption, Glyph, MacBook, macDisplay, MenuBar, Mark, Phone } from "../parts";
import { clamp, E, INOUT, lerp, OUT, SP } from "../kit";
import { sceneSec, word, FILM_SEC } from "../timeline";

/* Scenes 12 and 13. Pairing as the Mac's menu bar popover and the iPhone's camera draw it
   (web/src/pairing.ts); the code's dots gather into a check; the two devices and one line inside
   the Wi-Fi mark. Then everything folds into the Wi-Fi mark's dot, and the dot becomes the
   Glasspad mark. Film seconds. */

const P0 = sceneSec("private"), E0 = sceneSec("end");
export const FT = {
  aim: [P0 + 0.3, P0 + 1.25] as const, seen: P0 + word("private", "scan") - 0.1,
  gather: [P0 + word("private", "scan") + 0.1, P0 + word("private", "scan") + 1.0] as const,
  paired: P0 + word("private", "scan") + 0.55,
  back: [P0 + 2.55, P0 + 3.35] as const, wifi: P0 + 2.95, line: [P0 + word("private", "between") - 0.15, P0 + word("private", "between") + 0.55] as const,
  words: P0 + 3.75,
  fold: [E0 - 0.4, E0 + 0.45] as const, wipe: [E0 + 0.2, E0 + 0.95] as const,
  pad: E0 + 0.6, rise: [E0 + 0.8, E0 + 1.45] as const,
  word: E0 + word("end", "glasspad") - 0.15, tag: E0 + word("end", "glasspad") + 0.5,
  free: E0 + word("end", "free") - 0.05, url: E0 + word("end", "free") + 0.5, credit: E0 + word("end", "free") + 0.95,
};
export const FINALE_CUES = () => ({
  click: [FT.seen],
  chime: [FT.paired],
  whoosh: [FT.back[0] + 0.1, FT.fold[0] + 0.2],
  land: [FT.pad - 0.3],
});

/* The QR-like code from web/src/pairing.ts, as single modules so they can move. */
const QN = 25;
const CELLS: [number, number][] = (() => {
  const out: [number, number][] = [];
  let seed = 7;
  const rnd = () => (seed = (seed * 16807) % 2147483647) / 2147483647;
  const finder = (x: number, y: number) => (x < 8 && y < 8) || (x > QN - 9 && y < 8) || (x < 8 && y > QN - 9);
  for (let y = 0; y < QN; y++) for (let x = 0; x < QN; x++) {
    if (finder(x, y)) continue;
    if (rnd() < 0.5) out.push([x, y]);
  }
  for (const [fx, fy] of [[0, 0], [QN - 7, 0], [0, QN - 7]]) for (let y = 0; y < 7; y++) for (let x = 0; x < 7; x++) {
    const ring = x === 0 || y === 0 || x === 6 || y === 6, core = x >= 2 && x <= 4 && y >= 2 && y <= 4;
    if (ring || core) out.push([fx + x, fy + y]);
  }
  return out;
})();
/* Points along a check, in the code's units, one per module, in order from left to right. */
const CHECK: [number, number][] = [[5.5, 13], [10.5, 18.2], [19.5, 6.5]];
const along = (u: number): [number, number] => {
  const l1 = Math.hypot(CHECK[1][0] - CHECK[0][0], CHECK[1][1] - CHECK[0][1]), l2 = Math.hypot(CHECK[2][0] - CHECK[1][0], CHECK[2][1] - CHECK[1][1]);
  const d = u * (l1 + l2);
  if (d <= l1) { const k = d / l1; return [lerp(CHECK[0][0], CHECK[1][0], k), lerp(CHECK[0][1], CHECK[1][1], k)]; }
  const k = (d - l1) / l2; return [lerp(CHECK[1][0], CHECK[2][0], k), lerp(CHECK[1][1], CHECK[2][1], k)];
};
const ORDER = CELLS.map((c, i) => [c[0] + c[1] * 0.001, i] as [number, number]).sort((a, b) => a[0] - b[0]).map(([, i]) => i);
const TARGET: [number, number][] = new Array(CELLS.length);
ORDER.forEach((ci, k) => { TARGET[ci] = along(k / (ORDER.length - 1)); });

const Code: React.FC<{ t: number; cam?: boolean }> = ({ t, cam }) => {
  const g = cam ? (i: number) => E(t, FT.gather[0] + (CELLS[i][0] / QN) * 0.35, FT.gather[1] - FT.gather[0] - 0.35, INOUT) : () => 0;
  const green = cam ? E(t, FT.gather[1] - 0.2, 0.3) : 0;
  const col = `rgb(${Math.round(lerp(17, 52, green))},${Math.round(lerp(17, 199, green))},${Math.round(lerp(17, 89, green))})`;
  const bgO = cam ? 1 - E(t, FT.gather[0], 0.5) : 1;
  return (
    <svg viewBox="-1 -1 27 27" style={{ position: "absolute", inset: 0, width: "100%", height: "100%", overflow: "visible" }}>
      <rect x="-1" y="-1" width="27" height="27" rx="1.2" fill="#fff" stroke="none" opacity={bgO} />
      {CELLS.map(([x, y], i) => {
        const u = g(i);
        const [tx, ty] = TARGET[i];
        const cx = lerp(x + 0.5, tx, u), cy = lerp(y + 0.5, ty, u);
        const s = lerp(1, 0.62, u), r = lerp(0.04, 0.31, u);
        return <rect key={i} x={cx - s / 2} y={cy - s / 2} width={s} height={s} rx={r} fill={col} stroke="none" />;
      })}
    </svg>
  );
};

/* The Mac's menu bar popover (Apps/Mac), as the site draws it. */
const Popover: React.FC<{ t: number; done: number }> = ({ t, done }) => (
  <div className="pair-pt" style={{ position: "absolute", left: 0, top: 0, width: "100%", height: "100%", transform: "none" }}>
    <div className="gpop" style={{ right: "3cqw", top: "5.4cqh", opacity: 1, transform: `scale(${1.45})`, transformOrigin: "100% 0" }}>
      <div className="ph"><b>Glasspad</b><i className="tg on" /></div>
      <div style={{ position: "relative" }}>
        <div className="pstate" style={{ display: "block", opacity: 1 - done }}>
          <div className="prow"><span className="pi"><Glyph n="iphone" /></span><div><b>No iPhone Paired</b><small>Scan the code below with your iPhone.</small></div></div>
          <div className="pcode"><div className="qr" style={{ position: "relative", display: "inline-block", width: 138, height: 138, padding: 6, borderRadius: 10, background: "#fff", boxShadow: "0 0 0 1px rgba(0,0,0,0.1)" }}><div style={{ position: "absolute", inset: 6 }}><Code t={t} /></div></div>
            <p>On your iPhone, open Glasspad, tap Pair a Mac and hold it over this code.</p><div className="plink">Show Code as Text</div></div>
        </div>
        {done > 0 ? <div className="pstate done" style={{ display: "block", position: "absolute", left: 0, right: 0, top: 0, opacity: done }}>
          <span className="pok"><Glyph n="checkmark" /></span><b>Paired with Soham&rsquo;s iPhone</b><small>Your iPhone now controls this Mac. Glasspad stays in the menu bar.</small>
        </div> : null}
      </div>
    </div>
  </div>
);
const MenuIcon: React.FC = () => (
  <span style={{ display: "grid", placeItems: "center", width: "4.4cqh", height: "3.6cqh", borderRadius: "0.8cqh", background: "rgba(0,0,0,0.14)" }}>
    <svg viewBox="0 0 24 24" style={{ width: "3cqh", height: "3cqh", fill: "none", stroke: "#1A1A1A", strokeWidth: 1.8 }}><rect x="3" y="6" width="18" height="12" rx="3.5" /><circle cx="15" cy="11" r="1.8" fill="currentColor" stroke="none" /></svg>
  </span>
);

/* The Wi-Fi mark's arcs, drawn on with their length. */
const Arc: React.FC<{ r: number; p: number; cx: number; cy: number }> = ({ r, p, cx, cy }) => {
  const a = Math.PI / 4, len = 2 * a * r;
  const d = `M ${cx - r * Math.sin(a)} ${cy - r * Math.cos(a)} A ${r} ${r} 0 0 1 ${cx + r * Math.sin(a)} ${cy - r * Math.cos(a)}`;
  return <path d={d} fill="none" stroke="#F2F1EE" strokeWidth={4} strokeLinecap="round" strokeDasharray={len} strokeDashoffset={len * (1 - p)} opacity={p > 0 ? 0.9 : 0} />;
};

export const Finale: React.FC = () => {
  const t = useCurrentFrame() / 60;
  const inP = E(t, P0 - 0.05, 0.45);
  const aim = E(t, FT.aim[0], FT.aim[1] - FT.aim[0], INOUT);
  const seen = E(t, FT.seen, 0.2);
  const done = E(t, FT.paired, 0.3);
  const back = E(t, FT.back[0], FT.back[1] - FT.back[0], INOUT);
  const fold = E(t, FT.fold[0], FT.fold[1] - FT.fold[0], INOUT);
  // devices: full size, then small on either side of the Wi-Fi mark
  const DOT = { x: 960, y: 640 };
  const mac = { x: lerp(170, 375, back), y: lerp(210, 470, back), s: lerp(1, 0.42, back) };
  const ph = { cx: lerp(1455, 1344, back), cy: lerp(560, 600, back), s: lerp(1, 0.5, back), tilt: lerp(-4, 0, back) };
  const LID = 960;
  const d = macDisplay(0, 0, LID);
  const lineP = E(t, FT.line[0], FT.line[1] - FT.line[0], INOUT);
  const wordsP = E(t, FT.words, 0.6);
  // the fold: everything goes into the dot
  const foldS = lerp(1, 0.02, fold), foldO = 1 - E(t, FT.fold[0] + 0.15, FT.fold[1] - FT.fold[0] - 0.15);
  const wipe = E(t, FT.wipe[0], FT.wipe[1] - FT.wipe[0], INOUT);
  const pad = SP(t, FT.pad, 0.55, 0.78);
  const rise = E(t, FT.rise[0], FT.rise[1] - FT.rise[0], INOUT);
  // the end card
  const MARK = 210;
  const markY = lerp(540, 330, rise);
  const dotX = 960 + MARK * (660 / 1024 - 0.5), dotY = markY + MARK * (440 / 1024 - 0.5);
  const dotPos = { x: lerp(DOT.x, dotX, E(t, FT.wipe[0], FT.pad + 0.4 - FT.wipe[0], INOUT)), y: lerp(DOT.y, dotY, E(t, FT.wipe[0], FT.pad + 0.4 - FT.wipe[0], INOUT)) };
  const ink = E(t, FT.wipe[0] + 0.1, 0.5);
  const dotR = lerp(13, 74 * MARK / 1024, E(t, FT.wipe[0], 0.8, INOUT));
  const show = (t0: number) => E(t, t0, 0.6);
  const drift = lerp(1, 1.025, E(t, FT.word, FILM_SEC - FT.word, INOUT));
  const dark = "#0B0B0F", paper = "#F2F1EE";
  return (
    <div className="fm" style={{ background: dark }}>
      {/* pairing and the Wi-Fi mark, folding into the dot */}
      <div style={{ position: "absolute", inset: 0, opacity: inP * foldO, transform: `translate(${DOT.x}px, ${DOT.y}px) scale(${foldS}) translate(${-DOT.x}px, ${-DOT.y}px)` }}>
        <div style={{ position: "absolute", left: 0, top: 0, transform: `translate(${mac.x}px, ${mac.y}px) scale(${mac.s})`, transformOrigin: "0 0" }}>
          <MacBook x={0} y={0} lid={LID} displayStyle={{ background: "linear-gradient(160deg, #D3D8E0, #AEB7C6)" }}>
            <div className="mbx">
              <MenuBar app="Finder" extra={<MenuIcon />} />
              <Popover t={t} done={done} />
            </div>
          </MacBook>
        </div>
        <Phone cx={ph.cx} cy={ph.cy} w={330} scale={ph.s} tilt={ph.tilt} finish="dark" shadow="hand"
          port={<div style={{ position: "absolute", inset: 0, background: "radial-gradient(80% 60% at 60% 40%, #4A4C52, #1C1D20)" }}>
            <div style={{ position: "absolute", left: 89, top: 297, width: 225, height: 225, opacity: lerp(0.35, 1, aim), filter: `blur(${(1 - aim) * 6}px)`, transform: `translate(${(1 - aim) * 30}px, ${(1 - aim) * 18}px) scale(${lerp(0.82, 1, aim)})` }}>
              <Code t={t} cam />
            </div>
            {[["tl", 72, 280], ["tr", 330, 280], ["bl", 72, 538], ["br", 330, 538]].map(([k, x, y]) => (
              <i key={k as string} style={{ position: "absolute", left: (x as number) - 28, top: (y as number) - 28, width: 56, height: 56, opacity: seen * (1 - E(t, FT.gather[0] + 0.3, 0.3)),
                borderStyle: "solid", borderColor: "#FFD60A", borderWidth: 0, borderTopWidth: (k as string)[0] === "t" ? 5 : 0, borderBottomWidth: (k as string)[0] === "b" ? 5 : 0, borderLeftWidth: (k as string)[1] === "l" ? 5 : 0, borderRightWidth: (k as string)[1] === "r" ? 5 : 0,
                borderRadius: { tl: "12px 0 0 0", tr: "0 12px 0 0", bl: "0 0 0 12px", br: "0 0 12px 0" }[k as string] }} />
            ))}
          </div>} />
        {/* the Wi-Fi mark, the line between the two, the dot */}
        <svg width="1920" height="1080" style={{ position: "absolute", left: 0, top: 0, overflow: "visible" }}>
          {[78, 140, 202].map((r, i) => <Arc key={r} r={r} cx={DOT.x} cy={DOT.y} p={E(t, FT.wifi + 0.12 * i, 0.6, INOUT)} />)}
          <line x1={lerp(DOT.x, 375 + LID * 0.42 * 1.0 + 10, lineP)} y1={DOT.y} x2={lerp(DOT.x, 1344 - 330 * 0.5 / 2 - 14, lineP)} y2={DOT.y} stroke="#F2F1EE" strokeWidth={3} strokeLinecap="round" strokeDasharray="1 11" opacity={0.75 * clamp(lineP * 3)} />
        </svg>
        <div className="fm-head" style={{ top: 840, fontSize: 46, color: "#F2F1EE", opacity: wordsP, transform: `translateY(${(1 - OUT(wordsP)) * 14}px)` }}>No account. Encrypted. Your Wi-Fi.</div>
      </div>
      {/* the paper end card grows out of the dot */}
      {wipe > 0 ? <div style={{ position: "absolute", inset: 0, background: paper, clipPath: `circle(${lerp(0, 2300, wipe)}px at ${DOT.x}px ${DOT.y}px)` }} /> : null}
      {t > FT.wipe[0] ? (
        <div style={{ position: "absolute", inset: 0, transform: `scale(${drift})`, transformOrigin: "50% 45%" }}>
          <div style={{ position: "absolute", left: 960 - MARK / 2, top: markY - MARK / 2, width: MARK, height: MARK, opacity: clamp(pad * 1.4), transform: `scale(${lerp(0.4, 1, pad)})`, transformOrigin: `${660 / 1024 * 100}% ${440 / 1024 * 100}%`, borderRadius: MARK * 0.225, overflow: "hidden", boxShadow: `0 ${MARK * 0.06}px ${MARK * 0.14}px -${MARK * 0.05}px rgba(20,20,20,${0.22 * pad})` }}>
            <Mark size={MARK} />
          </div>
          <div className="fm-word" style={{ top: 470, fontSize: 168, opacity: show(FT.word), transform: `translateY(${(1 - OUT(show(FT.word))) * 26}px)` }}>Glasspad</div>
          <div className="fm-line" style={{ top: 680, fontSize: 46, opacity: show(FT.tag), transform: `translateY(${(1 - OUT(show(FT.tag))) * 16}px)` }}>A control surface for your Mac, on your iPhone.</div>
          <div className="fm-small" style={{ top: 790, fontSize: 28, color: "rgba(26,26,26,0.72)", opacity: show(FT.free) }}>Free and open source.</div>
          <div className="fm-small" style={{ top: 836, fontSize: 28, color: "#1A1A1A", fontWeight: 500, opacity: show(FT.url) }}>glasspad.sohamaggarwal.com</div>
          <div className="fm-small" style={{ top: 1018, fontSize: 17, color: "rgba(26,26,26,0.45)", opacity: show(FT.credit) }}>Music: &ldquo;Uplifting Electronic Indie&rdquo; by WinnieTheMoog, CC BY 4.0</div>
        </div>
      ) : null}
      {/* the dot itself, white on the dark, then the mark's ink */}
      {t > FT.fold[0] && pad < 0.98 ? (
        <div style={{ position: "absolute", left: dotPos.x - dotR, top: dotPos.y - dotR, width: dotR * 2, height: dotR * 2, borderRadius: "50%",
          background: `rgba(${Math.round(lerp(242, 26, ink))},${Math.round(lerp(241, 26, ink))},${Math.round(lerp(238, 26, ink))},${lerp(1, 0.62, ink)})`, opacity: 1 - clamp((pad - 0.6) * 3) }} />
      ) : null}
      {/* the Wi-Fi dot before the fold */}
      {t <= FT.fold[0] ? <div style={{ position: "absolute", left: DOT.x - 13, top: DOT.y - 13, width: 26, height: 26, borderRadius: "50%", background: "#F2F1EE", opacity: E(t, FT.wifi, 0.3) * inP }} /> : null}
      <Caption text="Private" color="#63E6BE" dark p={E(t, P0 + 0.15, 0.6)} q={E(t, FT.fold[0], 0.3)} />
    </div>
  );
};
