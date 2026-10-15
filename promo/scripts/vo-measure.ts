// Synthesises (cached) and measures every VO line, before placement. Prints seconds per line.
import { execFileSync } from "node:child_process";
import { loadKey, tts, totalUsage } from "./elevenlabs.ts";
import { VO_TEXT, VO_MODEL, VO_SETTINGS, VO_VOICE } from "../src/voScript.ts";
const key = loadKey();
let total = 0;
for (const l of VO_TEXT) {
  const r = await tts(key, VO_VOICE.id, VO_MODEL, l.text, VO_SETTINGS);
  const d = Number(execFileSync("ffprobe", ["-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", r.file]).toString());
  total += d;
  console.log(`${l.id.padEnd(10)} ${d.toFixed(2)}s ${(d * 60).toFixed(0).padStart(4)}fr  ${l.text}`);
}
console.log(`total ${total.toFixed(1)} s; usage ${JSON.stringify(totalUsage())}`);
