// Spoken word times in film seconds, from the placed voice lines (edit.json) and the
// measured alignment (vo-measured.json). Picture cues read these, so a retimed line moves
// its cues with it.
import edit from "./edit.json";
import measured from "./vo-measured.json";

type Cut = "film" | "teaser";
const M = measured as Record<string, { dur: number; words: { w: string; s: number; e: number }[] }>;

export const lineAt = (id: string, cut: Cut = "film") => {
  const v = (edit as any)[cut].vo.find((x: any) => x.id === id);
  if (!v) throw new Error(`no line ${id} in ${cut}`);
  return v.at as number;
};
/** Start of word `i` (0 based) of line `id`, in seconds. */
export const word = (id: string, i: number, cut: Cut = "film") => lineAt(id, cut) + M[id].words[i].s;
/** End of line `id`. */
export const lineEnd = (id: string, cut: Cut = "film") => lineAt(id, cut) + M[id].dur;
/** Every word start of a line, in seconds. */
export const words = (id: string, cut: Cut = "film") => M[id].words.map((w) => lineAt(id, cut) + w.s);
