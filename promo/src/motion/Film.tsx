import React from "react";
import { AbsoluteFill, useCurrentFrame } from "remotion";
import "./site/device.css";
import "./site/redo.css";
import "./site/v3.css";
import "./site/surface.css";
import "./film.css";
import { Desk } from "./scenes/Desk";
import { Couch } from "./scenes/Couch";
import { Night } from "./scenes/Night";
import { Themes } from "./scenes/Themes";
import { Finale } from "./scenes/Finale";
import { barF, FILM_LEN } from "./timeline";

/* The motion film: one component per stretch of the film, each drawing its own world from the
   film's frame (no Sequence, so every part reads absolute film time). Where two meet they
   overlap by a few frames and the later one fades in over the earlier. */
type Part = { C: React.FC; from: number; to: number; fadeIn?: number };
const PARTS: Part[] = [
  { C: Desk, from: 0, to: barF(25) },
  { C: Couch, from: barF(25), to: barF(33) },
  { C: Night, from: barF(33), to: barF(40) },
  { C: Themes, from: barF(40), to: barF(43) },
  { C: Finale, from: barF(43), to: FILM_LEN },
];

export const MotionFilm: React.FC = () => {
  const f = useCurrentFrame();
  return (
    <AbsoluteFill style={{ background: "#E9E7E2" }}>
      {PARTS.filter(p => f >= p.from && f < p.to).map((p, i) => (
        <Fade key={i} from={p.from} fadeIn={p.fadeIn} f={f}><p.C /></Fade>
      ))}
    </AbsoluteFill>
  );
};
const Fade: React.FC<{ from: number; fadeIn?: number; f: number; children: React.ReactNode }> = ({ from, fadeIn, f, children }) => (
  <div style={{ position: "absolute", inset: 0, opacity: fadeIn ? Math.min(1, Math.max(0, (f - from) / fadeIn)) : 1 }}>{children}</div>
);
export const MOTION_LEN = FILM_LEN;
