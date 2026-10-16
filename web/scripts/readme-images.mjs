// Renders the clean README images from the website's drawn screens.
// Usage: npm run build && npm run preview &   then   node scripts/readme-images.mjs [url]
// Output: ../docs/img/{hero,actions,remote,modes}-{light,dark}.png  (generous whitespace, 1 to 3 devices each)
// To use real simulator screenshots instead, drop PNGs with the same names into docs/img and skip this script.
import { chromium } from "playwright";
import { mkdirSync } from "node:fs";
const url = process.argv[2] || "http://localhost:4173/";
const out = new URL("../../docs/img/", import.meta.url).pathname;
mkdirSync(out, { recursive: true });
const THEMES = { light: { bg: "#F2F1EE", finish: "light" }, dark: { bg: "#151515", finish: "dark" } };

const browser = await chromium.launch();
const ctx = await browser.newContext({ viewport: { width: 1400, height: 1000 }, deviceScaleFactor: 2, reducedMotion: "reduce" });
const page = await ctx.newPage();
await page.goto(url, { waitUntil: "load" });
await page.waitForTimeout(1500);
// Show every drawn device flat on a plain background, nothing else.
await page.addStyleTag({ content: `.reveal{opacity:1!important;transform:none!important} *{animation:none!important} html,body,main,section{background:transparent!important}` });

/** PNG of one element with a transparent background. */
async function shot(sel) {
  const el = page.locator(sel).first();
  await el.scrollIntoViewIfNeeded();
  await page.waitForTimeout(500);
  return el.screenshot({ omitBackground: true });
}
/** Lay PNGs out in a row on a background and save one image. */
async function compose(name, theme, pngs, { width, height, gap = 80 }) {
  const t = THEMES[theme];
  const p = await ctx.newPage();
  await p.setViewportSize({ width, height });
  const imgs = pngs.map(b => `<img src="data:image/png;base64,${b.toString("base64")}" style="max-height:78%;max-width:${Math.floor(90 / pngs.length)}%;object-fit:contain">`).join("");
  await p.setContent(`<body style="margin:0;background:${t.bg};display:flex;align-items:center;justify-content:center;gap:${gap}px;width:${width}px;height:${height}px">${imgs}</body>`);
  await p.waitForTimeout(200);
  await p.screenshot({ path: `${out}${name}-${theme}.png` });
  await p.close();
}
const finish = f => page.evaluate(f => document.querySelectorAll(".iphone").forEach(d => d.setAttribute("data-finish", f)), f);
async function mode(key) {
  await page.evaluate(() => document.getElementById("modes").scrollIntoView());
  await page.click(`#tab-${key}`);
  await page.waitForTimeout(1200);
  return shot("#modeIphone");
}

for (const theme of ["light", "dark"]) {
  await finish(THEMES[theme].finish);
  // hero: one landscape phone, Trackpad beside Actions
  await compose("hero", theme, [await shot("#lpStage .iphone")], { width: 1600, height: 900 });
  // actions: buttons for the app in front, beside Pinned
  await compose("actions", theme, [await shot("#axPhone")], { width: 1600, height: 900 });
  // remote: couch remote and the TV
  await compose("remote", theme, [await shot("#rmTv"), await shot(".rm-phone .iphone")], { width: 1600, height: 900, gap: 120 });
  // modes: three portrait devices
  await compose("modes", theme, [await mode("keys"), await mode("media"), await mode("dock")], { width: 1600, height: 900 });
}
await browser.close();
console.log("wrote", out);
