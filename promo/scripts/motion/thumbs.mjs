// The motion film's YouTube thumbnails (src/motion/thumbs):
//   node scripts/motion/thumbs.mjs [--4k] [only...]
// Writes out/thumbs/glasspad-<name>.png at 1280 x 720 (and -4k.png at 3840 x 2160 with --4k),
// then out/thumbs/contact-sheet.png: each at full size beside how YouTube shows it at 336 px
// (the watch page sidebar) and 168 px (the smallest list).
import { bundle } from "@remotion/bundler";
import { getCompositions, renderStill } from "@remotion/renderer";
import { execFileSync } from "node:child_process";
import path from "node:path";
import fs from "node:fs";

const root = path.resolve(path.dirname(new URL(import.meta.url).pathname), "../..");
const out = path.join(root, "out/thumbs");
const k4 = process.argv.includes("--4k");
const only = process.argv.slice(2).filter(a => !a.startsWith("--"));
fs.mkdirSync(out, { recursive: true });
const serveUrl = await bundle({ entryPoint: path.join(root, "src/index.ts"), publicDir: path.join(root, "public") });
const comps = (await getCompositions(serveUrl)).filter(c => c.id.startsWith("MotionThumb-"));
const files = [];
for (const composition of comps) {
  const name = composition.id.replace("MotionThumb-", "");
  if (only.length && !only.includes(name)) continue;
  const file = path.join(out, `glasspad-${name}.png`);
  await renderStill({ composition, serveUrl, output: file, scale: 1, chromiumOptions: { gl: "angle" } });
  if (k4) await renderStill({ composition, serveUrl, output: path.join(out, `glasspad-${name}-4k.png`), scale: 3, chromiumOptions: { gl: "angle" } });
  files.push(file);
  console.log(file);
}
if (!only.length) {
  execFileSync("python3", ["-I", "-c", `
import sys, json
from PIL import Image, ImageDraw
fs = json.loads(sys.argv[1]); out = sys.argv[2]
pad = 24; W = 1280 + 336 + 168 + pad * 4
rows = [Image.open(f).convert("RGB") for f in fs]
S = Image.new("RGB", (W, len(rows) * (720 + pad) + pad), (255, 255, 255))
for i, im in enumerate(rows):
    y = pad + i * (720 + pad)
    S.paste(im, (pad, y))
    S.paste(im.resize((336, 189), Image.LANCZOS), (pad * 2 + 1280, y))
    S.paste(im.resize((168, 94), Image.LANCZOS), (pad * 3 + 1280 + 336, y))
S.save(out)
print(out)
`, JSON.stringify(files), path.join(out, "contact-sheet.png")], { stdio: "inherit" });
}
