// Writes src/v4/cues.json (sound cues in film seconds) from the scenes. Run: pnpm v4:cues
import { writeFileSync } from "node:fs";
import { ALL_CUES } from "../../src/v4/cues";
writeFileSync(new URL("../../src/v4/cues.json", import.meta.url), JSON.stringify(ALL_CUES, null, 1));
console.log(Object.entries(ALL_CUES).map(([k, v]) => `${k}: ${v.length}`).join(", "));
