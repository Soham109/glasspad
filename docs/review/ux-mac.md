# Mac app UX review

Scope: menu bar popover, Settings window, Mac first run, pairing across both devices, naming across Mac, iPhone, website and README, Mac error and empty states, accessibility, native feel. Based on snapshots in /tmp/gpmac (light and dark) and a read of Apps/Mac/Sources, Apps/iOS/Sources/Pairing, README.md and web/index.html. Not tested with a live VoiceOver session or a real first launch; those items are marked "unverified".

Severity: High, Medium, Low. Effort: S, M, L.

## Issues, ranked

1. **Mode name "Dock" vs "Apps" (High, S).** iPhone app, README and Mac Settings call the mode Dock. The website calls it Apps (web/index.html lines 86, 140, 275, 392). AppMode.swift even notes it "was called Apps for a while". A visitor reads "Apps", opens the phone, finds "Dock". Fix: change the website to Dock, or rename in the app. Pick one, apply everywhere.

2. **Mac Settings tab "Actions & Macros" with sub-tabs "Macros" and "App Buttons" (High, M).** iPhone and website say Actions, Pinned, Library, Macros. "App Buttons" appears nowhere else. Fix: sub-tabs become "Per-App Sets" and "Pinned" (or whatever the phone calls them), and the Mac names must match the phone's words exactly.

3. **Silent first launch on Mac (High, M).** GlasspadApp is menu bar only and opens nothing on first launch. A new user who just dragged the app in sees no window and may think nothing happened. Fix: on first launch (no paired phones), open the popover or a small welcome window pointing at the menu bar icon, with the QR shown straight away. Unverified on a real first launch.

4. **Permissions are asked late and out of order (High, M).** The popover lists Accessibility and Spotify, but the user must click Allow themselves, and Spotify is asked as a peer of Accessibility even though it is optional. The first-run snapshot shows no checklist at all (fixture has permissions granted), so the real first-run view was not rendered. Fix: show only Accessibility until a phone pairs, mark Spotify "Optional", and add a first-run snapshot with nothing granted.

5. **Pairing wording differs across devices (Medium, S).** Mac menu: "Pair Your iPhone…". iPhone onboarding: "Pair Your iPhone" as a heading on the phone itself, plus "Pair a Mac" elsewhere. Mac sheet tells the user to "tap Pair"; the iPhone button is "Scan the code" or "Pair a Mac" depending on screen. Fix: Mac says "In Glasspad on your iPhone, tap Pair a Mac, then scan this code". Phone says "On your Mac, choose Pair Your iPhone in the Glasspad menu" (already close).

6. **Pairing has no feedback or timeout on the Mac (Medium, M).** The QR popover shows only Cancel. No "Waiting for iPhone", no success confirmation, no expiry or error if the scan fails (unverified; no expiry found in the code). Fix: spinner line under the code, a green "Paired with <name>" state, and a "code expired, show a new one" state.

7. **Raw developer text in Macros editor (Medium, S).** Placeholders such as "e.g. fourFingerTap", "c, return, f5, left, code:93" and "App bundle ID" are developer terms. Fix: show a picker for gestures, label the field "App", and let users choose an app by name.

8. **Spelling and locale (Low, S).** "Colour" in the Macros editor (MacrosSettings.swift:260) is British; the rest of the UI and README are US ("Color" is the macOS word in a US locale). Pick one. Also "Allow Automation" in Settings does not match the popover label "Spotify Control" vs Settings "Music and Spotify". Make all three say "Music and Spotify".

9. **Accessibility gaps (Medium, M, unverified with VoiceOver).** Good: header combined into one element, hidden decorative icons, Allow buttons labelled, QR has a label and hint. Gaps: the QR cannot be used by a VoiceOver user (no fallback such as a typed code, which the iPhone has via paste text, but the Mac does not show one); sub-tabs and the macro list rely on double-click to edit ("Double-click a step to edit it") with no keyboard route; signal bars are hidden in the popover (fine) but the status text says "Excellent signal" so that is covered. Fix: show a short copyable pairing link under the QR, and make Return open the selected step.

10. **Contrast of secondary text (Low, S).** Grey captions and tertiary shortcut hints (⌘, and ⌘Q) are low contrast in the light snapshots, and the grey on off toggles is faint. Fix: use .secondary instead of .tertiary for shortcuts, and check captions against 4.5:1.

11. **Non-native touches (Low, S).** Mostly native (SwiftUI MenuBarExtra, SettingsLink, standard tabs). Oddities: popover rows are custom, so they do not highlight or work with arrow keys like a real menu; the Settings window is wide and tall with oversized body text; Advanced shows "Rejected packets" and "Round trip, slowest 5%" to every user, which suits a Debug section. Fix: group the diagnostics under a "Diagnostics" disclosure.

12. **Number format (Low, S).** The Advanced snapshot shows "1,84,220" because the snapshot ran in an Indian locale. That is correct for that locale; just confirm the app uses the system formatter everywhere (it appears to).

## What is already good

- Popover status header answers "who is connected and how well" in one glance, with plain words.
- Empty state in Settings > iPhone is clear ("No iPhones Paired" plus a button).
- Hide Mac Dock explains it restores your Dock on quit.
- Dark mode renders cleanly in every snapshot.
- Plain language, no jargon in most strings; no em dashes in the Mac copy.

## Suggested order

Fix 1, 2, 5 first (copy only, one pass across Mac, iPhone, README and website). Then 3, 4, 6 as one "first run" change. Then the rest.
