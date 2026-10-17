/* Facts shared by the pages, structured data and llms.txt, so they are written once.
   Answers are HTML (links and <code> only); structured data and llms-full.txt get them as plain text. */

import { SITE, REPO, RELEASE, VERSION } from "./pages";
import { themesLine } from "../src/themes";

export const INSTALL = "curl -fsSL https://raw.githubusercontent.com/Soham109/glasspad/main/install.sh | bash";

export const DEFINITION = "Glasspad is a free, open source (MIT) app that turns an iPhone into a trackpad, keyboard, media remote and button deck for a Mac, over Wi-Fi, with no account.";

export const FAQS: Record<string, { q: string; a: string }[]> = {
  home: [
    {
      q: "What is Glasspad?",
      a: `${DEFINITION} It has 11 modes: Trackpad, Keyboard, Media, Dock, Actions, Pinned, Macros, Clipboard, Present, Remote and Displays. Actions has ready-made buttons for more than 70 apps, Layouts put up to three modes on one screen, and there are 39 themes. It is made by Soham Aggarwal.`,
    },
    {
      q: "Is Glasspad free?",
      a: `Yes. It is free and open source under the MIT License, with no account and nothing to buy. The code is public on <a href="${REPO}">GitHub</a> under that license, so no feature in it can be moved behind a paywall later.`,
    },
    {
      q: "Is Glasspad on the App Store?",
      a: "No. One command in Terminal builds it on your Mac with Xcode and installs it on your iPhone with your free Apple ID. It waits for you at each step, and is safe to run again.",
    },
    {
      q: "Does it stop opening after 7 days?",
      a: "Not while your Mac can reach it. With a free Apple ID, apps you install yourself stop opening after 7 days, so your Mac renews Glasspad over Wi-Fi before then. If it cannot, it tells you.",
    },
    {
      q: "What if my Mac sleeps or the Wi-Fi drops?",
      a: "The iPhone reconnects by itself when the Wi-Fi is back, the Mac wakes or you open the app, and says why the Mac is away, such as asleep, locked or Glasspad turned off. Wake Mac sends a wake signal over Wi-Fi to a Mac with Wake for network access on; a Mac on battery cannot wake this way. If the Wi-Fi keeps devices apart, Glasspad tries a direct Wi-Fi link to the Mac, which is slower than a normal network.",
    },
    {
      q: "Does anything leave my Wi-Fi?",
      a: "Almost nothing. Glasspad pairs once with a QR code, encrypts everything, and your iPhone and Mac talk only over your Wi-Fi. There is no account. Website buttons fetch their site's name and logo, and the Mac may fetch album artwork for what is playing.",
    },
    {
      q: "What do I need?",
      a: "A Mac on macOS 14 or later with Xcode 26 or later, an iPhone on iOS 18 or later, a free Apple ID, a USB cable for the first install, and one Wi-Fi for both.",
    },
  ],
  guide: [
    {
      q: "Can I use my iPhone as a trackpad for my Mac?",
      a: 'Yes, with an app on both devices; macOS has no built-in way, and Universal Control does not work with iPhone. Glasspad is a free, open source one: one finger moves the pointer, a tap clicks and the iPhone taps back, two fingers scroll and pinch, and three fingers swipe between Spaces or open Mission Control. More in <a href="/use/iphone-as-mac-trackpad">iPhone as a Mac trackpad</a>.',
    },
    {
      q: "How do I control my Mac from my iPhone?",
      a: 'Install an app on both. If you are away from the Mac and need to see its screen, use a screen sharing app. If you are in the same room, Glasspad makes the iPhone a trackpad, keyboard, media remote and button deck for the Mac: install it with one Terminal command, pair the iPhone by QR code, and both talk over your Wi-Fi. See <a href="/install">Install</a>.',
    },
    {
      q: "Can I use my iPhone as a keyboard for my Mac?",
      a: 'Yes. In Glasspad\'s Keyboard mode, what you type or dictate on the iPhone lands where the cursor is on the Mac. It has Control, Option, Command and Shift, arrows, and F1 to F12, and works with any Mac keyboard layout. More in <a href="/use/iphone-as-mac-keyboard">iPhone as a Mac keyboard</a>.',
    },
    {
      q: "Can I use my iPhone as a remote for Netflix or YouTube on my Mac?",
      a: 'Yes. Glasspad\'s Remote is a touch pad like the Siri Remote: tap to play or pause, swipe sideways to skip 10 seconds, up or down for volume. Its buttons follow 11 players: YouTube, Netflix, Prime Video, Disney+, Apple TV, QuickTime Player, IINA, VLC, Infuse, Spotify and Music, with Skip Intro on Netflix. More in <a href="/use/iphone-remote-for-mac">iPhone remote for Mac</a>.',
    },
    {
      q: "Can I split the screen on my Mac from my iPhone?",
      a: 'Yes. Add Split Screen to Actions to put windows side by side, or touch and hold a window in Displays for the halves, Fill, Center and Split With. More in <a href="/use/mac-split-screen-from-iphone">Split screen from iPhone</a>.',
    },
    {
      q: "What is a free Stream Deck alternative for Mac?",
      a: 'Glasspad is one: a free, open source iPhone app that puts buttons for your Mac on the phone, with no key limit. Its Actions mode has ready-made buttons for more than 70 apps that follow the app in front, and you can pin your own: apps, websites, keyboard shortcuts, macros, Shortcuts and Mac controls. Elgato\'s <a href="https://apps.apple.com/us/app/elgato-stream-deck-mobile/id1440014184">Stream Deck Mobile</a> is free for 6 keys and $2.99 a month for up to 64. Glasspad has no physical keys and no streaming plugins, so for OBS or Twitch a Stream Deck fits better. More in <a href="/compare/stream-deck-mobile">Glasspad vs Stream Deck Mobile</a>.',
    },
    {
      q: "How is Glasspad different from Universal Control?",
      a: 'Universal Control is built into macOS: it lets one Mac\'s keyboard and trackpad control up to two nearby Macs or iPads. <a href="https://support.apple.com/102459">Apple lists no iPhone support</a>. Glasspad makes your iPhone the trackpad, keyboard and remote for your Mac, and works alongside Universal Control. More in <a href="/compare/universal-control">Glasspad vs Universal Control</a>.',
    },
    {
      q: "How is Glasspad different from Remote Mouse?",
      a: '<a href="https://www.remotemouse.net/">Remote Mouse</a> turns a phone into a mouse and keyboard for a Mac, Windows or Linux computer, on iPhone and Android, and is free with ads and paid extras. Glasspad is only for iPhone and Mac, is free with no ads or purchases, is open source, and adds buttons for the app in front, a couch remote, a slide clicker, your displays and layouts. More in <a href="/compare/remote-mouse">Glasspad vs Remote Mouse</a>.',
    },
    {
      q: "Can I use my iPhone as a presentation clicker for my Mac?",
      a: "Yes. Glasspad's Present mode has Next and Back, a timer, and a laser pointer you steer with one finger, for slides in Keynote, PowerPoint and other apps on the Mac. Next, Back and the timer also show on the iPhone's Lock Screen.",
    },
    {
      q: "Can I use Glasspad with more than one Mac?",
      a: "Yes. Choose Pair Another Mac in Settings on the iPhone, then tap a Mac to switch. With two or more, the Mac's name at the top of the screen is a menu to switch too. One Mac is connected at a time.",
    },
    {
      q: "Can I control my Mac without opening Glasspad?",
      a: "Partly. A Control Center control and a Lock Screen widget open the trackpad. While Remote, Media or Present is open, a Live Activity puts its keys on the Lock Screen. Siri and the Shortcuts app can open a mode or layout, play or pause, send the clipboard, open Mission Control, or run a button or macro.",
    },
    {
      q: "Does Glasspad work with Windows, Android or iPad?",
      a: "No. Glasspad works only with an iPhone on iOS 18 or later and a Mac on macOS 14 or later.",
    },
    {
      q: "Is Glasspad safe?",
      a: 'Glasspad pairs once by QR code, keeps the pairing key in the Keychain on both devices, and encrypts every message (ChaCha20-Poly1305) with a fresh key for each connection. There is no account or server. The code is open to read on <a href="https://github.com/Soham109/glasspad">GitHub</a>, and the details are in <a href="https://github.com/Soham109/glasspad/blob/main/SECURITY.md">SECURITY.md</a>.',
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
  ["Trackpad", "Move, click, scroll, pinch, swipe between Spaces and open Mission Control, with a tap you can feel on every click. It follows your Mac's own trackpad settings."],
  ["Keyboard", "Type or dictate. Modifier keys, shortcuts, arrows and F1 to F12, with any Mac keyboard layout."],
  ["Media", "What is playing in Spotify, Music, Podcasts or a browser: artwork, scrubbing, sound output, volume and screen brightness."],
  ["Dock", "Your Mac's Dock. Tap to open, hold to hide or quit, and hide the Mac's own Dock."],
  ["Actions", "Buttons that follow the app in front, for more than 70 apps."],
  ["Pinned", "Your own buttons: Do Not Disturb, Night Shift, Keep Awake, Split Screen and window tiling, screenshots, apps, and websites with their real logos. Folders keep them tidy; the Library finds anything."],
  ["Macros", "Record steps on your Mac once, replay them with a tap."],
  ["Shortcuts", "Run any shortcut from the Shortcuts app on your Mac."],
  ["Remote", "A touch pad like the Siri Remote: tap to pause, swipe to skip 10 seconds, up or down for volume. The keys follow 11 players, among them YouTube, Netflix, Prime Video, Disney+, VLC and Spotify, and Search types on the Mac."],
  ["Present", "Next and Back, a timer, and a laser you steer with one finger."],
  ["Clipboard", "Text and images, both ways."],
  ["Displays", "Every display and its windows. Move a window to another display or tile it, and set brightness, resolution and Night Shift."],
  ["Layouts", "Up to three modes on one screen. The divider rests on thirds and the middle; your layouts sit in the mode menu."],
  ["StandBy", "A clock beside Now Playing or your calendar while the iPhone charges, in dim red at night."],
  ["Siri and Shortcuts", "Open a mode or a layout from Siri or the Shortcuts app, plus a Control Center control, a Lock Screen widget and a Live Activity with Remote or Present keys."],
  ["Themes", themesLine()],
  ["Connection", "Reconnects by itself and says why the Mac is away. Wake Mac wakes a Mac with Wake for network access on. On Wi-Fi that keeps devices apart, it tries a direct Wi-Fi link."],
  ["More than one Mac", "Pair Another Mac in Settings, then tap to switch."],
  ["Private", "Paired by QR code, encrypted, no account. Your iPhone and Mac talk only over your Wi-Fi. Website buttons fetch their site's logo and the Mac may fetch album art."],
];

export const FILM = {
  id: "6AArTWOADGc",
  /** the title on YouTube */
  name: "Use Your iPhone as a Mac Trackpad (Free, Open Source) | Glasspad",
  description: "Glasspad turns your iPhone into a wireless trackpad, keyboard and remote for your Mac. Free, open source (MIT), no account, no cloud.",
  uploadDate: "2026-10-15T18:05:20-07:00",
  duration: "PT1M4S",
  /** chapters as in the YouTube description: [start in seconds, name] */
  chapters: [
    [0, "Your iPhone as a Mac trackpad"],
    [13, "Click with haptics and swipe between Spaces"],
    [26, "Your Mac's trackpad settings, mode menu and Dock"],
    [39, "Actions for the app in front, and media"],
    [50, "Private: no account, no cloud, encrypted"],
  ] as [number, string][],
  /** the spoken words, from the film's English captions */
  transcript: [
    "Your Mac is over there.",
    "Your phone is right here.",
    "Glasspad turns it into a trackpad.",
    "Slide a finger, and the pointer glides, in step with your display.",
    "Tap, and you feel the click.",
    "Swipe three fingers, and your Spaces move with your hand.",
    "It follows your Mac's own trackpad settings, so it already feels like yours.",
    "Tap the top for everything else.",
    "Open Word without getting up.",
    "Actions follow the app in front.",
    "Switch to Safari, and the buttons switch with you.",
    "Play Spotify on your Mac, and scrub it from your phone.",
    "No account. No cloud.",
    "Every touch is encrypted, and stays on your Wi-Fi.",
    "Glasspad is free and open source.",
  ],
};

export const LINKS: [string, string, string][] = [
  ["Source code", REPO, "Swift, MIT License"],
  [`Release ${VERSION}`, RELEASE, "release notes"],
  ["License", `${REPO}/blob/main/LICENSE`, "MIT"],
  ["Demo video", `https://www.youtube.com/watch?v=${FILM.id}`, "one minute, on YouTube"],
  ["Full text for language models", `${SITE}/llms-full.txt`, "the features, install steps and questions in full"],
];
