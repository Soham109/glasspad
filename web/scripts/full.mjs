// Full-page screenshots at desktop and phone widths. Usage: node scripts/full.mjs url outdir
import { chromium } from "playwright";
const [url = "http://localhost:4173/", out = "screenshots/v5"] = process.argv.slice(2);
const b = await chromium.launch(); const errs = [];
for (const [name, vp, touch] of [["desktop", { width: 1440, height: 900 }, false], ["phone", { width: 390, height: 844 }, true]]) {
  const p = await (await b.newContext({ viewport: vp, deviceScaleFactor: 1, hasTouch: touch, isMobile: touch })).newPage();
  p.on("pageerror", e => errs.push(`${name}: ${e.message}`)); p.on("console", m => { if (["error", "warning"].includes(m.type())) errs.push(`${name}: ${m.text()}`); });
  await p.goto(url, { waitUntil: "networkidle" });
  for (let y = 0; y < 40000; y += 600) { await p.evaluate(y => scrollTo(0, y), y); await p.waitForTimeout(40); }
  await p.evaluate(() => { scrollTo(0, 0); document.querySelectorAll(".reveal").forEach(e => e.classList.add("in")); document.querySelectorAll(".steps-list li").forEach(e => e.classList.add("in")); });
  await p.waitForTimeout(1200);
  await p.screenshot({ path: `${out}/${name}-full.png`, fullPage: true });
  const ow = await p.evaluate(() => document.documentElement.scrollWidth - innerWidth); if (ow) errs.push(`${name}: overflow ${ow}`);
}
await b.close(); console.log(errs.length ? errs.join("\n") : "no console errors");
