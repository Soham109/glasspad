/* Facts shared by the pages, structured data and llms.txt, so they are written once.
   Answers are HTML (links and <code> only); structured data and llms-full.txt get them as plain text. */

import { SITE, REPO, RELEASE, VERSION } from "./pages";
import { themesLine } from "../src/themes";

export const INSTALL = "curl -fsSL https://raw.githubusercontent.com/Soham109/glasspad/main/install.sh | bash";

export const DEFINITION = "Glasspad is a free, open source app that turns your iPhone into a control surface for your Mac.";

export const FAQS: Record<string, { q: string; a: string }[]> = {
  home: [
    {
      q: "What is Glasspad?",
      a: `${DEFINITION} It is a trackpad you can feel, a keyboard, media controls, your Dock, buttons for the app in front, a couch remote, a slide clicker, your displays, and layouts with up to three modes on one screen.`,
    },
    {
      q: "Is Glasspad free?",
      a: `Yes. It is free and open source under the MIT License, with no account and nothing to buy. The code is on <a href="${REPO}">GitHub</a>.`,
    },
    {
      q: "Is Glasspad on the App Store?",
      a: "No. One command in Terminal builds it on your Mac with Xcode and installs it on your iPhone with your free Apple ID. It waits for you at each step, and is safe to run again.",
    },
    {
      q: "Does it stop opening after 7 days?",
      a: "Not while your Mac can reach it. With a free Apple ID, apps you install yourself stop opening after 7 days, so your Mac renews Glasspad over Wi-Fi before then. If it can't, it tells you.",
    },
    {
      q: "Does anything leave my Wi-Fi?",
      a: "No. Glasspad pairs once with a QR code, encrypts everything, and your iPhone and Mac talk only over your Wi-Fi. There is no account. Website buttons fetch their site's name and logo from that site.",
    },
    {
      q: "What do I need?",
      a: "A Mac on macOS 14 or later with Xcode 26 or later, an iPhone on iOS 18 or later, a free Apple ID, a USB cable for the first install, and one Wi-Fi for both.",
    },
  ],
  guide: [
    {
      q: "Can I use my iPhone as a remote for Netflix or YouTube on my Mac?",
      a: 'Yes. Remote is a touch pad like the Siri Remote: tap to play or pause, swipe sideways to skip 10 seconds, up or down for volume. The buttons follow the player, like Skip Intro on Netflix. More in <a href="/use/iphone-remote-for-mac">iPhone remote for Mac</a>.',
    },
    {
      q: "Can I split the screen on my Mac from my iPhone?",
      a: 'Yes. Add Split Screen to Actions to put windows side by side, or touch and hold a window in Displays for the halves, Fill, Center and Split With. More in <a href="/use/mac-split-screen-from-iphone">Split screen from iPhone</a>.',
    },
    {
      q: "Is Glasspad a free Stream Deck alternative?",
      a: 'Stream Deck is a keypad from Elgato with buttons you program. Actions in Glasspad puts buttons on your iPhone instead, for free: they follow the app in front, and you can pin your own, with macros, shortcuts and websites. It has no physical keys. More in <a href="/compare/stream-deck-mobile">Glasspad vs Stream Deck Mobile</a>.',
    },
    {
      q: "How is Glasspad different from Universal Control?",
      a: 'Universal Control is built into macOS: it lets the keyboard and trackpad of one Mac work on a nearby Mac or iPad. It does not use an iPhone. Glasspad makes your iPhone the trackpad, keyboard and remote for your Mac. More in <a href="/compare/universal-control">Glasspad vs Universal Control</a>.',
    },
    {
      q: "How is Glasspad different from Remote Mouse?",
      a: 'Remote Mouse turns a phone into a mouse and keyboard for a Mac or PC, on iPhone and Android. Glasspad is only for iPhone and Mac, is free and open source, and adds buttons for the app in front, a couch remote, a slide clicker, your displays and layouts. More in <a href="/compare/remote-mouse">Glasspad vs Remote Mouse</a>.',
    },
  ],
};

/** The install steps as on the install page, for HowTo data. */
export const HOWTO: { name: string; text: string }[] = [
  { name: "Run the command", text: `Paste ${INSTALL} into Terminal on your Mac. It waits for you at each step, and is safe to run again.` },
  { name: "Xcode", text: "Install Xcode, then enter your Mac password once." },
  { name: "Build tools", text: "The script downloads XcodeGen." },
  { name: "Source", text: "The script downloads Glasspad." },
  { name: "Apple account", text: "Sign in to Xcode with your Apple ID and pick your team." },
  { name: "Mac app", text: "Allow Accessibility for Glasspad in System Settings." },
  { name: "iPhone", text: "Trust the Mac, turn on Developer Mode, and trust the app." },
  { name: "Automatic renewal", text: "Your Mac keeps the app opening by renewing it over Wi-Fi." },
  { name: "Pair", text: "Click Glasspad in the menu bar, choose Pair Your iPhone, and scan the code." },
];

export const NEEDS = ["A Mac on macOS 14 or later", "Xcode 26 or later", "An iPhone on iOS 18 or later", "A free Apple ID", "A USB cable for the first install", "One Wi-Fi for the Mac and the iPhone"];

export const FEATURES: [string, string][] = [
  ["Trackpad", "Move, click, scroll, pinch and swipe between Spaces, with a tap you can feel on every click."],
  ["Keyboard", "Type or dictate. Modifier keys, shortcuts, arrows and F1 to F12."],
  ["Media", "What is playing in Spotify, Music or a browser: artwork, scrubbing, sound output, volume and screen brightness."],
  ["Dock", "Your Mac's Dock. Tap to open, hold to hide or quit, and hide the Mac's own Dock."],
  ["Actions", "Buttons that follow the app in front, for more than 70 apps."],
  ["Pinned", "Your own buttons: Do Not Disturb, Night Shift, Keep Awake, Split Screen and window tiling, screenshots, apps, and websites with their real logos. Folders keep them tidy; the Library finds anything."],
  ["Macros", "Record steps on your Mac once, replay them with a tap."],
  ["Shortcuts", "Run any shortcut from the Shortcuts app on your Mac."],
  ["Remote", "A touch pad like the Siri Remote: tap to pause, swipe to skip 10 seconds, up or down for volume. The keys follow the player, and Search types on the Mac."],
  ["Present", "Next and Back, a timer, and a laser you steer with one finger."],
  ["Clipboard", "Text and images, both ways."],
  ["Displays", "Every display and its windows. Move a window to another display or tile it, and set brightness, resolution and Night Shift."],
  ["Layouts", "Up to three modes on one screen. The divider rests on thirds and the middle; your layouts sit in the mode menu."],
  ["StandBy", "A clock beside Now Playing or your calendar while the iPhone charges, in dim red at night."],
  ["Themes", themesLine()],
  ["Private", "Paired by QR code, encrypted, no account. Nothing leaves your Wi-Fi, except Website buttons fetching their site's name and logo."],
];

export const FILM = {
  id: "6AArTWOADGc",
  name: "Introducing Glasspad",
  description: "A one minute film of Glasspad: an iPhone as a trackpad, keyboard, media remote and control surface for a Mac.",
  uploadDate: "2026-10-15T18:05:20-07:00",
  duration: "PT1M4S",
};

export const LINKS: [string, string, string][] = [
  ["Source code", REPO, "Swift, MIT License"],
  [`Release ${VERSION}`, RELEASE, "release notes"],
  ["License", `${REPO}/blob/main/LICENSE`, "MIT"],
  ["Demo film", `https://www.youtube.com/watch?v=${FILM.id}`, "one minute, on YouTube"],
  ["Full text for language models", `${SITE}/llms-full.txt`, "the features, install steps and questions in full"],
];
