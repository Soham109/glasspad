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

## 5. Accessibility-off warning on the phone (from: Mac app and GlasspadKit, to: iPhone app)

The Mac now sends `ControlMessage.macStatus(MacStatus)` right after each handshake and whenever a
field changes (docs/SPEC.md section 5, "As built"). Requested on the phone:

- Show a banner on Trackpad (and anywhere input is sent) while `accessibilityTrusted == false`:
  "Glasspad on <macName> needs Accessibility. On your Mac, open System Settings > Privacy &
  Security > Accessibility and turn on Glasspad." Hide it as soon as a status with `true`
  arrives. Do not cache it across sessions; a new session always gets a fresh status.
- Optional: on Media, when `automationMedia == .denied`, say what is playing cannot be shown
  until Spotify and Music control is allowed on the Mac.
- `MacSession.received(_:)` currently has `case .bye, .ping, .pong, .macStatus, .unknown: break`
  (the only iOS change made, so the app compiles). Replace the `.macStatus` part with the
  handling above. Keep ignoring `.unknown`.

## 6. Typed pairing code for VoiceOver users (from: Mac app, to: GlasspadKit, follow-up)

The Mac now offers Copy Link and Share (AirDrop) under every QR code, so a VoiceOver user can
pair without the camera: copy on the Mac, then "Paste the Link Instead" on the phone. A short
code typed by hand (for example 8 characters) is not possible with the current protocol: the
QR carries a 32-byte pairing key, and a short code would need a new key agreement step
(for example SPAKE2 or a similar password-authenticated exchange) so a guessable code cannot
be brute-forced on the network. That is a protocol change beyond additive messages, so it is
left as a follow-up.

Request 3 above (Copy pairing link) is done: Copy Link and Share… in the Mac popover, the
Settings pairing sheet and the Welcome window.

