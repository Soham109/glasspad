import { defineConfig } from "vite";
import { readFileSync, existsSync } from "node:fs";

// <!--shot:file.png|alt text--> becomes a figure only when docs/img/file.png exists.
function screenshots() {
  return {
    name: "glasspad-screenshots",
    transformIndexHtml(html: string) {
      const list: string[] = existsSync("src/screens.json") ? JSON.parse(readFileSync("src/screens.json", "utf8")) : [];
      return html.replace(/<!--shot:([^|]+)\|([^>]*?)-->/g, (_m, file: string, alt: string) =>
        list.includes(file) ? `<figure class="shot"><img src="/img/${file}" alt="${alt}" loading="lazy" decoding="async"></figure>` : "");
    },
  };
}

export default defineConfig({
  plugins: [screenshots()],
  build: { target: "es2020", cssMinify: true, assetsInlineLimit: 0, modulePreload: { polyfill: false } },
});
