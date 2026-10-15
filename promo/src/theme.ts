import { loadFont } from "@remotion/fonts";
import { staticFile } from "remotion";

// Flat colours only. Paper, ink, graphite, and the app's own surface tones from Apps/iOS/Sources/Design/Theme.swift.
export const C = {
  paper: "#F2F1EE",
  ink: "#1A1A1A",
  graphite: "#141414",
  surface: "#FBFBF9", // icon surface, windows
  raised: "#FBFAF8", // app cards and buttons
  pressed: "#E6E4DF",
  tile: "#EDECE8", // icon background
  desk: "#E6E4DF",
  ink2: "rgba(26,26,26,0.62)",
  ink3: "rgba(26,26,26,0.42)",
  line: "rgba(26,26,26,0.10)",
  onDark: "#F2F1EE",
  onDark2: "rgba(242,241,238,0.62)",
  onDark3: "rgba(242,241,238,0.36)",
  lineDark: "rgba(242,241,238,0.14)",
  green: "#34C759", // the app's connected dot
};

// The app's per-mode accents (Apps/iOS/Sources/Modes/AppMode.swift). Used only inside redrawn app screens.
export const MODE_ACCENT: Record<string, string> = {
  trackpad: "#1A1A1A",
  dock: "#3D7BF2",
  keys: "#8A63E8",
  media: "#EC4F73",
  deck: "#E8930C",
  macros: "#12A594",
  clipboard: "#2E9E5B",
  present: "#EE6A2F",
};

export const FONT = "Inter, -apple-system, 'SF Pro Text', system-ui, sans-serif";
export const MONO = "ui-monospace, 'SF Mono', Menlo, monospace";

let requested = false;
export const loadFonts = () => {
  if (requested) return;
  requested = true;
  for (const w of ["400", "500", "600", "700"]) loadFont({ family: "Inter", url: staticFile(`fonts/Inter-${w}.woff2`), weight: w });
};
