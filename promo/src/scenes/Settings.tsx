import React from "react";
import { AbsoluteFill } from "remotion";
import { C, FONT } from "../theme";
import { Caption } from "../Captions";
import { clamp, lerp, prog, spring, minJerk, snappy } from "../motion";

/* "It follows your Mac's own trackpad settings." Two panes, as on the site: the Mac's Trackpad settings,
   a wire, and what the phone uses. A change on the Mac travels to the phone. */
const Toggle: React.FC<{ on: number }> = ({ on }) => (
  <span style={{ position: "relative", width: 58, height: 34, borderRadius: 17, background: on > 0.5 ? C.ink : "rgba(26,26,26,0.14)", display: "inline-block" }}>
    <i style={{ position: "absolute", top: 3, left: lerp(3, 27, on), width: 28, height: 28, borderRadius: 14, background: "#fff", boxShadow: "0 0 0 1px rgba(26,26,26,0.08)" }} />
  </span>
);
const Row: React.FC<{ label: string; children: React.ReactNode; last?: boolean }> = ({ label, children, last }) => (
  <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", height: 82, borderBottom: last ? undefined : "1px solid rgba(26,26,26,0.08)", fontSize: 27, fontWeight: 500, letterSpacing: "-0.015em" }}>
    <span>{label}</span>
    {children}
  </div>
);
const Pane: React.FC<{ title: string; note: string; x: number; y: number; w: number; o: number; children: React.ReactNode }> = ({ title, note, x, y, w, o, children }) => (
  <div style={{ position: "absolute", left: x, top: y + (1 - o) * 40, width: w, opacity: clamp(o * 1.4), background: C.raised, borderRadius: 32, boxShadow: "0 0 0 1px rgba(26,26,26,0.07)", padding: "26px 36px 14px" }}>
    <div style={{ fontSize: 22, fontWeight: 600, marginBottom: 6 }}>{title} <span style={{ color: C.ink3, fontWeight: 500 }}>{note}</span></div>
    {children}
  </div>
);
const Swap: React.FC<{ a: string; b: string; t: number }> = ({ a, b, t }) => (
  <span style={{ position: "relative", display: "inline-block", overflow: "hidden", height: 34, width: 60, textAlign: "right", color: C.ink2 }}>
    <span style={{ position: "absolute", right: 0, transform: `translateY(${-t * 100}%)`, opacity: 1 - t }}>{a}</span>
    <span style={{ position: "absolute", right: 0, transform: `translateY(${(1 - t) * 100}%)`, opacity: t, color: C.ink }}>{b}</span>
  </span>
);

export const SETTINGS_EVENTS = (at: number) => ({ toggleClick: at + 116, pulseArrive: at + 152, dragStart: at + 196, dragEnd: at + 262 });

export const Settings: React.FC<{ f: number; at: number; end: number }> = ({ f, at, end }) => {
  const k = f - at;
  const ev = SETTINGS_EVENTS(0);
  const out = clamp((f - (end - 20)) / 18);
  const pA = spring(k, 18, 160, 1), pB = spring(k, 28, 160, 1);
  const drag = snappy(k, ev.toggleClick);
  const flip = clamp(spring(k, ev.toggleClick, 420, 0.75));
  const arrived = clamp(spring(k, ev.pulseArrive, 300, 1));
  const sp = minJerk((k - ev.dragStart) / (ev.dragEnd - ev.dragStart));
  const speed = lerp(1.5, 2.5, sp); // of 0..3
  const meter = lerp(1.5, 2.5, minJerk((k - ev.dragStart - 10) / (ev.dragEnd - ev.dragStart)));
  // the wire: a pulse per change, and a stream while dragging
  const pulses: number[] = [];
  const pulseAt = (s: number) => { const t = (k - s) / 36; if (t >= 0 && t <= 1) pulses.push(minJerk(t)); };
  pulseAt(ev.toggleClick);
  for (let s = ev.dragStart; s < ev.dragEnd; s += 9) pulseAt(s);
  const paneW = 690, y = 392, gx = 160, wireX = gx + paneW, wireW = 1920 - 2 * gx - 2 * paneW;
  const trackW = 230;
  // pointer on the Mac pane
  const toggleX = gx + paneW - 36 - 58 + 14, toggleY = y + 74 + 82 * 2 + 41;
  const knobX = gx + paneW - 36 - trackW + (speed / 3) * trackW, knobY = y + 74 + 41;
  const pIn = minJerk((k - 70) / 40);
  let px = lerp(gx + 300, toggleX, pIn), py = lerp(y + 560, toggleY, pIn);
  const toKnob = minJerk((k - (ev.toggleClick + 30)) / 46);
  px = lerp(px, gx + paneW - 36 - trackW + 0.5 * trackW, toKnob);
  py = lerp(py, knobY, toKnob);
  if (k >= ev.dragStart) { px = knobX; py = knobY; }
  const press = (k >= ev.toggleClick && k < ev.toggleClick + 7) || (k >= ev.dragStart - 2 && k <= ev.dragEnd + 2) ? 1 : 0;
  void drag;
  return (
    <AbsoluteFill style={{ background: C.paper, fontFamily: FONT, color: C.ink, opacity: 1 - out }}>
      <Caption frame={f} c={{ at: at + 4, out: end - 26, title: "It follows your Mac's own trackpad settings.", x: gx, y: 128, size: 80, maxW: 1300 }} />
      <Pane title="Trackpad" note="on your Mac" x={gx} y={y} w={paneW} o={pA}>
        <Row label="Tracking speed">
          <span style={{ position: "relative", width: trackW, height: 34, display: "inline-block" }}>
            <i style={{ position: "absolute", left: 0, right: 0, top: 15, height: 4, borderRadius: 2, background: "rgba(26,26,26,0.12)" }} />
            <i style={{ position: "absolute", left: 0, width: (speed / 3) * trackW, top: 15, height: 4, borderRadius: 2, background: C.ink }} />
            <i style={{ position: "absolute", left: (speed / 3) * trackW - 15, top: 2, width: 30, height: 30, borderRadius: 15, background: "#fff", boxShadow: "0 0 0 1px rgba(26,26,26,0.16)" }} />
          </span>
        </Row>
        <Row label="Natural scrolling"><Toggle on={1} /></Row>
        <Row label="Three finger drag"><Toggle on={flip} /></Row>
        <Row label="Swipe between pages"><Toggle on={1} /></Row>
        <Row label="Mission Control" last><Toggle on={1} /></Row>
      </Pane>
      <svg width={wireW} height={40} style={{ position: "absolute", left: wireX, top: y + 250 }}>
        <line x1={14} x2={wireW - 14} y1={20} y2={20} stroke={C.ink} strokeOpacity={0.16 * pB} strokeWidth={2} strokeDasharray="2 9" strokeLinecap="round" />
        {pulses.map((t, i) => <circle key={i} cx={lerp(14, wireW - 14, t)} cy={20} r={6} fill={C.ink} opacity={Math.sin(Math.PI * t)} />)}
      </svg>
      <Pane title="Glasspad" note="on your phone" x={1920 - gx - paneW} y={y} w={paneW} o={pB}>
        <Row label="Tracking speed">
          <span style={{ position: "relative", width: trackW, height: 10, borderRadius: 5, background: "rgba(26,26,26,0.12)", overflow: "hidden", display: "inline-block" }}>
            <i style={{ position: "absolute", left: 0, top: 0, bottom: 0, width: (meter / 3) * trackW, background: C.ink, borderRadius: 5 }} />
          </span>
        </Row>
        <Row label="Natural scrolling"><Swap a="On" b="On" t={0} /></Row>
        <Row label="Three finger drag"><Swap a="Off" b="On" t={arrived} /></Row>
        <Row label="Swipe between pages"><Swap a="On" b="On" t={0} /></Row>
        <Row label="Mission Control" last><Swap a="On" b="On" t={0} /></Row>
      </Pane>
      {k > 60 && (
        <svg viewBox="0 0 16 22" width={26} height={36} style={{ position: "absolute", left: px, top: py, transformOrigin: "0 0", transform: `scale(${1 - 0.15 * press})`, opacity: clamp((k - 64) / 8) * (1 - clamp((k - ev.dragEnd - 30) / 12)) }}>
          <path d="M1 1v17l4.6-4.4 3 6.9 3-1.3-3-6.8H15Z" fill="#1A1A1A" stroke="#fff" strokeWidth={1.4} strokeLinejoin="round" />
        </svg>
      )}
    </AbsoluteFill>
  );
};
