// Checks the structured data (JSON-LD, the block search engines read) in every built web page.
// For each .html file under the given folder (default web/dist) it checks that:
//   - the page has at least one <script type="application/ld+json"> block and each one is valid JSON;
//   - every @type is a real schema.org type, and every property is one schema.org allows on that
//     type (or on a type it inherits from);
//   - every {"@id": ...} reference points at something defined on the same page.
// The schema.org vocabulary is a pinned release, downloaded once and checked against its SHA-256.
// Usage: node scripts/release/check-jsonld.mjs [web/dist]   (run `npm run build` in web/ first)
// Exits 1 on any problem. Needs Node 18 or later and network access the first time.
import { readFileSync, readdirSync, writeFileSync, existsSync, mkdirSync } from "node:fs";
import { createHash } from "node:crypto";
import { join, relative } from "node:path";
import { tmpdir } from "node:os";

const VOCAB_VERSION = "30.1";
const VOCAB_URL = `https://raw.githubusercontent.com/schemaorg/schemaorg/v${VOCAB_VERSION}/data/releases/${VOCAB_VERSION}/schemaorg-current-https.jsonld`;
const VOCAB_SHA256 = "0a4b8c4c910fc831ec8695196510973390906a5ee34dc6b862dfec4d21a12f74";

const dist = process.argv[2] ?? "web/dist";
if (!existsSync(dist)) { console.error(`No ${dist}. Run npm run build in web/ first.`); process.exit(1); }

async function vocabulary() {
  const dir = process.env.SCHEMA_CACHE ?? join(tmpdir(), "glasspad-schemaorg");
  const file = join(dir, `schemaorg-${VOCAB_VERSION}.jsonld`);
  let text = existsSync(file) ? readFileSync(file) : null;
  const sum = b => createHash("sha256").update(b).digest("hex");
  if (!text || sum(text) !== VOCAB_SHA256) {
    const res = await fetch(VOCAB_URL);
    if (!res.ok) throw new Error(`Could not download the schema.org vocabulary: HTTP ${res.status}`);
    text = Buffer.from(await res.arrayBuffer());
    if (sum(text) !== VOCAB_SHA256) throw new Error("The schema.org vocabulary did not match its pinned SHA-256.");
    mkdirSync(dir, { recursive: true });
    writeFileSync(file, text);
  }
  return JSON.parse(text.toString("utf8"))["@graph"];
}

const short = s => s.replace(/^schema:/, "");
const list = v => [].concat(v ?? []);
const types = {}, props = {};
for (const n of await vocabulary()) {
  const t = list(n["@type"]);
  if (t.includes("rdfs:Class")) types[short(n["@id"])] = list(n["rdfs:subClassOf"]).map(x => short(x["@id"]));
  if (t.includes("rdf:Property")) props[short(n["@id"])] = list(n["schema:domainIncludes"]).map(x => short(x["@id"]));
}
// Data types (Text, URL, Number...) are classes too, so they appear in types[] as well.
const ancestors = t => {
  const out = new Set([t]), todo = [t];
  while (todo.length) for (const p of types[todo.pop()] ?? []) if (!out.has(p)) { out.add(p); todo.push(p); }
  return out;
};

const htmlFiles = dir => readdirSync(dir, { withFileTypes: true }).flatMap(e =>
  e.isDirectory() ? htmlFiles(join(dir, e.name)) : e.name.endsWith(".html") ? [join(dir, e.name)] : []);

let problems = 0, blocksSeen = 0;
const problem = (file, msg) => { problems++; console.log(`${file}: ${msg}`); };

for (const path of htmlFiles(dist).sort()) {
  const file = relative(dist, path);
  const html = readFileSync(path, "utf8");
  const blocks = [...html.matchAll(/<script type="application\/ld\+json">([\s\S]*?)<\/script>/g)];
  if (!blocks.length) { problem(file, "no JSON-LD block"); continue; }
  const defined = new Set(), referenced = [];
  const walk = (node, at) => {
    if (Array.isArray(node)) return node.forEach((n, i) => walk(n, `${at}[${i}]`));
    if (!node || typeof node !== "object") return;
    const keys = Object.keys(node);
    if (node["@id"] && keys.length === 1) referenced.push([node["@id"], at]);
    else if (node["@id"]) defined.add(node["@id"]);
    for (const t of list(node["@type"])) {
      if (!types[t]) { problem(file, `unknown type ${t} at ${at}`); continue; }
      const anc = ancestors(t);
      for (const k of keys) {
        if (k.startsWith("@")) continue;
        if (!props[k]) problem(file, `unknown property ${k} on ${t} at ${at}`);
        else if (!props[k].some(d => anc.has(d))) problem(file, `property ${k} is not expected on ${t} at ${at}`);
      }
    }
    for (const [k, v] of Object.entries(node)) walk(v, `${at}.${k}`);
  };
  for (const [i, b] of blocks.entries()) {
    blocksSeen++;
    let data;
    try { data = JSON.parse(b[1]); } catch (e) { problem(file, `block ${i + 1} is not valid JSON: ${e.message}`); continue; }
    if (data["@context"] !== "https://schema.org") problem(file, `block ${i + 1} @context is ${JSON.stringify(data["@context"])}, expected "https://schema.org"`);
    walk(data, `$${blocks.length > 1 ? i + 1 : ""}`);
  }
  for (const [id, at] of referenced) if (!defined.has(id)) problem(file, `${at} points at ${id}, which this page does not define`);
}

console.log(problems ? `JSON-LD: ${problems} problems` : `JSON-LD: ${blocksSeen} blocks checked against schema.org ${VOCAB_VERSION}, no problems`);
process.exit(problems ? 1 : 0);
