// Renders HTML or SVG files to PNG (or PDF) with the Playwright Chromium in web/node_modules.
// Usage (repo root): node docs/brand/tools/shoot.mjs <jobs.json>
//   jobs.json: [{ "in": "file.html", "out": "file.png", "w": 1200, "h": 630, "transparent": false, "pdf": false }]
import { createRequire } from "node:module";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { pathToFileURL } from "node:url";

const require = createRequire(resolve("web/package.json"));
const { chromium } = require("playwright");
const jobs = JSON.parse(readFileSync(process.argv[2], "utf8"));
const browser = await chromium.launch();
for (const j of jobs) {
  const page = await browser.newPage({ viewport: { width: j.w, height: j.h }, deviceScaleFactor: j.scale ?? 1 });
  await page.goto(pathToFileURL(resolve(j.in)).href);
  await page.evaluate(() => document.fonts.ready);
  if (j.pdf) await page.pdf({ path: j.out, width: `${j.w}px`, height: `${j.h}px`, printBackground: true });
  else await page.screenshot({ path: j.out, omitBackground: !!j.transparent, clip: { x: 0, y: 0, width: j.w, height: j.h } });
  await page.close();
  console.log("wrote", j.out);
}
await browser.close();
