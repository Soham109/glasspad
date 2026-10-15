import React from "react";
import { Composition } from "remotion";
import { Film } from "./Film";
import { FILM_LEN, FPS, TEASER_LEN } from "./timeline";
import { Teaser } from "./Teaser";
import { loadFonts } from "./theme";
import { Film as Film2 } from "./v2/Film";
import { Teaser as Teaser2 } from "./v2/Teaser";
import { FILM_LEN as FILM2_LEN, TEASER_LEN as TEASER2_LEN, loadFonts as loadFonts2 } from "./v2/system";

loadFonts();
loadFonts2();

export const Root: React.FC = () => (
  <>
    <Composition id="GlasspadDemo" component={Film} defaultProps={{ vo: true, audio: true }} durationInFrames={FILM_LEN} fps={FPS} width={1920} height={1080} />
    <Composition id="GlasspadTeaser" component={Teaser} defaultProps={{ audio: true }} durationInFrames={TEASER_LEN} fps={FPS} width={1080} height={1920} />
    <Composition id="GlasspadTeaserVertical" component={Teaser2} durationInFrames={TEASER2_LEN} fps={60} width={1080} height={1920} />
    <Composition id="GlasspadFilm" component={Film2} durationInFrames={FILM2_LEN} fps={60} width={1920} height={1080} />
  </>
);
