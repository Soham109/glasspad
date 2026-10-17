/* Build-time parts of the pages added for a complete site (site/plugin.ts calls these):
   - the Changelog page and its Atom feed, both read from ../CHANGELOG.md, so the site never
     disagrees with the repository;
   - the press kit zip (app icon, brand files and real app screens), written into the build;
   - <i data-icon="name"></i> in a hand written page becomes that line icon from site/icons.ts. */

import { readFileSync, readdirSync, existsSync } from "node:fs";
import { join } from "node:path";
import { deflateRawSync } from "node:zlib";
import { SITE, REPO } from "./pages";
import { icon } from "./icons";
import { esc } from "./render";

/* ------------------------------------------------------------------ changelog */

export interface Release { version: string; date: string; intro: string[]; groups: { title: string; items: string[] }[] }

/** The few Markdown forms CHANGELOG.md uses: **bold**, `code` and [links](url). Input is escaped first. */
const inline = (md: string) => esc(md)
  .replace(/`([^`]+)`/g, "<code>$1</code>")
  .replace(/\*\*([^*]+)\*\*/g, "<b>$1</b>")
  .replace(/\[([^\]]+)\]\(([^)\s]+)\)/g, '<a href="$2">$1</a>');

/** Every released version in CHANGELOG.md, newest first. An empty Unreleased section is skipped. */
export function releases(root: string): Release[] {
  const text = readFileSync(join(root, "..", "CHANGELOG.md"), "utf8");
  return text.split(/^## /m).slice(1).flatMap(part => {
    const [title, ...lines] = part.split("\n");
    const m = /^\[(.+?)\](?:\s*-\s*(\S+))?/.exec(title.trim());
    if (!m || m[1].toLowerCase() === "unreleased") return [];
    const r: Release = { version: m[1], date: m[2] ?? "", intro: [], groups: [] };
    for (const raw of lines) {
      const line = raw.trimEnd();
      if (!line || /^\[[^\]]+\]:\s/.test(line)) continue;
      if (line.startsWith("### ")) r.groups.push({ title: line.slice(4).trim(), items: [] });
      else if (/^[-*] /.test(line) && r.groups.length) r.groups.at(-1)!.items.push(inline(line.slice(2)));
      else if (/^\s+\S/.test(raw) && r.groups.at(-1)?.items.length) { const g = r.groups.at(-1)!; g.items[g.items.length - 1] += " " + inline(line.trim()); }
      else if (!r.groups.length) r.intro.push(inline(line));
    }
    return [r];
  });
}

const tagUrl = (v: string) => `${REPO}/releases/tag/v${v}`;
const longDate = (d: string) => d ? new Date(d + "T12:00:00Z").toLocaleDateString("en-US", { year: "numeric", month: "long", day: "numeric", timeZone: "UTC" }) : "";
const count = (r: Release) => r.groups.reduce((n, g) => n + g.items.length, 0);

function releaseBody(r: Release): string {
  return [
    ...r.intro.map(p => `<p class="cl-intro">${p}</p>`),
    ...r.groups.map(g => `<div class="cl-group"><h3><span class="cl-tag cl-${g.title.toLowerCase()}">${esc(g.title)}</span></h3><ul>${g.items.map(i => `<li>${i}</li>`).join("")}</ul></div>`),
    `<p class="cl-more"><a href="${tagUrl(r.version)}">Release ${esc(r.version)} on GitHub</a></p>`,
  ].join("\n");
}

/** The Changelog page's list: the newest release open, older ones folded so the page stays short. */
export function changelogHtml(root: string): string {
  return releases(root).map((r, i) => {
    const head = `<span class="cl-v">${esc(r.version)}</span>${i === 0 ? '<span class="cl-latest">Latest</span>' : ""}<time datetime="${r.date}">${longDate(r.date)}</time>`;
    return i === 0
      ? `<article class="cl-rel" id="v${esc(r.version)}"><header class="cl-head"><h2>${head}</h2></header>${releaseBody(r)}</article>`
      : `<details class="cl-rel" id="v${esc(r.version)}"><summary class="cl-head"><h2>${head}</h2><span class="cl-n">${count(r)} ${count(r) === 1 ? "change" : "changes"}</span>${icon("chevron", 16, "pg-faq-chev")}</summary>${releaseBody(r)}</details>`;
  }).join("\n");
}

/** An Atom feed of releases, for feed readers: /changelog.xml. */
export function changelogFeed(root: string): string {
  const all = releases(root);
  const x = (s: string) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
  const entries = all.map(r => `  <entry>
    <title>Glasspad ${x(r.version)}</title>
    <id>${SITE}/changelog#v${x(r.version)}</id>
    <link rel="alternate" type="text/html" href="${SITE}/changelog#v${x(r.version)}"/>
    <link rel="related" type="text/html" href="${tagUrl(r.version)}"/>
    <updated>${r.date}T12:00:00Z</updated>
    <published>${r.date}T12:00:00Z</published>
    <summary>${x(r.groups.map(g => `${g.title}: ${g.items.length}`).join(", "))}</summary>
    <content type="html">${x(releaseBody(r))}</content>
  </entry>`).join("\n");
  return `<?xml version="1.0" encoding="utf-8"?>
<feed xmlns="http://www.w3.org/2005/Atom" xml:lang="en">
  <title>Glasspad releases</title>
  <subtitle>Every Glasspad release, newest first.</subtitle>
  <id>${SITE}/changelog</id>
  <link rel="self" type="application/atom+xml" href="${SITE}/changelog.xml"/>
  <link rel="alternate" type="text/html" href="${SITE}/changelog"/>
  <icon>${SITE}/icon-192.png</icon>
  <author><name>Soham Aggarwal</name><uri>https://sohamaggarwal.com</uri></author>
  <rights>MIT License</rights>
  <updated>${all[0]?.date ?? "2026-01-01"}T12:00:00Z</updated>
${entries}
</feed>
`;
}

/* ------------------------------------------------------------------ icons in hand written pages */

export const icons = (html: string) => html.replace(/<i data-icon="([a-z-]+)"(?: data-size="(\d+)")?><\/i>/g, (_, k: string, n?: string) => icon(k, n ? +n : 22));

/* ------------------------------------------------------------------ press kit zip */

const CRC = Array.from({ length: 256 }, (_, n) => { let c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1; return c >>> 0; });
const crc32 = (b: Buffer) => { let c = 0xffffffff; for (const x of b) c = CRC[(c ^ x) & 0xff] ^ (c >>> 8); return (c ^ 0xffffffff) >>> 0; };

/** A plain .zip (deflate), so the press kit needs no extra package. */
function zip(files: [string, Buffer][]): Buffer {
  const local: Buffer[] = [], central: Buffer[] = [];
  let offset = 0;
  for (const [name, data] of files) {
    const n = Buffer.from(name, "utf8"), packed = deflateRawSync(data, { level: 9 }), crc = crc32(data);
    const h = Buffer.alloc(30);
    h.writeUInt32LE(0x04034b50, 0); h.writeUInt16LE(20, 4); h.writeUInt16LE(0x0800, 6); h.writeUInt16LE(8, 8);
    h.writeUInt16LE(0, 10); h.writeUInt16LE(0x5d51, 12); // 2026-10-17, so builds are byte for byte the same
    h.writeUInt32LE(crc, 14); h.writeUInt32LE(packed.length, 18); h.writeUInt32LE(data.length, 22); h.writeUInt16LE(n.length, 26);
    local.push(h, n, packed);
    const c = Buffer.alloc(46);
    c.writeUInt32LE(0x02014b50, 0); c.writeUInt16LE(20, 4); c.writeUInt16LE(20, 6); c.writeUInt16LE(0x0800, 8); c.writeUInt16LE(8, 10);
    c.writeUInt16LE(0, 12); c.writeUInt16LE(0x5d51, 14);
    c.writeUInt32LE(crc, 16); c.writeUInt32LE(packed.length, 20); c.writeUInt32LE(data.length, 24); c.writeUInt16LE(n.length, 28);
    c.writeUInt32LE(offset, 42);
    central.push(c, n);
    offset += 30 + n.length + packed.length;
  }
  const dir = Buffer.concat(central), end = Buffer.alloc(22);
  end.writeUInt32LE(0x06054b50, 0); end.writeUInt16LE(files.length, 8); end.writeUInt16LE(files.length, 10);
  end.writeUInt32LE(dir.length, 12); end.writeUInt32LE(offset, 16);
  return Buffer.concat([...local, dir, end]);
}

/** Everything in docs/brand (the icon and any brand art) and docs/img/screens (real app screens), plus a facts sheet. */
export function pressKit(root: string, facts: string): Buffer {
  const docs = join(root, "..", "docs");
  const take = (dir: string, into: string): [string, Buffer][] => existsSync(join(docs, dir))
    ? readdirSync(join(docs, dir)).filter(f => /\.(png|svg|jpe?g)$/i.test(f)).sort().map(f => [`glasspad-press-kit/${into}/${f}`, readFileSync(join(docs, dir, f))])
    : [];
  return zip([
    ["glasspad-press-kit/README.txt", Buffer.from(facts, "utf8")],
    ...take("brand", "brand"),
    ...take("img/screens", "screenshots"),
  ]);
}

/* ------------------------------------------------------------------ 404 in vite preview */

/** For `vite preview`: an address with no page gets dist/404.html with status 404, as Vercel serves it. */
export const notFound = (dist: string) => (req: { url?: string }, res: { statusCode: number; setHeader(k: string, v: string): void; end(b: Buffer): void }, next: () => void) => {
  const path = decodeURIComponent((req.url ?? "/").split("?")[0]);
  const page = join(dist, "404.html");
  if (existsSync(join(dist, path)) && !path.endsWith("/") || path === "/" || !existsSync(page)) return next();
  res.statusCode = 404;
  res.setHeader("Content-Type", "text/html; charset=utf-8");
  res.end(readFileSync(page));
};
