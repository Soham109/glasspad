// Glasspad film v4: a day with Glasspad. Scenes sit on the score's bars (edit.json); the audio
// is mixed offline (scripts/v4/mix.py) and muxed after the picture renders.
import React from "react";
import { AbsoluteFill, Sequence } from "remotion";
import { C, FILM_LEN } from "./core";
import { Morning, MORNING_LEN } from "./scenes/Morning";
import { Grain, Vignette } from "./fx";

export const FilmV4: React.FC = () => (
  <AbsoluteFill style={{ background: C.black }}>
    <Sequence from={0} durationInFrames={MORNING_LEN + 30} name="Morning">
      <Morning />
    </Sequence>
    <Vignette amount={0.38} />
    <Grain amount={0.05} />
  </AbsoluteFill>
);
export const FILM_V4_LEN = FILM_LEN;
