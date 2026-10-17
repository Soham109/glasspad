/* Builds every page's shared parts, and what search engines and language models read, from
   pages.ts, content.ts and features.ts:
   - in each page: <!--site:head--> (title, description, canonical, icons, social cards, JSON-LD),
     <!--site:nav--> and <!--site:footer--> (the same nav and footer everywhere, from render.ts),
     <!--site:page--> (a whole Features or Compare page, from render.ts), <!--site:faq--> (the
     page's questions), and <picture> with AVIF and WebP for images that have light copies
     (scripts/sync-screens.mjs);
   - sitemap.xml, llms.txt and llms-full.txt. */

import type { Plugin } from "vite";
import { join } from "node:path";
import { SITE, REPO, RELEASE, RELEASED, VERSION, pages, type Page } from "./pages";
import { existsSync, readFileSync } from "node:fs";
import { DEFINITION, FAQS, HOWTO, NEEDS, FEATURES, FILM, INSTALL, LINKS } from "./content";
import { themesLine } from "../src/themes";
import { nav, footer, body, pageFaq, pageImage } from "./render";
import { CONTENT, SHOTS, type Shot } from "./features";
import { changelogHtml, changelogFeed, icons, pressKit, notFound } from "./extras";

const NAME = "Glasspad";
const TAGLINE = "A control surface for your Mac, on your iPhone.";
const OG = { url: `${SITE}/og-light.png`, width: 1200, height: 630, alt: "Glasspad: a control surface for your Mac, on your iPhone" };
const AUTHOR = "Soham Aggarwal";
const YOUTUBE = "https://www.youtube.com/@sohamaggarwal5";
const LICENSE = "https://opensource.org/licenses/MIT";
const CHANGES = `${REPO}/blob/main/CHANGELOG.md`;
const FILM_URL = `https://www.youtube.com/watch?v=${FILM.id}`;
const FILM_EMBED = `https://www.youtube.com/embed/${FILM.id}`;
/** Seconds in an ISO 8601 duration such as PT1M4S, for the video sitemap. */
const seconds = (d: string) => { const m = /PT(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?/.exec(d)!; return (+(m[1] ?? 0)) * 3600 + (+(m[2] ?? 0)) * 60 + (+(m[3] ?? 0)); };

/** Things everything else points at by @id, so every page describes one connected set of entities. */
const ID = {
  person: `${SITE}/#soham`, website: `${SITE}/#website`, app: `${SITE}/#app`, ios: `${SITE}/#app-ios`, mac: `${SITE}/#app-mac`,
  code: `${SITE}/#code`, film: `${SITE}/#film`, logo: `${SITE}/#logo`,
};
const ref = (id: string) => ({ "@id": id });

const esc = (s: string) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
const plain = (html: string) => html.replace(/<[^>]+>/g, "").replace(/&amp;/g, "&").replace(/&rsaquo;/g, "›").replace(/&nbsp;/g, " ").replace(/&middot;/g, "·");
const url = (p: Page) => SITE + p.path;
const json = (o: unknown) => JSON.stringify(o).replace(/</g, "\\u003c");

/** Vite input names: index.html keeps "main"; others are their path, "use/trackpad.html" -> "use-trackpad". */
export const inputs = () => Object.fromEntries(pages.map(p => [p.file === "index.html" ? "main" : p.file.replace(/\.html$/, "").replace(/\//g, "-"), p.file]));

/** Real app screens, with the size and words the Features pages use for them (home's four first). */
const SCREENS = (["trackpad", "actions", "remote", "media", ...Object.keys(SHOTS).filter(k => !["trackpad", "actions", "remote", "media"].includes(k))] as Shot[])
  .map(name => ({ "@type": "ImageObject", contentUrl: `${SITE}/img/screens/${name}.png`, url: `${SITE}/img/screens/${name}.png`, width: SHOTS[name].w, height: SHOTS[name].h, caption: SHOTS[name].alt }));

const free = { "@type": "Offer", price: "0", priceCurrency: "USD", availability: "https://schema.org/InStock", url: `${SITE}/install` };

/** The same on every page: who makes it, the site, the product and its two apps, the code and the film. */
function entities(withFilm: boolean): object[] {
  const person = {
    "@type": "Person", "@id": ID.person, name: AUTHOR, url: "https://sohamaggarwal.com",
    sameAs: ["https://github.com/Soham109", YOUTUBE],
  };
  const website = {
    "@type": "WebSite", "@id": ID.website, name: NAME, alternateName: "Glasspad for iPhone and Mac", url: `${SITE}/`,
    description: `${DEFINITION} ${TAGLINE}`, inLanguage: "en", publisher: ref(ID.person), author: ref(ID.person),
    about: ref(ID.app), copyrightHolder: ref(ID.person), license: LICENSE,
  };
  const logo = { "@type": "ImageObject", "@id": ID.logo, contentUrl: `${SITE}/icon-512.png`, url: `${SITE}/icon-512.png`, width: 512, height: 512, caption: "The Glasspad app icon" };
  const shared = {
    softwareVersion: VERSION, dateModified: RELEASED, releaseNotes: RELEASE,
    offers: free, isAccessibleForFree: true, license: LICENSE, author: ref(ID.person), publisher: ref(ID.person),
    installUrl: `${SITE}/install`, downloadUrl: RELEASE, softwareHelp: { "@type": "CreativeWork", name: "Glasspad Guide", url: `${SITE}/guide` },
  };
  const app = {
    "@type": "SoftwareApplication", "@id": ID.app, name: NAME, url: `${SITE}/`,
    description: `${DEFINITION} ${TAGLINE} It is an iPhone app and a Mac menu bar app that talk over your Wi-Fi.`,
    applicationCategory: "UtilitiesApplication", applicationSubCategory: "Remote control",
    operatingSystem: "macOS 14 or later, iOS 18 or later", availableOnDevice: ["iPhone", "Mac"],
    softwareRequirements: NEEDS.join("; "), featureList: FEATURES.map(([k, v]) => `${k}: ${v}`),
    ...shared, image: ref(ID.logo), screenshot: SCREENS,
    hasPart: [ref(ID.ios), ref(ID.mac)], subjectOf: withFilm ? [ref(ID.film), ref(ID.code)] : [ref(ID.code)], sameAs: [REPO],
  };
  const ios = {
    "@type": "MobileApplication", "@id": ID.ios, name: `${NAME} for iPhone`, url: `${SITE}/`,
    description: "The iPhone app: the trackpad, keyboard, remote, buttons and every other mode you touch.",
    applicationCategory: "UtilitiesApplication", operatingSystem: "iOS 18 or later", availableOnDevice: "iPhone",
    softwareRequirements: "An iPhone on iOS 18 or later, paired with the Glasspad Mac app on the same Wi-Fi",
    ...shared, image: ref(ID.logo), screenshot: SCREENS.slice(0, 4), isPartOf: ref(ID.app),
  };
  const mac = {
    "@type": "SoftwareApplication", "@id": ID.mac, name: `${NAME} for Mac`, url: `${SITE}/`,
    description: "The Mac menu bar app: it carries out what you do on the iPhone and renews the iPhone app over Wi-Fi.",
    applicationCategory: "UtilitiesApplication", operatingSystem: "macOS 14 or later", availableOnDevice: "Mac",
    softwareRequirements: "A Mac on macOS 14 or later, with Xcode 26 or later for the install",
    ...shared, image: ref(ID.logo), isPartOf: ref(ID.app),
  };
  const code = {
    "@type": "SoftwareSourceCode", "@id": ID.code, name: `${NAME} source code`, url: REPO, codeRepository: REPO,
    programmingLanguage: "Swift", runtimePlatform: ["iOS 18", "macOS 14"], license: LICENSE,
    author: ref(ID.person), targetProduct: ref(ID.app), version: VERSION,
  };
  const film = {
    "@type": "VideoObject", "@id": ID.film, name: FILM.name, description: FILM.description,
    thumbnailUrl: [`${SITE}/film.jpg`, `https://i.ytimg.com/vi/${FILM.id}/hqdefault.jpg`],
    uploadDate: FILM.uploadDate, duration: FILM.duration, embedUrl: FILM_EMBED, url: FILM_URL,
    inLanguage: "en", creator: ref(ID.person), author: ref(ID.person), about: ref(ID.app), isFamilyFriendly: true,
    transcript: FILM.transcript.join(" "),
    hasPart: FILM.chapters.map(([start, name], i) => ({
      "@type": "Clip", name, startOffset: start, endOffset: FILM.chapters[i + 1]?.[0] ?? seconds(FILM.duration), url: `${FILM_URL}&t=${start}s`,
    })),
  };
  return [person, website, logo, app, ios, mac, code, ...(withFilm ? [film] : [])];
}

/** The parts that belong to one page: the page itself, its breadcrumb, questions and steps. */
function schema(p: Page): object {
  const home = pages[0];
  const u = url(p);
  const c = CONTENT[p.path];
  const page: Record<string, unknown> = {
    "@type": "WebPage", "@id": `${u}#page`, url: u,
    name: p.title, headline: p.ogTitle ?? p.title, description: p.description, inLanguage: "en",
    isPartOf: ref(ID.website), about: ref(ID.app), author: ref(ID.person), publisher: ref(ID.person),
    dateModified: p.lastmod, primaryImageOfPage: image(p), image: image(p),
  };
  if (p === home) Object.assign(page, { mainEntity: ref(ID.app), video: ref(ID.film), significantLink: [`${SITE}/install`, `${SITE}/guide`, REPO] });
  if (p.crumb) page.breadcrumb = ref(`${u}#crumbs`);
  if (c?.kind === "compare") page.mentions = { "@type": "SoftwareApplication", name: c.them };
  const graph: object[] = [...entities(p === home), page];
  const qa = questions(p);
  if (qa) {
    graph.push({
      "@type": "FAQPage", "@id": `${u}#faq`, url: page.url, name: `Questions: ${p.crumb ?? NAME}`, inLanguage: "en",
      isPartOf: ref(`${u}#page`), about: ref(ID.app), dateModified: p.lastmod,
      mainEntity: qa.map(([q, a]) => ({ "@type": "Question", name: plain(q), acceptedAnswer: { "@type": "Answer", text: plain(a) } })),
    });
    page.hasPart = ref(`${u}#faq`);
  }
  if (p.crumb) graph.push({
    "@type": "BreadcrumbList", "@id": `${u}#crumbs`, name: `${p.crumb} | ${NAME}`,
    itemListElement: [{ name: NAME, item: `${SITE}/` }, { name: p.crumb, item: u }].map((x, i) => ({ "@type": "ListItem", position: i + 1, ...x })),
  });
  if (p.path === "/install") {
    graph.push({
      "@type": "HowTo", "@id": `${u}#howto`, name: "How to install Glasspad on a Mac and an iPhone", url: u,
      description: "Install Glasspad on your Mac and iPhone with one command in Terminal. The script builds the apps with Xcode and your free Apple ID, and waits for you where Apple needs a click.",
      inLanguage: "en", about: ref(ID.app), author: ref(ID.person), dateModified: p.lastmod, estimatedCost: { "@type": "MonetaryAmount", currency: "USD", value: 0 },
      tool: NEEDS.map(n => ({ "@type": "HowToTool", name: n })),
      step: HOWTO.map((s, i) => ({ "@type": "HowToStep", position: i + 1, name: s.name, text: s.text, url: i === 0 ? `${u}#get` : `${u}#stp-b${i}` })),
    });
    page.mainEntity = ref(`${u}#howto`);
  }
  return { "@context": "https://schema.org", "@graph": graph };
}

/** The page's questions as [question, answer HTML]: home and the guide from content.ts, the others from features.ts. */
const questions = (p: Page): [string, string][] | undefined => p.faq ? FAQS[p.faq].map(f => [f.q, f.a]) : pageFaq(p);

/** The page's main picture: its real app screen on Features pages, else the social card. */
function image(p: Page) {
  const s = pageImage(p);
  return s
    ? { "@type": "ImageObject", contentUrl: `${SITE}/img/screens/${s.name}.png`, url: `${SITE}/img/screens/${s.name}.png`, width: s.w, height: s.h, caption: s.alt }
    : { "@type": "ImageObject", contentUrl: OG.url, url: OG.url, width: OG.width, height: OG.height, caption: OG.alt };
}

function head(p: Page): string {
  const u = url(p);
  const og = p.ogTitle ?? p.title;
  const card = p.ogImage ? { ...OG, url: SITE + p.ogImage } : OG;
  return [
    `<title>${esc(p.title)}</title>`,
    `<meta name="description" content="${esc(p.description)}">`,
    ...(p.noindex ? [] : [`<link rel="canonical" href="${u}">`]),
    `<meta name="theme-color" content="#F2F1EE">`,
    `<link rel="icon" href="/favicon.ico" sizes="48x48">`,
    `<link rel="icon" href="/icon.svg" type="image/svg+xml">`,
    `<link rel="apple-touch-icon" href="/apple-touch-icon.png">`,
    `<link rel="manifest" href="/site.webmanifest">`,
    `<link rel="alternate" type="text/plain" href="/llms.txt" title="llms.txt">`,
    `<link rel="alternate" type="text/plain" href="/llms-full.txt" title="llms-full.txt">`,
    `<link rel="alternate" type="application/atom+xml" href="/changelog.xml" title="Glasspad releases">`,
    `<meta name="robots" content="${p.noindex ? "noindex, follow" : "index, follow, max-image-preview:large, max-snippet:-1, max-video-preview:-1"}">`,
    `<meta name="author" content="${AUTHOR}">`,
    `<meta property="og:type" content="${p.ogType ?? "website"}">`,
    `<meta property="og:site_name" content="${NAME}">`,
    `<meta property="og:locale" content="en_US">`,
    `<meta property="og:url" content="${u}">`,
    `<meta property="og:title" content="${esc(og)}">`,
    `<meta property="og:description" content="${esc(p.description)}">`,
    `<meta property="og:image" content="${card.url}">`,
    `<meta property="og:image:type" content="image/png">`,
    `<meta property="og:image:width" content="${OG.width}">`,
    `<meta property="og:image:height" content="${OG.height}">`,
    `<meta property="og:image:alt" content="${esc(OG.alt)}">`,
    ...(p.ogType === "article" ? [`<meta property="article:modified_time" content="${p.lastmod}">`, `<meta property="article:author" content="${AUTHOR}">`] : []),
    ...(p === pages[0] ? [
      `<meta property="og:video" content="${FILM_EMBED}">`,
      `<meta property="og:video:secure_url" content="${FILM_EMBED}">`,
      `<meta property="og:video:type" content="text/html">`,
      `<meta property="og:video:width" content="1280">`,
      `<meta property="og:video:height" content="720">`,
    ] : []),
    `<meta name="twitter:card" content="summary_large_image">`,
    `<meta name="twitter:title" content="${esc(og)}">`,
    `<meta name="twitter:description" content="${esc(p.description)}">`,
    `<meta name="twitter:image" content="${card.url}">`,
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

/** The film, for Google's video sitemap: only on home, the one page that shows it. */
const sitemapVideo = (p: Page): string => p !== pages[0] ? "" : `
    <video:video>
      <video:thumbnail_loc>${SITE}/film.jpg</video:thumbnail_loc>
      <video:title>${esc(FILM.name)}</video:title>
      <video:description>${esc(FILM.description)}</video:description>
      <video:player_loc>${FILM_EMBED}</video:player_loc>
      <video:duration>${seconds(FILM.duration)}</video:duration>
      <video:publication_date>${FILM.uploadDate}</video:publication_date>
      <video:family_friendly>yes</video:family_friendly>
      <video:requires_subscription>no</video:requires_subscription>
      <video:uploader>${AUTHOR}</video:uploader>
      <video:live>no</video:live>
    </video:video>`;

function sitemap(): string {
  const rows = pages.filter(p => !p.noindex).map(p => {
    const images = sitemapImages(p).map(i => `\n    <image:image><image:loc>${i}</image:loc></image:image>`).join("");
    return `  <url>\n    <loc>${url(p)}</loc>\n    <lastmod>${p.lastmod}</lastmod>${images}${sitemapVideo(p)}\n  </url>`;
  });
  return `<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9" xmlns:image="http://www.google.com/schemas/sitemap-image/1.1" xmlns:video="http://www.google.com/schemas/sitemap-video/1.1">\n${rows.join("\n")}\n</urlset>\n`;
}

const facts = () => [
  `- Modes: 11 named modes, buttons for more than 70 apps, up to 3 modes on one screen, 39 themes`,
  `- Made for: iPhone (iOS 18 or later) and Mac (macOS 14 or later). There is no Android, Windows or Linux version.`,
  `- Price: free, with nothing to buy and no subscription. License: MIT (open source). Source code: ${REPO}`,
  `- Latest version: ${VERSION}, released ${RELEASED}. Release notes: ${RELEASE}`,
  `- Not on the App Store: one command in Terminal builds it with Xcode 26 or later and installs it with a free Apple ID. A free Apple ID install stops opening after 7 days, so the Mac renews it over Wi-Fi.`,
  `- Private: paired once by QR code, encrypted, talks only over your Wi-Fi, no account and no cloud.`,
  `- Made by ${AUTHOR} (https://sohamaggarwal.com, https://github.com/Soham109)`,
];

/** The page list for llms.txt, grouped as the nav groups it. */
function pageList(): string[] {
  const line = (p: Page) => `- [${p.crumb ?? "Home"}](${url(p)}): ${p.summary}`;
  return [
    "## Pages", "", ...pages.filter(p => !p.group && !p.noindex).map(line), "",
    "## Feature pages", "", ...pages.filter(p => p.group === "feature").map(line), "",
    "## Comparison pages", "", ...pages.filter(p => p.group === "compare").map(line), "",
  ];
}

const intro = () => [
  `# ${NAME}`,
  "",
  `> ${DEFINITION} ${TAGLINE}`,
  "",
  ...facts(),
  "",
];

function llms(): string {
  const [film, full, ...rest] = [LINKS.find(l => l[1].includes("youtube.com")), LINKS.find(l => l[1].endsWith("llms-full.txt")), ...LINKS.filter(l => !l[1].includes("youtube.com") && !l[1].endsWith("llms-full.txt"))];
  return [
    ...intro(),
    ...pageList(),
    "## Project",
    "",
    ...rest.map(l => `- [${l![0]}](${l![1]}): ${l![2]}`),
    `- [Changelog](${CHANGES}): every release, newest first`,
    "",
    "## Optional",
    "",
    ...[full, film].filter(Boolean).map(l => `- [${l![0]}](${l![1]}): ${l![2]}`),
    "",
  ].join("\n");
}

/** The newest release's section of CHANGELOG.md, headings moved down a level to sit under "## Latest release". */
function latestRelease(root: string): string[] {
  try {
    const text = readFileSync(join(root, "..", "CHANGELOG.md"), "utf8");
    const parts = text.split(/^## /m).slice(1);
    const first = parts.find(x => !x.startsWith("[Unreleased]"));
    if (!first) return [];
    const [title, ...body] = first.trim().split("\n");
    const [, version, date] = /\[(.+?)\]\s*-\s*(\S+)/.exec(title) ?? [, title, ""];
    const lines = body.join("\n").trim().split("\n").filter((l, i, all) => !(l === "" && all[i - 1] === ""));
    return ["## Latest release", "", `Version ${version}${date ? `, released ${date}` : ""}. Full history: ${CHANGES}`, "", ...lines, ""];
  } catch { return []; }
}

function llmsFull(root: string): string {
  const qa = (k: string) => FAQS[k].flatMap(f => [`### ${plain(f.q)}`, "", plain(f.a), ""]);
  return [
    ...intro(),
    "A small menu bar app on your Mac and an app on your iPhone, on the same Wi-Fi. Pick a mode on the iPhone and it controls the Mac.",
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
    `Full steps with pictures: ${SITE}/install`,
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
    "## Demo film",
    "",
    `${FILM.name} (${seconds(FILM.duration)} seconds, on YouTube): ${FILM_URL}`,
    "",
    FILM.description,
    "",
    "Chapters:",
    "",
    ...FILM.chapters.map(([t, n]) => `- ${Math.floor(t / 60)}:${String(t % 60).padStart(2, "0")} ${n}`),
    "",
    "Transcript:",
    "",
    FILM.transcript.join(" "),
    "",
    "## Questions",
    "",
    ...qa("home"),
    ...qa("guide"),
    ...pages.filter(p => p.group).flatMap(p => {
      const c = CONTENT[p.path];
      return [`## ${p.crumb}`, "", `Page: ${url(p)}`, "", plain(c.answer), "", ...c.faq.flatMap(([q, a]) => [`### ${plain(q)}`, "", plain(a), ""])];
    }),
    ...latestRelease(root),
    ...pageList(),
    "## Project",
    "",
    ...LINKS.filter(l => !l[1].endsWith("llms-full.txt")).map(([t, h, d]) => `- [${t}](${h}): ${d}`),
    `- [Changelog](${CHANGES}): every release, newest first`,
    "",
  ].join("\n");
}

export function site(): Plugin {
  let pub = "", root = "";
  const FILES: Record<string, [string, () => string | Buffer]> = {
    "sitemap.xml": ["application/xml", sitemap],
    "llms.txt": ["text/plain; charset=utf-8", llms],
    "llms-full.txt": ["text/plain; charset=utf-8", () => llmsFull(root)],
    "changelog.xml": ["application/atom+xml; charset=utf-8", () => changelogFeed(root)],
    "press/glasspad-press-kit.zip": ["application/zip", () => pressKit(root, [...intro(), `Press kit: ${SITE}/press`, `Contact: hello@sohamaggarwal.com`, ""].join("\n"))],
  };
  return {
    name: "glasspad-site",
    configResolved(c) { pub = c.publicDir; root = c.root; },
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
      if (html.includes("<!--site:changelog-->")) html = html.replace("<!--site:changelog-->", changelogHtml(root));
      html = icons(html);
      // the theme line as guide.ts writes it, so it is in the page without JavaScript
      html = html.replace(/(<li data-themes>)[^<]*(<\/li>)/, `$1Settings, then Theme. ${themesLine()} System follows your iPhone.$2`);
      return pictures(html, pub);
    },
    configurePreviewServer(server) {
      return () => { server.middlewares.use(notFound(join(server.config.root, server.config.build.outDir))); };
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
