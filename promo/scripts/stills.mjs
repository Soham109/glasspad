// Render selected frames to out/frames/*.png with one bundle.
// usage: node scripts/stills.mjs [CompositionId] frame frame ...
import { bundle } from "@remotion/bundler";
import { renderStill, selectComposition } from "@remotion/renderer";
import path from "node:path";
import { fileURLToPath } from "node:url";
import fs from "node:fs";

const root = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const args = process.argv.slice(2);
const id = args[0] && isNaN(Number(args[0])) ? args.shift() : "GlasspadDemo";
const frames = args.map(Number);
const outDir = path.join(root, "out/frames");
fs.mkdirSync(outDir, { recursive: true });
const serveUrl = await bundle({ entryPoint: path.join(root, "src/index.ts"), webpackOverride: (c) => c });
const chromiumOptions = { gl: "angle" };
const composition = await selectComposition({ serveUrl, id, chromiumOptions, inputProps: { audio: false } });
const pre = id === "GlasspadDemo" ? "f" : "t";
await Promise.all(frames.map(async (frame) => {
  const output = path.join(outDir, `${pre}${String(frame).padStart(4, "0")}.png`);
  await renderStill({ serveUrl, composition, frame, output, chromiumOptions, inputProps: { audio: false }, timeoutInMilliseconds: 120000 });
  console.log(`frame ${frame} -> ${path.relative(root, output)}`);
}));
