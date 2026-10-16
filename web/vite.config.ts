import { defineConfig } from "vite";

export default defineConfig({
  build: {
    target: "es2020", cssMinify: true, assetsInlineLimit: 0, modulePreload: { polyfill: false },
    rollupOptions: { input: { main: "index.html", guide: "guide.html",
      "use/iphone-as-mac-trackpad": "use/iphone-as-mac-trackpad.html",
      "use/iphone-as-mac-keyboard": "use/iphone-as-mac-keyboard.html",
      "use/iphone-remote-for-mac": "use/iphone-remote-for-mac.html",
      "use/stream-deck-alternative-mac": "use/stream-deck-alternative-mac.html",
      "use/mac-split-screen-from-iphone": "use/mac-split-screen-from-iphone.html",
      "use/control-mac-displays-from-iphone": "use/control-mac-displays-from-iphone.html",
      "compare/remote-mouse": "compare/remote-mouse.html",
      "compare/stream-deck-mobile": "compare/stream-deck-mobile.html",
      "compare/universal-control": "compare/universal-control.html",
    } },
  },
});
