#!/usr/bin/env bash
# Build the Mac app, install it to /Applications and sign it with your Apple Development
# certificate, so macOS keeps its Accessibility permission across updates. Restarts the app.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
scripts/build-mac.sh >/dev/null
APP=/Applications/Glasspad.app
pkill -f "$APP/Contents/MacOS/Glasspad" 2>/dev/null || true
rm -rf "$APP"
ditto build/Glasspad.app "$APP"
xattr -cr "$APP"
IDENTITY="$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development/ {print $2; exit}')"
SIGN=(--force --timestamp=none --options runtime)
if [ -n "$IDENTITY" ]; then SIGN+=(-s "$IDENTITY"); else SIGN+=(-s -); fi
# Inner code first, then the app with its entitlements (Apple Events for Media mode).
for lib in "$APP"/Contents/Frameworks/*.dylib; do [ -e "$lib" ] && codesign "${SIGN[@]}" "$lib"; done
codesign "${SIGN[@]}" --entitlements "$ROOT/Config/Mac/Glasspad.entitlements" "$APP"
codesign --verify --strict "$APP"
open "$APP"
echo "Installed $APP (${IDENTITY:-ad-hoc})"
