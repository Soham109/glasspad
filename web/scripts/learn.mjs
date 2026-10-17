// Writes the small HTML file Vite needs for each Features and Compare page in site/pages.ts.
// The build (site/plugin.ts) fills in the head, nav, page and footer from site/pages.ts and
// site/features.ts, so this file never needs editing. Runs before every build (npm run build).
import { writeFileSync, mkdirSync, readFileSync, existsSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { pages } from "../site/pages.ts";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const STUB = `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<script>document.documentElement.classList.add("js")</script>
<!--site:head-->
</head>
<body>
<!--site:page-->
<script type="module" src="/src/page.ts"></script>
</body>
</html>
`;
let n = 0;
for (const p of pages.filter(p => p.group)) {
  const file = join(root, p.file);
  if (existsSync(file) && readFileSync(file, "utf8") === STUB) continue;
  mkdirSync(dirname(file), { recursive: true });
  writeFileSync(file, STUB); n++;
}
console.log(`learn: ${pages.filter(p => p.group).length} pages, ${n} written`);
