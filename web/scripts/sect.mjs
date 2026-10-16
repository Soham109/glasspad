// Element screenshots of named sections at desktop and phone widths. Usage: node scripts/sect.mjs url outdir id1,id2 [wait]
import { chromium } from "playwright";
const [url, out, ids, wait = "1600"] = process.argv.slice(2);
const b = await chromium.launch();
const errs = [];
for (const [name, vp, touch] of [["desktop", { width: 1440, height: 900 }, false], ["phone", { width: 390, height: 844 }, true]]) {
  const ctx = await b.newContext({ viewport: vp, deviceScaleFactor: 2, hasTouch: touch, isMobile: touch });
  const p = await ctx.newPage();
  p.on("console", m => { if (m.type() === "error" || m.type() === "warning") errs.push(`${name}: ${m.text()}`); });
  p.on("pageerror", e => errs.push(`${name}: pageerror ${e.message}`));
  await p.goto(url, { waitUntil: "networkidle" });
  for (let y = 0; y < await p.evaluate(() => document.body.scrollHeight); y += 700) { await p.evaluate(y => scrollTo(0, y), y); await p.waitForTimeout(60); }
  for (const id of ids.split(",")) {
    const sel = id.startsWith(".") || id.startsWith("#") ? id : "#" + id;
    await p.evaluate(s => document.querySelector(s).scrollIntoView({ block: "start" }), sel);
    await p.waitForTimeout(+wait);
    await p.evaluate(() => document.querySelectorAll(".reveal").forEach(e => e.classList.add("in")));
    await p.waitForTimeout(500);
    await p.locator(sel).first().screenshot({ path: `${out}/${name}-${id.replace(/[#.]/g, "")}.png` });
  }
  const ow = await p.evaluate(() => document.documentElement.scrollWidth - innerWidth);
  if (ow > 0) errs.push(`${name}: horizontal overflow ${ow}px`);
  await ctx.close();
}
await b.close();
console.log(errs.length ? errs.join("\n") : "no console errors");
