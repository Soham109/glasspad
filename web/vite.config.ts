import { defineConfig } from "vite";

export default defineConfig({
  build: {
    target: "es2020", cssMinify: true, assetsInlineLimit: 0, modulePreload: { polyfill: false },
    rollupOptions: { input: { main: "index.html", guide: "guide.html" } },
  },
});
