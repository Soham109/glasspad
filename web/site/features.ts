/* The words on the Features and Compare pages, keyed by path in site/pages.ts.
   site/render.ts lays every one out the same way, so a new page is a new entry here.
   Answers and table cells are HTML (links, <code> and entities only). */

export type Shot = "trackpad" | "keyboard" | "remote" | "media" | "actions" | "library" | "folder" | "website" | "displays" | "clipboard" | "menu" | "layouts";

/** Real app screens from docs/img/screens (copied to /img/screens by scripts/sync-screens.mjs). */
export const SHOTS: Record<Shot, { w: number; h: number; alt: string }> = {
  trackpad: { w: 1280, h: 698, alt: "Trackpad on an iPhone held sideways, with three finger dots" },
  keyboard: { w: 700, h: 1288, alt: "Keyboard on an iPhone: modifier keys, shortcuts and arrows above the iPhone keyboard" },
  remote: { w: 700, h: 1288, alt: "Remote on an iPhone for a film on Netflix in Safari: a large touch pad, skip and pause buttons, then Search, Skip Intro, Full Screen and Mute" },
  media: { w: 700, h: 1288, alt: "Media on an iPhone: artwork, the song, scrubber, controls, volume and brightness" },
  actions: { w: 700, h: 1288, alt: "Actions on an iPhone: Safari's buttons on top, Pinned buttons below" },
  library: { w: 700, h: 1288, alt: "Library on an iPhone: search, Pinned, Record New Macro, and apps with add buttons" },
  folder: { w: 700, h: 1288, alt: "Actions on an iPhone with the Windows folder open: Left Half, Right Half, Fill, Split Screen and Next Display" },
  website: { w: 700, h: 1288, alt: "Edit Button on an iPhone for a GitHub website button, with name, symbol, color and size" },
  displays: { w: 700, h: 1288, alt: "Displays on an iPhone: two displays drawn as in System Settings, and the list of windows on them" },
  clipboard: { w: 700, h: 1288, alt: "Clipboard on an iPhone: Send to Mac with Paste, Get from Mac with its button" },
  menu: { w: 700, h: 1288, alt: "The mode menu on an iPhone: Trackpad, Keyboard, Media, Dock and Actions, then Layouts, then Present, Remote and Displays" },
  layouts: { w: 1280, h: 698, alt: "A layout on an iPhone held sideways: Media beside Actions" },
};

export interface Tile { icon: string; title: string; text: string }
export interface Step { icon: string; title: string; text: string }

export interface Feature {
  kind: "feature";
  /** the page's one <h1>: short, with the words people search for */
  h1: string;
  /** one line under the headline */
  sub: string;
  /** the drawn, animated scene from src/ shown under the hero (src/page.ts mounts it) */
  visual: "trackpad" | "keys" | "couch" | "studio" | "desk" | "displays";
  /** what the scene shows, for people who cannot see it */
  visualLabel: string;
  /** the answer quoted in "In short": what it is and how Glasspad does it, in a few sentences */
  answer: string;
  /** the real app screen beside the answer */
  shot: Shot;
  /** the matching part of the guide: [href, link text] */
  guide: [string, string];
  /** three or four benefits */
  tiles: Tile[];
  /** how it works, three steps */
  steps: Step[];
  faq: [string, string][];
  /** three paths of related pages */
  related: string[];
}

export type Mark = "yes" | "no" | "part" | "";
export interface Row { k: string; us: [Mark, string]; them: [Mark, string] }

export interface Comparison {
  kind: "compare";
  /** the other product's name */
  them: string;
  h1: string;
  sub: string;
  answer: string;
  rows: Row[];
  fitThem: string[];
  fitUs: string[];
  /** a line under the cards */
  note?: string;
  faq: [string, string][];
  sources: [string, string][];
  related: string[];
}

/** One sentence of product facts, the same on every page. */
export const FACTS = "Glasspad is free and open source (MIT). It needs a Mac on macOS 14 or later and an iPhone on iOS 18 or later, on the same Wi-Fi.";

export const CONTENT: Record<string, Feature | Comparison> = {
  "/use/iphone-as-mac-trackpad": {
    kind: "feature",
    h1: "Use your iPhone as a Mac trackpad",
    sub: "Real gestures, and a tap you can feel on every click.",
    visual: "trackpad",
    visualLabel: "Try it: an iPhone held sideways as a trackpad beside a Mac",
    answer: "macOS has no built-in way to use an iPhone as a trackpad, so you need an app on both devices. Glasspad is a free, open source one: it turns your iPhone into a trackpad for your Mac over Wi-Fi. One finger moves the pointer, a tap clicks and you feel it, two fingers scroll and pinch, and three fingers swipe between Spaces or open Mission Control, following your Mac's own trackpad settings.",
    shot: "trackpad",
    guide: ["/guide#modes", "Trackpad in the guide"],
    tiles: [
      { icon: "haptic", title: "A click you can feel", text: "Every tap clicks, and the iPhone taps back." },
      { icon: "pinch", title: "Your Mac's gestures", text: "Scroll with momentum, pinch, rotate, smart zoom and force click." },
      { icon: "spaces", title: "Spaces and Mission Control", text: "Three fingers swipe between Spaces, or up for Mission Control." },
      { icon: "sliders", title: "Follows your settings", text: "Gestures and pointer speed come from your Mac's trackpad settings." },
    ],
    steps: [
      { icon: "trackpad", title: "Turn the iPhone sideways", text: "Trackpad is the first mode. Held sideways, the pad is wider." },
      { icon: "hand", title: "Use your fingers", text: "One finger moves the pointer, a tap clicks, two scroll, three swipe." },
      { icon: "layout", title: "Add a keyboard", text: "The Type layout puts the trackpad beside the keyboard on one screen." },
    ],
    faq: [
      ["Can I use my iPhone as a trackpad without an app?", "No. Universal Control works between Macs and iPads, not iPhones, and iPhone Mirroring goes the other way: the Mac controls the iPhone. You need an app on the iPhone and a small helper on the Mac. <a href=\"/compare/universal-control\">Glasspad vs Universal Control</a>."],
      ["Does it use Bluetooth?", "No. The iPhone and the Mac talk over the same Wi-Fi network. They pair once with a QR code, and every message is encrypted."],
      ["Does it feel like a real trackpad?", "It reads your Mac's trackpad settings and pointer acceleration, draws in step with the Mac's display, and keeps motion smooth over short Wi-Fi gaps. Touches are read at 120 Hz on ProMotion iPhones. On a crowded or weak network you will notice more lag than with a Magic Trackpad."],
      ["My Mac's trackpad is broken. Can this replace it?", "Once it is set up, yes. Installing it needs a few clicks on the Mac (Xcode, your Apple ID, Accessibility), so borrow a mouse for the first install."],
      ["Is it free?", "Yes, all of it. There are no ads, accounts, subscriptions or in-app purchases, and the code is on GitHub under the MIT License."],
    ],
    related: ["/use/iphone-as-mac-keyboard", "/use/iphone-remote-for-mac", "/compare/remote-mouse"],
  },

  "/use/iphone-as-mac-keyboard": {
    kind: "feature",
    h1: "Use your iPhone as a Mac keyboard",
    sub: "Type or dictate on the iPhone. The words land on the Mac.",
    visual: "keys",
    visualLabel: "Keyboard on an iPhone: the words typed on it appear in Notes on a Mac",
    answer: "To type on your Mac from your iPhone, you need an app on both. Glasspad is a free, open source one: in its Keyboard mode, what you type or dictate on the iPhone lands wherever the cursor is on your Mac, over Wi-Fi. It has control, option, command and shift, the usual shortcuts, arrows, and F1 to F12, and it works with any Mac keyboard layout.",
    shot: "keyboard",
    guide: ["/guide#modes", "Keyboard in the guide"],
    tiles: [
      { icon: "keyboard", title: "Type anywhere", text: "Text lands wherever the cursor is on the Mac." },
      { icon: "mic", title: "Dictate", text: "Tap the microphone, speak, and the words are typed on the Mac." },
      { icon: "command", title: "Every key you need", text: "control, option, command, shift, shortcuts, arrows, and fn for F1 to F12." },
      { icon: "clipboard", title: "Send a long text", text: "Clipboard, at the end of the shortcut row, sends text or an image both ways." },
    ],
    steps: [
      { icon: "menu", title: "Open Keyboard", text: "Tap the mode button at the top of the screen, then Keyboard." },
      { icon: "keyboard", title: "Type or dictate", text: "Hold a key to repeat it, or tap the microphone and speak." },
      { icon: "layout", title: "Keep the trackpad close", text: "The Type layout puts the keyboard beside the trackpad." },
    ],
    faq: [
      ["Can I dictate on my Mac with my iPhone?", "Yes. In Keyboard, tap the microphone on the iPhone keyboard and speak. The words are typed on the Mac."],
      ["Does it work with my keyboard layout?", "Yes. Keys are sent for the Mac's own keyboard layout, whichever it is."],
      ["Can I send a long text from my iPhone?", "Copy it on the iPhone, tap Clipboard at the end of Keyboard's shortcut row, then tap Paste under Send to Mac. It is then on the Mac's clipboard, ready to paste."],
      ["Is what I type sent over the internet?", "No. Glasspad pairs once with a QR code, encrypts everything, and your iPhone and Mac talk only over your Wi-Fi. There is no account."],
    ],
    related: ["/use/iphone-as-mac-trackpad", "/use/stream-deck-alternative-mac", "/use/iphone-remote-for-mac"],
  },

  "/use/iphone-remote-for-mac": {
    kind: "feature",
    h1: "An iPhone remote for your Mac",
    sub: "Netflix, YouTube and Spotify from the couch, like a Siri Remote.",
    visual: "couch",
    visualLabel: "A film on a TV plugged into a Mac, and Remote on an iPhone in hand: a swipe skips ahead, a slide turns it up, a tap pauses",
    answer: "Glasspad's Remote mode turns your iPhone into a remote for whatever plays on your Mac, much like a Siri Remote: tap the pad to play or pause, swipe sideways to skip 10 seconds, and up or down for volume. Its buttons follow the player, such as Skip Intro on Netflix and Subtitles and Next on YouTube. It works with YouTube, Netflix, Prime Video, Disney+, Apple TV, QuickTime Player, IINA, VLC, Infuse, Spotify and Music. Glasspad is free and open source.",
    shot: "remote",
    guide: ["/guide#modes", "Remote in the guide"],
    tiles: [
      { icon: "hand", title: "A pad like the Siri Remote", text: "Tap to pause. Swipe to skip 10 seconds, up or down for volume." },
      { icon: "captions", title: "Buttons that follow the player", text: "Skip Intro on Netflix, Subtitles and Next on YouTube." },
      { icon: "search", title: "Search from the couch", text: "Search types on the Mac and presses Return." },
      { icon: "moon", title: "Dark and dim", text: "The screen stays dark, so it does not light up the room." },
    ],
    steps: [
      { icon: "menu", title: "Open Remote", text: "Tap the mode button at the top of the screen, then Remote." },
      { icon: "play", title: "Play anything", text: "Netflix or YouTube in Safari, Chrome, Firefox, Edge, Brave or Arc, or a player app." },
      { icon: "couch", title: "Sit back", text: "The Couch layout puts Remote and a trackpad on one screen." },
    ],
    faq: [
      ["Does it work with Netflix in Safari or Chrome?", "Yes. Netflix and YouTube on a Mac play in the browser, and Remote works in Safari, Chrome, Firefox, Edge, Brave and Arc."],
      ["Do I need an Apple TV?", "No. The iPhone talks to the Mac directly over your Wi-Fi. Nothing else is needed."],
      ["Can I change the Mac's volume from the couch?", "Yes. Swipe up or down on the pad, or use Media for the volume slider and the sound output."],
      ["Can I keep the trackpad close by?", "Yes. The Couch layout puts Remote and a trackpad on one screen."],
    ],
    related: ["/use/iphone-as-mac-trackpad", "/use/control-mac-displays-from-iphone", "/use/iphone-as-mac-keyboard"],
  },

  "/use/stream-deck-alternative-mac": {
    kind: "feature",
    h1: "A free Stream Deck alternative for Mac",
    sub: "Buttons for the app in front, and your own. On the iPhone you have.",
    visual: "studio",
    visualLabel: "Final Cut Pro on a MacBook, and its buttons on an iPhone on a stand: Play, Blade at Playhead and Mark In edit the timeline",
    answer: "Glasspad turns your iPhone into a deck of buttons for your Mac, free. Its Actions mode shows buttons for the app in front, ready made for more than 70 apps, and below them your own: apps, websites, keyboard shortcuts, recorded macros, shortcuts from the Shortcuts app, and Mac controls like Do Not Disturb, Night Shift, Keep Awake and Split Screen. There are no key limits, ads or subscriptions, and it is open source (MIT). It has no physical keys and no plugins for tools like OBS, so for live streaming a Stream Deck is still the better fit.",
    shot: "actions",
    guide: ["/guide#yours", "Actions in the guide"],
    tiles: [
      { icon: "actions", title: "Follows the app in front", text: "Ready-made buttons for more than 70 apps." },
      { icon: "pin", title: "Pin your own", text: "Apps, websites with their logos, shortcuts and Mac controls." },
      { icon: "record", title: "Macros", text: "Record steps on your Mac once, then replay them with a tap." },
      { icon: "free", title: "No key limits", text: "Every button free, with no ads and no subscription." },
    ],
    steps: [
      { icon: "menu", title: "Open Actions", text: "Tap the mode button at the top of the screen, then Actions." },
      { icon: "search", title: "Add from the Library", text: "Every app, Mac control, macro, shortcut and website, with search." },
      { icon: "folder", title: "Make it yours", text: "Touch and hold a button to change its name, symbol, color and size." },
    ],
    faq: [
      ["Is it really free?", "Yes. Every feature, with no limit on pinned buttons, no ads and no subscription. The code is under the MIT License."],
      ["Can it run my Shortcuts?", "Yes. Any shortcut from the Shortcuts app on your Mac can be a button."],
      ["Can a button press a keyboard shortcut?", "Yes. Add a Keyboard Shortcut button and set the keys, such as command C, or a hotkey you set in another app."],
      ["Does it work with OBS or Twitch?", "Only through keyboard shortcuts you set up in those apps. Glasspad has no streaming plugins; Stream Deck has many. <a href=\"/compare/stream-deck-mobile\">Glasspad vs Stream Deck Mobile</a>."],
      ["Does it work with Windows or Android?", "No. Glasspad is for an iPhone and a Mac only."],
    ],
    related: ["/compare/stream-deck-mobile", "/use/mac-split-screen-from-iphone", "/use/iphone-as-mac-keyboard"],
  },

  "/use/mac-split-screen-from-iphone": {
    kind: "feature",
    h1: "Split screen on your Mac from your iPhone",
    sub: "Two windows side by side, top and bottom or in quarters, in one tap.",
    visual: "desk",
    visualLabel: "A Mac desk with a display, a MacBook and an iPhone on a stand: tapping Split Screen on the iPhone puts Safari and Xcode side by side",
    answer: "On a Mac you split the screen from the green button at the top left of a window, or, on macOS 15 and later, by pressing fn, control and the left or right arrow. Glasspad puts this on your iPhone: tap Split Screen, choose Left &amp; Right, Top &amp; Bottom, Quarters or Full Screen (Split View), pick the windows and the display, and see where each one will go before anything moves. Window buttons put the front window on a half or a quarter, Fill or Center.",
    shot: "folder",
    guide: ["/guide#yours", "Actions in the guide"],
    tiles: [
      { icon: "halves", title: "Four ways to split", text: "Left &amp; Right, Top &amp; Bottom, Quarters or Full Screen." },
      { icon: "quarters", title: "Window buttons", text: "Halves, quarters, Fill and Center for the front window." },
      { icon: "display", title: "Any display", text: "Pick the display, or send the front window to the next one." },
      { icon: "check", title: "See it first", text: "Arrange shows where each window will go before anything moves." },
    ],
    steps: [
      { icon: "pin", title: "Add Split Screen", text: "Pin it in Actions from the Library, or keep it in a folder." },
      { icon: "split", title: "Tap it", text: "Choose how to split, then the windows and the display." },
      { icon: "displays", title: "Or use Displays", text: "Touch and hold any window for the halves, Fill, Center and Split With." },
    ],
    faq: [
      ["What is the keyboard shortcut for split screen on a Mac?", "On macOS 15 and later, fn control left arrow puts the front window on the left half and fn control right arrow on the right. Add shift to arrange the next window on the other half too. The same moves are in Window &rsaquo; Move &amp; Resize."],
      ["What is the difference between tiling and Split View?", "Tiled windows stay on your desktop with everything else. Split View puts two windows side by side in full screen, in a Space of their own. Glasspad does both: Left &amp; Right tiles, Full Screen makes a Split View."],
      ["Does it work with two displays?", "Yes. Pick the display in Arrange. If the windows are on different displays, the second one moves over first."],
      ["What if an app's window will not get narrow enough?", "Some apps have a minimum width. Glasspad tells you which window will not fit instead of leaving them overlapped."],
      ["Does it leave room for Stage Manager?", "Yes. Tiling keeps clear of Stage Manager's strip of apps."],
    ],
    related: ["/use/control-mac-displays-from-iphone", "/use/stream-deck-alternative-mac", "/use/iphone-as-mac-trackpad"],
  },

  "/use/control-mac-displays-from-iphone": {
    kind: "feature",
    h1: "Control your Mac's displays from your iPhone",
    sub: "Move a window to another display, tile it, and set brightness.",
    visual: "displays",
    visualLabel: "Displays on an iPhone held sideways: Mail is dragged from the MacBook to the Studio Display, then fills it",
    answer: "Glasspad's Displays mode shows your Mac's displays on your iPhone the way System Settings draws them, with every window on them. Tap a window to bring it forward, drag it to another display, or touch and hold it to tile, split, enter full screen, minimize or close it. Its settings set brightness, resolution, Night Shift, the main display, mirroring and the arrangement, and a new resolution goes back after 15 seconds unless you keep it.",
    shot: "displays",
    guide: ["/guide#modes", "Displays in the guide"],
    tiles: [
      { icon: "displays", title: "As in System Settings", text: "Your displays, drawn where they sit, with every window on them." },
      { icon: "hand", title: "Drag between displays", text: "Drag a window onto another display, or tap it to bring it forward." },
      { icon: "halves", title: "Tile and split", text: "Touch and hold a window for the halves, Fill, Center and Split With." },
      { icon: "sun", title: "Brightness and more", text: "Brightness, resolution, Night Shift, mirroring and the main display." },
    ],
    steps: [
      { icon: "menu", title: "Open Displays", text: "Tap the mode button at the top of the screen, then Displays." },
      { icon: "hand", title: "Move a window", text: "Drag it to another display, or touch and hold it for more." },
      { icon: "undo", title: "Change a setting safely", text: "A new resolution goes back after 15 seconds unless you keep it." },
    ],
    faq: [
      ["Can I move a window to another monitor from my iPhone?", "Yes. Drag it onto the other display in Displays, or tap a Next Display button in Actions."],
      ["Can I change the resolution from my iPhone?", "Yes, in the settings in Displays. A new resolution or mirroring goes back after 15 seconds unless you keep it, so a blank screen fixes itself."],
      ["Does it work with one display?", "Yes. You still get the list of windows, and tiling, brightness, resolution and Night Shift."],
      ["What does the Mac need to allow?", "Accessibility, in System Settings &rsaquo; Privacy &amp; Security, so Glasspad can move windows. The installer walks you through it."],
    ],
    related: ["/use/mac-split-screen-from-iphone", "/use/stream-deck-alternative-mac", "/use/iphone-remote-for-mac"],
  },

  "/compare/stream-deck-mobile": {
    kind: "compare",
    them: "Stream Deck Mobile",
    h1: "Glasspad vs Stream Deck Mobile",
    sub: "Two ways to put buttons for your Mac on your iPhone.",
    answer: "Stream Deck Mobile, from Elgato, turns an iPhone or iPad into Stream Deck keys for a Mac or Windows PC running the Stream Deck app, with hundreds of plugins for streaming and creative tools. It is free for 6 keys; Pro gives up to 64 and costs $2.99 a month, $24.99 a year or $49.99 once. Glasspad is a free, open source iPhone app for the Mac only, with no key limit and buttons that change with the app in front, plus a trackpad, keyboard, remote and window control. For live streaming, Stream Deck's plugins make it the stronger choice.",
    rows: [
      { k: "Devices", us: ["part", "iPhone (iOS 18 or later) with a Mac (macOS 14 or later)"], them: ["yes", "iPhone or iPad (iOS 17 or later) with a Mac or Windows PC; Android with Pro"] },
      { k: "Price", us: ["yes", "Free, everything"], them: ["part", "Free for 6 keys. Pro: $2.99 a month, $24.99 a year or $49.99 once"] },
      { k: "Keys", us: ["yes", "No limit on pinned buttons, plus up to 8 for each app"], them: ["part", "6 free, up to 64 with Pro"] },
      { k: "Plugins", us: ["no", "None. Buttons are apps, websites, keyboard shortcuts, macros, Shortcuts and Mac controls"], them: ["yes", "Hundreds, for OBS, Twitch, music and more"] },
      { k: "Per app", us: ["yes", "Ready-made buttons for 70+ apps, following the app in front"], them: ["part", "Profiles can switch with the app in front"] },
      { k: "Also", us: ["yes", "Trackpad, keyboard, media, remote, Dock, displays and window tiling"], them: ["", "Stream Deck keys"] },
      { k: "Install", us: ["part", "One-line installer that builds the app with Xcode and a free Apple ID"], them: ["yes", "App Store, plus the Stream Deck app on the computer"] },
      { k: "Source code", us: ["yes", "Open source, MIT"], them: ["no", "Not open source"] },
    ],
    fitThem: [
      "You stream, and want OBS scenes, Twitch and other plugins.",
      "You already use a Stream Deck and want the same profiles on your phone.",
      "You use Windows, an iPad or Android.",
    ],
    fitUs: [
      "You want a free deck with no key limit for everyday Mac work.",
      "You want buttons that change with the app in front, ready made.",
      "You want the same iPhone to be a trackpad, keyboard and remote too.",
    ],
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
    related: ["/use/stream-deck-alternative-mac", "/compare/remote-mouse", "/compare/universal-control"],
  },

  "/compare/remote-mouse": {
    kind: "compare",
    them: "Remote Mouse",
    h1: "Glasspad vs Remote Mouse",
    sub: "Two ways to turn a phone into a mouse and keyboard for your computer.",
    answer: "Remote Mouse and Glasspad both turn a phone into a mouse, keyboard and media remote for a computer over Wi-Fi. Remote Mouse works on iPhone and Android with Mac, Windows and Linux, installs from the App Store, and is free with ads and paid extras. Glasspad is for iPhone and Mac only, free with no ads or purchases, and open source (MIT). It adds a trackpad with haptics that follows your Mac's own gestures, buttons for the app in front, and window and display control. It is not on the App Store, so installing it takes more steps.",
    rows: [
      { k: "Phone", us: ["part", "iPhone (iOS 18 or later)"], them: ["yes", "iPhone and iPad (iOS 15 or later), and Android"] },
      { k: "Computer", us: ["part", "Mac (macOS 14 or later)"], them: ["yes", "Mac, Windows and Linux"] },
      { k: "Install", us: ["part", "One-line installer that builds the app with Xcode and a free Apple ID; the Mac renews it every 7 days"], them: ["yes", "App Store or Google Play, plus a helper app on the computer"] },
      { k: "Price", us: ["yes", "Free. No ads or in-app purchases"], them: ["part", "Free with ads. Pro is $1.49 a month or $13.99 a year; Remove Ads is $0.99"] },
      { k: "Source code", us: ["yes", "Open source, MIT"], them: ["no", "Not open source"] },
      { k: "Connection", us: ["yes", "Same Wi-Fi, paired by QR code, encrypted"], them: ["", "Same Wi-Fi"] },
      { k: "Trackpad", us: ["yes", "Your Mac's own gestures: Spaces, Mission Control, pinch, rotate, force click, with haptics"], them: ["part", "Touchpad, plus a mouse you move by tilting the phone"] },
      { k: "Also", us: ["yes", "Media, Remote, Dock, buttons for 70+ apps, macros, Shortcuts, Present, Clipboard, Displays, Layouts"], them: ["", "Media and web remotes, app switcher, power options, voice typing, clipboard"] },
    ],
    fitThem: [
      "You use Windows, Linux or an Android phone.",
      "You want to install from the App Store in a minute.",
    ],
    fitUs: [
      "You have an iPhone and a Mac and want the Mac's own trackpad gestures.",
      "You want everything free, with no ads, and code you can read.",
      "You want buttons for the app in front, window tiling and display control too.",
    ],
    faq: [
      ["Is Glasspad an open source alternative to Remote Mouse?", "Yes. Glasspad's code is on GitHub under the MIT License, and every feature is free. It works only with an iPhone and a Mac."],
      ["Why is Glasspad not on the App Store?", "The Mac app uses system features that the App Store does not allow. Instead, the installer builds both apps on your Mac with Xcode and your free Apple ID."],
      ["Does Glasspad work on Windows?", "No. For Windows or Linux, Remote Mouse is a good choice."],
      ["Do I need to pay Apple to install Glasspad?", "No. A free Apple ID is enough. Apps installed that way stop opening after 7 days, and your Mac renews Glasspad over Wi-Fi before then."],
    ],
    sources: [
      ["Remote Mouse website: features and platforms", "https://www.remotemouse.net/"],
      ["Remote Mouse on the App Store: prices and requirements", "https://apps.apple.com/us/app/remote-mouse/id385894596"],
    ],
    related: ["/use/iphone-as-mac-trackpad", "/compare/universal-control", "/compare/stream-deck-mobile"],
  },

  "/compare/universal-control": {
    kind: "compare",
    them: "Universal Control",
    h1: "Glasspad vs Universal Control",
    sub: "Universal Control does not work with iPhone. Here is what does.",
    answer: "Universal Control does not work with iPhone. It lets one Mac's keyboard and trackpad control up to two other Macs or iPads nearby (macOS 12.4 and iPadOS 15.4 or later, signed in to the same Apple Account). iPhone Mirroring goes the other way: your Mac controls your iPhone. To control a Mac from an iPhone you need an app. Glasspad is a free, open source one that makes the iPhone a trackpad, keyboard, remote and button deck for the Mac over Wi-Fi.",
    rows: [
      { k: "Direction", us: ["", "iPhone controls the Mac"], them: ["", "A Mac's keyboard and trackpad control other Macs and iPads"] },
      { k: "iPhone", us: ["yes", "iPhone (iOS 18 or later) with a Mac (macOS 14 or later)"], them: ["no", "No iPhone. A Mac (macOS 12.4 or later) with up to two Macs or iPads (iPadOS 15.4 or later)"] },
      { k: "Setup", us: ["part", "Install with the one-line installer, pair once by QR code"], them: ["yes", "Built in. Same Apple Account with two-factor authentication"] },
      { k: "Connection", us: ["", "Same Wi-Fi"], them: ["", "Bluetooth, Wi-Fi and Handoff on, within 10 meters"] },
      { k: "What you get", us: ["", "Trackpad, keyboard, media, remote, buttons, displays and windows"], them: ["", "One pointer and keyboard across screens, drag and drop between them"] },
      { k: "Price", us: ["yes", "Free, open source (MIT)"], them: ["yes", "Free, part of macOS and iPadOS"] },
    ],
    fitThem: [
      "You have an iPad or a second Mac on your desk.",
      "You want one keyboard and trackpad across them, with drag and drop.",
    ],
    fitUs: [
      "You want your iPhone to control your Mac.",
      "You want a remote for the couch, a deck of buttons, or a spare trackpad.",
    ],
    note: "They work side by side: Glasspad does not replace Universal Control.",
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
    related: ["/use/iphone-as-mac-trackpad", "/use/iphone-as-mac-keyboard", "/compare/remote-mouse"],
  },
};
