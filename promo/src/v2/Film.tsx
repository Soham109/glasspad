// The film: scenes on the music grid (edit.json). Audio is mixed offline (scripts/film/mix.py)
// and muxed after render, so the picture stays frame exact and the mix is measured.
import React from "react";
import { AbsoluteFill, Sequence } from "remotion";
import { C, s } from "./system";
import { Hook } from "./scenes/Hook";
import { Desk } from "./scenes/Desk";
import { Hand } from "./scenes/Hand";
import { Outro } from "./scenes/Outro";

export const Film: React.FC = () => (
  <AbsoluteFill style={{ background: C.paper }}>
    <Sequence from={0} durationInFrames={s(8.6)} name="Hook">
      <Hook />
    </Sequence>
    <Sequence from={0} durationInFrames={s(40.4)} name="Desk">
      <Desk />
    </Sequence>
    <Sequence from={0} durationInFrames={s(60.6)} name="Hand">
      <Hand />
    </Sequence>
    <Sequence from={0} name="Outro">
      <Outro />
    </Sequence>
  </AbsoluteFill>
);
