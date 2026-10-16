<h1 align="center">Glasspad</h1>

<p align="center"><b>A control surface for your Mac, on your iPhone.</b></p>

<p align="center">
  <a href="https://glasspad.sohamaggarwal.com">Website</a> &middot;
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
  <img src="docs/img/hero.png" alt="Three iPhones: Remote for a film on Netflix, Actions for Safari, and Media playing a song in Spotify" width="820">
</p>

**Glasspad is a free, open source (MIT) app that turns your iPhone into a trackpad, keyboard, media remote and customizable button deck for your Mac.** A small menu bar app on the Mac and an app on the iPhone talk over your Wi-Fi, with no account and no cloud. It covers what a wireless trackpad, a Stream Deck and a Siri-style remote do, using the phone you already own.

[Website](https://glasspad.sohamaggarwal.com) · [Guide](https://glasspad.sohamaggarwal.com/guide) · [Releases](https://github.com/Soham109/glasspad/releases) · [Changelog](CHANGELOG.md)

## Features

| | |
| --- | --- |
| **Trackpad** | Move, click, scroll, pinch and swipe between Spaces, with a tap you can feel on every click. |
| **Keyboard** | Type or dictate. Modifier keys, shortcuts, arrows and F1 to F12. |
| **Media** | What is playing in Spotify, Music or a browser: artwork, scrubbing, sound output, volume and screen brightness. |
| **Dock** | Your Mac's Dock. Tap to open, hold to hide or quit, and hide the Mac's own Dock. |
| **Actions** | Buttons that follow the app in front, for more than 70 apps. |
| **Pinned** | Your own buttons: Do Not Disturb, Night Shift, Keep Awake, Split Screen and window tiling, screenshots, apps, and websites with their real logos. Folders keep them tidy; the Library finds anything. |
| **Macros** | Record steps on your Mac once, replay them with a tap. |
| **Shortcuts** | Run any shortcut from the Shortcuts app on your Mac. |
| **Remote** | A touch pad like the Siri Remote: tap to pause, swipe to skip 10 seconds, up or down for volume. The keys follow the player, and Search types on the Mac. |
| **Present** | Next and Back, a timer, and a laser you steer with one finger. |
| **Clipboard** | Text and images, both ways. |
| **Displays** | Every display and its windows. Move a window to another display or tile it, and set brightness, resolution and Night Shift. |
| **Layouts** | Up to three modes on one screen. The divider rests on thirds and the middle; your layouts sit in the mode menu. |
| **StandBy** | A clock beside Now Playing or your calendar while the iPhone charges, in dim red at night. |
| **Themes** | 28 themes in four groups: Classic, Glass, Color, and Photo, which blurs a picture of yours behind everything. |
| **Private** | Paired by QR code, encrypted, no account. Nothing leaves your Wi-Fi, except Website buttons fetching their site's name and logo. |

<p align="center">
  <img src="docs/img/modes.png" alt="Four iPhones: the Mac's Dock, Present, Clipboard and Displays" width="820">
</p>

<p align="center">
  <img src="docs/img/layouts.png" alt="Two iPhones held sideways: the Media and Actions layout, and StandBy with a clock beside Now Playing" width="820">
</p>

<p align="center">
  <img src="docs/img/themes.png" alt="Four themes: Actions in Glass, Media in Aurora, Actions in Ocean and Dock in Midnight" width="820">
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

It does what it can by itself and waits for you where Apple needs a click: Xcode, your Apple ID, Accessibility for the Mac app, and Developer Mode and trust on the iPhone. It is safe to run again. Then click Glasspad in the menu bar, choose **Pair Your iPhone…** and scan the code.

With a free Apple ID, apps you install yourself stop opening after 7 days. Your Mac renews Glasspad over Wi-Fi before then. Every step, and help when something goes wrong, is in the [guide](https://glasspad.sohamaggarwal.com/guide).

## FAQ

**What is Glasspad?**
A free, open source control surface for your Mac that runs on your iPhone. It is a trackpad, keyboard, media remote, Dock, app-aware button deck, macro recorder, presentation clicker and TV-style remote in one app.

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

**What does it need?**
A Mac on macOS 14 or later, an iPhone on iOS 18 or later, and both on the same Wi-Fi. To install, you also need Xcode 26 or later, a cable for the first install and a free Apple ID.

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
