// Renders line 1 with candidate voices into out/vo-samples/ (cached; small usage). Never prints the key.
import fs from "node:fs";
import path from "node:path";
import { loadKey, tts, totalUsage } from "./elevenlabs.ts";
import { VO_TEXT, VO_MODEL, VO_SETTINGS } from "../src/voScript.ts";
const root = path.dirname(path.dirname(new URL(import.meta.url).pathname));
const CANDIDATES = [
  ["SAz9YHcvj6GT2YYXdXww", "river"],
  ["cjVigY5qzO86Huf0OWal", "eric"],
  ["onwK4e9ZLuTAKqWW03F9", "daniel"],
  ["EXAVITQu4vr4xnSDxMaL", "sarah"],
];
const out = path.join(root, "out/vo-samples");
fs.mkdirSync(out, { recursive: true });
const key = loadKey();
for (const [id, name] of CANDIDATES) {
  const r = await tts(key, id, VO_MODEL, VO_TEXT[0].text, VO_SETTINGS);
  fs.copyFileSync(r.file, path.join(out, `${name}.mp3`));
  console.log(`${name}: ${r.cached ? "cached" : "generated"}`);
}
console.log("usage", JSON.stringify(totalUsage()));
