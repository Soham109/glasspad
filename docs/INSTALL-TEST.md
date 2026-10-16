# Installer test, 15 Oct 2026

## How to check the installer today

| What | How |
| --- | --- |
| Every case with fake Apple tools | `scripts/test.sh` (runs `scripts/tests/installer-test.sh` after the package tests), or that script alone. 77 checks passed on 16 Oct 2026. |
| The fakes | `scripts/tests/stubs`: xcrun and devicectl, xcodebuild, xcodegen, security, openssl, codesign, sudo, curl, brew, launchctl, open, osascript and pkill. Each reads what to do from files in a scratch folder. |
| A real run on this Mac | `GLASSPAD_HOME=<scratch folder> bash -c "$(curl -fsSL https://raw.githubusercontent.com/Soham109/glasspad/main/install.sh)"` |
| A real run of a local copy | `GLASSPAD_REPO_URL=<path to a clone> bash < install.sh` |

The scripts it drives: `scripts/install-mac.sh` (build, install in Applications, sign with your
certificate), `scripts/install-phone.sh` (build and install on the iPhone),
`scripts/setup-autorefresh.sh` (the hourly renewal job) and `scripts/refresh-phone.sh` (what that
job runs). The installer and these scripts have not changed since the runs below. The Mac app's
menu item is now called **Pair Your iPhone…**; the installer's last line still says "Pair new
iPhone".

## The runs

What a real run of the one-line installer printed, on a Mac that already had Xcode 27, an
Apple Development certificate (team V8PCS2UL23) and a paired iPhone on the same Wi-Fi. No
terminal was attached (standard input was `/dev/null`, `/dev/tty` could not be opened), which is
how the installer runs inside automation or when it is piped somewhere unusual.

## Run 1: install.sh from GitHub main, before the fixes

```
GLASSPAD_HOME=/tmp/gp-e2e/glasspad bash -c "$(curl -fsSL https://raw.githubusercontent.com/Soham109/glasspad/main/install.sh)" </dev/null
```

```
1. Xcode
  ✓ Xcode 27.0

2. Build tools
  ✓ XcodeGen 2.46.0

3. Glasspad source
  ✓ /tmp/gp-e2e/glasspad

4. Your Apple account (free)
  ✓ Team V8PCS2UL23

5. Mac app
/tmp/gp-e2e/glasspad/build/Glasspad.app/Contents/Frameworks/GlasspadNowPlaying.dylib: replacing existing signature
/tmp/gp-e2e/glasspad/build/Glasspad.app: replacing existing signature
/Applications/Glasspad.app/Contents/Frameworks/GlasspadNowPlaying.dylib: replacing existing signature
/Applications/Glasspad.app: replacing existing signature
  ✓ Installed in Applications and running in your menu bar
  → Allow Accessibility so Glasspad can move the pointer. Opening the right page:
  System Settings > Privacy & Security > Accessibility > switch on Glasspad.
  (press Return when done) bash: line 25: /dev/tty: Device not configured

6. iPhone
  → On the iPhone: Settings > Privacy & Security > Developer Mode (at the bottom) > On.
  → It restarts; after unlocking, tap Turn On and enter your passcode.
  waiting: Developer Mode....
```

It waited here forever and was stopped by hand. Developer Mode **was** on. What went wrong:

- **Developer Mode was never detected (would hang every user).** The check was
  `devicectl ... | grep -q "Developer Mode Status: Enabled"` under `set -o pipefail`. `grep -q`
  quits at the first match, devicectl is still writing the rest of its report and dies of
  SIGPIPE (exit 141), so the whole check fails every time. Reproduced 3 out of 3 in bash.
  The same pattern sat in step 7 (`setup-autorefresh.sh | head -1`), and in an `awk ... exit`
  over the device list.
- **No terminal:** "press Return" printed a raw `/dev/tty: Device not configured` error;
  the license step (`sudo ... </dev/tty`) would have stopped the script; every wait was endless.
- **codesign noise** ("replacing existing signature") leaked into the friendly output.

## Run 2: fixed installer, full install

Same Mac, piped into bash exactly like the README (`bash < install.sh`), no terminal, and an
install folder with a space in its name. The source came from a local copy of GitHub main with
the fixed scripts committed on top (`GLASSPAD_REPO_URL`), because the fixed scripts are not on
GitHub yet.

```
1. Xcode
  ✓ Xcode 27.0

2. Build tools
  ✓ XcodeGen 2.46.0

3. Glasspad source
  ✓ /tmp/gp-e2e/glass pad (f20b012)

4. Your Apple account (free)
  ✓ Team V8PCS2UL23

5. Mac app
  Building the Mac app...
  ✓ Installed in Applications and running in your menu bar
  → Allow Accessibility so Glasspad can move the pointer. Opening the right page:
  System Settings > Privacy & Security > Accessibility > switch on Glasspad.

6. iPhone
  ✓ Soham’s iPhone
  Building and installing (the first build takes a while)...
  ✓ Installed f20b012
  ✓ Glasspad is open on your iPhone

7. Automatic renewal
  ✓ Automatic renewal is on. Your Mac checks hourly and renews when the install is 5 days old.
  Free Apple accounts expire apps after 7 days. Your Mac now renews it over Wi-Fi by itself.

Done. What is installed:
  Xcode           27.0 (/Applications/Xcode.app)
  Source          /tmp/gp-e2e/glass pad at f20b012
  Apple team      V8PCS2UL23
  Mac app         /Applications/Glasspad.app (f20b012, installed now)
  iPhone          Soham’s iPhone (00008160-000E614036400036), f20b012
  Auto-renew      on (checks hourly, log: ~/Library/Logs/Glasspad/refresh.log)

  Pair: click the Glasspad icon in your Mac's menu bar > Pair new iPhone, then scan the code
  with the Glasspad app (or the iPhone Camera).
```

Exit code 0. Nothing waited: the phone was reachable, Developer Mode on and the app already
trusted. Without a terminal, "press Return" is skipped instead of failing.

## Run 3: the same command again

Finished in 6 seconds, exit code 0, nothing rebuilt:

```
5. Mac app
  ✓ Already installed (f20b012), nothing to do

6. iPhone
  ✓ Soham’s iPhone
  ✓ Already installed (f20b012), nothing to do
  ✓ Glasspad is open on your iPhone

7. Automatic renewal
  ✓ Automatic renewal is already on.
```

## Run 4: `GLASSPAD_SKIP_PHONE=1`

```
6. iPhone
  Skipped (GLASSPAD_SKIP_PHONE=1). Run the installer again with your iPhone nearby to add it.

7. Automatic renewal
  Skipped: it needs the iPhone install first.
```

Exit code 0. (Since then, when renewal was set up by an earlier run, step 7 says
"Left as it was (set up by an earlier run)." instead.)

## Not reproducible on this Mac, covered by the fake-tools tests instead

`scripts/tests/installer-test.sh` (run by `scripts/test.sh`) replaces xcrun/devicectl, security,
xcodebuild, sudo, curl, brew, launchctl and the other tools listed above with small fakes, and runs install.sh piped into bash
with a home folder whose path has spaces. Cases: a fresh Mac (license not accepted, no password
available, then accepted; XcodeGen download rejected by its checksum, Homebrew fallback), a second
run that skips everything, uncommitted local changes, offline without Homebrew, no iPhone, a
paired iPhone that is out of reach, skipping the phone, Developer Mode off (then switched on while
waiting), the old text-only devicectl report, an untrusted app (then trusted while waiting), a
locked iPhone, an unknown launch error, two Apple teams (first one, `GLASSPAD_TEAM`, remembered
from last time, chosen at the prompt), no certificate, a folder in the way, and the renewal job
(not due, due, app open on the phone, app open on the last day, phone away).

When a step needs a person and nobody is at the terminal, the installer stops with exit code 2
and says what to do, for example:

```
  Stopped: Could not reach your iPhone.
    Unlock it and bring it onto this Mac's Wi-Fi (or plug it in), then run the installer again.
    To set up only the Mac: GLASSPAD_SKIP_PHONE=1 before the command.
    Run the installer again once that is done; finished steps are skipped.
```
