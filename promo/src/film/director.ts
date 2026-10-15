// Film director for the setup scene: camera, phone tilt and reveals, as functions of the frame.
import { S, FILM_STROKES, Stroke } from "../timeline";
import { Cam, Key, camAt, toScreen } from "./camera";
import { FILM_LAYOUT as L, geom, phoneToWorld, dispToWorld } from "./layout";
import { fingersAt, desktopAt, GAIN } from "./choreo";
import { prog, lerp, minJerk, clamp } from "../motion";

export const PHONE_TOP: Cam = { x: 960, y: 896, z: 2.6 };
export const WIDE: Cam = { x: 800, y: 515, z: 1.1 };
export const CENTER: Cam = { x: 960, y: 520, z: 1.18 };
const MATCH = 800; // the match cut: finger dot on the phone -> pointer on the Mac

/** Camera for the Mac close-up, solved so the pointer lands exactly where the finger dot was, moving at the same speed. */
export const macClose = (): Cam => {
  const g = geom(L);
  const fz = PHONE_TOP.z;
  const zB = (g.scr.s * fz) / (GAIN * g.disp.s);
  const fin = fingersAt(FILM_STROKES, MATCH)[0];
  const dotScreen = toScreen(PHONE_TOP, L.W, L.H, ...phoneToWorld(L, fin.x, fin.y));
  const cur = desktopAt(FILM_STROKES, MATCH).cursor;
  // aim at the pointer's hotspot plus half the dot, so the two read as the same mark
  const pw = dispToWorld(L, cur.x + 5, cur.y + 9);
  return { x: pw[0] - (dotScreen[0] - L.W / 2) / zB, y: pw[1] - (dotScreen[1] - L.H / 2) / zB, z: zB };
};

const tapAt = (label: string) => FILM_STROKES.find((s): s is Extract<Stroke, { kind: "tap" }> => s.kind === "tap" && s.label.includes(label))!;

export const FILM_CAM: Key[] = (() => {
  const close = tapAt("close up");
  const [tx] = phoneToWorld(L, close.x, close.y);
  return [
    { f: 0, cam: PHONE_TOP },
    { f: 540, cam: WIDE, move: 112 },
    { f: 676, cam: PHONE_TOP, move: 42 },
    { f: 718, cam: { ...PHONE_TOP, z: 2.66 }, move: 82 },
    { f: MATCH, cam: macClose() },
    { f: 812, cam: { ...macClose(), z: macClose().z * 1.02 }, move: 38 },
    { f: 852, cam: WIDE, move: 64 },
    { f: 1002, cam: { x: lerp(960, tx, 0.3), y: 900, z: 2.6 }, move: 44 },
    { f: 1046, cam: { x: lerp(960, tx, 0.3), y: 900, z: 2.66 }, move: 70 },
    { f: S.scroll, cam: CENTER },
    { f: S.scroll + 6, cam: { ...CENTER, z: 1.24 }, move: 194 },
    { f: S.spaces, cam: WIDE },
    { f: S.spaces + 6, cam: { x: 800, y: 530, z: 1.05 }, move: 230 },
    { f: S.mission, cam: { x: 930, y: 470, z: 1.2 } },
    { f: S.mission + 6, cam: { x: 935, y: 460, z: 1.27 }, move: 190 },
  ];
})();

export const filmTilt = (f: number) => {
  if (f < 540) return 0;
  if (f < 676) return 52 * minJerk((f - 540) / 100);
  if (f < MATCH) return 52 * (1 - minJerk((f - 676) / 40));
  if (f < 1002) return 52;
  if (f < S.scroll) return 52 * (1 - minJerk((f - 1002) / 42));
  return 52;
};

const SHAKE_STRONG = [0, 1.7, -1.4, 1.05, -0.7, 0.4, -0.18, 0];
const SHAKE_SOFT = [0, 0.7, -0.5, 0.25, 0];
export const shakeAt = (strokes: Stroke[], f: number) => {
  for (const s of strokes) if (s.kind === "tap") {
    const k = f - s.at, arr = s.strong ? SHAKE_STRONG : SHAKE_SOFT;
    if (k >= 0 && k < arr.length) return arr[k];
  }
  return 0;
};

export const filmSetupState = (f: number) => ({
  cam: camAt(FILM_CAM, f),
  tilt: filmTilt(f),
  fingers: fingersAt(FILM_STROKES, f),
  desk: desktopAt(FILM_STROKES, f),
  // the Mac is a front view; it gives way while the camera is overhead the phone
  macO: prog(f, 556, 70) * clamp(filmTilt(f) / 26),
  macRise: (1 - prog(f, 556, 84)) * 70,
  deskO: prog(f, 540, 90),
  body: clamp((f - 486) / 30),
  shake: shakeAt(FILM_STROKES, f),
});
export { MATCH };
