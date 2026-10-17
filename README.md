<h1 align="center">Glasspad</h1>

<p align="center"><b>Use your iPhone as a trackpad, keyboard, remote and button deck for your Mac. Free and open source.</b></p>

<p align="center">
  <a href="https://glasspad.sohamaggarwal.com">Website</a> &middot;
  <a href="https://glasspad.sohamaggarwal.com/install">Install</a> &middot;
  <a href="https://glasspad.sohamaggarwal.com/guide">Guide</a> &middot;
  <a href="https://www.youtube.com/watch?v=6AArTWOADGc">Film</a>
</p>

<p align="center">
  <a href="https://github.com/Soham109/glasspad/releases/latest"><img alt="Latest release" src="https://img.shields.io/github/v/release/Soham109/glasspad?color=blue"></a>
  <a href="LICENSE"><img alt="MIT license" src="https://img.shields.io/badge/license-MIT-blue.svg"></a>
  <img alt="macOS 14 or later" src="https://img.shields.io/badge/macOS-14%2B-lightgrey">
  <img alt="iOS 18 or later" src="https://img.shields.io/badge/iOS-18%2B-lightgrey">
  <img alt="Swift" src="https://img.shields.io/badge/Swift-SwiftUI-orange">
</p>

<p align="center">
  <img src="docs/img/hero.png" alt="Glasspad on three iPhones: the Remote mode controlling a Netflix film in Safari on a Mac, the Actions button deck with buttons for Safari, and the Media mode playing a song in Spotify" width="820">
</p>

**Glasspad is a free, open source (MIT) app that turns your iPhone into a trackpad, keyboard, media remote and customizable button deck for your Mac.** A small menu bar app on the Mac and an app on the iPhone talk over your Wi-Fi, with no account and no cloud. It covers what a wireless trackpad, a Stream Deck and a Siri-style remote do, using the phone you already own.

**Who it is for:** Mac users who want to control their Mac from the couch or across the room, watch Netflix or YouTube on a Mac without getting up, present slides, or have a free touchscreen button deck next to the keyboard.

**Install** with one Terminal command (details in [Install](#install)):

```bash
curl -fsSL https://raw.githubusercontent.com/Soham109/glasspad/main/install.sh | bash
```

[Website](https://glasspad.sohamaggarwal.com) · [Install guide](https://glasspad.sohamaggarwal.com/install) · [Guide](https://glasspad.sohamaggarwal.com/guide) · [Releases](https://github.com/Soham109/glasspad/releases) · [Changelog](CHANGELOG.md)

## Features

| | |
| --- | --- |
| **Trackpad** | Move, click, scroll, pinch and swipe between Spaces or up for Mission Control, with a tap you can feel on every click. [More](https://glasspad.sohamaggarwal.com/use/iphone-as-mac-trackpad) |
| **Keyboard** | Type or dictate. Modifier keys, shortcuts, arrows and F1 to F12. [More](https://glasspad.sohamaggarwal.com/use/iphone-as-mac-keyboard) |
| **Media** | What is playing in Spotify, Music or a browser: artwork, scrubbing, sound output, volume and screen brightness. |
| **Dock** | Your Mac's Dock. Tap to open, hold to hide or quit, and hide the Mac's own Dock. |
| **Actions** | Buttons that follow the app in front, for more than 70 apps. A free Stream Deck alternative on your iPhone. [More](https://glasspad.sohamaggarwal.com/use/stream-deck-alternative-mac) |
| **Pinned** | Your own buttons: Do Not Disturb, Night Shift, Keep Awake, Split Screen and window tiling, screenshots, apps, and websites with their real logos. Folders keep them tidy; the Library finds anything. |
| **Macros** | Record steps on your Mac once, replay them with a tap. |
| **Shortcuts** | Run any shortcut from the Shortcuts app on your Mac. |
| **Remote** | A touch pad like the Siri Remote for Netflix, YouTube, Apple TV and Spotify on your Mac: tap to pause, swipe to skip 10 seconds, up or down for volume. The keys follow the player, and Search types on the Mac. [More](https://glasspad.sohamaggarwal.com/use/iphone-remote-for-mac) |
| **Present** | A presentation remote: Next and Back, a talk timer, and a laser you steer with one finger. |
| **Clipboard** | Text and images, both ways. |
| **Displays** | Every display and its windows. Move a window to another display or tile it, and set brightness, resolution and Night Shift. [More](https://glasspad.sohamaggarwal.com/use/control-mac-displays-from-iphone) |
| **Arrange** | Split Screen from the phone: Left and Right, Top and Bottom, Quarters or Full Screen. See which windows go where, then one tap. [More](https://glasspad.sohamaggarwal.com/use/mac-split-screen-from-iphone) |
| **Layouts** | Up to three modes on one screen. The divider rests on thirds and the middle; your layouts sit in the mode menu. |
| **Lock Screen** | Remote and Present controls on the iPhone Lock Screen while something plays or a talk runs. |
| **Siri** | "Open Glasspad Mode" and "Open Glasspad Layout" in Siri and the Shortcuts app, and Mission Control by voice. |
| **StandBy** | A clock beside Now Playing or your calendar while the iPhone charges, in dim red at night. |
| **Themes** | 39 themes in six groups: Classic, Glass, Color, Grain (a fine still grain, like paper or film), Tinted (one color for everything, app icons included, or any color you pick), and Photo, which blurs a picture of yours behind everything. |
| **Private** | Paired by QR code, encrypted, no account. Nothing leaves your Wi-Fi, except Website buttons fetching their site's name and logo. |

<p align="center">
  <img src="docs/img/modes.png" alt="Glasspad on four iPhones: the Mac's Dock, the Present slide remote with a timer, the shared Clipboard, and Displays with each screen's windows" width="820">
</p>

<p align="center">
  <img src="docs/img/layouts.png" alt="Glasspad on two iPhones held sideways: a layout with Media and Actions side by side, and StandBy with a clock beside Now Playing" width="820">
</p>

<p align="center">
  <img src="docs/img/themes.png" alt="Four Glasspad themes on iPhones: Actions in Glass, Media in Aurora, Actions in Ocean and Dock in Midnight" width="820">
</p>

## Requirements

- A Mac on macOS 14 or later
- An iPhone on iOS 18 or later
- Xcode 26 or later (free on the App Store), a cable for the first install, and a free Apple ID

## Install

Paste this into Terminal:

```bash
curl -fsSL https://raw.githubusercontent.com/Soham109/glasspad/main/install.sh | bash
```

It does what it can by itself and waits for you where Apple needs a click: Xcode, your Apple ID, Accessibility for the Mac app, and Developer Mode and trust on the iPhone. It is safe to run again. Prefer to read before you paste? The script is [install.sh](install.sh), and the [install page](https://glasspad.sohamaggarwal.com/install) shows each step. Then click Glasspad in the menu bar, choose **Pair Your iPhone…** and scan the code.

With a free Apple ID, apps you install yourself stop opening after 7 days. Your Mac renews Glasspad over Wi-Fi before then. Every step, and help when something goes wrong, is in the [guide](https://glasspad.sohamaggarwal.com/guide).

## How it compares

| | Glasspad | Stream Deck Mobile | Remote Mouse | Universal Control |
| --- | --- | --- | --- | --- |
| Price | Free, everything | 6 keys free, Pro is paid | Free with ads, Pro is paid | Free, part of macOS |
| Open source | Yes, MIT | No | No | No |
| Uses an iPhone | Yes | Yes | Yes | No (Macs and iPads) |
| Works with | Mac only | Mac and Windows | Mac, Windows and Linux | Mac and iPad |
| Trackpad with Mac gestures | Yes, with haptics | No | Touchpad | Shares the Mac's own |
| App-aware buttons | 70+ apps | Profiles | No | No |
| Install | One Terminal command, builds with Xcode | App Store | App Store | Built in |

Full side by side pages: [vs Stream Deck Mobile](https://glasspad.sohamaggarwal.com/compare/stream-deck-mobile) · [vs Remote Mouse](https://glasspad.sohamaggarwal.com/compare/remote-mouse) · [vs Universal Control](https://glasspad.sohamaggarwal.com/compare/universal-control)

## FAQ

**What is Glasspad?**
A free, open source control surface for your Mac that runs on your iPhone. It is a trackpad, keyboard, media remote, Dock, app-aware button deck, macro recorder, presentation clicker and TV-style remote in one app.

**Can I use my iPhone as a mouse or trackpad for my Mac?**
Yes. macOS has no built-in way to do it, so you need an app on both devices. Glasspad's Trackpad mode moves the pointer, clicks, scrolls and uses the Mac's own gestures for Spaces and Mission Control, with a haptic tap on each click.

**Can I type on my Mac from my iPhone?**
Yes. In Keyboard, what you type or dictate on the iPhone lands wherever the cursor is on the Mac, with command, option, control, shortcuts, arrows and F1 to F12.

**Is it free?**
Yes. There are no ads, accounts, subscriptions or in-app purchases. The code is under the [MIT license](LICENSE).

**Is it on the App Store?**
No. You install it yourself with the one-line installer, which builds the apps from source with Xcode and your own Apple ID. The [guide](https://glasspad.sohamaggarwal.com/guide) walks through each step.

**Is it private?**
Yes. Phone and Mac talk directly over your local network, paired by QR code, with every message encrypted. There is no account or server of ours. The one outside request is a Website button fetching its site's name and logo. Details are in [SECURITY.md](SECURITY.md).

**What is the 7-day limit?**
Apple lets a free Apple ID install apps on your own iPhone, but they stop opening after 7 days. Glasspad's Mac app renews the iPhone app over Wi-Fi before that happens. A paid Apple Developer account is not needed.

**How is it different from Universal Control?**
Universal Control, from Apple, shares a Mac's keyboard and mouse with an iPad or another Mac. It does not use an iPhone. Glasspad is for an iPhone and adds app-aware buttons, macros, media and display controls. It does not replace Universal Control.

**How is it different from Remote Mouse and similar apps?**
Remote Mouse and Unified Remote are also phone-as-remote apps. Glasspad is open source, free in full, uses the Mac's own trackpad settings and gestures, and has haptic feedback on clicks. Those apps support other systems, such as Windows and Linux. Glasspad works only with a Mac.

**Is it a Stream Deck alternative?**
For many uses, yes. Pinned buttons, per-app Actions, Shortcuts and Macros give you a touchscreen deck for launching apps, running shortcuts and system controls. A Stream Deck has physical keys you can press without looking, and a large plugin library. Glasspad has neither.

**Does it work with Windows, Android or iPad?**
No. Glasspad is an iPhone app and a Mac app. It needs both.

**Who makes it?**
Soham Aggarwal. It is open source on GitHub, so anyone can read the code, report a bug or send a change.

**What does it need?**
A Mac on macOS 14 or later, an iPhone on iOS 18 or later, and both on the same Wi-Fi. To install, you also need Xcode 26 or later, a cable for the first install and a free Apple ID.

## Learn more

- [Use your iPhone as a Mac trackpad](https://glasspad.sohamaggarwal.com/use/iphone-as-mac-trackpad)
- [Use your iPhone as a Mac keyboard](https://glasspad.sohamaggarwal.com/use/iphone-as-mac-keyboard)
- [iPhone remote for Netflix, YouTube and Spotify on a Mac](https://glasspad.sohamaggarwal.com/use/iphone-remote-for-mac)
- [A free Stream Deck alternative for Mac](https://glasspad.sohamaggarwal.com/use/stream-deck-alternative-mac)
- [Split screen on your Mac from your iPhone](https://glasspad.sohamaggarwal.com/use/mac-split-screen-from-iphone)
- [Control your Mac's displays and windows from iPhone](https://glasspad.sohamaggarwal.com/use/control-mac-displays-from-iphone)
- [Every mode, step by step, in the guide](https://glasspad.sohamaggarwal.com/guide)
- [The film on YouTube](https://www.youtube.com/watch?v=6AArTWOADGc)

## Security

- The pairing key lives in the Keychain on both devices.
- Every message is encrypted (ChaCha20-Poly1305) with a fresh key per connection, and replays are rejected.
- Remove a phone from the Mac menu to revoke it.

More in [SECURITY.md](SECURITY.md) and [ARCHITECTURE.md](ARCHITECTURE.md).

## Building by hand

```bash
git clone https://github.com/Soham109/glasspad.git
cd glasspad
xcodegen generate
open Glasspad.xcodeproj
```

Run the **Glasspad Mac** scheme, then **Glasspad iOS** on your iPhone with your Apple ID under Signing. Scripts for each piece are in `scripts/`. The website is in `web/`, and `web/scripts/readme-images.mjs` makes the pictures above.

## Contributing

Bug reports, ideas and pull requests are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md).

## Credits and license

Film music: "Uplifting Electronic Indie" by WinnieTheMoog, [CC BY 4.0](https://creativecommons.org/licenses/by/4.0). [MIT](LICENSE), copyright 2026 Soham Aggarwal.
