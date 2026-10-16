#!/usr/bin/env bash
# Build the Mac app, install it to /Applications and sign it with your Apple Development
# certificate, so macOS keeps its Accessibility permission across updates. Restarts the app.
#   GLASSPAD_SIGN_IDENTITY  SHA-1 of the certificate to sign with (install.sh passes it).
#   GLASSPAD_TEAM           Otherwise: the first Apple Development certificate of this team.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
STATE_DIR="${HOME}/Library/Application Support/Glasspad"
scripts/build-mac.sh >/dev/null
APP=/Applications/Glasspad.app
pkill -f "$APP/Contents/MacOS/Glasspad" 2>/dev/null || true
rm -rf "$APP"
ditto build/Glasspad.app "$APP"
xattr -cr "$APP"

# The SHA-1 is unambiguous; a certificate name is not when two of them share it.
IDENTITY="${GLASSPAD_SIGN_IDENTITY:-}"
if [ -z "$IDENTITY" ]; then
  pems="$(security find-certificate -a -Z -p -c "Apple Development" 2>/dev/null || true)"
  for h in $(security find-identity -v -p codesigning 2>/dev/null \
               | sed -n 's/^ *[0-9]*) \([0-9A-F]\{40\}\) "Apple Development: .*/\1/p'); do
    [ -n "$IDENTITY" ] || IDENTITY="$h"
    [ -n "${GLASSPAD_TEAM:-}" ] || break
    team="$(printf '%s\n' "$pems" | awk -v h="$h" '/^SHA-1 hash:/ {on = ($3 == h)} on && /BEGIN CERT/ {p=1} p && on {print} /END CERT/ {p=0}' \
      | openssl x509 -noout -subject 2>/dev/null | sed -n 's/.*OU *= *\([A-Z0-9]\{10\}\).*/\1/p')" || true
    if [ "$team" = "$GLASSPAD_TEAM" ]; then IDENTITY="$h"; break; fi
  done
fi
SIGN=(--force --timestamp=none --options runtime -s "${IDENTITY:--}")
# Inner code first, then the app with its entitlements (Apple Events for Media mode).
for lib in "$APP"/Contents/Frameworks/*.dylib; do
  if [ -e "$lib" ]; then codesign "${SIGN[@]}" "$lib" 2>/dev/null; fi
done
codesign "${SIGN[@]}" --entitlements "$ROOT/Config/Mac/Glasspad.entitlements" "$APP" 2>/dev/null
codesign --verify --strict "$APP"
open "$APP"

# Lets install.sh skip this step next time when nothing changed.
mkdir -p "$STATE_DIR"
printf 'GLASSPAD_MAC_REV=%q\nGLASSPAD_MAC_INSTALLED_AT=%q\n' \
  "$(git rev-parse HEAD 2>/dev/null || true)" "$(date +%s)" > "$STATE_DIR/mac-install.env"
echo "Installed $APP (${IDENTITY:-ad-hoc})"
