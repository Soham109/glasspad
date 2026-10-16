# Interface requests

Requests from one part of Glasspad to another. Add a request at the bottom, and mark it
done (with the shipped names) when it lands. Open follow-ups are listed first.

## Open

### A. Typed pairing code for VoiceOver users (from: Mac app, to: GlasspadKit)

The Mac offers Copy Link and Share (AirDrop) under every QR code, so a VoiceOver user can pair
without the camera: copy on the Mac, then "Paste the Link Instead" on the phone. A short code
typed by hand (for example 8 characters) is not possible with the current protocol: the QR
carries a 32-byte pairing key, and a short code would need a new key agreement step (for
example SPAKE2 or a similar password-authenticated exchange) so a guessable code cannot be
brute-forced on the network. That is a protocol change beyond additive messages.

### B. Gestures the self-check cannot see break (from: reliability review H5, to: GlasspadMacCore)

The per-gesture override is done (see Done, 7). Still open: noticing on its own that a native
gesture stopped working, for example watching `NSWorkspace.activeSpaceDidChangeNotification`
after completed native Spaces swipes and switching to the shortcut after 3 swipes with no Space
change. Needs a device test on a macOS where the private events stop working.

### C. Known limits on the Mac (from: GlasspadMacCore, to: coordinator)

- `forceClick(stage:)` has no native path (it would need private pressure events, type 34).
  Stage 2 triggers Look Up (ctrl+cmd+D) when `settings.lookUp == .forceClick`.
- `notificationCenter` clicks the menu bar item named "Clock" through System Events. The name
  is localized, so it fails on non-English Macs, and it needs the Automation permission the
  first time (reliability L1: find the item by its AX identifier instead).
- The Spaces and Mission Control shortcuts depend on the user's keyboard shortcut settings
  (reliability L9: read `com.apple.symbolichotkeys` and warn when they are off).

## Done

1. **Macros mode messages** (iPhone app to GlasspadKit). `ModeMessage.macro(MacroMessage)`,
   `GlasspadMode.macros`, and the payload types `MacroSummary` (with `rgb`),
   `ActiveProfileInfo`, `MacroProgress` (with `fraction`), `RunOutcome`, exactly as in
   docs/SPEC-macros.md section 6, plus `recordingFailed(message:)`. The Mac handles every case
   (GlasspadMacCore `MacroCoordinator`).
2. **Mac side notes** (GlasspadMacCore). `ModeRouter.handle` switches over every `ModeMessage`
   case, so a new case must be added there or the Mac package stops compiling. The Mac's
   Keychain record is `StoredPhone` (GlasspadKit has `PairedPhone`). Haptics: the phone runs its
   own recognizer for instant clicks; the Mac only sends `.haptic(.snap)` when a Dock-level
   swipe completes. Build products live in `~/Library/Caches/glasspad-build/<package>`
   (override with `GLASSPAD_BUILD_ROOT`), because codesign refuses bundles in the iCloud-synced
   Desktop.
3. **Copy pairing link** (iPhone app to Mac app). Copy Link and Share… in the Mac popover, the
   Settings pairing sheet and the Welcome window.
4. **Connectivity for the phone** (GlasspadKit to iPhone app). `reconnectNow()` on foreground,
   wake targets kept with the pairing and "Wake Mac", `failed(GlasspadService.replacedFailure)`
   when another iPhone takes the Mac, `AppMode.macros.wireMode`.
5. **Trackpad feel settings** (trackpad feel to Settings screen). `TrackpadTuningSection` sits
   in the phone's Settings pages; values in `TrackpadSettings.tuning`, sent inside
   `ControlMessage.settings`, stored on the Mac under `phoneTrackpadTuning`.
6. **Accessibility-off warning on the phone** (Mac app and GlasspadKit to iPhone app).
   `ControlMessage.macStatus(MacStatus)`; the phone shows a banner while
   `accessibilityTrusted == false` and a Media notice when `automationMedia == .denied`.
7. **Gesture overrides** (reliability H5 part 1). `GesturePreference` (Automatic, Native,
   Keyboard shortcut) per `SynthGesture`, stored in the Mac app's preferences under
   `synth.gesturePreferences`. Settings > Trackpad > "If a Gesture Stops Working" sets them;
   `GlasspadController.setGesturePreference(_:for:)` applies a change at once
   (`EventSynthesizer.updateCapabilities`, which first ends a native Dock swipe in progress).
   Advanced > Diagnostics shows the path each gesture uses now.
8. **Clipboard on slow Wi-Fi** (reliability M1). Partial frames count as liveness on both ends
   (`ControlChannel.onBytes`), so a large message no longer drops the link. Text over
   `ClipboardContent.maxTextBytes` (2 MB) is refused whole by either side. The Mac answers
   every push with `ModeMessage.clipboardPushResult(ok:message:)` and explains a refused pull
   with `clipboardPullRefused(message:)` before the plain `clipboardContent(nil)`. The phone
   says "Sent" only after an `ok`, shows the Mac's reason otherwise, and says so when the Mac
   did not answer or the link dropped. The Mac shows its last refusal in Advanced >
   Diagnostics.
