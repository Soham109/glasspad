# Glasspad: build spec

Glasspad turns an iPhone into a wireless Mac trackpad with haptics, plus a set of
extra modes (Dock, Keys, Media, Deck, Clipboard, Present). Open source, MIT.
This file is the contract every part is built against. If you change an
interface here, change it everywhere.

## 1. Principles

- Feels like the Mac's own trackpad. Gestures follow the user's real macOS
  trackpad settings, read live from `defaults`.
- Lowest possible latency over Wi-Fi. Measure it, never guess it.
- Minimal UI. The trackpad screen is a plain soft-white (or graphite) surface
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
      Protocol/                  wire messages + binary codec
      Crypto/                    pairing payload, session keys, AEAD framing
      Transport/                 Bonjour discovery, TCP control, UDP touch link
      Gestures/                  touch model, TrackpadSettings, GestureRecognizer
    Tests/GlasspadKitTests/
  Packages/GlasspadMacCore/      Mac-only logic as a package (macOS 14+)
    Sources/GlasspadMacCore/
      Settings/                  reads macOS trackpad prefs -> TrackpadSettings
      Synth/                     CGEvent pointer/click/scroll + private gestures
      Server/                    NWListener, pairing store, session handling
      Modes/                     Dock, Media, Keys, Deck, Clipboard, Present
    Tests/GlasspadMacCoreTests/
  Apps/Mac/                      menu bar app (SwiftUI + AppKit), thin shell
  Apps/iOS/                      iPhone app (SwiftUI + UIKit touch view), thin shell
  project.yml                    XcodeGen project for both apps
  scripts/                       test.sh, build-mac.sh (SwiftPM + ad-hoc .app)
  docs/                          SPEC, ARCHITECTURE, screenshots, site
```

Build without Xcode (Mac side only): `scripts/test.sh` and `scripts/build-mac.sh`.
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
- Wrong key or bad tag: drop silently, count it, surface in the Mac debug view.

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
  enters power save. Stops when the screen is hidden or the phone is idle 2 min.
- RTT: Mac sends `ping` on TCP each second, phone answers `pong` with the
  same id; Mac shows median and p95 RTT in its debug view.
- Reconnect automatically with backoff (0.2, 0.5, 1, 2 s cap).

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
  `serverSilenceTimeout` (6 s) without hearing from the phone.
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
}
public enum HapticKind: String, Codable, Sendable { case click, forceClick, detent, snap, error }
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
  `GlasspadMode.macros` exists for `modeSelected(.macros)`, which makes the Mac send `macroList`.
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

Behaviour notes:
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
  discrete events kept in order. Delay `D` = 90th percentile of frame lateness (eased, capped
  at one display frame); added latency is `D` plus about half a sample interval. Recognizer
  ticks (momentum, hold timers) run once per display frame on the same delayed timeline. If
  the display stops calling back for 50 ms, events post at once. The clock stops after about
  half a second idle. Without a frame clock (tests) the old immediate path is used.
- `TouchDiagnostics` logs one line per second while frames flow:
  `feel: N fps, gap p50/p95/max, lost, late p50/p95/max, buffer, display Hz, out/s`.
  Read it with `/usr/bin/log show --predicate 'subsystem == "com.soham109.glasspad"'`.

## 8. Modes

All modes are minimal: same background, SF Symbols, one accent color.
Each mode is a `ModeMessage` case pair handled by `GlasspadMacCore/Modes`.

| Mode | Phone | Mac side |
|---|---|---|
| Trackpad | full-screen surface, finger dots | gesture engine + synth |
| Apps (Dock) | grid of the Mac's Dock apps + running + recent apps, running dots, search, long-press Quit / Hide / Show in Finder / Keep, phone-side order and hiding | read Dock prefs + NSWorkspace, icons as 256 px PNG keyed by bundle id + app modification date, sent once (`dockSync`), launch / activate / reopen (`AppLauncher`), hide the Mac Dock (`MacDockHider`) |
| Keys | text field that streams typed text; arrows, esc, tab, cmd shortcuts row; dictation works | CGEvent keyboard unicode strings |
| Media | now playing title/artist/art, play/pause/next/prev, volume, brightness | MediaRemote (private, with fallback to media key events), volume via CoreAudio |
| Actions (Deck) | pages: front-app page (follows the Mac), Mac controls, My Buttons + macros, Clipboard, Present; folders, sizes, colours, edit on the phone | executes actions directly (screencapture, pmset, CoreAudio...), config v3 on the Mac, phone edits via `deckSave` (never shell) |
| Clipboard | send phone clipboard to Mac, pull Mac clipboard to phone (text, images) | NSPasteboard |
| Present | big next/previous buttons, timer, laser dot (move a highlight on the Mac) | arrow keys + transparent overlay window for the laser |

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
  (`preferredScreenEdgesDeferringSystemGestures = .all`).
- Mode switching: a small pill at the top centre that fades out after 2 s,
  revealed by touching the top 24 pt. Long press the pill for Settings.
- Haptics: Core Haptics (`CHHapticEngine`) pre-warmed; transient events for
  click, force click ramp, detents. Strength follows Mac click pressure and
  the phone-side slider.
- Phone safety: `isIdleTimerDisabled` only while the surface is visible;
  dims the surface after 60 s idle; on `thermalState >= .serious` it stops
  haptics and heartbeats and shows a calm notice; no brightness changes.
- Pairing: camera QR scan (`AVCaptureMetadataOutput`), Keychain storage.
- Themes: Paper (#F2F1EE background, dots #1A1A1A at 14% opacity) and
  Graphite (#141414, dots white at 18%). Dots 44 pt, soft edge, fade on lift.

## 10. Mac app (Apps/Mac)

- Menu bar only (`LSUIElement`). Popover: connection state + RTT, pair button
  (QR), permissions checklist, which gestures are native vs fallback,
  paired phones (revoke), launch at login (`SMAppService`).
- Settings sync: watches the trackpad preference domains and pushes changes.

## 11. Definition of done

- `scripts/test.sh` green for both packages.
- Mac app builds into `build/Glasspad.app` with `scripts/build-mac.sh`.
- iOS app builds in Xcode once installed (project generated by XcodeGen).
- A loopback test: `GlasspadClient` (macOS) pairs with `GlasspadServer` in one
  process, sends touch frames, server receives decoded frames.
