/* The parts every page shares (the nav and the footer) and the two page templates (Features
   and Compare), written from site/pages.ts and site/features.ts at build time by site/plugin.ts. */

import { REPO, pages, featurePages, comparePages, type Page } from "./pages";
import { CONTENT, FACTS, SHOTS, type Feature, type Comparison, type Mark, type Section } from "./features";
import { icon } from "./icons";

export const INSTALL_CMD = "curl -fsSL https://raw.githubusercontent.com/Soham109/glasspad/main/install.sh | bash";

export const esc = (s: string) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
const page = (path: string) => { const p = pages.find(x => x.path === path); if (!p) throw new Error(`site: no page ${path} in site/pages.ts`); return p; };
const cur = (p: Page, q: Page) => (p === q ? ' aria-current="page"' : "");

const GITHUB = '<svg width="18" height="18" viewBox="0 0 16 16" aria-hidden="true" focusable="false"><path fill="currentColor" d="M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27.68 0 1.36.09 2 .27 1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.013 8.013 0 0016 8c0-4.42-3.58-8-8-8z"/></svg>';
const BRAND = '<img src="/icon.svg" width="26" height="26" alt=""><span>Glasspad</span>';

/* ------------------------------------------------------------------ nav */

/** The global nav: Features and Compare open a menu on hover, click or keyboard; on phones, Menu opens a full sheet. */
export function nav(p: Page): string {
  const feats = featurePages(), comps = comparePages();
  const featureItem = (q: Page) => `<li><a href="${q.path}"${cur(p, q)}><span class="gn-ic">${icon(q.icon!, 22)}</span><span class="gn-tx"><b>${esc(q.nav!)}</b><small>${esc(q.blurb!)}</small></span></a></li>`;
  const compareItem = (q: Page) => `<li><a href="${q.path}"${cur(p, q)}><span class="gn-tx"><b>${esc(q.nav!)}</b><small>${esc(q.blurb!)}</small></span></a></li>`;
  const top = (label: string, id: string, active: boolean, body: string) => `
    <div class="gn-item" data-menu>
      <button class="gn-top${active ? " is-active" : ""}" type="button" aria-expanded="false" aria-controls="${id}">${label}${icon("chevron", 12, "gn-chev")}</button>
      <div class="gn-panel" id="${id}">${body}</div>
    </div>`;
  const sheetList = (label: string, list: Page[], withIcon: boolean) => `<p class="gn-h" aria-hidden="true">${label}</p><ul aria-label="${label}">${list.map(q => `<li><a href="${q.path}"${cur(p, q)}>${withIcon ? `<span class="gn-ic">${icon(q.icon!, 20)}</span>` : ""}${esc(q.nav!)}</a></li>`).join("")}</ul>`;
  return `<header class="nav gn" id="nav">
  <a class="brand" href="/"${p.path === "/" ? ' aria-current="page"' : ""}>${BRAND}</a>
  <nav class="gn-links" aria-label="Main" id="navLinks">
    <span class="nav-ind" id="navInd" aria-hidden="true"></span>${top("Features", "gn-features", p.group === "feature", `
        <ul class="gn-grid">${feats.map(featureItem).join("")}</ul>
        <a class="gn-more" href="/guide#modes">Every mode in the guide${icon("arrow", 14)}</a>`)}${top("Compare", "gn-compare", p.group === "compare", `
        <ul class="gn-list">${comps.map(compareItem).join("")}</ul>`)}
    <a class="gn-top" href="/guide"${p.path === "/guide" ? ' aria-current="page"' : ""}>Guide</a>
  </nav>
  <a class="nav-gh" href="${REPO}" aria-label="Glasspad on GitHub">${GITHUB}</a>
  <a class="gn-install" href="/install"${p.path === "/install" ? ' aria-current="page"' : ""}>Install</a>
  <button class="nav-menu" id="navMenu" type="button" aria-expanded="false" aria-controls="navSheet">Menu</button>
</header>
<div class="gn-sheet" id="navSheet">
  <nav class="gn-sheet-in wrap" aria-label="Menu">
    <div class="gn-sec">${sheetList("Features", feats, true)}</div>
    <div class="gn-sec">${sheetList("Compare", comps, false)}</div>
    <div class="gn-sec"><p class="gn-h" aria-hidden="true">More</p><ul aria-label="More"><li><a href="/">Home</a></li><li><a href="/install"${p.path === "/install" ? ' aria-current="page"' : ""}>Install</a></li><li><a href="/guide"${p.path === "/guide" ? ' aria-current="page"' : ""}>Guide</a></li><li><a href="${REPO}">GitHub</a></li></ul></div>
  </nav>
</div>`;
}

/* ------------------------------------------------------------------ footer */

/** The footer's columns, and on inner pages the breadcrumb trail (as BreadcrumbList data says it). */
export function footer(p: Page): string {
  const col = (title: string, links: [string, string, boolean?][]) =>
    `<div class="gf-col"><h2>${title}</h2><ul>${links.map(([t, h, here]) => `<li><a href="${h}"${here ? ' aria-current="page"' : ""}>${esc(t)}</a></li>`).join("")}</ul></div>`;
  const crumbs = p.crumb
    ? `<nav class="gf-crumbs" aria-label="Breadcrumb"><ol><li><a href="/">Glasspad</a></li><li><a href="${p.path}" aria-current="page">${esc(p.crumb)}</a></li></ol></nav>`
    : "";
  return `<div class="gf wrap">
    <div class="gf-top">
      <div class="gf-brand"><a class="brand" href="/">${BRAND}</a><p>A control surface for your Mac, on your iPhone.</p></div>
      <nav class="gf-cols" aria-label="Footer">
        ${col("Product", [["Overview", "/", p.path === "/"], ["Install", "/install", p.path === "/install"], ["Demo film", "/#film"], ["Questions", "/#questions"]])}
        ${col("Features", featurePages().map(q => [q.nav!, q.path, p === q]))}
        ${col("Compare", comparePages().map(q => [q.nav!.replace(/^vs /, ""), q.path, p === q]))}
        ${col("Resources", [["Guide", "/guide", p.path === "/guide"], ["GitHub", REPO], ["Releases", `${REPO}/releases`], ["Changelog", `${REPO}/blob/main/CHANGELOG.md`]])}
        ${col("Legal", [["MIT License", `${REPO}/blob/main/LICENSE`]])}
      </nav>
    </div>
    <div class="gf-base">${crumbs}<p class="gf-by">Made by <a href="https://sohamaggarwal.com">Soham Aggarwal</a>. Free and open source.</p></div>
  </div>`;
}

/* ------------------------------------------------------------------ shared blocks */

const copyButton = (cmd: string, label: string) =>
  `<button class="copy" type="button" data-copy="${esc(cmd)}" aria-label="${label}">${icon("copy", 15, "ic-copy")}${icon("check", 15, "ic-check")}<span>Copy</span></button>`;

const hero = (eyebrow: string, eyeIcon: string | undefined, h1: string, sub: string, second: [string, string]) => `<header class="pg-hero wrap">
  <p class="pg-eye">${eyeIcon ? icon(eyeIcon, 20) : ""}${esc(eyebrow)}</p>
  <h1>${h1}</h1>
  <p class="pg-sub">${sub}</p>
  <div class="pg-cta"><a class="btn btn-ink" href="/install">Install Glasspad</a><a class="btn btn-quiet" href="${second[0]}">${second[1]}</a></div>
</header>`;

const faqBlock = (faq: [string, string][]) => `<section class="pg-sec wrap" id="faq" aria-labelledby="faq-t">
  <h2 class="pg-h2" id="faq-t">Questions</h2>
  <div class="pg-faq">
${faq.map(([q, a]) => `    <details><summary><span>${q}</span>${icon("chevron", 16, "pg-faq-chev")}</summary><div class="pg-faq-a"><p>${a}</p></div></details>`).join("\n")}
  </div>
</section>`;

const related = (paths: string[]) => `<section class="pg-sec wrap" aria-labelledby="more-t">
  <h2 class="pg-h2" id="more-t">Keep exploring</h2>
  <ul class="pg-related">
${paths.map(page).map(q => `    <li><a href="${q.path}"><span class="pg-rel-ic">${icon(q.icon ?? "compare", 22)}</span><b>${esc(q.crumb!)}</b><span>${esc(q.blurb!)}</span><span class="pg-rel-go">${icon("arrow", 16)}</span></a></li>`).join("\n")}
  </ul>
</section>`;

const band = () => `<section class="pg-band" id="install" aria-labelledby="install-t">
  <div class="wrap pg-band-in">
    <h2 id="install-t">Get Glasspad. It is free.</h2>
    <p>${FACTS} Paste this into Terminal on your Mac:</p>
    <div class="pg-cmd"><code>${INSTALL_CMD}</code>${copyButton(INSTALL_CMD, "Copy the install command")}</div>
    <p class="pg-band-more">The script builds it with Xcode 26 or later and your free Apple ID, and waits for you where Apple needs a click. <a href="/install">Every install step</a> <span aria-hidden="true">&middot;</span> <a href="/guide#help">Help in the guide</a></p>
  </div>
</section>`;

const shot = (name: keyof typeof SHOTS, cls = "") => {
  const s = SHOTS[name];
  return `<img class="${cls}" src="/img/screens/${name}.png" width="${s.w}" height="${s.h}" alt="${esc(s.alt)}" loading="lazy" decoding="async">`;
};

/* ------------------------------------------------------------------ the drawn scenes */

/** The interactive trackpad from the home page, as one dark band (src/demo.ts). */
const DEMO = `<section class="demo dark pg-demo" id="trackpad" aria-labelledby="try-title">
  <div class="wrap">
    <div class="section-head center">
      <h2 id="try-title">Try it here.</h2>
      <p class="lede" data-touch-copy="Put one, two or three fingers on the phone, or pick a gesture below." data-mouse-copy="Move your pointer on the phone, or pick a gesture below.">Move your pointer on the phone, or pick a gesture below.</p>
    </div>
    <div class="stage">
      <div class="phone-col">
        <div class="iphone " data-orient="landscape" data-finish="dark" id="phone">
          <i class="ip-btn l action"></i><i class="ip-btn l up"></i><i class="ip-btn l down"></i><i class="ip-btn r side"></i><i class="ip-btn r cam"></i>
          <div class="ip-body"><div class="ip-bezel"></div><div class="ip-screen"><div class="phone-screen" id="surface" role="application" aria-label="Trackpad demo. Use your pointer or fingers on this surface." tabindex="0"><svg class="trails" id="trails" aria-hidden="true"></svg><div class="dots" id="dots" aria-hidden="true"></div></div></div><div class="ip-island"></div></div>
        </div>
      </div>
      <div class="mac-col">
        <div class="mac" id="mac" aria-hidden="true">
          <div class="mac-bar"><svg class="mac-apple" viewBox="0 0 14 17" aria-hidden="true"><path d="M11.6 9c0-2 1.6-2.9 1.7-3-1-1.4-2.4-1.6-2.9-1.6-1.2-.1-2.4.7-3 .7-.6 0-1.6-.7-2.6-.7C3.4 4.4 2.1 5.2 1.4 6.5 0 9 1 12.7 2.4 14.7c.7 1 1.5 2 2.5 2 1 0 1.4-.6 2.6-.6s1.5.6 2.6.6c1.1 0 1.8-1 2.4-2 .8-1.1 1.1-2.2 1.1-2.3 0 0-2-.8-2-3.4ZM9.7 3c.5-.7.9-1.6.8-2.5-.8 0-1.8.5-2.3 1.2-.5.6-1 1.5-.8 2.4.9.1 1.8-.5 2.3-1.1Z"/></svg><b>Safari</b><span>File</span><span>Edit</span><span>View</span><span>History</span><span class="mac-clock">Fri 9:41</span></div>
          <div class="mac-viewport">
            <div class="spaces" id="spaces">
              <div class="space">
                <div class="win" id="win">
                  <div class="win-bar"><i></i><i></i><i></i></div>
                  <div class="win-body"><div class="doc" id="doc"></div></div>
                </div>
                <div class="win win-b"><div class="win-bar"><i></i><i></i><i></i></div></div>
              </div>
              <div class="space space-2"><div class="win win-c"><div class="win-bar"><i></i><i></i><i></i></div></div></div>
              <div class="space space-3"><div class="win win-d"><div class="win-bar"><i></i><i></i><i></i></div></div></div>
            </div>
            <svg class="cursor" id="cursor" width="16" height="22" viewBox="0 0 16 22"><path d="M1 1v17l4.6-4.4 3 6.9 3-1.3-3-6.8H15Z" fill="#1A1A1A" stroke="#fff" stroke-width="1.4" stroke-linejoin="round"/></svg>
          </div>
          <div class="mac-dots" id="macSpaces"><i class="on"></i><i></i><i></i></div>
        </div>
        <div class="caption" aria-live="polite"><span class="caption-text" id="caption">Move the pointer</span></div>
      </div>
    </div>
    <div class="gestures" role="group" aria-label="Show a gesture">
      <button class="chip" data-g="move">Move</button>
      <button class="chip" data-g="click">Tap to click</button>
      <button class="chip" data-g="scroll">Two finger scroll</button>
      <button class="chip" data-g="pinch">Pinch to zoom</button>
      <button class="chip" data-g="spaces">Three finger swipe</button>
      <button class="chip" data-g="mission">Mission Control</button>
    </div>
  </div>
</section>`;

function visual(f: Feature): string {
  const label = esc(f.visualLabel);
  switch (f.visual) {
    case "trackpad": return DEMO;
    case "displays": return `<div class="pg-visual wrap"><div class="dp-stage" id="dpStage" role="img" aria-label="${label}"></div></div>`;
    case "keys": case "media": case "clipboard": return `<div class="pg-visual wrap"><div class="pg-mode" data-mode="${f.visual}" role="img" aria-label="${label}"><div class="pgm-phone"></div><div class="pgm-mac"></div></div></div>`;
    default: return `<div class="pg-visual wrap"><div class="uc-stage pg-stage" data-room="${f.visual}" role="img" aria-label="${label}"></div></div>`;
  }
}

/* ------------------------------------------------------------------ longer parts */

const slug = (t: string) => t.toLowerCase().replace(/&[a-z]+;/g, "").replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "");
const MARK: Record<Mark, string> = { yes: "Yes", no: "No", part: "Partly", "": "" };
const cell = ([m, t]: [Mark, string]) => `<td>${m ? `<span class="cmp-mk ${m}">${icon(m === "yes" ? "check" : m === "no" ? "cross" : "part", 14)}<span class="sr">${MARK[m]}. </span></span>` : ""}<span class="cmp-tx">${t}</span></td>`;
const fitList = (points: string[]) => `<ul>${points.map(x => `<li>${icon("check", 16)}<span>${x}</span></li>`).join("")}</ul>`;
const cmpKey = `<p class="cmp-key"><span><span class="cmp-mk yes">${icon("check", 14)}</span>Has it</span><span><span class="cmp-mk part">${icon("part", 14)}</span>Partly, or with limits</span><span><span class="cmp-mk no">${icon("cross", 14)}</span>Does not</span></p>`;

function section(s: Section): string {
  const id = slug(s.title);
  const head = `<h2 class="pg-h2" id="${id}-t">${s.title}</h2>`;
  const note = s.note ? `\n  <p class="cmp-note">${s.note}</p>` : "";
  if (s.kind === "text") return `<section class="pg-sec wrap" id="${id}" aria-labelledby="${id}-t">
  ${head}
  <div class="pg-short solo"><div class="pg-short-tx"><p class="pg-answer">${s.text}</p>${s.note ? `<p class="pg-facts">${s.note}</p>` : ""}</div></div>
</section>`;
  if (s.kind === "cards") return `<section class="pg-sec wrap" id="${id}" aria-labelledby="${id}-t">
  ${head}
  <div class="cmp-fits">
${s.cards.map(c => `    <div class="cmp-fit${c.us ? " us" : ""}"><h3>${c.title}</h3>${fitList(c.points)}</div>`).join("\n")}
  </div>${note}
</section>`;
  const marks = s.rows.some(r => r.us[0] || r.them[0]);
  return `<section class="pg-sec wrap" id="${id}" aria-labelledby="${id}-t">
  ${head}
  <table class="cmp">
    <caption class="sr">${s.caption}</caption>
    <thead><tr><td></td><th scope="col">${s.cols[0]}</th><th scope="col">${s.cols[1]}</th></tr></thead>
    <tbody>
${s.rows.map(r => `      <tr><th scope="row">${r.k}</th>${cell(r.us)}${cell(r.them)}</tr>`).join("\n")}
    </tbody>
  </table>${marks ? `\n  ${cmpKey}` : ""}${note}
</section>`;
}
const sections = (list?: Section[]) => (list ?? []).map(section).map(x => `\n\n${x}`).join("");

const sourcesBlock = (sources: [string, string][], checked: string) => `<section class="pg-sec wrap pg-sources" aria-labelledby="src-t">
  <h2 class="pg-h3" id="src-t">Sources</h2>
  <p>Checked on ${checked}.${sources.some(([, u]) => u.includes("apps.apple.com")) ? " Prices are from the US App Store and can differ in other countries." : ""}</p>
  <ul>
${sources.map(([t, u]) => `    <li><a href="${u}">${t}</a></li>`).join("\n")}
  </ul>
</section>`;

/* ------------------------------------------------------------------ templates */

function featurePage(p: Page, f: Feature): string {
  return `${hero(p.nav!, p.icon, f.h1, f.sub, f.guide)}

${visual(f)}

<section class="pg-sec wrap" aria-labelledby="short-t">
  <div class="pg-short">
    <div class="pg-short-tx">
      <h2 class="pg-label" id="short-t">In short</h2>
      <p class="pg-answer">${f.answer}</p>
      <p class="pg-facts">${FACTS}</p>
    </div>
    <figure class="pg-shot${SHOTS[f.shot].w > SHOTS[f.shot].h ? " land" : ""}">${shot(f.shot)}<figcaption>${f.caption}</figcaption></figure>
  </div>
</section>${sections(f.early)}

<section class="pg-sec wrap" aria-labelledby="why-t">
  <h2 class="pg-h2" id="why-t">What you get</h2>
  <ul class="pg-tiles n${f.tiles.length}">
${f.tiles.map(t => `    <li><span class="pg-tile-ic">${icon(t.icon, 24)}</span><h3>${t.title}</h3><p>${t.text}</p></li>`).join("\n")}
  </ul>
</section>

<section class="pg-sec wrap" aria-labelledby="how-t">
  <h2 class="pg-h2" id="how-t">How it works</h2>
  <ol class="pg-steps">
${f.steps.map((s, i) => `    <li><span class="pg-step-art">${icon(s.icon, 40)}<span class="pg-step-n" aria-hidden="true">${i + 1}</span></span><h3>${s.title}</h3><p>${s.text}</p></li>`).join("\n")}
  </ol>
</section>${sections(f.more)}

${faqBlock(f.faq)}

${related(f.related)}${f.sources ? `\n\n${sourcesBlock(f.sources, f.checked ?? "17 October 2026")}` : ""}`;
}

function comparePage(p: Page, c: Comparison): string {
  return `${hero("Compare", undefined, c.h1, c.sub, ["#compare", "See the table"])}

<section class="pg-sec wrap" aria-labelledby="short-t">
  <div class="pg-short${c.shot ? "" : " solo"}">
    <div class="pg-short-tx">
      <h2 class="pg-label" id="short-t">In short</h2>
      <p class="pg-answer">${c.answer}</p>
    </div>${c.shot ? `\n    <figure class="pg-shot${SHOTS[c.shot].w > SHOTS[c.shot].h ? " land" : ""}">${shot(c.shot)}<figcaption>${c.caption ?? ""}</figcaption></figure>` : ""}
  </div>
</section>

<section class="pg-sec wrap" id="compare" aria-labelledby="compare-t">
  <h2 class="pg-h2" id="compare-t">Side by side</h2>
  <table class="cmp">
    <caption class="sr">Glasspad and ${esc(c.them)}, side by side</caption>
    <thead><tr><td></td><th scope="col">Glasspad</th><th scope="col">${esc(c.them)}</th></tr></thead>
    <tbody>
${c.rows.map(r => `      <tr><th scope="row">${r.k}</th>${cell(r.us)}${cell(r.them)}</tr>`).join("\n")}
    </tbody>
  </table>
  ${cmpKey}
</section>

<section class="pg-sec wrap" aria-labelledby="fit-t">
  <h2 class="pg-h2" id="fit-t">Which one fits you</h2>
  <div class="cmp-fits">
    <div class="cmp-fit"><h3>Choose ${esc(c.them)} if</h3>${fitList(c.fitThem)}</div>
    <div class="cmp-fit us"><h3>Choose Glasspad if</h3>${fitList(c.fitUs)}</div>
  </div>${c.note ? `\n  <p class="cmp-note">${c.note}</p>` : ""}
</section>${sections(c.more)}

${faqBlock(c.faq)}

${related(c.related)}

${sourcesBlock(c.sources, c.checked ?? "16 October 2026")}`;
}

/** The whole <body> of a Features or Compare page. */
export function body(p: Page): string {
  const c = CONTENT[p.path];
  if (!c) throw new Error(`site: ${p.path} has a group in site/pages.ts but no content in site/features.ts`);
  const main = c.kind === "feature" ? featurePage(p, c) : comparePage(p, c);
  return `<a class="skip" href="#main">Skip to content</a>
${nav(p)}

<main id="main" class="pg pg-${c.kind}">

${main}

${band()}

</main>

<footer class="foot">
  ${footer(p)}
</footer>`;
}

/** For structured data: the page's questions as plain [q, a] pairs, and its main image. */
export const pageFaq = (p: Page) => CONTENT[p.path]?.faq;
export const pageImage = (p: Page) => { const c = CONTENT[p.path]; return c?.shot ? { name: c.shot, ...SHOTS[c.shot] } : undefined; };
