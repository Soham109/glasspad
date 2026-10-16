// Screenshots at desktop and phone widths, plus console errors. Usage: node scripts/shots.mjs [url]
import { chromium } from "playwright";
import { mkdirSync } from "node:fs";
const url = process.argv[2] || "http://localhost:4173/";
const out = new URL("../screenshots/", import.meta.url).pathname;
mkdirSync(out, { recursive: true });
const browser = await chromium.launch();
const errors = [];
for (const [name, vp, touch] of [["desktop", { width: 1440, height: 900 }, false], ["phone", { width: 390, height: 844 }, true]]) {
  const ctx = await browser.newContext({ viewport: vp, deviceScaleFactor: 2, hasTouch: touch, isMobile: touch });
  const page = await ctx.newPage();
  page.on("console", m => { if (m.type() === "error" || m.type() === "warning") errors.push(`${name}: ${m.type()}: ${m.text()}`); });
  page.on("pageerror", e => errors.push(`${name}: pageerror: ${e.message}`));
  await page.goto(url, { waitUntil: "networkidle" });
  await page.waitForTimeout(1400);
  await page.screenshot({ path: `${out}${name}-0-hero.png` });
  const ids = ["setups", "trackpad", "modes", "displays", "layouts", "yours", "privacy", "get"];
  for (const [i, id] of ids.entries()) {
    await page.evaluate(id => document.getElementById(id).scrollIntoView({ block: "start" }), id);
    await page.waitForTimeout(id === "trackpad" || id === "setups" ? 2600 : 1300);
    await page.screenshot({ path: `${out}${name}-${i + 1}-${id}.png` });
  }
  await page.evaluate(() => scrollTo(0, document.body.scrollHeight));
  await page.waitForTimeout(800);
  await page.screenshot({ path: `${out}${name}-9-footer.png` });
  const cls = await page.evaluate(() => { let s = 0; new PerformanceObserver(l => { for (const e of l.getEntries()) s += e.value; }).observe({ type: "layout-shift", buffered: true }); return new Promise(r => setTimeout(() => r(s), 100)); });
  console.log(name, "CLS", cls);
  await ctx.close();
}
await browser.close();
console.log(errors.length ? errors.join("\n") : "no console errors");
