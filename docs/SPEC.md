# Glasspad: build spec

Glasspad turns an iPhone into a control surface for a Mac: a wireless trackpad with
haptics, plus Keyboard, Media, Dock, Actions (Deck and Macros), Remote, Present, Clipboard,
Displays and the StandBy screens (Clock, Now Playing, Calendar), alone or up to three at once
in a layout. Open source, MIT.
This file is the contract every part is built against. If you change an
interface here, change it everywhere.

## 1. Principles

- Feels like the Mac's own trackpad. Gestures follow the user's real macOS
  trackpad settings, read live from `defaults`.
- Lowest possible latency over Wi-Fi. Measure it, never guess it.
- Minimal UI. The trackpad screen is a plain surface in the theme's colors
  with a dot under each finger. Nothing else unless asked for.
- Safe for the phone. Only public iOS APIs on the phone. Dims after idle,
  backs off when the phone is warm, never forces max brightness.
- Private macOS APIs are allowed on the Mac side (not an App Store app), but
  every private call has a public fallback and a runtime self-check.
- Secure by default: it controls the Mac, so every packet is encrypted and
  authenticated with a key that only a paired phone has.

## 2. Repo layout

```
glasspad/
  Packages/GlasspadKit/          shared Swift package (iOS 17+, macOS 14+)
    Sources/GlasspadKit/
      Protocol/                  wire messages, binary codec, Deck types, lenient decoding
      Crypto/                    pairing payload, session keys, AEAD framing
      Transport/                 Bonjour discovery, TCP control, UDP touch link, known Macs, Wake-on-LAN
      Gestures/                  touch model, TrackpadSettings, GestureRecognizer, Mac acceleration
      Pairing/                   living pairing pattern, Vision code reader
      Layouts/                   ScreenLayout, templates, divider math, what to tell the Mac
      Theme/                     ThemeCatalog, photo tone
      Power/                     PowerPolicy
      StandBy/                   clock faces, burn in shift, night mode, StandBy power
      Remote/                    RemoteKeymap
      Displays/                  display and window types, frame math
      Layout/                    tile grids
      Media/, Keys/, Web/        playback clock, keyboard input, website icons
      Present/, Live/, Install/  talk timer, Lock Screen controls, install expiry
    Tests/GlasspadKitTests/
  Packages/GlasspadMacCore/      Mac-only logic as a package (macOS 14+)
    Sources/GlasspadMacCore/
      Settings/                  reads macOS trackpad prefs -> TrackpadSettings
      Synth/                     CGEvent pointer/click/scroll, private gestures, MotionScheduler
      Server/                    controller, pairing store and flow, touch pipeline, Mac status
      Modes/                     Dock, Keys, Media, Deck, Clipboard, Present, Displays, Mac controls, tiling
      Macros/                    bridge between Macros mode and GlasspadMacros
      LiveCheck/, Install/       the guided live check, renewal status for Settings
    Tests/GlasspadMacCoreTests/
  Packages/GlasspadMacros/       macros engine (macOS 14+), see docs/SPEC-macros.md
  Apps/Mac/                      menu bar app (SwiftUI + AppKit), a SwiftPM package
    Helpers/                     now playing helper (MediaRemote)
    Tests/GlasspadMacSnapshots/  wording and pairing code tests, snapshot harness
  Apps/iOS/                      iPhone app (iOS 18+, SwiftUI + UIKit touch view), widgets
  project.yml                    XcodeGen project for both apps
  install.sh                     one-line installer
  scripts/                       test.sh, build-mac.sh, install and renewal scripts, tests/
  docs/                          developer docs (start at docs/README.md), SPEC, ADRs, images
  web/, promo/                   website and demo film
```

Build without Xcode (Mac side only): `scripts/test.sh` and `scripts/build-mac.sh`.
The scripts keep intermediate build files in `~/Library/Caches/glasspad-build` (`GLASSPAD_BUILD_ROOT`), outside the repo.
Command line tools need extra flags for swift-testing; `scripts/test.sh` adds them:
`-Xswiftc -F$F -Xlinker -F$F -Xlinker -rpath -Xlinker $F` with
`F=/Library/Developer/CommandLineTools/Library/Developer/Frameworks`.
Tests use swift-testing (`import Testing`), not XCTest.

## 3. Pairing and crypto (GlasspadKit/Crypto)

- Mac generates once: `macID` (UUID) and per-phone `pairKey` (32 random bytes).
- Mac shows a QR code: `glasspad://pair?v=1&id=<macID>&name=<urlenc name>&k=<base64url pairKey>`.
- Phone scans it (camera) and stores `{macID, name, pairKey}` in Keychain.
  Mac stores `{phoneID, phoneName, pairKey}` in its Keychain. Mac can revoke.
- Session: on each connect both sides send a 16-byte random nonce in Hello.
  `sessionKey = HKDF-SHA256(ikm: pairKey, salt: phoneNonce || macNonce, info: "glasspad v1 session", 32 bytes)`.
- AEAD: ChaCha20-Poly1305 (CryptoKit). Nonce (12 bytes) = 4-byte direction
  tag (`"P2M\0"` phone to Mac, `"M2P\0"` Mac to phone) + 8-byte big-endian counter.
  Separate counters for TCP and UDP (UDP uses tags `"P2MU"`/`"M2PU"`).
- Replay: TCP counters must strictly increase. UDP accepts a sliding window of
  64 behind the highest counter seen and rejects duplicates.
- Wrong key or bad tag: drop silently and count it (`LinkStats.authFailures`, `replayDrops`).

Public API:
```swift
public struct PairingPayload: Codable, Equatable, Sendable {
  public var macID: UUID; public var macName: String; public var pairKey: Data
  public init(macID: UUID, macName: String, pairKey: Data)
  public var url: URL                       // glasspad://pair?...
  public init?(url: URL)
}
public struct SessionCrypto: Sendable {
  public enum Role: Sendable { case phone, mac }
  public init(pairKey: Data, phoneNonce: Data, macNonce: Data, role: Role)
  public mutating func sealTCP(_ plaintext: Data) throws -> Data
  public mutating func openTCP(_ sealed: Data) throws -> Data
  public mutating func sealUDP(_ plaintext: Data) throws -> Data
  public mutating func openUDP(_ sealed: Data) throws -> Data   // replay window
}
```
Sealed format: `counter(8, BE) || ciphertext || tag(16)`.

As built (GlasspadKit):
- `phoneID` is a `String` (the phone app picks it, e.g. a UUID string).
- Key confirmation: right after the two Hellos, each side sends one sealed TCP
  frame whose plaintext is `"glasspad confirm v1"` (phone first, then Mac). The
  Mac only stores a new pairing, and the phone only reports `connected`, after
  the other side's confirmation opens. A wrong key never gets past this step.
- Refusal: instead of its Hello the Mac may send plaintext
  `{"t":"reject","reason":"not paired" | "wrong mac" | "unsupported version N" | ...}`
  and close. The phone shows `failed(reason)` and does not retry.
- Helpers: `PairingPayload.generateKey()`, `randomBytes(_:)`.
  `SessionCryptoError`: `tooShort`, `replay`, `authenticationFailed`, `counterExhausted`.
- The code (Oct 2026): `PairingFlow` (GlasspadMacCore) keeps one code valid for 5 minutes
  (`codeLifetime`), then disarms its key and shows Code Expired. The QR code is drawn as a
  living pattern (`Pairing/PairingPattern.swift`): finder squares stay solid, every other dark
  module is a dot that drifts at most 0.07 of a module, and the dots gather into a checkmark
  when pairing finishes. The phone reads it from camera frames with Vision
  (`PairingCodeReader`, which also tries the picture inverted for the dark card in Dark Mode).
  `PairingPatternTests` and the Mac's `PairingCodeRenderTests` render the moving code in light
  and dark and read it back. Copy Link and Share (AirDrop) carry the same `glasspad://pair` link.

## 4. Transport (GlasspadKit/Transport)

- Mac advertises Bonjour `_glasspad._tcp` with TXT `id=<macID>`, `v=1`.
- Phone browses (`NWBrowser`), finds the paired macID, opens TCP (control).
  TCP: `noDelay = true`, frames are `UInt32 BE length || sealed`.
- TCP handshake (Hello is the only plaintext message, JSON):
  phone -> `{"t":"hello","v":1,"phoneID":..,"phoneName":..,"macID":..,"nonce":b64}`
  mac   -> `{"t":"hello","v":1,"nonce":b64,"udpPort":N}`
  After that, everything is sealed.
- UDP touch link: phone sends sealed touch packets to `udpPort`. Mac learns the
  phone's UDP address from the first valid packet. Parameters:
  `serviceClass = .interactiveVoice` (WMM voice queue), `includePeerToPeer = true`.
- Keep-awake: while the trackpad screen is visible, the phone sends a
  heartbeat every 20 ms when no touches are flowing, so the Wi-Fi radio never
  enters power save. Stops when the screen is hidden or the phone is idle 2 min (10 s in Low
  Power Mode), and pauses while the phone is warm (`PowerPolicy`, section 9).
- RTT: Mac sends `ping` on TCP each second, phone answers `pong` with the
  same id; the Mac turns median and p95 RTT into signal bars on the iPhone row of its menu
  bar popover (`SignalQuality`).
- Reconnect automatically with backoff (`ReconnectBackoff.steps`: 0.2, 0.5, 1, 2, 5, 10, 30 s, the last
  repeating; waits of 5 s and more move by up to 20% either way, and a quiet Bonjour browse tries
  at once when the Mac's service comes back).

Public API (both sides use these; names are fixed):
```swift
public final class GlasspadServer   // macOS only: listener, sessions, callbacks
public final class GlasspadClient   // iOS (and macOS for tests): browse, connect
public protocol GlasspadLinkDelegate: AnyObject {  // messages and state changes
  func link(didChangeState state: LinkState)
  func link(didReceive message: ControlMessage)
  func link(didReceive frame: TouchFrame)          // server side only
}
public enum LinkState: Equatable, Sendable { case idle, searching, connecting, connected(rttMs: Double?), failed(String) }
```

As built (GlasspadKit), exact signatures:
```swift
// Server (macOS). Every member is thread safe. Callbacks arrive on delegateQueue.
public init(macID: UUID, macName: String, tcpPort: UInt16 = 0, udpPort: UInt16 = 0,
            advertise: Bool = true, delegateQueue: DispatchQueue = .main,
            pairKeyLookup: @escaping @Sendable (String) -> Data?)   // phoneID -> pairKey, nil = unknown/revoked
public weak var delegate: (any GlasspadLinkDelegate)?
public var pendingPairKey: Data?          // key in the QR on screen; accepted once for an unknown phone
public var onPaired: (@Sendable (PairedPhone) -> Void)?   // new phone proved the key; app stores it
public func start() throws; public func stop()
public func send(_ message: ControlMessage)               // to the active phone
public func disconnect(reason: String)                    // sends bye, closes (phone reconnects)
public var state: LinkState; public var stats: LinkStats  // RTT median/p95, auth failures, replays...
public var ports: (tcp: UInt16, udp: UInt16)?; public var connectedPhone: PairedPhone?
public struct PairedPhone { phoneID: String; phoneName: String; pairKey: Data }

// Client (iOS, and macOS for tests).
public init(phoneID: String, phoneName: String, pairing: PairingPayload, delegateQueue: DispatchQueue = .main)
public func connect()                             // Bonjour, match TXT id == pairing.macID
public func connect(host: String, port: UInt16)   // direct (tests, manual address)
public func disconnect()
public func send(frame: TouchFrame)               // client assigns seq
public func send(message: ControlMessage)
public var heartbeatsEnabled: Bool                // true while the trackpad screen is visible
```
- One active phone at a time; a new authenticated connection replaces the old one.
- `pairKeyLookup` runs on the server's private queue; do not call back into the server from it.
- `ping`/`pong` are answered and measured inside the transport, never delivered.
  `link(didReceive frame:)` has a default empty implementation.
- A `bye` from the phone closes its session. TCP frames (including Hello) are
  `UInt32 BE length || payload`, max 16 MiB.
- Replacing a session: the Mac sends the old one `bye(GlasspadService.replacedReason)`; a client
  that gets it stops retrying and reports `failed(GlasspadService.replacedFailure)`, so two phones
  never take turns. `server.onSessionStarted(PairedPhone)` fires for every new active session
  (the state can stay `connected` through a replacement); the Mac resets input and resends
  settings and mode data there.
- Liveness: the client reconnects at once after `clientSilenceTimeout` (3.5 s) with no frame from
  the Mac, on an `NWPathMonitor` change (interface gone, another Wi-Fi network, back from no
  network), and on `client.reconnectNow()` (call it on foreground). The Mac closes a session after
  `serverSilenceTimeout` (6 s) without hearing from the phone. Any bytes from the peer count, including part of a frame
  still arriving (`ControlChannel.onBytes`; on the Mac only for the active, authenticated
  session), so a large clipboard message on slow Wi-Fi keeps the link up while the pings queue
  behind it (`ConnectivityTests.slowLargeMessage*`, through a throttling loopback proxy).
- Wake-on-LAN: after each handshake the Mac sends a sealed, transport-internal
  `{"t":"wake","target":WakeTarget}` (hardware address, subnet broadcast, last IPv4) worked out
  from the interface the phone connected on (`server.wakeTargetOverride` replaces it). The client
  exposes `wakeTarget` / `onWakeTarget`; `WakeOnLAN.send(to:)` sends the 102-byte magic packet to
  the broadcast, 255.255.255.255 and the unicast address. On iPhone broadcast needs the
  `com.apple.developer.networking.multicast` entitlement.
- Several Macs: `KnownMacs` (value) + `KnownMacsStore` (Keychain item, thread safe) remember every
  pairing, when it last connected, its wake target and the last used Mac. `MacConnector` owns one
  client at a time: `connect(to:)`, `connectToLastUsed()`, `wake(_:)`, optional `manualAddress`.
  `GlasspadDiscovery` lists every Mac advertising nearby. `server.isAdvertising` reports Bonjour
  registration.
- While any finger is down the client resends the last snapshot (phases set to
  `stationary`, fresh timestamp) every 20 ms; otherwise it sends heartbeats when
  `heartbeatsEnabled` and the phone touched within 2 min.
- Shared network first (feel pass, Oct 2026): the phone browses and connects with
  `includePeerToPeer = false` and cellular prohibited; only if the Mac is not found within
  `GlasspadService.peerToPeerFallbackDelay` (3 s) does it browse again with peer-to-peer Wi-Fi
  (AWDL) allowed. While AWDL is active the Wi-Fi chip hops to AWDL channels several times a
  second, which shows up as periodic latency spikes on every packet. The Mac's listeners keep
  peer-to-peer on so the fallback works, and log `(peer-to-peer Wi-Fi: expect latency spikes)`
  when a phone arrives that way. `tcpParameters(peerToPeer:)` / `udpParameters(peerToPeer:)`.
- Measured RTT on the owner's Wi-Fi with heartbeats: median 7.6 ms (TCP ping, includes the
  phone's power-save wake). The 1.1 ms figure was over the USB cable (`en8`). Without
  heartbeats the median is 70 to 120 ms.

## 5. Wire messages (GlasspadKit/Protocol)

UDP touch packet plaintext (little endian, compact):
```
u8  kind          1 = touches, 2 = heartbeat
u32 seq
u64 tPhoneMicros  phone monotonic clock
u8  count         0..10
per touch (8 bytes):
  u8  id          stable per finger for its lifetime
  u8  phase       0 began 1 moved 2 stationary 3 ended 4 cancelled
  u16 x           0..65535 across the surface width
  u16 y           0..65535 across the surface height
  u8  majorRadius points / 2, clamped
  u8  reserved
```
Also in the packet header (after count): `u16 surfaceWidthPt`, `u16 surfaceHeightPt`
so the Mac can convert to physical points (needed for speed and acceleration).

```swift
public struct Touch: Equatable, Sendable { public var id: UInt8; public var phase: TouchPhase; public var x: Double; public var y: Double; public var majorRadius: Double } // x,y in points
public enum TouchPhase: UInt8, Sendable { case began, moved, stationary, ended, cancelled }
public struct TouchFrame: Equatable, Sendable { public var seq: UInt32; public var timestamp: TimeInterval; public var touches: [Touch]; public var surface: CGSize }
public enum TouchCodec { static func encode(_: TouchFrame) -> Data; static func decode(_: Data) throws -> TouchFrame; static func heartbeat(seq:) -> Data }
```

Control messages (TCP, sealed, JSON, `Codable` enum with `t` discriminator):
```swift
public enum ControlMessage: Codable, Equatable, Sendable {
  case ping(id: UInt32), pong(id: UInt32)
  case settings(TrackpadSettings)                 // mac -> phone, on connect and on change
  case haptic(HapticKind)                         // mac -> phone, e.g. space snapped
  case mode(ModeMessage)                          // both ways, see section 8
  case bye(reason: String)
  case macStatus(MacStatus)                       // mac -> phone, see below
  case phoneStatus(PhoneStatus)                   // phone -> mac, see below
  case unknown(type: String)                      // a type from a newer build, ignored
}
public enum HapticKind: String, Codable, Sendable { case click, forceClick, detent, snap, error, dragLock }
```

As built (GlasspadKit):
- Every touch packet is a full snapshot: it lists every finger currently down.
  A finger missing from a packet is treated as lifted, so a lost "ended"
  packet heals on the next one.
- `TouchFrame.timestamp` is the phone's `systemUptime` in seconds (UITouch
  timestamps already are). The Mac never compares it with its own clock directly.
- `TouchCodec`: `encode(_:)`, `decode(_:)` (touches only), `decodePacket(_:) -> TouchPacket`
  (`.touches(TouchFrame)` or `.heartbeat(seq:timestamp:)`), `heartbeat(seq:timestamp: = 0)`.
  Malformed packets throw `TouchCodecError`. A heartbeat is the 18-byte header with count 0.
- `ControlMessage.jsonData()` and `ControlMessage.from(jsonData:)` are the wire helpers.
- `ModeMessage` (in `Protocol/ModeMessage.swift`, `"t"`-discriminated JSON like
  `ControlMessage`, e.g. `{"t":"dockOpen","bundleID":".."}`; the older synthesized shape still
  decodes; one doc comment per case with its direction): `modeSelected`, `dockRequest`,
  `dockList(apps: [DockApp])`, `dockOpen(bundleID:)` (launch or activate),
  `keysText`, `keysKeystroke(Keystroke)`, `mediaRequest`, `mediaState(MediaState)`,
  `mediaCommand(MediaCommand)`, `mediaSetVolume`, `mediaSetBrightness`,
  `deckRequest`, `deckButtons([DeckButton])`, `deckRun(id:)`,
  `deckResult(id:ok:message:)`, `clipboardPush(ClipboardContent)`, `clipboardPull`,
  `clipboardContent(ClipboardContent?)`, `presentNext`, `presentPrevious`,
  `presentLaser(on:)`, `presentLaserPosition(x:y:)` (0...1 of the main display),
  `macro(MacroMessage)` (docs/SPEC-macros.md section 6, plus `recordingFailed(message:)`).
  Clipboard answers (Oct 2026, additive): `clipboardPushResult(ok:message:)` answers every
  `clipboardPush`, and `clipboardPullRefused(message:)` comes just before `clipboardContent(nil)`
  when the Mac will not send what it has. Text over `ClipboardContent.maxTextBytes` (2 MB,
  UTF-8) is refused whole, never cut. The phone shows "Sent" only after `ok: true`.
  `GlasspadMode.macros` exists for `modeSelected(.macros)`, which makes the Mac send `macroList`.
  Remote (Oct 2026, additive): `modeSelected(.remote)` makes the Mac send media states (as for
  Media) and `frontmostApp` (as for Dock and Deck). `remoteSystem(id:action:)` runs one
  `DeckSystemAction` without a Deck button (Sleep Display, Do Not Disturb, volume keys); the
  Mac answers `deckResult` for `id` and refuses actions that need confirming. An older Mac
  drops both, and the phone falls back to plain media and key messages. On success the Mac
  sends the new state of a switch as `message` ("Do Not Disturb is on"), as for Deck runs.
  Layouts (Oct 2026, additive): after `modeSelected` (the pane `LayoutWirePlan` picks), a layout
  of several panes sends `modesShown([GlasspadMode])`, every pane's mode. The Mac then pushes
  `frontmostApp` while any of Dock, Deck or Remote shows and Dock list changes while Dock shows.
  Modes it does not know are skipped. An older Mac drops it; a Dock pane still asks for its list
  every 3 seconds.
  Deck actions from a newer build (a new kind, or a Mac control this build does not know) decode
  as `DeckAction.unsupported` with the raw JSON, written back unchanged, so saving the Deck never
  loses them; lists of buttons and pages skip only an element that cannot be read at all. The
  phone shows such a button as "Update Glasspad to use this"; the Mac refuses to run it, and
  refuses a `deckSave` that adds or changes one. A `deckSave` with no `deckSaveResult` within
  10 seconds (an older Mac drops what it cannot read) shows as not saved.
  Displays (Oct 2026, additive; types in `Displays/DisplayTypes.swift`): `displaysWatch(on:)`
  (phone -> Mac) starts or stops `displaysState(DisplaysState)` (Mac -> phone), sent at once and
  again on every change, read four times a second while watched; any Displays screen or layout
  pane watches, so it does not depend on `modeSelected`. `DisplaysState`: `displays`
  (`MacDisplay`: id, name, frame, visibleFrame, isMain, isBuiltIn, notchWidth, mirrorOf,
  brightness, resolutions, resolutionID), `windows` (`MacWindow`, front to back: id, bundleID,
  appName, title, frame), `nightShift`, `canArrangeWindows`, `tileMargin`, `pending`. Frames are
  Quartz global points (origin top-left of the main display, y down), each `CGRect` as
  `[[x, y], [width, height]]`. Window order and frames come from the window server's list and
  names from the Accessibility API, so Screen Recording is never needed. The Mac sends
  `dockIcons` for apps the phone has not had icons for just before the state that first lists
  them. `windowCommand(id:windowID:command:)` (`raise`, `tile(WindowTile)`, `split(with:)`,
  `move(display:origin:)`, `minimize`, `close`, `fullScreen`) and `displayCommand(id:command:)`
  (`brightness`, `resolution`, `mirror`, `makeMain`, `arrange`, `keepChanges`, `revertChanges`)
  are answered with `displaysResult(id:ok:message:)`. Frames for tiles, splits and moves come
  from `DisplaysState.frames(for:window:)`, the same code on both sides, so the phone shows the
  result before the Mac confirms. `windowHighlight(windowID:)` has the Mac outline that window for
  about a second in a click-through overlay (no fade with Reduce Motion; nothing moves or comes
  forward, no answer), sent only when `DisplaysState.highlightsWindows` is true.
  A new resolution or mirroring is applied for Glasspad's run
  only and shows as `pending`; `keepChanges` makes it permanent, and without it the Mac restores
  the permanent setup after 15 seconds by itself (`CGRestorePermanentDisplayConfiguration`), like
  macOS's own "Keep these display settings?". Other display changes wait until then. Night Shift
  uses `remoteSystem(.nightShift)`. An older Mac drops every Displays message; the phone says so
  after four seconds without a state. Tests: `DisplayGeometryTests`, `WindowPlanTests`,
  `DisplaysProtocolTests`, `DisplaysModeTests`, `ResolutionChoicesTests`.
  Checks on the Mac (Oct 2026): an arrangement must leave one piece of desk, no overlaps and
  every display sharing part of an edge with another, within 100,000 points
  (`DisplayGeometry.isReachableArrangement`), naming each display with its own picture once; a
  display that copies another cannot be copied (no mirroring loops or chains). `ArrangementTests`.
- `ControlMessage.macStatus(MacStatus)` (Oct 2026, additive), Mac -> phone, JSON
  `{"t":"macStatus","status":{"accessibilityTrusted":false,"automationMedia":"notDetermined","macName":"My MacBook Pro"}}`.
  `MacStatus` (`Protocol/MacStatus.swift`): `accessibilityTrusted: Bool` (required; when false the
  Mac drops every touch, so the pointer cannot move), `automationMedia: AutomationState?`
  (`granted`, `denied`, `notDetermined`, `notNeeded`; Spotify and Music control, optional) and
  `macName: String?`, plus `followsAllPanes: Bool?` (the Mac follows every pane of a layout from
  `modesShown`, so the phone stops polling) and `screenLocked: Bool?` (the Mac's screen is
  locked). The Mac sends it right after each handshake and again whenever a field
  changes (`GlasspadMacCore` `MacStatusReporter`). Accessibility is re-read every second both
  ways (`AccessibilityMonitor`) while a phone is connected or a pairing code is up, so turning
  it off in System Settings while connected reaches the phone within a second; with no phone
  and no code it is read every 5 seconds. Unknown fields and unknown `automationMedia` values are ignored.
- `ControlMessage.phoneStatus(PhoneStatus)` (Oct 2026, additive), phone -> Mac, JSON
  `{"t":"phoneStatus","status":{"batteryPercent":42,"charging":false}}`. Sent after connecting
  and whenever a field changes, so the Mac shows the iPhone's battery on its row. Every field is
  optional; a value out of range reads as unknown. A Mac without it reads `.unknown` and ignores it.
- `ControlMessage.unknown(type:)`: a `t` this build does not know decodes to this no-op instead
  of throwing, and both ends ignore it without ending the session (a known `t` with broken
  fields still throws and counts as malformed). Builds from before this change dropped any
  frame that failed to decode and kept the session, so they ignore `macStatus` too. The
  transport's own `{"t":"wake"}` frame now arrives as `.unknown("wake")` and is handled inside
  `GlasspadClient` as before. Tests: `ProtocolTests` (`macStatus*`, `buildsWithoutMacStatusIgnoreIt`,
  `unknownTypesDecodeAsNoOpButBrokenMessagesThrow`), `ConnectivityTests.macStatusArrivesAndUnknownTypesKeepTheSession`.
- Measured touch-path latency on loopback (encode + seal + UDP send + receive + open + decode +
  delegate hop), `ConnectivityTests.loopbackTouchLatency`: p50 about 0.1 to 0.2 ms, p95 about
  0.2 to 0.4 ms on an M-series Mac. Wi-Fi adds its own air time on top.

## 6. Gestures (GlasspadKit/Gestures)

The recognizer runs on the Mac (source of truth for events) and the same code
runs on the phone, fed by local touches, only to trigger haptics instantly.

```swift
public struct TrackpadSettings: Codable, Equatable, Sendable {
  public var trackingSpeed: Double        // com.apple.trackpad.scaling, 0...3
  public var naturalScrolling: Bool       // com.apple.swipescrolldirection
  public var tapToClick: Bool             // Clicking
  public var secondaryClick: SecondaryClick   // twoFinger | bottomRight | bottomLeft | off
  public var threeFingerDrag: Bool        // TrackpadThreeFingerDrag
  public var lookUp: LookUp               // forceClick | threeFingerTap | off
  public var scrollMomentum: Bool
  public var pinchToZoom: Bool, rotate: Bool, smartZoom: Bool
  public var swipeBetweenPages: SwipePages    // twoFinger | threeFinger | twoOrThree | off
  public var swipeBetweenSpaces: FingerCount  // three | four | off
  public var missionControl: FingerCount, appExpose: FingerCount
  public var launchpadPinch: Bool, showDesktopSpread: Bool
  public var notificationCenterEdge: Bool
  public var clickPressure: ClickPressure     // light | medium | firm (FirstClickThreshold 0/1/2)
  public var hapticStrength: Double           // phone-side, 0...1
  public static let macDefault: TrackpadSettings
}
public enum GestureEvent: Equatable, Sendable {
  case move(dx: Double, dy: Double)                       // Mac points, accelerated
  case button(MouseButton, down: Bool, clickCount: Int)   // left/right/middle
  case drag(dx: Double, dy: Double)                       // move while left is down
  case scroll(dx: Double, dy: Double, phase: ScrollPhase, momentum: MomentumPhase)
  case magnify(delta: Double, phase: GesturePhase)
  case rotate(degrees: Double, phase: GesturePhase)
  case smartMagnify
  case swipe(SwipeKind, progress: Double, phase: GesturePhase)  // fluid, follows fingers
  case navigate(back: Bool)                               // swipe between pages
  case forceClick(stage: Int)                             // 1 = start, 2 = deep
  case lookUp
  case notificationCenter
}
public final class GestureRecognizer {
  public init(settings: TrackpadSettings)
  public var settings: TrackpadSettings
  public func process(_ frame: TouchFrame) -> [GestureEvent]
  public func tick(now: TimeInterval) -> [GestureEvent]   // momentum, tap timeouts
  public var onHaptic: ((HapticKind) -> Void)?
}
public enum SwipeKind: Sendable { case spaces, missionControl, appExpose, launchpad, showDesktop }
```

Behavior notes:
- iPhones have no pressure sensor, so: tap = click (always on, even if the
  Mac has tap to click off, because a phone cannot be pressed down; show this
  in Settings). Press and hold still for 450 ms = force click (haptic ramp at
  stage 1, sharp tick at stage 2). One finger touch, then drag = click-drag
  (tap then touch again within 250 ms and move = drag, like tap-drag on Mac).
- Pointer acceleration: synthetic events are not accelerated by macOS, so the
  recognizer applies a curve that approximates the Mac's for the user's
  tracking speed. Phone points convert to Mac points with a gain tuned so a
  full-width swipe on the phone covers about 60% of the main display.
- Scroll: two fingers, pixel deltas, phases began/changed/ended; after lift,
  momentum with exponential decay (match macOS feel: ~0.95 per 8 ms frame),
  stopped by a new touch. Respect natural scrolling.
- Swipes: classify finger count at gesture start, lock axis after 12 pt,
  then emit continuous `progress` so Spaces and Mission Control follow fingers.
- Every threshold is a named constant in one file (`GestureTuning.swift`).
- Fully unit tested with scripted touch sequences.

As built (GlasspadKit), additions to the API above:
```swift
public enum MouseButton { case left, right, middle }
public enum GesturePhase { case began, changed, ended, cancelled }
public enum ScrollPhase { case none, began, changed, ended, cancelled }   // none on momentum events
public enum MomentumPhase { case none, began, changed, ended }
// GestureRecognizer
public func process(_ frame: TouchFrame, receivedAt localTime: TimeInterval) -> [GestureEvent]
public func cancelAll() -> [GestureEvent]     // call on disconnect: releases buttons, cancels everything
public var needsTick: Bool                    // call tick(now:) about every 8 ms while true
public var isLeftButtonDown: Bool
public var displayWidth: Double               // main display width in Mac points (pointer gain)
public var staleTouchTimeout: TimeInterval?   // 0.5 s; set nil on the phone
public var clock: () -> TimeInterval          // caller's clock, default systemUptime
```
- Clocks: `tick(now:)` takes the caller's own clock (the Mac's `systemUptime`).
  The recognizer learns the phone-to-Mac clock offset from frame arrivals.
- Conventions: `move`/`drag` in Mac points, +y down. `scroll` uses CGEvent pixel
  signs (positive dy = wheel up, content moves down) with natural scrolling
  already applied. `rotate` positive = counterclockwise. `swipe.progress` is
  cumulative from `began`, 1.0 = one full transition; positive = fingers left
  (spaces), up (missionControl), down (appExpose), pinch in (launchpad),
  spread out (showDesktop). Reversing gives negative progress; with App Exposé
  off a downward swipe drives `missionControl` negative.
- Force click: at 450 ms still, the left button goes down, then `forceClick(1)`;
  250 ms later `forceClick(2)`. Moving after stage 1 becomes a drag. When
  `lookUp == .forceClick`, stage 2 is the Look Up trigger (synth chooses native
  pressure events or the ctrl+cmd+D fallback); `.lookUp` is only emitted for
  `lookUp == .threeFingerTap`.
- Two-finger tap waits 250 ms for a possible second tap when smart zoom is on
  (right click after the wait, `smartMagnify` instead if the second tap comes).
- Two-finger swipe between pages arrives as horizontal phased scroll; three
  fingers emit `navigate(back:)` once past 50 pt.
- Never a stuck button: when no finger is down, the left button is up. Lifts,
  `cancelled` touches, a silent link (`staleTouchTimeout`), a phone clock restart
  and `cancelAll()` all release it.

As built, feel pass (Oct 2026):
- Pointer acceleration is the Mac's own, in physical units (`Gestures/MacAcceleration.swift`).
  It re-implements IOHIDFamily's parametric curve (`IOHIDParametricAcceleration`) and
  `IOHIDPointerAccelerator`: speed is counts per 120 Hz report at 400 counts per inch (floored),
  standardized by 400/67, run through the curve for `trackingSpeed` (the `HIDAccelCurves` table,
  blended between entries), and one inch moves the pointer `96 * f(v) / v` points. Curves,
  resolution and report rate were read from the reference MacBook Pro's IORegistry. Phone
  points become inches with `phonePointsPerInch` (153.3: 460 ppi at 3x). Finger speed is the
  frame's travel over max(dt, 1/120 s). `displayWidth` no longer affects gain.
- Scroll uses the same formula on `HIDScrollAccelCurves` at `TrackpadSettings.scrollSpeed`
  (`com.apple.trackpad.scrolling`, default 0.3125), times `GestureTuning.scrollCalibration`
  (1.5, the main scroll knob). Momentum decays at 0.998 per ms (time constant about 0.5 s).
- `TrackpadSettings.scrollSpeed` and `TrackpadSettings.tuning: TrackpadTuning` are new and
  optional on the wire (older peers decode). `TrackpadTuning` (phone-owned): `pointerSpeed`
  (multiplier, 1 = match Mac), `acceleration` (`.mac`, `.linear` = Mac gain at 2 in/s, `.off` =
  96 pt per inch), `scrollSpeed`, `momentumStrength` (0 = none, rate 0.998^(1/s) per ms),
  `clickHaptic`, `forceClickHaptic`, `dragLockHaptic`. The phone sends it inside
  `ControlMessage.settings` (phone -> Mac); the Mac keeps only `tuning` from it, stores it, and
  echoes the merged settings. `GestureRecognizer.pointerGain(speed:settings:)` is public for the
  settings preview.
- Haptics: only clicks (tap, two-finger click, corner click, three-finger Look Up tap), force
  click stages, and drag lock (new `HapticKind.dragLock`, when a tap-drag picks something up).
  Spaces, Mission Control, swipes, page swipes, the edge swipe and scroll never buzz, and the
  Mac no longer sends `.haptic(.snap)`.
- The phone-to-Mac clock offset is the fastest frame's delay, allowed to creep up at 200 ppm
  (`clockOffsetCreep`) so drift between the clocks never leaves it stale.
  `learnedClockOffset` exposes it.

As built, precision pass (Oct 2026). Thresholds are in `GestureTuning` in millimetres of finger
travel (`points(mm:)`, 6.04 pt per mm):
- Touch-down hold: while a touch can still be a tap, no pointer motion until the finger is 1 mm
  from where it landed (after `tapMaxDuration`, `pointerStartSlop`). Released motion is fed out
  over 40 ms on top of live motion (no jump, nothing lost). A tap undoes any motion it posted
  before clicking, so every tap clicks at the touch-down pointer position.
- Lift-off roll: a contact radius 15% (and 0.4 mm) under its 100 ms peak plus a speed spike
  (2.5x the slowest recent frame) holds motion until 1.5 mm from where the peel began or 80 ms;
  a lift discards it. A lift within 80 ms of leaving a rest (0.25 mm for 60 ms) takes back what
  was posted since the rest, which covers rolls the radius did not show.
- Fingers: a lifting finger's last delta is left out while others stay; with several fingers
  the pointer follows the settled, non-lifting finger that moves most; a landing finger drops
  held and pending motion; pointing resumes after an extra finger leaves without a gesture.
- Force-click drags and tap-drags press before any motion and feed their start travel out the
  same way. Display-synced output adds no extra lag at move start (`PrecisionPipelineTests`).

## 7. Mac event synthesis (GlasspadMacCore/Synth)

- Pointer, clicks, drags: `CGEvent` mouse events with delta fields set, click
  state for double and triple clicks, clamped to the union of display bounds.
- Scroll: `CGEvent(scrollWheelEvent2Source:units: .pixel ...)` with
  `scrollWheelEventIsContinuous = 1`, scroll phase and momentum phase fields,
  so apps get native rubber-banding and momentum.
- Real gestures via private CGS event fields (event type 29 "gesture" and the
  dock-control type), the technique used by open-source apps such as Mac Mouse
  Fix. Implement from first principles and document every field; do not copy
  code from projects with incompatible licenses. Covers: magnify, rotate,
  smart magnify, dock swipes (Spaces horizontal, Mission Control / App Exposé
  vertical, Launchpad pinch, Show Desktop spread), navigate swipes.
- `SynthCapabilities.selfCheck()` at launch: if a private event type cannot be
  created, switch that gesture to its fallback and say so in the menu.
  Fallbacks: Spaces = ctrl+left/right, Mission Control = ctrl+up,
  App Exposé = ctrl+down, Launchpad/Show Desktop = their shortcuts or
  NSWorkspace, magnify = cmd+scroll, Look Up = ctrl+cmd+D.
- Requires Accessibility permission. Check with `AXIsProcessTrustedWithOptions`.
- Tests must never post events into the live session. Test by building events
  and asserting their fields. A separate opt-in `--live-demo` flag can post.

As built, feel pass (Oct 2026): display-synced output.
- Before, every packet was posted the moment it arrived, so Wi-Fi bunching became pointer
  jitter and a 120 Hz display got 0, 1 or 3 updates per frame. Now `TouchPipeline` (with a
  `FrameClock`; the app uses `DisplayFrameClock`, `NSScreen.displayLink` at the screen's real
  rate, 120 Hz on ProMotion, timer fallback) puts every recognizer event on the phone's timeline
  in `Synth/MotionScheduler.swift` and releases it at display frames: at most one move, drag
  and scroll event per frame, motion spread evenly over the sample interval after its sample,
  discrete events kept in order. Delay `D` = 90th percentile of frame lateness, capped at 35 ms,
  moving at most 4% (up) or 1% (down) of real time, so a bursty link raises it within a second
  and a clean one brings it back to 1 to 3 ms; added latency is `D` plus about half a sample
  interval. Recognizer ticks (momentum, hold timers) run once per display frame on the same
  delayed timeline. If the display stops calling back for 50 ms, events post at once. The clock
  stops after about half a second idle. Without a frame clock (tests) the old immediate path is
  used.
- As built, gap pass (Oct 2026): macOS hops the Wi-Fi radio to AWDL for system services, so
  frames stop for 70 to 200 ms mid-move and then arrive in a burst or not at all. The scheduler
  now hides that. `GestureRecognizer.continuingMotion` says which stream (move, drag, scroll)
  may be carried on; it is nil in a tap or roll hold, while held motion is fed out, while a
  contact peels off, in a force-click hold, a pinch or a swipe, and after a lift. With a stream
  continuing and 15 ms of silence past the last frame, the stream goes on at its recent velocity
  (40 ms estimate, lowered by the last 17 ms so a slowing finger is not carried on), held for
  30 ms then decaying (80 ms), for at most 140 ms and a soft cap of 80 pt (160 scroll px). The
  next real frame ends it; real travel minus predicted travel is fed out over a few display
  frames (20 ms time constant, adding at most the stream's own speed plus 150 pt/s), never a jump.
  Motion that reaches the playhead more than half a display frame late (a burst, or the
  snapshot that carries a whole gap) goes out the same way. A drag's owed motion always goes out
  before its button-up. Swipe progress is never extrapolated; its late part eases in the same
  way. A finger that stops is confirmed by the phone's 20 ms resend, so a hard stop overshoots
  by at most about 5 ms of travel, taken back smoothly. The recognizer's speed clamp
  (`maxFrameInterval`) is now 200 ms, so the snapshot after a gap is not mistaken for a fast
  flick by the acceleration curve. The phone sends each frame once on the WMM voice queue; a
  duplicate 2 ms later was rejected because losses come in runs longer than that.
- `TouchDiagnostics` logs one line per second while frames flow:
  `feel: N fps, gap p50/p95/max, lost, late p50/p95/max, buffer, predicted ms, fixes N max E,
  smoothed U, display Hz, out/s` (`predicted`: playhead time bridged by prediction; `fixes`:
  predictions reconciled with real frames and the largest error in points or scroll pixels;
  `smoothed`: late motion fed out gradually).
  Read it with `/usr/bin/log show --predicate 'subsystem == "com.soham109.glasspad"'`.

## 8. Modes

All modes are minimal: same background, SF Symbols, one accent color.
Each mode is a `ModeMessage` case pair handled by `GlasspadMacCore/Modes`.

| Mode | Phone | Mac side |
|---|---|---|
| Trackpad | full-screen surface, finger dots | gesture engine + synth |
| Dock | the Mac's Dock and nothing else: Dock apps + running apps in Dock order, running dots, long-press Quit / Hide / Show in Finder / Keep, phone-side order and hiding. Apps outside the Dock are pinned in Actions | read Dock prefs + NSWorkspace, icons as 384 px PNG (3x the largest icon the phone draws) keyed by bundle id + app modification date + size, sent once (`dockSync`), in messages of at most 1.5 MB of icons, launch / activate / reopen (`AppLauncher`), hide the Mac Dock (`MacDockHider`) |
| Keyboard (stored as `keys`) | text field that streams typed text; arrows, esc, tab, cmd shortcuts row, modifier keys, F1 to F12; dictation works | CGEvent keyboard unicode strings; shortcuts press the key that types that character on the Mac's keyboard layout (`KeyLayout`) |
| Media | now playing title/artist/art, play/pause/next/prev, scrubbing, shuffle and repeat, sound output, volume, brightness | MediaRemote through `Apps/Mac/Helpers/NowPlayingHelper.m` (since macOS 15.4 MediaRemote answers only Apple processes, so the helper runs inside `/usr/bin/perl`), AppleScript to Spotify and Music, media key events for commands, volume via CoreAudio |
| Actions (Deck) | one screen: the front app's best buttons (6 by default, up to 8 chosen and ordered per app) above Pinned (favorites of every kind, + opens a searchable Library whose Apps group lists every installed Mac app); folders, sizes, colors, edit on the phone. Sideways it splits: front app on the left half, Pinned on the right. Present is a tool in the mode menu; Clipboard opens from Keyboard's shortcut row or a Pinned button. Older Decks move into Pinned once, losslessly (`PinnedDeck.migrated`) | executes actions directly (screencapture, pmset, CoreAudio...), config v3 on the Mac, phone edits via `deckSave` (never shell) |
| Macros | the Mac's macros, the set for the app in front, record on the Mac | GlasspadMacros (docs/SPEC-macros.md) |
| Clipboard | send phone clipboard to Mac, pull Mac clipboard to phone (text, images) | NSPasteboard |
| Present | big next/previous buttons, timer, laser dot (move a highlight on the Mac) | arrow keys + transparent overlay window for the laser |
| Remote | couch remote: touch surface (tap play or pause, swipe sideways to skip, up and down for volume), back 10 / play / forward 10, Search, Subtitles, Full Screen, Mute, Sleep Display and Do Not Disturb. Keys follow the player in front (`RemoteKeymap`: web players, with YouTube, Netflix, Prime Video and Disney+ told apart, Apple TV, QuickTime, IINA, VLC, Infuse, Spotify and Music); Skip Intro shows for Netflix. Hidden at first: a tool in the mode menu until Settings shows it | media commands and seeking through now playing, keystrokes, CoreAudio volume |
| Displays | the Mac's displays drawn as in System Settings (true sizes and places, menu bar and camera housing on the main one) with every window in front to back order and its app icon, plus a window list. Tap brings a window forward, drag moves it (to another display keeping its share), touch and hold for Left, Right, Top and Bottom Half, Fill, Center, Split With (the Split Screen sheet), Move to a display, Full Screen, Minimize and Close (asks first). Tap a display for brightness, the "Looks like" resolutions, Night Shift, main display, mirroring and Arrange Displays. Hidden at first: a tool in the mode menu until Settings shows it | window server list for order and frames, Accessibility for names and moves, CoreGraphics display configuration with Keep or Revert, DisplayServices brightness |
| StandBy (Clock, Now Playing, Calendar) | glanceable screens like iOS StandBy, hidden at first, used as layout panes (templates StandBy and Clock and Trackpad). Clock: Digital, Analog and Minimal faces (tap to change), 12 or 24 hour as the phone is set, date and charge level. Now Playing: cover, title, artist, back, play or pause, next (MediaStore). Calendar: the next three events from EventKit, asked for only after a tap. Always black, content shifts up to 3 pt each minute against burn in, night mode turns everything dim red (Off, At Night 22:00 to 07:00, Always), dims in Low Power Mode and when warm. Keeps the screen on only while visible and charging, or on battery when Stay On When Unplugged is on and Low Power Mode is off, and never while the phone is warm (thermal state serious or worse, `PowerPolicy.isWarm`) (rules in GlasspadKit `StandBy.swift`) | Now Playing reports `media` (now playing stream); Clock and Calendar report `trackpad` and need nothing from the Mac |

As built, UX pass (Oct 2026):
- The mode once called Apps is called Dock again (SF Symbol `dock.rectangle`), and mirrors the
  Mac's Dock only: no search and no Recent row. Its stored identifier is still `dock`, so saved
  mode lists, launch mode and deep links (`glasspad://mode/dock`) keep working. Search over every
  installed app moved to Actions > + > Apps > All Apps on Your Mac.
- A new Deck (no `deck.json` yet) starts with one Pinned page of six essentials
  (`PinnedDeck.essentials()`: Screenshot, Do Not Disturb, Split Screen, Lock Screen, Mute, Dark
  Mode); the other Mac controls are in the Library. Migration pins every macro only for a
  layout from before Actions (it has the Mac page or no Pinned page). Existing Pinned pages are
  never trimmed on their own: over 12 tiles, Actions offers Tidy Up once, and edit mode has
  Reset to Defaults (`PinnedDeck.resetPinned`), both behind a confirmation.
- Split Screen on the phone opens a sheet first: the display in miniature with the front window
  on the left half and the one behind it on the right. Tap a half for another window, swap them,
  pick the display, then Split; a line names what happened ("Safari and Notes, side by side on
  Studio Display."). It sends the Displays commands (`move` when the left window is on another
  display, then `split(with:)`). A Mac that never answers `displaysWatch` gets the one tap
  button instead. On the Mac, Split moves the second window onto the first one's display before
  sizing it, reads each move back until it lands, lets a window with a minimum width keep it, and
  names the app and what to do when it cannot.
- Mac controls with no public API: Do Not Disturb presses the switch in Control Center (or the
  Focus menu) through Accessibility, by its stable identifiers, and falls back to a shortcut the
  user already has ("Toggle Do Not Disturb", "Do Not Disturb", "Toggle Focus"); Night Shift uses
  CoreBrightness `CBBlueLightClient`; Keep Awake holds a display sleep power assertion; window
  tiling sets the front window's frame with Accessibility inside the screen's visible frame (with
  the 8 pt gap when "Tiled windows have margins" is on), falling back to the app's Window > Move &
  Resize item. Switches send their new state as the `deckResult` message ("Do Not Disturb is on").
- Starter buttons per app (`StarterLibrary`, version 2) can be keystrokes or Mac controls
  (`MacroStep.macControl`). A Mac with older starters is upgraded once (`StarterSeeder.upgrade`):
  untouched starters update, edited ones stay, deleted ones stay deleted, new apps get profiles.

- Tile grids (Actions, Pinned, folders, the Library's Pinned preview, Dock) size themselves from
  the space they get, not the screen (`TileGridMetrics`, `BalancedRows` in GlasspadKit): tiles near
  the preferred size and never under 44 pt, rows that differ by at most one (7 is 4 + 3, 6 is
  3 + 3), every row centered. Mac controls in the Library come from `DeckSystemCatalog`, grouped.
- Website buttons show the site's own logo: the phone reads the page's icon links, then
  `/apple-touch-icon.png` and `/favicon.ico`, keeps the largest, caches it by host, and falls back
  to the site's first letter. It asks the site only (no favicon services). A new Website button is
  named after the site. Every fetch and redirect goes through `SiteFetch`: https only, never a
  device on the local network or a numeric address unless the typed link is that device, the
  page read to 400 KB and an image to 3 MB (counted after decompression). A logo frame over
  4096 × 4096 pixels is never decoded (`LogoImage.thumbnail`). `SiteFetchTests`.
- Deck safety on the Mac: Open File refuses what runs when opened (scripts such as `.command`,
  programs, installers, Automator, Terminal and link files, following symbolic links;
  `DeckMode.runsWhenOpened`), Open URL refuses `file`, `x-man-page` and `help` links, and the log
  names only the kind of action. A clipboard image from the phone over 100 million pixels is
  refused before it is decoded. A phone forgotten during its handshake is closed before it
  becomes active (`TransportTests.phoneRevokedMidHandshakeNeverConnects`).

## 9. iPhone app (Apps/iOS)

- SwiftUI app shell; the trackpad surface is a UIKit `UIView` subclass for
  raw touches: `isMultipleTouchEnabled`, uses `coalescedTouches(for:)` and
  sends every sample immediately (no batching to display frames).
  As built (feel pass): `CADisableMinimumFrameDurationOnPhone` is set, so touches arrive at
  120 Hz on ProMotion. Coalesced samples update finger positions in order, but the surface
  sends one frame per touch callback (newest positions, newest timestamp), plus one at the
  moment a finger lifts. Sending every sample per finger had produced 430 to 700 packets a
  second. It logs `touch rate: ... callbacks (/s), samples (/s), frames sent (/s)` per touch.
- Hides the status bar and home indicator, defers system edge gestures
  (SwiftUI `defersSystemGestures(on: .all)` while a trackpad shows, alone or in a layout pane).
- Mode switching: a small pill at the top center (or the bottom, in Settings) that fades out
  after 2 s, revealed by touching the edge it sits on. Tap it for the mode menu, long press it
  for Settings, swipe it sideways to flip back to the mode or layout before (again to return;
  a light tap is felt; VoiceOver action "Previous Mode"). As built (Oct 2026): the pill and the
  menu are one piece of glass (on iOS 26 the pill grows into the menu); the menu lists the
  modes, the tools (Present, Remote, Displays unless shown as modes) and a Layouts row with +
  for a new layout. Clipboard opens from the last chip of Keyboard's shortcut row, from a
  Pinned button (Library, `glasspad://mode/clipboard`, opened on the phone, never sent to the
  Mac), from Shortcuts, or as a mode when Actions is split. A small dot on the pill shows the
  connection only when something is wrong.
- Haptics: Core Haptics (`CHHapticEngine`) pre-warmed; transient events for
  click, force click ramp, detents. Strength follows Mac click pressure and
  the phone-side slider.
- Phone safety: `isIdleTimerDisabled` only while the surface is visible;
  dims the surface after 60 s idle (Settings: 30 s, 1, 2 or 5 minutes, or never); on
  `thermalState >= .serious` it stops haptics and heartbeats and shows a calm notice; no
  brightness changes.
  As built (Oct 2026): one `PowerPolicy` (GlasspadKit `Power/PowerPolicy.swift`), fed by the
  app's `PowerMonitor` with the thermal state and Low Power Mode, decides every extra. Warm
  (`isWarm`, serious or worse): no haptics, no heartbeats, no decorative motion, progress
  redraws once a second. Low Power Mode or fair heat: decorative motion at 30 frames a second.
  Low Power Mode also: one marquee pass instead of three, progress redraws once a second, and
  heartbeats stop after 10 s idle. Keep Screen On holds the screen only for the trackpad or Present, with the app active,
  nothing on top, a Mac connected, and less than `keepAwakeLimit` since the last touch (10
  minutes; 3 in Low Power Mode or warm; 1 when critical). Pointer traffic, click haptics and
  taps are never slowed. The haptic engine rests while dimmed or in the background. Tests:
  `PowerPolicyTests`.
  Memory and storage (Oct 2026): only the theme on screen and the one before it keep their
  full-size glass backdrop or photo in memory (`RecentKeys`, about 5 MB each), so trying every
  theme keeps no more than four. Covers are written to disk off the main thread and stay
  within 40 files and 30 MB (`DiskCacheLimit`). Debug builds measure it:
  `-GPTour [rounds]` visits every mode, tool, sheet, layout and theme and comes back, and
  `-GPLaunchClock` prints the time to the first frame. Tests: `RecentKeysTests`,
  `DiskCacheLimitTests`.
- Pairing: camera QR scan (`AVCaptureVideoDataOutput` frames read with Vision through
  `PairingCodeReader`, section 3), or a pasted `glasspad://pair` link; Keychain storage
  (this device only).
- Themes: Paper (#F2F1EE background, dots #1A1A1A at 14% opacity) and
  Graphite (#141414, dots white at 18%). Dots 44 pt, soft edge, fade on lift.
  As built (Oct 2026): also System (Paper or Graphite with the phone), Mono (pure white or black
  with the phone, no color anywhere: accents, tiles and icons draw in the ink), Sand (warm light)
  and Midnight (deep blue dark). Settings shows a live miniature of each.
  Themes (Oct 2026): 27 themes plus Photo, in groups on Settings > Theme. Classic: System, Paper,
  Graphite, Mono, Pure Black (true black for OLED), High Contrast (text at 7:1 or more). Glass
  (frosted cards over a soft backdrop of color pools): Glass, Glass Dark, Clear, Aurora, Ocean,
  Dusk, Rose, Mint, Lavender, Ember, Citrus, Smoke. Color: Sand, Midnight, Forest, Plum, Slate,
  Espresso, Solar, Frost, Dawn. Photo blurs a picked photo (PhotosPicker, no permission prompt)
  into the backdrop and veils it just enough for text to read (`PhotoTone`). Every theme defines
  every color (GlasspadKit `ThemeCatalog`), including its own accent (app tint, Trackpad's mode
  color); a test checks text, secondary text, accent, button labels and status colors reach
  WCAG AA on every surface. Mode accents and status colors are Apple's system colors, moved
  toward the ink only as far as a theme needs for 3:1. Unknown saved themes fall back to System.
  Remote and StandBy stay dark.
  Grain and Tinted (Oct 2026): 38 themes plus Photo. Grain: Grain (warm paper), Grain Dark
  (charcoal), Risograph (pink stock, riso blue), Film (teal shadows, warm highlights), each with a
  still grain from a fixed seed drawn once at the screen's pixel density. Tinted: Mono Blue, Green,
  Rose, Amber, Violet, Slate, light and dark with the phone, and Custom Tint (a color picker on
  the Theme page). One hue for everything: surface, cards, text, accents, mode colors, and app
  icons and website logos, recolored along the hue by their brightness like the tinted Home
  Screen. Status colors in the tinted themes work as in Mono. Remote uses the tinted dark colors.
  `scripts/web-themes.sh` regenerates the website's theme list from the catalog.
- Layouts (Oct 2026): one to three modes on one screen (GlasspadKit `Layouts/`, views in
  `Apps/iOS/Sources/Layouts`). `ScreenLayout` keeps panes by mode name (unknown names
  survive), a direction (`automatic`: side by side in landscape, stacked upright; or fixed),
  the main split and, with three panes, the inner split of the second side. A mode never
  shows twice: putting it in a second pane swaps the two. Dividers (`DividerMath`) rest on a
  third, the middle or two thirds within 22 pt, resist past a 120 pt minimum pane, and fold a
  pane away when pulled 56 pt further; double tap a line for even shares. A new install has
  Desk, Type, Listen and Couch (`LayoutLibrary.starter`); the gallery adds Trackpad and Dock,
  Media and Actions, Studio, Presenter, StandBy, and Clock and Trackpad. Layouts sit in the
  mode menu and are edited on the phone (name, panes, Swap Panes, Split direction). What the Mac is told
  is `LayoutWirePlan` (section 5). Views shown in several panes count with `ShownCount`, so
  one pane leaving never switches off the trackpad or diagnostics of another. Tests:
  `ScreenLayoutTests`, `ShownCountTests`.

## 10. Mac app (Apps/Mac)

- Menu bar only (`LSUIElement`). Popover: connection state + RTT, pair button
  (QR), permissions checklist, which gestures are native vs fallback,
  paired phones (revoke), launch at login (`SMAppService`).
- Settings sync: watches the trackpad preference domains and pushes changes (notifications,
  plus a read every 2 s while a phone is connected and every 5 s otherwise).

As built (Oct 2026 UX pass):
- First launch with no phone paired opens a Welcome window (`SetupViews.swift`) with the code
  already showing, three steps, and the permissions in order: Accessibility (Required), then
  Spotify and Music (Optional, "Ask" enabled only once Accessibility is allowed).
  As built (Oct 2026): a short assistant (welcome, permissions that tick themselves off as each
  is granted, then the living pairing code). The popover is laid out like the system's own
  menu bar extras: Glasspad with an on switch, the iPhone as a device row, anything that needs
  fixing, Pair Your iPhone…, Hide Mac Dock, then Glasspad Settings… and Quit Glasspad. Settings has General
  (Open at Login), iPhone (paired phones, Forget… to revoke), Trackpad, Macros, Advanced and
  About.
- Pairing states (`GlasspadMacCore` `PairingFlow`): waiting (code valid 5 minutes), Paired with
  the phone's name (closes itself after 2.5 s), Code Expired (Show a New Code), failed (Try
  Again). Copy Link and Share (AirDrop) sit under every code; the phone pastes the link with
  "Paste the Link Instead" or opens it as a `glasspad://pair` link.
- The Mac uses the phone's words: Trackpad, Keyboard, Media, Dock, Actions (Pinned, Library),
  Macros. Settings > Macros has "All Macros" and "For Each App" (the sets behind "For <app>" in
  Macros on the iPhone). The macro editor shows gestures, keys and apps by name, never as
  identifiers. Trackpad has "If a Gesture Stops Working": Automatic, Trackpad gesture or Keyboard
  shortcut per gesture, applied at once, with the path each gesture uses now under its name.
  As built (Oct 2026): the Diagnostics rows (round trip, packet counts, last clipboard refusal)
  left Settings; round trip shows as signal bars in the popover, and connection and touch
  diagnostics are in the log (`/usr/bin/log show --predicate 'subsystem == "com.soham109.glasspad"'`). Advanced keeps
  "Allow shell command buttons" and the Macros folder.

## 11. Definition of done

- `scripts/test.sh` green for every package and the installer tests.
- Mac app tests green (wording and pairing code render tests); the command is in
  [docs/testing.md](testing.md#mac-app-tests).
- Mac app builds into `build/Glasspad.app` with `scripts/build-mac.sh`.
- iOS app builds in Xcode once installed (project generated by XcodeGen).
- A loopback test: `GlasspadClient` (macOS) pairs with `GlasspadServer` in one
  process, sends touch frames, server receives decoded frames.
