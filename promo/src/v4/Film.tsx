// Glasspad film v4: a day with Glasspad. Scenes sit on the score's bars (edit.json); the audio
// is mixed offline (scripts/v4/mix.py) and muxed after the picture renders.
import React from "react";
import { AbsoluteFill, Sequence } from "remotion";
import { C, FILM_LEN, FPS } from "./core";
import { Morning, MORNING_LEN } from "./scenes/Morning";
import { Layouts, Edit, Present } from "./scenes/Work";
import { Remote, Clipboard, Displays } from "./scenes/Home";
import { More, Private, End } from "./scenes/Finale";
import { Grain, Vignette } from "./fx";
import { sceneF } from "./timeline";

const S: React.FC<{ id: string; children: React.ReactNode; tail?: number }> = ({ id, children, tail = 0 }) => {
  const sc = sceneF(id);
  return (
    <Sequence from={sc.from} durationInFrames={sc.len + tail} name={id}>
      {children}
    </Sequence>
  );
};

export const FilmV4: React.FC = () => (
  <AbsoluteFill style={{ background: C.black }}>
    <Sequence from={0} durationInFrames={MORNING_LEN} name="Morning (open, actions, pinned)">
      <Morning />
    </Sequence>
    <S id="layouts"><Layouts /></S>
    <S id="edit"><Edit /></S>
    <S id="present"><Present /></S>
    <S id="remote"><Remote /></S>
    <S id="clipboard"><Clipboard /></S>
    <S id="displays"><Displays /></S>
    <S id="more"><More /></S>
    <S id="private"><Private /></S>
    <S id="end" tail={FILM_LEN - sceneF("end").to}><End /></S>
    <Vignette amount={0.32} />
    <Grain amount={0.045} />
  </AbsoluteFill>
);
export const FILM_V4_LEN = FILM_LEN;
void FPS;
