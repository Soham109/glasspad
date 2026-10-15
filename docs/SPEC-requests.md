# Interface requests

Requests from one part of Glasspad to another. Add a request at the bottom, and mark it
done (with the shipped names) when it lands.

## 1. Macros mode messages (from: iPhone app, to: GlasspadKit)

Superseded by `docs/SPEC-macros.md` section 6 (`case macro(MacroMessage)`). The iPhone app
builds against that shape. One addition is still needed: `GlasspadMode.macros`, so the phone
can send `modeSelected(.macros)` like every other screen.

Until `MacroMessage` exists in GlasspadKit the iPhone app leaves the Macros screen and the
"Run macro" action out, rather than shipping a screen that cannot work.

## 2. Mac side notes (from: GlasspadMacCore, to: GlasspadKit and coordinator)

- `ModeRouter.handle` switches over every `ModeMessage` case. When the macros cases from
  request 1 land, add them there (`Packages/GlasspadMacCore/Sources/GlasspadMacCore/Modes/ModeRouter.swift`)
  or the Mac package stops compiling.
- GlasspadKit exports `PairedPhone` (transport view). The Mac's Keychain record is named
  `StoredPhone` to avoid a clash; no kit change needed.
- Haptics: the Mac does not echo `GestureRecognizer.onHaptic` back to the phone, because the
  phone runs its own recognizer for instant clicks. The Mac only sends `.haptic(.snap)` when a
  Dock-level swipe (Spaces, Mission Control, ...) actually completes. Confirm this split.
- `forceClick(stage:)` has no native path yet (it would need private pressure events, type 34).
  Stage 2 triggers Look Up (ctrl+cmd+D) when `settings.lookUp == .forceClick`.
- `notificationCenter` has no private-event path; the Mac clicks the menu bar clock through
  System Events, which needs the Automation permission the first time.
- Build products now live in `~/Library/Caches/glasspad-build/<package>` (override with
  `GLASSPAD_BUILD_ROOT`). The repo sits in an iCloud-synced Desktop, which tags bundles with
  Finder info, and codesign then refuses the test bundle. `scripts/test.sh` also runs every
  package before failing, instead of stopping at the first failure.

## 3. Copy pairing link (from: iPhone app, to: Mac app)

The phone's pair screen accepts a pasted `glasspad://pair?...` link when there is no camera
(simulator, or camera access denied). A "Copy pairing link" item next to the QR code in the
Mac popover would make that path usable without a terminal. Scanning the QR with the
iPhone's own Camera app already works: it opens Glasspad through the `glasspad://` URL scheme
and pairs.
