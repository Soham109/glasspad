/* Every page of the site, in one list.

   The build (site/plugin.ts) reads this list for the Vite inputs, sitemap.xml, llms.txt and
   llms-full.txt, every page's <head> (title, description, canonical URL, social cards and
   structured data), and the nav and footer, which list the Features and Compare pages in the
   order below.

   To add a feature or comparison page: add an entry here with `group`, write its content in
   site/features.ts under the same path, and run `npm run build` (scripts/learn.mjs writes the
   small HTML file Vite needs; the build fills it in). Home and the guide are hand written. */

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
  /** <title>. Keep it under about 60 characters. */
  title: string;
  /** meta description and social card text: 120 to 160 characters */
  description: string;
  /** date of the last real change to the page, YYYY-MM-DD (sitemap lastmod) */
  lastmod: string;
  /** one line for llms.txt */
  summary: string;
  /** breadcrumb name; every page but home has one */
  crumb?: string;
  /** "feature" pages are listed under Features in the nav and footer, "compare" pages under Compare */
  group?: "feature" | "compare";
  /** short name in the nav and footer, for pages with a group */
  nav?: string;
  /** one line under the name in the nav menu and in related pages, for pages with a group */
  blurb?: string;
  /** icon key in site/icons.ts, for feature pages */
  icon?: string;
  /** "article" for pages that read like one */
  ogType?: "website" | "article";
  /** social card title when it should differ from the <title> */
  ogTitle?: string;
  /** FAQ list from content.ts shown on this page (home and guide; feature pages keep theirs in features.ts) */
  faq?: string;
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

  // Features, in nav order
  {
    path: "/use/iphone-as-mac-trackpad", file: "use/iphone-as-mac-trackpad.html", group: "feature", icon: "trackpad",
    nav: "Trackpad", blurb: "Click, scroll and swipe, with a tap you can feel.",
    crumb: "iPhone as a Mac trackpad", lastmod: "2026-10-16", ogType: "article",
    title: "Use your iPhone as a Mac trackpad, free | Glasspad",
    ogTitle: "Use your iPhone as a Mac trackpad",
    description: "Turn your iPhone into a trackpad for your Mac over Wi-Fi: click with haptics, scroll, pinch, and swipe between Spaces. Free and open source.",
    summary: "Use your iPhone as a trackpad for your Mac over Wi-Fi: click with haptics, scroll, pinch, and swipe between Spaces.",
  },
  {
    path: "/use/iphone-as-mac-keyboard", file: "use/iphone-as-mac-keyboard.html", group: "feature", icon: "keyboard",
    nav: "Keyboard", blurb: "Type or dictate on the iPhone, and it lands on the Mac.",
    crumb: "iPhone as a Mac keyboard", lastmod: "2026-10-16", ogType: "article",
    title: "Use your iPhone as a Mac keyboard | Glasspad",
    ogTitle: "Use your iPhone as a Mac keyboard",
    description: "Type or dictate on your iPhone and the text lands on your Mac, with command, option, control, shortcuts, arrows and F1 to F12. Free and open source.",
    summary: "Type or dictate on your iPhone and the text lands on your Mac, with modifier keys, shortcuts, arrows and F1 to F12.",
  },
  {
    path: "/use/iphone-remote-for-mac", file: "use/iphone-remote-for-mac.html", group: "feature", icon: "remote",
    nav: "Remote", blurb: "Netflix and YouTube from the couch, like a Siri Remote.",
    crumb: "iPhone remote for Mac", lastmod: "2026-10-16", ogType: "article",
    title: "iPhone remote for your Mac: Netflix, YouTube and more | Glasspad",
    ogTitle: "An iPhone remote for your Mac",
    description: "Control Netflix, YouTube, Apple TV and Spotify on your Mac from your iPhone: tap to pause, swipe to skip, Skip Intro and Subtitles. Free and open source.",
    summary: "Control Netflix, YouTube, Apple TV and Spotify on your Mac from your iPhone: tap to pause, swipe to skip, Skip Intro and Subtitles.",
  },
  {
    path: "/use/stream-deck-alternative-mac", file: "use/stream-deck-alternative-mac.html", group: "feature", icon: "actions",
    nav: "Actions", blurb: "Buttons for the app in front, and your own. A free Stream Deck.",
    crumb: "Free Stream Deck alternative", lastmod: "2026-10-16", ogType: "article",
    title: "A free Stream Deck alternative for Mac, on your iPhone | Glasspad",
    ogTitle: "A free Stream Deck alternative for Mac",
    description: "Use your iPhone as a Stream Deck for your Mac: buttons that follow the app in front, plus your own apps, websites, shortcuts and macros. Free, no key limits.",
    summary: "Your iPhone as a Stream Deck for your Mac: buttons that follow the app in front, plus your own apps, websites, shortcuts and macros.",
  },
  {
    path: "/use/mac-split-screen-from-iphone", file: "use/mac-split-screen-from-iphone.html", group: "feature", icon: "split",
    nav: "Split Screen", blurb: "Two windows side by side, or in quarters, in one tap.",
    crumb: "Split screen from iPhone", lastmod: "2026-10-16", ogType: "article",
    title: "Split screen on your Mac from your iPhone | Glasspad",
    ogTitle: "Split screen on your Mac from your iPhone",
    description: "Put two Mac windows side by side, top and bottom or in quarters with one tap on your iPhone, on any display. Plus the Mac's own split screen shortcuts.",
    summary: "Put two Mac windows side by side, top and bottom or in quarters with one tap on your iPhone, on any display.",
  },
  {
    path: "/use/control-mac-displays-from-iphone", file: "use/control-mac-displays-from-iphone.html", group: "feature", icon: "displays",
    nav: "Displays", blurb: "Every display and window. Move, tile and dim them.",
    crumb: "Displays and windows", lastmod: "2026-10-16", ogType: "article",
    title: "Control your Mac's displays and windows from iPhone | Glasspad",
    ogTitle: "Control your Mac's displays and windows from your iPhone",
    description: "See every display and window on your Mac from your iPhone. Move windows between displays, tile them, and set brightness, resolution and Night Shift.",
    summary: "See every display and window on your Mac from your iPhone, move and tile windows, and set brightness, resolution and Night Shift.",
  },

  // Comparisons, in nav order
  {
    path: "/compare/stream-deck-mobile", file: "compare/stream-deck-mobile.html", group: "compare",
    nav: "vs Stream Deck Mobile", blurb: "Keys, price and plugins, side by side.",
    crumb: "Glasspad vs Stream Deck Mobile", lastmod: "2026-10-16", ogType: "article",
    title: "Glasspad vs Stream Deck Mobile for Mac | Glasspad",
    ogTitle: "Glasspad vs Stream Deck Mobile",
    description: "How Glasspad and Elgato's Stream Deck Mobile compare: keys, price, plugins and what else your iPhone can do for your Mac.",
    summary: "How Glasspad and Elgato's Stream Deck Mobile compare: keys, price, plugins and what else your iPhone can do for your Mac.",
  },
  {
    path: "/compare/remote-mouse", file: "compare/remote-mouse.html", group: "compare",
    nav: "vs Remote Mouse", blurb: "Platforms, price and install, side by side.",
    crumb: "Glasspad vs Remote Mouse", lastmod: "2026-10-16", ogType: "article",
    title: "Glasspad vs Remote Mouse: an open source alternative | Glasspad",
    ogTitle: "Glasspad vs Remote Mouse",
    description: "How Glasspad and Remote Mouse compare: platforms, price, install, trackpad and extras. Glasspad is free and open source for iPhone and Mac.",
    summary: "How Glasspad and Remote Mouse compare: platforms, price, install, trackpad and extras.",
  },
  {
    path: "/compare/universal-control", file: "compare/universal-control.html", group: "compare",
    nav: "vs Universal Control", blurb: "What it does, and why it skips the iPhone.",
    crumb: "Glasspad vs Universal Control", lastmod: "2026-10-16", ogType: "article",
    title: "Universal Control with iPhone? Glasspad vs Universal Control",
    ogTitle: "Glasspad vs Universal Control",
    description: "Universal Control does not work with iPhone. Here is what it does, how it differs from iPhone Mirroring, and how to control a Mac from an iPhone.",
    summary: "Universal Control does not work with iPhone: what it does, how it differs from iPhone Mirroring, and how to control a Mac from an iPhone.",
  },
];

export const featurePages = () => pages.filter(p => p.group === "feature");
export const comparePages = () => pages.filter(p => p.group === "compare");
