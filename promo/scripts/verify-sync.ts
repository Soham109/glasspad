// Sync check, three ways:
//  1. sound: each verified cue's transient onset in the rendered SFX (or a final MP4's audio) vs the cue frame;
//  2. picture: the frame where the picture code itself shows the event (cue.probe) vs the cue frame;
//  3. words: VO speech onset in the VO stem vs its timeline frame, and each caption's entry vs its VO line.
// usage: node voice/work/verify-sync.mjs [audio file to check, default out/stems/sfx.wav]
import fs from "node:fs";
import { execFileSync } from "node:child_process";
import { buildFilmCues } from "../src/cues";
import { FPS, VO_AT } from "../src/timeline";
import { FILM_CAPS } from "../src/film/captions";

const SR = 44100;
const file = process.argv[2] ?? "out/stems/sfx.wav";
const mono = (f: string, hp = 0) => {
  const tmp = `voice/work/verify-${f.replace(/\W/g, "_")}-${hp}.raw`;
  execFileSync("ffmpeg", ["-loglevel", "error", "-y", "-i", f, "-ac", "1", "-ar", String(SR), ...(hp ? ["-af", `highpass=f=${hp}`] : []), "-f", "f32le", tmp]);
  const b = fs.readFileSync(tmp);
  return new Float32Array(b.buffer, b.byteOffset, b.length / 4);
};
const envMs = (x: Float32Array) => {
  const e = new Float32Array(Math.floor((x.length / SR) * 1000));
  for (let i = 0; i < e.length; i++) { const a = Math.floor((i * SR) / 1000), b = Math.floor(((i + 1) * SR) / 1000); let s = 0; for (let k = a; k < b; k++) s += x[k] ** 2; e[i] = Math.sqrt(s / (b - a)); }
  return e;
};
// in a full mix the music masks low transients: listen above 1.5 kHz, where the clicks live
const env = envMs(mono(file, file.endsWith(".mp4") ? 1500 : 0));
const ms = (f: number) => Math.round((f / FPS) * 1000);
const onset = (f: number) => {
  const a = ms(f) - 40, b = ms(f) + 60;
  let base = 0, n = 0;
  for (let i = a - 60; i < a; i++) if (i >= 0) { base += env[i]; n++; }
  base /= Math.max(1, n);
  let peak = 0; for (let i = a; i <= b && i < env.length; i++) peak = Math.max(peak, env[i]);
  const thr = base + 0.3 * (peak - base);
  for (let i = a; i <= b; i++) if (env[i] >= thr) return i;
  return NaN;
};

let worstA = 0, worstV = 0;
const rows: string[] = [];
for (const c of buildFilmCues().filter((c) => c.probe)) {
  const aOff = c.kind === "air" ? 0 : (onset(c.f) / 1000) * FPS - c.f;
  let v = NaN;
  for (let g = c.f - 15; g <= c.f + 15; g++) if (c.probe!(g)) { v = g; break; }
  const vOff = v - c.f;
  if (Number.isFinite(aOff)) worstA = Math.max(worstA, Math.abs(aOff));
  if (Number.isFinite(vOff)) worstV = Math.max(worstV, Math.abs(vOff));
  rows.push(`${String(c.f).padStart(5)}  ${c.kind.padEnd(6)} ${c.label.padEnd(36)} sound ${c.kind === "air" ? "  (swell)" : (aOff >= 0 ? "+" : "") + aOff.toFixed(2) + " fr"}   picture ${Number.isFinite(vOff) ? (vOff >= 0 ? "+" : "") + vOff + " fr" : "not found"}`);
}
console.log(rows.join("\n"));
console.log(`\nsound: max |transient - cue| = ${worstA.toFixed(2)} frames (${((worstA / FPS) * 1000).toFixed(1)} ms)`);
console.log(`picture: max |event - cue| = ${worstV} frames`);

if (!file.endsWith(".mp4") && fs.existsSync("out/stems/vo.wav")) {
  const v = mono("out/stems/vo.wav");
  let worst = 0;
  for (const [id, f] of Object.entries(VO_AT)) {
    const a = Math.round((f / FPS) * SR);
    let i = a - Math.round(SR * 0.2);
    while (i < a + SR * 0.5 && Math.abs(v[i]) < 0.01) i++;
    worst = Math.max(worst, Math.abs(((i - a) / SR) * FPS));
    void id;
  }
  console.log(`VO: max |speech onset - timeline frame| = ${worst.toFixed(2)} frames`);
  const vo = JSON.parse(fs.readFileSync("public/vo-lines.json", "utf8")) as { lines: Array<{ f: number; seconds: number; text: string }> };
  let capWorst = 0;
  const capRows: string[] = [];
  for (const c of FILM_CAPS) {
    const line = vo.lines.find((l) => c.at >= l.f - 12 && c.at <= l.f + l.seconds * FPS);
    if (!line) { capRows.push(`  caption "${c.title}" at ${c.at}: no VO line over it (visual-only caption)`); continue; }
    capWorst = Math.max(capWorst, c.at - line.f);
    capRows.push(`  caption "${c.title}" enters ${c.at - line.f >= 0 ? "+" : ""}${c.at - line.f} fr after "${line.text}"`);
  }
  console.log(capRows.join("\n"));
  console.log(`captions: latest entry ${capWorst} frames after its VO line starts`);
}
