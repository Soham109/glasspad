# Building and running

How to build both apps from a clone and run them while you work. For how the code fits together, see [ARCHITECTURE.md](../ARCHITECTURE.md).

## What you need

| Tool | For | Get it |
| --- | --- | --- |
| A Mac and Swift 6 | The packages and the Mac app | Xcode, or the command line tools alone (`xcode-select --install`) |
| Xcode 26 or newer | The iPhone app (it uses iOS 26's glass where available) | App Store, free |
| [XcodeGen](https://github.com/yonaskolb/XcodeGen) | Making `Glasspad.xcodeproj` from `project.yml` | `brew install xcodegen` |
| A free Apple ID | Signing the iPhone app | Xcode > Settings > Apple Accounts |
| An iPhone on iOS 18 or later | Running on a device | Developer Mode on (Settings > Privacy & Security) |

No paid Apple Developer Program membership is needed ([ADR 0001](adr/0001-free-apple-id-with-automatic-renewal.md)).

## First build

```bash
git clone https://github.com/Soham109/glasspad.git
cd glasspad
scripts/test.sh          # all package tests, installer tests, main-thread check
scripts/build-mac.sh     # build/Glasspad.app, signed locally, not launched
xcodegen generate        # Glasspad.xcodeproj (not committed)
open Glasspad.xcodeproj
```

## Ways to run

| Goal | Command | Notes |
| --- | --- | --- |
| Mac app, quick build | `scripts/build-mac.sh`, then `open build/Glasspad.app` | Signed ad hoc (no certificate). macOS may ask for Accessibility again after each rebuild. |
| Mac app, installed like a user has it | `scripts/install-mac.sh` | Builds, copies to `/Applications`, signs with your Apple Development certificate (so Accessibility survives updates) and restarts it. |
| Mac app in Xcode | Scheme **Glasspad Mac** | Uses `Config/Mac/Info.plist` and the entitlements there. |
| iPhone app on a device | Scheme **Glasspad iOS**, your team under Signing & Capabilities | Debug build, so the [debug launch arguments](#debug-launch-arguments) work. |
| iPhone app, installed like a user has it | `scripts/install-phone.sh [device id]` | Builds the **committed** revision (`GLASSPAD_REV`, default `HEAD`) in a separate worktree, Release by default. `GLASSPAD_CONFIG=Debug` for a debug build. |
| iPhone app in the simulator | Scheme **Glasspad iOS**, any iPhone simulator | No camera and no Mac needed with `-GPDemo` (below). |

`scripts/install-phone.sh` ignores uncommitted changes on purpose: renewal reinstalls exactly what was installed. Commit first, or run from Xcode.

## Where build files go

All scripts share `scripts/toolchain.sh`:

| Setting | Default | Change it with |
| --- | --- | --- |
| SwiftPM build folder | `~/Library/Caches/glasspad-build/<checkout name>-<hash>` (one per checkout, so worktrees never fight) | `GLASSPAD_BUILD_ROOT` |
| Developer folder | `xcode-select -p` | `DEVELOPER_DIR` (for example `/Library/Developer/CommandLineTools` before the Xcode license is accepted) |
| Extra flags for swift-testing with only the command line tools | Added by the script | Nothing to do |

The build folder sits outside the repo because codesign refuses bundles in an iCloud-synced Desktop or Documents folder.

## Debug launch arguments

Debug builds of the iPhone app read launch arguments, so screens can be drawn without a Mac, a camera or a finger. Set them in Xcode under **Product > Scheme > Edit Scheme > Run > Arguments**. The full list is the comment above `DebugLaunch` in `Apps/iOS/Sources/App/RootView.swift`.

| Argument | Does |
| --- | --- |
| `-GPDemo <icon folder>` | Fills every screen with sample Mac data. Any folder works; an empty one gives letter icons. |
| `-GPMode <mode>` | Opens a mode: `trackpad`, `keys`, `media`, `dock`, `actions`, `deck`, `macros`, `clipboard`, `present`, `remote`, `displays`, `clock`, `nowPlaying`, `calendar` |
| `-GPTheme <theme>` | Sets the theme, for example `paper`, `graphite`, `mono`, `grain` |
| `-GPPair <glasspad://pair?... link>` | Pairs as if the code was scanned |
| `-GPOnboarding`, `-GPSettings`, `-GPMenu` | Opens onboarding, Settings or the mode menu |
| `-GPTour [rounds]` | Visits every mode, sheet, layout and theme, for memory checks |
| `-GPLaunchClock` | Prints the time to the first frame |

`scripts/visual-screens.txt` lists the argument sets the visual check uses. They are good examples.

## Logs

| From | How |
| --- | --- |
| Mac app and its link | `log stream --predicate 'subsystem == "com.soham109.glasspad"'` (live) or `log show --last 10m --predicate 'subsystem == "com.soham109.glasspad"'` |
| iPhone app on a device | Launch with `GLASSPAD_LOG=1` in the environment (Xcode scheme, or `xcrun devicectl device process launch --console`) and read the console |
| Touch feel on the Mac | One `feel:` line per second while frames flow (`TouchDiagnostics`); see [SPEC section 7](SPEC.md#7-mac-event-synthesis-glasspadmaccoresynth) |
| Renewal | `~/Library/Logs/Glasspad/refresh.log` |

## Editing tips

- **New iPhone files** under `Apps/iOS/Sources` appear in Xcode after `xcodegen generate`.
- **New Mac app files** need nothing: `Apps/Mac` is a SwiftPM package.
- **A theme changed?** Run `scripts/web-themes.sh` to update the website's theme list.
- **App icons changed?** `swift scripts/make-icons.swift` redraws them.
- **Several checkouts at once?** Use `git worktree add`. Each gets its own build folder.

## Next

- [Testing](testing.md): what to run before a pull request.
- [Troubleshooting](troubleshooting.md): when a build or run goes wrong.
