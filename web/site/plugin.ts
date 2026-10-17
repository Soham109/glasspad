/* Builds every page's shared parts, and what search engines and language models read, from
   pages.ts, content.ts and features.ts:
   - in each page: <!--site:head--> (title, description, canonical, icons, social cards, JSON-LD),
     <!--site:nav--> and <!--site:footer--> (the same nav and footer everywhere, from render.ts),
     <!--site:page--> (a whole Features or Compare page, from render.ts), <!--site:faq--> (the
     page's questions), and <picture> with AVIF and WebP for images that have light copies
     (scripts/sync-screens.mjs);
   - sitemap.xml, llms.txt and llms-full.txt. */

import type { Plugin } from "vite";
import { existsSync } from "node:fs";
import { join } from "node:path";
import { SITE, REPO, RELEASE, RELEASED, VERSION, pages, type Page } from "./pages";
import { DEFINITION, FAQS, HOWTO, NEEDS, FEATURES, FILM, INSTALL, LINKS } from "./content";
import { themesLine } from "../src/themes";
import { nav, footer, body, pageFaq, pageImage } from "./render";
import { CONTENT } from "./features";

const NAME = "Glasspad";
const TAGLINE = "A control surface for your Mac, on your iPhone.";
const OG = { url: `${SITE}/og-light.png`, width: 1200, height: 630, alt: "Glasspad: a control surface for your Mac, on your iPhone" };
const PERSON = { "@type": "Person", "@id": `${SITE}/#soham`, name: "Soham Aggarwal", url: "https://sohamaggarwal.com", sameAs: ["https://github.com/Soham109"] };

const esc = (s: string) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
const plain = (html: string) => html.replace(/<[^>]+>/g, "").replace(/&amp;/g, "&").replace(/&rsaquo;/g, "›");
const url = (p: Page) => SITE + p.path;
const json = (o: unknown) => JSON.stringify(o).replace(/</g, "\\u003c");

/** Vite input names: index.html keeps "main"; others are their path, "use/trackpad.html" -> "use-trackpad". */
export const inputs = () => Object.fromEntries(pages.map(p => [p.file === "index.html" ? "main" : p.file.replace(/\.html$/, "").replace(/\//g, "-"), p.file]));

function schema(p: Page): object {
  const home = pages[0];
  const app = {
    "@type": "SoftwareApplication", "@id": `${SITE}/#app`, name: NAME, url: url(home),
    description: `${DEFINITION} ${TAGLINE}`,
    applicationCategory: "UtilitiesApplication", operatingSystem: "macOS 14+, iOS 18+",
    softwareVersion: VERSION, datePublished: RELEASED,
    offers: { "@type": "Offer", price: "0", priceCurrency: "USD" },
    isAccessibleForFree: true, license: "https://opensource.org/licenses/MIT",
    downloadUrl: RELEASE, installUrl: `${SITE}/install`, softwareRequirements: NEEDS.join(", "),
    featureList: FEATURES.map(([k]) => k),
    screenshot: ["trackpad", "actions", "remote", "media"].map(s => `${SITE}/img/screens/${s}.png`),
    image: OG.url, author: { "@id": PERSON["@id"] }, sameAs: [REPO],
  };
  const graph: object[] = [
    { "@type": "WebSite", "@id": `${SITE}/#website`, name: NAME, url: url(home), inLanguage: "en", publisher: { "@id": PERSON["@id"] } },
    PERSON,
    app,
    { "@type": "SoftwareSourceCode", "@id": `${SITE}/#code`, name: NAME, codeRepository: REPO, programmingLanguage: "Swift", license: "https://opensource.org/licenses/MIT", author: { "@id": PERSON["@id"] }, targetProduct: { "@id": app["@id"] } },
    {
      "@type": "WebPage", "@id": `${url(p)}#page`, url: url(p), name: p.title, description: p.description,
      isPartOf: { "@id": `${SITE}/#website` }, about: { "@id": app["@id"] }, dateModified: p.lastmod, inLanguage: "en",
      primaryImageOfPage: image(p),
      ...(p.crumb ? { breadcrumb: { "@id": `${url(p)}#crumbs` } } : {}),
    },
  ];
  if (p.crumb) graph.push({
    "@type": "BreadcrumbList", "@id": `${url(p)}#crumbs`,
    itemListElement: [{ name: NAME, item: url(home) }, { name: p.crumb, item: url(p) }].map((c, i) => ({ "@type": "ListItem", position: i + 1, ...c })),
  });
  const qa = questions(p);
  if (qa) graph.push({
    "@type": "FAQPage", "@id": `${url(p)}#faq`, url: url(p),
    mainEntity: qa.map(([q, a]) => ({ "@type": "Question", name: plain(q), acceptedAnswer: { "@type": "Answer", text: plain(a) } })),
  });
  if (p.path === "/install") graph.push({
    "@type": "HowTo", "@id": `${SITE}/install#steps`, name: "How to install Glasspad", description: "Install Glasspad on your Mac and iPhone with one command in Terminal.",
    tool: NEEDS.map(n => ({ "@type": "HowToTool", name: n })),
    step: HOWTO.map((s, i) => ({ "@type": "HowToStep", position: i + 1, name: s.name, text: s.text, url: `${SITE}/install#get` })),
  });
  if (p === home) graph.push(
    {
      "@type": "VideoObject", "@id": `${SITE}/#film`, name: FILM.name, description: FILM.description,
      thumbnailUrl: `${SITE}/film.jpg`, uploadDate: FILM.uploadDate, duration: FILM.duration,
      embedUrl: `https://www.youtube-nocookie.com/embed/${FILM.id}`, url: `https://www.youtube.com/watch?v=${FILM.id}`,
      about: { "@id": app["@id"] },
    },
  );
  graph.push(...(p.schema ?? []));
  return { "@context": "https://schema.org", "@graph": graph };
}

/** The page's questions as [question, answer HTML]: home and the guide from content.ts, the others from features.ts. */
const questions = (p: Page): [string, string][] | undefined => p.faq ? FAQS[p.faq].map(f => [f.q, f.a]) : pageFaq(p);

/** The page's main picture: its real app screen on Features pages, else the social card. */
function image(p: Page) {
  const s = pageImage(p);
  return s
    ? { "@type": "ImageObject", url: `${SITE}/img/screens/${s.name}.png`, width: s.w, height: s.h, caption: s.alt }
    : { "@type": "ImageObject", url: OG.url, width: OG.width, height: OG.height };
}

function head(p: Page): string {
  const u = url(p);
  const og = p.ogTitle ?? p.title;
  return [
    `<title>${esc(p.title)}</title>`,
    `<meta name="description" content="${esc(p.description)}">`,
    `<link rel="canonical" href="${u}">`,
    `<meta name="theme-color" content="#F2F1EE">`,
    `<link rel="icon" href="/favicon.ico" sizes="48x48">`,
    `<link rel="icon" href="/icon.svg" type="image/svg+xml">`,
    `<link rel="apple-touch-icon" href="/apple-touch-icon.png">`,
    `<link rel="manifest" href="/site.webmanifest">`,
    `<link rel="alternate" type="text/plain" href="/llms.txt" title="llms.txt">`,
    `<meta property="og:type" content="${p.ogType ?? "website"}">`,
    `<meta property="og:site_name" content="${NAME}">`,
    `<meta property="og:locale" content="en_US">`,
    `<meta property="og:url" content="${u}">`,
    `<meta property="og:title" content="${esc(og)}">`,
    `<meta property="og:description" content="${esc(p.description)}">`,
    `<meta property="og:image" content="${OG.url}">`,
    `<meta property="og:image:type" content="image/png">`,
    `<meta property="og:image:width" content="${OG.width}">`,
    `<meta property="og:image:height" content="${OG.height}">`,
    `<meta property="og:image:alt" content="${esc(OG.alt)}">`,
    `<meta name="twitter:card" content="summary_large_image">`,
    `<meta name="twitter:title" content="${esc(og)}">`,
    `<meta name="twitter:description" content="${esc(p.description)}">`,
    `<meta name="twitter:image" content="${OG.url}">`,
    `<meta name="twitter:image:alt" content="${esc(OG.alt)}">`,
    `<script type="application/ld+json">${json(schema(p))}</script>`,
  ].join("\n");
}

const faq = (p: Page) => `<dl class="faq">\n${FAQS[p.faq!].map(f => `<dt>${esc(f.q)}</dt>\n<dd>${f.a}</dd>`).join("\n")}\n</dl>`;


/** <img src="/x.png"> becomes <picture> with AVIF and WebP when /img/x.avif and .webp exist in public/. */
function pictures(html: string, pub: string): string {
  return html.replace(/<img\b[^>]*\bsrc="(\/[^"]+)\.(png|jpe?g)"[^>]*>/g, (tag, base: string) => {
    const light = base.startsWith("/img/") ? base : "/img" + base;
    if (!["avif", "webp"].every(x => existsSync(join(pub, `${light}.${x}`)))) return tag;
    return `<picture><source type="image/avif" srcset="${light}.avif"><source type="image/webp" srcset="${light}.webp">${tag}</picture>`;
  });
}

/** Real app screenshots each page shows, for Google Images (home: the four on its first screen). */
const sitemapImages = (p: Page): string[] => {
  if (p === pages[0]) return ["trackpad", "actions", "remote", "media"].map(s => `${SITE}/img/screens/${s}.png`);
  const img = pageImage(p);
  return img ? [`${SITE}/img/screens/${img.name}.png`] : [];
};

function sitemap(): string {
  const rows = pages.map(p => {
    const images = sitemapImages(p).map(i => `\n    <image:image><image:loc>${i}</image:loc></image:image>`).join("");
    return `  <url>\n    <loc>${url(p)}</loc>\n    <lastmod>${p.lastmod}</lastmod>${images}\n  </url>`;
  });
  return `<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9" xmlns:image="http://www.google.com/schemas/sitemap-image/1.1">\n${rows.join("\n")}\n</urlset>\n`;
}

const facts = () => [
  `- Made for: iPhone (iOS 18 or later) and Mac (macOS 14 or later)`,
  `- Price: free. License: MIT. Source: ${REPO}`,
  `- Latest version: ${VERSION}, released ${RELEASED}`,
  `- Not on the App Store: one command in Terminal builds it with Xcode and installs it with a free Apple ID`,
  `- Private: paired by QR code, encrypted, talks only over your Wi-Fi, no account`,
  `- Made by Soham Aggarwal (https://sohamaggarwal.com)`,
];

/** The page list for llms.txt, grouped as the nav groups it. */
function pageList(): string[] {
  const line = (p: Page) => `- [${p.crumb ?? "Home"}](${url(p)}): ${p.summary}`;
  return [
    "## Pages", "", ...pages.filter(p => !p.group).map(line), "",
    "## Feature pages", "", ...pages.filter(p => p.group === "feature").map(line), "",
    "## Comparison pages", "", ...pages.filter(p => p.group === "compare").map(line), "",
  ];
}

function llms(): string {
  return [
    `# ${NAME}`,
    "",
    `> ${DEFINITION} It is a trackpad, a keyboard, media controls, your Dock, buttons for the app in front, a couch remote, a slide clicker, your displays, and layouts with up to three modes on one screen.`,
    "",
    ...facts(),
    "",
    ...pageList(),
    "## Links",
    "",
    ...LINKS.map(([t, h, d]) => `- [${t}](${h}): ${d}`),
    "",
  ].join("\n");
}

function llmsFull(): string {
  const qa = (k: string) => FAQS[k].flatMap(f => [`### ${f.q}`, "", plain(f.a), ""]);
  return [
    `# ${NAME}`,
    "",
    `> ${DEFINITION} ${TAGLINE}`,
    "",
    "A small menu bar app on your Mac and an app on your iPhone, on the same Wi-Fi.",
    "",
    ...facts(),
    "",
    "## Features",
    "",
    ...FEATURES.map(([k, v]) => `- ${k}: ${v}`),
    "",
    "## Requirements",
    "",
    ...NEEDS.map(n => `- ${n}`),
    "",
    "## Install",
    "",
    "Paste this into Terminal on your Mac:",
    "",
    "```bash",
    INSTALL,
    "```",
    "",
    ...HOWTO.slice(1).map((s, i) => `${i + 1}. ${s.name}: ${s.text}`),
    "",
    "With a free Apple ID, apps you install yourself stop opening after 7 days. Your Mac checks every hour and reinstalls Glasspad over Wi-Fi once the install is 5 days old, as long as the Mac is on and the iPhone is on the same Wi-Fi at some point. It notifies you if it can't.",
    "",
    "## Questions",
    "",
    ...qa("home"),
    ...qa("guide"),
    ...pages.filter(p => p.group).flatMap(p => {
      const c = CONTENT[p.path];
      return [`## ${p.crumb}`, "", `${url(p)}`, "", plain(c.answer), "", ...c.faq.flatMap(([q, a]) => [`### ${plain(q)}`, "", plain(a), ""])];
    }),
    ...pageList(),
    "## Links",
    "",
    ...LINKS.slice(0, -1).map(([t, h, d]) => `- [${t}](${h}): ${d}`),
    "",
  ].join("\n");
}

const FILES: Record<string, [string, () => string]> = {
  "sitemap.xml": ["application/xml", sitemap],
  "llms.txt": ["text/plain; charset=utf-8", llms],
  "llms-full.txt": ["text/plain; charset=utf-8", llmsFull],
};

export function site(): Plugin {
  let pub = "";
  return {
    name: "glasspad-site",
    configResolved(c) { pub = c.publicDir; },
    transformIndexHtml(html, ctx) {
      const file = ctx.path.replace(/^\//, "");
      const p = pages.find(x => x.file === file);
      if (!p) throw new Error(`site: ${file} is not in site/pages.ts`);
      if (p.faq && !html.includes("<!--site:faq-->")) throw new Error(`site: ${file} has no <!--site:faq-->`);
      if (!html.includes("<!--site:head-->")) throw new Error(`site: ${file} has no <!--site:head-->`);
      html = html.replace("<!--site:head-->", head(p));
      if (p.group) {
        if (!html.includes("<!--site:page-->")) throw new Error(`site: ${file} has no <!--site:page--> (run node scripts/learn.mjs)`);
        html = html.replace("<!--site:page-->", body(p));
      } else {
        if (!html.includes("<!--site:nav-->") || !html.includes("<!--site:footer-->")) throw new Error(`site: ${file} needs <!--site:nav--> and <!--site:footer-->`);
        html = html.replace("<!--site:nav-->", nav(p)).replace("<!--site:footer-->", footer(p));
      }
      if (p.faq) html = html.replace("<!--site:faq-->", faq(p));
      // the theme line as guide.ts writes it, so it is in the page without JavaScript
      html = html.replace(/(<li data-themes>)[^<]*(<\/li>)/, `$1Settings, then Theme. ${themesLine()} System follows your iPhone.$2`);
      return pictures(html, pub);
    },
    configureServer(server) {
      server.middlewares.use((req, res, next) => {
        const f = FILES[(req.url ?? "").replace(/^\//, "").split("?")[0]];
        if (!f) return next();
        res.setHeader("Content-Type", f[0]); res.end(f[1]());
      });
    },
    generateBundle() {
      for (const [fileName, [, make]] of Object.entries(FILES)) this.emitFile({ type: "asset", fileName, source: make() });
    },
  };
}
