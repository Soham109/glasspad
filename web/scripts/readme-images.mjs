// Frames the app's screens in an iPhone and lays them out for the README and the guide.
//
// Usage:  npm run build && npm run preview &
//         node scripts/readme-images.mjs <raw folder> [site url]
//
// <raw folder> holds simulator screenshots (iPhone 18 Pro, 1206 x 2622), named after what they show.
// They come from the app's demo launch arguments (DebugLaunch in Apps/iOS/Sources/App/RootView.swift):
//   actions, actions-mono, actions-midnight, actions-sand   -GPMode actions -GPTheme <theme>
//   dock, media                                             -GPMode dock / media
//   present, clipboard                                      -GPActionsPage present / clipboard
//   library, folder, website                                -GPActionsPage library / folder, and a new Website button
//   remote                                                  -GPMode remote
//   themes, menu                                            -GPSettings / -GPMenu
//   trackpad (landscape)                                    -GPFilm trackpad -GPOrientation landscape
// Keyboard, Macros, Displays and Layouts are taken from the website's drawn screens for now.
//
// Output: ../docs/img/screens/<name>.png, one framed phone each on a clear background (the guide shows these),
//         ../docs/img/{hero,modes,themes,layouts}.png, a few phones together for the README.
import { chromium } from "playwright";
import { mkdirSync, readFileSync, existsSync } from "node:fs";
import { join } from "node:path";

const [raw, url = "http://localhost:4173/"] = process.argv.slice(2);
if (!raw || !existsSync(raw)) { console.error("usage: node scripts/readme-images.mjs <raw folder> [site url]"); process.exit(1); }
const root = new URL("../../docs/img/", import.meta.url).pathname;
const screens = join(root, "screens");
mkdirSync(screens, { recursive: true });
const deviceCSS = readFileSync(new URL("../src/device.css", import.meta.url), "utf8");
const PAPER = "#F2F1EE";
const browser = await chromium.launch();

/* 1. The drawn screens, from the website, held still (reduced motion) */
const site = await (await browser.newContext({ viewport: { width: 1440, height: 1000 }, deviceScaleFactor: 3, reducedMotion: "reduce" })).newPage();
await site.goto(url, { waitUntil: "networkidle" });
const shots = {};
async function grab(name, sel, land, before) {
  await site.evaluate(s => document.querySelector(s).scrollIntoView({ block: "center" }), sel);
  if (before) await before();
  await site.waitForTimeout(700);
  const png = await site.locator(sel).first().screenshot({ omitBackground: true });
  shots[name] = { src: `data:image/png;base64,${png.toString("base64")}`, land };
}
await grab("keyboard", "#modeIphone .ip-screen", false, () => site.click("#tab-keys"));
await grab("macros", "#modeIphone .ip-screen", false, () => site.click("#tab-macros"));
await grab("displays", "#dpStage .ip-screen", true);
await grab("layouts", "#lpStage .ip-screen", true, () => site.getByRole("radio", { name: "Desk" }).click());

/* 2. Every screen in the same drawn iPhone (web/src/device.css) */
const REAL = ["actions", "actions-mono", "actions-midnight", "actions-sand", "dock", "media", "present", "clipboard", "library", "folder", "website", "remote", "themes", "menu", "trackpad"];
for (const n of REAL) {
  const f = join(raw, n + ".png");
  if (!existsSync(f)) { console.warn("missing", f); continue; }
  shots[n] = { src: `data:image/png;base64,${readFileSync(f).toString("base64")}`, land: n === "trackpad" };
}

const page = await (await browser.newContext({ viewport: { width: 1600, height: 1000 }, deviceScaleFactor: 2 })).newPage();
const phoneHTML = (s, w) => `<div class="iphone" data-orient="${s.land ? "landscape" : "portrait"}" data-finish="light" style="width:${w}px">
  <i class="ip-btn l action"></i><i class="ip-btn l up"></i><i class="ip-btn l down"></i><i class="ip-btn r side"></i><i class="ip-btn r cam"></i>
  <div class="ip-body"><div class="ip-bezel"></div><div class="ip-screen"><img src="${s.src}" style="display:block;width:100%;height:100%;object-fit:cover"></div><div class="ip-island"></div></div></div>`;
const html = (body, bg = PAPER) => `<!doctype html><style>${deviceCSS} body{margin:0;background:${bg}} .row{display:flex;align-items:center;justify-content:center}</style><body>${body}</body>`;

// the guide shows one of each; the theme variants only appear together in the README
const GUIDE = ["trackpad", "keyboard", "media", "dock", "actions", "remote", "present", "clipboard", "macros", "displays", "layouts", "library", "website", "folder", "themes", "menu"];
for (const n of GUIDE) {
  const s = shots[n]; if (!s) continue;
  await page.setContent(html(`<div id="o" style="padding:40px;display:inline-block">${phoneHTML(s, s.land ? 560 : 270)}</div>`, "transparent"));
  await page.waitForTimeout(80);
  await page.locator("#o").screenshot({ path: join(screens, n + ".png"), omitBackground: true });
}

/* 3. A few phones side by side, with room around them */
async function compose(name, names, { gap = 72, w = 300 } = {}) {
  await page.setContent(html(`<div class="row" id="o" style="gap:${gap}px;padding:80px 96px;display:inline-flex">${names.map(n => phoneHTML(shots[n], shots[n].land ? 600 : w)).join("")}</div>`));
  await page.waitForTimeout(120);
  await page.locator("#o").screenshot({ path: join(root, name + ".png") });
}
await compose("hero", ["remote", "actions", "media"]);
await compose("modes", ["dock", "present", "clipboard", "library"], { gap: 56, w: 260 });
await compose("themes", ["actions", "actions-mono", "actions-sand", "actions-midnight"], { gap: 56, w: 260 });
await compose("layouts", ["layouts", "displays"]);

await browser.close();
console.log("wrote", root);
