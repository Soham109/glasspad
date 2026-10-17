# Troubleshooting for developers

Problems you may hit while building, testing or running from source. For help using the app, see the [guide on the website](https://glasspad.sohamaggarwal.com/guide).

## Building

| Symptom | Cause | Fix |
| --- | --- | --- |
| `resource fork, Finder information, or similar detritus not allowed` | The build folder is in an iCloud-synced folder (Desktop, Documents) | Use the scripts; they build in `~/Library/Caches/glasspad-build`. With plain `swift test`, pass `--scratch-path` outside iCloud. |
| `no such module 'Testing'` with only the command line tools | swift-testing is in a framework folder that is not on the default path | Run `scripts/test.sh`; it adds the flags. By hand: `source scripts/toolchain.sh` and pass `${GP_SWIFT_FLAGS[@]}`. |
| Xcode license not accepted, so `swift` refuses to run | Xcode is installed but its license is not | `sudo xcodebuild -license accept`, or `DEVELOPER_DIR=/Library/Developer/CommandLineTools scripts/test.sh` |
| A new iPhone file is missing in Xcode | The Xcode project is generated | `xcodegen generate` |
| `xcodegen: command not found` | Not installed | `brew install xcodegen` |
| Two worktrees break each other's builds | Shared build folder | Nothing to do with the scripts: each checkout gets its own folder. With `GLASSPAD_BUILD_ROOT` set, give each its own. |
| iPhone build: no team or no signing certificate | Not signed in to Xcode | Xcode > Settings > Apple Accounts, sign in, pick your team once under Signing & Capabilities |
| `scripts/install-phone.sh` did not include my change | It builds the committed revision only | Commit first, or run from Xcode |

## Running

| Symptom | Cause | Fix |
| --- | --- | --- |
| Pointer does not move | Accessibility is off for this copy of the app | System Settings > Privacy & Security > Accessibility. Each ad hoc build from `scripts/build-mac.sh` can count as a new app; `scripts/install-mac.sh` signs with your certificate so the permission sticks. |
| Media shows nothing | Now playing helper not built or `/usr/bin/perl` missing | Build with `scripts/build-mac.sh` or `scripts/install-mac.sh` (they compile the helper). Check the log for `now-playing helper`. |
| Phone keeps "Looking for your Mac" | Different networks, Local Network permission off, or a network that keeps devices apart | Same Wi-Fi; iPhone Settings > Privacy & Security > Local Network > Glasspad; try a home network |
| Spaces swipe does nothing | Private gesture events stopped working on this macOS | Mac Settings > Trackpad > "If a Gesture Stops Working": choose Keyboard shortcut |
| Pointer feels jumpy | Peer-to-peer Wi-Fi in use, or a busy network | The Mac logs `peer-to-peer Wi-Fi: expect latency spikes`. Read the `feel:` lines in the log. |
| Phone app stops opening after 7 days | Free Apple ID profile expired | `scripts/refresh-phone.sh --now`, or run `scripts/install-phone.sh` again. Check `~/Library/Logs/Glasspad/refresh.log`. |

Read the Mac's log:

```bash
log show --last 10m --predicate 'subsystem == "com.soham109.glasspad"'
```

## Tests

| Symptom | Cause | Fix |
| --- | --- | --- |
| `main thread:` lists a call | A blocking call in main-thread code | Move the work to a background queue or `Task.detached`, then hop back. Only if it truly cannot block, add a line to `scripts/main-thread-allowlist.txt` with the reason. |
| `WireGoldenTests` fails: `no longer reads` or `written differently now` | A wire change broke an older build | Make the change additive: new optional fields, new cases. Never rename or remove. See [ADR 0005](adr/0005-additive-protocol-and-frozen-wire.md). |
| A timing test fails only under load | The machine is busy | Run again with less running. CI retries a few failed tests once by itself. |
| Installer tests fail after editing `install.sh` | A stub in `scripts/tests/stubs` does not know the new call | Teach the stub, and add a case to `scripts/tests/installer-test.sh` |
| `visual-check.sh`: `no simulator named GP-guard` | The simulator does not exist yet | `xcrun simctl create GP-guard "iPhone 17 Pro"` |
| `visual-check.sh`: `build failed` | The iPhone app does not compile | Read `build/visual-build.log` |
| `visual-check.sh` lists screens with motion | Clocks or animations | Raise that screen's allowance in `scripts/visual-screens.txt`, with a reason in the comment |
