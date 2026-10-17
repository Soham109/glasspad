// Finds broken links in the built website.
// Reads every .html file under the given folder (default web/dist), plus sitemap.xml, robots.txt,
// llms.txt and llms-full.txt, and checks each href, src and srcset:
//   - links inside the site (relative, or starting with https://glasspad.sohamaggarwal.com) must
//     point at a file in the build, with the clean URLs the host serves (/guide is guide.html),
//     and a #part must match an id on that page;
//   - with --external, links to other sites are fetched too. Sites that turn away automated
//     requests (HTTP 403, 429 or 999) are listed as warnings, not failures.
// Usage: node scripts/release/check-links.mjs [web/dist] [--external]
// Exits 1 on any broken link. Needs Node 18 or later.
import { readFileSync, readdirSync, existsSync, statSync } from "node:fs";
import { join, relative, posix } from "node:path";

const args = process.argv.slice(2);
const external = args.includes("--external");
const dist = args.find(a => !a.startsWith("--")) ?? "web/dist";
const SITE = "https://glasspad.sohamaggarwal.com";
if (!existsSync(dist)) { console.error(`No ${dist}. Run npm run build in web/ first.`); process.exit(1); }

const walk = dir => readdirSync(dir, { withFileTypes: true }).flatMap(e =>
  e.isDirectory() ? walk(join(dir, e.name)) : [join(dir, e.name)]);
const files = walk(dist).map(f => relative(dist, f).split("\\").join("/"));
const pages = files.filter(f => f.endsWith(".html"));
const texts = ["sitemap.xml", "robots.txt", "llms.txt", "llms-full.txt"].filter(f => files.includes(f));

/** The file the host serves for a site path, or null. Mirrors cleanUrls in web/public/vercel.json. */
function served(path) {
  const p = decodeURIComponent(path).replace(/^\/+/, "").replace(/\/+$/, "");
  for (const c of p === "" ? ["index.html"] : [p, `${p}.html`, `${p}/index.html`])
    if (existsSync(join(dist, c)) && statSync(join(dist, c)).isFile()) return c;
  return null;
}

const ids = new Map();
const idsOf = file => {
  if (!ids.has(file)) ids.set(file, new Set([...readFileSync(join(dist, file), "utf8").matchAll(/\s(?:id|name)="([^"]+)"/g)].map(m => m[1])));
  return ids.get(file);
};

/** url -> the files that link to it */
const links = new Map();
const add = (url, from) => { url = url.trim().replace(/&amp;/g, "&"); if (url) (links.get(url) ?? links.set(url, new Set()).get(url)).add(from); };
for (const f of pages) {
  const html = readFileSync(join(dist, f), "utf8").replace(/<script type="application\/ld\+json">[\s\S]*?<\/script>/g, "");
  for (const m of html.matchAll(/\s(href|src|srcset|poster)="([^"]*)"/g)) {
    if (m[1] === "srcset") for (const part of m[2].split(",")) add(part.trim().split(/\s+/)[0], f);
    else add(m[2], f);
  }
}
for (const f of texts) for (const m of readFileSync(join(dist, f), "utf8").matchAll(/https?:\/\/[^\s)<>"'\]]+/g)) add(m[0].replace(/[.,;:]+$/, ""), f);

let broken = 0, warned = 0, checked = 0;
const outside = [];
for (const [url, from] of links) {
  if (/^(mailto|tel|data|javascript|sms):/i.test(url)) continue;
  const local = url.startsWith(SITE) ? url.slice(SITE.length) || "/" : url;
  if (/^[a-z][a-z0-9+.-]*:|^\/\//i.test(local)) { outside.push([url, from]); continue; }
  for (const page of from) {
    checked++;
    const [pathPart, hash] = local.split("#");
    const path = pathPart.split("?")[0];
    // Relative links resolve against the linking page's folder; text files only hold absolute URLs.
    const base = posix.dirname("/" + page);
    const target = path === "" ? (page.endsWith(".html") ? page : null) : served(path.startsWith("/") ? path : posix.join(base, path));
    if (!target) { broken++; console.log(`MISSING  ${url}  (in ${page})`); continue; }
    if (hash && target.endsWith(".html") && !idsOf(target).has(decodeURIComponent(hash))) {
      broken++; console.log(`NO ANCHOR  ${url}  (in ${page})`);
    }
  }
}

if (external) {
  const check = async ([url, from]) => {
    const tries = [{ method: "HEAD" }, { method: "GET" }, { method: "GET" }];
    let status = "no answer";
    for (const [i, opt] of tries.entries()) {
      if (i) await new Promise(r => setTimeout(r, 1500 * i));
      try {
        const res = await fetch(url, { ...opt, redirect: "follow", signal: AbortSignal.timeout(20000),
          headers: { "user-agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) glasspad-link-check", accept: "*/*" } });
        status = res.status;
        if (res.ok) return;
        // Some servers answer HEAD wrongly, so a failed HEAD always moves on to GET.
        if (opt.method === "GET" && status < 500 && status !== 429) break;
      } catch (e) { status = e.cause?.code ?? e.name; }
    }
    const where = [...from].join(", ");
    if ([403, 429, 999].includes(status)) { warned++; console.log(`WARNING ${status}  ${url}  (in ${where}): the site turns away automated checks`); }
    else { broken++; console.log(`BROKEN ${status}  ${url}  (in ${where})`); }
  };
  for (let i = 0; i < outside.length; i += 8) await Promise.all(outside.slice(i, i + 8).map(check));
}

console.log(`Links: ${checked} inside the site${external ? ` and ${outside.length} outside it` : ` checked (${outside.length} outside links skipped; add --external)`}, ${broken} broken${warned ? `, ${warned} warnings` : ""}`);
process.exit(broken ? 1 : 0);
