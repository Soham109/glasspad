// Live action with the real app on its screens. Layers, bottom to top:
//   1. the plate (the stock clip as shot)
//   2. each tracked screen: the app, corner-pinned to the screen's four corners every frame
//      (a CSS matrix3d homography), matched to the shot's light (exposure, a soft sheen, the
//      lens's own softness)
//   3. the keyed foreground (scripts/v4/footage.py): hands, bezels and fingers over the screen
// all inside one "lens" box, so a camera move (push in, drift) moves them together.
import React from "react";
import { AbsoluteFill, OffthreadVideo, staticFile, useCurrentFrame, useVideoConfig } from "remotion";
import { FPS } from "../core";
import { quadToCss } from "./homography";

export type Track = {
  src: string; fg: string; fps: number; w: number; h: number; frames: number;
  crop: [number, number, number, number];
  screens: (number[][] | null)[];
};

export type ScreenSpec = {
  /** The app, drawn at w x h (its own pixels). */
  w: number;
  h: number;
  content: React.ReactNode;
  /** 0..1: how bright the screen reads in this room (a lit phone in daylight is not pure white). */
  exposure?: number;
  /** Grows the pinned rectangle past the green so no green fringe can show (fraction). */
  bleed?: number;
  /** Rotate which tracked corner is the app's top left (0..3). */
  rot?: number;
};

export type Lens = {
  /** Zoom about (cx, cy) in source pixels; 1 = the clip fills the frame. */
  zoom?: number;
  cx?: number;
  cy?: number;
  /** Extra softness of the whole plate in output px (a rack focus away from it). */
  blur?: number;
};

const cornersAt = (track: Track, screen: number, t: number) => {
  const q = track.screens[screen];
  if (!q) return null;
  // The tracked corners are per source frame; between frames they are interpolated so the
  // pin never steps, then the same time is what the plate shows.
  const x = Math.max(0, Math.min(track.frames - 1, t * track.fps));
  const i = Math.floor(x), j = Math.min(track.frames - 1, i + 1), u = x - i;
  return q[i].map((v, k) => v + (q[j][k] - v) * u);
};

export const Footage: React.FC<{
  track: Track;
  /** Seconds into the clip at this Sequence's frame 0. */
  from: number;
  /** Playback rate (1 = as shot). */
  rate?: number;
  screens?: (ScreenSpec | null)[];
  lens?: Lens | ((f: number) => Lens);
  grade?: React.CSSProperties["filter"];
  children?: React.ReactNode;
}> = ({ track, from, rate = 1, screens = [], lens = {}, grade, children }) => {
  const f = useCurrentFrame();
  const { width, height } = useVideoConfig();
  const L = typeof lens === "function" ? lens(f) : lens;
  const t = from + (f / FPS) * rate;
  // The plate covers the frame; the lens zooms about a point in source pixels, which stays
  // where it was on screen.
  const base = Math.max(width / track.w, height / track.h);
  const z = L.zoom ?? 1;
  const cx = L.cx ?? track.w / 2, cy = L.cy ?? track.h / 2;
  const k = base * z;
  const ox = (cx - track.w / 2) * base + width / 2 - cx * k;
  const oy = (cy - track.h / 2) * base + height / 2 - cy * k;
  const startFrom = Math.round(from * FPS);
  // Frame the composition asks for vs. the clip's own frame: OffthreadVideo shows the source
  // frame at time t; the corners use the same t.
  const [x0, y0, cw, ch] = track.crop;
  return (
    <AbsoluteFill style={{ overflow: "hidden", background: "#000" }}>
      <div style={{ position: "absolute", left: 0, top: 0, width: track.w, height: track.h, transformOrigin: "0 0", transform: `translate(${ox}px, ${oy}px) scale(${k})`, filter: [grade, L.blur ? `blur(${L.blur / k}px)` : ""].filter(Boolean).join(" ") || undefined }}>
        <OffthreadVideo src={staticFile(track.src)} startFrom={startFrom} playbackRate={rate} muted style={{ position: "absolute", left: 0, top: 0, width: track.w, height: track.h }} />
        {screens.map((sc, i) => {
          if (!sc) return null;
          const q = cornersAt(track, i, t);
          if (!q) return null;
          const pts: [number, number][] = [[q[0], q[1]], [q[2], q[3]], [q[4], q[5]], [q[6], q[7]]];
          const r = sc.rot ?? 0;
          const ord = [0, 1, 2, 3].map((n) => pts[(n + r) % 4]);
          // bleed: push every corner away from the centre
          const mx = ord.reduce((a, p) => a + p[0], 0) / 4, my = ord.reduce((a, p) => a + p[1], 0) / 4;
          const b = 1 + (sc.bleed ?? 0.012);
          const grown = ord.map(([x, y]) => [mx + (x - mx) * b, my + (y - my) * b] as [number, number]);
          const exp = sc.exposure ?? 0.92;
          return (
            <div key={i} style={{ position: "absolute", left: 0, top: 0, width: sc.w, height: sc.h, transformOrigin: "0 0", transform: quadToCss(sc.w, sc.h, grown), overflow: "hidden" }}>
              <div style={{ position: "absolute", inset: 0, filter: `brightness(${exp}) contrast(0.96) saturate(0.94)` }}>{sc.content}</div>
              {/* the glass: a faint sheen from the room's light */}
              <div style={{ position: "absolute", inset: 0, background: "linear-gradient(125deg, rgba(255,255,255,0.10) 0%, rgba(255,255,255,0.02) 38%, rgba(255,255,255,0) 60%)" }} />
            </div>
          );
        })}
        <OffthreadVideo src={staticFile(track.fg)} transparent startFrom={startFrom} playbackRate={rate} muted style={{ position: "absolute", left: x0, top: y0, width: cw, height: ch }} />
        {children}
      </div>
    </AbsoluteFill>
  );
};

/** Maps a point in the clip's source pixels to output pixels for a lens (to place overlays). */
export const lensPoint = (track: Track, L: Lens, width: number, height: number, x: number, y: number) => {
  const base = Math.max(width / track.w, height / track.h);
  const z = L.zoom ?? 1;
  const cx = L.cx ?? track.w / 2, cy = L.cy ?? track.h / 2;
  const k = base * z;
  const ox = (cx - track.w / 2) * base + width / 2 - cx * k;
  const oy = (cy - track.h / 2) * base + height / 2 - cy * k;
  return { x: ox + x * k, y: oy + y * k };
};

export { cornersAt };
