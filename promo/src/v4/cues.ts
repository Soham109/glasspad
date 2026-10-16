// Every sound cue in film seconds, gathered from the scenes so picture and sound share one
// source. `pnpm v4:cues` writes them to src/v4/cues.json for scripts/v4/mix.py.
import { MORNING_CUES } from "./scenes/Morning";
import { WORK_CUES } from "./scenes/Work";
import { HOME_CUES } from "./scenes/Home";
import { FINALE_CUES } from "./scenes/Finale";

type Cues = Record<string, (number | number[])[]>;
export const ALL_CUES = (() => {
  const out: Cues = {};
  for (const c of [MORNING_CUES, WORK_CUES, HOME_CUES, FINALE_CUES] as Cues[]) {
    for (const [k, v] of Object.entries(c)) out[k] = [...(out[k] ?? []), ...v];
  }
  return out;
})();
