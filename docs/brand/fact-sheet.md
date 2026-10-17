# Glasspad fact sheet

**Glasspad turns your iPhone into a trackpad, keyboard, remote and button deck for your Mac.** Free and open source.

| | |
| --- | --- |
| What it is | An iPhone app plus a small Mac menu bar app. They talk over your Wi-Fi. |
| Price | Free. No ads, no in-app purchases, no account. |
| License | MIT (open source) |
| Current version | 0.3.0, released 2026-10-17 |
| First release | 0.1.0, 2026-10-16 |
| Needs | A Mac on macOS 14 or later, an iPhone on iOS 18 or later, Xcode 26 (free) and a free Apple ID |
| How to get it | Not on the App Store. One Terminal command builds and installs both apps: glasspad.sohamaggarwal.com/install |
| Built with | Swift 6 and SwiftUI |
| Privacy | Paired by QR code, encrypted, no account, no tracking. Nothing leaves your Wi-Fi, except Website buttons fetching a site's name and logo. |
| Developer | Soham Aggarwal, sohamaggarwal.com |
| Website | glasspad.sohamaggarwal.com |
| Source code | github.com/Soham109/glasspad |
| Press contact | hello@sohamaggarwal.com |

## What it does

- **Trackpad:** move, click, scroll, pinch, swipe between Spaces, with a tap you can feel.
- **Keyboard:** type or dictate; modifier keys, shortcuts, arrows, F1 to F12.
- **Remote and Media:** a Siri Remote style pad for Netflix, YouTube, Apple TV and Spotify on the Mac.
- **Actions:** buttons that follow the app in front, for more than 70 apps. A free Stream Deck alternative.
- **Present:** Next and Back, a talk timer, a laser pointer.
- **Displays and Split Screen:** move and tile windows across displays from the phone.
- **Themes:** 39 themes.

## In this kit

| Folder | What |
| --- | --- |
| `icon/` | App icon: Mac (transparent, rounded) and iOS (square, light and dark), PNG 1024 to 64, iOS as SVG |
| `wordmark/` | Icon plus name, and name alone, for light and dark backgrounds (transparent PNG) |
| `screenshots/` | 7 iPhone screens (1206x2622) and 1 Mac menu bar view |
| `colors.json` | Brand colors from the app and site code |
| `brand-guide.md` | Short brand guide: how to use the icon and name (`docs/brand/README.md` in the repo) |

About the screenshots: real captures of the iPhone app in the iOS Simulator, with the app's built-in sample Mac data (no Mac was connected). The Mac view is drawn by the Mac app's own snapshot tests with sample data.
