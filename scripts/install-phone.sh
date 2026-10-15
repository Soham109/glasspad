#!/usr/bin/env bash
# Build Glasspad from the committed code and install it on a plugged-in (or Wi-Fi paired) iPhone.
# Re-run every 7 days with a free Apple account, or after any update.
# Usage: GLASSPAD_TEAM=<team id> scripts/install-phone.sh [device id]
set -euo pipefail
cd "$(dirname "$0")/.."
TEAM="${GLASSPAD_TEAM:?Set GLASSPAD_TEAM to your Apple team ID (Xcode > Settings > Apple Accounts)}"
DEVICE="${1:-$(xcrun devicectl list devices 2>/dev/null | awk '(/available \(paired\)/ || / connected /) && !/simulated/ {for(i=1;i<=NF;i++) if ($i ~ /^[0-9A-F]{8}-[0-9A-F]{16}$/) {print $i; exit}}')}"
[ -n "$DEVICE" ] || { echo "No iPhone found. Plug it in and unlock it."; exit 1; }
# Build from a clean copy outside iCloud Desktop so codesign and unfinished edits never interfere.
WT="${HOME}/Library/Caches/glasspad-phone"
git worktree remove --force "$WT" 2>/dev/null || true
git worktree add -q --detach "$WT" HEAD
DD="${HOME}/Library/Caches/glasspad-dd-phone"
( cd "$WT" && xcodegen -q && xcodebuild -project Glasspad.xcodeproj -scheme "Glasspad iOS" \
    -destination "id=$DEVICE" -derivedDataPath "$DD" \
    -allowProvisioningUpdates -allowProvisioningDeviceRegistration \
    DEVELOPMENT_TEAM="$TEAM" -quiet build )
xcrun devicectl device install app --device "$DEVICE" "$DD/Build/Products/Debug-iphoneos/Glasspad.app" >/dev/null
echo "Installed Glasspad on $DEVICE"
