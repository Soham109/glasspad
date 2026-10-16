// The morning desk, in 3D: a 27 inch display in the middle, a MacBook Pro on the left, the
// iPhone sideways on a small stand on the right (as the brief has it). Dark walnut desk, a
// window's dawn light from the back right. World units are millimetres x 1.5.
import React from "react";
import { Cam, Obj, Plane, Stage } from "./Stage3D";
import { ExternalDisplay, MacBookPro } from "../devices/Mac";
import { IPhone } from "../devices/IPhone";

export const MM = 1.5;
// Placement (world units). y = 0 is the desk top; negative y is up.
export const DESK = {
  display: { x: 0, z: -120, w: 613 * MM, ry: 0 },
  mbp: { x: -760, z: 160, w: 312 * MM, ry: 24 },
  phone: { x: 640, z: 210, short: 71.9 * MM, ry: -22, tilt: 16, lift: 46 },
};

/** Size of the display object (with stand) and of the MacBook (open, front on). */
const DISPLAY_H = (w: number) => w * (0.5625 * 0.957 + 0.044) + w * 0.3;

export const DeskSet: React.FC<{
  cam: Cam;
  display: React.ReactNode; // screen content at EXT points (1600 x 900)
  laptop: React.ReactNode; // screen content at MBP points (1512 x 982)
  phone: React.ReactNode; // landscape capture content (2622 x 1206)
  phoneSweep?: number;
  light?: number; // 0..1 dawn light strength
  children?: React.ReactNode;
}> = ({ cam, display, laptop, phone, phoneSweep = -1, light = 1, children }) => {
  const d = DESK.display, m = DESK.mbp, p = DESK.phone;
  const dh = DISPLAY_H(d.w);
  const mbpH = m.w * (0.649 + 0.03 + 0.018);
  const pw = p.short * (150 / 71.9);
  return (
    <Stage cam={cam} background={`radial-gradient(70% 60% at 72% 30%, rgba(255,176,120,${0.22 * light}) 0%, rgba(255,176,120,0) 70%), linear-gradient(180deg, #121014 0%, #1A1613 55%, #0B0A0A 100%)`}>
      {/* back wall with the window's light falling across it */}
      <Obj x={0} y={0} z={-1400} w={6000} h={2600} dof={false}>
        <div style={{ width: "100%", height: "100%", background: "linear-gradient(180deg, #17151A 0%, #221D1A 70%, #1A1614 100%)" }}>
          <div style={{ position: "absolute", left: "55%", top: "10%", width: "22%", height: "70%", background: `linear-gradient(115deg, rgba(255,190,140,${0.0}) 0%, rgba(255,190,140,${0.14 * light}) 40%, rgba(255,190,140,0) 80%)`, filter: "blur(30px)" }} />
        </div>
      </Obj>
      {/* the desk */}
      <Plane x={0} y={0} z={600} w={4200} d={3200} background={`radial-gradient(22% 14% at 50% 18%, rgba(150,140,220,0.16) 0%, rgba(150,140,220,0) 100%), radial-gradient(45% 40% at 60% 30%, rgba(255,190,140,${0.12 * light}) 0%, rgba(255,190,140,0) 100%), repeating-linear-gradient(90deg, rgba(255,255,255,0.012) 0px, rgba(255,255,255,0.012) 2px, rgba(0,0,0,0.02) 3px, rgba(0,0,0,0.0) 9px), linear-gradient(180deg, #2A1F18 0%, #3B2B20 50%, #2A1E16 100%)`}>
        {/* soft contact shadows */}
        <div style={{ position: "absolute", left: 2100 + d.x - 220, top: 1000 + d.z - 40, width: 440, height: 90, borderRadius: "50%", background: "rgba(0,0,0,0.55)", filter: "blur(24px)" }} />
        <div style={{ position: "absolute", left: 2100 + m.x - m.w * 0.62, top: 1000 + m.z - 40, width: m.w * 1.24, height: 120, borderRadius: "50%", background: "rgba(0,0,0,0.5)", filter: "blur(26px)", transform: `rotate(${-m.ry}deg)` }} />
        <div style={{ position: "absolute", left: 2100 + p.x - pw * 0.45, top: 1000 + p.z - 30, width: pw * 0.9, height: 70, borderRadius: "50%", background: "rgba(0,0,0,0.55)", filter: "blur(18px)", transform: `rotate(${-p.ry}deg)` }} />
      </Plane>
      {/* display */}
      <Obj x={d.x} y={0} z={d.z} w={d.w} h={dh} ry={d.ry} res={2}>
        <ExternalDisplay width={d.w * 2}>{display}</ExternalDisplay>
      </Obj>
      {/* MacBook Pro, open */}
      {/* the MacBook's keyboard half, flat on the desk in front of the lid */}
      <Obj x={m.x} y={0} z={m.z} w={m.w * 1.11} h={m.w * 0.69} ry={m.ry} rx={90} ax={0.5} ay={0} dof={false}>
        <div style={{ width: "100%", height: "100%", borderRadius: `0 0 ${m.w * 0.03}px ${m.w * 0.03}px`, background: "linear-gradient(180deg, #3A3B3F, #2A2B2E)", position: "relative" }}>
          <div style={{ position: "absolute", left: "8%", right: "8%", top: "6%", height: "48%", borderRadius: 8, background: "repeating-linear-gradient(90deg, #111 0 26px, #2A2B2E 26px 30px), #111", opacity: 0.85 }} />
          <div style={{ position: "absolute", left: "30%", right: "30%", top: "60%", height: "34%", borderRadius: 10, background: "#323337", boxShadow: "inset 0 0 0 1px rgba(255,255,255,0.05)" }} />
        </div>
      </Obj>
      <Obj x={m.x} y={0} z={m.z} w={m.w} h={mbpH} ry={m.ry} res={2}>
        <MacBookPro width={m.w * 2}>{laptop}</MacBookPro>
      </Obj>
      {/* the phone on its stand */}
      {/* the stand: an aluminium cradle behind the phone, and its foot */}
      <Obj x={p.x} y={0} z={p.z - 30} w={pw * 0.3} h={p.lift + p.short * 0.62} ry={p.ry} rx={22}>
        <div style={{ width: "100%", height: "100%", borderRadius: 8, background: "linear-gradient(180deg, #3C3D41, #1C1D20)" }} />
      </Obj>
      <Obj x={p.x} y={-p.lift + 2} z={p.z + 5} w={pw * 0.5} h={6} ry={p.ry}>
        <div style={{ width: "100%", height: "100%", borderRadius: 3, background: "linear-gradient(180deg, #4A4B4F, #232427)" }} />
      </Obj>
      <Obj x={p.x} y={-p.lift} z={p.z} w={pw} h={p.short} ry={p.ry} rx={p.tilt} res={6}>
        <IPhone size={p.short * 6} orient="landscape" sweep={phoneSweep}>{phone}</IPhone>
      </Obj>
      {children}
    </Stage>
  );
};
