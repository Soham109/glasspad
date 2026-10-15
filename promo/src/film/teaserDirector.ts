// Vertical teaser: the same setup, framed for 1080 x 1920.
import { T, TEASER_STROKES } from "../timeline";
import { Cam, Key, camAt } from "./camera";
import { fingersAt, desktopAt } from "./choreo";
import { shakeAt } from "./director";
import { prog, minJerk, clamp } from "../motion";
import { ColdOpenTiming } from "./ColdOpen";
import { Cap } from "../Captions";

export const V_PHONE: Cam = { x: 540, y: 1390, z: 1.5 };
export const V_WIDE: Cam = { x: 540, y: 900, z: 1.0 };
export const TEASER_CAM: Key[] = [
  { f: 0, cam: V_PHONE },
  { f: 352, cam: V_WIDE, move: 100 },
  { f: 452, cam: { ...V_WIDE, z: 1.04 }, move: 100 },
  { f: T.scroll, cam: { x: 540, y: 880, z: 1.08 } },
  { f: T.scroll + 6, cam: { x: 540, y: 880, z: 1.12 }, move: 150 },
  { f: T.spaces, cam: V_WIDE },
  { f: T.spaces + 6, cam: { ...V_WIDE, z: 1.06 }, move: 190 },
];
export const teaserTilt = (f: number) => (f < 352 ? 0 : 52 * minJerk((f - 352) / 92));
export const teaserSetupState = (f: number) => ({
  cam: camAt(TEASER_CAM, f),
  tilt: teaserTilt(f),
  fingers: fingersAt(TEASER_STROKES, f),
  desk: desktopAt(TEASER_STROKES, f),
  macO: prog(f, 366, 64) * clamp(teaserTilt(f) / 26),
  macRise: (1 - prog(f, 366, 80)) * 70,
  deskO: prog(f, 352, 90),
  body: clamp((f - 296) / 30),
  shake: shakeAt(TEASER_STROKES, f),
});
export const TEASER_OPEN: ColdOpenTiming = {
  glides: [
    { down: 20, ms: 26, me: 80, a: [540, 330], b: [470, 690], k: 70, liftAt: 96 },
    { down: 104, ms: 110, me: 172, a: [300, 610], b: [660, 440], k: 0 },
  ],
  focus0: [505, 512],
  pull: [104, 200],
  word: 186,
  tag: 210,
  exit: 244,
  morph: [252, 334],
  zFrom: 3.4,
  zTo: 0.44,
  center: [540, 700],
};
const X = 90, Y = 200, SZ = 96;
export const TEASER_CAPS: Cap[] = [
  { at: 452, out: 552, title: "Move. Click.", sub: "A small tap answers every click.", x: X, y: Y, size: SZ, maxW: 900 },
  { at: 576, out: 704, title: "Scroll.", sub: "Two fingers, with momentum.", x: X, y: Y, size: SZ, maxW: 900 },
  { at: 736, out: 900, title: "Spaces.", sub: "The screen follows your hand.", x: X, y: Y, size: SZ, maxW: 900 },
];
