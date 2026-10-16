#!/usr/bin/env bash
# Build Glasspad and install it on your iPhone (USB or Wi-Fi). With a free Apple account the
# install lasts 7 days; run scripts/setup-autorefresh.sh once and your Mac renews it for you.
#
# Usage: scripts/install-phone.sh [device id]
#   GLASSPAD_TEAM  Apple team ID. Default: read from your "Apple Development" certificate.
#   GLASSPAD_REV   Git revision to build. Default: HEAD.
set -euo pipefail
cd "$(dirname "$0")/.."
REPO="$PWD"
STATE_DIR="${HOME}/Library/Application Support/Glasspad"
STATE="${STATE_DIR}/phone-install.env"
export PATH="$PATH:$STATE_DIR/bin:/opt/homebrew/bin:/usr/local/bin"

# iPhone builds need Xcode itself; use it even when xcode-select points at the command line tools.
if [ -z "${DEVELOPER_DIR:-}" ]; then
  case "$(xcode-select -p 2>/dev/null || true)" in
    *.app/Contents/Developer) ;;
    *) if [ -d /Applications/Xcode.app/Contents/Developer ]; then
         export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer; fi ;;
  esac
fi

TEAM="${GLASSPAD_TEAM:-$(security find-certificate -c "Apple Development" -p 2>/dev/null \
  | openssl x509 -noout -subject 2>/dev/null | sed -n 's/.*OU *= *\([A-Z0-9]\{10\}\).*/\1/p' || true)}"
[ -n "$TEAM" ] || { echo "No Apple team found. Sign in under Xcode > Settings > Apple Accounts, pick your team once in the project's Signing tab, then retry."; exit 1; }

if [ -n "${1:-}" ]; then DEVICE="$1"; else
  J="$(mktemp)"; DEVICE=""
  if xcrun devicectl list devices --quiet --json-output "$J" >/dev/null 2>&1; then
    i=0; n="$(plutil -extract result.devices raw "$J" 2>/dev/null || echo 0)"
    while [ "$i" -lt "$n" ] && [ -z "$DEVICE" ]; do
      x() { plutil -extract "result.devices.$i.$1" raw "$J" 2>/dev/null || true; }
      if [ "$(x hardwareProperties.reality)" = physical ] && [ "$(x hardwareProperties.platform)" = iOS ] \
         && [ "$(x connectionProperties.pairingState)" = paired ]; then DEVICE="$(x hardwareProperties.udid)"; fi
      i=$((i+1))
    done
  fi
  rm -f "$J"
fi
[ -n "$DEVICE" ] || { echo "No iPhone found. Unlock it and keep it on the same Wi-Fi as this Mac, or plug it in."; exit 1; }

REV="$(git rev-parse "${GLASSPAD_REV:-HEAD}")"

# Build from a clean copy outside iCloud Desktop so codesign and unfinished edits never interfere.
WT="${HOME}/Library/Caches/glasspad-phone"
git worktree remove --force "$WT" 2>/dev/null || rm -rf "$WT"
git worktree prune
git worktree add -q --detach "$WT" "$REV"
DD="${HOME}/Library/Caches/glasspad-dd-phone"
( cd "$WT" && xcodegen -q && xcodebuild -project Glasspad.xcodeproj -scheme "Glasspad iOS" \
    -destination "id=$DEVICE" -derivedDataPath "$DD" \
    -allowProvisioningUpdates -allowProvisioningDeviceRegistration \
    DEVELOPMENT_TEAM="$TEAM" -quiet build </dev/null )
xcrun devicectl device install app --device "$DEVICE" "$DD/Build/Products/Debug-iphoneos/Glasspad.app" >/dev/null

# %q keeps any path (spaces, quotes) safe to read back with `source`.
mkdir -p "$STATE_DIR"
{
  printf 'GLASSPAD_REPO=%q\n' "$REPO"
  printf 'GLASSPAD_DEVICE=%q\n' "$DEVICE"
  printf 'GLASSPAD_TEAM=%q\n' "$TEAM"
  printf 'GLASSPAD_REV=%q\n' "$REV"
  printf 'GLASSPAD_DEVELOPER_DIR=%q\n' "${DEVELOPER_DIR:-}"
  printf 'GLASSPAD_INSTALLED_AT=%q\n' "$(date +%s)"
} > "$STATE.tmp" && mv "$STATE.tmp" "$STATE"
echo "Installed Glasspad ${REV:0:7} on $DEVICE"
