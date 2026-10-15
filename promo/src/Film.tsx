import React from "react";
import { AbsoluteFill, Audio, staticFile, useCurrentFrame } from "remotion";
import { C } from "./theme";
import { S, FILM_STROKES, FILM_LEN } from "./timeline";
import { Setup } from "./film/Setup";
import { FILM_LAYOUT } from "./film/layout";
import { filmSetupState, PHONE_TOP } from "./film/director";
import { ripplesAt } from "./film/choreo";
import { ColdOpen, FILM_OPEN } from "./film/ColdOpen";
import { Captions } from "./Captions";
import { FILM_CAPS } from "./film/captions";
import { Speed } from "./scenes/Speed";
import { Settings } from "./scenes/Settings";
import { Modes } from "./scenes/Modes";
import { Privacy } from "./scenes/Privacy";
import { End } from "./scenes/End";

const inR = (f: number, a: number, b: number) => f >= a && f < b;
export const FILM_MODES = [S.dock, S.keys, S.media, S.deck, S.macros, S.clipboard, S.present];

export const Film: React.FC<{ vo: boolean; audio?: boolean }> = ({ vo, audio = true }) => {
  const f = useCurrentFrame();
  const setup = inR(f, FILM_OPEN.morph[0], S.speed) || inR(f, S.spaces, S.settings);
  return (
    <AbsoluteFill style={{ background: C.paper }}>
      {setup && <Setup l={FILM_LAYOUT} {...filmSetupState(f)} ripples={ripplesAt(FILM_STROKES, f)} />}
      {f < FILM_OPEN.morph[1] && <ColdOpen f={f} t={FILM_OPEN} l={FILM_LAYOUT} phoneCam={PHONE_TOP} W={1920} H={1080} />}
      <Captions caps={FILM_CAPS} />
      {inR(f, S.speed, S.spaces) && <Speed f={f} at={S.speed} end={S.spaces} />}
      {inR(f, S.settings, S.menu) && <Settings f={f} at={S.settings} end={S.menu} />}
      {inR(f, S.menu, S.privacy) && <Modes f={f} menuAt={S.menu} modeAt={FILM_MODES} end={S.privacy} />}
      {inR(f, S.privacy, S.end) && <Privacy f={f} at={S.privacy} end={S.end} />}
      {inR(f, S.end, FILM_LEN) && <End f={f} at={S.end} />}
      {audio && <Audio src={staticFile(vo ? "mix-film-vo.wav" : "mix-film-novo.wav")} />}
    </AbsoluteFill>
  );
};
