// Real phone recordings. A clip is placed as segments: from local frame `at`, play the
// recording from `src` seconds. Cuts happen only where the app's screen is still, so the
// remap is invisible; it lets the app's real events land on the voice.
import React from "react";
import { OffthreadVideo, Sequence, staticFile, useCurrentFrame } from "remotion";
import clips from "../clips.json";
import tracksData from "../trackpad-tracks.json";
import { C, FPS, clamp01, lerp } from "../system";

export type Seg = { at: number; src: number };
type ClipName = "trackpad" | "menu" | "actions" | "media";

export const PhoneClip: React.FC<{ clip: ClipName; segs: Seg[]; len: number; w: number; h: number }> = ({ clip, segs, len, w, h }) => {
  const file = (clips as any)[clip].file as string;
  return (
    <div style={{ position: "absolute", inset: 0, width: w, height: h }}>
      {segs.map((sg, i) => {
        const end = i + 1 < segs.length ? segs[i + 1].at : len;
        if (end <= sg.at) return null;
        return (
          <Sequence key={i} from={sg.at} durationInFrames={end - sg.at} layout="none">
            <OffthreadVideo src={staticFile(file)} startFrom={Math.round(sg.src * FPS)} muted style={{ position: "absolute", left: 0, top: 0, width: w, height: h, objectFit: "cover" }} />
          </Sequence>
        );
      })}
    </div>
  );
};

/** Which recording time is on screen at local frame `f` for these segments. */
export const clipTime = (segs: Seg[], f: number) => {
  let cur = segs[0];
  for (const sg of segs) if (f >= sg.at) cur = sg;
  return cur.src + (f - cur.at) / FPS;
};

/** Finger positions (0..1 of the landscape surface) in the trackpad recording at time t. */
export const fingersAt = (t: number): [number, number][] => {
  const fr = (tracksData as any).frames as [number, number][][];
  const i = Math.max(0, Math.min(fr.length - 1, Math.round(t * FPS)));
  return fr[i] ?? [];
};

/** Contact rings drawn over the app's own dots: the film's "finger". */
export const Touches: React.FC<{ segs: Seg[]; w: number; h: number; color?: string }> = ({ segs, w, h, color = C.paper }) => {
  const f = useCurrentFrame();
  const t = clipTime(segs, f);
  const now = fingersAt(t);
  // presence over the last few frames softens the start and end of a touch
  const before = fingersAt(t - 4 / FPS).length;
  const after = fingersAt(t + 4 / FPS).length;
  const fade = now.length ? clamp01(0.4 + 0.3 * (before ? 1 : 0) + 0.3 * (after ? 1 : 0)) : 0;
  const d = h * 0.2;
  // A short glide trail behind each finger (the app icon's motif): the last 0.3 s of travel.
  const trails: string[] = [];
  if (now.length) {
    for (let k = 0; k < now.length; k++) {
      const pts: [number, number][] = [];
      for (let j = 0; j <= 18; j++) {
        const fs = fingersAt(t - j / FPS);
        if (fs.length !== now.length) break;
        pts.push([fs[k][0] * w, fs[k][1] * h]);
      }
      if (pts.length > 1) trails.push(pts.map(([x, y], i) => `${i ? "L" : "M"}${x.toFixed(1)} ${y.toFixed(1)}`).join(" "));
    }
  }
  return (
    <div style={{ position: "absolute", inset: 0 }}>
      <svg width={w} height={h} style={{ position: "absolute", inset: 0 }}>
        {trails.map((dd, i) => <path key={i} d={dd} fill="none" stroke={color} strokeOpacity={0.14 * fade} strokeWidth={d * 0.55} strokeLinecap="round" strokeLinejoin="round" />)}
      </svg>
      {/* follow-through: after a lift the rings stay a moment, shrinking, so the glass never goes blank at once */}
      {!now.length ? (() => {
        for (let j = 1; j <= 54; j++) {
          const past = fingersAt(clipTime(segs, f - j));
          if (past.length) {
            const age = j / 54;
            return past.map(([x, y], i) => {
              const dd = d * lerp(1, 0.5, age);
              return <div key={i} style={{ position: "absolute", left: x * w - dd / 2, top: y * h - dd / 2, width: dd, height: dd, borderRadius: dd, boxShadow: `inset 0 0 0 ${d * 0.04}px ${color}`, opacity: Math.pow(1 - age, 1.6) * 0.75 }} />;
            });
          }
        }
        return null;
      })() : null}
      {now.map(([x, y], i) => (
        <div key={i} style={{ position: "absolute", left: x * w - d / 2, top: y * h - d / 2, width: d, height: d, borderRadius: d, boxShadow: `inset 0 0 0 ${d * 0.05}px ${color}`, opacity: fade }} />
      ))}
    </div>
  );
};
