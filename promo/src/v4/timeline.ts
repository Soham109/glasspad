// Scene and voice timing, from edit.json (the same file the mix reads) and the measured voice.
import edit from "./edit.json";
import measured from "./vo-measured.json";
import { BAR_S, FPS } from "./core";

type Scene = { id: string; from: number; to: number };
const SCENES = (edit as any).scenes as Scene[];
const M = measured as Record<string, { dur: number; words: { w: string; s: number; e: number }[] }>;

/** Scene start and end in film seconds. */
export const scene = (id: string) => {
  const sc = SCENES.find((x) => x.id === id);
  if (!sc) throw new Error(`no scene ${id}`);
  return { from: sc.from * BAR_S, to: sc.to * BAR_S, len: (sc.to - sc.from) * BAR_S };
};
/** Scene start and end in frames. */
export const sceneF = (id: string) => {
  const sc = scene(id);
  return { from: Math.round(sc.from * FPS), to: Math.round(sc.to * FPS), len: Math.round(sc.to * FPS) - Math.round(sc.from * FPS) };
};

export const lineAt = (id: string) => {
  const v = (edit as any).vo.find((x: any) => x.id === id);
  if (!v) throw new Error(`no line ${id}`);
  return v.at as number;
};
/** Film seconds when word i (0 based) of line id starts. */
export const word = (id: string, i: number) => lineAt(id) + M[id].words[i].s;
export const wordEnd = (id: string, i: number) => lineAt(id) + M[id].words[i].e;
export const lineEnd = (id: string) => lineAt(id) + M[id].dur;

/** Film seconds of a scene's local time (seconds from its start). */
export const at = (id: string, sec: number) => scene(id).from + sec;
/** Local frame (inside a scene's Sequence) of a film second. */
export const local = (id: string, filmSec: number) => Math.round((filmSec - scene(id).from) * FPS);
