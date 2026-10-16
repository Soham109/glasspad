import React from "react";
import { Composition, Still } from "remotion";
import { Film } from "./Film";
import { FILM_LEN, FPS, TEASER_LEN } from "./timeline";
import { Teaser } from "./Teaser";
import { loadFonts } from "./theme";
import { Film as Film2 } from "./v2/Film";
import { Teaser as Teaser2 } from "./v2/Teaser";
import { CUT_LEN, Warped } from "./v2/warp";
import { Thumb1, Thumb2, Thumb3, Thumb4, Thumb5, Thumb6 } from "./v2/Thumbs";
import { loadFonts as loadFonts2 } from "./v2/system";

loadFonts();
loadFonts2();

const WarpedFilm: React.FC = () => <Warped cut="film"><Film2 /></Warped>;
const WarpedTeaser: React.FC = () => <Warped cut="teaser"><Teaser2 /></Warped>;

export const Root: React.FC = () => (
  <>
    <Composition id="GlasspadDemo" component={Film} defaultProps={{ vo: true, audio: true }} durationInFrames={FILM_LEN} fps={FPS} width={1920} height={1080} />
    <Composition id="GlasspadTeaser" component={Teaser} defaultProps={{ audio: true }} durationInFrames={TEASER_LEN} fps={FPS} width={1080} height={1920} />
    <Composition id="GlasspadTeaserVertical" component={WarpedTeaser} durationInFrames={CUT_LEN("teaser")} fps={60} width={1080} height={1920} />
    <Composition id="GlasspadFilm" component={WarpedFilm} durationInFrames={CUT_LEN("film")} fps={60} width={1920} height={1080} />
    {[Thumb1, Thumb2, Thumb3, Thumb4, Thumb5, Thumb6].map((T, i) => (
      <Still key={i} id={`GlasspadThumb${i + 1}`} component={T} width={1920} height={1080} />
    ))}
  </>
);
