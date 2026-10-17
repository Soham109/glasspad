import { defineConfig } from "vite";
import { site, inputs } from "./site/plugin";

// Pages are listed once, in site/pages.ts.
export default defineConfig({
  // a multi page site: an unknown address is a 404 (dist/404.html), never the home page
  appType: "mpa",
  plugins: [site()],
  build: {
    target: "es2020", cssMinify: true, assetsInlineLimit: 0, modulePreload: { polyfill: false },
    rollupOptions: { input: inputs() },
  },
});
