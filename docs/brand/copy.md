# Glasspad copy

The one place for Glasspad's words. Copy from here; do not rewrite from memory. Every fact below was checked in the code on 17 Oct 2026 (version 0.3.0). If a fact changes, change it here first, then everywhere in [Where the copy disagrees](#where-the-copy-disagrees).

## Names

| Use | Do not use |
| --- | --- |
| Glasspad | GlassPad, Glass Pad, glasspad (except in code and URLs) |
| the Glasspad Mac app, the menu bar app | the server, the daemon, the helper |
| the Glasspad iPhone app | the iOS client, the phone app |
| mode | screen, tab, page |
| the mode menu | the pill, the switcher |

**The 11 modes**, exactly as the app names them (`Apps/iOS/Sources/Modes/AppMode.swift`), in this order:

Trackpad, Keyboard, Media, Dock, Actions, Pinned, Macros, Clipboard, Present, Remote, Displays.

- Five show by default: Trackpad, Keyboard, Media, Dock, Actions. Actions holds Pinned, Macros, Clipboard and Present until Settings splits them out.
- Remote and Displays open from the mode menu until Settings adds them.
- Not modes (call them features): Layouts, StandBy (Clock, Now Playing, Calendar), Shortcuts, Siri, Lock Screen, Themes.
- Old names, never use: Apps (now Dock), Deck (now Pinned), Keys (now Keyboard).

## The definition

The site's `DEFINITION` (`web/site/content.ts`). Use it word for word as the first sentence anywhere Glasspad is introduced.

> Glasspad is a free, open source (MIT) app that turns an iPhone into a trackpad, keyboard, media remote and button deck for a Mac, over Wi-Fi, with no account.

## Taglines

| Length | Text | Chars |
| --- | --- | --- |
| 30 | `Your iPhone as a Mac trackpad` | 29 |
| 50 | `Your iPhone as a Mac trackpad, keyboard and remote` | 50 |
| 80 | `Free, open source: your iPhone as a trackpad, keyboard and remote for your Mac` | 78 |
| Home hero only | `A control surface for your Mac, on your iPhone.` | 47 |

The home hero line is part of the home page design; keep it there. Elsewhere use the 50, because "control surface" is jargon.

## Descriptions

**120** (store one-liners, social bios; 114 chars)
```
Free, open source app that turns your iPhone into a trackpad, keyboard, media remote and button deck for your Mac.
```

**160** (meta descriptions, link previews; 157 chars)
```
Glasspad is a free, open source app that turns your iPhone into a trackpad, keyboard, media remote and button deck for your Mac, over Wi-Fi, with no account.
```

**260** (Product Hunt, directories; 241 chars)
```
Glasspad turns your iPhone into a trackpad with haptics, a keyboard, a media remote and buttons that follow the app in front on your Mac. It talks over your Wi-Fi, paired by QR code and encrypted. No account, no cloud. Free and MIT licensed.
```

**500** (directory long fields; 485 chars)
```
Glasspad is a free, open source (MIT) iPhone app and Mac menu bar app. Your iPhone becomes a trackpad you can feel click, a keyboard, a media remote, a remote for Netflix and YouTube, your Mac's Dock, a slide clicker, and buttons that follow the app in front, for more than 70 apps. Show up to three modes at once, in 39 themes. It pairs once by QR code, encrypts every message, and needs no account. Not on the App Store: one Terminal command builds it with Xcode and a free Apple ID.
```

## Boilerplate

**50 words** (press, end of a post)
```
Glasspad is a free, open source (MIT) app that turns an iPhone into a trackpad, keyboard, media remote and button deck for a Mac. An iPhone app and a Mac menu bar app talk over Wi-Fi, paired once by QR code and encrypted, with no account. Made by Soham Aggarwal.
```

**150 words** (press kit, About sections)
```
Glasspad is a free, open source (MIT) app that turns an iPhone into a trackpad, keyboard, media remote and button deck for a Mac. It has two parts: an iPhone app and a Mac menu bar app, which talk over your Wi-Fi. They pair once with a QR code and encrypt every message. There is no account and no Glasspad server. It has 11 modes, among them a trackpad with a tap you can feel on every click, a couch remote for Netflix and YouTube, a slide clicker, and buttons that follow the app in front, for more than 70 apps. Layouts put up to three modes on one screen, and there are 39 themes. It is not on the App Store: one Terminal command builds it with Xcode and installs it with a free Apple ID, and the Mac renews it over Wi-Fi. It is made by Soham Aggarwal.
```

**About the developer** (press line)
```
Glasspad is built by Soham Aggarwal, a solo developer who publishes all of its code on GitHub. Contact: hello@sohamaggarwal.com · sohamaggarwal.com · github.com/Soham109
```

## Feature one-liners

One line each, same order as the site (`FEATURES` in `web/site/content.ts`).

| Name | One-liner |
| --- | --- |
| Trackpad | Move, click, scroll, pinch and swipe between Spaces, with a tap you can feel on every click. |
| Keyboard | Type or dictate, with modifier keys, shortcuts, arrows and F1 to F12, in any Mac keyboard layout. |
| Media | What is playing in Spotify, Music or a browser, with artwork, scrubbing, sound output, volume and brightness. |
| Dock | Your Mac's Dock: tap to open, hold to hide or quit. |
| Actions | Buttons that follow the app in front, for more than 70 apps. |
| Pinned | Your own buttons: apps, websites, shortcuts, window tiling and Mac controls, in folders. |
| Macros | Record steps on your Mac once, replay them with a tap. |
| Clipboard | Text and images, both ways. |
| Present | Next and Back, a timer, and a laser you steer with one finger. |
| Remote | A touch pad like the Siri Remote that follows 11 players, from Netflix to VLC. |
| Displays | Every display and its windows: move, tile, and set brightness, resolution and Night Shift. |
| Layouts | Up to three modes on one screen. |
| StandBy | A clock beside Now Playing or your calendar while the iPhone charges. |
| Shortcuts and Siri | Run any Mac shortcut, and open a mode or layout from Siri. |
| Lock Screen | Remote and Present keys on the iPhone Lock Screen. |
| Themes | 39 themes, from plain to glass to a photo of yours. |
| Private | Paired by QR code, encrypted, no account. |

Facts behind the numbers:
- 11 modes: `AppMode` cases minus the three StandBy screens.
- More than 70 apps: 75 profiles in `StarterDefinitions.swift`, one of them the "Everywhere" fallback.
- 11 players: `RemoteKeymap.swift` (YouTube, Netflix, Prime Video, Disney+, Apple TV, QuickTime Player, IINA, VLC, Infuse, Spotify, Music).
- 10 second skip: `seekStep` in `RemoteKeymap.swift`.
- 39 themes: `THEMES` in `web/src/themes.ts`.
- Up to 3 modes: `ScreenLayout.maxPanes`.
- iOS 18, macOS 14: `project.yml`. Xcode 26: the app uses iOS 26 APIs behind availability checks, which need the iOS 26 SDK.
- Encryption: ChaCha20-Poly1305, `SessionCrypto.swift`.

## The honest limits

Use this paragraph, or its bullets, anywhere someone could be surprised later.

> Glasspad is not on the App Store. One Terminal command builds it on your Mac with Xcode 26 or later and installs it on your iPhone with your free Apple ID. Apps installed with a free Apple ID stop opening after 7 days, so the Mac checks every hour and reinstalls Glasspad over Wi-Fi once the install is 5 days old. That needs the Mac on and the iPhone on the same Wi-Fi at some point; if it cannot renew, the Mac tells you. Glasspad works only with an iPhone on iOS 18 or later and a Mac on macOS 14 or later.

- Not on the App Store; installs with one Terminal command.
- Needs Xcode 26 or later (a large free download), a free Apple ID and a USB cable the first time.
- 7-day free signing; the Mac renews it by itself over Wi-Fi (`scripts/refresh-phone.sh`).
- iPhone and Mac only. No iPad, Android, Windows or Linux.
- Over Wi-Fi it can lag more than a Magic Trackpad on a weak network.
- No physical keys and no streaming plugins, unlike a Stream Deck.

## What leaves your Wi-Fi

Say: "Your iPhone and Mac talk only over your Wi-Fi. There is no account and no Glasspad server."

Do not say "nothing leaves your Wi-Fi". Three things do, as `web/privacy.html` lists: Website buttons fetch the site's name and logo, Media may download album artwork from the music service, and install and renewal use GitHub and Apple.

## FAQ short answers

| Question | Answer |
| --- | --- |
| What is Glasspad? | The definition, word for word. |
| Is it free? | Yes. Free and open source under MIT, with no ads, account or purchases. |
| Is it on the App Store? | No. One Terminal command builds it with Xcode and installs it with your free Apple ID. |
| Does it stop after 7 days? | Not while your Mac can reach it. The Mac renews it over Wi-Fi, and tells you if it can't. |
| Is it private? | Paired by QR code, encrypted, no account, no Glasspad server. |
| What do I need? | macOS 14+, iOS 18+, Xcode 26+, a free Apple ID, a USB cable once, and one Wi-Fi. |
| Windows, Android or iPad? | No. iPhone and Mac only. |
| Is it a Stream Deck alternative? | For on-screen buttons, yes. It has no physical keys and no streaming plugins. |
| Is it like Universal Control? | No. Universal Control does not work with iPhone. Glasspad works alongside it. |
| Who makes it? | Soham Aggarwal. The code is on GitHub. |

## Banned

| Do not write | Write instead |
| --- | --- |
| Em dashes and en dashes | A comma, a colon, or two sentences. Ranges in words: "F1 to F12". |
| seamless, effortless, powerful, magic, magical (Magic Trackpad is fine), revolutionary, game-changer, next-level, cutting-edge, best-in-class, world-class, ultimate, blazing fast, supercharge, unleash, unlock, elevate, empower, transform, streamline, robust, leverage | Say what it does: "a tap you can feel on every click" |
| "Say goodbye to...", "Look no further", "Whether you're X or Y", "It's not just X, it's Y", "In today's world", "Introducing...", "delve", "dive in", "take it to the next level" | Lead with the fact. |
| "Nothing leaves your Wi-Fi", "works offline", "no internet needed" | "Your iPhone and Mac talk only over your Wi-Fi." |
| "free forever", "always free" | "free and open source (MIT)" |
| "on the App Store", "download Glasspad" | "install with one Terminal command" |
| "Stream Deck replacement", "Universal Control for iPhone" | "a free Stream Deck alternative", "works alongside Universal Control" |
| "zero lag", "no latency", "instant" | "draws in step with your Mac's display" |
| "military-grade", "bank-level" encryption | "encrypted (ChaCha20-Poly1305)" |
| user counts, ratings, "loved by", testimonials, press logos | Nothing. There are none yet. |
| "control surface" outside the home hero | "trackpad, keyboard, media remote and button deck" |
| "customizable button deck", "Stream Deck style button deck" | "button deck" |

## Where the copy disagrees

Checked: README.md, the site (`web/site/content.ts`, `pages.ts`, `plugin.ts`, the HTML pages), GitHub About (`gh repo view`), CITATION.cff, llms.txt (built by `web/site/plugin.ts`), and ~/Desktop/Glasspad SEO Kit. The Reddit Kit holds only media. No em dashes or hype words were found in any of them.

| # | Where | Says | Problem | Fix |
| --- | --- | --- | --- | --- |
| 1 | `web/site/content.ts` FEATURES "Private"; home FAQ "Does anything leave my Wi-Fi?"; README features "Private" row | "Nothing leaves your Wi-Fi, except Website buttons..." | Leaves out album artwork, which `privacy.html` and `MediaMode.swift` show the Mac downloads | Add ", and Media fetching album artwork". FAQ answer: "No, except two things: Website buttons fetch their site's name and logo, and Media may fetch album artwork." |
| 2 | README FAQ "Is it private?" | "The one outside request is a Website button..." | Same: there are two | "The outside requests are Website buttons fetching their site's name and logo, and Media fetching album artwork." |
| 3 | SEO Kit `offsite/14-openalternative.md` | "nothing leaves your Wi-Fi" | Not true (see 1) | "your iPhone and Mac talk only over your Wi-Fi" |
| 4 | SEO Kit `offsite/13-macmenubar.md` | "Everything stays on your Wi-Fi" | Not true (see 1) | Same as 3 |
| 5 | GitHub About | "Stream Deck style button deck" | Differs from the definition | Use the 160 description. The user changes this in repo settings. |
| 6 | README bold line, CITATION.cff abstract | "customizable button deck" | Differs from the definition | "button deck" |
| 7 | README FAQ "What is Glasspad?" | "A free, open source control surface... macro recorder, presentation clicker and TV-style remote in one app." | Jargon, and a different list from the definition | The definition, then "It has 11 modes: Trackpad, Keyboard, Media, Dock, Actions, Pinned, Macros, Clipboard, Present, Remote and Displays." |
| 8 | Home meta description (`pages.ts`, path "/") | "...a control surface for your Mac: trackpad, keyboard, remote, Dock, app buttons and split screen." | Jargon; differs from the definition | The 160 description |
| 9 | llms.txt intro (`TAGLINE` in `plugin.ts`) | "A control surface for your Mac, on your iPhone." after the definition | Jargon, and repeats the definition | Drop it from llms.txt, or use the 50 tagline. Keep it on the home hero. |
| 10 | README features table | Lists Shortcuts, Arrange, Lock Screen and Siri as rows beside the modes; the site has "Siri and Shortcuts" and no Arrange or Lock Screen row | Reader cannot tell the 11 modes from the features | Put the 11 modes first, then a "Also" group: Layouts, Split Screen, StandBy, Shortcuts and Siri, Lock Screen, Themes, Private |
| 11 | README Present row | "a talk timer" | Site says "a timer" | "a timer" |
| 12 | `pages.ts` Stream Deck page description | "an iPhone XS or newer" | Leaves out iPhone XR, which also runs iOS 18 | "any iPhone on iOS 18" |
| 13 | SEO Kit `00-before-you-submit.md` | "One line, 120 characters" | It is 114 | Label it "under 120" |
| 14 | YouTube description, `FILM.description` | "wireless trackpad, keyboard and remote... no cloud" | Fine, but a different wording | Leave: it matches what is already live on YouTube |

These agree already: version 0.3.0, MIT, macOS 14 / iOS 18 / Xcode 26, more than 70 apps, 39 themes, 11 players, 7-day renewal, contact address.
