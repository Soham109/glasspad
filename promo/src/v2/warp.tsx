// The final cut is the picture timeline played through a time warp (edit.json "warp", built by
// scripts/film/build_edit.py): faster voice, tighter gaps, hits pinned to the new score's bars.
// Each final frame renders the picture at its warped time (a per-frame Sequence offset), so springs, recordings
// and type all follow the same map, and the mix uses the same map for every sound cue.
import React from "react";
import { Sequence, useCurrentFrame } from "remotion";
import edit from "./edit.json";
import { FPS } from "./system";

type Cut = "film" | "teaser";
const K = (edit as any).warp as Record<Cut, [number, number][]>;

/** Final-cut seconds to picture-timeline seconds. */
export const unwarp = (t: number, cut: Cut) => {
  const k = K[cut];
  for (let i = 1; i < k.length; i++) {
    const [o0, n0] = k[i - 1], [o1, n1] = k[i];
    if (t <= n1) return o0 + ((t - n0) * (o1 - o0)) / (n1 - n0);
  }
  const [o, n] = k[k.length - 1];
  return o + (t - n);
};

export const Warped: React.FC<{ cut: Cut; children: React.ReactNode }> = ({ cut, children }) => {
  const f = useCurrentFrame();
  const old = Math.round(unwarp(f / FPS, cut) * FPS);
  // A Sequence offset (not <Freeze>, which clamps to the cut's shorter length) so children see `old`.
  return (
    <Sequence from={f - old} layout="none">
      {children}
    </Sequence>
  );
};

export const CUT_LEN = (cut: Cut) => Math.round((edit as any).audio[cut].duration * FPS);
