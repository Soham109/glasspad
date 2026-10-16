// Copies the framed app screens (../docs/img/screens, made by readme-images.mjs) into public/img/screens for the guide.
import { readdirSync, mkdirSync, copyFileSync, existsSync, rmSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const src = join(root, "..", "docs", "img", "screens");
const out = join(root, "public", "img", "screens");
rmSync(join(root, "public", "img"), { recursive: true, force: true });
const files = existsSync(src) ? readdirSync(src).filter(f => f.endsWith(".png")) : [];
mkdirSync(out, { recursive: true });
for (const f of files) copyFileSync(join(src, f), join(out, f));
console.log(`screens: ${files.length}`);
