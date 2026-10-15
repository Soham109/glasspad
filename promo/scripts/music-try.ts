// One attempt at ElevenLabs music (official API). Caches the result; never prints the key.
import fs from "node:fs";
import path from "node:path";
import { loadKey } from "./elevenlabs.ts";
const root = path.dirname(path.dirname(new URL(import.meta.url).pathname));
const out = path.join(root, "voice/cache/music-eleven.mp3");
if (fs.existsSync(out)) { console.log("cached"); process.exit(0); }
const key = loadKey();
if (!key) { console.log("no key"); process.exit(1); }
const body = {
  prompt: "Minimal ambient electronic score for a premium product film, 120 BPM, calm and modern, warm analog pads, soft felt-piano pluck arpeggio, subtle sub pulse on every beat, no vocals, sparse and spacious, gentle build in the last 15 seconds into a resolved ending",
  music_length_ms: 70000,
  force_instrumental: true,
};
const res = await fetch("https://api.elevenlabs.io/v1/music", { method: "POST", headers: { "xi-api-key": key, "content-type": "application/json" }, body: JSON.stringify(body) });
if (!res.ok) {
  const t = (await res.text()).split(key).join("[redacted]").slice(0, 300);
  console.log(`status ${res.status}: ${t}`);
  process.exit(2);
}
fs.writeFileSync(out, Buffer.from(await res.arrayBuffer()));
console.log("generated", out);
