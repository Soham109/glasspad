<h1 align="center">Glasspad</h1>

<p align="center"><b>Your iPhone, as a Mac trackpad</b></p>

<p align="center">
A wireless trackpad with haptics, plus a dock, keyboard, media controls, shortcut deck, macros, clipboard and presenter remote. Private, free and open source.
</p>

<p align="center">
  <img alt="license" src="https://img.shields.io/badge/license-MIT-blue.svg">
  <img alt="platform" src="https://img.shields.io/badge/macOS-14%2B-lightgrey">
  <img alt="platform" src="https://img.shields.io/badge/iOS-17%2B-lightgrey">
  <img alt="status" src="https://img.shields.io/badge/status-0.1.0%20unreleased-orange">
</p>

<p align="center">
  <img src="docs/brand/icon.png" alt="Glasspad icon" width="160">
</p>

<!-- SCREENSHOT: docs/img/hero.png (phone showing the trackpad next to a Mac, 1640 px wide) -->
<p align="center">
  <img src="docs/img/hero.png" alt="Glasspad on an iPhone controlling a Mac" width="820">
</p>

<p align="center"><sub>One soft surface · a dot under each finger · nothing else until you ask</sub></p>

---

## What is Glasspad?

Glasspad turns your iPhone into a trackpad for your Mac over Wi-Fi. The phone screen is a plain surface with a soft dot under each finger. When you tap, press or swipe, your Mac reacts as if you used its own trackpad, and the phone gives you a small vibration (a haptic) so it feels like something clicked.

It is two small apps that talk to each other on your local network:

| Component | What it does |
| --- | --- |
| **Mac app** | Lives in the menu bar. Shows a QR code to pair, receives touches, and moves the pointer, clicks, scrolls and gestures. Reads your real trackpad settings. |
| **iPhone app** | The trackpad surface and the extra modes (Dock, Keys, Media, Deck, Macros, Clipboard, Present). Plays haptics. |
| **GlasspadKit** | A shared Swift package with the message format, encryption and gesture logic used by both apps. |

## Why Glasspad

- **Private.** Everything stays on your network. There are no accounts, no servers and no tracking.
- **Free.** No subscription and no in-app purchases.
- **No App Store.** You build it yourself, which is what lets the Mac side do things the App Store does not allow, such as native Mission Control and Spaces swipes.
- **Open source.** MIT licensed. Read it, change it, fork it.

## Features

**Trackpad**
- Move, tap to click, two finger right click, drag, two finger scroll with momentum, pinch to zoom, rotate, smart zoom.
- Swipe between pages and Spaces, Mission Control, App Exposé, Launchpad and Show Desktop, with the animation following your fingers.
- Press and hold for a force click. An iPhone cannot feel how hard you press, so a still hold of a moment stands in for it.

**Modes** (switch with the small pill at the top of the phone)

| Mode | What it does |
| --- | --- |
| **Dock** | Your Mac's Dock apps and running apps as a grid. Tap to open or switch. |
| **Keys** | Type on the phone and it appears on the Mac. Arrow keys, Esc, Tab and Command shortcuts in a row. Dictation works. |
| **Media** | Now playing title and artwork, play, pause, next, previous, volume and brightness. |
| **Deck** | A grid of your own buttons: open an app or URL, run an Apple Shortcut, send a keystroke, run a script. |
| **Macros** | Record a sequence of actions and replay it. Run Apple Shortcuts. Per-app profiles switch automatically when you change the front app on your Mac. |
| **Clipboard** | Send what is copied on your phone to the Mac, or pull the Mac's clipboard to the phone (text and images). |
| **Present** | Big next and previous buttons, a timer, and a laser dot you move on the Mac screen. |

<!-- SCREENSHOTS: docs/img/modes.png (the seven modes side by side), docs/img/menubar.png (Mac popover), docs/img/pairing.png (QR code on Mac) -->
<p align="center">
  <img src="docs/img/modes.png" alt="Glasspad modes" width="820">
</p>

## Gestures follow your Mac

Glasspad reads your trackpad settings from macOS while it runs, so you do not set anything up twice. Tracking speed, natural scrolling, tap to click, secondary click, three finger drag, Look Up, swipe between pages and Spaces, Mission Control, App Exposé, Launchpad, Show Desktop and click firmness all come from System Settings. Change one on the Mac and the phone follows.

One difference: a phone cannot be pressed down, so a tap always clicks, even if tap to click is off on your Mac. Glasspad shows this in its settings.

## Security

Glasspad can control your Mac, so it is locked down by default.

- **QR pairing.** The Mac shows a QR code that holds a random secret key. Your phone scans it with the camera and keeps the key in the iOS Keychain (Apple's encrypted storage for secrets). The Mac keeps its copy in its own Keychain. No key, no connection.
- **Encryption.** Every message after the first hello is encrypted and authenticated with ChaCha20-Poly1305 (a widely used encryption method). Each connection derives a fresh session key from the paired secret.
- **Replay protection.** Recorded packets cannot be played back later. The Mac rejects repeats.
- **Revoking.** Remove a phone in the Mac menu and its key stops working.

Details are in [SECURITY.md](SECURITY.md) and [ARCHITECTURE.md](ARCHITECTURE.md).

## Phone safety

Glasspad is careful with your phone. It uses only public iOS interfaces. The screen dims after a minute of no touch, it never forces full brightness, and if the phone gets warm it pauses haptics and background traffic and shows a calm notice. The screen is only kept awake while the trackpad is on screen.

## Install

Glasspad is built from source. You need a Mac with Xcode 16 or newer and an iPhone running iOS 17 or newer.

```bash
git clone https://github.com/Soham109/glasspad.git
cd glasspad
brew install xcodegen      # makes the Xcode project from project.yml
xcodegen generate
open Glasspad.xcodeproj
```

1. In Xcode, pick the **Glasspad Mac** scheme and run it. Allow Accessibility access when asked (macOS needs this before any app can move the pointer).
2. Plug in your iPhone, pick the **Glasspad iOS** scheme, choose your phone and run it. Sign in with your Apple ID under Signing and Capabilities.
3. Click the Glasspad icon in the Mac menu bar, choose Pair, and scan the QR code with the iPhone app.

**Free Apple ID note.** Apps signed with a free Apple ID stop opening after 7 days. Run it from Xcode again to refresh. A paid developer account lasts a year. Optionally, [AltStore](https://altstore.io) can re-sign the app for you automatically while your Mac is on.

Mac only, without Xcode: `scripts/build-mac.sh` builds `build/Glasspad.app`.

## FAQ

**Does it work over the internet?** No. The phone and Mac need to be on the same Wi-Fi network, or the phone can connect directly to the Mac.

**Is it as fast as a real trackpad?** It is built for low delay, but no numbers are published yet. Latency is measured, not guessed, and results will be added here once measured on real devices.

**Why is it not on the App Store?** The Mac app uses private macOS interfaces for real gesture support, which the App Store does not allow. Each one has a public fallback, and the app checks at launch which ones work.

**Does it work on iPad or Windows?** Not yet. iPhone to Mac only.

**Can someone else on my Wi-Fi control my Mac?** Not without the key from your QR code. Unpaired devices are ignored.

**Why does the Mac ask for Accessibility access?** Moving the pointer and sending clicks on behalf of another device requires it.

## Roadmap

- [ ] First tagged release (0.1.0)
- [ ] Measured latency numbers on real hardware
- [ ] Signed and notarized Mac download
- [ ] More Deck actions and shareable macro files
- [ ] iPad support
- [ ] Pointer gain and acceleration tuning presets

## Contributing

Bug reports, ideas and pull requests are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md). To report a security problem, see [SECURITY.md](SECURITY.md).

## License

[MIT](LICENSE), copyright 2026 Soham Aggarwal.
