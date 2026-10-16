# Changelog

All notable changes are listed here. The format follows [Keep a Changelog](https://keepachangelog.com), and the project follows [semantic versioning](https://semver.org).

## [0.1.0] - 2026-10-16

The first release. Changed and Fixed compare it with the test builds made before it.

### Added

- **Trackpad:** move, click, force click, drag, scroll with momentum, pinch, rotate, smart zoom, and swipes for Spaces, Mission Control, Show Desktop and the rest of the Mac's trackpad gestures. It follows the Mac's own trackpad settings and pointer acceleration, draws in step with the Mac's display, carries motion smoothly over short Wi-Fi gaps, and reads touches at 120 Hz on ProMotion iPhones.
- **Haptics** for clicks, force clicks and drag lock. Pointer speed, scrolling and haptics can be tuned on the iPhone.
- **Keyboard:** type or dictate, modifier keys, shortcuts, arrows, F1 to F12 and key repeat, on any Mac keyboard layout.
- **Media:** what is playing in Spotify, Music or a browser, with artwork, scrubbing, shuffle, repeat, sound output, volume and display brightness.
- **Dock:** the Mac's Dock in its own order with running dots. Hold an app to quit, hide or show it in Finder. Hide the Mac's own Dock.
- **Actions:** buttons that follow the app in front, with starter buttons for 74 apps and an Everywhere set. Pinned buttons with folders, sizes and colors, and a Library that finds any app, Mac control, macro, shortcut or website. Website buttons show the site's own logo.
- **Mac controls:** Do Not Disturb, Night Shift, Keep Awake, Notification Center, Split Screen, Next Display and window tiling (Left, Right, Top and Bottom Half, Fill, Center), next to Lock Screen, Sleep, Dark Mode, volume, brightness, screenshots and screen recording.
- **Macros:** record steps on the Mac once and replay them with a tap, with sets for each app. **Shortcuts:** run any shortcut from the Mac's Shortcuts app.
- **Remote:** a touch pad like the Siri Remote (tap to pause, swipe to skip, up or down for volume). Its keys follow the player: YouTube, Netflix, Prime Video, Disney+, Apple TV, QuickTime Player, IINA, VLC, Infuse, Spotify and Music. Search types on the Mac; Subtitles, Full Screen, Skip Intro (Netflix), Mute, Sleep Display and Do Not Disturb are one tap away, and switches show their new state.
- **Present:** Next and Back, a timer, and a laser you steer with one finger.
- **Clipboard:** text and images, both ways.
- **Displays:** every display and its windows, drawn as System Settings draws them. Tap a window to bring it forward, drag it to move it, or hold it to tile, split, move to another display, enter full screen, minimize or close. Set brightness, resolution, Night Shift, the main display, mirroring and the arrangement. A new resolution or mirroring goes back after 15 seconds unless you keep it.
- **StandBy screens:** Clock (Digital, Analog and Minimal faces), Now Playing and Calendar, for a desk or a nightstand. Always black, moved a few points each minute against burn in, dim red at night, and on only while charging unless you choose otherwise.
- **Layouts:** up to three modes on one screen. The divider rests on thirds and the middle and folds a pane away when pulled to the edge. Desk, Type, Listen and Couch come ready; more are in the gallery, and your own sit in the mode menu.
- **Themes:** 28 themes in four groups: Classic, Glass, Color, and Photo, which blurs a picture of yours behind everything. Every theme is checked for readable contrast.
- **Mode menu:** one piece of glass that grows out of the pill, with Clipboard, Present, Remote and Displays as tools and a Layouts row.
- **Pairing:** a living pairing code on the Mac (soft dots that still read as a QR code, valid for 5 minutes), a viewfinder on the iPhone that locks onto it and gathers the dots into a check, and Copy Link and Share for a phone that cannot scan.
- **Setup:** first-run pages on the iPhone in Apple's style, a setup checklist and connection help. On the Mac, a first-run assistant whose permission steps tick themselves off.
- **Mac app:** a menu bar window laid out like the system's own, and Settings with General, iPhone, Trackpad, Macros, Advanced and About. For each gesture you can choose the trackpad gesture or a keyboard shortcut.
- Several Macs per iPhone, reconnecting by itself, and Wake-on-LAN for a sleeping Mac.
- Siri and Shortcuts actions, a Control Center control, a Lock Screen widget and a Live Activity.
- Encrypted, authenticated connection with a key only the paired devices hold. Phones can be forgotten on the Mac.
- Care for the iPhone: when it is warm, haptics and background traffic pause; in Low Power Mode extras slow down; the screen stays on only while you use it.
- One-line installer, and automatic renewal of the iPhone app for free Apple IDs.

### Changed

- The Apps mode is called Dock again and shows only the Mac's Dock. Search over every installed app moved to Actions > + > Apps.
- The Toggle Focus button, which did not work, is now Do Not Disturb. Saved buttons are moved over.
- Older Decks move into Pinned once, without losing anything. A new Deck starts with six essentials: Screenshot, Do Not Disturb, Split Screen, Lock Screen, Mute and Dark Mode.
- Starter buttons are version 2. Starters you never touched update; ones you edited or deleted stay as you left them.
- Dock icons are sharper (384 px) and arrive in smaller messages.
- Keep Screen On holds the screen only while a Mac is connected, and lets the phone lock after it is left alone.
- With no iPhone connected, the Mac checks its status and trackpad settings less often (every 5 seconds).
- The Mac's Settings no longer show diagnostic rows. Connection quality shows as signal bars in the menu bar window.
- In the layout editor, double tap the line for even sizes (the Even button is gone).
- The text in both apps uses US spelling.

### Fixed

- Actions no longer crashes on very wide screens.
- Lock Screen locks directly. Dark Mode switches without asking for Automation permission. Screen recording no longer stops right after it starts. A full screen screenshot saves one file per display. A shortcut that does not exist is named as missing.
- Remote sends keys only when they reach the player, with corrected keys for VLC, QuickTime Player, Music and Prime Video.
- Starter buttons: Things Complete, Lightroom Before and After, Sketch Frame, and the symbol for Final Cut Pro Snapping. Keys that no app maker documents are gone; Warp has Command Search.
- Buttons made by a newer Glasspad are kept when you save the Deck, shown as "Update Glasspad to use this", and never run.
- When one trackpad pane replaces another (switching layouts, for example), the iPhone keeps its Wi-Fi awake for the pointer instead of letting it doze.
- Key repeat stops when a touch is cancelled.
- A drag to reorder buttons that ends outside a drop target ends on the next tap.
- When now playing cannot work on a Mac, Glasspad now reads why and stops retrying.
- Website logos use less memory and are let go when the iPhone runs low.
- Setup text no longer cuts off sideways, and the Mac's menu bar window never clips.
