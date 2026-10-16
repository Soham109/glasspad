#!/usr/bin/env bash
# Glasspad installer. One command sets up everything:
#   curl -fsSL https://raw.githubusercontent.com/Soham109/glasspad/main/install.sh | bash
#
# It does every step it can by itself and, where Apple requires a person (signing in, a tap on
# the iPhone), it tells you exactly what to click and waits until it sees that you have done it.
# Safe to run again at any time: finished steps are skipped.
#
# Options (environment variables):
#   GLASSPAD_HOME=path     Where the source goes. Default: ~/Projects/glasspad
#   GLASSPAD_SKIP_PHONE=1  Set up only the Mac (no iPhone at hand, or a run without a person).
#   GLASSPAD_TEAM=ID       Which Apple team to sign with, when you have more than one.
#   GLASSPAD_DEVICE=UDID   Which iPhone to use, when several are paired with this Mac.
#   GLASSPAD_FORCE=1       Rebuild and reinstall even when nothing changed.
#   GLASSPAD_WAIT_LIMIT=N  Give up waiting for a step after N seconds. Default: wait as long as it
#                          takes when you are at a terminal, 120 seconds when nobody is.
#
# Exit codes: 0 done, 1 something failed, 2 it needed a person and nobody was there.
#
# Everything lives inside main(), so a half-downloaded copy never runs, and nothing the script
# starts can swallow the rest of it when it is piped into bash.

main() {
set -euo pipefail

REPO_URL="${GLASSPAD_REPO_URL:-https://github.com/Soham109/glasspad.git}"
DEST="${GLASSPAD_HOME:-$HOME/Projects/glasspad}"
SUPPORT="$HOME/Library/Application Support/Glasspad"
BIN="$SUPPORT/bin"
LOGS="$HOME/Library/Logs/Glasspad"
XCODEGEN_VERSION="2.46.0"
# GitHub's published digest for xcodegen.zip of that release.
XCODEGEN_SHA256="4d9e34b62172d645eed6457cac13fc222569974098ef4ee9c3368bedf0196806"
BUNDLE_ID="com.soham109.glasspad.ios"
POLL="${GLASSPAD_POLL:-3}"
TTY="${GLASSPAD_TTY:-/dev/tty}"
# Appended, not prepended: tools you already have win over the ones this script adds.
export PATH="$PATH:$BIN:${GLASSPAD_EXTRA_PATH-/opt/homebrew/bin:/usr/local/bin}"
mkdir -p "$LOGS"

# A person is there when the terminal can be opened (true even when this script is piped in).
if [ "${GLASSPAD_NONINTERACTIVE:-0}" != 1 ] && (exec <"$TTY") 2>/dev/null; then
  INTERACTIVE=1; LIMIT="${GLASSPAD_WAIT_LIMIT:-0}"
else
  INTERACTIVE=0; LIMIT="${GLASSPAD_WAIT_LIMIT:-120}"
fi

if [ -t 1 ]; then bold=$'\033[1m'; dim=$'\033[2m'; green=$'\033[32m'; red=$'\033[31m'; reset=$'\033[0m'
else bold=; dim=; green=; red=; reset=; fi
step()  { printf '\n%s%s%s\n' "$bold" "$1" "$reset"; }
ok()    { printf '  %s✓%s %s\n' "$green" "$reset" "$1"; }
say()   { printf '  %s\n' "$1"; }
todo()  { printf '  %s→%s %s\n' "$bold" "$reset" "$1"; }
fail()  { printf '\n  %s✗ %s%s\n' "$red" "$1" "$reset" >&2; shift
          for line in "$@"; do printf '    %s\n' "$line" >&2; done; exit 1; }
# Stops when the next step needs a person and nobody is at the terminal.
needs_person() { printf '\n  %sStopped: %s%s\n' "$red" "$1" "$reset" >&2; shift
          for line in "$@"; do printf '    %s\n' "$line" >&2; done
          printf '    Run the installer again once that is done; finished steps are skipped.\n' >&2
          exit 2; }

# wait_for "what" check-command...: polls until the check succeeds. Returns 1 after LIMIT seconds
# (0 means no limit). Prints a quiet heartbeat.
wait_for() {
  local what="$1" start; shift; start=$(date +%s)
  printf '  %swaiting for %s%s' "$dim" "$what" "$reset"
  until "$@" >/dev/null 2>&1; do
    if [ "$LIMIT" -gt 0 ] && [ $(( $(date +%s) - start )) -ge "$LIMIT" ]; then
      printf ' gave up after %ss\n' "$LIMIT"; return 1
    fi
    printf '.'; sleep "$POLL"
  done
  printf ' done\n'
}
# Waits for Return at the terminal. Without one it just carries on.
pause() {
  [ "$INTERACTIVE" = 1 ] || return 0
  printf '  %s(press Return when done)%s ' "$dim" "$reset"; read -r _ <"$TTY" || true
}
# ask "question" default: prints the answer typed at the terminal, or the default.
ask() {
  local reply=""
  if [ "$INTERACTIVE" = 1 ]; then printf '  %s ' "$1" >&2; read -r reply <"$TTY" || true; fi
  printf '%s' "${reply:-$2}"
}
# Runs a quiet sub-step with its output in a log; on failure shows the end of the log.
run_logged() {
  local name="$1" log="$LOGS/$1.log"; shift
  if "$@" </dev/null >"$log" 2>&1; then return 0; fi
  printf '\n' >&2; tail -n 25 "$log" | sed 's/^/    | /' >&2
  fail "The $name step failed." "Full log: $log" \
    "If it is not clear what went wrong, open an issue at github.com/Soham109/glasspad/issues and attach that log."
}

[ "$(uname)" = "Darwin" ] || fail "Glasspad needs a Mac."

SUMMARY=""
note() { SUMMARY="$SUMMARY$(printf '  %-15s %s' "$1" "$2")"$'\n'; }
# field file NAME: the value of NAME in one of our saved state files (empty when unset).
# A reminder for whoever edits this: with pipefail, `cmd | grep -q` or `cmd | head` can fail at
# random, because the reader quits early and cmd dies of SIGPIPE. Read whole outputs instead.
in_list() { case $'\n'"$2"$'\n' in *$'\n'"$1"$'\n'*) return 0 ;; esac; return 1; }
# shellcheck disable=SC1090
field() { [ -f "$1" ] || return 0; ( set +eu; . "$1" >/dev/null 2>&1; eval "printf '%s' \"\${$2:-}\"" ); }

# 1. Xcode -----------------------------------------------------------------------------------
step "1. Xcode"
find_xcode() {
  local d app
  if [ -n "${GLASSPAD_XCODE:-}" ]; then printf '%s' "$GLASSPAD_XCODE"; return 0; fi
  # An Xcode you already chose (DEVELOPER_DIR or xcode-select) wins. The command line tools alone
  # cannot build iPhone apps, so a choice pointing at them is skipped.
  for d in "${DEVELOPER_DIR:-}" "$(xcode-select -p 2>/dev/null || true)"; do
    case "$d" in *.app/Contents/Developer)
      [ -x "$d/usr/bin/xcodebuild" ] && { printf '%s' "${d%/Contents/Developer}"; return 0; } ;;
    esac
  done
  for app in /Applications/Xcode.app /Applications/Xcode*.app; do
    [ -x "$app/Contents/Developer/usr/bin/xcodebuild" ] && { printf '%s' "$app"; return 0; }
  done
  return 1
}
has_xcode() { find_xcode >/dev/null; }
if ! has_xcode; then
  todo "Install Xcode from the App Store (free). Opening it for you."
  open "macappstore://apps.apple.com/app/id497799835" >/dev/null 2>&1 || true
  [ "$INTERACTIVE" = 1 ] || needs_person "Xcode is not installed." "Install it from the App Store."
  wait_for "Xcode to finish installing" has_xcode || needs_person "Xcode is not installed yet."
fi
XCODE="$(find_xcode)"
# Every Apple tool below (xcodebuild, xcrun, swift, clang, git) follows DEVELOPER_DIR, so this
# works even when xcode-select still points at the command line tools.
export DEVELOPER_DIR="$XCODE/Contents/Developer"
XCODEBUILD="$DEVELOPER_DIR/usr/bin/xcodebuild"
# -license check: 0 when accepted. -checkFirstLaunchStatus: 0 when the one-time setup is done.
if ! "$XCODEBUILD" -license check >/dev/null 2>&1 || ! "$XCODEBUILD" -checkFirstLaunchStatus >/dev/null 2>&1; then
  todo "Xcode needs its one-time setup and license. Enter your Mac password if asked."
  # sudo clears DEVELOPER_DIR, so the full path makes sure it is this Xcode that gets set up.
  if [ "$INTERACTIVE" = 1 ]; then
    if ! { sudo "$XCODEBUILD" -license accept && sudo "$XCODEBUILD" -runFirstLaunch >/dev/null; } <"$TTY"; then
      fail "Xcode's setup did not finish." "Run: sudo \"$XCODEBUILD\" -license accept && sudo \"$XCODEBUILD\" -runFirstLaunch"
    fi
  elif ! { sudo -n "$XCODEBUILD" -license accept && sudo -n "$XCODEBUILD" -runFirstLaunch >/dev/null; } </dev/null 2>/dev/null; then
    needs_person "Xcode needs your Mac password to finish its one-time setup." \
      "Run this in Terminal: sudo \"$XCODEBUILD\" -license accept && sudo \"$XCODEBUILD\" -runFirstLaunch"
  fi
fi
XCODE_VERSION="$("$XCODEBUILD" -version 2>/dev/null | awk 'NR==1 {print $2}')" \
  || fail "Xcode at $XCODE does not start." "Open it once from Applications, then run this again."
[ -n "$XCODE_VERSION" ] || fail "Xcode at $XCODE does not start." "Open it once from Applications, then run this again."
ok "Xcode $XCODE_VERSION"
note "Xcode" "$XCODE_VERSION ($XCODE)"

# 2. Build tools -----------------------------------------------------------------------------
step "2. Build tools"
get_xcodegen() {
  local tmp sum
  tmp="$(mktemp -d)"
  if ! curl -fsSL --retry 3 -o "$tmp/xcodegen.zip" \
      "https://github.com/yonaskolb/XcodeGen/releases/download/${XCODEGEN_VERSION}/xcodegen.zip"; then
    rm -rf "$tmp"; say "Could not download XcodeGen (offline, or GitHub is unreachable)."; return 1
  fi
  sum="$(shasum -a 256 "$tmp/xcodegen.zip" | awk '{print $1}')"
  if [ "$sum" != "$XCODEGEN_SHA256" ]; then
    rm -rf "$tmp"; say "The XcodeGen download did not match its published checksum, so it was not used."; return 1
  fi
  unzip -q "$tmp/xcodegen.zip" -d "$tmp" && [ -x "$tmp/xcodegen/bin/xcodegen" ] || { rm -rf "$tmp"; return 1; }
  mkdir -p "$BIN"
  rm -rf "$SUPPORT/xcodegen" && mv "$tmp/xcodegen" "$SUPPORT/xcodegen"
  ln -sf "$SUPPORT/xcodegen/bin/xcodegen" "$BIN/xcodegen"
  rm -rf "$tmp"
}
if ! command -v xcodegen >/dev/null 2>&1; then
  say "Downloading XcodeGen $XCODEGEN_VERSION (turns the project description into an Xcode project)..."
  if ! get_xcodegen; then
    if command -v brew >/dev/null 2>&1; then
      say "Trying Homebrew instead..."
      brew install xcodegen >/dev/null 2>&1 || true
    fi
    command -v xcodegen >/dev/null 2>&1 || fail "Could not install XcodeGen." \
      "Check your internet connection and run the installer again."
  fi
fi
XCODEGEN_V="$(xcodegen --version 2>/dev/null | awk '{print $NF}')" || true
[ -n "$XCODEGEN_V" ] || fail "XcodeGen is installed but does not run ($(command -v xcodegen))."
ok "XcodeGen $XCODEGEN_V"

# 3. Source ----------------------------------------------------------------------------------
step "3. Glasspad source"
if [ -d "$DEST/.git" ]; then
  if [ -n "$(git -C "$DEST" status --porcelain --untracked-files=no 2>/dev/null)" ]; then
    say "You have changes in this folder that are not committed, so it was not updated."
    say "The iPhone build uses the last commit, without those changes."
  elif ! git -C "$DEST" pull -q --ff-only </dev/null >/dev/null 2>&1; then
    say "Could not update (offline, or the folder has its own commits). Using what is there."
  fi
elif [ -e "$DEST" ] && [ -n "$(ls -A "$DEST" 2>/dev/null)" ]; then
  fail "$DEST already exists and is not a copy of Glasspad." \
    "Move it away, or choose another folder: GLASSPAD_HOME=/path/to/folder"
else
  mkdir -p "$(dirname "$DEST")"
  git clone -q "$REPO_URL" "$DEST" </dev/null || fail "Could not download Glasspad from $REPO_URL." \
    "Check your internet connection and run the installer again."
fi
cd "$DEST"
REV="$(git rev-parse HEAD)"
ok "$DEST (${REV:0:7})"
note "Source" "$DEST at ${REV:0:7}"

# 4. Apple account -----------------------------------------------------------------------------
step "4. Your Apple account (free)"
# Prints "TEAM<tab>SHA-1<tab>certificate name" for each valid Apple Development identity.
identities() {
  local hash name pems
  pems="$(security find-certificate -a -Z -p -c "Apple Development" 2>/dev/null || true)"
  security find-identity -v -p codesigning 2>/dev/null \
    | sed -n 's/^ *[0-9]*) \([0-9A-F]\{40\}\) "\(Apple Development: .*\)"$/\1	\2/p' \
    | while IFS='	' read -r hash name; do
        team="$(printf '%s\n' "$pems" | awk -v h="$hash" '/^SHA-1 hash:/ {on = ($3 == h)} on && /BEGIN CERT/ {p=1} p && on {print} /END CERT/ {p=0}' \
          | openssl x509 -noout -subject 2>/dev/null | sed -n 's/.*OU *= *\([A-Z0-9]\{10\}\).*/\1/p')" || true
        [ -n "$team" ] && printf '%s\t%s\t%s\n' "$team" "$hash" "$name"
      done
}
teams() { identities | cut -f1 | awk '!seen[$0]++'; }
has_team() { [ -n "$(teams)" ]; }
if ! has_team; then
  todo "In Xcode: Settings (Cmd+,) > Apple Accounts > + > sign in with your Apple ID."
  open -a "$XCODE" >/dev/null 2>&1 || true
  [ "$INTERACTIVE" = 1 ] || needs_person "No Apple Development certificate on this Mac yet." \
    "Sign in to Xcode with your Apple ID, pick your team once in the Glasspad project's Signing tab."
  pause
  xcodegen -q >/dev/null 2>&1 || true
  todo "Xcode is opening the Glasspad project. Click Glasspad (top of the left sidebar),"
  todo "then target 'Glasspad iOS' > Signing & Capabilities > Team > pick your name."
  open -a "$XCODE" Glasspad.xcodeproj >/dev/null 2>&1 || true
  wait_for "your signing certificate" has_team || needs_person "No signing certificate appeared."
fi
ALL_TEAMS="$(teams)"
TEAM="${GLASSPAD_TEAM:-}"
if [ -z "$TEAM" ] && [ "$(printf '%s\n' "$ALL_TEAMS" | wc -l | tr -d ' ')" = 1 ]; then
  TEAM="$ALL_TEAMS"
fi
if [ -z "$TEAM" ]; then
  # Several teams: prefer the one used last time, then the one picked in Xcode for this project.
  prev="$(field "$SUPPORT/phone-install.env" GLASSPAD_TEAM)"
  proj="$(sed -n 's/.*DEVELOPMENT_TEAM = \([A-Z0-9]\{10\}\);.*/\1/p' Glasspad.xcodeproj/project.pbxproj 2>/dev/null | awk 'NR == 1' || true)"
  for cand in "$prev" "$proj"; do
    if [ -n "$cand" ] && in_list "$cand" "$ALL_TEAMS"; then TEAM="$cand"; break; fi
  done
fi
if [ -z "$TEAM" ]; then
  say "This Mac has certificates for more than one Apple team:"
  i=0; while IFS='	' read -r t _ n; do i=$((i+1)); say "  $i) $t  $n"; done <<EOF
$(identities | awk -F'\t' '!seen[$1]++')
EOF
  pick="$(ask "Which one should sign Glasspad? [1]" 1)"
  case "$pick" in ''|*[!0-9]*) pick=1 ;; esac
  TEAM="$(printf '%s\n' "$ALL_TEAMS" | sed -n "${pick}p")"
  [ -n "$TEAM" ] || TEAM="$(printf '%s\n' "$ALL_TEAMS" | awk 'NR == 1')"
  [ "$INTERACTIVE" = 1 ] || say "Using the first one. To choose: GLASSPAD_TEAM=<team> before the command."
fi
SIGN_HASH="$(identities | awk -F'\t' -v t="$TEAM" '$1 == t && h == "" {h = $2} END {print h}')"
[ -n "$SIGN_HASH" ] || fail "No valid Apple Development certificate for team $TEAM." \
  "Teams on this Mac: $(printf '%s' "$ALL_TEAMS" | tr '\n' ' ')"
export GLASSPAD_TEAM="$TEAM" GLASSPAD_SIGN_IDENTITY="$SIGN_HASH"
ok "Team $TEAM"
note "Apple team" "$TEAM"

# 5. Mac app ---------------------------------------------------------------------------------
step "5. Mac app"
APP="${GLASSPAD_APP:-/Applications/Glasspad.app}"
MAC_STATE="$SUPPORT/mac-install.env"
mac_rev="$(field "$MAC_STATE" GLASSPAD_MAC_REV)"
dirty="$(git status --porcelain --untracked-files=no 2>/dev/null)"
if [ "${GLASSPAD_FORCE:-0}" != 1 ] && [ -z "$dirty" ] && [ "$mac_rev" = "$REV" ] && [ -d "$APP" ] \
   && codesign --verify --strict "$APP" >/dev/null 2>&1; then
  ok "Already installed (${REV:0:7}), nothing to do"
  note "Mac app" "$APP (${REV:0:7}, already up to date)"
else
  first_mac=0; [ -f "$MAC_STATE" ] || first_mac=1
  say "Building the Mac app..."
  run_logged install-mac scripts/install-mac.sh
  ok "Installed in Applications and running in your menu bar"
  note "Mac app" "$APP (${REV:0:7}, installed now)"
  if [ "$first_mac" = 1 ]; then
    todo "Allow Accessibility so Glasspad can move the pointer. Opening the right page:"
    say  "System Settings > Privacy & Security > Accessibility > switch on Glasspad."
    open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility" >/dev/null 2>&1 || true
    pause
  fi
fi

# 6. iPhone ----------------------------------------------------------------------------------
step "6. iPhone"
PHONE_DONE=0
if [ "${GLASSPAD_SKIP_PHONE:-0}" = 1 ]; then
  say "Skipped (GLASSPAD_SKIP_PHONE=1). Run the installer again with your iPhone nearby to add it."
  note "iPhone" "skipped"
else
  TMPJ="$(mktemp -d)"; trap 'rm -rf "$TMPJ"' EXIT
  # Paired iPhones and iPads, as UDIDs, best guess first. Reads devicectl's JSON, which keeps
  # the same shape across Xcode versions (the table layout does not).
  paired() {
    local i=0 n kind
    xcrun devicectl list devices --quiet --json-output "$TMPJ/list.json" >/dev/null 2>&1 || return 0
    n="$(plutil -extract result.devices raw "$TMPJ/list.json" 2>/dev/null || echo 0)"
    while [ "$i" -lt "$n" ]; do
      x() { plutil -extract "result.devices.$i.$1" raw "$TMPJ/list.json" 2>/dev/null || true; }
      if [ "$(x hardwareProperties.reality)" = physical ] && [ "$(x hardwareProperties.platform)" = iOS ] \
         && [ "$(x connectionProperties.pairingState)" = paired ]; then
        kind="$(x hardwareProperties.deviceType)"
        printf '%s %s\n' "$([ "$kind" = iPhone ] && echo 0 || echo 1)" "$(x hardwareProperties.udid)"
      fi
      i=$((i+1))
    done | sort | awk '{print $2}'
  }
  # Asks the device itself: succeeds only when it is reachable right now, and saves its details.
  reach() { xcrun devicectl device info details --device "$1" --timeout 20 --quiet \
      --json-output "$TMPJ/details.json" >/dev/null 2>&1; }
  PREV_DEVICE="$(field "$SUPPORT/phone-install.env" GLASSPAD_DEVICE)"
  find_phone() {
    local d list
    list="$(paired)"
    [ -n "$list" ] || return 1
    for d in ${GLASSPAD_DEVICE:-} $PREV_DEVICE $list; do
      in_list "$d" "$list" || continue
      if reach "$d"; then DEVICE="$d"; printf '%s\n' "$d" >"$TMPJ/device"; return 0; fi
    done
    return 1
  }
  found_phone() { find_phone && [ -s "$TMPJ/device" ]; }
  DEVICE=""
  if ! find_phone; then
    if [ -z "$(paired)" ]; then
      todo "Plug your iPhone into this Mac with a cable, unlock it, and tap Trust on the iPhone."
    else
      todo "Your iPhone is paired but this Mac cannot reach it right now."
      todo "Unlock it and keep it on the same Wi-Fi as this Mac, or plug it in with a cable."
    fi
    say "No iPhone with you? Stop with Ctrl+C and run again with GLASSPAD_SKIP_PHONE=1 to set up the Mac only."
    wait_for "your iPhone" found_phone || needs_person "Could not reach your iPhone." \
      "Unlock it and bring it onto this Mac's Wi-Fi (or plug it in), then run the installer again." \
      "To set up only the Mac: GLASSPAD_SKIP_PHONE=1 before the command."
    DEVICE="$(cat "$TMPJ/device")"
  fi
  # "enabled", "disabled", or empty on iOS versions that have no Developer Mode at all.
  devmode_state() {
    local s
    s="$(plutil -extract result.deviceProperties.developerModeStatus raw "$TMPJ/details.json" 2>/dev/null || true)"
    if [ -z "$s" ]; then   # older devicectl: read the text report instead
      s="$(xcrun devicectl device info details --device "$DEVICE" 2>/dev/null \
        | awk -F'Developer Mode Status: *' 'NF > 1 && !s {split($2, w, /[^A-Za-z]/); s = tolower(w[1])} END {print s}' || true)"
    fi
    printf '%s' "$s"
  }
  devmode_on() { reach "$DEVICE" && [ "$(devmode_state)" != disabled ]; }
  if [ "$(devmode_state)" = disabled ]; then
    todo "On the iPhone: Settings > Privacy & Security > Developer Mode (at the bottom) > On."
    todo "It restarts; after unlocking, tap Turn On and enter your passcode."
    say "Do not see Developer Mode? Keep the iPhone plugged in to this Mac for a minute and look again."
    wait_for "Developer Mode" devmode_on || needs_person "Developer Mode is off on your iPhone." \
      "Settings > Privacy & Security > Developer Mode > On."
  fi
  NAME="$(plutil -extract result.deviceProperties.name raw "$TMPJ/details.json" 2>/dev/null || echo "$DEVICE")"
  ok "$NAME"

  phone_field() { field "$SUPPORT/phone-install.env" "$1"; }
  app_on_phone() {
    xcrun devicectl device info apps --device "$DEVICE" --bundle-id "$BUNDLE_ID" --quiet \
      --json-output "$TMPJ/apps.json" >/dev/null 2>&1 \
      && [ "$(plutil -extract result.apps raw "$TMPJ/apps.json" 2>/dev/null || echo 0)" -gt 0 ]
  }
  if [ "${GLASSPAD_FORCE:-0}" != 1 ] && [ "$(phone_field GLASSPAD_REV)" = "$REV" ] \
     && [ "$(phone_field GLASSPAD_DEVICE)" = "$DEVICE" ] && [ "$(phone_field GLASSPAD_TEAM)" = "$TEAM" ] \
     && [ "$(phone_field GLASSPAD_REPO)" = "$PWD" ] && app_on_phone; then
    ok "Already installed (${REV:0:7}), nothing to do"
  else
    say "Building and installing (the first build takes a while)..."
    run_logged install-phone scripts/install-phone.sh "$DEVICE"
    ok "Installed ${REV:0:7}"
  fi

  # Opening the app is how we learn whether the iPhone trusts it yet.
  LAUNCH_OUT="$TMPJ/launch.txt"
  launch_state() {
    if xcrun devicectl device process launch --device "$DEVICE" "$BUNDLE_ID" >"$LAUNCH_OUT" 2>&1; then
      echo ok
    elif grep -qiE 'explicitly trusted|untrusted|not trusted|0xe8008018|invalid code signature' "$LAUNCH_OUT"; then
      echo untrusted
    elif grep -qiE 'locked|unlock|passcode' "$LAUNCH_OUT"; then
      echo locked
    elif grep -qiE 'not installed|-10814' "$LAUNCH_OUT"; then
      echo missing
    else
      echo other
    fi
  }
  shown=""
  start=$(date +%s)
  while :; do
    st="$(launch_state)"
    [ "$st" = ok ] && break
    if [ "$st" != "$shown" ]; then
      [ -n "$shown" ] && printf '\n'
      case "$st" in
        untrusted) todo "On the iPhone: Settings > General > VPN & Device Management > your Apple ID > Trust." ;;
        locked)    todo "Unlock your iPhone so the app can open." ;;
        missing)   fail "The app is not on the iPhone after installing." "Run the installer again with GLASSPAD_FORCE=1." ;;
        *)         todo "The app did not open on the iPhone. What it said:"
                   awk 'NF && n < 4 {print "      " $0; n++}' "$LAUNCH_OUT" ;;
      esac
      printf '  %swaiting' "$dim"; shown="$st"
    fi
    if [ "$LIMIT" -gt 0 ] && [ $(( $(date +%s) - start )) -ge "$LIMIT" ]; then
      printf ' gave up after %ss%s\n' "$LIMIT" "$reset"
      case "$st" in
        untrusted) needs_person "The iPhone does not trust the app yet." \
                     "Settings > General > VPN & Device Management > your Apple ID > Trust." ;;
        locked)    needs_person "Your iPhone is locked." "Unlock it." ;;
        *)         fail "The app did not open on the iPhone." "$(grep -v '^ *$' "$LAUNCH_OUT" | tail -n 1)" ;;
      esac
    fi
    printf '.'; sleep "$POLL"
  done
  [ -n "$shown" ] && printf ' done%s\n' "$reset"
  ok "Glasspad is open on your iPhone"
  note "iPhone" "$NAME ($DEVICE), ${REV:0:7}"
  PHONE_DONE=1
fi

# 7. Stay installed --------------------------------------------------------------------------
step "7. Automatic renewal"
if [ "$PHONE_DONE" = 1 ]; then
  run_logged setup-autorefresh scripts/setup-autorefresh.sh
  ok "$(head -n 1 "$LOGS/setup-autorefresh.log")"
  say "Free Apple accounts expire apps after 7 days. Your Mac now renews it over Wi-Fi by itself."
  note "Auto-renew" "on (checks hourly, log: ~/Library/Logs/Glasspad/refresh.log)"
else
  if [ -f "$HOME/Library/LaunchAgents/com.soham109.glasspad.refresh.plist" ]; then
    say "Left as it was (set up by an earlier run)."
    note "Auto-renew" "unchanged (set up by an earlier run)"
  else
    say "Skipped: it needs the iPhone install first."
    note "Auto-renew" "not set up (needs the iPhone install)"
  fi
fi

step "Done. What is installed:"
printf '%s' "$SUMMARY"
if [ "$PHONE_DONE" = 1 ]; then
  printf '\n'
  say "Pair: click the Glasspad icon in your Mac's menu bar > Pair new iPhone, then scan the code"
  say "with the Glasspad app (or the iPhone Camera)."
fi
}

main "$@"
