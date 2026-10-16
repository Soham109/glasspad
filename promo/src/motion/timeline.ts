import measured from "./vo-measured.json";
import { FPS } from "./lib";

/* The film's clock. Scenes start on bars of the score ("Uplifting Electronic Indie" by
   WinnieTheMoog, CC BY 4.0, 145 BPM, MUSIC.md), so every cut lands on a downbeat. */

export const BAR = 1.6552; // seconds
export const BEAT = BAR / 4;
export const barSec = (b: number) => b * BAR;
export const barF = (b: number) => Math.round(b * BAR * FPS);

export type SceneId = "open" | "trackpad" | "actions" | "pinned" | "modes" | "layouts" | "remote" | "present" | "displays" | "standby" | "themes" | "private" | "end";
/** [id, first bar, last bar]. */
export const SCENES: [SceneId, number, number][] = [
  ["open", 0, 4],
  ["trackpad", 4, 8],
  ["actions", 8, 13],
  ["pinned", 13, 17],
  ["modes", 17, 22],
  ["layouts", 22, 25],
  ["remote", 25, 30],
  ["present", 30, 33],
  ["displays", 33, 37],
  ["standby", 37, 40],
  ["themes", 40, 43],
  ["private", 43, 47],
  ["end", 47, 50],
];
/** The score stops at the end of bar 50; the end card holds while a short room tail rings. */
export const TAIL = 2.6;
export const FILM_SEC = barSec(50) + TAIL;
export const FILM_LEN = Math.round(FILM_SEC * FPS);
export const sceneBar = (id: SceneId) => SCENES.find(s => s[0] === id)![1];
export const sceneSec = (id: SceneId) => barSec(sceneBar(id));

/** Where each voice line starts, in seconds after its scene starts. */
export const VO_AT: Record<SceneId, number> = {
  open: 1.9, trackpad: 0.4, actions: 0.45, pinned: 0.35, modes: 0.3, layouts: 0.35, remote: 0.45,
  present: 0.3, displays: 0.35, standby: 0.45, themes: 0.35, private: 0.4, end: 1.6,
};
type Measured = Record<string, { text: string; dur: number; words: { w: string; s: number; e: number }[] }>;
export const VO = measured as Measured;
/** Absolute start of a voice line, in seconds. */
export const voSec = (id: SceneId) => sceneSec(id) + VO_AT[id];
/** Seconds after the scene starts where the n-th word matching `w` starts. */
export function word(id: SceneId, w: string, n = 0) {
  const words = VO[id].words.filter(x => x.w.toLowerCase().replace(/[^a-z0-9-]/g, "") === w.toLowerCase());
  if (!words[n]) throw new Error(`no word "${w}" in ${id}`);
  return VO_AT[id] + words[n].s;
}

/** The music edit: film bar `at` plays track bars fromBar..toBar (splices on phrase starts). */
export const MUSIC = [
  { at: 0, fromBar: 0, toBar: 17 }, // intro, then the groove on the trackpad (bar 4)
  { at: 17, fromBar: 20, toBar: 28 }, // the lift, under the modes and layouts
  { at: 25, fromBar: 52, toBar: 60 }, // the breakdown: the dark room and the stage
  { at: 33, fromBar: 60, toBar: 74 }, // the build and the second lift
  { at: 47, fromBar: 96, toBar: 99, stop: true }, // the last bars and the hard stop
];

/** A scene title's in and out (0 to 1 each): it rises as the voice line starts and leaves after. */
export function titleAt(id: SceneId, t: number, hold = 2.5) {
  const a = voSec(id) - 0.15;
  const ease = (x: number) => 1 - Math.pow(1 - Math.min(1, Math.max(0, x)), 3);
  return { p: ease((t - a) / 0.6), q: ease((t - a - 0.6 - hold) / 0.45) };
}
