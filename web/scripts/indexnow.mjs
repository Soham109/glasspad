// Tells Bing (and through it ChatGPT search, Copilot, DuckDuckGo and Yahoo), Yandex, Seznam
// and Naver that the site's pages changed, using IndexNow (https://www.indexnow.org).
// One request to api.indexnow.org is shared with every engine that takes part.
//
// Run after each deploy, from web/:   node scripts/indexnow.mjs
//   --dry-run   print what would be sent, send nothing
//   --local     read the page list from dist/sitemap.xml instead of the live sitemap
//
// The key is the name of the one 32 character .txt file in public/ (its contents are the same
// key). The live site must serve that file, so the script checks it first and stops if not.
import { readdirSync, readFileSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const HOST = "glasspad.sohamaggarwal.com";
const ORIGIN = `https://${HOST}`;
const ENDPOINT = "https://api.indexnow.org/indexnow";
const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const args = new Set(process.argv.slice(2));
const dryRun = args.has("--dry-run");
const local = args.has("--local");

const keys = readdirSync(join(root, "public")).filter(f => /^[0-9a-f]{32}\.txt$/.test(f));
if (keys.length !== 1) throw new Error(`expected one IndexNow key file in public/, found ${keys.length}`);
const key = keys[0].slice(0, -4);
if (readFileSync(join(root, "public", keys[0]), "utf8").trim() !== key) throw new Error("key file contents do not match its name");
const keyLocation = `${ORIGIN}/${key}.txt`;

const sitemap = local
  ? readFileSync(join(root, "dist", "sitemap.xml"), "utf8")
  : await (await fetch(`${ORIGIN}/sitemap.xml`)).text();
// Page addresses only: <loc> directly inside <url>, not the <image:loc> entries.
const urlList = [...sitemap.matchAll(/<url>\s*<loc>([^<]+)<\/loc>/g)].map(m => m[1].trim());
if (!urlList.length) throw new Error("no page addresses found in the sitemap");
const foreign = urlList.filter(u => new URL(u).host !== HOST);
if (foreign.length) throw new Error(`sitemap lists addresses on another host: ${foreign.join(", ")}`);

const body = { host: HOST, key, keyLocation, urlList };
console.log(`indexnow: ${urlList.length} pages, key ${key}`);
for (const u of urlList) console.log(`  ${u}`);
if (dryRun) { console.log("dry run: nothing sent"); process.exit(0); }

const live = await fetch(keyLocation);
const liveText = live.ok ? (await live.text()).trim() : "";
if (liveText !== key) {
  console.error(`stopped: ${keyLocation} answered ${live.status}${live.ok ? " with other contents" : ""}. Deploy first, then run again.`);
  process.exit(1);
}

const res = await fetch(ENDPOINT, {
  method: "POST",
  headers: { "Content-Type": "application/json; charset=utf-8" },
  body: JSON.stringify(body),
});
const meaning = {
  200: "received",
  202: "received; the key is still being checked, which is normal the first time",
  400: "the request was malformed",
  403: "the key was not accepted (key file missing or different)",
  422: "an address is not on this host, or the key does not match",
  429: "too many submissions; wait before trying again",
}[res.status] ?? "unexpected answer";
console.log(`indexnow: ${res.status} ${meaning}`);
const text = await res.text();
if (text) console.log(text);
if (res.status !== 200 && res.status !== 202) process.exit(1);
