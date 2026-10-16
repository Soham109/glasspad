// Product shots of the phone (and a few drawn sets) without the full 3D stage: a phone placed
// in the frame with its own perspective tilt, a contact shadow, and a soft reflection on a
// dark surface. Sizes are output pixels, so the phone is always rasterised at full detail.
import React from "react";
import { AbsoluteFill } from "remotion";
import { IPhone, iphoneScreen } from "../devices/IPhone";

export type PhonePose = {
  x: number; // centre, output px
  y: number;
  size: number; // short side, px
  rx?: number; // tilt back (deg)
  ry?: number; // turn (deg)
  rz?: number; // roll (deg)
  orient?: "portrait" | "landscape";
  blur?: number;
  opacity?: number;
};

export const StudioPhone: React.FC<{ pose: PhonePose; children?: React.ReactNode; sweep?: number; reflection?: boolean; shadow?: number; perspective?: number; overlay?: React.ReactNode }> = ({ pose, children, sweep = -1, reflection = false, shadow = 0.5, perspective = 2400, overlay }) => {
  const o = pose.orient ?? "portrait";
  const sc = iphoneScreen(pose.size, o);
  const t = `rotateX(${pose.rx ?? 0}deg) rotateY(${pose.ry ?? 0}deg) rotateZ(${pose.rz ?? 0}deg)`;
  const box = (child: React.ReactNode, flip = false) => (
    <div style={{ position: "absolute", left: pose.x - sc.W / 2, top: pose.y - sc.H / 2 + (flip ? sc.H + 12 : 0), width: sc.W, height: sc.H, transformStyle: "preserve-3d", transform: flip ? `${t} scaleY(-1)` : t, transformOrigin: flip ? "50% 0%" : "50% 50%" }}>{child}</div>
  );
  return (
    <AbsoluteFill style={{ perspective, perspectiveOrigin: `${pose.x}px ${pose.y}px`, filter: pose.blur ? `blur(${pose.blur}px)` : undefined, opacity: pose.opacity ?? 1 }}>
      {shadow > 0 ? <div style={{ position: "absolute", left: pose.x - sc.W * 0.45, top: pose.y + sc.H * 0.42, width: sc.W * 0.9, height: sc.H * 0.16, borderRadius: "50%", background: `rgba(0,0,0,${shadow})`, filter: `blur(${sc.H * 0.05}px)` }} /> : null}
      {reflection ? (
        <div style={{ position: "absolute", inset: 0, opacity: 0.18, WebkitMaskImage: `linear-gradient(180deg, rgba(0,0,0,0) ${((pose.y + sc.H / 2) / 1080) * 100}%, rgba(0,0,0,1) ${((pose.y + sc.H / 2 + 20) / 1080) * 100}%, rgba(0,0,0,0) ${((pose.y + sc.H) / 1080) * 100}%)` }}>
          {box(<IPhone size={pose.size} orient={o}>{children}</IPhone>, true)}
        </div>
      ) : null}
      {box(
        <>
          <IPhone size={pose.size} orient={o} sweep={sweep}>{children}</IPhone>
          {overlay ? <div style={{ position: "absolute", left: sc.x, top: sc.y, width: sc.w, height: sc.h, borderRadius: pose.size * 0.13, overflow: "hidden", pointerEvents: "none" }}>{overlay}</div> : null}
        </>,
      )}
    </AbsoluteFill>
  );
};

/** A point on the phone's screen (u, v in 0..1) in output px, ignoring the tilt (for flat poses). */
export const phonePoint = (pose: PhonePose, u: number, v: number) => {
  const o = pose.orient ?? "portrait";
  const sc = iphoneScreen(pose.size, o);
  const lx = sc.x + u * sc.w - sc.W / 2, ly = sc.y + v * sc.h - sc.H / 2;
  const r = ((pose.rz ?? 0) * Math.PI) / 180;
  return { x: pose.x + lx * Math.cos(r) - ly * Math.sin(r), y: pose.y + lx * Math.sin(r) + ly * Math.cos(r) };
};
