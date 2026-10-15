// Copies real app screenshots from ../docs/img/*.png into public/img and lists them in src/screens.json.
// The page shows a screenshot slot only when its file exists, so nothing fake ships in the meantime.
import { readdirSync, mkdirSync, copyFileSync, writeFileSync, existsSync, rmSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const src = join(root, "..", "docs", "img");
const out = join(root, "public", "img");
rmSync(out, { recursive: true, force: true });
const files = existsSync(src) ? readdirSync(src).filter(f => /\.(png|jpe?g|webp)$/i.test(f)) : [];
if (files.length) mkdirSync(out, { recursive: true });
for (const f of files) copyFileSync(join(src, f), join(out, f));
writeFileSync(join(root, "src", "screens.json"), JSON.stringify(files, null, 2) + "\n");
console.log(`screens: ${files.length ? files.join(", ") : "none yet"}`);
