// The v4 film's timing, type and colour. Motion curves and springs are the v3 film's own
// (v2/system.ts), so the two films move alike.
import { staticFile } from "remotion";
import edit from "./edit.json";
export { E, SPRING, spr, prog, lerp, clamp01, keys } from "../v2/system";

// ---------- Grid: "Uplifting Electronic Indie", 145 BPM ----------
export const FPS = 60;
export const BAR_S = 0.4138 * 4; // seconds per bar
export const BEAT_S = 0.4138;
/** Film seconds to frames. */
export const s = (sec: number) => Math.round(sec * FPS);
/** Film bar to frames. */
export const bar = (b: number) => Math.round(b * BAR_S * FPS);
export const FILM_LEN = s((edit as any).duration);

// ---------- Type: SF Pro, the Mac's own (installed with macOS; never shipped with the film) ----------
export const SF = '"SF Pro Display", "SF Pro", -apple-system, BlinkMacSystemFont, system-ui, sans-serif';
export const SFT = '"SF Pro Text", "SF Pro", -apple-system, BlinkMacSystemFont, system-ui, sans-serif';

// ---------- Colour ----------
export const C = {
  black: "#050506",
  stage: "#0B0B0D", // the product studio
  ink: "#1D1D1F", // Apple's own near black for text on light
  paper: "#F5F5F7",
  dim: "rgba(245,245,247,0.56)",
  accent: "#0A84FF",
  dot: "#F5F5F7",
};

// ---------- Assets ----------
export const phone = (name: string) => staticFile(`v4/phone/${name}`);
export const icon = (id: string) => staticFile(`v4/icons/${id}.png`);
export const sym = (name: string) => staticFile(`v4/symbols/${name}.png`);
export const footage = (p: string) => staticFile(p);

/** Smoothstep 0..1 between a and b. */
export const sstep = (a: number, b: number, x: number) => {
  const t = Math.max(0, Math.min(1, (x - a) / (b - a)));
  return t * t * (3 - 2 * t);
};
