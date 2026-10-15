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

TEAM="${GLASSPAD_TEAM:-$(security find-certificate -c "Apple Development" -p 2>/dev/null \
  | openssl x509 -noout -subject 2>/dev/null | sed -n 's/.*OU=\([A-Z0-9]\{10\}\).*/\1/p')}"
[ -n "$TEAM" ] || { echo "No Apple team found. Sign in under Xcode > Settings > Apple Accounts, pick your team once in the project's Signing tab, then retry."; exit 1; }

DEVICE="${1:-$(xcrun devicectl list devices 2>/dev/null | awk '(/available \(paired\)/ || / connected /) && !/simulated/ {for(i=1;i<=NF;i++) if ($i ~ /^[0-9A-F]{8}-[0-9A-F]{16}$/) {print $i; exit}}')}"
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
    DEVELOPMENT_TEAM="$TEAM" -quiet build )
xcrun devicectl device install app --device "$DEVICE" "$DD/Build/Products/Debug-iphoneos/Glasspad.app" >/dev/null

mkdir -p "$STATE_DIR"
cat > "$STATE" <<EOF
GLASSPAD_REPO="$REPO"
GLASSPAD_DEVICE="$DEVICE"
GLASSPAD_TEAM="$TEAM"
GLASSPAD_REV="$REV"
GLASSPAD_INSTALLED_AT="$(date +%s)"
EOF
echo "Installed Glasspad ${REV:0:7} on $DEVICE"
