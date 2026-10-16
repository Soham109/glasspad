# Contributing

Thanks for helping. Small, focused changes are easiest to review.

## Set up

You need a Mac with Xcode 26 or newer for the iPhone app, which uses iOS 26's glass where it is available. The Swift packages and the Mac app also build with only the command line tools (Swift 6).

```bash
git clone https://github.com/Soham109/glasspad.git
cd glasspad
scripts/test.sh          # every package's tests, then the installer tests
scripts/build-mac.sh     # builds build/Glasspad.app (does not launch it)
xcodegen generate        # makes Glasspad.xcodeproj from project.yml
```

Open `Glasspad.xcodeproj` and run the **Glasspad Mac** scheme, then **Glasspad iOS** on your iPhone with your Apple ID under Signing. New files under `Apps/iOS/Sources` are picked up the next time you run `xcodegen generate`. The scripts keep their intermediate build files in `~/Library/Caches/glasspad-build` (set `GLASSPAD_BUILD_ROOT` to move them).

## Project layout

| Folder | What it holds |
| --- | --- |
| `Packages/GlasspadKit` | Code both apps share: protocol, encryption, transport, gestures, and the rules behind Layouts, themes, power, StandBy, Remote and Displays. |
| `Packages/GlasspadMacCore` | Mac only: event synthesis, server, pairing, modes, Mac controls. |
| `Packages/GlasspadMacros` | Mac only: macros, Shortcuts, per-app profiles, starter buttons. |
| `Apps/Mac` | The menu bar app, as a SwiftPM package, with its own tests in `Tests/GlasspadMacSnapshots`. |
| `Apps/iOS` | The iPhone app, its widgets and the code they share. |
| `scripts` | Build, install, test and renewal scripts. Fake Apple tools for the installer tests are in `scripts/tests/stubs`. |
| `docs` | The spec, the installer test notes, reviews and images. |
| `web`, `promo` | The website and the demo film. |

[ARCHITECTURE.md](ARCHITECTURE.md) explains how the pieces fit together.

## Scripts

| Script | What it does |
| --- | --- |
| `install.sh` | The one-line installer: Xcode, XcodeGen, source, signing, Mac app, iPhone app, renewal. Safe to run again. |
| `scripts/test.sh` | Runs every package's tests and `scripts/tests/installer-test.sh`. Extra arguments go to `swift test` (for example `--filter Layout`). |
| `scripts/build-mac.sh` | Builds the Mac app with SwiftPM into `build/Glasspad.app`, signed locally with no certificate needed. |
| `scripts/install-mac.sh` | Builds the Mac app, installs it in Applications, signs it with your Apple Development certificate and restarts it. |
| `scripts/install-phone.sh` | Builds the iPhone app and installs it on your iPhone, over a cable or Wi-Fi. |
| `scripts/setup-autorefresh.sh` | Sets up the hourly job that renews the iPhone app for free Apple IDs. `--remove` takes it away. |
| `scripts/refresh-phone.sh` | What that job runs: reinstalls the last installed version once the install is 5 days old. Logs to `~/Library/Logs/Glasspad/refresh.log`. |
| `scripts/toolchain.sh` | Shared by the scripts: finds the toolchain and adds the flags swift-testing needs with only the command line tools. |
| `scripts/make-icons.swift` | Redraws the app icons. |

## Tests

- `scripts/test.sh` must pass. CI runs it on every push and pull request.
- The Mac app's own tests check its wording and draw the living pairing code, then read it back with Vision:

  ```bash
  swift test --package-path Apps/Mac --scratch-path ~/Library/Caches/glasspad-build/GlasspadMacDebug
  ```

- The snapshot harness in the same target draws every Mac screen, light and dark, to PNGs in `/tmp/gpmac` (or `GLASSPAD_SNAPSHOT_DIR`). It runs only when asked:

  ```bash
  GLASSPAD_SNAPSHOTS=1 swift test --package-path Apps/Mac --scratch-path ~/Library/Caches/glasspad-build/GlasspadMacDebug
  ```

- The iPhone app has demo data for the simulator in debug builds, so it draws without a Mac: `-GPDemo <icon folder>`, `-GPMode <mode>`, `-GPTheme <theme>`, `-GPOrientation` and more (see `Apps/iOS/Sources/App/DemoData.swift` and `DebugLaunch` in `RootView.swift`).

## Before you open a pull request

- Read [docs/SPEC.md](docs/SPEC.md). If you change an interface, change it in the spec too.
- Add a test for new behavior. Gesture changes need a scripted touch sequence test.
- Tests must never post events into the live session. Build events and check their fields, or use the fakes.
- New messages must be additive: an older phone or Mac has to ignore them and keep the session.
- Keep gesture thresholds in `GestureTuning.swift`, not scattered in code.
- Any private macOS call needs a public fallback and a runtime check.
- Only public iOS APIs on the phone.
- Views take colors from `Palette`, never hard-coded.
- Do not copy code from projects with incompatible licenses.

## Style

- Keep the interface minimal. No extra chrome on the trackpad screen.
- Plain words in docs and UI text, in US English. Explain any technical term where you use it.
- Use the names macOS uses: Do Not Disturb, Mission Control, Split Screen.
- Do not use em dashes or en dashes.

## Reporting bugs

Use the bug template. Include your macOS and iOS versions, iPhone model, and which gestures the Mac's Settings > Trackpad shows as using a keyboard shortcut.

## License

By contributing you agree your work is released under the [MIT license](LICENSE).
