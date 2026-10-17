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
export const VERSION = "0.3.0";
export const RELEASE = `${REPO}/releases/tag/v${VERSION}`;
export const RELEASED = "2026-10-17";

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
  /** kept out of search results, the sitemap and llms.txt (the 404 page) */
  noindex?: boolean;
  /** this page's own social card, a 1200 x 630 PNG in public/ ("/og/press.png"); the site card when unset */
  ogImage?: string;
}

export const pages: Page[] = [
  {
    path: "/",
    file: "index.html",
    title: "Glasspad: your iPhone as a Mac trackpad, keyboard and remote",
    description: "Glasspad is a free, open source app that turns your iPhone into a trackpad, keyboard, media remote and button deck for your Mac, over Wi-Fi, with no account.",
    lastmod: "2026-10-17",
    summary: "What Glasspad does, the demo video, how to install it, and common questions.",
    faq: "home",
  },
  {
    path: "/guide",
    file: "guide.html",
    title: "How to use Glasspad for iPhone and Mac: every mode and help",
    description: "How to use Glasspad on your iPhone and Mac: setting up, Trackpad, Keyboard, Media, Remote, Actions, Displays, split screen Layouts, StandBy, themes and help.",
    lastmod: "2026-10-17",
    summary: "How to use every mode, Layouts, Actions, StandBy and themes, how Glasspad compares with similar tools, and help.",
    crumb: "Guide",
    ogType: "article",
    faq: "guide",
  },
  {
    path: "/install",
    file: "install.html",
    title: "Install Glasspad on your Mac and iPhone | Glasspad",
    ogTitle: "Install Glasspad",
    description: "Install Glasspad with one command in Terminal: what you need, every step with pictures, automatic renewal with a free Apple ID, troubleshooting and uninstall.",
    lastmod: "2026-10-17",
    summary: "How to install Glasspad: one Terminal command, what you need, every step with pictures, troubleshooting and uninstall.",
    crumb: "Install",
    ogType: "article",
  },

  {
    path: "/about", file: "about.html", crumb: "About", lastmod: "2026-10-17", ogType: "website",
    title: "About Glasspad and its developer, Soham Aggarwal",
    description: "Glasspad is a free, open source iPhone and Mac app made by Soham Aggarwal. Who makes it, how to get in touch, and where the code lives.",
    summary: "Who makes Glasspad, how to contact the developer, and where the source code is.",
  },
  {
    path: "/privacy", file: "privacy.html", crumb: "Privacy", lastmod: "2026-10-17", ogType: "website",
    title: "Glasspad Privacy Policy: no accounts, no tracking",
    description: "Glasspad collects no data. The iPhone and Mac apps talk only over your Wi-Fi, encrypted, with no account, analytics or tracking. The site uses no cookies.",
    summary: "Privacy policy: no data collection, no account, encrypted Wi-Fi link, no cookies on the site.",
  },
  {
    path: "/terms", file: "terms.html", crumb: "Terms", lastmod: "2026-10-17", ogType: "website",
    title: "Glasspad Terms of Use",
    description: "Glasspad is free, open source software under the MIT license, provided as it is. The terms for using the apps and this website.",
    summary: "Terms of use: MIT license, no warranty, not affiliated with Apple or other companies named.",
  },

  {
    path: "/support", file: "support.html", crumb: "Support", lastmod: "2026-10-17", ogType: "website",
    title: "Glasspad Support: help, troubleshooting and contact",
    description: "Get help with Glasspad: the guide, install troubleshooting, the 7 day renewal, reporting a bug on GitHub, and email for anything else.",
    summary: "Where to get help: the guide, install troubleshooting, renewal, GitHub issues for bugs and ideas, and email.",
  },
  {
    path: "/changelog", file: "changelog.html", crumb: "Changelog", lastmod: "2026-10-17", ogType: "website",
    title: "Glasspad Changelog: what is new in each release",
    description: "Every Glasspad release for iPhone and Mac, newest first: what was added, changed and fixed. Also as an Atom feed and on GitHub Releases.",
    summary: "Every release, newest first, built from CHANGELOG.md, with an Atom feed at /changelog.xml.",
  },
  {
    path: "/press", file: "press.html", crumb: "Press kit", lastmod: "2026-10-17", ogType: "website",
    title: "Glasspad Press Kit: descriptions, facts, icon and screenshots",
    description: "Everything to write about Glasspad: one line and long descriptions, the facts, the app icon, real app screenshots in one download, and how to reach the developer.",
    summary: "Press kit: descriptions, facts, app icon, real screenshots as files or one zip, logo use and press contact.",
  },
  {
    path: "/accessibility", file: "accessibility.html", crumb: "Accessibility", lastmod: "2026-10-17", ogType: "website",
    title: "Glasspad Accessibility: VoiceOver, Reduce Motion and more",
    description: "What the Glasspad apps and this website support for accessibility today, such as VoiceOver, Reduce Motion, larger text and contrast, what is not there yet, and how to tell me.",
    summary: "Accessibility statement: what the apps and site support (VoiceOver, Reduce Motion, Dynamic Type, contrast), known gaps, and contact.",
  },
  // Features, in nav order
  {
    path: "/use/iphone-as-mac-trackpad", file: "use/iphone-as-mac-trackpad.html", group: "feature", icon: "trackpad",
    nav: "Trackpad", blurb: "Click, scroll and swipe, with a tap you can feel.",
    crumb: "iPhone as a Mac mouse and trackpad", lastmod: "2026-10-17", ogType: "article",
    title: "Use your iPhone as a mouse or trackpad for Mac | Glasspad",
    ogTitle: "Use your iPhone as a mouse and trackpad for your Mac",
    description: "Use your iPhone as a mouse and trackpad for your Mac or Mac mini over Wi-Fi: click with haptics, scroll, pinch, swipe between Spaces. Free and open source.",
    summary: "Use your iPhone as a mouse and trackpad for your Mac over Wi-Fi: click with haptics, scroll, pinch, and swipe between Spaces. Why there is no built-in way, and setup steps.",
  },
  {
    path: "/use/iphone-as-mac-keyboard", file: "use/iphone-as-mac-keyboard.html", group: "feature", icon: "keyboard",
    nav: "Keyboard", blurb: "Type or dictate on the iPhone, and it lands on the Mac.",
    crumb: "iPhone as a Mac keyboard", lastmod: "2026-10-17", ogType: "article",
    title: "Use your iPhone as a Mac keyboard | Glasspad",
    ogTitle: "Use your iPhone as a Mac keyboard",
    description: "Type or dictate on your iPhone and the text lands on your Mac, with Command, Option, Control, shortcuts, arrows and F1 to F12. Free and open source.",
    summary: "Type or dictate on your iPhone and the text lands on your Mac, with modifier keys, shortcuts, arrows and F1 to F12.",
  },
  {
    path: "/use/iphone-remote-for-mac", file: "use/iphone-remote-for-mac.html", group: "feature", icon: "remote",
    nav: "Remote", blurb: "Netflix and YouTube from the couch, like a Siri Remote.",
    crumb: "iPhone remote for Mac", lastmod: "2026-10-17", ogType: "article",
    title: "A remote for your Mac or MacBook, on your iPhone | Glasspad",
    ogTitle: "Your iPhone as a remote for your Mac",
    description: "Control Netflix, YouTube, Spotify and the volume on your Mac or MacBook from your iPhone: tap to pause, swipe to skip, Skip Intro. Free and open source.",
    summary: "Your iPhone as a remote for your Mac: Netflix, YouTube and Apple TV with a Siri Remote style pad, Spotify and Music with Media, and the Mac's volume and sound output.",
  },
  {
    path: "/use/iphone-presentation-remote-mac", file: "use/iphone-presentation-remote-mac.html", group: "feature", icon: "display",
    nav: "Present", blurb: "A clicker for PowerPoint and Keynote, with a laser.",
    crumb: "iPhone presentation remote", lastmod: "2026-10-17", ogType: "article",
    title: "iPhone clicker for PowerPoint and Keynote on Mac | Glasspad",
    ogTitle: "Use your iPhone as a presentation remote for your Mac",
    description: "Use your iPhone as a clicker for PowerPoint, Keynote and Google Slides on your Mac: Next and Back, a laser on the slides and a talk timer. Free and open source.",
    summary: "Use your iPhone as a presentation remote for PowerPoint, Keynote and Google Slides on a Mac: Next and Back, a laser on the slides' display and a talk timer. No speaker notes on the phone.",
  },
  {
    path: "/use/stream-deck-alternative-mac", file: "use/stream-deck-alternative-mac.html", group: "feature", icon: "actions",
    nav: "Actions", blurb: "Buttons for the app in front, and your own. A free Stream Deck.",
    crumb: "Free Stream Deck alternative", lastmod: "2026-10-17", ogType: "article",
    title: "Turn an old iPhone into a free Stream Deck for Mac | Glasspad",
    ogTitle: "A free Stream Deck for your Mac, on an iPhone you own",
    description: "Use any iPhone on iOS 18 as a Stream Deck for your Mac: buttons that follow the app in front, plus apps, websites, shortcuts and macros. Free, no key limits.",
    summary: "Your iPhone as a Stream Deck for your Mac: buttons that follow the app in front, plus your own apps, websites, shortcuts and macros.",
  },
  {
    path: "/use/mac-split-screen-from-iphone", file: "use/mac-split-screen-from-iphone.html", group: "feature", icon: "split",
    nav: "Split Screen", blurb: "Two windows side by side, or in quarters, in one tap.",
    crumb: "Split screen from iPhone", lastmod: "2026-10-17", ogType: "article",
    title: "Split screen on your Mac from your iPhone | Glasspad",
    ogTitle: "Split screen on your Mac from your iPhone",
    description: "Every Mac split screen and tiling shortcut on macOS 15 and later, what to do on macOS 14, and how to split windows with one tap on your iPhone.",
    summary: "Put two Mac windows side by side, top and bottom or in quarters with one tap on your iPhone, on any display.",
  },
  {
    path: "/use/control-mac-displays-from-iphone", file: "use/control-mac-displays-from-iphone.html", group: "feature", icon: "displays",
    nav: "Displays", blurb: "Every display and window. Move, tile and dim them.",
    crumb: "Displays and windows", lastmod: "2026-10-17", ogType: "article",
    title: "Control your Mac's displays and windows from iPhone | Glasspad",
    ogTitle: "Control your Mac's displays and windows from your iPhone",
    description: "See every display and window on your Mac from your iPhone. Move windows between displays, tile them, and set brightness, resolution and Night Shift.",
    summary: "See every display and window on your Mac from your iPhone, move and tile windows, and set brightness, resolution and Night Shift.",
  },
  {
    path: "/use/iphone-to-mac-clipboard", file: "use/iphone-to-mac-clipboard.html", group: "feature", icon: "clipboard",
    nav: "Clipboard", blurb: "Send text and images to the Mac when paste fails.",
    crumb: "Copy from iPhone to Mac", lastmod: "2026-10-17", ogType: "article",
    title: "Copy from iPhone to Mac not working? Send it | Glasspad",
    ogTitle: "Copy text and images from your iPhone to your Mac",
    description: "Why copy and paste from iPhone to Mac fails, the fixes for Universal Clipboard, and how to send text, links and images both ways with one tap instead.",
    summary: "Why Universal Clipboard fails between iPhone and Mac, the fixes, and how Glasspad's Clipboard sends text, links and images both ways on a tap.",
  },
  {
    path: "/use/control-mac-from-iphone", file: "use/control-mac-from-iphone.html", group: "feature", icon: "compare",
    nav: "All the ways", blurb: "Screen Sharing, Switch Control or Glasspad: which fits.",
    crumb: "Control your Mac from your iPhone", lastmod: "2026-10-17", ogType: "article",
    title: "How to control your Mac from your iPhone | Glasspad",
    ogTitle: "How to control your Mac from your iPhone",
    description: "Every way to control a Mac from an iPhone: Screen Sharing and remote desktop to see the screen, Switch Control, and Glasspad as a trackpad, keyboard and remote.",
    summary: "Every way to control a Mac from an iPhone, and which to pick: Screen Sharing or remote desktop apps to see the screen, Switch Control, or Glasspad as a trackpad, keyboard and remote on the same Wi-Fi.",
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
    crumb: "Glasspad vs Remote Mouse", lastmod: "2026-10-17", ogType: "article",
    title: "Remote Mouse alternative for Mac: Glasspad vs Remote Mouse",
    ogTitle: "Glasspad vs Remote Mouse",
    description: "How Glasspad and Remote Mouse compare: platforms, price, install, trackpad and extras. Glasspad is free and open source for iPhone and Mac.",
    summary: "How Glasspad and Remote Mouse compare: platforms, price, install, trackpad and extras.",
  },
  {
    path: "/compare/mobile-mouse", file: "compare/mobile-mouse.html", group: "compare",
    nav: "vs Mobile Mouse", blurb: "Price, platforms and gestures, side by side.",
    crumb: "Glasspad vs Mobile Mouse", lastmod: "2026-10-17", ogType: "article",
    title: "Glasspad vs Mobile Mouse for iPhone and Mac | Glasspad",
    ogTitle: "Glasspad vs Mobile Mouse",
    description: "How Glasspad and Mobile Mouse compare on iPhone and Mac: price, platforms, install, trackpad gestures and extras. Glasspad is free and open source.",
    summary: "How Glasspad and Mobile Mouse compare: price, platforms, install, trackpad gestures and extras.",
  },
  {
    path: "/compare/coast", file: "compare/coast.html", group: "compare",
    nav: "vs Coast", blurb: "Price, devices and buttons, side by side.",
    crumb: "Glasspad vs Coast", lastmod: "2026-10-17", ogType: "article",
    title: "Glasspad vs Coast for iPhone and Mac | Glasspad",
    ogTitle: "Glasspad vs Coast",
    description: "How Glasspad and Coast compare on iPhone and Mac: price, Pro features, devices, install, trackpad and buttons. Glasspad is free and open source.",
    summary: "How Glasspad and Coast compare: price, Coast Pro, devices, install, trackpad and buttons.",
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
  {
    path: "/404", file: "404.html", lastmod: "2026-10-17", noindex: true,
    title: "Page not found | Glasspad",
    description: "This page does not exist. Go to the Glasspad home page, the install steps, the guide or support.",
    summary: "Page not found.",
  },
];

export const featurePages = () => pages.filter(p => p.group === "feature");
export const comparePages = () => pages.filter(p => p.group === "compare");
