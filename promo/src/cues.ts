// The audio-visual cue sheet: every sound and the frame of the visual event it belongs to.
// `probe(f)` asks the picture code itself whether the event is visible at frame f; scripts/verify-sync.ts
// uses it to find the picture's event frame independently of the cue's own number.
import { S, FILM_STROKES, TEASER_STROKES, Stroke, T, TEASER_MODES, FILM_LEN, TEASER_LEN } from "./timeline";
import { fingersAt, ripplesAt, swipeProgress, swipeLand } from "./film/choreo";
import { FILM_OPEN } from "./film/ColdOpen";
import { TEASER_OPEN } from "./film/teaserDirector";
import { MENU } from "./scenes/Modes";
import { DOCK, KEYS, MEDIA, DECK, MACROS, CLIP, PRESENT, tapFx, keysTimes } from "./screens/Modes";
import { SETTINGS_EVENTS } from "./scenes/Settings";
import { PRIV } from "./scenes/Privacy";
import { END } from "./scenes/End";

export type CueKind = "touch" | "click" | "haptic" | "snap" | "key" | "pop" | "air" | "chime" | "thump" | "tick";
export type Cue = { f: number; kind: CueKind; gain: number; pan: number; label: string; probe?: (f: number) => boolean };

const firstTouch = (strokes: Stroke[], s: Extract<Stroke, { down: number }>) => {
  for (let f = s.down; f < s.down + 20; f++) if (fingersAt([s], f).some((x) => x.o >= 0.5)) return f;
  return s.down;
};
const touchProbe = (s: Extract<Stroke, { down: number }>) => (f: number) => fingersAt([s], f).some((x) => x.o >= 0.5);
const rippleProbe = (strokes: Stroke[], x: number, y: number) => (f: number) => ripplesAt(strokes, f).some((r) => r.age === 0 && r.x === x && r.y === y);
const modeTap = (base: number, at: number, x = 0, y = 0) => (f: number) => tapFx(f - base, at, x, y).r.some((r) => r.age === 0);

const setupCues = (strokes: Stroke[], c: Cue[]) => {
  for (const s of strokes) {
    if (s.kind === "tap") c.push({ f: s.at, kind: s.strong ? "haptic" : "click", gain: s.strong ? 0.9 : 0.75, pan: 0.15, label: `tap: ${s.label}`, probe: rippleProbe(strokes, s.x, s.y) });
    else {
      c.push({ f: firstTouch(strokes, s), kind: "touch", gain: s.kind === "move" ? 0.45 : 0.4, pan: 0.15, label: `${s.kind} touch down`, probe: touchProbe(s) });
      if (s.kind === "swipe") {
        const land = swipeLand(s);
        c.push({ f: land, kind: s.target === "space" ? "snap" : "air", gain: s.target === "space" ? 0.7 : 0.25, pan: 0, label: `${s.target} lands`, probe: (f) => swipeProgress(s, f) >= 0.999 });
      }
    }
  }
};

const openCues = (t: typeof FILM_OPEN, c: Cue[]) => {
  t.glides.forEach((g, i) => c.push({ f: g.down, kind: "touch", gain: 0.8, pan: 0, label: `icon dot ${i + 1} lands`, probe: (f) => f >= g.down }));
  c.push({ f: t.pull[0] + 20, kind: "air", gain: 0.3, pan: 0, label: "pull back to the icon" });
  c.push({ f: t.morph[0] + 10, kind: "air", gain: 0.35, pan: 0, label: "icon becomes the phone" });
};

const modeCues = (c: Cue[], at: number[], count: number) => {
  const m = (i: number) => at[i];
  if (count > 0) {
    c.push({ f: m(0) + DOCK.tapNotes, kind: "click", gain: 0.7, pan: -0.3, label: "dock: tap Notes", probe: modeTap(m(0), DOCK.tapNotes) });
    c.push({ f: m(0) + DOCK.open, kind: "pop", gain: 0.35, pan: 0.3, label: "dock: Notes opens on the Mac" });
  }
  if (count > 1) {
    c.push({ f: m(1), kind: "air", gain: 0.3, pan: 0, label: "phone turns upright" });
    keysTimes().forEach((t, i) => { if (t < at[2] - at[1] || count === 2) c.push({ f: m(1) + t, kind: "key", gain: 0.35, pan: -0.3, label: `keys: key ${i + 1}`, probe: i === 0 ? (f) => f - m(1) >= KEYS.start : undefined }); });
  }
  if (count > 2) c.push({ f: m(2) + MEDIA.touch, kind: "touch", gain: 0.5, pan: -0.3, label: "media: touch volume", probe: (f) => f - m(2) >= MEDIA.touch });
  if (count > 3) {
    c.push({ f: m(3) + DECK.tap, kind: "click", gain: 0.7, pan: -0.3, label: "deck: Do Not Disturb", probe: modeTap(m(3), DECK.tap) });
    c.push({ f: m(3) + DECK.tap + 6, kind: "pop", gain: 0.3, pan: 0.3, label: "deck: done" });
  }
  if (count > 4) {
    c.push({ f: m(4) + MACROS.tap, kind: "click", gain: 0.7, pan: -0.3, label: "macros: Reopen Closed Tab", probe: modeTap(m(4), MACROS.tap) });
    c.push({ f: m(4) + MACROS.switchApp, kind: "air", gain: 0.3, pan: 0.3, label: "macros: front app changes" });
  }
  if (count > 5) c.push({ f: m(5) + CLIP.tap, kind: "click", gain: 0.7, pan: -0.3, label: "clipboard: Get Mac clipboard", probe: modeTap(m(5), CLIP.tap) });
  if (count > 6) {
    c.push({ f: m(6) + PRESENT.next, kind: "click", gain: 0.75, pan: -0.3, label: "present: Next", probe: modeTap(m(6), PRESENT.next) });
    c.push({ f: m(6) + PRESENT.padDown, kind: "touch", gain: 0.45, pan: -0.3, label: "present: laser" });
  }
};

export const buildFilmCues = (): Cue[] => {
  const c: Cue[] = [];
  openCues(FILM_OPEN, c);
  c.push({ f: 548, kind: "air", gain: 0.35, pan: 0, label: "pull back: the Mac appears" });
  setupCues(FILM_STROKES, c);
  c.push({ f: 800, kind: "air", gain: 0.25, pan: 0, label: "match cut", probe: (f) => f >= 800 });
  for (const cut of [S.speed, S.spaces, S.mission, S.settings, S.menu, S.privacy]) c.push({ f: cut, kind: "air", gain: 0.22, pan: 0, label: `cut ${cut}` });
  for (let i = 0; i < 30; i++) c.push({ f: S.speed + 26 + Math.round((i * 10 * 96) / 300), kind: "tick", gain: 0.12, pan: -0.6 + (1.2 * i) / 30, label: "update tick" });
  const se = SETTINGS_EVENTS(S.settings);
  c.push({ f: se.toggleClick, kind: "click", gain: 0.45, pan: -0.4, label: "settings: toggle on the Mac" });
  c.push({ f: se.pulseArrive, kind: "pop", gain: 0.35, pan: 0.4, label: "settings: phone follows" });
  for (let f = se.dragStart; f < se.dragEnd; f += 9) c.push({ f, kind: "tick", gain: 0.1, pan: -0.3, label: "settings: slider detent" });
  c.push({ f: S.menu + MENU.touchTop, kind: "touch", gain: 0.4, pan: 0, label: "menu: touch the top", probe: (f) => tapFx(f - S.menu, MENU.touchTop, 0, 0).r.some((r) => r.age === 0) });
  c.push({ f: S.menu + MENU.tapPill, kind: "click", gain: 0.65, pan: 0, label: "menu: tap the pill", probe: modeTap(S.menu, MENU.tapPill) });
  c.push({ f: S.menu + MENU.tapPill + 4, kind: "pop", gain: 0.3, pan: 0, label: "menu opens" });
  c.push({ f: S.menu + MENU.tapDock, kind: "click", gain: 0.65, pan: 0, label: "menu: tap Dock", probe: modeTap(S.menu, MENU.tapDock) });
  modeCues(c, [S.dock, S.keys, S.media, S.deck, S.macros, S.clipboard, S.present], 7);
  const pv = PRIV(S.privacy);
  c.push({ f: pv.paired, kind: "chime", gain: 0.45, pan: 0, label: "privacy: paired" });
  for (let f = pv.packets; f < S.end - 20; f += 13) c.push({ f, kind: "tick", gain: 0.06, pan: -0.2, label: "packet" });
  const e = END(S.end);
  c.push({ f: e.drop, kind: "thump", gain: 0.55, pan: 0, label: "end: paper dot lands", probe: (f) => f >= e.drop });
  c.push({ f: e.iconTap, kind: "touch", gain: 0.7, pan: 0, label: "end: icon dot lands", probe: (f) => f >= e.iconTap });
  return c.filter((x) => x.f >= 0 && x.f < FILM_LEN).sort((a, b) => a.f - b.f);
};

export const buildTeaserCues = (): Cue[] => {
  const c: Cue[] = [];
  openCues(TEASER_OPEN, c);
  c.push({ f: 360, kind: "air", gain: 0.35, pan: 0, label: "pull back: the Mac appears" });
  setupCues(TEASER_STROKES, c);
  for (const cut of [T.scroll, T.spaces, T.modes]) c.push({ f: cut, kind: "air", gain: 0.22, pan: 0, label: `cut ${cut}` });
  modeCues(c, TEASER_MODES, 4);
  const e = END(T.end);
  c.push({ f: e.drop, kind: "thump", gain: 0.55, pan: 0, label: "end: paper dot lands", probe: (f) => f >= e.drop });
  c.push({ f: e.iconTap, kind: "touch", gain: 0.7, pan: 0, label: "end: icon dot lands", probe: (f) => f >= e.iconTap });
  return c.filter((x) => x.f >= 0 && x.f < TEASER_LEN).sort((a, b) => a.f - b.f);
};
