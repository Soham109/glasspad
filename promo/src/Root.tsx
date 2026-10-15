import React from "react";
import { Composition } from "remotion";
import { Film } from "./Film";
import { FILM_LEN, FPS, TEASER_LEN } from "./timeline";
import { Teaser } from "./Teaser";
import { loadFonts } from "./theme";

loadFonts();

export const Root: React.FC = () => (
  <>
    <Composition id="GlasspadDemo" component={Film} defaultProps={{ vo: true, audio: true }} durationInFrames={FILM_LEN} fps={FPS} width={1920} height={1080} />
    <Composition id="GlasspadTeaser" component={Teaser} defaultProps={{ audio: true }} durationInFrames={TEASER_LEN} fps={FPS} width={1080} height={1920} />
  </>
);
