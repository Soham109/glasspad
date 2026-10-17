# Scripts

Everything you need to build, test, install and check Glasspad from the command line. The
`Makefile` in the repo root wraps the common ones, so `make help` is the fastest way in:

```sh
make doctor        # which tools you have and which are missing (changes nothing)
make test          # every test; needs no iPhone, Apple account or network
make build-mac     # build/Glasspad.app, no Apple account needed
make build-ios     # the iPhone app for the simulator, unsigned
make web-dev       # the website with live reload (run make web-deps once first)
```

Every shell script here answers `--help` (or `-h`) with its purpose, usage and settings, and
does nothing else when asked for help.

## Make tasks

| Task | What it runs |
| --- | --- |
| `make help` | Lists every task. The default when you type `make`. |
| `make doctor` | Checks for swift, Xcode, xcodegen, node, npm, the web packages, shellcheck and Pillow. Read only. |
| `make test` | `scripts/test.sh`. Pass swift test options with `ARGS`, for example `make test ARGS="--filter Layout"`. |
| `make build-ios` | `xcodegen generate`, then `xcodebuild` for the iOS Simulator with code signing off. The app lands in this checkout's build folder (see [Where things go](#where-things-go)); the last line prints the path. |
| `make build-mac` | `scripts/build-mac.sh`. |
| `make install-mac` | `scripts/install-mac.sh`. |
| `make install-phone` | `scripts/install-phone.sh`. `DEVICE=<udid>` picks the iPhone. |
| `make autorefresh` | `scripts/setup-autorefresh.sh`. |
| `make live-check` | `scripts/live-check.sh`. Options go in `ARGS`, for example `ARGS=--install`. |
| `make web-deps` | `npm ci` in `web/`, from the lock file. |
| `make web` | `npm run build` in `web/`: copies screenshots, type checks, then builds `web/dist`. |
| `make web-dev` | `npm run dev` in `web/`: the Vite development server with live reload. |
| `make web-preview` | `npm run preview` in `web/`: serves the built `web/dist` on port 4173. |
| `make web-themes` | `scripts/web-themes.sh`. |
| `make icons` | `swift scripts/make-icons.swift`. |
| `make lint` | `scripts/lint.sh` when it exists. Otherwise: shell syntax of every script, shellcheck (errors fail, warnings are shown; skipped if not installed), Python syntax, and the web type check. |
| `make clean` | Removes this checkout's build folders and prints each one. See [Cleaning](#cleaning). |

## Building and testing

### `test.sh`

Runs every Swift package's tests (`Packages/*`), then `tests/installer-test.sh`, then the main
thread check (`check-main-thread.py`). Every part runs even when an earlier one fails; the
script exits 1 at the end and names what failed. CI runs this on every push and pull request.

- Usage: `scripts/test.sh [swift test arguments]`, for example `scripts/test.sh --filter Layout`.
- Environment: `DEVELOPER_DIR` (which Xcode or command line tools), `GLASSPAD_BUILD_ROOT` (where
  builds go), `CI` (set by CI: a failed timing test gets one more run on its own, and the log
  names it).
- Works with only the command line tools installed. Needs no iPhone, Apple account or network.

### `build-mac.sh`

Builds the Mac menu bar app with SwiftPM (Swift's own build tool, no Xcode project needed) and
assembles `build/Glasspad.app`, ad hoc signed (signed without a certificate, which is enough to
run it on this Mac). Does not launch or install it.

- Usage: `scripts/build-mac.sh`
- Environment: `GLASSPAD_VERSION` (default: `MARKETING_VERSION` in `project.yml`),
  `GLASSPAD_BUILD_NUMBER` (default: 1), `GLASSPAD_BUILD_ROOT`, `DEVELOPER_DIR`.
- Writes only `build/Glasspad.app` and the SwiftPM build folder.

### `toolchain.sh`

Shared by `test.sh`, `build-mac.sh` and `visual-check-mac.sh`. Source it, do not run it. It
finds the active toolchain, adds the flags swift-testing needs when only the command line tools
are installed, and sets `GP_BUILD_ROOT`, the build folder for this checkout. It has no
`set -euo pipefail` on purpose: a sourced file would change the shell options of the script
that sources it.

### `web-themes.sh` and `web-themes/main.swift`

Compiles the app's theme catalog (`Packages/GlasspadKit/Sources/GlasspadKit/Theme`) together
with `web-themes/main.swift` into a temporary tool, and rewrites the theme list in
`web/src/themes.ts` from it. Run it after adding or changing a theme.

- Usage: `scripts/web-themes.sh`
- Needs `swiftc`. Changes only `web/src/themes.ts`; the temporary folder is removed on exit.

### `make-icons.swift`

Draws every app icon with CoreGraphics (the same shapes as `docs/brand/icon.svg`) and writes
them into the asset catalogs under `Apps/iOS/Resources` and `Apps/Mac/Resources`.

- Usage: `swift scripts/make-icons.swift`, from the repo root.
- Overwrites the icon PNGs and their `Contents.json` files. Review the diff before committing.

## Installing

### `install.sh` (repo root)

The one command installer for people who are not developers:
`curl -fsSL https://raw.githubusercontent.com/Soham109/glasspad/main/install.sh | bash`. It
gets the source, checks Xcode, downloads XcodeGen (checking its published SHA-256 checksum),
installs the Mac app, installs the iPhone app and turns on automatic renewal. Where Apple needs
a person (signing in, a tap on the iPhone) it says exactly what to do and waits. Safe to run
again: finished steps are skipped.

- Environment: `GLASSPAD_HOME` (where the source goes, default `~/Projects/glasspad`),
  `GLASSPAD_SKIP_PHONE=1` (Mac only), `GLASSPAD_TEAM`, `GLASSPAD_DEVICE`, `GLASSPAD_FORCE=1`
  (rebuild even when nothing changed), `GLASSPAD_WAIT_LIMIT=N` (seconds to wait for a step).
  The tests also use `GLASSPAD_REPO_URL`, `GLASSPAD_XCODE`, `GLASSPAD_APP`, `GLASSPAD_POLL`,
  `GLASSPAD_TTY`, `GLASSPAD_EXTRA_PATH` and `GLASSPAD_NONINTERACTIVE`.
- Exit codes: 0 done, 1 something failed, 2 it needed a person and nobody was there.
- Safety: it may ask for your password once, to accept the Xcode license
  (`sudo xcodebuild -license accept`). Everything runs inside one `main()` function, so a half
  downloaded copy never runs.

### `install-mac.sh`

Builds the Mac app with `build-mac.sh`, copies it to `/Applications/Glasspad.app` and signs it
with your Apple Development certificate, so macOS keeps its Accessibility permission across
updates. With no certificate it signs ad hoc. Then starts the app.

- Usage: `scripts/install-mac.sh`
- Environment: `GLASSPAD_SIGN_IDENTITY` (the SHA-1 of the certificate; `install.sh` passes
  it), `GLASSPAD_TEAM` (otherwise the first Apple Development certificate of this team).
- Safety: quits a running Glasspad and replaces `/Applications/Glasspad.app`. Records the
  installed revision in `~/Library/Application Support/Glasspad/mac-install.env`.

### `install-phone.sh`

Builds the iPhone app and installs it over a cable or Wi-Fi. With a free Apple account the
install lasts 7 days; `setup-autorefresh.sh` makes your Mac renew it.

- Usage: `scripts/install-phone.sh [device id]`. Without an id it picks the first paired
  iPhone that `xcrun devicectl list devices` shows.
- Environment: `GLASSPAD_TEAM` (default: read from your Apple Development certificate),
  `GLASSPAD_REV` (git revision to build, default `HEAD`), `GLASSPAD_CONFIG` (`Release` by
  default, or `Debug`), `DEVELOPER_DIR`.
- Safety: builds from a clean copy of the revision in `~/Library/Caches/glasspad-phone`, a git
  worktree (a second checkout of the same repo) that this script removes and recreates each
  run, so never work in that folder. Xcode's build goes to `~/Library/Caches/glasspad-dd-phone`.
  Records what it installed in `~/Library/Application Support/Glasspad/phone-install.env`.

### `setup-autorefresh.sh`

Turns on automatic renewal: installs a LaunchAgent (a background job macOS runs for you) at
`~/Library/LaunchAgents/com.soham109.glasspad.refresh.plist` that runs `refresh-phone.sh` from
this checkout every hour. Run `install-phone.sh` once first.

- Usage: `scripts/setup-autorefresh.sh [--remove]`. `--remove` turns it off and deletes the
  LaunchAgent.
- Safe to run again: it does nothing when the same job is already on.

### `refresh-phone.sh`

What the hourly job runs. Does nothing until the install is 5 days old, waits while Glasspad
is in use on the iPhone, and reinstalls the exact revision you last installed (so an unfinished
change never reaches the phone). In the install's last day it renews even while the app is in
use, and says so in a notification.

- Usage: `scripts/refresh-phone.sh [--now]`. `--now` renews right away, whatever the age.
- Output goes to `~/Library/Logs/Glasspad/refresh.log`, not the terminal. Each run writes its
  outcome to `~/Library/Application Support/Glasspad/refresh-status.json`, which the Mac app
  shows in Settings > iPhone.
- Uses `set -uo pipefail` without `-e` on purpose: a failed step must still reach the end,
  record its status and notify you.

## Checking

### `live-check.sh`

The guided live check on this Mac ([docs/LIVE-CHECK.md](../docs/LIVE-CHECK.md)): Glasspad tries
each Mac feature for real, one step at a time in its own window, puts the Mac back after each
one, and writes `~/Library/Logs/Glasspad/live-check-<date>.md`.

- Usage: `scripts/live-check.sh [--install] [--include-disruptive]`. `--install` installs this
  checkout first; `--include-disruptive` adds Lock Screen, Sleep Display, Sleep Mac, Empty
  Trash and Eject All.
- Safety: quits the running Glasspad (your iPhone disconnects) and starts it again at the end.
  It really changes things such as Dark Mode, volume, brightness and window positions (and puts
  each one back), so run it when you are at the Mac.

### `check-main-thread.py` and `main-thread-allowlist.txt`

Fails when code that runs on the main thread makes a call that can block it (the menu bar icon
froze once that way). Reviewed exceptions go in `main-thread-allowlist.txt`, one per line with a
reason. Part of `test.sh`.

- Usage: `python3 -I scripts/check-main-thread.py [repo root]`, or `--self-test`. Exit 1 when
  it finds something.

### `visual-check.sh`, `visual-screens.txt` and `visual-diff.py`

Visual regression check for the iPhone app, in the simulator only: takes every screen listed in
`visual-screens.txt` in each theme and compares it with a baseline folder, writing side by side
pictures of what changed and a `report.md`.

- Usage: `scripts/visual-check.sh --baseline DIR [--record] [--only REGEX] ...` (see `--help`
  for all options). `--record` makes the baseline.
- Environment: `GLASSPAD_VISUAL_BASELINE`, `GLASSPAD_DEMO_ICONS`, `GLASSPAD_VISUAL_WAIT`,
  `GLASSPAD_MAX_LOAD` (wait while the Mac's load average is above this before each launch).
- Needs Xcode, xcodegen, a simulator named `GP-guard` (or `--sim NAME`) and Pillow for python3.
  Boots that one simulator and shuts it down at the end. Never touches a real iPhone or your
  screen.
- Exit codes: 0 nothing changed beyond its allowance, 1 something did, 2 setup error.
- `visual-diff.py <baseline> <current> <out>` does the comparing; `--allow name=percent`,
  `--default`, `--fuzz`, `--current-only`, `--no-island`.

### `visual-check-mac.sh`

The same for the Mac app's windows, in light and dark. Draws them off screen with the snapshot
tests in `Apps/Mac/Tests`; no window appears and nothing is clicked.

- Usage: `scripts/visual-check-mac.sh --baseline DIR [--record] [--out DIR]`
- Exit codes as above. Needs Pillow for python3.

### `tests/installer-test.sh` and `tests/stubs/`

Tests `install.sh` and the phone scripts against fake Apple tools (`tests/stubs`: xcrun,
xcodebuild, security, sudo, curl, brew, launchctl and more), in a scratch home folder whose path
has spaces in it. Needs no iPhone, Xcode or Apple account, and nothing outside its temporary
folder is touched. Part of `test.sh`.

- Usage: `scripts/tests/installer-test.sh`
- Uses `set -uo pipefail` without `-e` on purpose: a failing case is counted and the run goes
  on to the next one.

## Where things go

| What | Where |
| --- | --- |
| SwiftPM builds (tests, Mac app) and `make build-ios` | `~/Library/Caches/glasspad-build/<checkout name>-<hash>/`, one folder per checkout so parallel worktrees never share a build. `GLASSPAD_BUILD_ROOT` overrides it. |
| Mac app build | `build/Glasspad.app` |
| iPhone install build | `~/Library/Caches/glasspad-phone` (source copy) and `~/Library/Caches/glasspad-dd-phone` (Xcode build) |
| Install records | `~/Library/Application Support/Glasspad/` (`mac-install.env`, `phone-install.env`, `refresh-status.json`) |
| Logs | `~/Library/Logs/Glasspad/` (`refresh.log`, live check reports) |
| Website build | `web/dist`, plus generated images in `web/public/img` |

Builds live outside the repo because a checkout in an iCloud synced folder gets Finder
information attached to its files, and `codesign` then refuses the bundles.

## Cleaning

`make clean` removes, and prints, only these: `build/`, the generated `Glasspad.xcodeproj`,
`web/dist`, `web/public/img`, any `.build` folder under `Apps/` or `Packages/`, and this
checkout's own folder under `~/Library/Caches/glasspad-build`. If `GLASSPAD_BUILD_ROOT` points
anywhere else it leaves that folder alone and says so. It never touches the iPhone install
folders, `web/node_modules`, your installed apps, logs or settings.

## Conventions for new scripts

- Start with `#!/usr/bin/env bash`, a comment block that says what the script does, a
  `Usage:` line and every environment variable it reads, then `set -euo pipefail`. If the
  script must not stop at the first error, say why in a comment next to `set -uo pipefail`.
- Answer `-h` and `--help` by printing that comment block:
  `awk 'NR>1 && /^#/ {sub(/^# ?/, ""); print; next} NR>1 {exit}' "$0"`.
- `cd "$(dirname "$0")/.."` so it works from any folder.
- Print a `== step` line before each long step, errors to stderr, and end with one line that
  says what was made or where.
- Keep build products out of the repo (use `GP_BUILD_ROOT` from `toolchain.sh`).
- Exit 0 on success, 1 on failure, 2 on a usage or setup error.
- Add it to this file and, if people run it often, to the `Makefile`.
