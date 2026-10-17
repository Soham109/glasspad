/* Every page of the site, in one list.

   To add a page, write the HTML file and add an entry below. The build then adds it to the Vite
   inputs, sitemap.xml, llms.txt and llms-full.txt, and, when it has `learn`, to the Learn list in
   every footer (scripts/learn.mjs reads the same list for the Learn pages).
   A page whose <head> has <!--site:head--> also gets its title, description, canonical URL, social
   cards and structured data from here; it then needs `title` and `description`. The Learn pages
   (use/, compare/) write their own <head> in scripts/learn.mjs. */

export const SITE = "https://glasspad.sohamaggarwal.com";
export const REPO = "https://github.com/Soham109/glasspad";
export const VERSION = "0.1.2";
export const RELEASE = `${REPO}/releases/tag/v${VERSION}`;
export const RELEASED = "2026-10-16";

export interface Page {
  /** URL path, without .html: "/" or "/guide" */
  path: string;
  /** source HTML file, relative to web/ */
  file: string;
  /** <title>, for pages with <!--site:head-->. Keep it under about 60 characters. */
  title?: string;
  /** meta description and social card text, for pages with <!--site:head-->: 120 to 160 characters */
  description?: string;
  /** date of the last real change to the page, YYYY-MM-DD (sitemap lastmod) */
  lastmod: string;
  /** one line for llms.txt */
  summary: string;
  /** breadcrumb name; every page but home has one */
  crumb?: string;
  /** link text in the footer's Learn list, in list order. Leave out to keep the page out of it. */
  learn?: string;
  /** "article" for pages that read like one */
  ogType?: "website" | "article";
  /** FAQ list from content.ts shown on this page (rendered at <!--site:faq-->, and as FAQPage data) */
  faq?: string;
  /** extra schema.org nodes for this page */
  schema?: object[];
}

export const pages: Page[] = [
  {
    path: "/",
    file: "index.html",
    title: "Glasspad: your iPhone as a Mac trackpad, keyboard and remote",
    description: "Glasspad is a free, open source app that turns your iPhone into a control surface for your Mac: trackpad, keyboard, remote, Dock, app buttons and split screen.",
    lastmod: "2026-10-16",
    summary: "What Glasspad does, the demo film, how to install it, and common questions.",
    faq: "home",
  },
  {
    path: "/guide",
    file: "guide.html",
    title: "Glasspad Guide: every mode, Layouts and help",
    description: "How to use Glasspad on your iPhone and Mac: setting up, Trackpad, Keyboard, Media, Remote, Actions, Displays, split screen Layouts, StandBy, themes and help.",
    lastmod: "2026-10-16",
    summary: "How to use every mode, Layouts, Actions, StandBy and themes, how Glasspad compares with similar tools, and help.",
    crumb: "Guide",
    ogType: "article",
    faq: "guide",
  },

  // Learn pages, written by scripts/learn.mjs. Their footer list follows this order.
  { path: "/use/iphone-as-mac-trackpad", file: "use/iphone-as-mac-trackpad.html", crumb: "iPhone as a Mac trackpad", learn: "iPhone as a Mac trackpad", lastmod: "2026-10-16", ogType: "article",
    summary: "Use your iPhone as a trackpad for your Mac over Wi-Fi: click with haptics, scroll, pinch, and swipe between Spaces." },
  { path: "/use/iphone-as-mac-keyboard", file: "use/iphone-as-mac-keyboard.html", crumb: "iPhone as a Mac keyboard", learn: "iPhone as a Mac keyboard", lastmod: "2026-10-16", ogType: "article",
    summary: "Type or dictate on your iPhone and the text lands on your Mac, with modifier keys, shortcuts, arrows and F1 to F12." },
  { path: "/use/iphone-remote-for-mac", file: "use/iphone-remote-for-mac.html", crumb: "iPhone remote for Mac", learn: "iPhone remote for Mac", lastmod: "2026-10-16", ogType: "article",
    summary: "Control Netflix, YouTube, Apple TV and Spotify on your Mac from your iPhone: tap to pause, swipe to skip, Skip Intro and Subtitles." },
  { path: "/use/stream-deck-alternative-mac", file: "use/stream-deck-alternative-mac.html", crumb: "Free Stream Deck alternative", learn: "Free Stream Deck alternative", lastmod: "2026-10-16", ogType: "article",
    summary: "Your iPhone as a Stream Deck for your Mac: buttons that follow the app in front, plus your own apps, websites, shortcuts and macros." },
  { path: "/use/mac-split-screen-from-iphone", file: "use/mac-split-screen-from-iphone.html", crumb: "Split screen from iPhone", learn: "Split screen from iPhone", lastmod: "2026-10-16", ogType: "article",
    summary: "Put two Mac windows side by side, top and bottom or in quarters with one tap on your iPhone, on any display." },
  { path: "/use/control-mac-displays-from-iphone", file: "use/control-mac-displays-from-iphone.html", crumb: "Displays and windows", learn: "Displays and windows", lastmod: "2026-10-16", ogType: "article",
    summary: "See every display and window on your Mac from your iPhone, move and tile windows, and set brightness, resolution and Night Shift." },
  { path: "/compare/remote-mouse", file: "compare/remote-mouse.html", crumb: "Glasspad vs Remote Mouse", learn: "Glasspad vs Remote Mouse", lastmod: "2026-10-16", ogType: "article",
    summary: "How Glasspad and Remote Mouse compare: platforms, price, install, trackpad and extras." },
  { path: "/compare/stream-deck-mobile", file: "compare/stream-deck-mobile.html", crumb: "Glasspad vs Stream Deck Mobile", learn: "Glasspad vs Stream Deck Mobile", lastmod: "2026-10-16", ogType: "article",
    summary: "How Glasspad and Elgato's Stream Deck Mobile compare: keys, price, plugins and what else your iPhone can do for your Mac." },
  { path: "/compare/universal-control", file: "compare/universal-control.html", crumb: "Glasspad vs Universal Control", learn: "Glasspad vs Universal Control", lastmod: "2026-10-16", ogType: "article",
    summary: "Universal Control does not work with iPhone: what it does, how it differs from iPhone Mirroring, and how to control a Mac from an iPhone." },
];
