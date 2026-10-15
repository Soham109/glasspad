# Glasspad macros: spec

Package: `Packages/GlasspadMacros` (swift-tools-version 6.0, macOS 14+).
It depends on nothing else in the repo. The Mac app wires it in through the
protocols below; the phone talks to it through new `ModeMessage` cases that
the coordinator adds to GlasspadKit (section 6).

Tests: `cd Packages/GlasspadMacros && swift test`. No test posts a real event
or starts a real event tap. If the repo lives in an iCloud-synced folder
(Desktop/Documents), codesigning the test bundle fails with "resource fork,
Finder information, or similar detritus not allowed"; build outside the synced
folder with `swift test --scratch-path /tmp/glasspad-macros-build`.

## 1. Model

A macro is a named list of steps with an SF Symbol and a colour.

```swift
public struct Macro: Identifiable, Codable, Sendable {
  var id: UUID; var name: String
  var symbol: String            // SF Symbol, default "bolt.fill"
  var color: String             // "#RRGGBB"
  var steps: [MacroStep]
  var allowScripts: Bool        // must be true before shell or AppleScript runs
  var gestureTriggers: [String] // phone gesture names, e.g. "fourFingerTap"
  var hotkey: KeyCombo?         // global Mac hotkey
  var origin: ItemOrigin        // user | starter | recorded
}
```

Steps (JSON `type` in brackets):

| Step | JSON fields |
|---|---|
| keystroke `[keystroke]` | `key`, `modifiers` |
| type text `[typeText]` | `text` (newline and tab are sent as real Return/Tab keys) |
| click `[click]` | `button` left/right/middle, `at` point, `count` 1 to 3, `modifiers` |
| move pointer `[moveMouse]` | `to` point |
| drag `[drag]` | `button`, `from`, `to`, `durationMs` |
| scroll `[scroll]` | `dx`, `dy` pixels, Quartz convention (positive dy scrolls up) |
| wait `[wait]` | `ms` |
| wait until app is frontmost `[waitForApp]` | `bundleID`, `timeoutMs`; fails the run on timeout |
| open app `[openApp]` | `bundleID` |
| open URL `[openURL]` | `url` (must have a scheme) |
| open file `[openFile]` | `path` (`~` expanded) |
| run Apple Shortcut `[runShortcut]` | `shortcut` (name or identifier), optional `input` text |
| run AppleScript `[runAppleScript]` | `source`; needs `allowScripts` |
| run shell `[runShell]` | `command`, `timeoutMs`; needs `allowScripts` |
| set clipboard `[setClipboard]` | `text` |
| notification `[notify]` | `title`, `body` |
| repeat `[repeat]` | `count` 1 to 10000, `steps` (nests freely) |

AppleScript is gated by `allowScripts` as well as shell, because
`do shell script` makes it exactly as powerful.

Keys: a single character (`"t"`, `"/"`, `"["`) means "the key that types this
character with no modifiers" and is mapped to a key code for the active
keyboard layout at run time, so shortcuts stay right on non-US layouts. Named
keys: `return tab space delete forwardDelete escape left right up down home end
pageUp pageDown keypadEnter help f1...f20`. Escape hatch: `"code:93"`.
Modifiers: an array of `control option shift command`.

Points: `{"x":..,"y":..,"relativeTo":"screen"}` or
`{"x":..,"y":..,"relativeTo":"window","anchor":"topLeft"}`. Coordinates are
Quartz global points (top-left origin, y down), the same space as
`CGEvent.location` and the Accessibility API. A window point is an offset from
an anchor (`topLeft topRight bottomLeft bottomRight center`) of the frontmost
app's focused window, read through Accessibility when the step runs (falling
back to the window server's list if Accessibility is not granted).

Storage, one file per macro:
`~/Library/Application Support/Glasspad/macros/<uuid>.json`

```json
{ "formatVersion": 1, "macro": { "id": "...", "name": "...", "steps": [ ... ] } }
```

Versioning: a file with a higher `formatVersion` than this build knows is
refused with a clear error and left untouched. A bare macro object with no
envelope reads as version 0 (handy for hand-written files). Optional fields
fall back to defaults, so adding fields later does not break old files. A
broken file is reported in `loadFailures` and never hides the others.

Profiles: `~/Library/Application Support/Glasspad/profiles.json`,
`{"formatVersion":1,"profiles":[...]}`.

## 2. Recorder

`MacroRecorder` listens with a listen-only `CGEventTap` (Input Monitoring) on
its own thread. It turns the raw stream into steps:

- typed characters become one `typeText`; Delete edits the run;
- Command/Control combos and non-printing keys become `keystroke`;
- pointer moves collapse to their end point and are dropped before a click;
- press then release is a click, or a drag if the pointer moved more than 4 pt;
  rising click counts merge into a double or triple click;
- scroll bursts (gaps under 300 ms) merge into one step;
- pauses of 50 ms or more become `wait` (rounded to 10 ms, capped at 5 s).

Options: screen or window-relative positions, keep timing on/off, the stop
hotkey (default Control-Option-Command-period, never recorded).

Passwords are never captured: `start()` throws `secureInputActive` while
`IsSecureEventInputEnabled()` is true, and any key press arriving while it is
true mid-recording is discarded and counted. Events posted by macro playback
carry a marker in `kCGEventSourceUserData` and are never recorded.

Stop from the phone with `engine.stopRecording()`. Stop from the Mac menu with
`stopRecording(fromMacMenu: true)`, which drops the click on the menu item.

## 3. Player

`MacroPlayer.run(macro, options, progress:)`:

- validates the whole macro first (script flag, counts, timeouts, expansion
  limit of 100000 steps), so nothing half-runs;
- `speed` scales waits and drag durations (0.05 to 20); app timeouts are not scaled;
- cancel the calling task (or `engine.cancelRun()`) to stop at any point,
  including mid-wait; a cancelled drag still releases the button;
- `stopOnUserInput` (default on): a listen-only tap watches the real mouse and
  keyboard and stops playback on a key press, click, scroll or a pointer move
  of 4 pt or more. Key-ups, modifier changes and auto-repeat are ignored so the
  hotkey that started the macro does not stop it. If the tap cannot start
  (no Input Monitoring) the run continues and `userInputGuardActive` is false;
- progress callback before each step and once at the end;
- result: `completed | cancelled | interruptedByUser | failed(MacroError)`,
  steps done, the step path where it stopped, and text outputs from
  shortcuts, AppleScript and shell.

`dryRun(macro)` resolves every step (window points against the window that is
frontmost now, waits scaled, URLs and files checked) and returns the
`[PlannedAction]` without posting, opening, running or waiting.

## 4. Protocols the Mac app implements or reuses

Each has a real default in the package; the app only replaces one if it wants to.

| Protocol | Default | Job |
|---|---|---|
| `MacroEventOutput` | `CGEventOutput` | press keys, type text, move, click, drag, scroll. Needs Accessibility. Must stamp `MacroEventMarker.userData` on every event |
| `FrontmostWindowProviding` | `AXWindowProvider` | frontmost bundle id, focused window frame |
| `AppLaunching` | `WorkspaceAppLauncher` | open app by bundle id, open URL or file |
| `ShortcutsRunning` | `ShortcutsCLI` | list shortcuts with folders, run with input, capture text output |
| `ScriptRunning` | `SystemScriptRunner` | NSAppleScript on one dedicated serial queue (never the main thread); shell via `/bin/zsh -c` with timeout, Homebrew paths added |
| `ClipboardWriting` | `PasteboardClipboard` | set clipboard text |
| `Notifying` | `SystemNotifier` | UserNotifications inside the app bundle, `osascript` fallback outside |
| `UserInputMonitoring` | `EventTapUserInputMonitor` | hard stop on real input |
| `SecureInputChecking` | `SystemSecureInputChecker` | `IsSecureEventInputEnabled()` |
| `RecordingEventSource` | `CGEventTapRecordingSource` | raw events for the recorder |
| `FrontmostAppObserving` | `WorkspaceFrontmostAppObserver` | `didActivateApplicationNotification` |
| `HotkeyRegistering` (main actor) | `CarbonHotkeyCenter` | global hotkeys via `RegisterEventHotKey` (no permission needed) |
| `MacroClock` | `ContinuousMacroClock` | sleeping, injectable for tests |

Wiring, in the Mac app:

```swift
let engine = MacroEngine.live()              // @MainActor
engine.onActiveProfileChanged = { info in send(.macro(.activeProfileChanged(info))) }
engine.onProgress = { p, trigger in send(.macro(.progress(p))) }
engine.onRunFinished = { id, trigger, result in send(.macro(.runFinished(...))) }
engine.onRecordingStoppedByHotkey = { result in /* save draft, notify phone */ }
try engine.start()                           // seeds starters once, loads, registers hotkeys
// gesture engine: when it emits a named gesture
Task { await engine.handleGesture("fourFingerTap") }
```

`ProfileSwitcher` ignores the app's own bundle id, so opening the Glasspad
menu does not swap the phone's buttons. Only one macro plays at a time; a
second request returns `failed(.busy)`.

Permissions the app must request: Accessibility (posting), Input Monitoring
(recording and the user-input guard), Automation prompts appear per target app
on the first AppleScript that talks to it.

## 5. Context profiles

`ContextProfile { id, name, symbol, bundleIDs, macroIDs (button order), isFallback, origin }`.
Resolution: a user profile for the frontmost app beats a starter for the same
app; otherwise list order; no match means the fallback profile.

Starter profiles, seeded once (a marker file stops re-seeding, so a deleted
starter stays deleted; "Restore starters" brings them back without touching the
user's own items). Every button is one standard, documented shortcut:
Everywhere (fallback), Safari, Finder, Xcode, Final Cut Pro, Keynote, Music,
Figma, VS Code, Slack, Zoom. Starter ids are derived from their names, so
restoring overwrites in place.

## 6. ModeMessage cases for GlasspadKit

Add one case to `ModeMessage`, `case macro(MacroMessage)`, with:

```swift
public enum MacroMessage: Codable, Equatable, Sendable {
  // phone -> mac
  case listMacros                                  // reply: macroList
  case run(macroID: UUID)                          // a deck button
  case gesture(name: String)                       // a named phone gesture
  case cancelRun
  case recordStart(windowRelative: Bool, keepTiming: Bool)
  case recordStop                                  // reply: recordingFinished

  // mac -> phone
  case macroList(active: ActiveProfileInfo, all: [MacroSummary])
  case activeProfileChanged(ActiveProfileInfo)     // on every frontmost-app profile switch
  case progress(MacroProgress)                     // before each step and at the end
  case runFinished(macroID: UUID, outcome: RunOutcome, message: String?, outputs: [String])
  case recordingState(isRecording: Bool)           // also sent when the Mac hotkey starts/stops it
  case recordingFinished(macro: MacroSummary, droppedSecureKeys: Int)
}
public enum RunOutcome: String, Codable, Sendable { case completed, cancelled, interruptedByUser, failed }
```

The payload types mirror structs that already exist in this package, all
`Codable` with plain fields:

- `MacroSummary { id: UUID, name, symbol, color: String, stepCount: Int, usesScripts: Bool }`
- `ActiveProfileInfo { profileID: UUID?, name, symbol: String, bundleID: String?, macros: [MacroSummary] }`
- `MacroProgress { macroID: UUID, completedSteps, totalSteps: Int, currentPath: [Int], currentSummary: String }`

GlasspadKit should define its own copies (it cannot import this package); the
Mac app converts between them. `recordStop` from the phone maps to
`engine.stopRecording()`, after which the Mac saves
`MacroEngine.draft(from:name:)` and replies with its summary.

## 7. Needs a live test on a real Mac

These paths cannot run in unit tests without posting events or opening a tap:

- `CGEventOutput`: keystrokes on a non-US layout, text typing into several apps,
  double clicks, drags, pixel scroll direction;
- `EventTapUserInputMonitor`: stops on a real mouse nudge, ignores the
  releasing hotkey;
- `CGEventTapRecordingSource`: record a real session, check secure input with
  a password field;
- `CarbonHotkeyCenter`: hotkey fires and is consumed;
- `AXWindowProvider`: frames for a few apps, multi-display negative coordinates;
- `ShortcutsCLI.run` with real input and output; `SystemNotifier` inside the app bundle;
- NSAppleScript from the serial queue against Finder and Music.
