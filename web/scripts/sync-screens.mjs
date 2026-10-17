// Copies the framed app screens (../docs/img/screens, made by readme-images.mjs) into public/img/screens for the guide,
// and writes AVIF and WebP copies of them and of the film still. The site build (site/plugin.ts) serves those through <picture>.
import { readdirSync, mkdirSync, copyFileSync, existsSync, rmSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import sharp from "sharp";
const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const src = join(root, "..", "docs", "img", "screens");
const img = join(root, "public", "img");
const out = join(img, "screens");
rmSync(img, { recursive: true, force: true });
const files = existsSync(src) ? readdirSync(src).filter(f => f.endsWith(".png")) : [];
mkdirSync(out, { recursive: true });
for (const f of files) copyFileSync(join(src, f), join(out, f));

// Light copies: /img/screens/a.png -> /img/screens/a.avif + .webp, /film.jpg -> /img/film.avif + .webp
const jobs = files.map(f => [join(out, f), join(out, f.replace(/\.png$/, ""))]);
jobs.push([join(root, "public", "film.jpg"), join(img, "film")]);
await Promise.all(jobs.map(async ([from, to]) => {
  await sharp(from).avif({ quality: 62, effort: 6 }).toFile(to + ".avif");
  await sharp(from).webp({ quality: 86, effort: 6 }).toFile(to + ".webp");
}));
console.log(`screens: ${files.length}, light copies: ${jobs.length * 2}`);
