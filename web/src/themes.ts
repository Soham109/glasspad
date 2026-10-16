/* The app's themes (Apps/iOS/Sources/Design/Theme.swift), in the order Settings lists them.
   The Themes card on the home page and the guide both read this list, so a new theme is one line here.
   bg is any CSS background; glass themes approximate the app's soft color pools. */
export interface Theme {
  key: string; name: string;
  bg: string; tile: string; ink: string; ink2: string; line: string;
  /** Swatch for the picker: a color, or two halves for themes that follow light and dark. */
  swatch: string;
  /** Mono has no colors: every accent is the ink. */
  mono?: boolean;
  dark?: boolean;
}

const glassLight = "radial-gradient(55% 55% at 5% 5%, #B9CFFFd9, transparent), radial-gradient(42% 42% at 36% 36%, #E3D3FFd9, transparent), radial-gradient(42% 42% at 12% 62%, #FFDCCBd9, transparent), radial-gradient(42% 42% at 62% 12%, #FFDCCBd9, transparent), radial-gradient(40% 40% at 92% 95%, #C6EBE4d9, transparent), #EDEFF6";
const glassDark = "radial-gradient(55% 55% at 5% 5%, #2B3A8Cd9, transparent), radial-gradient(40% 40% at 36% 36%, #4A2A78d9, transparent), radial-gradient(42% 42% at 12% 66%, #0E5560d9, transparent), radial-gradient(42% 42% at 66% 12%, #0E5560d9, transparent), radial-gradient(36% 36% at 95% 95%, #5A2050d9, transparent), #0B0D16";

export const THEMES: Theme[] = [
  { key: "paper", name: "Paper", bg: "#F2F1EE", tile: "#FBFAF8", ink: "#1A1A1A", ink2: "rgba(26,26,26,.56)", line: "rgba(26,26,26,.08)", swatch: "#F2F1EE" },
  { key: "graphite", name: "Graphite", bg: "#141414", tile: "#1F1F1F", ink: "#F2F1EE", ink2: "rgba(242,241,238,.58)", line: "rgba(255,255,255,.1)", swatch: "#141414", dark: true },
  { key: "system", name: "System", bg: "#F2F1EE", tile: "#FBFAF8", ink: "#1A1A1A", ink2: "rgba(26,26,26,.56)", line: "rgba(26,26,26,.08)", swatch: "linear-gradient(90deg, #F2F1EE 50%, #141414 50%)" },
  { key: "mono", name: "Mono", bg: "#FFFFFF", tile: "#F4F4F4", ink: "#000000", ink2: "rgba(0,0,0,.55)", line: "rgba(0,0,0,.1)", swatch: "linear-gradient(90deg, #FFFFFF 50%, #000000 50%)", mono: true },
  { key: "sand", name: "Sand", bg: "#ECE4D6", tile: "#F7F2E9", ink: "#2E261D", ink2: "rgba(46,38,29,.58)", line: "rgba(59,47,34,.1)", swatch: "#ECE4D6" },
  { key: "midnight", name: "Midnight", bg: "#0B111D", tile: "#151D2D", ink: "#E8EDF7", ink2: "rgba(232,237,247,.6)", line: "rgba(169,188,230,.13)", swatch: "#0B111D", dark: true },
  { key: "glass", name: "Glass", bg: glassLight, tile: "rgba(255,255,255,.52)", ink: "#11141C", ink2: "rgba(17,20,28,.56)", line: "rgba(255,255,255,.7)", swatch: glassLight },
  { key: "glassDark", name: "Glass Dark", bg: glassDark, tile: "rgba(255,255,255,.085)", ink: "#F3F4F9", ink2: "rgba(243,244,249,.6)", line: "rgba(255,255,255,.12)", swatch: glassDark, dark: true },
];

/** CSS custom properties for a theme, for a style attribute or element.style. */
export const themeVars = (t: Theme) =>
  `--pt-bg:${t.bg};--tile:${t.tile};--ink:${t.ink};--ink2:${t.ink2};--tline:${t.line};--tint:${t.dark ? "26%" : "16%"}`;

/** One line about the collection, used by the card and the guide. */
export const themesLine = () => {
  const glass = THEMES.filter(t => /glass/i.test(t.key)).length;
  return `${THEMES.length} themes, light, dark${glass ? " and glass" : ""}. System follows your iPhone.`;
};
