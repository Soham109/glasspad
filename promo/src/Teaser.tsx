import React from "react";
import { AbsoluteFill, Audio, staticFile, useCurrentFrame } from "remotion";
import { C } from "./theme";
import { T, TEASER_STROKES, TEASER_LEN, TEASER_MODES } from "./timeline";
import { Setup } from "./film/Setup";
import { TEASER_LAYOUT } from "./film/layout";
import { teaserSetupState, TEASER_OPEN, V_PHONE, TEASER_CAPS } from "./film/teaserDirector";
import { ripplesAt } from "./film/choreo";
import { ColdOpen } from "./film/ColdOpen";
import { Captions } from "./Captions";
import { Modes } from "./scenes/Modes";
import { End } from "./scenes/End";

const inR = (f: number, a: number, b: number) => f >= a && f < b;
export const Teaser: React.FC<{ audio?: boolean }> = ({ audio = true }) => {
  const f = useCurrentFrame();
  return (
    <AbsoluteFill style={{ background: C.paper }}>
      {inR(f, TEASER_OPEN.morph[0], T.modes) && <Setup l={TEASER_LAYOUT} {...teaserSetupState(f)} ripples={ripplesAt(TEASER_STROKES, f)} />}
      {f < TEASER_OPEN.morph[1] && <ColdOpen f={f} t={TEASER_OPEN} l={TEASER_LAYOUT} phoneCam={V_PHONE} W={1080} H={1920} />}
      <Captions caps={TEASER_CAPS} />
      {inR(f, T.modes, T.end) && <Modes f={f} menuAt={T.modes - 200} modeAt={TEASER_MODES} end={T.end} W={1080} H={1920} vertical skipMenu count={4} />}
      {inR(f, T.end, TEASER_LEN) && <End f={f} at={T.end} W={1080} H={1920} />}
      {audio && <Audio src={staticFile("mix-teaser.wav")} />}
    </AbsoluteFill>
  );
};
