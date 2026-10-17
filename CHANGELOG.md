# Changelog

All notable changes are listed here. The format follows [Keep a Changelog](https://keepachangelog.com), and the project follows [semantic versioning](https://semver.org).

## [Unreleased]

### Added

- **Activity log:** connections and media commands (which route each took and whether it worked) go to `~/Library/Logs/Glasspad/activity.log` on the Mac, capped at 256 KB, with no titles or typed text. Mac Settings > Advanced > Show Log opens it. The iPhone keeps the same log in the app's own storage.

### Fixed

- **Media and Remote:** the Mac's now-playing helper sends what plays as soon as it starts and refreshes every 5 seconds again. Before, it stayed silent until the player changed, so the phone could show an old state.
- **Media and Remote:** with the helper stopped, play or pause no longer goes to a paused Spotify or Music while a browser was the Mac's now playing app. It goes to the Mac's now playing instead.
- **Media and Remote:** on macOS 15.4 and later, the media key is used when the helper is not running, since macOS ignores Glasspad's own MediaRemote commands there.

## [0.2.1] - 2026-10-17

### Changed

- Tapping Next, Previous, or Play or Pause again while the iPhone reconnects now counts once, so a slide is not skipped and playback does not undo itself.

### Removed

- The iPhone's own low-battery notice at 20% and 10%. iOS already shows its Low Battery alert at those levels. The Mac still shows the iPhone's battery level.

## [0.2.0] - 2026-10-16

### Added

- **Themes:** 39 in all, including Grain (Grain, Grain Dark, Risograph, Film) and Tinted themes where everything takes one color.
- **Present:** a laser pointer on the slides' display, a talk timer that taps you at 5 minutes and at 1 minute left, and a screen that stays on during a talk (until the iPhone is left alone for 30 minutes).
- **Lock Screen controls:** the Live Activity shows Remote's Back 10, Play or Pause and Forward 10 with what is playing, or Present's Back, Next and the running timer.
- **Siri and Shortcuts:** Open Glasspad Mode and Open Glasspad Layout. Mission Control from Siri works and says what happened.
- **Mode menu:** swipe the mode button sideways to go back to the previous mode or layout.
- **Keyboard:** Glasspad draws its own Mac keyboard, sized to fit, with the Mac's letters.
- **Window highlight:** pick a window on the phone and the Mac outlines it for a second.
- **Battery:** the Mac shows the iPhone's battery level, and the iPhone mentions it once at 20% and 10%.
- **Remote:** the More menu lists the Mac's sound outputs.
- **Renewal:** iPhone Settings > About shows when the app needs renewing. Mac Settings > iPhone shows the last renewal and any problem in plain words.
- **Website:** Features and Compare menus, six feature pages and three comparisons, one footer everywhere, and Install as the main button.

### Changed

- The connection to the Mac recovers faster. Taps wait briefly for a quick reconnect, and the iPhone says why the Mac is away: asleep, Glasspad turned off, locked, or this iPhone forgotten.
- Displays and Arrange are calmer, with less text.
- Clipboard moved out of the mode menu. It opens from the end of Keyboard's shortcut row, or from the Library.
- The Live Activity shows Remote, Media and Present controls instead of the trackpad's connection status.
- Siri's Open Mission Control waits for the Mac's answer and never sends a second try that could close it again.
- The installer now builds an optimized iPhone app, which is lighter on battery.

### Fixed

- Leaving Keyboard no longer holds on to memory, and trying themes uses far less memory.
- Lower idle cost on the Mac and the iPhone: fewer redraws, no needless checks, timers only when needed.
- A macro stopped right after a step reports the right step.

## [0.1.2] - 2026-10-16

### Added

- **Arrange:** Split Screen opens a sheet showing which windows go where before anything moves. Choose Left & Right, Top & Bottom, Quarters or Full Screen (Split View), pick the windows and the display, then one tap.
- Window buttons for the four quarters and Return to Previous Size.

### Fixed

- Mission Control, Show Desktop and App Windows did nothing: macOS stopped Mission Control when it was started directly. They now ask the Dock.
- Split Screen failed when the two windows were on different displays, and refused windows in full screen. The second window now moves to the right display first, and full-screen windows leave full screen first, as macOS does.
- Window tiling finds the Mac's Move & Resize items by their internal names, so it works in every language, and never makes the menu bar icon wait.
- Tiling leaves room for Stage Manager's strip.
- Eject All could freeze the menu bar icon while a disk was busy.
- Brightness buttons now reach the laptop screen when an external display is the main one.
- Displays moves full-screen windows and brings background windows forward.
- When macOS denies paste access, Get from Mac now says why instead of coming back empty.
- Labels on bright buttons are dark so they stay readable.

## [0.1.1] - 2026-10-16

### Fixed

- The Mac menu bar icon could stop responding while Media looked up Spotify or Music, because macOS never answered a permission check. That check now never makes the app wait.

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
- **Mode menu:** one piece of glass that grows out of the mode button, with Clipboard, Present, Remote and Displays as tools and a Layouts row.
- **Pairing:** a living pairing code on the Mac (soft dots that still read as a QR code, valid for 5 minutes), a viewfinder on the iPhone that locks onto it and gathers the dots into a check mark, and Copy Link and Share for an iPhone that cannot scan.
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
- Buttons from the older Deck move into Pinned once, without losing anything. A new Pinned starts with six essentials: Screenshot, Do Not Disturb, Split Screen, Lock Screen, Mute and Dark Mode.
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
- Buttons made by a newer Glasspad are kept when you save your buttons, shown as "Update Glasspad to use this", and never run.
- When one trackpad pane replaces another (switching layouts, for example), the iPhone keeps its Wi-Fi awake for the pointer instead of letting it doze.
- Key repeat stops when a touch is canceled.
- A drag to reorder buttons that ends outside a drop target ends on the next tap.
- When a Mac cannot report what is playing, Glasspad now shows why and stops retrying.
- Website logos use less memory and are released when the iPhone runs low on memory.
- Setup text is no longer cut off at the sides, and the Mac's menu bar window no longer clips.

[0.2.1]: https://github.com/Soham109/glasspad/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/Soham109/glasspad/compare/v0.1.2...v0.2.0
[0.1.2]: https://github.com/Soham109/glasspad/compare/v0.1.1...v0.1.2
[0.1.1]: https://github.com/Soham109/glasspad/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/Soham109/glasspad/releases/tag/v0.1.0
