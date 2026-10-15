#!/usr/bin/env bash
# Glasspad installer. One command sets up everything:
#   curl -fsSL https://raw.githubusercontent.com/Soham109/glasspad/main/install.sh | bash
#
# It does every step it can by itself and, where Apple requires a person (signing in, a tap on
# the iPhone), it tells you exactly what to click and waits until it sees that you have done it.
# Safe to run again at any time: finished steps are skipped.
set -euo pipefail

REPO_URL="https://github.com/Soham109/glasspad.git"
DEST="${GLASSPAD_HOME:-$HOME/Projects/glasspad}"
SUPPORT="$HOME/Library/Application Support/Glasspad"
BIN="$SUPPORT/bin"
XCODEGEN_VERSION="2.46.0"
export PATH="$BIN:/opt/homebrew/bin:/usr/local/bin:$PATH"

bold=$'\033[1m'; dim=$'\033[2m'; green=$'\033[32m'; reset=$'\033[0m'
step()  { printf '\n%s%s%s\n' "$bold" "$1" "$reset"; }
ok()    { printf '  %s✓%s %s\n' "$green" "$reset" "$1"; }
say()   { printf '  %s\n' "$1"; }
todo()  { printf '  %s→%s %s\n' "$bold" "$reset" "$1"; }
# Waits until a check command succeeds, printing a quiet heartbeat.
wait_for() { local what="$1"; shift; printf '  %swaiting: %s%s' "$dim" "$what" "$reset"
  until "$@" >/dev/null 2>&1; do printf '.'; sleep 3; done; printf '\n'; }
# Reads from the terminal even when this script is piped into bash.
pause() { printf '  %s(press Return when done)%s ' "$dim" "$reset"; read -r _ </dev/tty || true; }

[ "$(uname)" = "Darwin" ] || { echo "Glasspad needs a Mac."; exit 1; }

# 1. Xcode -----------------------------------------------------------------------------------
step "1. Xcode"
if [ ! -d /Applications/Xcode.app ]; then
  todo "Install Xcode from the App Store (free). Opening it for you."
  open "macappstore://apps.apple.com/app/id497799835" || true
  wait_for "Xcode to finish installing" test -x /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild
fi
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
if ! xcodebuild -checkFirstLaunchStatus >/dev/null 2>&1 || ! xcodebuild -version >/dev/null 2>&1; then
  todo "Xcode needs its one-time setup and license. Enter your Mac password if asked."
  sudo xcodebuild -license accept </dev/tty
  sudo xcodebuild -runFirstLaunch </dev/tty
fi
ok "Xcode $(xcodebuild -version | head -1 | awk '{print $2}')"

# 2. Build tools -----------------------------------------------------------------------------
step "2. Build tools"
if ! command -v xcodegen >/dev/null; then
  mkdir -p "$BIN"
  tmp="$(mktemp -d)"
  curl -fsSL -o "$tmp/xcodegen.zip" \
    "https://github.com/yonaskolb/XcodeGen/releases/download/${XCODEGEN_VERSION}/xcodegen.zip"
  unzip -q "$tmp/xcodegen.zip" -d "$tmp"
  rm -rf "$SUPPORT/xcodegen" && mv "$tmp/xcodegen" "$SUPPORT/xcodegen"
  ln -sf "$SUPPORT/xcodegen/bin/xcodegen" "$BIN/xcodegen"
  rm -rf "$tmp"
fi
ok "XcodeGen $(xcodegen --version 2>/dev/null | awk '{print $NF}')"

# 3. Source ----------------------------------------------------------------------------------
step "3. Glasspad source"
if [ -d "$DEST/.git" ]; then
  git -C "$DEST" pull -q --ff-only || say "Could not update (local changes?); using what is there."
else
  mkdir -p "$(dirname "$DEST")"
  git clone -q "$REPO_URL" "$DEST"
fi
ok "$DEST"
cd "$DEST"

# 4. Apple account -----------------------------------------------------------------------------
step "4. Your Apple account (free)"
team() { security find-certificate -c "Apple Development" -p 2>/dev/null \
  | openssl x509 -noout -subject 2>/dev/null | sed -n 's/.*OU=\([A-Z0-9]\{10\}\).*/\1/p'; }
if [ -z "$(team)" ]; then
  todo "In Xcode: Settings (Cmd+,) > Apple Accounts > + > sign in with your Apple ID."
  open -a Xcode
  pause
  xcodegen -q
  todo "Xcode is opening the Glasspad project. Click Glasspad (top of the left sidebar),"
  todo "then target 'Glasspad iOS' > Signing & Capabilities > Team > pick your name."
  open Glasspad.xcodeproj
  has_team() { [ -n "$(team)" ]; }
  wait_for "your signing certificate" has_team
fi
TEAM="$(team)"
ok "Team $TEAM"

# 5. Mac app ---------------------------------------------------------------------------------
step "5. Mac app"
scripts/install-mac.sh >/dev/null
ok "Installed in Applications and running in your menu bar"
todo "Allow Accessibility so Glasspad can move the pointer. Opening the right page:"
say  "System Settings > Privacy & Security > Accessibility > switch on Glasspad."
open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
pause

# 6. iPhone ----------------------------------------------------------------------------------
step "6. iPhone"
device() { xcrun devicectl list devices 2>/dev/null | awk '(/available \(paired\)/ || / connected /) && !/simulated/ \
  {for(i=1;i<=NF;i++) if ($i ~ /^[0-9A-F]{8}-[0-9A-F]{16}$/) {print $i; exit}}'; }
if [ -z "$(device)" ]; then
  todo "Plug your iPhone into this Mac with a cable, unlock it, and tap Trust."
  has_device() { [ -n "$(device)" ]; }
  wait_for "your iPhone" has_device
fi
DEVICE="$(device)"
devmode() { xcrun devicectl device info details --device "$DEVICE" 2>/dev/null | grep -q "Developer Mode Status: Enabled"; }
if ! devmode; then
  todo "On the iPhone: Settings > Privacy & Security > Developer Mode (at the bottom) > On."
  todo "It restarts; after unlocking, tap Turn On and enter your passcode."
  wait_for "Developer Mode" devmode
fi
ok "$(xcrun devicectl list devices 2>/dev/null | grep "$DEVICE" | awk -F'  +' '{print $1}')"
say "Building and installing (the first build takes a while)..."
GLASSPAD_TEAM="$TEAM" scripts/install-phone.sh "$DEVICE" | tail -1
launches() { xcrun devicectl device process launch --device "$DEVICE" com.soham109.glasspad.ios >/dev/null 2>&1; }
if ! launches; then
  todo "On the iPhone: Settings > General > VPN & Device Management > your Apple ID > Trust."
  wait_for "the app to be trusted" launches
fi
ok "Glasspad is open on your iPhone"

# 7. Stay installed --------------------------------------------------------------------------
step "7. Automatic renewal"
scripts/setup-autorefresh.sh | head -1 | sed 's/^/  /'
say "Free Apple accounts expire apps after 7 days. Your Mac now renews it over Wi-Fi by itself."

step "Done"
say "Pair: click the Glasspad icon in your Mac's menu bar > Pair new iPhone, then scan the code"
say "with the Glasspad app (or the iPhone Camera)."
