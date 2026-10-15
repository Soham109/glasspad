// Voiceover: ElevenLabs (cached by input hash; the key is read from promo/.env and never printed).
// Each line: trim edge silence, high-pass, gentle compression, a touch of presence, loudness-matched.
// Then placed on the timeline. Outputs public/vo-film.wav + public/vo-lines.json, public/vo-teaser.wav + public/vo-teaser-lines.json.
import fs from "node:fs";
import path from "node:path";
import { execFileSync } from "node:child_process";
import { loadKey, tts, totalUsage } from "./elevenlabs.ts";
import { VO_TEXT, VO_MODEL, VO_SETTINGS, VO_VOICE } from "../src/voScript.ts";
import { FILM_LEN, TEASER_LEN, FPS, VO_AT, TEASER_VO_AT } from "../src/timeline.ts";

const root = path.dirname(path.dirname(new URL(import.meta.url).pathname));
const tmp = path.join(root, "voice/work");
fs.mkdirSync(tmp, { recursive: true });
const ff = (...a: string[]) => execFileSync("ffmpeg", ["-loglevel", "error", "-y", ...a]);
const dur = (f: string) => Number(execFileSync("ffprobe", ["-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", f]).toString());
const key = loadKey();

const processed: Record<string, { file: string; seconds: number; text: string }> = {};
for (const line of VO_TEXT) {
  const r = await tts(key, VO_VOICE.id, VO_MODEL, line.text, VO_SETTINGS);
  const raw = path.join(tmp, `raw-${line.id}.wav`), proc = path.join(tmp, `line-${line.id}.wav`);
  ff("-i", r.file, "-ar", "48000", "-ac", "1", raw);
  ff("-i", raw, "-af", [
    "silenceremove=start_periods=1:start_threshold=-50dB:start_silence=0.02",
    "areverse,silenceremove=start_periods=1:start_threshold=-50dB:start_silence=0.08,areverse",
    "highpass=f=80",
    "equalizer=f=230:t=q:w=1.2:g=-1.5",
    "equalizer=f=4200:t=q:w=1.5:g=1.2",
    "deesser=i=0.3",
    "acompressor=threshold=-20dB:ratio=2.5:attack=8:release=160:makeup=2",
    "loudnorm=I=-18:TP=-2:LRA=7",
  ].join(","), "-ar", "48000", "-ac", "1", proc);
  processed[line.id] = { file: proc, seconds: dur(proc), text: line.text };
}

const place = (at: Record<string, number>, len: number, out: string, json: string) => {
  const ids = Object.keys(at).sort((a, b) => at[a] - at[b]);
  ids.forEach((id, i) => {
    const end = at[id] / FPS + processed[id].seconds, next = ids[i + 1];
    if (next && end > at[next] / FPS - 0.2) console.warn(`warning: "${id}" ends at ${end.toFixed(2)} s, "${next}" starts ${(at[next] / FPS).toFixed(2)} s`);
  });
  const inputs = ids.flatMap((id) => ["-i", processed[id].file]);
  const delays = ids.map((id, i) => `[${i}:a]adelay=${Math.round((at[id] / FPS) * 1000)}:all=1[v${i}]`).join(";");
  const mixIn = ids.map((_, i) => `[v${i}]`).join("");
  ff(...inputs, "-filter_complex", `${delays};${mixIn}amix=inputs=${ids.length}:normalize=0,apad,atrim=0:${len / FPS},pan=stereo|c0=c0|c1=c0[out]`, "-map", "[out]", "-ar", "44100", "-c:a", "pcm_s16le", path.join(root, out));
  fs.writeFileSync(path.join(root, json), JSON.stringify({ engine: `ElevenLabs ${VO_VOICE.name} / ${VO_MODEL}`, lines: ids.map((id) => ({ id, f: at[id], text: processed[id].text, seconds: +processed[id].seconds.toFixed(2) })) }, null, 2));
  for (const id of ids) console.log(`  ${String(at[id]).padStart(5)}  ${processed[id].seconds.toFixed(2)}s  ends ${(at[id] + processed[id].seconds * FPS).toFixed(0).padStart(5)}  ${processed[id].text}`);
};
console.log("film"); place(VO_AT, FILM_LEN, "public/vo-film.wav", "public/vo-lines.json");
console.log("teaser"); place(TEASER_VO_AT, TEASER_LEN, "public/vo-teaser.wav", "public/vo-teaser-lines.json");
console.log("elevenlabs usage so far", JSON.stringify(totalUsage()));
