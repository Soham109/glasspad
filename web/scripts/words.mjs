// Counts visible words on the page (desktop width). Usage: node scripts/words.mjs url
import { chromium } from "playwright";
const b = await chromium.launch(); const p = await (await b.newContext({ viewport: { width: 1440, height: 900 } })).newPage();
await p.goto(process.argv[2] || "http://localhost:4173/", { waitUntil: "networkidle" });
for (let y = 0; y < 40000; y += 800) { await p.evaluate(y => scrollTo(0, y), y); await p.waitForTimeout(20); }
const r = await p.evaluate(() => {
  const n = (el) => (el?.innerText || "").split(/\s+/).filter(Boolean).length;
  const out = { total: n(document.querySelector("main")) };
  document.querySelectorAll("main > section").forEach(s => out[s.id] = n(s));
  return out;
});
console.log(JSON.stringify(r)); await b.close();
