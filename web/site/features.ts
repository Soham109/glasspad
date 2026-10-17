/* The words on the Features and Compare pages, keyed by path in site/pages.ts.
   site/render.ts lays every one out the same way, so a new page is a new entry here.
   Answers and table cells are HTML (links, <code> and entities only). */

export type Shot = "trackpad" | "keyboard" | "remote" | "media" | "actions" | "library" | "folder" | "website" | "displays" | "clipboard" | "menu" | "layouts" | "present" | "standby" | "dock";

/** Real app screens from docs/img/screens (copied to /img/screens by scripts/sync-screens.mjs). */
export const SHOTS: Record<Shot, { w: number; h: number; alt: string }> = {
  trackpad: { w: 1280, h: 698, alt: "Trackpad on an iPhone held sideways, with three finger dots" },
  keyboard: { w: 700, h: 1288, alt: "Keyboard on an iPhone: modifier keys, shortcuts and arrows above the iPhone keyboard" },
  remote: { w: 700, h: 1288, alt: "Remote on an iPhone for a movie on Netflix in Safari: a large touch pad, skip and pause buttons, then Search, Skip Intro, Full Screen and Mute" },
  media: { w: 700, h: 1288, alt: "Media on an iPhone: artwork, the song, scrubber, controls, volume and brightness" },
  actions: { w: 700, h: 1288, alt: "Actions on an iPhone: Safari's buttons on top, Pinned buttons below" },
  library: { w: 700, h: 1288, alt: "Library on an iPhone: search, Pinned, Record New Macro, and apps with add buttons" },
  folder: { w: 700, h: 1288, alt: "Actions on an iPhone with the Windows folder open: Left Half, Right Half, Fill, Split Screen and Next Display" },
  website: { w: 700, h: 1288, alt: "Edit Button on an iPhone for a GitHub website button, with name, symbol, color and size" },
  displays: { w: 700, h: 1288, alt: "Displays on an iPhone: two displays drawn as in System Settings, and the list of windows on them" },
  clipboard: { w: 700, h: 1288, alt: "Clipboard on an iPhone: Send to Mac with Paste, Get from Mac with its button" },
  menu: { w: 700, h: 1288, alt: "The mode menu on an iPhone: Trackpad, Keyboard, Media, Dock and Actions, then Layouts, then Present, Remote and Displays" },
  layouts: { w: 1280, h: 698, alt: "A layout on an iPhone held sideways: Media beside Actions" },
  present: { w: 700, h: 1288, alt: "Present on an iPhone: the talk timer, a pad to touch and hold for the laser, and large Back and Next buttons" },
  standby: { w: 1280, h: 698, alt: "StandBy on an iPhone held sideways: a large clock beside Now Playing" },
  dock: { w: 700, h: 1288, alt: "Dock on an iPhone: the Mac's apps in a grid, with dots under the open ones" },
};

export interface Tile { icon: string; title: string; text: string }
export interface Step { icon: string; title: string; text: string }

/** A longer part of a page, built only from the blocks the templates already use:
   "text" is an answer card, "cards" the Compare page's fit cards, "table" the Compare table. */
export type Section =
  | { kind: "text"; title: string; text: string; note?: string }
  | { kind: "cards"; title: string; cards: { title: string; points: string[]; us?: boolean }[]; note?: string }
  | { kind: "table"; title: string; caption: string; cols: [string, string]; rows: Row[]; note?: string };

export interface Feature {
  kind: "feature";
  /** the page's one <h1>: short, with the words people search for */
  h1: string;
  /** one line under the headline */
  sub: string;
  /** the drawn, animated scene from src/ shown under the hero (src/page.ts mounts it) */
  visual: "trackpad" | "keys" | "media" | "clipboard" | "couch" | "studio" | "desk" | "presenter" | "displays";
  /** what the scene shows, for people who cannot see it */
  visualLabel: string;
  /** the answer quoted in "In short": what it is and how Glasspad does it, in a few sentences */
  answer: string;
  /** the real app screen beside the answer, one the drawing above does not already show */
  shot: Shot;
  /** a line under that screen */
  caption: string;
  /** the matching part of the guide: [href, link text] */
  guide: [string, string];
  /** three or four benefits */
  tiles: Tile[];
  /** how it works, three steps */
  steps: Step[];
  /** parts shown right after "In short" */
  early?: Section[];
  /** parts shown after "How it works" */
  more?: Section[];
  faq: [string, string][];
  /** three paths of related pages */
  related: string[];
  /** where third-party facts on the page come from, and the day they were read */
  sources?: [string, string][];
  checked?: string;
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
  /** parts shown after "Which one fits you" */
  more?: Section[];
  /** a line under the cards */
  note?: string;
  /** a real app screen beside the answer, and a line under it */
  shot?: Shot;
  caption?: string;
  faq: [string, string][];
  sources: [string, string][];
  /** the day the sources were read, as the page says it: "October 17, 2026" */
  checked?: string;
  related: string[];
}

/** One sentence of product facts, the same on every page. */
export const FACTS = "Glasspad is free and open source (MIT). It needs a Mac on macOS 14 or later and an iPhone on iOS 18 or later, on the same Wi-Fi.";

export const CONTENT: Record<string, Feature | Comparison> = {
  "/use/iphone-as-mac-trackpad": {
    kind: "feature",
    h1: "Use your iPhone as a mouse and trackpad for your Mac",
    sub: "Real gestures, and a tap you can feel on every click.",
    visual: "trackpad",
    visualLabel: "Try it: an iPhone held sideways as a trackpad beside a Mac",
    answer: "macOS has no built-in way to use an iPhone as a mouse or trackpad, so you need an app on both devices. Glasspad is a free, open source one: it turns your iPhone into a trackpad for your Mac, MacBook or Mac mini over Wi-Fi. One finger moves the pointer, a tap clicks and you feel it, two fingers scroll and pinch, and three fingers swipe between Spaces or open Mission Control, following your Mac's own trackpad settings.",
    shot: "trackpad",
    caption: "Trackpad in the app, held sideways.",
    guide: ["/guide#trackpad", "Trackpad in the guide"],
    early: [
      { kind: "text", title: "Is there a built-in way?", text: "No. Universal Control shares one Mac's keyboard and trackpad with other Macs and iPads, not with an iPhone. iPhone Mirroring goes the other way: your Mac controls your iPhone. Switch Control can drive a Mac from an iPhone, but it is an accessibility feature that steps through items on the screen, not a pointer you move with your finger. To use the iPhone like a mouse, you need an app on the iPhone and a small helper on the Mac.", note: "More on this: <a href=\"/use/control-mac-from-iphone\">every way to control your Mac from your iPhone</a>." },
    ],
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
      ["Can I use my iPhone as a mouse for my MacBook?", "Yes. Glasspad works with any MacBook, iMac, Mac mini or Mac Studio on macOS 14 or later. The iPhone works as a trackpad rather than a mouse you push around: you move the pointer with your finger, as on a MacBook's own trackpad."],
      ["Can I use my iPhone as a trackpad without an app?", "No. Universal Control works between Macs and iPads, not iPhones, and iPhone Mirroring goes the other way: the Mac controls the iPhone. You need an app on the iPhone and a small helper on the Mac. <a href=\"/compare/universal-control\">Glasspad vs Universal Control</a>."],
      ["Does it use Bluetooth?", "No. The iPhone and the Mac talk over the same Wi-Fi network. They pair once with a QR code, and every message is encrypted."],
      ["Does it feel like a real trackpad?", "It reads your Mac's trackpad settings and pointer acceleration, draws in step with the Mac's display, and keeps motion smooth over short Wi-Fi gaps. Touches are read at 120 Hz on ProMotion iPhones. On a crowded or weak network you will notice more lag than with a Magic Trackpad."],
      ["My Mac's trackpad is broken. Can this replace it?", "Once it is set up, yes. Installing it needs a few clicks on the Mac (Xcode, your Apple ID, Accessibility), so borrow a mouse for the first install."],
      ["Is it free?", "Yes, all of it. There are no ads, accounts, subscriptions or in-app purchases, and the code is on GitHub under the MIT License."],
    ],
    more: [
      {
        kind: "table", title: "Every gesture", caption: "Trackpad gestures on the iPhone and what the Mac does",
        cols: ["On your iPhone", "What your Mac does"],
        rows: [
          { k: "Move", us: ["", "Slide one finger"], them: ["", "The pointer moves, at your Mac's tracking speed"] },
          { k: "Click", us: ["", "Tap with one finger"], them: ["", "A click, and the iPhone taps back"] },
          { k: "Force click", us: ["", "Hold a finger still for a moment"], them: ["", "Look up, or a preview, as on a Magic Trackpad"] },
          { k: "Right click", us: ["", "Tap with two fingers"], them: ["", "The menu for what is under the pointer"] },
          { k: "Scroll", us: ["", "Slide two fingers"], them: ["", "Scrolls, with momentum, in your Mac's scroll direction"] },
          { k: "Zoom", us: ["", "Pinch with two fingers"], them: ["", "Zooms in or out"] },
          { k: "Spaces", us: ["", "Swipe three fingers sideways"], them: ["", "Moves to the next or previous Space"] },
          { k: "Mission Control", us: ["", "Swipe three fingers up"], them: ["", "Shows every open window"] },
        ],
      },
      { kind: "text", title: "With a Mac mini, Mac Studio or a broken trackpad", text: "Glasspad works with any Mac on macOS 14 or later, including a Mac mini or Mac Studio with no trackpad of its own. The first install needs a few clicks on the Mac (Xcode, your Apple ID and the Accessibility permission), so borrow a mouse and keyboard for that. After that the iPhone can be the Mac's trackpad and keyboard: the Type layout puts both on one screen, with the iPhone held sideways." },
    ],
    related: ["/use/iphone-as-mac-keyboard", "/use/iphone-remote-for-mac", "/compare/remote-mouse"],
  },

  "/use/iphone-as-mac-keyboard": {
    kind: "feature",
    h1: "Use your iPhone as a Mac keyboard",
    sub: "Type or dictate on the iPhone. The words land on the Mac.",
    visual: "keys",
    visualLabel: "Keyboard on an iPhone: the words typed on it appear in Notes on a Mac",
    answer: "To type on your Mac from your iPhone, you need an app on both. Glasspad is a free, open source one: in its Keyboard mode, what you type or dictate on the iPhone lands wherever the cursor is on your Mac, over Wi-Fi. It has Control, Option, Command and Shift, the usual shortcuts, arrows, and F1 to F12, and it works with any Mac keyboard layout.",
    shot: "clipboard",
    caption: "Clipboard in the app: Send to Mac and Get from Mac.",
    guide: ["/guide#keyboard", "Keyboard in the guide"],
    tiles: [
      { icon: "keyboard", title: "Type anywhere", text: "Text lands wherever the cursor is on the Mac." },
      { icon: "mic", title: "Dictate", text: "Tap the microphone, speak, and the words are typed on the Mac." },
      { icon: "command", title: "Every key you need", text: "Control, Option, Command, Shift, shortcuts, arrows, and Fn for F1 to F12." },
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
      ["Can I use my iPhone as a mouse and keyboard together?", "Yes. The Type layout puts the trackpad beside the keyboard on one screen, with the iPhone held sideways. It is useful with a Mac mini that has no keyboard or mouse nearby."],
      ["Is what I type sent over the internet?", "No. Glasspad pairs once with a QR code, encrypts everything, and your iPhone and Mac talk only over your Wi-Fi. There is no account."],
    ],
    related: ["/use/iphone-as-mac-trackpad", "/use/stream-deck-alternative-mac", "/use/iphone-remote-for-mac"],
  },

  "/use/iphone-remote-for-mac": {
    kind: "feature",
    h1: "Your iPhone as a remote for your Mac",
    sub: "Netflix, YouTube and Spotify from the couch, like a Siri Remote.",
    visual: "couch",
    visualLabel: "A movie on a TV plugged into a Mac, and Remote on an iPhone in hand: a swipe skips ahead, a slide turns it up, a tap pauses",
    answer: "Glasspad's Remote mode turns your iPhone into a remote for whatever plays on your Mac, much like a Siri Remote: tap the pad to play or pause, swipe sideways to skip 10 seconds, and up or down for volume. Its buttons follow the player, such as Skip Intro on Netflix and Subtitles and Next on YouTube. It works with YouTube, Netflix, Prime Video, Disney+, Apple TV, QuickTime Player, IINA, VLC, Infuse, Spotify and Music. Glasspad is free and open source.",
    shot: "media",
    caption: "Media shows what is playing, with volume, sound output and brightness.",
    guide: ["/guide#remote", "Remote in the guide"],
    early: [
      {
        kind: "cards", title: "What it works with",
        cards: [
          { title: "Movies and shows: Remote", points: ["YouTube, Netflix, Prime Video, Disney+ and Apple TV in Safari, Chrome, Firefox, Edge, Brave or Arc.", "QuickTime Player, IINA, VLC and Infuse.", "A pad like the Siri Remote, with buttons that follow the player."] },
          { title: "Music and podcasts: Media", points: ["Spotify, Music, Podcasts or a browser: the artwork, the song and a scrubber.", "Play, pause, next, previous, shuffle and repeat.", "The Mac's volume, its sound output, such as speakers or AirPods, and the screen's brightness."] },
        ],
      },
    ],
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
      ["Can I control Spotify on my Mac from my iPhone?", "Yes. Media plays, pauses, skips and scrubs the Spotify app on your Mac, and shows what it plays. It controls the app on the Mac itself, so it works whatever your Spotify plan."],
      ["Can I put the Mac's display to sleep from the couch?", "Yes. Remote's More menu has Sleep Display, Do Not Disturb and the sound output."],
      ["Does it work with a MacBook plugged into a TV?", "Yes. Remote controls whatever plays on the Mac, on any display, and the Mac's volume, which is the TV's sound when the TV is the sound output."],
    ],
    related: ["/use/iphone-as-mac-trackpad", "/use/control-mac-displays-from-iphone", "/use/iphone-as-mac-keyboard"],
  },

  "/use/stream-deck-alternative-mac": {
    kind: "feature",
    h1: "A free Stream Deck for your Mac, on an iPhone you already own",
    sub: "Buttons for the app in front, and your own. No key limits.",
    visual: "studio",
    visualLabel: "Final Cut Pro on a MacBook, and its buttons on an iPhone on a stand: Play, Blade at Playhead and Mark In edit the timeline",
    answer: "Glasspad turns your iPhone into a deck of buttons for your Mac, free. Its Actions mode shows buttons for the app in front, ready made for more than 70 apps, and below them your own: apps, websites, keyboard shortcuts, recorded macros, shortcuts from the Shortcuts app, and Mac controls like Do Not Disturb, Night Shift, Keep Awake and Split Screen. There are no key limits, ads or subscriptions, and it is open source (MIT). It has no physical keys and no plugins for tools like OBS, so for live streaming a Stream Deck is still the better fit.",
    shot: "library",
    caption: "The Library: every app, Mac control, macro, shortcut and website.",
    guide: ["/guide#actions", "Actions in the guide"],
    early: [
      { kind: "text", title: "Which iPhones work", text: "Any iPhone that runs iOS 18: iPhone XS, XS Max, XR, iPhone SE (2nd generation) and every newer model. An old one in a drawer makes a good deck on a stand beside the keyboard. It needs Wi-Fi, not a SIM card, and you can leave it on the charger.", note: "Not for streaming: Glasspad has no plugins for OBS, Twitch or other streaming tools. If you stream, a Stream Deck is the better fit. <a href=\"/compare/stream-deck-mobile\">Glasspad vs Stream Deck Mobile</a>." },
    ],
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
      ["Can a button press a keyboard shortcut?", "Yes. Add a Keyboard Shortcut button and set the keys, such as Command-C, or a hotkey you set in another app."],
      ["Does it work with OBS or Twitch?", "Only through keyboard shortcuts you set up in those apps. Glasspad has no streaming plugins; Stream Deck has many. <a href=\"/compare/stream-deck-mobile\">Glasspad vs Stream Deck Mobile</a>."],
      ["Does it work with Windows or Android?", "No. Glasspad is for an iPhone and a Mac only."],
      ["Will an iPhone X or iPhone 8 work?", "No. Glasspad needs iOS 18, which starts with the iPhone XS and XR."],
    ],
    related: ["/compare/stream-deck-mobile", "/use/mac-split-screen-from-iphone", "/use/iphone-as-mac-keyboard"],
    sources: [
      ["Macworld: iOS 18 compatibility, which iPhones are supported", "https://www.macworld.com/article/2420917/ios-18-compatibility-which-iphones.html"],
    ],
  },

  "/use/mac-split-screen-from-iphone": {
    kind: "feature",
    h1: "Split screen on your Mac from your iPhone",
    sub: "Two windows side by side, top and bottom or in quarters, in one tap.",
    visual: "desk",
    visualLabel: "A Mac desk with a display, a MacBook and an iPhone on a stand: tapping Split Screen on the iPhone puts Safari and Xcode side by side",
    answer: "On a Mac you split the screen from the green button at the top left of a window, or, on macOS 15 and later, by pressing fn, control and the left or right arrow. Glasspad puts this on your iPhone: tap Split Screen, choose Left &amp; Right, Top &amp; Bottom, Quarters or Full Screen (Split View), pick the windows and the display, and see where each one will go before anything moves. Window buttons put the front window on a half or a quarter, Fill or Center.",
    shot: "folder",
    caption: "Window buttons in a folder in Actions.",
    guide: ["/guide#displays", "Displays and Arrange in the guide"],
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
    more: [
      {
        kind: "table", title: "Mac split screen shortcuts", caption: "Window tiling keyboard shortcuts on macOS 15 and later, and the same move in Glasspad",
        cols: ["Keyboard shortcut, macOS 15 and later", "On your iPhone with Glasspad"],
        rows: [
          { k: "Left or right half", us: ["", "Fn-Control-Left Arrow, or Right Arrow"], them: ["yes", "Left Half or Right Half button"] },
          { k: "Top or bottom half", us: ["", "Fn-Control-Up Arrow, or Down Arrow"], them: ["yes", "Top Half or Bottom Half button"] },
          { k: "Fill the screen", us: ["", "Fn-Control-F"], them: ["yes", "Fill button"] },
          { k: "Center", us: ["", "Fn-Control-C"], them: ["yes", "Center button"] },
          { k: "One quarter", us: ["no", "No shortcut. Use Window &rsaquo; Move &amp; Resize"], them: ["yes", "Top Left, Top Right, Bottom Left and Bottom Right Quarter buttons"] },
          { k: "Back to the old size", us: ["", "Fn-Control-R"], them: ["yes", "Return to Previous Size button"] },
          { k: "Two windows side by side", us: ["", "Fn-Control-Shift-Left Arrow, or Right Arrow"], them: ["yes", "Split Screen, Left &amp; Right"] },
          { k: "Two windows top and bottom", us: ["", "Fn-Control-Shift-Up Arrow, or Down Arrow"], them: ["yes", "Split Screen, Top &amp; Bottom"] },
          { k: "Four windows in quarters", us: ["no", "No shortcut. Use Window &rsaquo; Move &amp; Resize"], them: ["yes", "Split Screen, Quarters"] },
          { k: "Three windows: one half and two quarters", us: ["", "Fn-Control-Option-Shift and an arrow"], them: ["no", "Not offered"] },
        ],
      },
      { kind: "text", title: "On macOS 14 Sonoma", text: "Window tiling, with its menu and these shortcuts, came with macOS 15. On macOS 14 the green button can still put two apps side by side in full screen Split View, but there is no shortcut to snap a window to a half. Glasspad's window buttons and Split Screen work on macOS 14 too: they move and size the windows themselves, through the Accessibility permission." },
    ],
    faq: [
      ["What is the keyboard shortcut for split screen on a Mac?", "On macOS 15 and later, Fn-Control-Left Arrow puts the front window on the left half and Fn-Control-Right Arrow on the right. Add Shift to arrange the next window on the other half too. The same moves are in Window &rsaquo; Move &amp; Resize."],
      ["How do I split my Mac screen top and bottom?", "On macOS 15 and later, press Fn-Control-Shift-Up Arrow to put the front window on top and the next one below it, or choose Window &rsaquo; Move &amp; Resize &rsaquo; Top &amp; Bottom. In Glasspad, tap Split Screen and choose Top &amp; Bottom."],
      ["Can I split my Mac screen into three or four?", "Into four, yes: Quarters, in Window &rsaquo; Move &amp; Resize or in Glasspad's Split Screen. Into three, macOS 15 has the &amp; Quarters moves (one half and two quarters) with Fn-Control-Option-Shift and an arrow; Glasspad does not offer those."],
      ["Why is split screen not working on my Mac?", "Tiling shortcuts need macOS 15 or later. Some apps have a minimum width and will not fit a half or a quarter. If dragging a window to the edge does nothing, check that tiling by dragging is on in System Settings, under Desktop &amp; Dock."],
      ["What is the difference between tiling and Split View?", "Tiled windows stay on your desktop with everything else. Split View puts two windows side by side in full screen, in a Space of their own. Glasspad does both: Left &amp; Right tiles, Full Screen makes a Split View."],
      ["Does it work with two displays?", "Yes. Pick the display in Arrange. If the windows are on different displays, the second one moves over first."],
      ["What if an app's window will not get narrow enough?", "Some apps have a minimum width. Glasspad tells you which window will not fit instead of leaving them overlapped."],
      ["Does it leave room for Stage Manager?", "Yes. Tiling keeps clear of Stage Manager's strip of apps."],
    ],
    related: ["/use/control-mac-displays-from-iphone", "/use/stream-deck-alternative-mac", "/use/iphone-as-mac-trackpad"],
    sources: [
      ["Apple: Mac window tiling icons and keyboard shortcuts", "https://support.apple.com/guide/mac-help/mchl9674d0b0/mac"],
      ["Apple: Tile windows on Mac", "https://support.apple.com/guide/mac-help/mchlef287e5d/mac"],
    ],
  },

  "/use/control-mac-displays-from-iphone": {
    kind: "feature",
    h1: "Control your Mac's displays from your iPhone",
    sub: "Move a window to another display, tile it, and set brightness.",
    visual: "displays",
    visualLabel: "Displays on an iPhone held sideways: Mail is dragged from the MacBook to the Studio Display, then fills it",
    answer: "Glasspad's Displays mode shows your Mac's displays on your iPhone the way System Settings draws them, with every window on them. Tap a window to bring it forward, drag it to another display, or touch and hold it to tile, split, enter full screen, minimize or close it. Its settings set brightness, resolution, Night Shift, the main display, mirroring and the arrangement, and a new resolution goes back after 15 seconds unless you keep it.",
    shot: "displays",
    caption: "Displays in the app: your displays, and every window on them.",
    guide: ["/guide#displays", "Displays in the guide"],
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
    answer: "Stream Deck Mobile, from Elgato, turns an iPhone or iPad into Stream Deck keys for a Mac or PC, free for 6 keys and paid for more. Glasspad is free and open source for iPhone and Mac, with no key limit and buttons that follow the app in front. For live streaming plugins, Stream Deck is stronger.",
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
    answer: "Remote Mouse turns an iPhone or Android phone into a mouse, keyboard and media remote for Mac, Windows or Linux, free with ads and paid extras. Glasspad is free with no ads, open source, and for iPhone and Mac only. It adds a haptic trackpad with Mac gestures and buttons for the app in front.",
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
      ["Why is Glasspad not on the App Store?", "The App Store needs Apple's paid developer program ($99 a year). Building from source with a free Apple ID keeps Glasspad free."],
      ["Does Glasspad work on Windows?", "No. For Windows or Linux, Remote Mouse is a good choice."],
      ["What other Remote Mouse alternatives are there for Mac?", "Mobile Mouse is a paid one for iPhone, iPad and Apple Watch, with Mac and Windows. <a href=\"/compare/mobile-mouse\">Glasspad vs Mobile Mouse</a> compares them."],
      ["Do I need to pay Apple to install Glasspad?", "No. A free Apple ID is enough. Apps installed that way stop opening after 7 days, and your Mac renews Glasspad over Wi-Fi before then."],
    ],
    sources: [
      ["Remote Mouse website: features and platforms", "https://www.remotemouse.net/"],
      ["Remote Mouse on the App Store: prices and requirements", "https://apps.apple.com/us/app/remote-mouse/id385894596"],
    ],
    related: ["/use/iphone-as-mac-trackpad", "/compare/mobile-mouse", "/compare/universal-control"],
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

  "/use/iphone-presentation-remote-mac": {
    kind: "feature",
    h1: "Use your iPhone as a presentation remote for your Mac",
    sub: "Next and Back under your thumb, a laser on the slides, and a talk timer.",
    visual: "presenter",
    visualLabel: "Slides on a big screen and the Presenter layout on an iPhone in hand: Next moves the slide on, and a finger on the pad steers a red laser dot across the slide",
    answer: "Glasspad's Present mode turns your iPhone into a clicker for your Mac. Its large Next and Back buttons press the right and left arrow keys, so it works with PowerPoint, Keynote, Google Slides and any slideshow that moves on with the arrow keys. Touch and hold the pad to point with a red laser dot on the display the slides are on, and let the timer count up, or down from a talk length with a tap you feel at 5 and 1 minute left. It does not show your slides or speaker notes on the iPhone. Glasspad is free and open source.",
    shot: "present",
    caption: "Present in the app: the timer, the laser pad, Back and Next.",
    guide: ["/guide#present", "Present in the guide"],
    early: [
      { kind: "text", title: "Is there a built-in way?", text: "Only for Keynote. Apple's Keynote Remote lets an iPhone run a Keynote slideshow on a Mac, with Keynote installed on both. For PowerPoint, Google Slides or a PDF, you need a clicker or an app. Glasspad works with all of them, because it presses the same arrow keys a clicker does.", note: "Apple: <a href=\"https://support.apple.com/guide/keynote-iphone/use-a-remote-tan9e9970a4/ios\">Use a remote to control a Keynote presentation</a>." },
    ],
    tiles: [
      { icon: "play", title: "Any slides app", text: "Next and Back press the arrow keys: PowerPoint, Keynote, Google Slides and more." },
      { icon: "hand", title: "A laser you steer", text: "Touch and hold the pad, and a red dot follows your finger on the slides." },
      { icon: "haptic", title: "A timer that taps you", text: "Count up, or down from 10 to 60 minutes, with a tap at 5 and 1 minute left." },
      { icon: "lock", title: "From the Lock Screen", text: "Back, Next and the running timer on the Lock Screen." },
    ],
    steps: [
      { icon: "menu", title: "Open Present", text: "Tap the mode button at the top of the screen, then Present." },
      { icon: "play", title: "Start the slideshow", text: "Play it on the Mac as usual, then tap Next and Back on the iPhone." },
      { icon: "layout", title: "Keep a trackpad close", text: "The Presenter layout puts Present over a trackpad, for a demo between slides." },
    ],
    more: [
      {
        kind: "table", title: "Glasspad or Keynote Remote", caption: "Glasspad's Present and Apple's Keynote Remote, side by side",
        cols: ["Glasspad Present", "Keynote Remote"],
        rows: [
          { k: "Slides apps", us: ["yes", "Any app that moves on with the arrow keys: PowerPoint, Keynote, Google Slides, PDFs"], them: ["part", "Keynote only"] },
          { k: "On the iPhone", us: ["part", "Next, Back, the laser pad and the timer. No slides or notes"], them: ["yes", "The current or next slide, or your presenter notes"] },
          { k: "Laser", us: ["yes", "A red dot on the display the slides are on"], them: ["yes", "A laser pointer, and drawing on the slide"] },
          { k: "Timer", us: ["yes", "Counts up or down, with a tap at 5 and 1 minute left"], them: ["yes", "A clock or a timer"] },
          { k: "Needs", us: ["", "Glasspad on the iPhone and the Mac, on the same Wi-Fi"], them: ["", "Keynote on both, with Wi-Fi on"] },
          { k: "Also", us: ["yes", "A trackpad, keyboard and media remote in the same app"], them: ["", "Remote control of Keynote"] },
        ],
        note: "Presenting in Keynote and want your notes in your hand? Keynote Remote is the better fit.",
      },
    ],
    faq: [
      ["Can I use my iPhone as a PowerPoint clicker on a Mac?", "Yes. Open Present in Glasspad and start the slideshow in PowerPoint. Next and Back press the right and left arrow keys, which PowerPoint uses to move between slides."],
      ["Does it work with Google Slides?", "Yes. Start the slideshow in the browser and keep it as the window in front. Next and Back press the arrow keys, which Google Slides follows."],
      ["Can I see my speaker notes on the iPhone?", "No. Present shows Next, Back, the laser pad and the timer. Use presenter view on the Mac, or Keynote Remote if you present in Keynote."],
      ["Keynote Remote is not connecting. What can I try?", "Apple's steps: turn on Wi-Fi on both devices, allow Keynote under Local Network in the iPhone's Settings, then in Keynote on the Mac open Settings, click Remote, select Enable and click Link next to your iPhone. If it still will not connect, Glasspad's Present works with Keynote too."],
      ["Does the laser show on the projector?", "Yes. The dot is drawn on the display the slides are playing on. With presenter view on your Mac's own screen and the slides on a projector, it goes to the projector."],
      ["Will my iPhone's screen turn off during the talk?", "No. In Present the screen stays on, until the iPhone is left alone for 30 minutes."],
      ["Does it work on conference or hotel Wi-Fi?", "The iPhone and the Mac need to reach each other on the same Wi-Fi. Some networks keep devices apart; then Glasspad tries a direct Wi-Fi link between the iPhone and the Mac for a minute. Try it in the room before you speak."],
    ],
    related: ["/use/iphone-remote-for-mac", "/use/iphone-as-mac-trackpad", "/use/control-mac-from-iphone"],
    sources: [
      ["Apple: Use a remote to control a Keynote presentation (iPhone)", "https://support.apple.com/guide/keynote-iphone/use-a-remote-tan9e9970a4/ios"],
    ],
  },

  "/use/control-mac-from-iphone": {
    kind: "feature",
    h1: "How to control your Mac from your iPhone",
    sub: "Every way, and which one fits what you want to do.",
    visual: "desk",
    visualLabel: "A Mac desk with a display, a MacBook and an iPhone on a stand: tapping Split Screen on the iPhone puts Safari and Xcode side by side",
    answer: "It depends on what you want. To see your Mac's screen on the iPhone and use it, even away from home, turn on Screen Sharing on the Mac and connect with a screen sharing (VNC) or remote desktop app. To drive the Mac without a screen of its own, Apple's Switch Control can, but it is built for people who use switches and is slow for everyday use. To use the iPhone as a trackpad, keyboard and remote while you look at the Mac, use an app made for that. Glasspad is a free, open source one; it works on the same Wi-Fi and does not show the Mac's screen.",
    shot: "menu",
    caption: "Glasspad's mode menu: the ways your iPhone can control your Mac.",
    guide: ["/guide#modes", "Every mode in the guide"],
    early: [
      {
        kind: "cards", title: "Every way, by what you need",
        cards: [
          { title: "See the screen: Screen Sharing or remote desktop", points: ["Shows the Mac's screen on the iPhone, so you can work on it from another room or away from home.", "Screen Sharing is built into macOS; you add a VNC or remote desktop app on the iPhone.", "Small on a phone screen, and you tap on a picture of the Mac."] },
          { title: "Built in: Switch Control", points: ["Apple's accessibility feature can move from the iPhone to a Mac on the same Wi-Fi and Apple Account.", "Made for people who use switches. You step through items, so it is slow for everyday use."] },
          { title: "Use it as a trackpad and remote: Glasspad", us: true, points: ["A trackpad with your Mac's own gestures, a keyboard, a remote, buttons for the app in front, and window control.", "Free and open source. Works on the same Wi-Fi, and does not show the Mac's screen."] },
          { title: "What does not do this", points: ["Universal Control works between Macs and iPads, not iPhones.", "iPhone Mirroring goes the other way: your Mac controls your iPhone."] },
        ],
      },
    ],
    tiles: [
      { icon: "trackpad", title: "Trackpad", text: "Your Mac's gestures, with a tap you can feel on every click." },
      { icon: "keyboard", title: "Keyboard", text: "Type or dictate, with modifier keys, shortcuts and F1 to F12." },
      { icon: "remote", title: "Remote", text: "Play, pause, skip and volume, for Netflix, YouTube and Spotify." },
      { icon: "actions", title: "Buttons and windows", text: "Buttons for the app in front, split screen and every display." },
    ],
    steps: [
      { icon: "code", title: "Install it", text: "One command in Terminal on the Mac builds and installs both apps." },
      { icon: "wifi", title: "Pair once", text: "Scan the QR code on the Mac and click Allow. Everything after that is encrypted." },
      { icon: "menu", title: "Pick a mode", text: "Trackpad, Keyboard, Remote, Actions and more, from the mode menu." },
    ],
    more: [
      { kind: "text", title: "To see your Mac's screen: Screen Sharing", text: "On the Mac, open System Settings, then General, then Sharing, and turn on Screen Sharing. Its settings can let VNC viewers control the screen with a password, so a VNC app on the iPhone can connect over your network. To reach the Mac from outside your home, use a remote desktop service that works over the internet, such as Chrome Remote Desktop.", note: "Apple: <a href=\"https://support.apple.com/guide/mac-help/turn-screen-sharing-on-or-off-mh11848/mac\">Turn screen sharing on or off</a>. Google: <a href=\"https://support.google.com/chrome/answer/1649523\">Access another computer with Chrome Remote Desktop</a>." },
      { kind: "text", title: "Built in, for accessibility: Switch Control", text: "On the Mac, turn on Switch Control and allow platform switching to control your computer. On the iPhone, open the Switch Control menu, choose Device, then Use Other Device, and pick the Mac. Both need the same Wi-Fi and the same Apple Account. To stop, hold the switch for ten seconds or choose Disconnect.", note: "Apple: <a href=\"https://support.apple.com/118667\">Use Switch Control on your device to control another Apple device</a>." },
    ],
    faq: [
      ["Can I control my Mac from my iPhone without an app?", "Only with Switch Control, Apple's accessibility feature, which is slow for everyday use. Screen Sharing is built into the Mac, but the iPhone needs a VNC or remote desktop app to connect to it."],
      ["Can I control my Mac from my iPhone when I am away from home?", "Not with Glasspad: it works only when the iPhone and the Mac are on the same Wi-Fi. Use a remote desktop app that works over the internet."],
      ["Does Glasspad show my Mac's screen on the iPhone?", "No. You look at the Mac, and the iPhone is the trackpad, keyboard or remote. It sends touches and key presses, not video."],
      ["How do I control a Mac mini from my iPhone?", "Install Glasspad on the Mac mini, then use the iPhone as its trackpad and keyboard. The first install needs a few clicks on the Mac (Xcode, your Apple ID, Accessibility), so keep a mouse and keyboard nearby for that."],
      ["Does it work with Universal Control?", "Universal Control does not work with iPhone. <a href=\"/compare/universal-control\">Glasspad vs Universal Control</a> explains what it does and does not do."],
      ["Is Glasspad free?", "Yes, all of it. There are no ads, accounts, subscriptions or in-app purchases, and the code is on GitHub under the MIT License."],
    ],
    related: ["/use/iphone-as-mac-trackpad", "/use/iphone-remote-for-mac", "/compare/universal-control"],
    sources: [
      ["Apple: Turn screen sharing on or off on Mac", "https://support.apple.com/guide/mac-help/turn-screen-sharing-on-or-off-mh11848/mac"],
      ["Apple: Use Switch Control on your device to control another Apple device", "https://support.apple.com/118667"],
      ["Apple: Universal Control requirements", "https://support.apple.com/102459"],
      ["Apple: iPhone Mirroring requirements", "https://support.apple.com/120421"],
      ["Google: Access another computer with Chrome Remote Desktop", "https://support.google.com/chrome/answer/1649523"],
    ],
  },

  "/use/iphone-to-mac-clipboard": {
    kind: "feature",
    h1: "Copy text and images from your iPhone to your Mac",
    sub: "When Universal Clipboard will not paste, send it with one tap.",
    visual: "clipboard",
    visualLabel: "Clipboard on an iPhone beside a Mac: Paste under Send to Mac puts what the iPhone copied on the Mac's clipboard",
    answer: "Apple's Universal Clipboard copies between iPhone and Mac when both share an Apple Account with Wi-Fi, Bluetooth and Handoff on. When it will not paste, Glasspad's Clipboard sends text, links and images on a tap, both ways, over your Wi-Fi. It is free and open source.",
    shot: "keyboard",
    caption: "Clipboard sits at the end of Keyboard's shortcut row.",
    guide: ["/guide#clipboard", "Clipboard in the guide"],
    early: [
      {
        kind: "cards", title: "First, try these fixes",
        cards: [
          { title: "Check on both devices", points: ["Signed in to the same Apple Account.", "Wi-Fi and Bluetooth turned on.", "Handoff turned on. It is on unless someone turned it off."] },
          { title: "Then", points: ["Keep the iPhone near the Mac.", "Paste soon: what you copy stays on the other device only briefly, or until you copy something else."] },
        ],
        note: "Apple: <a href=\"https://support.apple.com/102430\">Use Universal Clipboard to copy and paste between your Apple devices</a>.",
      },
    ],
    tiles: [
      { icon: "clipboard", title: "Both ways", text: "Send to Mac, and Get from Mac, each on one tap." },
      { icon: "globe", title: "Text, links and images", text: "A paragraph, a link or a photo you copied." },
      { icon: "wifi", title: "Just your Wi-Fi", text: "No Apple Account sign-in, Bluetooth or Handoff. Paired by QR code and encrypted." },
      { icon: "check", title: "Says when it worked", text: "The iPhone says Sent only once the Mac has taken it." },
    ],
    steps: [
      { icon: "copy", title: "Copy on the iPhone", text: "Text, a link or an image, from any app." },
      { icon: "keyboard", title: "Open Clipboard", text: "At the end of Keyboard's shortcut row, or pin it from the Library." },
      { icon: "command", title: "Paste on the Mac", text: "Tap Paste under Send to Mac, then press Command-V on the Mac." },
    ],
    faq: [
      ["Why is copy from iPhone to Mac not working?", "Universal Clipboard needs the same Apple Account on both devices, Wi-Fi, Bluetooth and Handoff on, and the devices near each other. What you copy stays available only briefly. If all of that is right and it still fails, send it with Glasspad's Clipboard instead."],
      ["Does Glasspad replace Universal Clipboard?", "No. Universal Clipboard is automatic; Glasspad's Clipboard is a tap to send or get. Use it when the automatic way does not work, or when the devices are on different Apple Accounts."],
      ["Can I send a photo from my iPhone to my Mac this way?", "Yes. Copy the image on the iPhone, then tap Paste under Send to Mac. Images up to 11 MB go at once. For many photos or full-size files, AirDrop is the better tool."],
      ["Can I get what my Mac copied onto my iPhone?", "Yes. Tap Get from Mac. Large images from the Mac are scaled down to fit, so they arrive quickly."],
      ["Get from Mac says my Mac does not allow it. What do I do?", "macOS can stop apps from reading the clipboard. Allow Glasspad in System Settings, under Privacy &amp; Security."],
    ],
    related: ["/use/iphone-as-mac-keyboard", "/use/control-mac-from-iphone", "/use/stream-deck-alternative-mac"],
    sources: [
      ["Apple: Use Universal Clipboard to copy and paste between your Apple devices", "https://support.apple.com/102430"],
    ],
  },

  "/compare/coast": {
    kind: "compare",
    them: "Coast",
    h1: "Glasspad vs Coast",
    sub: "Two new ways to control your Mac from your iPhone, side by side.",
    answer: "Coast, from LeShan Chen, turns an iPhone, iPad or Apple Watch into decks of controls, a trackpad and a keyboard for a Mac, free with a $2.99 Pro upgrade. Glasspad is free with nothing to buy, open source, and for iPhone and Mac only, with buttons for 70+ apps and a remote for Netflix and YouTube.",
    shot: "actions",
    caption: "Glasspad's Actions: buttons for the app in front.",
    rows: [
      { k: "Phone", us: ["part", "iPhone (iOS 18 or later)"], them: ["yes", "iPhone and iPad (iOS 17 or later), and Apple Watch with Pro"] },
      { k: "Computer", us: ["part", "Mac (macOS 14 or later)"], them: ["part", "Mac, with its free menu bar app"] },
      { k: "Price", us: ["yes", "Free. No ads or in-app purchases"], them: ["part", "Free. Coast Pro $2.99 once, for macros, screen mirror, air mouse, drawing, Apple Watch, iCloud sync and more grids"] },
      { k: "Install", us: ["part", "One-line installer that builds the app with Xcode and a free Apple ID; the Mac renews it every 7 days"], them: ["yes", "App Store, plus the Mac app from its website"] },
      { k: "Connection", us: ["part", "Same Wi-Fi, paired by QR code, encrypted"], them: ["part", "Same Wi-Fi, paired by a six-digit code, encrypted"] },
      { k: "Trackpad", us: ["yes", "Your Mac's own gestures: Spaces, Mission Control, pinch, force click, with haptics"], them: ["yes", "Mac gestures, press to click, and an optical mouse with the camera"] },
      { k: "Buttons", us: ["yes", "Ready-made buttons for 70+ apps that follow the app in front, plus your own"], them: ["yes", "Decks you design from about 40 controls, in grids up to 8 by 12, that can switch with the app in front"] },
      { k: "Also", us: ["yes", "Media, Remote for 11 players, Present with a laser, Dock, macros, Clipboard, Displays, Layouts, StandBy"], them: ["yes", "Clipboard, a talk timer and Home Screen widgets; now playing, screen mirror and a laser with Pro"] },
      { k: "Source code", us: ["yes", "Open source, MIT"], them: ["no", "Not open source"] },
    ],
    fitThem: [
      "You want an iPad or Apple Watch too.",
      "You want to see the Mac's screen on the phone, or an air mouse, and $2.99 is fine.",
      "You want to design your own controls, with sliders, dials and jog wheels.",
    ],
    fitUs: [
      "You want every feature free, macros and now playing included, and code you can read.",
      "You want buttons that are ready for 70+ apps without building decks.",
      "You want a couch remote for Netflix and YouTube, and window and display control.",
    ],
    faq: [
      ["Is Coast free?", "The app and its Mac app are free. Coast Pro, $2.99 once on the US App Store, adds macros, screen mirroring, the air mouse, drawing and a laser, the Apple Watch app, iCloud sync and more grids."],
      ["Is there a free and open source alternative to Coast?", "Yes. Glasspad is free with nothing to buy, and its code is public under the MIT license. It works only with an iPhone and a Mac, and installs with a Terminal command instead of the App Store."],
      ["Can Glasspad show my Mac's screen on the iPhone?", "No. Glasspad has no screen mirroring. Its Displays mode shows a map of your displays and windows to move and tile them. For the screen itself, Coast Pro or a screen sharing app fits better."],
      ["Does Glasspad work on iPad or Apple Watch?", "There is no Watch or iPad app. Glasspad's Lock Screen controls also show on Apple Watch. For an iPad, Coast is a good choice."],
    ],
    sources: [
      ["Coast on the App Store: price, Coast Pro, requirements and devices", "https://apps.apple.com/us/app/id6790821600"],
      ["Coast features: every feature, with Pro marked", "https://coast.masn.studio/features"],
      ["Coast privacy policy: pairing, camera and iCloud sync", "https://coast.masn.studio/privacy"],
    ],
    checked: "October 17, 2026",
    related: ["/compare/stream-deck-mobile", "/use/stream-deck-alternative-mac", "/use/iphone-as-mac-trackpad"],
  },
  "/compare/mobile-mouse": {
    kind: "compare",
    them: "Mobile Mouse",
    h1: "Glasspad vs Mobile Mouse",
    sub: "Two ways to use your iPhone as a mouse and remote for your Mac.",
    answer: "Mobile Mouse, from R.P.A. Tech, turns an iPhone, iPad or Apple Watch into a trackpad, air mouse, keyboard and remote for a Mac or PC, for $9.99. Glasspad is free with nothing to buy, open source, and for iPhone and Mac only, with haptics on every click and buttons for the app in front.",
    shot: "trackpad",
    caption: "Glasspad's Trackpad, held sideways.",
    rows: [
      { k: "Phone", us: ["part", "iPhone (iOS 18 or later)"], them: ["yes", "iPhone and iPad (iOS 17 or later), and Apple Watch"] },
      { k: "Computer", us: ["part", "Mac (macOS 14 or later)"], them: ["yes", "Mac (macOS 10.14 or later) and Windows 10 or later"] },
      { k: "Price", us: ["yes", "Free. No ads or in-app purchases"], them: ["part", "$9.99. Advanced Communications $0.99 and Pro Presentation Mode $1.99 in the app"] },
      { k: "Install", us: ["part", "One-line installer that builds the app with Xcode and a free Apple ID; the Mac renews it every 7 days"], them: ["yes", "App Store, plus the free Mobile Mouse Server on the computer"] },
      { k: "Connection", us: ["part", "Same Wi-Fi, paired by QR code, encrypted"], them: ["yes", "Wi-Fi with the server app; Bluetooth and USB versions without it"] },
      { k: "Trackpad", us: ["yes", "Your Mac's own gestures: Spaces, Mission Control, pinch, rotate, force click, with haptics"], them: ["yes", "Trackpad with multi-touch gestures, and an air mouse you move by moving the phone"] },
      { k: "Also", us: ["yes", "Media, Remote, Present with a laser, Dock, buttons for 70+ apps, macros, Shortcuts, Clipboard, Displays, Layouts"], them: ["yes", "Media and presentation remotes, hotkeys, app launcher, numeric keypad, file browser, Apple Watch controls"] },
      { k: "Source code", us: ["yes", "Open source, MIT"], them: ["no", "Not open source"] },
    ],
    fitThem: [
      "You use Windows, an iPad or an Apple Watch.",
      "You want to install from the App Store in a minute.",
      "You want an air mouse, or a Bluetooth link without Wi-Fi.",
    ],
    fitUs: [
      "You have an iPhone and a Mac and want the Mac's own trackpad gestures, with haptics.",
      "You want everything free, with nothing to buy, and code you can read.",
      "You want buttons for the app in front, window tiling and display control too.",
    ],
    faq: [
      ["Is there a free alternative to Mobile Mouse for Mac?", "Yes. Glasspad is free and open source, with no ads or in-app purchases. It works only with an iPhone and a Mac, and installs with a Terminal command instead of the App Store."],
      ["How much does Mobile Mouse cost?", "On the US App Store it is $9.99, with two in-app purchases: Advanced Communications for $0.99 and Pro Presentation Mode for $1.99. The server app on the computer is free."],
      ["Does Glasspad work on Windows or Apple Watch?", "Glasspad is for a Mac only. There is no Watch or iPad app. Glasspad's Lock Screen controls also show on Apple Watch. For Windows, Mobile Mouse is a good choice."],
      ["Do I need to pay Apple to install Glasspad?", "No. A free Apple ID is enough. Apps installed that way stop opening after 7 days, and your Mac renews Glasspad over Wi-Fi before then."],
    ],
    sources: [
      ["Mobile Mouse on the App Store: price, in-app purchases and requirements", "https://apps.apple.com/us/app/mobile-mouse/id289616509"],
      ["Mobile Mouse website: features, platforms and connections", "https://mobilemouse.com/"],
    ],
    checked: "October 17, 2026",
    related: ["/compare/remote-mouse", "/use/iphone-as-mac-trackpad", "/use/iphone-presentation-remote-mac"],
  },
};
