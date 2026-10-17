// Writes the Learn pages (web/use/*.html and web/compare/*.html) from the text below, so every
// page shares one head, nav, install block, footer and product facts. Run `node scripts/learn.mjs`
// after changing a page here, and commit the HTML it writes.
import { writeFileSync, mkdirSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { pages as SITE_PAGES, VERSION, RELEASE } from "../site/pages.ts";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const SITE = "https://glasspad.sohamaggarwal.com";
const UPDATED = "2026-10-16";
const INSTALL = "curl -fsSL https://raw.githubusercontent.com/Soham109/glasspad/main/install.sh | bash";

/* One sentence of product facts, the same on every page. */
const FACTS = "Glasspad is free and open source (MIT). It needs a Mac on macOS 14 or later and an iPhone on iOS 18 or later, on the same Wi-Fi.";

/* Real screenshots from docs/img/screens (copied to /img/screens by sync-screens.mjs). */
const SHOT = {
  trackpad: { w: 640, h: 349, land: true, alt: "Trackpad, sideways, with three finger dots" },
  keyboard: { w: 350, h: 644, alt: "Keyboard: modifier keys, shortcuts and arrows above the iPhone keyboard" },
  remote: { w: 350, h: 644, alt: "Remote for a film on Netflix in Safari: a large touch pad, skip and pause buttons, then Search, Skip Intro, Full Screen and Mute" },
  media: { w: 350, h: 644, alt: "Media: artwork, the song, scrubber, controls, volume and brightness" },
  actions: { w: 350, h: 644, alt: "Actions: Safari's buttons on top, Pinned buttons below" },
  library: { w: 350, h: 644, alt: "Library: search, Pinned, Record New Macro, and apps with add buttons" },
  folder: { w: 350, h: 644, alt: "Actions with the Windows folder open: Left Half, Right Half, Fill, Split Screen and Next Display" },
  website: { w: 350, h: 644, alt: "Edit Button for a GitHub website button, with name, symbol, color and size" },
  displays: { w: 350, h: 644, alt: "Displays: two displays drawn as in System Settings, and the list of windows on them" },
  clipboard: { w: 350, h: 644, alt: "Clipboard: Send to Mac with Paste, Get from Mac with its button" },
  menu: { w: 350, h: 644, alt: "The mode menu: Trackpad, Keyboard, Media, Dock and Actions, then Layouts, then Clipboard, Present, Remote and Displays" },
};

/* The Learn list in every footer: the pages with `learn` in site/pages.ts, in that order. */
const PAGES = SITE_PAGES.filter(p => p.learn).map(p => ({ path: p.path, label: p.learn }));

const esc = s => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
const plain = html => html.replace(/<[^>]+>/g, "").replace(/&amp;/g, "&").replace(/&rsaquo;/g, "›").replace(/&nbsp;/g, " ").replace(/\s+/g, " ").trim();

function fig(name, cls = "") {
  const s = SHOT[name];
  return `<figure class="g-fig${cls}"><img src="/img/screens/${name}.png" width="${s.w}" height="${s.h}" alt="${esc(s.alt)}" loading="lazy" decoding="async"></figure>`;
}
const list = items => `<ul>\n${items.map(i => `        <li>${i}</li>`).join("\n")}\n      </ul>`;

/* A screenshot beside its points, as the guide lays them out. */
function row(name, title, items) {
  const land = SHOT[name].land;
  return `  <div class="g-row${land ? " land" : ""}">
    ${fig(name)}
    <div class="g-text">${title ? `<h3>${title}</h3>` : ""}
      ${list(items)}
    </div>
  </div>`;
}

function table(them, rows) {
  return `  <div class="lp-table" role="table" aria-label="Glasspad and ${esc(them)} side by side">
    <div class="lp-tr lp-th" role="row"><span role="columnheader"></span><span role="columnheader">Glasspad</span><span role="columnheader">${them}</span></div>
${rows.map(([k, g, t]) => `    <div class="lp-tr" role="row"><span class="lp-k" role="rowheader">${k}</span><span role="cell" data-l="Glasspad">${g}</span><span role="cell" data-l="${esc(them)}">${t}</span></div>`).join("\n")}
  </div>`;
}

function picks(them, theirs, ours) {
  return `  <div class="g-grid lp-picks">
    <article class="g-card"><div class="g-text"><h3>Choose ${them} if</h3>
      ${list(theirs)}
    </div></article>
    <article class="g-card"><div class="g-text"><h3>Choose Glasspad if</h3>
      ${list(ours)}
    </div></article>
  </div>`;
}

function page(p) {
  const url = SITE + p.path;
  const faqLd = p.faq.map(([q, a]) => ({ "@type": "Question", name: q, acceptedAnswer: { "@type": "Answer", text: plain(a) } }));
  const ld = {
    "@context": "https://schema.org",
    "@graph": [
      {
        "@type": "WebPage", "@id": url + "#page", url, name: p.title, description: p.desc,
        inLanguage: "en", dateModified: UPDATED,
        isPartOf: { "@type": "WebSite", "@id": SITE + "/#website", name: "Glasspad", url: SITE + "/" },
        about: { "@id": SITE + "/#app" },
        primaryImageOfPage: { "@type": "ImageObject", url: `${SITE}/img/screens/${p.shot}.png` },
        breadcrumb: { "@id": url + "#crumbs" },
      },
      {
        "@type": "BreadcrumbList", "@id": url + "#crumbs",
        itemListElement: [
          { "@type": "ListItem", position: 1, name: "Glasspad", item: SITE + "/" },
          { "@type": "ListItem", position: 2, name: p.crumb, item: url },
        ],
      },
      { "@type": "FAQPage", "@id": url + "#faq", mainEntity: faqLd },
      {
        "@type": "SoftwareApplication", "@id": SITE + "/#app", name: "Glasspad", url: SITE + "/",
        description: "A control surface for your Mac, on your iPhone: a trackpad, keyboard, media remote and button deck, over your Wi-Fi.",
        applicationCategory: "UtilitiesApplication", operatingSystem: "macOS 14+, iOS 18+", softwareVersion: VERSION, downloadUrl: RELEASE,
        softwareRequirements: "Xcode 26 or later and a free Apple ID to install; iPhone and Mac on the same Wi-Fi",
        license: "https://opensource.org/licenses/MIT", isAccessibleForFree: true,
        offers: { "@type": "Offer", price: "0", priceCurrency: "USD" },
        author: { "@type": "Person", "@id": SITE + "/#soham", name: "Soham Aggarwal", url: "https://sohamaggarwal.com" },
      },
    ],
  };
  const learn = PAGES.map(l => l.path === p.path
    ? `      <li><a href="${l.path}" aria-current="page">${l.label}</a></li>`
    : `      <li><a href="${l.path}">${l.label}</a></li>`).join("\n");

  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<title>${esc(p.title)}</title>
<meta name="description" content="${esc(p.desc)}">
<meta name="theme-color" content="#F2F1EE">
<script>document.documentElement.classList.add("js")</script>
<link rel="icon" href="/favicon.ico" sizes="48x48">
<link rel="icon" href="/icon.svg" type="image/svg+xml">
<link rel="apple-touch-icon" href="/apple-touch-icon.png">
<link rel="manifest" href="/site.webmanifest">
<link rel="alternate" type="text/plain" href="/llms.txt" title="llms.txt">
<link rel="canonical" href="${url}">
<meta property="og:title" content="${esc(p.og || p.h1)}">
<meta property="og:description" content="${esc(p.desc)}">
<meta property="og:url" content="${url}">
<meta property="og:site_name" content="Glasspad">
<meta property="og:image" content="${SITE}/og-light.png">
<meta property="og:image:width" content="1200">
<meta property="og:image:height" content="630">
<meta property="og:image:alt" content="Glasspad: a control surface for your Mac, on your iPhone">
<meta property="og:type" content="article">
<meta name="twitter:card" content="summary_large_image">
<meta name="twitter:image" content="${SITE}/og-light.png">
<meta name="twitter:image:alt" content="Glasspad: a control surface for your Mac, on your iPhone">
<script type="application/ld+json">${JSON.stringify(ld)}</script>
</head>
<body>
<a class="skip" href="#main">Skip to content</a>
<svg width="0" height="0" class="sr-sprite" aria-hidden="true"><defs>
  <symbol id="i-github" viewBox="0 0 16 16"><path fill="currentColor" d="M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27.68 0 1.36.09 2 .27 1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.013 8.013 0 0016 8c0-4.42-3.58-8-8-8z"/></symbol>
  <symbol id="i-copy" viewBox="0 0 24 24"><rect x="8.5" y="8.5" width="11" height="11" rx="2.5"/><path d="M15.5 8.5V6.5A2 2 0 0 0 13.5 4.5h-7a2 2 0 0 0-2 2v7a2 2 0 0 0 2 2h2"/></symbol>
  <symbol id="i-check" viewBox="0 0 24 24"><path d="m5 12.5 4.5 4.5L19 7.5"/></symbol>
</defs></svg>

<header class="nav" id="nav">
  <a class="brand" href="/" aria-label="Glasspad home">
    <img src="/icon.svg" width="26" height="26" alt="">
    <span>Glasspad</span>
  </a>
  <nav class="nav-links" aria-label="Site" id="navLinks">
    <span class="nav-ind" id="navInd" aria-hidden="true"></span>
    <a href="/#modes">Modes</a>
    <a href="/guide">Guide</a>
    <a href="#install">Install</a>
  </nav>
  <a class="nav-gh" href="https://github.com/Soham109/glasspad" aria-label="Glasspad on GitHub">
    <svg width="18" height="18" aria-hidden="true"><use href="#i-github"/></svg>
  </a>
  <button class="nav-menu" id="navMenu" aria-expanded="false" aria-controls="navSheet">Menu</button>
</header>
<nav class="nav-sheet" id="navSheet" aria-label="Site">
  <a href="/">Home</a>
  <a href="/#modes">Modes</a>
  <a href="/guide">Guide</a>
  <a href="#install">Install</a>
</nav>

<main id="main" class="g lp">

<header class="g-hero wrap lp-hero">
  <h1>${p.h1}</h1>
  <p class="lp-answer">${p.answer}</p>
  <div class="lp-cta">
    <a class="btn btn-ink" href="#install">Install Glasspad</a>
    <a class="btn btn-quiet" href="${p.guide[0]}">${p.guide[1]}</a>
  </div>
</header>

${p.body}

<!-- FAQ -->
<section class="g-sec wrap" id="faq" aria-labelledby="faq-t">
  <h2 id="faq-t">Questions</h2>
  <dl class="g-help">
${p.faq.map(([q, a]) => `    <dt>${q}</dt>\n    <dd>${a}</dd>`).join("\n")}
  </dl>
</section>
${p.sources ? `
<section class="g-sec wrap lp-sources" aria-labelledby="src-t">
  <h2 id="src-t">Sources</h2>
  <p>Checked on 16 October 2026. Prices are from the US App Store and can differ in other countries.</p>
  <ul>
${p.sources.map(([t, u]) => `    <li><a href="${u}">${t}</a></li>`).join("\n")}
  </ul>
</section>
` : ""}
<!-- Install -->
<section class="g-sec wrap" id="install" aria-labelledby="install-t">
  <h2 id="install-t">Install</h2>
  <p class="lp-need">${FACTS} To install, you also need Xcode 26 or later (free on the App Store), a cable for the first install, and a free Apple ID. Paste this into Terminal on your Mac:</p>
  <div class="g-cmd"><code>${INSTALL}</code>
    <button class="copy" type="button" data-copy="${INSTALL}" aria-label="Copy the install command">
      <svg width="15" height="15" class="ic-copy" aria-hidden="true"><use href="#i-copy"/></svg><svg width="15" height="15" class="ic-check" aria-hidden="true"><use href="#i-check"/></svg><span>Copy</span>
    </button></div>
  <p class="g-more">It waits for you where Apple needs a click. With a free Apple ID, apps you install yourself stop opening after 7 days; your Mac renews Glasspad over Wi-Fi before then. Every step, with pictures: <a href="/#get">Install</a>. Help: <a href="/guide#help">Guide</a>.</p>
</section>

</main>

<footer class="foot lp-foot">
  <nav class="wrap lp-learn" aria-labelledby="learn-t">
    <h2 id="learn-t">Learn</h2>
    <ul>
${learn}
    </ul>
  </nav>
  <nav class="foot-links wrap" aria-label="Project links">
    <a href="/">Home</a>
    <a href="/guide">Guide</a>
    <a href="https://github.com/Soham109/glasspad">GitHub</a>
    <a href="https://github.com/Soham109/glasspad/blob/main/LICENSE">MIT License</a>
    <a class="foot-by" href="https://sohamaggarwal.com">Made by Soham Aggarwal</a>
  </nav>
</footer>

<script type="module" src="/src/learn.ts"></script>
</body>
</html>
`;
}

/* ---------------------------------------------------------------- pages */

const pages = [];

pages.push({
  path: "/use/iphone-as-mac-trackpad", crumb: "iPhone as a Mac trackpad", shot: "trackpad",
  title: "Use your iPhone as a Mac trackpad, free | Glasspad",
  desc: "Turn your iPhone into a trackpad for your Mac over Wi-Fi: click with haptics, scroll, pinch, and swipe between Spaces. Free and open source.",
  h1: "Use your iPhone as a Mac trackpad",
  answer: "macOS has no built-in way to use an iPhone as a trackpad, so you need an app on both devices. Glasspad is a free, open source one: it turns your iPhone into a trackpad for your Mac over Wi-Fi. One finger moves the pointer, a tap clicks and you feel it, two fingers scroll and pinch, and three fingers swipe between Spaces or open Mission Control, following your Mac's own trackpad settings.",
  guide: ["/guide#modes", "Trackpad in the guide"],
  body: `<section class="g-sec wrap" id="how" aria-labelledby="how-t">
  <h2 id="how-t">How Glasspad does it</h2>
${row("trackpad", "", [
    "One finger moves the pointer. Tap to click, and feel a tap on every click.",
    "Hold a finger still for a moment to force click. Drag, scroll with momentum, pinch, rotate and smart zoom.",
    "Three fingers swipe between Spaces, or up for Mission Control.",
    "Gestures and pointer speed follow your Mac's trackpad settings. Speed, scrolling and haptics can be tuned on the iPhone.",
    "Touches are read at 120 Hz on ProMotion iPhones.",
  ])}
  <p class="lp-also">Want to type too? The Type layout puts the trackpad beside the <a href="/use/iphone-as-mac-keyboard">keyboard</a> on one screen.</p>
</section>`,
  faq: [
    ["Can I use my iPhone as a trackpad without an app?", "No. Universal Control works between Macs and iPads, not iPhones, and iPhone Mirroring goes the other way: the Mac controls the iPhone. You need an app on the iPhone and a small helper on the Mac. <a href=\"/compare/universal-control\">Glasspad vs Universal Control</a>."],
    ["Does it use Bluetooth?", "No. The iPhone and the Mac talk over the same Wi-Fi network. They pair once with a QR code, and every message is encrypted."],
    ["Does it feel like a real trackpad?", "It reads your Mac's trackpad settings and pointer acceleration, draws in step with the Mac's display, and keeps motion smooth over short Wi-Fi gaps. On a crowded or weak network you will notice more lag than with a Magic Trackpad."],
    ["My Mac's trackpad is broken. Can this replace it?", "Once it is set up, yes. Installing it needs a few clicks on the Mac (Xcode, your Apple ID, Accessibility), so borrow a mouse for the first install."],
    ["Is it free?", "Yes, all of it. There are no ads, accounts, subscriptions or in-app purchases, and the code is on GitHub under the MIT license."],
  ],
});

pages.push({
  path: "/use/iphone-as-mac-keyboard", crumb: "iPhone as a Mac keyboard", shot: "keyboard",
  title: "Use your iPhone as a Mac keyboard | Glasspad",
  desc: "Type or dictate on your iPhone and the text lands on your Mac, with command, option, control, shortcuts, arrows and F1 to F12. Free and open source.",
  h1: "Use your iPhone as a Mac keyboard",
  answer: "To type on your Mac from your iPhone, you need an app on both. Glasspad is a free, open source one: in its Keyboard mode, what you type or dictate on the iPhone lands wherever the cursor is on your Mac, over Wi-Fi. It has control, option, command and shift, the usual shortcuts, arrows, and F1 to F12, and it works with any Mac keyboard layout.",
  guide: ["/guide#modes", "Keyboard in the guide"],
  body: `<section class="g-sec wrap" id="how" aria-labelledby="how-t">
  <h2 id="how-t">How Glasspad does it</h2>
${row("keyboard", "Keyboard", [
    "Type or dictate. The text lands wherever the cursor is on the Mac.",
    "control, option, command and shift, the usual shortcuts, arrows, and fn for F1 to F12.",
    "Hold a key to repeat it.",
    "The Type layout puts the keyboard beside the <a href=\"/use/iphone-as-mac-trackpad\">trackpad</a> on one screen.",
  ])}
${row("clipboard", "Clipboard", [
    "Send to Mac: tap Paste to send what you copied on the iPhone, text or an image.",
    "Get from Mac: tap it to copy what your Mac has copied.",
  ])}
</section>`,
  faq: [
    ["Can I dictate on my Mac with my iPhone?", "Yes. In Keyboard, tap the microphone on the iPhone keyboard and speak. The words are typed on the Mac."],
    ["Does it work with my keyboard layout?", "Yes. Keys are sent for the Mac's own keyboard layout, whichever it is."],
    ["Can I send a long text from my iPhone?", "Copy it on the iPhone, open Clipboard and tap Paste under Send to Mac. It is then on the Mac's clipboard, ready to paste."],
    ["Is what I type sent over the internet?", "No. Glasspad pairs once with a QR code, encrypts everything, and your iPhone and Mac talk only over your Wi-Fi. There is no account."],
  ],
});

pages.push({
  path: "/use/iphone-remote-for-mac", crumb: "iPhone remote for Mac", shot: "remote",
  title: "iPhone remote for your Mac: Netflix, YouTube and more | Glasspad",
  og: "An iPhone remote for your Mac",
  desc: "Control Netflix, YouTube, Apple TV and Spotify on your Mac from your iPhone: tap to pause, swipe to skip, Skip Intro and Subtitles. Free and open source.",
  h1: "An iPhone remote for your Mac",
  answer: "Glasspad's Remote mode turns your iPhone into a remote for whatever plays on your Mac, much like a Siri Remote: tap the pad to play or pause, swipe sideways to skip 10 seconds, and up or down for volume. Its buttons follow the player, such as Skip Intro on Netflix and Subtitles and Next on YouTube. It works with YouTube, Netflix, Prime Video, Disney+, Apple TV, QuickTime Player, IINA, VLC, Infuse, Spotify and Music. Glasspad is free and open source.",
  guide: ["/guide#modes", "Remote in the guide"],
  body: `<section class="g-sec wrap" id="how" aria-labelledby="how-t">
  <h2 id="how-t">How Glasspad does it</h2>
${row("remote", "Remote", [
    "Tap the pad to play or pause. Swipe sideways to skip 10 seconds, up or down for volume.",
    "The buttons follow the player: Skip Intro on Netflix, Subtitles and Next on YouTube, Full Screen and Mute.",
    "Search types on the Mac and presses Return.",
    "The screen stays dark and dim, so it does not light up the room.",
  ])}
${row("media", "Media", [
    "What is playing in Spotify, Music, Podcasts or a browser, with the artwork.",
    "Drag to scrub. Set the volume, the sound output and the screen brightness.",
  ])}
</section>`,
  faq: [
    ["Does it work with Netflix in Safari or Chrome?", "Yes. Netflix and YouTube on a Mac play in the browser, and Remote works in Safari, Chrome, Firefox, Edge, Brave and Arc."],
    ["Do I need an Apple TV?", "No. The iPhone talks to the Mac directly over your Wi-Fi. Nothing else is needed."],
    ["Can I change the Mac's volume from the couch?", "Yes. Swipe up or down on the pad, or use Media for the volume slider and the sound output."],
    ["Can I keep the trackpad close by?", "Yes. The Couch layout puts Remote beside a trackpad on one screen."],
  ],
});

pages.push({
  path: "/use/stream-deck-alternative-mac", crumb: "Free Stream Deck alternative", shot: "actions",
  title: "A free Stream Deck alternative for Mac, on your iPhone | Glasspad",
  og: "A free Stream Deck alternative for Mac",
  desc: "Use your iPhone as a Stream Deck for your Mac: buttons that follow the app in front, plus your own apps, websites, shortcuts and macros. Free, no key limits.",
  h1: "A free Stream Deck alternative for Mac",
  answer: "Glasspad turns your iPhone into a deck of buttons for your Mac, free. Its Actions mode shows buttons for the app in front, ready made for more than 70 apps, and below them your own: apps, websites, keyboard shortcuts, recorded macros, shortcuts from the Shortcuts app, and Mac controls like Do Not Disturb, Night Shift, Keep Awake and Split Screen. There are no key limits, ads or subscriptions, and it is open source (MIT). It has no physical keys and no plugins for tools like OBS, so for live streaming a Stream Deck is still the better fit.",
  guide: ["/guide#yours", "Actions in the guide"],
  body: `<section class="g-sec wrap" id="how" aria-labelledby="how-t">
  <h2 id="how-t">How Glasspad does it</h2>
${row("actions", "Actions", [
    "The top follows the app in front on your Mac. More than 70 apps have their own buttons.",
    "Pinned holds yours. Folders keep them tidy.",
  ])}
  <div class="g-grid lp-gap">
    <article class="g-card">
      ${fig("library")}
      <div class="g-text"><h3>Library</h3>
      ${list([
        "Every app, Mac control, macro, shortcut and website, with search.",
        "Record steps on your Mac once, then replay them with a tap.",
      ])}
    </div></article>
    <article class="g-card">
      ${fig("website")}
      <div class="g-text"><h3>Any button</h3>
      ${list([
        "Touch and hold a button to change its name, symbol, color and size.",
        "Add a website and its logo appears by itself.",
      ])}
    </div></article>
  </div>
  <p class="lp-also">Comparing the two? <a href="/compare/stream-deck-mobile">Glasspad vs Stream Deck Mobile</a>.</p>
</section>`,
  faq: [
    ["Is it really free?", "Yes. Every feature, with no limit on pinned buttons, no ads and no subscription. The code is under the MIT license."],
    ["Can it run my Shortcuts?", "Yes. Any shortcut from the Shortcuts app on your Mac can be a button."],
    ["Can a button press a keyboard shortcut?", "Yes. Add a Keyboard Shortcut button and set the keys, such as command C, or a hotkey you set in another app."],
    ["Does it work with OBS or Twitch?", "Only through keyboard shortcuts you set up in those apps. Glasspad has no streaming plugins; Stream Deck has many."],
    ["Does it work with Windows or Android?", "No. Glasspad is for an iPhone and a Mac only."],
  ],
});

pages.push({
  path: "/use/mac-split-screen-from-iphone", crumb: "Split screen from iPhone", shot: "folder",
  title: "Split screen on your Mac from your iPhone | Glasspad",
  desc: "Put two Mac windows side by side, top and bottom or in quarters with one tap on your iPhone, on any display. Plus the Mac's own split screen shortcuts.",
  h1: "Split screen on your Mac from your iPhone",
  answer: "On a Mac you split the screen from the green button at the top left of a window, or, on macOS 15 and later, by pressing fn, control and the left or right arrow. Glasspad puts this on your iPhone: tap Split Screen, choose Left & Right, Top & Bottom, Quarters or Full Screen (Split View), pick the windows and the display, and see where each one will go before anything moves. Window buttons put the front window on a half or a quarter, Fill or Center.",
  guide: ["/guide#yours", "Actions in the guide"],
  body: `<section class="g-sec wrap" id="how" aria-labelledby="how-t">
  <h2 id="how-t">How Glasspad does it</h2>
${row("folder", "Window buttons", [
    "Split Screen opens Arrange: Left & Right, Top & Bottom, Quarters or Full Screen.",
    "Left Half, Right Half, Top Half, Bottom Half, the four quarters, Fill and Center.",
    "Next Display moves the front window to your other display.",
    "Add them to Pinned from the Library, or keep them in a folder as here.",
  ])}
${row("displays", "Displays", [
    "Touch and hold any window for the halves, Fill, Center and Split With.",
    "Drag a window to another display.",
  ])}
</section>`,
  faq: [
    ["What is the keyboard shortcut for split screen on a Mac?", "On macOS 15 and later, fn control left arrow puts the front window on the left half and fn control right arrow on the right. Add shift to arrange the next window on the other half too. The same moves are in Window &rsaquo; Move &amp; Resize."],
    ["What is the difference between tiling and Split View?", "Tiled windows stay on your desktop with everything else. Split View puts two windows side by side in full screen, in a Space of their own. Glasspad does both: Left & Right tiles, Full Screen makes a Split View."],
    ["Does it work with two displays?", "Yes. Pick the display in Arrange. If the windows are on different displays, the second one moves over first."],
    ["What if an app's window will not get narrow enough?", "Some apps have a minimum width. Glasspad tells you which window will not fit instead of leaving them overlapped."],
    ["Does it leave room for Stage Manager?", "Yes. Tiling keeps clear of Stage Manager's strip of apps."],
  ],
});

pages.push({
  path: "/use/control-mac-displays-from-iphone", crumb: "Displays and windows", shot: "displays",
  title: "Control your Mac's displays and windows from iPhone | Glasspad",
  og: "Control your Mac's displays and windows from your iPhone",
  desc: "See every display and window on your Mac from your iPhone. Move windows between displays, tile them, and set brightness, resolution and Night Shift.",
  h1: "Control your Mac's displays and windows from your iPhone",
  answer: "Glasspad's Displays mode shows your Mac's displays on your iPhone the way System Settings draws them, with every window on them. Tap a window to bring it forward, drag it to another display, or touch and hold it to tile, split, enter full screen, minimize or close it. Its settings set brightness, resolution, Night Shift, the main display, mirroring and the arrangement, and a new resolution goes back after 15 seconds unless you keep it.",
  guide: ["/guide#modes", "Displays in the guide"],
  body: `<section class="g-sec wrap" id="how" aria-labelledby="how-t">
  <h2 id="how-t">How Glasspad does it</h2>
${row("displays", "Displays", [
    "Your displays as in System Settings, with every window on them.",
    "Tap a window to bring it forward, or drag it to another display.",
    "Touch and hold a window for the halves, Fill, Center, Split With, full screen, minimize and close.",
    "The settings button sets brightness, resolution, Night Shift, the main display, mirroring and the arrangement.",
  ])}
  <p class="lp-also">Two windows side by side in one tap: <a href="/use/mac-split-screen-from-iphone">split screen from your iPhone</a>.</p>
</section>`,
  faq: [
    ["Can I move a window to another monitor from my iPhone?", "Yes. Drag it onto the other display in Displays, or tap a Next Display button in Actions."],
    ["Can I change the resolution from my iPhone?", "Yes, in the settings in Displays. A new resolution or mirroring goes back after 15 seconds unless you keep it, so a blank screen fixes itself."],
    ["Does it work with one display?", "Yes. You still get the list of windows, and tiling, brightness, resolution and Night Shift."],
    ["What does the Mac need to allow?", "Accessibility, in System Settings &rsaquo; Privacy &amp; Security, so Glasspad can move windows. The installer walks you through it."],
  ],
});

pages.push({
  path: "/compare/remote-mouse", crumb: "Glasspad vs Remote Mouse", shot: "trackpad",
  title: "Glasspad vs Remote Mouse: an open source alternative | Glasspad",
  og: "Glasspad vs Remote Mouse",
  desc: "How Glasspad and Remote Mouse compare: platforms, price, install, trackpad and extras. Glasspad is free and open source for iPhone and Mac.",
  h1: "Glasspad vs Remote Mouse",
  answer: "Remote Mouse and Glasspad both turn a phone into a mouse, keyboard and media remote for a computer over Wi-Fi. Remote Mouse works on iPhone and Android with Mac, Windows and Linux, installs from the App Store, and is free with ads and paid extras. Glasspad is for iPhone and Mac only, free with no ads or purchases, and open source (MIT). It adds a trackpad with haptics that follows your Mac's own gestures, buttons for the app in front, and window and display control. It is not on the App Store, so installing it takes more steps.",
  guide: ["/guide#modes", "Every mode in the guide"],
  body: `<section class="g-sec wrap" id="compare" aria-labelledby="compare-t">
  <h2 id="compare-t">Side by side</h2>
${table("Remote Mouse", [
    ["Phone", "iPhone (iOS 18 or later)", "iPhone and iPad (iOS 15 or later), and Android"],
    ["Computer", "Mac (macOS 14 or later)", "Mac, Windows and Linux"],
    ["Install", "One-line installer that builds the app with Xcode and a free Apple ID; the Mac renews it every 7 days", "App Store or Google Play, plus a helper app on the computer"],
    ["Price", "Free. No ads or in-app purchases", "Free with ads. Pro is $1.49 a month or $13.99 a year; Remove Ads is $0.99"],
    ["Source code", "Open source, MIT", "Not open source"],
    ["Connection", "Same Wi-Fi, paired by QR code, encrypted", "Same Wi-Fi"],
    ["Trackpad", "Your Mac's own gestures: Spaces, Mission Control, pinch, rotate, force click, with haptics", "Touchpad, plus a mouse you move by tilting the phone"],
    ["Also", "Media, Remote, Dock, buttons for 70+ apps, macros, Shortcuts, Present, Clipboard, Displays, Layouts", "Media and web remotes, app switcher, power options, voice typing, clipboard"],
  ])}
</section>

<section class="g-sec wrap" id="choose" aria-labelledby="choose-t">
  <h2 id="choose-t">Which one fits</h2>
${picks("Remote Mouse", [
    "You use Windows, Linux or an Android phone.",
    "You want to install from the App Store in a minute.",
  ], [
    "You have an iPhone and a Mac and want the Mac's own trackpad gestures.",
    "You want everything free, with no ads, and code you can read.",
    "You want buttons for the app in front, window tiling and display control too.",
  ])}
</section>`,
  faq: [
    ["Is Glasspad an open source alternative to Remote Mouse?", "Yes. Glasspad's code is on GitHub under the MIT license, and every feature is free. It works only with an iPhone and a Mac."],
    ["Why is Glasspad not on the App Store?", "The Mac app uses system features that the App Store does not allow. Instead, the installer builds both apps on your Mac with Xcode and your free Apple ID."],
    ["Does Glasspad work on Windows?", "No. For Windows or Linux, Remote Mouse is a good choice."],
    ["Do I need to pay Apple to install Glasspad?", "No. A free Apple ID is enough. Apps installed that way stop opening after 7 days, and your Mac renews Glasspad over Wi-Fi before then."],
  ],
  sources: [
    ["Remote Mouse website: features and platforms", "https://www.remotemouse.net/"],
    ["Remote Mouse on the App Store: prices and requirements", "https://apps.apple.com/us/app/remote-mouse/id385894596"],
  ],
});

pages.push({
  path: "/compare/stream-deck-mobile", crumb: "Glasspad vs Stream Deck Mobile", shot: "actions",
  title: "Glasspad vs Stream Deck Mobile for Mac | Glasspad",
  og: "Glasspad vs Stream Deck Mobile",
  desc: "How Glasspad and Elgato's Stream Deck Mobile compare: keys, price, plugins and what else your iPhone can do for your Mac.",
  h1: "Glasspad vs Stream Deck Mobile",
  answer: "Stream Deck Mobile, from Elgato, turns an iPhone or iPad into Stream Deck keys for a Mac or Windows PC running the Stream Deck app, with hundreds of plugins for streaming and creative tools. It is free for 6 keys; Pro gives up to 64 and costs $2.99 a month, $24.99 a year or $49.99 once. Glasspad is a free, open source iPhone app for the Mac only, with no key limit and buttons that change with the app in front, plus a trackpad, keyboard, remote and window control. For live streaming, Stream Deck's plugins make it the stronger choice.",
  guide: ["/guide#yours", "Actions in the guide"],
  body: `<section class="g-sec wrap" id="compare" aria-labelledby="compare-t">
  <h2 id="compare-t">Side by side</h2>
${table("Stream Deck Mobile", [
    ["Devices", "iPhone (iOS 18 or later) with a Mac (macOS 14 or later)", "iPhone or iPad (iOS 17 or later) with a Mac or Windows PC; Android with Pro"],
    ["Price", "Free, everything", "Free for 6 keys. Pro: $2.99 a month, $24.99 a year or $49.99 once"],
    ["Keys", "No limit on pinned buttons, plus up to 8 for each app", "6 free, up to 64 with Pro"],
    ["Plugins", "None. Buttons are apps, websites, keyboard shortcuts, macros, Shortcuts and Mac controls", "Hundreds, for OBS, Twitch, music and more"],
    ["Per app", "Ready-made buttons for 70+ apps, following the app in front", "Profiles can switch with the app in front"],
    ["Also", "Trackpad, keyboard, media, remote, Dock, displays and window tiling", "Stream Deck keys"],
    ["Install", "One-line installer that builds the app with Xcode and a free Apple ID", "App Store, plus the Stream Deck app on the computer"],
    ["Source code", "Open source, MIT", "Not open source"],
  ])}
</section>

<section class="g-sec wrap" id="choose" aria-labelledby="choose-t">
  <h2 id="choose-t">Which one fits</h2>
${picks("Stream Deck Mobile", [
    "You stream, and want OBS scenes, Twitch and other plugins.",
    "You already use a Stream Deck and want the same profiles on your phone.",
    "You use Windows, an iPad or Android.",
  ], [
    "You want a free deck with no key limit for everyday Mac work.",
    "You want buttons that change with the app in front, ready made.",
    "You want the same iPhone to be a trackpad, keyboard and remote too.",
  ])}
</section>`,
  faq: [
    ["Is Glasspad a free alternative to Stream Deck Mobile?", "For everyday Mac work, yes: apps, websites, shortcuts, macros and Mac controls, with no key limit. It has no streaming plugins."],
    ["How many keys does Stream Deck Mobile give for free?", "Six, with unlimited actions. Pro raises it to 64."],
    ["Can I use both?", "Yes. They do not get in each other's way."],
    ["Does Glasspad work on iPad?", "No. Glasspad is made for iPhone."],
  ],
  sources: [
    ["Stream Deck Mobile on the App Store: prices, keys and requirements", "https://apps.apple.com/us/app/elgato-stream-deck-mobile/id1440014184"],
    ["Elgato: Stream Deck Mobile is free for six keys (2023)", "https://www.corsair.com/newsroom/press-release/stream-deck-goes-free-elgato-announces-groundbreaking-changes-to-mobile-app"],
  ],
});

pages.push({
  path: "/compare/universal-control", crumb: "Glasspad vs Universal Control", shot: "trackpad",
  title: "Universal Control with iPhone? Glasspad vs Universal Control",
  og: "Glasspad vs Universal Control",
  desc: "Universal Control does not work with iPhone. Here is what it does, how it differs from iPhone Mirroring, and how to control a Mac from an iPhone.",
  h1: "Glasspad vs Universal Control",
  answer: "Universal Control does not work with iPhone. It lets one Mac's keyboard and trackpad control up to two other Macs or iPads nearby (macOS 12.4 and iPadOS 15.4 or later, signed in to the same Apple Account). iPhone Mirroring goes the other way: your Mac controls your iPhone. To control a Mac from an iPhone you need an app. Glasspad is a free, open source one that makes the iPhone a trackpad, keyboard, remote and button deck for the Mac over Wi-Fi.",
  guide: ["/guide#modes", "Every mode in the guide"],
  body: `<section class="g-sec wrap" id="compare" aria-labelledby="compare-t">
  <h2 id="compare-t">Side by side</h2>
${table("Universal Control", [
    ["Direction", "iPhone controls the Mac", "A Mac's keyboard and trackpad control other Macs and iPads"],
    ["Devices", "iPhone (iOS 18 or later) and Mac (macOS 14 or later)", "Mac (macOS 12.4 or later) with up to two Macs or iPads (iPadOS 15.4 or later); no iPhone"],
    ["Setup", "Install with the one-line installer, pair once by QR code", "Built in. Same Apple Account with two-factor authentication"],
    ["Connection", "Same Wi-Fi", "Bluetooth, Wi-Fi and Handoff on, within 10 meters"],
    ["What you get", "Trackpad, keyboard, media, remote, buttons, displays and windows", "One pointer and keyboard across screens, drag and drop between them"],
    ["Price", "Free, open source (MIT)", "Free, part of macOS and iPadOS"],
  ])}
</section>

<section class="g-sec wrap" id="choose" aria-labelledby="choose-t">
  <h2 id="choose-t">Which one fits</h2>
${picks("Universal Control", [
    "You have an iPad or a second Mac on your desk.",
    "You want one keyboard and trackpad across them, with drag and drop.",
  ], [
    "You want your iPhone to control your Mac.",
    "You want a remote for the couch, a deck of buttons, or a spare trackpad.",
  ])}
  <p class="lp-also">They work side by side: Glasspad does not replace Universal Control.</p>
</section>`,
  faq: [
    ["Does Universal Control work with iPhone?", "No. Apple lists Macs and iPads only. For the iPhone, Apple points to iPhone Mirroring, which lets your Mac control your iPhone."],
    ["What is iPhone Mirroring?", "A macOS 15 feature that shows your iPhone's screen on your Mac so you can use its apps there. It needs iOS 18, a Mac with Apple silicon or the T2 chip, and the same Apple Account."],
    ["How do I control my Mac from my iPhone?", "With an app on both devices. Glasspad is free and open source: install it on the Mac, pair the iPhone by QR code, and use it as a trackpad, keyboard or remote over Wi-Fi."],
    ["Does Glasspad need an Apple Account?", "Only a free Apple ID to install the app on your iPhone. Glasspad itself has no account, and the iPhone and Mac talk only over your Wi-Fi."],
  ],
  sources: [
    ["Apple: Universal Control requirements", "https://support.apple.com/102459"],
    ["Apple: iPhone Mirroring requirements", "https://support.apple.com/120421"],
  ],
});

for (const p of pages) {
  const file = join(root, p.path.slice(1) + ".html");
  mkdirSync(dirname(file), { recursive: true });
  writeFileSync(file, page(p));
}
console.log(`learn: ${pages.length} pages`);
