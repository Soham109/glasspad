// Stills of the motion film at given seconds, for checking a range by eye:
//   node scripts/motion/stills.mjs <out dir> <name> <seconds...> [--scale=0.5]
// Writes one PNG per time and <name>.jpg, a labelled sheet of all of them.
import { bundle } from "@remotion/bundler";
import { renderStill, selectComposition } from "@remotion/renderer";
import { execFileSync } from "node:child_process";
import path from "node:path";
import fs from "node:fs";
const args = process.argv.slice(2).filter(a => !a.startsWith("--"));
const scale = Number((process.argv.find(a => a.startsWith("--scale=")) ?? "--scale=0.5").split("=")[1]);
const [out, name, ...secs] = args;
fs.mkdirSync(out, { recursive: true });
const root = path.resolve(path.dirname(new URL(import.meta.url).pathname), "../..");
const serveUrl = await bundle({ entryPoint: path.join(root, "src/index.ts"), publicDir: path.join(root, "public") });
const composition = await selectComposition({ serveUrl, id: "GlasspadMotion" });
const files = [];
for (const s of secs) {
  const frame = Math.round(Number(s) * 60);
  const file = path.join(out, `${name}-${String(frame).padStart(5, "0")}.png`);
  await renderStill({ composition, serveUrl, output: file, frame, scale, chromiumOptions: { gl: "angle" } });
  files.push([file, Number(s)]);
}
execFileSync("python3", ["-I", "-c", `
import sys, json
from PIL import Image, ImageDraw
fs = json.loads(sys.argv[1]); out = sys.argv[2]
ims = [Image.open(f).convert("RGB") for f, _ in fs]
w, h = ims[0].size; cols = 2 if len(ims) > 1 else 1; rows = (len(ims) + cols - 1) // cols
S = Image.new("RGB", (cols * (w + 4), rows * (h + 4)), (255, 0, 255))
for i, (im, (f, s)) in enumerate(zip(ims, fs)):
    d = ImageDraw.Draw(im); d.rectangle([0, 0, 96, 18], fill=(0, 0, 0)); d.text((4, 3), f"{s:.2f}s", fill=(255, 220, 0))
    S.paste(im, ((i % cols) * (w + 4), (i // cols) * (h + 4)))
S.save(out, quality=88)
print(out)
`, JSON.stringify(files), path.join(out, `${name}.jpg`)], { stdio: "inherit" });
