// The motion film's edit for the mix: length, the music cut, where each voice line starts, and
// the picture's sound cues (taps, keys, whooshes), read from the scene timings themselves so
// the sound always lands on the frame where the thing happens. Writes src/motion/edit.json.
//   pnpm motion:cues
import fs from "node:fs";
import path from "node:path";
import { BAR, FILM_SEC, MUSIC, SCENES, voSec } from "../../src/motion/timeline";
import { DESK_CUES } from "../../src/motion/scenes/Desk";
import { MODES_CUES } from "../../src/motion/scenes/DeskPhone";
import { COUCH_CUES } from "../../src/motion/scenes/Couch";
import { NIGHT_CUES } from "../../src/motion/scenes/Night";
import { THEMES_CUES } from "../../src/motion/scenes/Themes";
import { FINALE_CUES } from "../../src/motion/scenes/Finale";

type Cues = Record<string, (number | [number, number])[]>;
const all: Cues = {};
for (const c of [DESK_CUES(), MODES_CUES(), COUCH_CUES(), NIGHT_CUES(), THEMES_CUES(), FINALE_CUES()] as Cues[]) {
  for (const [k, v] of Object.entries(c)) all[k] = [...(all[k] ?? []), ...v];
}
const round = (x: number) => Math.round(x * 1000) / 1000;
for (const k of Object.keys(all)) all[k] = all[k].map(v => (Array.isArray(v) ? [round(v[0]), round(v[1])] : round(v))).sort((a, b) => (Array.isArray(a) ? a[0] : a) - (Array.isArray(b) ? b[0] : b)) as Cues[string];
const edit = {
  duration: round(FILM_SEC),
  bar: BAR,
  grid: { offset: 0.431, bar: BAR },
  music: MUSIC,
  vo: SCENES.map(([id]) => ({ id, at: round(voSec(id)) })),
  cues: all,
};
const out = path.join(path.dirname(new URL(import.meta.url).pathname), "../../src/motion/edit.json");
fs.writeFileSync(path.resolve(out), JSON.stringify(edit, null, 1) + "\n");
console.log(`edit.json: ${edit.duration}s, ${edit.vo.length} voice lines, ${Object.values(all).reduce((n, v) => n + v.length, 0)} cues`);
