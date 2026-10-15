// The film's design and motion system. Everything on screen takes its colour, type, timing
// and movement from here, so scenes stay consistent and a change lands everywhere.
import { loadFont } from "@remotion/fonts";
import { Easing, interpolate, spring, staticFile } from "remotion";
import edit from "./edit.json";

// ---------- Colour: flat only. Three neutrals and one accent. ----------
export const C = {
  paper: "#F2F1EE",
  ink: "#1A1A1A",
  graphite: "#141414",
  accent: "#0A84FF", // macOS system blue: the Mac's own highlight, used sparingly
  // Tints of the neutrals (still flat fills, never gradients).
  ink60: "rgba(26,26,26,0.6)",
  ink40: "rgba(26,26,26,0.4)",
  ink12: "rgba(26,26,26,0.12)",
  ink06: "rgba(26,26,26,0.06)",
  paper60: "rgba(242,241,238,0.6)",
  paper30: "rgba(242,241,238,0.3)",
  paper12: "rgba(242,241,238,0.12)",
  // Surfaces derived from the palette for drawn UI.
  sheet: "#FBFAF8", // windows, cards (the app's "raised")
  desk: "#E4E2DD", // ink 8% over paper
  band: "#BDBAB4", // phone aluminium band (site drawing)
  bezel: "#0C0C0C",
};

// ---------- Type ----------
export const FONT = "Inter, system-ui, sans-serif";
let fontsRequested = false;
export const loadFonts = () => {
  if (fontsRequested) return;
  fontsRequested = true;
  for (const w of [400, 500, 600, 700] as const) {
    loadFont({ family: "Inter", url: staticFile(`fonts/Inter-${w}.woff2`), weight: String(w) });
  }
};
// Display type is tight; text type is neutral.
export const T = {
  hero: { fontSize: 132, fontWeight: 600, letterSpacing: "-0.045em", lineHeight: 1.0 },
  title: { fontSize: 96, fontWeight: 600, letterSpacing: "-0.04em", lineHeight: 1.02 },
  head: { fontSize: 64, fontWeight: 600, letterSpacing: "-0.03em", lineHeight: 1.06 },
  sub: { fontSize: 34, fontWeight: 500, letterSpacing: "-0.015em", lineHeight: 1.2 },
  label: { fontSize: 22, fontWeight: 600, letterSpacing: "0.06em", lineHeight: 1.2, textTransform: "uppercase" as const },
};

// ---------- Timing grid: the music is 120 BPM ----------
export const FPS = 60;
export const BEAT = 30; // frames
export const BAR = 120;
export const PHRASE = 480;
export const s = (sec: number) => Math.round(sec * FPS);
export const FILM_LEN = s(edit.film.duration);
export const TEASER_LEN = s(edit.teaser.duration);

// ---------- Easing curves ----------
export const E = {
  out: Easing.bezier(0.16, 1, 0.3, 1), // expo out: arrivals
  in: Easing.bezier(0.7, 0, 0.84, 0), // expo in: departures
  inOut: Easing.bezier(0.65, 0, 0.35, 1), // moves between two rests
  glide: Easing.bezier(0.33, 0, 0.15, 1), // camera: slow start, long settle
  linear: (t: number) => t,
};

// ---------- Springs: named presets, used everywhere instead of ad hoc numbers ----------
export const SPRING = {
  snap: { damping: 22, stiffness: 320, mass: 0.6 }, // UI taps, small elements
  pop: { damping: 13, stiffness: 220, mass: 0.7 }, // a little overshoot: dots, icons
  settle: { damping: 26, stiffness: 120, mass: 1 }, // panels and devices arriving
  heavy: { damping: 30, stiffness: 70, mass: 1.4 }, // big camera and device moves
};
export type SpringName = keyof typeof SPRING;

/** 0 to 1 spring starting at `start` frames. */
export const spr = (frame: number, start: number, name: SpringName = "settle", fps = FPS) =>
  spring({ frame: frame - start, fps, config: SPRING[name] });

/** 0 to 1 eased progress over [start, start + dur). */
export const prog = (frame: number, start: number, dur: number, ease = E.inOut) =>
  interpolate(frame, [start, start + dur], [0, 1], { extrapolateLeft: "clamp", extrapolateRight: "clamp", easing: ease });

export const lerp = (a: number, b: number, t: number) => a + (b - a) * t;
export const clamp01 = (t: number) => Math.max(0, Math.min(1, t));

/** Piecewise keyframes: [[frame, value], ...] with one easing per segment. */
export const keys = (frame: number, kf: [number, number][], ease = E.inOut) => {
  if (frame <= kf[0][0]) return kf[0][1];
  for (let i = 1; i < kf.length; i++) {
    if (frame <= kf[i][0]) {
      const [f0, v0] = kf[i - 1];
      const [f1, v1] = kf[i];
      return lerp(v0, v1, ease((frame - f0) / Math.max(1, f1 - f0)));
    }
  }
  return kf[kf.length - 1][1];
};

/** Beat pulse: 1 at each beat, decaying. For things that breathe with the music. */
export const beatPulse = (frame: number, start = 0, decay = 10) => {
  const f = frame - start;
  if (f < 0) return 0;
  return Math.exp(-(f % BEAT) / decay);
};
