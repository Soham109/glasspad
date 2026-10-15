<h1 align="center">Glasspad</h1>

<p align="center"><b>Your iPhone, as a Mac trackpad</b></p>

<p align="center">
A wireless trackpad you can feel, plus a keyboard, a media remote, your Mac's apps and buttons that follow the app in front. Private, free and open source.
</p>

<p align="center">
  <img alt="license" src="https://img.shields.io/badge/license-MIT-blue.svg">
  <img alt="platform" src="https://img.shields.io/badge/macOS-14%2B-lightgrey">
  <img alt="platform" src="https://img.shields.io/badge/iOS-18%2B-lightgrey">
  <img alt="status" src="https://img.shields.io/badge/status-0.1.0%20unreleased-orange">
</p>

<p align="center">
  <img src="docs/brand/icon.png" alt="Glasspad icon" width="160">
</p>

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/img/hero-dark.png">
    <source media="(prefers-color-scheme: light)" srcset="docs/img/hero-light.png">
    <img src="docs/img/hero-light.png" alt="An iPhone held sideways as a trackpad next to a MacBook: two fingers moving up scroll the window on the Mac" width="820">
  </picture>
</p>

<p align="center"><a href="https://glasspad.sohamaggarwal.com">Website</a> · <a href="#install">Install</a> · <a href="#faq">FAQ</a> · <a href="#troubleshooting">Troubleshooting</a></p>

---

## What it is

Your iPhone becomes a wireless trackpad for your Mac, with a small tap you can feel on every click. Two apps on the same Wi-Fi: a menu bar app on the Mac and the Glasspad app on the phone.

- **Private.** No accounts, no servers, no tracking. Nothing leaves your network.
- **Free and open source.** MIT licensed. No subscription.
- **One command to install.** It builds the app on your Mac and keeps it on your iPhone for you.

## Trackpad

- Move, click, right click, drag, scroll with momentum, pinch, rotate, smart zoom.
- Swipe between pages and Spaces, Mission Control, App Exposé, Launchpad, Show Desktop.
- The pointer updates in step with your Mac's display, with the same speed-up curve as a real Mac trackpad.
- Taps never nudge the pointer. Only clicks buzz.
- Hold one finger still for half a second for a force click (a phone cannot sense pressure).
- Gestures follow your Mac's own trackpad settings. The phone adds its own pointer speed, acceleration, scroll speed, momentum and haptics for each kind of click.
- Upright or sideways. Three looks: Paper, Graphite, or System to match your iPhone.

## Modes

Tap the pill at the top of the phone to open the mode menu.

| Mode | What it does |
| --- | --- |
| **Trackpad** | The trackpad above. |
| **Keyboard** | Type and dictate on the phone. Command, Option, Control, Shift, common shortcuts, Esc, Tab and arrows. |
| **Media** | What is playing in Spotify or any other player: artwork, a bar you can scrub, instant play and pause, where the sound goes, volume, brightness. |
| **Apps** | Your Mac's Dock with full-size icons, dots for running apps, recent apps and search. Touch and hold for Quit, Hide or Keep. Can hide the Mac's own Dock. |
| **Actions** | The best buttons for the app in front on your Mac, switching as you switch apps. Below, your Pinned grid: tap + to add Mac controls, apps, macros, Shortcuts, or record a new macro. |

Two quick tools sit in the mode menu too: **Clipboard** (copy text or images between phone and Mac) and **Present** (next, previous, timer and a laser dot).

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/img/modes-dark.png">
    <source media="(prefers-color-scheme: light)" srcset="docs/img/modes-light.png">
    <img src="docs/img/modes-light.png" alt="The mode menu, Apps, Keyboard, Actions (front app and Pinned), editing Pinned, the Library, the Clipboard tool and Settings" width="820">
  </picture>
</p>
<p align="center"><sub>Simulator screenshots against a stand-in Mac.</sub></p>

## Install

You need a Mac on macOS 14 or newer with Xcode (free on the App Store), an iPhone on iOS 18 or newer, a cable for the first install, and a free Apple ID.

Paste this into Terminal:

```bash
curl -fsSL https://raw.githubusercontent.com/Soham109/glasspad/main/install.sh | bash
```

It walks you through each step. Whatever it can do alone, it does; whenever Apple needs you to click or tap, it tells you exactly where and waits until it sees you did it. Safe to run again: finished steps are skipped.

What it does, in order:

1. **Xcode.** Opens the App Store page if Xcode is missing, then accepts its license and one-time setup (asks for your Mac password).
2. **Build tools.** Downloads XcodeGen, the tool that creates the Xcode project.
3. **Source.** Downloads Glasspad into `~/Projects/glasspad` (or updates it).
4. **Your Apple account.** Asks you to sign in to Xcode with your Apple ID and pick your name as the team.
5. **Mac app.** Installs Glasspad in Applications and starts it in the menu bar. You switch on Accessibility for it, so it can move the pointer.
6. **iPhone.** Asks you to plug in and trust the Mac, and turn on Developer Mode. Then it builds and installs the app. The first time, you trust your Apple ID on the phone.
7. **Automatic renewal.** Sets your Mac to renew the iPhone app before the 7-day limit (see the FAQ).

Then pair: click the Glasspad icon in your Mac's menu bar, choose **Pair new iPhone**, and scan the code with the Glasspad app or the iPhone Camera.

## FAQ

**Why does a free Apple ID matter?** Apps you install yourself with a free Apple ID stop opening after 7 days. Glasspad handles this for you: your Mac checks every hour and, once the install is 5 days old, reinstalls the same version over Wi-Fi. You get a notification when it is done. Your Mac needs to be awake and your iPhone on the same Wi-Fi at some point in those two days. A paid developer account lasts a year instead.

**Can I turn automatic renewal off?** Yes: `~/Projects/glasspad/scripts/setup-autorefresh.sh --remove`. Its log is in `~/Library/Logs/Glasspad/refresh.log`.

**Why not the App Store?** Real gestures like Mission Control and Spaces swipes need parts of macOS the App Store does not allow. Each has a fallback that works without them.

**Over the internet?** No. Same Wi-Fi only.

**How fast is it?** Built for the shortest possible delay. Numbers will be published once measured on real devices.

**Can others on my Wi-Fi use it?** Not without the key from your QR code.

**More than one Mac or iPhone?** Pair several Macs and pick one from the mode menu. A Mac follows one iPhone at a time.

## Troubleshooting

**The pointer does not move after a reinstall or update.** macOS can quietly switch Accessibility off when the app is replaced. Open System Settings > Privacy & Security > Accessibility, switch Glasspad off and on again. If that does not help, remove it with the minus button and run the installer again.

**Media shows no song from Spotify.** The first time, macOS asks whether Glasspad may control Spotify. Click OK. If you clicked Don't Allow, open System Settings > Privacy & Security > Automation, find Glasspad and switch Spotify on.

**The iPhone app will not install or open.**
- *Developer Mode:* on the iPhone, Settings > Privacy & Security > Developer Mode (at the bottom) > On. The phone restarts; after unlocking, tap Turn On and enter your passcode.
- *Untrusted developer:* Settings > General > VPN & Device Management > your Apple ID > Trust.

**The iPhone app stopped opening after a week.** Renewal could not reach the phone in time. Bring the phone onto your Mac's Wi-Fi (or plug it in) and run `~/Projects/glasspad/scripts/refresh-phone.sh --now`.

## Security

- Pair by scanning a QR code. The key lives in the Keychain, Apple's encrypted store for secrets, on both devices.
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

Run the **Glasspad Mac** scheme, then **Glasspad iOS** on your iPhone with your Apple ID under Signing. Scripts for each piece live in `scripts/`.

## Roadmap

- [ ] First tagged release (0.1.0)
- [ ] Measured latency numbers on real hardware
- [ ] Signed and notarized Mac download
- [ ] Shareable macro files
- [ ] iPad support

## Contributing

Bug reports, ideas and pull requests are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md). To report a security problem, see [SECURITY.md](SECURITY.md).

## Credits

Demo film music: "Brand New World" by Kai Engel, [CC BY 4.0](https://creativecommons.org/licenses/by/4.0), from [Wikimedia Commons](https://commons.wikimedia.org/wiki/File:Kai_Engel_-_01_-_Brand_New_World.ogg). Details in [promo/MUSIC.md](promo/MUSIC.md).

## License

[MIT](LICENSE), copyright 2026 Soham Aggarwal.
