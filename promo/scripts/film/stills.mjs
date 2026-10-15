// Critique stills: render frames at given seconds with one bundle, then a contact sheet.
// usage: node scripts/film/stills.mjs <CompositionId> <outDir> <sec> [sec ...]
//        node scripts/film/stills.mjs <CompositionId> <outDir> every=<sec> [from=<sec>] [to=<sec>]
import { bundle } from "@remotion/bundler";
import { renderStill, selectComposition } from "@remotion/renderer";
import { execFileSync } from "node:child_process";
import path from "node:path";
import fs from "node:fs";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const [id, outDir, ...rest] = process.argv.slice(2);
fs.mkdirSync(outDir, { recursive: true });
const serveUrl = await bundle({ entryPoint: path.join(root, "src/index.ts"), webpackOverride: (c) => c });
const chromiumOptions = { gl: "angle" };
const composition = await selectComposition({ serveUrl, id, chromiumOptions });
const opt = Object.fromEntries(rest.filter((a) => a.includes("=")).map((a) => a.split("=")).map(([k, v]) => [k, Number(v)]));
let secs = rest.filter((a) => !a.includes("=")).map(Number);
if (opt.every) {
  const end = opt.to ?? composition.durationInFrames / composition.fps;
  for (let t = opt.from ?? 0; t < end - 1e-6; t += opt.every) secs.push(Math.round(t * 1000) / 1000);
}
const files = [];
for (let i = 0; i < secs.length; i += 6) {
  await Promise.all(secs.slice(i, i + 6).map(async (sec) => {
    const frame = Math.min(composition.durationInFrames - 1, Math.round(sec * composition.fps));
    const output = path.join(outDir, `s${String(sec.toFixed(2)).padStart(6, "0")}.png`);
    await renderStill({ serveUrl, composition, frame, output, chromiumOptions, timeoutInMilliseconds: 180000 });
    files.push([sec, output]);
  }));
}
files.sort((a, b) => a[0] - b[0]);
execFileSync("python3", ["-I", path.join(root, "scripts/film/sheet.py"), outDir], { stdio: "inherit" });
