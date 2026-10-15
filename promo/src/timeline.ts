// The edit, as data. 60 fps, 90 BPM: one beat = 40 frames, one bar = 160 frames. Cuts land on beats.
// Shared by the picture, the captions, scripts/mix.ts (sound) and scripts/verify-sync.ts. No React here.
export const FPS = 60;
export const BEAT = 40;
export const BAR = 160;

export const S = {
  open: 0, // a finger dot glides; the camera pulls back to the app icon
  morph: 440, // the icon's surface becomes the phone's screen
  setup: 520, // pull back: the phone lies in front of a MacBook
  move: 680, // push in: one finger moves the pointer; match cut to the Mac
  click: 920, // tap to click, the window behind comes forward; a close tap you can feel
  scroll: 1120, // two finger scroll with momentum
  speed: 1320, // measured facts, typographic
  spaces: 1560, // three finger swipe between Spaces, following the fingers
  mission: 1800, // three fingers up: Mission Control
  settings: 2000, // the Mac's own trackpad settings, mirrored
  menu: 2360, // the mode pill and menu
  dock: 2560,
  keys: 2720,
  media: 2880,
  deck: 3040,
  macros: 3200,
  clipboard: 3360,
  present: 3520,
  privacy: 3680, // QR pairing, encryption, your network, no accounts
  end: 4120, // free and open source
};
export const FILM_LEN = 4480;

// VO start frames (each on a beat or half beat). Lines are measured by scripts/make-voice.ts.
export const VO_AT: Record<string, number> = {
  intro: 200, lay: 560, move: 760, click: 960, scroll: 1160, speed: 1360, spaces: 1600, mission: 1840,
  settings: 2040, menu: 2400, dock: 2580, keys: 2740, media: 2900, deck: 3060, macros: 3220, clipboard: 3380,
  present: 3540, pair: 3720, encrypt: 3840, local: 3960, end: 4200,
};

export type P = [number, number];
/** Phone gestures in landscape screen points (874 x 402). down: finger lands; ms/me: moving; up: lift starts. */
export type Stroke =
  | { kind: "move"; down: number; ms: number; me: number; up: number; a: P; b: P; k: number }
  | { kind: "tap"; at: number; x: number; y: number; strong?: boolean; label: string }
  | { kind: "scroll"; down: number; ms: number; me: number; up: number; pts: P[]; dy: number }
  | { kind: "swipe"; target: "space" | "mission"; down: number; ms: number; me: number; up: number; pts: P[]; dx: number; dy: number };

export const FILM_STROKES: Stroke[] = [
  { kind: "move", down: 720, ms: 730, me: 890, up: 890, a: [180, 320], b: [680, 110], k: -60 },
  { kind: "tap", at: 980, x: 690, y: 122, label: "click: window comes forward" },
  { kind: "tap", at: 1068, x: 470, y: 215, strong: true, label: "click: close up" },
  { kind: "scroll", down: 1176, ms: 1184, me: 1232, up: 1232, pts: [[400, 300], [490, 308]], dy: -190 },
  { kind: "swipe", target: "space", down: 1604, ms: 1612, me: 1680, up: 1680, pts: [[530, 222], [650, 200], [770, 226]], dx: -400, dy: 0 },
  { kind: "swipe", target: "mission", down: 1846, ms: 1854, me: 1900, up: 1900, pts: [[320, 330], [437, 312], [554, 334]], dx: 0, dy: -200 },
];
export const CURSOR0: P = [560, 640]; // pointer start, display points

// Vertical teaser: 25 s.
export const T = {
  open: 0,
  morph: 252,
  setup: 330,
  scroll: 560,
  spaces: 720,
  modes: 920, // dock, keys, media, deck: 80 frames each
  end: 1280,
};
export const TEASER_MODES = [920, 1010, 1100, 1190];
export const TEASER_LEN = 1500;
export const TEASER_VO_AT: Record<string, number> = { intro: 340, end: 1340 };
export const TEASER_STROKES: Stroke[] = [
  { kind: "move", down: 400, ms: 410, me: 500, up: 500, a: [200, 300], b: [660, 120], k: -50 },
  { kind: "tap", at: 530, x: 668, y: 128, label: "click: window comes forward" },
  { kind: "scroll", down: 584, ms: 592, me: 640, up: 640, pts: [[400, 300], [490, 308]], dy: -190 },
  { kind: "swipe", target: "space", down: 744, ms: 752, me: 820, up: 820, pts: [[530, 222], [650, 200], [770, 226]], dx: -400, dy: 0 },
];
