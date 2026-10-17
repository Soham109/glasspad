import { defineConfig } from "vite";
import { site, inputs } from "./site/plugin";

// Pages are listed once, in site/pages.ts.
export default defineConfig({
  plugins: [site()],
  build: {
    target: "es2020", cssMinify: true, assetsInlineLimit: 0, modulePreload: { polyfill: false },
    rollupOptions: { input: inputs() },
  },
});
