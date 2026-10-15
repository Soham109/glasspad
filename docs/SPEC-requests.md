# Interface requests

Requests from one part of Glasspad to another. Add a request at the bottom, and mark it
done (with the shipped names) when it lands.

## 1. Macros mode messages (from: iPhone app, to: GlasspadKit)

Superseded by `docs/SPEC-macros.md` section 6 (`case macro(MacroMessage)`). The iPhone app
builds against that shape. One addition is still needed: `GlasspadMode.macros`, so the phone
can send `modeSelected(.macros)` like every other screen.

Until `MacroMessage` exists in GlasspadKit the iPhone app leaves the Macros screen and the
"Run macro" action out, rather than shipping a screen that cannot work.

Done: `ModeMessage.macro(MacroMessage)`, `GlasspadMode.macros`, and the payload types
`MacroSummary` (with `rgb`), `ActiveProfileInfo`, `MacroProgress` (with `fraction`), `RunOutcome`,
exactly as in SPEC-macros section 6, plus one extra Mac -> phone case,
`recordingFailed(message:)`, sent when recording cannot start or nothing was captured. The Mac
handles every case (GlasspadMacCore `MacroCoordinator`).

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

## 3. Connectivity for the phone (from: GlasspadKit, to: iPhone app)

All additive; nothing the phone uses today changed shape.

- Call `client.reconnectNow()` when the app returns to the foreground.
- Persist `client.onWakeTarget` values with the pairing, and offer "Wake Mac" with
  `WakeOnLAN.send(to:)` (needs the `com.apple.developer.networking.multicast` entitlement for
  the broadcast copy). `KnownMacsStore` + `MacConnector` do this, plus last-used auto-connect,
  if the app wants to use them instead of its own `PairingStore`.
- Expect `failed(GlasspadService.replacedFailure)` (and a `bye(replacedReason)` message) when
  another iPhone takes the Mac; the client stops retrying until `connect()` is called again.
- `AppMode.macros.wireMode` can now return `.macros`.

## 4. Trackpad feel settings (from: trackpad feel, to: Settings screen)

- Please place `TrackpadTuningSection()` (in `Apps/iOS/Sources/Trackpad/TrackpadTuningSection.swift`)
  inside the Settings `Form`, for example after the Feel section. It is a `Group` of three
  `Section`s (Pointer with a live preview pad, Scrolling, Haptics by kind) and reads
  `TrackpadTuningStore.shared` itself; it needs only the `\.palette` environment.
- Values live in `TrackpadSettings.tuning` (`TrackpadTuning`, in GlasspadKit). The phone owns them
  (`TrackpadTuningStore`, UserDefaults key `trackpadTuning`) and sends them inside
  `ControlMessage.settings`; the Mac stores them (UserDefaults key `phoneTrackpadTuning`).
- One small additive change outside the trackpad folder: `MacSession.send(control:)` in
  `Apps/iOS/Sources/Link/MacSession.swift`, used to send that message.
- `HapticKind.dragLock` is new. Code that switches over `HapticKind` must handle it.
