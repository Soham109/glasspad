# Interface requests

Requests from one part of Glasspad to another. Add a request at the bottom, and mark it
done (with the shipped names) when it lands.

## 1. Macros mode messages (from: iPhone app, to: GlasspadKit)

The iPhone app has a Macros screen and Siri / Shortcuts actions ("Run macro") but
`ModeMessage` has no macro cases yet. Requested additions:

```swift
public enum GlasspadMode { ...; case macros }

/// One macro as the phone shows it. Steps stay on the Mac.
public struct MacroSummary: Codable, Equatable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var name: String
    public var symbol: String        // SF Symbol name
    public var color: String?        // "#RRGGBB", optional accent
    public var stepCount: Int
    public init(id: UUID, name: String, symbol: String, color: String?, stepCount: Int)
}

public enum ModeMessage {
    /// Phone -> Mac: send the macros for the current front app profile.
    case macrosRequest
    /// Mac -> phone: macros in display order, plus the active profile's name
    /// (e.g. "Safari"), nil for the default profile. Sent on request and whenever the
    /// front app changes the profile while Macros is shown.
    case macrosList(profile: String?, macros: [MacroSummary])
    /// Phone -> Mac: run this macro.
    case macrosRun(id: UUID)
    /// Mac -> phone: outcome of `macrosRun`; `message` is shown on failure.
    case macrosResult(id: UUID, ok: Bool, message: String?)
}
```

Until these exist the iPhone app leaves the Macros screen and the "Run macro" action out
rather than shipping a screen that cannot work.

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
