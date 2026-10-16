# Glasspad reliability and edge-case review

Read-only review, 15 Oct 2026, against commit `7d100b1`. The 14 bugs fixed in `ab7afff` and
`d331173` are not repeated. When this was written the working tree had uncommitted work (a new
`MacStatus` message, `ControlMessage.unknown`, script changes). Where that work touches a finding,
the finding says so.

How to read each entry:

- **Severity**: critical (can lose the user's work or do something destructive), high (a main
  feature breaks with no explanation), medium (degraded or confusing, has a workaround), low.
- **Confidence**: *confirmed* (the code path was traced end to end), *likely* (the code was traced
  and the result depends on documented or well-known macOS/iOS behaviour), *speculative* (depends on
  OS behaviour that needs a device test).
- **Effort**: S (under a day, local change), M (a few files plus tests), L (design change).
- **Viability**: whether the suggested fix is practical as written.

---

## Critical

### C1. Non-US keyboard layouts: shortcut buttons press the wrong keys (AZERTY "Undo" closes the window, "Select All" quits the app)

- **Scenario**: keyboard layouts. A Mac set to French AZERTY, German QWERTZ, Dvorak and similar.
- **What happens**: phone buttons send `Keystroke(.character("z"), [.command])` and so on
  (`Apps/iOS/Sources/Modes/ActionLibrary.swift:318-326`). The Mac turns the character into a key
  code with a fixed US ANSI table (`KeysMode.swift:48-69`, table at `:77-88`). A key code is a
  physical key position. macOS matches Command shortcuts against the character the active layout
  gives that key. On AZERTY, the US "a" position (code 0) types "q", and "z" (code 6) types "w".
  So "Select All" becomes Cmd+Q, "Undo" becomes Cmd+W, and "Close Window" (code 13) becomes Cmd+Z.
  On QWERTZ "Undo" becomes Cmd+Y. The same path serves Keys mode, Deck buttons
  (`LiveDeckEnvironment.swift:71`) and Actions.
- **User impact**: the front app quits or a browser tab closes when the user asked to select all
  or undo. A closed tab loses typed form input with no prompt.
- **Severity**: critical. **Confidence**: confirmed for the key-code mapping. The layout behaviour
  is standard macOS.
- **Fix**: the macros package already reads the active layout (`GlasspadMacros/System/KeyboardLayout.swift`,
  `KeyboardLayoutMap.current()`). Use it in `KeysMode.keyStroke(for:)` (character -> code on the
  current layout, US table only as a fallback). Cache it and refresh it on
  `kTISNotifySelectedKeyboardInputSourceChanged`. Add a test with an AZERTY map.
- **Effort**: S. **Viability**: high. The code already exists in the repo.

---

## High

### H1. A half-second Wi-Fi stall drops a drag at the wrong place, then the returning finger can click

- **Scenario**: dragging a file or window while AirDrop, Universal Control, Bluetooth audio or a
  mesh Wi-Fi handover stalls packets; phone in Low Power Mode; busy 2.4 GHz network.
- **What happens**: the phone resends a resting finger every 20 ms. The Mac's stale guard fires
  after 0.5 s with no frame (`GestureTuning.swift:162`, checked in `GestureRecognizer.tick`
  `:311-314`). It calls `cancelSession()`, which releases the left button (`:1046-1066`). The
  mouse-up lands wherever the pointer is. When packets come back, the same finger IDs are unknown
  to the recognizer, so Stage 3 adds them as a fresh touch-down with no check that the phase is
  `began` (`:280-291`, `handleAdd` `:800-816`). If the user lifts soon after, that is a tap, so a
  click lands at the drop point.
- **User impact**: a file dropped into the wrong folder or onto the Dock's Trash on the way. A
  window snapped somewhere unwanted. A stray click.
- **Severity**: high. **Confidence**: confirmed by trace. How often depends on the network.
- **Fix**: while dragging or holding, a stale stream should freeze: stop motion, keep the button
  down, and release only on a real disconnect (the server's 6 s silence close, or
  `linkStateChanged`). Re-adopt a returning finger whose phase is not `began` as the same touch,
  not a new one. Keep 0.5 s for pointing and scrolling, where releasing does no harm.
- **Effort**: M. **Viability**: high. Needs new GestureTests for "stall mid-drag, resume, lift".

### H2. Guest Wi-Fi, VPN or firewall: the phone finds the Mac but loops on "Connecting" forever

- **Scenario**: captive or guest Wi-Fi with client isolation but an mDNS gateway (common in hotels,
  campuses, offices); a full-tunnel VPN on the phone or the Mac with LAN access blocked; the Mac
  firewall blocking incoming connections.
- **What happens**: the AWDL fallback (AWDL is Apple's peer-to-peer Wi-Fi) only starts when the
  Bonjour browse finds nothing within 3 s (`GlasspadClient.swift:272-281`, the guard needs
  `self.browser != nil`). Here Bonjour does find the Mac, so the browser is cancelled and TCP opens
  (`:288-293`). The TCP connect then fails or waits (`Link.swift:197-200`) -> `lost` -> backoff ->
  browse again -> found again (`:404-421`). This repeats forever and never tries AWDL. The state
  only ever shows `searching`/`connecting`, with no reason.
- **User impact**: the trackpad never connects on exactly the networks where AWDL would have
  worked, and the user is not told why.
- **Severity**: high. **Confidence**: confirmed by trace.
- **Fix**: count consecutive TCP failures after a Bonjour hit. After 2, set `usePeerToPeer = true`
  for the next attempt. After 4, report `failed("Your Mac was found but this network does not let
  devices talk to each other (guest Wi-Fi, VPN or firewall)")`, and keep retrying in the
  background.
- **Effort**: S. **Viability**: high.

### H3. Local Network permission denied: stuck on "Looking for your Mac" with no hint

- **Scenario**: first pairing. The user taps "Don't Allow" on the iOS Local Network prompt, or
  turns it off later in Settings > Privacy > Local Network.
- **What happens**: a denied `NWBrowser` goes to `.waiting(PolicyDenied)`. The client only reacts
  to `.failed` (`GlasspadClient.swift:297-301`), so the state stays `searching` for good. No iOS
  source mentions Local Network (the only hit is the Info.plist usage string), and
  `GlasspadDiscovery.onFailure` (which does see `.waiting`) is never used by the app.
- **User impact**: the first-run experience fails silently. This is the most common reason a
  Bonjour app "can't find" a Mac.
- **Severity**: high. **Confidence**: confirmed by trace.
- **Fix**: in `browse()`, treat `.waiting` with a policy-denied DNS error as
  `failed("Local Network access is off")`. Show a button that opens `UIApplication.openSettingsURLString`.
  Also check this in onboarding before the QR scan.
- **Effort**: S. **Viability**: high.

### H4. Accessibility revoked while running (or not granted yet): the phone says Connected and nothing happens

- **Scenario**: Accessibility revoked while running. Also first pairing before the permission is
  granted, and every ad-hoc rebuild from `scripts/build-mac.sh` (the permission is tied to the
  code signature).
- **What happens**: `refreshStatus` re-checks `AXIsProcessTrusted()` only while it is already
  false (`GlasspadController.swift:207-210`). Once true, a revocation is never noticed, and
  `received(frame)` keeps feeding the pipeline (`:194-197`). macOS drops the posted events
  silently. If revoked mid-drag, the mouse-down already got through and the mouse-up does not, so
  the system can think the button is still held. When it is not trusted from the start, frames are
  dropped and the phone still shows Connected. The uncommitted `MacStatus.swift` adds a field for
  this, but nothing on the Mac sends it and the phone ignores it (`MacSession.swift:380`, working
  tree).
- **User impact**: a dead trackpad with no explanation on either screen.
- **Severity**: high. **Confidence**: confirmed by trace.
- **Fix**: check AX every status tick, unconditionally. On true -> false: run `pipeline.cancelAll()`
  first, show the menu-bar warning, and send `macStatus(accessibilityTrusted: false)`. The phone
  shows a banner over the trackpad.
- **Effort**: S. **Viability**: high. The protocol part is already being written.

### H5. A macOS update that changes private gesture events silently breaks Spaces, Mission Control and zoom

- **Scenario**: macOS update changing private gesture events.
- **What happens**: `SynthCapabilities.selfCheck()` only builds each private event and checks that
  its fields read back (`SynthCapabilities.swift:81-116`). It cannot tell whether the Dock or
  WindowServer still acts on them. If a future macOS ignores them or reads a field differently,
  the native path stays selected and gestures do nothing. If it reads the "began" event but not the
  end, the Dock is left mid-transition (the end reposts at `EventSynthesizer.swift:301-304` help
  only if the end is understood). `forceFallback` exists but the Mac app never calls it (no hit in
  `Apps/Mac`), so the user has no switch.
- **User impact**: core trackpad gestures stop working after an OS update, with no workaround
  short of a new build.
- **Severity**: high. **Confidence**: likely. The breakage itself is speculative, but the missing
  detection and the missing switch are confirmed.
- **Fix**: (1) a per-gesture "Use keyboard shortcut instead" toggle in Settings, persisted and
  applied through `forceFallback`. (2) For Spaces, watch
  `NSWorkspace.activeSpaceDidChangeNotification` after a completed native swipe. After 3 completed
  swipes with no Space change, switch Spaces to the fallback and say so in the menu.
- **Effort**: M. **Viability**: high for (1), medium for (2).

---

## Medium

### M1. Large clipboard transfers on slow Wi-Fi drop the whole session; huge text fails silently

- **Scenario**: clipboard with huge text, or an image near the 11 MB cap, on congested Wi-Fi.
- **What happens**: liveness is counted only when a whole TCP frame arrives: on the phone
  `lastReceived` is set in `handleFrame` (`GlasspadClient.swift:331`) and checked against 3.5 s
  (`:488`). On the Mac, `lastHeard` is set per frame (`GlasspadServer.swift:403`) and checked
  against 6 s. Pings queue behind a 14 MB base64 frame. At about 3 MB/s the transfer takes longer
  than 3.5 s, so the phone tears the link down mid-transfer, and any drag on the Mac is cancelled.
  Text has no size cap. Over 16 MB, `ControlChannel.send` drops it with only a log line
  (`Link.swift:237-240`), while the phone already shows "Sent N characters"
  (`Apps/iOS/Sources/Modes/ClipboardMode.swift:79-85`) or the pull spinner just ends. A multi-MB
  string shown in a SwiftUI `Text` (`ClipboardMode.swift:129-135`) can freeze the phone UI.
- **User impact**: a disconnect plus a missing paste, with no message.
- **Severity**: medium. **Confidence**: likely. The trace is confirmed; whether it triggers
  depends on throughput.
- **Fix**: mark the link alive on any bytes received (give `ControlChannel` an `onBytes` callback
  from `receive`). Cap text at about 4 MB on both sides with a clear message. Show only the first
  few thousand characters in the preview.
- **Effort**: S. **Viability**: high.

### M2. Japanese or Chinese input method on the Mac garbles typed text

- **Scenario**: IME active (Japanese romaji/kana, Chinese Pinyin).
- **What happens**: Keys mode and macro typing post the text as Unicode strings on key code 0
  (`KeyboardSynth.swift:69-89`, `GlasspadMacros/System/CGEventOutput.swift:52-78`). Input methods
  intercept key events, so ASCII text goes into an uncommitted composition ("konnichiwa" becomes
  marked kana). Apps that read the key code instead of the string (remote desktop clients, VMs,
  some games) type "a" for every chunk.
- **User impact**: wrong or uncommitted text for every user who keeps an IME selected.
- **Severity**: medium. **Confidence**: likely.
- **Fix**: around a typing burst, switch to `TISCopyCurrentASCIICapableKeyboardInputSource()` with
  `TISSelectInputSource`, then restore. For long text, offer paste through the pasteboard.
- **Effort**: M. **Viability**: medium. Switching input sources has a visible flicker; paste is
  the more robust option.

### M3. Dock hider: a crash at the wrong moment leaves the Dock hidden for good, and phone locks restart the Dock

- **Scenario**: Dock hidden by Glasspad, then the Mac crashes; phone locked and unlocked with
  "hide while connected" on.
- **What happens**:
  1. `hide()` writes the saved values to Glasspad's own `UserDefaults` (`MacDockHider.swift:119`)
     but only synchronizes the Dock's domain (`:123`) before `killall Dock`. A kernel panic or
     power loss before cfprefsd flushes Glasspad's domain keeps the 1000 s delay and loses the
     record of what to restore.
  2. Recovery runs only when Glasspad launches again (`ModeRouter.swift:54`). If it is not a
     login item, or was removed, the Dock stays effectively hidden. Turning autohide back on later
     still has the 1000 s delay, so the Dock never appears.
  3. Backgrounding the phone disconnects (`MacSession.swift:119-125`). After the 2 s grace
     (`ModeRouter.swift:39`, `:176-187`) the Dock is restored with `killall Dock`, and again on
     unlock. Each restart closes Mission Control and Launchpad and makes the Dock flash.
- **User impact**: (1)/(2) rare but confusing and hard to undo by hand. (3) Every phone lock.
- **Severity**: medium. **Confidence**: (3) confirmed; (1) and (2) likely.
- **Fix**: call `CFPreferencesAppSynchronize` on Glasspad's own domain before touching the Dock.
  Add "Dock looks hidden?" with a one-click restore in the menu. Mention
  `defaults delete com.apple.dock autohide-delay` in the README. Raise the reconnect grace to
  about 30 s, or keep the Dock hidden while the phone is only backgrounded.
- **Effort**: S. **Viability**: high.

### M4. Battery: a 50 Hz strict timer runs for the whole session, and Low Power Mode is ignored

- **Scenario**: Low Power Mode on phone; any long session.
- **What happens**: `startKeepalive` schedules a `.strict` timer every 20 ms for as long as the
  phone is connected (`GlasspadClient.swift:475-483`), including in Deck, Media and Clipboard
  where it does nothing. Heartbeats go out 50 times a second for 120 s after every touch while
  the trackpad is visible (`Link.swift:63-65`). Nothing in the iOS app reads
  `isLowPowerModeEnabled`; only the thermal state is checked (`MacSession.swift:331-340`).
- **User impact**: steady CPU and Wi-Fi wakeups drain the battery; Low Power Mode gets no relief.
- **Severity**: medium. **Confidence**: confirmed by trace. The drain has not been measured.
- **Fix**: run the 20 ms timer only while a finger is down, lift resends are pending or heartbeats
  are on; otherwise tick at 1 s for the silence check. In Low Power Mode, cut the heartbeat idle
  window to about 10 s.
- **Effort**: S. **Viability**: high.

### M5. Apple Music and Spotify both open: the fallback always picks Spotify, so pause can start Spotify

- **Scenario**: Apple Music plus Spotify both running, when the MediaRemote helper is unavailable
  or has reported nothing for 2 s.
- **What happens**: `scriptTarget` returns `players.first { !denied }` (`MediaMode.swift:315-316`),
  and `ScriptablePlayer.allCases` lists Spotify first (`NowPlayingAppleScript.swift:7-9`). Media
  shows Spotify even while Music plays. Commands then go to Spotify (`MediaMode.swift:111-115`),
  so "pause" sends `playpause` and starts Spotify on top of Music.
- **User impact**: the wrong player is shown and both play at once.
- **Severity**: medium. **Confidence**: confirmed for the fallback path. With the helper working,
  MediaRemote picks the right app.
- **Fix**: poll every running player and prefer the one whose state is "playing", then the most
  recently started.
- **Effort**: S. **Viability**: high.

### M6. The Mac always advertises over AWDL, which may cause the latency spikes the phone avoids

- **Scenario**: Bluetooth or AirDrop interference; everyday use on a shared network.
- **What happens**: both Mac listeners allow peer-to-peer (`GlasspadServer.swift:162-166`). Publishing
  a Bonjour service over AWDL can keep the Mac's `awdl0` interface active, and that interface
  makes the Wi-Fi chip hop channels. The phone's comment (`Link.swift:90-94`) names that hopping as
  the cause of periodic spikes, but the Mac pays it all the time.
- **User impact**: periodic pointer hitches on the Mac side, even on good Wi-Fi.
- **Severity**: medium. **Confidence**: speculative. Check `ifconfig awdl0` and the `TouchDiagnostics`
  lateness with peer-to-peer on and off.
- **Fix**: if confirmed, make peer-to-peer an opt-in "Connect without shared Wi-Fi" setting, or
  start the peer-to-peer listener only after a phone has failed on the shared network.
- **Effort**: S. **Viability**: depends on the measurement.

### M7. Automatic renewal reinstalls the app while it is in use

- **Scenario**: 7-day expiry mid-use.
- **What happens**: `scripts/refresh-phone.sh` runs every hour from day 5 and reinstalls as soon
  as the phone is reachable (`:21-31`, working-tree version). It does not check whether Glasspad is
  in use, so iOS kills the running app mid-session.
- **User impact**: the trackpad vanishes mid-task about once a week.
- **Severity**: medium. **Confidence**: confirmed by trace.
- **Fix**: have the Mac app write a "phone connected" marker file, skip renewal while it is fresh,
  and prefer night hours until day 6.
- **Effort**: S. **Viability**: high.

---

## Low

### L1. The Notification Center gesture only works on English Macs and needs a second permission

- `EventSynthesizer.swift:243-246` clicks the menu bar item named "Clock" through System Events.
  The name is localized, and it needs Automation consent for System Events, which the onboarding
  does not mention. On other languages it fails silently. **Confidence**: likely.
  **Fix**: find the item by AX identifier (`com.apple.menuextra.clock`) instead of its name.
  **Effort**: S.

### L2. Gesture fallbacks use US key positions too

- The page-swipe fallback presses Cmd + key code 33 ("[" on US, "ü" on German), and Look Up
  presses Cmd+Ctrl + code 2 ("e" on Dvorak) (`EventSynthesizer.swift:228`, `:240`).
  **Confidence**: confirmed. **Fix**: same as C1. **Effort**: S.

### L3. A replaced phone never retries after the other phone leaves

- After a takeover the client stops retrying for good (`GlasspadClient.swift:377-384`), and
  foregrounding does not retry either (`MacSession.swift:197-199`). If the second iPhone
  disconnects, the first still says "Another iPhone is using this Mac" until the user taps
  "Use here". **Confidence**: confirmed. **Fix**: publish `busy=0/1` in the Bonjour TXT record and
  retry automatically once the Mac is free. **Effort**: M.

### L4. Unplugging the display the frame clock follows leaves output unsmoothed

- `DisplayFrameClock` binds to the screen under the pointer when it starts (`FrameClock.swift:27-46`)
  and is stopped only from `displayFrame` (`TouchPipeline.swift:94-99`). If that display goes
  away, the link never fires again, `isRunning` stays true, and every event goes out through the
  stall path with no smoothing until the next disconnect. Also, a pointer moved to a 60 Hz display
  stays paced by the old display. **Confidence**: likely. **Fix**: restart the clock on
  `NSApplication.didChangeScreenParametersNotification` and when the pointer changes screen.
  **Effort**: S.

### L5. Flipping the phone 180 degrees in Landscape mid-touch can jump the pointer

- The "landscape" mask allows both landscape sides (`Orientation.swift:20-26`). A 180-degree turn
  keeps the same bounds size, so `layoutSubviews` does not cancel the fingers
  (`TrackpadSurfaceView.swift:74-81`), and a touch that survives the turn reports flipped
  coordinates. **Confidence**: speculative. UIKit may cancel touches on rotation; needs a device
  test. **Fix**: also cancel when the interface orientation changes. **Effort**: S.

### L6. The phone keeps retrying every 2 s while the Mac sleeps

- The backoff tops out at 2 s (`Link.swift:61`). With the app left open, a Bonjour Sleep Proxy can
  turn each TCP attempt into a wake request, so the Mac may not stay asleep. **Confidence**:
  speculative. **Fix**: after about 10 failures, back off to 30 s until the user touches the
  screen. **Effort**: S.

### L7. The macro stop-on-input guard cannot see typing under Secure Event Input

- When a password field or Terminal's "Secure Keyboard Entry" is active, the listen-only tap
  (`UserInputGuard.swift:44-81`) gets no key events, so typing does not stop playback. The mouse
  still does. **Confidence**: likely. **Fix**: when `IsSecureEventInputEnabled()` is true at start,
  show "stop with the mouse or the phone". **Effort**: S.

### L8. Games and fullscreen apps that read raw input ignore the trackpad

- Synthetic CGEvents do not reach apps that read the mouse through GameController or IOHID. This
  is inherent. **Confidence**: speculative. **Fix**: document it; no code fix. **Effort**: none.

### L9. The Mission Control and Spaces fallbacks depend on the user's shortcut settings

- The fallbacks press Ctrl+arrows (`EventSynthesizer.swift:316-318`). If those shortcuts are off or
  remapped in System Settings > Keyboard > Shortcuts, the fallback does nothing. **Confidence**:
  confirmed. **Fix**: read `com.apple.symbolichotkeys` IDs 32, 33, 79, 81 and warn when they are
  off. **Effort**: S.

---

## Scenarios walked with no new issue found

- **Mac sleeps mid-drag**: on wake the server's silence check closes the session; `linkStateChanged`
  -> `pipeline.cancelAll()` releases the button. The phone reconnects on its 3.5 s silence check.
- **Phone locks mid-scroll**: UIKit cancels the touches, the cancel frame ends the scroll, and the
  0.5 s stale guard covers a lost packet. Backgrounding sends bye.
- **Incoming call or notification**: touches are cancelled and the button is released.
  `.inactive` keeps the link up.
- **Backgrounded for hours, then resumed**: a fresh connector, and the clock offset resets per
  session (`cancelAll` clears it).
- **Two Macs**: macID lives in a ThisDeviceOnly Keychain item, so a migrated Mac does not clone it.
  The phone holds one client at a time.
- **Wi-Fi switch**: a gateway change restarts the session at once (`GlasspadClient.swift:223-250`).
- **Mac on Ethernet + Wi-Fi**: Bonjour answers per interface and UDP follows the resolved TCP
  address.
- **Multiple displays**: `clamp` keeps the pointer out of gaps and stops at unshared edges, as a
  real trackpad does.
- **Spotify not running**: every script checks "is running" first, and players are polled only
  when running.
- **Event taps disabled by timeout**: re-enabled (`EventTap.swift:36`, `:59`).
- **Dynamic Type huge**: dense screens cap the size (`KeysMode`, `DockMode`, `ModeSwitcher`,
  `DeckComponents`). Settings and onboarding were not checked visually.
- **VoiceOver**: the trackpad uses `.allowsDirectInteraction`, and the mode switcher adapts.
- **Stage Manager**: nothing in the event path depends on it.
