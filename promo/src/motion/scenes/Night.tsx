import React from "react";
import { useCurrentFrame } from "remotion";
import { AppIcon, Caption, Doc, Finger, Glyph, MacBook, MenuBar, Monitor, Phone, Poster, Ring, Stand, Win } from "../parts";
import { clamp, E, INOUT, K, lerp, OUT, SP, TAP } from "../kit";
import { sceneSec, word } from "../timeline";

/* Scenes 9 and 10: Displays on the desk (DisplaysMode.swift, sideways), then the same phone on a
   nightstand in StandBy. The phone stays put while the room changes around it. Film seconds. */

const D0 = sceneSec("displays"), N0 = sceneSec("standby"), T0 = sceneSec("themes");
export const NT = {
  touch: D0 + 0.85, drag: [D0 + 1.0, D0 + word("displays", "display") + 0.05] as const,
  cross: D0 + word("displays", "display") + 0.15,
  hold: D0 + 3.05, menu: D0 + 3.45, fill: D0 + 4.05,
  night: [N0 - 0.95, N0 + 0.1] as const,
  dot: N0 + 0.25, tick: N0 + word("standby", "clock"),
  lamp: N0 + word("standby", "nightstand") - 0.1, red: N0 + word("standby", "nightstand") + 0.35,
};
export const NIGHT_CUES = () => ({
  tap: [NT.fill],
  drag: [[NT.drag[0], NT.drag[1]]] as [number, number][],
  haptic: [NT.menu],
  whoosh: [NT.cross, NT.night[0] + 0.3],
  click: [NT.lamp],
});

const OY = 60, CQ = 19.2;
const MB = { x: -4 * CQ, y: 26.5 * CQ + OY, w: 34.5 * CQ }; // .mb-dp, its box
const LID = 0.58 * MB.w, LIDX = MB.x + (MB.w - LID) / 2, LIDY = MB.y + 4 * (MB.w / 100);
const MON = { x: 19 * CQ, y: 6.4 * CQ + OY, w: 34 * CQ };
const SPD = { x: 56.5 * CQ, y: 18 * CQ + OY, w: 41 * CQ }; // the phone on its stand, sideways
const SPN = { x: 40 * CQ - 60, y: 15.4 * CQ + 60, w: 52 * CQ };

const macWin = (cls: string, k: string, style?: React.CSSProperties, front = false) => (
  <div className={`md-win dw ${cls}${front ? " front" : ""}`} data-w={k} style={style}><div className="wb"><i /><i /><i /></div><div className="wbody"><Doc n={5} rows={["", "", "", "", ""]} /></div></div>
);

/* ---------- Displays, sideways (874 x 402 points) ---------- */
const thumb = (k: string, style?: React.CSSProperties, cls = "") => <span key={k} className={`dwin w-${k} ${cls}`} style={style}><AppIcon k={k} /></span>;
const row = (k: string, name: string, sub: string) => <div key={k} className="drow"><AppIcon k={k} /><div><b>{name}</b><span>{sub}</span></div></div>;
const Displays: React.FC<{ t: number }> = ({ t }) => {
  const u = E(t, NT.drag[0], NT.drag[1] - NT.drag[0], INOUT);
  const dropped = t >= NT.drag[1];
  const settle = SP(t, NT.drag[1], 0.42, 0.8);
  const held = t > NT.menu && t < NT.fill + 0.05;
  const menu = SP(t, NT.menu, 0.36, 0.8) * (1 - E(t, NT.fill + 0.05, 0.18));
  const filled = SP(t, NT.fill + 0.05, 0.45, 0.85);
  const fTap = TAP(t, NT.fill);
  // the dragged thumbnail flies from the small display to the big one (in points)
  const from = [12 + 140 * 0.33, 116 + 45], to = [153 + 238 * 0.82, 72 + 67];
  const fx = lerp(from[0], to[0], u), fy = lerp(from[1], to[1], u) - Math.sin(u * Math.PI) * 26;
  const dragO = E(t, NT.touch, 0.15) * (1 - E(t, NT.drag[1], 0.2));
  const holdO = E(t, NT.hold - 0.12, 0.12) * (1 - E(t, NT.menu + 0.15, 0.2));
  const [hx, hy] = [153 + 238 * (lerp(0.82, 0.5, filled)), 72 + 67];
  return (
    <div className="dsp" style={{ position: "absolute", inset: 0 }}>
      <span className="dx"><Glyph n="xmark" /></span>
      <div className="dh"><b>Displays</b><span>2 displays · 4 windows</span></div>
      <span className="dset">Settings</span>
      <div className="dbox">
        <div className="dd small"><div className="ds">
          {thumb("mail", { flex: dropped ? `${1 - settle} 1 0` : "1 1 0", opacity: dropped ? 0 : 1, visibility: u > 0 && !dropped ? "hidden" : undefined })}
          {thumb("msg", { flex: dropped ? `1 1 0` : "0 0 34%" })}
        </div><small>Built-in Retina Display</small></div>
        <div className="dd big"><div className="ds">
          {thumb("web")}{thumb("xcode")}
          {dropped ? thumb("mail", filled > 0.001 ? { position: "absolute", left: `${lerp(66.6, 0, filled)}%`, top: 0, bottom: 0, width: `${lerp(33.4, 100, filled)}%`, zIndex: 3, boxShadow: held ? "0 0 0 2.5px #0A84FF" : undefined }
            : { flex: `${settle} 1 0`, boxShadow: held ? "0 0 0 2.5px #0A84FF" : undefined }) : null}
        </div><small>Studio Display</small></div>
      </div>
      <div className="dlist">{row("web", "Safari", "Apple · Studio Display")}{row("mail", "Mail", dropped ? "Inbox · Studio Display" : "Inbox · Built-in Retina Display")}{row("xcode", "Xcode", "Glasspad · Studio Display")}{row("msg", "Messages", "Built-in Retina Display")}</div>
      <div className="dmenu" style={{ opacity: clamp(menu * 1.6), transform: `scale(${lerp(0.9, 1, menu)})` }}>
        {[["Left Half", "rectangle.lefthalf.filled"], ["Right Half", "rectangle.righthalf.filled"], ["Top Half", "rectangle.tophalf.filled"], ["Bottom Half", "rectangle.bottomhalf.filled"]].map(([n, g]) => <span key={n}><Glyph n={g} />{n}</span>)}
        <i />
        <span className="fill" style={{ background: fTap.press < 0.99 ? "rgba(26,26,26,0.08)" : undefined }}><Glyph n="rectangle.inset.filled" />Fill</span>
        <span><Glyph n="rectangle.center.inset.filled" />Center</span>
      </div>
      {/* the dragged copy */}
      {u > 0 && !dropped ? <span className="dwin lift" style={{ position: "absolute", left: fx - 23, top: fy - 45, width: 46, height: 90, zIndex: 5, boxShadow: "0 14px 28px -8px rgba(0,0,0,0.4)" }}><AppIcon k="mail" /></span> : null}
      <Finger x={fx} y={fy} o={dragO} />
      <Finger x={hx} y={hy} o={holdO} s={lerp(1, 0.9, E(t, NT.hold, 0.4))} />
      <Finger x={350} y={96 + 6 + 4 * 38 + 9 + 19} o={fTap.o} s={fTap.s} /><Ring x={350} y={96 + 6 + 4 * 38 + 9 + 19} p={fTap.ring} />
    </div>
  );
};

/* ---------- StandBy, sideways: Clock beside Now Playing (StandByMode.swift) ---------- */
const StandBy: React.FC<{ t: number }> = ({ t }) => {
  const red = E(t, NT.red, 1.2, INOUT);
  const mm = t < NT.tick ? "09" : "10";
  const flip = E(t, NT.tick - 0.15, 0.3);
  // the dot arrives and splits into the colon
  const land = SP(t, NT.dot, 0.5, 0.75);
  const split = SP(t, NT.dot + 0.35, 0.4, 0.7);
  const dotO = E(t, NT.dot - 0.1, 0.2);
  return (
    <div className="sby" style={{ position: "absolute", inset: 0 }}>
      <div className="sb-pane clk" style={{ width: 470, filter: `grayscale(${red})`, opacity: lerp(1, 0.8, red) }}>
        <div className="cd" style={{ marginBottom: 6 }}>Fri, 16 Oct <span className="chg"><Glyph n="bolt.fill" />82%</span></div>
        <div className="fm-clk">
          <span>10</span>
          <span className="fm-colon">
            <i style={{ position: "absolute", left: 17 - 9, top: lerp(50, 26, split) - 9, width: 18, height: 18, borderRadius: 9, background: "#D8D8D8", opacity: dotO, transform: `translate(${(1 - land) * 140}px, ${(1 - land) * 60}px)` }} />
            <i style={{ position: "absolute", left: 17 - 9, top: lerp(50, 74, split) - 9, width: 18, height: 18, borderRadius: 9, background: "#D8D8D8", opacity: dotO * clamp(split * 4), transform: `translate(${(1 - land) * 140}px, ${(1 - land) * 60}px)` }} />
          </span>
          <span style={{ position: "relative" }}>
            <span style={{ opacity: 1 - flip, display: "inline-block", transform: `translateY(${-flip * 20}px)` }}>{t < NT.tick ? mm : "09"}</span>
            <span style={{ position: "absolute", left: 0, top: 0, opacity: flip, transform: `translateY(${(1 - flip) * 20}px)` }}>10</span>
          </span>
        </div>
      </div>
      <div className="lyt-div" style={{ left: 522 }}><i /></div>
      <div className="sb-pane np" style={{ left: 546, filter: `grayscale(${red})`, opacity: lerp(1, 0.8, red) }}>
        <Poster style={{ width: 170, height: 170, borderRadius: 14 }} />
        <div className="npt"><b>Slow Light</b><span>Paper Rooms</span></div>
        <div className="npc"><Glyph n="backward.fill" /><Glyph n="pause.fill" /><Glyph n="forward.fill" /></div>
      </div>
      <div style={{ position: "absolute", inset: 0, zIndex: 5, background: "#C8261A", mixBlendMode: "multiply", opacity: red, pointerEvents: "none" }} />
    </div>
  );
};

/* ---------- the scene ---------- */
export const Night: React.FC = () => {
  const t = useCurrentFrame() / 60;
  const n = E(t, NT.night[0], NT.night[1] - NT.night[0], INOUT); // desk to nightstand
  const inO = E(t, D0, 0.4);
  const cross = E(t, NT.cross, 0.7, INOUT);
  const filled = SP(t, NT.fill + 0.05, 0.45, 0.85);
  const dark = E(t, NT.lamp, 0.9, INOUT);
  const exit = E(t, T0 - 0.5, 0.5, INOUT);
  // the phone moves from the desk stand to the nightstand
  const ph = { x: lerp(SPD.x, SPN.x, n), y: lerp(SPD.y, SPN.y, n), w: lerp(SPD.w, SPN.w, n) };
  const pw = ph.w * 71.9 / 150;
  const bg = `rgb(${[233, 231, 226].map((v, i) => Math.round(lerp(lerp(v, [35, 37, 43][i], n), [14, 15, 18][i], dark))).join(",")})`;
  const sU = ph.w / 21;
  return (
    <div className="fm" style={{ background: bg }}>
      <div className="fm-world" style={{ opacity: inO }}>
        {/* the desk */}
        <div style={{ opacity: 1 - clamp(n * 2), position: "absolute", inset: 0 }}>
          <div style={{ position: "absolute", left: 0, right: 0, top: 37 * CQ + OY, bottom: 0, background: "#DEDBD5" }} />
          <MacBook x={LIDX} y={LIDY} lid={LID}>
            <div className="mbx">
              <MenuBar app={cross > 0.5 ? "Messages" : "Mail"} clock="" />
              {macWin("m-mb", "mail", { transform: `translateX(${cross * 120}%)`, opacity: 1 - clamp(cross * 1.2 - 0.2) }, cross < 0.5)}
              {macWin("g-mb", "msg", undefined, cross >= 0.5)}
            </div>
          </MacBook>
          <Monitor x={MON.x} y={MON.y} w={MON.w}>
            <div className="mbx">
              <MenuBar app={filled > 0.5 ? "Mail" : "Safari"} />
              {macWin("s-st", "web", undefined, cross < 0.5)}
              {macWin("x-st", "xcode")}
              {cross > 0 ? macWin("m-st", "mail", {
                opacity: clamp(cross * 2), transform: `translateX(${(1 - OUT(cross)) * -70}%)`,
                left: `${lerp(22, 0.5, filled)}%`, top: `${lerp(20, 5.6, filled)}%`, width: `${lerp(50, 99, filled)}%`, height: `${lerp(56, 76, filled)}%`,
              }, true) : null}
            </div>
          </Monitor>
        </div>
        {/* the nightstand and the lamp */}
        <div style={{ opacity: clamp(n * 2 - 1), position: "absolute", inset: 0 }}>
          <div style={{ position: "absolute", inset: 0, background: "radial-gradient(40% 70% at 22% 34%, rgba(255,214,160,0.22), transparent 70%)", opacity: 1 - dark }} />
          <div className="nstand" style={{ top: 41 * CQ + 70, filter: `brightness(${lerp(1, 0.35, dark)})` }} />
          <div className="lamp" style={{ top: 14 * CQ + 70, filter: `brightness(${lerp(1, 0.35, dark)})` }}><i className="shade" /><i className="glow" style={{ opacity: 1 - dark }} /><i className="stem" /><i className="base" /></div>
        </div>
        <Stand x={ph.x + ph.w * 0.19} y={ph.y + pw - 1.6 * sU} width={ph.w * 0.62} dim={lerp(1, 0.5, n) * lerp(1, 0.36, dark)} />
        <Phone cx={ph.x + ph.w / 2} cy={ph.y + pw / 2} w={pw} turn={1} finish={n > 0.5 ? "dark" : "light"}
          land={<>
            {n < 0.7 ? <div style={{ position: "absolute", inset: 0, opacity: 1 - clamp((n - 0.3) / 0.4) }}><Displays t={t} /></div> : null}
            {n > 0.3 ? <div style={{ position: "absolute", inset: 0, opacity: clamp((n - 0.3) / 0.4) }}><StandBy t={t} /></div> : null}
          </>} />
      </div>
      <div style={{ position: "absolute", inset: 0, background: "#141414", opacity: exit }} />
      <Caption text="Displays" color="#63E6E2" p={E(t, D0 + 0.2, 0.6)} q={E(t, NT.night[0], 0.3)} />
      <Caption text="StandBy" color="#FF453A" dark p={E(t, N0 + 0.1, 0.6)} q={E(t, T0 - 0.6, 0.3)} />
    </div>
  );
};
